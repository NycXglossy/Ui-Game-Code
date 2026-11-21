--!strict
-- CLUB NEON MASTER INSTALLER v0.3.0
-- One Command Bar installer for the repository-owned Club Neon / ClubMusic runtime.
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

local INSTALLER_VERSION = "0.3.0"
local DRY_RUN = true -- Set false only after ClubNeon_Config.lua is completed and a place backup exists.

local REPO = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/"
local RELEASE = {
    runtime = "1314c10dba2f7fb656cd42e3e80551af686cb652",
    audio = "6ec3766ef48f38eb2893f3385e4b4370ec0b7112",
    globalService = "1314c10dba2f7fb656cd42e3e80551af686cb652",
    security = "1314c10dba2f7fb656cd42e3e80551af686cb652",
    threat = "1314c10dba2f7fb656cd42e3e80551af686cb652",
    phase32 = "1314c10dba2f7fb656cd42e3e80551af686cb652",
    diagnostics = "a486f1f046fc187da8c59d46d91d64e96f3e710c",
}

if RunService:IsRunning() then
    error("[ClubNeon Master Installer] Stop Play/Run before installing. No changes made.")
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
        error("[ClubNeon Master Installer] Could not stage " .. path .. " from " .. commit .. ": " .. tostring(result))
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

-- Project config must be staged before any runtime service can start.
local projectConfigSource = fetchSource("ClubNeon_Config.lua", RELEASE.runtime)
local ownerList = string.match(projectConfigSource, "OwnerUserIds%s*=%s*%{([^}]*)%}") or ""
local configuredGroupId = string.match(projectConfigSource, "GroupId%s*=%s*(%d+)") or "0"
if not DRY_RUN and string.gsub(ownerList, "%s", "") == "" then
    error("[Club Neon Master Installer] Configure at least one OwnerUserId in ClubNeon_Config.lua before live installation. No changes made.")
end
addRaw("ClubNeon_Config", "ModuleScript", "ServerStorage", projectConfigSource, "ClubNeon_Config.lua@" .. RELEASE.runtime)

-- Core controller and client UI. Validate project isolation before staging.
local controllerSource = fetchSource("ClubNeon_UI_Server_Controller.server.lua", RELEASE.runtime)
if not string.find(controllerSource, "EnableGlobalPlaybackSync = false", 1, true)
    or string.find(controllerSource, "MusicGlobalPlaybackAuthority", 1, true) then
    error("Club Neon controller failed the local-playback isolation check.")
end
for _, forbiddenId in ipairs({500470662,2089785323,2089263330,2087955353,2088891595,2089053637,2087955619,2088585676,2088315619,3731386650,3731387153,3731392651,3731394060,3731488823,3731489572,3731490154,3731490513,3731490937,3731491257,3731491679}) do
    if string.find(controllerSource, tostring(forbiddenId), 1, true) then
        error("Club Neon controller contains an inherited project ID: " .. tostring(forbiddenId))
    end
end
addRaw("UI_Server_Controller", "Script", "ServerScriptService", controllerSource, "ClubNeon_UI_Server_Controller.server.lua@" .. RELEASE.runtime)

local rendererSource = fetchSource("ClubNeon_UI_Renderer.lua", RELEASE.runtime)
for _, forbiddenId in ipairs({2089785323,2089263330,2087955353,2088891595,2089053637,2087955619,2088585676,2088315619,3731386650,3731387153,3731392651,3731394060,3731488823,3731489572,3731490154,3731490513,3731490937,3731491257,3731491679}) do
    if string.find(rendererSource, tostring(forbiddenId), 1, true) then
        error("Club Neon renderer contains an inherited purchase ID: " .. tostring(forbiddenId))
    end
end
addRaw("ClubNeon_UI_Renderer", "ModuleScript", "ReplicatedStorage", rendererSource, "ClubNeon_UI_Renderer.lua@" .. RELEASE.runtime)

