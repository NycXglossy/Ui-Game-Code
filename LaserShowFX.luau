-- LaserShowFX (client half of the dual-script laser show):
-- animates the wall-mounted laser projector rig built by the server
-- script. Uses the shared ClubAudioSync beat clock, hue cadence
-- (0.045/beat) and 16-beat pattern rotation so the whole club hits
-- together, synced to the club's ClubMusic AudioPlayer backend.
-- Heavy kicks fire hard flare bursts across the rig. Runs client-side
-- for 60fps beam sweeps.

local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

-- Tunables
local FLARE_BURST = 1.0 -- seconds a heavy-kick flare lasts
local FLARE_HZ = 12 -- hard on/off flashes per second during a flare

-- Measure the dance floor from the panel grid (same as the rig builder)
-- Client scripts can start before Workspace has finished replicating the floor.
-- Wait for usable panel bounds instead of silently exiting during the join-time race.
local folder = workspace:FindFirstChild("CeilingFX")
local floorY = -math.huge
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
local floorPartCount = 0
local floorDeadline = os.clock() + 60
repeat
	folder = folder or workspace:FindFirstChild("CeilingFX")
	floorY = -math.huge
	minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	floorPartCount = 0
	if folder then
		for _, p in folder:GetChildren() do
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
	warn("[ClubNeon][LaserShowFX] Startup aborted: CeilingFX floor panels did not replicate with usable bounds within 60 seconds.")
	return
end
print("[ClubNeon][LaserShowFX] Floor bounds ready; panels=" .. floorPartCount)

local CENTER = Vector3.new((minX + maxX) / 2, floorY, (minZ + maxZ) / 2)
local RADIUS = math.min(maxX - minX, maxZ - minZ) / 2

-- Wall perimeter walk (same as the rig builder, for the wall-crawl pattern)
local INSET = 0.4
local wallMinX, wallMaxX = minX + INSET, maxX - INSET
local wallMinZ, wallMaxZ = minZ + INSET, maxZ - INSET
local wallW = wallMaxX - wallMinX
local wallH = wallMaxZ - wallMinZ
local perimTotal = 2 * (wallW + wallH)

local function wallPoint(t)
	local d = (t % 1) * perimTotal
	if d < wallW then
		return Vector3.new(wallMinX + d, 0, wallMinZ)
	elseif d < wallW + wallH then
		return Vector3.new(wallMaxX, 0, wallMinZ + (d - wallW))
	elseif d < 2 * wallW + wallH then
		return Vector3.new(wallMaxX - (d - wallW - wallH), 0, wallMaxZ)
	else
		return Vector3.new(wallMinX, 0, wallMaxZ - (d - 2 * wallW - wallH))
	end
end

-- Discover the rig built by the server script (streaming-robust)
local rig = workspace:FindFirstChild("LaserRig")
while not rig do
	task.wait(0.5)
	rig = workspace:FindFirstChild("LaserRig")
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

-- Stratified coverage assigns each laser a distinct floor cell. Per-beat
-- variation stays inside that cell, preventing random pileups in one hotspot.
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

