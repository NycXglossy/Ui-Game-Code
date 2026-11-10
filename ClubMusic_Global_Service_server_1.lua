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

local queueModule = ServerStorage:WaitForChild("MusicGlobalQueueService", 20)
if not queueModule or not queueModule:IsA("ModuleScript") then
	error("[ClubMusic Global] Missing ServerStorage.MusicGlobalQueueService ModuleScript.")
end
local queueRequireOk, queueRequireResult = pcall(require, queueModule)
if not queueRequireOk then
	error("[ClubMusic Global] MusicGlobalQueueService failed to load: " .. tostring(queueRequireResult))
end
local MusicGlobalQueueService = queueRequireResult

local CONFIG = {
	Enabled = true,
	-- Keep Studio isolated by default. Set true only for intentional cross-server Studio tests.
	EnableInStudio = false,

	Topics = {
		Announcements = "ClubMusic_Global_Announcements_v1",
		Moderation = "ClubMusic_Global_Moderation_v1",
		DJ = "ClubMusic_Global_DJ_v1",
		XPBoost = "ClubMusic_Global_XPBoost_v1",
		Catalog = "ClubMusic_Global_Catalog_v1",
		Queue = "ClubMusic_Global_Queue_v1",
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
local globalRegistryService: any = nil
local globalEventLogService: any = nil
local globalWatchdogService: any = nil
local globalConfigService: any = nil
local globalStateReconciliationService: any = nil
local globalMaintenanceService: any = nil
local globalMetricsService: any = nil
local globalAuditService: any = nil
local globalRateLimitService: any = nil
local globalAuthorizationService: any = nil
local globalSecurityMonitorService: any = nil
local globalMessageValidationService: any = nil
local globalIdempotencyService: any = nil
local globalIncidentResponseService: any = nil
local globalSecurityPolicyService: any = nil
local authorizeGlobalActor: (any, string) -> boolean
local budgetMap = MemoryStoreService:GetHashMap(CONFIG.BudgetMapName)
local moderationStore = DataStoreService:GetDataStore(CONFIG.ModerationStoreName)
local globalControlStore = DataStoreService:GetDataStore(CONFIG.GlobalControlStoreName)
local GLOBAL_XP_BOOST_KEY = "globalXPBoost_v1" -- Preserve existing active timers.
local XP_RECEIPT_STORE_NAME = "ClubMusic_XPBoostReceipts_v1"
local MAX_GLOBAL_XP_BOOST_SECONDS = 30 * 24 * 60 * 60
local xpReceiptStore = DataStoreService:GetDataStore(XP_RECEIPT_STORE_NAME)
local MAX_PURCHASE_ID_LENGTH = 128

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

local function consumeShared(key: string, capacity: number, refill: number, cost: number): (boolean, boolean)
	if not finiteNumber(cost) or cost <= 0 or cost > capacity then return false, false end
	local now = os.time()
	local ok, allowed = pcall(function()
		local result = budgetMap:UpdateAsync(key, function(old)
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
	-- MemoryStore outage: degrade to a conservative per-server limiter, not a hard outage.
	warn("[ClubMusic Global] MemoryStore budget unavailable; using local fallback: " .. tostring(allowed))
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
	if not budgetShared or not budgetAllowed then
		return {lookupFailed = true}
	end
	local ok, data = pcall(function() return moderationStore:GetAsync(key) end)
	if not ok then
		warn("[ClubMusic Global] Moderation lookup failed for " .. key .. ": " .. tostring(data))
		return {lookupFailed = true}
	end
	return if typeof(data) == "table" then data else {}
end

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
	local publishOk, publishErr = pcall(function() MessagingService:PublishAsync(CONFIG.Topics.Moderation, message) end)
	if not publishOk then warn("[ClubMusic Global] Moderation publish failed; periodic reconciliation remains active: " .. tostring(publishErr)) end
	globalEventBindable:Fire({kind = "Moderation", userId = userId, field = field, value = value, reason = reason})
	return true
end

local function publishTopic(topic: string, payload: {[string]: any}): boolean
	if not SERVICE_ENABLED then return false end
	payload.version = 1
	payload.senderJob = JOB_ID
	payload.id = HttpService:GenerateGUID(false)
	payload.at = os.time()
	local ok, err = pcall(function() MessagingService:PublishAsync(topic, payload) end)
	if not ok then warn("[ClubMusic Global] Publish failed: " .. tostring(err)); return false end
	if globalMetricsService then pcall(globalMetricsService.Record, globalMetricsService, "publish:" .. tostring(payload.kind or "unknown"), 1) end
	if globalAuditService then
		if payload.kind == "DJ" then
			pcall(globalAuditService.Record, globalAuditService, "AdminAction", payload.actorUserId, tostring(payload.command), tostring(payload.command))
		elseif payload.kind == "Catalog" then
			pcall(globalAuditService.Record, globalAuditService, "CatalogChange", 0, "catalog", "invalidate")
		elseif payload.kind == "QueueChanged" then
			pcall(globalAuditService.Record, globalAuditService, "GlobalQueueChange", 0, "global-queue", "changed")
		end
	end
	return true
end

local allowedDJCommands = {Skip = true, ClearQueue = true, SetRequestLock = true, SetPlaybackPaused = true, Restart = true}
local function publishDJCommand(command: any, payload: any, actorUserId: any): (boolean, number?)
	if not SERVICE_ENABLED or not allowedDJCommands[command] or not finiteNumber(actorUserId) then return false end
	local permission = if command == "ClearQueue" then "GlobalModeration" else "GlobalDJ"
	if not authorizeGlobalActor(actorUserId, permission) then return false end
	if typeof(payload) ~= "table" then payload = {} end
	local cleanPayload = {}
	if command == "SetRequestLock" then
		if typeof(payload.locked) ~= "boolean" then return false end
		cleanPayload.locked = payload.locked
		-- Persist request-lock state only for SetRequestLock. Previously this
		-- block was accidentally nested under SetPlaybackPaused, where it read
		-- a nil payload.locked and prevented pause/resume publication.
		local budgetAllowed, budgetShared = consumeShared("all:datastore", 90, 15, 1)
		if not budgetShared or not budgetAllowed then
			warn("[ClubMusic Global] Global request lock change rejected: shared DataStore budget unavailable.")
			return false
		end
		local stored, storeResult = pcall(function()
			return globalControlStore:UpdateAsync("requestLock", function(old)
				local state = if typeof(old) == "table" then table.clone(old) else {}
				state.locked = cleanPayload.locked
				state.updatedAt = os.time()
				state.updatedBy = math.floor(actorUserId)
				return state
			end)
		end)
		if not stored or typeof(storeResult) ~= "table" or storeResult.locked ~= cleanPayload.locked then
			warn("[ClubMusic Global] Could not persist global request lock: " .. tostring(storeResult))
			return false
		end
	elseif command == "SetPlaybackPaused" then
		if typeof(payload.paused) ~= "boolean" then return false end
		cleanPayload.paused = payload.paused
	elseif command == "Restart" then
		cleanPayload.restart = true
	end
	if command == "SetPlaybackPaused" or command == "Restart" then
		local budgetAllowed, budgetShared = consumeShared("all:datastore", 90, 15, 1)
		if not budgetShared or not budgetAllowed then
			warn("[ClubMusic Global] Playback control rejected: shared DataStore budget unavailable.")
			return false
		end
		local stored, storeResult = pcall(function()
			return globalControlStore:UpdateAsync("playbackControl", function(old)
				local state = if typeof(old) == "table" then table.clone(old) else {}
				local revision = if finiteNumber(state.revision) and state.revision >= 0 then math.floor(state.revision) else 0
				state.revision = revision + 1
				state.command = command
				state.paused = if command == "SetPlaybackPaused" then cleanPayload.paused else (state.paused == true)
				if command == "SetPlaybackPaused" then
					state.pauseRevision = state.revision
				else
					state.restartRevision = state.revision
				end
				state.updatedAt = os.time()
				state.updatedBy = math.floor(actorUserId)
				return state
			end)
		end)
		if not stored or typeof(storeResult) ~= "table" or not finiteNumber(storeResult.revision) then
			warn("[ClubMusic Global] Could not persist global playback control: " .. tostring(storeResult))
			return false
		end
		cleanPayload.revision = math.floor(storeResult.revision)
	end
	local published = publishTopic(CONFIG.Topics.DJ, {
		kind = "DJ", command = command, payload = cleanPayload,
		actorUserId = math.floor(actorUserId),
	})
	-- Pause/resume and restart are durable; polling repairs missed MessagingService events.
	if command == "SetRequestLock" then return true end
	if command == "SetPlaybackPaused" or command == "Restart" then return true, cleanPayload.revision end
	return published
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

bindFunction("SetRequestBlocked", function(userId: any, blocked: any, actorUserId: any)
	if not SERVICE_ENABLED or typeof(blocked) ~= "boolean" or not finiteNumber(actorUserId) or not authorizeGlobalActor(actorUserId, "GlobalModeration") then return false end
	return updateModeration(userId, "requestBlocked", blocked, actorUserId, nil)
end)

bindFunction("PublishAnnouncement", function(message: any, actorUserId: any)
	local clean = cleanText(message, CONFIG.MaxAnnouncementLength)
	if not SERVICE_ENABLED or not clean or not finiteNumber(actorUserId) or not authorizeGlobalActor(actorUserId, "GlobalAnnouncement") then return false end
	return publishTopic(CONFIG.Topics.Announcements, {kind = "Announcement", text = clean, actorUserId = math.floor(actorUserId)})
end)

bindFunction("PublishDJCommand", publishDJCommand)

local function allowGlobalQueueStoreOperation(): boolean
	local allowed, shared = consumeShared("all:datastore", 90, 15, 1)
	return shared and allowed
end

-- Global queue API: every mutation is atomic in the shared DataStore.
-- Controller callers still perform role, moderation, catalog, and request-limit checks.
bindFunction("GetGlobalQueueState", function()
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	return MusicGlobalQueueService:GetSnapshot()
end)

bindFunction("EnqueueGlobalQueueEntry", function(entry: any, playerQueueCap: any, catalogRevision: any)
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:Enqueue(entry, playerQueueCap, catalogRevision)
	if ok then publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision}) end
	return ok, state, message
end)

bindFunction("EnqueueGlobalQueueBatch", function(entries: any, maxQueueSize: any, targetQueueSize: any, catalogRevision: any)
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:EnqueueBatch(entries, maxQueueSize, targetQueueSize, catalogRevision)
	if ok then publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision}) end
	return ok, state, message
end)

