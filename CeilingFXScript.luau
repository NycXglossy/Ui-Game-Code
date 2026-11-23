-- Ceiling light show: cycles through multiple effects on the CeilingPanel grid
local folder = workspace:FindFirstChild("CeilingFX")
while not folder do
	task.wait(0.5)
	folder = workspace:FindFirstChild("CeilingFX")
end

local panels = {} -- active set; swapped between floor/ceiling so each surface runs its own show
local floorPanels = {}
local ceilPanels = {}
local maxGX, maxGZ = 0, 0
if folder then
	for _, p in folder:GetChildren() do
		if p.Name == "CeilingPanel" or p.Name == "FloorPanel" then
			if p.Name == "CeilingPanel" then
				table.insert(ceilPanels, p)
			else
				table.insert(floorPanels, p)
			end
			maxGX = math.max(maxGX, p:GetAttribute("GX") or 0)
			maxGZ = math.max(maxGZ, p:GetAttribute("GZ") or 0)
		end
	end
end
if #floorPanels + #ceilPanels == 0 then
	-- Retry instead of giving up: panels may not exist yet at server start
	while #floorPanels + #ceilPanels == 0 do
		task.wait(1)
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") and (p.Name == "CeilingPanel" or p.Name == "FloorPanel") then
				if p.Name == "CeilingPanel" then
					table.insert(ceilPanels, p)
				else
					table.insert(floorPanels, p)
				end
				maxGX = math.max(maxGX, p:GetAttribute("GX") or 0)
				maxGZ = math.max(maxGZ, p:GetAttribute("GZ") or 0)
			end
		end
	end
end

-- Ceiling pillars: collect their neon parts so the show can drive them too
local pillarNeons = {}
local pillarsModel = workspace:FindFirstChild("CeilingPillars")
while not pillarsModel do
	task.wait(1)
	pillarsModel = workspace:FindFirstChild("CeilingPillars")
end
for _, part in pillarsModel:GetDescendants() do
	if part:IsA("BasePart") and part.Material == Enum.Material.Neon then
		table.insert(pillarNeons, part)
	end
end

local CENTER_X, CENTER_Z = maxGX / 2, maxGZ / 2
local PATTERN_TIME = 10 -- seconds per effect
local MAX_BRIGHTNESS = 0.72 -- cap on glow intensity (turned down a bit)

local function setPanel(p, hue, value)
	-- Scale the effect's brightness into the dimmer range
	local v = 0.04 + (math.clamp(value, 0, 1) - 0.04) * MAX_BRIGHTNESS
	p.Color = Color3.fromHSV(hue % 1, 1, v)
end

-- Effect 1: expanding ripple rings from the center
local function ripple(t)
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX"), p:GetAttribute("GZ")
		local dist = math.sqrt((gx - CENTER_X) ^ 2 + (gz - CENTER_Z) ^ 2)
		local ring = (t * 6 - dist * 0.45) % 6
		local glow = math.max(0, 1 - math.abs(ring - 1) * 1.4)
		setPanel(p, (dist * 0.04 + t * 0.05) % 1, 0.06 + 0.94 * glow)
	end
end

-- Effect 2: diagonal color sweep chasing across the grid
local function sweep(t)
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX"), p:GetAttribute("GZ")
		local phase = (gx + gz) / (maxGX + maxGZ)
		local wave = (t * 0.8 - phase * 3) % 3
		local glow = math.max(0.05, 1 - wave * 1.2)
		setPanel(p, (phase + t * 0.1) % 1, glow)
	end
end

-- Effect 3: random panels twinkle like stars
local function twinkle(t)
	for _, p in panels do
		local seed = (p:GetAttribute("GX") * 31 + p:GetAttribute("GZ") * 17) % 97
		local phase = math.sin(t * (1 + seed % 5 * 0.4) + seed)
		local glow = 0.04 + 0.96 * math.max(0, phase)
		setPanel(p, (seed * 0.37 + t * 0.03) % 1, glow)
	end
end

-- Effect 4: rainbow rows scrolling in opposite directions
local function rainbowRows(t)
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX"), p:GetAttribute("GZ")
		local dir = (gz % 2 == 0) and 1 or -1
		setPanel(p, ((gx * 0.06 * dir) + t * 0.12) % 1, 0.85)
	end
end

-- Effect 5: hard rave strobe - rapid alternating flashes that shift color each beat
local function strobe(t)
	local beat = math.floor(t * 4)
	local on = beat % 2 == 0
	local hue = (beat * 0.13) % 1
	for _, p in panels do
		setPanel(p, hue, on and 1 or 0.02)
	end
end

-- Effect 6: breathing fade - slow smooth hue drift with a pulsing glow
local function fade(t)
	local breath = 0.5 + 0.5 * math.sin(t * 1.2)
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX"), p:GetAttribute("GZ")
		setPanel(p, (t * 0.06 + (gx + gz) * 0.012) % 1, 0.08 + 0.92 * breath)
	end
end

-- Effect 7: lightning - random panels burst bright then decay fast
local function lightning(t)
	local seed = math.floor(t * 6)
	local decay = (t * 6) % 1
	for _, p in panels do
		local s = (p:GetAttribute("GX") * 7 + p:GetAttribute("GZ") * 13 + seed * 31) % 100
		local glow = 0.03
		if s < 18 then
			glow = math.max(0.03, 1 - decay * 1.6)
		end
		setPanel(p, (s * 0.01 + t * 0.1) % 1, glow)
	end
end

