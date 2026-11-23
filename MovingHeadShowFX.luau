-- MovingHeadShowFX (client half of the dual-script projector show):
-- animates the moving-head rig built by the server script. Uses the shared
-- ClubAudioSync beat clock, hue cadence (0.045/beat) and 16-beat pattern
-- rotation so the whole club hits together, synced to the club's ClubMusic
-- AudioPlayer backend. Heavy kicks fire the strobe bars in 12Hz bursts.
-- Runs client-side for 60fps pan/tilt sweeps.

local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

-- Tunables
local IDLE_BPM = 128 -- keeps the show gently cycling when no track plays
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

local function collectHeads()
	local list = {}
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
					currentTarget = target.Position,
				})
			end
		end
	end
	table.sort(list, function(a, b) return a.idx < b.idx end)
	return list
end

local function collectStrobeCells()
	local cells = {}
	for _, d in rig:GetChildren() do
		if d:IsA("BasePart") and d.Name:match("^Strobe%a_Cell%d+$") then
			table.insert(cells, d)
		end
	end
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
local startTime = clock()
local lastT = startTime
local showTime = 0

-- Stable deterministic values avoid allocating a Random object for every fixture on every frame.
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
	showTime = now - startTime
	beatAge += dt
	frameCount += 1
	if frameCount == 120 then print("[ClubNeon][MovingHeadShowFX] Heartbeat active; frames=" .. frameCount) end

	-- Audit every fixture independently; don't let a stale later fixture
	-- remain frozen just because the first head is still present.
	if now >= nextRigAudit then
		nextRigAudit = now + 2
		local discoveredHeads = collectHeads()
		local needsRefresh = #discoveredHeads ~= #heads
		for _, H in ipairs(heads) do
			if not H.head.Parent or not H.target.Parent or not H.pool.Parent
				or not H.beam.Parent or not H.spot.Parent then
				needsRefresh = true
				break
			end
		end
		if needsRefresh then
			heads = discoveredHeads
			strobeCells = collectStrobeCells()
			print("[ClubNeon][MovingHeadShowFX] Fixture references refreshed; active heads=" .. #heads)
		end
	end
	if #heads == 0 then return end

	-- Beat clock from the shared ClubAudioSync module
	local beat = ClubAudioSync.getBeatState()
	if beat.playing then
		if beat.beatCount ~= lastBeatCount then
			lastBeatCount = beat.beatCount
				beatCount = beat.beatCount
			beatAge = 0
			beatPower = math.clamp(0.8 + beat.energy * 1.6, 0.5, 3)
			-- Heavy kick: fire the strobe bars in a rapid burst
			if beatPower > 1.6 then
				burstUntil = now + STROBE_BURST
			end
		else
			beatAge = beat.beatPhase * (60 / beat.bpm)
		end
	else
		-- Idle clock: keep the show cycling at a gentle tempo when silent
		local idleBeat = math.floor(now * IDLE_BPM / 60)
		if idleBeat > beatCount then
			beatCount = idleBeat
			beatAge = 0
			beatPower = 0.6
		end
	end
	beatPower *= math.max(0, 1 - dt * 2)

	local kick = math.exp(-beatAge * 5) * beatPower
	local hue = (beatCount * 0.045) % 1 -- same cadence as the other FX
	local pattern = math.floor(beatCount / 16) % 6
	local beatBlend = if beat.playing then math.clamp(beat.beatPhase, 0, 1) else math.clamp(beatAge / (60 / IDLE_BPM), 0, 1)
	beatBlend = beatBlend * beatBlend * (3 - 2 * beatBlend)
	local bursting = now < burstUntil
	local strobeVis = bursting and (math.floor(now * STROBE_HZ) % 2 == 0) and 1 or 0

	-- Strobe cells flash hard during a burst, hidden otherwise
	for _, cell in strobeCells do
		cell.Transparency = 1 - strobeVis
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
	local beamFade = math.clamp(0.5 - kick * 0.35, 0.1, 0.5)
	for _, H in ipairs(heads) do
		H.beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, beamFade),
			NumberSequenceKeypoint.new(0.7, beamFade + 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
	end

	-- Choreography: a new pattern every 16 beats (one musical phrase)
	for i, H in ipairs(heads) do
		local ang = i / #heads * math.pi * 2
		local targetPos
		if pattern == 0 then
			-- Classic pan sweep: beams swing side to side over the crowd,
			-- alternating direction so they criss-cross in the air
			local sweep = math.sin(showTime * 0.75 + (i % 2) * math.pi)
			targetPos = CENTER + Vector3.new(sweep * RADIUS * 0.8, 1, math.cos(ang) * RADIUS * 0.3)
		elseif pattern == 1 then
			-- Circle chase: targets orbit the floor in a ring
			local spin = showTime * 0.5
			local r = RADIUS * 0.75
			targetPos = CENTER + Vector3.new(math.cos(ang + spin) * r, 1, math.sin(ang + spin) * r)
		elseif pattern == 2 then
			-- Beat snap: beams jump to a new spot every beat, strobing motion
			local function spotForBeat(n)
				local seed = n + i * 131
				local r = RADIUS * (0.15 + seededUnit(seed) * 0.8)
				local a = ang + seededUnit(seed + 1) * math.pi
				return CENTER + Vector3.new(math.cos(a) * r, 1, math.sin(a) * r)
			end
			-- Smoothly travel between deterministic beat targets at high BPM.
			targetPos = spotForBeat(beatCount):Lerp(spotForBeat(beatCount + 1), beatBlend)
		elseif pattern == 3 then
			-- Wall wash: beams rake up and down the venue walls
			local t = (showTime * 0.03 + i / #heads) % 1
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
			targetPos = Vector3.new(wx, floorY + 14 + math.sin(showTime * 1.2 + i) * 8, wz)
		elseif pattern == 4 then
			-- Ceiling rake: beams swing up and wash the roof itself, racing
			-- bright cones across the ceiling over the crowd
			local sweep = math.sin(showTime * 0.5 + i * math.pi / 3)
			targetPos = CENTER + Vector3.new(sweep * 45, CEIL_Y - 1, math.cos(ang + showTime * 0.3) * 45)
		else
			-- Converging center hit: all beams pull to the middle of the
			-- floor on the kick, then relax back outward
			local r = RADIUS * (0.05 + 0.55 * (1 - kick))
			targetPos = CENTER + Vector3.new(math.cos(ang) * r, 1, math.sin(ang) * r)
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
		H.pool.Transparency = onFloor and (0.55 - kick * 0.3) or 1
		if onFloor then
			local poolScale = 1 + kick * 0.5
			H.pool.Size = Vector3.new(0.1, 4 * poolScale, 4 * poolScale)
			H.pool.CFrame = CFrame.new(smoothTarget.X, floorY + 0.2, smoothTarget.Z)
				* CFrame.Angles(0, 0, math.pi / 2)
		end
		H.spot.Brightness = 1.5 + kick * 5
	end
end)