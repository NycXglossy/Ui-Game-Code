--!strict
-- TIKI TIDE MASTER INSTALLER
-- One Command Bar installer for the repository-owned Tiki Tide / ClubMusic runtime.
-- Run from Roblox Studio > View > Command Bar with HTTP Requests enabled.
-- Stop Play/Run first. Back up the place. Test in an unpublished copy before publishing.
--
-- This source-based release does not require a .rbxl export. It uses documented
-- service paths, validates destination classes, preserves replaced instances,
-- and never deletes unknown descendants or third-party packages.
--
-- IMPORTANT: DRY_RUN defaults to true. Review the printed plan first. Set false
-- only when running in a backed-up test copy. Runtime verification is still required.
--
-- Playback isolation is enforced: the Global Service source is pinned to the
-- hard-disabled release, and MusicGlobalPlaybackAuthority is excluded/archived.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

local DRY_RUN = true

local REPO = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/"
local RELEASE = {
    runtime = "db9387c7e796694d647b09bdaf34dcadf1691c1a",
    audio = "6ec3766ef48f38eb2893f3385e4b4370ec0b7112",
    globalService = "03982721949665c4fc0fa7a29c54a70bce749339",
    security = "7ebc71e3a6fa9ef04e80d5f332e5f72617c8d288",
    threat = "5790cd0c61d2f1bd38fe8aab92f5a234e7ec7e87",
    phase32 = "6ae4883c2c260df61bf760b8637dd339bda33d7b",
    diagnostics = "a486f1f046fc187da8c59d46d91d64e96f3e710c",
}

if RunService:IsRunning() then
    error("[TikiTide Master Installer] Stop Play/Run before installing. No changes made.")
end

local function encodePath(path: string): string
    return (string.gsub(path, " ", "%%20"))
end

local function fetchSource(path: string, commit: string, minimum: number?): string
    local url = REPO .. commit .. "/" .. encodePath(path)
    local ok, result = pcall(function()
        return HttpService:GetAsync(url, true)
    end)
    if not ok or type(result) ~= "string" or #result < (minimum or 100) then
        error("[TikiTide Master Installer] Could not stage " .. path .. " from " .. commit .. ": " .. tostring(result))
    end
    return result
end

type Entry = {
    name: string,
    className: string,
    parentKey: string,
    source: string?,
    value: string?,
    sourcePath: string,
    optional: boolean?,
}

local entries: {Entry} = {}
local skippedOptional: {string} = {}

local function addSource(path: string, className: string, parentKey: string, name: string?, commit: string?, minimum: number?)
    local resolvedName = name or path:match("([^/]+)$")
    resolvedName = resolvedName:gsub("%.client%.lua$", ""):gsub("%.server%.lua$", ""):gsub("%.luau$", ""):gsub("%.lua$", "")
    table.insert(entries, {
        name = resolvedName,
        className = className,
        parentKey = parentKey,
        source = fetchSource(path, commit or RELEASE.runtime, minimum),
        sourcePath = path,
    })
end

local function addValue(name: string, className: string, parentKey: string, value: string, sourcePath: string)
    table.insert(entries, {name=name, className=className, parentKey=parentKey, value=value, sourcePath=sourcePath})
end

local function addRaw(name: string, className: string, parentKey: string, source: string, sourcePath: string)
    if type(source) ~= "string" or #source < 100 then error("Invalid staged source for " .. name) end
    table.insert(entries, {name=name, className=className, parentKey=parentKey, source=source, sourcePath=sourcePath})
end

-- Core controller and client UI.
addSource("UI_Server_Controller_server (1).lua", "Script", "ServerScriptService", "UI_Server_Controller")
addSource("UI_Renderer (2).lua", "ModuleScript", "ReplicatedStorage", "UI_Renderer")
addSource("UI_Network.lua", "ModuleScript", "ReplicatedStorage", "UI_Network")
addSource("ClubMusicBootstrap.client.lua", "LocalScript", "StarterPlayerScripts", "ClubMusicBootstrap")
addSource("ClubMusic_Overhead_Title_Renderer_client.lua", "LocalScript", "StarterPlayerScripts", "ClubMusic_Overhead_Title_Renderer")
addSource("ClubMusicErrorHandler.lua", "ModuleScript", "ServerStorage", "ClubMusicErrorHandler")

