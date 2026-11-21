--!strict
-- Controller-owned modern AudioPlayer source contract, startup, recovery and cleanup.
-- Mutable playback state is shared through the controller-owned state table.
return function(context: {[string]: any})
	local ControllerFunctions = context.ControllerFunctions
	local SoundService = context.SoundService
	local CONFIG = context.CONFIG
	local state = context.state
	local getNowPlaying = context.getNowPlaying

local activeAudioPlayingConnection: RBXScriptConnection? = nil
ControllerFunctions.refreshActiveMusicSoundCount = function()
	local snapshot = ControllerFunctions.getAudioSnapshot and ControllerFunctions.getAudioSnapshot() or nil
	local playing = typeof(snapshot) == "table" and snapshot.playing == true
	SoundService:SetAttribute("ActiveMusicSoundCount", if playing then 1 else 0)
end
ControllerFunctions.bindActiveAudioPlayingSignal = function()
	if activeAudioPlayingConnection then
		activeAudioPlayingConnection:Disconnect()
		activeAudioPlayingConnection = nil
	end
	local source = state.activeAudioSource
	-- Publish the active output type. Unavailable means modern startup/recovery
	-- failed; no legacy source is selected.
	local sourceKind = if source.kind == "Backend" and source.backend then "AudioPlayer" else "Unavailable"
	SoundService:SetAttribute("ClubMusicAudioSourceKind", sourceKind)
	local signalInstance = if source.kind == "Backend" and source.backend then source.backend:GetPlayer() else nil
	if typeof(signalInstance) == "Instance" then
		local ok, signal = pcall(function() return signalInstance:GetPropertyChangedSignal("IsPlaying") end)
		if ok and signal then
			activeAudioPlayingConnection = signal:Connect(ControllerFunctions.refreshActiveMusicSoundCount)
		end
	end
	ControllerFunctions.refreshActiveMusicSoundCount()
end

-- Prevent out-of-order persistence replies from an earlier pause/resume/restart
-- overwriting a newer local control action on the same track.
local playbackControlRequestId = 0

-- One controller-owned source contract: modern AudioPlayer or unavailable.
ControllerFunctions.getAudioSnapshot = function()
	local source = state.activeAudioSource
	if typeof(source) ~= "table" then
		return { kind = "Unavailable", ready = false, playing = false, paused = state.playbackPaused, position = 0, length = 0, asset = "" }
	end
	if source.kind == "Backend" and source.backend then
		local backend = source.backend
		local function read(methodName: string, fallback: any)
			local ok, value = pcall(function() return backend[methodName](backend) end)
			return if ok then value else fallback
		end
		local asset = read("GetAsset", "")
		if typeof(asset) ~= "string" then asset = "" end
		if asset == "" then
			local player = read("GetPlayer", nil)
			if player then pcall(function() asset = tostring(player.Asset) end) end
		end
		local function finiteNonNegative(value: any): number
			local numberValue = tonumber(value)
			if numberValue == nil or numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then return 0 end
			return math.max(0, numberValue)
		end
		return {
			kind = "AudioPlayer",
			ready = read("IsReady", false) == true,
			playing = read("IsPlaying", false) == true,
			paused = state.playbackPaused,
			position = finiteNonNegative(read("GetTimePosition", 0)),
			length = finiteNonNegative(read("GetTimeLength", 0)),
			asset = asset,
		}
	end
	return { kind = "Unavailable", ready = false, playing = false, paused = state.playbackPaused, position = 0, length = 0, asset = "" }
