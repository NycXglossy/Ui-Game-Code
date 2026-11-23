--!strict
-- Shared static configuration for the Club Neon UI renderer.
-- Keep catalog, device profiles, shop data, and title allowlists in this bounded module.

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local C = {
	Base = Color3.fromRGB(13, 16, 24),
	Surface = Color3.fromRGB(21, 25, 37),
	SurfaceLight = Color3.fromRGB(31, 37, 52),
	Magenta = Color3.fromRGB(224, 112, 151),
	Cyan = Color3.fromRGB(119, 196, 203),
	Orange = Color3.fromRGB(220, 160, 108),
	Gold = Color3.fromRGB(226, 194, 132),
	Purple = Color3.fromRGB(116, 91, 153),
	Green = Color3.fromRGB(94, 184, 139),
	White = Color3.fromRGB(242, 241, 236),
	Muted = Color3.fromRGB(157, 164, 177),
	Red = Color3.fromRGB(218, 104, 112),
}
local FONT = Enum.Font.GothamMedium
local BOLD = Enum.Font.GothamBold
local ITALIC = Enum.Font.SourceSansItalic

local GENRES = {
	{id="rockstar", name="Rockstar Music", tagline="New tracks coming soon", color=Color3.fromRGB(226,194,132), tracks={
		{"temp-rockstar","Coming Soon — Rockstar Music","New music is on the way",1},
	}},
	{id="other", name="Other", tagline="More sounds beyond the main genres", color=Color3.fromRGB(119,196,203), tracks={}},
}

-- Renderer-side indexes are built from the same static genre catalog used by
-- the browser. Server catalog updates can extend these maps later, but queue
-- rendering must never depend on an optional update arriving first.
local ALL_TRACKS: {any} = {}
local TRACK_INDEX: {[string]: any} = {}
local TRACK_GENRE: {[string]: any} = {}
local TRACK_ARTWORK: {[string]: number} = {}

for _, genre in ipairs(GENRES) do
	for _, track in ipairs(genre.tracks) do
		local trackId = tostring(track[1] or "")
		if trackId ~= "" then
			TRACK_INDEX[trackId] = track
			TRACK_GENRE[trackId] = {
				id = genre.id,
				name = genre.name,
				color = genre.color,
			}
			table.insert(ALL_TRACKS, track)
		end
	end
end

