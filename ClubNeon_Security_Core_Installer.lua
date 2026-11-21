--!strict
-- Club Neon / ClubMusic private security module installer.
-- Run from Studio Command Bar with HTTP Requests enabled and simulation stopped.
-- Installs a staged release, preserves unknown children, and retains one previous release.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

local RELEASE_COMMIT = "356b48891906d3e4e1b0a95f12ccf48bb63d28b4"
local BASE_URL = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. RELEASE_COMMIT .. "/ClubNeonSecurityCore/"
-- Threat Intelligence alone is sourced from the hardened Phase 15 snapshot.
-- All other SecurityCore modules, including receipt modules, keep the current release pin.
local THREAT_INTELLIGENCE_COMMIT = "356b48891906d3e4e1b0a95f12ccf48bb63d28b4"
local THREAT_INTELLIGENCE_BASE_URL = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. THREAT_INTELLIGENCE_COMMIT .. "/ClubNeonSecurityCore/"
-- Phase 32 is pinned independently so the previously certified SecurityCore
-- module snapshot is not silently changed by later commits.
local PHASE32_COMMIT = "356b48891906d3e4e1b0a95f12ccf48bb63d28b4"
local PHASE32_BASE_URL = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. PHASE32_COMMIT .. "/ClubNeonSecurityCore/"
local MODULE_NAMES = {"StorageGuard", "ResourceGuard", "ConnectionJanitor", "Authorization", "EntitlementAuthority", "AvatarAccessoryValidationService", "AnimationIntegrityService", "RateLimit", "MessageValidation", "Idempotency", "SecurityMonitor", "SecurityPolicy", "Audit", "EventLog", "IncidentResponse", "MovementAuthority", "CharacterPhysicsGuard", "SanityValidation", "TeleportValidationService", "StaffSpectatorService", "SecurityReplayService", "AdaptiveSecurityLoadManager", "SecurityThreatIntelligence", "HoneypotManager", "ClientIntegrityTelemetry", "ReceiptAuthority", "ReceiptHash", "ReceiptTransactionService"}
local PHASE32_MODULE_NAMES = {"ModerationPunishmentService", "AccountRiskSignalService", "ChatAbuseDetectionService", "Phase32ServiceBundle"}
local FOLDER_NAME = "ClubNeonSecurityCore"
local BOOTSTRAP_NAME = "ClubNeonCharacterPhysicsGuardBootstrap"
local STAGE_NAME = FOLDER_NAME .. "_Staging"
local BACKUP_NAME = FOLDER_NAME .. "_Previous"
local BOOTSTRAP_STAGE_NAME = BOOTSTRAP_NAME .. "_Staging"
local BOOTSTRAP_BACKUP_NAME = BOOTSTRAP_NAME .. "_Previous"
local CAMERA_NAME = "ClubNeonStaffSpectatorCamera"
local CAMERA_BACKUP_NAME = CAMERA_NAME .. "_Previous"
local CAMERA_STAGE_NAME = CAMERA_NAME .. "_Staging"
local INTEGRITY_NAME = "ClubNeonClientIntegrityTelemetry"
local INTEGRITY_BACKUP_NAME = INTEGRITY_NAME .. "_Previous"
local INTEGRITY_STAGE_NAME = INTEGRITY_NAME .. "_Staging"
local VISUAL_NAME = "ClubNeonAdaptiveVisualQuality"
local VISUAL_BACKUP_NAME = VISUAL_NAME .. "_Previous"
local VISUAL_STAGE_NAME = VISUAL_NAME .. "_Staging"

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
local activeVisual = getTyped(StarterPlayerScripts, VISUAL_NAME, "LocalScript")
local visualBackup = getTyped(StarterPlayerScripts, VISUAL_BACKUP_NAME, "LocalScript")
local oldVisualStage = getTyped(StarterPlayerScripts, VISUAL_STAGE_NAME, "LocalScript")

local cameraUrl = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. RELEASE_COMMIT .. "/ClubNeon_StaffSpectatorCamera.client.lua"
local cameraOk, cameraSource = pcall(function() return HttpService:GetAsync(cameraUrl, true) end)
if not cameraOk or type(cameraSource) ~= "string" or #cameraSource < 100 then
 error("Could not stage StaffSpectatorCamera.client.lua; active installation was not changed.")
