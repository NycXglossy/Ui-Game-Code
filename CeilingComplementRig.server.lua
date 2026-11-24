-- CeilingComplementRig: server-owned ceiling profile, wash and LED PAR fixtures.
-- The paired client script performs local pan/tilt and beat-synced light animation.
local Workspace = game:GetService("Workspace")

local FLOOR_NAME = "CeilingFX"
local RIG_NAME = "CeilingComplementRig"
local function floorBounds()
    local folder = Workspace:FindFirstChild(FLOOR_NAME)
    if not folder then return nil end
    local x0, x1, z0, z1, y = math.huge, -math.huge, math.huge, -math.huge, -math.huge
    local count = 0
    for _, p in ipairs(folder:GetChildren()) do
        if p:IsA("BasePart") and p.Name == "FloorPanel" then
            count += 1
            x0, x1 = math.min(x0, p.Position.X), math.max(x1, p.Position.X)
            z0, z1 = math.min(z0, p.Position.Z), math.max(z1, p.Position.Z)
            y = math.max(y, p.Position.Y)
        end
    end
    if count < 4 or x1 - x0 < 40 or z1 - z0 < 40 then return nil end
    return x0, x1, z0, z1, y, count
end
local x0, x1, z0, z1, floorY, panelCount
repeat
    x0, x1, z0, z1, floorY, panelCount = floorBounds()
    if not x0 then task.wait(0.5) end
until x0

-- Match the existing moving-head/strobe venue footprint when wall trim is present.
local vx0, vx1, vz0, vz1 = x0, x1, z0, z1
local usedTrim = false
for _, item in ipairs(Workspace:GetDescendants()) do
    if item:IsA("BasePart") and (item.Name == "TrimH" or item.Name == "TrimV")
        and math.max(item.Size.X, item.Size.Z) >= 300 then
        usedTrim = true
        for _, ux in ipairs({-0.5, 0.5}) do
            for _, uz in ipairs({-0.5, 0.5}) do
                local p = item.CFrame * Vector3.new(item.Size.X * ux, 0, item.Size.Z * uz)
                vx0, vx1 = math.min(vx0, p.X), math.max(vx1, p.X)
                vz0, vz1 = math.min(vz0, p.Z), math.max(vz1, p.Z)
            end
        end
    end
end
local center = Vector3.new((vx0 + vx1) * 0.5, floorY, (vz0 + vz1) * 0.5)
local ceilingRay = Workspace:Raycast(center, Vector3.new(0, 500, 0))
local ceilingY = ceilingRay and ceilingRay.Position.Y or floorY + 60
local mountY = math.max(floorY + 12, ceilingY - 5)
local inset = usedTrim and 10 or 5
vx0, vx1, vz0, vz1 = vx0 + inset, vx1 - inset, vz0 + inset, vz1 - inset
if vx1 - vx0 < 40 or vz1 - vz0 < 40 then
    warn("[ClubNeon][CeilingComplementRig] Venue bounds too small; no fixtures created.")
    return
end

local old = Workspace:FindFirstChild(RIG_NAME)
if old then old:Destroy() end
local rig = Instance.new("Model")
rig.Name = RIG_NAME
rig.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
rig:SetAttribute("ServerOwnedLayout", true)
rig:SetAttribute("Ready", false)
rig:SetAttribute("FloorPanelCount", panelCount)
rig:SetAttribute("UsedVenueTrimBounds", usedTrim)
rig.Parent = Workspace

local function makePart(name, size, cf, parent, material, color)
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame = name, size, cf
    p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
    p.Material, p.Color = material or Enum.Material.Metal, color or Color3.fromRGB(32, 34, 40)
    p.Parent = parent
    return p
