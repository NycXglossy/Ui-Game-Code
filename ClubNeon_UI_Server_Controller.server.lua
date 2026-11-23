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

local ServerStorage = game:GetService("ServerStorage")
-- Preserve the established lowercase alias used by legacy controller sections.
local serverStorage = ServerStorage
local projectConfigModule = ServerStorage:WaitForChild("ClubNeon_Config", 20)
if not projectConfigModule or not projectConfigModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_Config; controller will not start.")
end
local projectConfig = require(projectConfigModule)
assert(typeof(projectConfig) == "table" and typeof(projectConfig.Permissions) == "table"
	and typeof(projectConfig.Monetization) == "table" and typeof(projectConfig.Storage) == "table",
	"[Club Neon] Invalid project configuration; controller will not start.")
local permissions = projectConfig.Permissions
local passes = projectConfig.Monetization.GamePasses
local products = projectConfig.Monetization.DeveloperProducts
local storage = projectConfig.Storage
local monetizationEnabled = projectConfig.Monetization.Enabled == true
local function paidId(value: any): number
	if not monetizationEnabled then return 0 end
	local id = tonumber(value) or 0
	return if id > 0 and id % 1 == 0 then id else 0
end
local rawDonations = if typeof(products.Donations) == "table" then products.Donations else {}
local CONFIG = {
	GroupId = tonumber(permissions.GroupId) or 0,
	RankThresholds = permissions.RankThresholds,
	StaffUserIds = permissions.OwnerUserIds,
	RoleUserIds = {
		Owner = permissions.OwnerUserIds, CoOwner = permissions.CoOwnerUserIds,
		Admin = permissions.AdminUserIds, Moderator = permissions.ModeratorUserIds, DJ = permissions.DJUserIds,
	},
	StudioStaff = permissions.StudioOwnerBypass == true,
	VipGamePassId = paidId(passes.VIP),
	VvipGamePassId = paidId(passes.VVIP),
	ClubNeonPassId = paidId(passes.Elite),
	VipPriority = true,
	MaxRequestsPerPlayer = 2, VipMaxRequestsPerPlayer = 4, VvipMaxRequestsPerPlayer = 6,
	ClubNeonMaxRequestsPerPlayer = 8, RequestCooldownSeconds = 8, VipCooldownSeconds = 3,
	VvipCooldownSeconds = 2, ClubNeonCooldownSeconds = 1, MaxQueueSize = 40,
	AutoQueueTarget = 3, AutoAvoidRecent = 6, SkipVoteRatio = 0.5, SkipVoteMin = 2,
	MaxFavorites = 60, ResyncSeconds = 5, ReloadCooldownSeconds = 3,
	DataStoreName = storage.ProfileStore, SaveIntervalSeconds = 90, StudioUseDataStore = false,
	UseModernAudioBackend = true, EnableGlobalPlaybackSync = false,
	CrossfadeDurationSeconds = 4, CrossfadePrepareLeadSeconds = 14,
	SoundIds = {} :: {[string]: string},
	AudioMaxSeconds = 600, AudioLoadTimeoutSeconds = 8, MaxConcurrentAudioInspections = 2,
	AudioInspectionCooldownSeconds = 10, GetStateCooldownSeconds = 0.75, SaveTitleCooldownSeconds = 2,
	GlobalActionBurst = 180, GlobalActionRefillPerSecond = 90, PerPlayerActionBurst = 18,
	PerPlayerActionRefillPerSecond = 12, GlobalAudioBurst = 3, GlobalAudioRefillPerSecond = 0.25,
	GlobalStateMinIntervalSeconds = 0.2, ProfileWriteLockTimeoutSeconds = 12,
	ProfileSaveQueueDelaySeconds = 0.25, XPPerMinute = 10, XPPerLevel = 100,
	XPBoost2xProductId = paidId(products.XPBoost2x),
	XPBoost4xProductId = paidId(products.XPBoost4x),
	PersonalXP2xPassId = paidId(passes.PersonalXP2x),
	PersonalXP4xPassId = paidId(passes.PersonalXP4x),
	MountPassId = paidId(passes.IslandMount),
	CompanionPassId = paidId(passes.Companion),
	StageClubLightingPassId = paidId(passes.StageLighting),
	GlobalDataStoreBurst = 30, GlobalDataStoreRefillPerSecond = 3,
	RestrictAudioToAllowlist = false, AllowedAudioAssetIds = {} :: {number},
	TitleSlotProductIds = { [2] = paidId(products.TitleSlot2), [3] = paidId(products.TitleSlot3) } :: {[number]: number},
	DonationProductIds = {
		Coconut = paidId(rawDonations.Coconut), Pineapple = paidId(rawDonations.Pineapple),
		NeonTorch = paidId(rawDonations.NeonTorch), Volcano = paidId(rawDonations.Volcano),
		IslandLegend = paidId(rawDonations.IslandLegend), IslandRoyalty = paidId(rawDonations.IslandRoyalty),
		ClubNeonLegacy = paidId(rawDonations.ClubNeonLegacy),
	},
	TitleSlotPrices = { [2] = 99, [3] = 199 } :: {[number]: number},
}


-- Catalog diagnostics run asynchronously and never gate controller startup.
local marketplaceDiagnosticsModule = ServerStorage:FindFirstChild("ClubNeon_MarketplaceDiagnostics")
if not marketplaceDiagnosticsModule or not marketplaceDiagnosticsModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_MarketplaceDiagnostics; controller will not start.")
end
require(marketplaceDiagnosticsModule)({
	MarketplaceService = MarketplaceService,
	CONFIG = CONFIG,
	Enum = Enum,
})

-- Publish the remote contract before loading storage modules so clients can
-- wait safely even when catalog initialization is delayed.
-- The catalog is server-owned. The controller remains the only authority
-- for request limits, moderation, queue priority, and playback.
local bootstrapHelpersModule = ServerStorage:FindFirstChild("ClubNeon_ControllerBootstrap")
if not bootstrapHelpersModule or not bootstrapHelpersModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_ControllerBootstrap; controller will not start.")
end
local bootstrapHelpers = require(bootstrapHelpersModule)(ServerStorage)
ControllerFunctions.getOrCreate = bootstrapHelpers.getOrCreate
ControllerFunctions.findAudioModule = bootstrapHelpers.findAudioModule
ControllerFunctions.findServerStorageModule = bootstrapHelpers.findServerStorageModule

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

-- Purchase and moderation telemetry is isolated in a server-local service.
local purchaseDiagnosticRemote = ControllerFunctions.getOrCreate(remotes, "RemoteEvent", "PurchaseDiagnostic") :: RemoteEvent
local purchaseDiagnosticsModule = ServerStorage:FindFirstChild("ClubNeon_PurchaseDiagnostics")
if not purchaseDiagnosticsModule or not purchaseDiagnosticsModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_PurchaseDiagnostics; controller will not start.")
end
local purchaseDiagnostics = require(purchaseDiagnosticsModule)({
	Players = Players,
	CONFIG = CONFIG,
	PurchaseDiagnosticRemote = purchaseDiagnosticRemote,
})
-- Resolve optional audio modules in either supported installation layout:
--   ServerStorage/ClubMusicAudioModules/<ModuleScript>
--   ServerStorage/<ModuleScript>
-- Folder layout takes precedence when both copies exist, avoiding accidental
-- mixing of two independently installed module sets.


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


remotes:SetAttribute("StartupStage", "LoadingMusicCoreService")
local coreModule = ControllerFunctions.findServerStorageModule("MusicCoreService")
remotes:SetAttribute("StartupStage", "LoadingMusicPlaylistService")
local playlistModule = ControllerFunctions.findServerStorageModule("MusicPlaylistService")
if not coreModule or not coreModule:IsA("ModuleScript") then
	remotes:SetAttribute("StartupError", "Missing ServerStorage.MusicCoreService ModuleScript.")
	error("[ClubMusic] Missing ServerStorage.MusicCoreService ModuleScript.")
end
if not playlistModule or not playlistModule:IsA("ModuleScript") then
	remotes:SetAttribute("StartupError", "Missing ServerStorage.MusicPlaylistService ModuleScript.")
	error("[ClubMusic] Missing ServerStorage.MusicPlaylistService ModuleScript.")
end
local coreRequireOk, coreRequireResult = pcall(require, coreModule)
if not coreRequireOk then
	remotes:SetAttribute("StartupError", "MusicCoreService require failed: " .. string.sub(tostring(coreRequireResult), 1, 180))
	error("[ClubMusic] MusicCoreService failed to load: " .. tostring(coreRequireResult))
end
local playlistRequireOk, playlistRequireResult = pcall(require, playlistModule)
if not playlistRequireOk then
	remotes:SetAttribute("StartupError", "MusicPlaylistService require failed: " .. string.sub(tostring(playlistRequireResult), 1, 180))
	error("[ClubMusic] MusicPlaylistService failed to load: " .. tostring(playlistRequireResult))
