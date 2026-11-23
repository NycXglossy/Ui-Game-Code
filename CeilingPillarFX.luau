-- CeilingPillarFX: premium ceiling light rig with a full-blown light show.
-- Neon pillars drop partway from the ceiling on every beat (same shared
-- ClubAudioSync beat clock as the wall visualizer) while the tips act as
-- sweeping searchlights, strobe on the kick, and chase hues across the grid.
-- Patterns rotate every 12 beats across six looks: full-floor pulse,
-- center ripple, random slam, sweeping wave, checkerboard slam and vortex.
-- Runs on the client for silky 60fps motion.

local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

-- Tunables
local CEIL_Y = 140.6 -- real club ceiling
local SHAFT_TOP = CEIL_Y - 1.5 -- shaft top (collar bottom)
local MIN_H = 0.5 -- retracted shaft length (studs)
local MAX_H = 62 -- capped drop: tips stop high above the dance floor
local DROP_LERP = 30 -- how fast pillars shoot down
local RETRACT_LERP = 2.2 -- how slow pillars rise back up

-- Locate the fixtures (may stream in late)
local pillarsModel = workspace:FindFirstChild("CeilingPillars")
while not pillarsModel do
	task.wait(0.25)
	pillarsModel = workspace:FindFirstChild("CeilingPillars")
end

-- Collect fixtures. Each is a Model named P<col>_<row> holding Mount, Collar,
-- Shaft and Tip. Retry until the model has its parts (client may start
-- before replication finishes).
local GRID = 5
local function collectPillars()
	local found = {}
	if not pillarsModel then return found end
	for _, fixture in ipairs(pillarsModel:GetDescendants()) do
		if not (fixture:IsA("Model") or fixture:IsA("Folder")) then continue end
		local col, row = fixture.Name:match("^P(%d+)_(%d+)$")
		if not col or not row then continue end
		local shaft = fixture:FindFirstChild("Shaft", true)
		local tip = fixture:FindFirstChild("Tip", true)
		if shaft and shaft:IsA("BasePart") and tip and tip:IsA("BasePart") then
			table.insert(found, {
				shaft = shaft, tip = tip,
				collar = fixture:FindFirstChild("Collar", true),
				glow = tip:FindFirstChild("Glow", true),
				beam = tip:FindFirstChild("Beam", true),
				col = tonumber(col), row = tonumber(row),
				seed = tonumber(col) * 101 + tonumber(row),
				h = math.max(MIN_H, shaft.Size.Y),
			})
		end
	end
	table.sort(found, function(a, b)
		if a.row == b.row then return a.col < b.col end
		return a.row < b.row
	end)
	return found
end
local pillars = collectPillars()
-- StreamingEnabled: on live servers the fixtures can take a long time to
-- replicate to the client. Keep retrying indefinitely instead of giving up
-- after 10 seconds.
while #pillars == 0 do
	task.wait(0.5)
	pillars = collectPillars()
end

-- Grid coordinates centered at 0
local function gridPos(p)
	return (p.col - (GRID + 1) / 2), (p.row - (GRID + 1) / 2)
end
local maxDist = math.sqrt(2) * (GRID - 1) / 2

local rng = Random.new()

-- Self-heal: with StreamingEnabled the fixtures can stream out and back in;
-- our saved references go stale. Detect and re-collect periodically.
local nextHealthCheck = 0

