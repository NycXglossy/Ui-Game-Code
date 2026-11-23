-- AtmosFX: fog machines and flame jets tightly synced to the club's music.
-- Flames flicker continuously with the sound envelope, blast on every
-- beat (scaled by how hard it hits), and roar huge on heavy kicks.
-- Fog machines breathe a continuous haze that thickens with the music and
-- burst big clouds on the beat, heavier during loud parts. Uses the shared
-- ClubAudioSync beat clock so the whole club hits together.
-- Client-side for 60fps response.

local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

-- Tunables
local FOG_EVERY = 4 -- beats between fog bursts
local FOG_PUFF = 35 -- particles per fog burst
local FLAME_PUFF = 10 -- particles per flame beat (scaled by power)
local FLAME_PUFF_HOT = 30 -- particles on a heavy kick
local FLAME_AMBIENT = 22 -- max particles/sec flickering with the envelope
local FOG_AMBIENT = 3 -- max particles/sec continuous haze

-- Collect fixtures (streaming-robust: retry until they arrive).
-- All fixtures (foggers and flame jets) live as independent objects
-- directly in Workspace, ungrouped so they can be moved individually.
local function collectFixtures()
	local fogs, flames = {}, {}
	for _, unit in workspace:GetChildren() do
		if unit:IsA("BasePart") then
			local nozzle = unit:FindFirstChild("Nozzle")
			if not nozzle then continue end
			if unit.Name:match("^Fog%d+$") then
				local emitter = nozzle:FindFirstChild("Fog")
			if emitter then table.insert(fogs, { unit = unit, emitter = emitter }) end
			elseif unit.Name:match("^Flame%d+$") then
				local emitter = nozzle:FindFirstChild("Fire")
				local glow = unit:FindFirstChild("Glow")
			if emitter then table.insert(flames, { unit = unit, emitter = emitter, glow = glow }) end
			end
		end
	end
	return fogs, flames
end

local fogs, flames = collectFixtures()
while #fogs == 0 and #flames == 0 do
	task.wait(0.5)
	fogs, flames = collectFixtures()
end

-- Beat state (driven by ClubAudioSync's beat clock)
local norm = 0
local lastBeatCount = -1
local beatAge = math.huge
local beatPower = 0
local beatCount = 0

local clock = os.clock
local lastT = clock()

RunService.Heartbeat:Connect(function()
	local now = clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now
	beatAge += dt

	-- Self-heal if streaming replaces the fixtures
	if fogs[1] and fogs[1].unit.Parent == nil then
		fogs, flames = collectFixtures()
	end

	-- Beat clock from the shared ClubAudioSync module
	local beat = ClubAudioSync.getBeatState()
	norm = beat.energy

	if beat.beatCount ~= lastBeatCount then
		lastBeatCount = beat.beatCount
		beatCount = beat.beatCount
		beatAge = 0
		beatPower = math.clamp(0.8 + beat.energy * 1.6, 0.4, 3)

		-- Fog: every FOG_EVERY beats one machine bursts; during loud parts all
		-- of them breathe together for a heavy haze
		if #fogs > 0 and beatCount % FOG_EVERY == 0 then
			if norm > 0.6 then
				for _, fog in fogs do
					if fog.emitter.Parent then fog.emitter:Emit(FOG_PUFF) end
				end
			else
				local pickIndex = (math.floor(beatCount / FOG_EVERY) % #fogs) + 1
				local pick = fogs[pickIndex]
				if pick and pick.emitter.Parent then pick.emitter:Emit(FOG_PUFF) end
			end
		end
			else
				local pick = fogs[(beatCount / FOG_EVERY) % #fogs + 1]
				pick.emitter:Emit(FOG_PUFF)
			end
		end

		-- Flames: every jet blasts on every beat, particle count scaled by
		-- how hard the beat hits; heavy kicks light the whole ring huge
		local puff = math.ceil(FLAME_PUFF + (FLAME_PUFF_HOT - FLAME_PUFF)
			* math.clamp(beatPower - 0.4, 0, 1.6) / 1.6)
		for i, f in flames do
			-- Tiny stagger so the ring ripples, but tight enough to still
			-- read as one simultaneous hit
			local stagger = (i - 1) / #flames * 0.08
			task.delay(stagger, function()
				if f.unit.Parent then
					f.emitter:Emit(puff)
				end
			end)
		end
	else
		beatAge = beat.beatPhase * (60 / beat.bpm)
	end
	beatPower *= math.max(0, 1 - dt * 2.5)

	-- Continuous reactivity: flames flicker with the live sound envelope so
	-- they track every swell, riff and vocal, not just the drum hits
	local beatGlow = math.exp(-beatAge * 5) * beatPower
	local envelope = norm ^ 1.4 -- sharpened so quiet parts stay calm
	local flicker = 0.75 + 0.25 * math.sin(now * 31) -- subtle flame jitter
	for _, f in flames do
		if f.unit.Parent then
			f.emitter.Rate = FLAME_AMBIENT * envelope * flicker
			if f.glow then
				f.glow.Brightness = (beatGlow * 6 + envelope * 2.5) * flicker
			end
		end
	end

	-- Fog haze follows the music's loudness: quiet = wisps, loud = thick
	for _, f in fogs do
		if f.unit.Parent then
			f.emitter.Rate = FOG_AMBIENT * envelope
		end
	end
end)