-- ClubMusic audio ModuleScript installer
-- Five server audio modules and one client preferences module are pinned to one canonical package snapshot.
-- Playback and request queues remain controller-owned; optional playback-only global sync is installed separately.
-- Run this entire script once in Roblox Studio's Command Bar (View > Command Bar).
-- Requires Game Settings > Security > Allow HTTP Requests.
-- This installs source modules only; it does NOT update the controller or renderer scripts.
-- The current controller performs playback quality inspection locally and no longer requires MusicPlaybackManager.
-- Existing MusicPlaybackManager instances are left untouched for live-place rollback/consumer reconciliation.
-- Install all matching branch revisions together in a stopped test place before starting playback.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = {
    {name = "ClubMusicAudioBackend", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/f47410ac9a9674d3df0b24eb1714b31d1a4ef816/ClubMusicAudioBackend.luau"},
    {name = "ClubMusicAudioCrossfadeManager", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/f47410ac9a9674d3df0b24eb1714b31d1a4ef816/ClubMusicAudioCrossfadeManager.luau"},
    {name = "ClubMusicAudioQualityProfiles", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/f47410ac9a9674d3df0b24eb1714b31d1a4ef816/ClubMusicAudioQualityProfiles.luau"},
    {name = "ClubMusicDJSessionManager", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/f47410ac9a9674d3df0b24eb1714b31d1a4ef816/ClubMusicDJSessionManager.luau"},
    {name = "ClubMusicPlayerPreferences", side = "client", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/f47410ac9a9674d3df0b24eb1714b31d1a4ef816/ClubMusicPlayerPreferences.luau"},
    {name = "ClubMusicSpatialAudioGraph", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/f47410ac9a9674d3df0b24eb1714b31d1a4ef816/ClubMusicSpatialAudioGraph.luau"},
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

for side, parent in pairs(destinations) do
    local folder = parent:FindFirstChild(folders[side])
    if folder and not folder:IsA("Folder") then
        error("A non-Folder already uses the name " .. folders[side] .. " under " .. parent.Name .. ". Rename it before retrying.")
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

print("[ClubMusic] Installed 5 audio support ModuleScripts in ServerStorage/" .. folders.server)
print("[ClubMusic] Installed 1 client ModuleScript in ReplicatedStorage/" .. folders.client)
print("[ClubMusic] Install this package with the matching controller and UI_Renderer from the same branch snapshot.")
print("[ClubMusic] Modern AudioPlayer is the only controller playback source. Remove obsolete ServerMusicSound/MusicGroup instances from the place only after confirming no unrelated scripts use them.")
