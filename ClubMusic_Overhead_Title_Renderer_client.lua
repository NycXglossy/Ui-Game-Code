--!strict
-- ClubMusic_Overhead_Title_Renderer.client.lua
-- Place as a LocalScript in StarterPlayer/StarterPlayerScripts.
--
-- Reads ONLY server-replicated Player attributes written by UI_Server_Controller.
-- This script does not create remotes, accept privileged requests, save data,
-- grant permissions, or modify authoritative title settings.
--
-- Expected attributes:
-- ShowCustomTitle, CustomTitle, TitleEffect, TitleSet, TitleColors,
-- TitleSpeed, TitleFont, TitleStyle, TitleHeight, TitleDistance

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LOCAL_PLAYER = Players.LocalPlayer

local GUI_NAME_PREFIX = "ClubMusicOverheadTitle_"
local UPDATE_INTERVAL = 0.10 -- 10 updates/second for animated effects
local MAX_TITLE_BYTES = 256
local MAX_COLORS = 7

local FONT_MAP: {[string]: Enum.Font} = {
	gotham = Enum.Font.GothamBold,
	fredoka = Enum.Font.FredokaOne,
	arcade = Enum.Font.Arcade,
	cartoon = Enum.Font.Cartoon,
	scifi = Enum.Font.SciFi,
	fantasy = Enum.Font.Fantasy,
	bangers = Enum.Font.Bangers,
	luckiest = Enum.Font.LuckiestGuy,
	marker = Enum.Font.PermanentMarker,
	hand = Enum.Font.PatrickHand,
	retro = Enum.Font.SpecialElite,
	code = Enum.Font.Code,
}

local ALLOWED_EFFECTS: {[string]: boolean} = {
	fixed = true,
	rgb = true,
	gradient = true,
	rainbow = true,
	twotone = true,
	-- Future-compatible only. The current supplied server allowlist does not
	-- permit this effect yet, so it cannot be selected through the UI.
	shimmer = true,
}

-- Rainbow sets that are full-spectrum hue cycles. Every other Rainbow set is a palette that flows
-- through its own colors instead (the server sends those as a circular color list).
local SPECTRUM_RAINBOW_SETS: {[string]: boolean} = {
	classic = true,
	pastel = true,
	neon = true,
	deep = true,
}

local ALLOWED_STYLES: {[string]: boolean} = {
	normal = true,
	bold = true,
	italic = true,
	outline = true,
}

type PlayerState = {
	player: Player,
	character: Model?,
	gui: BillboardGui?,
	label: TextLabel?,
	gradient: UIGradient?,
	connections: {RBXScriptConnection},
}

local states: {[Player]: PlayerState} = {}
local globalConnections: {RBXScriptConnection} = {}
local updateAccumulator = 0

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function boundedNumber(value: any, fallback: number, minimum: number, maximum: number): number
	local numberValue = tonumber(value)
	if not isFiniteNumber(numberValue) then
		return fallback
	end
	return math.clamp(numberValue :: number, minimum, maximum)
end

local function escapeRichText(value: string): string
	value = string.gsub(value, "&", "&amp;")
	value = string.gsub(value, "<", "&lt;")
	value = string.gsub(value, ">", "&gt;")
	value = string.gsub(value, '"', "&quot;")
	value = string.gsub(value, "'", "&apos;")
	return value
end

local function parseColors(raw: any): {Color3}
	local result: {Color3} = {}
	if typeof(raw) ~= "string" or #raw > 96 then
		return result
	end

	for token in string.gmatch(raw, "[^,]+") do
		if #result >= MAX_COLORS then
			break
		end
		local hex = string.match(token, "^%s*#?(%x%x%x%x%x%x)%s*$")
		if hex then
			local ok, color = pcall(function()
				return Color3.fromHex(hex)
			end)
			if ok and typeof(color) == "Color3" then
				table.insert(result, color)
			end
		end
	end

	return result
end

