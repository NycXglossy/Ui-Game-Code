-- FXWatchdogClient: guarantees the club's visualizers never stay dead.
-- Every few seconds it verifies each FX LocalScript exists in PlayerScripts
-- and that its animation is actually moving (probes live parts fresh each
-- check, so stale references after streaming are caught too). If a script
-- is missing or frozen while the music plays, it is destroyed and re-cloned
-- from StarterPlayerScripts so the show restarts itself -- no matter what
-- killed it (an error, streaming, replication races, anything).

local Players = game:GetService("Players")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

local WATCH_INTERVAL = 8 -- seconds between checks
local SAMPLE_GAP = 2.5 -- seconds between the two animation samples

-- All client FX rigs, watched for existence; rigs with a motion probe
-- are also watched for frozen animation.
local FX_NAMES = {
	"WallVisualizerClient",
	"CeilingPillarFX",
	"StrobeLightsFX",
	"SpeakerEffects",
	"AtmosFX",
	"AudienceBlinderFX",
	"HazeBeamFX",
	"KineticCenterpieceFX",
	"BeatImpactFX",
	"MovingHeadShowFX",
	"LaserShowFX",
	"CeilingComplementFX",
	"DJStageLEDBarFX",
	"ArchitecturalAccentFX",
	"PixelMatrixFX",
	"GlowFloorFXScript",
	"SpeakerEffects",
	"NeonSignFX",
	"NeonTrimEffects",
	"BarNeonScript",
	"LightshowFX",
}

local player = Players.LocalPlayer

-- PlayerScripts may not exist for a moment on join; wait for it politely.
local playerScripts = player:FindFirstChild("PlayerScripts")
while not playerScripts do
	task.wait(0.5)
	playerScripts = player:FindFirstChild("PlayerScripts")
end

local starterScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")

local function restartScript(name)
	local existing = playerScripts:FindFirstChild(name)
	if existing then
		existing.Parent = nil
		existing:Destroy()
	end
	if starterScripts then
		local template = starterScripts:FindFirstChild(name)
		if template then
			local clone = template:Clone()
			clone.Parent = playerScripts
			return true
		end
	end
	return false
end

-- Motion probes: find a live part FRESH each check (never cache references)
-- and return a signature that changes every frame while the rig animates.
-- Returns nil when the rig is not measurable (not streamed in yet).

local function wallSignature()
	local vis = workspace:FindFirstChild("WallVisualizer")
	if not vis then return nil end
	for _, wf in vis:GetChildren() do
		local b1 = wf:FindFirstChild("B1")
		local b20 = wf:FindFirstChild("B20")
		if b1 and b20 then
			return b1.Size.Y + b20.Size.Y * 7 + b1.Color.R + b20.Color.B * 3
		end
	end
	return nil
end

local function pillarSignature()
	local model = workspace:FindFirstChild("CeilingPillars")
	if not model then return nil end
	local fixture = model:GetChildren()[1]
	if not fixture then return nil end
	local shaft = fixture:FindFirstChild("Shaft")
	local tip = fixture:FindFirstChild("Tip")
	if shaft and tip then
		return shaft.Size.Y + shaft.Transparency * 10 + tip.Color.R * 5 + tip.Color.G
	end
	return nil
end

local function strobeSignature()
	local model = workspace:FindFirstChild("StrobeLights")
	if not model then return nil end
	local panel = model:GetChildren()[1]
	if not panel then return nil end
	local light = panel:FindFirstChild("Flash")
	if light then
		return light.Brightness * 13 + light.Color.R + light.Color.G * 3
	end
	return nil
end

local function movingHeadSignature()
	local rig = workspace:FindFirstChild("MovingHeadRig")
	if not rig then return nil end
	local target = rig:FindFirstChild("Head1_Target")
	local lens = rig:FindFirstChild("Head1_Lens")
	if target and lens then
		local p, c = target.Position, lens.CFrame.LookVector
		return p.X + p.Y * 3 + p.Z * 7 + c.X * 11 + c.Y * 13 + c.Z * 17
	end
	return nil
