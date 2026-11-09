--!strict
-- MusicCatalogService
-- Place as ModuleScript: ServerStorage/MusicCatalogService
--
-- Server-owned metadata catalog. This module does not own playback, queueing,
-- permissions, DataStores, or Sound instances. The UI_Server_Controller remains
-- authoritative for every request and playback decision.

local MusicCatalogService = {}

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local catalogStore = DataStoreService:GetDataStore("ClubMusic_Catalog_v1")
local CATALOG_KEY = "custom_tracks"
local MAX_CUSTOM_TRACKS = 200
local customTracks: {[string]: Track} = {}
local storageInitialized = false
local storagePersistent = false
local storageReady = false
local storageWriteBusy = false

export type Track = {
	id: string,
	genreId: string,
	title: string,
	artist: string,
	duration: number,
	genre: string,
	assetId: number?,
	soundId: string?,
}

type Genre = {
	id: string,
	name: string,
}

local GENRES: {Genre} = {
	{id = "hiphop", name = "Hip Hop / Rap"},
	{id = "rnb", name = "R&B / Soul"},
	{id = "rock", name = "Rock"},
	{id = "kpop", name = "K-Pop"},
	{id = "latin", name = "Latin Music"},
	{id = "edm", name = "EDM"},
	{id = "country", name = "Country"},
	{id = "pop", name = "Pop"},
	{id = "exclusive", name = "Club Exclusives"},
}