-- Effect 8: checkerboard flash - alternating halves of the grid strobe against each other
local function checker(t)
	local beat = math.floor(t * 4)
	local flip = beat % 2 == 0
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX"), p:GetAttribute("GZ")
		local on = ((gx + gz) % 2 == 0) == flip
		setPanel(p, (beat * 0.09) % 1, on and 1 or 0.03)
	end
end

-- Effect 9: heartbeat pulse - double-thump kick like a bass drop
local function pulse(t)
	local beat = t % 1
	local kick = math.exp(-beat * 6) + 0.6 * math.exp(-((beat - 0.3) % 1) * 8)
	for _, p in panels do
		local gx = p:GetAttribute("GX")
		setPanel(p, (t * 0.15 + gx * 0.02) % 1, 0.05 + 0.95 * math.min(1, kick))
	end
end

-- Effect 10: spiral vortex -- rotating arms of light spinning out from the center
local function spiral(t)
	local spin = t * 2.5
	local maxDist = math.max(maxGX, maxGZ) * 0.75
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX"), p:GetAttribute("GZ")
		local dx, dz = gx - CENTER_X, gz - CENTER_Z
		local dist = math.sqrt(dx * dx + dz * dz)
		local angle = math.atan(dz, dx)
		-- Offset the angle by distance to create the swirl shape
		local arm = math.cos(angle * 2 - dist * 0.9 - spin)
		local glow = math.max(0, arm) * math.max(0, 1 - dist / maxDist)
		setPanel(p, (angle / (math.pi * 2) + t * 0.1) % 1, 0.04 + 0.96 * glow)
	end
end

-- Effect 11: fireworks -- bursts explode at random spots and ripple outward
local function fireworks(t)
	local seed = math.floor(t * 1.5)
	local rand = Random.new(seed)
	local decay = (t * 1.5) % 1
	local bursts = {}
	for i = 1, 3 do
		bursts[i] = {x = rand:NextInteger(0, maxGX), z = rand:NextInteger(0, maxGZ), hue = rand:NextNumber()}
	end
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX"), p:GetAttribute("GZ")
		local glow, hue = 0.03, 0
		for _, b in ipairs(bursts) do
			local d = math.sqrt((gx - b.x) ^ 2 + (gz - b.z) ^ 2)
			local shell = math.abs(d - decay * maxGX * 0.6)
			local g = math.max(0, 1 - shell * 1.3) * (1 - decay)
			if g > glow then
				glow = g
				hue = (b.hue + decay * 0.2) % 1
			end
		end
		setPanel(p, hue, glow)
	end
end

-- Effect 12: plasma interference -- colliding waves melting into pools of color
local function plasma(t)
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX"), p:GetAttribute("GZ")
		local w1 = math.sin(gx * 0.7 + t * 2.2)
		local w2 = math.sin(gz * 0.6 - t * 1.7)
		local w3 = math.sin((gx + gz) * 0.4 + t * 1.1)
		local v = (w1 + w2 + w3) / 3
		setPanel(p, (v * 0.5 + 0.5 + t * 0.05) % 1, 0.05 + 0.95 * math.max(0, v))
	end
end

-- Effect 13: comet -- a bright orb orbiting the grid with a glowing trail
local function comet(t)
	local orbit = t * 3
	local cx = CENTER_X + math.cos(orbit) * CENTER_X * 0.8
	local cz = CENTER_Z + math.sin(orbit) * CENTER_Z * 0.8
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX"), p:GetAttribute("GZ")
		local d = math.sqrt((gx - cx) ^ 2 + (gz - cz) ^ 2)
		local glow = math.exp(-d * 0.55) + math.exp(-d * 0.18) * 0.35
		setPanel(p, (t * 0.25 - d * 0.04) % 1, math.min(1, glow))
	end
end

-- Effect 14: matrix rain -- columns of light cascading down the grid
local function matrixRain(t)
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX"), p:GetAttribute("GZ")
		local speed = 3 + (gx % 4) * 1.5
		local head = (t * speed + gx * 2.7) % (maxGZ + 4)
		local trail = head - gz
		local glow = 0.03
		if trail >= 0 and trail < 4 then
			glow = 1 - trail / 4
		end
		setPanel(p, 0.33, glow) -- classic green rain
	end
end

local effects = {ripple, sweep, twinkle, rainbowRows, strobe, fade, lightning, checker, pulse, spiral, fireworks, plasma, comet, matrixRain}

-- Pillar show: hue drifts with the pattern clock and the glow gently
-- breathes, staying in sync with whichever effect is running.
local function runPillars(t, index)
	local hue = (t * 0.05 + index * 0.09) % 1
	local breath = 0.55 + 0.2 * math.sin(t * 1.1) -- soft pulse, dimmer range
	local v = 0.04 + breath * MAX_BRIGHTNESS
	for _, part in pillarNeons do
		if part.Parent then
			part.Color = Color3.fromHSV((hue + part.Position.X * 0.001) % 1, 0.85, v)
		end
	end
end

-- 12 Hz is sufficient for replicated ambient panel color animation and reduces server property churn.
while task.wait(1 / 12) do
	local t = os.clock()
	local index = (math.floor(t / PATTERN_TIME) % #effects) + 1
	-- The floor runs the current effect while the ceiling runs the next
	-- one, so both surfaces dance with complementary shows at once.
	-- pcall keeps one bad effect from freezing the whole show.
	panels = floorPanels
	pcall(effects[index], t)
	panels = ceilPanels
	pcall(effects[(index % #effects) + 1], t)
	runPillars(t, index)
end