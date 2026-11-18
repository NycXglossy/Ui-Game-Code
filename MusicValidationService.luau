local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local MusicValidationService = {}
MusicValidationService.__index = MusicValidationService

function MusicValidationService.new(config, assetInfoProvider)
	local self = setmetatable({}, MusicValidationService)
	self.config = config or {}
	self.config.MUSIC_ID_CACHE_DURATION = self.config.MUSIC_ID_CACHE_DURATION or 3600
	self.cacheTTLSeconds = math.clamp(tonumber(self.config.CacheTTLSeconds) or 300, 1, 3600)
	self.failureCacheTTLSeconds = math.clamp(tonumber(self.config.FailureCacheTTLSeconds) or 5, 1, 30)
	self.maxCacheEntries = math.clamp(math.floor(tonumber(self.config.MaxCacheEntries) or 128), 16, 1024)
	self.assetInfoProvider = if typeof(assetInfoProvider) == "function" then assetInfoProvider else function(assetId)
		return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset)
	end
	self.musicIdCache = {}
	self.audioAssetInfoCache = {}
	self.musicIdCacheOrder = {items = {}, head = 1, tail = 0, count = 0}
	self.audioAssetInfoCacheOrder = {items = {}, head = 1, tail = 0, count = 0}
	self.playerCooldowns = {}
	self.playerLastAction = {}
	return self
end

-- Bounded FIFO cache insertion is O(1); cache misses never scan the full cache
-- to find an eviction candidate. Existing keys are refreshed in place.
local function setBoundedCache(cache, order, key, value, maxEntries)
	if cache[key] == nil then
		if order.count >= maxEntries then
			while order.head <= order.tail do
				local oldestKey = order.items[order.head]
				order.items[order.head] = nil
				order.head += 1
				if oldestKey ~= nil and cache[oldestKey] ~= nil then
					cache[oldestKey] = nil
					order.count = math.max(0, order.count - 1)
					break
				end
			end
		end
		order.tail += 1
		order.items[order.tail] = key
		order.count += 1
	end
	cache[key] = value
end

-- Metadata cache only. The controller still performs its separate preload and
-- experience-permission check; a cache hit never proves that audio is playable.
function MusicValidationService:GetAudioAssetInfo(assetId)
	local numericId = tonumber(assetId)
	if not numericId or numericId < 1 or numericId % 1 ~= 0 then
		return false, "Invalid audio asset ID."
	end
	local key = tostring(numericId)
	local now = os.clock()
	local cached = self.audioAssetInfoCache[key]
	if cached then
		local ttl = if cached.valid then self.cacheTTLSeconds else self.failureCacheTTLSeconds
		if now - cached.timestamp < ttl then
			return cached.valid, cached.data or cached.error
		end
	end
	local ok, info = pcall(self.assetInfoProvider, numericId)
	if not ok or typeof(info) ~= "table" then
		local message = "Audio asset metadata is temporarily unavailable."
		setBoundedCache(self.audioAssetInfoCache, self.audioAssetInfoCacheOrder, key, {
			valid = false, error = message, timestamp = now,
		}, self.maxCacheEntries)
		return false, message
	end
	setBoundedCache(self.audioAssetInfoCache, self.audioAssetInfoCacheOrder, key, {
		valid = true, data = info, timestamp = now,
	}, self.maxCacheEntries)
	return true, info
end

-- Return one bounded metadata shape for every validated audio asset.
-- Duration remains supplied by the controller's actual preload, never Marketplace metadata.
function MusicValidationService:NormalizeAudioMetadata(assetId, info, duration)
	local numericId = tonumber(assetId)
	if not numericId or numericId < 1 or numericId % 1 ~= 0 or typeof(info) ~= "table" then
		return nil
	end
	local rawCreator = info.Creator
	local creator = if typeof(rawCreator) == "table" then rawCreator.Name else nil
	local title = if typeof(info.Name) == "string" then info.Name else "Untitled audio"
	if typeof(creator) ~= "string" or creator == "" then creator = "Unknown" end
	if typeof(duration) ~= "number" or duration ~= duration or duration % 1 ~= 0 or duration < 1 or duration > 3600 then
		return nil
	end
	return {
		assetId = numericId,
		soundId = "rbxassetid://" .. tostring(numericId),
		title = string.sub(title, 1, 60),
		artist = string.sub(creator, 1, 40),
		genre = "Creator Hub Audio",
		duration = duration,
		metadataSource = "MarketplaceService",
	}
end

-- ====================================
-- MUSIC ID VALIDATION
-- ====================================

