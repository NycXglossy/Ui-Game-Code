--!strict
-- SultanSettingsService.server.lua
-- Place in ServerScriptService. Uses the existing server-owned ClubMusic rank/pass attributes.
-- Movement/AFK/teleport preferences are session-scoped; no profile schema is changed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")

local FOLDER_NAME = "SultanSettingsRemotes"
local REQUEST_COOLDOWN = 0.25
local ANNOUNCEMENT_COOLDOWN = 180
local BUBBLE_COOLDOWN = 5
local MAX_MESSAGE_LENGTH = 180

local existingFolder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
if existingFolder and not existingFolder:IsA("Folder") then
	error("[Sultan Settings] ReplicatedStorage." .. FOLDER_NAME .. " exists but is not a Folder; refusing to replace an unrelated instance.")
end

local folder = existingFolder :: Folder?
if not folder then
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage
end

local existingRequest = folder:FindFirstChild("Request")
if existingRequest and not existingRequest:IsA("RemoteFunction") then
	error("[Sultan Settings] Request exists with the wrong class; expected RemoteFunction.")
end

local request = existingRequest :: RemoteFunction?
if not request then
	request = Instance.new("RemoteFunction")
	request.Name = "Request"
	request.Parent = folder
end

local existingBroadcast = folder:FindFirstChild("Broadcast")
if existingBroadcast and not existingBroadcast:IsA("RemoteEvent") then
	error("[Sultan Settings] Broadcast exists with the wrong class; expected RemoteEvent.")
end

local broadcast = existingBroadcast :: RemoteEvent?
if not broadcast then
	broadcast = Instance.new("RemoteEvent")
	broadcast.Name = "Broadcast"
	broadcast.Parent = folder
end

type Settings = {
	walkSpeed: number,
	jumpPower: number,
	afk: boolean,
	afkMessage: string,
	allowTeleport: boolean,
}

local settingsByUserId: {[number]: Settings} = {}
local lastRequestAt: {[number]: number} = {}
local lastBubbleAt: {[number]: number} = {}
local lastAnnouncementAt = 0
local baseMovementByHumanoid: {[Humanoid]: {walkSpeed: number, jumpPower: number, useJumpPower: boolean}} = {}

local function getSettings(player: Player): Settings
	local existing = settingsByUserId[player.UserId]
	if existing then return existing end
	local created: Settings = {
		walkSpeed = 20,
		jumpPower = 80,
		afk = false,
		afkMessage = "",
		allowTeleport = false,
	}
	settingsByUserId[player.UserId] = created
	return created
end

local function isSultan(player: Player): boolean
	-- This attribute is set by UI_Server_Controller after server-side pass/rank checks.
	return player:GetAttribute("IsTikiTideSultan") == true
end

local function hasClubPermission(player: Player, permission: string): boolean
	local resolver = ServerStorage:FindFirstChild("ClubMusicAuthorizationResolver")
	if not resolver or not resolver:IsA("BindableFunction") then return false end
	local ok, allowed = pcall(function()
		return resolver:Invoke(player.UserId, permission)
	end)
	return ok and allowed == true
end

local function filterBroadcastText(player: Player, raw: any): string?
	if typeof(raw) ~= "string" then return nil end
	local trimmed = string.match(raw, "^%s*(.-)%s*$") or ""
	if trimmed == "" or #trimmed > MAX_MESSAGE_LENGTH then return nil end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(trimmed, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(result) ~= "string" or result == "" then return nil end
	return string.sub(result, 1, MAX_MESSAGE_LENGTH)
end

