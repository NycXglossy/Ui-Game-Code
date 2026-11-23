-- WallVisualizerClient: beat-synced LED EQ walls on all 4 club walls.
-- Syncs to the club's ClubMusic AudioPlayer backend through the shared
-- ClubAudioSync module (beat clock derived from TimePosition + simulated
-- energy envelope) and drives 40 neon EQ bars + peak caps per wall with
-- pattern choreography and shockwave ripples.
-- Runs on the client: silky 60fps motion, zero server cost.

local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

-- Tunables
local BAR_COUNT = 40
local MIN_H = 0.5 -- resting bar height (studs)
local MAX_H = 46 -- bar + peak cap together reach the wall backing top (Y~48)
local CAP_FALL = 15 -- peak cap gravity (studs/sec)
local CAP_GAP = 0.4
local RISE_LERP = 14 -- how fast bars shoot up
local FALL_LERP = 3.5 -- how slow bars fall (classic EQ bounce)
local WAVE_SPEED = 30 -- shockwave travel speed (bar indices/sec)

-- Locate the visualizer (may stream in late)
local visualizer = workspace:FindFirstChild("WallVisualizer")
while not visualizer do
	task.wait(0.25)
	visualizer = workspace:FindFirstChild("WallVisualizer")
end

local nextHealthCheck = 0

-- Collect each wall's bars, caps and rail. The client may start before
-- workspace finishes replicating, so retry until the walls actually have
-- their bars instead of silently giving up on the first empty pass.
local function collectWalls()
	local found = {}
	for _, wallFolder in visualizer:GetChildren() do
		local wall = { bars = {}, caps = {}, rail = nil }
		for _, part in wallFolder:GetChildren() do
			local i = tonumber(part.Name:match("^B(%d+)$"))
			if i then
				-- baseY is the bar's true bottom (on the floor) so bars grow
				-- upward from the floor instead of drifting up as they animate
				wall.bars[i] = { part = part, baseY = part.Position.Y - part.Size.Y / 2, h = MIN_H, capH = MIN_H + 4 }
			else
				i = tonumber(part.Name:match("^C(%d+)$"))
				if i then
					wall.caps[i] = part
				elseif part.Name == "Rail" then
					wall.rail = part
				end
			end
		end
		if next(wall.bars) then table.insert(found, wall) end
	end
	return found
end

local walls = collectWalls()
-- StreamingEnabled: on live servers the walls can take a long time to
-- replicate to the client (slow connections, far spawns). Keep retrying
-- indefinitely instead of giving up after 10 seconds -- once the player
-- gets near the club the walls stream in and the show starts.
while #walls == 0 do
	task.wait(0.5)
	walls = collectWalls()
end

local rng = Random.new()
local spectrum = {} -- per-bar energy, reshuffled every beat
for i = 1, BAR_COUNT do spectrum[i] = 0.3 end

