--!strict
-- ClubAudioSync: one client-local live audio analyzer and beat clock for all Club Neon FX.
-- AudioAnalyzer is deliberately a parallel tap from AudioPlayer: it never sits
-- in the audible output chain and therefore cannot alter playback or volume.
-- Roblox returns zero/empty analyzer measurements on the server, so this module
-- is consumed by the client-side MovingHeadShowFX and LaserShowFX scripts only.

local SoundService = game:GetService("SoundService")

local ClubAudioSync = {}

local ROOT_NAME = "ClubMusicModernAudio"
local BPM_MIN = 70
local BPM_MAX = 190
local BPM_SEED = 120
local SAMPLE_RATE = 40
local HISTORY_SECONDS = 12
local HISTORY_LIMIT = SAMPLE_RATE * HISTORY_SECONDS
local ANALYZE_INTERVAL = 0.025
local MOVEMENT_SPEED_MIN = 0.55
local MOVEMENT_SPEED_MAX = 1.45

local audioPlayer: AudioPlayer? = nil
local analyzer: AudioAnalyzer? = nil
local analyzerWire: Wire? = nil
local lastScan = 0
local lastPlayer: AudioPlayer? = nil
local lastAssetId = ""
local lastSampleAt = 0
local sampleAccumulator = 0
local previousSpectrum: {number}? = nil
local previousRms = 0
local envelopeHistory: {number} = {}
local bpmCurrent = BPM_SEED
local bpmDetected: number? = nil
local bpmConfidence = 0
local lastTempoUpdate = 0
local TEMPO_STALE_SECONDS = 5
local energy = 0
local movementSpeedCurrent = 1
local lastT = os.clock()
local lastBeatIndex = -1
local beatCount = 0
local lastPlaying: boolean? = nil
-- Three-point onset peak tracking and a lightweight beat phase-locked loop.
local fluxOlder = 0
local fluxPrevious = 0
local fluxPreviousPosition = 0
local lastOnsetPosition = -math.huge
local beatAnchorPosition = 0
local beatAnchorReady = false
local fallbackAnchorReady = false
local onsetStrength = 0
local phaseLockConfidence = 0
local lastDiagnosticsAt = 0

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
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
		if player then return player end
	end
	for _, descendant in SoundService:GetDescendants() do
		if descendant:IsA("AudioPlayer") and backendRootFor(descendant) then
			return descendant
		end
	end
	return nil
end

local function clearAnalysis()
	previousSpectrum = nil
	previousRms = 0
	envelopeHistory = {}
	bpmDetected = nil
	bpmConfidence = 0
	lastTempoUpdate = 0
	energy = 0
	sampleAccumulator = 0
	lastSampleAt = 0
	lastBeatIndex = -1
	fluxOlder = 0
	fluxPrevious = 0
	fluxPreviousPosition = 0
	lastOnsetPosition = -math.huge
	beatAnchorPosition = 0
	beatAnchorReady = false
	fallbackAnchorReady = false
	onsetStrength = 0
	phaseLockConfidence = 0
end

local function ensureAnalyzer(player: AudioPlayer?)
	if player == lastPlayer and analyzer and analyzer.Parent and analyzerWire and analyzerWire.Parent then
		return
	end
	if analyzerWire then pcall(function() analyzerWire:Destroy() end) end
	if analyzer then pcall(function() analyzer:Destroy() end) end
	analyzerWire = nil
	analyzer = nil
	lastPlayer = player
	clearAnalysis()
	if not player then return end

	local root = backendRootFor(player)
	if not root then return end
	local ok, result = pcall(function()
		local liveAnalyzer = Instance.new("AudioAnalyzer")
		liveAnalyzer.Name = "ClubNeonLiveAudioAnalyzer"
		liveAnalyzer.SpectrumEnabled = true
		liveAnalyzer.Parent = root

		local wire = Instance.new("Wire")
		wire.Name = "ClubNeonAnalyzerTap"
		wire.SourceInstance = player
		wire.SourceName = "Output"
		wire.TargetInstance = liveAnalyzer
		wire.TargetName = "Input"
		wire.Parent = root
		return {liveAnalyzer, wire}
	end)
	if ok and result then
		analyzer = result[1] :: AudioAnalyzer
		analyzerWire = result[2] :: Wire
	else
		warn("[ClubAudioSync] Live AudioAnalyzer route unavailable: " .. tostring(result))
	end
