-- Animates the wall neon trim with a traveling rainbow wave and pulsing glow
local folder = workspace:FindFirstChild("NeonTrim")

local trims = {}
local lights = {}

if folder then
	for _, obj in folder:GetChildren() do
		if obj:IsA("BasePart") and obj.Name ~= "TrimLightAnchor" then
			table.insert(trims, obj)
		elseif obj:IsA("BasePart") then
			local pl = obj:FindFirstChildOfClass("PointLight")
			if pl then table.insert(lights, pl) end
		end
	end
end

local SPEED = 0.06 -- hue cycles per second
local WAVELENGTH = 420 -- studs per full hue rotation along the walls

while task.wait(0.05) do
	local t = os.clock()
	local pulse = 0.5 + 0.5 * math.sin(t * 2) -- 0..1 breathing pulse

	for _, p in trims do
		local hue = (t * SPEED + (p.Position.X + p.Position.Z) / WAVELENGTH) % 1
		p.Color = Color3.fromHSV(hue, 1, 0.75 + 0.25 * pulse)
	end

	for _, l in lights do
		local anchorPos = l.Parent.Position
		local hue = (t * SPEED + (anchorPos.X + anchorPos.Z) / WAVELENGTH) % 1
		l.Color = Color3.fromHSV(hue, 1, 1)
		l.Brightness = 1 + 1.2 * pulse
	end
end