bindFunction("RemoveGlobalQueueEntry", function(entryId: any)
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:Remove(entryId)
	if ok then publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision}) end
	return ok, state, message
end)

bindFunction("SetGlobalPlaylistRotation", function(playlistId: any, playlistName: any, trackIds: any)
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:SetPlaylistRotation(playlistId, playlistName, trackIds)
	if ok then publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision}) end
	return ok, state, message
end)

bindFunction("MoveUpGlobalQueueEntry", function(entryId: any)
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:MoveUp(entryId)
	if ok then publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision}) end
	return ok, state, message
end)

bindFunction("PurgeGlobalUserQueueEntries", function(userId: any)
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:RemoveUserEntries(userId)
	if ok then publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision}) end
	return ok, state, message
end)

bindFunction("ClearGlobalQueue", function()
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:Clear()
	if ok then publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision}) end
	return ok, state, message
end)

bindFunction("AdvanceGlobalQueue", function(expectedTrackRevision: any, fallbackEntry: any, catalogRevision: any)
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:Advance(expectedTrackRevision, fallbackEntry, catalogRevision)
	if ok then publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision}) end
	return ok, state, message
end)

bindFunction("ReserveCatalogRemoval", function(trackId: any, catalogRevision: any)
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:ReserveCatalogRemoval(trackId, catalogRevision)
	if ok then publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision}) end
	return ok, state, message