-- Modern AudioPlayer modules and controller-required core modules use their
-- dedicated immutable audio release. Do not install rollback-only adapters.
for _, item in ipairs({
    {"ClubMusicAudioBackend.luau", "ClubMusicAudioBackend"},
    {"ClubMusicAudioCrossfadeManager.luau", "ClubMusicAudioCrossfadeManager"},
    {"ClubMusicAudioQualityProfiles.luau", "ClubMusicAudioQualityProfiles"},
    {"ClubMusicDJSessionManager.luau", "ClubMusicDJSessionManager"},
    {"ClubMusicSpatialAudioGraph.luau", "ClubMusicSpatialAudioGraph"},
}) do
    addSource(item[1], "ModuleScript", "AudioModules", item[2], RELEASE.audio)
end
addSource("ClubMusicPlayerPreferences.luau", "ModuleScript", "ClientAudioModules", "ClubMusicPlayerPreferences", RELEASE.audio)
addSource("MusicCoreService.lua", "ModuleScript", "ServerStorage", "MusicCoreService", RELEASE.audio)
addSource("MusicPlaylistService.lua", "ModuleScript", "ServerStorage", "MusicPlaylistService", RELEASE.audio)

-- Security Core keeps its three certified source pins independent.
local securityModules = {
    "StorageGuard", "ResourceGuard", "ConnectionJanitor", "Authorization",
    "EntitlementAuthority", "AvatarAccessoryValidationService", "AnimationIntegrityService",
    "RateLimit", "MessageValidation", "Idempotency", "SecurityMonitor", "SecurityPolicy",
    "Audit", "EventLog", "IncidentResponse", "MovementAuthority", "CharacterPhysicsGuard",
    "SanityValidation", "TeleportValidationService", "StaffSpectatorService",
    "SecurityReplayService", "AdaptiveSecurityLoadManager", "HoneypotManager",
    "ClientIntegrityTelemetry", "ReceiptAuthority", "ReceiptHash", "ReceiptTransactionService",
}
for _, moduleName in ipairs(securityModules) do
    addSource("ClubMusicSecurityCore/" .. moduleName .. ".lua", "ModuleScript", "SecurityCore", moduleName, RELEASE.security)
end
addSource("ClubMusicSecurityCore/SecurityThreatIntelligence.lua", "ModuleScript", "SecurityCore", "SecurityThreatIntelligence", RELEASE.threat)
for _, moduleName in ipairs({"ModerationPunishmentService", "AccountRiskSignalService", "ChatAbuseDetectionService", "Phase32ServiceBundle"}) do
    addSource("ClubMusicSecurityCore/" .. moduleName .. ".lua", "ModuleScript", "SecurityCore", moduleName, RELEASE.phase32)
end

-- Reuse the exact detection-only bootstrap source embedded in the certified
-- Security Core installer; do not maintain a divergent hand-copied variant.
local securityInstallerSource = fetchSource("ClubMusic_Security_Core_Installer.lua", RELEASE.runtime)
local bootstrapMarker = "local bootstrapSource = [=["
local bootstrapStart = string.find(securityInstallerSource, bootstrapMarker, 1, true)
if not bootstrapStart then error("Security installer bootstrap source marker was not found.") end
bootstrapStart += #bootstrapMarker
local bootstrapEnd = string.find(securityInstallerSource, "]=]", bootstrapStart, true)
if not bootstrapEnd then error("Security installer bootstrap source terminator was not found.") end
local physicsBootstrapSource = string.sub(securityInstallerSource, bootstrapStart, bootstrapEnd - 1)
addRaw("TikiTideCharacterPhysicsGuardBootstrap", "Script", "ServerScriptService", physicsBootstrapSource, "embedded:ClubMusic_Security_Core_Installer.lua")