end
if typeof(coreRequireResult) ~= "table"
	or typeof(coreRequireResult.Catalog) ~= "table"
	or typeof(coreRequireResult.Validation) ~= "table"
	or typeof(coreRequireResult.Queue) ~= "table"
	or typeof(coreRequireResult.Validation.new) ~= "function"
	or typeof(coreRequireResult.Queue.new) ~= "function" then
	remotes:SetAttribute("StartupError", "MusicCoreService returned an invalid interface.")
	error("[ClubMusic] MusicCoreService returned an invalid interface.")
end
local MusicCoreService = coreRequireResult
local MusicCatalogService = MusicCoreService.Catalog
local MusicValidationService = MusicCoreService.Validation
local MusicQueueManager = MusicCoreService.Queue
local MusicPlaylistService = playlistRequireResult
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
	vip = true, party = true, wave = true, neon = true, sunset = true, bass = true, island = true,
}

-- Server-owned title validation palettes and allowlists are staged as a focused data module.
local titleValidationDataModule = ServerStorage:FindFirstChild("ClubNeon_TitleValidationData")
if not titleValidationDataModule or not titleValidationDataModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_TitleValidationData; controller will not start.")
end
local titleValidationData = require(titleValidationDataModule)
local TITLE_COLORS = titleValidationData.TITLE_COLORS
local TITLE_STYLES = titleValidationData.TITLE_STYLES
local TITLE_SETS = titleValidationData.TITLE_SETS
local TITLE_FONTS = titleValidationData.TITLE_FONTS
local TITLE_HEX = titleValidationData.TITLE_HEX
local RAINBOW_PARAMS = titleValidationData.RAINBOW_PARAMS
local RGB_SPEED = titleValidationData.RGB_SPEED

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
local audioState: {[string]: any} = {
	activeAudioSource = { kind = "Unavailable" },
	audioSourceRevision = 0,
	modernBackendStartSucceeded = false,
	modernBackendStartFailureCount = 0,
	modernAudioStartToken = 0,
	playbackPaused = false,
	audioReloadInProgress = false,
	audioTransitionTrackToken = 0,
}
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

-- legacy group migration and setup
-- Publish the number of active controller-owned main outputs (0 or 1).
-- The binding is refreshed whenever the canonical source changes.
-- AudioBackendManager owns the modern source contract and recovery lifecycle.
local audioBackendManager: any = nil

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
				local trim = audioBackendManager.GetTrackVolumeTrim(incomingTrackId)
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
			if audioState.activeAudioSource.kind ~= "Backend" or not audioState.activeAudioSource.backend then
				error("Crossfade requires the modern AudioPlayer backend; no legacy Sound fallback is available.")
			end
			transitionOutgoing = audioState.activeAudioSource
			transitionRevision = audioState.audioSourceRevision
			local ok, value = ControllerFunctions.getAudioGain(transitionOutgoing)
			if not ok then error("Outgoing audio gain is unavailable.") end
			ControllerFunctions.crossfadeOutgoingBaseGain = value
			return value
		end,
		SetOutgoingGain = function(value: number)
			if not transitionOutgoing or transitionOutgoing.kind ~= "Backend" or not transitionOutgoing.backend
				or audioState.activeAudioSource ~= transitionOutgoing or audioState.audioSourceRevision ~= transitionRevision then return false end
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
				or audioState.activeAudioSource ~= outgoing or audioState.audioSourceRevision ~= transitionRevision or audioState.playbackPaused
				or not entry or pendingCrossfadeToken ~= audioState.audioTransitionTrackToken then
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

			audioState.activeAudioSource = { kind = "Backend", backend = incoming }
			local bindOk = pcall(ControllerFunctions.bindActiveAudioPlayingSignal)
			if not bindOk then
				audioState.activeAudioSource = outgoing
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
				audioState.activeAudioSource = outgoing
				pcall(ControllerFunctions.bindActiveAudioPlayingSignal)
				if outgoingWasPlaying then
					pcall(function()
						outgoing.backend:Play(nil, outgoingPosition)
					end)
				end
				return false
			end
			audioState.audioSourceRevision += 1
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
				audioBackendManager.RetireBackend(outgoing.backend, "crossfade outgoing commit")
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
	if audioState.playbackPaused then return false, "Cannot crossfade while playback is paused." end
	if audioState.activeAudioSource.kind ~= "Backend" or not audioState.activeAudioSource.backend then
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


audioBackendManager = require(ServerStorage:WaitForChild("ClubNeon_AudioBackendManager"))({
	ControllerFunctions = ControllerFunctions,
	SoundService = SoundService,
	CONFIG = CONFIG,
	state = audioState,
	getNowPlaying = function() return nowPlaying end,
})

-- Optional cross-server service bridge. The UI remains functional if this separate
-- service is disabled or temporarily unavailable; the server's local security remains active.
remotes:SetAttribute("StartupStage", "LoadingReceiptHash")
local receiptSecurityCore = ServerStorage:FindFirstChild("ClubNeonSecurityCore")
local receiptHashModule = receiptSecurityCore and receiptSecurityCore:FindFirstChild("ReceiptHash")
if not receiptHashModule or not receiptHashModule:IsA("ModuleScript") then
	remotes:SetAttribute("StartupError", "Missing ServerStorage.ClubNeonSecurityCore.ReceiptHash ModuleScript.")
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

local studioXpBoostMultiplier = 1
local studioXpBoostExpiresAt = 0


local xpServiceModule = ServerStorage:FindFirstChild("ClubNeon_XPService")
if not xpServiceModule or not xpServiceModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_XPService; controller will not start.")
end
local xpService = require(xpServiceModule)({
	Players = Players,
	CONFIG = CONFIG,
	RunService = RunService,
	ControllerFunctions = ControllerFunctions,
	profiles = profiles,
	publishState = function(player: Player?) publishState(player) end,
	getStudioBoostState = function() return studioXpBoostMultiplier, studioXpBoostExpiresAt end,
})
ControllerFunctions.setGlobalXPState = xpService.SetGlobalXPState
ControllerFunctions.refreshGlobalXPBoost = xpService.RefreshGlobalXPBoost
ControllerFunctions.settlePlayerXP = xpService.SettlePlayerXP

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
remotes:SetAttribute("StartupStage", "UsingMusicCoreQueue")
if typeof(MusicQueueManager) ~= "table" or typeof(MusicQueueManager.new) ~= "function" then
	local detail = "MusicCoreService.Queue must return a table with a .new() constructor."
	ControllerFunctions.reportStartupError("ModuleLoader", "Validate MusicCoreService queue", detail, coreModule)
	error("[ClubMusic] " .. detail)
end
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

-- Rate-limit buckets are isolated in a server-only module. The buckets remain
-- local to this server instance; no cross-server coordination is introduced.
local rateLimitModule = ServerStorage:FindFirstChild("ClubNeon_RateLimitBuckets")
assert(rateLimitModule and rateLimitModule:IsA("ModuleScript"), "ClubNeon_RateLimitBuckets is required")
local RateLimitBuckets = require(rateLimitModule)
local rateLimitBuckets = RateLimitBuckets.create(CONFIG)
ControllerFunctions.newTokenBucket = rateLimitBuckets.newTokenBucket
ControllerFunctions.consumeToken = rateLimitBuckets.consumeToken
ControllerFunctions.waitForDataStoreBudget = rateLimitBuckets.waitForDataStoreBudget
ControllerFunctions.consumeActionBudget = rateLimitBuckets.consumeActionBudget
local globalActionBucket = rateLimitBuckets.globalActionBucket
local globalAudioBucket = rateLimitBuckets.globalAudioBucket
local globalStateQueryBucket = rateLimitBuckets.globalStateQueryBucket
local globalCatalogQueryBucket = rateLimitBuckets.globalCatalogQueryBucket
local globalDataStoreBucket = rateLimitBuckets.globalDataStoreBucket
local perPlayerActionBuckets = rateLimitBuckets.perPlayerActionBuckets

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



local sanityValidationService: any = nil