local networkSource = fetchSource("ClubNeon_UI_Network.lua", RELEASE.runtime)
if not string.find(networkSource, 'FOLDER_NAME = "ClubMusicRemotes"', 1, true) then
    error("Club Neon network remote contract does not match its server controller.")
end
addRaw("ClubNeon_UI_Network", "ModuleScript", "ReplicatedStorage", networkSource, "ClubNeon_UI_Network.lua@" .. RELEASE.runtime)
addSource("ClubNeonBootstrap.client.lua", "LocalScript", "StarterPlayerScripts", "ClubNeonBootstrap")
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
    addSource("ClubNeonSecurityCore/" .. moduleName .. ".lua", "ModuleScript", "SecurityCore", moduleName, RELEASE.security)
end
addSource("ClubNeonSecurityCore/SecurityThreatIntelligence.lua", "ModuleScript", "SecurityCore", "SecurityThreatIntelligence", RELEASE.threat)
for _, moduleName in ipairs({"ModerationPunishmentService", "AccountRiskSignalService", "ChatAbuseDetectionService", "Phase32ServiceBundle"}) do
    addSource("ClubNeonSecurityCore/" .. moduleName .. ".lua", "ModuleScript", "SecurityCore", moduleName, RELEASE.phase32)
end

-- Reuse the exact detection-only bootstrap source embedded in the certified
-- Security Core installer; do not maintain a divergent hand-copied variant.
local securityInstallerSource = fetchSource("ClubNeon_Security_Core_Installer.lua", RELEASE.runtime)
local bootstrapMarker = "local bootstrapSource = [=["
local bootstrapStart = string.find(securityInstallerSource, bootstrapMarker, 1, true)
if not bootstrapStart then error("Security installer bootstrap source marker was not found.") end
bootstrapStart += #bootstrapMarker
local bootstrapEnd = string.find(securityInstallerSource, "]=]", bootstrapStart, true)
if not bootstrapEnd then error("Security installer bootstrap source terminator was not found.") end
local physicsBootstrapSource = string.sub(securityInstallerSource, bootstrapStart, bootstrapEnd - 1)
addRaw("ClubNeonCharacterPhysicsGuardBootstrap", "Script", "ServerScriptService", physicsBootstrapSource, "embedded:ClubNeon_Security_Core_Installer.lua")

addSource("ClubNeonSecurityServer.server.lua", "Script", "ServerScriptService", "ClubNeonSecurityServer")
addSource("ClubNeonStaffActions.server.lua", "Script", "ServerScriptService", "ClubNeonStaffActions")
addSource("ClubNeon_SecurityClient.client.lua", "LocalScript", "StarterPlayerScripts", "ClubNeonSecurityClient")
addSource("ClubNeon_SecurityConsole.client.lua", "LocalScript", "StarterPlayerScripts", "ClubNeonSecurityConsole")
addSource("ClubNeon_StaffSpectatorCamera.client.lua", "LocalScript", "StarterPlayerScripts", "ClubNeonStaffSpectatorCamera", RELEASE.security)
addSource("ClubNeonClientIntegrityTelemetry.client.lua", "LocalScript", "StarterPlayerScripts", "ClubNeonClientIntegrityTelemetry", RELEASE.security)
addSource("ClubNeonAdaptiveVisualQuality.client.lua", "LocalScript", "StarterPlayerScripts", "ClubNeonAdaptiveVisualQuality", RELEASE.security)

-- Client-local diagnostics are independently pinned and are not the server
-- diagnostics/error-history module.
addSource("ClubMusic_Client_Diagnostics_Service.lua", "ModuleScript", "ReplicatedStorage", "ClubMusic_Client_Diagnostics_Service", RELEASE.diagnostics)
addSource("ClubMusic_Client_Diagnostics_Bootstrap.client.lua", "LocalScript", "StarterPlayerScripts", "ClubMusic_Client_Diagnostics_Bootstrap", RELEASE.diagnostics)

