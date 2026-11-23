-- Club Neon remote payload validation and request eligibility gates.
-- The controller supplies authoritative state through accessors; this module
-- does not own queue, moderation, or request-accounting state.
return function(context)
	local ControllerFunctions = context.ControllerFunctions

	local function isValidString(value: any, maxLength: number): boolean
		return typeof(value) == "string" and #value > 0 and #value <= maxLength
	end

	local function isBoundedPayload(payload: any): boolean
		if typeof(payload) ~= "table" then return false end
		if context.sanityValidationService then
			local ok, valid = pcall(context.sanityValidationService.ValidateDataTree, payload, {
				maxDepth = 3,
				maxEntries = 64,
				maxStringLength = 1024,
			})
			if not ok or valid ~= true then return false end
		end
		local topCount = 0
		for key, value in pairs(payload) do
			topCount += 1
			if topCount > 16 or typeof(key) ~= "string" or #key > 32 then return false end
			if typeof(value) == "string" then
				if #value > 1024 then return false end
			elseif typeof(value) == "number" then
				if not ControllerFunctions.isFiniteNumber(value) then return false end
			elseif typeof(value) == "table" then
				local nestedCount = 0
				for nestedKey, nestedValue in pairs(value) do
					nestedCount += 1
					local nestedKeyType = typeof(nestedKey)
					local validNestedKey = (nestedKeyType == "string" and #nestedKey <= 32)
						or (nestedKeyType == "number" and nestedKey % 1 == 0 and nestedKey >= 1 and nestedKey <= 16)
					if nestedCount > 16 or not validNestedKey then return false end
					local valueType = typeof(nestedValue)
					if valueType == "string" then
						if #nestedValue > 1024 then return false end
					elseif valueType == "number" then
						if not ControllerFunctions.isFiniteNumber(nestedValue) then return false end
					elseif valueType ~= "boolean" then
						return false
					end
				end
			elseif typeof(value) ~= "boolean" then
				return false
			end
		end
		return true
	end

	local function findTarget(actor: Player, userId: any): Player?
		if not ControllerFunctions.isFiniteNumber(userId) or userId < 1 or userId % 1 ~= 0 or userId > 9007199254740991 then return nil end
		local target = context.Players:GetPlayerByUserId(userId)
		if not target or target == actor then return nil end
		if not ControllerFunctions.canModerate(actor, target) then
			context.notify(actor, "You can't moderate someone with equal or higher rank.", "warn")
			return nil
		end
		return target
	end

	local function requestBlockReason(player: Player, trackId: string, now: number): string?
		if player:GetAttribute("GlobalModerationPending") == true then
			return "Global moderation is temporarily checking your account. Song requests are paused until verification completes."
		end
		if context.blockedUsers[player.UserId] then return "Your requests are disabled by staff." end
		if ControllerFunctions.isTrackBlocked(trackId) then return "That track has been blocked by ClubMusic staff." end
		if context.getDjControlModeEnabled() and context.getDjControlModeUserId() ~= player.UserId then
			return "DJ Control Mode is active. Only the current DJ controller can submit requests."
		end
		if context.getRequestsLocked() and ControllerFunctions.getLevel(player) < 3 then return "Emergency request lock is active on this server." end
		if ControllerFunctions.countPlayerEntries() >= context.CONFIG.MaxQueueSize then return "The request queue is full." end
		local cooldown = ControllerFunctions.cooldownFor(player)
		local sinceLast = now - (context.lastRequestAt[player.UserId] or -1000)
		if sinceLast < cooldown then
			return string.format("Slow down - wait %ds to request again.", math.ceil(cooldown - sinceLast))
		end
		local count = context.requestCounts[player.UserId] or 0
		local limit = ControllerFunctions.requestLimitFor(player)
		if count >= limit then
			return string.format("Request limit reached (%d/%d). Wait for your track to play.", count, limit)
		end
		if context.nowPlaying.trackId == trackId then return "That track is playing right now." end
		for _, queued in ipairs(context.queue) do
			if queued.trackId == trackId then return "That track is already in the queue." end
		end
		return nil
	end

	return {
		isValidString = isValidString,
		isBoundedPayload = isBoundedPayload,
		findTarget = findTarget,
		requestBlockReason = requestBlockReason,
	}
end
