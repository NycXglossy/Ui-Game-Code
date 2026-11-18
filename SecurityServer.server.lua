--!strict
-- ServerScriptService/SecurityServer
-- Public reports and VIP-zone detection feed the existing Phase 21 IncidentResponse
-- service through ServerStorage only. This script creates no parallel incident store
-- and performs no automatic punishment.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local REPORT_COOLDOWN_SECONDS = 15
local ZONE_COOLDOWN_SECONDS = 5
local MAX_REASON_BYTES = 400
local MAX_SUMMARY_CHARACTERS = 120
local GROUP_ID = 500470662

local function getOrCreateFolder(parent: Instance, name: string): Folder?
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("Folder") then return existing end
		warn("[Tiki Tide][SecurityServer] " .. name .. " exists with the wrong class.")
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function getOrCreateRemote(parent: Instance, name: string): RemoteEvent?
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing:IsA("RemoteEvent") then return existing end
		warn("[Tiki Tide][SecurityServer] " .. name .. " exists with the wrong class.")
		return nil
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local securityFolder = getOrCreateFolder(ReplicatedStorage, "SecuritySystem")
if not securityFolder then return end
local reportEvent = getOrCreateRemote(securityFolder, "ReportIncident")
local staffAlert = getOrCreateRemote(securityFolder, "StaffAlert")
if not reportEvent or not staffAlert then return end

local apiFolder = ServerStorage:WaitForChild("ClubMusicGlobalAPI", 30)
local reportEndpoint = if apiFolder and apiFolder:IsA("Folder")
	then apiFolder:WaitForChild("SubmitGlobalSecurityReport", 15) else nil
local systemEndpoint = if apiFolder and apiFolder:IsA("Folder")
	then apiFolder:WaitForChild("SubmitGlobalSecuritySystemSignal", 15) else nil

local authorization: any = nil
local core = ServerStorage:WaitForChild("ClubMusicSecurityCore", 30)
local authorizationModule = if core and core:IsA("Folder") then core:FindFirstChild("Authorization") else nil
if authorizationModule and authorizationModule:IsA("ModuleScript") then
	local requireOk, exported = pcall(require, authorizationModule)
	if requireOk and typeof(exported) == "table" and type(exported.GetShared) == "function" then
		local sharedOk, instance = pcall(exported.GetShared, {
			groupId = GROUP_ID,
			studioStaff = true,
		})
		if sharedOk and typeof(instance) == "table"
			and type(instance.GetLevel) == "function"
			and type(instance.Refresh) == "function" then
			authorization = instance
		end
	end
end
if not authorization then
	warn("[Tiki Tide][SecurityServer] SecurityCore Authorization unavailable; staff-only alerts and zone bypass are disabled.")
end

local reportCooldowns: {[number]: number} = {}
local zoneCooldowns: {[number]: number} = {}

local function truncateUtf8(value: string, maxCharacters: number): string
	local length = utf8.len(value)
	if not length or length <= maxCharacters then return value end
	local nextByte = utf8.offset(value, maxCharacters + 1)
	return if nextByte then string.sub(value, 1, nextByte - 1) else value
end

local function cleanReason(value: any): string?
	if typeof(value) ~= "string" or #value < 1 or #value > MAX_REASON_BYTES or not utf8.len(value) then
		return nil
	end
	if string.find(value, "%c") then return nil end
	local trimmed = string.match(value, "^%s*(.-)%s*$") or ""
	if trimmed == "" or #trimmed > MAX_REASON_BYTES then return nil end
	return trimmed
end

local function getStaffLevel(player: Player): number?
	if not authorization or player.Parent ~= Players then return nil end
	local ok, level = pcall(authorization.GetLevel, authorization, player)
	if not ok then return nil end
	if typeof(level) ~= "number" then return nil end
	if level == 0 then
		local refreshOk, refreshed = pcall(authorization.Refresh, authorization, player)
		if not refreshOk or refreshed ~= true then return nil end
		ok, level = pcall(authorization.GetLevel, authorization, player)
		if not ok or typeof(level) ~= "number" then return nil end
	end
	return level
end

local function notifyStaff(payload: {[string]: any})
	if not staffAlert or not staffAlert.Parent then return end
	for _, staffPlayer in ipairs(Players:GetPlayers()) do
		local level = getStaffLevel(staffPlayer)
		if level and level >= 1 then
			pcall(function() staffAlert:FireClient(staffPlayer, payload) end)
		end
	end
end

