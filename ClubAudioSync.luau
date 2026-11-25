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
-- Verified library references are soft tempo priors, never forced playback tempos.
local TRACK_TEMPO_PRIORS: {[string]: number} = {
	["92952858514774"] = 89.3, -- Metallic Chaos Within Magic Theory
	["86468432953052"] = 139.8, -- Fallen Star Blues
	["84266261446965"] = 190.0, -- Anvil of Ruin: dominant pulse; bridge/outro sections vary
	["99973341792058"] = 170.0, -- Midnight Lucid: composition reference pulse; chaotic intro and breakdowns vary
}
local trackWarmupUntil = 0
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
local rawCandidateConfidence = 0
local pendingBPM: number? = nil
local pendingTempoSamples = 0
local pendingTempoConfidence = 0
local pendingChallengerBPM: number? = nil
local pendingChallengerSamples = 0
local lastPendingTempoEvidenceAt = 0
-- Keep several independent tempo-family hypotheses alive at once. Octave-related
-- estimates (e.g. 65 and 130 BPM) contribute to one family, while unrelated
-- periodicities (e.g. 86 BPM) cannot erase that family's accumulated evidence.
type TempoFamilyHypothesis = {
	familyBPM: number,
	lowBPM: number,
	highBPM: number,
	lowSamples: number,
	highSamples: number,
	confidence: number,
	samples: number,
	lastEvidenceAt: number,
}
local tempoFamilyHypotheses: {TempoFamilyHypothesis} = {}
local TEMPO_FAMILY_MATCH_TOLERANCE = 0.055
local TEMPO_FAMILY_MAX_HYPOTHESES = 4
local lastTempoUpdate = 0
local lastTempoAnalysisAt = 0
local TEMPO_ANALYZE_INTERVAL = 0.10
local TEMPO_STALE_SECONDS = 12
-- Mixed arrangements and free-time intros can suppress a candidate while a different
-- transient pattern dominates. Retain recurring family evidence across a longer gap,
-- but still expire it before evidence from an earlier musical section can linger.
local PENDING_EVIDENCE_TIMEOUT = 22.0
-- Evidence is recency-weighted: a family that dominated several sections ago
-- must not beat a currently consistent challenger solely through old sample count.
-- A slower decay lets intermittent groove evidence survive sparse transitions
-- without turning old evidence into a permanent vote.
local TEMPO_EVIDENCE_DECAY_SECONDS = 15.0
local CHALLENGER_REQUIRED_SAMPLES = 8
local energy = 0
local tempoLayerAgreement = 0.5
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
local lastFastOnsetPosition = -math.huge
local beatAnchorPosition = 0
local beatAnchorReady = false
local fallbackAnchorReady = false
local onsetStrength = 0
local phaseLockConfidence = 0
local phaseErrorSeconds = 0
local lastAcceptedOnsetPosition = -math.huge
local lastDiagnosticsAt = 0
-- Rhythmic feel is diagnostic-only: it never retunes BPM or changes BeatState.
-- AudioAnalyzer supplies a mixed signal, so classifications require repeated
-- onset-interval evidence and remain unknown when accents are inconclusive.
local feelOnsetIntervals: {number} = {}
local lastFeelOnsetPosition = -math.huge
local rhythmicFeel = "unknown"
local rhythmicFeelCandidate = "unknown"
local rhythmicFeelCandidateSamples = 0
local rhythmicFeelConfidence = 0
local feelDoubleTimeVotes = 0
local feelOnBeatVotes = 0
local feelHalfTimeVotes = 0
local feelUnclassifiedIntervals = 0
local feelTransientDropouts = 0
local feelGridRejected = 0
local matchingTempoEvidenceSamples = 0
local FEEL_INTERVAL_HISTORY = 12
local FEEL_CLASSIFY_MIN_INTERVALS = 6

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
	rawCandidateConfidence = 0
	pendingBPM = nil
	pendingTempoSamples = 0
	pendingTempoConfidence = 0
	pendingChallengerBPM = nil
	pendingChallengerSamples = 0
	lastPendingTempoEvidenceAt = 0
	tempoFamilyHypotheses = {}
	lastTempoUpdate = 0
	lastTempoAnalysisAt = 0
	energy = 0
	tempoLayerAgreement = 0.5
	sampleAccumulator = 0
	lastSampleAt = 0
	lastBeatIndex = -1
	fluxOlder = 0
	fluxPrevious = 0
	fluxPreviousPosition = 0
	lastOnsetPosition = -math.huge
	lastFastOnsetPosition = -math.huge
	beatAnchorPosition = 0
	beatAnchorReady = false
	fallbackAnchorReady = false
	onsetStrength = 0
	phaseLockConfidence = 0
	phaseErrorSeconds = 0
	lastAcceptedOnsetPosition = -math.huge
	feelOnsetIntervals = {}
	lastFeelOnsetPosition = -math.huge
	rhythmicFeel = "unknown"
	rhythmicFeelCandidate = "unknown"
	rhythmicFeelCandidateSamples = 0
	rhythmicFeelConfidence = 0
	feelDoubleTimeVotes = 0
	feelOnBeatVotes = 0
	feelHalfTimeVotes = 0
	feelUnclassifiedIntervals = 0
	feelTransientDropouts = 0
	feelGridRejected = 0
	matchingTempoEvidenceSamples = 0
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
	tempoLayerAgreement = 0.5
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
				table.insert(activeChannels, {centered = centered, weight = channel.weight, scores = {}, bestScore = -math.huge})
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
			channel.scores[lag] = normalized
			channel.bestScore = math.max(channel.bestScore, normalized)
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
	local referenceBPM = TRACK_TEMPO_PRIORS[lastAssetId] or bpmDetected or bpmCurrent
	local familyAmbiguous = false
	local octaveAlternatives = {bestLag * 2, math.floor(bestLag / 2 + 0.5)}
	-- Also inspect 3:2 metrical interpretations. A strong triplet pulse can
	-- produce a stable autocorrelation peak at 2/3 or 3/2 of the underlying
	-- beat period (for example, ~85.7 BPM can coexist with a ~128.6 BPM grid).
	-- These alternatives are deliberately held to a much tighter score margin
	-- than octave alternatives, because unrelated tempos must not be merged.
	local tripletAlternatives = {
		math.floor(bestLag * 2 / 3 + 0.5),
		math.floor(bestLag * 3 / 2 + 0.5),
	}
	-- On established tracks, protect the confirmed metrical level against
	-- octave-related transients (blast beats, double-kick, tremolo and dense
	-- electronic subdivisions). A competing octave hypothesis may be weaker
	-- than the raw autocorrelation winner yet still be the correct beat grid.
	-- This is continuity evidence, not a hard BPM clamp: a genuinely new tempo
	-- can still win when its evidence is clearly stronger across the windows.
	local hasTrackPrior = TRACK_TEMPO_PRIORS[lastAssetId] ~= nil
	local familyContinuityMargin = if hasTrackPrior then 0.22 elseif bpmDetected then 0.18 else 0.075
	for _, alternateLag in ipairs(octaveAlternatives) do
		if alternateLag >= minLag and alternateLag <= maxLag then
			local alternateScore = scoreAt(alternateLag)
			local candidateBPM = 60 * SAMPLE_RATE / alternateLag
			local selectedBPM = 60 * SAMPLE_RATE / selectedLag
			local candidateDistance = math.abs(candidateBPM - referenceBPM) / math.max(referenceBPM, 1)
			local selectedDistance = math.abs(selectedBPM - referenceBPM) / math.max(referenceBPM, 1)
			if alternateScore >= bestScore - familyContinuityMargin then
				if alternateScore >= bestScore - 0.075 then
					familyAmbiguous = true
				end
				if candidateDistance < selectedDistance then
					selectedLag = alternateLag
					selectedScore = alternateScore
				end
			end
		end
	end
	-- Resolve a close competing peak toward the known track pulse without
	-- clamping BPM: the prior is accepted only when its measured correlation
	-- remains within 0.22 of the strongest observed lag.
	local trackPrior = TRACK_TEMPO_PRIORS[lastAssetId]
	if trackPrior then
		local priorLag = math.floor(60 * SAMPLE_RATE / trackPrior + 0.5)
		local priorScore = math.max(scoreAt(priorLag - 1), scoreAt(priorLag), scoreAt(priorLag + 1))
		if priorLag >= minLag and priorLag <= maxLag and priorScore >= bestScore - 0.22 then
			selectedLag = priorLag
			selectedScore = priorScore
		end
	end

	local tripletScoreMargin = if bpmDetected then 0.012 else 0.025
	for _, alternateLag in ipairs(tripletAlternatives) do
		if alternateLag >= minLag and alternateLag <= maxLag then
			local alternateScore = scoreAt(alternateLag)
			if alternateScore >= bestScore - tripletScoreMargin then
				familyAmbiguous = true
				local candidateBPM = 60 * SAMPLE_RATE / alternateLag
				local selectedBPM = 60 * SAMPLE_RATE / selectedLag
				local candidateDistance = math.abs(candidateBPM - referenceBPM) / math.max(referenceBPM, 1)
				local selectedDistance = math.abs(selectedBPM - referenceBPM) / math.max(referenceBPM, 1)
				if candidateDistance < selectedDistance then
					selectedLag = alternateLag
					selectedScore = alternateScore
				end
			end
		end
	end

	-- Measure whether independent spectral regions support the selected pulse family.
	-- Octave-related peaks count as the same metrical family, but an unrelated
	-- transient peak in only one band cannot dominate the fused tempo estimate.
	local supportedWeight = 0
	for _, channel in ipairs(activeChannels) do
		local function localScore(lag: number): number
			return math.max(channel.scores[lag - 1] or -math.huge,
				channel.scores[lag] or -math.huge, channel.scores[lag + 1] or -math.huge)
		end
		local familyScore = math.max(localScore(selectedLag),
			localScore(math.floor(selectedLag * 0.5 + 0.5)),
			localScore(selectedLag * 2))
		if familyScore >= channel.bestScore - 0.12 then
			supportedWeight += channel.weight
		end
	end
	tempoLayerAgreement = if #activeChannels >= 2
		then math.clamp(supportedWeight / totalWeight, 0, 1) else 0.5

	local bpm = math.clamp(60 * SAMPLE_RATE / (if selectedLag == bestLag then refinedLag else selectedLag), BPM_MIN, BPM_MAX)
	local periodicity = math.clamp((selectedScore - 0.08) / 0.52, 0, 1)
	local peakSeparation = if secondScore > -math.huge
		then math.clamp((bestScore - secondScore) / 0.18, 0, 1)
		else 0.5
	local confidence = periodicity * (0.62 + peakSeparation * 0.38)
	-- Apply a bounded penalty when bass, low-mid, presence and high-frequency
	-- evidence disagree. One dominant attack layer is not sufficient to certify tempo.
	confidence *= 0.70 + tempoLayerAgreement * 0.30
	-- A near-tie between a pulse and its octave-related interpretation is
	-- not enough evidence to declare the metrical level on a new track.
	-- Once a tempo is established, continuity may resolve that ambiguity.
	if familyAmbiguous and not bpmDetected then
		confidence *= 0.68
	end
	if confidence < 0.22 then return nil, confidence end
	return bpm, confidence
