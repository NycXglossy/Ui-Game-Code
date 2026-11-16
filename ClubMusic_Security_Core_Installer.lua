--!strict
-- Tiki Tide / ClubMusic private security module installer.
-- Run from Studio Command Bar with HTTP Requests enabled and simulation stopped.
-- Installs a staged release, preserves unknown children, and retains one previous release.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RELEASE_COMMIT = "89d9248735bf38551259a5d7442653bb4deb7db8"
local BASE_URL = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. RELEASE_COMMIT .. "/ClubMusicSecurityCore/"
local MODULE_NAMES = {"StorageGuard", "ResourceGuard", "ConnectionJanitor", "Authorization", "EntitlementAuthority", "AvatarAccessoryValidationService", "RateLimit", "MessageValidation", "Idempotency", "SecurityMonitor", "SecurityPolicy", "Audit", "EventLog", "IncidentResponse", "MovementAuthority", "CharacterPhysicsGuard", "SanityValidation", "TeleportValidationService"}
local FOLDER_NAME = "ClubMusicSecurityCore"
local BOOTSTRAP_NAME = "TikiTideCharacterPhysicsGuardBootstrap"
local STAGE_NAME = FOLDER_NAME .. "_Staging"
local BACKUP_NAME = FOLDER_NAME .. "_Previous"
local BOOTSTRAP_STAGE_NAME = BOOTSTRAP_NAME .. "_Staging"
local BOOTSTRAP_BACKUP_NAME = BOOTSTRAP_NAME .. "_Previous"

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
]=]

local stagedBootstrap = Instance.new("Script")
stagedBootstrap.Name = BOOTSTRAP_STAGE_NAME
stagedBootstrap.Source = bootstrapSource
stagedBootstrap.Disabled = true
stagedBootstrap.Parent = ServerScriptService

-- Keep the last known-good generation as a rollback copy. Promote only after staging succeeds.
if oldBackup then oldBackup:Destroy() end
if bootstrapBackup then bootstrapBackup:Destroy() end
local promotedFolder, promotedBootstrap = false, false
local ok, installError = pcall(function()
 if active then active.Name = BACKUP_NAME end
 stage.Name = FOLDER_NAME
 promotedFolder = true
 if activeBootstrap then activeBootstrap.Name = BOOTSTRAP_BACKUP_NAME end
 stagedBootstrap.Name = BOOTSTRAP_NAME
 promotedBootstrap = true
 stagedBootstrap.Disabled = false
end)
if not ok then
 pcall(function()
  local failedFolder = ServerStorage:FindFirstChild(FOLDER_NAME)
  if failedFolder and failedFolder ~= active then failedFolder:Destroy() end
  if active and active.Parent then active.Name = FOLDER_NAME end
  local failedScript = ServerScriptService:FindFirstChild(BOOTSTRAP_NAME)
  if failedScript and failedScript ~= activeBootstrap then failedScript:Destroy() end
  if activeBootstrap and activeBootstrap.Parent then activeBootstrap.Name = BOOTSTRAP_NAME end
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
print("[Tiki Tide Security] CharacterPhysicsGuard remains detection-only.")