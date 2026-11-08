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

local CONFIG = {
	Enabled = true,
	-- Keep Studio isolated by default. Set true only for intentional cross-server Studio tests.
	EnableInStudio = false,

	Topics = {
		Announcements = "ClubMusic_Global_Announcements_v1",
		Moderation = "ClubMusic_Global_Moderation_v1",
		DJ = "ClubMusic_Global_DJ_v1",
		XPBoost = "ClubMusic_Global_XPBoost_v1",
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

local SERVICE_ENABLED = CONFIG.Enabled and (not RunService:IsStudio() or CONFIG.EnableInStudio)
local JOB_ID = game.JobId ~= "" and game.JobId or HttpService:GenerateGUID(false)
local budgetMap = MemoryStoreService:GetHashMap(CONFIG.BudgetMapName)
local moderationStore = DataStoreService:GetDataStore(CONFIG.ModerationStoreName)
local globalControlStore = DataStoreService:GetDataStore(CONFIG.GlobalControlStoreName)
local GLOBAL_XP_BOOST_KEY = "globalXPBoost_v1" -- Preserve existing active timers.
local XP_RECEIPT_STORE_NAME = "ClubMusic_XPBoostReceipts_v1"
local MAX_GLOBAL_XP_BOOST_SECONDS = 30 * 24 * 60 * 60
local xpReceiptStore = DataStoreService:GetDataStore(XP_RECEIPT_STORE_NAME)
local MAX_PURCHASE_ID_LENGTH = 46 -- "xpr_" + PurchaseId must fit the 50-character key limit.

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
	return true
end

local allowedDJCommands = {Skip = true, ClearQueue = true, SetRequestLock = true}
local function publishDJCommand(command: any, payload: any, actorUserId: any): boolean
	if not SERVICE_ENABLED or not allowedDJCommands[command] or not finiteNumber(actorUserId) then return false end
	if typeof(payload) ~= "table" then payload = {} end
	local cleanPayload = {}
	if command == "SetRequestLock" then
		if typeof(payload.locked) ~= "boolean" then return false end
		cleanPayload.locked = payload.locked
		local budgetAllowed, budgetShared = consumeShared("all:datastore", 90, 15, 1)
		if not budgetShared or not budgetAllowed then
			warn("[ClubMusic Global] Global request lock change rejected: shared DataStore budget unavailable.")
			return false
		end
		local stored, storeResult = pcall(function()
			return globalControlStore:UpdateAsync("requestLock", function(old)
				local state = if typeof(old) == "table" then table.clone(old) else {}
				state.locked = payload.locked
				state.updatedAt = os.time()
				state.updatedBy = math.floor(actorUserId)
				return state
			end)
		end)
		if not stored or typeof(storeResult) ~= "table" or storeResult.locked ~= payload.locked then
			warn("[ClubMusic Global] Could not persist global request lock: " .. tostring(storeResult))
			return false
		end
	end
	local published = publishTopic(CONFIG.Topics.DJ, {
		kind = "DJ", command = command, payload = cleanPayload,
		actorUserId = math.floor(actorUserId),
	})
	-- SetRequestLock is durable; a missed notification is recovered by polling.
	-- Return success after persistence even if MessagingService is unavailable.
	if command == "SetRequestLock" then return true end
	return published
end

bindFunction("ConsumeActionBudget", function(userId: any, action: any, cost: any)
	if not SERVICE_ENABLED then return true end
	local key = userKey(userId)
	if not key or typeof(action) ~= "string" or #action > 40 then return false end
	local globalOk, globalShared = consumeShared("all:actions", CONFIG.GlobalActionCapacity, CONFIG.GlobalActionRefillPerSecond, if finiteNumber(cost) then cost else 1)
	if not globalShared or not globalOk then return false end
	local playerOk, playerShared = consumeShared("user:" .. key, CONFIG.GlobalPlayerCapacity, CONFIG.GlobalPlayerRefillPerSecond, if finiteNumber(cost) then cost else 1)
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
	if not SERVICE_ENABLED or typeof(banned) ~= "boolean" or not finiteNumber(actorUserId) then return false end
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
	if not SERVICE_ENABLED or typeof(blocked) ~= "boolean" or not finiteNumber(actorUserId) then return false end
	return updateModeration(userId, "requestBlocked", blocked, actorUserId, nil)
end)

bindFunction("PublishAnnouncement", function(message: any, actorUserId: any)
	local clean = cleanText(message, CONFIG.MaxAnnouncementLength)
	if not SERVICE_ENABLED or not clean or not finiteNumber(actorUserId) then return false end
	return publishTopic(CONFIG.Topics.Announcements, {kind = "Announcement", text = clean, actorUserId = math.floor(actorUserId)})
end)

bindFunction("PublishDJCommand", publishDJCommand)

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

bindFunction("ReportSignal", function(userId: any, signal: any, detail: any)
	if not SERVICE_ENABLED then return true end
	local key = userKey(userId)
	local cleanSignal = cleanText(signal, 48)
	local cleanDetail = if detail == nil then "" else cleanText(detail, 180)
	if not key or not cleanSignal then return false end
	-- Reports are intentionally aggregated locally; do not publish attacker-controlled details globally.
	local reportKey = key .. ":" .. cleanSignal
	local previous = signalCounts[reportKey]
	if previous == nil then
		local keyCount = 0
		for _ in pairs(signalCounts) do keyCount += 1 end
		-- Diagnostics are best-effort; cap unique keys to prevent memory growth.
		if keyCount >= MAX_SIGNAL_KEYS then return false end
		previous = 0
	end
	local count = previous + 1
	signalCounts[reportKey] = math.min(count, 100)
	if count == 1 then warn("[ClubMusic Global] Suspicious signal user=" .. key .. " type=" .. cleanSignal .. " detail=" .. (cleanDetail or "")) end
	return true
end)

local function validEnvelope(data: any): boolean
	if typeof(data) ~= "table" then return false end
	if data.version ~= 1 or data.senderJob == JOB_ID then return false end
	if typeof(data.id) ~= "string" or #data.id > 64 then return false end
	if not finiteNumber(data.at) or math.abs(os.time() - data.at) > 120 then return false end
	local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
	return ok and #encoded <= CONFIG.MaxMessageBytes
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
	if not validEnvelope(data) or data.kind ~= "Announcement" or not unseen(data.id) then return end
	local clean = cleanText(data.text, CONFIG.MaxAnnouncementLength)
	if clean then globalEventBindable:Fire({kind = "Announcement", text = clean, actorUserId = data.actorUserId}) end
end

local function onModeration(message)
	local data = message.Data
	if not validEnvelope(data) or data.kind ~= "Moderation" or not unseen(data.id) then return end
	if not finiteNumber(data.userId) or (data.field ~= "globalBan" and data.field ~= "requestBlocked")
		or typeof(data.value) ~= "boolean" then return end
	globalEventBindable:Fire({kind = "Moderation", userId = data.userId, field = data.field, value = data.value, reason = cleanText(data.reason, CONFIG.MaxModerationReasonLength)})
end

local function onXPBoost(message)
	local data = if typeof(message) == "table" and typeof(message.Data) == "table" then message.Data else message
	if typeof(data) ~= "table" or data.kind ~= "XPBoost"
		or (data.multiplier ~= 1 and data.multiplier ~= 2 and data.multiplier ~= 4)
		or not finiteNumber(data.expiresAt) or data.expiresAt < 0 then return end
	globalEventBindable:Fire({kind = "XPBoost", multiplier = data.multiplier, expiresAt = math.floor(data.expiresAt)})
end

local function onDJ(message)
	local data = message.Data
	if not validEnvelope(data) or data.kind ~= "DJ" or not unseen(data.id) then return end
	if not allowedDJCommands[data.command] or not finiteNumber(data.actorUserId) then return end
	local payload = if typeof(data.payload) == "table" then data.payload else {}
	if data.command == "SetRequestLock" and typeof(payload.locked) ~= "boolean" then return end
	globalEventBindable:Fire({kind = "DJ", command = data.command, payload = payload, actorUserId = data.actorUserId})
end

local function subscribeWithRetry(topic: string, callback: (any) -> ())
	task.spawn(function()
		while SERVICE_ENABLED do
			local ok, err = pcall(function() MessagingService:SubscribeAsync(topic, callback) end)
			if ok then
				-- Subscription stays active after SubscribeAsync returns.
				return
			end
			warn("[ClubMusic Global] Subscription failed for " .. topic .. "; retrying: " .. tostring(err))
			task.wait(CONFIG.SubscriptionRetrySeconds)
		end
	end)
end

if SERVICE_ENABLED then
	subscribeWithRetry(CONFIG.Topics.Announcements, onAnnouncement)
	subscribeWithRetry(CONFIG.Topics.Moderation, onModeration)
	subscribeWithRetry(CONFIG.Topics.DJ, onDJ)
	subscribeWithRetry(CONFIG.Topics.XPBoost, onXPBoost)
else
	warn("[ClubMusic Global] Disabled in Studio or by configuration; local UI controller remains fully functional.")
end

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
	if fourExpiry > now then return 4, fourExpiry, if twoExpiry > now then twoExpiry else 0 end
	if twoExpiry > now then return 2, twoExpiry, 0 end
	return 1, 0, 0
end

local function xpReceiptKey(receiptId: string): string?
	if #receiptId < 1 or #receiptId > MAX_PURCHASE_ID_LENGTH
		or not string.match(receiptId, "^[%w%-_]+$") then return nil end
	return "xpr_" .. receiptId
end

local function getXPReceipt(receiptId: string): any
	local key = xpReceiptKey(receiptId)
	if not key then return nil end
	local ok, result = pcall(function() return xpReceiptStore:GetAsync(key) end)
	if not ok then
		warn("[ClubMusic Global] XP receipt lookup failed: " .. tostring(result))
		return nil
	end
	return result
end

-- The active timer and pending receipt marker are committed in one UpdateAsync.
-- This single marker serializes transactions; a crash is recoverable from the per-purchase journal.
local function recoverPendingXPReceipt(record: any): (boolean, any)
	if typeof(record) ~= "table" or typeof(record.pendingReceipt) ~= "string" then return true, record end
	local pendingId = record.pendingReceipt
	local key = xpReceiptKey(pendingId)
	if not key then return false, record end
	local journal = getXPReceipt(pendingId)
	if typeof(journal) ~= "table" or (journal.status ~= "Prepared" and journal.status ~= "Completed") then
		warn("[ClubMusic Global] Pending XP receipt has no recoverable journal: " .. pendingId)
		return false, record
	end
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
		warn("[ClubMusic Global] XP PurchaseId is too long or contains unsupported characters; receipt remains pending.")
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
		local effectiveMultiplier, expiry = globalXPState(current)
		return true, expiry, effectiveMultiplier
	end

	local receiptReadOk, receiptRecord = pcall(function() return xpReceiptStore:GetAsync(receiptKey) end)
	if not receiptReadOk then return false, 0, 1 end
	if typeof(receiptRecord) == "table" and receiptRecord.status == "Completed" then
		local latestOk, latest = pcall(function() return globalControlStore:GetAsync(GLOBAL_XP_BOOST_KEY) end)
		if not latestOk then return false, 0, 1 end
		local effectiveMultiplier, expiry = globalXPState(latest)
		return true, expiry, effectiveMultiplier
	end

	-- One small durable record per purchase; the shared timer record no longer grows.
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
		local latestOk, latest = pcall(function() return globalControlStore:GetAsync(GLOBAL_XP_BOOST_KEY) end)
		if not latestOk then return false, 0, 1 end
		local effectiveMultiplier, expiry = globalXPState(latest)
		return true, expiry, effectiveMultiplier
	end

	local now = os.time()
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

	local effectiveMultiplier, expiry, lowerExpiry = globalXPState(cleared)
	local message = {kind = "XPBoost", multiplier = effectiveMultiplier, expiresAt = expiry, lowerExpiresAt = lowerExpiry}
	globalEventBindable:Fire(message)
	publishTopic(CONFIG.Topics.XPBoost, message)
	return true, expiry, effectiveMultiplier
end)

print("[ClubMusic Global] Cross-server service initialized. Enabled=" .. tostring(SERVICE_ENABLED) .. " JobId=" .. JOB_ID)
