--!strict
-- ServerStorage/ClubNeon_LocalDiagnosticsBridge.lua
-- Owns the server-local admin authorization adapters and diagnostics/replay endpoint.

local DiagnosticsBridge = {}

function DiagnosticsBridge.initialize(deps: {[string]: any})
	local ControllerFunctions = deps.ControllerFunctions
	local Players = deps.Players
	local ServerStorage: ServerStorage = deps.ServerStorage
	local remotes: Folder = deps.remotes
	local purchaseDiagnostics = deps.purchaseDiagnostics
	local nowPlaying = deps.nowPlaying
	local queue = deps.queue
	local CONFIG = deps.CONFIG
	local audioState = deps.audioState

	ControllerFunctions.adminBridgeGlobalCall = function(name: string, ...: any): (boolean, any, any)
		local invoked, accepted, value, detail = ControllerFunctions.globalInvoke(name, ...)
		if not invoked then return false, "Global security service is unavailable." end
		if name == "GetGlobalAudit" then
			if typeof(accepted) == "table" then return true, accepted end
			return false, if typeof(value) == "string" then value else "Security audit log is unavailable."
		end
		if accepted ~= true then
			return false, if typeof(value) == "string" then value else "Global security operation was rejected."
		end
		return true, if value == nil then true else value, detail
	end

	ControllerFunctions.adminBridgeAuthorize = function(caller: Player, permission: string): boolean
		if typeof(caller) ~= "Instance" or not caller:IsA("Player") or caller.Parent ~= Players then
			return false
		end
		local actorUserId = caller.UserId
		local invoked, allowed = ControllerFunctions.globalInvoke("AuthorizeGlobalAction", actorUserId, permission)
		return caller.Parent == Players and caller.UserId == actorUserId
			and invoked and allowed == true
	end

	ControllerFunctions.adminBridgeReportSignal = function(caller: Player, signal: string, detail: string)
		pcall(ControllerFunctions.globalInvoke, "ReportSignal", caller.UserId, signal, detail)
	end

	local endpoint = ServerStorage:FindFirstChild("GetClubMusicLocalDiagnostics")
	if endpoint and not endpoint:IsA("BindableFunction") then
		endpoint:Destroy()
		endpoint = nil
	end
	if not endpoint then
		endpoint = Instance.new("BindableFunction")
		endpoint.Name = "GetClubMusicLocalDiagnostics"
		endpoint.Parent = ServerStorage
	end
	local diagnosticsBindable = endpoint :: BindableFunction

	ControllerFunctions.inspectPlaybackQuality = function()
		if nowPlaying.trackId == "" then return {state = "Idle"} end
		if nowPlaying.soundId == "" then return {state = "SilentCatalogTrack"} end
		local snapshotOk, snapshot = pcall(ControllerFunctions.getAudioSnapshot)
		if not snapshotOk or typeof(snapshot) ~= "table" or snapshot.kind == "Unavailable" then
			return {state = "Unavailable", reason = "AudioInstanceMissing"}
		end
		local elapsed = if ControllerFunctions.isFiniteNumber(nowPlaying.elapsed) then math.max(0, nowPlaying.elapsed) else 0
		local isReady = snapshot.ready == true
		local isPlaying = snapshot.playing == true
		local length = if isReady and ControllerFunctions.isFiniteNumber(snapshot.length) then math.max(0, snapshot.length) else 0
		if isPlaying then
			return {state = "Playing", backend = snapshot.kind, elapsed = elapsed, loaded = isReady, length = length}
		end
		if snapshot.paused == true then
			return {state = "Paused", backend = snapshot.kind, elapsed = elapsed, loaded = isReady, length = length}
		end
		if isReady and length > 0 then
			return {state = "StoppedAfterLoad", backend = snapshot.kind, elapsed = elapsed, loaded = true, length = length}
		end
		return {state = "BufferingOrStopped", backend = snapshot.kind, elapsed = elapsed, loaded = isReady, length = length}
	end

	diagnosticsBindable.OnInvoke = function()
		local audioSnapshot = nil
		if type(ControllerFunctions.getAudioSnapshot) == "function" then
			local ok, result = pcall(ControllerFunctions.getAudioSnapshot)
			if ok and typeof(result) == "table" then audioSnapshot = result end
		end
		local playbackQuality = nil
		local qualityOk, qualityResult = pcall(ControllerFunctions.inspectPlaybackQuality)
		if qualityOk and typeof(qualityResult) == "table" then playbackQuality = qualityResult end
		return {
			state = if remotes:GetAttribute("Ready") == true then "Healthy" else "Starting",
			scope = "ServerLocal",
			purchase = table.clone(purchaseDiagnostics.PurchaseStats),
			moderation = table.clone(purchaseDiagnostics.ModerationStats),
			playback = {
				backend = if typeof(audioSnapshot) == "table" then tostring(audioSnapshot.kind or "Unavailable") else "Unavailable",
				playing = typeof(audioSnapshot) == "table" and audioSnapshot.playing == true,
				paused = typeof(audioSnapshot) == "table" and audioSnapshot.paused == true,
				qualityState = if typeof(playbackQuality) == "table" then tostring(playbackQuality.state or "Unknown") else "Unavailable",
				qualityReason = if typeof(playbackQuality) == "table" and typeof(playbackQuality.reason) == "string" then playbackQuality.reason else "",
				qualityBackend = if typeof(playbackQuality) == "table" and typeof(playbackQuality.backend) == "string" then playbackQuality.backend else "",
				qualityLoaded = typeof(playbackQuality) == "table" and playbackQuality.loaded == true,
				qualityLength = typeof(playbackQuality) == "table" and ControllerFunctions.isFiniteNumber(playbackQuality.length) and math.max(0, playbackQuality.length) or 0,
				queueDepth = #queue,
				globalPlaybackSync = {
					enabled = ControllerFunctions.globalPlaybackSyncState.enabled == true,
					isLeader = ControllerFunctions.globalPlaybackSyncState.isLeader == true,
					leaderJobId = ControllerFunctions.globalPlaybackSyncState.leaderJobId,
					authorityReady = ControllerFunctions.globalPlaybackSyncState.authorityReady == true,
					localQueueIsolated = true,
				},
				modernBackendConfigured = CONFIG.UseModernAudioBackend == true,
				modernBackendStartSucceeded = audioState.modernBackendStartSucceeded,
				modernBackendStartFailureCount = audioState.modernBackendStartFailureCount,
				activeSourceKind = audioState.activeAudioSource.kind,
			},
			updatedAt = os.time(),
		}
	end

	ControllerFunctions.recordAudioValidationSignal = function(player: Player, signal: string)
		local invoked, accepted = ControllerFunctions.globalInvoke("ReportSignal", player.UserId, signal)
		if invoked and accepted == true then return end
		local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
		if replay and replay:IsA("BindableFunction") then
			pcall(function()
				replay:Invoke("Record", signal, player.UserId, 0, "Warning", "ClubMusicAudioValidation", {})
			end)
		end
	end

	ControllerFunctions.recordAudioReplayEvent = function(player: Player, eventType: string)
		local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
		if replay and replay:IsA("BindableFunction") then
			pcall(function()
				replay:Invoke("Record", eventType, player.UserId, 0, "Info", "ClubMusicAudioValidation", {})
			end)
		end
	end

	ControllerFunctions.recordTextReplayEvent = function(player: Player, eventType: string)
		local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
		if replay and replay:IsA("BindableFunction") then
			pcall(function()
				replay:Invoke("Record", eventType, player.UserId, 0, "Info", "ClubMusicTextValidation", {})
			end)
		end
	end
end

return DiagnosticsBridge
