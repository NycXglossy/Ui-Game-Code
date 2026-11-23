--!strict
-- PixelMatrixFX: client-local choreography for the existing FloorPanel/CeilingPanel grids.
-- Server-created panel geometry remains authoritative; only each client's visual colors animate.
-- Uses ClubAudioSync's shared beat count/phase so every client sees the same 16-beat phrases.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClubAudioSync = require(ReplicatedStorage:WaitForChild("ClubAudioSync"))

local ROOT_NAME = "CeilingFX"
local FLOOR_BRIGHTNESS = 0.34
local CEILING_BRIGHTNESS = 0.30
local UPDATE_RATE = 1 / 15
local root = workspace:WaitForChild(ROOT_NAME)

type Panel = {part: BasePart, x: number, z: number, seed: number}
local floorPanels: {Panel} = {}
local ceilingPanels: {Panel} = {}
local maxX, maxZ = 0, 0
local refreshAge = 0

local function collect()
	table.clear(floorPanels)
	table.clear(ceilingPanels)
	maxX, maxZ = 0, 0
	for _, item in ipairs(root:GetChildren()) do
		if item:IsA("BasePart") and (item.Name == "FloorPanel" or item.Name == "CeilingPanel") then
			local x = item:GetAttribute("GX")
			local z = item:GetAttribute("GZ")
			if typeof(x) == "number" and typeof(z) == "number" then
				local entry: Panel = {part = item, x = x, z = z, seed = (x * 73 + z * 137) % 997}
				table.insert(if item.Name == "FloorPanel" then floorPanels else ceilingPanels, entry)
				maxX = math.max(maxX, x)
				maxZ = math.max(maxZ, z)
			end
		end
	end
end
collect()
root.ChildAdded:Connect(function() task.defer(collect) end)
root.ChildRemoved:Connect(function() task.defer(collect) end)

local function paint(panel: Panel, hue: number, level: number, ceiling: boolean)
	if not panel.part.Parent then return end
	local cap = if ceiling then CEILING_BRIGHTNESS else FLOOR_BRIGHTNESS
	local value = 0.035 + math.clamp(level, 0, 1) * cap
	panel.part.Color = Color3.fromHSV(hue % 1, 0.88, value)
end

local function floorPattern(panel: Panel, phrase: number, phase: number, pulse: number)
	local cx, cz = maxX * 0.5, maxZ * 0.5
	local dx, dz = panel.x - cx, panel.z - cz
	local distance = math.sqrt(dx * dx + dz * dz)
	local angle = math.atan2(dz, dx)
	local pattern = phrase % 6
	local hue = (0.52 + phrase * 0.035 + panel.seed * 0.0007) % 1
	local level = 0.08
	if pattern == 0 then -- diagonal traveling wave
		level = 0.12 + 0.88 * math.max(0, math.cos((panel.x + panel.z) * 0.62 - phase * math.pi * 2)) ^ 3
	elseif pattern == 1 then -- concentric rings
		level = 0.08 + 0.92 * math.max(0, math.cos(distance * 0.9 - phase * math.pi * 4)) ^ 4
	elseif pattern == 2 then -- spiral arms
		level = 0.06 + 0.94 * math.max(0, math.cos(angle * 2 + distance * 0.55 - phase * math.pi * 4)) ^ 3
	elseif pattern == 3 then -- checkerboard beat alternation
		local on = ((math.floor(panel.x) + math.floor(panel.z) + math.floor(phase * 4)) % 2) == 0
		level = if on then 0.9 else 0.08
	elseif pattern == 4 then -- four-corner chase
		local wave = math.cos((math.abs(dx) + math.abs(dz)) * 0.55 - phase * math.pi * 4)
		level = 0.08 + 0.92 * math.max(0, wave) ^ 3
	else -- soft kick pulse with seeded tile variation
		level = 0.07 + pulse * (0.45 + (panel.seed % 31) / 40)
	end
	paint(panel, hue + phase * 0.08, level, false)
end

local function ceilingPattern(panel: Panel, phrase: number, phase: number, pulse: number)
	local cx, cz = maxX * 0.5, maxZ * 0.5
	local dx, dz = panel.x - cx, panel.z - cz
	local angle = math.atan2(dz, dx)
	local distance = math.sqrt(dx * dx + dz * dz)
	local pattern = phrase % 5
	local hue = (0.53 + phrase * 0.045 + (panel.x / math.max(1, maxX)) * 0.12) % 1
	local level
	if pattern == 0 then -- overhead traveling wave
		level = 0.08 + 0.92 * math.max(0, math.cos(panel.x * 0.52 - phase * math.pi * 2)) ^ 3
	elseif pattern == 1 then -- rotating radial spokes
		level = 0.06 + 0.94 * math.max(0, math.cos(angle * 4 - phase * math.pi * 2 + distance * 0.12)) ^ 4
	elseif pattern == 2 then -- broad overhead rings
		level = 0.08 + 0.92 * math.max(0, math.cos(distance * 0.7 - phase * math.pi * 3)) ^ 3
	elseif pattern == 3 then -- counter-moving rows
		local direction = (math.floor(panel.z) % 2 == 0) and 1 or -1
		level = 0.08 + 0.92 * math.max(0, math.cos(panel.x * 0.45 * direction + phase * math.pi * 2)) ^ 3
	else -- subtle ceiling-wide phrase pulse
		level = 0.08 + pulse * 0.58
	end
	paint(panel, hue + phase * 0.045, level, true)
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	refreshAge += dt
	if refreshAge >= 4 then
		refreshAge = 0
		if #floorPanels == 0 or #ceilingPanels == 0 then collect() end
	end
	if accumulator < UPDATE_RATE then return end
	accumulator %= UPDATE_RATE
	local beat = ClubAudioSync.getBeatState()
	local phrase = math.floor(beat.beatCount / 16)
	local phase = (beat.beatCount % 16 + beat.beatPhase) / 16
	local kick = math.exp(-beat.beatPhase * 5) * (0.25 + beat.energy * 0.75)
	for _, panel in ipairs(floorPanels) do floorPattern(panel, phrase, phase, kick) end
	for _, panel in ipairs(ceilingPanels) do ceilingPattern(panel, phrase, phase, kick) end
end)

print("[ClubNeon][PixelMatrixFX] Client-local floor and ceiling matrix choreography ready; floor="
	.. #floorPanels .. " ceiling=" .. #ceilingPanels)
