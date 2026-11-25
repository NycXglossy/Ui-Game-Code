--!strict
-- StageHazeRig: persistent server-owned haze anchors and emitter configuration.
-- Existing anchors/emitters are adopted; only missing indices/children are created.
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
	if minX == math.huge or floorY == -math.huge or minX >= maxX or minZ >= maxZ then return nil end
	return minX, maxX, minZ, maxZ, floorY
end

local minX, maxX, minZ, maxZ, floorY
repeat
	minX, maxX, minZ, maxZ, floorY = getFloorBounds()
	if not minX then task.wait(0.5) end
until minX

local folder = workspace:FindFirstChild("StageHazeRig")
if folder and not folder:IsA("Folder") then
	error("[ClubNeon][StageHazeRig] Existing destination is not a Folder; refusing to replace it.")
end
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "StageHazeRig"
	folder.Parent = workspace
end
folder:SetAttribute("ServerOwnedLayout", true)
folder:SetAttribute("Ready", false)

local points = {
	Vector3.new((minX + maxX) * 0.25, floorY + 5, (minZ + maxZ) * 0.25),
	Vector3.new((minX + maxX) * 0.75, floorY + 5, (minZ + maxZ) * 0.25),
	Vector3.new((minX + maxX) * 0.25, floorY + 5, (minZ + maxZ) * 0.75),
	Vector3.new((minX + maxX) * 0.75, floorY + 5, (minZ + maxZ) * 0.75),
}

local created = 0
for i, position in ipairs(points) do
	local name = "HazeAnchor" .. i
	local anchor = folder:FindFirstChild(name)
	if anchor and not anchor:IsA("BasePart") then
		error("[ClubNeon][StageHazeRig] " .. name .. " exists but is not a BasePart.")
	end
	if not anchor then
		anchor = Instance.new("Part")
		anchor.Name = name
		anchor.Size = Vector3.one
		anchor.Transparency = 1
		anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
		anchor.Position = position
		anchor.Parent = folder
		created += 1
	end

	local attachment = anchor:FindFirstChild("HazeAttachment")
	if attachment and not attachment:IsA("Attachment") then
		error("[ClubNeon][StageHazeRig] " .. name .. "/HazeAttachment exists but is not an Attachment.")
	end
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "HazeAttachment"
		attachment.Parent = anchor
		created += 1
	end

	local emitter = attachment:FindFirstChild("SoftStageHaze")
	if emitter and not emitter:IsA("ParticleEmitter") then
		error("[ClubNeon][StageHazeRig] " .. name .. "/SoftStageHaze exists but is not a ParticleEmitter.")
	end
	if not emitter then
		emitter = Instance.new("ParticleEmitter")
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
		created += 1
	end
end

local emitterCount = 0
for _, descendant in ipairs(folder:GetDescendants()) do
	if descendant:IsA("ParticleEmitter") and descendant.Name == "SoftStageHaze" then
		emitterCount += 1
	end
end
folder:SetAttribute("EmitterCount", emitterCount)
folder:SetAttribute("CreatedInstanceCount", created)
folder:SetAttribute("Ready", emitterCount == #points)
if emitterCount ~= #points then
	warn("[ClubNeon][StageHazeRig] Layout incomplete; emitters=" .. emitterCount .. "/" .. #points)
else
	print("[ClubNeon][StageHazeRig] Persistent server haze layout ready; emitters=" .. emitterCount .. " createdInstances=" .. created)
end