end


-- Short and long windows serve different purposes: the short view follows
-- genuine section changes, while the long view protects slow/sparse passages.
-- When they disagree without a clear winner, hold the prior trusted tempo.
local function estimateTempo(): (number?, number)
	local shortBPM, shortConfidence = estimateTempoWindow(3.5)
	local shortLayerAgreement = tempoLayerAgreement
	local longBPM, longConfidence = estimateTempoWindow(8.0)
	local longLayerAgreement = tempoLayerAgreement
	if shortBPM and longBPM then
		local disagreement = math.abs(shortBPM - longBPM) / math.max(longBPM, 1)
		if disagreement <= 0.06 then
			tempoLayerAgreement = shortLayerAgreement * 0.65 + longLayerAgreement * 0.35
			return shortBPM * 0.65 + longBPM * 0.35,
				math.clamp(shortConfidence * 0.65 + longConfidence * 0.35, 0, 1)
		end
		if shortConfidence >= 0.48 and shortConfidence >= longConfidence - 0.08 then
			tempoLayerAgreement = shortLayerAgreement
			return shortBPM, shortConfidence * 0.90
		end
		tempoLayerAgreement = longLayerAgreement
		return longBPM, longConfidence * 0.92
	elseif longBPM then
		tempoLayerAgreement = longLayerAgreement
		return longBPM, longConfidence
	elseif shortBPM then
		tempoLayerAgreement = shortLayerAgreement
		return shortBPM, shortConfidence * 0.80
	end
	return nil, math.max(shortConfidence, longConfidence)