end
-- Per-track loudness trim for the 11 Club Exclusives. A 1.5 multiplier is a
-- first-pass +50% boost. It is applied before the fader so crossfade gain
-- remains independent of each player's private output preference.
local TRACK_VOLUME_TRIM_OVERRIDES: {[string]: number} = {
	["custom-100919684616729"] = 1.5, -- CROWN OF THE NIGHT
	["custom-99973341792058"] = 1.5, -- Midnight Lucid
	["custom-137104933242988"] = 1.5, -- Empire of Stone
	["custom-84266261446965"] = 1.5, -- Anvil_of_Ruin
	["custom-85420661204078"] = 1.5, -- Code in the Smoke
	["custom-134987433423089"] = 1.5, -- Rich Lifestyle
	["custom-92952858514774"] = 1.5, -- Metallic Chaos Within Magic Theory
	["custom-117388170134707"] = 1.5, -- Steel Collision
	["custom-86468432953052"] = 1.5, -- Fallen Star Blues
	["custom-126526272193872"] = 1.5, -- Winter Between Us
	["custom-96399574470852"] = 1.5, -- Terminal Frequency
}
local function getTrackVolumeTrim(trackId: string?): number
	if typeof(trackId) ~= "string" then return 1 end
	local configured = TRACK_VOLUME_TRIM_OVERRIDES[trackId]
	if not ControllerFunctions.isFiniteNumber(configured) or configured <= 0 then return 1 end
	-- AudioPlayer.Volume supports values above 1, but
	-- clamp the shared per-track trim to their documented 0..10 range.
	return math.clamp(configured, 0.01, 10)
end
ControllerFunctions.getTrackVolumeTrim = getTrackVolumeTrim

-- Gain is owned by the active source. Keep the crossfade/profile contract
-- backend-neutral so a transition never assumes the outgoing deck is at 100%.
ControllerFunctions.getAudioGain = function(sourceOverride: any?): (boolean, number)
	local source = sourceOverride or state.activeAudioSource
	if typeof(source) ~= "table" then return false, 0 end
	if source.kind == "Backend" and source.backend then
		local ok, value = pcall(function() return source.backend:GetGain() end)
		if not ok or typeof(value) ~= "number" or not ControllerFunctions.isFiniteNumber(value)
			or value < 0 or value > 1 then return false, 0 end
		return true, value
	end
	return false, 0
end
ControllerFunctions.setAudioGain = function(value: number, sourceOverride: any?): boolean
	if not ControllerFunctions.isFiniteNumber(value) or value < 0 or value > 1 then return false end
	local source = sourceOverride or state.activeAudioSource
	if typeof(source) ~= "table" then return false end
	if source.kind == "Backend" and source.backend then
		local ok, result = pcall(function() return source.backend:SetGain(value) end)
		return ok and result ~= false
	end
	return false
end

-- Track-specific playback-rate corrections. CROWN OF THE NIGHT's uploaded
-- source is already time-stretched by 9% with pitch preserved, so Roblox must
-- play that asset at normal speed rather than applying another 1.09 multiplier.
local TRACK_PLAYBACK_SPEED_OVERRIDES: {[string]: number} = {
	["custom-100919684616729"] = 1.0,
}
ControllerFunctions.setAudioPlaybackSpeed = function(value: number): boolean
	if not ControllerFunctions.isFiniteNumber(value) or value < 0.5 or value > 2 then return false end
	local source = state.activeAudioSource
	if typeof(source) ~= "table" then return false end
	if source.kind == "Backend" and source.backend then
		local ok, result = pcall(function() return source.backend:SetPlaybackSpeed(value) end)
		return ok and result ~= false
	end
	return false
end
ControllerFunctions.applyTrackPlaybackSpeed = function(trackId: string): boolean
	local speed = TRACK_PLAYBACK_SPEED_OVERRIDES[trackId]
	if speed == nil then return true end
	return ControllerFunctions.setAudioPlaybackSpeed(speed)
end

-- A controller mutation must not invalidate the source/revision captured by
-- an in-flight crossfade. Cancel first so the coordinator restores the outgoing
-- gain while its ownership guard is still valid; refuse the mutation if that
-- restoration cannot be completed safely.
local function cancelCrossfadeBeforeAudioMutation(reason: string): boolean
	local managers = ControllerFunctions.ChildManagers
	local crossfade = managers and managers.Crossfade
	if not crossfade or (not crossfade.active and not crossfade.starting) then return true end
	if typeof(ControllerFunctions.cancelAudioTransition) ~= "function" then return false end
	return ControllerFunctions.cancelAudioTransition(reason) == true
end

ControllerFunctions.setAudioAsset = function(asset: string)
	if not cancelCrossfadeBeforeAudioMutation("set-audio-asset") then
		return false, "Active crossfade could not be safely cancelled before changing the audio asset."
	end
	state.audioSourceRevision += 1
	local source = state.activeAudioSource
	if source.kind == "Backend" then return source.backend:SetAsset(asset) end
	return false, "No active audio source is available."
