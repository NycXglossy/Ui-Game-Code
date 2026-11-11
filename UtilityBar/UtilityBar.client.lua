--!strict
-- UtilityBar.client.lua
-- Separate non-music utility launcher. Place in StarterPlayer/StarterPlayerScripts.
-- Utility actions are published through PlayerGui.UtilityBarAction for independent
-- client modules to consume; this script does not implement those separate systems.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("UtilityBarGui")
if oldGui then oldGui:Destroy() end

local actionEvent = playerGui:FindFirstChild("UtilityBarAction")
if actionEvent and not actionEvent:IsA("BindableEvent") then
	actionEvent:Destroy()
	actionEvent = nil
end
if not actionEvent then
	actionEvent = Instance.new("BindableEvent")
	actionEvent.Name = "UtilityBarAction"
	actionEvent.Parent = playerGui
end
local utilityAction = actionEvent :: BindableEvent

local COLORS = {
	background = Color3.fromRGB(13, 16, 24),
	surface = Color3.fromRGB(24, 29, 41),
	surfaceHover = Color3.fromRGB(37, 45, 60),
	gold = Color3.fromRGB(226, 194, 132),
	cyan = Color3.fromRGB(119, 196, 203),
	text = Color3.fromRGB(242, 241, 236),
	muted = Color3.fromRGB(157, 164, 177),
}

local function make(className: string, props: {[string]: any}, parent: Instance): Instance
	local object = Instance.new(className)
	for key, value in pairs(props) do
		(object :: any)[key] = value
	end
	object.Parent = parent
	return object
end

local function round(object: Instance, radius: number)
	make("UICorner", {CornerRadius = UDim.new(0, radius)}, object)
end

local gui = make("ScreenGui", {
	Name = "UtilityBarGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	DisplayOrder = 28,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui) :: ScreenGui

local shell = make("Frame", {
	Name = "UtilityBar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(760, 76),
	BackgroundColor3 = COLORS.background,
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
}, gui) :: Frame
round(shell, 22)
make("UISizeConstraint", {MinSize = Vector2.new(280, 68), MaxSize = Vector2.new(760, 76)}, shell)
make("UIStroke", {Color = COLORS.gold, Transparency = 0.46, Thickness = 1.2}, shell)
make("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(28, 34, 47), COLORS.background),
}, shell)

local rail = make("ScrollingFrame", {
	Name = "ButtonRail",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -16, 1, -12),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 0,
	ScrollingDirection = Enum.ScrollingDirection.X,
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	Selectable = false,
	Active = true,
	ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	ScrollingEnabled = true,
}, shell) :: ScrollingFrame

local layout = make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 7),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, rail) :: UIListLayout
make("UIPadding", {PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2)}, rail)

local toast = make("TextLabel", {
	Name = "UtilityToast",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0, -8),
	Size = UDim2.new(1, -20, 0, 22),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = COLORS.muted,
	TextSize = 10,
	Font = Enum.Font.GothamMedium,
	TextTransparency = 1,
	ZIndex = 4,
}, shell) :: TextLabel
local toastToken = 0
local function showToast(message: string)
	toastToken += 1
	local token = toastToken
	toast.Text = message
	TweenService:Create(toast, TweenInfo.new(0.14), {TextTransparency = 0}):Play()
	task.delay(1.8, function()
		if token ~= toastToken or not toast.Parent then return end
		TweenService:Create(toast, TweenInfo.new(0.22), {TextTransparency = 1}):Play()
	end)
end

