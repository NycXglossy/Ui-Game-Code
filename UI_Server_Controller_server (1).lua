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
	GroupId = 500470662, -- Roblox group used for rank/group features.
	RankThresholds = { Owner = 255, CoOwner = 254, Admin = 200, Moderator = 150, GroupDJ = 100 },

	-- Extra staff without needing a group (treated as OWNER).
	StaffUserIds = {} :: {number},
	-- In Studio every player is treated as OWNER so you can test the DJ booth.
	-- Set to false to test the normal guest experience in Studio.
	StudioStaff = true,

	-- Paid Game Passes remain available alongside group VIP and owner-issued free rewards.
	-- Set each ID to its matching Roblox Game Pass before publishing; 0 disables that purchase tier.
	VipGamePassId = 2089785323,
	VvipGamePassId = 2089263330,
	TikiTidePassId = 2087955353,
	VipPriority = true,      -- VIP and higher membership tiers receive queue priority.

	MaxRequestsPerPlayer = 2,
	VipMaxRequestsPerPlayer = 4,
	VvipMaxRequestsPerPlayer = 6,
	TikiTideMaxRequestsPerPlayer = 8,
	RequestCooldownSeconds = 8,
	VipCooldownSeconds = 3,
	VvipCooldownSeconds = 2,
	TikiTideCooldownSeconds = 1,
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

	-- Modern AudioPlayer is the only main playback source; failures remain unavailable.
	UseModernAudioBackend = true,
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
	XPBoost2xProductId = 3731386650,
	XPBoost4xProductId = 3731387153,
	-- Permanent personal XP Game Passes; these do not replace global Developer Products.
	PersonalXP2xPassId = 2088891595,
	PersonalXP4xPassId = 2089053637,
	MountPassId = 2087955619,
	CompanionPassId = 2088585676,
	StageClubLightingPassId = 2088315619,
	GlobalDataStoreBurst = 30,
	GlobalDataStoreRefillPerSecond = 3,
	RestrictAudioToAllowlist = false,           -- true = only IDs listed below can be requested.
	AllowedAudioAssetIds = {} :: {number},

	-- Title slots: slot 1 is free, slots 2 and 3 are Developer Products. 0 = not configured.
	TitleSlotProductIds = { [2] = 3731392651, [3] = 3731394060 } :: {[number]: number},
	TitleSlotPrices = { [2] = 99, [3] = 199 } :: {[number]: number}, -- Display only; set to match the products.
}


-- Marketplace diagnostics: inspect configured paid IDs without blocking server startup.
-- This reports Roblox's catalog metadata; it does not alter purchases or receipts.
task.spawn(function()
	local configured = {
		{ label = "VIP Game Pass", id = CONFIG.VipGamePassId, infoType = Enum.InfoType.GamePass },
		{ label = "VVIP Game Pass", id = CONFIG.VvipGamePassId, infoType = Enum.InfoType.GamePass },
		{ label = "Tiki Tide Game Pass", id = CONFIG.TikiTidePassId, infoType = Enum.InfoType.GamePass },
		{ label = "2x Personal XP Game Pass", id = CONFIG.PersonalXP2xPassId, infoType = Enum.InfoType.GamePass },
		{ label = "4x Personal XP Game Pass", id = CONFIG.PersonalXP4xPassId, infoType = Enum.InfoType.GamePass },
		{ label = "Island Mount Game Pass", id = CONFIG.MountPassId, infoType = Enum.InfoType.GamePass },
		{ label = "Island Companion Game Pass", id = CONFIG.CompanionPassId, infoType = Enum.InfoType.GamePass },
		{ label = "Stage & Club Lighting Game Pass", id = CONFIG.StageClubLightingPassId, infoType = Enum.InfoType.GamePass },
		{ label = "2x XP Developer Product", id = CONFIG.XPBoost2xProductId, infoType = Enum.InfoType.Product },
		{ label = "4x XP Developer Product", id = CONFIG.XPBoost4xProductId, infoType = Enum.InfoType.Product },
		{ label = "Title Slot 2 Developer Product", id = CONFIG.TitleSlotProductIds[2], infoType = Enum.InfoType.Product },
		{ label = "Title Slot 3 Developer Product", id = CONFIG.TitleSlotProductIds[3], infoType = Enum.InfoType.Product },
		{ label = "Coconut Donation Developer Product", id = 3731488823, infoType = Enum.InfoType.Product },
		{ label = "Pineapple Donation Developer Product", id = 3731489572, infoType = Enum.InfoType.Product },
		{ label = "Tiki Torch Donation Developer Product", id = 3731490154, infoType = Enum.InfoType.Product },
		{ label = "Volcano Donation Developer Product", id = 3731490513, infoType = Enum.InfoType.Product },
		{ label = "Island Legend Donation Developer Product", id = 3731490937, infoType = Enum.InfoType.Product },
		{ label = "Island Royalty Donation Developer Product", id = 3731491257, infoType = Enum.InfoType.Product },
		{ label = "Sultan's Legacy Donation Developer Product", id = 3731491679, infoType = Enum.InfoType.Product },
	}
	for _, entry in ipairs(configured) do
		if typeof(entry.id) ~= "number" or entry.id <= 0 then
			warn(string.format("[ClubMusic][MarketplaceCheck] %s has an invalid/unconfigured ID.", entry.label))
			continue
		end
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(entry.id, entry.infoType)
		end)
		if not ok or typeof(info) ~= "table" then
			warn(string.format("[ClubMusic][MarketplaceCheck] LOOKUP_FAILED | %s | ID=%d | Error=%s",
				entry.label, entry.id, string.sub(tostring(info), 1, 220)))
			continue
		end
		local creator = if typeof(info.Creator) == "table" then info.Creator else {}
		local creatorType = tostring(creator.CreatorType or "unknown")
		local creatorId = tostring(creator.CreatorTargetId or creator.Id or "unknown")
		local saleStatus = if info.IsForSale == true then "ON_SALE" elseif info.IsForSale == false then "NOT_FOR_SALE" else "UNKNOWN"
		local price = tostring(info.PriceInRobux or info.Price or "not-returned")
		local name = tostring(info.Name or info.ProductName or "unnamed")
		print(string.format(
			"[ClubMusic][MarketplaceCheck] LOOKUP_OK | %s | ID=%d | Name=%s | CreatorType=%s | CreatorId=%s | Sale=%s | Price=%s | ExpectedGroup=%d",
			entry.label, entry.id, name, creatorType, creatorId, saleStatus, price, CONFIG.GroupId
		))
	end
end)

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

-- Bounded, server-local purchase telemetry. Client prompt outcomes are explicitly
-- marked as unverified telemetry; only ProcessReceipt entries are server-authoritative.
local purchaseDiagnosticRemote = ControllerFunctions.getOrCreate(remotes, "RemoteEvent", "PurchaseDiagnostic") :: RemoteEvent
local purchaseDiagnosticEntries: {any} = {}
local purchaseDiagnosticRate: {[number]: {windowAt: number, count: number}} = {}
local PURCHASE_DIAGNOSTIC_CAPACITY = 30
local purchaseDiagnosticStats = {
	totalEvents = 0, promptEvents = 0, receiptEvents = 0, receiptCallbacks = 0,
	granted = 0, pending = 0, failures = 0, duplicates = 0, lastOutcome = nil, lastAt = nil,
	lastSuccessAt = nil, lastPendingAt = nil, lastFailureAt = nil,
}
local moderationDiagnosticStats = {
	totalLookups = 0, joinLookups = 0, retryLookups = 0,
	successfulLookups = 0, failedLookups = 0, pendingChecks = 0,
	bannedResults = 0, blockedResults = 0, lastLookupAt = nil,
	lastSuccessAt = nil, lastFailureAt = nil,
}
local function recordModerationDiagnostic(source: string, succeeded: boolean, banned: boolean?, blocked: boolean?)
	moderationDiagnosticStats.totalLookups += 1
	if source == "Join" then moderationDiagnosticStats.joinLookups += 1
	else moderationDiagnosticStats.retryLookups += 1 end
	moderationDiagnosticStats.lastLookupAt = os.time()
	if succeeded then
		moderationDiagnosticStats.successfulLookups += 1
		moderationDiagnosticStats.lastSuccessAt = moderationDiagnosticStats.lastLookupAt
		if banned == true then moderationDiagnosticStats.bannedResults += 1 end
		if blocked == true then moderationDiagnosticStats.blockedResults += 1 end
	else
		moderationDiagnosticStats.failedLookups += 1
		moderationDiagnosticStats.pendingChecks += 1
		moderationDiagnosticStats.lastFailureAt = moderationDiagnosticStats.lastLookupAt
	end
end
local function recordPurchaseDiagnostic(source: string, userId: number, itemId: number, outcome: string, detail: string?)
	local now = os.time()
	purchaseDiagnosticStats.totalEvents += 1
	purchaseDiagnosticStats.lastOutcome = string.sub(outcome, 1, 48)
	purchaseDiagnosticStats.lastAt = now
	if source == "ServerReceipt" then
		purchaseDiagnosticStats.receiptEvents += 1
		if outcome == "ProcessReceiptReached" then purchaseDiagnosticStats.receiptCallbacks += 1 end
	else
		purchaseDiagnosticStats.promptEvents += 1
	end
	if outcome == "ReceiptGranted" then
		purchaseDiagnosticStats.granted += 1
		purchaseDiagnosticStats.lastSuccessAt = now
	elseif outcome == "AwaitingPlayerProfile" or outcome == "XPBoostActivationFailed"
		or outcome == "ReceiptPersistenceFailed" or outcome == "ReceiptConcurrentRetry"
		or outcome == "ReceiptConcurrencyCapacity" then
		purchaseDiagnosticStats.pending += 1
		purchaseDiagnosticStats.lastPendingAt = now
		if outcome == "XPBoostActivationFailed" or outcome == "ReceiptPersistenceFailed" then
			purchaseDiagnosticStats.failures += 1
			purchaseDiagnosticStats.lastFailureAt = now
		end
	elseif outcome == "RejectedUnregisteredProduct" or outcome == "MalformedReceipt"
		or outcome == "ReceiptHandlerFailed" or outcome == "ReceiptInvalidDecision" then
		purchaseDiagnosticStats.failures += 1
		purchaseDiagnosticStats.lastFailureAt = now
	elseif outcome == "ReceiptDuplicate" then
		purchaseDiagnosticStats.duplicates += 1
	end
	table.insert(purchaseDiagnosticEntries, {
		at = os.time(),
		source = source,
		userId = userId,
		itemId = itemId,
		outcome = string.sub(outcome, 1, 48),
		detail = string.sub(tostring(detail or ""), 1, 140),
	})
	while #purchaseDiagnosticEntries > PURCHASE_DIAGNOSTIC_CAPACITY do
		table.remove(purchaseDiagnosticEntries, 1)
	end
end

local function classifyConfiguredPurchaseId(promptType: string, itemId: number): string
	if promptType == "GamePass" then
		if itemId == CONFIG.VipGamePassId or itemId == CONFIG.VvipGamePassId or itemId == CONFIG.TikiTidePassId
			or itemId == CONFIG.PersonalXP2xPassId or itemId == CONFIG.PersonalXP4xPassId
			or itemId == CONFIG.MountPassId or itemId == CONFIG.CompanionPassId
			or itemId == CONFIG.StageClubLightingPassId then
			return "ConfiguredClubMusicGamePass"
		end
	elseif itemId == CONFIG.XPBoost2xProductId or itemId == CONFIG.XPBoost4xProductId
		or itemId == CONFIG.TitleSlotProductIds[2] or itemId == CONFIG.TitleSlotProductIds[3]
		or itemId == 3731488823 or itemId == 3731489572 or itemId == 3731490154
		or itemId == 3731490513 or itemId == 3731490937 or itemId == 3731491257
		or itemId == 3731491679 then
		return "ConfiguredClubMusicDeveloperProduct"
	end
	return "UnrecognizedByClubMusicConfig"
end

purchaseDiagnosticRemote.OnServerEvent:Connect(function(player: Player, promptType: any, itemId: any, eventKind: any, payload: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players
		or (promptType ~= "GamePass" and promptType ~= "DeveloperProduct")
		or typeof(itemId) ~= "number" or not (itemId > 0 and itemId <= 9007199254740991) or itemId % 1 ~= 0 then
		return
	end
	local isLegacyCallback = typeof(eventKind) == "boolean"
	local isPromptRequest = eventKind == "PromptRequested" and typeof(payload) == "string" and #payload <= 128
	local isPromptFinished = eventKind == "PromptFinished" and typeof(payload) == "boolean"
	if not isLegacyCallback and not isPromptRequest and not isPromptFinished then return end

	local now = os.clock()
	local rate = purchaseDiagnosticRate[player.UserId]
	if not rate or now - rate.windowAt >= 60 then
		rate = {windowAt = now, count = 0}
		purchaseDiagnosticRate[player.UserId] = rate
	end
	if rate.count >= 12 then return end
	rate.count += 1

	local idClass = classifyConfiguredPurchaseId(promptType, itemId)
	if isPromptRequest then
		recordPurchaseDiagnostic("ClientPromptRequestUnverified", player.UserId, itemId, "PromptRequested",
			promptType .. " | source=" .. string.sub(payload, 1, 48) .. " | " .. idClass .. "; request telemetry only")
	else
		local wasPurchased = if isLegacyCallback then eventKind else payload
		recordPurchaseDiagnostic("ClientPromptUnverified", player.UserId, itemId,
			if wasPurchased then "PromptReportedPurchased" else "PromptClosedWithoutPurchase",
			promptType .. " prompt callback | " .. idClass .. "; client telemetry is not proof of a completed transaction")
	end
end)
Players.PlayerRemoving:Connect(function(player: Player)
	purchaseDiagnosticRate[player.UserId] = nil
end)

local ServerStorage = game:GetService("ServerStorage")
-- Keep the established lowercase alias for existing storage-module loaders.
local serverStorage = ServerStorage


-- Resolve optional audio modules in either supported installation layout:
--   ServerStorage/ClubMusicAudioModules/<ModuleScript>
--   ServerStorage/<ModuleScript>
-- Folder layout takes precedence when both copies exist, avoiding accidental
-- mixing of two independently installed module sets.
ControllerFunctions.findAudioModule = function(moduleName: string): ModuleScript?
	if typeof(moduleName) ~= "string" or #moduleName < 1 or #moduleName > 100 then
		return nil
	end
	local modulesFolder = serverStorage:FindFirstChild("ClubMusicAudioModules")
	local candidate = if modulesFolder and modulesFolder:IsA("Folder")
		then modulesFolder:FindFirstChild(moduleName) else nil
	if candidate and candidate:IsA("ModuleScript") then
		return candidate
	end
	candidate = serverStorage:FindFirstChild(moduleName)
	if candidate and candidate:IsA("ModuleScript") then
		return candidate
	end
	return nil
end

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

-- Resolve canonical ServerStorage modules from either direct-child installation
-- or the bundled ClubMusic_ServerStorage_Modules folder.
ControllerFunctions.findServerStorageModule = function(moduleName: string): Instance?
	if typeof(moduleName) ~= "string" or #moduleName < 1 or #moduleName > 100 then return nil end
	local direct = serverStorage:FindFirstChild(moduleName)
	if direct then return direct end
	local packageFolder = serverStorage:FindFirstChild("ClubMusic_ServerStorage_Modules")
	if packageFolder and packageFolder:IsA("Folder") then
		local bundled = packageFolder:FindFirstChild(moduleName)
		if bundled then return bundled end
	end
	local waited = serverStorage:WaitForChild(moduleName, 20)
	if waited then return waited end
	if packageFolder and packageFolder:IsA("Folder") then
		return packageFolder:WaitForChild(moduleName, 2)
	end
	return nil
end

remotes:SetAttribute("StartupStage", "LoadingMusicCatalogService")
local catalogModule = ControllerFunctions.findServerStorageModule("MusicCatalogService")
remotes:SetAttribute("StartupStage", "LoadingMusicPlaylistService")
local playlistModule = ControllerFunctions.findServerStorageModule("MusicPlaylistService")
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
local validationModule = ControllerFunctions.findServerStorageModule("MusicValidationService")
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

type Track = { id: string, genreId: string, title: string, artist: string, duration: number, genre: string, assetId: number?, soundId: string?, artworkAssetId: number?, placeholder: boolean? }

local TRACK_BY_ID: {[string]: Track} = {}
local ALL_TRACK_IDS: {string} = {}

local function isPlayableTrack(track: Track?): boolean
	if not track or track.placeholder == true then return false end
	local soundId = track.soundId or CONFIG.SoundIds[track.id]
	return typeof(soundId) == "string" and soundId ~= ""
end

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

-- Main playback is owned exclusively by the modern AudioPlayer backend.
local activeAudioSource: any = { kind = "Unavailable" }
local audioSourceRevision = 0
local modernBackendStartSucceeded = false
local modernBackendStartFailureCount = 0
local modernAudioStartToken = 0
-- Forward-declared state is shared with the early-created crossfade factory.
local queue: any = {}
local queueManager: any = nil
-- Retired permanently: all request queues and playback transitions are server-local.
local enterLocalQueueBackup: ((string) -> ())? = nil
-- Display hints may lead the authoritative snapshot, but must never advance
-- queue ownership or the revision used by crossfade compare-and-swap.
local nowPlaying: any = nil
local refreshLocalCatalog: (() -> boolean)? = nil
local publishState: (Player?) -> () = function(_player: Player?) end
local pendingCrossfadeEntry: any = nil
local pendingCrossfadeToken = -1
local audioTransitionTrackToken = 0

-- legacy group migration and setup
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
	-- Publish the active output type. Unavailable means modern startup/recovery
	-- failed; no legacy source is selected.
	local sourceKind = if source.kind == "Backend" and source.backend then "AudioPlayer" else "Unavailable"
	SoundService:SetAttribute("ClubMusicAudioSourceKind", sourceKind)
	local signalInstance = if source.kind == "Backend" and source.backend then source.backend:GetPlayer() else nil
	if typeof(signalInstance) == "Instance" then
		local ok, signal = pcall(function() return signalInstance:GetPropertyChangedSignal("IsPlaying") end)
		if ok and signal then
			activeAudioPlayingConnection = signal:Connect(ControllerFunctions.refreshActiveMusicSoundCount)
		end
	end
	ControllerFunctions.refreshActiveMusicSoundCount()
end

local playbackPaused = false
local audioReloadInProgress = false
-- Prevent out-of-order persistence replies from an earlier pause/resume/restart
-- overwriting a newer local control action on the same track.
local playbackControlRequestId = 0

-- One controller-owned source contract: modern AudioPlayer or unavailable.
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
		local asset = read("GetAsset", "")
		if typeof(asset) ~= "string" then asset = "" end
		if asset == "" then
			local player = read("GetPlayer", nil)
			if player then pcall(function() asset = tostring(player.Asset) end) end
		end
		local function finiteNonNegative(value: any): number
			local numberValue = tonumber(value)
			if numberValue == nil or numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then return 0 end
			return math.max(0, numberValue)
		end
		return {
			kind = "AudioPlayer",
			ready = read("IsReady", false) == true,
			playing = read("IsPlaying", false) == true,
			paused = playbackPaused,
			position = finiteNonNegative(read("GetTimePosition", 0)),
			length = finiteNonNegative(read("GetTimeLength", 0)),
			asset = asset,
		}
	end
	return { kind = "Unavailable", ready = false, playing = false, paused = playbackPaused, position = 0, length = 0, asset = "" }
end
-- Per-track loudness trim for the 11 Club Exclusives. A 1.5 multiplier is a
-- first-pass +50% boost. It is applied before the fader so crossfade gain
-- remains independent of each player's private output preference.
local TRACK_VOLUME_TRIM_OVERRIDES: {[string]: number} = {
	["custom-100919684616729"] = 1.5, -- CROWN OF THE NIGHT
	["custom-99973341792058"] = 1.5, -- Midnight Lucid
	["custom-137104933242988"] = 1.5, -- Empire of Stone
	["custom-84266261446965"] = 1.5, -- Anvil_of_Ruin
	["custom-85420661204078"] = 1.5, -- Code in the Smoke
	["custom-134987433423089"] = 1.5, -- Rich Lifestyle
	["custom-92952858514774"] = 1.5, -- Metallic Chaos Within Magic Theory
	["custom-117388170134707"] = 1.5, -- Steel Collision
	["custom-86468432953052"] = 1.5, -- Fallen Star Blues
	["custom-126526272193872"] = 1.5, -- Winter Between Us
	["custom-96399574470852"] = 1.5, -- Terminal Frequency
}
local function getTrackVolumeTrim(trackId: string?): number
	if typeof(trackId) ~= "string" then return 1 end
	local configured = TRACK_VOLUME_TRIM_OVERRIDES[trackId]
	if not ControllerFunctions.isFiniteNumber(configured) or configured <= 0 then return 1 end
	-- AudioPlayer.Volume supports values above 1, but
	-- clamp the shared per-track trim to their documented 0..10 range.
	return math.clamp(configured, 0.01, 10)
end
ControllerFunctions.getTrackVolumeTrim = getTrackVolumeTrim

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
	return false, 0
end
ControllerFunctions.setAudioGain = function(value: number, sourceOverride: any?): boolean
	if not ControllerFunctions.isFiniteNumber(value) or value < 0 or value > 1 then return false end
	local source = sourceOverride or activeAudioSource
	if typeof(source) ~= "table" then return false end
	if source.kind == "Backend" and source.backend then
		local ok, result = pcall(function() return source.backend:SetGain(value) end)
		return ok and result ~= false
	end
	return false
end

-- Track-specific playback-rate corrections. CROWN OF THE NIGHT's uploaded
-- source is already time-stretched by 9% with pitch preserved, so Roblox must
-- play that asset at normal speed rather than applying another 1.09 multiplier.
local TRACK_PLAYBACK_SPEED_OVERRIDES: {[string]: number} = {
	["custom-100919684616729"] = 1.0,
}
ControllerFunctions.setAudioPlaybackSpeed = function(value: number): boolean
	if not ControllerFunctions.isFiniteNumber(value) or value < 0.5 or value > 2 then return false end
	local source = activeAudioSource
	if typeof(source) ~= "table" then return false end
	if source.kind == "Backend" and source.backend then
		local ok, result = pcall(function() return source.backend:SetPlaybackSpeed(value) end)
		return ok and result ~= false
	end
	return false
end
ControllerFunctions.applyTrackPlaybackSpeed = function(trackId: string): boolean
	local speed = TRACK_PLAYBACK_SPEED_OVERRIDES[trackId]
	if speed == nil then return true end
	return ControllerFunctions.setAudioPlaybackSpeed(speed)
end

-- A controller mutation must not invalidate the source/revision captured by
-- an in-flight crossfade. Cancel first so the coordinator restores the outgoing
-- gain while its ownership guard is still valid; refuse the mutation if that
-- restoration cannot be completed safely.
local function cancelCrossfadeBeforeAudioMutation(reason: string): boolean
	local managers = ControllerFunctions.ChildManagers
	local crossfade = managers and managers.Crossfade
	if not crossfade or (not crossfade.active and not crossfade.starting) then return true end
	if typeof(ControllerFunctions.cancelAudioTransition) ~= "function" then return false end
	return ControllerFunctions.cancelAudioTransition(reason) == true
end

ControllerFunctions.setAudioAsset = function(asset: string)
	if not cancelCrossfadeBeforeAudioMutation("set-audio-asset") then
		return false, "Active crossfade could not be safely cancelled before changing the audio asset."
	end
	audioSourceRevision += 1
	local source = activeAudioSource
	if source.kind == "Backend" then return source.backend:SetAsset(asset) end
	return false, "No active audio source is available."
end
ControllerFunctions.seekAudio = function(position: number)
	if audioReloadInProgress then return false, "Audio controls are temporarily locked while the current track reloads." end
	if not cancelCrossfadeBeforeAudioMutation("seek-audio") then
		return false, "Active crossfade could not be safely cancelled before seeking."
	end
	audioSourceRevision += 1
	local source = activeAudioSource
	if source.kind == "Backend" then return source.backend:Seek(position) end
	return false, "No active audio source is available."
end
ControllerFunctions.playAudio = function()
	if audioReloadInProgress then return false, "Audio controls are temporarily locked while the current track reloads." end
	if not cancelCrossfadeBeforeAudioMutation("play-audio") then
		return false, "Active crossfade could not be safely cancelled before playback restart."
	end
	audioSourceRevision += 1
	local source = activeAudioSource
	if source.kind == "Backend" then return source.backend:Play() end
	return false, "No active audio source is available."
end
ControllerFunctions.stopAudio = function()
	if not cancelCrossfadeBeforeAudioMutation("stop-audio") then
		return false, "Active crossfade could not be safely cancelled before stopping playback."
	end
	audioSourceRevision += 1
	local source = activeAudioSource
	if source.kind == "Backend" then return source.backend:Stop() end
	return true, nil
end
ControllerFunctions.pauseAudio = function()
	if audioReloadInProgress then return false, "Audio controls are temporarily locked while the current track reloads." end
	if not cancelCrossfadeBeforeAudioMutation("pause-audio") then
		return false, "Active crossfade could not be safely cancelled before pausing playback."
	end
	audioSourceRevision += 1
	local source = activeAudioSource
	if source.kind == "Backend" then return source.backend:Pause() end
	return false, "No active audio source is available."
end
ControllerFunctions.resumeAudio = function()
	if audioReloadInProgress then return false, "Audio controls are temporarily locked while the current track reloads." end
	if not cancelCrossfadeBeforeAudioMutation("resume-audio") then
		return false, "Active crossfade could not be safely cancelled before resuming playback."
	end
	audioSourceRevision += 1
	local source = activeAudioSource
	if source.kind == "Backend" then return source.backend:Resume() end
	return false, "No active audio source is available."
end

-- Keep failed backend retirements reachable and retry transient Destroy failures.
-- A backend may be retired only after controller ownership has moved elsewhere.
local retiredAudioBackends: {[any]: string} = {}
local function retireAudioBackend(backend: any, reason: string): boolean
	if typeof(backend) ~= "table" then return true end
	if retiredAudioBackends[backend] == "retrying" then return false end
	local ok, result, detail = pcall(function()
		return backend:Cleanup()
	end)
	if ok and result ~= false then
		retiredAudioBackends[backend] = nil
		return true
	end
	retiredAudioBackends[backend] = "retrying"
	warn("[ClubMusic][AudioBackend] Backend retirement failed (" .. reason .. "): " .. tostring(detail or result))
	task.spawn(function()
		for attempt = 1, 3 do
			task.wait(attempt)
			local retryOk, retryResult, retryDetail = pcall(function()
				return backend:Cleanup()
			end)
			if retryOk and retryResult ~= false then
				retiredAudioBackends[backend] = nil
				return
			end
			warn("[ClubMusic][AudioBackend] Backend cleanup retry " .. tostring(attempt)
				.. " failed (" .. reason .. "): " .. tostring(retryDetail or retryResult))
		end
		-- Keep the reference in the registry for diagnosis and a later retry.
		retiredAudioBackends[backend] = "pending"
	end)
	return false
end

-- Final teardown drain for controller-retired backends. Normal retirement uses
-- bounded asynchronous retries; shutdown waits for those attempts, then makes a
-- final bounded pass over entries explicitly marked pending.
local function drainRetiredAudioBackends(reason: string): boolean
	local deadline = os.clock() + 6.5
	while os.clock() < deadline do
		local retrying = false
		for _, status in pairs(retiredAudioBackends) do
			if status == "retrying" then retrying = true; break end
		end
		if not retrying then break end
		task.wait(0.1)
	end

	local allClean = true
	for backend, status in pairs(retiredAudioBackends) do
		if status == "pending" then
			retiredAudioBackends[backend] = "retrying"
			local cleaned = false
			for attempt = 1, 3 do
				if attempt > 1 then task.wait(attempt) end
				local ok, result, detail = pcall(function()
					return backend:Cleanup()
				end)
				if ok and result ~= false then
					retiredAudioBackends[backend] = nil
					cleaned = true
					break
				end
				warn("[ClubMusic][AudioBackend] Final cleanup retry " .. tostring(attempt)
					.. " failed (" .. reason .. "): " .. tostring(detail or result))
			end
			if not cleaned then
				retiredAudioBackends[backend] = "pending"
				allClean = false
			end
		elseif status == "retrying" then
			allClean = false
		end
	end
	return allClean
end

-- Initialize source telemetry/playing-count for the unavailable pre-track state.
ControllerFunctions.bindActiveAudioPlayingSignal()

-- One controller-owned cancellation seam for every dual-deck transition.
-- Pending queue metadata is invalidated even when the manager is absent or cleanup reports failure.
ControllerFunctions.cancelAudioTransition = function(reason: string?)
	local managers = ControllerFunctions.ChildManagers
	local crossfade = managers and managers.Crossfade
	local ok, result = true, true
	if crossfade then
		ok, result = pcall(function()
			return crossfade:Cancel(reason)
		end)
	end
	pendingCrossfadeEntry = nil
	pendingCrossfadeToken = -1
	if not ok or result == false then
		warn("[ClubMusic] Audio transition cancellation reported a failure (" .. tostring(reason or "unspecified") .. "): " .. tostring(result))
		return false
	end
	return true
end

-- A prepared incoming deck is a real playback resource, not just queue metadata.
-- Invalidate it immediately when its catalog/moderation identity is withdrawn;
-- waiting for OnCommit to notice a changed queue head would allow an obsolete
-- asset to become audible during the fade window.
ControllerFunctions.cancelPreparedCrossfadeForTrack = function(trackId: string, reason: string): boolean
	local prepared = pendingCrossfadeEntry
	if typeof(prepared) ~= "table" or prepared.trackId ~= trackId then return true end
	return ControllerFunctions.cancelAudioTransition(reason)
end

-- Destroy the optional coordinator explicitly during teardown. Cleanup invalidates
-- any waiting transition, destroys its incoming deck, and restores outgoing gain.
ControllerFunctions.destroyAudioCrossfadeManager = function(reason: string?): (boolean, string?)
	local managers = ControllerFunctions.ChildManagers
	local crossfade = managers and managers.Crossfade
	pendingCrossfadeEntry = nil
	pendingCrossfadeToken = -1
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
	local backendModule = ControllerFunctions.findAudioModule("ClubMusicAudioBackend")
	local crossfadeModule = ControllerFunctions.findAudioModule("ClubMusicAudioCrossfadeManager")
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
			local deck = BackendClass.new({ Name = "ClubMusicCrossfadeDeck", Parent = game:GetService("SoundService"), InitialGain = 0 })
			local setupOk, setupError = pcall(function()
				local incomingTrackId = if typeof(pendingCrossfadeEntry) == "table"
					then tostring(pendingCrossfadeEntry.trackId or "") else ""
				local player = deck:GetPlayer()
				if not player then error("Incoming AudioPlayer instance is unavailable.") end
				local trim = getTrackVolumeTrim(incomingTrackId)
				if ControllerFunctions.isFiniteNumber(trim) then player.Volume = math.clamp(trim, 0.01, 10) end
			end)
			if not setupOk then
				local cleanupOk, cleanupResult, cleanupError = pcall(function()
					return deck:Cleanup()
				end)
				if not cleanupOk or cleanupResult == false then
					warn("[ClubMusic][Crossfade] Partially configured incoming deck cleanup failed: "
						.. tostring(cleanupError or cleanupResult))
				end
				error("Incoming deck setup failed: " .. tostring(setupError))
			end
			return deck
		end,
		GetRemainingTime = function()
			if not nowPlaying then return 0 end
			return math.max(0, (tonumber(nowPlaying.duration) or 0) - (tonumber(nowPlaying.elapsed) or 0))
		end,
		GetOutgoingGain = function()
			if activeAudioSource.kind ~= "Backend" or not activeAudioSource.backend then
				error("Crossfade requires the modern AudioPlayer backend; no legacy Sound fallback is available.")
			end
			transitionOutgoing = activeAudioSource
			transitionRevision = audioSourceRevision
			local ok, value = ControllerFunctions.getAudioGain(transitionOutgoing)
			if not ok then error("Outgoing audio gain is unavailable.") end
			ControllerFunctions.crossfadeOutgoingBaseGain = value
			return value
		end,
		SetOutgoingGain = function(value: number)
			if not transitionOutgoing or transitionOutgoing.kind ~= "Backend" or not transitionOutgoing.backend
				or activeAudioSource ~= transitionOutgoing or audioSourceRevision ~= transitionRevision then return false end
			return ControllerFunctions.setAudioGain(value, transitionOutgoing)
		end,
		OnFailure = function(message: string)
			warn("[ClubMusic][Crossfade] Transition was cancelled safely: " .. tostring(message))
		end,
		OnSettled = function(_outcome: string)
			-- Do not retain a reference to the previous outgoing backend after
			-- commit, cancellation, or teardown; the active source owns it now.
			transitionOutgoing = nil
			transitionRevision = nil
			ControllerFunctions.crossfadeOutgoingBaseGain = nil
		end,
		OnCommit = function(incoming: any): boolean
			local outgoing = transitionOutgoing
			local entry = pendingCrossfadeEntry
			if not outgoing or outgoing.kind ~= "Backend" or not outgoing.backend
				or activeAudioSource ~= outgoing or audioSourceRevision ~= transitionRevision or playbackPaused
				or not entry or pendingCrossfadeToken ~= audioTransitionTrackToken then
				return false
			end
			local playerOk, player = pcall(function() return incoming:GetPlayer() end)
			if not playerOk or typeof(player) ~= "Instance" or not player:IsA("AudioPlayer")
				or not player.IsPlaying then return false end
			if queue[1] ~= entry then
				return false
			end


			-- Stop the outgoing source before changing ownership. If it cannot be
			-- stopped, leave the old source authoritative so Cancel can restore gain.
			local outgoingSnapshot = ControllerFunctions.getAudioSnapshot()
			local outgoingWasPlaying = typeof(outgoingSnapshot) == "table" and outgoingSnapshot.playing == true
			local outgoingPosition = if typeof(outgoingSnapshot) == "table"
				then math.max(0, tonumber(outgoingSnapshot.position) or 0) else 0
			local stopOk, stopResult = pcall(function()
				local stopped, stopError = outgoing.backend:Stop()
				if stopped == false then error(tostring(stopError or "Outgoing AudioPlayer did not stop.")) end
				return true
			end)
			if not stopOk or stopResult == false then
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
						outgoing.backend:Play(nil, outgoingPosition)
					end)
				end
				return false
			end

			-- Crossfade completion consumes the prepared entry from this server's queue.
			local popOk, popped = pcall(function()
				if not queueManager then return nil end
				return queueManager:PopNext()
			end)
			if not popOk or popped ~= entry then
				activeAudioSource = outgoing
				pcall(ControllerFunctions.bindActiveAudioPlayingSignal)
				if outgoingWasPlaying then
					pcall(function()
						outgoing.backend:Play(nil, outgoingPosition)
					end)
				end
				return false
			end
			audioSourceRevision += 1
			-- Ownership and queue consumption are now committed. Never surface a
			-- later bookkeeping error as a failed commit: manager cancellation would
			-- otherwise destroy the incoming deck that is already controller-active.
			local nowPlayingOk, nowPlayingError = pcall(function()
				ControllerFunctions.setNowPlaying(entry, true)
			end)
			if not nowPlayingOk then
				warn("[ClubMusic][Crossfade] Track metadata publication failed after audio ownership transfer: "
					.. tostring(nowPlayingError))
			end
			local deferOk, deferError = pcall(function()
				task.defer(function()
					local topUpOk, topUpError = pcall(ControllerFunctions.topUpAuto)
					if not topUpOk then
						warn("[ClubMusic][Crossfade] Automatic queue top-up failed: " .. tostring(topUpError))
					end
					local publishOk, publishError = pcall(publishState, nil)
					if not publishOk then
						warn("[ClubMusic][Crossfade] State publication failed: " .. tostring(publishError))
					end
				end)
			end)
			if not deferOk then
				warn("[ClubMusic][Crossfade] Deferred post-commit work could not be scheduled: " .. tostring(deferError))
			end
			if outgoing.backend ~= incoming then
				-- Ownership has transferred to the incoming deck; retire the previous
				-- backend through the controller registry so failed cleanup stays reachable.
				retireAudioBackend(outgoing.backend, "crossfade outgoing commit")
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
	if activeAudioSource.kind ~= "Backend" or not activeAudioSource.backend then
		return false, "Crossfade requires the modern AudioPlayer backend; normal track advance remains available while the backend is unavailable."
	end
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

