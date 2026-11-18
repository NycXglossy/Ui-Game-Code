--!strict
-- Central server-side membership entitlement resolver.
-- Uses the existing SecurityCore.Authorization group-rank cache and bounded,
-- per-live-player game-pass cache. This module never reads or writes a DataStore.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Service = {}
Service.__index = Service

local CACHE_SECONDS = 300
local RETRY_SECONDS = 15

type PassState = {
	vip: boolean,
	vvip: boolean,
	tikiTide: boolean,
	expiresAt: number,
	lastRefreshAt: number,
	lastError: string?,
}

local function validPassId(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and value % 1 == 0
end

local function validPlayer(player: any): boolean
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

function Service.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table", "EntitlementAuthority dependencies are required")
	assert(typeof(dependencies.authorization) == "table", "SecurityCore.Authorization is required")

	local passIds = if typeof(dependencies.passIds) == "table" then dependencies.passIds else {}
	return setmetatable({
		authorization = dependencies.authorization,
		passIds = {
			vip = if validPassId(passIds.vip) then math.floor(passIds.vip) else 0,
			vvip = if validPassId(passIds.vvip) then math.floor(passIds.vvip) else 0,
			tikiTide = if validPassId(passIds.tikiTide) then math.floor(passIds.tikiTide) else 0,
		},
		cache = {} :: {[number]: PassState},
		refreshInFlight = {} :: {[number]: boolean},
		refreshes = 0,
		refreshFailures = 0,
		lastError = nil :: string?,
	}, Service)
end

function Service:_lookup(userId: number, passId: number): (boolean?, string?)
	if passId <= 0 then return false, nil end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
	end)
	if not ok then
		return nil, string.sub(tostring(owns), 1, 160)
	end
	if typeof(owns) ~= "boolean" then
		return nil, "Marketplace returned a non-boolean ownership result."
	end
	return owns, nil
end

function Service:Refresh(player: Player, force: boolean?): boolean
	if not validPlayer(player) then return false end
	local userId = player.UserId
	local existing = self.cache[userId]
	if force ~= true and existing and existing.expiresAt > os.clock() then
		return true
	end

	if self.refreshInFlight[userId] then
		while self.refreshInFlight[userId] and validPlayer(player) do
			task.wait(0.05)
		end
		local current = self.cache[userId]
		return validPlayer(player) and current ~= nil and current.expiresAt > os.clock()
	end

	self.refreshInFlight[userId] = true
	self.refreshes += 1

	local previous = self.cache[userId]
	local vip, vipError = self:_lookup(userId, self.passIds.vip)
	local vvip, vvipError = self:_lookup(userId, self.passIds.vvip)
	local tikiTide, tikiTideError = self:_lookup(userId, self.passIds.tikiTide)

	if not validPlayer(player) then
		self.cache[userId] = nil
		self.refreshInFlight[userId] = nil
		return false
	end

	local errors = {}
	if vipError then table.insert(errors, "VIP: " .. vipError) end
	if vvipError then table.insert(errors, "VVIP: " .. vvipError) end
	if tikiTideError then table.insert(errors, "Tiki Tide: " .. tikiTideError) end

	-- A transient lookup failure does not erase a previously verified positive
	-- game-pass result. Game-pass ownership is persistent; new players fail closed.
	local nextState: PassState = {
		vip = if vip ~= nil then vip else (previous ~= nil and previous.vip == true),
		vvip = if vvip ~= nil then vvip else (previous ~= nil and previous.vvip == true),
		tikiTide = if tikiTide ~= nil then tikiTide else (previous ~= nil and previous.tikiTide == true),
		expiresAt = os.clock() + (if #errors == 0 then CACHE_SECONDS else RETRY_SECONDS),
		lastRefreshAt = os.clock(),
		lastError = if #errors > 0 then string.sub(table.concat(errors, " | "), 1, 300) else nil,
	}
	self.cache[userId] = nextState
	self.refreshInFlight[userId] = nil

	if #errors > 0 then
		self.refreshFailures += 1
		self.lastError = nextState.lastError
	else
		self.lastError = nil
	end
	return #errors == 0
end

function Service:_scheduleRefresh(player: Player)
	local userId = player.UserId
	if self.refreshInFlight[userId] then return end
	task.spawn(function()
		self:Refresh(player, false)
	end)
end

function Service:GetTier(player: Player, rewardedTier: any): (number, {[string]: any})
	if not validPlayer(player) then
		return 0, {ready = false, groupMember = false, vip = false, vvip = false, tikiTide = false}
	end

	local userId = player.UserId
	local state = self.cache[userId]
	if not state or state.expiresAt <= os.clock() then
		self:_scheduleRefresh(player)
	end

	local groupMember = false
	local authorization = self.authorization
	local authOk, isMember = pcall(authorization.IsGroupMember, authorization, player)
	if authOk and isMember == true then groupMember = true end

	local staff = false
	local owner = false
	local rankOk, _, level = pcall(authorization.GetRank, authorization, player)
	if rankOk and typeof(level) == "number" then
		staff = level >= 1 -- Moderator (150) and every higher staff rank receive VIP.
		owner = level >= 4
	end

	local awarded = if typeof(rewardedTier) == "number" and rewardedTier == rewardedTier
		then math.clamp(math.floor(rewardedTier), 0, 3) else 0
	local paidTier = if state and state.tikiTide then 3
		elseif state and state.vvip then 2
		elseif state and state.vip then 1 else 0
	local groupTier = if groupMember then 1 else 0
	local staffTier = if staff then 1 else 0
	local tier = if owner then 3 else math.max(groupTier, paidTier, awarded, staffTier)

	return tier, {
		ready = state ~= nil and state.expiresAt > os.clock(),
		groupMember = groupMember,
		staff = staff,
		owner = owner,
		vip = tier >= 1,
		vvip = state ~= nil and state.vvip == true,
		tikiTide = state ~= nil and state.tikiTide == true,
		rewardedTier = awarded,
		paidTier = paidTier,
		lastError = if state then state.lastError else nil,
	}
end

function Service:Clear(player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local userId = player.UserId
	self.cache[userId] = nil
	-- Leave an outstanding lookup marked in-flight until it returns. The lookup
	-- checks the original Player instance before publishing, preventing a rapid
	-- rejoin from racing a second refresh for the same UserId.
end

function Service:GetStatus(): {[string]: any}
	local entries = 0
	for _ in pairs(self.cache) do entries += 1 end
	return {
		cacheEntries = entries,
		refreshes = self.refreshes,
		refreshFailures = self.refreshFailures,
		refreshInFlight = (function()
			local count = 0
			for _ in pairs(self.refreshInFlight) do count += 1 end
			return count
		end)(),
		lastError = self.lastError,
		cacheSeconds = CACHE_SECONDS,
		retrySeconds = RETRY_SECONDS,
	}
end

return Service
