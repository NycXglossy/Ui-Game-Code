--!nonstrict
-- UI_Renderer
-- Place as ModuleScript: ReplicatedStorage/UI_Renderer
-- Builds the complete client UI. All privileged actions are delegated to UI_Network/server.
--
-- Layout is responsive: the main window sizes itself to the available screen area and switches
-- between a sidebar layout (PC / tablet / console) and a top tab strip (phones / small windows).
-- Console and VR get a larger UI scale and gamepad navigation; blur is skipped in VR.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local GroupService = game:GetService("GroupService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local VRService = game:GetService("VRService")
local SoundService = game:GetService("SoundService")

local Renderer = {}

local C = {
    Base = Color3.fromRGB(15, 14, 18),
    Surface = Color3.fromRGB(26, 24, 34),
    SurfaceLight = Color3.fromRGB(40, 36, 51),
    Magenta = Color3.fromRGB(255, 46, 147),
    Cyan = Color3.fromRGB(0, 240, 255),
    Orange = Color3.fromRGB(255, 140, 0),
    Gold = Color3.fromRGB(252, 211, 77),
    Purple = Color3.fromRGB(88, 28, 135),
    Green = Color3.fromRGB(46, 204, 113),
    Red = Color3.fromRGB(130, 35, 55),
    White = Color3.fromRGB(255, 255, 255),
    Muted = Color3.fromRGB(160, 155, 175),
    Wood = Color3.fromRGB(70, 38, 28),
}
local FONT = Enum.Font.Gotham
local BOLD = Enum.Font.GothamBold

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
}

-- Flat catalog used by "All Tracks", "Favorites" and track lookups.
local TRACK_INDEX = {}
local ALL_TRACKS = {}
for _, genre in ipairs(GENRES) do
    for _, t in ipairs(genre.tracks) do
        local item = {id = t[1], title = t[2], artist = t[3], duration = t[4], genreId = genre.id, genre = genre.name, color = genre.color}
        TRACK_INDEX[item.id] = item
        table.insert(ALL_TRACKS, item)
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
    {name="VIP Backstage Pass",desc="Backstage lounge, private bar and stage view.",price=1500,rarity="Legendary",kind="GamePass",id=0},
    {name="Neon Flower Lei",desc="Glowing hibiscus lei with petal trails.",price=150,rarity="Rare",kind="Product",id=0},
    {name="LED Party Shades",desc="Visualizer lenses that react to the current track.",price=320,rarity="Epic",kind="Product",id=0},
}
local REWARDS = {
    {day=1,label="50 Coins"},{day=2,label="2x Glowsticks"},{day=3,label="100 Tickets"},
    {day=4,label="Song Skip Token"},{day=5,label="250 Coins"},{day=6,label="Neon Trail"},{day=7,label="Exclusive Title Tag"},
}
local TAGS = {
    {id="vip",label="VIP",source="VIP Pass",owned=true,a=Color3.fromRGB(244,114,182),b=Color3.fromRGB(217,70,239)},
    {id="party",label="Party Animal",source="Dance 10 hours",owned=true,a=Color3.fromRGB(251,146,60),b=Color3.fromRGB(252,211,77)},
    {id="wave",label="Wave Rider",source="Login streak",owned=true,a=Color3.fromRGB(103,232,249),b=Color3.fromRGB(14,165,233)},
    {id="tiki",label="Tiki Legend",source="Shop",owned=false,price=400,a=Color3.fromRGB(252,211,77),b=Color3.fromRGB(239,68,68)},
    {id="sunset",label="Sunset Soul",source="Shop",owned=false,price=250,a=Color3.fromRGB(236,72,153),b=Color3.fromRGB(253,224,71)},
    {id="bass",label="Bass Head",source="Shop",owned=false,price=150,a=Color3.fromRGB(167,139,250),b=Color3.fromRGB(99,102,241)},
    {id="island",label="Island Royalty",source="Day 7 reward",owned=false,a=Color3.fromRGB(254,240,138),b=Color3.fromRGB(168,85,247)},
}

-- Instance helpers ------------------------------------------------------------------------------

local function corner(parent, radius)
    local obj = Instance.new("UICorner")
    obj.CornerRadius = UDim.new(0, radius)
    obj.Parent = parent
    return obj
end

local function stroke(parent, color, thickness)
    local obj = Instance.new("UIStroke")
    obj.Color = color
    obj.Thickness = thickness or 1
    obj.Transparency = 0.25
    obj.Parent = parent
    return obj
end

local function gradient(parent, a, b, rotation)
    local obj = Instance.new("UIGradient")
    obj.Color = ColorSequence.new(a, b)
    obj.Rotation = rotation or 0
    obj.Parent = parent
    return obj
end

local function childZ(parent)
    return if parent:IsA("GuiObject") then parent.ZIndex + 1 else 2
end

local function label(parent, text, size, pos, color, textSize, bold)
    local obj = Instance.new("TextLabel")
    obj.ZIndex = childZ(parent)
    obj.BackgroundTransparency = 1
    obj.Size = size
    obj.Position = pos
    obj.Font = if bold then BOLD else FONT
    obj.Text = text
    obj.TextColor3 = color or C.White
    obj.TextSize = textSize or 12
    obj.TextXAlignment = Enum.TextXAlignment.Left
    obj.TextYAlignment = Enum.TextYAlignment.Center
    obj.TextWrapped = true
    obj.Parent = parent
    return obj
end

-- Single line, truncated with "..." instead of wrapping.
local function oneLine(obj)
    obj.TextWrapped = false
    obj.TextTruncate = Enum.TextTruncate.AtEnd
    return obj
end

local function button(parent, text, size, pos, color, callback)
    local obj = Instance.new("TextButton")
    obj.ZIndex = childZ(parent)
    obj.Size = size
    obj.Position = pos
    obj.BackgroundColor3 = color or C.SurfaceLight
    obj.BorderSizePixel = 0
    obj.Font = BOLD
    obj.Text = text
    obj.TextSize = 12
    obj.TextColor3 = C.White
    obj.AutoButtonColor = true
    obj.Parent = parent
    corner(obj, 8)
    if callback then obj.Activated:Connect(callback) end
    return obj
end

-- Greys a button out and removes its click behaviour.
local function disable(btn, text)
    if text then btn.Text = text end
    btn.BackgroundColor3 = C.Surface
    btn.TextColor3 = C.Muted
    btn.AutoButtonColor = false
    btn.Active = false
end

local function panel(parent, height, accent)
    local obj = Instance.new("Frame")
    obj.ZIndex = childZ(parent)
    obj.Size = UDim2.new(1, -8, 0, height)
    obj.BackgroundColor3 = C.Surface
    obj.BorderSizePixel = 0
    obj.Parent = parent
    corner(obj, 10)
    stroke(obj, accent or C.SurfaceLight, 1)
    return obj
end

