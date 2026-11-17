--!strict
-- Opt-in-by-installation client dependency observations.
-- Reports only fixed missing-component codes. All client reports are untrusted and
-- cannot authorize actions or trigger punishment. No device, account, or free-form data is sent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_NAME = "TikiTideClientIntegrityTelemetry_v1"
local CHECK_DELAY_SECONDS = 60
local REMOTE_WAIT_SECONDS = 30

local reportRemote = ReplicatedStorage:WaitForChild(REMOTE_NAME, REMOTE_WAIT_SECONDS)
if not reportRemote or not reportRemote:IsA("RemoteEvent") then
	-- No fallback remote is created by the client. A missing server endpoint is not
	-- evidence against the player and is deliberately not reported.
	return
end

local function report(signal: string)
	pcall(function()
		reportRemote:FireServer(signal)
	end)
end

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
