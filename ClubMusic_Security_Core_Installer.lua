--!strict
-- Tiki Tide / ClubMusic private security module installer.
-- Run once from Roblox Studio Command Bar with HTTP Requests enabled.
-- Installs private ModuleScripts under ServerStorage/ClubMusicSecurityCore.
-- All module source is staged before any existing ModuleScript is replaced.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local BASE_URL = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/cec6e139c9bba7c06ab2b0f7fc3b63e6bed26293/ClubMusicSecurityCore/"
local MODULE_NAMES = {"StorageGuard", "ResourceGuard", "ConnectionJanitor", "Authorization", "RateLimit", "MessageValidation", "Idempotency", "SecurityMonitor", "SecurityPolicy", "Audit", "EventLog", "IncidentResponse", "MovementAuthority"}
local FOLDER_NAME = "ClubMusicSecurityCore"

local staged = {}
for _, name in ipairs(MODULE_NAMES) do
	local ok, source = pcall(function()
		return HttpService:GetAsync(BASE_URL .. name .. ".lua", true)
	end)
	if not ok or type(source) ~= "string" or #source < 100 then
		error("Could not stage private security module " .. name .. ". No modules were changed.")
	end
	staged[name] = source
end

local existingFolder = ServerStorage:FindFirstChild(FOLDER_NAME)
if existingFolder and not existingFolder:IsA("Folder") then
	error("ServerStorage/" .. FOLDER_NAME .. " exists but is not a Folder. Nothing was changed.")
end
if existingFolder then
	for _, name in ipairs(MODULE_NAMES) do
		local existing = existingFolder:FindFirstChild(name)
		if existing and not existing:IsA("ModuleScript") then
			error("A non-ModuleScript named " .. name .. " already exists. Nothing was changed.")
		end
	end
end

local folder = existingFolder or Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = ServerStorage

for _, name in ipairs(MODULE_NAMES) do
	local module = folder:FindFirstChild(name) or Instance.new("ModuleScript")
	module.Name = name
	module.Source = staged[name]
	module.Parent = folder
end

print("[Tiki Tide Security] Installed " .. tostring(#MODULE_NAMES) .. " private modules in ServerStorage/" .. FOLDER_NAME)
print("[Tiki Tide Security] The global service will prefer these split modules and retain the legacy bundle as fallback.")
