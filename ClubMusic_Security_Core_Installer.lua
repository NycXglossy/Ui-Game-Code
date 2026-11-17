--!strict
-- Tiki Tide / ClubMusic private security module installer.
-- Run from Studio Command Bar with HTTP Requests enabled and simulation stopped.
-- Installs a staged release, preserves unknown children, and retains one previous release.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

local RELEASE_COMMIT = "01e4038fbc9ef1fff61e06ae0fea5a3c234215ab"
local BASE_URL = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. RELEASE_COMMIT .. "/ClubMusicSecurityCore/"
local MODULE_NAMES = {"StorageGuard", "ResourceGuard", "ConnectionJanitor", "Authorization", "EntitlementAuthority", "AvatarAccessoryValidationService", "RateLimit", "MessageValidation", "Idempotency", "SecurityMonitor", "SecurityPolicy", "Audit", "EventLog", "IncidentResponse", "MovementAuthority", "CharacterPhysicsGuard", "SanityValidation", "TeleportValidationService", "StaffSpectatorService"}
local FOLDER_NAME = "ClubMusicSecurityCore"
local BOOTSTRAP_NAME = "TikiTideCharacterPhysicsGuardBootstrap"
local STAGE_NAME = FOLDER_NAME .. "_Staging"
local BACKUP_NAME = FOLDER_NAME .. "_Previous"
local BOOTSTRAP_STAGE_NAME = BOOTSTRAP_NAME .. "_Staging"
local BOOTSTRAP_BACKUP_NAME = BOOTSTRAP_NAME .. "_Previous"
local CAMERA_NAME = "TikiTideStaffSpectatorCamera"
local CAMERA_BACKUP_NAME = CAMERA_NAME .. "_Previous"
local CAMERA_STAGE_NAME = CAMERA_NAME .. "_Staging"

if RunService:IsRunning() then
 error("Installation blocked: stop Play/Run simulation before replacing server modules.")
end

local function getTyped(parent, name, className)
 local object = parent:FindFirstChild(name)
 if object and not object:IsA(className) then error(parent:GetFullName() .. "/" .. name .. " has the wrong class.") end
 return object
end

local active = getTyped(ServerStorage, FOLDER_NAME, "Folder")
local oldBackup = getTyped(ServerStorage, BACKUP_NAME, "Folder")
local oldStage = getTyped(ServerStorage, STAGE_NAME, "Folder")
local activeBootstrap = getTyped(ServerScriptService, BOOTSTRAP_NAME, "Script")
local bootstrapBackup = getTyped(ServerScriptService, BOOTSTRAP_BACKUP_NAME, "Script")
local oldBootstrapStage = getTyped(ServerScriptService, BOOTSTRAP_STAGE_NAME, "Script")
local activeCamera = getTyped(StarterPlayerScripts, CAMERA_NAME, "LocalScript")
local cameraBackup = getTyped(StarterPlayerScripts, CAMERA_BACKUP_NAME, "LocalScript")
local oldCameraStage = getTyped(StarterPlayerScripts, CAMERA_STAGE_NAME, "LocalScript")

local cameraUrl = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. RELEASE_COMMIT .. "/StaffSpectatorCamera.client.lua"
local cameraOk, cameraSource = pcall(function() return HttpService:GetAsync(cameraUrl, true) end)
if not cameraOk or type(cameraSource) ~= "string" or #cameraSource < 100 then
 error("Could not stage StaffSpectatorCamera.client.lua; active installation was not changed.")
end

local stagedSources = {}
for _, name in ipairs(MODULE_NAMES) do
 local ok, source = pcall(function() return HttpService:GetAsync(BASE_URL .. name .. ".lua", true) end)
 if not ok or type(source) ~= "string" or #source < 100 then
  error("Could not stage " .. name .. "; active installation was not changed.")
 end
 stagedSources[name] = source
end

