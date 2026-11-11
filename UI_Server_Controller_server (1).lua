--!strict

-- Keep controller helpers in one registry to stay below Luau's local-register limit.
local ControllerFunctions: {[string]: any} = {}
-- UI_Server_Controller (Security Hardened)
-- Place as Script: ServerScriptService/UI_Server_Controller
--
-- Preserves the existing Club Music UI features and adds:
--   * Per-action, per-player token buckets, and server-wide RemoteEvent budgets.
--   * GetState RemoteFunction throttling and protected snapshot generation.
--   * Server-wide audio inspection budgets, bounded concurrency, and timeout cleanup.
--   * Strict finite-number / byte-length validation for custom title settings.
--   * Fail-closed profile loading (no default-profile overwrite after a DataStore error).
--   * Bounded profile write serialization, coalesced saves, and cross-server session leases.
--   * Durable, idempotent Developer Product receipt recording before PurchaseGranted.
--   * Preservation and size safeguards for the durable receipt ledger (never pruned).\n--   * Coalesced state broadcasts and bounded GetState snapshot work.
--
-- Keep this script server-side. Configure GroupId, StaffUserIds, audio allowlists,
-- and real Developer Product IDs before publishing. See the companion README.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")

local CONFIG = {
	GroupId = 0, -- Set to the Roblox group ID for rank/group features.
	RankThresholds = { Owner = 255, CoOwner = 254, Admin = 200, GroupDJ = 100 },

	-- Extra staff without needing a group (treated as OWNER).
	StaffUserIds = {} :: {number},
	-- In Studio every player is treated as OWNER so you can test the DJ booth.
	-- Set to false to test the normal guest experience in Studio.
	StudioStaff = true,

	-- VIP: any ONE of these grants VIP. Staff are always VIP. Staff can also grant temporary VIP in the DJ booth.
	VipGamePassId = 0,       -- Configure your VIP Game Pass ID.
	VvipGamePassId = 0,      -- Configure your VVIP Game Pass ID.
	TikiTideSultanPassId = 0,-- Configure your Tiki Tide Sultan Game Pass ID.
	VipGroupRank = 0,        -- Group rank that counts as VIP (0 = disabled; needs GroupId).
	VipPriority = true,      -- Pass holders receive tiered request priority.

	MaxRequestsPerPlayer = 2,
	VipMaxRequestsPerPlayer = 4,
	VvipMaxRequestsPerPlayer = 6,
	SultanMaxRequestsPerPlayer = 8,
	RequestCooldownSeconds = 8,
	VipCooldownSeconds = 3,
	VvipCooldownSeconds = 2,
	SultanCooldownSeconds = 1,
	MaxQueueSize = 40,         -- Max PLAYER requests waiting at once.

	AutoQueueTarget = 3,       -- Auto DJ keeps at least this many tracks visible in the queue.
	AutoAvoidRecent = 6,       -- Auto DJ will not repeat any of the last N tracks.

	SkipVoteRatio = 0.5,       -- Share of players needed to skip by vote.
	SkipVoteMin = 2,           -- Minimum votes (capped to the number of players in the server).

	MaxFavorites = 60,
	ResyncSeconds = 5,         -- Clients interpolate between resyncs, so we don't spam every second.
	ReloadCooldownSeconds = 3, -- Per-player cooldown for the "Reload song" button.

	DataStoreName = "SunsetStageClubProfiles_v1",
	SaveIntervalSeconds = 90,
	-- Studio defaults to session-only profiles so testing works even when
	-- "Enable Studio Access to API Services" is disabled. Set true only when
	-- you intentionally want Studio to use the live DataStore.
	StudioUseDataStore = false,

	-- Keep the legacy Sound as the default until the modern AudioPlayer route is validated in Studio.
	UseModernAudioBackend = false,
	CrossfadeDurationSeconds = 4,
	CrossfadePrepareLeadSeconds = 14,

	-- Optional audio. Map trackId -> "rbxassetid://123". Tracks without an entry play silently
	-- (the UI still shows progress and an animated visualizer).
	SoundIds = {} :: {[string]: string},

	-- Creator Hub audio requests (staff only). The server loads the audio to confirm it is playable and
	-- to read its real length before queueing it.
	AudioMaxSeconds = 600,
	AudioLoadTimeoutSeconds = 8,
	MaxConcurrentAudioInspections = 2,
	AudioInspectionCooldownSeconds = 10,
	GetStateCooldownSeconds = 0.75,
	SaveTitleCooldownSeconds = 2,

	-- Server-wide abuse / workload budgets. These are shared by every player.
	GlobalActionBurst = 180,
	GlobalActionRefillPerSecond = 90,
	PerPlayerActionBurst = 18,
	PerPlayerActionRefillPerSecond = 12,
	GlobalAudioBurst = 3,
	GlobalAudioRefillPerSecond = 0.25,
	GlobalStateMinIntervalSeconds = 0.2,
	ProfileWriteLockTimeoutSeconds = 12,
	ProfileSaveQueueDelaySeconds = 0.25,
	XPPerMinute = 10,
	XPPerLevel = 100,
	XPBoost2xProductId = 0,
	XPBoost4xProductId = 0,
	GlobalDataStoreBurst = 30,
	GlobalDataStoreRefillPerSecond = 3,
	RestrictAudioToAllowlist = false,           -- true = only IDs listed below can be requested.
	AllowedAudioAssetIds = {} :: {number},

	-- Title slots: slot 1 is free, slots 2 and 3 are Developer Products. 0 = not configured.
	TitleSlotProductIds = { [2] = 0, [3] = 0 } :: {[number]: number},
	TitleSlotPrices = { [2] = 99, [3] = 199 } :: {[number]: number}, -- Display only; set to match the products.
}

-- Publish the remote contract before loading storage modules so clients can
-- wait safely even when catalog initialization is delayed.
-- The catalog is server-owned. The controller remains the only authority
-- for request limits, moderation, queue priority, and playback.
ControllerFunctions.getOrCreate = function(parent: Instance, className: string, name: string): Instance
	local found = parent:FindFirstChild(name)
	if found and found.ClassName == className then return found end
	if found then found:Destroy() end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local remotes = ControllerFunctions.getOrCreate(ReplicatedStorage, "Folder", "ClubMusicRemotes") :: Folder
remotes:SetAttribute("Ready", false)
remotes:SetAttribute("StartupStage", "LoadingStorageModules")
remotes:SetAttribute("StartupError", nil)
local actionRemote = ControllerFunctions.getOrCreate(remotes, "RemoteEvent", "RequestAction") :: RemoteEvent
local stateRemote = ControllerFunctions.getOrCreate(remotes, "RemoteEvent", "StateChanged") :: RemoteEvent
local noticeRemote = ControllerFunctions.getOrCreate(remotes, "RemoteEvent", "Notice") :: RemoteEvent
local stateFunction = ControllerFunctions.getOrCreate(remotes, "RemoteFunction", "GetState") :: RemoteFunction
local catalogFunction = ControllerFunctions.getOrCreate(remotes, "RemoteFunction", "GetMusicCatalog") :: RemoteFunction
local playlistFunction = ControllerFunctions.getOrCreate(remotes, "RemoteFunction", "GetMusicPlaylists") :: RemoteFunction

local ServerStorage = game:GetService("ServerStorage")
-- Keep the established lowercase alias for existing storage-module loaders.
local serverStorage = ServerStorage

-- Diagnostics are optional: a missing handler must never prevent ClubMusic startup.
local diagnosticsModule = serverStorage:FindFirstChild("ClubMusicErrorHandler")
if diagnosticsModule and diagnosticsModule:IsA("ModuleScript") then
	local diagnosticsOk, diagnosticsResult = pcall(require, diagnosticsModule)
	if diagnosticsOk and typeof(diagnosticsResult) == "table"
		and typeof(diagnosticsResult.Report) == "function"
		and typeof(diagnosticsResult.SafeRequire) == "function"
		and typeof(diagnosticsResult.DescribeChildren) == "function" then
		ControllerFunctions.ErrorHandler = diagnosticsResult
	else
		warn("[ClubMusic][Diagnostics] ClubMusicErrorHandler failed validation/load; using built-in startup diagnostics. " .. tostring(diagnosticsResult))
	end
else
	warn("[ClubMusic][Diagnostics] Optional ServerStorage.ClubMusicErrorHandler ModuleScript is not installed; using built-in startup diagnostics.")
end

ControllerFunctions.reportStartupError = function(subsystem: string, operation: string, message: string, context: Instance?): string
	local errorId = "CM-STARTUP"
	local handler = ControllerFunctions.ErrorHandler
	if handler then
		local reportOk, reportResult = pcall(handler.Report, subsystem, operation, message, context)
		if reportOk and typeof(reportResult) == "string" then
			errorId = reportResult
		else
			warn("[ClubMusic][Diagnostics] Error handler reporting failed: " .. tostring(reportResult))
		end
	else
		warn("[ClubMusic][Error][" .. errorId .. "] " .. subsystem .. " / " .. operation .. ": " .. message)
		if context then
			warn("[ClubMusic][Diagnostics] Context=" .. context:GetFullName())
		end
	end
	local startupMessage = "[" .. errorId .. "] " .. string.sub(message, 1, 850)
	pcall(function()
		remotes:SetAttribute("StartupError", startupMessage)
	end)
	return errorId
end

remotes:SetAttribute("StartupStage", "LoadingMusicCatalogService")
local catalogModule = serverStorage:WaitForChild("MusicCatalogService", 20)
remotes:SetAttribute("StartupStage", "LoadingMusicPlaylistService")
local playlistModule = serverStorage:WaitForChild("MusicPlaylistService", 20)
if not catalogModule or not catalogModule:IsA("ModuleScript") then
	remotes:SetAttribute("StartupError", "Missing ServerStorage.MusicCatalogService ModuleScript.")
	error("[ClubMusic] Missing ServerStorage.MusicCatalogService ModuleScript.")
end
if not playlistModule or not playlistModule:IsA("ModuleScript") then
	remotes:SetAttribute("StartupError", "Missing ServerStorage.MusicPlaylistService ModuleScript.")
	error("[ClubMusic] Missing ServerStorage.MusicPlaylistService ModuleScript.")
end
local catalogRequireOk, catalogRequireResult = pcall(require, catalogModule)
if not catalogRequireOk then
	remotes:SetAttribute("StartupError", "MusicCatalogService require failed: " .. string.sub(tostring(catalogRequireResult), 1, 180))
	error("[ClubMusic] MusicCatalogService failed to load: " .. tostring(catalogRequireResult))
end
local playlistRequireOk, playlistRequireResult = pcall(require, playlistModule)
if not playlistRequireOk then
	remotes:SetAttribute("StartupError", "MusicPlaylistService require failed: " .. string.sub(tostring(playlistRequireResult), 1, 180))
	error("[ClubMusic] MusicPlaylistService failed to load: " .. tostring(playlistRequireResult))
end
local validationModule = serverStorage:WaitForChild("MusicValidationService", 20)
if not validationModule or not validationModule:IsA("ModuleScript") then
	remotes:SetAttribute("StartupError", "Missing ServerStorage.MusicValidationService ModuleScript.")
	error("[ClubMusic] Missing ServerStorage.MusicValidationService ModuleScript.")
end
local validationRequireOk, validationRequireResult = pcall(require, validationModule)
if not validationRequireOk then
	remotes:SetAttribute("StartupError", "MusicValidationService require failed: " .. string.sub(tostring(validationRequireResult), 1, 180))
	error("[ClubMusic] MusicValidationService failed to load: " .. tostring(validationRequireResult))
end

local MusicCatalogService = catalogRequireResult
local MusicPlaylistService = playlistRequireResult
local MusicValidationService = validationRequireResult
local musicValidation = MusicValidationService.new({
	CacheTTLSeconds = 300,
	MaxCacheEntries = 128,
}, function(assetId: number)
	return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset)
end)
remotes:SetAttribute("StartupStage", "InitializingStorage")

type Track = { id: string, genreId: string, title: string, artist: string, duration: number, genre: string, assetId: number?, soundId: string?, artworkAssetId: number? }

local TRACK_BY_ID: {[string]: Track} = {}
local ALL_TRACK_IDS: {string} = {}

local TAGS: {[string]: boolean} = {
	vip = true, party = true, wave = true, tiki = true, sunset = true, bass = true, island = true,
}

-- Custom title allowlists. These values are data keys, not client-supplied styles.
local TITLE_COLORS: {[string]: boolean} = {
	red = true,
	darkred = true,
	crimson = true,
	coral = true,
	rose = true,
	hotpink = true,
	pink = true,
	blue = true,
	darkblue = true,
	skyblue = true,
	navy = true,
	cyan = true,
	aqua = true,
	turquoise = true,
	green = true,
	darkgreen = true,
	lime = true,
	mint = true,
	emerald = true,
	olive = true,
	teal = true,
	purple = true,
	darkpurple = true,
	violet = true,
	lavender = true,
	magenta = true,
	indigo = true,
	yellow = true,
	gold = true,
	orange = true,
	darkorange = true,
	amber = true,
	peach = true,
	white = true,
	silver = true,
	gray = true,
	black = true,
	brown = true,
	tan = true,
	beige = true,
	maroon = true,
	lightpink = true,
	neoongreen = true,
	salmon = true,
	chartreuse = true,
	aquamarine = true,
	steelblue = true,
	deeppink = true,
	tomato = true,
	orchid = true,
	slateblue = true,
	chocolate = true,
	periwinkle = true,
	burntorange = true,
	midnightblue = true,
	springgreen = true,
	coralpink = true,
	plum = true,
	royalblue = true,
	mediumseagreen = true,
	darkviolet = true,
	deepskyblue = true,
	dodgerblue = true,
	cadetblue = true,
	slategray = true,
	dimgray = true,
	hotorange = true,
	lavenderpink = true,
	darkslateblue = true,
	mediumspringgreen = true,
	goldorange = true,
}
local TITLE_STYLES: {[string]: boolean} = {
	normal = true, bold = true, italic = true, outline = true,
}
-- Effect -> allowed color-set ids (must match the client's UI_Renderer lists).
local TITLE_SETS: {[string]: {[string]: boolean}} = {
	fixed = {
		red = true,
		darkred = true,
		crimson = true,
		coral = true,
		rose = true,
		hotpink = true,
		pink = true,
		blue = true,
		darkblue = true,
		skyblue = true,
		navy = true,
		cyan = true,
		aqua = true,
		turquoise = true,
		green = true,
		darkgreen = true,
		lime = true,
		mint = true,
		emerald = true,
		olive = true,
		teal = true,
		purple = true,
		darkpurple = true,
		violet = true,
		lavender = true,
		magenta = true,
		indigo = true,
		yellow = true,
		gold = true,
		orange = true,
		darkorange = true,
		amber = true,
		peach = true,
		white = true,
		silver = true,
		gray = true,
		black = true,
		brown = true,
		tan = true,
		beige = true,
		maroon = true,
		lightpink = true,
		neoongreen = true,
		salmon = true,
		chartreuse = true,
		aquamarine = true,
		steelblue = true,
		deeppink = true,
		tomato = true,
		orchid = true,
		slateblue = true,
		chocolate = true,
		periwinkle = true,
		burntorange = true,
		midnightblue = true,
		springgreen = true,
		coralpink = true,
		plum = true,
		royalblue = true,
		mediumseagreen = true,
		darkviolet = true,
		deepskyblue = true,
		dodgerblue = true,
		cadetblue = true,
		slategray = true,
		dimgray = true,
		hotorange = true,
		lavenderpink = true,
		darkslateblue = true,
		mediumspringgreen = true,
		goldorange = true,
	},
	rgb = { slow = true, normal = true, fast = true },
	gradient = { amethyst = true, aurora = true, candy = true, cotton = true, cyber = true, desert = true, emerald = true, fire = true, forest = true, galaxy = true, ice = true, lava = true, midnight = true, neon = true, ocean = true, pastel = true, purple = true, rosegold = true, royal = true, sakura = true, sapphire = true, sunset = true, thunder = true, tropical = true, volcano = true },
	rainbow = { classic = true, pastel = true, neon = true, deep = true, amethyst = true, aurora = true, candy = true, cotton = true, cyber = true, desert = true, emerald = true, fire = true, forest = true, galaxy = true, ice = true, lava = true, midnight = true, ocean = true, purple = true, rosegold = true, royal = true, sakura = true, sapphire = true, sunset = true, thunder = true, tropical = true, volcano = true },
	twotone = { amethyst = true, aurora = true, candy = true, cotton = true, cyber = true, desert = true, emerald = true, fire = true, forest = true, galaxy = true, ice = true, lava = true, midnight = true, neon = true, ocean = true, pastel = true, purple = true, rosegold = true, royal = true, sakura = true, sapphire = true, sunset = true, thunder = true, tropical = true, volcano = true },
	shimmer = { amethyst = true, aurora = true, candy = true, cotton = true, cyber = true, desert = true, emerald = true, fire = true, forest = true, galaxy = true, ice = true, lava = true, midnight = true, neon = true, ocean = true, pastel = true, purple = true, rosegold = true, royal = true, sakura = true, sapphire = true, sunset = true, thunder = true, tropical = true, volcano = true },
}
local TITLE_FONTS: {[string]: boolean} = {
	gotham = true, gothammed = true, source = true, ubuntu = true, roboto = true,
	fredoka = true, bangers = true, oswald = true, nunito = true, michroma = true,
	fantasy = true, arcade = true, scifi = true, code = true,
	-- Retain validation for previously saved titles while the editor offers the refreshed face set.
	cartoon = true, luckiest = true, marker = true, hand = true, retro = true,
}
-- Server-side colors so clients never choose raw colors.
local TITLE_HEX: {[string]: {[string]: {string}}} = {
	fixed = {
		red = {"#EF4444"},
		darkred = {"#8B0000"},
		crimson = {"#DC143C"},
		coral = {"#FF7F50"},
		rose = {"#F43F5E"},
		hotpink = {"#FF69B4"},
		pink = {"#EC4899"},
		blue = {"#3B82F6"},
		darkblue = {"#00008B"},
		skyblue = {"#87CEEB"},
		navy = {"#000080"},
		cyan = {"#00FFFF"},
		aqua = {"#00FFFF"},
		turquoise = {"#40E0D0"},
		green = {"#22C55E"},
		darkgreen = {"#006400"},
		lime = {"#00FF00"},
		mint = {"#98FFCC"},
		emerald = {"#50C878"},
		olive = {"#808000"},
		teal = {"#008080"},
		purple = {"#A855F7"},
		darkpurple = {"#301934"},
		violet = {"#8F00FF"},
		lavender = {"#E6E6FA"},
		magenta = {"#FF00FF"},
		indigo = {"#4B0082"},
		yellow = {"#FFFF00"},
		gold = {"#FFD700"},
		orange = {"#FFA500"},
		darkorange = {"#FF8C00"},
		amber = {"#FFBF00"},
		peach = {"#FFE5B4"},
		white = {"#FFFFFF"},
		silver = {"#C0C0C0"},
		gray = {"#808080"},
		black = {"#000000"},
		brown = {"#8B4513"},
		tan = {"#D2B48C"},
		beige = {"#F5F5DC"},
		maroon = {"#800000"},
		lightpink = {"#FFB6C1"},
		neoongreen = {"#39FF14"},
		salmon = {"#FA8072"},
		chartreuse = {"#7FFF00"},
		aquamarine = {"#7FFFD4"},
		steelblue = {"#4682B4"},
		deeppink = {"#FF1493"},
		tomato = {"#FF6347"},
		orchid = {"#DA70D6"},
		slateblue = {"#6A5ACD"},
		chocolate = {"#D2691E"},
		periwinkle = {"#CCCCFF"},
		burntorange = {"#CC5500"},
		midnightblue = {"#191970"},
		springgreen = {"#00FF7F"},
		coralpink = {"#F88379"},
		plum = {"#DDA0DD"},
		royalblue = {"#4169E1"},
		mediumseagreen = {"#3CB371"},
		darkviolet = {"#9400D3"},
		deepskyblue = {"#00BFFF"},
		dodgerblue = {"#1E90FF"},
		cadetblue = {"#5F9EA0"},
		slategray = {"#708090"},
		dimgray = {"#696969"},
		hotorange = {"#FF4500"},
		lavenderpink = {"#FBAED2"},
		darkslateblue = {"#483D8B"},
		mediumspringgreen = {"#00FA9A"},
		goldorange = {"#DAA520"},
	},
	gradient = {
		amethyst = {"#C084FC", "#6D28D9"},
		aurora = {"#34D399", "#A78BFA"},
		candy = {"#FF4FA3", "#7DD3FC"},
		cotton = {"#FBCFE8", "#E0F2FE"},
		cyber = {"#00F5FF", "#FF00D4"},
		desert = {"#F4A261", "#E9C46A"},
		emerald = {"#34D399", "#047857"},
		fire = {"#FDE047", "#DC2626"},
		forest = {"#86A86B", "#14532D"},
		galaxy = {"#312E81", "#D946EF"},
		ice = {"#E0F7FF", "#60A5FA"},
		lava = {"#FB923C", "#7F1D1D"},
		midnight = {"#1E1B4B", "#475569"},
		neon = {"#00F0FF", "#FF2E93"},
		ocean = {"#00F0FF", "#2563EB"},
		pastel = {"#F9A8D4", "#A5B4FC"},
		purple = {"#C084FC", "#581C87"},
		rosegold = {"#F4B6A6", "#B76E79"},
		royal = {"#FCD34D", "#7C3AED"},
		sakura = {"#FDA4AF", "#FCE7F3"},
		sapphire = {"#60A5FA", "#1E40AF"},
		sunset = {"#FF8C00", "#FF2E93"},
		thunder = {"#FDE047", "#4338CA"},
		tropical = {"#2DD4BF", "#FACC15"},
		volcano = {"#FB7185", "#7F1D1D"},
	},
	twotone = {
		amethyst = {"#C084FC", "#6D28D9"},
		aurora = {"#34D399", "#A78BFA"},
		candy = {"#FF4FA3", "#7DD3FC"},
		cotton = {"#FBCFE8", "#E0F2FE"},
		cyber = {"#00F5FF", "#FF00D4"},
		desert = {"#F4A261", "#E9C46A"},
		emerald = {"#34D399", "#047857"},
		fire = {"#FDE047", "#DC2626"},
		forest = {"#86A86B", "#14532D"},
		galaxy = {"#312E81", "#D946EF"},
		ice = {"#E0F7FF", "#60A5FA"},
		lava = {"#FB923C", "#7F1D1D"},
		midnight = {"#1E1B4B", "#475569"},
		neon = {"#00F0FF", "#FF2E93"},
		ocean = {"#00F0FF", "#2563EB"},
		pastel = {"#F9A8D4", "#A5B4FC"},
		purple = {"#C084FC", "#581C87"},
		rosegold = {"#F4B6A6", "#B76E79"},
		royal = {"#FCD34D", "#7C3AED"},
		sakura = {"#FDA4AF", "#FCE7F3"},
		sapphire = {"#60A5FA", "#1E40AF"},
		sunset = {"#FF8C00", "#FF2E93"},
		thunder = {"#FDE047", "#4338CA"},
		tropical = {"#2DD4BF", "#FACC15"},
		volcano = {"#FB7185", "#7F1D1D"},
	},
	shimmer = {
		amethyst = {"#C084FC", "#6D28D9"},
		aurora = {"#34D399", "#A78BFA"},
		candy = {"#FF4FA3", "#7DD3FC"},
		cotton = {"#FBCFE8", "#E0F2FE"},
		cyber = {"#00F5FF", "#FF00D4"},
		desert = {"#F4A261", "#E9C46A"},
		emerald = {"#34D399", "#047857"},
		fire = {"#FDE047", "#DC2626"},
		forest = {"#86A86B", "#14532D"},
		galaxy = {"#312E81", "#D946EF"},
		ice = {"#E0F7FF", "#60A5FA"},
		lava = {"#FB923C", "#7F1D1D"},
		midnight = {"#1E1B4B", "#475569"},
		neon = {"#00F0FF", "#FF2E93"},
		ocean = {"#00F0FF", "#2563EB"},
		pastel = {"#F9A8D4", "#A5B4FC"},
		purple = {"#C084FC", "#581C87"},
		rosegold = {"#F4B6A6", "#B76E79"},
		royal = {"#FCD34D", "#7C3AED"},
		sakura = {"#FDA4AF", "#FCE7F3"},
		sapphire = {"#60A5FA", "#1E40AF"},
		sunset = {"#FF8C00", "#FF2E93"},
		thunder = {"#FDE047", "#4338CA"},
		tropical = {"#2DD4BF", "#FACC15"},
		volcano = {"#FB7185", "#7F1D1D"},
	},
}
local RAINBOW_PARAMS: {[string]: {number}} = { classic = {0.85, 1}, pastel = {0.4, 1}, neon = {1, 1}, deep = {1, 0.8} }
local RGB_SPEED: {[string]: number} = { slow = 0.12, normal = 0.25, fast = 0.5 }

local MAX_CUSTOM_TITLE_LENGTH = 24
local TITLE_SLOT_COUNT = 3

ControllerFunctions.truncateUtf8 = function(value: string, maxCharacters: number): string
	local boundary = utf8.offset(value, maxCharacters + 1)
	if boundary then
		return string.sub(value, 1, boundary - 1)
	end
	return value
end
local DAILY_REWARD_COUNT = 7
local store = DataStoreService:GetDataStore(CONFIG.DataStoreName)
local USE_STUDIO_MEMORY_PROFILES = RunService:IsStudio() and not CONFIG.StudioUseDataStore
local SESSION_LOCK_SECONDS = 180

if USE_STUDIO_MEMORY_PROFILES then
	warn("[ClubMusic] Studio in-memory profile mode is active. DataStore access is skipped; profile changes will not persist after this Studio server session.")
end
local SESSION_TOKEN = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)
local random = Random.new()

-- One server-owned Sound drives the entire server. Reuse the supplied
-- SoundService.ServerMusicSound and SoundService.MusicGroup instances so the
-- existing assets are not shadowed by duplicate playback objects.
-- The controller remains the only playback authority; clients may adjust the
-- canonical SoundGroup locally for their own volume preference.
local musicSoundGroup = ControllerFunctions.getOrCreate(SoundService, "SoundGroup", "MusicGroup") :: SoundGroup
local musicSound = ControllerFunctions.getOrCreate(SoundService, "Sound", "ServerMusicSound") :: Sound
local activeAudioSource: any = { kind = "Sound", instance = musicSound }
local audioSourceRevision = 0
local modernAudioMigrationAttempted = false
-- Forward-declared state is shared with the early-created crossfade factory.
local queue: any = {}
local queueManager: any = nil
local globalQueueMode = false
local globalTrackRevision = 0
ControllerFunctions.globalPlaybackEndTime = 0
local localCatalogRevision = 0
local syncGlobalQueueSnapshot: (() -> boolean)? = nil
local refreshLocalCatalog: (() -> boolean)? = nil
local enqueueGlobalQueueEntry: ((QueueEntry) -> (boolean, string?))? = nil
local nowPlaying: any = nil
local publishState: (Player?) -> () = function(_player: Player?) end
local pendingCrossfadeEntry: any = nil
local pendingCrossfadeToken = -1
ControllerFunctions.pendingCrossfadeGlobalRevision = -1
ControllerFunctions.pendingCrossfadeGlobalCommitted = false
ControllerFunctions.pendingCrossfadeDeadline = 0
local audioTransitionTrackToken = 0

-- Migrate any legacy ClubMusic-routed sounds to the supplied canonical group.
-- This preserves other SoundService audio while removing the obsolete group.
local legacyMusicGroup = SoundService:FindFirstChild("ClubMusic")
if legacyMusicGroup and legacyMusicGroup:IsA("SoundGroup") and legacyMusicGroup ~= musicSoundGroup then
	for _, descendant in ipairs(SoundService:GetDescendants()) do
		if descendant:IsA("Sound") and descendant.SoundGroup == legacyMusicGroup then
			descendant.SoundGroup = musicSoundGroup
		end
	end
	legacyMusicGroup:Destroy()
end

musicSound.SoundGroup = musicSoundGroup
musicSound.Volume = 1
musicSound.Looped = false
musicSound.PlaybackSpeed = 1
musicSoundGroup.Volume = 1
musicSound:SetAttribute("ManagedByClubMusicController", true)

-- Publish the number of active controller-owned main outputs (0 or 1).
-- The binding is refreshed whenever the canonical source changes.
local activeAudioPlayingConnection: RBXScriptConnection? = nil
ControllerFunctions.refreshActiveMusicSoundCount = function()
	local snapshot = ControllerFunctions.getAudioSnapshot and ControllerFunctions.getAudioSnapshot() or nil
	local playing = typeof(snapshot) == "table" and snapshot.playing == true
	SoundService:SetAttribute("ActiveMusicSoundCount", if playing then 1 else 0)
end
ControllerFunctions.bindActiveAudioPlayingSignal = function()
	if activeAudioPlayingConnection then
		activeAudioPlayingConnection:Disconnect()
		activeAudioPlayingConnection = nil
	end
	local source = activeAudioSource
	local signalInstance = if source.kind == "Backend" and source.backend
		then source.backend:GetPlayer() else source.instance
	if typeof(signalInstance) == "Instance" then
		local propertyName = if source.kind == "Backend" then "IsPlaying" else "Playing"
		local ok, signal = pcall(function() return signalInstance:GetPropertyChangedSignal(propertyName) end)
		if ok and signal then
			activeAudioPlayingConnection = signal:Connect(ControllerFunctions.refreshActiveMusicSoundCount)
		end
	end
	ControllerFunctions.refreshActiveMusicSoundCount()
end

local playbackPaused = false
local lastGlobalPlaybackRevision = 0

-- One controller-owned source contract. The legacy Sound remains the active
-- implementation until every route is migrated and a Studio cutover is validated.
ControllerFunctions.getAudioSnapshot = function()
	local source = activeAudioSource
	if typeof(source) ~= "table" then
		return { kind = "Unavailable", ready = false, playing = false, paused = playbackPaused, position = 0, length = 0, asset = "" }
	end
	if source.kind == "Backend" and source.backend then
		local backend = source.backend
		local function read(methodName: string, fallback: any)
			local ok, value = pcall(function() return backend[methodName](backend) end)
			return if ok then value else fallback
		end
		local player = read("GetPlayer", nil)
		local asset = ""
		if player then pcall(function() asset = tostring(player.Asset) end) end
		return {
			kind = "AudioPlayer",
			ready = read("IsReady", false) == true,
			playing = read("IsPlaying", false) == true,
			paused = playbackPaused,
			position = math.max(0, tonumber(read("GetTimePosition", 0)) or 0),
			length = math.max(0, tonumber(read("GetTimeLength", 0)) or 0),
			asset = asset,
		}
	end
	local sound = source.instance
	if typeof(sound) ~= "Instance" or not sound:IsA("Sound") or sound.Parent == nil then
		return { kind = "Unavailable", ready = false, playing = false, paused = playbackPaused, position = 0, length = 0, asset = "" }
	end
	return {
		kind = "Sound",
		ready = sound.IsLoaded,
		playing = sound.IsPlaying,
		paused = playbackPaused,
		position = math.max(0, sound.TimePosition),
		length = math.max(0, sound.TimeLength),
		asset = sound.SoundId,
	}
end
-- Gain is owned by the active source. Keep the crossfade/profile contract
-- backend-neutral so a transition never assumes the outgoing deck is at 100%.
ControllerFunctions.getAudioGain = function(sourceOverride: any?): (boolean, number)
	local source = sourceOverride or activeAudioSource
	if typeof(source) ~= "table" then return false, 0 end
	if source.kind == "Backend" and source.backend then
		local ok, value = pcall(function() return source.backend:GetGain() end)
		if not ok or typeof(value) ~= "number" or not ControllerFunctions.isFiniteNumber(value)
			or value < 0 or value > 1 then return false, 0 end
		return true, value
	end
	local sound = source.instance
	if typeof(sound) ~= "Instance" or not sound:IsA("Sound") or sound.Parent == nil then return false, 0 end
	local value = sound.Volume
	if not ControllerFunctions.isFiniteNumber(value) or value < 0 or value > 1 then return false, 0 end
	return true, value
end
ControllerFunctions.setAudioGain = function(value: number, sourceOverride: any?): boolean
	if not ControllerFunctions.isFiniteNumber(value) or value < 0 or value > 1 then return false end
	local source = sourceOverride or activeAudioSource
	if typeof(source) ~= "table" then return false end
	if source.kind == "Backend" and source.backend then
		local ok, result = pcall(function() return source.backend:SetGain(value) end)
		return ok and result ~= false
	end
	local sound = source.instance
	if typeof(sound) ~= "Instance" or not sound:IsA("Sound") or sound.Parent == nil then return false end
	local ok = pcall(function() sound.Volume = value end)
	return ok
end

ControllerFunctions.setAudioAsset = function(asset: string)
	audioSourceRevision += 1
	local source = activeAudioSource
	if source.kind == "Backend" then return source.backend:SetAsset(asset) end
	source.instance.SoundId = asset
	return true, nil
end
ControllerFunctions.seekAudio = function(position: number)
	audioSourceRevision += 1
	local source = activeAudioSource
	if source.kind == "Backend" then return source.backend:Seek(position) end
	source.instance.TimePosition = position
	return true, nil
end
ControllerFunctions.playAudio = function()
	audioSourceRevision += 1
	local source = activeAudioSource
	if source.kind == "Backend" then return source.backend:Play() end
	source.instance:Play()
	return true, nil
end
ControllerFunctions.stopAudio = function()
	audioSourceRevision += 1
	local source = activeAudioSource
	if source.kind == "Backend" then return source.backend:Stop() end
	source.instance:Stop()
	return true, nil
end
ControllerFunctions.pauseAudio = function()
	audioSourceRevision += 1
	local source = activeAudioSource
	if source.kind == "Backend" then return source.backend:Pause() end
	source.instance:Pause()
	return true, nil
end
ControllerFunctions.resumeAudio = function()
	audioSourceRevision += 1
	local source = activeAudioSource
	if source.kind == "Backend" then return source.backend:Resume() end
	source.instance:Resume()
	return true, nil
end

