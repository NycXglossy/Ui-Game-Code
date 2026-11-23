-- AudienceBlinderFX: locally rendered audience-facing blinder banks.
-- Builds lightweight client-only fixtures around the dance floor and pulses
-- them on musical kicks. No server Heartbeat or replicated part churn.
local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

local function getFloorBounds()
	local folder = workspace:FindFirstChild("CeilingFX")
	if not folder then return nil end
	local minX, maxX, minZ, maxZ, floorY = math.huge, -math.huge, math.huge, -math.huge, -math.huge
	for _, part in folder:GetChildren() do
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

local bounds
while true do
	local found = table.pack(getFloorBounds())
	if found[1] ~= nil then bounds = found; break end
	task.wait(0.5)
end
local minX, maxX, minZ, maxZ, floorY = table.unpack(bounds, 1, bounds.n)
local center = Vector3.new((minX + maxX) * 0.5, floorY, (minZ + maxZ) * 0.5)
local folder = workspace:FindFirstChild("ClientAudienceBlinderRig")
if folder then folder:Destroy() end
folder = Instance.new("Folder")
folder.Name = "ClientAudienceBlinderRig"
folder.Parent = workspace

local fixtures = {}
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
	lens.Parent = folder
	local light = Instance.new("SpotLight")
	light.Name = "AudienceWash"
	light.Face = Enum.NormalId.Front
	light.Angle = 78
	light.Range = math.max(90, (maxX - minX) * 0.8)
	light.Brightness = 0
	light.Shadows = false
	light.Color = Color3.fromRGB(230, 240, 255)
	light.Parent = housing
	table.insert(fixtures, {housing = housing, lens = lens, light = light, index = i})
end

local lastBeat = -1
local pulse = 0
local energy = 0
local lastT = os.clock()
local palette = {
	Color3.fromRGB(255, 245, 220),
	Color3.fromRGB(0, 235, 255),
	Color3.fromRGB(255, 45, 175),
	Color3.fromRGB(150, 90, 255),
}
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now
	local beat = ClubAudioSync.getBeatState()
	energy = beat.energy
	if beat.beatCount ~= lastBeat then lastBeat = beat.beatCount end
	pulse = math.exp(-beat.beatPhase * 5) * math.clamp(0.35 + beat.energy * 0.9, 0.25, 1)
	local tempoTime = now * (beat.bpm / 128)
	local hueStep = math.floor(beat.beatCount / 4)
	for _, fixture in ipairs(fixtures) do
		local wave = 0.5 + 0.5 * math.sin(tempoTime * 1.4 + fixture.index * 0.8)
		local intensity = math.clamp(0.08 + energy * 0.12 + pulse * (0.35 + wave * 0.35), 0, 0.8)
		fixture.light.Brightness = intensity * 5.5
		local color = if pulse > 0.18 then palette[(hueStep + fixture.index - 1) % #palette + 1] else palette[(fixture.index - 1) % #palette + 1]
		fixture.light.Color = color
		fixture.lens.Color = color
	end
end)

script.Destroying:Connect(function()
	if folder then folder:Destroy() end
end)
