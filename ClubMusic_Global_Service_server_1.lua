--!strict
-- ClubMusic_Global_Service
-- Place as a Script in ServerScriptService.
-- Cross-server coordination for the secured Club Music UI.
--
-- Uses DataStore for durable global moderation/configuration/receipts and
-- MessagingService for best-effort cross-server notifications/commands.
-- Playback-only sync is opt-in and shares Now Playing only; request queues remain server-local.
-- Rate limiting is bounded and server-local.
-- Every receiving server validates messages and applies only allowlisted commands.
-- MessagingService is not a durable queue; periodic reconciliation handles moderation state.

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local ServerStorage = game:GetService("ServerStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local receiptSecurityCore = ServerStorage:WaitForChild("ClubMusicSecurityCore", 20)
local receiptHashModule = if receiptSecurityCore and receiptSecurityCore:IsA("Folder")
	then receiptSecurityCore:FindFirstChild("ReceiptHash") else nil
if not receiptHashModule or not receiptHashModule:IsA("ModuleScript") then
	error("[ClubMusic Global] Missing ServerStorage.ClubMusicSecurityCore.ReceiptHash ModuleScript.")
end
local receiptHashOk, receiptHashResult = pcall(require, receiptHashModule)
if not receiptHashOk or typeof(receiptHashResult) ~= "table" or type(receiptHashResult.KeySuffix) ~= "function" then
	error("[ClubMusic Global] Security Core ReceiptHash failed to load: " .. tostring(receiptHashResult))
end
local ReceiptHash = receiptHashResult

local CONFIG = {
	Enabled = true,
	-- Keep Studio isolated by default. Set true only for intentional cross-server Studio tests.
	EnableInStudio = false,

	Topics = {
		Announcements = "ClubMusic_Global_Announcements_v1",
		Moderation = "ClubMusic_Global_Moderation_v1",
		XPBoost = "ClubMusic_Global_XPBoost_v1",
		Catalog = "ClubMusic_Global_Catalog_v1",
	},
	ModerationStoreName = "ClubMusic_GlobalModeration_v1",
	GlobalControlStoreName = "ClubMusic_GlobalControl_v1",
	-- Bounded per-server budgets; no shared MemoryStore limiter.
	FallbackPlayerCapacity = 20,
	FallbackPlayerRefillPerSecond = 5,
	ModerationReconcileSeconds = 180,
	SubscriptionRetrySeconds = 10,
	MaxAnnouncementLength = 240,
	MaxModerationReasonLength = 120,
	MaxMessageBytes = 4096,
}

local IS_STUDIO = RunService:IsStudio()
local SERVICE_ENABLED = CONFIG.Enabled and (not IS_STUDIO or CONFIG.EnableInStudio)
local JOB_ID = game.JobId ~= "" and game.JobId or HttpService:GenerateGUID(false)
local globalDiagnosticsService: any = nil
local globalServiceRegistry: any = nil
local globalServerHealthService: any = nil
local globalLocalWatchdog: any = nil
local subscriptionStatus: {[string]: string} = {}
local messagingPublishSuccess = 0
local messagingPublishFailures = 0
local messagingReceived = 0
local messagingRejected = 0
local messagingLastError: string? = nil
local globalConfigService: any = nil
local globalStateReconciliationService: any = nil
local globalMaintenanceService: any = nil
local globalAuditService: any = nil
local globalEventLogService: any = nil
local globalRateLimitService: any = nil
local globalAuthorizationService: any = nil
local globalSecurityMonitorService: any = nil
local globalMessageValidationService: any = nil
local globalIdempotencyService: any = nil
local globalIncidentResponseService: any = nil
local globalSecurityPolicyService: any = nil
local authorizeGlobalActor: (any, string) -> boolean
local moderationStore: any = nil
local globalControlStore: any = nil
local globalConfigStore: any = nil
local GLOBAL_XP_BOOST_KEY = "globalXPBoost_v1" -- Preserve existing active timers.
local XP_RECEIPT_STORE_NAME = "ClubMusic_XPBoostReceipts_v1"
local MAX_GLOBAL_XP_BOOST_SECONDS = 30 * 24 * 60 * 60
local xpReceiptStore: any = nil
local MAX_PURCHASE_ID_LENGTH = 128

if SERVICE_ENABLED then
	-- Durable DataStore handles are required for global moderation, configuration,
	-- and purchase records. Request budgets remain server-local.
	local storesOk, storesError = pcall(function()
		moderationStore = DataStoreService:GetDataStore(CONFIG.ModerationStoreName)
		globalControlStore = DataStoreService:GetDataStore(CONFIG.GlobalControlStoreName)
		globalConfigStore = DataStoreService:GetDataStore("ClubMusic_GlobalConfig_v1")
		xpReceiptStore = DataStoreService:GetDataStore(XP_RECEIPT_STORE_NAME)
	end)
	if not storesOk then
		SERVICE_ENABLED = false
		warn("[ClubMusic Global] DataStore handle initialization failed; global features are disabled safely: "
			.. tostring(storesError))
	end
end

local apiFolder = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
if apiFolder and not apiFolder:IsA("Folder") then apiFolder:Destroy(); apiFolder = nil end
if not apiFolder then
	apiFolder = Instance.new("Folder")
	apiFolder.Name = "ClubMusicGlobalAPI"
	apiFolder.Parent = ServerStorage
end

local globalEvent = apiFolder:FindFirstChild("GlobalEvent")
if globalEvent and not globalEvent:IsA("BindableEvent") then globalEvent:Destroy(); globalEvent = nil end
if not globalEvent then
	globalEvent = Instance.new("BindableEvent")
	globalEvent.Name = "GlobalEvent"
	globalEvent.Parent = apiFolder
end
local globalEventBindable = globalEvent :: BindableEvent

local function bindFunction(name: string, callback: (...any) -> any): BindableFunction
	local object = apiFolder:FindFirstChild(name)
	if object and not object:IsA("BindableFunction") then object:Destroy(); object = nil end
	if not object then
		object = Instance.new("BindableFunction")
		object.Name = name
		object.Parent = apiFolder
	end
	(object :: BindableFunction).OnInvoke = callback
	return object :: BindableFunction
end

local function finiteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function recordSecurityReplay(eventType: string, userId: number, targetUserId: number, severity: string, source: string, metadata: {[string]: any}?)
	local storage = game:GetService("ServerStorage")
	local endpoint = storage:FindFirstChild("TikiTideSecurityReplay")
	if not endpoint or not endpoint:IsA("BindableFunction") or endpoint.Parent ~= storage then return false end
	local ok, recorded = pcall(function()
		return endpoint:Invoke("Record", eventType, userId, targetUserId, severity, source, metadata or {})
	end)
	return ok and recorded == true
end

local function recordThreatIntelligence(signal: string, userId: number, source: string, severity: string): boolean
	local storage = game:GetService("ServerStorage")
	local endpoint = storage:FindFirstChild("TikiTideThreatIntelligence")
	if not endpoint or not endpoint:IsA("BindableFunction") or endpoint.Parent ~= storage then return false end
	local ok, recorded = pcall(function()
		return endpoint:Invoke("Record", signal, userId, source, severity)
	end)
	return ok and recorded == true
end

local function cleanText(value: any, maxLength: number): string?
	if typeof(value) ~= "string" or #value == 0 or #value > maxLength then return nil end
	local clean = value:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if clean == "" then return nil end
	return clean
end

-- Cross-server announcements are filtered at the trusted publishing server.
-- Receivers can then rely on the server-published, envelope-validated message and
-- do not need to re-filter the same text independently in every destination server.
local function filterAnnouncementText(value: any, actorUserId: number): string?
	local clean = cleanText(value, CONFIG.MaxAnnouncementLength)
	if not clean then return nil end
	local ok, filteredText = pcall(function()
		local filtered = TextService:FilterStringAsync(clean, actorUserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(filteredText) ~= "string" then return nil end
	return cleanText(filteredText, CONFIG.MaxAnnouncementLength)
end

local fallbackBuckets: {[string]: {tokens: number, updated: number}} = {}
local signalCounts: {[string]: number} = {}
local MAX_FALLBACK_BUCKETS = 2048
local MAX_SIGNAL_KEYS = 2048
local FALLBACK_BUCKET_IDLE_SECONDS = CONFIG.BudgetKeyTtlSeconds
local lastFallbackPrune = 0

local function pruneFallbackBuckets(now: number)
	if now - lastFallbackPrune < 15 then return end
	lastFallbackPrune = now
	for key, state in pairs(fallbackBuckets) do
		if now - state.updated > FALLBACK_BUCKET_IDLE_SECONDS then
			fallbackBuckets[key] = nil
		end
	end
end

local function fallbackBucket(key: string, capacity: number, refill: number, cost: number): boolean
	local now = os.clock()
	pruneFallbackBuckets(now)
	local state = fallbackBuckets[key]
	if not state then
		-- Bound cardinality even during bursts of unique user IDs between prune passes.
		local count = 0
		local oldestKey: string? = nil
		local oldestUpdated = math.huge
		for existingKey, existing in pairs(fallbackBuckets) do
			count += 1
			if existing.updated < oldestUpdated then
				oldestUpdated = existing.updated
				oldestKey = existingKey
			end
		end
		if count >= MAX_FALLBACK_BUCKETS and oldestKey then
			fallbackBuckets[oldestKey] = nil
		end
		state = {tokens = capacity, updated = now}
		fallbackBuckets[key] = state
	end
	state.tokens = math.min(capacity, state.tokens + math.max(0, now - state.updated) * refill)
	state.updated = now
	if state.tokens < cost then return false end
	state.tokens -= cost
	return true
end

local function consumeLocalBudget(key: string, capacity: number, refill: number, cost: number): (boolean, boolean)
	if not finiteNumber(cost) or cost <= 0 or cost > capacity then return false, false end
	-- This limiter is intentionally local to this server. The bounded token
	-- buckets do not depend on MemoryStore availability or shared state.
	return fallbackBucket(
		key,
		math.min(capacity, CONFIG.FallbackPlayerCapacity),
		CONFIG.FallbackPlayerRefillPerSecond,
		cost
	), false
end

local function userKey(userId: number): string?
	if not finiteNumber(userId) or userId < 1 or userId % 1 ~= 0 then return nil end
	return tostring(math.floor(userId))
end

local function getModeration(userId: number): {[string]: any}
	local key = userKey(userId)
	if not key then return {} end
	-- Bound durable reads with a per-server token bucket. Exhaustion fails closed;
	-- no MemoryStore request or shared budget is involved.
	local budgetAllowed = consumeLocalBudget("all:datastore", 90, 15, 1)
	if not budgetAllowed then
		return {lookupFailed = true}
	end
	local ok, data = pcall(function() return moderationStore:GetAsync(key) end)
	if not ok then
		warn("[ClubMusic Global] Moderation lookup failed for " .. key .. ": " .. tostring(data))
		return {lookupFailed = true}
	end
	return if typeof(data) == "table" then data else {}
end

local publishTopic: (string, {[string]: any}) -> boolean

local function updateModeration(userId: number, field: string, value: any, actorUserId: number, reason: string?): boolean
	local key = userKey(userId)
	if not key or (field ~= "globalBan" and field ~= "requestBlocked") then return false end
	local budgetAllowed = consumeLocalBudget("all:datastore", 90, 15, 1)
	-- The bounded per-server token bucket remains mandatory; reject only when exhausted.
	if not budgetAllowed then
		warn("[ClubMusic Global] Moderation update rejected: local DataStore budget exhausted.")
		return false
	end
	local ok, result = pcall(function()
		return moderationStore:UpdateAsync(key, function(old)
			local data = if typeof(old) == "table" then table.clone(old) else {}
			data[field] = value
			data.updatedAt = os.time()
			data.updatedBy = actorUserId
			data.reason = reason
			local history = if typeof(data.history) == "table" then table.clone(data.history) else {}
			table.insert(history, 1, {field = field, value = value, actorUserId = math.floor(actorUserId), reason = reason, at = os.time()})
			while #history > 20 do table.remove(history) end
			data.history = history
			return data
		end)
	end)
	if not ok or typeof(result) ~= "table" then
		warn("[ClubMusic Global] Moderation update failed for " .. key .. ": " .. tostring(result))
		return false
	end
	recordSecurityReplay("moderation_" .. field, userId, 0, "Warning", "GlobalModeration", {
		actorUserId = actorUserId,
		value = value,
	})
	local message = {
		version = 1, senderJob = JOB_ID, id = HttpService:GenerateGUID(false),
		kind = "Moderation", userId = userId, field = field, value = value,
		actorUserId = actorUserId, reason = reason, at = os.time(),
	}
	local published = publishTopic(CONFIG.Topics.Moderation, message)
	if not published then warn("[ClubMusic Global] Moderation publish failed; periodic reconciliation remains active.") end
	-- The local event listener writes one audit record. Do not write here as well.
	globalEventBindable:Fire({kind = "Moderation", userId = userId, field = field, value = value,
		actorUserId = actorUserId, reason = reason, senderJob = JOB_ID})
	return true
end

publishTopic = function(topic: string, payload: {[string]: any}): boolean
	if not SERVICE_ENABLED then return false end
	payload.version = 1
	payload.senderJob = JOB_ID
	payload.id = HttpService:GenerateGUID(false)
	payload.at = os.time()
	local ok, err = pcall(function() MessagingService:PublishAsync(topic, payload) end)
	if not ok then
		messagingPublishFailures += 1
		messagingLastError = string.sub(tostring(err), 1, 240)
		warn("[ClubMusic Global] Publish failed on topic " .. topic .. ": " .. tostring(err))
		return false
	end
	messagingPublishSuccess += 1
	messagingLastError = nil
	if globalDiagnosticsService then pcall(globalDiagnosticsService.Record, globalDiagnosticsService, "publish:" .. tostring(payload.kind or "unknown"), 1) end
	if globalAuditService then
		if payload.kind == "DJ" then
			pcall(globalAuditService.Record, globalAuditService, "AdminAction", payload.actorUserId, tostring(payload.command), tostring(payload.command))
		elseif payload.kind == "Catalog" and typeof(payload.trackId) ~= "string" then
			pcall(globalAuditService.Record, globalAuditService, "CatalogChange", 0, "catalog", "invalidate")
		end
	end
	return true
end

bindFunction("ConsumeActionBudget", function(userId: any, action: any, cost: any)
	if not SERVICE_ENABLED then return true end
	local key = userKey(userId)
	if not key or typeof(action) ~= "string" or #action > 40 then return false end
	local globalOk, globalShared
	if globalRateLimitService then
		globalOk, globalShared = globalRateLimitService:Consume("all:actions", CONFIG.GlobalActionCapacity, CONFIG.GlobalActionRefillPerSecond, if finiteNumber(cost) then cost else 1)
	else
		globalOk, globalShared = consumeLocalBudget("all:actions", CONFIG.GlobalActionCapacity, CONFIG.GlobalActionRefillPerSecond, if finiteNumber(cost) then cost else 1)
	end
	if not globalShared or not globalOk then return false end
	local playerOk, playerShared
	if globalRateLimitService then
		playerOk, playerShared = globalRateLimitService:Consume("user:" .. key, CONFIG.GlobalPlayerCapacity, CONFIG.GlobalPlayerRefillPerSecond, if finiteNumber(cost) then cost else 1)
	else
		playerOk, playerShared = consumeLocalBudget("user:" .. key, CONFIG.GlobalPlayerCapacity, CONFIG.GlobalPlayerRefillPerSecond, if finiteNumber(cost) then cost else 1)
	end
	-- Global action enforcement must not silently degrade to independent server buckets.
	return playerShared and playerOk
end)

bindFunction("ConsumeStateBudget", function(userId: any)
	if not SERVICE_ENABLED then return true end
	local key = userKey(userId)
	if not key then return false end
	local globalOk, globalShared = consumeLocalBudget("all:state", 300, 100, 1)
	if not globalShared or not globalOk then return false end
	local playerOk, playerShared = consumeLocalBudget("state:" .. key, 12, 2, 1)
	return playerShared and playerOk
end)

bindFunction("ConsumeDataStoreBudget", function()
	if not SERVICE_ENABLED then return true end
	local allowed, shared = consumeLocalBudget("all:datastore", 90, 15, 1)
	-- Avoid a cross-server DataStore thundering herd when MemoryStore is unavailable.
	return shared and allowed
end)

bindFunction("ConsumeAudioBudget", function(userId: any)
	if not SERVICE_ENABLED then return true end
	local key = userKey(userId)
	if not key then return false end
	local globalOk, globalShared = consumeLocalBudget("all:audio", CONFIG.GlobalAudioCapacity, CONFIG.GlobalAudioRefillPerSecond, 1)
	if not globalShared or not globalOk then return false end
	local playerOk, playerShared = consumeLocalBudget("audio:" .. key, 3, 0.2, 1)
	return playerShared and playerOk
end)

bindFunction("IsGloballyBanned", function(userId: any)
	if not SERVICE_ENABLED then return false, false end
	local data = getModeration(userId)
	if data.lookupFailed then return false, false end
	return data.globalBan == true, true, data.reason
end)

-- Join-time moderation uses one authoritative durable read for both ban and
-- request-block state. This avoids two sequential DataStore lookups per player.
bindFunction("GetModerationState", function(userId: any)
	if not SERVICE_ENABLED then return false, false end
	local data = getModeration(userId)
	if data.lookupFailed then return false, false end
	return true, data.globalBan == true, data.requestBlocked == true, data.reason
end)

bindFunction("SetGlobalBan", function(userId: any, banned: any, actorUserId: any, reason: any)
	if not SERVICE_ENABLED or typeof(banned) ~= "boolean" or not finiteNumber(actorUserId) or not authorizeGlobalActor(actorUserId, "GlobalModeration") then return false end
	local cleanReason = if reason == nil then nil else cleanText(reason, CONFIG.MaxModerationReasonLength)
	if reason ~= nil and not cleanReason then return false end
	return updateModeration(userId, "globalBan", banned, actorUserId, cleanReason)
end)

bindFunction("IsRequestBlocked", function(userId: any)
	if not SERVICE_ENABLED then return false, true end
	local data = getModeration(userId)
	if data.lookupFailed then return false, false end
	return data.requestBlocked == true, true
end)

bindFunction("SetRequestBlocked", function(userId: any, blocked: any, actorUserId: any, reason: any)
	if not SERVICE_ENABLED or typeof(blocked) ~= "boolean" or not finiteNumber(actorUserId) or not authorizeGlobalActor(actorUserId, "GlobalModeration") then return false end
	local cleanReason = if reason == nil then nil else cleanText(reason, CONFIG.MaxModerationReasonLength)
	if reason ~= nil and not cleanReason then return false end
	return updateModeration(userId, "requestBlocked", blocked, actorUserId, cleanReason)
end)

bindFunction("GetModerationHistory", function(userId: any, actorUserId: any, limit: any)
	if not SERVICE_ENABLED or not userKey(userId) or not finiteNumber(actorUserId)
		or not authorizeGlobalActor(actorUserId, "GlobalModeration") then return false, nil end
	local data = getModeration(userId)
	if data.lookupFailed then return false, nil end
	local history = if typeof(data.history) == "table" then data.history else {}
	local result = {}
	local count = math.clamp(math.floor(if finiteNumber(limit) then limit else 10), 1, 20)
	for index = 1, math.min(#history, count) do
		local item = history[index]
		if typeof(item) == "table" then
			table.insert(result, {field = tostring(item.field or "unknown"), value = item.value == true,
				actorUserId = if finiteNumber(item.actorUserId) then math.floor(item.actorUserId) else 0,
				reason = if typeof(item.reason) == "string" then string.sub(item.reason, 1, 120) else "",
				at = if finiteNumber(item.at) then math.floor(item.at) else 0})
		end
	end
	return true, result
end)

local function validTrackKey(trackId: any): string?
	if typeof(trackId) ~= "string" or #trackId < 1 or #trackId > 64
		or not string.match(trackId, "^[%w%-_]+$") then return nil end
	return "trackBlock_" .. trackId
end

bindFunction("IsTrackBlocked", function(trackId: any)
	local key = validTrackKey(trackId)
	if not SERVICE_ENABLED or not key then return false, false end
	local allowed = consumeLocalBudget("all:datastore", 90, 15, 1)
	if not allowed then return false, false end
	local ok, record = pcall(function() return globalControlStore:GetAsync(key) end)
	if not ok then return false, false end
	return typeof(record) == "table" and record.blocked == true, true
end)

bindFunction("SetTrackBlocked", function(trackId: any, blocked: any, actorUserId: any, reason: any)
	local key = validTrackKey(trackId)
	if not SERVICE_ENABLED or not key or typeof(blocked) ~= "boolean"
		or not finiteNumber(actorUserId) or not authorizeGlobalActor(actorUserId, "GlobalModeration") then return false end
	local cleanReason = if reason == nil then nil else cleanText(reason, CONFIG.MaxModerationReasonLength)
	if reason ~= nil and not cleanReason then return false end
	local allowed = consumeLocalBudget("all:datastore", 90, 15, 1)
	if not allowed then return false end
	local ok, record = pcall(function()
		return globalControlStore:UpdateAsync(key, function(old)
			local nextRecord = if typeof(old) == "table" then table.clone(old) else {}
			nextRecord.blocked = blocked
			nextRecord.trackId = trackId
			nextRecord.updatedAt = os.time()
			nextRecord.updatedBy = math.floor(actorUserId)
			nextRecord.reason = cleanReason
			return nextRecord
		end)
	end)
	if not ok or typeof(record) ~= "table" or record.blocked ~= blocked then return false end
	if globalAuditService then pcall(globalAuditService.Record, globalAuditService, "Moderation", math.floor(actorUserId), trackId, "trackBlock=" .. tostring(blocked) .. (if cleanReason then " | " .. cleanReason else "")) end
	publishTopic(CONFIG.Topics.Catalog, {kind = "Catalog", trackId = trackId, blocked = blocked})
	globalEventBindable:Fire({kind = "TrackModeration", trackId = trackId, blocked = blocked, senderJob = JOB_ID})
	return true
end)

bindFunction("PublishAnnouncement", function(message: any, actorUserId: any)
	if not SERVICE_ENABLED or not finiteNumber(actorUserId) or actorUserId < 1
		or actorUserId % 1 ~= 0 or actorUserId > 9007199254740991 then return false end
	local actorId = math.floor(actorUserId)
	local actor = Players:GetPlayerByUserId(actorId)
	if not actor or actor.Parent ~= Players or not authorizeGlobalActor(actorId, "GlobalAnnouncement") then return false end

	local filteredText = filterAnnouncementText(message, actorId)
	if not filteredText or actor.Parent ~= Players
		or not authorizeGlobalActor(actorId, "GlobalAnnouncement") then return false end

	return publishTopic(CONFIG.Topics.Announcements, {
		kind = "Announcement",
		text = filteredText,
		actorUserId = actorId,
	})
end)


local function allowGlobalDataStoreOperation(): boolean
	-- Shared DataStore operations retain a conservative per-server budget
	-- when the optional cross-server MemoryStore budget is unavailable.
	local allowed = consumeLocalBudget("all:datastore", 90, 15, 1)
	return allowed == true
end

bindFunction("PublishCatalogChange", function()
	if not SERVICE_ENABLED then return false end
	return publishTopic(CONFIG.Topics.Catalog, {kind = "Catalog"})
end)

bindFunction("IsEnabled", function()
	-- Reports availability of global moderation/configuration services only.
	-- Optional playback-only sync has its own separately gated API and status.
	return SERVICE_ENABLED
end)

-- Global playback synchronization is retired. Every server owns its own Now Playing
-- state and request queue; global moderation, announcements, catalog invalidation,
-- and XP boost coordination remain independent services.
local function getGlobalSyncStatus(): {[string]: any}
	return {
		state = "LocalOnly",
		detail = "Global playback sync is retired. Each server owns its own playback and request queue.",
		playbackSyncEnabled = false,
		localQueueIsolated = true,
		peerCount = 0,
		queueNotificationsReceived = 0,
	}
end

-- Reuse the same per-server diagnostic handler used by the local UI controller.
-- This is intentionally optional: diagnostics must never prevent global service startup.
local globalErrorHandler: any = nil
local errorHandlerModule = ServerStorage:FindFirstChild("ClubMusicErrorHandler")
if errorHandlerModule and errorHandlerModule:IsA("ModuleScript") then
	local handlerOk, handlerResult = pcall(require, errorHandlerModule)
	if handlerOk and typeof(handlerResult) == "table" and type(handlerResult.Report) == "function" then
		globalErrorHandler = handlerResult
	else
		warn("[ClubMusic Global] ClubMusicErrorHandler could not be loaded; using local warnings.")
	end
else
	warn("[ClubMusic Global] ClubMusicErrorHandler is unavailable; using local warnings.")
end

local function reportOperationalError(subsystem: string, operation: string, err: any, context: Instance?)
	local metricName = string.lower(tostring(subsystem)) .. ":" .. string.lower(tostring(operation))
	if globalDiagnosticsService then
		pcall(globalDiagnosticsService.Record, globalDiagnosticsService, "error:" .. string.sub(metricName, 1, 42), 1)
		if string.find(metricName, "playback", 1, true) or string.find(metricName, "audio", 1, true) then
			pcall(globalDiagnosticsService.Record, globalDiagnosticsService, "playbackFailure", 1)
		end
	end
	if globalErrorHandler then
		local reportOk, reportResult = pcall(
			globalErrorHandler.Report,
			subsystem,
			operation,
			err,
			context or script
		)
		if reportOk then return reportResult end
		warn("[ClubMusic Global] Error handler reporting failed: " .. tostring(reportResult))
	end
	warn("[ClubMusic Global][" .. subsystem .. "][" .. operation .. "] " .. tostring(err))
	return nil
end

local OPTIONAL_GLOBAL_MODULE_ALIASES: {[string]: {string}} = {
		ClubMusic_Global_RateLimit_Service = {
		"ClubMusic_Global_RateLimit_Service",
		"ClubMusic_Global_Ratelimit_Service",
	},
}

local SECURITY_MODULE_EXPORTS: {[string]: string} = {
	ClubMusic_Global_Authorization_Service = "Authorization",
	ClubMusic_Global_RateLimit_Service = "RateLimit",
	ClubMusic_Global_Message_Validation_Service = "MessageValidation",
	ClubMusic_Global_Idempotency_Service = "Idempotency",
	ClubMusic_Global_Security_Monitor_Service = "SecurityMonitor",
	ClubMusic_Global_Security_Policy_Service = "SecurityPolicy",
	ClubMusic_Global_Audit_Service = "Audit",
	ClubMusic_Global_Event_Log_Service = "EventLog",
	ClubMusic_Global_Incident_Response_Service = "IncidentResponse",
	ClubMusic_Global_Connection_Janitor_Service = "ConnectionJanitor",
}
local cachedSecurityBundle: any = nil
local securityBundleLoadAttempted = false
local EXPECTED_SECURITY_CORE_RELEASE = "142562f0727f8c3fa748a9bd00dbd1871e5f4fe9"
local securityCoreInstallStatus: {[string]: any} = {
 state = "NotChecked",
 expectedRelease = EXPECTED_SECURITY_CORE_RELEASE,
 installedRelease = nil,
 manifestPresent = false,
}

local function loadOptionalGlobalModule(moduleName: string): any?
	local securityExport = SECURITY_MODULE_EXPORTS[moduleName]
	if securityExport then
		-- Preferred layout: independently maintained private ModuleScripts under
		-- ServerStorage/ClubMusicSecurityCore. A present-but-invalid split folder
		-- fails closed instead of silently loading an outdated fallback.
		local privateCore = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
		if privateCore then
			if not privateCore:IsA("Folder") then
				securityCoreInstallStatus.state = "InvalidContainer"
				warn("[ClubMusic Global] Private security core has an invalid container type.")
				return nil
			end
			local manifest = privateCore:FindFirstChild("InstallManifest")
			if manifest then
				if not manifest:IsA("StringValue") then
					securityCoreInstallStatus.state = "InvalidManifest"
					warn("[ClubMusic Global] Security Core install manifest has the wrong class.")
					return nil
				end
				local installedRelease = string.match(manifest.Value, "[Rr]elease=([%w]+)")
				securityCoreInstallStatus.manifestPresent = true
				securityCoreInstallStatus.installedRelease = installedRelease
				if installedRelease ~= EXPECTED_SECURITY_CORE_RELEASE then
					securityCoreInstallStatus.state = "VersionMismatch"
					warn("[ClubMusic Global] Security Core release mismatch; refusing split modules.")
					return nil
				end
				securityCoreInstallStatus.state = "VersionVerified"
			else
				securityCoreInstallStatus.state = "InstalledUnversioned"
			end
			local privateModule = privateCore:FindFirstChild(securityExport)
			if not privateModule or not privateModule:IsA("ModuleScript") then
				warn("[ClubMusic Global] Private security module is missing: " .. securityExport)
				return nil
			end
			local moduleOk, exported = pcall(require, privateModule)
			if not moduleOk or typeof(exported) ~= "table" or type(exported.new) ~= "function" then
				warn("[ClubMusic Global] Private security module failed validation: " .. securityExport
					.. "; error=" .. string.sub(tostring(exported), 1, 180))
				return nil
			end
			return exported
		end

		-- Backward compatibility only: existing places without the split folder
		-- continue to use the previously installed consolidated bundle.
		if not securityBundleLoadAttempted then
			securityBundleLoadAttempted = true
			local bundleModule = ServerStorage:FindFirstChild("ClubMusic_Global_Security_Service")
				or ServerStorage:FindFirstChild("ClubMusic_Global_Security_Service", true)
			if bundleModule and bundleModule:IsA("ModuleScript") then
				local bundleOk, bundle = pcall(require, bundleModule)
				if bundleOk and typeof(bundle) == "table" then
					cachedSecurityBundle = bundle
				else
					warn("[ClubMusic Global] Legacy security bundle failed to load: " .. tostring(bundle))
				end
			else
				warn("[ClubMusic Global] No split security core or legacy bundle exists under ServerStorage.")
			end
		end
		local exported = if cachedSecurityBundle then cachedSecurityBundle[securityExport] else nil
		if typeof(exported) ~= "table" or type(exported.new) ~= "function" then
			warn("[ClubMusic Global] Security export is unavailable: " .. moduleName)
			return nil
		end
		return exported
	end
	-- Support canonical names and established instance-name aliases for non-security modules.
	local candidates = OPTIONAL_GLOBAL_MODULE_ALIASES[moduleName] or {moduleName}
	local module: Instance? = nil
	local resolvedName = moduleName
	for _, candidateName in ipairs(candidates) do
		local candidate = ServerStorage:FindFirstChild(candidateName)
			or ServerStorage:FindFirstChild(candidateName, true)
		if candidate and candidate:IsA("ModuleScript") then
			module = candidate
			resolvedName = candidateName
			break
		end
	end
	if not module then
		warn("[ClubMusic Global] Optional service ModuleScript is missing under ServerStorage: "
			.. moduleName .. " (accepted names: " .. table.concat(candidates, ", ") .. ")")
		return nil
	end
	if resolvedName ~= moduleName then
		warn("[ClubMusic Global] Resolved " .. moduleName .. " using existing instance name "
			.. module:GetFullName() .. ".")
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn("[ClubMusic Global] Optional service failed to load (" .. moduleName .. "): " .. tostring(result))
		return nil
	end
	if typeof(result) ~= "table" or type(result.new) ~= "function" then
		warn("[ClubMusic Global] Optional service has an invalid module contract: " .. moduleName)
		return nil
	end
	return result
end

-- Shared SafeCall diagnostics are optional and never gate core global behavior.
local safeCallModule = loadOptionalGlobalModule("ClubMusic_Global_SafeCall_Service")
local globalSafeCall: any = nil
if safeCallModule then
	local safeOk, safeInstance = pcall(function()
		return safeCallModule.new({
			serviceName = "ClubMusicGlobal",
			onFailure = function(_serviceName, _operation)
				recordThreatIntelligence("safe_call_failed", 0, "SafeCall", "Warning")
			end,
		})
	end)
	if safeOk and typeof(safeInstance) == "table"
		and type(safeInstance.Run) == "function"
		and type(safeInstance.GetStatus) == "function"
		and type(safeInstance.GetRecent) == "function" then
		globalSafeCall = safeInstance
	else
		warn("[ClubMusic][SafeCall] Diagnostics helper unavailable; existing protected-call behavior remains active: " .. tostring(safeInstance))
	end
end
if globalSafeCall then
	bindFunction("GetGlobalMemoryStoreStatus", function()
		return {
			sharedRateLimitsEnabled = false,
			capacityLimited = false,
			lastCapacityError = nil,
			playbackLeaseEnabled = false,
			mode = "LocalOnly",
			detail = "MemoryStore is not used for playback synchronization; playback and request queues are server-local.",
		}
	end)

bindFunction("GetGlobalSafeCallStatus", function()
		return globalSafeCall:GetStatus()
	end)
	bindFunction("GetGlobalSafeCallRecent", function(limit: any)
		return globalSafeCall:GetRecent(if finiteNumber(limit) then limit else 20)
	end)
	print("[ClubMusic][SafeCall] Diagnostics helper ready; maxRecords=50.")
end

-- Optional server-local registry. It records status only; it never controls services.
do
	local module = ServerStorage:FindFirstChild("ClubMusic_Local_Service_Registry")
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new)
			if createOk and typeof(instance) == "table"
				and type(instance.Register) == "function"
				and type(instance.SetStatus) == "function"
				and type(instance.GetStatus) == "function"
				and type(instance.RegisterDependency) == "function" then
				globalServiceRegistry = instance
				pcall(instance.RegisterDependency, instance, "GlobalAPI", apiFolder, "Folder", ServerStorage, true)
			if globalErrorHandler and type(globalErrorHandler.GetStatus) == "function" then
				pcall(instance.Register, instance, "ErrorHistory", globalErrorHandler, {"Report", "GetRecentErrors", "GetStatus"}, true)
			else
				pcall(instance.SetStatus, instance, "ErrorHistory", "Unavailable", "ClubMusicErrorHandler is not installed.")
			end
			else
				warn("[ClubMusic Diagnostics] Local service registry initialization failed: " .. tostring(instance))
			end
		else
			warn("[ClubMusic Diagnostics] Local service registry could not be loaded: " .. tostring(exported))
		end
	else
		warn("[ClubMusic Diagnostics] Optional ClubMusic_Local_Service_Registry ModuleScript is not installed.")
	end
end

local function updateRegistryStatus(name: string, state: string, detail: string)
	if globalServiceRegistry then
		pcall(globalServiceRegistry.SetStatus, globalServiceRegistry, name, state, detail)
	end
end

-- Local ServerHealth probe: heartbeat timing and process memory only.
do
	local module = ServerStorage:FindFirstChild("ClubMusic_Server_Health_Service")
	if globalServiceRegistry then
		if module and module:IsA("ModuleScript") then
			pcall(globalServiceRegistry.RegisterDependency, globalServiceRegistry, "ServerHealthModule", module, "ModuleScript", ServerStorage, false)
		else
			updateRegistryStatus("ServerHealthModule", "NotInstalled", "ServerHealth ModuleScript is not installed directly under ServerStorage.")
		end
	end
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new)
			if createOk and typeof(instance) == "table" and type(instance.Start) == "function"
				and type(instance.GetStatus) == "function" and type(instance.Stop) == "function" then
				globalServerHealthService = instance
				local startOk, started = pcall(instance.Start, instance)
				if startOk and started == true then
					if globalServiceRegistry then
						pcall(globalServiceRegistry.Register, globalServiceRegistry, "ServerHealth", instance, {"Start", "GetStatus", "Stop"}, false)
					end
				else
					globalServerHealthService = nil
					updateRegistryStatus("ServerHealth", "Unavailable", "ServerHealth probe failed to start.")
					warn("[ClubMusic Diagnostics] ServerHealth probe failed to start.")
				end
			else
				updateRegistryStatus("ServerHealth", "Unavailable", "ServerHealth module has an invalid interface.")
				warn("[ClubMusic Diagnostics] ServerHealth module has an invalid interface.")
			end
		else
			updateRegistryStatus("ServerHealth", "Unavailable", "ServerHealth module failed to load.")
			warn("[ClubMusic Diagnostics] ServerHealth module failed to load: " .. tostring(exported))
		end
	else
		updateRegistryStatus("ServerHealth", "NotInstalled", "Optional ServerHealth module is not installed.")
		warn("[ClubMusic Diagnostics] Optional ClubMusic_Server_Health_Service ModuleScript is not installed.")
	end
end

-- Local Watchdog records progress pulses only; it never controls the observed systems.
do
	local module = ServerStorage:FindFirstChild("ClubMusic_Local_Watchdog_Service")
	if globalServiceRegistry then
		if module and module:IsA("ModuleScript") then
			pcall(globalServiceRegistry.RegisterDependency, globalServiceRegistry, "WatchdogModule", module, "ModuleScript", ServerStorage, false)
		else
			updateRegistryStatus("WatchdogModule", "NotInstalled", "Watchdog ModuleScript is not installed directly under ServerStorage.")
		end
	end
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new)
			if createOk and typeof(instance) == "table" and type(instance.Pulse) == "function"
				and type(instance.SetExpected) == "function" and type(instance.GetStatus) == "function" then
				globalLocalWatchdog = instance
				if globalServiceRegistry then
					pcall(globalServiceRegistry.Register, globalServiceRegistry, "Watchdog", instance, {"Pulse", "SetExpected", "GetStatus"}, false)
				end
			else
				updateRegistryStatus("Watchdog", "Unavailable", "Watchdog module has an invalid interface.")
				warn("[ClubMusic Diagnostics] Watchdog module has an invalid interface.")
			end
		else
			updateRegistryStatus("Watchdog", "Unavailable", "Watchdog module failed to load.")
			warn("[ClubMusic Diagnostics] Watchdog module failed to load: " .. tostring(exported))
		end
	else
		updateRegistryStatus("Watchdog", "NotInstalled", "Optional Watchdog module is not installed.")
		warn("[ClubMusic Diagnostics] Optional ClubMusic_Local_Watchdog_Service ModuleScript is not installed.")
	end
end

local function readServerStorageStatus(endpointName: string, action: string?)
	local endpoint = ServerStorage:FindFirstChild(endpointName)
	if not endpoint or not endpoint:IsA("BindableFunction") or endpoint.Parent ~= ServerStorage then
		return {state = "NotInstalled", available = false}
	end
	-- BindableFunction:Invoke() yields indefinitely if OnInvoke has not been
	-- assigned. Optional diagnostics providers can be created before their
	-- owning service finishes bootstrapping, so never invoke an unbound endpoint.
	if type(endpoint.OnInvoke) ~= "function" then
		return {state = "Starting", available = false, detail = "Status callback is not bound yet."}
	end
	local ok, result = pcall(function()
		if action then return endpoint:Invoke(action) end
		return endpoint:Invoke()
	end)
	if not ok or typeof(result) ~= "table" then
		return {state = "Unavailable", available = false}
	end
	return result
end

local diagnosticsModuleInstance: ModuleScript? = nil
for _, candidateName in ipairs(OPTIONAL_GLOBAL_MODULE_ALIASES.ClubMusic_Global_Diagnostics_Service
	or {"ClubMusic_Global_Diagnostics_Service"}) do
	local candidate = ServerStorage:FindFirstChild(candidateName)
		or ServerStorage:FindFirstChild(candidateName, true)
	if candidate and candidate:IsA("ModuleScript") then
		diagnosticsModuleInstance = candidate :: ModuleScript
		break
	end
end
local diagnosticsModule = loadOptionalGlobalModule("ClubMusic_Global_Diagnostics_Service")
if globalServiceRegistry then
	if diagnosticsModuleInstance then
		pcall(globalServiceRegistry.RegisterDependency, globalServiceRegistry, "DiagnosticsModule",
			diagnosticsModuleInstance, "ModuleScript", diagnosticsModuleInstance.Parent, false)
	else
		updateRegistryStatus("DiagnosticsModule", "NotInstalled", "Diagnostics ModuleScript is not installed under ServerStorage.")
	end
end
if diagnosticsModule then
	local createOk, instance = pcall(function()
		return diagnosticsModule.new({
			isEnabled = function() return SERVICE_ENABLED end,
			getRegistryStatus = function() return if globalServiceRegistry then globalServiceRegistry:GetStatus() else {state = "Unavailable", scope = "ServerLocal", detail = "Registry module is not installed."} end,
			getServerHealthStatus = function() return if globalServerHealthService then globalServerHealthService:GetStatus() else nil end,
			getWatchdogStatus = function() return if globalLocalWatchdog then globalLocalWatchdog:GetStatus() else nil end,
			apiFolder = apiFolder,
				getSyncStatus = getGlobalSyncStatus,
			getRecentErrors = function()
				if globalErrorHandler and type(globalErrorHandler.GetRecentErrors) == "function" then return globalErrorHandler.GetRecentErrors() end
				return nil
			end,
			getErrorHistoryStatus = function()
				return if globalErrorHandler and type(globalErrorHandler.GetStatus) == "function"
					then globalErrorHandler.GetStatus() else nil
			end,
			getMemoryStoreStatus = function()
				return {
					sharedRateLimitsEnabled = false,
					playbackLeaseEnabled = false,
					mode = "LocalOnly",
					detail = "Playback synchronization is retired; MemoryStore is not used for playback leadership.",
				}
			end,
			getAuthorizationStatus = function() return if globalAuthorizationService then globalAuthorizationService:GetStatus() else nil end,
			getRateLimitStatus = function() return if globalRateLimitService then globalRateLimitService:GetStatus() else nil end,
			getSecurityPolicyStatus = function() return if globalSecurityPolicyService then globalSecurityPolicyService:GetStatus() else nil end,
			getSecurityMonitorStatus = function() return if globalSecurityMonitorService then globalSecurityMonitorService:GetStatus() else nil end,
			getMessageValidationStatus = function() return if globalMessageValidationService then globalMessageValidationService:GetStatus() else nil end,
			getIdempotencyStatus = function() return if globalIdempotencyService then globalIdempotencyService:GetStatus() else nil end,
			getAuditStatus = function() return if globalAuditService then globalAuditService:GetStatus() else nil end,
			getEventLogStatus = function() return if globalEventLogService then globalEventLogService:GetStatus() else nil end,
			getIncidentResponseStatus = function() return if globalIncidentResponseService then globalIncidentResponseService:GetStatus() else nil end,
			allowAnalyticsAggregation = function()
				local endpoint = ServerStorage:FindFirstChild("TikiTideSecurityLoadManager")
				if not endpoint or not endpoint:IsA("BindableFunction") or type(endpoint.OnInvoke) ~= "function" then return true end
				local ok, allowed = pcall(function() return endpoint:Invoke("TryConsume", "AnalyticsAggregation") end)
				-- Analytics are optional; an unavailable governor must not break diagnostics reads.
				return not ok or allowed == true
			end,
			getAdaptiveLoadStatus = function() return readServerStorageStatus("GetTikiTideSecurityLoadStatus") end,
			getSecurityReplayStatus = function() return readServerStorageStatus("GetTikiTideSecurityReplayStatus") end,
			getThreatIntelligenceStatus = function() return readServerStorageStatus("GetTikiTideThreatIntelligenceStatus") end,
			getHoneypotStatus = function() return readServerStorageStatus("GetTikiTideHoneypotStatus") end,
			getClientIntegrityStatus = function() return readServerStorageStatus("GetTikiTideClientIntegrityStatus") end,
			getControllerDiagnostics = function() return readServerStorageStatus("GetClubMusicLocalDiagnostics") end,
			getCharacterPhysicsStatus = function() return readServerStorageStatus("GetTikiTideCharacterPhysicsGuardStatus") end,
			getSafeCallStatus = function()
				if not globalSafeCall then return nil end
				local result = globalSafeCall:GetStatus()
				result.state = if result.lastOutcome == "Failure" then "Degraded" else "Healthy"
				result.detail = if result.lastOutcome == "Failure" then "The most recent protected operation ended in failure."
					else "The latest protected operation succeeded or recovered."
				return result
			end,
		})
	end)
	if createOk and instance and type(instance.Start) == "function"
		and type(instance.GetStatus) == "function" and type(instance.GetSnapshot) == "function" then
		globalDiagnosticsService = instance
		if globalServiceRegistry then pcall(globalServiceRegistry.Register, globalServiceRegistry, "Diagnostics", instance, {"Start", "Check", "GetStatus", "GetSnapshot", "GetMetrics"}, true) end
		task.delay(4, function()
			if globalDiagnosticsService == instance then
				local startOk, startError = pcall(function() instance:Start() end)
				if not startOk then warn("[ClubMusic Diagnostics] Delayed startup failed: " .. tostring(startError)) end
			end
		end)
	else
		updateRegistryStatus("Diagnostics", "Unavailable", "Diagnostics coordinator failed to initialize.")
		warn("[ClubMusic Global] Could not initialize lightweight Diagnostics Service: " .. tostring(instance))
	end
else
	updateRegistryStatus("Diagnostics", "NotInstalled", "Diagnostics coordinator ModuleScript is not installed.")
	warn("[ClubMusic Diagnostics] Optional ClubMusic_Global_Diagnostics_Service ModuleScript is not installed.")
end

-- Operational services are optional modules and fail independently. They manage
-- shared configuration, moderation, security, and bounded diagnostics only.
local function createOperationalService(moduleName: string, dependencies: {[string]: any}, requiredMethods: {string}): any?
	-- These optional modules are cross-server infrastructure, not local playback
	-- dependencies. Do not construct them in isolated Studio sessions.
	if not SERVICE_ENABLED then
		updateRegistryStatus(moduleName, "Disabled", "Global service is disabled in this server.")
		return nil
	end
	local module = loadOptionalGlobalModule(moduleName)
	if not module then
		updateRegistryStatus(moduleName, "Unavailable", "Optional ModuleScript is not installed or failed to load.")
		return nil
	end
	local ok, instance = pcall(function() return module.new(dependencies) end)
	if not ok or typeof(instance) ~= "table" then
		warn("[ClubMusic Global] Could not create " .. moduleName .. ": " .. tostring(instance))
		updateRegistryStatus(moduleName, "Unavailable", "Service constructor failed.")
		return nil
	end
	for _, methodName in ipairs(requiredMethods) do
		if type(instance[methodName]) ~= "function" then
			warn("[ClubMusic Global] " .. moduleName .. " is missing method " .. methodName)
			updateRegistryStatus(moduleName, "Unavailable", "Required method missing: " .. methodName)
			return nil
		end
	end
	if globalServiceRegistry then
		pcall(globalServiceRegistry.Register, globalServiceRegistry, moduleName, instance, requiredMethods, false)
	end
	return instance
end


local sharedDependencies = {
	safeCall = globalSafeCall,
	isEnabled = function() return SERVICE_ENABLED end,
	memoryStoreService = MemoryStoreService,
	dataStore = globalConfigStore,
	allowStoreOperation = allowGlobalDataStoreOperation,
	jobId = JOB_ID,
	guid = function() return HttpService:GenerateGUID(false) end,
	jsonEncode = function(value) return HttpService:JSONEncode(value) end,
	jsonDecode = function(value) return HttpService:JSONDecode(value) end,
}
globalConfigService = createOperationalService("ClubMusic_Global_Config_Service", sharedDependencies, {"Start", "GetStatus", "Get", "Set", "SetLocal"})

if globalConfigService then globalConfigService:Start() end

local auditDependencies = table.clone(sharedDependencies)
auditDependencies.isEnabled = function()
	return SERVICE_ENABLED and globalConfigService ~= nil and globalConfigService:Get("auditEnabled") == true
end
globalAuditService = createOperationalService("ClubMusic_Global_Audit_Service", auditDependencies, {"Start", "GetStatus", "Record", "GetRecent"})
if globalAuditService then globalAuditService:Start() end

globalEventLogService = if globalAuditService then createOperationalService("ClubMusic_Global_Event_Log_Service", {
	isEnabled = auditDependencies.isEnabled,
	auditService = globalAuditService,
}, {"Start", "GetStatus", "Record", "GetRecent"}) else nil
if globalEventLogService then globalEventLogService:Start() end

globalRateLimitService = createOperationalService("ClubMusic_Global_RateLimit_Service", {
	isEnabled = function() return SERVICE_ENABLED end,
	consumeLocalBudget = consumeLocalBudget,
}, {"Start", "GetStatus", "Consume"})
if globalRateLimitService then globalRateLimitService:Start() end

globalMaintenanceService = if globalConfigService then createOperationalService("ClubMusic_Global_Maintenance_Service", {
	isEnabled = function() return SERVICE_ENABLED end,
	configService = globalConfigService,
	publish = function(payload)
		globalEventBindable:Fire(payload)
		if globalAuditService then globalAuditService:Record("Maintenance", 0, "global", if payload.enabled then "enabled" else "disabled") end
	end,
}, {"Start", "GetStatus", "Set"}) else nil
if globalMaintenanceService then globalMaintenanceService:Start() end

-- Authorization is owned by the installed SecurityCore module. There is no
-- controller BindableFunction resolver or legacy authorization fallback.
local authorizationModule = loadOptionalGlobalModule("ClubMusic_Global_Authorization_Service")
if authorizationModule and type(authorizationModule.GetShared) == "function" then
	local createOk, instance = pcall(function()
		return authorizationModule.GetShared({
			groupId = 500470662,
			studioStaff = true,
			onDenied = function(actorUserId, permission, count)
				if globalAuditService then
					pcall(globalAuditService.Record, globalAuditService, "SecurityEvent", actorUserId,
						permission, "repeated-privilege-denial:" .. tostring(count))
				end
			end,
		})
	end)
	if createOk and typeof(instance) == "table"
		and type(instance.Start) == "function"
		and type(instance.GetStatus) == "function"
		and type(instance.Check) == "function" then
		globalAuthorizationService = instance
		if globalServiceRegistry then pcall(globalServiceRegistry.Register, globalServiceRegistry, "Authorization", instance, {"Start", "GetStatus", "Check"}, true) end
		local authStartOk, authStartResult = pcall(instance.Start, instance)
		if not authStartOk or authStartResult ~= true then
			warn("[ClubMusic][Authorization] SecurityCore authorization failed to start; protected actions remain denied.")
			globalAuthorizationService = nil
			updateRegistryStatus("Authorization", "Unavailable", "SecurityCore Authorization failed to start.")
		end
	else
		warn("[ClubMusic][Authorization] SecurityCore authorization module could not be initialized: "
			.. tostring(instance))
		updateRegistryStatus("Authorization", "Unavailable", "SecurityCore Authorization could not initialize.")
	end
else
	warn("[ClubMusic][Authorization] SecurityCore Authorization module is unavailable; protected actions remain denied.")
	updateRegistryStatus("Authorization", "Unavailable", "SecurityCore Authorization ModuleScript is missing.")
end

authorizeGlobalActor = function(actorUserId: any, permission: string): boolean
	local service = globalAuthorizationService
	if not service then return false end
	local ok, allowed, reason = pcall(service.Check, service, actorUserId, permission)
	if not ok then
		warn("[ClubMusic][Authorization] SecurityCore Check failed; access denied: " .. string.sub(tostring(allowed), 1, 180))
		return false
	end
	return allowed == true
end

-- Cross-server playback synchronization has been retired. No playback authority,
-- shared playback configuration, leader lease, or playback API is initialized.

globalSecurityPolicyService = createOperationalService("ClubMusic_Global_Security_Policy_Service", {
	configService = globalConfigService,
	authorize = authorizeGlobalActor,
	onChange = function(key, value, revision, actor)
		if globalAuditService then pcall(globalAuditService.Record, globalAuditService, "SecurityEvent", actor, key, "policy-update") end
	end,
}, {"Start", "GetStatus", "Get", "GetAll", "Set"})
if globalSecurityPolicyService then globalSecurityPolicyService:Start() end

globalSecurityMonitorService = createOperationalService("ClubMusic_Global_Security_Monitor_Service", {
	isEnabled = function() return SERVICE_ENABLED and globalSecurityPolicyService ~= nil and globalSecurityPolicyService:Get("monitoringEnabled") == true end,
	memoryStoreService = MemoryStoreService,
	jobId = JOB_ID,
	guid = function() return HttpService:GenerateGUID(false) end,
	jsonEncode = function(value) return HttpService:JSONEncode(value) end,
	getThreshold = function() return if globalSecurityPolicyService then globalSecurityPolicyService:Get("suspiciousSignalThreshold") else 8 end,
	onAlert = function(signal, count, subject)
		if globalAuditService then pcall(globalAuditService.Record, globalAuditService, "SecurityEvent", 0, signal, "threshold-reached:" .. tostring(count)) end
		local subjectUserId = tonumber(subject) or 0
		if not finiteNumber(subjectUserId) or subjectUserId < 0 or subjectUserId % 1 ~= 0 then subjectUserId = 0 end
		recordThreatIntelligence("security_monitor_threshold", subjectUserId, "SecurityMonitor", "Warning")
	end,
}, {"Start", "GetStatus", "Record", "ForgetSubject"})
if globalSecurityMonitorService then globalSecurityMonitorService:Start() end

-- Local character-physics detections feed the existing bounded SecurityMonitor.
-- This is telemetry only; it never changes enforcement or creates another storage map.
bindFunction("RecordGlobalSecuritySignal", function(signal: any, subject: any)
	if not globalSecurityMonitorService or typeof(signal) ~= "string"
		or #signal < 1 or #signal > 48 then return false end
	local safeSubject = if typeof(subject) == "string" then string.sub(subject, 1, 48) else "server"
	local subjectUserId = tonumber(safeSubject) or 0
	if not finiteNumber(subjectUserId) or subjectUserId < 0 or subjectUserId % 1 ~= 0 then subjectUserId = 0 end
	recordThreatIntelligence(signal, subjectUserId, "CharacterPhysicsGuard", "Warning")
	local ok, recorded = pcall(globalSecurityMonitorService.Record,
		globalSecurityMonitorService, signal, safeSubject)
	return ok and recorded == true
end)

globalMessageValidationService = createOperationalService("ClubMusic_Global_Message_Validation_Service", {
	getJobId = function() return JOB_ID end,
	jsonEncode = function(value) return HttpService:JSONEncode(value) end,
	getMaxBytes = function() return if globalSecurityPolicyService then globalSecurityPolicyService:Get("messageMaxBytes") else CONFIG.MaxMessageBytes end,
	getMaxAge = function() return if globalSecurityPolicyService then globalSecurityPolicyService:Get("messageMaxAgeSeconds") else 120 end,
}, {"Start", "GetStatus", "Validate"})
if globalMessageValidationService then globalMessageValidationService:Start() end

globalIdempotencyService = createOperationalService("ClubMusic_Global_Idempotency_Service", {
	isEnabled = function() return SERVICE_ENABLED end,
	memoryStoreService = MemoryStoreService,
	guid = function() return HttpService:GenerateGUID(false) end,
	getDefaultTtl = function() return if globalSecurityPolicyService then globalSecurityPolicyService:Get("idempotencyTtlSeconds") else 120 end,
}, {"Start", "GetStatus", "Reserve"})
if globalIdempotencyService then globalIdempotencyService:Start() end

globalIncidentResponseService = createOperationalService("ClubMusic_Global_Incident_Response_Service", {
	isEnabled = function() return SERVICE_ENABLED end,
	memoryStoreService = MemoryStoreService,
	authorize = authorizeGlobalActor,
	guid = function() return HttpService:GenerateGUID(false) end,
	onChange = function(action, incident)
		if globalAuditService then pcall(globalAuditService.Record, globalAuditService, "SecurityEvent", incident.actorUserId, incident.kind, "incident-" .. action) end
	end,
}, {"Start", "GetStatus", "Open", "Resolve", "GetRecent", "SubmitReport", "SubmitSystemSignal"})
if globalIncidentResponseService then globalIncidentResponseService:Start() end

local janitorModule = loadOptionalGlobalModule("ClubMusic_Global_Connection_Janitor_Service")
local lifecycleJanitor = nil
if janitorModule then
	local janitorOk,janitorResult=pcall(janitorModule.new)
	if janitorOk and typeof(janitorResult)=="table" and type(janitorResult.Add)=="function"
		and type(janitorResult.Cleanup)=="function" then
		lifecycleJanitor=janitorResult
	else
		warn("[ClubMusic][SecurityJanitor] Lifecycle cleanup unavailable: "..tostring(janitorResult))
	end
end
local function ownConnection(connection)
	if lifecycleJanitor then lifecycleJanitor:Add(connection,"Disconnect") end
	return connection
end
local function ownThread(thread)
	if lifecycleJanitor then lifecycleJanitor:Add(thread,"Cancel") end
	return thread
end
if lifecycleJanitor then
	lifecycleJanitor:Add(function()
		for _,service in pairs({
			Audit=globalAuditService,
			EventLog=globalEventLogService,
			SecurityMonitor=globalSecurityMonitorService,
			Idempotency=globalIdempotencyService,
			IncidentResponse=globalIncidentResponseService,
			Diagnostics=globalDiagnosticsService,
			ServerHealth=globalServerHealthService,
			Watchdog=globalLocalWatchdog,
		}) do
			if service and type(service.Stop)=="function" then pcall(service.Stop,service) end
		end
	end,true)
	ownConnection(script.Destroying:Connect(function()
		lifecycleJanitor:Cleanup()
	end))
end

ownConnection(globalEventBindable.Event:Connect(function(event)
	if typeof(event) ~= "table" then return end
	local kind = tostring(event.kind or "Unknown")
	if globalDiagnosticsService then pcall(globalDiagnosticsService.Record, globalDiagnosticsService, "event:" .. kind, 1) end
	if globalAuditService then
		if kind == "DJ" then
			pcall(globalAuditService.Record, globalAuditService, "AdminAction", event.actorUserId, tostring(event.command or "unknown"), tostring(event.command or "unknown"))
		elseif kind == "Catalog" and (event.senderJob == nil or event.senderJob == JOB_ID) then
			pcall(globalAuditService.Record, globalAuditService, "CatalogChange", 0, "catalog", "received")
		elseif kind == "Moderation" and event.source ~= "reconciliation"
			and (event.senderJob == nil or event.senderJob == JOB_ID) then
			pcall(globalAuditService.Record, globalAuditService, "Moderation", event.actorUserId,
				tostring(event.userId or "unknown"), tostring(event.field or "moderation") .. "=" .. tostring(event.value))
		end
	end
end))

ownConnection(Players.PlayerRemoving:Connect(function(player)
	local userId=tostring(player.UserId)
	fallbackBuckets["user:"..userId]=nil
	fallbackBuckets["state:"..userId]=nil
	fallbackBuckets["audio:"..userId]=nil
	for key in pairs(signalCounts) do
		if string.sub(key,1,#userId+1)==userId..":" then signalCounts[key]=nil end
	end
	if globalSecurityMonitorService then
		pcall(globalSecurityMonitorService.ForgetSubject,globalSecurityMonitorService,userId)
	end
end))

local function getMessagingStatus(): {[string]: any}
	local active, total = 0, 0
	for _, state in pairs(subscriptionStatus) do
		total += 1
		if state == "Active" then active += 1 end
	end
	local state = if not SERVICE_ENABLED then "Disabled"
		elseif total == 0 or active == 0 then "Starting"
		elseif active < total then "Degraded"
		else "Healthy"
	return {
		state = state,
		published = messagingPublishSuccess,
		publishFailures = messagingPublishFailures,
		received = messagingReceived,
		rejected = messagingRejected,
		activeSubscriptions = active,
		totalSubscriptions = total,
		subscriptions = table.clone(subscriptionStatus),
		lastError = messagingLastError,
	}
end

bindFunction("GetGlobalMetrics", function()
	if not globalDiagnosticsService then return false, nil end
	return true, globalDiagnosticsService:GetMetrics()
end)
bindFunction("GetGlobalAudit", function(limit: any, moderatorUserId: any)
	if not globalAuditService then return false, {} end
	return globalAuditService:GetRecent(limit, moderatorUserId)
end)
bindFunction("GetGlobalOperationalStatus", function()
	local status = {
		Messaging = getMessagingStatus(),
		Diagnostics = if globalDiagnosticsService then globalDiagnosticsService:GetStatus() else {state = "Unavailable"},
		ServerHealth = if globalServerHealthService then globalServerHealthService:GetStatus() else {state = "NotInstalled"},
		Watchdog = if globalLocalWatchdog then globalLocalWatchdog:GetStatus() else {state = "NotInstalled"},
		AdaptiveLoad = readServerStorageStatus("GetTikiTideSecurityLoadStatus"),
		SecurityReplay = readServerStorageStatus("GetTikiTideSecurityReplayStatus"),
		ThreatIntelligence = readServerStorageStatus("GetTikiTideThreatIntelligenceStatus"),
		Honeypot = readServerStorageStatus("GetTikiTideHoneypotStatus"),
		ClientIntegrityTelemetry = readServerStorageStatus("GetTikiTideClientIntegrityStatus"),
		Controller = readServerStorageStatus("GetClubMusicLocalDiagnostics"),
		CharacterPhysics = readServerStorageStatus("GetTikiTideCharacterPhysicsGuardStatus"),
		SafeCall = if globalSafeCall then globalSafeCall:GetStatus() else {state = "Unavailable"},
		ErrorHistory = if globalErrorHandler and type(globalErrorHandler.GetStatus) == "function" then globalErrorHandler.GetStatus() else {state = "Unavailable"},
		ServiceRegistry = if globalServiceRegistry then globalServiceRegistry:GetStatus() else {state = "NotInstalled"},
		Config = if globalConfigService then globalConfigService:GetStatus() else {state = "Unavailable"},
		Reconciliation = if globalStateReconciliationService then globalStateReconciliationService:GetStatus() else {state = "Unavailable"},
		Maintenance = if globalMaintenanceService then globalMaintenanceService:GetStatus() else {state = "Unavailable"},
		Metrics = if globalDiagnosticsService then globalDiagnosticsService:GetMetrics() else {state = "Unavailable"},
		Audit = if globalAuditService then globalAuditService:GetStatus() else {state = "Unavailable"},
		EventLog = if globalEventLogService then globalEventLogService:GetStatus() else {state = "Unavailable"},
		RateLimit = if globalRateLimitService then globalRateLimitService:GetStatus() else {state = "Unavailable"},
		Authorization = if globalAuthorizationService then globalAuthorizationService:GetStatus() else {state = "Unavailable"},
		SecurityMonitor = if globalSecurityMonitorService then globalSecurityMonitorService:GetStatus() else {state = "Unavailable"},
		MessageValidation = if globalMessageValidationService then globalMessageValidationService:GetStatus() else {state = "Unavailable"},
		Idempotency = if globalIdempotencyService then globalIdempotencyService:GetStatus() else {state = "Unavailable"},
		IncidentResponse = if globalIncidentResponseService then globalIncidentResponseService:GetStatus() else {state = "Unavailable"},
		SecurityPolicy = if globalSecurityPolicyService then globalSecurityPolicyService:GetStatus() else {state = "Unavailable"},
	}
	return true, status
end)
local function filterMaintenanceMessage(message: any, actorUserId: any): string?
	if typeof(message) ~= "string" or #message > CONFIG.MaxAnnouncementLength then return nil end
	-- Empty text is an intentional clear operation; non-empty text must pass
	-- broadcast filtering before it enters shared configuration or MessagingService.
	if message == "" then return "" end
	if not finiteNumber(actorUserId) or actorUserId < 1 or actorUserId % 1 ~= 0
		or actorUserId > 9007199254740991 then return nil end
	local actor = Players:GetPlayerByUserId(math.floor(actorUserId))
	if not actor or actor.Parent ~= Players or not authorizeGlobalActor(actorUserId, "GlobalConfig") then return nil end
	local filtered = filterAnnouncementText(message, math.floor(actorUserId))
	if not filtered or Players:GetPlayerByUserId(math.floor(actorUserId)) ~= actor
		or actor.Parent ~= Players or not authorizeGlobalActor(actorUserId, "GlobalConfig") then return nil end
	return filtered
end

bindFunction("GetGlobalConfig", function()
	if not globalConfigService then return false, nil end
	return true, globalConfigService:GetStatus()
end)
bindFunction("SetGlobalConfig", function(key: any, value: any, actorUserId: any)
	if not SERVICE_ENABLED or not globalConfigService or not finiteNumber(actorUserId)
		or not authorizeGlobalActor(actorUserId, "GlobalConfig") then return false end
	if key == "maintenanceMessage" then
		local filtered = filterMaintenanceMessage(value, actorUserId)
		if filtered == nil then return false, "Maintenance text could not be safely filtered." end
		value = filtered
	end
	local ok, result = globalConfigService:Set(key, value, actorUserId)
	if ok and globalAuditService then globalAuditService:Record("AdminAction", actorUserId, tostring(key), "config-update") end
	return ok, result
end)
bindFunction("SetGlobalMaintenance", function(enabled: any, message: any, actorUserId: any)
	if not SERVICE_ENABLED or not globalMaintenanceService or not finiteNumber(actorUserId)
		or not authorizeGlobalActor(actorUserId, "GlobalConfig") then return false end
	local messageToFilter = if message ~= nil then message
		elseif globalConfigService then globalConfigService:Get("maintenanceMessage") else nil
	if messageToFilter ~= nil then
		local filtered = filterMaintenanceMessage(messageToFilter, actorUserId)
		if filtered == nil then return false, "Maintenance text could not be safely filtered." end
		message = filtered
	end
	local actor = Players:GetPlayerByUserId(math.floor(actorUserId))
	if not actor or actor.Parent ~= Players or not authorizeGlobalActor(actorUserId, "GlobalConfig") then return false end
	local ok, err = globalMaintenanceService:Set(enabled, message, actorUserId)
	return ok, err
end)
bindFunction("ConsumeGlobalRateLimit", function(key: any, capacity: any, refill: any, cost: any)
	if not globalRateLimitService or typeof(key) ~= "string" or #key > 100
		or not finiteNumber(capacity) or not finiteNumber(refill) or not finiteNumber(cost) then return false, false end
	return globalRateLimitService:Consume(key, capacity, refill, cost)
end)
bindFunction("RecordLocalWatchdogPulse", function(name: any, detail: any, healthy: any, metadata: any)
	if not globalLocalWatchdog or typeof(name) ~= "string" or #name > 24
		or (detail ~= nil and typeof(detail) ~= "string")
		or (healthy ~= nil and typeof(healthy) ~= "boolean")
		or (metadata ~= nil and typeof(metadata) ~= "table") then return false end
	local recorded = globalLocalWatchdog:Pulse(name, detail, healthy, metadata)
	if recorded and healthy == false then
		recordThreatIntelligence("watchdog_degraded", 0, "Watchdog", "Warning")
	end
	return recorded
end)
bindFunction("RecordGlobalMetric", function(name: any, value: any, latencySeconds: any, outcome: any)
	if not globalDiagnosticsService or typeof(name) ~= "string" or #name > 48
		or (outcome ~= nil and outcome ~= "Success" and outcome ~= "Failure" and outcome ~= "Observed") then return false end
	return globalDiagnosticsService:Record(name, value, latencySeconds, outcome)
end)
bindFunction("RecordGlobalAuditEvent", function(kind: any, actorUserId: any, target: any, action: any)
	if not globalAuditService then return false end
	return globalAuditService:Record(kind, actorUserId, target, action)
end)
bindFunction("RecordGlobalEvent", function(kind: any, detail: any, severity: any)
	if not globalEventLogService then return false end
	return globalEventLogService:Record(kind, detail, severity)
end)
bindFunction("GetGlobalEvents", function(limit: any)
	if not globalEventLogService then return false, {} end
	return globalEventLogService:GetRecent(limit)
end)

bindFunction("GetGlobalHealth", function()
	if not globalDiagnosticsService then return false, nil end
	return true, globalDiagnosticsService:GetStatus()
end)

bindFunction("RunGlobalReconciliation", function(actorUserId: any)
	if not SERVICE_ENABLED or not globalStateReconciliationService
		or not finiteNumber(actorUserId) or not authorizeGlobalActor(actorUserId, "GlobalConfig") then
		return false, "Owner-level authorization and an enabled global service are required."
	end
	local ok, result = pcall(globalStateReconciliationService.Reconcile, globalStateReconciliationService)
	if not ok or result ~= true then
		return false, "Read-only queue reconciliation could not complete."
	end
	return true, globalStateReconciliationService:GetStatus()
end)

-- Server-only diagnostic snapshot for trusted scripts in ServerStorage.
-- This API performs no DataStore/MessagingService calls and never changes service state.
bindFunction("GetGlobalDiagnostics", function()
	if not globalDiagnosticsService then return false, nil end
	local ok, snapshot = pcall(globalDiagnosticsService.GetSnapshot, globalDiagnosticsService)
	if not ok or typeof(snapshot) ~= "table" then return false, nil end
	return true, snapshot
end)

bindFunction("ReportSignal", function(userId: any, signal: any, detail: any)
	local key = userKey(userId)
	local cleanSignal = cleanText(signal, 48)
	local cleanDetail = if detail == nil then "" else cleanText(detail, 180)
	if not key or not cleanSignal then return false end
	-- Local replay remains available even when cross-server DataStore services are disabled.
	recordSecurityReplay(cleanSignal, tonumber(key) or 0, 0, "Warning", "GlobalSecuritySignal", {})
	recordThreatIntelligence(cleanSignal, tonumber(key) or 0, "GlobalSecuritySignal", "Warning")
	if not SERVICE_ENABLED then return true end
	local reportKey = key .. ":" .. cleanSignal
	local previous = signalCounts[reportKey]
	if previous == nil then
		local keyCount = 0
		for _ in pairs(signalCounts) do keyCount += 1 end
		if keyCount >= MAX_SIGNAL_KEYS then return false end
		previous = 0
	end
	local count = previous + 1
	signalCounts[reportKey] = math.min(count, 100)
	if globalSecurityMonitorService then pcall(globalSecurityMonitorService.Record, globalSecurityMonitorService, cleanSignal, key) end
	if count == 1 then warn("[ClubMusic Global] Suspicious signal user=" .. key .. " type=" .. cleanSignal .. " detail=" .. (cleanDetail or "")) end
	return true
end)

bindFunction("AuthorizeGlobalAction", function(actorUserId: any, permission: any)
	if typeof(permission) ~= "string" then return false, "Invalid permission." end
	return authorizeGlobalActor(actorUserId, permission)
end)
bindFunction("GetGlobalSecurityStatus", function()
	return true, {
		SecurityCoreInstall = table.clone(securityCoreInstallStatus),
		Authorization = if globalAuthorizationService then globalAuthorizationService:GetStatus() else {state = "Unavailable"},
		Monitor = if globalSecurityMonitorService then globalSecurityMonitorService:GetStatus() else {state = "Unavailable"},
		MessageValidation = if globalMessageValidationService then globalMessageValidationService:GetStatus() else {state = "Unavailable"},
		Idempotency = if globalIdempotencyService then globalIdempotencyService:GetStatus() else {state = "Unavailable"},
		IncidentResponse = if globalIncidentResponseService then globalIncidentResponseService:GetStatus() else {state = "Unavailable"},
		ThreatIntelligence = readServerStorageStatus("GetTikiTideThreatIntelligenceStatus"),
		Policy = if globalSecurityPolicyService then globalSecurityPolicyService:GetAll() else nil,
	}
end)
bindFunction("GetGlobalSecurityPolicy", function()
	if not globalSecurityPolicyService then return false, nil end
	return true, globalSecurityPolicyService:GetAll()
end)
bindFunction("SetGlobalSecurityPolicy", function(key: any, value: any, actorUserId: any)
	if not globalSecurityPolicyService or typeof(key) ~= "string" then return false, "Policy service unavailable." end
	return globalSecurityPolicyService:Set(key, value, actorUserId)
end)
bindFunction("ReserveGlobalOperation", function(operationId: any, ttlSeconds: any, crossServer: any)
	if not globalIdempotencyService then return false, "Idempotency service unavailable." end
	return globalIdempotencyService:Reserve(operationId, ttlSeconds, crossServer == true)
end)
bindFunction("OpenGlobalSecurityIncident", function(kind: any, summary: any, actorUserId: any, subjectUserId: any)
	if not globalIncidentResponseService then return false, "Incident service unavailable." end
	return globalIncidentResponseService:Open(kind, summary, actorUserId, subjectUserId)
end)
bindFunction("ResolveGlobalSecurityIncident", function(id: any, actorUserId: any)
	if not globalIncidentResponseService then return false, "Incident service unavailable." end
	return globalIncidentResponseService:Resolve(id, actorUserId)
end)
bindFunction("GetGlobalSecurityIncidents", function(limit: any, moderatorUserId: any)
	if not globalIncidentResponseService then return false, {} end
	return globalIncidentResponseService:GetRecent(limit, moderatorUserId)
end)

-- These intake endpoints live only in ServerStorage/ClubMusicGlobalAPI. They are
-- for trusted server scripts; no client RemoteEvent is connected to them directly.
bindFunction("SubmitGlobalSecurityReport", function(reporterUserId: any, subjectUserId: any, summary: any)
	if not globalIncidentResponseService then return false, "Incident service unavailable." end
	return globalIncidentResponseService:SubmitReport(reporterUserId, subjectUserId, summary)
end)
bindFunction("SubmitGlobalSecuritySystemSignal", function(kind: any, summary: any, subjectUserId: any, source: any)
	if not globalIncidentResponseService then return false, "Incident service unavailable." end
	return globalIncidentResponseService:SubmitSystemSignal(kind, summary, subjectUserId, source)
end)

local function validEnvelope(data: any, topic: string): boolean
	-- Cross-server messages must never fall back to a weaker envelope check.
	-- If the dedicated validator is missing or failed to initialize, reject the
	-- message and let the existing subscription/reconciliation paths recover.
	if not globalMessageValidationService then
		messagingRejected += 1
		if globalSecurityMonitorService then
			pcall(globalSecurityMonitorService.Record, globalSecurityMonitorService, "message_validator_unavailable", topic)
		end
		return false
	end
	local ok, valid = pcall(globalMessageValidationService.Validate, globalMessageValidationService, topic, data)
	if not ok or valid ~= true then
		messagingRejected += 1
		if globalSecurityMonitorService then
			pcall(globalSecurityMonitorService.Record, globalSecurityMonitorService, "invalid_message", topic)
		end
		return false
	end
	return true
end

local seenMessages: {[string]: number} = {}
local function unseen(id: string): boolean
	local now = os.clock()
	for messageId, expiry in pairs(seenMessages) do if expiry <= now then seenMessages[messageId] = nil end end
	if seenMessages[id] then return false end
	local count = 0
	for _ in pairs(seenMessages) do count += 1 end
	if count >= 2048 then
		local oldestId = nil
		local oldestExpiry = math.huge
		for messageId, expiry in pairs(seenMessages) do
			if expiry < oldestExpiry then oldestExpiry = expiry; oldestId = messageId end
		end
		if oldestId then seenMessages[oldestId] = nil end
	end
	seenMessages[id] = now + 120
	return true
end

local function onAnnouncement(message)
	local data = message.Data
	if not validEnvelope(data, "Announcements") or data.kind ~= "Announcement" or not unseen(data.id) then return end
	local clean = cleanText(data.text, CONFIG.MaxAnnouncementLength)
	if clean then globalEventBindable:Fire({kind = "Announcement", text = clean, actorUserId = data.actorUserId}) end
end

local function onModeration(message)
	local data = message.Data
	if not validEnvelope(data, "Moderation") or data.kind ~= "Moderation" or not unseen(data.id) then return end
	if not finiteNumber(data.userId) or (data.field ~= "globalBan" and data.field ~= "requestBlocked")
		or typeof(data.value) ~= "boolean" or not finiteNumber(data.actorUserId) or data.actorUserId < 1 then return end
	globalEventBindable:Fire({kind = "Moderation", userId = data.userId, field = data.field, value = data.value,
		actorUserId = math.floor(data.actorUserId), reason = cleanText(data.reason, CONFIG.MaxModerationReasonLength),
		senderJob = data.senderJob})
end

local function onXPBoost(message)
	-- MessagingService supplies the envelope in message.Data. Do not accept a
	-- bare payload fallback, and apply the same bounded replay suppression used
	-- by the other cross-server topics before mutating local boost state.
	local data = if typeof(message) == "table" then message.Data else nil
	if not validEnvelope(data, "XPBoost") or data.kind ~= "XPBoost" or not unseen(data.id)
		or (data.multiplier ~= 1 and data.multiplier ~= 2 and data.multiplier ~= 4)
		or not finiteNumber(data.expiresAt) or data.expiresAt < 0 then return end
	local lowerExpiry = if finiteNumber(data.lowerExpiresAt) and data.lowerExpiresAt > os.time() then math.floor(data.lowerExpiresAt) else 0
	globalEventBindable:Fire({kind = "XPBoost", multiplier = data.multiplier, expiresAt = math.floor(data.expiresAt), lowerExpiresAt = lowerExpiry})
end

local function onCatalog(message)
	local data = message.Data
	if not validEnvelope(data, "Catalog") or data.kind ~= "Catalog" or not unseen(data.id) then return end
	-- Catalog invalidation remains metadata-free; the optional moderation fields
	-- carry only a validated track key and boolean decision.
	if typeof(data.trackId) == "string" and #data.trackId <= 64
		and string.match(data.trackId, "^[%w%-_]+$") and typeof(data.blocked) == "boolean" then
		globalEventBindable:Fire({kind = "TrackModeration", trackId = data.trackId, blocked = data.blocked, senderJob = data.senderJob})
	else
		globalEventBindable:Fire({kind = "Catalog", senderJob = data.senderJob, at = data.at})
	end
end

local function subscribeWithRetry(topic: string, callback: (any) -> ())
	subscriptionStatus[topic] = "Subscribing"
	ownThread(task.spawn(function()
		while SERVICE_ENABLED do
			local ok, subscriptionOrError = pcall(function()
				return MessagingService:SubscribeAsync(topic, function(message)
					messagingReceived += 1
					local callbackOk, callbackError = pcall(callback, message)
					if not callbackOk then
						messagingRejected += 1
						messagingLastError = string.sub(tostring(callbackError), 1, 240)
						warn("[ClubMusic Global] Message handler failed on topic " .. topic .. ": " .. tostring(callbackError))
					end
				end)
				end)
			if ok then
				if typeof(subscriptionOrError)=="RBXScriptConnection" then ownConnection(subscriptionOrError) end
				-- Subscription stays active after SubscribeAsync returns.
				subscriptionStatus[topic] = "Active"
				print("[ClubMusic Global] Messaging subscription active: " .. topic)
				return
			end
			subscriptionStatus[topic] = "Retrying"
			warn("[ClubMusic Global] Subscription failed for " .. topic .. "; retrying: " .. tostring(subscriptionOrError))
			task.wait(CONFIG.SubscriptionRetrySeconds)
		end
		subscriptionStatus[topic] = "Disabled"
	end))
end

if SERVICE_ENABLED then
	subscribeWithRetry(CONFIG.Topics.Announcements, onAnnouncement)
	subscribeWithRetry(CONFIG.Topics.Moderation, onModeration)
	subscribeWithRetry(CONFIG.Topics.XPBoost, onXPBoost)
	subscribeWithRetry(CONFIG.Topics.Catalog, onCatalog)
else
	if not CONFIG.Enabled then
		warn("[ClubMusic Global] Cross-server service is disabled by CONFIG.Enabled=false; local UI controller remains fully functional.")
	elseif IS_STUDIO and not CONFIG.EnableInStudio then
		warn("[ClubMusic Global] Studio isolation is active (EnableInStudio=false). Local commands work only in this server. For an intentional cross-server Studio test, set EnableInStudio=true in this script and enable Studio Access to API Services for the published experience; use a dedicated test universe.")
	else
		warn("[ClubMusic Global] Cross-server service is unavailable because its configuration did not enable it; local UI controller remains fully functional.")
	end
end

-- Reconcile online users against durable moderation records so missed MessagingService
-- deliveries do not leave a stale request-block/ban state indefinitely.
ownThread(task.spawn(function()
	while true do
		task.wait(CONFIG.ModerationReconcileSeconds)
		if SERVICE_ENABLED then
			for _, player in ipairs(Players:GetPlayers()) do
				local data = getModeration(player.UserId)
				if data.lookupFailed then
					-- Unknown is not the same as banned. Keep moderation-sensitive
					-- actions closed while the authoritative record is unavailable,
					-- but never kick a player solely because a backend read failed.
					player:SetAttribute("GlobalModerationPending", true)
				else
					if data.globalBan == true then
						player:Kick("You are globally banned from this experience.")
					else
						player:SetAttribute("GlobalModerationPending", false)
					end
					globalEventBindable:Fire({kind = "Moderation", userId = player.UserId, field = "requestBlocked", value = data.requestBlocked == true, source = "reconciliation"})
				end
				task.wait(1.1)
			end
		end
	end
end))

local function globalXPState(record: any): (number, number, number)
	if typeof(record) ~= "table" or typeof(record.boosts) ~= "table" then return 1, 0, 0 end
	local now = os.time()
	local twoExpiry = tonumber(record.boosts["2"]) or 0
	local fourExpiry = tonumber(record.boosts["4"]) or 0
	if not finiteNumber(twoExpiry) or twoExpiry < 0 then twoExpiry = 0 end
	if not finiteNumber(fourExpiry) or fourExpiry < 0 then fourExpiry = 0 end
	if fourExpiry > now then return 4, fourExpiry, if twoExpiry > now then twoExpiry else 0 end
	if twoExpiry > now then return 2, twoExpiry, 0 end
	return 1, 0, 0
end

local function publishXPState(record: any): (number, number)
	local multiplier, expiry, lowerExpiry = globalXPState(record)
	local message = {kind = "XPBoost", multiplier = multiplier, expiresAt = expiry, lowerExpiresAt = lowerExpiry}
	globalEventBindable:Fire(message)
	publishTopic(CONFIG.Topics.XPBoost, message)
	return multiplier, expiry
end

local function allowXPDataStoreOperation(): boolean
	local allowed, shared = consumeLocalBudget("all:datastore", 90, 15, 1)
	return shared and allowed
end

local function xpReceiptKey(receiptId: string): string?
	if #receiptId < 1 or #receiptId > MAX_PURCHASE_ID_LENGTH then return nil end
	return "xph_" .. ReceiptHash.KeySuffix(receiptId)
end

local function legacyXPReceiptKey(receiptId: string): string?
	if #receiptId < 1 or #receiptId > 46 or not string.match(receiptId, "^[%w%-_]+$") then return nil end
	return "xpr_" .. receiptId
end

local function readXPReceipt(receiptId: string): (boolean, any, string?)
	local key = xpReceiptKey(receiptId)
	if not key or not allowXPDataStoreOperation() then return false, nil, nil end
	local ok, value = pcall(function() return xpReceiptStore:GetAsync(key) end)
	if not ok then return false, nil, key end
	if typeof(value) == "table" then return true, value, key end
	local legacyKey = legacyXPReceiptKey(receiptId)
	if legacyKey then
		if not allowXPDataStoreOperation() then return false, nil, nil end
		local legacyOk, legacyValue = pcall(function() return xpReceiptStore:GetAsync(legacyKey) end)
		if not legacyOk then return false, nil, legacyKey end
		if typeof(legacyValue) == "table" then return true, legacyValue, legacyKey end
	end
	return true, nil, key
end

-- The active timer and pending receipt marker are committed in one UpdateAsync.
-- This single marker serializes transactions; a crash is recoverable from the per-purchase journal.
local function recoverPendingXPReceipt(record: any): (boolean, any)
	if typeof(record) ~= "table" or typeof(record.pendingReceipt) ~= "string" then return true, record end
	local pendingId = record.pendingReceipt
	local key = xpReceiptKey(pendingId)
	if not key or not allowXPDataStoreOperation() then return false, record end
	local journalOk, journal = pcall(function() return xpReceiptStore:GetAsync(key) end)
	if not journalOk then return false, record end
	if typeof(journal) ~= "table" or journal.purchaseId ~= pendingId then
		local legacyKey = legacyXPReceiptKey(pendingId)
		if not legacyKey or not allowXPDataStoreOperation() then return false, record end
		local legacyOk, legacyValue = pcall(function() return xpReceiptStore:GetAsync(legacyKey) end)
		if not legacyOk or typeof(legacyValue) ~= "table" or legacyValue.purchaseId ~= pendingId then return false, record end
		journal = legacyValue
		key = legacyKey
	end
	if typeof(journal) ~= "table" or journal.purchaseId ~= pendingId or (journal.status ~= "Prepared" and journal.status ~= "Completed") then
		warn("[ClubMusic Global] Pending XP receipt has no recoverable journal; transaction remains retryable.")
		return false, record
	end
	if not allowXPDataStoreOperation() then return false, record end
	local markOk, marked = pcall(function()
		return xpReceiptStore:UpdateAsync(key, function(old)
			if typeof(old) ~= "table" then return nil end
			local nextRecord = table.clone(old)
			nextRecord.status = "Completed"
			nextRecord.completedAt = os.time()
			return nextRecord
		end)
	end)
	if not markOk or typeof(marked) ~= "table" or marked.status ~= "Completed" then return false, record end
	if not allowXPDataStoreOperation() then return false, record end
	local clearOk, cleared = pcall(function()
		return globalControlStore:UpdateAsync(GLOBAL_XP_BOOST_KEY, function(old)
			if typeof(old) ~= "table" or old.pendingReceipt ~= pendingId then return old end
			local nextRecord = table.clone(old)
			nextRecord.pendingReceipt = nil
			return nextRecord
		end)
	end)
	if not clearOk or typeof(cleared) ~= "table" or cleared.pendingReceipt == pendingId then return false, record end
	return true, cleared
end

bindFunction("GetGlobalXPBoost", function()
	if not SERVICE_ENABLED then return nil, nil end
	local budgetAllowed, budgetShared = consumeLocalBudget("all:datastore", 90, 15, 1)
	if not budgetShared or not budgetAllowed then return nil, nil end
	local ok, record = pcall(function() return globalControlStore:GetAsync(GLOBAL_XP_BOOST_KEY) end)
	if not ok then
		warn("[ClubMusic Global] XP boost lookup failed: " .. tostring(record))
		return nil, nil
	end
	return globalXPState(record)
end)

bindFunction("ActivateGlobalXPBoost", function(multiplier: any, duration: any, receiptId: any)
	if not SERVICE_ENABLED then return false, 0, 1 end
	if (multiplier ~= 2 and multiplier ~= 4) or not finiteNumber(duration)
		or duration ~= (if multiplier == 2 then 900 else 1800)
		or typeof(receiptId) ~= "string" then return false, 0, 1 end
	local receiptKey = xpReceiptKey(receiptId)
	if not receiptKey then
		warn("[ClubMusic Global] XP PurchaseId is invalid or too long; receipt remains pending.")
		return false, 0, 1
	end
	local budgetAllowed, budgetShared = consumeLocalBudget("all:datastore", 90, 15, 1)
	if not budgetShared or not budgetAllowed then return false, 0, 1 end

	local readOk, current = pcall(function() return globalControlStore:GetAsync(GLOBAL_XP_BOOST_KEY) end)
	if not readOk then return false, 0, 1 end
	local recovered = recoverPendingXPReceipt(current)
	if not recovered then return false, 0, 1 end

	-- Backward compatibility: honor receipts already committed by the previous ledger.
	if typeof(current) == "table" and typeof(current.receipts) == "table" and current.receipts[receiptId] == true then
		local effectiveMultiplier, expiry = publishXPState(current)
		return true, expiry, effectiveMultiplier
	end

	local receiptReadOk, receiptRecord, storedReceiptKey = readXPReceipt(receiptId)
	if not receiptReadOk then return false, 0, 1 end
	if storedReceiptKey then receiptKey = storedReceiptKey end
	if typeof(receiptRecord) == "table" and (receiptRecord.purchaseId ~= receiptId
		or receiptRecord.multiplier ~= multiplier or receiptRecord.duration ~= duration) then
		warn("[ClubMusic Global] XP receipt journal identity mismatch; refusing to grant.")
		return false, 0, 1
	end
	if typeof(receiptRecord) == "table" and receiptRecord.status == "Completed" then
		if not allowXPDataStoreOperation() then return false, 0, 1 end
		local latestOk, latest = pcall(function() return globalControlStore:GetAsync(GLOBAL_XP_BOOST_KEY) end)
		if not latestOk then return false, 0, 1 end
		local effectiveMultiplier, expiry = publishXPState(latest)
		return true, expiry, effectiveMultiplier
	end

	-- One small durable record per purchase; the shared timer record no longer grows.
	if not allowXPDataStoreOperation() then return false, 0, 1 end
	local preparedOk, prepared = pcall(function()
		return xpReceiptStore:UpdateAsync(receiptKey, function(old)
			if typeof(old) == "table" then return old end
			return {status = "Prepared", purchaseId = receiptId, multiplier = multiplier,
				duration = duration, createdAt = os.time()}
		end)
	end)
	if not preparedOk or typeof(prepared) ~= "table"
		or (prepared.status ~= "Prepared" and prepared.status ~= "Completed")
		or prepared.purchaseId ~= receiptId or prepared.multiplier ~= multiplier
		or prepared.duration ~= duration then return false, 0, 1 end
	if prepared.status == "Completed" then
		if not allowXPDataStoreOperation() then return false, 0, 1 end
		local latestOk, latest = pcall(function() return globalControlStore:GetAsync(GLOBAL_XP_BOOST_KEY) end)
		if not latestOk then return false, 0, 1 end
		local effectiveMultiplier, expiry = publishXPState(latest)
		return true, expiry, effectiveMultiplier
	end

	local now = os.time()
	if not allowXPDataStoreOperation() then return false, 0, 1 end
	local applyOk, applied = pcall(function()
		return globalControlStore:UpdateAsync(GLOBAL_XP_BOOST_KEY, function(old)
			local data = if typeof(old) == "table" then table.clone(old) else {}
			if data.pendingReceipt == receiptId then return data end
			if data.pendingReceipt ~= nil then return nil end
			data.boosts = if typeof(data.boosts) == "table" then table.clone(data.boosts) else {}
			local key = tostring(multiplier)
			local oldExpiry = math.max(now, tonumber(data.boosts[key]) or 0)
			data.boosts[key] = math.min(now + MAX_GLOBAL_XP_BOOST_SECONDS, oldExpiry + duration)
			data.pendingReceipt = receiptId -- atomic with the timer extension
			data.updatedAt = now
			return data
		end)
	end)
	if not applyOk or typeof(applied) ~= "table" or applied.pendingReceipt ~= receiptId then
		warn("[ClubMusic Global] XP boost transaction is waiting for another receipt to recover.")
		return false, 0, 1
	end

	if not allowXPDataStoreOperation() then return false, 0, 1 end
	local completeOk, completed = pcall(function()
		return xpReceiptStore:UpdateAsync(receiptKey, function(old)
			if typeof(old) ~= "table" or old.purchaseId ~= receiptId then return nil end
			local nextRecord = table.clone(old)
			nextRecord.status = "Completed"
			nextRecord.completedAt = os.time()
			return nextRecord
		end)
	end)
	if not completeOk or typeof(completed) ~= "table" or completed.status ~= "Completed" then
		warn("[ClubMusic Global] XP boost applied; journal completion will recover on retry.")
		return false, 0, 1
	end

	if not allowXPDataStoreOperation() then return false, 0, 1 end
	local clearOk, cleared = pcall(function()
		return globalControlStore:UpdateAsync(GLOBAL_XP_BOOST_KEY, function(old)
			if typeof(old) ~= "table" or old.pendingReceipt ~= receiptId then return old end
			local nextRecord = table.clone(old)
			nextRecord.pendingReceipt = nil
			return nextRecord
		end)
	end)
	if not clearOk or typeof(cleared) ~= "table" or cleared.pendingReceipt == receiptId then
		warn("[ClubMusic Global] XP boost completed; marker cleanup will recover on retry.")
		return false, 0, 1
	end

	local effectiveMultiplier, expiry = publishXPState(cleared)
	return true, expiry, effectiveMultiplier
end)

print("[ClubMusic Global] Cross-server service initialized. Enabled=" .. tostring(SERVICE_ENABLED) .. " JobId=" .. JOB_ID)