-- Modern-only startup. If module loading, decoding, or playback verification
-- fails, leave the source unavailable and report the failure; never start legacy
-- AudioPlayer. A monotonically increasing token fences late decoder completions.
ControllerFunctions.startServerMusic = function(soundId: any)
	local retiredSource = activeAudioSource
	ControllerFunctions.stopServerMusic()
	-- New-track startup owns a fresh candidate. Mark the source unavailable while
	-- it loads, and retire the stopped previous backend so the controller never
	-- reports a stopped output as the active source.
	if retiredSource.kind == "Backend" and retiredSource.backend then
		retireAudioBackend(retiredSource.backend, "new track startup")
	end
	activeAudioSource = { kind = "Unavailable" }
	ControllerFunctions.bindActiveAudioPlayingSignal()
	modernAudioStartToken += 1
	local startToken = modernAudioStartToken
	local startRevision = audioSourceRevision
	if typeof(soundId) ~= "string" or #soundId > 64
		or not string.match(soundId, "^rbxassetid://%d+$") then
		ControllerFunctions.setAudioAsset("")
		return
	end

	local trackId = tostring(nowPlaying and nowPlaying.trackId or "")
	local trim = getTrackVolumeTrim(trackId)
	local playbackSpeed = TRACK_PLAYBACK_SPEED_OVERRIDES[trackId] or 1
	local wasPaused = playbackPaused == true

	local function isCurrentStart(): boolean
		return modernAudioStartToken == startToken
			and audioSourceRevision == startRevision
			and activeAudioSource.kind == "Unavailable"
			and tostring(nowPlaying and nowPlaying.soundId or "") == soundId
	end

	local function reportModernStartupFailure(reason: string?)
		if not isCurrentStart() then return end
		modernBackendStartFailureCount += 1
		warn("[ClubMusic][AudioBackend] Modern-only startup failed; no legacy fallback was started: "
			.. tostring(reason or "UseModernAudioBackend is disabled."))
	end

	if not CONFIG.UseModernAudioBackend then
		reportModernStartupFailure("UseModernAudioBackend is disabled.")
		return
	end

	task.spawn(function()
		local candidate: any = nil
		local function discardCandidate()
			if candidate then
				pcall(function() candidate:Stop() end)
				retireAudioBackend(candidate, "modern startup candidate discarded")
				candidate = nil
			end
		end
		local ok, failure = pcall(function()
			local backendModule = ControllerFunctions.findAudioModule("ClubMusicAudioBackend")
			if not backendModule or not backendModule:IsA("ModuleScript") then
				error("Modern backend ModuleScript is missing.")
			end
			local BackendClass = require(backendModule)
			if typeof(BackendClass) ~= "table" or typeof(BackendClass.new) ~= "function" then
				error("Modern backend module has an invalid constructor.")
			end
			candidate = BackendClass.new({
				Name = "ClubMusicMainAudioBackend",
				Parent = SoundService,
				Volume = math.clamp(trim, 0.01, 10),
				PlaybackSpeed = playbackSpeed,
				InitialGain = 0,
			})
			if typeof(candidate) ~= "table" then error("Modern backend could not be constructed.") end
			local assetOk, assetError = candidate:SetAsset(soundId)
			if assetOk ~= true then error(tostring(assetError or "Modern backend rejected the track asset.")) end

			local readyDeadline = os.clock() + 8
			local ready = false
			repeat
				if not isCurrentStart() then return "stale" end
				local readiness = candidate:GetReadinessSnapshot()
				ready = typeof(readiness) == "table"
					and readiness.ready == true
					and readiness.asset == soundId
					and ControllerFunctions.isFiniteNumber(readiness.length)
					and readiness.length > 0
				if not ready then task.wait(0.1) end
			until ready or os.clock() >= readyDeadline
			if not ready then error("Modern AudioPlayer decoder did not become ready within 8 seconds.") end

			local startPosition = math.max(0, tonumber(nowPlaying and nowPlaying.elapsed) or 0)
			local played, playError = candidate:Play(nil, startPosition)
			if played ~= true then error(tostring(playError or "Modern AudioPlayer failed to start.")) end
			local playDeadline = os.clock() + 2
			local playing = false
			repeat
				if not isCurrentStart() then return "stale" end
				playing = candidate:IsPlaying() == true
				if not playing then task.wait(0.05) end
			until playing or os.clock() >= playDeadline
			if not playing then error("Modern AudioPlayer did not enter the playing state.") end
			local finalReadiness = candidate:GetReadinessSnapshot()
			if typeof(finalReadiness) ~= "table" or finalReadiness.ready ~= true
				or finalReadiness.asset ~= soundId or finalReadiness.length <= 0 then
				error("Modern AudioPlayer readiness changed during startup.")
			end
			if wasPaused then
				local paused, pauseError = candidate:Pause()
				if paused ~= true then error(tostring(pauseError or "Modern AudioPlayer could not preserve pause state.")) end
			end
			if not isCurrentStart() then return "stale" end
			local gainOk, gainError = candidate:SetGain(1)
			if gainOk ~= true then error(tostring(gainError or "Modern AudioPlayer gain could not be enabled.")) end

			local previousSource = activeAudioSource
			activeAudioSource = { kind = "Backend", backend = candidate }
			candidate = nil
			ControllerFunctions.bindActiveAudioPlayingSignal()
			if previousSource.kind == "Backend" and previousSource.backend then
				retireAudioBackend(previousSource.backend, "modern startup source replacement")
			end
			modernBackendStartSucceeded = true
			modernBackendStartFailureCount = 0
			print("[ClubMusic][AudioBackend] Modern AudioPlayer started as the primary track source.")
		end)
		discardCandidate()
		if ok and failure == "stale" then
			-- Expected cancellation: never warn or invoke legacy recovery for an
			-- obsolete track. If only the same track's playhead/pause revision
			-- changed, retry with the latest controller state.
			if modernAudioStartToken == startToken
				and activeAudioSource.kind == "Unavailable"
				and tostring(nowPlaying and nowPlaying.soundId or "") == soundId
				and audioSourceRevision ~= startRevision then
				task.defer(ControllerFunctions.startServerMusic, soundId)
			end
		elseif not ok then
			-- A seek/pause or other controller action may legitimately revise the
			-- active backend while the candidate is loading. Retry the same current
			-- track with the latest playhead/pause state instead of falling silent.
			if modernAudioStartToken == startToken
				and activeAudioSource.kind == "Unavailable"
				and tostring(nowPlaying and nowPlaying.soundId or "") == soundId
				and audioSourceRevision ~= startRevision then
				task.defer(ControllerFunctions.startServerMusic, soundId)
			else
				reportModernStartupFailure(tostring(failure))
			end
		end
	end)
end

-- Restart the active source in place through the normalized controller contract.
-- Avoid reselecting the asset and reapplying track gain/speed on every restart.
ControllerFunctions.restartServerMusic = function(soundId: any): (boolean, string?)
	if typeof(soundId) ~= "string" or #soundId > 64
		or not string.match(soundId, "^rbxassetid://%d+$") then
		return false, "The current track has no valid audio asset."
	end
	-- Read only the two properties restart actually needs. A full snapshot also
	-- queries readiness, duration, and playhead, adding work to a latency-sensitive
	-- button path without changing the restart decision.
	local snapshotOk, snapshot = pcall(ControllerFunctions.getAudioSnapshot)
	if not snapshotOk or typeof(snapshot) ~= "table" or snapshot.kind == "Unavailable" then
		return false, "The current audio source state could not be read safely."
	end
	local sourceAsset = tostring(snapshot.asset or "")
	local sourcePlaying = snapshot.playing == true
	if sourceAsset ~= soundId then
		ControllerFunctions.startServerMusic(soundId)
		return true, nil
	end

	-- Reset the active playhead in place instead of Stop -> Seek -> Play.
	-- Stopping a loaded source can force the decoder to reinitialize and adds
	-- avoidable latency. If the source was paused/stopped, start it after seeking.
	local seekOk, seekResult, seekError = pcall(ControllerFunctions.seekAudio, 0)
	if not seekOk or seekResult == false then
		return false, tostring(seekError or seekResult or "The current audio source could not be reset.")
	end
	if sourcePlaying ~= true then
		local playOk, playResult, playError = pcall(ControllerFunctions.playAudio)
		if not playOk or playResult == false then
			return false, tostring(playError or playResult or "The current audio source could not be restarted.")
		end
	end
	return true, nil
end

-- Rebuild a failed modern deck without falling back to legacy Sound playback.
-- The queue and authoritative track clock remain untouched; only the audio graph
-- is replaced after the new AudioPlayer is loaded, positioned, and verified.
local function rebuildModernAudioBackend(source: any, asset: string, position: number,
	expectedTrackId: string, expectedTransitionToken: number): (boolean, string?)
	if typeof(source) ~= "table" or source.kind ~= "Backend" or typeof(source.backend) ~= "table" then
		return false, "Modern audio recovery requires the controller-owned AudioPlayer backend."
	end
	local expectedRevision = audioSourceRevision
	local wasPaused = playbackPaused == true
	local gainOk, outgoingGain = ControllerFunctions.getAudioGain(source)
	if not gainOk then
		return false, "The active AudioPlayer gain could not be read safely; keeping the current backend unchanged."
	end
	local backendModule = ControllerFunctions.findAudioModule("ClubMusicAudioBackend")
	if not backendModule or not backendModule:IsA("ModuleScript") then
		return false, "Modern audio recovery module is unavailable."
	end
	local requireOk, BackendClass = pcall(require, backendModule)
	if not requireOk or typeof(BackendClass) ~= "table" or typeof(BackendClass.new) ~= "function" then
		return false, "Modern audio recovery module could not be loaded."
	end
	local createOk, candidate = pcall(BackendClass.new, {
		Name = "ClubMusicMainAudioBackendRecovery",
		Parent = SoundService,
		Volume = getTrackVolumeTrim(expectedTrackId),
		InitialGain = 0,
	})
	if not createOk or typeof(candidate) ~= "table" then
		return false, "A replacement modern AudioPlayer graph could not be created."
	end
	local function abandon(message: string): (boolean, string?)
		pcall(function() candidate:Stop() end)
		retireAudioBackend(candidate, "modern recovery candidate abandoned")
		return false, message
	end
	local selected, selectError = candidate:SetAsset(asset)
	if selected ~= true then return abandon(tostring(selectError or "Replacement AudioPlayer rejected the current asset.")) end
	local speed = TRACK_PLAYBACK_SPEED_OVERRIDES[expectedTrackId] or 1
	local speedSet, speedError = candidate:SetPlaybackSpeed(speed)
	if speedSet ~= true then return abandon(tostring(speedError or "Replacement AudioPlayer rejected playback speed.")) end

	local deadline = os.clock() + 8
	local readiness = nil
	repeat
		task.wait(0.1)
		local readOk, state = pcall(function() return candidate:GetReadinessSnapshot() end)
		if readOk and typeof(state) == "table" and state.ready == true
			and state.asset == asset and ControllerFunctions.isFiniteNumber(state.length) and state.length > 0 then
			readiness = state
			break
		end
	until os.clock() >= deadline
	if not readiness then return abandon("Replacement AudioPlayer did not become ready within 8 seconds.") end

	local target = math.clamp(position, 0, math.max(0, readiness.length - 0.5))
	local seeked, seekError = candidate:Seek(target)
	if seeked ~= true then return abandon(tostring(seekError or "Replacement AudioPlayer could not restore the playhead.")) end
	if wasPaused then
		local paused, pauseError = candidate:Pause()
		if paused ~= true then return abandon(tostring(pauseError or "Replacement AudioPlayer could not preserve pause state.")) end
	else
		local started, startError = candidate:Play()
		if started ~= true then return abandon(tostring(startError or "Replacement AudioPlayer could not start.")) end
		local startDeadline = os.clock() + 2
		repeat
			task.wait(0.05)
		until candidate:IsPlaying() or os.clock() >= startDeadline
		if not candidate:IsPlaying() then return abandon("Replacement AudioPlayer did not enter the playing state.") end
	end
	-- Keep the replacement deck muted throughout every yielding preparation
	-- step. Revalidate ownership immediately before restoring audible gain; the
	-- gain setter is synchronous, so no stale candidate can become audible between
	-- this final compare and the controller ownership transfer.
	if activeAudioSource ~= source or audioSourceRevision ~= expectedRevision
		or tostring(nowPlaying.trackId or "") ~= expectedTrackId
		or audioTransitionTrackToken ~= expectedTransitionToken
		or playbackPaused ~= wasPaused then
		return abandon("Playback changed while modern audio recovery was preparing.")
	end

	local gainSet, gainError = candidate:SetGain(math.clamp(outgoingGain, 0, 1))
	if gainSet ~= true then return abandon(tostring(gainError or "Replacement AudioPlayer could not restore output gain.")) end

	activeAudioSource = { kind = "Backend", backend = candidate }
	ControllerFunctions.bindActiveAudioPlayingSignal()
	retireAudioBackend(source.backend, "watchdog backend recovery")
	print("[ClubMusic][AudioBackend] Recovered playback with a replacement modern AudioPlayer.")
	return true, nil
end

-- Recover the current server-local audio source without changing queue ownership,
-- track identity, or the authoritative playback clock. This is deliberately blocked
-- during a crossfade so a manual recovery cannot interrupt a deck handoff.
local function performReloadServerMusic(): (boolean, string?)
	local asset = nowPlaying.soundId or CONFIG.SoundIds[nowPlaying.trackId] or ""
	if typeof(asset) ~= "string" or #asset > 64
		or not string.match(asset, "^rbxassetid://%d+$") then
		return false, "There is no playable audio asset for the current track."
	end
	local managers = ControllerFunctions.ChildManagers
	local crossfade = managers and managers.Crossfade
	if crossfade and crossfade.active then
		return false, "Please wait for the current crossfade to finish before reloading audio."
	end

	local source = activeAudioSource
	local duration = math.max(1, tonumber(nowPlaying.duration) or 1)
	local expectedTrackId = tostring(nowPlaying.trackId or "")
	local expectedTransitionToken = audioTransitionTrackToken
	local expectedPaused = playbackPaused == true

	if source.kind ~= "Backend" or not source.backend then
		-- If startup previously failed, retry the current track through the same
		-- verified modern-only startup path. startServerMusic restores the
		-- controller's saved elapsed position and pause state; it never starts Sound.
		ControllerFunctions.startServerMusic(asset)
		local startupDeadline = os.clock() + 12
		repeat
			task.wait(0.1)
			if tostring(nowPlaying.trackId or "") ~= expectedTrackId
				or audioTransitionTrackToken ~= expectedTransitionToken
				or playbackPaused ~= expectedPaused then
				return false, "The current track changed during modern audio recovery."
			end
			local recoveredSource = activeAudioSource
			if recoveredSource.kind == "Backend" and recoveredSource.backend then
				local stateOk, recoveredSnapshot = pcall(ControllerFunctions.getAudioSnapshot)
				local restoredState = if expectedPaused
					then typeof(recoveredSnapshot) == "table" and recoveredSnapshot.paused == true
					else typeof(recoveredSnapshot) == "table" and recoveredSnapshot.playing == true
				if stateOk and restoredState and recoveredSnapshot.asset == asset then
					return true, nil
				end
			elseif recoveredSource.kind ~= "Unavailable" then
				return false, "The audio source changed unexpectedly during modern recovery."
			end
		until os.clock() >= startupDeadline
		return false, "Modern AudioPlayer could not be restarted; no legacy fallback was started."
	end

	local snapshot = ControllerFunctions.getAudioSnapshot()
	if typeof(snapshot) ~= "table" or snapshot.kind == "Unavailable" then
		return false, "The active modern AudioPlayer is unavailable."
	end
	local expectedSourceRevision = audioSourceRevision
	local position = if ControllerFunctions.isFiniteNumber(snapshot.position)
		then snapshot.position else math.max(0, tonumber(nowPlaying.elapsed) or 0)
	position = math.clamp(position, 0, math.max(0, duration - 0.5))

	if source.kind == "Backend" and source.backend then
		-- AudioPlayer reload must reselect the asset and wait for its decoder;
		-- Stop/Seek/Play on the same selection is not a reliable recovery.
		local reloadCallOk, reloaded, reloadError = pcall(function()
			return source.backend:Reload(position)
		end)
		if not reloadCallOk or reloaded ~= true then
			local recovered, recoveryError = rebuildModernAudioBackend(
				source, asset, position, expectedTrackId, expectedTransitionToken
			)
			if recovered then return true, nil end
			return false, tostring(recoveryError or reloadError or reloaded or "The modern audio decoder could not be recovered.")
		end
	else
		return false, "The active modern AudioPlayer does not support reload recovery."
	end

	-- Confirm actual playback and fence out a track change that occurred while
	-- the decoder was loading. Never report success for a stale source.
	local resumeDeadline = os.clock() + 3
	repeat
		task.wait(0.1)
		if activeAudioSource ~= source or audioSourceRevision ~= expectedSourceRevision
			or tostring(nowPlaying.trackId or "") ~= expectedTrackId
			or audioTransitionTrackToken ~= expectedTransitionToken or playbackPaused then
			return false, "The current track changed during reload; no stale playback state was committed."
		end
		local stateOk, current = pcall(ControllerFunctions.getAudioSnapshot)
		local restoredState = if playbackPaused
			then typeof(current) == "table" and current.paused == true
			else typeof(current) == "table" and current.playing == true
		if stateOk and restoredState and current.asset == asset then
			return true, nil
		end
	until os.clock() >= resumeDeadline
	return false, "The audio source did not resume after reloading. Please try again."
end

ControllerFunctions.reloadServerMusic = function(): (boolean, string?)
	if audioReloadInProgress then
		return false, "An audio reload is already in progress."
	end
	audioReloadInProgress = true
	local callOk, recovered, recoveryError = pcall(performReloadServerMusic)
	audioReloadInProgress = false
	if not callOk then
		return false, "Audio reload failed safely: " .. tostring(recovered)
	end
	return recovered == true, recoveryError
end
-- Optional cross-server service bridge. The UI remains functional if this separate
-- service is disabled or temporarily unavailable; the server's local security remains active.
remotes:SetAttribute("StartupStage", "LoadingReceiptHash")
local receiptSecurityCore = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
local receiptHashModule = receiptSecurityCore and receiptSecurityCore:FindFirstChild("ReceiptHash")
if not receiptHashModule or not receiptHashModule:IsA("ModuleScript") then
	remotes:SetAttribute("StartupError", "Missing ServerStorage.ClubMusicSecurityCore.ReceiptHash ModuleScript.")
	error("[ClubMusic] Security Core ReceiptHash module is required.")
end
local receiptHashOk, receiptHashResult = pcall(require, receiptHashModule)
if not receiptHashOk or typeof(receiptHashResult) ~= "table" or type(receiptHashResult.KeySuffix) ~= "function" then
	remotes:SetAttribute("StartupError", "Security Core ReceiptHash failed to load.")
	error("[ClubMusic] Security Core ReceiptHash failed to load: " .. tostring(receiptHashResult))
end
local ReceiptHash = receiptHashResult
local globalApi: Instance? = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
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
	-- Preserve every BindableFunction return value. Some contracts (notably
	-- GetModerationState) return more than three values, including revision data.
	local results = table.pack(pcall(function()
		return (fn :: BindableFunction):Invoke(table.unpack(args, 1, args.n))
	end))
	return table.unpack(results, 1, results.n)
end

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
	danceFloorLastRewardAt: number,
	titleTagUnlocksVersion: number,
	titleSlots: {[number]: TitleSlot},
	unlockedSlots: number,
	activeSlot: number,
	showCustomTitle: boolean,
	rewardedPassTier: number,
	glowsticks: number,
	skipTokens: number,
	neonTrail: boolean,
	favorites: {[string]: boolean},
	xp: number,
}

local profiles: {[number]: Profile} = {}
local receiptTransactions: any = nil
queue = {}
local ServerStorageForQueue = serverStorage
remotes:SetAttribute("StartupStage", "LoadingMusicQueueManager")

-- WaitForChild only searches direct children. Report both the direct-child inventory
-- and any nested matches so incorrect placement is distinguishable from absence.
local queueManagerModule = ControllerFunctions.findServerStorageModule("MusicQueueManager")
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
local autoQueueHold = false
-- Queue mutations have their own revision, independent of playback transitions.
-- This prevents delayed MessagingService snapshots from restoring an older queue.
-- Catalog revision fences every shared enqueue/advance against stale local caches.
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
-- A newly joined server must align its audio deck once the asset is ready,
-- even when that deck initially reports position 0 or is ahead of the snapshot.
local activePlaylistId: string? = nil
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
local pendingArtwork: {[number]: boolean} = {}
local artworkInspectionCount = 0
local lastActionByType: {[number]: {[string]: number}} = {}
-- Admin-addon commands use their own per-action cooldown namespace so recent
-- UI actions cannot reject a trusted command (and vice versa).
local lastAdminActionByType: {[number]: {[string]: number}} = {}
local lastStateInvoke: {[number]: number} = {}
local lastCatalogInvoke: {[number]: number} = {}
local lastAudioInspection: {[number]: number} = {}
local audioInspectionCount = 0
local profileWriteLocks: {[number]: any} = {}
local serverShuttingDown = false
local activeReceiptCallbacks = 0
local saveQueued: {[number]: boolean} = {}
local saveAgain: {[number]: boolean} = {}
local saveQueueTokens: {[number]: any} = {}
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
-- Read-only catalog browsing gets an isolated budget so GetState traffic or
-- temporary global security-service pressure cannot starve catalog visibility.
-- This does not authorize mutations; all writes still pass their security gates.
local globalCatalogQueryBucket = ControllerFunctions.newTokenBucket(30, 15)
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
	-- DataStore operations use a bounded per-server token bucket. Persistent
	-- storage remains server-owned; no MemoryStore call is required for budgeting.
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

