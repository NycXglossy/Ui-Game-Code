--!strict
-- ServerStorage/ClubNeon_StartupErrorReporter.lua
-- Adapts optional structured diagnostics to the controller's startup status attributes.

local StartupErrorReporter = {}

function StartupErrorReporter.initialize(ControllerFunctions: {[string]: any}, remotes: Instance)
	ControllerFunctions.reportStartupError = function(subsystem: string, operation: string, message: string, context: Instance?): string
		local errorId = "CM-STARTUP"
		local handler = ControllerFunctions.ErrorHandler
		if handler then
			local reportOk, reportResult = pcall(handler.Report, subsystem, operation, message, context)
			if reportOk and typeof(reportResult) == "string" then
				errorId = reportResult
			else
				warn("[ClubMusic][Diagnostics] Error handler reporting failed: " .. tostring(reportResult))
			end
		else
			warn("[ClubMusic][Error][" .. errorId .. "] " .. subsystem .. " / " .. operation .. ": " .. message)
			if context then
				warn("[ClubMusic][Diagnostics] Context=" .. context:GetFullName())
			end
		end
		local startupMessage = "[" .. errorId .. "] " .. string.sub(message, 1, 850)
		pcall(function()
			remotes:SetAttribute("StartupError", startupMessage)
		end)
		return errorId
	end
end

return StartupErrorReporter