end
ControllerFunctions.seekAudio = function(position: number)
	if state.audioReloadInProgress then return false, "Audio controls are temporarily locked while the current track reloads." end
	if not cancelCrossfadeBeforeAudioMutation("seek-audio") then
		return false, "Active crossfade could not be safely cancelled before seeking."
	end
	state.audioSourceRevision += 1
	local source = state.activeAudioSource
	if source.kind == "Backend" then return source.backend:Seek(position) end
	return false, "No active audio source is available."
end
ControllerFunctions.playAudio = function()
	if state.audioReloadInProgress then return false, "Audio controls are temporarily locked while the current track reloads." end
	if not cancelCrossfadeBeforeAudioMutation("play-audio") then
		return false, "Active crossfade could not be safely cancelled before playback restart."
	end
	state.audioSourceRevision += 1
	local source = state.activeAudioSource
	if source.kind == "Backend" then return source.backend:Play() end
	return false, "No active audio source is available."
end
ControllerFunctions.stopAudio = function()
	if not cancelCrossfadeBeforeAudioMutation("stop-audio") then
		return false, "Active crossfade could not be safely cancelled before stopping playback."
	end
	state.audioSourceRevision += 1
	local source = state.activeAudioSource
	if source.kind == "Backend" then return source.backend:Stop() end
	return true, nil
end
ControllerFunctions.pauseAudio = function()
	if state.audioReloadInProgress then return false, "Audio controls are temporarily locked while the current track reloads." end
	if not cancelCrossfadeBeforeAudioMutation("pause-audio") then
		return false, "Active crossfade could not be safely cancelled before pausing playback."
	end
	state.audioSourceRevision += 1
	local source = state.activeAudioSource
	if source.kind == "Backend" then return source.backend:Pause() end
	return false, "No active audio source is available."
end
ControllerFunctions.resumeAudio = function()
	if state.audioReloadInProgress then return false, "Audio controls are temporarily locked while the current track reloads." end
	if not cancelCrossfadeBeforeAudioMutation("resume-audio") then
		return false, "Active crossfade could not be safely cancelled before resuming playback."
	end
	state.audioSourceRevision += 1
	local source = state.activeAudioSource
	if source.kind == "Backend" then return source.backend:Resume() end
	return false, "No active audio source is available."
end

-- Keep failed backend retirements reachable and retry transient Destroy failures.
-- A backend may be retired only after controller ownership has moved elsewhere.
local retiredAudioBackends: {[any]: string} = {}
local function retireAudioBackend(backend: any, reason: string): boolean
	if typeof(backend) ~= "table" then return true end
	if retiredAudioBackends[backend] == "retrying" then return false end
	local ok, result, detail = pcall(function()
		return backend:Cleanup()
	end)
	if ok and result ~= false then
		retiredAudioBackends[backend] = nil
		return true
	end
	retiredAudioBackends[backend] = "retrying"
	warn("[ClubMusic][AudioBackend] Backend retirement failed (" .. reason .. "): " .. tostring(detail or result))
	task.spawn(function()
		for attempt = 1, 3 do
			task.wait(attempt)
			local retryOk, retryResult, retryDetail = pcall(function()
				return backend:Cleanup()
			end)
			if retryOk and retryResult ~= false then
				retiredAudioBackends[backend] = nil
				return
			end
			warn("[ClubMusic][AudioBackend] Backend cleanup retry " .. tostring(attempt)
				.. " failed (" .. reason .. "): " .. tostring(retryDetail or retryResult))
		end
		-- Keep the reference in the registry for diagnosis and a later retry.
		retiredAudioBackends[backend] = "pending"
	end)
	return false
end

