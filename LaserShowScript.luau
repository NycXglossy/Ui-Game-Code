-- LaserShowScript (server half of the dual-script laser show):
-- builds the wall-mounted laser projector rig and the centerpiece orb
-- once at startup. The rig is server-authoritative and replicated to
-- every client. All beat-synced animation lives in the client half
-- (StarterPlayerScripts.LaserShowFX), which uses the same beat detector
-- as the rest of the club's lighting FX.

-- Measure the dance floor from the panel grid
local folder = workspace:FindFirstChild("CeilingFX")
if not folder then return end
local floorY = -math.huge
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
for _, p in folder:GetChildren() do
	if p:IsA("BasePart") then
		local pos = p.Position
		if pos.Y < 40 then floorY = math.max(floorY, pos.Y) end
		minX = math.min(minX, pos.X); maxX = math.max(maxX, pos.X)
		minZ = math.min(minZ, pos.Z); maxZ = math.max(maxZ, pos.Z)
	end
end
if floorY == -math.huge then return end

local CENTER = Vector3.new((minX + maxX) / 2, floorY, (minZ + maxZ) / 2)

local rig = Instance.new("Folder")
rig.Name = "LaserRig"
rig.Parent = workspace

local function mkPart(name, size, material, color, cframe)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = material
	p.Color = color
	p.CFrame = cframe
	p.Parent = rig
	return p
end

-- Wall rig: laser projectors mounted directly on the walls all the way
-- around the venue, hugging the rectangle perimeter so every wall is
-- lined with fixtures and the beams sweep the entire floor
local WALL_HEADS = 24
local INSET = 0.4
local wallMinX, wallMaxX = minX + INSET, maxX - INSET
local wallMinZ, wallMaxZ = minZ + INSET, maxZ - INSET
local wallW = wallMaxX - wallMinX
local wallH = wallMaxZ - wallMinZ
local perimTotal = 2 * (wallW + wallH)

-- Walk the wall perimeter: t in [0,1) returns a point on the walls
local function wallPoint(t)
	local d = (t % 1) * perimTotal
	if d < wallW then
		return Vector3.new(wallMinX + d, 0, wallMinZ)
	elseif d < wallW + wallH then
		return Vector3.new(wallMaxX, 0, wallMinZ + (d - wallW))
	elseif d < 2 * wallW + wallH then
		return Vector3.new(wallMaxX - (d - wallW - wallH), 0, wallMaxZ)
	else
		return Vector3.new(wallMinX, 0, wallMaxZ - (d - 2 * wallW - wallH))
	end
end

-- Laser projector: a compact cannon pod bolted to the wall. Styled like
-- the venue's fixtures (black metal mount + neon lens), but a distinct
-- fixture type from the truss-hung moving heads: flat pods that fire fan
-- beams rather than panning spotlights.
local mountHeights = {37, 50, 62, 44, 56}
for i = 1, WALL_HEADS do
	local t = (i - 0.5) / WALL_HEADS
	local wp = wallPoint(t)
	local h = mountHeights[(i - 1) % #mountHeights + 1]
	local flat = Vector3.new(wp.X, 0, wp.Z)
	local toCenter = Vector3.new(CENTER.X, 0, CENTER.Z) - flat
	if toCenter.Magnitude > 0.01 then
		local dir = toCenter.Unit
		local color = Color3.fromHSV(i / WALL_HEADS, 1, 1)

		-- Mount plate flush against the wall
		local mountPos = wp + dir * 0.15 + Vector3.new(0, h, 0)
		mkPart("Laser" .. i .. "_Mount", Vector3.new(1.6, 1.2, 0.3),
			Enum.Material.Metal, Color3.fromRGB(40, 40, 45),
			CFrame.lookAt(mountPos, mountPos + dir))

		-- Housing: dark metal projector body sticking out from the wall
		local housingPos = wp + dir * 0.95 + Vector3.new(0, h, 0)
		mkPart("Laser" .. i .. "_Housing", Vector3.new(0.9, 0.7, 1.3),
			Enum.Material.Metal, Color3.fromRGB(35, 36, 40),
			CFrame.lookAt(housingPos, housingPos + dir))

		-- Lens: neon emitter at the front of the housing
		local lensPos = wp + dir * 1.65 + Vector3.new(0, h, 0)
		local lens = mkPart("Laser" .. i .. "_Lens", Vector3.new(0.75, 0.4, 0.75),
			Enum.Material.Neon, color,
			CFrame.lookAt(lensPos, lensPos + dir))

		-- Invisible target the beam fan chases; the choreography moves this
		local target = mkPart("Laser" .. i .. "_Target", Vector3.new(1, 1, 1),
			Enum.Material.SmoothPlastic, color,
			CFrame.new(lensPos - Vector3.new(0, 2.5, 0)))
		target.Transparency = 1

		-- Glowing neon pool where the beams land on the floor
		local pool = mkPart("Laser" .. i .. "_Pool", Vector3.new(0.1, 3, 3),
			Enum.Material.Neon, color,
			CFrame.new(target.Position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2))
		pool.Transparency = 0.35

		-- Fan of five beams per head: the center beam is straight, the side
		-- beams bow outward via CurveSize for a wide sweeping laser fan effect
		local a0 = Instance.new("Attachment"); a0.Parent = lens
		local a1 = Instance.new("Attachment"); a1.Parent = target
		for b = 1, 5 do
			local beam = Instance.new("Beam")
			beam.Name = "Beam" .. b
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.FaceCamera = true
			beam.Width0 = 0.1
			beam.Width1 = 1.1 - (b - 1) * 0.14
			beam.CurveSize0 = (b - 3) * 2.75
			beam.CurveSize1 = (b - 3) * -1
			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.08),
				NumberSequenceKeypoint.new(0.6, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			})
			beam.Color = ColorSequence.new(color)
			beam.Parent = lens
		end

		local spot = Instance.new("SpotLight")
		spot.Name = "Spot"
		spot.Angle = 25
		spot.Brightness = 2
		spot.Range = 30
		spot.Color = color
		spot.Face = Enum.NormalId.Bottom
		spot.Shadows = true
		spot.Parent = lens
	end
end

-- Centerpiece: a glowing orb with spinning rings above the floor center
local orb = mkPart("CenterOrb", Vector3.new(3.5, 3.5, 3.5),
	Enum.Material.Neon, Color3.fromHSV(0, 1, 1),
	CFrame.new(CENTER + Vector3.new(0, 25, 0)))
orb.Shape = Enum.PartType.Ball
local orbLight = Instance.new("PointLight")
orbLight.Name = "Glow"
orbLight.Brightness = 3
orbLight.Range = 50
orbLight.Color = orb.Color
orbLight.Parent = orb

for i = 1, 3 do
	local ring = mkPart("OrbRing" .. i, Vector3.new(0.4, 5.5 + i * 1.5, 5.5 + i * 1.5),
		Enum.Material.Neon, orb.Color,
		orb.CFrame * CFrame.Angles(0, i * math.pi / 3, i * 0.6))
	ring.Shape = Enum.PartType.Cylinder
end

-- Rig is built. The client script LaserShowFX discovers
-- Workspace.LaserRig and drives all beat-synced animation.