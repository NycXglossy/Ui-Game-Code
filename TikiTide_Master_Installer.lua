--!strict
-- Tiki Tide MASTER INSTALLER
-- Run once from Roblox Studio > View > Command Bar with HTTP Requests enabled.
-- Stop Play/Run first. Back up the place before running.
-- Source snapshot is immutable: every downloaded script comes from one commit.
-- Playback and request queues remain server-local. Cross-server playback sync is DISABLED.
-- This installer does not create/replace remote endpoints, DataStores, purchases, or world assets.
-- SAFETY HOLD: source inventory is not yet complete and live-place parent mappings are unverified.
-- Do not remove this guard until the full script/package/hierarchy audit and Studio test pass.
error("[TikiTide Master Installer] SAFETY HOLD: not ready to run. Await the completed hierarchy-aware release.")

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

local RELEASE = "db9387c7e796694d647b09bdaf34dcadf1691c1a"
local BASE = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. RELEASE .. "/"
local BACKUP_ROOT = "TikiTide_MasterInstaller_Backups"

if RunService:IsRunning() then
    error("[TikiTide Installer] Stop Play/Run before installing. No changes made.")
end

type Entry = {path: string, className: string, parent: Instance, name: string}
local function folder(parent: Instance, name: string): Folder
    local found = parent:FindFirstChild(name)
    if found then
        if not found:IsA("Folder") then error(found:GetFullName() .. " exists but is not a Folder.") end
        return found
    end
    local f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
end

local audioFolder = folder(ServerStorage, "ClubMusicAudioModules")
local securityFolder = folder(ServerStorage, "ClubMusicSecurityCore")
local globalOptionalFolder = folder(ServerStorage, "ClubMusic_Global_Optional_Services")
local clientAudioFolder = folder(ReplicatedStorage, "ClubMusicClientAudioModules")

local entries: {Entry} = {}
local function add(path: string, className: string, parent: Instance, name: string?)
    table.insert(entries, {path=path, className=className, parent=parent, name=name or path:match("([^/]+)$"):gsub("%.client%.lua$", ""):gsub("%.server%.lua$", ""):gsub("%.luau$", ""):gsub("%.lua$", "")})
end

-- Core controller/UI pair
add("UI_Server_Controller_server (1).lua", "Script", ServerScriptService, "UI_Server_Controller")
add("UI_Renderer (2).lua", "ModuleScript", ReplicatedStorage, "UI_Renderer")
add("UI_Network.lua", "ModuleScript", ReplicatedStorage, "UI_Network")
add("ClubMusicBootstrap.client.lua", "LocalScript", StarterPlayerScripts, "ClubMusicBootstrap")
add("ClubMusicErrorHandler.lua", "ModuleScript", ReplicatedStorage, "ClubMusicErrorHandler")
add("ClubMusic_Overhead_Title_Renderer_client.lua", "LocalScript", StarterPlayerScripts, "ClubMusic_Overhead_Title_Renderer")

-- Modern audio modules; no legacy/global playback authority is installed.
for _, name in ipairs({
    "ClubMusicAudioBackend.luau", "ClubMusicAudioCrossfadeManager.luau",
    "ClubMusicAudioQualityProfiles.luau", "ClubMusicDJSessionManager.luau",
    "ClubMusicSpatialAudioGraph.luau"
}) do add(name, "ModuleScript", audioFolder) end
add("ClubMusicPlayerPreferences.luau", "ModuleScript", clientAudioFolder)
for _, name in ipairs({"MusicCoreService.lua","MusicPlaylistService.lua","MusicQueueManager.luau","MusicValidationService.luau"}) do
    add(name, "ModuleScript", ServerStorage)
end

-- Security Core module tree
for _, name in ipairs({
    "AccountRiskSignalService","AdaptiveSecurityLoadManager","AnimationIntegrityService","Audit",
    "Authorization","AvatarAccessoryValidationService","CharacterPhysicsGuard","ChatAbuseDetectionService",
    "ClientIntegrityTelemetry","ConnectionJanitor","EntitlementAuthority","EventLog","HoneypotManager",
    "Idempotency","IncidentResponse","MessageValidation","ModerationPunishmentService","MovementAuthority",
    "Phase32ServiceBundle","RateLimit","ReceiptAuthority","ReceiptHash","ReceiptTransactionService",
    "ResourceGuard","SanityValidation","SecurityMonitor","SecurityPolicy","SecurityReplayService",
    "SecurityThreatIntelligence","StaffSpectatorService","StorageGuard","TeleportValidationService"
}) do
    add("ClubMusicSecurityCore/" .. name .. ".lua", "ModuleScript", securityFolder)
end
add("SecurityServer.server.lua", "Script", ServerScriptService, "SecurityServer")
add("StaffActions.server.lua", "Script", ServerScriptService, "StaffActions")
add("RegularCommandsSecurityServer.lua", "ModuleScript", ServerScriptService, "RegularCommandsSecurityServer")
add("KohlsAdmin_ClubMusic_Addon.lua", "ModuleScript", ServerScriptService, "KohlsAdmin_ClubMusic_Addon")
add("ClientIntegrityTelemetry.client.lua", "LocalScript", StarterPlayerScripts, "ClientIntegrityTelemetry")
add("StaffSpectatorCamera.client.lua", "LocalScript", StarterPlayerScripts, "StaffSpectatorCamera")
add("TikiTideAdaptiveVisualQuality.client.lua", "LocalScript", StarterPlayerScripts, "TikiTideAdaptiveVisualQuality")
add("StarterPlayer/StarterPlayerScripts/SecurityClient.client.lua", "LocalScript", StarterPlayerScripts, "SecurityClient")
add("StarterPlayer/StarterPlayerScripts/SecurityConsole.client.lua", "LocalScript", StarterPlayerScripts, "SecurityConsole")
add("ClubMusic_SecuritySmokeTest.client.lua", "LocalScript", StarterPlayerScripts, "ClubMusic_SecuritySmokeTest")

