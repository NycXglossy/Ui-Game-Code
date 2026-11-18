--!strict
-- Phase 22 graphical ClubMusic staff console.
-- Buttons select fixed command IDs; the server maps those IDs to allowlisted
-- ClubMusicAdminBridge operations. This client never supplies an operation name
-- and never makes authorization decisions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local securityAction = ReplicatedStorage:WaitForChild("SecurityAction") :: RemoteEvent
local actionResult = ReplicatedStorage:WaitForChild("SecurityActionResult") :: RemoteEvent
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("StaffConsoleGui")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "StaffConsoleGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 80
gui.Enabled = false
gui.Parent = playerGui

-- Separate launcher remains visible while the console itself is closed.
local launcherGui = Instance.new("ScreenGui")
launcherGui.Name = "StaffConsoleLauncher"
launcherGui.ResetOnSpawn = false
launcherGui.DisplayOrder = 79
launcherGui.Enabled = false
launcherGui.Parent = playerGui
local launcherButton = Instance.new("TextButton")
launcherButton.Name = "OpenStaffConsole"
launcherButton.AnchorPoint = Vector2.new(1, 0)
launcherButton.Position = UDim2.new(1, -18, 0, 82)
launcherButton.Size = UDim2.fromOffset(142, 34)
launcherButton.BackgroundColor3 = Color3.fromRGB(30, 88, 91)
launcherButton.Text = "STAFF CONSOLE"
launcherButton.TextColor3 = Color3.fromRGB(255, 255, 255)
launcherButton.TextSize = 10
launcherButton.Font = Enum.Font.GothamBold
launcherButton.Parent = launcherGui
Instance.new("UICorner", launcherButton).CornerRadius = UDim.new(0, 10)
launcherButton.Activated:Connect(function()
	if gui:GetAttribute("StaffAuthorized") == true then
		gui.Enabled = true
	else
		warn("[Tiki Tide][SecurityConsole] Staff authorization is unavailable.")
	end
end)

local main = Instance.new("Frame")
main.Name = "MainFrame"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.fromScale(0.5, 0.5)
main.Size = UDim2.fromScale(0.88, 0.82)
main.BackgroundColor3 = Color3.fromRGB(12, 17, 27)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 16)
local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = Color3.fromRGB(54, 80, 105)
mainStroke.Thickness = 1.2

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(320, 520)
sizeConstraint.MaxSize = Vector2.new(1040, 760)
sizeConstraint.Parent = main

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 54)
header.BackgroundColor3 = Color3.fromRGB(20, 29, 43)
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 16)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(18, 7)
title.Size = UDim2.new(1, -76, 0, 22)
title.Font = Enum.Font.GothamBold
title.Text = "TIKI TIDE  •  STAFF CONSOLE"
title.TextColor3 = Color3.fromRGB(245, 202, 112)
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(18, 30)
subtitle.Size = UDim2.new(1, -76, 0, 16)
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "Quick controls for existing ClubMusic staff commands"
subtitle.TextColor3 = Color3.fromRGB(157, 174, 194)
subtitle.TextSize = 9
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = header

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(34, 34)
close.Position = UDim2.new(1, -45, 0, 10)
close.BackgroundColor3 = Color3.fromRGB(45, 56, 72)
close.Text = "×"
close.TextColor3 = Color3.fromRGB(255, 255, 255)
close.TextSize = 22
close.Font = Enum.Font.GothamBold
close.Parent = header
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)
local stopClientDiagnostics: () -> ()
close.Activated:Connect(function() gui.Enabled = false end)

local categoryBar = Instance.new("ScrollingFrame")
categoryBar.Name = "Categories"
categoryBar.Position = UDim2.fromOffset(14, 64)
categoryBar.Size = UDim2.new(1, -28, 0, 34)
categoryBar.BackgroundTransparency = 1
categoryBar.BorderSizePixel = 0
categoryBar.ScrollBarThickness = 2
categoryBar.ScrollingDirection = Enum.ScrollingDirection.X
categoryBar.AutomaticCanvasSize = Enum.AutomaticSize.X
categoryBar.CanvasSize = UDim2.new()
categoryBar.Parent = main
local categoryLayout = Instance.new("UIListLayout")
categoryLayout.FillDirection = Enum.FillDirection.Horizontal
categoryLayout.Padding = UDim.new(0, 6)
categoryLayout.Parent = categoryBar

local actionList = Instance.new("ScrollingFrame")
actionList.Name = "ActionList"
actionList.Position = UDim2.fromOffset(14, 106)
actionList.Size = UDim2.new(1, -28, 0.26, -8)
actionList.BackgroundColor3 = Color3.fromRGB(17, 25, 38)
actionList.BorderSizePixel = 0
actionList.ScrollBarThickness = 4
actionList.CanvasSize = UDim2.new()
actionList.AutomaticCanvasSize = Enum.AutomaticSize.Y
actionList.Parent = main
Instance.new("UICorner", actionList).CornerRadius = UDim.new(0, 11)
local actionPadding = Instance.new("UIPadding")
actionPadding.PaddingTop = UDim.new(0, 8)
actionPadding.PaddingBottom = UDim.new(0, 8)
actionPadding.PaddingLeft = UDim.new(0, 8)
actionPadding.PaddingRight = UDim.new(0, 8)
actionPadding.Parent = actionList
local actionLayout = Instance.new("UIGridLayout")
actionLayout.CellSize = UDim2.new(0.5, -6, 0, 36)
actionLayout.CellPadding = UDim2.fromOffset(8, 7)
actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
actionLayout.Parent = actionList