-- Final teardown drain for controller-retired backends. Normal retirement uses
-- bounded asynchronous retries; shutdown waits for those attempts, then makes a
-- final bounded pass over entries explicitly marked pending.
local function drainRetiredAudioBackends(reason: string): boolean
	local deadline = os.clock() + 6.5
	while os.clock() < deadline do
		local retrying = false
		for _, status in pairs(retiredAudioBackends) do
			if status == "retrying" then retrying = true; break end
		end
		if not retrying then break end
		task.wait(0.1)
	end

	local allClean = true
	for backend, status in pairs(retiredAudioBackends) do
		if status == "pending" then
			retiredAudioBackends[backend] = "retrying"
			local cleaned = false
			for attempt = 1, 3 do
				if attempt > 1 then task.wait(attempt) end
				local ok, result, detail = pcall(function()
					return backend:Cleanup()
				end)
				if ok and result ~= false then
					retiredAudioBackends[backend] = nil
					cleaned = true
					break
				end
				warn("[ClubMusic][AudioBackend] Final cleanup retry " .. tostring(attempt)
					.. " failed (" .. reason .. "): " .. tostring(detail or result))
			end
			if not cleaned then
				retiredAudioBackends[backend] = "pending"
				allClean = false
			end
		elseif status == "retrying" then
			allClean = false
		end
	end
	return allClean
end

-- Initialize source telemetry/playing-count for the unavailable pre-track state.
ControllerFunctions.bindActiveAudioPlayingSignal()

ControllerFunctions.stopServerMusic = function()
	pcall(function() ControllerFunctions.stopAudio() end)
	ControllerFunctions.refreshActiveMusicSoundCount()
end

