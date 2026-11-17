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

local RELEASE_COMMIT = "cad82810a7ee52438a8c2ec9e671b271ff39d4c9"
local BASE_URL = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. RELEASE_COMMIT .. "/ClubMusicSecurityCore/"
local MODULE_NAMES = {"StorageGuard", "ResourceGuard", "ConnectionJanitor", "Authorization", "EntitlementAuthority", "AvatarAccessoryValidationService", "RateLimit", "MessageValidation", "Idempotency", "SecurityMonitor", "SecurityPolicy", "Audit", "EventLog", "IncidentResponse", "MovementAuthority", "CharacterPhysicsGuard", "SanityValidation", "TeleportValidationService", "StaffSpectatorService", "SecurityReplayService", "AdaptiveSecurityLoadManager", "SecurityThreatIntelligence", "HoneypotManager", "ClientIntegrityTelemetry"}
local FOLDER_NAME = "ClubMusicSecurityCore"
local BOOTSTRAP_NAME = "TikiTideCharacterPhysicsGuardBootstrap"
local STAGE_NAME = FOLDER_NAME .. "_Staging"
local BACKUP_NAME = FOLDER_NAME .. "_Previous"
local BOOTSTRAP_STAGE_NAME = BOOTSTRAP_NAME .. "_Staging"
local BOOTSTRAP_BACKUP_NAME = BOOTSTRAP_NAME .. "_Previous"
local CAMERA_NAME = "TikiTideStaffSpectatorCamera"
local CAMERA_BACKUP_NAME = CAMERA_NAME .. "_Previous"
local CAMERA_STAGE_NAME = CAMERA_NAME .. "_Staging"
local INTEGRITY_NAME = "TikiTideClientIntegrityTelemetry"
local INTEGRITY_BACKUP_NAME = INTEGRITY_NAME .. "_Previous"
local INTEGRITY_STAGE_NAME = INTEGRITY_NAME .. "_Staging"

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
local activeIntegrity = getTyped(StarterPlayerScripts, INTEGRITY_NAME, "LocalScript")
local integrityBackup = getTyped(StarterPlayerScripts, INTEGRITY_BACKUP_NAME, "LocalScript")
local oldIntegrityStage = getTyped(StarterPlayerScripts, INTEGRITY_STAGE_NAME, "LocalScript")

local cameraUrl = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. RELEASE_COMMIT .. "/StaffSpectatorCamera.client.lua"
local cameraOk, cameraSource = pcall(function() return HttpService:GetAsync(cameraUrl, true) end)
if not cameraOk or type(cameraSource) ~= "string" or #cameraSource < 100 then
 error("Could not stage StaffSpectatorCamera.client.lua; active installation was not changed.")
end
local integrityUrl = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. RELEASE_COMMIT .. "/ClientIntegrityTelemetry.client.lua"
local integrityOk, integritySource = pcall(function() return HttpService:GetAsync(integrityUrl, true) end)
if not integrityOk or type(integritySource) ~= "string" or #integritySource < 100 then
 error("Could not stage ClientIntegrityTelemetry.client.lua; active installation was not changed.")
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
if oldIntegrityStage then oldIntegrityStage:Destroy() end
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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
 local replayEndpoint = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
 local subjectId = tonumber(subject) or 0
 if replayEndpoint and replayEndpoint:IsA("BindableFunction") then
  pcall(function()
   replayEndpoint:Invoke("Record", signal, subjectId, 0, "Warning", "CharacterPhysicsGuard", {detail = detail})
  end)
 end
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
		local replayEndpoint = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
		if replayEndpoint and replayEndpoint:IsA("BindableFunction") then
			pcall(function()
				replayEndpoint:Invoke("Record", action, actorUserId, targetUserId, "Info", "StaffSpectator", {})
			end)
		end
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

-- Bounded server-local event timeline. This endpoint is in ServerStorage and
-- is callable only by trusted server scripts; staff queries re-check authorization.
local replayModule = core:WaitForChild("SecurityReplayService")
local replayOk, replayExport = pcall(require, replayModule)
if not replayOk or typeof(replayExport) ~= "table" or type(replayExport.new) ~= "function" then
 warn("[Tiki Tide][SecurityReplay] Service failed to load: " .. tostring(replayExport))
 return
end
local replay = replayExport.new({
 authorize = function(userId, permission) return auth:Check(userId, permission) end,
})
if not replay:Start() then warn("[Tiki Tide][SecurityReplay] Startup failed."); return end
local replayEndpoint = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
if replayEndpoint and not replayEndpoint:IsA("BindableFunction") then
 warn("[Tiki Tide][SecurityReplay] Endpoint has wrong class."); replay:Stop(); return