-- Global moderation/announcement/config services only. Playback sync remains off.
add("ClubMusic_Global_Service_server_1.lua", "Script", ServerScriptService, "ClubMusic_Global_Service")
add("ClubMusic_Global_Config_Service.lua", "ModuleScript", globalOptionalFolder)
add("ClubMusic_Global_Diagnostics_Service.lua", "ModuleScript", globalOptionalFolder)
add("ClubMusic_Global_Maintenance_Service.lua", "ModuleScript", globalOptionalFolder)
add("ClubMusic_Global_SafeCall_Service.lua", "ModuleScript", globalOptionalFolder)
add("ClubMusic_Global_Security_Service.lua", "ModuleScript", globalOptionalFolder)
add("ClubMusic_Global_Event_Log_Service", "ModuleScript", globalOptionalFolder, "ClubMusic_Global_Event_Log_Service")
add("ClubMusic_Local_Service_Registry.lua", "ModuleScript", ServerStorage)
add("ClubMusic_Local_Watchdog_Service.lua", "ModuleScript", ServerStorage)
add("ClubMusic_Server_Health_Service.lua", "ModuleScript", ServerStorage)

-- Utility Bar
for _, name in ipairs({"UtilityBar.client.lua","UtilityBarActions.client.lua","UtilityBarPanels.client.lua","ToolShop.client.lua"}) do
    add("UtilityBar/" .. name, "LocalScript", StarterPlayerScripts)
end
for _, name in ipairs({"UtilityBarActions.server.lua","UtilityBarExtendedActions.server.lua","ToolShop.server.lua"}) do
    add("UtilityBar/" .. name, "Script", ServerScriptService)
end

-- Settings and social actions
add("TikiTideSettings/TikiTideSettings.client.lua", "LocalScript", StarterPlayerScripts, "TikiTideSettings")
add("TikiTideSettings/TikiTideSettingsService.server.lua", "Script", ServerScriptService, "TikiTideSettingsService")
add("TikiTideSocialActions.client.lua", "LocalScript", StarterPlayerScripts, "TikiTideSocialActions")
add("TikiTideSocialActions.server.lua", "Script", ServerScriptService, "TikiTideSocialActionsServer")
add("TikiTideSocialActions/AnimationConfig.lua", "ModuleScript", ServerScriptService, "AnimationConfig")
add("StarterPlayer/StarterPlayerScripts/TikiTideUnifiedLauncher.client.lua", "LocalScript", StarterPlayerScripts, "TikiTideUnifiedLauncher")

-- Stage every source before touching active scripts.
local staged = {}
for _, entry in ipairs(entries) do
    local ok, source = pcall(function() return HttpService:GetAsync(BASE .. entry.path, true) end)
    if not ok or type(source) ~= "string" or #source < 20 then
        error("[TikiTide Installer] Source staging failed for " .. entry.path .. ". Nothing has been replaced. " .. tostring(source))
    end
    local existing = entry.parent:FindFirstChild(entry.name)
    if existing and not existing:IsA(entry.className) then
        error("[TikiTide Installer] Type conflict at " .. existing:GetFullName() .. " (expected " .. entry.className .. "). Nothing has been replaced.")
    end
    table.insert(staged, {entry=entry, source=source, existing=existing})
end

local backup = folder(ServerStorage, BACKUP_ROOT)
local releaseBackup = folder(backup, DateTime.now():ToUnixTimestamp() .. "_" .. RELEASE:sub(1,8))
local backupCount, installedCount = 0, 0
local created = {}

local function makeScript(className: string): LuaSourceContainer
    return Instance.new(className) :: LuaSourceContainer
end

local ok, failure = pcall(function()
    for _, item in ipairs(staged) do
        local e = item.entry
        local old = item.existing
        if old then
            local snapshot = old:Clone()
            snapshot.Name = e.name .. "_Previous"
            snapshot.Parent = folder(releaseBackup, e.parent.Name)
            backupCount += 1
        end
        local replacement = makeScript(e.className)
        replacement.Name = e.name
        replacement.Source = item.source
        if replacement:IsA("BaseScript") then
            (replacement :: BaseScript).Disabled = true
        end
        replacement.Parent = e.parent
        table.insert(created, {replacement=replacement, old=old, entry=e})
        if old then old:Destroy() end
        if replacement:IsA("BaseScript") then
            (replacement :: BaseScript).Disabled = false
        end
        installedCount += 1
    end
end)

if not ok then
    for i = #created, 1, -1 do
        local item = created[i]
        pcall(function() item.replacement:Destroy() end)
        -- Backups remain in ServerStorage for manual recovery; do not guess how to restore a destroyed script.
    end
    error("[TikiTide Installer] Promotion stopped: " .. tostring(failure) .. ". Backups, if any, remain under ServerStorage/" .. BACKUP_ROOT .. ".")
end

print("======================================================")
print("[TikiTide Master Installer] COMPLETE")
print("Source commit: " .. RELEASE)
print("Scripts installed/updated: " .. installedCount)
print("Previous scripts backed up: " .. backupCount)
print("Backup folder: ServerStorage/" .. BACKUP_ROOT .. "/" .. releaseBackup.Name)
print("Playback sync: DISABLED; queues and Now Playing remain server-local.")
print("Legacy playback objects, remotes, DataStores, purchases, player data, and world assets were not deleted or modified.")
print("IMPORTANT: Review duplicate legacy scripts/remotes and run the Studio regression checklist before publishing.")
print("======================================================")
