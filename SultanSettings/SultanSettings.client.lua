--!strict
-- SultanSettings.client.lua
-- Place in StarterPlayer/StarterPlayerScripts.
-- Separate settings surface; ClubMusic's existing Title Tag tab remains the title editor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("SultanSettingsRemotes", 20)
if not remotes then
	warn("[Sultan Settings] Server remotes were not found.")
	return
end
local requestObject = remotes:WaitForChild("Request", 10)
local broadcastObject = remotes:WaitForChild("Broadcast", 10)
if not requestObject or not requestObject:IsA("RemoteFunction") then
	warn("[Sultan Settings] Request RemoteFunction is missing or invalid.")
	return
end
if not broadcastObject or not broadcastObject:IsA("RemoteEvent") then
	warn("[Sultan Settings] Broadcast RemoteEvent is missing or invalid.")
	return
end
local request = requestObject :: RemoteFunction
local broadcast = broadcastObject :: RemoteEvent

local old = playerGui:FindFirstChild("SultanSettingsGui")
if old then old:Destroy() end

-- Match the ClubMusic full-screen palette for a unified premium surface.
local COLORS = {
	background = Color3.fromRGB(13, 16, 24),
	card = Color3.fromRGB(21, 25, 37),
	card2 = Color3.fromRGB(31, 37, 52),
	accent = Color3.fromRGB(226, 194, 132),
	cyan = Color3.fromRGB(119, 196, 203),
	text = Color3.fromRGB(242, 241, 236),
	muted = Color3.fromRGB(157, 164, 177),
	red = Color3.fromRGB(218, 104, 112),
	green = Color3.fromRGB(94, 184, 139),
	magenta = Color3.fromRGB(224, 112, 151),
}

local function make(className: string, props: {[string]: any}, parent: Instance): Instance
	local object = Instance.new(className)
	for key, value in pairs(props) do
		(object :: any)[key] = value
	end
	object.Parent = parent
	return object
end

local function rounded(instance: Instance, radius: number)
	make("UICorner", {CornerRadius = UDim.new(0, radius)}, instance)
end

local function invoke(action: string, payload: {[string]: any}?)
	local ok, result = pcall(function()
		return request:InvokeServer(action, payload or {})
	end)
	if not ok or typeof(result) ~= "table" then
		return {ok = false, message = "Settings service is unavailable."}
	end
	return result
end

local gui = make("ScreenGui", {
	Name = "SultanSettingsGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	DisplayOrder = 35,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui) :: ScreenGui

local toggle = make("TextButton", {
	Name = "SultanSettingsToggle",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 90),
	Size = UDim2.fromOffset(116, 34),
	BackgroundColor3 = COLORS.card,
	Text = "SULTAN",
	TextColor3 = COLORS.text,
	TextSize = 11,
	Font = Enum.Font.GothamBold,
	AutoButtonColor = true,
	Visible = false,
}, gui) :: TextButton
rounded(toggle, 12)
make("UIStroke", {Color = COLORS.accent, Transparency = 0.28, Thickness = 1.4}, toggle)
make("UIGradient", {Rotation = 90, Color = ColorSequence.new(COLORS.card2, COLORS.card)}, toggle)
-- Native equalizer mark: no emoji or special-font glyph dependency.
local toggleMark = make("Frame", {
	Name = "SultanMark", Position = UDim2.fromOffset(11, 9),
	Size = UDim2.fromOffset(17, 16), BackgroundTransparency = 1,
}, toggle)
for index, height in ipairs({8, 14, 10}) do
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new((index - 0.5) / 3, 0, 1, 0),
		Size = UDim2.fromOffset(3, height),
		BackgroundColor3 = COLORS.accent,
		BorderSizePixel = 0,
	}, toggleMark)
end
toggle.TextXAlignment = Enum.TextXAlignment.Right
toggle.TextYAlignment = Enum.TextYAlignment.Center
toggle.TextSize = 10
toggle.Size = UDim2.fromOffset(116, 36)

local shade = make("TextButton", {
	Name = "Shade",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	Text = "",
	Visible = false,
	AutoButtonColor = false,
}, gui) :: TextButton
-- Keep the Sultan Settings shadow/backdrop fully transparent.
shade.BackgroundTransparency = 1

