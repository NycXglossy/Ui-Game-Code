--!strict
-- ClubNeon distributed venue LED bar rig.
-- Independent of the DJ booth/stage: derives its layout from the same
-- CeilingFX floor grid and wall-trim bounds used by the other ClubNeon rigs.
-- Server owns geometry; DJStageLEDBarFX animates it using ClubAudioSync.

local Workspace = game:GetService("Workspace")

local RIG_NAME = "DJStageLEDBarRig"
local FLOOR_FOLDER_NAME = "CeilingFX"
local HORIZONTAL_ROWS_PER_WALL = 5
local HORIZONTAL_SEGMENTS = 48
local VERTICAL_SEGMENTS = 24
local WALL_INSET = 7
local CORNER_INSET = 2

local floorFolder = Workspace:FindFirstChild(FLOOR_FOLDER_NAME)
if not floorFolder then
	warn("[ClubNeon][VenueLEDBarRig] CeilingFX floor grid not found; distributed LED bars were not created.")
	return
end

local floorY = -math.huge
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
local floorPanels = 0
for _, item in ipairs(floorFolder:GetChildren()) do
	if item:IsA("BasePart") and item.Name == "FloorPanel" then
		floorPanels += 1
		local p = item.Position
		floorY = math.max(floorY, p.Y)
		minX = math.min(minX, p.X)
		maxX = math.max(maxX, p.X)
		minZ = math.min(minZ, p.Z)
		maxZ = math.max(maxZ, p.Z)
	end
end

if floorPanels < 4 or floorY == -math.huge or maxX - minX < 40 or maxZ - minZ < 40 then
	warn("[ClubNeon][VenueLEDBarRig] Floor grid bounds are incomplete; refusing to build a collapsed LED layout. panels=" .. floorPanels)
	return
end

-- Match MovingHeadShow's venue-wide trim measurement so the bars follow the
-- room perimeter rather than clustering around the dance-floor/stage footprint.
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
local topY = math.max(floorY + 12, ceilingY - 5)
local usableTopY = math.min(topY, floorY + 55)
local x0, x1 = venueMinX + WALL_INSET, venueMaxX - WALL_INSET
local z0, z1 = venueMinZ + WALL_INSET, venueMaxZ - WALL_INSET
if x1 - x0 < 40 or z1 - z0 < 40 then
	warn("[ClubNeon][VenueLEDBarRig] Venue perimeter is too small after safety inset; no rig was replaced.")
	return
end

local oldRig = Workspace:FindFirstChild(RIG_NAME)
if oldRig then
	if oldRig:GetAttribute("Ready") == true then
		print("[ClubNeon][VenueLEDBarRig] Existing complete server rig found; preserving it.")
	else
		warn("[ClubNeon][VenueLEDBarRig] Existing incomplete rig found; refusing destructive rebuild or duplicate creation.")
	end
	return
end

local rig = Instance.new("Model")
rig.Name = RIG_NAME
-- Keep the complete venue rig available to clients even when instance
-- streaming is enabled; clients must not animate a partially streamed rig.
rig.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
rig:SetAttribute("Ready", false)
rig:SetAttribute("LayoutMode", "FourWallVenuePerimeter")
rig:SetAttribute("FloorPanelCount", floorPanels)
rig:SetAttribute("UsedVenueTrimBounds", foundTrim)
rig.Parent = Workspace

local function makeSegment(name: string, position: Vector3, size: Vector3, rotation: CFrame, row: number, index: number, orientation: string, wallSide: string)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(40, 180, 255)
	part.Transparency = 0.84
	part.CFrame = CFrame.new(position) * rotation
	part:SetAttribute("BarOrientation", orientation)
	part:SetAttribute("BarRow", row)
	part:SetAttribute("BarIndex", index)
	part:SetAttribute("WallSide", wallSide)
	part.Parent = rig
end

