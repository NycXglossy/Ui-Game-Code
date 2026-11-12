--!strict
-- UtilityBarActions.client.lua
-- Place as a LocalScript in StarterPlayer/StarterPlayerScripts.
-- Handles independent client-side Inventory and server-authoritative Refresh Outfit actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local actionEvent = playerGui:WaitForChild("UtilityBarAction", 20)
if not actionEvent or not actionEvent:IsA("BindableEvent") then
	warn("[UtilityBar] UtilityBarAction was not found. Install UtilityBar.client.lua first.")
	return
end

local remoteFolder = ReplicatedStorage:WaitForChild("UtilityBarRemotes", 20)
local refreshRemote = if remoteFolder then remoteFolder:WaitForChild("RefreshOwnAvatar", 20) else nil
local extendedRemote = if remoteFolder then remoteFolder:WaitForChild("ExecuteUtility", 20) else nil
if extendedRemote and not extendedRemote:IsA("RemoteFunction") then
	warn("[UtilityBar] ExecuteUtility has an invalid class; extended utilities are unavailable.")
	extendedRemote = nil
end
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


-- Custom inventory panel: Roblox does not expose a supported API to open
-- the built-in Backpack window, so this panel lists the player's actual Tools.
local inventoryPanel = Instance.new("Frame")
inventoryPanel.Name = "InventoryPanel"
inventoryPanel.AnchorPoint = Vector2.new(0.5, 0.5)
inventoryPanel.Position = UDim2.fromScale(0.5, 0.5)
-- Scale with the available viewport on phones, tablets, laptops, and desktops.
-- A maximum size keeps the panel comfortable on large monitors; deliberately
-- avoid a minimum pixel size so compact screens are never forced off-screen.
inventoryPanel.Size = UDim2.new(0.9, 0, 0.78, 0)
inventoryPanel.BackgroundColor3 = Color3.fromRGB(13, 16, 24)
inventoryPanel.BorderSizePixel = 0
inventoryPanel.Visible = false
inventoryPanel.Parent = feedbackGui
local panelSize = Instance.new("UISizeConstraint")
panelSize.Parent = inventoryPanel

-- Match the main ClubMusic menu's exact device profiles and viewport-fit math.
-- This keeps the complete panel, including its close control, inside short laptop
-- screens and adapts again when the window is resized or a device rotates.
local inventoryScale = Instance.new("UIScale")
inventoryScale.Parent = inventoryPanel

local INVENTORY_PROFILES = {
	Desktop = { base = 1.00, refX = 1280, refY = 720, minF = 0.80, w = 0.68, h = 0.80,
		min = Vector2.new(360, 340) },
	Tablet = { base = 0.92, refX = 1024, refY = 600, minF = 0.85, w = 0.72, h = 0.80,
		min = Vector2.new(320, 280) },
	Mobile = { base = 0.90, refX = 640, refY = 340, minF = 0.90, w = 0.94, h = 0.90,
		min = Vector2.new(280, 220) },
	VR = { base = 0.90, refX = 1280, refY = 720, minF = 0.90, w = 0.60, h = 0.70,
		min = Vector2.new(320, 300) },
	Console = { base = 1.00, refX = 1280, refY = 720, minF = 1.00, w = 0.66, h = 0.76,
		min = Vector2.new(360, 320) },
}

local function getInventoryDevice(viewport: Vector2): string
	if UserInputService.VREnabled then return "VR" end
	if GuiService:IsTenFootInterface() then return "Console" end
	local touch = UserInputService.TouchEnabled
	local keyboard = UserInputService.KeyboardEnabled
	if touch and not keyboard then
		return if math.min(viewport.X, viewport.Y) >= 600 then "Tablet" else "Mobile"
	end
	if UserInputService.GamepadEnabled and not keyboard and not touch then return "Console" end
	return "Desktop"
end

