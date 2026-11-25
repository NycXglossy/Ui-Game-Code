--!strict
-- AudienceBlinderRig: persistent server-owned layout for client-rendered blinder pulses.
-- Existing fixtures are adopted; only missing fixture indices/children are created.
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

local center = Vector3.new((minX + maxX) * 0.5, floorY, (minZ + maxZ) * 0.5)
local folder = workspace:FindFirstChild("AudienceBlinderRig")
if folder and not folder:IsA("Folder") then
	error("[ClubNeon][AudienceBlinderRig] Existing destination is not a Folder; refusing to replace it.")
end
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "AudienceBlinderRig"
	folder.Parent = workspace
end
folder:SetAttribute("ServerOwnedLayout", true)
folder:SetAttribute("Ready", false)

local positions = {
	Vector3.new(minX + 12, floorY + 2, minZ + 12),
	Vector3.new(center.X, floorY + 2, minZ + 12),
	Vector3.new(maxX - 12, floorY + 2, minZ + 12),
	Vector3.new(maxX - 12, floorY + 2, center.Z),
	Vector3.new(maxX - 12, floorY + 2, maxZ - 12),
	Vector3.new(center.X, floorY + 2, maxZ - 12),
	Vector3.new(minX + 12, floorY + 2, maxZ - 12),
	Vector3.new(minX + 12, floorY + 2, center.Z),
}

local created = 0
for i, position in ipairs(positions) do
	local name = "Blinder" .. i
	local housing = folder:FindFirstChild(name)
	if housing and not housing:IsA("BasePart") then
		error("[ClubNeon][AudienceBlinderRig] " .. name .. " exists but is not a BasePart.")
	end
	if not housing then
		housing = Instance.new("Part")
		housing.Name = name
		housing.Size = Vector3.new(2.4, 0.8, 1.2)
		housing.Anchored, housing.CanCollide, housing.CanQuery, housing.CanTouch = true, false, false, false
		housing.Material = Enum.Material.Metal
		housing.Color = Color3.fromRGB(28, 29, 36)
		housing.CFrame = CFrame.lookAt(position, Vector3.new(center.X, floorY + 7, center.Z))
		housing.Parent = folder
		created += 1
	end

	local lens = housing:FindFirstChild("Lens")
	if lens and not lens:IsA("BasePart") then
		error("[ClubNeon][AudienceBlinderRig] " .. name .. "/Lens exists but is not a BasePart.")
	end
	if not lens then
		lens = Instance.new("Part")
		lens.Name = "Lens"
		lens.Size = Vector3.new(1.7, 0.12, 0.65)
		lens.Anchored, lens.CanCollide, lens.CanQuery, lens.CanTouch = true, false, false, false
		lens.Material = Enum.Material.Neon
		lens.Color = Color3.fromRGB(235, 245, 255)
		lens.CFrame = housing.CFrame * CFrame.new(0, 0.47, -0.12)
		lens.Parent = housing
		created += 1
	end

	local light = housing:FindFirstChild("AudienceWash")
	if light and not light:IsA("SpotLight") then
		error("[ClubNeon][AudienceBlinderRig] " .. name .. "/AudienceWash exists but is not a SpotLight.")
	end
	if not light then
		light = Instance.new("SpotLight")
		light.Name = "AudienceWash"
		light.Face = Enum.NormalId.Front
		light.Angle = 78
		light.Range = math.max(90, (maxX - minX) * 0.8)
		light.Brightness = 0
		light.Shadows = false
		light.Color = Color3.fromRGB(230, 240, 255)
		light.Parent = housing
		created += 1
	end
end

local fixtureCount = 0
for _, child in ipairs(folder:GetChildren()) do
	if child:IsA("BasePart") and child.Name:match("^Blinder%d+$")
		and child:FindFirstChild("Lens") and child:FindFirstChild("AudienceWash") then
		fixtureCount += 1
	end
end
folder:SetAttribute("FixtureCount", fixtureCount)
folder:SetAttribute("CreatedInstanceCount", created)
folder:SetAttribute("Ready", fixtureCount == #positions)
if fixtureCount ~= #positions then
	warn("[ClubNeon][AudienceBlinderRig] Layout incomplete; valid fixtures=" .. fixtureCount .. "/" .. #positions)
else
	print("[ClubNeon][AudienceBlinderRig] Persistent server layout ready; fixtures=" .. fixtureCount .. " createdInstances=" .. created)
end
