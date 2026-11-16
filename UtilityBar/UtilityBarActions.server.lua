--!strict
-- UtilityBarActions.server.lua
-- Place as a Script in ServerScriptService.
-- This service is independent from ClubMusic and only refreshes the caller's own avatar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_FOLDER_NAME = "UtilityBarRemotes"
local REMOTE_NAME = "RefreshOwnAvatar"
local REQUEST_COOLDOWN = 15
local lastRequestAt: {[number]: number} = {}

local remoteFolder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
if remoteFolder and not remoteFolder:IsA("Folder") then
	remoteFolder:Destroy()
	remoteFolder = nil
end
if not remoteFolder then
	local folder = Instance.new("Folder")
	folder.Name = REMOTE_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	remoteFolder = folder
end

local remote = remoteFolder:FindFirstChild(REMOTE_NAME)
if remote and not remote:IsA("RemoteFunction") then
	remote:Destroy()
	remote = nil
end
if not remote then
	local functionObject = Instance.new("RemoteFunction")
	functionObject.Name = REMOTE_NAME
	functionObject.Parent = remoteFolder
	remote = functionObject
end

local refreshRemote = remote :: RemoteFunction

refreshRemote.OnServerInvoke = function(player: Player): (boolean, string)
	local now = os.clock()
	local previous = lastRequestAt[player.UserId] or 0
	if now - previous < REQUEST_COOLDOWN then
		return false, "Please wait before refreshing again."
	end
	lastRequestAt[player.UserId] = now

	local character = player.Character
	if not character or not character.Parent then
		return false, "Your character is not ready yet."
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Your character is still loading."
	end

	local ok, result = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
	end)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("HumanoidDescription") then
		warn("[UtilityBar] Avatar description lookup failed for userId " .. tostring(player.UserId) .. ": " .. tostring(result))
		return false, "Roblox could not load your current avatar."
	end

	local description = result :: HumanoidDescription
	local applyOk, applyError = pcall(function()
		if player.Character ~= character or not character.Parent or humanoid.Parent ~= character then
			error("Character changed while avatar was loading.")
		end
		humanoid:ApplyDescriptionResetAsync(description)
	end)
	description:Destroy()

	if not applyOk then
		warn("[UtilityBar] Avatar refresh failed for userId " .. tostring(player.UserId) .. ": " .. tostring(applyError))
		return false, "Avatar refresh failed. Please try again."
	end

	return true, "Your avatar has been refreshed."
end

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player.UserId] = nil
end)

print("[UtilityBar] Server-authoritative avatar refresh ready.")
