-- ClubMusic audio ModuleScript installer
-- Run this entire script once in Roblox Studio's Command Bar (View > Command Bar).
-- Requires Game Settings > Security > Allow HTTP Requests.
-- This installs source modules only; it does NOT switch the live playback backend.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = {
    {name = "ClubMusicAudioBackend", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/8198d36/ClubMusicAudioBackend.luau"},
    {name = "ClubMusicAudioCrossfadeManager", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/652c5b3/ClubMusicAudioCrossfadeManager.luau"},
    {name = "ClubMusicAudioQualityProfiles", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/9334b4a/ClubMusicAudioQualityProfiles.luau"},
    {name = "ClubMusicDJSessionManager", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/e6286dc/ClubMusicDJSessionManager.luau"},
    {name = "ClubMusicPlayerPreferences", side = "client", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/353f021/ClubMusicPlayerPreferences.luau"},
    {name = "ClubMusicSpatialAudioGraph", side = "server", url = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/1fc0871/ClubMusicSpatialAudioGraph.luau"},
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

print("[ClubMusic] Installed 5 server ModuleScripts in ServerStorage/" .. folders.server)
print("[ClubMusic] Installed 1 client ModuleScript in ReplicatedStorage/" .. folders.client)
print("[ClubMusic] Existing playback remains unchanged. Do not delete ServerMusicSound or MusicGroup.")
