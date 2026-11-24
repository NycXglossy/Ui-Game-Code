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
	local bpm = math.clamp(beat.bpm or 120, 70, 190)
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
	local cycle = (beatPosition * speed * math.clamp(bpm / 120, 0.65, 1.55)) % 16

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
				local front = progress * 12 + (row - 1) * 2.5
				active = math.abs(index - front) <= 2.2
			else
				local front = 1 + progress * 8
				active = math.abs(index - front) <= 2
			end
			intensity = if active then 1 else 0.18
		elseif segment.orientation == "Horizontal" then
			-- Expanding fan from the center of the DJ backdrop.
			local distance = math.abs(index - 6.5)
			local fanFront = (cycle * 0.75 + (row - 1) * 1.8) % 7
			active = math.abs(distance - fanFront) < 1.15
			-- Alternate chase direction on every horizontal row.
			local chase = wrap(math.floor(cycle * 1.5) + (row % 2 == 0 and -1 or 1), 12)
			if math.abs(index - chase) <= 1 then active = true end
			intensity = if active then 0.55 + beatPulse * 0.4 else 0.10
		else
			-- Vertical side bars chase in opposite directions.
			local direction = if row == 1 then 1 else -1
			local chase = wrap(math.floor(cycle * 0.8) * direction + 1, 8)
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
