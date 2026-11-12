--!strict
-- ToolShop.client.lua
-- Separate Tool Shop panel. Inventory equip/unequip remains in UtilityBarActions.client.lua.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local actionEvent = playerGui:WaitForChild("UtilityBarAction", 20)
if not actionEvent or not actionEvent:IsA("BindableEvent") then
	warn("[Tool Shop] UtilityBarAction is missing.")
	return
end

local remoteFolder = ReplicatedStorage:WaitForChild("UtilityBarRemotes", 30)
local shopRemote = remoteFolder and remoteFolder:WaitForChild("ToolShop", 30)
if not shopRemote or not shopRemote:IsA("RemoteFunction") then
	warn("[Tool Shop] ToolShop server remote is missing. Install ToolShop.server.lua.")
end

local gui = Instance.new("ScreenGui")
gui.Name = "UtilityToolShopGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 32
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "ToolShopPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0.88, 0, 0.72, 0)
panel.BackgroundColor3 = Color3.fromRGB(13, 16, 24)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(280, 240)
sizeConstraint.MaxSize = Vector2.new(760, 560)
sizeConstraint.Parent = panel
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 18)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(226, 194, 132)
stroke.Transparency = 0.42
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(18, 12)
title.Size = UDim2.new(1, -150, 0, 28)
title.Font = Enum.Font.GothamBlack
title.Text = "TOOL SHOP"
title.TextColor3 = Color3.fromRGB(242, 241, 236)
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local balance = Instance.new("TextLabel")
balance.BackgroundColor3 = Color3.fromRGB(35, 53, 59)
balance.Position = UDim2.new(1, -142, 0, 12)
balance.Size = UDim2.fromOffset(88, 28)
balance.Font = Enum.Font.GothamBold
balance.Text = "0 COINS"
balance.TextColor3 = Color3.fromRGB(119, 196, 203)
balance.TextSize = 10
balance.Parent = panel
local balanceCorner = Instance.new("UICorner")
balanceCorner.CornerRadius = UDim.new(0, 9)
balanceCorner.Parent = balance

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -10, 0, 10)
close.Size = UDim2.fromOffset(28, 28)
close.BackgroundColor3 = Color3.fromRGB(37, 45, 60)
close.BorderSizePixel = 0
close.Text = "×"
close.TextColor3 = Color3.fromRGB(242, 241, 236)
close.TextSize = 19
close.Font = Enum.Font.GothamBold
close.Parent = panel
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 9)
closeCorner.Parent = close

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Position = UDim2.fromOffset(18, 48)
hint.Size = UDim2.new(1, -36, 0, 34)
hint.Font = Enum.Font.GothamMedium
hint.Text = "Spend Coins on tools. New stock will appear here when configured."
hint.TextColor3 = Color3.fromRGB(157, 164, 177)
hint.TextSize = 11
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Name = "ShopItems"
list.Position = UDim2.fromOffset(14, 88)
list.Size = UDim2.new(1, -28, 1, -102)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local function makePlaceholder(index: number)
	local card = Instance.new("Frame")
	card.Name = "ComingSoon_" .. index
	card.Size = UDim2.new(1, -6, 0, 66)
	card.BackgroundColor3 = Color3.fromRGB(24, 29, 41)
	card.BorderSizePixel = 0
	card.LayoutOrder = index
	card.Parent = list
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 13)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(119, 196, 203)
	cardStroke.Transparency = 0.82
	cardStroke.Parent = card
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(14, 8)
	name.Size = UDim2.new(1, -120, 0, 22)
	name.Font = Enum.Font.GothamBold
	name.Text = "TOOL SLOT " .. string.format("%02d", index)
	name.TextColor3 = Color3.fromRGB(242, 241, 236)
	name.TextSize = 12
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = card
	local description = Instance.new("TextLabel")
	description.BackgroundTransparency = 1
	description.Position = UDim2.fromOffset(14, 31)
	description.Size = UDim2.new(1, -120, 0, 22)
	description.Font = Enum.Font.Gotham
	description.Text = "Tool details and price coming soon"
	description.TextColor3 = Color3.fromRGB(157, 164, 177)
	description.TextSize = 10
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.Parent = card
	local status = Instance.new("TextLabel")
	status.AnchorPoint = Vector2.new(1, 0.5)
	status.Position = UDim2.new(1, -12, 0.5, 0)
	status.Size = UDim2.fromOffset(92, 26)
	status.BackgroundColor3 = Color3.fromRGB(54, 48, 37)
	status.BorderSizePixel = 0
	status.Font = Enum.Font.GothamBold
	status.Text = "COMING SOON"
	status.TextColor3 = Color3.fromRGB(226, 194, 132)
	status.TextSize = 9
	status.Parent = card
	local statusCorner = Instance.new("UICorner")
	statusCorner.CornerRadius = UDim.new(0, 8)
	statusCorner.Parent = status
end

local function refresh()
	if shopRemote and shopRemote:IsA("RemoteFunction") then
		local ok, data = pcall(function()
			return shopRemote:InvokeServer("GetShop")
		end)
		if ok and typeof(data) == "table" then
			balance.Text = tostring(math.max(0, math.floor(tonumber(data.coins) or 0))) .. " COINS"
		else
			balance.Text = "COINS —"
		end
	else
		balance.Text = "COINS —"
	end
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	-- Deliberate placeholders only: no tools, prices, or purchase buttons are
	-- fabricated before the owner adds and configures real Tool assets.
	for index = 1, 3 do makePlaceholder(index) end
end

local function closePanel()
	panel.Visible = false
	playerGui:SetAttribute("UtilityToolShopOpen", false)
end
close.Activated:Connect(closePanel)
actionEvent.Event:Connect(function(actionName: string)
	if actionName ~= "ToolShop" then return end
	panel.Visible = true
	playerGui:SetAttribute("UtilityToolShopOpen", true)
	refresh()
end)
print("[Tool Shop] Placeholder catalog connected; no purchasable items configured.")
