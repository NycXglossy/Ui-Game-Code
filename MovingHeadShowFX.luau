-- MovingHeadShowFX (client half of the dual-script projector show):
-- animates the 32-fixture, eight-per-side moving-head rig built by the server script. Uses the shared
-- ClubAudioSync beat clock, hue cadence (0.045/beat) and independent quadrant trajectories
-- driven by shared adaptive BPM/energy movement., synced to the club's ClubMusic
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
			if p:IsA("BasePart") and p.Name == "FloorPanel" then
				floorPartCount += 1
				local pos = p.Position
				floorY = math.max(floorY, pos.Y)
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
-- Four-wall crosshatch coverage: north/south fixtures scan the full floor depth
-- on distinct X lanes; east/west fixtures scan the full width on distinct Z lanes.
-- Fixture phase and BPM-scaled speed remain independent; no ceiling-FX pattern clock.
local coverageGridLogged = false
local function adaptiveCoverageTarget(coverageIndex, totalFixtures, phase, fixtureSpeed, showTime, beat, y)
	local spanX, spanZ = maxX - minX, maxZ - minZ
	local marginX = math.min(2.5, spanX * 0.035)
	local marginZ = math.min(2.5, spanZ * 0.035)
	local usableX = math.max(1, spanX - marginX * 2)
	local usableZ = math.max(1, spanZ - marginZ * 2)

	-- Assign every fixture a dedicated cell across the entire floor. The
	-- previous wall-parallel lanes left the same narrow strips active for long
	-- periods, so overlapping sweeps could still look weighted to one side.
	-- A 2:1 cell grid keeps the 32-head and 24-laser layouts evenly tiled.
	local aspect = usableX / math.max(1, usableZ)
	-- Never collapse the target lattice into a single row/column: that leaves
	-- one full half-axis underused on long rectangular dance floors.
	local rows = math.max(2, math.floor(math.sqrt(math.max(1, totalFixtures) / (2 * aspect)) + 0.5))
	local columns = math.max(2, math.ceil(totalFixtures / rows))
	if not coverageGridLogged then
		coverageGridLogged = true
		print("[ClubNeon][MovingHeadShowFX] Full-floor target lattice; columns=" .. columns
			.. ", rows=" .. rows .. ", floorAspect=" .. string.format("%.2f", aspect)
			.. ", fixtures=" .. totalFixtures)
	end
	local index = math.clamp(math.floor(coverageIndex or 1) - 1, 0, math.max(0, totalFixtures - 1))
	local column = index % columns
	local row = math.floor(index / columns)
	local cellWidth = usableX / columns
	local cellDepth = usableZ / rows
	local centerX = minX + marginX + (column + 0.5) * cellWidth
	local centerZ = minZ + marginZ + (row + 0.5) * cellDepth

	-- Shared BPM/energy changes travel speed only. Each fixture retains its
	-- own phase and traces a two-axis loop inside its assigned floor cell.
	local tempoDrive = math.clamp((((beat and beat.bpm) or 120) - 70) / 120, 0, 1)
	local energyDrive = math.clamp((beat and beat.energy) or 0, 0, 1)
	local rate = (0.38 + tempoDrive * 0.32 + energyDrive * 0.12) * fixtureSpeed
	local sweepX = math.sin(showTime * rate + phase)
	local sweepZ = math.sin(showTime * rate * 0.73 + phase * 1.61)
	local x = centerX + sweepX * cellWidth * 0.48
	local z = centerZ + sweepZ * cellDepth * 0.48
	return Vector3.new(
		math.clamp(x, minX + marginX, maxX - marginX),
		y,
		math.clamp(z, minZ + marginZ, maxZ - marginZ)
	)