end
if not replayEndpoint then
 replayEndpoint = Instance.new("BindableFunction")
 replayEndpoint.Name = "TikiTideSecurityReplay"
 replayEndpoint.Parent = ServerStorage
end

-- Adaptive budgets apply only to optional workload. Core security paths and replay
-- event recording remain available in every mode.
local loadManager: any = nil
local loadModule = core:FindFirstChild("AdaptiveSecurityLoadManager")
if loadModule and loadModule:IsA("ModuleScript") then
 local loadOk, loadExport = pcall(require, loadModule)
 if loadOk and typeof(loadExport) == "table" and type(loadExport.new) == "function" then
  loadManager = loadExport.new({
   onModeChanged = function(previousMode, nextMode, averageDelta, maximumDelta, reason)
    pcall(function()
     replayEndpoint:Invoke("Record", "security_load_mode_changed", 0, 0,
      if nextMode == "Critical" then "Warning" else "Info",
      "AdaptiveSecurityLoadManager",
      {previousMode = previousMode, mode = nextMode, averageHeartbeatDelta = averageDelta,
       maximumHeartbeatDelta = maximumDelta, reason = reason})
    end)
   end,
  })
  local loadStarted, loadResult = pcall(function() return loadManager:Start() end)
  if not loadStarted or loadResult ~= true then
   warn("[Tiki Tide][AdaptiveLoad] Startup failed: " .. tostring(loadResult))
   loadManager = nil
  end
 else
  warn("[Tiki Tide][AdaptiveLoad] Module failed to load: " .. tostring(loadExport))
 end
else
 warn("[Tiki Tide][AdaptiveLoad] Module is missing; optional workload remains ungated.")
end

local loadControl = ServerStorage:FindFirstChild("TikiTideSecurityLoadManager")
if loadManager then
 if loadControl and not loadControl:IsA("BindableFunction") then
  warn("[Tiki Tide][AdaptiveLoad] Control endpoint has wrong class; endpoint not exposed.")
 else
  if not loadControl then
   loadControl = Instance.new("BindableFunction")
   loadControl.Name = "TikiTideSecurityLoadManager"
   loadControl.Parent = ServerStorage
  end
  loadControl.OnInvoke = function(action, taskName, amount)
   if action == "Status" then return loadManager:GetStatus() end
   if action == "GetBudget" then return loadManager:GetBudget(taskName) end
   if action == "TryConsume" then return loadManager:TryConsume(taskName, amount) end
   return false, "Unsupported adaptive-load operation."
  end
  local loadStatus = ServerStorage:FindFirstChild("GetTikiTideSecurityLoadStatus")
  if loadStatus and not loadStatus:IsA("BindableFunction") then loadStatus:Destroy(); loadStatus = nil end
  if not loadStatus then
   loadStatus = Instance.new("BindableFunction")
   loadStatus.Name = "GetTikiTideSecurityLoadStatus"
   loadStatus.Parent = ServerStorage
  end
  loadStatus.OnInvoke = function() return loadManager:GetStatus() end
 end
end

-- Correlate multiple independent, sanitized signals into bounded staff-review items.
-- This service is server-local and never enforces against a player.
local threatService: any = nil
local threatModule = core:FindFirstChild("SecurityThreatIntelligence")
if threatModule and threatModule:IsA("ModuleScript") then
 local threatOk, threatExport = pcall(require, threatModule)
 if threatOk and typeof(threatExport) == "table" and type(threatExport.new) == "function" then
  local createOk, instance = pcall(threatExport.new, {
   authorize = function(userId, permission) return auth:Check(userId, permission) end,
  })
  if createOk and typeof(instance) == "table" and type(instance.Record) == "function"
   and type(instance.Query) == "function" and type(instance.GetStatus) == "function" then
   threatService = instance
   if not threatService:Start() then threatService = nil end
  else
   warn("[Tiki Tide][ThreatIntelligence] Service interface validation failed: " .. tostring(instance))
  end
 else
  warn("[Tiki Tide][ThreatIntelligence] Module failed to load: " .. tostring(threatExport))
 end
else
 warn("[Tiki Tide][ThreatIntelligence] Optional module is missing.")
end

local threatEndpoint = ServerStorage:FindFirstChild("TikiTideThreatIntelligence")
if threatEndpoint and not threatEndpoint:IsA("BindableFunction") then
 warn("[Tiki Tide][ThreatIntelligence] Endpoint has wrong class; service remains unavailable.")
 if threatService then threatService:Stop(); threatService = nil end