addSource("SecurityServer.server.lua", "Script", "ServerScriptService", "SecurityServer")
addSource("StaffActions.server.lua", "Script", "ServerScriptService", "StaffActions")
addSource("StarterPlayer/StarterPlayerScripts/SecurityClient.client.lua", "LocalScript", "StarterPlayerScripts", "SecurityClient")
addSource("StarterPlayer/StarterPlayerScripts/SecurityConsole.client.lua", "LocalScript", "StarterPlayerScripts", "SecurityConsole")
addSource("StaffSpectatorCamera.client.lua", "LocalScript", "StarterPlayerScripts", "TikiTideStaffSpectatorCamera", RELEASE.security)
addSource("ClientIntegrityTelemetry.client.lua", "LocalScript", "StarterPlayerScripts", "TikiTideClientIntegrityTelemetry", RELEASE.security)
addSource("TikiTideAdaptiveVisualQuality.client.lua", "LocalScript", "StarterPlayerScripts", "TikiTideAdaptiveVisualQuality", RELEASE.security)

-- Client-local diagnostics are independently pinned and are not the server
-- diagnostics/error-history module.
addSource("ClubMusic_Client_Diagnostics_Service.lua", "ModuleScript", "ReplicatedStorage", "ClubMusic_Client_Diagnostics_Service", RELEASE.diagnostics)
addSource("ClubMusic_Client_Diagnostics_Bootstrap.client.lua", "LocalScript", "StarterPlayerScripts", "ClubMusic_Client_Diagnostics_Bootstrap", RELEASE.diagnostics)

-- Global operational services. The patched Global Service hard-disables all
-- cross-server playback sync and rejects attempts to enable it.
local globalServiceSource = fetchSource("ClubMusic_Global_Service_server_1.lua", RELEASE.globalService)
if string.find(globalServiceSource, "MusicGlobalPlaybackAuthority", 1, true)
    or not string.find(globalServiceSource, "Cross-server playback synchronization is disabled in this release.", 1, true) then
    error("Global Service source did not pass the playback-isolation release check.")
end
addRaw("ClubMusic_Global_Service", "Script", "ServerScriptService", globalServiceSource, "ClubMusic_Global_Service_server_1.lua@" .. RELEASE.globalService)
addSource("ClubMusic_Global_Config_Service.lua", "ModuleScript", "GlobalOptional", "ClubMusic_Global_Config_Service")
addSource("ClubMusic_Global_Diagnostics_Service.lua", "ModuleScript", "GlobalOptional", "ClubMusic_Global_Diagnostics_Service")
addSource("ClubMusic_Global_Maintenance_Service.lua", "ModuleScript", "GlobalOptional", "ClubMusic_Global_Maintenance_Service")
addSource("ClubMusic_Global_SafeCall_Service.lua", "ModuleScript", "GlobalOptional", "ClubMusic_Global_SafeCall_Service")
addSource("ClubMusic_Global_Security_Service.lua", "ModuleScript", "GlobalOptional", "ClubMusic_Global_Security_Service")
addSource("ClubMusic_Local_Service_Registry.lua", "ModuleScript", "ServerStorage", "ClubMusic_Local_Service_Registry")
addSource("ClubMusic_Local_Watchdog_Service.lua", "ModuleScript", "ServerStorage", "ClubMusic_Local_Watchdog_Service")
addSource("ClubMusic_Server_Health_Service.lua", "ModuleScript", "ServerStorage", "ClubMusic_Server_Health_Service")

