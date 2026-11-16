--!strict
-- Tiki Tide / ClubMusic private security module installer.
-- Run once from Roblox Studio Command Bar with HTTP Requests enabled.
-- Installs private ModuleScripts under ServerStorage/ClubMusicSecurityCore.
-- All module source is staged before any existing ModuleScript is replaced.

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BASE_URL = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/799b9db6c89731c1055053757d7292933b46a1d5/ClubMusicSecurityCore/"
local MODULE_NAMES = {"StorageGuard", "ResourceGuard", "ConnectionJanitor", "Authorization", "RateLimit", "MessageValidation", "Idempotency", "SecurityMonitor", "SecurityPolicy", "Audit", "EventLog", "IncidentResponse", "MovementAuthority", "CharacterPhysicsGuard"}
local FOLDER_NAME = "ClubMusicSecurityCore"
local BOOTSTRAP_NAME = "TikiTideCharacterPhysicsGuardBootstrap"

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
local existingBootstrap = ServerScriptService:FindFirstChild(BOOTSTRAP_NAME)
if existingBootstrap and not existingBootstrap:IsA("Script") then
	error("ServerScriptService/" .. BOOTSTRAP_NAME .. " exists but is not a Script. Nothing was changed.")
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

local bootstrapSource = [=[
--!strict
-- Starts the server-local, detection-only CharacterPhysicsGuard.
local ServerStorage = game:GetService("ServerStorage")
local core = ServerStorage:WaitForChild("ClubMusicSecurityCore")
local guardModule = core:WaitForChild("CharacterPhysicsGuard")
local ok, exported = pcall(require, guardModule)
if not ok or typeof(exported) ~= "table" or type(exported.new) ~= "function" then
	warn("[Tiki Tide][CharacterPhysicsGuard] Module failed to load: " .. tostring(exported))
	return
end

local guard = exported.new({
	onSignal = function(signal, subject, detail)
		local api = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
		local recorder = api and api:FindFirstChild("RecordGlobalSecuritySignal")
		if recorder and recorder:IsA("BindableFunction") then
			local recordOk, result = pcall(function()
					return recorder:Invoke(signal, subject)
				end)
			if recordOk and result == true then return end
		end
		warn("[Tiki Tide][CharacterPhysicsGuard] " .. tostring(signal)
			.. " subject=" .. tostring(subject) .. " detail=" .. tostring(detail))
	end,
})
local started, startError = pcall(function() return guard:Start() end)
if not started or startError ~= true then
	warn("[Tiki Tide][CharacterPhysicsGuard] Startup failed: " .. tostring(startError))
	return
end

local statusFunction = ServerStorage:FindFirstChild("GetTikiTideCharacterPhysicsGuardStatus")
if statusFunction and not statusFunction:IsA("BindableFunction") then
	statusFunction:Destroy()
	statusFunction = nil
end
if not statusFunction then
	statusFunction = Instance.new("BindableFunction")
	statusFunction.Name = "GetTikiTideCharacterPhysicsGuardStatus"
	statusFunction.Parent = ServerStorage
end
statusFunction.OnInvoke = function()
	return guard:GetStatus()
end

script.Destroying:Connect(function()
	guard:Stop()
end)
print("[Tiki Tide][CharacterPhysicsGuard] Detection-only protection started; automatic enforcement=false.")
]=]

local bootstrap = existingBootstrap or Instance.new("Script")
bootstrap.Name = BOOTSTRAP_NAME
bootstrap.Source = bootstrapSource
bootstrap.Parent = ServerScriptService

print("[Tiki Tide Security] Installed " .. tostring(#MODULE_NAMES) .. " private modules in ServerStorage/" .. FOLDER_NAME)
print("[Tiki Tide Security] Installed " .. BOOTSTRAP_NAME .. " in ServerScriptService.")
print("[Tiki Tide Security] CharacterPhysicsGuard is detection-only and creates no persistent or MemoryStore records.")