local function makeColorSequence(colors: {Color3}): ColorSequence?
	if #colors == 0 then
		return nil
	elseif #colors == 1 then
		return ColorSequence.new(colors[1])
	end

	local points = {}
	for index, color in ipairs(colors) do
		local time = (index - 1) / (#colors - 1)
		table.insert(points, ColorSequenceKeypoint.new(time, color))
	end
	return ColorSequence.new(points)
end

-- Rotates a circular color list smoothly; phase 0..1 is one full loop.
local function flowSequence(colors: {Color3}, phase: number): ColorSequence?
	local count = #colors
	if count < 2 then
		return makeColorSequence(colors)
	end
	local position = (phase % 1) * count
	local base = math.floor(position)
	local fraction = position - base
	local points = {}
	for index = 0, count do
		local from = colors[((index + base) % count) + 1]
		local to = colors[((index + base + 1) % count) + 1]
		table.insert(points, ColorSequenceKeypoint.new(index / count, from:Lerp(to, fraction)))
	end
	return ColorSequence.new(points)
end

local function getSafeTitle(player: Player): (string, boolean)
	local visible = player:GetAttribute("ShowCustomTitle") == true
	local rawText = player:GetAttribute("CustomTitle")

	if not visible or typeof(rawText) ~= "string" then
		return "", false
	end
	if #rawText == 0 or #rawText > MAX_TITLE_BYTES then
		return "", false
	end

	-- The server filters title text before publishing it. RichText is escaped
	-- again here so markup-like text cannot alter the label's formatting.
	local utf8Length = utf8.len(rawText)
	if not utf8Length or utf8Length > 24 then
		return "", false
	end

	return rawText, true
end

local function removeGui(state: PlayerState)
	if state.gui then
		state.gui:Destroy()
	end
	state.gui = nil
	state.label = nil
	state.gradient = nil
	state.character = nil
end

local function disconnectAll(state: PlayerState)
	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end
	table.clear(state.connections)
end

local function applyTextStyle(label: TextLabel, rawText: string, fontId: any, styleId: any)
	local fontKey = if typeof(fontId) == "string" then fontId else "gotham"
	label.Font = FONT_MAP[fontKey] or FONT_MAP.gotham

	local style = if typeof(styleId) == "string" and ALLOWED_STYLES[styleId] then styleId else "normal"
	local safeText = escapeRichText(rawText)
	label.RichText = true

	if style == "bold" then
		label.Text = "<b>" .. safeText .. "</b>"
	elseif style == "italic" then
		label.Text = "<i>" .. safeText .. "</i>"
	else
		label.Text = safeText
	end

	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = if style == "outline" then 0.12 else 0.72
end

local function createGui(state: PlayerState, character: Model, head: BasePart)
	removeGui(state)

	local player = state.player
	local billboard = Instance.new("BillboardGui")
	billboard.Name = GUI_NAME_PREFIX .. tostring(player.UserId)
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Size = UDim2.fromOffset(260, 44)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0, 0)
	label.Text = ""
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.RichText = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.72
	label.Parent = billboard

	local gradient = Instance.new("UIGradient")
	gradient.Enabled = false
	gradient.Parent = label

	local currentGui = LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui")
	if not currentGui then
		billboard:Destroy()
		return
	end
	billboard.Parent = currentGui

	state.character = character
	state.gui = billboard
	state.label = label
	state.gradient = gradient
end

local function refreshState(state: PlayerState)
	local player = state.player
	if player.Parent ~= Players then
		removeGui(state)
		return
	end

	local titleText, visible = getSafeTitle(player)
	if not visible then
		if state.gui then
			state.gui.Enabled = false
		end
		return
	end

	local character = player.Character
	if not character then
		removeGui(state)
		return
	end

	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		if state.character ~= character then
			removeGui(state)
		end
		return
	end

	if not state.gui or state.character ~= character or state.gui.Adornee ~= head then
		createGui(state, character, head)
	end

	local billboard = state.gui
	local label = state.label
	local gradient = state.gradient
	if not billboard or not label or not gradient then
		return
	end

	billboard.Enabled = true
	billboard.MaxDistance = boundedNumber(player:GetAttribute("TitleDistance"), 80, 20, 200)
	billboard.StudsOffset = Vector3.new(
		0,
		boundedNumber(player:GetAttribute("TitleHeight"), 2.5, 0, 8),
		0
	)

	applyTextStyle(
		label,
		titleText,
		player:GetAttribute("TitleFont"),
		player:GetAttribute("TitleStyle")
	)

	local effectRaw = player:GetAttribute("TitleEffect")
	local effect = if typeof(effectRaw) == "string" and ALLOWED_EFFECTS[effectRaw] then effectRaw else "fixed"
	local colors = parseColors(player:GetAttribute("TitleColors"))

	gradient.Enabled = false
	gradient.Offset = Vector2.zero
	gradient.Rotation = 0
	label.TextColor3 = Color3.new(1, 1, 1)

	if effect == "fixed" then
		gradient.Enabled = false
		label.TextColor3 = colors[1] or Color3.fromRGB(252, 211, 77)
	elseif effect == "rgb" then
		gradient.Enabled = false
		-- Animated hue is updated by the shared, throttled Heartbeat loop.
		local speed = boundedNumber(player:GetAttribute("TitleSpeed"), 0.25, 0.05, 1)
		local hue = (os.clock() * speed * 0.12) % 1
		label.TextColor3 = Color3.fromHSV(hue, 1, 1)
	elseif effect == "gradient" or effect == "twotone" or effect == "rainbow" then
		local sequence = makeColorSequence(colors)
		if sequence then
			gradient.Color = sequence
			gradient.Enabled = true
		else
			label.TextColor3 = Color3.fromRGB(252, 211, 77)
		end
	elseif effect == "shimmer" then
		-- This path is dormant with the currently supplied server controller.
		-- It becomes usable only after the server explicitly allowlists shimmer.
		local base = colors[1] or Color3.fromRGB(252, 211, 77)
		local highlight = colors[2] or Color3.new(1, 1, 1)
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, base),
			ColorSequenceKeypoint.new(0.45, highlight),
			ColorSequenceKeypoint.new(0.55, highlight),
			ColorSequenceKeypoint.new(1, base),
		})
		gradient.Enabled = true
		gradient.Offset = Vector2.new(-1, 0)
	end