-- Extract only the three active optional services from the XML package. The
-- embedded MusicGlobalPlaybackAuthority is intentionally not extracted.
local packageXml = fetchSource("ClubMusic_Global_Optional_Services.rbxmx", RELEASE.runtime, 1000)
local packageAllowlist = {
    ClubMusic_Global_Event_Log_Service = true,
    ClubMusic_Global_RateLimit_Service = true,
    ClubMusic_Global_Authorization_Service = true,
}
local extracted = {}
local cursor = 1
while true do
    local itemStart = string.find(packageXml, '<Item class="ModuleScript"', cursor, true)
    if not itemStart then break end
    local itemEnd = string.find(packageXml, "</Item>", itemStart, true)
    if not itemEnd then error("Malformed global optional services RBXMX package.") end
    local block = string.sub(packageXml, itemStart, itemEnd + 6)
    local moduleName = string.match(block, '<string name="Name">(.-)</string>')
    if moduleName and packageAllowlist[moduleName] then
        local protectedStart = string.find(block, '<ProtectedString name="Source">', 1, true)
        local cdataMarker = protectedStart and string.find(block, "<![CDATA[", protectedStart, true)
        local sourceEnd = cdataMarker and string.find(block, "]]></ProtectedString>", cdataMarker + 9, true)
        if not protectedStart or not cdataMarker or not sourceEnd then error("Missing embedded Source for " .. moduleName) end
        local moduleSource = string.sub(block, cdataMarker + 9, sourceEnd - 1)
        if #moduleSource < 100 then error("Embedded module source is too short: " .. moduleName) end
        extracted[moduleName] = moduleSource
    end
    cursor = itemEnd + 7
end
for moduleName in pairs(packageAllowlist) do
    if not extracted[moduleName] then error("Global optional services package is missing " .. moduleName) end
    addRaw(moduleName, "ModuleScript", "GlobalOptional", extracted[moduleName], "embedded:ClubMusic_Global_Optional_Services.rbxmx")
end

-- Settings, social actions, unified launcher, and Utility Bar.
addSource("TikiTideSettings/TikiTideSettingsService.server.lua", "Script", "ServerScriptService", "TikiTideSettingsService")
addSource("TikiTideSettings/TikiTideSettings.client.lua", "LocalScript", "StarterPlayerScripts", "TikiTideSettings")
addSource("TikiTideSocialActions.server.lua", "Script", "ServerScriptService", "TikiTideSocialActionsServer")
addSource("TikiTideSocialActions/AnimationConfig.lua", "ModuleScript", "SocialConfig", "AnimationConfig")
addSource("TikiTideSocialActions.client.lua", "LocalScript", "StarterPlayerScripts", "TikiTideSocialActions")
addSource("StarterPlayer/StarterPlayerScripts/TikiTideUnifiedLauncher.client.lua", "LocalScript", "StarterPlayerScripts", "TikiTideUnifiedLauncher")

for _, item in ipairs({
    {"UtilityBar/UtilityBar.client.lua", "LocalScript", "UtilityBar"},
    {"UtilityBar/UtilityBarActions.client.lua", "LocalScript", "UtilityBarActions"},
    {"UtilityBar/UtilityBarPanels.client.lua", "LocalScript", "UtilityBarPanels"},
    {"UtilityBar/ToolShop.client.lua", "LocalScript", "ToolShop"},
    {"UtilityBar/UtilityBarActions.server.lua", "Script", "UtilityBarActions"},
    {"UtilityBar/UtilityBarExtendedActions.server.lua", "Script", "UtilityBarExtendedActions"},
    {"UtilityBar/ToolShop.server.lua", "Script", "ToolShop"},
}) do
    local parentKey = if string.find(item[1], ".client.", 1, true) then "StarterPlayerScripts" else "ServerScriptService"
    addSource(item[1], item[2], parentKey, item[3])
end

-- Optional Kohl's Admin adapters are installed only into existing external
-- package folders. The installer never creates/replaces Kohl's Admin itself.
local kohlsRoot = ServerScriptService:FindFirstChild("Kohl's Admin")
local configFolder = kohlsRoot and kohlsRoot:FindFirstChild("Config")
local configAddons = configFolder and configFolder:FindFirstChild("Addons")
local regularAddons = kohlsRoot and kohlsRoot:FindFirstChild("Addons")
if configAddons and configAddons:IsA("Folder") then
    addSource("KohlsAdmin_ClubMusic_Addon.lua", "ModuleScript", "KohlsConfigAddons", "ClubMusic")
else
    table.insert(skippedOptional, "KohlsAdmin_ClubMusic_Addon.lua — Kohl's Admin Config/Addons folder not found")