end

local function getActiveAssetId(player: AudioPlayer?): string
	if not player then return "" end
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
	return id or ""
end

local function pushHistory(value: number)
	table.insert(envelopeHistory, value)
	if #envelopeHistory > HISTORY_LIMIT then table.remove(envelopeHistory, 1) end
end

-- Autocorrelation of measured bass-band spectral flux. The strongest periodic
-- lag across a rolling 12-second window estimates tempo from the audio itself.
local function estimateTempo(): (number?, number)
	local count = #envelopeHistory
	if count < SAMPLE_RATE * 7 then return nil, 0 end
	local mean = 0
	for _, value in ipairs(envelopeHistory) do mean += value end
	mean /= count
	local centered = table.create(count)
	local variance = 0
	for i, value in ipairs(envelopeHistory) do
		local v = value - mean
		centered[i] = v
		variance += v * v
	end
	if variance < 0.00001 then return nil, 0 end

	local bestLag, bestScore = 0, -math.huge
	local minLag = math.floor(60 / BPM_MAX * SAMPLE_RATE)
	local maxLag = math.ceil(60 / BPM_MIN * SAMPLE_RATE)
	for lag = minLag, maxLag do
		local score, normA, normB = 0, 0, 0
		for i = lag + 1, count do
			local a, b = centered[i], centered[i - lag]
			score += a * b
			normA += a * a
			normB += b * b
		end
		local normalized = score / math.sqrt(math.max(1e-9, normA * normB))
		-- Slight preference for the normal club tempo range reduces octave errors.
		local candidateBPM = 60 * SAMPLE_RATE / lag
		local preference = if candidateBPM >= 95 and candidateBPM <= 160 then 0.025 else 0
		normalized += preference
		if normalized > bestScore then
			bestScore = normalized
			bestLag = lag
		end
	end
	if bestLag == 0 then return nil, 0 end
	-- Parabolic interpolation around the winning autocorrelation lag reduces
	-- quantization error between integer sample offsets.
	local refinedLag = bestLag
	if bestLag > minLag and bestLag < maxLag then
		local function correlationAt(lag)
			local score, normA, normB = 0, 0, 0
			for i = lag + 1, count do
				local a, b = centered[i], centered[i - lag]
				score += a * b
				normA += a * a
				normB += b * b
			end
			return score / math.sqrt(math.max(1e-9, normA * normB))
		end
		local left, center, right = correlationAt(bestLag - 1), correlationAt(bestLag), correlationAt(bestLag + 1)
		local denominator = left - 2 * center + right
		if math.abs(denominator) > 1e-6 then
			refinedLag += math.clamp(0.5 * (left - right) / denominator, -0.5, 0.5)
		end
	end
	local bpm = math.clamp(60 * SAMPLE_RATE / refinedLag, BPM_MIN, BPM_MAX)
	local confidence = math.clamp((bestScore - 0.08) / 0.52, 0, 1)
	if confidence < 0.16 then return nil, confidence end
	return bpm, confidence
end

