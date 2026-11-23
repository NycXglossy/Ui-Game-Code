--!strict
-- RaveIntroUI: accessible flashing-lights warning followed by a cinematic Club Neon beach-club intro.
-- Install as a LocalScript in StarterPlayer > StarterPlayerScripts.
-- The warning is shown before the animated intro; no strobe/flashing effect is created by this UI.

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
if not player then
	warn("[Club Neon Rave Intro] LocalPlayer unavailable; intro skipped.")
	return
end

local playerGui = player:WaitForChild("PlayerGui", 15)
if not playerGui or not playerGui:IsA("PlayerGui") then
	warn("[Club Neon Rave Intro] PlayerGui unavailable; intro skipped.")
	return
end

local GUI_NAME = "RaveIntroGui"
local existing = playerGui:FindFirstChild(GUI_NAME)
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function mk(className: string, props: {[string]: any}, parent: Instance): Instance
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		(inst :: any)[key] = value
	end
	inst.Parent = parent
	return inst
end

local function tween(instance: Instance, duration: number, properties: {[string]: any}, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local animation = TweenService:Create(instance, info, properties)
	animation:Play()
	return animation
end

-- PHASE 1: flashing-lights accessibility warning. The warning itself does not flash.
local warningFrame = mk("Frame", {
	Name = "WarningFrame",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(13, 18, 28),
	BorderSizePixel = 0,
	ZIndex = 10,
}, gui) :: Frame

mk("Frame", {
	Name = "Vignette",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(24, 29, 41),
	BackgroundTransparency = 0.9,
	BorderSizePixel = 0,
	ZIndex = 10,
}, warningFrame)

local warningCard = mk("Frame", {
	Name = "WarningCard",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.9, 0.72),
	BackgroundColor3 = Color3.fromRGB(13, 16, 24),
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	ZIndex = 11,
}, warningFrame) :: Frame
mk("UISizeConstraint", {MinSize = Vector2.new(280, 300), MaxSize = Vector2.new(560, 390)}, warningCard)
mk("UICorner", {CornerRadius = UDim.new(0, 20)}, warningCard)
mk("UIStroke", {Thickness = 2, Color = Color3.fromRGB(226, 194, 132), Transparency = 0.35}, warningCard)

local warningIcon = mk("TextLabel", {
	Name = "WarningIcon",
	Size = UDim2.new(1, -32, 0, 66),
	Position = UDim2.new(0, 16, 0, 16),
	BackgroundTransparency = 1,
	Text = "⚠",
	TextColor3 = Color3.fromRGB(226, 194, 132),
	TextScaled = true,
	Font = Enum.Font.GothamBold,
	ZIndex = 12,
}, warningCard) :: TextLabel
mk("UITextSizeConstraint", {MaxTextSize = 58, MinTextSize = 34}, warningIcon)

local warningTitle = mk("TextLabel", {
	Name = "WarningTitle",
	Size = UDim2.new(1, -36, 0, 42),
	Position = UDim2.new(0, 18, 0, 88),
	BackgroundTransparency = 1,
	Text = "WARNING: FLASHING LIGHTS",
	TextColor3 = Color3.fromRGB(242, 241, 236),
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	ZIndex = 12,
}, warningCard) :: TextLabel
mk("UITextSizeConstraint", {MaxTextSize = 25, MinTextSize = 16}, warningTitle)

local warningBody = mk("TextLabel", {
	Name = "WarningBody",
	Size = UDim2.new(1, -48, 0, 112),
	Position = UDim2.new(0, 24, 0, 140),
	BackgroundTransparency = 1,
	Text = "This experience contains rapidly flashing colors, strobe lights, and bright neon effects. If you are sensitive to flashing lights or have photosensitive epilepsy, please use caution.",
	TextColor3 = Color3.fromRGB(190, 197, 207),
	TextScaled = true,
	TextWrapped = true,
	Font = Enum.Font.Gotham,
	ZIndex = 12,
}, warningCard) :: TextLabel
mk("UITextSizeConstraint", {MaxTextSize = 18, MinTextSize = 13}, warningBody)

local enterButton = mk("TextButton", {
	Name = "EnterButton",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -20),
	Size = UDim2.new(0.82, 0, 0, 54),
	BackgroundColor3 = Color3.fromRGB(119, 196, 203),
	Text = "ENTER THE CLUB",
	TextColor3 = Color3.fromRGB(13, 18, 28),
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	AutoButtonColor = true,
	ZIndex = 12,
}, warningCard) :: TextButton
mk("UICorner", {CornerRadius = UDim.new(0, 14)}, enterButton)
mk("UIStroke", {Thickness = 2, Color = Color3.fromRGB(119, 196, 203), Transparency = 0.45}, enterButton)
mk("UITextSizeConstraint", {MaxTextSize = 23, MinTextSize = 16}, enterButton)