local function collectLasers()
	local list = {}
	if not rig then return list end
	-- Use the actual emitter perimeter for wall classification. The venue trim
	-- can extend beyond the CeilingFX dance-floor panels, so comparing fixture
	-- positions directly with floor bounds can label every fixture as one side.
		for _, d in rig:GetChildren() do
		local n = d.Name:match("^Laser(%d+)_Lens$")
		if n and d:IsA("BasePart") then
			local idx = tonumber(n)
			local target = rig:FindFirstChild("Laser" .. n .. "_Target")
			local pool = rig:FindFirstChild("Laser" .. n .. "_Pool")
			local spot = d:FindFirstChildOfClass("SpotLight")
			if target and pool and spot then
				local beams = {}
				for _, child in d:GetChildren() do
					if child:IsA("Beam") then table.insert(beams, child) end
				end
				-- Wall identity is authored by the server rig builder; do not infer
				-- it from world-space extrema, which can collapse on irregular venues.
				local side = d:GetAttribute("WallSide")
				local along = d:GetAttribute("WallSlot")
				if type(side) ~= "string" or type(along) ~= "number" then
					continue
				end
				table.insert(list, {
					idx = idx, lens = d, target = target, pool = pool,
					spot = spot, beams = beams, side = side,
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
	for i, L in ipairs(list) do
		L.anchor = distributedFloorSpot(i, #list, L.idx * 31.9, floorY + 0.5)
		L.currentTarget = L.anchor
	end
	return list
end

local lasers = collectLasers()
while #lasers == 0 do
	task.wait(0.5)
	lasers = collectLasers()
end
local beamCount = 0
for _, laser in ipairs(lasers) do beamCount += #laser.beams end
print("[ClubNeon][LaserShowFX] Animation started; lasers=" .. #lasers .. ", beams=" .. beamCount)

-- Beat state (driven by ClubAudioSync's beat clock)
local lastBeatCount = -1
local beatAge = math.huge
local beatPower = 0
local beatCount = 0
local lastColorBeat = -1

-- Heavy-kick flare state
local flareUntil = 0

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
	if frameCount == 120 then print("[ClubNeon][LaserShowFX] Heartbeat active; frames=" .. frameCount) end

	-- Audit every laser independently so stale references on later fixtures
	-- are recovered even while the first laser remains healthy.
	if now >= nextRigAudit then
		nextRigAudit = now + 2
		if not rig or not rig.Parent then rig = workspace:FindFirstChild("LaserRig") end
		local discoveredLasers = collectLasers()
		local needsRefresh = #discoveredLasers ~= #lasers
		for _, L in ipairs(lasers) do
			if not L.lens.Parent or not L.target.Parent or not L.pool.Parent or not L.spot.Parent then
				needsRefresh = true
				break
			end
			for _, beam in ipairs(L.beams) do
				if not beam.Parent then needsRefresh = true; break end
			end
			if needsRefresh then break end
		end
		if needsRefresh then
			lasers = discoveredLasers
			local refreshedBeams = 0
			for _, L in ipairs(lasers) do refreshedBeams += #L.beams end
			print("[ClubNeon][LaserShowFX] Fixture references refreshed; active lasers=" .. #lasers .. ", beams=" .. refreshedBeams)
		end
	end
	if #lasers == 0 then return end

	-- Beat clock from the shared ClubAudioSync module
	local beat = ClubAudioSync.getBeatState()
	showTime += dt * (beat.bpm / 128) * beat.movementSpeed
	if beat.beatCount ~= lastBeatCount then
		lastBeatCount = beat.beatCount
		beatCount = beat.beatCount
		beatAge = 0
		beatPower = if beat.playing then math.clamp(0.8 + beat.energy * 1.6, 0.5, 3) else 0.6
		-- Heavy kick: trigger a beat-scaled flare burst across the rig
		if beat.playing and beatPower > 1.6 then
			flareUntil = now + (60 / beat.bpm) * 1.5
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
	local flaring = now < flareUntil
	local flare = flaring and (math.floor(now * FLARE_HZ) % 2 == 0) and 1 or 0
	local flareKick = kick + flare * 1.5

	-- On-beat events: color shifts across every laser fixture
	if beatCount ~= lastColorBeat then
		lastColorBeat = beatCount
		for i, L in ipairs(lasers) do
				local c = Color3.fromHSV((hue + i / #lasers * 0.15) % 1, 1, 1)
			L.lens.Color = c
			L.pool.Color = c
			L.spot.Color = c
			for _, bm in ipairs(L.beams) do
				bm.Color = ColorSequence.new(c)
			end
		end
	end

	-- Laser floor-pool choreography; the centerpiece has its own client animator.
	-- Keep floor pools readable without washing out nearby panels.
	local poolScale = 1 + math.clamp(flareKick, 0, 1.5) * 0.08
	local poolFade = math.clamp(0.86 - math.clamp(flareKick, 0, 1.5) * 0.025, 0.82, 0.86)

	-- Laser choreography: a new pattern every 16 beats (one musical phrase)
	for i, L in ipairs(lasers) do
		local phase, speed = L.phase, L.speed
		local anchor = L.anchor
		local targetPos
		if pattern == 0 then
			-- Independent orbit paths around randomized floor anchors.
			local spin = showTime * 0.6 * speed + phase
			local r = RADIUS * (0.12 + 0.22 * (0.5 + 0.5 * math.sin(showTime * 0.25 * speed + phase)))
			targetPos = clampFloorPoint(anchor.X + math.cos(spin) * r,
				anchor.Z + math.sin(spin) * r, floorY + 0.5)
		elseif pattern == 1 then
			-- Criss-cross sweeps use separate randomized lanes per laser.
			local sweep = math.sin(showTime * 1.5 * speed + phase)
			targetPos = clampFloorPoint(anchor.X + sweep * RADIUS * 0.3,
				anchor.Z + math.cos(phase) * RADIUS * 0.3, floorY + 0.5)
		elseif pattern == 2 then
			-- Beat destinations are independently randomized across the floor.
			local function spotForBeat(n)
				return distributedFloorSpot(i, #lasers, n * 211 + L.idx * 1877, floorY + 0.5)
			end
			targetPos = spotForBeat(beatCount):Lerp(spotForBeat(beatCount + 1), beatBlend)
		elseif pattern == 3 then
			-- Balanced four-wall cross-hatch: each wall owns evenly spaced lanes.
			-- Opposing walls sweep in opposite directions so the whole floor is
			-- crossed without repeatedly piling every beam into the center.
			local sweep = (math.sin(showTime * 0.42 * speed + phase) + 1) * 0.5
			local marginX = math.min(3, (maxX - minX) * 0.045)
			local marginZ = math.min(3, (maxZ - minZ) * 0.045)
			local x, z
			if L.side == "north" or L.side == "south" then
				x = minX + marginX + L.sideSlot * (maxX - minX - marginX * 2)
				local depth = if L.side == "north" then sweep else 1 - sweep
				z = minZ + marginZ + depth * (maxZ - minZ - marginZ * 2)
			else
				z = minZ + marginZ + L.sideSlot * (maxZ - minZ - marginZ * 2)
				local width = if L.side == "west" then 1 - sweep else sweep
				x = minX + marginX + width * (maxX - minX - marginX * 2)
			end
			targetPos = clampFloorPoint(x, z, floorY + 0.5)
		elseif pattern == 4 then
			-- Wall crawl remains perimeter-based with per-laser phase offsets.
			local t = (showTime * 0.02 * speed + i / #lasers + phase / (math.pi * 2)) % 1
			targetPos = wallPoint(t) + Vector3.new(0, 0.5, 0)
		else
			-- Blizzard: randomized full-floor spots on each beat, no center snap.
			local function spotForBeat(n)
				return distributedFloorSpot(i, #lasers, n * 307 + L.idx * 2371, floorY + 0.5)
			end
			targetPos = spotForBeat(beatCount):Lerp(spotForBeat(beatCount + 1), beatBlend)
		end
		-- Smooth target motion across beat/pattern changes rather than snapping fixtures.
		local motionAlpha = 1 - math.exp(-dt * 10)
		L.currentTarget = L.currentTarget:Lerp(targetPos, motionAlpha)
		local smoothTarget = L.currentTarget
		L.target.CFrame = CFrame.new(smoothTarget)
		-- Light pool chases the smoothed beam and pulses with the kick
		L.pool.CFrame = CFrame.new(smoothTarget + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		L.pool.Size = Vector3.new(0.1, 2.7 * poolScale, 2.7 * poolScale)
		L.pool.Transparency = poolFade
		L.spot.Brightness = 0.28 + math.clamp(flareKick, 0, 1.5) * 0.38
		L.spot.Enabled = true
	end
end)