end

local function updateRhythmicFeel(onsetPosition: number, referenceBPM: number)
	if referenceBPM < BPM_MIN or referenceBPM > BPM_MAX then return end
	-- A mixed electronic/metal master can generate many valid spectral peaks
	-- that are not part of its perceived pulse. Only let sufficiently strong
	-- peaks vote when they align with the locked beat OR half-beat grid.
	-- This keeps syncopated/glitch transients from freely steering feel labels.
	if not beatAnchorReady or phaseLockConfidence < 0.28 or onsetStrength < 0.18 then
		feelGridRejected += 1
		return
	end
	local beatPeriod = 60 / referenceBPM
	local beatsFromAnchor = (onsetPosition - beatAnchorPosition) / beatPeriod
	local nearestHalfBeat = math.floor(beatsFromAnchor * 2 + 0.5) * 0.5
	local gridAligned = math.abs(beatsFromAnchor - nearestHalfBeat) <= 0.16
	if not gridAligned then
		-- Some hybrid grooves place recurring accents just outside the strict
		-- beat/half-beat phase window. Admit one only when it repeats at a
		-- plausible subdivision of the established pulse, with stronger live
		-- onset and phase evidence than the normal on-grid path requires.
		local interval = if lastFeelOnsetPosition > -math.huge
			then onsetPosition - lastFeelOnsetPosition else 0
		local repeatedPulseInterval = false
		if interval > 0 then
			for _, multiplier in ipairs({0.5, 1, 2}) do
				local expected = beatPeriod * multiplier
				if math.abs(interval - expected) / expected <= 0.16 then
					repeatedPulseInterval = true
					break
				end
			end
		end
		if not repeatedPulseInterval or phaseLockConfidence < 0.45 or onsetStrength < 0.30 then
			feelGridRejected += 1
			return
		end
	end
	if lastFeelOnsetPosition > -math.huge then
		local interval = onsetPosition - lastFeelOnsetPosition
		-- A long gap between detected peaks is not automatically half-time.
		-- Compare the envelope during that gap with the preceding active section:
		-- a sharp activity collapse indicates missing transient evidence, not a
		-- reliable slower pulse. Keep such gaps out of the feel vote history.
		local transientDropout = false
		local beatPeriod = 60 / referenceBPM
		if interval >= beatPeriod * 1.35 and interval <= 2.0 then
			local segmentSamples = math.min(#envelopeHistory,
				math.max(1, math.floor(interval * SAMPLE_RATE)))
			local precedingSamples = math.min(SAMPLE_RATE * 2,
				math.max(0, #envelopeHistory - segmentSamples))
			if segmentSamples >= SAMPLE_RATE * 0.5 and precedingSamples >= SAMPLE_RATE * 0.5 then
				local segmentMean, precedingMean = 0, 0
				local segmentStart = #envelopeHistory - segmentSamples + 1
				local precedingStart = segmentStart - precedingSamples
				for index = segmentStart, #envelopeHistory do
					segmentMean += envelopeHistory[index]
				end
				segmentMean /= segmentSamples
				for index = precedingStart, segmentStart - 1 do
					precedingMean += envelopeHistory[index]
				end
				precedingMean /= precedingSamples
				transientDropout = precedingMean > 1e-5
					and segmentMean < precedingMean * 0.38
			end
		end
		if interval >= 0.16 and interval <= 2.0 then
			if transientDropout then
				feelTransientDropouts += 1
			else
				table.insert(feelOnsetIntervals, interval)
				if #feelOnsetIntervals > FEEL_INTERVAL_HISTORY then
					table.remove(feelOnsetIntervals, 1)
				end
			end
		end
	end
	lastFeelOnsetPosition = onsetPosition
	if #feelOnsetIntervals < FEEL_CLASSIFY_MIN_INTERVALS then return end

	local beatPeriod = 60 / referenceBPM
	local doubleTimeCount, onBeatCount, halfTimeCount, total = 0, 0, 0, 0
	for _, interval in ipairs(feelOnsetIntervals) do
		local doubleError = math.abs(interval - beatPeriod * 0.5) / (beatPeriod * 0.5)
		local beatError = math.abs(interval - beatPeriod) / beatPeriod
		local halfError = math.abs(interval - beatPeriod * 2) / (beatPeriod * 2)
		local bestError = math.min(doubleError, beatError, halfError)
		if bestError <= 0.22 then
			total += 1
			if bestError == doubleError then
				doubleTimeCount += 1
			elseif bestError == beatError then
				onBeatCount += 1
			else
				halfTimeCount += 1
			end
		end
	end
	if total < FEEL_CLASSIFY_MIN_INTERVALS then
		feelDoubleTimeVotes = doubleTimeCount
		feelOnBeatVotes = onBeatCount
		feelHalfTimeVotes = halfTimeCount
		feelUnclassifiedIntervals = #feelOnsetIntervals - total
		return
	end

	feelDoubleTimeVotes = doubleTimeCount
	feelOnBeatVotes = onBeatCount
	feelHalfTimeVotes = halfTimeCount
	feelUnclassifiedIntervals = #feelOnsetIntervals - total

	local winner = if doubleTimeCount > onBeatCount and doubleTimeCount > halfTimeCount then "double-time"
		elseif halfTimeCount > onBeatCount and halfTimeCount > doubleTimeCount then "half-time"
		elseif onBeatCount > doubleTimeCount and onBeatCount > halfTimeCount then "on-beat"
		else "ambiguous"
	local winnerCount = math.max(doubleTimeCount, onBeatCount, halfTimeCount)
	-- Confidence includes inconclusive intervals. A dense subdivision pattern
	-- must not be labeled as a confident rhythmic feel when much of the recent
	-- onset history does not support that interpretation.
	local confidence = winnerCount / math.max(#feelOnsetIntervals, 1)
	if confidence < 0.70 then winner = "ambiguous" end
	rhythmicFeelConfidence = confidence
	if winner == rhythmicFeelCandidate then
		rhythmicFeelCandidateSamples += 1
	else
		rhythmicFeelCandidate = winner
		rhythmicFeelCandidateSamples = 1
	end
	if rhythmicFeelCandidateSamples >= 3 then
		rhythmicFeel = winner
	end
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
		-- Extreme-metal blast beats and double-kick runs can create very large,
		-- tightly packed spectral-flux spikes. Apply a concave transfer before
		-- autocorrelation so isolated high-energy attacks cannot dominate the
		-- envelope by amplitude alone. Timing and periodicity are preserved;
		-- this is not a low-pass tempo clamp or an instrument classifier.
		local compressed = math.sqrt(math.max(0, raw))
		local history = bandHistories[name]
		-- Soft-limit isolated spectral outliers against the recent band envelope.
		-- The cap adapts to recurring attacks, so sustained blast-beat/kick patterns
		-- remain measurable while one-off clicks and glitch spikes lose influence.
		if #history >= 12 then
			local recentCount = math.min(#history, math.floor(SAMPLE_RATE * 1.5))
			local first = #history - recentCount + 1
			local mean, variance = 0, 0
			for i = first, #history do mean += history[i] end
			mean /= recentCount
			for i = first, #history do
				local delta = history[i] - mean
				variance += delta * delta
			end
			local deviation = math.sqrt(variance / math.max(1, recentCount - 1))
			local ceiling = mean + math.max(deviation * 2.8, mean * 1.8, 0.0001)
			if compressed > ceiling then
				compressed = ceiling + (compressed - ceiling) * 0.25
			end
		end
		if #history > 0 then return history[#history] * 0.42 + compressed * 0.58 end
		return compressed
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
		and peak > threshold and peakPosition - lastFastOnsetPosition >= 0.16 then
		lastFastOnsetPosition = peakPosition
		onsetStrength = math.clamp((peak - mean) / math.max(deviation * 3, 1e-5), 0, 1)

		local bpm = bpmDetected or bpmCurrent
		local period = 60 / math.clamp(bpm, BPM_MIN, BPM_MAX)
		-- The fast diagnostic lane may observe 0.16-0.22s events, but the
		-- primary beat PLL retains its independent stricter 0.22s gate.
		local mainClockOnset = peakPosition - lastOnsetPosition >= 0.22
		if mainClockOnset then lastOnsetPosition = peakPosition end
		local strongOnset = onsetStrength >= 0.18
		if mainClockOnset and not beatAnchorReady then
			beatAnchorPosition = peakPosition
			beatAnchorReady = true
			lastAcceptedOnsetPosition = peakPosition
			phaseLockConfidence = 0.20 + onsetStrength * 0.15
		elseif mainClockOnset and strongOnset then
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
		updateRhythmicFeel(peakPosition, bpm)
	end
	fluxOlder = fluxPrevious
	fluxPrevious = smoothedOnset
	fluxPreviousPosition = timePosition

	local analysisNow = os.clock()
	if analysisNow - lastTempoAnalysisAt < TEMPO_ANALYZE_INTERVAL then return end
	local analysisElapsed = if lastTempoAnalysisAt > 0
		then math.clamp(analysisNow - lastTempoAnalysisAt, 0, TEMPO_ANALYZE_INTERVAL * 4)
		else TEMPO_ANALYZE_INTERVAL
	lastTempoAnalysisAt = analysisNow
	-- Decay every family on every analysis pass, including passes with no
	-- candidate. This makes pending evidence represent recent support rather
	-- than an unbounded lifetime tally.
	local evidenceDecay = math.exp(-analysisElapsed / TEMPO_EVIDENCE_DECAY_SECONDS)
	for _, hypothesis in ipairs(tempoFamilyHypotheses) do
		-- All votes must share the same recency window. Previously only the
		-- aggregate family score decayed; low/high metrical votes accumulated
		-- for the entire track and could keep an obsolete half/double-time
		-- preference alive after the supporting section had passed.
		hypothesis.samples *= evidenceDecay
		hypothesis.lowSamples *= evidenceDecay
		hypothesis.highSamples *= evidenceDecay
		hypothesis.confidence *= evidenceDecay
	end
	local detected, confidence = estimateTempo()
	rawCandidateBPM = detected
	rawCandidateConfidence = confidence
	-- Initial acquisition is deliberately stricter than tracking an established
	-- clock. A weak but persistent low-frequency periodicity can otherwise win
	-- during a hybrid intro before the analyzer has enough evidence to identify
	-- the main pulse. Once acquired, normal transition thresholds apply.
	-- When the incumbent has lost nearly all confidence, require fresh
	-- acquisition-grade evidence from its challenger. A stale lock must not
	-- retain the easier established-track threshold indefinitely.
	local incumbentStillTrusted = bpmDetected ~= nil and bpmConfidence > 0.18
	local hasTrackPrior = TRACK_TEMPO_PRIORS[lastAssetId] ~= nil
	-- A long-lived, tightly clustered family is stronger evidence than any
	-- single autocorrelation window. Track priors may lower the acquisition bar
	-- only when the measured candidate remains close to that known pulse.
	local minimumCandidateConfidence = if incumbentStillTrusted then 0.34 elseif hasTrackPrior then 0.38 else 0.52
	-- Preserve moderate-confidence candidates as family evidence during hybrid
	-- arrangements. A candidate may alternate between half-time and double-time
	-- (e.g. 85.7 and 171 BPM) while describing the same underlying pulse family.
	local minimumFamilyEvidenceConfidence = if hasTrackPrior then 0.26 elseif bpmDetected then 0.34 else 0.30
	-- Do not let numerical autocorrelation noise from a near-silent
	-- interval seed or confirm a tempo family. The floor is intentionally
	-- very low so quiet musical passages remain analyzable.
	local hasUsableSignal = rms > 0.0005
	if detected and hasUsableSignal and confidence >= minimumFamilyEvidenceConfidence then
		-- Expire stale hypotheses independently so an intermittent but recurring
		-- pulse can survive brief windows in which another periodicity wins.
		for index = #tempoFamilyHypotheses, 1, -1 do
			if analysisNow - tempoFamilyHypotheses[index].lastEvidenceAt > PENDING_EVIDENCE_TIMEOUT then
				table.remove(tempoFamilyHypotheses, index)
			end
		end

		-- Canonicalize only octave-equivalent BPMs into the same family. This
		-- deliberately does not merge unrelated candidates such as 86 and 130.
		local familyBPM = detected
		while familyBPM > 120 do familyBPM *= 0.5 end
		while familyBPM < 60 do familyBPM *= 2 end
		local hypothesis: TempoFamilyHypothesis? = nil
		for _, item in ipairs(tempoFamilyHypotheses) do
			local familyDistance = math.abs(familyBPM - item.familyBPM) / math.max(item.familyBPM, 1)
			if familyDistance <= TEMPO_FAMILY_MATCH_TOLERANCE then
				hypothesis = item
				break
			end
		end
		if not hypothesis then
			hypothesis = {
				familyBPM = familyBPM,
				lowBPM = 0,
				highBPM = 0,
				lowSamples = 0,
				highSamples = 0,
				confidence = confidence,
				samples = 0,
				lastEvidenceAt = analysisNow,
			}
			table.insert(tempoFamilyHypotheses, hypothesis)
		end

		hypothesis.familyBPM += (familyBPM - hypothesis.familyBPM) * 0.12
		if detected > hypothesis.familyBPM * 1.42 then
			hypothesis.highSamples += 1
			hypothesis.highBPM = if hypothesis.highBPM > 0
				then hypothesis.highBPM + (detected - hypothesis.highBPM) * 0.12 else detected
		else
			hypothesis.lowSamples += 1
			hypothesis.lowBPM = if hypothesis.lowBPM > 0
				then hypothesis.lowBPM + (detected - hypothesis.lowBPM) * 0.12 else detected
		end
		hypothesis.samples += 1
		hypothesis.confidence += (confidence - hypothesis.confidence) * 0.12
		hypothesis.lastEvidenceAt = analysisNow

		-- Retain the strongest few independent families. Give the startup tempo
		-- only a modest tie-break advantage when choosing the displayed metrical
		-- level; it never causes unrelated families to be merged.
		table.sort(tempoFamilyHypotheses, function(a, b)
			local aScore = a.samples * (0.65 + a.confidence * 0.35)
			local bScore = b.samples * (0.65 + b.confidence * 0.35)
			if math.abs(aScore - bScore) < 0.001 then
				local aLevel = if a.highSamples > a.lowSamples * 1.20 then a.highBPM
					elseif a.lowSamples > a.highSamples * 1.20 then a.lowBPM
					else if a.highBPM > 0 and a.lowBPM > 0
						then (if math.abs(a.highBPM - bpmCurrent) < math.abs(a.lowBPM - bpmCurrent) then a.highBPM else a.lowBPM)
						else math.max(a.highBPM, a.lowBPM)
				local bLevel = if b.highSamples > b.lowSamples * 1.20 then b.highBPM
					elseif b.lowSamples > b.highSamples * 1.20 then b.lowBPM
					else if b.highBPM > 0 and b.lowBPM > 0
						then (if math.abs(b.highBPM - bpmCurrent) < math.abs(b.lowBPM - bpmCurrent) then b.highBPM else b.lowBPM)
						else math.max(b.highBPM, b.lowBPM)
					return math.abs(aLevel - bpmCurrent) < math.abs(bLevel - bpmCurrent)
			end
			return aScore > bScore
		end)
		while #tempoFamilyHypotheses > TEMPO_FAMILY_MAX_HYPOTHESES do
			table.remove(tempoFamilyHypotheses)
		end

		local winner = tempoFamilyHypotheses[1]
		if winner then
			local preferredBPM: number
			-- Require a meaningful recent vote advantage before choosing one
			-- metrical level. Near-ties use continuity as a tie-breaker instead
			-- of flipping between half-time and double-time on tiny vote changes.
			if winner.highSamples > winner.lowSamples * 1.20 and winner.highBPM > 0 then
				preferredBPM = winner.highBPM
			elseif winner.lowSamples > winner.highSamples * 1.20 and winner.lowBPM > 0 then
				preferredBPM = winner.lowBPM
			elseif winner.highBPM > 0 and winner.lowBPM > 0 then
				preferredBPM = if math.abs(winner.highBPM - bpmCurrent) < math.abs(winner.lowBPM - bpmCurrent)
					then winner.highBPM else winner.lowBPM
			else
				preferredBPM = math.max(winner.highBPM, winner.lowBPM)
			end

			-- A track prior may disambiguate the octave inside an already-supported
			-- family. It cannot create a family or bypass the evidence/confidence gate.
			local trackPrior = TRACK_TEMPO_PRIORS[lastAssetId]
			if trackPrior then
				local lowMatchesPrior = winner.lowBPM > 0
					and math.abs(winner.lowBPM - trackPrior) / trackPrior <= 0.055
				local highMatchesPrior = winner.highBPM > 0
					and math.abs(winner.highBPM - trackPrior) / trackPrior <= 0.055
				local lowEvidence = winner.lowSamples or 0
				local highEvidence = winner.highSamples or 0
				if highMatchesPrior and highEvidence >= math.max(8, lowEvidence * 0.65)
					and winner.confidence >= 0.28 then
					preferredBPM = winner.highBPM
				elseif lowMatchesPrior and lowEvidence >= math.max(8, highEvidence * 0.65)
					and winner.confidence >= 0.28 then
					preferredBPM = winner.lowBPM
				end
			end
			pendingBPM = preferredBPM
			pendingTempoSamples = math.floor(winner.samples)
			pendingTempoConfidence = winner.confidence
			lastPendingTempoEvidenceAt = analysisNow

			-- Keep legacy diagnostic challenger fields meaningful: the runner-up
			-- family is reported as a challenger, but cannot reset winner evidence.
			local challenger = tempoFamilyHypotheses[2]
			pendingChallengerBPM = if challenger then challenger.familyBPM else nil
			pendingChallengerSamples = if challenger then math.floor(challenger.samples) else 0

			local relativeChange = if bpmDetected
				then math.abs(preferredBPM - bpmDetected) / math.max(bpmDetected, 1) else 0
			local octaveMatch = bpmDetected ~= nil and (
				math.abs(preferredBPM * 2 - bpmDetected) / bpmDetected <= 0.08
				or math.abs(preferredBPM * 0.5 - bpmDetected) / bpmDetected <= 0.08)
			-- Initial acquisition needs fewer repeated windows now that family evidence is
			-- retained across short candidate dropouts. Confidence remains unchanged.
			local requiredSamples = if not bpmDetected then 18 elseif relativeChange > 0.30 and not octaveMatch then 18 else 12
			local sustainedAcquisition = not bpmDetected
				and winner.samples >= 30
				and winner.confidence >= 0.42
			local normalAcquisition = winner.samples >= requiredSamples
				and winner.confidence >= minimumCandidateConfidence
			local trackPrior = TRACK_TEMPO_PRIORS[lastAssetId]
			local priorSupportedAcquisition = trackPrior ~= nil
				and winner.samples >= 18
				and winner.confidence >= 0.26
				and math.abs(preferredBPM - trackPrior) / trackPrior <= 0.055
			if sustainedAcquisition or normalAcquisition or priorSupportedAcquisition then
				local deltaRatio = if bpmDetected then math.abs(preferredBPM - bpmDetected) / math.max(bpmDetected, 1) else 1
				local blend = math.clamp(0.18 + winner.confidence * 0.30
					+ math.clamp(deltaRatio * 1.4, 0, 0.18), 0.18, 0.58)
				local previousDetected = bpmDetected
				bpmDetected = if previousDetected then previousDetected + (preferredBPM - previousDetected) * blend else preferredBPM
				bpmConfidence += (winner.confidence - bpmConfidence) * 0.28
				if previousDetected and deltaRatio > 0.025 then
					phaseLockConfidence *= 0.92
				end
				lastTempoUpdate = analysisNow
			elseif bpmDetected and detected and hasUsableSignal and confidence >= 0.22
				and tempoLayerAgreement >= 0.45
				and math.abs(detected - bpmDetected) / math.max(bpmDetected, 1) <= 0.035 then
				-- A confirmed tempo should not become "untrusted" merely because
				-- the family accumulator is still gathering enough votes for a
				-- formal update. Matching, usable live evidence refreshes its lease.
				-- This does not move BPM or accept an unrelated challenger.
				lastTempoUpdate = analysisNow
				local retainedConfidence = math.max(confidence, 0.24)
				bpmConfidence += (retainedConfidence - bpmConfidence) * 0.08
			end
		end
	else
		-- A brief dropout pauses consensus. After a longer evidence gap, discard
		-- only the unconfirmed candidate; the last confirmed BPM remains intact.
		for index = #tempoFamilyHypotheses, 1, -1 do
			if analysisNow - tempoFamilyHypotheses[index].lastEvidenceAt > PENDING_EVIDENCE_TIMEOUT then
				table.remove(tempoFamilyHypotheses, index)
			end
		end
		if #tempoFamilyHypotheses == 0 then
			pendingBPM = nil
			pendingTempoSamples = 0
			pendingTempoConfidence = 0
			pendingChallengerBPM = nil
			pendingChallengerSamples = 0
			lastPendingTempoEvidenceAt = 0
		end
	end

	-- Keep an established tempo trusted when several consecutive windows
	-- continue to support the same pulse, even if individual windows fall
	-- below the stricter family-accumulation threshold. This refresh is
	-- continuity-only: it cannot acquire a tempo or move the confirmed BPM.
	if bpmDetected and detected and hasUsableSignal and confidence >= 0.14
		and tempoLayerAgreement >= 0.40
		and math.abs(detected - bpmDetected) / math.max(bpmDetected, 1) <= 0.025 then
		matchingTempoEvidenceSamples = math.min(matchingTempoEvidenceSamples + 1, 8)
	else
		matchingTempoEvidenceSamples = math.max(0, matchingTempoEvidenceSamples - 0.75)
	end
	if bpmDetected and matchingTempoEvidenceSamples >= 3 then
		lastTempoUpdate = analysisNow
		local retainedConfidence = math.max(confidence, 0.22)
		bpmConfidence += (retainedConfidence - bpmConfidence) * 0.06
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
		-- Ignore residual spectrum from the outgoing asset during the swap.
		trackWarmupUntil = now + 0.75
	end

	local playing = player ~= nil and player.IsPlaying
	local timePosition = if playing and player then player.TimePosition else 0
	if lastPlaying ~= playing then
		lastPlaying = playing
		lastBeatIndex = -1
	end
	if playing and now >= trackWarmupUntil then sampleAnalyzer(dt, timePosition) end

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
		local priorBPM = TRACK_TEMPO_PRIORS[assetId] or 0
		local tempoFamily = if rawCandidateBPM
			then string.format("%.1f/%.1f/%.1f", rawCandidateBPM * 0.5, rawCandidateBPM, rawCandidateBPM * 2)
			else "none"
		local feelFamily = if bpmDetected
			then string.format("half=%.1f base=%.1f double=%.1f", bpmDetected * 0.5, bpmDetected, bpmDetected * 2)
			else "warming"
		print(string.format(
			"[ClubAudioSync][Analyzer] track=%s generation=%d BPM=%.1f confidence=%.2f source=%s candidate=%s candidateConfidence=%.2f prior=%.1f pendingConfidence=%.2f familyHalfCurrentDouble=%s feel=%s feelConfidence=%.2f feelSamples=%d feelVotes(double/on/half/unclassified)=%d/%d/%d/%d feelTransientDropouts=%d feelGridRejected=%d layerAgreement=%.2f family=%s pending=%d phaseLockQuality=%.2f phaseErrorMs=%.1f onset=%.2f energy=%.2f analyzerReady=%s",
			if assetId ~= "" then assetId else "unknown", trackGeneration, bpm, bpmConfidence,
			if bpmDetected then "audio-confirmed" else "seed/warming", candidateText, rawCandidateConfidence, priorBPM, pendingTempoConfidence, tempoFamily,
			rhythmicFeel, rhythmicFeelConfidence, #feelOnsetIntervals,
			feelDoubleTimeVotes, feelOnBeatVotes, feelHalfTimeVotes, feelUnclassifiedIntervals,
			feelTransientDropouts, feelGridRejected, tempoLayerAgreement, feelFamily,
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