local panel = make("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0.88, 0, 0.82, 0),
	BackgroundColor3 = COLORS.background,
	BorderSizePixel = 0,
	Visible = false,
}, gui) :: Frame
-- Scale with the available viewport while keeping a usable minimum and
-- preventing the panel from becoming oversized on large desktop displays.
panel.Size = UDim2.new(0.92, 0, 0.86, 0)
panel.ClipsDescendants = true
rounded(panel, 20)
make("UISizeConstraint", {
	MinSize = Vector2.new(260, 340),
	MaxSize = Vector2.new(760, 720),
}, panel)
make("UIStroke", {Color = COLORS.accent, Transparency = 0.28, Thickness = 1.5}, panel)
make("UIGradient", {Rotation = 90, Color = ColorSequence.new(COLORS.background, COLORS.card)}, panel)

local header = make("Frame", {
	Name = "Header",
	Position = UDim2.fromOffset(1, 1),
	Size = UDim2.new(1, -2, 0, 58),
	BackgroundColor3 = COLORS.card,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, panel)
-- Inset the header slightly inside the panel stroke and use a matching radius.
-- The lower fill keeps the transition into the content area perfectly straight.
rounded(header, 19)
make("UIStroke", {
	Color = COLORS.accent,
	Transparency = 0.88,
	Thickness = 1,
}, header)
make("Frame", {
	Name = "HeaderLowerFill",
	Position = UDim2.new(0, 0, 1, -19),
	Size = UDim2.new(1, 0, 0, 19),
	BackgroundColor3 = COLORS.card,
	BorderSizePixel = 0,
}, header)
-- Recalculate scale when the device rotates or the viewport changes.
local function fitPanelToViewport()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local viewport = camera.ViewportSize
	local widthScale = if viewport.X < 520 then 0.94 else 0.90
	local heightScale = if viewport.Y < 520 then 0.90 else 0.84
	panel.Size = UDim2.new(widthScale, 0, heightScale, 0)
	-- Keep the launcher comfortably inside narrow device safe areas.
	toggle.Position = UDim2.new(1, if viewport.X < 520 then -10 else -18, 0, if viewport.Y < 520 then 64 else 90)
end

fitPanelToViewport()
local viewportConnection: RBXScriptConnection? = nil
local function bindViewport()
	if viewportConnection then viewportConnection:Disconnect(); viewportConnection = nil end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanelToViewport)
	end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindViewport()
	fitPanelToViewport()
end)
bindViewport()

local title = make("TextLabel", {
	Position = UDim2.fromOffset(18, 8),
	Size = UDim2.new(1, -80, 0, 22),
	BackgroundTransparency = 1,
	Text = "SULTAN SETTINGS",
	TextColor3 = COLORS.accent,
	TextSize = 16,
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)
make("TextLabel", {
	Position = UDim2.fromOffset(19, 31),
	Size = UDim2.new(1, -90, 0, 16),
	BackgroundTransparency = 1,
	Text = "PERSONAL CONTROLS  |  PLAYER ACCESS  |  MESSAGES",
	TextColor3 = COLORS.muted,
	TextSize = 9,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)
local close = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(32, 32),
	BackgroundColor3 = COLORS.card2,
	Text = "X",
	TextColor3 = COLORS.text,
	TextSize = 20,
	Font = Enum.Font.GothamBold,
}, header) :: TextButton
rounded(close, 10)