local function makeWallRun(side: string, row: number, count: number)
	local rowSpacing = math.min(3.2, math.max(1.8, (usableTopY - floorY - 5) / (HORIZONTAL_ROWS_PER_WALL + 1)))
	local y = usableTopY - (row - 1) * rowSpacing
	local runLength = if side == "north" or side == "south" then x1 - x0 else z1 - z0
	local segmentLength = runLength / count
	for index = 1, count do
		local along = (index - 0.5) / count
		local position: Vector3
		local rotation: CFrame
		if side == "north" then
			position = Vector3.new(x0 + runLength * along, y, z0)
			rotation = CFrame.new()
		elseif side == "east" then
			position = Vector3.new(x1, y, z0 + runLength * along)
			rotation = CFrame.Angles(0, math.pi * 0.5, 0)
		elseif side == "south" then
			position = Vector3.new(x1 - runLength * along, y, z1)
			rotation = CFrame.Angles(0, math.pi, 0)
		else
			position = Vector3.new(x0, y, z1 - runLength * along)
			rotation = CFrame.Angles(0, -math.pi * 0.5, 0)
		end
		makeSegment(
			"LED_" .. side .. "_R" .. row .. "_S" .. index,
			position,
			Vector3.new(segmentLength * 0.88, 0.34, 0.32),
			rotation,
			(row - 1) * 4 + ({north = 1, east = 2, south = 3, west = 4})[side],
			index,
			"Horizontal",
			side
		)
	end
end

-- Five independently animated horizontal runs on each of the four walls.
for _, side in ipairs({"north", "east", "south", "west"}) do
	for row = 1, HORIZONTAL_ROWS_PER_WALL do
		makeWallRun(side, row, HORIZONTAL_SEGMENTS)
	end
end

-- Eight vertical columns: corners plus each wall midpoint for denser connections.
local verticalHeight = math.max(8, usableTopY - floorY - 3)
local verticalStep = verticalHeight / VERTICAL_SEGMENTS
for cornerIndex, corner in ipairs({
	{side = "northwest", x = x0 + CORNER_INSET, z = z0 + CORNER_INSET},
	{side = "northmid", x = (x0 + x1) * 0.5, z = z0 + CORNER_INSET},
	{side = "northeast", x = x1 - CORNER_INSET, z = z0 + CORNER_INSET},
	{side = "eastmid", x = x1 - CORNER_INSET, z = (z0 + z1) * 0.5},
	{side = "southeast", x = x1 - CORNER_INSET, z = z1 - CORNER_INSET},
	{side = "southmid", x = (x0 + x1) * 0.5, z = z1 - CORNER_INSET},
	{side = "southwest", x = x0 + CORNER_INSET, z = z1 - CORNER_INSET},
	{side = "westmid", x = x0 + CORNER_INSET, z = (z0 + z1) * 0.5},
}) do
	for index = 1, VERTICAL_SEGMENTS do
		local y = floorY + 1.5 + (index - 0.5) * verticalStep
		makeSegment(
			"LED_" .. corner.side .. "_V" .. index,
			Vector3.new(corner.x, y, corner.z),
			Vector3.new(0.34, verticalStep * 0.88, 0.32),
			CFrame.new(),
			cornerIndex,
			index,
			"Vertical",
			corner.side
		)
	end
end

local horizontalBars = 4 * HORIZONTAL_ROWS_PER_WALL
local verticalBars = 8
local segmentCount = horizontalBars * HORIZONTAL_SEGMENTS + verticalBars * VERTICAL_SEGMENTS
rig:SetAttribute("HorizontalBars", horizontalBars)
rig:SetAttribute("HorizontalSegmentsPerBar", HORIZONTAL_SEGMENTS)
rig:SetAttribute("VerticalBars", verticalBars)
rig:SetAttribute("VerticalSegmentsPerBar", VERTICAL_SEGMENTS)
rig:SetAttribute("SegmentCount", segmentCount)
rig:SetAttribute("Ready", true)

print("[ClubNeon][VenueLEDBarRig] Four-wall venue perimeter ready; walls=N/E/S/W=5/5/5/5 rows; "
	.. "horizontal=" .. horizontalBars .. "x" .. HORIZONTAL_SEGMENTS
	.. " vertical=" .. verticalBars .. "x" .. VERTICAL_SEGMENTS
	.. " segments=" .. segmentCount
	.. " floorPanels=" .. floorPanels
	.. " trimBounds=" .. tostring(foundTrim))
