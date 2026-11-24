--!strict
-- DJStageLEDBarFX: client-local LED pixel choreography.
-- Uses the same ClubAudioSync beat clock as LaserShowFX and MovingHeadShowFX.
-- This controller owns only the DJ backdrop LED bars; it does not alter either
-- existing fixture controller or create another analyzer/audio route.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClubAudioSync = require(ReplicatedStorage:WaitForChild("ClubAudioSync"))

local RIG_NAME = "DJStageLEDBarRig"
local rig = workspace:WaitForChild(RIG_NAME, 60)
if not rig or rig:GetAttribute("Ready") ~= true then
	warn("[ClubNeon][DJStageLEDBarFX] Rig unavailable or not ready; LED bar animation not started.")
	return
end

type Segment = {
	part: BasePart,
	orientation: string,
	row: number,
	index: number,
}

local segments: {Segment} = {}
local function collectSegments()
	table.clear(segments)
	for _, item in ipairs(rig:GetChildren()) do
		if item:IsA("BasePart") then
			table.insert(segments, {
				part = item,
				orientation = tostring(item:GetAttribute("BarOrientation") or "Horizontal"),
				row = tonumber(item:GetAttribute("BarRow")) or 1,
				index = tonumber(item:GetAttribute("BarIndex")) or 1,
			})
		end
	end
end
collectSegments()

local lastBeatCount = -1
local dropUntil = 0
local horizontalCount = tonumber(rig:GetAttribute("HorizontalSegmentsPerBar")) or 24
local verticalCount = tonumber(rig:GetAttribute("VerticalSegmentsPerBar")) or 16
local showClock = 0
local lastAudit = 0
local function wrap(value: number, size: number): number
	return ((value - 1) % size) + 1
end

RunService.RenderStepped:Connect(function(dt)
	if not rig.Parent then return end
	showClock += math.min(dt, 0.05)
	if #segments == 0 or (os.clock() - lastAudit > 2) then
		lastAudit = os.clock()
		collectSegments()
	end

	local beat = ClubAudioSync.getBeatState()
	local beatPosition = beat.beatCount + beat.beatPhase
	local speed = math.clamp(beat.movementSpeed or 1, 0.55, 1.45)
	local hueBase = (showClock * 0.035 + beatPosition * 0.012) % 1

	-- Strong onset near a beat starts a short coordinated drop sweep.
	if beat.beatCount ~= lastBeatCount then
		lastBeatCount = beat.beatCount
		if (beat.onsetStrength or 0) >= 0.78 and beat.beatPhase <= 0.20 then
			dropUntil = os.clock() + 0.62
		end
	end
	local dropActive = os.clock() < dropUntil
	local beatPulse = math.exp(-beat.beatPhase * 5)
	-- beatPosition already advances at the live detected BPM. Multiplying by
	-- BPM again would square tempo changes and make the bars drift away from
	-- the shared beat clock. movementSpeed is the shared adaptive choreography
	-- rate, so it is the only additional rate multiplier.
	local cycle = (beatPosition * speed) % 32

	for _, segment in ipairs(segments) do
		local index = segment.index
		local row = segment.row
		local active = false
		local intensity = 0.12
		local hue = (hueBase + row * 0.075 + index * 0.006) % 1

		if dropActive then
			-- Cascading drop: horizontal rows sweep down in sequence while the
			-- vertical frame rises from the bottom, all on the same beat clock.
			local progress = 1 - math.clamp((dropUntil - os.clock()) / 0.62, 0, 1)
			if segment.orientation == "Horizontal" then
				local front = progress * horizontalCount + (row - 1) * (horizontalCount * 0.10)
				active = math.abs(index - front) <= math.max(2, horizontalCount * 0.055)
			else
				local front = 1 + progress * verticalCount
				active = math.abs(index - front) <= math.max(2, verticalCount * 0.10)
			end
			intensity = if active then 1 else 0.18
		elseif segment.orientation == "Horizontal" then
			-- Expanding fan from the center of the DJ backdrop.
			local center = (horizontalCount + 1) * 0.5
			local distance = math.abs(index - center)
			local fanRadius = (cycle * 0.52 + (row - 1) * (horizontalCount * 0.075)) % (horizontalCount * 0.5 + 1)
			active = math.abs(distance - fanRadius) < math.max(1.4, horizontalCount * 0.045)
			-- Alternate chase direction on every horizontal row.
			local chaseStep = math.floor(cycle * 1.35)
			local chase = wrap((row % 2 == 0) and (horizontalCount - chaseStep) or (chaseStep + 1), horizontalCount)
			if math.abs(index - chase) <= 1 then active = true end
			intensity = if active then 0.55 + beatPulse * 0.4 else 0.10
		else
			-- Vertical side bars chase in opposite directions.
			local direction = if row == 1 then 1 else -1
			local chase = wrap(math.floor(cycle * 0.72) * direction + 1, verticalCount)
			active = math.abs(index - chase) <= 1
			intensity = if active then 0.62 + beatPulse * 0.32 else 0.12
		end

		local energy = math.clamp(beat.energy or 0, 0, 1)
		intensity = math.clamp(intensity * (0.72 + energy * 0.28), 0.06, 1)
		segment.part.Color = Color3.fromHSV(hue, 0.88, intensity)
		segment.part.Transparency = 0.88 - intensity * 0.78
	end
end)

print("[ClubNeon][DJStageLEDBarFX] Shared beat-clock choreography active; segments=" .. #segments)