local sanityValidationService: any = nil

local ACTION_COOLDOWNS: {[string]: number} = {
	RequestTrack = 0.5, RequestAudioAsset = CONFIG.AudioInspectionCooldownSeconds,
	ReloadSong = CONFIG.ReloadCooldownSeconds, ToggleFavorite = 0.2, VoteSkip = 0.5,
	CatalogAddAudio = 10, CatalogRemoveTrack = 2,
	PlaylistCreate = 2, PlaylistDelete = 1, PlaylistAddTrack = 0.5, PlaylistRemoveTrack = 0.5, PlaylistMoveTrack = 0.5,
	DJPlayPlaylist = 2, DJStopPlaylist = 1,
	DJMoveUp = 0.2, DJRemove = 0.2, DJSkip = 0.5, DJPause = 0.5, DJRestart = 1, DJClearQueue = 1, DJToggleLock = 1,
	ModBlockUser = 0.5, ModSetPassTier = 0.5, ModPurgeUser = 0.5,
	ClaimDailyReward = 1, EquipTitleTag = 0.5, BuyTitleTag = 1, SaveCustomTitle = CONFIG.SaveTitleCooldownSeconds,
	SaveTitleSlot = CONFIG.SaveTitleCooldownSeconds, SelectTitleSlot = 0.3,
	ClearTitleSlot = 0.5, SetTitleVisible = 0.3,
}

ControllerFunctions.isFiniteNumber = function(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Audio asset IDs are untrusted input. Prefer the shared finite-integer validator;
-- keep a strict local fallback for staged deployments without the module.
ControllerFunctions.isValidAudioAssetId = function(value: any): boolean
	if sanityValidationService then
		local ok, valid = pcall(sanityValidationService.IsInteger, value, 1, 9007199254740991)
		if ok then return valid == true end
	end
	return ControllerFunctions.isFiniteNumber(value)
		and value >= 1
		and value <= 9007199254740991
		and value % 1 == 0
end

ControllerFunctions.acquireProfileWriteLock = function(userId: number, timeoutSeconds: number?): any
	local startedAt = os.clock()
	local timeout = if typeof(timeoutSeconds) == "number"
		then math.clamp(timeoutSeconds, 0, CONFIG.ProfileWriteLockTimeoutSeconds)
		else CONFIG.ProfileWriteLockTimeoutSeconds
	while profileWriteLocks[userId] do
		if os.clock() - startedAt >= timeout then
			warn("[ClubMusic] Timed out waiting for profile write lock for userId " .. tostring(userId))
			return nil
		end
		task.wait(0.05)
	end
	-- Each holder gets an identity token. A delayed completion may release only
	-- its own lock, never a newer writer's lock for a rapid same-server rejoin.
	local lockToken = {}
	profileWriteLocks[userId] = lockToken
	return lockToken
end

ControllerFunctions.releaseProfileWriteLock = function(userId: number, lockToken: any?)
	if lockToken == nil or profileWriteLocks[userId] == lockToken then
		profileWriteLocks[userId] = nil
	end
end

-- Session-only moderation / VIP / vote state.
-- All group-rank authorization and caching is owned by SecurityCore.Authorization.
local entitlementAuthority: any = nil
local blockedUsers: {[number]: boolean} = {}
local skipVotes: {[number]: boolean} = {}
local requestsLocked = false -- Emergency request lock only; DJ Control Mode is separate.
local djControlModeEnabled = false
local djControlModeUserId: number? = nil
local recentTracks: {string} = {}
local lastAutoGenre = ""

do
	local core = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("SanityValidation") else nil
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table"
			and type(exported.ValidateDataTree) == "function"
			and type(exported.IsLivePlayer) == "function" then
			sanityValidationService = exported
		end
	end
	if not sanityValidationService then
		warn("[ClubMusic][SanityValidation] Shared validator unavailable; bounded local remote validation remains active.")
	end
end

ControllerFunctions.isLiveRemotePlayer = function(player: any): boolean
	if sanityValidationService then
		local ok, valid = pcall(sanityValidationService.IsLivePlayer, player)
		return ok and valid == true
	end
	return typeof(player) == "Instance" and player:IsA("Player")
		and player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local authorizationService: any = nil
do
	local core = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("Authorization") else nil
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.GetShared) == "function" then
			local sharedOk, instance = pcall(exported.GetShared, {
				groupId = CONFIG.GroupId,
				studioStaff = CONFIG.StudioStaff,
				staffUserIds = CONFIG.StaffUserIds,
				thresholds = {
					GroupDJ = CONFIG.RankThresholds.GroupDJ,
					Moderator = CONFIG.RankThresholds.Moderator,
					Admin = CONFIG.RankThresholds.Admin,
					CoOwner = CONFIG.RankThresholds.CoOwner,
					Owner = CONFIG.RankThresholds.Owner,
				},
			})
			if sharedOk and typeof(instance) == "table"
				and type(instance.GetRank) == "function"
				and type(instance.GetLevel) == "function"
				and type(instance.IsGroupMember) == "function"
				and type(instance.Refresh) == "function" then
				authorizationService = instance
			end
		end
	end
	if not authorizationService then
		warn("[ClubMusic][Authorization] SecurityCore Authorization is unavailable; rank-based privileges are fail-closed.")
	end
end

-- Phase 32 moderation services share the already initialized SecurityCore authority.
-- No client remote is created; the Kohl's Admin server bridge is the only staff entry point.
local phase32Services: any = nil
do
	local core = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("Phase32ServiceBundle") else nil
	if module and module:IsA("ModuleScript") and authorizationService then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new, {
				onNotify = function(target: Player, kind: string, message: string)
					if target.Parent == Players then
						noticeRemote:FireClient(target, {text = string.sub(message, 1, 180), kind = kind})
					end
				end,
				onAudit = function(event: {[string]: any})
					local replay = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
					if replay and replay:IsA("BindableFunction") then
						pcall(function()
							replay:Invoke("Record", "moderation_" .. tostring(event.kind),
								event.targetUserId, event.actorUserId, "Warning", "ModerationPunishment",
								{caseId = event.caseId, detail = event.detail})
						end)
					end
				end,
			})
			if createOk and typeof(instance) == "table"
				and type(instance.Issue) == "function"
				and type(instance.Unban) == "function"
				and type(instance.GetHistory) == "function"
				and type(instance.GetRiskSignals) == "function"
				and type(instance.RevokeRestrictions) == "function"
				and type(instance.RecordVerifiedViolation) == "function"
				and type(instance.IsRestricted) == "function" then
				phase32Services = instance
			else
				warn("[ClubMusic][Phase32] Service bundle failed validation; punishment actions are unavailable.")
			end
		else
			warn("[ClubMusic][Phase32] Service bundle could not be loaded; punishment actions are unavailable.")
		end
	else
		warn("[ClubMusic][Phase32] Module bundle or SecurityCore Authorization is unavailable; Phase 32 is not active.")
	end
end

-- Membership entitlement decisions are centralized separately from staff authorization.
-- This service reuses Authorization's group cache and keeps bounded, session-only pass results.
do
	local core = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("EntitlementAuthority") else nil
	if module and module:IsA("ModuleScript") and authorizationService then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new, {
				authorization = authorizationService,
				passIds = {
					vip = CONFIG.VipGamePassId,
					vvip = CONFIG.VvipGamePassId,
					tikiTide = CONFIG.TikiTidePassId,
				},
			})
			if createOk and typeof(instance) == "table"
				and type(instance.GetTier) == "function"
				and type(instance.Refresh) == "function"
				and type(instance.Clear) == "function" then
				entitlementAuthority = instance
			end
		end
	end
	if not entitlementAuthority then
		warn("[ClubMusic][Entitlements] EntitlementAuthority unavailable; paid/group membership access is fail-closed.")
	end
end

-- Detection-only avatar/accessory validation. It records bounded server observations
-- and never removes accessories or applies moderation actions.
local avatarAccessoryValidation: any = nil
do
	local core = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("AvatarAccessoryValidationService") else nil
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new, {
				onSignal = function(signal: string, subject: number, detail: string)
					local replay = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
					if replay and replay:IsA("BindableFunction") then
						pcall(function()
							replay:Invoke("Record", signal, subject, 0, "Warning", "AvatarAccessoryValidation", {})
						end)
					end
					local api = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
					local recorder = api and api:FindFirstChild("RecordGlobalSecuritySignal")
					if recorder and recorder:IsA("BindableFunction") then
						local recordOk, result = pcall(function()
							return recorder:Invoke(signal, subject)
						end)
						if recordOk and result == true then return end
					end
					warn("[Tiki Tide][AvatarValidation] " .. tostring(signal)
						.. " subject=" .. tostring(subject) .. " detail=" .. string.sub(tostring(detail), 1, 120))
				end,
			})
			if createOk and typeof(instance) == "table"
				and type(instance.Start) == "function"
				and type(instance.GetStatus) == "function"
				and type(instance.Stop) == "function" then
				avatarAccessoryValidation = instance
				local startOk, started = pcall(instance.Start, instance)
				if not startOk or started ~= true then
					warn("[Tiki Tide][AvatarValidation] Startup failed: " .. tostring(started))
					avatarAccessoryValidation = nil
				end
			end
		end
	end
	if not avatarAccessoryValidation then
		warn("[Tiki Tide][AvatarValidation] Detection service unavailable; avatar checks are not active.")
	end
end

script.Destroying:Connect(function()
	if avatarAccessoryValidation then
		pcall(avatarAccessoryValidation.Stop, avatarAccessoryValidation)
		avatarAccessoryValidation = nil
	end
end)

-- Server-observed animation inventory. This is bounded telemetry only: it does
-- not stop tracks, rewrite assets, or infer that an unfamiliar ID is malicious.
local animationIntegrityService: any = nil
local animationIntegrityStatus: BindableFunction? = nil
do
	local core = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("AnimationIntegrityService") else nil
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new, {
				onSignal = function(signal: string, subject: number, detail: string, metadata: {[string]: any})
					local severity = if string.find(signal, "_cap", 1, true) then "Warning" else "Info"
					local replay = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
					if replay and replay:IsA("BindableFunction") then
						pcall(function()
							replay:Invoke("Record", signal, subject, 0, severity, "AnimationIntegrity", metadata)
						end)
					end
				end,
			})
			if createOk and typeof(instance) == "table"
				and type(instance.Start) == "function"
				and type(instance.GetStatus) == "function"
				and type(instance.Stop) == "function" then
				animationIntegrityService = instance
				local startOk, started = pcall(instance.Start, instance)
				if not startOk or started ~= true then
					warn("[Tiki Tide][AnimationIntegrity] Startup failed: " .. tostring(started))
					animationIntegrityService = nil
				end
			end
		end
	end

	local existingStatus = ServerStorage:FindFirstChild("GetTikiTideAnimationIntegrityStatus")
	if existingStatus and existingStatus:IsA("BindableFunction") then
		animationIntegrityStatus = existingStatus
	elseif not existingStatus then
		animationIntegrityStatus = Instance.new("BindableFunction")
		animationIntegrityStatus.Name = "GetTikiTideAnimationIntegrityStatus"
		animationIntegrityStatus.Parent = ServerStorage
	else
		warn("[Tiki Tide][AnimationIntegrity] Status endpoint has the wrong class; status endpoint was not replaced.")
	end
	if animationIntegrityStatus then
		animationIntegrityStatus.OnInvoke = function()
			return if animationIntegrityService
				then animationIntegrityService:GetStatus()
				else {state = "Unavailable", mode = "DetectionOnly", automaticEnforcement = false}
		end
	end

	if not animationIntegrityService then
		warn("[Tiki Tide][AnimationIntegrity] Observer unavailable; animation telemetry is inactive.")
	end
end

script.Destroying:Connect(function()
	if animationIntegrityService then
		pcall(animationIntegrityService.Stop, animationIntegrityService)
		animationIntegrityService = nil
	end
	if animationIntegrityStatus then
		animationIntegrityStatus.OnInvoke = nil
		animationIntegrityStatus = nil
	end
end)

-- Rank names, levels and refreshes are projections of the single SecurityCore cache.
ControllerFunctions.computeRank = function(player: Player): (string, number)
	if not authorizationService then return "GUEST", 0 end
	return authorizationService:GetRank(player)
end

ControllerFunctions.refreshRank = function(player: Player): boolean
	if not authorizationService or player.Parent ~= Players then return false end
	local ok, refreshed = pcall(authorizationService.Refresh, authorizationService, player)
	return ok and refreshed == true
end

ControllerFunctions.getRank = function(player: Player): string
	if not authorizationService then return "GUEST" end
	local rank = authorizationService:GetRank(player)
	return rank
end

ControllerFunctions.getLevel = function(player: Player): number
	if not authorizationService then return 0 end
	return authorizationService:GetLevel(player)
end

ControllerFunctions.isStaff = function(player: Player): boolean
	return ControllerFunctions.getLevel(player) >= 1
end

ControllerFunctions.isAdmin = function(player: Player): boolean
	return ControllerFunctions.getLevel(player) >= 2
end

-- Elevated booth management remains Owner/Co-owner only.
ControllerFunctions.isDJBoothController = function(player: Player): boolean
	return ControllerFunctions.getLevel(player) >= 3
end

-- Rank-100+ DJs may enter limited Control Mode and operate playback controls.
-- This is deliberately separate from staff and elevated booth-management rights.
ControllerFunctions.canUseDJBooth = function(player: Player): boolean
	if not authorizationService or player.Parent ~= Players then return false end
	local ok, allowed = pcall(authorizationService.Check, authorizationService, player.UserId, "GlobalDJ")
	return ok and allowed == true
end

ControllerFunctions.passTier = function(player: Player): number
	local profile = profiles[player.UserId]
	local rewardedTier = if profile then math.clamp(profile.rewardedPassTier, 0, 3) else 0
	if entitlementAuthority then
		local ok, tier = pcall(entitlementAuthority.GetTier, entitlementAuthority, player, rewardedTier)
		if ok and typeof(tier) == "number" then return math.clamp(math.floor(tier), 0, 3) end
	end
	-- Preserve owner and profile-awarded access during a staged module outage;
	-- paid/group access is never reconstructed from client attributes.
	if ControllerFunctions.getLevel(player) >= 4 then return 3 end
	return rewardedTier
end

ControllerFunctions.isGroupMember = function(player: Player): boolean
	if not authorizationService or player.Parent ~= Players then return false end
	local ok, member = pcall(authorizationService.IsGroupMember, authorizationService, player)
	return ok and member == true
end

ControllerFunctions.isVip = function(player: Player): boolean
	return ControllerFunctions.passTier(player) >= 1
end

ControllerFunctions.isVvip = function(player: Player): boolean
	return ControllerFunctions.passTier(player) >= 2
end

ControllerFunctions.hasTikiTideAccess = function(player: Player): boolean
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
	player:SetAttribute("HasTikiTideAccess", ControllerFunctions.hasTikiTideAccess(player))
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

ControllerFunctions.refreshPersonalPasses = function(player: Player)
	if player.Parent ~= Players then return end
	local userId = player.UserId
	local ownsPersonal2x = ControllerFunctions.ownsGamePass(userId, CONFIG.PersonalXP2xPassId)
	if player.Parent ~= Players or player.UserId ~= userId then return end
	local ownsPersonal4x = ControllerFunctions.ownsGamePass(userId, CONFIG.PersonalXP4xPassId)
	if player.Parent ~= Players or player.UserId ~= userId then return end
	local ownsMount = ControllerFunctions.ownsGamePass(userId, CONFIG.MountPassId)
	if player.Parent ~= Players or player.UserId ~= userId then return end
	local ownsCompanion = ControllerFunctions.ownsGamePass(userId, CONFIG.CompanionPassId)
	if player.Parent ~= Players or player.UserId ~= userId then return end
	local ownsStageClubLighting = ControllerFunctions.ownsGamePass(userId, CONFIG.StageClubLightingPassId)
	if player.Parent ~= Players or player.UserId ~= userId then return end
	player:SetAttribute("HasPersonalXP2xPass", ownsPersonal2x)
	player:SetAttribute("HasPersonalXP4xPass", ownsPersonal4x)
	player:SetAttribute("HasIslandMountPass", ownsMount)
	player:SetAttribute("HasIslandCompanionPass", ownsCompanion)
	player:SetAttribute("HasStageClubLightingPass", ownsStageClubLighting)
	player:SetAttribute("PersonalXPMultiplier", if ownsPersonal4x then 4 elseif ownsPersonal2x then 2 else 1)
end

ControllerFunctions.refreshVip = function(player: Player, force: boolean?): boolean
	if not entitlementAuthority or player.Parent ~= Players then return false end
	local ok, refreshed = pcall(entitlementAuthority.Refresh, entitlementAuthority, player, force == true)
	if not ok then
		warn("[ClubMusic][Entitlements] Membership refresh failed; previous verified pass state is retained where available.")
		return false
	end
	return refreshed == true
end

ControllerFunctions.requestLimitFor = function(player: Player): number
	local tier = ControllerFunctions.passTier(player)
	if tier >= 3 then return CONFIG.TikiTideMaxRequestsPerPlayer end
	if tier == 2 then return CONFIG.VvipMaxRequestsPerPlayer end
	if tier == 1 then return CONFIG.VipMaxRequestsPerPlayer end
	return CONFIG.MaxRequestsPerPlayer
end

ControllerFunctions.cooldownFor = function(player: Player): number
	local tier = ControllerFunctions.passTier(player)
	if tier >= 3 then return CONFIG.TikiTideCooldownSeconds end
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

-- Per-session cache of text that has passed Roblox broadcast filtering.
-- Profile text is preserved if TextService is temporarily unavailable, but is never
-- replicated until the current value has been filtered successfully.
local filteredTitleTextByUserId: {[number]: {[number]: string}} = {}
local lastCustomTitleTextAt: {[number]: number} = {}
local CUSTOM_TITLE_TEXT_COOLDOWN_SECONDS = 60

-- Mirrors the active slot onto player attributes for the overhead title script.
-- Legacy attributes (CustomTitle/TitleColor/TitleStyle/ShowCustomTitle) are kept up to date as well.
ControllerFunctions.applyTitleAttributes = function(player: Player, profile: Profile)
	local slot = profile.titleSlots[profile.activeSlot]
	local safeTexts = filteredTitleTextByUserId[player.UserId]
	local safeText = if safeTexts then safeTexts[profile.activeSlot] else nil
	-- Replicate the equipped collection tag on join as well as after equip actions.
	-- The overhead renderer consumes this cosmetic attribute; ownership remains server-authoritative.
	player:SetAttribute("EquippedTag", if typeof(profile.equippedTag) == "string" then profile.equippedTag else "")
	player:SetAttribute("TitleSlotsUnlocked", profile.unlockedSlots)
	player:SetAttribute("TitleSlot", profile.activeSlot)
	player:SetAttribute("ShowCustomTitle", profile.showCustomTitle)
	if slot == nil or typeof(safeText) ~= "string" or safeText == "" then
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
	player:SetAttribute("CustomTitle", safeText)
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
	if typeof(rawText) ~= "string" or #rawText > 256 then return nil end
	local trimmed = string.match(rawText, "^%s*(.-)%s*$") or ""
	if trimmed == "" then return "" end
	local characterLength = utf8.len(trimmed)
	if not characterLength or characterLength > MAX_CUSTOM_TITLE_LENGTH then return nil end
	if phase32Services then
		local filterOk, filtered = phase32Services:FilterBroadcast(player, trimmed)
		if not filterOk or typeof(filtered) ~= "string" then return nil end
		return ControllerFunctions.truncateUtf8(filtered, MAX_CUSTOM_TITLE_LENGTH)
	end
	-- Compatibility fallback while the Phase 32 module bundle is not installed.
	-- Still fail closed and never display raw player text.
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(trimmed, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(result) ~= "string" then return nil end
	return ControllerFunctions.truncateUtf8(result, MAX_CUSTOM_TITLE_LENGTH)
end

-- Re-filter persisted titles before they can be selected or replicated. The cache
-- is session-local and keyed by slot; failed filtering leaves saved profile data
-- intact but keeps that title hidden until a later successful retry.
ControllerFunctions.ensureFilteredTitleSlot = function(player: Player, profile: Profile, slotNumber: number): boolean
	local slot = profile.titleSlots[slotNumber]
	if not slot then return false end
	local safeTexts = filteredTitleTextByUserId[player.UserId]
	if safeTexts and safeTexts[slotNumber] == slot.text then return true end
	local filtered = ControllerFunctions.filterTitleText(player, slot.text)
	if filtered == nil or filtered == "" then return false end
	if player.Parent ~= Players or profile.titleSlots[slotNumber] ~= slot then return false end
	slot.text = filtered
	if not safeTexts then
		safeTexts = {}
		filteredTitleTextByUserId[player.UserId] = safeTexts
	end
	safeTexts[slotNumber] = filtered
	return true
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
		danceFloorLastRewardAt = 0,
		titleTagUnlocksVersion = 2,
		titleSlots = {},
		unlockedSlots = 1,
		activeSlot = 1,
		showCustomTitle = true,
		rewardedPassTier = 0,
		glowsticks = 0,
		skipTokens = 0,
		neonTrail = false,
		favorites = {},
		xp = 0,
	}
end

ControllerFunctions.loadProfile = function(player: Player)
	local userId = player.UserId
	if player.Parent ~= Players then return false end
	local profile = ControllerFunctions.defaultProfile()
	local data = nil
	local ok = false
	local lastError = "Profile session is already active on another server."
	local function abandonDepartedLoad(): boolean
		filteredTitleTextByUserId[userId] = nil
		-- The join can finish its yielding DataStore/TextService work after
		-- PlayerRemoving has already run. Retain the lease until its normal expiry:
		-- SESSION_TOKEN is server-scoped, so an immediate same-server rejoin could
		-- otherwise acquire the same owner token and have this stale load clear it.
		return false
	end

	if USE_STUDIO_MEMORY_PROFILES then
		-- Studio test profile: keep all existing gameplay/profile features usable
		-- without attempting a DataStore request or requiring API access.
		data = {}
		ok = true
	else
		for attempt = 1, 5 do
			if player.Parent ~= Players or player.UserId ~= userId then return abandonDepartedLoad() end
			if not ControllerFunctions.waitForDataStoreBudget(20) then
				lastError = "Server DataStore request budget is busy."
				break
			end
			-- Serialize load-lock acquisition with local saves and receipt commits.
			-- SESSION_TOKEN is server-scoped, so a rapid same-server rejoin must not
			-- read the old snapshot while that Player's final/periodic write is active.
			local loadWriteLockToken = ControllerFunctions.acquireProfileWriteLock(userId)
			if not loadWriteLockToken then
				lastError = "Profile is busy with another local write."
				break
			end
			local invalidStoredRecord = false
			local callOk, result = pcall(function()
				return store:UpdateAsync(tostring(userId), function(oldData)
					if oldData ~= nil and typeof(oldData) ~= "table" then
						invalidStoredRecord = true
						return nil -- Never replace a corrupt/non-profile value with a default record.
					end
					local current = if typeof(oldData) == "table" then table.clone(oldData) else {}
					local lock = current.sessionLock
					if lock ~= nil then
						local expiresAt = if typeof(lock) == "table" then lock.expiresAt else nil
						if typeof(lock) ~= "table" or typeof(lock.owner) ~= "string" or lock.owner == ""
							or typeof(expiresAt) ~= "number" or expiresAt ~= expiresAt
							or expiresAt <= 0 or expiresAt >= math.huge then
							invalidStoredRecord = true
							return nil -- A malformed lease is ambiguous; fail closed.
						end
						if lock.owner ~= SESSION_TOKEN and expiresAt > os.time() then
							return nil -- Another live server owns this profile.
						end
					end
					current.sessionLock = { owner = SESSION_TOKEN, expiresAt = os.time() + SESSION_LOCK_SECONDS }
					return current
				end)
			end)
			ControllerFunctions.releaseProfileWriteLock(userId, loadWriteLockToken)
			if player.Parent ~= Players or player.UserId ~= userId then return abandonDepartedLoad() end
			if callOk and typeof(result) == "table" then
				data = result
				ok = true
				break
			end
			if invalidStoredRecord then
				lastError = "Stored profile or session lock is malformed; refusing to overwrite it."
			elseif not callOk then
				lastError = tostring(result)
			end
			if attempt < 5 then
				task.wait(2)
				if player.Parent ~= Players or player.UserId ~= userId then return abandonDepartedLoad() end
			end
		end
	end
	if not ok then
		warn("[ClubMusic] Profile load/lock failed for " .. player.Name .. ": " .. lastError .. ". Profile remains unavailable; refusing to save defaults.")
		return false
	end
	filteredTitleTextByUserId[userId] = {}
	if typeof(data) == "table" then
		profile.xp = math.clamp(math.floor(tonumber(data.xp) or 0), 0, 9007199254740000)
		profile.tickets = math.max(0, tonumber(data.tickets) or 0)
		profile.coins = math.max(0, tonumber(data.coins) or 0)
		profile.loginStreak = math.clamp(math.floor(tonumber(data.loginStreak) or 1), 1, 7)
		profile.lastClaimDay = math.max(0, math.floor(tonumber(data.lastClaimDay) or 0))
		profile.claimedToday = data.claimedToday == true
		profile.equippedTag = if typeof(data.equippedTag) == "string" and TAGS[data.equippedTag] == true then data.equippedTag else nil
		profile.showCustomTitle = data.showCustomTitle ~= false
		profile.rewardedPassTier = math.clamp(math.floor(tonumber(data.rewardedPassTier) or 0), 0, 3)
		profile.glowsticks = math.max(0, math.floor(tonumber(data.glowsticks) or 0))
		profile.skipTokens = math.max(0, math.floor(tonumber(data.skipTokens) or 0))
		profile.neonTrail = data.neonTrail == true
		profile.clubPlaySeconds = math.clamp(math.floor(tonumber(data.clubPlaySeconds) or 0), 0, 9007199254740000)
		local savedDanceFloorRewardAt = tonumber(data.danceFloorLastRewardAt)
		profile.danceFloorLastRewardAt = if ControllerFunctions.isFiniteNumber(savedDanceFloorRewardAt)
			then math.max(0, math.floor(savedDanceFloorRewardAt)) else 0
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
					filteredTitleTextByUserId[player.UserId][1] = filteredText
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
	if profile.titleSlots[profile.activeSlot] then
		-- Only the active title is filtered during join; other slots are filtered
		-- lazily when selected, avoiding up to three TextService calls per player.
		ControllerFunctions.ensureFilteredTitleSlot(player, profile, profile.activeSlot)
	end
	-- Text filtering can yield after the DataStore session lock was acquired.
	-- Do not publish a profile or player attributes for a departed join.
	if player.Parent ~= Players or player.UserId ~= userId then return abandonDepartedLoad() end

	local today = math.floor(os.time() / 86400)
	if profile.lastClaimDay < today then
		if profile.lastClaimDay > 0 and today - profile.lastClaimDay == 1 then
			profile.loginStreak = (profile.loginStreak % 7) + 1
		elseif profile.lastClaimDay == 0 or today - profile.lastClaimDay > 1 then
			profile.loginStreak = 1
		end
		profile.claimedToday = false
	end

	profiles[userId] = profile
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

local function buildProfileSnapshot(profile: any): {[string]: any}
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

	return {
		tickets = profile.tickets,
		coins = profile.coins,
		loginStreak = profile.loginStreak,
		lastClaimDay = profile.lastClaimDay,
		claimedToday = profile.claimedToday,
		equippedTag = profile.equippedTag,
		ownedTags = table.clone(profile.ownedTags),
		clubPlaySeconds = profile.clubPlaySeconds,
		danceFloorLastRewardAt = profile.danceFloorLastRewardAt,
		titleTagUnlocksVersion = profile.titleTagUnlocksVersion,
		titleSlots = slotsSnapshot,
		unlockedSlots = profile.unlockedSlots,
		activeSlot = profile.activeSlot,
		showCustomTitle = profile.showCustomTitle,
		rewardedPassTier = profile.rewardedPassTier,
		glowsticks = profile.glowsticks,
		skipTokens = profile.skipTokens,
		neonTrail = profile.neonTrail,
		favorites = table.clone(profile.favorites),
		xp = profile.xp,
	}
end

local function profileSnapshotsEqual(left: any, right: any): boolean
	if typeof(left) ~= "table" or typeof(right) ~= "table" then
		return left == right
	end
	for key, value in pairs(left) do
		if not profileSnapshotsEqual(value, right[key]) then return false end
	end
	for key in pairs(right) do
		if left[key] == nil then return false end
	end
	return true
end

