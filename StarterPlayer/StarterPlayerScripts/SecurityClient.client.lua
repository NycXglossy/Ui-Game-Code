--!strict
-- StarterPlayer/StarterPlayerScripts/SecurityClient (LocalScript)
-- Client presentation only. ServerSecurity decides who receives staff alerts
-- and validates every report; this script is not an authorization boundary.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local localPlayer = Players.LocalPlayer
local securityFolder = ReplicatedStorage:WaitForChild("SecuritySystem")
local staffAlertEvent = securityFolder:WaitForChild("StaffAlert") :: RemoteEvent
local reportEvent = securityFolder:WaitForChild("ReportIncident") :: RemoteEvent

local function safeText(value: any, fallback: string): string
	if typeof(value) ~= "string" and typeof(value) ~= "number" then
		return fallback
	end
	local result = tostring(value)
	result = string.gsub(result, "[%c]", " ")
	if result == "" then return fallback end
	return string.sub(result, 1, 180)
end

local function showNotification(title: string, message: string)
	local notification = {
		Title = title,
		Text = message,
		Duration = 8,
	}
	-- SetCore may not be ready at LocalScript startup. Retry briefly rather
	-- than dropping the first dispatch alert.
	task.spawn(function()
		for attempt = 1, 5 do
			local ok = pcall(function()
				StarterGui:SetCore("SendNotification", notification)
			end)
			if ok then return end
			task.wait(1)
		end
		warn("[Tiki Tide][SecurityClient] Roblox notification API was unavailable.")
	end)
end

staffAlertEvent.OnClientEvent:Connect(function(incident: any)
	if typeof(incident) ~= "table" then return end

	-- Accept the Phase 21 legacy field names and the structured server fields.
	local incidentId = safeText(incident.Id or incident.incidentId, "Pending")
	local category = safeText(incident.Category or incident.kind, "Security Alert")
	local targetName = safeText(incident.TargetName or incident.subjectUserId, "Unknown player")
	local reason = safeText(incident.Reason or incident.summary, "No additional details")
	local reporterName = safeText(incident.ReporterName or incident.reporterUserId, "System")

	local alertText = string.format(
		"[%s] %s - %s (By: %s)",
		category,
		targetName,
		reason,
		reporterName
	)
	showNotification("🚨 Security Dispatch #" .. incidentId, alertText)
end)

-- Call this from your report button's Activated callback after selecting a
-- target Player and reading the reason TextBox. The server repeats all checks.
local function submitPlayerReport(targetPlayer: Player?, reasonText: string): boolean
	if not targetPlayer or not targetPlayer:IsA("Player") then return false end
	if targetPlayer == localPlayer or targetPlayer.Parent ~= Players then return false end
	if typeof(reasonText) ~= "string" then return false end

	local reason = string.match(reasonText, "^%s*(.-)%s*$") or ""
	if reason == "" or #reason > 400 then return false end

	reportEvent:FireServer(targetPlayer.UserId, reason)
	return true
end

-- Example UI wiring:
-- reportButton.Activated:Connect(function()
--     local targetPlayer = Players:FindFirstChild(targetNameTextBox.Text)
--     if submitPlayerReport(targetPlayer, reasonTextBox.Text) then
--         print("Report submitted for server validation.")
--     end
-- end)

-- Keep the helper available to code below in this LocalScript; do not expose
-- report submission through _G or treat client-side validation as security.