else
 if not threatEndpoint then
  threatEndpoint = Instance.new("BindableFunction")
  threatEndpoint.Name = "TikiTideThreatIntelligence"
  threatEndpoint.Parent = ServerStorage
 end
 threatEndpoint.OnInvoke = function(action, ...)
  if not threatService then return false, {}, "Threat intelligence is unavailable." end
  if action == "Record" then return threatService:Record(...) end
  if action == "Query" then return threatService:Query(...) end
  if action == "Status" then return threatService:GetStatus() end
  return false, "Unsupported threat-intelligence action."
 end
 local threatStatus = ServerStorage:FindFirstChild("GetTikiTideThreatIntelligenceStatus")
 if threatStatus and not threatStatus:IsA("BindableFunction") then threatStatus:Destroy(); threatStatus = nil end
 if not threatStatus then
  threatStatus = Instance.new("BindableFunction")
  threatStatus.Name = "GetTikiTideThreatIntelligenceStatus"
  threatStatus.Parent = ServerStorage
 end
 threatStatus.OnInvoke = function()
  return if threatService then threatService:GetStatus() else {state = "Unavailable", scope = "ServerLocal", automaticEnforcement = false}
 end
end

-- Decoy remotes are isolated under a dedicated ReplicatedStorage folder.
-- Hits feed existing local threat/replay services; no hit triggers enforcement.
local honeypotService: any = nil
local honeypotModule = core:FindFirstChild("HoneypotManager")
if honeypotModule and honeypotModule:IsA("ModuleScript") then
 local honeypotOk, honeypotExport = pcall(require, honeypotModule)
 if honeypotOk and typeof(honeypotExport) == "table" and type(honeypotExport.new) == "function" then
  local createOk, instance = pcall(honeypotExport.new, {
   recordThreat = function(signal, userId, source, severity)
    if threatEndpoint and threatEndpoint:IsA("BindableFunction") then
     return threatEndpoint:Invoke("Record", signal, userId, source, severity)
    end
    return false
   end,
   recordReplay = function(signal, userId, kind)
    if replayEndpoint and replayEndpoint:IsA("BindableFunction") then
     return replayEndpoint:Invoke("Record", signal, userId, 0, "Warning", "HoneypotManager", {decoyType = kind})
    end
    return false
   end,
  })
  if createOk and typeof(instance) == "table" and type(instance.Start) == "function"
   and type(instance.GetStatus) == "function" and type(instance.Stop) == "function" then
   honeypotService = instance
   local startedOk, startedResult = pcall(function() return honeypotService:Start() end)
   if not startedOk or startedResult ~= true then
    warn("[Tiki Tide][Honeypot] Startup failed: " .. tostring(startedResult))
    honeypotService = nil
   end
  else
   warn("[Tiki Tide][Honeypot] Module interface validation failed: " .. tostring(instance))
  end
 else
  warn("[Tiki Tide][Honeypot] Module failed to load: " .. tostring(honeypotExport))
 end
else
 warn("[Tiki Tide][Honeypot] Optional module is missing.")
end

local honeypotStatus = ServerStorage:FindFirstChild("GetTikiTideHoneypotStatus")
if honeypotStatus and not honeypotStatus:IsA("BindableFunction") then
 honeypotStatus:Destroy()
 honeypotStatus = nil
end
if honeypotService then
 if not honeypotStatus then
  honeypotStatus = Instance.new("BindableFunction")
  honeypotStatus.Name = "GetTikiTideHoneypotStatus"
  honeypotStatus.Parent = ServerStorage
 end
 honeypotStatus.OnInvoke = function() return honeypotService:GetStatus() end
end

replayEndpoint.OnInvoke = function(action, ...)
 if action == "Record" then return replay:Record(...) end
 if action == "Query" then
  if loadManager and not loadManager:TryConsume("ReplayQueries") then
   return false, {}, "Replay review is temporarily rate-limited while the server is under load."
  end
  return replay:Query(...)
 end
 if action == "Status" then return replay:GetStatus() end
 return false, "Unsupported replay action."
end
local replayStatus = ServerStorage:FindFirstChild("GetTikiTideSecurityReplayStatus")
if replayStatus and not replayStatus:IsA("BindableFunction") then replayStatus:Destroy(); replayStatus = nil end
if not replayStatus then
 replayStatus = Instance.new("BindableFunction")
 replayStatus.Name = "GetTikiTideSecurityReplayStatus"
 replayStatus.Parent = ServerStorage
end
replayStatus.OnInvoke = function() return replay:GetStatus() end

