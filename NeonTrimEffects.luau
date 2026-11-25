--!strict
-- NeonTrimEffects: client-local color and light animation for server-owned wall trim.
local Workspace = game:GetService("Workspace")
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))
local folder = Workspace:WaitForChild("NeonTrim")
local trims = {}
local lights = {}
local function collect()
	table.clear(trims); table.clear(lights)
	for _, obj in ipairs(folder:GetChildren()) do
		if obj:IsA("BasePart") and obj.Name ~= "TrimLightAnchor" then
			table.insert(trims, obj)
		elseif obj:IsA("BasePart") then
			local light = obj:FindFirstChildOfClass("PointLight")
			if light then table.insert(lights, light) end
		end
	end
end
collect()
folder.ChildAdded:Connect(function() task.defer(collect) end)
folder.ChildRemoved:Connect(function() task.defer(collect) end)
local SPEED = 0.06
local WAVELENGTH = 420
local refreshAge = 0
while true do
	local dt = task.wait(0.1)
	refreshAge += dt
	if refreshAge >= 3 then refreshAge = 0; collect() end
	local beat = ClubAudioSync.getBeatState()
	local bpm = math.max(beat.bpm, 1)
	local beatTime = (beat.beatCount + beat.beatPhase) * 60 / bpm
	local t = beatTime * bpm / 128
	local pulse = 0.5 + 0.5 * math.sin(t * 2)
	for _, part in ipairs(trims) do
		if part.Parent then
			local hue = (t * SPEED + (part.Position.X + part.Position.Z) / WAVELENGTH) % 1
			part.Color = Color3.fromHSV(hue, 1, 0.75 + 0.25 * pulse)
		end
	end
	for _, light in ipairs(lights) do
		if light.Parent and light.Parent:IsA("BasePart") then
			local pos = light.Parent.Position
			local hue = (t * SPEED + (pos.X + pos.Z) / WAVELENGTH) % 1
			light.Color = Color3.fromHSV(hue, 1, 1)
			light.Brightness = 1 + 1.2 * pulse
		end
	end
end
