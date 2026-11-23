-- MovingHeadShowFX (client half of the dual-script projector show):
-- animates the moving-head rig built by the server script. Uses the shared
-- ClubAudioSync beat clock, hue cadence (0.045/beat) and 16-beat pattern
-- rotation so the whole club hits together, synced to the club's ClubMusic
-- AudioPlayer backend. Heavy kicks fire the strobe bars in 12Hz bursts.
-- Runs client-side for 60fps pan/tilt sweeps.

local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

-- Tunables
local STROBE_BURST = 1.0 -- seconds a heavy-kick strobe-bar burst lasts
local STROBE_HZ = 12 -- hard on/off flashes per second during a burst

-- Measure the dance floor from the panel grid (same as the rig builder)
-- Client scripts can start before Workspace has finished replicating the floor.
-- Wait for usable panel bounds instead of silently exiting during the join-time race.
local fx = workspace:FindFirstChild("CeilingFX")
local floorY = -math.huge
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
local floorPartCount = 0
local floorDeadline = os.clock() + 60
repeat
	fx = fx or workspace:FindFirstChild("CeilingFX")
	floorY = -math.huge
	minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	floorPartCount = 0
	if fx then
		for _, p in fx:GetChildren() do
			if p:IsA("BasePart") then
				floorPartCount += 1
				local pos = p.Position
				if pos.Y < 40 then floorY = math.max(floorY, pos.Y) end
				minX = math.min(minX, pos.X); maxX = math.max(maxX, pos.X)
				minZ = math.min(minZ, pos.Z); maxZ = math.max(maxZ, pos.Z)
			end
		end
	end
	if floorY == -math.huge or maxX <= minX or maxZ <= minZ then task.wait(0.5) end
until (floorY ~= -math.huge and maxX > minX and maxZ > minZ) or os.clock() >= floorDeadline
if floorY == -math.huge or maxX <= minX or maxZ <= minZ then
	warn("[ClubNeon][MovingHeadShowFX] Startup aborted: CeilingFX floor panels did not replicate with usable bounds within 60 seconds.")
	return
end
print("[ClubNeon][MovingHeadShowFX] Floor bounds ready; panels=" .. floorPartCount)

local CENTER = Vector3.new((minX + maxX) / 2, floorY, (minZ + maxZ) / 2)
local RADIUS = math.min(maxX - minX, maxZ - minZ) / 2

-- Ceiling height for the ceiling-rake pattern (same raycast as the builder)
local ceilRay = workspace:Raycast(CENTER, Vector3.new(0, 500, 0))
local CEIL_Y = ceilRay and ceilRay.Position.Y or floorY + 60

-- Discover the rig built by the server script (streaming-robust)
local rig = workspace:FindFirstChild("MovingHeadRig")
while not rig do
	task.wait(0.5)
	rig = workspace:FindFirstChild("MovingHeadRig")
end

-- Stable deterministic values avoid allocating a Random object for every fixture per frame.
local function seededUnit(seed)
	local value = math.sin(seed * 12.9898) * 43758.5453
	return value - math.floor(value)
end

local function randomFloorSpot(seed, y)
	local margin = math.min(2, math.max(0.25, (maxX - minX) * 0.04))
	local x = minX + margin + seededUnit(seed) * math.max(0.5, maxX - minX - margin * 2)
	local z = minZ + margin + seededUnit(seed + 1) * math.max(0.5, maxZ - minZ - margin * 2)
	return Vector3.new(x, y, z)
end

local function clampFloorPoint(x, z, y)
	return Vector3.new(
		math.clamp(x, minX + 1, maxX - 1),
		y,
		math.clamp(z, minZ + 1, maxZ - 1)
	)
end

-- Stratified coverage: each projector owns a different floor cell instead of
-- independently rolling anywhere on the floor (which can create hotspots).
local function distributedFloorSpot(index, total, seed, y)
	local columns = math.max(1, math.ceil(math.sqrt(total * ((maxX - minX) / math.max(1, maxZ - minZ)))))
	local rows = math.max(1, math.ceil(total / columns))
	local cell = (index - 1) % total
	local column = cell % columns
	local row = math.floor(cell / columns)
	local cellWidth = (maxX - minX) / columns
	local cellDepth = (maxZ - minZ) / rows
	local jitterX = (seededUnit(seed) - 0.5) * cellWidth * 0.42
	local jitterZ = (seededUnit(seed + 1) - 0.5) * cellDepth * 0.42
	return clampFloorPoint(
		minX + (column + 0.5) * cellWidth + jitterX,
		minZ + (row + 0.5) * cellDepth + jitterZ,
		y
	)
end