-- Replace the canonical source only after a prepared backend is ready and can
-- start silently. On any failure, restore the previous source and playhead.
-- This seam is intentionally not called during startup; Studio cutover testing
-- is still required before any production enablement.
ControllerFunctions.adoptAudioBackend = function(candidate: any): (boolean, string?)
	if typeof(candidate) ~= "table" then return false, "A prepared audio backend is required." end
	for _, methodName in ipairs({ "IsReady", "IsPlaying", "GetTimePosition", "GetTimeLength", "GetPlayer", "SetAsset", "SetGain", "Play", "Stop", "Pause", "Resume", "Seek", "Cleanup" }) do
		if typeof(candidate[methodName]) ~= "function" then return false, "Audio backend is missing " .. methodName .. "." end
	end
	local playerOk, player = pcall(function() return candidate:GetPlayer() end)
	if not playerOk or typeof(player) ~= "Instance" or not player:IsA("AudioPlayer") then
		return false, "Incoming audio backend has no valid AudioPlayer."
	end
	if activeAudioSource.kind == "Backend" and activeAudioSource.backend == candidate then
		return false, "The candidate is already the active audio backend."
	end

	local outgoing = activeAudioSource
	local outgoingSnapshot = ControllerFunctions.getAudioSnapshot()
	local asset = tostring(outgoingSnapshot.asset or "")
	if asset == "" then return false, "There is no active track to transfer." end
	local position = math.max(0, tonumber(outgoingSnapshot.position) or 0)
	local wasPaused = playbackPaused == true
	local wasPlaying = outgoingSnapshot.playing == true and not wasPaused
	if not wasPlaying and not wasPaused then
		return false, "Outgoing audio is not playing; handoff was not committed."
	end
	local expectedRevision = audioSourceRevision
	ControllerFunctions.cancelAudioTransition("audio-source-adoption")

	local function candidateCleanup()
		pcall(function() candidate:Stop() end)
		pcall(function() candidate:Cleanup() end)
	end
	local function outgoingStillCurrent(): boolean
		local current = ControllerFunctions.getAudioSnapshot()
		return activeAudioSource == outgoing
			and audioSourceRevision == expectedRevision
			and current.asset == asset
			and playbackPaused == wasPaused
	end
	local function restoreOutgoing(): boolean
		local ok, result = pcall(function()
			if outgoing.kind == "Backend" then
				local started, message = outgoing.backend:Play(asset, position)
				if started ~= true then error(message or "Previous backend could not restart.") end
				if wasPaused then
					local paused, pauseMessage = outgoing.backend:Pause()
					if paused ~= true then error(pauseMessage or "Previous backend could not restore pause.") end
				end
			else
				outgoing.instance.SoundId = asset
				outgoing.instance.TimePosition = position
				outgoing.instance:Play()
				if wasPaused then outgoing.instance:Pause() end
			end
		end)
		return ok and result ~= false
	end

	local outgoingGainOk, outgoingGain = ControllerFunctions.getAudioGain(outgoing)
	if not outgoingGainOk then
		candidateCleanup()
		return false, "Outgoing audio gain could not be read safely."
	end
	local gainOk, gainResult = pcall(function() return candidate:SetGain(0) end)
	if not gainOk or gainResult == false then
		candidateCleanup()
		return false, "Incoming audio backend could not be muted for handoff."
	end
	local assetOk, assetResult = pcall(function() return candidate:SetAsset(asset) end)
	if not assetOk or assetResult == false then
		candidateCleanup()
		return false, "Incoming audio backend could not load the current asset."
	end

	local deadline = os.clock() + 8
	local ready = false
	while os.clock() < deadline do
		if not outgoingStillCurrent() then
			candidateCleanup()
			return false, "Playback changed while the incoming backend was loading."
		end
		local readyOk, readyValue = pcall(function() return candidate:IsReady() end)
		if readyOk and readyValue == true then ready = true; break end
		task.wait(0.1)
	end
	if not ready then
		candidateCleanup()
		return false, "Incoming audio backend did not become ready before the handoff timeout."
	end
	if not outgoingStillCurrent() then
		candidateCleanup()
		return false, "Playback changed before the audio handoff could start."
	end

	local playOk, playResult = pcall(function() return candidate:Play(nil, position) end)
	if not playOk or playResult == false then
		candidateCleanup()
		return false, "Incoming audio backend could not start for handoff."
	end
	if wasPaused then
		local pauseOk, pauseResult = pcall(function() return candidate:Pause() end)
		if not pauseOk or pauseResult == false then
			candidateCleanup()
			return false, "Incoming audio backend could not preserve the paused state."
		end
	end

	-- Re-check immediately before source ownership changes. No yielding occurs
	-- between this check, stopping the outgoing source, and committing the swap.
	if not outgoingStillCurrent() then
		candidateCleanup()
		return false, "Playback changed before the audio handoff could commit."
	end
	local outgoingStopOk, outgoingStopResult = pcall(function()
		if outgoing.kind == "Backend" then return outgoing.backend:Stop() end
		outgoing.instance:Stop()
		return true
	end)
	if not outgoingStopOk or outgoingStopResult == false then
		candidateCleanup()
		restoreOutgoing()
		return false, "Outgoing audio could not be stopped; the previous source was restored."
	end

	local fullGainOk, fullGainResult = pcall(function() return candidate:SetGain(outgoingGain) end)
	if not fullGainOk or fullGainResult == false then
		restoreOutgoing()
		candidateCleanup()
		return false, "Incoming gain could not be restored; the previous source was restored."
	end

	activeAudioSource = { kind = "Backend", backend = candidate }
	ControllerFunctions.bindActiveAudioPlayingSignal()
	if outgoing.kind == "Backend" and outgoing.backend ~= candidate then
		pcall(function() outgoing.backend:Cleanup() end)
	end
	return true, nil
end

ControllerFunctions.bindActiveAudioPlayingSignal()

-- Optional one-time migration after the first valid track starts. Disabled by
-- default; if preparation or handoff fails, adoptAudioBackend cleans the
-- candidate and the canonical Sound continues without interruption.
ControllerFunctions.tryModernAudioBackendMigration = function()
	if not CONFIG.UseModernAudioBackend or modernAudioMigrationAttempted then return false end
	modernAudioMigrationAttempted = true
	local modules = ServerStorage:FindFirstChild("ClubMusicAudioModules")
	local backendModule = modules and modules:FindFirstChild("ClubMusicAudioBackend")
	if not backendModule or not backendModule:IsA("ModuleScript") then
		warn("[ClubMusic][AudioBackend] Modern backend is enabled but its ModuleScript is missing; legacy Sound remains active.")
		return false
	end
	local requireOk, BackendClass = pcall(require, backendModule)
	if not requireOk or typeof(BackendClass) ~= "table" or typeof(BackendClass.new) ~= "function" then
		warn("[ClubMusic][AudioBackend] Modern backend could not be loaded; legacy Sound remains active.")
		return false
	end
	local createOk, candidate = pcall(BackendClass.new, {
		Name = "ClubMusicMainAudioBackend",
		Parent = SoundService,
		InitialGain = 0,
	})
	if not createOk or typeof(candidate) ~= "table" then
		warn("[ClubMusic][AudioBackend] Modern backend could not be constructed; legacy Sound remains active.")
		return false
	end
	local adopted, message = ControllerFunctions.adoptAudioBackend(candidate)
	if not adopted then
		warn("[ClubMusic][AudioBackend] Safe handoff was rejected; legacy Sound remains active: " .. tostring(message))
		return false
	end
	print("[ClubMusic][AudioBackend] Modern AudioPlayer is now the controller-owned main source.")
	return true
end

-- One controller-owned cancellation seam for a future dual-deck transition.
-- It is deliberately a no-op until a Crossfade manager is safely constructed.
ControllerFunctions.cancelAudioTransition = function(reason: string?)
	local managers = ControllerFunctions.ChildManagers
	local crossfade = managers and managers.Crossfade
	if not crossfade then return true end
	local ok, result = pcall(function()
		return crossfade:Cancel(reason)
	end)
	if not ok or result == false then
		warn("[ClubMusic] Audio transition cancellation reported a failure (" .. tostring(reason or "unspecified") .. "): " .. tostring(result))
		return false
	end
	pendingCrossfadeEntry = nil
	pendingCrossfadeToken = -1
	ControllerFunctions.pendingCrossfadeGlobalRevision = -1
	ControllerFunctions.pendingCrossfadeGlobalCommitted = false
	ControllerFunctions.pendingCrossfadeDeadline = 0
	return true
end

-- Destroy the optional coordinator explicitly during teardown. Cleanup invalidates
-- any waiting transition, destroys its incoming deck, and restores outgoing gain.
ControllerFunctions.destroyAudioCrossfadeManager = function(reason: string?): (boolean, string?)
	local managers = ControllerFunctions.ChildManagers
	local crossfade = managers and managers.Crossfade
	if not crossfade then return true, nil end
	local ok, result, detail = pcall(function()
		return crossfade:Cleanup()
	end)
	-- Cleanup permanently destroys this manager even when it reports a resource
	-- cleanup failure, so never leave a dead instance registered as reusable.
	if managers.Crossfade == crossfade then
		managers.Crossfade = nil
	end
	if not ok or result == false then
		warn("[ClubMusic] Audio crossfade cleanup failed (" .. tostring(reason or "unspecified") .. "): " .. tostring(detail or result))
		return false, "Audio crossfade manager cleanup failed."
	end
	return true, nil
end

-- Explicit, dormant factory for the controller-owned dual-deck coordinator.
-- Nothing is constructed at startup; Studio validation must precede any call.
ControllerFunctions.createAudioCrossfadeManager = function(): (boolean, string?)
	local managers = ControllerFunctions.ChildManagers
	if typeof(managers) ~= "table" then return false, "Audio manager registry is unavailable." end
	if managers.Crossfade then return false, "An audio crossfade manager already exists." end
	local modules = ServerStorage:FindFirstChild("ClubMusicAudioModules")
	if not modules or not modules:IsA("Folder") then
		return false, "ServerStorage.ClubMusicAudioModules is not installed."
	end
	local backendModule = modules:FindFirstChild("ClubMusicAudioBackend")
	local crossfadeModule = modules:FindFirstChild("ClubMusicAudioCrossfadeManager")
	if not backendModule or not backendModule:IsA("ModuleScript")
		or not crossfadeModule or not crossfadeModule:IsA("ModuleScript") then
		return false, "Audio backend and crossfade ModuleScripts are both required."
	end
	local backendOk, BackendClass = pcall(require, backendModule)
	local managerOk, ManagerClass = pcall(require, crossfadeModule)
	if not backendOk or typeof(BackendClass) ~= "table" or typeof(BackendClass.new) ~= "function"
		or not managerOk or typeof(ManagerClass) ~= "table" or typeof(ManagerClass.new) ~= "function" then
		return false, "Audio backend or crossfade module failed validation."
	end
	local transitionOutgoing = nil
	local transitionRevision = nil
	local context = {
		CreateDeck = function()
			return BackendClass.new({ Name = "ClubMusicCrossfadeDeck", Parent = game:GetService("SoundService"), InitialGain = 0 })
		end,
		GetRemainingTime = function()
			if globalQueueMode and ControllerFunctions.pendingCrossfadeGlobalRevision >= 0 and ControllerFunctions.pendingCrossfadeDeadline > 0 then
				return math.max(0, ControllerFunctions.pendingCrossfadeDeadline - game:GetService("Workspace"):GetServerTimeNow())
			end
			if not nowPlaying then return 0 end
			return math.max(0, (tonumber(nowPlaying.duration) or 0) - (tonumber(nowPlaying.elapsed) or 0))
		end,
		GetOutgoingGain = function()
			transitionOutgoing = activeAudioSource
			transitionRevision = audioSourceRevision
			local ok, value = ControllerFunctions.getAudioGain(transitionOutgoing)
			if not ok then error("Outgoing audio gain is unavailable.") end
			ControllerFunctions.crossfadeOutgoingBaseGain = value
			return value
		end,
		SetOutgoingGain = function(value: number)
			if not transitionOutgoing or activeAudioSource ~= transitionOutgoing
				or audioSourceRevision ~= transitionRevision then return false end
			return ControllerFunctions.setAudioGain(value, transitionOutgoing)
		end,
		OnCommit = function(incoming: any): boolean
			local outgoing = transitionOutgoing
			local entry = pendingCrossfadeEntry
			if not outgoing or activeAudioSource ~= outgoing
				or audioSourceRevision ~= transitionRevision or playbackPaused
				or not entry or pendingCrossfadeToken ~= audioTransitionTrackToken then
				return false
			end
			local playerOk, player = pcall(function() return incoming:GetPlayer() end)
			if not playerOk or typeof(player) ~= "Instance" or not player:IsA("AudioPlayer")
				or not player.IsPlaying then return false end
			local isGlobalTransition = globalQueueMode
			if isGlobalTransition then
				if ControllerFunctions.pendingCrossfadeGlobalRevision < 0 then return false end
				local queueHeadMatches = queue[1] ~= nil and queue[1].id == entry.id
					and globalTrackRevision == ControllerFunctions.pendingCrossfadeGlobalRevision
				if not queueHeadMatches and not ControllerFunctions.pendingCrossfadeGlobalCommitted then return false end
				-- Re-read through the CAS even if a MessagingService snapshot already
				-- announced the commit. This confirms no later skip/restart replaced
				-- the prepared track before this server finishes its local handoff.
				local callOk, didAdvance, state, message = ControllerFunctions.globalInvoke(
					"AdvanceGlobalQueue", ControllerFunctions.pendingCrossfadeGlobalRevision, nil,
					localCatalogRevision, entry.id
				)
				if typeof(state) == "table" then ControllerFunctions.applyGlobalQueueState(state) end
				local committedEntry = if typeof(state) == "table" then state.current else nil
				local committed = typeof(committedEntry) == "table"
					and committedEntry.id == entry.id
					and typeof(state.playback) == "table"
					and tonumber(state.playback.trackRevision) > ControllerFunctions.pendingCrossfadeGlobalRevision
				if not committed and syncGlobalQueueSnapshot then
					local syncOk = syncGlobalQueueSnapshot()
					committed = syncOk == true and ControllerFunctions.pendingCrossfadeGlobalCommitted == true
				end
				if not committed then
					if not callOk then warn("[ClubMusic][Crossfade] Global queue commit unavailable: " .. tostring(didAdvance)) end
					if didAdvance ~= true and message then
						warn("[ClubMusic][Crossfade] Global queue did not commit the prepared entry: " .. tostring(message))
					end
					return false
				end
			elseif queue[1] ~= entry then
				return false
			end

			-- If the global CAS has committed but a local source operation fails,
			-- continue the authoritative track on the existing controller source.
			-- The manager will treat this as a completed fallback and will not leak
			-- the already-prepared incoming deck.
			local function recoverCommittedGlobalTrack(): boolean
				if not isGlobalTransition then return false end
				activeAudioSource = outgoing
				pcall(ControllerFunctions.bindActiveAudioPlayingSignal)
				local baseGain = tonumber(ControllerFunctions.crossfadeOutgoingBaseGain) or 1
				pcall(function() ControllerFunctions.setAudioGain(math.clamp(baseGain, 0, 1), outgoing) end)
				ControllerFunctions.setNowPlaying(entry, true)
				local fallbackAsset = entry.soundId or CONFIG.SoundIds[entry.trackId] or ""
				ControllerFunctions.startServerMusic(fallbackAsset)
				pcall(function() incoming:Stop() end)
				local cleanupOk, cleanupResult = pcall(function() return incoming:Cleanup() end)
				if not cleanupOk or cleanupResult == false then
					warn("[ClubMusic][Crossfade] Incoming deck cleanup failed after global fallback.")
				end
				task.defer(function()
					ControllerFunctions.topUpAuto()
					publishState(nil)
				end)
				return true
			end

			-- Stop the outgoing source before changing ownership. If it cannot be
			-- stopped, leave the old source authoritative so Cancel can restore gain.
			local outgoingSnapshot = ControllerFunctions.getAudioSnapshot()
			local outgoingWasPlaying = typeof(outgoingSnapshot) == "table" and outgoingSnapshot.playing == true
			local outgoingPosition = if typeof(outgoingSnapshot) == "table"
				then math.max(0, tonumber(outgoingSnapshot.position) or 0) else 0
			local stopOk, stopResult = pcall(function()
				if outgoing.kind == "Backend" and outgoing.backend then
					return outgoing.backend:Stop()
				elseif outgoing.kind == "Sound" and outgoing.instance
					and outgoing.instance:IsA("Sound") then
					outgoing.instance:Stop()
					return not outgoing.instance.IsPlaying
				end
				return false
			end)
			if not stopOk or stopResult == false then
				if recoverCommittedGlobalTrack() then return true end
				return false
			end

			activeAudioSource = { kind = "Backend", backend = incoming }
			local bindOk = pcall(ControllerFunctions.bindActiveAudioPlayingSignal)
			if not bindOk then
				activeAudioSource = outgoing
				pcall(ControllerFunctions.bindActiveAudioPlayingSignal)
				if recoverCommittedGlobalTrack() then return true end
				if outgoingWasPlaying then
					pcall(function()
						if outgoing.kind == "Backend" then
							outgoing.backend:Play(nil, outgoingPosition)
						elseif outgoing.kind == "Sound" then
							outgoing.instance.TimePosition = outgoingPosition
							outgoing.instance:Play()
						end
					end)
				end
				return false
			end

			-- Local mode owns a mutable queue table. Global mode has already
			-- committed the exact entry through the shared DataStore CAS above.
			local popOk, popped = true, entry
			if not isGlobalTransition then
				popOk, popped = pcall(function()
					if not queueManager then return nil end
					return queueManager:PopNext()
				end)
			end
			if not popOk or popped ~= entry then
				activeAudioSource = outgoing
				pcall(ControllerFunctions.bindActiveAudioPlayingSignal)
				if outgoingWasPlaying then
					pcall(function()
						if outgoing.kind == "Backend" then outgoing.backend:Play(nil, outgoingPosition)
						elseif outgoing.kind == "Sound" then outgoing.instance.TimePosition = outgoingPosition; outgoing.instance:Play() end
					end)
				end
				return false
			end
			audioSourceRevision += 1
			ControllerFunctions.setNowPlaying(entry, true)
			ControllerFunctions.pendingCrossfadeGlobalRevision = -1
			ControllerFunctions.pendingCrossfadeGlobalCommitted = false
			ControllerFunctions.pendingCrossfadeDeadline = 0
			task.defer(function()
				ControllerFunctions.topUpAuto()
				publishState(nil)
			end)
			if outgoing.kind == "Backend" and outgoing.backend ~= incoming then
				pcall(function() outgoing.backend:Cleanup() end)
			end
			return true
		end,
	}
	local managerCreateOk, manager = pcall(ManagerClass.new, context)
	if not managerCreateOk or typeof(manager) ~= "table"
		or typeof(manager.Begin) ~= "function" or typeof(manager.Cancel) ~= "function"
		or typeof(manager.Cleanup) ~= "function" then
		return false, "Crossfade manager could not be constructed safely."
	end
	managers.Crossfade = manager
	return true, nil
end

-- Explicit transition entry point. This does not alter queue state or run
-- automatically; callers must provide a validated catalog asset and duration.
ControllerFunctions.beginAudioCrossfade = function(asset: string, duration: number): (boolean, string?)
	local managers = ControllerFunctions.ChildManagers
	local crossfade = managers and managers.Crossfade
	if not crossfade then return false, "Audio crossfade manager is not initialized." end
	if playbackPaused then return false, "Cannot crossfade while playback is paused." end
	local snapshot = ControllerFunctions.getAudioSnapshot()
	if typeof(snapshot) ~= "table" or snapshot.playing ~= true then
		return false, "The active music source is not playing."
	end
	if typeof(asset) ~= "string" or #asset > 64
		or not string.match(asset, "^rbxassetid://%d+$") then
		return false, "Invalid incoming audio asset."
	end
	if typeof(duration) ~= "number" or duration ~= duration
		or duration < 0.25 or duration > 12 then
		return false, "Crossfade duration must be between 0.25 and 12 seconds."
	end
	local ok, result, detail = pcall(function()
		return crossfade:Begin(asset, duration)
	end)
	if not ok then
		return false, "Audio crossfade could not be started safely."
	end
	if result ~= true then
		return false, tostring(detail or "Audio crossfade was rejected.")
	end
	return true, nil
end


ControllerFunctions.stopServerMusic = function()
	pcall(function() ControllerFunctions.stopAudio() end)
	ControllerFunctions.refreshActiveMusicSoundCount()
end

ControllerFunctions.startServerMusic = function(soundId: any)
	ControllerFunctions.stopServerMusic()
	if typeof(soundId) ~= "string" or #soundId > 64
		or not string.match(soundId, "^rbxassetid://%d+$") then
		ControllerFunctions.setAudioAsset("")
		return
	end
	local setOk, setError = ControllerFunctions.setAudioAsset(soundId)
	if setOk == false then warn("[ClubMusic] Server audio asset could not be assigned: " .. tostring(setError)); return end
	local seekOk, seekError = ControllerFunctions.seekAudio(0)
	if seekOk == false then warn("[ClubMusic] Server audio position could not be reset: " .. tostring(seekError)); return end
	local ok, err = pcall(function()
		ControllerFunctions.playAudio()
		if playbackPaused then ControllerFunctions.pauseAudio() end
	end)
	if not ok then
		warn("[ClubMusic] Server playback could not start: " .. tostring(err))
	end
end

-- Optional cross-server service bridge. The UI remains functional if this separate
-- service is disabled or temporarily unavailable; the server's local security remains active.
remotes:SetAttribute("StartupStage", "LoadingReceiptHash")
local receiptHashModule = ServerStorage:WaitForChild("ClubMusic_ReceiptHash", 20)
if not receiptHashModule or not receiptHashModule:IsA("ModuleScript") then
	remotes:SetAttribute("StartupError", "Missing ServerStorage.ClubMusic_ReceiptHash ModuleScript.")
	error("[ClubMusic] Missing ServerStorage.ClubMusic_ReceiptHash ModuleScript.")
end
local receiptHashOk, receiptHashResult = pcall(require, receiptHashModule)
if not receiptHashOk then
	remotes:SetAttribute("StartupError", "ClubMusic_ReceiptHash require failed: " .. string.sub(tostring(receiptHashResult), 1, 180))
	error("[ClubMusic] ClubMusic_ReceiptHash failed to load: " .. tostring(receiptHashResult))
end
local ReceiptHash = receiptHashResult
local globalApi: Instance? = ServerStorage:FindFirstChild("ClubMusicGlobalAPI") or ServerStorage:WaitForChild("ClubMusicGlobalAPI", 15)
ControllerFunctions.globalInvoke = function(name: string, ...: any): any
	-- Re-resolve on every call so the bridge recovers if its separate Script starts late.
	if not globalApi or globalApi.Parent ~= ServerStorage or not globalApi:IsA("Folder") then
		local discovered = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
		globalApi = if discovered and discovered:IsA("Folder") then discovered else nil
	end
	if not globalApi or not globalApi:IsA("Folder") then return false end
	local fn = globalApi:FindFirstChild(name)
	if not fn or not fn:IsA("BindableFunction") then return false end
	local args = table.pack(...)
	local ok, a, b, c = pcall(function()
		return (fn :: BindableFunction):Invoke(table.unpack(args, 1, args.n))
	end)
	return ok, a, b, c
end
local globalEventObject = if globalApi then globalApi:FindFirstChild("GlobalEvent") else nil

local cachedGlobalXpMultiplier = 1
local cachedGlobalXpExpiresAt = 0
local cachedGlobalXpLowerExpiresAt = 0
local studioXpBoostMultiplier = 1
local studioXpBoostExpiresAt = 0
local xpLastAwardAt: {[number]: number} = {}
local xpFractional: {[number]: number} = {}
local xpLastSaveAt: {[number]: number} = {}
local settleAllXP: (() -> ())? = nil
local xpStateDirty = false

ControllerFunctions.setGlobalXPState = function(multiplier: number, expiresAt: number, lowerExpiresAt: number?)
	if multiplier ~= 1 and multiplier ~= 2 and multiplier ~= 4 then return end
	if typeof(expiresAt) ~= "number" or expiresAt ~= expiresAt
		or expiresAt == math.huge or expiresAt == -math.huge or expiresAt < 0 then return end
	local cleanExpiry = if multiplier == 1 or expiresAt <= os.time() then 0 else math.floor(expiresAt)
	local cleanMultiplier = if cleanExpiry == 0 then 1 else multiplier
	local lowerIsFinite = typeof(lowerExpiresAt) == "number" and lowerExpiresAt == lowerExpiresAt
		and lowerExpiresAt ~= math.huge and lowerExpiresAt ~= -math.huge
	local cleanLowerExpiry = if cleanMultiplier == 4 and lowerIsFinite
		and (lowerExpiresAt :: number) > os.time() then math.floor(lowerExpiresAt :: number) else 0
	if cleanMultiplier == cachedGlobalXpMultiplier and cleanExpiry == cachedGlobalXpExpiresAt
		and cleanLowerExpiry == cachedGlobalXpLowerExpiresAt then return end
	if settleAllXP then settleAllXP() end
	cachedGlobalXpMultiplier = cleanMultiplier
	cachedGlobalXpExpiresAt = cleanExpiry
	cachedGlobalXpLowerExpiresAt = cleanLowerExpiry
	xpStateDirty = true
end

ControllerFunctions.refreshGlobalXPBoost = function()
	if RunService:IsStudio() then
		ControllerFunctions.setGlobalXPState(studioXpBoostMultiplier, studioXpBoostExpiresAt)
		return
	end
	local callOk, multiplier, expiresAt, lowerExpiresAt = ControllerFunctions.globalInvoke("GetGlobalXPBoost")
	if callOk and typeof(multiplier) == "number" and multiplier == multiplier
		and typeof(expiresAt) == "number" and expiresAt == expiresAt
		and (multiplier == 1 or multiplier == 2 or multiplier == 4) then
		ControllerFunctions.setGlobalXPState(multiplier, expiresAt, lowerExpiresAt)
	end
	if cachedGlobalXpExpiresAt > 0 and cachedGlobalXpExpiresAt <= os.time() then
		if cachedGlobalXpLowerExpiresAt > os.time() then
			ControllerFunctions.setGlobalXPState(2, cachedGlobalXpLowerExpiresAt)
		else
			ControllerFunctions.setGlobalXPState(1, 0)
		end
	end
end

local configFolder = ControllerFunctions.getOrCreate(ReplicatedStorage, "Folder", "ClubMusicConfig") :: Folder
configFolder:SetAttribute("GroupId", CONFIG.GroupId)

type QueueEntry = {
	id: string,
	trackId: string,
	title: string,
	artist: string,
	duration: number,
	requestedBy: string,
	userId: number,
	genre: string,
	source: string, -- "player" | "auto" | "playlist"
	vip: boolean,
	passTier: number?,
	soundId: string?,
}
type TitleSlot = {
	text: string,
	effect: string,
	set: string,
	font: string,
	style: string,
	textSize: number,
	height: number,
	distance: number,
}
type Profile = {
	tickets: number,
	coins: number,
	loginStreak: number,
	lastClaimDay: number,
	claimedToday: boolean,
	equippedTag: string?,
	ownedTags: {[string]: boolean},
	clubPlaySeconds: number,
	titleTagUnlocksVersion: number,
	titleSlots: {[number]: TitleSlot},
	unlockedSlots: number,
	activeSlot: number,
	showCustomTitle: boolean,
	glowsticks: number,
	skipTokens: number,
	neonTrail: boolean,
	favorites: {[string]: boolean},
	xp: number,
}

local profiles: {[number]: Profile} = {}
type PendingReceiptMemory = { profile: Profile, productData: {[string]: any} }
local receiptMemoryPending: {[string]: PendingReceiptMemory} = {}
local receiptMemoryApplied: {[string]: Profile} = {}
queue = {}
local ServerStorageForQueue = serverStorage
remotes:SetAttribute("StartupStage", "LoadingMusicQueueManager")

-- WaitForChild only searches direct children. Report both the direct-child inventory
-- and any nested matches so incorrect placement is distinguishable from absence.
local queueManagerModule = ServerStorageForQueue:FindFirstChild("MusicQueueManager")
if not queueManagerModule then
	queueManagerModule = ServerStorageForQueue:WaitForChild("MusicQueueManager", 20)
end
if not queueManagerModule or not queueManagerModule:IsA("ModuleScript") then
	local directChildren = if ControllerFunctions.ErrorHandler
		then ControllerFunctions.ErrorHandler.DescribeChildren(ServerStorageForQueue)
		else "<diagnostic handler unavailable>"
	local nestedMatches = {}
	for _, descendant in ipairs(ServerStorageForQueue:GetDescendants()) do
		if string.lower(descendant.Name) == "musicqueuemanager" then
			table.insert(nestedMatches, descendant:GetFullName() .. " [" .. descendant.ClassName .. "]")
		end
	end
	local nestedDescription = if #nestedMatches > 0 then table.concat(nestedMatches, ", ") else "<no nested matches>"
	local reason = if queueManagerModule then "Found direct child with wrong class: " .. queueManagerModule.ClassName else "Direct child not found"
	local detail = reason .. ". Expected ServerStorage.MusicQueueManager (ModuleScript). ServerStorage direct children: "
		.. directChildren .. ". Descendant matches: " .. nestedDescription
	ControllerFunctions.reportStartupError("ModuleLoader", "Locate MusicQueueManager", detail, ServerStorageForQueue)
	error("[ClubMusic] MusicQueueManager startup blocked. " .. detail)
end

local queueManagerRequireOk, queueManagerRequireResult, queueManagerErrorId
if ControllerFunctions.ErrorHandler then
	queueManagerRequireOk, queueManagerRequireResult, queueManagerErrorId = ControllerFunctions.ErrorHandler.SafeRequire(queueManagerModule, "ServerStorage.MusicQueueManager")
else
	queueManagerRequireOk, queueManagerRequireResult = pcall(require, queueManagerModule)
end
if not queueManagerRequireOk then
	local detail = "MusicQueueManager failed to load: " .. tostring(queueManagerRequireResult)
	if queueManagerErrorId then
		pcall(function() remotes:SetAttribute("StartupError", "[" .. queueManagerErrorId .. "] " .. string.sub(detail, 1, 850)) end)
	else
		ControllerFunctions.reportStartupError("ModuleLoader", "Require MusicQueueManager", detail, queueManagerModule)
	end
	error("[ClubMusic] " .. detail)
end
if typeof(queueManagerRequireResult) ~= "table" or typeof(queueManagerRequireResult.new) ~= "function" then
	local detail = "MusicQueueManager must return a table with a .new() constructor."
	ControllerFunctions.reportStartupError("ModuleLoader", "Validate MusicQueueManager", detail, queueManagerModule)
	error("[ClubMusic] " .. detail)
end
local MusicQueueManager = queueManagerRequireResult
ControllerFunctions.ChildManagerModules = {}
for _, moduleName in ipairs({
	"ServerMusicAudioHandler",
	"MusicPlaybackManager",
	"MusicPlaylistManager",
	"MusicSkipVoteManager",
}) do
	local moduleScript = ServerStorageForQueue:FindFirstChild(moduleName)
	if not moduleScript then
		moduleScript = ServerStorageForQueue:WaitForChild(moduleName, 20)
	end
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		local detail = "Expected direct child ServerStorage." .. moduleName .. " (ModuleScript); found "
			.. (if moduleScript then moduleScript.ClassName else "nothing")
			.. ". Direct children: " .. (if ControllerFunctions.ErrorHandler
				then ControllerFunctions.ErrorHandler.DescribeChildren(ServerStorageForQueue)
				else "<diagnostic handler unavailable>")
		ControllerFunctions.reportStartupError("ModuleLoader", "Locate " .. moduleName, detail, ServerStorageForQueue)
		error("[ClubMusic] " .. detail)
	end

	local requireOk, requireResult, requireErrorId
	if ControllerFunctions.ErrorHandler then
		requireOk, requireResult, requireErrorId = ControllerFunctions.ErrorHandler.SafeRequire(moduleScript, "ServerStorage." .. moduleName)
	else
		requireOk, requireResult = pcall(require, moduleScript)
	end
	if not requireOk or typeof(requireResult) ~= "table" then
		local detail = moduleName .. " failed to load or returned an invalid module table: " .. tostring(requireResult)
		if requireErrorId then
			pcall(function() remotes:SetAttribute("StartupError", "[" .. requireErrorId .. "] " .. string.sub(detail, 1, 850)) end)
		else
			ControllerFunctions.reportStartupError("ModuleLoader", "Load " .. moduleName, detail, moduleScript)
		end
		error("[ClubMusic] " .. detail)
	end
	ControllerFunctions.ChildManagerModules[moduleName] = requireResult
end
ControllerFunctions.globalPlaybackEndTime = 0
local globalRestartRevision = 0
local autoQueueHold = false
-- Queue mutations have their own revision, independent of playback transitions.
-- This prevents delayed MessagingService snapshots from restoring an older queue.
local globalQueueRevision = 0
-- Catalog revision fences every shared enqueue/advance against stale local caches.
local globalCatalogRevision = 0
local globalCatalogChangeTrackId: string? = nil
local globalCatalogChangeKind: string? = nil
ControllerFunctions.refreshCatalogWhenReady = function(): boolean
	-- The controller publishes its remote contract before the cross-server
	-- invalidation listener is defined. A very early UI action waits briefly for
	-- that initializer rather than stranding a catalog reservation.
	for _ = 1, 100 do
		local callback = refreshLocalCatalog
		if callback then return callback() end
		task.wait(0.05)
	end
	return false
end
local globalQueueSyncBusy = false
local globalQueueRefreshScheduled = false
local globalPlaybackInitialized = false
local enqueueGlobalQueueBatch: (({QueueEntry}) -> (boolean, string?))? = nil
local activePlaylistId: string? = nil
local globalPlaylistRotationEnabled = false
local activePlaylistName = ""
local activePlaylistTracks: {Track} = {}
local activePlaylistCursor = 1
local notify: (Player, string, string?) -> ()
nowPlaying = {
	trackId = "",
	title = "",
	artist = "",
	genre = "",
	duration = 1,
	elapsed = 0,
	dj = "Automated Selector",
	source = "auto",
	requestedBy = "Auto DJ",
	vip = false,
	soundId = "",
}
local requestCounts: {[number]: number} = {}
local lastRequestAt: {[number]: number} = {}
local lastActionAt: {[number]: number} = {}
local lastAdminActionAt: {[number]: number} = {}
local lastReloadAt: {[number]: number} = {}
local reloadNonce: {[number]: number} = {}
local pendingAudio: {[number]: boolean} = {}
local lastActionByType: {[number]: {[string]: number}} = {}
-- Admin-addon commands use their own per-action cooldown namespace so recent
-- UI actions cannot reject a trusted command (and vice versa).
local lastAdminActionByType: {[number]: {[string]: number}} = {}
local lastStateInvoke: {[number]: number} = {}
local lastCatalogInvoke: {[number]: number} = {}
local lastAudioInspection: {[number]: number} = {}
local audioInspectionCount = 0
local profileWriteLocks: {[number]: boolean} = {}
local saveQueued: {[number]: boolean} = {}
local saveAgain: {[number]: boolean} = {}
local queueCounter = 0

-- Token buckets are server-authoritative and shared across all requests in this
-- server instance. They are deliberately separate from per-player cooldowns.
type TokenBucket = { tokens: number, capacity: number, refillPerSecond: number, updatedAt: number }

ControllerFunctions.newTokenBucket = function(capacity: number, refillPerSecond: number): TokenBucket
	return {
		tokens = capacity,
		capacity = capacity,
		refillPerSecond = refillPerSecond,
		updatedAt = os.clock(),
	}
end

local globalActionBucket = ControllerFunctions.newTokenBucket(CONFIG.GlobalActionBurst, CONFIG.GlobalActionRefillPerSecond)
local globalAudioBucket = ControllerFunctions.newTokenBucket(CONFIG.GlobalAudioBurst, CONFIG.GlobalAudioRefillPerSecond)
local globalStateQueryBucket = ControllerFunctions.newTokenBucket(30, 15)
local globalDataStoreBucket = ControllerFunctions.newTokenBucket(CONFIG.GlobalDataStoreBurst, CONFIG.GlobalDataStoreRefillPerSecond)
local perPlayerActionBuckets: {[number]: TokenBucket} = {}

ControllerFunctions.consumeToken = function(bucket: TokenBucket, now: number, cost: number?): boolean
	local amount = cost or 1
	local elapsed = math.max(0, now - bucket.updatedAt)
	bucket.updatedAt = now
	bucket.tokens = math.min(bucket.capacity, bucket.tokens + elapsed * bucket.refillPerSecond)
	if bucket.tokens < amount then return false end
	bucket.tokens -= amount
	return true
end

ControllerFunctions.waitForDataStoreBudget = function(maxWaitSeconds: number): boolean
	local sharedStoreCallOk, sharedStoreAllowed = ControllerFunctions.globalInvoke("ConsumeDataStoreBudget")
	if RunService:IsStudio() then
		if sharedStoreCallOk and sharedStoreAllowed == false then return false end
	else
		if not sharedStoreCallOk or sharedStoreAllowed ~= true then return false end
	end
	local startedAt = os.clock()
	while true do
		if ControllerFunctions.consumeToken(globalDataStoreBucket, os.clock(), 1) then return true end
		if os.clock() - startedAt >= maxWaitSeconds then return false end
		task.wait(0.1)
	end
end

