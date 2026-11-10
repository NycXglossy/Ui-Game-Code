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
	info: AssetInfo,
	expiresAt: number,
	lastUsed: number,
}

local MusicValidationService = {}
MusicValidationService.__index = MusicValidationService

function MusicValidationService.new(config: any, metadataProvider: MetadataProvider)
	assert(type(config) == "table", "MusicValidationService requires a configuration table")
	assert(type(metadataProvider) == "function", "MusicValidationService requires an injected metadata provider")

	local ttl = tonumber(config.CacheTTLSeconds) or 300
	local maxEntries = tonumber(config.MaxCacheEntries) or 128
	assert(ttl >= 1 and ttl <= 3600, "CacheTTLSeconds must be between 1 and 3600")
	assert(maxEntries >= 1 and maxEntries <= 512 and maxEntries % 1 == 0, "MaxCacheEntries must be an integer between 1 and 512")

	local self = setmetatable({}, MusicValidationService)
	self.cacheTTLSeconds = ttl
	self.maxCacheEntries = maxEntries
	self.metadataProvider = metadataProvider
	self.cache = {} :: {[number]: CacheEntry}
	self.accessSequence = 0
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

function MusicValidationService:GetAudioAssetInfo(assetId: number): (boolean, AssetInfo | string, boolean)
	if type(assetId) ~= "number" or assetId ~= assetId or assetId % 1 ~= 0
		or assetId <= 0 or assetId > 9007199254740991 then
		return false, "Invalid audio asset ID.", false
	end

	local now = os.clock()
	local cached = self.cache[assetId]
	if cached and cached.expiresAt > now then
		self.accessSequence += 1
		cached.lastUsed = self.accessSequence
		return true, cached.info, true
	end
	if cached then self.cache[assetId] = nil end

	local providerOk, rawInfo = pcall(self.metadataProvider, assetId)
	if not providerOk then
		return false, "Audio asset metadata is temporarily unavailable.", false
	end

	local info = normalizeAssetInfo(rawInfo)
	if not info then
		return false, "Audio asset metadata is invalid or unavailable.", false
	end

	self.accessSequence += 1
	if self.cache[assetId] == nil then
		local count = 0
		local oldestId: number? = nil
		local oldestUse = math.huge
		for cachedId, entry in pairs(self.cache) do
			count += 1
			if entry.lastUsed < oldestUse then
				oldestUse = entry.lastUsed
				oldestId = cachedId
			end
		end
		if count >= self.maxCacheEntries and oldestId ~= nil then
			self.cache[oldestId] = nil
		end
	end

	self.cache[assetId] = {
		info = info,
		expiresAt = now + self.cacheTTLSeconds,
		lastUsed = self.accessSequence,
	}
	return true, info, false
end

function MusicValidationService:ClearCache()
	table.clear(self.cache)
end

function MusicValidationService:GetCacheStats(): { total: number, max: number }
	local now = os.clock()
	local total = 0
	for assetId, entry in pairs(self.cache) do
		if entry.expiresAt <= now then
			self.cache[assetId] = nil
		else
			total += 1
		end
	end
	return { total = total, max = self.maxCacheEntries }
end

return MusicValidationService
