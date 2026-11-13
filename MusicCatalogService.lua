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
	{id="custom-84266261446965",genreId="exclusive",title="Anvil_of_Ruin",artist="DJ Doom",duration=190,genre="Club Exclusives",assetId=84266261446965,soundId="rbxassetid://84266261446965"},
	{id="custom-85420661204078",genreId="exclusive",title="Code in the Smoke",artist="DJ Doom",duration=184,genre="Club Exclusives",assetId=85420661204078,soundId="rbxassetid://85420661204078"},
	{id="custom-134987433423089",genreId="exclusive",title="Rich Lifestyle",artist="DJ Doom",duration=212,genre="Club Exclusives",assetId=134987433423089,soundId="rbxassetid://134987433423089"},
	{id="custom-92952858514774",genreId="exclusive",title="Metallic Chaos Within Magic Theory",artist="DJ Doom",duration=333,genre="Club Exclusives",assetId=92952858514774,soundId="rbxassetid://92952858514774"},
	{id="custom-117388170134707",genreId="exclusive",title="Steel Collision",artist="DJ Doom",duration=184,genre="Club Exclusives",assetId=117388170134707,soundId="rbxassetid://117388170134707"},
	{id="custom-86468432953052",genreId="exclusive",title="Fallen Star Blues",artist="DJ Doom",duration=230,genre="Club Exclusives",assetId=86468432953052,soundId="rbxassetid://86468432953052"},
	{id="custom-126526272193872",genreId="exclusive",title="Winter Between Us",artist="DJ Doom",duration=214,genre="Club Exclusives",assetId=126526272193872,soundId="rbxassetid://126526272193872"},
	{id="custom-96399574470852",genreId="exclusive",title="Terminal Frequency",artist="DJ Doom",duration=200,genre="Club Exclusives",assetId=96399574470852,soundId="rbxassetid://96399574470852"},
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
		artworkAssetId = track.artworkAssetId,
		placeholder = track.placeholder,
	}
end

local function hasValidStoredCatalogShape(stored: any): boolean
	if stored == nil then return true end
	if typeof(stored) ~= "table" or typeof(stored.tracks) ~= "table" then
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
	if TRACK_BY_ID[id] or customTracks[id] then return false, "That audio is already in the catalog." end
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
			return {schemaVersion=2, tracks=list}
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
			return {schemaVersion=2, tracks=filtered}
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

return MusicCatalogService
