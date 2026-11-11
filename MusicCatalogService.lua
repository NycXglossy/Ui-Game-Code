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
	{id = "rockstar", name = "Rockstar Music"},
}

-- Keep IDs stable: player favorites, queue entries, and the existing UI refer
-- to these IDs. Add approved songs here; never accept client-supplied metadata.
-- Official Rockstar Music tracks supplied for the built-in catalog.
-- Duration is a safe initial display/rotation estimate; audio length can be refined in Studio.
local CATALOG: {Track} = {
	{id="rs-001",genreId="rockstar",title="ЦАРСТВО ЛЬДА (KINGDOM ICE) - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=101747069867682,soundId="rbxassetid://101747069867682"},
	{id="rs-002",genreId="rockstar",title="VALHALLA - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=94572475036358,soundId="rbxassetid://94572475036358"},
	{id="rs-003",genreId="rockstar",title="EWIGKEIT (ETERNITY) - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=80224719113223,soundId="rbxassetid://80224719113223"},
	{id="rs-004",genreId="rockstar",title="RAISE YOUR SWORD - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=97360164630989,soundId="rbxassetid://97360164630989"},
	{id="rs-005",genreId="rockstar",title="BRAINROT - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=84463838060420,soundId="rbxassetid://84463838060420"},
	{id="rs-006",genreId="rockstar",title="FUEGO ETERNO - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=130189738826331,soundId="rbxassetid://130189738826331"},
	{id="rs-007",genreId="rockstar",title="THE ANIMALS - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=139929361277273,soundId="rbxassetid://139929361277273"},
	{id="rs-008",genreId="rockstar",title="MUSIC TO MY EARS - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=74410160876344,soundId="rbxassetid://74410160876344"},
	{id="rs-009",genreId="rockstar",title="PUNK NEVER DIE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=89299465649956,soundId="rbxassetid://89299465649956"},
	{id="rs-010",genreId="rockstar",title="WHERE THE MOONLIGHT FLOWS - ROCKSTAR MUSIC 🎹",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=98130232662740,soundId="rbxassetid://98130232662740"},
	{id="rs-011",genreId="rockstar",title="THEE, BEFORE THE DAWN - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=117631207759208,soundId="rbxassetid://117631207759208"},
	{id="rs-012",genreId="rockstar",title="THE CURSED HORSE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=86998726982213,soundId="rbxassetid://86998726982213"},
	{id="rs-013",genreId="rockstar",title="SURVIVE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=131330506049555,soundId="rbxassetid://131330506049555"},
	{id="rs-014",genreId="rockstar",title="BAD KITTY - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=95928884244632,soundId="rbxassetid://95928884244632"},
	{id="rs-015",genreId="rockstar",title="MOCHI MOCHI - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=127525416201816,soundId="rbxassetid://127525416201816"},
	{id="rs-016",genreId="rockstar",title="DEMON BOY - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=119611072399925,soundId="rbxassetid://119611072399925"},
	{id="rs-017",genreId="rockstar",title="HEAVEN'S OFFLINE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=96888364100902,soundId="rbxassetid://96888364100902"},
	{id="rs-018",genreId="rockstar",title="I WANT YOU - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=91426946588492,soundId="rbxassetid://91426946588492"},
	{id="rs-019",genreId="rockstar",title="STATIC IN MY HEAD - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=112675036295887,soundId="rbxassetid://112675036295887"},
	{id="rs-020",genreId="rockstar",title="WERE ALIVE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=87650244621618,soundId="rbxassetid://87650244621618"},
	{id="rs-021",genreId="rockstar",title="WHO ATE MY FRIES - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=136167356610135,soundId="rbxassetid://136167356610135"},
	{id="rs-022",genreId="rockstar",title="KOWASHITE KOROSHITE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=132641200748584,soundId="rbxassetid://132641200748584"},
	{id="rs-023",genreId="rockstar",title="JIGOKU NO ONIGOKKO - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=74995316988124,soundId="rbxassetid://74995316988124"},
	{id="rs-024",genreId="rockstar",title="☠️ MEMENTO MORI - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=81806204263973,soundId="rbxassetid://81806204263973"},
	{id="rs-025",genreId="rockstar",title="YOUTHFUL - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=116320151021949,soundId="rbxassetid://116320151021949"},
	{id="rs-026",genreId="rockstar",title="When Death Whispers - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=70824515147879,soundId="rbxassetid://70824515147879"},
	{id="rs-027",genreId="rockstar",title="CABBAGE SONG - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=119070170970736,soundId="rbxassetid://119070170970736"},
	{id="rs-028",genreId="rockstar",title="JARVIS, MORE COFFEE! - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=130828265778523,soundId="rbxassetid://130828265778523"},
	{id="rs-029",genreId="rockstar",title="JOIN THE DARKNESS - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=122614742546089,soundId="rbxassetid://122614742546089"},
	{id="rs-030",genreId="rockstar",title="Calling, Falling - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=108232416715644,soundId="rbxassetid://108232416715644"},
	{id="rs-031",genreId="rockstar",title="LOCKED IN - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=87112919850017,soundId="rbxassetid://87112919850017"},
	{id="rs-032",genreId="rockstar",title="WIZARDS & WITCHES - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=129367805552989,soundId="rbxassetid://129367805552989"},
	{id="rs-033",genreId="rockstar",title="BRUXARIA - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=116891138317333,soundId="rbxassetid://116891138317333"},
	{id="rs-034",genreId="rockstar",title="PRESS START! - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=71944613506230,soundId="rbxassetid://71944613506230"},
	{id="rs-035",genreId="rockstar",title="TOMA ESSA - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=102676299218296,soundId="rbxassetid://102676299218296"},
	{id="rs-036",genreId="rockstar",title="STAY UNTIL THE MORNING - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=101500253951278,soundId="rbxassetid://101500253951278"},
	{id="rs-037",genreId="rockstar",title="BAD HABIT - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=140404086478231,soundId="rbxassetid://140404086478231"},
	{id="rs-038",genreId="rockstar",title="TOXIC HEAVEN - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=83924033717755,soundId="rbxassetid://83924033717755"},
	{id="rs-039",genreId="rockstar",title="LIKE A BAD HABIT - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=97738124376304,soundId="rbxassetid://97738124376304"},
	{id="rs-040",genreId="rockstar",title="《頭の中の声 — THE VOICE INSIDE》 - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=72210385597387,soundId="rbxassetid://72210385597387"},
	{id="rs-041",genreId="rockstar",title="《爱到最后》 — Love Until the End - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=117350103658197,soundId="rbxassetid://117350103658197"},
	{id="rs-042",genreId="rockstar",title="《撕裂我》 — TEAR ME APART - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=75493068377605,soundId="rbxassetid://75493068377605"},
	{id="rs-043",genreId="rockstar",title="《YOU PISSED ME GTFO》 - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=136568256580687,soundId="rbxassetid://136568256580687"},
	{id="rs-044",genreId="rockstar",title="《THE CHAOS INSIDE THE GRAVE》 - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=139037867481453,soundId="rbxassetid://139037867481453"},
	{id="rs-045",genreId="rockstar",title="NO PULSE - ROCKSTAR MUSIC 1",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=115701042643443,soundId="rbxassetid://115701042643443"},
	{id="rs-046",genreId="rockstar",title="ASYLUM - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=103411776894823,soundId="rbxassetid://103411776894823"},
	{id="rs-047",genreId="rockstar",title="😈 DEVIL PARTY - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=115684367542992,soundId="rbxassetid://115684367542992"},
	{id="rs-048",genreId="rockstar",title="DEVIL KING DIABLO 🔥 - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=113706658243302,soundId="rbxassetid://113706658243302"},
	{id="rs-049",genreId="rockstar",title="BABY GIRL - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=103743609892959,soundId="rbxassetid://103743609892959"},
	{id="rs-050",genreId="rockstar",title="😈 DEVIL PARTY 2 - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=78170006189365,soundId="rbxassetid://78170006189365"},
	{id="rs-051",genreId="rockstar",title="BAD INTENTIONS - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=97169308940761,soundId="rbxassetid://97169308940761"},
	{id="rs-052",genreId="rockstar",title="PRETTY LITTLE VILLAIN - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=120334121966618,soundId="rbxassetid://120334121966618"},
	{id="rs-053",genreId="rockstar",title="LOCO DE NOVO - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=75188213635961,soundId="rbxassetid://75188213635961"},
	{id="rs-054",genreId="rockstar",title="MALA SUERTE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=140584878033447,soundId="rbxassetid://140584878033447"},
	{id="rs-055",genreId="rockstar",title="RUN BACK TO YOU - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=129155813472971,soundId="rbxassetid://129155813472971"},
	{id="rs-056",genreId="rockstar",title="LOCO LA NOCHE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=78726556241060,soundId="rbxassetid://78726556241060"},
	{id="rs-057",genreId="rockstar",title="HOMEBOUND - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=91642669963413,soundId="rbxassetid://91642669963413"},
	{id="rs-058",genreId="rockstar",title="YOU WILL SAVE ME - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=81535116483228,soundId="rbxassetid://81535116483228"},
	{id="rs-059",genreId="rockstar",title="NOCHE MILITAR - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=101887058731629,soundId="rbxassetid://101887058731629"},
	{id="rs-060",genreId="rockstar",title="LETS RAVE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=128862263867208,soundId="rbxassetid://128862263867208"},
	{id="rs-061",genreId="rockstar",title="LETS GO - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=83132345518796,soundId="rbxassetid://83132345518796"},
	{id="rs-062",genreId="rockstar",title="Lái ba! - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=129632173614221,soundId="rbxassetid://129632173614221"},
	{id="rs-063",genreId="rockstar",title="Stay With Me Tonight - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=139536344523269,soundId="rbxassetid://139536344523269"},
	{id="rs-064",genreId="rockstar",title="LOUD AGAIN - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=138509819036095,soundId="rbxassetid://138509819036095"},
	{id="rs-065",genreId="rockstar",title="HIT THE JACKPOT - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=127417451579851,soundId="rbxassetid://127417451579851"},
	{id="rs-066",genreId="rockstar",title="JACKPOT - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=105532556092908,soundId="rbxassetid://105532556092908"},
	{id="rs-067",genreId="rockstar",title="ONE MILLION AURA - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=126071591868074,soundId="rbxassetid://126071591868074"},
	{id="rs-068",genreId="rockstar",title="AURA UP - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=121200628445088,soundId="rbxassetid://121200628445088"},
	{id="rs-069",genreId="rockstar",title="ROCKSTAR LOUD AGAIN - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=100090621989807,soundId="rbxassetid://100090621989807"},
	{id="rs-070",genreId="rockstar",title="ELECTRO NOCHE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=81881557980900,soundId="rbxassetid://81881557980900"},
	{id="rs-071",genreId="rockstar",title="HASTA LA VISTA - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=76475729757169,soundId="rbxassetid://76475729757169"},
	{id="rs-072",genreId="rockstar",title="WIKI WIKI CALIENTE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=71291402073981,soundId="rbxassetid://71291402073981"},
	{id="rs-073",genreId="rockstar",title="TROMPETA LOCA - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=113783736171409,soundId="rbxassetid://113783736171409"},
	{id="rs-074",genreId="rockstar",title="STAR - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=130904670655160,soundId="rbxassetid://130904670655160"},
	{id="rs-075",genreId="rockstar",title="808 - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=108789141362528,soundId="rbxassetid://108789141362528"},
	{id="rs-076",genreId="rockstar",title="West Side Rodeo - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=101092834150124,soundId="rbxassetid://101092834150124"},
	{id="rs-077",genreId="rockstar",title="Dead Man Rodeo - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=99683897143014,soundId="rbxassetid://99683897143014"},
	{id="rs-078",genreId="rockstar",title="Wild West - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=102658900947597,soundId="rbxassetid://102658900947597"},
	{id="rs-079",genreId="rockstar",title="DIGITAL ANGEL SLOWED - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=130044584626758,soundId="rbxassetid://130044584626758"},
	{id="rs-080",genreId="rockstar",title="BENEATH THE ROCKSTAR",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=102156431152181,soundId="rbxassetid://102156431152181"},
	{id="rs-081",genreId="rockstar",title="ROCKSTAR v2",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=81102671419153,soundId="rbxassetid://81102671419153"},
	{id="rs-082",genreId="rockstar",title="ROCKSTAR TONIGHT",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=87715903017727,soundId="rbxassetid://87715903017727"},
	{id="rs-083",genreId="rockstar",title="Rockstar Rythm",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=104091161753141,soundId="rbxassetid://104091161753141"},
	{id="rs-084",genreId="rockstar",title="ROCKSTAR — ROYAL FLOW",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=102981123299750,soundId="rbxassetid://102981123299750"},
	{id="rs-085",genreId="rockstar",title="ROCKSTAR CHOIR - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=97919991033288,soundId="rbxassetid://97919991033288"},
	{id="rs-086",genreId="rockstar",title="WELCOME TO ROCKSTAR CLUB",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=137496138684881,soundId="rbxassetid://137496138684881"},
	{id="rs-087",genreId="rockstar",title="WE ARE ROCKSTAR CLUB",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=78566160749049,soundId="rbxassetid://78566160749049"},
	{id="rs-088",genreId="rockstar",title="DISS by ROCKSTAR CLUB",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=132003269845086,soundId="rbxassetid://132003269845086"},
	{id="rs-089",genreId="rockstar",title="WIKI WIKI - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=72287010284190,soundId="rbxassetid://72287010284190"},
	{id="rs-090",genreId="rockstar",title="NO APPEAL - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=86409600066151,soundId="rbxassetid://86409600066151"},
	{id="rs-091",genreId="rockstar",title="RED VS BLUE DANCE BATTLE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=103078774347092,soundId="rbxassetid://103078774347092"},
	{id="rs-092",genreId="rockstar",title="DANCE BATTLE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=102629234857720,soundId="rbxassetid://102629234857720"},
	{id="rs-093",genreId="rockstar",title="DOKI DOKI SENORITA - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=110646640395028,soundId="rbxassetid://110646640395028"},
	{id="rs-094",genreId="rockstar",title="FUEGO - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=75008964642462,soundId="rbxassetid://75008964642462"},
	{id="rs-095",genreId="rockstar",title="TATAKAE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=130143479667778,soundId="rbxassetid://130143479667778"},
	{id="rs-096",genreId="rockstar",title="TOKYO DRIFTO - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=114841627753534,soundId="rbxassetid://114841627753534"},
	{id="rs-097",genreId="rockstar",title="AUUUU - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=139902099684446,soundId="rbxassetid://139902099684446"},
	{id="rs-098",genreId="rockstar",title="INSOMNIACS - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=72696775581246,soundId="rbxassetid://72696775581246"},
	{id="rs-099",genreId="rockstar",title="CULLING GAME- ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=93654119801657,soundId="rbxassetid://93654119801657"},
	{id="rs-100",genreId="rockstar",title="NEXT LEVEL - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=79771127330486,soundId="rbxassetid://79771127330486"},
	{id="rs-101",genreId="rockstar",title="HIGHER - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=107931667328651,soundId="rbxassetid://107931667328651"},
	{id="rs-102",genreId="rockstar",title="VAMOS - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=89492694953186,soundId="rbxassetid://89492694953186"},
	{id="rs-103",genreId="rockstar",title="ROCKSTAR FAMILY - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=118822539347835,soundId="rbxassetid://118822539347835"},
	{id="rs-104",genreId="rockstar",title="MEMORIES- ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=101797843704545,soundId="rbxassetid://101797843704545"},
	{id="rs-105",genreId="rockstar",title="Virtual Reality - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=117514615022926,soundId="rbxassetid://117514615022926"},
	{id="rs-106",genreId="rockstar",title="DOMAIN EXPANSION - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=126558441678884,soundId="rbxassetid://126558441678884"},
	{id="rs-107",genreId="rockstar",title="Emotion - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=112627522114597,soundId="rbxassetid://112627522114597"},
	{id="rs-108",genreId="rockstar",title="YAKUZA - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=85534313579791,soundId="rbxassetid://85534313579791"},
	{id="rs-109",genreId="rockstar",title="THE CROWN - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=91438992535993,soundId="rbxassetid://91438992535993"},
	{id="rs-110",genreId="rockstar",title="EMPTY LOOP - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=113514858456781,soundId="rbxassetid://113514858456781"},
	{id="rs-111",genreId="rockstar",title="Demon Angel - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=94660678846607,soundId="rbxassetid://94660678846607"},
	{id="rs-112",genreId="rockstar",title="WILDZONE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=118779117482054,soundId="rbxassetid://118779117482054"},
	{id="rs-113",genreId="rockstar",title="Nuketown After Dark - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=99466352585457,soundId="rbxassetid://99466352585457"},
	{id="rs-114",genreId="rockstar",title="King Electrico - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=84765623519656,soundId="rbxassetid://84765623519656"},
	{id="rs-115",genreId="rockstar",title="Party from HELL - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=118642737393541,soundId="rbxassetid://118642737393541"},
	{id="rs-116",genreId="rockstar",title="##### - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=76429804603461,soundId="rbxassetid://76429804603461"},
	{id="rs-117",genreId="rockstar",title="ROBUX APOCALYPSE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=84284978816291,soundId="rbxassetid://84284978816291"},
	{id="rs-118",genreId="rockstar",title="SHADOW BOXER - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=120629707718179,soundId="rbxassetid://120629707718179"},
	{id="rs-119",genreId="rockstar",title="Sit Down - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=71614707708061,soundId="rbxassetid://71614707708061"},
	{id="rs-120",genreId="rockstar",title="BAM BAM TOKYO - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=100538989750966,soundId="rbxassetid://100538989750966"},
	{id="rs-121",genreId="rockstar",title="SHAKE IT FAST - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=121688700922262,soundId="rbxassetid://121688700922262"},
	{id="rs-122",genreId="rockstar",title="LA DI DA - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=106557974673739,soundId="rbxassetid://106557974673739"},
	{id="rs-123",genreId="rockstar",title="NINGEN JA NAI - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=130064289789295,soundId="rbxassetid://130064289789295"},
	{id="rs-124",genreId="rockstar",title="I WANNA BE YOURS - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=83549314703180,soundId="rbxassetid://83549314703180"},
	{id="rs-125",genreId="rockstar",title="I WAS KING - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=95500594892325,soundId="rbxassetid://95500594892325"},
	{id="rs-126",genreId="rockstar",title="FULLDIVE DOMINATION - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=115280038385551,soundId="rbxassetid://115280038385551"},
	{id="rs-127",genreId="rockstar",title="SATISFACTION - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=119585852446002,soundId="rbxassetid://119585852446002"},
	{id="rs-128",genreId="rockstar",title="REMIX MY DREAM - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=70748760058676,soundId="rbxassetid://70748760058676"},
	{id="rs-129",genreId="rockstar",title="NOWHERE TO GO - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=79145736371802,soundId="rbxassetid://79145736371802"},
	{id="rs-130",genreId="rockstar",title="DRAGON SHAMISEN - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=138833744313175,soundId="rbxassetid://138833744313175"},
	{id="rs-131",genreId="rockstar",title="CHK CHK - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=105836038795048,soundId="rbxassetid://105836038795048"},
	{id="rs-132",genreId="rockstar",title="WIKY WIKY BOOM BOOM - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=89869046754252,soundId="rbxassetid://89869046754252"},
	{id="rs-133",genreId="rockstar",title="TAKE ME AS I AM - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=136751225401274,soundId="rbxassetid://136751225401274"},
	{id="rs-134",genreId="rockstar",title="LEAVE THE SHADOWS - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=130660508750095,soundId="rbxassetid://130660508750095"},
	{id="rs-135",genreId="rockstar",title="HOME - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=104500209960951,soundId="rbxassetid://104500209960951"},
	{id="rs-136",genreId="rockstar",title="THE DEVIL INSIDE OF ME - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=89581255187211,soundId="rbxassetid://89581255187211"},
	{id="rs-137",genreId="rockstar",title="WILD PERSONALITY - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=92289950230523,soundId="rbxassetid://92289950230523"},
	{id="rs-138",genreId="rockstar",title="BREAKING FREE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=117915912690305,soundId="rbxassetid://117915912690305"},
	{id="rs-139",genreId="rockstar",title="LEVEL UP TONIGHT - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=116708485796940,soundId="rbxassetid://116708485796940"},
	{id="rs-140",genreId="rockstar",title="SAILING NO CAP - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=73292895427268,soundId="rbxassetid://73292895427268"},
	{id="rs-141",genreId="rockstar",title="CONTINUE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=100245316172652,soundId="rbxassetid://100245316172652"},
	{id="rs-142",genreId="rockstar",title="SPACE MONEY BABY - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=135994417625670,soundId="rbxassetid://135994417625670"},
	{id="rs-143",genreId="rockstar",title="TOO RICH TO SLEEP - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=80476746875979,soundId="rbxassetid://80476746875979"},
	{id="rs-144",genreId="rockstar",title="SELF SATISFACTION - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=140181806875883,soundId="rbxassetid://140181806875883"},
	{id="rs-145",genreId="rockstar",title="Midnight Phantom - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=140218419172755,soundId="rbxassetid://140218419172755"},
	{id="rs-146",genreId="rockstar",title="Black Veins - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=122503393736590,soundId="rbxassetid://122503393736590"},
	{id="rs-147",genreId="rockstar",title="Dancin Through the Night - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=133012318131516,soundId="rbxassetid://133012318131516"},
	{id="rs-148",genreId="rockstar",title="S I N P I - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=96936689660160,soundId="rbxassetid://96936689660160"},
	{id="rs-149",genreId="rockstar",title="Sleepless Nights - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=74724142838287,soundId="rbxassetid://74724142838287"},
	{id="rs-150",genreId="rockstar",title="Winter Bloom - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=127326224077938,soundId="rbxassetid://127326224077938"},
	{id="rs-151",genreId="rockstar",title="Heaven Sent - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=102719769382569,soundId="rbxassetid://102719769382569"},
	{id="rs-152",genreId="rockstar",title="OH MY GOD - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=98622222124023,soundId="rbxassetid://98622222124023"},
	{id="rs-153",genreId="rockstar",title="Netflix and Chill - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=90980794461351,soundId="rbxassetid://90980794461351"},
	{id="rs-154",genreId="rockstar",title="Summer Banana - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=88474669415723,soundId="rbxassetid://88474669415723"},
	{id="rs-155",genreId="rockstar",title="RESPAWN.exe - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=113368354044600,soundId="rbxassetid://113368354044600"},
	{id="rs-156",genreId="rockstar",title="Dace of Spades - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=117700175720719,soundId="rbxassetid://117700175720719"},
	{id="rs-157",genreId="rockstar",title="Shadows of the Crown - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=113346342947953,soundId="rbxassetid://113346342947953"},
	{id="rs-158",genreId="rockstar",title="TENJOU KESSEN - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=82905149351949,soundId="rbxassetid://82905149351949"},
	{id="rs-159",genreId="rockstar",title="ROCKSTAR TERROR - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=76939350716867,soundId="rbxassetid://76939350716867"},
	{id="rs-160",genreId="rockstar",title="ANGELS DRIFT IN HELL - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=121643547014940,soundId="rbxassetid://121643547014940"},
	{id="rs-161",genreId="rockstar",title="G0DMODE - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=104414709955736,soundId="rbxassetid://104414709955736"},
	{id="rs-162",genreId="rockstar",title="RUM GOLD - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=130554714345272,soundId="rbxassetid://130554714345272"},
	{id="rs-163",genreId="rockstar",title="DEAD TIDES - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=78349784691144,soundId="rbxassetid://78349784691144"},
	{id="rs-164",genreId="rockstar",title="CURSED GOLD - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=124528341939081,soundId="rbxassetid://124528341939081"},
	{id="rs-165",genreId="rockstar",title="BROKEN IVORY - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=87815156233953,soundId="rbxassetid://87815156233953"},
	{id="rs-166",genreId="rockstar",title="CAPTAIN OF THE WAVES - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=108771718184326,soundId="rbxassetid://108771718184326"},
	{id="rs-167",genreId="rockstar",title="GG - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=119845290012591,soundId="rbxassetid://119845290012591"},
	{id="rs-168",genreId="rockstar",title="THE FAME (DRIFT REMIX) - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=83251198487236,soundId="rbxassetid://83251198487236"},
	{id="rs-169",genreId="rockstar",title="TOKYO GO - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=107192893978296,soundId="rbxassetid://107192893978296"},
	{id="rs-170",genreId="rockstar",title="CTRL + HEART - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=123788349491879,soundId="rbxassetid://123788349491879"},
	{id="rs-171",genreId="rockstar",title="Banyak Gaya - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=88647281325157,soundId="rbxassetid://88647281325157"},
	{id="rs-172",genreId="rockstar",title="Brawl Club - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=92619965128873,soundId="rbxassetid://92619965128873"},
	{id="rs-173",genreId="rockstar",title="Such a Clown - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=117931860258546,soundId="rbxassetid://117931860258546"},
	{id="rs-174",genreId="rockstar",title="MERAH PUTIH - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=134619820718563,soundId="rbxassetid://134619820718563"},
	{id="rs-175",genreId="rockstar",title="AMERICAN NIGHT - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=90161477634230,soundId="rbxassetid://90161477634230"},
	{id="rs-176",genreId="rockstar",title="EXPENSIVE AVATAR - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=90149646887810,soundId="rbxassetid://90149646887810"},
	{id="rs-177",genreId="rockstar",title="DAME DAME - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=71901593889343,soundId="rbxassetid://71901593889343"},
	{id="rs-178",genreId="rockstar",title="RED WHITE ENERGY - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=121376370955229,soundId="rbxassetid://121376370955229"},
	{id="rs-179",genreId="rockstar",title="NINJA NINJA - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=83383913094162,soundId="rbxassetid://83383913094162"},
	{id="rs-180",genreId="rockstar",title="ANGEL IN THE DARK - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=77086451705749,soundId="rbxassetid://77086451705749"},
	{id="rs-181",genreId="rockstar",title="SHADOW CODE - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=77001931536731,soundId="rbxassetid://77001931536731"},
	{id="rs-182",genreId="rockstar",title="NO LIMIT - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=104516545227009,soundId="rbxassetid://104516545227009"},
	{id="rs-183",genreId="rockstar",title="RUN IT UP - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=82777265963025,soundId="rbxassetid://82777265963025"},
	{id="rs-184",genreId="rockstar",title="SHINOBI - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=102364733671160,soundId="rbxassetid://102364733671160"},
	{id="rs-185",genreId="rockstar",title="BLACK CASINO - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=107216594308719,soundId="rbxassetid://107216594308719"},
	{id="rs-186",genreId="rockstar",title="Dancing in the Midnight Moon - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=106920320888810,soundId="rbxassetid://106920320888810"},
	{id="rs-187",genreId="rockstar",title="Earth on Fire - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=133240283058621,soundId="rbxassetid://133240283058621"},
	{id="rs-188",genreId="rockstar",title="Joker in Las Vegas - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=85228078918471,soundId="rbxassetid://85228078918471"},
	{id="rs-189",genreId="rockstar",title="Miss Secretz - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=115774699229355,soundId="rbxassetid://115774699229355"},
	{id="rs-190",genreId="rockstar",title="Where You at - Rockstar Music",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=120492884108069,soundId="rbxassetid://120492884108069"},
	{id="rs-191",genreId="rockstar",title="SATU MIC — INDO vs ENGLISH - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=81446988142746,soundId="rbxassetid://81446988142746"},
	{id="rs-192",genreId="rockstar",title="DRAGON HEART - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=74771374367797,soundId="rbxassetid://74771374367797"},
	{id="rs-193",genreId="rockstar",title="FUEGO _ 閃光 (SENKŌ) - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=139994092251547,soundId="rbxassetid://139994092251547"},
	{id="rs-194",genreId="rockstar",title="OATH OF STEEL - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=94537532654391,soundId="rbxassetid://94537532654391"},
	{id="rs-195",genreId="rockstar",title="Spellbound Blade - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=88140540778402,soundId="rbxassetid://88140540778402"},
	{id="rs-196",genreId="rockstar",title="UNWRITE THE STARS - ROCKSTAR MUSIC",artist="Rockstar Music",duration=240,genre="Rockstar Music",assetId=123161916752734,soundId="rbxassetid://123161916752734"},
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
