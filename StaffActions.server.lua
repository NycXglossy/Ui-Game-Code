--!strict
-- ServerScriptService/StaffActions.server.lua
-- Phase 22: server-local lockdown and staff player removal.
-- Security Core is the only authorization authority. All actions are server-side.
-- Lockdown is intentionally local to this Roblox server; no cross-server APIs are used.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local GROUP_ID = 500470662
local ACTION_COOLDOWN_SECONDS = 2

local function getOrCreateRemote(parent: Instance, name: string): RemoteEvent?
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("RemoteEvent") then return existing end
		warn("[Tiki Tide][StaffActions] " .. name .. " exists with the wrong class.")
		return nil
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local securityAction = getOrCreateRemote(ReplicatedStorage, "SecurityAction")
local actionResult = getOrCreateRemote(ReplicatedStorage, "SecurityActionResult")
if not securityAction or not actionResult then return end

local authorization: any = nil
local coreFolder = ServerStorage:WaitForChild("ClubMusicSecurityCore", 30)
local authorizationModule = if coreFolder and coreFolder:IsA("Folder")
	then coreFolder:FindFirstChild("Authorization") else nil

if authorizationModule and authorizationModule:IsA("ModuleScript") then
	local requireOk, exported = pcall(require, authorizationModule)
	if requireOk and typeof(exported) == "table" and type(exported.GetShared) == "function" then
		local sharedOk, shared = pcall(exported.GetShared, {
			groupId = GROUP_ID,
			studioStaff = true,
		})
		if sharedOk and typeof(shared) == "table"
			and type(shared.GetLevel) == "function"
			and type(shared.Refresh) == "function"
			and type(shared.Check) == "function" then
			authorization = shared
		end
	end
end

if not authorization then
	warn("[Tiki Tide][StaffActions] Security Core Authorization unavailable; all console actions are disabled.")
end

local function getVerifiedLevel(player: Player): number?
	if not authorization or player.Parent ~= Players then return nil end
	local ok, level = pcall(authorization.GetLevel, authorization, player)
	if not ok or typeof(level) ~= "number" then return nil end
	if level == 0 then
		local refreshOk, refreshed = pcall(authorization.Refresh, authorization, player)
		if not refreshOk or refreshed ~= true then return nil end
		ok, level = pcall(authorization.GetLevel, authorization, player)
		if not ok or typeof(level) ~= "number" then return nil end
	end
	return level
end

local function hasPermission(player: Player, permission: string): (boolean, string?)
	local level = getVerifiedLevel(player)
	if level == nil then return false, "Staff authorization is unavailable. Please retry shortly." end
	local ok, allowed, detail = pcall(authorization.Check, authorization, player.UserId, permission)
	if not ok then return false, "Staff authorization check failed." end
	if allowed ~= true then return false, if typeof(detail) == "string" then detail else "Permission denied." end
	return true
end

local function recordAudit(
	eventType: string,
	actorUserId: number,
	targetUserId: number,
	severity: string,
	metadata: {[string]: any}
): boolean
	local endpoint = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
	if not endpoint or not endpoint:IsA("BindableFunction") then
		warn("[Tiki Tide][StaffActions] Security replay audit endpoint is unavailable.")
		return false
	end
	local ok, recorded = pcall(function()
		return endpoint:Invoke("Record", eventType, actorUserId, targetUserId, severity, "StaffActions", metadata)
	end)
	return ok and recorded == true
end

local lastActionAt: {[number]: number} = {}
local lastStatusAt: {[number]: number} = {}
local function consumeActionCooldown(player: Player): boolean
	local now = os.clock()
	local previous = lastActionAt[player.UserId]
	if previous and now - previous < ACTION_COOLDOWN_SECONDS then return false end
	lastActionAt[player.UserId] = now
	return true
end

-- Door state is stored only in this server's memory. Original values are restored
-- exactly when lockdown is disabled. Newly added BaseParts are captured as well.
local lockdownActive = false
local originalDoorState: {[BasePart]: {canCollide: boolean, brickColor: BrickColor}} = {}
local doorAddedConnection: RBXScriptConnection? = nil

local function applyLockdownToPart(part: BasePart)
	if originalDoorState[part] == nil then
		originalDoorState[part] = {
			canCollide = part.CanCollide,
			brickColor = part.BrickColor,
		}
	end
	part.CanCollide = true
	part.BrickColor = BrickColor.new("Really red")
end

