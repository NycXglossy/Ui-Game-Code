--!strict
-- Bounded, server-local security event history for staff review.
-- This is an event timeline, not a frame-by-frame recorder or durable evidence store.
local Players = game:GetService("Players")

local Service = {}
Service.__index = Service

local SERVER_CAPACITY = 2048
local PLAYER_CAPACITY = 128
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
	return (result:gsub("[%c]", " "))
end

local function sanitizeMetadata(value: any): {[string]: any}
	local clean = {}
	if typeof(value) ~= "table" then return clean end
	local count = 0
	for key, item in pairs(value) do
		if count >= MAX_METADATA_KEYS then break end
		if typeof(key) == "string" then
			local safeKey = cleanString(key, 24)
			if safeKey ~= "" then
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
	if typeof(eventType) ~= "string" or #eventType < 1 or #eventType > MAX_EVENT_TYPE
		or not validUserId(userId, true) then
		self.dropped += 1
		return false, "Invalid replay event."
	end
	if targetUserId ~= nil and not validUserId(targetUserId, true) then
		self.dropped += 1
		return false, "Invalid replay target."
	end
	local normalizedSeverity = cleanString(severity or "Info", 12)
	local event = {
		id = self.nextId + 1,
		at = os.time(),
		clock = os.clock(),
		jobId = cleanString(game.JobId, 40),
		userId = math.floor(userId),
		targetUserId = if targetUserId ~= nil then math.floor(targetUserId) else 0,
		type = eventType,
		severity = normalizedSeverity,
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

function Service:Query(actor: any, targetUserId: any, limit: any, beforeTimestamp: any, eventType: any)
	if not self:_authorized(actor) then
		self.denied += 1
		return false, {}, "Security replay permission denied."
	end
	if targetUserId ~= nil and not validUserId(targetUserId, true) then return false, {}, "Invalid target UserId." end
	local queryLimit = if finiteNumber(limit) then math.clamp(math.floor(limit), 1, MAX_QUERY) else 50
	local before = if finiteNumber(beforeTimestamp) and beforeTimestamp > 0 then beforeTimestamp else math.huge
	local filterType = if typeof(eventType) == "string" and #eventType <= MAX_EVENT_TYPE then eventType else nil
	local result = {}
	for offset = 0, self.count - 1 do
		local index = ((self.head + self.count - offset - 2) % SERVER_CAPACITY) + 1
		local item = self.events[index]
		if item and item.at <= before
			and (targetUserId == nil or item.userId == targetUserId or item.targetUserId == targetUserId)
			and (filterType == nil or item.type == filterType) then
			table.insert(result, table.clone(item))
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
		perPlayerCapacity = PLAYER_CAPACITY,
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
