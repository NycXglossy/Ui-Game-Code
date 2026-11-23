-- MovingHeadShow (server half of the dual-script projector show):
-- builds the truss ring, the moving-head fixtures and the strobe bars
-- once at startup. The rig is server-authoritative and replicated to
-- every client. All beat-synced animation lives in the client half
-- (StarterPlayerScripts.MovingHeadShowFX), which uses the same beat
-- detector as the rest of the club's lighting FX.

-- Measure the dance floor from the panel grid
local fx = workspace:FindFirstChild("CeilingFX")
if not fx then return end
local floorY = -math.huge
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
for _, p in fx:GetChildren() do
	if p:IsA("BasePart") and p.Name == "FloorPanel" then
		local pos = p.Position
		floorY = math.max(floorY, pos.Y)
		minX = math.min(minX, pos.X); maxX = math.max(maxX, pos.X)
		minZ = math.min(minZ, pos.Z); maxZ = math.max(maxZ, pos.Z)
	end
end
if floorY == -math.huge then return end

local CENTER = Vector3.new((minX + maxX) / 2, floorY, (minZ + maxZ) / 2)
local RADIUS = math.min(maxX - minX, maxZ - minZ) / 2

-- Measure the full venue from the long wall trim strips (they run along
-- each wall of the club) so the truss ring can span wall-to-wall instead
-- of hugging the dance floor. Extents are computed rotation-aware since
-- the strips are oriented parts.
local vX0, vX1, vZ0, vZ1 = minX, maxX, minZ, maxZ
local foundTrim = false
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") and (d.Name == "TrimH" or d.Name == "TrimV")
		and math.max(d.Size.X, d.Size.Z) >= 300 then
		foundTrim = true
		local cf, sz = d.CFrame, d.Size
		for _, ux in ipairs({ -0.5, 0.5 }) do
			for _, uz in ipairs({ -0.5, 0.5 }) do
				local c = cf * Vector3.new(sz.X * ux, 0, sz.Z * uz)
				vX0 = math.min(vX0, c.X); vX1 = math.max(vX1, c.X)
				vZ0 = math.min(vZ0, c.Z); vZ1 = math.max(vZ1, c.Z)
			end
		end
	end
end

local rig = Instance.new("Folder")
rig.Name = "MovingHeadRig"
rig.Parent = workspace

-- -----------------------------------------------------------
-- Truss ring: a box-truss loop suspended above the floor edge
-- -----------------------------------------------------------
-- Hang the rig just under the roof: raycast up from the floor center to
-- find the ceiling, then suspend the truss a few studs below it
local ceilRay = workspace:Raycast(CENTER, Vector3.new(0, 500, 0))
local CEIL_Y = ceilRay and ceilRay.Position.Y or floorY + 60
local TRUSS_Y = CEIL_Y - 4
-- Span the full venue walls so the floor supports land at each corner of
-- the club; fall back to the old dance-floor inset if no wall trims exist
local INSET = foundTrim and 7 or 14
local tx0, tx1 = vX0 + INSET, vX1 - INSET
local tz0, tz1 = vZ0 + INSET, vZ1 - INSET

local function trussRun(fromX, fromZ, toX, toZ, name)
	local len = math.sqrt((toX - fromX)^2 + (toZ - fromZ)^2)
	local midX, midZ = (fromX + toX) / 2, (fromZ + toZ) / 2
	local angle = math.atan2(toZ - fromZ, toX - fromX)
	local rot = CFrame.Angles(0, -angle, 0)
	-- Four parallel rails make a box truss silhouette
	for _, off in ipairs({ Vector3.new(0, 1.2, 1.2), Vector3.new(0, 1.2, -1.2),
		Vector3.new(0, -1.2, 1.2), Vector3.new(0, -1.2, -1.2) }) do
		local rail = Instance.new("Part")
		rail.Name = name .. "_Rail"
		rail.Size = Vector3.new(len, 0.5, 0.5)
		rail.Anchored = true
		rail.CanCollide = false
		rail.CanQuery = false
		rail.Material = Enum.Material.Metal
		rail.Color = Color3.fromRGB(120, 122, 128)
		rail.CFrame = CFrame.new(midX + off.X, TRUSS_Y + off.Y, midZ + off.Z) * rot
		rail.Parent = rig
	end
	-- Diagonal cross-braces every 12 studs for a real truss look
	local n = math.max(1, math.floor(len / 12))
	for i = 0, n - 1 do
		local t = (i + 0.5) / n
		local px = fromX + (toX - fromX) * t
		local pz = fromZ + (toZ - fromZ) * t
		for _, flip in ipairs({ 1, -1 }) do
			local brace = Instance.new("Part")
			brace.Name = name .. "_Brace"
			brace.Size = Vector3.new(0.35, 3.4, 0.35)
			brace.Anchored = true
			brace.CanCollide = false
			brace.CanQuery = false
			brace.Material = Enum.Material.Metal
			brace.Color = Color3.fromRGB(110, 112, 118)
			brace.CFrame = CFrame.new(px, TRUSS_Y, pz)
			* CFrame.Angles(0, -angle, flip * 0.72)
			brace.Parent = rig
		end
	end
