local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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
local lastStep = -1

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock() * SPEED
	local step = math.floor(now)
	if step == lastStep then return end
	lastStep = step

	for _, rig in rigsFolder:GetChildren() do
		for _, part in rig:GetChildren() do
			if part:IsA("BasePart") and part.Name:match("^Segment") then
				local segNum = tonumber(part.Name:match("Segment(%d+)")) or 1
				local paletteIndex = ((segNum + step) % #PALETTE) + 1
				part.Color = PALETTE[paletteIndex]
			end
		end
	end
end)