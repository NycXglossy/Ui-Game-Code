--!strict
-- ClubAudioSync: one client-local live audio analyzer and beat clock for all Club Neon FX.
-- AudioAnalyzer is deliberately a parallel tap from AudioPlayer: it never sits
-- in the audible output chain and therefore cannot alter playback or volume.
-- Roblox returns zero/empty analyzer measurements on the server, so this module
-- is consumed by the client-side MovingHeadShowFX and LaserShowFX scripts only.

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local ClubAudioSync = {}

local ROOT_NAME = "ClubMusicModernAudio"
local BPM_MIN = 55
local BPM_MAX = 240
local BPM_SEED = 120
local SAMPLE_RATE = 40
local HISTORY_SECONDS = 8
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
local trackGeneration = 0
local lastSampleAt = 0
local sampleAccumulator = 0
local previousSpectrum: {number}? = nil
local previousRms = 0
local envelopeHistory: {number} = {}
-- Independent spectral-band onset histories. These are frequency regions,
-- not semantic instrument detectors: AudioAnalyzer exposes a mixed spectrum.
local bandHistories: {[string]: {number}} = {
	bass = {},
	lowMid = {},
	presence = {},
	high = {},
}
local bpmCurrent = BPM_SEED
local bpmDetected: number? = nil
local bpmConfidence = 0
local rawCandidateBPM: number? = nil
local pendingBPM: number? = nil
local pendingTempoSamples = 0
local pendingTempoConfidence = 0
local lastTempoUpdate = 0
local lastTempoAnalysisAt = 0
local TEMPO_ANALYZE_INTERVAL = 0.10
local TEMPO_STALE_SECONDS = 12
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
local phaseErrorSeconds = 0
local lastAcceptedOnsetPosition = -math.huge
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
	bandHistories = {bass = {}, lowMid = {}, presence = {}, high = {}}
	bpmDetected = nil
	bpmCurrent = BPM_SEED
	bpmConfidence = 0
	rawCandidateBPM = nil
	pendingBPM = nil
	pendingTempoSamples = 0
	pendingTempoConfidence = 0
	lastTempoUpdate = 0
	lastTempoAnalysisAt = 0
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
	phaseErrorSeconds = 0
	lastAcceptedOnsetPosition = -math.huge
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
		liveAnalyzer.WindowSize = Enum.AudioWindowSize.Medium
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

local function pushBoundedHistory(history: {number}, value: number)
	table.insert(history, value)
	if #history > HISTORY_LIMIT then table.remove(history, 1) end
end

local function pushHistory(value: number, bands: {[string]: number})
	pushBoundedHistory(envelopeHistory, value)
	pushBoundedHistory(bandHistories.bass, bands.bass)
	pushBoundedHistory(bandHistories.lowMid, bands.lowMid)
	pushBoundedHistory(bandHistories.presence, bands.presence)
	pushBoundedHistory(bandHistories.high, bands.high)
end