end
if regularAddons and regularAddons:IsA("Folder") then
    addSource("RegularCommandsSecurityServer.lua", "ModuleScript", "KohlsRegularAddons", "RegularCommandsSecurityServer")
else
    table.insert(skippedOptional, "RegularCommandsSecurityServer.lua — Kohl's Admin Addons folder not found")
end

-- Security manifest is consumed by the Global Service to reject mixed releases.
local securityManifest = "securityCoreRelease=" .. RELEASE.security
    .. ";phase32Release=" .. RELEASE.phase32
    .. ";threatIntelligenceRelease=" .. RELEASE.threat
    .. ";modules=" .. table.concat(securityModules, ",")
    .. ",SecurityThreatIntelligence,ModerationPunishmentService,AccountRiskSignalService,ChatAbuseDetectionService,Phase32ServiceBundle"
    .. ";visualClient=TikiTideAdaptiveVisualQuality;installedBy=TikiTideMasterInstaller"
addValue("InstallManifest", "StringValue", "SecurityCore", securityManifest, "generated:SecurityCoreInstallManifest")
addValue("TikiTideMasterInstallManifest", "StringValue", "ServerStorage",
    "runtime=" .. RELEASE.runtime .. ";audio=" .. RELEASE.audio .. ";globalService=" .. RELEASE.globalService
    .. ";security=" .. RELEASE.security .. ";threat=" .. RELEASE.threat .. ";phase32=" .. RELEASE.phase32
    .. ";diagnostics=" .. RELEASE.diagnostics .. ";playbackSync=DISABLED;localQueues=ENFORCED",
    "generated:TikiTideMasterInstallManifest")

-- Destination folders are deterministic and only created when absent.
local createdFolders: {Folder} = {}
local function ensureFolder(parent: Instance, name: string): Folder
    local existing = parent:FindFirstChild(name)
    if existing then
        if not existing:IsA("Folder") then error(parent:GetFullName() .. "/" .. name .. " exists but is not a Folder.") end
        return existing
    end
    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    table.insert(createdFolders, folder)
    return folder
end

local backupRootExisting = ServerStorage:FindFirstChild("TikiTide_MasterInstaller_Backups")
if backupRootExisting and not backupRootExisting:IsA("Folder") then
    error("ServerStorage/TikiTide_MasterInstaller_Backups exists but is not a Folder.")
end

local parents: {[string]: Instance} = {
    ServerScriptService = ServerScriptService,
    ReplicatedStorage = ReplicatedStorage,
    ServerStorage = ServerStorage,
    StarterPlayerScripts = StarterPlayerScripts,
}
if configAddons and configAddons:IsA("Folder") then parents.KohlsConfigAddons = configAddons end
if regularAddons and regularAddons:IsA("Folder") then parents.KohlsRegularAddons = regularAddons end

local function peekParent(parentKey: string): Instance?
    if parentKey == "AudioModules" then return ServerStorage:FindFirstChild("ClubMusicAudioModules") end
    if parentKey == "ClientAudioModules" then return ReplicatedStorage:FindFirstChild("ClubMusicClientAudioModules") end
    if parentKey == "GlobalOptional" then return ServerStorage:FindFirstChild("ClubMusic_Global_Optional_Services") end
    if parentKey == "SecurityCore" then return ServerStorage:FindFirstChild("ClubMusicSecurityCore") end
    if parentKey == "SocialConfig" then
        local socialScript = ServerScriptService:FindFirstChild("TikiTideSocialActionsServer")
        return socialScript and socialScript:FindFirstChild("TikiTideSocialActions") or nil
    end
    return parents[parentKey]
end

