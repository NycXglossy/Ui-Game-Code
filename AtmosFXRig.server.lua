-- AtmosFXRig: server-owned atmospheric fixture provisioning.
-- The paired AtmosFX LocalScript owns client-local beat-reactive particle animation.
local Workspace = game:GetService("Workspace")

local FLOOR_NAME = "CeilingFX"
local RIG_NAME = "AtmosFXRig"
local FOG_COUNT = 4
local FLAME_COUNT = 8

local function floorBounds()
    local folder = Workspace:FindFirstChild(FLOOR_NAME)
    if not folder then return nil end
    local minX, maxX, minZ, maxZ, floorY = math.huge, -math.huge, math.huge, -math.huge, -math.huge
    local count = 0
    for _, part in ipairs(folder:GetChildren()) do
        if part:IsA("BasePart") and part.Name == "FloorPanel" then
            count += 1
            minX, maxX = math.min(minX, part.Position.X), math.max(maxX, part.Position.X)
            minZ, maxZ = math.min(minZ, part.Position.Z), math.max(maxZ, part.Position.Z)
            floorY = math.max(floorY, part.Position.Y)
        end
    end
    if count < 4 or maxX - minX < 40 or maxZ - minZ < 40 then return nil end
    return minX, maxX, minZ, maxZ, floorY, count
end

local minX, maxX, minZ, maxZ, floorY, panelCount
repeat
    minX, maxX, minZ, maxZ, floorY, panelCount = floorBounds()
    if not minX then task.wait(0.5) end
until minX

local insetX = math.min(12, (maxX - minX) * 0.12)
local insetZ = math.min(12, (maxZ - minZ) * 0.12)
minX, maxX, minZ, maxZ = minX + insetX, maxX - insetX, minZ + insetZ, maxZ - insetZ
local centerX, centerZ = (minX + maxX) * 0.5, (minZ + maxZ) * 0.5
local mountY = floorY + 0.35

local old = Workspace:FindFirstChild(RIG_NAME)
if old then old:Destroy() end
local rig = Instance.new("Model")
rig.Name = RIG_NAME
rig.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
rig:SetAttribute("ServerOwnedLayout", true)
rig:SetAttribute("Ready", false)
rig:SetAttribute("FloorPanelCount", panelCount)
rig:SetAttribute("FloorY", floorY)
rig:SetAttribute("VenueMinX", minX)
rig:SetAttribute("VenueMaxX", maxX)
rig:SetAttribute("VenueMinZ", minZ)
rig:SetAttribute("VenueMaxZ", maxZ)
rig.Parent = Workspace

local function makePart(name: string, position: Vector3, parent: Instance): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Size = Vector3.new(1.4, 0.7, 1.4)
    part.CFrame = CFrame.new(position)
    part.Anchored = true
    part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = false, false, false, false
    part.Material = Enum.Material.Metal
    part.Color = Color3.fromRGB(28, 30, 36)
    part.Parent = parent
    return part
end

local function makeNozzle(unit: Part): Attachment
    local nozzle = Instance.new("Attachment")
    nozzle.Name = "Nozzle"
    nozzle.Position = Vector3.new(0, 0.45, 0)
    nozzle.Parent = unit
    return nozzle
end

local function makeFog(index: number, position: Vector3)
    local unit = makePart(string.format("Fog%d", index), position, rig)
    unit:SetAttribute("FixtureType", "Fog")
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "Fog"
    emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
    emitter.Enabled = true
    emitter.Rate = 0
    emitter.Lifetime = NumberRange.new(2.8, 4.2)
    emitter.Speed = NumberRange.new(3, 6)
    emitter.SpreadAngle = Vector2.new(24, 24)
    emitter.Drag = 1.5
    emitter.Acceleration = Vector3.new(0, 1.2, 0)
    emitter.Rotation = NumberRange.new(0, 360)
    emitter.RotSpeed = NumberRange.new(-18, 18)
    emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(0.45, 7), NumberSequenceKeypoint.new(1, 10)})
    emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.48), NumberSequenceKeypoint.new(0.7, 0.62), NumberSequenceKeypoint.new(1, 1)})
    emitter.Color = ColorSequence.new(Color3.fromRGB(190, 205, 220), Color3.fromRGB(105, 120, 140))
    emitter.LightEmission = 0.08
    emitter.Parent = makeNozzle(unit)
end

local function makeFlame(index: number, position: Vector3)
    local unit = makePart(string.format("Flame%d", index), position, rig)
    unit:SetAttribute("FixtureType", "Flame")
    local nozzle = makeNozzle(unit)
    local fire = Instance.new("ParticleEmitter")
    fire.Name = "Fire"
    fire.Texture = "rbxasset://textures/particles/fire_main.dds"
    fire.Enabled = true
    fire.Rate = 0
    fire.Lifetime = NumberRange.new(0.35, 0.75)
    fire.Speed = NumberRange.new(13, 21)
    fire.SpreadAngle = Vector2.new(8, 8)
    fire.Acceleration = Vector3.new(0, 5, 0)
    fire.Drag = 0.8
    fire.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(0.35, 1.8), NumberSequenceKeypoint.new(1, 0.15)})
    fire.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.65, 0.22), NumberSequenceKeypoint.new(1, 1)})
    fire.Color = ColorSequence.new(Color3.fromRGB(255, 245, 170), Color3.fromRGB(255, 80, 18))
    fire.LightEmission = 0.85
    fire.Parent = nozzle

    local glow = Instance.new("PointLight")
    glow.Name = "Glow"
    glow.Color = Color3.fromRGB(255, 125, 42)
    glow.Range = 18
    glow.Brightness = 0
    glow.Shadows = false
    glow.Parent = unit
end

-- Foggers occupy the four corners; flame jets line both long sides.
local fogPositions = {
    Vector3.new(minX, mountY, minZ), Vector3.new(maxX, mountY, minZ),
    Vector3.new(maxX, mountY, maxZ), Vector3.new(minX, mountY, maxZ),
}
for index, position in ipairs(fogPositions) do makeFog(index, position) end
for index = 1, FLAME_COUNT do
    local t = (index - 0.5) / (FLAME_COUNT / 2)
    if index <= FLAME_COUNT / 2 then
        makeFlame(index, Vector3.new(minX + (maxX - minX) * t, mountY, minZ + 5))
    else
        makeFlame(index, Vector3.new(maxX - (maxX - minX) * (t - 1), mountY, maxZ - 5))
    end
end

rig:SetAttribute("FogCount", FOG_COUNT)
rig:SetAttribute("FlameCount", FLAME_COUNT)
rig:SetAttribute("Ready", true)
print("[ClubNeon][AtmosFXRig] Server-owned atmospheric fixtures ready; fog=" .. FOG_COUNT
    .. " flames=" .. FLAME_COUNT .. " floorPanels=" .. panelCount)
