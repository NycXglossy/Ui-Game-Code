--!strict
-- Installs the client-local diagnostics ModuleScript and its StarterPlayerScripts bootstrap.
-- Run from Studio Command Bar with HTTP Requests enabled and simulation stopped.
-- This installer changes only these two client diagnostics instances.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

local RELEASE_COMMIT = "a486f1f046fc187da8c59d46d91d64e96f3e710c"
local BASE_URL = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. RELEASE_COMMIT .. "/"
local MODULE_NAME = "ClubMusic_Client_Diagnostics_Service"
local BOOTSTRAP_NAME = "ClubMusic_Client_Diagnostics_Bootstrap"
local MODULE_STAGE_NAME = MODULE_NAME .. "_Staging"
local BOOTSTRAP_STAGE_NAME = BOOTSTRAP_NAME .. "_Staging"
local MODULE_BACKUP_NAME = MODULE_NAME .. "_Previous"
local BOOTSTRAP_BACKUP_NAME = BOOTSTRAP_NAME .. "_Previous"

if RunService:IsRunning() then
	error("Installation blocked: stop Play/Run simulation before installing client diagnostics.")
end

local function getTyped(parent: Instance, name: string, className: string): Instance?
	local object = parent:FindFirstChild(name)
	if object and not object:IsA(className) then
		error(parent:GetFullName() .. "/" .. name .. " has the wrong class; no changes were made.")
	end
	return object
end

local moduleUrl = BASE_URL .. MODULE_NAME .. ".lua"
local bootstrapUrl = BASE_URL .. BOOTSTRAP_NAME .. ".client.lua"
local moduleOk, moduleSource = pcall(function()
	return HttpService:GetAsync(moduleUrl, true)
end)
if not moduleOk or type(moduleSource) ~= "string" or #moduleSource < 100 then
	error("Could not retrieve the diagnostics ModuleScript; no instances were changed.")
end
local bootstrapOk, bootstrapSource = pcall(function()
	return HttpService:GetAsync(bootstrapUrl, true)
end)
if not bootstrapOk or type(bootstrapSource) ~= "string" or #bootstrapSource < 100 then
	error("Could not retrieve the diagnostics bootstrap; no instances were changed.")
end

local activeModule = getTyped(ReplicatedStorage, MODULE_NAME, "ModuleScript") :: ModuleScript?
local activeBootstrap = getTyped(StarterPlayerScripts, BOOTSTRAP_NAME, "LocalScript") :: LocalScript?
local oldModuleBackup = getTyped(ReplicatedStorage, MODULE_BACKUP_NAME, "ModuleScript")
local oldBootstrapBackup = getTyped(StarterPlayerScripts, BOOTSTRAP_BACKUP_NAME, "LocalScript")
local oldModuleStage = getTyped(ReplicatedStorage, MODULE_STAGE_NAME, "ModuleScript")
local oldBootstrapStage = getTyped(StarterPlayerScripts, BOOTSTRAP_STAGE_NAME, "LocalScript")

if oldModuleStage then oldModuleStage:Destroy() end
if oldBootstrapStage then oldBootstrapStage:Destroy() end

local stagedModule = Instance.new("ModuleScript")
stagedModule.Name = MODULE_STAGE_NAME
stagedModule.Source = moduleSource
stagedModule.Parent = ReplicatedStorage

local stagedBootstrap = Instance.new("LocalScript")
stagedBootstrap.Name = BOOTSTRAP_STAGE_NAME
stagedBootstrap.Source = bootstrapSource
stagedBootstrap.Disabled = true
stagedBootstrap.Parent = StarterPlayerScripts

if oldModuleBackup then oldModuleBackup:Destroy() end
if oldBootstrapBackup then oldBootstrapBackup:Destroy() end

local activeBootstrapWasDisabled = activeBootstrap and activeBootstrap.Disabled
local ok, installError = pcall(function()
	if activeModule then activeModule.Name = MODULE_BACKUP_NAME end
	stagedModule.Name = MODULE_NAME

	if activeBootstrap then
		activeBootstrap.Name = BOOTSTRAP_BACKUP_NAME
		activeBootstrap.Disabled = true
	end
	stagedBootstrap.Name = BOOTSTRAP_NAME
	stagedBootstrap.Disabled = false
end)

if not ok then
	pcall(function()
		local failedModule = ReplicatedStorage:FindFirstChild(MODULE_NAME)
		if failedModule and failedModule ~= activeModule then failedModule:Destroy() end
		local failedBootstrap = StarterPlayerScripts:FindFirstChild(BOOTSTRAP_NAME)
		if failedBootstrap and failedBootstrap ~= activeBootstrap then failedBootstrap:Destroy() end
		if activeModule and activeModule.Parent then activeModule.Name = MODULE_NAME end
		if activeBootstrap and activeBootstrap.Parent then
			activeBootstrap.Name = BOOTSTRAP_NAME
			activeBootstrap.Disabled = activeBootstrapWasDisabled == true
		end
		local moduleStage = ReplicatedStorage:FindFirstChild(MODULE_STAGE_NAME)
		if moduleStage then moduleStage:Destroy() end
		local bootstrapStage = StarterPlayerScripts:FindFirstChild(BOOTSTRAP_STAGE_NAME)
		if bootstrapStage then bootstrapStage:Destroy() end
	end)
	error("Diagnostics installation failed; previous instances restored where possible: " .. tostring(installError))
end

print("[ClubMusic][ClientDiagnostics] Installed ReplicatedStorage/" .. MODULE_NAME)
print("[ClubMusic][ClientDiagnostics] Installed StarterPlayer/StarterPlayerScripts/" .. BOOTSTRAP_NAME)
print("[ClubMusic][ClientDiagnostics] FPS/frame-time, memory and optional audio sampling remain client-local; Workspace effects audit remains opt-in.")
print("[ClubMusic][ClientDiagnostics] Previous instances retained with _Previous suffix for rollback.")