local SHOP = {
	{name="2x Personal XP Pass",desc="Permanently doubles your personal XP. Stacks with active global XP boosts.",price=149,rarity="Rare",kind="GamePass",passKey="personalXP2x",ownedAttribute="HasPersonalXP2xPass",id=0},
	{name="4x Personal XP Pass",desc="Permanently quadruples your personal XP. Stacks with active global XP boosts.",price=399,rarity="Epic",kind="GamePass",passKey="personalXP4x",ownedAttribute="HasPersonalXP4xPass",id=0},
	{name="Island Mount Pass",desc="Unlock your permanent rideable island mount.",price=299,rarity="Legendary",kind="GamePass",passKey="mount",ownedAttribute="HasIslandMountPass",id=0},
	{name="VIP Backstage Pass",desc="Backstage lounge, priority song requests, 4 queue slots and 3s request cooldown.",price=1500,rarity="Legendary",kind="GamePass",passKey="vip",id=0},
	{name="VVIP Ocean Crown Pass",desc="Everything in VIP plus 6 queue slots, 2s cooldown and higher request priority.",price=2500,rarity="Mythic",kind="GamePass",passKey="vvip",id=0},
	{name="Club Neon Pass",desc="Ultimate island status: 8 queue slots, 1s cooldown and highest player-request priority.",price=4500,rarity="Exclusive",kind="GamePass",passKey="elite",id=0},
	{name="Island Companion Pass",desc="Unlock your exclusive tropical companion and an additional companion equip slot.",price=249,rarity="Epic",kind="GamePass",passKey="companion",ownedAttribute="HasIslandCompanionPass",id=0},
	{name="Stage & Club Lighting Pass",desc="Unlock the Stage & Club Lighting Controller and customize the performance atmosphere.",price=499,rarity="Mythic",kind="GamePass",passKey="stageClubLighting",ownedAttribute="HasStageClubLightingPass",id=0},
}
-- Donation products are configured with live Creator Dashboard Developer Product IDs.
local DONATIONS: {any} = {
	{ key = "Coconut", label = "Coconut", perk = "A little tropical love", amount = 10, productId = 0 },
	{ key = "Pineapple", label = "Pineapple", perk = "A burst of island sunshine", amount = 50, productId = 0 },
	{ key = "NeonTorch", label = "Neon Torch", perk = "Light up the island", amount = 100, productId = 0 },
	{ key = "Volcano", label = "Volcano", perk = "Unleash the island's fiery spirit", amount = 500, productId = 0 },
	{ key = "IslandLegend", label = "Island Legend", perk = "A legendary show of support", amount = 1000, productId = 0 },
	{ key = "IslandRoyalty", label = "Island Royalty", perk = "A royal contribution to paradise", amount = 5000, productId = 0 },
	{ key = "ClubNeonLegacy", label = "Club Neon Legacy", perk = "The ultimate island contribution", amount = 10000, productId = 0 },
}
local REWARDS = {
	{day=1,label="50 Coins"},{day=2,label="2x Glowsticks"},{day=3,label="100 Tickets"},
	{day=4,label="Song Skip Token"},{day=5,label="250 Coins"},{day=6,label="Neon Trail"},{day=7,label="Exclusive Title Tag"},
}
local TAGS = {
	{id="vip",label="VIP",source="VIP Pass",owned=false,a=Color3.fromRGB(244,114,182),b=Color3.fromRGB(217,70,239)},
	{id="party",label="Party Animal",source="Spend 10 hours at the festival",owned=false,a=Color3.fromRGB(251,146,60),b=Color3.fromRGB(252,211,77)},
	{id="wave",label="Wave Rider",source="7-day login streak",owned=false,a=Color3.fromRGB(103,232,249),b=Color3.fromRGB(14,165,233)},
	{id="neon",label="Neon Legend",source="400 Tickets • Festival shop",owned=false,price=400,a=Color3.fromRGB(252,211,77),b=Color3.fromRGB(239,68,68)},
	{id="sunset",label="Sunset Soul",source="250 Tickets • Festival shop",owned=false,price=250,a=Color3.fromRGB(236,72,153),b=Color3.fromRGB(253,224,71)},
	{id="bass",label="Bass Head",source="150 Tickets • Festival shop",owned=false,price=150,a=Color3.fromRGB(167,139,250),b=Color3.fromRGB(99,102,241)},
	{id="island",label="Island Royalty",source="Day 7 reward",owned=false,a=Color3.fromRGB(254,240,138),b=Color3.fromRGB(168,85,247)},
}

-- Device profiles: compact sizing for each platform.
-- base   = UIScale applied to the whole panel (smaller = more compact)
-- ref    = viewport the base scale is tuned for; smaller viewports shrink further (never below minF)
-- w / h  = panel size as a fraction of the screen
-- min/max= panel pixel limits (in unscaled UI units)
local PROFILES: {[string]: any} = {
	Desktop = { base = 1.00, refX = 1280, refY = 720, minF = 0.80, w = 0.68, h = 0.80,
		min = Vector2.new(360, 340), max = Vector2.new(1100, 820), toggle = 48, togglePos = UDim2.new(1, -14, 0.55, 0), hudTop = 8 },
	Tablet = { base = 0.92, refX = 1024, refY = 600, minF = 0.85, w = 0.72, h = 0.80,
		min = Vector2.new(320, 280), max = Vector2.new(820, 640), toggle = 52, togglePos = UDim2.new(1, -14, 0.5, 0), hudTop = 8 },
	Mobile = { base = 0.90, refX = 640, refY = 340, minF = 0.90, w = 0.94, h = 0.90,
		min = Vector2.new(280, 220), max = Vector2.new(640, 520), toggle = 44, togglePos = UDim2.new(1, -10, 0.35, 0), hudTop = 4 },
	VR = { base = 0.90, refX = 1280, refY = 720, minF = 0.90, w = 0.60, h = 0.70,
		min = Vector2.new(320, 300), max = Vector2.new(820, 640), toggle = 56, togglePos = UDim2.new(1, -24, 0.5, 0), hudTop = 40 },
	-- Consoles and smart TVs both report as Roblox's "ten-foot interface".
	Console = { base = 1.00, refX = 1280, refY = 720, minF = 1.00, w = 0.66, h = 0.76,
		min = Vector2.new(360, 320), max = Vector2.new(860, 660), toggle = 56, togglePos = UDim2.new(1, -48, 0.5, 0), hudTop = 36 },
}