-- Native Roblox GUI iconography: crisp layered shapes, no emoji or text glyphs.
local function buildUtilityIcon(parent: Instance, kind: string, color: Color3): Frame
	local root = make("Frame", {Name="PremiumIcon_"..kind, AnchorPoint=Vector2.new(0.5,0), Position=UDim2.new(0.5,0,0,5), Size=UDim2.fromOffset(27,25), BackgroundTransparency=1, BorderSizePixel=0}, parent) :: Frame
	local function part(name: string, x: number, y: number, w: number, h: number, rotation: number?)
		local shape = make("Frame", {Name=name, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(x,y), Size=UDim2.fromScale(w,h), Rotation=rotation or 0, BackgroundColor3=color, BorderSizePixel=0}, root) :: Frame
		round(shape, 3)
		return shape
	end
	local function outline(name: string, x: number, y: number, w: number, h: number)
		local shape = make("Frame", {Name=name, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(x,y), Size=UDim2.fromScale(w,h), BackgroundTransparency=1, BorderSizePixel=0}, root) :: Frame
		round(shape, 5)
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 2
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = shape
		return shape
	end
	if kind == "RefreshOutfit" then
		outline("RefreshRing",.48,.52,.68,.72)
		part("ArrowTipA",.75,.18,.12,.34,42)
		part("ArrowTipB",.85,.31,.12,.34,-48)
	elseif kind == "SultanSettings" then
		part("CrownBase",.5,.77,.72,.12,0)
		part("CrownLeft",.25,.47,.12,.48,-25)
		part("CrownCenter",.5,.35,.12,.58,0)
		part("CrownRight",.75,.47,.12,.48,25)
		part("CrownBand",.5,.64,.66,.10,0)
	elseif kind == "Mount" then
		part("HorseNeck",.60,.42,.25,.64,28)
		part("HorseHead",.70,.23,.34,.30,-12)
		part("HorseMuzzle",.84,.36,.20,.14,0)
		part("HorseBody",.38,.70,.54,.22,0)
		part("HorseEar",.57,.08,.10,.25,-18)
		part("HorseLegA",.25,.88,.09,.27,5)
		part("HorseLegB",.48,.88,.09,.27,-5)
	elseif kind == "Size" then
		part("SizeSpine",.5,.5,.09,.70,0)
		part("UpLeft",.31,.24,.10,.34,-45)
		part("UpRight",.69,.24,.10,.34,45)
		part("DownLeft",.31,.76,.10,.34,45)
		part("DownRight",.69,.76,.10,.34,-45)
	elseif kind == "Clone" then
		outline("CloneBack",.40,.43,.55,.62)
		outline("CloneFront",.61,.60,.55,.62)
	elseif kind == "Aura" then
		part("AuraVertical",.5,.5,.11,.92,0)
		part("AuraHorizontal",.5,.5,.11,.92,90)
		part("AuraDiagonalA",.5,.5,.09,.74,45)
		part("AuraDiagonalB",.5,.5,.09,.74,-45)
		part("AuraCore",.5,.5,.23,.23,0)
	elseif kind == "Inventory" then
		outline("BagBody",.5,.58,.72,.62)
		outline("BagFlap",.5,.29,.42,.26)
		part("BagHandle",.5,.08,.28,.10,0)
	end
	return root
end

local definitions = {
	{key = "RefreshOutfit", label = "Refresh", tint = COLORS.cyan},
	{key = "SultanSettings", label = "Sultan", tint = COLORS.gold},
	{key = "Mount", label = "Mount", tint = COLORS.cyan},
	{key = "Size", label = "Size", tint = COLORS.gold},
	{key = "Clone", label = "Clone", tint = COLORS.cyan},
	{key = "Aura", label = "Aura", tint = COLORS.gold},
	{key = "Inventory", label = "Inventory", tint = COLORS.cyan},
}