end)

bindFunction("CompleteCatalogRemoval", function(trackId: any)
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:CompleteCatalogRemoval(trackId)
	if ok then
		publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision})
		publishTopic(CONFIG.Topics.Catalog, {kind = "Catalog"})
	end
	return ok, state, message
end)

bindFunction("ReserveCatalogAddition", function(trackId: any, catalogRevision: any)
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:ReserveCatalogAddition(trackId, catalogRevision)
	if ok then publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision}) end
	return ok, state, message
end)

bindFunction("CompleteCatalogAddition", function(trackId: any)
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:CompleteCatalogAddition(trackId)
	if ok then
		publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision})
		publishTopic(CONFIG.Topics.Catalog, {kind = "Catalog"})
	end
	return ok, state, message
end)

bindFunction("AdvanceCatalogRevision", function()
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:AdvanceCatalogRevision()
	if ok then
		publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision})
		publishTopic(CONFIG.Topics.Catalog, {kind = "Catalog"})
	end
	return ok, state, message
end)

bindFunction("SetGlobalPlayback", function(paused: any, position: any, expectedTrackRevision: any, restart: any)
	if not SERVICE_ENABLED then return false, nil, "Global queue service is disabled." end
	if not allowGlobalQueueStoreOperation() then return false, nil, "Global queue storage budget is unavailable." end
	local ok, state, message = MusicGlobalQueueService:SetPlayback(paused, position, expectedTrackRevision, restart)
	if ok then publishTopic(CONFIG.Topics.Queue, {kind = "QueueChanged", revision = state.revision}) end
	return ok, state, message
end)

bindFunction("GetGlobalPlaybackPosition", function(snapshot: any)
	return MusicGlobalQueueService:GetPosition(snapshot)
end)

bindFunction("PublishCatalogChange", function()
	if not SERVICE_ENABLED then return false end
	return publishTopic(CONFIG.Topics.Catalog, {kind = "Catalog"})
end)

bindFunction("GetGlobalPlaybackControl", function()
	if not SERVICE_ENABLED then return nil, false end
	local allowed, shared = consumeShared("all:datastore", 90, 15, 1)
	if not shared or not allowed then return nil, false end
	local ok, state = pcall(function() return globalControlStore:GetAsync("playbackControl") end)
	if not ok then return nil, false end
	if typeof(state) == "table" and finiteNumber(state.revision)
		and (state.command == "SetPlaybackPaused" or state.command == "Restart")
		and typeof(state.paused) == "boolean" then
		return {revision = math.floor(state.revision), command = state.command, paused = state.paused}, true
	end
	return nil, true
end)

bindFunction("GetGlobalRequestLock", function()
	if not SERVICE_ENABLED then return nil, false end
	local budgetAllowed, budgetShared = consumeShared("all:datastore", 90, 15, 1)
	if not budgetShared or not budgetAllowed then return nil, false end
	local ok, state = pcall(function() return globalControlStore:GetAsync("requestLock") end)
	if not ok then return nil, false end
	if typeof(state) == "table" and typeof(state.locked) == "boolean" then return state.locked, true end
	-- No persisted lock means the experience is unlocked by default.
	return false, true
end)

bindFunction("IsEnabled", function()
	return SERVICE_ENABLED
end)

-- Optional operational services. They observe the existing global queue and
-- never create a second playback controller or mutate queue ownership.
local globalRecoveryService: any = nil
local globalHealthService: any = nil