local function detectDevice(viewport: Vector2): string
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

-- Developer Product IDs for the two paid title slots (0 = not configured; the server can override via state).
local TITLE_SLOT_PRODUCTS: {[number]: number} = { [2] = 0, [3] = 0 }
local XP_BOOST_PRODUCTS: {[string]: number} = { twoX = 0, fourX = 0 }
local TITLE_SLOT_PRICES: {[number]: number} = { [2] = 99, [3] = 199 }

local TITLE_FIXED = {
	{ id = "red", name = "Red", color = Color3.fromHex("#EF4444") },
	{ id = "darkred", name = "Dark Red", color = Color3.fromHex("#8B0000") },
	{ id = "crimson", name = "Crimson", color = Color3.fromHex("#DC143C") },
	{ id = "coral", name = "Coral", color = Color3.fromHex("#FF7F50") },
	{ id = "rose", name = "Rose", color = Color3.fromHex("#F43F5E") },
	{ id = "hotpink", name = "Hot Pink", color = Color3.fromHex("#FF69B4") },
	{ id = "pink", name = "Pink", color = Color3.fromHex("#EC4899") },
	{ id = "blue", name = "Blue", color = Color3.fromHex("#3B82F6") },
	{ id = "darkblue", name = "Dark Blue", color = Color3.fromHex("#00008B") },
	{ id = "skyblue", name = "Sky Blue", color = Color3.fromHex("#87CEEB") },
	{ id = "navy", name = "Navy", color = Color3.fromHex("#000080") },
	{ id = "cyan", name = "Cyan", color = Color3.fromHex("#00FFFF") },
	{ id = "aqua", name = "Aqua", color = Color3.fromHex("#00FFFF") },
	{ id = "turquoise", name = "Turquoise", color = Color3.fromHex("#40E0D0") },
	{ id = "green", name = "Green", color = Color3.fromHex("#22C55E") },
	{ id = "darkgreen", name = "Dark Green", color = Color3.fromHex("#006400") },
	{ id = "lime", name = "Lime", color = Color3.fromHex("#00FF00") },
	{ id = "mint", name = "Mint", color = Color3.fromHex("#98FFCC") },
	{ id = "emerald", name = "Emerald", color = Color3.fromHex("#50C878") },
	{ id = "olive", name = "Olive", color = Color3.fromHex("#808000") },
	{ id = "teal", name = "Teal", color = Color3.fromHex("#008080") },
	{ id = "purple", name = "Purple", color = Color3.fromHex("#A855F7") },
	{ id = "darkpurple", name = "Dark Purple", color = Color3.fromHex("#301934") },
	{ id = "violet", name = "Violet", color = Color3.fromHex("#8F00FF") },
	{ id = "lavender", name = "Lavender", color = Color3.fromHex("#E6E6FA") },
	{ id = "magenta", name = "Magenta", color = Color3.fromHex("#FF00FF") },
	{ id = "indigo", name = "Indigo", color = Color3.fromHex("#4B0082") },
	{ id = "yellow", name = "Yellow", color = Color3.fromHex("#FFFF00") },
	{ id = "gold", name = "Gold", color = Color3.fromHex("#FFD700") },
	{ id = "orange", name = "Orange", color = Color3.fromHex("#FFA500") },
	{ id = "darkorange", name = "Darkorange", color = Color3.fromHex("#FF8C00") },
	{ id = "amber", name = "Amber", color = Color3.fromHex("#FFBF00") },
	{ id = "peach", name = "Peach", color = Color3.fromHex("#FFE5B4") },
	{ id = "white", name = "White", color = Color3.fromHex("#FFFFFF") },
	{ id = "silver", name = "Silver", color = Color3.fromHex("#C0C0C0") },
	{ id = "gray", name = "Gray", color = Color3.fromHex("#808080") },
	{ id = "black", name = "Black", color = Color3.fromHex("#000000") },
	{ id = "brown", name = "Brown", color = Color3.fromHex("#8B4513") },
	{ id = "tan", name = "Tan", color = Color3.fromHex("#D2B48C") },
	{ id = "beige", name = "Beige", color = Color3.fromHex("#F5F5DC") },
	{ id = "maroon", name = "Maroon", color = Color3.fromHex("#800000") },
	{ id = "lightpink", name = "Light Pink", color = Color3.fromHex("#FFB6C1") },
	{ id = "neoongreen", name = "Neon Green", color = Color3.fromHex("#39FF14") },
	{ id = "salmon", name = "Salmon", color = Color3.fromHex("#FA8072") },
	{ id = "chartreuse", name = "Chartreuse", color = Color3.fromHex("#7FFF00") },
	{ id = "aquamarine", name = "Aquamarine", color = Color3.fromHex("#7FFFD4") },
	{ id = "steelblue", name = "Steel Blue", color = Color3.fromHex("#4682B4") },
	{ id = "deeppink", name = "Deep Pink", color = Color3.fromHex("#FF1493") },
	{ id = "tomato", name = "Tomato", color = Color3.fromHex("#FF6347") },
	{ id = "orchid", name = "Orchid", color = Color3.fromHex("#DA70D6") },
	{ id = "slateblue", name = "Slate Blue", color = Color3.fromHex("#6A5ACD") },
	{ id = "chocolate", name = "Chocolate", color = Color3.fromHex("#D2691E") },
	{ id = "periwinkle", name = "Periwinkle", color = Color3.fromHex("#CCCCFF") },
	{ id = "burntorange", name = "Burnt Orange", color = Color3.fromHex("#CC5500") },
	{ id = "midnightblue", name = "Midnight Blue", color = Color3.fromHex("#191970") },
	{ id = "springgreen", name = "Spring Green", color = Color3.fromHex("#00FF7F") },
	{ id = "coralpink", name = "Coral Pink", color = Color3.fromHex("#F88379") },
	{ id = "plum", name = "Plum", color = Color3.fromHex("#DDA0DD") },
	{ id = "royalblue", name = "Royal Blue", color = Color3.fromHex("#4169E1") },
	{ id = "mediumseagreen", name = "Medium Sea Green", color = Color3.fromHex("#3CB371") },
	{ id = "darkviolet", name = "Dark Violet", color = Color3.fromHex("#9400D3") },
	{ id = "deepskyblue", name = "Deep Sky Blue", color = Color3.fromHex("#00BFFF") },
	{ id = "dodgerblue", name = "Dodger Blue", color = Color3.fromHex("#1E90FF") },
	{ id = "cadetblue", name = "Cadet Blue", color = Color3.fromHex("#5F9EA0") },
	{ id = "slategray", name = "Slate Gray", color = Color3.fromHex("#708090") },
	{ id = "dimgray", name = "Dim Gray", color = Color3.fromHex("#696969") },
	{ id = "hotorange", name = "Hot Orange", color = Color3.fromHex("#FF4500") },
	{ id = "lavenderpink", name = "Lavender Pink", color = Color3.fromHex("#FBAED2") },
	{ id = "darkslateblue", name = "Dark Slate Blue", color = Color3.fromHex("#483D8B") },
	{ id = "mediumspringgreen", name = "Medium Spring Green", color = Color3.fromHex("#00FA9A") },
	{ id = "goldorange", name = "Gold Orange", color = Color3.fromHex("#DAA520") },
}
local TITLE_GRADIENTS = {
	{ id="amethyst", name="Amethyst", a=Color3.fromRGB(192,132,252), b=Color3.fromRGB(109,40,217) },
	{ id="aurora", name="Aurora", a=Color3.fromRGB(52,211,153), b=Color3.fromRGB(167,139,250) },
	{ id="candy", name="Candy", a=Color3.fromRGB(255,79,163), b=Color3.fromRGB(125,211,252) },
	{ id="cotton", name="Cotton", a=Color3.fromRGB(251,207,232), b=Color3.fromRGB(224,242,254) },
	{ id="cyber", name="Cyber", a=Color3.fromRGB(0,245,255), b=Color3.fromRGB(255,0,212) },
	{ id="desert", name="Desert", a=Color3.fromRGB(244,162,97), b=Color3.fromRGB(233,196,106) },
	{ id="emerald", name="Emerald", a=Color3.fromRGB(52,211,153), b=Color3.fromRGB(4,120,87) },
	{ id="fire", name="Fire", a=Color3.fromRGB(253,224,71), b=Color3.fromRGB(220,38,38) },
	{ id="forest", name="Forest", a=Color3.fromRGB(134,168,107), b=Color3.fromRGB(20,83,45) },
	{ id="galaxy", name="Galaxy", a=Color3.fromRGB(49,46,129), b=Color3.fromRGB(217,70,239) },
	{ id="ice", name="Ice", a=Color3.fromRGB(224,247,255), b=Color3.fromRGB(96,165,250) },
	{ id="lava", name="Lava", a=Color3.fromRGB(251,146,60), b=Color3.fromRGB(127,29,29) },
	{ id="midnight", name="Midnight", a=Color3.fromRGB(30,27,75), b=Color3.fromRGB(71,85,105) },
	{ id="neon", name="Neon", a=C.Cyan, b=C.Magenta },
	{ id="ocean", name="Ocean", a=C.Cyan, b=Color3.fromRGB(37,99,235) },
	{ id="pastel", name="Pastel", a=Color3.fromRGB(249,168,212), b=Color3.fromRGB(165,180,252) },
	{ id="purple", name="Purple", a=Color3.fromRGB(192,132,252), b=Color3.fromRGB(88,28,135) },
	{ id="rosegold", name="Rosegold", a=Color3.fromRGB(244,182,166), b=Color3.fromRGB(183,110,121) },
	{ id="royal", name="Royal", a=C.Gold, b=Color3.fromRGB(124,58,237) },
	{ id="sakura", name="Sakura", a=Color3.fromRGB(253,164,175), b=Color3.fromRGB(252,231,243) },
	{ id="sapphire", name="Sapphire", a=Color3.fromRGB(96,165,250), b=Color3.fromRGB(30,64,175) },
	{ id="sunset", name="Sunset", a=C.Orange, b=C.Magenta },
	{ id="thunder", name="Thunder", a=Color3.fromRGB(253,224,71), b=Color3.fromRGB(67,56,202) },
	{ id="tropical", name="Tropical", a=Color3.fromRGB(45,212,191), b=Color3.fromRGB(250,204,21) },
	{ id="volcano", name="Volcano", a=Color3.fromRGB(251,113,133), b=Color3.fromRGB(127,29,29) },
}
local TITLE_TWOTONES = table.clone(TITLE_GRADIENTS)
local TITLE_SHIMMERS = table.clone(TITLE_GRADIENTS)
local TITLE_RAINBOWS: {any} = {
	{ id = "classic", name = "Classic", s = 0.85, v = 1 },
	{ id = "pastel", name = "Pastel", s = 0.4, v = 1 },
	{ id = "neon", name = "Neon", s = 1, v = 1 },
	{ id = "deep", name = "Deep", s = 1, v = 0.8 },
}
-- Palette rainbow sets: every gradient palette is also a Rainbow color set (a flowing loop of its two colors).
-- "pastel" and "neon" already exist above as spectrum variants, so those two keep their original behavior.
do
	local taken: {[string]: boolean} = {}
	for _, existing in ipairs(TITLE_RAINBOWS) do taken[existing.id] = true end
	for _, palette in ipairs(TITLE_GRADIENTS) do
		if not taken[palette.id] then
			table.insert(TITLE_RAINBOWS, { id = palette.id, name = palette.name, a = palette.a, b = palette.b })
		end
	end