local tabBar = make("Frame", {
	Position = UDim2.fromOffset(12, 68),
	Size = UDim2.new(1, -24, 0, 38),
	BackgroundTransparency = 1,
}, panel)
local content = make("ScrollingFrame", {
	Name = "SettingsContent",
	Position = UDim2.fromOffset(12, 114),
	Size = UDim2.new(1, -24, 1, -126),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = COLORS.accent,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel) :: ScrollingFrame
make("UIListLayout", {Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder}, content)
make("UIPadding", {PaddingBottom = UDim.new(0, 12)}, content)

local state: {[string]: any} = {}
local activeTab = "Settings"
local currentRoster: {any} = {}
local render: () -> ()

local function clearContent()
	for _, child in ipairs(content:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then child:Destroy() end
	end
	content.CanvasPosition = Vector2.zero
end

local function card(height: number): Frame
	local frame = make("Frame", {
		Size = UDim2.new(1, -4, 0, height),
		BackgroundColor3 = COLORS.card,
		BorderSizePixel = 0,
	}, content) :: Frame
	rounded(frame, 12)
	make("UIStroke", {Color = COLORS.accent, Transparency = 0.86, Thickness = 1}, frame)
	return frame
end

local function label(parent: Instance, text: string, pos: UDim2, size: UDim2, color: Color3?, fontSize: number?)
	return make("TextLabel", {
		Position = pos, Size = size, BackgroundTransparency = 1,
		Text = text, TextColor3 = color or COLORS.text,
		TextSize = fontSize or 11, Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
	}, parent)
end

local function button(parent: Instance, text: string, pos: UDim2, size: UDim2, callback: () -> (), tint: Color3?)
	local b = make("TextButton", {
		Position = pos, Size = size, BackgroundColor3 = tint or COLORS.card2,
		Text = text, TextColor3 = COLORS.text, TextSize = 10,
		Font = Enum.Font.GothamBold, AutoButtonColor = true,
	}, parent) :: TextButton
	rounded(b, 9)
	make("UIStroke", {Color = tint or COLORS.accent, Transparency = 0.78, Thickness = 1}, b)
	b.Activated:Connect(callback)
	return b
end

local function input(parent: Instance, placeholder: string, pos: UDim2, size: UDim2, initial: string?)
	local box = make("TextBox", {
		Position = pos, Size = size, BackgroundColor3 = COLORS.card2,
		Text = initial or "", PlaceholderText = placeholder,
		PlaceholderColor3 = COLORS.muted, TextColor3 = COLORS.text,
		ClearTextOnFocus = false, TextSize = 11,
		Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
	}, parent) :: TextBox
	rounded(box, 8)
	return box
end

local function notify(message: string, success: boolean?)
	local toast = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(0.8, 0, 0, 36),
		BackgroundColor3 = COLORS.card2,
		Text = message,
		TextColor3 = if success then COLORS.green else COLORS.text,
		TextSize = 10,
		Font = Enum.Font.GothamBold,
		TextWrapped = true,
		ZIndex = 20,
	}, gui) :: TextLabel
	rounded(toast, 10)
	task.delay(3, function()
		if toast.Parent then toast:Destroy() end
	end)
end

local function refreshState()
	local result = invoke("GetSnapshot")
	if not result.ok then
		notify(result.message or "Could not load settings.")
		return false
	end
	state = result.data or {}
	currentRoster = if typeof(state.players) == "table" then state.players else {}
	return true
end

local function refreshTabs()
	for _, child in ipairs(tabBar:GetChildren()) do child:Destroy() end
	local tabs = {"Settings", "Players", "Message"}
	for index, name in ipairs(tabs) do
		local b = make("TextButton", {
			Position = UDim2.new((index - 1) / 3, 4, 0, 0),
			Size = UDim2.new(1 / 3, -8, 1, 0),
			BackgroundColor3 = if activeTab == name then COLORS.accent else COLORS.card,
			Text = string.upper(name),
			TextColor3 = if activeTab == name then COLORS.background else COLORS.text,
			TextSize = 10,
			Font = Enum.Font.GothamBold,
		}, tabBar) :: TextButton
		rounded(b, 9)
		make("UIStroke", {Color = if activeTab == name then COLORS.accent else COLORS.card2, Transparency = if activeTab == name then 0.2 else 0.8, Thickness = 1}, b)
		b.Activated:Connect(function()
			activeTab = name
			render()
		end)
	end
end

