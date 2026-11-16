--!strict
-- ClubMusic_Global_Service
-- Place as a Script in ServerScriptService.
-- Cross-server coordination for the secured Club Music UI.
--
-- Uses MemoryStore for expiring shared budgets, DataStore for durable moderation,
-- and MessagingService for best-effort cross-server notifications/commands.
-- Every receiving server validates messages and applies only allowlisted commands.
-- MessagingService is not a durable queue; periodic reconciliation handles moderation state.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReceiptHash = require(ServerStorage:WaitForChild("ClubMusic_ReceiptHash"))

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
	BudgetMapName = "ClubMusic_GlobalBudgets_v1",
	-- A shared bucket limits aggregate activity across all live servers.
	GlobalActionCapacity = 900,
	GlobalActionRefillPerSecond = 300,
	GlobalPlayerCapacity = 45,
	GlobalPlayerRefillPerSecond = 12,
	GlobalAudioCapacity = 18,
	GlobalAudioRefillPerSecond = 3,
	BudgetKeyTtlSeconds = 90,
	-- Temporary local fallback is conservative if MemoryStore is unavailable.
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
local globalRateLimitService: any = nil
local globalAuthorizationService: any = nil
local globalSecurityMonitorService: any = nil
local globalMessageValidationService: any = nil
local globalIdempotencyService: any = nil
local globalIncidentResponseService: any = nil
local globalSecurityPolicyService: any = nil
local authorizeGlobalActor: (any, string) -> boolean
-- Cross-server stores are created only when cross-server operation is enabled.
-- In isolated Studio sessions, requiring this controller must not touch DataStore
-- or MemoryStore APIs (the place may be unpublished and API access unavailable).
local budgetMap: any = nil
local budgetMapInitializationError: string? = nil
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
	-- and purchase records. MemoryStore rate-limit allocation remains disabled.
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
	else
		-- MemoryStore rate-limit records are intentionally disabled to minimize
		-- universe-wide allocation. Cross-server requests use bounded local limits.
		budgetMap = nil
		budgetMapInitializationError = "MemoryStore total memory budget disabled for minimal storage mode."
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

local function cleanText(value: any, maxLength: number): string?
	if typeof(value) ~= "string" or #value == 0 or #value > maxLength then return nil end
	local clean = value:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if clean == "" then return nil end
	return clean
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

local memoryStoreCapacityLimited = false
local memoryStoreCapacityError = nil

local function isMemoryCapacityError(err: any): boolean
 local message = string.lower(tostring(err or ""))
 return string.find(message, "total memory", 1, true) ~= nil
  or string.find(message, "memory limit", 1, true) ~= nil
  or string.find(message, "memory usage", 1, true) ~= nil
end

