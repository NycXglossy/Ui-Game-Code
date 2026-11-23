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
local bpmOverride: number? = nil -- pushed via ClubAudioSync.setBPM
local bpmTarget = BPM_SEED
local bpmCurrent = BPM_SEED
local bpmLastKnown = BPM_SEED
local lastPlaying: boolean? = nil

local function sanitizeBPM(value: any): number?
	if typeof(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then return nil end
	return math.clamp(value, BPM_MIN, BPM_MAX)
end

local audioPlayer: AudioPlayer? = nil
local lastBeatPlayer: AudioPlayer? = nil
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

local function resolveBPMTarget()
	local target = bpmOverride
	local player = ClubAudioSync.getAudioPlayer()
	if sanitizeBPM(target) == nil then
		-- Per-track tempo published directly on the AudioPlayer wins first.
		target = player and player:GetAttribute("BPM")
	end
	if sanitizeBPM(target) == nil then
		local root = backendRootFor(player)
		if root then
			target = root:GetAttribute("ClubMusicBPM")
			if sanitizeBPM(target) == nil then
				target = root:GetAttribute("BPM")
			end
		end
	end
	local validTarget = sanitizeBPM(target)
	if validTarget ~= nil then
		bpmLastKnown = validTarget
		bpmTarget = validTarget
	else
		-- No metadata right now: keep grooving at the last known tempo.
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
	timePosition: number,
	bpm: number,
	beatIndex: number, -- beats elapsed in the current track
	beatCount: number, -- beats since this module started syncing (hue/pattern cycling)
	beatPhase: number, -- 0..1 position inside the current beat
	barPhase: number, -- 0..1 position inside the current 4-beat bar
	pulse: number, -- 1 on the kick, exponential decay
	energy: number, -- smoothed 0..1 simulated loudness envelope
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

	return {
		playing = playing,
		timePosition = timePosition,
		bpm = bpm,
		beatIndex = math.floor(beats),
		beatCount = beatCount,
		beatPhase = beatPhase,
		barPhase = (math.floor(beats) % 4) / 4,
		pulse = pulse,
		energy = energy,
	}
end

return ClubAudioSync