local warningAlive = true
task.spawn(function()
	while warningAlive and enterButton.Parent do
		tween(enterButton, 0.9, {BackgroundColor3 = Color3.fromRGB(75, 143, 151)}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()
		if not warningAlive or not enterButton.Parent then break end
		tween(enterButton, 0.9, {BackgroundColor3 = Color3.fromRGB(119, 196, 203)}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()
	end
end)

local enterClicked = false
enterButton.Activated:Connect(function()
	if enterClicked then return end
	enterClicked = true
	enterButton.Text = "LET'S GO!"
end)

while not enterClicked and gui.Parent do
	task.wait(0.1)
end
if not gui.Parent then return end
warningAlive = false

for _, descendant in ipairs(warningFrame:GetDescendants()) do
	if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
		tween(descendant, 0.45, {TextTransparency = 1, BackgroundTransparency = 1})
	elseif descendant:IsA("Frame") then
		tween(descendant, 0.45, {BackgroundTransparency = 1})
	elseif descendant:IsA("UIStroke") then
		tween(descendant, 0.45, {Transparency = 1})
	end
end
tween(warningFrame, 0.45, {BackgroundTransparency = 1}).Completed:Wait()
if not gui.Parent then return end
warningFrame:Destroy()

-- PHASE 2: cinematic sunset beach-club title sequence.
local scene = mk("Frame", {
	Name = "BeachScene",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(13, 18, 28),
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 5,
}, gui) :: Frame

local sky = mk("Frame", {
	Name = "SunsetSky",
	Size = UDim2.fromScale(1, 0.76),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ZIndex = 5,
}, scene)
mk("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(13, 18, 28)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(24, 29, 41)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(119, 196, 203)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(226, 194, 132)),
	}),
}, sky)

local sun = mk("Frame", {
	Name = "Sun",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.56),
	Size = UDim2.fromScale(0.16, 0.16),
	BackgroundColor3 = Color3.fromRGB(226, 194, 132),
	BorderSizePixel = 0,
	ZIndex = 6,
}, scene) :: Frame
mk("UICorner", {CornerRadius = UDim.new(1, 0)}, sun)
mk("UIStroke", {Thickness = 6, Color = Color3.fromRGB(119, 196, 203), Transparency = 0.5}, sun)
tween(sun, 6, {Position = UDim2.fromScale(0.5, 0.66)}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local waveColors = {
	Color3.fromRGB(45, 78, 91),
	Color3.fromRGB(29, 53, 67),
	Color3.fromRGB(18, 35, 49),
}
local waves: {Frame} = {}
for index = 1, 3 do
	local wave = mk("Frame", {
		Name = "OceanWave" .. index,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 0.72 + index * 0.02),
		Size = UDim2.fromScale(1, 0.1 + index * 0.05),
		BackgroundColor3 = waveColors[index],
		BorderSizePixel = 0,
		ZIndex = 6 + index,
	}, scene) :: Frame
	waves[index] = wave
end

local sceneAlive = true
task.spawn(function()
	local timeValue = 0
	while sceneAlive and scene.Parent do
		timeValue += 0.03
		for index, wave in ipairs(waves) do
			local bob = math.sin(timeValue * (1 + index * 0.35)) * 0.006
			wave.Position = UDim2.fromScale(0, 0.72 + index * 0.02 + bob)
		end
		task.wait(0.03)
	end
end)

mk("Frame", {
	Name = "Sand",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(1, 0.16),
	BackgroundColor3 = Color3.fromRGB(205, 169, 104),
	BorderSizePixel = 0,
	ZIndex = 10,
}, scene)