local function sampleAnalyzer(dt: number, timePosition: number)
	if not analyzer or not analyzer.Parent then return end
	sampleAccumulator += dt
	if sampleAccumulator < ANALYZE_INTERVAL then return end
	sampleAccumulator %= ANALYZE_INTERVAL

	local ok, rms = pcall(function() return analyzer.RmsLevel end)
	if not ok or not finite(rms) then return end
	local spectrumOk, spectrum = pcall(function() return analyzer:GetSpectrum() end)
	if not spectrumOk or typeof(spectrum) ~= "table" or #spectrum < 8 then
		energy += (math.clamp(rms, 0, 1) - energy) * 0.25
		return
	end

	-- Separate bass, low-mid and upper transient energy. Bass gets the
	-- strongest weight for kick detection, while upper bands retain snare/clap
	-- information so the tempo estimator does not depend on bass-only tracks.
	local bassFlux, lowMidFlux, upperFlux = 0, 0, 0
	local lastBin = math.min(#spectrum, 48)
	for i = 2, lastBin do
		local current = if finite(spectrum[i]) then math.max(0, spectrum[i]) else 0
		local previous = previousSpectrum and previousSpectrum[i] or 0
		local rise = math.max(0, current - previous)
		if i <= 9 then
			bassFlux += rise
		elseif i <= 24 then
			lowMidFlux += rise
		else
			upperFlux += rise
		end
	end
	local rmsRise = math.max(0, rms - previousRms)
	previousSpectrum = table.clone(spectrum)
	previousRms = rms

	-- Normalize bands independently to avoid a loud midrange dominating the
	-- onset stream. A small RMS-rise term preserves kick transients.
	local flux = bassFlux * 1.0 + lowMidFlux * 0.62 + upperFlux * 0.34
	local rawOnset = flux * 0.78 + rmsRise * 0.22
	local smoothedOnset = rawOnset
	if #envelopeHistory > 0 then
		smoothedOnset = envelopeHistory[#envelopeHistory] * 0.32 + rawOnset * 0.68
	end
	pushHistory(smoothedOnset)
	energy += (math.clamp(rms * 5, 0, 1) - energy) * 0.20

	-- Use a rolling adaptive threshold, rather than a fixed amplitude. This
	-- allows quieter mastered tracks and louder drops to share one detector.
	local n = math.min(#envelopeHistory, SAMPLE_RATE * 3)
	local mean, variance = 0, 0
	for i = #envelopeHistory - n + 1, #envelopeHistory do
		mean += envelopeHistory[i]
	end
	if n > 0 then mean /= n end
	for i = #envelopeHistory - n + 1, #envelopeHistory do
		local delta = envelopeHistory[i] - mean
		variance += delta * delta
	end
	local deviation = if n > 1 then math.sqrt(variance / (n - 1)) else 0
	local threshold = mean + deviation * 0.72

	-- Confirm a peak one sample late (three-point peak detector) to avoid
	-- locking the beat clock to every rising sample in a sustained sound.
	local peak = fluxPrevious
	local peakPosition = fluxPreviousPosition
	if fluxPrevious > fluxOlder and fluxPrevious >= smoothedOnset
		and peak > threshold and peakPosition - lastOnsetPosition >= 0.22 then
		lastOnsetPosition = peakPosition
		onsetStrength = math.clamp((peak - mean) / math.max(deviation * 3, 1e-5), 0, 1)

		local bpm = bpmDetected or bpmCurrent
		local period = 60 / math.clamp(bpm, BPM_MIN, BPM_MAX)
		if not beatAnchorReady then
			beatAnchorPosition = peakPosition
			beatAnchorReady = true
			phaseLockConfidence = 0.25
		else
			-- Find the nearest predicted beat and gently correct phase. Ignore
			-- off-beat percussion instead of allowing it to drag the whole show.
			local beatsFromAnchor = (peakPosition - beatAnchorPosition) / period
			local phaseError = beatsFromAnchor - math.floor(beatsFromAnchor + 0.5)
			local errorSeconds = phaseError * period
			if math.abs(errorSeconds) <= period * 0.22 then
				local gain = 0.12 + 0.20 * math.clamp(bpmConfidence, 0, 1)
				beatAnchorPosition += errorSeconds * gain
				phaseLockConfidence += (1 - phaseLockConfidence) * 0.12
			else
				phaseLockConfidence *= 0.96
			end
		end
	end
	fluxOlder = fluxPrevious
	fluxPrevious = smoothedOnset
	fluxPreviousPosition = timePosition

	local detected, confidence = estimateTempo()
	if detected then
		-- Confidence-weighted adaptation, with a tighter clamp to prevent
		-- octave errors and momentary fills from abruptly changing tempo.
		if bpmDetected then
			local maxStep = bpmCurrent * 0.035
			detected = math.clamp(detected, bpmDetected - maxStep, bpmDetected + maxStep)
		end
		local blend = math.clamp(0.08 + confidence * 0.22, 0.08, 0.30)
		bpmDetected = if bpmDetected then bpmDetected + (detected - bpmDetected) * blend else detected
		bpmConfidence += (confidence - bpmConfidence) * 0.18
		lastTempoUpdate = os.clock()
	end
end

function ClubAudioSync.getAudioPlayer(): AudioPlayer?
	if audioPlayer == nil or audioPlayer.Parent == nil then
		local now = os.clock()
		if now - lastScan >= 0.5 then
			lastScan = now
			audioPlayer = scanForAudioPlayer()
		end
	end
	-- Retry analyzer construction if the replicated audio graph appeared before
	-- its AudioPlayer/Wire pins were ready on this client.
	if audioPlayer and (lastPlayer ~= audioPlayer or analyzer == nil or analyzer.Parent == nil
		or analyzerWire == nil or analyzerWire.Parent == nil) then
		ensureAnalyzer(audioPlayer)
	end
	return audioPlayer
end

export type BeatState = {
	playing: boolean,
	assetId: string,
	timePosition: number,
	bpm: number,
	bpmConfidence: number,
	bpmSource: string,
	beatIndex: number,
	beatCount: number,
	beatPhase: number,
	barPhase: number,
	pulse: number,
	energy: number,
	movementSpeed: number,
	phaseLocked: boolean,
	onsetStrength: number,
}

function ClubAudioSync.getBeatState(): BeatState
	local now = os.clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now

	local player = ClubAudioSync.getAudioPlayer()
	if player ~= lastPlayer then ensureAnalyzer(player) end
	local assetId = getActiveAssetId(player)
	if assetId ~= lastAssetId then
		lastAssetId = assetId
		clearAnalysis()
	end

	local playing = player ~= nil and player.IsPlaying
	local timePosition = if playing and player then player.TimePosition else 0
	if lastPlaying ~= playing then
		lastPlaying = playing
		lastBeatIndex = -1
	end
	if playing then sampleAnalyzer(dt, timePosition) end

	if bpmDetected and lastTempoUpdate > 0 and now - lastTempoUpdate > TEMPO_STALE_SECONDS then
		bpmDetected = nil
		bpmConfidence = 0
		phaseLockConfidence *= 0.8
	end
	local targetBPM = bpmDetected or BPM_SEED
	bpmCurrent += (targetBPM - bpmCurrent) * (1 - math.exp(-1.8 * dt))
	local bpm = bpmCurrent

	-- Analyzer onset peaks now correct the phase of the playback-time clock.
	-- This preserves smooth AudioPlayer timing while preventing BPM-only drift.
	local period = 60 / bpm
	local beatPosition = if playing then timePosition else now
	if not beatAnchorReady and (not playing or not analyzer or not analyzer.Parent) then
		if not fallbackAnchorReady then
			beatAnchorPosition = beatPosition
			fallbackAnchorReady = true
		end
	end
	local beats = (beatPosition - beatAnchorPosition) / period
	local beatIndex = math.floor(beats)
	if beatIndex ~= lastBeatIndex then
		if lastBeatIndex >= 0 and beatIndex > lastBeatIndex then
			beatCount += math.min(beatIndex - lastBeatIndex, 8)
		else
			beatCount += 1
		end
		lastBeatIndex = beatIndex
	end
	local beatPhase = beats % 1
	local pulse = math.exp(-beatPhase * 5)
	if playing and now - lastDiagnosticsAt >= 5 then
		lastDiagnosticsAt = now
		print(string.format(
			"[ClubAudioSync][Analyzer] BPM=%.1f confidence=%.2f phaseLocked=%s onset=%.2f energy=%.2f analyzerReady=%s",
			bpm, bpmConfidence, tostring(phaseLockConfidence >= 0.35), onsetStrength,
			energy, tostring(analyzer ~= nil and analyzer.Parent ~= nil)
		))
	end
	local tempoDrive = math.clamp((bpm - 70) / 90, 0, 1)
	local targetMovementSpeed = math.clamp(0.58 + tempoDrive * 0.68 + energy * 0.18,
		MOVEMENT_SPEED_MIN, MOVEMENT_SPEED_MAX)
	movementSpeedCurrent += (targetMovementSpeed - movementSpeedCurrent) * (1 - math.exp(-1.8 * dt))

	return {
		playing = playing,
		assetId = assetId,
		timePosition = timePosition,
		bpm = bpm,
		bpmConfidence = bpmConfidence,
		bpmSource = if bpmDetected then "AudioAnalyzer+OnsetPLL" else "Analyzer warming up",
		beatIndex = beatIndex,
		beatCount = beatCount,
		beatPhase = beatPhase,
		barPhase = (beatIndex % 4) / 4,
		pulse = pulse,
		energy = energy,
		movementSpeed = movementSpeedCurrent,
		phaseLocked = phaseLockConfidence >= 0.35,
		onsetStrength = onsetStrength,
	}
end

return ClubAudioSync
