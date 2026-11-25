--!strict
-- Consolidated ClubMusic server core.
-- Keeps catalog persistence, metadata validation, and controller-owned queue operations
-- as isolated interfaces within one ModuleScript. No playback or permission authority.

--!strict
-- MusicCatalogService
-- Place as ModuleScript: ServerStorage/MusicCatalogService
--
-- Server-owned metadata catalog with a bounded DataStore-backed custom-track overlay.
-- This module does not own playback, queueing, or permissions. The UI_Server_Controller
-- remains authoritative for every request and playback decision.

local MusicCatalogService = {}

export type Track = {
	id: string,
	genreId: string,
	title: string,
	artist: string,
	duration: number,
	genre: string,
	assetId: number?,
	soundId: string?,
	bpm: number?,
	artworkAssetId: number?,
	placeholder: boolean?,
}

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local catalogStore = DataStoreService:GetDataStore("ClubMusic_Catalog_v1")
local CATALOG_KEY = "custom_tracks"
local MAX_CUSTOM_TRACKS = 200
local customTracks: {[string]: Track} = {}
local storageInitialized = false
local storageInitializing = false
local storagePersistent = false
local storageReady = false
-- Shared operation lock: reads that replace the in-memory overlay must not race writes.
local storageWriteBusy = false

type Genre = {
	id: string,
	name: string,
}

local GENRES: {Genre} = {
	-- Retain established genre keys so previously saved custom-track records
	-- remain valid after the built-in catalog migration.
	{id = "hiphop", name = "Hip Hop / Rap"},
	{id = "rnb", name = "R&B / Soul"},
	{id = "rock", name = "Rock"},
	{id = "kpop", name = "K-Pop"},
	{id = "latin", name = "Latin Music"},
	{id = "edm", name = "EDM"},
	{id = "country", name = "Country"},
	{id = "pop", name = "Pop"},
	{id = "exclusive", name = "Club Exclusives"},
	{id = "rockstar", name = "Rockstar Music"},
	{id = "other", name = "Other"},
}