end

trussRun(tx0, tz0, tx1, tz0, "TrussN")
trussRun(tx1, tz0, tx1, tz1, "TrussE")
trussRun(tx0, tz1, tx1, tz1, "TrussS")
trussRun(tx0, tz0, tx0, tz1, "TrussW")

-- Vertical truss legs down to the floor at the corners so the rig reads
-- as a real structure instead of floating tubes
for _, corner in ipairs({
	{ tx0, tz0 }, { tx1, tz0 }, { tx1, tz1 }, { tx0, tz1 },
}) do
	local leg = Instance.new("Part")
	leg.Name = "TrussLeg"
	leg.Size = Vector3.new(2.4, TRUSS_Y - floorY, 2.4)
	leg.Anchored = true
	leg.CanCollide = false
	leg.CanQuery = false
	leg.Material = Enum.Material.Metal
	leg.Color = Color3.fromRGB(120, 122, 128)
	leg.CFrame = CFrame.new(corner[1], floorY + (TRUSS_Y - floorY) / 2, corner[2])
	leg.Parent = rig

	-- Chrome base plate at the foot of each support tower
	local base = Instance.new("Part")
	base.Name = "TrussBase"
	base.Size = Vector3.new(5, 0.5, 5)
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.Material = Enum.Material.DiamondPlate
	base.Color = Color3.fromRGB(140, 142, 148)
	base.Reflectance = 0.35
	base.CFrame = CFrame.new(corner[1], floorY + 0.25, corner[2])
	base.Parent = rig
end

