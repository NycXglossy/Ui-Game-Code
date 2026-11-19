--!strict
-- Bounded, server-local security event history for staff review.
-- This is an event timeline, not a frame-by-frame recorder or durable evidence store.
local Players = game:GetService("Players")

local Service = {}
Service.__index = Service

local SERVER_CAPACITY = 2048
local MAX_EVENT_TYPE = 48
local MAX_SOURCE = 32
local MAX_METADATA_KEYS = 12
local MAX_METADATA_STRING = 96
local MAX_QUERY = 100
local MAX_USER_ID = 9007199254740991

local function finiteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function validUserId(value: any, allowZero: boolean?): boolean
	return finiteNumber(value) and value % 1 == 0
		and value >= (if allowZero then 0 else 1) and value <= MAX_USER_ID
end

local function cleanString(value: any, limit: number): string
	local result = string.sub(tostring(value or ""), 1, limit)
	result = result:gsub("[%c]", " ")
	return (string.gsub(result, "^%s*(.-)%s*$", "%1"))
end

local function normalizeEventType(value: any): string?
	if typeof(value) ~= "string" then return nil end
	local normalized = cleanString(value, MAX_EVENT_TYPE)
	if normalized == "" or #normalized > MAX_EVENT_TYPE or not string.match(normalized, "^[%w_%-]+$") then
		return nil
	end
	return normalized
end

local function normalizeSeverity(value: any): string
	local normalized = string.lower(cleanString(value or "Info", 12))
	if normalized == "warning" then return "Warning" end
	if normalized == "error" then return "Error" end
	if normalized == "critical" then return "Critical" end
	return "Info"
end

local function sanitizeMetadata(value: any): {[string]: any}
	local clean = {}
	if typeof(value) ~= "table" then return clean end
	local count = 0
	for key, item in pairs(value) do
		if count >= MAX_METADATA_KEYS then break end
		if typeof(key) == "string" then
			local safeKey = cleanString(key, 24)
			if safeKey ~= "" and string.match(safeKey, "^[%w_%-]+$") and clean[safeKey] == nil then
				local kind = typeof(item)
				if kind == "string" then
					clean[safeKey] = cleanString(item, MAX_METADATA_STRING)
					count += 1
				elseif kind == "boolean" then
					clean[safeKey] = item
					count += 1
				elseif kind == "number" and finiteNumber(item) then
					clean[safeKey] = math.clamp(item, -1000000000, 1000000000)
					count += 1
				end
			end
		end
	end
	return clean
end

local function copyEvent(item: {[string]: any}): {[string]: any}
	local copied = table.clone(item)
	-- Metadata is scalar-only after sanitization; clone it separately so callers
	-- cannot mutate the retained event through a returned query result.
	copied.metadata = if typeof(item.metadata) == "table" then table.clone(item.metadata) else {}
	return copied
end

local function validTimestamp(value: any): boolean
	return finiteNumber(value) and value >= 0
end

function Service.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table" and type(dependencies.authorize) == "function",
		"SecurityReplayService requires an authorization callback")
	return setmetatable({
		d = dependencies,
		events = {},
		head = 1,
		count = 0,
		nextId = 0,
		recorded = 0,
		dropped = 0,
		denied = 0,
		started = false,
	}, Service)
end

function Service:Record(eventType: any, userId: any, targetUserId: any, severity: any, source: any, metadata: any)
	if not self.started then return false, "Replay service is not started." end
	local normalizedType = normalizeEventType(eventType)
	if not normalizedType or not validUserId(userId, true) then
		self.dropped += 1
		return false, "Invalid replay event."
	end
	if targetUserId ~= nil and not validUserId(targetUserId, true) then
		self.dropped += 1
		return false, "Invalid replay target."
	end
	local event = {
		id = self.nextId + 1,
		at = os.time(),
		clock = os.clock(),
		jobId = cleanString(game.JobId, 40),
		userId = math.floor(userId),
		targetUserId = if targetUserId ~= nil then math.floor(targetUserId) else 0,
		type = normalizedType,
		severity = normalizeSeverity(severity),
		source = cleanString(source or "Server", MAX_SOURCE),
		metadata = sanitizeMetadata(metadata),
	}
	self.nextId = event.id
	local index = ((self.head + self.count - 1) % SERVER_CAPACITY) + 1
	if self.count >= SERVER_CAPACITY then
		self.events[self.head] = event
		self.head = (self.head % SERVER_CAPACITY) + 1
		self.dropped += 1
	else
		self.events[index] = event
		self.count += 1
	end
	self.recorded += 1
	return true, event.id
end

function Service:_authorized(actor: any): boolean
	if typeof(actor) ~= "Instance" or not actor:IsA("Player") or actor.Parent ~= Players then
		return false
	end
	local ok, allowed = pcall(self.d.authorize, actor.UserId, "GlobalModeration")
	return ok and allowed == true and actor.Parent == Players
end

-- Query accepts an inclusive upper timestamp, exact event type, and optional
-- inclusive lower timestamp. Results are newest-first and detached from storage.
function Service:Query(actor: any, targetUserId: any, limit: any, beforeTimestamp: any, eventType: any, afterTimestamp: any)
	if not self:_authorized(actor) then
		self.denied += 1
		return false, {}, "Security replay permission denied."
	end
	if targetUserId ~= nil and not validUserId(targetUserId, true) then
		return false, {}, "Invalid target UserId."
	end
	local queryLimit = 50
	if limit ~= nil then
		if not finiteNumber(limit) or limit % 1 ~= 0 or limit < 1 or limit > MAX_QUERY then
			return false, {}, "Query limit must be an integer from 1 to 100."
		end
		queryLimit = limit
	end
	if beforeTimestamp ~= nil and not validTimestamp(beforeTimestamp) then
		return false, {}, "Invalid upper timestamp."
	end
	if afterTimestamp ~= nil and not validTimestamp(afterTimestamp) then
		return false, {}, "Invalid lower timestamp."
	end
	local before = beforeTimestamp or math.huge
	local after = afterTimestamp or 0
	if after > before then return false, {}, "Lower timestamp must not exceed upper timestamp." end
	local filterType: string? = nil
	if eventType ~= nil then
		filterType = normalizeEventType(eventType)
		if not filterType then return false, {}, "Invalid event-type filter." end
	end

	local result = {}
	for offset = 0, self.count - 1 do
		local index = ((self.head + self.count - offset - 2) % SERVER_CAPACITY) + 1
		local item = self.events[index]
		if item and item.at >= after and item.at <= before
			and (targetUserId == nil or item.userId == targetUserId or item.targetUserId == targetUserId)
			and (filterType == nil or item.type == filterType) then
			table.insert(result, copyEvent(item))
			if #result >= queryLimit then break end
		end
	end
	return true, result
end

function Service:GetStatus()
	return {
		state = if self.started then "Ready" else "Stopped",
		recorded = self.recorded,
		retained = self.count,
		capacity = SERVER_CAPACITY,
		dropped = self.dropped,
		deniedQueries = self.denied,
		scope = "PerServerMemoryOnly",
		frameCapture = false,
		persistentWrites = 0,
	}
end

function Service:Start(): boolean
	self.started = true
	return true
end

function Service:Stop()
	self.started = false
	table.clear(self.events)
	self.head = 1
	self.count = 0
end

return Service