-- Modern-only startup. If module loading, decoding, or playback verification
-- fails, leave the source unavailable and report the failure; never start legacy
-- AudioPlayer. A monotonically increasing token fences late decoder completions.
ControllerFunctions.startServerMusic = function(soundId: any)
	local nowPlaying = getNowPlaying()
	local retiredSource = state.activeAudioSource
	ControllerFunctions.stopServerMusic()
	-- New-track startup owns a fresh candidate. Mark the source unavailable while
	-- it loads, and retire the stopped previous backend so the controller never
	-- reports a stopped output as the active source.
	if retiredSource.kind == "Backend" and retiredSource.backend then
		retireAudioBackend(retiredSource.backend, "new track startup")
	end
	state.activeAudioSource = { kind = "Unavailable" }
	ControllerFunctions.bindActiveAudioPlayingSignal()
	state.modernAudioStartToken += 1
	local startToken = state.modernAudioStartToken
	local startRevision = state.audioSourceRevision
	if typeof(soundId) ~= "string" or #soundId > 64
		or not string.match(soundId, "^rbxassetid://%d+$") then
		ControllerFunctions.setAudioAsset("")
		return
	end

	local trackId = tostring(nowPlaying and nowPlaying.trackId or "")
	local expectedTransitionToken = state.audioTransitionTrackToken
	local trim = getTrackVolumeTrim(trackId)
	local playbackSpeed = TRACK_PLAYBACK_SPEED_OVERRIDES[trackId] or 1
	local wasPaused = state.playbackPaused == true

	local function isCurrentStart(): boolean
		return state.modernAudioStartToken == startToken
			and state.audioSourceRevision == startRevision
			and state.audioTransitionTrackToken == expectedTransitionToken
			and tostring(nowPlaying and nowPlaying.trackId or "") == trackId
			and tostring(nowPlaying and nowPlaying.soundId or "") == soundId
			and state.playbackPaused == wasPaused
			and state.activeAudioSource.kind == "Unavailable"
	end

	local function reportModernStartupFailure(reason: string?)
		if not isCurrentStart() then return end
		state.modernBackendStartFailureCount += 1
		warn("[ClubMusic][AudioBackend] Modern-only startup failed; no legacy fallback was started: "
			.. tostring(reason or "UseModernAudioBackend is disabled."))
	end

	if not CONFIG.UseModernAudioBackend then
		reportModernStartupFailure("UseModernAudioBackend is disabled.")
		return
	end

	task.spawn(function()
		local candidate: any = nil
		local function discardCandidate()
			if candidate then
				pcall(function() candidate:Stop() end)
				retireAudioBackend(candidate, "modern startup candidate discarded")
				candidate = nil
			end
		end
		local ok, failure = pcall(function()
			local backendModule = ControllerFunctions.findAudioModule("ClubMusicAudioBackend")
			if not backendModule or not backendModule:IsA("ModuleScript") then
				error("Modern backend ModuleScript is missing.")
			end
			local BackendClass = require(backendModule)
			if typeof(BackendClass) ~= "table" or typeof(BackendClass.new) ~= "function" then
				error("Modern backend module has an invalid constructor.")
			end
			candidate = BackendClass.new({
				Name = "ClubMusicMainAudioBackend",
				Parent = SoundService,
				Volume = math.clamp(trim, 0.01, 10),
				PlaybackSpeed = playbackSpeed,
				InitialGain = 0,
			})
			if typeof(candidate) ~= "table" then error("Modern backend could not be constructed.") end
			local assetOk, assetError = candidate:SetAsset(soundId)
			if assetOk ~= true then error(tostring(assetError or "Modern backend rejected the track asset.")) end

			local readyDeadline = os.clock() + 8
			local ready = false
			repeat
				if not isCurrentStart() then return "stale" end
				local readiness = candidate:GetReadinessSnapshot()
				ready = typeof(readiness) == "table"
					and readiness.ready == true
					and readiness.asset == soundId
					and ControllerFunctions.isFiniteNumber(readiness.length)
					and readiness.length > 0
				if not ready then task.wait(0.1) end
			until ready or os.clock() >= readyDeadline
			if not ready then error("Modern AudioPlayer decoder did not become ready within 8 seconds.") end

			local startPosition = math.max(0, tonumber(nowPlaying and nowPlaying.elapsed) or 0)
			local played, playError = candidate:Play(nil, startPosition)
			if played ~= true then error(tostring(playError or "Modern AudioPlayer failed to start.")) end
			local playDeadline = os.clock() + 2
			local playing = false
			repeat
				if not isCurrentStart() then return "stale" end
				playing = candidate:IsPlaying() == true
				if not playing then task.wait(0.05) end
			until playing or os.clock() >= playDeadline
			if not playing then error("Modern AudioPlayer did not enter the playing state.") end
			local finalReadiness = candidate:GetReadinessSnapshot()
			if typeof(finalReadiness) ~= "table" or finalReadiness.ready ~= true
				or finalReadiness.asset ~= soundId or finalReadiness.length <= 0 then
				error("Modern AudioPlayer readiness changed during startup.")
			end
			if wasPaused then
				local paused, pauseError = candidate:Pause()
				if paused ~= true then error(tostring(pauseError or "Modern AudioPlayer could not preserve pause state.")) end
			end
			if not isCurrentStart() then return "stale" end
			local gainOk, gainError = candidate:SetGain(1)
			if gainOk ~= true then error(tostring(gainError or "Modern AudioPlayer gain could not be enabled.")) end

			local previousSource = state.activeAudioSource
			state.activeAudioSource = { kind = "Backend", backend = candidate }
			candidate = nil
			ControllerFunctions.bindActiveAudioPlayingSignal()
			if previousSource.kind == "Backend" and previousSource.backend then
				retireAudioBackend(previousSource.backend, "modern startup source replacement")
			end
			state.modernBackendStartSucceeded = true
			state.modernBackendStartFailureCount = 0
			print("[ClubMusic][AudioBackend] Modern AudioPlayer started as the primary track source.")
		end)
		discardCandidate()
		if ok and failure == "stale" then
			-- Expected cancellation: never warn or invoke legacy recovery for an
			-- obsolete track. If the same startup still owns the current track but
			-- its playhead or pause state changed, retry with the latest state.
			if state.modernAudioStartToken == startToken
				and state.activeAudioSource.kind == "Unavailable"
				and state.audioTransitionTrackToken == expectedTransitionToken
				and tostring(nowPlaying and nowPlaying.trackId or "") == trackId
				and tostring(nowPlaying and nowPlaying.soundId or "") == soundId
				and (state.audioSourceRevision ~= startRevision or state.playbackPaused ~= wasPaused) then
				task.defer(ControllerFunctions.startServerMusic, soundId)
			end
		elseif not ok then
			-- A seek/pause or other controller action may legitimately revise the
			-- source while the candidate is loading. Retry only if this startup
			-- still owns the same track transition, using the latest controller state.
			if state.modernAudioStartToken == startToken
				and state.activeAudioSource.kind == "Unavailable"
				and state.audioTransitionTrackToken == expectedTransitionToken
				and tostring(nowPlaying and nowPlaying.trackId or "") == trackId
				and tostring(nowPlaying and nowPlaying.soundId or "") == soundId
				and (state.audioSourceRevision ~= startRevision or state.playbackPaused ~= wasPaused) then
				task.defer(ControllerFunctions.startServerMusic, soundId)
			else
				reportModernStartupFailure(tostring(failure))
			end
		end
	end)
