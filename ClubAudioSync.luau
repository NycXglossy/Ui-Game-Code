--!strict
-- ClubAudioSync: shared audio sync for every club FX script.
-- The club's music is played by the ClubMusic modern audio backend, which
-- injects an AudioPlayer graph at runtime under SoundService. AudioPlayer
-- exposes IsPlaying and TimePosition but NO PlaybackLoudness, so this module
-- derives a live beat clock from TimePosition and simulates the energy
-- envelope that legacy Sound.PlaybackLoudness used to provide.
-- Works on both server and client (keep it in ReplicatedStorage).

local SoundService = game:GetService("SoundService")

local ClubAudioSync = {}

local ROOT_NAME = "ClubMusicModernAudio"

-- Adaptive BPM state. All published tempos are bounded to the supported
-- club-show range so every lighting system behaves consistently at 60–300 BPM.
-- Missing metadata retains the last known valid tempo; changes ease smoothly.
local BPM_MIN = 60
local BPM_MAX = 300
local BPM_SEED = 128
-- Optional per-asset BPM catalogue. Keys are the numeric Roblox audio asset IDs
-- as strings; add a verified tempo here when one is known. The asset ID itself
-- does not encode BPM, so unknown tracks deliberately retain last-known tempo.
local ASSET_BPM_BY_ID: {[string]: number} = {
	-- ["100919684616729"] = 124,
}
local bpmOverride: number? = nil -- pushed via ClubAudioSync.setBPM
local bpmTarget = BPM_SEED
local bpmCurrent = BPM_SEED
local bpmLastKnown = BPM_SEED

-- One shared movement-speed envelope consumed by every Club Neon FX animator.
local MOVEMENT_SPEED_MIN = 0.55
local MOVEMENT_SPEED_MAX = 1.45
local movementSpeedCurrent = 1
local lastPlaying: boolean? = nil