local function renderSettings()
	label(content, "MOVEMENT", UDim2.fromOffset(4, 0), UDim2.new(1, -8, 0, 22), COLORS.accent, 12)
	local movement = card(174)
	label(movement, "WALK SPEED", UDim2.fromOffset(14, 10), UDim2.new(0.45, 0, 0, 20), COLORS.muted, 9)
	local speedBox = input(movement, "20-100", UDim2.new(0, 14, 0, 34), UDim2.new(0.42, -8, 0, 34), tostring(state.walkSpeed or 20))
	label(movement, "JUMP POWER", UDim2.new(0.52, 0, 0, 10), UDim2.new(0.42, 0, 0, 20), COLORS.muted, 9)
	local jumpBox = input(movement, "80-300", UDim2.new(0.52, 0, 0, 34), UDim2.new(0.42, -8, 0, 34), tostring(state.jumpPower or 80))
	button(movement, "APPLY MOVEMENT", UDim2.fromOffset(14, 82), UDim2.new(1, -28, 0, 30), function()
		local result = invoke("SetMovement", {walkSpeed = tonumber(speedBox.Text), jumpPower = tonumber(jumpBox.Text)})
		notify(result.message or "Movement update failed.", result.ok)
		if result.ok and result.data then state = result.data end
	end, COLORS.accent)
	label(movement, "Speed 20-100  |  Jump power 80-300", UDim2.fromOffset(14, 124), UDim2.new(1, -28, 0, 18), COLORS.muted, 9)

	local gravity = card(112)
	label(gravity, "SERVER GRAVITY", UDim2.fromOffset(14, 9), UDim2.new(0.55, 0, 0, 18), COLORS.accent, 10)
	local gravityBox = input(gravity, "20-192.62", UDim2.fromOffset(14, 36), UDim2.new(0.48, -8, 0, 32), string.format("%.2f", math.clamp(tonumber(state.gravity) or 192.62, 20, 192.62)))
	local gravityButton = button(gravity, if state.canSetGravity then "SET GRAVITY" else "ADMIN ONLY", UDim2.new(0.52, 0, 0, 36), UDim2.new(0.44, -8, 0, 32), function()
		if state.canSetGravity ~= true then
			notify("Server gravity requires administrator configuration permission.")
			return
		end
		local result = invoke("SetGravity", {gravity = tonumber(gravityBox.Text)})
		notify(result.message or "Gravity update failed.", result.ok)
		if result.ok and result.data then state = result.data end
	end, COLORS.cyan)
	if state.canSetGravity ~= true then
		gravityButton.AutoButtonColor = false
		gravityButton.BackgroundColor3 = COLORS.card2
	end
	label(gravity, "Changes affect the entire server and require administrator configuration access.", UDim2.fromOffset(14, 76), UDim2.new(1, -28, 0, 28), COLORS.muted, 8)

	local afk = card(158)
	label(afk, "AFK MODE", UDim2.fromOffset(14, 9), UDim2.new(1, -28, 0, 18), COLORS.accent, 10)
	local afkMessage = input(afk, "Your AFK message", UDim2.fromOffset(14, 36), UDim2.new(1, -28, 0, 32), tostring(state.afkMessage or ""))
	button(afk, if state.afk then "TURN AFK OFF" else "TURN AFK ON", UDim2.fromOffset(14, 80), UDim2.new(1, -28, 0, 30), function()
		local result = invoke("SetAFK", {enabled = not state.afk, message = afkMessage.Text})
		notify(result.message or "AFK update failed.", result.ok)
		if result.ok and result.data then state = result.data; render() end
	end, if state.afk then COLORS.red else COLORS.green)
	label(afk, "AFK status and filtered message are replicated to other players.", UDim2.fromOffset(14, 120), UDim2.new(1, -28, 0, 20), COLORS.muted, 8)

	local teleport = card(92)
	label(teleport, "TELEPORT PERMISSIONS", UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 18), COLORS.accent, 10)
	button(teleport, if state.allowTeleport then "DISABLE TELEPORT TO ME" else "ALLOW TELEPORT TO ME", UDim2.fromOffset(14, 34), UDim2.new(1, -28, 0, 30), function()
		local result = invoke("SetTeleportAllowed", {enabled = not state.allowTeleport})
		notify(result.message or "Permission update failed.", result.ok)
		if result.ok and result.data then state = result.data; render() end
	end, COLORS.cyan)

	local note = card(58)
	label(note, "NAME TAGS", UDim2.fromOffset(14, 7), UDim2.new(1, -28, 0, 18), COLORS.accent, 10)
	label(note, "Custom fonts, effects, title slots and overhead display remain in ClubMusic in Title Tag.", UDim2.fromOffset(14, 26), UDim2.new(1, -28, 0, 24), COLORS.muted, 8)
end