local form = Instance.new("Frame")
form.Name = "CommandForm"
form.Position = UDim2.new(0, 14, 0.26, 108)
form.Size = UDim2.new(1, -28, 0.39, -10)
form.BackgroundColor3 = Color3.fromRGB(17, 25, 38)
form.BorderSizePixel = 0
form.Parent = main
Instance.new("UICorner", form).CornerRadius = UDim.new(0, 11)

local selectedLabel = Instance.new("TextLabel")
selectedLabel.Position = UDim2.fromOffset(12, 8)
selectedLabel.Size = UDim2.new(1, -24, 0, 20)
selectedLabel.BackgroundTransparency = 1
selectedLabel.Font = Enum.Font.GothamBold
selectedLabel.Text = "Choose a staff action"
selectedLabel.TextColor3 = Color3.fromRGB(245, 202, 112)
selectedLabel.TextSize = 12
selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
selectedLabel.Parent = form

local hint = Instance.new("TextLabel")
hint.Position = UDim2.fromOffset(12, 29)
hint.Size = UDim2.new(1, -24, 0, 24)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.Text = "Select an action above. Fields change to match the selected function."
hint.TextColor3 = Color3.fromRGB(157, 174, 194)
hint.TextSize = 9
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Parent = form

local function makeInput(name: string, y: number, placeholder: string)
	local box = Instance.new("TextBox")
	box.Name = name
	box.Position = UDim2.fromOffset(12, y)
	box.Size = UDim2.new(1, -24, 0, 30)
	box.BackgroundColor3 = Color3.fromRGB(29, 40, 57)
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Gotham
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(135, 151, 171)
	box.Text = ""
	box.TextColor3 = Color3.fromRGB(245, 248, 252)
	box.TextSize = 10
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = form
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 9)
	padding.PaddingRight = UDim.new(0, 9)
	padding.Parent = box
	return box
end

local inputA = makeInput("InputA", 52, "Target UserId / queue ID / track ID")
local inputB = makeInput("InputB", 84, "Reason / details")
local inputC = makeInput("InputC", 116, "Mode / features / duration / limit")

local runButton = Instance.new("TextButton")
runButton.Name = "RunAction"
runButton.Position = UDim2.new(1, -154, 1, -43)
runButton.Size = UDim2.fromOffset(142, 32)
runButton.BackgroundColor3 = Color3.fromRGB(29, 124, 105)
runButton.Text = "RUN ACTION"
runButton.TextColor3 = Color3.fromRGB(255, 255, 255)
runButton.TextSize = 10
runButton.Font = Enum.Font.GothamBold
runButton.Parent = form
Instance.new("UICorner", runButton).CornerRadius = UDim.new(0, 8)

local lockdownButton = Instance.new("TextButton")
lockdownButton.Name = "LockdownBtn"
lockdownButton.Position = UDim2.new(0, 12, 1, -43)
lockdownButton.Size = UDim2.fromOffset(134, 32)
lockdownButton.BackgroundColor3 = Color3.fromRGB(138, 53, 53)
lockdownButton.Text = "LOCAL LOCKDOWN"
lockdownButton.TextColor3 = Color3.fromRGB(255, 255, 255)
lockdownButton.TextSize = 9
lockdownButton.Font = Enum.Font.GothamBold
lockdownButton.Parent = form
Instance.new("UICorner", lockdownButton).CornerRadius = UDim.new(0, 8)

local statusFrame = Instance.new("ScrollingFrame")
statusFrame.Name = "CommandResult"
statusFrame.Position = UDim2.new(0, 14, 0.84, 0)
statusFrame.Size = UDim2.new(1, -28, 0.14, -8)
statusFrame.BackgroundColor3 = Color3.fromRGB(17, 25, 38)
statusFrame.BorderSizePixel = 0
statusFrame.ScrollBarThickness = 3
statusFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
statusFrame.CanvasSize = UDim2.new()
statusFrame.Parent = main
Instance.new("UICorner", statusFrame).CornerRadius = UDim.new(0, 9)

-- Diagnostics overview is part of this authorized Staff Controls console.
-- Server values arrive only through the existing allowlisted staff command.
-- Client measurements are read locally and are never sent to the server.
local diagnosticsPanel = Instance.new("Frame")
diagnosticsPanel.Name = "DiagnosticsOverview"
diagnosticsPanel.Position = UDim2.fromOffset(14, 106)
diagnosticsPanel.Size = UDim2.new(1, -28, 0.65, -8)
diagnosticsPanel.BackgroundColor3 = Color3.fromRGB(17, 25, 38)
diagnosticsPanel.BorderSizePixel = 0
diagnosticsPanel.Visible = false
diagnosticsPanel.Parent = main
Instance.new("UICorner", diagnosticsPanel).CornerRadius = UDim.new(0, 11)