end

-- Restart the active source in place through the normalized controller contract.
-- Avoid reselecting the asset and reapplying track gain/speed on every restart.
ControllerFunctions.restartServerMusic = function(soundId: any): (boolean, string?)
	local nowPlaying = getNowPlaying()
	if typeof(soundId) ~= "string" or #soundId > 64
		or not string.match(soundId, "^rbxassetid://%d+$") then
		return false, "The current track has no valid audio asset."
	end
	-- Read only the two properties restart actually needs. A full snapshot also
	-- queries readiness, duration, and playhead, adding work to a latency-sensitive
	-- button path without changing the restart decision.
	local snapshotOk, snapshot = pcall(ControllerFunctions.getAudioSnapshot)
	if not snapshotOk or typeof(snapshot) ~= "table" then
		return false, "The current audio source state could not be read safely."
	end
	if snapshot.kind == "Unavailable" then
		-- A restart is an explicit request to recover and resume the selected
		-- track. Publish its intended start state before task.spawn can observe it.
		nowPlaying.elapsed = 0
		state.playbackPaused = false
		ControllerFunctions.startServerMusic(soundId)
		return true, nil
	end
	local sourceAsset = tostring(snapshot.asset or "")
	local sourcePlaying = snapshot.playing == true
	if sourceAsset ~= soundId then
		ControllerFunctions.startServerMusic(soundId)
		return true, nil
	end

	-- Reset the active playhead in place instead of Stop -> Seek -> Play.
	-- Stopping a loaded source can force the decoder to reinitialize and adds
	-- avoidable latency. If the source was paused/stopped, start it after seeking.
	local seekOk, seekResult, seekError = pcall(ControllerFunctions.seekAudio, 0)
	if not seekOk or seekResult == false then
		return false, tostring(seekError or seekResult or "The current audio source could not be reset.")
	end
	if sourcePlaying ~= true then
		local playOk, playResult, playError = pcall(ControllerFunctions.playAudio)
		if not playOk or playResult == false then
			return false, tostring(playError or playResult or "The current audio source could not be restarted.")
		end
	end
	return true, nil
end

