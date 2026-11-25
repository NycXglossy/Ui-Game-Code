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

local PROBES = {
	MovingHeadShowFX = movingHeadSignature,
	LaserShowFX = laserSignature,
	WallVisualizerClient = wallSignature,
	CeilingPillarFX = pillarSignature,
	StrobeLightsFX = strobeSignature,
	CeilingComplementFX = ceilingComplementSignature,
	DJStageLEDBarFX = ledBarSignature,
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