local function clear(container)
    for _, child in ipairs(container:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then child:Destroy() end
    end
end

local function formatTime(seconds)
    local value = math.max(0, math.floor(seconds))
    return string.format("%d:%02d", value // 60, value % 60)
end

local function formatNumber(value)
    local raw = tostring(math.floor(value))
    local reversed = raw:reverse():gsub("(%d%d%d)", "%1,")
    local result = reversed:reverse()
    return if result:sub(1, 1) == "," then result:sub(2) else result
end

local function rankColor(rank)
    if rank == "OWNER" then return C.Gold end
    if rank == "CO-OWNER" then return C.Magenta end
    if rank == "ADMIN" then return C.Orange end
    if rank == "GROUP DJ" then return C.Cyan end
    return C.Muted
end

-- Audio visualizer bars ------------------------------------------------------------------------

local function makeBars(container, count)
    local bars = {}
    for i = 1, count do
        local bar = Instance.new("Frame")
        bar.ZIndex = childZ(container)
        bar.AnchorPoint = Vector2.new(0, 1)
        bar.Position = UDim2.new((i - 1) / count, 1, 1, 0)
        bar.Size = UDim2.new(1 / count, -2, 0.1, 0)
        bar.BackgroundColor3 = C.Magenta:Lerp(C.Cyan, (i - 1) / math.max(1, count - 1))
        bar.BorderSizePixel = 0
        bar.Parent = container
        corner(bar, 2)
        bars[i] = bar
    end
    return bars
end

-- level is 0..1 overall energy. Real loudness drives it when a local Sound is playing;
-- otherwise the bars run a procedural beat so the UI still feels alive without audio assets.
local function updateBars(bars, t, level, beatsPerSecond)
    local count = #bars
    local beat = math.max(0, math.sin(t * math.pi * 2 * beatsPerSecond)) ^ 6
    for i, bar in ipairs(bars) do
        local weight = 1 - ((i - 1) / count) * 0.5 -- bass-heavy on the left
        local wobble = 0.5 + math.noise(i * 0.37, t * 1.9) * 1.1
        local value = (0.12 + 0.55 * math.clamp(wobble, 0, 1) * weight + 0.33 * beat * weight) * level
        bar.Size = UDim2.new(1 / count, -2, math.clamp(value, 0.05, 1), 0)
    end
end

-- Mount ------------------------------------------------------------------------------------------

function Renderer.Mount(player, Network)
    local playerGui = player:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("ClubMusicSystemGui")
    if old then old:Destroy() end

    local config = game:GetService("ReplicatedStorage"):FindFirstChild("ClubMusicConfig")
    local groupId = if config then config:GetAttribute("GroupId") or 0 else 0

    local connections = {}
    local function track(conn)
        table.insert(connections, conn)
        return conn
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "ClubMusicSystemGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    -- Blur is skipped in VR (uncomfortable and unnecessary on a floating panel).
    local blur = nil
    if not VRService.VREnabled then
        blur = Lighting:FindFirstChild("ClubMenuBlur")
        if not blur or not blur:IsA("BlurEffect") then
            blur = Instance.new("BlurEffect")
            blur.Name = "ClubMenuBlur"
            blur.Size = 0
            blur.Parent = Lighting
        end
    end

    ---------------------------------------------------------------------------------------------
    -- State
    ---------------------------------------------------------------------------------------------
    local latestState = Network.GetState()
    local receivedAt = os.clock()
    local currentTab = "music"
    local expanded = false
    local animating = false
    local activeGenre = nil
    local searchText = ""
    local genreFilter = 0 -- 0 = all genres, otherwise index into GENRES
    local volume = 0.7
    local muted = false
    local lastReloadAt = 0
    local lastSig = {}
    local compact = false
    local modalWidth, modalHeight = 720, 440
    local toolbarVisible = false
    local sidebarButtons = {}
    local stripButtons = {}
    local renderTab
    local rerenderIfNeeded
    local relayout

    local function estimatedElapsed()
        local p = latestState and latestState.nowPlaying
        if not p then return 0 end
        local duration = tonumber(p.duration) or 0
        return math.min(duration, (tonumber(p.elapsed) or 0) + (os.clock() - receivedAt))
    end

    local function queuedSet()
        local set = {}
        local s = latestState
        if s and s.queue then
            for _, e in ipairs(s.queue) do set[e.trackId] = true end
        end
        return set
    end

    ---------------------------------------------------------------------------------------------
    -- HUD (top bar + now-playing strip)
    ---------------------------------------------------------------------------------------------
    local hudRoot = Instance.new("Frame")
    hudRoot.Name = "HudRoot"
    hudRoot.BackgroundTransparency = 1
    hudRoot.AnchorPoint = Vector2.new(0.5, 0)
    hudRoot.Position = UDim2.new(0.5, 0, 0, 8)
    hudRoot.Size = UDim2.fromOffset(340, 80)
    hudRoot.Parent = gui
    local hudScale = Instance.new("UIScale")
    hudScale.Parent = hudRoot

    local hud = Instance.new("Frame")
    hud.Name = "TopBarHUD"
    hud.Size = UDim2.new(1, 0, 0, 46)
    hud.BackgroundColor3 = C.Base
    hud.BackgroundTransparency = 0.15
    hud.BorderSizePixel = 0
    hud.Parent = hudRoot
    corner(hud, 12)
    stroke(hud, C.Cyan, 1.5)
    gradient(hud, C.Wood, C.Purple, 90)

    local avatar = Instance.new("ImageLabel")
    avatar.ZIndex = 21
    avatar.Size = UDim2.fromOffset(34, 34)
    avatar.Position = UDim2.fromOffset(6, 6)
    avatar.BackgroundColor3 = C.SurfaceLight
    avatar.BorderSizePixel = 0
    avatar.Parent = hud
    corner(avatar, 17)
    stroke(avatar, C.Magenta, 1.5)
    task.spawn(function()
        local ok, imageUrl = pcall(function()
            return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
        end)
        if ok and gui.Parent then avatar.Image = imageUrl end
    end)

    oneLine(label(hud, player.DisplayName, UDim2.new(1, -212, 0, 18), UDim2.fromOffset(46, 5), C.White, 13, true))
    local rankLabel = oneLine(label(hud, "★ FESTIVAL GUEST", UDim2.new(1, -212, 0, 14), UDim2.fromOffset(46, 24), C.Magenta, 10, true))
    local ticketButton = button(hud, "🎟 0", UDim2.fromOffset(64, 30), UDim2.new(1, -162, 0, 8), C.Base)
    ticketButton.TextColor3 = C.Gold
    ticketButton.AutoButtonColor = false
    local shopButton = button(hud, "R$", UDim2.fromOffset(50, 30), UDim2.new(1, -94, 0, 8), C.Base)
    shopButton.TextColor3 = C.Green
    local expand = button(hud, "☰", UDim2.fromOffset(34, 34), UDim2.new(1, -40, 0, 6), C.SurfaceLight)
    expand.TextColor3 = C.Cyan
    expand.TextSize = 20

    -- Now-playing strip under the HUD (tap to open the queue)
    local mini = Instance.new("TextButton")
    mini.Name = "NowPlayingStrip"
    mini.Text = ""
    mini.AutoButtonColor = false
    mini.Position = UDim2.fromOffset(0, 50)
    mini.Size = UDim2.new(1, 0, 0, 28)
    mini.BackgroundColor3 = C.Base
    mini.BackgroundTransparency = 0.2
    mini.BorderSizePixel = 0
    mini.Parent = hudRoot
    corner(mini, 10)
    stroke(mini, C.Magenta, 1)
    local miniTitle = oneLine(label(mini, "♫ Waiting for track", UDim2.new(1, -112, 1, 0), UDim2.fromOffset(10, 0), C.White, 11, true))
    local miniTime = label(mini, "0:00 / 0:00", UDim2.fromOffset(62, 28), UDim2.new(1, -100, 0, 0), C.Muted, 10, false)
    miniTime.TextXAlignment = Enum.TextXAlignment.Right
    local miniViz = Instance.new("Frame")
    miniViz.BackgroundTransparency = 1
    miniViz.AnchorPoint = Vector2.new(1, 0.5)
    miniViz.Position = UDim2.new(1, -8, 0.5, 0)
    miniViz.Size = UDim2.fromOffset(26, 16)
    miniViz.ZIndex = 3
    miniViz.Parent = mini
    local miniBars = makeBars(miniViz, 6)

    ---------------------------------------------------------------------------------------------
    -- Toast notifications
    ---------------------------------------------------------------------------------------------
    local toastFrame = Instance.new("Frame")
    toastFrame.Name = "Toast"
    toastFrame.AnchorPoint = Vector2.new(0.5, 0)
    toastFrame.Position = UDim2.new(0.5, 0, 0, 92)
    toastFrame.AutomaticSize = Enum.AutomaticSize.XY
    toastFrame.Size = UDim2.fromOffset(0, 0)
    toastFrame.BackgroundColor3 = C.SurfaceLight
    toastFrame.BorderSizePixel = 0
    toastFrame.Visible = false
    toastFrame.ZIndex = 60
    toastFrame.Parent = gui
    corner(toastFrame, 10)
    stroke(toastFrame, C.Cyan, 1)
    local toastPad = Instance.new("UIPadding")
    toastPad.PaddingLeft = UDim.new(0, 14)
    toastPad.PaddingRight = UDim.new(0, 14)
    toastPad.PaddingTop = UDim.new(0, 8)
    toastPad.PaddingBottom = UDim.new(0, 8)
    toastPad.Parent = toastFrame
    local toastLabel = Instance.new("TextLabel")
    toastLabel.ZIndex = 61
    toastLabel.BackgroundTransparency = 1
    toastLabel.AutomaticSize = Enum.AutomaticSize.XY
    toastLabel.Size = UDim2.fromOffset(0, 0)
    toastLabel.Font = BOLD
    toastLabel.TextSize = 12
    toastLabel.TextColor3 = C.White
    toastLabel.TextWrapped = true
    toastLabel.Text = ""
    toastLabel.Parent = toastFrame
    local toastLimit = Instance.new("UISizeConstraint")
    toastLimit.MaxSize = Vector2.new(280, 100)
    toastLimit.Parent = toastLabel
    local toastScale = Instance.new("UIScale")
    toastScale.Parent = toastFrame
    local toastToken = 0

    local function toast(text, kind)
        toastToken += 1
        local mine = toastToken
        toastLabel.Text = text
        toastFrame.BackgroundColor3 = if kind == "warn" then C.Red elseif kind == "ok" then Color3.fromRGB(24, 92, 60) else C.SurfaceLight
        toastFrame.Position = if expanded then UDim2.new(0.5, 0, 0, 10) else UDim2.new(0.5, 0, 0, 92)
        toastFrame.Visible = true
        task.delay(2.8, function()
            if mine == toastToken and toastFrame.Parent then toastFrame.Visible = false end
        end)
    end

    ---------------------------------------------------------------------------------------------
    -- Main window
    ---------------------------------------------------------------------------------------------
    local backdrop = Instance.new("TextButton")
    backdrop.Name = "Backdrop"
    backdrop.Text = ""
    backdrop.AutoButtonColor = false
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3 = Color3.fromRGB(18, 6, 26)
    backdrop.BackgroundTransparency = 1
    backdrop.Visible = false
    backdrop.ZIndex = 5
    backdrop.Parent = gui

    local modal = Instance.new("Frame")
    modal.Name = "MainModal"
    modal.AnchorPoint = Vector2.new(0.5, 0.5)
    modal.Size = UDim2.fromOffset(modalWidth, modalHeight)
    modal.Position = UDim2.fromScale(0.5, 0.5)
    modal.BackgroundColor3 = C.Base
    modal.BackgroundTransparency = 0.05
    modal.BorderSizePixel = 0
    modal.ClipsDescendants = true
    modal.Visible = false
    modal.ZIndex = 10
    modal.SelectionGroup = true
    modal.Parent = gui
    corner(modal, 14)
    stroke(modal, C.Magenta, 1.5)
    local modalScale = Instance.new("UIScale")
    modalScale.Parent = modal

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 42)
    header.BackgroundColor3 = C.Surface
    header.BorderSizePixel = 0
    header.ZIndex = 11
    header.Parent = modal
    label(header, "🌴  SUNSET STAGE", UDim2.new(1, -60, 0, 22), UDim2.fromOffset(14, 4), C.Gold, 15, true)
    label(header, "AUTOMATED MUSIC • BEACH CLUB", UDim2.new(1, -60, 0, 14), UDim2.fromOffset(15, 25), C.Muted, 9, true)
    local closeButton = button(header, "✕", UDim2.fromOffset(32, 32), UDim2.fromOffset(modalWidth - 40, 5), C.SurfaceLight)
    closeButton.ZIndex = 12

    -- Wide layout: vertical sidebar
    local sidebar = Instance.new("ScrollingFrame")
    sidebar.ZIndex = 11
    sidebar.BackgroundColor3 = C.Surface
    sidebar.BorderSizePixel = 0
    sidebar.ScrollBarThickness = 3
    sidebar.ScrollBarImageColor3 = C.Magenta
    sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sidebar.CanvasSize = UDim2.new()
    sidebar.Parent = modal
    corner(sidebar, 10)
    local sideLayout = Instance.new("UIListLayout")
    sideLayout.Padding = UDim.new(0, 4)
    sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
    sideLayout.Parent = sidebar
    local sidePadding = Instance.new("UIPadding")
    sidePadding.PaddingTop = UDim.new(0, 6)
    sidePadding.PaddingBottom = UDim.new(0, 6)
    sidePadding.PaddingLeft = UDim.new(0, 6)
    sidePadding.PaddingRight = UDim.new(0, 8)
    sidePadding.Parent = sidebar

    -- Compact layout: horizontal tab strip
    local tabStrip = Instance.new("ScrollingFrame")
    tabStrip.ZIndex = 11
    tabStrip.BackgroundColor3 = C.Surface
    tabStrip.BorderSizePixel = 0
    tabStrip.ScrollBarThickness = 0
    tabStrip.ScrollingDirection = Enum.ScrollingDirection.X
    tabStrip.AutomaticCanvasSize = Enum.AutomaticSize.X
    tabStrip.CanvasSize = UDim2.new()
    tabStrip.Visible = false
    tabStrip.Parent = modal
    corner(tabStrip, 10)
    local stripLayout = Instance.new("UIListLayout")
    stripLayout.FillDirection = Enum.FillDirection.Horizontal
    stripLayout.Padding = UDim.new(0, 4)
    stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
    stripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    stripLayout.Parent = tabStrip
    local stripPadding = Instance.new("UIPadding")
    stripPadding.PaddingLeft = UDim.new(0, 4)
    stripPadding.PaddingRight = UDim.new(0, 4)
    stripPadding.Parent = tabStrip

    -- Toolbar (search + genre filter) shown on the All Tracks tab
    local toolbar = Instance.new("Frame")
    toolbar.ZIndex = 11
    toolbar.BackgroundTransparency = 1
    toolbar.Visible = false
    toolbar.Parent = modal
    local searchBox = Instance.new("TextBox")
    searchBox.ZIndex = 12
    searchBox.Size = UDim2.new(1, -128, 1, 0)
    searchBox.BackgroundColor3 = C.Surface
    searchBox.BorderSizePixel = 0
    searchBox.Font = FONT
    searchBox.TextSize = 12
    searchBox.TextColor3 = C.White
    searchBox.PlaceholderText = "🔍 Search title or artist"
    searchBox.PlaceholderColor3 = C.Muted
    searchBox.Text = ""
    searchBox.ClearTextOnFocus = false
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.Parent = toolbar
    corner(searchBox, 8)
    stroke(searchBox, C.SurfaceLight, 1)
    local searchPad = Instance.new("UIPadding")
    searchPad.PaddingLeft = UDim.new(0, 10)
    searchPad.Parent = searchBox
    local genreButton = button(toolbar, "All genres", UDim2.fromOffset(120, 30), UDim2.new(1, -120, 0, 0), C.SurfaceLight)
    genreButton.ZIndex = 12
    genreButton.TextSize = 11
    oneLine(genreButton)

    local content = Instance.new("ScrollingFrame")
    content.Name = "ContentPane"
    content.ZIndex = 11
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ScrollBarThickness = 4
    content.ScrollBarImageColor3 = C.Magenta
    content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    content.CanvasSize = UDim2.new()
    content.Parent = modal
    local contentLayout = Instance.new("UIListLayout")
    contentLayout.Padding = UDim.new(0, 7)
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Parent = content
    local contentPadding = Instance.new("UIPadding")
    contentPadding.PaddingBottom = UDim.new(0, 10)
    contentPadding.PaddingRight = UDim.new(0, 6)
    contentPadding.Parent = content

    ---------------------------------------------------------------------------------------------
    -- Now-playing dock (always visible inside the window)
    ---------------------------------------------------------------------------------------------
    local DOCK_H = 84
    local dock = Instance.new("Frame")
    dock.ZIndex = 11
    dock.BackgroundColor3 = C.Surface
    dock.BorderSizePixel = 0
    dock.Parent = modal
    corner(dock, 10)
    stroke(dock, C.Cyan, 1)

    local dockLeft = Instance.new("Frame")
    dockLeft.ZIndex = 12
    dockLeft.BackgroundTransparency = 1
    dockLeft.Size = UDim2.new(1, -90, 1, 0)
    dockLeft.Parent = dock

    local dockViz = Instance.new("Frame")
    dockViz.ZIndex = 12
    dockViz.BackgroundTransparency = 1
    dockViz.AnchorPoint = Vector2.new(1, 0.5)
    dockViz.Position = UDim2.new(1, -8, 0.5, 0)
    dockViz.Size = UDim2.new(0, 74, 1, -18)
    dockViz.Parent = dock
    local dockBars = makeBars(dockViz, 14)

    local dockTitle = oneLine(label(dockLeft, "Waiting for track", UDim2.new(1, -14, 0, 18), UDim2.fromOffset(10, 5), C.White, 13, true))
    local dockMeta = oneLine(label(dockLeft, "", UDim2.new(1, -14, 0, 14), UDim2.fromOffset(10, 23), C.Muted, 10, false))

    local progressTrack = Instance.new("Frame")
    progressTrack.ZIndex = 12
    progressTrack.Position = UDim2.fromOffset(10, 44)
    progressTrack.Size = UDim2.new(1, -84, 0, 6)
    progressTrack.BackgroundColor3 = C.SurfaceLight
    progressTrack.BorderSizePixel = 0
    progressTrack.Parent = dockLeft
    corner(progressTrack, 3)
    local progressFill = Instance.new("Frame")
    progressFill.ZIndex = 13
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.BackgroundColor3 = C.Magenta
    progressFill.BorderSizePixel = 0
    progressFill.Parent = progressTrack
    corner(progressFill, 3)
    gradient(progressFill, C.Magenta, C.Cyan, 0)
    local dockTime = label(dockLeft, "0:00 / 0:00", UDim2.fromOffset(66, 16), UDim2.new(1, -72, 0, 39), C.Muted, 10, false)
    dockTime.TextXAlignment = Enum.TextXAlignment.Right

    local favButton = button(dockLeft, "♡", UDim2.fromOffset(28, 26), UDim2.fromOffset(10, 54), C.SurfaceLight)
    favButton.TextSize = 15
    local reloadButton = button(dockLeft, "⟳", UDim2.fromOffset(28, 26), UDim2.fromOffset(42, 54), C.SurfaceLight)
    reloadButton.TextSize = 16
    local voteButton = button(dockLeft, "⏭ 0/0", UDim2.fromOffset(64, 26), UDim2.fromOffset(74, 54), C.SurfaceLight)
    voteButton.TextSize = 11
    local muteButton = button(dockLeft, "🔊", UDim2.fromOffset(28, 26), UDim2.fromOffset(142, 54), C.SurfaceLight)
    muteButton.TextSize = 13
    local volMinus = button(dockLeft, "−", UDim2.fromOffset(24, 26), UDim2.new(1, -56, 0, 54), C.SurfaceLight)
    local volPlus = button(dockLeft, "+", UDim2.fromOffset(24, 26), UDim2.new(1, -28, 0, 54), C.SurfaceLight)

    local sliderHit = Instance.new("TextButton")
    sliderHit.ZIndex = 12
    sliderHit.Text = ""
    sliderHit.AutoButtonColor = false
    sliderHit.BackgroundTransparency = 1
    sliderHit.Position = UDim2.fromOffset(178, 54)
    sliderHit.Size = UDim2.new(1, -240, 0, 26)
    sliderHit.Parent = dockLeft
    local sliderTrack = Instance.new("Frame")
    sliderTrack.ZIndex = 13
    sliderTrack.AnchorPoint = Vector2.new(0, 0.5)
    sliderTrack.Position = UDim2.new(0, 6, 0.5, 0)
    sliderTrack.Size = UDim2.new(1, -12, 0, 6)
    sliderTrack.BackgroundColor3 = C.SurfaceLight
    sliderTrack.BorderSizePixel = 0
    sliderTrack.Parent = sliderHit
    corner(sliderTrack, 3)
    local sliderFill = Instance.new("Frame")
    sliderFill.ZIndex = 14
    sliderFill.Size = UDim2.new(volume, 0, 1, 0)
    sliderFill.BackgroundColor3 = C.Cyan
    sliderFill.BorderSizePixel = 0
    sliderFill.Parent = sliderTrack
    corner(sliderFill, 3)
    local sliderKnob = Instance.new("Frame")
    sliderKnob.ZIndex = 15
    sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
    sliderKnob.Position = UDim2.new(volume, 0, 0.5, 0)
    sliderKnob.Size = UDim2.fromOffset(14, 14)
    sliderKnob.BackgroundColor3 = C.White
    sliderKnob.BorderSizePixel = 0
    sliderKnob.Parent = sliderTrack
    corner(sliderKnob, 7)

    ---------------------------------------------------------------------------------------------
    -- Local audio (each client plays the current track from the server-reported position)
    ---------------------------------------------------------------------------------------------
    local localSound = nil
    local soundKey = ""

    local function effectiveVolume()
        return if muted then 0 else volume
    end

    local function stopSound()
        if localSound then
            localSound:Destroy()
            localSound = nil
        end
        soundKey = ""
    end

    local function syncSound(force)
        local playing = latestState and latestState.nowPlaying
        local soundId = playing and playing.soundId
        if not playing or typeof(soundId) ~= "string" or soundId == "" then
            stopSound()
            return
        end
        local key = tostring(playing.trackId) .. "|" .. soundId
        if force or key ~= soundKey or not localSound then
            stopSound()
            local snd = Instance.new("Sound")
            snd.Name = "ClubMusicLocal"
            snd.SoundId = soundId
            snd.Volume = effectiveVolume()
            snd.Looped = false
            snd.Parent = SoundService
            localSound = snd
            soundKey = key
            task.spawn(function()
                local started = os.clock()
                while snd.Parent and not snd.IsLoaded and os.clock() - started < 10 do
                    task.wait(0.1)
                end
                if not snd.Parent or not snd.IsLoaded then return end
                local startAt = estimatedElapsed()
                snd.TimePosition = math.clamp(startAt, 0, math.max(0, snd.TimeLength - 0.1))
                snd:Play()
            end)
        elseif localSound.IsLoaded and math.abs(localSound.TimePosition - estimatedElapsed()) > 3 then
            -- Drift correction
            localSound.TimePosition = math.clamp(estimatedElapsed(), 0, math.max(0, localSound.TimeLength - 0.1))
        end
    end

    local function setVolume(value)
        volume = math.clamp(value, 0, 1)
        if volume > 0 then muted = false end
        sliderFill.Size = UDim2.new(volume, 0, 1, 0)
        sliderKnob.Position = UDim2.new(volume, 0, 0.5, 0)
        muteButton.Text = if muted or volume == 0 then "🔇" elseif volume < 0.5 then "🔈" else "🔊"
        if localSound then localSound.Volume = effectiveVolume() end
    end

    -- Slider interaction (mouse, touch and VR pointer). -/+ buttons cover gamepads.
    local draggingVolume = false
    local function volumeFromInput(input)
        local width = sliderTrack.AbsoluteSize.X
        if width <= 0 then return end
        setVolume((input.Position.X - sliderTrack.AbsolutePosition.X) / width)
    end
    track(sliderHit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingVolume = true
            volumeFromInput(input)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if draggingVolume and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            volumeFromInput(input)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingVolume = false
        end
    end))
    muteButton.Activated:Connect(function()
        if muted or volume == 0 then
            muted = false
            if volume == 0 then volume = 0.5 end
        else
            muted = true
        end
        setVolume(volume)
    end)
    volMinus.Activated:Connect(function() setVolume(volume - 0.1) end)
    volPlus.Activated:Connect(function() setVolume(volume + 0.1) end)
    setVolume(volume)

    ---------------------------------------------------------------------------------------------
    -- Favorites / vote skip / reload
    ---------------------------------------------------------------------------------------------
    local function isFavorite(trackId)
        local s = latestState
        return s and s.favorites and s.favorites[trackId] == true or false
    end

    local function toggleFavorite(trackId)
        if not trackId or trackId == "" then return end
        local s = latestState
        if not s then
            toast("Offline - can't save favorites.", "warn")
            return
        end
        s.favorites = s.favorites or {}
        -- Optimistic update; the server's next snapshot confirms it.
        if s.favorites[trackId] then s.favorites[trackId] = nil else s.favorites[trackId] = true end
        Network.ToggleFavorite(trackId)
        if rerenderIfNeeded then rerenderIfNeeded(true) end
    end

    local function updateDockStatics()
        local s = latestState
        local p = s and s.nowPlaying
        if not p then
            dockTitle.Text = "Waiting for track"
            dockMeta.Text = ""
            miniTitle.Text = "♫ Waiting for track"
            return
        end
        dockTitle.Text = "♫  " .. tostring(p.title or "Unknown") .. "  —  " .. tostring(p.artist or "")
        local requester = if p.source == "player" then ("Requested by " .. tostring(p.requestedBy or "a guest") .. (p.vip and "  ★ VIP" or "")) else "Auto DJ"
        dockMeta.Text = "▶ " .. tostring(p.genre or "") .. " playlist   •   " .. requester
        dockMeta.TextColor3 = if p.source == "player" then C.Cyan else C.Muted
        miniTitle.Text = "♫ " .. tostring(p.title or "") .. " — " .. tostring(p.artist or "")

        local fav = isFavorite(p.trackId)
        favButton.Text = if fav then "♥" else "♡"
        favButton.TextColor3 = if fav then C.Magenta else C.White

        local skip = s.skip or {votes = 0, needed = 1, voted = false}
        voteButton.Text = (if skip.voted then "✓ " else "⏭ ") .. tostring(skip.votes) .. "/" .. tostring(skip.needed)
        voteButton.BackgroundColor3 = if skip.voted then Color3.fromRGB(24, 92, 60) else C.SurfaceLight
    end

    favButton.Activated:Connect(function()
        local p = latestState and latestState.nowPlaying
        if p then toggleFavorite(p.trackId) end
        updateDockStatics()
    end)

    voteButton.Activated:Connect(function()
        local s = latestState
        if not s then
            toast("Offline - can't vote.", "warn")
            return
        end
        if s.skip and s.skip.voted then
            toast("You already voted to skip this track.", "warn")
            return
        end
        Network.VoteSkip()
    end)

    reloadButton.Activated:Connect(function()
        if os.clock() - lastReloadAt < 2 then return end
        lastReloadAt = os.clock()
        task.spawn(function()
            local refreshed = Network.Refresh()
            syncSound(true)
            if refreshed then
                toast("Song reloaded and resynced.", "ok")
            else
                toast("Couldn't reach the server.", "warn")
            end
        end)
    end)

    ---------------------------------------------------------------------------------------------
    -- Shared content builders
    ---------------------------------------------------------------------------------------------
    local function addHeading(kicker, title, desc)
        local p = panel(content, 60, C.Magenta)
        label(p, kicker, UDim2.new(1, -24, 0, 12), UDim2.fromOffset(12, 6), C.Cyan, 9, true)
        oneLine(label(p, title, UDim2.new(1, -24, 0, 22), UDim2.fromOffset(12, 18), C.White, 17, true))
        oneLine(label(p, desc, UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 42), C.Muted, 10, false))
    end

    local function addSection(text, color)
        local holder = Instance.new("Frame")
        holder.ZIndex = 11
        holder.BackgroundTransparency = 1
        holder.Size = UDim2.new(1, -8, 0, 18)
        holder.Parent = content
        label(holder, text, UDim2.new(1, 0, 1, 0), UDim2.fromOffset(2, 0), color or C.Cyan, 10, true)
    end

    local function addEmpty(text)
        local p = panel(content, 56, C.SurfaceLight)
        label(p, text, UDim2.new(1, -24, 1, -12), UDim2.fromOffset(12, 6), C.Muted, 12, false)
    end

    local function promptPurchase(kind, id)
        if id <= 0 then
            warn("[ClubMusic] Configure the real " .. kind .. " asset ID before enabling this purchase.")
            toast("This item isn't available yet.", "warn")
            return
        end
        if kind == "GamePass" then
            MarketplaceService:PromptGamePassPurchase(player, id)
        else
            MarketplaceService:PromptProductPurchase(player, id)
        end
    end

    -- Returns the label + whether the request button is usable for this track
    local function requestStatus(trackId)
        local s = latestState
        if not s then return "OFFLINE", false end
        if s.blocked then return "BLOCKED", false end
        if s.locked and (s.perm or 0) < 1 then return "LOCKED", false end
        local p = s.nowPlaying
        if p and p.trackId == trackId then return "PLAYING", false end
        if queuedSet()[trackId] then return "QUEUED", false end
        local req = s.requests
        if req and req.used >= req.limit then return "LIMIT " .. req.used .. "/" .. req.limit, false end
        return "REQUEST", true
    end

    local function trackRow(item, showGenre)
        local row = panel(content, 52, item.color)
        local fav = isFavorite(item.id)
        local favBtn = button(row, if fav then "♥" else "♡", UDim2.fromOffset(30, 30), UDim2.fromOffset(8, 11), C.Surface, function()
            toggleFavorite(item.id)
        end)
        favBtn.TextSize = 16
        favBtn.TextColor3 = if fav then C.Magenta else C.Muted
        oneLine(label(row, item.title, UDim2.new(1, -152, 0, 18), UDim2.fromOffset(46, 7), C.White, 12, true))
        local meta = item.artist .. "  •  " .. formatTime(item.duration)
        if showGenre then meta = item.artist .. "  •  " .. item.genre .. "  •  " .. formatTime(item.duration) end
        oneLine(label(row, meta, UDim2.new(1, -152, 0, 14), UDim2.fromOffset(46, 28), C.Muted, 10, false))

        local text, usable = requestStatus(item.id)
        local request = button(row, text, UDim2.fromOffset(92, 30), UDim2.new(1, -100, 0.5, -15), item.color, usable and function()
            Network.RequestTrack(item.genreId, item.id)
        end or nil)
        request.TextSize = 11
        if not usable then disable(request, text) end
    end

    ---------------------------------------------------------------------------------------------
    -- Tabs
    ---------------------------------------------------------------------------------------------
    local tabDefs = {
        {"music", "♫", "Music"}, {"all", "☰", "All Tracks"}, {"queue", "≡", "Queue"}, {"fav", "♥", "Favorites"},
        {"dj", "✦", "DJ Booth"}, {"donate", "♡", "Tip Jar"}, {"shop", "◇", "Item Shop"},
        {"rewards", "★", "Rewards"}, {"tags", "✧", "Title Tag"}, {"group", "♧", "Community"},
    }

    local function renderMusic()
        clear(content)
        local p = latestState and latestState.nowPlaying
        addHeading("PLAYLISTS", "Choose your sound", "Browse a genre playlist and request tracks. Favorite with ♥.")
        if activeGenre then
            local back = panel(content, 42, C.Cyan)
            button(back, "←  ALL", UDim2.fromOffset(84, 28), UDim2.fromOffset(7, 7), C.SurfaceLight, function()
                activeGenre = nil
                renderMusic()
            end)
            oneLine(label(back, activeGenre.name, UDim2.new(1, -108, 1, 0), UDim2.fromOffset(100, 0), activeGenre.color, 14, true))
            for _, item in ipairs(ALL_TRACKS) do
                if item.genreId == activeGenre.id then trackRow(item, false) end
            end
            return
        end
        for _, genre in ipairs(GENRES) do
            local row = panel(content, 60, genre.color)
            oneLine(label(row, genre.name, UDim2.new(1, -140, 0, 22), UDim2.fromOffset(12, 8), C.White, 14, true))
            oneLine(label(row, genre.tagline .. "  •  " .. #genre.tracks .. " tracks", UDim2.new(1, -140, 0, 16), UDim2.fromOffset(12, 32), C.Muted, 10, false))
            local live = p and p.genre == genre.name
            local b = button(row, if live then "▶ LIVE" else "BROWSE →", UDim2.fromOffset(104, 32), UDim2.new(1, -112, 0.5, -16), genre.color, function()
                activeGenre = genre
                renderMusic()
            end)
            b.TextSize = 11
        end
    end

    local function renderAll()
        clear(content)
        local needle = string.lower(searchText)
        local shown = 0
        for _, item in ipairs(ALL_TRACKS) do
            local genreOk = genreFilter == 0 or item.genreId == GENRES[genreFilter].id
            local textOk = needle == "" or string.find(string.lower(item.title), needle, 1, true) ~= nil
                or string.find(string.lower(item.artist), needle, 1, true) ~= nil
            if genreOk and textOk then
                if shown == 0 then
                    addSection("ALL TRACKS — tap ♥ to favorite, REQUEST to queue", C.Cyan)
                end
                shown += 1
                trackRow(item, true)
            end
        end
        if shown == 0 then addEmpty("No tracks match your search.") end
    end

    local function renderFavorites()
        clear(content)
        addHeading("YOUR PICKS", "Favorite Tracks", "Songs you love, saved to your profile.")
        local shown = 0
        for _, item in ipairs(ALL_TRACKS) do
            if isFavorite(item.id) then
                shown += 1
                trackRow(item, true)
            end
        end
        if shown == 0 then addEmpty("No favorites yet. Tap ♡ on any track (or in the player below) to save it here.") end
    end

    local function renderQueue()
        clear(content)
        local s = latestState
        local queue = s and s.queue or {}
        local total = 0
        for _, e in ipairs(queue) do total += tonumber(e.duration) or 0 end
        addHeading("LIVE QUEUE", "Up Next", #queue .. " queued  •  " .. formatTime(total) .. " of music lined up")

        local p = s and s.nowPlaying
        if p then
            local row = panel(content, 62, C.Gold)
            oneLine(label(row, "NOW PLAYING", UDim2.new(1, -20, 0, 12), UDim2.fromOffset(12, 6), C.Gold, 9, true))
            oneLine(label(row, tostring(p.title), UDim2.new(1, -20, 0, 18), UDim2.fromOffset(12, 18), C.White, 13, true))
            local by = if p.source == "player" then ("🎧 Requested by " .. tostring(p.requestedBy) .. (p.vip and " ★" or "")) else "🤖 Auto DJ"
            oneLine(label(row, tostring(p.artist) .. "  •  " .. tostring(p.genre) .. " playlist  •  " .. formatTime(p.duration or 0) .. "  •  " .. by,
                UDim2.new(1, -20, 0, 14), UDim2.fromOffset(12, 40), C.Muted, 10, false))
        end

        if #queue == 0 then addEmpty("The queue is empty — the Auto DJ will pick something good.") end
        for index, item in ipairs(queue) do
            local isPlayer = item.source == "player"
            local row = panel(content, 60, if isPlayer then C.Cyan else C.SurfaceLight)
            oneLine(label(row, string.format("%02d  %s", index, tostring(item.title)), UDim2.new(1, -60, 0, 18), UDim2.fromOffset(12, 6), C.White, 12, true))
            oneLine(label(row, tostring(item.artist) .. "  •  " .. tostring(item.genre) .. " playlist  •  " .. formatTime(item.duration or 0),
                UDim2.new(1, -60, 0, 14), UDim2.fromOffset(12, 25), C.Muted, 10, false))
            local by = if isPlayer then ("🎧 Requested by " .. tostring(item.requestedBy) .. (item.vip and "  ★ VIP" or "")) else "🤖 Queued by Auto DJ"
            oneLine(label(row, by, UDim2.new(1, -60, 0, 14), UDim2.fromOffset(12, 40), if isPlayer then C.Cyan else C.Muted, 10, true))
            local fav = isFavorite(item.trackId)
            local favBtn = button(row, if fav then "♥" else "♡", UDim2.fromOffset(34, 34), UDim2.new(1, -44, 0.5, -17), C.Surface, function()
                toggleFavorite(item.trackId)
            end)
            favBtn.TextSize = 16
            favBtn.TextColor3 = if fav then C.Magenta else C.Muted
        end
    end

    local function renderDJ()
        clear(content)
        addHeading("LIVE CONTROL ROOM", "DJ Booth", "Moderation for staff. Song selection is automated; VIPs get perks.")
        local s = latestState
        local rank = if s then s.rank or "GUEST" else "GUEST"
        local perm = if s then tonumber(s.perm) or 0 else 0
        local isDJ = perm >= 1
        local isAdmin = perm >= 2
        local vip = s and s.vip == true

        -- Access + VIP status
        local status = panel(content, 66, rankColor(rank))
        oneLine(label(status, "YOUR ACCESS: " .. rank .. (if vip then "   ★ VIP" else ""), UDim2.new(1, -20, 0, 22), UDim2.fromOffset(12, 6), rankColor(rank), 13, true))
        local req = s and s.requests or {used = 0, limit = 0}
        local perks = s and s.vipPerks or {}
        oneLine(label(status, string.format("Requests %d/%d   •   %s", req.used or 0, req.limit or 0,
            if vip then "VIP priority queue active" else ("VIP: " .. tostring(perks.slots or "?") .. " slots, " .. tostring(perks.cooldown or "?") .. "s cooldown, priority")),
            UDim2.new(1, -20, 0, 14), UDim2.fromOffset(12, 30), C.Muted, 10, false))
        if not vip then
            local gp = s and tonumber(s.vipGamePassId) or 0
            local getVip = button(status, "GET VIP", UDim2.fromOffset(80, 22), UDim2.new(1, -90, 0, 6), C.Magenta, function()
                promptPurchase("GamePass", gp)
            end)
            getVip.TextSize = 10
        end

        -- Now playing
        local p = s and s.nowPlaying or {}
        local current = panel(content, 62, C.Cyan)
        oneLine(label(current, "♫  " .. tostring(p.title or "Waiting for track"), UDim2.new(1, -24, 0, 20), UDim2.fromOffset(12, 6), C.White, 13, true))
        local by = if p.source == "player" then ("Requested by " .. tostring(p.requestedBy or "a guest") .. (p.vip and " ★" or "")) else "Auto DJ"
        oneLine(label(current, tostring(p.genre or "") .. " playlist  •  " .. by, UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 28), C.Muted, 10, false))
        local skip = s and s.skip or {votes = 0, needed = 1}
        oneLine(label(current, string.format("Skip votes: %d / %d needed", skip.votes or 0, skip.needed or 1), UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 43), C.Orange, 10, true))

        if isDJ then
            addSection("CONTROLS", C.Magenta)
            local controls = panel(content, 46, C.Magenta)
            local skipBtn = button(controls, "SKIP", UDim2.fromOffset(64, 30), UDim2.fromOffset(8, 8), C.Magenta, function() Network.DJSkip() end)
            local locked = s and s.locked == true
            local lockBtn = button(controls, if locked then "UNLOCK REQ" else "LOCK REQ", UDim2.fromOffset(96, 30), UDim2.fromOffset(78, 8), if locked then C.Orange else C.SurfaceLight, function()
                Network.DJToggleLock()
            end)
            skipBtn.TextSize = 11
            lockBtn.TextSize = 11
            if isAdmin then
                local clearBtn = button(controls, "CLEAR QUEUE", UDim2.fromOffset(96, 30), UDim2.fromOffset(180, 8), C.Red, function()
                    Network.DJClearQueue()
                end)
                clearBtn.TextSize = 11
            end
        end

        -- Queue moderation
        addSection("QUEUE", C.Cyan)
        local queue = s and s.queue or {}
        if #queue == 0 then addEmpty("The request queue is currently empty.") end
        for index, item in ipairs(queue) do
            local isPlayer = item.source == "player"
            local row = panel(content, 54, C.SurfaceLight)
            local textW = if isDJ then -(34 * 2 + 28) else -20
            oneLine(label(row, string.format("%02d  %s", index, tostring(item.title)), UDim2.new(1, textW, 0, 18), UDim2.fromOffset(12, 6), C.White, 12, true))
            oneLine(label(row, (if isPlayer then "🎧 " .. tostring(item.requestedBy) .. (item.vip and " ★" or "") else "🤖 Auto DJ") .. "  •  " .. tostring(item.genre or ""),
                UDim2.new(1, textW, 0, 14), UDim2.fromOffset(12, 28), if isPlayer then C.Cyan else C.Muted, 10, false))
            if isDJ then
                button(row, "↑", UDim2.fromOffset(34, 30), UDim2.new(1, -80, 0.5, -15), C.SurfaceLight, function()
                    Network.DJMoveUp(tostring(item.id))
                end)
                button(row, "✕", UDim2.fromOffset(34, 30), UDim2.new(1, -42, 0.5, -15), C.Red, function()
                    Network.DJRemove(tostring(item.id))
                end)
            end
        end

        -- Player moderation (staff only)
        if isDJ and s and s.players then
            addSection("PLAYERS", C.Orange)
            for _, target in ipairs(s.players) do
                local row = panel(content, 70, if target.blocked then C.Red else C.SurfaceLight)
                local flags = {}
                if target.rank and target.rank ~= "GUEST" then table.insert(flags, target.rank) end
                if target.vip then table.insert(flags, if target.tempVip then "VIP (staff)" else "VIP") end
                if target.blocked then table.insert(flags, "REQUESTS BLOCKED") end
                oneLine(label(row, target.displayName .. "  (@" .. target.name .. ")", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(12, 6), C.White, 12, true))
                oneLine(label(row, (if #flags > 0 then table.concat(flags, "  •  ") .. "  •  " else "") .. "Requests: " .. tostring(target.requests or 0),
                    UDim2.new(1, -20, 0, 14), UDim2.fromOffset(12, 24), C.Muted, 10, false))
                if isAdmin and target.canMod then
                    local vipBtn = button(row, if target.tempVip then "− VIP" else "+ VIP", UDim2.fromOffset(70, 26), UDim2.fromOffset(10, 40), C.Purple, function()
                        Network.ModSetVip(target.userId, not target.tempVip)
                    end)
                    vipBtn.TextSize = 11
                    local blockBtn = button(row, if target.blocked then "UNBLOCK" else "BLOCK", UDim2.fromOffset(78, 26), UDim2.fromOffset(86, 40), if target.blocked then C.Green else C.Red, function()
                        Network.ModBlockUser(target.userId, not target.blocked)
                    end)
                    blockBtn.TextSize = 11
                    local purge = button(row, "PURGE REQS", UDim2.fromOffset(92, 26), UDim2.fromOffset(170, 40), C.SurfaceLight, function()
                        Network.ModPurgeUser(target.userId)
                    end)
                    purge.TextSize = 11
                else
                    label(row, if target.canMod then "ADMIN rank needed for moderation" else "Protected / you", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(12, 42), C.Muted, 10, false)
                end
            end
        end
    end

    local function renderDonations()
        clear(content)
        addHeading("SUPPORT THE STAGE", "Tip Jar", "Choose a contribution tier.")
        for _, tier in ipairs(DONATIONS) do
            local row = panel(content, 58, C.Orange)
            oneLine(label(row, tier.label .. "  •  R$ " .. formatNumber(tier.amount), UDim2.new(1, -130, 0, 20), UDim2.fromOffset(12, 7), C.Gold, 13, true))
            oneLine(label(row, tier.perk, UDim2.new(1, -130, 0, 16), UDim2.fromOffset(12, 30), C.Muted, 10, false))
            button(row, "SUPPORT", UDim2.fromOffset(100, 30), UDim2.new(1, -108, 0.5, -15), C.Green, function()
                promptPurchase("Product", tier.productId)
            end)
        end
        local note = panel(content, 44, C.SurfaceLight)
        label(note, "Top donor leaderboard is supplied by the game data service; no client-side donor totals are trusted.", UDim2.new(1, -20, 1, -8), UDim2.fromOffset(10, 4), C.Muted, 10, false)
    end

    local function renderShop()
        clear(content)
        addHeading("STAGE ESSENTIALS", "Item Shop", "Cosmetics and access items.")
        for _, item in ipairs(SHOP) do
            local row = panel(content, 66, C.Purple)
            oneLine(label(row, item.name, UDim2.new(1, -130, 0, 20), UDim2.fromOffset(12, 6), C.White, 12, true))
            label(row, item.desc .. "  •  " .. item.rarity, UDim2.new(1, -130, 0, 30), UDim2.fromOffset(12, 28), C.Muted, 10, false)
            button(row, "R$ " .. formatNumber(item.price), UDim2.fromOffset(100, 32), UDim2.new(1, -108, 0.5, -16), C.Green, function()
                promptPurchase(item.kind, item.id)
            end)
        end
    end

    local function renderRewards()
        clear(content)
        addHeading("COME BACK DAILY", "Daily Rewards", "Claim the reward for your current login streak.")
        local s = latestState
        local streak = if s then tonumber(s.loginStreak) or 1 else 1
        local claimed = if s then s.claimedToday == true else false
        for _, reward in ipairs(REWARDS) do
            local isCurrent = reward.day == math.clamp(streak, 1, 7)
            local status = if reward.day < streak then "COMPLETE"
                elseif isCurrent and claimed then "CLAIMED"
                elseif isCurrent then "AVAILABLE"
                else "LOCKED"
            local row = panel(content, 50, if isCurrent then C.Gold else C.SurfaceLight)
            oneLine(label(row, "DAY " .. reward.day .. "  •  " .. reward.label, UDim2.new(1, -124, 1, 0), UDim2.fromOffset(12, 0), C.White, 12, true))
            button(row, if status == "AVAILABLE" then "CLAIM"
                elseif status == "COMPLETE" then "✓ DONE"
                elseif status == "CLAIMED" then "✓ CLAIMED"
                else "LOCKED",
                UDim2.fromOffset(100, 30), UDim2.new(1, -108, 0.5, -15),
                if status == "AVAILABLE" then C.Green else C.SurfaceLight,
                if status == "AVAILABLE" then function() Network.ClaimDailyReward(reward.day) end else nil)
        end
    end

    local function renderTags()
        clear(content)
        addHeading("PERSONALIZE YOUR NAMEPLATE", "Title Tags", "Equip a title you own.")
        local equipped = if latestState then latestState.equippedTag else nil
        for _, tag in ipairs(TAGS) do
            local owned = tag.owned or (latestState and latestState.ownedTags and latestState.ownedTags[tag.id] == true)
            local row = panel(content, 52, tag.a)
            local name = oneLine(label(row, "[" .. string.upper(tag.label) .. "]", UDim2.new(1, -130, 0, 20), UDim2.fromOffset(12, 5), tag.a, 13, true))
            gradient(name, tag.a, tag.b, 0)
            oneLine(label(row, tag.source, UDim2.new(1, -130, 0, 14), UDim2.fromOffset(12, 28), C.Muted, 10, false))
            if equipped == tag.id then
                button(row, "✓ EQUIPPED", UDim2.fromOffset(104, 30), UDim2.new(1, -112, 0.5, -15), C.Magenta)
            elseif owned then
                button(row, "EQUIP", UDim2.fromOffset(104, 30), UDim2.new(1, -112, 0.5, -15), C.SurfaceLight, function()
                    Network.EquipTitleTag(tag.id)
                end)
            else
                button(row, "LOCKED", UDim2.fromOffset(104, 30), UDim2.new(1, -112, 0.5, -15), C.SurfaceLight)
            end
        end
    end

    local function renderGroup()
        clear(content)
        addHeading("COMMUNITY", "Join the Crew", "Become part of the Sunset Stage Roblox Group.")
        local p = panel(content, 112, C.Magenta)
        gradient(p, Color3.fromRGB(190,24,93), C.Purple, 20)
        label(p, "🌴  OFFICIAL ROBLOX GROUP", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(14, 12), C.Gold, 11, true)
        oneLine(label(p, "Sunset Stage Collective", UDim2.new(1, -24, 0, 28), UDim2.fromOffset(14, 32), C.White, 21, true))
        label(p, "Dance faster, earn more, and get first dibs on DJ applications.", UDim2.new(1, -24, 0, 30), UDim2.fromOffset(14, 66), C.White, 11, false)
        local joined = false
        if groupId > 0 then
            local ok, result = pcall(function() return player:IsInGroup(groupId) end)
            joined = ok and result == true
        end
        local joinPanel = panel(content, 52, C.Orange)
        button(joinPanel, if joined then "✓  YOU'RE IN THE CREW" else "JOIN GROUP", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 9), if joined then C.Green else C.Magenta, function()
            if groupId <= 0 then
                warn("[ClubMusic] Set GroupId in the server configuration before enabling group join.")
                toast("Group isn't configured yet.", "warn")
                return
            end
            if not joined then
                pcall(function() GroupService:PromptJoinAsync(groupId) end)
                task.delay(2, function() if gui.Parent then renderGroup() end end)
            end
        end)
        local perks = panel(content, 70, C.Cyan)
        label(perks, "+10% Dance Speed   •   +10% Daily Rewards", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(12, 10), C.Cyan, 12, true)
        label(perks, "DJ applications   •   Event early access", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(12, 38), C.Muted, 11, false)
    end

    -- Decides when a tab has to be rebuilt because of a state update. Tabs that don't depend on
    -- live state (shop, tip jar...) never re-render, and the scroll position is preserved.
    local function tabSignature(tabId)
        local s = latestState
        if not s then return "offline" end
        local function favSig()
            local ids = {}
            for id in pairs(s.favorites or {}) do table.insert(ids, id) end
            table.sort(ids)
            return table.concat(ids, ",")
        end
        local function queueSig()
            local ids = {}
            for _, e in ipairs(s.queue or {}) do table.insert(ids, e.id) end
            return table.concat(ids, ",")
        end
        local playingId = tostring(s.nowPlaying and s.nowPlaying.trackId)
        if tabId == "music" or tabId == "all" or tabId == "fav" then
            local req = s.requests or {}
            return table.concat({favSig(), queueSig(), playingId, tostring(s.locked), tostring(s.blocked), tostring(req.used), tostring(req.limit)}, "|")
        elseif tabId == "queue" then
            return table.concat({favSig(), queueSig(), playingId}, "|")
        elseif tabId == "dj" then
            local roster = {}
            for _, p in ipairs(s.players or {}) do
                table.insert(roster, p.userId .. ":" .. tostring(p.vip) .. tostring(p.blocked) .. tostring(p.requests) .. tostring(p.canMod))
            end
            local skip = s.skip or {}
            local req = s.requests or {}
            return table.concat({queueSig(), playingId, tostring(s.locked), tostring(s.perm), tostring(s.vip), tostring(skip.votes), tostring(skip.needed),
                tostring(req.used), tostring(req.limit), table.concat(roster, ",")}, "|")
        elseif tabId == "rewards" or tabId == "tags" then
            return table.concat({tostring(s.loginStreak), tostring(s.claimedToday), tostring(s.equippedTag)}, "|")
        end
        return tabId
    end

    local function setToolbar(visible)
        toolbarVisible = visible
        toolbar.Visible = visible and expanded
        if relayout then relayout() end
    end

    renderTab = function(tabId, keepScroll)
        local previous = content.CanvasPosition
        currentTab = tabId
        for id, tabButton in pairs(sidebarButtons) do
            local active = id == tabId
            tabButton.BackgroundColor3 = if active then C.SurfaceLight else C.Surface
            tabButton.TextColor3 = if active then C.White else C.Muted
        end
        for id, tabButton in pairs(stripButtons) do
            local active = id == tabId
            tabButton.BackgroundColor3 = if active then C.SurfaceLight else C.Surface
            tabButton.TextColor3 = if active then C.White else C.Muted
        end
        setToolbar(tabId == "all")

        if tabId == "music" then renderMusic()
        elseif tabId == "all" then renderAll()
        elseif tabId == "queue" then renderQueue()
        elseif tabId == "fav" then renderFavorites()
        elseif tabId == "dj" then renderDJ()
        elseif tabId == "donate" then renderDonations()
        elseif tabId == "shop" then renderShop()
        elseif tabId == "rewards" then renderRewards()
        elseif tabId == "tags" then renderTags()
        elseif tabId == "group" then renderGroup()
        else renderMusic() end

        lastSig[tabId] = tabSignature(tabId)
        if keepScroll then
            task.defer(function()
                if content.Parent then content.CanvasPosition = previous end
            end)
        else
            content.CanvasPosition = Vector2.zero
        end
    end

    rerenderIfNeeded = function(force)
        if not expanded then return end
        local sig = tabSignature(currentTab)
        if force or sig ~= lastSig[currentTab] then
            renderTab(currentTab, true)
        end
    end

    for index, definition in ipairs(tabDefs) do
        local id, icon, name = definition[1], definition[2], definition[3]

        local sideButton = button(sidebar, icon .. "  " .. name, UDim2.new(1, 0, 0, 34), UDim2.new(), C.Surface, function()
            renderTab(id)
        end)
        sideButton.LayoutOrder = index
        sideButton.TextXAlignment = Enum.TextXAlignment.Left
        sideButton.TextSize = 12
        sideButton.TextColor3 = C.Muted
        local sidePad = Instance.new("UIPadding")
        sidePad.PaddingLeft = UDim.new(0, 10)
        sidePad.Parent = sideButton
        sidebarButtons[id] = sideButton

        local stripButton = button(tabStrip, icon .. " " .. name, UDim2.fromOffset(0, 30), UDim2.new(), C.Surface, function()
            renderTab(id)
        end)
        stripButton.LayoutOrder = index
        stripButton.AutomaticSize = Enum.AutomaticSize.X
        stripButton.TextSize = 12
        stripButton.TextColor3 = C.Muted
        local stripPad = Instance.new("UIPadding")
        stripPad.PaddingLeft = UDim.new(0, 12)
        stripPad.PaddingRight = UDim.new(0, 12)
        stripPad.Parent = stripButton
        stripButtons[id] = stripButton
    end

    -- Toolbar wiring
    local searchToken = 0
    track(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        searchToken += 1
        local mine = searchToken
        task.delay(0.25, function()
            if mine ~= searchToken then return end
            searchText = searchBox.Text
            if expanded and currentTab == "all" then renderTab("all", false) end
        end)
    end))
    genreButton.Activated:Connect(function()
        genreFilter = (genreFilter + 1) % (#GENRES + 1)
        genreButton.Text = if genreFilter == 0 then "All genres" else GENRES[genreFilter].name
        genreButton.TextColor3 = if genreFilter == 0 then C.White else GENRES[genreFilter].color
        if expanded and currentTab == "all" then renderTab("all", false) end
    end)

    ---------------------------------------------------------------------------------------------
    -- Responsive layout (phones, tablets, PC, console, VR)
    ---------------------------------------------------------------------------------------------
    local function deviceScale()
        if VRService.VREnabled then return 1.3 end
        if GuiService:IsTenFootInterface() then return 1.25 end
        return 1
    end

    local function modalTargetSize()
        local s = deviceScale()
        local area = gui.AbsoluteSize
        local availW = area.X / s - 16
        local availH = area.Y / s - 16
        return math.floor(math.min(availW, 720)), math.floor(math.min(availH, 440))
    end

    relayout = function()
        local s = deviceScale()
        modalScale.Scale = s
        hudScale.Scale = s
        toastScale.Scale = s

        local area = gui.AbsoluteSize
        if area.X <= 0 or area.Y <= 0 then return end -- not laid out yet; AbsoluteSize signal will re-run this
        hudRoot.Size = UDim2.fromOffset(math.clamp(area.X / s - 16, 220, 360), 80)

        local w, h = modalTargetSize()
        modalWidth, modalHeight = w, h
        compact = w < 560

        if expanded and not animating then
            modal.Size = UDim2.fromOffset(w, h)
        end

        closeButton.Position = UDim2.fromOffset(w - 40, 5)

        local top = 48
        local bottom = h - DOCK_H - 14
        local contentLeft, contentTop, contentWidth
        if compact then
            sidebar.Visible = false
            tabStrip.Visible = true
            tabStrip.Position = UDim2.fromOffset(10, top - 2)
            tabStrip.Size = UDim2.fromOffset(w - 20, 36)
            contentLeft, contentTop, contentWidth = 10, top + 40, w - 20
        else
            tabStrip.Visible = false
            sidebar.Visible = true
            sidebar.Position = UDim2.fromOffset(10, top)
            sidebar.Size = UDim2.fromOffset(128, bottom - top)
            contentLeft, contentTop, contentWidth = 146, top, w - 156
        end

        toolbar.Position = UDim2.fromOffset(contentLeft, contentTop)
        toolbar.Size = UDim2.fromOffset(contentWidth, 30)
        toolbar.Visible = toolbarVisible and expanded
        local offset = if toolbarVisible then 36 else 0
        content.Position = UDim2.fromOffset(contentLeft, contentTop + offset)
        content.Size = UDim2.fromOffset(contentWidth, math.max(40, bottom - contentTop - offset))

        dock.Position = UDim2.fromOffset(10, h - DOCK_H - 8)
        dock.Size = UDim2.fromOffset(w - 20, DOCK_H)

        -- Dock internals scale with the available width
        local dockWidth = w - 20
        local showViz = dockWidth >= 330
        dockViz.Visible = showViz
        local vizWidth = if showViz then math.clamp(math.floor(dockWidth * 0.17), 54, 110) else 0
        dockViz.Size = UDim2.new(0, vizWidth, 1, -18)
        dockLeft.Size = UDim2.new(1, -(vizWidth + (if showViz then 14 else 4)), 1, 0)
        local leftWidth = dockWidth - (vizWidth + (if showViz then 14 else 4))
        local showStepButtons = leftWidth >= 330
        volMinus.Visible = showStepButtons
        volPlus.Visible = showStepButtons
        sliderHit.Size = UDim2.new(1, -(178 + 10 + (if showStepButtons then 60 else 0)), 0, 26)
    end

    track(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout))
    relayout()

    ---------------------------------------------------------------------------------------------
    -- Open / close
    ---------------------------------------------------------------------------------------------
    local function focusFirstControl()
        if UserInputService.GamepadEnabled and not UserInputService.TouchEnabled or GuiService:IsTenFootInterface() then
            local first = if compact then stripButtons[currentTab] else sidebarButtons[currentTab]
            if first then GuiService.SelectedObject = first end
        end
    end

    local function open()
        if expanded or animating then return end
        expanded, animating = true, true
        relayout()
        modal.Visible = true
        backdrop.Visible = true
        hudRoot.Visible = false
        renderTab(currentTab)
        TweenService:Create(backdrop, TweenInfo.new(0.25), {BackgroundTransparency = 0.42}):Play()
        if blur then TweenService:Create(blur, TweenInfo.new(0.25), {Size = 16}):Play() end
        modal.Size = UDim2.fromOffset(math.min(340, modalWidth), 46)
        local tween = TweenService:Create(modal, TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(modalWidth, modalHeight)})
        tween.Completed:Once(function()
            animating = false
            relayout()
            focusFirstControl()
        end)
        tween:Play()
    end

    local function close()
        if not expanded or animating then return end
        animating = true
        GuiService.SelectedObject = nil
        TweenService:Create(backdrop, TweenInfo.new(0.22), {BackgroundTransparency = 1}):Play()
        if blur then TweenService:Create(blur, TweenInfo.new(0.22), {Size = 0}):Play() end
        local tween = TweenService:Create(modal, TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {Size = UDim2.fromOffset(math.min(340, modalWidth), 46)})
        tween.Completed:Once(function()
            modal.Visible = false
            backdrop.Visible = false
            toolbar.Visible = false
            hudRoot.Visible = true
            expanded, animating = false, false
        end)
        tween:Play()
    end

    local function cycleTab(direction)
        local index = 1
        for i, def in ipairs(tabDefs) do
            if def[1] == currentTab then index = i break end
        end
        index = ((index - 1 + direction) % #tabDefs) + 1
        renderTab(tabDefs[index][1])
    end

    expand.Activated:Connect(open)
    closeButton.Activated:Connect(close)
    backdrop.Activated:Connect(close)
    shopButton.Activated:Connect(function() currentTab = "shop"; open() end)
    mini.Activated:Connect(function() currentTab = "queue"; open() end)
    track(UserInputService.InputBegan:Connect(function(input, processed)
        if input.KeyCode == Enum.KeyCode.ButtonB and expanded then
            close()
            return
        end
        if processed then return end
        if input.KeyCode == Enum.KeyCode.M then
            if expanded then close() else open() end
        elseif expanded and input.KeyCode == Enum.KeyCode.ButtonR1 then
            cycleTab(1)
        elseif expanded and input.KeyCode == Enum.KeyCode.ButtonL1 then
            cycleTab(-1)
        end
    end))

    ---------------------------------------------------------------------------------------------
    -- State + frame updates
    ---------------------------------------------------------------------------------------------
    local function applyState(state)
        latestState = state
        receivedAt = os.clock()
        local rank = tostring(state.rank or "GUEST")
        local equipped = state.equippedTag
        local tagData = nil
        for _, tag in ipairs(TAGS) do
            if tag.id == equipped then tagData = tag break end
        end
        local vipMark = if state.vip then " ★" else ""
        if tagData then
            rankLabel.Text = "★ [" .. string.upper(tagData.label) .. "]"
            rankLabel.TextColor3 = tagData.a
        else
            rankLabel.Text = "★ " .. rank .. vipMark
            rankLabel.TextColor3 = rankColor(rank)
        end
        ticketButton.Text = "🎟 " .. formatNumber(tonumber(state.tickets) or 0)
        updateDockStatics()
        syncSound(false)
        rerenderIfNeeded(false)
    end

    track(Network.OnStateChanged(applyState))
    if Network.OnNotice then
        track(Network.OnNotice(function(notice)
            toast(notice.text, notice.kind)
        end))
    end
    if latestState then applyState(latestState) end

    local barAccumulator = 0
    local textAccumulator = 0
    track(RunService.Heartbeat:Connect(function(dt)
        local p = latestState and latestState.nowPlaying
        barAccumulator += dt
        textAccumulator += dt

        -- Text + progress (4 times a second is plenty)
        if textAccumulator >= 0.25 then
            textAccumulator = 0
            local elapsed = estimatedElapsed()
            local duration = if p then (tonumber(p.duration) or 0) else 0
            local timeText = formatTime(elapsed) .. " / " .. formatTime(duration)
            miniTime.Text = timeText
            if expanded then
                dockTime.Text = timeText
                progressFill.Size = UDim2.new(if duration > 0 then math.clamp(elapsed / duration, 0, 1) else 0, 0, 1, 0)
            end
        end

        -- Visualizer (~30 fps, only while something is visible)
        if barAccumulator >= 1 / 30 then
            barAccumulator = 0
            if not (hudRoot.Visible or expanded) then return end
            local t = os.clock()
            local level = 0.08
            local bps = 2
            if p then
                local finished = estimatedElapsed() >= (tonumber(p.duration) or 0)
                if localSound and localSound.IsPlaying then
                    level = math.clamp(localSound.PlaybackLoudness / 450, 0.06, 1)
                elseif not finished then
                    level = 1
                end
                -- Slightly different tempo per track so each song feels distinct
                bps = 1.6 + ((#tostring(p.trackId) * 7 + (tonumber(p.duration) or 0)) % 9) / 10
            end
            if hudRoot.Visible then updateBars(miniBars, t, level, bps) end
            if expanded then updateBars(dockBars, t, level, bps) end
        end
    end))

    local destroyed = false
    gui.Destroying:Connect(function()
        if destroyed then return end
        destroyed = true
        for _, conn in ipairs(connections) do conn:Disconnect() end
        stopSound()
        if blur and blur.Parent then blur.Size = 0 end
    end)

    return {
        Gui = gui,
        Open = open,
        Close = close,
        Destroy = function()
            if gui.Parent then gui:Destroy() end
        end,
    }
end

return Renderer
