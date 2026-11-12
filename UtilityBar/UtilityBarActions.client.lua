--!strict
-- UtilityBarActions.client.lua
-- Place as a LocalScript in StarterPlayer/StarterPlayerScripts.
-- Handles independent client-side Inventory and server-authoritative Refresh Outfit actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local actionEvent = playerGui:WaitForChild("UtilityBarAction", 20)
if not actionEvent or not actionEvent:IsA("BindableEvent") then
	warn("[UtilityBar] UtilityBarAction was not found. Install UtilityBar.client.lua first.")
	return
end

local remoteFolder = ReplicatedStorage:WaitForChild("UtilityBarRemotes", 20)
local refreshRemote = if remoteFolder then remoteFolder:WaitForChild("RefreshOwnAvatar", 20) else nil
if refreshRemote and not refreshRemote:IsA("RemoteFunction") then
	warn("[UtilityBar] RefreshOwnAvatar has an invalid class; Refresh Outfit is unavailable.")
	refreshRemote = nil
end

local existingGui = playerGui:FindFirstChild("UtilityActionFeedback")
if existingGui then existingGui:Destroy() end

local feedbackGui = Instance.new("ScreenGui")
feedbackGui.Name = "UtilityActionFeedback"
feedbackGui.ResetOnSpawn = false
feedbackGui.IgnoreGuiInset = true
feedbackGui.DisplayOrder = 31
feedbackGui.Parent = playerGui

local message = Instance.new("TextLabel")
message.Name = "Message"
message.AnchorPoint = Vector2.new(0.5, 1)
message.Position = UDim2.new(0.5, 0, 1, -108)
message.Size = UDim2.new(0.86, 0, 0, 42)
message.BackgroundColor3 = Color3.fromRGB(16, 20, 29)
message.BackgroundTransparency = 0.08
message.BorderSizePixel = 0
message.Font = Enum.Font.GothamMedium
message.Text = ""
message.TextColor3 = Color3.fromRGB(242, 241, 236)
message.TextSize = 12
message.TextWrapped = true
message.TextTransparency = 1
message.Visible = false
message.Parent = feedbackGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = message

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(226, 194, 132)
stroke.Transparency = 0.48
stroke.Thickness = 1
stroke.Parent = message

local token = 0
local function showMessage(text: string)
	token += 1
	local currentToken = token
	message.Text = text
	message.Visible = true
	message.TextTransparency = 1
	message.BackgroundTransparency = 0.3
	TweenService:Create(message, TweenInfo.new(0.16), {
		TextTransparency = 0,
		BackgroundTransparency = 0.08,
	}):Play()
	task.delay(2.4, function()
		if currentToken ~= token or not message.Parent then return end
		local fade = TweenService:Create(message, TweenInfo.new(0.2), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		fade:Play()
		fade.Completed:Wait()
		if currentToken == token and message.Parent then message.Visible = false end
	end)
end

local requestPending = false
actionEvent.Event:Connect(function(actionName: string)
	if actionName == "Inventory" then
		local ok, isEnabled = pcall(function()
			return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
		end)
		if not ok then
			showMessage("Roblox inventory is unavailable right now.")
			return
		end
		local setOk, setError = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, not isEnabled)
		end)
		if not setOk then
			warn("[UtilityBar] Inventory toggle failed: " .. tostring(setError))
			showMessage("Could not toggle the Roblox inventory.")
		else
			showMessage(if isEnabled then "Inventory hidden." else "Inventory opened.")
		end
		return
	end

	if actionName ~= "RefreshOutfit" then return end
	if not refreshRemote or not refreshRemote:IsA("RemoteFunction") then
		showMessage("Avatar refresh service is unavailable.")
		return
	end
	if requestPending then
		showMessage("Avatar refresh is already in progress.")
		return
	end

	requestPending = true
	showMessage("Refreshing your Roblox avatar…")
	task.spawn(function()
		local ok, success, resultMessage = pcall(function()
			return (refreshRemote :: RemoteFunction):InvokeServer()
		end)
		requestPending = false

		if not ok then
			warn("[UtilityBar] Avatar refresh request failed: " .. tostring(success))
			showMessage("Could not contact the avatar service. Try again.")
		elseif success == true then
			showMessage(if typeof(resultMessage) == "string" then resultMessage else "Avatar refreshed.")
		else
			showMessage(if typeof(resultMessage) == "string" then resultMessage else "Avatar refresh was not completed.")
		end
	end)
end)

print("[UtilityBar] Inventory and Refresh Outfit actions connected.")