-- Keep IDs stable: player favorites, queue entries, and the existing UI refer
-- to these IDs. Add approved songs here; never accept client-supplied metadata.
local CATALOG: {Track} = {
	{id="hh-0",genreId="hiphop",title="Palm Tree Freestyle",artist="Lil Coconut",duration=184,genre="Hip Hop / Rap"},
	{id="hh-1",genreId="hiphop",title="Tide Money",artist="MC Lagoon",duration=201,genre="Hip Hop / Rap"},
	{id="hh-2",genreId="hiphop",title="Boardwalk Bounce",artist="Kid Kahuna",duration=176,genre="Hip Hop / Rap"},
	{id="hh-3",genreId="hiphop",title="Sandcastle Kings",artist="Reef Gang",duration=213,genre="Hip Hop / Rap"},
	{id="hh-4",genreId="hiphop",title="Midnight Luau",artist="Big Pineapple",duration=195,genre="Hip Hop / Rap"},
	{id="hh-5",genreId="hiphop",title="Wave Check",artist="Yung Tsunami",duration=168,genre="Hip Hop / Rap"},
	{id="rnb-0",genreId="rnb",title="Golden Hour Love",artist="Coral Rose",duration=224,genre="R&B / Soul"},
	{id="rnb-1",genreId="rnb",title="Slow Tide",artist="Marina Soul",duration=241,genre="R&B / Soul"},
	{id="rnb-2",genreId="rnb",title="Tiki Torch Serenade",artist="D'Angelo Bay",duration=232,genre="R&B / Soul"},
	{id="rnb-3",genreId="rnb",title="Velvet Shoreline",artist="Honey Kai",duration=207,genre="R&B / Soul"},
	{id="rnb-4",genreId="rnb",title="Lantern Light",artist="Nalu & The Keys",duration=219,genre="R&B / Soul"},
	{id="rk-0",genreId="rock",title="Volcano Riff",artist="The Lava Kings",duration=238,genre="Rock"},
	{id="rk-1",genreId="rock",title="Surf's Up Anthem",artist="Riptide Rebels",duration=199,genre="Rock"},
	{id="rk-2",genreId="rock",title="Driftwood Highway",artist="Saltwater Saints",duration=262,genre="Rock"},
	{id="rk-3",genreId="rock",title="Thunder on the Bay",artist="Coral Crush",duration=221,genre="Rock"},
	{id="kp-0",genreId="kpop",title="SUMMER GLITCH",artist="NEONWAVE",duration=192,genre="K-Pop"},
	{id="kp-1",genreId="kpop",title="Pink Horizon",artist="STARR1SE",duration=205,genre="K-Pop"},
	{id="kp-2",genreId="kpop",title="Island Signal",artist="LUMI-9",duration=187,genre="K-Pop"},
	{id="kp-3",genreId="kpop",title="Heartbeat Lagoon",artist="KORAL",duration=199,genre="K-Pop"},
	{id="kp-4",genreId="kpop",title="Firework Kiss",artist="AURA X",duration=181,genre="K-Pop"},
	{id="lt-0",genreId="latin",title="Playa Caliente",artist="DJ Mango",duration=214,genre="Latin Music"},
	{id="lt-1",genreId="latin",title="Bailando en la Arena",artist="Sol y Mar",duration=228,genre="Latin Music"},
	{id="lt-2",genreId="latin",title="Noche Tropical",artist="La Ola",duration=203,genre="Latin Music"},
	{id="lt-3",genreId="latin",title="Fuego Lento",artist="Rey Coco",duration=197,genre="Latin Music"},
	{id="edm-0",genreId="edm",title="Sunset Overdrive",artist="Aqualux",duration=246,genre="EDM"},
	{id="edm-1",genreId="edm",title="Neon Coastline",artist="VOLTA",duration=233,genre="EDM"},
	{id="edm-2",genreId="edm",title="Tidal Drop",artist="Prism Reef",duration=258,genre="EDM"},
	{id="edm-3",genreId="edm",title="Laser Lagoon",artist="Kairo",duration=219,genre="EDM"},
	{id="edm-4",genreId="edm",title="Afterglow Rave",artist="SKYE.EXE",duration=271,genre="EDM"},
	{id="edm-5",genreId="edm",title="Bassquake Beach",artist="Subduction",duration=205,genre="EDM"},
	{id="ct-0",genreId="country",title="Beach Truck Blues",artist="Dusty Shores",duration=212,genre="Country"},
	{id="ct-1",genreId="country",title="Sunburnt Sweetheart",artist="Cody Cove",duration=198,genre="Country"},
	{id="ct-2",genreId="country",title="Barefoot Rodeo",artist="The Palm Ranch",duration=205,genre="Country"},
	{id="pop-0",genreId="pop",title="Electric Paradise",artist="Mia Lumen",duration=189,genre="Pop"},
	{id="pop-1",genreId="pop",title="Coconut Crush",artist="Jade Rivers",duration=176,genre="Pop"},
	{id="pop-2",genreId="pop",title="Ocean Eyes Tonight",artist="Leo Starr",duration=201,genre="Pop"},
	{id="pop-3",genreId="pop",title="Glow Up Summer",artist="Nova Bay",duration=183,genre="Pop"},
	{id="pop-4",genreId="pop",title="Postcard Heart",artist="Kenna Blue",duration=194,genre="Pop"},
	{id="ex-0",genreId="exclusive",title="Sunset Stage Anthem",artist="Club Resident",duration=262,genre="Club Exclusives"},
	{id="ex-1",genreId="exclusive",title="Tiki Torch Theory",artist="Club Resident ft. VOLTA",duration=238,genre="Club Exclusives"},
	{id="ex-2",genreId="exclusive",title="Low-Poly Paradise",artist="Pixel Palms",duration=224,genre="Club Exclusives"},
	{id="ex-3",genreId="exclusive",title="Mainstage Moonrise",artist="The Owners",duration=289,genre="Club Exclusives"},
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
	}
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
	if typeof(title) ~= "string" or #title < 1 or #title > 100 then return nil end
	if typeof(artist) ~= "string" or #artist < 1 or #artist > 100 then return nil end
	if typeof(duration) ~= "number" or duration ~= duration or duration % 1 ~= 0 or duration < 1 or duration > 3600 then return nil end
	if typeof(genre) ~= "string" or #genre < 1 or #genre > 40 then return nil end
	return {id=id, genreId=genreId, title=title, artist=artist, duration=duration, genre=genre,
		assetId=assetId, soundId="rbxassetid://" .. tostring(assetId)}
end

local function serializeCustomTracks(source: {[string]: Track}): {any}
	local result = {}
	for _, track in pairs(source) do
		table.insert(result, {assetId=track.assetId, genreId=track.genreId, title=track.title,
			artist=track.artist, duration=track.duration, genre=track.genre})
	end
	table.sort(result, function(a, b) return a.assetId < b.assetId end)
	return result
end