local function resolveParent(parentKey: string): Instance
    if parentKey == "AudioModules" then return ensureFolder(ServerStorage, "ClubMusicAudioModules") end
    if parentKey == "ClientAudioModules" then return ensureFolder(ReplicatedStorage, "ClubMusicClientAudioModules") end
    if parentKey == "GlobalOptional" then return ensureFolder(ServerStorage, "ClubMusic_Global_Optional_Services") end
    if parentKey == "SecurityCore" then return ensureFolder(ServerStorage, "ClubMusicSecurityCore") end
    if parentKey == "SocialConfig" then
        local socialScript = ServerScriptService:FindFirstChild("TikiTideSocialActionsServer")
        if not socialScript or not socialScript:IsA("Script") then error("Social Actions server Script was not staged before its config folder.") end
        return ensureFolder(socialScript, "TikiTideSocialActions")
    end
    local parent = parents[parentKey]
    if not parent then error("Unknown or unavailable destination parent: " .. parentKey) end
    return parent
end

-- Validate unique manifest destinations and exact destination classes before
-- moving any existing instance.
local destinationKeys = {}
for _, entry in ipairs(entries) do
    local key = entry.parentKey .. "/" .. entry.name
    if destinationKeys[key] then error("Duplicate manifest destination: " .. key) end
    destinationKeys[key] = true
    local parent = peekParent(entry.parentKey)
    if parent then
        if (entry.parentKey == "AudioModules" or entry.parentKey == "ClientAudioModules"
            or entry.parentKey == "GlobalOptional" or entry.parentKey == "SecurityCore"
            or entry.parentKey == "SocialConfig") and not parent:IsA("Folder") then
            error(parent:GetFullName() .. " exists but is not a Folder.")
        end
        local existing = parent:FindFirstChild(entry.name)
        if existing and not existing:IsA(entry.className) then
            error(parent:GetFullName() .. "/" .. entry.name .. " has class " .. existing.ClassName
                .. "; expected " .. entry.className .. ". No scripts were replaced.")
        end
        if existing and not existing.Archivable then
            error(parent:GetFullName() .. "/" .. entry.name .. " is not Archivable and cannot be safely backed up.")
        end
    end
end

-- The retired authority must not remain anywhere under ServerStorage because
-- the Global Service historically searched recursively for this module.
local retiredAuthorities = {}
for _, descendant in ipairs(ServerStorage:GetDescendants()) do
    if descendant.Name == "MusicGlobalPlaybackAuthority" then
        if not descendant:IsA("ModuleScript") then
            error("A non-ModuleScript named MusicGlobalPlaybackAuthority exists under ServerStorage.")
        end
        table.insert(retiredAuthorities, descendant)
    end
end

local sourceScriptCount = 0
for _, entry in ipairs(entries) do
    if entry.className == "Script" or entry.className == "LocalScript" or entry.className == "ModuleScript" then
        sourceScriptCount += 1
    end
