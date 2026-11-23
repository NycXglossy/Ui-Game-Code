--!strict
-- Club Neon title-slot presentation and validation. No persistence or text filtering is owned here.
return function(deps: {[string]: any})
	local TITLE_HEX, RAINBOW_PARAMS = deps.TITLE_HEX, deps.RAINBOW_PARAMS
	local TITLE_SETS, TITLE_FONTS, TITLE_STYLES = deps.TITLE_SETS, deps.TITLE_FONTS, deps.TITLE_STYLES
	local RGB_SPEED = deps.RGB_SPEED
	local TITLE_SLOT_COUNT, MAX_CUSTOM_TITLE_LENGTH = deps.TITLE_SLOT_COUNT, deps.MAX_CUSTOM_TITLE_LENGTH
	local isFiniteNumber = deps.isFiniteNumber

	local function titleHexFor(effect: string, set: string): {string}
		if effect == "rainbow" then
			local palette = if RAINBOW_PARAMS[set] == nil then TITLE_HEX.gradient[set] else nil
			if palette and #palette >= 2 then
				local first, second = Color3.fromHex(palette[1]), Color3.fromHex(palette[2])
				local middle = "#" .. first:Lerp(second, 0.5):ToHex()
				return { palette[1], middle, palette[2], middle }
			end
			local params, out = RAINBOW_PARAMS[set] or RAINBOW_PARAMS.classic, {}
			for i = 0, 6 do table.insert(out, "#" .. Color3.fromHSV(i / 7, params[1], params[2]):ToHex()) end
			return out
		end
		local group = TITLE_HEX[effect]
		local colors = if group then group[set] else nil
		return colors or {}
	end

	local function sanitizeTitleSlot(data: any): any
		if typeof(data) ~= "table" then return nil end
		local text = data.text
		if typeof(text) ~= "string" or #text > 256 then return nil end
		local length = utf8.len(text)
		if not length or length < 1 or length > MAX_CUSTOM_TITLE_LENGTH then return nil end
		local effect = data.effect
		if typeof(effect) ~= "string" or TITLE_SETS[effect] == nil then return nil end
		local set = data.set
		if typeof(set) ~= "string" or TITLE_SETS[effect][set] ~= true then return nil end
		local font = data.font
		if typeof(font) ~= "string" or TITLE_FONTS[font] ~= true then return nil end
		local style = data.style
		if typeof(style) ~= "string" or TITLE_STYLES[style] ~= true then return nil end
		local textSize, height, distance = tonumber(data.textSize or data.size), tonumber(data.heightOffset or data.height), tonumber(data.viewDistance or data.distance)
		if not isFiniteNumber(textSize) then textSize = 20 end
		if not isFiniteNumber(height) then height = 2.5 end
		if not isFiniteNumber(distance) then distance = 80 end
		return {
			text = text, effect = effect, set = set, font = font, style = style,
			textSize = math.clamp(math.floor((textSize or 20) + 0.5), 14, 32),
			height = math.clamp(height or 2.5, 0, 8), distance = math.clamp(distance or 80, 20, 200),
		}
	end

	local function firstFilledSlot(profile: any): number?
		for i = 1, TITLE_SLOT_COUNT do
			if profile.titleSlots[i] and i <= profile.unlockedSlots then return i end
		end
		return nil
	end

	local function applyTitleAttributes(player: Player, profile: any, safeTexts: {[number]: string}?)
		local slot = profile.titleSlots[profile.activeSlot]
		local safeText = if safeTexts then safeTexts[profile.activeSlot] else nil
		player:SetAttribute("EquippedTag", if typeof(profile.equippedTag) == "string" then profile.equippedTag else "")
		player:SetAttribute("TitleSlotsUnlocked", profile.unlockedSlots)
		player:SetAttribute("TitleSlot", profile.activeSlot)
		player:SetAttribute("ShowCustomTitle", profile.showCustomTitle)
		if slot == nil or typeof(safeText) ~= "string" or safeText == "" then
			player:SetAttribute("CustomTitle", "")
			player:SetAttribute("TitleColor", "gold")
			player:SetAttribute("TitleStyle", "normal")
			player:SetAttribute("TitleEffect", "fixed")
			player:SetAttribute("TitleSet", "gold")
			player:SetAttribute("TitleColors", "#FCD34D")
			player:SetAttribute("TitleSpeed", 0)
			player:SetAttribute("TitleShimmer", false)
			player:SetAttribute("TitleFont", "gotham")
			player:SetAttribute("TitleTextSize", 20)
			player:SetAttribute("TitleHeight", 2.5)
			player:SetAttribute("TitleDistance", 80)
			return
		end
		player:SetAttribute("CustomTitle", safeText)
		player:SetAttribute("TitleColor", if slot.effect == "fixed" then slot.set else "gold")
		player:SetAttribute("TitleStyle", slot.style)
		player:SetAttribute("TitleEffect", slot.effect)
		player:SetAttribute("TitleSet", slot.set)
		player:SetAttribute("TitleColors", table.concat(titleHexFor(slot.effect, slot.set), ","))
		player:SetAttribute("TitleSpeed", if slot.effect == "rgb" then (RGB_SPEED[slot.set] or 0.25) elseif slot.effect == "shimmer" then 0.35 else 0)
		player:SetAttribute("TitleShimmer", slot.effect == "shimmer")
		player:SetAttribute("TitleFont", slot.font)
		player:SetAttribute("TitleTextSize", slot.textSize)
		player:SetAttribute("TitleHeight", slot.height)
		player:SetAttribute("TitleDistance", slot.distance)
	end

	return {titleHexFor=titleHexFor, sanitizeTitleSlot=sanitizeTitleSlot, firstFilledSlot=firstFilledSlot, applyTitleAttributes=applyTitleAttributes}
end