local buttons: {TextButton} = {}
for index, definition in ipairs(definitions) do
	local button = make("TextButton", {
		Name = definition.key .. "Button",
		LayoutOrder = index,
		Size = UDim2.fromOffset(82, 58),
		BackgroundColor3 = COLORS.surface,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Selectable = true,
		Active = true,
	}, rail) :: TextButton
	round(button, 15)
	make("UIStroke", {Color = definition.tint, Transparency = 0.72, Thickness = 1}, button)
	make("UIGradient", {Rotation = 90, Color = ColorSequence.new(COLORS.surfaceHover, COLORS.surface)}, button)
	local iconTile = make("Frame", {
		Name = "IconTile", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(36, 31),
		BackgroundColor3 = definition.tint, BackgroundTransparency = 0.91, BorderSizePixel = 0,
	}, button)
	round(iconTile, 10)
	make("UIStroke", {Color = definition.tint, Transparency = 0.88, Thickness = 1}, iconTile)
	buildUtilityIcon(button, definition.key, definition.tint)
	local label = make("TextLabel", {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -4, 0, 17),
		BackgroundTransparency = 1,
		Text = definition.label,
		TextColor3 = COLORS.text,
		TextSize = 9,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = Enum.Font.GothamBold,
	}, button)
	local focus = make("UIStroke", {Name = "ControllerFocus", Color = COLORS.gold, Thickness = 2, Transparency = 1}, button) :: UIStroke
	button.SelectionGained:Connect(function()
		focus.Transparency = 0
		local viewLeft = rail.AbsolutePosition.X
		local viewRight = viewLeft + rail.AbsoluteSize.X
		local itemLeft = button.AbsolutePosition.X
		local itemRight = itemLeft + button.AbsoluteSize.X
		if itemLeft < viewLeft then
			rail.CanvasPosition = Vector2.new(math.max(0, rail.CanvasPosition.X - (viewLeft - itemLeft)), 0)
		elseif itemRight > viewRight then
			rail.CanvasPosition = Vector2.new(rail.CanvasPosition.X + (itemRight - viewRight), 0)
		end
	end)
	button.SelectionLost:Connect(function() focus.Transparency = 1 end)
	button.MouseEnter:Connect(function()
		if UserInputService:GetLastInputType() == Enum.UserInputType.MouseMovement then
			TweenService:Create(button, TweenInfo.new(0.12), {BackgroundColor3 = COLORS.surfaceHover}):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), {BackgroundColor3 = COLORS.surface}):Play()
	end)
	button.Activated:Connect(function()
		if definition.key == "SultanSettings" then
			if player:GetAttribute("IsTikiTideSultan") ~= true then
				showToast("Sultan access is required.")
				return
			end
			local current = tonumber(playerGui:GetAttribute("SultanSettingsOpenRequest")) or 0
			playerGui:SetAttribute("SultanSettingsOpenRequest", current + 1)
			return
		end
		utilityAction:Fire(definition.key)
		showToast(definition.label .. " utility requested")
	end)
	table.insert(buttons, button)
end

