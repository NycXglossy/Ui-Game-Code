--!strict
-- Club Neon XP accrual and global boost reconciliation.
-- Profile storage and receipt authority remain controller-owned.
return function(context: {[string]: any})
	local Players = context.Players
	local CONFIG = context.CONFIG
	local RunService = context.RunService
	local ControllerFunctions = context.ControllerFunctions
	local profiles = context.profiles
	local publishState = context.publishState
	local getStudioBoostState = context.getStudioBoostState

	local cachedGlobalXpMultiplier = 1
	local cachedGlobalXpExpiresAt = 0
	local cachedGlobalXpLowerExpiresAt = 0
	local xpLastAwardAt: {[number]: number} = {}
	local xpFractional: {[number]: number} = {}
	local xpLastSaveAt: {[number]: number} = {}
	local xpStateDirty = false

	local service = {}

	function service.SettlePlayerXP(player: Player, nowClock: number): boolean
		local userId = player.UserId
		local profile = profiles[userId]
		local lastClock = xpLastAwardAt[userId]
		if not profile then return false end
		if not lastClock then xpLastAwardAt[userId] = nowClock; return false end
		local elapsed = math.max(0, nowClock - lastClock)
		xpLastAwardAt[userId] = nowClock
		if elapsed <= 0 then return false end
		local boostedFourSeconds = 0
		local boostedTwoSeconds = 0
		if cachedGlobalXpMultiplier == 4 and cachedGlobalXpExpiresAt > 0 then
			local fourExpiryClock = nowClock + (cachedGlobalXpExpiresAt - os.time())
			boostedFourSeconds = math.clamp(fourExpiryClock - lastClock, 0, elapsed)
			if cachedGlobalXpLowerExpiresAt > cachedGlobalXpExpiresAt then
				local twoExpiryClock = nowClock + (cachedGlobalXpLowerExpiresAt - os.time())
				boostedTwoSeconds = math.clamp(twoExpiryClock - math.max(lastClock, fourExpiryClock), 0, elapsed - boostedFourSeconds)
			end
		elseif cachedGlobalXpMultiplier == 2 and cachedGlobalXpExpiresAt > 0 then
			local twoExpiryClock = nowClock + (cachedGlobalXpExpiresAt - os.time())
			boostedTwoSeconds = math.clamp(twoExpiryClock - lastClock, 0, elapsed)
		end
		local weightedSeconds = elapsed + boostedFourSeconds * 3 + boostedTwoSeconds
		-- Personal multiplier is derived from server-verified pass ownership.
		local personalMultiplier = math.clamp(tonumber(player:GetAttribute("PersonalXPMultiplier")) or 1, 1, 4)
		local fractional = (xpFractional[userId] or 0) + weightedSeconds * personalMultiplier * (CONFIG.XPPerMinute / 60)
		local gain = math.floor(fractional + 1e-7)
		xpFractional[userId] = fractional - gain
		if gain <= 0 then return false end
		profile.xp = math.min(9007199254740000, profile.xp + gain)
		player:SetAttribute("XP", profile.xp)
		player:SetAttribute("Level", math.floor(profile.xp / CONFIG.XPPerLevel) + 1)
		player:SetAttribute("XPToNextLevel", CONFIG.XPPerLevel - (profile.xp % CONFIG.XPPerLevel))
		local lastSavedAt = xpLastSaveAt[userId] or nowClock
		if nowClock - lastSavedAt >= 60 then
			xpLastSaveAt[userId] = nowClock
			ControllerFunctions.scheduleProfileSave(player)
		end
		return true
	end

	function service.SettleAll()
		local nowClock = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			service.SettlePlayerXP(player, nowClock)
		end
	end

	function service.SetGlobalXPState(multiplier: number, expiresAt: number, lowerExpiresAt: number?)
		if multiplier ~= 1 and multiplier ~= 2 and multiplier ~= 4 then return end
		if typeof(expiresAt) ~= "number" or expiresAt ~= expiresAt
			or expiresAt == math.huge or expiresAt == -math.huge or expiresAt < 0 then return end
		local cleanExpiry = if multiplier == 1 or expiresAt <= os.time() then 0 else math.floor(expiresAt)
		local cleanMultiplier = if cleanExpiry == 0 then 1 else multiplier
		local lowerIsFinite = typeof(lowerExpiresAt) == "number" and lowerExpiresAt == lowerExpiresAt
			and lowerExpiresAt ~= math.huge and lowerExpiresAt ~= -math.huge
		local cleanLowerExpiry = if cleanMultiplier == 4 and lowerIsFinite
			and (lowerExpiresAt :: number) > os.time() then math.floor(lowerExpiresAt :: number) else 0
		if cleanMultiplier == cachedGlobalXpMultiplier and cleanExpiry == cachedGlobalXpExpiresAt
			and cleanLowerExpiry == cachedGlobalXpLowerExpiresAt then return end
		service.SettleAll()
		cachedGlobalXpMultiplier = cleanMultiplier
		cachedGlobalXpExpiresAt = cleanExpiry
		cachedGlobalXpLowerExpiresAt = cleanLowerExpiry
		xpStateDirty = true
	end

	function service.RefreshGlobalXPBoost()
		if RunService:IsStudio() then
			local multiplier, expiresAt = getStudioBoostState()
			service.SetGlobalXPState(multiplier, expiresAt)
			return
		end
		local callOk, multiplier, expiresAt, lowerExpiresAt = ControllerFunctions.globalInvoke("GetGlobalXPBoost")
		if callOk and typeof(multiplier) == "number" and multiplier == multiplier
			and typeof(expiresAt) == "number" and expiresAt == expiresAt
			and (multiplier == 1 or multiplier == 2 or multiplier == 4) then
			service.SetGlobalXPState(multiplier, expiresAt, lowerExpiresAt)
		end
		if cachedGlobalXpExpiresAt > 0 and cachedGlobalXpExpiresAt <= os.time() then
			if cachedGlobalXpLowerExpiresAt > os.time() then
				service.SetGlobalXPState(2, cachedGlobalXpLowerExpiresAt)
			else
				service.SetGlobalXPState(1, 0)
			end
		end
	end

	function service.InitializePlayer(userId: number)
		xpLastAwardAt[userId] = os.clock()
		xpFractional[userId] = 0
		xpLastSaveAt[userId] = os.clock()
	end

	function service.RemovePlayer(player: Player)
		local userId = player.UserId
		service.SettlePlayerXP(player, os.clock())
		xpLastAwardAt[userId] = nil
		xpFractional[userId] = nil
		xpLastSaveAt[userId] = nil
	end

	function service.GetClientState(): {[string]: number}
		local now = os.time()
		return {
			multiplier = if cachedGlobalXpExpiresAt > now then cachedGlobalXpMultiplier
				elseif cachedGlobalXpLowerExpiresAt > now then 2 else 1,
			expiresAt = if cachedGlobalXpExpiresAt > now then cachedGlobalXpExpiresAt
				elseif cachedGlobalXpLowerExpiresAt > now then cachedGlobalXpLowerExpiresAt else 0,
		}
	end

	function service.Start(controllerScript: Instance)
		task.spawn(function()
			service.RefreshGlobalXPBoost()
			while controllerScript.Parent do
				task.wait(45 + Random.new():NextNumber(0, 15))
				service.RefreshGlobalXPBoost()
			end
		end)
		task.spawn(function()
			while controllerScript.Parent do
				task.wait(5)
				local nowClock = os.clock()
				local changed = xpStateDirty
				xpStateDirty = false
				for _, player in ipairs(Players:GetPlayers()) do
					if service.SettlePlayerXP(player, nowClock) then changed = true end
				end
				if changed then publishState(nil) end
			end
		end)
	end

	return service
end
