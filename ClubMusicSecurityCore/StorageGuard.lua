--!strict
-- Shared private storage-operation guard used by security modules.
return (function()
	local tokens = 5
	local updatedAt = os.clock()
	local openUntil = 0
	local failures = 0
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
		tokens = math.min(5, tokens + math.max(0, now - updatedAt) * 0.2)
		updatedAt = now
		-- Keep two tokens available for critical idempotency and incident writes.
		-- Audit and moderator reads cannot consume this reserved capacity.
		if priority ~= "critical" and tokens <= 2 then return false, "CriticalCapacityReserved" end
		if tokens < 1 then return false, "LocalTokenBucketEmpty" end
		tokens -= 1
		return true
	end
	local function Failure(err)
		if isThrottleOrTimeout(err) then
			failures += 1
			openUntil = os.clock() + math.random(15, 30)
			return true
		end
		return false
	end
	local function GetStatus()
		return {tokens = tokens, circuitOpen = os.clock() < openUntil,
			openForSeconds = math.max(0, openUntil - os.clock()), failures = failures,
			refillPerSecond = 0.2, capacity = 5}
	end
	return {Allow = Allow, Failure = Failure, GetStatus = GetStatus}
end)()