end

local function bindPlayer(player: Player)
	if states[player] then
		return
	end

	local state: PlayerState = {
		player = player,
		character = nil,
		gui = nil,
		label = nil,
		gradient = nil,
		connections = {},
	}
	states[player] = state

	local function changed()
		refreshState(state)
	end

	local watchedAttributes = {
		"ShowCustomTitle",
		"CustomTitle",
		"TitleEffect",
		"TitleSet",
		"TitleColors",
		"TitleSpeed",
		"TitleFont",
		"TitleStyle",
		"TitleHeight",
		"TitleDistance",
	}

	for _, attributeName in ipairs(watchedAttributes) do
		table.insert(state.connections, player:GetAttributeChangedSignal(attributeName):Connect(changed))
	end

	table.insert(state.connections, player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			local head = character:WaitForChild("Head", 10)
			if states[player] ~= state or player.Character ~= character then
				return
			end
			-- Always refresh after the Head appears. Attribute changes can occur
			-- while WaitForChild yields; they must not suppress the initial render.
			if head and head:IsA("BasePart") then
				refreshState(state)
			end
		end)
	end))

	table.insert(state.connections, player.CharacterRemoving:Connect(function(character)
		if state.character == character then
			removeGui(state)
		end
	end))

	if player.Character then
		task.spawn(function()
			local character = player.Character
			local head = character and character:WaitForChild("Head", 10)
			if states[player] == state and character and player.Character == character and head and head:IsA("BasePart") then
				refreshState(state)
			end
		end)
	end

	refreshState(state)
end

local function unbindPlayer(player: Player)
	local state = states[player]
	if not state then
		return
	end
	states[player] = nil
	disconnectAll(state)
	removeGui(state)
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

table.insert(globalConnections, Players.PlayerAdded:Connect(bindPlayer))
table.insert(globalConnections, Players.PlayerRemoving:Connect(unbindPlayer))

-- One shared, throttled animation loop instead of one loop per player.
table.insert(globalConnections, RunService.Heartbeat:Connect(function(deltaTime)
	updateAccumulator += deltaTime
	if updateAccumulator < UPDATE_INTERVAL then
		return
	end
	updateAccumulator = 0

	for player, state in pairs(states) do
		local label = state.label
		local gradient = state.gradient
		if label and label.Parent and player.Parent == Players and player:GetAttribute("ShowCustomTitle") == true then
			local effect = player:GetAttribute("TitleEffect")
			if effect == "rgb" then
				local speed = boundedNumber(player:GetAttribute("TitleSpeed"), 0.25, 0.05, 1)
				local hue = (os.clock() * speed * 0.12) % 1
				label.TextColor3 = Color3.fromHSV(hue, 1, 1)
			elseif effect == "rainbow" and gradient then
				local colors = parseColors(player:GetAttribute("TitleColors"))
				if #colors > 0 then
					local phase = (os.clock() * 0.08) % 1
					local setId = player:GetAttribute("TitleSet")
					local sequence: ColorSequence? = nil
					if typeof(setId) == "string" and SPECTRUM_RAINBOW_SETS[setId] then
						local shifted = {}
						for _, color in ipairs(colors) do
							local hue, saturation, value = color:ToHSV()
							table.insert(shifted, Color3.fromHSV((hue + phase) % 1, saturation, value))
						end
						sequence = makeColorSequence(shifted)
					else
						sequence = flowSequence(colors, phase)
					end
					if sequence then
						gradient.Color = sequence
						gradient.Enabled = true
					end
				end
			elseif effect == "shimmer" and gradient and gradient.Enabled then
				local speed = boundedNumber(player:GetAttribute("TitleSpeed"), 0.25, 0.05, 1)
				local phase = (os.clock() * speed * 0.35) % 2
				gradient.Offset = Vector2.new(if phase <= 1 then phase - 1 else 1 - phase, 0)
			end
		end
	end
end))

-- Clean up if the local PlayerGui is replaced during unusual client resets.
table.insert(globalConnections, LOCAL_PLAYER.ChildRemoved:Connect(function(child)
	if child.Name == "PlayerGui" then
		for _, state in pairs(states) do
			removeGui(state)
		end
	end
end))

table.insert(globalConnections, LOCAL_PLAYER.ChildAdded:Connect(function(child)
	if child:IsA("PlayerGui") then
		for _, state in pairs(states) do
			refreshState(state)
		end
	end
end))

script.Destroying:Connect(function()
	for _, connection in ipairs(globalConnections) do
		pcall(function() connection:Disconnect() end)
	end
	table.clear(globalConnections)
	for player in pairs(states) do
		unbindPlayer(player)
	end
end)
