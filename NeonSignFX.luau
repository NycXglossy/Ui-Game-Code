--!strict
-- NeonSignFX: client-local marquee, gradient and glow choreography for server-owned sign geometry.
local ClubAudioSync = require(game:GetService("ReplicatedStorage"):WaitForChild("ClubAudioSync"))
local Workspace = game:GetService("Workspace")

local PALETTE_SPEED = 0.06
local sign: Instance? = nil
local back: Instance? = nil
local container: GuiObject? = nil
local light: PointLight? = nil
local frame: {Instance?} = {}
local letters = {}
local containerWidth = 1
local refreshAge = 0

local function collect()
	sign = Workspace:FindFirstChild("ClubNeonSign")
	back = sign and sign:FindFirstChild("Backing")
	local gui = back and back:FindFirstChild("SignGui")
	local viewport = gui and gui:FindFirstChild("ScrollViewport")
	local candidate = viewport and viewport:FindFirstChild("ScrollContainer")
	container = if candidate and candidate:IsA("GuiObject") then candidate else nil
	light = if back then back:FindFirstChildOfClass("PointLight") else nil
	frame = {
		sign and sign:FindFirstChild("FrameTop"),
		sign and sign:FindFirstChild("FrameBottom"),
		sign and sign:FindFirstChild("FrameLeft"),
		sign and sign:FindFirstChild("FrameRight"),
	}
	table.clear(letters)
	if container then
		containerWidth = math.max(container.Size.X.Scale, 0.05)
		for _, cell in ipairs(container:GetChildren()) do
			local label = cell:FindFirstChildOfClass("TextLabel")
			if label and label.Text ~= " " then
				table.insert(letters, {label=label, stroke=label:FindFirstChildOfClass("UIStroke"), gradient=label:FindFirstChildOfClass("UIGradient")})
			end
		end
	end
end

collect()
Workspace.ChildAdded:Connect(function(child)
	if child.Name == "ClubNeonSign" then task.defer(collect) end
end)
Workspace.ChildRemoved:Connect(function(child)
	if child == sign then task.defer(collect) end
end)

local flickerUntil = 0
local nextFlickerCheck = os.clock() + 6
while true do
	local dt = task.wait(0.1)
	refreshAge += dt
	if refreshAge >= 2 then refreshAge = 0; collect() end
	if not sign or not sign.Parent then continue end
	local beat = ClubAudioSync.getBeatState()
	local bpm = math.max(beat.bpm, 1)
	local beatTime = (beat.beatCount + beat.beatPhase) * 60 / bpm
	local now = os.clock()
	if now > nextFlickerCheck then
		nextFlickerCheck = now + 4 + math.random() * 8
		if math.random() < 0.55 then flickerUntil = now + 0.12 + math.random() * 0.25 end
	end
	local flickering = now < flickerUntil
	local breathe = 0.75 + 0.25 * math.sin(beatTime * 1.2 * bpm / 128)
	local glow = flickering and 0.15 or breathe
	local hue = (beatTime * PALETTE_SPEED * bpm / 128) % 1
	local color = Color3.fromHSV(hue, 1, 1)

	if container then
		local speed = 0.09
		local startX, endX = 1, -containerWidth
		local cycle = (startX - endX) / speed
		local p = (beatTime % cycle) / cycle
		container.Position = UDim2.fromScale(startX + (endX - startX) * p, 0)
	end
	for _, info in ipairs(letters) do
		if info.gradient then
			info.gradient.Rotation = (beatTime * 90 * bpm / 128) % 360
			info.gradient.Offset = Vector2.new((beatTime * 0.25 * bpm / 128) % 2 - 0.5, 0)
		end
		if info.stroke then
			info.stroke.Color = color
			info.stroke.Transparency = flickering and 0.7 or 0
		end
		info.label.TextColor3 = if flickering then Color3.fromRGB(90, 90, 100) else Color3.fromRGB(255, 255, 255)
	end
	if light then
		light.Color = color
		light.Brightness = 2 + glow * 3
		light.Range = 90 + glow * 60
	end
	for i, part in ipairs(frame) do
		if part and part:IsA("BasePart") then
			part.Color = Color3.fromHSV((hue + i * 0.06) % 1, 1, 1)
			part.Transparency = 1 - glow
		end
	end
end
