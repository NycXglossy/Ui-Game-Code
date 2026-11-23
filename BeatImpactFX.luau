-- BeatImpactFX: makes players FEEL the beat. On every kick the camera
-- punches in (FOV), the view shakes, bloom flares, and colors saturate.
-- Effect strength scales with proximity to the dance floor so it hits
-- hardest in the crowd and fades by the front door. Uses the shared
-- ClubAudioSync beat clock so everything hits together.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

local player = Players.LocalPlayer
local camera: Camera? = nil
local baseFOV = 70
local trackedHumanoid: Humanoid? = nil
local baseCameraOffset = Vector3.zero

-- Tunables
local BASE_FOV = 70
local MAX_FOV_PUNCH = 5 -- extra FOV degrees at full beat power
local SHAKE_POWER = 0.35 -- max humanoid camera offset magnitude
local FLOOR_CENTER = Vector3.new(458, 0, -110)
local FULL_EFFECT_DIST = 150 -- full intensity inside this radius
local FADE_OUT_DIST = 320 -- no effect beyond this radius

-- Post-processing stack (created here so the base game stays untouched)
local bloom = Instance.new("BloomEffect")
bloom.Name = "BeatBloom"
bloom.Intensity = 0.4
bloom.Size = 32
bloom.Threshold = 1.05
bloom.Parent = Lighting

local colorFx = Instance.new("ColorCorrectionEffect")
colorFx.Name = "BeatColor"
colorFx.Parent = Lighting

-- Beat state (driven by ClubAudioSync's beat clock)
local lastBeatCount = -1
local beatAge = math.huge
local beatPower = 0

-- Impact state
local fovPunch = 0
local shake = Vector3.zero

local clock = os.clock
local lastT = clock()

local heartbeatConnection = RunService.Heartbeat:Connect(function()
	local currentCamera = workspace.CurrentCamera
	if currentCamera ~= camera then
		camera = currentCamera
		if camera then baseFOV = camera.FieldOfView end
	end
	local now = clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now
	beatAge += dt

	-- Beat clock from the shared ClubAudioSync module
	local beat = ClubAudioSync.getBeatState()
	local tempoScale = beat.bpm / 128
	if beat.beatCount ~= lastBeatCount then
		lastBeatCount = beat.beatCount
		beatAge = 0
		beatPower = math.clamp(0.8 + beat.energy * 1.6, 0.5, 3)
		-- Kick: punch the FOV and kick off a shake
		fovPunch = math.min(fovPunch + beatPower * MAX_FOV_PUNCH * 0.6, MAX_FOV_PUNCH)
		shake = Vector3.new(
			(math.random() - 0.5),
			(math.random() - 0.5),
			(math.random() - 0.5)
		) * SHAKE_POWER * beatPower * 0.5
	else
		beatAge = beat.beatPhase * (60 / beat.bpm)
	end
	beatPower *= math.max(0, 1 - dt * 2)

	-- Proximity: full effect on the dance floor, fading with distance
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local effectScale = 0
	if hrp then
		local dist = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - FLOOR_CENTER).Magnitude
		effectScale = 1 - math.clamp((dist - FULL_EFFECT_DIST) / (FADE_OUT_DIST - FULL_EFFECT_DIST), 0, 1)
	end

	-- Master switch: players can turn the immersion off from the phone Settings app
	local fxOn = player:GetAttribute("ImmersionFX") ~= false
	if not fxOn then
		effectScale = 0
	end

	-- Decay the impact envelopes
	fovPunch *= math.max(0, 1 - dt * 6 * tempoScale)
	shake = shake:Lerp(Vector3.zero, math.min(dt * 9 * tempoScale, 1))

	-- Beat glow curve: sharp attack, fast falloff
	local beatGlow = math.exp(-beatAge * 5) * beatPower * effectScale

	-- FOV punch
	if camera then
		camera.FieldOfView = baseFOV + fovPunch * effectScale
	end

	-- Camera shake through the humanoid so it layers cleanly on the camera
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid ~= trackedHumanoid then
		if trackedHumanoid then trackedHumanoid.CameraOffset = baseCameraOffset end
		trackedHumanoid = humanoid
		baseCameraOffset = if humanoid then humanoid.CameraOffset else Vector3.zero
	end
	if humanoid then
		humanoid.CameraOffset = baseCameraOffset + shake * effectScale
	end

	-- Bloom flare on the kick (base glow also switches off with the setting)
	bloom.Intensity = (fxOn and 0.4 or 0) + beatGlow * 1.4
	bloom.Size = 32 + beatGlow * 24

	-- Saturation + contrast hit so colors feel more alive on the beat
	colorFx.Saturation = beatGlow * 0.35
	colorFx.Contrast = beatGlow * 0.18

	-- Loud parts of the track push a gentle brightness lift
	colorFx.Brightness = beat.energy * 0.05 * effectScale
end)

script.Destroying:Connect(function()
	heartbeatConnection:Disconnect()
	if camera then camera.FieldOfView = baseFOV end
	if trackedHumanoid then trackedHumanoid.CameraOffset = baseCameraOffset end
	bloom:Destroy()
	colorFx:Destroy()
end)
