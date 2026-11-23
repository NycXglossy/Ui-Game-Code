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

local function collectLasers()
	local list = {}
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
				if child:IsA("Beam") then
					table.insert(beams, child)
				end
			end
				table.insert(list, {
					idx = idx, lens = d, target = target, pool = pool,
					spot = spot, beams = beams,
					currentTarget = CENTER,
				})
			end
		end
	end
	table.sort(list, function(a, b) return a.idx < b.idx end)
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

local orb = rig:FindFirstChild("CenterOrb")
local orbLight = orb and orb:FindFirstChildOfClass("PointLight")
local orbRings = {}
for i = 1, 3 do
	local ring = rig:FindFirstChild("OrbRing" .. i)
	if ring then table.insert(orbRings, ring) end
end

-- Beat state (driven by ClubAudioSync's beat clock)
local lastBeatCount = -1
local beatAge = math.huge
local beatPower = 0
local beatCount = 0
local lastColorBeat = -1

-- Heavy-kick flare state
local flareUntil = 0

local clock = os.clock
local lastT = startTime
local showTime = 0

-- Stable deterministic values avoid allocating a Random object for every laser on every frame.
local function seededUnit(seed)
	local value = math.sin(seed * 12.9898) * 43758.5453
	return value - math.floor(value)
end
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
			orb = rig:FindFirstChild("CenterOrb")
			orbLight = orb and orb:FindFirstChildOfClass("PointLight")
			orbRings = {}
			for i = 1, 3 do
				local ring = rig:FindFirstChild("OrbRing" .. i)
				if ring then table.insert(orbRings, ring) end
			end
			local refreshedBeams = 0
			for _, L in ipairs(lasers) do refreshedBeams += #L.beams end
			print("[ClubNeon][LaserShowFX] Fixture references refreshed; active lasers=" .. #lasers .. ", beams=" .. refreshedBeams)
		end
	end
	if #lasers == 0 then return end

	-- Beat clock from the shared ClubAudioSync module
	local beat = ClubAudioSync.getBeatState()
	showTime += dt * (beat.bpm / 128)
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

	-- On-beat events: color shifts across every laser and the orb
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
		if orb and orbLight then
			orb.Color = Color3.fromHSV((hue + 0.5) % 1, 1, 1)
			orbLight.Color = orb.Color
			for _, ring in ipairs(orbRings) do
				ring.Color = orb.Color
			end
		end
	end

	-- Per-frame glow: everything swells with the kick and settles after
	if orb and orbLight then
		orb.Size = Vector3.new(3.5, 3.5, 3.5) * (1 + flareKick * 0.25)
		orbLight.Brightness = 2 + flareKick * 6
	end
	local poolScale = 1 + flareKick * 0.8
	local poolFade = 0.55 - flareKick * 0.3
	for i, ring in ipairs(orbRings) do
		-- Rings spin around the orb at different speeds and axes
		ring.CFrame = CFrame.new(orb.Position)
			* CFrame.Angles(showTime * (0.4 + i * 0.25), 0, i * 0.6 + showTime * 0.3)
	end

	-- Laser choreography: a new pattern every 16 beats (one musical phrase)
	for i, L in ipairs(lasers) do
		local motionSeed = L.idx * 23.17
		local phase = seededUnit(motionSeed) * math.pi * 2
		local speed = 0.78 + seededUnit(motionSeed + 1) * 0.44
		local ang = i / #lasers * math.pi * 2 + phase * 0.22
		local targetPos
		if pattern == 0 then
			-- Orbiting spotlights circling the floor
			local spin = showTime * 0.6 * speed + phase
			local r = RADIUS * (0.15 + 0.3 * (0.5 + 0.5 * math.sin(showTime * 0.25 * speed + phase)))
			targetPos = CENTER + Vector3.new(math.cos(ang + spin) * r, 0.5, math.sin(ang + spin) * r)
		elseif pattern == 1 then
			-- Criss-cross sweeps slashing across the crowd
			local sweep = math.sin(showTime * 1.5 * speed + phase)
			targetPos = CENTER + Vector3.new(sweep * RADIUS * 0.7, 0.5, math.cos(ang) * RADIUS * 0.45)
		elseif pattern == 2 then
			-- Beat pulse: beams snap to the center on the kick, then burst outward
			local r = RADIUS * (0.05 + (0.45 + seededUnit(motionSeed + 2) * 0.3) * (1 - kick))
			targetPos = CENTER + Vector3.new(math.cos(ang) * r, 0.5, math.sin(ang) * r)
		elseif pattern == 3 then
			-- Tunnel: every beam fans outward from the center, rotating like
			-- a spinning tunnel of light around the crowd
			local spin = showTime * 0.35 * speed + phase
			local r = RADIUS * 0.95
			targetPos = CENTER + Vector3.new(math.cos(ang + spin) * r, 0.5, math.sin(ang + spin) * r)
		elseif pattern == 4 then
			-- Wall crawl: beams rake along the walls themselves, tracing
			-- light around the whole perimeter of the venue
			local t = (showTime * 0.02 * speed + i / #lasers + phase / (math.pi * 2)) % 1
			targetPos = wallPoint(t) + Vector3.new(0, 0.5, 0)
		else
			-- Blizzard: beams snap to random floor spots every beat, strobing
			local function spotForBeat(n)
				local seed = n + i * 97
				local r = RADIUS * (0.2 + seededUnit(seed) * 0.75)
				local a = ang + seededUnit(seed + 1) * math.pi
				return CENTER + Vector3.new(math.cos(a) * r, 0.5, math.sin(a) * r)
			end
			-- Interpolate between deterministic beat targets to avoid apparent
			-- stalls in the high-tempo blizzard pattern.
			targetPos = spotForBeat(beatCount):Lerp(spotForBeat(beatCount + 1), beatBlend)
		end
		-- Smooth target motion across beat/pattern changes rather than snapping fixtures.
		local motionAlpha = 1 - math.exp(-dt * 10)
		L.currentTarget = L.currentTarget:Lerp(targetPos, motionAlpha)
		local smoothTarget = L.currentTarget
		L.target.CFrame = CFrame.new(smoothTarget)
		-- Light pool chases the smoothed beam and pulses with the kick
		L.pool.CFrame = CFrame.new(smoothTarget + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		L.pool.Size = Vector3.new(0.1, 3.5 * poolScale, 3.5 * poolScale)
		L.pool.Transparency = poolFade
		L.spot.Brightness = 1.5 + flareKick * 5
		L.spot.Enabled = true
	end
end)