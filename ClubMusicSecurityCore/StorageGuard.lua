--!strict
-- Shared private storage-operation guard used by security modules.
-- Local-only circuit breaker; no MemoryStore records are created.
return (function()
	local tokens = 5
	local updatedAt = os.clock()
	local openUntil = 0
	local failures = 0
	local failureWindowAt = 0
	local probeInFlight = false
	local lastSuccessAt = 0
	local consecutiveOpens = 0

	local function isThrottleOrTimeout(err)
		local message = string.lower(tostring(err))
		return string.find(message, "thrott", 1, true) ~= nil
			or string.find(message, "timeout", 1, true) ~= nil
			or string.find(message, "timed out", 1, true) ~= nil
			or string.find(message, "request queue", 1, true) ~= nil
	end

	local function Allow(priority)
		local now = os.clock()
		if now < openUntil then return false, "CircuitOpen" end
		if openUntil > 0 then
			if probeInFlight then return false, "HalfOpenProbeInFlight" end
			probeInFlight = true
		end
		tokens = math.min(5, tokens + math.max(0, now - updatedAt) * 0.2)
		updatedAt = now
		-- Keep two tokens available for critical idempotency and incident writes.
		if priority ~= "critical" and tokens <= 2 then
			if openUntil > 0 then probeInFlight = false end
			return false, "CriticalCapacityReserved"
		end
		if tokens < 1 then
			if openUntil > 0 then probeInFlight = false end
			return false, "LocalTokenBucketEmpty"
		end
		tokens -= 1
		return true
	end

	local function Success()
		lastSuccessAt = os.clock()
		failures = 0
		failureWindowAt = 0
		openUntil = 0
		probeInFlight = false
		consecutiveOpens = 0
	end

	local function Failure(err)
		if not isThrottleOrTimeout(err) then
			probeInFlight = false
			return false
		end
		local now = os.clock()
		probeInFlight = false
		if now - failureWindowAt > 60 then
			failures = 0
			failureWindowAt = now
		end
		failures += 1
		if failures >= 3 then
			consecutiveOpens = math.min(4, consecutiveOpens + 1)
			local cooldown = math.min(120, 15 * (2 ^ (consecutiveOpens - 1)))
			openUntil = now + cooldown
			failures = 0
			failureWindowAt = now
			return true
		end
		return false
	end

	local function GetStatus()
		return {
			tokens = tokens,
			circuitOpen = os.clock() < openUntil,
			openForSeconds = math.max(0, openUntil - os.clock()),
			halfOpenProbeInFlight = probeInFlight,
			failuresInWindow = failures,
			failureWindowSeconds = 60,
			lastSuccessAgo = if lastSuccessAt > 0 then math.max(0, os.clock() - lastSuccessAt) else nil,
			refillPerSecond = 0.2,
			capacity = 5,
			criticalReserve = 2,
		}
	end

	return {Allow = Allow, Success = Success, Failure = Failure, GetStatus = GetStatus}
end)()