local diagnosticsTitle = Instance.new("TextLabel")
diagnosticsTitle.BackgroundTransparency = 1
diagnosticsTitle.Position = UDim2.fromOffset(12, 8)
diagnosticsTitle.Size = UDim2.new(1, -24, 0, 22)
diagnosticsTitle.Font = Enum.Font.GothamBold
diagnosticsTitle.Text = "CURRENT SERVER DIAGNOSTICS"
diagnosticsTitle.TextColor3 = Color3.fromRGB(245, 202, 112)
diagnosticsTitle.TextSize = 12
diagnosticsTitle.TextXAlignment = Enum.TextXAlignment.Left
diagnosticsTitle.Parent = diagnosticsPanel

local diagnosticsScope = Instance.new("TextLabel")
diagnosticsScope.BackgroundTransparency = 1
diagnosticsScope.Position = UDim2.fromOffset(12, 30)
diagnosticsScope.Size = UDim2.new(1, -24, 0, 16)
diagnosticsScope.Font = Enum.Font.Gotham
diagnosticsScope.Text = "Server-local health • client measurements remain on this device"
diagnosticsScope.TextColor3 = Color3.fromRGB(157, 174, 194)
diagnosticsScope.TextSize = 9
diagnosticsScope.TextXAlignment = Enum.TextXAlignment.Left
diagnosticsScope.Parent = diagnosticsPanel

local diagnosticsReadout = Instance.new("ScrollingFrame")
diagnosticsReadout.Name = "DiagnosticsReadout"
diagnosticsReadout.Position = UDim2.fromOffset(12, 52)
diagnosticsReadout.Size = UDim2.new(1, -24, 1, -104)
diagnosticsReadout.BackgroundColor3 = Color3.fromRGB(11, 18, 29)
diagnosticsReadout.BorderSizePixel = 0
diagnosticsReadout.ScrollBarThickness = 3
diagnosticsReadout.AutomaticCanvasSize = Enum.AutomaticSize.Y
diagnosticsReadout.CanvasSize = UDim2.new()
diagnosticsReadout.Parent = diagnosticsPanel
Instance.new("UICorner", diagnosticsReadout).CornerRadius = UDim.new(0, 8)

local diagnosticsReadoutText = Instance.new("TextLabel")
diagnosticsReadoutText.Name = "ReadoutText"
diagnosticsReadoutText.Position = UDim2.fromOffset(8, 8)
diagnosticsReadoutText.Size = UDim2.new(1, -16, 0, 0)
diagnosticsReadoutText.AutomaticSize = Enum.AutomaticSize.Y
diagnosticsReadoutText.BackgroundTransparency = 1
diagnosticsReadoutText.Font = Enum.Font.Code
diagnosticsReadoutText.Text = "Select Refresh to request this server's current authorized diagnostic snapshot."
diagnosticsReadoutText.TextColor3 = Color3.fromRGB(220, 230, 241)
diagnosticsReadoutText.TextSize = 10
diagnosticsReadoutText.TextWrapped = true
diagnosticsReadoutText.TextXAlignment = Enum.TextXAlignment.Left
diagnosticsReadoutText.TextYAlignment = Enum.TextYAlignment.Top
diagnosticsReadoutText.Parent = diagnosticsReadout

local diagnosticsRefresh = Instance.new("TextButton")
diagnosticsRefresh.Name = "RefreshDiagnostics"
diagnosticsRefresh.Position = UDim2.new(0, 12, 1, -42)
diagnosticsRefresh.Size = UDim2.fromOffset(132, 30)
diagnosticsRefresh.BackgroundColor3 = Color3.fromRGB(29, 124, 105)
diagnosticsRefresh.Text = "REFRESH"
diagnosticsRefresh.TextColor3 = Color3.fromRGB(255, 255, 255)
diagnosticsRefresh.TextSize = 9
diagnosticsRefresh.Font = Enum.Font.GothamBold
diagnosticsRefresh.Parent = diagnosticsPanel
Instance.new("UICorner", diagnosticsRefresh).CornerRadius = UDim.new(0, 8)

local diagnosticsCommands = Instance.new("TextButton")
diagnosticsCommands.Name = "DetailedDiagnosticsCommands"
diagnosticsCommands.Position = UDim2.new(1, -166, 1, -42)
diagnosticsCommands.Size = UDim2.fromOffset(154, 30)
diagnosticsCommands.BackgroundColor3 = Color3.fromRGB(49, 63, 84)
diagnosticsCommands.Text = "DETAILED COMMANDS"
diagnosticsCommands.TextColor3 = Color3.fromRGB(255, 255, 255)
diagnosticsCommands.TextSize = 9
diagnosticsCommands.Font = Enum.Font.GothamBold
diagnosticsCommands.Parent = diagnosticsPanel
Instance.new("UICorner", diagnosticsCommands).CornerRadius = UDim.new(0, 8)