-- Rebuild a failed modern deck without falling back to legacy Sound playback.
-- The queue and authoritative track clock remain untouched; only the audio graph
-- is replaced after the new AudioPlayer is loaded, positioned, and verified.
local function rebuildModernAudioBackend(source: any, asset: string, position: number,
	expectedTrackId: string, expectedTransitionToken: number): (boolean, string?)
	local nowPlaying = getNowPlaying()
	if typeof(source) ~= "table" or source.kind ~= "Backend" or typeof(source.backend) ~= "table" then
		return false, "Modern audio recovery requires the controller-owned AudioPlayer backend."
	end
	local expectedRevision = state.audioSourceRevision
	local wasPaused = state.playbackPaused == true
	local gainOk, outgoingGain = ControllerFunctions.getAudioGain(source)
	if not gainOk then
		return false, "The active AudioPlayer gain could not be read safely; keeping the current backend unchanged."
	end
	local backendModule = ControllerFunctions.findAudioModule("ClubMusicAudioBackend")
	if not backendModule or not backendModule:IsA("ModuleScript") then
		return false, "Modern audio recovery module is unavailable."
	end
	local requireOk, BackendClass = pcall(require, backendModule)
	if not requireOk or typeof(BackendClass) ~= "table" or typeof(BackendClass.new) ~= "function" then
		return false, "Modern audio recovery module could not be loaded."
	end
	local createOk, candidate = pcall(BackendClass.new, {
		Name = "ClubMusicMainAudioBackendRecovery",
		Parent = SoundService,
		Volume = getTrackVolumeTrim(expectedTrackId),
		InitialGain = 0,
	})
	if not createOk or typeof(candidate) ~= "table" then
		return false, "A replacement modern AudioPlayer graph could not be created."
	end
	local function abandon(message: string): (boolean, string?)
		pcall(function() candidate:Stop() end)
		retireAudioBackend(candidate, "modern recovery candidate abandoned")
		return false, message
	end
	local selected, selectError = candidate:SetAsset(asset)
	if selected ~= true then return abandon(tostring(selectError or "Replacement AudioPlayer rejected the current asset.")) end
	local speed = TRACK_PLAYBACK_SPEED_OVERRIDES[expectedTrackId] or 1
	local speedSet, speedError = candidate:SetPlaybackSpeed(speed)
	if speedSet ~= true then return abandon(tostring(speedError or "Replacement AudioPlayer rejected playback speed.")) end

	local deadline = os.clock() + 8
	local readiness = nil
	repeat
		task.wait(0.1)
		local readOk, state = pcall(function() return candidate:GetReadinessSnapshot() end)
		if readOk and typeof(state) == "table" and state.ready == true
			and state.asset == asset and ControllerFunctions.isFiniteNumber(state.length) and state.length > 0 then
			readiness = state
			break
		end
	until os.clock() >= deadline
	if not readiness then return abandon("Replacement AudioPlayer did not become ready within 8 seconds.") end

	local target = math.clamp(position, 0, math.max(0, readiness.length - 0.5))
	local seeked, seekError = candidate:Seek(target)
	if seeked ~= true then return abandon(tostring(seekError or "Replacement AudioPlayer could not restore the playhead.")) end
	if wasPaused then
		local paused, pauseError = candidate:Pause()
		if paused ~= true then return abandon(tostring(pauseError or "Replacement AudioPlayer could not preserve pause state.")) end
	else
		local started, startError = candidate:Play()
		if started ~= true then return abandon(tostring(startError or "Replacement AudioPlayer could not start.")) end
		local startDeadline = os.clock() + 2
		repeat
			task.wait(0.05)
		until candidate:IsPlaying() or os.clock() >= startDeadline
		if not candidate:IsPlaying() then return abandon("Replacement AudioPlayer did not enter the playing state.") end
	end
	-- Keep the replacement deck muted throughout every yielding preparation
	-- step. Revalidate ownership immediately before restoring audible gain; the
	-- gain setter is synchronous, so no stale candidate can become audible between
	-- this final compare and the controller ownership transfer.
	if state.activeAudioSource ~= source or state.audioSourceRevision ~= expectedRevision
		or tostring(nowPlaying.trackId or "") ~= expectedTrackId
		or state.audioTransitionTrackToken ~= expectedTransitionToken
		or state.playbackPaused ~= wasPaused then
		return abandon("Playback changed while modern audio recovery was preparing.")
	end

	local gainSet, gainError = candidate:SetGain(math.clamp(outgoingGain, 0, 1))
	if gainSet ~= true then return abandon(tostring(gainError or "Replacement AudioPlayer could not restore output gain.")) end

	state.activeAudioSource = { kind = "Backend", backend = candidate }
	ControllerFunctions.bindActiveAudioPlayingSignal()
	retireAudioBackend(source.backend, "watchdog backend recovery")
	print("[ClubMusic][AudioBackend] Recovered playback with a replacement modern AudioPlayer.")
	return true, nil
end

