--!strict
-- Facade over the existing shared token buckets; intentionally creates no second limiter.
local Service = {}
Service.__index = Service

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Service.new(dependencies)
	assert(type(dependencies) == "table", "RateLimit dependencies must be a table")
	assert(type(dependencies.isEnabled) == "function", "RateLimit requires isEnabled")
	assert(type(dependencies.consumeShared) == "function", "RateLimit requires consumeShared")
	return setmetatable({
		d = dependencies,
		checks = 0,
		rejected = 0,
		sharedFailures = 0,
		lastError = nil,
	}, Service)
end

function Service:Consume(key, capacity, refill, cost)
	local enabledOk, enabled = pcall(self.d.isEnabled)
	if not enabledOk then
		self.lastError = tostring(enabled)
		return false, false
	end
	-- Cross-server limits are deliberately bypassed while global service is disabled
	-- (for example, ordinary isolated Studio sessions).
	if enabled ~= true then return true, true end
	if type(key) ~= "string" or #key < 1 or #key > 100
		or not isFiniteNumber(capacity) or capacity <= 0
		or not isFiniteNumber(refill) or refill < 0
		or not isFiniteNumber(cost) or cost <= 0 or cost > capacity then
		self.rejected += 1
		return false, false
	end
	self.checks += 1
	local callOk, allowed, shared = pcall(self.d.consumeShared, key, capacity, refill, cost)
	if not callOk then
		self.sharedFailures += 1
		self.rejected += 1
		self.lastError = tostring(allowed)
		return false, false
	end
	if allowed ~= true then self.rejected += 1 end
	if shared ~= true then self.sharedFailures += 1 end
	self.lastError = nil
	return allowed == true, shared == true
end

function Service:GetStatus()
	local enabledOk, enabled = pcall(self.d.isEnabled)
	local state = if not enabledOk then "Degraded" else if enabled ~= true then "Disabled" else "Healthy"
	return {
		state = state,
		checks = self.checks,
		rejected = self.rejected,
		sharedFailures = self.sharedFailures,
		usesExistingBuckets = true,
		lastError = self.lastError,
	}
end

function Service:Start()
	return true
end

function Service:Stop()
end

return Service