local status = Instance.new("TextLabel")
status.Name = "StatusLabel"
status.Position = UDim2.fromOffset(9, 7)
status.Size = UDim2.new(1, -18, 0, 0)
status.AutomaticSize = Enum.AutomaticSize.Y
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.Text = "Waiting for server authorization…"
status.TextColor3 = Color3.fromRGB(157, 174, 194)
status.TextSize = 9
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Parent = statusFrame

type Command = {key: string, label: string, help: string, kind: string?}
local groups: {[string]: {Command}} = {
	Playback = {
		{key="PlaybackSkip",label="Skip current track",help="Move playback to the next track."},
		{key="PlaybackPause",label="Pause / resume",help="Toggle the current playback pause state."},
		{key="PlaybackRestart",label="Restart track",help="Restart the currently playing track."},
		{key="PlaybackStatus",label="Playback status",help="Show playback, request lock and queue status."},
		{key="QueueView",label="View request queue",help="List queued tracks and their removal IDs."},
		{key="QueueRemove",label="Remove queue entry",help="Enter the queue ID from the queue listing.",kind="queue"},
		{key="QueueClear",label="Clear entire queue",help="Removes all queued requests. Requires confirmation."},
		{key="RequestLock",label="Toggle request lock",help="Toggle the normal request lock."},
		{key="EmergencyRequestLock",label="Emergency request lock",help="Emergency-lock requests across servers. Requires confirmation."},
		{key="PlaybackForceStop",label="Emergency stop playback",help="Stops playback across servers. Requires confirmation."},
	},
	Requests = {
		{key="RequestMute",label="Mute / unmute requests",help="Enter UserId, on/off, and an optional reason.",kind="targetOptionReason"},
		{key="ClearUserQueue",label="Clear one user's requests",help="Remove all queued requests submitted by a UserId.",kind="target"},
		{key="TrackBlock",label="Block / allow a track",help="Enter track ID, on/off, and an optional reason.",kind="targetOptionReason"},
		{key="ModerationHistory",label="Request moderation history",help="Review ClubMusic request moderation for a UserId.",kind="target"},
	},
	["DJ Sessions"] = {
		{key="DJSessionStatus",label="Session status",help="Show the active DJ session."},
		{key="DJSessionStart",label="Start my DJ session",help="Start a DJ session for your account."},
		{key="DJSessionHandoff",label="Hand off DJ session",help="Enter the receiving staff member's UserId.",kind="target"},
		{key="DJSessionEnd",label="End DJ session",help="End the active DJ session."},
	},
	Moderation = {
		{key="Warn",label="Issue formal warning",help="Enter UserId and reason.",kind="targetReason"},
		{key="Restrict",label="Apply feature restrictions",help="Enter UserId, feature keys, and reason.",kind="targetOptionReason"},
		{key="TempBan",label="Temporary ban",help="Enter UserId, duration in seconds, and reason.",kind="targetReasonOption"},
		{key="PermanentBan",label="Permanent ban",help="Enter UserId and reason. Requires confirmation.",kind="targetReason"},
		{key="PermanentBanAlts",label="Permanent ban + suspected alts",help="Senior authorization required. Requires confirmation.",kind="targetReason"},
		{key="Unban",label="Unban player",help="Enter UserId and reversal reason.",kind="targetReason"},
		{key="Unrestrict",label="Remove restrictions",help="Enter UserId and reversal reason.",kind="targetReason"},
		{key="PunishmentHistory",label="Punishment history",help="Review retained Phase 32 history for a UserId.",kind="target"},
		{key="AccountRisk",label="Account risk review",help="Advisory-only account-risk review for a UserId.",kind="target"},
	},
	Security = {
		{key="SecurityStatus",label="Security status",help="Show global security service status."},
		{key="SecurityIncidents",label="Recent incidents",help="List retained security incidents."},
		{key="SecurityReplay",label="Security replay",help="Optional UserId and result limit.",kind="replay"},
		{key="ThreatIntelligence",label="Threat intelligence",help="Optional UserId and result limit.",kind="replay"},
		{key="SpectateEnter",label="Observe player",help="Enter a live player's UserId.",kind="target"},
		{key="SpectateSwitch",label="Switch observation target",help="Enter the next live player's UserId.",kind="target"},
		{key="SpectateExit",label="Exit observation",help="Restore your normal camera and movement."},
		{key="SpectateState",label="Observation status",help="Show your current observation target."},
		{key="ThreatCaseOpen",label="Escalate threat review",help="Enter the TTI review ID.",kind="detail"},
		{key="IncidentOpen",label="Open incident",help="Enter incident type, target (UserId or server), and summary.",kind="incident"},
		{key="IncidentResolve",label="Resolve incident",help="Enter the incident ID.",kind="detail"},
		{key="SecurityPolicy",label="View security policy",help="Show the current security policy."},
		{key="SecurityPolicySet",label="Update security policy",help="Enter policy key and value.",kind="policy"},
	},
	["Club Closure"] = {
		{key="ClubClose",label="Close club (current server)",help="Prepare and confirm guest evacuation. Verified staff remain."},
		{key="ClubReopen",label="Reopen club (current server)",help="Prepare and confirm reopening this server."},
		{key="ClubStatus",label="Club closure status",help="Show whether this server is open or closed."},
	},
	Diagnostics = {
		{key="Health",label="Audio / service health",help="Show local and cross-server health."},
		{key="Diagnostics",label="Diagnostic snapshot",help="Show a safe diagnostic snapshot."},
		{key="PurchaseDiagnostics",label="Purchase diagnostics",help="Review recent purchase/receipt diagnostics."},
		{key="Services",label="Service status",help="List ClubMusic service states."},
		{key="Errors",label="Error history",help="Review recent operational errors."},
		{key="Metrics",label="Operational metrics",help="Review performance and workload metrics."},
		{key="SecurityLog",label="Security audit log",help="Review retained security audit events."},
		{key="RateLimit",label="Rate-limit status",help="Review rate-limit status."},
		{key="Config",label="Configuration status",help="Review effective configuration."},
		{key="Recovery",label="Recovery status",help="Review recovery service status."},
		{key="Reconcile",label="Reconciliation status",help="Review reconciliation state."},
		{key="CatalogRefresh",label="Refresh music catalog",help="Refresh the server's catalog view."},
		{key="Maintenance",label="Maintenance mode",help="Enter status, on, or off. Turning maintenance on/off requires confirmation.",kind="maintenance"},
	},
}