-- Cross-server sync is verified with peer heartbeats, not inferred from DataStore access.
local SYNC_HEARTBEAT_INTERVAL_SECONDS = 60
local SYNC_HEARTBEAT_TIMEOUT_SECONDS = 180
local syncHeartbeatTopic = CONFIG.Topics.Queue
local subscriptionStatus: {[string]: string} = {[syncHeartbeatTopic] = "Starting"}
local peerHeartbeats: {[string]: {seenAt: number, reportedAt: number}} = {}
local hasSeenSyncPeer = false
local lastQueueNotificationAt = 0
local queueNotificationsReceived = 0
local lastHeartbeatPublishAt = 0

local function getGlobalSyncStatus(): {[string]: any}
    local now = os.clock()
    local peerCount = 0
    local newestPeerAt = 0
    for jobId, heartbeat in pairs(peerHeartbeats) do
        if now - heartbeat.seenAt > SYNC_HEARTBEAT_TIMEOUT_SECONDS then
            peerHeartbeats[jobId] = nil
        else
            peerCount += 1
            newestPeerAt = math.max(newestPeerAt, heartbeat.reportedAt)
        end
    end

    local subscription = subscriptionStatus[syncHeartbeatTopic] or "Starting"
    local state = "Unverified"
    local detail = "No other server heartbeat has been observed yet; cross-server sync is unverified."
    if not SERVICE_ENABLED then
        state = "Disabled"
        detail = "Cross-server messaging is disabled in this server (Studio isolation or configuration)."
    elseif subscription ~= "Active" then
        state = if subscription == "Starting" then "Starting" else "Degraded"
        detail = "Cross-server sync heartbeat subscription is " .. subscription .. "."
    elseif lastHeartbeatPublishAt == 0 then
        state = "Starting"
        detail = "The first cross-server sync heartbeat has not been published yet."
    elseif now - lastHeartbeatPublishAt > SYNC_HEARTBEAT_TIMEOUT_SECONDS then
        state = "Degraded"
        detail = "This server has not successfully published a sync heartbeat within "
            .. tostring(SYNC_HEARTBEAT_TIMEOUT_SECONDS) .. " seconds."
    elseif peerCount > 0 then
        state = "Healthy"
        detail = "Cross-server messaging is receiving heartbeats from " .. tostring(peerCount) .. " peer server(s)."
    elseif hasSeenSyncPeer then
        state = "Degraded"
        detail = "Previously observed peer servers stopped sending sync heartbeats for more than "
            .. tostring(SYNC_HEARTBEAT_TIMEOUT_SECONDS) .. " seconds."
    end

    return {
        state = state,
        detail = detail,
        subscription = subscription,
        peerCount = peerCount,
        lastPeerHeartbeatAt = newestPeerAt,
        lastHeartbeatPublishedAt = if lastHeartbeatPublishAt > 0 then os.time() - math.floor(now - lastHeartbeatPublishAt) else 0,
        lastQueueNotificationAt = if lastQueueNotificationAt > 0 then os.time() - math.floor(now - lastQueueNotificationAt) else 0,
        queueNotificationsReceived = queueNotificationsReceived,
        heartbeatIntervalSeconds = SYNC_HEARTBEAT_INTERVAL_SECONDS,
        heartbeatTimeoutSeconds = SYNC_HEARTBEAT_TIMEOUT_SECONDS,
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
	if globalMetricsService then
		pcall(globalMetricsService.Record, globalMetricsService, "error:" .. string.sub(metricName, 1, 42), 1)
		if string.find(metricName, "playback", 1, true) or string.find(metricName, "audio", 1, true) then
			pcall(globalMetricsService.Record, globalMetricsService, "playbackFailure", 1)
		end
	end
	if globalEventLogService then
		pcall(globalEventLogService.Record, globalEventLogService, "OperationalError", tostring(subsystem) .. "." .. tostring(operation), "Error")
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

local function loadOptionalGlobalModule(moduleName: string): any?
	local module = ServerStorage:FindFirstChild(moduleName)
	if not module or not module:IsA("ModuleScript") then
		warn("[ClubMusic Global] Optional service module is missing: ServerStorage." .. moduleName)
		return nil
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

local recoveryModule = loadOptionalGlobalModule("ClubMusic_Global_Recovery_Service")
if recoveryModule then
	local createOk, instance = pcall(function()
		return recoveryModule.new({
			isEnabled = function() return SERVICE_ENABLED end,
			allowStoreOperation = allowGlobalQueueStoreOperation,
			invalidateSnapshot = function()
				if typeof(MusicGlobalQueueService.InvalidateSnapshot) == "function" then
					MusicGlobalQueueService:InvalidateSnapshot()
				end
			end,
			getSnapshot = function()
				return MusicGlobalQueueService:GetSnapshot()
			end,
			initialRetrySeconds = 30,
			maxRetrySeconds = 180,
			reportError = reportOperationalError,
		})
	end)
	if createOk and instance and type(instance.Start) == "function" and type(instance.GetStatus) == "function" then
		globalRecoveryService = instance
		globalRecoveryService:Start()
	else
		warn("[ClubMusic Global] Could not initialize Global Recovery Service: " .. tostring(instance))
	end
end

local healthModule = loadOptionalGlobalModule("ClubMusic_Global_Health_Service")
if healthModule and globalRecoveryService then
	local createOk, instance = pcall(function()
		return healthModule.new({
			isEnabled = function() return SERVICE_ENABLED end,
			getRecoveryStatus = function() return globalRecoveryService:GetStatus() end,
			getSyncStatus = getGlobalSyncStatus,
			apiFolder = apiFolder,
			queueModule = queueModule,
			intervalSeconds = 30,
			reportError = reportOperationalError,
		})
	end)
	if createOk and instance and type(instance.Start) == "function" and type(instance.GetStatus) == "function" then
		globalHealthService = instance
		globalHealthService:Start()
	else
		warn("[ClubMusic Global] Could not initialize Global Health Service: " .. tostring(instance))
	end
end

-- Operational services are optional modules and fail independently. They observe or
-- coordinate shared state; none of them owns playback or the global queue controller.
local function createOperationalService(moduleName: string, dependencies: {[string]: any}, requiredMethods: {string}): any?
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
	isEnabled = function() return SERVICE_ENABLED end,
	memoryStoreService = MemoryStoreService,
	dataStore = DataStoreService:GetDataStore("ClubMusic_GlobalConfig_v1"),
	allowStoreOperation = allowGlobalQueueStoreOperation,
	jobId = JOB_ID,
	guid = function() return HttpService:GenerateGUID(false) end,
}
globalConfigService = createOperationalService("ClubMusic_Global_Config_Service", sharedDependencies, {"Start", "GetStatus", "Get", "Set"})
if globalConfigService then globalConfigService:Start() end