-- Beat state (driven by ClubAudioSync's beat clock)
local norm = 0
local lastBeatCount = -1
local beatAge = math.huge
local beatPower = 0
local beatCount = 0
local dropSet = {}

local clock = os.clock
local lastT = clock()

RunService.Heartbeat:Connect(function()
	local now = clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now
	beatAge += dt

	if now > nextHealthCheck then
		nextHealthCheck = now + 2
		if not pillarsModel or not pillarsModel.Parent then pillarsModel = workspace:FindFirstChild("CeilingPillars") end
		local discovered = collectPillars()
		local stale = #discovered ~= #pillars
		if not stale then
			for _, entry in ipairs(pillars) do
				if not entry.shaft.Parent or not entry.tip.Parent
					or (entry.collar and not entry.collar.Parent)
					or (entry.glow and not entry.glow.Parent)
					or (entry.beam and not entry.beam.Parent) then
					stale = true
					break
				end
			end
		end
		if stale then
			pillars = discovered
			print("[ClubNeon][CeilingPillarFX] Fixture references refreshed; active pillars=" .. #pillars)
		end
	end

	-- Beat clock from the shared ClubAudioSync module
	local beat = ClubAudioSync.getBeatState()
	local tempoNow = os.clock() * (beat.bpm / 128)
	norm = beat.energy

	if beat.beatCount ~= lastBeatCount then
		lastBeatCount = beat.beatCount
		beatCount = beat.beatCount
		beatAge = 0
		beatPower = math.clamp(0.8 + beat.energy * 1.6, 0.5, 3)
		-- Pattern 2 picks a fresh random set of pillars to slam down each beat
		if math.floor(beatCount / 12) % 6 == 2 then
			table.clear(dropSet)
			local picks = math.min(rng:NextInteger(4, 9), #pillars)
			local selected = 0
			while selected < picks do
				local pick = rng:NextInteger(1, #pillars)
				if not dropSet[pick] then dropSet[pick] = true; selected += 1 end
			end
		end
	else
		beatAge = beat.beatPhase * (60 / beat.bpm)
	end
	beatPower *= math.max(0, 1 - dt * 2 * (beat.bpm / 128))

	local beatGlow = math.exp(-beat.beatPhase * 4) * beatPower
	-- Strobe: hard double-flash on strong kicks
	local strobe = 0
	if beatPower > 1.4 then
		if beatAge < 0.06 or (beatAge > 0.12 and beatAge < 0.18) then
			strobe = 1
		end
	end
	local hue = (beatCount * 0.045) % 1
	local pattern = math.floor(beatCount / 12) % 6

	for idx, entry in pillars do
		local shaft = entry.shaft
		if shaft.Parent == nil then continue end
		local tip = entry.tip
		if tip.Parent == nil then continue end
		local gx, gz = gridPos(entry)

		local target
		if pattern == 0 then
			-- Full-floor pulse: everything drops with the music's envelope
			target = 0.04 + norm * 0.75 + beatGlow * 0.2
		elseif pattern == 1 then
			-- Independent randomized drop timing; no center-out ripple.
			local phaseOffset = (entry.seed * 0.173) % 1
			local localPhase = (beat.beatPhase + phaseOffset) % 1
			local hit = math.exp(-localPhase * 5)
			local depth = 0.25 + ((entry.seed * 37) % 71) / 100
			target = 0.05 + hit * depth * (0.35 + beatGlow * 0.65)
		elseif pattern == 2 then
			-- Random slam: chosen pillars drop hard, others idle-breathe
			local idle = 0.06 + 0.06 * math.sin(tempoNow * 1.8 + (gx + gz) * 0.9)
			if dropSet[idx] then
				target = 0.25 + beatGlow * 0.75
			else
				target = idle + norm * 0.1
			end
		elseif pattern == 3 then
			-- Sweeping wave: a diagonal wave rolls across the grid
			local wave = math.abs(math.sin((gx + gz) * 0.8 - tempoNow * 1.6))
			target = wave * (0.3 + norm * 0.45 + beatGlow * 0.35) + 0.05
		elseif pattern == 4 then
			-- Checkerboard slam: alternating cells hammer down on odd/even beats
			local parity = (gx + gz) % 2 == 0
			local phase = beatCount % 2 == 0
			if parity == phase then
				target = 0.3 + beatGlow * 0.7
			else
				target = 0.04 + norm * 0.12
			end
		else
			-- Each pillar has its own phase, speed and random depth.
			local phaseOffset = (entry.seed * 0.071) % (math.pi * 2)
			local speed = 0.7 + ((entry.seed * 13) % 9) * 0.11
			local variation = 0.5 + 0.5 * math.sin(tempoNow * speed + phaseOffset)
			local randomDepth = 0.18 + ((entry.seed * 29) % 76) / 100
			target = 0.04 + variation * randomDepth * (0.35 + beatGlow * 0.65)
		end
		target = math.clamp(target, 0.02, 1)

		-- Animate: fast drop, slow retract (frame-rate independent)
		local lerp = if target * MAX_H > entry.h then DROP_LERP else RETRACT_LERP
		local alpha = 1 - math.exp(-lerp * dt)
		entry.h += (target * MAX_H - entry.h) * alpha

		local h = entry.h
		local x = shaft.Position.X
		local z = shaft.Position.Z

		-- Shaft: top fixed at the collar, length animates downward;
		-- thickness pulses subtly on the beat
		local th = 2.2 + 0.7 * beatGlow
		shaft.Size = Vector3.new(th, h, th)
		shaft.Position = Vector3.new(x, SHAFT_TOP - h / 2, z)
		-- Shimmer: retracted pillars glimmer while dropped ones go solid
		shaft.Transparency = 0.05 + 0.3 * (1 - h / MAX_H)
			* (0.5 + 0.5 * math.sin(now * 3 + idx * 0.9))

		-- Tip: rides at the bottom of the shaft and sweeps like a searchlight.
		-- Pattern 3 spins the whole rig into a hurricane of crossing beams;
		-- other patterns keep a slow majestic rotation with a gentle tilt.
		local tipY = SHAFT_TOP - h - 0.3
		local spinSpeed = if pattern == 3 or pattern == 5 then 2.4 else 0.45
		local heading = now * spinSpeed + (gx * 0.7 + gz * 1.3)
		local tilt = if pattern == 3
			then 0.3 + 0.22 * math.sin(now * 1.3 + idx * 1.1)
			else 0.1 + 0.06 * math.sin(now * 0.7 + idx)
		tip.CFrame = CFrame.new(x, tipY, z)
			* CFrame.Angles(0, heading, 0)
			* CFrame.Angles(tilt, 0, 0)
			* CFrame.Angles(0, 0, now * 1.2)

		-- Colors: a hue chase that travels across the grid; tips flash white
		local hueOff = ((gx + gz) / (GRID - 1)) * 0.2 + now * 0.12
		-- Checkerboard pattern splits the grid into complementary color pairs
		if pattern == 4 and (gx + gz) % 2 == 1 then hueOff += 0.5 end
		local barHue = (hue + hueOff) % 1
		local sat = math.clamp(1 - (beatGlow + strobe) * 0.5, 0, 1)
		local shaftColor = Color3.fromHSV(barHue, sat, 1)
		if strobe > 0 then
			-- Hard white flash on strong kicks
			shaft.Color = Color3.new(1, 1, 1)
			tip.Color = Color3.new(1, 1, 1)
		else
			shaft.Color = shaftColor
			tip.Color = Color3.fromHSV(barHue, sat * 0.35, 1)
		end

		if entry.collar then
			entry.collar.Color = Color3.fromHSV(barHue, 0.8, 0.8)
		end

		-- Lights: glow scales with drop depth; beams strobe on the kick
		if entry.glow then
			entry.glow.Color = shaftColor
			entry.glow.Brightness = 1.5 * (h / MAX_H) + beatGlow * 2 + strobe * 3
		end
		if entry.beam then
			entry.beam.Color = shaftColor
			entry.beam.Brightness = beatGlow * 6 * (h / MAX_H + 0.2) + strobe * 5
		end
	end
end)