local function applyInventoryLayout()
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local profile = INVENTORY_PROFILES[getInventoryDevice(viewport)]
	local fit = math.clamp(math.min(viewport.X / profile.refX, viewport.Y / profile.refY), profile.minF, 1)
	local scale = profile.base * fit
	inventoryScale.Scale = scale

	local targetWidth = math.max(1, viewport.X * profile.w / scale)
	local targetHeight = math.max(1, viewport.Y * profile.h / scale)
	panelSize.MinSize = Vector2.new(
		math.min(profile.min.X, targetWidth * 0.90),
		math.min(profile.min.Y, targetHeight * 0.90)
	)
	panelSize.MaxSize = Vector2.new(targetWidth, targetHeight)
	inventoryPanel.Size = UDim2.new(profile.w / scale, 0, profile.h / scale, 0)
end

local inventoryCameraConnection: RBXScriptConnection? = nil
local function bindInventoryCamera()
	if inventoryCameraConnection then inventoryCameraConnection:Disconnect() end
	local camera = workspace.CurrentCamera
	if camera then
		inventoryCameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyInventoryLayout)
	end
	applyInventoryLayout()
end
bindInventoryCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindInventoryCamera)
UserInputService.LastInputTypeChanged:Connect(applyInventoryLayout)
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 18)
panelCorner.Parent = inventoryPanel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(226, 194, 132)
panelStroke.Transparency = 0.42
panelStroke.Thickness = 1
panelStroke.Parent = inventoryPanel

local panelGradient = Instance.new("UIGradient")
panelGradient.Rotation = 90
panelGradient.Color = ColorSequence.new(Color3.fromRGB(27, 33, 46), Color3.fromRGB(13, 16, 24))
panelGradient.Parent = inventoryPanel

local headerAccent = Instance.new("Frame")
headerAccent.Name = "HeaderAccent"
headerAccent.Position = UDim2.fromOffset(18, 48)
headerAccent.Size = UDim2.new(0, 42, 0, 2)
headerAccent.BackgroundColor3 = Color3.fromRGB(226, 194, 132)
headerAccent.BorderSizePixel = 0
headerAccent.Parent = inventoryPanel
local accentCorner = Instance.new("UICorner")
accentCorner.CornerRadius = UDim.new(1, 0)
accentCorner.Parent = headerAccent

local inventoryTitle = Instance.new("TextLabel")
inventoryTitle.BackgroundTransparency = 1
inventoryTitle.Position = UDim2.fromOffset(18, 10)
inventoryTitle.Size = UDim2.new(1, -78, 0, 30)
inventoryTitle.Font = Enum.Font.GothamBlack
inventoryTitle.Text = "YOUR INVENTORY"
inventoryTitle.TextColor3 = Color3.fromRGB(242, 241, 236)
inventoryTitle.TextSize = 17
inventoryTitle.TextXAlignment = Enum.TextXAlignment.Left
inventoryTitle.Parent = inventoryPanel

local closeInventory = Instance.new("TextButton")
closeInventory.Name = "Close"
closeInventory.AnchorPoint = Vector2.new(1, 0)
closeInventory.Position = UDim2.new(1, -12, 0, 12)
closeInventory.Size = UDim2.fromOffset(36, 32)
closeInventory.BackgroundColor3 = Color3.fromRGB(37, 45, 60)
closeInventory.BorderSizePixel = 0
closeInventory.Font = Enum.Font.GothamBold
closeInventory.Text = "×"
closeInventory.TextColor3 = Color3.fromRGB(242, 241, 236)
closeInventory.TextSize = 20
closeInventory.Parent = inventoryPanel
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 11)
closeCorner.Parent = closeInventory
local closeStroke = Instance.new("UIStroke")
closeStroke.Color = Color3.fromRGB(226, 194, 132)
closeStroke.Transparency = 0.78
closeStroke.Thickness = 1
closeStroke.Parent = closeInventory