function MusicCatalogService:Initialize(studioUseDataStore: boolean?, budgetCallback: (() -> boolean)?): boolean
	if storageInitialized then return storageReady end
	storageInitialized = true
	storagePersistent = not RunService:IsStudio() or studioUseDataStore == true
	if not storagePersistent then
		storageReady = true -- Studio session-only catalog; never pretend it persisted.
		return true
	end
	if budgetCallback and not budgetCallback() then
		warn("[ClubMusic Catalog] Shared DataStore budget unavailable; custom catalog storage is read-only until restart.")
		return false
	end
	local ok, stored = pcall(function() return catalogStore:GetAsync(CATALOG_KEY) end)
	if not ok then
		warn("[ClubMusic Catalog] Could not load persisted catalog: " .. tostring(stored))
		return false
	end
	local loaded: {[string]: Track} = {}
	if typeof(stored) == "table" and typeof(stored.tracks) == "table" then
		local count = 0
		for _, rawTrack in ipairs(stored.tracks) do
			count += 1
			if count > MAX_CUSTOM_TRACKS then break end
			local clean = sanitizeStoredTrack(rawTrack)
			if clean and not TRACK_BY_ID[clean.id] then loaded[clean.id] = clean end
		end
	end
	customTracks = loaded
	storageReady = true
	return true
end

function MusicCatalogService:IsStorageReady(): boolean
	return storageReady
end

function MusicCatalogService:AddCustomTrack(assetId: number, title: string, artist: string, duration: number, genreId: string): (boolean, string)
	if not storageReady then return false, "Catalog storage is unavailable; no changes were saved." end
	if typeof(assetId) ~= "number" or assetId % 1 ~= 0 or assetId <= 0 or assetId > 9007199254740991 then return false, "Invalid audio asset ID." end
	if typeof(title) ~= "string" or #title < 1 or #title > 100 or typeof(artist) ~= "string" or #artist < 1 or #artist > 100 then return false, "Invalid track metadata." end
	if typeof(duration) ~= "number" or duration % 1 ~= 0 or duration < 1 or duration > 3600 then return false, "Invalid track duration." end
	if typeof(genreId) ~= "string" or not VALID_GENRES[genreId] then return false, "Choose a valid catalog genre." end
	if storageWriteBusy then return false, "Catalog is busy. Try again shortly." end
	local id = "custom-" .. tostring(assetId)
	if TRACK_BY_ID[id] or customTracks[id] then return false, "That audio is already in the catalog." end
	local genreName = "Club Exclusives"
	for _, genre in ipairs(GENRES) do if genre.id == genreId then genreName = genre.name break end end
	local candidate: Track = {id=id, genreId=genreId, title=title, artist=artist, duration=duration,
		genre=genreName, assetId=assetId, soundId="rbxassetid://" .. tostring(assetId)}
	if not storagePersistent then customTracks[id] = candidate; return true, "Added for this Studio session only." end
	storageWriteBusy = true
	local updatedData: any = nil
	local ok, err = pcall(function()
		updatedData = catalogStore:UpdateAsync(CATALOG_KEY, function(old)
			local list = if typeof(old) == "table" and typeof(old.tracks) == "table" then table.clone(old.tracks) else {}
			for _, raw in ipairs(list) do
				if typeof(raw) == "table" and tonumber(raw.assetId) == assetId then return old end
			end
			if #list >= MAX_CUSTOM_TRACKS then return old end
			table.insert(list, {assetId=assetId, genreId=genreId, title=title, artist=artist, duration=duration, genre=genreName})
			return {schemaVersion=1, tracks=list}
		end)
	end)
	storageWriteBusy = false
	if not ok then warn("[ClubMusic Catalog] Add failed: " .. tostring(err)); return false, "Catalog save failed. Try again later." end
	local found = false
	if typeof(updatedData) == "table" and typeof(updatedData.tracks) == "table" then
		for _, raw in ipairs(updatedData.tracks) do
			local clean = sanitizeStoredTrack(raw)
			if clean and clean.id == id then found = true; break end
		end
	end
	if not found then return false, "Catalog is full or the track already exists." end
	customTracks[id] = candidate
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
	local ok, err = pcall(function()
		updatedData = catalogStore:UpdateAsync(CATALOG_KEY, function(old)
			local list = if typeof(old) == "table" and typeof(old.tracks) == "table" then table.clone(old.tracks) else {}
			local filtered = {}
			for _, raw in ipairs(list) do
				if not (typeof(raw) == "table" and tonumber(raw.assetId) == assetId) then table.insert(filtered, raw) end
			end
			return {schemaVersion=1, tracks=filtered}
		end)
	end)
	storageWriteBusy = false
	if not ok then warn("[ClubMusic Catalog] Remove failed: " .. tostring(err)); return false, "Catalog save failed. Track was not removed." end
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