if oldStage then oldStage:Destroy() end
if oldBootstrapStage then oldBootstrapStage:Destroy() end
if oldCameraStage then oldCameraStage:Destroy() end
local stage = Instance.new("Folder")
stage.Name = STAGE_NAME
stage.Parent = ServerStorage
local expected = {}
for _, name in ipairs(MODULE_NAMES) do expected[name] = true end
if active then
 for _, child in ipairs(active:GetChildren()) do
  if not expected[child.Name] and child.Archivable then
   local ok, clone = pcall(function() return child:Clone() end)
   if ok and clone then clone.Parent = stage end
  end
 end
end
for _, name in ipairs(MODULE_NAMES) do
 local module = Instance.new("ModuleScript")
 module.Name = name
 module.Source = stagedSources[name]
 module.Parent = stage
 if module.Source ~= stagedSources[name] then stage:Destroy(); error("Staging validation failed for " .. name) end
end
local manifest = Instance.new("StringValue")
manifest.Name = "InstallManifest"
manifest.Value = "release=" .. RELEASE_COMMIT .. ";modules=" .. table.concat(MODULE_NAMES, ",") .. ";installedAt=" .. DateTime.now():ToIsoDate()
manifest.Parent = stage

local bootstrapSource = [=[
--!strict
-- Server-local, detection-only CharacterPhysicsGuard bootstrap.
local ServerStorage = game:GetService("ServerStorage")
local core = ServerStorage:WaitForChild("ClubMusicSecurityCore")
local movementModule = core:WaitForChild("MovementAuthority")
local movementOk, movementExport = pcall(require, movementModule)
if not movementOk or typeof(movementExport) ~= "table" or type(movementExport.Invoke) ~= "function" then
 warn("[Tiki Tide][MovementAuthority] Module failed to load: " .. tostring(movementExport)); return
end
local authority = ServerStorage:FindFirstChild("TikiTideMovementAuthority")
if authority and not authority:IsA("BindableFunction") then warn("[Tiki Tide][MovementAuthority] Wrong authority class."); return end
if not authority then authority = Instance.new("BindableFunction"); authority.Name = "TikiTideMovementAuthority"; authority.Parent = ServerStorage end
authority.OnInvoke = function(...) return movementExport.Invoke(...) end
local guardModule = core:WaitForChild("CharacterPhysicsGuard")
local ok, exported = pcall(require, guardModule)
if not ok or typeof(exported) ~= "table" or type(exported.new) ~= "function" then warn("[Tiki Tide][CharacterPhysicsGuard] Module failed to load: " .. tostring(exported)); return end
local guard = exported.new({onSignal = function(signal, subject, detail)
 local api = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
 local recorder = api and api:FindFirstChild("RecordGlobalSecuritySignal")
 if recorder and recorder:IsA("BindableFunction") then
  local recordOk, result = pcall(function() return recorder:Invoke(signal, subject) end)
  if recordOk and result == true then return end
 end
 warn("[Tiki Tide][CharacterPhysicsGuard] " .. tostring(signal) .. " subject=" .. tostring(subject) .. " detail=" .. tostring(detail))
end})
local started, startError = pcall(function() return guard:Start() end)
if not started or startError ~= true then warn("[Tiki Tide][CharacterPhysicsGuard] Startup failed: " .. tostring(startError)); return end
local statusFunction = ServerStorage:FindFirstChild("GetTikiTideCharacterPhysicsGuardStatus")
if statusFunction and not statusFunction:IsA("BindableFunction") then statusFunction:Destroy(); statusFunction = nil end
if not statusFunction then statusFunction = Instance.new("BindableFunction"); statusFunction.Name = "GetTikiTideCharacterPhysicsGuardStatus"; statusFunction.Parent = ServerStorage end
statusFunction.OnInvoke = function() return guard:GetStatus() end
script.Destroying:Connect(function() guard:Stop() end)
print("[Tiki Tide][CharacterPhysicsGuard] Detection-only protection started; automatic enforcement=false.")

-- Staff spectator state is server-authoritative; this LocalScript only renders
-- the camera subject selected by server-owned player attributes.
local spectatorModule = core:WaitForChild("StaffSpectatorService")
local spectatorOk, spectatorExport = pcall(require, spectatorModule)
local authorizationModule = core:WaitForChild("Authorization")
local authOk, authExport = pcall(require, authorizationModule)
if not spectatorOk or typeof(spectatorExport) ~= "table" or type(spectatorExport.new) ~= "function"
	or not authOk or typeof(authExport) ~= "table" or type(authExport.GetShared) ~= "function" then
	warn("[Tiki Tide][StaffSpectator] Service or authorization module failed to load.")
	return
end
local auth = authExport.GetShared()
local globalApi = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
local spectator = spectatorExport.new({
	authorize = function(userId, permission) return auth:Check(userId, permission) end,
	audit = function(actorUserId, targetUserId, action)
		local currentApi = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
		local auditFunction = currentApi and currentApi:FindFirstChild("RecordGlobalAuditEvent")
		if auditFunction and auditFunction:IsA("BindableFunction") then
			pcall(function() auditFunction:Invoke("AdminAction", actorUserId, tostring(targetUserId), action) end)
		else
			warn("[Tiki Tide][StaffSpectator][AuditUnavailable] actor=" .. tostring(actorUserId) .. " target=" .. tostring(targetUserId) .. " action=" .. tostring(action))
		end
	end,
})
if not spectator:Start() then warn("[Tiki Tide][StaffSpectator] Startup failed."); return end
local control = ServerStorage:FindFirstChild("TikiTideStaffSpectatorControl")
if control and not control:IsA("BindableFunction") then warn("[Tiki Tide][StaffSpectator] Control endpoint has wrong class."); spectator:Stop(); return end
if not control then control = Instance.new("BindableFunction"); control.Name = "TikiTideStaffSpectatorControl"; control.Parent = ServerStorage end
control.OnInvoke = function(action, actorUserId, targetUserId)
	if type(actorUserId) ~= "number" or actorUserId % 1 ~= 0 then return false, "Invalid staff actor." end
	local actor = game:GetService("Players"):GetPlayerByUserId(actorUserId)
	if not actor then return false, "A live staff player is required." end
	if action == "Enter" then return spectator:Enter(actor, targetUserId) end
	if action == "SwitchTarget" then return spectator:SwitchTarget(actor, targetUserId) end
	if action == "Exit" then return spectator:Exit(actor) end
	if action == "GetState" then return spectator:GetState(actor) end
	return false, "Unsupported spectator action."
end
local statusFunction = ServerStorage:FindFirstChild("GetTikiTideStaffSpectatorStatus")
if statusFunction and not statusFunction:IsA("BindableFunction") then statusFunction:Destroy(); statusFunction = nil end
if not statusFunction then statusFunction = Instance.new("BindableFunction"); statusFunction.Name = "GetTikiTideStaffSpectatorStatus"; statusFunction.Parent = ServerStorage end
statusFunction.OnInvoke = function() return spectator:GetStatus() end
script.Destroying:Connect(function() spectator:Stop() end)
print("[Tiki Tide][StaffSpectator] Server-authorized observation service started; no gameplay powers granted.")
]=]