end
local integrityUrl = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. RELEASE_COMMIT .. "/ClubNeonClientIntegrityTelemetry.client.lua"
local integrityOk, integritySource = pcall(function() return HttpService:GetAsync(integrityUrl, true) end)
if not integrityOk or type(integritySource) ~= "string" or #integritySource < 100 then
 error("Could not stage ClientIntegrityTelemetry.client.lua; active installation was not changed.")
end
local visualUrl = "https://raw.githubusercontent.com/NycXglossy/Ui-Game-Code/" .. RELEASE_COMMIT .. "/ClubNeonAdaptiveVisualQuality.client.lua"
local visualOk, visualSource = pcall(function() return HttpService:GetAsync(visualUrl, true) end)
if not visualOk or type(visualSource) ~= "string" or #visualSource < 100 then
 error("Could not stage ClubNeonAdaptiveVisualQuality.client.lua; active installation was not changed.")
end

local stagedSources = {}
for _, name in ipairs(MODULE_NAMES) do
 local moduleBaseUrl = if name == "SecurityThreatIntelligence" then THREAT_INTELLIGENCE_BASE_URL else BASE_URL
 local ok, source = pcall(function() return HttpService:GetAsync(moduleBaseUrl .. name .. ".lua", true) end)
 if not ok or type(source) ~= "string" or #source < 100 then
  error("Could not stage " .. name .. "; active installation was not changed.")
 end
 stagedSources[name] = source
end
for _, name in ipairs(PHASE32_MODULE_NAMES) do
 local ok, source = pcall(function() return HttpService:GetAsync(PHASE32_BASE_URL .. name .. ".lua", true) end)
 if not ok or type(source) ~= "string" or #source < 100 then
  error("Could not stage Phase 32 module " .. name .. "; active installation was not changed.")
 end
 stagedSources[name] = source
end
local ALL_MODULE_NAMES = table.clone(MODULE_NAMES)
for _, name in ipairs(PHASE32_MODULE_NAMES) do table.insert(ALL_MODULE_NAMES, name) end

if oldStage then oldStage:Destroy() end
if oldBootstrapStage then oldBootstrapStage:Destroy() end
if oldCameraStage then oldCameraStage:Destroy() end
if oldIntegrityStage then oldIntegrityStage:Destroy() end
if oldVisualStage then oldVisualStage:Destroy() end
local stage = Instance.new("Folder")
stage.Name = STAGE_NAME
stage.Parent = ServerStorage
local expected = {}
for _, name in ipairs(ALL_MODULE_NAMES) do expected[name] = true end
if active then
 for _, child in ipairs(active:GetChildren()) do
  if not expected[child.Name] and child.Archivable then
   local ok, clone = pcall(function() return child:Clone() end)
   if ok and clone then clone.Parent = stage end
  end
 end
end
for _, name in ipairs(ALL_MODULE_NAMES) do
 local module = Instance.new("ModuleScript")
 module.Name = name
 module.Source = stagedSources[name]
 module.Parent = stage
 if module.Source ~= stagedSources[name] then stage:Destroy(); error("Staging validation failed for " .. name) end
end
local manifest = Instance.new("StringValue")
manifest.Name = "InstallManifest"
manifest.Value = "securityCoreRelease=" .. RELEASE_COMMIT .. ";phase32Release=" .. PHASE32_COMMIT .. ";threatIntelligenceRelease=" .. THREAT_INTELLIGENCE_COMMIT .. ";modules=" .. table.concat(ALL_MODULE_NAMES, ",") .. ";visualClient=" .. VISUAL_NAME .. ";installedAt=" .. DateTime.now():ToIsoDate()
manifest.Parent = stage

