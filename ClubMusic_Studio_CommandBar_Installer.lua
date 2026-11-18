-- ClubMusic audio ModuleScript installer
-- Five server audio modules, five controller-required ServerStorage core modules, and one client preferences module are pinned snapshots.
-- Playback and request queues remain controller-owned and server-local; cross-server playback synchronization is retired.
-- Run this entire script once in Roblox Studio's Command Bar (View > Command Bar).
-- Requires Game Settings > Security > Allow HTTP Requests.
-- This installs source modules only; it does NOT update the controller or renderer scripts.
-- The current controller performs playback quality inspection locally and no longer requires MusicPlaybackManager.
-- Existing MusicPlaybackManager instances are left untouched for live-place rollback/consumer reconciliation.
-- Queue/catalog/playlist/validation modules are installed as direct ServerStorage children,
-- matching the controller's direct-child path while also supporting the ServerStorage RBXMX folder layout.
-- Install all matching branch revisions together in a stopped test place before starting playback.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if RunService:IsRunning() then
    error("Installation blocked: stop Play/Run simulation before replacing ClubMusic modules.")
end

local modules = {
    {name = "ClubMusicAudioBackend", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/b8ee084b4dc001b084e4b36c79f02031097cbe76/ClubMusicAudioBackend.luau"},
    {name = "ClubMusicAudioCrossfadeManager", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/b8ee084b4dc001b084e4b36c79f02031097cbe76/ClubMusicAudioCrossfadeManager.luau"},
    {name = "ClubMusicAudioQualityProfiles", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/b8ee084b4dc001b084e4b36c79f02031097cbe76/ClubMusicAudioQualityProfiles.luau"},
    {name = "ClubMusicDJSessionManager", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/b8ee084b4dc001b084e4b36c79f02031097cbe76/ClubMusicDJSessionManager.luau"},
    {name = "ClubMusicPlayerPreferences", side = "client", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/b8ee084b4dc001b084e4b36c79f02031097cbe76/ClubMusicPlayerPreferences.luau"},
    {name = "ClubMusicSpatialAudioGraph", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/b8ee084b4dc001b084e4b36c79f02031097cbe76/ClubMusicSpatialAudioGraph.luau"},
}

local coreModules = {
    {name = "MusicCatalogService", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/b8ee084b4dc001b084e4b36c79f02031097cbe76/MusicCatalogService.lua"},
    {name = "MusicPlaylistService", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/b8ee084b4dc001b084e4b36c79f02031097cbe76/MusicPlaylistService.lua"},
    {name = "MusicQueueManager", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/b8ee084b4dc001b084e4b36c79f02031097cbe76/MusicQueueManager.lua"},
    {name = "MusicQueueManagerService", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/b8ee084b4dc001b084e4b36c79f02031097cbe76/MusicQueueManagerService.lua"},
    {name = "MusicValidationService", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/b8ee084b4dc001b084e4b36c79f02031097cbe76/MusicValidationService.lua"},
}

local destinations = {
    server = ServerStorage,
    client = ReplicatedStorage,
}
local folders = {
    server = "ClubMusicAudioModules",
    client = "ClubMusicClientAudioModules",
}

local staged = {}
for _, item in ipairs(modules) do
    local ok, source = pcall(function()
        return HttpService:GetAsync(item.url, true)
    end)
    if not ok or type(source) ~= "string" or #source < 100 then
        error("Could not retrieve " .. item.name .. ". Check HTTP requests and internet access. No modules have been installed yet.")
    end
    staged[item.name] = source
end

local stagedCore = {}
for _, item in ipairs(coreModules) do
    local ok, source = pcall(function()
        return HttpService:GetAsync(item.url, true)
    end)
    if not ok or type(source) ~= "string" or #source < 100 then
        error("Could not retrieve " .. item.name .. ". Check HTTP requests and internet access. No modules have been installed yet.")
    end
    stagedCore[item.name] = source
end

for side, parent in pairs(destinations) do
    local folder = parent:FindFirstChild(folders[side])
    if folder and not folder:IsA("Folder") then
        error("A non-Folder already uses the name " .. folders[side] .. " under " .. parent.Name .. ". Rename it before retrying.")
    end
end

-- Validate every existing destination before creating folders or replacing any source.
for side, parent in pairs(destinations) do
    local folder = parent:FindFirstChild(folders[side])
    if folder then
        for _, item in ipairs(modules) do
            if item.side == side then
                local existing = folder:FindFirstChild(item.name)
                if existing and not existing:IsA("ModuleScript") then
                    error("A non-ModuleScript already uses the name " .. item.name .. " under " .. folder:GetFullName() .. ". No source was overwritten.")
                end
            end
        end
    end
end

for _, item in ipairs(coreModules) do
    local existing = ServerStorage:FindFirstChild(item.name)
    if existing and not existing:IsA("ModuleScript") then
        error("A non-ModuleScript already uses the name " .. item.name .. " under ServerStorage. Rename it before retrying.")
    end
end

for side, parent in pairs(destinations) do
    local folder = parent:FindFirstChild(folders[side])
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = folders[side]
        folder.Parent = parent
    end
    for _, item in ipairs(modules) do
        if item.side == side then
            local existing = folder:FindFirstChild(item.name)
            if existing and not existing:IsA("ModuleScript") then
                error("A non-ModuleScript already uses the name " .. item.name .. ". No existing object was overwritten.")
            end
            local moduleScript = existing or Instance.new("ModuleScript")
            moduleScript.Name = item.name
            moduleScript.Source = staged[item.name]
            moduleScript.Parent = folder
        end
    end
end

for _, item in ipairs(coreModules) do
    local existing = ServerStorage:FindFirstChild(item.name)
    local moduleScript = existing or Instance.new("ModuleScript")
    moduleScript.Name = item.name
    moduleScript.Source = stagedCore[item.name]
    moduleScript.Parent = ServerStorage
end

print("[ClubMusic] Installed 5 audio support ModuleScripts in ServerStorage/" .. folders.server)
print("[ClubMusic] Installed 5 controller-required ServerStorage core ModuleScripts directly under ServerStorage.")
print("[ClubMusic] Installed 1 client ModuleScript in ReplicatedStorage/" .. folders.client)
print("[ClubMusic] Install this package with the matching controller and UI_Renderer from the same branch snapshot.")
print("[ClubMusic] Modern AudioPlayer is the only controller playback source. This installer does not create or delete legacy Sound objects; remove any old Sound/MusicGroup instances only after auditing live-place consumers.")