end
local TITLE_RGB_SPEEDS = {
	{ id = "slow", name = "Slow", speed = 0.12 },
	{ id = "normal", name = "Normal", speed = 0.25 },
	{ id = "fast", name = "Fast", speed = 0.5 },
}
local TITLE_EFFECTS = {
	{ id = "fixed", name = "Fixed", sets = TITLE_FIXED },
	{ id = "rgb", name = "RGB", sets = TITLE_RGB_SPEEDS },
	{ id = "gradient", name = "Gradient", sets = TITLE_GRADIENTS },
	{ id = "rainbow", name = "Rainbow", sets = TITLE_RAINBOWS },
	{ id = "twotone", name = "Two-Tone", sets = TITLE_TWOTONES },
	{ id = "shimmer", name = "Shimmer", sets = TITLE_SHIMMERS },
}
local TITLE_FONTS = {
	{ id = "gotham", name = "Gotham", font = Enum.Font.GothamBold },
	{ id = "gothammed", name = "Gotham Medium", font = Enum.Font.GothamMedium },
	{ id = "source", name = "Source", font = Enum.Font.SourceSans },
	{ id = "ubuntu", name = "Ubuntu", font = Enum.Font.Ubuntu },
	{ id = "roboto", name = "Roboto", font = Enum.Font.Roboto },
	{ id = "fredoka", name = "Fredoka", font = Enum.Font.FredokaOne },
	{ id = "bangers", name = "Bangers", font = Enum.Font.Bangers },
	{ id = "oswald", name = "Oswald", font = Enum.Font.Oswald },
	{ id = "nunito", name = "Nunito", font = Enum.Font.Nunito },
	{ id = "michroma", name = "Michroma", font = Enum.Font.Michroma },
	{ id = "fantasy", name = "Fantasy", font = Enum.Font.Fantasy },
	{ id = "arcade", name = "Arcade", font = Enum.Font.Arcade },
	{ id = "scifi", name = "Sci-Fi", font = Enum.Font.SciFi },
	{ id = "code", name = "Code", font = Enum.Font.Code },
}
local TITLE_STYLES = { "normal", "bold", "italic", "outline" }

return {
	C=C, FONT=FONT, BOLD=BOLD, ITALIC=ITALIC,
	GENRES=GENRES, ALL_TRACKS=ALL_TRACKS, TRACK_INDEX=TRACK_INDEX, TRACK_GENRE=TRACK_GENRE, TRACK_ARTWORK=TRACK_ARTWORK,
	SHOP=SHOP, DONATIONS=DONATIONS, REWARDS=REWARDS, TAGS=TAGS, PROFILES=PROFILES, detectDevice=detectDevice,
	TITLE_SLOT_PRODUCTS=TITLE_SLOT_PRODUCTS, XP_BOOST_PRODUCTS=XP_BOOST_PRODUCTS, TITLE_SLOT_PRICES=TITLE_SLOT_PRICES,
	TITLE_FIXED=TITLE_FIXED, TITLE_GRADIENTS=TITLE_GRADIENTS, TITLE_TWOTONES=TITLE_TWOTONES,
	TITLE_RAINBOWS=TITLE_RAINBOWS, TITLE_RGB_SPEEDS=TITLE_RGB_SPEEDS, TITLE_EFFECTS=TITLE_EFFECTS,
	TITLE_FONTS=TITLE_FONTS, TITLE_STYLES=TITLE_STYLES,
}
