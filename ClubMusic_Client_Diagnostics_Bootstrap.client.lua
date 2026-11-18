--!strict
-- Client-local diagnostics bootstrap.
-- Install this LocalScript under StarterPlayerScripts and the matching
-- ClubMusic_Client_Diagnostics_Service ModuleScript under ReplicatedStorage.
-- Sampling is local to this client; no measurements are sent to the server.

local ENABLE_CLIENT_DIAGNOSTICS = true

if not ENABLE_CLIENT_DIAGNOSTICS then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local moduleScript = ReplicatedStorage:WaitForChild("ClubMusic_Client_Diagnostics_Service", 10)
if not moduleScript or not moduleScript:IsA("ModuleScript") then
	warn("[ClubMusic][ClientDiagnostics] Optional module is not installed in ReplicatedStorage.")
	return
end

local ok, exported = pcall(require, moduleScript)
if not ok or typeof(exported) ~= "table" or type(exported.new) ~= "function" then
	warn("[ClubMusic][ClientDiagnostics] Module could not be loaded: " .. tostring(exported))
	return
end

-- The default service options keep the full Workspace effects inventory disabled.
-- FPS/frame-time, client memory, and optional modern AudioPlayer observations remain local.
local createOk, diagnostics = pcall(exported.new)
if not createOk or typeof(diagnostics) ~= "table"
	or type(diagnostics.Start) ~= "function" or type(diagnostics.GetStatus) ~= "function"
	or type(diagnostics.Stop) ~= "function" then
	warn("[ClubMusic][ClientDiagnostics] Module interface is invalid: " .. tostring(diagnostics))
	return
end

local started, startResult = pcall(diagnostics.Start, diagnostics)
if not started or startResult ~= true then
	warn("[ClubMusic][ClientDiagnostics] Could not start local sampling: " .. tostring(startResult))
	return
end

local existing = playerScripts:FindFirstChild("GetClubMusicClientDiagnostics")
if existing then existing:Destroy() end
local statusFunction = Instance.new("BindableFunction")
statusFunction.Name = "GetClubMusicClientDiagnostics"
statusFunction.Parent = playerScripts
statusFunction.OnInvoke = function()
	local statusOk, status = pcall(diagnostics.GetStatus, diagnostics)
	if statusOk and typeof(status) == "table" then return status end
	return {state = "Unavailable", scope = "ClientLocalUntrusted", transmitted = false}
end

script.Destroying:Connect(function()
	pcall(diagnostics.Stop, diagnostics)
	if statusFunction.Parent then statusFunction:Destroy() end
end)

print("[ClubMusic][ClientDiagnostics] Local-only sampling enabled; data is untrusted and never transmitted.")
