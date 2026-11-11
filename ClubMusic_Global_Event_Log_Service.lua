--!strict
-- Bounded, expiring operational event log. Does not record chat or raw player data.
local Service = {}
Service.__index = Service

local DEFAULT_TTL_SECONDS = 24 * 60 * 60
local MAX_DETAIL_LENGTH = 180
local MAX_KIND_LENGTH = 48
local MAX_QUERY_LIMIT = 100

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isEnabled(self)
	local ok, enabled = pcall(self.d.isEnabled)
	return ok and enabled == true
end

function Service.new(dependencies)
	assert(type(dependencies) == "table", "EventLog dependencies must be a table")
	assert(dependencies.memoryStoreService ~= nil, "EventLog requires memoryStoreService")
	assert(type(dependencies.isEnabled) == "function", "EventLog requires isEnabled")
	local self = setmetatable({
		d = dependencies,
		count = 0,
		lastError = nil,
	}, Service)
	local ok, mapOrError = pcall(function()
		return dependencies.memoryStoreService:GetSortedMap(dependencies.mapName or "ClubMusic_EventLog_v1")
	end)
	if not ok then
		self.lastError = tostring(mapOrError)
		self.map = nil
	else
		self.map = mapOrError
	end
	return self
end

function Service:Record(kind, detail, severity)
	if not isEnabled(self) or not self.map then return false end
	if type(kind) ~= "string" or #kind < 1 or #kind > MAX_KIND_LENGTH then return false end
	local safeDetail = if type(detail) == "string" then string.sub(detail, 1, MAX_DETAIL_LENGTH)
		else string.sub(tostring(detail or ""), 1, MAX_DETAIL_LENGTH)
	local safeSeverity = if type(severity) == "string" and #severity <= 16 then severity else "Info"
	local jobId = tostring(self.d.jobId or "unknown")
	local guidOk, guid = pcall(self.d.guid)
	if not guidOk then
		self.lastError = tostring(guid)
		return false
	end
	local id = tostring(os.time()) .. ":" .. jobId .. ":" .. tostring(guid)
	local value = {
		kind = kind,
		detail = safeDetail,
		severity = safeSeverity,
		jobId = jobId,
		at = os.time(),
	}
	local ttl = self.d.ttlSeconds
	if not isFiniteNumber(ttl) or ttl < 60 then ttl = DEFAULT_TTL_SECONDS end
	local ok, err = pcall(function()
		self.map:SetAsync(id, value, math.floor(ttl), os.time())
	end)
	if ok then
		self.count += 1
		self.lastError = nil
	else
		self.lastError = tostring(err)
	end
	return ok
end

function Service:GetRecent(limit)
	if not isEnabled(self) or not self.map then return false, {} end
	local requested = tonumber(limit)
	if not isFiniteNumber(requested) then requested = 25 end
	local count = math.clamp(math.floor(requested), 1, MAX_QUERY_LIMIT)
	local ok, result = pcall(function()
		return self.map:GetRangeAsync(Enum.SortDirection.Descending, count)
	end)
	if not ok then
		self.lastError = tostring(result)
		return false, {}
	end
	local out = {}
	if type(result) == "table" then
		for _, entry in ipairs(result) do
			if type(entry) == "table" and typeof(entry.value) == "table" then
				table.insert(out, table.clone(entry.value))
			end
		end
	end
	self.lastError = nil
	return true, out
end

function Service:GetStatus()
	return {
		state = if isEnabled(self) and self.map then "Healthy" else if not self.map then "Degraded" else "Disabled",
		written = self.count,
		lastError = self.lastError,
		available = self.map ~= nil,
	}
end

function Service:Start()
	return self.map ~= nil
end

function Service:Stop()
	-- MemoryStore owns the backing map; no local resources need closing.
end

return Service
