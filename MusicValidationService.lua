--!strict
-- Bounded metadata cache for ClubMusic's existing server-side audio inspection.
-- This module does not own player permissions, cooldowns, spam limits, or audio playback.
-- The controller remains responsible for loading each Sound and verifying playability.

export type AssetInfo = {
	AssetTypeId: number?,
	Name: string?,
	Creator: { Name: string? }?,
}

export type MetadataProvider = (assetId: number) -> any

type CacheEntry = {
	valid: boolean,
	info: AssetInfo?,
	error: string?,
	expiresAt: number,
	generation: number,
}

type CacheQueueItem = {
	assetId: number,
	generation: number,
}

local MusicValidationService = {}
MusicValidationService.__index = MusicValidationService

function MusicValidationService.new(config: any, metadataProvider: MetadataProvider)
	assert(type(config) == "table", "MusicValidationService requires a configuration table")
	assert(type(metadataProvider) == "function", "MusicValidationService requires an injected metadata provider")

	local ttl = tonumber(config.CacheTTLSeconds) or 300
	local failureTtl = tonumber(config.FailureCacheTTLSeconds) or 5
	local maxEntries = tonumber(config.MaxCacheEntries) or 128
	assert(ttl >= 1 and ttl <= 3600, "CacheTTLSeconds must be between 1 and 3600")
	assert(failureTtl >= 1 and failureTtl <= 30, "FailureCacheTTLSeconds must be between 1 and 30")
	assert(maxEntries >= 1 and maxEntries <= 512 and maxEntries % 1 == 0, "MaxCacheEntries must be an integer between 1 and 512")

	local self = setmetatable({}, MusicValidationService)
	self.cacheTTLSeconds = ttl
	self.failureCacheTTLSeconds = failureTtl
	self.maxCacheEntries = maxEntries
	self.metadataProvider = metadataProvider
	self.cache = {} :: {[number]: CacheEntry}
	self.cacheOrder = {
		items = {} :: {[number]: CacheQueueItem},
		head = 1,
		count = 0,
	}
	self.cacheSequence = 0
	return self
end

local function normalizeAssetInfo(rawInfo: any): AssetInfo?
	if typeof(rawInfo) ~= "table" then return nil end

	local assetTypeId = tonumber(rawInfo.AssetTypeId)
	if not assetTypeId or assetTypeId % 1 ~= 0 then return nil end

	local creatorName = "Unknown"
	if typeof(rawInfo.Creator) == "table" and type(rawInfo.Creator.Name) == "string" then
		creatorName = string.sub(rawInfo.Creator.Name, 1, 80)
	end

	local name = if type(rawInfo.Name) == "string" then string.sub(rawInfo.Name, 1, 120) else "Untitled audio"
	return {
		AssetTypeId = assetTypeId,
		Name = name,
		Creator = { Name = creatorName },
	}
end

-- Circular FIFO insertion is O(1). A generation token prevents an old queue
-- slot from evicting a newer entry for the same asset after expiry/reinsertion.
local function setCache(self: any, assetId: number, entry: CacheEntry)
	self.cacheSequence += 1
	local existing = self.cache[assetId]
	if existing then
		entry.generation = existing.generation
	else
		local order = self.cacheOrder
		local nextItem: CacheQueueItem = {
			assetId = assetId,
			generation = self.cacheSequence,
		}
		if order.count >= self.maxCacheEntries then
			local oldest = order.items[order.head]
			order.items[order.head] = nextItem
			order.head = (order.head % self.maxCacheEntries) + 1
			if oldest then
				local oldEntry = self.cache[oldest.assetId]
				if oldEntry and oldEntry.generation == oldest.generation then
					self.cache[oldest.assetId] = nil
				end
			end
		else
			local tail = ((order.head + order.count - 1) % self.maxCacheEntries) + 1
			order.items[tail] = nextItem
			order.count += 1
		end
		entry.generation = self.cacheSequence
	end
	self.cache[assetId] = entry
end

function MusicValidationService:GetAudioAssetInfo(assetId: number): (boolean, AssetInfo | string, boolean)
	if type(assetId) ~= "number" or assetId ~= assetId or assetId % 1 ~= 0
		or assetId <= 0 or assetId > 9007199254740991 then
		return false, "Invalid audio asset ID.", false
	end

	local now = os.clock()
	local cached = self.cache[assetId]
	if cached then
		if cached.expiresAt > now then
			return cached.valid, if cached.valid then cached.info :: AssetInfo else cached.error :: string, true
		end
		self.cache[assetId] = nil
	end

	local providerOk, rawInfo = pcall(self.metadataProvider, assetId)
	if not providerOk then
		local message = "Audio asset metadata is temporarily unavailable."
		setCache(self, assetId, {
			valid = false,
			error = message,
			expiresAt = now + self.failureCacheTTLSeconds,
			generation = 0,
		})
		return false, message, false
	end

	local info = normalizeAssetInfo(rawInfo)
	if not info then
		local message = "Audio asset metadata is invalid or unavailable."
		setCache(self, assetId, {
			valid = false,
			error = message,
			expiresAt = now + self.failureCacheTTLSeconds,
			generation = 0,
		})
		return false, message, false
	end

	setCache(self, assetId, {
		valid = true,
		info = info,
		expiresAt = now + self.cacheTTLSeconds,
		generation = 0,
	})
	return true, info, false
end

-- Marketplace metadata alone never proves experience permission or playability.
-- The controller performs the separate AudioPlayer preload before accepting a track.
function MusicValidationService:NormalizeAudioMetadata(assetId: number, info: any, duration: number): {[string]: any}?
	if type(assetId) ~= "number" or assetId ~= assetId or assetId % 1 ~= 0
		or assetId <= 0 or assetId > 9007199254740991 or typeof(info) ~= "table" then
		return nil
	end
	if type(duration) ~= "number" or duration ~= duration or duration % 1 ~= 0
		or duration < 1 or duration > 3600 then
		return nil
	end

	local rawCreator = info.Creator
	local creator = if typeof(rawCreator) == "table" then rawCreator.Name else nil
	if type(creator) ~= "string" or creator == "" then creator = "Unknown" end
	local title = if type(info.Name) == "string" then info.Name else "Untitled audio"

	return {
		assetId = assetId,
		soundId = "rbxassetid://" .. tostring(assetId),
		title = string.sub(title, 1, 60),
		artist = string.sub(creator, 1, 40),
		genre = "Creator Hub Audio",
		duration = duration,
		metadataSource = "MarketplaceService",
	}
end

function MusicValidationService:ClearCache()
	table.clear(self.cache)
	self.cacheOrder = {
		items = {} :: {[number]: CacheQueueItem},
		head = 1,
		count = 0,
	}
	self.cacheSequence = 0
end

function MusicValidationService:GetCacheStats(): { total: number, max: number, valid: number, invalid: number }
	local now = os.clock()
	local total = 0
	local valid = 0
	local invalid = 0
	for assetId, entry in pairs(self.cache) do
		if entry.expiresAt <= now then
			self.cache[assetId] = nil
		else
			total += 1
			if entry.valid then valid += 1 else invalid += 1 end
		end
	end
	return { total = total, max = self.maxCacheEntries, valid = valid, invalid = invalid }
end

return MusicValidationService
