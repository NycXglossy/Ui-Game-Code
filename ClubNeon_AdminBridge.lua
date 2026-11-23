--!strict
-- Server-only ClubMusic/Kohl's Admin bridge. All mutable controller state and
-- authoritative services are injected; this module owns only the bridge callback.
return function(context: {[string]: any})
	local ControllerFunctions = context.ControllerFunctions
	local Players = context.Players
	local ServerStorage = context.ServerStorage
	local ALL_TRACK_IDS = context.ALL_TRACK_IDS
	local blockedUsers = context.blockedUsers
	local getDJControlModeEnabled = context.getDJControlModeEnabled
	local nowPlaying = context.nowPlaying
	local operationalDiagnosticsFormatter = context.operationalDiagnosticsFormatter
	local permissions = context.permissions
	local phase32Services = context.phase32Services
	local getPlaybackPaused = context.getPlaybackPaused
	local setPlaybackPaused = context.setPlaybackPaused
	local publishState = context.publishState
	local purchaseDiagnostics = context.purchaseDiagnostics
	local queue = context.queue
	local queueManager = context.queueManager
	local remotes = context.remotes
	local getRequestsLocked = context.getRequestsLocked
	local setRequestsLocked = context.setRequestsLocked
	local storage = context.storage

local adminBridge = ControllerFunctions.getOrCreate(ServerStorage, "BindableFunction", "ClubMusicAdminBridge") :: BindableFunction
local ADMIN_BRIDGE_ACTIONS: {[string]: string} = {
	Skip = "DJSkip",
	TogglePause = "DJPause",
	Restart = "DJRestart",
	ToggleRequestLock = "DJToggleLock",
	ClearQueue = "DJClearQueue",
}
local adminBridgeShuttingDown = false
local adminBridgeCallback = function(caller: any, operation: any, argument: any): (boolean, string)
	if adminBridgeShuttingDown then return false, "ClubMusic admin bridge is shutting down." end
	if typeof(caller) ~= "Instance" or not caller:IsA("Player") or caller.Parent ~= Players then
		return false, "A live player caller is required."
	end
	if typeof(operation) ~= "string" or #operation > 32 then
		ControllerFunctions.adminBridgeReportSignal(caller, "admin_bridge_invalid_operation", "invalid operation name")
		return false, "Invalid ClubMusic admin operation."
	end
	if not ControllerFunctions.isStaff(caller) then
		ControllerFunctions.adminBridgeReportSignal(caller, "admin_bridge_access_denied", operation)
		return false, "ClubMusic staff permission is required."
	end

	-- Phase 32: server-authorized graduated punishment and investigation operations.
	if string.sub(operation, 1, 7) == "Phase32" then
		if not phase32Services then return false, "Phase 32 moderation services are unavailable; no action was applied." end
		if typeof(argument) ~= "string" or #argument < 1 or #argument > 320 then
			return false, "A bounded command argument is required."
		end
		local rawUserId, remainder
		if operation == "Phase32History" or operation == "Phase32Risk" then
			rawUserId = string.match(argument, "^%s*(%d+)%s*$")
		else
			rawUserId, remainder = string.match(argument, "^(%d+)%s+(.+)$")
		end
		local targetUserId = tonumber(rawUserId)
		if not targetUserId or targetUserId < 1 or targetUserId % 1 ~= 0 or targetUserId > 9007199254740991 then
			return false, "Provide a valid numeric Roblox UserId."
		end
		if operation == "Phase32Warn" then
			local ok, message = phase32Services:Issue(caller, targetUserId, {kind = "Warn", reason = remainder})
			return ok, message or "Warning could not be recorded."
		elseif operation == "Phase32Restrict" then
			local featureText, reason
			if remainder then featureText, reason = string.match(remainder, "^([%w,]+)%s+(.+)$") end
			if not featureText or not reason then return false, "Use: ;cmrestrict UserId Feature[,Feature] reason" end
			local restrictions = {}
			for item in string.gmatch(featureText, "[^,]+") do table.insert(restrictions, item) end
			local ok, message = phase32Services:Issue(caller, targetUserId, {kind = "Restrict", restrictions = restrictions, reason = reason})
			return ok, message or "Restriction could not be recorded."
		elseif operation == "Phase32TempBan" then
			local secondsText, reason
			if remainder then secondsText, reason = string.match(remainder, "^(%d+)%s+(.+)$") end
			local seconds = tonumber(secondsText)
			if not seconds or not reason then return false, "Use: ;cmtempban UserId Seconds reason" end
			local ok, message = phase32Services:Issue(caller, targetUserId, {kind = "TempBan", durationSeconds = seconds, reason = reason})
			return ok, message or "Temporary ban could not be applied."
		elseif operation == "Phase32PermanentBan" or operation == "Phase32PermanentBanAlts" then
			if not remainder then return false, "A permanent-ban reason is required." end
			local propagate = operation == "Phase32PermanentBanAlts"
			local ok, message = phase32Services:Issue(caller, targetUserId, {
				kind = "PermanentBan", reason = remainder,
				propagateAltAccounts = propagate, confirmAltPropagation = propagate,
			})
			return ok, message or "Permanent ban could not be applied."
		elseif operation == "Phase32Unban" then
			if not remainder then return false, "An unban reason is required." end
			return phase32Services:Unban(caller, targetUserId, remainder)
		elseif operation == "Phase32Unrestrict" then
			if not remainder then return false, "A restriction-reversal reason is required." end
			return phase32Services:RevokeRestrictions(caller, targetUserId, remainder)
		elseif operation == "Phase32History" then
			local ok, history = phase32Services:GetHistory(caller, targetUserId, 10)
			if not ok or typeof(history) ~= "table" then return false, "Moderation history is unavailable or access was denied." end
			if #history == 0 then return true, "No retained moderation history for UserId " .. tostring(targetUserId) .. "." end
			local lines = {"Phase 32 moderation history for UserId " .. tostring(targetUserId) .. ":"}
			for index, item in ipairs(history) do
				if index > 10 then break end
				local stamp = if typeof(item.at) == "number" then os.date("!%Y-%m-%d %H:%M UTC", item.at) else "Unknown time"
				local detail = if typeof(item.category) == "string" then " | category " .. string.sub(item.category, 1, 48) else ""
				if typeof(item.evidenceReference) == "string" then detail ..= " | evidence " .. string.sub(item.evidenceReference, 1, 64) end
				table.insert(lines, string.format("%s | %s | %s | case %s | actor %d%s",
					stamp, tostring(item.kind or "Unknown"), tostring(item.status or "Unknown"),
					string.sub(tostring(item.caseId or "?"), 1, 36), tonumber(item.actorUserId) or 0, detail))
			end
			return true, string.sub(table.concat(lines, "\n"), 1, 1600)
		elseif operation == "Phase32Risk" then
			local ok, summary = phase32Services:GetRiskSignals(caller, targetUserId)
			if not ok or typeof(summary) ~= "table" then return false, "Account-risk review requires IncidentResponse and available verified history." end
			local lines = {string.format("Advisory account-risk review | UserId %d | score %d/100", targetUserId, summary.score or 0)}
			for _, signal in ipairs(summary.signals or {}) do
				local detail = if typeof(signal.category) == "string" then " | " .. signal.category else ""
				if typeof(signal.eventCount) == "number" then detail ..= " | events " .. tostring(signal.eventCount) end
				if typeof(signal.accountAgeDays) == "number" then detail ..= " | account age " .. tostring(signal.accountAgeDays) .. "d" end
				table.insert(lines, string.format("%s | %s%s", tostring(signal.type), tostring(signal.confidence), detail))
			end
			table.insert(lines, "Account linkage: " .. tostring(summary.accountLinkage))
			table.insert(lines, "No automatic punishment is applied by this score.")
			return true, string.sub(table.concat(lines, "\n"), 1, 1500)
		end
		return false, "Unknown Phase 32 moderation operation."
	end

	-- Read-only status and queue inspection do not enter the action handler or
	-- consume mutation cooldowns. Global inspection refreshes the authoritative mirror.
	if operation == "Status" then
		local currentTitle = if typeof(nowPlaying.title) == "string" and nowPlaying.title ~= "" then nowPlaying.title else "Nothing playing"
		local currentArtist = if typeof(nowPlaying.artist) == "string" then nowPlaying.artist else ""
		local playbackLabel = if getPlaybackPaused() then "PAUSED" else "PLAYING"
		local requestLabel = if getRequestsLocked() then "EMERGENCY LOCK" elseif getDJControlModeEnabled() then "DJ CONTROL (CURRENT DJ ONLY)" else "OPEN"
		local queueCount = #queue
		local elapsed = math.max(0, math.floor(tonumber(nowPlaying.elapsed) or 0))
		local duration = math.max(0, math.floor(tonumber(nowPlaying.duration) or 0))
		local trackLabel = currentTitle .. (if currentArtist ~= "" then " — " .. currentArtist else "")
		return true, string.sub(string.format("ClubMusic: %s | %s | Requests %s | Local queue %d | %ds/%ds", trackLabel, playbackLabel, requestLabel, queueCount, elapsed, duration), 1, 450)
	end
	if operation == "DJSessionStatus" then
		local manager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.DJSession
		if not manager then return false, "DJ session module is not installed in ServerStorage.ClubMusicAudioModules." end
		local state = manager:GetState()
		local current = state.current
		if not current then return true, "No DJ session is currently active." end
		return true, string.sub(string.format("Active DJ session: %s (UserId %d).", tostring(current.name), current.userId), 1, 180)
	end
	if operation == "DJSessionStart" then
		local manager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.DJSession
		if not manager then return false, "DJ session module is not installed in ServerStorage.ClubMusicAudioModules." end
		local started, sessionOrMessage = manager:Start(caller)
		if not started then return false, tostring(sessionOrMessage) end
		caller:SetAttribute("ClubMusicActiveDJSession", true)
		return true, "DJ session started for " .. caller.Name .. "."
	end
	if operation == "DJSessionHandoff" then
		local manager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.DJSession
		if not manager then return false, "DJ session module is not installed in ServerStorage.ClubMusicAudioModules." end
		if typeof(argument) ~= "string" or #argument < 1 or #argument > 16 or not string.match(argument, "^%d+$") then
			return false, "Use ;cmdjhandoff with the target staff member's numeric UserId."
		end
		local targetUserId = tonumber(argument)
		if not targetUserId or targetUserId < 1 or targetUserId % 1 ~= 0 or targetUserId > 9007199254740991 then
			return false, "A valid target UserId is required."
		end
		local target = Players:GetPlayerByUserId(targetUserId)
		if not target or target.Parent ~= Players then return false, "The target player must be connected to this server." end
		if not ControllerFunctions.isStaff(target) then return false, "The target must have ClubMusic staff permissions." end
		local handedOff, sessionOrMessage = manager:Handoff(caller, target)
		if not handedOff then return false, tostring(sessionOrMessage) end
		caller:SetAttribute("ClubMusicActiveDJSession", false)
		target:SetAttribute("ClubMusicActiveDJSession", true)
		return true, "DJ session handed off to " .. target.Name .. "."
	end
	if operation == "DJSessionEnd" then
		local manager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.DJSession
		if not manager then return false, "DJ session module is not installed in ServerStorage.ClubMusicAudioModules." end
		local ended, message = manager:End(caller)
		if not ended then return false, tostring(message) end
		caller:SetAttribute("ClubMusicActiveDJSession", false)
		return true, "DJ session ended."
	end
	if operation == "Queue" then
		local total = #queue
		if total == 0 then return true, "This server's ClubMusic queue is empty." end
		local lines = {string.format("This server's ClubMusic queue — %d queued:", total)}
		local shown = math.min(total, 6)
		for index = 1, shown do
			local entry = queue[index]
			local title = string.sub(string.gsub(tostring(entry.title or "Unknown track"), "[%c]", " "), 1, 34)
			local artist = string.sub(string.gsub(tostring(entry.artist or "Unknown artist"), "[%c]", " "), 1, 24)
			local requester = string.sub(string.gsub(tostring(entry.requestedBy or "Unknown"), "[%c]", " "), 1, 18)
			table.insert(lines, string.format("%d. %s — %s | %s | ID: %s", index, title, artist, requester, tostring(entry.id or "")))
		end
		if total > shown then table.insert(lines, string.format("...and %d more. Run ;cmqueue again after removals.", total - shown)) end
		return true, string.sub(table.concat(lines, "\n"), 1, 1800)
	end
	-- Security administration is exposed through this server-only bridge, not client remotes.
	if operation == "RequestMute" or operation == "ClearUserQueue" or operation == "EmergencyLock"
		or operation == "TrackBlock" or operation == "ForceStop" or operation == "ModerationHistory" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "GlobalModeration") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_moderation_access_denied", operation)
			return false, "ClubMusic administrator permission is required."
		end
	end
	if operation == "RequestMute" then
		if typeof(argument) ~= "string" or #argument < 3 or #argument > 220 then
			return false, "Usage: ;cmrequestmute <UserId> on|off [reason]"
		end
		local rawUserId, mode, reason = string.match(argument, "^(%d+)%s+(%a+)%s*(.-)$")
		local targetUserId = tonumber(rawUserId)
		if not targetUserId or targetUserId < 1 or targetUserId % 1 ~= 0 or targetUserId > 9007199254740991 then
			return false, "Provide a valid numeric Roblox UserId."
		end
		mode = if mode then string.lower(mode) else ""
		if mode ~= "on" and mode ~= "off" then return false, "Use on or off. Example: ;cmrequestmute 123456 on Spam" end
		local cleanReason = if reason ~= "" then string.sub(reason, 1, 120) else nil
		local ok, accepted = ControllerFunctions.adminBridgeGlobalCall("SetRequestBlocked", targetUserId, mode == "on", caller.UserId, cleanReason)
		if not ok or accepted ~= true then return false, tostring(accepted or "Request restriction update failed.") end
		local target = Players:GetPlayerByUserId(targetUserId)
		if mode == "on" then
			blockedUsers[targetUserId] = true
			ControllerFunctions.purgeUserEntries(targetUserId)
		else
			blockedUsers[targetUserId] = nil
		end
		publishState(nil)
		return true, string.format("ClubMusic requests %s for UserId %d%s.", if mode == "on" then "disabled" else "re-enabled", targetUserId, if target then " (" .. target.Name .. ")" else "")
	end
	if operation == "TrackBlock" then
		if typeof(argument) ~= "string" or #argument < 4 or #argument > 220 then
			return false, "Usage: ;cmblocktrack <trackId> on|off [reason]"
		end
		local trackId, mode, reason = string.match(argument, "^([%w%-_]+)%s+(%a+)%s*(.-)$")
		if not trackId or #trackId > 64 then return false, "Provide a valid catalog track ID or audio-<assetId>." end
		mode = string.lower(mode or "")
		if mode ~= "on" and mode ~= "off" then return false, "Use on or off. Example: ;cmblocktrack audio-123456 on Copyright" end
		local cleanReason = if reason ~= "" then string.sub(reason, 1, 120) else nil
		local ok, accepted = ControllerFunctions.adminBridgeGlobalCall("SetTrackBlocked", trackId, mode == "on", caller.UserId, cleanReason)
		if not ok or accepted ~= true then return false, tostring(accepted or "Track moderation update failed.") end
		ControllerFunctions.blockedTrackCache = ControllerFunctions.blockedTrackCache or {}
		ControllerFunctions.blockedTrackCache[trackId] = {blocked = mode == "on", checkedAt = os.clock()}
		if mode == "on" then
			ControllerFunctions.cancelPreparedCrossfadeForTrack(trackId, "track-blocked-local")
			for index = #queue, 1, -1 do
				if queue[index].trackId == trackId then queueManager:RemoveAt(index, true) end
			end
			if nowPlaying.trackId == trackId then
				ControllerFunctions.cancelAudioTransition("track-blocked")
				ControllerFunctions.advance()
			end
		end
		publishState(nil)
		return true, string.format("Track %s is now %s globally.", trackId, if mode == "on" then "blocked" else "allowed")
	end
	if operation == "ForceStop" then
		ControllerFunctions.cancelAudioTransition("admin-force-stop")
		setPlaybackPaused(true)
		nowPlaying.trackId = ""; nowPlaying.title = ""; nowPlaying.artist = ""
		nowPlaying.genre = ""; nowPlaying.duration = 1; nowPlaying.elapsed = 0
		nowPlaying.dj = "Staff"; nowPlaying.source = "admin"
		nowPlaying.requestedBy = "Emergency stop"; nowPlaying.vip = false; nowPlaying.soundId = ""
		ControllerFunctions.stopServerMusic()
		ControllerFunctions.setAudioAsset("")
		ControllerFunctions.broadcast("ClubMusic playback was emergency-stopped on this server by staff.", "warn")
		publishState(nil)
		return true, "ClubMusic playback was emergency-stopped on this server. Use ;cmskip to resume."
	end

	if operation == "ModerationHistory" then
		if typeof(argument) ~= "string" or #argument > 24 or not string.match(argument, "^%d+$") then
			return false, "Usage: ;cmmoderationhistory <numeric UserId>"
		end
		local targetUserId = tonumber(argument)
		if not targetUserId or targetUserId < 1 or targetUserId % 1 ~= 0 or targetUserId > 9007199254740991 then return false, "Provide a valid numeric Roblox UserId." end
		local ok, history = ControllerFunctions.adminBridgeGlobalCall("GetModerationHistory", targetUserId, caller.UserId, 10)
		if not ok or typeof(history) ~= "table" then return false, tostring(history or "Moderation history is unavailable.") end
		if #history == 0 then return true, "No recorded ClubMusic moderation actions for UserId " .. tostring(targetUserId) .. "." end
		local lines = {"ClubMusic moderation history for UserId " .. tostring(targetUserId) .. ":"}
		for index, item in ipairs(history) do
			if index > 10 then break end
			local stamp = if item.at > 0 then os.date("!%Y-%m-%d %H:%M UTC", item.at) else "Unknown time"
			table.insert(lines, string.format("%s | %s=%s | by %d%s", stamp, tostring(item.field),
				tostring(item.value), tonumber(item.actorUserId) or 0,
				if item.reason ~= "" then " | " .. string.sub(item.reason, 1, 80) else ""))
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1600)
	end
	if operation == "ClearUserQueue" then
		if typeof(argument) ~= "string" or #argument > 24 or not string.match(argument, "^%d+$") then
			return false, "Usage: ;cmclearuserqueue <numeric UserId>"
		end
		local targetUserId = tonumber(argument)
		if not targetUserId or targetUserId < 1 or targetUserId % 1 ~= 0 or targetUserId > 9007199254740991 then return false, "Provide a valid numeric Roblox UserId." end
		local removed = ControllerFunctions.purgeUserEntries(targetUserId)
		publishState(nil)
		return true, string.format("Removed %d queued ClubMusic request(s) for UserId %d.", removed, targetUserId)
	end
	if operation == "EmergencyLock" then
		setRequestsLocked(true)
		ControllerFunctions.broadcast("ClubMusic requests have been emergency-locked on this server by staff. Auto DJ playback/refill remains server-managed.", "warn")
		publishState(nil)
		return true, "ClubMusic requests are now locked on this server. Use ;cmlock after the incident to reopen them."
	end
	if operation == "SecurityReplay" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "GlobalModeration") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic administrator permission is required."
		end
		-- Positional filters preserve the original syntax:
		-- ;cmreplay [UserId] [Limit] [AfterUnix] [BeforeUnix] [EventType]
		-- Use 0 for an omitted UserId/timestamp when supplying later filters.
		local targetUserId: number? = nil
		local queryLimit = 15
		local afterTimestamp: number? = nil
		local beforeTimestamp: number? = nil
		local eventType: string? = nil
		local rawArgument = if typeof(argument) == "string" then string.gsub(argument, "^%s*(.-)%s*$", "%1") else ""
		local tokens = {}
		for token in string.gmatch(rawArgument, "%S+") do
			table.insert(tokens, token)
			if #tokens > 5 then return false, "Use ;cmreplay [UserId] [Limit] [AfterUnix] [BeforeUnix] [EventType]." end
		end
		if #tokens >= 1 then
			local parsedUserId = tonumber(tokens[1])
			if not parsedUserId or parsedUserId < 0 or parsedUserId > 9007199254740991
				or parsedUserId % 1 ~= 0 then return false, "Replay target UserId is invalid." end
			if parsedUserId > 0 then targetUserId = parsedUserId end
		end
		if #tokens >= 2 then
			local parsedLimit = tonumber(tokens[2])
			if not parsedLimit or parsedLimit < 1 or parsedLimit > 30 or parsedLimit % 1 ~= 0 then
				return false, "Replay limit must be an integer from 1 to 30."
			end
			queryLimit = parsedLimit
		end
		if #tokens >= 3 then
			local parsedAfter = tonumber(tokens[3])
			if not parsedAfter or parsedAfter < 0 or parsedAfter > 9007199254740991 or parsedAfter % 1 ~= 0 then
				return false, "Replay lower timestamp must be a non-negative Unix timestamp."
			end
			if parsedAfter > 0 then afterTimestamp = parsedAfter end
		end
		if #tokens >= 4 then
			local parsedBefore = tonumber(tokens[4])
			if not parsedBefore or parsedBefore < 0 or parsedBefore > 9007199254740991 or parsedBefore % 1 ~= 0 then
				return false, "Replay upper timestamp must be a non-negative Unix timestamp."
			end
			if parsedBefore > 0 then beforeTimestamp = parsedBefore end
		end
		if #tokens >= 5 then
			eventType = tokens[5]
			if #eventType < 1 or #eventType > 48 or not string.match(eventType, "^[%w_%-]+$") then
				return false, "Replay event type must contain only letters, numbers, underscores, or hyphens (max 48 characters)."
			end
		end
		if afterTimestamp and beforeTimestamp and afterTimestamp > beforeTimestamp then
			return false, "Replay lower timestamp must not exceed upper timestamp."
		end
		local endpoint = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
		if not endpoint or not endpoint:IsA("BindableFunction") or endpoint.Parent ~= ServerStorage then
			return false, "Security replay is unavailable on this server."
		end
		local queryOk, allowed, events, queryError = pcall(function()
			return endpoint:Invoke("Query", caller, targetUserId, queryLimit, beforeTimestamp, eventType, afterTimestamp)
		end)
		if not queryOk or allowed ~= true or typeof(events) ~= "table" then
			return false, if typeof(queryError) == "string" then queryError else "Security replay query failed."
		end
		if #events == 0 then
			return true, if targetUserId then "No retained replay events for UserId " .. tostring(targetUserId) .. "."
				else "No replay events match the filters on this server."
		end
		local lines = {"Club Neon Security Replay (newest first):"}
		local outputLength = #lines[1]
		for index, item in ipairs(events) do
			if index > queryLimit then break end
			if typeof(item) == "table" then
				local at = if typeof(item.at) == "number" then os.date("!%H:%M:%S UTC", item.at) else "time?"
				local actorId = typeof(item.userId) == "number" and item.userId or 0
				local targetId = typeof(item.targetUserId) == "number" and item.targetUserId or 0
				local summary = string.format("%s | %s | %s | Actor %d%s | %s",
					at, string.sub(tostring(item.severity or "Info"), 1, 12),
					string.sub(tostring(item.type or "unknown"), 1, 48),
					actorId, if targetId > 0 then " -> " .. tostring(targetId) else "",
					string.sub(tostring(item.source or "Server"), 1, 24))
				if outputLength + #summary + 1 > 1800 then break end
				table.insert(lines, summary)
				outputLength += #summary + 1
				local metadata = if typeof(item.metadata) == "table" then item.metadata else {}
				local keys = {}
				for key, value in pairs(metadata) do
					if typeof(key) == "string" and (typeof(value) == "string" or typeof(value) == "number" or typeof(value) == "boolean") then
						table.insert(keys, key)
					end
				end
				table.sort(keys)
				local details = {}
				for _, key in ipairs(keys) do
					local value = metadata[key]
					local rendered = string.sub(tostring(value), 1, 48)
					table.insert(details, key .. "=" .. rendered)
				end
				if #details > 0 then
					local detailLine = "  " .. table.concat(details, " | ")
					if outputLength + #detailLine + 1 <= 1800 then
						table.insert(lines, detailLine)
						outputLength += #detailLine + 1
					end
				end
			end
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1900)
	end
	if operation == "SecurityThreatIntelligence" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "GlobalModeration") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic administrator permission is required."
		end
		local targetUserId: number? = nil
		local queryLimit = 15
		local rawArgument = if typeof(argument) == "string" then string.gsub(argument, "^%s*(.-)%s*$", "%1") else ""
		if rawArgument ~= "" then
			local userPart, limitPart = string.match(rawArgument, "^(%d+)%s*(%d*)$")
			if not userPart then return false, "Use ;cmthreat [UserId] [Limit]." end
			local parsedUserId = tonumber(userPart)
			if not parsedUserId or parsedUserId < 1 or parsedUserId > 9007199254740991
				or parsedUserId % 1 ~= 0 then return false, "Threat-intelligence target UserId is invalid." end
			targetUserId = parsedUserId
			if limitPart ~= "" then
				local parsedLimit = tonumber(limitPart)
				if not parsedLimit or parsedLimit < 1 or parsedLimit > 30 or parsedLimit % 1 ~= 0 then
					return false, "Threat-intelligence limit must be an integer from 1 to 30."
				end
				queryLimit = parsedLimit
			end
		end
		local endpoint = ServerStorage:FindFirstChild("ClubNeonThreatIntelligence")
		if not endpoint or not endpoint:IsA("BindableFunction") or endpoint.Parent ~= ServerStorage then
			return false, "Threat intelligence is unavailable on this server."
		end
		local queryOk, allowed, incidents, queryError = pcall(function()
			return endpoint:Invoke("Query", caller, targetUserId, queryLimit)
		end)
		if not queryOk or allowed ~= true or typeof(incidents) ~= "table" then
			return false, if typeof(queryError) == "string" then queryError else "Threat-intelligence query failed."
		end
		local raidReviews = {}
		local raidQueryError: string? = nil
		if targetUserId == nil then
			local raidOk, raidAllowed, raidItems, raidError = pcall(function()
				return endpoint:Invoke("QueryRaids", caller, math.min(queryLimit, 10))
			end)
			if raidOk and raidAllowed == true and typeof(raidItems) == "table" then
				raidReviews = raidItems
			else
				raidQueryError = if raidOk and typeof(raidError) == "string" then raidError else "Raid cohort query failed."
			end
		end
		if #incidents == 0 and #raidReviews == 0 then
			return true, if targetUserId then "No correlated review items for UserId " .. tostring(targetUserId) .. " on this server."
				elseif raidQueryError then "No player reviews are retained; raid cohort review is unavailable: " .. string.sub(raidQueryError, 1, 120)
				else "No correlated player or raid-cohort review items are currently retained on this server."
		end
		local lines = {"Club Neon Threat Intelligence (server-local advisory review only):"}
		for index, item in ipairs(incidents) do
			if index > queryLimit then break end
			if typeof(item) == "table" then
				local age = if typeof(item.lastAt) == "number" then math.floor(math.max(0, os.clock() - item.lastAt)) else 0
				local categories = if typeof(item.categories) == "table" then table.concat(item.categories, ",") else "n/a"
				local signals = if typeof(item.signals) == "table" then table.concat(item.signals, ",") else "n/a"
				local sources = if typeof(item.sources) == "table" then table.concat(item.sources, ",") else "n/a"
				local reasons = if typeof(item.reasons) == "table" then table.concat(item.reasons, ",") else "n/a"
				local subjectLabel = if item.kind == "ServerReview" then "SERVER"
					else "UserId " .. tostring(typeof(item.subjectUserId) == "number" and item.subjectUserId or 0)
				table.insert(lines, string.format("%s | %s | %s confidence | score %d | %d events | %ds ago",
					tostring(item.id or "?"), subjectLabel,
					tostring(item.confidence or "Low"), typeof(item.score) == "number" and item.score or 0,
					typeof(item.eventCount) == "number" and item.eventCount or 0, age))
				table.insert(lines, "  Categories: " .. string.sub(categories, 1, 140)
					.. " | Sources: " .. string.sub(sources, 1, 100))
				table.insert(lines, "  Signals: " .. string.sub(signals, 1, 180)
					.. " | Reasons: " .. string.sub(reasons, 1, 100))
				table.insert(lines, "  Session: " .. tostring(item.sessionAgeSeconds or 0) .. "s / "
					.. tostring(item.sessionEventCount or 0) .. " observed events")
			end
		end
		for index, item in ipairs(raidReviews) do
			if index > math.min(queryLimit, 10) then break end
			if typeof(item) == "table" then
				local age = if typeof(item.lastAt) == "number" then math.floor(math.max(0, os.clock() - item.lastAt)) else 0
				table.insert(lines, string.format("%s | RAID COHORT | %s confidence | %d joins | %d distinct signaled players | %ds ago",
					tostring(item.id or "RAID-?"), tostring(item.confidence or "Medium"),
					typeof(item.joinCount) == "number" and item.joinCount or 0,
					typeof(item.signaledPlayerCount) == "number" and item.signaledPlayerCount or 0, age))
				table.insert(lines, string.format("  Evidence: %d categories | %d sources | %d signal codes",
					typeof(item.categoryCount) == "number" and item.categoryCount or 0,
					typeof(item.sourceCount) == "number" and item.sourceCount or 0,
					typeof(item.signalCodeCount) == "number" and item.signalCodeCount or 0))
				table.insert(lines, "  Reasons: " .. (typeof(item.reasons) == "table" and table.concat(item.reasons, ",") or "n/a"))
			end
		end
		if raidQueryError then table.insert(lines, "Raid cohort query unavailable: " .. string.sub(raidQueryError, 1, 120)) end
		table.insert(lines, "Raid reviews are advisory; join bursts alone never trigger enforcement.")
		return true, string.sub(table.concat(lines, "\n"), 1, 1850)
	end
	if operation == "StaffSpectatorEnter" or operation == "StaffSpectatorSwitch" or operation == "StaffSpectatorExit" or operation == "StaffSpectatorState" or operation == "StaffSpectatorStealth" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "GlobalModeration") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic administrator permission is required."
		end
		local endpoint = ServerStorage:FindFirstChild("ClubNeonStaffSpectatorControl")
		if not endpoint or not endpoint:IsA("BindableFunction") or endpoint.Parent ~= ServerStorage then
			return false, "Staff observation is unavailable on this server."
		end
		local action = if operation == "StaffSpectatorEnter" then "Enter"
			elseif operation == "StaffSpectatorSwitch" then "SwitchTarget"
			elseif operation == "StaffSpectatorExit" then "Exit"
			elseif operation == "StaffSpectatorStealth" then "SetStealth" else "GetState"
		local targetUserId: number? = nil
		local stealthEnabled = false
		if action == "Enter" or action == "SwitchTarget" then
			if typeof(argument) ~= "string" or #argument < 1 or #argument > 32 then
				return false, if action == "Enter" then "Usage: ;cmspectate <UserId> [stealth|visible]" else "Usage: ;cmspectateswitch <UserId>"
			end
			local rawUserId, mode = string.match(argument, "^(%d+)%s*(%a*)$")
			mode = string.lower(mode or "")
			if not rawUserId or (action == "SwitchTarget" and mode ~= "")
				or (mode ~= "" and mode ~= "stealth" and mode ~= "visible") then
				return false, if action == "Enter" then "Use a UserId with optional stealth or visible mode."
					else "Use a numeric UserId when switching targets."
			end
			targetUserId = tonumber(rawUserId)
			if not targetUserId or targetUserId < 1 or targetUserId % 1 ~= 0 or targetUserId > 9007199254740991 then
				return false, "Provide a valid numeric Roblox UserId."
			end
			stealthEnabled = action == "Enter" and mode == "stealth"
		elseif action == "SetStealth" then
			if typeof(argument) ~= "string" then return false, "Use on or off to change stealth mode." end
			local mode = string.lower(argument)
			if mode ~= "on" and mode ~= "off" and mode ~= "stealth" and mode ~= "visible" then
				return false, "Use on/stealth or off/visible."
			end
			stealthEnabled = mode == "on" or mode == "stealth"
		end
		local invokeOk, accepted, result = pcall(function()
			return endpoint:Invoke(action, caller.UserId, targetUserId, stealthEnabled)
		end)
		if not invokeOk or accepted ~= true then
			return false, if typeof(result) == "string" then result else "Staff observation request was rejected."
		end
		if action == "GetState" then
			if typeof(result) ~= "table" or result.active ~= true then return true, "Staff observation is not active." end
			return true, "Observing " .. tostring(result.targetName or "player") .. " (UserId " .. tostring(result.targetUserId or 0) .. ")."
				.. (result.stealth == true and " Stealth is ON." or " Stealth is OFF.")
		end
		return true, if typeof(result) == "string" then result else "Staff observation request completed."
	end
	if operation == "SecurityStatus" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "GlobalModeration") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic administrator permission is required."
		end
		local ok, status = ControllerFunctions.adminBridgeGlobalCall("GetGlobalSecurityStatus")
		if not ok or typeof(status) ~= "table" then return false, tostring(status or "Security status is unavailable.") end
		local lines = {"ClubMusic Global Security Status:"}
		for _, key in ipairs({"Authorization", "Monitor", "MessageValidation", "Idempotency", "IncidentResponse", "ThreatIntelligence"}) do
			local item = status[key]
			local state = if typeof(item) == "table" then tostring(item.state or "Unknown") else "Unavailable"
			table.insert(lines, key .. ": " .. state)
		end
		local policy = status.Policy
		table.insert(lines, "Policy revision: " .. tostring(if typeof(policy) == "table" then policy.revision else "Unavailable"))
		return true, table.concat(lines, "\n")
	end
	if operation == "SecurityIncidents" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "IncidentResponse") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic co-owner/owner permission is required."
		end
		local ok, incidents = ControllerFunctions.adminBridgeGlobalCall("GetGlobalSecurityIncidents", 8, caller.UserId)
		if not ok or typeof(incidents) ~= "table" then return false, tostring(incidents or "Incident service is unavailable.") end
		if #incidents == 0 then return true, "No recent ClubMusic security incidents." end
		local lines = {"Recent ClubMusic security incidents:"}
		for index, item in ipairs(incidents) do
			if index > 8 then break end
			if typeof(item) == "table" then
				table.insert(lines, string.format("%s | %s | %s | %s", tostring(item.id or "?"), tostring(item.kind or "?"), tostring(item.state or "?"), string.sub(tostring(item.summary or ""), 1, 100)))
			end
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1700)
	end
	if operation == "SecurityThreatCaseOpen" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "IncidentResponse") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic incident-response permission is required."
		end
		if typeof(argument) ~= "string" or #argument < 5 or #argument > 24
			or not string.match(argument, "^TTI%-%d+$") then
			return false, "Usage: ;cmthreatcase <TTI-review-ID>"
		end
		local endpoint = ServerStorage:FindFirstChild("ClubNeonThreatIntelligence")
		if not endpoint or not endpoint:IsA("BindableFunction") or endpoint.Parent ~= ServerStorage then
			return false, "Threat intelligence is unavailable on this server."
		end
		local queryOk, allowed, reviews, queryError = pcall(function()
			return endpoint:Invoke("Query", caller, nil, 30)
		end)
		if not queryOk or allowed ~= true or typeof(reviews) ~= "table" then
			return false, if typeof(queryError) == "string" then queryError else "Threat review lookup failed."
		end
		local selected = nil
		for _, item in ipairs(reviews) do
			if typeof(item) == "table" and item.id == argument then selected = item; break end
		end
		if not selected then return false, "That review item is no longer retained on this server." end
		local subjectUserId = selected.subjectUserId
		if typeof(subjectUserId) ~= "number" or subjectUserId < 1 or subjectUserId % 1 ~= 0 then
			return false, "A server-level review cannot be converted to a player incident."
		end
		local confidence = if selected.confidence == "High" then "High" else "Medium"
		local score = if typeof(selected.score) == "number" then math.clamp(math.floor(selected.score), 0, 1000000) else 0
		local signals = if typeof(selected.signals) == "table" then table.concat(selected.signals, ",") else "unavailable"
		local summary = string.sub("Threat review " .. argument .. " | " .. confidence
			.. " confidence | score " .. tostring(score) .. " | signals " .. signals, 1, 120)
		local openOk, incidentId = ControllerFunctions.adminBridgeGlobalCall(
			"OpenGlobalSecurityIncident", "ManualReview", summary, caller.UserId, subjectUserId)
		if not openOk then return false, tostring(incidentId or "Incident creation failed.") end
		return true, "Threat review converted to a ManualReview incident: " .. tostring(incidentId)
	end
	if operation == "SecurityIncidentOpen" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "IncidentResponse") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic co-owner/owner permission is required."
		end
		if typeof(argument) ~= "string" or #argument < 4 or #argument > 200 then
			return false, "Usage: ;cmincident <SecurityAlert|ServiceDegraded|AbuseReport|ManualReview> <userId|server> <summary>"
		end
		local kind, subjectToken, summary = string.match(argument, "^(%a+)%s+(%S+)%s+(.+)$")
		local subjectUserId = if subjectToken == "server" then 0 else tonumber(subjectToken)
		if not kind or not subjectUserId or subjectUserId < 0 or subjectUserId % 1 ~= 0 or not summary or #summary > 180 then
			return false, "Provide an allowed incident type, a numeric userId (or server), and a summary."
		end
		local ok, incidentId = ControllerFunctions.adminBridgeGlobalCall("OpenGlobalSecurityIncident", kind, summary, caller.UserId, subjectUserId)
		if not ok then return false, tostring(incidentId) end
		return true, "Security incident opened: " .. tostring(incidentId)
	end
	if operation == "SecurityIncidentResolve" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "IncidentResponse") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic co-owner/owner permission is required."
		end
		if typeof(argument) ~= "string" or #argument < 8 or #argument > 64 or not string.match(argument, "^[%w%-]+$") then
			return false, "Usage: ;cmresolve <incident ID>"
		end
		local ok, resolved = ControllerFunctions.adminBridgeGlobalCall("ResolveGlobalSecurityIncident", argument, caller.UserId)
		if not ok then return false, tostring(resolved) end
		return true, "Security incident resolved."
	end
	if operation == "SecurityPolicy" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "SecurityPolicy") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic co-owner/owner permission is required."
		end
		local ok, policy = ControllerFunctions.adminBridgeGlobalCall("GetGlobalSecurityPolicy")
		if not ok or typeof(policy) ~= "table" then return false, tostring(policy or "Security policy is unavailable.") end
		local values = if typeof(policy.values) == "table" then policy.values else {}
		local keys = {}
		for key in pairs(values) do table.insert(keys, tostring(key)) end
		table.sort(keys)
		local lines = {"ClubMusic Security Policy (revision " .. tostring(policy.revision or "?") .. "):"}
		for _, key in ipairs(keys) do table.insert(lines, key .. " = " .. tostring(values[key])) end
		return true, table.concat(lines, "\n")
	end
	if operation == "SecurityPolicySet" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "SecurityPolicy") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic co-owner/owner permission is required."
		end
		if typeof(argument) ~= "string" or #argument > 80 then return false, "Usage: ;cmpolicyset <key> <value>" end
		local key, rawValue = string.match(argument, "^(%w+)%s+([^%s]+)$")
		if not key or not rawValue then return false, "Usage: ;cmpolicyset <key> <value>" end
		local value: any
		if key == "monitoringEnabled" then
			if rawValue ~= "true" and rawValue ~= "false" then return false, "monitoringEnabled must be true or false." end
			value = rawValue == "true"
		else
			value = tonumber(rawValue)
			if not value or value ~= value or value == math.huge or value == -math.huge then return false, "Policy value must be a finite number." end
		end
		local ok, policy = ControllerFunctions.adminBridgeGlobalCall("SetGlobalSecurityPolicy", key, value, caller.UserId)
		if not ok then return false, tostring(policy) end
		return true, "Security policy updated. " .. key .. " = " .. tostring(value)
	end
	-- Operational inspection commands use the same independent ClubMusic
	-- authorization service as security administration. All inspection paths are
	-- read-only; only explicit owner maintenance/reconcile requests reach setters.
	local operationalPermission = ({
		OperationalHealth = "GlobalModeration",
		OperationalCatalogRefresh = "GlobalConfig",
		OperationalServices = "GlobalModeration",
		OperationalDiagnostics = "GlobalConfig",
		PurchaseDiagnostics = "GlobalConfig",
		OperationalErrors = "GlobalConfig",
		OperationalMetrics = "GlobalModeration",
		OperationalSecurityLog = "IncidentResponse",
		OperationalRateLimit = "IncidentResponse",
		OperationalConfig = "GlobalConfig",
		OperationalRecovery = "GlobalConfig",
		OperationalReconcile = "GlobalConfig",
		OperationalMaintenance = "GlobalConfig",
	} :: {[string]: string})[operation]
	if operationalPermission then
		if not ControllerFunctions.adminBridgeAuthorize(caller, operationalPermission) then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_operational_access_denied", operation)
			return false, if operationalPermission == "GlobalModeration"
				then "ClubMusic administrator permission is required."
				else "ClubMusic co-owner/owner permission is required."
		end
	end

	if operation == "OperationalCatalogRefresh" then
		if not ControllerFunctions.refreshCatalogWhenReady() then
			return false, "Catalog refresh could not complete. Check catalog storage readiness and DataStore budget."
		end
		return true, string.format("ClubMusic catalog refreshed successfully: %d playable tracks.", #ALL_TRACK_IDS)
	end
	if operation == "OperationalHealth" then
		local ok, health = ControllerFunctions.adminBridgeGlobalCall("GetGlobalHealth")
		if not ok or typeof(health) ~= "table" then return false, tostring(health or "Health status is unavailable.") end
		return true, string.sub(string.format(
			"ClubMusic Local Health: %s | Dependencies: %s | Global service: %s | Recovery: %s\n%s",
			tostring(health.state or "Unknown"), tostring(health.localState or "Unknown"),
			tostring(health.serviceState or "Unknown"), tostring(health.recoveryState or "Unknown"),
			string.sub(tostring(health.detail or health.localDetail or ""), 1, 500)
		), 1, 1100)
	end
	if operation == "PurchaseDiagnostics" then
		local lines = {"Recent ClubMusic purchase events (latest server-local records):"}
		if #purchaseDiagnostics.PurchaseEntries == 0 then
			table.insert(lines, "No purchase prompt or receipt events have been recorded in this server yet.")
		else
			for index = math.max(1, #purchaseDiagnostics.PurchaseEntries - 11), #purchaseDiagnostics.PurchaseEntries do
				local item = purchaseDiagnostics.PurchaseEntries[index]
				table.insert(lines, string.format("%s | %s | UserId %d | ID %d | %s%s",
					os.date("!%H:%M:%S UTC", item.at), item.source, item.userId, item.itemId,
					item.outcome, if item.detail ~= "" then " | " .. item.detail else ""))
			end
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1700)
	end
	if operation == "OperationalDiagnostics" then
		return operationalDiagnosticsFormatter(ControllerFunctions.adminBridgeGlobalCall, purchaseDiagnostics.PurchaseEntries)
	end
	if operation == "OperationalErrors" then
		local ok, snapshot = ControllerFunctions.adminBridgeGlobalCall("GetGlobalDiagnostics")
		if not ok or typeof(snapshot) ~= "table" then return false, "Diagnostic status is unavailable." end
		local services = if typeof(snapshot.operationalServices) == "table" then snapshot.operationalServices else {}
		local history = if typeof(services.errorHistory) == "table" then services.errorHistory else {}
		if snapshot.errorHistoryAvailable ~= true then
			return true, "Server-local ErrorHistory is unavailable. Detailed records remain server-side."
		end
		return true, string.format(
			"Server-local ErrorHistory: %s/%s records retained | %s total unique errors | %s repeated occurrences. Error messages and tracebacks are not sent to clients.",
			tostring(history.count or 0), tostring(history.maxRecords or 50),
			tostring(history.totalErrors or 0), tostring(history.totalRepeats or 0))
	end
	if operation == "OperationalMetrics" then
		local ok, metrics = ControllerFunctions.adminBridgeGlobalCall("GetGlobalMetrics")
		if not ok or typeof(metrics) ~= "table" then return false, tostring(metrics or "Metrics are unavailable or disabled.") end
		if metrics.state == "Deferred" or metrics.deferred == true then
			return true, "ClubMusic Metrics (Deferred): Optional analytics aggregation is temporarily paused by the current server-load budget. Health monitoring and security services remain active."
		end
		local aggregate = if typeof(metrics.aggregate) == "table" then metrics.aggregate else {}
		local counters = if typeof(aggregate.counters) == "table" then aggregate.counters else {}
		local structuredCounters = if typeof(metrics.counters) == "table" then metrics.counters else {}
		local keys = {}
		for key in pairs(counters) do table.insert(keys, tostring(key)) end
		table.sort(keys)
		local lines = {"ClubMusic Metrics (" .. tostring(metrics.state or "Unknown") .. "):"}
		for index = 1, math.min(#keys, 12) do
			local key = keys[index]
			local detail = structuredCounters[key]
			if typeof(detail) == "table" then
				table.insert(lines, key .. " = " .. tostring(counters[key])
					.. " | success " .. tostring(detail.successCount or 0)
					.. " | failure " .. tostring(detail.failureCount or 0)
					.. " | last " .. tostring(detail.lastOutcome or "Observed"))
			else
				table.insert(lines, key .. " = " .. tostring(counters[key]))
			end
		end
		if #keys == 0 then table.insert(lines, "No aggregated counters are available yet.") end
		return true, string.sub(table.concat(lines, "\n"), 1, 1400)
	end
	if operation == "OperationalSecurityLog" then
		local ok, entries = ControllerFunctions.adminBridgeGlobalCall("GetGlobalAudit", 30, caller.UserId)
		if not ok or typeof(entries) ~= "table" then return false, tostring(entries or "Security audit log is unavailable.") end
		local lines = {"Recent ClubMusic security audit events:"}
		local count = 0
		for _, item in ipairs(entries) do
			if typeof(item) == "table" and item.kind == "SecurityEvent" then
				count += 1
				table.insert(lines, string.format("%s | actor %s | %s | %s",
					tostring(item.at or "?"), tostring(item.actorUserId or "?"),
					string.sub(tostring(item.target or "?"), 1, 48), string.sub(tostring(item.action or "?"), 1, 64)))
				if count >= 8 then break end
			end
		end
		if count == 0 then table.insert(lines, "No recent security audit events were found in the latest audit page.") end
		return true, string.sub(table.concat(lines, "\n"), 1, 1500)
	end
	if operation == "OperationalRateLimit" then
		local ok, services = ControllerFunctions.adminBridgeGlobalCall("GetGlobalOperationalStatus")
		local item = if ok and typeof(services) == "table" then services.RateLimit else nil
		if typeof(item) ~= "table" then return false, "Rate-limit service status is unavailable." end
		return true, string.format("ClubMusic Rate Limits: %s | checks %s | rejected %s | shared failures %s | existing shared buckets: %s",
			tostring(item.state or "Unknown"), tostring(item.checks or 0), tostring(item.rejected or 0),
			tostring(item.sharedFailures or 0), tostring(item.usesExistingBuckets == true))
	end
	if operation == "OperationalConfig" then
		local ok, config = ControllerFunctions.adminBridgeGlobalCall("GetGlobalConfig")
		if not ok or typeof(config) ~= "table" then return false, tostring(config or "Global configuration is unavailable.") end
		local values = if typeof(config.values) == "table" then config.values else {}
		local keys = {}
		for key in pairs(values) do table.insert(keys, tostring(key)) end
		table.sort(keys)
		local lines = {"ClubMusic Global Config (revision " .. tostring(config.revision or "?") .. "):"}
		for _, key in ipairs(keys) do
			local value = values[key]
			if key == "maintenanceMessage" then value = string.sub(tostring(value), 1, 80) end
			table.insert(lines, key .. " = " .. tostring(value))
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1500)
	end
	if operation == "OperationalRecovery" then
		local ok, snapshot = ControllerFunctions.adminBridgeGlobalCall("GetGlobalDiagnostics")
		if not ok or typeof(snapshot) ~= "table" then return false, tostring(snapshot or "Recovery status is unavailable.") end
		local recovery = if typeof(snapshot.recovery) == "table" then snapshot.recovery else {}
		return true, string.sub("ClubMusic Recovery: " .. tostring(recovery.state or "Unavailable")
			.. " | attempts " .. tostring(recovery.attempts or 0) .. " | " .. tostring(recovery.detail or ""), 1, 900)
	end
	if operation == "OperationalReconcile" then
		local ok, result = ControllerFunctions.adminBridgeGlobalCall("RunGlobalReconciliation", caller.UserId)
		if not ok then return false, tostring(result or "Read-only reconciliation failed.") end
		local status = if typeof(result) == "table" then result else {}
		return true, "Read-only reconciliation: " .. tostring(status.state or "Unknown") .. " | " .. tostring(status.detail or "")
	end
	if operation == "OperationalMaintenance" then
		local command = if typeof(argument) == "string" then string.sub(argument, 1, 240) else "status"
		local action, message = string.match(command, "^(%a+)%s*(.*)$")
		if not action or action == "" then action = "status" end
		action = string.lower(action)
		if action == "status" then
			local ok, services = ControllerFunctions.adminBridgeGlobalCall("GetGlobalOperationalStatus")
			local item = if ok and typeof(services) == "table" then services.Maintenance else nil
			if typeof(item) ~= "table" then return false, "Maintenance service status is unavailable." end
			return true, "ClubMusic Maintenance: " .. tostring(item.enabled == true) .. " | revision " .. tostring(item.revision or "?") .. " | " .. tostring(item.message or "")
		end
		if action ~= "on" and action ~= "off" then return false, "Usage: ;cmmaintenance status OR ;cmmaintenance on [message] OR ;cmmaintenance off" end
		local enabled = action == "on"
		local maintenanceMessage = if enabled and message ~= "" then message else nil
		local ok, result = ControllerFunctions.adminBridgeGlobalCall("SetGlobalMaintenance", enabled, maintenanceMessage, caller.UserId)
		if not ok then return false, tostring(result or "Maintenance setting was rejected.") end
		return true, "ClubMusic global maintenance mode " .. (if enabled then "enabled." else "disabled.")
	end
	local action = ADMIN_BRIDGE_ACTIONS[operation]
	local payload = {}
	if operation == "RemoveQueueEntry" then
		if typeof(argument) ~= "string" or #argument > 64
			or not string.match(argument, "^cm%-%x+%-%x+%-%x+%-%x+%-%x+$") then
			return false, "Use ;cmremove with a queue ID copied from ;cmqueue."
		end
		action = "DJRemove"
		payload = {queueId = argument}
	end
	if not action then return false, "That ClubMusic admin operation is not exposed." end
	if action == "DJClearQueue" and not ControllerFunctions.isAdmin(caller) then
		ControllerFunctions.adminBridgeReportSignal(caller, "admin_bridge_access_denied", operation)
		return false, "ClubMusic administrator permission is required to clear the queue."
	end
	local ok, accepted, message = pcall(ControllerFunctions.handleAction, caller, action, payload, true)
	if not ok then
		warn("[ClubMusic Admin Bridge] Action failed: " .. tostring(accepted))
		return false, "ClubMusic could not process that action."
	end
	if accepted ~= true then
		return false, if typeof(message) == "string" then message else "ClubMusic rejected that action."
	end
	return true, if typeof(message) == "string" then message else "ClubMusic action accepted."
end
	adminBridge.OnInvoke = adminBridgeCallback
	return {
		Bridge = adminBridge,
		Shutdown = function()
			adminBridgeShuttingDown = true
			if adminBridge.Parent == ServerStorage and adminBridge.OnInvoke == adminBridgeCallback then
				adminBridge.OnInvoke = nil
			end
		end,
	}
end
