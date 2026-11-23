-- HazeBeamFX: client-only atmospheric haze and beam readability.
-- Low particle rates create a subtle stage haze without changing global
-- Lighting/Atmosphere or adding server-side simulation cost.
local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

local function floorBounds()
	local folder = workspace:FindFirstChild("CeilingFX")
	if not folder then return nil end
	local minX, maxX, minZ, maxZ, y = math.huge, -math.huge, math.huge, -math.huge, -math.huge
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") then
			minX, maxX = math.min(minX, p.Position.X), math.max(maxX, p.Position.X)
			minZ, maxZ = math.min(minZ, p.Position.Z), math.max(maxZ, p.Position.Z)
			if p.Position.Y < 40 then y = math.max(y, p.Position.Y) end
		end
	end
	if minX == math.huge or y == -math.huge then return nil end
	return minX, maxX, minZ, maxZ, y
end

local bounds
while true do
	local found = table.pack(floorBounds())
	if found[1] ~= nil then bounds = found; break end
	task.wait(0.5)
end
local minX, maxX, minZ, maxZ, floorY = table.unpack(bounds, 1, bounds.n)
local hazeFolder = workspace:FindFirstChild("ClientStageHaze")
if hazeFolder then hazeFolder:Destroy() end
hazeFolder = Instance.new("Folder")
hazeFolder.Name = "ClientStageHaze"
hazeFolder.Parent = workspace

local emitters = {}
for i, offset in ipairs({
	Vector3.new(minX * 0.0 + (minX + maxX) * 0.25, 5, (minZ + maxZ) * 0.25),
	Vector3.new((minX + maxX) * 0.75, 5, (minZ + maxZ) * 0.25),
	Vector3.new((minX + maxX) * 0.25, 5, (minZ + maxZ) * 0.75),
	Vector3.new((minX + maxX) * 0.75, 5, (minZ + maxZ) * 0.75),
}) do
	local anchor = Instance.new("Part")
	anchor.Name = "HazeAnchor" .. i
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Position = Vector3.new(offset.X, floorY + offset.Y, offset.Z)
	anchor.Parent = hazeFolder
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SoftStageHaze"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 1.2
	emitter.Lifetime = NumberRange.new(7, 11)
	emitter.Speed = NumberRange.new(0.25, 0.8)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-8, 8)
	emitter.LightEmission = 0.18
	emitter.LightInfluence = 0.15
	emitter.Color = ColorSequence.new(Color3.fromRGB(190, 205, 255), Color3.fromRGB(100, 115, 160))
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.94),
		NumberSequenceKeypoint.new(0.25, 0.82),
		NumberSequenceKeypoint.new(0.8, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 8),
		NumberSequenceKeypoint.new(0.5, 14),
		NumberSequenceKeypoint.new(1, 19),
	})
	emitter.Parent = attachment
	table.insert(emitters, emitter)
end

-- Give existing moving-head and laser beams a brighter, broader look while
-- preserving their current color/transparency choreography.
local function enhanceBeams(root)
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("Beam") and item:GetAttribute("HazeBeamEnhanced") ~= true then
			item:SetAttribute("HazeBeamEnhanced", true)
			item.LightEmission = 1
			item.LightInfluence = 0
			item.Width0 = math.clamp(item.Width0 * 1.15, 0.08, 1.4)
			item.Width1 = math.clamp(item.Width1 * 1.12, 0.12, 3.5)
		end
	end
end

local function refresh()
	for _, name in ipairs({"MovingHeadRig", "LaserRig"}) do
		local root = workspace:FindFirstChild(name)
		if root then enhanceBeams(root) end
	end
end
refresh()
workspace.ChildAdded:Connect(function(child)
	if child.Name == "MovingHeadRig" or child.Name == "LaserRig" then
		task.defer(refresh)
	end
end)

local lastT = os.clock()
local scanAge = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now
	scanAge += dt
	if scanAge >= 5 then scanAge = 0; refresh() end
	local beat = ClubAudioSync.getBeatState()
	local lift = math.clamp(beat.energy, 0, 1)
	local beatBreath = 0.5 + 0.5 * math.cos(beat.beatPhase * math.pi * 2)
	for _, emitter in ipairs(emitters) do
		emitter.Rate = 0.6 + lift * 1.1 + beatBreath * beat.pulse * 1.4
	end
end)

script.Destroying:Connect(function()
	if hazeFolder then hazeFolder:Destroy() end
end)