-- Global operational services. The patched Global Service hard-disables all
-- cross-server playback sync and rejects attempts to enable it.
local globalServiceSource = fetchSource("ClubNeon_Global_Service.server.lua", RELEASE.globalService)
if string.find(globalServiceSource, "MusicGlobalPlaybackAuthority", 1, true)
    or not string.find(globalServiceSource, "Cross-server playback synchronization is disabled in this release.", 1, true) then
    error("Global Service source did not pass the playback-isolation release check.")
end
addRaw("ClubNeon_Global_Service", "Script", "ServerScriptService", globalServiceSource, "ClubNeon_Global_Service.server.lua@" .. RELEASE.globalService)
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
        moduleSource = moduleSource:gsub("TikiTide", "ClubNeon"):gsub("Tiki Tide", "Club Neon"):gsub("500470662", configuredGroupId)
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
addSource("ClubNeonSettings/ClubNeonSettingsService.server.lua", "Script", "ServerScriptService", "ClubNeonSettingsService")
addSource("ClubNeonSettings/ClubNeonSettings.client.lua", "LocalScript", "StarterPlayerScripts", "ClubNeonSettings")
addSource("ClubNeonSocialActions.server.lua", "Script", "ServerScriptService", "ClubNeonSocialActionsServer")
addSource("ClubNeonSocialActions/AnimationConfig.lua", "ModuleScript", "SocialConfig", "AnimationConfig")
addSource("ClubNeonSocialActions.client.lua", "LocalScript", "StarterPlayerScripts", "ClubNeonSocialActions")
addSource("ClubNeonUnifiedLauncher.client.lua", "LocalScript", "StarterPlayerScripts", "ClubNeonUnifiedLauncher")