ControllerFunctions.saveProfile = function(player: Player, lockTimeoutSeconds: number?, budgetTimeoutSeconds: number?)
	-- Studio memory mode intentionally has no durable backend. The in-memory
	-- profile remains authoritative for this test session; never call UpdateAsync.
	if USE_STUDIO_MEMORY_PROFILES then
		return profiles[player.UserId] ~= nil
	end

	local userId = player.UserId
	local profile = profiles[userId]
	if not profile then return false end
	local writeLockToken = ControllerFunctions.acquireProfileWriteLock(userId, lockTimeoutSeconds)
	if not writeLockToken then return false end
	profile = profiles[userId]
	if not profile then ControllerFunctions.releaseProfileWriteLock(userId, writeLockToken); return false end
	if not ControllerFunctions.waitForDataStoreBudget(budgetTimeoutSeconds or 8) then
		ControllerFunctions.releaseProfileWriteLock(userId, writeLockToken)
		warn("[ClubMusic] Profile save deferred: server DataStore budget is busy for userId " .. tostring(userId))
		return false
	end

	-- Capture a detached snapshot before the yielding UpdateAsync call.
	local snapshot = buildProfileSnapshot(profile)
	local ownershipLost = false
	local ok, result = pcall(function()
		return store:UpdateAsync(tostring(userId), function(oldData)
			if typeof(oldData) ~= "table" or typeof(oldData.sessionLock) ~= "table"
				or oldData.sessionLock.owner ~= SESSION_TOKEN then
				ownershipLost = true
				return nil -- This server no longer owns the profile; never overwrite another session.
			end
			local pendingReceiptId = if typeof(oldData.pendingReceipt) == "string" then oldData.pendingReceipt else nil
			local hasPendingReceiptMemory = if pendingReceiptId and receiptTransactions
				then receiptTransactions:HasPendingMemory(profile, pendingReceiptId) else false
			if hasPendingReceiptMemory then
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
			-- Start from the current durable record so fields introduced by an
			-- older/newer profile writer survive this controller's narrower schema.
			-- The validated in-memory snapshot remains authoritative for every field
			-- this controller owns; nested allowlisted collections are replaced below.
			local output = table.clone(oldData)
			for key, value in pairs(snapshot) do
				output[key] = value
			end
			output.ownedTags = table.clone(snapshot.ownedTags)
			output.favorites = table.clone(snapshot.favorites)
			output.receiptIds = preservedReceipts -- legacy entries only; new receipts use the sharded journal.
			output.pendingReceipt = preservedPendingReceipt
			output.sessionLock = { owner = SESSION_TOKEN, expiresAt = os.time() + SESSION_LOCK_SECONDS }
			return output
		end)
	end)
	-- Detect mutations that happened while UpdateAsync was yielding, including
	-- throttled reward/XP paths that do not enqueue on every individual change.
	local profileChangedDuringSave = profiles[userId] == profile
		and not profileSnapshotsEqual(buildProfileSnapshot(profile), snapshot)
	ControllerFunctions.releaseProfileWriteLock(userId, writeLockToken)
	if not ok or typeof(result) ~= "table" then
		warn("[ClubMusic] Profile save failed for " .. player.Name .. ": " .. tostring(result or "profile session ownership lost"))
		if ownershipLost and player.Parent == Players then
			-- A second server now owns this profile. Stop this session from continuing
			-- to mutate a stale in-memory copy that can no longer be saved safely.
			player:Kick("Your profile session moved to another server. Please rejoin.")
		end
		return false
	end
	if profileChangedDuringSave and player.Parent == Players and profiles[userId] == profile then
		ControllerFunctions.scheduleProfileSave(player)
	end
	return true
end

-- Collapse rapid profile mutations into one save. Queue identity prevents a
-- delayed callback from an old Player instance clearing a rejoin's new queue.
ControllerFunctions.scheduleProfileSave = function(player: Player)
	if serverShuttingDown then return end
	local userId = player.UserId
	local scheduledProfile = profiles[userId]
	if not scheduledProfile then return end
	if saveQueued[userId] then
		saveAgain[userId] = true
		return
	end
	local queueToken = {}
	saveQueueTokens[userId] = queueToken
	saveQueued[userId] = true
	task.delay(CONFIG.ProfileSaveQueueDelaySeconds, function()
		if saveQueueTokens[userId] ~= queueToken then return end
		if serverShuttingDown or player.Parent ~= Players or profiles[userId] ~= scheduledProfile then
			saveQueued[userId] = nil
			saveAgain[userId] = nil
			saveQueueTokens[userId] = nil
			return
		end
		ControllerFunctions.saveProfile(player)
		if saveQueueTokens[userId] ~= queueToken then return end
		saveQueued[userId] = nil
		saveQueueTokens[userId] = nil
		if saveAgain[userId] then
			saveAgain[userId] = nil
			if player.Parent == Players and profiles[userId] == scheduledProfile then
				ControllerFunctions.scheduleProfileSave(player)
			end
		end
	end)
end

