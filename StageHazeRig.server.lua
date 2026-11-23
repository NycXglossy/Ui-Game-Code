-- StageHazeRig: server-owned haze anchors and emitter configuration.
-- Particle rates and beam enhancement are adjusted locally by HazeBeamFX.
local function getFloorBounds()
	local folder = workspace:FindFirstChild("CeilingFX")
	if not folder then return nil end
	local minX, maxX, minZ, maxZ, floorY = math.huge, -math.huge, math.huge, -math.huge, -math.huge
	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart") then
			local p = part.Position
			minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
			minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
			if p.Y < 40 then floorY = math.max(floorY, p.Y) end
		end
	end
	if minX == math.huge or floorY == -math.huge then return nil end
	return minX, maxX, minZ, maxZ, floorY
end
local minX, maxX, minZ, maxZ, floorY
repeat
	minX, maxX, minZ, maxZ, floorY = getFloorBounds()
	if not minX then task.wait(0.5) end
until minX

local folder = workspace:FindFirstChild("StageHazeRig")
if folder then folder:Destroy() end
folder = Instance.new("Folder")
folder.Name = "StageHazeRig"
folder:SetAttribute("ServerOwnedLayout", true)
folder.Parent = workspace

local points = {
	Vector3.new((minX + maxX) * 0.25, floorY + 5, (minZ + maxZ) * 0.25),
	Vector3.new((minX + maxX) * 0.75, floorY + 5, (minZ + maxZ) * 0.25),
	Vector3.new((minX + maxX) * 0.25, floorY + 5, (minZ + maxZ) * 0.75),
	Vector3.new((minX + maxX) * 0.75, floorY + 5, (minZ + maxZ) * 0.75),
}
for i, position in ipairs(points) do
	local anchor = Instance.new("Part")
	anchor.Name = "HazeAnchor" .. i
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Position = position
	anchor.Parent = folder
	local attachment = Instance.new("Attachment")
	attachment.Name = "HazeAttachment"
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SoftStageHaze"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 0
	emitter.Enabled = true
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
end
print("[ClubNeon][StageHazeRig] Server haze anchors ready; emitters=" .. #points)
