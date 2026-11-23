-- KineticCenterpieceFX: animated centerpiece orb and rings built by LaserShowScript.
-- Client-side CFrame motion keeps the kinetic sculpture responsive without
-- adding a server Heartbeat or creating replicated parts.
local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

local rig
local orb
local glow
local rings = {}
local baseOrbSize = Vector3.new(3.5, 3.5, 3.5)
local center = Vector3.zero

local function collect()
	rig = workspace:FindFirstChild("LaserRig")
	if not rig then return false end
	orb = rig:FindFirstChild("CenterOrb")
	if not (orb and orb:IsA("BasePart")) then return false end
	glow = orb:FindFirstChild("Glow")
	center = orb.Position
	baseOrbSize = orb.Size
	table.clear(rings)
	for _, child in ipairs(rig:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^OrbRing%d+$") then
			local index = tonumber(child.Name:match("%d+")) or (#rings + 1)
			table.insert(rings, {part = child, index = index, base = child.CFrame, size = child.Size})
		end
	end
	return #rings > 0
end

while not collect() do task.wait(0.5) end
local lastT = os.clock()
local lastBeat = -1
local kick = 0
local hueOffset = 0
RunService.Heartbeat:Connect(function()
	if not (orb and orb.Parent and rig and rig.Parent) then
		if not collect() then return end
	end
	local now = os.clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now
	local beat = ClubAudioSync.getBeatState()
	if beat.beatCount ~= lastBeat then
		lastBeat = beat.beatCount
		hueOffset = (beat.beatCount * 0.035) % 1
	end
	local tempoTime = now * (beat.bpm / 128)
	kick = math.exp(-beat.beatPhase * 5) * math.clamp(0.35 + beat.energy * 0.9, 0.25, 1)
	local pulse = 1 + kick * 0.18 + math.sin(tempoTime * 1.7) * 0.035
	local color = Color3.fromHSV((hueOffset + tempoTime * 0.018) % 1, 0.88, 1)
	orb.Size = baseOrbSize * pulse
	orb.Color = color
	orb.CFrame = CFrame.new(center) * CFrame.Angles(0, tempoTime * 0.28, math.sin(tempoTime * 0.65) * 0.08)
	if glow and glow.Parent then
		glow.Color = color
		glow.Brightness = 2.2 + kick * 4.5
		glow.Range = 44 + kick * 18
	end
	for _, ring in ipairs(rings) do
		if ring.part.Parent then
			local speed = 0.18 + ring.index * 0.11
			local tilt = math.sin(tempoTime * 0.42 + ring.index) * 0.16
			ring.part.CFrame = CFrame.new(center) * CFrame.Angles(tilt, tempoTime * speed * (if ring.index % 2 == 0 then -1 else 1), ring.index * 0.6 + tempoTime * 0.08)
			ring.part.Size = ring.size * (1 + kick * 0.035)
			ring.part.Color = color:Lerp(Color3.fromRGB(255, 255, 255), kick * 0.28)
		end
	end
end)
