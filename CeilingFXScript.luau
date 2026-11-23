local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))
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

-- CeilingPillarFX owns pillar color and movement locally; avoid competing server writes.

local CENTER_X, CENTER_Z = maxGX / 2, maxGZ / 2
local PATTERN_TIME = 10 -- seconds per effect
local MAX_BRIGHTNESS = 0.72 -- cap on glow intensity (turned down a bit)

local function setPanel(p, hue, value)
	-- Scale the effect's brightness into the dimmer range
	local v = 0.04 + (math.clamp(value, 0, 1) - 0.04) * MAX_BRIGHTNESS
	p.Color = Color3.fromHSV(hue % 1, 1, v)
end

-- Effect 1: independent randomized pulses; no center-out ripple.
local function ripple(t)
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX") or 0, p:GetAttribute("GZ") or 0
		local seed = (gx * 71 + gz * 113) % 997
		local phase = seed * 0.071
		local speed = 0.55 + (seed % 13) * 0.09
		local pulse = 0.5 + 0.5 * math.sin(t * speed + phase)
		local glow = 0.06 + 0.94 * pulse ^ 3
		setPanel(p, (seed * 0.013 + t * 0.045) % 1, glow)
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

-- Effect 10: independently phased randomized shimmer, not a center vortex.
local function spiral(t)
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX") or 0, p:GetAttribute("GZ") or 0
		local seed = (gx * 193 + gz * 227) % 991
		local phase = seed * 0.037
		local speed = 0.65 + (seed % 17) * 0.08
		local arm = math.cos(t * speed + phase)
		local glow = 0.04 + 0.96 * math.max(0, arm) ^ 2
		setPanel(p, (seed * 0.019 + t * 0.08) % 1, glow)
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

-- Effect 13: independent randomized spark bursts across the panel grid.
local function comet(t)
	for _, p in panels do
		local gx, gz = p:GetAttribute("GX") or 0, p:GetAttribute("GZ") or 0
		local seed = (gx * 137 + gz * 149) % 983
		local phase = seed * 0.053
		local speed = 0.8 + (seed % 11) * 0.13
		local spark = math.max(0, math.cos(t * speed + phase)) ^ 8
		local glow = 0.04 + spark * 0.96
		setPanel(p, (seed * 0.011 + t * 0.06) % 1, glow)
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


-- 12 Hz is sufficient for replicated ambient panel color animation and reduces server property churn.
while task.wait(1 / 12) do
	local beat = ClubAudioSync.getBeatState()
	local t = os.clock() * (beat.bpm / 128)
	local index = (math.floor(t / PATTERN_TIME) % #effects) + 1
	-- The floor runs the current effect while the ceiling runs the next
	-- one, so both surfaces dance with complementary shows at once.
	-- pcall keeps one bad effect from freezing the whole show.
	panels = floorPanels
	pcall(effects[index], t)
	panels = ceilPanels
	pcall(effects[(index % #effects) + 1], t)
end