local function consumeShared(key: string, capacity: number, refill: number, cost: number): (boolean, boolean)
 if not finiteNumber(cost) or cost <= 0 or cost > capacity then return false, false end
 -- Shared MemoryStore rate-limit allocation is intentionally disabled in
 -- minimal-storage mode. Use bounded per-server buckets directly; do not
 -- classify this deliberate configuration as a capacity failure.
 if budgetMap == nil then
  return fallbackBucket(key, math.min(capacity, CONFIG.FallbackPlayerCapacity), CONFIG.FallbackPlayerRefillPerSecond, cost), false
 end
 -- Consolidate the three per-player limiter records (user/state/audio) into
 -- one expiring MemoryStore item per player. This lowers key cardinality
 -- without merging their independent token buckets or changing their limits.
 local bucketName, playerId = string.match(key, "^(%a+):(%d+)$")
 if bucketName ~= "user" and bucketName ~= "state" and bucketName ~= "audio" then
  bucketName, playerId = nil, nil
 end
 local storageKey = if playerId then "player:" .. playerId else key
 if not memoryStoreCapacityLimited then
  local now = os.time()
  local ok, allowed = pcall(function()
   local result = budgetMap:UpdateAsync(storageKey, function(old)
    if playerId then
     local record = if typeof(old) == "table" then table.clone(old) else {}
     local buckets = if typeof(record.buckets) == "table" then table.clone(record.buckets) else {}
     for name, saved in pairs(buckets) do
      if typeof(saved) ~= "table" or not finiteNumber(saved.updated)
       or now - saved.updated > CONFIG.BudgetKeyTtlSeconds then
       buckets[name] = nil
      end
     end
     local state = if typeof(buckets[bucketName]) == "table" then buckets[bucketName] else {}
     local tokens = if finiteNumber(state.tokens) then state.tokens else capacity
     local updated = if finiteNumber(state.updated) then state.updated else now
     tokens = math.min(capacity, tokens + math.max(0, now - updated) * refill)
     local permit = tokens >= cost
     if permit then tokens -= cost end
     buckets[bucketName] = {tokens = tokens, updated = now}
     record.buckets = buckets
     record.lastUpdated = now
     record.allowed = permit
     return record
    end
    local state = if typeof(old) == "table" then old else {}
    local tokens = if finiteNumber(state.tokens) then state.tokens else capacity
    local updated = if finiteNumber(state.updated) then state.updated else now
    tokens = math.min(capacity, tokens + math.max(0, now - updated) * refill)
    local permit = tokens >= cost
    if permit then tokens -= cost end
    return {tokens = tokens, updated = now, allowed = permit}
   end, CONFIG.BudgetKeyTtlSeconds)
   return typeof(result) == "table" and result.allowed == true
  end)
  if ok then return allowed == true, true end
  if isMemoryCapacityError(allowed) then
   -- Stop issuing more MemoryStore writes while the allocation is full.
   -- The per-server fallback remains bounded and does not bypass authorization.
   memoryStoreCapacityLimited = true
   memoryStoreCapacityError = string.sub(tostring(allowed), 1, 300)
   warn("[ClubMusic Global] MemoryStore total memory limit reached; shared rate limiting is temporarily using bounded per-server fallback.")
  else
   warn("[ClubMusic Global] MemoryStore budget unavailable; using local fallback: " .. tostring(allowed))
  end
 end
 return fallbackBucket(key, math.min(capacity, CONFIG.FallbackPlayerCapacity), CONFIG.FallbackPlayerRefillPerSecond, cost), false
end

local function userKey(userId: number): string?
	if not finiteNumber(userId) or userId < 1 or userId % 1 ~= 0 then return nil end
	return tostring(math.floor(userId))
end

local function getModeration(userId: number): {[string]: any}
	local key = userKey(userId)
	if not key then return {} end
	-- Bound durable reads across all servers. If the shared limiter itself is
	-- unavailable, report a lookup failure so callers can fail closed.
	local budgetAllowed, budgetShared = consumeShared("all:datastore", 90, 15, 1)
	-- consumeShared already applies a conservative per-server fallback when
	-- MemoryStore is unavailable. Only an exhausted limiter should block the
	-- durable read; a MemoryStore outage alone must not manufacture an unknown
	-- moderation result when DataStore is still reachable.
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
	local budgetAllowed, budgetShared = consumeShared("all:datastore", 90, 15, 1)
	if not budgetShared or not budgetAllowed then
		warn("[ClubMusic Global] Moderation update rejected: shared DataStore budget unavailable.")
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
	local message = {
		version = 1, senderJob = JOB_ID, id = HttpService:GenerateGUID(false),
		kind = "Moderation", userId = userId, field = field, value = value,
		actorUserId = actorUserId, reason = reason, at = os.time(),
	}
	local published = publishTopic(CONFIG.Topics.Moderation, message)
	if not published then warn("[ClubMusic Global] Moderation publish failed; periodic reconciliation remains active.") end
	if globalAuditService then
		pcall(globalAuditService.Record, globalAuditService, "Moderation", actorUserId,
			tostring(userId), field .. "=" .. tostring(value) .. (if reason then " | " .. reason else ""))
	end
	globalEventBindable:Fire({kind = "Moderation", userId = userId, field = field, value = value, reason = reason})
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
		elseif payload.kind == "Catalog" then
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
		globalOk, globalShared = consumeShared("all:actions", CONFIG.GlobalActionCapacity, CONFIG.GlobalActionRefillPerSecond, if finiteNumber(cost) then cost else 1)
	end
	if not globalShared or not globalOk then return false end
	local playerOk, playerShared
	if globalRateLimitService then
		playerOk, playerShared = globalRateLimitService:Consume("user:" .. key, CONFIG.GlobalPlayerCapacity, CONFIG.GlobalPlayerRefillPerSecond, if finiteNumber(cost) then cost else 1)
	else
		playerOk, playerShared = consumeShared("user:" .. key, CONFIG.GlobalPlayerCapacity, CONFIG.GlobalPlayerRefillPerSecond, if finiteNumber(cost) then cost else 1)
	end
	-- Global action enforcement must not silently degrade to independent server buckets.
	return playerShared and playerOk