function MusicValidationService:ValidateMusicId(musicId)
	if type(musicId) ~= "string" then
		return false, nil, "Invalid type"
	end

	if #musicId < 1 or #musicId > self.config.MAX_MUSIC_ID_LENGTH then
		return false, nil, "Invalid length"
	end

	if not musicId:match("^%d+$") then
		return false, nil, "Invalid format"
	end

	-- Check cache first
	local cached = self.musicIdCache[musicId]
	if cached and (tick() - cached.timestamp) < self.config.MUSIC_ID_CACHE_DURATION then
		if cached.valid then
			return true, cached.data, "Cached"
		else
			return false, nil, "Cached invalid"
		end
	end

	-- Validate with MarketplaceService
	local success, info = pcall(function()
		return MarketplaceService:GetProductInfo(tonumber(musicId))
	end)

	if success and info and info.AssetTypeId == 3 then
		local data = {
			id = musicId,
			judul = info.Name:sub(1, 100),
			sampul = "rbxthumb://type=Asset&id=" .. musicId .. "&w=150&h=150",
			Duration = 0
		}

		setBoundedCache(self.musicIdCache, self.musicIdCacheOrder, musicId, {
			valid = true,
			data = data,
			timestamp = tick()
		}, self.maxCacheEntries)

		return true, data, "Valid"
	else
		setBoundedCache(self.musicIdCache, self.musicIdCacheOrder, musicId, {
			valid = false,
			data = nil,
			timestamp = tick()
		}, self.maxCacheEntries)

		return false, nil, "Invalid asset or not an audio"
	end
end

-- ====================================
-- SPAM PROTECTION
-- ====================================

function MusicValidationService:CheckSpamProtection(player)
	local userId = player.UserId
	local currentTime = tick()

	if not self.playerLastAction[userId] then
		self.playerLastAction[userId] = {}
	end

	local actions = self.playerLastAction[userId]
	local validActions = {}

	-- Remove old actions outside time window
	for _, timestamp in ipairs(actions) do
		if currentTime - timestamp < self.config.SPAM_PROTECTION.TIME_WINDOW then
			table.insert(validActions, timestamp)
		end
	end

	self.playerLastAction[userId] = validActions

	-- Check if player is spamming
	if #validActions >= self.config.SPAM_PROTECTION.ACTIONS_LIMIT then
		return false, "Tolong jangan spam! Tunggu beberapa detik."
	end

	table.insert(self.playerLastAction[userId], currentTime)
	return true, nil
end

-- ====================================
-- COOLDOWN SYSTEM
-- ====================================

function MusicValidationService:CheckCooldown(player, roleCooldowns)
	local userId = player.UserId
	local RoleSystem = require(game:GetService("ServerStorage").Modules.RoleSystem)
	local role = RoleSystem:GetPlayerRole(player)
	local cooldown = roleCooldowns[role] or 300

	if cooldown == 0 then
		return true, nil
	end

	local lastTime = self.playerCooldowns[userId]
	if lastTime then
		local elapsed = tick() - lastTime
		if elapsed < cooldown then
			local remaining = math.ceil(cooldown - elapsed)
			local minutes = math.floor(remaining / 60)
			local seconds = remaining % 60
			local timeStr = minutes > 0 and string.format("%dm %ds", minutes, seconds) or string.format("%ds", seconds)

			return false, string.format("Cooldown aktif! Tunggu %s lagi.", timeStr)
		end
	end

	return true, nil
end

function MusicValidationService:UpdateCooldown(player)
	self.playerCooldowns[player.UserId] = tick()
end

-- ====================================
-- PLAYER VALIDATION
-- ====================================

function MusicValidationService:ValidatePlayer(player)
	return player and player:IsDescendantOf(Players)
end

-- ====================================
-- CLEANUP
-- ====================================

function MusicValidationService:CleanupPlayer(userId)
	self.playerCooldowns[userId] = nil
	self.playerLastAction[userId] = nil
end

-- ====================================
-- CACHE MANAGEMENT
-- ====================================

function MusicValidationService:ClearCache()
	self.musicIdCache = {}
	self.audioAssetInfoCache = {}
	self.musicIdCacheOrder = {items = {}, head = 1, tail = 0, count = 0}
	self.audioAssetInfoCacheOrder = {items = {}, head = 1, tail = 0, count = 0}
end

function MusicValidationService:GetCacheStats()
	local cacheCount = 0
	local validCount = 0

	for _, cached in pairs(self.musicIdCache) do
		cacheCount = cacheCount + 1
		if cached.valid then
			validCount = validCount + 1
		end
	end

	return {
		total = cacheCount,
		valid = validCount,
		invalid = cacheCount - validCount
	}
end

return MusicValidationService