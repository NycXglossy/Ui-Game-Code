--!strict
-- Club Neon Social Actions client. Place in StarterPlayer/StarterPlayerScripts.
-- This UI only sends requests; the server owns entitlement, consent, range and playback.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("ClubNeonSocialRemotes")
local request = remotes:WaitForChild("Request") :: RemoteEvent
local event = remotes:WaitForChild("Event") :: RemoteEvent

local old = playerGui:FindFirstChild("ClubNeonSocialGui")
if old then old:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = "ClubNeonSocialGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 61
gui.Parent = playerGui

local function makeButton(parent: Instance, text: string, position: UDim2, size: UDim2, callback: () -> ())
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = Color3.fromRGB(31, 37, 52)
	button.TextColor3 = Color3.fromRGB(242, 241, 236)
	button.TextSize = 12
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = parent
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 9); corner.Parent = button
	button.Activated:Connect(callback)
	return button
end

local toggle = Instance.new("TextButton")
toggle.Name = "SocialToggle"
toggle.Size = UDim2.fromOffset(104, 34)
toggle.Position = UDim2.new(1, -116, 0, 72)
toggle.BackgroundColor3 = Color3.fromRGB(31, 37, 52)
toggle.TextColor3 = Color3.fromRGB(242, 241, 236)
toggle.Text = "SOCIAL  +"
toggle.TextSize = 11
toggle.Font = Enum.Font.GothamBold
toggle.Parent = gui
local toggleCorner = Instance.new("UICorner"); toggleCorner.CornerRadius = UDim.new(0, 10); toggleCorner.Parent = toggle

local panel = Instance.new("Frame")
panel.Name = "SocialPanel"
panel.Size = UDim2.fromOffset(210, 214)
panel.Position = UDim2.new(1, -224, 0, 112)
panel.Visible = false
panel.BackgroundColor3 = Color3.fromRGB(13, 16, 24)
panel.Parent = gui
local function setPanelOpen(isOpen: boolean)
	panel.Visible = isOpen
	toggle.Text = if isOpen then "SOCIAL  −" else "SOCIAL  +"
end

toggle.Activated:Connect(function()
	setPanelOpen(not panel.Visible)
end)

-- A dedicated close control remains available when the standalone toggle is
-- hidden by the unified launcher.
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseSocialPanel"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -7, 0, 5)
closeButton.Size = UDim2.fromOffset(25, 24)
closeButton.BackgroundColor3 = Color3.fromRGB(42, 48, 62)
closeButton.Text = "×"
closeButton.TextColor3 = Color3.fromRGB(242, 241, 236)
closeButton.TextSize = 18
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = panel
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 7)
closeCorner.Parent = closeButton
closeButton.Activated:Connect(function()
	setPanelOpen(false)
end)

local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 14); corner.Parent = panel
local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(226, 194, 132); stroke.Transparency = 0.35; stroke.Parent = panel
local heading = Instance.new("TextLabel")
heading.BackgroundTransparency = 1
heading.Size = UDim2.new(1, -16, 0, 28)
heading.Position = UDim2.fromOffset(8, 5)
heading.Text = "CLUB NEON SOCIAL"
heading.TextColor3 = Color3.fromRGB(226, 194, 132)
heading.Font = Enum.Font.GothamBold
heading.TextSize = 12
heading.Parent = panel

makeButton(panel, "Dance 1", UDim2.fromOffset(10, 38), UDim2.new(0.5, -14, 0, 30), function()
	request:FireServer("Play", {name = "Dance1"})
end)
makeButton(panel, "Dance 2", UDim2.new(0.5, 4, 0, 38), UDim2.new(0.5, -14, 0, 30), function()
	request:FireServer("Play", {name = "Dance2"})
end)
makeButton(panel, "VIP Dance", UDim2.fromOffset(10, 74), UDim2.new(1, -20, 0, 30), function()
	request:FireServer("Play", {name = "VIPDance"})
end)
makeButton(panel, "Hug a nearby player", UDim2.fromOffset(10, 110), UDim2.new(1, -20, 0, 30), function()
	local nearest: Player? = nil
	local myCharacter = player.Character
	local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
	if not myRoot or not myRoot:IsA("BasePart") then return end
	local bestDistance = 12
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local distance = (root.Position - myRoot.Position).Magnitude
				if distance < bestDistance then bestDistance = distance; nearest = other end
			end
		end
	end
	if nearest then
		request:FireServer("Invite", {userId = nearest.UserId, name = "Hug"})
	else
		local status = panel:FindFirstChild("Status")
		if status and status:IsA("TextLabel") then status.Text = "No player close enough." end
	end
end)
makeButton(panel, "Cancel my pending invite", UDim2.fromOffset(10, 146), UDim2.new(1, -20, 0, 28), function()
	request:FireServer("Cancel", {})
end)
local status = Instance.new("TextLabel")
status.Name = "Status"
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(10, 178)
status.Size = UDim2.new(1, -20, 0, 24)
status.Text = "Choose an action"
status.TextColor3 = Color3.fromRGB(157, 164, 177)
status.Font = Enum.Font.Gotham
status.TextSize = 9
status.Parent = panel

local inviteGui: Frame? = nil
local function closeInvite()
	if inviteGui then inviteGui:Destroy(); inviteGui = nil end
end

event.OnClientEvent:Connect(function(kind: any, ...)
	if kind == "Notice" then
		local message = select(1, ...)
		if typeof(message) == "string" then status.Text = string.sub(message, 1, 90) end
	elseif kind == "Invite" then
		local id, senderUserId, senderDisplay, actionName, ttl = ...
		if typeof(id) ~= "string" or typeof(senderUserId) ~= "number" or actionName ~= "Hug" then return end
		closeInvite()
		local prompt = Instance.new("Frame")
		inviteGui = prompt
		prompt.AnchorPoint = Vector2.new(0.5, 0.5)
		prompt.Position = UDim2.fromScale(0.5, 0.5)
		prompt.Size = UDim2.fromOffset(300, 126)
		prompt.BackgroundColor3 = Color3.fromRGB(13, 16, 24)
		prompt.Parent = gui
		prompt:SetAttribute("InviteId", id)
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = prompt
		local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(226, 194, 132); s.Parent = prompt
		local textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.Position = UDim2.fromOffset(12, 8)
		textLabel.Size = UDim2.new(1, -24, 0, 42)
		textLabel.Text = tostring(senderDisplay) .. " invited you to hug. Expires in " .. tostring(ttl or 20) .. "s."
		textLabel.TextColor3 = Color3.fromRGB(242, 241, 236)
		textLabel.TextWrapped = true
		textLabel.Font = Enum.Font.GothamBold
		textLabel.TextSize = 12
		textLabel.Parent = prompt
		makeButton(prompt, "ACCEPT", UDim2.fromOffset(12, 65), UDim2.new(0.5, -18, 0, 38), function()
			request:FireServer("Respond", {id = id, accepted = true})
			closeInvite()
		end)
		makeButton(prompt, "DECLINE", UDim2.new(0.5, 6, 0, 65), UDim2.new(0.5, -18, 0, 38), function()
			request:FireServer("Respond", {id = id, accepted = false})
			closeInvite()
		end)
	elseif kind == "InviteClosed" then
		local id = select(1, ...)
		if inviteGui and inviteGui:GetAttribute("InviteId") == id then closeInvite() end
	end
end)