local selected: Command? = nil
local activeGroup = "Playback"
local diagnosticsDashboardMode = false
local diagnosticsServerMessage = "No server snapshot loaded."
local clientDiagnostics: any = nil
local clientDiagnosticsModuleAttempted = false
local diagnosticsRequestPending = false
local pendingConfirmation = false
local confirmationToken = 0
local pendingRequest = false
local requestToken = 0
local initialStatusHandled = false
local lockdownActive = false
local closurePreparedMode: string? = nil

local function setStatus(message: string, success: boolean?)
	status.Text = string.sub(message, 1, 1800)
	task.defer(function()
		statusFrame.CanvasPosition = Vector2.new(0, math.max(0, statusFrame.AbsoluteCanvasSize.Y - statusFrame.AbsoluteSize.Y))
	end)
	status.TextColor3 = if success == true then Color3.fromRGB(119, 220, 173)
		elseif success == false then Color3.fromRGB(245, 139, 139)
		else Color3.fromRGB(157, 174, 194)
end

local function clearInputs()
	inputA.Text = ""
	inputB.Text = ""
	inputC.Text = ""
end

local function updateForm()
	if not selected then return end
	selectedLabel.Text = selected.label
	hint.Text = selected.help
	local kind = selected.kind or "none"
	inputA.Visible = kind ~= "none" and kind ~= "detail"
	inputB.Visible = kind == "targetReason" or kind == "targetOptionReason" or kind == "targetReasonOption" or kind == "incident" or kind == "policy" or kind == "maintenance" or kind == "detail"
	inputC.Visible = kind == "targetOptionReason" or kind == "targetReasonOption" or kind == "replay" or kind == "incident"
	if kind == "target" then inputA.PlaceholderText = "Roblox UserId"
	elseif kind == "queue" then inputA.PlaceholderText = "Queue entry ID"
	elseif kind == "targetReason" then inputA.PlaceholderText = "Roblox UserId"; inputB.PlaceholderText = "Reason"
	elseif kind == "targetOptionReason" then inputA.PlaceholderText = "UserId or track ID"; inputB.PlaceholderText = "Reason (optional)"; inputC.PlaceholderText = "on/off or feature keys"
	elseif kind == "targetReasonOption" then inputA.PlaceholderText = "Roblox UserId"; inputB.PlaceholderText = "Reason"; inputC.PlaceholderText = "Duration in seconds"
	elseif kind == "replay" then inputA.PlaceholderText = "UserId (optional)"; inputB.Visible = false; inputC.PlaceholderText = "Result limit (1-30, optional)"
	elseif kind == "incident" then inputA.PlaceholderText = "Incident type (SecurityAlert, ServiceDegraded, AbuseReport, ManualReview)"; inputB.PlaceholderText = "Target UserId or server"; inputC.PlaceholderText = "Incident summary"
	elseif kind == "policy" then inputA.PlaceholderText = "Policy setting key"; inputB.PlaceholderText = "New value"; inputC.Visible = false
	elseif kind == "maintenance" then inputA.PlaceholderText = "status / on / off"; inputB.PlaceholderText = "Maintenance notice (optional)"; inputC.Visible = false
	elseif kind == "detail" then inputA.Visible = false; inputB.PlaceholderText = "ID"; inputC.Visible = false
	else
		inputA.PlaceholderText = "Target / ID"
		inputB.PlaceholderText = "Reason / details"
		inputC.PlaceholderText = "Option / limit"
	end
	if kind == "none" then clearInputs() end
end