end
local profileCount, washCount, parCount = 0, 0, 0
local walls = {
    function(t) return Vector3.new(vx0 + (vx1-vx0)*t, mountY, vz0), Vector3.new(center.X, floorY, center.Z) end,
    function(t) return Vector3.new(vx1, mountY, vz0 + (vz1-vz0)*t), Vector3.new(center.X, floorY, center.Z) end,
    function(t) return Vector3.new(vx1 - (vx1-vx0)*t, mountY, vz1), Vector3.new(center.X, floorY, center.Z) end,
    function(t) return Vector3.new(vx0, mountY, vz1 - (vz1-vz0)*t), Vector3.new(center.X, floorY, center.Z) end,
}
local function makeProfile(index, pos, targetPos)
    profileCount += 1
    local model = Instance.new("Model")
    model.Name = string.format("Profile%02d", index)
    model:SetAttribute("FixtureType", "Profile")
    model:SetAttribute("FixtureIndex", index)
    model.Parent = rig
    makePart("Yoke", Vector3.new(0.7, 1.1, 0.7), CFrame.new(pos + Vector3.new(0,-0.65,0)), model)
    local head = makePart("Emitter", Vector3.new(1.1, 1.4, 1.1), CFrame.lookAt(pos + Vector3.new(0,-1.5,0), targetPos), model)
    head.Material = Enum.Material.Metal
    local lens = makePart("Lens", Vector3.new(0.72,0.08,0.08), head.CFrame * CFrame.new(0,0,-0.56), model, Enum.Material.Neon, Color3.new(1,1,1))
    local target = makePart("Target", Vector3.new(0.2,0.2,0.2), CFrame.new(targetPos), model)
    target.Transparency = 1
    local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
    a0.Parent, a1.Parent = lens, target
    local beam = Instance.new("Beam")
    beam.Name, beam.Attachment0, beam.Attachment1 = "ProfileBeam", a0, a1
    beam.LightEmission, beam.LightInfluence, beam.FaceCamera = 1, 0, true
    beam.Width0, beam.Width1, beam.Segments = 0.28, 2.2, 1
    beam.Color = ColorSequence.new(Color3.fromRGB(220,235,255))
    beam.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.35),NumberSequenceKeypoint.new(1,1)})
    beam.Parent = lens
    local spot = Instance.new("SpotLight")
    spot.Name, spot.Face, spot.Angle, spot.Range = "ProfileSpot", Enum.NormalId.Front, 12, 180
    spot.Brightness, spot.Shadows, spot.Enabled = 0, false, false
    spot.Parent = lens
end
local function makeWash(index, pos, targetPos)
    washCount += 1
    local model = Instance.new("Model")
    model.Name = string.format("Wash%02d", index)
    model:SetAttribute("FixtureType", "Wash")
    model:SetAttribute("FixtureIndex", index)
    model.Parent = rig
    local body = makePart("Housing", Vector3.new(2.2,0.8,1.2), CFrame.lookAt(pos, targetPos), model)
    local lens = makePart("Lens", Vector3.new(1.8,0.12,0.12), body.CFrame * CFrame.new(0,0,-0.62), model, Enum.Material.Neon)
    local light = Instance.new("SpotLight")
    light.Name, light.Face, light.Angle, light.Range = "WashLight", Enum.NormalId.Front, 100, 150
    light.Brightness, light.Shadows, light.Enabled = 0, false, false
    light.Parent = lens
end
local function makePar(index, pos, targetPos)
    parCount += 1
    local model = Instance.new("Model")
    model.Name = string.format("LEDPar%02d", index)
    model:SetAttribute("FixtureType", "LEDPar")
    model:SetAttribute("FixtureIndex", index)
    model.Parent = rig
    local body = makePart("Can", Vector3.new(1.15,1.15,1.15), CFrame.lookAt(pos,targetPos), model)
    local lens = makePart("Lens", Vector3.new(0.82,0.1,0.1), body.CFrame * CFrame.new(0,0,-0.58), model, Enum.Material.Neon)
    local light = Instance.new("SpotLight")
    light.Name, light.Face, light.Angle, light.Range = "ParLight", Enum.NormalId.Front, 72, 110
    light.Brightness, light.Shadows, light.Enabled = 0, false, false
    light.Parent = lens
end
-- Four pan/tilt profiles per wall, three broad washes per wall, four PARs per wall.
for wallIndex, pointOnWall in ipairs(walls) do
    for slot = 1, 4 do
        local pos, target = pointOnWall((slot - 0.5) / 4)
        makeProfile((wallIndex-1)*4+slot, pos, target)
    end
    for slot = 1, 3 do
        local pos, target = pointOnWall((slot - 0.5) / 3)
        makeWash((wallIndex-1)*3+slot, pos + Vector3.new(0,-0.6,0), target)
    end
    for slot = 1, 4 do
        local pos, target = pointOnWall((slot - 0.5) / 4)
        makePar((wallIndex-1)*4+slot, pos + Vector3.new(0,-1.2,0), target)
    end
end
rig:SetAttribute("ProfileCount", profileCount)
rig:SetAttribute("WashCount", washCount)
rig:SetAttribute("LEDParCount", parCount)
rig:SetAttribute("Ready", true)
print("[ClubNeon][CeilingComplementRig] Server-owned ceiling fixtures ready; profiles=" .. profileCount
    .. " washes=" .. washCount .. " ledPars=" .. parCount .. " floorPanels=" .. panelCount
    .. " trimBounds=" .. tostring(usedTrim))