globalRegistryService = createOperationalService("ClubMusic_Global_Server_Registry", {
	isEnabled = function() return SERVICE_ENABLED end,
	memoryStoreService = MemoryStoreService,
	jobId = JOB_ID,
	getHealth = function()
		return if globalHealthService then globalHealthService:GetStatus().localState else "Unknown"
	end,
}, {"Start", "GetStatus", "GetServers"})
if globalRegistryService then globalRegistryService:Start() end

local auditDependencies = table.clone(sharedDependencies)
auditDependencies.isEnabled = function()
	return SERVICE_ENABLED and globalConfigService ~= nil and globalConfigService:Get("auditEnabled") == true
end
local metricsDependencies = table.clone(sharedDependencies)
metricsDependencies.isEnabled = function()
	return SERVICE_ENABLED and globalConfigService ~= nil and globalConfigService:Get("metricsEnabled") == true
end

globalEventLogService = createOperationalService("ClubMusic_Global_Event_Log_Service", auditDependencies, {"Start", "GetStatus", "Record", "GetRecent"})
if globalEventLogService then globalEventLogService:Start() end

globalMetricsService = createOperationalService("ClubMusic_Global_Metrics_Service", metricsDependencies, {"Start", "GetStatus", "GetAggregate", "Record", "ObserveLatency"})
if globalMetricsService then globalMetricsService:Start() end

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
		if globalEventLogService then globalEventLogService:Record("Maintenance", "Maintenance state changed", "Warning") end
		if globalAuditService then globalAuditService:Record("Maintenance", 0, "global", if payload.enabled then "enabled" else "disabled") end
	end,
}, {"Start", "GetStatus", "Set"}) else nil
if globalMaintenanceService then globalMaintenanceService:Start() end

globalStateReconciliationService = createOperationalService("ClubMusic_Global_State_Reconciliation_Service", {
	isEnabled = function() return SERVICE_ENABLED end,
	getSnapshot = function() return MusicGlobalQueueService:GetSnapshot() end,
}, {"Start", "GetStatus", "Reconcile"})
if globalStateReconciliationService then globalStateReconciliationService:Start() end

globalWatchdogService = createOperationalService("ClubMusic_Global_Watchdog_Service", {
	isEnabled = function() return SERVICE_ENABLED end,
	getChecks = function()
		local health = if globalHealthService then globalHealthService:GetStatus() else nil
		local recovery = if globalRecoveryService then globalRecoveryService:GetStatus() else nil
		return {
			LocalHealth = health ~= nil and health.localState == "Healthy",
			QueueModule = queueModule.Parent == ServerStorage and queueModule:IsA("ModuleScript"),
			Recovery = recovery ~= nil and (recovery.state == "Healthy" or recovery.state == "Disabled"),
			Registry = globalRegistryService ~= nil and globalRegistryService:GetStatus().state == "Healthy",
		}
	end,
	reportError = reportOperationalError,
}, {"Start", "GetStatus", "Check"})
if globalWatchdogService then globalWatchdogService:Start() end