local function applyMovement(player: Player)
	if not isSultan(player) then return end
	local settings = getSettings(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	-- Capture this character's actual baseline once so entitlement revocation
	-- restores the game's configured movement instead of assuming Roblox defaults.
	if not baseMovementByHumanoid[humanoid] then
		baseMovementByHumanoid[humanoid] = {
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			useJumpPower = humanoid.UseJumpPower,
		}
	end
	humanoid.WalkSpeed = math.clamp(settings.walkSpeed, 20, 100)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = math.clamp(settings.jumpPower, 80, 300)
end

local function revokeSultanState(player: Player)
	local settings = getSettings(player)
	settings.walkSpeed = 20
	settings.jumpPower = 80
	settings.afk = false
	settings.afkMessage = ""
	settings.allowTeleport = false
	player:SetAttribute("SultanAFK", false)
	player:SetAttribute("SultanAFKMessage", "")
	player:SetAttribute("SultanAllowTeleport", false)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local baseline = humanoid and baseMovementByHumanoid[humanoid]
	if humanoid and baseline then
		humanoid.WalkSpeed = baseline.walkSpeed
		humanoid.UseJumpPower = baseline.useJumpPower
		humanoid.JumpPower = baseline.jumpPower
		baseMovementByHumanoid[humanoid] = nil
	end
end

local function snapshot(player: Player)
	local settings = getSettings(player)
	local roster = {}
	for _, other in ipairs(Players:GetPlayers()) do
		table.insert(roster, {
			userId = other.UserId,
			name = other.Name,
			displayName = other.DisplayName,
			allowTeleport = other:GetAttribute("SultanAllowTeleport") == true,
		})
	end
	return {
		walkSpeed = settings.walkSpeed,
		jumpPower = settings.jumpPower,
		afk = settings.afk,
		afkMessage = settings.afkMessage,
		allowTeleport = settings.allowTeleport,
		gravity = workspace.Gravity,
		isSultan = isSultan(player),
		canAnnounce = hasClubPermission(player, "GlobalAnnouncement"),
		canSetGravity = hasClubPermission(player, "GlobalConfig"),
		players = roster,
	}
end

local function fail(message: string)
	return {ok = false, message = message}
end

local function handleRequest(player: Player, action: any, payload: any)
	if player.Parent ~= Players then return fail("Player is no longer connected.") end
	if typeof(action) ~= "string" or #action > 32 or typeof(payload) ~= "table" then
		return fail("Invalid request.")
	end

	local now = os.clock()
	local previous = lastRequestAt[player.UserId] or 0
	if previous > 0 and now - previous < REQUEST_COOLDOWN then
		return fail("Please wait before changing another setting.")
	end
	lastRequestAt[player.UserId] = now

	if action == "GetSnapshot" then
		if not isSultan(player) then return fail("Tiki Tide Sultan access is required.") end
		return {ok = true, data = snapshot(player)}
	end

	if not isSultan(player) then
		return fail("Tiki Tide Sultan access is required.")
	end

	local settings = getSettings(player)

	if action == "SetMovement" then
		local speed = payload.walkSpeed
		local jump = payload.jumpPower
		if typeof(speed) ~= "number" or speed ~= speed or speed == math.huge or speed == -math.huge
			or typeof(jump) ~= "number" or jump ~= jump or jump == math.huge or jump == -math.huge then
			return fail("Invalid movement values.")
		end
		settings.walkSpeed = math.clamp(speed, 20, 100)
		settings.jumpPower = math.clamp(jump, 80, 300)
		applyMovement(player)
		return {ok = true, message = "Movement settings applied.", data = snapshot(player)}
	elseif action == "SetAFK" then
		if typeof(payload.enabled) ~= "boolean" then return fail("Invalid AFK setting.") end
		local message = ""
		if payload.enabled then
			local filtered = filterBroadcastText(player, payload.message or "")
			if filtered == nil then return fail("Enter a valid AFK message (maximum 180 characters).") end
			-- Text filtering yields; re-check entitlement before committing state.
			if not isSultan(player) or player.Parent ~= Players then
				return fail("Tiki Tide Sultan access is required.")
			end
			message = filtered
		end
		settings.afk = payload.enabled
		settings.afkMessage = message
		player:SetAttribute("SultanAFK", settings.afk)
		player:SetAttribute("SultanAFKMessage", settings.afkMessage)
		return {ok = true, message = if settings.afk then "AFK mode enabled." else "AFK mode disabled.", data = snapshot(player)}
	elseif action == "SetTeleportAllowed" then
		if typeof(payload.enabled) ~= "boolean" then return fail("Invalid teleport permission.") end
		settings.allowTeleport = payload.enabled
		player:SetAttribute("SultanAllowTeleport", settings.allowTeleport)
		return {ok = true, message = if settings.allowTeleport then "Players may teleport to you." else "Teleport permission disabled.", data = snapshot(player)}
	elseif action == "TeleportTo" then
		local targetUserId = payload.userId
		if typeof(targetUserId) ~= "number" or targetUserId % 1 ~= 0 or targetUserId <= 0 then
			return fail("Select a valid player.")
		end
		local target = Players:GetPlayerByUserId(targetUserId)
		if not target or target == player or not target.Character then return fail("That player is unavailable.") end
		if target:GetAttribute("SultanAllowTeleport") ~= true and not hasClubPermission(player, "GlobalModeration") then
			return fail("That player has not allowed teleporting to them.")
		end
		-- Permission resolution may yield; verify both participants and consent again.
		if not isSultan(player) or player.Parent ~= Players or target.Parent ~= Players then
			return fail("Teleport access is no longer available.")
		end
		if target:GetAttribute("SultanAllowTeleport") ~= true and not hasClubPermission(player, "GlobalModeration") then
			return fail("That player has not allowed teleporting to them.")
		end
		local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		local ownRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not targetRoot or not targetRoot:IsA("BasePart") or not ownRoot or not ownRoot:IsA("BasePart") then
			return fail("Character position is not ready.")
		end
		ownRoot.CFrame = targetRoot.CFrame * CFrame.new(3, 0, 0)
		return {ok = true, message = "Teleported to " .. target.DisplayName .. "."}
	elseif action == "SetGravity" then
		if not hasClubPermission(player, "GlobalConfig") then
			return fail("Administrator configuration permission is required to change server gravity.")
		end
		local gravity = payload.gravity
		if typeof(gravity) ~= "number" or gravity ~= gravity or gravity == math.huge or gravity == -math.huge then
			return fail("Invalid gravity value.")
		end
		-- Keep the entitlement and administrator checks adjacent to the mutation.
		-- This makes the intended authorization boundary explicit if the resolver
		-- implementation later gains yielding work.
		if not isSultan(player) or player.Parent ~= Players
			or not hasClubPermission(player, "GlobalConfig") then
			return fail("Administrator configuration permission is no longer available.")
		end
		workspace.Gravity = math.clamp(gravity, 20, 192.62)
		return {ok = true, message = "Server gravity updated.", data = snapshot(player)}
	elseif action == "BubbleBroadcast" then
		if not hasClubPermission(player, "GlobalAnnouncement") then return fail("Administrator announcement permission is required.") end
		local last = lastBubbleAt[player.UserId] or 0
		if last > 0 and now - last < BUBBLE_COOLDOWN then return fail("Wait before sending another overhead broadcast.") end
		local filtered = filterBroadcastText(player, payload.message)
		if not filtered then return fail("Enter a valid broadcast message.") end
		-- Filtering yields; reauthorize immediately before broadcasting.
		if not isSultan(player) or player.Parent ~= Players or not hasClubPermission(player, "GlobalAnnouncement") then
			return fail("Administrator announcement permission is required.")
		end
		local broadcastAt = os.clock()
		local previousBubble = lastBubbleAt[player.UserId] or 0
		if previousBubble > 0 and broadcastAt - previousBubble < BUBBLE_COOLDOWN then
			return fail("Wait before sending another overhead broadcast.")
		end
		lastBubbleAt[player.UserId] = broadcastAt
		broadcast:FireAllClients("Bubble", player.UserId, filtered)
		return {ok = true, message = "Overhead broadcast sent."}
	elseif action == "Announcement" then
		if not hasClubPermission(player, "GlobalAnnouncement") then return fail("Administrator announcement permission is required.") end
		if lastAnnouncementAt > 0 and now - lastAnnouncementAt < ANNOUNCEMENT_COOLDOWN then
			local remaining = math.ceil(ANNOUNCEMENT_COOLDOWN - (now - lastAnnouncementAt))
			return fail("Announcement cooldown: " .. tostring(remaining) .. " seconds remaining.")
		end
		local filtered = filterBroadcastText(player, payload.message)
		if not filtered then return fail("Enter a valid announcement.") end
		-- Filtering yields; reauthorize immediately before broadcasting.
		if not isSultan(player) or player.Parent ~= Players or not hasClubPermission(player, "GlobalAnnouncement") then
			return fail("Administrator announcement permission is required.")
		end
		local broadcastAt = os.clock()
		if lastAnnouncementAt > 0 and broadcastAt - lastAnnouncementAt < ANNOUNCEMENT_COOLDOWN then
			local remaining = math.ceil(ANNOUNCEMENT_COOLDOWN - (broadcastAt - lastAnnouncementAt))
			return fail("Announcement cooldown: " .. tostring(remaining) .. " seconds remaining.")
		end
		lastAnnouncementAt = broadcastAt
		broadcast:FireAllClients("Announcement", player.UserId, filtered)
		return {ok = true, message = "Announcement sent to this server."}
	end

	return fail("Unsupported Sultan Settings action.")
end

request.OnServerInvoke = function(player: Player, action: any, payload: any)
	local ok, result = pcall(handleRequest, player, action, payload)
	if not ok then
		warn("[Sultan Settings] Request failed: " .. tostring(result))
		return fail("The settings request could not be completed.")
	end
	return result
end

local function bindPlayer(player: Player)
	getSettings(player)

	-- Pass/rank verification can finish after CharacterAdded. Re-apply the
	-- saved movement values when the server-owned Sultan entitlement arrives.
	player:GetAttributeChangedSignal("IsTikiTideSultan"):Connect(function()
		if player.Parent ~= Players then return end
		if isSultan(player) then
			task.defer(function()
				if player.Parent == Players then applyMovement(player) end
			end)
		else
			revokeSultanState(player)
		end
	end)

	player.CharacterAdded:Connect(function()
		task.defer(function()
			if player.Parent == Players then applyMovement(player) end
		end)
	end)
	player.CharacterRemoving:Connect(function(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then baseMovementByHumanoid[humanoid] = nil end
	end)
	player:SetAttribute("SultanAFK", false)
	player:SetAttribute("SultanAFKMessage", "")
	player:SetAttribute("SultanAllowTeleport", false)

	-- Handle players whose entitlement was already resolved before this
	-- service bound their player lifecycle.
	if isSultan(player) then
		task.defer(function()
			if player.Parent == Players then applyMovement(player) end
		end)
	end
end

for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end
Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	settingsByUserId[player.UserId] = nil
	lastRequestAt[player.UserId] = nil
	lastBubbleAt[player.UserId] = nil
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then baseMovementByHumanoid[humanoid] = nil end
end)

print("[Sultan Settings] Server service ready.")