local stagedBootstrap = Instance.new("Script")
stagedBootstrap.Name = BOOTSTRAP_STAGE_NAME
stagedBootstrap.Source = bootstrapSource
stagedBootstrap.Disabled = true
stagedBootstrap.Parent = ServerScriptService

local stagedCamera = Instance.new("LocalScript")
stagedCamera.Name = CAMERA_STAGE_NAME
stagedCamera.Source = cameraSource
stagedCamera.Disabled = true
stagedCamera.Parent = StarterPlayerScripts

-- Keep the last known-good generation as a rollback copy. Promote only after staging succeeds.
if oldBackup then oldBackup:Destroy() end
if bootstrapBackup then bootstrapBackup:Destroy() end
if cameraBackup then cameraBackup:Destroy() end
local activeBootstrapWasDisabled = activeBootstrap and activeBootstrap.Disabled
local activeCameraWasDisabled = activeCamera and activeCamera.Disabled
local promotedFolder, promotedBootstrap, promotedCamera = false, false, false
local ok, installError = pcall(function()
 if active then active.Name = BACKUP_NAME end
 stage.Name = FOLDER_NAME
 promotedFolder = true
 if activeBootstrap then activeBootstrap.Name = BOOTSTRAP_BACKUP_NAME; activeBootstrap.Disabled = true end
 stagedBootstrap.Name = BOOTSTRAP_NAME
 promotedBootstrap = true
 stagedBootstrap.Disabled = false
 if activeCamera then activeCamera.Name = CAMERA_BACKUP_NAME; activeCamera.Disabled = true end
 stagedCamera.Name = CAMERA_NAME
 promotedCamera = true
 stagedCamera.Disabled = false
end)
if not ok then
 pcall(function()
  local failedFolder = ServerStorage:FindFirstChild(FOLDER_NAME)
  if failedFolder and failedFolder ~= active then failedFolder:Destroy() end
  if active and active.Parent then active.Name = FOLDER_NAME end
  local failedScript = ServerScriptService:FindFirstChild(BOOTSTRAP_NAME)
  if failedScript and failedScript ~= activeBootstrap then failedScript:Destroy() end
  if activeBootstrap and activeBootstrap.Parent then activeBootstrap.Name = BOOTSTRAP_NAME; activeBootstrap.Disabled = activeBootstrapWasDisabled end
  local failedCamera = StarterPlayerScripts:FindFirstChild(CAMERA_NAME)
  if failedCamera and failedCamera ~= activeCamera then failedCamera:Destroy() end
  if activeCamera and activeCamera.Parent then activeCamera.Name = CAMERA_NAME; activeCamera.Disabled = activeCameraWasDisabled end
  local failedCameraStage = StarterPlayerScripts:FindFirstChild(CAMERA_STAGE_NAME)
  if failedCameraStage then failedCameraStage:Destroy() end
  local failedStage = ServerStorage:FindFirstChild(STAGE_NAME)
  if failedStage then failedStage:Destroy() end
  local failedBootstrapStage = ServerScriptService:FindFirstChild(BOOTSTRAP_STAGE_NAME)
  if failedBootstrapStage then failedBootstrapStage:Destroy() end
 end)
 error("Installation failed; previous release restored where possible: " .. tostring(installError))
end

-- Remove the obsolete resolver instance only after the new SecurityCore release is active.
local legacyAuthorization = ServerStorage:FindFirstChild("ClubMusicAuthorizationResolver")
if legacyAuthorization then
 if legacyAuthorization:IsA("BindableFunction") then
  legacyAuthorization:Destroy()
  print("[Tiki Tide Security] Removed obsolete ClubMusicAuthorizationResolver BindableFunction.")
 else
  warn("[Tiki Tide Security] Legacy authorization object has an unexpected class; it was left untouched.")
 end
end

print("[Tiki Tide Security] Installed " .. tostring(#MODULE_NAMES) .. " modules; release=" .. RELEASE_COMMIT)
print("[Tiki Tide Security] Manifest: ServerStorage/" .. FOLDER_NAME .. "/InstallManifest")
print("[Tiki Tide Security] Previous release retained under ServerStorage/" .. BACKUP_NAME)
print("[Tiki Tide Security] Staff spectator camera installed under StarterPlayer/StarterPlayerScripts/" .. CAMERA_NAME)
print("[Tiki Tide Security] CharacterPhysicsGuard remains detection-only.")