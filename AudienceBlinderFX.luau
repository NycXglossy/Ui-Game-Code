-- AudienceBlinderFX: client-side beat animation for server-owned AudienceBlinderRig.
local RunService = game:GetService("RunService")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))

local folder = workspace:WaitForChild("AudienceBlinderRig")
local fixtures = {}
local function collect()
	table.clear(fixtures)
	for _, housing in ipairs(folder:GetChildren()) do
		if housing:IsA("BasePart") and housing.Name:match("^Blinder%d+$") then
			local lens = housing:FindFirstChild("Lens")
			local light = housing:FindFirstChild("AudienceWash")
			if lens and light and light:IsA("SpotLight") then
				table.insert(fixtures, {housing = housing, lens = lens, light = light, index = tonumber(housing.Name:match("%d+")) or #fixtures + 1})
			end
		end
	end
	table.sort(fixtures, function(a, b) return a.index < b.index end)
end
collect()
folder.DescendantAdded:Connect(function() task.defer(collect) end)
folder.DescendantRemoving:Connect(function() task.defer(collect) end)

local palette = {
	Color3.fromRGB(255, 245, 220),
	Color3.fromRGB(0, 235, 255),
	Color3.fromRGB(255, 45, 175),
	Color3.fromRGB(150, 90, 255),
}
local lastBeat = -1
local lastT = os.clock()
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local dt = math.min(now - lastT, 0.1)
	lastT = now
	local beat = ClubAudioSync.getBeatState()
	if beat.beatCount ~= lastBeat then lastBeat = beat.beatCount end
	local pulse = math.exp(-beat.beatPhase * 5) * math.clamp(0.35 + beat.energy * 0.9, 0.25, 1)
	local tempoTime = now * (beat.bpm / 128)
	local hueStep = math.floor(beat.beatCount / 4)
	for _, fixture in ipairs(fixtures) do
		local wave = 0.5 + 0.5 * math.sin(tempoTime * 1.4 + fixture.index * 0.8)
		local intensity = math.clamp(0.05 + beat.energy * 0.08 + pulse * (0.22 + wave * 0.22), 0, 0.52)
		fixture.light.Brightness = intensity * 3.2
		local color = if pulse > 0.18 then palette[(hueStep + fixture.index - 1) % #palette + 1] else palette[(fixture.index - 1) % #palette + 1]
		fixture.light.Color = color
		fixture.lens.Color = color
	end
end)