-- Security services remain independent; authorization denies by default until a trusted resolver exists.
globalAuthorizationService = createOperationalService("ClubMusic_Global_Authorization_Service", {
	isResolverAvailable = function()
		local resolver = ServerStorage:FindFirstChild("ClubMusicAuthorizationResolver")
		return resolver ~= nil and resolver:IsA("BindableFunction") and resolver.Parent == ServerStorage
	end,
	resolvePermission = function(actorUserId, permission)
		local resolver = ServerStorage:FindFirstChild("ClubMusicAuthorizationResolver")
		if not resolver or not resolver:IsA("BindableFunction") or resolver.Parent ~= ServerStorage then return false end
		local ok, allowed = pcall(function() return resolver:Invoke(actorUserId, permission) end)
		return ok and allowed == true
	end,
}, {"Start", "GetStatus", "Check"})
if globalAuthorizationService then globalAuthorizationService:Start() end
authorizeGlobalActor = function(actorUserId: any, permission: string): boolean
	if not globalAuthorizationService then return false end
	local ok, allowed = pcall(globalAuthorizationService.Check, globalAuthorizationService, actorUserId, permission)
	return ok and allowed == true
end

globalSecurityPolicyService = createOperationalService("ClubMusic_Global_Security_Policy_Service", {
	configService = globalConfigService,
	authorize = authorizeGlobalActor,
	onChange = function(key, value, revision, actor)
		if globalAuditService then pcall(globalAuditService.Record, globalAuditService, "SecurityEvent", actor, key, "policy-update") end
		if globalEventLogService then pcall(globalEventLogService.Record, globalEventLogService, "SecurityPolicyChanged", key, "Info") end
	end,
}, {"Start", "GetStatus", "Get", "GetAll", "Set"})
if globalSecurityPolicyService then globalSecurityPolicyService:Start() end

globalSecurityMonitorService = createOperationalService("ClubMusic_Global_Security_Monitor_Service", {
	isEnabled = function() return SERVICE_ENABLED and globalSecurityPolicyService ~= nil and globalSecurityPolicyService:Get("monitoringEnabled") == true end,
	getThreshold = function() return if globalSecurityPolicyService then globalSecurityPolicyService:Get("suspiciousSignalThreshold") else 8 end,
	onAlert = function(signal, count)
		if globalAuditService then pcall(globalAuditService.Record, globalAuditService, "SecurityEvent", 0, signal, "threshold-reached:" .. tostring(count)) end
		if globalEventLogService then pcall(globalEventLogService.Record, globalEventLogService, "SecuritySignal", signal, "Warning") end
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
		if globalEventLogService then pcall(globalEventLogService.Record, globalEventLogService, "SecurityIncident", incident.kind .. ":" .. incident.id, action) end
	end,
}, {"Start", "GetStatus", "Open", "Resolve", "GetRecent"})
if globalIncidentResponseService then globalIncidentResponseService:Start() end

globalEventBindable.Event:Connect(function(event)
	if typeof(event) ~= "table" then return end
	local kind = tostring(event.kind or "Unknown")
	if globalEventLogService then pcall(globalEventLogService.Record, globalEventLogService, kind, "Global event received", "Info") end
	if globalMetricsService then pcall(globalMetricsService.Record, globalMetricsService, "event:" .. kind, 1) end
	if globalAuditService then
		if kind == "DJ" then
			pcall(globalAuditService.Record, globalAuditService, "AdminAction", event.actorUserId, tostring(event.command or "unknown"), tostring(event.command or "unknown"))
		elseif kind == "Catalog" then
			pcall(globalAuditService.Record, globalAuditService, "CatalogChange", 0, "catalog", "received")
		elseif kind == "QueueChanged" then
			pcall(globalAuditService.Record, globalAuditService, "GlobalQueueChange", 0, "global-queue", "received")
		elseif kind == "Moderation" then
			pcall(globalAuditService.Record, globalAuditService, "SecurityEvent", event.actorUserId, tostring(event.field or "moderation"), tostring(event.field or "moderation"))
		end
	end
end)