-- Client observations are fixed-code, untrusted telemetry. They never affect auth or enforcement.
local clientIntegrityService: any = nil
local clientIntegrityModule = core:FindFirstChild("ClientIntegrityTelemetry")
if clientIntegrityModule and clientIntegrityModule:IsA("ModuleScript") then
 local telemetryOk, telemetryExport = pcall(require, clientIntegrityModule)
 if telemetryOk and typeof(telemetryExport) == "table" and type(telemetryExport.new) == "function" then
  local createOk, instance = pcall(telemetryExport.new, {
   recordReplay = function(signal, userId)
    if replayEndpoint and replayEndpoint:IsA("BindableFunction") then
     return replayEndpoint:Invoke("Record", signal, userId, 0, "Info", "ClientIntegrityTelemetry", {})
    end
    return false
   end,
  })
  if createOk and typeof(instance) == "table" and type(instance.Start) == "function"
   and type(instance.GetStatus) == "function" and type(instance.Stop) == "function" then
   clientIntegrityService = instance
   local startedOk, startedResult = pcall(function() return clientIntegrityService:Start() end)
   if not startedOk or startedResult ~= true then
    warn("[Tiki Tide][ClientIntegrity] Startup failed: " .. tostring(startedResult))
    clientIntegrityService = nil
   end
  else
   warn("[Tiki Tide][ClientIntegrity] Module interface validation failed: " .. tostring(instance))
  end
 else
  warn("[Tiki Tide][ClientIntegrity] Module failed to load: " .. tostring(telemetryExport))
 end
else
 warn("[Tiki Tide][ClientIntegrity] Optional module is missing.")
end
local clientIntegrityStatus = ServerStorage:FindFirstChild("GetTikiTideClientIntegrityStatus")
if clientIntegrityStatus and not clientIntegrityStatus:IsA("BindableFunction") then
 clientIntegrityStatus:Destroy()
 clientIntegrityStatus = nil
end
if clientIntegrityService then
 if not clientIntegrityStatus then
  clientIntegrityStatus = Instance.new("BindableFunction")
  clientIntegrityStatus.Name = "GetTikiTideClientIntegrityStatus"
  clientIntegrityStatus.Parent = ServerStorage
 end
 clientIntegrityStatus.OnInvoke = function() return clientIntegrityService:GetStatus() end
end
script.Destroying:Connect(function()
 replay:Stop()
 if threatService then threatService:Stop() end
 if honeypotService then honeypotService:Stop() end
 if clientIntegrityService then clientIntegrityService:Stop() end
 if loadManager then loadManager:Stop() end
end)
print("[Tiki Tide][SecurityReplay] Bounded server-local event history ready; persistent writes=0; frame capture=false.")
if loadManager then print("[Tiki Tide][AdaptiveLoad] Adaptive optional-work budgets started; essential security paths remain unrestricted.") end
if threatService then print("[Tiki Tide][ThreatIntelligence] Bounded local correlation ready; automatic enforcement=false.") end
if honeypotService then print("[Tiki Tide][Honeypot] Isolated decoy remotes active; detection-only; automatic enforcement=false.") end
if clientIntegrityService then print("[Tiki Tide][ClientIntegrity] Fixed-code client observations enabled; untrusted; no enforcement.") end
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
local stagedIntegrity = Instance.new("LocalScript")
stagedIntegrity.Name = INTEGRITY_STAGE_NAME
stagedIntegrity.Source = integritySource
stagedIntegrity.Disabled = true
stagedIntegrity.Parent = StarterPlayerScripts

-- Keep the last known-good generation as a rollback copy. Promote only after staging succeeds.
if oldBackup then oldBackup:Destroy() end
if bootstrapBackup then bootstrapBackup:Destroy() end
if cameraBackup then cameraBackup:Destroy() end
if integrityBackup then integrityBackup:Destroy() end
local activeBootstrapWasDisabled = activeBootstrap and activeBootstrap.Disabled
local activeCameraWasDisabled = activeCamera and activeCamera.Disabled
local activeIntegrityWasDisabled = activeIntegrity and activeIntegrity.Disabled
local promotedFolder, promotedBootstrap, promotedCamera, promotedIntegrity = false, false, false, false
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
 if activeIntegrity then activeIntegrity.Name = INTEGRITY_BACKUP_NAME; activeIntegrity.Disabled = true end
 stagedIntegrity.Name = INTEGRITY_NAME
 promotedIntegrity = true
 stagedIntegrity.Disabled = false
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
  local failedIntegrity = StarterPlayerScripts:FindFirstChild(INTEGRITY_NAME)
  if failedIntegrity and failedIntegrity ~= activeIntegrity then failedIntegrity:Destroy() end
  if activeIntegrity and activeIntegrity.Parent then activeIntegrity.Name = INTEGRITY_NAME; activeIntegrity.Disabled = activeIntegrityWasDisabled end
  local failedIntegrityStage = StarterPlayerScripts:FindFirstChild(INTEGRITY_STAGE_NAME)
  if failedIntegrityStage then failedIntegrityStage:Destroy() end
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
print("[Tiki Tide Security] Untrusted client integrity observer installed under StarterPlayer/StarterPlayerScripts/" .. INTEGRITY_NAME)
print("[Tiki Tide Security] CharacterPhysicsGuard remains detection-only.")