end
local function collectHeads()
	local list = {}
	if not rig then return list, {north = 0, east = 0, south = 0, west = 0} end
	-- Backward-compatible metadata recovery: older replicated rig builders may not
	-- have WallSide/WallSlot yet. Infer from the actual emitter perimeter, never
	-- from CeilingFX floor bounds (which can collapse the entire rig onto one wall).
	local rigMinX, rigMaxX, rigMinZ, rigMaxZ = math.huge, -math.huge, math.huge, -math.huge
	local emitterCount = 0
	for _, candidate in ipairs(rig:GetChildren()) do
		if candidate:IsA("BasePart") and candidate.Name:match("^Head(%d+)_Lens$") then
			emitterCount += 1
			rigMinX = math.min(rigMinX, candidate.Position.X)
			rigMaxX = math.max(rigMaxX, candidate.Position.X)
			rigMinZ = math.min(rigMinZ, candidate.Position.Z)
			rigMaxZ = math.max(rigMaxZ, candidate.Position.Z)
		end
	end
	local rigSpanX = math.max(0.01, rigMaxX - rigMinX)
	local rigSpanZ = math.max(0.01, rigMaxZ - rigMinZ)
	local function inferWallMetadata(emitter, preferredSide)
		local side = preferredSide
		if side ~= "north" and side ~= "east" and side ~= "south" and side ~= "west" then
			local p = emitter.Position
			local distances = {
				{side = "north", distance = math.abs(p.Z - rigMinZ)},
				{side = "east", distance = math.abs(rigMaxX - p.X)},
				{side = "south", distance = math.abs(rigMaxZ - p.Z)},
				{side = "west", distance = math.abs(p.X - rigMinX)},
			}
			table.sort(distances, function(a, b) return a.distance < b.distance end)
			side = distances[1].side
		end
		local p = emitter.Position
		local slot
		if side == "north" then
			slot = (p.X - rigMinX) / rigSpanX
		elseif side == "east" then
			slot = (p.Z - rigMinZ) / rigSpanZ
		elseif side == "south" then
			slot = (rigMaxX - p.X) / rigSpanX
		else
			slot = (rigMaxZ - p.Z) / rigSpanZ
		end
		return side, math.clamp(slot, 0.04, 0.96)
	end
	local recoveredMetadata = 0
	local invalidMetadata = 0
	-- Use the actual emitter perimeter for wall classification. The venue trim
	-- can extend beyond the CeilingFX dance-floor panels, so comparing fixture
	-- positions directly with floor bounds can label every fixture as one side.
		for _, d in rig:GetChildren() do
		local n = d.Name:match("^Head(%d+)_Lens$")
		if n and d:IsA("BasePart") then
			local idx = tonumber(n)
			local target = rig:FindFirstChild("Head" .. n .. "_Target")
			local pool = rig:FindFirstChild("Head" .. n .. "_Pool")
			local beam = d:FindFirstChildOfClass("Beam")
			local spot = d:FindFirstChildOfClass("SpotLight")
			if target and pool and beam and spot then
				local side = d:GetAttribute("WallSide")
				local along = d:GetAttribute("WallSlot")
				if side ~= "north" and side ~= "east" and side ~= "south" and side ~= "west" then
					side = nil
				end
				if type(along) ~= "number" then along = nil end
				if not side or not along then
					recoveredMetadata += 1
					side, along = inferWallMetadata(d, side)
				end
				if not side or not along then
					invalidMetadata += 1
					warn("[ClubNeon][FX] Unable to infer wall metadata for " .. d:GetFullName())
					continue
				end
				table.insert(list, {
					idx = idx, head = d, target = target, pool = pool,
					beam = beam, spot = spot, pos = d.Position, side = side,
					sideSlot = math.clamp(along, 0.04, 0.96),
					currentTarget = randomFloorSpot(idx * 17.31, floorY + 1),
					anchor = randomFloorSpot(idx * 17.31 + 7, floorY + 1),
					phase = seededUnit(idx * 17.31 + 2) * math.pi * 2,
					speed = 0.78 + seededUnit(idx * 17.31 + 3) * 0.44,
				})
			end
		end
	end
	table.sort(list, function(a, b) return a.idx < b.idx end)
	local sideOrder = {"north", "east", "south", "west"}
	local sideGroups = {north = {}, east = {}, south = {}, west = {}}
	for _, fixture in ipairs(list) do
		local group = sideGroups[fixture.side]
		if group then table.insert(group, fixture) end
	end
	local maxSideCount = 0
	local sideCounts = {}
	for sideIndex, sideName in ipairs(sideOrder) do
		local group = sideGroups[sideName]
		table.sort(group, function(a, b) return a.sideSlot < b.sideSlot end)
		sideCounts[sideName] = #group
		maxSideCount = math.max(maxSideCount, #group)
	end
	-- Assign every fixture one unique floor cell. Round-robin by lane and wall
	-- keeps the four walls spatially interleaved even if a future venue has
	-- unequal fixture counts on its sides; modulo-based indexing could collide.
	local coverageIndex = 0
	for laneIndex = 1, maxSideCount do
		for sideIndex, sideName in ipairs(sideOrder) do
			local H = sideGroups[sideName][laneIndex]
			if H then
				coverageIndex += 1
				H.coverageIndex = coverageIndex
				-- The wall and slot define the full-floor crosshatch lane.
			end
		end
	end
	print("[ClubNeon][FX] MovingHead fixtures=" .. #list
		.. " emitters=" .. emitterCount
		.. " sides N/E/S/W=" .. sideCounts.north .. "/" .. sideCounts.east .. "/" .. sideCounts.south .. "/" .. sideCounts.west
		.. " recoveredMetadata=" .. recoveredMetadata .. " invalidMetadata=" .. invalidMetadata)
	return list, sideCounts
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

local heads, headSideCounts = collectHeads()
-- A replicated rig Folder can arrive before all fixture parts and their
-- attachments/targets. Wait for the ready-fixture count to settle before
-- taking the one-time controller snapshot.
local stableCount = #heads
local stableSince = os.clock()
local replicationDeadline = os.clock() + 20
while os.clock() < replicationDeadline do
	task.wait(0.25)
	local nextFixtures, nextCounts = collectHeads()
	if #nextFixtures ~= stableCount then
		stableCount = #nextFixtures
		stableSince = os.clock()
	end
	heads, headSideCounts = nextFixtures, nextCounts
	if #heads > 0 and os.clock() - stableSince >= 3 then
		break
	end
end
if #heads == 0 then
	warn("[ClubNeon][FX] No complete fixtures replicated within 20 seconds; controller will not start.")
	return
end
local strobeCells = collectStrobeCells()
print("[ClubNeon][MovingHeadShowFX] Four-wall crosshatch coverage ready; heads=" .. #heads
	.. ", sides=N:" .. (headSideCounts.north or 0) .. "/E:" .. (headSideCounts.east or 0)
	.. "/S:" .. (headSideCounts.south or 0) .. "/W:" .. (headSideCounts.west or 0)
	.. ", floorCells=" .. #heads .. ", strobeCells=" .. #strobeCells)

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
-- Continuous movement uses the shared adaptive speed published by ClubAudioSync.

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
		local discoveredHeads, discoveredSideCounts = collectHeads()
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
			headSideCounts = discoveredSideCounts
			strobeCells = discoveredCells
			print("[ClubNeon][MovingHeadShowFX] Fixture references refreshed; active heads=" .. #heads
				.. ", sides=N:" .. (headSideCounts.north or 0) .. "/E:" .. (headSideCounts.east or 0)
				.. "/S:" .. (headSideCounts.south or 0) .. "/W:" .. (headSideCounts.west or 0)
				.. ", strobeCells=" .. #strobeCells)
		end
	end
	if #heads == 0 then return end

	-- Beat clock from the shared ClubAudioSync module
	local beat = ClubAudioSync.getBeatState()
	showTime += dt * beat.movementSpeed
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
	local beamFade = math.clamp(0.68 - kick * 0.12, 0.44, 0.68)
	for _, H in ipairs(heads) do
		H.beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, beamFade),
			NumberSequenceKeypoint.new(0.7, beamFade + 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
	end

	-- Full-floor crosshatch movement: each wall scans an independent axis,
		-- while shared BPM/energy continuously modulate its sweep rate.
		for i, H in ipairs(heads) do
			local targetPos = adaptiveCoverageTarget(
				H.coverageIndex,
				#heads,
				H.phase,
				H.speed,
				showTime,
				beat,
				floorY + 1
			)

		-- Smooth adaptive target motion rather than snapping fixtures.
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