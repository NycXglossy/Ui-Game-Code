-- CeilingComplementFX: client-local pan/tilt profile choreography and wash/PAR color animation.
local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))
local RIG_NAME = "CeilingComplementRig"
local function waitForRig()
    while true do
        local rig = workspace:FindFirstChild(RIG_NAME)
        if rig then
            while rig.Parent and rig:GetAttribute("Ready") ~= true do task.wait(0.1) end
            if rig.Parent and rig:GetAttribute("Ready") == true then return rig end
        end
        task.wait(0.5)
    end
end
local rig = waitForRig()
local function collect()
    local profiles, washes, pars = {}, {}, {}
    for _, model in ipairs(rig:GetChildren()) do
        if model:IsA("Model") then
            local kind = model:GetAttribute("FixtureType")
            local index = model:GetAttribute("FixtureIndex") or 0
            if kind == "Profile" then
                local emitter, target = model:FindFirstChild("Emitter"), model:FindFirstChild("Target")
                local lens = model:FindFirstChild("Lens")
                local beam = lens and lens:FindFirstChild("ProfileBeam")
                local spot = lens and lens:FindFirstChild("ProfileSpot")
                if emitter and target and lens and beam and spot then
                    table.insert(profiles,{index=index,emitter=emitter,target=target,lens=lens,beam=beam,spot=spot,phase=index*1.713})
                end
            elseif kind == "Wash" then
                local lens = model:FindFirstChild("Lens")
                local light = lens and lens:FindFirstChild("WashLight")
                if lens and light then table.insert(washes,{index=index,lens=lens,light=light,phase=index*0.91}) end
            elseif kind == "LEDPar" then
                local lens = model:FindFirstChild("Lens")
                local light = lens and lens:FindFirstChild("ParLight")
                if lens and light then table.insert(pars,{index=index,lens=lens,light=light,phase=index*1.37}) end
            end
        end
    end
    table.sort(profiles,function(a,b) return a.index<b.index end)
    table.sort(washes,function(a,b) return a.index<b.index end)
    table.sort(pars,function(a,b) return a.index<b.index end)
    return profiles,washes,pars
end
local profiles,washes,pars = collect()
while #profiles == 0 or #washes == 0 or #pars == 0 do
    task.wait(0.5)
    rig = workspace:FindFirstChild(RIG_NAME) or rig
    profiles,washes,pars = collect()
end
print("[ClubNeon][CeilingComplementFX] Client animation ready; profiles=" .. #profiles
    .. " washes=" .. #washes .. " ledPars=" .. #pars)
local started = os.clock()
local function readRigBounds()
    return rig:GetAttribute("VenueMinX"), rig:GetAttribute("VenueMaxX"), rig:GetAttribute("VenueMinZ"), rig:GetAttribute("VenueMaxZ"), rig:GetAttribute("FloorY")
end
local lastBeat = -1
local hueBase = 0
local frameAccumulator = 0
local UPDATE_INTERVAL = 1 / 30
local lastPhrase = -1
local phrasePattern = 1
RunService.Heartbeat:Connect(function(dt)
    frameAccumulator += math.min(dt, 0.1)
    if frameAccumulator < UPDATE_INTERVAL then return end
    frameAccumulator %= UPDATE_INTERVAL
    if not rig or not rig.Parent then
        rig = workspace:FindFirstChild(RIG_NAME)
        if not rig then return end
        profiles,washes,pars = collect()
        return
    end
    local beat = ClubAudioSync.getBeatState()
    local now = os.clock()
    if beat.beatCount ~= lastBeat then
        lastBeat = beat.beatCount
        hueBase = (beat.beatCount * 0.037) % 1
    end
    local bpm = math.clamp(beat.bpm or 120,60,200)
    local energy = math.clamp(beat.energy or 0,0,1)
    local t = now - started
    local phrase = math.floor((beat.beatCount or 0) / 16)
    if phrase ~= lastPhrase then
        lastPhrase = phrase
        phrasePattern = (phrase % 4) + 1
    end
    local minX,maxX,minZ,maxZ,floorY = readRigBounds()
    if type(minX) ~= "number" or type(maxX) ~= "number" or type(minZ) ~= "number"
        or type(maxZ) ~= "number" or type(floorY) ~= "number" then return end
    for _, f in ipairs(profiles) do
        if not f.emitter.Parent or not f.target.Parent then continue end
        -- Independent crossed elliptical sweeps keep the profile layer distinct from moving heads.
        local rate = 0.16 + bpm/600 + energy*0.12
        local phase = t*rate + f.phase
        local x, z
        if phrasePattern == 1 then
            x = math.sin(phase) * 0.39 + math.sin(phase * 0.43 + f.phase) * 0.12
            z = math.cos(phase * 0.71 + f.phase) * 0.39
        elseif phrasePattern == 2 then
            x = math.sin(phase * 0.72 + f.phase) * 0.42
            z = math.sin(phase * 0.72 + f.phase + math.pi * 0.5) * 0.42
        elseif phrasePattern == 3 then
            x = math.sin(phase * 1.15 + f.phase) * 0.34
            z = math.sin(phase * 0.58 - f.phase) * 0.46
        else
            local side = if f.index % 2 == 0 then 1 else -1
            x = math.sin(phase * 0.82 + f.phase) * 0.44
            z = math.cos(phase * 0.82 + f.phase) * 0.30 * side
        end
        local pos = f.emitter.Position
        local target = Vector3.new(
            math.clamp(pos.X + x*150,minX+1,maxX-1),
            floorY + 1,
            math.clamp(pos.Z + z*150,minZ+1,maxZ-1)
        )
        f.target.CFrame = CFrame.new(target)
        f.emitter.CFrame = CFrame.lookAt(pos,target)
        f.lens.CFrame = f.emitter.CFrame * CFrame.new(0,0,-0.56)
        local hue = (hueBase + f.phase*0.025 + math.sin(phase*0.3)*0.035) % 1
        local color = Color3.fromHSV(hue,0.72,1)
        f.lens.Color, f.beam.Color, f.spot.Color = color,ColorSequence.new(color),color
        f.spot.Brightness = 1.5 + energy*2.5
        f.spot.Enabled = true
        f.beam.Enabled = energy > 0.04
    end
    for _, f in ipairs(washes) do
        if not f.lens.Parent then continue end
        local pulse = 0.58 + 0.22*math.sin(t*0.42+f.phase) + energy*0.2
        local hue = (hueBase + 0.18 + f.phase*0.018) % 1
        local color = Color3.fromHSV(hue,0.48,1)
        f.lens.Color, f.light.Color = color,color
        f.light.Brightness = math.clamp(pulse,0.15,1)*2.4
        f.light.Enabled = true
    end
    for _, f in ipairs(pars) do
        if not f.lens.Parent then continue end
        local chase = (beat.beatCount*0.12 + f.index/#pars) % 1
        local hue = (hueBase + chase*0.32 + f.phase*0.012) % 1
        local color = Color3.fromHSV(hue,0.95,1)
        local pulse = 0.35 + energy*0.65
        f.lens.Color, f.light.Color = color,color
        f.light.Brightness = pulse*1.8
        f.light.Enabled = true
    end
end)