local function renderPlayers()
	label(content, "PLAYER TELEPORT", UDim2.fromOffset(4, 0), UDim2.new(1, -8, 0, 22), COLORS.accent, 12)
	local info = card(54)
	label(info, 'Choose a player who has enabled "Allow teleport to me".', UDim2.fromOffset(14, 7), UDim2.new(1, -28, 0, 38), COLORS.muted, 9)
	local searchCard = card(48)
	local search = input(searchCard, "Search player or username", UDim2.fromOffset(10, 8), UDim2.new(1, -20, 0, 32), "")
	local list = card(math.max(90, #currentRoster * 58 + 12))
	local rows = {}
	for _, entry in ipairs(currentRoster) do
		if entry.userId ~= player.UserId then
		local row = make("Frame", {
			Position = UDim2.fromOffset(8, 8 + (#rows * 54)),
			Size = UDim2.new(1, -16, 0, 48),
			BackgroundColor3 = COLORS.card2,
			BorderSizePixel = 0,
		}, list) :: Frame
		rounded(row, 8)
		table.insert(rows, row)
		local display = tostring(entry.displayName or entry.name or "Player")
		local username = tostring(entry.name or "")
		label(row, display .. "  @" .. username, UDim2.fromOffset(10, 4), UDim2.new(0.62, -10, 0, 18), COLORS.text, 9)
		label(row, if entry.allowTeleport then "TELEPORT ALLOWED" else "PERMISSION OFF", UDim2.fromOffset(10, 24), UDim2.new(0.62, -10, 0, 16), if entry.allowTeleport then COLORS.green else COLORS.muted, 8)
		local teleportButton = button(row, "TELEPORT", UDim2.new(1, -104, 0, 9), UDim2.fromOffset(94, 30), function()
			local result = invoke("TeleportTo", {userId = entry.userId})
			notify(result.message or "Teleport failed.", result.ok)
		end, COLORS.cyan)
		if not entry.allowTeleport then
			teleportButton.Text = "LOCKED"
			teleportButton.BackgroundColor3 = COLORS.card
			teleportButton.AutoButtonColor = false
		end
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(function()
		local query = string.lower(string.sub(search.Text, 1, 40))
		for _, row in ipairs(rows) do
			local text = string.lower(tostring(row:FindFirstChildWhichIsA("TextLabel") and row:FindFirstChildWhichIsA("TextLabel").Text or ""))
			row.Visible = query == "" or string.find(text, query, 1, true) ~= nil
		end
	end)
	if #rows == 0 then
		label(list, "No other players are currently in this server.", UDim2.fromOffset(12, 12), UDim2.new(1, -24, 0, 28), COLORS.muted, 9)
	end
end

local function renderMessage()
	label(content, "MESSAGES & ANNOUNCEMENTS", UDim2.fromOffset(4, 0), UDim2.new(1, -8, 0, 22), COLORS.accent, 12)
	local afk = card(86)
	label(afk, "YOUR AFK MESSAGE", UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 18), COLORS.accent, 10)
	label(afk, tostring(state.afkMessage or "No AFK message saved.") , UDim2.fromOffset(14, 32), UDim2.new(1, -28, 0, 38), COLORS.muted, 9)

	local bubble = card(124)
	label(bubble, "ADMIN OVERHEAD BROADCAST", UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 18), COLORS.accent, 10)
	local bubbleInput = input(bubble, "Message shown above your character", UDim2.fromOffset(14, 34), UDim2.new(1, -28, 0, 32), "")
	local bubbleButton = button(bubble, if state.canAnnounce then "SEND OVERHEAD BROADCAST" else "ADMIN ONLY", UDim2.fromOffset(14, 78), UDim2.new(1, -28, 0, 30), function()
		if state.canAnnounce ~= true then notify("Administrator announcement permission is required."); return end
		local result = invoke("BubbleBroadcast", {message = bubbleInput.Text})
		notify(result.message or "Broadcast failed.", result.ok)
	end, COLORS.cyan)
	if state.canAnnounce ~= true then bubbleButton.AutoButtonColor = false end

	local announcement = card(124)
	label(announcement, "SERVER ANNOUNCEMENT  |  3 MIN COOLDOWN", UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 18), COLORS.accent, 10)
	local announcementInput = input(announcement, "Announcement for everyone in this server", UDim2.fromOffset(14, 34), UDim2.new(1, -28, 0, 32), "")
	local announcementButton = button(announcement, if state.canAnnounce then "SEND ANNOUNCEMENT" else "ADMIN ONLY", UDim2.fromOffset(14, 78), UDim2.new(1, -28, 0, 30), function()
		if state.canAnnounce ~= true then notify("Administrator announcement permission is required."); return end
		local result = invoke("Announcement", {message = announcementInput.Text})
		notify(result.message or "Announcement failed.", result.ok)
	end, COLORS.accent)
	if state.canAnnounce ~= true then announcementButton.AutoButtonColor = false end
end

render = function()
	clearContent()
	refreshTabs()
	if activeTab == "Players" then renderPlayers()
	elseif activeTab == "Message" then renderMessage()
	else renderSettings() end
end

-- Keep the compact ClubMusic overhead bar out of the way while Sultan
-- Settings is open. Preserve each bar's previous state so closing this panel
-- never forces a HUD visible that another menu intentionally hid.
local hiddenClubHud: {[Instance]: boolean} = {}

local function isCompactClubHud(instance: Instance): boolean
	if not instance:IsA("GuiObject") then return false end
	local normalizedName = string.lower(string.gsub(instance.Name, "[^%w]", ""))
	return normalizedName == "topbarhud"
		or normalizedName == "clubmusictopbarhud"
		or normalizedName == "compactclubhud"
		or normalizedName == "clubmusiccompacthud"
end

local function hideClubHud()
	playerGui:SetAttribute("SultanSettingsOpen", true)
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if isCompactClubHud(descendant) then
			local guiObject = descendant :: GuiObject
			if hiddenClubHud[guiObject] == nil then
				hiddenClubHud[guiObject] = guiObject.Visible
			end
			guiObject.Visible = false
		end
	end
end

local function restoreClubHud()
	playerGui:SetAttribute("SultanSettingsOpen", false)
	local clubMenuExpanded = playerGui:GetAttribute("ClubMusicMenuExpanded") == true
	for instance, wasVisible in pairs(hiddenClubHud) do
		if instance.Parent and instance:IsA("GuiObject") then
			-- Never reveal the compact HUD underneath the full-screen ClubMusic menu.
			(instance :: GuiObject).Visible = wasVisible and not clubMenuExpanded
		end
	end
	table.clear(hiddenClubHud)
end

playerGui.DescendantAdded:Connect(function(descendant)
	if panel.Visible and isCompactClubHud(descendant) then
		local guiObject = descendant :: GuiObject
		if hiddenClubHud[guiObject] == nil then
			hiddenClubHud[guiObject] = guiObject.Visible
		end
		guiObject.Visible = false
	end
end)

local function open()
	if not refreshState() then return end
	panel.Visible = true
	shade.Visible = true
	toggle.Visible = false
	hideClubHud()
	activeTab = "Settings"
	render()
end

local function closePanel()
	panel.Visible = false
	shade.Visible = false
	-- Do not expose the Sultan launcher to guests or underneath the full ClubMusic menu.
	toggle.Visible = player:GetAttribute("IsTikiTideSultan") == true
		and playerGui:GetAttribute("ClubMusicMenuExpanded") ~= true
	restoreClubHud()
end

toggle.Activated:Connect(open)
close.Activated:Connect(closePanel)
shade.Activated:Connect(closePanel)

local function showBroadcast(kind: any, senderUserId: any, message: any)
	if typeof(kind) ~= "string" or typeof(senderUserId) ~= "number" or typeof(message) ~= "string" then return end
	if kind == "Announcement" then
		local banner = make("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 18),
			Size = UDim2.new(0.82, 0, 0, 52),
			BackgroundColor3 = COLORS.card,
			Text = "ANNOUNCEMENT  |  " .. string.sub(message, 1, 180),
			TextColor3 = COLORS.accent,
			TextSize = 12,
			Font = Enum.Font.GothamBold,
			TextWrapped = true,
			ZIndex = 40,
		}, gui) :: TextLabel
		rounded(banner, 12)
		task.delay(8, function() if banner.Parent then banner:Destroy() end end)
	elseif kind == "Bubble" then
		local sender = Players:GetPlayerByUserId(senderUserId)
		local character = sender and sender.Character
		local head = character and character:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") then return end
		local bubbleGui = make("BillboardGui", {
			Name = "SultanAdminBroadcast",
			Adornee = head,
			Size = UDim2.fromOffset(260, 64),
			StudsOffset = Vector3.new(0, 4.2, 0),
			AlwaysOnTop = true,
			MaxDistance = 120,
		}, head) :: BillboardGui
		local textLabel = make("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = COLORS.card,
			BackgroundTransparency = 0.08,
			Text = string.sub(message, 1, 180),
			TextColor3 = COLORS.text,
			TextSize = 13,
			Font = Enum.Font.GothamBold,
			TextWrapped = true,
		}, bubbleGui)
		rounded(textLabel, 10)
		task.delay(8, function() if bubbleGui.Parent then bubbleGui:Destroy() end end)
	end
end

broadcast.OnClientEvent:Connect(showBroadcast)

local function updateVisibility()
	local allowed = player:GetAttribute("IsTikiTideSultan") == true
	toggle.Visible = allowed and not panel.Visible and playerGui:GetAttribute("ClubMusicMenuExpanded") ~= true
end
player:GetAttributeChangedSignal("IsTikiTideSultan"):Connect(updateVisibility)
playerGui:GetAttributeChangedSignal("ClubMusicMenuExpanded"):Connect(updateVisibility)
updateVisibility()

player.CharacterAdded:Connect(function()
	if panel.Visible then
		task.delay(1, function()
			if panel.Visible then refreshState(); render() end
		end)
	end
end)

print("[Sultan Settings] Client UI loaded.")