local bootstrapSource = [=[
--!strict
-- Server-local, detection-only CharacterPhysicsGuard bootstrap.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local core = ServerStorage:WaitForChild("ClubNeonSecurityCore")
local movementModule = core:WaitForChild("MovementAuthority")
local movementOk, movementExport = pcall(require, movementModule)
if not movementOk or typeof(movementExport) ~= "table" or type(movementExport.Invoke) ~= "function" then
 warn("[Club Neon][MovementAuthority] Module failed to load: " .. tostring(movementExport)); return
end
local authority = ServerStorage:FindFirstChild("ClubNeonMovementAuthority")
if authority and not authority:IsA("BindableFunction") then warn("[Club Neon][MovementAuthority] Wrong authority class."); return end
if not authority then authority = Instance.new("BindableFunction"); authority.Name = "ClubNeonMovementAuthority"; authority.Parent = ServerStorage end
authority.OnInvoke = function(...) return movementExport.Invoke(...) end
local loadControl = ServerStorage:FindFirstChild("ClubNeonSecurityLoadManager")
local function getMovementSampleInterval()
 local mode = Workspace:GetAttribute("ClubNeonAdaptiveLoadMode")
 if mode == "Critical" then return 3.0 end
 if mode == "Reduced" then return 1.5 end
 return 0.5
end
local function allowMovementSample()
 if not loadControl or not loadControl:IsA("BindableFunction") or type(loadControl.OnInvoke) ~= "function" then return true end
 local playerCount = math.max(1, #Players:GetPlayers())
 local ok, allowed = pcall(function()
  return loadControl:Invoke("TryConsume", "DiagnosticsSampling", 1 / playerCount)
 end)
 -- Sampling is optional; if the governor is unavailable, retain the normal passive sample.
 return not ok or allowed == true
end
local guardModule = core:WaitForChild("CharacterPhysicsGuard")
local ok, exported = pcall(require, guardModule)
if not ok or typeof(exported) ~= "table" or type(exported.new) ~= "function" then warn("[Club Neon][CharacterPhysicsGuard] Module failed to load: " .. tostring(exported)); return end
local guard = exported.new({getMovementSampleInterval = getMovementSampleInterval, allowMovementSample = allowMovementSample, onSignal = function(signal, subject, detail)
 local replayEndpoint = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
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
 warn("[Club Neon][CharacterPhysicsGuard] " .. tostring(signal) .. " subject=" .. tostring(subject) .. " detail=" .. tostring(detail))
end})
local started, startError = pcall(function() return guard:Start() end)
if not started or startError ~= true then warn("[Club Neon][CharacterPhysicsGuard] Startup failed: " .. tostring(startError)); return end
local statusFunction = ServerStorage:FindFirstChild("GetClubNeonCharacterPhysicsGuardStatus")
if statusFunction and not statusFunction:IsA("BindableFunction") then statusFunction:Destroy(); statusFunction = nil end
if not statusFunction then statusFunction = Instance.new("BindableFunction"); statusFunction.Name = "GetClubNeonCharacterPhysicsGuardStatus"; statusFunction.Parent = ServerStorage end
statusFunction.OnInvoke = function() return guard:GetStatus() end
script.Destroying:Connect(function() guard:Stop() end)
print("[Club Neon][CharacterPhysicsGuard] Detection-only protection started; automatic enforcement=false.")

-- Staff spectator state is server-authoritative; this LocalScript only renders
-- the camera subject selected by server-owned player attributes.
local spectatorModule = core:WaitForChild("StaffSpectatorService")
local spectatorOk, spectatorExport = pcall(require, spectatorModule)
local authorizationModule = core:WaitForChild("Authorization")
local authOk, authExport = pcall(require, authorizationModule)
if not spectatorOk or typeof(spectatorExport) ~= "table" or type(spectatorExport.new) ~= "function"
	or not authOk or typeof(authExport) ~= "table" or type(authExport.GetShared) ~= "function" then
	warn("[Club Neon][StaffSpectator] Service or authorization module failed to load.")
	return
end
local auth = authExport.GetShared()
local globalApi = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
local spectator = spectatorExport.new({
	authorize = function(userId, permission) return auth:Check(userId, permission) end,
	audit = function(actorUserId, targetUserId, action)
		local replayEndpoint = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
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
			warn("[Club Neon][StaffSpectator][AuditUnavailable] actor=" .. tostring(actorUserId) .. " target=" .. tostring(targetUserId) .. " action=" .. tostring(action))
		end
	end,
})
if not spectator:Start() then warn("[Club Neon][StaffSpectator] Startup failed."); return end
local control = ServerStorage:FindFirstChild("ClubNeonStaffSpectatorControl")
if control and not control:IsA("BindableFunction") then warn("[Club Neon][StaffSpectator] Control endpoint has wrong class."); spectator:Stop(); return end
if not control then control = Instance.new("BindableFunction"); control.Name = "ClubNeonStaffSpectatorControl"; control.Parent = ServerStorage end
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
local statusFunction = ServerStorage:FindFirstChild("GetClubNeonStaffSpectatorStatus")
if statusFunction and not statusFunction:IsA("BindableFunction") then statusFunction:Destroy(); statusFunction = nil end
if not statusFunction then statusFunction = Instance.new("BindableFunction"); statusFunction.Name = "GetClubNeonStaffSpectatorStatus"; statusFunction.Parent = ServerStorage end
statusFunction.OnInvoke = function() return spectator:GetStatus() end
script.Destroying:Connect(function() spectator:Stop() end)
print("[Club Neon][StaffSpectator] Server-authorized observation service started; no gameplay powers granted.")

-- Bounded server-local event timeline. This endpoint is in ServerStorage and
-- is callable only by trusted server scripts; staff queries re-check authorization.
local replayModule = core:WaitForChild("SecurityReplayService")
local replayOk, replayExport = pcall(require, replayModule)
if not replayOk or typeof(replayExport) ~= "table" or type(replayExport.new) ~= "function" then
 warn("[Club Neon][SecurityReplay] Service failed to load: " .. tostring(replayExport))
 return
end
local replay = replayExport.new({
 authorize = function(userId, permission) return auth:Check(userId, permission) end,
})
if not replay:Start() then warn("[Club Neon][SecurityReplay] Startup failed."); return end
local replayEndpoint = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
if replayEndpoint and not replayEndpoint:IsA("BindableFunction") then
 warn("[Club Neon][SecurityReplay] Endpoint has wrong class."); replay:Stop(); return
end
if not replayEndpoint then
 replayEndpoint = Instance.new("BindableFunction")
 replayEndpoint.Name = "ClubNeonSecurityReplay"
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
    pcall(function() Workspace:SetAttribute("ClubNeonAdaptiveLoadMode", nextMode) end)
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
   warn("[Club Neon][AdaptiveLoad] Startup failed: " .. tostring(loadResult))
   loadManager = nil
  else
   Workspace:SetAttribute("ClubNeonAdaptiveLoadMode", loadManager:GetStatus().mode)
  end
 else
  warn("[Club Neon][AdaptiveLoad] Module failed to load: " .. tostring(loadExport))
 end
else
 warn("[Club Neon][AdaptiveLoad] Module is missing; optional workload remains ungated.")
end

local loadControl = ServerStorage:FindFirstChild("ClubNeonSecurityLoadManager")
if loadManager then
 if loadControl and not loadControl:IsA("BindableFunction") then
  warn("[Club Neon][AdaptiveLoad] Control endpoint has wrong class; endpoint not exposed.")
 else
  if not loadControl then
   loadControl = Instance.new("BindableFunction")
   loadControl.Name = "ClubNeonSecurityLoadManager"
   loadControl.Parent = ServerStorage
  end
  loadControl.OnInvoke = function(action, taskName, amount)
   if action == "Status" then return loadManager:GetStatus() end
   if action == "GetBudget" then return loadManager:GetBudget(taskName) end
   if action == "TryConsume" then return loadManager:TryConsume(taskName, amount) end
   return false, "Unsupported adaptive-load operation."
  end
  local loadStatus = ServerStorage:FindFirstChild("GetClubNeonSecurityLoadStatus")
  if loadStatus and not loadStatus:IsA("BindableFunction") then loadStatus:Destroy(); loadStatus = nil end
  if not loadStatus then
   loadStatus = Instance.new("BindableFunction")
   loadStatus.Name = "GetClubNeonSecurityLoadStatus"
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
   and type(instance.Query) == "function" and type(instance.QueryRaids) == "function"
   and type(instance.GetStatus) == "function" then
   threatService = instance
   if not threatService:Start() then threatService = nil end
  else
   warn("[Club Neon][ThreatIntelligence] Service interface validation failed: " .. tostring(instance))
  end
 else
  warn("[Club Neon][ThreatIntelligence] Module failed to load: " .. tostring(threatExport))
 end
else
 warn("[Club Neon][ThreatIntelligence] Optional module is missing.")
end

local threatEndpoint = ServerStorage:FindFirstChild("ClubNeonThreatIntelligence")
if threatEndpoint and not threatEndpoint:IsA("BindableFunction") then
 warn("[Club Neon][ThreatIntelligence] Endpoint has wrong class; service remains unavailable.")
 if threatService then threatService:Stop(); threatService = nil end
else
 if not threatEndpoint then
  threatEndpoint = Instance.new("BindableFunction")
  threatEndpoint.Name = "ClubNeonThreatIntelligence"
  threatEndpoint.Parent = ServerStorage
 end
 threatEndpoint.OnInvoke = function(action, ...)
  if not threatService then return false, {}, "Threat intelligence is unavailable." end
  if action == "Record" then return threatService:Record(...) end
  if action == "Query" then
   if loadManager and not loadManager:TryConsume("ThreatReviewQueries") then
    return false, {}, "Threat review is temporarily rate-limited while the server is under load."
   end
   return threatService:Query(...)
  end
  if action == "QueryRaids" then
   if loadManager and not loadManager:TryConsume("ThreatReviewQueries") then
    return false, {}, "Raid review is temporarily rate-limited while the server is under load."
   end
   return threatService:QueryRaids(...)
  end
  if action == "Status" then return threatService:GetStatus() end
  return false, "Unsupported threat-intelligence action."
 end
 local threatStatus = ServerStorage:FindFirstChild("GetClubNeonThreatIntelligenceStatus")
 if threatStatus and not threatStatus:IsA("BindableFunction") then threatStatus:Destroy(); threatStatus = nil end
 if not threatStatus then
  threatStatus = Instance.new("BindableFunction")
  threatStatus.Name = "GetClubNeonThreatIntelligenceStatus"
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
    warn("[Club Neon][Honeypot] Startup failed: " .. tostring(startedResult))
    honeypotService = nil
   end
  else
   warn("[Club Neon][Honeypot] Module interface validation failed: " .. tostring(instance))
  end
 else
  warn("[Club Neon][Honeypot] Module failed to load: " .. tostring(honeypotExport))
 end
else
 warn("[Club Neon][Honeypot] Optional module is missing.")
end

local honeypotStatus = ServerStorage:FindFirstChild("GetClubNeonHoneypotStatus")
if honeypotStatus and not honeypotStatus:IsA("BindableFunction") then
 honeypotStatus:Destroy()
 honeypotStatus = nil
end
if honeypotService then
 if not honeypotStatus then
  honeypotStatus = Instance.new("BindableFunction")
  honeypotStatus.Name = "GetClubNeonHoneypotStatus"
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
local replayStatus = ServerStorage:FindFirstChild("GetClubNeonSecurityReplayStatus")
if replayStatus and not replayStatus:IsA("BindableFunction") then replayStatus:Destroy(); replayStatus = nil end
if not replayStatus then
 replayStatus = Instance.new("BindableFunction")
 replayStatus.Name = "GetClubNeonSecurityReplayStatus"
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
    warn("[Club Neon][ClientIntegrity] Startup failed: " .. tostring(startedResult))
    clientIntegrityService = nil
   end
  else
   warn("[Club Neon][ClientIntegrity] Module interface validation failed: " .. tostring(instance))
  end
 else
  warn("[Club Neon][ClientIntegrity] Module failed to load: " .. tostring(telemetryExport))
 end
else
 warn("[Club Neon][ClientIntegrity] Optional module is missing.")
end
local clientIntegrityStatus = ServerStorage:FindFirstChild("GetClubNeonClientIntegrityStatus")
if clientIntegrityStatus and not clientIntegrityStatus:IsA("BindableFunction") then
 clientIntegrityStatus:Destroy()
 clientIntegrityStatus = nil
end
if clientIntegrityService then
 if not clientIntegrityStatus then
  clientIntegrityStatus = Instance.new("BindableFunction")
  clientIntegrityStatus.Name = "GetClubNeonClientIntegrityStatus"
  clientIntegrityStatus.Parent = ServerStorage
 end
 clientIntegrityStatus.OnInvoke = function() return clientIntegrityService:GetStatus() end
end
script.Destroying:Connect(function()
 replay:Stop()
 if threatService then threatService:Stop() end
 if honeypotService then honeypotService:Stop() end
 if clientIntegrityService then clientIntegrityService:Stop() end
 if loadManager then
  loadManager:Stop()
  if Workspace:GetAttribute("ClubNeonAdaptiveLoadMode") ~= nil then Workspace:SetAttribute("ClubNeonAdaptiveLoadMode", nil) end
 end
end)
print("[Club Neon][SecurityReplay] Bounded server-local event history ready; persistent writes=0; frame capture=false.")
if loadManager then print("[Club Neon][AdaptiveLoad] Adaptive optional-work budgets started; essential security paths remain unrestricted.") end
if threatService then print("[Club Neon][ThreatIntelligence] Bounded local correlation ready; automatic enforcement=false.") end
if honeypotService then print("[Club Neon][Honeypot] Isolated decoy remotes active; detection-only; automatic enforcement=false.") end
if clientIntegrityService then print("[Club Neon][ClientIntegrity] Fixed-code client observations enabled; untrusted; no enforcement.") end
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
local stagedVisual = Instance.new("LocalScript")
stagedVisual.Name = VISUAL_STAGE_NAME
stagedVisual.Source = visualSource
stagedVisual.Disabled = true
stagedVisual.Parent = StarterPlayerScripts

-- Keep the last known-good generation as a rollback copy. Promote only after staging succeeds.
if oldBackup then oldBackup:Destroy() end
if bootstrapBackup then bootstrapBackup:Destroy() end
if cameraBackup then cameraBackup:Destroy() end
if integrityBackup then integrityBackup:Destroy() end
if visualBackup then visualBackup:Destroy() end
local activeBootstrapWasDisabled = activeBootstrap and activeBootstrap.Disabled
local activeCameraWasDisabled = activeCamera and activeCamera.Disabled
local activeIntegrityWasDisabled = activeIntegrity and activeIntegrity.Disabled
local activeVisualWasDisabled = activeVisual and activeVisual.Disabled
local promotedFolder, promotedBootstrap, promotedCamera, promotedIntegrity, promotedVisual = false, false, false, false, false
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
 if activeVisual then activeVisual.Name = VISUAL_BACKUP_NAME; activeVisual.Disabled = true end
 stagedVisual.Name = VISUAL_NAME
 promotedVisual = true
 stagedVisual.Disabled = false
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
  local failedVisual = StarterPlayerScripts:FindFirstChild(VISUAL_NAME)
  if failedVisual and failedVisual ~= activeVisual then failedVisual:Destroy() end
  if activeVisual and activeVisual.Parent then activeVisual.Name = VISUAL_NAME; activeVisual.Disabled = activeVisualWasDisabled end
  local failedVisualStage = StarterPlayerScripts:FindFirstChild(VISUAL_STAGE_NAME)
  if failedVisualStage then failedVisualStage:Destroy() end
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
  print("[Club Neon Security] Removed obsolete ClubMusicAuthorizationResolver BindableFunction.")
 else
  warn("[Club Neon Security] Legacy authorization object has an unexpected class; it was left untouched.")
 end
end

print("[Club Neon Security] Installed " .. tostring(#ALL_MODULE_NAMES) .. " modules; SecurityCore release=" .. RELEASE_COMMIT .. "; Phase32 release=" .. PHASE32_COMMIT)
print("[Club Neon Security] Phase 32 modules installed; updated controller and Kohl's Admin addon sources are still required for commands and enforcement wiring.")
print("[Club Neon Security] Manifest: ServerStorage/" .. FOLDER_NAME .. "/InstallManifest")
print("[Club Neon Security] Previous release retained under ServerStorage/" .. BACKUP_NAME)
print("[Club Neon Security] Staff spectator camera installed under StarterPlayer/StarterPlayerScripts/" .. CAMERA_NAME)
print("[Club Neon Security] Untrusted client integrity observer installed under StarterPlayer/StarterPlayerScripts/" .. INTEGRITY_NAME)
print("[Club Neon Security] Adaptive visual quality client installed under StarterPlayer/StarterPlayerScripts/" .. VISUAL_NAME)
print("[Club Neon Security] CharacterPhysicsGuard remains detection-only.")