end)

bindFunction("ConsumeStateBudget", function(userId: any)
	if not SERVICE_ENABLED then return true end
	local key = userKey(userId)
	if not key then return false end
	local globalOk, globalShared = consumeShared("all:state", 300, 100, 1)
	if not globalShared or not globalOk then return false end
	local playerOk, playerShared = consumeShared("state:" .. key, 12, 2, 1)
	return playerShared and playerOk
end)

bindFunction("ConsumeDataStoreBudget", function()
	if not SERVICE_ENABLED then return true end
	local allowed, shared = consumeShared("all:datastore", 90, 15, 1)
	-- Avoid a cross-server DataStore thundering herd when MemoryStore is unavailable.
	return shared and allowed
end)

bindFunction("ConsumeAudioBudget", function(userId: any)
	if not SERVICE_ENABLED then return true end
	local key = userKey(userId)
	if not key then return false end
	local globalOk, globalShared = consumeShared("all:audio", CONFIG.GlobalAudioCapacity, CONFIG.GlobalAudioRefillPerSecond, 1)
	if not globalShared or not globalOk then return false end
	local playerOk, playerShared = consumeShared("audio:" .. key, 3, 0.2, 1)
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
	local allowed, shared = consumeShared("all:datastore", 90, 15, 1)
	if not shared or not allowed then return false, false end
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
	local allowed, shared = consumeShared("all:datastore", 90, 15, 1)
	if not shared or not allowed then return false end
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
	local clean = cleanText(message, CONFIG.MaxAnnouncementLength)
	if not SERVICE_ENABLED or not clean or not finiteNumber(actorUserId) or not authorizeGlobalActor(actorUserId, "GlobalAnnouncement") then return false end
	return publishTopic(CONFIG.Topics.Announcements, {kind = "Announcement", text = clean, actorUserId = math.floor(actorUserId)})
end)


local function allowGlobalDataStoreOperation(): boolean
	-- Shared DataStore operations retain a conservative per-server budget
	-- when the optional cross-server MemoryStore budget is unavailable.
	local allowed = consumeShared("all:datastore", 90, 15, 1)
	return allowed == true
end

bindFunction("PublishCatalogChange", function()
	if not SERVICE_ENABLED then return false end
	return publishTopic(CONFIG.Topics.Catalog, {kind = "Catalog"})
end)

bindFunction("IsEnabled", function()
	-- Reports availability of global moderation/configuration services only.
	-- Queue/playback modes are permanently local and no longer gate this check.
	return SERVICE_ENABLED
end)

-- Diagnostics expose the local-only playback architecture without maintaining
-- cross-server playback state or peer heartbeats.
local function getGlobalSyncStatus(): {[string]: any}
	return {
		state = "LocalOnly",
		detail = "Each server owns its own playback and request queue.",
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
	ClubMusic_Global_Incident_Response_Service = "IncidentResponse",
}
local cachedSecurityBundle: any = nil
local securityBundleLoadAttempted = false