local function makeActionButton(command: Command, order: number)
	local button = Instance.new("TextButton")
	button.Name = command.key
	button.LayoutOrder = order
	button.BackgroundColor3 = Color3.fromRGB(34, 47, 65)
	button.BorderSizePixel = 0
	button.Text = command.label
	button.TextColor3 = Color3.fromRGB(225, 235, 246)
	button.TextSize = 10
	button.Font = Enum.Font.GothamSemibold
	button.TextWrapped = true
	button.Parent = actionList
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
	button.Activated:Connect(function()
		selected = command
		pendingConfirmation = false
		closurePreparedMode = nil
		clearInputs()
		updateForm()
		for _, child in ipairs(actionList:GetChildren()) do
			if child:IsA("TextButton") then child.BackgroundColor3 = Color3.fromRGB(34, 47, 65) end
		end
		button.BackgroundColor3 = Color3.fromRGB(89, 58, 111)
	end)
end

stopClientDiagnostics = function()
	if clientDiagnostics and type(clientDiagnostics.Stop) == "function" then
		pcall(clientDiagnostics.Stop, clientDiagnostics)
	end
end

local function startClientDiagnostics()
	if clientDiagnostics then
		pcall(clientDiagnostics.Start, clientDiagnostics)
		return
	end
	if clientDiagnosticsModuleAttempted then return end
	clientDiagnosticsModuleAttempted = true
	local moduleScript = ReplicatedStorage:FindFirstChild("ClubMusic_Client_Diagnostics_Service")
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		diagnosticsReadoutText.Text = diagnosticsServerMessage .. "\n\nCLIENT-LOCAL\nClient diagnostics module is not installed."
		return
	end
	local requireOk, exported = pcall(require, moduleScript)
	if not requireOk or typeof(exported) ~= "table" or type(exported.new) ~= "function" then
		diagnosticsReadoutText.Text = diagnosticsServerMessage .. "\n\nCLIENT-LOCAL\nClient diagnostics module is unavailable."
		return
	end
	local createOk, instance = pcall(function()
		return exported.new({auditWorkspaceEffects = false, sampleAudio = false})
	end)
	if not createOk or typeof(instance) ~= "table" or type(instance.Start) ~= "function"
		or type(instance.GetStatus) ~= "function" or type(instance.Stop) ~= "function" then
		diagnosticsReadoutText.Text = diagnosticsServerMessage .. "\n\nCLIENT-LOCAL\nClient diagnostics interface is invalid."
		return
	end
	local startOk, started = pcall(instance.Start, instance)
	if not startOk or started ~= true then
		pcall(instance.Stop, instance)
		diagnosticsReadoutText.Text = diagnosticsServerMessage .. "\n\nCLIENT-LOCAL\nLocal sampling could not start."
		return
	end
	clientDiagnostics = instance
end

local function renderDiagnosticsReadout()
	local clientLines = {"CLIENT-LOCAL MEASUREMENTS (untrusted; not transmitted)"}
	if clientDiagnostics then
		local ok, snapshot = pcall(clientDiagnostics.GetStatus, clientDiagnostics)
		if ok and typeof(snapshot) == "table" then
			local fps = if typeof(snapshot.fps) == "number" then tostring(math.floor(snapshot.fps + 0.5)) else "n/a"
			local ping = if typeof(snapshot.ping) == "table" and typeof(snapshot.ping.milliseconds) == "number"
				then tostring(math.floor(snapshot.ping.milliseconds + 0.5)) .. " ms" else "n/a"
			local memory = if typeof(snapshot.memory) == "table" and typeof(snapshot.memory.usageMb) == "number"
				then tostring(math.floor(snapshot.memory.usageMb + 0.5)) .. " MB" else "n/a"
			table.insert(clientLines, "Client FPS: " .. fps .. " | Ping: " .. ping .. " | Client memory: " .. memory)
			table.insert(clientLines, "Client sample state: " .. tostring(snapshot.state or "Unknown"))
		else
			table.insert(clientLines, "Client-local measurements are temporarily unavailable.")
		end
	else
		table.insert(clientLines, "Client-local sampling is not active.")
	end
	diagnosticsReadoutText.Text = string.sub(diagnosticsServerMessage .. "\n\n" .. table.concat(clientLines, "\n"), 1, 7000)
end

local function renderGroup()
	local isDiagnostics = activeGroup == "Diagnostics"
	diagnosticsPanel.Visible = isDiagnostics and diagnosticsDashboardMode
	actionList.Visible = not (isDiagnostics and diagnosticsDashboardMode)
	form.Visible = not (isDiagnostics and diagnosticsDashboardMode)
	if isDiagnostics and diagnosticsDashboardMode then
		startClientDiagnostics()
		renderDiagnosticsReadout()
	else
		stopClientDiagnostics()
	end
	for _, child in ipairs(actionList:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	local commands = groups[activeGroup] or {}
	for index, command in ipairs(commands) do makeActionButton(command, index) end
	clearInputs()
	selected = commands[1]
	if selected then updateForm() end
end

gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not gui.Enabled then
		stopClientDiagnostics()
	elseif activeGroup == "Diagnostics" and diagnosticsDashboardMode then
		startClientDiagnostics()
		renderDiagnosticsReadout()
	end
end)