local function buildPalm(xScale: number, scaleValue: number, flip: boolean)
	local palm = mk("Frame", {
		Name = flip and "PalmRight" or "PalmLeft",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(xScale, 0.82),
		Size = UDim2.fromScale(0.18 * scaleValue, 0.44 * scaleValue),
		BackgroundTransparency = 1,
		ZIndex = 11,
	}, scene) :: Frame

	local silhouette = Color3.fromRGB(13, 18, 28)
	local trunk = mk("Frame", {
		Name = "Trunk",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.09, 0.9),
		Rotation = flip and -8 or 8,
		BackgroundColor3 = silhouette,
		BorderSizePixel = 0,
		ZIndex = 11,
	}, palm)
	mk("UICorner", {CornerRadius = UDim.new(0.3, 0)}, trunk)

	local leafAngles = {-72, -48, -24, 0, 24, 48, 72}
	for _, angle in ipairs(leafAngles) do
		local leaf = mk("Frame", {
			Name = "PalmLeaf",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.5, 0.1),
			Size = UDim2.fromScale(0.56, 0.045),
			Rotation = angle * (flip and -1 or 1),
			BackgroundColor3 = silhouette,
			BorderSizePixel = 0,
			ZIndex = 11,
		}, palm)
		mk("UICorner", {CornerRadius = UDim.new(1, 0)}, leaf)
	end
end

buildPalm(0.1, 1.05, false)
buildPalm(0.9, 1.2, true)

local title = mk("TextLabel", {
	Name = "ClubNeonTitle",
	Size = UDim2.fromScale(0.9, 0.17),
	Position = UDim2.fromScale(0.05, 0.3),
	BackgroundTransparency = 1,
	Text = "CLUB NEON",
	TextColor3 = Color3.fromRGB(226, 194, 132),
	TextScaled = true,
	Font = Enum.Font.GothamBlack,
	TextTransparency = 1,
	ZIndex = 12,
}, scene) :: TextLabel
mk("UITextSizeConstraint", {MaxTextSize = 68, MinTextSize = 28}, title)
local titleStroke = mk("UIStroke", {Thickness = 4, Color = Color3.fromRGB(119, 196, 203), Transparency = 1}, title)

local subtitle = mk("TextLabel", {
	Name = "Subtitle",
	Size = UDim2.fromScale(0.9, 0.07),
	Position = UDim2.fromScale(0.05, 0.49),
	BackgroundTransparency = 1,
	Text = "THE CLUB NEON EXPERIENCE",
	TextColor3 = Color3.fromRGB(242, 241, 236),
	TextScaled = true,
	Font = Enum.Font.GothamBold,
	TextTransparency = 1,
	ZIndex = 12,
}, scene) :: TextLabel
mk("UITextSizeConstraint", {MaxTextSize = 24, MinTextSize = 13}, subtitle)

local skipButton = mk("TextButton", {
	Name = "SkipIntro",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -18, 1, -18),
	Size = UDim2.fromOffset(130, 40),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.4,
	Text = "SKIP  >>",
	TextColor3 = Color3.fromRGB(242, 241, 236),
	TextSize = 18,
	Font = Enum.Font.GothamBold,
	AutoButtonColor = true,
	ZIndex = 12,
}, scene) :: TextButton
mk("UICorner", {CornerRadius = UDim.new(0, 8)}, skipButton)

local skipped = false
skipButton.Activated:Connect(function()
	skipped = true
end)

tween(title, 0.55, {TextTransparency = 0}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
tween(titleStroke, 0.55, {Transparency = 0.2})
tween(subtitle, 0.55, {TextTransparency = 0}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

task.spawn(function()
	while sceneAlive and titleStroke.Parent do
		tween(titleStroke, 0.9, {Transparency = 0.7}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()
		if not sceneAlive or not titleStroke.Parent then break end
		tween(titleStroke, 0.9, {Transparency = 0.15}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()
	end
end)

local hype = {
	"THE CLUB NEON EXPERIENCE",
	"TEAL GLOW • ROYAL GOLD",
	"LIGHTS UP • MUSIC ON",
	"WELCOME TO CLUB NEON",
}
local elapsed = 0
while elapsed < 5 and not skipped and gui.Parent do
	local index = (math.floor(elapsed) % #hype) + 1
	if subtitle.Text ~= hype[index] then subtitle.Text = hype[index] end
	task.wait(0.1)
	elapsed += 0.1
end

sceneAlive = false
if not gui.Parent then return end
for _, descendant in ipairs(scene:GetDescendants()) do
	if descendant:IsA("TextLabel") then
		tween(descendant, 0.65, {TextTransparency = 1})
	elseif descendant:IsA("TextButton") then
		tween(descendant, 0.4, {TextTransparency = 1, BackgroundTransparency = 1})
	elseif descendant:IsA("Frame") and descendant.BackgroundTransparency < 1 then
		tween(descendant, 0.65, {BackgroundTransparency = 1})
	elseif descendant:IsA("UIStroke") then
		tween(descendant, 0.65, {Transparency = 1})
	end
end
tween(scene, 0.75, {BackgroundTransparency = 1}).Completed:Wait()
if gui.Parent then gui:Destroy() end
