--!strict
-- MusicCatalogService
-- Place as ModuleScript: ServerStorage/MusicCatalogService
--
-- Server-owned metadata catalog. This module does not own playback, queueing,
-- permissions, DataStores, or Sound instances. The UI_Server_Controller remains
-- authoritative for every request and playback decision.

local MusicCatalogService = {}

export type Track = {
	id: string,
	genreId: string,
	title: string,
	artist: string,
	duration: number,
	genre: string,
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
	}
end

function MusicCatalogService:GetTrackById(trackId: any): Track?
	if type(trackId) ~= "string" or #trackId > 24 then return nil end
	local track = TRACK_BY_ID[trackId]
	return if track then copyTrack(track) else nil
end

function MusicCatalogService:GetAllTracks(): {Track}
	local result: {Track} = {}
	for _, track in ipairs(CATALOG) do
		table.insert(result, copyTrack(track))
	end
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
	for _, track in ipairs(CATALOG) do
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