local function sanitizeBPM(value: any): number?
	if typeof(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then return nil end
	return math.clamp(value, BPM_MIN, BPM_MAX)
end

local audioPlayer: AudioPlayer? = nil
local lastBeatPlayer: AudioPlayer? = nil
local lastBeatAssetId: string? = nil
local lastScan = 0

-- Live beat-clock state (updated lazily whenever getBeatState is called)
local lastT = os.clock()
local lastBeatIndex = -1
local beatCount = 0
local pulse = 0 -- 1 on the kick, decays fast
local energy = 0 -- smoothed 0..1 envelope, the PlaybackLoudness substitute

local function hash01(n: number): number
	return (math.sin(n * 12.9898) * 43758.5453) % 1
end

local function backendRootFor(player: AudioPlayer?): Instance?
	local root = player and player.Parent
	if root and root:GetAttribute("ManagedByClubMusicAudioBackend") == true then
		return root
	end
	return nil
end

local function scanForAudioPlayer(): AudioPlayer?
	local root = SoundService:FindFirstChild(ROOT_NAME)
	if root and root:GetAttribute("ManagedByClubMusicAudioBackend") == true then
		local player = root:FindFirstChildOfClass("AudioPlayer")
		if player then
			return player
		end
	end
	-- Fallback: the backend may be named differently; any AudioPlayer whose
	-- parent is flagged as backend-managed is the club deck.
	for _, descendant in SoundService:GetDescendants() do
		if descendant:IsA("AudioPlayer") and backendRootFor(descendant) then
			return descendant
		end
	end
	return nil
end

-- Rescans at most once per second until the runtime-created graph appears.
function ClubAudioSync.getAudioPlayer(): AudioPlayer?
	if audioPlayer == nil or audioPlayer.Parent == nil then
		local now = os.clock()
		if now - lastScan >= 1 then
			lastScan = now
			audioPlayer = scanForAudioPlayer()
		end
	end
	return audioPlayer
end

local function getActiveAssetId(player: AudioPlayer?): string?
	if not player then return nil end
	local asset = ""
	pcall(function() asset = player.Asset end)
	local id = if typeof(asset) == "string" then string.match(asset, "^rbxassetid://(%d+)$") else nil
	if not id then
		local attribute = player:GetAttribute("ClubMusicAssetId")
		if typeof(attribute) == "number" and attribute > 0 and attribute % 1 == 0 then
			id = string.format("%.0f", attribute)
		elseif typeof(attribute) == "string" and string.match(attribute, "^%d+$") then
			id = attribute
		end
	end
	return id
end

local function resolveAssetBPM(player: AudioPlayer?, root: Instance?, assetId: string?): number?
	if not player or not assetId then return nil end
	local catalogBPM = sanitizeBPM(ASSET_BPM_BY_ID[assetId])
	if catalogBPM then return catalogBPM end
	-- Prefer explicitly asset-keyed metadata so a previous song's tempo cannot
	-- be mistaken for the newly selected AudioPlayer asset.
	for _, key in ipairs({"BPM_" .. assetId, "ClubMusicBPM_" .. assetId}) do
		local value = sanitizeBPM(player:GetAttribute(key))
		if value then return value end
	end
	if root then
		for _, key in ipairs({"ClubMusicBPM_" .. assetId, "BPM_" .. assetId}) do
			local value = sanitizeBPM(root:GetAttribute(key))
			if value then return value end
		end
	end
	local playerBPMAsset = player:GetAttribute("BPMAssetId")
	local playerBPMAssetText = if typeof(playerBPMAsset) == "number"
		then string.format("%.0f", playerBPMAsset) else tostring(playerBPMAsset or "")
	if playerBPMAssetText == assetId then
		local value = sanitizeBPM(player:GetAttribute("BPM"))
		if value then return value end
	end
	if root then
		local rootBPMAsset = root:GetAttribute("ClubMusicBPMAssetId")
		local rootBPMAssetText = if typeof(rootBPMAsset) == "number"
			then string.format("%.0f", rootBPMAsset) else tostring(rootBPMAsset or "")
		if rootBPMAssetText == assetId then
			local value = sanitizeBPM(root:GetAttribute("ClubMusicBPM"))
			if value then return value end
			value = sanitizeBPM(root:GetAttribute("BPM"))
			if value then return value end
		end
	end
	return nil
end

local function resolveBPMTarget()
	local target = bpmOverride
	local player = ClubAudioSync.getAudioPlayer()
	local root = backendRootFor(player)
	local assetId = getActiveAssetId(player)
	if sanitizeBPM(target) == nil then
		target = resolveAssetBPM(player, root, assetId)
	end
	local validTarget = sanitizeBPM(target)
	if validTarget ~= nil then
		bpmLastKnown = validTarget
		bpmTarget = validTarget
	else
		-- An asset ID alone does not expose musical tempo. Keep the last
		-- verified BPM until metadata matching the active asset is available.
		bpmTarget = bpmLastKnown
	end
end

function ClubAudioSync.getBPM(): number
	resolveBPMTarget()
	return bpmCurrent
end

-- Push the tempo from outside (e.g. the audio backend or an admin tool).
-- Values are clamped to the supported 60–300 BPM range. Pass nil to clear.
function ClubAudioSync.setBPM(bpm: number?)
	bpmOverride = sanitizeBPM(bpm)
end

export type BeatState = {
	playing: boolean,
	assetId: string,
	timePosition: number,
	bpm: number,
	beatIndex: number, -- beats elapsed in the current track
	beatCount: number, -- beats since this module started syncing (hue/pattern cycling)
	beatPhase: number, -- 0..1 position inside the current beat
	barPhase: number, -- 0..1 position inside the current 4-beat bar
	pulse: number, -- 1 on the kick, exponential decay
	energy: number, -- smoothed 0..1 simulated loudness envelope
	movementSpeed: number, -- shared smoothed movement multiplier, adapted primarily to BPM
}

-- Call every frame (or whenever fresh beat data is needed). Advances the
-- internal clock from real elapsed time, so it is safe to call from any
-- number of scripts without double-stepping.
function ClubAudioSync.getBeatState(): BeatState
	local now = os.clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now

	local player = ClubAudioSync.getAudioPlayer()
	if player ~= lastBeatPlayer then
		lastBeatPlayer = player
		lastBeatAssetId = nil
		lastBeatIndex = -1
	end
	local assetId = getActiveAssetId(player)
	if assetId ~= lastBeatAssetId then
		lastBeatAssetId = assetId
		lastBeatIndex = -1
	end
	local playing = player ~= nil and player.IsPlaying
	local timePosition = if playing then player.TimePosition else 0
	if lastPlaying ~= playing then
		lastPlaying = playing
		lastBeatIndex = -1
	end

	resolveBPMTarget()
	-- Ease toward the target tempo so track changes adapt the beat clock
	-- smoothly instead of snapping (converges in roughly a second).
	bpmCurrent += (bpmTarget - bpmCurrent) * (1 - math.exp(-4 * dt))
	local bpm = bpmCurrent

	-- Music follows AudioPlayer.TimePosition. When stopped, a quiet tempo clock
	-- keeps ambient lighting alive at the last known BPM instead of freezing.
	local beats = (if playing then timePosition else now) * bpm / 60
	local beatIndex = math.floor(beats)
	if beatIndex ~= lastBeatIndex then
		-- Track rewinds and play/stop transitions start a fresh beat segment.
		if lastBeatIndex >= 0 and beatIndex > lastBeatIndex then
			beatCount += beatIndex - lastBeatIndex
		else
			beatCount += 1
		end
		lastBeatIndex = beatIndex
		pulse = 1
	end

	local beatPhase = beats % 1
	pulse = math.exp(-beatPhase * 5)

	-- Simulated envelope: per-beat variety from a deterministic hash so EQ
	-- bars breathe differently each beat, plus the kick pulse on top.
	local beatVariety = 0.25 + 0.5 * hash01(beatCount)
	local targetEnergy = if playing then math.clamp(0.3 + 0.4 * pulse + 0.3 * beatVariety, 0, 1) else 0
	energy += (targetEnergy - energy) * (1 - math.exp(-10 * dt))

	-- Centralize the movement response so all FX use the same tempo adaptation.
	-- BPM drives the response; the simulated energy envelope adds only a subtle lift.
	local tempoDrive = math.clamp((bpm - 70) / 90, 0, 1)
	local energyDrive = math.clamp(energy, 0, 1)
	local targetMovementSpeed = math.clamp(0.58 + tempoDrive * 0.68 + energyDrive * 0.18,
		MOVEMENT_SPEED_MIN, MOVEMENT_SPEED_MAX)
	movementSpeedCurrent += (targetMovementSpeed - movementSpeedCurrent) * (1 - math.exp(-1.8 * dt))

	return {
		playing = playing,
		assetId = assetId or "",
		timePosition = timePosition,
		bpm = bpm,
		beatIndex = math.floor(beats),
		beatCount = beatCount,
		beatPhase = beatPhase,
		barPhase = (math.floor(beats) % 4) / 4,
		pulse = pulse,
		energy = energy,
		movementSpeed = movementSpeedCurrent,
	}
end

return ClubAudioSync