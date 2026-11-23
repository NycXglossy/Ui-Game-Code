-- Speaker Beat Effects (Enhanced)
-- Concert-style: rainbow hue waves across speakers, beat detection with
-- expanding shockwave rings, flashing light beams, and sparkle bursts.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

-- Shared beat clock: the club's modern AudioPlayer backend exposes no
-- PlaybackLoudness, so beats and energy come from ClubAudioSync instead of
-- scanning SoundService for a legacy Sound.
local ClubAudioSync = require(ReplicatedStorage:WaitForChild("ClubAudioSync"))

-- Collect all speaker effect sets
local function collectSpeakers()
	local speakers = {}
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == "SpeakerGlow" then
			local light = descendant:FindFirstChildOfClass("PointLight")
			local emitter = descendant:FindFirstChildOfClass("ParticleEmitter")
			local beam = descendant:FindFirstChild("SpeakerBeam")
			if light and emitter then
				table.insert(speakers, {
					glow = descendant,
					light = light,
					emitter = emitter,
					beam = beam,
				})
			end
		end
	end
	return speakers
end

local speakers = collectSpeakers()

Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("BasePart") and descendant.Name == "SpeakerGlow" then
		speakers = collectSpeakers()
	end
end)

-- Beat clock state: a new beatCount value means the beat just landed
local lastBeatCount = -1

-- Expanding shockwave ring that ripples out from a speaker on a beat
local function spawnShockwave(position, color)
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.Parent = Workspace

	-- Animate the ring expanding and fading
	task.spawn(function()
		local radius = 2
		for i = 1, 20 do
			radius += 2.2
			ring.Size = Vector3.new(0.4, radius, radius)
			ring.Transparency = 0.2 + (i / 20) * 0.8
			task.wait(0.03)
		end
		ring:Destroy()
	end)
	Debris:AddItem(ring, 2)
end

local IDLE_LEVEL = 0.12

RunService.RenderStepped:Connect(function(dt)
	local beat = ClubAudioSync.getBeatState()
	local tempoNow = os.clock() * (beat.bpm / 128)
	local level = if beat.playing then beat.energy else IDLE_LEVEL

	-- One shockwave/burst per beat on the shared club beat clock
	local isBeat = beat.beatCount ~= lastBeatCount
	lastBeatCount = beat.beatCount

	-- Smoothly ease the visual intensity toward the audio level
	for index, speaker in speakers do
		-- Rainbow wave: each speaker is offset in hue and the whole pattern flows over time
		local hue = (tempoNow * 0.12 + (index - 1) * 0.07) % 1
		local color = Color3.fromHSV(hue, 1, 1)

		speaker.glow.Color = color
		speaker.glow.Transparency = 0.95 - level * 0.75

		speaker.light.Color = color
		speaker.light.Brightness = 0.3 + level * 4.5
		speaker.light.Range = 8 + level * 20

		speaker.emitter.Color = ColorSequence.new(color)
		speaker.emitter.Rate = level * 45

		-- Light beam flashes bright on beats, fades smoothly otherwise
		if speaker.beam then
			local targetTransparency = 1 - level * 0.55
			if isBeat then
				speaker.beam.Transparency = 0.35
				speaker.beam.Color = color
			else
				speaker.beam.Transparency += (targetTransparency - speaker.beam.Transparency) * math.min(dt * 6, 1)
			end
		end

		-- On a beat: sparkle burst + shockwave ring rippling outward
		if isBeat then
			speaker.emitter:Emit(12)
			spawnShockwave(speaker.glow.Position, color)
		end
	end
end)