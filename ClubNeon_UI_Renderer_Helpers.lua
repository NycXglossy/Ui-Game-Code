--!strict
-- Shared renderer primitives. Constructed once by UI_Renderer with its runtime dependencies.
return function(deps: {[string]: any})
	local C = deps.C
	local TITLE_EFFECTS, TITLE_FONTS = deps.TITLE_EFFECTS, deps.TITLE_FONTS
	local TITLE_STYLES, TITLE_FIXED = deps.TITLE_STYLES, deps.TITLE_FIXED
	local UserInputService, GuiService = deps.UserInputService, deps.GuiService
	local function findById(list: {any}, id: string): any
		for _, entry in ipairs(list) do
			if entry.id == id then return entry end
		end
		return nil
	end
	
	local function titleSetFor(effectId: string, setId: string): any
		local effect = findById(TITLE_EFFECTS, effectId)
		if not effect then return TITLE_FIXED[1] end
		return findById(effect.sets, setId) or effect.sets[1]
	end
	
	local function normalizeTitle(data: any): {[string]: any}
		local d: any = if typeof(data) == "table" then data else {}
		local effect = tostring(d.effect or "fixed")
		if not findById(TITLE_EFFECTS, effect) then effect = "fixed" end
		local set = titleSetFor(effect, tostring(d.set or d.colorSet or d.color or ""))
		local font = tostring(d.font or "gotham")
		if not findById(TITLE_FONTS, font) then font = "gotham" end
		local style = tostring(d.style or "normal")
		if not table.find(TITLE_STYLES, style) then style = "normal" end
		return {
			text = tostring(d.text or ""),
			effect = effect,
			set = set.id,
			font = font,
			style = style,
			size = math.clamp(math.floor((tonumber(d.textSize or d.size) or 20) + 0.5), 14, 32),
			height = math.clamp(tonumber(d.heightOffset or d.height) or 2.5, 0, 8),
			distance = math.clamp(tonumber(d.viewDistance or d.distance) or 80, 20, 200),
		}
	end
	
	-- Circular palette (A, midpoint, B, midpoint) used by palette-based Rainbow sets; mirrors the server.
	local function rainbowPaletteFor(set: any): {Color3}
		local middle = set.a:Lerp(set.b, 0.5)
		return { set.a, middle, set.b, middle }
	end
	
	local function titleColorHex(effectId: string, setId: string): {string}
		local set = titleSetFor(effectId, setId)
		local function hex(color: Color3): string return "#" .. color:ToHex() end
		if effectId == "fixed" then
			return { hex(set.color) }
		elseif effectId == "gradient" or effectId == "twotone" or effectId == "shimmer" then
			return { hex(set.a), hex(set.b) }
		elseif effectId == "rainbow" then
			local out = {}
			if set.a ~= nil then
				for _, color in ipairs(rainbowPaletteFor(set)) do table.insert(out, hex(color)) end
				return out
			end
			for i = 0, 6 do table.insert(out, hex(Color3.fromHSV(i / 7, set.s, set.v))) end
			return out
		end
		return {}
	end
	
	local function escapeRich(text: string): string
		text = string.gsub(text, "&", "&amp;")
		text = string.gsub(text, "<", "&lt;")
		text = string.gsub(text, ">", "&gt;")
		return text
	end
	
	-- Rotates a circular palette smoothly; phase 0..1 is one full loop.
	local function flowPaletteSequence(colors: {Color3}, phase: number): ColorSequence
		local count = #colors
		local position = (phase % 1) * count
		local base = math.floor(position)
		local fraction = position - base
		local keypoints = {}
		for i = 0, count do
			local from = colors[((i + base) % count) + 1]
			local to = colors[((i + base + 1) % count) + 1]
			keypoints[i + 1] = ColorSequenceKeypoint.new(i / count, from:Lerp(to, fraction))
		end
		return ColorSequence.new(keypoints)
	end
	
	-- Styles a TextLabel from a title spec (effect, color set, font, style) and returns an
	-- update(t) function that animates the RGB and Rainbow effects (a no-op for static ones).
	local function styleTitleLabel(label: TextLabel, spec: any): (number) -> ()
		local fontEntry = findById(TITLE_FONTS, spec.font) or TITLE_FONTS[1]
		label.Font = fontEntry.font
		label.RichText = true
		local text = escapeRich(if spec.text ~= "" then spec.text else "Your Title")
		if spec.style == "bold" then text = "<b>" .. text .. "</b>"
		elseif spec.style == "italic" then text = "<i>" .. text .. "</i>" end
		label.Text = text
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = if spec.style == "outline" then 0 else 1
		label.TextColor3 = C.White
	
		local gradient = label:FindFirstChildOfClass("UIGradient") :: UIGradient?
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Parent = label
		end
		local grad = gradient :: UIGradient
		local set = titleSetFor(spec.effect, spec.set)
		grad.Enabled = true
		local function noop(_: number) end
	
		if spec.effect == "fixed" then
			grad.Enabled = false
			label.TextColor3 = set.color
			return noop
		elseif spec.effect == "gradient" then
			grad.Color = ColorSequence.new(set.a, set.b)
			return noop
		elseif spec.effect == "twotone" then
			grad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, set.a),
				ColorSequenceKeypoint.new(0.499, set.a),
				ColorSequenceKeypoint.new(0.5, set.b),
				ColorSequenceKeypoint.new(1, set.b),
			})
			return noop
		elseif spec.effect == "shimmer" then
			grad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, set.a),
				ColorSequenceKeypoint.new(0.36, set.a),
				ColorSequenceKeypoint.new(0.5, C.White),
				ColorSequenceKeypoint.new(0.64, set.b),
				ColorSequenceKeypoint.new(1, set.b),
			})
			grad.Rotation = 0
			return function(t: number)
				grad.Offset = Vector2.new(((t * 0.45) % 2) - 1, 0)
			end
		elseif spec.effect == "rainbow" then
			if set.a ~= nil then
				local palette = rainbowPaletteFor(set)
				grad.Color = flowPaletteSequence(palette, 0)
				return function(t: number)
					grad.Color = flowPaletteSequence(palette, t * 0.12)
				end
			end
			return function(t: number)
				local keypoints = {}
				for i = 0, 7 do
					local hue = ((i / 7) - t * 0.12) % 1
					keypoints[i + 1] = ColorSequenceKeypoint.new(i / 7, Color3.fromHSV(hue, set.s, set.v))
				end
				grad.Color = ColorSequence.new(keypoints)
			end
		else -- rgb
			grad.Enabled = false
			return function(t: number)
				label.TextColor3 = Color3.fromHSV((t * set.speed) % 1, 0.9, 1)
			end
		end
	end
	
	-- Accepts a bare ID, "rbxassetid://123", or a Creator Hub link such as
	-- https://create.roblox.com/store/asset/123/Name and returns the numeric asset ID.
	local function parseAssetId(text: string): number?
		local raw = tostring(text)
		local id = string.match(raw, "rbxassetid://(%d+)")
			or string.match(raw, "asset/(%d+)")
			or string.match(raw, "[?&]id=(%d+)")
			or string.match(raw, "^%s*(%d+)%s*$")
			or string.match(raw, "(%d%d%d%d+)")
		local number = tonumber(id)
		if number and number > 0 and number < 9007199254740992 then
			return math.floor(number)
		end
		return nil
	end
	
	local function corner(parent: Instance, radius: number)
		local obj = Instance.new("UICorner")
		obj.CornerRadius = UDim.new(0, radius)
		obj.Parent = parent
		return obj
	end
	
	local function stroke(parent: Instance, color: Color3, thickness: number?)
		local obj = Instance.new("UIStroke")
		obj.Color = color
		obj.Thickness = thickness or 1
		obj.Transparency = 0.68
		obj.Parent = parent
		return obj
	end
	
	local function make(className: string, props: {[string]: any}, parent: Instance?): any
		local obj = Instance.new(className)
		for key, value in pairs(props) do
			(obj :: any)[key] = value
		end
		if parent then obj.Parent = parent end
		return obj
	end
	
	local function formatTime(seconds: number): string
		local value = math.max(0, math.floor(seconds))
		return string.format("%d:%02d", math.floor(value / 60), value % 60)
	end
	
	-- Explicit selection feedback keeps controller focus visible across all menu controls.
	local function bindFocusFeedback(button: GuiButton, outline: UIStroke?, baseColor: Color3?)
		button.Selectable = true
		button.SelectionGroup = false
		local normalColor = baseColor or button.BackgroundColor3
		local function setFocused(focused: boolean)
			if outline and outline.Parent then
				outline.Color = if focused then C.Cyan else normalColor
				outline.Transparency = if focused then 0 else 0.58
				outline.Thickness = if focused then 2.5 else 1
			end
			if button.Parent and button:IsA("TextButton") then
				button.BackgroundColor3 = if focused then normalColor:Lerp(C.Cyan, 0.16) else normalColor
			end
		end
		button.SelectionGained:Connect(function() setFocused(true) end)
		button.SelectionLost:Connect(function() setFocused(false) end)
		button.MouseEnter:Connect(function()
			if not UserInputService.GamepadEnabled or GuiService.SelectedObject ~= button then setFocused(true) end
		end)
		button.MouseLeave:Connect(function()
			if GuiService.SelectedObject ~= button then setFocused(false) end
		end)
	end
	
	-- Small icons are composed from Roblox Frames, not emoji or external assets.
	local function buildNativeIcon(parent: Instance, kind: string, color: Color3, zIndex: number?): Frame
		local root = make("Frame", {Name="NativeIcon_"..kind, AnchorPoint=Vector2.new(.5,.5), Position=UDim2.fromScale(.5,.5), Size=UDim2.fromScale(.58,.58), BackgroundTransparency=1, BorderSizePixel=0, ZIndex=zIndex or 2}, parent) :: Frame
		local function part(name: string, x: number, y: number, w: number, h: number, rotation: number?)
			local item = make("Frame", {Name=name, AnchorPoint=Vector2.new(.5,.5), Position=UDim2.fromScale(x,y), Size=UDim2.fromScale(w,h), BackgroundColor3=color, BorderSizePixel=0, Rotation=rotation or 0, ZIndex=root.ZIndex}, root) :: Frame
			corner(item, 3)
			return item
		end
		if kind == "music" then
			part("StemLeft",.39,.42,.075,.60,0); part("StemRight",.69,.33,.075,.60,0); part("Beam",.54,.16,.38,.075,-8)
			part("NoteHeadLeft",.25,.78,.27,.19,0); part("NoteHeadRight",.57,.78,.27,.19,0)
		elseif kind == "close" then
			part("SlashA",.5,.5,.78,.09,45); part("SlashB",.5,.5,.78,.09,-45)
		elseif kind == "up" or kind == "down" then
			local direction = if kind == "up" then -1 else 1
			part("ArrowLeft",.37,.5,.10,.42,45 * direction)
			part("ArrowRight",.63,.5,.10,.42,-45 * direction)
		elseif kind == "reload" or kind == "restart" then
			-- Familiar Roblox-style circular arrow, drawn from native GUI shapes.
			-- A slightly open-ended ring and a compact arrow tip stay crisp at small sizes.
			local arc = make("Frame", {
				Name = if kind == "restart" then "RestartArc" else "ReloadArc",
				AnchorPoint = Vector2.new(.5,.5),
				Position = UDim2.fromScale(.47,.53),
				Size = UDim2.fromScale(.72,.72),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = root.ZIndex,
			}, root) :: Frame
			local arcStroke = Instance.new("UIStroke")
			arcStroke.Color = color
			arcStroke.Thickness = 2.4
			arcStroke.LineJoinMode = Enum.LineJoinMode.Round
			arcStroke.Parent = arc
			corner(arc, 20)
			part("ArrowHeadA",.75,.17,.12,.34,42)
			part("ArrowHeadB",.85,.29,.12,.34,-48)
		elseif kind == "minus" then
			part("MinusBar",.5,.5,.72,.10,0)
		elseif kind == "star" then
			for i = 1, 5 do
				local angle = (i - 1) * 72 - 90
				local radians = math.rad(angle)
				local x, y = .5 + math.cos(radians) * .22, .5 + math.sin(radians) * .22
				part("StarRay"..i, x, y, .11, .38, angle + 90)
			end
		elseif kind == "volume" then
			part("SpeakerBody",.25,.5,.20,.34,0); part("SpeakerConeA",.43,.39,.10,.36,-45); part("SpeakerConeB",.43,.61,.10,.36,45)
			local a=part("SoundArcA",.70,.5,.075,.36,0); local b=part("SoundArcB",.82,.5,.075,.58,0)
			a:SetAttribute("SoundArc",true); b:SetAttribute("SoundArc",true)
		end
		return root
	end
	
	-- Native navigation icon builder; isolated from menu construction.
	-- Navigation icons are assembled from native Frames, rounded corners and UIStrokes.
	-- This avoids font-dependent Unicode glyphs and renders consistently on Roblox clients.
	local function navIconPart(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, radius: number?, rotation: number?): Frame
		local part = make("Frame", {
			Name = name,
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(w, h),
			BackgroundColor3 = color,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Rotation = rotation or 0,
		}, parent) :: Frame
		if radius and radius > 0 then corner(part, radius) end
		return part
	end

	local function navIconOutline(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, radius: number?, rotation: number?): Frame
		local part = make("Frame", {
			Name = name,
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(w, h),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Rotation = rotation or 0,
		}, parent) :: Frame
		if radius and radius > 0 then corner(part, radius) end
		local outline = stroke(part, color, 1.7)
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		return part
	end

	local function createNavIcon(parent: Frame, tabName: string): Frame
		local icon = make("Frame", {
			Name = "NavIcon",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, parent) :: Frame
		local ink = C.Muted
		local function line(name: string, x: number, y: number, w: number, h: number, angle: number?)
			navIconPart(icon, name, x, y, w, h, ink, 1, angle)
		end
		local function ring(name: string, x: number, y: number, w: number, h: number, angle: number?)
			navIconOutline(icon, name, x, y, w, h, ink, 1, angle)
		end
		if tabName == "Home" then
			line("RoofLeft", .19, .30, .36, .075, -38); line("RoofRight", .45, .30, .36, .075, 38)
			ring("House", .27, .43, .46, .39); navIconPart(icon, "Door", .46, .59, .10, .23, ink, 1)
		elseif tabName == "Music" or tabName == "Audio ID" then
			line("StemOne", .33, .24, .075, .53); line("StemTwo", .67, .17, .075, .53)
			line("Beam", .36, .19, .36, .075, -8)
			ring("NoteOne", .13, .66, .30, .23); ring("NoteTwo", .48, .59, .30, .23)
		elseif tabName == "Shop" then
			ring("BagBody", .22, .35, .56, .48); line("BagHandle", .36, .20, .28, .07)
			line("BagHandleLeft", .34, .22, .07, .20, -18); line("BagHandleRight", .59, .22, .07, .20, 18)
		elseif tabName == "Playlists" then
			for i = 0, 2 do
				ring("PlaylistDot"..i, .13, .24 + i * .25, .12, .12)
				line("PlaylistLine"..i, .36, .27 + i * .25, .50, .065)
			end
		elseif tabName == "Queue" then
			for i = 0, 2 do
				line("QueueLine"..i, .24, .23 + i * .25, .62, .07)
			end
			ring("QueueDot", .08, .18, .12, .12)
		elseif tabName == "DJ Booth" then
			ring("VinylOuter", .15, .15, .70, .70); ring("VinylInner", .29, .29, .42, .42)
			navIconPart(icon, "VinylCenter", .43, .43, .14, .14, ink, 1)
		elseif tabName == "Daily Rewards" then
		elseif tabName == "Daily Rewards" then
			ring("Calendar", .20, .24, .60, .58); line("CalendarHeader", .22, .40, .56, .07)
			line("CalendarPinA", .34, .13, .07, .22); line("CalendarPinB", .61, .13, .07, .22)
			for row = 0, 1 do for col = 0, 1 do navIconPart(icon, "Date"..row..col, .34 + col * .22, .53 + row * .14, .10, .08, ink, 1) end end
		elseif tabName == "Title Tag" then
			ring("TagBody", .24, .31, .52, .38, 45)
			navIconPart(icon, "TagHole", .27, .43, .09, .09, ink, 1)
			line("TagPointA", .57, .30, .075, .38, 45); line("TagPointB", .57, .30, .075, .38, -45)
		elseif tabName == "Community" then
			ring("PersonLeft", .17, .20, .25, .25); ring("PersonRight", .58, .20, .25, .25)
			ring("GroupLeft", .08, .53, .40, .30); ring("GroupRight", .52, .53, .40, .30)
		elseif tabName == "Moderation" then
			line("ShieldTop", .27, .20, .46, .065)
			line("ShieldLeft", .23, .23, .065, .40, -8); line("ShieldRight", .70, .23, .065, .40, 8)
			line("ShieldLowerLeft", .30, .58, .065, .25, 34); line("ShieldLowerRight", .64, .58, .065, .25, -34)
			line("CheckA", .34, .51, .075, .22, -42); line("CheckB", .48, .48, .075, .34, 42)
		end
		return icon
	end


	return {
		findById=findById, titleSetFor=titleSetFor, normalizeTitle=normalizeTitle,
		rainbowPaletteFor=rainbowPaletteFor, titleColorHex=titleColorHex, escapeRich=escapeRich,
		flowPaletteSequence=flowPaletteSequence, styleTitleLabel=styleTitleLabel, parseAssetId=parseAssetId,
		corner=corner, stroke=stroke, make=make, formatTime=formatTime,
		bindFocusFeedback=bindFocusFeedback, buildNativeIcon=buildNativeIcon,
		createNavIcon=createNavIcon,
	}
end
