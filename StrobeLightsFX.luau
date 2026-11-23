-- StrobeLightsFX: robust, independently phased perimeter strobes.
-- Every fixture is discovered recursively and audited independently so a
-- streamed/replaced panel cannot leave the rest of the rig frozen.
-- Beat-synced at 60–300 BPM; rapid bursts remain capped at 12 Hz.

local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

local STROBE_BURST_HZ = 12
local AUDIT_INTERVAL = 2
local clock = os.clock

local function findRig()
	return workspace:FindFirstChild("StrobeLights")
end

local strobesModel = findRig()
while not strobesModel do
	task.wait(0.5)
	strobesModel = findRig()
end

local function isLight(instance)
	return instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight")
end

local function collectStrobes()
	local found = {}
	if not strobesModel or not strobesModel.Parent then return found end
	for _, panel in ipairs(strobesModel:GetDescendants()) do
		if panel:IsA("BasePart") and panel.Name:match("^S%d+$") then
			local lights = {}
			local namedFlash = panel:FindFirstChild("Flash", true)
			if namedFlash and isLight(namedFlash) then
				table.insert(lights, namedFlash)
			else
				for _, child in ipairs(panel:GetDescendants()) do
					if isLight(child) then table.insert(lights, child) end
				end
			end
			table.insert(found, { panel = panel, lights = lights, id = tonumber(panel.Name:match("%d+")) or #found + 1 })
		end
	end
	table.sort(found, function(a, b) return a.id < b.id end)
	return found
end

local strobes = collectStrobes()
while #strobes == 0 do
	task.wait(0.5)
	strobesModel = findRig() or strobesModel
	strobes = collectStrobes()
end

local function seededUnit(seed)
	local value = math.sin(seed * 12.9898) * 43758.5453
	return value - math.floor(value)
end

local lastBeatCount = -1
local burstUntil = 0
local burstHue = 0
local nextAudit = 0
local lastT = clock()

RunService.Heartbeat:Connect(function()
	local now = clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now

	if now >= nextAudit then
		nextAudit = now + AUDIT_INTERVAL
		if not strobesModel or not strobesModel.Parent then
			strobesModel = findRig()
		end
		local discovered = collectStrobes()
		local refresh = #discovered ~= #strobes
		if not refresh then
			for _, entry in ipairs(strobes) do
				if not entry.panel.Parent then refresh = true; break end
				for _, light in ipairs(entry.lights) do
					if not light.Parent then refresh = true; break end
				end
				if refresh then break end
			end
		end
		if refresh then
			strobes = discovered
			print("[ClubNeon][StrobeLightsFX] Fixture references refreshed; active panels=" .. #strobes)
		end
	end
	if #strobes == 0 then return end

	local beat = ClubAudioSync.getBeatState()
	if beat.beatCount ~= lastBeatCount then
		lastBeatCount = beat.beatCount
		if beat.energy >= 0.55 then
			burstUntil = now + (60 / beat.bpm) * 1.25
			burstHue = (beat.beatCount * 0.137) % 1
		end
	end

	local beatPhase = math.clamp(beat.beatPhase, 0, 1)
	local beatGlow = math.exp(-beatPhase * 5) * math.clamp(0.25 + beat.energy, 0.25, 1)
	local phrase = math.floor(beat.beatCount / 16) % 3
	local bursting = now < burstUntil

	for index, entry in ipairs(strobes) do
		local panel = entry.panel
		if not panel.Parent then continue end

		local phaseOffset = seededUnit(entry.id * 19.73 + index * 3.17)
		local intensity
		if phrase == 0 then
			local chase = (index / #strobes + beat.beatCount * 0.075 + phaseOffset * 0.2) % 1
			intensity = math.exp(-((chase - 0.5) ^ 2) * 28) * (0.25 + beatGlow)
		elseif phrase == 1 then
			local side = index <= math.ceil(#strobes / 2) and 0 or 1
			intensity = ((beat.beatCount + side) % 2 == 0) and beatGlow or 0.04
		else
			intensity = beatGlow * (0.55 + phaseOffset * 0.45)
		end

		if bursting then
			local flashStep = math.floor((now + phaseOffset / STROBE_BURST_HZ) * STROBE_BURST_HZ)
			intensity = flashStep % 2 == 0 and 1 or 0
		end
		intensity = math.clamp(intensity, 0, 1)

		local hue = bursting
			and (burstHue + phaseOffset * 0.22) % 1
			or (beat.beatCount * 0.045 + phaseOffset * 0.18) % 1
		local color = Color3.fromHSV(hue, 1 - intensity * 0.55, 1)
		panel.Material = Enum.Material.Neon
		panel.Color = Color3.fromHSV(hue, (1 - intensity * 0.55) * (0.15 + intensity * 0.85), 0.15 + intensity * 0.85)

		for _, light in ipairs(entry.lights) do
			if light.Parent then
				light.Color = color
				light.Brightness = intensity * 8
				light.Enabled = intensity > 0.02
			end
		end
	end
end)