local function collectHeads()
	local list = {}
	if not rig then return list end
	for _, d in rig:GetChildren() do
		local n = d.Name:match("^Head(%d+)_Lens$")
		if n and d:IsA("BasePart") then
			local idx = tonumber(n)
			local target = rig:FindFirstChild("Head" .. n .. "_Target")
			local pool = rig:FindFirstChild("Head" .. n .. "_Pool")
			local beam = d:FindFirstChildOfClass("Beam")
			local spot = d:FindFirstChildOfClass("SpotLight")
			if target and pool and beam and spot then
				table.insert(list, {
					idx = idx, head = d, target = target, pool = pool,
					beam = beam, spot = spot, pos = d.CFrame.Position,
					currentTarget = randomFloorSpot(idx * 17.31, floorY + 1),
					anchor = randomFloorSpot(idx * 17.31 + 7, floorY + 1),
					phase = seededUnit(idx * 17.31 + 2) * math.pi * 2,
					speed = 0.78 + seededUnit(idx * 17.31 + 3) * 0.44,
				})
			end
		end
	end
	table.sort(list, function(a, b) return a.idx < b.idx end)
	for i, H in ipairs(list) do
		H.anchor = distributedFloorSpot(i, #list, H.idx * 29.7, floorY + 1)
		H.currentTarget = H.anchor
	end
	return list
end

local function collectStrobeCells()
	local cells = {}
	if not rig then return cells end
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:match("^Strobe%a_Cell%d+$") then
			table.insert(cells, d)
		end
	end
	table.sort(cells, function(a, b) return a.Name < b.Name end)
	return cells
end

local heads = collectHeads()
while #heads == 0 do
	task.wait(0.5)
	heads = collectHeads()
end
local strobeCells = collectStrobeCells()
print("[ClubNeon][MovingHeadShowFX] Animation started; heads=" .. #heads .. ", strobeCells=" .. #strobeCells)

-- Beat state (driven by ClubAudioSync's beat clock)
local lastBeatCount = -1
local beatAge = math.huge
local beatPower = 0
local beatCount = 0
local lastColorBeat = -1

-- Heavy-kick strobe burst state
local burstUntil = 0

local clock = os.clock
local lastT = clock()
local showTime = 0

local frameCount = 0
local nextRigAudit = 0

RunService.Heartbeat:Connect(function()
	local now = clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now
	-- Use elapsed wall time so a long frame does not permanently slow the choreography.
	beatAge += dt
	frameCount += 1
	if frameCount == 120 then print("[ClubNeon][MovingHeadShowFX] Heartbeat active; frames=" .. frameCount) end

	-- Audit every fixture independently; don't let a stale later fixture
	-- remain frozen just because the first head is still present.
	if now >= nextRigAudit then
		nextRigAudit = now + 2
		if not rig or not rig.Parent then rig = workspace:FindFirstChild("MovingHeadRig") end
		local discoveredHeads = collectHeads()
		local needsRefresh = #discoveredHeads ~= #heads
		for _, H in ipairs(heads) do
			if not H.head.Parent or not H.target.Parent or not H.pool.Parent
				or not H.beam.Parent or not H.spot.Parent then
				needsRefresh = true
				break
			end
		end
		local discoveredCells = collectStrobeCells()
		if #discoveredCells ~= #strobeCells then needsRefresh = true end
		if not needsRefresh then
			for _, cell in ipairs(strobeCells) do
				if not cell.Parent then needsRefresh = true; break end
			end
		end
		if needsRefresh then
			heads = discoveredHeads
			strobeCells = discoveredCells
			print("[ClubNeon][MovingHeadShowFX] Fixture references refreshed; active heads=" .. #heads .. ", strobeCells=" .. #strobeCells)
		end
	end
	if #heads == 0 then return end

	-- Beat clock from the shared ClubAudioSync module
	local beat = ClubAudioSync.getBeatState()
	showTime += dt * (beat.bpm / 128)
	if beat.beatCount ~= lastBeatCount then
		lastBeatCount = beat.beatCount
		beatCount = beat.beatCount
		beatAge = 0
		beatPower = if beat.playing then math.clamp(0.8 + beat.energy * 1.6, 0.5, 3) else 0.6
		-- Heavy kick: fire the strobe bars in a beat-scaled burst
		if beat.playing and beatPower > 1.6 then
			burstUntil = now + (60 / beat.bpm) * 1.5
		end
	else
		beatAge = beat.beatPhase * (60 / beat.bpm)
	end
	beatPower *= math.max(0, 1 - dt * 2 * (beat.bpm / 128))

	local kick = math.exp(-beat.beatPhase * 5) * beatPower
	local hue = (beatCount * 0.045) % 1 -- same cadence as the other FX
	local pattern = math.floor(beatCount / 16) % 6
	local beatBlend = math.clamp(beat.beatPhase, 0, 1)
	beatBlend = beatBlend * beatBlend * (3 - 2 * beatBlend)
	local bursting = now < burstUntil
	-- Every cell flashes on its own deterministic phase, but remains locked
	-- to the same beat-triggered burst. This avoids synchronized dead-looking
	-- pairs and ensures every discovered cell receives an update each frame.
	for cellIndex, cell in ipairs(strobeCells) do
		if cell.Parent then
			local phaseOffset = seededUnit(cellIndex * 41.17 + 5.3)
			local flashOn = bursting
				and (math.floor((now + phaseOffset / STROBE_HZ) * STROBE_HZ) % 2 == 0)
			cell.Transparency = flashOn and 0 or 1
		end
	end

	-- On-beat color rotation around the hue wheel
	if beatCount ~= lastColorBeat then
		lastColorBeat = beatCount
		for i, H in ipairs(heads) do
			local c = Color3.fromHSV((hue + i / #heads * 0.25) % 1, 1, 1)
			H.head.Color = c
			H.beam.Color = ColorSequence.new(c)
			H.spot.Color = c
			H.pool.Color = c
		end
	end

	-- Beam glow swells with the kick
	local beamFade = math.clamp(0.72 - kick * 0.12, 0.48, 0.72)
	for _, H in ipairs(heads) do
		H.beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, beamFade),
			NumberSequenceKeypoint.new(0.7, beamFade + 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
	end

	-- Choreography: a new pattern every 16 beats (one musical phrase)
		for i, H in ipairs(heads) do
		local phase, speed = H.phase, H.speed
		local anchor = H.anchor
		local targetPos
		if pattern == 0 then
			-- Independent randomized sweep around each fixture's own floor lane.
			local sweep = math.sin(showTime * 0.75 * speed + phase)
			targetPos = clampFloorPoint(anchor.X + sweep * RADIUS * 0.28,
				anchor.Z + math.cos(showTime * 0.42 * speed + phase) * RADIUS * 0.22, floorY + 1)
		elseif pattern == 1 then
			-- Each head orbits a different randomized anchor and radius.
			local spin = showTime * 0.5 * speed + phase
			local r = RADIUS * (0.12 + seededUnit(H.idx * 17.31 + 4) * 0.22)
			targetPos = clampFloorPoint(anchor.X + math.cos(spin) * r,
				anchor.Z + math.sin(spin) * r, floorY + 1)
		elseif pattern == 2 then
			-- Every head selects independent full-floor destinations each beat.
			local function spotForBeat(n)
				return distributedFloorSpot(i, #heads, n * 131 + H.idx * 911, floorY + 1)
			end
			targetPos = spotForBeat(beatCount):Lerp(spotForBeat(beatCount + 1), beatBlend)
		elseif pattern == 3 then
			-- Per-fixture perimeter crawl with a randomized starting offset.
			local t = (showTime * 0.03 * speed + i / #heads + phase / (math.pi * 2)) % 1
			local per = 2 * ((maxX - minX) + (maxZ - minZ))
			local d2 = t * per
			local wx, wz
			if d2 < maxX - minX then
				wx, wz = minX + d2, minZ
			elseif d2 < (maxX - minX) + (maxZ - minZ) then
				wx, wz = maxX, minZ + (d2 - (maxX - minX))
			elseif d2 < 2 * (maxX - minX) + (maxZ - minZ) then
				wx, wz = maxX - (d2 - (maxX - minX) - (maxZ - minZ)), maxZ
			else
				wx, wz = minX, maxZ - (d2 - 2 * (maxX - minX) - (maxZ - minZ))
			end
			targetPos = Vector3.new(wx, floorY + 14 + math.sin(showTime * 1.2 * speed + phase) * 8, wz)
		elseif pattern == 4 then
			-- Ceiling rake with each beam crossing a different randomized lane.
			local sweep = math.sin(showTime * 0.5 * speed + phase)
			targetPos = clampFloorPoint(anchor.X + sweep * RADIUS * 0.3,
				anchor.Z + math.cos(phase + showTime * 0.3 * speed) * RADIUS * 0.3, CEIL_Y - 1)
		else
			-- Randomized wandering destinations; never converge on the center.
			local function spotForBeat(n)
				return distributedFloorSpot(i, #heads, n * 197 + H.idx * 1297, floorY + 1)
			end
			targetPos = spotForBeat(beatCount):Lerp(spotForBeat(beatCount + 1), beatBlend)
		end
		-- Smooth target motion across beat/pattern changes rather than snapping fixtures.
		local motionAlpha = 1 - math.exp(-dt * 9)
		H.currentTarget = H.currentTarget:Lerp(targetPos, motionAlpha)
		local smoothTarget = H.currentTarget
		H.target.CFrame = CFrame.new(smoothTarget)

		-- Head visibly aims at its smoothed target: pan and tilt like a real moving head
		H.head.CFrame = CFrame.lookAt(H.pos, smoothTarget) * CFrame.Angles(0, 0, math.pi / 2)

		-- Light pool follows the beam when it lands on the floor
		local onFloor = smoothTarget.Y < floorY + 4
		H.pool.Transparency = onFloor and (0.75 - kick * 0.07) or 1
		if onFloor then
			local poolScale = 1 + kick * 0.15
			H.pool.Size = Vector3.new(0.1, 3.5 * poolScale, 3.5 * poolScale)
			H.pool.CFrame = CFrame.new(smoothTarget.X, floorY + 0.2, smoothTarget.Z)
				* CFrame.Angles(0, 0, math.pi / 2)
		end
		H.spot.Brightness = 0.55 + kick * 1.15
	end
end)