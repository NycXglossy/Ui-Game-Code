-- StrobeLightsFX: perimeter strobe rig synced to the club's music.
-- Panels flash on every beat, run color chases along each wall, and fire
-- rapid strobe bursts on heavy kicks. Patterns rotate every 16 beats.
-- Uses the shared ClubAudioSync beat clock so the whole club hits together.
-- Runs client-side for 60fps flashes.

local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

-- Tunables
local STROBE_BURST_HZ = 12 -- flashes per second during a burst
local BURST_LENGTH = 1.0 -- seconds a strobe burst lasts

-- Collect strobe panels (streaming-robust: retry until they arrive)
local strobesModel = workspace:FindFirstChild("StrobeLights")
while not strobesModel do
	task.wait(0.5)
	strobesModel = workspace:FindFirstChild("StrobeLights")
end

local function collectStrobes()
	local found = {}
	for _, panel in strobesModel:GetChildren() do
		if panel:IsA("BasePart") and panel.Name:match("^S%d+$") then
			local light = panel:FindFirstChild("Flash")
			if light then
				table.insert(found, { panel = panel, light = light })
			end
		end
	end
	return found
end

local strobes = collectStrobes()
while #strobes == 0 do
	task.wait(0.5)
	strobes = collectStrobes()
end

local N = #strobes

-- Beat state (driven by ClubAudioSync's beat clock)
local lastBeatCount = -1
local beatAge = math.huge
local beatPower = 0
local beatCount = 0

-- Strobe burst state: heavy kicks trigger a rapid strobe burst
local burstUntil = 0
local burstHue = 0

local clock = os.clock
local lastT = clock()

RunService.Heartbeat:Connect(function()
	local now = clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now
	beatAge += dt

	-- Self-heal if streaming replaces the panels
	if strobes[1] and strobes[1].panel.Parent == nil then
		strobes = collectStrobes()
		if #strobes == 0 then return end
		N = #strobes
	end

	-- Beat clock from the shared ClubAudioSync module
	local beat = ClubAudioSync.getBeatState()
	local tempoNow = os.clock() * (beat.bpm / 128)
	if beat.beatCount ~= lastBeatCount then
		lastBeatCount = beat.beatCount
		beatCount = beat.beatCount
		beatAge = 0
		beatPower = math.clamp(0.8 + beat.energy * 1.6, 0.5, 3)
		-- Heavy kick: trigger a rapid strobe burst
		if beatPower > 1.6 then
			burstUntil = now + (60 / beat.bpm) * 1.5
			burstHue = (beatCount * 0.13) % 1
		end
	else
		beatAge = beat.beatPhase * (60 / beat.bpm)
	end
	beatPower *= math.max(0, 1 - dt * 2 * (beat.bpm / 128))

	local beatGlow = math.exp(-beat.beatPhase * 5) * beatPower
	local hue = (beatCount * 0.045) % 1
	local pattern = math.floor(beatCount / 16) % 3
	local bursting = now < burstUntil
	-- Square wave for hard on/off strobing during a burst
	local strobeOn = bursting and (math.floor(now * STROBE_BURST_HZ) % 2 == 0)

	for idx, entry in strobes do
		local panel = entry.panel
		local light = entry.light

		-- Base flash intensity per pattern
		local intensity
		if pattern == 0 then
			-- Wall chase: a pulse of light travels around the perimeter
			local phase = (idx / N + tempoNow * 0.35) % 1
			intensity = math.exp(-((phase - 0.5) ^ 2) * 40) * (0.4 + beatGlow)
		elseif pattern == 1 then
			-- Alternating halves: panels flip on/off each beat like classic club strobes
			local half = (idx % (N / 2) < N / 4) and 0 or 1
			intensity = if (beatCount + half) % 2 == 0 then beatGlow else 0.05
		else
			-- All-flash: everything fires together on the kick
			intensity = beatGlow
		end

		-- Strobe burst overrides the pattern with hard flashes
		if bursting then
			intensity = strobeOn and 1 or 0
		end

		intensity = math.clamp(intensity, 0, 1)

		-- Colors: hue cycles around the perimeter during bursts; otherwise a
		-- slow chase with white-hot peaks at full intensity
		local phue = if bursting
			then (burstHue + idx / N * 0.25) % 1
			else (hue + idx / N * 0.15) % 1
		local color = Color3.fromHSV(phue, 1 - intensity * 0.6, 1)
		panel.Color = color
		light.Color = color

		-- Neon flash: bright when lit, near-black when off for hard contrast
		panel.Material = Enum.Material.Neon
		local lit = 0.15 + intensity * 0.85
		panel.Color = Color3.fromHSV(phue, (1 - intensity * 0.6) * lit, lit)

		light.Brightness = intensity * 8
		light.Enabled = intensity > 0.02
	end
end)