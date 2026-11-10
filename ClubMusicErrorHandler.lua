--!strict
-- Centralized, bounded diagnostics for ClubMusic server-side failures.
-- This module reports errors; it does not swallow failures or change subsystem behavior.

local ClubMusicErrorHandler = {}

local MAX_RECORDS = 50
local DEDUPE_WINDOW_SECONDS = 10
local nextErrorId = 0
local records: {{id: string, at: number, subsystem: string, operation: string, message: string, traceback: string}} = {}
local recentByKey: {[string]: {at: number, id: string, repeats: number}} = {}

local function safeString(value: any): string
	local ok, result = pcall(tostring, value)
	return if ok then string.sub(result, 1, 1200) else "<unprintable error>"
end

function ClubMusicErrorHandler.DescribeChildren(parent: Instance?): string
	if not parent then
		return "<parent is nil>"
	end

	local ok, childrenOrError = pcall(function()
		local names = {}
		for _, child in ipairs(parent:GetChildren()) do
			table.insert(names, child.Name .. " [" .. child.ClassName .. "]")
		end
		table.sort(names)
		return names
	end)

	if not ok then
		return "<unable to enumerate children: " .. safeString(childrenOrError) .. ">"
	end
	return if #childrenOrError > 0 then table.concat(childrenOrError, ", ") else "<no direct children>"
end

function ClubMusicErrorHandler.Report(subsystem: string, operation: string, err: any, context: Instance?): string
	local message = safeString(err)
	local contextPath = if context then safeString(context:GetFullName()) else "<none>"
	local key = subsystem .. "|" .. operation .. "|" .. message .. "|" .. contextPath
	local now = os.clock()
	local recent = recentByKey[key]

	if recent and now - recent.at < DEDUPE_WINDOW_SECONDS then
		recent.repeats += 1
		return recent.id
	end

	nextErrorId += 1
	local errorId = "CM-" .. tostring(nextErrorId)
	local trace = debug.traceback("[ClubMusic] " .. subsystem .. " / " .. operation .. ": " .. message, 2)
	local record = {
		id = errorId,
		at = now,
		subsystem = subsystem,
		operation = operation,
		message = message,
		traceback = trace,
	}
	table.insert(records, record)
	if #records > MAX_RECORDS then
		table.remove(records, 1)
	end
	recentByKey[key] = {at = now, id = errorId, repeats = 0}

	local detail = "[ClubMusic][Error][" .. errorId .. "] " .. subsystem .. " / " .. operation
		.. " | Context=" .. contextPath .. " | " .. message
	pcall(warn, detail)
	pcall(warn, trace)
	return errorId
end

function ClubMusicErrorHandler.SafeRequire(moduleScript: Instance?, label: string): (boolean, any, string?)
	if not moduleScript then
		local id = ClubMusicErrorHandler.Report("ModuleLoader", "Find " .. label, "ModuleScript was not found", nil)
		return false, "ModuleScript was not found: " .. label, id
	end
	if not moduleScript:IsA("ModuleScript") then
		local id = ClubMusicErrorHandler.Report(
			"ModuleLoader",
			"Validate " .. label,
			"Expected ModuleScript; found " .. moduleScript.ClassName,
			moduleScript
		)
		return false, "Expected ModuleScript; found " .. moduleScript.ClassName, id
	end

	local ok, result = pcall(require, moduleScript)
	if not ok then
		local id = ClubMusicErrorHandler.Report("ModuleLoader", "Require " .. label, result, moduleScript)
		return false, result, id
	end
	return true, result, nil
end

function ClubMusicErrorHandler.GetRecentErrors(): {any}
	local copy = {}
	for index, record in ipairs(records) do
		copy[index] = table.clone(record)
	end
	return copy
end

return ClubMusicErrorHandler