-- Fuse independent autocorrelation evidence from frequency regions. No
-- region is treated as a named instrument; bass, synths, guitars and percussion
-- can all occupy overlapping frequency ranges in a mixed master.
local function estimateTempoWindow(windowSeconds: number): (number?, number)
	local analysisSamples = math.min(#envelopeHistory, SAMPLE_RATE * windowSeconds)
	if analysisSamples < SAMPLE_RATE * 3.5 then return nil, 0 end

	local channels = {
		{history = envelopeHistory, weight = 0.10},
		{history = bandHistories.bass, weight = 0.36},
		{history = bandHistories.lowMid, weight = 0.28},
		{history = bandHistories.presence, weight = 0.18},
		{history = bandHistories.high, weight = 0.08},
	}
	local activeChannels = {}
	local totalWeight = 0
	for _, channel in ipairs(channels) do
		local history = channel.history
		if #history >= analysisSamples then
			local firstIndex = #history - analysisSamples + 1
			local mean = 0
			for i = firstIndex, #history do mean += history[i] end
			mean /= analysisSamples
			local centered = table.create(analysisSamples)
			local variance = 0
			for i = firstIndex, #history do
				local value = history[i] - mean
				centered[i - firstIndex + 1] = value
				variance += value * value
			end
			if variance > 0.00001 then
				table.insert(activeChannels, {centered = centered, weight = channel.weight})
				totalWeight += channel.weight
			end
		end
	end
	if #activeChannels == 0 or totalWeight <= 0 then return nil, 0 end

	local minLag = math.floor(60 / BPM_MAX * SAMPLE_RATE)
	local maxLag = math.ceil(60 / BPM_MIN * SAMPLE_RATE)
	local combinedScores: {[number]: number} = {}
	local bestLag, bestScore = 0, -math.huge
	local secondScore = -math.huge
	for lag = minLag, maxLag do
		local weightedScore = 0
		for _, channel in ipairs(activeChannels) do
			local centered = channel.centered
			local score, normA, normB = 0, 0, 0
			for i = lag + 1, analysisSamples do
				local a, b = centered[i], centered[i - lag]
				score += a * b
				normA += a * a
				normB += b * b
			end
			local normalized = score / math.sqrt(math.max(1e-9, normA * normB))
			weightedScore += normalized * channel.weight
		end
		local combined = weightedScore / totalWeight
		combinedScores[lag] = combined
		if combined > bestScore then
			secondScore = bestScore
			bestScore = combined
			bestLag = lag
		elseif math.abs(lag - bestLag) > 2 and combined > secondScore then
			secondScore = combined
		end
	end
	if bestLag == 0 then return nil, 0 end

	local function scoreAt(lag: number): number
		return combinedScores[lag] or -math.huge
	end

	-- Refine the winning lag between sample intervals.
	local refinedLag = bestLag
	if bestLag > minLag and bestLag < maxLag then
		local left, center, right = scoreAt(bestLag - 1), scoreAt(bestLag), scoreAt(bestLag + 1)
		local denominator = left - 2 * center + right
		if math.abs(denominator) > 1e-6 then
			refinedLag += math.clamp(0.5 * (left - right) / denominator, -0.5, 0.5)
		end
	end

	-- Keep half-time and double-time interpretations alive when their evidence
	-- is competitive. Continuity is a tie-breaker, not the source of tempo.
	local selectedLag = bestLag
	local selectedScore = bestScore
	local referenceBPM = bpmDetected or bpmCurrent
	local alternatives = {bestLag * 2, math.floor(bestLag / 2 + 0.5)}
	for _, alternateLag in ipairs(alternatives) do
		if alternateLag >= minLag and alternateLag <= maxLag then
			local alternateScore = scoreAt(alternateLag)
			local candidateBPM = 60 * SAMPLE_RATE / alternateLag
			local selectedBPM = 60 * SAMPLE_RATE / selectedLag
			if alternateScore >= bestScore - 0.075
				and math.abs(candidateBPM - referenceBPM) < math.abs(selectedBPM - referenceBPM) then
				selectedLag = alternateLag
				selectedScore = alternateScore
			end
		end
	end

	local bpm = math.clamp(60 * SAMPLE_RATE / (if selectedLag == bestLag then refinedLag else selectedLag), BPM_MIN, BPM_MAX)
	local periodicity = math.clamp((selectedScore - 0.08) / 0.52, 0, 1)
	local peakSeparation = if secondScore > -math.huge
		then math.clamp((bestScore - secondScore) / 0.18, 0, 1)
		else 0.5
	local confidence = periodicity * (0.62 + peakSeparation * 0.38)
	if confidence < 0.22 then return nil, confidence end
	return bpm, confidence
end


-- Short and long windows serve different purposes: the short view follows
-- genuine section changes, while the long view protects slow/sparse passages.
-- When they disagree without a clear winner, hold the prior trusted tempo.
local function estimateTempo(): (number?, number)
	local shortBPM, shortConfidence = estimateTempoWindow(3.5)
	local longBPM, longConfidence = estimateTempoWindow(8.0)
	if shortBPM and longBPM then
		local disagreement = math.abs(shortBPM - longBPM) / math.max(longBPM, 1)
		if disagreement <= 0.06 then
			return shortBPM * 0.65 + longBPM * 0.35,
				math.clamp(shortConfidence * 0.65 + longConfidence * 0.35, 0, 1)
		end
		if shortConfidence >= 0.48 and shortConfidence >= longConfidence - 0.08 then
			return shortBPM, shortConfidence * 0.90
		end
		return longBPM, longConfidence * 0.92
	elseif longBPM then
		return longBPM, longConfidence
	elseif shortBPM then
		return shortBPM, shortConfidence * 0.80
	end
	return nil, math.max(shortConfidence, longConfidence)
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

	-- Convert spectrum indices to their documented frequency positions
	-- (0..24 kHz). Fixed bin numbers are invalid across different window sizes.
	local bandFlux: {[string]: number} = {bass = 0, lowMid = 0, presence = 0, high = 0}
	local bandCounts: {[string]: number} = {bass = 0, lowMid = 0, presence = 0, high = 0}
	local spectrumCount = #spectrum
	for i = 2, spectrumCount do
		local frequency = ((i - 1) / math.max(spectrumCount - 1, 1)) * 24000
		local current = if finite(spectrum[i]) then math.max(0, spectrum[i]) else 0
		local previous = previousSpectrum and previousSpectrum[i] or 0
		local rise = math.max(0, current - previous)
		local bandName = if frequency < 160 then "bass"
			elseif frequency < 600 then "lowMid"
			elseif frequency < 4000 then "presence"
			elseif frequency < 12000 then "high" else nil
		if bandName then
			bandFlux[bandName] += rise
			bandCounts[bandName] += 1
		end
	end
	local rmsRise = math.max(0, rms - previousRms)
	previousSpectrum = table.clone(spectrum)
	previousRms = rms

	-- Average within each band so a band with more FFT bins does not win merely
	-- because it contains more entries. Keep independent envelopes for tempo
	-- voting and a weighted composite for onset/phase tracking.
	local function smoothBand(name: string): number
		local raw = bandFlux[name] / math.max(1, bandCounts[name])
		local history = bandHistories[name]
		if #history > 0 then return history[#history] * 0.32 + raw * 0.68 end
		return raw
	end
	local smoothedBands = {
		bass = smoothBand("bass"),
		lowMid = smoothBand("lowMid"),
		presence = smoothBand("presence"),
		high = smoothBand("high"),
	}
	local flux = smoothedBands.bass * 1.0 + smoothedBands.lowMid * 0.72
		+ smoothedBands.presence * 0.42 + smoothedBands.high * 0.20
	local rawOnset = flux * 0.78 + rmsRise * 0.22
	local smoothedOnset = rawOnset
	if #envelopeHistory > 0 then
		smoothedOnset = envelopeHistory[#envelopeHistory] * 0.32 + rawOnset * 0.68
	end
	pushHistory(smoothedOnset, smoothedBands)
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
		-- Reject weak transients and repeated subdivisions as phase references.
		local strongOnset = onsetStrength >= 0.18
		if not beatAnchorReady then
			beatAnchorPosition = peakPosition
			beatAnchorReady = true
			lastAcceptedOnsetPosition = peakPosition
			phaseLockConfidence = 0.20 + onsetStrength * 0.15
		elseif strongOnset then
			local beatsFromAnchor = (peakPosition - beatAnchorPosition) / period
			local phaseError = beatsFromAnchor - math.floor(beatsFromAnchor + 0.5)
			local errorSeconds = phaseError * period
			local interval = peakPosition - lastAcceptedOnsetPosition
			local nearBeat = math.abs(errorSeconds) <= period * 0.18
			local beatLikeInterval = interval >= period * 0.72 and interval <= period * 1.28
			if nearBeat and (beatLikeInterval or interval > period * 1.65) then
				-- Bounded correction avoids large phase jumps from one transient.
				local confidenceWeight = math.clamp(bpmConfidence * 0.65 + onsetStrength * 0.35, 0.15, 1)
				local gain = 0.07 + 0.11 * confidenceWeight
				local correction = math.clamp(errorSeconds * gain, -0.018, 0.018)
				beatAnchorPosition += correction
				phaseErrorSeconds += (errorSeconds - phaseErrorSeconds) * 0.18
				lastAcceptedOnsetPosition = peakPosition
				phaseLockConfidence += (1 - phaseLockConfidence) * (0.08 + onsetStrength * 0.06)
			else
				phaseLockConfidence *= 0.985
			end
		end
	end
	fluxOlder = fluxPrevious
	fluxPrevious = smoothedOnset
	fluxPreviousPosition = timePosition

	local analysisNow = os.clock()
	if analysisNow - lastTempoAnalysisAt < TEMPO_ANALYZE_INTERVAL then return end
	lastTempoAnalysisAt = analysisNow
	local detected, confidence = estimateTempo()
	rawCandidateBPM = detected
	local minimumCandidateConfidence = if bpmDetected then 0.34 else 0.46
	if detected and confidence >= minimumCandidateConfidence then
		-- Require a sustained, internally consistent candidate before it can
		-- influence the shared clock. A fill or one ambiguous autocorrelation
		-- peak cannot immediately retune the lighting system.
		local agrees = pendingBPM ~= nil
			and math.abs(detected - pendingBPM) / math.max(pendingBPM, 1) <= 0.055
		if agrees then
			local priorPending = pendingBPM :: number
			pendingBPM = priorPending + (detected - priorPending) * 0.12
			pendingTempoSamples += 1
			pendingTempoConfidence += (confidence - pendingTempoConfidence) * 0.12
		else
			pendingBPM = detected
			pendingTempoSamples = 1
			pendingTempoConfidence = confidence
		end

		-- Require a longer consensus than a single short fill or genre-layer change.
		-- At 10 Hz, 12 observations ~= 1.2 seconds; large non-octave transitions
		-- need 1.8 seconds so a competing subdivision cannot retune the clock.
		local accepted = pendingBPM :: number
		local relativeChange = if bpmDetected
			then math.abs(accepted - bpmDetected) / math.max(bpmDetected, 1) else 0
		local octaveMatch = bpmDetected ~= nil and (
			math.abs(accepted * 2 - bpmDetected) / bpmDetected <= 0.08
			or math.abs(accepted * 0.5 - bpmDetected) / bpmDetected <= 0.08)
		local requiredSamples = if not bpmDetected then 24 elseif relativeChange > 0.30 and not octaveMatch then 18 else 12
		if pendingTempoSamples >= requiredSamples then
			if bpmDetected and relativeChange > 0.30 and not octaveMatch
				and pendingTempoConfidence < 0.58 then
				pendingTempoSamples = requiredSamples - 1
			else
			-- React faster to sustained, confident tempo movement while keeping
			-- weak or ambiguous estimates deliberately conservative.
			local deltaRatio = if bpmDetected then math.abs(accepted - bpmDetected) / math.max(bpmDetected, 1) else 1
			local blend = math.clamp(0.18 + pendingTempoConfidence * 0.30
				+ math.clamp(deltaRatio * 1.4, 0, 0.18), 0.18, 0.58)
			local previousDetected = bpmDetected
			bpmDetected = if previousDetected then previousDetected + (accepted - previousDetected) * blend else accepted
			bpmConfidence += (pendingTempoConfidence - bpmConfidence) * 0.28
			if previousDetected and deltaRatio > 0.025 then
				phaseLockConfidence *= 0.92
			end
			lastTempoUpdate = os.clock()
			end
		end
	else
		pendingTempoSamples = math.max(0, pendingTempoSamples - 1)
		pendingTempoConfidence *= 0.96
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
		trackGeneration += 1
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
		-- Keep the last trusted tempo through breakdowns and analyzer dropouts.
		-- A new asset explicitly clears this state in clearAnalysis().
		bpmConfidence *= math.exp(-dt * 0.12)
		phaseLockConfidence *= math.exp(-dt * 0.08)
	end
	local targetBPM = bpmDetected or bpmCurrent
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
	if RunService:IsClient() and playing and now - lastDiagnosticsAt >= 5 then
		lastDiagnosticsAt = now
		local candidateText = if rawCandidateBPM then string.format("%.1f", rawCandidateBPM) else "none"
		local tempoFamily = if rawCandidateBPM
			then string.format("%.1f/%.1f/%.1f", rawCandidateBPM * 0.5, rawCandidateBPM, rawCandidateBPM * 2)
			else "none"
		print(string.format(
			"[ClubAudioSync][Analyzer] track=%s generation=%d BPM=%.1f confidence=%.2f source=%s candidate=%s familyHalfCurrentDouble=%s pending=%d phaseLockQuality=%.2f phaseErrorMs=%.1f onset=%.2f energy=%.2f analyzerReady=%s",
			if assetId ~= "" then assetId else "unknown", trackGeneration, bpm, bpmConfidence,
			if bpmDetected then "audio-confirmed" else "seed/warming", candidateText, tempoFamily,
			pendingTempoSamples, phaseLockConfidence, phaseErrorSeconds * 1000, onsetStrength, energy,
			tostring(analyzer ~= nil and analyzer.Parent ~= nil)
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