local inventoryHint = Instance.new("TextLabel")
inventoryHint.BackgroundTransparency = 1
inventoryHint.Position = UDim2.fromOffset(18, 54)
inventoryHint.Size = UDim2.new(1, -36, 0, 20)
inventoryHint.Font = Enum.Font.GothamMedium
inventoryHint.Text = "Select an item to equip or unequip"
inventoryHint.TextColor3 = Color3.fromRGB(157, 164, 177)
inventoryHint.TextSize = 11
inventoryHint.TextXAlignment = Enum.TextXAlignment.Left
inventoryHint.Parent = inventoryPanel

local inventoryList = Instance.new("ScrollingFrame")
inventoryList.Name = "Items"
inventoryList.Position = UDim2.fromOffset(12, 82)
inventoryList.Size = UDim2.new(1, -24, 1, -94)
inventoryList.BackgroundTransparency = 1
inventoryList.BorderSizePixel = 0
inventoryList.ScrollBarThickness = 4
inventoryList.CanvasSize = UDim2.new()
inventoryList.AutomaticCanvasSize = Enum.AutomaticSize.Y
inventoryList.Parent = inventoryPanel
local inventoryLayout = Instance.new("UIListLayout")
inventoryLayout.Padding = UDim.new(0, 6)
inventoryLayout.SortOrder = Enum.SortOrder.Name
inventoryLayout.Parent = inventoryList