local function loadOptionalGlobalModule(moduleName: string): any?
	-- Security implementations are bundled into one ModuleScript while each
	-- exported service retains its original constructor and public method contract.
	local securityExport = SECURITY_MODULE_EXPORTS[moduleName]
	if securityExport then
		if not securityBundleLoadAttempted then
			securityBundleLoadAttempted = true
			local bundleModule = ServerStorage:FindFirstChild("ClubMusic_Global_Security_Service")
				or ServerStorage:FindFirstChild("ClubMusic_Global_Security_Service", true)
			if bundleModule and bundleModule:IsA("ModuleScript") then
				local bundleOk, bundle = pcall(require, bundleModule)
				if bundleOk and typeof(bundle) == "table" then
					cachedSecurityBundle = bundle
				else
					warn("[ClubMusic Global] Consolidated security bundle failed to load: " .. tostring(bundle))
				end
			else
				warn("[ClubMusic Global] Consolidated security ModuleScript is missing under ServerStorage.")
			end
		end
		local exported = if cachedSecurityBundle then cachedSecurityBundle[securityExport] else nil
		if typeof(exported) ~= "table" or type(exported.new) ~= "function" then
			warn("[ClubMusic Global] Consolidated security export is unavailable: " .. moduleName)
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
		return safeCallModule.new({serviceName = "ClubMusicGlobal"})
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
		sharedRateLimitsEnabled = budgetMap ~= nil and not memoryStoreCapacityLimited,
		capacityLimited = memoryStoreCapacityLimited,
		lastCapacityError = memoryStoreCapacityError,
		mode = if budgetMap == nil then "LocalOnly" else (if memoryStoreCapacityLimited then "LocalFallback" else "Shared")
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

local diagnosticsModule = loadOptionalGlobalModule("ClubMusic_Global_Diagnostics_Service")
if diagnosticsModule then
	local createOk, instance = pcall(function()
		return diagnosticsModule.new({
			isEnabled = function() return SERVICE_ENABLED end,
			apiFolder = apiFolder,
				getSyncStatus = getGlobalSyncStatus,
			getRecentErrors = function()
				if globalErrorHandler and type(globalErrorHandler.GetRecentErrors) == "function" then return globalErrorHandler.GetRecentErrors() end
				return nil
			end,
			getMemoryStoreStatus = function() return {capacityLimited = memoryStoreCapacityLimited, lastCapacityError = memoryStoreCapacityError} end,
			getSecurityMonitorStatus = function() return if globalSecurityMonitorService then globalSecurityMonitorService:GetStatus() else nil end,
			getMessageValidationStatus = function() return if globalMessageValidationService then globalMessageValidationService:GetStatus() else nil end,
			getIdempotencyStatus = function() return if globalIdempotencyService then globalIdempotencyService:GetStatus() else nil end,
		})
	end)
	if createOk and instance and type(instance.Start) == "function"
		and type(instance.GetStatus) == "function" and type(instance.GetSnapshot) == "function" then
		globalDiagnosticsService = instance
		task.delay(4, function()
			if globalDiagnosticsService == instance then
				local startOk, startError = pcall(function() instance:Start() end)
				if not startOk then warn("[ClubMusic Diagnostics] Delayed startup failed: " .. tostring(startError)) end
			end
		end)
	else
		warn("[ClubMusic Global] Could not initialize lightweight Diagnostics Service: " .. tostring(instance))
	end
end

-- Operational services are optional modules and fail independently. They manage
-- shared configuration, moderation, security, and bounded diagnostics only.
local function createOperationalService(moduleName: string, dependencies: {[string]: any}, requiredMethods: {string}): any?
	-- These optional modules are cross-server infrastructure, not local playback
	-- dependencies. Do not construct them in isolated Studio sessions.
	if not SERVICE_ENABLED then return nil end
	local module = loadOptionalGlobalModule(moduleName)
	if not module then return nil end
	local ok, instance = pcall(function() return module.new(dependencies) end)
	if not ok or typeof(instance) ~= "table" then
		warn("[ClubMusic Global] Could not create " .. moduleName .. ": " .. tostring(instance))
		return nil
	end
	for _, methodName in ipairs(requiredMethods) do
		if type(instance[methodName]) ~= "function" then
			warn("[ClubMusic Global] " .. moduleName .. " is missing method " .. methodName)
			return nil
		end
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