-- Dance Floor rewards are server-observed and profile-backed. The map supplies
-- one or more BaseParts tagged TikiTideDanceFloorZone; without a valid tagged
-- zone the service remains fail-closed and grants nothing.
ControllerFunctions.startDanceFloorRewards = function()
	if ControllerFunctions.DanceFloorRewardsStarted == true then return end
	ControllerFunctions.DanceFloorRewardsStarted = true

	local CollectionService = game:GetService("CollectionService")
	local Workspace = game:GetService("Workspace")
	local ZONE_TAG = "TikiTideDanceFloorZone"
	local TICK_INTERVAL = 10
	local BASE_PAYOUT = 15
	local IDLE_CUTOFF_SECONDS = 180
	local SAVE_INTERVAL_SECONDS = 30
	local MAX_TAGGED_INSTANCES_TO_INSPECT = 64
	local MAX_ZONES = 16
	local MAX_ANIMATION_TRACKS_TO_INSPECT = 64
	local playerStates: {[number]: any} = {}
	local warnedMissingZone = false

	local function hasDanceFloorActivity(humanoid: Humanoid, moved: boolean): boolean
		if moved or humanoid.MoveDirection.Magnitude >= 0.05 then return true end
		local ok, tracks = pcall(function()
			return humanoid:GetPlayingAnimationTracks()
		end)
		if not ok or typeof(tracks) ~= "table" then return false end
		for index = 1, math.min(#tracks, MAX_ANIMATION_TRACKS_TO_INSPECT) do
			local track = tracks[index]
			if track and track.IsPlaying == true
				and track.Priority.Value >= Enum.AnimationPriority.Movement.Value then
				return true
			end
		end
		return false
	end

	local function isInsideDanceFloor(rootPart: BasePart, zones: {BasePart}): boolean
		for _, zone in ipairs(zones) do
			local halfSize = zone.Size * 0.5
			if halfSize.X > 0 and halfSize.Y > 0 and halfSize.Z > 0 then
				local relative = zone.CFrame:PointToObjectSpace(rootPart.Position)
				if math.abs(relative.X) <= halfSize.X
					and math.abs(relative.Z) <= halfSize.Z
					and math.abs(relative.Y) <= halfSize.Y + 10 then
					return true
				end
			end
		end
		return false
	end

	task.spawn(function()
		while script.Parent do
			task.wait(TICK_INTERVAL)
			local tagged = CollectionService:GetTagged(ZONE_TAG)
			local zones: {BasePart} = {}
			for index, instance in ipairs(tagged) do
				if index > MAX_TAGGED_INSTANCES_TO_INSPECT or #zones >= MAX_ZONES then break end
				if instance:IsA("BasePart") and instance:IsDescendantOf(Workspace) then
					table.insert(zones, instance)
				end
			end

			if #zones == 0 then
				if not warnedMissingZone then
					warnedMissingZone = true
					warn("[ClubMusic][DanceFloorRewards] No valid BasePart tagged TikiTideDanceFloorZone; rewards are disabled until the map zone is configured.")
				end
			else
				warnedMissingZone = false
			end

			local nowClock = os.clock()
			local nowUnix = os.time()
			for _, player in ipairs(Players:GetPlayers()) do
				local userId = player.UserId
				local character = player.Character
				local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
				local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
				if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
					local existing = playerStates[userId]
					if existing then
						existing.character = nil
						existing.lastPosition = nil
					end
					continue
				end

				local state = playerStates[userId]
				if not state or state.character ~= character then
					-- A respawn resets the position sample, not the AFK timer; repeatedly
					-- resetting characters must not keep an inactive player reward-eligible.
					state = {
						character = character,
						lastPosition = root.Position,
						lastActivityClock = if state then state.lastActivityClock else nowClock,
						lastSaveClock = if state then state.lastSaveClock else nowClock,
					}
					playerStates[userId] = state
				else
					local moved = if state.lastPosition
						then (root.Position - state.lastPosition).Magnitude >= 0.5 else false
					if hasDanceFloorActivity(humanoid, moved) then
						state.lastActivityClock = nowClock
					end
					state.lastPosition = root.Position
				end

				if #zones == 0 or nowClock - state.lastActivityClock > IDLE_CUTOFF_SECONDS
					or not isInsideDanceFloor(root, zones) then
					continue
				end

				local profile = profiles[userId]
				if not profile then continue end
				local lastRewardAt = profile.danceFloorLastRewardAt
				if not ControllerFunctions.isFiniteNumber(lastRewardAt) then lastRewardAt = 0 end
				if nowUnix - lastRewardAt < TICK_INTERVAL then continue end

				-- Membership is resolved through Security Core, not the replicated IsVIP attribute.
				local multiplier = if ControllerFunctions.passTier(player) >= 1 then 2 else 1
				local reward = BASE_PAYOUT * multiplier
				if not ControllerFunctions.isFiniteNumber(profile.coins)
					or profile.coins < 0 or profile.coins > 9007199254740000 - reward then
					continue
				end

				-- Balance and interval marker are included in the same existing profile
				-- snapshot. Once persisted, the timestamp prevents rapid duplicate grants across service restarts.
				profile.coins += reward
				profile.danceFloorLastRewardAt = nowUnix
				player:SetAttribute("Coins", profile.coins)
				if nowClock - state.lastSaveClock >= SAVE_INTERVAL_SECONDS then
					state.lastSaveClock = nowClock
					ControllerFunctions.scheduleProfileSave(player)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerStates[player.UserId] = nil
	end)
end

ControllerFunctions.recordDiagnosticPulse = function(name: string, detail: string, healthy: boolean?, metadata: {[string]: any}?)
	local ok, recorded = ControllerFunctions.globalInvoke("RecordLocalWatchdogPulse", name, detail, healthy, metadata)
	return ok and recorded == true
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

-- Queue order: Tiki Tide, VVIP, VIP, normal player requests, then auto tracks.
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

ControllerFunctions.isTrackBlocked = function(trackId: string): boolean
	if typeof(trackId) ~= "string" or #trackId < 1 or #trackId > 64
		or not string.match(trackId, "^[%w%-_]+$") then return true end

	local cache = ControllerFunctions.blockedTrackCache or {}
	ControllerFunctions.blockedTrackCache = cache
	local now = os.clock()
	local cached = cache[trackId]
	-- Moderation decisions are cached per server to avoid a DataStore read for
	-- every queue/catalog check. MessagingService updates this cache immediately.
	if typeof(cached) == "table" and typeof(cached.blocked) == "boolean"
		and typeof(cached.checkedAt) == "number" and now - cached.checkedAt < 300 then
		return cached.blocked
	end

	local callOk, blocked, lookupOk = ControllerFunctions.globalInvoke("IsTrackBlocked", trackId)
	if callOk and lookupOk == true and typeof(blocked) == "boolean" then
		cache[trackId] = {blocked = blocked, checkedAt = now}
		return blocked
	end

	-- Studio isolation intentionally permits local testing without the global
	-- moderation backend. In live servers, an unknown moderation decision fails
	-- closed; a previously cached block also remains effective during outages.
	if cached and cached.blocked == true then return true end
	return not RunService:IsStudio()
end

ControllerFunctions.pickAutoTrack = function(): Track?
	local queued: {[string]: boolean} = {}
	for _, entry in ipairs(queue) do queued[entry.trackId] = true end
	local recentSet: {[string]: boolean} = {}
	for _, id in ipairs(recentTracks) do recentSet[id] = true end

	local pool: {Track} = {}
	local preferred: {Track} = {}
	for _, id in ipairs(ALL_TRACK_IDS) do
		local track = TRACK_BY_ID[id]
		if isPlayableTrack(track) and not queued[id] and not recentSet[id] and id ~= nowPlaying.trackId
			and not ControllerFunctions.isTrackBlocked(id) then
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
	-- Never bypass recent-history exclusions when the preferred pool is empty.
	-- Waiting for the next authoritative refill is safer than replaying a
	-- recently heard track simply to keep the queue populated.
	return nil
end

ControllerFunctions.nextPlaylistTrack = function(): Track?
	if not activePlaylistId or #activePlaylistTracks == 0 then return nil end
	for _ = 1, #activePlaylistTracks do
		if activePlaylistCursor > #activePlaylistTracks then activePlaylistCursor = 1 end
		local track = activePlaylistTracks[activePlaylistCursor]
		activePlaylistCursor += 1
		if isPlayableTrack(TRACK_BY_ID[track.id]) and not ControllerFunctions.isTrackBlocked(track.id) then return TRACK_BY_ID[track.id] end
	end
	return nil
end

ControllerFunctions.topUpAuto = function()
	if autoQueueHold then
		ControllerFunctions.recordDiagnosticPulse("AutoDJ", "refill-held", true, {queueDepth = #queue})
		return
	end
-- Auto DJ refills only this server's queue.
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
			local autoTrack = ControllerFunctions.pickAutoTrack()
			if not autoTrack then warn("[ClubMusic] No playable catalog tracks are available; automatic queue refill paused."); break end
			entry = ControllerFunctions.makeEntry(autoTrack, "auto", nil)
		end
		queueManager:Insert(#queue + 1, entry)
	end
	local healthy = #queue >= CONFIG.AutoQueueTarget
	ControllerFunctions.recordDiagnosticPulse("AutoDJ",
		if healthy then "refill-complete" else "no-playable-catalog-tracks",
		healthy, {queueDepth = #queue, target = CONFIG.AutoQueueTarget})
	ControllerFunctions.recordDiagnosticPulse("Queue", "queue-refill-observed", true, {queueDepth = #queue})
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
			-- Rebuild the catalog-resolved view without changing the saved ID list.
			-- When the current song belongs to this rotation, continue after it rather
			-- than restarting at the first entry after a catalog/playlist refresh.
			local nextCursor = 1
			if nowPlaying.source == "playlist" then
				local currentIndex: number? = nil
				for index, track in ipairs(validTracks) do
					if track.id == nowPlaying.trackId then currentIndex = index; break end
				end
				if currentIndex then
					nextCursor = if currentIndex >= #validTracks then 1 else currentIndex + 1
				else
					-- The current track may have been removed remotely. Continue after
					-- its former position in the previous resolved rotation.
					local oldIndex: number? = nil
					for index, track in ipairs(activePlaylistTracks) do
						if track.id == nowPlaying.trackId then oldIndex = index; break end
					end
					if oldIndex then
						local foundNext = false
						for offset = 1, #activePlaylistTracks do
							if not foundNext then
								local oldTrack = activePlaylistTracks[((oldIndex + offset - 1) % #activePlaylistTracks) + 1]
								for index, track in ipairs(validTracks) do
									if track.id == oldTrack.id then
										nextCursor = index
										foundNext = true
										break
									end
								end
							end
						end
					end
				end
			end
			activePlaylistName = playlist.name
			activePlaylistTracks = validTracks
			activePlaylistCursor = nextCursor
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
ControllerFunctions.stoppedAudioGeneration = -1
ControllerFunctions.stoppedAudioSince = 0
ControllerFunctions.audioRecoveryAttemptedGeneration = -1

ControllerFunctions.setNowPlaying = function(entry: QueueEntry, preserveAudio: boolean?, suppressGlobalCommit: boolean?)
	if preserveAudio ~= true then ControllerFunctions.cancelAudioTransition("track-change") end
	playbackGeneration += 1
	audioTransitionTrackToken += 1
	pendingCrossfadeEntry = nil
	pendingCrossfadeToken = -1
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

	table.insert(recentTracks, entry.trackId)
	while #recentTracks > CONFIG.AutoAvoidRecent do
		table.remove(recentTracks, 1)
	end
	table.clear(skipVotes)
	if ControllerFunctions.publishPlaybackState then ControllerFunctions.publishPlaybackState() end
end

-- Queue state and playback transitions are owned by this server.


ControllerFunctions.advance = function(expectedGeneration: number?): (boolean, string?)
	-- Server-local queue only. Generation checks prevent the playback clock and
	-- watchdog from advancing the same track twice.
	if transitionInProgress then return false, "A track transition is already in progress." end
	if expectedGeneration ~= nil and expectedGeneration ~= playbackGeneration then
		return false, "The current track changed before the transition started."
	end
	ControllerFunctions.cancelAudioTransition("advance")
	transitionInProgress = true
	local ok, err = pcall(function()
		local nextEntry = queueManager:PopNext()
		if not nextEntry then
			local playlistTrack = ControllerFunctions.nextPlaylistTrack()
			local autoTrack = if playlistTrack then nil else ControllerFunctions.pickAutoTrack()
			if not playlistTrack and not autoTrack then
				error("No playable catalog tracks are available for the next transition.")
			end
			nextEntry = if playlistTrack
				then ControllerFunctions.makeEntry(playlistTrack, "playlist", nil)
				else ControllerFunctions.makeEntry(autoTrack :: Track, "auto", nil)
		end
		ControllerFunctions.setNowPlaying(nextEntry :: QueueEntry)
		ControllerFunctions.topUpAuto()
	end)
	transitionInProgress = false
	if not ok then
		warn("[ClubMusic] Local track transition failed: " .. tostring(err))
		return false, "The local track transition failed."
	end
	return true, nil
end

-- Boot: start with an auto-selected track and a visible auto queue.
local initialTrack = ControllerFunctions.pickAutoTrack()
if initialTrack then
	ControllerFunctions.setNowPlaying(ControllerFunctions.makeEntry(initialTrack, "auto", nil))
	ControllerFunctions.topUpAuto()
else
	warn("[ClubMusic] Startup held: the catalog contains no playable audio tracks.")
end

-- Each server runs its own local queue and playback clock.

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
		canUseDJBooth = ControllerFunctions.canUseDJBooth(player),
		canManageDJBooth = ControllerFunctions.isDJBoothController(player),
		vip = vip,
		customTitleUnlocked = ControllerFunctions.hasTikiTideAccess(player),
		queue = safeQueue,
		globalPlaybackSync = {
			enabled = false,
			retired = true,
			detail = "Each server owns its own playback and request queue.",
			localQueueIsolated = true,
		},
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
		djControlMode = djControlModeEnabled,
		djControlModeUserId = djControlModeUserId,
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
		tikiTideGamePassId = CONFIG.TikiTidePassId,
		passTier = ControllerFunctions.passTier(player),
		passName = if ControllerFunctions.hasTikiTideAccess(player) then "TIKI TIDE" elseif ControllerFunctions.isVvip(player) then "VVIP" elseif ControllerFunctions.isVip(player) then "VIP" else "GUEST",
		passPerks = {
			vip = { slots = CONFIG.VipMaxRequestsPerPlayer, cooldown = CONFIG.VipCooldownSeconds },
			vvip = { slots = CONFIG.VvipMaxRequestsPerPlayer, cooldown = CONFIG.VvipCooldownSeconds },
			tikiTide = { slots = CONFIG.TikiTideMaxRequestsPerPlayer, cooldown = CONFIG.TikiTideCooldownSeconds, priority = "highest" },
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
				passTier = ControllerFunctions.passTier(other),
				rewardedPassTier = if profiles[other.UserId] then profiles[other.UserId].rewardedPassTier else 0,
				groupMember = ControllerFunctions.isGroupMember(other),
				blocked = blockedUsers[other.UserId] == true,
				requests = requestCounts[other.UserId] or 0,
				canMod = ControllerFunctions.canModerate(player, other),
				-- Explicit server-derived flag for the free tier award controls.
				-- Owners may award any other player; self-awards remain prohibited.
				canAwardPassTier = ControllerFunctions.getLevel(player) >= 4 and other.UserId ~= player.UserId,
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

-- Playback state is latency-sensitive: don't hold title, pause, or restart
-- updates behind the general-purpose state coalescing interval.
ControllerFunctions.publishPlaybackState = function()
	-- Playback commits already run on the server task that owns the new state.
	-- Build and send the snapshot in that same task so clients don't wait for
	-- another deferred scheduler turn to learn the new title/pause/restart state.
	for _, target in ipairs(Players:GetPlayers()) do
		local ok, snapshot = pcall(ControllerFunctions.snapshotFor, target)
		if ok and target.Parent == Players then
			pcall(function() stateRemote:FireClient(target, snapshot) end)
		end
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
	Coconut = 3731488823,
	Pineapple = 3731489572,
	TikiTorch = 3731490154,
	Volcano = 3731490513,
	IslandLegend = 3731490937,
	IslandRoyalty = 3731491257,
	SultansLegacy = 3731491679,

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
ControllerFunctions.registerProduct(PRODUCT_IDS.IslandRoyalty, {
	type = "Donation", perk = "Island Royalty", amount = 5000,
})
ControllerFunctions.registerProduct(PRODUCT_IDS.SultansLegacy, {
	type = "Donation", perk = "Sultan's Legacy", amount = 10000,
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

-- Durable receipt journal ownership is in Security Core. This controller only
-- supplies the existing profile/session adapters and product reward mutators.
do
	local core = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("ReceiptTransactionService") else nil
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new, {
				profileStore = store,
				journalStore = DataStoreService:GetDataStore("ClubMusic_ProductReceipts_v1"),
				getProfile = function(userId: number) return profiles[userId] end,
				getSessionToken = function() return SESSION_TOKEN end,
				getSessionLockSeconds = function() return SESSION_LOCK_SECONDS end,
				waitForDataStoreBudget = function(timeout: number)
					return ControllerFunctions.waitForDataStoreBudget(timeout)
				end,
				acquireProfileWriteLock = function(userId: number)
					return ControllerFunctions.acquireProfileWriteLock(userId)
				end,
				releaseProfileWriteLock = function(userId: number)
					return ControllerFunctions.releaseProfileWriteLock(userId)
				end,
				applyReceiptToStoredData = function(data: {[string]: any}, productData: {[string]: any})
					return ControllerFunctions.applyReceiptToStoredData(data, productData)
				end,
				applyReceiptToMemory = function(profile: Profile, productData: {[string]: any})
					ControllerFunctions.applyReceiptToMemory(profile, productData)
				end,
				keySuffix = function(value: string) return ReceiptHash.KeySuffix(value) end,
				useStudioMemoryProfiles = USE_STUDIO_MEMORY_PROFILES,
			})
			if createOk and typeof(instance) == "table" and type(instance.Commit) == "function"
				and type(instance.HasPendingMemory) == "function" and type(instance.ForgetProfile) == "function" then
				receiptTransactions = instance
			else
				warn("[ClubMusic][ReceiptTransaction] Security Core transaction service construction failed: " .. tostring(instance))
			end
		else
			warn("[ClubMusic][ReceiptTransaction] Security Core transaction module failed to load: " .. tostring(exported))
		end
	else
		warn("[ClubMusic][ReceiptTransaction] Security Core transaction module is missing; Developer Product receipts will remain retryable.")
	end
end

local function recordReceiptReplayEvent(eventType: string, userId: number, productId: number, severity: string, outcome: string)
	-- Never place PurchaseId or other receipt secrets in replay metadata.
	local replay = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
	if replay and replay:IsA("BindableFunction") then
		pcall(function()
			replay:Invoke("Record", eventType, userId, 0, severity, "PurchaseReceipt", {
				productId = productId,
				outcome = outcome,
			})
		end)
	end
end

local function processValidatedReceipt(receiptInfo: any, productData: ProductData): Enum.ProductPurchaseDecision
	local userId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local receiptId = receiptInfo.PurchaseId
	print(string.format("[ClubMusic][PurchaseServer] ProcessReceiptReached | UserId=%s | ProductId=%s | PlaceId=%d | GameId=%d",
		tostring(userId), tostring(productId), game.PlaceId, game.GameId))
	recordPurchaseDiagnostic("ServerReceipt", userId, productId, "ProcessReceiptReached", "Roblox dispatched an authoritative Developer Product receipt")
	recordReceiptReplayEvent("receipt_received", userId, productId, "Info", "RobloxReceiptCallback")
	local player = Players:GetPlayerByUserId(userId)
	local profile = profiles[userId]
	if not player or not profile then
		recordPurchaseDiagnostic("ServerReceipt", userId, productId, "AwaitingPlayerProfile", "Player or loaded profile is not available; Roblox receipt will retry")
		recordReceiptReplayEvent("receipt_waiting_profile", userId, productId, "Info", "RetryPending")
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
				recordPurchaseDiagnostic("ServerReceipt", userId, productId, "XPBoostActivationFailed", "Global XP service rejected or failed activation; Roblox receipt will retry")
				recordReceiptReplayEvent("receipt_activation_failed", userId, productId, "Warning", "RetryPending")
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
		recordPurchaseDiagnostic("ServerReceipt", userId, productId, "ReceiptGranted", "Global XP boost activation completed")
		recordReceiptReplayEvent("receipt_granted", userId, productId, "Info", "XPBoost")
		notify(player, string.format("%dx global XP boost activated!", productData.multiplier), "ok")
		publishState(nil)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if not receiptTransactions then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local ok, alreadyProcessed, err = receiptTransactions:Commit(userId, receiptId, productData)
	if not ok then
		warn("[ClubMusic] Receipt persistence failed for userId " .. tostring(userId) .. " productId " .. tostring(productId) .. ": " .. tostring(err))
		recordPurchaseDiagnostic("ServerReceipt", userId, productId, "ReceiptPersistenceFailed", tostring(err))
		recordReceiptReplayEvent("receipt_persistence_failed", userId, productId, "Warning", "RetryPending")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- A receipt already in the durable ledger was granted by an earlier callback/server.
	-- The loaded profile already contains its reward, so never apply it twice in memory.
	if alreadyProcessed then
		recordPurchaseDiagnostic("ServerReceipt", userId, productId, "ReceiptDuplicate", "Receipt was already committed in the durable ledger")
		recordReceiptReplayEvent("receipt_duplicate", userId, productId, "Info", "AlreadyCommittedInDurableLedger")
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if profiles[userId] ~= profile then
		recordReceiptReplayEvent("receipt_profile_changed", userId, productId, "Warning", "RetryPending")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if USE_STUDIO_MEMORY_PROFILES then ControllerFunctions.applyReceiptToMemory(profile, productData) end
	recordPurchaseDiagnostic("ServerReceipt", userId, productId, "ReceiptGranted", "Receipt persistence completed and reward application proceeded")
	recordReceiptReplayEvent("receipt_granted", userId, productId, "Info", "DurableReceiptCommitted")
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
		elseif perk == "Island Legend" then ControllerFunctions.broadcast(string.format("👑 LEGENDARY: %s is displayed on the Big Stage Screens!", player.DisplayName), "info")
		elseif perk == "Island Royalty" then ControllerFunctions.broadcast(string.format("👑 ROYAL CELEBRATION: %s has supported the island with an extraordinary gift!", player.DisplayName), "info")
		elseif perk == "Sultan's Legacy" then ControllerFunctions.broadcast(string.format("✨ SULTAN'S LEGACY: %s has made the ultimate island contribution!", player.DisplayName), "ok") end
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


local receiptAuthority: any = nil
do
	local core = ServerStorage:FindFirstChild("ClubMusicSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("ReceiptAuthority") else nil
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new, {
				resolveProduct = function(productId: number)
					return PRODUCT_MAP[productId]
				end,
				processValidatedReceipt = processValidatedReceipt,
				onEvent = function(eventName: string, receiptInfo: any, detail: string?)
					local userId, productId = 0, 0
					if typeof(receiptInfo) == "table" then
						local candidateUserId, candidateProductId = receiptInfo.PlayerId, receiptInfo.ProductId
						if typeof(candidateUserId) == "number" and candidateUserId == candidateUserId
							and candidateUserId > 0 and candidateUserId < math.huge and candidateUserId % 1 == 0
							and candidateUserId <= 9007199254740991 then userId = candidateUserId end
						if typeof(candidateProductId) == "number" and candidateProductId == candidateProductId
							and candidateProductId > 0 and candidateProductId < math.huge and candidateProductId % 1 == 0
							and candidateProductId <= 9007199254740991 then productId = candidateProductId end
					end
					local outcomes = {
						MalformedReceipt = "MalformedReceipt",
						ReceiptDuplicate = "ReceiptDuplicate",
						ReceiptInFlight = "ReceiptConcurrentRetry",
						ReceiptCapacity = "ReceiptConcurrencyCapacity",
						UnknownProduct = "RejectedUnregisteredProduct",
						TransactionHandlerFailed = "ReceiptHandlerFailed",
						InvalidDecision = "ReceiptInvalidDecision",
					}
					local outcome = outcomes[eventName] or "ReceiptAuthorityEvent"
					recordPurchaseDiagnostic("ServerReceipt", userId, productId, outcome, detail)
					recordReceiptReplayEvent("receipt_" .. string.lower(eventName), userId, productId,
						if eventName == "UnknownProduct" or eventName == "TransactionHandlerFailed" then "Warning" else "Info", outcome)
				end,
			})
			if createOk and typeof(instance) == "table" and type(instance.Process) == "function"
				and type(instance.GetStatus) == "function" then
				receiptAuthority = instance
			else
				warn("[ClubMusic][ReceiptAuthority] Service construction failed: " .. tostring(instance))
			end
		else
			warn("[ClubMusic][ReceiptAuthority] Module load failed: " .. tostring(exported))
		end
	else
		warn("[ClubMusic][ReceiptAuthority] Security Core module is missing; Developer Product receipts will remain retryable.")
	end
end

local receiptAuthorityStatusObject = ServerStorage:FindFirstChild("GetTikiTideReceiptAuthorityStatus")
local receiptAuthorityStatus: BindableFunction? = nil
if receiptAuthorityStatusObject and receiptAuthorityStatusObject:IsA("BindableFunction") then
	receiptAuthorityStatus = receiptAuthorityStatusObject
elseif receiptAuthorityStatusObject then
	warn("[ClubMusic][ReceiptAuthority] Status endpoint has the wrong class; leaving it untouched.")
else
	local createdStatus = Instance.new("BindableFunction")
	createdStatus.Name = "GetTikiTideReceiptAuthorityStatus"
	createdStatus.Parent = ServerStorage
	receiptAuthorityStatus = createdStatus
end
if receiptAuthorityStatus then
	receiptAuthorityStatus.OnInvoke = function()
		local ingress = if receiptAuthority then receiptAuthority:GetStatus()
			else {state = "Unavailable", scope = "ServerLocalIngress"}
		local transaction = if receiptTransactions then receiptTransactions:GetStatus() else {state = "Unavailable"}
		return {state = if ingress.state == "Ready" and transaction.state == "Ready" then "Ready" else "Degraded",
			scope = "ServerLocalReceiptAuthority", ingress = ingress, transaction = transaction}
	end
end

-- This controller remains Roblox's single ProcessReceipt callback adapter.
-- Security Core owns validation, serialization, profile receipt journaling, and
-- recovery. The Global Service retains the existing cross-server XP boost journal.
MarketplaceService.ProcessReceipt = function(receiptInfo: any)
	-- Stop accepting new callbacks once shutdown starts. Roblox will retry any
	-- unacknowledged receipt on another server; active callbacks remain tracked.
	if serverShuttingDown or not receiptAuthority then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	activeReceiptCallbacks += 1
	local callOk, decision = pcall(receiptAuthority.Process, receiptAuthority, receiptInfo)
	activeReceiptCallbacks = math.max(0, activeReceiptCallbacks - 1)
	if not callOk then
		warn("[ClubMusic][ReceiptAuthority] ProcessReceipt adapter failed; Roblox will retry: " .. tostring(decision))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return decision
end

ControllerFunctions.isValidString = function(value: any, maxLength: number): boolean
	return typeof(value) == "string" and #value > 0 and #value <= maxLength
end

-- Remote payloads are intentionally shallow and small. This rejects oversized
-- tables before action-specific code can inspect or retain attacker-controlled data.
ControllerFunctions.isBoundedPayload = function(payload: any): boolean
	if typeof(payload) ~= "table" then return false end
	-- Shared validation is deliberately capped to a tiny, shallow request tree.
	-- The legacy field checks below remain as a compatibility contract for UI actions.
	if sanityValidationService then
		local ok, valid = pcall(sanityValidationService.ValidateDataTree, payload, {
			maxDepth = 3,
			maxEntries = 64,
			maxStringLength = 1024,
		})
		if not ok or valid ~= true then return false end
	end
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
	if player:GetAttribute("GlobalModerationPending") == true then
		return "Global moderation is temporarily checking your account. Song requests are paused until verification completes."
	end
	if blockedUsers[player.UserId] then return "Your requests are disabled by staff." end
	if ControllerFunctions.isTrackBlocked(trackId) then return "That track has been blocked by ClubMusic staff." end
	if djControlModeEnabled and djControlModeUserId ~= player.UserId then return "DJ Control Mode is active. Only the current DJ controller can submit requests." end
	if requestsLocked and ControllerFunctions.getLevel(player) < 3 then return "Emergency request lock is active on this server." end
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
	if not ControllerFunctions.hasTikiTideAccess(player) then
		notify(player, "Custom titles are exclusive to Tiki Tide members.", "warn")
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
	local textNow = os.clock()
	local previousTextAt = lastCustomTitleTextAt[player.UserId] or 0
	if previousTextAt > 0 and textNow - previousTextAt < CUSTOM_TITLE_TEXT_COOLDOWN_SECONDS then
		local remaining = math.ceil(CUSTOM_TITLE_TEXT_COOLDOWN_SECONDS - (textNow - previousTextAt))
		notify(player, "Custom title text can only be changed once every 60 seconds. Wait " .. tostring(remaining) .. " seconds.", "warn")
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

	-- Filtering yields. Revalidate profile ownership, live caller, entitlement,
	-- and slot access immediately before committing the filtered text.
	local commitNow = os.clock()
	local latestTextAt = lastCustomTitleTextAt[player.UserId] or 0
	if profiles[player.UserId] ~= profile or player.Parent ~= Players
		or not ControllerFunctions.hasTikiTideAccess(player)
		or slotNumber > profile.unlockedSlots
		or (latestTextAt > 0 and commitNow - latestTextAt < CUSTOM_TITLE_TEXT_COOLDOWN_SECONDS) then
		return false
	end
	lastCustomTitleTextAt[player.UserId] = commitNow
	ControllerFunctions.recordTextReplayEvent(player, "custom_title_filtered")
	local safeTexts = filteredTitleTextByUserId[player.UserId]
	if not safeTexts then safeTexts = {}; filteredTitleTextByUserId[player.UserId] = safeTexts end
	safeTexts[slotNumber] = filtered
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
	if not ControllerFunctions.isLiveRemotePlayer(player) then return false, "The caller is no longer in this server." end

	-- Spend the cheap per-player/per-server ingress budget before walking any
	-- attacker-controlled table. This bounds validation CPU under malformed spam.
	local now = os.clock()
	local userId = player.UserId
	if not ControllerFunctions.consumeActionBudget(userId, now) then return false, "ClubMusic action rate limit reached. Try again shortly." end

	-- Validate the fixed request contract only after the ingress budget is charged.
	if not ControllerFunctions.isValidString(action, 32)
		or not ControllerFunctions.isBoundedPayload(payload) then
		return false, "Invalid action or payload."
	end
	if ACTION_COOLDOWNS[action] == nil then return false, "That action is not supported." end
	-- Check every cooldown before recording timestamps. A rejected action must not
	-- consume the cross-action interval and block an unrelated command immediately after it.
	-- Keep trusted admin commands in a separate per-action cooldown lane.
	-- The local per-player/server budgets still protect this bridge, while this avoids
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
			ControllerFunctions.clearAutomaticQueue()
			ControllerFunctions.topUpAuto()
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
		if not ControllerFunctions.isValidAudioAssetId(assetId) then
			notify(player, "Enter a valid audio asset ID.", "warn"); return
		end
		if typeof(genreId) ~= "string" or #genreId > 24 then
			notify(player, "Choose a valid catalog genre.", "warn"); return
		end
		if artworkAssetId ~= nil and not ControllerFunctions.isValidAudioAssetId(artworkAssetId) then
			notify(player, "Artwork must be a valid Roblox image asset ID.", "warn"); return
		end
		if artworkAssetId ~= nil then
			-- Metadata lookups yield. Bound concurrent artwork inspections separately
			-- from audio preloads, and allow only one pending artwork lookup per caller.
			if pendingArtwork[userId] then
				notify(player, "An artwork inspection is already running.", "warn"); return
			end
			if artworkInspectionCount >= 4 then
				notify(player, "Artwork inspection is busy. Try again shortly.", "warn"); return
			end
			pendingArtwork[userId] = true
			artworkInspectionCount += 1
			local artworkInfoOk, artworkInfo = pcall(function()
				return MarketplaceService:GetProductInfo(artworkAssetId, Enum.InfoType.Asset)
			end)
			pendingArtwork[userId] = nil
			artworkInspectionCount = math.max(0, artworkInspectionCount - 1)
			local imageType = Enum.AssetType.Image.Value
			local decalType = Enum.AssetType.Decal.Value
			local deletedName = artworkInfoOk and typeof(artworkInfo) == "table"
				and typeof(artworkInfo.Name) == "string"
				and string.lower(string.gsub(artworkInfo.Name, "%s+", " ")) == "[ content deleted ]"
			if not artworkInfoOk or typeof(artworkInfo) ~= "table"
				or (artworkInfo.AssetTypeId ~= imageType and artworkInfo.AssetTypeId ~= decalType)
				or deletedName then
				notify(player, "That artwork is unavailable or is not an accessible Roblox image/decal asset.", "warn"); return
			end
			-- Recheck the caller after the yielding marketplace lookup. A role or
			-- session change while inspection was in flight must not authorize a write.
			if player.Parent ~= Players or not ControllerFunctions.isStaff(player) then return end
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
		local saved, message = MusicCatalogService:AddCustomTrack(assetId, title, artist, duration, genreId, artworkAssetId)
		if not saved then
			notify(player, message, "warn")
			return
		end

		local track = MusicCatalogService:GetTrackById(trackId)
		if track then
			TRACK_BY_ID[trackId] = track
			if not table.find(ALL_TRACK_IDS, trackId) then table.insert(ALL_TRACK_IDS, trackId) end
			table.sort(ALL_TRACK_IDS)
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
		local track = TRACK_BY_ID[trackId]
		if not track or track.assetId == nil then
			notify(player, "Only staff-added catalog tracks can be removed here.", "warn"); return
		end
		if not catalogStorageReady or not ControllerFunctions.waitForDataStoreBudget(5) then
			notify(player, "Catalog storage is unavailable; track was not removed.", "warn"); return
		end
		if nowPlaying.trackId == trackId then
			notify(player, "That track is currently playing. Remove it after playback ends.", "warn"); return
		end
		for _, queued in ipairs(queue) do
			if queued.trackId == trackId then
				notify(player, "That track is queued. Remove it from the queue first.", "warn"); return
			end
		end
		local removed, message = MusicCatalogService:RemoveCustomTrack(trackId)
		if not removed then
			notify(player, tostring(message or "Catalog track could not be removed."), "warn")
			return
		end
		TRACK_BY_ID[trackId] = nil
		for index, id in ipairs(ALL_TRACK_IDS) do
			if id == trackId then table.remove(ALL_TRACK_IDS, index); break end
		end
		if activePlaylistId then
			for index = #activePlaylistTracks, 1, -1 do
				if activePlaylistTracks[index].id == trackId then table.remove(activePlaylistTracks, index) end
			end
			activePlaylistCursor = math.clamp(activePlaylistCursor, 1, math.max(1, #activePlaylistTracks))
			ControllerFunctions.clearAutomaticQueue()
			ControllerFunctions.topUpAuto()
		end
		local publishOk, published = ControllerFunctions.globalInvoke("PublishCatalogChange")
		if not publishOk or published ~= true then
			warn("[ClubMusic] Catalog removal saved locally; cross-server invalidation publish failed.")
		end
		notify(player, tostring(message or "Track removed from the catalog."), "ok")
		publishState(nil)
		return
	end

	if action == "RequestTrack" then
		if phase32Services then
			local restrictionOk, restricted = phase32Services:IsRestricted(player.UserId, "MusicRequests")
			if not restrictionOk then notify(player, "Moderation restrictions could not be verified. Requests are temporarily unavailable.", "warn"); return end
			if restricted then notify(player, "Your music requests are restricted by moderation.", "warn"); return end
		end
		local trackId = payload.trackId
		if not ControllerFunctions.isValidString(trackId, 24) then return end
		local track = TRACK_BY_ID[trackId]
		if not track then return end
		if not isPlayableTrack(track) then notify(player, "That catalog entry is a temporary placeholder and is not playable yet.", "warn"); return end

		if djControlModeEnabled and djControlModeUserId ~= player.UserId then
			notify(player, "DJ Control Mode is active. Only the current DJ controller can submit requests.", "warn")
			return
		end
		if blockedUsers[player.UserId] then
			notify(player, "Your requests are disabled by staff.", "warn")
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
		queueManager:Insert(ControllerFunctions.insertIndex(ControllerFunctions.passTier(player)), entry)
		requestCounts[player.UserId] = count + 1
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
		if djControlModeEnabled and djControlModeUserId ~= player.UserId then
			notify(player, "DJ Control Mode is active. Only the current DJ controller can submit requests.", "warn")
			return
		end
		local assetId = payload.assetId
		if not ControllerFunctions.isValidAudioAssetId(assetId) then
			ControllerFunctions.recordAudioValidationSignal(player, "audio_asset_invalid_id")
			notify(player, "That audio asset ID isn't valid.", "warn")
			return
		end
		if CONFIG.RestrictAudioToAllowlist and not table.find(CONFIG.AllowedAudioAssetIds, assetId) then
			ControllerFunctions.recordAudioValidationSignal(player, "audio_asset_not_allowlisted")
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
		if player.Parent ~= Players or not ControllerFunctions.isStaff(player) then return end
		if djControlModeEnabled and djControlModeUserId ~= player.UserId then
			notify(player, "DJ Control Mode is active. Only the current DJ controller can submit requests.", "warn")
			return
		end

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
		queueManager:Insert(ControllerFunctions.insertIndex(ControllerFunctions.passTier(player)), entry)
		requestCounts[player.UserId] = (requestCounts[player.UserId] or 0) + 1
		lastRequestAt[player.UserId] = recheckNow
		ControllerFunctions.recordAudioReplayEvent(player, "audio_asset_queued")
		notify(player, "Audio queued: " .. titleOrError, "ok")
		publishState(nil)
		return
	end

	if action == "ReloadSong" then
		-- Self-service recovery: any live player may reload audio when it fails.
		-- Per-player cooldown and the global action budget still protect this operation.
		local last = lastReloadAt[player.UserId] or -1000
		if now - last < CONFIG.ReloadCooldownSeconds then return end
		lastReloadAt[player.UserId] = now
		local recovered, recoveryError = ControllerFunctions.reloadServerMusic()
		if recovered then
			reloadNonce[player.UserId] = (reloadNonce[player.UserId] or 0) + 1
			notify(player, "Audio reloaded at the current track position.", "ok")
		else
			notify(player, tostring(recoveryError or "Audio reload could not be completed."), "warn")
		end
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
		local accepted, message = ControllerFunctions.castSkipVote(player)
		if accepted ~= true then notify(player, tostring(message or "Skip vote was rejected."), "warn") end
		return
	end

	-- Staff ----------------------------------------------------------------------------

	if action == "DJToggleGlobalPlaybackSync" then
		return false, "Global playback sync has been retired; each server owns its own playback and request queue."
	end

	if action == "DJPlayPlaylist" then
		if not ControllerFunctions.isDJBoothController(player) then notify(player, "The DJ Booth is restricted to the Owner and Co-Owner.", "warn"); return end
		if not playlistStorageReady or not MusicPlaylistService:IsReady() then
			notify(player, "Playlist storage is unavailable.", "warn"); return
		end
		if ControllerFunctions.startPlaylistRotation(player, payload.playlistId) then publishState(nil) end
		return
	end

	if action == "DJStopPlaylist" then
		if not ControllerFunctions.isDJBoothController(player) then notify(player, "The DJ Booth is restricted to the Owner and Co-Owner.", "warn"); return end
		if ControllerFunctions.stopPlaylistRotation(player) then publishState(nil) end
		return
	end

	if action == "DJMoveUp" then
		if not ControllerFunctions.isDJBoothController(player) then return false, "The DJ Booth is restricted to the Owner and Co-Owner." end
		local id = payload.queueId
		if not ControllerFunctions.isValidString(id, 64) then return end
		local index = ControllerFunctions.findQueueIndex(id)
		if index and index > 1 then queue[index], queue[index - 1] = queue[index - 1], queue[index] end
		publishState(nil)
		return
	end

	if action == "DJRemove" then
		if not ControllerFunctions.isDJBoothController(player) then return false, "The DJ Booth is restricted to the Owner and Co-Owner." end
		local id = payload.queueId
		if not ControllerFunctions.isValidString(id, 64) then return false, "A valid queue entry ID is required." end
		local index = ControllerFunctions.findQueueIndex(id)
		if not index then return false, "Queue entry was not found. Run ;cmqueue to refresh the IDs." end
		local removedEntry = queueManager:RemoveAt(index, true)
		if not removedEntry then return false, "Queue entry could not be removed." end
		ControllerFunctions.topUpAuto()
		publishState(nil)
		return true, "Removed queued track: " .. tostring(removedEntry.title or "Unknown track") .. "."
	end

	if action == "DJSkip" then
		if not ControllerFunctions.canUseDJBooth(player) then return false, "DJ Booth access is required." end
		if trustedAdminCommand == true and transitionInProgress then
			return true, "A track transition is already being processed; no second skip was sent."
		end
		local advanced, transitionError = ControllerFunctions.advance()
		if not advanced then
			local reason = tostring(transitionError or "The local track transition could not be confirmed.")
			notify(player, reason, "warn")
			return false, reason
		end
		notify(player, "Track skipped on this server.", "ok")
		return true, "Track skipped on this server."
	end

	if action == "DJPause" then
		if not ControllerFunctions.canUseDJBooth(player) then return false, "DJ Booth access is required." end
		if audioReloadInProgress then
			notify(player, "Please wait for the current audio reload to finish before changing playback controls.", "warn")
			return false, "Audio reload is in progress."
		end
		if nowPlaying.trackId == "" then notify(player, "No track is currently selected.", "warn"); return false, "No track is currently selected." end
		local desiredPaused = not playbackPaused
		playbackControlRequestId += 1
		ControllerFunctions.cancelAudioTransition(if desiredPaused then "pause" else "resume")
		local position = math.clamp(tonumber(nowPlaying.elapsed) or 0, 0, nowPlaying.duration)
		local audioOk, audioError = pcall(function()
			local controlOk, controlResult, capturedPosition
			if desiredPaused then
				controlOk, controlResult, capturedPosition = ControllerFunctions.pauseAudio()
				if ControllerFunctions.isFiniteNumber(capturedPosition) then
					position = math.clamp(capturedPosition, 0, nowPlaying.duration)
				end
			else
				controlOk, controlResult = ControllerFunctions.resumeAudio()
			end
			if controlOk == false or controlResult == false then error("The audio source rejected the pause/resume command.") end
		end)
		if not audioOk then
			notify(player, "Audio control could not be applied: " .. tostring(audioError), "warn")
			return false, tostring(audioError)
		end
		nowPlaying.elapsed = position
		playbackPaused = desiredPaused
		ControllerFunctions.publishPlaybackState()
		notify(player, if desiredPaused then "Music paused on this server." else "Music resumed on this server.", "ok")
		return true, if desiredPaused then "Music paused on this server." else "Music resumed on this server."
	end

	if action == "DJRestart" then
		if not ControllerFunctions.canUseDJBooth(player) then return false, "DJ Booth access is required." end
		if audioReloadInProgress then
			notify(player, "Please wait for the current audio reload to finish before restarting the track.", "warn")
			return false, "Audio reload is in progress."
		end
		if nowPlaying.trackId == "" then notify(player, "No track is currently selected.", "warn"); return false, "No track is currently selected." end
		playbackControlRequestId += 1
		local restartAsset = nowPlaying.soundId
		ControllerFunctions.cancelAudioTransition("restart")
		local restartOk, restartError = ControllerFunctions.restartServerMusic(restartAsset)
		if not restartOk then
			playbackPaused = true
			notify(player, "Track restart could not be applied: " .. tostring(restartError), "warn")
			return false, tostring(restartError)
		end
		nowPlaying.elapsed = 0
		playbackPaused = false
		ControllerFunctions.publishPlaybackState()
		notify(player, "Current track restarted on this server.", "ok")
		return true, "Current track restarted on this server."
	end

	if action == "DJClearQueue" then
		if not ControllerFunctions.isDJBoothController(player) then return false, "The DJ Booth is restricted to the Owner and Co-Owner." end
		ControllerFunctions.cancelAudioTransition("queue-clear")
		queueManager:Clear(true)
		autoQueueHold = true
		notify(player, "This server's queue was cleared.", "ok")
		publishState(nil)
		return true, "This server's queue was cleared."
	end

	if action == "DJToggleLock" then
		if not ControllerFunctions.canUseDJBooth(player) then return false, "DJ Booth access is required." end
		if djControlModeEnabled then
			if djControlModeUserId ~= player.UserId then
				return false, "Only the player currently controlling the DJ booth can turn DJ Control Mode off."
			end
			djControlModeEnabled = false
			djControlModeUserId = nil
		else
			djControlModeEnabled = true
			djControlModeUserId = player.UserId
		end
		ControllerFunctions.broadcast(if djControlModeEnabled then "DJ Control Mode is ON. Only the current DJ controller can submit player requests; Auto DJ remains active." else "DJ Control Mode is OFF. Normal player requests are open; Auto DJ remains active.", "info")
		publishState(nil)
		return true, if djControlModeEnabled then "DJ Control Mode enabled. Your requests remain permitted; other player requests are blocked." else "DJ Control Mode disabled. Normal player requests are open."
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

	if action == "ModSetPassTier" then
		-- Only the actual configured OWNER may issue free membership rank-up rewards.
		if ControllerFunctions.getLevel(player) < 4 then return end
		local target = ControllerFunctions.findTarget(player, payload.userId)
		local requestedTier = payload.passTier
		if not target or typeof(requestedTier) ~= "number" or requestedTier % 1 ~= 0
			or requestedTier < 0 or requestedTier > 3 then return end
		local profile = profiles[target.UserId]
		if not profile then
			notify(player, "That player's profile is not ready; no membership reward was changed.", "warn")
			return
		end
		profile.rewardedPassTier = requestedTier
		ControllerFunctions.applyVipAttribute(target)
		ControllerFunctions.scheduleProfileSave(target)
		local tierName = ({"GUEST", "VIP", "VVIP", "TIKI TIDE"})[requestedTier + 1]
		notify(target, if requestedTier > 0 then "Your free membership rank was raised to " .. tierName .. "!" else "Your owner-awarded membership rank was reset.", "info")
		notify(player, target.DisplayName .. " membership reward set to " .. tierName .. ".", "ok")
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
		if phase32Services then
			local restrictionOk, restricted = phase32Services:IsRestricted(player.UserId, "CustomText")
			if not restrictionOk or restricted then notify(player, "Custom titles are unavailable under your current moderation restrictions.", "warn"); return end
		end
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
		if phase32Services then
			local restrictionOk, restricted = phase32Services:IsRestricted(player.UserId, "CustomText")
			if not restrictionOk or restricted then notify(player, "Custom titles are unavailable under your current moderation restrictions.", "warn"); return end
		end
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
		if not ControllerFunctions.hasTikiTideAccess(player) then notify(player, "Custom titles require Tiki Tide.", "warn"); return end
		local slotNumber = payload.slot
		if typeof(slotNumber) ~= "number" or slotNumber % 1 ~= 0 or slotNumber < 1 or slotNumber > TITLE_SLOT_COUNT then return end
		local profile = profiles[player.UserId]
		if not profile or slotNumber > profile.unlockedSlots then return end
		if profile.titleSlots[slotNumber] == nil then
			notify(player, "Save a title in that slot first.", "warn")
			return
		end
		if not ControllerFunctions.ensureFilteredTitleSlot(player, profile, slotNumber) then
			notify(player, "Roblox text filtering is unavailable. This title remains hidden; please try again.", "warn")
			return
		end
		-- The filter call yields; entitlement and profile identity must still be
		-- valid before switching the replicated active title.
		if profiles[player.UserId] ~= profile or player.Parent ~= Players
			or not ControllerFunctions.hasTikiTideAccess(player)
			or slotNumber > profile.unlockedSlots then return end
		profile.activeSlot = slotNumber
		ControllerFunctions.applyTitleAttributes(player, profile)
		ControllerFunctions.scheduleProfileSave(player)
		publishState(player)
		return
	end

	if action == "ClearTitleSlot" then
		if not ControllerFunctions.hasTikiTideAccess(player) then notify(player, "Custom titles require Tiki Tide.", "warn"); return end
		local slotNumber = payload.slot
		if typeof(slotNumber) ~= "number" or slotNumber % 1 ~= 0 or slotNumber < 1 or slotNumber > TITLE_SLOT_COUNT then return end
		local profile = profiles[player.UserId]
		if not profile or slotNumber > profile.unlockedSlots then return end
		profile.titleSlots[slotNumber] = nil
		local safeTexts = filteredTitleTextByUserId[player.UserId]
		if safeTexts then safeTexts[slotNumber] = nil end
		if profile.activeSlot == slotNumber then
			profile.activeSlot = ControllerFunctions.firstFilledSlot(profile) or 1
			if profile.titleSlots[profile.activeSlot] then
				ControllerFunctions.ensureFilteredTitleSlot(player, profile, profile.activeSlot)
			end
		end
		ControllerFunctions.applyTitleAttributes(player, profile)
		ControllerFunctions.scheduleProfileSave(player)
		publishState(player)
		return
	end

	if action == "SetTitleVisible" then
		if not ControllerFunctions.hasTikiTideAccess(player) then notify(player, "Custom titles require Tiki Tide.", "warn"); return end
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
	if not ControllerFunctions.isLiveRemotePlayer(player) then return nil end
	local now = os.clock()
	if not ControllerFunctions.consumeToken(globalCatalogQueryBucket, now, 1) then return nil end
	-- Catalog browsing is a read-only lookup over the built-in in-memory
	-- catalog plus the local custom-track cache. Keep it available during a
	-- transient global security-service outage; the per-server token bucket
	-- above and per-player cooldown below still bound request volume.
	local previous = lastCatalogInvoke[player.UserId] or 0
	if previous > 0 and now - previous < 0.75 then return nil end
	lastCatalogInvoke[player.UserId] = now

	if query ~= nil and (typeof(query) ~= "string" or #query > 48) then return nil end
	if genreId ~= nil and (typeof(genreId) ~= "string" or #genreId > 24) then return nil end
	if offset ~= nil and (typeof(offset) ~= "number" or offset ~= offset or offset % 1 ~= 0 or offset < 0 or offset > 10000) then return nil end
	if limit ~= nil and (typeof(limit) ~= "number" or limit ~= limit or limit % 1 ~= 0 or limit < 1 or limit > 50) then return nil end

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
	if not ControllerFunctions.isLiveRemotePlayer(player) or not playlistStorageReady then return nil end
	local now = os.clock()
	if not ControllerFunctions.consumeToken(globalStateQueryBucket, now, 1) then return nil end
	local previous = lastPlaylistInvoke[player.UserId] or 0
	if previous > 0 and now - previous < 1 then return nil end
	lastPlaylistInvoke[player.UserId] = now
	if os.clock() - playlistRefreshAt >= 5 then
		if ControllerFunctions.waitForDataStoreBudget(2) and MusicPlaylistService:Refresh() then
			playlistRefreshAt = os.clock()
			-- Another server may have edited or deleted the active playlist. Reconcile
			-- this server's playback view from the refreshed saved record. Compare the
			-- resolved sequence first so ordinary UI polling does not reset the queue.
			if activePlaylistId then
				local previousId = activePlaylistId
				local previousName = activePlaylistName
				local previousTrackIds = {}
				for _, track in ipairs(activePlaylistTracks) do
					table.insert(previousTrackIds, track.id)
				end
				ControllerFunctions.reloadActivePlaylist()
				local changed = previousId ~= activePlaylistId or previousName ~= activePlaylistName
					or #previousTrackIds ~= #activePlaylistTracks
				if not changed then
					for index, track in ipairs(activePlaylistTracks) do
						if previousTrackIds[index] ~= track.id then changed = true; break end
					end
				end
				if changed then
					ControllerFunctions.clearAutomaticQueue()
					ControllerFunctions.topUpAuto()
				end
			end
		end
	end
	return MusicPlaylistService:GetAll()
end

stateFunction.OnServerInvoke = function(player: Player)
	if not ControllerFunctions.isLiveRemotePlayer(player) then return nil end
	local now = os.clock()
	if not ControllerFunctions.consumeToken(globalStateQueryBucket, now, 1) then return nil end
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

-- Trusted admin integrations use ClubMusic Global's SecurityCore authorization API.
-- Kohl's Admin security bridge helpers. Global security operations are checked by
-- the same server-only authorization service used by the cross-server API.
ControllerFunctions.adminBridgeGlobalCall = function(name: string, ...: any): (boolean, any, any)
	local invoked, accepted, value, detail = ControllerFunctions.globalInvoke(name, ...)
	if not invoked then return false, "Global security service is unavailable." end
	-- GetGlobalAudit is a read-only list getter whose established provider
	-- contract returns the records directly, rather than true, records.
	-- Normalize that one legacy contract at this consumer boundary so the
	-- provider and any other callers keep their existing return shape.
	if name == "GetGlobalAudit" then
		if typeof(accepted) == "table" then return true, accepted end
		return false, if typeof(value) == "string" then value else "Security audit log is unavailable."
	end
	if accepted ~= true then
		return false, if typeof(value) == "string" then value else "Global security operation was rejected."
	end
	-- Boolean-only mutation APIs have no data payload. Preserve a positive
	-- confirmation for callers that check the second return value explicitly.
	return true, if value == nil then true else value, detail
end
ControllerFunctions.adminBridgeAuthorize = function(caller: Player, permission: string): boolean
	-- Authorization crosses a yielding BindableFunction boundary. Capture the
	-- actor identity before invoking it and reject a positive result if that
	-- Player departed or was replaced while the authorization call was in flight.
	if typeof(caller) ~= "Instance" or not caller:IsA("Player") or caller.Parent ~= Players then
		return false
	end
	local actorUserId = caller.UserId
	local invoked, allowed = ControllerFunctions.globalInvoke("AuthorizeGlobalAction", actorUserId, permission)
	return caller.Parent == Players and caller.UserId == actorUserId
		and invoked and allowed == true
end
ControllerFunctions.adminBridgeReportSignal = function(caller: Player, signal: string, detail: string)
	pcall(ControllerFunctions.globalInvoke, "ReportSignal", caller.UserId, signal, detail)
end

-- Server-only aggregate diagnostics bridge. It exposes counters and state only:
-- no purchase IDs, names, raw errors, reasons, or client telemetry.
local localDiagnosticsEndpoint = ServerStorage:FindFirstChild("GetClubMusicLocalDiagnostics")
if localDiagnosticsEndpoint and not localDiagnosticsEndpoint:IsA("BindableFunction") then
	localDiagnosticsEndpoint:Destroy()
	localDiagnosticsEndpoint = nil
end
if not localDiagnosticsEndpoint then
	localDiagnosticsEndpoint = Instance.new("BindableFunction")
	localDiagnosticsEndpoint.Name = "GetClubMusicLocalDiagnostics"
	localDiagnosticsEndpoint.Parent = ServerStorage
end
local localDiagnosticsBindable = localDiagnosticsEndpoint :: BindableFunction
ControllerFunctions.inspectPlaybackQuality = function()
	if nowPlaying.trackId == "" then return {state = "Idle"} end
	if nowPlaying.soundId == "" then return {state = "SilentCatalogTrack"} end
	local snapshotOk, snapshot = pcall(ControllerFunctions.getAudioSnapshot)
	if not snapshotOk or typeof(snapshot) ~= "table" or snapshot.kind == "Unavailable" then
		return {state = "Unavailable", reason = "AudioInstanceMissing"}
	end
	local elapsed = if ControllerFunctions.isFiniteNumber(nowPlaying.elapsed) then math.max(0, nowPlaying.elapsed) else 0
	local isReady = snapshot.ready == true
	local isPlaying = snapshot.playing == true
	local length = if isReady and ControllerFunctions.isFiniteNumber(snapshot.length) then math.max(0, snapshot.length) else 0
	if isPlaying then
		return {state = "Playing", backend = snapshot.kind, elapsed = elapsed, loaded = isReady, length = length}
	end
	if snapshot.paused == true then
		return {state = "Paused", backend = snapshot.kind, elapsed = elapsed, loaded = isReady, length = length}
	end
	if isReady and length > 0 then
		return {state = "StoppedAfterLoad", backend = snapshot.kind, elapsed = elapsed, loaded = true, length = length}
	end
	return {state = "BufferingOrStopped", backend = snapshot.kind, elapsed = elapsed, loaded = isReady, length = length}
end

localDiagnosticsBindable.OnInvoke = function()
	local audioSnapshot = nil
	if type(ControllerFunctions.getAudioSnapshot) == "function" then
		local ok, result = pcall(ControllerFunctions.getAudioSnapshot)
		if ok and typeof(result) == "table" then audioSnapshot = result end
	end
	local playbackQuality = nil
	local qualityOk, qualityResult = pcall(ControllerFunctions.inspectPlaybackQuality)
	if qualityOk and typeof(qualityResult) == "table" then playbackQuality = qualityResult end
	return {
		state = if remotes:GetAttribute("Ready") == true then "Healthy" else "Starting",
		scope = "ServerLocal",
		purchase = table.clone(purchaseDiagnosticStats),
		moderation = table.clone(moderationDiagnosticStats),
		playback = {
			backend = if typeof(audioSnapshot) == "table" then tostring(audioSnapshot.kind or "Unavailable") else "Unavailable",
			playing = typeof(audioSnapshot) == "table" and audioSnapshot.playing == true,
			paused = typeof(audioSnapshot) == "table" and audioSnapshot.paused == true,
			qualityState = if typeof(playbackQuality) == "table" then tostring(playbackQuality.state or "Unknown") else "Unavailable",
			qualityReason = if typeof(playbackQuality) == "table" and typeof(playbackQuality.reason) == "string" then playbackQuality.reason else "",
			qualityBackend = if typeof(playbackQuality) == "table" and typeof(playbackQuality.backend) == "string" then playbackQuality.backend else "",
			qualityLoaded = typeof(playbackQuality) == "table" and playbackQuality.loaded == true,
			qualityLength = if typeof(playbackQuality) == "table" and ControllerFunctions.isFiniteNumber(playbackQuality.length) then math.max(0, playbackQuality.length) else 0,
			queueDepth = #queue,
			globalPlaybackSync = {
				enabled = false,
				retired = true,
				localQueueIsolated = true,
			},
			modernBackendConfigured = CONFIG.UseModernAudioBackend == true,
			modernBackendStartSucceeded = modernBackendStartSucceeded,
			modernBackendStartFailureCount = modernBackendStartFailureCount,
			activeSourceKind = activeAudioSource.kind,
		},
		updatedAt = os.time(),
	}
end

-- Audio validation signals contain only a fixed event name and server-known actor ID.
-- No asset IDs, client payloads, provider metadata, or user text enter the replay timeline.
ControllerFunctions.recordAudioValidationSignal = function(player: Player, signal: string)
	local invoked, accepted = ControllerFunctions.globalInvoke("ReportSignal", player.UserId, signal)
	if invoked and accepted == true then return end
	local replay = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
	if replay and replay:IsA("BindableFunction") then
		pcall(function()
			replay:Invoke("Record", signal, player.UserId, 0, "Warning", "ClubMusicAudioValidation", {})
		end)
	end
end
ControllerFunctions.recordAudioReplayEvent = function(player: Player, eventType: string)
	local replay = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
	if replay and replay:IsA("BindableFunction") then
		pcall(function()
			replay:Invoke("Record", eventType, player.UserId, 0, "Info", "ClubMusicAudioValidation", {})
		end)
	end
end
ControllerFunctions.recordTextReplayEvent = function(player: Player, eventType: string)
	local replay = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
	if replay and replay:IsA("BindableFunction") then
		pcall(function()
			replay:Invoke("Record", eventType, player.UserId, 0, "Info", "ClubMusicTextValidation", {})
		end)
	end
end

local adminBridge = ControllerFunctions.getOrCreate(ServerStorage, "BindableFunction", "ClubMusicAdminBridge") :: BindableFunction
local ADMIN_BRIDGE_ACTIONS: {[string]: string} = {
	Skip = "DJSkip",
	TogglePause = "DJPause",
	Restart = "DJRestart",
	ToggleRequestLock = "DJToggleLock",
	ClearQueue = "DJClearQueue",
}
local adminBridgeShuttingDown = false
local adminBridgeCallback = function(caller: any, operation: any, argument: any): (boolean, string)
	if adminBridgeShuttingDown then return false, "ClubMusic admin bridge is shutting down." end
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

	-- Phase 32: server-authorized graduated punishment and investigation operations.
	if string.sub(operation, 1, 7) == "Phase32" then
		if not phase32Services then return false, "Phase 32 moderation services are unavailable; no action was applied." end
		if typeof(argument) ~= "string" or #argument < 1 or #argument > 320 then
			return false, "A bounded command argument is required."
		end
		local rawUserId, remainder
		if operation == "Phase32History" or operation == "Phase32Risk" then
			rawUserId = string.match(argument, "^%s*(%d+)%s*$")
		else
			rawUserId, remainder = string.match(argument, "^(%d+)%s+(.+)$")
		end
		local targetUserId = tonumber(rawUserId)
		if not targetUserId or targetUserId < 1 or targetUserId % 1 ~= 0 or targetUserId > 9007199254740991 then
			return false, "Provide a valid numeric Roblox UserId."
		end
		if operation == "Phase32Warn" then
			local ok, message = phase32Services:Issue(caller, targetUserId, {kind = "Warn", reason = remainder})
			return ok, message or "Warning could not be recorded."
		elseif operation == "Phase32Restrict" then
			local featureText, reason
			if remainder then featureText, reason = string.match(remainder, "^([%w,]+)%s+(.+)$") end
			if not featureText or not reason then return false, "Use: ;cmrestrict UserId Feature[,Feature] reason" end
			local restrictions = {}
			for item in string.gmatch(featureText, "[^,]+") do table.insert(restrictions, item) end
			local ok, message = phase32Services:Issue(caller, targetUserId, {kind = "Restrict", restrictions = restrictions, reason = reason})
			return ok, message or "Restriction could not be recorded."
		elseif operation == "Phase32TempBan" then
			local secondsText, reason
			if remainder then secondsText, reason = string.match(remainder, "^(%d+)%s+(.+)$") end
			local seconds = tonumber(secondsText)
			if not seconds or not reason then return false, "Use: ;cmtempban UserId Seconds reason" end
			local ok, message = phase32Services:Issue(caller, targetUserId, {kind = "TempBan", durationSeconds = seconds, reason = reason})
			return ok, message or "Temporary ban could not be applied."
		elseif operation == "Phase32PermanentBan" or operation == "Phase32PermanentBanAlts" then
			if not remainder then return false, "A permanent-ban reason is required." end
			local propagate = operation == "Phase32PermanentBanAlts"
			local ok, message = phase32Services:Issue(caller, targetUserId, {
				kind = "PermanentBan", reason = remainder,
				propagateAltAccounts = propagate, confirmAltPropagation = propagate,
			})
			return ok, message or "Permanent ban could not be applied."
		elseif operation == "Phase32Unban" then
			if not remainder then return false, "An unban reason is required." end
			return phase32Services:Unban(caller, targetUserId, remainder)
		elseif operation == "Phase32Unrestrict" then
			if not remainder then return false, "A restriction-reversal reason is required." end
			return phase32Services:RevokeRestrictions(caller, targetUserId, remainder)
		elseif operation == "Phase32History" then
			local ok, history = phase32Services:GetHistory(caller, targetUserId, 10)
			if not ok or typeof(history) ~= "table" then return false, "Moderation history is unavailable or access was denied." end
			if #history == 0 then return true, "No retained moderation history for UserId " .. tostring(targetUserId) .. "." end
			local lines = {"Phase 32 moderation history for UserId " .. tostring(targetUserId) .. ":"}
			for index, item in ipairs(history) do
				if index > 10 then break end
				local stamp = if typeof(item.at) == "number" then os.date("!%Y-%m-%d %H:%M UTC", item.at) else "Unknown time"
				local detail = if typeof(item.category) == "string" then " | category " .. string.sub(item.category, 1, 48) else ""
				if typeof(item.evidenceReference) == "string" then detail ..= " | evidence " .. string.sub(item.evidenceReference, 1, 64) end
				table.insert(lines, string.format("%s | %s | %s | case %s | actor %d%s",
					stamp, tostring(item.kind or "Unknown"), tostring(item.status or "Unknown"),
					string.sub(tostring(item.caseId or "?"), 1, 36), tonumber(item.actorUserId) or 0, detail))
			end
			return true, string.sub(table.concat(lines, "\n"), 1, 1600)
		elseif operation == "Phase32Risk" then
			local ok, summary = phase32Services:GetRiskSignals(caller, targetUserId)
			if not ok or typeof(summary) ~= "table" then return false, "Account-risk review requires IncidentResponse and available verified history." end
			local lines = {string.format("Advisory account-risk review | UserId %d | score %d/100", targetUserId, summary.score or 0)}
			for _, signal in ipairs(summary.signals or {}) do
				local detail = if typeof(signal.category) == "string" then " | " .. signal.category else ""
				if typeof(signal.eventCount) == "number" then detail ..= " | events " .. tostring(signal.eventCount) end
				if typeof(signal.accountAgeDays) == "number" then detail ..= " | account age " .. tostring(signal.accountAgeDays) .. "d" end
				table.insert(lines, string.format("%s | %s%s", tostring(signal.type), tostring(signal.confidence), detail))
			end
			table.insert(lines, "Account linkage: " .. tostring(summary.accountLinkage))
			table.insert(lines, "No automatic punishment is applied by this score.")
			return true, string.sub(table.concat(lines, "\n"), 1, 1500)
		end
		return false, "Unknown Phase 32 moderation operation."
	end

	-- Read-only status and queue inspection do not enter the action handler or
	-- consume mutation cooldowns. Global inspection refreshes the authoritative mirror.
	if operation == "Status" then
		local currentTitle = if typeof(nowPlaying.title) == "string" and nowPlaying.title ~= "" then nowPlaying.title else "Nothing playing"
		local currentArtist = if typeof(nowPlaying.artist) == "string" then nowPlaying.artist else ""
		local playbackLabel = if playbackPaused then "PAUSED" else "PLAYING"
		local requestLabel = if requestsLocked then "EMERGENCY LOCK" elseif djControlModeEnabled then "DJ CONTROL (CURRENT DJ ONLY)" else "OPEN"
		local queueCount = #queue
		local elapsed = math.max(0, math.floor(tonumber(nowPlaying.elapsed) or 0))
		local duration = math.max(0, math.floor(tonumber(nowPlaying.duration) or 0))
		local trackLabel = currentTitle .. (if currentArtist ~= "" then " — " .. currentArtist else "")
		return true, string.sub(string.format("ClubMusic: %s | %s | Requests %s | Local queue %d | %ds/%ds", trackLabel, playbackLabel, requestLabel, queueCount, elapsed, duration), 1, 450)
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
		local total = #queue
		if total == 0 then return true, "This server's ClubMusic queue is empty." end
		local lines = {string.format("This server's ClubMusic queue — %d queued:", total)}
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
	if operation == "RequestMute" or operation == "ClearUserQueue" or operation == "EmergencyLock"
		or operation == "TrackBlock" or operation == "ForceStop" or operation == "ModerationHistory" then
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
		local cleanReason = if reason ~= "" then string.sub(reason, 1, 120) else nil
		local ok, accepted = ControllerFunctions.adminBridgeGlobalCall("SetRequestBlocked", targetUserId, mode == "on", caller.UserId, cleanReason)
		if not ok or accepted ~= true then return false, tostring(accepted or "Request restriction update failed.") end
		local target = Players:GetPlayerByUserId(targetUserId)
		if mode == "on" then
			blockedUsers[targetUserId] = true
			ControllerFunctions.purgeUserEntries(targetUserId)
		else
			blockedUsers[targetUserId] = nil
		end
		publishState(nil)
		return true, string.format("ClubMusic requests %s for UserId %d%s.", if mode == "on" then "disabled" else "re-enabled", targetUserId, if target then " (" .. target.Name .. ")" else "")
	end
	if operation == "TrackBlock" then
		if typeof(argument) ~= "string" or #argument < 4 or #argument > 220 then
			return false, "Usage: ;cmblocktrack <trackId> on|off [reason]"
		end
		local trackId, mode, reason = string.match(argument, "^([%w%-_]+)%s+(%a+)%s*(.-)$")
		if not trackId or #trackId > 64 then return false, "Provide a valid catalog track ID or audio-<assetId>." end
		mode = string.lower(mode or "")
		if mode ~= "on" and mode ~= "off" then return false, "Use on or off. Example: ;cmblocktrack audio-123456 on Copyright" end
		local cleanReason = if reason ~= "" then string.sub(reason, 1, 120) else nil
		local ok, accepted = ControllerFunctions.adminBridgeGlobalCall("SetTrackBlocked", trackId, mode == "on", caller.UserId, cleanReason)
		if not ok or accepted ~= true then return false, tostring(accepted or "Track moderation update failed.") end
		ControllerFunctions.blockedTrackCache = ControllerFunctions.blockedTrackCache or {}
		ControllerFunctions.blockedTrackCache[trackId] = {blocked = mode == "on", checkedAt = os.clock()}
		if mode == "on" then
			ControllerFunctions.cancelPreparedCrossfadeForTrack(trackId, "track-blocked-local")
			for index = #queue, 1, -1 do
				if queue[index].trackId == trackId then queueManager:RemoveAt(index, true) end
			end
			if nowPlaying.trackId == trackId then
				ControllerFunctions.cancelAudioTransition("track-blocked")
				ControllerFunctions.advance()
			end
		end
		publishState(nil)
		return true, string.format("Track %s is now %s globally.", trackId, if mode == "on" then "blocked" else "allowed")
	end
	if operation == "ForceStop" then
		ControllerFunctions.cancelAudioTransition("admin-force-stop")
		playbackPaused = true
		nowPlaying.trackId = ""; nowPlaying.title = ""; nowPlaying.artist = ""
		nowPlaying.genre = ""; nowPlaying.duration = 1; nowPlaying.elapsed = 0
		nowPlaying.dj = "Staff"; nowPlaying.source = "admin"
		nowPlaying.requestedBy = "Emergency stop"; nowPlaying.vip = false; nowPlaying.soundId = ""
		ControllerFunctions.stopServerMusic()
		ControllerFunctions.setAudioAsset("")
		ControllerFunctions.broadcast("ClubMusic playback was emergency-stopped on this server by staff.", "warn")
		publishState(nil)
		return true, "ClubMusic playback was emergency-stopped on this server. Use ;cmskip to resume."
	end

	if operation == "ModerationHistory" then
		if typeof(argument) ~= "string" or #argument > 24 or not string.match(argument, "^%d+$") then
			return false, "Usage: ;cmmoderationhistory <numeric UserId>"
		end
		local targetUserId = tonumber(argument)
		if not targetUserId or targetUserId < 1 or targetUserId % 1 ~= 0 or targetUserId > 9007199254740991 then return false, "Provide a valid numeric Roblox UserId." end
		local ok, history = ControllerFunctions.adminBridgeGlobalCall("GetModerationHistory", targetUserId, caller.UserId, 10)
		if not ok or typeof(history) ~= "table" then return false, tostring(history or "Moderation history is unavailable.") end
		if #history == 0 then return true, "No recorded ClubMusic moderation actions for UserId " .. tostring(targetUserId) .. "." end
		local lines = {"ClubMusic moderation history for UserId " .. tostring(targetUserId) .. ":"}
		for index, item in ipairs(history) do
			if index > 10 then break end
			local stamp = if item.at > 0 then os.date("!%Y-%m-%d %H:%M UTC", item.at) else "Unknown time"
			table.insert(lines, string.format("%s | %s=%s | by %d%s", stamp, tostring(item.field),
				tostring(item.value), tonumber(item.actorUserId) or 0,
				if item.reason ~= "" then " | " .. string.sub(item.reason, 1, 80) else ""))
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1600)
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
		requestsLocked = true
		ControllerFunctions.broadcast("ClubMusic requests have been emergency-locked on this server by staff. Auto DJ playback/refill remains server-managed.", "warn")
		publishState(nil)
		return true, "ClubMusic requests are now locked on this server. Use ;cmlock after the incident to reopen them."
	end
	if operation == "SecurityReplay" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "GlobalModeration") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic administrator permission is required."
		end
		local targetUserId: number? = nil
		local queryLimit = 15
		local rawArgument = if typeof(argument) == "string" then string.gsub(argument, "^%s*(.-)%s*$", "%1") else ""
		if rawArgument ~= "" then
			local userPart, limitPart = string.match(rawArgument, "^(%d+)%s*(%d*)$")
			if not userPart then return false, "Use ;cmreplay [UserId] [Limit]." end
			local parsedUserId = tonumber(userPart)
			if not parsedUserId or parsedUserId < 1 or parsedUserId > 9007199254740991
				or parsedUserId % 1 ~= 0 then return false, "Replay target UserId is invalid." end
			targetUserId = parsedUserId
			if limitPart ~= "" then
				local parsedLimit = tonumber(limitPart)
				if not parsedLimit or parsedLimit < 1 or parsedLimit > 30 or parsedLimit % 1 ~= 0 then
					return false, "Replay limit must be an integer from 1 to 30."
				end
				queryLimit = parsedLimit
			end
		end
		local endpoint = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
		if not endpoint or not endpoint:IsA("BindableFunction") or endpoint.Parent ~= ServerStorage then
			return false, "Security replay is unavailable on this server."
		end
		local queryOk, allowed, events, queryError = pcall(function()
			return endpoint:Invoke("Query", caller, targetUserId, queryLimit, nil, nil)
		end)
		if not queryOk or allowed ~= true or typeof(events) ~= "table" then
			return false, if typeof(queryError) == "string" then queryError else "Security replay query failed."
		end
		if #events == 0 then
			return true, if targetUserId then "No retained replay events for UserId " .. tostring(targetUserId) .. "." else "No replay events are currently retained on this server."
		end
		local lines = {"Tiki Tide Security Replay (newest first):"}
		for index, item in ipairs(events) do
			if index > queryLimit then break end
			if typeof(item) == "table" then
				local at = if typeof(item.at) == "number" then os.date("!%H:%M:%S UTC", item.at) else "time?"
				table.insert(lines, string.format("%s | %s | %s | UserId %d | %s",
					at, string.sub(tostring(item.severity or "Info"), 1, 12),
					string.sub(tostring(item.type or "unknown"), 1, 48),
					typeof(item.userId) == "number" and item.userId or 0,
					string.sub(tostring(item.source or "Server"), 1, 24)))
			end
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1900)
	end
	if operation == "SecurityThreatIntelligence" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "GlobalModeration") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic administrator permission is required."
		end
		local targetUserId: number? = nil
		local queryLimit = 15
		local rawArgument = if typeof(argument) == "string" then string.gsub(argument, "^%s*(.-)%s*$", "%1") else ""
		if rawArgument ~= "" then
			local userPart, limitPart = string.match(rawArgument, "^(%d+)%s*(%d*)$")
			if not userPart then return false, "Use ;cmthreat [UserId] [Limit]." end
			local parsedUserId = tonumber(userPart)
			if not parsedUserId or parsedUserId < 1 or parsedUserId > 9007199254740991
				or parsedUserId % 1 ~= 0 then return false, "Threat-intelligence target UserId is invalid." end
			targetUserId = parsedUserId
			if limitPart ~= "" then
				local parsedLimit = tonumber(limitPart)
				if not parsedLimit or parsedLimit < 1 or parsedLimit > 30 or parsedLimit % 1 ~= 0 then
					return false, "Threat-intelligence limit must be an integer from 1 to 30."
				end
				queryLimit = parsedLimit
			end
		end
		local endpoint = ServerStorage:FindFirstChild("TikiTideThreatIntelligence")
		if not endpoint or not endpoint:IsA("BindableFunction") or endpoint.Parent ~= ServerStorage then
			return false, "Threat intelligence is unavailable on this server."
		end
		local queryOk, allowed, incidents, queryError = pcall(function()
			return endpoint:Invoke("Query", caller, targetUserId, queryLimit)
		end)
		if not queryOk or allowed ~= true or typeof(incidents) ~= "table" then
			return false, if typeof(queryError) == "string" then queryError else "Threat-intelligence query failed."
		end
		if #incidents == 0 then
			return true, if targetUserId then "No correlated review items for UserId " .. tostring(targetUserId) .. " on this server."
				else "No correlated threat-review items are currently retained on this server."
		end
		local lines = {"Tiki Tide Threat Intelligence (server-local review only):"}
		for index, item in ipairs(incidents) do
			if index > queryLimit then break end
			if typeof(item) == "table" then
				local age = if typeof(item.lastAt) == "number" then math.floor(math.max(0, os.clock() - item.lastAt)) else 0
				local categories = if typeof(item.categories) == "table" then table.concat(item.categories, ",") else "n/a"
				local signals = if typeof(item.signals) == "table" then table.concat(item.signals, ",") else "n/a"
				table.insert(lines, string.format("%s | UserId %d | %s confidence | score %d | %d events | %ds ago",
					tostring(item.id or "?"), typeof(item.subjectUserId) == "number" and item.subjectUserId or 0,
					tostring(item.confidence or "Low"), typeof(item.score) == "number" and item.score or 0,
					typeof(item.eventCount) == "number" and item.eventCount or 0, age))
				table.insert(lines, "  Categories: " .. string.sub(categories, 1, 180))
				table.insert(lines, "  Signals: " .. string.sub(signals, 1, 180))
			end
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1850)
	end
	if operation == "StaffSpectatorEnter" or operation == "StaffSpectatorSwitch" or operation == "StaffSpectatorExit" or operation == "StaffSpectatorState" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "GlobalModeration") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic administrator permission is required."
		end
		local endpoint = ServerStorage:FindFirstChild("TikiTideStaffSpectatorControl")
		if not endpoint or not endpoint:IsA("BindableFunction") or endpoint.Parent ~= ServerStorage then
			return false, "Staff observation is unavailable on this server."
		end
		local action = if operation == "StaffSpectatorEnter" then "Enter"
			elseif operation == "StaffSpectatorSwitch" then "SwitchTarget"
			elseif operation == "StaffSpectatorExit" then "Exit" else "GetState"
		local targetUserId: number? = nil
		if action == "Enter" or action == "SwitchTarget" then
			if typeof(argument) ~= "string" or #argument < 1 or #argument > 16
				or not string.match(argument, "^%d+$") then
				return false, if action == "Enter" then "Usage: ;cmspectate <UserId>" else "Usage: ;cmspectateswitch <UserId>"
			end
			targetUserId = tonumber(argument)
			if not targetUserId or targetUserId < 1 or targetUserId % 1 ~= 0 or targetUserId > 9007199254740991 then
				return false, "Provide a valid numeric Roblox UserId."
			end
		end
		local invokeOk, accepted, result = pcall(function()
			return endpoint:Invoke(action, caller.UserId, targetUserId)
		end)
		if not invokeOk or accepted ~= true then
			return false, if typeof(result) == "string" then result else "Staff observation request was rejected."
		end
		if action == "GetState" then
			if typeof(result) ~= "table" or result.active ~= true then return true, "Staff observation is not active." end
			return true, "Observing " .. tostring(result.targetName or "player") .. " (UserId " .. tostring(result.targetUserId or 0) .. ")."
		end
		return true, if typeof(result) == "string" then result else "Staff observation request completed."
	end
	if operation == "SecurityStatus" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "GlobalModeration") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic administrator permission is required."
		end
		local ok, status = ControllerFunctions.adminBridgeGlobalCall("GetGlobalSecurityStatus")
		if not ok or typeof(status) ~= "table" then return false, tostring(status or "Security status is unavailable.") end
		local lines = {"ClubMusic Global Security Status:"}
		for _, key in ipairs({"Authorization", "Monitor", "MessageValidation", "Idempotency", "IncidentResponse", "ThreatIntelligence"}) do
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
		local ok, incidents = ControllerFunctions.adminBridgeGlobalCall("GetGlobalSecurityIncidents", 8, caller.UserId)
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
	if operation == "SecurityThreatCaseOpen" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "IncidentResponse") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic incident-response permission is required."
		end
		if typeof(argument) ~= "string" or #argument < 5 or #argument > 24
			or not string.match(argument, "^TTI%-%d+$") then
			return false, "Usage: ;cmthreatcase <TTI-review-ID>"
		end
		local endpoint = ServerStorage:FindFirstChild("TikiTideThreatIntelligence")
		if not endpoint or not endpoint:IsA("BindableFunction") or endpoint.Parent ~= ServerStorage then
			return false, "Threat intelligence is unavailable on this server."
		end
		local queryOk, allowed, reviews, queryError = pcall(function()
			return endpoint:Invoke("Query", caller, nil, 30)
		end)
		if not queryOk or allowed ~= true or typeof(reviews) ~= "table" then
			return false, if typeof(queryError) == "string" then queryError else "Threat review lookup failed."
		end
		local selected = nil
		for _, item in ipairs(reviews) do
			if typeof(item) == "table" and item.id == argument then selected = item; break end
		end
		if not selected then return false, "That review item is no longer retained on this server." end
		local subjectUserId = selected.subjectUserId
		if typeof(subjectUserId) ~= "number" or subjectUserId < 1 or subjectUserId % 1 ~= 0 then
			return false, "A server-level review cannot be converted to a player incident."
		end
		local confidence = if selected.confidence == "High" then "High" else "Medium"
		local score = if typeof(selected.score) == "number" then math.clamp(math.floor(selected.score), 0, 1000000) else 0
		local signals = if typeof(selected.signals) == "table" then table.concat(selected.signals, ",") else "unavailable"
		local summary = string.sub("Threat review " .. argument .. " | " .. confidence
			.. " confidence | score " .. tostring(score) .. " | signals " .. signals, 1, 120)
		local openOk, incidentId = ControllerFunctions.adminBridgeGlobalCall(
			"OpenGlobalSecurityIncident", "ManualReview", summary, caller.UserId, subjectUserId)
		if not openOk then return false, tostring(incidentId or "Incident creation failed.") end
		return true, "Threat review converted to a ManualReview incident: " .. tostring(incidentId)
	end
	if operation == "SecurityIncidentOpen" then
		if not ControllerFunctions.adminBridgeAuthorize(caller, "IncidentResponse") then
			ControllerFunctions.adminBridgeReportSignal(caller, "admin_security_access_denied", operation)
			return false, "ClubMusic co-owner/owner permission is required."
		end
		if typeof(argument) ~= "string" or #argument < 4 or #argument > 200 then
			return false, "Usage: ;cmincident <SecurityAlert|ServiceDegraded|AbuseReport|ManualReview> <userId|server> <summary>"
		end
		local kind, subjectToken, summary = string.match(argument, "^(%a+)%s+(%S+)%s+(.+)$")
		local subjectUserId = if subjectToken == "server" then 0 else tonumber(subjectToken)
		if not kind or not subjectUserId or subjectUserId < 0 or subjectUserId % 1 ~= 0 or not summary or #summary > 180 then
			return false, "Provide an allowed incident type, a numeric userId (or server), and a summary."
		end
		local ok, incidentId = ControllerFunctions.adminBridgeGlobalCall("OpenGlobalSecurityIncident", kind, summary, caller.UserId, subjectUserId)
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
		PurchaseDiagnostics = "GlobalConfig",
		OperationalErrors = "GlobalConfig",
		OperationalMetrics = "GlobalModeration",
		OperationalSecurityLog = "IncidentResponse",
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
			"ClubMusic Local Health: %s | Dependencies: %s | Global service: %s | Recovery: %s\n%s",
			tostring(health.state or "Unknown"), tostring(health.localState or "Unknown"),
			tostring(health.serviceState or "Unknown"), tostring(health.recoveryState or "Unknown"),
			string.sub(tostring(health.detail or health.localDetail or ""), 1, 500)
		), 1, 1100)
	end
	if operation == "PurchaseDiagnostics" then
		local lines = {"Recent ClubMusic purchase events (latest server-local records):"}
		if #purchaseDiagnosticEntries == 0 then
			table.insert(lines, "No purchase prompt or receipt events have been recorded in this server yet.")
		else
			for index = math.max(1, #purchaseDiagnosticEntries - 11), #purchaseDiagnosticEntries do
				local item = purchaseDiagnosticEntries[index]
				table.insert(lines, string.format("%s | %s | UserId %d | ID %d | %s%s",
					os.date("!%H:%M:%S UTC", item.at), item.source, item.userId, item.itemId,
					item.outcome, if item.detail ~= "" then " | " .. item.detail else ""))
			end
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1700)
	end
	if operation == "OperationalDiagnostics" then
		local ok, snapshot = ControllerFunctions.adminBridgeGlobalCall("GetGlobalDiagnostics")
		if not ok or typeof(snapshot) ~= "table" then return false, tostring(snapshot or "Diagnostic snapshot is unavailable.") end
		local health = if typeof(snapshot.health) == "table" then snapshot.health else {}
		local recovery = if typeof(snapshot.recovery) == "table" then snapshot.recovery else {}
		local sync = if typeof(snapshot.syncStatus) == "table" then snapshot.syncStatus else {}
		local services = if typeof(snapshot.operationalServices) == "table" then snapshot.operationalServices else {}
		local watchdog = if typeof(services.watchdog) == "table" then services.watchdog else {}
		local watchdogIssues = if typeof(watchdog.issues) == "table" then watchdog.issues else {}
		local watchdogDetail = if #watchdogIssues > 0 then table.concat(watchdogIssues, " | ") else "none reported"
		local serverHealth = if typeof(services.serverHealth) == "table" then services.serverHealth else {}
		local heartbeat = if typeof(serverHealth.heartbeat) == "table" then serverHealth.heartbeat else {}
		local memory = if typeof(serverHealth.memory) == "table" then serverHealth.memory else {}
		local registry = if typeof(services.serviceRegistry) == "table" then services.serviceRegistry else {}
		local registryCounts = if typeof(registry.counts) == "table" then registry.counts else {}
		local healthTransitions = if typeof(health.healthHistory) == "table" then health.healthHistory else {}
		local latestHealthTransition = if #healthTransitions > 0 and typeof(healthTransitions[#healthTransitions]) == "table"
			then healthTransitions[#healthTransitions] else {}
		local errorHistory = if typeof(services.errorHistory) == "table" then services.errorHistory else {}
		local securityHealth = if typeof(services.securityHealth) == "table" then services.securityHealth else {}
		local securityComponents = if typeof(securityHealth.components) == "table" then securityHealth.components else {}
		local observabilityHealth = if typeof(services.observabilityHealth) == "table" then services.observabilityHealth else {}
		local adaptiveLoad = if typeof(services.adaptiveLoad) == "table" then services.adaptiveLoad else {}
		local adaptiveTaskStats = if typeof(adaptiveLoad.taskStats) == "table" then adaptiveLoad.taskStats else {}
		local function adaptiveUsage(name: string): string
			local item = if typeof(adaptiveTaskStats[name]) == "table" then adaptiveTaskStats[name] else {}
			return tostring(item.accepted or 0) .. "/" .. tostring(item.deferred or 0)
		end
		local securityReplay = if typeof(services.securityReplay) == "table" then services.securityReplay else {}
		local safeCall = if typeof(services.safeCall) == "table" then services.safeCall else {}
		local threatIntelligence = if typeof(services.threatIntelligence) == "table" then services.threatIntelligence else {}
		local honeypot = if typeof(services.honeypot) == "table" then services.honeypot else {}
		local clientIntegrity = if typeof(services.clientIntegrityTelemetry) == "table" then services.clientIntegrityTelemetry else {}
		local controller = if typeof(services.controller) == "table" then services.controller else {}
		local purchase = if typeof(controller.purchase) == "table" then controller.purchase else {}
		local moderation = if typeof(controller.moderation) == "table" then controller.moderation else {}
		local controllerPlayback = if typeof(controller.playback) == "table" then controller.playback else {}
		local securityMonitor = if typeof(services.securityMonitor) == "table" then services.securityMonitor else {}
		local resourceGuard = if typeof(securityMonitor.resourceGuard) == "table" then securityMonitor.resourceGuard else {}
		local resourceLanes = if typeof(resourceGuard.lanes) == "table" then resourceGuard.lanes else {}
		local writeLane = if typeof(resourceLanes.MemoryStoreWrite) == "table" then resourceLanes.MemoryStoreWrite else {}
		local readLane = if typeof(resourceLanes.MemoryStoreRead) == "table" then resourceLanes.MemoryStoreRead else {}
		local auditStatus = if typeof(services.audit) == "table" then services.audit else {}
		local storageGuard = if typeof(auditStatus.storageGuard) == "table" then auditStatus.storageGuard else {}
		local characterPhysics = if typeof(services.characterPhysics) == "table" then services.characterPhysics else {}
		local clientTelemetry = if typeof(snapshot.clientTelemetry) == "table" then snapshot.clientTelemetry else {}
		local _, globalOperational = ControllerFunctions.adminBridgeGlobalCall("GetGlobalOperationalStatus")
		local messaging = if typeof(globalOperational) == "table" and typeof(globalOperational.Messaging) == "table" then globalOperational.Messaging else {}
		local memoryStore = if typeof(services.memoryStore) == "table" then services.memoryStore else {}
		local lines = {
			"ClubMusic Diagnostic Snapshot:",
			"Generated: " .. os.date("!%Y-%m-%d %H:%M:%S UTC", tonumber(snapshot.generatedAt) or os.time()),
			"Global enabled: " .. tostring(snapshot.serviceEnabled == true),
			"Local health: " .. tostring(health.state or "Unavailable") .. " / " .. tostring(health.localState or "Unavailable"),
			"Health dimensions: cross-server " .. tostring(health.crossServerState or "Unavailable")
				.. " | performance " .. tostring(health.performanceState or "Unavailable")
				.. " | watchdog " .. tostring(health.watchdogState or "Unavailable"),
			"Health trend: state age " .. tostring(health.stateDurationSeconds or 0) .. "s"
				.. " | degraded duration " .. tostring(health.degradedDurationSeconds or 0) .. "s"
				.. " | consecutive degraded checks " .. tostring(health.consecutiveDegradedChecks or 0)
				.. " | transitions retained " .. tostring(#healthTransitions) .. "/" .. tostring(health.healthHistoryCapacity or 20)
				.. " | last recovery " .. tostring(health.lastRecoveredAt or "none"),
			"Last health transition: " .. tostring(latestHealthTransition.from or "n/a")
				.. " -> " .. tostring(latestHealthTransition.to or "n/a")
				.. " | " .. tostring(latestHealthTransition.detail or "No transition recorded."),
			"Server runtime: " .. tostring(serverHealth.state or "NotInstalled")
				.. " | average FPS " .. tostring(if typeof(heartbeat.averageFps) == "number" then math.floor(heartbeat.averageFps + 0.5) else "n/a")
				.. " | max frame " .. tostring(math.floor((tonumber(heartbeat.maxFrameMilliseconds) or 0) * 10) / 10) .. "ms"
				.. " | Memory " .. tostring(memory.usageMb or "n/a") .. " MB (" .. tostring(memory.state or "n/a") .. ")"
				.. " | trend " .. tostring(memory.changeSinceOldestSampleMb or "n/a") .. " MB",
			"Service registry: " .. tostring(registry.state or "NotInstalled")
				.. " | total " .. tostring(registry.serviceCount or 0)
				.. " | healthy " .. tostring(registryCounts.Healthy or 0)
				.. " | degraded " .. tostring(registryCounts.Degraded or 0)
				.. " | unavailable " .. tostring(registryCounts.Unavailable or 0)
				.. " | misconfigured " .. tostring(registryCounts.Misconfigured or 0)
				.. " | verified dependencies " .. tostring(registry.dependencyCount or 0),
			"Recovery: " .. tostring(recovery.state or "Unavailable"),
			"Watchdog: " .. tostring(watchdog.state or "Unavailable"),
			"Observability: " .. tostring(observabilityHealth.state or "Unavailable")
				.. " | Adaptive load " .. tostring(adaptiveLoad.mode or adaptiveLoad.state or "NotInstalled")
				.. " | Replay " .. tostring(securityReplay.state or "NotInstalled")
				.. " (" .. tostring(securityReplay.retained or 0) .. "/" .. tostring(securityReplay.capacity or 0) .. ")",
			"Adaptive load trend: mode duration " .. tostring(math.floor((tonumber(adaptiveLoad.currentModeDurationSeconds) or 0) + 0.5)) .. "s"
				.. " | healthy recovery windows " .. tostring(adaptiveLoad.recoveryHealthyWindowStreak or adaptiveLoad.healthyStreak or 0)
				.. " | transitions " .. tostring(adaptiveLoad.transitions or 0)
				.. " | reason " .. string.sub(tostring(adaptiveLoad.lastTransitionReason or "n/a"), 1, 100),
			"Adaptive accepted/deferred (Analytics/Diagnostics/Replay/Threat/Maintenance): "
				.. adaptiveUsage("AnalyticsAggregation") .. " / " .. adaptiveUsage("DiagnosticsSampling") .. " / "
				.. adaptiveUsage("ReplayQueries") .. " / " .. adaptiveUsage("ThreatReviewQueries") .. " / "
				.. adaptiveUsage("BackgroundMaintenance"),
			"SafeCall: " .. tostring(safeCall.calls or 0) .. " calls | failures "
				.. tostring(safeCall.failures or 0) .. " | recovered " .. tostring(safeCall.recovered or 0),
			"Threat intelligence: " .. tostring(threatIntelligence.state or "NotInstalled")
				.. " | review items " .. tostring(threatIntelligence.openReviewItems or 0)
				.. "/" .. tostring(threatIntelligence.maxReviewItems or 0)
				.. " | tracked subjects " .. tostring(threatIntelligence.trackedSubjects or 0),
			"Honeypot: " .. tostring(honeypot.state or "NotInstalled")
				.. " | hits " .. tostring(honeypot.totalHits or 0)
				.. " | suppressed " .. tostring(honeypot.suppressedHits or 0)
				.. " | decoys " .. tostring(honeypot.decoyRemoteCount or 0),
			"Client integrity telemetry: " .. tostring(clientIntegrity.state or "NotInstalled")
				.. " | accepted " .. tostring(clientIntegrity.acceptedReports or 0)
				.. " | rejected " .. tostring(clientIntegrity.rejectedReports or 0)
				.. " | duplicate " .. tostring(clientIntegrity.duplicateReports or 0)
				.. " | untrusted=true; enforcement=false",
			"SecurityCore health: " .. tostring(securityHealth.state or "Unavailable")
				.. " (" .. tostring(securityHealth.observedComponents or 0) .. "/" .. tostring(securityHealth.totalComponents or 0) .. " observed)"
				.. " | Auth " .. tostring(securityComponents.authorization or "Unavailable")
				.. " | RateLimit " .. tostring(securityComponents.rateLimit or "Unavailable")
				.. " | Validation " .. tostring(securityComponents.messageValidation or "Unavailable")
				.. " | Audit " .. tostring(securityComponents.audit or "Unavailable")
				.. " | Incidents " .. tostring(securityComponents.incidentResponse or "Unavailable")
				.. " | Physics " .. tostring(securityComponents.characterPhysics or "Unavailable"),
			"Watchdog detail: " .. string.sub(watchdogDetail, 1, 300),
			"Error history: " .. tostring(errorHistory.count or 0) .. "/" .. tostring(errorHistory.maxRecords or 50)
				.. " records | repeats " .. tostring(errorHistory.totalRepeats or 0),
			"Messaging: " .. tostring(messaging.state or "Unavailable")
				.. " | published " .. tostring(messaging.published or 0)
				.. " | failures " .. tostring(messaging.publishFailures or 0)
				.. " | received " .. tostring(messaging.received or 0)
				.. " | rejected " .. tostring(messaging.rejected or 0),
			"MemoryStore limiter fallback: " .. tostring(memoryStore.capacityLimited == true),
			"Purchase: receipts " .. tostring(purchase.receiptCallbacks or 0)
				.. " | granted " .. tostring(purchase.granted or 0)
				.. " | pending " .. tostring(purchase.pending or 0)
				.. " | failures " .. tostring(purchase.failures or 0)
				.. " | duplicates " .. tostring(purchase.duplicates or 0),
			"Moderation lookups: " .. tostring(moderation.totalLookups or 0)
				.. " | success " .. tostring(moderation.successfulLookups or 0)
				.. " | failed/pending " .. tostring(moderation.failedLookups or 0),
			"Playback: " .. tostring(controllerPlayback.backend or "Unavailable")
				.. " | playing " .. tostring(controllerPlayback.playing == true)
				.. " | paused " .. tostring(controllerPlayback.paused == true)
				.. " | queue " .. tostring(controllerPlayback.queueDepth or 0)
				.. " | migration failures " .. tostring(controllerPlayback.migrationFailureCount or 0),
			"Security signals: " .. tostring(securityMonitor.totalSignals or 0)
				.. " | alerts " .. tostring(securityMonitor.alerts or 0)
				.. " | physics " .. tostring(characterPhysics.totalSignals or 0),
			"Movement observation: interval " .. tostring(if typeof(characterPhysics.movementMeasurement) == "table" then characterPhysics.movementMeasurement.sampleIntervalSeconds or "n/a" else "n/a")
				.. "s | samples " .. tostring(if typeof(characterPhysics.movementMeasurement) == "table" then characterPhysics.movementMeasurement.samples or 0 else 0)
				.. " | deferred " .. tostring(if typeof(characterPhysics.movementMeasurement) == "table" then characterPhysics.movementMeasurement.deferredSamples or 0 else 0)
				.. " | detection-only",
			"Resource guards: write " .. tostring(writeLane.active or 0) .. "/" .. tostring(writeLane.limit or 0)
				.. " rejected " .. tostring(writeLane.rejected or 0)
				.. " | read " .. tostring(readLane.active or 0) .. "/" .. tostring(readLane.limit or 0)
				.. " rejected " .. tostring(readLane.rejected or 0)
				.. " | storage circuit open " .. tostring(storageGuard.circuitOpen == true)
				.. " failures " .. tostring(storageGuard.failuresInWindow or 0),
			"Client performance telemetry: " .. tostring(clientTelemetry.state or "Unavailable")
				.. " | local-only, untrusted, not transmitted",
			"Client integrity reports are untrusted dependency observations; absence is not proof of tampering.",
			"Purchase telemetry: " .. tostring(#purchaseDiagnosticEntries) .. " recent server-local event(s):",
		}
		for index = math.max(1, #purchaseDiagnosticEntries - 3), #purchaseDiagnosticEntries do
			local item = purchaseDiagnosticEntries[index]
			table.insert(lines, string.format("Purchase %s | ID %d | %s | %s",
				item.source, item.itemId, item.outcome, string.sub(item.detail, 1, 90)))
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1900)
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
		if not ok or typeof(snapshot) ~= "table" then return false, "Diagnostic status is unavailable." end
		local services = if typeof(snapshot.operationalServices) == "table" then snapshot.operationalServices else {}
		local history = if typeof(services.errorHistory) == "table" then services.errorHistory else {}
		if snapshot.errorHistoryAvailable ~= true then
			return true, "Server-local ErrorHistory is unavailable. Detailed records remain server-side."
		end
		return true, string.format(
			"Server-local ErrorHistory: %s/%s records retained | %s total unique errors | %s repeated occurrences. Error messages and tracebacks are not sent to clients.",
			tostring(history.count or 0), tostring(history.maxRecords or 50),
			tostring(history.totalErrors or 0), tostring(history.totalRepeats or 0))
	end
	if operation == "OperationalMetrics" then
		local ok, metrics = ControllerFunctions.adminBridgeGlobalCall("GetGlobalMetrics")
		if not ok or typeof(metrics) ~= "table" then return false, tostring(metrics or "Metrics are unavailable or disabled.") end
		if metrics.state == "Deferred" or metrics.deferred == true then
			return true, "ClubMusic Metrics (Deferred): Optional analytics aggregation is temporarily paused by the current server-load budget. Health monitoring and security services remain active."
		end
		local aggregate = if typeof(metrics.aggregate) == "table" then metrics.aggregate else {}
		local counters = if typeof(aggregate.counters) == "table" then aggregate.counters else {}
		local structuredCounters = if typeof(metrics.counters) == "table" then metrics.counters else {}
		local keys = {}
		for key in pairs(counters) do table.insert(keys, tostring(key)) end
		table.sort(keys)
		local lines = {"ClubMusic Metrics (" .. tostring(metrics.state or "Unknown") .. "):"}
		for index = 1, math.min(#keys, 12) do
			local key = keys[index]
			local detail = structuredCounters[key]
			if typeof(detail) == "table" then
				table.insert(lines, key .. " = " .. tostring(counters[key])
					.. " | success " .. tostring(detail.successCount or 0)
					.. " | failure " .. tostring(detail.failureCount or 0)
					.. " | last " .. tostring(detail.lastOutcome or "Observed"))
			else
				table.insert(lines, key .. " = " .. tostring(counters[key]))
			end
		end
		if #keys == 0 then table.insert(lines, "No aggregated counters are available yet.") end
		return true, string.sub(table.concat(lines, "\n"), 1, 1400)
	end
	if operation == "OperationalSecurityLog" then
		local ok, entries = ControllerFunctions.adminBridgeGlobalCall("GetGlobalAudit", 30, caller.UserId)
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
adminBridge.OnInvoke = adminBridgeCallback

-- Do not leave a stale callback closure callable if this controller Script is
-- removed or replaced. Clear only the exact callback owned by this instance.
script.Destroying:Connect(function()
	adminBridgeShuttingDown = true
	if adminBridge.Parent == ServerStorage and adminBridge.OnInvoke == adminBridgeCallback then
		adminBridge.OnInvoke = nil
	end
end)

-- Construct the remaining optional child managers only after controller state exists.
-- Playback quality is now inspected directly from the canonical modern AudioPlayer snapshot.
ControllerFunctions.ChildManagers = {}


ControllerFunctions.castSkipVote = function(player: Player): (boolean, string)
	if player.Parent ~= Players then return false, "A connected player is required." end
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
end

-- Optional DJ session facade. It is loaded from either supported ServerStorage
-- layout and never grants staff roles or changes queue/playback ownership.
local djSessionModule = ControllerFunctions.findAudioModule("ClubMusicDJSessionManager")
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
			print("[ClubMusic][DJSession] Manager initialized successfully; DJ session commands are available.")
		else
			warn("[ClubMusic][DJSession] Optional manager initialization failed: " .. tostring(djSessionManager))
		end
	else
		warn("[ClubMusic][DJSession] Optional module failed validation/load: " .. tostring(djSessionClass))
	end
else
	warn("[ClubMusic][DJSession] Optional ClubMusicDJSessionManager ModuleScript was not found under ServerStorage or ServerStorage.ClubMusicAudioModules. DJ session commands are unavailable.")
end

-- Load the optional crossfade coordinator after controller state and all child
-- managers exist. Construction creates no deck and does not change live output;
-- an explicit controller call is still required to begin a transition.
do
	local crossfadeOk, crossfadeError = ControllerFunctions.createAudioCrossfadeManager()
	if not crossfadeOk then
		warn("[ClubMusic][Crossfade] Coordinator unavailable; modern AudioPlayer remains the only playback source: " .. tostring(crossfadeError))
	else
		print("[ClubMusic][Crossfade] Coordinator initialized (inactive until explicitly requested).")
	end
end

remotes:SetAttribute("StartupStage", "BindingHandlers")
actionRemote.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
	if serverShuttingDown then return end
	if typeof(action) ~= "string" or #action < 1 or #action > 32 then
		local replay = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
		if replay and replay:IsA("BindableFunction") then
			pcall(function()
				replay:Invoke("Record", "clubmusic_remote_invalid_action", player.UserId, 0,
					"Warning", "ClubMusicRemote", {actionType = typeof(action)})
			end)
		end
	end
	local isPlaybackControl = action == "DJPause" or action == "DJRestart" or action == "DJSkip"
	if isPlaybackControl then
		print("[ClubMusic][PlaybackControl] Request received; action=" .. tostring(action) .. "; player=" .. player.Name)
	end
	local ok, accepted, result = pcall(ControllerFunctions.handleAction, player, action, payload)
	if not ok then
		local replay = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
		if replay and replay:IsA("BindableFunction") then
			pcall(function()
				replay:Invoke("Record", "clubmusic_remote_handler_error", player.UserId, 0,
					"Warning", "ClubMusicRemote", {actionType = typeof(action)})
			end)
		end
		warn("[ClubMusic] Action handler error: " .. tostring(accepted))
	elseif isPlaybackControl then
		print("[ClubMusic][PlaybackControl] Handler result; action=" .. tostring(action)
			.. "; accepted=" .. tostring(accepted) .. "; detail=" .. tostring(result))
	end
end)
remotes:SetAttribute("StartupStage", "Ready")
remotes:SetAttribute("Ready", true)

-- Releases this server's profile lease after the final save. Ownership is checked
-- inside UpdateAsync so a stale server cannot clear a newer server's lease.
ControllerFunctions.releaseProfileSession = function(userId: number)
	if USE_STUDIO_MEMORY_PROFILES then
		return
	end
	-- Lease release shares the same local writer lock as saves and receipt commits.
	-- Otherwise a receipt transaction could be interrupted between its durable
	-- profile marker and journal completion by a concurrent departure release.
	local writeLockToken = ControllerFunctions.acquireProfileWriteLock(userId)
	if not writeLockToken then
		warn("[ClubMusic] Could not acquire profile writer lock for lease release; lease will expire naturally for userId " .. tostring(userId))
		return
	end
	if not ControllerFunctions.waitForDataStoreBudget(3) then
		ControllerFunctions.releaseProfileWriteLock(userId, writeLockToken)
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
	ControllerFunctions.releaseProfileWriteLock(userId, writeLockToken)
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

-- Roblox-native ban history is separate from Tiki Tide's custom moderation store.
-- This API is production-only and may yield/fail when Roblox services are unavailable.
ControllerFunctions.checkNativeBanHistory = function(player: Player)
	if RunService:IsStudio() then return end
	local ok, banned, displayReason = pcall(function()
		local pages = Players:GetBanHistoryAsync(player.UserId)
		local currentPage = pages:GetCurrentPage()
		local latestRecord = nil
		local latestTimestamp = -math.huge
		for _, record in ipairs(currentPage) do
			if typeof(record) == "table" and typeof(record.StartTime) == "string"
				and typeof(record.Ban) == "boolean" then
				local parsed = DateTime.fromIsoDate(record.StartTime)
				local timestamp = parsed.UnixTimestamp
				if timestamp > latestTimestamp then
					latestTimestamp = timestamp
					latestRecord = record
				end
			end
		end
		if not latestRecord or latestRecord.Ban ~= true then return false, nil end
		local duration = latestRecord.Duration
		if typeof(duration) ~= "number" then error("Ban history returned an invalid duration") end
		if duration == -1 then
			return true, latestRecord.DisplayReason
		end
		if duration <= 0 then return false, nil end
		local expiresAt = latestTimestamp + duration
		return expiresAt > os.time(), latestRecord.DisplayReason
	end)
	if not ok then
		warn("[Tiki Tide][NativeBanLookup] Roblox ban history unavailable for UserId "
			.. tostring(player.UserId) .. ": " .. tostring(banned))
		return
	end
	if banned == true and player.Parent == Players then
		local reason = if typeof(displayReason) == "string" and #displayReason > 0
			then displayReason else "You are banned from this experience."
		player:Kick(reason)
	end
end

-- PlayerAdded and the startup GetPlayers sweep can overlap. Make join
-- initialization idempotent for the lifetime of this Player instance.
local onJoinStarted: {[Player]: boolean} = {}

ControllerFunctions.onJoin = function(player: Player)
	if player.Parent ~= Players or onJoinStarted[player] then return end
	onJoinStarted[player] = true
	task.spawn(ControllerFunctions.checkNativeBanHistory, player)
	local enabledCallOk, globalServiceEnabled = ControllerFunctions.globalInvoke("IsEnabled")
	if player.Parent ~= Players then return end
	local globalModerationRequired = not RunService:IsStudio()
	local globalServiceReady = enabledCallOk and globalServiceEnabled == true
	-- A service-readiness failure is not a ban. Keep moderation-sensitive actions
	-- closed and retry authoritative checks instead of kicking legitimate players.
	-- Fetch ban and request-block status together to avoid serial durable reads.
	local moderationCallOk, moderationLookupOk, globallyBanned, globallyBlocked, _moderationReason, moderationRevision =
		ControllerFunctions.globalInvoke("GetModerationState", player.UserId)
	if player.Parent ~= Players then return end
	local knownModerationRevision = ControllerFunctions.moderationRevisions
		and ControllerFunctions.moderationRevisions[player.UserId] or 0
	if moderationCallOk and moderationLookupOk == true
		and (not ControllerFunctions.isFiniteNumber(moderationRevision) or moderationRevision < knownModerationRevision) then
		-- A cross-server invalidation arrived while this yielding lookup was in flight.
		-- Its newer revision wins; keep the player restricted until a current read succeeds.
		moderationLookupOk = false
	elseif moderationCallOk and moderationLookupOk == true then
		ControllerFunctions.moderationRevisions = ControllerFunctions.moderationRevisions or {}
		ControllerFunctions.moderationRevisions[player.UserId] = moderationRevision
	end
	local moderationVerified = not globalModerationRequired or (moderationCallOk and moderationLookupOk == true)
	if globalModerationRequired then
		recordModerationDiagnostic("Join", moderationCallOk and moderationLookupOk == true,
			globallyBanned == true, globallyBlocked == true)
	end
	ControllerFunctions.recordDiagnosticPulse("Moderation",
		if not globalModerationRequired then "studio-local-moderation-isolated"
		elseif moderationVerified then "join-moderation-verified" else "join-moderation-lookup-failed",
		moderationVerified, {lookupSucceeded = moderationCallOk and moderationLookupOk == true})
	if moderationCallOk and moderationLookupOk == true then
		if globallyBanned == true then
			player:Kick("You are globally banned from this experience.")
			return
		end
		blockedUsers[player.UserId] = if globallyBlocked == true then true else nil
	elseif globalModerationRequired then
		-- Unknown remains restricted; a failed read never grants requests or kicks.
		blockedUsers[player.UserId] = true
	end
	local retryModeration = globalModerationRequired and
		(not globalServiceReady or not moderationCallOk or moderationLookupOk ~= true)
	if retryModeration then player:SetAttribute("GlobalModerationPending", true) end
	if retryModeration then
		task.spawn(function()
			local serviceResolved = globalServiceReady
			local moderationResolved = not retryModeration
			local attempt = 0
			-- Stable per-user staggering prevents simultaneous joins from retrying
			-- the shared DataStore bucket on identical backoff boundaries.
			local retryJitter = 0.85 + ((player.UserId % 31) / 100)
			while player.Parent == Players and not (serviceResolved and moderationResolved) do
				attempt += 1
				-- The initial join checks already ran immediately. If a backend was still
				-- loading, retry quickly instead of imposing a five-second blind lock;
				-- increase the interval only when the service continues to fail.
				local retryBaseDelay = if attempt == 1 then 1 else math.min(15, 2 ^ math.min(attempt - 1, 4))
				local retryDelay = math.min(15, retryBaseDelay * retryJitter)
				task.wait(retryDelay)
				if player.Parent ~= Players then return end
				if not serviceResolved then
					local callOk, enabled = ControllerFunctions.globalInvoke("IsEnabled")
					if player.Parent ~= Players then return end
					serviceResolved = callOk and enabled == true
				end
				if not moderationResolved then
					local callOk, lookupOk, banned, blocked, _reason, revision =
						ControllerFunctions.globalInvoke("GetModerationState", player.UserId)
					if player.Parent ~= Players then return end
					local latestRevision = ControllerFunctions.moderationRevisions
						and ControllerFunctions.moderationRevisions[player.UserId] or 0
					if callOk and lookupOk == true
						and (not ControllerFunctions.isFiniteNumber(revision) or revision < latestRevision) then
						lookupOk = false
					end
					recordModerationDiagnostic("Retry", callOk and lookupOk == true, banned == true, blocked == true)
					if callOk and lookupOk == true then
						ControllerFunctions.moderationRevisions = ControllerFunctions.moderationRevisions or {}
						ControllerFunctions.moderationRevisions[player.UserId] = revision
						ControllerFunctions.recordDiagnosticPulse("Moderation", "moderation-retry-verified", true,
							{lookupSucceeded = true})
						moderationResolved = true
						if banned == true then
							player:Kick("You are globally banned from this experience.")
							return
						end
						blockedUsers[player.UserId] = if blocked == true then true else nil
					end
				end
				if moderationResolved and serviceResolved then
					player:SetAttribute("GlobalModerationPending", false)
					publishState(nil)
					return
				end
			end
			-- If the player leaves, the loop exits. Unknown moderation state never
			-- grants requests or triggers a kick; checks continue with bounded backoff.
		end)
	end
	ControllerFunctions.refreshRank(player)
	ControllerFunctions.refreshVip(player)
	ControllerFunctions.refreshPersonalPasses(player)
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
				placeholder = catalogTrack.placeholder,
			}
			nextTracks[track.id] = track
			table.insert(nextIds, track.id)
		end
		table.sort(nextIds)
		-- A remote catalog removal must invalidate every local queue reference too.
		-- Release request slots for removed tracks; surviving player requests retain
		-- their existing order and the per-server queue remains authoritative.
		local removedQueuedTrack = false
		if typeof(pendingCrossfadeEntry) == "table"
			and typeof(pendingCrossfadeEntry.trackId) == "string"
			and nextTracks[pendingCrossfadeEntry.trackId] == nil then
			ControllerFunctions.cancelPreparedCrossfadeForTrack(pendingCrossfadeEntry.trackId, "catalog-track-removed")
		end
		for index = #queue, 1, -1 do
			local entry = queue[index]
			if typeof(entry) == "table" and typeof(entry.trackId) == "string"
				and nextTracks[entry.trackId] == nil then
				queueManager:RemoveAt(index, true)
				removedQueuedTrack = true
			end
		end

		table.clear(TRACK_BY_ID)
		for id, track in pairs(nextTracks) do TRACK_BY_ID[id] = track end
		table.clear(ALL_TRACK_IDS)
		for _, id in ipairs(nextIds) do table.insert(ALL_TRACK_IDS, id) end

		-- Catalog invalidation can remove tracks referenced by an active playlist.
		-- Rebuild only this server's playable view; saved IDs/order remain untouched.
		local activePlaylistChanged = false
		if activePlaylistId then
			local previousPlaylistId = activePlaylistId
			local previousPlaylistName = activePlaylistName
			local previousTrackIds = {}
			for _, track in ipairs(activePlaylistTracks) do table.insert(previousTrackIds, track.id) end
			ControllerFunctions.reloadActivePlaylist()
			activePlaylistChanged = previousPlaylistId ~= activePlaylistId
				or previousPlaylistName ~= activePlaylistName
				or #previousTrackIds ~= #activePlaylistTracks
			if not activePlaylistChanged then
				for index, track in ipairs(activePlaylistTracks) do
					if previousTrackIds[index] ~= track.id then activePlaylistChanged = true; break end
				end
			end
		end
		if activePlaylistChanged then ControllerFunctions.clearAutomaticQueue() end
		if activePlaylistChanged or removedQueuedTrack then ControllerFunctions.topUpAuto() end

		refreshed = true
	end)
	catalogRefreshBusy = false
	if not ok then warn("[ClubMusic] Catalog refresh failed: " .. tostring(err)) end
	if refreshed then
		lastCatalogRefreshAt = os.clock()
		publishState(nil)
	end
	return refreshed
end

-- Playback-only sync messages carry snapshot invalidations, never queue contents.
ControllerFunctions.handleGlobalMessage = function(message: any)
	if typeof(message) ~= "table" then return end
	if message.kind == "TrackModeration" and typeof(message.trackId) == "string" and typeof(message.blocked) == "boolean" then
		if message.senderJob == game.JobId then return end
		ControllerFunctions.blockedTrackCache = ControllerFunctions.blockedTrackCache or {}
		ControllerFunctions.blockedTrackCache[message.trackId] = {blocked = message.blocked, checkedAt = os.clock()}
		if message.blocked ~= true then return end
		ControllerFunctions.cancelPreparedCrossfadeForTrack(message.trackId, "track-blocked-global")
		for index = #queue, 1, -1 do
			if queue[index].trackId == message.trackId then queueManager:RemoveAt(index, true) end
		end
		if nowPlaying.trackId == message.trackId then
			ControllerFunctions.cancelAudioTransition("track-blocked-global")
			ControllerFunctions.advance()
		end
		publishState(nil)
		return
	end
	if message.kind == "Catalog" then
		-- Track moderation shares the catalog topic so one durable update can
		-- invalidate both the custom catalog and per-server moderation decisions.
		-- MessagingService delivery is best-effort; the local 300-second cache
		-- expiry remains the fallback when this invalidation is missed.
		if message.senderJob ~= game.JobId
			and typeof(message.trackId) == "string"
			and #message.trackId >= 1 and #message.trackId <= 64
			and string.match(message.trackId, "^[%w%-_]+$")
			and typeof(message.blocked) == "boolean" then
			ControllerFunctions.blockedTrackCache = ControllerFunctions.blockedTrackCache or {}
			ControllerFunctions.blockedTrackCache[message.trackId] = {
				blocked = message.blocked,
				checkedAt = os.clock(),
			}
			if message.blocked == true then
				ControllerFunctions.cancelPreparedCrossfadeForTrack(message.trackId, "track-blocked-global")
				for index = #queue, 1, -1 do
					if queue[index].trackId == message.trackId then queueManager:RemoveAt(index, true) end
				end
				if nowPlaying.trackId == message.trackId then
					ControllerFunctions.cancelAudioTransition("track-blocked-global")
					ControllerFunctions.advance()
				end
				publishState(nil)
			end
		end
		if os.clock() - lastCatalogRefreshAt < 3 then return end
		task.spawn(function()
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
	if message.kind == "ModerationReconcile" and ControllerFunctions.isFiniteNumber(message.userId)
		and message.userId > 0 and message.userId % 1 == 0 and message.userId <= 9007199254740991
		and typeof(message.globalBan) == "boolean" and typeof(message.requestBlocked) == "boolean"
		and ControllerFunctions.isFiniteNumber(message.revision) and message.revision >= 0
		and message.revision % 1 == 0 then
		local revisions = ControllerFunctions.moderationRevisions
			or (function() ControllerFunctions.moderationRevisions = {}; return ControllerFunctions.moderationRevisions end)()
		local target = Players:GetPlayerByUserId(message.userId)
		local knownRevision = if target then (revisions[message.userId] or 0) else message.revision
		-- Reconciliation snapshots may equal the last event revision: they contain
		-- both durable flags and repair state after a missed notification.
		if target and message.revision >= knownRevision then
			revisions[message.userId] = message.revision
			if message.globalBan then
				target:Kick("You are globally banned from this experience.")
			else
				blockedUsers[message.userId] = if message.requestBlocked then true else nil
				if message.requestBlocked then ControllerFunctions.purgeUserEntries(message.userId) end
				target:SetAttribute("GlobalModerationPending", false)
				publishState(nil)
			end
		end
		return
	end
	if message.kind == "Moderation" and ControllerFunctions.isFiniteNumber(message.userId)
		and message.userId > 0 and message.userId % 1 == 0 and message.userId <= 9007199254740991
		and (message.field == "globalBan" or message.field == "requestBlocked")
		and typeof(message.value) == "boolean" and ControllerFunctions.isFiniteNumber(message.revision)
		and message.revision >= 1 and message.revision % 1 == 0 then
		local revisions = ControllerFunctions.moderationRevisions
			or (function() ControllerFunctions.moderationRevisions = {}; return ControllerFunctions.moderationRevisions end)()
		local target = Players:GetPlayerByUserId(message.userId)
		local knownRevision = if target then (revisions[message.userId] or 0) else message.revision
		if target and message.revision > knownRevision then
			revisions[message.userId] = message.revision
			if message.field == "globalBan" and message.value == true then
				if target then target:Kick("You are globally banned from this experience.") end
			elseif message.field == "requestBlocked" then
				if message.value then
					blockedUsers[message.userId] = true
					ControllerFunctions.purgeUserEntries(message.userId)
				else
					blockedUsers[message.userId] = nil
				end
			end
			publishState(nil)
		end
		return
	end
end

local connectedGlobalEvents: {[any]: any} = {}

-- Keep bridge connections owned by this controller and reconnect when the
-- optional Global Service recreates its API folder or GlobalEvent BindableEvent.
-- This registry avoids extra top-level locals in the controller's large chunk.
connectedGlobalEvents.detachEvent = function()
	local connection = connectedGlobalEvents.eventConnection
	connectedGlobalEvents.eventConnection = nil
	connectedGlobalEvents.currentEvent = nil
	if connection then pcall(function() connection:Disconnect() end) end
end

connectedGlobalEvents.attachGlobalEvent = function(folder: Folder, eventObject: Instance?)
	if connectedGlobalEvents.currentFolder ~= folder then return end
	if not eventObject or not eventObject:IsA("BindableEvent") then
		connectedGlobalEvents.detachEvent()
		return
	end
	local event = eventObject :: BindableEvent
	if connectedGlobalEvents.currentEvent == event then return end
	connectedGlobalEvents.detachEvent()
	connectedGlobalEvents.currentEvent = event
	connectedGlobalEvents.eventConnection = event.Event:Connect(function(...)
		-- Ignore callbacks from a removed/replaced API generation.
		if connectedGlobalEvents.currentFolder == folder
			and connectedGlobalEvents.currentEvent == event
			and folder.Parent == ServerStorage and event.Parent == folder then
			ControllerFunctions.handleGlobalMessage(...)
		end
	end)
end

connectedGlobalEvents.unwatchGlobalApi = function(folder: Instance)
	if connectedGlobalEvents.currentFolder ~= folder then return end
	connectedGlobalEvents.detachEvent()
	local childConnection = connectedGlobalEvents.folderChildAdded
	local removedConnection = connectedGlobalEvents.folderChildRemoved
	connectedGlobalEvents.folderChildAdded = nil
	connectedGlobalEvents.folderChildRemoved = nil
	if childConnection then pcall(function() childConnection:Disconnect() end) end
	if removedConnection then pcall(function() removedConnection:Disconnect() end) end
	connectedGlobalEvents.currentFolder = nil
	if globalApi == folder then globalApi = nil end
end

connectedGlobalEvents.watchGlobalApi = function(folder: Instance)
	if not folder:IsA("Folder") or folder.Parent ~= ServerStorage then return end
	if connectedGlobalEvents.currentFolder == folder then
		connectedGlobalEvents.attachGlobalEvent(folder, folder:FindFirstChild("GlobalEvent"))
		return
	end
	local previousFolder = connectedGlobalEvents.currentFolder
	if previousFolder then connectedGlobalEvents.unwatchGlobalApi(previousFolder) end
	globalApi = folder
	connectedGlobalEvents.currentFolder = folder
	connectedGlobalEvents.attachGlobalEvent(folder, folder:FindFirstChild("GlobalEvent"))
	connectedGlobalEvents.folderChildAdded = folder.ChildAdded:Connect(function(child)
		if child.Name == "GlobalEvent" then connectedGlobalEvents.attachGlobalEvent(folder, child) end
	end)
	connectedGlobalEvents.folderChildRemoved = folder.ChildRemoved:Connect(function(child)
		if child == connectedGlobalEvents.currentEvent then connectedGlobalEvents.detachEvent() end
	end)
end

connectedGlobalEvents.serverChildAdded = ServerStorage.ChildAdded:Connect(function(child)
	if child.Name == "ClubMusicGlobalAPI" and child:IsA("Folder") then
		connectedGlobalEvents.watchGlobalApi(child)
	end
end)
connectedGlobalEvents.serverChildRemoved = ServerStorage.ChildRemoved:Connect(function(child)
	if child == connectedGlobalEvents.currentFolder then connectedGlobalEvents.unwatchGlobalApi(child) end
end)

if globalApi and globalApi:IsA("Folder") and globalApi.Parent == ServerStorage then
	connectedGlobalEvents.watchGlobalApi(globalApi)
end

script.Destroying:Connect(function()
	local folder = connectedGlobalEvents.currentFolder
	if folder then connectedGlobalEvents.unwatchGlobalApi(folder) end
	for _, key in ipairs({"serverChildAdded", "serverChildRemoved"}) do
		local connection = connectedGlobalEvents[key]
		connectedGlobalEvents[key] = nil
		if connection then pcall(function() connection:Disconnect() end) end
	end
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
	-- Permanent personal XP ownership multiplies the globally boosted award.
	-- The client never supplies this value; it comes from server-verified pass ownership.
	local personalMultiplier = math.clamp(tonumber(player:GetAttribute("PersonalXPMultiplier")) or 1, 1, 4)
	local fractional = (xpFractional[userId] or 0) + weightedSeconds * personalMultiplier * (CONFIG.XPPerMinute / 60)
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
ControllerFunctions.startDanceFloorRewards()

Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	onJoinStarted[player] = nil
	if ControllerFunctions.moderationRevisions then ControllerFunctions.moderationRevisions[userId] = nil end
	if djControlModeEnabled and djControlModeUserId == userId then
		djControlModeEnabled = false
		djControlModeUserId = nil
		ControllerFunctions.broadcast("DJ Control Mode ended because the current DJ controller left. Normal player requests are open again.", "info")
		publishState(nil)
	end
	filteredTitleTextByUserId[userId] = nil
	lastCustomTitleTextAt[userId] = nil
	local djSessionManager = ControllerFunctions.ChildManagers and ControllerFunctions.ChildManagers.DJSession
	if djSessionManager then
		local endedSession = djSessionManager:EndForDeparture(userId)
		if endedSession then player:SetAttribute("ClubMusicActiveDJSession", false) end
	end
	if settleAllXP then ControllerFunctions.settlePlayerXP(player, os.clock()) end
	xpLastAwardAt[userId] = nil
	xpFractional[userId] = nil
	xpLastSaveAt[userId] = nil
	local finalSaveOk = if serverShuttingDown
		then ControllerFunctions.saveProfile(player, 8, 6)
		else ControllerFunctions.saveProfile(player)
	if finalSaveOk and not serverShuttingDown then
		ControllerFunctions.releaseProfileSession(userId)
	else
		-- Keep the lease until it expires naturally. Clearing it after a failed
		-- save could let another server load stale profile data immediately.
		warn("[ClubMusic] Final profile save failed; retaining session lease until expiry for userId " .. tostring(userId))
	end
	local departingProfile = profiles[userId]
	if receiptTransactions then receiptTransactions:ForgetProfile(departingProfile) end
	profiles[userId] = nil
	-- Do not clear profileWriteLocks here. A timed-out save/receipt operation may
	-- still be in flight; its owner releases its own token when it actually ends.
	-- A rapid same-server rejoin must wait rather than overlap that old writer.
	requestCounts[userId] = nil
	lastRequestAt[userId] = nil
	lastActionAt[userId] = nil
	lastAdminActionAt[userId] = nil
	lastActionByType[userId] = nil
	lastAdminActionByType[userId] = nil
	perPlayerActionBuckets[userId] = nil
	saveQueued[userId] = nil
	saveAgain[userId] = nil
	saveQueueTokens[userId] = nil
	lastStateInvoke[userId] = nil
	lastCatalogInvoke[userId] = nil
	lastPlaylistInvoke[userId] = nil
	pendingStatePlayers[userId] = nil
	lastAudioInspection[userId] = nil
	lastReloadAt[userId] = nil
	reloadNonce[userId] = nil
	pendingAudio[userId] = nil
	if entitlementAuthority then pcall(entitlementAuthority.Clear, entitlementAuthority, player) end
	blockedUsers[userId] = nil
	skipVotes[userId] = nil
	-- The leaving player may still be counted by GetPlayers(); re-check next frame.
	task.defer(function()
		if ControllerFunctions.checkSkipVotes() then ControllerFunctions.broadcast("Track skipped by vote.", "ok") end
		publishState(nil)
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(ControllerFunctions.onJoin, player)
end

-- Refresh purchased membership entitlements after a successful in-session purchase.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	if not purchased then return end
	local isMembershipPass = passId == CONFIG.VipGamePassId or passId == CONFIG.VvipGamePassId or passId == CONFIG.TikiTidePassId
	local isNewFeaturePass = passId == CONFIG.PersonalXP2xPassId or passId == CONFIG.PersonalXP4xPassId
		or passId == CONFIG.MountPassId or passId == CONFIG.CompanionPassId or passId == CONFIG.StageClubLightingPassId
	if not isMembershipPass and not isNewFeaturePass then return end
	task.spawn(function()
		if player.Parent ~= Players then return end
		if isNewFeaturePass then ControllerFunctions.refreshPersonalPasses(player) end
		if player.Parent ~= Players then return end
		if isMembershipPass then ControllerFunctions.refreshVip(player, true) end
		if player.Parent ~= Players then return end
		if isMembershipPass then
			ControllerFunctions.applyVipAttribute(player)
			ControllerFunctions.syncTitleTagUnlocks(player)
			local tierName = if ControllerFunctions.hasTikiTideAccess(player) then "Tiki Tide" elseif ControllerFunctions.isVvip(player) then "VVIP" elseif ControllerFunctions.isVip(player) then "VIP" else "Pass"
			notify(player, tierName .. " unlocked! Your perks are now active.", "ok")
		else
			notify(player, "Your new Game Pass entitlement is active.", "ok")
		end
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
	while not serverShuttingDown do
		task.wait(CONFIG.SaveIntervalSeconds)
		if serverShuttingDown then break end
		for _, player in ipairs(Players:GetPlayers()) do
			if serverShuttingDown then break end
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
-- resyncs. A single server-owned AudioPlayer graph replicates the active track to everyone; CONFIG.SoundIds
-- supplies optional built-in track audio, while staff-requested Creator Hub audio is validated
-- before it can enter the queue.
task.spawn(function()
	local ticks = 0
	while true do
		task.wait(1)
		if not playbackPaused and not audioReloadInProgress then
			nowPlaying.elapsed += 1
		end
		ticks += 1
		ControllerFunctions.recordDiagnosticPulse("Playback", "playback-clock-tick", true, {
			trackId = nowPlaying.trackId,
			queueDepth = #queue,
			elapsed = nowPlaying.elapsed,
		})
		if ticks % 30 == 0 then
			ControllerFunctions.recordDiagnosticPulse("Queue", "queue-state-sampled", true, {queueDepth = #queue})
			ControllerFunctions.recordDiagnosticPulse("AutoDJ",
				if autoQueueHold then "refill-held" else "queue-target-sampled",
				autoQueueHold or #queue >= CONFIG.AutoQueueTarget,
				{queueDepth = #queue, target = CONFIG.AutoQueueTarget})
		end

		local currentGeneration = playbackGeneration
		local shouldAdvance = not playbackPaused and not audioReloadInProgress and nowPlaying.trackId ~= ""
			and nowPlaying.elapsed >= nowPlaying.duration
		-- Catalog tracks without a configured SoundId are intentionally silent
		-- UI/visualizer entries. Do not treat their intentionally absent audio as a failed
		-- asset: let their catalog duration drive the normal transition instead.
		-- A transient IsPlaying=false must not be treated as end-of-track.
		-- Require a short stable stop, then attempt one in-place resume from the
		-- captured playhead before allowing the queue watchdog to advance.
		local audio = ControllerFunctions.getAudioSnapshot()
		if playbackPaused or audioReloadInProgress or nowPlaying.trackId == "" or nowPlaying.soundId == ""
			or audio.playing == true then
			ControllerFunctions.stoppedAudioGeneration = -1
			ControllerFunctions.stoppedAudioSince = 0
			ControllerFunctions.audioRecoveryAttemptedGeneration = -1
		elseif not audioReloadInProgress and not shouldAdvance and nowPlaying.elapsed >= 15 then
			local now = os.clock()
			if ControllerFunctions.stoppedAudioGeneration ~= currentGeneration then
				ControllerFunctions.stoppedAudioGeneration = currentGeneration
				ControllerFunctions.stoppedAudioSince = now
				ControllerFunctions.audioRecoveryAttemptedGeneration = -1
			end
			local stoppedFor = math.max(0, now - ControllerFunctions.stoppedAudioSince)
			local loadedAndKnownLength = audio.ready and audio.length > 0
			local playheadAtEnd = loadedAndKnownLength
				and audio.position >= math.max(0, audio.length - 1.5)
			if stoppedFor >= 2 and not playheadAtEnd and loadedAndKnownLength
				and ControllerFunctions.audioRecoveryAttemptedGeneration ~= currentGeneration then
				ControllerFunctions.audioRecoveryAttemptedGeneration = currentGeneration
				local resumePosition = math.clamp(audio.position, 0, math.max(0, audio.length - 0.25))
				local seekOk, seekResult = pcall(ControllerFunctions.seekAudio, resumePosition)
				local playOk, playResult = false, false
				if seekOk and seekResult ~= false then
					playOk, playResult = pcall(ControllerFunctions.playAudio)
				end
				local recoveredAudio = playOk and playResult ~= false
				ControllerFunctions.recordDiagnosticPulse("Recovery",
					if recoveredAudio then "audio-resume-recovered" else "audio-resume-failed",
					recoveredAudio, {generation = currentGeneration})
				if not recoveredAudio then
					warn("[ClubMusic] Playback watchdog could not resume the stopped track at its saved playhead.")
				end
			elseif (playheadAtEnd and stoppedFor >= 2)
				or (ControllerFunctions.audioRecoveryAttemptedGeneration == currentGeneration and stoppedFor >= 7)
				or (not loadedAndKnownLength and nowPlaying.elapsed >= 45) then
				local quality = ControllerFunctions.inspectPlaybackQuality()
				local reason = if typeof(quality) == "table" then tostring(quality.state or "Unknown") else "WatchdogStoppedTrack"
				shouldAdvance = true
				warn("[ClubMusic] Playback watchdog confirmed an ended or unrecoverable track (" .. reason .. "); advancing safely.")
				if ControllerFunctions.ErrorHandler then
					local errorContext: Instance? = nil
					pcall(function()
						local source = activeAudioSource
						if source.kind == "Backend" and source.backend then
							errorContext = source.backend:GetPlayer()
						end
					end)
					ControllerFunctions.ErrorHandler.Report("PlaybackQuality", "StoppedTrack", reason, errorContext or SoundService)
				end
			end
		end

		-- This server prepares its own next local queue entry before the current
		-- track ends; the crossfade commit advances only this server's queue.
		if not playbackPaused and not audioReloadInProgress and nowPlaying.trackId ~= ""
			and nowPlaying.soundId ~= "" and nowPlaying.elapsed < nowPlaying.duration then
			local remaining = nowPlaying.duration - nowPlaying.elapsed
			local managers = ControllerFunctions.ChildManagers
			local crossfade = managers and managers.Crossfade
			local nextEntry = queue[1]
			local nextAsset = if typeof(nextEntry) == "table"
				then (nextEntry.soundId or CONFIG.SoundIds[nextEntry.trackId] or "") else ""
			local validNextAsset = typeof(nextAsset) == "string" and #nextAsset <= 64
				and string.match(nextAsset, "^rbxassetid://%d+$") ~= nil
			-- Start preparation any time before the track ends. The coordinator itself waits
			-- until the fade window; a strict duration-plus-one gate can miss the window
			-- when the one-second playback clock lands exactly on its boundary.
			if crossfade and not crossfade.destroyed and not crossfade.active
				and crossfadeAttemptedGeneration ~= currentGeneration
				and remaining <= CONFIG.CrossfadePrepareLeadSeconds
				and remaining > 0
				and typeof(nextEntry) == "table" and validNextAsset
				and ControllerFunctions.getAudioSnapshot().playing == true then
				crossfadeAttemptedGeneration = currentGeneration
				pendingCrossfadeEntry = nextEntry
				pendingCrossfadeToken = audioTransitionTrackToken
				local started, startError = ControllerFunctions.beginAudioCrossfade(nextAsset, CONFIG.CrossfadeDurationSeconds)
				if not started then
					pendingCrossfadeEntry = nil
					pendingCrossfadeToken = -1
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
	-- Freeze new profile-save scheduling and receipt ingress before taking the
	-- final snapshot. Existing receipt callbacks retain their shared writer lock.
	serverShuttingDown = true
	adminBridgeShuttingDown = true
	local shutdownDeadline = os.clock() + 27

	-- Cancel delayed/coalesced saves; the shutdown pass below writes the latest
	-- profile snapshots directly and does not depend on task.delay callbacks.
	for _, player in ipairs(Players:GetPlayers()) do
		local userId = player.UserId
		saveQueueTokens[userId] = nil
		saveQueued[userId] = nil
		saveAgain[userId] = nil
	end

	-- Give authoritative receipt transactions a short opportunity to finish
	-- their profile+journal sequence. If one remains active, its writer lock
	-- prevents a conflicting final save; the durable pending marker/journal
	-- remains recoverable by Roblox's receipt retry on another server.
	local receiptDrainDeadline = math.min(shutdownDeadline - 16, os.clock() + 5)
	while activeReceiptCallbacks > 0 and os.clock() < receiptDrainDeadline do
		task.wait(0.05)
	end
	if activeReceiptCallbacks > 0 then
		warn("[ClubMusic][ReceiptAuthority] Shutdown deadline reached while receipt callbacks remained active; unacknowledged receipts will be retried.")
	end

	-- Cancel first so an interrupted fade restores the controller-owned outgoing
	-- source before the active backend is stopped and retired.
	ControllerFunctions.destroyAudioCrossfadeManager("server-shutdown")
	local shutdownSource = activeAudioSource
	if shutdownSource and shutdownSource.kind == "Backend" and shutdownSource.backend then
		pcall(function() shutdownSource.backend:Stop() end)
		retireAudioBackend(shutdownSource.backend, "server shutdown active source")
	end
	if not drainRetiredAudioBackends("server shutdown") then
		warn("[ClubMusic][AudioBackend] One or more retired backends remain pending after final shutdown cleanup.")
	end

	-- Studio memory mode has no durable profile backend and never acquires a
	-- DataStore session lease. PlayerRemoving may already have cleared the
	-- in-memory profile while the player is still briefly returned by GetPlayers().
	-- There is therefore nothing to persist or release during Studio shutdown.
	if USE_STUDIO_MEMORY_PROFILES then
		return
	end

	local playersToSave = Players:GetPlayers()
	local completed = 0
	local results: {[number]: boolean} = {}
	for _, player in ipairs(playersToSave) do
		local userId = player.UserId
		task.spawn(function()
			local remaining = math.max(0, shutdownDeadline - os.clock())
			local lockTimeout = math.min(8, math.max(0, remaining - 7))
			local budgetTimeout = math.min(6, math.max(0, remaining - lockTimeout - 1))
			local saved = false
			if profiles[userId] ~= nil then
				saved = ControllerFunctions.saveProfile(player, lockTimeout, budgetTimeout) == true
			end
			results[userId] = saved
			if not saved and profiles[userId] ~= nil then
				warn("[ClubMusic] Shutdown save failed or exceeded its bounded wait; retaining profile lease until expiry for userId " .. tostring(userId))
			end
			completed += 1
		end)
	end

	while completed < #playersToSave and os.clock() < shutdownDeadline do
		task.wait(0.05)
	end
	if completed < #playersToSave then
		warn(string.format("[ClubMusic] Shutdown save deadline reached; completed %d/%d profile saves. Unreleased leases will expire naturally.",
			completed, #playersToSave))
	end
	-- Do not release session leases from BindToClose. PlayerRemoving may be
	-- concurrently saving/releasing the same user, and an interrupted shutdown
	-- save must never make an unconfirmed snapshot available to another server.
end)