bindFunction("GetGlobalServers", function(limit: any)
	if not globalRegistryService then return false, {}, "Registry unavailable." end
	return globalRegistryService:GetServers(limit)
end)
bindFunction("GetGlobalMetrics", function()
	if not globalMetricsService then return false, nil end
	local aggregateOk, aggregate, aggregateError = globalMetricsService:GetAggregate()
	local status = globalMetricsService:GetStatus()
	status.aggregate = aggregate
	return aggregateOk, status, aggregateError
end)
bindFunction("GetGlobalAudit", function(limit: any)
	if not globalAuditService then return false, {} end
	return globalAuditService:GetRecent(limit)
end)
bindFunction("GetGlobalEventLog", function(limit: any)
	if not globalEventLogService then return false, {} end
	return globalEventLogService:GetRecent(limit)
end)
bindFunction("GetGlobalOperationalStatus", function()
	local status = {
		Registry = if globalRegistryService then globalRegistryService:GetStatus() else {state = "Unavailable"},
		EventLog = if globalEventLogService then globalEventLogService:GetStatus() else {state = "Unavailable"},
		Watchdog = if globalWatchdogService then globalWatchdogService:GetStatus() else {state = "Unavailable"},
		Config = if globalConfigService then globalConfigService:GetStatus() else {state = "Unavailable"},
		Reconciliation = if globalStateReconciliationService then globalStateReconciliationService:GetStatus() else {state = "Unavailable"},
		Maintenance = if globalMaintenanceService then globalMaintenanceService:GetStatus() else {state = "Unavailable"},
		Metrics = if globalMetricsService then globalMetricsService:GetStatus() else {state = "Unavailable"},
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
	if not globalMetricsService or typeof(name) ~= "string" or #name > 48 then return false end
	globalMetricsService:Record(name, value)
	if finiteNumber(latencySeconds) then globalMetricsService:ObserveLatency(name, latencySeconds) end
	return true
end)
bindFunction("RecordGlobalAuditEvent", function(kind: any, actorUserId: any, target: any, action: any)
	if not globalAuditService then return false end
	return globalAuditService:Record(kind, actorUserId, target, action)
end)

bindFunction("GetGlobalHealth", function()
	if not globalHealthService then return false, nil end
	return true, globalHealthService:GetStatus()
end)

-- Server-only diagnostic snapshot for trusted scripts in ServerStorage.
-- This API performs no DataStore/MessagingService calls and never changes service state.
bindFunction("GetGlobalDiagnostics", function()
	local healthOk, health = pcall(function()
		return if globalHealthService then globalHealthService:GetStatus() else nil
	end)
	local recoveryOk, recovery = pcall(function()
		return if globalRecoveryService then globalRecoveryService:GetStatus() else nil
	end)
	local errors = {}
	local errorsAvailable = false
	if globalErrorHandler and type(globalErrorHandler.GetRecentErrors) == "function" then
		local errorsOk, result = pcall(globalErrorHandler.GetRecentErrors)
		if errorsOk and typeof(result) == "table" then
			errorsAvailable = true
			local firstIndex = math.max(1, #result - 19)
			for index = firstIndex, #result do
				local record = result[index]
				if typeof(record) == "table" then
					table.insert(errors, table.clone(record))
				end
			end
		end
	end
	return true, {
		generatedAt = os.time(),
		serviceEnabled = SERVICE_ENABLED,
		healthAvailable = healthOk and health ~= nil,
		health = if healthOk then health else nil,
		recoveryAvailable = recoveryOk and recovery ~= nil,
		recovery = if recoveryOk then recovery else nil,
		syncStatus = getGlobalSyncStatus(),
		errorHistoryAvailable = errorsAvailable,
		recentErrors = errors,
		operationalServices = {
			registry = if globalRegistryService then globalRegistryService:GetStatus() else nil,
			metrics = if globalMetricsService then globalMetricsService:GetStatus() else nil,
			watchdog = if globalWatchdogService then globalWatchdogService:GetStatus() else nil,
			securityMonitor = if globalSecurityMonitorService then globalSecurityMonitorService:GetStatus() else nil,
			messageValidation = if globalMessageValidationService then globalMessageValidationService:GetStatus() else nil,
			idempotency = if globalIdempotencyService then globalIdempotencyService:GetStatus() else nil,
		},
	}
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
	local valid, reason = false, "Message validation service unavailable."
	if globalMessageValidationService then
		valid, reason = globalMessageValidationService:Validate(topic, data)
	else
		valid = typeof(data) == "table" and data.version == 1 and data.senderJob ~= JOB_ID
			and typeof(data.id) == "string" and #data.id > 0 and #data.id <= 64
			and finiteNumber(data.at) and math.abs(os.time() - data.at) <= 120
	end
	if not valid and globalSecurityMonitorService then
		pcall(globalSecurityMonitorService.Record, globalSecurityMonitorService, "invalid_message", topic)
	end
	return valid
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

local function onDJ(message)
	local data = message.Data
	if not validEnvelope(data, "DJ") or data.kind ~= "DJ" or not unseen(data.id) then return end
	if not allowedDJCommands[data.command] or not finiteNumber(data.actorUserId) then return end
	local payload = if typeof(data.payload) == "table" then data.payload else {}
	if data.command == "SetRequestLock" and typeof(payload.locked) ~= "boolean" then return end
	if data.command == "SetPlaybackPaused" and (typeof(payload.paused) ~= "boolean" or not finiteNumber(payload.revision)) then return end
	if data.command == "Restart" and not finiteNumber(payload.revision) then return end
	globalEventBindable:Fire({kind = "DJ", command = data.command, payload = payload, actorUserId = data.actorUserId, senderJob = data.senderJob})
end

local function onCatalog(message)
	local data = message.Data
	if not validEnvelope(data, "Catalog") or data.kind ~= "Catalog" or not unseen(data.id) then return end
	-- The message carries invalidation only, never track metadata or executable commands.
	globalEventBindable:Fire({kind = "Catalog", senderJob = data.senderJob, at = data.at})
end

local function onQueueChanged(message)
	local data = if typeof(message) == "table" then message.Data else nil
	if not validEnvelope(data, "Queue") then return end
	if data.kind == "ServerHeartbeat" then
		if typeof(data.serverJob) ~= "string" or #data.serverJob < 1 or #data.serverJob > 64
			or data.serverJob ~= data.senderJob or data.serverJob == JOB_ID then return end
		peerHeartbeats[data.serverJob] = {seenAt = os.clock(), reportedAt = math.floor(data.at)}
		hasSeenSyncPeer = true
		return
	end
	if data.kind ~= "QueueChanged" or not finiteNumber(data.revision) then return end
	if not unseen(data.id) then return end
	-- The originating controller already applies the state returned by its
	-- successful mutation. Ignore our own echo to avoid a redundant DataStore read.
	if data.senderJob == JOB_ID then return end
	lastQueueNotificationAt = os.clock()
	queueNotificationsReceived += 1
	-- MessagingService is an invalidation signal: discard this server's short-lived
	-- snapshot cache before the controller asks for the authoritative queue state.
	if typeof(MusicGlobalQueueService.InvalidateSnapshot) == "function" then
		MusicGlobalQueueService:InvalidateSnapshot()
	end
	globalEventBindable:Fire({kind = "QueueChanged", revision = math.floor(data.revision), senderJob = data.senderJob})
end

local function subscribeWithRetry(topic: string, callback: (any) -> ())
	subscriptionStatus[topic] = "Subscribing"
	task.spawn(function()
		while SERVICE_ENABLED do
			local ok, err = pcall(function() MessagingService:SubscribeAsync(topic, callback) end)
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
	subscribeWithRetry(CONFIG.Topics.DJ, onDJ)
	subscribeWithRetry(CONFIG.Topics.XPBoost, onXPBoost)
	subscribeWithRetry(CONFIG.Topics.Catalog, onCatalog)
	subscribeWithRetry(CONFIG.Topics.Queue, onQueueChanged)
	task.spawn(function()
		while SERVICE_ENABLED do
			local published = publishTopic(CONFIG.Topics.Queue, {kind = "ServerHeartbeat", serverJob = JOB_ID})
			if published then lastHeartbeatPublishAt = os.clock() end
			task.wait(SYNC_HEARTBEAT_INTERVAL_SECONDS)
		end
	end)
else
	if not CONFIG.Enabled then
		warn("[ClubMusic Global] Cross-server service is disabled by CONFIG.Enabled=false; local UI controller remains fully functional.")
	elseif IS_STUDIO and not CONFIG.EnableInStudio then
		warn("[ClubMusic Global] Studio isolation is active (EnableInStudio=false). Local commands work only in this server. For an intentional cross-server Studio test, set EnableInStudio=true in this script and enable Studio Access to API Services for the published experience; use a dedicated test universe.")
	else
		warn("[ClubMusic Global] Cross-server service is unavailable because its configuration did not enable it; local UI controller remains fully functional.")
	end
end

-- Reconcile both the latest pause state and the latest restart independently.
-- Emit in revision order so an older pause cannot override a newer restart (or vice versa).
task.spawn(function()
	while true do
		if SERVICE_ENABLED then
			local allowed, shared = consumeShared("all:datastore", 90, 15, 1)
			if allowed and shared then
				local ok, state = pcall(function() return globalControlStore:GetAsync("playbackControl") end)
				if ok and typeof(state) == "table" and finiteNumber(state.revision) then
					local events = {}
					if finiteNumber(state.restartRevision) and state.restartRevision > 0 then
						table.insert(events, {revision = math.floor(state.restartRevision), command = "Restart"})
					end
					if finiteNumber(state.pauseRevision) and state.pauseRevision > 0 and typeof(state.paused) == "boolean" then
						table.insert(events, {revision = math.floor(state.pauseRevision), command = "SetPlaybackPaused", paused = state.paused})
					end
					table.sort(events, function(a, b) return a.revision < b.revision end)
					for _, event in ipairs(events) do
						globalEventBindable:Fire({
							kind = "DJ", command = event.command,
							payload = {revision = event.revision, paused = event.paused},
							actorUserId = if finiteNumber(state.updatedBy) then state.updatedBy else 0,
						})
					end
				elseif not ok then
					warn("[ClubMusic Global] Playback-control reconciliation read failed: " .. tostring(state))
				end
			end
		end
		task.wait(60 + math.random(0, 15))
	end
end)

-- Reconcile online users against durable moderation records so missed MessagingService
-- deliveries do not leave a stale request-block/ban state indefinitely.
task.spawn(function()
	while true do
		task.wait(CONFIG.ModerationReconcileSeconds)
		if SERVICE_ENABLED then
			local lockBudgetAllowed, lockBudgetShared = consumeShared("all:datastore", 90, 15, 1)
			local lockOk, lockState = false, nil
			if lockBudgetShared and lockBudgetAllowed then
				lockOk, lockState = pcall(function() return globalControlStore:GetAsync("requestLock") end)
			end
			if lockOk and typeof(lockState) == "table" and typeof(lockState.locked) == "boolean" then
				globalEventBindable:Fire({kind = "DJ", command = "SetRequestLock", payload = {locked = lockState.locked}, actorUserId = 0})
			elseif not lockOk then
				globalEventBindable:Fire({kind = "DJ", command = "SetRequestLock", payload = {locked = true}, actorUserId = 0})
			else
				globalEventBindable:Fire({kind = "DJ", command = "SetRequestLock", payload = {locked = false}, actorUserId = 0})
			end
			for _, player in ipairs(Players:GetPlayers()) do
				local data = getModeration(player.UserId)
				if data.lookupFailed then
					player:Kick("Global moderation is temporarily unavailable. Please rejoin shortly.")
				else
					if data.globalBan == true then player:Kick("You are globally banned from this experience.") end
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