for _, item in ipairs({
    {"ClubNeonUtilityBar/UtilityBar.client.lua", "LocalScript", "UtilityBar"},
    {"ClubNeonUtilityBar/UtilityBarActions.client.lua", "LocalScript", "UtilityBarActions"},
    {"ClubNeonUtilityBar/UtilityBarPanels.client.lua", "LocalScript", "UtilityBarPanels"},
    {"ClubNeonUtilityBar/ToolShop.client.lua", "LocalScript", "ToolShop"},
    {"ClubNeonUtilityBar/UtilityBarActions.server.lua", "Script", "UtilityBarActions"},
    {"ClubNeonUtilityBar/UtilityBarExtendedActions.server.lua", "Script", "UtilityBarExtendedActions"},
    {"ClubNeonUtilityBar/ToolShop.server.lua", "Script", "ToolShop"},
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
    addSource("KohlsAdmin_ClubNeon_Addon.lua", "ModuleScript", "KohlsConfigAddons", "ClubNeon")
else
    table.insert(skippedOptional, "KohlsAdmin_ClubNeon_Addon.lua — Kohl's Admin Config/Addons folder not found")
end
if regularAddons and regularAddons:IsA("Folder") then
    addSource("ClubNeonRegularCommandsSecurityServer.lua", "ModuleScript", "KohlsRegularAddons", "ClubNeonRegularCommandsSecurityServer")
else
    table.insert(skippedOptional, "ClubNeonRegularCommandsSecurityServer.lua — Kohl's Admin Addons folder not found")
end

-- Security manifest is consumed by the Global Service to reject mixed releases.
local securityManifest = "securityCoreRelease=" .. RELEASE.security
    .. ";phase32Release=" .. RELEASE.phase32
    .. ";threatIntelligenceRelease=" .. RELEASE.threat
    .. ";modules=" .. table.concat(securityModules, ",")
    .. ",SecurityThreatIntelligence,ModerationPunishmentService,AccountRiskSignalService,ChatAbuseDetectionService,Phase32ServiceBundle"
    .. ";visualClient=ClubNeonAdaptiveVisualQuality;installedBy=ClubNeonMasterInstaller"
addValue("InstallManifest", "StringValue", "SecurityCore", securityManifest, "generated:SecurityCoreInstallManifest")
addValue("ClubNeonMasterInstallManifest", "StringValue", "ServerStorage",
    "runtime=" .. RELEASE.runtime .. ";audio=" .. RELEASE.audio .. ";globalService=" .. RELEASE.globalService
    .. ";security=" .. RELEASE.security .. ";threat=" .. RELEASE.threat .. ";phase32=" .. RELEASE.phase32
    .. ";diagnostics=" .. RELEASE.diagnostics .. ";playbackSync=DISABLED;localQueues=ENFORCED",
    "generated:ClubNeonMasterInstallManifest")

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

local backupRootExisting = ServerStorage:FindFirstChild("ClubNeon_MasterInstaller_Backups")
if backupRootExisting and not backupRootExisting:IsA("Folder") then
    error("ServerStorage/ClubNeon_MasterInstaller_Backups exists but is not a Folder.")
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
    if parentKey == "SecurityCore" then return ServerStorage:FindFirstChild("ClubNeonSecurityCore") end
    if parentKey == "SocialConfig" then
        local socialScript = ServerScriptService:FindFirstChild("ClubNeonSocialActionsServer")
        return socialScript and socialScript:FindFirstChild("ClubNeonSocialActions") or nil
    end
    return parents[parentKey]
end

local function resolveParent(parentKey: string): Instance
    if parentKey == "AudioModules" then return ensureFolder(ServerStorage, "ClubMusicAudioModules") end
    if parentKey == "ClientAudioModules" then return ensureFolder(ReplicatedStorage, "ClubMusicClientAudioModules") end
    if parentKey == "GlobalOptional" then return ensureFolder(ServerStorage, "ClubMusic_Global_Optional_Services") end
    if parentKey == "SecurityCore" then return ensureFolder(ServerStorage, "ClubNeonSecurityCore") end
    if parentKey == "SocialConfig" then
        local socialScript = ServerScriptService:FindFirstChild("ClubNeonSocialActionsServer")
        if not socialScript or not socialScript:IsA("Script") then error("Social Actions server Script was not staged before its config folder.") end
        return ensureFolder(socialScript, "ClubNeonSocialActions")
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
print("[ClubNeon Master Installer] v" .. INSTALLER_VERSION .. " source staging and preflight passed.")
print("Runtime source instances: " .. sourceScriptCount)
print("Security Core modules: " .. (#securityModules + 5))
print("Embedded global modules: " .. #({ "ClubMusic_Global_Event_Log_Service", "ClubMusic_Global_RateLimit_Service", "ClubMusic_Global_Authorization_Service" }))
print("Existing retired playback authority instances to archive: " .. #retiredAuthorities)
print("Playback synchronization: DISABLED; per-server Now Playing and request queues.")
print("Kohl's Admin adapters pending: " .. #skippedOptional)
for _, message in ipairs(skippedOptional) do print("[ClubNeon Master Installer] OPTIONAL: " .. message) end
if DRY_RUN then
    print("[ClubNeon Master Installer] DRY RUN ONLY. No existing scripts were replaced and no staged sources were promoted.")
    print("Set DRY_RUN = false only in a backed-up unpublished test place after reviewing this plan.")
    print("======================================================")
    return
end

local backupRoot = backupRootExisting or ensureFolder(ServerStorage, "ClubNeon_MasterInstaller_Backups")
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
        ClubNeonCharacterPhysicsGuardBootstrap = 3,
        StaffActions = 4,
        UI_Server_Controller = 5,
        ClubNeonSettingsService = 6,
        ClubNeonSocialActionsServer = 7,
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
    error("[ClubNeon Master Installer] Promotion failed and prior instances were restored: " .. tostring(failure))
end

print("======================================================")
print("[ClubNeon Master Installer] INSTALL PROMOTION COMPLETE")
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
print("Configure owned Social Action animation IDs and supply approved ClubNeonMounts models separately.")
print("Tool Shop catalog intentionally remains empty until configured.")
print("Run the full copied-place regression checklist before publishing.")
print("======================================================")
