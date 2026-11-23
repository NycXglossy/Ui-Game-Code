--!strict
-- Server-local profile write-lock primitives.
-- Each holder receives an identity token so stale completions cannot release a newer lock.
return function(dependencies: {[string]: any})
	local locks: {[number]: any} = dependencies.locks
	local timeoutLimit: number = dependencies.timeoutLimit

	local function acquire(userId: number, timeoutSeconds: number?): any
		local startedAt = os.clock()
		local timeout = if typeof(timeoutSeconds) == "number"
			then math.clamp(timeoutSeconds, 0, timeoutLimit)
			else timeoutLimit
		while locks[userId] do
			if os.clock() - startedAt >= timeout then
				warn("[ClubMusic] Timed out waiting for profile write lock for userId " .. tostring(userId))
				return nil
			end
			task.wait(0.05)
		end
		local lockToken = {}
		locks[userId] = lockToken
		return lockToken
	end

	local function release(userId: number, lockToken: any?)
		if lockToken == nil or locks[userId] == lockToken then
			locks[userId] = nil
		end
	end

	return {
		acquire = acquire,
		release = release,
	}
end