globalRateLimitService = createOperationalService("ClubMusic_Global_RateLimit_Service", {
	isEnabled = function() return SERVICE_ENABLED end,
	consumeShared = consumeShared,
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

-- Security services remain independent; authorization denies by default until a trusted resolver exists.
local globalAuthorizationServiceResolver = function(actorUserId: any, permission: any): boolean
	local resolver = ServerStorage:FindFirstChild("ClubMusicAuthorizationResolver")
	if not resolver or not resolver:IsA("BindableFunction") or resolver.Parent ~= ServerStorage then
		warn("[ClubMusic][Authorization] Resolver dependency could not find the expected ServerStorage BindableFunction.")
		return false
	end
	local ok, allowed = pcall(function() return resolver:Invoke(actorUserId, permission) end)
	if not ok then
		warn("[ClubMusic][Authorization] Resolver Invoke failed; actor=" .. tostring(actorUserId)
			.. "; permission=" .. tostring(permission) .. "; error=" .. string.sub(tostring(allowed), 1, 180))
		return false
	end
	print("[ClubMusic][Authorization] Resolver returned; actor=" .. tostring(actorUserId)
		.. "; permission=" .. tostring(permission) .. "; allowed=" .. tostring(allowed))
	return allowed == true
end

-- Authorization is local security infrastructure, not a cross-server feature.
-- Load the separately installed ModuleScript even when SERVICE_ENABLED is false
-- (including isolated Studio sessions).
local authorizationModule = loadOptionalGlobalModule("ClubMusic_Global_Authorization_Service")
if authorizationModule then
	local createOk, instance = pcall(function()
		return authorizationModule.new({
			isResolverAvailable = function()
				local resolver = ServerStorage:FindFirstChild("ClubMusicAuthorizationResolver")
				local available = resolver ~= nil and resolver:IsA("BindableFunction")
					and resolver.Parent == ServerStorage
				print("[ClubMusic][Authorization] Resolver availability checked; available="
					.. tostring(available) .. "; class=" .. tostring(if resolver then resolver.ClassName else "missing"))
				return available
			end,
			resolvePermission = globalAuthorizationServiceResolver,
		})
	end)
	if createOk and typeof(instance) == "table"
		and type(instance.Start) == "function"
		and type(instance.GetStatus) == "function"
		and type(instance.Check) == "function" then
		globalAuthorizationService = instance
	else
		warn("[ClubMusic][Authorization] Separate authorization ModuleScript could not be constructed: "
			.. tostring(instance))
	end
else
	warn("[ClubMusic][Authorization] Separate authorization ModuleScript was not found under ServerStorage.")
end
if not globalAuthorizationService then
	-- Keep a strict built-in fallback if the separately installed module is absent
	-- or malformed. The trusted controller resolver remains mandatory.
	local allowedPermissions = {
		GlobalDJ = true,
		GlobalModeration = true,
		GlobalAnnouncement = true,
		GlobalConfig = true,
		SecurityPolicy = true,
		IncidentResponse = true,
	}
	globalAuthorizationService = {
		checks = 0,
		denied = 0,
		Start = function(self)
			return true
		end,
		Check = function(self, actorUserId, permission)
			if not finiteNumber(actorUserId) or actorUserId < 1 or actorUserId % 1 ~= 0
				or not allowedPermissions[permission] then
				self.denied += 1
				return false, "Invalid actor or permission."
			end
			local ok, allowed = pcall(function()
				return globalAuthorizationServiceResolver(actorUserId, permission)
			end)
			self.checks += 1
			if not ok or allowed ~= true then
				self.denied += 1
				return false, "Permission denied."
			end
			return true
		end,
		GetStatus = function(self)
			return {state = "Fallback", checks = self.checks, denied = self.denied, default = "Deny"}
		end,
	}
	warn("[ClubMusic][Authorization] Using built-in fail-closed authorization adapter.")
end
local authStartOk, authStartResult = pcall(globalAuthorizationService.Start, globalAuthorizationService)
print("[ClubMusic][Authorization] Authorization service loaded; startOk=" .. tostring(authStartOk)
	.. "; startResult=" .. tostring(authStartResult))
authorizeGlobalActor = function(actorUserId: any, permission: string): boolean
	print("[ClubMusic][Authorization] Authorization check requested; actor=" .. tostring(actorUserId)
		.. "; permission=" .. tostring(permission) .. "; servicePresent=" .. tostring(globalAuthorizationService ~= nil))
	if not globalAuthorizationService then
		warn("[ClubMusic][Authorization] Authorization check denied because the service instance is missing.")
		return false
	end
	-- Use a statement rather than a conditional expression here: the authorization
	-- adapter and SafeCall both return multiple values, and a Luau if-expression
	-- can collapse those returns, leaving allowed=nil even when Check returned true.
	local ok, allowed
	if globalSafeCall then
		ok, allowed = globalSafeCall:Run("GlobalAuthorization", "Check",
			globalAuthorizationService.Check, globalAuthorizationService, actorUserId, permission)
	else
		ok, allowed = pcall(globalAuthorizationService.Check,
			globalAuthorizationService, actorUserId, permission)
	end
	if not ok then
		warn("[ClubMusic][Authorization] Authorization Check threw an error: " .. string.sub(tostring(allowed), 1, 180))
		return false
	end
	print("[ClubMusic][Authorization] Authorization Check returned; allowed=" .. tostring(allowed))
	return allowed == true
end

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
	getThreshold = function() return if globalSecurityPolicyService then globalSecurityPolicyService:Get("suspiciousSignalThreshold") else 8 end,
	onAlert = function(signal, count)
		if globalAuditService then pcall(globalAuditService.Record, globalAuditService, "SecurityEvent", 0, signal, "threshold-reached:" .. tostring(count)) end
	end,
}, {"Start", "GetStatus", "Record"})
if globalSecurityMonitorService then globalSecurityMonitorService:Start() end

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
}, {"Start", "GetStatus", "Open", "Resolve", "GetRecent"})
if globalIncidentResponseService then globalIncidentResponseService:Start() end