-- -----------------------------------------------------------
-- Moving-head fixtures hung from the truss
-- -----------------------------------------------------------
-- Preserve the original 16 fixture positions and interleave a supplemental
-- set of 16. This gives every wall an independent second coverage row.
local ORIGINAL_HEADS = 16
local SUPPLEMENTAL_HEADS = 16
local HEADS = ORIGINAL_HEADS + SUPPLEMENTAL_HEADS
local function makeHead(i, pos, wallSide, wallSlot)
	local color = Color3.fromHSV(i / HEADS, 1, 1)

	-- Clamp block bolted under the truss rail
	local clamp = Instance.new("Part")
	clamp.Name = "Head" .. i .. "_Clamp"
	clamp.Size = Vector3.new(1, 0.6, 1)
	clamp.Anchored = true
	clamp.CanCollide = false
	clamp.CanQuery = false
	clamp.Material = Enum.Material.Metal
	clamp.Color = Color3.fromRGB(60, 62, 66)
	clamp.CFrame = CFrame.new(pos.X, TRUSS_Y - 1.4, pos.Z)
	clamp.Parent = rig

	-- Fixture body: dark metal canister with a chrome heat-shield band
	local body = Instance.new("Part")
	body.Name = "Head" .. i .. "_Body"
	body.Size = Vector3.new(1.3, 1.8, 1.3)
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.Material = Enum.Material.Metal
	body.Color = Color3.fromRGB(35, 36, 40)
	body.CFrame = CFrame.new(pos.X, TRUSS_Y - 2.3, pos.Z)
	body.Parent = rig

	local band = Instance.new("Part")
	band.Name = "Head" .. i .. "_Band"
	band.Size = Vector3.new(1.45, 0.35, 1.45)
	band.Anchored = true
	band.CanCollide = false
	band.CanQuery = false
	band.Material = Enum.Material.Metal
	band.Color = Color3.fromRGB(180, 185, 195)
	band.Reflectance = 0.6
	band.CFrame = CFrame.new(pos.X, TRUSS_Y - 1.7, pos.Z)
	band.Parent = rig

	-- Yoke arms: chrome side arms cradling the head, like real moving heads
	for _, side in ipairs({ -1, 1 }) do
		local arm = Instance.new("Part")
		arm.Name = "Head" .. i .. "_Yoke" .. (side < 0 and "L" or "R")
		arm.Size = Vector3.new(0.25, 2.4, 0.8)
		arm.Anchored = true
		arm.CanCollide = false
		arm.CanQuery = false
		arm.Material = Enum.Material.Metal
		arm.Color = Color3.fromRGB(160, 165, 175)
		arm.Reflectance = 0.5
		arm.CFrame = CFrame.new(pos.X + side * 0.95, TRUSS_Y - 3.4, pos.Z)
		arm.Parent = rig
	end

	-- The head itself: a neon lens that visibly aims at its target
	local head = Instance.new("Part")
	head.Name = "Head" .. i .. "_Lens"
	head.Shape = Enum.PartType.Cylinder
	head.Size = Vector3.new(1.3, 1.5, 1.5)
	head.Anchored = true
	head.CanCollide = false
	head.CanQuery = false
	head.Material = Enum.Material.Neon
	head.Color = color
	head.CFrame = CFrame.new(pos.X, TRUSS_Y - 3.2, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
	head:SetAttribute("WallSide", wallSide)
	head:SetAttribute("WallSlot", wallSlot)
	head.Parent = rig

	-- Invisible target the beam chases; the choreography moves this
	local target = Instance.new("Part")
	target.Name = "Head" .. i .. "_Target"
	target.Size = Vector3.new(1, 1, 1)
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.Transparency = 1
	target.CFrame = CFrame.new(CENTER)
	target.Parent = rig

	local a0 = Instance.new("Attachment"); a0.Parent = head
	local a1 = Instance.new("Attachment"); a1.Parent = target

	-- The visible volumetric beam: a soft cone of light from lens to target
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = 0.7
	beam.Width1 = 4 -- cone spreads as it travels, like a real spotlight
	beam.CurveSize0 = 0
	beam.CurveSize1 = 0
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.7, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = head

	-- Real light cast onto whatever the beam hits
	local spot = Instance.new("SpotLight")
	spot.Angle = 18
	spot.Brightness = 2
	spot.Range = 170
	spot.Color = color
	spot.Face = Enum.NormalId.Front
	spot.Shadows = false -- 32 dynamic fixtures; avoid expensive per-light shadows
	spot.Parent = head

	-- Glowing pool where the beam lands on the floor
	local pool = Instance.new("Part")
	pool.Name = "Head" .. i .. "_Pool"
	pool.Shape = Enum.PartType.Cylinder
	pool.Size = Vector3.new(0.1, 4, 4)
	pool.Anchored = true
	pool.CanCollide = false
	pool.CanQuery = false
	pool.CanTouch = false
	pool.Material = Enum.Material.Neon
	pool.Color = color
	pool.Transparency = 0.45
	pool.CFrame = CFrame.new(CENTER + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	pool.Parent = rig
end

-- Four original fixtures on each wall, centered within equal-width side segments.
-- Keep those placements unchanged and interleave a supplemental set at the gaps.
-- This yields 8 fixtures per wall and 32 total.
local w = tx1 - tx0
local h = tz1 - tz0
local PER_WALL_PER_SET = ORIGINAL_HEADS / 4
local function placeWallFixture(index, slot, supplemental)
	local side = math.floor((index - 1) / PER_WALL_PER_SET)
	local wallSide = ({ "north", "east", "south", "west" })[side + 1]
	local px, pz
	if side == 0 then -- North wall: west to east
		px, pz = tx0 + w * slot, tz0
	elseif side == 1 then -- East wall: north to south
		px, pz = tx1, tz0 + h * slot
	elseif side == 2 then -- South wall: east to west
		px, pz = tx1 - w * slot, tz1
	else -- West wall: south to north
		px, pz = tx0, tz1 - h * slot
	end
	makeHead(index + (supplemental and ORIGINAL_HEADS or 0), { X = px, Z = pz }, wallSide, slot)
end

for i = 1, ORIGINAL_HEADS do
	local slot = ((i - 1) % PER_WALL_PER_SET + 0.5) / PER_WALL_PER_SET
	placeWallFixture(i, slot, false)
end

for i = 1, SUPPLEMENTAL_HEADS do
	local wallSlot = (i - 1) % PER_WALL_PER_SET
	-- Interleave between original fixture positions (quarter-slot offsets).
	local slot = (wallSlot + 0.25) / PER_WALL_PER_SET
	placeWallFixture(i, slot, true)
end

-- -----------------------------------------------------------
-- Strobe bars: rows of white flash cans on the truss that pop on drops
-- -----------------------------------------------------------
local function makeStrobeBar(name, x, z, faceCenter)
	local bar = Instance.new("Part")
	bar.Name = name .. "_Bar"
	bar.Size = Vector3.new(6, 0.6, 1)
	bar.Anchored = true
	bar.CanCollide = false
	bar.CanQuery = false
	bar.Material = Enum.Material.Metal
	bar.Color = Color3.fromRGB(35, 36, 40)
	local toC = (Vector3.new(CENTER.X, 0, CENTER.Z) - Vector3.new(x, 0, z)).Unit
	bar.CFrame = CFrame.new(x, TRUSS_Y - 1, z)
		* CFrame.Angles(0, math.atan2(toC.X, toC.Z), 0)
	bar.Parent = rig
	for c = 1, 6 do
		local cell = Instance.new("Part")
		cell.Name = name .. "_Cell" .. c
		cell.Size = Vector3.new(0.7, 0.7, 0.2)
		cell.Anchored = true
		cell.CanCollide = false
		cell.CanQuery = false
		cell.Material = Enum.Material.Neon
		cell.Color = Color3.new(1, 1, 1)
		cell.Transparency = 1
		cell.CFrame = bar.CFrame * CFrame.new(-2.5 + (c - 1), 0, -0.6)
		cell.Parent = rig
	end
end

makeStrobeBar("StrobeN", (tx0 + tx1) / 2, tz0 + 1, true)
makeStrobeBar("StrobeS", (tx0 + tx1) / 2, tz1 - 1, true)
makeStrobeBar("StrobeW", tx0 + 1, (tz0 + tz1) / 2, true)
makeStrobeBar("StrobeE", tx1 - 1, (tz0 + tz1) / 2, true)

-- Rig is built. The client script MovingHeadShowFX discovers
-- Workspace.MovingHeadRig and drives all beat-synced animation.