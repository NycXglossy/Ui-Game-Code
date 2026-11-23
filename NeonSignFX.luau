local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))
-- NeonSignFX: animated effects for the CLUB NEON wall sign.
-- The giant letters scroll across the sign like a marquee, a rainbow
-- gradient sweeps through them, the neon frame cycles color, the glow
-- pulses, and the sign flickers like a real neon tube.

local sign = workspace:FindFirstChild("ClubNeonSign")
if not sign then return end

local back = sign:FindFirstChild("Backing")
local gui = back and back:FindFirstChild("SignGui")
local viewport = gui and gui:FindFirstChild("ScrollViewport")
local container = viewport and viewport:FindFirstChild("ScrollContainer")
local light = back and back:FindFirstChildOfClass("PointLight")
local frame = {
	sign:FindFirstChild("FrameTop"),
	sign:FindFirstChild("FrameBottom"),
	sign:FindFirstChild("FrameLeft"),
	sign:FindFirstChild("FrameRight"),
}

-- Collect each letter label with its stroke and gradient
local letters = {}
if container then
	for _, cell in container:GetChildren() do
		local l = cell:FindFirstChildOfClass("TextLabel")
		if l and l.Text ~= " " then
			table.insert(letters, {
				label = l,
				stroke = l:FindFirstChildOfClass("UIStroke"),
				grad = l:FindFirstChildOfClass("UIGradient"),
			})
		end
	end
end

local CONTAINER_W = container and container.Size.X.Scale or 1

-- Flicker state: occasionally a tube sputters for a moment
local flickerUntil = 0
local nextFlickerCheck = os.clock() + 6

while true do
	task.wait(0.1) -- 10 Hz is adequate for marquee/glow and reduces server-side UI property churn
	local now = os.clock()
	local beat = ClubAudioSync.getBeatState()
	local tempoNow = now * (beat.bpm / 128)

	-- Schedule a random flicker every so often
	if now > nextFlickerCheck then
		nextFlickerCheck = now + 4 + math.random() * 8
		if math.random() < 0.55 then
			flickerUntil = now + 0.12 + math.random() * 0.25
		end
	end
	local flickering = now < flickerUntil

	-- Slow breathing glow + flicker dim
	local breathe = 0.75 + 0.25 * math.sin(tempoNow * 1.2)
	local glow = flickering and 0.15 or breathe

	-- Cycle color through the spectrum
	local hue = (tempoNow * 0.06) % 1
	local c = Color3.fromHSV(hue, 1, 1)

	-- Scroll the letters across the sign: the container slides in from
	-- the right edge, travels left across the whole sign, then wraps and repeats
	if container then
		local speed = 0.09 -- fraction of the sign width per second
		local start_x = 1 -- just off the right edge
		local end_x = -CONTAINER_W -- fully past the left edge
		local cycle = (start_x - end_x) / speed
		local p = (tempoNow % cycle) / cycle
		container.Position = UDim2.fromScale(start_x + (end_x - start_x) * p, 0)
	end

	-- Rainbow gradient sweeps across the letters as they scroll
	for _, info in ipairs(letters) do
		if info.grad then
			info.grad.Rotation = (tempoNow * 90) % 360
			info.grad.Offset = Vector2.new((tempoNow * 0.25) % 2 - 0.5, 0)
		end
		if info.stroke then
			info.stroke.Color = c
			info.stroke.Transparency = flickering and 0.7 or 0
		end
		if info.label then
			info.label.TextColor3 = flickering
				and Color3.fromRGB(90, 90, 100)
				or Color3.fromRGB(255, 255, 255)
		end
	end

	-- Frame and light wash with the cycled color
	if light then
		light.Color = c
		light.Brightness = 2 + glow * 3
		light.Range = 90 + glow * 60
	end
	for i, f in ipairs(frame) do
		if f then
			-- Slight per-strip hue offset for a chasing border look
			f.Color = Color3.fromHSV((hue + i * 0.06) % 1, 1, 1)
			f.Transparency = 1 - glow
		end
	end

end