-- Keep IDs stable: player favorites, queue entries, and the existing UI refer
-- to these IDs. Add approved songs here; never accept client-supplied metadata.
local CATALOG: {Track} = {
	{id="temp-hiphop",genreId="hiphop",title="Coming Soon — Hip Hop / Rap",artist="Temporary placeholder • audio pending",duration=1,genre="Hip Hop / Rap",placeholder=true},
	{id="temp-rnb",genreId="rnb",title="Coming Soon — R&B / Soul",artist="Temporary placeholder • audio pending",duration=1,genre="R&B / Soul",placeholder=true},
	{id="temp-rock",genreId="rock",title="Coming Soon — Rock",artist="Temporary placeholder • audio pending",duration=1,genre="Rock",placeholder=true},
	{id="temp-kpop",genreId="kpop",title="Coming Soon — K-Pop",artist="Temporary placeholder • audio pending",duration=1,genre="K-Pop",placeholder=true},
	{id="temp-latin",genreId="latin",title="Coming Soon — Latin Music",artist="Temporary placeholder • audio pending",duration=1,genre="Latin Music",placeholder=true},
	{id="temp-edm",genreId="edm",title="Coming Soon — EDM",artist="Temporary placeholder • audio pending",duration=1,genre="EDM",placeholder=true},
	{id="temp-country",genreId="country",title="Coming Soon — Country",artist="Temporary placeholder • audio pending",duration=1,genre="Country",placeholder=true},
	{id="temp-pop",genreId="pop",title="Coming Soon — Pop",artist="Temporary placeholder • audio pending",duration=1,genre="Pop",placeholder=true},
	{id="custom-100919684616729",genreId="exclusive",title="CROWN OF THE NIGHT",artist="DJ Doom",duration=415,genre="Club Exclusives",assetId=100919684616729,soundId="rbxassetid://100919684616729"},
	{id="custom-99973341792058",genreId="exclusive",title="Midnight Lucid",artist="DJ Doom",duration=252,genre="Club Exclusives",assetId=99973341792058,soundId="rbxassetid://99973341792058"},
	{id="custom-137104933242988",genreId="exclusive",title="Empire of Stone",artist="DJ Doom",duration=248,genre="Club Exclusives",assetId=137104933242988,soundId="rbxassetid://137104933242988"},
	{id="custom-84266261446965",genreId="exclusive",title="Anvil of Ruin",artist="DJ Doom",duration=190,genre="Club Exclusives",assetId=84266261446965,soundId="rbxassetid://84266261446965"},
	{id="custom-85420661204078",genreId="exclusive",title="Code in the Smoke",artist="DJ Doom",duration=184,genre="Club Exclusives",assetId=85420661204078,soundId="rbxassetid://85420661204078",bpm=136},
	{id="custom-134987433423089",genreId="exclusive",title="Rich Lifestyle",artist="DJ Doom",duration=212,genre="Club Exclusives",assetId=134987433423089,soundId="rbxassetid://134987433423089"},
	{id="custom-92952858514774",genreId="exclusive",title="Metallic Chaos Within Magic Theory",artist="DJ Doom",duration=333,genre="Club Exclusives",assetId=92952858514774,soundId="rbxassetid://92952858514774"},
	{id="custom-117388170134707",genreId="exclusive",title="Steel Collision",artist="DJ Doom",duration=184,genre="Club Exclusives",assetId=117388170134707,soundId="rbxassetid://117388170134707"},
	{id="custom-86468432953052",genreId="exclusive",title="Fallen Star Blues",artist="DJ Doom",duration=230,genre="Club Exclusives",assetId=86468432953052,soundId="rbxassetid://86468432953052"},
	{id="custom-126526272193872",genreId="exclusive",title="Winter Between Us",artist="DJ Doom",duration=214,genre="Club Exclusives",assetId=126526272193872,soundId="rbxassetid://126526272193872"},
	{id="custom-96399574470852",genreId="exclusive",title="Terminal Frequency",artist="DJ Doom",duration=200,genre="Club Exclusives",assetId=96399574470852,soundId="rbxassetid://96399574470852"},
	{id="custom-113786540921203",genreId="exclusive",title="Static Defiance",artist="DJ Doom",duration=230,genre="Club Exclusives",assetId=113786540921203,soundId="rbxassetid://113786540921203"},
	{id="custom-115697666216583",genreId="exclusive",title="Respawn Anthem",artist="DJ Doom",duration=248,genre="Club Exclusives",assetId=115697666216583,soundId="rbxassetid://115697666216583",bpm=165},
	{id="temp-rockstar",genreId="rockstar",title="Coming Soon — Rockstar Music",artist="Temporary placeholder • audio pending",duration=1,genre="Rockstar Music",placeholder=true},
	{id="temp-other",genreId="other",title="Coming Soon — Other",artist="Temporary placeholder • audio pending",duration=1,genre="Other",placeholder=true},
}

local TRACK_BY_ID: {[string]: Track} = {}
local VALID_GENRES: {[string]: boolean} = {}
for _, genre in ipairs(GENRES) do
	VALID_GENRES[genre.id] = true
end

for _, track in ipairs(CATALOG) do
	assert(type(track.id) == "string" and string.match(track.id, "^[%w%-_]+$"),
		"MusicCatalogService: invalid catalog track ID")
	assert(TRACK_BY_ID[track.id] == nil, "MusicCatalogService: duplicate track ID " .. track.id)
	assert(VALID_GENRES[track.genreId] == true, "MusicCatalogService: unknown genre for " .. track.id)
	assert(type(track.title) == "string" and #track.title > 0 and #track.title <= 100,
		"MusicCatalogService: invalid title for " .. track.id)
	assert(type(track.artist) == "string" and #track.artist <= 100,
		"MusicCatalogService: invalid artist for " .. track.id)
	assert(type(track.duration) == "number" and track.duration > 0 and track.duration <= 3600,
		"MusicCatalogService: invalid duration for " .. track.id)
	TRACK_BY_ID[track.id] = track
end

