local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))
-- LightshowFX: low-frequency palette cycling for decorative rig segments.
-- Cache the segment list once and sleep between checks instead of scanning all rigs
-- on every server Heartbeat.

local rigsFolder = workspace:WaitForChild("LightshowRigs", 10)
if not rigsFolder then return end

local PALETTE = {
	Color3.fromRGB(255, 0, 98),
	Color3.fromRGB(0, 255, 255),
	Color3.fromRGB(255, 0, 255),
	Color3.fromRGB(0, 255, 128),
	Color3.fromRGB(255, 200, 0),
	Color3.fromRGB(120, 0, 255),
}

local SPEED = 0.5 -- color steps per second
local segments = {}

local function addSegment(part)
	if not part:IsA("BasePart") then return end
	local segNum = tonumber(part.Name:match("^Segment(%d+)"))
	if segNum then
		table.insert(segments, {part = part, index = segNum})
	end
end

local function collectRig(rig)
	for _, part in rig:GetChildren() do
		addSegment(part)
	end
	rig.ChildAdded:Connect(addSegment)
end

for _, rig in rigsFolder:GetChildren() do
	collectRig(rig)
end
rigsFolder.ChildAdded:Connect(collectRig)

local lastStep = -1
while task.wait(0.1) do
	local beat = ClubAudioSync.getBeatState()
	local step = math.floor(os.clock() * SPEED * (beat.bpm / 128))
	if step ~= lastStep then
		lastStep = step
		for _, entry in ipairs(segments) do
			if entry.part.Parent then
				local paletteIndex = ((entry.index + step) % #PALETTE) + 1
				entry.part.Color = PALETTE[paletteIndex]
			end
		end
	end
end