-- Initialize storage with bounded retries. The services leave their initialization
-- state retryable after transient budget/DataStore failures; built-in catalog tracks
-- remain available even when persistent custom storage cannot be initialized.
ControllerFunctions.initializeStorageWithRetries = function(service: any, label: string): boolean
	local delays = {0, 1, 2, 4}
	for attempt, delaySeconds in ipairs(delays) do
		if delaySeconds > 0 then task.wait(delaySeconds) end
		local ok, ready = pcall(function()
			return service:Initialize(CONFIG.StudioUseDataStore, function()
				return ControllerFunctions.waitForDataStoreBudget(5)
			end)
		end)
		if ok and ready == true then return true end
		warn(string.format("[ClubMusic] %s initialization attempt %d/%d failed: %s",
			label, attempt, #delays, if ok then "storage not ready" else tostring(ready)))
	end
	return false
end

local catalogStorageReady = ControllerFunctions.initializeStorageWithRetries(MusicCatalogService, "MusicCatalogService")
local playlistRefreshAt = 0
local playlistStorageReady = ControllerFunctions.initializeStorageWithRetries(MusicPlaylistService, "MusicPlaylistService")
if not playlistStorageReady then
	warn("[ClubMusic] Persistent playlists unavailable; playlist management is disabled for this server.")
end
if not catalogStorageReady then
	warn("[ClubMusic] Persistent catalog unavailable; custom catalog changes are disabled for this server.")
end
for _, catalogTrack in ipairs(MusicCatalogService:GetAllTracks()) do
	local track: Track = {
		id = catalogTrack.id,
		genreId = catalogTrack.genreId,
		title = catalogTrack.title,
		artist = catalogTrack.artist,
		duration = catalogTrack.duration,
		genre = catalogTrack.genre,
		assetId = catalogTrack.assetId,
		soundId = catalogTrack.soundId,
		artworkAssetId = catalogTrack.artworkAssetId,
	}
	TRACK_BY_ID[track.id] = track
	table.insert(ALL_TRACK_IDS, track.id)
end
table.sort(ALL_TRACK_IDS)
remotes:SetAttribute("StartupStage", "BuildingController")

ControllerFunctions.consumeActionBudget = function(userId: number, now: number): boolean
	local bucket = perPlayerActionBuckets[userId]
	if not bucket then
		bucket = ControllerFunctions.newTokenBucket(CONFIG.PerPlayerActionBurst, CONFIG.PerPlayerActionRefillPerSecond)
		perPlayerActionBuckets[userId] = bucket
	end
	-- Consume the per-player bucket first. Only consume the global bucket when
	-- the player has capacity, avoiding global-budget loss to one noisy player.
	if not ControllerFunctions.consumeToken(bucket, now, 1) then return false end
	if not ControllerFunctions.consumeToken(globalActionBucket, now, 1) then
		bucket.tokens = math.min(bucket.capacity, bucket.tokens + 1)
		return false
	end
	return true
end

local ACTION_COOLDOWNS: {[string]: number} = {
	RequestTrack = 0.5, RequestAudioAsset = CONFIG.AudioInspectionCooldownSeconds,
	ReloadSong = CONFIG.ReloadCooldownSeconds, ToggleFavorite = 0.2, VoteSkip = 0.5,
	CatalogAddAudio = 10, CatalogRemoveTrack = 2,
	PlaylistCreate = 2, PlaylistDelete = 1, PlaylistAddTrack = 0.5, PlaylistRemoveTrack = 0.5, PlaylistMoveTrack = 0.5,
	DJPlayPlaylist = 2, DJStopPlaylist = 1,
	DJMoveUp = 0.2, DJRemove = 0.2, DJSkip = 0.5, DJPause = 0.5, DJRestart = 1, DJClearQueue = 1, DJToggleLock = 1,
	ModBlockUser = 0.5, ModSetVip = 0.5, ModPurgeUser = 0.5,
	ClaimDailyReward = 1, EquipTitleTag = 0.5, BuyTitleTag = 1, SaveCustomTitle = CONFIG.SaveTitleCooldownSeconds,
	SaveTitleSlot = CONFIG.SaveTitleCooldownSeconds, SelectTitleSlot = 0.3,
	ClearTitleSlot = 0.5, SetTitleVisible = 0.3,
}

ControllerFunctions.isFiniteNumber = function(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

ControllerFunctions.acquireProfileWriteLock = function(userId: number): boolean
	local startedAt = os.clock()
	while profileWriteLocks[userId] do
		if os.clock() - startedAt >= CONFIG.ProfileWriteLockTimeoutSeconds then
			warn("[ClubMusic] Timed out waiting for profile write lock for userId " .. tostring(userId))
			return false
		end
		task.wait(0.05)
	end
	profileWriteLocks[userId] = true
	return true
end

ControllerFunctions.releaseProfileWriteLock = function(userId: number)
	profileWriteLocks[userId] = nil
end

-- Session-only moderation / VIP / vote state
local rankCache: {[number]: {rank: string, level: number}} = {}
local vipPass: {[number]: boolean} = {}
local vvipPass: {[number]: boolean} = {}
local sultanPass: {[number]: boolean} = {}
local tempVip: {[number]: boolean} = {}
local blockedUsers: {[number]: boolean} = {}
local skipVotes: {[number]: boolean} = {}
local requestsLocked = false
local recentTracks: {string} = {}
local lastAutoGenre = ""

-- Ranks, permissions and VIP -------------------------------------------------

ControllerFunctions.computeRank = function(player: Player): (string, number)
	for _, id in ipairs(CONFIG.StaffUserIds) do
		if id == player.UserId then return "OWNER", 4 end
	end
	if CONFIG.StudioStaff and RunService:IsStudio() then return "OWNER", 4 end
	if CONFIG.GroupId <= 0 then return "GUEST", 0 end

	local ok, rank = pcall(function() return player:GetRankInGroup(CONFIG.GroupId) end)
	if not ok or typeof(rank) ~= "number" then return "GUEST", 0 end
	local t = CONFIG.RankThresholds
	if rank >= t.Owner then return "OWNER", 4 end
	if rank >= t.CoOwner then return "CO-OWNER", 3 end
	if rank >= t.Admin then return "ADMIN", 2 end
	if rank >= t.GroupDJ then return "GROUP DJ", 1 end
	return "GUEST", 0
end

-- Yields (group lookups). Never call from the per-second loop.
ControllerFunctions.refreshRank = function(player: Player)
	local rank, level = ControllerFunctions.computeRank(player)
	rankCache[player.UserId] = { rank = rank, level = level }
end

ControllerFunctions.getRank = function(player: Player): string
	local cached = rankCache[player.UserId]
	return if cached then cached.rank else "GUEST"
end

-- Permission level: 0 guest, 1 GROUP DJ, 2 ADMIN, 3 CO-OWNER, 4 OWNER
ControllerFunctions.getLevel = function(player: Player): number
	local cached = rankCache[player.UserId]
	return if cached then cached.level else 0
end

ControllerFunctions.isStaff = function(player: Player): boolean
	return ControllerFunctions.getLevel(player) >= 1
end

ControllerFunctions.isAdmin = function(player: Player): boolean
	return ControllerFunctions.getLevel(player) >= 2
end

ControllerFunctions.passTier = function(player: Player): number
	local userId = player.UserId
	-- Staff receive the complete club membership tier by default. This is
	-- derived from the server-verified staff rank, never from client attributes.
	if ControllerFunctions.getLevel(player) >= 1 then return 3 end
	if sultanPass[userId] == true then return 3 end
	if vvipPass[userId] == true then return 2 end
	if vipPass[userId] == true or tempVip[userId] == true then return 1 end
	return 0
end

ControllerFunctions.isVip = function(player: Player): boolean
	return ControllerFunctions.passTier(player) >= 1
end

ControllerFunctions.isVvip = function(player: Player): boolean
	return ControllerFunctions.passTier(player) >= 2
end

ControllerFunctions.isSultan = function(player: Player): boolean
	return ControllerFunctions.passTier(player) >= 3
end

-- Owners can moderate anyone but themselves; everyone else only moderates strictly lower ranks.
ControllerFunctions.canModerate = function(actor: Player, target: Player): boolean
	if actor == target then return false end
	local actorLevel = ControllerFunctions.getLevel(actor)
	if actorLevel >= 4 then return true end
	return ControllerFunctions.getLevel(target) < actorLevel
end

ControllerFunctions.applyVipAttribute = function(player: Player)
	player:SetAttribute("IsVIP", ControllerFunctions.isVip(player))
	player:SetAttribute("IsVVIP", ControllerFunctions.isVvip(player))
	player:SetAttribute("IsTikiTideSultan", ControllerFunctions.isSultan(player))
	player:SetAttribute("ClubPassTier", ControllerFunctions.passTier(player))
end

-- Ownership is always checked by the server. Failed marketplace lookups fail closed
-- for the affected pass and are retried by the periodic refresh.
ControllerFunctions.ownsGamePass = function(userId: number, passId: number): boolean
	if passId <= 0 then return false end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
	end)
	return ok and owns == true
end

ControllerFunctions.refreshVip = function(player: Player)
	local userId = player.UserId
	vipPass[userId] = ControllerFunctions.ownsGamePass(userId, CONFIG.VipGamePassId)
	vvipPass[userId] = ControllerFunctions.ownsGamePass(userId, CONFIG.VvipGamePassId)
	sultanPass[userId] = ControllerFunctions.ownsGamePass(userId, CONFIG.TikiTideSultanPassId)
	if not vipPass[userId] and CONFIG.VipGroupRank > 0 and CONFIG.GroupId > 0 then
		local ok, rank = pcall(function() return player:GetRankInGroup(CONFIG.GroupId) end)
		if ok and typeof(rank) == "number" and rank >= CONFIG.VipGroupRank then vipPass[userId] = true end
	end
end

ControllerFunctions.requestLimitFor = function(player: Player): number
	local tier = ControllerFunctions.passTier(player)
	if tier >= 3 then return CONFIG.SultanMaxRequestsPerPlayer end
	if tier == 2 then return CONFIG.VvipMaxRequestsPerPlayer end
	if tier == 1 then return CONFIG.VipMaxRequestsPerPlayer end
	return CONFIG.MaxRequestsPerPlayer
end

ControllerFunctions.cooldownFor = function(player: Player): number
	local tier = ControllerFunctions.passTier(player)
	if tier >= 3 then return CONFIG.SultanCooldownSeconds end
	if tier == 2 then return CONFIG.VvipCooldownSeconds end
	if tier == 1 then return CONFIG.VipCooldownSeconds end
	return CONFIG.RequestCooldownSeconds
end

-- Title slots -------------------------------------------------------------------

-- Returns the hex colors for an effect/set (empty for RGB, which animates by speed instead).
ControllerFunctions.titleHexFor = function(effect: string, set: string): {string}
	if effect == "rainbow" then
		-- Palette-based rainbow sets (amethyst, fire, ocean, ...) reuse the two-color palettes above as a
		-- circular list (color A, midpoint, color B, midpoint) that the client flows through the title.
		local palette = if RAINBOW_PARAMS[set] == nil then TITLE_HEX.gradient[set] else nil
		if palette and #palette >= 2 then
			local first = Color3.fromHex(palette[1])
			local second = Color3.fromHex(palette[2])
			local middle = "#" .. first:Lerp(second, 0.5):ToHex()
			return { palette[1], middle, palette[2], middle }
		end
		local params = RAINBOW_PARAMS[set] or RAINBOW_PARAMS.classic
		local out = {}
		for i = 0, 6 do
			table.insert(out, "#" .. Color3.fromHSV(i / 7, params[1], params[2]):ToHex())
		end
		return out
	end
	local group = TITLE_HEX[effect]
	local colors = if group then group[set] else nil
	return colors or {}
end

-- Validates a stored/received slot. Returns nil when anything is out of the allowlists.
ControllerFunctions.sanitizeTitleSlot = function(data: any): TitleSlot?
	if typeof(data) ~= "table" then return nil end
	local text = data.text
	if typeof(text) ~= "string" or #text > 256 then return nil end
	local length = utf8.len(text)
	if not length or length < 1 or length > MAX_CUSTOM_TITLE_LENGTH then return nil end
	local effect = data.effect
	if typeof(effect) ~= "string" or TITLE_SETS[effect] == nil then return nil end
	local set = data.set
	if typeof(set) ~= "string" or TITLE_SETS[effect][set] ~= true then return nil end
	local font = data.font
	if typeof(font) ~= "string" or TITLE_FONTS[font] ~= true then return nil end
	local style = data.style
	if typeof(style) ~= "string" or TITLE_STYLES[style] ~= true then return nil end
	local textSize = tonumber(data.textSize or data.size)
	local height = tonumber(data.heightOffset or data.height)
	local distance = tonumber(data.viewDistance or data.distance)
	if not ControllerFunctions.isFiniteNumber(textSize) then textSize = 20 end
	if not ControllerFunctions.isFiniteNumber(height) then height = 2.5 end
	if not ControllerFunctions.isFiniteNumber(distance) then distance = 80 end
	return {
		text = text,
		effect = effect,
		set = set,
		font = font,
		style = style,
		textSize = math.clamp(math.floor((textSize or 20) + 0.5), 14, 32),
		height = math.clamp(height or 2.5, 0, 8),
		distance = math.clamp(distance or 80, 20, 200),
	}
end

ControllerFunctions.firstFilledSlot = function(profile: Profile): number?
	for i = 1, TITLE_SLOT_COUNT do
		if profile.titleSlots[i] and i <= profile.unlockedSlots then return i end
	end
	return nil
end

-- Mirrors the active slot onto player attributes for the overhead title script.
-- Legacy attributes (CustomTitle/TitleColor/TitleStyle/ShowCustomTitle) are kept up to date as well.
ControllerFunctions.applyTitleAttributes = function(player: Player, profile: Profile)
	local slot = profile.titleSlots[profile.activeSlot]
	-- Replicate the equipped collection tag on join as well as after equip actions.
	-- The overhead renderer consumes this cosmetic attribute; ownership remains server-authoritative.
	player:SetAttribute("EquippedTag", if typeof(profile.equippedTag) == "string" then profile.equippedTag else "")
	player:SetAttribute("TitleSlotsUnlocked", profile.unlockedSlots)
	player:SetAttribute("TitleSlot", profile.activeSlot)
	player:SetAttribute("ShowCustomTitle", profile.showCustomTitle)
	if slot == nil then
		player:SetAttribute("CustomTitle", "")
		player:SetAttribute("TitleColor", "gold")
		player:SetAttribute("TitleStyle", "normal")
		player:SetAttribute("TitleEffect", "fixed")
		player:SetAttribute("TitleSet", "gold")
		player:SetAttribute("TitleColors", "#FCD34D")
		player:SetAttribute("TitleSpeed", 0)
		player:SetAttribute("TitleShimmer", false)
		player:SetAttribute("TitleFont", "gotham")
		player:SetAttribute("TitleTextSize", 20)
		player:SetAttribute("TitleHeight", 2.5)
		player:SetAttribute("TitleDistance", 80)
		return
	end
	player:SetAttribute("CustomTitle", slot.text)
	player:SetAttribute("TitleColor", if slot.effect == "fixed" then slot.set else "gold")
	player:SetAttribute("TitleStyle", slot.style)
	player:SetAttribute("TitleEffect", slot.effect)
	player:SetAttribute("TitleSet", slot.set)
	player:SetAttribute("TitleColors", table.concat(ControllerFunctions.titleHexFor(slot.effect, slot.set), ","))
	player:SetAttribute("TitleSpeed", if slot.effect == "rgb" then (RGB_SPEED[slot.set] or 0.25) elseif slot.effect == "shimmer" then 0.35 else 0)
	player:SetAttribute("TitleShimmer", slot.effect == "shimmer")
	player:SetAttribute("TitleFont", slot.font)
	player:SetAttribute("TitleTextSize", slot.textSize)
	player:SetAttribute("TitleHeight", slot.height)
	player:SetAttribute("TitleDistance", slot.distance)
end

-- Filters player-authored text on the server before storing or replicating it. Returns nil on failure.
ControllerFunctions.filterTitleText = function(player: Player, rawText: string): string?
	local trimmed = string.match(rawText, "^%s*(.-)%s*$") or ""
	if trimmed == "" then return "" end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(trimmed, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(result) ~= "string" then return nil end
	return ControllerFunctions.truncateUtf8(result, MAX_CUSTOM_TITLE_LENGTH)
end

-- Profiles --------------------------------------------------------------------

ControllerFunctions.defaultProfile = function(): Profile
	return {
		tickets = 0,
		coins = 0,
		loginStreak = 1,
		lastClaimDay = 0,
		claimedToday = false,
		equippedTag = nil,
		ownedTags = {},
		clubPlaySeconds = 0,
		titleTagUnlocksVersion = 2,
		titleSlots = {},
		unlockedSlots = 1,
		activeSlot = 1,
		showCustomTitle = true,
		glowsticks = 0,
		skipTokens = 0,
		neonTrail = false,
		favorites = {},
		xp = 0,
	}
end

ControllerFunctions.loadProfile = function(player: Player)
	local profile = ControllerFunctions.defaultProfile()
	local data = nil
	local ok = false
	local lastError = "Profile session is already active on another server."

	if USE_STUDIO_MEMORY_PROFILES then
		-- Studio test profile: keep all existing gameplay/profile features usable
		-- without attempting a DataStore request or requiring API access.
		data = {}
		ok = true
	else
		for attempt = 1, 5 do
			if not ControllerFunctions.waitForDataStoreBudget(20) then
				lastError = "Server DataStore request budget is busy."
				break
			end
			local callOk, result = pcall(function()
				return store:UpdateAsync(tostring(player.UserId), function(oldData)
					local current = if typeof(oldData) == "table" then table.clone(oldData) else {}
					local lock = current.sessionLock
					if typeof(lock) == "table" and typeof(lock.owner) == "string"
						and lock.owner ~= SESSION_TOKEN and (tonumber(lock.expiresAt) or 0) > os.time() then
						return nil -- Another live server owns this profile.
					end
					current.sessionLock = { owner = SESSION_TOKEN, expiresAt = os.time() + SESSION_LOCK_SECONDS }
					return current
				end)
			end)
			if callOk and typeof(result) == "table" then
				data = result
				ok = true
				break
			end
			if not callOk then lastError = tostring(result) end
			if attempt < 5 then task.wait(2) end
		end
	end
	if not ok then
		warn("[ClubMusic] Profile load/lock failed for " .. player.Name .. ": " .. lastError .. ". Profile remains unavailable; refusing to save defaults.")
		return false
	end
	if typeof(data) == "table" then
		profile.xp = math.clamp(math.floor(tonumber(data.xp) or 0), 0, 9007199254740000)
		profile.tickets = math.max(0, tonumber(data.tickets) or 0)
		profile.coins = math.max(0, tonumber(data.coins) or 0)
		profile.loginStreak = math.clamp(math.floor(tonumber(data.loginStreak) or 1), 1, 7)
		profile.lastClaimDay = math.max(0, math.floor(tonumber(data.lastClaimDay) or 0))
		profile.claimedToday = data.claimedToday == true
		profile.equippedTag = if typeof(data.equippedTag) == "string" and TAGS[data.equippedTag] == true then data.equippedTag else nil
		profile.showCustomTitle = data.showCustomTitle ~= false
		profile.glowsticks = math.max(0, math.floor(tonumber(data.glowsticks) or 0))
		profile.skipTokens = math.max(0, math.floor(tonumber(data.skipTokens) or 0))
		profile.neonTrail = data.neonTrail == true
		profile.clubPlaySeconds = math.clamp(math.floor(tonumber(data.clubPlaySeconds) or 0), 0, 9007199254740000)
		profile.titleTagUnlocksVersion = math.max(0, math.floor(tonumber(data.titleTagUnlocksVersion) or 0))
		if typeof(data.ownedTags) == "table" then
			for id, owned in pairs(data.ownedTags) do
				if TAGS[id] == true and owned == true then profile.ownedTags[id] = true end
			end
		end
		-- One-time migration: the previous defaults falsely marked these tags as owned.
		-- Re-evaluate them below using the real server-side unlock conditions.
		if profile.titleTagUnlocksVersion < 2 then
			profile.ownedTags.vip = nil
			profile.ownedTags.party = nil
			profile.ownedTags.wave = nil
			if profile.equippedTag == "vip" or profile.equippedTag == "party" or profile.equippedTag == "wave" then
				profile.equippedTag = nil
			end
			profile.titleTagUnlocksVersion = 2
		end
		if typeof(data.favorites) == "table" then
			local count = 0
			for id, flag in pairs(data.favorites) do
				if count >= CONFIG.MaxFavorites then break end
				if typeof(id) == "string" and flag == true and TRACK_BY_ID[id] then
					profile.favorites[id] = true
					count += 1
				end
			end
		end

		-- Load every valid new-format slot first. Only migrate the legacy title when
		-- none of the new-format slots contains a valid title; this repairs profiles
		-- with an empty/invalid titleSlots table without overwriting newer slot data.
		profile.unlockedSlots = math.clamp(math.floor(tonumber(data.unlockedSlots) or 1), 1, TITLE_SLOT_COUNT)
		local hasValidNewTitle = false
		if typeof(data.titleSlots) == "table" then
			for i = 1, TITLE_SLOT_COUNT do
				local stored = data.titleSlots[tostring(i)] or data.titleSlots[i]
				local clean = ControllerFunctions.sanitizeTitleSlot(stored)
				if clean then
					profile.titleSlots[i] = clean
					hasValidNewTitle = true
				end
			end
		end

		if not hasValidNewTitle and typeof(data.customTitle) == "string" and data.customTitle ~= "" then
			local legacyColor = if typeof(data.titleColor) == "string" and TITLE_COLORS[data.titleColor] == true then data.titleColor else "gold"
			local legacyStyle = if typeof(data.titleStyle) == "string" and TITLE_STYLES[data.titleStyle] == true then data.titleStyle else "normal"
			local legacy = ControllerFunctions.sanitizeTitleSlot({
				text = data.customTitle, effect = "fixed", set = legacyColor, font = "gotham", style = legacyStyle,
			})
			if legacy then
				-- Legacy text is player-authored. Re-filter it for broadcast before it
				-- can be placed in replicated player attributes. Never fall back to raw text.
				local filteredText = ControllerFunctions.filterTitleText(player, legacy.text)
				if filteredText and filteredText ~= "" then
					legacy.text = filteredText
					profile.titleSlots[1] = legacy
				else
					warn("[ClubMusic] Legacy custom title migration was skipped because Roblox text filtering failed for userId " .. tostring(player.UserId))
				end
			else
				warn("[ClubMusic] Legacy custom title migration was skipped because the saved title failed validation for userId " .. tostring(player.UserId))
			end
		end
		profile.activeSlot = math.clamp(math.floor(tonumber(data.activeSlot) or 1), 1, TITLE_SLOT_COUNT)
	end

	-- Staff have all three custom-title slots unlocked automatically. Existing
	-- player-owned slots and title data are preserved; this only raises access.
	if ControllerFunctions.isStaff(player) then
		profile.unlockedSlots = TITLE_SLOT_COUNT
	end

	-- The active slot must be unlocked and filled; otherwise fall back to the first filled slot.
	if profile.activeSlot > profile.unlockedSlots or profile.titleSlots[profile.activeSlot] == nil then
		profile.activeSlot = ControllerFunctions.firstFilledSlot(profile) or 1
	end

	local today = math.floor(os.time() / 86400)
	if profile.lastClaimDay < today then
		if profile.lastClaimDay > 0 and today - profile.lastClaimDay == 1 then
			profile.loginStreak = (profile.loginStreak % 7) + 1
		elseif profile.lastClaimDay == 0 or today - profile.lastClaimDay > 1 then
			profile.loginStreak = 1
		end
		profile.claimedToday = false
	end

	profiles[player.UserId] = profile
	player:SetAttribute("XP", profile.xp)
	player:SetAttribute("Level", math.floor(profile.xp / CONFIG.XPPerLevel) + 1)
	player:SetAttribute("XPToNextLevel", CONFIG.XPPerLevel - (profile.xp % CONFIG.XPPerLevel))
	player:SetAttribute("Tickets", profile.tickets)
	player:SetAttribute("Coins", profile.coins)
	player:SetAttribute("Glowsticks", profile.glowsticks)
	player:SetAttribute("SkipTokens", profile.skipTokens)
	player:SetAttribute("NeonTrailUnlocked", profile.neonTrail)
	player:SetAttribute("LoginStreak", profile.loginStreak)
	player:SetAttribute("ClaimedToday", profile.claimedToday)
	player:SetAttribute("EquippedTag", profile.equippedTag or "")
	ControllerFunctions.applyTitleAttributes(player, profile)
	return true
end

ControllerFunctions.saveProfile = function(player: Player)
	-- Studio memory mode intentionally has no durable backend. The in-memory
	-- profile remains authoritative for this test session; never call UpdateAsync.
	if USE_STUDIO_MEMORY_PROFILES then
		return profiles[player.UserId] ~= nil
	end

	local userId = player.UserId
	local profile = profiles[userId]
	if not profile then return false end
	if not ControllerFunctions.acquireProfileWriteLock(userId) then return false end
	profile = profiles[userId]
	if not profile then ControllerFunctions.releaseProfileWriteLock(userId); return false end
	if not ControllerFunctions.waitForDataStoreBudget(8) then
		ControllerFunctions.releaseProfileWriteLock(userId)
		warn("[ClubMusic] Profile save deferred: server DataStore budget is busy for userId " .. tostring(userId))
		return false
	end

	-- String keys keep the slot table a dictionary (safe for sparse slots) in the DataStore.
	local slotsSnapshot: {[string]: any} = {}
	for i = 1, TITLE_SLOT_COUNT do
		local slot = profile.titleSlots[i]
		if slot then
			slotsSnapshot[tostring(i)] = {
				text = slot.text, effect = slot.effect, set = slot.set, font = slot.font,
				style = slot.style, textSize = slot.textSize, height = slot.height, distance = slot.distance,
			}
		end
	end

	local snapshot = {
		tickets = profile.tickets,
		coins = profile.coins,
		loginStreak = profile.loginStreak,
		lastClaimDay = profile.lastClaimDay,
		claimedToday = profile.claimedToday,
		equippedTag = profile.equippedTag,
		ownedTags = table.clone(profile.ownedTags),
		clubPlaySeconds = profile.clubPlaySeconds,
		titleTagUnlocksVersion = profile.titleTagUnlocksVersion,
		titleSlots = slotsSnapshot,
		unlockedSlots = profile.unlockedSlots,
		activeSlot = profile.activeSlot,
		showCustomTitle = profile.showCustomTitle,
		glowsticks = profile.glowsticks,
		skipTokens = profile.skipTokens,
		neonTrail = profile.neonTrail,
		favorites = table.clone(profile.favorites),
		xp = profile.xp,
	}
	local ownershipLost = false
	local ok, result = pcall(function()
		return store:UpdateAsync(tostring(userId), function(oldData)
			if typeof(oldData) ~= "table" or typeof(oldData.sessionLock) ~= "table"
				or oldData.sessionLock.owner ~= SESSION_TOKEN then
				ownershipLost = true
				return nil -- This server no longer owns the profile; never overwrite another session.
			end
			local pendingReceiptId = if typeof(oldData.pendingReceipt) == "string" then oldData.pendingReceipt else nil
			local pendingMemory = if pendingReceiptId then receiptMemoryPending[pendingReceiptId] else nil
			if pendingMemory and pendingMemory.profile == profile then
				-- Do not overwrite a durably applied reward with a stale in-memory snapshot.
				return nil
			end
			local preservedReceipts = {}
			if typeof(oldData) == "table" and typeof(oldData.receiptIds) == "table" then
				for id, value in pairs(oldData.receiptIds) do
					if typeof(id) == "string" and value == true then preservedReceipts[id] = true end
				end
			end
			local preservedPendingReceipt = if typeof(oldData.pendingReceipt) == "string" then oldData.pendingReceipt else nil
			local output = table.clone(snapshot)
			output.ownedTags = table.clone(snapshot.ownedTags)
			output.favorites = table.clone(snapshot.favorites)
			output.receiptIds = preservedReceipts -- legacy entries only; new receipts use the sharded journal.
			output.pendingReceipt = preservedPendingReceipt
			output.sessionLock = { owner = SESSION_TOKEN, expiresAt = os.time() + SESSION_LOCK_SECONDS }
			return output
		end)
	end)
	ControllerFunctions.releaseProfileWriteLock(userId)
	if not ok or typeof(result) ~= "table" then
		warn("[ClubMusic] Profile save failed for " .. player.Name .. ": " .. tostring(result or "profile session ownership lost"))
		if ownershipLost and player.Parent == Players then
			-- A second server now owns this profile. Stop this session from continuing
			-- to mutate a stale in-memory copy that can no longer be saved safely.
			player:Kick("Your profile session moved to another server. Please rejoin.")
		end
		return false
	end
	return true
end

-- Collapse rapid profile mutations into one save. If another mutation happens
-- during a save, schedule one follow-up instead of spawning an unbounded stack.
ControllerFunctions.scheduleProfileSave = function(player: Player)
	local userId = player.UserId
	if saveQueued[userId] then
		saveAgain[userId] = true
		return
	end
	saveQueued[userId] = true
	task.delay(CONFIG.ProfileSaveQueueDelaySeconds, function()
		if player.Parent ~= Players or profiles[userId] == nil then
			saveQueued[userId] = nil
			saveAgain[userId] = nil
			return
		end
		ControllerFunctions.saveProfile(player)
		saveQueued[userId] = nil
		if saveAgain[userId] then
			saveAgain[userId] = nil
			ControllerFunctions.scheduleProfileSave(player)
		end
	end)
end

-- Queue / Auto DJ ---------------------------------------------------------------

ControllerFunctions.makeEntry = function(track: Track, source: string, player: Player?): QueueEntry
	queueCounter += 1
	return {
		id = "cm-" .. HttpService:GenerateGUID(false),
		trackId = track.id,
		title = track.title,
		artist = track.artist,
		duration = track.duration,
		requestedBy = if player then player.DisplayName else "Auto DJ",
		userId = if player then player.UserId else 0,
		genre = track.genre,
		source = source,
		vip = if player then ControllerFunctions.isVip(player) else false,
		passTier = if player then ControllerFunctions.passTier(player) else 0,
		soundId = track.soundId or CONFIG.SoundIds[track.id],
	}
end

ControllerFunctions.releaseSlot = function(entry: QueueEntry)
	if entry.source == "player" and entry.userId > 0 then
		local remaining = (requestCounts[entry.userId] or 0) - 1
		requestCounts[entry.userId] = if remaining > 0 then remaining else nil
	end
end

-- The manager is an adapter over this controller-owned table. It never creates a
-- parallel queue and all request-slot accounting remains in releaseSlot above.
queueManager = MusicQueueManager.new(queue, ControllerFunctions.releaseSlot)

ControllerFunctions.countPlayerEntries = function(): number
	local n = 0
	for _, entry in ipairs(queue) do
		if entry.source == "player" then n += 1 end
	end
	return n
end

ControllerFunctions.findQueueIndex = function(id: string): number?
	for index, entry in ipairs(queue) do
		if entry.id == id then return index end
	end
	return nil
end

-- Queue order: Sultan, VVIP, VIP, normal player requests, then auto tracks.
ControllerFunctions.insertIndex = function(tier: number): number
	local lastPlayer = 0
	local insertAt = 0
	for index, entry in ipairs(queue) do
		if entry.source == "player" then
			lastPlayer = index
			local existingTier = tonumber(entry.passTier) or (entry.vip and 1 or 0)
			if tier > 0 and existingTier >= tier then insertAt = index end
		end
	end
	if tier > 0 and CONFIG.VipPriority then return insertAt + 1 end
	return lastPlayer + 1
end

ControllerFunctions.pickAutoTrack = function(): Track
	local queued: {[string]: boolean} = {}
	for _, entry in ipairs(queue) do queued[entry.trackId] = true end
	local recentSet: {[string]: boolean} = {}
	for _, id in ipairs(recentTracks) do recentSet[id] = true end

	local pool: {Track} = {}
	local preferred: {Track} = {}
	for _, id in ipairs(ALL_TRACK_IDS) do
		local track = TRACK_BY_ID[id]
		if not queued[id] and not recentSet[id] and id ~= nowPlaying.trackId then
			table.insert(pool, track)
			if track.genreId ~= lastAutoGenre then table.insert(preferred, track) end
		end
	end

	local source = if #preferred > 0 then preferred elseif #pool > 0 then pool else nil
	if source then
		local chosen = source[random:NextInteger(1, #source)]
		lastAutoGenre = chosen.genreId
		return chosen
	end
	return TRACK_BY_ID[ALL_TRACK_IDS[random:NextInteger(1, #ALL_TRACK_IDS)]]
end

ControllerFunctions.nextPlaylistTrack = function(): Track?
	if not activePlaylistId or #activePlaylistTracks == 0 then return nil end
	for _ = 1, #activePlaylistTracks do
		if activePlaylistCursor > #activePlaylistTracks then activePlaylistCursor = 1 end
		local track = activePlaylistTracks[activePlaylistCursor]
		activePlaylistCursor += 1
		if TRACK_BY_ID[track.id] then return track end
	end
	return nil
end

ControllerFunctions.topUpAuto = function()
	if autoQueueHold then return end
	if globalQueueMode then
		-- Generate one refill and commit it atomically. The service rechecks the
		-- queue target inside UpdateAsync so concurrent servers cannot overfill it.
		if not enqueueGlobalQueueBatch then return end
		local entries: {QueueEntry} = {}
		local guard = 0
		while #queue + #entries < CONFIG.AutoQueueTarget and guard < 10 do
			guard += 1
			local playlistTrack = ControllerFunctions.nextPlaylistTrack()
			if playlistTrack then
				table.insert(entries, ControllerFunctions.makeEntry(playlistTrack, "playlist", nil))
			else
				if activePlaylistId then
					warn("[ClubMusic] Active playlist has no playable catalog tracks; returning to Auto DJ.")
					activePlaylistId = nil; activePlaylistName = ""
					table.clear(activePlaylistTracks); activePlaylistCursor = 1
				end
				table.insert(entries, ControllerFunctions.makeEntry(ControllerFunctions.pickAutoTrack(), "auto", nil))
			end
		end
		if #entries > 0 then enqueueGlobalQueueBatch(entries) end
		return
	end
	local guard = 0
	while #queue < CONFIG.AutoQueueTarget and guard < 10 do
		guard += 1
		local playlistTrack = ControllerFunctions.nextPlaylistTrack()
		local entry: QueueEntry
		if playlistTrack then
			entry = ControllerFunctions.makeEntry(playlistTrack, "playlist", nil)
		else
			if activePlaylistId then
				warn("[ClubMusic] Active playlist has no playable catalog tracks; returning to Auto DJ.")
				activePlaylistId = nil; activePlaylistName = ""
				table.clear(activePlaylistTracks); activePlaylistCursor = 1
			end
			entry = ControllerFunctions.makeEntry(ControllerFunctions.pickAutoTrack(), "auto", nil)
		end
		queueManager:Insert(#queue + 1, entry)
	end
end

ControllerFunctions.clearAutomaticQueue = function()
	queueManager:ClearAutomatic()
end

ControllerFunctions.reloadActivePlaylist = function(): boolean
	if not activePlaylistId then return false end
	for _, playlist in ipairs(MusicPlaylistService:GetAll()) do
		if playlist.id == activePlaylistId then
			local validTracks: {Track} = {}
			for _, trackId in ipairs(playlist.trackIds) do
				local track = TRACK_BY_ID[trackId]
				if track then table.insert(validTracks, track) end
			end
			if #validTracks == 0 then
				activePlaylistId = nil
				activePlaylistName = ""
				table.clear(activePlaylistTracks)
				activePlaylistCursor = 1
				return false
			end
			activePlaylistName = playlist.name
			activePlaylistTracks = validTracks
			activePlaylistCursor = 1
			return true
		end
	end
	activePlaylistId = nil
	activePlaylistName = ""
	table.clear(activePlaylistTracks)
	activePlaylistCursor = 1
	return false
end

ControllerFunctions.startPlaylistRotation = function(player: Player, playlistId: any): boolean
	if typeof(playlistId) ~= "string" or #playlistId == 0 or #playlistId > 64 then
		notify(player, "Choose a valid playlist.", "warn")
		return false
	end
	local found: any = nil
	for _, playlist in ipairs(MusicPlaylistService:GetAll()) do
		if playlist.id == playlistId then found = playlist; break end
	end
	if not found then
		notify(player, "Playlist not found. Refresh the playlist list and try again.", "warn")
		return false
	end
	local validTracks: {Track} = {}
	for _, trackId in ipairs(found.trackIds) do
		local track = TRACK_BY_ID[trackId]
		if track then table.insert(validTracks, track) end
	end
	if #validTracks == 0 then
		notify(player, "This playlist has no tracks available in the current catalog.", "warn")
		return false
	end
	if globalQueueMode then
		local trackIds = {}
		for _, playlistTrack in ipairs(validTracks) do table.insert(trackIds, playlistTrack.id) end
		local callOk, changed, state, message = ControllerFunctions.globalInvoke("SetGlobalPlaylistRotation", found.id, found.name, trackIds)
		if not callOk or changed ~= true or typeof(state) ~= "table" then
			notify(player, tostring(message or "Global playlist rotation could not be started."), "warn")
			return false
		end
		ControllerFunctions.applyGlobalQueueState(state)
		ControllerFunctions.topUpAuto()
		notify(player, "Global playlist rotation enabled: " .. found.name .. ".", "ok")
		return true
	end
	activePlaylistId = found.id
	activePlaylistName = found.name
	activePlaylistTracks = validTracks
	activePlaylistCursor = 1
	ControllerFunctions.clearAutomaticQueue()
	ControllerFunctions.topUpAuto()
	notify(player, "Playlist rotation enabled: " .. activePlaylistName .. ". The current track will finish first.", "ok")
	return true
end

ControllerFunctions.stopPlaylistRotation = function(player: Player?)
	if not activePlaylistId then
		if player then notify(player, "No playlist rotation is active.", "info") end
		return false
	end
	local stoppedName = activePlaylistName
	if globalQueueMode then
		local callOk, stopped, state, message = ControllerFunctions.globalInvoke("SetGlobalPlaylistRotation", nil)
		if not callOk or stopped ~= true or typeof(state) ~= "table" then
			if player then notify(player, tostring(message or "Global playlist rotation could not be stopped."), "warn") end
			return false
		end
		ControllerFunctions.applyGlobalQueueState(state)
		ControllerFunctions.topUpAuto()
		if player then notify(player, "Global playlist rotation stopped: " .. stoppedName .. ".", "ok") end
		return true
	end
	activePlaylistId = nil
	activePlaylistName = ""
	table.clear(activePlaylistTracks)
	activePlaylistCursor = 1
	ControllerFunctions.clearAutomaticQueue()
	ControllerFunctions.topUpAuto()
	if player then notify(player, "Playlist rotation stopped: " .. stoppedName .. ".", "ok") end
	return true
end

local playbackGeneration = 0
local transitionInProgress = false
local crossfadeAttemptedGeneration = -1
local crossfadeBoundaryWaitGeneration = -1
local crossfadeBoundaryWaitStartedAt = 0

ControllerFunctions.setNowPlaying = function(entry: QueueEntry, preserveAudio: boolean?)
	if preserveAudio ~= true then ControllerFunctions.cancelAudioTransition("track-change") end
	playbackGeneration += 1
	audioTransitionTrackToken += 1
	pendingCrossfadeEntry = nil
	pendingCrossfadeToken = -1
	ControllerFunctions.pendingCrossfadeGlobalRevision = -1
	ControllerFunctions.pendingCrossfadeGlobalCommitted = false
	ControllerFunctions.pendingCrossfadeDeadline = 0
	crossfadeAttemptedGeneration = -1
	crossfadeBoundaryWaitGeneration = -1
	autoQueueHold = false
	nowPlaying.trackId = entry.trackId
	nowPlaying.title = entry.title
	nowPlaying.artist = entry.artist
	nowPlaying.genre = entry.genre
	nowPlaying.duration = math.max(1, entry.duration)
	nowPlaying.elapsed = 0
	nowPlaying.dj = if entry.source == "playlist" then "Playlist: " .. activePlaylistName else "Automated Selector"
	nowPlaying.source = entry.source
	nowPlaying.requestedBy = if entry.source == "playlist" then activePlaylistName else entry.requestedBy
	nowPlaying.vip = entry.vip
	nowPlaying.soundId = entry.soundId or CONFIG.SoundIds[entry.trackId] or ""
	if preserveAudio ~= true then ControllerFunctions.startServerMusic(nowPlaying.soundId) end
	if preserveAudio ~= true and CONFIG.UseModernAudioBackend then
		task.defer(ControllerFunctions.tryModernAudioBackendMigration)
	end

	table.insert(recentTracks, entry.trackId)
	while #recentTracks > CONFIG.AutoAvoidRecent do
		table.remove(recentTracks, 1)
	end
	table.clear(skipVotes)
end

-- Shared queue mirror. The global DataStore is authoritative when the global
-- service is enabled; the local table remains a detached UI mirror only.
ControllerFunctions.applyGlobalQueueState = function(state: any): boolean
	if typeof(state) ~= "table" or typeof(state.queue) ~= "table"
		or typeof(state.playback) ~= "table" then return false end
	-- Queue and playback revisions are separate monotonic counters. A snapshot
	-- must be fresh for both dimensions before it can replace the local mirror.
	local queueRevision = tonumber(state.revision)
	local catalogRevision = tonumber(state.catalogRevision) or 0
	local revision = tonumber(state.playback.trackRevision)
	if not ControllerFunctions.isFiniteNumber(queueRevision) or queueRevision < 0 or queueRevision % 1 ~= 0
		or queueRevision > 9007199254740991 or queueRevision < globalQueueRevision then return false end
	if not ControllerFunctions.isFiniteNumber(revision) or revision < 0 or revision % 1 ~= 0
		or revision > 9007199254740991 or revision < globalTrackRevision then return false end
	if not ControllerFunctions.isFiniteNumber(catalogRevision) or catalogRevision < 0 or catalogRevision % 1 ~= 0
		or catalogRevision > 9007199254740991 then return false end
	globalCatalogRevision = math.max(globalCatalogRevision, catalogRevision)
	globalCatalogChangeTrackId = if typeof(state.catalogChangeTrackId) == "string" then state.catalogChangeTrackId else nil
	globalCatalogChangeKind = if state.catalogChangeKind == "add" or state.catalogChangeKind == "remove"
		then state.catalogChangeKind else nil
	globalPlaylistRotationEnabled = typeof(state.rotation) == "table" and state.rotation.enabled == true
	if typeof(state.rotation) == "table" and state.rotation.enabled == true
		and typeof(state.rotation.trackIds) == "table" then
		activePlaylistId = tostring(state.rotation.id)
		activePlaylistName = tostring(state.rotation.name)
		activePlaylistTracks = {}
		for _, trackId in ipairs(state.rotation.trackIds) do
			local track = TRACK_BY_ID[trackId]
			if track then table.insert(activePlaylistTracks, track) end
		end
		activePlaylistCursor = math.clamp(tonumber(state.rotation.cursor) or 1, 1, math.max(1, #activePlaylistTracks))
		if #activePlaylistTracks == 0 then activePlaylistId = nil; activePlaylistName = "" end
	else
		activePlaylistId = nil; activePlaylistName = ""; table.clear(activePlaylistTracks); activePlaylistCursor = 1
	end
	table.clear(queue)
	for _, raw in ipairs(state.queue) do
		if typeof(raw) == "table" and typeof(raw.id) == "string" and typeof(raw.trackId) == "string"
			and typeof(raw.title) == "string" and typeof(raw.artist) == "string"
			and typeof(raw.duration) == "number" and typeof(raw.userId) == "number"
			and typeof(raw.source) == "string" then
			table.insert(queue, {
				id = raw.id, trackId = raw.trackId, title = raw.title, artist = raw.artist,
				duration = raw.duration, requestedBy = tostring(raw.requestedBy or "Auto DJ"),
				userId = raw.userId, genre = tostring(raw.genre or "Unknown"), source = raw.source,
				vip = raw.vip == true, passTier = tonumber(raw.passTier) or 0,
				soundId = tostring(raw.soundId or ""),
			})
		end
	end
	for userId in pairs(requestCounts) do requestCounts[userId] = nil end
	for _, entry in ipairs(queue) do
		if entry.source == "player" and Players:GetPlayerByUserId(entry.userId) then
			requestCounts[entry.userId] = (requestCounts[entry.userId] or 0) + 1
		end
	end
	local previousRestartRevision = globalRestartRevision
	local restartRevision = tonumber(state.playback.restartRevision) or 0
	if not ControllerFunctions.isFiniteNumber(restartRevision) or restartRevision < 0 or restartRevision % 1 ~= 0 then return false end
	local current = state.current
	if typeof(current) == "table" and typeof(current.trackId) == "string" then
		local playbackAnchor = tonumber(state.playback.anchorTime)
		local playbackBasePosition = tonumber(state.playback.position) or 0
		local currentDuration = tonumber(current.duration) or 1
		if ControllerFunctions.isFiniteNumber(playbackAnchor) and ControllerFunctions.isFiniteNumber(playbackBasePosition) then
			ControllerFunctions.globalPlaybackEndTime = playbackAnchor + math.max(0, currentDuration - playbackBasePosition)
		end
		local pendingManager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.Crossfade
		local pendingPreparedEntry = pendingCrossfadeEntry
		local preservePreparedCrossfade = pendingManager ~= nil and pendingManager.active == true
			and typeof(pendingPreparedEntry) == "table"
			and pendingCrossfadeToken == audioTransitionTrackToken
			and ControllerFunctions.pendingCrossfadeGlobalRevision >= 0
			and revision > ControllerFunctions.pendingCrossfadeGlobalRevision
			and state.playback.paused ~= true
			and restartRevision <= previousRestartRevision
			and typeof(current) == "table" and current.id == pendingPreparedEntry.id
		if preservePreparedCrossfade then ControllerFunctions.pendingCrossfadeGlobalCommitted = true end
		if nowPlaying.trackId ~= current.trackId and not preservePreparedCrossfade then
			local entry: QueueEntry = {
				id = tostring(current.id), trackId = current.trackId, title = tostring(current.title),
				artist = tostring(current.artist), duration = tonumber(current.duration) or 1,
				requestedBy = tostring(current.requestedBy or "Auto DJ"), userId = tonumber(current.userId) or 0,
				genre = tostring(current.genre or "Unknown"), source = tostring(current.source or "auto"),
				vip = current.vip == true, passTier = tonumber(current.passTier) or 0,
				soundId = tostring(current.soundId or ""),
			}
			ControllerFunctions.setNowPlaying(entry)
		end
		-- Pause is authoritative state, not a side effect of a position lookup.
		-- Apply it even if the optional position helper is temporarily unavailable.
		playbackPaused = state.playback.paused == true
		local restartObserved = globalPlaybackInitialized and restartRevision > previousRestartRevision
		if playbackPaused and not preservePreparedCrossfade then
			local pendingManager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.Crossfade
			if pendingManager and pendingManager.active then
				ControllerFunctions.cancelAudioTransition("global-snapshot-pause")
			end
		end
		if preservePreparedCrossfade then
			-- Keep the outgoing deck untouched until the prepared incoming deck
			-- completes its local fade and commits controller ownership.
		elseif restartObserved then
			ControllerFunctions.cancelAudioTransition("global-restart-reconcile")
			nowPlaying.elapsed = 0
			pcall(function() ControllerFunctions.startServerMusic(nowPlaying.soundId) end)
		elseif ControllerFunctions.isFiniteNumber(state.playback.position) then
			nowPlaying.elapsed = math.clamp(state.playback.position, 0, nowPlaying.duration)
		end
		if not preservePreparedCrossfade then
			local positionCallOk, position = ControllerFunctions.globalInvoke("GetGlobalPlaybackPosition", state)
			if positionCallOk and ControllerFunctions.isFiniteNumber(position) then
				nowPlaying.elapsed = math.clamp(position, 0, nowPlaying.duration)
			end
			pcall(function()
				local audio = ControllerFunctions.getAudioSnapshot()
				if audio.asset ~= nowPlaying.soundId then
					if nowPlaying.soundId ~= "" then ControllerFunctions.startServerMusic(nowPlaying.soundId)
					else ControllerFunctions.stopServerMusic(); ControllerFunctions.setAudioAsset("") end
				end
				audio = ControllerFunctions.getAudioSnapshot()
				if audio.ready and math.abs(audio.position - nowPlaying.elapsed) > 2 then ControllerFunctions.seekAudio(nowPlaying.elapsed) end
				if playbackPaused then ControllerFunctions.pauseAudio()
				elseif not audio.playing and nowPlaying.soundId ~= "" then ControllerFunctions.playAudio() end
			end)
		end
		globalTrackRevision = revision
		globalRestartRevision = restartRevision
		globalPlaybackInitialized = true
	else
		ControllerFunctions.globalPlaybackEndTime = 0
		if nowPlaying.trackId ~= "" then
			nowPlaying.trackId = ""; nowPlaying.title = ""; nowPlaying.artist = ""
			nowPlaying.genre = ""; nowPlaying.duration = 1; nowPlaying.elapsed = 0
			nowPlaying.dj = "Automated Selector"; nowPlaying.source = "auto"
			nowPlaying.requestedBy = "Auto DJ"; nowPlaying.vip = false; nowPlaying.soundId = ""
			ControllerFunctions.stopServerMusic(); ControllerFunctions.setAudioAsset("")
		end
		playbackPaused = true
		globalTrackRevision = revision
		globalRestartRevision = restartRevision
	end
	autoQueueHold = state.autoQueueHold == true
	globalQueueRevision = queueRevision
	return true
end

-- Playlist edits are persistent per playlist, but an active rotation is shared
-- state. Republish its complete ordered track list atomically so every server
-- drops stale automatic entries and resumes from the same rotation definition.
ControllerFunctions.syncGlobalPlaylistRotation = function(): (boolean, string?)
	if not globalQueueMode then return true, nil end
	local callOk, changed, state, message = false, false, nil, nil
	if activePlaylistId and #activePlaylistTracks > 0 then
		local trackIds = {}
		for _, track in ipairs(activePlaylistTracks) do
			table.insert(trackIds, track.id)
		end
		callOk, changed, state, message = ControllerFunctions.globalInvoke(
			"SetGlobalPlaylistRotation", activePlaylistId, activePlaylistName, trackIds
		)
	else
		callOk, changed, state, message = ControllerFunctions.globalInvoke("SetGlobalPlaylistRotation", nil)
	end
	if not callOk or changed ~= true or typeof(state) ~= "table" then
		if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
		return false, tostring(message or "The shared playlist rotation could not be updated.")
	end
	if not ControllerFunctions.applyGlobalQueueState(state) then
		return false, "The shared playlist state could not be applied."
	end
	return true, nil
end

syncGlobalQueueSnapshot = function(): boolean
	if not globalQueueMode or globalQueueSyncBusy then return false end
	globalQueueSyncBusy = true
	-- A malformed or unexpectedly-shaped bridge response must not strand the
	-- sync lock. Keep the whole read/apply path protected and always release it.
	local syncOk, applied = pcall(function(): boolean
		local callOk, readOk, state = ControllerFunctions.globalInvoke("GetGlobalQueueState")
		return callOk == true and readOk == true and ControllerFunctions.applyGlobalQueueState(state)
	end)
	globalQueueSyncBusy = false
	if not syncOk then
		warn("[ClubMusic] Global queue snapshot reconciliation failed: " .. tostring(applied))
		return false
	end
	if applied then publishState(nil) end
	return applied == true
end

enqueueGlobalQueueEntry = function(entry: QueueEntry): (boolean, string?)
	local callOk, writeOk, state, message = ControllerFunctions.globalInvoke(
		"EnqueueGlobalQueueEntry", entry, CONFIG.MaxQueueSize, localCatalogRevision
	)
	if typeof(state) == "table" then ControllerFunctions.applyGlobalQueueState(state) end
	if callOk and writeOk == true then return true, nil end
	if tostring(message) == "Catalog changed on another server; refresh and retry."
		and ControllerFunctions.refreshCatalogWhenReady() then
		if not TRACK_BY_ID[entry.trackId] then return false, "That track is no longer in the shared catalog." end
		callOk, writeOk, state, message = ControllerFunctions.globalInvoke(
			"EnqueueGlobalQueueEntry", entry, CONFIG.MaxQueueSize, localCatalogRevision
		)
		if typeof(state) == "table" then ControllerFunctions.applyGlobalQueueState(state) end
		if callOk and writeOk == true then return true, nil end
	end
	if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
	return false, tostring(message or "Global queue is unavailable.")
end

enqueueGlobalQueueBatch = function(entries: {QueueEntry}): (boolean, string?)
	local callOk, writeOk, state, message = ControllerFunctions.globalInvoke(
		"EnqueueGlobalQueueBatch", entries, CONFIG.MaxQueueSize, CONFIG.AutoQueueTarget, localCatalogRevision
	)
	if typeof(state) == "table" then ControllerFunctions.applyGlobalQueueState(state) end
	if callOk and writeOk == true then return true, nil end
	if tostring(message) == "Catalog changed on another server; refresh and retry."
		and ControllerFunctions.refreshCatalogWhenReady() then
		local allTracksPresent = true
		for _, entry in ipairs(entries) do
			if not TRACK_BY_ID[entry.trackId] then allTracksPresent = false; break end
		end
		if not allTracksPresent then
			-- Rebuild the Auto DJ batch from the refreshed catalog rather than
			-- leaving a short queue after a stale server selected a deleted ID.
			task.defer(ControllerFunctions.topUpAuto)
			return false, "An automatic track is no longer in the shared catalog; refill is being rebuilt."
		end
		callOk, writeOk, state, message = ControllerFunctions.globalInvoke(
			"EnqueueGlobalQueueBatch", entries, CONFIG.MaxQueueSize, CONFIG.AutoQueueTarget, localCatalogRevision
		)
		if typeof(state) == "table" then ControllerFunctions.applyGlobalQueueState(state) end
		if callOk and writeOk == true then return true, nil end
	end
	if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
	return false, tostring(message or "Global automatic queue refill is unavailable.")
end

ControllerFunctions.advance = function(expectedGeneration: number?): (boolean, string?)
	-- Every transition is synchronous and generation-checked. This prevents the
	-- duration clock and playback watchdog from advancing the same track twice.
	if transitionInProgress then return false, "A track transition is already in progress." end
	if expectedGeneration ~= nil and expectedGeneration ~= playbackGeneration then
		return false, "The current track changed before the transition started."
	end
	ControllerFunctions.cancelAudioTransition("advance")
	transitionInProgress = true
	if globalQueueMode then
		-- Always release the transition lock, including when fallback selection,
		-- state synchronization, or post-transition queue maintenance throws.
		local branchOk, advanced, reason = pcall(function(): (boolean, string?)
			-- A queue snapshot carries the catalog epoch. Refresh stale local catalog
			-- data before choosing a fallback so removed IDs are never replayed.
			if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
			if localCatalogRevision ~= globalCatalogRevision then
				if not ControllerFunctions.refreshCatalogWhenReady() then
					return false, "The shared catalog is updating; track transition will retry."
				end
			end
			if globalPlaylistRotationEnabled and not activePlaylistId then
				local rotationSynced, rotationMessage = ControllerFunctions.syncGlobalPlaylistRotation()
				if not rotationSynced then
					return false, "The shared playlist rotation is still recovering: " .. tostring(rotationMessage)
				end
			end
			-- Build one fallback entry for this transition. Retrying a stale revision
			-- must not consume additional playlist cursor positions or pick new tracks.
			local playlistFallback = ControllerFunctions.nextPlaylistTrack()
			local fallback = if playlistFallback then ControllerFunctions.makeEntry(playlistFallback, "playlist", nil) else ControllerFunctions.makeEntry(ControllerFunctions.pickAutoTrack(), "auto", nil)
			local function attemptGlobalAdvance(): (boolean, string?)
				local expectedRevision = globalTrackRevision
				local callOk, didAdvance, state, message = ControllerFunctions.globalInvoke(
					"AdvanceGlobalQueue", expectedRevision, fallback, localCatalogRevision
				)
				if typeof(state) == "table" then ControllerFunctions.applyGlobalQueueState(state) end
				if callOk and didAdvance == true and typeof(state) == "table" then
					return true, nil
				end
				return false, tostring(message or (if callOk then "The shared queue rejected the transition." else "The shared queue service is unavailable."))
			end
			local didAdvance, failureReason = attemptGlobalAdvance()
			if not didAdvance and failureReason == "Catalog changed on another server; refresh and retry." then
				-- The reservation/revision may have committed after the preflight
				-- snapshot. Reconcile the catalog, then retry once with the refreshed
				-- playlist cursor or a new Auto DJ fallback if the old ID disappeared.
				if syncGlobalQueueSnapshot and syncGlobalQueueSnapshot()
					and ControllerFunctions.refreshCatalogWhenReady() then
					if not TRACK_BY_ID[fallback.trackId] then
						local refreshedPlaylistTrack = ControllerFunctions.nextPlaylistTrack()
						fallback = if refreshedPlaylistTrack
							then ControllerFunctions.makeEntry(refreshedPlaylistTrack, "playlist", nil)
							else ControllerFunctions.makeEntry(ControllerFunctions.pickAutoTrack(), "auto", nil)
					end
					didAdvance, failureReason = attemptGlobalAdvance()
				end
			end
			-- A stale revision means another server has already won this transition.
			-- Refresh and accept that authoritative advance instead of issuing a
			-- second skip against the newly-current track (which would double-skip).
			if not didAdvance and failureReason == "Track already advanced by another server." then
				local previousRevision = globalTrackRevision
				local refreshed = false
				-- Snapshot sync may already be running in another event callback.
				for refreshAttempt = 1, 10 do
					if syncGlobalQueueSnapshot and syncGlobalQueueSnapshot()
						and globalTrackRevision > previousRevision then
						refreshed = true
						break
					end
					task.wait(0.1)
				end
				if refreshed then
					didAdvance, failureReason = true, nil
				else
					failureReason = "The shared track changed, but this server could not confirm the newer snapshot. Please retry."
				end
			end
			-- Keep the transition lock scoped to the authoritative CAS and any
			-- required stale-revision confirmation. Queue replenishment and the
			-- follow-up snapshot can yield on DataStore work, so they must run only
			-- after the lock is released.
			return didAdvance, failureReason
		end)
		transitionInProgress = false
		if not branchOk then
			local failure = "Global track transition failed unexpectedly: " .. tostring(advanced)
			warn("[ClubMusic] " .. failure)
			return false, failure
		end
		if not advanced then
			warn("[ClubMusic] Global transition was not applied: " .. tostring(reason))
			if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
			return false, reason
		end
		local maintenanceOk, maintenanceError = pcall(function()
			ControllerFunctions.topUpAuto()
			if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
		end)
		if not maintenanceOk then
			warn("[ClubMusic] Track advanced, but post-transition queue maintenance failed: " .. tostring(maintenanceError))
		end
		return true, nil
	end
	local ok, err = pcall(function()
		local nextEntry = queueManager:PopNext()
		if nextEntry then
		else nextEntry = ControllerFunctions.makeEntry(ControllerFunctions.pickAutoTrack(), "auto", nil) end
		ControllerFunctions.setNowPlaying(nextEntry :: QueueEntry)
		ControllerFunctions.topUpAuto()
	end)
	transitionInProgress = false
	if not ok then
		warn("[ClubMusic] Track transition failed: " .. tostring(err))
		return false, "The local track transition failed."
	end
	return true, nil
end

-- Boot: start with an auto-selected track and a visible auto queue.
ControllerFunctions.setNowPlaying(ControllerFunctions.makeEntry(TRACK_BY_ID["edm-0"], "auto", nil))
ControllerFunctions.topUpAuto()

-- Switch to shared authority only when the separately configured global service
-- confirms it is enabled. Studio remains local unless explicitly enabled there.
task.spawn(function()
	local enabledCallOk, enabled = false, false
	for _ = 1, 30 do
		enabledCallOk, enabled = ControllerFunctions.globalInvoke("IsEnabled")
		if enabledCallOk then break end
		task.wait(2)
	end
	if not enabledCallOk or enabled ~= true then return end
	globalQueueMode = true
	local readOk = syncGlobalQueueSnapshot and syncGlobalQueueSnapshot()
	if not readOk then
		table.clear(queue)
		nowPlaying.trackId = ""; nowPlaying.title = ""; nowPlaying.artist = ""; nowPlaying.elapsed = 0
		ControllerFunctions.stopServerMusic()
		warn("[ClubMusic] Global queue could not be loaded; shared playback and requests remain fail-closed.")
		return
	end
	if localCatalogRevision ~= globalCatalogRevision then
		if not ControllerFunctions.refreshCatalogWhenReady() then
			warn("[ClubMusic] Catalog revision could not be synchronized; global queue writes remain blocked on this server.")
			return
		end
	end
	if globalPlaylistRotationEnabled and not activePlaylistId then
		local rotationSynced, rotationMessage = ControllerFunctions.syncGlobalPlaylistRotation()
		if not rotationSynced then
			warn("[ClubMusic] Empty global playlist rotation could not be cleared: " .. tostring(rotationMessage))
			return
		end
	end
	if nowPlaying.trackId == "" then
		local playlistFallback = ControllerFunctions.nextPlaylistTrack()
		local fallback = if playlistFallback then ControllerFunctions.makeEntry(playlistFallback, "playlist", nil) else ControllerFunctions.makeEntry(ControllerFunctions.pickAutoTrack(), "auto", nil)
		local callOk, advanced, state = ControllerFunctions.globalInvoke("AdvanceGlobalQueue", globalTrackRevision, fallback, localCatalogRevision)
		if callOk and advanced == true and typeof(state) == "table" then ControllerFunctions.applyGlobalQueueState(state)
		elseif syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
	end
	if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
	ControllerFunctions.topUpAuto()
end)

-- MessagingService is the primary fast invalidation path. Periodic snapshots are
-- a repair fallback. A server with no synchronized current track is recovering
-- from startup/service unavailability, so retry it quickly instead of waiting
-- through the normal low-frequency reconciliation interval.
task.spawn(function()
	while script.Parent do
		local recoveringPlayback = globalQueueMode and nowPlaying.trackId == ""
		task.wait(if recoveringPlayback then 5 + math.random(0, 5) else 90 + math.random(0, 30))
		if globalQueueMode then
			local synchronized = syncGlobalQueueSnapshot and syncGlobalQueueSnapshot()
			if synchronized and nowPlaying.trackId == "" then
				-- Use the controller's generation-checked transition path. It owns
				-- the transition lock, authoritative CAS, snapshot application, and
				-- post-transition queue refill; do not issue a parallel raw advance.
				ControllerFunctions.advance(globalTrackRevision)
			end
			-- Queue refill is performed by the server that wins the atomic track transition.
			-- Periodic repair only refreshes missed state notifications; it must not make every server race to refill.
		end
	end
end)

-- Skip voting ---------------------------------------------------------------------

ControllerFunctions.skipStatus = function(player: Player?): (number, number, boolean)
	local list = Players:GetPlayers()
	local count = #list
	local votes = 0
	for _, p in ipairs(list) do
		if skipVotes[p.UserId] then votes += 1 end
	end
	local needed = math.min(count, math.max(CONFIG.SkipVoteMin, math.ceil(count * CONFIG.SkipVoteRatio)))
	needed = math.max(needed, 1)
	local voted = if player then skipVotes[player.UserId] == true else false
	return votes, needed, voted
end

ControllerFunctions.checkSkipVotes = function(): boolean
	local votes, needed = ControllerFunctions.skipStatus(nil)
	if votes > 0 and votes >= needed then
		ControllerFunctions.advance()
		return true
	end
	return false
end

-- State publishing ------------------------------------------------------------------

ControllerFunctions.snapshotFor = function(player: Player)
	local profile = profiles[player.UserId] or ControllerFunctions.defaultProfile()
	local level = ControllerFunctions.getLevel(player)
	local vip = ControllerFunctions.isVip(player)

	local safeQueue = {}
	for _, item in ipairs(queue) do
		table.insert(safeQueue, {
			id = item.id, trackId = item.trackId, title = item.title, artist = item.artist,
			duration = item.duration, requestedBy = item.requestedBy, genre = item.genre,
			source = item.source, vip = item.vip,
		})
	end

	local favorites = {}
	for id in pairs(profile.favorites) do favorites[id] = true end

	local votes, needed, voted = ControllerFunctions.skipStatus(player)

	-- Title slots use string keys so sparse slots survive the remote.
	local slotsOut: {[string]: any} = {}
	for i = 1, TITLE_SLOT_COUNT do
		local slot = profile.titleSlots[i]
		if slot then
			slotsOut[tostring(i)] = {
				text = slot.text, effect = slot.effect, set = slot.set, font = slot.font,
				style = slot.style, textSize = slot.textSize, heightOffset = slot.height, viewDistance = slot.distance,
			}
		end
	end
	local pricesOut: {[string]: number} = {}
	local productsOut: {[string]: number} = {}
	for i = 2, TITLE_SLOT_COUNT do
		pricesOut[tostring(i)] = CONFIG.TitleSlotPrices[i] or 0
		productsOut[tostring(i)] = CONFIG.TitleSlotProductIds[i] or 0
	end
	local activeSlotData = profile.titleSlots[profile.activeSlot]
	-- The rotation cursor points beyond tracks already prefetched into the queue.
	-- Derive the visible position from the authoritative current track instead.
	local playlistPosition: number? = nil
	local playlistTotal = if activePlaylistId ~= nil then #activePlaylistTracks else 0
	local playlistRemaining: number? = nil
	if activePlaylistId ~= nil and nowPlaying.source == "playlist" and playlistTotal > 0 then
		for index, track in ipairs(activePlaylistTracks) do
			if track.id == nowPlaying.trackId then
				playlistPosition = index
				playlistRemaining = playlistTotal - index
				break
			end
		end
	end

	local snapshot = {
		rank = ControllerFunctions.getRank(player),
		perm = level,
		vip = vip,
		customTitleUnlocked = ControllerFunctions.isSultan(player),
		queue = safeQueue,
		nowPlaying = {
			trackId = nowPlaying.trackId, title = nowPlaying.title, artist = nowPlaying.artist,
			genre = nowPlaying.genre, duration = nowPlaying.duration, elapsed = nowPlaying.elapsed,
			dj = nowPlaying.dj, source = nowPlaying.source, requestedBy = nowPlaying.requestedBy,
			vip = nowPlaying.vip, soundId = nowPlaying.soundId, paused = playbackPaused,
			playlist = {
				active = activePlaylistId ~= nil, id = activePlaylistId, name = activePlaylistName,
				currentPosition = playlistPosition, totalTracks = playlistTotal,
				remainingBeforeLoop = playlistRemaining,
			},
		},
		reloadNonce = reloadNonce[player.UserId] or 0,
		favorites = favorites,
		skip = { votes = votes, needed = needed, voted = voted },
		requests = { used = requestCounts[player.UserId] or 0, limit = ControllerFunctions.requestLimitFor(player) },
		locked = requestsLocked,
		blocked = blockedUsers[player.UserId] == true,
		vipPerks = {
			slots = CONFIG.VipMaxRequestsPerPlayer,
			cooldown = CONFIG.VipCooldownSeconds,
			baseSlots = CONFIG.MaxRequestsPerPlayer,
			baseCooldown = CONFIG.RequestCooldownSeconds,
			priority = CONFIG.VipPriority,
		},
		vipGamePassId = CONFIG.VipGamePassId,
		vvipGamePassId = CONFIG.VvipGamePassId,
		sultanGamePassId = CONFIG.TikiTideSultanPassId,
		passTier = ControllerFunctions.passTier(player),
		passName = if ControllerFunctions.isSultan(player) then "TIKI TIDE SULTAN" elseif ControllerFunctions.isVvip(player) then "VVIP" elseif ControllerFunctions.isVip(player) then "VIP" else "GUEST",
		passPerks = {
			vip = { slots = CONFIG.VipMaxRequestsPerPlayer, cooldown = CONFIG.VipCooldownSeconds },
			vvip = { slots = CONFIG.VvipMaxRequestsPerPlayer, cooldown = CONFIG.VvipCooldownSeconds },
			sultan = { slots = CONFIG.SultanMaxRequestsPerPlayer, cooldown = CONFIG.SultanCooldownSeconds, priority = "highest" },
		},
		equippedTag = profile.equippedTag,
		ownedTags = profile.ownedTags,
		clubPlaySeconds = profile.clubPlaySeconds,
		titleSlots = {
			unlocked = profile.unlockedSlots,
			active = profile.activeSlot,
			visible = profile.showCustomTitle,
			slots = slotsOut,
			prices = pricesOut,
			products = productsOut,
		},
		-- Legacy fields (mirror the active slot) for older clients.
		customTitle = if activeSlotData then activeSlotData.text else "",
		titleColor = if activeSlotData and activeSlotData.effect == "fixed" then activeSlotData.set else "gold",
		titleStyle = if activeSlotData then activeSlotData.style else "normal",
		showCustomTitle = profile.showCustomTitle,
		loginStreak = profile.loginStreak,
		claimedToday = profile.claimedToday,
		tickets = profile.tickets,
		coins = profile.coins,
		glowsticks = profile.glowsticks,
		skipTokens = profile.skipTokens,
		neonTrail = profile.neonTrail,
		xp = profile.xp,
		level = math.floor(profile.xp / CONFIG.XPPerLevel) + 1,
		xpToNextLevel = CONFIG.XPPerLevel - (profile.xp % CONFIG.XPPerLevel),
		xpMultiplier = if cachedGlobalXpExpiresAt > os.time() then cachedGlobalXpMultiplier
			elseif cachedGlobalXpLowerExpiresAt > os.time() then 2 else 1,
		xpBoostExpiresAt = if cachedGlobalXpExpiresAt > os.time() then cachedGlobalXpExpiresAt
			elseif cachedGlobalXpLowerExpiresAt > os.time() then cachedGlobalXpLowerExpiresAt else 0,
		xpBoostProductIds = { twoX = CONFIG.XPBoost2xProductId, fourX = CONFIG.XPBoost4xProductId },
		groupId = CONFIG.GroupId,
		players = nil :: any,
	}

	-- Only staff receive the moderation roster.
	if level >= 1 then
		local roster = {}
		for _, other in ipairs(Players:GetPlayers()) do
			table.insert(roster, {
				userId = other.UserId,
				name = other.Name,
				displayName = other.DisplayName,
				rank = ControllerFunctions.getRank(other),
				vip = ControllerFunctions.isVip(other),
				tempVip = tempVip[other.UserId] == true,
				blocked = blockedUsers[other.UserId] == true,
				requests = requestCounts[other.UserId] or 0,
				canMod = ControllerFunctions.canModerate(player, other),
			})
		end
		snapshot.players = roster
	end

	return snapshot
end

-- Coalesce bursts of state changes. A nil target means a full server broadcast;
-- individual player refreshes are batched when no full broadcast is pending.
local pendingStateAll = false
local pendingStatePlayers: {[number]: boolean} = {}
local stateFlushScheduled = false

ControllerFunctions.flushPendingState = function()
	task.wait(CONFIG.GlobalStateMinIntervalSeconds)
	local sendAll = pendingStateAll
	local targets = pendingStatePlayers
	pendingStateAll = false
	pendingStatePlayers = {}

	if sendAll then
		for _, target in ipairs(Players:GetPlayers()) do
			local ok, snapshot = pcall(ControllerFunctions.snapshotFor, target)
			if ok and target.Parent == Players then
				pcall(function() stateRemote:FireClient(target, snapshot) end)
			end
		end
	else
		for userId in pairs(targets) do
			local target = Players:GetPlayerByUserId(userId)
			if target then
				local ok, snapshot = pcall(ControllerFunctions.snapshotFor, target)
				if ok then pcall(function() stateRemote:FireClient(target, snapshot) end) end
			end
		end
	end

	stateFlushScheduled = false
	-- Work queued during the flush is handled by one further coalesced pass.
	if pendingStateAll or next(pendingStatePlayers) ~= nil then
		stateFlushScheduled = true
		task.defer(ControllerFunctions.flushPendingState)
	end
end

publishState = function(player: Player?)
	if player then
		pendingStatePlayers[player.UserId] = true
	else
		pendingStateAll = true
		table.clear(pendingStatePlayers)
	end
	if not stateFlushScheduled then
		stateFlushScheduled = true
		task.defer(ControllerFunctions.flushPendingState)
	end
end

notify = function(player: Player, text: string, kind: string?)
	noticeRemote:FireClient(player, { text = text, kind = kind or "info" })
end

ControllerFunctions.broadcast = function(text: string, kind: string?)
	noticeRemote:FireAllClients({ text = text, kind = kind or "info" })
end


-- Developer Product purchases --------------------------------------------------
-- Replace each 0 with a UNIQUE Developer Product ID from Creator Dashboard.
-- A zero ID is intentionally ignored so unconfigured products cannot collide.
local PRODUCT_IDS = {
	-- Donations / Tips
	Coconut = 0,
	Pineapple = 0,
	TikiTorch = 0,
	Volcano = 0,
	IslandLegend = 0,

	-- Shop Items
	Glowsticks = 0,
	TikiMask = 0,
	NeonAura = 0,
	NeonLei = 0,
	LEDShades = 0,
	XPBoost2x = CONFIG.XPBoost2xProductId,
	XPBoost4x = CONFIG.XPBoost4xProductId,
}

type ProductData = {
	type: "Donation" | "Item" | "TitleSlot" | "XPBoost",
	productId: number?,
	perk: string?,
	amount: number?,
	name: string?,
	costCoins: number?,
	slot: number?,
	multiplier: number?,
	duration: number?,
}

local PRODUCT_MAP: {[number]: ProductData} = {}

ControllerFunctions.registerProduct = function(productId: number, data: ProductData)
	if productId <= 0 then
		return -- Not configured yet.
	end
	if PRODUCT_MAP[productId] then
		error(string.format("[ClubMusic] Duplicate Developer Product ID: %d", productId))
	end
	data.productId = productId
	PRODUCT_MAP[productId] = data
end

-- Donations / Tips
ControllerFunctions.registerProduct(PRODUCT_IDS.Coconut, {
	type = "Donation", perk = "Coconut", amount = 10,
})
ControllerFunctions.registerProduct(PRODUCT_IDS.Pineapple, {
	type = "Donation", perk = "Pineapple", amount = 50,
})
ControllerFunctions.registerProduct(PRODUCT_IDS.TikiTorch, {
	type = "Donation", perk = "Tiki Torch", amount = 100,
})
ControllerFunctions.registerProduct(PRODUCT_IDS.Volcano, {
	type = "Donation", perk = "Volcano", amount = 500,
})
ControllerFunctions.registerProduct(PRODUCT_IDS.IslandLegend, {
	type = "Donation", perk = "Island Legend", amount = 1000,
})

-- Shop Items
ControllerFunctions.registerProduct(PRODUCT_IDS.Glowsticks, {
	type = "Item", name = "Glowsticks", costCoins = 75,
})
ControllerFunctions.registerProduct(PRODUCT_IDS.TikiMask, {
	type = "Item", name = "Tiki Mask", costCoins = 250,
})
ControllerFunctions.registerProduct(PRODUCT_IDS.NeonAura, {
	type = "Item", name = "Neon Aura", costCoins = 600,
})
ControllerFunctions.registerProduct(PRODUCT_IDS.NeonLei, {
	type = "Item", name = "Neon Lei", costCoins = 150,
})
ControllerFunctions.registerProduct(PRODUCT_IDS.LEDShades, {
	type = "Item", name = "LED Shades", costCoins = 320,
})
ControllerFunctions.registerProduct(PRODUCT_IDS.XPBoost2x, { type = "XPBoost", multiplier = 2, duration = 900, name = "2x XP Boost" })
ControllerFunctions.registerProduct(PRODUCT_IDS.XPBoost4x, { type = "XPBoost", multiplier = 4, duration = 1800, name = "4x XP Boost" })

-- Title slots (slot 1 is free; slots 2 and 3 are paid)
for slotNumber = 2, TITLE_SLOT_COUNT do
	ControllerFunctions.registerProduct(CONFIG.TitleSlotProductIds[slotNumber] or 0, {
		type = "TitleSlot", slot = slotNumber, name = "Title Slot " .. tostring(slotNumber),
	})
end

-- Durable receipt journal. The profile reward and pending marker are committed in
-- one UpdateAsync; a separate hashed per-purchase journal is completed before
-- ProcessReceipt acknowledges the purchase. The legacy profile receipt map is read
-- for migration only and is not expanded by new purchases.
ControllerFunctions.applyReceiptToStoredData = function(data: {[string]: any}, productData: {[string]: any}): boolean
	if productData.type == "Donation" then
		local amount = math.max(0, math.floor(tonumber(productData.amount) or 0))
		data.tickets = math.max(0, math.floor(tonumber(data.tickets) or 0)) + math.floor(amount * 1.5)
		data.coins = math.max(0, math.floor(tonumber(data.coins) or 0)) + amount * 10
		return true
	elseif productData.type == "Item" then
		local name = productData.name or ""
		data.ownedTags = if typeof(data.ownedTags) == "table" then data.ownedTags else {}
		if name == "Glowsticks" then data.glowsticks = math.max(0, math.floor(tonumber(data.glowsticks) or 0)) + 2
		elseif name == "Tiki Mask" then data.ownedTags.tiki = true
		elseif name == "Neon Aura" then data.ownedTags.sunset = true
		elseif name == "Neon Lei" then data.coins = math.max(0, math.floor(tonumber(data.coins) or 0)) + 500
		elseif name == "LED Shades" then data.ownedTags.bass = true
		else return false end
		return true
	elseif productData.type == "TitleSlot" then
		local slotNumber = math.clamp(math.floor(tonumber(productData.slot) or 2), 2, TITLE_SLOT_COUNT)
		data.unlockedSlots = math.max(1, math.floor(tonumber(data.unlockedSlots) or 1), slotNumber)
		return true
	elseif productData.type == "XPBoost" then
		return productData.multiplier == 2 or productData.multiplier == 4
	end
	return false
end

ControllerFunctions.applyReceiptToMemory = function(profile: Profile, productData: {[string]: any})
	if productData.type == "Donation" then
		local amount = math.max(0, math.floor(tonumber(productData.amount) or 0))
		profile.tickets += math.floor(amount * 1.5)
		profile.coins += amount * 10
	elseif productData.type == "Item" then
		local name = productData.name or ""
		if name == "Glowsticks" then profile.glowsticks += 2
		elseif name == "Tiki Mask" then profile.ownedTags.tiki = true
		elseif name == "Neon Aura" then profile.ownedTags.sunset = true
		elseif name == "Neon Lei" then profile.coins += 500
		elseif name == "LED Shades" then profile.ownedTags.bass = true end
	elseif productData.type == "TitleSlot" then
		local slotNumber = math.clamp(math.floor(tonumber(productData.slot) or 2), 2, TITLE_SLOT_COUNT)
		profile.unlockedSlots = math.max(profile.unlockedSlots, slotNumber)
	elseif productData.type == "XPBoost" then
		-- The global boost is applied by the global service, not to one profile.
	end
end

local processedReceipts: {[string]: boolean} = {}

local productReceiptJournalStore = DataStoreService:GetDataStore("ClubMusic_ProductReceipts_v1")

ControllerFunctions.productReceiptKey = function(userId: number, receiptId: string): string
	return "r_" .. ReceiptHash.KeySuffix(tostring(userId) .. ":" .. receiptId)
end

ControllerFunctions.recoverPendingProductReceipt = function(userId: number): (boolean, string?)
	local journalStore = productReceiptJournalStore
	if not ControllerFunctions.waitForDataStoreBudget(10) then return false, "DataStore budget is busy while recovering a receipt" end
	local readOk, profileData = pcall(function() return store:GetAsync(tostring(userId)) end)
	if not readOk then return false, tostring(profileData) end
	if typeof(profileData) ~= "table" or typeof(profileData.pendingReceipt) ~= "string" then return true, nil end

	local pendingId = profileData.pendingReceipt
	local journalKey = ControllerFunctions.productReceiptKey(userId, pendingId)
	if not ControllerFunctions.waitForDataStoreBudget(10) then return false, "DataStore budget is busy while reading receipt journal" end
	local journalOk, journal = pcall(function() return journalStore:GetAsync(journalKey) end)
	if not journalOk then return false, tostring(journal) end
	if typeof(journal) ~= "table" or journal.purchaseId ~= pendingId
		or journal.userId ~= userId or journal.status ~= "Prepared" and journal.status ~= "Completed" then
		warn("[ClubMusic] Profile has an unrecoverable pending receipt marker for userId " .. tostring(userId))
		return false, "Pending receipt journal is missing or mismatched"
	end

	local pendingMemory = receiptMemoryPending[pendingId]
	local currentProfile = profiles[userId]
	if pendingMemory and pendingMemory.profile == currentProfile and currentProfile then
		ControllerFunctions.applyReceiptToMemory(currentProfile, pendingMemory.productData)
		receiptMemoryApplied[pendingId] = currentProfile
		receiptMemoryPending[pendingId] = nil
	end

	if journal.status ~= "Completed" then
		if not ControllerFunctions.waitForDataStoreBudget(10) then return false, "DataStore budget is busy while completing receipt journal" end
		local completeOk, completed = pcall(function()
			return journalStore:UpdateAsync(journalKey, function(old)
				if typeof(old) ~= "table" or old.purchaseId ~= pendingId or old.userId ~= userId then return nil end
				local nextRecord = table.clone(old)
				nextRecord.status = "Completed"
				nextRecord.completedAt = os.time()
				return nextRecord
			end)
		end)
		if not completeOk or typeof(completed) ~= "table" or completed.status ~= "Completed" then
			return false, "Could not complete pending receipt journal"
		end
	end

	if not ControllerFunctions.waitForDataStoreBudget(10) then return false, "DataStore budget is busy while clearing pending receipt" end
	local clearOk, cleared = pcall(function()
		return store:UpdateAsync(tostring(userId), function(old)
			if typeof(old) ~= "table" or typeof(old.sessionLock) ~= "table"
				or old.sessionLock.owner ~= SESSION_TOKEN then return nil end
			if old.pendingReceipt ~= pendingId then return old end
			local nextData = table.clone(old)
			nextData.pendingReceipt = nil
			nextData.sessionLock = { owner = SESSION_TOKEN, expiresAt = os.time() + SESSION_LOCK_SECONDS }
			return nextData
		end)
	end)
	if not clearOk or typeof(cleared) ~= "table" or cleared.pendingReceipt == pendingId then
		return false, "Could not clear recovered pending receipt marker"
	end
	return true, nil
end

ControllerFunctions.persistReceipt = function(userId: number, receiptId: string, productData: {[string]: any}): (boolean, boolean, string?)
	if USE_STUDIO_MEMORY_PROFILES then
		return profiles[userId] ~= nil, false, nil
	end
	if not ControllerFunctions.acquireProfileWriteLock(userId) then
		return false, false, "Profile is busy; receipt will be retried"
	end

	local journalStore = productReceiptJournalStore
	local recovered, recoveryError = ControllerFunctions.recoverPendingProductReceipt(userId)
	if not recovered then ControllerFunctions.releaseProfileWriteLock(userId); return false, false, recoveryError end

	local journalKey = ControllerFunctions.productReceiptKey(userId, receiptId)
	if not ControllerFunctions.waitForDataStoreBudget(10) then
		ControllerFunctions.releaseProfileWriteLock(userId)
		return false, false, "DataStore budget is busy while reading receipt journal"
	end
	local readOk, journal = pcall(function() return journalStore:GetAsync(journalKey) end)
	if not readOk then ControllerFunctions.releaseProfileWriteLock(userId); return false, false, tostring(journal) end
	if typeof(journal) == "table" then
		if journal.purchaseId ~= receiptId or journal.userId ~= userId or journal.productId ~= productData.productId then
			ControllerFunctions.releaseProfileWriteLock(userId)
			return false, false, "Receipt journal key collision or product mismatch"
		end
		if journal.status == "Completed" then
			local currentProfile = profiles[userId]
			local pendingMemory = receiptMemoryPending[receiptId]
			if pendingMemory and pendingMemory.profile == currentProfile and currentProfile then
				ControllerFunctions.applyReceiptToMemory(currentProfile, pendingMemory.productData)
				receiptMemoryApplied[receiptId] = currentProfile
				receiptMemoryPending[receiptId] = nil
			end
			local memoryApplied = currentProfile ~= nil and receiptMemoryApplied[receiptId] == currentProfile
			if not memoryApplied then receiptMemoryPending[receiptId] = nil end
			ControllerFunctions.releaseProfileWriteLock(userId)
			return true, not memoryApplied, nil
		end
		if journal.status ~= "Prepared" then
			ControllerFunctions.releaseProfileWriteLock(userId)
			return false, false, "Receipt journal has an invalid status"
		end
	else
		if not ControllerFunctions.waitForDataStoreBudget(10) then ControllerFunctions.releaseProfileWriteLock(userId); return false, false, "DataStore budget is busy while preparing receipt" end
		local prepareOk, prepared = pcall(function()
			return journalStore:UpdateAsync(journalKey, function(old)
				if typeof(old) == "table" then return old end
				return {status = "Prepared", purchaseId = receiptId, userId = userId,
					productId = productData.productId, productType = productData.type, createdAt = os.time()}
			end)
		end)
		if not prepareOk or typeof(prepared) ~= "table" or prepared.purchaseId ~= receiptId
			or prepared.userId ~= userId or prepared.productId ~= productData.productId
			or (prepared.status ~= "Prepared" and prepared.status ~= "Completed") then
			ControllerFunctions.releaseProfileWriteLock(userId)
			return false, false, "Could not prepare durable receipt journal"
		end
		journal = prepared
		if prepared.status == "Completed" then
			local currentProfile = profiles[userId]
			local pendingMemory = receiptMemoryPending[receiptId]
			if pendingMemory and pendingMemory.profile == currentProfile and currentProfile then
				ControllerFunctions.applyReceiptToMemory(currentProfile, pendingMemory.productData)
				receiptMemoryApplied[receiptId] = currentProfile
				receiptMemoryPending[receiptId] = nil
			end
			local memoryApplied = currentProfile ~= nil and receiptMemoryApplied[receiptId] == currentProfile
			if not memoryApplied then receiptMemoryPending[receiptId] = nil end
			ControllerFunctions.releaseProfileWriteLock(userId)
			return true, not memoryApplied, nil
		end
	end

	if not ControllerFunctions.waitForDataStoreBudget(10) then ControllerFunctions.releaseProfileWriteLock(userId); return false, false, "DataStore budget is busy while applying receipt" end
	local alreadyProcessed = false
	-- Set before yielding: UpdateAsync can commit even if the client-side call later errors.
	-- A retry can then reconcile the same in-memory Profile exactly once.
	local receiptProfile = profiles[userId]
	if not receiptProfile then ControllerFunctions.releaseProfileWriteLock(userId); return false, false, "Profile disappeared before receipt application" end
	receiptMemoryPending[receiptId] = {profile = receiptProfile, productData = productData}
	local applyOk, applied = pcall(function()
		return store:UpdateAsync(tostring(userId), function(oldData)
			if typeof(oldData) ~= "table" or typeof(oldData.sessionLock) ~= "table"
				or oldData.sessionLock.owner ~= SESSION_TOKEN then return nil end
			if typeof(oldData.pendingReceipt) == "string" then return nil end
			local data = table.clone(oldData)
			data.receiptIds = if typeof(data.receiptIds) == "table" then table.clone(data.receiptIds) else {}
			if data.receiptIds[receiptId] == true then
				alreadyProcessed = true
				return data
			end
			if not ControllerFunctions.applyReceiptToStoredData(data, productData) then return nil end
			data.pendingReceipt = receiptId -- reward and recovery marker are one atomic profile write.
			data.sessionLock = { owner = SESSION_TOKEN, expiresAt = os.time() + SESSION_LOCK_SECONDS }
			return data
		end)
	end)
	if not applyOk or typeof(applied) ~= "table" then
		ControllerFunctions.releaseProfileWriteLock(userId)
		return false, false, "Receipt reward was not confirmed in the profile"
	end

	if alreadyProcessed then
		receiptMemoryPending[receiptId] = nil
	else
		ControllerFunctions.applyReceiptToMemory(receiptProfile, productData)
		receiptMemoryApplied[receiptId] = receiptProfile
		receiptMemoryPending[receiptId] = nil
	end
	if not ControllerFunctions.waitForDataStoreBudget(10) then
		ControllerFunctions.releaseProfileWriteLock(userId)
		return false, false, "DataStore budget is busy while completing receipt journal"
	end
	local completeOk, completed = pcall(function()
		return journalStore:UpdateAsync(journalKey, function(old)
			if typeof(old) ~= "table" or old.purchaseId ~= receiptId or old.userId ~= userId then return nil end
			local nextRecord = table.clone(old)
			nextRecord.status = "Completed"
			nextRecord.completedAt = os.time()
			return nextRecord
		end)
	end)
	if not completeOk or typeof(completed) ~= "table" or completed.status ~= "Completed" then
		ControllerFunctions.releaseProfileWriteLock(userId)
		return false, false, "Reward is saved; receipt journal completion will recover on retry"
	end

	if not ControllerFunctions.waitForDataStoreBudget(10) then
		ControllerFunctions.releaseProfileWriteLock(userId)
		return false, false, "Receipt is durable; pending marker cleanup will recover on retry"
	end
	local clearOk, cleared = pcall(function()
		return store:UpdateAsync(tostring(userId), function(old)
			if typeof(old) ~= "table" or typeof(old.sessionLock) ~= "table"
				or old.sessionLock.owner ~= SESSION_TOKEN then return nil end
			if old.pendingReceipt ~= receiptId then return old end
			local nextData = table.clone(old)
			nextData.pendingReceipt = nil
			nextData.sessionLock = { owner = SESSION_TOKEN, expiresAt = os.time() + SESSION_LOCK_SECONDS }
			return nextData
		end)
	end)
	if not clearOk or typeof(cleared) ~= "table" or cleared.pendingReceipt == receiptId then
		ControllerFunctions.releaseProfileWriteLock(userId)
		return false, false, "Receipt is durable; pending marker cleanup will recover on retry"
	end

	ControllerFunctions.releaseProfileWriteLock(userId)
	return true, alreadyProcessed, nil
end

MarketplaceService.ProcessReceipt = function(receiptInfo: any)
	local userId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local receiptId = tostring(receiptInfo.PurchaseId)
	if typeof(userId) ~= "number" or typeof(productId) ~= "number"
		or receiptId == "" or #receiptId > 128 then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if processedReceipts[receiptId] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local player = Players:GetPlayerByUserId(userId)
	local profile = profiles[userId]
	if not player or not profile then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local productData = PRODUCT_MAP[productId]
	if not productData then
		warn(string.format("[ClubMusic] Unregistered Developer Product ID %d (receipt %s).", productId, receiptId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if productData.type == "XPBoost" then
		if RunService:IsStudio() then
			-- Studio uses session-only boost state because the global service is intentionally disabled.
			local key = productData.multiplier
			if key ~= 2 and key ~= 4 then return Enum.ProductPurchaseDecision.NotProcessedYet end
			local previousExpiry = if studioXpBoostMultiplier == key then studioXpBoostExpiresAt else os.time()
			studioXpBoostExpiresAt = math.min(os.time() + 30 * 24 * 60 * 60,
				math.max(os.time(), previousExpiry) + productData.duration)
			studioXpBoostMultiplier = key
			ControllerFunctions.setGlobalXPState(key, studioXpBoostExpiresAt)
		else
			local activateOk, activated, expiry, effectiveMultiplier = ControllerFunctions.globalInvoke(
				"ActivateGlobalXPBoost", productData.multiplier, productData.duration, receiptId
			)
			if not activateOk or activated ~= true then
				warn("[ClubMusic] Global XP boost activation failed; receipt will be retried.")
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			if typeof(expiry) == "number" and (effectiveMultiplier == 1 or effectiveMultiplier == 2 or effectiveMultiplier == 4) then
				ControllerFunctions.refreshGlobalXPBoost()
			end
		end
	end
	if productData.type == "XPBoost" then
		-- The global per-PurchaseId journal is authoritative for XP boosts.
		-- Do not write XP receipts into the legacy profile receipt map.
		processedReceipts[receiptId] = true
		notify(player, string.format("%dx global XP boost activated!", productData.multiplier), "ok")
		publishState(nil)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local ok, alreadyProcessed, err = ControllerFunctions.persistReceipt(userId, receiptId, productData)
	if not ok then
		warn("[ClubMusic] Receipt persistence failed for " .. receiptId .. ": " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- A receipt already in the durable ledger was granted by an earlier callback/server.
	-- The loaded profile already contains its reward, so never apply it twice in memory.
	if alreadyProcessed or processedReceipts[receiptId] then
		processedReceipts[receiptId] = true
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if profiles[userId] ~= profile then return Enum.ProductPurchaseDecision.NotProcessedYet end
	if USE_STUDIO_MEMORY_PROFILES then ControllerFunctions.applyReceiptToMemory(profile, productData) end
	receiptMemoryApplied[receiptId] = nil
	processedReceipts[receiptId] = true
	player:SetAttribute("Tickets", profile.tickets)
	player:SetAttribute("Coins", profile.coins)
	player:SetAttribute("Glowsticks", profile.glowsticks)
	player:SetAttribute("SkipTokens", profile.skipTokens)
	player:SetAttribute("NeonTrailUnlocked", profile.neonTrail)
	if productData.type == "TitleSlot" then ControllerFunctions.applyTitleAttributes(player, profile) end

	if productData.type == "Donation" then
		local amount = math.max(0, math.floor(tonumber(productData.amount) or 0))
		local perk = productData.perk or "Donation"
		if perk == "Coconut" then ControllerFunctions.broadcast(string.format("🌴 %s sent a Coconut Tip! (+%d Tickets)", player.DisplayName, math.floor(amount * 1.5)), "info")
		elseif perk == "Pineapple" then ControllerFunctions.broadcast(string.format("🎆 %s launched a Pineapple Firework burst!", player.DisplayName), "ok")
		elseif perk == "Tiki Torch" then ControllerFunctions.broadcast(string.format("🎊 %s filled the dancefloor with Stage Confetti!", player.DisplayName), "ok")
		elseif perk == "Volcano" then ControllerFunctions.broadcast(string.format("🔥 %s activated the Volcano Light Show!", player.DisplayName), "warn")
		elseif perk == "Island Legend" then ControllerFunctions.broadcast(string.format("👑 LEGENDARY: %s is displayed on the Big Stage Screens!", player.DisplayName), "info") end
	elseif productData.type == "Item" then
		notify(player, string.format("Purchase Successful: %s acquired!", productData.name or "Item"), "ok")
	elseif productData.type == "TitleSlot" then
		notify(player, string.format("Title slot %d unlocked!", profile.unlockedSlots), "ok")
	elseif productData.type == "XPBoost" then
		notify(player, string.format("%dx global XP boost activated!", productData.multiplier), "ok")
	end
	publishState(nil)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

ControllerFunctions.isValidString = function(value: any, maxLength: number): boolean
	return typeof(value) == "string" and #value > 0 and #value <= maxLength
end

-- Remote payloads are intentionally shallow and small. This rejects oversized
-- tables before action-specific code can inspect or retain attacker-controlled data.
ControllerFunctions.isBoundedPayload = function(payload: any): boolean
	if typeof(payload) ~= "table" then return false end
	local topCount = 0
	for key, value in pairs(payload) do
		topCount += 1
		if topCount > 16 or typeof(key) ~= "string" or #key > 32 then return false end
		if typeof(value) == "string" then
			if #value > 1024 then return false end
		elseif typeof(value) == "number" then
			if not ControllerFunctions.isFiniteNumber(value) then return false end
		elseif typeof(value) == "table" then
			local nestedCount = 0
			for nestedKey, nestedValue in pairs(value) do
				nestedCount += 1
				-- String keys (maps) or small positive integer keys (arrays such as the title "colors" list).
				local nestedKeyType = typeof(nestedKey)
				local validNestedKey = (nestedKeyType == "string" and #nestedKey <= 32)
					or (nestedKeyType == "number" and nestedKey % 1 == 0 and nestedKey >= 1 and nestedKey <= 16)
				if nestedCount > 16 or not validNestedKey then return false end
				local valueType = typeof(nestedValue)
				if valueType == "string" then
					if #nestedValue > 1024 then return false end
				elseif valueType == "number" then
					if not ControllerFunctions.isFiniteNumber(nestedValue) then return false end
				elseif valueType ~= "boolean" then
					return false
				end
			end
		elseif typeof(value) ~= "boolean" then
			return false
		end
	end
	return true
end

ControllerFunctions.findTarget = function(actor: Player, userId: any): Player?
	if not ControllerFunctions.isFiniteNumber(userId) or userId < 1 or userId % 1 ~= 0 or userId > 9007199254740991 then return nil end
	local target = Players:GetPlayerByUserId(userId)
	if not target then return nil end
	if target == actor then return nil end
	if not ControllerFunctions.canModerate(actor, target) then
		notify(actor, "You can't moderate someone with equal or higher rank.", "warn")
		return nil
	end
	return target
end

ControllerFunctions.purgeUserEntries = function(userId: number): number
	if globalQueueMode then
		local removedCount = 0
		for _, entry in ipairs(queue) do if entry.source == "player" and entry.userId == userId then removedCount += 1 end end
		local callOk, purged, state = ControllerFunctions.globalInvoke("PurgeGlobalUserQueueEntries", userId)
		if callOk and purged == true and typeof(state) == "table" then ControllerFunctions.applyGlobalQueueState(state); return removedCount end
		if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
		return 0
	end
	local removed = 0
	for index = #queue, 1, -1 do
		local entry = queue[index]
		if entry.source == "player" and entry.userId == userId then
			queueManager:RemoveAt(index, true)
			removed += 1
		end
	end
	if removed > 0 then ControllerFunctions.topUpAuto() end
	return removed
end

-- Returns a reason string when this player may NOT queue this track right now, otherwise nil.
-- Used by Creator Hub audio requests, which re-check after yielding for the asset lookup.
ControllerFunctions.requestBlockReason = function(player: Player, trackId: string, now: number): string?
	if blockedUsers[player.UserId] then return "Your requests are disabled by staff." end
	if requestsLocked and ControllerFunctions.getLevel(player) < 1 then return "Requests are locked by staff right now." end
	if ControllerFunctions.countPlayerEntries() >= CONFIG.MaxQueueSize then return "The request queue is full." end
	local cooldown = ControllerFunctions.cooldownFor(player)
	local sinceLast = now - (lastRequestAt[player.UserId] or -1000)
	if sinceLast < cooldown then
		return string.format("Slow down - wait %ds to request again.", math.ceil(cooldown - sinceLast))
	end
	local count = requestCounts[player.UserId] or 0
	local limit = ControllerFunctions.requestLimitFor(player)
	if count >= limit then
		return string.format("Request limit reached (%d/%d). Wait for your track to play.", count, limit)
	end
	if nowPlaying.trackId == trackId then return "That track is playing right now." end
	for _, queued in ipairs(queue) do
		if queued.trackId == trackId then return "That track is already in the queue." end
	end
	return nil
end

-- Yields. Confirms an asset is an audio file, loadable by this experience, and returns its real length.
ControllerFunctions.inspectAudioAsset = function(assetId: number): (boolean, string, string, number, boolean)
	-- Cache metadata only. Every request still creates and preloads an AudioProbe
	-- below, so a metadata cache hit never bypasses experience permission/playability checks.
	local infoOk, infoOrError = musicValidation:GetAudioAssetInfo(assetId)
	if not infoOk then
		return false, tostring(infoOrError), "", 0, false
	end
	local info = infoOrError :: any
	if info.AssetTypeId ~= Enum.AssetType.Audio.Value then
		return false, "That asset is not an audio file.", "", 0, false
	end

	local audioProbe = Instance.new("AudioPlayer")
	audioProbe.Name = "AudioProbe"
	audioProbe.AutoLoad = true
	audioProbe.Asset = "rbxassetid://" .. tostring(assetId)
	audioProbe.Parent = SoundService
	local loadedOk = false
	local finished = false
	local timedOut = false
	task.spawn(function()
		loadedOk = pcall(function() ContentProvider:PreloadAsync({ audioProbe }) end)
		finished = true
		if timedOut then
			-- A timed-out PreloadAsync cannot be cancelled. Keep the global slot
			-- occupied until the underlying work really ends, then clean it up.
			pcall(function() audioProbe:Destroy() end)
			audioInspectionCount = math.max(0, audioInspectionCount - 1)
		end
	end)
	local waited = 0
	while not finished and waited < CONFIG.AudioLoadTimeoutSeconds do
		task.wait(0.2)
		waited += 0.2
	end
	if not finished then
		timedOut = true
		return false, "Audio inspection timed out. The server will release its inspection slot when loading finishes.", "", 0, true
	end

	local isReady = audioProbe.IsReady
	local length = audioProbe.TimeLength
	pcall(function() audioProbe:Destroy() end)
	if not loadedOk or not isReady or length <= 0 then
		return false, "Audio could not be loaded (it may be private or not allowed in this experience).", "", 0, false
	end
	local normalized = musicValidation:NormalizeAudioMetadata(assetId, info, math.ceil(length))
	if typeof(normalized) ~= "table" then
		return false, "Audio metadata could not be normalized.", "", 0, false
	end
	return true, normalized.title, normalized.artist, normalized.duration, false
end

-- Saves a validated title slot. Returns true on success. Yields (text filtering).
ControllerFunctions.saveTitleSlot = function(player: Player, slotNumber: number, data: any, visible: boolean): boolean
	local profile = profiles[player.UserId]
	if not profile then return false end
	if not ControllerFunctions.isSultan(player) then
		notify(player, "Custom titles are exclusive to Tiki Tide Sultan members.", "warn")
		return false
	end
	if slotNumber < 1 or slotNumber > TITLE_SLOT_COUNT then return false end
	if slotNumber > profile.unlockedSlots then
		notify(player, "That title slot is locked.", "warn")
		return false
	end

	local clean = ControllerFunctions.sanitizeTitleSlot(data)
	if not clean then
		notify(player, "That title isn't valid. Titles are 1-24 characters.", "warn")
		return false
	end
	local filtered = ControllerFunctions.filterTitleText(player, clean.text)
	if filtered == nil then
		notify(player, "Roblox text filtering is unavailable. Please try again.", "warn")
		return false
	end
	if filtered == "" then
		notify(player, "That title can't be used.", "warn")
		return false
	end
	clean.text = filtered

	-- The profile may have been unloaded while the filter request yielded.
	if profiles[player.UserId] ~= profile then return false end
	profile.titleSlots[slotNumber] = clean
	profile.showCustomTitle = visible
	if profile.titleSlots[profile.activeSlot] == nil or profile.activeSlot > profile.unlockedSlots then
		profile.activeSlot = slotNumber
	end
	ControllerFunctions.applyTitleAttributes(player, profile)
	ControllerFunctions.scheduleProfileSave(player)
	return true
end

-- Actions -----------------------------------------------------------------------------

ControllerFunctions.handleAction = function(player: Player, action: any, payload: any, trustedAdminCommand: boolean?): (boolean?, string?)
	if player.Parent ~= Players then return false, "The caller is no longer in this server." end
	-- Validate the small, fixed remote contract before spending shared-service
	-- budget or forwarding attacker-controlled action values across the server bridge.
	if not ControllerFunctions.isValidString(action, 32) or not ControllerFunctions.isBoundedPayload(payload) then return false, "Invalid action or payload." end
	if ACTION_COOLDOWNS[action] == nil then return false, "That action is not supported." end

	-- Global + per-action throttles apply only to recognized, bounded actions.
	local now = os.clock()
	local userId = player.UserId
	if not ControllerFunctions.consumeActionBudget(userId, now) then return false, "ClubMusic action rate limit reached. Try again shortly." end
	local globalBudgetOk, globalAllowed = ControllerFunctions.globalInvoke("ConsumeActionBudget", userId, action, 1)
	if RunService:IsStudio() then
		if globalBudgetOk and globalAllowed == false then return false, "ClubMusic shared action budget is exhausted." end
	else
		-- Live servers require the global security service; never bypass aggregate
		-- budgets because the bridge or shared MemoryStore is unavailable.
		if not globalBudgetOk or globalAllowed ~= true then return false, "ClubMusic security budget is unavailable. Try again shortly." end
	end
	-- Check every cooldown before recording timestamps. A rejected action must not
	-- consume the cross-action interval and block an unrelated command immediately after it.
	-- Keep trusted admin commands in a separate per-action cooldown lane.
	-- The shared action budgets above still protect the server, while this avoids
	-- a normal DJ-booth/UI action accidentally blocking the equivalent admin command.
	local actionTimesByPlayer = if trustedAdminCommand == true then lastAdminActionByType else lastActionByType
	local actionTimes = actionTimesByPlayer[userId]
	if not actionTimes then actionTimes = {}; actionTimesByPlayer[userId] = actionTimes end
	-- Trusted admin commands use only the dedicated cross-command throttle below.
	-- Do not apply a second per-action cooldown: the shared token/global budgets
	-- and cross-command interval already protect this bridge, and a redundant
	-- per-action gate can reject valid Kohl's Admin invocations.
	local previousAction = actionTimes[action] or 0
	if trustedAdminCommand ~= true then
		local actionCooldown = ACTION_COOLDOWNS[action] or 0.2
		if previousAction > 0 and now - previousAction < actionCooldown then
			return false, "That ClubMusic action is cooling down."
		end
	end

	if trustedAdminCommand == true then
		-- Protect state-changing admin commands from duplicate command-framework
		-- dispatch. Toggle duplicates reverse state; restart duplicates replay the
		-- same track and can emit repeated success notices.
		if action == "DJPause" or action == "DJToggleLock" or action == "DJRestart" then
			local duplicateCooldown = if action == "DJPause" then 0.75
				elseif action == "DJToggleLock" then 1.25
				else (ACTION_COOLDOWNS.DJRestart or 1)
			local previousActionAt = actionTimes[action] or 0
			if previousActionAt > 0 and now - previousActionAt < duplicateCooldown then
				local message = if action == "DJRestart"
					then "ClubMusic restart was just triggered. Wait a moment before restarting again."
					else "That ClubMusic toggle was just used. Wait a moment before toggling it again."
				return false, message
			end
		end
		lastAdminActionAt[userId] = now
	else
		local previousGlobal = lastActionAt[userId] or 0
		if previousGlobal > 0 and now - previousGlobal < 0.12 then
			return false, "Please wait before using another ClubMusic action."
		end
		lastActionAt[userId] = now
	end
	actionTimes[action] = now

	if string.sub(tostring(action), 1, 8) == "Playlist" then
		if not ControllerFunctions.isStaff(player) then notify(player, "Only staff can manage playlists.", "warn"); return end
		if not playlistStorageReady or not MusicPlaylistService:IsReady() then
			notify(player, "Playlist storage is unavailable. No changes were made.", "warn"); return
		end
		if not ControllerFunctions.waitForDataStoreBudget(5) then
			notify(player, "Shared DataStore budget is unavailable; playlist was not changed.", "warn"); return
		end
		local wasActivePlaylist = activePlaylistId == payload.playlistId
		local ok, message = false, "Invalid playlist action."
		if action == "PlaylistCreate" then
			ok, message = MusicPlaylistService:Create(payload.name)
		elseif action == "PlaylistDelete" then
			ok, message = MusicPlaylistService:Delete(payload.playlistId)
			if ok and wasActivePlaylist then
				activePlaylistId = nil
				activePlaylistName = ""
				table.clear(activePlaylistTracks)
				activePlaylistCursor = 1
			end
		elseif action == "PlaylistAddTrack" then
			local trackId = payload.trackId
			if not ControllerFunctions.isValidString(trackId, 24) or not TRACK_BY_ID[trackId] then
				notify(player, "Choose a track from the current server catalog.", "warn"); return
			end
			ok, message = MusicPlaylistService:AddTrack(payload.playlistId, trackId)
		elseif action == "PlaylistRemoveTrack" then
			ok, message = MusicPlaylistService:RemoveTrack(payload.playlistId, payload.trackId)
		elseif action == "PlaylistMoveTrack" then
			ok, message = MusicPlaylistService:MoveTrack(payload.playlistId, payload.trackId, payload.position)
		end
		if ok and wasActivePlaylist then
			if action == "PlaylistAddTrack" or action == "PlaylistRemoveTrack" or action == "PlaylistMoveTrack" then
				ControllerFunctions.reloadActivePlaylist()
			end
			if globalQueueMode then
				local rotationSynced, syncMessage = ControllerFunctions.syncGlobalPlaylistRotation()
				if rotationSynced then
					ControllerFunctions.topUpAuto()
				else
					message = tostring(message) .. " Shared rotation update failed: " .. tostring(syncMessage)
				end
			else
				ControllerFunctions.clearAutomaticQueue()
				ControllerFunctions.topUpAuto()
			end
		end
		notify(player, message, if ok then "ok" else "warn")
		if ok then publishState(nil) end
		return
	end

	if action == "CatalogAddAudio" then
		if not ControllerFunctions.isStaff(player) then notify(player, "Only staff can add catalog tracks.", "warn"); return end
		if not catalogStorageReady or not MusicCatalogService:IsStorageReady() then
			notify(player, "Persistent catalog storage is unavailable. No changes were made.", "warn"); return
		end
		local assetId = payload.assetId
		local genreId = payload.genreId
		local artworkAssetId = payload.artworkAssetId
		if typeof(assetId) ~= "number" or assetId % 1 ~= 0 or assetId <= 0 or assetId > 9007199254740991 then
			notify(player, "Enter a valid audio asset ID.", "warn"); return
		end
		if typeof(genreId) ~= "string" or #genreId > 24 then
			notify(player, "Choose a valid catalog genre.", "warn"); return
		end
		if artworkAssetId ~= nil and (typeof(artworkAssetId) ~= "number" or artworkAssetId ~= artworkAssetId or artworkAssetId % 1 ~= 0 or artworkAssetId <= 0 or artworkAssetId > 9007199254740991) then
			notify(player, "Artwork must be a valid Roblox image asset ID.", "warn"); return
		end
		if artworkAssetId ~= nil then
			local artworkInfoOk, artworkInfo = pcall(function()
				return MarketplaceService:GetProductInfo(artworkAssetId, Enum.InfoType.Asset)
			end)
			local imageType = Enum.AssetType.Image.Value
			local decalType = Enum.AssetType.Decal.Value
			if not artworkInfoOk or typeof(artworkInfo) ~= "table"
				or (artworkInfo.AssetTypeId ~= imageType and artworkInfo.AssetTypeId ~= decalType) then
				notify(player, "That artwork ID is not an accessible Roblox image or decal asset.", "warn"); return
			end
		end
		if CONFIG.RestrictAudioToAllowlist and not table.find(CONFIG.AllowedAudioAssetIds, assetId) then
			notify(player, "That audio asset is not on the approved list.", "warn"); return
		end
		if pendingAudio[userId] then notify(player, "An audio inspection is already running.", "warn"); return end
		local audioNow = os.clock()
		local previousAudio = lastAudioInspection[userId] or 0
		if previousAudio > 0 and audioNow - previousAudio < CONFIG.AudioInspectionCooldownSeconds then
			notify(player, "Please wait before inspecting another audio asset.", "warn"); return
		end
		if audioInspectionCount >= math.max(1, CONFIG.MaxConcurrentAudioInspections)
			or not ControllerFunctions.consumeToken(globalAudioBucket, audioNow, 1) then
			notify(player, "Audio inspection is busy. Try again shortly.", "warn"); return
		end
		pendingAudio[userId] = true
		lastAudioInspection[userId] = audioNow
		audioInspectionCount += 1
		local inspectOk, valid, title, artist, duration, inspectionOwnsSlot = pcall(ControllerFunctions.inspectAudioAsset, assetId)
		if inspectionOwnsSlot ~= true then audioInspectionCount = math.max(0, audioInspectionCount - 1) end
		pendingAudio[userId] = nil
		if not inspectOk or not valid then
			notify(player, if inspectOk then tostring(title) else "Audio inspection failed.", "warn"); return
		end
		if duration > CONFIG.AudioMaxSeconds then
			notify(player, string.format("Audio exceeds the %d-minute catalog limit.", math.floor(CONFIG.AudioMaxSeconds / 60)), "warn"); return
		end
		if player.Parent ~= Players or not ControllerFunctions.isStaff(player) then return end
		local budgetReady = ControllerFunctions.waitForDataStoreBudget(5)
		if not budgetReady then notify(player, "Shared DataStore budget is unavailable; catalog was not changed.", "warn"); return end
		local trackId = "custom-" .. tostring(assetId)
		local additionReserved = false
		if globalQueueMode then
			-- Serialize additions as well as removals. This prevents a restore/add
			-- from racing a removal reservation for the same catalog ID.
			local reserveCallOk, reserved, reserveState, reserveMessage = ControllerFunctions.globalInvoke(
				"ReserveCatalogAddition", trackId, localCatalogRevision
			)
			if typeof(reserveState) == "table" then ControllerFunctions.applyGlobalQueueState(reserveState) end
			if reserveCallOk and reserved ~= true
				and tostring(reserveMessage) == "Catalog changed on another server; refresh and retry." then
				if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
				ControllerFunctions.refreshCatalogWhenReady()
				reserveCallOk, reserved, reserveState, reserveMessage = ControllerFunctions.globalInvoke(
					"ReserveCatalogAddition", trackId, localCatalogRevision
				)
				if typeof(reserveState) == "table" then ControllerFunctions.applyGlobalQueueState(reserveState) end
			end
			local alreadyReserved = reserveCallOk and reserved ~= true
				and tostring(reserveMessage) == "Catalog addition is already reserved for this track."
			if not reserveCallOk or (reserved ~= true and not alreadyReserved) then
				notify(player, tostring(reserveMessage or "The shared catalog could not reserve this addition."), "warn")
				return
			end
			additionReserved = true
			if not ControllerFunctions.refreshCatalogWhenReady() then
				notify(player, "Catalog addition is reserved globally, but the catalog could not be refreshed. Retry the audio addition after storage recovers.", "warn")
				return
			end
			local existingTrack = TRACK_BY_ID[trackId]
			if existingTrack then
				if alreadyReserved then
					local completeCallOk, completed, completeState, completeMessage = ControllerFunctions.globalInvoke("CompleteCatalogAddition", trackId)
					if typeof(completeState) == "table" then ControllerFunctions.applyGlobalQueueState(completeState) end
					if completeCallOk and completed == true then
						notify(player, "The previously saved catalog addition was recovered and synchronized.", "ok")
					else
						notify(player, "The track is saved, but its shared addition reservation remains pending. Retry the addition to finish recovery.", "warn")
					end
				else
					local completeCallOk, completed, completeState = ControllerFunctions.globalInvoke("CompleteCatalogAddition", trackId)
					if typeof(completeState) == "table" then ControllerFunctions.applyGlobalQueueState(completeState) end
					if not completeCallOk or completed ~= true then
						notify(player, "That track is already in the catalog; reservation cleanup is pending.", "warn")
					else
						notify(player, "That audio is already in the catalog.", "warn")
					end
				end
				return
			end
		end

		local saved, message = MusicCatalogService:AddCustomTrack(assetId, title, artist, duration, genreId, artworkAssetId)
		if not saved and globalQueueMode and tostring(message) == "That audio was added by another server already. Refresh the catalog." then
			if ControllerFunctions.refreshCatalogWhenReady() and TRACK_BY_ID[trackId] then
				saved = true
				message = "Track was added by another server; shared catalog state recovered."
			end
		end
		if not saved then
			if globalQueueMode and additionReserved then
				local uncertain = tostring(message) == "Catalog save failed. Try again later."
					or tostring(message) == "The catalog update could not be confirmed; refresh and retry."
				if not uncertain then
					local releaseCallOk, released, releaseState = ControllerFunctions.globalInvoke("CompleteCatalogAddition", trackId)
					if typeof(releaseState) == "table" then ControllerFunctions.applyGlobalQueueState(releaseState) end
					if not releaseCallOk or released ~= true then
						warn("[ClubMusic] Could not release rejected catalog addition reservation.")
					end
				else
					notify(player, tostring(message) .. " The shared addition reservation remains active so stale servers cannot queue this ID. Retry the audio addition to recover.", "warn")
					return
				end
			end
			notify(player, message, "warn")
			return
		end

		local track = MusicCatalogService:GetTrackById(trackId)
		if track then
			TRACK_BY_ID[trackId] = track
			if not table.find(ALL_TRACK_IDS, trackId) then table.insert(ALL_TRACK_IDS, trackId) end
			table.sort(ALL_TRACK_IDS)
		end
		if globalQueueMode and additionReserved then
			local completeCallOk, completed, completeState, completeMessage = ControllerFunctions.globalInvoke("CompleteCatalogAddition", trackId)
			if typeof(completeState) == "table" then ControllerFunctions.applyGlobalQueueState(completeState) end
			if not completeCallOk or completed ~= true then
				warn("[ClubMusic] Catalog addition saved but shared reservation finalization is pending: " .. tostring(completeMessage))
				notify(player, "Track saved. Shared addition finalization is pending; retry the audio addition to finish safely.", "warn")
				publishState(nil)
				return
			end
		end
		local publishOk, published = ControllerFunctions.globalInvoke("PublishCatalogChange")
		if not publishOk or published ~= true then
			warn("[ClubMusic] Catalog add saved locally; cross-server invalidation publish failed.")
		end
		notify(player, message, "ok")
		publishState(nil)
		return
	end

	if action == "CatalogRemoveTrack" then
		if not ControllerFunctions.isStaff(player) then notify(player, "Only staff can remove catalog tracks.", "warn"); return end
		local trackId = payload.trackId
		if not ControllerFunctions.isValidString(trackId, 32) or not string.match(trackId, "^custom%-%d+$") then
			notify(player, "Only a valid staff-added catalog track ID can be removed.", "warn"); return
		end
		local initialTrack = TRACK_BY_ID[trackId]
		if initialTrack and initialTrack.assetId == nil then
			notify(player, "Only staff-added catalog tracks can be removed here.", "warn"); return
		end
		if not catalogStorageReady or not ControllerFunctions.waitForDataStoreBudget(5) then
			notify(player, "Catalog storage is unavailable; track was not removed.", "warn"); return
		end

		local track = TRACK_BY_ID[trackId]
		if globalQueueMode and not track then
			-- A missing local record is valid only for an interrupted removal.
			-- Refresh once so stale caches are not mistaken for completed deletion.
			if syncGlobalQueueSnapshot and not syncGlobalQueueSnapshot() then
				notify(player, "The shared catalog state could not be verified; track was not removed.", "warn"); return
			end
			if ControllerFunctions.refreshCatalogWhenReady() then track = TRACK_BY_ID[trackId] end
			if not track and not (globalCatalogChangeTrackId == trackId and globalCatalogChangeKind == "remove") then
				notify(player, "Custom catalog track not found.", "warn"); return
			end
		end
		if not globalQueueMode then
			if not track or track.assetId == nil then
				notify(player, "Only staff-added catalog tracks can be removed here.", "warn"); return
			end
			if nowPlaying.trackId == trackId then
				notify(player, "That track is currently playing. Remove it after playback ends.", "warn"); return
			end
			for _, queued in ipairs(queue) do
				if queued.trackId == trackId then
					notify(player, "That track is queued. Remove it from the queue first.", "warn"); return
				end
			end
		else
			-- Reserve the ID atomically in the same DataStore used by every global
			-- enqueue/advance. This closes the read-queue-then-delete race.
			local reserveCallOk, reserved, reserveState, reserveMessage = ControllerFunctions.globalInvoke(
				"ReserveCatalogRemoval", trackId, localCatalogRevision
			)
			if typeof(reserveState) == "table" then ControllerFunctions.applyGlobalQueueState(reserveState) end
			if reserveCallOk and reserved ~= true
				and tostring(reserveMessage) == "Catalog changed on another server; refresh and retry." then
				if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
				ControllerFunctions.refreshCatalogWhenReady()
				reserveCallOk, reserved, reserveState, reserveMessage = ControllerFunctions.globalInvoke(
					"ReserveCatalogRemoval", trackId, localCatalogRevision
				)
				if typeof(reserveState) == "table" then ControllerFunctions.applyGlobalQueueState(reserveState) end
			end
			local alreadyReserved = reserveCallOk and reserved ~= true
				and tostring(reserveMessage) == "Catalog removal is already reserved for this track."
			if not reserveCallOk or (reserved ~= true and not alreadyReserved) then
				notify(player, tostring(reserveMessage or "The shared catalog could not reserve this removal."), "warn")
				return
			end
			-- Refresh after the reservation's revision bump. If this server stopped
			-- after deleting the catalog record but before finalizing, a retry sees
			-- the missing record and safely completes the existing reservation.
			if not ControllerFunctions.refreshCatalogWhenReady() then
				notify(player, "Removal is reserved globally, but the catalog could not be refreshed. Retry the catalog removal from the staff catalog UI for this same track after storage recovers.", "warn")
				return
			end
			track = TRACK_BY_ID[trackId]
			if track and track.assetId == nil then
				local releaseCallOk, released, releaseState = ControllerFunctions.globalInvoke("CompleteCatalogRemoval", trackId)
				if typeof(releaseState) == "table" then ControllerFunctions.applyGlobalQueueState(releaseState) end
				if not releaseCallOk or released ~= true then
					warn("[ClubMusic] Could not release an invalid catalog removal reservation.")
				end
				notify(player, "Only staff-added catalog tracks can be removed here.", "warn"); return
			end
		end

		local removed = false
		local message = "Track removed from the shared catalog."
		if track then
			removed, message = MusicCatalogService:RemoveCustomTrack(trackId)
			if not removed and globalQueueMode then
				-- UpdateAsync can report an error after its write outcome becomes
				-- uncertain. Re-read before deciding whether to keep the reservation.
				if MusicCatalogService:Refresh() then
					if MusicCatalogService:GetTrackById(trackId) == nil then
						removed = true
						message = "Catalog removal was already committed; shared reservation recovered."
					end
				end
			end
		else
			-- A missing local record is acceptable only when this is a reserved
			-- global retry and the authoritative catalog refresh confirmed absence.
			removed = globalQueueMode == true
		end
		if not removed then
			if globalQueueMode then
				notify(player, tostring(message) .. " The shared removal reservation remains active to prevent stale servers from queueing this track. Retry the catalog removal from the staff catalog UI for this same track after storage recovers.", "warn")
			else
				notify(player, message, "warn")
			end
			return
		end

		TRACK_BY_ID[trackId] = nil
		for index, id in ipairs(ALL_TRACK_IDS) do
			if id == trackId then table.remove(ALL_TRACK_IDS, index); break end
		end
		local rotationReady = true
		if activePlaylistId or (globalQueueMode and globalPlaylistRotationEnabled) then
			for index = #activePlaylistTracks, 1, -1 do
				if activePlaylistTracks[index].id == trackId then table.remove(activePlaylistTracks, index) end
			end
			activePlaylistCursor = math.clamp(activePlaylistCursor, 1, math.max(1, #activePlaylistTracks))
			if globalQueueMode then
				local rotationSynced, syncMessage = ControllerFunctions.syncGlobalPlaylistRotation()
				if not rotationSynced then
					rotationReady = false
					warn("[ClubMusic] Removed catalog track locally, but shared playlist rotation sync failed: " .. tostring(syncMessage))
				end
			else
				ControllerFunctions.clearAutomaticQueue()
				ControllerFunctions.topUpAuto()
			end
		end

		if globalQueueMode then
			if not rotationReady then
				notify(player, "Catalog record is removed, but the shared playlist rotation is not synchronized. The safety reservation remains active; retry the catalog removal from the staff catalog UI for this same track after storage recovers.", "warn")
				publishState(nil)
				return
			end
			local completeCallOk, completed, completeState, completeMessage = ControllerFunctions.globalInvoke("CompleteCatalogRemoval", trackId)
			if typeof(completeState) == "table" then ControllerFunctions.applyGlobalQueueState(completeState) end
			if not completeCallOk or completed ~= true then
				warn("[ClubMusic] Catalog record removed but shared reservation finalization is pending: " .. tostring(completeMessage))
				notify(player, "Catalog record removed. Shared reservation finalization is pending; retry the catalog removal from the staff catalog UI for this same track to finish safely.", "warn")
				publishState(nil)
				return
			end
		end

		local publishOk, published = ControllerFunctions.globalInvoke("PublishCatalogChange")
		if not publishOk or published ~= true then
			warn("[ClubMusic] Catalog removal saved locally; cross-server invalidation publish failed.")
		end
		notify(player, message, "ok")
		publishState(nil)
		return
	end

	if action == "RequestTrack" then
		local trackId = payload.trackId
		if not ControllerFunctions.isValidString(trackId, 24) then return end
		local track = TRACK_BY_ID[trackId]
		if not track then return end

		local level = ControllerFunctions.getLevel(player)
		if blockedUsers[player.UserId] then
			notify(player, "Your requests are disabled by staff.", "warn")
			return
		end
		if requestsLocked and level < 1 then
			notify(player, "Requests are locked by staff right now.", "warn")
			return
		end
		if ControllerFunctions.countPlayerEntries() >= CONFIG.MaxQueueSize then
			notify(player, "The request queue is full.", "warn")
			return
		end

		local cooldown = ControllerFunctions.cooldownFor(player)
		local sinceLast = now - (lastRequestAt[player.UserId] or -1000)
		if sinceLast < cooldown then
			notify(player, string.format("Slow down - wait %ds to request again.", math.ceil(cooldown - sinceLast)), "warn")
			return
		end

		local count = requestCounts[player.UserId] or 0
		local limit = ControllerFunctions.requestLimitFor(player)
		if count >= limit then
			notify(player, string.format("Request limit reached (%d/%d). Wait for your track to play.", count, limit), "warn")
			return
		end

		if nowPlaying.trackId == track.id then
			notify(player, "That track is playing right now.", "warn")
			return
		end
		for _, queued in ipairs(queue) do
			if queued.trackId == track.id then
				notify(player, "That track is already in the queue.", "warn")
				return
			end
		end

		local vip = ControllerFunctions.isVip(player)
		local entry = ControllerFunctions.makeEntry(track, "player", player)
		if globalQueueMode then
			local queued: boolean = false
			local queueError: string? = "Global queue is not ready."
			if enqueueGlobalQueueEntry then queued, queueError = enqueueGlobalQueueEntry(entry) end
			if not queued then notify(player, tostring(queueError or "Global queue is unavailable."), "warn"); return end
		else
			queueManager:Insert(ControllerFunctions.insertIndex(ControllerFunctions.passTier(player)), entry)
			requestCounts[player.UserId] = count + 1
		end
		lastRequestAt[player.UserId] = now
		notify(player, if vip and CONFIG.VipPriority then "Requested with VIP priority!" else "Track requested!", "ok")
		publishState(nil)
		return
	end

	-- Staff only: queue a Creator Hub / Roblox audio asset by ID.
	if action == "RequestAudioAsset" then
		if not ControllerFunctions.isStaff(player) then
			notify(player, "Audio asset IDs are staff only.", "warn")
			return
		end
		local audioBudgetCallOk, audioBudgetAllowed = ControllerFunctions.globalInvoke("ConsumeAudioBudget", userId)
		if RunService:IsStudio() then
			if audioBudgetCallOk and audioBudgetAllowed == false then
				notify(player, "Global audio inspection capacity is busy. Please try again shortly.", "warn")
				return
			end
		else
			-- Live servers must not silently fall back to independent per-server
			-- audio limits when the shared cross-server budget is unavailable.
			if not audioBudgetCallOk or audioBudgetAllowed ~= true then
				notify(player, "Shared audio inspection capacity is unavailable. Try again shortly.", "warn")
				return
			end
		end
		local assetId = payload.assetId
		if typeof(assetId) ~= "number" or assetId % 1 ~= 0 or assetId <= 0 or assetId > 9007199254740991 then
			notify(player, "That audio asset ID isn't valid.", "warn")
			return
		end
		if CONFIG.RestrictAudioToAllowlist and not table.find(CONFIG.AllowedAudioAssetIds, assetId) then
			notify(player, "That audio asset isn't on the approved list.", "warn")
			return
		end
		if pendingAudio[player.UserId] then
			notify(player, "Still checking your last audio request.", "warn")
			return
		end
		local audioNow = os.clock()
		local previousAudio = lastAudioInspection[player.UserId] or 0
		if previousAudio > 0 and audioNow - previousAudio < CONFIG.AudioInspectionCooldownSeconds then
			notify(player, "Please wait before checking another audio asset.", "warn")
			return
		end
		if audioInspectionCount >= math.max(1, CONFIG.MaxConcurrentAudioInspections) then
			notify(player, "Audio inspection is busy. Try again shortly.", "warn")
			return
		end
		if not ControllerFunctions.consumeToken(globalAudioBucket, audioNow, 1) then
			notify(player, "The server is checking too many audio requests. Try again shortly.", "warn")
			return
		end

		local trackId = "audio-" .. tostring(assetId)
		local reason = ControllerFunctions.requestBlockReason(player, trackId, now)
		if reason then
			notify(player, reason, "warn")
			return
		end

		pendingAudio[player.UserId] = true
		lastAudioInspection[player.UserId] = audioNow
		audioInspectionCount += 1
		local okInspect, valid, titleOrError, creator, duration, inspectionOwnsSlot = pcall(ControllerFunctions.inspectAudioAsset, assetId)
		if inspectionOwnsSlot ~= true then
			audioInspectionCount = math.max(0, audioInspectionCount - 1)
		end
		pendingAudio[player.UserId] = nil
		if not okInspect then
			warn("[ClubMusic] Audio inspect error: " .. tostring(valid))
			notify(player, "Could not check that audio asset.", "warn")
			return
		end
		if not valid then
			notify(player, titleOrError, "warn")
			return
		end
		if duration > CONFIG.AudioMaxSeconds then
			notify(player, string.format("That audio is too long (max %d minutes).", math.floor(CONFIG.AudioMaxSeconds / 60)), "warn")
			return
		end
		if not player.Parent then return end

		-- State may have changed while the asset loaded, so re-check before queueing.
		local recheckNow = os.clock()
		local recheck = ControllerFunctions.requestBlockReason(player, trackId, recheckNow)
		if recheck then
			notify(player, recheck, "warn")
			return
		end

		local vip = ControllerFunctions.isVip(player)
		local entry = ControllerFunctions.makeEntry({
			id = trackId,
			genreId = "audio",
			title = titleOrError,
			artist = creator,
			duration = duration,
			genre = "Creator Hub Audio",
		}, "player", player)
		entry.soundId = "rbxassetid://" .. tostring(assetId)
		if globalQueueMode then
			local queued: boolean = false
			local queueError: string? = "Global queue is not ready."
			if enqueueGlobalQueueEntry then queued, queueError = enqueueGlobalQueueEntry(entry) end
			if not queued then notify(player, tostring(queueError or "Global queue is unavailable."), "warn"); return end
		else
			queueManager:Insert(ControllerFunctions.insertIndex(ControllerFunctions.passTier(player)), entry)
			requestCounts[player.UserId] = (requestCounts[player.UserId] or 0) + 1
		end
		lastRequestAt[player.UserId] = recheckNow
		notify(player, "Audio queued: " .. titleOrError, "ok")
		publishState(nil)
		return
	end

	if action == "ReloadSong" then
		local last = lastReloadAt[player.UserId] or -1000
		if now - last < CONFIG.ReloadCooldownSeconds then return end
		lastReloadAt[player.UserId] = now
		-- Bumping the nonce makes this player's next snapshot differ, so their client re-processes
		-- the current track (e.g. an audio script can restart playback at the right position).
		reloadNonce[player.UserId] = (reloadNonce[player.UserId] or 0) + 1
		publishState(player)
		return
	end

	if action == "ToggleFavorite" then
		local trackId = payload.trackId
		if not ControllerFunctions.isValidString(trackId, 24) or not TRACK_BY_ID[trackId] then return end
		local profile = profiles[player.UserId]
		if not profile then return end
		if profile.favorites[trackId] then
			profile.favorites[trackId] = nil
		else
			local count = 0
			for _ in pairs(profile.favorites) do count += 1 end
			if count >= CONFIG.MaxFavorites then
				notify(player, "Favorites list is full.", "warn")
				return
			end
			profile.favorites[trackId] = true
		end
		ControllerFunctions.scheduleProfileSave(player)
		publishState(player)
		return
	end

	if action == "VoteSkip" then
		local manager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.SkipVote
		if not manager then
			notify(player, "Skip voting is temporarily unavailable.", "warn")
			return
		end
		local accepted, message = manager:CastVote(player)
		if accepted ~= true then notify(player, tostring(message or "Skip vote was rejected."), "warn") end
		return
	end

	-- Staff ----------------------------------------------------------------------------

	if action == "DJPlayPlaylist" then
		if not ControllerFunctions.isStaff(player) then notify(player, "Only staff can start playlist rotation.", "warn"); return end
		if not playlistStorageReady or not MusicPlaylistService:IsReady() then
			notify(player, "Playlist storage is unavailable.", "warn"); return
		end
		local manager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.Playlist
		if manager and manager:StartRotation(player, payload.playlistId) then publishState(nil) end
		return
	end

	if action == "DJStopPlaylist" then
		if not ControllerFunctions.isStaff(player) then notify(player, "Only staff can stop playlist rotation.", "warn"); return end
		local manager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.Playlist
		if manager and manager:StopRotation(player) then publishState(nil) end
		return
	end

	if action == "DJMoveUp" then
		if not ControllerFunctions.isStaff(player) then return end
		local id = payload.queueId
		if not ControllerFunctions.isValidString(id, 64) then return end
		if globalQueueMode then
			local callOk, moved, state = ControllerFunctions.globalInvoke("MoveUpGlobalQueueEntry", id)
			if callOk and moved == true and typeof(state) == "table" then ControllerFunctions.applyGlobalQueueState(state)
			elseif syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
		else
			local index = ControllerFunctions.findQueueIndex(id)
			if index and index > 1 then queue[index], queue[index - 1] = queue[index - 1], queue[index] end
		end
		publishState(nil)
		return
	end

	if action == "DJRemove" then
		if not ControllerFunctions.isStaff(player) then return false, "ClubMusic staff permission is required." end
		local id = payload.queueId
		if not ControllerFunctions.isValidString(id, 64) then return false, "A valid queue entry ID is required." end
		if globalQueueMode then
			local callOk, removed, state, message = ControllerFunctions.globalInvoke("RemoveGlobalQueueEntry", id)
			if callOk and removed == true then
				if typeof(state) == "table" and not ControllerFunctions.applyGlobalQueueState(state) and syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
				if typeof(state) ~= "table" and syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
				ControllerFunctions.topUpAuto()
				publishState(nil)
				return true, "Queued track removed."
			end
			if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
			return false, tostring(message or "Queue entry was not found or the shared queue is unavailable.")
		end
		local index = ControllerFunctions.findQueueIndex(id)
		if not index then return false, "Queue entry was not found. Run ;cmqueue to refresh the IDs." end
		local removedEntry = queueManager:RemoveAt(index, true)
		if not removedEntry then return false, "Queue entry could not be removed." end
		ControllerFunctions.topUpAuto()
		publishState(nil)
		return true, "Removed queued track: " .. tostring(removedEntry.title or "Unknown track") .. "."
	end

	if action == "DJSkip" then
		if not ControllerFunctions.isStaff(player) then return false, "ClubMusic staff permission is required." end
		-- Kohl's Admin can dispatch the same command while an automatic or
		-- admin-triggered transition is still yielding on shared queue work.
		-- The active transition already owns this track change; do not call
		-- advance() a second time or surface its internal lock as a warning.
		if trustedAdminCommand == true and transitionInProgress then
			return true, "A track transition is already being processed; no second skip was sent."
		end
		local advanced, transitionError = ControllerFunctions.advance()
		if not advanced then
			local reason = tostring(transitionError or "The shared track transition could not be confirmed.")
			notify(player, reason, "warn")
			return false, reason
		end
		if not globalQueueMode then ControllerFunctions.globalInvoke("PublishDJCommand", "Skip", {}, player.UserId) end
		notify(player, "Track skipped.", "ok")
		publishState(nil)
		return true, "Track skipped."
	end

	if action == "DJPause" then
		if not ControllerFunctions.isStaff(player) then return false, "ClubMusic staff permission is required." end
		if nowPlaying.trackId == "" then notify(player, "No track is currently selected.", "warn"); return false, "No track is currently selected." end
		local desiredPaused = not playbackPaused
		ControllerFunctions.cancelAudioTransition(if desiredPaused then "pause" else "resume")
		if globalQueueMode then
			local position = nowPlaying.elapsed
			pcall(function() local audio = ControllerFunctions.getAudioSnapshot(); if audio.ready then position = audio.position end end)
			local callOk, changed, state, message = ControllerFunctions.globalInvoke("SetGlobalPlayback", desiredPaused, position, globalTrackRevision, false)
			if not callOk or changed ~= true or typeof(state) ~= "table" then
				notify(player, tostring(message or "Global playback state could not be saved."), "warn")
				if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
				return false, tostring(message or "Global playback state could not be saved.")
			end
			ControllerFunctions.applyGlobalQueueState(state)
			notify(player, if desiredPaused then "Music paused globally." else "Music resumed globally.", "ok")
		else
			local position = nowPlaying.elapsed
			pcall(function() local audio = ControllerFunctions.getAudioSnapshot(); if audio.ready then position = audio.position end end)
			nowPlaying.elapsed = math.clamp(position, 0, nowPlaying.duration)
			playbackPaused = desiredPaused
			pcall(function()
				local audio = ControllerFunctions.getAudioSnapshot()
				if audio.ready then ControllerFunctions.seekAudio(nowPlaying.elapsed) end
				if playbackPaused then ControllerFunctions.pauseAudio() else ControllerFunctions.resumeAudio() end
			end)
			local globalOk, globalPublished, globalRevision = ControllerFunctions.globalInvoke("PublishDJCommand", "SetPlaybackPaused", {paused = playbackPaused, position = nowPlaying.elapsed}, player.UserId)
			if globalOk and globalPublished == true and ControllerFunctions.isFiniteNumber(globalRevision) then lastGlobalPlaybackRevision = math.max(lastGlobalPlaybackRevision, math.floor(globalRevision)) end
			if not globalOk or globalPublished ~= true then notify(player, "Playback changed on this server, but cross-server sync is unavailable.", "warn") end
			notify(player, if playbackPaused then "Music paused." else "Music resumed.", "ok")
		end
		publishState(nil)
		return true, if desiredPaused then "Music paused." else "Music resumed."
	end

	if action == "DJRestart" then
		if not ControllerFunctions.isStaff(player) then return false, "ClubMusic staff permission is required." end
		if nowPlaying.trackId == "" then notify(player, "No track is currently selected.", "warn"); return false, "No track is currently selected." end
		ControllerFunctions.cancelAudioTransition("restart")
		if globalQueueMode then
			local callOk, restarted, state, message = ControllerFunctions.globalInvoke("SetGlobalPlayback", false, 0, globalTrackRevision, true)
			if not callOk or restarted ~= true or typeof(state) ~= "table" then
				notify(player, tostring(message or "Global restart could not be confirmed."), "warn")
				if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
				return false, tostring(message or "Global restart could not be confirmed.")
			end
			ControllerFunctions.applyGlobalQueueState(state)
			notify(player, "Current track restarted across servers.", "ok")
		else
			nowPlaying.elapsed = 0; playbackPaused = false
			ControllerFunctions.startServerMusic(nowPlaying.soundId)
			local globalOk, globalPublished, globalRevision = ControllerFunctions.globalInvoke("PublishDJCommand", "Restart", {}, player.UserId)
			if globalOk and globalPublished == true and ControllerFunctions.isFiniteNumber(globalRevision) then lastGlobalPlaybackRevision = math.max(lastGlobalPlaybackRevision, math.floor(globalRevision)) end
			if not globalOk or globalPublished ~= true then notify(player, "Track restarted here, but cross-server sync is unavailable.", "warn")
			else notify(player, "Current track restarted across servers.", "ok") end
		end
		publishState(nil)
		return true, "Current track restarted."
	end

	if action == "DJClearQueue" then
		if not ControllerFunctions.isAdmin(player) then return false, "ClubMusic administrator permission is required." end
		ControllerFunctions.cancelAudioTransition("queue-clear")
		if globalQueueMode then
			local callOk, cleared, state, message = ControllerFunctions.globalInvoke("ClearGlobalQueue")
			if not callOk or cleared ~= true then
				local reason = tostring(message or "The shared queue service did not confirm the clear.")
				warn("[ClubMusic] Shared queue clear failed: " .. reason)
				notify(player, reason, "warn")
				return false, reason
			end
			if typeof(state) == "table" then ControllerFunctions.applyGlobalQueueState(state) end
		else
			queueManager:Clear(true)
			autoQueueHold = true
			ControllerFunctions.globalInvoke("PublishDJCommand", "ClearQueue", {}, player.UserId)
		end
		notify(player, "Queue cleared.", "ok")
		publishState(nil)
		return true, "Queue cleared."
	end

	if action == "DJToggleLock" then
		if not ControllerFunctions.isStaff(player) then return false, "ClubMusic staff permission is required." end
		local desiredLock = not requestsLocked
		local publishCallOk, persisted = ControllerFunctions.globalInvoke("PublishDJCommand", "SetRequestLock", {locked = desiredLock}, player.UserId)
		if not RunService:IsStudio() and (not publishCallOk or persisted ~= true) then
			-- Fail closed locally if the durable global lock cannot be confirmed.
			requestsLocked = true
			notify(player, "Global lock could not be confirmed. Requests remain locked on this server.", "warn")
			publishState(nil)
			return false, "Global lock could not be confirmed; requests remain locked here."
		end
		requestsLocked = desiredLock
		ControllerFunctions.broadcast(if requestsLocked then "Song requests are now LOCKED." else "Song requests are open again.", "info")
		publishState(nil)
		return true, if requestsLocked then "Song requests locked." else "Song requests opened."
	end

	if action == "ModBlockUser" then
		if not ControllerFunctions.isAdmin(player) then return end
		local target = ControllerFunctions.findTarget(player, payload.userId)
		if not target or typeof(payload.blocked) ~= "boolean" then return end

		if payload.blocked then
			-- Apply the local restriction before yielding to persistent storage.
			blockedUsers[target.UserId] = true
			ControllerFunctions.purgeUserEntries(target.UserId)
		end

		local globalWriteOk = true
		if not RunService:IsStudio() then
			local callOk, persisted = ControllerFunctions.globalInvoke("SetRequestBlocked", target.UserId, payload.blocked, player.UserId)
			globalWriteOk = callOk and persisted == true
		end

		if not globalWriteOk then
			-- Never claim a global moderation change succeeded if its durable
			-- record could not be confirmed. Failed unblocks remain blocked.
			if payload.blocked then
				blockedUsers[target.UserId] = true
				ControllerFunctions.purgeUserEntries(target.UserId)
				if target.Parent == Players then
					notify(target, "Staff disabled your song requests on this server.", "warn")
				end
				notify(player, "The request block is active on this server, but the global moderation save failed.", "warn")
			else
				blockedUsers[target.UserId] = true
				notify(player, "The global unblock could not be confirmed. The player remains blocked.", "warn")
			end
			publishState(nil)
			return
		end

		if not payload.blocked then
			blockedUsers[target.UserId] = nil
			if target.Parent == Players then
				notify(target, "Your song requests were re-enabled.", "ok")
			end
			notify(player, target.DisplayName .. " can request songs again.", "ok")
		else
			if target.Parent == Players then
				notify(target, "Staff disabled your song requests.", "warn")
			end
			notify(player, target.DisplayName .. " can no longer request songs.", "ok")
		end
		publishState(nil)
		return
	end

	if action == "ModSetVip" then
		if not ControllerFunctions.isAdmin(player) then return end
		local target = ControllerFunctions.findTarget(player, payload.userId)
		if not target or typeof(payload.vip) ~= "boolean" then return end
		tempVip[target.UserId] = if payload.vip then true else nil
		ControllerFunctions.applyVipAttribute(target)
		notify(target, if payload.vip then "You were given VIP by staff!" else "Your staff-granted VIP was removed.", "info")
		notify(player, (if payload.vip then "VIP granted to " else "VIP removed from ") .. target.DisplayName .. ".", "ok")
		publishState(nil)
		return
	end

	if action == "ModPurgeUser" then
		if not ControllerFunctions.isAdmin(player) then return end
		local target = ControllerFunctions.findTarget(player, payload.userId)
		if not target then return end
		local removed = ControllerFunctions.purgeUserEntries(target.UserId)
		notify(player, string.format("Removed %d request(s) from %s.", removed, target.DisplayName), "ok")
		publishState(nil)
		return
	end

	-- Rewards / cosmetics -------------------------------------------------------------

	if action == "ClaimDailyReward" then
		local day = payload.day
		if typeof(day) ~= "number" or day % 1 ~= 0 or day < 1 or day > DAILY_REWARD_COUNT then return end
		local profile = profiles[player.UserId]
		if not profile or profile.claimedToday or day ~= profile.loginStreak then return end

		-- Grants map directly to the reward labels in the supplied data file.
		if day == 1 then profile.coins += 50
		elseif day == 2 then profile.glowsticks += 2
		elseif day == 3 then profile.tickets += 100
		elseif day == 4 then profile.skipTokens += 1
		elseif day == 5 then profile.coins += 250
		elseif day == 6 then profile.neonTrail = true
		elseif day == 7 then profile.ownedTags.island = true
		end
		profile.claimedToday = true
		profile.lastClaimDay = math.floor(os.time() / 86400)
		player:SetAttribute("Tickets", profile.tickets)
		player:SetAttribute("Coins", profile.coins)
		player:SetAttribute("Glowsticks", profile.glowsticks)
		player:SetAttribute("SkipTokens", profile.skipTokens)
		player:SetAttribute("NeonTrailUnlocked", profile.neonTrail)
		player:SetAttribute("ClaimedToday", true)
		ControllerFunctions.scheduleProfileSave(player)
		publishState(player)
		return
	end

	if action == "BuyTitleTag" then
		local tagId = payload.tagId
		local prices = { bass = 150, sunset = 250, tiki = 400 }
		local price = if typeof(tagId) == "string" then prices[tagId] else nil
		local profile = profiles[player.UserId]
		if not profile or not price then return end
		if profile.ownedTags[tagId] == true then
			notify(player, "You already own this title tag.", "info")
			return
		end
		if profile.tickets < price then
			notify(player, string.format("You need %d Tickets to unlock this title tag.", price), "warn")
			return
		end
		profile.tickets -= price
		profile.ownedTags[tagId] = true
		player:SetAttribute("Tickets", profile.tickets)
		ControllerFunctions.scheduleProfileSave(player)
		notify(player, tagId == "bass" and "Bass Head unlocked!" or tagId == "sunset" and "Sunset Soul unlocked!" or "Tiki Legend unlocked!", "ok")
		publishState(player)
		return
	end

	if action == "EquipTitleTag" then
		local tagId = payload.tagId
		if not ControllerFunctions.isValidString(tagId, 24) or TAGS[tagId] ~= true then return end
		local profile = profiles[player.UserId]
		if not profile or profile.ownedTags[tagId] ~= true then return end
		profile.equippedTag = tagId
		player:SetAttribute("EquippedTag", tagId)
		ControllerFunctions.scheduleProfileSave(player)
		publishState(player)
		return
	end

	-- Legacy single custom title: stored in slot 1 as a fixed-color title.
	if action == "SaveCustomTitle" then
		local profile = profiles[player.UserId]
		if not profile then return end

		local rawText = payload.text
		local colorKey = payload.color
		local styleKey = payload.style
		local visible = payload.visible

		if typeof(rawText) ~= "string" then return end
		-- Match the extended title-slot path: trim first, then enforce the
		-- character limit against the exact text that will be filtered and saved.
		local trimmedText = string.match(rawText, "^%s*(.-)%s*$") or ""
		local rawLength = utf8.len(trimmedText)
		if not rawLength or rawLength < 1 or rawLength > MAX_CUSTOM_TITLE_LENGTH then
			notify(player, "Title must be 1-24 characters.", "warn")
			return
		end
		if typeof(colorKey) ~= "string" or TITLE_COLORS[colorKey] ~= true then return end
		if typeof(styleKey) ~= "string" or TITLE_STYLES[styleKey] ~= true then return end
		if typeof(visible) ~= "boolean" then return end

		local existing = profile.titleSlots[1]
		local ok = ControllerFunctions.saveTitleSlot(player, 1, {
			text = trimmedText,
			effect = "fixed",
			set = colorKey,
			font = if existing then existing.font else "gotham",
			style = styleKey,
			textSize = if existing then existing.textSize else 20,
			height = if existing then existing.height else 2.5,
			distance = if existing then existing.distance else 80,
		}, visible)
		if ok then
			notify(player, "Custom title saved.", "ok")
			publishState(player)
		end
		return
	end

	-- Extended title slots ------------------------------------------------------------

	if action == "SaveTitleSlot" then
		local slotNumber = payload.slot
		if typeof(slotNumber) ~= "number" or slotNumber % 1 ~= 0 or slotNumber < 1 or slotNumber > TITLE_SLOT_COUNT then return end
		if typeof(payload.text) ~= "string" then return end
		-- Colors sent by the client are ignored; the server derives them from the allowlisted set.
		local visible = if typeof(payload.visible) == "boolean" then payload.visible else true
		local ok = ControllerFunctions.saveTitleSlot(player, slotNumber, {
			text = string.match(payload.text, "^%s*(.-)%s*$") or "",
			effect = payload.effect,
			set = payload.set,
			font = payload.font,
			style = payload.style,
			textSize = payload.textSize,
			heightOffset = payload.heightOffset,
			viewDistance = payload.viewDistance,
		}, visible)
		if ok then
			notify(player, string.format("Title slot %d saved.", slotNumber), "ok")
			publishState(player)
		end
		return
	end

	if action == "SelectTitleSlot" then
		if not ControllerFunctions.isSultan(player) then notify(player, "Custom titles require Tiki Tide Sultan.", "warn"); return end
		local slotNumber = payload.slot
		if typeof(slotNumber) ~= "number" or slotNumber % 1 ~= 0 or slotNumber < 1 or slotNumber > TITLE_SLOT_COUNT then return end
		local profile = profiles[player.UserId]
		if not profile or slotNumber > profile.unlockedSlots then return end
		if profile.titleSlots[slotNumber] == nil then
			notify(player, "Save a title in that slot first.", "warn")
			return
		end
		profile.activeSlot = slotNumber
		ControllerFunctions.applyTitleAttributes(player, profile)
		ControllerFunctions.scheduleProfileSave(player)
		publishState(player)
		return
	end

	if action == "ClearTitleSlot" then
		if not ControllerFunctions.isSultan(player) then notify(player, "Custom titles require Tiki Tide Sultan.", "warn"); return end
		local slotNumber = payload.slot
		if typeof(slotNumber) ~= "number" or slotNumber % 1 ~= 0 or slotNumber < 1 or slotNumber > TITLE_SLOT_COUNT then return end
		local profile = profiles[player.UserId]
		if not profile or slotNumber > profile.unlockedSlots then return end
		profile.titleSlots[slotNumber] = nil
		if profile.activeSlot == slotNumber then
			profile.activeSlot = ControllerFunctions.firstFilledSlot(profile) or 1
		end
		ControllerFunctions.applyTitleAttributes(player, profile)
		ControllerFunctions.scheduleProfileSave(player)
		publishState(player)
		return
	end

	if action == "SetTitleVisible" then
		if not ControllerFunctions.isSultan(player) then notify(player, "Custom titles require Tiki Tide Sultan.", "warn"); return end
		if typeof(payload.visible) ~= "boolean" then return end
		local profile = profiles[player.UserId]
		if not profile then return end
		profile.showCustomTitle = payload.visible
		ControllerFunctions.applyTitleAttributes(player, profile)
		ControllerFunctions.scheduleProfileSave(player)
		publishState(player)
		return
	end
end

catalogFunction.OnServerInvoke = function(player: Player, query: any, genreId: any, offset: any, limit: any)
	if player.Parent ~= Players then return nil end
	local now = os.clock()
	if not ControllerFunctions.consumeToken(globalStateQueryBucket, now, 1) then return nil end
	local sharedStateCallOk, sharedStateAllowed = ControllerFunctions.globalInvoke("ConsumeStateBudget", player.UserId)
	if RunService:IsStudio() then
		if sharedStateCallOk and sharedStateAllowed == false then return nil end
	else
		if not sharedStateCallOk or sharedStateAllowed ~= true then return nil end
	end
	local previous = lastCatalogInvoke[player.UserId] or 0
	if previous > 0 and now - previous < 0.75 then return nil end
	lastCatalogInvoke[player.UserId] = now

	if query ~= nil and (typeof(query) ~= "string" or #query > 48) then return nil end
	if genreId ~= nil and (typeof(genreId) ~= "string" or #genreId > 24) then return nil end
	if offset ~= nil and (typeof(offset) ~= "number" or offset ~= offset or offset % 1 ~= 0) then return nil end
	if limit ~= nil and (typeof(limit) ~= "number" or limit ~= limit or limit % 1 ~= 0) then return nil end

	local ok, result = pcall(function()
		return MusicCatalogService:GetCatalog(query or "", genreId or "", offset or 0, limit or 30)
	end)
	if not ok then
		warn("[ClubMusic] GetMusicCatalog failed for " .. player.Name .. ": " .. tostring(result))
		return nil
	end
	return result
end

local lastPlaylistInvoke: {[number]: number} = {}
playlistFunction.OnServerInvoke = function(player: Player)
	if player.Parent ~= Players or not playlistStorageReady then return nil end
	local now = os.clock()
	if not ControllerFunctions.consumeToken(globalStateQueryBucket, now, 1) then return nil end
	local sharedOk, allowed = ControllerFunctions.globalInvoke("ConsumeStateBudget", player.UserId)
	if RunService:IsStudio() then
		if sharedOk and allowed == false then return nil end
	else
		if not sharedOk or allowed ~= true then return nil end
	end
	local previous = lastPlaylistInvoke[player.UserId] or 0
	if previous > 0 and now - previous < 1 then return nil end
	lastPlaylistInvoke[player.UserId] = now
	if os.clock() - playlistRefreshAt >= 5 then
		if ControllerFunctions.waitForDataStoreBudget(2) and MusicPlaylistService:Refresh() then
			playlistRefreshAt = os.clock()
		end
	end
	return MusicPlaylistService:GetAll()
end

stateFunction.OnServerInvoke = function(player: Player)
	if player.Parent ~= Players then return nil end
	local now = os.clock()
	if not ControllerFunctions.consumeToken(globalStateQueryBucket, now, 1) then return nil end
	local sharedStateCallOk, sharedStateAllowed = ControllerFunctions.globalInvoke("ConsumeStateBudget", player.UserId)
	if RunService:IsStudio() then
		if sharedStateCallOk and sharedStateAllowed == false then return nil end
	else
		if not sharedStateCallOk or sharedStateAllowed ~= true then return nil end
	end
	local previous = lastStateInvoke[player.UserId] or 0
	if previous > 0 and now - previous < CONFIG.GetStateCooldownSeconds then
		return nil -- StateChanged continues to push live updates; client can retry after cooldown.
	end
	lastStateInvoke[player.UserId] = now
	local ok, snapshot = pcall(ControllerFunctions.snapshotFor, player)
	if not ok then
		warn("[ClubMusic] GetState failed for " .. player.Name .. ": " .. tostring(snapshot))
		return nil
	end
	return snapshot
end

-- Server-only integration point for trusted admin addons (for example Kohl's Admin).
-- This is deliberately not replicated. Every request is re-authorized by ClubMusic's
-- own rank cache and then passes through the same action budgets/cooldowns/handlers.
-- Narrow server-only permission resolver for the global security authorization adapter.
-- Uses the same server-verified rank cache as the existing admin bridge.
local authorizationResolver = ControllerFunctions.getOrCreate(
	ServerStorage,
	"BindableFunction",
	"ClubMusicAuthorizationResolver"
) :: BindableFunction
local GLOBAL_PERMISSION_LEVELS = {
	GlobalDJ = 1,
	GlobalModeration = 2,
	GlobalAnnouncement = 2,
	GlobalConfig = 3,
	SecurityPolicy = 3,
	IncidentResponse = 3,
}
authorizationResolver.OnInvoke = function(actorUserId: any, permission: any): boolean
	if typeof(actorUserId) ~= "number" or actorUserId < 1 or actorUserId % 1 ~= 0
		or typeof(permission) ~= "string" then
		return false
	end
	local requiredLevel = GLOBAL_PERMISSION_LEVELS[permission]
	if not requiredLevel then return false end
	local player = Players:GetPlayerByUserId(math.floor(actorUserId))
	if not player or player.Parent ~= Players then return false end
	return ControllerFunctions.getLevel(player) >= requiredLevel
end

-- Kohl's Admin security bridge helpers. Global security operations are checked by
-- the same server-only authorization service used by the cross-server API.
ControllerFunctions.adminBridgeGlobalCall = function(name: string, ...: any): (boolean, any, any)
	local invoked, accepted, value, detail = ControllerFunctions.globalInvoke(name, ...)
	if not invoked then return false, "Global security service is unavailable." end
	if accepted ~= true then
		return false, if typeof(value) == "string" then value else "Global security operation was rejected."
	end
	return true, value, detail
end
ControllerFunctions.adminBridgeAuthorize = function(caller: Player, permission: string): boolean
	local invoked, allowed = ControllerFunctions.globalInvoke("AuthorizeGlobalAction", caller.UserId, permission)
	return invoked and allowed == true
end
ControllerFunctions.adminBridgeReportSignal = function(caller: Player, signal: string, detail: string)
	pcall(ControllerFunctions.globalInvoke, "ReportSignal", caller.UserId, signal, detail)
end

local adminBridge = ControllerFunctions.getOrCreate(ServerStorage, "BindableFunction", "ClubMusicAdminBridge") :: BindableFunction
local ADMIN_BRIDGE_ACTIONS: {[string]: string} = {
	Skip = "DJSkip",
	TogglePause = "DJPause",
	Restart = "DJRestart",
	ToggleRequestLock = "DJToggleLock",
	ClearQueue = "DJClearQueue",
}
adminBridge.OnInvoke = function(caller: any, operation: any, argument: any): (boolean, string)
	if typeof(caller) ~= "Instance" or not caller:IsA("Player") or caller.Parent ~= Players then
		return false, "A live player caller is required."
	end
	if typeof(operation) ~= "string" or #operation > 32 then
		ControllerFunctions.adminBridgeReportSignal(caller, "admin_bridge_invalid_operation", "invalid operation name")
		return false, "Invalid ClubMusic admin operation."
	end
	if not ControllerFunctions.isStaff(caller) then
		ControllerFunctions.adminBridgeReportSignal(caller, "admin_bridge_access_denied", operation)
		return false, "ClubMusic staff permission is required."
	end
	-- Read-only status and queue inspection do not enter the action handler or
	-- consume mutation cooldowns. Global inspection refreshes the authoritative mirror.
	if operation == "Status" then
		local currentTitle = if typeof(nowPlaying.title) == "string" and nowPlaying.title ~= "" then nowPlaying.title else "Nothing playing"
		local currentArtist = if typeof(nowPlaying.artist) == "string" then nowPlaying.artist else ""
		local playbackLabel = if playbackPaused then "PAUSED" else "PLAYING"
		local requestLabel = if requestsLocked then "LOCKED" else "OPEN"
		local queueModeLabel = if globalQueueMode then "GLOBAL" else "LOCAL"
		local queueCount = #queue
		local elapsed = math.max(0, math.floor(tonumber(nowPlaying.elapsed) or 0))
		local duration = math.max(0, math.floor(tonumber(nowPlaying.duration) or 0))
		local trackLabel = currentTitle .. (if currentArtist ~= "" then " — " .. currentArtist else "")
		return true, string.sub(string.format("ClubMusic: %s | %s | Requests %s | Queue %d (%s) | %ds/%ds", trackLabel, playbackLabel, requestLabel, queueCount, queueModeLabel, elapsed, duration), 1, 450)
	end
	if operation == "DJSessionStatus" then
		local manager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.DJSession
		if not manager then return false, "DJ session module is not installed in ServerStorage.ClubMusicAudioModules." end
		local state = manager:GetState()
		local current = state.current
		if not current then return true, "No DJ session is currently active." end
		return true, string.sub(string.format("Active DJ session: %s (UserId %d).", tostring(current.name), current.userId), 1, 180)
	end
	if operation == "DJSessionStart" then
		local manager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.DJSession
		if not manager then return false, "DJ session module is not installed in ServerStorage.ClubMusicAudioModules." end
		local started, sessionOrMessage = manager:Start(caller)
		if not started then return false, tostring(sessionOrMessage) end
		caller:SetAttribute("ClubMusicActiveDJSession", true)
		return true, "DJ session started for " .. caller.Name .. "."
	end
	if operation == "DJSessionHandoff" then
		local manager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.DJSession
		if not manager then return false, "DJ session module is not installed in ServerStorage.ClubMusicAudioModules." end
		if typeof(argument) ~= "string" or #argument < 1 or #argument > 16 or not string.match(argument, "^%d+$") then
			return false, "Use ;cmdjhandoff with the target staff member's numeric UserId."
		end
		local targetUserId = tonumber(argument)
		if not targetUserId or targetUserId < 1 or targetUserId % 1 ~= 0 or targetUserId > 9007199254740991 then
			return false, "A valid target UserId is required."
		end
		local target = Players:GetPlayerByUserId(targetUserId)
		if not target or target.Parent ~= Players then return false, "The target player must be connected to this server." end
		if not ControllerFunctions.isStaff(target) then return false, "The target must have ClubMusic staff permissions." end
		local handedOff, sessionOrMessage = manager:Handoff(caller, target)
		if not handedOff then return false, tostring(sessionOrMessage) end
		caller:SetAttribute("ClubMusicActiveDJSession", false)
		target:SetAttribute("ClubMusicActiveDJSession", true)
		return true, "DJ session handed off to " .. target.Name .. "."
	end
	if operation == "DJSessionEnd" then
		local manager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.DJSession
		if not manager then return false, "DJ session module is not installed in ServerStorage.ClubMusicAudioModules." end
		local ended, message = manager:End(caller)
		if not ended then return false, tostring(message) end
		caller:SetAttribute("ClubMusicActiveDJSession", false)
		return true, "DJ session ended."
	end
	if operation == "Queue" then
		if globalQueueMode and (not syncGlobalQueueSnapshot or not syncGlobalQueueSnapshot()) then
			return false, "The shared queue could not be refreshed. Try ;cmqueue again shortly."
		end
		local total = #queue
		if total == 0 then return true, "ClubMusic queue is empty (" .. (if globalQueueMode then "GLOBAL" else "LOCAL") .. ")." end
		local lines = {string.format("ClubMusic queue (%s) — %d queued:", if globalQueueMode then "GLOBAL" else "LOCAL", total)}
		local shown = math.min(total, 6)
		for index = 1, shown do
			local entry = queue[index]
			local title = string.sub(string.gsub(tostring(entry.title or "Unknown track"), "[%c]", " "), 1, 34)
			local artist = string.sub(string.gsub(tostring(entry.artist or "Unknown artist"), "[%c]", " "), 1, 24)
			local requester = string.sub(string.gsub(tostring(entry.requestedBy or "Unknown"), "[%c]", " "), 1, 18)
			table.insert(lines, string.format("%d. %s — %s | %s | ID: %s", index, title, artist, requester, tostring(entry.id or "")))
		end
		if total > shown then table.insert(lines, string.format("...and %d more. Run ;cmqueue again after removals.", total - shown)) end
		return true, string.sub(table.concat(lines, "\n"), 1, 1800)
	end
	-- Security administration is exposed through this server-only bridge, not client remotes.
	if operation == "RequestMute" or operation == "ClearUserQueue" or operation == "EmergencyLock" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "GlobalModeration") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_moderation_access_denied", operation)
			return false, "ClubMusic administrator permission is required."
		end
	end
	if operation == "RequestMute" then
		if typeof(argument) ~= "string" or #argument < 3 or #argument > 220 then
			return false, "Usage: ;cmrequestmute <UserId> on|off [reason]"
		end
		local rawUserId, mode, reason = string.match(argument, "^(%d+)%s+(%a+)%s*(.-)$")
		local targetUserId = tonumber(rawUserId)
		if not targetUserId or targetUserId < 1 or targetUserId % 1 ~= 0 or targetUserId > 9007199254740991 then
			return false, "Provide a valid numeric Roblox UserId."
		end
		mode = if mode then string.lower(mode) else ""
		if mode ~= "on" and mode ~= "off" then return false, "Use on or off. Example: ;cmrequestmute 123456 on Spam" end
		local cleanReason = if reason ~= "" then string.sub(reason, 1, 160) else nil
		local ok, accepted = ControllerFunctions.adminBridgeGlobalCall("SetRequestBlocked", targetUserId, mode == "on", caller.UserId)
		if not ok or accepted ~= true then return false, tostring(accepted or "Request restriction update failed.") end
		local target = Players:GetPlayerByUserId(targetUserId)
		if mode == "on" then
			blockedUsers[targetUserId] = true
			ControllerFunctions.purgeUserEntries(targetUserId)
		else
			blockedUsers[targetUserId] = nil
		end
		ControllerFunctions.adminBridgeGlobalCall("RecordGlobalModerationAction", targetUserId, "RequestMute", mode, caller.UserId, cleanReason)
		publishState(nil)
		return true, string.format("ClubMusic requests %s for UserId %d%s.", if mode == "on" then "disabled" else "re-enabled", targetUserId, if target then " (" .. target.Name .. ")" else "")
	end
	if operation == "ClearUserQueue" then
		if typeof(argument) ~= "string" or #argument > 24 or not string.match(argument, "^%d+$") then
			return false, "Usage: ;cmclearuserqueue <numeric UserId>"
		end
		local targetUserId = tonumber(argument)
		if not targetUserId or targetUserId < 1 or targetUserId % 1 ~= 0 or targetUserId > 9007199254740991 then return false, "Provide a valid numeric Roblox UserId." end
		local removed = ControllerFunctions.purgeUserEntries(targetUserId)
		publishState(nil)
		return true, string.format("Removed %d queued ClubMusic request(s) for UserId %d.", removed, targetUserId)
	end
	if operation == "EmergencyLock" then
		local ok, accepted = ControllerFunctions.adminBridgeGlobalCall("PublishDJCommand", "SetRequestLock", {locked = true}, caller.UserId)
		if not ok or accepted ~= true then return false, tostring(accepted or "Global request lock could not be persisted.") end
		requestsLocked = true
		ControllerFunctions.broadcast("ClubMusic requests have been emergency-locked by staff.", "warn")
		publishState(nil)
		return true, "ClubMusic requests are now locked across servers. Use ;cmlock after the incident to reopen them."
	end
	if operation == "SecurityStatus" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "GlobalModeration") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic administrator permission is required."
		end
		local ok, status = ControllerFunctions.adminBridgeGlobalCall("GetGlobalSecurityStatus")
		if not ok or typeof(status) ~= "table" then return false, tostring(status or "Security status is unavailable.") end
		local lines = {"ClubMusic Global Security Status:"}
		for _, key in ipairs({"Authorization", "Monitor", "MessageValidation", "Idempotency", "IncidentResponse"}) do
			local item = status[key]
			local state = if typeof(item) == "table" then tostring(item.state or "Unknown") else "Unavailable"
			table.insert(lines, key .. ": " .. state)
		end
		local policy = status.Policy
		table.insert(lines, "Policy revision: " .. tostring(if typeof(policy) == "table" then policy.revision else "Unavailable"))
		return true, table.concat(lines, "\n")
	end
	if operation == "SecurityIncidents" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "IncidentResponse") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic co-owner/owner permission is required."
		end
		local ok, incidents = ControllerFunctions.adminBridgeGlobalCall("GetGlobalSecurityIncidents", 8)
		if not ok or typeof(incidents) ~= "table" then return false, tostring(incidents or "Incident service is unavailable.") end
		if #incidents == 0 then return true, "No recent ClubMusic security incidents." end
		local lines = {"Recent ClubMusic security incidents:"}
		for index, item in ipairs(incidents) do
			if index > 8 then break end
			if typeof(item) == "table" then
				table.insert(lines, string.format("%s | %s | %s | %s", tostring(item.id or "?"), tostring(item.kind or "?"), tostring(item.state or "?"), string.sub(tostring(item.summary or ""), 1, 100)))
			end
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1700)
	end
	if operation == "SecurityIncidentOpen" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "IncidentResponse") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic co-owner/owner permission is required."
		end
		if typeof(argument) ~= "string" or #argument < 4 or #argument > 200 then
			return false, "Usage: ;cmincident <SecurityAlert|ServiceDegraded|AbuseReport|ManualReview> <summary>"
		end
		local kind, summary = string.match(argument, "^(%a+)%s+(.+)$")
		if not kind or not summary or #summary > 180 then return false, "Provide an allowed incident type followed by a summary (max 180 characters)." end
		local ok, incidentId = ControllerFunctions.adminBridgeGlobalCall("OpenGlobalSecurityIncident", kind, summary, caller.UserId)
		if not ok then return false, tostring(incidentId) end
		return true, "Security incident opened: " .. tostring(incidentId)
	end
	if operation == "SecurityIncidentResolve" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "IncidentResponse") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic co-owner/owner permission is required."
		end
		if typeof(argument) ~= "string" or #argument < 8 or #argument > 64 or not string.match(argument, "^[%w%-]+$") then
			return false, "Usage: ;cmresolve <incident ID>"
		end
		local ok, resolved = ControllerFunctions.adminBridgeGlobalCall("ResolveGlobalSecurityIncident", argument, caller.UserId)
		if not ok then return false, tostring(resolved) end
		return true, "Security incident resolved."
	end
	if operation == "SecurityPolicy" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "SecurityPolicy") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic co-owner/owner permission is required."
		end
		local ok, policy = ControllerFunctions.adminBridgeGlobalCall("GetGlobalSecurityPolicy")
		if not ok or typeof(policy) ~= "table" then return false, tostring(policy or "Security policy is unavailable.") end
		local values = if typeof(policy.values) == "table" then policy.values else {}
		local keys = {}
		for key in pairs(values) do table.insert(keys, tostring(key)) end
		table.sort(keys)
		local lines = {"ClubMusic Security Policy (revision " .. tostring(policy.revision or "?") .. "):"}
		for _, key in ipairs(keys) do table.insert(lines, key .. " = " .. tostring(values[key])) end
		return true, table.concat(lines, "\n")
	end
	if operation == "SecurityPolicySet" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "SecurityPolicy") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic co-owner/owner permission is required."
		end
		if typeof(argument) ~= "string" or #argument > 80 then return false, "Usage: ;cmpolicyset <key> <value>" end
		local key, rawValue = string.match(argument, "^(%w+)%s+([^%s]+)$")
		if not key or not rawValue then return false, "Usage: ;cmpolicyset <key> <value>" end
		local value: any
		if key == "monitoringEnabled" then
			if rawValue ~= "true" and rawValue ~= "false" then return false, "monitoringEnabled must be true or false." end
			value = rawValue == "true"
		else
			value = tonumber(rawValue)
			if not value or value ~= value or value == math.huge or value == -math.huge then return false, "Policy value must be a finite number." end
		end
		local ok, policy = ControllerFunctions.adminBridgeGlobalCall("SetGlobalSecurityPolicy", key, value, caller.UserId)
		if not ok then return false, tostring(policy) end
		return true, "Security policy updated. " .. key .. " = " .. tostring(value)
	end
	-- Operational inspection commands use the same independent ClubMusic
	-- authorization service as security administration. All inspection paths are
	-- read-only; only explicit owner maintenance/reconcile requests reach setters.
	local operationalPermission = ({
		OperationalHealth = "GlobalModeration",
		OperationalCatalogRefresh = "GlobalConfig",
		OperationalServices = "GlobalModeration",
		OperationalDiagnostics = "GlobalConfig",
		OperationalErrors = "GlobalConfig",
		OperationalMetrics = "GlobalModeration",
		OperationalSecurityLog = "IncidentResponse",
		OperationalServers = "IncidentResponse",
		OperationalRateLimit = "IncidentResponse",
		OperationalConfig = "GlobalConfig",
		OperationalRecovery = "GlobalConfig",
		OperationalReconcile = "GlobalConfig",
		OperationalMaintenance = "GlobalConfig",
	} :: {[string]: string})[operation]
	if operationalPermission then
		if not ControllerFunctions.adminBridgeAuthorize(caller, operationalPermission) then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_operational_access_denied", operation)
			return false, if operationalPermission == "GlobalModeration"
				then "ClubMusic administrator permission is required."
				else "ClubMusic co-owner/owner permission is required."
		end
	end

	if operation == "OperationalCatalogRefresh" then
		if not ControllerFunctions.refreshCatalogWhenReady() then
			return false, "Catalog refresh could not complete. Check catalog storage readiness and DataStore budget."
		end
		return true, string.format("ClubMusic catalog refreshed successfully: %d playable tracks.", #ALL_TRACK_IDS)
	end
	if operation == "OperationalHealth" then
		local ok, health = ControllerFunctions.adminBridgeGlobalCall("GetGlobalHealth")
		if not ok or typeof(health) ~= "table" then return false, tostring(health or "Health status is unavailable.") end
		return true, string.sub(string.format(
			"ClubMusic Health: %s | Local: %s | Global: %s | Sync: %s (%d peers) | Recovery: %s\n%s",
			tostring(health.state or "Unknown"), tostring(health.localState or "Unknown"),
			tostring(health.serviceState or "Unknown"), tostring(health.syncState or "Unknown"),
			math.clamp(tonumber(health.syncStatus and health.syncStatus.peerCount) or 0, 0, 999),
			tostring(health.recoveryState or "Unknown"), string.sub(tostring(health.detail or health.localDetail or ""), 1, 500)
		), 1, 1100)
	end
	if operation == "OperationalDiagnostics" then
		local ok, snapshot = ControllerFunctions.adminBridgeGlobalCall("GetGlobalDiagnostics")
		if not ok or typeof(snapshot) ~= "table" then return false, tostring(snapshot or "Diagnostic snapshot is unavailable.") end
		local health = if typeof(snapshot.health) == "table" then snapshot.health else {}
		local recovery = if typeof(snapshot.recovery) == "table" then snapshot.recovery else {}
		local sync = if typeof(snapshot.syncStatus) == "table" then snapshot.syncStatus else {}
		local services = if typeof(snapshot.operationalServices) == "table" then snapshot.operationalServices else {}
		local lines = {
			"ClubMusic Diagnostic Snapshot:",
			"Generated: " .. os.date("!%Y-%m-%d %H:%M:%S UTC", tonumber(snapshot.generatedAt) or os.time()),
			"Global enabled: " .. tostring(snapshot.serviceEnabled == true),
			"Health: " .. tostring(health.state or "Unavailable") .. " / Local: " .. tostring(health.localState or "Unavailable"),
			"Sync: " .. tostring(sync.state or "Unavailable") .. " / peers: " .. tostring(sync.peerCount or 0),
			"Recovery: " .. tostring(recovery.state or "Unavailable"),
			"Watchdog: " .. tostring(services.watchdog and services.watchdog.state or "Unavailable"),
			"Error history: " .. tostring(snapshot.errorHistoryAvailable == true),
		}
		return true, string.sub(table.concat(lines, "\n"), 1, 1300)
	end
	if operation == "OperationalServices" then
		local ok, services = ControllerFunctions.adminBridgeGlobalCall("GetGlobalOperationalStatus")
		if not ok or typeof(services) ~= "table" then return false, tostring(services or "Operational service status is unavailable.") end
		local keys = {}
		for key in pairs(services) do table.insert(keys, tostring(key)) end
		table.sort(keys)
		local lines = {"ClubMusic Service Status:"}
		for _, key in ipairs(keys) do
			local item = services[key]
			table.insert(lines, key .. ": " .. tostring(if typeof(item) == "table" then item.state or "Unknown" else "Unavailable"))
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1500)
	end
	if operation == "OperationalErrors" then
		local ok, snapshot = ControllerFunctions.adminBridgeGlobalCall("GetGlobalDiagnostics")
		if not ok or typeof(snapshot) ~= "table" then return false, tostring(snapshot or "Diagnostic history is unavailable.") end
		if snapshot.errorHistoryAvailable ~= true then return true, "ClubMusic error history is unavailable; check whether ClubMusicErrorHandler is installed." end
		local errors = if typeof(snapshot.recentErrors) == "table" then snapshot.recentErrors else {}
		if #errors == 0 then return true, "No recent ClubMusic errors are recorded." end
		local lines = {"Recent ClubMusic errors (metadata only):"}
		for index = math.max(1, #errors - 7), #errors do
			local item = errors[index]
			if typeof(item) == "table" then
				table.insert(lines, string.format("%s | %s / %s | repeats not included",
					tostring(item.id or "?"), tostring(item.subsystem or "?"), tostring(item.operation or "?")))
			end
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1200)
	end
	if operation == "OperationalMetrics" then
		local ok, metrics = ControllerFunctions.adminBridgeGlobalCall("GetGlobalMetrics")
		if not ok or typeof(metrics) ~= "table" then return false, tostring(metrics or "Metrics are unavailable or disabled.") end
		local aggregate = if typeof(metrics.aggregate) == "table" then metrics.aggregate else {}
		local counters = if typeof(aggregate.counters) == "table" then aggregate.counters else {}
		local keys = {}
		for key in pairs(counters) do table.insert(keys, tostring(key)) end
		table.sort(keys)
		local lines = {"ClubMusic Metrics (" .. tostring(metrics.state or "Unknown") .. "):"}
		for index = 1, math.min(#keys, 12) do
			local key = keys[index]
			table.insert(lines, key .. " = " .. tostring(counters[key]))
		end
		if #keys == 0 then table.insert(lines, "No aggregated counters are available yet.") end
		return true, string.sub(table.concat(lines, "\n"), 1, 1400)
	end
	if operation == "OperationalSecurityLog" then
		local ok, entries = ControllerFunctions.adminBridgeGlobalCall("GetGlobalAudit", 30)
		if not ok or typeof(entries) ~= "table" then return false, tostring(entries or "Security audit log is unavailable.") end
		local lines = {"Recent ClubMusic security audit events:"}
		local count = 0
		for _, item in ipairs(entries) do
			if typeof(item) == "table" and item.kind == "SecurityEvent" then
				count += 1
				table.insert(lines, string.format("%s | actor %s | %s | %s",
					tostring(item.at or "?"), tostring(item.actorUserId or "?"),
					string.sub(tostring(item.target or "?"), 1, 48), string.sub(tostring(item.action or "?"), 1, 64)))
				if count >= 8 then break end
			end
		end
		if count == 0 then table.insert(lines, "No recent security audit events were found in the latest audit page.") end
		return true, string.sub(table.concat(lines, "\n"), 1, 1500)
	end
	if operation == "OperationalServers" then
		local ok, servers = ControllerFunctions.adminBridgeGlobalCall("GetGlobalServers", 12)
		if not ok or typeof(servers) ~= "table" then return false, tostring(servers or "Server registry is unavailable.") end
		local lines = {"Registered ClubMusic servers (up to 12):"}
		for index, item in ipairs(servers) do
			if index > 12 then break end
			if typeof(item) == "table" then
				table.insert(lines, string.format("%d. Place %s | %d/%d players | health %s | heartbeat %s",
					index, tostring(item.placeId or "?"), math.clamp(tonumber(item.players) or 0, 0, 1000),
					math.clamp(tonumber(item.maxPlayers) or 0, 0, 1000), tostring(item.health or "Unknown"),
					os.date("!%H:%M:%S", tonumber(item.updatedAt) or 0)))
			end
		end
		if #servers == 0 then table.insert(lines, "No active registry entries were returned.") end
		return true, string.sub(table.concat(lines, "\n"), 1, 1300)
	end
	if operation == "OperationalRateLimit" then
		local ok, services = ControllerFunctions.adminBridgeGlobalCall("GetGlobalOperationalStatus")
		local item = if ok and typeof(services) == "table" then services.RateLimit else nil
		if typeof(item) ~= "table" then return false, "Rate-limit service status is unavailable." end
		return true, string.format("ClubMusic Rate Limits: %s | checks %s | rejected %s | shared failures %s | existing shared buckets: %s",
			tostring(item.state or "Unknown"), tostring(item.checks or 0), tostring(item.rejected or 0),
			tostring(item.sharedFailures or 0), tostring(item.usesExistingBuckets == true))
	end
	if operation == "OperationalConfig" then
		local ok, config = ControllerFunctions.adminBridgeGlobalCall("GetGlobalConfig")
		if not ok or typeof(config) ~= "table" then return false, tostring(config or "Global configuration is unavailable.") end
		local values = if typeof(config.values) == "table" then config.values else {}
		local keys = {}
		for key in pairs(values) do table.insert(keys, tostring(key)) end
		table.sort(keys)
		local lines = {"ClubMusic Global Config (revision " .. tostring(config.revision or "?") .. "):"}
		for _, key in ipairs(keys) do
			local value = values[key]
			if key == "maintenanceMessage" then value = string.sub(tostring(value), 1, 80) end
			table.insert(lines, key .. " = " .. tostring(value))
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1500)
	end
	if operation == "OperationalRecovery" then
		local ok, snapshot = ControllerFunctions.adminBridgeGlobalCall("GetGlobalDiagnostics")
		if not ok or typeof(snapshot) ~= "table" then return false, tostring(snapshot or "Recovery status is unavailable.") end
		local recovery = if typeof(snapshot.recovery) == "table" then snapshot.recovery else {}
		return true, string.sub("ClubMusic Recovery: " .. tostring(recovery.state or "Unavailable")
			.. " | attempts " .. tostring(recovery.attempts or 0) .. " | " .. tostring(recovery.detail or ""), 1, 900)
	end
	if operation == "OperationalReconcile" then
		local ok, result = ControllerFunctions.adminBridgeGlobalCall("RunGlobalReconciliation", caller.UserId)
		if not ok then return false, tostring(result or "Read-only reconciliation failed.") end
		local status = if typeof(result) == "table" then result else {}
		return true, "Read-only reconciliation: " .. tostring(status.state or "Unknown") .. " | " .. tostring(status.detail or "")
	end
	if operation == "OperationalMaintenance" then
		local command = if typeof(argument) == "string" then string.sub(argument, 1, 240) else "status"
		local action, message = string.match(command, "^(%a+)%s*(.*)$")
		if not action or action == "" then action = "status" end
		action = string.lower(action)
		if action == "status" then
			local ok, services = ControllerFunctions.adminBridgeGlobalCall("GetGlobalOperationalStatus")
			local item = if ok and typeof(services) == "table" then services.Maintenance else nil
			if typeof(item) ~= "table" then return false, "Maintenance service status is unavailable." end
			return true, "ClubMusic Maintenance: " .. tostring(item.enabled == true) .. " | revision " .. tostring(item.revision or "?") .. " | " .. tostring(item.message or "")
		end
		if action ~= "on" and action ~= "off" then return false, "Usage: ;cmmaintenance status OR ;cmmaintenance on [message] OR ;cmmaintenance off" end
		local enabled = action == "on"
		local maintenanceMessage = if enabled and message ~= "" then message else nil
		local ok, result = ControllerFunctions.adminBridgeGlobalCall("SetGlobalMaintenance", enabled, maintenanceMessage, caller.UserId)
		if not ok then return false, tostring(result or "Maintenance setting was rejected.") end
		return true, "ClubMusic global maintenance mode " .. (if enabled then "enabled." else "disabled.")
	end
	local action = ADMIN_BRIDGE_ACTIONS[operation]
	local payload = {}
	if operation == "RemoveQueueEntry" then
		if typeof(argument) ~= "string" or #argument > 64
			or not string.match(argument, "^cm%-%x+%-%x+%-%x+%-%x+%-%x+$") then
			return false, "Use ;cmremove with a queue ID copied from ;cmqueue."
		end
		action = "DJRemove"
		payload = {queueId = argument}
	end
	if not action then return false, "That ClubMusic admin operation is not exposed." end
	if action == "DJClearQueue" and not ControllerFunctions.isAdmin(caller) then
		ControllerFunctions.adminBridgeReportSignal(caller, "admin_bridge_access_denied", operation)
		return false, "ClubMusic administrator permission is required to clear the queue."
	end
	local ok, accepted, message = pcall(ControllerFunctions.handleAction, caller, action, payload, true)
	if not ok then
		warn("[ClubMusic Admin Bridge] Action failed: " .. tostring(accepted))
		return false, "ClubMusic could not process that action."
	end
	if accepted ~= true then
		return false, if typeof(message) == "string" then message else "ClubMusic rejected that action."
	end
	return true, if typeof(message) == "string" then message else "ClubMusic action accepted."
end

-- Construct the child managers only after their controller-owned callbacks and
-- service state exist. These instances are facades; they do not start independent
-- playback loops, sounds, queues, playlist cursors, or vote timers.
ControllerFunctions.ChildManagers = {}
local childManagerModules = ControllerFunctions.ChildManagerModules
local audioManagerOk, audioManager = pcall(childManagerModules.ServerMusicAudioHandler.new, {
	Sound = musicSound,
	GetSound = function()
		local source = activeAudioSource
		return if source.kind == "Sound" then source.instance else nil
	end,
	GetSnapshot = function() return ControllerFunctions.getAudioSnapshot() end,
	GetPaused = function() return playbackPaused end,
})
if not audioManagerOk then error("[ClubMusic] ServerMusicAudioHandler initialization failed: " .. tostring(audioManager)) end
ControllerFunctions.ChildManagers.Audio = audioManager

local playbackManagerOk, playbackManager = pcall(childManagerModules.MusicPlaybackManager.new, {
	GetSnapshot = function()
		return {
			nowPlaying = table.clone(nowPlaying),
			playbackPaused = playbackPaused,
		}
	end,
	GetSound = function()
		local source = activeAudioSource
		return if source.kind == "Sound" then source.instance else nil
	end,
	GetAudioSnapshot = function() return audioManager:GetPlaybackSnapshot() end,
	GetElapsedTime = function() return nowPlaying.elapsed end,
	TogglePause = function(player: Player)
		return ControllerFunctions.handleAction(player, "DJPause", {}, false)
	end,
	RestartTrack = function(player: Player)
		return ControllerFunctions.handleAction(player, "DJRestart", {}, false)
	end,
})
if not playbackManagerOk then error("[ClubMusic] MusicPlaybackManager initialization failed: " .. tostring(playbackManager)) end
ControllerFunctions.ChildManagers.Playback = playbackManager

local playlistManagerOk, playlistManager = pcall(childManagerModules.MusicPlaylistManager.new, {
	Service = MusicPlaylistService,
	GetRotationState = function()
		local trackIds = {}
		for _, track in ipairs(activePlaylistTracks) do table.insert(trackIds, track.id) end
		return {
			active = activePlaylistId ~= nil or globalPlaylistRotationEnabled,
			playlistId = activePlaylistId,
			name = activePlaylistName,
			cursor = activePlaylistCursor,
			trackIds = trackIds,
			global = globalQueueMode,
		}
	end,
	StartRotation = function(player: Player, playlistId: any)
		return ControllerFunctions.startPlaylistRotation(player, playlistId), nil
	end,
	StopRotation = function(player: Player)
		return ControllerFunctions.stopPlaylistRotation(player), nil
	end,
	SelectNextTrack = function()
		return ControllerFunctions.nextPlaylistTrack()
	end,
})
if not playlistManagerOk then error("[ClubMusic] MusicPlaylistManager initialization failed: " .. tostring(playlistManager)) end
ControllerFunctions.ChildManagers.Playlist = playlistManager

local skipVoteManagerOk, skipVoteManager = pcall(childManagerModules.MusicSkipVoteManager.new, {
	GetVoteState = function()
		local votes, needed = ControllerFunctions.skipStatus(nil)
		return {
			active = nowPlaying.trackId ~= "",
			votes = votes,
			needed = needed,
			playerCount = #Players:GetPlayers(),
		}
	end,
	CastVote = function(player: Player)
		if skipVotes[player.UserId] then return false, "You already voted to skip this track." end
		skipVotes[player.UserId] = true
		if ControllerFunctions.checkSkipVotes() then
			ControllerFunctions.broadcast("Track skipped by vote.", "ok")
		else
			local votes, needed = ControllerFunctions.skipStatus(nil)
			notify(player, string.format("Skip vote counted (%d/%d).", votes, needed), "ok")
		end
		publishState(nil)
		return true, "Skip vote counted."
	end,
	RemoveVoter = function(userId: number)
		skipVotes[userId] = nil
		-- Defer until Players:GetPlayers() no longer includes the departing player.
		task.defer(function()
			if ControllerFunctions.checkSkipVotes() then ControllerFunctions.broadcast("Track skipped by vote.", "ok") end
			publishState(nil)
		end)
	end,
})
if not skipVoteManagerOk then error("[ClubMusic] MusicSkipVoteManager initialization failed: " .. tostring(skipVoteManager)) end
ControllerFunctions.ChildManagers.SkipVote = skipVoteManager

-- Optional DJ session facade. It lives in the separately installed audio module
-- folder and never grants staff roles or changes queue/playback ownership.
local audioModulesFolder = ServerStorage:FindFirstChild("ClubMusicAudioModules")
local djSessionModule = audioModulesFolder and audioModulesFolder:FindFirstChild("ClubMusicDJSessionManager")
if djSessionModule and djSessionModule:IsA("ModuleScript") then
	local djRequireOk, djSessionClass = pcall(require, djSessionModule)
	if djRequireOk and typeof(djSessionClass) == "table" and typeof(djSessionClass.new) == "function" then
		local djSessionOk, djSessionManager = pcall(djSessionClass.new, {
			Authorize = function(player: Player, _action: string): boolean
				return player.Parent == Players and ControllerFunctions.isStaff(player)
			end,
			OnHandoff = function(fromPlayer: Player, toPlayer: Player): boolean
				if fromPlayer.Parent ~= Players or toPlayer.Parent ~= Players then return false end
				if not ControllerFunctions.isStaff(fromPlayer) or not ControllerFunctions.isStaff(toPlayer) then return false end
				fromPlayer:SetAttribute("ClubMusicActiveDJSession", false)
				toPlayer:SetAttribute("ClubMusicActiveDJSession", true)
				return true
			end,
		})
		if djSessionOk then
			ControllerFunctions.ChildManagers.DJSession = djSessionManager
		else
			warn("[ClubMusic][DJSession] Optional manager initialization failed: " .. tostring(djSessionManager))
		end
	else
		warn("[ClubMusic][DJSession] Optional module failed validation/load: " .. tostring(djSessionClass))
	end
else
	warn("[ClubMusic][DJSession] Optional module not found at ServerStorage.ClubMusicAudioModules. DJ session commands are unavailable.")
end

-- Load the optional crossfade coordinator after controller state and all child
-- managers exist. Construction creates no deck and does not change live output;
-- an explicit controller call is still required to begin a transition.
do
	local crossfadeOk, crossfadeError = ControllerFunctions.createAudioCrossfadeManager()
	if not crossfadeOk then
		warn("[ClubMusic][Crossfade] Coordinator unavailable; legacy playback remains active: " .. tostring(crossfadeError))
	else
		print("[ClubMusic][Crossfade] Coordinator initialized (inactive until explicitly requested).")
	end
end

remotes:SetAttribute("StartupStage", "BindingHandlers")
actionRemote.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
	local ok, err = pcall(ControllerFunctions.handleAction, player, action, payload)
	if not ok then warn("[ClubMusic] Action handler error: " .. tostring(err)) end
end)
remotes:SetAttribute("StartupStage", "Ready")
remotes:SetAttribute("Ready", true)

-- Releases this server's profile lease after the final save. Ownership is checked
-- inside UpdateAsync so a stale server cannot clear a newer server's lease.
ControllerFunctions.releaseProfileSession = function(userId: number)
	if USE_STUDIO_MEMORY_PROFILES then
		return
	end
	if not ControllerFunctions.waitForDataStoreBudget(3) then
		warn("[ClubMusic] Could not release profile lease before shutdown/removal; lease will expire naturally for userId " .. tostring(userId))
		return
	end

	local ok, err = pcall(function()
		store:UpdateAsync(tostring(userId), function(oldData)
			if typeof(oldData) ~= "table" or typeof(oldData.sessionLock) ~= "table"
				or oldData.sessionLock.owner ~= SESSION_TOKEN then return nil end
			local updated = table.clone(oldData)
			updated.sessionLock = nil
			return updated
		end)
	end)
	if not ok then warn("[ClubMusic] Could not release profile session for " .. tostring(userId) .. ": " .. tostring(err)) end
end

-- Player lifecycle ----------------------------------------------------------------------

-- Collection tag unlocks are granted only from server-verified profile/pass state.
ControllerFunctions.syncTitleTagUnlocks = function(player: Player): boolean
	local profile = profiles[player.UserId]
	if not profile then return false end
	local changed = false
	if ControllerFunctions.isVip(player) and profile.ownedTags.vip ~= true then
		profile.ownedTags.vip = true
		changed = true
		notify(player, "VIP title tag unlocked!", "ok")
	end
	if profile.loginStreak >= 7 and profile.ownedTags.wave ~= true then
		profile.ownedTags.wave = true
		changed = true
		notify(player, "Wave Rider title tag unlocked for your 7-day login streak!", "ok")
	end
	if profile.clubPlaySeconds >= 36000 and profile.ownedTags.party ~= true then
		profile.ownedTags.party = true
		changed = true
		notify(player, "Party Animal title tag unlocked after 10 hours at the festival!", "ok")
	end
	if changed then
		ControllerFunctions.scheduleProfileSave(player)
		publishState(player)
	end
	return changed
end

ControllerFunctions.onJoin = function(player: Player)
	local enabledCallOk, globalServiceEnabled = ControllerFunctions.globalInvoke("IsEnabled")
	local globalModerationRequired = not RunService:IsStudio()
	if globalModerationRequired and (not enabledCallOk or globalServiceEnabled ~= true) then
		player:Kick("The experience security service is temporarily unavailable. Please rejoin shortly.")
		return
	end
	local lockCallOk, globalLock, lockLookupOk = ControllerFunctions.globalInvoke("GetGlobalRequestLock")
	if lockCallOk and lockLookupOk == true and typeof(globalLock) == "boolean" then
		requestsLocked = globalLock
	elseif globalModerationRequired then
		-- Do not silently open requests when the authoritative global lock cannot be read.
		requestsLocked = true
	end
	local banCallOk, globallyBanned, banLookupOk = ControllerFunctions.globalInvoke("IsGloballyBanned", player.UserId)
	if banCallOk and banLookupOk == true and globallyBanned == true then
		player:Kick("You are globally banned from this experience.")
		return
	elseif globalModerationRequired and (not banCallOk or banLookupOk ~= true) then
		-- Fail closed for global bans while the authoritative moderation store is unavailable.
		player:Kick("Global moderation is temporarily unavailable. Please rejoin shortly.")
		return
	end
	local blockCallOk, globallyBlocked, blockLookupOk = ControllerFunctions.globalInvoke("IsRequestBlocked", player.UserId)
	if blockCallOk and blockLookupOk == true and globallyBlocked == true then
		blockedUsers[player.UserId] = true
	elseif globalModerationRequired and (not blockCallOk or blockLookupOk ~= true) then
		-- Keep the player connected, but fail closed for the request feature.
		blockedUsers[player.UserId] = true
	end
	ControllerFunctions.refreshRank(player)
	ControllerFunctions.refreshVip(player)
	local loaded = ControllerFunctions.loadProfile(player)
	if not loaded then
		notify(player, "Your profile could not be loaded. Please rejoin in a moment; no default profile was saved over your data.", "warn")
		return
	end
	ControllerFunctions.applyVipAttribute(player)
	ControllerFunctions.syncTitleTagUnlocks(player)
	player:SetAttribute("ClubRank", ControllerFunctions.getRank(player))
	xpLastAwardAt[player.UserId] = os.clock()
	xpFractional[player.UserId] = 0
	xpLastSaveAt[player.UserId] = os.clock()
	publishState(nil) -- also refreshes the staff roster for everyone with access
end


-- Apply validated cross-server events to this server's local state. The API
-- folder can be created slightly after this controller starts, so attach both
-- immediately and through ServerStorage.ChildAdded for startup-order recovery.
local lastCatalogRefreshAt = 0
local catalogRefreshBusy = false

refreshLocalCatalog = function(): boolean
	if catalogRefreshBusy or not catalogStorageReady then return false end
	catalogRefreshBusy = true
	local refreshed = false
	local ok, err = pcall(function()
		if not ControllerFunctions.waitForDataStoreBudget(5) then return end
		if not MusicCatalogService:Refresh() then return end
		local nextTracks: {[string]: Track} = {}
		local nextIds: {string} = {}
		for _, catalogTrack in ipairs(MusicCatalogService:GetAllTracks()) do
			local track: Track = {
				id = catalogTrack.id,
				genreId = catalogTrack.genreId,
				title = catalogTrack.title,
				artist = catalogTrack.artist,
				duration = catalogTrack.duration,
				genre = catalogTrack.genre,
				assetId = catalogTrack.assetId,
				soundId = catalogTrack.soundId,
			}
			nextTracks[track.id] = track
			table.insert(nextIds, track.id)
		end
		table.sort(nextIds)
		table.clear(TRACK_BY_ID)
		for id, track in pairs(nextTracks) do TRACK_BY_ID[id] = track end
		table.clear(ALL_TRACK_IDS)
		for _, id in ipairs(nextIds) do table.insert(ALL_TRACK_IDS, id) end

		-- Catalog invalidation can remove tracks referenced by an active playlist.
		-- Rebuild the in-memory playable view without mutating the saved playlist:
		-- stale IDs remain available if a track is restored in a later catalog sync.
		if globalQueueMode then
			-- The shared rotation is authoritative in global mode; re-read it
			-- against the refreshed local catalog instead of replacing it with
			-- this server's possibly stale playlist copy.
			if syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
			-- A removed track can leave a rotation with no locally playable IDs.
			-- Disable that stale rotation so an empty queue can fall back to Auto DJ.
			if globalPlaylistRotationEnabled and not activePlaylistId then
				local rotationSynced, rotationMessage = ControllerFunctions.syncGlobalPlaylistRotation()
				if not rotationSynced then
					warn("[ClubMusic] Could not clear a playlist rotation with no playable catalog tracks: " .. tostring(rotationMessage))
				end
			end
		elseif activePlaylistId then
			ControllerFunctions.reloadActivePlaylist()
		end
		refreshed = true
	end)
	catalogRefreshBusy = false
	if not ok then warn("[ClubMusic] Catalog refresh failed: " .. tostring(err)) end
	if refreshed then
		lastCatalogRefreshAt = os.clock()
		localCatalogRevision = globalCatalogRevision
		publishState(nil)
	end
	return refreshed
end

ControllerFunctions.applyGlobalPlaybackControl = function(command: string, payload: any): boolean
	-- When the shared queue is active, its playback snapshot is authoritative.
	-- The legacy playbackControl store is a separate compatibility path; applying
	-- its delayed reconciliation events here could overwrite a newer queue pause
	-- or restart with stale state.
	if globalQueueMode then return false end
	-- Playback revisions are monotonic integer sequence numbers. Reject malformed
	-- fractional/unsafe values instead of silently rounding them into a valid revision.
	if typeof(payload) ~= "table" or not ControllerFunctions.isFiniteNumber(payload.revision)
		or payload.revision < 1 or payload.revision % 1 ~= 0
		or payload.revision > 9007199254740991 then return false end
	local revision = payload.revision
	if revision <= lastGlobalPlaybackRevision then return false end
	if command == "SetPlaybackPaused" then
		if typeof(payload.paused) ~= "boolean" then return false end
		ControllerFunctions.cancelAudioTransition(if payload.paused then "global-pause" else "global-resume")
		playbackPaused = payload.paused
		if ControllerFunctions.isFiniteNumber(payload.position) then
			nowPlaying.elapsed = math.clamp(payload.position, 0, nowPlaying.duration)
		end
		pcall(function()
			local audio = ControllerFunctions.getAudioSnapshot()
			if audio.ready and ControllerFunctions.isFiniteNumber(payload.position) then ControllerFunctions.seekAudio(nowPlaying.elapsed) end
			if playbackPaused then ControllerFunctions.pauseAudio() else ControllerFunctions.resumeAudio() end
		end)
	elseif command == "Restart" then
		ControllerFunctions.cancelAudioTransition("global-restart")
		nowPlaying.elapsed = 0
		playbackPaused = false
		ControllerFunctions.startServerMusic(nowPlaying.soundId)
	else
		return false
	end
	lastGlobalPlaybackRevision = revision
	return true
end

ControllerFunctions.handleGlobalMessage = function(message: any)
	if typeof(message) ~= "table" then return end
	if message.kind == "QueueChanged" and globalQueueMode then
		-- Coalesce bursts (for example, several automatic queue inserts) into one
		-- authoritative snapshot read. Observer servers only refresh their HUD mirror.
		if not globalQueueRefreshScheduled then
			globalQueueRefreshScheduled = true
			task.delay(0.2, function()
				-- MessagingService is only an invalidation hint. If a transient
				-- DataStore read fails, retry the read with short backoff instead
				-- of leaving this server's HUD mirror stale until the slow poll.
				local retryDelays = {0, 1, 3}
				for attempt, delaySeconds in ipairs(retryDelays) do
					if delaySeconds > 0 then task.wait(delaySeconds) end
					if not globalQueueMode or not syncGlobalQueueSnapshot then break end
					if syncGlobalQueueSnapshot() then break end
					if attempt == #retryDelays then
						warn("[ClubMusic] Global queue refresh remained unavailable after retry attempts; periodic reconciliation will retry.")
					end
				end
				globalQueueRefreshScheduled = false
			end)
		end
		return
	end
	if message.kind == "Catalog" then
		if os.clock() - lastCatalogRefreshAt < 3 then return end
		task.spawn(function()
			if globalQueueMode and syncGlobalQueueSnapshot then syncGlobalQueueSnapshot() end
			ControllerFunctions.refreshCatalogWhenReady()
		end)
		return
	end
	if message.kind == "XPBoost" and (message.multiplier == 1 or message.multiplier == 2 or message.multiplier == 4)
		and ControllerFunctions.isFiniteNumber(message.expiresAt) and message.expiresAt >= 0 then
		ControllerFunctions.setGlobalXPState(message.multiplier, message.expiresAt, message.lowerExpiresAt)
		publishState(nil)
		return
	end
	if message.kind == "Announcement" and ControllerFunctions.isValidString(message.text, 240) then
		ControllerFunctions.broadcast("[GLOBAL] " .. message.text, "info")
		return
	end
	if message.kind == "Moderation" and ControllerFunctions.isFiniteNumber(message.userId)
		and message.userId > 0 and message.userId % 1 == 0 and message.userId <= 9007199254740991 then
		local target = Players:GetPlayerByUserId(message.userId)
		if message.field == "globalBan" and message.value == true then
			if target then target:Kick("You are globally banned from this experience.") end
		elseif message.field == "requestBlocked" and typeof(message.value) == "boolean" then
			if message.value then
				blockedUsers[message.userId] = true
				ControllerFunctions.purgeUserEntries(message.userId)
			else
				blockedUsers[message.userId] = nil
			end
			publishState(nil)
		end
		return
	end
	if message.kind == "DJ" and typeof(message.command) == "string"
		and (message.command == "Skip" or message.command == "ClearQueue" or message.command == "SetRequestLock"
			or message.command == "SetPlaybackPaused" or message.command == "Restart") then
		-- MessagingService may echo a command to its originating server. The local
		-- action has already been applied there, so ignore that echo to avoid double skips.
		if message.senderJob == game.JobId then return end
		if message.command == "Skip" then
			ControllerFunctions.advance()
			ControllerFunctions.broadcast("A global DJ command skipped the current track.", "info")
		elseif message.command == "ClearQueue" then
			queueManager:Clear(true)
			ControllerFunctions.topUpAuto()
			ControllerFunctions.broadcast("The request queue was globally cleared.", "info")
		elseif message.command == "SetRequestLock" and typeof(message.payload) == "table"
			and typeof(message.payload.locked) == "boolean" then
			local changed = requestsLocked ~= message.payload.locked
			requestsLocked = message.payload.locked
			if changed then
				ControllerFunctions.broadcast(if requestsLocked then "Song requests are globally locked." else "Song requests are globally open.", "info")
			end
		elseif message.command == "SetPlaybackPaused" or message.command == "Restart" then
			if ControllerFunctions.applyGlobalPlaybackControl(message.command, message.payload) then
				if message.command == "SetPlaybackPaused" then
					ControllerFunctions.broadcast(if playbackPaused then "Music was paused globally." else "Music was resumed globally.", "info")
				else
					ControllerFunctions.broadcast("The current track was restarted globally.", "info")
				end
			end
		end
		publishState(nil)
	end
end

local connectedGlobalEvents: {[any]: any} = {}

-- Store late-lifecycle callbacks on the existing connection registry instead of
-- allocating more top-level locals. The controller chunk is close to Luau's
-- 200-local register ceiling, and these callbacks only need script-lifetime state.
connectedGlobalEvents.attachGlobalEvent = function(eventObject: Instance?)
	if eventObject and eventObject:IsA("BindableEvent") then
		local event = eventObject :: BindableEvent
		-- Connection ownership belongs to this Script's lifetime. A restarted
		-- controller receives a fresh table and can reconnect to this persistent event.
		if connectedGlobalEvents[event] then return end
		connectedGlobalEvents[event] = true
		event.Event:Connect(ControllerFunctions.handleGlobalMessage)
	end
end

connectedGlobalEvents.watchGlobalApi = function(folder: Instance)
	if not folder:IsA("Folder") then return end
	connectedGlobalEvents.attachGlobalEvent(folder:FindFirstChild("GlobalEvent"))
	folder.ChildAdded:Connect(function(child)
		if child.Name == "GlobalEvent" then connectedGlobalEvents.attachGlobalEvent(child) end
	end)
end

connectedGlobalEvents.attachGlobalEvent(globalEventObject)
if globalApi and globalApi:IsA("Folder") then connectedGlobalEvents.watchGlobalApi(globalApi) end
ServerStorage.ChildAdded:Connect(function(child)
	if child.Name == "ClubMusicGlobalAPI" and child:IsA("Folder") then connectedGlobalEvents.watchGlobalApi(child) end
end)

-- MessagingService invalidations are best-effort. A low-frequency, jittered
-- reconciliation repairs missed messages without making the catalog a hot DataStore path.
task.spawn(function()
	while script.Parent do
		task.wait(180 + math.random(0, 30))
		if catalogStorageReady and os.clock() - lastCatalogRefreshAt >= 150 then
			refreshLocalCatalog()
		end
	end
end)

ControllerFunctions.settlePlayerXP = function(player: Player, nowClock: number): boolean
	local userId = player.UserId
	local profile = profiles[userId]
	local lastClock = xpLastAwardAt[userId]
	if not profile then return false end
	if not lastClock then xpLastAwardAt[userId] = nowClock; return false end
	local elapsed = math.max(0, nowClock - lastClock)
	xpLastAwardAt[userId] = nowClock
	if elapsed <= 0 then return false end
	local boostedFourSeconds = 0
	local boostedTwoSeconds = 0
	if cachedGlobalXpMultiplier == 4 and cachedGlobalXpExpiresAt > 0 then
		local fourExpiryClock = nowClock + (cachedGlobalXpExpiresAt - os.time())
		boostedFourSeconds = math.clamp(fourExpiryClock - lastClock, 0, elapsed)
		if cachedGlobalXpLowerExpiresAt > cachedGlobalXpExpiresAt then
			local twoExpiryClock = nowClock + (cachedGlobalXpLowerExpiresAt - os.time())
			boostedTwoSeconds = math.clamp(twoExpiryClock - math.max(lastClock, fourExpiryClock), 0, elapsed - boostedFourSeconds)
		end
	elseif cachedGlobalXpMultiplier == 2 and cachedGlobalXpExpiresAt > 0 then
		local twoExpiryClock = nowClock + (cachedGlobalXpExpiresAt - os.time())
		boostedTwoSeconds = math.clamp(twoExpiryClock - lastClock, 0, elapsed)
	end
	local weightedSeconds = elapsed + boostedFourSeconds * 3 + boostedTwoSeconds
	local fractional = (xpFractional[userId] or 0) + weightedSeconds * (CONFIG.XPPerMinute / 60)
	local gain = math.floor(fractional + 1e-7)
	xpFractional[userId] = fractional - gain
	if gain <= 0 then return false end
	profile.xp = math.min(9007199254740000, profile.xp + gain)
	player:SetAttribute("XP", profile.xp)
	player:SetAttribute("Level", math.floor(profile.xp / CONFIG.XPPerLevel) + 1)
	player:SetAttribute("XPToNextLevel", CONFIG.XPPerLevel - (profile.xp % CONFIG.XPPerLevel))
	local lastSavedAt = xpLastSaveAt[userId] or nowClock
	if nowClock - lastSavedAt >= 60 then
		xpLastSaveAt[userId] = nowClock
		ControllerFunctions.scheduleProfileSave(player)
	end
	return true
end

settleAllXP = function()
	local nowClock = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do ControllerFunctions.settlePlayerXP(player, nowClock) end
end

task.spawn(function()
	ControllerFunctions.refreshGlobalXPBoost()
	while true do
		-- MessagingService is primary; staggered durable reads reconcile missed notifications.
		task.wait(45 + random:NextNumber(0, 15))
		ControllerFunctions.refreshGlobalXPBoost()
	end
end)

task.spawn(function()
	while true do
		task.wait(5)
		local nowClock = os.clock()
		local changed = xpStateDirty
		xpStateDirty = false
		for _, player in ipairs(Players:GetPlayers()) do
			if ControllerFunctions.settlePlayerXP(player, nowClock) then changed = true end
		end
		if changed then publishState(nil) end
	end
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(ControllerFunctions.onJoin, player)
end)

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	local djSessionManager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.DJSession
	if djSessionManager then
		local endedSession = djSessionManager:EndForDeparture(userId)
		if endedSession then player:SetAttribute("ClubMusicActiveDJSession", false) end
	end
	if settleAllXP then ControllerFunctions.settlePlayerXP(player, os.clock()) end
	xpLastAwardAt[userId] = nil
	xpFractional[userId] = nil
	xpLastSaveAt[userId] = nil
	local finalSaveOk = ControllerFunctions.saveProfile(player)
	if finalSaveOk then
		ControllerFunctions.releaseProfileSession(userId)
	else
		-- Keep the lease until it expires naturally. Clearing it after a failed
		-- save could let another server load stale profile data immediately.
		warn("[ClubMusic] Final profile save failed; retaining session lease until expiry for userId " .. tostring(userId))
	end
	local departingProfile = profiles[userId]
	for receiptId, pendingMemory in pairs(receiptMemoryPending) do
		if pendingMemory.profile == departingProfile then receiptMemoryPending[receiptId] = nil end
	end
	for receiptId, appliedProfile in pairs(receiptMemoryApplied) do
		if appliedProfile == departingProfile then receiptMemoryApplied[receiptId] = nil end
	end
	profiles[userId] = nil
	requestCounts[userId] = nil
	lastRequestAt[userId] = nil
	lastActionAt[userId] = nil
	lastAdminActionAt[userId] = nil
	lastActionByType[userId] = nil
	lastAdminActionByType[userId] = nil
	perPlayerActionBuckets[userId] = nil
	saveQueued[userId] = nil
	saveAgain[userId] = nil
	lastStateInvoke[userId] = nil
	lastCatalogInvoke[userId] = nil
	lastPlaylistInvoke[userId] = nil
	pendingStatePlayers[userId] = nil
	lastAudioInspection[userId] = nil
	lastReloadAt[userId] = nil
	reloadNonce[userId] = nil
	pendingAudio[userId] = nil
	rankCache[userId] = nil
	vipPass[userId] = nil
	vvipPass[userId] = nil
	sultanPass[userId] = nil
	tempVip[userId] = nil
	blockedUsers[userId] = nil
	local voteManager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.SkipVote
	if voteManager then
		voteManager:UpdateVoteOnPlayerLeave(userId)
	else
		skipVotes[userId] = nil
		-- The leaving player may still be counted by GetPlayers(); re-check next frame.
		task.defer(function()
			if ControllerFunctions.checkSkipVotes() then ControllerFunctions.broadcast("Track skipped by vote.", "ok") end
			publishState(nil)
		end)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(ControllerFunctions.onJoin, player)
end

-- Purchasing any pass mid-session refreshes server-verified tier ownership immediately.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	if not purchased then return end
	local recognized = passId == CONFIG.VipGamePassId
		or passId == CONFIG.VvipGamePassId
		or passId == CONFIG.TikiTideSultanPassId
	if not recognized then return end
	task.spawn(function()
		ControllerFunctions.refreshVip(player)
		ControllerFunctions.applyVipAttribute(player)
		ControllerFunctions.syncTitleTagUnlocks(player)
		local tierName = if ControllerFunctions.isSultan(player) then "Tiki Tide Sultan" elseif ControllerFunctions.isVvip(player) then "VVIP" elseif ControllerFunctions.isVip(player) then "VIP" else "Pass"
		notify(player, tierName .. " unlocked! Your perks are now active.", "ok")
		publishState(nil)
	end)
end)

-- Track time spent in this experience for the Party Animal collection unlock.
-- Progress is server-owned, persisted, and never accepted from a client.
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = profiles[player.UserId]
			if profile then
				local previousSeconds = profile.clubPlaySeconds
				profile.clubPlaySeconds = math.min(previousSeconds + 60, 9007199254740000)
				if math.floor(profile.clubPlaySeconds / 300) > math.floor(previousSeconds / 300) then
					ControllerFunctions.scheduleProfileSave(player)
				end
				if math.floor(profile.clubPlaySeconds / 3600) > math.floor(previousSeconds / 3600) then
					publishState(player)
				end
				ControllerFunctions.syncTitleTagUnlocks(player)
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(CONFIG.SaveIntervalSeconds)
		for _, player in ipairs(Players:GetPlayers()) do
			ControllerFunctions.saveProfile(player)
		end
	end
end)

-- Periodically re-check group rank / VIP so promotions apply without rejoining.
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				local previousRank = ControllerFunctions.getRank(player)
				local previousTier = ControllerFunctions.passTier(player)
				ControllerFunctions.refreshRank(player)
				ControllerFunctions.refreshVip(player)
				local profile = profiles[player.UserId]
				local slotsUpgraded = false
				if profile and ControllerFunctions.isStaff(player) and profile.unlockedSlots < TITLE_SLOT_COUNT then
					profile.unlockedSlots = TITLE_SLOT_COUNT
					ControllerFunctions.applyTitleAttributes(player, profile)
					ControllerFunctions.scheduleProfileSave(player)
					slotsUpgraded = true
				end
				ControllerFunctions.applyVipAttribute(player)
				player:SetAttribute("ClubRank", ControllerFunctions.getRank(player))
				ControllerFunctions.syncTitleTagUnlocks(player)
				-- Publish promotions/demotions even when the player already owns all
				-- title slots, so every client receives the current rank and tier.
				if slotsUpgraded or previousRank ~= ControllerFunctions.getRank(player) or previousTier ~= ControllerFunctions.passTier(player) then
					publishState(nil)
				end
			end)
		end
	end
end)

-- The server publishes authoritative elapsed time and current state. Clients interpolate between
-- resyncs. A single server-owned Sound replicates the active track to everyone; CONFIG.SoundIds
-- supplies optional built-in track audio, while staff-requested Creator Hub audio is validated
-- before it can enter the queue.
task.spawn(function()
	local ticks = 0
	while true do
		task.wait(1)
		if not playbackPaused then
			nowPlaying.elapsed += 1
		end
		ticks += 1

		local currentGeneration = playbackGeneration
		local shouldAdvance = not playbackPaused and nowPlaying.trackId ~= ""
			and nowPlaying.elapsed >= nowPlaying.duration
		-- Catalog tracks without a configured SoundId are intentionally silent
		-- UI/visualizer entries. Do not treat their non-playing Sound as a failed
		-- asset: let their catalog duration drive the normal transition instead.
		if not shouldAdvance and not playbackPaused and nowPlaying.trackId ~= ""
			and nowPlaying.soundId ~= "" and nowPlaying.elapsed >= 15 and not ControllerFunctions.getAudioSnapshot().playing then
			-- IsLoaded/TimeLength distinguishes a confirmed stopped/ended sound from
			-- an audio asset that is still buffering. If loading never completes,
			-- the 45-second ceiling prevents a permanently stuck track.
			local audio = ControllerFunctions.getAudioSnapshot()
			local loadedAndKnownLength = audio.ready and audio.length > 0
			shouldAdvance = loadedAndKnownLength or nowPlaying.elapsed >= 45
			if shouldAdvance then
				local playbackAdapter = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.Playback
				local quality = if playbackAdapter then playbackAdapter:InspectQuality() else nil
				local reason = if typeof(quality) == "table" then tostring(quality.state or "Unknown") else "WatchdogStoppedTrack"
				warn("[ClubMusic] Playback watchdog detected a stopped or unplayable track (" .. reason .. "); advancing safely.")
				if ControllerFunctions.ErrorHandler then
					ControllerFunctions.ErrorHandler.Report("PlaybackQuality", "StoppedTrack", reason, musicSound)
				end
			end
		end

		-- Each server prepares the same authoritative global queue head. At fade
		-- completion the queue service CAS commits that exact entry once; peers
		-- accept the same committed entry rather than advancing a second time.
		if not playbackPaused and nowPlaying.trackId ~= ""
			and nowPlaying.soundId ~= "" and nowPlaying.elapsed < nowPlaying.duration then
			local remaining = nowPlaying.duration - nowPlaying.elapsed
			if globalQueueMode and ControllerFunctions.globalPlaybackEndTime > 0 then
				remaining = math.max(0, ControllerFunctions.globalPlaybackEndTime - game:GetService("Workspace"):GetServerTimeNow())
			end
			local managers = ControllerFunctions.ChildManagers
			local crossfade = managers and managers.Crossfade
			local nextEntry = queue[1]
			local nextAsset = if typeof(nextEntry) == "table"
				then (nextEntry.soundId or CONFIG.SoundIds[nextEntry.trackId] or "") else ""
			local validNextAsset = typeof(nextAsset) == "string" and #nextAsset <= 64
				and string.match(nextAsset, "^rbxassetid://%d+$") ~= nil
			if crossfade and not crossfade.destroyed and not crossfade.active
				and crossfadeAttemptedGeneration ~= currentGeneration
				and remaining <= CONFIG.CrossfadePrepareLeadSeconds
				and remaining > (CONFIG.CrossfadeDurationSeconds + 1)
				and typeof(nextEntry) == "table" and validNextAsset
				and ControllerFunctions.getAudioSnapshot().playing == true then
				crossfadeAttemptedGeneration = currentGeneration
				pendingCrossfadeEntry = nextEntry
				pendingCrossfadeToken = audioTransitionTrackToken
				ControllerFunctions.pendingCrossfadeGlobalRevision = if globalQueueMode then globalTrackRevision else -1
				ControllerFunctions.pendingCrossfadeGlobalCommitted = false
				ControllerFunctions.pendingCrossfadeDeadline = if globalQueueMode then ControllerFunctions.globalPlaybackEndTime else 0
				local started, startError = ControllerFunctions.beginAudioCrossfade(nextAsset, CONFIG.CrossfadeDurationSeconds)
				if not started then
					pendingCrossfadeEntry = nil
					pendingCrossfadeToken = -1
					ControllerFunctions.pendingCrossfadeGlobalRevision = -1
					ControllerFunctions.pendingCrossfadeGlobalCommitted = false
					ControllerFunctions.pendingCrossfadeDeadline = 0
					warn("[ClubMusic][Crossfade] Automatic transition was not started; normal track advance remains available: " .. tostring(startError))
				end
			end
		end

		if shouldAdvance then
			local crossfade = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.Crossfade
			if crossfade and crossfade.active and pendingCrossfadeToken == audioTransitionTrackToken then
				-- Never race the in-flight deck commit with a second queue advance.
				-- The manager owns completion or cancellation; normal advance resumes
				-- on the next clock tick if preparation/fade/commit fails.
				shouldAdvance = false
			end
		end

		if shouldAdvance then
			if ControllerFunctions.advance(currentGeneration) then
				ticks = 0
				publishState(nil)
			end
		elseif ticks >= CONFIG.ResyncSeconds then
			ticks = 0
			publishState(nil)
		end
	end
end)

game:BindToClose(function()
	ControllerFunctions.destroyAudioCrossfadeManager("server-shutdown")
	-- Studio memory mode has no durable profile backend and never acquires a
	-- DataStore session lease. PlayerRemoving may already have cleared the
	-- in-memory profile while the player is still briefly returned by GetPlayers().
	-- There is therefore nothing to persist or release during Studio shutdown.
	if USE_STUDIO_MEMORY_PROFILES then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local finalSaveOk = ControllerFunctions.saveProfile(player)
		if finalSaveOk then
			ControllerFunctions.releaseProfileSession(player.UserId)
		else
			-- Do not clear a lease when the final snapshot was not persisted.
			warn("[ClubMusic] Shutdown save failed; retaining profile lease until expiry for userId " .. tostring(player.UserId))
		end
	end
end)