globalEventBindable.Event:Connect(function(event)
	if typeof(event) ~= "table" then return end
	local kind = tostring(event.kind or "Unknown")
	if globalDiagnosticsService then pcall(globalDiagnosticsService.Record, globalDiagnosticsService, "event:" .. kind, 1) end
	if globalAuditService then
		if kind == "DJ" then
			pcall(globalAuditService.Record, globalAuditService, "AdminAction", event.actorUserId, tostring(event.command or "unknown"), tostring(event.command or "unknown"))
		elseif kind == "Catalog" then
			pcall(globalAuditService.Record, globalAuditService, "CatalogChange", 0, "catalog", "received")
		elseif kind == "Moderation" then
			pcall(globalAuditService.Record, globalAuditService, "SecurityEvent", event.actorUserId, tostring(event.field or "moderation"), tostring(event.field or "moderation"))
		end
	end
end)

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
bindFunction("GetGlobalAudit", function(limit: any)
	if not globalAuditService then return false, {} end
	return globalAuditService:GetRecent(limit)
end)
bindFunction("GetGlobalOperationalStatus", function()
	local status = {
		Messaging = getMessagingStatus(),
		Diagnostics = if globalDiagnosticsService then globalDiagnosticsService:GetStatus() else {state = "Unavailable"},
		Config = if globalConfigService then globalConfigService:GetStatus() else {state = "Unavailable"},
		Reconciliation = if globalStateReconciliationService then globalStateReconciliationService:GetStatus() else {state = "Unavailable"},
		Maintenance = if globalMaintenanceService then globalMaintenanceService:GetStatus() else {state = "Unavailable"},
		Metrics = if globalDiagnosticsService then globalDiagnosticsService:GetMetrics() else {state = "Unavailable"},
		Audit = if globalAuditService then globalAuditService:GetStatus() else {state = "Unavailable"},
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
bindFunction("GetGlobalConfig", function()
	if not globalConfigService then return false, nil end
	return true, globalConfigService:GetStatus()
end)
bindFunction("SetGlobalConfig", function(key: any, value: any, actorUserId: any)
	if not SERVICE_ENABLED or not globalConfigService or not finiteNumber(actorUserId) or not authorizeGlobalActor(actorUserId, "GlobalConfig") then return false end
	local ok, result = globalConfigService:Set(key, value, actorUserId)
	if ok and globalAuditService then globalAuditService:Record("AdminAction", actorUserId, tostring(key), "config-update") end
	return ok, result
end)
bindFunction("SetGlobalMaintenance", function(enabled: any, message: any, actorUserId: any)
	if not SERVICE_ENABLED or not globalMaintenanceService or typeof(actorUserId) ~= "number" or not authorizeGlobalActor(actorUserId, "GlobalConfig") then return false end
	local ok, err = globalMaintenanceService:Set(enabled, message, actorUserId)
	return ok, err
end)
bindFunction("ConsumeGlobalRateLimit", function(key: any, capacity: any, refill: any, cost: any)
	if not globalRateLimitService or typeof(key) ~= "string" or #key > 100
		or not finiteNumber(capacity) or not finiteNumber(refill) or not finiteNumber(cost) then return false, false end
	return globalRateLimitService:Consume(key, capacity, refill, cost)
end)
bindFunction("RecordGlobalMetric", function(name: any, value: any, latencySeconds: any)
	if not globalDiagnosticsService or typeof(name) ~= "string" or #name > 48 then return false end
	return globalDiagnosticsService:Record(name, value, latencySeconds)
end)
bindFunction("RecordGlobalAuditEvent", function(kind: any, actorUserId: any, target: any, action: any)
	if not globalAuditService then return false end
	return globalAuditService:Record(kind, actorUserId, target, action)
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
	if not SERVICE_ENABLED then return true end
	local key = userKey(userId)
	local cleanSignal = cleanText(signal, 48)
	local cleanDetail = if detail == nil then "" else cleanText(detail, 180)
	if not key or not cleanSignal then return false end
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
		Authorization = if globalAuthorizationService then globalAuthorizationService:GetStatus() else {state = "Unavailable"},
		Monitor = if globalSecurityMonitorService then globalSecurityMonitorService:GetStatus() else {state = "Unavailable"},
		MessageValidation = if globalMessageValidationService then globalMessageValidationService:GetStatus() else {state = "Unavailable"},
		Idempotency = if globalIdempotencyService then globalIdempotencyService:GetStatus() else {state = "Unavailable"},
		IncidentResponse = if globalIncidentResponseService then globalIncidentResponseService:GetStatus() else {state = "Unavailable"},
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
bindFunction("ReserveGlobalOperation", function(operationId: any, ttlSeconds: any)
	if not globalIdempotencyService then return false, "Idempotency service unavailable." end
	return globalIdempotencyService:Reserve(operationId, ttlSeconds)
end)
bindFunction("OpenGlobalSecurityIncident", function(kind: any, summary: any, actorUserId: any)
	if not globalIncidentResponseService then return false, "Incident service unavailable." end
	return globalIncidentResponseService:Open(kind, summary, actorUserId)
end)
bindFunction("ResolveGlobalSecurityIncident", function(id: any, actorUserId: any)
	if not globalIncidentResponseService then return false, "Incident service unavailable." end
	return globalIncidentResponseService:Resolve(id, actorUserId)
end)
bindFunction("GetGlobalSecurityIncidents", function(limit: any)
	if not globalIncidentResponseService then return false, {} end
	return globalIncidentResponseService:GetRecent(limit)
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
		or typeof(data.value) ~= "boolean" then return end
	globalEventBindable:Fire({kind = "Moderation", userId = data.userId, field = data.field, value = data.value, reason = cleanText(data.reason, CONFIG.MaxModerationReasonLength)})
end

local function onXPBoost(message)
	local data = if typeof(message) == "table" and typeof(message.Data) == "table" then message.Data else message
	if not validEnvelope(data, "XPBoost") or data.kind ~= "XPBoost"
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
	task.spawn(function()
		while SERVICE_ENABLED do
			local ok, err = pcall(function()
				MessagingService:SubscribeAsync(topic, function(message)
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
				-- Subscription stays active after SubscribeAsync returns.
				subscriptionStatus[topic] = "Active"
				print("[ClubMusic Global] Messaging subscription active: " .. topic)
				return
			end
			subscriptionStatus[topic] = "Retrying"
			warn("[ClubMusic Global] Subscription failed for " .. topic .. "; retrying: " .. tostring(err))
			task.wait(CONFIG.SubscriptionRetrySeconds)
		end
		subscriptionStatus[topic] = "Disabled"
	end)
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
task.spawn(function()
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
					globalEventBindable:Fire({kind = "Moderation", userId = player.UserId, field = "requestBlocked", value = data.requestBlocked == true})
				end
				task.wait(1.1)
			end
		end
	end
end)

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
	local allowed, shared = consumeShared("all:datastore", 90, 15, 1)
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
		warn("[ClubMusic Global] Pending XP receipt has no recoverable journal: " .. pendingId)
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
	local budgetAllowed, budgetShared = consumeShared("all:datastore", 90, 15, 1)
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
	local budgetAllowed, budgetShared = consumeShared("all:datastore", 90, 15, 1)
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
