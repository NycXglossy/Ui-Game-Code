--!strict
-- Central server-side authorization authority for Tiki Tide / ClubMusic.
-- No external BindableFunction resolver is used. Permission checks are local,
-- cached, synchronous and fail closed while a group-rank refresh is unavailable.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Service = {}
Service.__index = Service

local GROUP_ID = 500470662
local CACHE_MIN_SECONDS = 120
local CACHE_MAX_SECONDS = 300
local RETRY_SECONDS = 15
local MAX_DENIAL_KEYS = 256

local PERMISSION_LEVELS = {
	GlobalDJ = 1,
	GlobalModeration = 2,
	GlobalAnnouncement = 2,
	GlobalConfig = 3,
	SecurityPolicy = 3,
	IncidentResponse = 3,
}

local DEFAULT_THRESHOLDS = {
	GroupDJ = 100,
	Moderator = 150,
	Admin = 200,
	CoOwner = 254,
	Owner = 255,
}

local sharedInstance: any = nil

local function validUserId(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and value % 1 == 0
end

function Service.new(dependencies: {[string]: any}?)
	dependencies = if typeof(dependencies) == "table" then dependencies else {}
	local thresholds = if typeof(dependencies.thresholds) == "table" then dependencies.thresholds else DEFAULT_THRESHOLDS
	local instance = setmetatable({
		groupId = if validUserId(dependencies.groupId) then math.floor(dependencies.groupId) else GROUP_ID,
		studioStaff = dependencies.studioStaff ~= false,
		thresholds = thresholds,
		staffUserIds = {},
		onDenied = dependencies.onDenied,
		cache = {},
		refreshInFlight = {},
		retryAfter = {},
		connections = {},
		checks = 0,
		allowed = 0,
		denied = 0,
		refreshes = 0,
		refreshFailures = 0,
		lastError = nil,
		started = false,
		denials = {},
		deniedActions = 0,
	}, Service)
	instance:Configure(dependencies)
	return instance
end

function Service:Configure(dependencies: {[string]: any})
	if typeof(dependencies) ~= "table" then return end
	if validUserId(dependencies.groupId) then self.groupId = math.floor(dependencies.groupId) end
	if typeof(dependencies.studioStaff) == "boolean" then self.studioStaff = dependencies.studioStaff end
	if typeof(dependencies.thresholds) == "table" then self.thresholds = dependencies.thresholds end
	if typeof(dependencies.staffUserIds) == "table" then
		local configured = {}
		for _, userId in ipairs(dependencies.staffUserIds) do
			if validUserId(userId) then configured[math.floor(userId)] = true end
		end
		self.staffUserIds = configured
	end
end

function Service:_rankName(level: number): string
	if level >= 4 then return "OWNER" end
	if level >= 3 then return "CO-OWNER" end
	if level >= 2 then return "ADMIN" end
	if level >= 1 then return "MODERATOR" end
	return "GUEST"
end

function Service:GetRank(player: Player): (string, number)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return "GUEST", 0
	end
	if (RunService:IsStudio() and self.studioStaff) or self.staffUserIds[player.UserId] == true then
		return "OWNER", 4
	end
	local cached = self.cache[player.UserId]
	if not cached or cached.expiresAt <= os.clock() then
		if cached then self.cache[player.UserId] = nil end
		self:_scheduleRefresh(player)
		return "GUEST", 0
	end
	return self:_rankName(cached.level), cached.level
end

function Service:GetLevel(player: Player): number
	local _, level = self:GetRank(player)
	return level
end

function Service:IsGroupMember(player: Player): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then return false end
	if (RunService:IsStudio() and self.studioStaff) or self.staffUserIds[player.UserId] == true then return true end
	local cached = self.cache[player.UserId]
	if not cached or cached.expiresAt <= os.clock() then
		if cached then self.cache[player.UserId] = nil end
		self:_scheduleRefresh(player)
		return false
	end
	return typeof(cached.groupRank) == "number" and cached.groupRank > 0
end

function Service:_levelForRank(rank: number): number
	local t = self.thresholds
	if rank >= t.Owner then return 4 end
	if rank >= t.CoOwner then return 3 end
	if rank >= t.Admin then return 2 end
	if rank >= t.Moderator then return 1 end
	return 0
end

function Service:Refresh(player: Player): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false
	end
	local userId = player.UserId
	local existingCache = self.cache[userId]
	if existingCache and existingCache.expiresAt > os.clock() then return true end
	if self.refreshInFlight[userId] then
		while self.refreshInFlight[userId] and player.Parent == Players do task.wait(0.05) end
		local refreshed = self.cache[userId]
		return player.Parent == Players and refreshed ~= nil and refreshed.expiresAt > os.clock()
	end
	local retryAt = self.retryAfter[userId]
	if retryAt and retryAt > os.clock() then return false end

	self.refreshInFlight[userId] = true
	self.refreshes += 1
	local level: number? = nil
	local groupRank: number? = nil
	local lookupError: any = nil

	if (RunService:IsStudio() and self.studioStaff) or self.staffUserIds[userId] == true then
		level = 4
		groupRank = if self.staffUserIds[userId] == true then 0 else 255
	else
		local ok, rank = pcall(function()
			return player:GetRankInGroup(self.groupId)
		end)
		if ok and typeof(rank) == "number" and rank == rank
			and rank >= 0 and rank <= 255 and rank % 1 == 0 then
			groupRank = rank
			level = self:_levelForRank(rank)
		else
			lookupError = if ok then "Invalid group rank response." else rank
		end
	end

	self.refreshInFlight[userId] = nil
	if player.Parent ~= Players then
		self.cache[userId] = nil
		self.retryAfter[userId] = nil
		return false
	end
	if level == nil then
		self.cache[userId] = nil
		self.retryAfter[userId] = os.clock() + RETRY_SECONDS
		self.refreshFailures += 1
		self.lastError = string.sub(tostring(lookupError or "Group rank lookup failed."), 1, 180)
		warn("[ClubMusic][Authorization] Group-rank refresh failed; protected actions remain denied.")
		return false
	end

	local now = os.clock()
	self.cache[userId] = {
		level = level,
		groupRank = groupRank,
		refreshedAt = now,
		expiresAt = now + math.random(CACHE_MIN_SECONDS, CACHE_MAX_SECONDS),
	}
	self.retryAfter[userId] = nil
	self.lastError = nil
	return true
end

function Service:_scheduleRefresh(player: Player)
	local userId = player.UserId
	if self.refreshInFlight[userId] then return end
	local retryAt = self.retryAfter[userId]
	if retryAt and retryAt > os.clock() then return end
	task.spawn(function()
		self:Refresh(player)
	end)
end

function Service:Start(): boolean
	if self.started then return true end
	self.started = true
	table.insert(self.connections, Players.PlayerAdded:Connect(function(player)
		self:_scheduleRefresh(player)
	end))
	table.insert(self.connections, Players.PlayerRemoving:Connect(function(player)
		self.cache[player.UserId] = nil
		self.refreshInFlight[player.UserId] = nil
		self.retryAfter[player.UserId] = nil
		local prefix = tostring(player.UserId) .. ":"
		for key in pairs(self.denials) do
			if string.sub(key, 1, #prefix) == prefix then self.denials[key] = nil end
		end
	end))
	for _, player in ipairs(Players:GetPlayers()) do
		self:_scheduleRefresh(player)
	end
	return true
end

function Service:_recordDenied(userId: number, permission: string)
	local now = os.clock()
	local key = tostring(userId) .. ":" .. permission
	local entry = self.denials[key]
	if not entry then
		local count, oldestKey, oldestAt = 0, nil, math.huge
		for existingKey, value in pairs(self.denials) do
			count += 1
			if value.updated < oldestAt then oldestAt = value.updated; oldestKey = existingKey end
		end
		if count >= MAX_DENIAL_KEYS and oldestKey then self.denials[oldestKey] = nil end
		entry = {count = 0, windowStart = now, updated = now, reportedAt = 0}
		self.denials[key] = entry
	end
	if now - entry.windowStart > 60 then
		entry.count = 0
		entry.windowStart = now
	end
	entry.count += 1
	entry.updated = now
	self.deniedActions += 1
	if entry.count >= 3 and now - entry.reportedAt >= 60 then
		entry.reportedAt = now
		if type(self.onDenied) == "function" then
			pcall(self.onDenied, userId, permission, entry.count)
		end
	end
end

function Service:SetOnDenied(callback: any)
	self.onDenied = if type(callback) == "function" then callback else nil
end

function Service:Check(actorUserId: any, permission: any): (boolean, string?)
	self.checks += 1
	if not validUserId(actorUserId) or typeof(permission) ~= "string"
		or not PERMISSION_LEVELS[permission] then
		self.denied += 1
		return false, "Invalid actor or permission."
	end

	local userId = math.floor(actorUserId)
	local player = Players:GetPlayerByUserId(userId)
	if not player or player.Parent ~= Players then
		self.denied += 1
		self:_recordDenied(userId, permission)
		return false, "A live player is required."
	end

	if RunService:IsStudio() and self.studioStaff then
		self.allowed += 1
		return true
	end

	local cached = self.cache[userId]
	if not cached or cached.expiresAt <= os.clock() then
		if cached then self.cache[userId] = nil end
		self:_scheduleRefresh(player)
		self.denied += 1
		self:_recordDenied(userId, permission)
		return false, "Authorization data is unavailable; retry shortly."
	end

	-- DJ rank is a narrowly scoped booth entitlement, not general staff.
	-- Keep GlobalDJ available to rank 100+ without elevating that player to
	-- Moderator or granting staff-only controller actions.
	local allowed = if permission == "GlobalDJ"
		then (typeof(cached.groupRank) == "number" and cached.groupRank >= self.thresholds.GroupDJ)
			or cached.level >= 1
		else cached.level >= PERMISSION_LEVELS[permission]
	if not allowed then
		self.denied += 1
		self:_recordDenied(userId, permission)
		return false, "Permission denied."
	end

	self.allowed += 1
	return true
end

function Service:GetStatus(): {[string]: any}
	local cacheEntries = 0
	for _ in pairs(self.cache) do cacheEntries += 1 end
	return {
		state = if self.started then "Ready" else "Stopped",
		started = self.started,
		authority = "SecurityCore",
		groupId = self.groupId,
		permissionLevels = table.clone(PERMISSION_LEVELS),
		checks = self.checks,
		allowed = self.allowed,
		denied = self.denied,
		deniedActions = self.deniedActions,
		refreshes = self.refreshes,
		refreshFailures = self.refreshFailures,
		cacheEntries = cacheEntries,
		cacheMinSeconds = CACHE_MIN_SECONDS,
		cacheMaxSeconds = CACHE_MAX_SECONDS,
		lastError = self.lastError,
		default = "Deny",
	}
end

function Service:Stop()
	for _, connection in ipairs(self.connections) do
		pcall(function() connection:Disconnect() end)
	end
	table.clear(self.connections)
	self.started = false
	table.clear(self.cache)
	table.clear(self.refreshInFlight)
	table.clear(self.retryAfter)
end

function Service.GetShared(dependencies: {[string]: any}?): any
	if not sharedInstance then
		sharedInstance = Service.new(dependencies)
		sharedInstance:Start()
	elseif typeof(dependencies) == "table" then
		sharedInstance:Configure(dependencies)
		if type(dependencies.onDenied) == "function" then sharedInstance:SetOnDenied(dependencies.onDenied) end
	end
	return sharedInstance
end

return Service