local function setLockdown(enabled: boolean): (boolean, string)
	if enabled == lockdownActive then
		return true, if enabled then "Lockdown is already active." else "Lockdown is already inactive."
	end

	if enabled then
		local found = Workspace:FindFirstChild("ClubDoors")
		if not found then return false, "Workspace.ClubDoors was not found." end
		local parts: {BasePart} = {}
		for _, descendant in ipairs(found:GetDescendants()) do
			if descendant:IsA("BasePart") then table.insert(parts, descendant) end
		end
		if #parts == 0 then return false, "No door BaseParts were found under Workspace.ClubDoors." end

		table.clear(originalDoorState)
		for _, part in ipairs(parts) do
			applyLockdownToPart(part)
		end
		if doorAddedConnection then doorAddedConnection:Disconnect() end
		doorAddedConnection = found.DescendantAdded:Connect(function(descendant)
			if lockdownActive and descendant:IsA("BasePart") then
				applyLockdownToPart(descendant)
			end
		end)
		lockdownActive = true
		return true, "Lockdown enabled for this server."
	end

	if doorAddedConnection then
		doorAddedConnection:Disconnect()
		doorAddedConnection = nil
	end
	for part, state in pairs(originalDoorState) do
		pcall(function()
			part.CanCollide = state.canCollide
			part.BrickColor = state.brickColor
		end)
	end
	table.clear(originalDoorState)
	lockdownActive = false
	return true, "Lockdown disabled; original door settings restored."
end

local function updateConsoleForPlayer(player: Player)
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui", 15)
		if not playerGui or player.Parent ~= Players then return end
		local console = playerGui:WaitForChild("StaffConsoleGui", 15)
		if not console or not console:IsA("ScreenGui") then
			warn("[Tiki Tide][StaffActions] StaffConsoleGui is missing or is not a ScreenGui for " .. player.Name)
			return
		end

		while player.Parent == Players do
			local level = getVerifiedLevel(player)
			local authorized = level ~= nil and level >= 1
			console:SetAttribute("StaffAuthorized", authorized)
			if not authorized then console.Enabled = false end
			local launcher = playerGui:FindFirstChild("StaffConsoleLauncher")
			if launcher and launcher:IsA("ScreenGui") then launcher.Enabled = authorized end
			task.wait(30)
		end
		if console.Parent then console.Enabled = false end
		local launcher = playerGui:FindFirstChild("StaffConsoleLauncher")
		if launcher and launcher:IsA("ScreenGui") then launcher.Enabled = false end
	end)
end

