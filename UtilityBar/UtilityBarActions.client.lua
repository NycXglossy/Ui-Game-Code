--!strict
-- UtilityBarActions.client.lua
-- Place as a LocalScript in StarterPlayer/StarterPlayerScripts.
-- Handles independent client-side Inventory and server-authoritative Refresh Outfit actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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


-- Custom inventory panel: Roblox does not expose a supported API to open
-- the built-in Backpack window, so this panel lists the player's actual Tools.
local inventoryPanel = Instance.new("Frame")
inventoryPanel.Name = "InventoryPanel"
inventoryPanel.AnchorPoint = Vector2.new(0.5, 0.5)
inventoryPanel.Position = UDim2.fromScale(0.5, 0.5)
inventoryPanel.Size = UDim2.new(0.9, 0, 0.75, 0)
inventoryPanel.BackgroundColor3 = Color3.fromRGB(15, 19, 28)
inventoryPanel.BorderSizePixel = 0
inventoryPanel.Visible = false
inventoryPanel.Parent = feedbackGui
local panelSize = Instance.new("UISizeConstraint")
panelSize.MinSize = Vector2.new(280, 260)
panelSize.MaxSize = Vector2.new(460, 520)
panelSize.Parent = inventoryPanel
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 18)
panelCorner.Parent = inventoryPanel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(226, 194, 132)
panelStroke.Transparency = 0.35
panelStroke.Thickness = 1
panelStroke.Parent = inventoryPanel

local inventoryTitle = Instance.new("TextLabel")
inventoryTitle.BackgroundTransparency = 1
inventoryTitle.Position = UDim2.fromOffset(18, 12)
inventoryTitle.Size = UDim2.new(1, -78, 0, 32)
inventoryTitle.Font = Enum.Font.GothamBold
inventoryTitle.Text = "INVENTORY"
inventoryTitle.TextColor3 = Color3.fromRGB(242, 241, 236)
inventoryTitle.TextSize = 16
inventoryTitle.TextXAlignment = Enum.TextXAlignment.Left
inventoryTitle.Parent = inventoryPanel

local closeInventory = Instance.new("TextButton")
closeInventory.Name = "Close"
closeInventory.AnchorPoint = Vector2.new(1, 0)
closeInventory.Position = UDim2.new(1, -12, 0, 12)
closeInventory.Size = UDim2.fromOffset(34, 30)
closeInventory.BackgroundColor3 = Color3.fromRGB(37, 45, 60)
closeInventory.BorderSizePixel = 0
closeInventory.Font = Enum.Font.GothamBold
closeInventory.Text = "×"
closeInventory.TextColor3 = Color3.fromRGB(242, 241, 236)
closeInventory.TextSize = 20
closeInventory.Parent = inventoryPanel
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 9)
closeCorner.Parent = closeInventory

local inventoryHint = Instance.new("TextLabel")
inventoryHint.BackgroundTransparency = 1
inventoryHint.Position = UDim2.fromOffset(18, 46)
inventoryHint.Size = UDim2.new(1, -36, 0, 22)
inventoryHint.Font = Enum.Font.Gotham
inventoryHint.Text = "Select an item to equip or unequip"
inventoryHint.TextColor3 = Color3.fromRGB(157, 164, 177)
inventoryHint.TextSize = 11
inventoryHint.TextXAlignment = Enum.TextXAlignment.Left
inventoryHint.Parent = inventoryPanel

local inventoryList = Instance.new("ScrollingFrame")
inventoryList.Name = "Items"
inventoryList.Position = UDim2.fromOffset(12, 76)
inventoryList.Size = UDim2.new(1, -24, 1, -88)
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
		empty.Text = "No tools in your inventory"
		empty.TextColor3 = Color3.fromRGB(157, 164, 177)
		empty.TextSize = 12
		empty.Parent = inventoryList
		local emptyCorner = Instance.new("UICorner")
		emptyCorner.CornerRadius = UDim.new(0, 10)
		emptyCorner.Parent = empty
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
		itemButton.AutoButtonColor = true
		itemButton.Font = Enum.Font.GothamSemibold
		itemButton.Text = (equipped and "EQUIPPED  •  " or "EQUIP  •  ") .. tool.Name
		itemButton.TextColor3 = equipped and Color3.fromRGB(226, 194, 132) or Color3.fromRGB(242, 241, 236)
		itemButton.TextSize = 12
		itemButton.Parent = inventoryList
		local itemCorner = Instance.new("UICorner")
		itemCorner.CornerRadius = UDim.new(0, 10)
		itemCorner.Parent = itemButton
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
	refreshInventory()
end
closeInventory.Activated:Connect(function() inventoryPanel.Visible = false end)

local requestPending = false
actionEvent.Event:Connect(function(actionName: string)
	if actionName == "Inventory" then
		openInventory()
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
