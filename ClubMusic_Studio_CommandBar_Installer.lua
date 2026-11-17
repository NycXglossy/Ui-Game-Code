-- ClubMusic audio ModuleScript installer
-- The six package modules are pinned to the audited audio package snapshot. The controller playback adapter is pinned separately below.
-- Playback and queues are server-local; this package does not install global queue/playback services.
-- Run this entire script once in Roblox Studio's Command Bar (View > Command Bar).
-- Requires Game Settings > Security > Allow HTTP Requests.
-- This installs source modules only; it does NOT update the controller or renderer scripts.
-- MusicPlaybackManager is installed as a direct ServerStorage child because the controller requires that exact path.
-- Install all matching branch revisions together in a stopped test place before starting playback.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = {
    {name = "ClubMusicAudioBackend", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/8edd537a30f002e39bd437a6d77f74e5ce66c2c6/ClubMusicAudioBackend.luau"},
    {name = "ClubMusicAudioCrossfadeManager", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/8edd537a30f002e39bd437a6d77f74e5ce66c2c6/ClubMusicAudioCrossfadeManager.luau"},
    {name = "ClubMusicAudioQualityProfiles", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/8edd537a30f002e39bd437a6d77f74e5ce66c2c6/ClubMusicAudioQualityProfiles.luau"},
    {name = "ClubMusicDJSessionManager", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/8edd537a30f002e39bd437a6d77f74e5ce66c2c6/ClubMusicDJSessionManager.luau"},
    {name = "ClubMusicPlayerPreferences", side = "client", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/8edd537a30f002e39bd437a6d77f74e5ce66c2c6/ClubMusicPlayerPreferences.luau"},
    {name = "ClubMusicSpatialAudioGraph", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/8edd537a30f002e39bd437a6d77f74e5ce66c2c6/ClubMusicSpatialAudioGraph.luau"},
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

local playbackManagerUrl = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/44ad160be15ac14eca7907d7158fc81bae865c67/MusicPlaybackManager.luau"
local playbackManagerOk, playbackManagerSource = pcall(function()
    return HttpService:GetAsync(playbackManagerUrl, true)
end)
if not playbackManagerOk or type(playbackManagerSource) ~= "string" or #playbackManagerSource < 100 then
    error("Could not retrieve MusicPlaybackManager. Check HTTP requests and internet access. No modules have been installed yet.")
end

for side, parent in pairs(destinations) do
    local folder = parent:FindFirstChild(folders[side])
    if folder and not folder:IsA("Folder") then
        error("A non-Folder already uses the name " .. folders[side] .. " under " .. parent.Name .. ". Rename it before retrying.")
    end
end

local existingPlaybackManager = ServerStorage:FindFirstChild("MusicPlaybackManager")
if existingPlaybackManager and not existingPlaybackManager:IsA("ModuleScript") then
    error("A non-ModuleScript already uses the name MusicPlaybackManager under ServerStorage. Rename it before retrying.")
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

local playbackManager = existingPlaybackManager or Instance.new("ModuleScript")
playbackManager.Name = "MusicPlaybackManager"
playbackManager.Source = playbackManagerSource
playbackManager.Parent = ServerStorage

print("[ClubMusic] Installed 5 audio support ModuleScripts in ServerStorage/" .. folders.server)
print("[ClubMusic] Installed MusicPlaybackManager directly under ServerStorage.")
print("[ClubMusic] Installed 1 client ModuleScript in ReplicatedStorage/" .. folders.client)
print("[ClubMusic] Install this package with the matching controller and UI_Renderer from the same branch snapshot.")
print("[ClubMusic] Modern AudioPlayer is the only controller playback source. Remove obsolete ServerMusicSound/MusicGroup instances from the place only after confirming no unrelated scripts use them.")