Players.PlayerAdded:Connect(updateConsoleForPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	updateConsoleForPlayer(player)
end

local function sendResult(player: Player, action: string, ok: boolean, message: string)
	if player.Parent == Players and actionResult.Parent then
		pcall(function()
			actionResult:FireClient(player, action, ok, message, lockdownActive)
		end)
	end
end

-- Client-visible command IDs are deliberately mapped to fixed bridge operations.
-- The client never supplies a bridge operation name. The controller remains the
-- source of truth for per-operation staff/admin authorization and argument rules.
local STAFF_COMMANDS: {[string]: string} = {
	PlaybackSkip = "Skip", PlaybackPause = "TogglePause", PlaybackRestart = "Restart",
	RequestLock = "ToggleRequestLock", PlaybackStatus = "Status", QueueView = "Queue",
	QueueRemove = "RemoveQueueEntry", QueueClear = "ClearQueue",
	EmergencyRequestLock = "EmergencyLock", PlaybackForceStop = "ForceStop",
	RequestMute = "RequestMute", ClearUserQueue = "ClearUserQueue",
	TrackBlock = "TrackBlock", ModerationHistory = "ModerationHistory",
	DJSessionStatus = "DJSessionStatus", DJSessionStart = "DJSessionStart",
	DJSessionHandoff = "DJSessionHandoff", DJSessionEnd = "DJSessionEnd",
	Warn = "Phase32Warn", Restrict = "Phase32Restrict", TempBan = "Phase32TempBan",
	PermanentBan = "Phase32PermanentBan", PermanentBanAlts = "Phase32PermanentBanAlts",
	Unban = "Phase32Unban", Unrestrict = "Phase32Unrestrict",
	PunishmentHistory = "Phase32History", AccountRisk = "Phase32Risk",
	SecurityReplay = "SecurityReplay", ThreatIntelligence = "SecurityThreatIntelligence",
	SpectateEnter = "StaffSpectatorEnter", SpectateSwitch = "StaffSpectatorSwitch",
	SpectateExit = "StaffSpectatorExit", SpectateState = "StaffSpectatorState",
	SecurityStatus = "SecurityStatus", SecurityIncidents = "SecurityIncidents",
	ThreatCaseOpen = "SecurityThreatCaseOpen", IncidentOpen = "SecurityIncidentOpen",
	IncidentResolve = "SecurityIncidentResolve", SecurityPolicy = "SecurityPolicy",
	SecurityPolicySet = "SecurityPolicySet",
	Health = "OperationalHealth", Diagnostics = "OperationalDiagnostics",
	PurchaseDiagnostics = "PurchaseDiagnostics", Services = "OperationalServices",
	Errors = "OperationalErrors", Metrics = "OperationalMetrics",
	SecurityLog = "OperationalSecurityLog", RateLimit = "OperationalRateLimit",
	Config = "OperationalConfig", Recovery = "OperationalRecovery",
	Reconcile = "OperationalReconcile", CatalogRefresh = "OperationalCatalogRefresh",
	Maintenance = "OperationalMaintenance",
}

securityAction.OnServerEvent:Connect(function(player: Player, action: any, targetName: any, rawReason: any)
	if player.Parent ~= Players or typeof(action) ~= "string" then return end

	if action == "GetStatus" then
		local now = os.clock()
		local previousStatus = lastStatusAt[player.UserId]
		if previousStatus and now - previousStatus < 1 then return end
		lastStatusAt[player.UserId] = now
		local level = getVerifiedLevel(player)
		if level == nil or level < 1 then
			sendResult(player, action, false, "Staff console access is unavailable.")
			return
		end
		sendResult(player, action, true, "Security status refreshed.")
		return
	end

	if action ~= "ToggleLockdown" and action ~= "RunClubMusicCommand" then
		sendResult(player, tostring(action):sub(1, 32), false, "Unsupported security action.")
		return
	end

	if not consumeActionCooldown(player) then
		sendResult(player, action, false, "Please wait before using another security action.")
		return
	end

	if action == "RunClubMusicCommand" then
		local level = getVerifiedLevel(player)
		if level == nil or level < 1 then
			sendResult(player, action, false, "Staff authorization is unavailable or insufficient.")
			return
		end
		if typeof(targetName) ~= "string" or #targetName > 40 then
			sendResult(player, action, false, "Select a valid Staff Console action.")
			return
		end
		local operation = STAFF_COMMANDS[targetName]
		if not operation then
			sendResult(player, action, false, "That Staff Console action is not allowlisted.")
			return
		end
		local argument = if typeof(rawReason) == "string" then rawReason else ""
		if #argument > 320 or not utf8.len(argument) or string.find(argument, "%c") then
			sendResult(player, action, false, "The command details are invalid or too long.")
			return
		end
		local bridge = ServerStorage:FindFirstChild("ClubMusicAdminBridge")
		if not bridge or not bridge:IsA("BindableFunction") or bridge.Parent ~= ServerStorage then
			sendResult(player, action, false, "ClubMusic admin bridge is unavailable.")
			return
		end
		if not recordAudit("staff_console_command_requested", player.UserId, 0, "Warning", {
			command = targetName,
			operation = operation,
		}) then
			sendResult(player, action, false, "Security audit is unavailable; the command was not run.")
			return
		end
		local invokeOk, accepted, message = pcall(function()
			return bridge:Invoke(player, operation, argument)
		end)
		local succeeded = invokeOk and accepted == true
		local resultMessage = if typeof(message) == "string" then message
			elseif not invokeOk then "The ClubMusic command failed. Check server Output."
			else "ClubMusic rejected the command."
		recordAudit(if succeeded then "staff_console_command_completed" else "staff_console_command_rejected",
			player.UserId, 0, if succeeded then "Info" else "Warning", {
				command = targetName,
				operation = operation,
				accepted = succeeded,
			})
		sendResult(player, action, succeeded, resultMessage)
		return
	end

	if action == "ToggleLockdown" then
		local allowed, denial = hasPermission(player, "SecurityPolicy")
		if not allowed then
			sendResult(player, action, false, denial or "SecurityPolicy permission required.")
			return
		end

		local requestedState = not lockdownActive
		if not recordAudit("staff_action_requested", player.UserId, 0, "Warning", {
			action = "ToggleLockdown",
			requestedState = requestedState,
		}) then
			sendResult(player, action, false, "Security audit is unavailable; lockdown was not changed.")
			return
		end

		local changed, message = setLockdown(requestedState)
		recordAudit(if changed then "staff_action_completed" else "staff_action_failed",
			player.UserId, 0, if changed then "Warning" else "Error", {
				action = "ToggleLockdown",
				lockdownActive = lockdownActive,
				result = message,
			})
		sendResult(player, action, changed, message)
		return
	end

end)

Players.PlayerRemoving:Connect(function(player)
	lastActionAt[player.UserId] = nil
	lastStatusAt[player.UserId] = nil
end)

script.Destroying:Connect(function()
	if doorAddedConnection then doorAddedConnection:Disconnect() end
	if lockdownActive then
		for part, state in pairs(originalDoorState) do
			pcall(function()
				part.CanCollide = state.canCollide
				part.BrickColor = state.brickColor
			end)
		end
	end
end)

print("[Tiki Tide][StaffActions] Phase 22 local lockdown and allowlisted ClubMusic staff command console ready.")
