--!strict
-- GlowFloorFXScript: client-local animation for server-owned neon perimeter strips.
-- Recollects streamed/replaced strips and keeps each PointLight paired with its own part.
local Workspace = game:GetService("Workspace")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

local PALETTE = {
	Color3.fromRGB(255, 0, 200),
	Color3.fromRGB(0, 255, 255),
	Color3.fromRGB(160, 0, 255),
	Color3.fromRGB(0, 255, 130),
	Color3.fromRGB(255, 140, 0),
	Color3.fromRGB(255, 255, 255),
}
local fixtures = {}
local function collect()
	table.clear(fixtures)
	local folder = Workspace:FindFirstChild("GlowFloorFX")
	if not folder then return end
	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart") and part.Name:match("^Strip_") then
			table.insert(fixtures, {part=part, light=part:FindFirstChildOfClass("PointLight")})
		end
	end
	table.sort(fixtures, function(a, b) return a.part.Name < b.part.Name end)
end

collect()
local lastBeatCount = -1
local hueShift = 0
local refreshAge = 0
while true do
	local dt = task.wait(0.1)
	refreshAge += dt
	if refreshAge >= 2 then refreshAge = 0; collect() end
	local beat = ClubAudioSync.getBeatState()
	local beatCount = beat.beatCount
	if not beat.playing then beatCount = math.floor(os.clock() * beat.bpm / 60) end
	if beatCount ~= lastBeatCount then
		lastBeatCount = beatCount
		hueShift = (hueShift + 1) % #PALETTE
		for index, fixture in ipairs(fixtures) do
			if fixture.part.Parent then
				local color = PALETTE[((hueShift + index - 1) % #PALETTE) + 1]
				fixture.part.Color = color
				if fixture.light and fixture.light.Parent then
					fixture.light.Color = color
					fixture.light.Brightness = 0.48
				end
			end
		end
	end
	for _, fixture in ipairs(fixtures) do
		local light = fixture.light
		if light and light.Parent and light.Brightness > 0.28 then
			light.Brightness = math.max(0.28, light.Brightness - dt * 3.2 * (beat.bpm / 128))
		end
	end
end