-- Recover the current server-local audio source without changing queue ownership,
-- track identity, or the authoritative playback clock. This is deliberately blocked
-- during a crossfade so a manual recovery cannot interrupt a deck handoff.
local function performReloadServerMusic(): (boolean, string?)
	local nowPlaying = getNowPlaying()
	local asset = nowPlaying.soundId or CONFIG.SoundIds[nowPlaying.trackId] or ""
	if typeof(asset) ~= "string" or #asset > 64
		or not string.match(asset, "^rbxassetid://%d+$") then
		return false, "There is no playable audio asset for the current track."
	end
	local managers = ControllerFunctions.ChildManagers
	local crossfade = managers and managers.Crossfade
	if crossfade and crossfade.active then
		return false, "Please wait for the current crossfade to finish before reloading audio."
	end

	local source = state.activeAudioSource
	local duration = math.max(1, tonumber(nowPlaying.duration) or 1)
	local expectedTrackId = tostring(nowPlaying.trackId or "")
	local expectedTransitionToken = state.audioTransitionTrackToken
	local expectedPaused = state.playbackPaused == true

	if source.kind ~= "Backend" or not source.backend then
		-- If startup previously failed, retry the current track through the same
		-- verified modern-only startup path. startServerMusic restores the
		-- controller's saved elapsed position and pause state; it never starts Sound.
		ControllerFunctions.startServerMusic(asset)
		local startupDeadline = os.clock() + 12
		repeat
			task.wait(0.1)
			if tostring(nowPlaying.trackId or "") ~= expectedTrackId
				or state.audioTransitionTrackToken ~= expectedTransitionToken
				or state.playbackPaused ~= expectedPaused then
				return false, "The current track changed during modern audio recovery."
			end
			local recoveredSource = state.activeAudioSource
			if recoveredSource.kind == "Backend" and recoveredSource.backend then
				local stateOk, recoveredSnapshot = pcall(ControllerFunctions.getAudioSnapshot)
				local restoredState = if expectedPaused
					then typeof(recoveredSnapshot) == "table" and recoveredSnapshot.paused == true
					else typeof(recoveredSnapshot) == "table" and recoveredSnapshot.playing == true
				if stateOk and restoredState and recoveredSnapshot.asset == asset then
					return true, nil
				end
			elseif recoveredSource.kind ~= "Unavailable" then
				return false, "The audio source changed unexpectedly during modern recovery."
			end
		until os.clock() >= startupDeadline
		return false, "Modern AudioPlayer could not be restarted; no legacy fallback was started."
	end

	local snapshot = ControllerFunctions.getAudioSnapshot()
	if typeof(snapshot) ~= "table" or snapshot.kind == "Unavailable" then
		return false, "The active modern AudioPlayer is unavailable."
	end
	local expectedSourceRevision = state.audioSourceRevision
	local position = if ControllerFunctions.isFiniteNumber(snapshot.position)
		then snapshot.position else math.max(0, tonumber(nowPlaying.elapsed) or 0)
	position = math.clamp(position, 0, math.max(0, duration - 0.5))

	if source.kind == "Backend" and source.backend then
		-- AudioPlayer reload must reselect the asset and wait for its decoder;
		-- Stop/Seek/Play on the same selection is not a reliable recovery.
		local reloadCallOk, reloaded, reloadError = pcall(function()
			return source.backend:Reload(position)
		end)
		if not reloadCallOk or reloaded ~= true then
			local recovered, recoveryError = rebuildModernAudioBackend(
				source, asset, position, expectedTrackId, expectedTransitionToken
			)
			if recovered then return true, nil end
			return false, tostring(recoveryError or reloadError or reloaded or "The modern audio decoder could not be recovered.")
		end
	else
		return false, "The active modern AudioPlayer does not support reload recovery."
	end

	-- Confirm actual playback and fence out a track change that occurred while
	-- the decoder was loading. Never report success for a stale source.
	local resumeDeadline = os.clock() + 3
	repeat
		task.wait(0.1)
		if state.activeAudioSource ~= source or state.audioSourceRevision ~= expectedSourceRevision
			or tostring(nowPlaying.trackId or "") ~= expectedTrackId
			or state.audioTransitionTrackToken ~= expectedTransitionToken or state.playbackPaused then
			return false, "The current track changed during reload; no stale playback state was committed."
		end
		local stateOk, current = pcall(ControllerFunctions.getAudioSnapshot)
		local restoredState = if state.playbackPaused
			then typeof(current) == "table" and current.paused == true
			else typeof(current) == "table" and current.playing == true
		if stateOk and restoredState and current.asset == asset then
			return true, nil
		end
	until os.clock() >= resumeDeadline
	return false, "The audio source did not resume after reloading. Please try again."
end

ControllerFunctions.reloadServerMusic = function(): (boolean, string?)
	if state.audioReloadInProgress then
		return false, "An audio reload is already in progress."
	end
	state.audioReloadInProgress = true
	local callOk, recovered, recoveryError = pcall(performReloadServerMusic)
	state.audioReloadInProgress = false
	if not callOk then
		return false, "Audio reload failed safely: " .. tostring(recovered)
	end
	return recovered == true, recoveryError
end

	return {
		RetireBackend = retireAudioBackend,
		DrainRetiredBackends = drainRetiredAudioBackends,
		GetTrackVolumeTrim = getTrackVolumeTrim,
	}
end
