--!strict
-- Bounded, server-local ClubMusic error history.
-- Reporting only: it never retries, repairs, authorizes, or changes subsystem behavior.

local ClubMusicErrorHandler = {}

local MAX_RECORDS = 50
local MAX_DEDUPE_KEYS = 100
local DEDUPE_WINDOW_SECONDS = 10
local MAX_SUBSYSTEM = 64
local MAX_OPERATION = 96
local MAX_MESSAGE = 1200
local MAX_TRACEBACK = 6000

local nextErrorId = 0
local totalErrors = 0
local totalRepeats = 0
local records: {{[string]: any}} = {}
local recentByKey: {[string]: {at: number, id: string, repeats: number}} = {}
local reporter: ((any) -> ())? = nil
local lastErrorAt: number? = nil

function ClubMusicErrorHandler.SetReporter(callback: any): boolean
	if callback ~= nil and typeof(callback) ~= "function" then return false end
	reporter = callback
	return true
end

local function safeString(value: any, limit: number?): string
	local ok, result = pcall(tostring, value)
	if not ok then return "<unprintable error>" end
	result = string.gsub(result, "[%c]", " ")
	return string.sub(result, 1, limit or MAX_MESSAGE)
end

local function safeContextPath(context: Instance?): string
	if not context then return "<none>" end
	local ok, result = pcall(function() return context:GetFullName() end)
	return if ok then safeString(result, 240) else "<context unavailable>"
end

local function findRecord(errorId: string): {[string]: any}?
	for index = #records, 1, -1 do
		if records[index].id == errorId then return records[index] end
	end
	return nil
end

local function pruneDedupe(now: number)
	for key, value in pairs(recentByKey) do
		if now - value.at >= DEDUPE_WINDOW_SECONDS then recentByKey[key] = nil end
	end
	local count = 0
	for _ in pairs(recentByKey) do count += 1 end
	while count > MAX_DEDUPE_KEYS do
		local oldestKey = nil
		local oldestAt = math.huge
		for key, value in pairs(recentByKey) do
			if value.at < oldestAt then oldestAt = value.at; oldestKey = key end
		end
		if not oldestKey then break end
		recentByKey[oldestKey] = nil
		count -= 1
	end
end

function ClubMusicErrorHandler.DescribeChildren(parent: Instance?): string
	if not parent then return "<parent is nil>" end
	local ok, childrenOrError = pcall(function()
		local names = {}
		for _, child in ipairs(parent:GetChildren()) do
			table.insert(names, child.Name .. " [" .. child.ClassName .. "]")
		end
		table.sort(names)
		return names
	end)
	if not ok then
		return "<unable to enumerate children: " .. safeString(childrenOrError, 180) .. ">"
	end
	return if #childrenOrError > 0 then table.concat(childrenOrError, ", ") else "<no direct children>"
end

function ClubMusicErrorHandler.Report(subsystem: string, operation: string, err: any, context: Instance?): string
	local safeSubsystem = safeString(subsystem, MAX_SUBSYSTEM)
	local safeOperation = safeString(operation, MAX_OPERATION)
	local message = safeString(err, MAX_MESSAGE)
	local contextPath = safeContextPath(context)
	local key = safeSubsystem .. "|" .. safeOperation .. "|" .. message .. "|" .. contextPath
	local now = os.clock()
	pruneDedupe(now)

	local recent = recentByKey[key]
	if recent and now - recent.at < DEDUPE_WINDOW_SECONDS then
		recent.at = now
		recent.repeats += 1
		totalRepeats += 1
		local existing = findRecord(recent.id)
		if existing then
			existing.repeats = recent.repeats
			existing.lastSeenAt = os.time()
		end
		return recent.id
	end

	nextErrorId += 1
	totalErrors += 1
	local errorId = "CM-" .. tostring(nextErrorId)
	local traceOk, traceResult = pcall(function()
		return debug.traceback("[ClubMusic] " .. safeSubsystem .. " / " .. safeOperation .. ": " .. message, 2)
	end)
	local trace = if traceOk then safeString(traceResult, MAX_TRACEBACK) else "<traceback unavailable>"
	local wallTime = os.time()
	local record = {
		id = errorId,
		at = now,
		timestamp = wallTime,
		lastSeenAt = wallTime,
		scope = "ServerLocal",
		subsystem = safeSubsystem,
		operation = safeOperation,
		message = message,
		context = contextPath,
		traceback = trace,
		repeats = 0,
	}
	table.insert(records, record)
	if #records > MAX_RECORDS then table.remove(records, 1) end
	recentByKey[key] = {at = now, id = errorId, repeats = 0}
	lastErrorAt = wallTime

	pcall(warn, "[ClubMusic][Error][" .. errorId .. "] " .. safeSubsystem .. " / " .. safeOperation
		.. " | Context=" .. contextPath .. " | " .. message)
	pcall(warn, trace)
	if reporter then
		pcall(reporter, {
			id = errorId,
			timestamp = wallTime,
			scope = "ServerLocal",
			subsystem = safeSubsystem,
			operation = safeOperation,
		})
	end
	return errorId
end

function ClubMusicErrorHandler.SafeRequire(moduleScript: Instance?, label: string): (boolean, any, string?)
	if not moduleScript then
		local id = ClubMusicErrorHandler.Report("ModuleLoader", "Find " .. label, "ModuleScript was not found", nil)
		return false, "ModuleScript was not found: " .. label, id
	end
	if not moduleScript:IsA("ModuleScript") then
		local id = ClubMusicErrorHandler.Report(
			"ModuleLoader", "Validate " .. label,
			"Expected ModuleScript; found " .. moduleScript.ClassName, moduleScript
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
	for index, record in ipairs(records) do copy[index] = table.clone(record) end
	return copy
end

function ClubMusicErrorHandler.GetStatus(): {[string]: any}
	local dedupeCount = 0
	for _ in pairs(recentByKey) do dedupeCount += 1 end
	return {
		state = "Healthy",
		scope = "ServerLocal",
		count = #records,
		maxRecords = MAX_RECORDS,
		dedupeKeys = dedupeCount,
		maxDedupeKeys = MAX_DEDUPE_KEYS,
		totalErrors = totalErrors,
		totalRepeats = totalRepeats,
		lastErrorAt = lastErrorAt,
		updatedAt = os.time(),
	}
end

return ClubMusicErrorHandler
