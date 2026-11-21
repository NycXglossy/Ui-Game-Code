--!strict
-- CLUB NEON PROJECT CONFIGURATION
-- Dedicated target configuration. Do not copy Tiki Tide IDs or datastore keys here.
-- Keep monetization disabled until Club Neon-owned IDs are supplied and verified.

local Config = {
  Project = { Name = "Club Neon", Brand = "CLUB NEON", ShortBrand = "NEON", DataStorePrefix = "ClubNeon_v1", ReleaseChannel = "production" },
  Permissions = {
    OwnerUserIds = {}, -- REQUIRED: add actual Club Neon owner UserId(s) before live installation.
    CoOwnerUserIds = {}, AdminUserIds = {}, ModeratorUserIds = {}, DJUserIds = {},
    GroupId = 0, -- 0 disables group-rank integration until Club Neon supplies its group ID.
    RankThresholds = { Owner = 255, CoOwner = 254, Admin = 200, Moderator = 150, DJ = 100 },
    StudioOwnerBypass = false,
  },
  Monetization = {
    Enabled = false,
    GamePasses = { VIP = 0, VVIP = 0, Elite = 0, IslandMount = 0, Companion = 0, StageLighting = 0 },
    DeveloperProducts = { XPBoost2x = 0, XPBoost4x = 0, TitleSlot2 = 0, TitleSlot3 = 0, Donations = {} },
  },
  Features = {
    MusicRequests = true, ModernAudioPlayer = true, Crossfade = true, DJControls = true, AutoDJ = true,
    Playlists = true, CustomTitles = true, StaffTools = true, SecurityCore = true, ThreatIntelligence = true,
    Diagnostics = true, UtilityBar = true, Settings = true, SocialActions = true, ToolShop = true,
    Mounts = true, Companions = true, StageLighting = true, GlobalModeration = true, GlobalAnnouncements = true,
    GlobalCatalogInvalidation = true, GlobalReceiptCoordination = true, CrossServerPlaybackSync = false,
  },
  Playback = { Mode = "ServerLocal", QueueScope = "PerServer", PlaybackClockScope = "PerServer", AutoDJScope = "PerServer", SkipVotesScope = "PerServer" },
  Storage = {
    Prefix = "ClubNeon_v1", ProfileStore = "ClubNeon_v1_PlayerProfiles",
    ModerationStore = "ClubNeon_v1_GlobalModeration", GlobalControlStore = "ClubNeon_v1_GlobalControls",
    GlobalConfigStore = "ClubNeon_v1_GlobalConfig", ReceiptStore = "ClubNeon_v1_Receipts",
    ToolShopCoinsStore = "ClubNeon_v1_ToolShopCoins",
  },
  Safety = { RequireOwnerConfigured = true, RequireMonetizationIdsVerified = true,
    FailClosedOnMissingStaffConfig = true, PreserveExistingMapAssets = true,
    PreserveInteractionAnimations = true, PreserveThirdPartyAdmin = true, NeverInstallRetiredPlaybackAuthority = true },
}
return Config