-- AudienceBlinderRig: server-owned fixture layout for client-rendered blinder pulses.
-- Geometry and light instances replicate once; clients only animate light/color locally.
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

local center = Vector3.new((minX + maxX) * 0.5, floorY, (minZ + maxZ) * 0.5)
local folder = workspace:FindFirstChild("AudienceBlinderRig")
if folder then folder:Destroy() end
folder = Instance.new("Folder")
folder.Name = "AudienceBlinderRig"
folder:SetAttribute("ServerOwnedLayout", true)
folder.Parent = workspace

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
for i, position in ipairs(positions) do
	local housing = Instance.new("Part")
	housing.Name = "Blinder" .. i
	housing.Size = Vector3.new(2.4, 0.8, 1.2)
	housing.Anchored, housing.CanCollide, housing.CanQuery, housing.CanTouch = true, false, false, false
	housing.Material = Enum.Material.Metal
	housing.Color = Color3.fromRGB(28, 29, 36)
	housing.CFrame = CFrame.lookAt(position, Vector3.new(center.X, floorY + 7, center.Z))
	housing.Parent = folder
	local lens = Instance.new("Part")
	lens.Name = "Lens"
	lens.Size = Vector3.new(1.7, 0.12, 0.65)
	lens.Anchored, lens.CanCollide, lens.CanQuery, lens.CanTouch = true, false, false, false
	lens.Material = Enum.Material.Neon
	lens.Color = Color3.fromRGB(235, 245, 255)
	lens.CFrame = housing.CFrame * CFrame.new(0, 0.47, -0.12)
	lens.Parent = housing
	local light = Instance.new("SpotLight")
	light.Name = "AudienceWash"
	light.Face = Enum.NormalId.Front
	light.Angle = 78
	light.Range = math.max(90, (maxX - minX) * 0.8)
	light.Brightness = 0
	light.Shadows = false
	light.Color = Color3.fromRGB(230, 240, 255)
	light.Parent = housing
end
print("[ClubNeon][AudienceBlinderRig] Server fixture layout ready; fixtures=" .. #positions)
