--!strict
-- StarterPlayer/StarterPlayerScripts/SecurityConsole.client.lua
-- Phase 22 UI companion. This script only sends requests and displays server results.
-- It never decides whether the local player is authorized.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local securityAction = ReplicatedStorage:WaitForChild("SecurityAction") :: RemoteEvent
local actionResult = ReplicatedStorage:WaitForChild("SecurityActionResult") :: RemoteEvent

local playerGui = localPlayer:WaitForChild("PlayerGui")
local console = playerGui:WaitForChild("StaffConsoleGui")
if not console:IsA("ScreenGui") then
	warn("[Tiki Tide][SecurityConsole] StaffConsoleGui must be a ScreenGui.")
	return
end

local mainFrame = console:WaitForChild("MainFrame")
local lockdownButton = mainFrame:WaitForChild("LockdownBtn") :: GuiButton
local kickButton = mainFrame:WaitForChild("KickBtn") :: GuiButton
local targetBox = mainFrame:WaitForChild("TargetPlayerBox") :: TextBox
local reasonBox = mainFrame:WaitForChild("ReasonBox") :: TextBox
local statusLabel = mainFrame:FindFirstChild("StatusLabel")

local lockdownActive = false
local awaitingLockdownConfirmation = false
local confirmationGeneration = 0
local requestPending = false
local pendingKickTarget = ""

local function setStatus(message: string)
	if statusLabel and statusLabel:IsA("TextLabel") then
		statusLabel.Text = string.sub(message, 1, 180)
	end
end

local function updateLockdownButton()
	lockdownButton.Active = not requestPending
	lockdownButton.AutoButtonColor = not requestPending
	(lockdownButton :: any).Text = if lockdownActive then "Disable Lockdown" else "Enable Lockdown"
end

local function requestFinished()
	requestPending = false
	updateLockdownButton()
	kickButton.Active = true
	kickButton.AutoButtonColor = true
end

lockdownButton.Activated:Connect(function()
	if requestPending then return end
	if not awaitingLockdownConfirmation then
		awaitingLockdownConfirmation = true
		confirmationGeneration += 1
		local thisGeneration = confirmationGeneration
		(lockdownButton :: any).Text = if lockdownActive then "Confirm Disable" else "Confirm Lockdown"
		setStatus("Click the lockdown button again within 5 seconds to confirm.")
		task.delay(5, function()
			if confirmationGeneration == thisGeneration and awaitingLockdownConfirmation then
				awaitingLockdownConfirmation = false
				updateLockdownButton()
			end
		end)
		return
	end

	awaitingLockdownConfirmation = false
	confirmationGeneration += 1
	requestPending = true
	updateLockdownButton()
	kickButton.Active = false
	kickButton.AutoButtonColor = false
	setStatus("Sending lockdown request to the server...")
	securityAction:FireServer("ToggleLockdown")
	task.delay(8, function()
		if requestPending then
			requestFinished()
			setStatus("No server response was received. Check the server before retrying.")
		end
	end)
end)

kickButton.Activated:Connect(function()
	if requestPending then return end
	local targetName = string.match(targetBox.Text, "^%s*(.-)%s*$") or ""
	local reason = string.match(reasonBox.Text, "^%s*(.-)%s*$") or ""
	if targetName == "" then
		setStatus("Enter the exact Roblox username of the player.")
		return
	end
	if #targetName > 20 or string.find(targetName, "[^%w_]") then
		setStatus("Use an exact Roblox username (letters, numbers, and underscores).")
		return
	end
	if #reason > 200 then
		setStatus("The removal reason must be 200 bytes or fewer.")
		return
	end

	pendingKickTarget = targetName
	requestPending = true
	kickButton.Active = false
	kickButton.AutoButtonColor = false
	lockdownButton.Active = false
	lockdownButton.AutoButtonColor = false
	setStatus("Sending player-removal request to the server...")
	securityAction:FireServer("KickPlayer", targetName, reason)
	task.delay(8, function()
		if requestPending then
			requestFinished()
			setStatus("No server response was received. Check the server before retrying.")
		end
	end)
end)

actionResult.OnClientEvent:Connect(function(action: any, succeeded: any, message: any, serverLockdownState: any)
	if typeof(action) ~= "string" or typeof(succeeded) ~= "boolean" then return end
	if typeof(serverLockdownState) == "boolean" then
		lockdownActive = serverLockdownState
		updateLockdownButton()
	end
	local resultMessage = if typeof(message) == "string" then message else "The server returned an unknown result."
	setStatus(resultMessage)

	if action == "GetStatus" or action == "ToggleLockdown" or action == "KickPlayer" then
		if action == "KickPlayer" and succeeded and targetBox.Text == pendingKickTarget then
			targetBox.Text = ""
			reasonBox.Text = ""
		end
		requestFinished()
	end
end)

updateLockdownButton()
securityAction:FireServer("GetStatus")
print("[Tiki Tide][SecurityConsole] Client controls connected; server remains authoritative.")
