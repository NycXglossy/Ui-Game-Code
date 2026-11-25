--!strict
-- BarNeonScript: client-local neon bar animation; geometry remains server-owned.
local Workspace = game:GetService("Workspace")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))
local bar = Workspace:WaitForChild("NeonBar")
local neons = {}
local function collect()
	table.clear(neons)
	for _, part in ipairs(bar:GetChildren()) do
		if part:IsA("BasePart") and part.Name == "BarNeon" and part.Material == Enum.Material.Neon then
			table.insert(neons, part)
		end
	end
end
collect()
bar.ChildAdded:Connect(function() task.defer(collect) end)
bar.ChildRemoved:Connect(function() task.defer(collect) end)
while true do
	task.wait(0.1)
	local beat = ClubAudioSync.getBeatState()
	local bpm = math.max(beat.bpm, 1)
	local musicalTime = (beat.beatCount + beat.beatPhase) * 60 / bpm * bpm / 128
	local pulse = 0.5 + 0.5 * math.sin(musicalTime * 2)
	for _, part in ipairs(neons) do
		if part.Parent then
			local hue = (musicalTime * 0.06 + (part.Position.X + part.Position.Y * 0.3) / 420) % 1
			part.Color = Color3.fromHSV(hue, 1, 0.75 + 0.25 * pulse)
		end
	end
end