local function updateSizing()
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(800, 600)
	local compactTouch = UserInputService.TouchEnabled and viewport.X < 900
	local widthScale = if compactTouch then 0.88 else (if viewport.X < 420 then 0.98 else 0.94)
	local width = math.max(280, math.min(760, math.floor(viewport.X * widthScale)))
	local shortScreen = viewport.Y < 460
	local veryNarrow = viewport.X < 360
	local narrow = viewport.X < 560
	local tablet = viewport.X >= 560 and viewport.X < 900

	-- On touch devices keep the rail compact and lift it above the default
	-- thumb-control zone so it does not sit over the joystick or jump button.
	local buttonWidth = if compactTouch then (if veryNarrow then 40 else 44) else (if veryNarrow then 52 else (if narrow then 58 else (if tablet then 70 else 82)))
	local buttonHeight = if compactTouch then (if shortScreen then 38 else 42) else (if shortScreen then 46 else (if narrow then 52 else 58))
	local gap = if compactTouch then 3 else (if veryNarrow then 4 else (if narrow then 5 else 7))
	local shellHeight = if compactTouch then (if shortScreen then 46 else 50) else (if shortScreen then 58 else (if narrow then 66 else 76))

	for _, button in ipairs(buttons) do
		button.Size = UDim2.fromOffset(buttonWidth, buttonHeight)
		local iconTile = button:FindFirstChild("IconTile")
		if iconTile and iconTile:IsA("Frame") then
			iconTile.Size = UDim2.fromOffset(if compactTouch then 27 else (if veryNarrow then 31 else 36), if compactTouch then 25 else (if shortScreen then 27 else 31))
		end
		local icon = button:FindFirstChild("PremiumIcon_" .. button.Name:gsub("Button", ""))
		if icon and icon:IsA("Frame") then
			icon.Position = UDim2.new(0.5, 0, 0, if compactTouch then 2 else (if shortScreen then 3 else 5))
			icon.Size = UDim2.fromOffset(if compactTouch then 21 else (if veryNarrow then 23 else 27), if compactTouch then 20 else (if shortScreen then 21 else 25))
		end
		local label = button:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Position = UDim2.new(0.5, 0, 1, -3)
			label.Size = UDim2.new(1, -3, 0, if compactTouch then 11 else (if shortScreen then 14 else 16))
			label.TextSize = if compactTouch then 7 else (if veryNarrow then 8 else (if narrow then 9 else 10))
		end
	end

	layout.Padding = UDim.new(0, gap)
	shell.Size = UDim2.fromOffset(width, shellHeight)

	-- Respect the device's bottom safe area (home indicator / system inset).
	local _, bottomInset = GuiService:GetGuiInset()
	local touchLift = if compactTouch then (if shortScreen then 108 else 148) else 8
	local bottomOffset = math.max(touchLift, bottomInset.Y + 8)
	shell.Position = UDim2.new(0.5, 0, 1, -bottomOffset)

	-- Calculate from the target width, not AbsoluteSize, which may still
	-- contain the previous frame's dimensions immediately after a resize.
	local availableWidth = math.max(0, width - 16)
	local totalWidth = #buttons * buttonWidth + (#buttons - 1) * gap + 4
	if totalWidth <= availableWidth then
		rail.CanvasPosition = Vector2.zero
		rail.ScrollingEnabled = false
	else
		rail.ScrollingEnabled = true
	end
end

local function updateVisibility()
	local expanded = playerGui:GetAttribute("ClubMusicMenuExpanded") == true
	local sultanOpen = playerGui:GetAttribute("SultanSettingsOpen") == true
	local visible = not expanded and not sultanOpen
	shell.Visible = visible
	playerGui:SetAttribute("UtilityBarVisible", visible)
	if not visible then
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(gui) then GuiService.SelectedObject = nil end
	end
end

local function wireNavigation()
	for index, button in ipairs(buttons) do
		button.NextSelectionLeft = buttons[((index - 2) % #buttons) + 1]
		button.NextSelectionRight = buttons[(index % #buttons) + 1]
	end
end
wireNavigation()

playerGui:GetAttributeChangedSignal("ClubMusicMenuExpanded"):Connect(updateVisibility)
playerGui:GetAttributeChangedSignal("SultanSettingsOpen"):Connect(updateVisibility)
-- The Sultan entry stays in the seven-button layout; its activation is
-- entitlement-checked before the panel receives an open request.

local viewportConnection: RBXScriptConnection? = nil
local function bindViewport()
	if viewportConnection then viewportConnection:Disconnect(); viewportConnection = nil end
	local camera = workspace.CurrentCamera
	if camera then viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateSizing) end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindViewport()
	updateSizing()
end)
bindViewport()
updateSizing()
updateVisibility()

UserInputService.LastInputTypeChanged:Connect(function(inputType)
	local isGamepad = inputType == Enum.UserInputType.Gamepad1
		or inputType == Enum.UserInputType.Gamepad2
		or inputType == Enum.UserInputType.Gamepad3
		or inputType == Enum.UserInputType.Gamepad4
		or inputType == Enum.UserInputType.Gamepad5
		or inputType == Enum.UserInputType.Gamepad6
		or inputType == Enum.UserInputType.Gamepad7
		or inputType == Enum.UserInputType.Gamepad8
	if isGamepad and shell.Visible and not GuiService.SelectedObject then
		GuiService.SelectedObject = buttons[1]
	end
end)

gui.Destroying:Connect(function()
	if viewportConnection then viewportConnection:Disconnect(); viewportConnection = nil end
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end)

print("[Utility Bar] Separate seven-action launcher loaded.")