reportEvent.OnServerEvent:Connect(function(reporter: Player, targetUserId: any, rawReason: any)
	if reporter.Parent ~= Players or typeof(targetUserId) ~= "number"
		or targetUserId ~= targetUserId or targetUserId <= 0 or targetUserId == math.huge
		or targetUserId % 1 ~= 0 then return end

	local target = Players:GetPlayerByUserId(math.floor(targetUserId))
	if not target or target == reporter or target.Parent ~= Players then return end
	local reason = cleanReason(rawReason)
	if not reason then return end

	local now = os.clock()
	local lastReport = reportCooldowns[reporter.UserId]
	if lastReport and now - lastReport < REPORT_COOLDOWN_SECONDS then return end
	-- Reserve the cooldown before TextService yields so concurrent remote calls
	-- cannot create parallel filter requests.
	reportCooldowns[reporter.UserId] = now

	local filterOk, filteredReason = pcall(function()
		local result = TextService:FilterStringAsync(reason, reporter.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not filterOk or typeof(filteredReason) ~= "string" or filteredReason == "" then
		warn("[Tiki Tide][SecurityServer] Report text filtering failed; report rejected.")
		return
	end

	local summary = truncateUtf8("Player report: " .. filteredReason, MAX_SUMMARY_CHARACTERS)
	if not reportEndpoint or not reportEndpoint:IsA("BindableFunction") then
		warn("[Tiki Tide][SecurityServer] Incident intake endpoint unavailable; player report was not stored.")
		return
	end

	local callOk, accepted, incidentId, detail = pcall(function()
		return reportEndpoint:Invoke(reporter.UserId, target.UserId, summary)
	end)
	if not callOk or accepted ~= true then
		warn("[Tiki Tide][SecurityServer] Player report intake failed: " .. tostring(if callOk then detail or incidentId else accepted))
		return
	end

	local alertId = tostring(incidentId or "")
	local alertReason = truncateUtf8(filteredReason, 100)
	notifyStaff({
		-- Compatibility names used by the Phase 21 SecurityClient.
		Category = "Player Report",
		TargetName = target.Name,
		Reason = alertReason,
		ReporterName = reporter.Name,
		Id = alertId,
		-- Structured fields retained for future dispatch UI integrations.
		kind = "AbuseReport",
		incidentId = alertId,
		reporterUserId = reporter.UserId,
		subjectUserId = target.UserId,
	})
end)

local clubClosedState = ServerStorage:WaitForChild("TikiTideClubClosed", 30)
local vipZone = Workspace:FindFirstChild("VIPRestrictedZone")
local clubEntrance = Workspace:FindFirstChild("ClubEntrance")
if vipZone and vipZone:IsA("BasePart") then
	if not vipZone.Anchored then
		warn("[Tiki Tide][SecurityServer] VIPRestrictedZone must be anchored; zone enforcement was not connected.")
	else
		vipZone.Touched:Connect(function(hit: BasePart)
			local character = hit:FindFirstAncestorOfClass("Model")
			if not character then return end
			local player = Players:GetPlayerFromCharacter(character)
			if not player or player.Parent ~= Players or player.Character ~= character then return end
			if zoneCooldowns[player.UserId] then return end

			local root = character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then return end
			local localPosition = vipZone.CFrame:PointToObjectSpace(root.Position)
			local halfSize = vipZone.Size * 0.5 + Vector3.new(3, 5, 3)
			if math.abs(localPosition.X) > halfSize.X
				or math.abs(localPosition.Y) > halfSize.Y
				or math.abs(localPosition.Z) > halfSize.Z then return end

			-- VIP is resolved only by the main controller's EntitlementAuthority.
			-- Wait briefly for the authoritative entitlement attribute; unresolved access is denied.
			local hasVip = player:GetAttribute("IsVIP")
			local entitlementDeadline = os.clock() + 8
			while typeof(hasVip) ~= "boolean" and os.clock() < entitlementDeadline
				and player.Parent == Players do
				task.wait(0.2)
				hasVip = player:GetAttribute("IsVIP")
			end

			local closed = clubClosedState ~= nil and clubClosedState:IsA("BoolValue")
				and (clubClosedState :: BoolValue).Value
			local level = getStaffLevel(player)
			local isStaff = level ~= nil and level >= 1
			if closed and isStaff then return end
			if not closed and hasVip == true then return end
			-- Unknown entitlement and unavailable staff verification fail closed.
			if isStaff then return end

			local now = os.clock()
			zoneCooldowns[player.UserId] = now
			local destination = if clubEntrance and clubEntrance:IsA("BasePart") then clubEntrance else nil
			if destination and player.Character == character and root.Parent == character then
				character:PivotTo(destination.CFrame + Vector3.new(0, 3, 0))
			else
				warn("[Tiki Tide][SecurityServer] ClubEntrance is missing or invalid; trespass was recorded without teleport.")
			end

			if systemEndpoint and systemEndpoint:IsA("BindableFunction") then
				local callOk, accepted, incidentId = pcall(function()
					return systemEndpoint:Invoke(
						"SecurityAlert",
						"Entered VIP zone without verified VIP entitlement.",
						player.UserId,
						"VIPRestrictedZone"
					)
				end)
				if callOk and accepted == true then
					local alertId = tostring(incidentId or "")
					notifyStaff({
						Category = "Zone Trespass",
						TargetName = player.Name,
						Reason = "Entered VIP zone without verified VIP entitlement.",
						ReporterName = "Automated Security",
						Id = alertId,
						kind = "SecurityAlert",
						incidentId = alertId,
						subjectUserId = player.UserId,
					})
				else
					warn("[Tiki Tide][SecurityServer] VIP-zone incident could not be stored.")
				end
			else
				warn("[Tiki Tide][SecurityServer] System incident intake endpoint unavailable.")
			end

			task.delay(ZONE_COOLDOWN_SECONDS, function()
				if zoneCooldowns[player.UserId] == now then
					zoneCooldowns[player.UserId] = nil
				end
			end)
		end)
	end
elseif vipZone then
	warn("[Tiki Tide][SecurityServer] VIPRestrictedZone exists but is not a BasePart.")
end

Players.PlayerRemoving:Connect(function(player)
	reportCooldowns[player.UserId] = nil
	zoneCooldowns[player.UserId] = nil
end)

print("[Tiki Tide][SecurityServer] Validated player reports and VIP-zone incident intake connected to Phase 21 IncidentResponse.")
