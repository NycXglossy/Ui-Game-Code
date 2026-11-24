--!strict
-- Distributed venue LED bar client choreography.
-- Uses the shared ClubAudioSync beat clock used by lasers and moving heads.
-- No DJ booth, stage anchor, or separate analyzer is required.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClubAudioSync = require(ReplicatedStorage:WaitForChild("ClubAudioSync"))

local RIG_NAME = "DJStageLEDBarRig"
local rig = workspace:WaitForChild(RIG_NAME, 60)
if not rig or rig:GetAttribute("Ready") ~= true then
	warn("[ClubNeon][VenueLEDBarFX] Distributed LED rig unavailable or not ready; animation not started.")
	return
end

type Segment = {
	part: BasePart,
	orientation: string,
	row: number,
	index: number,
	wallSide: string,
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
				wallSide = tostring(item:GetAttribute("WallSide") or "north"),
			})
		end
	end
end
collectSegments()

local lastBeatCount = -1
local dropUntil = 0
local horizontalCount = tonumber(rig:GetAttribute("HorizontalSegmentsPerBar")) or 32
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

	if beat.beatCount ~= lastBeatCount then
		lastBeatCount = beat.beatCount
		if (beat.onsetStrength or 0) >= 0.78 and beat.beatPhase <= 0.20 then
			dropUntil = os.clock() + 0.62
		end
	end

	local dropActive = os.clock() < dropUntil
	local beatPulse = math.exp(-beat.beatPhase * 5)
	-- beatPosition already follows detected BPM; movementSpeed is the shared
	-- adaptive choreography multiplier. Do not apply BPM a second time.
	local cycle = (beatPosition * speed) % 32

	for _, segment in ipairs(segments) do
		local index = segment.index
		local row = segment.row
		local active = false
		local intensity = 0.10
		local sidePhase = ({north = 0, east = 0.12, south = 0.24, west = 0.36})[segment.wallSide] or 0
		local hue = (hueBase + sidePhase + (row % 4) * 0.055 + index * 0.004) % 1

		if dropActive then
			local progress = 1 - math.clamp((dropUntil - os.clock()) / 0.62, 0, 1)
			if segment.orientation == "Horizontal" then
				local front = progress * horizontalCount + ((row - 1) % 3) * (horizontalCount * 0.10)
				active = math.abs(index - front) <= math.max(2, horizontalCount * 0.055)
			else
				local front = 1 + progress * verticalCount
				active = math.abs(index - front) <= math.max(2, verticalCount * 0.10)
			end
			intensity = if active then 1 else 0.16
		elseif segment.orientation == "Horizontal" then
			local center = (horizontalCount + 1) * 0.5
			local distance = math.abs(index - center)
			local fanRadius = (cycle * 0.52 + ((row - 1) % 3) * (horizontalCount * 0.075) + sidePhase * horizontalCount) % (horizontalCount * 0.5 + 1)
			active = math.abs(distance - fanRadius) < math.max(1.4, horizontalCount * 0.045)
			local chaseStep = math.floor(cycle * 1.35 + sidePhase * horizontalCount)
			local reverse = (row % 2 == 0) or segment.wallSide == "south" or segment.wallSide == "west"
			local chase = wrap(reverse and (horizontalCount - chaseStep) or (chaseStep + 1), horizontalCount)
			if math.abs(index - chase) <= 1 then active = true end
			intensity = if active then 0.55 + beatPulse * 0.4 else 0.09
		else
			local reverse = segment.wallSide == "northeast" or segment.wallSide == "southwest"
			local chase = wrap(math.floor(cycle * 0.72) * (reverse and -1 or 1) + 1, verticalCount)
			active = math.abs(index - chase) <= 1
			intensity = if active then 0.62 + beatPulse * 0.32 else 0.11
		end

		local energy = math.clamp(beat.energy or 0, 0, 1)
		intensity = math.clamp(intensity * (0.72 + energy * 0.28), 0.05, 1)
		segment.part.Color = Color3.fromHSV(hue, 0.88, intensity)
		segment.part.Transparency = 0.88 - intensity * 0.78
	end
end)

print("[ClubNeon][VenueLEDBarFX] Shared beat-clock venue choreography active; segments=" .. #segments)