end
print("======================================================")
print("[TikiTide Master Installer] Source staging and preflight passed.")
print("Runtime source instances: " .. sourceScriptCount)
print("Security Core modules: " .. (#securityModules + 5))
print("Embedded global modules: " .. #({ "ClubMusic_Global_Event_Log_Service", "ClubMusic_Global_RateLimit_Service", "ClubMusic_Global_Authorization_Service" }))
print("Existing retired playback authority instances to archive: " .. #retiredAuthorities)
print("Playback synchronization: DISABLED; per-server Now Playing and request queues.")
print("Kohl's Admin adapters pending: " .. #skippedOptional)
for _, message in ipairs(skippedOptional) do print("[TikiTide Master Installer] OPTIONAL: " .. message) end
if DRY_RUN then
    print("[TikiTide Master Installer] DRY RUN ONLY. No existing scripts were replaced and no staged sources were promoted.")
    print("Set DRY_RUN = false only in a backed-up unpublished test place after reviewing this plan.")
    print("======================================================")
    return
end

local backupRoot = backupRootExisting or ensureFolder(ServerStorage, "TikiTide_MasterInstaller_Backups")
local backupName = DateTime.now():ToUnixTimestamp() .. "_" .. HttpService:GenerateGUID(false) .. "_" .. RELEASE.runtime:sub(1,8)
local backupRelease = ensureFolder(backupRoot, backupName)
local replacements = {}
local promoted = {}

local function makeInstance(entry: Entry): Instance
    local object = Instance.new(entry.className)
    object.Name = entry.name
    if entry.source then
        (object :: any).Source = entry.source
    elseif entry.value then
        (object :: any).Value = entry.value
    end
    if object:IsA("BaseScript") then object.Disabled = true end
    return object
end

local ok, failure = pcall(function()
    -- Archive retired authority modules first, preserving their original parent.
    for _, old in ipairs(retiredAuthorities) do
        local oldParent = old.Parent
        local oldName = old.Name
        old.Name = oldName .. "__Retired"
        old.Parent = backupRelease
        table.insert(replacements, {old=old, parent=oldParent, name=oldName, disabled=nil})
    end

    for _, entry in ipairs(entries) do
        local parent = resolveParent(entry.parentKey)
        local old = parent:FindFirstChild(entry.name)
        local oldDisabled = if old and old:IsA("BaseScript") then old.Disabled else nil
        if old then
            if old:IsA("BaseScript") then old.Disabled = true end
            old.Name = entry.name .. "__Previous"
            old.Parent = backupRelease
            table.insert(replacements, {old=old, parent=parent, name=entry.name, disabled=oldDisabled})
        end

        local replacement = makeInstance(entry)
        replacement.Parent = parent
        table.insert(promoted, replacement)
    end

    -- All new instances are in place and disabled. Start shared services before
    -- consumers, then enable the remaining scripts.
    local priority = {
        ClubMusic_Global_Service = 1,
        SecurityServer = 2,
        TikiTideCharacterPhysicsGuardBootstrap = 3,
        StaffActions = 4,
        UI_Server_Controller = 5,
        TikiTideSettingsService = 6,
        TikiTideSocialActionsServer = 7,
        UtilityBarActions = 8,
        UtilityBarExtendedActions = 9,
        ToolShop = 10,
    }
    table.sort(promoted, function(a, b)
        local ap = priority[a.Name] or 100
        local bp = priority[b.Name] or 100
        if ap == bp then return a.Name < b.Name end
        return ap < bp
    end)
    for _, object in ipairs(promoted) do
        if object:IsA("BaseScript") then
            object.Disabled = false
            if object:IsA("Script") then task.wait(0.05) end
        end
    end
end)

if not ok then
    for i = #promoted, 1, -1 do pcall(function() promoted[i]:Destroy() end) end
    for i = #replacements, 1, -1 do
        local item = replacements[i]
        pcall(function()
            item.old.Name = item.name
            item.old.Parent = item.parent
            if item.old:IsA("BaseScript") and item.disabled ~= nil then item.old.Disabled = item.disabled end
        end)
    end
    for i = #createdFolders, 1, -1 do
        local folder = createdFolders[i]
        pcall(function() if #folder:GetChildren() == 0 then folder:Destroy() end end)
    end
    error("[TikiTide Master Installer] Promotion failed and prior instances were restored: " .. tostring(failure))
end

print("======================================================")
print("[TikiTide Master Installer] INSTALL PROMOTION COMPLETE")
print("Source release: " .. RELEASE.runtime)
print("Audio release: " .. RELEASE.audio)
print("Global Service hard-disabled release: " .. RELEASE.globalService)
print("Security Core release: " .. RELEASE.security)
print("Threat Intelligence release: " .. RELEASE.threat)
print("Phase 32 release: " .. RELEASE.phase32)
print("Client diagnostics release: " .. RELEASE.diagnostics)
print("Instances promoted: " .. #promoted)
print("Prior instances and retired playback authority archived under ServerStorage/" .. backupRoot.Name .. "/" .. backupRelease.Name)
print("Playback synchronization: DISABLED. No leader lease or shared playback snapshots are installed.")
print("Server-owned AudioPlayer remains the only playback source; each server keeps its own queue and Now Playing state.")
print("No player data, DataStores, purchases, world assets, or unknown descendants were deleted.")
print("Configure owned Social Action animation IDs and supply approved TikiTideMounts models separately.")
print("Tool Shop catalog intentionally remains empty until configured.")
print("Run the full copied-place regression checklist before publishing.")
print("======================================================")
