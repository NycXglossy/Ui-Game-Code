-- Animates the NeonBar's neon accents: slow hue shift + breathing pulse
local bar = workspace:FindFirstChild("NeonBar")
if not bar then return end

local neons = {}
for _, p in bar:GetChildren() do
	if p:IsA("BasePart") and p.Name == "BarNeon" and p.Material == Enum.Material.Neon then
		table.insert(neons, p)
	end
end
if #neons == 0 then return end

while task.wait(0.06) do
	local t = os.clock()
	local pulse = 0.5 + 0.5 * math.sin(t * 2) -- matches the wall trim pulse
	for i, p in neons do
		-- offset hue by position so colors flow along the bar
		local hue = (t * 0.06 + (p.Position.X + p.Position.Y * 0.3) / 420) % 1
		p.Color = Color3.fromHSV(hue, 1, 0.75 + 0.25 * pulse)
	end
end