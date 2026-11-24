-- StrobeLightsRig: server-owned perimeter strobe fixture layout.
-- Geometry and SpotLight instances replicate once; StrobeLightsFX animates
-- their color, brightness, and beat-synced bursts locally on each client.
-- Kept separate from MovingHeadRig so both systems can be tuned independently.

local Workspace = game:GetService("Workspace")

local RIG_NAME = "StrobeLights"
local FLOOR_FOLDER_NAME = "CeilingFX"
local FIXTURES_PER_WALL = 6
local WALL_INSET = 5
local HEIGHT_BELOW_CEILING = 7

local function getFloorBounds()
	local folder = Workspace:FindFirstChild(FLOOR_FOLDER_NAME)
	if not folder then return nil end
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local floorY = -math.huge
	local panelCount = 0
	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart") and part.Name == "FloorPanel" then
			panelCount += 1
			local p = part.Position
			minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
			minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
			floorY = math.max(floorY, p.Y)
		end
	end
	if panelCount < 4 or floorY == -math.huge or maxX - minX < 40 or maxZ - minZ < 40 then
		return nil
	end
	return minX, maxX, minZ, maxZ, floorY, panelCount
end

local minX, maxX, minZ, maxZ, floorY, floorPanels
repeat
	minX, maxX, minZ, maxZ, floorY, floorPanels = getFloorBounds()
	if not minX then task.wait(0.5) end
until minX

-- Match the venue-wide bounds used by MovingHeadShow so the perimeter strobes
-- complement the ceiling rig instead of clustering around the dance-floor grid.
local venueMinX, venueMaxX, venueMinZ, venueMaxZ = minX, maxX, minZ, maxZ
local foundTrim = false
for _, item in ipairs(Workspace:GetDescendants()) do
	if item:IsA("BasePart") and (item.Name == "TrimH" or item.Name == "TrimV")
		and math.max(item.Size.X, item.Size.Z) >= 300 then
		foundTrim = true
		local cf, size = item.CFrame, item.Size
		for _, ux in ipairs({-0.5, 0.5}) do
			for _, uz in ipairs({-0.5, 0.5}) do
				local corner = cf * Vector3.new(size.X * ux, 0, size.Z * uz)
				venueMinX = math.min(venueMinX, corner.X)
				venueMaxX = math.max(venueMaxX, corner.X)
				venueMinZ = math.min(venueMinZ, corner.Z)
				venueMaxZ = math.max(venueMaxZ, corner.Z)
			end
		end
	end
end

local center = Vector3.new((venueMinX + venueMaxX) * 0.5, floorY, (venueMinZ + venueMaxZ) * 0.5)
local ceilingRay = Workspace:Raycast(center, Vector3.new(0, 500, 0))
local ceilingY = ceilingRay and ceilingRay.Position.Y or floorY + 60
local fixtureY = math.max(floorY + 12, ceilingY - HEIGHT_BELOW_CEILING)
local x0, x1 = venueMinX + WALL_INSET, venueMaxX - WALL_INSET
local z0, z1 = venueMinZ + WALL_INSET, venueMaxZ - WALL_INSET
if x1 - x0 < 40 or z1 - z0 < 40 then
	warn("[ClubNeon][StrobeLightsRig] Venue bounds are too small after safety inset; existing rig was left untouched.")
	return
end

local oldRig = Workspace:FindFirstChild(RIG_NAME)
if oldRig then oldRig:Destroy() end

local rig = Instance.new("Model")
rig.Name = RIG_NAME
rig.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
rig:SetAttribute("ServerOwnedLayout", true)
rig:SetAttribute("Ready", false)
rig:SetAttribute("FloorPanelCount", floorPanels)
rig:SetAttribute("UsedVenueTrimBounds", foundTrim)
rig.Parent = Workspace

local function makeFixture(index, position, lookAt)
	local panel = Instance.new("Part")
	panel.Name = "S" .. index
	panel.Size = Vector3.new(3.4, 1.1, 0.55)
	panel.Anchored = true
	panel.CanCollide = false
	panel.CanTouch = false
	panel.CanQuery = false
	panel.CastShadow = false
	panel.Material = Enum.Material.Metal
	panel.Color = Color3.fromRGB(32, 34, 42)
	panel.CFrame = CFrame.lookAt(position, lookAt)
	panel.Parent = rig

	local lens = Instance.new("Part")
	lens.Name = "Lens"
	lens.Size = Vector3.new(2.7, 0.12, 0.18)
	lens.Anchored = true
	lens.CanCollide = false
	lens.CanTouch = false
	lens.CanQuery = false
	lens.CastShadow = false
	lens.Material = Enum.Material.Neon
	lens.Color = Color3.new(1, 1, 1)
	lens.CFrame = panel.CFrame * CFrame.new(0, 0.36, -0.31)
	lens.Parent = panel

	local flash = Instance.new("SpotLight")
	flash.Name = "Flash"
	flash.Face = Enum.NormalId.Front
	flash.Angle = 105
	flash.Range = math.max(100, (maxX - minX) * 0.9)
	flash.Brightness = 0
	flash.Shadows = false
	flash.Color = Color3.new(1, 1, 1)
	flash.Enabled = false
	flash.Parent = panel
end

local index = 0
local walls = {
	{ name = "North", count = FIXTURES_PER_WALL, point = function(t) return Vector3.new(x0 + (x1 - x0) * t, fixtureY, z0), Vector3.new(center.X, floorY, center.Z) end },
	{ name = "East", count = FIXTURES_PER_WALL, point = function(t) return Vector3.new(x1, fixtureY, z0 + (z1 - z0) * t), Vector3.new(center.X, floorY, center.Z) end },
	{ name = "South", count = FIXTURES_PER_WALL, point = function(t) return Vector3.new(x1 - (x1 - x0) * t, fixtureY, z1), Vector3.new(center.X, floorY, center.Z) end },
	{ name = "West", count = FIXTURES_PER_WALL, point = function(t) return Vector3.new(x0, fixtureY, z1 - (z1 - z0) * t), Vector3.new(center.X, floorY, center.Z) end },
}
for _, wall in ipairs(walls) do
	for slot = 1, wall.count do
		index += 1
		local t = (slot - 0.5) / wall.count
		local position, target = wall.point(t)
		makeFixture(index, position, target)
	end
end

rig:SetAttribute("FixtureCount", index)
rig:SetAttribute("Ready", true)
print("[ClubNeon][StrobeLightsRig] Server-owned four-wall strobe layout ready; fixtures="
	.. index .. " floorPanels=" .. floorPanels .. " trimBounds=" .. tostring(foundTrim))