local function refreshInventory()
	for _, child in ipairs(inventoryList:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	local tools: {Tool} = {}
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") then table.insert(tools, item) end
		end
	end
	if character then
		for _, item in ipairs(character:GetChildren()) do
			if item:IsA("Tool") and not table.find(tools, item) then table.insert(tools, item) end
		end
	end
	table.sort(tools, function(a, b) return string.lower(a.Name) < string.lower(b.Name) end)

	if #tools == 0 then
		local empty = Instance.new("TextLabel")
		empty.Name = "EmptyState"
		empty.Size = UDim2.new(1, -8, 0, 54)
		empty.BackgroundColor3 = Color3.fromRGB(24, 29, 41)
		empty.BorderSizePixel = 0
		empty.Font = Enum.Font.GothamMedium
		empty.Text = "YOUR INVENTORY IS EMPTY"
		empty.TextColor3 = Color3.fromRGB(157, 164, 177)
		empty.TextSize = 11
		empty.Parent = inventoryList
		local emptyCorner = Instance.new("UICorner")
		emptyCorner.CornerRadius = UDim.new(0, 13)
		emptyCorner.Parent = empty
		local emptyStroke = Instance.new("UIStroke")
		emptyStroke.Color = Color3.fromRGB(119, 196, 203)
		emptyStroke.Transparency = 0.88
		emptyStroke.Thickness = 1
		emptyStroke.Parent = empty
		return
	end

	for index, tool in ipairs(tools) do
		local equipped = character ~= nil and tool.Parent == character
		local itemButton = Instance.new("TextButton")
		itemButton.Name = "Item_" .. tostring(index)
		itemButton.LayoutOrder = index
		itemButton.Size = UDim2.new(1, -8, 0, 46)
		itemButton.BackgroundColor3 = Color3.fromRGB(24, 29, 41)
		itemButton.BorderSizePixel = 0
		itemButton.AutoButtonColor = false
		itemButton.Text = ""
		itemButton.Parent = inventoryList
		local itemCorner = Instance.new("UICorner")
		itemCorner.CornerRadius = UDim.new(0, 13)
		itemCorner.Parent = itemButton
		local itemStroke = Instance.new("UIStroke")
		itemStroke.Color = equipped and Color3.fromRGB(226, 194, 132) or Color3.fromRGB(119, 196, 203)
		itemStroke.Transparency = equipped and 0.48 or 0.84
		itemStroke.Thickness = 1
		itemStroke.Parent = itemButton

		local itemAccent = Instance.new("Frame")
		itemAccent.Name = "ItemAccent"
		itemAccent.Position = UDim2.fromOffset(10, 10)
		itemAccent.Size = UDim2.new(0, 3, 1, -20)
		itemAccent.BackgroundColor3 = equipped and Color3.fromRGB(226, 194, 132) or Color3.fromRGB(119, 196, 203)
		itemAccent.BorderSizePixel = 0
		itemAccent.Parent = itemButton
		local itemAccentCorner = Instance.new("UICorner")
		itemAccentCorner.CornerRadius = UDim.new(1, 0)
		itemAccentCorner.Parent = itemAccent

		local itemName = Instance.new("TextLabel")
		itemName.Name = "ItemName"
		itemName.BackgroundTransparency = 1
		itemName.Position = UDim2.fromOffset(23, 0)
		itemName.Size = UDim2.new(1, -132, 1, 0)
		itemName.Font = Enum.Font.GothamSemibold
		itemName.Text = tool.Name
		itemName.TextColor3 = Color3.fromRGB(242, 241, 236)
		itemName.TextSize = 13
		itemName.TextTruncate = Enum.TextTruncate.AtEnd
		itemName.TextXAlignment = Enum.TextXAlignment.Left
		itemName.Parent = itemButton

		local itemStatus = Instance.new("TextLabel")
		itemStatus.Name = "ItemStatus"
		itemStatus.AnchorPoint = Vector2.new(1, 0.5)
		itemStatus.Position = UDim2.new(1, -12, 0.5, 0)
		itemStatus.Size = UDim2.fromOffset(88, 24)
		itemStatus.BackgroundColor3 = equipped and Color3.fromRGB(74, 61, 39) or Color3.fromRGB(35, 53, 59)
		itemStatus.BorderSizePixel = 0
		itemStatus.Font = Enum.Font.GothamBold
		itemStatus.Text = equipped and "EQUIPPED" or "EQUIP"
		itemStatus.TextColor3 = equipped and Color3.fromRGB(226, 194, 132) or Color3.fromRGB(119, 196, 203)
		itemStatus.TextSize = 9
		itemStatus.Parent = itemButton
		local statusCorner = Instance.new("UICorner")
		statusCorner.CornerRadius = UDim.new(0, 8)
		statusCorner.Parent = itemStatus
		itemButton.Activated:Connect(function()
			local currentCharacter = player.Character
			local humanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
			if not humanoid or not tool.Parent then
				showMessage("That item is no longer available.")
				refreshInventory()
				return
			end
			if tool.Parent == currentCharacter then
				humanoid:UnequipTools()
			else
				humanoid:EquipTool(tool)
			end
			task.defer(refreshInventory)
		end)
	end
end

local function openInventory()
	inventoryPanel.Visible = true
	playerGui:SetAttribute("UtilityInventoryOpen", true)
	refreshInventory()
end
local function closeInventoryPanel()
	inventoryPanel.Visible = false
	playerGui:SetAttribute("UtilityInventoryOpen", false)
end
closeInventory.Activated:Connect(closeInventoryPanel)

local requestPending = false
actionEvent.Event:Connect(function(actionName: string)
	if actionName == "Inventory" then
		openInventory()
		return
	end

	if actionName == "Mount" or actionName == "Size" or actionName == "Clone" or actionName == "Aura" then
		if not extendedRemote or not extendedRemote:IsA("RemoteFunction") then
			showMessage("Utility service is unavailable. Install UtilityBarExtendedActions.server.lua.")
			return
		end
		if requestPending then
			showMessage("A utility request is already in progress.")
			return
		end
		requestPending = true
		showMessage(actionName .. " request…")
		task.spawn(function()
			local ok, success, resultMessage = pcall(function()
				return (extendedRemote :: RemoteFunction):InvokeServer(actionName)
			end)
			requestPending = false
			if not ok then
				warn("[UtilityBar] " .. actionName .. " request failed: " .. tostring(success))
				showMessage("Could not contact the utility service. Try again.")
			else
				showMessage(if typeof(resultMessage) == "string" then resultMessage
					else (if success == true then actionName .. " completed." else actionName .. " was not completed."))
			end
		end)
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

print("[UtilityBar] Custom Inventory and Refresh Outfit actions connected.")
