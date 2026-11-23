-- GlowFloorFXScript: animates the neon perimeter strips around the dance
-- floor, color-cycling and beat-flashing in sync with the music. Syncs to
-- the club's ClubMusic AudioPlayer backend through the shared ClubAudioSync
-- module (beat clock derived from TimePosition).

local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

local PALETTE = {
	Color3.fromRGB(255, 0, 200),   -- magenta
	Color3.fromRGB(0, 255, 255),   -- cyan
	Color3.fromRGB(160, 0, 255),   -- purple
	Color3.fromRGB(0, 255, 130),   -- green
	Color3.fromRGB(255, 140, 0),   -- orange
	Color3.fromRGB(255, 255, 255), -- white flash
}

-- Collect the strips once the folder exists
local strips = {}
local lights = {}

local function loadStrips()
	table.clear(strips)
	table.clear(lights)
	local folder = workspace:FindFirstChild("GlowFloorFX")
	if not folder then return end
	for _, d in ipairs(folder:GetChildren()) do
		if d:IsA("BasePart") and string.match(d.Name, "^Strip_") then
			table.insert(strips, d)
			local pl = d:FindFirstChildOfClass("PointLight")
			if pl then table.insert(lights, pl) end
		end
	end
end

loadStrips()

local lastBeatCount = -1
local hueShift = 0

while true do
	local dt = task.wait(0.1) -- 10 Hz keeps beat flashes readable with fewer replicated updates
	local beat = ClubAudioSync.getBeatState()

	-- Beat clock: advances with the song's position when playing; an idle
	-- wall clock keeps the strips gently cycling when the club is silent
	local beatCount = beat.beatCount
	if not beat.playing then
		beatCount = math.floor(os.clock() * beat.bpm / 60)
	end

	-- New beat? Flash the strips brighter and shift the palette
	if beatCount ~= lastBeatCount then
		lastBeatCount = beatCount
		hueShift = (hueShift + 1) % #PALETTE
		local color = PALETTE[hueShift + 1]
		for i, strip in ipairs(strips) do
			-- Slight per-strip offset so edges chase each other
			local c = PALETTE[((hueShift + i - 1) % #PALETTE) + 1]
			strip.Color = c
			local pl = lights[i]
			if pl then
				pl.Color = c
				pl.Brightness = 2 -- flash on the beat
			end
		end
	end

	-- Decay the flash between beats
	for _, pl in ipairs(lights) do
		if pl.Brightness > 1 then
			pl.Brightness = math.max(1, pl.Brightness - dt * 8 * (beat.bpm / 128))
		end
	end
end
