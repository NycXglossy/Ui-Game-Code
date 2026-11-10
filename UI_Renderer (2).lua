--!strict
-- UI_Renderer
-- Place as ModuleScript: ReplicatedStorage/UI_Renderer
-- Complete native Roblox client UI for Firebeach Music Festival Club.
-- Privileged actions are delegated to UI_Network / UI_Server_Controller.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local GroupService = game:GetService("GroupService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Renderer = {}

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
	{id="hiphop", name="Hip Hop / Rap", tagline="Heavy bass, big bars", color=Color3.fromRGB(192,38,211), tracks={
		{"hh-0","Palm Tree Freestyle","Lil Coconut",184},{"hh-1","Tide Money","MC Lagoon",201},{"hh-2","Boardwalk Bounce","Kid Kahuna",176},{"hh-3","Sandcastle Kings","Reef Gang",213},{"hh-4","Midnight Luau","Big Pineapple",195},{"hh-5","Wave Check","Yung Tsunami",168}}},
	{id="rnb", name="R&B / Soul", tagline="Smooth sunset grooves", color=Color3.fromRGB(244,63,94), tracks={
		{"rnb-0","Golden Hour Love","Coral Rose",224},{"rnb-1","Slow Tide","Marina Soul",241},{"rnb-2","Tiki Torch Serenade","D'Angelo Bay",232},{"rnb-3","Velvet Shoreline","Honey Kai",207},{"rnb-4","Lantern Light","Nalu & The Keys",219}}},
	{id="rock", name="Rock", tagline="Amps up to eleven", color=Color3.fromRGB(234,88,12), tracks={
		{"rk-0","Volcano Riff","The Lava Kings",238},{"rk-1","Surf's Up Anthem","Riptide Rebels",199},{"rk-2","Driftwood Highway","Saltwater Saints",262},{"rk-3","Thunder on the Bay","Coral Crush",221}}},
	{id="kpop", name="K-Pop", tagline="Choreo-ready hits", color=Color3.fromRGB(236,72,153), tracks={
		{"kp-0","SUMMER GLITCH","NEONWAVE",192},{"kp-1","Pink Horizon","STARR1SE",205},{"kp-2","Island Signal","LUMI-9",187},{"kp-3","Heartbeat Lagoon","KORAL",199},{"kp-4","Firework Kiss","AURA X",181}}},
	{id="latin", name="Latin Music", tagline="Reggaeton & salsa heat", color=Color3.fromRGB(245,158,11), tracks={
		{"lt-0","Playa Caliente","DJ Mango",214},{"lt-1","Bailando en la Arena","Sol y Mar",228},{"lt-2","Noche Tropical","La Ola",203},{"lt-3","Fuego Lento","Rey Coco",197}}},
	{id="edm", name="EDM", tagline="Drops over the ocean", color=Color3.fromRGB(34,211,238), tracks={
		{"edm-0","Sunset Overdrive","Aqualux",246},{"edm-1","Neon Coastline","VOLTA",233},{"edm-2","Tidal Drop","Prism Reef",258},{"edm-3","Laser Lagoon","Kairo",219},{"edm-4","Afterglow Rave","SKYE.EXE",271},{"edm-5","Bassquake Beach","Subduction",205}}},
	{id="country", name="Country", tagline="Boots in the sand", color=Color3.fromRGB(234,179,8), tracks={
		{"ct-0","Beach Truck Blues","Dusty Shores",212},{"ct-1","Sunburnt Sweetheart","Cody Cove",198},{"ct-2","Barefoot Rodeo","The Palm Ranch",205}}},
	{id="pop", name="Pop", tagline="Sing-along anthems", color=Color3.fromRGB(139,92,246), tracks={
		{"pop-0","Electric Paradise","Mia Lumen",189},{"pop-1","Coconut Crush","Jade Rivers",176},{"pop-2","Ocean Eyes Tonight","Leo Starr",201},{"pop-3","Glow Up Summer","Nova Bay",183},{"pop-4","Postcard Heart","Kenna Blue",194}}},
	{id="exclusive", name="Club Exclusives", tagline="Only at Sunset Stage", color=Color3.fromRGB(255,46,147), tracks={
		{"ex-0","Sunset Stage Anthem","Club Resident",262},{"ex-1","Tiki Torch Theory","Club Resident ft. VOLTA",238},{"ex-2","Low-Poly Paradise","Pixel Palms",224},{"ex-3","Mainstage Moonrise","The Owners",289}}},
	{id="other", name="Other", tagline="More sounds beyond the main genres", color=Color3.fromRGB(119,196,203), tracks={}},
}

local TRACK_INDEX: {[string]: any} = {}
local TRACK_GENRE: {[string]: any} = {}
local TRACK_ARTWORK: {[string]: number} = {}
local ALL_TRACKS: {any} = {}
for _, genre in ipairs(GENRES) do
	for _, track in ipairs(genre.tracks) do
		TRACK_INDEX[track[1] :: string] = track
		TRACK_GENRE[track[1] :: string] = genre
		table.insert(ALL_TRACKS, track)
	end
end

