--!strict
-- Opt-in-by-installation client observations.
-- All reports are fixed-code, untrusted telemetry. They never authorize or punish.
-- No client values, timestamps, free-form text, device data, or movement measurements are sent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_NAME = "TikiTideClientIntegrityTelemetry_v1"
local CHECK_DELAY_SECONDS = 60
local REMOTE_WAIT_SECONDS = 30
local HEARTBEAT_INTERVAL_SECONDS = 60
local MOVEMENT_LOCAL_COOLDOWN_SECONDS = 30
local HUMANOID_WAIT_SECONDS = 10

local player = Players.LocalPlayer
local reportRemote = ReplicatedStorage:WaitForChild(REMOTE_NAME, REMOTE_WAIT_SECONDS)
if not reportRemote or not reportRemote:IsA("RemoteEvent") then
	-- No fallback remote is created by the client. Missing telemetry is not evidence.
	return
end

local function report(signal: string)
	if not script.Parent or not reportRemote.Parent then return end
	pcall(function()
		reportRemote:FireServer(signal)
	end)
end

local activeCharacter: Model? = nil
local humanoidConnection: RBXScriptConnection? = nil
local humanoidDestroyingConnection: RBXScriptConnection? = nil
local lastMovementReportAt = -math.huge

local function disconnectHumanoid()
	if humanoidConnection then
		humanoidConnection:Disconnect()
		humanoidConnection = nil
	end
	if humanoidDestroyingConnection then
		humanoidDestroyingConnection:Disconnect()
		humanoidDestroyingConnection = nil
	end
	activeCharacter = nil
end

local function monitorCharacter(character: Model)
	disconnectHumanoid()
	activeCharacter = character

	local humanoid = character:WaitForChild("Humanoid", HUMANOID_WAIT_SECONDS)
	if not script.Parent or player.Character ~= character or activeCharacter ~= character then return end
	if not humanoid or not humanoid:IsA("Humanoid") then return end

	humanoidDestroyingConnection = humanoid.Destroying:Connect(function()
		if activeCharacter == character then disconnectHumanoid() end
	end)
	humanoidConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if not script.Parent or activeCharacter ~= character
			or player.Character ~= character or humanoid.Parent ~= character then
			return
		end

		local now = os.clock()
		if now - lastMovementReportAt < MOVEMENT_LOCAL_COOLDOWN_SECONDS then return end
		lastMovementReportAt = now
		-- This says only that the local observer saw a property change. No value is sent.
		report("client_walkspeed_observed_change")
	end)
end

local characterAddedConnection = player.CharacterAdded:Connect(monitorCharacter)
local characterRemovingConnection = player.CharacterRemoving:Connect(function(character)
	if activeCharacter == character then disconnectHumanoid() end
end)

if player.Character then
	task.spawn(monitorCharacter, player.Character)
end

-- Heartbeat reports only that a client message arrived. Server receive time is
-- authoritative for liveness; this client does not send os.clock() or wall time.
task.spawn(function()
	while script.Parent do
		task.wait(HEARTBEAT_INTERVAL_SECONDS)
		if not script.Parent then break end
		report("client_integrity_observer_heartbeat")
	end
end)

task.delay(CHECK_DELAY_SECONDS, function()
	if not script.Parent then return end

	local network = ReplicatedStorage:FindFirstChild("UI_Network")
	if not network or not network:IsA("ModuleScript") then
		report("client_integrity_ui_network_missing")
		task.wait(1.1)
	end

	local renderer = ReplicatedStorage:FindFirstChild("UI_Renderer")
	if not renderer or not renderer:IsA("ModuleScript") then
		report("client_integrity_ui_renderer_missing")
		task.wait(1.1)
	end

	local remotes = ReplicatedStorage:FindFirstChild("ClubMusicRemotes")
	if not remotes or not remotes:IsA("Folder") then
		report("client_integrity_remote_folder_missing")
		return
	end

	local expected = {
		{ name = "RequestAction", className = "RemoteEvent", signal = "client_integrity_request_remote_missing" },
		{ name = "StateChanged", className = "RemoteEvent", signal = "client_integrity_state_remote_missing" },
		{ name = "Notice", className = "RemoteEvent", signal = "client_integrity_notice_remote_missing" },
		{ name = "GetState", className = "RemoteFunction", signal = "client_integrity_state_function_missing" },
	}
	for _, item in ipairs(expected) do
		local object = remotes:FindFirstChild(item.name)
		if not object or object.ClassName ~= item.className then
			report(item.signal)
			task.wait(1.1)
		end
	end
	report("client_integrity_probe_completed")
end)

script.Destroying:Connect(function()
	disconnectHumanoid()
	characterAddedConnection:Disconnect()
	characterRemovingConnection:Disconnect()
end)
