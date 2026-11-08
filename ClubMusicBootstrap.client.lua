--!strict
-- ClubMusicBootstrap (Security / Reliability Hardened)
-- Place as LocalScript: StarterPlayer > StarterPlayerScripts
-- Requires:
--   ReplicatedStorage/UI_Network (ModuleScript)
--   ReplicatedStorage/UI_Renderer (ModuleScript)
-- Server:
--   ServerScriptService/UI_Server_Controller (Script)
--
-- Client bootstrap hardening is defense-in-depth only. All permissions,
-- purchases, ownership checks, and action validation remain server-authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if not player then
	warn("[ClubMusic Bootstrap] LocalPlayer is unavailable; startup aborted.")
	return
end

local cleaned = false
local mounted: any = nil
local Network: any = nil
local noticeConnection: RBXScriptConnection? = nil
local playerGui: PlayerGui? = nil
local sessionMarker: Folder? = nil
local ownsNetwork = false

local MODULE_TIMEOUT = 45
local PLAYER_GUI_TIMEOUT = 15
local MAX_NOTICE_LENGTH = 400
local SESSION_MARKER_NAME = "ClubMusicBootstrapSession"

local NOTICE_COLORS: {[string]: Color3} = {
	ok = Color3.fromRGB(46, 204, 113),
	warn = Color3.fromRGB(255, 140, 0),
	error = Color3.fromRGB(239, 68, 68),
	info = Color3.fromRGB(0, 240, 255),
}

local function safeDisconnect(connection: RBXScriptConnection?)
	if connection then
		pcall(function()
			connection:Disconnect()
		end)
	end
end

local function cleanup()
	if cleaned then
		return
	end
	cleaned = true

	safeDisconnect(noticeConnection)
	noticeConnection = nil

	if typeof(mounted) == "table" and typeof(mounted.Destroy) == "function" then
		pcall(function()
			mounted.Destroy()
		end)
	end
	mounted = nil

	-- Network.Destroy() is terminal for this module instance. Call it only
	-- after this bootstrap successfully initialized and took ownership of it.
	if ownsNetwork and typeof(Network) == "table" and typeof(Network.Destroy) == "function" then
		pcall(function()
			Network.Destroy()
		end)
	end

	if sessionMarker and sessionMarker.Parent then
		sessionMarker:Destroy()
	end
	sessionMarker = nil
end

script.Destroying:Connect(cleanup)

local function fail(message: string)
	warn("[ClubMusic Bootstrap] " .. message)
	cleanup()
end

-- Resolve PlayerGui with a finite wait so startup cannot hang indefinitely.
local guiInstance = player:WaitForChild("PlayerGui", PLAYER_GUI_TIMEOUT)
if not guiInstance or not guiInstance:IsA("PlayerGui") then
	fail("PlayerGui did not become available; UI startup aborted.")
	return
end
playerGui = guiInstance

-- Prevent accidental duplicate bootstrap copies from stacking notice listeners
-- or creating competing UI/network lifecycles on the same client.
if playerGui:FindFirstChild(SESSION_MARKER_NAME) then
	warn("[ClubMusic Bootstrap] Another bootstrap session is already active; duplicate startup ignored.")
	return
end

sessionMarker = Instance.new("Folder")
sessionMarker.Name = SESSION_MARKER_NAME
sessionMarker.Parent = playerGui

local networkInstance = ReplicatedStorage:WaitForChild("UI_Network", MODULE_TIMEOUT)
local rendererInstance = ReplicatedStorage:WaitForChild("UI_Renderer", MODULE_TIMEOUT)

if not networkInstance or not networkInstance:IsA("ModuleScript") then
	fail("ReplicatedStorage.UI_Network is missing or is not a ModuleScript.")
	return
end
if not rendererInstance or not rendererInstance:IsA("ModuleScript") then
	fail("ReplicatedStorage.UI_Renderer is missing or is not a ModuleScript.")
	return
end

-- Protect startup from a module load error while retaining clear diagnostics.
local networkOk, networkResult = pcall(require, networkInstance)
if not networkOk or typeof(networkResult) ~= "table" then
	fail("UI_Network failed to load or did not return a table: " .. string.sub(tostring(networkResult), 1, 300))
	return
end
Network = networkResult

local rendererOk, rendererResult = pcall(require, rendererInstance)
if not rendererOk or typeof(rendererResult) ~= "table" then
	fail("UI_Renderer failed to load or did not return a table: " .. string.sub(tostring(rendererResult), 1, 300))
	return
end
local Renderer: any = rendererResult

if typeof(Network.Init) ~= "function" then
	fail("UI_Network is missing Network.Init().")
	return
end
if typeof(Renderer.Mount) ~= "function" then
	fail("UI_Renderer is missing Renderer.Mount().")
	return
end

-- The hardened UI_Network returns false when remotes are unavailable. Do not
-- mount a UI that cannot communicate with the authoritative server.
local initOk, initResult = pcall(Network.Init)
if not initOk or initResult ~= true then
	fail("Network initialization failed. Confirm UI_Server_Controller is running and created ClubMusicRemotes.")
	return
end
ownsNetwork = true

local mountOk, mountResult = pcall(Renderer.Mount, player, Network)
if not mountOk or typeof(mountResult) ~= "table" then
	fail("Renderer.Mount() failed: " .. string.sub(tostring(mountResult), 1, 300))
	return
end
mounted = mountResult

-- Display only validated, bounded text. The network module also sanitizes
-- notices; this second check protects the UI boundary if the module changes.
if typeof(Network.OnNotice) == "function" then
	local subscribeOk, connectionOrError = pcall(function()
		return Network.OnNotice(function(notice: any)
			if cleaned or typeof(notice) ~= "table" then
				return
			end

			local messageValue = notice.text
			if typeof(messageValue) ~= "string" then
				messageValue = notice.message
			end
			if typeof(messageValue) ~= "string" then
				return
			end

			local message = string.sub(messageValue, 1, MAX_NOTICE_LENGTH)
			if message == "" then
				return
			end

			print("[ClubMusic Notice] " .. message)

			local kind = if typeof(notice.kind) == "string" then string.sub(notice.kind, 1, 32) else "info"
			local color = NOTICE_COLORS[kind] or NOTICE_COLORS.info
			if typeof(mounted) == "table" and typeof(mounted.Notify) == "function" then
				pcall(function()
					mounted.Notify(message, color)
				end)
			end
		end)
	end)

	if subscribeOk and typeof(connectionOrError) == "RBXScriptConnection" then
		noticeConnection = connectionOrError
	else
		warn("[ClubMusic Bootstrap] Could not subscribe to server notices: " .. string.sub(tostring(connectionOrError), 1, 200))
	end
end

print("[ClubMusic Bootstrap] UI started successfully.")