local DONATIONS = {
	{amount=10,label="Coconut",perk="Shoutout in chat",productId=0},
	{amount=50,label="Pineapple",perk="Firework burst",productId=0},
	{amount=100,label="Tiki Torch",perk="Stage confetti",productId=0},
	{amount=500,label="Volcano",perk="Lava light show",productId=0},
	{amount=1000,label="Island Legend",perk="Name on the big screen",productId=0},
}
local SHOP = {
	{name="Custom Glowsticks",desc="Dual-wield glowsticks synced to stage lights.",price=75,rarity="Common",kind="Product",id=0},
	{name="Tiki Mask",desc="Hand-carved mask with glowing ember eyes.",price=250,rarity="Rare",kind="Product",id=0},
	{name="Neon Aura Effect",desc="A magenta-cyan aura that pulses on every beat.",price=600,rarity="Epic",kind="Product",id=0},
	{name="VIP Backstage Pass",desc="Backstage lounge, priority song requests, 4 queue slots and 3s request cooldown.",price=1500,rarity="Legendary",kind="GamePass",passKey="vip",id=0},
	{name="VVIP Ocean Crown Pass",desc="Everything in VIP plus 6 queue slots, 2s cooldown and higher request priority.",price=2500,rarity="Mythic",kind="GamePass",passKey="vvip",id=0},
	{name="Tiki Tide Sultan Pass",desc="Ultimate island status: 8 queue slots, 1s cooldown and highest player-request priority.",price=4500,rarity="Exclusive",kind="GamePass",passKey="sultan",id=0},
	{name="Neon Flower Lei",desc="Glowing hibiscus lei with petal trails.",price=150,rarity="Rare",kind="Product",id=0},
	{name="LED Party Shades",desc="Visualizer lenses that react to the current track.",price=320,rarity="Epic",kind="Product",id=0},
}
local REWARDS = {
	{day=1,label="50 Coins"},{day=2,label="2x Glowsticks"},{day=3,label="100 Tickets"},
	{day=4,label="Song Skip Token"},{day=5,label="250 Coins"},{day=6,label="Neon Trail"},{day=7,label="Exclusive Title Tag"},
}
local TAGS = {
	{id="vip",label="VIP",source="VIP Pass",owned=false,a=Color3.fromRGB(244,114,182),b=Color3.fromRGB(217,70,239)},
	{id="party",label="Party Animal",source="Spend 10 hours at the festival",owned=false,a=Color3.fromRGB(251,146,60),b=Color3.fromRGB(252,211,77)},
	{id="wave",label="Wave Rider",source="7-day login streak",owned=false,a=Color3.fromRGB(103,232,249),b=Color3.fromRGB(14,165,233)},
	{id="tiki",label="Tiki Legend",source="400 Tickets • Festival shop",owned=false,price=400,a=Color3.fromRGB(252,211,77),b=Color3.fromRGB(239,68,68)},
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
	Desktop = { base = 0.88, refX = 1280, refY = 720, minF = 0.80, w = 0.62, h = 0.74,
		min = Vector2.new(320, 300), max = Vector2.new(820, 640), toggle = 48, togglePos = UDim2.new(1, -14, 0.55, 0), hudTop = 8 },
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

local function safeCall(callback: any, ...)
	if typeof(callback) == "function" then
		local ok, err = pcall(callback, ...)
		if not ok then warn("[ClubMusic UI] " .. tostring(err)) end
	end
end

-- Client-side defense in depth only. The server must still validate every action,
-- permission, argument, cooldown, and ownership check independently.
local ALLOWED_ACTIONS: {[string]: boolean} = {
	ReloadSong = true, ToggleFavorite = true, RequestTrack = true, VoteSkip = true,
	RequestAudioAsset = true, CatalogAddAudio = true, CatalogRemoveTrack = true, DJSkip = true, DJToggleLock = true, DJClearQueue = true,
	DJMoveUp = true, DJRemove = true, DJPause = true, DJRestart = true, ModBlockUser = true, ModSetVip = true,
	ModPurgeUser = true, ClaimDailyReward = true, EquipTitleTag = true, BuyTitleTag = true,
	SaveTitleSlot = true, SetTitleVisible = true, SelectTitleSlot = true,
	ClearTitleSlot = true,
}
local ALLOWED_NETWORK_METHODS: {[string]: boolean} = {
	RequestTrack = true, ToggleFavorite = true, VoteSkip = true,
	DJSkip = true, DJMoveUp = true, DJRemove = true, DJPause = true, DJRestart = true, ClaimDailyReward = true,
	EquipTitleTag = true, BuyTitleTag = true, RequestAudioAsset = true, SaveTitleSlot = true,
	SaveCustomTitle = true,
	-- Wrappers that UI_Network exposes; act() prefers these over raw Network.Send.
	ReloadSong = true, DJClearQueue = true, DJToggleLock = true,
	ModBlockUser = true, ModSetVip = true, ModPurgeUser = true,
	SelectTitleSlot = true, ClearTitleSlot = true, SetTitleVisible = true,
}
local ACTION_MIN_INTERVAL: {[string]: number} = {
	RequestTrack = 0.35, RequestAudioAsset = 1.0, CatalogAddAudio = 10.0, CatalogRemoveTrack = 2.0, ReloadSong = 3.0,
	SaveTitleSlot = 0.35, ClaimDailyReward = 0.35,
}

local function sanitizeStateValue(value: any, depth: number, seen: {[any]: boolean}): any
	local kind = typeof(value)
	if kind == "string" then
		return string.sub(value, 1, 500)
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then return nil end
		return math.clamp(value, -1e9, 1e9)
	elseif kind == "boolean" then
		return value
	elseif kind ~= "table" or depth >= 5 or seen[value] then
		return nil
	end
	seen[value] = true
	local copy = {}
	local count = 0
	for key, child in pairs(value) do
		count += 1
		if count > 500 then break end
		if typeof(key) == "string" then
			copy[string.sub(key, 1, 80)] = sanitizeStateValue(child, depth + 1, seen)
		elseif typeof(key) == "number" and key == math.floor(key) and key >= 1 and key <= 10000 then
			copy[key] = sanitizeStateValue(child, depth + 1, seen)
		end
	end
	seen[value] = nil
	return copy
end

function Renderer.Mount(player: Player, Network: {[string]: any})
	assert(player and player:IsA("Player"), "Renderer.Mount expected a Player")
	assert(typeof(Network) == "table", "Renderer.Mount expected the UI_Network table")

	local playerGui = player:WaitForChild("PlayerGui")
	local connections: {RBXScriptConnection} = {}
	local destroyed = false
	local expanded = false
	local activeTab = "Home"
	local lastRenderedTab: string? = nil
	local selectedGenre = "hiphop"
	local musicSearchQuery = ""
	local trackSearch = ""
	local trackGenreFilter = "all"
	local catalogOffset = 0
	local catalogHasMore = false
	local catalogRequestSerial = 0
	local pendingCatalogRemoval: string? = nil
	local selectedPlaylistId: string? = nil
	local selectedPlaylistName: string? = nil
	local requestCatalogPage: (number) -> ()
	local volume = 0.8
	local lastVolume = 0.8
	local sliderDragging = false
	local lastReload = 0
	local audioInput = ""
	local artworkInput = ""
	local audioLookup: {[string]: any}? = nil
	local catalogGenreId = "exclusive"
	local lookupSerial = 0
	local previewAudio: AudioPlayer? = nil
	local previewFader: AudioFader? = nil
	local previewGraph: Folder? = nil
	local playerAudioPreferences: any = nil
	local playerMusicGroup: SoundGroup? = nil

	-- Player-local gain is applied only on this client to the canonical music
	-- SoundGroup. The server keeps MusicGroup at unity and remains playback owner.
	-- The same preference is mirrored to the local staff-preview fader.
	local preferencesFolder = ReplicatedStorage:FindFirstChild("ClubMusicClientAudioModules")
	local preferencesModule = preferencesFolder and preferencesFolder:FindFirstChild("ClubMusicPlayerPreferences")
	local musicGroupCandidate = SoundService:FindFirstChild("MusicGroup")
	if musicGroupCandidate and musicGroupCandidate:IsA("SoundGroup") then
		playerMusicGroup = musicGroupCandidate
	end
	if preferencesModule and preferencesModule:IsA("ModuleScript") and playerMusicGroup then
		local moduleOk, preferencesClass = pcall(require, preferencesModule)
		if moduleOk and typeof(preferencesClass) == "table" and typeof(preferencesClass.new) == "function" then
			local preferenceOk, preferenceInstance = pcall(preferencesClass.new, {
				SetLocalGain = function(gain: number): boolean
					if not playerMusicGroup or not playerMusicGroup.Parent then return false end
					playerMusicGroup.Volume = math.clamp(gain, 0, 1)
					if previewFader and previewFader.Parent then previewFader.Volume = math.clamp(gain, 0, 1) end
					return true
				end,
			})
			if preferenceOk then
				playerAudioPreferences = preferenceInstance
			else
				warn("[ClubMusic UI] Player audio preferences could not initialize: " .. tostring(preferenceInstance))
			end
		else
			warn("[ClubMusic UI] Player audio preference module failed to load: " .. tostring(preferencesClass))
		end
	end
	local previewId: number? = nil
	local renderTabFn: (() -> ())? = nil
	local hudBottom = 54
	local titleSub = "collection"
	local titleEditSlot = 1
	local titleDraft: {[string]: any}? = nil
	local titleAnimators: {(number) -> ()} = {}
	local applyStateFn: ((any) -> ())? = nil
	local state: {[string]: any} = {}
	local toastSerial = 0
	local lastActionAt: {[string]: number} = {}
	local lastAudioLookupAt = -math.huge

	local function perm(): number
		return tonumber(state.perm) or 0
	end

	local function nz(value: any, fallback: string): string
		if value == nil or value == "" then return fallback end
		return tostring(value)
	end

	-- Now-playing progress is interpolated locally between server resyncs.
	local elapsedBase = 0
	local baseClock = os.clock()
	local progressRefs: {fill: any, timeLabel: any, duration: number}? = nil
	local vizRefs: {container: any, bars: {any}, phases: {number}, seed: number}? = nil
	local sliderRefs: {track: any, control: GuiButton, setFromX: (number) -> (), adjust: (number) -> ()}? = nil

	local function syncElapsed()
		local np: any = state.nowPlaying
		if typeof(np) == "table" then
			elapsedBase = tonumber(np.elapsed) or 0
			baseClock = os.clock()
		end
	end

	local function playbackIsPaused(): boolean
		local np: any = state.nowPlaying
		return typeof(np) == "table" and np.paused == true
	end

	local function interpolatedElapsed(duration: number): number
		local elapsed = elapsedBase
		-- The server snapshot is authoritative. Do not locally advance the clock
		-- while paused; resume starts interpolation from the fresh server snapshot.
		if not playbackIsPaused() then
			elapsed += math.max(0, os.clock() - baseClock)
		end
		return math.clamp(elapsed, 0, duration)
	end

	local function updateProgress()
		local refs = progressRefs
		if not refs or not refs.fill.Parent then return end
		local elapsed = interpolatedElapsed(refs.duration)
		refs.fill.Size = UDim2.new(math.clamp(elapsed / refs.duration, 0, 1), 0, 1, 0)
		refs.fill.BackgroundColor3 = if playbackIsPaused() then C.Orange else C.Gold
		refs.timeLabel.Text = formatTime(elapsed) .. " / " .. formatTime(refs.duration)
	end

	local oldGui = playerGui:FindFirstChild("FirebeachMusicFestivalClubUI")
	if oldGui then oldGui:Destroy() end
	local legacyGui = playerGui:FindFirstChild("SunsetStageClubUI")
	if legacyGui then legacyGui:Destroy() end

	local gui = make("ScreenGui", {
		Name = "FirebeachMusicFestivalClubUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 40,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui) :: ScreenGui

	local layoutScale = 1

	local function notify(message: string, color: Color3?)
		toastSerial += 1
		local thisToast = toastSerial
		local toast = make("TextLabel", {
			Name = "Toast",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, hudBottom),
			Size = UDim2.new(0.9 / layoutScale, 0, 0, 42),
			BackgroundColor3 = C.SurfaceLight,
			BackgroundTransparency = 0,
			Text = message,
			TextColor3 = color or C.White,
			TextSize = 13,
			Font = BOLD,
			TextWrapped = true,
			ZIndex = 100,
		}, gui)
		corner(toast, 10)
		stroke(toast, color or C.Cyan, 1)
		make("UISizeConstraint", { MaxSize = Vector2.new(340, 42) }, toast)
		make("UIScale", { Scale = layoutScale }, toast)
		task.delay(2.6, function()
			if toast.Parent then
				local tween = TweenService:Create(toast, TweenInfo.new(0.2), {BackgroundTransparency=1, TextTransparency=1})
				tween:Play()
				tween.Completed:Once(function() if toast.Parent then toast:Destroy() end end)
			end
		end)
		return thisToast
	end

	local function send(action: string, payload: any?)
		if destroyed then return end
		if typeof(action) ~= "string" or not ALLOWED_ACTIONS[action] then
			warn("[ClubMusic UI] Blocked unknown client action.")
			return
		end
		if payload ~= nil and typeof(payload) ~= "table" then
			warn("[ClubMusic UI] Blocked malformed action payload: " .. action)
			return
		end
		local now = os.clock()
		local interval = ACTION_MIN_INTERVAL[action] or 0.10
		if now - (lastActionAt[action] or 0) < interval then return end
		lastActionAt[action] = now
		if typeof(Network.Send) ~= "function" then
			notify("Network action unavailable: " .. action, C.Red)
			return
		end
		local ok, result = pcall(Network.Send, action, payload or {})
		if not ok then
			warn("[ClubMusic UI] Send failed: " .. tostring(result))
			notify("Could not send request.", C.Red)
		end
	end

	local function callNetwork(method: string, ...)
		if destroyed then return end
		if typeof(method) ~= "string" or not ALLOWED_NETWORK_METHODS[method] then
			warn("[ClubMusic UI] Blocked unknown network method.")
			return
		end
		local fn = Network[method]
		-- Missing optional wrappers fall back to Network.Send at the call site.
		if typeof(fn) ~= "function" then return end
		local now = os.clock()
		local interval = ACTION_MIN_INTERVAL[method] or 0.10
		if now - (lastActionAt[method] or 0) < interval then return end
		lastActionAt[method] = now
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[ClubMusic UI] " .. method .. ": " .. tostring(err))
			notify("Action failed.", C.Red)
		end
	end

	local toggleButton = make("TextButton", {
		Name = "OpenButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.55, 0),
		Size = UDim2.fromOffset(54, 54),
		BackgroundColor3 = C.Magenta,
		Text = "",
		TextColor3 = C.White,
		TextSize = 28,
		Font = BOLD,
		AutoButtonColor = true,
		ZIndex = 10,
	}, gui) :: TextButton
	corner(toggleButton, 18)
	buildNativeIcon(toggleButton, "music", C.White, 11)
	local toggleOutline = stroke(toggleButton, C.Cyan, 2)
	bindFocusFeedback(toggleButton, toggleOutline, C.Magenta)

	-- Top bar HUD: a compact companion to the full festival panel, with matching surfaces and accents.
	local hud = make("TextButton", {
		Name = "TopBarHUD",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.96, 0, 0, 68),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = 0,
		Text = "",
		AutoButtonColor = false,
	}, gui) :: TextButton
	corner(hud, 18)
	local hudOutline = stroke(hud, C.Gold, 1.5)
	hudOutline.Transparency = 0.22
	bindFocusFeedback(hud, hudOutline, C.Surface)
	make("UIGradient", {
		Rotation = 0,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.SurfaceLight),
			ColorSequenceKeypoint.new(1, C.Surface),
		}),
	}, hud)
	local hudConstraint = make("UISizeConstraint", { MinSize = Vector2.new(260, 64), MaxSize = Vector2.new(760, 68) }, hud)
	local hudScale = make("UIScale", { Scale = 1 }, hud)
	local hudBars: {any} = {}
	local hudBarHolder = make("Frame", {
		Name = "HudFestivalMark",
		Position = UDim2.fromOffset(14, 17),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = C.SurfaceLight,
		BorderSizePixel = 0,
	}, hud)
	corner(hudBarHolder, 10)
	stroke(hudBarHolder, C.Gold, 1).Transparency = 0.48
	for i = 1, 4 do
		local piece = make("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 6 + (i - 1) * 6, 1, -6),
			Size = UDim2.new(0, 3, 0.3, 0),
			BackgroundColor3 = if i == 2 then C.Gold else C.Cyan:Lerp(C.Magenta, (i - 1) / 3),
			BorderSizePixel = 0,
		}, hudBarHolder)
		corner(piece, 1)
		hudBars[i] = piece
	end
	local hudEyebrow = make("TextLabel", {
		Name = "HudEyebrow",
		Position = UDim2.fromOffset(58, 7),
		Size = UDim2.new(1, -210, 0, 12),
		BackgroundTransparency = 1,
		Text = "FIREBEACH  /  NOW PLAYING",
		TextColor3 = C.Cyan,
		TextSize = 8,
		Font = BOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, hud)
	local hudTitle = make("TextLabel", {
		Position = UDim2.fromOffset(58, 19),
		Size = UDim2.new(1, -210, 0, 21),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = C.White,
		TextSize = 14,
		Font = BOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, hud)
	local hudArtist = make("TextLabel", {
		Position = UDim2.fromOffset(58, 41),
		Size = UDim2.new(1, -210, 0, 15),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = C.Muted,
		TextSize = 10,
		Font = FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, hud)
	local hudTime = make("TextLabel", {
		Name = "HudTrackTime",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 13),
		Size = UDim2.fromOffset(104, 16),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = C.Gold,
		TextSize = 10,
		Font = BOLD,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, hud)
	local hudStatus = make("TextLabel", {
		Name = "HudRequestStatus",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 34),
		Size = UDim2.fromOffset(104, 15),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = C.Cyan,
		TextSize = 9,
		Font = BOLD,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, hud)
	local hudTrack = make("Frame", {
		Position = UDim2.new(0, 14, 1, -5),
		Size = UDim2.new(1, -28, 0, 2),
		BackgroundColor3 = C.SurfaceLight,
		BorderSizePixel = 0,
	}, hud)
	corner(hudTrack, 2)
	local hudFill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Gold,
		BorderSizePixel = 0,
	}, hudTrack)
	corner(hudFill, 2)
	make("UIGradient", {
		Color = ColorSequence.new(C.Cyan, C.Magenta),
		Rotation = 0,
	}, hudFill)

	local function updateHud()
		local now: any = if typeof(state.nowPlaying) == "table" then state.nowPlaying else nil
		if now then
			local paused = playbackIsPaused()
			hudEyebrow.Text = if paused then "FIREBEACH  /  PLAYBACK PAUSED" else "FIREBEACH  /  NOW PLAYING"
			hudEyebrow.TextColor3 = if paused then C.Orange else C.Cyan
			hudTitle.Text = "♫  " .. nz(now.title, "Unknown track")
			hudArtist.Text = nz(now.artist, "Firebeach Music Festival")
			local duration = math.max(1, tonumber(now.duration) or 1)
			local elapsed = interpolatedElapsed(duration)
			hudFill.Size = UDim2.fromScale(math.clamp(elapsed / duration, 0, 1), 1)
			hudTime.Text = formatTime(elapsed) .. " / " .. formatTime(duration)
			hudTime.TextColor3 = if paused then C.Orange else C.Gold
			hudFill.BackgroundColor3 = if paused then C.Orange else C.Gold
		else
			hudEyebrow.Text = "FIREBEACH  /  STAGE STANDBY"
			hudEyebrow.TextColor3 = C.Muted
			hudTitle.Text = "♫  The stage is warming up"
			hudArtist.Text = "Sunset Stage Club"
			hudFill.Size = UDim2.fromScale(0, 1)
			hudTime.Text = ""
			hudTime.TextColor3 = C.Gold
			hudFill.BackgroundColor3 = C.Gold
		end
		if state.blocked == true then
			hudStatus.Text = "Requests off"
		elseif state.locked == true and perm() < 1 then
			hudStatus.Text = "Requests locked"
		else
			local req: any = if typeof(state.requests) == "table" then state.requests else {}
			hudStatus.Text = string.format("%sReq %d/%d", if state.vip == true then "★ " else "", tonumber(req.used) or 0, tonumber(req.limit) or 0)
		end
	end
	updateHud()

	local shade = make("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0,0,0),
		BackgroundTransparency = 1,
		Text = "",
		Visible = false,
		AutoButtonColor = false,
	}, gui) :: TextButton

	local panel = make("Frame", {
		Name = "MainPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.88, 0, 0.82, 0),
		BackgroundColor3 = C.Base,
		Visible = false,
		ClipsDescendants = true,
	}, gui) :: Frame
	corner(panel, 22)
	stroke(panel, C.Gold, 1.5)

	local sizeConstraint = make("UISizeConstraint", {
		MinSize = Vector2.new(320, 360),
		MaxSize = Vector2.new(920, 720),
	}, panel)
	local panelScale = make("UIScale", { Scale = 1 }, panel)
	local panelTarget = UDim2.new(0.88, 0, 0.82, 0)
	local currentDevice = "Desktop"
	local sideRailMode = false

	local header = make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 76),
		BackgroundColor3 = C.Surface,
		BorderSizePixel = 0,
	}, panel) :: Frame
	make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.SurfaceLight),
			ColorSequenceKeypoint.new(1, C.Surface),
		}),
		Rotation = 0,
	}, header)
	-- Header follows the panel's rounded top corners; the filler squares off its bottom edge.
	corner(header, 24)
	make("Frame", {
		Name = "HeaderSquare",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = C.Surface,
		BorderSizePixel = 0,
	}, header)
	-- Native geometric festival mark avoids emoji and font-glyph dependencies.
	local brandMark = make("Frame", {
		Name = "FestivalMark", Position = UDim2.fromOffset(14, 15),
		Size = UDim2.fromOffset(42, 42), BackgroundColor3 = C.SurfaceLight,
		BorderSizePixel = 0,
	}, header)
	corner(brandMark, 13)
	stroke(brandMark, C.Gold, 1).Transparency = 0.35
	for index, height in ipairs({13, 23, 17}) do
		local bar = make("Frame", {
			Name = "SoundBar" .. tostring(index), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.25 + (index - 1) * 0.25, 0, 0.5, 0),
			Size = UDim2.fromOffset(4, height),
			BackgroundColor3 = if index == 2 then C.Gold else C.Cyan,
			BorderSizePixel = 0,
		}, brandMark)
		corner(bar, 3)
	end
	local title = make("TextLabel", {
		Name = "FestivalTitle", Position = UDim2.fromOffset(66, 10),
		Size = UDim2.new(1, -154, 0, 30), BackgroundTransparency = 1,
		Text = "FIREBEACH MUSIC FESTIVAL", TextColor3 = C.White,
		TextSize = 20, TextScaled = true, Font = BOLD,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
	}, header) :: TextLabel
	make("UITextSizeConstraint", {MinTextSize = 11, MaxTextSize = 20}, title)
	local subtitle = make("TextLabel", {
		Name = "FestivalSubtitle", Position = UDim2.fromOffset(67, 42),
		Size = UDim2.new(1, -154, 0, 17), BackgroundTransparency = 1,
		Text = "CLUB  •  LIVE MUSIC  •  COMMUNITY", TextColor3 = C.Cyan,
		TextSize = 9, TextScaled = true, Font = BOLD,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
	}, header)
	make("UITextSizeConstraint", {MinTextSize = 7, MaxTextSize = 10}, subtitle)
	local closeButton = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = C.SurfaceLight,
		Text = "",
		TextColor3 = C.White,
		TextSize = 26,
		Font = FONT,
		Selectable = true,
	}, header) :: TextButton
	corner(closeButton, 12)
	buildNativeIcon(closeButton, "close", C.White, 2)
	local closeOutline = stroke(closeButton, C.SurfaceLight, 1)
	bindFocusFeedback(closeButton, closeOutline, C.SurfaceLight)

	local nav = make("ScrollingFrame", {
		Name = "Navigation",
		Position = UDim2.fromOffset(0, 76),
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = C.Surface,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.Gold,
		ScrollingDirection = Enum.ScrollingDirection.X,
		Active = true,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
	}, panel) :: ScrollingFrame
	local navLayout = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, nav) :: UIListLayout
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 5),
	}, nav)

	local content = make("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(12, 130),
		Size = UDim2.new(1, -24, 1, -142),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.Gold,
		Active = true,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		CanvasSize = UDim2.new(0,0,0,0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, panel) :: ScrollingFrame
	local contentLayout = make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 9),
	}, content)
	make("UIPadding", {
		PaddingBottom = UDim.new(0, 12),
	}, content)

	local navButtons: {[string]: TextButton} = {}
	local navIconLabels: {[string]: Frame} = {}
	local navTextLabels: {[string]: TextLabel} = {}
	local navIconBadges: {[string]: Frame} = {}
	local navGroupLabels: {TextLabel} = {}
	local navSelectionAccents: {[string]: Frame} = {}
	local navDivider = make("Frame", {
		Name = "NavigationDivider",
		Position = UDim2.fromOffset(150, 76),
		Size = UDim2.new(0, 1, 1, -76),
		BackgroundColor3 = C.Gold,
		BackgroundTransparency = 0.84,
		BorderSizePixel = 0,
		Visible = false,
	}, panel) :: Frame
	local tabs = {"Home","Music","All Tracks","Playlists","Queue","DJ Booth","XP & Boosts","Tip Jar","Item Shop","Daily Rewards","Title Tag","Community","Audio ID","Moderation"}
	local function addNavGroup(text: string, order: number)
		local heading = make("TextLabel", {
			Name = "NavGroup" .. text:gsub("%s", ""),
			Size = UDim2.fromOffset(136, 14),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = C.Cyan,
			TextSize = 8,
			Font = BOLD,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			LayoutOrder = order,
			Visible = false,
		}, nav) :: TextLabel
		table.insert(navGroupLabels, heading)
	end
	addNavGroup("LISTEN", 10)
	addNavGroup("FESTIVAL", 70)
	addNavGroup("STAFF", 130)
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
		elseif tabName == "All Tracks" then
			for i = 0, 2 do
				line("TrackLine"..i, .22, .27 + i * .23, .56, .065)
				if i < 2 then navIconPart(icon, "TrackDot"..i, .13, .265 + i * .23, .09, .09, ink, 1) end
			end
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
		elseif tabName == "XP & Boosts" then
			line("SparkleVertical", .47, .12, .07, .76); line("SparkleHorizontal", .12, .46, .76, .07)
			line("SparkleDiagA", .30, .29, .07, .40, 45); line("SparkleDiagB", .30, .29, .07, .40, -45)
		elseif tabName == "Tip Jar" then
			ring("JarBody", .25, .34, .50, .48); line("JarRim", .23, .29, .54, .07)
			line("JarBase", .34, .83, .32, .07); ring("Coin", .39, .10, .22, .22)
		elseif tabName == "Item Shop" then
			ring("BagBody", .22, .35, .56, .48); line("BagHandle", .36, .20, .28, .07)
			line("BagHandleLeft", .34, .22, .07, .20, -18); line("BagHandleRight", .59, .22, .07, .20, 18)
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

	local function clearContent()
		progressRefs = nil
		titleAnimators = {}
		vizRefs = nil
		sliderRefs = nil
		for _, child in ipairs(content:GetChildren()) do
			if child ~= contentLayout and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
	end

	local function sectionLabel(text: string)
		-- Compact editorial section heading with a restrained accent rule.
		-- Kept at the same 30px layout height so existing tab spacing is unchanged.
		local heading = make("Frame", {
			Name = "SectionHeading",
			Size = UDim2.new(1, -4, 0, 30),
			BackgroundTransparency = 1,
		}, content) :: Frame
		local marker = make("Frame", {
			Name = "SectionMarker",
			Position = UDim2.fromOffset(1, 8),
			Size = UDim2.fromOffset(3, 14),
			BackgroundColor3 = C.Gold,
			BorderSizePixel = 0,
		}, heading)
		corner(marker, 2)
		make("TextLabel", {
			Name = "SectionTitle",
			Position = UDim2.fromOffset(11, 0),
			Size = UDim2.new(1, -18, 0, 25),
			BackgroundTransparency = 1,
			Text = string.upper(text),
			TextColor3 = C.Gold,
			TextSize = 12,
			Font = BOLD,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
		}, heading)
		local rule = make("Frame", {
			Name = "SectionRule",
			Position = UDim2.fromOffset(11, 26),
			Size = UDim2.new(1, -18, 0, 1),
			BackgroundColor3 = C.SurfaceLight,
			BackgroundTransparency = 0.28,
			BorderSizePixel = 0,
		}, heading)
		make("Frame", {
			Name = "SectionRuleAccent",
			Size = UDim2.new(0, 34, 1, 0),
			BackgroundColor3 = C.Gold,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
		}, rule)
		return heading
	end

	local function card(height: number?, parent: Instance?): Frame
		height = height or 72
		local frame = make("Frame", {
			Size = UDim2.new(1, -4, 0, height),
			BackgroundColor3 = C.Surface,
			BorderSizePixel = 0,
		}, parent or content) :: Frame
		corner(frame, 17)
		local outline = stroke(frame, C.SurfaceLight, 1)
		outline.Transparency = 0.26
		make("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(29, 34, 48)),
				ColorSequenceKeypoint.new(1, C.Surface),
			}),
			Rotation = 90,
		}, frame)
		-- Restrained top sheen and a rounded champagne accent; no drop shadow.
		make("Frame", {
			Name = "CardTopSheen",
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 0, 1),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.91,
			BorderSizePixel = 0,
		}, frame)
		local accent = make("Frame", {
			Name = "AccentEdge",
			Position = UDim2.fromOffset(0, 14),
			Size = UDim2.fromOffset(3, math.max(18, (height or 72) - 28)),
			BackgroundColor3 = C.Gold,
			BorderSizePixel = 0,
		}, frame)
		corner(accent, 2)
		make("UIGradient", {
			Color = ColorSequence.new(C.Gold, C.Magenta),
			Rotation = 90,
		}, accent)
		return frame
	end

	local function label(parent: Instance, text: string, position: UDim2, size: UDim2, color: Color3?, textSize: number?, bold: boolean?)
		return make("TextLabel", {
			Position = position,
			Size = size,
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = color or C.White,
			TextSize = textSize or 13,
			Font = if bold then BOLD else FONT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextWrapped = true,
		}, parent)
	end

	local function actionButton(parent: Instance, text: string, position: UDim2, size: UDim2, callback: () -> (), color: Color3?)
		local iconKind = if text == "↻ RELOAD" then "reload"
			elseif text == "↻ RESTART" then "restart"
			elseif text == "★" or text == "☆" then "star"
			elseif text == "▲" or text == "↑" then "up"
			elseif text == "▼" or text == "↓" then "down"
			elseif text == "✕" then "close"
			elseif text == "−" then "minus" else nil
		local semanticColor = color or C.Magenta
		local upperText = string.upper(text)
		if color == nil or color == C.SurfaceLight then
			if string.find(upperText, "BUY", 1, true) or string.find(upperText, "GET", 1, true)
				or string.find(upperText, "CLAIM", 1, true) or string.find(upperText, "EQUIP", 1, true)
				or string.find(upperText, "TIP", 1, true) then semanticColor = C.Gold
			elseif string.find(upperText, "CLEAR", 1, true) or string.find(upperText, "STOP", 1, true)
				or string.find(upperText, "LOCK", 1, true) or string.find(upperText, "REMOVE", 1, true) then semanticColor = C.Red
			elseif string.find(upperText, "PAUSE", 1, true) or string.find(upperText, "RESUME", 1, true)
				or string.find(upperText, "EDIT", 1, true) or string.find(upperText, "OPEN", 1, true) then semanticColor = C.Cyan
			elseif string.find(upperText, "LIKE", 1, true) or string.find(upperText, "VOTE", 1, true)
				or string.find(upperText, "SKIP", 1, true) then semanticColor = C.Purple
			end
		end
		-- Every caller owns its layout geometry. Never enlarge a control here:
		-- doing so makes paired/stacked controls overlap on compact screens.
		local resolvedSize = size
		local displayText = if iconKind == "restart" then "RESTART" elseif iconKind == "reload" then "RELOAD" elseif iconKind then "" else text
		local button = make("TextButton", {
			Position = position,
			Size = resolvedSize,
			BackgroundColor3 = semanticColor,
			Text = displayText,
			TextColor3 = C.White,
			TextSize = if #displayText > 15 then 10 else (#displayText > 10 and 11 or 12),
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = BOLD,
			AutoButtonColor = false,
			Selectable = true,
			Active = true,
		}, parent) :: TextButton
		button:SetAttribute("ClubActionControl", true)
		local hasInlineIcon = iconKind == "reload" or iconKind == "restart"
		corner(button, if hasInlineIcon then 10 else 11)
		if hasInlineIcon then
			local iconColor = if iconKind == "restart" then C.White else C.Gold
			local inlineIcon = buildNativeIcon(button, iconKind, iconColor, 2)
			inlineIcon.Position = UDim2.new(0, 13, 0.5, 0)
			inlineIcon.Size = UDim2.fromOffset(22, 22)
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.TextYAlignment = Enum.TextYAlignment.Center
			button.TextSize = 10
			button.TextWrapped = false
			button.TextTruncate = Enum.TextTruncate.AtEnd
			make("UIPadding", {PaddingLeft=UDim.new(0, 29), PaddingRight=UDim.new(0, 5)}, button)
		elseif iconKind then
			buildNativeIcon(button, iconKind, C.White, 2)
		end
		local outline = stroke(button, if hasInlineIcon then (if iconKind == "reload" then C.Gold else C.Cyan) else semanticColor, if hasInlineIcon then 1.5 else 1.15)
		outline.Transparency = if hasInlineIcon then 0.22 else 0.42
		bindFocusFeedback(button, outline, semanticColor)
		make("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, semanticColor:Lerp(C.White, 0.12)),
				ColorSequenceKeypoint.new(1, semanticColor:Lerp(C.Base, 0.24)),
			}),
			Rotation = 90,
		}, button)
		local scale = make("UIScale", {Scale = 1}, button) :: UIScale
		local function animateScale(target: number, duration: number)
			TweenService:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = target}):Play()
		end
		-- Keep hover/focus feedback inside the button bounds so adjacent
		-- controls never visually collide; the outline carries the emphasis.
		button.MouseEnter:Connect(function() animateScale(1, 0.12) end)
		button.MouseLeave:Connect(function() animateScale(1, 0.12) end)
		button.Activated:Connect(function()
			animateScale(0.99, 0.06)
			callback()
			task.delay(0.07, function()
				if button.Parent then animateScale(1, 0.12) end
			end)
		end)
		return button
	end
	local function act(method: string, payload: {[string]: any}, ...)
		if typeof(Network[method]) == "function" then
			callNetwork(method, ...)
		else
			send(method, payload)
		end
	end

	local function requestsDisabled(): (boolean, string)
		if state.blocked == true then
			return true, "Staff disabled your song requests."
		end
		if state.locked == true and perm() < 1 then
			return true, "Song requests are locked right now."
		end
		return false, ""
	end

	-- Volume is strictly client-local: preferences modify this client's replicated
	-- SoundGroup instance and the local preview fader, never a server RemoteFunction.
	local function applyVolume(value: number)
		volume = math.clamp(value, 0, 1)
		if volume > 0 then lastVolume = volume end
		gui:SetAttribute("Volume", volume)
		if playerAudioPreferences then
			local ok, accepted = pcall(function() return playerAudioPreferences:SetVolume(volume) end)
			if not ok or accepted ~= true then
				warn("[ClubMusic UI] Local volume preference could not be applied.")
			end
		else
			if playerMusicGroup and playerMusicGroup.Parent then playerMusicGroup.Volume = volume end
			if previewFader and previewFader.Parent then previewFader.Volume = volume end
		end
	end

	local function reloadSong()
		if os.clock() - lastReload < 3 then
			notify("Please wait a moment before reloading again.", C.Orange)
			return
		end
		lastReload = os.clock()
		act("ReloadSong", {})
		if typeof(Network.GetState) == "function" and applyStateFn then
			local ok, fresh = pcall(Network.GetState)
			if ok and typeof(fresh) == "table" then applyStateFn(fresh) end
		end
		notify("Reloading song…", C.Cyan)
	end

	local currentTrackId: any

	local function buildNowPlaying(parent: Instance?, artworkMode: boolean?, expandedMode: boolean?)
		parent = parent or content
		local now: any = if typeof(state.nowPlaying) == "table" then state.nowPlaying else {}
		local showArtwork = artworkMode == true
		local expandedArtwork = expandedMode == true
		local stackedArtwork = expandedArtwork and currentDevice == "Mobile"
		local leftInset = if stackedArtwork then 14 elseif showArtwork then 108 else 14
		local rightInset = if stackedArtwork then 14 elseif showArtwork then 122 else 28
		local nowCard = card(if stackedArtwork then 354 elseif expandedArtwork then 228 elseif showArtwork then 210 else 182, parent)
		local live = typeof(state.nowPlaying) == "table"
		if showArtwork then
			local genre = TRACK_GENRE[currentTrackId(now) or ""]
			local tint = if genre then genre.color else C.Magenta
			local art = make("Frame", {
				Name = "NowPlayingArtwork",
				Position = if stackedArtwork then UDim2.new(0.5, -44, 0, 34) else UDim2.fromOffset(14, 72),
				Size = UDim2.fromOffset(if stackedArtwork then 88 elseif expandedArtwork then 112 else 82, if stackedArtwork then 88 elseif expandedArtwork then 112 else 82),
				BackgroundColor3 = C.Base,
				BorderSizePixel = 0,
			}, nowCard)
			corner(art, 13)
			stroke(art, tint, 1.4).Transparency = 0.2
			local artworkId = tonumber(now.artworkAssetId) or TRACK_ARTWORK[currentTrackId(now) or ""]
			if artworkId and artworkId > 0 then
				make("ImageLabel", {Name="CatalogArtwork", Size=UDim2.fromScale(1, 1), BackgroundTransparency=1, Image="rbxassetid://" .. tostring(artworkId), ScaleType=Enum.ScaleType.Crop}, art)
			else
				make("UIGradient", {
					Color = ColorSequence.new(tint:Lerp(C.Base, 0.12), C.Base),
					Rotation = 135,
				}, art)
				local vinyl = make("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.48),
					Size = UDim2.fromOffset(54, 54),
					BackgroundColor3 = C.Base,
					BorderSizePixel = 0,
				}, art)
				corner(vinyl, 27)
				stroke(vinyl, tint, 1.2).Transparency = 0.18
				local center = make("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(15, 15),
					BackgroundColor3 = tint,
					BorderSizePixel = 0,
				}, vinyl)
				corner(center, 8)
				label(art, if genre then string.upper(string.sub(genre.name, 1, 12)) else "SUNSET MIX",
					UDim2.new(0, 4, 1, -19), UDim2.new(1, -8, 0, 14), C.White, 8, true)
			end
		end

		label(nowCard, nz(now.title, "The stage is warming up"), if stackedArtwork then UDim2.fromOffset(12, 130) else UDim2.fromOffset(leftInset, 8), if stackedArtwork then UDim2.new(1, -24, 0, 25) else UDim2.new(1, -(rightInset + 88), 0, 24), C.White, if stackedArtwork then 15 else 16, true)
		local paused = live and now.paused == true
		local liveColor = if paused then C.Orange elseif live then C.Green else C.SurfaceLight
		local liveBadge = make("TextLabel", {
			Position = UDim2.new(1, -92, 0, 8),
			Size = UDim2.fromOffset(78, 24),
			BackgroundColor3 = liveColor:Lerp(C.Base, 0.22),
			Text = if paused then "PAUSED" elseif live then "ON AIR" else "STANDBY",
			TextColor3 = liveColor:Lerp(C.White, 0.35),
			TextSize = 9,
			Font = BOLD,
		}, nowCard)
		corner(liveBadge, 8)
		local liveBadgeStroke = stroke(liveBadge, liveColor, 1)
		liveBadgeStroke.Transparency = 0.55
		make("Frame", {Name="PlayerAccent", Position=if stackedArtwork then UDim2.fromOffset(12, 184) else UDim2.fromOffset(leftInset, 58), Size=UDim2.new(1, -(leftInset + 14), 0, 2), BackgroundColor3=C.Gold, BackgroundTransparency=0.48, BorderSizePixel=0}, nowCard)
		local detail = nz(now.artist, "Firebeach Music Festival")
		if now.source == "player" and nz(now.requestedBy, "") ~= "" then
			detail ..= "  •  requested by " .. tostring(now.requestedBy)
		end
		label(nowCard, detail, if stackedArtwork then UDim2.fromOffset(12, 156) else UDim2.fromOffset(leftInset, 34), UDim2.new(1, -(leftInset + 14), 0, 18), C.Muted, 11, false)
		local bar = make("Frame", {
			Position = UDim2.fromOffset(leftInset, if stackedArtwork then 196 else 66),
			Size = UDim2.new(1, -(leftInset + 14), 0, 6),
			BackgroundColor3 = C.SurfaceLight,
			BorderSizePixel = 0,
		}, nowCard)
		corner(bar, 3)
		local fill = make("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = C.Gold,
			BorderSizePixel = 0,
		}, bar)
		corner(fill, 3)
		local timeLabel = label(nowCard, "0:00 / 0:00", UDim2.fromOffset(leftInset, if stackedArtwork then 207 else 78), UDim2.new(1, if stackedArtwork then -120 else -220, 0, 22), C.Gold, 10, true)
		progressRefs = { fill = fill, timeLabel = timeLabel, duration = math.max(1, tonumber(now.duration) or 1) }
		updateProgress()

		-- Reload song button
		actionButton(nowCard, "↻ RELOAD", UDim2.new(1, -116, 0, if stackedArtwork then 204 else 75), UDim2.fromOffset(104, 26), reloadSong, Color3.fromRGB(66, 54, 91))

		-- Audio visualizer
		local vizFrame = make("Frame", {
			Name = "Visualizer",
			Position = UDim2.fromOffset(leftInset, if stackedArtwork then 236 else 106),
			Size = UDim2.new(1, -(leftInset + 14), 0, 32),
			BackgroundColor3 = C.Base,
			BorderSizePixel = 0,
		}, nowCard)
		corner(vizFrame, 8)
		local barHolder = make("Frame", {
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 1, -8),
			BackgroundTransparency = 1,
		}, vizFrame)
		local count = 28
		local seed = 0
		for i = 1, #tostring(now.id or now.trackId or now.title or "x") do
			seed += string.byte(tostring(now.id or now.trackId or now.title or "x"), i)
		end
		local bars: {any} = {}
		local phases: {number} = {}
		for i = 1, count do
			local t = (i - 1) / (count - 1)
			local piece = make("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new((i - 1) / count, 1, 1, 0),
				Size = UDim2.new(1 / count, -2, 0.1, 0),
				BackgroundColor3 = C.Magenta:Lerp(C.Cyan, t),
				BorderSizePixel = 0,
			}, barHolder)
			corner(piece, 2)
			bars[i] = piece
			phases[i] = ((seed * 31 + i * 17) % 100) / 100 * math.pi * 2
		end
		vizRefs = { container = barHolder, bars = bars, phases = phases, seed = seed % 97 }

		-- Volume slider
		local muteButton = make("TextButton", {
			Position = UDim2.fromOffset(leftInset, if stackedArtwork then 282 else 148),
			Size = UDim2.fromOffset(30, 26),
			BackgroundColor3 = C.SurfaceLight,
			Text = "",
			TextColor3 = C.White,
			TextSize = 14,
			Font = BOLD,
		}, nowCard) :: TextButton
		corner(muteButton, 8)
		local muteOutline = stroke(muteButton, C.Cyan, 1)
		bindFocusFeedback(muteButton, muteOutline, C.SurfaceLight)
		local volumeIcon = buildNativeIcon(muteButton, "volume", C.White, 2)
		local track = make("Frame", {
			Position = UDim2.fromOffset(leftInset + 42, if stackedArtwork then 291 else 157),
			Size = UDim2.new(1, -(leftInset + 128), 0, 8),
			BackgroundColor3 = C.SurfaceLight,
			BorderSizePixel = 0,
		}, nowCard) :: Frame
		corner(track, 4)
		local volFill = make("Frame", {
			Size = UDim2.fromScale(volume, 1),
			BackgroundColor3 = C.Cyan,
			BorderSizePixel = 0,
		}, track)
		corner(volFill, 4)
		local knob = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(volume, 0, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = C.White,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, track)
		corner(knob, 8)
		local percent = label(nowCard, "", UDim2.new(1, -66, 0, if stackedArtwork then 282 else 148), UDim2.fromOffset(52, 26), C.Cyan, 11, true)
		percent.TextXAlignment = Enum.TextXAlignment.Right
		local hit = make("TextButton", {
			Name = "VolumeHit",
			Position = UDim2.fromOffset(leftInset + 42, if stackedArtwork then 282 else 148),
			Size = UDim2.new(1, -(leftInset + 128), 0, 26),
			BackgroundColor3 = C.SurfaceLight,
			BackgroundTransparency = 0.82,
			Text = "",
			AutoButtonColor = false,
			Selectable = true,
			Active = true,
		}, nowCard) :: TextButton
		corner(hit, 7)
		local sliderOutline = stroke(hit, C.Cyan, 1)
		bindFocusFeedback(hit, sliderOutline, C.SurfaceLight)

		local function refreshVolumeUI()
			volFill.Size = UDim2.fromScale(volume, 1)
			knob.Position = UDim2.new(volume, 0, 0.5, 0)
			percent.Text = string.format("%d%%", math.floor(volume * 100 + 0.5))
			for _, arc in ipairs(volumeIcon:GetChildren()) do
				if arc:IsA("Frame") and arc:GetAttribute("SoundArc") == true then arc.Visible = volume > 0 end
			end
		end
		refreshVolumeUI()

		local function setFromX(x: number)
			if not track.Parent or track.AbsoluteSize.X <= 0 then return end
			local relative = (x - (track.AbsolutePosition.X - gui.AbsolutePosition.X)) / track.AbsoluteSize.X
			applyVolume(math.clamp(relative, 0, 1))
			refreshVolumeUI()
		end
		local function adjustVolume(delta: number)
			applyVolume(volume + delta)
			refreshVolumeUI()
		end
		sliderRefs = { track = track, control = hit, setFromX = setFromX, adjust = adjustVolume }

		hit.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				sliderDragging = true
				setFromX(input.Position.X)
			end
		end)
		muteButton.Activated:Connect(function()
			applyVolume(if volume > 0 then 0 else (if lastVolume > 0 then lastVolume else 0.8))
			refreshVolumeUI()
		end)
	end

	local function makeTrackCard(track: {any}, parent: Instance?, allowCatalogRemoval: boolean?, targetPlaylistId: string?)
		local id = tostring(track[1])
		local canRemove = allowCatalogRemoval == true and perm() >= 1 and string.sub(id, 1, 7) == "custom-"
		local canAddToPlaylist = targetPlaylistId ~= nil and perm() >= 1
		local compact = currentDevice == "Mobile"
		local frame = make("Frame", {
			Size = UDim2.new(1, -4, 0, if compact then 84 else 66),
			BackgroundColor3 = C.Surface,
			BorderSizePixel = 0,
		}, parent or content)
		corner(frame, 13)
		local trackStroke = stroke(frame, C.SurfaceLight, 1)
		trackStroke.Transparency = 0.38
		make("Frame", {Name="TrackAccent", Position=UDim2.fromOffset(0, if compact then 8 else 12), Size=UDim2.fromOffset(2, if compact then 68 else 42), BackgroundColor3=C.Gold, BackgroundTransparency=0.28, BorderSizePixel=0}, frame)

		local artworkId = TRACK_ARTWORK[id]
		local textX = if artworkId then 66 else 12
		local artworkWidth = if artworkId then 54 else 0
		local titleInset = (if compact then (if string.sub(id, 1, 7) == "custom-" then -76 else -14) else (if canAddToPlaylist then (if canRemove then -330 else -250) else (if canRemove then -250 else -176))) - artworkWidth
		local artistInset = if compact then -14 - artworkWidth else titleInset
		if artworkId then
			local cover = make("ImageLabel", {Name="CatalogArtwork", Position=UDim2.fromOffset(12, 8), Size=UDim2.fromOffset(46, 46), BackgroundColor3=C.Base, BorderSizePixel=0, Image="rbxassetid://" .. tostring(artworkId), ScaleType=Enum.ScaleType.Crop}, frame)
			corner(cover, 8)
		end
		label(frame, tostring(track[2]), UDim2.fromOffset(textX, if compact then 4 else 8), UDim2.new(1, titleInset, 0, 22), C.White, 13, true)
		label(frame, tostring(track[3]) .. "  •  " .. formatTime(tonumber(track[4]) or 0), UDim2.fromOffset(textX, if compact then 25 else 32), UDim2.new(1, artistInset, 0, 18), C.Muted, 11, false)

		local favorites: any = state.favorites
		local isFavorite = typeof(favorites) == "table" and favorites[id] == true
		local starPosition = if compact then
			(if canAddToPlaylist then (if canRemove then -218 else -150) else (if canRemove then -166 else -132))
		else (if canAddToPlaylist then (if canRemove then -282 else -202) else (if canRemove then -202 else -138))
		local requestPosition = if compact then
			(if canAddToPlaylist then (if canRemove then -184 else -116) else (if canRemove then -132 else -90))
		else (if canAddToPlaylist then (if canRemove then -240 else -160) else (if canRemove then -160 else -96))
		local buttonY = if compact then 49 else 18
		local starWidth = if compact then (if canAddToPlaylist or canRemove then 28 else 32) else 32
		local star = actionButton(frame, if isFavorite then "★" else "☆", UDim2.new(1, starPosition, 0, buttonY), UDim2.fromOffset(starWidth, 30), function()
			act("ToggleFavorite", { trackId = id }, id)
		end, C.SurfaceLight)
		star.TextSize = 16
		star.TextColor3 = if isFavorite then C.Gold else C.Muted

		local disabled, reason = requestsDisabled()
		local requestWidth = if compact then (if canAddToPlaylist then 68 elseif canRemove then 72 else 82) else 84
		actionButton(frame, if disabled then "LOCKED" else "REQUEST", UDim2.new(1, requestPosition, 0, buttonY), UDim2.fromOffset(requestWidth, 30), function()
			if disabled then
				notify(reason, C.Orange)
				return
			end
			act("RequestTrack", { trackId = id }, id)
		end, if disabled then C.SurfaceLight else C.Purple)

		if canAddToPlaylist then
			local addPosition = if compact then (if canRemove then -112 else -58) else (if canRemove then -148 else -72)
			local addWidth = if compact then (if canRemove then 48 else 50) else 66
			actionButton(frame, "ADD", UDim2.new(1, addPosition, 0, buttonY), UDim2.fromOffset(addWidth, 30), function()
				send("PlaylistAddTrack", {playlistId = targetPlaylistId, trackId = id})
				notify("Adding track to selected playlist…", C.Cyan)
				task.delay(1.1, function()
					if not destroyed and renderTabFn then renderTabFn() end
				end)
			end, C.Green)
		end

		if canRemove then
			local removeButton: TextButton
			local removePosition = if compact then -58 else -72
			local removeWidth = if compact then 52 else 66
			removeButton = actionButton(frame, "REMOVE", UDim2.new(1, removePosition, 0, buttonY), UDim2.fromOffset(removeWidth, 30), function()
				if pendingCatalogRemoval ~= id then
					pendingCatalogRemoval = id
					removeButton.Text = "CONFIRM?"
					notify("Click CONFIRM? again to remove this custom catalog track.", C.Orange)
					return
				end
				pendingCatalogRemoval = nil
				removeButton.Text = "SENT"
				send("CatalogRemoveTrack", {trackId = id})
				notify("Removal request sent. The server will reject removal if the track is playing or queued.", C.Cyan)
				task.delay(1.1, function()
					if not destroyed and requestCatalogPage then requestCatalogPage(catalogOffset) end
				end)
			end, C.Red)
		end
		return frame
	end

	local function getQueue(): {any}
		local queue = state.queue or state.Queue or {}
		if typeof(queue) ~= "table" then return {} end
		return queue
	end

	currentTrackId = function(now: any): string?
		local direct = tostring(now.trackId or now.id or "")
		if TRACK_INDEX[direct] then return direct end
		for _, track in ipairs(ALL_TRACKS) do
			if track[2] == now.title then return track[1] :: string end
		end
		return nil
	end

	local function badge(parent: Instance, text: string, color: Color3, position: UDim2, width: number)
		local chip = make("TextLabel", {
			Position = position,
			Size = UDim2.fromOffset(width, 24),
			BackgroundColor3 = color:Lerp(C.Base, 0.22),
			Text = text,
			TextColor3 = color:Lerp(C.White, 0.35),
			TextSize = 9,
			Font = BOLD,
		}, parent)
		corner(chip, 8)
		local badgeStroke = stroke(chip, color, 1)
		badgeStroke.Transparency = 0.55
		return chip
	end

	local function renderHome()
		local now: any = if typeof(state.nowPlaying) == "table" then state.nowPlaying else nil
		sectionLabel("NOW PLAYING  /  LIVE QUEUE")

		-- Choose the side-by-side player/queue layout from measured content width,
		-- not the device label. Desktop windows can be narrow, and tablet/console
		-- safe areas can reduce usable width after the panel is laid out.
		local widePlayer = content.AbsoluteSize.X >= 620
		local playerRow = make("Frame", {
			Name = "PlayerQueueLayout",
			Size = UDim2.new(1, -4, 0, if widePlayer then 210 else 386),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, content)
		local playerColumn = make("Frame", {
			Position = UDim2.fromScale(0, 0),
			Size = if widePlayer then UDim2.new(0.57, -5, 1, 0) else UDim2.new(1, 0, 0, 182),
			BackgroundTransparency = 1,
		}, playerRow)
		local queueColumn = make("Frame", {
			Position = if widePlayer then UDim2.new(0.57, 5, 0, 0) else UDim2.new(0, 0, 0, 194),
			Size = if widePlayer then UDim2.new(0.43, -1, 1, 0) else UDim2.new(1, 0, 0, 182),
			BackgroundTransparency = 1,
		}, playerRow)
		buildNowPlaying(playerColumn, widePlayer)

		local queue = getQueue()
		local queueCard = card( if widePlayer then 210 else 182, queueColumn)
		stroke(queueCard, C.Magenta, 1).Transparency = 0.35
		label(queueCard, "UP NEXT", UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 18), C.Cyan, 10, true)
		label(queueCard, string.format("%d TRACK%s IN QUEUE", #queue, if #queue == 1 then "" else "S"),
			UDim2.fromOffset(12, 26), UDim2.new(1, -24, 0, 15), C.Muted, 8, true)
		if #queue == 0 then
			label(queueCard, "Nothing queued. Auto DJ will select the next track.",
				UDim2.fromOffset(12, 62), UDim2.new(1, -24, 0, 48), C.Muted, 11, false)
		else
			local shown = math.min(#queue, if widePlayer then 3 else 2)
			for index = 1, shown do
				local item: any = queue[index]
				local top = 46 + (index - 1) * 45
				local itemGenre: any = TRACK_GENRE[tostring(item.trackId or item.id or "")]
				local indexed: any = TRACK_INDEX[tostring(item.trackId or "")]
				local trackName = nz(item.title, if indexed then tostring(indexed[2]) else nz(item.trackId, "Unknown track"))
				local isPlayer = item.source == "player"
				if index > 1 then
					make("Frame", {
						Position = UDim2.fromOffset(12, top - 3),
						Size = UDim2.new(1, -24, 0, 1),
						BackgroundColor3 = C.SurfaceLight,
						BorderSizePixel = 0,
					}, queueCard)
				end
				label(queueCard, string.format("%02d  %s", index, trackName),
					UDim2.fromOffset(12, top), UDim2.new(1, -24, 0, 19), C.White, 10, true)
				local sourceText = if isPlayer then "PLAYER REQUEST" else "AUTO DJ"
				if item.vip == true then sourceText ..= "  •  VIP" end
				label(queueCard, (if itemGenre then itemGenre.name .. "  •  " else "") .. sourceText .. "  •  " .. formatTime(tonumber(item.duration) or 0),
					UDim2.fromOffset(12, top + 19), UDim2.new(1, -24, 0, 15), if isPlayer then C.Magenta else C.Muted, 8, false)
			end
			if #queue > shown then
				label(queueCard, string.format("+ %d MORE TRACKS", #queue - shown),
					UDim2.new(0, 12, 1, -20), UDim2.new(1, -24, 0, 14), C.Cyan, 8, true)
			end
		end

		-- Playlist type + who selected it
		local trackId: string? = if now then currentTrackId(now) else nil
		local genre: any = if trackId then TRACK_GENRE[trackId] else nil
		local fromPlayer = now ~= nil and now.source == "player"
		local playlistName = if genre then genre.name else nz(if now then (now.playlist or now.genre) else nil, "Club Mix")
		local playlistCard = card(76)
		label(playlistCard, "PLAYLIST", UDim2.fromOffset(12, 6), UDim2.new(1, -120, 0, 16), C.Muted, 9, true)
		label(playlistCard, tostring(playlistName), UDim2.fromOffset(12, 22), UDim2.new(1, -120, 0, 28), if genre then genre.color else C.Cyan, 16, true)
		label(playlistCard, if fromPlayer then "Selected by player: " .. nz(now.requestedBy, "a guest") else "Selected by Auto DJ",
			UDim2.fromOffset(12, 51), UDim2.new(1, -120, 0, 18), C.Muted, 10, false)
		badge(playlistCard, if fromPlayer then "PLAYER" else "AUTO", if fromPlayer then C.Magenta else C.Purple, UDim2.new(1, -92, 0.5, -12), 80)

		-- Like + skip vote
		local skip: any = if typeof(state.skip) == "table" then state.skip else {}
		local votes = tonumber(skip.votes) or 0
		local needed = tonumber(skip.needed) or 1
		local voted = skip.voted == true
		local favorites: any = state.favorites
		local liked = trackId ~= nil and typeof(favorites) == "table" and favorites[trackId] == true
		local controls = card(92)
		label(controls, string.format("VOTE SKIP  •  %d / %d VOTES", votes, needed), UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 20), C.Gold, 10, true)
		local likeButton = actionButton(controls, if liked then "★ LIKED" else "☆ LIKE", UDim2.fromOffset(12, 40), UDim2.new(0.5, -16, 0, 38), function()
			if not trackId then
				notify("This track can't be saved to favorites.", C.Orange)
				return
			end
			act("ToggleFavorite", { trackId = trackId }, trackId)
		end, C.SurfaceLight)
		likeButton.TextSize = 12
		likeButton.TextColor3 = if liked then C.Gold else C.White
		actionButton(controls, if voted then "VOTED" else "VOTE SKIP", UDim2.new(0.5, 4, 0, 40), UDim2.new(0.5, -16, 0, 38), function()
			if voted then
				notify("You already voted to skip this track.", C.Orange)
				return
			end
			act("VoteSkip", {})
		end, if voted then C.SurfaceLight else C.Purple)
	end

	local function renderQueue()
		local now: any = if typeof(state.nowPlaying) == "table" then state.nowPlaying else nil
		local queue = getQueue()
		sectionLabel("LIVE QUEUE  /  " .. tostring(#queue) .. " TRACKS")
		local current = card(66)
		label(current, "NOW PLAYING", UDim2.fromOffset(12, 5), UDim2.new(1, -24, 0, 14), C.Cyan, 9, true)
		label(current, if now then nz(now.title, "Unknown track") else "The stage is in standby",
			UDim2.fromOffset(12, 22), UDim2.new(1, -132, 0, 20), C.White, 12, true)
		label(current, if now then nz(now.artist, "Unknown artist") else "No active track",
			UDim2.fromOffset(12, 43), UDim2.new(1, -132, 0, 14), C.Muted, 9, false)
		badge(current, if now and now.paused == true then "PAUSED" elseif now then "ON AIR" else "STANDBY",
			if now and now.paused == true then C.Orange elseif now then C.Green else C.SurfaceLight,
			UDim2.new(1, -92, 0.5, -12), 80)

		sectionLabel("UP NEXT  /  " .. tostring(#queue) .. " TRACKS")
		if #queue == 0 then
			local empty = card(70)
			label(empty, "The queue is clear. Auto DJ will choose the next track, or listeners can request music from the catalog.",
				UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), C.Muted, 11, false)
			return
		end
		local staffLevel = perm()
		for index, item: any in ipairs(queue) do
			local queueId = tostring(item.id or "")
			local trackId = tostring(item.trackId or item.id or "")
			local indexed: any = TRACK_INDEX[trackId]
			local genre: any = TRACK_GENRE[trackId]
			local titleText = nz(item.title, if indexed then tostring(indexed[2]) else nz(item.trackId, "Unknown track"))
			local requestedBy = if item.source == "player" then "REQUESTED BY " .. string.upper(nz(item.requestedBy, "GUEST")) else "AUTO DJ"
			if item.vip == true then requestedBy ..= "  •  VIP PRIORITY" end
			local actionSpace = if staffLevel >= 1 then 100 else 12
			local row = card(62)
			label(row, string.format("%02d", index), UDim2.fromOffset(12, 8), UDim2.fromOffset(28, 18), C.Gold, 12, true)
			label(row, titleText, UDim2.fromOffset(44, 6), UDim2.new(1, -actionSpace - 54, 0, 22), C.White, 11, true)
			label(row, (if genre then genre.name .. "  •  " else "") .. requestedBy .. "  •  " .. formatTime(tonumber(item.duration) or 0),
				UDim2.fromOffset(44, 31), UDim2.new(1, -actionSpace - 54, 0, 18),
				if item.source == "player" then C.Magenta else C.Muted, 8, false)
			if staffLevel >= 1 and queueId ~= "" then
				if index > 1 then
					local move = actionButton(row, "↑", UDim2.new(1, -88, 0.5, -15), UDim2.fromOffset(34, 30), function()
						act("DJMoveUp", {queueId = queueId}, queueId)
					end, C.Purple)
					move.TextSize = 13
				end
				local remove = actionButton(row, "✕", UDim2.new(1, -48, 0.5, -15), UDim2.fromOffset(36, 30), function()
					act("DJRemove", {queueId = queueId}, queueId)
				end, C.Red)
				remove.TextSize = 13
			end
		end
	end

	local function renderMusic()
		sectionLabel("NOW PLAYING  /  LISTENING ROOM")
		buildNowPlaying(content, true, true)

		local now: any = if typeof(state.nowPlaying) == "table" then state.nowPlaying else {}
		local staffLevel = perm()
		if staffLevel >= 1 then
			local playbackControls = card(88)
			label(playbackControls, "GLOBAL PLAYBACK", UDim2.fromOffset(12, 5), UDim2.new(1, -24, 0, 15), C.Muted, 9, true)
			local controlGap = 8
			local controlWidth = UDim2.new(1/3, -((controlGap * 2) / 3) - 8, 0, 38)
			actionButton(playbackControls, if now.paused == true then "▶ RESUME" else "Ⅱ PAUSE",
				UDim2.fromOffset(12, 30), controlWidth, function()
				act("DJPause", {})
				end, C.Purple)
			actionButton(playbackControls, "↻ RESTART",
				UDim2.new(1/3, 2, 0, 30), controlWidth, function()
				act("DJRestart", {})
				end, C.Cyan)
			actionButton(playbackControls, "» SKIP",
				UDim2.new(2/3, -8, 0, 30), controlWidth, function()
				act("DJSkip", {})
				end, C.Magenta)
		end

		sectionLabel("LIVE QUEUE  /  " .. tostring(#getQueue()) .. " TRACKS")
		local liveQueue = getQueue()
		if #liveQueue == 0 then
			local emptyQueue = card(58)
			label(emptyQueue, "The queue is clear. Auto DJ will choose the next track.", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), C.Muted, 11, false)
		else
			for index, item: any in ipairs(liveQueue) do
				local queueCard = card(64)
				local queueId = tostring(item.id or "")
				local trackName = nz(item.title, nz(item.trackId, "Unknown track"))
				local requestedBy = if item.source == "player" then "REQUESTED BY " .. string.upper(nz(item.requestedBy, "GUEST")) else "AUTO DJ"
				if item.vip == true then requestedBy ..= "  •  VIP" end
				local actionInset = if staffLevel >= 1 then 104 else 12
				label(queueCard, string.format("%02d  %s", index, trackName),
					UDim2.fromOffset(12, 7), UDim2.new(1, -actionInset - 12, 0, 22), C.White, 11, true)
				label(queueCard, requestedBy .. "  •  " .. formatTime(tonumber(item.duration) or 0),
					UDim2.fromOffset(12, 34), UDim2.new(1, -actionInset - 12, 0, 16), if item.source == "player" then C.Magenta else C.Muted, 8, false)
				if staffLevel >= 1 and queueId ~= "" then
					if index > 1 then
						local moveUp = actionButton(queueCard, "▲", UDim2.new(1, -88, 0.5, -15), UDim2.fromOffset(34, 30), function()
							act("DJMoveUp", {queueId = queueId}, queueId)
						end, C.Purple)
						moveUp.TextSize = 13
					end
					local remove = actionButton(queueCard, "✕", UDim2.new(1, -48, 0.5, -15), UDim2.fromOffset(36, 30), function()
						act("DJRemove", {queueId = queueId}, queueId)
					end, C.Red)
					remove.TextSize = 13
				end
			end
		end

		sectionLabel("REQUEST STATUS")
		local statusCard = card(48)
		local disabled, reason = requestsDisabled()
		local statusText = reason
		local statusColor = C.Orange
		if not disabled then
			local req: any = if typeof(state.requests) == "table" then state.requests else {}
			statusText = string.format("Requests used: %d / %d", tonumber(req.used) or 0, tonumber(req.limit) or 0)
			if state.vip == true then statusText ..= "   •   VIP priority active" end
			statusColor = C.Cyan
		elseif state.blocked == true then
			statusColor = C.Red
		end
		label(statusCard, "REQUEST STATUS", UDim2.fromOffset(14, 5), UDim2.new(1, -28, 0, 14), C.Muted, 9, true)
		label(statusCard, statusText, UDim2.fromOffset(14, 20), UDim2.new(1, -28, 0, 22), statusColor, 11, true)

		local favoriteIds: {string} = {}
		local favorites: any = state.favorites
		if typeof(favorites) == "table" then
			for id, flag in pairs(favorites) do
				if flag == true and TRACK_INDEX[id] then table.insert(favoriteIds, id) end
			end
		end
		table.sort(favoriteIds)

		sectionLabel("YOUR LIBRARY")
		local searchCard = card(54)
		local searchBox = make("TextBox", {
			Name = "MusicLibrarySearch",
			Position = UDim2.fromOffset(12, 9),
			Size = UDim2.new(1, -24, 0, 36),
			BackgroundColor3 = C.Base,
			TextColor3 = C.White,
			PlaceholderColor3 = C.Muted,
			PlaceholderText = "Search songs, artists, or genres…",
			Text = musicSearchQuery,
			TextSize = 12,
			Font = FONT,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
		}, searchCard) :: TextBox
		corner(searchBox, 10)
		stroke(searchBox, C.SurfaceLight, 1).Transparency = 0.35
		make("UIPadding", {PaddingLeft=UDim.new(0,12), PaddingRight=UDim.new(0,10)}, searchBox)
		searchBox.FocusLost:Connect(function()
			local nextQuery = string.sub(searchBox.Text, 1, 48)
			if nextQuery == musicSearchQuery then return end
			musicSearchQuery = nextQuery
			selectedGenre = ""
			if renderTabFn then renderTabFn() end
		end)

		local normalizedQuery = string.lower(string.gsub(musicSearchQuery, "^%s*(.-)%s*$", "%1"))
		if normalizedQuery ~= "" then
			local matches = {}
			for _, track in ipairs(ALL_TRACKS) do
				local genre = TRACK_GENRE[track[1]]
				local searchable = string.lower(table.concat({tostring(track[2]), tostring(track[3]), tostring(genre and genre.name or "")}, " "))
				if string.find(searchable, normalizedQuery, 1, true) then
					table.insert(matches, track)
				end
			end
			sectionLabel("SEARCH RESULTS  •  " .. tostring(#matches))
			if #matches == 0 then
				local emptySearch = card(62)
				label(emptySearch, "No matching tracks. Try another song, artist, or genre.", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), C.Muted, 11, false)
			else
				for _, track in ipairs(matches) do makeTrackCard(track) end
			end
			return
		end

		local compactMusic = currentDevice == "Mobile"
		local function collectionGrid(name: string): Frame
			local grid = make("Frame", {
				Name = name,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, content) :: Frame
			make("UIGridLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				CellSize = UDim2.new(if compactMusic then 1 else 0.5, -5, 0, 82),
				CellPadding = UDim2.fromOffset(8, 8),
			}, grid)
			return grid
		end

		sectionLabel("COLLECTIONS")
		local shortcuts = collectionGrid("MusicCollectionShortcuts")
		local likedTile = card(82, shortcuts)
			label(likedTile, "★  LIKED SONGS", UDim2.fromOffset(12, 10), UDim2.new(1, -24, 0, 22), C.Gold, 13, true)
			label(likedTile, string.format("%d saved track%s", #favoriteIds, if #favoriteIds == 1 then "" else "s"), UDim2.fromOffset(12, 35), UDim2.new(1, -24, 0, 18), C.Muted, 10, false)
			badge(likedTile, "YOUR MIX", C.Gold, UDim2.new(1, -82, 1, -27), 70)
			local likedHit = actionButton(likedTile, if selectedGenre == "favorites" then "HIDE" else "OPEN",
				UDim2.new(1, -68, 0, 7), UDim2.fromOffset(58, 24), function()
				selectedGenre = if selectedGenre == "favorites" then "" else "favorites"
					clearContent()
					renderMusic()
				end, C.Gold)
			likedHit.TextSize = 9
		local allTile = card(82, shortcuts)
			label(allTile, "♫  ALL TRACKS", UDim2.fromOffset(12, 10), UDim2.new(1, -24, 0, 22), C.Cyan, 13, true)
			label(allTile, string.format("%d tracks in the catalog", #ALL_TRACKS), UDim2.fromOffset(12, 35), UDim2.new(1, -24, 0, 18), C.Muted, 10, false)
			badge(allTile, "FULL LIBRARY", C.Cyan, UDim2.new(1, -96, 1, -27), 84)
			local allHit = actionButton(allTile, if selectedGenre == "all" then "HIDE" else "OPEN",
				UDim2.new(1, -68, 0, 7), UDim2.fromOffset(58, 24), function()
				selectedGenre = if selectedGenre == "all" then "" else "all"
					clearContent()
					renderMusic()
				end, C.Cyan)
			allHit.TextSize = 9

		if selectedGenre == "favorites" then
			sectionLabel("LIKED SONGS  •  " .. tostring(#favoriteIds))
			if #favoriteIds == 0 then
				local empty = card(56)
				label(empty, "Tap ☆ on any track to save it to your collection.", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), C.Muted, 11, false)
			else
				for _, id in ipairs(favoriteIds) do
					makeTrackCard(TRACK_INDEX[id])
				end
			end
			return
		elseif selectedGenre == "all" then
			sectionLabel("ALL TRACKS  •  " .. tostring(#ALL_TRACKS))
			for _, track in ipairs(ALL_TRACKS) do makeTrackCard(track) end
			return
		end

		sectionLabel("EXPLORE BY GENRE")
		local genresGrid = collectionGrid("MusicGenreCollections")
		for _, genre in ipairs(GENRES) do
			local genreCard = card(82, genresGrid)
			local accent = make("Frame", {
				Name = "CollectionAccent",
				Position = UDim2.fromOffset(0, 10),
				Size = UDim2.fromOffset(3, 62),
				BackgroundColor3 = genre.color,
				BorderSizePixel = 0,
			}, genreCard)
			corner(accent, 2)
			label(genreCard, string.upper(genre.name), UDim2.fromOffset(12, 9), UDim2.new(1, -24, 0, 22), genre.color, 12, true)
			label(genreCard, genre.tagline, UDim2.fromOffset(12, 34), UDim2.new(1, -24, 0, 17), C.Muted, 9, false)
			local genreHit = actionButton(genreCard, if selectedGenre == genre.id then "HIDE" else "EXPLORE",
				UDim2.new(1, -88, 1, -29), UDim2.fromOffset(76, 23), function()
				selectedGenre = if selectedGenre == genre.id then "" else genre.id
					clearContent()
					renderMusic()
				end, genre.color)
			genreHit.TextSize = 9
		end

		if selectedGenre ~= "" then
			for _, genre in ipairs(GENRES) do
				if genre.id == selectedGenre then
					if genre.id == "other" then
						sectionLabel("OTHER  •  CATALOG TRACKS")
						local loading = card(54)
						label(loading, "Loading tracks assigned to Other…", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), C.Muted, 11, false)
						catalogRequestSerial += 1
						local requestSerial = catalogRequestSerial
						task.spawn(function()
							local ok, result = pcall(function()
								if typeof(Network.GetMusicCatalog) ~= "function" then error("Catalog network unavailable") end
								return Network.GetMusicCatalog("", "other", 0, 50)
							end)
							if destroyed or requestSerial ~= catalogRequestSerial or selectedGenre ~= "other" then return end
							if loading.Parent then loading:Destroy() end
							local items = if ok and typeof(result) == "table" and typeof(result.items) == "table" then result.items else {}
							sectionLabel("OTHER TRACKS  •  " .. tostring(#items))
							for _, entry in ipairs(items) do
								if typeof(entry) == "table" and typeof(entry.id) == "string" then
									local tuple = TRACK_INDEX[entry.id]
									if not tuple then
										tuple = {entry.id, tostring(entry.title or "Untitled"), tostring(entry.artist or "Unknown Artist"), tonumber(entry.duration) or 1}
										TRACK_INDEX[entry.id] = tuple
										table.insert(ALL_TRACKS, tuple)
									end
									tuple[2] = tostring(entry.title or tuple[2])
									tuple[3] = tostring(entry.artist or tuple[3])
									tuple[4] = tonumber(entry.duration) or tuple[4]
									TRACK_GENRE[entry.id] = {id = "other", name = "Other", color = genre.color}
									makeTrackCard(tuple)
								end
							end
							if #items == 0 then
								local empty = card(58)
								label(empty, if ok then "No tracks are assigned to Other yet. Staff can add one from the Audio ID tab." else "The catalog could not be loaded. Please try again.", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), C.Muted, 11, false)
							end
						end)
					else
						sectionLabel(string.upper(genre.name) .. "  •  " .. tostring(#genre.tracks) .. " TRACKS")
						for _, track in ipairs(genre.tracks) do makeTrackCard(track) end
					end
					break
				end
			end
		end
	end

	local function renderAllTracks(showPlaylists: boolean?)
		sectionLabel(if showPlaylists == true then "PLAYLIST LIBRARY" else "ALL TRACKS")

		if showPlaylists == true and perm() >= 1 then
			sectionLabel("STAFF PLAYLISTS")

			-- A read-only snapshot keeps playlist editing grounded in the same
			-- authoritative playback state used by the Now Playing panel.
			local playback = if typeof(state.nowPlaying) == "table" then state.nowPlaying else nil

			-- Rotation status comes from the server's authoritative playback snapshot.
			-- The client never guesses whether a playlist is active from button clicks.
			local rotation = if playback and typeof(playback.playlist) == "table" then playback.playlist else nil
			local rotationActive = rotation ~= nil and rotation.active == true
			local rotationPosition = if rotationActive then tonumber(rotation.currentPosition) else nil
			local rotationTotal = if rotationActive then tonumber(rotation.totalTracks) else nil
			local rotationRemaining = if rotationActive then tonumber(rotation.remainingBeforeLoop) else nil
			local hasPosition = rotationPosition ~= nil and rotationTotal ~= nil and rotationTotal > 0
			local rotationCard = card(if hasPosition then 100 else 76)
			label(rotationCard, "PLAYLIST ROTATION", UDim2.fromOffset(12, 7), UDim2.new(1, -120, 0, 16), C.Gold, 10, true)
			local rotationBadge = make("TextLabel", {
				Name = "PlaylistRotationState",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 7),
				Size = UDim2.fromOffset(94, 21),
				BackgroundColor3 = (if rotationActive then C.Green else C.SurfaceLight):Lerp(C.Base, 0.22),
				Text = if rotationActive then "ROTATION ACTIVE" else "STOPPED",
				TextColor3 = C.White,
				TextSize = 8,
				Font = BOLD,
			}, rotationCard)
			corner(rotationBadge, 7)
			local rotationName = if rotationActive then nz(rotation.name, "Active playlist") else "Auto DJ is selecting tracks"
			label(rotationCard, rotationName, UDim2.fromOffset(12, 29), UDim2.new(1, -24, 0, 19),
				if rotationActive then C.Green else C.White, 12, true)
			local rotationDetail = if rotationActive
				then "Repeating playlist order • " .. nz(if playback then playback.title else nil, "Waiting for next track")
				else "No staff playlist is currently controlling track selection."
			label(rotationCard, rotationDetail, UDim2.fromOffset(12, 51), UDim2.new(1, -24, 0, 17), C.Muted, 9, false)
			if hasPosition then
				local safePosition = math.clamp(math.floor(rotationPosition :: number), 1, math.floor(rotationTotal :: number))
				local safeTotal = math.max(1, math.floor(rotationTotal :: number))
				local remaining = math.max(0, math.floor(rotationRemaining or (safeTotal - safePosition)))
				local progressTrack = make("Frame", {
					Name = "PlaylistLoopProgressTrack",
					Position = UDim2.fromOffset(12, 76),
					Size = UDim2.new(1, -24, 0, 5),
					BackgroundColor3 = C.SurfaceLight,
					BorderSizePixel = 0,
				}, rotationCard)
				corner(progressTrack, 3)
				local progressFill = make("Frame", {
					Name = "PlaylistLoopProgressFill",
					Size = UDim2.fromScale(safePosition / safeTotal, 1),
					BackgroundColor3 = C.Cyan,
					BorderSizePixel = 0,
				}, progressTrack)
				corner(progressFill, 3)
				label(rotationCard,
					string.format("TRACK %d OF %d  •  %d %s UNTIL LOOP", safePosition, safeTotal, remaining, if remaining == 1 then "TRACK" else "TRACKS"),
					UDim2.fromOffset(12, 83), UDim2.new(1, -24, 0, 13), C.Cyan, 9, true)
			end

			local monitor = card(82)
			label(monitor, "PLAYBACK SNAPSHOT", UDim2.fromOffset(12, 7), UDim2.new(1, -24, 0, 17), C.Gold, 10, true)
			local playbackTitle = if playback then nz(playback.title, "Unknown track") else "Nothing is currently on air"
			local playbackArtist = if playback then nz(playback.artist, "Unknown artist") else "The stage is in standby"
			label(monitor, playbackTitle, UDim2.fromOffset(12, 27), UDim2.new(1, -24, 0, 19), C.White, 12, true)
			label(monitor, playbackArtist, UDim2.fromOffset(12, 48), UDim2.new(1, -24, 0, 16), C.Muted, 10, false)
			local playbackState = if not playback then "STANDBY" elseif playback.paused == true then "PAUSED" else "ON AIR"
			local stateColor = if not playback then C.Muted elseif playback.paused == true then C.Orange else C.Green
			local stateBadge = make("TextLabel", {
				Name = "PlaylistPlaybackState", AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 7), Size = UDim2.fromOffset(76, 20),
				BackgroundColor3 = stateColor:Lerp(C.Base, 0.25), Text = playbackState,
				TextColor3 = C.White, TextSize = 8, Font = BOLD,
			}, monitor)
			corner(stateBadge, 7)
			local destination = selectedPlaylistName and ("ADD DESTINATION  •  " .. selectedPlaylistName) or "ADD DESTINATION  •  None selected"
			label(monitor, destination, UDim2.fromOffset(12, 65), UDim2.new(1, -24, 0, 13), if selectedPlaylistName then C.Cyan else C.Muted, 9, true)

			local compactPlaylist = currentDevice == "Mobile" or currentDevice == "Tablet"
			local createCard = card(if compactPlaylist then 86 else 48)
			local playlistNameBox = make("TextBox", {
				Name = "NewPlaylistName", Position = UDim2.fromOffset(10, 8),
				Size = if compactPlaylist then UDim2.new(1, -20, 0, 30) else UDim2.new(1, -184, 0, 32),
				BackgroundColor3 = C.SurfaceLight,
				TextColor3 = C.White, PlaceholderColor3 = C.Muted,
				PlaceholderText = "New playlist name (2–32 characters)", Text = "",
				TextSize = 11, Font = FONT, TextXAlignment = Enum.TextXAlignment.Left,
				ClearTextOnFocus = false,
			}, createCard) :: TextBox
			corner(playlistNameBox, 8)
			make("UIPadding", {PaddingLeft=UDim.new(0,9)}, playlistNameBox)
			actionButton(createCard, "CREATE",
				if compactPlaylist then UDim2.fromOffset(10, 46) else UDim2.new(1, -94, 0, 8),
				if compactPlaylist then UDim2.new(0.5, -15, 0, 30) else UDim2.fromOffset(84, 32), function()
				local name = string.sub(playlistNameBox.Text, 1, 32)
				if #name < 2 then notify("Enter a playlist name (2–32 characters).", C.Orange); return end
				send("PlaylistCreate", {name = name})
				notify("Creating playlist…", C.Cyan)
				task.delay(1.2, function()
					if not destroyed then renderTab() end
				end)
			end, C.Green)
			actionButton(createCard, "STOP",
				if compactPlaylist then UDim2.new(0.5, 5, 0, 46) else UDim2.new(1, -164, 0, 8),
				if compactPlaylist then UDim2.new(0.5, -15, 0, 30) else UDim2.fromOffset(62, 32), function()
				send("DJStopPlaylist", {})
				notify("Stopping playlist rotation…", C.Orange)
			end, C.Red)

			local playlistList = make("Frame", {
				Name = "StaffPlaylistList", Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
			}, content) :: Frame
			make("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,6)}, playlistList)
			-- This status is updated asynchronously, so keep it as a TextLabel
			-- rather than the decorative Frame returned by sectionLabel().
			local playlistStatus = make("TextLabel", {
				Name = "PlaylistLoadStatus",
				Size = UDim2.new(1, -4, 0, 30),
				BackgroundTransparency = 1,
				Text = "LOADING PLAYLISTS…",
				TextColor3 = C.Gold,
				TextSize = 10,
				Font = BOLD,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
			}, content) :: TextLabel
			task.spawn(function()
				local ok, entries = pcall(function()
					if typeof(Network.GetMusicPlaylists) ~= "function" then return nil end
					return Network.GetMusicPlaylists()
				end)
				if destroyed or not playlistList.Parent then return end
				for _, child in ipairs(playlistList:GetChildren()) do
					if not child:IsA("UIListLayout") then child:Destroy() end
				end
				if not ok or typeof(entries) ~= "table" then
					playlistStatus.Text = "Playlist storage unavailable."
					return
				end
				playlistStatus.Text = if #entries == 0 then "No saved playlists yet." else "Select a playlist, then use ADD on catalog tracks."
				for order, entry in ipairs(entries) do
					if typeof(entry) == "table" and typeof(entry.id) == "string" and typeof(entry.name) == "string"
						and typeof(entry.trackIds) == "table" then
						local row = card(if compactPlaylist then 68 else 40)
						row.Parent = playlistList
						row.LayoutOrder = order * 102
						local selected = selectedPlaylistId == entry.id
						actionButton(row, (if selected then "SELECTED  " else "SELECT  ") .. entry.name .. "  •  " .. tostring(#entry.trackIds) .. " tracks",
							UDim2.fromOffset(8, 5),
							if compactPlaylist then UDim2.new(1, -16, 0, 27) else UDim2.new(1, -230, 0, 30), function()
								selectedPlaylistId = if selectedPlaylistId == entry.id then nil else entry.id
								selectedPlaylistName = if selectedPlaylistId == entry.id then nil else entry.name
								renderTab()
							end, if selected then C.Green else C.SurfaceLight)
						local actionY = if compactPlaylist then 37 else 5
						actionButton(row, "PLAY",
							if compactPlaylist then UDim2.fromOffset(8, actionY) else UDim2.new(1, -148, 0, actionY),
							if compactPlaylist then UDim2.new(0.5, -13, 0, 26) else UDim2.fromOffset(64, 30), function()
								send("DJPlayPlaylist", {playlistId = entry.id})
								notify("Starting playlist rotation after the current track…", C.Cyan)
							end, C.Purple)
						actionButton(row, "DELETE",
							if compactPlaylist then UDim2.new(0.5, 5, 0, actionY) else UDim2.new(1, -78, 0, actionY),
							if compactPlaylist then UDim2.new(0.5, -13, 0, 26) else UDim2.fromOffset(70, 30), function()
								send("PlaylistDelete", {playlistId = entry.id})
								if selectedPlaylistId == entry.id then selectedPlaylistId = nil end
								notify("Playlist deletion requested…", C.Orange)
								task.delay(1.2, function() if not destroyed then renderTab() end end)
							end, C.Red)
						if selected and #entry.trackIds > 0 then
							for trackIndex, trackId in ipairs(entry.trackIds) do
								if typeof(trackId) == "string" then
									local trackRow = card(if compactPlaylist then 62 else 34)
									trackRow.Parent = playlistList
									trackRow.LayoutOrder = order * 102 + trackIndex
									local indexedTrack: any = TRACK_INDEX[trackId]
									local displayName = if indexedTrack then tostring(indexedTrack[2]) else trackId
									label(trackRow, tostring(trackIndex) .. ". " .. displayName,
										UDim2.fromOffset(8, if compactPlaylist then 3 else 0),
										if compactPlaylist then UDim2.new(1, -16, 0, 22) else UDim2.new(1, -148, 1, 0), C.Muted, 10, false)
									local moveY = if compactPlaylist then 30 else 3
								local moveWidth = if compactPlaylist then UDim2.new(0.34, -8, 0, 27) else UDim2.fromOffset(36, 28)
								actionButton(trackRow, "↑", if compactPlaylist then UDim2.fromOffset(8, moveY) else UDim2.new(1, -136, 0, moveY), moveWidth, function()
										if trackIndex > 1 then
											send("PlaylistMoveTrack", {playlistId=entry.id, trackId=trackId, position=trackIndex-1})
											task.delay(1.1, function() if not destroyed then renderTab() end end)
										end
									end, C.SurfaceLight)
									actionButton(trackRow, "↓", if compactPlaylist then UDim2.new(0.34, 0, 0, moveY) else UDim2.new(1, -94, 0, moveY),
										if compactPlaylist then UDim2.new(0.34, -8, 0, 27) else UDim2.fromOffset(36, 28), function()
										if trackIndex < #entry.trackIds then
											send("PlaylistMoveTrack", {playlistId=entry.id, trackId=trackId, position=trackIndex+1})
											task.delay(1.1, function() if not destroyed then renderTab() end end)
										end
									end, C.SurfaceLight)
									actionButton(trackRow, "REMOVE",
										if compactPlaylist then UDim2.new(0.68, 0, 0, moveY) else UDim2.new(1, -54, 0, moveY),
										if compactPlaylist then UDim2.new(0.32, -8, 0, 27) else UDim2.fromOffset(50, 28), function()
										send("PlaylistRemoveTrack", {playlistId=entry.id, trackId=trackId})
										task.delay(1.1, function() if not destroyed then renderTab() end end)
									end, C.Red)
								end
							end
						end
					end
				end
			end)
		end

		if showPlaylists == true then return end

		if perm() >= 1 and selectedPlaylistId ~= nil then
			local targetCard = card(42)
			label(targetCard, "ADDING TRACKS TO", UDim2.fromOffset(12, 4), UDim2.new(1, -112, 0, 12), C.Muted, 8, true)
			label(targetCard, selectedPlaylistName or "Selected playlist", UDim2.fromOffset(12, 17), UDim2.new(1, -112, 0, 18), C.Green, 11, true)
			actionButton(targetCard, "CHANGE", UDim2.new(1, -88, 0, 6), UDim2.fromOffset(76, 30), function()
				selectedPlaylistId = nil
				selectedPlaylistName = nil
				renderTab()
			end, C.SurfaceLight)
		end

		local searchCard = card(52)
		local searchBox = make("TextBox", {
			Name = "TrackSearch",
			Position = UDim2.fromOffset(12, 9),
			Size = UDim2.new(1, -92, 0, 34),
			BackgroundColor3 = C.SurfaceLight,
			TextColor3 = C.White,
			PlaceholderColor3 = C.Muted,
			PlaceholderText = "🔍 Search title, artist or genre",
			Text = trackSearch,
			TextSize = 12,
			Font = FONT,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
		}, searchCard) :: TextBox
		corner(searchBox, 8)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, searchBox)

		local filterCard = card(46)
		local chips = make("ScrollingFrame", {
			Name = "GenreFilter",
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -16, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 2,
			ScrollingDirection = Enum.ScrollingDirection.X,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
		}, filterCard) :: ScrollingFrame
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}, chips)

		local chipButtons: {[string]: {button: any, color: Color3}} = {}
		local function refreshChips()
			for id, entry in pairs(chipButtons) do
				local active = id == trackGenreFilter
				entry.button.BackgroundColor3 = if active then entry.color else C.SurfaceLight
				entry.button.TextColor3 = if active then C.White else C.Muted
			end
		end
		local chipDefs: {any} = { { id = "all", name = "All", color = C.Magenta } }
		for _, genre in ipairs(GENRES) do
			table.insert(chipDefs, { id = genre.id, name = genre.name, color = genre.color })
		end
		for order, def in ipairs(chipDefs) do
			local chip = make("TextButton", {
				Name = "Chip_" .. def.id,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 0, 28),
				BackgroundColor3 = C.SurfaceLight,
				Text = def.name,
				TextColor3 = C.Muted,
				TextSize = 11,
				Font = BOLD,
				LayoutOrder = order,
			}, chips) :: TextButton
			corner(chip, 14)
			make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, chip)
			chipButtons[def.id] = { button = chip, color = def.color }
			chip.Activated:Connect(function()
				trackGenreFilter = def.id
				refreshChips()
				catalogOffset = 0
				requestCatalogPage(0)
			end)
		end
		refreshChips()

		-- Catalog status is a text element, not the decorative Frame returned by sectionLabel().
		local countLabel = make("TextLabel", {
			Name = "CatalogLoadStatus",
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Text = "LOADING CATALOG…",
			TextColor3 = C.Muted,
			TextSize = 11,
			Font = BOLD,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
		}, content) :: TextLabel

		local results = make("Frame", {
			Name = "TrackResults",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, content) :: Frame
		make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 9) }, results)

		local pager = card(44)
		local pageLabel = label(pager, "Page 1", UDim2.new(0.28, 0, 0, 0), UDim2.new(0.44, 0, 1, 0), C.Muted, 10, true)
		local previousButton = actionButton(pager, "PREVIOUS", UDim2.fromOffset(8, 7), UDim2.new(0.28, -12, 0, 30), function()
			if catalogOffset >= 30 then
				catalogOffset = math.max(0, catalogOffset - 30)
				requestCatalogPage(catalogOffset)
			end
		end, C.SurfaceLight)
		local nextButton = actionButton(pager, "NEXT", UDim2.new(1, -100, 0, 7), UDim2.fromOffset(92, 30), function()
			if catalogHasMore then
				catalogOffset += 30
				requestCatalogPage(catalogOffset)
			end
		end, C.Purple)

		local function showCatalogPage(result: any)
			if destroyed or not results.Parent then return end
			for _, child in ipairs(results:GetChildren()) do
				if not child:IsA("UIListLayout") then child:Destroy() end
			end
			if typeof(result) ~= "table" or typeof(result.items) ~= "table" then
				countLabel.Text = "Catalog is temporarily unavailable. Try again shortly."
				pageLabel.Text = "Unavailable"
				previousButton.Active = false
				nextButton.Active = false
				return
			end

			catalogHasMore = result.hasMore == true
			local shown = 0
			for _, entry in ipairs(result.items) do
				if typeof(entry) == "table" and typeof(entry.id) == "string"
					and typeof(entry.title) == "string" and typeof(entry.artist) == "string"
					and typeof(entry.duration) == "number" then
					local trackId = entry.id
					if typeof(entry.artworkAssetId) == "number" and entry.artworkAssetId > 0 then
						TRACK_ARTWORK[trackId] = entry.artworkAssetId
					else
						TRACK_ARTWORK[trackId] = nil
					end
					local tuple = TRACK_INDEX[trackId]
					if not tuple then
						tuple = {trackId, entry.title, entry.artist, entry.duration}
						TRACK_INDEX[trackId] = tuple
						table.insert(ALL_TRACKS, tuple)
					end
					tuple[2] = entry.title
					tuple[3] = entry.artist
					tuple[4] = entry.duration
					local genreInfo: any = TRACK_GENRE[trackId]
					if not genreInfo then
						local genreColor = C.Cyan
						for _, knownGenre in ipairs(GENRES) do
							if knownGenre.id == entry.genreId then genreColor = knownGenre.color break end
						end
						genreInfo = {id = entry.genreId, name = entry.genre, color = genreColor}
						TRACK_GENRE[trackId] = genreInfo
					end
					shown += 1
					local trackCard = makeTrackCard(tuple, results, true, selectedPlaylistId)
					trackCard.LayoutOrder = shown
					if string.sub(trackId, 1, 7) == "custom-" then
						local customLabel = make("TextLabel", {
							Name = "CustomCatalogBadge",
							Position = UDim2.new(1, if perm() >= 1 then -250 else -176, 0, 7),
							Size = UDim2.fromOffset(48, 16),
							BackgroundColor3 = C.Cyan,
							Text = "CUSTOM",
							TextColor3 = C.White,
							TextSize = 8,
							Font = BOLD,
						}, trackCard)
						corner(customLabel, 6)
					end
				end
			end

			local total = tonumber(result.total) or shown
			local summary = string.format("%d catalog result%s", total, if total == 1 then "" else "s")
			if trackGenreFilter ~= "all" then
				for _, genre in ipairs(GENRES) do
					if genre.id == trackGenreFilter then summary ..= " in " .. genre.name break end
				end
			end
			if trackSearch ~= "" then summary ..= " matching \"" .. trackSearch .. "\"" end
			countLabel.Text = summary
			pageLabel.Text = string.format("Page %d  •  %d–%d of %d",
				math.floor((tonumber(result.offset) or 0) / 30) + 1,
				if shown > 0 then (tonumber(result.offset) or 0) + 1 else 0,
				(tonumber(result.offset) or 0) + shown, total)
			previousButton.Active = (tonumber(result.offset) or 0) > 0
			previousButton.AutoButtonColor = previousButton.Active
			nextButton.Active = catalogHasMore
			nextButton.AutoButtonColor = nextButton.Active

			if shown == 0 then
				local empty = make("Frame", {
					Size = UDim2.new(1, -4, 0, 52),
					BackgroundColor3 = C.Surface,
					BorderSizePixel = 0,
				}, results)
				corner(empty, 12)
				label(empty, "No tracks match your search or filter.", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), C.Muted, 11, false)
			end
		end

		requestCatalogPage = function(offset: number)
			if destroyed then return end
			pendingCatalogRemoval = nil
			catalogRequestSerial += 1
			local serial = catalogRequestSerial
			countLabel.Text = "Loading catalog…"
			previousButton.Active = false
			previousButton.AutoButtonColor = false
			nextButton.Active = false
			nextButton.AutoButtonColor = false
			task.spawn(function()
				if typeof(Network.GetMusicCatalog) ~= "function" then
					if serial == catalogRequestSerial then showCatalogPage(nil) end
					return
				end
				local genreId = if trackGenreFilter == "all" then "" else trackGenreFilter
				local ok, result = pcall(function()
					return Network.GetMusicCatalog(trackSearch, genreId, offset, 30)
				end)
				if destroyed or serial ~= catalogRequestSerial then return end
				showCatalogPage(if ok then result else nil)
			end)
		end

		actionButton(searchCard, "CLEAR", UDim2.new(1, -72, 0, 11), UDim2.fromOffset(60, 30), function()
			trackSearch = ""
			searchBox.Text = ""
			catalogOffset = 0
			requestCatalogPage(0)
		end, C.SurfaceLight)

		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			if searchBox.Text ~= trackSearch then
				trackSearch = string.sub(searchBox.Text, 1, 48)
				catalogOffset = 0
				catalogRequestSerial += 1
				local serial = catalogRequestSerial
				task.delay(0.9, function()
					if not destroyed and serial == catalogRequestSerial then requestCatalogPage(0) end
				end)
			end
		end)
		requestCatalogPage(catalogOffset)
	end

	local function stopPreview()
		if previewAudio then pcall(function() previewAudio:Stop() end) end
		if previewGraph then pcall(function() previewGraph:Destroy() end) end
		previewAudio = nil
		previewFader = nil
		previewGraph = nil
		previewId = nil
	end

	local function refreshAudioTab()
		if expanded and activeTab == "Audio ID" and renderTabFn then renderTabFn() end
	end

	local function lookupAudio(rawText: string)
		if destroyed then return end
		if os.clock() - lastAudioLookupAt < 1.0 then
			notify("Please wait before looking up another asset.", C.Orange)
			return
		end
		lastAudioLookupAt = os.clock()
		if typeof(rawText) ~= "string" or #rawText > 256 then
			notify("Enter a valid audio asset ID or Creator Hub link.", C.Red)
			return
		end
		if perm() < 1 then
			notify("Audio asset IDs are staff only.", C.Red)
			return
		end
		local id = parseAssetId(rawText)
		if not id then
			notify("Enter a valid audio asset ID or Creator Hub link.", C.Red)
			return
		end
		lookupSerial += 1
		local serial = lookupSerial
		audioLookup = { id = id, status = "loading" }
		refreshAudioTab()
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, Enum.InfoType.Asset)
			end)
			if destroyed or serial ~= lookupSerial then return end
			if not ok or typeof(info) ~= "table" then
				audioLookup = { id = id, status = "error", message = "Asset not found or unavailable." }
			elseif info.AssetTypeId ~= Enum.AssetType.Audio.Value then
				audioLookup = { id = id, status = "error", message = "That asset is not an audio file." }
			else
				local creator = if typeof(info.Creator) == "table" then tostring(info.Creator.Name or "Unknown") else "Unknown"
				local assetName = tostring(info.Name or "Untitled audio")
				creator = string.sub(string.gsub(creator, "%c", ""), 1, 80)
				assetName = string.sub(string.gsub(assetName, "%c", ""), 1, 120)
				audioLookup = { id = id, status = "ok", name = assetName, creator = creator }
			end
			refreshAudioTab()
		end)
	end

	local function togglePreview(id: number)
		if previewId == id then
			stopPreview()
			refreshAudioTab()
			return
		end
		stopPreview()
		local graph = Instance.new("Folder")
		graph.Name = "ClubMusicAudioPreview"
		local audioPlayer = Instance.new("AudioPlayer")
		audioPlayer.Name = "AudioPreview"
		audioPlayer.AutoLoad = true
		audioPlayer.Asset = "rbxassetid://" .. tostring(id)
		audioPlayer.Parent = graph
		local fader = Instance.new("AudioFader")
		fader.Name = "PreviewVolume"
		fader.Volume = volume
		fader.Parent = graph
		local output = Instance.new("AudioDeviceOutput")
		output.Name = "PreviewOutput"
		output.Player = player
		output.Parent = graph
		local inputWire = Instance.new("Wire")
		inputWire.SourceInstance = audioPlayer
		inputWire.TargetInstance = fader
		inputWire.Parent = graph
		local outputWire = Instance.new("Wire")
		outputWire.SourceInstance = fader
		outputWire.TargetInstance = output
		outputWire.Parent = graph
		graph.Parent = SoundService
		previewGraph = graph
		previewAudio = audioPlayer
		previewFader = fader
		previewId = id
		audioPlayer.Ended:Connect(function()
			if previewAudio == audioPlayer then
				stopPreview()
				refreshAudioTab()
			end
		end)
		audioPlayer:Play()
		task.delay(10, function()
			if previewAudio == audioPlayer and not audioPlayer.IsReady then
				stopPreview()
				notify("Audio could not be loaded. It may be private or restricted.", C.Red)
				refreshAudioTab()
			end
		end)
		refreshAudioTab()
	end

	local function renderAudioId()
		sectionLabel("CREATOR HUB AUDIO")
		if perm() < 1 then
			local locked = card(56)
			label(locked, "🔒 Staff only. Audio asset IDs can only be used by DJs and staff.", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), C.Orange, 11, true)
			return
		end
		local info = card(84)
		label(info, "Play any Roblox audio by asset ID.", UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 22), C.White, 13, true)
		label(info, "Paste an audio ID or Creator Hub link, look it up, preview it, request it, or save a validated track to the shared catalog.",
			UDim2.fromOffset(12, 32), UDim2.new(1, -24, 0, 46), C.Muted, 10, false)

		local inputCard = card(96)
		local box = make("TextBox", {
			Name = "AudioIdInput",
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 0, 34),
			BackgroundColor3 = C.SurfaceLight,
			TextColor3 = C.White,
			PlaceholderColor3 = C.Muted,
			PlaceholderText = "Audio asset ID or Creator Hub link",
			Text = audioInput,
			TextSize = 12,
			Font = FONT,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
		}, inputCard) :: TextBox
		corner(box, 8)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)
		box:GetPropertyChangedSignal("Text"):Connect(function() audioInput = box.Text end)
		box.FocusLost:Connect(function(enterPressed)
			if enterPressed then lookupAudio(box.Text) end
		end)
		actionButton(inputCard, "LOOK UP", UDim2.fromOffset(12, 54), UDim2.new(0.5, -16, 0, 32), function()
			lookupAudio(box.Text)
		end, C.Magenta)
		actionButton(inputCard, "CLEAR", UDim2.new(0.5, 4, 0, 54), UDim2.new(0.5, -16, 0, 32), function()
			stopPreview()
			audioInput = ""
			artworkInput = ""
			audioLookup = nil
			lookupSerial += 1
			refreshAudioTab()
		end, C.SurfaceLight)

		local result = audioLookup
		if not result then return end
		sectionLabel("RESULT")
		if result.status == "loading" then
			local loading = card(52)
			label(loading, "Looking up asset " .. tostring(result.id) .. "…", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), C.Cyan, 11, true)
		elseif result.status == "error" then
			local failed = card(56)
			label(failed, tostring(result.message), UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), C.Red, 11, true)
		else
			local id = tonumber(result.id) or 0
			local found = card(218)
			label(found, tostring(result.name), UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 22), C.White, 13, true)
			label(found, "by " .. tostring(result.creator) .. "  •  ID " .. tostring(id), UDim2.fromOffset(12, 32), UDim2.new(1, -24, 0, 18), C.Muted, 10, false)
			local previewing = previewId == id
			actionButton(found, if previewing then "■ STOP" else "▶ PREVIEW", UDim2.fromOffset(12, 70), UDim2.new(0.5, -16, 0, 34), function()
				togglePreview(id)
			end, if previewing then C.Orange else C.Purple)
			local disabled, reason = requestsDisabled()
			actionButton(found, if disabled then "LOCKED" else "REQUEST", UDim2.new(0.5, 4, 0, 70), UDim2.new(0.5, -16, 0, 34), function()
				if disabled then
					notify(reason, C.Orange)
					return
				end
				stopPreview()
				local title = tostring(result.name)
				if typeof(Network.RequestAudioAsset) == "function" then
					callNetwork("RequestAudioAsset", id, title)
				else
					send("RequestAudioAsset", { assetId = id, title = title })
				end
			end, if disabled then C.SurfaceLight else C.Magenta)

			local genreName = "Club Exclusives"
			for _, genre in ipairs(GENRES) do
				if genre.id == catalogGenreId then genreName = genre.name break end
			end
			actionButton(found, "GENRE: " .. genreName, UDim2.fromOffset(12, 116), UDim2.new(0.5, -16, 0, 34), function()
				local currentIndex = 1
				for index, genre in ipairs(GENRES) do
					if genre.id == catalogGenreId then currentIndex = index break end
				end
				currentIndex = currentIndex % #GENRES + 1
				catalogGenreId = GENRES[currentIndex].id
				refreshAudioTab()
			end, C.SurfaceLight)
			local artworkBox = make("TextBox", {
				Name="CatalogArtworkAssetId", Position=UDim2.fromOffset(12, 160), Size=UDim2.new(1, -24, 0, 30),
				BackgroundColor3=C.SurfaceLight, TextColor3=C.White, PlaceholderColor3=C.Muted,
				PlaceholderText="Optional cover image asset ID (Roblox image/decal)", Text=artworkInput,
				TextSize=10, Font=FONT, TextXAlignment=Enum.TextXAlignment.Left, ClearTextOnFocus=false,
			}, found) :: TextBox
			corner(artworkBox, 8)
			make("UIPadding", {PaddingLeft=UDim.new(0, 9), PaddingRight=UDim.new(0, 9)}, artworkBox)
			artworkBox:GetPropertyChangedSignal("Text"):Connect(function() artworkInput = string.sub(artworkBox.Text, 1, 128) end)
			actionButton(found, "SAVE TO CATALOG", UDim2.new(0.5, 4, 0, 116), UDim2.new(0.5, -16, 0, 34), function()
				if typeof(Network.Send) ~= "function" then
					notify("Catalog storage network is unavailable.", C.Red)
					return
				end
				local artworkId = if string.gsub(artworkInput, "%s", "") == "" then nil else parseAssetId(artworkInput)
				if artworkInput ~= "" and not artworkId then
					notify("Enter a valid Roblox image asset ID or Creator Hub link.", C.Red)
					return
				end
				send("CatalogAddAudio", {assetId = id, genreId = catalogGenreId, artworkAssetId = artworkId})
				notify("Submitting audio and optional cover art for server validation and catalog storage…", C.Cyan)
			end, C.Cyan)
		end
	end

	local function renderDJ()
		local level = perm()
		sectionLabel("DJ BOOTH")
		buildNowPlaying()

		if level >= 1 then
			local controls = card(104)
			actionButton(controls, "DJ SKIP", UDim2.fromOffset(12, 10), UDim2.new(0.5, -18, 0, 34), function()
				act("DJSkip", {})
			end, C.Magenta)
			actionButton(controls, "PAUSE / RESUME", UDim2.new(0.5, 6, 0, 10), UDim2.new(0.5, -18, 0, 34), function()
				act("DJPause", {})
			end, C.Purple)
			actionButton(controls, "RESTART TRACK", UDim2.fromOffset(12, 54), UDim2.new(1, -24, 0, 34), function()
				act("DJRestart", {})
			end, C.Cyan)

			sectionLabel("STAFF CONTROLS")
			local staff = card(58)
			local locked = state.locked == true
			actionButton(staff, if locked then "UNLOCK REQUESTS" else "LOCK REQUESTS", UDim2.fromOffset(12, 12),
				if level >= 2 then UDim2.new(0.5, -16, 0, 34) else UDim2.new(1, -24, 0, 34), function()
					act("DJToggleLock", {})
				end, if locked then C.Orange else C.Purple)
			if level >= 2 then
				actionButton(staff, "CLEAR QUEUE", UDim2.new(0.5, 4, 0, 12), UDim2.new(0.5, -16, 0, 34), function()
					act("DJClearQueue", {})
				end, C.Red)
			end
		else
			local note = card(48)
			label(note, "Vote to skip the current song from the Home tab.", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), C.Muted, 11, false)
		end

		sectionLabel("UP NEXT")
		local queue = getQueue()
		if #queue == 0 then
			local empty = card(56)
			label(empty, "The request queue is empty.", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), C.Muted, 12, false)
			return
		end
		for index, item: any in ipairs(queue) do
			local qcard = card(64)
			local rank = make("Frame", {Name="QueuePosition", Position=UDim2.fromOffset(12, 17), Size=UDim2.fromOffset(30, 30), BackgroundColor3=C.SurfaceLight, BorderSizePixel=0}, qcard)
			corner(rank, 9)
			local rankText = make("TextLabel", {Size=UDim2.fromScale(1, 1), BackgroundTransparency=1, Text=string.format("%02d", index), TextColor3=C.Gold, TextSize=11, Font=BOLD}, rank)
			local textWidth = if level >= 1 then -100 else -24
			local trackName = nz(item.title, nz(item.trackId, "Unknown track"))
			local who = if item.source == "player" then "Requested by " .. nz(item.requestedBy, "a guest") else "Auto DJ pick"
			if item.vip == true then who ..= "  •  VIP" end
			label(qcard, trackName, UDim2.fromOffset(52, 7), UDim2.new(1, textWidth, 0, 22), C.White, 12, true)
			label(qcard, who .. "  •  " .. formatTime(tonumber(item.duration) or 0), UDim2.fromOffset(52, 33), UDim2.new(1, textWidth, 0, 17), C.Muted, 10, false)
			if level >= 1 then
				local queueId = tostring(item.id)
				if index > 1 then
					local up = actionButton(qcard, "▲", UDim2.new(1, -88, 0.5, -15), UDim2.fromOffset(34, 30), function()
						act("DJMoveUp", { queueId = queueId }, queueId)
					end, C.Purple)
					up.TextSize = 14
				end
				local remove = actionButton(qcard, "✕", UDim2.new(1, -48, 0.5, -15), UDim2.fromOffset(36, 30), function()
					act("DJRemove", { queueId = queueId }, queueId)
				end, C.Red)
				remove.TextSize = 14
			end
		end
	end

	local function renderModeration()
		local level = perm()
		sectionLabel("MODERATION")
		local roster: any = state.players
		if typeof(roster) ~= "table" then roster = {} end

		local summary = card(82)
		local manageable = 0
		local blockedCount = 0
		for _, entry: any in ipairs(roster) do
			if entry.canMod == true and level >= 2 then manageable += 1 end
			if entry.blocked == true then blockedCount += 1 end
		end
		label(summary, "LIVE PLAYER ROSTER", UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 18), C.Gold, 11, true)
		label(summary, string.format("%d online   •   %d blocked   •   %d manageable", #roster, blockedCount, manageable), UDim2.fromOffset(14, 29), UDim2.new(1, -28, 0, 17), C.White, 11, false)
		local search = make("TextBox", {Name="RosterSearch", Position=UDim2.fromOffset(12,52), Size=UDim2.new(1,-24,0,24), BackgroundColor3=Color3.fromRGB(13,16,24), TextColor3=C.White, PlaceholderColor3=C.Muted, PlaceholderText="Search display name, username or ID", Text="", TextSize=10, Font=FONT, ClearTextOnFocus=false, TextXAlignment=Enum.TextXAlignment.Left}, summary)
		corner(search, 8)
		local searchStroke = stroke(search, C.SurfaceLight, 1)
		searchStroke.Transparency = 0.25
		if #roster == 0 then
			local empty = card(64)
			label(empty, "No players are currently available in the roster.", UDim2.fromOffset(14,0), UDim2.new(1,-28,1,0), C.Muted, 12, false)
			return
		end
		local rosterCards: {Frame} = {}
		for _, p: any in ipairs(roster) do
			local showButtons = level >= 2 and p.canMod == true
			local pcard = card(if showButtons then 112 else 68)
			table.insert(rosterCards, pcard)
			local displayName = nz(p.displayName, "Player")
			local username = nz(p.name, "?")
			local userId = tonumber(p.userId) or 0
			pcard:SetAttribute("RosterSearchKey", string.lower(displayName .. " " .. username .. " " .. tostring(userId)))
			label(pcard, displayName, UDim2.fromOffset(13,7), UDim2.new(1,-26,0,20), C.White, 13, true)
			label(pcard, "@" .. username .. "   •   ID " .. tostring(userId), UDim2.fromOffset(13,27), UDim2.new(1,-26,0,15), C.Muted, 9, false)
			local bits = {nz(p.rank, "GUEST")}
			if p.vip == true then table.insert(bits, if p.tempVip == true then "TEMP VIP" else "VIP") end
			table.insert(bits, tostring(tonumber(p.requests) or 0) .. " queued")
			if p.blocked == true then table.insert(bits, "REQUESTS BLOCKED") end
			label(pcard, table.concat(bits, "   •   "), UDim2.fromOffset(13,45), UDim2.new(1,-26,0,17), if p.blocked == true then C.Red else C.Gold, 9, false)
			if showButtons then
				local isBlocked = p.blocked == true
				local isTempVip = p.tempVip == true
				local buttonY = 76
				local buttonWidth = UDim2.new(1/3,-16,0,27)
				local blockButton = actionButton(pcard, if isBlocked then "UNBLOCK" else "BLOCK", UDim2.new(0,12,0,buttonY), buttonWidth, function() act("ModBlockUser", {userId=userId, blocked=not isBlocked}, userId, not isBlocked) end, if isBlocked then C.Green else C.Red)
				local vipButton = actionButton(pcard, if isTempVip then "REMOVE VIP" else "GIVE VIP", UDim2.new(1/3,6,0,buttonY), buttonWidth, function() act("ModSetVip", {userId=userId, vip=not isTempVip}, userId, not isTempVip) end, C.Purple)
				local purgeButton = actionButton(pcard, "PURGE QUEUE", UDim2.new(2/3,0,0,buttonY), buttonWidth, function() act("ModPurgeUser", {userId=userId}, userId) end, C.Orange)
				blockButton.TextSize = 9
				vipButton.TextSize = 9
				purgeButton.TextSize = 9
			end
		end
		search:GetPropertyChangedSignal("Text"):Connect(function()
			local query = string.lower(string.sub(search.Text,1,40))
			for _, rosterCard in ipairs(rosterCards) do
				local key = rosterCard:GetAttribute("RosterSearchKey")
				rosterCard.Visible = query == "" or (typeof(key) == "string" and string.find(key,query,1,true) ~= nil)
			end
		end)
	end
	local function renderXPBoosts()
		sectionLabel("PLAYER PROGRESSION")
		local xp = math.max(0, math.floor(tonumber(state.xp) or 0))
		local level = math.max(1, math.floor(tonumber(state.level) or (math.floor(xp / 100) + 1)))
		local toNext = math.max(0, math.floor(tonumber(state.xpToNextLevel) or (100 - (xp % 100))))
		local progressCard = card(104)
		label(progressCard, "LEVEL " .. tostring(level), UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 22), C.Gold, 15, true)
		label(progressCard, tostring(xp) .. " XP  •  " .. tostring(toNext) .. " XP to next level",
			UDim2.fromOffset(12, 34), UDim2.new(1, -24, 0, 18), C.White, 11, false)
		local track = make("Frame", {Position=UDim2.fromOffset(12,64),Size=UDim2.new(1,-24,0,14),BackgroundColor3=C.SurfaceLight,BorderSizePixel=0}, progressCard)
		corner(track, 7)
		local fill = make("Frame", {Size=UDim2.new((xp % 100)/100,0,1,0),BackgroundColor3=C.Cyan,BorderSizePixel=0}, track)
		corner(fill, 7)
		label(progressCard, "Earn 10 base XP for each full minute played. Awards are server-authoritative.",
			UDim2.fromOffset(12,82), UDim2.new(1,-24,0,16), C.Muted, 9, false)

		sectionLabel("GLOBAL XP BOOST")
		local multiplier = tonumber(state.xpMultiplier) or 1
		local expiry = tonumber(state.xpBoostExpiresAt) or 0
		local remaining = math.max(0, expiry - os.time())
		local activeCard = card(76)
		label(activeCard, if multiplier > 1 and remaining > 0 then string.format("%dx XP ACTIVE", multiplier) else "STANDARD XP RATE",
			UDim2.fromOffset(12,8), UDim2.new(1,-24,0,22), if multiplier > 1 then C.Gold else C.Cyan, 13, true)
		label(activeCard, if multiplier > 1 and remaining > 0
			then string.format("Time remaining: %02d:%02d", math.floor(remaining/60), remaining%60)
			else "No global boost is currently active.",
			UDim2.fromOffset(12,36), UDim2.new(1,-24,0,18), C.Muted, 10, false)

		local ids: any = if typeof(state.xpBoostProductIds) == "table" then state.xpBoostProductIds else {}
		local twoId = tonumber(ids.twoX) or 0
		local fourId = tonumber(ids.fourX) or 0
		local twoCard = card(86)
		label(twoCard, "2x XP • 15 MINUTES", UDim2.fromOffset(12,8), UDim2.new(1,-120,0,22), C.Cyan, 12, true)
		label(twoCard, "Adds 15 minutes to the shared 2x timer.", UDim2.fromOffset(12,34), UDim2.new(1,-120,0,30), C.Muted, 9, false)
		actionButton(twoCard, "BUY", UDim2.new(1,-104,0.5,-16), UDim2.fromOffset(92,32), function()
			if twoId <= 0 then notify("Configure CONFIG.XPBoost2xProductId first.", C.Red); return end
			MarketplaceService:PromptProductPurchase(player, twoId)
		end, C.Cyan)
		local fourCard = card(86)
		label(fourCard, "4x XP • 30 MINUTES", UDim2.fromOffset(12,8), UDim2.new(1,-120,0,22), C.Gold, 12, true)
		label(fourCard, "Adds 30 minutes to the shared 4x timer.", UDim2.fromOffset(12,34), UDim2.new(1,-120,0,30), C.Muted, 9, false)
		actionButton(fourCard, "BUY", UDim2.new(1,-104,0.5,-16), UDim2.fromOffset(92,32), function()
			if fourId <= 0 then notify("Configure CONFIG.XPBoost4xProductId first.", C.Red); return end
			MarketplaceService:PromptProductPurchase(player, fourId)
		end, C.Gold)
		local note = card(54)
		label(note, "Boosts apply to all players on live servers. The strongest active multiplier wins; repeat purchases extend that boost's timer.",
			UDim2.fromOffset(12,0), UDim2.new(1,-24,1,0), C.Muted, 9, false)
	end

	local function renderTipJar()
		sectionLabel("SUPPORT THE STAGE")
		local info = card(68)
		label(info, "Tips help keep the island lights on.", UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 22), C.White, 13, true)
		label(info, "Choose a contribution below. Purchases require configured Developer Product IDs.", UDim2.fromOffset(12, 32), UDim2.new(1, -24, 0, 28), C.Muted, 10, false)
		for _, item in ipairs(DONATIONS) do
			local donationCard = card(76)
			label(donationCard, item.label .. "  •  " .. tostring(item.amount) .. " Robux", UDim2.fromOffset(12, 8), UDim2.new(1, -130, 0, 22), C.Gold, 13, true)
			label(donationCard, item.perk, UDim2.fromOffset(12, 34), UDim2.new(1, -130, 0, 20), C.Muted, 10, false)
			actionButton(donationCard, "TIP", UDim2.new(1, -104, 0.5, -16), UDim2.fromOffset(92, 32), function()
				if item.productId <= 0 then notify("Configure this Developer Product ID first.", C.Red); return end
				MarketplaceService:PromptProductPurchase(player, item.productId)
			end, C.Magenta)
		end
	end

	local function renderShop()
		sectionLabel("ISLAND ITEM SHOP")
		for _, item in ipairs(SHOP) do
			local shopCard = card(88)
			label(shopCard, item.name, UDim2.fromOffset(12, 8), UDim2.new(1, -130, 0, 22), C.White, 13, true)
			label(shopCard, item.desc, UDim2.fromOffset(12, 32), UDim2.new(1, -130, 0, 30), C.Muted, 10, false)
			label(shopCard, if item.kind == "GamePass" then item.rarity .. " • Roblox Game Pass" else item.rarity .. " • " .. tostring(item.price) .. " coins",
				UDim2.fromOffset(12, 64), UDim2.new(1, -130, 0, 16), C.Gold, 9, true)
			actionButton(shopCard, "GET", UDim2.new(1, -104, 0.5, -16), UDim2.fromOffset(92, 32), function()
				local itemId = item.id
				if item.kind == "GamePass" and itemId <= 0 then
					local passKey = item.passKey or "vip"
					if passKey == "sultan" then
						itemId = tonumber(state.sultanGamePassId) or 0
					elseif passKey == "vvip" then
						itemId = tonumber(state.vvipGamePassId) or 0
					else
						itemId = tonumber(state.vipGamePassId) or 0
					end
				end
				if itemId <= 0 then notify("This item is not configured for purchase yet.", C.Red); return end
				if item.kind == "GamePass" then
					MarketplaceService:PromptGamePassPurchase(player, itemId)
				else
					MarketplaceService:PromptProductPurchase(player, itemId)
				end
			end, C.Purple)
		end
	end

	local function renderRewards()
		sectionLabel("DAILY LOGIN REWARDS")
		local streak = tonumber(state.loginStreak or state.streak or 1) or 1
		local claimedToday = state.claimedToday == true
		local info = card(66)
		label(info, "Current login streak: " .. tostring(streak) .. (if streak == 1 then " day" else " days"), UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 22), C.Gold, 14, true)
		label(info, if claimedToday then "Today's reward is claimed. Come back tomorrow!" else "Your Day " .. tostring(streak) .. " reward is ready to claim.",
			UDim2.fromOffset(12, 34), UDim2.new(1, -24, 0, 18), C.Muted, 10, false)
		for _, reward in ipairs(REWARDS) do
			local status = "LOCKED"
			if reward.day < streak or (reward.day == streak and claimedToday) then
				status = "CLAIMED"
			elseif reward.day == streak then
				status = "CLAIM"
			end
			local ready = status == "CLAIM"
			local rewardCard = card(62)
			label(rewardCard, "DAY " .. reward.day .. "  •  " .. reward.label, UDim2.fromOffset(12, 0), UDim2.new(1, -120, 1, 0),
				if reward.day == streak then C.Gold else C.White, 12, true)
			actionButton(rewardCard, status, UDim2.new(1, -104, 0.5, -15), UDim2.fromOffset(92, 30), function()
				if not ready then
					notify(if status == "CLAIMED" then "You already claimed this reward." else "This reward isn't available yet.", C.Orange)
					return
				end
				act("ClaimDailyReward", { day = reward.day }, reward.day)
			end, if ready then C.Green else C.SurfaceLight)
		end
	end

	local function renderTagCollection()
		sectionLabel("TITLE TAG COLLECTION")
		local equipped = state.equippedTitleTag or state.equippedTag or ""
		local serverOwned = if typeof(state.ownedTags) == "table" then state.ownedTags else nil
		local intro = card(54)
		label(intro, "EQUIPPED COLLECTION TAGS APPEAR ABOVE YOUR AVATAR", UDim2.fromOffset(12, 5), UDim2.new(1, -24, 0, 18), C.Cyan, 10, true)
		label(intro, "Custom titles remain managed separately in the CUSTOM and MANAGE tabs.", UDim2.fromOffset(12, 25), UDim2.new(1, -24, 0, 18), C.Muted, 9, false)
		for _, tag in ipairs(TAGS) do
			-- The server is authoritative: tags bought in the shop or earned via rewards appear here.
			local isOwned = if serverOwned then serverOwned[tag.id] == true else false
			local tagCard = card(72)
			label(tagCard, tag.label, UDim2.fromOffset(12, 8), UDim2.new(1, -130, 0, 22), tag.a, 14, true)
			label(tagCard, tag.source, UDim2.fromOffset(12, 35), UDim2.new(1, -130, 0, 18), C.Muted, 10, false)
			if tag.id == "party" and not isOwned then
				local hours = math.min(10, math.floor((tonumber(state.clubPlaySeconds) or 0) / 3600))
				label(tagCard, string.format("%d / 10 HOURS", hours), UDim2.new(1, -112, 1, -17), UDim2.fromOffset(100, 14), C.Cyan, 9, true)
			end
			local buttonText = if equipped == tag.id then "EQUIPPED" elseif isOwned then "EQUIP" elseif tag.price then string.format("BUY  •  %d", tag.price) else "LOCKED"
			actionButton(tagCard, buttonText, UDim2.new(1, -112, 0.5, -15), UDim2.fromOffset(100, 30), function()
				if isOwned then
					callNetwork("EquipTitleTag", tag.id)
					if typeof(Network.EquipTitleTag) ~= "function" then send("EquipTitleTag", {tagId=tag.id}) end
				elseif tag.price then
					act("BuyTitleTag", {tagId=tag.id}, tag.id)
				else
					notify("Complete this title tag unlock requirement first.", C.Red)
				end
			end, isOwned and C.Purple or tag.price and C.Gold or C.SurfaceLight)
		end
	end

	local function titleSlotInfo()
		local ts: any = if typeof(state.titleSlots) == "table" then state.titleSlots else {}
		local unlocked = math.clamp(math.floor(tonumber(ts.unlocked) or 1), 1, 3)
		local active = math.clamp(math.floor(tonumber(ts.active) or 1), 1, 3)
		local slots: any = if typeof(ts.slots) == "table" then ts.slots else {}
		local function slotOf(index: number): {[string]: any}
			local data = slots[index] or slots[tostring(index)]
			if index == 1 and data == nil and nz(state.customTitle, "") ~= "" then
				data = { text = state.customTitle, color = state.customTitleColor, style = state.customTitleStyle }
			end
			return normalizeTitle(data)
		end
		return unlocked, active, slotOf, ts
	end

	local function titleSlotPrice(slot: number, ts: any): number
		local prices: any = if typeof(ts.prices) == "table" then ts.prices else {}
		return tonumber(prices[slot] or prices[tostring(slot)]) or TITLE_SLOT_PRICES[slot] or 0
	end

	local function buyTitleSlot(slot: number)
		local unlockedNow, _, _, ts = titleSlotInfo()
		if slot > unlockedNow + 1 then
			notify("Unlock slot " .. tostring(unlockedNow + 1) .. " first.", C.Orange)
			return
		end
		local products: any = if typeof(ts.products) == "table" then ts.products else {}
		local productId = tonumber(products[slot] or products[tostring(slot)]) or TITLE_SLOT_PRODUCTS[slot] or 0
		if productId <= 0 then
			notify("Configure this slot's Developer Product ID first.", C.Red)
			return
		end
		MarketplaceService:PromptProductPurchase(player, productId)
	end

	local function refreshTitleTab()
		if renderTabFn then renderTabFn() end
	end

	-- Horizontal row of selectable chips. Returns the row so callers can rebuild it.
	local function chipRow(parent: Instance, y: number, options: {any}, getSelected: () -> string, onPick: (string) -> (), tint: ((any) -> Color3?)?)
		local compactChips = currentDevice == "Mobile" or currentDevice == "Tablet"
		local chipHeight = if compactChips then 28 else 30
		local chipTextSize = if compactChips then 9 else 10
		local chipPadding = if compactChips then 9 else 11
		local chipGap = if compactChips then 5 else 6
		local row = make("ScrollingFrame", {
			Position = UDim2.fromOffset(12, y),
			Size = UDim2.new(1, -24, 0, 30),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 0,
			ScrollingDirection = Enum.ScrollingDirection.X,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
		}, parent) :: ScrollingFrame
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, chipGap),
		}, row)
		local buttons: {[string]: {button: any, tint: Color3, outline: UIStroke?}} = {}
		local navigationButtons: {TextButton} = {}
		local function refresh()
			for id, entry in pairs(buttons) do
				local on = id == getSelected()
				entry.button.BackgroundColor3 = if on then C.Magenta else C.SurfaceLight
				entry.button.TextColor3 = if on then C.White else entry.tint
				if entry.outline then
					entry.outline.Thickness = if on then 2 else 1
					entry.outline.Transparency = if on then 0.08 else 0.48
				end
			end
		end
		for order, option in ipairs(options) do
			local color = (if tint then tint(option) else nil) or C.Muted
			local chip = make("TextButton", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 0, chipHeight),
				BackgroundColor3 = C.SurfaceLight,
				Text = option.name,
				TextColor3 = color,
				TextSize = chipTextSize,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Font = BOLD,
				LayoutOrder = order,
				Selectable = true,
				Active = true,
				AutoButtonColor = false,
			}, row) :: TextButton
			corner(chip, 15)
			local chipOutline = stroke(chip, color, 1)
			chipOutline.Transparency = 0.48
			bindFocusFeedback(chip, chipOutline, C.SurfaceLight)
			-- Keep the currently selected chip visible while navigating long preset
			-- rows with a controller or keyboard. The row remains touch-scrollable.
			chip.SelectionGained:Connect(function()
				local left = chip.AbsolutePosition.X - row.AbsolutePosition.X + row.CanvasPosition.X
				local right = left + chip.AbsoluteSize.X
				local viewLeft = row.CanvasPosition.X
				local viewRight = viewLeft + row.AbsoluteSize.X
				local targetX = viewLeft
				if left < viewLeft then
					targetX = math.max(0, left - 8)
				elseif right > viewRight then
					targetX = math.max(0, right - row.AbsoluteSize.X + 8)
				else
					return
				end
				row.CanvasPosition = Vector2.new(targetX, row.CanvasPosition.Y)
			end)
			make("UIPadding", { PaddingLeft = UDim.new(0, chipPadding), PaddingRight = UDim.new(0, chipPadding) }, chip)
			buttons[option.id] = { button = chip, tint = color, outline = chipOutline }
			table.insert(navigationButtons, chip)
			chip.Activated:Connect(function()
				onPick(option.id)
				refresh()
			end)
		end
		-- Keep controller and keyboard focus within the horizontal chip row.
		-- SelectionGained above scrolls long rows so the focused chip stays visible.
		for index, chip in ipairs(navigationButtons) do
			chip.NextSelectionLeft = navigationButtons[math.max(1, index - 1)]
			chip.NextSelectionRight = navigationButtons[math.min(#navigationButtons, index + 1)]
		end
		refresh()
		return row
	end

	local function linkChipRows(upper: Instance?, lower: Instance?)
		if not upper or not lower then return end
		local function orderedButtons(row: Instance): {TextButton}
			local result: {TextButton} = {}
			for _, child in ipairs(row:GetChildren()) do
				if child:IsA("TextButton") then table.insert(result, child) end
			end
			table.sort(result, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
			return result
		end
		local upperButtons = orderedButtons(upper)
		local lowerButtons = orderedButtons(lower)
		if #upperButtons == 0 or #lowerButtons == 0 then return end
		upperButtons[#upperButtons].NextSelectionDown = lowerButtons[1]
		lowerButtons[1].NextSelectionUp = upperButtons[#upperButtons]
	end

	local function stepper(parent: Instance, y: number, text: string, get: () -> number, set: (number) -> (), minValue: number, maxValue: number, step: number, unit: string)
		local compact = currentDevice == "Mobile" or currentDevice == "Tablet"
		local titleLabel = label(parent, text, UDim2.fromOffset(12, y), UDim2.new(1, compact and -194 or -190, 0, 26), C.Cyan, compact and 9 or 10, true)
		titleLabel.TextScaled = true
		make("UITextSizeConstraint", { MinTextSize = 8, MaxTextSize = compact and 9 or 10 }, titleLabel)
		local valueLabel = label(parent, "", UDim2.new(1, -124, 0, y), UDim2.fromOffset(76, 26), C.White, compact and 10 or 11, true)
		valueLabel.TextXAlignment = Enum.TextXAlignment.Center
		local function show() valueLabel.Text = string.format("%.2f %s", get(), unit) end
		local function change(direction: number)
			local value = math.clamp(math.floor((get() + direction * step) / step + 0.5) * step, minValue, maxValue)
			set(value)
			show()
		end
		local decrement = actionButton(parent, "−", UDim2.new(1, -162, 0, y), UDim2.fromOffset(34, 26), function() change(-1) end, C.SurfaceLight)
		local increment = actionButton(parent, "+", UDim2.new(1, -44, 0, y), UDim2.fromOffset(34, 26), function() change(1) end, C.SurfaceLight)
		-- Keep controller focus moving predictably across the two value controls.
		decrement.NextSelectionRight = increment
		increment.NextSelectionLeft = decrement
		show()
		return decrement, increment
	end

	local function saveTitleDraft(draft: any)
		local unlocked = titleSlotInfo()
		if draft.slot > unlocked then
			notify("Unlock this slot first.", C.Red)
			return
		end
		-- Match the server's whitespace normalization so titles containing
		-- only spaces cannot appear saveable in the editor.
		local titleText = string.match(nz(draft.text, ""), "^%s*(.-)%s*$") or ""
		local titleLength = utf8.len(titleText)
		if titleText == "" then
			notify("Enter a title first. Spaces alone do not count.", C.Orange)
			return
		end
		if not titleLength or titleLength > 24 then
			notify("Titles must contain 1-24 valid characters.", C.Orange)
			return
		end
		local payload = {
			slot = draft.slot,
			text = titleText,
			effect = draft.effect,
			set = draft.set,
			colors = titleColorHex(draft.effect, draft.set),
			font = draft.font,
			style = draft.style,
			textSize = draft.size,
			heightOffset = draft.height,
			viewDistance = draft.distance,
			visible = true,
		}
		if typeof(Network.SaveTitleSlot) == "function" then
			callNetwork("SaveTitleSlot", payload)
		elseif typeof(Network.SaveCustomTitle) == "function" and draft.slot == 1 then
			-- Older servers only understand a fixed color name and basic style.
			callNetwork("SaveCustomTitle", titleText, if draft.effect == "fixed" then draft.set else "gold", draft.style, true)
		else
			send("SaveTitleSlot", payload)
		end
	end

	local function renderTitleEditor()
		if state.customTitleUnlocked ~= true then
			sectionLabel("CUSTOM TITLE  •  SULTAN EXCLUSIVE")
			local locked = card(112)
			label(locked, "🔒  TIKI TIDE SULTAN REQUIRED", UDim2.fromOffset(12, 12), UDim2.new(1, -24, 0, 24), C.Gold, 14, true)
			label(locked, "Unlock the Tiki Tide Sultan pass to create, style, and display your own overhead title.", UDim2.fromOffset(12, 43), UDim2.new(1, -24, 0, 42), C.Muted, 11, false)
			return
		end
		local unlocked, _, slotOf = titleSlotInfo()
		if titleEditSlot > unlocked then titleEditSlot = 1 end
		if not titleDraft or titleDraft.slot ~= titleEditSlot then
			local loaded: any = slotOf(titleEditSlot)
			loaded.slot = titleEditSlot
			titleDraft = loaded
		end
		local draft: any = titleDraft
		local compactTitleEditor = currentDevice == "Mobile" or currentDevice == "Tablet"
		local previewMaxTextSize = 32

		sectionLabel("CUSTOM TITLE")
		local slotCard = card(56)
		label(slotCard, "EDITING SLOT", UDim2.fromOffset(12, 1), UDim2.new(1, -24, 0, 14), C.Muted, 9, true)
		local slotButtons: {TextButton} = {}
		for i = 1, 3 do
			local isLocked = i > unlocked
			local slotButton = actionButton(slotCard, (if isLocked then "🔒 " else "") .. "SLOT " .. i, UDim2.new((i - 1) / 3, 8, 0, 19), UDim2.new(1 / 3, -12, 0, 29), function()
				if isLocked then
					notify("Slot " .. i .. " is locked. Unlock it from the MANAGE view.", C.Orange)
					return
				end
				titleEditSlot = i
				titleDraft = nil
				refreshTitleTab()
			end, if i == titleEditSlot then C.Magenta elseif isLocked then C.SurfaceLight else C.Purple)
			table.insert(slotButtons, slotButton)
		end
		for i, slotButton in ipairs(slotButtons) do
			slotButton.NextSelectionLeft = slotButtons[math.max(1, i - 1)]
			slotButton.NextSelectionRight = slotButtons[math.min(#slotButtons, i + 1)]
		end

		-- Live style preview
		local previewCard = card(108)
		label(previewCard, "LIVE PREVIEW", UDim2.fromOffset(12, 5), UDim2.new(1, -110, 0, 15), C.Muted, 9, true)
		local previewSlot = label(previewCard, "SLOT " .. tostring(titleEditSlot) .. "  •  UNSAVED", UDim2.new(1, -116, 0, 5), UDim2.fromOffset(104, 15), C.Gold, 8, true)
		previewSlot.TextXAlignment = Enum.TextXAlignment.Right
		previewSlot.TextScaled = true
		previewSlot.TextTruncate = Enum.TextTruncate.AtEnd
		make("UITextSizeConstraint", {
			MinTextSize = 7,
			MaxTextSize = if compactTitleEditor then 8 else 9,
		}, previewSlot)
		local previewStage = make("Frame", {
			Name = "TitlePreviewStage",
			Position = UDim2.fromOffset(9, 24),
			Size = UDim2.new(1, -18, 0, if compactTitleEditor then 48 else 52),
			BackgroundColor3 = C.SurfaceLight,
			BackgroundTransparency = 0.28,
			BorderSizePixel = 0,
		}, previewCard) :: Frame
		corner(previewStage, 11)
		local previewStageStroke = stroke(previewStage, C.SurfaceLight, 1)
		previewStageStroke.Transparency = 0.35
		local previewLabel = make("TextLabel", {
			Position = UDim2.fromOffset(8, 3),
			Size = UDim2.new(1, -16, 1, -6),
			BackgroundTransparency = 1,
			TextSize = previewMaxTextSize,
			TextScaled = true,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, previewStage) :: TextLabel
		local previewSizeConstraint = make("UITextSizeConstraint", {
			MinTextSize = math.max(10, math.floor(draft.size * 0.65)),
			MaxTextSize = draft.size,
		}, previewLabel) :: UITextSizeConstraint
		local previewHint = label(previewCard, "Changes appear here before you save", UDim2.fromOffset(12, 80), UDim2.new(1, -24, 0, 17), C.Muted, 9, false)
		previewHint.TextXAlignment = Enum.TextXAlignment.Center
		previewHint.TextScaled = true
		previewHint.TextTruncate = Enum.TextTruncate.AtEnd
		make("UITextSizeConstraint", { MinTextSize = 8, MaxTextSize = 9 }, previewHint)
		local previewUpdate: (number) -> () = function(_) end
		table.insert(titleAnimators, function(t) previewUpdate(t) end)
		local function refreshPreview()
			previewSizeConstraint.MinTextSize = math.max(10, math.floor(draft.size * 0.65))
			previewSizeConstraint.MaxTextSize = draft.size
			previewUpdate = styleTitleLabel(previewLabel, draft)
			previewUpdate(os.clock())
		end
		refreshPreview()

		local form = card(510)
		label(form, "Title text", UDim2.fromOffset(12, 6), UDim2.new(1, -132, 0, 18), C.Muted, 10, true)
		local titleCounter = label(form, "0 / 24", UDim2.new(1, -112, 0, 6), UDim2.fromOffset(100, 18), C.Muted, 9, true)
		titleCounter.TextXAlignment = Enum.TextXAlignment.Right
		titleCounter.TextScaled = true
		make("UITextSizeConstraint", { MinTextSize = 8, MaxTextSize = 9 }, titleCounter)
		local titleInput = make("TextBox", {
			Position = UDim2.fromOffset(12, 26),
			Size = UDim2.new(1, -24, 0, 36),
			BackgroundColor3 = C.SurfaceLight,
			TextColor3 = C.White,
			PlaceholderColor3 = C.Muted,
			PlaceholderText = "Enter a custom title",
			Text = draft.text,
			TextSize = if compactTitleEditor then 11 else 12,
			TextScaled = true,
			TextWrapped = false,
			Font = FONT,
			ClearTextOnFocus = false,
			Selectable = true,
			Active = true,
		}, form) :: TextBox
		corner(titleInput, 9)
		make("UITextSizeConstraint", {
			MinTextSize = if compactTitleEditor then 10 else 11,
			MaxTextSize = if compactTitleEditor then 12 else 13,
		}, titleInput)
		-- Controller navigation flows from the selected slot directly into title editing.
		local selectedSlotButton = slotButtons[titleEditSlot]
		if selectedSlotButton then
			selectedSlotButton.NextSelectionDown = titleInput
			titleInput.NextSelectionUp = selectedSlotButton
		end
		local titleInputStroke = stroke(titleInput, C.SurfaceLight, 1)
		titleInputStroke.Transparency = 0.38
		titleInput.Focused:Connect(function()
			titleInputStroke.Color = C.Cyan
			titleInputStroke.Transparency = 0
			titleInputStroke.Thickness = 2
		end)
		titleInput.FocusLost:Connect(function()
			titleInputStroke.Color = C.SurfaceLight
			titleInputStroke.Transparency = 0.38
			titleInputStroke.Thickness = 1
		end)
		local function refreshTitleCounter(text: string)
			local length = utf8.len(text) or 0
			titleCounter.Text = string.format("%d / 24", math.min(length, 24))
			titleCounter.TextColor3 = if length >= 24 then C.Orange elseif length >= 20 then C.Gold else C.Muted
		end
		refreshTitleCounter(titleInput.Text)
		titleInput:GetPropertyChangedSignal("Text"):Connect(function()
			local text = titleInput.Text
			local length = utf8.len(text)
			if length and length > 24 then
				titleInput.Text = string.sub(text, 1, (utf8.offset(text, 25) or (#text + 1)) - 1)
				return
			end
			draft.text = text
			refreshTitleCounter(text)
			refreshPreview()
		end)

		label(form, "Color effect", UDim2.fromOffset(12, 66), UDim2.new(1, -24, 0, 16), C.Cyan, 10, true)
		label(form, "Color set", UDim2.fromOffset(12, 116), UDim2.new(1, -24, 0, 16), C.Cyan, 10, true)
		local presetSearch = make("TextBox", {
			Position = UDim2.fromOffset(12, 134),
			Size = UDim2.new(1, -24, 0, 28),
			BackgroundColor3 = C.SurfaceLight,
			TextColor3 = C.White,
			PlaceholderColor3 = C.Muted,
			PlaceholderText = "Search color presets...",
			Text = "",
			TextSize = if compactTitleEditor then 9 else 10,
			Font = FONT,
			ClearTextOnFocus = false,
			Selectable = true,
			Active = true,
		}, form) :: TextBox
		corner(presetSearch, 7)
		local presetSearchStroke = stroke(presetSearch, C.SurfaceLight, 1)
		presetSearchStroke.Transparency = 0.38
		presetSearch.Focused:Connect(function()
			presetSearchStroke.Color = C.Cyan
			presetSearchStroke.Transparency = 0
			presetSearchStroke.Thickness = 2
		end)
		presetSearch.FocusLost:Connect(function()
			presetSearchStroke.Color = C.SurfaceLight
			presetSearchStroke.Transparency = 0.38
			presetSearchStroke.Thickness = 1
		end)
		presetSearch.TextScaled = true
		presetSearch.TextWrapped = false
		make("UITextSizeConstraint", {
			MinTextSize = 9,
			MaxTextSize = if compactTitleEditor then 10 else 11,
		}, presetSearch)

		local families = {
			{ id = "all", name = "All colors" },
			{ id = "red", name = "Reds / Pinks" },
			{ id = "warm", name = "Warm" },
			{ id = "green", name = "Greens" },
			{ id = "blue", name = "Blues" },
			{ id = "purple", name = "Purples" },
			{ id = "neutral", name = "Neutrals" },
		}
		local selectedFamily = "all"
		local function colorFamily(option: any): string
			local color = option.color or option.a
			if typeof(color) ~= "Color3" then return "neutral" end
			local hue, saturation = color:ToHSV()
			if saturation < 0.16 then return "neutral" end
			if hue < 0.045 or hue >= 0.94 then return "red" end
			if hue < 0.16 then return "warm" end
			if hue < 0.42 then return "green" end
			if hue < 0.70 then return "blue" end
			return "purple"
		end
		local initialEffect = findById(TITLE_EFFECTS, draft.effect)
		local initialPreset = findById(initialEffect.sets, draft.set)
		local selectedPreset = label(form, "SELECTED  •  " .. string.upper(initialPreset.name), UDim2.fromOffset(12, 234), UDim2.new(1, -24, 0, 16), initialPreset.color or initialPreset.a or C.Gold, 10, true)
		selectedPreset.TextScaled = true
		selectedPreset.TextTruncate = Enum.TextTruncate.AtEnd
		make("UITextSizeConstraint", { MinTextSize = 8, MaxTextSize = 10 }, selectedPreset)
		local setRow: Instance? = nil
		local familyRow: Instance? = nil
		local effectRow: Instance? = nil
		local fontRow: Instance? = nil
		local styleRow: Instance? = nil
		local emptyHint: Instance? = nil
		local function rowButtons(row: Instance?): {TextButton}
			local result: {TextButton} = {}
			if not row then return result end
			for _, child in ipairs(row:GetChildren()) do
				if child:IsA("TextButton") then table.insert(result, child) end
			end
			table.sort(result, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
			return result
		end
		local function refreshChipNavigation()
			linkChipRows(effectRow, familyRow)
			linkChipRows(fontRow, styleRow)
			local familyButtons = rowButtons(familyRow)
			local presetButtons = rowButtons(setRow)
			local fontButtons = rowButtons(fontRow)
			if #familyButtons > 0 then
				familyButtons[#familyButtons].NextSelectionDown = presetSearch
				presetSearch.NextSelectionUp = familyButtons[#familyButtons]
			end
			if #presetButtons > 0 then
				presetSearch.NextSelectionDown = presetButtons[1]
				presetButtons[1].NextSelectionUp = presetSearch
				if #fontButtons > 0 then
					presetButtons[#presetButtons].NextSelectionDown = fontButtons[1]
					fontButtons[1].NextSelectionUp = presetButtons[#presetButtons]
				end
			else
				-- An empty search result must not strand controller focus on a
				-- destroyed preset chip; route directly to the next live section.
				presetSearch.NextSelectionDown = fontButtons[1]
				if #fontButtons > 0 then fontButtons[1].NextSelectionUp = presetSearch end
			end
		end
		local function buildSetRow()
			if setRow then setRow:Destroy() end
			if emptyHint then emptyHint:Destroy(); emptyHint = nil end
			local effect = findById(TITLE_EFFECTS, draft.effect)
			local query = string.lower(presetSearch.Text or "")
			local filtered = {}
			for _, option in ipairs(effect.sets) do
				local matchesSearch = query == "" or string.find(string.lower(option.name .. " " .. option.id), query, 1, true)
				local matchesFamily = selectedFamily == "all" or colorFamily(option) == selectedFamily
				if matchesSearch and matchesFamily then table.insert(filtered, option) end
			end
			setRow = chipRow(form, 202, filtered, function() return draft.set end, function(id)
				draft.set = id
				local chosen = findById(effect.sets, id)
				selectedPreset.Text = "SELECTED  •  " .. string.upper(chosen.name)
				selectedPreset.TextColor3 = chosen.color or chosen.a or C.Gold
				refreshPreview()
			end, function(option) return option.color or option.a end)
			if #filtered == 0 then
				emptyHint = label(form, "No matching presets — try another family or search.", UDim2.fromOffset(12, 202), UDim2.new(1, -24, 0, 26), C.Muted, 10, false)
			end
			refreshChipNavigation()
		end
		familyRow = chipRow(form, 168, families, function() return selectedFamily end, function(id)
			selectedFamily = id
			buildSetRow()
		end)
		effectRow = chipRow(form, 84, TITLE_EFFECTS, function() return draft.effect end, function(id)
			local firstPreset = findById(TITLE_EFFECTS, id).sets[1]
			draft.effect = id
			draft.set = firstPreset.id
			selectedFamily = "all"
			presetSearch.Text = ""
			selectedPreset.Text = "SELECTED  •  " .. string.upper(firstPreset.name)
			selectedPreset.TextColor3 = firstPreset.color or firstPreset.a or C.Gold
			buildSetRow()
			refreshPreview()
		end)
		presetSearch:GetPropertyChangedSignal("Text"):Connect(function()
			buildSetRow()
		end)
		buildSetRow()

		label(form, "Text face", UDim2.fromOffset(12, 256), UDim2.new(1, -24, 0, 16), C.Cyan, 10, true)
		fontRow = chipRow(form, 274, TITLE_FONTS, function() return draft.font end, function(id)
			draft.font = id
			refreshPreview()
		end)
		label(form, "Text style", UDim2.fromOffset(12, 308), UDim2.new(1, -24, 0, 16), C.Cyan, 10, true)
		local styleOptions = {}
		for _, styleId in ipairs(TITLE_STYLES) do
			table.insert(styleOptions, { id = styleId, name = string.upper(string.sub(styleId, 1, 1)) .. string.sub(styleId, 2) })
		end
		styleRow = chipRow(form, 326, styleOptions, function() return draft.style end, function(id)
			draft.style = id
			refreshPreview()
		end)
		refreshChipNavigation()
		local firstEffectChip = effectRow and effectRow:FindFirstChildWhichIsA("TextButton")
		if firstEffectChip then
			titleInput.NextSelectionDown = firstEffectChip
			firstEffectChip.NextSelectionUp = titleInput
		end

		local heightDown, heightUp = stepper(form, 366, "Height offset (above head)", function() return draft.height end, function(v) draft.height = v end, 0, 8, 0.25, "studs")
		local distanceDown, distanceUp = stepper(form, 398, "View distance", function() return draft.distance end, function(v) draft.distance = v end, 20, 200, 10, "studs")
		local sizeDown, sizeUp = stepper(form, 430, "Title text size", function() return draft.size end, function(v) draft.size = v; refreshPreview() end, 14, 32, 2, "px")
		local firstStyleChip = styleRow and styleRow:FindFirstChildWhichIsA("TextButton")
		if firstStyleChip and heightDown then
			firstStyleChip.NextSelectionDown = heightDown
			heightDown.NextSelectionUp = firstStyleChip
		end
		if heightUp and distanceDown then
			heightUp.NextSelectionDown = distanceDown
			distanceDown.NextSelectionUp = heightUp
		end
		if distanceUp and sizeDown then
			distanceUp.NextSelectionDown = sizeDown
			sizeDown.NextSelectionUp = distanceUp
		end

		local saveButton = actionButton(form, "SAVE TITLE", UDim2.fromOffset(12, 466), UDim2.new(0.5, -16, 0, 36), function()
			saveTitleDraft(draft)
		end, C.Magenta)
		local resetButton = actionButton(form, "RESET", UDim2.new(0.5, 4, 0, 466), UDim2.new(0.5, -16, 0, 36), function()
			titleDraft = nil
			refreshTitleTab()
		end, C.SurfaceLight)
		-- Keep the primary and secondary actions paired for predictable controller navigation.
		saveButton.NextSelectionRight = resetButton
		resetButton.NextSelectionLeft = saveButton
		if sizeUp then
			sizeUp.NextSelectionDown = saveButton
			saveButton.NextSelectionUp = sizeUp
		end
		if compactTitleEditor then
			for _, button in ipairs({ saveButton, resetButton }) do
				button.TextSize = 10
				button.TextWrapped = false
				make("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 10 }, button)
			end
		end
	end

	local function renderTitleManage()
		if state.customTitleUnlocked ~= true then
			sectionLabel("MANAGE TITLES  •  SULTAN EXCLUSIVE")
			local locked = card(112)
			label(locked, "🔒  TIKI TIDE SULTAN REQUIRED", UDim2.fromOffset(12, 12), UDim2.new(1, -24, 0, 24), C.Gold, 14, true)
			label(locked, "Custom title slots and overhead title controls are exclusive to Tiki Tide Sultan members.", UDim2.fromOffset(12, 43), UDim2.new(1, -24, 0, 42), C.Muted, 11, false)
			return
		end
		local unlocked, active, slotOf, ts = titleSlotInfo()
		local shown = ts.visible ~= false
		sectionLabel("MANAGE TITLES")
		local info = card(88)
		label(info, "YOUR OVERHEAD TITLE", UDim2.fromOffset(12, 7), UDim2.new(1, -24, 0, 17), C.Cyan, 10, true)
		local activeData: any = slotOf(active)
		local activeName = nz(activeData.text, "") ~= "" and activeData.text or "No title equipped"
		label(info, activeName, UDim2.fromOffset(12, 26), UDim2.new(1, -150, 0, 22), C.White, 13, true)
		label(info, string.format("SLOT %d  •  %s", active, if shown then "VISIBLE ABOVE AVATAR" else "CURRENTLY HIDDEN"),
			UDim2.fromOffset(12, 51), UDim2.new(1, -150, 0, 17), if shown then C.Green else C.Muted, 9, true)
		actionButton(info, if shown then "HIDE TITLE" else "SHOW TITLE", UDim2.new(1, -132, 0, 27), UDim2.fromOffset(120, 30), function()
			act("SetTitleVisible", { visible = not shown }, not shown)
		end, if shown then C.SurfaceLight else C.Purple)

		sectionLabel("SAVED TITLE SLOTS")
		for i = 1, 3 do
			local isLocked = i > unlocked
			local data: any = slotOf(i)
			local hasTitle = nz(data.text, "") ~= ""
			local slotCard = card(132)
			local slotHeading = "SLOT " .. tostring(i) .. (if i == 1 then "  •  FREE" else "")
			label(slotCard, slotHeading, UDim2.fromOffset(12, 6), UDim2.new(1, -145, 0, 18), C.Muted, 10, true)
			if active == i and not isLocked then
				badge(slotCard, "EQUIPPED", C.Green, UDim2.new(1, -94, 0, 5), 82)
			elseif not isLocked and hasTitle then
				badge(slotCard, "SAVED", C.Cyan, UDim2.new(1, -82, 0, 5), 70)
			end
			if isLocked then
				label(slotCard, "🔒  SLOT LOCKED", UDim2.fromOffset(12, 29), UDim2.new(1, -24, 0, 24), C.Muted, 14, true)
				label(slotCard, string.format("Unlock this extra slot for %d Robux", titleSlotPrice(i, ts)), UDim2.fromOffset(12, 57), UDim2.new(1, -24, 0, 18), C.Gold, 10, true)
				actionButton(slotCard, string.format("UNLOCK SLOT  •  R$ %d", titleSlotPrice(i, ts)), UDim2.fromOffset(12, 91), UDim2.new(1, -24, 0, 30), function()
					buyTitleSlot(i)
				end, C.Magenta)
			else
				local previewLabel = make("TextLabel", {
					Position = UDim2.fromOffset(12, 27),
					Size = UDim2.new(1, -24, 0, 34),
					BackgroundTransparency = 1,
					TextSize = 20,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
				}, slotCard) :: TextLabel
				if hasTitle then
					local update = styleTitleLabel(previewLabel, data)
					update(os.clock())
					table.insert(titleAnimators, update)
				else
					previewLabel.Font = FONT
					previewLabel.Text = "No title saved in this slot"
					previewLabel.TextColor3 = C.Muted
					previewLabel.TextSize = 12
				end
				local effect = findById(TITLE_EFFECTS, data.effect)
				local setName = titleSetFor(data.effect, data.set).name
				local detail = if hasTitle
					then string.format("%s  •  %s  •  %.2f height  •  %d studs", effect.name, setName, data.height, math.floor(data.distance))
					else "Create a custom title to fill this slot"
				label(slotCard, detail, UDim2.fromOffset(12, 64), UDim2.new(1, -24, 0, 16), C.Muted, 9, false)
				actionButton(slotCard, if active == i then "EQUIPPED" else "EQUIP", UDim2.fromOffset(12, 94), UDim2.new(1 / 3, -12, 0, 28), function()
					if not hasTitle then
						notify("Save a title in this slot first.", C.Orange)
						return
					end
					act("SelectTitleSlot", { slot = i }, i)
				end, if active == i then C.SurfaceLight else C.Purple)
				actionButton(slotCard, if hasTitle then "EDIT" else "CREATE", UDim2.new(1 / 3, 2, 0, 94), UDim2.new(1 / 3, -8, 0, 28), function()
					titleEditSlot = i
					titleDraft = nil
					titleSub = "editor"
					refreshTitleTab()
				end, C.Magenta)
				actionButton(slotCard, "CLEAR", UDim2.new(2 / 3, 0, 0, 94), UDim2.new(1 / 3, -12, 0, 28), function()
					if not hasTitle then
						notify("This slot is already empty.", C.Orange)
						return
					end
					if titleDraft and titleDraft.slot == i then titleDraft = nil end
					act("ClearTitleSlot", { slot = i }, i)
				end, C.Red)
			end
		end
	end

	local function renderTags()
		local seg = card(48)
		for i, def in ipairs({ { id = "collection", name = "TAGS" }, { id = "editor", name = "CUSTOM" }, { id = "manage", name = "MANAGE" } }) do
			actionButton(seg, def.name, UDim2.new((i - 1) / 3, 8, 0, 9), UDim2.new(1 / 3, -12, 0, 30), function()
				titleSub = def.id
				refreshTitleTab()
			end, if titleSub == def.id then C.Magenta else C.SurfaceLight)
		end
		if titleSub == "editor" then
			renderTitleEditor()
		elseif titleSub == "manage" then
			renderTitleManage()
		else
			renderTagCollection()
		end
	end

	local function renderCommunity()
		sectionLabel("FIREBEACH MUSIC FESTIVAL COMMUNITY")
		local groupId = tonumber(state.groupId) or 0
		if groupId <= 0 then
			local config = ReplicatedStorage:FindFirstChild("ClubMusicConfig")
			if config then
				groupId = tonumber(config:GetAttribute("GroupId")) or 0
			end
		end
		local groupCard = card(108)
		label(groupCard, "JOIN THE CLUB", UDim2.fromOffset(12, 9), UDim2.new(1, -24, 0, 22), C.Gold, 14, true)
		label(groupCard, "Join the Roblox group to connect with the Sunset Stage community.", UDim2.fromOffset(12, 36), UDim2.new(1, -24, 0, 34), C.Muted, 10, false)
		actionButton(groupCard, "OPEN GROUP", UDim2.fromOffset(12, 72), UDim2.new(1, -24, 0, 26), function()
			if groupId <= 0 then notify("Configure CONFIG.GroupId on the server first.", C.Red); return end
			local ok, err = pcall(function()
				GroupService:PromptJoinAsync(groupId)
			end)
			if not ok then
				warn("[ClubMusic UI] Group prompt: " .. tostring(err))
				notify("Could not open group prompt.", C.Red)
			end
		end, C.Purple)
		local profile: any = if typeof(state.profile) == "table" then state.profile else {}
		local profileCard = card(122)
		label(profileCard, "YOUR CLUB PROFILE", UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 20), C.Cyan, 12, true)
		label(profileCard, "Rank: " .. nz(state.rank, "GUEST") .. "     VIP: " .. (if state.vip == true then "Yes" else "No"),
			UDim2.fromOffset(12, 32), UDim2.new(1, -24, 0, 20), C.White, 11, true)
		label(profileCard, "Tickets: " .. tostring(profile.tickets or state.tickets or 0) ..
			"     Coins: " .. tostring(profile.coins or state.coins or 0), UDim2.fromOffset(12, 56), UDim2.new(1, -24, 0, 20), C.White, 11, false)
		label(profileCard, "Glowsticks: " .. tostring(profile.glowsticks or state.glowsticks or 0) ..
			"     Skip tokens: " .. tostring(profile.skipTokens or state.skipTokens or 0), UDim2.fromOffset(12, 80), UDim2.new(1, -24, 0, 20), C.Muted, 10, false)
		label(profileCard, "Neon trail: " .. (if state.neonTrail == true then "Unlocked" else "Locked"),
			UDim2.fromOffset(12, 100), UDim2.new(1, -24, 0, 18), C.Muted, 10, false)

		local perks: any = if typeof(state.vipPerks) == "table" then state.vipPerks else {}
		local passPerks: any = if typeof(state.passPerks) == "table" then state.passPerks else {}
		local tier = tonumber(state.passTier) or 0
		local vipId = tonumber(state.vipGamePassId) or 0
		local vvipId = tonumber(state.vvipGamePassId) or 0
		local sultanId = tonumber(state.sultanGamePassId) or 0
		local passCard = card(244)
		label(passCard, "ISLAND MEMBERSHIP", UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 22), C.Gold, 14, true)
		label(passCard, "Current tier: " .. nz(state.passName, if tier >= 3 then "TIKI TIDE SULTAN" elseif tier == 2 then "VVIP" elseif tier == 1 then "VIP" else "GUEST"),
			UDim2.fromOffset(12, 32), UDim2.new(1, -24, 0, 20), C.White, 11, true)
		local baseSlots = tonumber(perks.baseSlots) or 2
		local baseCooldown = tonumber(perks.baseCooldown) or 8
		local vip = if typeof(passPerks.vip) == "table" then passPerks.vip else {}
		local vvip = if typeof(passPerks.vvip) == "table" then passPerks.vvip else {}
		local sultan = if typeof(passPerks.sultan) == "table" then passPerks.sultan else {}
		label(passCard, string.format("VIP  •  %d slots  •  %ds cooldown  •  priority requests",
			type(vip.slots) == "number" and vip.slots or (tonumber(perks.slots) or 4),
			type(vip.cooldown) == "number" and vip.cooldown or (tonumber(perks.cooldown) or 3)),
			UDim2.fromOffset(12, 58), UDim2.new(1, -24, 0, 22), C.Muted, 10, false)
		label(passCard, string.format("VVIP  •  %d slots  •  %ds cooldown  •  elevated priority",
			type(vvip.slots) == "number" and vvip.slots or 6,
			type(vvip.cooldown) == "number" and vvip.cooldown or 2),
			UDim2.fromOffset(12, 84), UDim2.new(1, -24, 0, 22), C.Cyan, 10, false)
		label(passCard, string.format("TIKI TIDE SULTAN  •  %d slots  •  %ds cooldown  •  highest priority",
			type(sultan.slots) == "number" and sultan.slots or 8,
			type(sultan.cooldown) == "number" and sultan.cooldown or 1),
			UDim2.fromOffset(12, 110), UDim2.new(1, -24, 0, 22), C.Gold, 10, true)
		label(passCard, string.format("Guest baseline: %d slots and %ds cooldown. Higher passes include lower-tier benefits.",
			baseSlots, baseCooldown), UDim2.fromOffset(12, 136), UDim2.new(1, -24, 0, 28), C.Muted, 9, false)
		if tier < 1 and vipId > 0 then
			actionButton(passCard, "GET VIP", UDim2.new(0, 12, 1, -38), UDim2.new(0.31, -8, 0, 28), function()
				MarketplaceService:PromptGamePassPurchase(player, vipId)
			end, C.Magenta)
		end
		if tier < 2 and vvipId > 0 then
			actionButton(passCard, "GET VVIP", UDim2.new(0.345, 0, 1, -38), UDim2.new(0.31, -8, 0, 28), function()
				MarketplaceService:PromptGamePassPurchase(player, vvipId)
			end, C.Cyan)
		end
		if tier < 3 and sultanId > 0 then
			actionButton(passCard, "GET SULTAN", UDim2.new(0.69, 0, 1, -38), UDim2.new(0.31, -8, 0, 28), function()
				MarketplaceService:PromptGamePassPurchase(player, sultanId)
			end, C.Gold)
		end
	end

	local renderers: {[string]: () -> ()} = {
		["Home"] = renderHome,
		["Music"] = renderMusic,
		["All Tracks"] = function() renderAllTracks(false) end,
		["Playlists"] = function() renderAllTracks(true) end,
		["Queue"] = renderQueue,
		["Audio ID"] = renderAudioId,
		["DJ Booth"] = renderDJ,
		["XP & Boosts"] = renderXPBoosts,
		["Tip Jar"] = renderTipJar,
		["Item Shop"] = renderShop,
		["Daily Rewards"] = renderRewards,
		["Title Tag"] = renderTags,
		["Community"] = renderCommunity,
		["Moderation"] = renderModeration,
	}

	local function refreshNav()
		local moderationButton = navButtons["Moderation"]
		if moderationButton then moderationButton.Visible = perm() >= 1 end
		local playlistsButton = navButtons["Playlists"]
		if playlistsButton then playlistsButton.Visible = perm() >= 1 end
		local audioButton = navButtons["Audio ID"]
		if audioButton then audioButton.Visible = perm() >= 1 end
		if (activeTab == "Moderation" or activeTab == "Audio ID" or activeTab == "Playlists") and perm() < 1 then activeTab = "Home" end
	end

	local function applyMenuTypography()
		-- Keep typography readable without fighting the panel's device UIScale.
		local scaleByDevice = {Desktop=1.04, Tablet=0.98, Mobile=0.92, Console=1.02, VR=0.96}
		local textScale = scaleByDevice[currentDevice] or 1
		for _, item in ipairs(panel:GetDescendants()) do
			if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
				local baseSize = item:GetAttribute("ClubBaseTextSize")
				if typeof(baseSize) ~= "number" then
					baseSize = item.TextSize
					item:SetAttribute("ClubBaseTextSize", baseSize)
				end
				local minSize = if currentDevice == "Mobile" then 8 else 9
				local maxSize = if currentDevice == "Mobile" then 25 else 28
				item.TextSize = math.clamp(math.floor(baseSize * textScale + 0.5), minSize, maxSize)
				if item:IsA("TextButton") then
					item.TextScaled = false
					item.Font = BOLD
				elseif item:IsA("TextBox") then
					item.TextScaled = false
					item.Font = FONT
				end
			end
		end

		-- Every tab shares the same editorial hierarchy: confident titles,
		-- calm supporting copy, and compact but legible control labels.
		for _, item in ipairs(content:GetDescendants()) do
			if item:IsA("TextLabel") then
				local baseSize = item:GetAttribute("ClubBaseTextSize")
				if typeof(baseSize) ~= "number" then
					baseSize = item.TextSize
					item:SetAttribute("ClubBaseTextSize", baseSize)
				end
				item.Font = if baseSize >= 13 then BOLD else FONT
				item.TextScaled = false
				-- Longer descriptions can wrap in their existing card area rather
				-- than being forced into an unreadably small font.
				local height = item.Size.Y.Offset
				if height >= 26 and #item.Text > 34 then
					item.TextWrapped = true
				end
			elseif item:IsA("TextButton") then
				item.Font = BOLD
				item.TextScaled = false
			elseif item:IsA("TextBox") then
				item.Font = FONT
				item.TextScaled = false
			end
		end
	end
	local function renderTab()
		refreshNav()
		local tabChanged = lastRenderedTab ~= activeTab
		lastRenderedTab = activeTab
		if tabChanged then content.CanvasPosition = Vector2.zero end
		clearContent()
		local renderer = renderers[activeTab]
		if renderer then renderer() end
		for name, button in pairs(navButtons) do
			local selected = name == activeTab
			local selectionAccent = navSelectionAccents[name]
			if selectionAccent then
				selectionAccent.Visible = selected and sideRailMode
			end
			button.BackgroundColor3 = if selected then Color3.fromRGB(57, 49, 37) else Color3.fromRGB(25, 30, 43)
			button.BackgroundTransparency = if selected then 0 else 0.08
			local outline = button:FindFirstChildOfClass("UIStroke")
			if outline then
				outline.Color = if selected then C.Gold else C.SurfaceLight
				outline.Transparency = if selected then 0.12 else 0.58
				outline.Thickness = if selected then 1.4 else 1
			end
			local iconRoot = navIconLabels[name]
			local iconBadge = navIconBadges[name]
			local textLabel = navTextLabels[name]
			local iconColor = if selected then C.Gold else C.Muted
			if iconRoot then
				for _, part in ipairs(iconRoot:GetDescendants()) do
					if part:IsA("UIStroke") then
						part.Color = iconColor
						part.Transparency = if selected then 0.02 else 0.12
					elseif part:IsA("Frame") and part.BackgroundTransparency < 1 then
						part.BackgroundColor3 = iconColor
					end
				end
			end
			if iconBadge then
				iconBadge.BackgroundColor3 = if selected then Color3.fromRGB(76, 63, 43) else Color3.fromRGB(35, 41, 55)
				local badgeStroke = iconBadge:FindFirstChildOfClass("UIStroke")
				if badgeStroke then
					badgeStroke.Color = if selected then C.Gold else C.SurfaceLight
					badgeStroke.Transparency = if selected then 0.18 else 0.68
				end
			end
			if textLabel then
				textLabel.TextColor3 = if selected then C.Gold else C.White
				textLabel.Font = if selected then BOLD else FONT
				textLabel.TextSize = if selected then 13 else 12
			end
		end
		applyMenuTypography()
		if tabChanged then
			-- Keep the active destination visible in the horizontal navigation on
			-- narrow screens and gamepad layouts without moving it on state refreshes.
			local selectedButton = navButtons[activeTab]
			if selectedButton then
				task.defer(function()
					if destroyed or not selectedButton.Parent or not nav.Parent then return end
							if sideRailMode then
						local top = selectedButton.AbsolutePosition.Y - nav.AbsolutePosition.Y + nav.CanvasPosition.Y
						local bottom = top + selectedButton.AbsoluteSize.Y
						local visibleTop = nav.CanvasPosition.Y
						local visibleBottom = visibleTop + nav.AbsoluteSize.Y
						local targetY = visibleTop
						if top < visibleTop then targetY = top
						elseif bottom > visibleBottom then targetY = bottom - nav.AbsoluteSize.Y
						else return end
						local maxY = math.max(0, nav.AbsoluteCanvasSize.Y - nav.AbsoluteSize.Y)
					targetY = math.clamp(targetY, 0, maxY)
						TweenService:Create(nav, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							CanvasPosition = Vector2.new(0, targetY),
						}):Play()
					else
						local left = selectedButton.AbsolutePosition.X - nav.AbsolutePosition.X + nav.CanvasPosition.X
						local right = left + selectedButton.AbsoluteSize.X
						local visibleLeft = nav.CanvasPosition.X
						local visibleRight = visibleLeft + nav.AbsoluteSize.X
						local targetX = visibleLeft
						if left < visibleLeft then targetX = left
						elseif right > visibleRight then targetX = right - nav.AbsoluteSize.X
						else return end
						local maxX = math.max(0, nav.AbsoluteCanvasSize.X - nav.AbsoluteSize.X)
						targetX = math.clamp(targetX, 0, maxX)
						TweenService:Create(nav, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							CanvasPosition = Vector2.new(targetX, 0),
						}):Play()
					end
				end)
			end
		end
	end

	renderTabFn = renderTab

	for index, tabName in ipairs(tabs) do
		local button = make("TextButton", {
			Name = tabName:gsub("%s","") .. "Tab",
			Size = UDim2.fromOffset(116, 38),
			BackgroundColor3 = Color3.fromRGB(25, 30, 43),
			BackgroundTransparency = 0.08,
			Text = "",
			AutoButtonColor = true,
			Selectable = true,
			LayoutOrder = index * 10 + 5,
		}, nav) :: TextButton
		corner(button, 12)
		local selectionAccent = make("Frame", {
			Name = "SelectedAccent",
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.fromOffset(3, 24),
			BackgroundColor3 = C.Gold,
			BorderSizePixel = 0,
			Visible = false,
		}, button) :: Frame
		corner(selectionAccent, 2)
		navSelectionAccents[tabName] = selectionAccent
		local navStroke = stroke(button, C.Gold, 1)
		navStroke.Transparency = 0.58
		bindFocusFeedback(button, navStroke, Color3.fromRGB(25, 30, 43))
		local iconBadge = make("Frame", {
			Name = "IconBadge",
			Position = UDim2.fromOffset(7, 6),
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = Color3.fromRGB(35, 41, 55),
			BorderSizePixel = 0,
		}, button) :: Frame
		corner(iconBadge, 9)
		local badgeStroke = stroke(iconBadge, C.SurfaceLight, 1)
		badgeStroke.Transparency = 0.72
		local iconLabel = createNavIcon(iconBadge, tabName)
		local textLabel = make("TextLabel", {
			Name = "NavLabel",
			Position = UDim2.fromOffset(39, 0),
			Size = UDim2.new(1, -45, 1, 0),
			BackgroundTransparency = 1,
			Text = tabName,
			TextColor3 = C.White,
			TextSize = 11,
			Font = FONT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, button) :: TextLabel
		navButtons[tabName] = button
		navIconLabels[tabName] = iconLabel
		navTextLabels[tabName] = textLabel
		navIconBadges[tabName] = iconBadge
		if tabName == "Moderation" or tabName == "Audio ID" then button.Visible = false end
		button.Activated:Connect(function()
			activeTab = tabName
			renderTab()
		end)
	end

	local function applyState(newState: any)
		if destroyed or typeof(newState) ~= "table" then return end
		local cleanState = sanitizeStateValue(newState, 0, {})
		if typeof(cleanState) ~= "table" then return end
		state = cleanState
		syncElapsed()
		updateHud()
		if not destroyed then renderTab() end
	end

	applyStateFn = applyState

	local function open()
		if destroyed then return end
		expanded = true
		shade.Visible = true
		panel.Visible = true
		toggleButton.Visible = false
		panel.Size = UDim2.new(panelTarget.X.Scale * 0.95, 0, panelTarget.Y.Scale * 0.95, 0)
		TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = panelTarget,
		}):Play()
		renderTab()
		if UserInputService.GamepadEnabled then
			task.defer(function()
				if expanded and navButtons[activeTab] and navButtons[activeTab].Visible then
					GuiService.SelectedObject = navButtons[activeTab]
				end
			end)
		end
	end

	local function close()
		if destroyed then return end
		stopPreview()
		expanded = false
		shade.Visible = false
		panel.Visible = false
		toggleButton.Visible = true
		if UserInputService.GamepadEnabled then GuiService.SelectedObject = toggleButton end
	end

	toggleButton.Activated:Connect(open)
	hud.Activated:Connect(function()
		if expanded then close() else open() end
	end)
	closeButton.Activated:Connect(close)
	shade.Activated:Connect(close)

	-- Applies the compact device profile (re-runs on resize, rotation and input-device changes).
	local function applyLayout()
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		currentDevice = detectDevice(viewport)
		local profile = PROFILES[currentDevice]

		local fit = math.clamp(math.min(viewport.X / profile.refX, viewport.Y / profile.refY), profile.minF, 1)
		layoutScale = profile.base * fit
		panelScale.Scale = layoutScale

		-- Calculate constraints from the actual viewport target. Fixed pixel maxima
		-- capped larger desktop panels, while fixed minima could force short mobile
		-- viewports to overflow. UISizeConstraint is evaluated before UIScale, so
		-- convert the intended on-screen dimensions back into panel-local units.
		local targetWidth = math.max(1, viewport.X * profile.w / layoutScale)
		local targetHeight = math.max(1, viewport.Y * profile.h / layoutScale)
		local targetSize = Vector2.new(targetWidth, targetHeight)
		local safeMinimum = Vector2.new(
			math.min(profile.min.X, targetWidth * 0.90),
			math.min(profile.min.Y, targetHeight * 0.90)
		)
		sizeConstraint.MinSize = safeMinimum
		sizeConstraint.MaxSize = targetSize
		panelTarget = UDim2.new(profile.w / layoutScale, 0, profile.h / layoutScale, 0)
		if expanded then panel.Size = panelTarget end

		toggleButton.Size = UDim2.fromOffset(profile.toggle, profile.toggle)
		toggleButton.Position = profile.togglePos
		toggleButton.TextSize = math.floor(profile.toggle * 0.52)
		sideRailMode = currentDevice == "Desktop" and viewport.X >= 1180 and viewport.Y >= 650
		local compactNav = currentDevice == "Mobile" or currentDevice == "Tablet"
		local navHeight = if compactNav then 36 else 40
		local iconSize = if currentDevice == "Mobile" then 23 elseif currentDevice == "Tablet" then 25 else 27
		local badgeOffset = if compactNav then 6 else 7
		navLayout.FillDirection = if sideRailMode then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
		nav.ScrollingDirection = if sideRailMode then Enum.ScrollingDirection.Y else Enum.ScrollingDirection.X
		nav.AutomaticCanvasSize = if sideRailMode then Enum.AutomaticSize.Y else Enum.AutomaticSize.X
		nav.CanvasPosition = Vector2.zero
		navDivider.Visible = sideRailMode
		for index, heading in ipairs(navGroupLabels) do
			heading.Visible = sideRailMode and (index ~= 3 or perm() >= 1)
			heading.LayoutOrder = if index == 1 then 10 elseif index == 2 then 70 else 130
		end
		if sideRailMode then
			nav.Position = UDim2.fromOffset(0, 76)
			nav.Size = UDim2.new(0, 150, 1, -76)
			content.Position = UDim2.fromOffset(162, 88)
			content.Size = UDim2.new(1, -174, 1, -100)
		else
			nav.Position = UDim2.fromOffset(0, 76)
			nav.Size = UDim2.new(1, 0, 0, 46)
			content.Position = UDim2.fromOffset(12, 130)
			content.Size = UDim2.new(1, -24, 1, -142)
		end
		for name, button in pairs(navButtons) do
			local width = if sideRailMode then 136 elseif compactNav then 108 else 120
			if not sideRailMode and (name == "Daily Rewards" or name == "XP & Boosts") then width += 12 end
			button.Size = UDim2.fromOffset(width, navHeight)
			button.LayoutOrder = (table.find(tabs, name) or 1) * 10 + 5
			local badge = navIconBadges[name]
			local glyph = navIconLabels[name]
			local textLabel = navTextLabels[name]
			if badge then
				badge.Position = UDim2.fromOffset(badgeOffset, math.floor((navHeight - iconSize) / 2))
				badge.Size = UDim2.fromOffset(iconSize, iconSize)
			end
			-- Icon geometry scales with its badge, so no font-size adjustment is needed.
			if textLabel then
				textLabel.Position = UDim2.fromOffset(badgeOffset + iconSize + 7, 0)
				textLabel.Size = UDim2.new(1, -(badgeOffset + iconSize + 13), 1, 0)
			end
		end

		hudScale.Scale = layoutScale
		hudConstraint.MaxSize = Vector2.new(math.clamp(viewport.X - 20, 260, 760), 68)
		local compactHud = viewport.X < 430
		hud.Size = UDim2.new(0.96 / layoutScale, 0, 0, 68)
		hudEyebrow.TextSize = if compactHud then 7 else 8
		hudTitle.TextSize = if compactHud then 11 else 14
		hudArtist.TextSize = if compactHud then 8 else 10
		hudTime.TextSize = if compactHud then 8 else 10
		hudStatus.TextSize = if compactHud then 7 else 9
		hudTitle.Size = UDim2.new(1, if compactHud then -142 else -210, 0, 20)
		hudArtist.Size = UDim2.new(1, if compactHud then -142 else -210, 0, 15)
		hudEyebrow.Size = UDim2.new(1, if compactHud then -142 else -210, 0, 12)
		hudTime.Size = UDim2.fromOffset(if compactHud then 78 else 104, 16)
		hudStatus.Size = UDim2.fromOffset(if compactHud then 78 else 104, 15)
		hud.Position = UDim2.new(0.5, 0, 0, profile.hudTop)
		hudBottom = profile.hudTop + math.floor(68 * layoutScale) + 8
		if expanded then applyMenuTypography() end
	end

	local cameraConnection: RBXScriptConnection? = nil
	local function bindCamera()
		if cameraConnection then cameraConnection:Disconnect(); cameraConnection = nil end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
			table.insert(connections, cameraConnection)
		end
		applyLayout()
	end
	bindCamera()
	table.insert(connections, UserInputService.LastInputTypeChanged:Connect(applyLayout))
	table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.M then
			if expanded then close() else open() end
		elseif input.KeyCode == Enum.KeyCode.ButtonY and not expanded then
			open()
		elseif input.KeyCode == Enum.KeyCode.ButtonB and expanded then
			close()
		end
	end))

	if typeof(Network.OnStateChanged) == "function" then
		local connection = Network.OnStateChanged(applyState)
		if typeof(connection) == "RBXScriptConnection" then
			table.insert(connections, connection)
		elseif typeof(connection) == "table" and typeof(connection.Disconnect) == "function" then
			-- Supports custom connection objects returned by alternate network modules.
			table.insert(connections, {
				Connected = true,
				Disconnect = function() connection:Disconnect() end,
			} :: any)
		end
	end

	if typeof(Network.GetState) == "function" then
		local ok, initialState = pcall(Network.GetState)
		if ok and typeof(initialState) == "table" then applyState(initialState) end
	end
	syncElapsed()

	task.spawn(function()
		while not destroyed do
			task.wait(1)
			updateProgress()
			updateHud()
		end
	end)

	-- Route directional input to the volume slider only while it owns gamepad/keyboard focus.
	table.insert(connections, UserInputService.InputBegan:Connect(function(input)
		local refs = sliderRefs
		if not refs or GuiService.SelectedObject ~= refs.control then return end
		if input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.Left then
			refs.adjust(-0.1)
		elseif input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.Right then
			refs.adjust(0.1)
		end
	end))

	-- Volume slider dragging
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if not sliderDragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local refs = sliderRefs
			if refs and refs.track.Parent then refs.setFromX(input.Position.X) end
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			sliderDragging = false
		end
	end))

	-- Audio visualizer (~30 fps) for the panel and the top bar HUD. Uses Network.GetLoudness() (0-1, or
	-- PlaybackLoudness 0-1000) when provided, otherwise an animated beat pattern scaled by the volume slider.
	local vizClock = 0
	local visualizerTime = 0
	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		vizClock += dt
		if vizClock < 1 / 30 or destroyed then return end
		-- Use accumulated active-playback time instead of wall-clock time so
		-- the fallback beat animation freezes on pause and continues on resume.
		if not playbackIsPaused() then
			visualizerTime += vizClock
		end
		vizClock = 0

		local playing = typeof(state.nowPlaying) == "table"
		local paused = playbackIsPaused()
		local t = visualizerTime
		local energy = 0.1
		-- A paused server track must not keep the visualizer reacting to stale
		-- PlaybackLoudness values; retain only the quiet idle baseline.
		if playing and not paused then
			local loud: number? = nil
			if typeof(Network.GetLoudness) == "function" then
				local ok, value = pcall(Network.GetLoudness)
				if ok and typeof(value) == "number" then
					loud = if value > 1 then value / 600 else value
				end
			end
			energy = if loud then math.clamp(loud, 0, 1) else 0.55 + 0.45 * (math.abs(math.sin(t * 2.2)) ^ 4)
		end
		local level = if volume <= 0 then 0 else 0.25 + 0.75 * volume

		for i, piece in ipairs(hudBars) do
			local wave = 0.5 + 0.5 * math.sin(t * (3 + i * 1.3) + i * 1.7)
			piece.Size = UDim2.new(0, 3, math.clamp(0.12 + 0.88 * energy * level * wave, 0.12, 1), 0)
		end

		if expanded then
			for _, update in ipairs(titleAnimators) do update(t) end
		end

		local refs = vizRefs
		if expanded and refs and refs.container.Parent then
			for i, piece in ipairs(refs.bars) do
				local wave = 0.5 + 0.5 * math.sin(t * (2 + (i % 5) * 0.7) + refs.phases[i])
				local noise = math.noise(i * 0.43 + refs.seed, t * 1.3) * 0.5 + 0.5
				local height = 0.08 + 0.92 * energy * level * (0.5 * wave + 0.5 * noise)
				piece.Size = UDim2.new(1 / #refs.bars, -2, math.clamp(height, 0.06, 1), 0)
			end
		end
	end))

	renderTab()

	local mounted = {
		Gui = gui,
		Notify = notify,
		Open = open,
		Close = close,
		Destroy = function()
			if destroyed then return end
			destroyed = true
			lookupSerial += 1
			stopPreview()
			if playerAudioPreferences then
				pcall(function() playerAudioPreferences:Cleanup() end)
				playerAudioPreferences = nil
			end
			for _, connection in ipairs(connections) do
				pcall(function()
					if connection.Connected then connection:Disconnect() end
				end)
			end
			table.clear(connections)
			if gui.Parent then gui:Destroy() end
		end,
	}

	gui.Destroying:Connect(function()
		if not destroyed then
			destroyed = true
			lookupSerial += 1
			stopPreview()
			if playerAudioPreferences then
				pcall(function() playerAudioPreferences:Cleanup() end)
				playerAudioPreferences = nil
			end
			for _, connection in ipairs(connections) do
				pcall(function() if connection.Connected then connection:Disconnect() end end)
			end
			table.clear(connections)
		end
	end)

	return mounted
end

return Renderer