local function makeCategory(name: string)
	local button = Instance.new("TextButton")
	button.AutomaticSize = Enum.AutomaticSize.X
	button.Size = UDim2.fromOffset(0, 30)
	button.BackgroundColor3 = Color3.fromRGB(35, 47, 65)
	button.Text = name
	button.TextColor3 = Color3.fromRGB(208, 220, 235)
	button.TextSize = 9
	button.Font = Enum.Font.GothamBold
	button.Parent = categoryBar
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = button
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 14)
	button.Activated:Connect(function()
		activeGroup = name
		diagnosticsDashboardMode = name == "Diagnostics"
		for _, item in ipairs(categoryBar:GetChildren()) do
			if item:IsA("TextButton") then item.BackgroundColor3 = if item == button then Color3.fromRGB(89, 58, 111) else Color3.fromRGB(35, 47, 65) end
		end
		renderGroup()
	end)
	return button
end

for _, groupName in ipairs({"Playback","Requests","DJ Sessions","Moderation","Security","Club Closure","Diagnostics"}) do makeCategory(groupName) end
renderGroup()

diagnosticsRefresh.Activated:Connect(function()
	if not gui:GetAttribute("StaffAuthorized") or diagnosticsRequestPending then return end
	diagnosticsRequestPending = true
	diagnosticsRefresh.Active = false
	diagnosticsRefresh.Text = "REFRESHING…"
	securityAction:FireServer("RunClubMusicCommand", "Diagnostics", "")
	task.delay(8, function()
		if diagnosticsRequestPending then
			diagnosticsRequestPending = false
			diagnosticsRefresh.Active = true
			diagnosticsRefresh.Text = "REFRESH"
			diagnosticsServerMessage = "Server snapshot request timed out. No diagnostic state was changed."
			renderDiagnosticsReadout()
		end
	end)
end)

diagnosticsCommands.Activated:Connect(function()
	diagnosticsDashboardMode = false
	activeGroup = "Diagnostics"
	renderGroup()
end)

local CONFIRM = {
	QueueClear=true, EmergencyRequestLock=true, PlaybackForceStop=true, Maintenance=true,
	RequestMute=true, ClearUserQueue=true, TrackBlock=true,
	PermanentBan=true, PermanentBanAlts=true, Unban=true, IncidentOpen=true, IncidentResolve=true,
	ThreatCaseOpen=true, SecurityPolicySet=true, ClubClose=true, ClubReopen=true,
}

local function buildArgument(command: Command): string
	local kind = command.kind or "none"
	local a = string.match(inputA.Text, "^%s*(.-)%s*$") or ""
	local b = string.match(inputB.Text, "^%s*(.-)%s*$") or ""
	local c = string.match(inputC.Text, "^%s*(.-)%s*$") or ""
	if kind == "none" then return ""
	elseif kind == "target" or kind == "queue" then return a
	elseif kind == "detail" then return b
	elseif kind == "targetReason" then return a .. " " .. b
	elseif kind == "targetOptionReason" then return a .. " " .. c .. (if b ~= "" then " " .. b else "")
	elseif kind == "targetReasonOption" then return a .. " " .. c .. " " .. b
	elseif kind == "replay" then return if a == "" and c == "" then "" else a .. " " .. c
	elseif kind == "incident" then return a .. " " .. b .. " " .. c
	elseif kind == "policy" then return a .. " " .. b
	elseif kind == "maintenance" then return a .. " " .. b end
	return ""
end

runButton.Activated:Connect(function()
	if pendingRequest then return end
	if selected and (selected.key == "ClubClose" or selected.key == "ClubReopen" or selected.key == "ClubStatus") then
		local key = selected.key
		local action = if key == "ClubStatus" then "ClubClosureStatus"
			elseif key == "ClubClose" then (if closurePreparedMode == "Close" then "ClubClosureConfirm" else "ClubClosurePrepare")
			else (if closurePreparedMode == "Reopen" then "ClubReopenConfirm" else "ClubReopenPrepare")
		pendingRequest = true
		requestToken += 1
		local thisRequest = requestToken
		runButton.Active = false
		runButton.Text = "SENDING…"
		securityAction:FireServer(action)
		task.delay(8, function()
			if pendingRequest and requestToken == thisRequest then
				pendingRequest = false
				runButton.Active = true
				runButton.Text = "RUN ACTION"
				setStatus("No server response was received. Check server health before retrying.", false)
			end
		end)
		return
	end
	if not selected then setStatus("Select an action first.", false); return end
	local argument = buildArgument(selected)
	if #argument > 320 then setStatus("The details are too long.", false); return end
	if (selected.kind or "none") ~= "none" and argument:gsub("%s", "") == "" then
		setStatus("Complete the required fields first.", false)
		return
	end
	if CONFIRM[selected.key] and not pendingConfirmation then
		pendingConfirmation = true
		confirmationToken += 1
		local token = confirmationToken
		runButton.Text = "CONFIRM ACTION"
		setStatus("Press Confirm Action again within 6 seconds to proceed.")
		task.delay(6, function()
			if pendingConfirmation and confirmationToken == token then
				pendingConfirmation = false
				runButton.Text = "RUN ACTION"
			end
		end)
		return
	end
	pendingConfirmation = false
	confirmationToken += 1
	pendingRequest = true
	requestToken += 1
	local thisRequest = requestToken
	runButton.Active = false
	runButton.Text = "SENDING…"
	setStatus("Submitting " .. selected.label .. " to the server…")
	securityAction:FireServer("RunClubMusicCommand", selected.key, argument)
	task.delay(8, function()
		if pendingRequest and requestToken == thisRequest then
			pendingRequest = false
			runButton.Active = true
			runButton.Text = "RUN ACTION"
			setStatus("No server response was received. Check server health before retrying.", false)
		end
	end)
end)