local function copyTrack(track: Track): Track
	return {
		id = track.id,
		genreId = track.genreId,
		title = track.title,
		artist = track.artist,
		duration = track.duration,
		genre = track.genre,
		assetId = track.assetId,
		soundId = track.soundId,
		bpm = track.bpm,
		artworkAssetId = track.artworkAssetId,
		placeholder = track.placeholder,
	}
end

local function hasValidStoredCatalogShape(stored: any): boolean
	if stored == nil then return true end
	if typeof(stored) ~= "table" or typeof(stored.tracks) ~= "table" then
		return false
	end
	-- Accept legacy unversioned records and the two persisted formats already
	-- used by this service. Refuse unknown future versions rather than rewriting them.
	if stored.schemaVersion ~= nil and stored.schemaVersion ~= 1 and stored.schemaVersion ~= 2 then
		return false
	end

	-- DataStore tracks must be a bounded, dense 1-based array. ipairs alone
	-- would silently ignore dictionary keys and holes, then replace good data.
	local entryCount = 0
	local highestIndex = 0
	for key in pairs(stored.tracks) do
		if typeof(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > MAX_CUSTOM_TRACKS then
			return false
		end
		entryCount += 1
		if key > highestIndex then highestIndex = key end
	end
	return entryCount == highestIndex
end

local function sanitizeStoredTrack(value: any): Track?
	if typeof(value) ~= "table" then return nil end
	local assetId = value.assetId
	if typeof(assetId) ~= "number" or assetId % 1 ~= 0 or assetId <= 0 or assetId > 9007199254740991 then return nil end
	local id = "custom-" .. tostring(assetId)
	local genreId = value.genreId
	if typeof(genreId) ~= "string" or not VALID_GENRES[genreId] then return nil end
	local title = value.title
	local artist = value.artist
	local duration = value.duration
	local genre = value.genre
	local artworkAssetId = value.artworkAssetId
	if artworkAssetId ~= nil and (typeof(artworkAssetId) ~= "number" or artworkAssetId ~= artworkAssetId or artworkAssetId % 1 ~= 0 or artworkAssetId <= 0 or artworkAssetId > 9007199254740991) then return nil end
	if typeof(title) ~= "string" or #title < 1 or #title > 100 then return nil end
	if typeof(artist) ~= "string" or #artist < 1 or #artist > 100 then return nil end
	if typeof(duration) ~= "number" or duration ~= duration or duration % 1 ~= 0 or duration < 1 or duration > 3600 then return nil end
	if typeof(genre) ~= "string" or #genre < 1 or #genre > 40 then return nil end
	return {id=id, genreId=genreId, title=title, artist=artist, duration=duration, genre=genre,
		assetId=assetId, soundId="rbxassetid://" .. tostring(assetId), artworkAssetId=artworkAssetId}
end

local function hasValidStoredCatalogRecords(stored: any): boolean
	if stored == nil then return true end
	if not hasValidStoredCatalogShape(stored) then return false end
	local seenIds: {[string]: boolean} = {}
	for _, rawTrack in ipairs(stored.tracks) do
		local clean = sanitizeStoredTrack(rawTrack)
		if not clean or TRACK_BY_ID[clean.id] or seenIds[clean.id] then
			return false
		end
		seenIds[clean.id] = true
	end
	return true
end

function MusicCatalogService:Initialize(studioUseDataStore: boolean?, budgetCallback: (() -> boolean)?): boolean
	if storageInitialized then return storageReady end
	if storageInitializing then return false end
	storageInitializing = true
	storagePersistent = not RunService:IsStudio() or studioUseDataStore == true
	if not storagePersistent then
		storageReady = true -- Studio session-only catalog; never pretend it persisted.
		storageInitialized = true
		storageInitializing = false
		return true
	end
	if budgetCallback then
		local budgetOk, budgetAvailable = pcall(budgetCallback)
		if not budgetOk or budgetAvailable ~= true then
			warn("[ClubMusic Catalog] Shared DataStore budget unavailable; initialization may be retried.")
			storageInitializing = false
			return false
		end
	end
	local ok, stored = pcall(function() return catalogStore:GetAsync(CATALOG_KEY) end)
	if not ok then
		warn("[ClubMusic Catalog] Could not load persisted catalog: " .. tostring(stored))
		storageInitializing = false
		return false
	end
	if not hasValidStoredCatalogRecords(stored) then
		warn("[ClubMusic Catalog] Initialization refused malformed catalog records; persisted data was not loaded.")
		storageInitializing = false
		storageReady = false
		storageInitialized = false
		return false
	end
	local loaded: {[string]: Track} = {}
	if stored ~= nil then
		for _, rawTrack in ipairs(stored.tracks) do
			local clean = sanitizeStoredTrack(rawTrack)
			if clean and not TRACK_BY_ID[clean.id] then loaded[clean.id] = clean end
		end
	end
	customTracks = loaded
	storageReady = true
	storageInitialized = true
	storageInitializing = false
	return true
end

function MusicCatalogService:IsStorageReady(): boolean
	return storageReady
end

-- Refresh the persisted custom overlay after a cross-server invalidation.
-- A failed read leaves the last known-good in-memory catalog untouched.
function MusicCatalogService:Refresh(budgetCallback: (() -> boolean)?): boolean
	if not storageReady then return false end
	if not storagePersistent then return true end
	if storageWriteBusy then return false end
	storageWriteBusy = true
	if budgetCallback then
		local budgetOk, budgetAvailable = pcall(budgetCallback)
		if not budgetOk or budgetAvailable ~= true then
			storageWriteBusy = false
			return false
		end
	end
	local ok, stored = pcall(function() return catalogStore:GetAsync(CATALOG_KEY) end)
	if not ok then
		storageWriteBusy = false
		warn("[ClubMusic Catalog] Cross-server refresh failed: " .. tostring(stored))
		return false
	end
	if not hasValidStoredCatalogRecords(stored) then
		storageWriteBusy = false
		warn("[ClubMusic Catalog] Refresh refused malformed catalog records; last-known-good cache preserved.")
		return false
	end
	local loaded: {[string]: Track} = {}
	if stored ~= nil then
		for _, rawTrack in ipairs(stored.tracks) do
			local clean = sanitizeStoredTrack(rawTrack)
			if clean and not TRACK_BY_ID[clean.id] then loaded[clean.id] = clean end
		end
	end
	customTracks = loaded
	storageWriteBusy = false
	return true
end

function MusicCatalogService:AddCustomTrack(assetId: number, title: string, artist: string, duration: number, genreId: string, artworkAssetId: number?): (boolean, string)
	if not storageReady then return false, "Catalog storage is unavailable; no changes were saved." end
	if typeof(assetId) ~= "number" or assetId % 1 ~= 0 or assetId <= 0 or assetId > 9007199254740991 then return false, "Invalid audio asset ID." end
	if typeof(title) ~= "string" or #title < 1 or #title > 100 or typeof(artist) ~= "string" or #artist < 1 or #artist > 100 then return false, "Invalid track metadata." end
	if typeof(duration) ~= "number" or duration % 1 ~= 0 or duration < 1 or duration > 3600 then return false, "Invalid track duration." end
	if typeof(genreId) ~= "string" or not VALID_GENRES[genreId] then return false, "Choose a valid catalog genre." end
	if artworkAssetId ~= nil and (typeof(artworkAssetId) ~= "number" or artworkAssetId ~= artworkAssetId or artworkAssetId % 1 ~= 0 or artworkAssetId <= 0 or artworkAssetId > 9007199254740991) then return false, "Invalid artwork image asset ID." end
	if storageWriteBusy then return false, "Catalog is busy. Try again shortly." end
	local id = "custom-" .. tostring(assetId)
	-- The persisted UpdateAsync record is authoritative in live servers. A
	-- different server may have removed this asset while our local overlay is
	-- waiting for its next invalidation/periodic refresh; do not let that stale
	-- cache prevent a legitimate re-add. Built-in catalog IDs remain reserved.
	if TRACK_BY_ID[id] then return false, "That audio is already in the catalog." end
	if not storagePersistent and customTracks[id] then
		return false, "That audio is already in the catalog."
	end
	local genreName = "Club Exclusives"
	for _, genre in ipairs(GENRES) do if genre.id == genreId then genreName = genre.name break end end
	local candidate: Track = {id=id, genreId=genreId, title=title, artist=artist, duration=duration,
		genre=genreName, assetId=assetId, soundId="rbxassetid://" .. tostring(assetId), artworkAssetId=artworkAssetId}
	if not storagePersistent then customTracks[id] = candidate; return true, "Added for this Studio session only." end
	storageWriteBusy = true
	local updatedData: any = nil
	local duplicateFound = false
	local capacityReached = false
	local invalidStoredCatalog = false
	local ok, err = pcall(function()
		updatedData = catalogStore:UpdateAsync(CATALOG_KEY, function(old)
			duplicateFound = false
			capacityReached = false
			invalidStoredCatalog = false
			if not hasValidStoredCatalogRecords(old) then
				-- Never overwrite malformed, invalid, or duplicate persisted records.
				invalidStoredCatalog = true
				return old
			end
			local list = if typeof(old) == "table" then table.clone(old.tracks) else {}
			for _, raw in ipairs(list) do
				if typeof(raw) == "table" and tonumber(raw.assetId) == assetId then
					duplicateFound = true
					return old
				end
			end
			if #list >= MAX_CUSTOM_TRACKS then
				capacityReached = true
				return old
			end
			table.insert(list, {assetId=assetId, genreId=genreId, title=title, artist=artist, duration=duration, genre=genreName, artworkAssetId=artworkAssetId})
			local output = if typeof(old) == "table" then table.clone(old) else {}
			output.schemaVersion = 2
			output.tracks = list
			return output
		end)
	end)
	storageWriteBusy = false
	if not ok then warn("[ClubMusic Catalog] Add failed: " .. tostring(err)); return false, "Catalog save failed. Try again later." end
	if invalidStoredCatalog then
		warn("[ClubMusic Catalog] Add refused because persisted catalog data has an unexpected shape.")
		return false, "Catalog data needs recovery; no addition was saved."
	end
	if duplicateFound then return false, "That audio was added by another server already. Refresh the catalog." end
	if capacityReached then return false, "The custom catalog is full (200 tracks)." end
	local persistedTrack: Track? = nil
	if hasValidStoredCatalogRecords(updatedData) and typeof(updatedData) == "table" and typeof(updatedData.tracks) == "table" then
		for _, raw in ipairs(updatedData.tracks) do
			local clean = sanitizeStoredTrack(raw)
			if clean and clean.id == id then persistedTrack = clean; break end
		end
	end
	if not persistedTrack then return false, "The catalog update could not be confirmed; refresh and retry." end
	customTracks[id] = persistedTrack
	return true, "Track saved to the shared catalog."
end

function MusicCatalogService:RemoveCustomTrack(trackId: string): (boolean, string)
	if not storageReady then return false, "Catalog storage is unavailable; no changes were saved." end
	local current = customTracks[trackId]
	if not current then return false, "Custom catalog track not found." end
	if not storagePersistent then customTracks[trackId] = nil; return true, "Removed for this Studio session only." end
	if storageWriteBusy then return false, "Catalog is busy. Try again shortly." end
	storageWriteBusy = true
	local updatedData: any = nil
	local assetId = current.assetId
	local invalidStoredCatalog = false
	local ok, err = pcall(function()
		updatedData = catalogStore:UpdateAsync(CATALOG_KEY, function(old)
			invalidStoredCatalog = false
			if not hasValidStoredCatalogRecords(old) then
				-- Never filter or rewrite malformed, invalid, or duplicate records.
				invalidStoredCatalog = true
				return old
			end
			local list = if typeof(old) == "table" then table.clone(old.tracks) else {}
			local filtered = {}
			for _, raw in ipairs(list) do
				if not (typeof(raw) == "table" and tonumber(raw.assetId) == assetId) then table.insert(filtered, raw) end
			end
			local output = if typeof(old) == "table" then table.clone(old) else {}
			output.schemaVersion = 2
			output.tracks = filtered
			return output
		end)
	end)
	storageWriteBusy = false
	if not ok then warn("[ClubMusic Catalog] Remove failed: " .. tostring(err)); return false, "Catalog save failed. Track was not removed." end
	if invalidStoredCatalog then
		warn("[ClubMusic Catalog] Remove refused because persisted catalog data has an unexpected shape.")
		return false, "Catalog data needs recovery; no removal was confirmed."
	end
	if not hasValidStoredCatalogRecords(updatedData) or typeof(updatedData) ~= "table" or typeof(updatedData.tracks) ~= "table" then
		return false, "Catalog removal could not be confirmed; no local change was applied."
	end
	for _, raw in ipairs(updatedData.tracks) do
		if typeof(raw) == "table" and tonumber(raw.assetId) == assetId then
			return false, "Catalog removal could not be confirmed; refresh and retry."
		end
	end
	customTracks[trackId] = nil
	return true, "Track removed from the shared catalog."
end

function MusicCatalogService:GetTrackById(trackId: any): Track?
	if type(trackId) ~= "string" or #trackId > 24 then return nil end
	local track = TRACK_BY_ID[trackId] or customTracks[trackId]
	return if track then copyTrack(track) else nil
end

function MusicCatalogService:GetAllTracks(): {Track}
	local result: {Track} = {}
	for _, track in ipairs(CATALOG) do
		table.insert(result, copyTrack(track))
	end
	for _, track in pairs(customTracks) do table.insert(result, copyTrack(track)) end
	table.sort(result, function(a, b)
		local left = string.lower(a.title)
		local right = string.lower(b.title)
		if left == right then return a.id < b.id end
		return left < right
	end)
	return result
end

function MusicCatalogService:GetGenres(): {Genre}
	local result: {Genre} = {}
	for _, genre in ipairs(GENRES) do
		table.insert(result, {id = genre.id, name = genre.name})
	end
	return result
end

-- Bounded server-side search. Returns detached records so callers cannot mutate
-- the canonical catalog. offset is zero-based; limit is clamped to 1..50.
function MusicCatalogService:GetCatalog(query: any, genreId: any, offset: any, limit: any)
	local cleanQuery = if type(query) == "string" then string.lower(string.sub(query, 1, 48)) else ""
	local cleanGenre = if type(genreId) == "string" then string.sub(genreId, 1, 24) else ""
	if cleanGenre ~= "" and not VALID_GENRES[cleanGenre] then
		return nil
	end

	local safeOffset = if type(offset) == "number" and offset == offset
		then math.clamp(math.floor(offset), 0, 10000) else 0
	local safeLimit = if type(limit) == "number" and limit == limit
		then math.clamp(math.floor(limit), 1, 50) else 30

	local matches: {Track} = {}
	local allTracks = self:GetAllTracks()
	for _, track in ipairs(allTracks) do
		local genreMatches = cleanGenre == "" or track.genreId == cleanGenre
		local textMatches = cleanQuery == ""
			or string.find(string.lower(track.title), cleanQuery, 1, true) ~= nil
			or string.find(string.lower(track.artist), cleanQuery, 1, true) ~= nil
			or string.find(string.lower(track.genre), cleanQuery, 1, true) ~= nil
		if genreMatches and textMatches then
			table.insert(matches, track)
		end
	end

	table.sort(matches, function(a, b)
		local left = string.lower(a.title)
		local right = string.lower(b.title)
		if left == right then return a.id < b.id end
		return left < right
	end)

	local items: {Track} = {}
	local first = safeOffset + 1
	local last = math.min(#matches, safeOffset + safeLimit)
	for index = first, last do
		table.insert(items, copyTrack(matches[index]))
	end

	return {
		schemaVersion = 1,
		items = items,
		total = #matches,
		offset = safeOffset,
		limit = safeLimit,
		hasMore = safeOffset + #items < #matches,
	}
end

local Catalog = MusicCatalogService


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
			local cachedValue: AssetInfo | string = if cached.valid then cached.info :: AssetInfo else cached.error :: string
			return cached.valid, cachedValue, true
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

local Validation = MusicValidationService


--!strict
-- Authoritative in-memory queue operations for ClubMusic.
-- The controller supplies the one shared queue and its slot-release callback.
-- This service deliberately does not create a second queue or own playback state.

local MusicQueueManagerService = {}
MusicQueueManagerService.__index = MusicQueueManagerService

export type QueueManagerService = {
	queue: {any},
	releaseSlot: ((any) -> ())?,
	GetQueue: (self: QueueManagerService) -> {any},
	GetSize: (self: QueueManagerService) -> number,
	IsEmpty: (self: QueueManagerService) -> boolean,
	Insert: (self: QueueManagerService, index: number, entry: any) -> boolean,
	PopNext: (self: QueueManagerService) -> any?,
	RemoveAt: (self: QueueManagerService, index: number, release: boolean?) -> any?,
	RemoveUserSongs: (self: QueueManagerService, userId: number) -> number,
	Clear: (self: QueueManagerService, release: boolean?) -> number,
	ClearAutomatic: (self: QueueManagerService) -> number,
}

function MusicQueueManagerService.new(sharedQueue: {any}, releaseSlot: ((any) -> ())?): QueueManagerService
	assert(type(sharedQueue) == "table", "MusicQueueManagerService requires the controller-owned queue table")
	assert(releaseSlot == nil or type(releaseSlot) == "function", "MusicQueueManagerService releaseSlot must be a function")
	local self = setmetatable({}, MusicQueueManagerService)
	self.queue = sharedQueue
	self.releaseSlot = releaseSlot
	return self
end

function MusicQueueManagerService:GetQueue(): {any}
	return self.queue
end

function MusicQueueManagerService:GetSize(): number
	return #self.queue
end

function MusicQueueManagerService:IsEmpty(): boolean
	return #self.queue == 0
end

function MusicQueueManagerService:Insert(index: number, entry: any): boolean
	if type(index) ~= "number"
		or index % 1 ~= 0
		or index < 1
		or index > #self.queue + 1
		or type(entry) ~= "table"
	then
		return false
	end
	table.insert(self.queue, index, entry)
	return true
end

function MusicQueueManagerService:PopNext(): any?
	if #self.queue == 0 then
		return nil
	end
	local entry = table.remove(self.queue, 1)
	if self.releaseSlot then
		self.releaseSlot(entry)
	end
	return entry
end

function MusicQueueManagerService:RemoveAt(index: number, release: boolean?): any?
	if type(index) ~= "number"
		or index % 1 ~= 0
		or index < 1
		or index > #self.queue
	then
		return nil
	end

	local entry = table.remove(self.queue, index)
	if release ~= false and self.releaseSlot then
		self.releaseSlot(entry)
	end
	return entry
end

function MusicQueueManagerService:RemoveUserSongs(userId: number): number
	if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
		return 0
	end

	local removed = 0
	for index = #self.queue, 1, -1 do
		local entry = self.queue[index]
		if type(entry) == "table" and entry.source == "player" and entry.userId == userId then
			self:RemoveAt(index, true)
			removed += 1
		end
	end
	return removed
end

function MusicQueueManagerService:Clear(release: boolean?): number
	local removed = #self.queue
	if release ~= false and self.releaseSlot then
		for _, entry in ipairs(self.queue) do
			self.releaseSlot(entry)
		end
	end
	table.clear(self.queue)
	return removed
end

function MusicQueueManagerService:ClearAutomatic(): number
	local removed = 0
	for index = #self.queue, 1, -1 do
		local entry = self.queue[index]
		if type(entry) == "table" and entry.source ~= "player" then
			self:RemoveAt(index, false)
			removed += 1
		end
	end
	return removed
end

local Queue = MusicQueueManagerService


return { Catalog = Catalog, Validation = Validation, Queue = Queue }