end

local function laserSignature()
	local rig = workspace:FindFirstChild("LaserRig")
	if not rig then return nil end
	local target = rig:FindFirstChild("Laser1_Target")
	if target then
		local p = target.Position
		return p.X + p.Y * 3 + p.Z * 7
	end
	return nil
end

local function ceilingComplementSignature()
	local rig = workspace:FindFirstChild("CeilingComplementRig")
	if not rig or rig:GetAttribute("Ready") ~= true then return nil end
	local fixture = rig:FindFirstChild("Profile01")
	local target = fixture and fixture:FindFirstChild("Target")
	local emitter = fixture and fixture:FindFirstChild("Emitter")
	if target and emitter then
		local p, look = target.Position, emitter.CFrame.LookVector
		return p.X + p.Y * 3 + p.Z * 7 + look.X * 11 + look.Y * 13 + look.Z * 17
	end
	return nil
end

local function ledBarSignature()
	local rig = workspace:FindFirstChild("DJStageLEDBarRig")
	if not rig or rig:GetAttribute("Ready") ~= true then return nil end
	local segment = rig:FindFirstChildWhichIsA("BasePart", true)
	if segment then
		local color = segment.Color
		return color.R + color.G * 3 + color.B * 7 + segment.Transparency * 11
	end
	return nil
end


local function atmosSignature()
	local rig = workspace:FindFirstChild("AtmosFXRig")
	if not rig or rig:GetAttribute("Ready") ~= true then return nil end
	local flame = rig:FindFirstChild("Flame1")
	local nozzle = flame and flame:FindFirstChild("Nozzle")
	local emitter = nozzle and nozzle:FindFirstChild("Fire")
	if emitter and emitter:IsA("ParticleEmitter") then
		local glow = flame:FindFirstChild("Glow")
		local brightness = if glow and glow:IsA("PointLight") then glow.Brightness else 0
		return emitter.Rate + brightness * 3
	end
	return nil
end

local function audienceBlinderSignature()
	local rig = workspace:FindFirstChild("AudienceBlinderRig")
	if not rig or rig:GetAttribute("Ready") ~= true then return nil end
	local fixture = rig:FindFirstChild("Blinder1")
	local light = fixture and fixture:FindFirstChild("AudienceWash")
	if light and light:IsA("SpotLight") then
		return light.Brightness + light.Color.R * 3 + light.Color.G * 7 + light.Color.B * 11
	end
	return nil
end

local function hazeSignature()
	local rig = workspace:FindFirstChild("StageHazeRig")
	if not rig or rig:GetAttribute("Ready") ~= true then return nil end
	local emitter = rig:FindFirstChild("SoftStageHaze", true)
	if emitter and emitter:IsA("ParticleEmitter") then return emitter.Rate + (emitter.Enabled and 1 or 0) end
	return nil
end

local function pixelMatrixSignature()
	local rig = workspace:FindFirstChild("CeilingFX")
	if not rig then return nil end
	local panel = rig:FindFirstChild("FloorPanel")
	if panel and panel:IsA("BasePart") then
		local color = panel.Color
		return color.R + color.G * 3 + color.B * 7
	end
	return nil
end

local function glowFloorSignature()
	local rig = workspace:FindFirstChild("GlowFloorFX")
	if not rig then return nil end
	for _, part in ipairs(rig:GetChildren()) do
		if part:IsA("BasePart") and part.Name:match("^Strip_") then
			local color = part.Color
			return color.R + color.G * 3 + color.B * 7
		end
	end
	return nil
end