local ACTION_COOLDOWNS: {[string]: number} = {
	RequestTrack = 0.5, RequestAudioAsset = CONFIG.AudioInspectionCooldownSeconds,
	ReloadSong = CONFIG.ReloadCooldownSeconds, ToggleFavorite = 0.2, VoteSkip = 0.5,
	CatalogAddAudio = 10, CatalogRemoveTrack = 2,
	PlaylistCreate = 2, PlaylistDelete = 1, PlaylistAddTrack = 0.5, PlaylistRemoveTrack = 0.5, PlaylistMoveTrack = 0.5,
	DJPlayPlaylist = 2, DJStopPlaylist = 1,
	DJMoveUp = 0.2, DJRemove = 0.2, DJSkip = 0.5, DJPause = 0.5, DJRestart = 1, DJClearQueue = 1, DJToggleLock = 1,
	DJToggleGlobalPlaybackSync = 1.5,
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

local profileWriteLocksModule = ServerStorage:FindFirstChild("ClubNeon_ProfileWriteLocks")
if not profileWriteLocksModule or not profileWriteLocksModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_ProfileWriteLocks; controller will not start.")
end
local profileWriteLocksService = require(profileWriteLocksModule)({
	locks = profileWriteLocks,
	timeoutLimit = CONFIG.ProfileWriteLockTimeoutSeconds,
})
ControllerFunctions.acquireProfileWriteLock = profileWriteLocksService.acquire
ControllerFunctions.releaseProfileWriteLock = profileWriteLocksService.release

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
	local core = ServerStorage:FindFirstChild("ClubNeonSecurityCore")
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
	local core = ServerStorage:FindFirstChild("ClubNeonSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("Authorization") else nil
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.GetShared) == "function" then
			local sharedOk, instance = pcall(exported.GetShared, {
				groupId = CONFIG.GroupId,
				studioStaff = CONFIG.StudioStaff,
				staffUserIds = CONFIG.StaffUserIds,
				roleUserIds = CONFIG.RoleUserIds,
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
	local core = ServerStorage:FindFirstChild("ClubNeonSecurityCore")
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
					local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
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
	local core = ServerStorage:FindFirstChild("ClubNeonSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("EntitlementAuthority") else nil
	if module and module:IsA("ModuleScript") and authorizationService then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new, {
				authorization = authorizationService,
				passIds = {
					vip = CONFIG.VipGamePassId,
					vvip = CONFIG.VvipGamePassId,
					elite = CONFIG.ClubNeonPassId,
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
	local core = ServerStorage:FindFirstChild("ClubNeonSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("AvatarAccessoryValidationService") else nil
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new, {
				onSignal = function(signal: string, subject: number, detail: string)
					local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
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
					warn("[Club Neon][AvatarValidation] " .. tostring(signal)
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
					warn("[Club Neon][AvatarValidation] Startup failed: " .. tostring(started))
					avatarAccessoryValidation = nil
				end
			end
		end
	end
	if not avatarAccessoryValidation then
		warn("[Club Neon][AvatarValidation] Detection service unavailable; avatar checks are not active.")
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
	local core = ServerStorage:FindFirstChild("ClubNeonSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("AnimationIntegrityService") else nil
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new, {
				onSignal = function(signal: string, subject: number, detail: string, metadata: {[string]: any})
					local severity = if string.find(signal, "_cap", 1, true) then "Warning" else "Info"
					local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
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
					warn("[Club Neon][AnimationIntegrity] Startup failed: " .. tostring(started))
					animationIntegrityService = nil
				end
			end
		end
	end

	local existingStatus = ServerStorage:FindFirstChild("GetClubNeonAnimationIntegrityStatus")
	if existingStatus and existingStatus:IsA("BindableFunction") then
		animationIntegrityStatus = existingStatus
	elseif not existingStatus then
		animationIntegrityStatus = Instance.new("BindableFunction")
		animationIntegrityStatus.Name = "GetClubNeonAnimationIntegrityStatus"
		animationIntegrityStatus.Parent = ServerStorage
	else
		warn("[Club Neon][AnimationIntegrity] Status endpoint has the wrong class; status endpoint was not replaced.")
	end
	if animationIntegrityStatus then
		animationIntegrityStatus.OnInvoke = function()
			return if animationIntegrityService
				then animationIntegrityService:GetStatus()
				else {state = "Unavailable", mode = "DetectionOnly", automaticEnforcement = false}
		end
	end

	if not animationIntegrityService then
		warn("[Club Neon][AnimationIntegrity] Observer unavailable; animation telemetry is inactive.")
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

ControllerFunctions.hasClubNeonAccess = function(player: Player): boolean
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
	player:SetAttribute("HasClubNeonAccess", ControllerFunctions.hasClubNeonAccess(player))
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
	player:SetAttribute("ClubNeonMountPassId", CONFIG.MountPassId)
	player:SetAttribute("ClubNeonCompanionPassId", CONFIG.CompanionPassId)
	player:SetAttribute("ClubNeonStageLightingPassId", CONFIG.StageClubLightingPassId)
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
	if tier >= 3 then return CONFIG.ClubNeonMaxRequestsPerPlayer end
	if tier == 2 then return CONFIG.VvipMaxRequestsPerPlayer end
	if tier == 1 then return CONFIG.VipMaxRequestsPerPlayer end
	return CONFIG.MaxRequestsPerPlayer
end

ControllerFunctions.cooldownFor = function(player: Player): number
	local tier = ControllerFunctions.passTier(player)
	if tier >= 3 then return CONFIG.ClubNeonCooldownSeconds end
	if tier == 2 then return CONFIG.VvipCooldownSeconds end
	if tier == 1 then return CONFIG.VipCooldownSeconds end
	return CONFIG.RequestCooldownSeconds
end

-- Title slots -------------------------------------------------------------------

-- Returns the hex colors for an effect/set (empty for RGB, which animates by speed instead).
-- Title presentation and slot validation are isolated from persistence and text filtering.
local titlePresentationModule = ServerStorage:FindFirstChild("ClubNeon_TitlePresentation")
if not titlePresentationModule or not titlePresentationModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_TitlePresentation; controller will not start.")
end
local titlePresentation = require(titlePresentationModule)({
	TITLE_HEX = TITLE_HEX, RAINBOW_PARAMS = RAINBOW_PARAMS, TITLE_SETS = TITLE_SETS,
	TITLE_FONTS = TITLE_FONTS, TITLE_STYLES = TITLE_STYLES, RGB_SPEED = RGB_SPEED,
	TITLE_SLOT_COUNT = TITLE_SLOT_COUNT, MAX_CUSTOM_TITLE_LENGTH = MAX_CUSTOM_TITLE_LENGTH,
	isFiniteNumber = ControllerFunctions.isFiniteNumber,
})
ControllerFunctions.titleHexFor = titlePresentation.titleHexFor
ControllerFunctions.sanitizeTitleSlot = titlePresentation.sanitizeTitleSlot
ControllerFunctions.firstFilledSlot = titlePresentation.firstFilledSlot

-- Per-session cache of text that has passed Roblox broadcast filtering.
-- Profile text is preserved if TextService is temporarily unavailable, but is never
-- replicated until the current value has been filtered successfully.
local filteredTitleTextByUserId: {[number]: {[number]: string}} = {}
local lastCustomTitleTextAt: {[number]: number} = {}
local CUSTOM_TITLE_TEXT_COOLDOWN_SECONDS = 60

-- Mirrors the active slot onto player attributes for the overhead title script.
-- Legacy attributes (CustomTitle/TitleColor/TitleStyle/ShowCustomTitle) are kept up to date as well.
ControllerFunctions.applyTitleAttributes = function(player: Player, profile: Profile)
	titlePresentation.applyTitleAttributes(player, profile, filteredTitleTextByUserId[player.UserId])
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

-- Profile persistence is isolated behind an injected state contract.
local profilePersistenceModule = ServerStorage:FindFirstChild("ClubNeon_ProfilePersistence")
if not profilePersistenceModule or not profilePersistenceModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_ProfilePersistence; controller will not start.")
end
local initializeProfilePersistence = require(profilePersistenceModule)
initializeProfilePersistence({
	ControllerFunctions = ControllerFunctions,
	Players = Players,
	getServerShuttingDown = function() return serverShuttingDown end,
	USE_STUDIO_MEMORY_PROFILES = USE_STUDIO_MEMORY_PROFILES,
	filteredTitleTextByUserId = filteredTitleTextByUserId,
	store = store,
	SESSION_TOKEN = SESSION_TOKEN,
	SESSION_LOCK_SECONDS = SESSION_LOCK_SECONDS,
	TAGS = TAGS,
	CONFIG = CONFIG,
	TITLE_SLOT_COUNT = TITLE_SLOT_COUNT,
	TRACK_BY_ID = TRACK_BY_ID,
	TITLE_COLORS = TITLE_COLORS,
	TITLE_STYLES = TITLE_STYLES,
	profiles = profiles,
	receiptTransactions = receiptTransactions,
	saveQueued = saveQueued,
	saveAgain = saveAgain,
	saveQueueTokens = saveQueueTokens,
})

-- Dance Floor rewards are server-observed and profile-backed. The map supplies
-- one or more BaseParts tagged ClubNeonDanceFloorZone; without a valid tagged
-- zone the service remains fail-closed and grants nothing.
-- Dance-floor rewards are isolated in a server-only, injected module.
local danceFloorRewardsModule = ServerStorage:FindFirstChild("ClubNeon_DanceFloorRewards")
if not danceFloorRewardsModule or not danceFloorRewardsModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_DanceFloorRewards; controller will not start.")
end
require(danceFloorRewardsModule)({
	ControllerFunctions = ControllerFunctions,
	Players = Players,
	profiles = profiles,
	controllerScript = script,
	getServerShuttingDown = function() return serverShuttingDown end,
})

ControllerFunctions.recordDiagnosticPulse = function(name: string, detail: string, healthy: boolean?, metadata: {[string]: any}?)
	local ok, recorded = ControllerFunctions.globalInvoke("RecordLocalWatchdogPulse", name, detail, healthy, metadata)
	return ok and recorded == true
end

-- Queue / Auto DJ ---------------------------------------------------------------
-- Queue primitives operate on the controller-owned local queue and request counts.
local queuePrimitivesModule = ServerStorage:FindFirstChild("ClubNeon_QueuePrimitives")
assert(queuePrimitivesModule and queuePrimitivesModule:IsA("ModuleScript"), "ClubNeon_QueuePrimitives is required")
local QueuePrimitives = require(queuePrimitivesModule)
local queuePrimitives = QueuePrimitives.create({
	ControllerFunctions = ControllerFunctions,
	HttpService = HttpService,
	CONFIG = CONFIG,
	queue = queue,
	requestCounts = requestCounts,
	RunService = RunService,
})
ControllerFunctions.makeEntry = queuePrimitives.makeEntry
ControllerFunctions.releaseSlot = queuePrimitives.releaseSlot
ControllerFunctions.countPlayerEntries = queuePrimitives.countPlayerEntries
ControllerFunctions.findQueueIndex = queuePrimitives.findQueueIndex
ControllerFunctions.insertIndex = queuePrimitives.insertIndex
ControllerFunctions.isTrackBlocked = queuePrimitives.isTrackBlocked

-- The manager is an adapter over the same controller-owned table. It never creates
-- a parallel queue and all request-slot accounting remains in releaseSlot above.
queueManager = MusicQueueManager.new(queue, ControllerFunctions.releaseSlot)

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

local playlistRotationModule = ServerStorage:FindFirstChild("ClubNeon_PlaylistRotation")
if not playlistRotationModule or not playlistRotationModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_PlaylistRotation; controller will not start.")
end
local createPlaylistRotation = require(playlistRotationModule)
local playlistRotation = createPlaylistRotation({
	ControllerFunctions = ControllerFunctions,
	MusicPlaylistService = MusicPlaylistService,
	TRACK_BY_ID = TRACK_BY_ID,
	nowPlaying = nowPlaying,
	isPlayableTrack = isPlayableTrack,
	getActivePlaylistId = function() return activePlaylistId end,
	getActivePlaylistName = function() return activePlaylistName end,
	getActivePlaylistTracks = function() return activePlaylistTracks end,
	getActivePlaylistCursor = function() return activePlaylistCursor end,
	setActivePlaylistCursor = function(value: number) activePlaylistCursor = value end,
	setActivePlaylist = function(id, name, tracks, cursor)
		activePlaylistId = id
		activePlaylistName = name
		activePlaylistTracks = tracks
		activePlaylistCursor = cursor
	end,
	notify = notify,
})
ControllerFunctions.nextPlaylistTrack = playlistRotation.nextPlaylistTrack
ControllerFunctions.reloadActivePlaylist = playlistRotation.reloadActivePlaylist
ControllerFunctions.startPlaylistRotation = playlistRotation.startPlaylistRotation
ControllerFunctions.stopPlaylistRotation = playlistRotation.stopPlaylistRotation

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
	audioState.audioTransitionTrackToken += 1
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
	if ControllerFunctions.commitGlobalPlaybackSync and suppressGlobalCommit ~= true then
		task.defer(function() ControllerFunctions.commitGlobalPlaybackSync("track-change") end)
	end
end

-- Playback-only sync shares Now Playing and its playhead. Every server keeps
-- its own queue, playlist cursor, Auto DJ refill, request locks, and skip votes.
ControllerFunctions.globalPlaybackSyncState = {
	enabled = false, isLeader = false, revision = 0, trackRevision = 0,
	lastAppliedRevision = -1, lastSyncAppliedAt = 0, lastErrorAt = 0, leaderJobId = nil, authorityReady = false, statusError = nil,
}
ControllerFunctions.commitGlobalPlaybackSync = function(reason: string?): boolean
	local state = ControllerFunctions.globalPlaybackSyncState
	if state.enabled ~= true or state.isLeader ~= true then return false end
	local snapshotOk, snapshotRead, current = ControllerFunctions.globalInvoke("GetGlobalPlaybackSnapshot")
	if not snapshotOk or snapshotRead ~= true or typeof(current) ~= "table" then return false end
	local audio = ControllerFunctions.getAudioSnapshot()
	local position = if typeof(audio) == "table" and ControllerFunctions.isFiniteNumber(audio.position)
		then math.clamp(audio.position, 0, nowPlaying.duration) else math.clamp(nowPlaying.elapsed, 0, nowPlaying.duration)
	local trackChanged = typeof(current.current) ~= "table" or current.current.trackId ~= nowPlaying.trackId
	local nextTrackRevision = math.max(tonumber(current.trackRevision) or 0, tonumber(state.trackRevision) or 0)
	if trackChanged then nextTrackRevision += 1 end
	local payload = {
		current = if nowPlaying.trackId ~= "" then {
			trackId = nowPlaying.trackId, title = nowPlaying.title, artist = nowPlaying.artist,
			soundId = nowPlaying.soundId, duration = nowPlaying.duration,
		} else nil,
		paused = audioState.playbackPaused == true,
		position = position,
		anchorTime = workspace:GetServerTimeNow(),
		trackRevision = nextTrackRevision,
	}
	local commitOk, committed, result, message = ControllerFunctions.globalInvoke(
		"CommitGlobalPlaybackSnapshot", payload, tonumber(current.revision) or 0
	)
	if commitOk and committed == true and typeof(result) == "table" then
		state.revision = tonumber(result.revision) or state.revision
		state.trackRevision = tonumber(result.trackRevision) or nextTrackRevision
		state.lastAppliedRevision = state.revision
		return true
	end
	if os.clock() - (state.lastErrorAt or 0) > 15 then
		state.lastErrorAt = os.clock()
		warn("[ClubMusic] Optional playback-only sync commit failed (" .. tostring(reason or "update") .. "): "
			.. tostring(message or committed))
	end
	return false
end

ControllerFunctions.applyGlobalPlaybackSyncSnapshot = function(snapshot: any, allowLeader: boolean?): boolean
	local state = ControllerFunctions.globalPlaybackSyncState
	if state.enabled ~= true or (state.isLeader == true and allowLeader ~= true)
		or typeof(snapshot) ~= "table" or not ControllerFunctions.isFiniteNumber(snapshot.revision)
		or snapshot.revision < 0 or snapshot.revision % 1 ~= 0 or snapshot.revision > 9007199254740991
		or snapshot.revision < (state.lastAppliedRevision or -1)
		or (snapshot.revision == state.lastAppliedRevision and os.clock() - (state.lastSyncAppliedAt or 0) < 12) then return false end
	local current = snapshot.current
	if typeof(current) == "table" and typeof(current.trackId) == "string"
		and typeof(current.soundId) == "string" and ControllerFunctions.isFiniteNumber(current.duration)
		and current.duration >= 1 and current.duration <= 86400 then
		local catalogTrack = TRACK_BY_ID[current.trackId]
		if ControllerFunctions.isTrackBlocked(current.trackId) then
			if nowPlaying.trackId == current.trackId then
				ControllerFunctions.cancelAudioTransition("global-playback-track-blocked")
				ControllerFunctions.stopServerMusic()
				ControllerFunctions.setAudioAsset("")
				nowPlaying.trackId = ""; nowPlaying.title = ""; nowPlaying.artist = ""
				nowPlaying.soundId = ""; nowPlaying.elapsed = 0
				audioState.playbackPaused = true
				ControllerFunctions.publishPlaybackState()
			end
			state.lastAppliedRevision = snapshot.revision
			state.lastSyncAppliedAt = os.clock()
			return false
		end
		if not catalogTrack or not isPlayableTrack(catalogTrack) then
			task.defer(ControllerFunctions.refreshCatalogWhenReady)
			return false
		end
		local canonicalSoundId = catalogTrack.soundId or CONFIG.SoundIds[current.trackId] or ""
		if canonicalSoundId == "" or canonicalSoundId ~= current.soundId then return false end
		audioState.playbackPaused = snapshot.paused == true
		if nowPlaying.trackId ~= current.trackId then
			local entry: QueueEntry = {
				id = "global-playback-" .. tostring(snapshot.trackRevision or snapshot.revision),
				trackId = current.trackId, title = catalogTrack.title, artist = catalogTrack.artist,
				duration = catalogTrack.duration, requestedBy = "Global Playback", userId = 0,
				genre = catalogTrack.genre, source = "auto", vip = false, passTier = 0,
				soundId = canonicalSoundId,
			}
			ControllerFunctions.setNowPlaying(entry, nil, true)
		end
		local anchor = if ControllerFunctions.isFiniteNumber(snapshot.anchorTime) then snapshot.anchorTime else workspace:GetServerTimeNow()
		local base = if ControllerFunctions.isFiniteNumber(snapshot.position) then snapshot.position else 0
		local elapsed = if snapshot.paused == true then base else base + math.max(0, workspace:GetServerTimeNow() - anchor)
		nowPlaying.elapsed = math.clamp(elapsed, 0, nowPlaying.duration)
		audioState.playbackPaused = snapshot.paused == true
		pcall(function()
			local audio = ControllerFunctions.getAudioSnapshot()
			if audio.ready then ControllerFunctions.seekAudio(nowPlaying.elapsed) end
			if audioState.playbackPaused then ControllerFunctions.pauseAudio()
			elseif not audio.playing then ControllerFunctions.playAudio() end
		end)
	else
		if nowPlaying.trackId ~= "" then
			ControllerFunctions.cancelAudioTransition("global-playback-empty")
			ControllerFunctions.stopServerMusic()
			ControllerFunctions.setAudioAsset("")
			nowPlaying.trackId = ""; nowPlaying.title = ""; nowPlaying.artist = ""
			nowPlaying.soundId = ""; nowPlaying.elapsed = 0
		end
		audioState.playbackPaused = true
	end
	state.revision = snapshot.revision
	state.trackRevision = tonumber(snapshot.trackRevision) or state.trackRevision
	state.lastAppliedRevision = snapshot.revision
	state.lastSyncAppliedAt = os.clock()
	ControllerFunctions.publishPlaybackState()
	local targetTrackId = nowPlaying.trackId
	local targetRevision = snapshot.revision
	local targetPosition = nowPlaying.elapsed
	local targetPaused = audioState.playbackPaused
	task.spawn(function()
		local deadline = os.clock() + 10
		while os.clock() < deadline do
			if state.enabled ~= true or nowPlaying.trackId ~= targetTrackId
				or state.lastAppliedRevision ~= targetRevision then return end
			local audio = ControllerFunctions.getAudioSnapshot()
			if typeof(audio) == "table" and audio.ready == true then
				pcall(function()
					ControllerFunctions.seekAudio(targetPosition)
					if targetPaused then ControllerFunctions.pauseAudio() else ControllerFunctions.playAudio() end
				end)
				return
			end
			task.wait(0.15)
		end
	end)
	return true
end


-- Queue state and playback transitions are owned by this server.


ControllerFunctions.advance = function(expectedGeneration: number?): (boolean, string?)
	-- Server-local queue only. Generation checks prevent the playback clock and
	-- watchdog from advancing the same track twice.
	if transitionInProgress then return false, "A track transition is already in progress." end
	if expectedGeneration ~= nil and expectedGeneration ~= playbackGeneration then
		return false, "The current track changed before the transition started."
	end
	local syncState = ControllerFunctions.globalPlaybackSyncState
	if syncState and syncState.enabled == true and syncState.isLeader ~= true then
		return false, "Global playback is controlled by the elected server; this server's request queue remains local."
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
	local xpClientState = xpService.GetClientState()
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
		customTitleUnlocked = ControllerFunctions.hasClubNeonAccess(player),
		queue = safeQueue,
		globalPlaybackSync = {
			enabled = ControllerFunctions.globalPlaybackSyncState.enabled == true,
			isLeader = ControllerFunctions.globalPlaybackSyncState.isLeader == true,
			leaderJobId = ControllerFunctions.globalPlaybackSyncState.leaderJobId,
			authorityReady = ControllerFunctions.globalPlaybackSyncState.authorityReady == true,
			error = ControllerFunctions.globalPlaybackSyncState.statusError,
			localQueueIsolated = true,
		},
		nowPlaying = {
			trackId = nowPlaying.trackId, title = nowPlaying.title, artist = nowPlaying.artist,
			genre = nowPlaying.genre, duration = nowPlaying.duration, elapsed = nowPlaying.elapsed,
			dj = nowPlaying.dj, source = nowPlaying.source, requestedBy = nowPlaying.requestedBy,
			vip = nowPlaying.vip, soundId = nowPlaying.soundId, paused = audioState.playbackPaused,
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
		eliteGamePassId = CONFIG.ClubNeonPassId,
		personalXP2xGamePassId = CONFIG.PersonalXP2xPassId,
		personalXP4xGamePassId = CONFIG.PersonalXP4xPassId,
		mountGamePassId = CONFIG.MountPassId,
		companionGamePassId = CONFIG.CompanionPassId,
		stageClubLightingGamePassId = CONFIG.StageClubLightingPassId,
		donationProductIds = table.clone(CONFIG.DonationProductIds),
		passTier = ControllerFunctions.passTier(player),
		passName = if ControllerFunctions.hasClubNeonAccess(player) then "CLUB NEON" elseif ControllerFunctions.isVvip(player) then "VVIP" elseif ControllerFunctions.isVip(player) then "VIP" else "GUEST",
		passPerks = {
			vip = { slots = CONFIG.VipMaxRequestsPerPlayer, cooldown = CONFIG.VipCooldownSeconds },
			vvip = { slots = CONFIG.VvipMaxRequestsPerPlayer, cooldown = CONFIG.VvipCooldownSeconds },
			elite = { slots = CONFIG.ClubNeonMaxRequestsPerPlayer, cooldown = CONFIG.ClubNeonCooldownSeconds, priority = "highest" },
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
		xpMultiplier = xpClientState.multiplier,
		xpBoostExpiresAt = xpClientState.expiresAt,
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
	Coconut = CONFIG.DonationProductIds.Coconut,
	Pineapple = CONFIG.DonationProductIds.Pineapple,
	NeonTorch = CONFIG.DonationProductIds.NeonTorch,
	Volcano = CONFIG.DonationProductIds.Volcano,
	IslandLegend = CONFIG.DonationProductIds.IslandLegend,
	IslandRoyalty = CONFIG.DonationProductIds.IslandRoyalty,
	ClubNeonLegacy = CONFIG.DonationProductIds.ClubNeonLegacy,

	-- Shop Items
	Glowsticks = 0,
	NeonMask = 0,
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
ControllerFunctions.registerProduct(PRODUCT_IDS.NeonTorch, {
	type = "Donation", perk = "Neon Torch", amount = 100,
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
ControllerFunctions.registerProduct(PRODUCT_IDS.ClubNeonLegacy, {
	type = "Donation", perk = "Club Neon Legacy", amount = 10000,
})

-- Shop Items
ControllerFunctions.registerProduct(PRODUCT_IDS.Glowsticks, {
	type = "Item", name = "Glowsticks", costCoins = 75,
})
ControllerFunctions.registerProduct(PRODUCT_IDS.NeonMask, {
	type = "Item", name = "Neon Mask", costCoins = 250,
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
	local core = ServerStorage:FindFirstChild("ClubNeonSecurityCore")
	local module = if core and core:IsA("Folder") then core:FindFirstChild("ReceiptTransactionService") else nil
	if module and module:IsA("ModuleScript") then
		local requireOk, exported = pcall(require, module)
		if requireOk and typeof(exported) == "table" and type(exported.new) == "function" then
			local createOk, instance = pcall(exported.new, {
				profileStore = store,
				journalStore = DataStoreService:GetDataStore(storage.ReceiptStore),
				getProfile = function(userId: number) return profiles[userId] end,
				getSessionToken = function() return SESSION_TOKEN end,
				getSessionLockSeconds = function() return SESSION_LOCK_SECONDS end,
				waitForDataStoreBudget = function(timeout: number)
					return ControllerFunctions.waitForDataStoreBudget(timeout)
				end,
				acquireProfileWriteLock = function(userId: number)
					return ControllerFunctions.acquireProfileWriteLock(userId)
				end,
				releaseProfileWriteLock = function(userId: number, lockToken: any)
					return ControllerFunctions.releaseProfileWriteLock(userId, lockToken)
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

local receiptProcessingModule = ServerStorage:FindFirstChild("ClubNeon_ReceiptProcessing")
if not receiptProcessingModule or not receiptProcessingModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_ReceiptProcessing; controller will not start.")
end
local createReceiptProcessing = require(receiptProcessingModule)
local receiptProcessing = createReceiptProcessing({
	ServerStorage = ServerStorage,
	Players = Players,
	profiles = profiles,
	purchaseDiagnostics = purchaseDiagnostics,
	RunService = RunService,
	ControllerFunctions = ControllerFunctions,
	notify = notify,
	publishState = publishState,
	USE_STUDIO_MEMORY_PROFILES = USE_STUDIO_MEMORY_PROFILES,
	getStudioXpBoostState = function() return studioXpBoostMultiplier, studioXpBoostExpiresAt end,
	setStudioXpBoostState = function(multiplier: number, expiresAt: number)
		studioXpBoostMultiplier = multiplier
		studioXpBoostExpiresAt = expiresAt
	end,
	getReceiptTransactions = function() return receiptTransactions end,
})
local recordReceiptReplayEvent = receiptProcessing.RecordReceiptReplayEvent
local processValidatedReceipt = receiptProcessing.ProcessValidatedReceipt

local receiptAuthority: any = nil
do
	local core = ServerStorage:FindFirstChild("ClubNeonSecurityCore")
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
					purchaseDiagnostics.RecordPurchase("ServerReceipt", userId, productId, outcome, detail)
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

local receiptAuthorityStatusObject = ServerStorage:FindFirstChild("GetClubNeonReceiptAuthorityStatus")
local receiptAuthorityStatus: BindableFunction? = nil
if receiptAuthorityStatusObject and receiptAuthorityStatusObject:IsA("BindableFunction") then
	receiptAuthorityStatus = receiptAuthorityStatusObject
elseif receiptAuthorityStatusObject then
	warn("[ClubMusic][ReceiptAuthority] Status endpoint has the wrong class; leaving it untouched.")
else
	local createdStatus = Instance.new("BindableFunction")
	createdStatus.Name = "GetClubNeonReceiptAuthorityStatus"
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

local requestValidationModule = ServerStorage:FindFirstChild("ClubNeon_RequestValidation")
if not requestValidationModule or not requestValidationModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_RequestValidation; controller will not start.")
end
local createRequestValidation = require(requestValidationModule)
local requestValidation = createRequestValidation({
	ControllerFunctions = ControllerFunctions,
	Players = Players,
	CONFIG = CONFIG,
	sanityValidationService = sanityValidationService,
	blockedUsers = blockedUsers,
	lastRequestAt = lastRequestAt,
	requestCounts = requestCounts,
	nowPlaying = nowPlaying,
	queue = queue,
	getDjControlModeEnabled = function() return djControlModeEnabled end,
	getDjControlModeUserId = function() return djControlModeUserId end,
	getRequestsLocked = function() return requestsLocked end,
	notify = notify,
})
ControllerFunctions.isValidString = requestValidation.isValidString
ControllerFunctions.isBoundedPayload = requestValidation.isBoundedPayload
ControllerFunctions.findTarget = requestValidation.findTarget
ControllerFunctions.requestBlockReason = requestValidation.requestBlockReason

-- Yields. Confirms an asset is an audio file, loadable by this experience, and returns its real length.
local audioAssetInspectorModule = ServerStorage:FindFirstChild("ClubNeon_AudioAssetInspector")
if not audioAssetInspectorModule or not audioAssetInspectorModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_AudioAssetInspector; controller will not start.")
end
local createAudioAssetInspector = require(audioAssetInspectorModule)
ControllerFunctions.inspectAudioAsset = createAudioAssetInspector({
	musicValidation = musicValidation,
	SoundService = SoundService,
	ContentProvider = ContentProvider,
	CONFIG = CONFIG,
	decrementInspectionSlot = function()
		audioInspectionCount = math.max(0, audioInspectionCount - 1)
	end,
})

-- Saves a validated title slot. Returns true on success. Yields (text filtering).
ControllerFunctions.saveTitleSlot = function(player: Player, slotNumber: number, data: any, visible: boolean): boolean
	local profile = profiles[player.UserId]
	if not profile then return false end
	if not ControllerFunctions.hasClubNeonAccess(player) then
		notify(player, "Custom titles are exclusive to Club Neon members.", "warn")
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
		or not ControllerFunctions.hasClubNeonAccess(player)
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

-- Catalog mutation logic is isolated from the request router. The context uses
-- accessors for counters and playlist cursor so yielding work updates live state.
local catalogMutationModule = ServerStorage:FindFirstChild("ClubNeon_CatalogMutationActions")
if not catalogMutationModule or not catalogMutationModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_CatalogMutationActions; controller will not start.")
end
local catalogMutationActions = require(catalogMutationModule)
local catalogMutationContext = {
	ControllerFunctions = ControllerFunctions,
	CONFIG = CONFIG,
	catalogStorageReady = catalogStorageReady,
	MusicCatalogService = MusicCatalogService,
	TRACK_BY_ID = TRACK_BY_ID,
	ALL_TRACK_IDS = ALL_TRACK_IDS,
	MarketplaceService = MarketplaceService,
	Enum = Enum,
	pendingArtwork = pendingArtwork,
	Players = Players,
	pendingAudio = pendingAudio,
	lastAudioInspection = lastAudioInspection,
	globalAudioBucket = globalAudioBucket,
	nowPlaying = nowPlaying,
	queue = queue,
	getActivePlaylistId = function() return activePlaylistId end,
	activePlaylistTracks = activePlaylistTracks,
	getActivePlaylistCursor = function() return activePlaylistCursor end,
	setActivePlaylistCursor = function(value: number) activePlaylistCursor = value end,
	publishState = publishState,
	notify = notify,
	getArtworkInspectionCount = function() return artworkInspectionCount end,
	setArtworkInspectionCount = function(value: number) artworkInspectionCount = value end,
	getAudioInspectionCount = function() return audioInspectionCount end,
	setAudioInspectionCount = function(value: number) audioInspectionCount = value end,
}

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
		-- The budget wait can yield. Revalidate the caller and staff role before
		-- entering a persistent playlist mutation.
		if not ControllerFunctions.isLiveRemotePlayer(player) or not ControllerFunctions.isStaff(player) then return end
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

	if action == "CatalogAddAudio" or action == "CatalogRemoveTrack" then
		catalogMutationActions(catalogMutationContext, player, action, payload, now, userId)
		return
	end

	if action == "RequestTrack" then
		if phase32Services then
			local restrictionOk, restricted = phase32Services:IsRestricted(player.UserId, "MusicRequests")
			if not restrictionOk then notify(player, "Moderation restrictions could not be verified. Requests are temporarily unavailable.", "warn"); return end
			if restricted then notify(player, "Your music requests are restricted by moderation.", "warn"); return end
			-- Moderation lookup may yield. Revalidate the player session before
			-- allowing the request to mutate this server's queue.
			if not ControllerFunctions.isLiveRemotePlayer(player) then return end
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
		if not CONFIG.EnableGlobalPlaybackSync then return false, "Optional global playback sync is disabled in this controller." end
		if ControllerFunctions.getLevel(player) < 3 then
			return false, "Global playback sync settings are restricted to the Owner and Co-Owner."
		end
		if typeof(payload) ~= "table" or typeof(payload.enabled) ~= "boolean" then
			return false, "Choose whether global playback sync should be enabled."
		end
		local callOk, accepted, result = ControllerFunctions.globalInvoke(
			"SetGlobalPlaybackSyncEnabled", payload.enabled, player.UserId
		)
		if not callOk or accepted ~= true then
			local reason = tostring(result or accepted or "The global playback setting could not be saved.")
			notify(player, reason, "warn")
			return false, reason
		end
		local syncState = ControllerFunctions.globalPlaybackSyncState
		syncState.enabled = payload.enabled
		if not payload.enabled then
			syncState.isLeader = false
			syncState.leaderJobId = nil
			syncState.lastAppliedRevision = -1
			syncState.lastSyncAppliedAt = 0
		end
		syncState.authorityReady = payload.enabled ~= true
		syncState.statusError = if payload.enabled then "Waiting for playback leader election." else nil
		publishState(nil)
		local message = if payload.enabled
			then "Global playback sync enabled. Every server keeps its own request queue."
			else "Global playback sync disabled. Each server continues with its own playback and queue."
		notify(player, message, "ok")
		return true, message
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
		if ControllerFunctions.globalPlaybackSyncState.enabled == true and ControllerFunctions.globalPlaybackSyncState.isLeader ~= true then
			return false, "Only the elected playback leader can pause or resume while global playback sync is enabled."
		end
		if audioState.audioReloadInProgress then
			notify(player, "Please wait for the current audio reload to finish before changing playback controls.", "warn")
			return false, "Audio reload is in progress."
		end
		if nowPlaying.trackId == "" then notify(player, "No track is currently selected.", "warn"); return false, "No track is currently selected." end
		local desiredPaused = not audioState.playbackPaused
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
		audioState.playbackPaused = desiredPaused
		ControllerFunctions.publishPlaybackState()
		ControllerFunctions.commitGlobalPlaybackSync(if desiredPaused then "pause" else "resume")
		notify(player, if desiredPaused then "Music paused on this server." else "Music resumed on this server.", "ok")
		return true, if desiredPaused then "Music paused on this server." else "Music resumed on this server."
	end

	if action == "DJRestart" then
		if not ControllerFunctions.canUseDJBooth(player) then return false, "DJ Booth access is required." end
		if ControllerFunctions.globalPlaybackSyncState.enabled == true and ControllerFunctions.globalPlaybackSyncState.isLeader ~= true then
			return false, "Only the elected playback leader can restart while global playback sync is enabled."
		end
		if audioState.audioReloadInProgress then
			notify(player, "Please wait for the current audio reload to finish before restarting the track.", "warn")
			return false, "Audio reload is in progress."
		end
		if nowPlaying.trackId == "" then notify(player, "No track is currently selected.", "warn"); return false, "No track is currently selected." end
		playbackControlRequestId += 1
		local restartAsset = nowPlaying.soundId
		ControllerFunctions.cancelAudioTransition("restart")
		local restartOk, restartError = ControllerFunctions.restartServerMusic(restartAsset)
		if not restartOk then
			audioState.playbackPaused = true
			notify(player, "Track restart could not be applied: " .. tostring(restartError), "warn")
			return false, tostring(restartError)
		end
		nowPlaying.elapsed = 0
		audioState.playbackPaused = false
		ControllerFunctions.publishPlaybackState()
		ControllerFunctions.commitGlobalPlaybackSync("restart")
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
		local tierName = ({"GUEST", "VIP", "VVIP", "CLUB NEON"})[requestedTier + 1]
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
		local prices = { bass = 150, sunset = 250, neon = 400 }
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
		notify(player, tagId == "bass" and "Bass Head unlocked!" or tagId == "sunset" and "Sunset Soul unlocked!" or "Neon Legend unlocked!", "ok")
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
		if not ControllerFunctions.hasClubNeonAccess(player) then notify(player, "Custom titles require Club Neon.", "warn"); return end
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
			or not ControllerFunctions.hasClubNeonAccess(player)
			or slotNumber > profile.unlockedSlots then return end
		profile.activeSlot = slotNumber
		ControllerFunctions.applyTitleAttributes(player, profile)
		ControllerFunctions.scheduleProfileSave(player)
		publishState(player)
		return
	end

	if action == "ClearTitleSlot" then
		if not ControllerFunctions.hasClubNeonAccess(player) then notify(player, "Custom titles require Club Neon.", "warn"); return end
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
		if not ControllerFunctions.hasClubNeonAccess(player) then notify(player, "Custom titles require Club Neon.", "warn"); return end
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
		purchase = table.clone(purchaseDiagnostics.PurchaseStats),
		moderation = table.clone(purchaseDiagnostics.ModerationStats),
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
				enabled = ControllerFunctions.globalPlaybackSyncState.enabled == true,
				isLeader = ControllerFunctions.globalPlaybackSyncState.isLeader == true,
				leaderJobId = ControllerFunctions.globalPlaybackSyncState.leaderJobId,
				authorityReady = ControllerFunctions.globalPlaybackSyncState.authorityReady == true,
				localQueueIsolated = true,
			},
			modernBackendConfigured = CONFIG.UseModernAudioBackend == true,
			modernBackendStartSucceeded = audioState.modernBackendStartSucceeded,
			modernBackendStartFailureCount = audioState.modernBackendStartFailureCount,
			activeSourceKind = audioState.activeAudioSource.kind,
		},
		updatedAt = os.time(),
	}
end

-- Audio validation signals contain only a fixed event name and server-known actor ID.
-- No asset IDs, client payloads, provider metadata, or user text enter the replay timeline.
ControllerFunctions.recordAudioValidationSignal = function(player: Player, signal: string)
	local invoked, accepted = ControllerFunctions.globalInvoke("ReportSignal", player.UserId, signal)
	if invoked and accepted == true then return end
	local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
	if replay and replay:IsA("BindableFunction") then
		pcall(function()
			replay:Invoke("Record", signal, player.UserId, 0, "Warning", "ClubMusicAudioValidation", {})
		end)
	end
end
ControllerFunctions.recordAudioReplayEvent = function(player: Player, eventType: string)
	local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
	if replay and replay:IsA("BindableFunction") then
		pcall(function()
			replay:Invoke("Record", eventType, player.UserId, 0, "Info", "ClubMusicAudioValidation", {})
		end)
	end
end
ControllerFunctions.recordTextReplayEvent = function(player: Player, eventType: string)
	local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
	if replay and replay:IsA("BindableFunction") then
		pcall(function()
			replay:Invoke("Record", eventType, player.UserId, 0, "Info", "ClubMusicTextValidation", {})
		end)
	end
end

local operationalDiagnosticsFormatterModule = ServerStorage:FindFirstChild("ClubNeon_OperationalDiagnosticsFormatter")
if not operationalDiagnosticsFormatterModule or not operationalDiagnosticsFormatterModule:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_OperationalDiagnosticsFormatter; controller will not start.")
end
local operationalDiagnosticsFormatter = require(operationalDiagnosticsFormatterModule)

local adminBridgeModuleSource = ServerStorage:FindFirstChild("ClubNeon_AdminBridge")
if not adminBridgeModuleSource or not adminBridgeModuleSource:IsA("ModuleScript") then
	error("[Club Neon] Missing ServerStorage.ClubNeon_AdminBridge; controller will not start.")
end
local createAdminBridge = require(adminBridgeModuleSource)
local adminBridgeModule = createAdminBridge({
	-- Mutable primitives remain controller-owned; bridge receives live accessors, not snapshots.
	getPlaybackPaused = function(): boolean return audioState.playbackPaused end,
	setPlaybackPaused = function(value: boolean) audioState.playbackPaused = value == true end,
	getRequestsLocked = function(): boolean return requestsLocked end,
	setRequestsLocked = function(value: boolean) requestsLocked = value == true end,
	getDJControlModeEnabled = function(): boolean return djControlModeEnabled end,
	ControllerFunctions = ControllerFunctions,
	Players = Players,
	ServerStorage = ServerStorage,
	ALL_TRACK_IDS = ALL_TRACK_IDS,
	blockedUsers = blockedUsers,
	djControlModeEnabled = djControlModeEnabled,
	nowPlaying = nowPlaying,
	operationalDiagnosticsFormatter = operationalDiagnosticsFormatter,
	permissions = permissions,
	phase32Services = phase32Services,
	playbackPaused = audioState.playbackPaused,
	publishState = publishState,
	purchaseDiagnostics = purchaseDiagnostics,
	queue = queue,
	queueManager = queueManager,
	remotes = remotes,
	requestsLocked = requestsLocked,
	storage = storage,
})
local adminBridge = adminBridgeModule.Bridge

-- Do not leave a stale callback closure callable if this controller Script is
-- removed or replaced. Clear only the exact callback owned by this instance.
script.Destroying:Connect(adminBridgeModule.Shutdown)

-- Construct the remaining optional child managers only after controller state exists.
-- Playback quality is now inspected directly from the canonical modern AudioPlayer snapshot.
ControllerFunctions.ChildManagers = {}


ControllerFunctions.castSkipVote = function(player: Player): (boolean, string)
	if player.Parent ~= Players then return false, "A connected player is required." end
	if ControllerFunctions.globalPlaybackSyncState.enabled == true and ControllerFunctions.globalPlaybackSyncState.isLeader ~= true then
		return false, "Global playback is controlled by the elected server; skip voting is unavailable on this follower server."
	end
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
		local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
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
		local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
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

-- Roblox-native ban history is separate from Club Neon's custom moderation store.
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
		warn("[Club Neon][NativeBanLookup] Roblox ban history unavailable for UserId "
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
	if serverShuttingDown or player.Parent ~= Players or onJoinStarted[player] then return end
	onJoinStarted[player] = true
	task.spawn(ControllerFunctions.checkNativeBanHistory, player)
	local enabledCallOk, globalServiceEnabled = ControllerFunctions.globalInvoke("IsEnabled")
	if player.Parent ~= Players or serverShuttingDown then return end
	local globalModerationRequired = not RunService:IsStudio()
	local globalServiceReady = enabledCallOk and globalServiceEnabled == true
	-- A service-readiness failure is not a ban. Keep moderation-sensitive actions
	-- closed and retry authoritative checks instead of kicking legitimate players.
	-- Fetch ban and request-block status together to avoid serial durable reads.
	local moderationCallOk, moderationLookupOk, globallyBanned, globallyBlocked, _moderationReason, moderationRevision =
		ControllerFunctions.globalInvoke("GetModerationState", player.UserId)
	if player.Parent ~= Players or serverShuttingDown then return end
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
		purchaseDiagnostics.RecordModeration("Join", moderationCallOk and moderationLookupOk == true,
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
			while not serverShuttingDown and player.Parent == Players and not (serviceResolved and moderationResolved) do
				attempt += 1
				-- The initial join checks already ran immediately. If a backend was still
				-- loading, retry quickly instead of imposing a five-second blind lock;
				-- increase the interval only when the service continues to fail.
				local retryBaseDelay = if attempt == 1 then 1 else math.min(15, 2 ^ math.min(attempt - 1, 4))
				local retryDelay = math.min(15, retryBaseDelay * retryJitter)
				task.wait(retryDelay)
				if player.Parent ~= Players or serverShuttingDown then return end
				if not serviceResolved then
					local callOk, enabled = ControllerFunctions.globalInvoke("IsEnabled")
					if player.Parent ~= Players or serverShuttingDown then return end
					serviceResolved = callOk and enabled == true
				end
				if not moderationResolved then
					local callOk, lookupOk, banned, blocked, _reason, revision =
						ControllerFunctions.globalInvoke("GetModerationState", player.UserId)
					if player.Parent ~= Players or serverShuttingDown then return end
					local latestRevision = ControllerFunctions.moderationRevisions
						and ControllerFunctions.moderationRevisions[player.UserId] or 0
					if callOk and lookupOk == true
						and (not ControllerFunctions.isFiniteNumber(revision) or revision < latestRevision) then
						lookupOk = false
					end
					purchaseDiagnostics.RecordModeration("Retry", callOk and lookupOk == true, banned == true, blocked == true)
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
	if serverShuttingDown or player.Parent ~= Players then return end
	ControllerFunctions.refreshVip(player)
	if serverShuttingDown or player.Parent ~= Players then return end
	ControllerFunctions.refreshPersonalPasses(player)
	if serverShuttingDown or player.Parent ~= Players then return end
	local loaded = ControllerFunctions.loadProfile(player)
	if not loaded then
		notify(player, "Your profile could not be loaded. Please rejoin in a moment; no default profile was saved over your data.", "warn")
		return
	end
	ControllerFunctions.applyVipAttribute(player)
	ControllerFunctions.syncTitleTagUnlocks(player)
	player:SetAttribute("ClubRank", ControllerFunctions.getRank(player))
	xpService.InitializePlayer(player.UserId)
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
	if message.kind == "PlaybackSyncModeChanged" and typeof(message.enabled) == "boolean" then
		local syncState = ControllerFunctions.globalPlaybackSyncState
		syncState.enabled = message.enabled
		if not message.enabled then
			syncState.isLeader = false
			syncState.wasLeader = false
			syncState.leaderJobId = nil
			syncState.lastAppliedRevision = -1
			syncState.lastSyncAppliedAt = 0
		else
			task.defer(function()
				local ok, readOk, snapshot = ControllerFunctions.globalInvoke("GetGlobalPlaybackSnapshot")
				if ok and readOk == true then ControllerFunctions.applyGlobalPlaybackSyncSnapshot(snapshot) end
			end)
		end
		publishState(nil)
		return
	end
	if message.kind == "PlaybackChanged" and ControllerFunctions.globalPlaybackSyncState.enabled == true then
		task.defer(function()
			local ok, readOk, snapshot = ControllerFunctions.globalInvoke("GetGlobalPlaybackSnapshot")
			if ok and readOk == true then ControllerFunctions.applyGlobalPlaybackSyncSnapshot(snapshot) end
		end)
		return
	end
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

-- The global service owns the fenced leadership lease. This controller only
-- observes status and reconciles Now Playing; no local queue is ever uploaded.
task.spawn(function()
	local syncState = ControllerFunctions.globalPlaybackSyncState
	if not CONFIG.EnableGlobalPlaybackSync then return end
	while script.Parent do
		local enabledOk, enabledStatus, status = ControllerFunctions.globalInvoke("GetGlobalPlaybackSyncStatus")
		if enabledOk and enabledStatus == true and typeof(status) == "table" and status.syncEnabled == true then
			syncState.enabled = true
			local previous = table.concat({tostring(syncState.isLeader), tostring(syncState.leaderJobId), tostring(syncState.authorityReady)}, "|")
			syncState.leaderJobId = if typeof(status.leaderJobId) == "string" then status.leaderJobId else nil
			syncState.wasLeader = syncState.isLeader == true
			syncState.isLeader = status.isLeader == true
			local authorityError = if typeof(status.lastServiceError) == "string" then status.lastServiceError
				elseif typeof(status.error) == "string" then status.error else nil
			local diagnosticError = authorityError or (if typeof(status.lastError) == "string" then status.lastError else nil)
			syncState.authorityReady = status.enabled == true and authorityError == nil
			syncState.statusError = if diagnosticError then string.sub(diagnosticError, 1, 120) else nil
			local current = table.concat({tostring(syncState.isLeader), tostring(syncState.leaderJobId), tostring(syncState.authorityReady)}, "|")
			if previous ~= current then publishState(nil) end
			if syncState.isLeader then
				local wasLeader = syncState.wasLeader == true
				local snapshotOk, snapshotRead, snapshot = ControllerFunctions.globalInvoke("GetGlobalPlaybackSnapshot")
				if snapshotOk and snapshotRead == true and typeof(snapshot) == "table" then
					if typeof(snapshot.current) == "table" then
						if not wasLeader or nowPlaying.trackId ~= snapshot.current.trackId then
							ControllerFunctions.applyGlobalPlaybackSyncSnapshot(snapshot, true)
						elseif ControllerFunctions.isFiniteNumber(snapshot.anchorTime)
							and workspace:GetServerTimeNow() - snapshot.anchorTime > 30 then
							ControllerFunctions.commitGlobalPlaybackSync("leader-stale-snapshot-recovery")
						end
						syncState.revision = tonumber(snapshot.revision) or syncState.revision
						syncState.trackRevision = tonumber(snapshot.trackRevision) or syncState.trackRevision
					elseif nowPlaying.trackId ~= "" then
						ControllerFunctions.commitGlobalPlaybackSync("leader-initialization")
					end
				end
			else
				local snapshotOk, snapshotRead, snapshot = ControllerFunctions.globalInvoke("GetGlobalPlaybackSnapshot")
				if snapshotOk and snapshotRead == true then ControllerFunctions.applyGlobalPlaybackSyncSnapshot(snapshot) end
			end
		elseif enabledOk and enabledStatus == true and typeof(status) == "table" and status.syncEnabled ~= true then
			syncState.enabled = false
			syncState.isLeader = false
			syncState.wasLeader = false
			syncState.leaderJobId = nil
			syncState.lastAppliedRevision = -1
			syncState.lastSyncAppliedAt = 0
			syncState.authorityReady = status.enabled == true and status.error == nil
			syncState.statusError = if typeof(status.error) == "string" then string.sub(status.error, 1, 120) else nil
			publishState(nil)
		elseif not enabledOk then
			-- A transient status outage must not let a stale former leader keep advancing.
			syncState.isLeader = false
			syncState.wasLeader = false
			syncState.leaderJobId = nil
			syncState.authorityReady = false
			syncState.statusError = "Global playback status unavailable."
		end
		task.wait(8)
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

xpService.Start(script)

Players.PlayerAdded:Connect(function(player)
	if serverShuttingDown then return end
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
	xpService.RemovePlayer(player)
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
	local isMembershipPass = passId == CONFIG.VipGamePassId or passId == CONFIG.VvipGamePassId or passId == CONFIG.ClubNeonPassId
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
			local tierName = if ControllerFunctions.hasClubNeonAccess(player) then "Club Neon" elseif ControllerFunctions.isVvip(player) then "VVIP" elseif ControllerFunctions.isVip(player) then "VIP" else "Pass"
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
	while not serverShuttingDown do
		task.wait(60)
		if serverShuttingDown then break end
		for _, player in ipairs(Players:GetPlayers()) do
			if serverShuttingDown then break end
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
	while not serverShuttingDown do
		task.wait(60)
		if serverShuttingDown then break end
		for _, player in ipairs(Players:GetPlayers()) do
			if serverShuttingDown then break end
			task.spawn(function()
				if serverShuttingDown or player.Parent ~= Players then return end
				local previousRank = ControllerFunctions.getRank(player)
				local previousTier = ControllerFunctions.passTier(player)
				ControllerFunctions.refreshRank(player)
				if serverShuttingDown or player.Parent ~= Players then return end
				ControllerFunctions.refreshVip(player)
				if serverShuttingDown or player.Parent ~= Players then return end
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
				if serverShuttingDown or player.Parent ~= Players then return end
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
	-- Studio disconnect and production shutdown both set this shared flag in
	-- BindToClose. Stop the playback worker before it can inspect a destroyed
	-- AudioPlayer or interpret shutdown as a failed track.
	while not serverShuttingDown do
		task.wait(1)
		if serverShuttingDown then break end
		if not audioState.playbackPaused and not audioState.audioReloadInProgress then
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
		local shouldAdvance = not audioState.playbackPaused and not audioState.audioReloadInProgress and nowPlaying.trackId ~= ""
			and nowPlaying.elapsed >= nowPlaying.duration
		-- Catalog tracks without a configured SoundId are intentionally silent
		-- UI/visualizer entries. Do not treat their intentionally absent audio as a failed
		-- asset: let their catalog duration drive the normal transition instead.
		-- A transient IsPlaying=false must not be treated as end-of-track.
		-- Require a short stable stop, then attempt one in-place resume from the
		-- captured playhead before allowing the queue watchdog to advance.
		local audio = ControllerFunctions.getAudioSnapshot()
		if serverShuttingDown then break end
		if audioState.playbackPaused or audioState.audioReloadInProgress or nowPlaying.trackId == "" or nowPlaying.soundId == ""
			or audio.playing == true then
			ControllerFunctions.stoppedAudioGeneration = -1
			ControllerFunctions.stoppedAudioSince = 0
			ControllerFunctions.audioRecoveryAttemptedGeneration = -1
		elseif not audioState.audioReloadInProgress and not shouldAdvance and nowPlaying.elapsed >= 15 then
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
						local source = audioState.activeAudioSource
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
		if not audioState.playbackPaused and not audioState.audioReloadInProgress and nowPlaying.trackId ~= ""
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
				pendingCrossfadeToken = audioState.audioTransitionTrackToken
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
			if crossfade and crossfade.active and pendingCrossfadeToken == audioState.audioTransitionTrackToken then
				-- Never race the in-flight deck commit with a second queue advance.
				-- The manager owns completion or cancellation; normal advance resumes
				-- on the next clock tick if preparation/fade/commit fails.
				shouldAdvance = false
			end
		end

		if serverShuttingDown then break end
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
	-- Settle accumulated XP once, then fence further accrual before final profile snapshots.
	xpService.StopAndSettle()
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
	local shutdownSource = audioState.activeAudioSource
	if shutdownSource and shutdownSource.kind == "Backend" and shutdownSource.backend then
		pcall(function() shutdownSource.backend:Stop() end)
		audioBackendManager.RetireBackend(shutdownSource.backend, "server shutdown active source")
	end
	if not audioBackendManager.DrainRetiredBackends("server shutdown") then
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