local lockdownConfirm = false
lockdownButton.Activated:Connect(function()
	if pendingRequest then return end
	if not lockdownConfirm then
		lockdownConfirm = true
		lockdownButton.Text = "CONFIRM LOCAL LOCK"
		setStatus("Click again within 5 seconds to toggle this server's door lockdown.")
		task.delay(5, function()
			if lockdownConfirm then lockdownConfirm = false; lockdownButton.Text = "LOCAL LOCKDOWN" end
		end)
		return
	end
	lockdownConfirm = false
	pendingRequest = true
	requestToken += 1
	local thisRequest = requestToken
	lockdownButton.Active = false
	lockdownButton.Text = "SENDING…"
	runButton.Active = false
	securityAction:FireServer("ToggleLockdown")
	task.delay(8, function()
		if pendingRequest and requestToken == thisRequest then
			pendingRequest = false
			runButton.Active = true
			lockdownButton.Active = true
			lockdownButton.Text = if lockdownActive then "DISABLE LOCAL LOCK" else "LOCAL LOCKDOWN"
			setStatus("No server response was received. Check server health before retrying.", false)
		end
	end)
end)

actionResult.OnClientEvent:Connect(function(action: any, succeeded: any, message: any, serverLockdownState: any)
	if typeof(action) ~= "string" or typeof(succeeded) ~= "boolean" then return end
	if typeof(serverLockdownState) == "boolean" then
		lockdownActive = serverLockdownState
		lockdownButton.Text = if lockdownActive then "DISABLE LOCAL LOCK" else "LOCAL LOCKDOWN"
	end
	local result = if typeof(message) == "string" then message else "The server returned an unknown result."
	if action ~= "GetStatus" then
		setStatus(result, succeeded)
	elseif not succeeded then
		setStatus(result, false)
	elseif not initialStatusHandled then
		setStatus("Staff authorization verified.", true)
	end
	if action == "GetStatus" then
		gui:SetAttribute("StaffAuthorized", succeeded)
		if not succeeded then stopClientDiagnostics() end
		launcherGui.Enabled = succeeded
		if not succeeded then
			gui.Enabled = false
		elseif not initialStatusHandled then
			gui.Enabled = true
		end
		initialStatusHandled = true
	end
	if action == "ClubClosurePrepare" and succeeded then
		closurePreparedMode = "Close"
		runButton.Text = "CONFIRM CLOSE"
	elseif action == "ClubReopenPrepare" and succeeded then
		closurePreparedMode = "Reopen"
		runButton.Text = "CONFIRM REOPEN"
	elseif action == "ClubClosureConfirm" or action == "ClubReopenConfirm" then
		closurePreparedMode = nil
		runButton.Text = "RUN ACTION"
	end
	if action == "RunClubMusicCommand" and diagnosticsRequestPending then
		diagnosticsServerMessage = if succeeded then result else "Server diagnostics request failed: " .. result
		diagnosticsRequestPending = false
		diagnosticsRefresh.Active = true
		diagnosticsRefresh.Text = "REFRESH"
		renderDiagnosticsReadout()
	end
	if action == "RunClubMusicCommand" and succeeded then clearInputs() end
	if action == "RunClubMusicCommand" or action == "ToggleLockdown"
		or action == "ClubClosurePrepare" or action == "ClubClosureConfirm"
		or action == "ClubReopenPrepare" or action == "ClubReopenConfirm"
		or action == "ClubClosureStatus" then
		pendingRequest = false
		requestToken += 1
		runButton.Active = true
		runButton.Text = if action == "ClubClosurePrepare" then "CONFIRM CLOSE"
			elseif action == "ClubReopenPrepare" then "CONFIRM REOPEN" else "RUN ACTION"
		lockdownButton.Active = true
	end
end)

task.spawn(function()
	while gui.Parent do
		if gui.Enabled and activeGroup == "Diagnostics" and diagnosticsDashboardMode then
			renderDiagnosticsReadout()
		end
		task.wait(1)
	end
end)

task.spawn(function()
	while gui.Parent do
		securityAction:FireServer("GetStatus")
		task.wait(30)
	end
end)
print("[Tiki Tide][SecurityConsole] Graphical command console and server-local closure controls connected.")