local function speakerSignature()
	for _, part in ipairs(workspace:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == "SpeakerGlow" then
			local light = part:FindFirstChildOfClass("PointLight")
			if light then return light.Brightness + light.Color.R * 3 + light.Color.G * 7 end
		end
	end
	return nil
end

local function accentSignature()
	for _, part in ipairs(workspace:GetDescendants()) do
		if part:IsA("BasePart") and part:GetAttribute("ClubNeonAccentEnabled") == true then
			local color = part.Color
			return color.R + color.G * 3 + color.B * 7
		end
	end
	return nil
end

local function signSignature()
	local sign = workspace:FindFirstChild("ClubNeonSign")
	local backing = sign and sign:FindFirstChild("Backing")
	local light = backing and backing:FindFirstChildOfClass("PointLight")
	if light then return light.Brightness + light.Color.R * 3 + light.Color.G * 7 end
	return nil
end

local function trimSignature()
	local folder = workspace:FindFirstChild("NeonTrim")
	if not folder then return nil end
	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "TrimLightAnchor" then
			local color = part.Color
			return color.R + color.G * 3 + color.B * 7
		end
	end
	return nil
end

local function barNeonSignature()
	local folder = workspace:FindFirstChild("NeonBar")
	if not folder then return nil end
	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart") and part.Name == "BarNeon" then
			local color = part.Color
			return color.R + color.G * 3 + color.B * 7
		end
	end
	return nil
end

local function lightshowSignature()
	local folder = workspace:FindFirstChild("LightshowRigs")
	if not folder then return nil end
	for _, rig in ipairs(folder:GetChildren()) do
		for _, part in ipairs(rig:GetChildren()) do
			if part:IsA("BasePart") and part.Name:match("^Segment%d+") then
				local color = part.Color
				return color.R + color.G * 3 + color.B * 7
			end
		end
	end
	return nil
end

local PROBES = {
	MovingHeadShowFX = movingHeadSignature,
	LaserShowFX = laserSignature,
	WallVisualizerClient = wallSignature,
	CeilingPillarFX = pillarSignature,
	StrobeLightsFX = strobeSignature,
	CeilingComplementFX = ceilingComplementSignature,
	DJStageLEDBarFX = ledBarSignature,
	AtmosFX = atmosSignature,
	AudienceBlinderFX = audienceBlinderSignature,
	HazeBeamFX = hazeSignature,
	PixelMatrixFX = pixelMatrixSignature,
	GlowFloorFXScript = glowFloorSignature,
	SpeakerEffects = speakerSignature,
	ArchitecturalAccentFX = accentSignature,
	NeonSignFX = signSignature,
	NeonTrimEffects = trimSignature,
	BarNeonScript = barNeonSignature,
	LightshowFX = lightshowSignature,
}

-- Is the club's music currently playing? Only treat frozen rigs as dead
-- when music is playing (between tracks the rigs legitimately rest).
-- The music comes from the ClubMusic AudioPlayer backend, so ask the
-- shared ClubAudioSync module instead of scanning for a legacy Sound.
local function musicPlaying()
	return ClubAudioSync.getBeatState().playing
end

local strikes = {}

while true do
	task.wait(WATCH_INTERVAL)

	-- 1) Existence: any FX script missing from PlayerScripts gets re-cloned.
	for _, name in FX_NAMES do
		if not playerScripts:FindFirstChild(name) then
			restartScript(name)
		end
	end

	-- 2) Motion: sample each probed rig twice; if the signature does not
	-- change at all while the music plays, count a strike. Three strikes in
	-- a row (>= 30s frozen) restarts the script so the show comes back.
	do
		-- Moving heads and lasers animate during idle as well as playback.
		for name, probe in PROBES do
			local sig1 = probe()
			if sig1 then
				task.wait(SAMPLE_GAP)
				local sig2 = probe()
				if sig2 and math.abs(sig2 - sig1) < 1e-6 and (musicPlaying() or name == "MovingHeadShowFX" or name == "LaserShowFX") then
					strikes[name] = (strikes[name] or 0) + 1
					if strikes[name] >= 3 then
						strikes[name] = 0
						restartScript(name)
					end
				else
					strikes[name] = 0
				end
			else
				strikes[name] = 0 -- nil means absent/not streamed, not frozen
			end
		end
	end
end