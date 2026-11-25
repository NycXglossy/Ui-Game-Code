--!strict
-- LightshowFX: client-local palette choreography for server-owned decorative rig segments.
local Workspace = game:GetService("Workspace")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))
local rigsFolder = Workspace:WaitForChild("LightshowRigs")
local PALETTE = {
	Color3.fromRGB(255, 0, 98), Color3.fromRGB(0, 255, 255),
	Color3.fromRGB(255, 0, 255), Color3.fromRGB(0, 255, 128),
	Color3.fromRGB(255, 200, 0), Color3.fromRGB(120, 0, 255),
}
local SPEED = 0.5
local segments = {}
local function addSegment(part)
	if not part:IsA("BasePart") then return end
	local index = tonumber(part.Name:match("^Segment(%d+)"))
	if index then table.insert(segments, {part=part, index=index}) end
end
local function collectRig(rig)
	for _, part in ipairs(rig:GetChildren()) do addSegment(part) end
	rig.ChildAdded:Connect(function() task.defer(function()
		table.clear(segments)
		for _, child in ipairs(rigsFolder:GetChildren()) do
			for _, part in ipairs(child:GetChildren()) do addSegment(part) end
		end
	end) end)
end
local function collectAll()
	table.clear(segments)
	for _, rig in ipairs(rigsFolder:GetChildren()) do
		for _, part in ipairs(rig:GetChildren()) do addSegment(part) end
	end
end
collectAll()
rigsFolder.ChildAdded:Connect(function() task.defer(collectAll) end)
rigsFolder.ChildRemoved:Connect(function() task.defer(collectAll) end)
local lastStep = -1
while true do
	task.wait(0.1)
	local beat = ClubAudioSync.getBeatState()
	local bpm = math.max(beat.bpm, 1)
	local musicalTime = (beat.beatCount + beat.beatPhase) * 60 / bpm
	local step = math.floor(musicalTime * SPEED)
	if step ~= lastStep then
		lastStep = step
		for _, entry in ipairs(segments) do
			if entry.part.Parent then
				entry.part.Color = PALETTE[((entry.index + step - 1) % #PALETTE) + 1]
			end
		end
	end
end