-- Beat state (driven by ClubAudioSync's beat clock)
local norm = 0 -- smoothed energy envelope the bars track
local lastBeatCount = -1
local beatAge = math.huge
local beatPower = 0

local clock = os.clock
local lastT = clock()


RunService.Heartbeat:Connect(function()
	local now = clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now
	beatAge += dt

	-- Self-heal: if streaming or anything else replaces the parts,
	-- our saved references go stale -- detect it and re-collect the walls.
	if now > nextHealthCheck then
		nextHealthCheck = now + 2
		local stale = #walls == 0
		for _, wall in walls do
			local first = wall.bars[1]
			if not first or first.part.Parent == nil then
				stale = true
				break
			end
		end
		if stale then
			walls = collectWalls()
		end
	end

	-- Beat clock from the shared ClubAudioSync module: the club's AudioPlayer
	-- has no PlaybackLoudness, so energy and beats come from its TimePosition
	local beat = ClubAudioSync.getBeatState()
	norm = beat.energy

	if beat.beatCount ~= lastBeatCount then
		lastBeatCount = beat.beatCount
		beatAge = 0
		beatPower = math.clamp(0.8 + beat.energy * 1.6, 0.5, 3)
		-- On each beat: reshuffle the simulated spectrum (bass hits hardest)
		for i = 1, BAR_COUNT do
			local bass = 1 - (i - 1) / BAR_COUNT
			spectrum[i] = math.clamp(rng:NextNumber(0.2, 1) * (0.45 + bass * 0.55), 0, 1)
		end
	else
		beatAge = beat.beatPhase * (60 / beat.bpm)
	end
	beatPower *= math.max(0, 1 - dt * 2)

	local beatGlow = math.exp(-beatAge * 4) * beatPower -- sharp hit, fast decay
	local wavefront = beatAge * WAVE_SPEED -- shockwave distance from wall center
	local hue = (beat.beatCount * 0.045) % 1 -- hue advances every beat
	local pattern = math.floor(beat.beatCount / 16) % 4 -- new pattern every 16 beats

	for w, wall in walls do
		for i = 1, BAR_COUNT do
			local entry = wall.bars[i]
			if not entry then continue end
			local bar = entry.part
			local t = (i - 0.5) / BAR_COUNT
			local m = math.abs(t - 0.5) * 2 -- 0 at wall center, 1 at edges

			-- Idle sway so the wall looks alive even between beats
			local sway = 0.5 + 0.5 * math.sin(tempoNow * 2.2 + i * 0.55 + w * 1.7)

			-- Pattern choreography (changes every 16 beats)
			local target
			if pattern == 0 then
				-- EQ dance: spectrum driven by real loudness
				target = (0.12 + norm * 0.9) * (spectrum[i] * 0.7 + sway * 0.3)
				target += beatGlow * 0.25
			elseif pattern == 1 then
				-- Traveling wave rolling along the wall
				local wave = math.abs(math.sin((t * 6 - tempoNow * 1.4 - w * 0.35) * math.pi))
				target = wave * (0.35 + norm * 0.5 + beatGlow * 0.35) + 0.06
			elseif pattern == 2 then
				-- Beat pulse: the whole wall jumps on the kick and settles
				target = (0.12 + beatGlow * 0.8) * (0.6 + 0.4 * math.sin(i * 1.3 + w))
				target += norm * 0.15
			else
				-- Center burst: energy explodes outward from the wall's middle
				local ring = math.abs(m - (1 - math.exp(-beatAge * 3)) * 0.95)
				target = math.clamp(1 - ring * 2.2, 0, 1) * (0.25 + beatGlow * 0.75) + 0.08
			end

			-- Shockwave ripple traveling outward from the wall's center on each beat
			local rippleDist = math.abs(m * (BAR_COUNT / 2) - wavefront)
			local ripple = math.exp(-(rippleDist * rippleDist) / 3) * beatGlow * 0.3
			target = math.clamp(target + ripple, 0.03, 1)

			-- Animate: fast rise, slow fall (frame-rate independent)
			local lerp = if target * MAX_H > entry.h then RISE_LERP else FALL_LERP
			local alpha = 1 - math.exp(-lerp * dt)
			entry.h += (target * MAX_H - entry.h) * alpha

			local h = entry.h
			bar.Size = Vector3.new(bar.Size.X, h, bar.Size.Z)
			bar.Position = Vector3.new(bar.Position.X, entry.baseY + h / 2, bar.Position.Z)

			-- Color: hue cycles per beat with a gradient across the row,
			-- flashing toward white on the kick
			local barHue = (hue + t * 0.25 + w * 0.06) % 1
			local sat = math.clamp(1 - beatGlow * 0.5, 0, 1)
			bar.Color = Color3.fromHSV(barHue, sat, 0.85) -- slightly dimmed glow

			-- Peak cap: rides the recent maximum, then falls with gravity
			local cap = wall.caps[i]
			if cap then
				entry.capH = math.max(entry.capH - CAP_FALL * dt, h)
				cap.Position = Vector3.new(cap.Position.X, entry.baseY + entry.capH + CAP_GAP + 0.25, cap.Position.Z)
				cap.Transparency = 0.1 + math.clamp(1 - entry.capH / MAX_H, 0, 1) * 0.3
				cap.Color = Color3.fromHSV(barHue, sat * 0.35, 0.85)
			end
		end

		-- Floor rail: white flash on the kick, fading back to the hue
		if wall.rail then
			local railSat = math.clamp(1 - beatGlow * 1.6, 0, 1)
			wall.rail.Color = Color3.fromHSV(hue, railSat, 1)
			wall.rail.Transparency = 0.3 - beatGlow * 0.25
		end
	end
end)
