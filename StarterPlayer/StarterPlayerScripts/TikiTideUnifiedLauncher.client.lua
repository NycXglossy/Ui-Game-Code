--!strict
-- Unified Tiki Tide launcher.
-- Hides the three standalone launch buttons and routes into their existing UIs.
-- Staff visibility is presentation only; the server remains authoritative.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Create the main-menu bridge before the renderer mounts. The renderer
-- connects its Open callback and sets Ready=true once that callback is live.
local mainOpenBridge = playerGui:FindFirstChild("TikiTideOpenMainUI")
if mainOpenBridge and not mainOpenBridge:IsA("BindableEvent") then
	mainOpenBridge:Destroy()
	mainOpenBridge = nil
end
if not mainOpenBridge then
	mainOpenBridge = Instance.new("BindableEvent")
	mainOpenBridge.Name = "TikiTideOpenMainUI"
	mainOpenBridge.Parent = playerGui
end
mainOpenBridge:SetAttribute("Ready", false)

local ROOT_NAME = "TikiTideUnifiedLauncher"
local old = playerGui:FindFirstChild(ROOT_NAME)
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = ROOT_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 100
gui.Parent = playerGui

local launcher = Instance.new("TextButton")
launcher.Name = "OpenUnifiedMenu"
launcher.AnchorPoint = Vector2.new(1, 0)
launcher.Position = UDim2.new(1, -14, 0, 12)
launcher.Size = UDim2.fromOffset(116, 38)
launcher.BackgroundColor3 = Color3.fromRGB(25, 34, 49)
launcher.Text = "☰  TIKI TIDE"
launcher.TextColor3 = Color3.fromRGB(245, 213, 157)
launcher.TextSize = 11
launcher.Font = Enum.Font.GothamBold
launcher.AutoButtonColor = true
launcher.Parent = gui
Instance.new("UICorner", launcher).CornerRadius = UDim.new(0, 11)
local launcherStroke = Instance.new("UIStroke")
launcherStroke.Color = Color3.fromRGB(205, 169, 104)
launcherStroke.Transparency = 0.25
launcherStroke.Parent = launcher

local panel = Instance.new("Frame")
panel.Name = "UnifiedMenu"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -14, 0, 58)
panel.Size = UDim2.fromOffset(214, 160)
panel.BackgroundColor3 = Color3.fromRGB(13, 18, 28)
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 13)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(205, 169, 104)
panelStroke.Transparency = 0.35
panelStroke.Parent = panel

local heading = Instance.new("TextLabel")
heading.BackgroundTransparency = 1
heading.Position = UDim2.fromOffset(12, 7)
heading.Size = UDim2.new(1, -24, 0, 22)
heading.Text = "QUICK ACCESS"
heading.TextColor3 = Color3.fromRGB(226, 194, 132)
heading.TextSize = 11
heading.Font = Enum.Font.GothamBold
heading.TextXAlignment = Enum.TextXAlignment.Left
heading.Parent = panel

local function makeEntry(name: string, label: string, y: number, callback: () -> ())
 local button = Instance.new("TextButton")
 button.Name = name
 button.Position = UDim2.fromOffset(9, y)
 button.Size = UDim2.new(1, -18, 0, 34)
 button.BackgroundColor3 = Color3.fromRGB(31, 42, 59)
 button.Text = label
 button.TextColor3 = Color3.fromRGB(241, 242, 245)
 button.TextSize = 11
 button.Font = Enum.Font.GothamBold
 button.Parent = panel
 Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
 button.Activated:Connect(callback)
 return button
end

local function findButton(guiName: string, buttonName: string): GuiButton?
 local root = playerGui:FindFirstChild(guiName)
 if not root then return nil end
 local found = root:FindFirstChild(buttonName, true)
 if found and found:IsA("GuiButton") then return found end
 return nil
end

local function findGui(guiName: string): ScreenGui?
 local found = playerGui:FindFirstChild(guiName)
 if found and found:IsA("ScreenGui") then return found end
 return nil
end

local function closeSocialPanel()
 local socialGui = findGui("TikiTideSocialGui")
 if not socialGui then return end
 local socialPanel = socialGui:FindFirstChild("SocialPanel", true)
 if socialPanel and socialPanel:IsA("GuiObject") then socialPanel.Visible = false end
 local socialToggle = socialGui:FindFirstChild("SocialToggle", true)
 if socialToggle and socialToggle:IsA("TextButton") then socialToggle.Text = "SOCIAL  +" end
end

local function hideOriginalLaunchers()
 local mainButton = findButton("FirebeachMusicFestivalClubUI", "OpenButton")
 if mainButton then mainButton.Visible = false end
 local socialButton = findButton("TikiTideSocialGui", "SocialToggle")
 if socialButton then socialButton.Visible = false end
 local staffButton = findButton("StaffConsoleLauncher", "OpenStaffConsole")
 if staffButton then staffButton.Visible = false end
end

local function staffIsAuthorized(): boolean
 local staffGui = findGui("StaffConsoleGui")
 local launcherGui = findGui("StaffConsoleLauncher")
 return staffGui ~= nil
  and staffGui:GetAttribute("StaffAuthorized") == true
  and launcherGui ~= nil
  and launcherGui.Enabled
end

local mainEntry = makeEntry("MainUI", "MAIN FESTIVAL UI", 35, function()
 panel.Visible = false
 closeSocialPanel()
 task.spawn(function()
  -- The renderer can mount after this launcher. Wait for its callback to
  -- register instead of firing a BindableEvent before a listener exists.
  for _ = 1, 100 do
   if not gui.Parent then return end
   if mainOpenBridge.Parent == playerGui and mainOpenBridge:GetAttribute("Ready") == true then
    mainOpenBridge:Fire()
    return
   end
   task.wait(0.1)
  end
  warn("[TikiTideUnifiedLauncher] Main UI did not finish loading. Check UI_Renderer startup.")
 end)
end)

local socialEntry = makeEntry("SocialActions", "SOCIAL ACTIONS", 74, function()
 panel.Visible = false
 local socialGui = findGui("TikiTideSocialGui")
 local socialPanel = socialGui and socialGui:FindFirstChild("SocialPanel", true)
 if socialPanel and socialPanel:IsA("GuiObject") then
  socialPanel.Visible = true
  local socialToggle = socialGui and socialGui:FindFirstChild("SocialToggle", true)
  if socialToggle and socialToggle:IsA("TextButton") then socialToggle.Text = "SOCIAL  −" end
 else
  warn("[TikiTideUnifiedLauncher] Social Actions panel is not ready yet.")
 end
end)

local staffEntry = makeEntry("StaffUI", "STAFF CONSOLE", 113, function()
 panel.Visible = false
 if not staffIsAuthorized() then return end
 local staffGui = findGui("StaffConsoleGui")
 if staffGui then staffGui.Enabled = true end
end)

local function refresh()
 hideOriginalLaunchers()
 local authorized = staffIsAuthorized()
 staffEntry.Visible = authorized
 panel.Size = UDim2.fromOffset(214, if authorized then 160 else 121)
 socialEntry.Position = UDim2.fromOffset(9, 74)
 if not authorized then
  staffEntry.Visible = false
 end
end

launcher.Activated:Connect(function()
 refresh()
 panel.Visible = not panel.Visible
end)

playerGui.DescendantAdded:Connect(function()
 task.defer(refresh)
end)
playerGui.ChildAdded:Connect(function()
 task.defer(refresh)
end)

task.spawn(function()
 while gui.Parent do
  refresh()
  task.wait(1)
 end
end)

refresh()
