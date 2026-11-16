--!strict
-- Centralized protected-call diagnostics for ClubMusic global services.
-- This module observes failures only; it never changes authorization or recovery policy.
local SafeCall = {}
SafeCall.__index = SafeCall

local MAX_RECORDS = 50
local MAX_TEXT = 240
local WARN_COOLDOWN = 30
local WARNING_TTL = 120
local MAX_WARNING_KEYS = 100

local function clean(value: any): string
	local ok, result = pcall(tostring, value or "")
	local text = if ok then result else "<unprintable>"
	text = string.gsub(text, "[%c]", " ")
	return string.sub(text, 1, MAX_TEXT)
end

local function pruneWarnings(warnings: {[string]: number}, now: number)
	local count = 0
	local oldestKey: string? = nil
	local oldestAt = math.huge
	for key, at in pairs(warnings) do
		if now - at >= WARNING_TTL then
			warnings[key] = nil
		else
			count += 1
			if at < oldestAt then oldestAt = at; oldestKey = key end
		end
	end
	if count >= MAX_WARNING_KEYS and oldestKey then warnings[oldestKey] = nil end
end

local function shouldWarn(self: any, signature: string, now: number): boolean
	pruneWarnings(self.lastWarnings, now)
	local lastWarn = self.lastWarnings[signature] or 0
	if now - lastWarn < WARN_COOLDOWN then return false end
	self.lastWarnings[signature] = now
	return true
end

function SafeCall.new(dependencies: {[string]: any}?)
	local d = if typeof(dependencies) == "table" then dependencies else {}
	return setmetatable({
		serviceName = clean(d.serviceName or "ClubMusicGlobal"),
		records = {},
		counts = {calls = 0, failures = 0, recovered = 0},
		lastSuccess = nil,
		lastFailure = nil,
		lastWarnings = {},
	}, SafeCall)
end

function SafeCall:Run(serviceName: string, operation: string, callback: (...any) -> ...any, ...: any): ...any
	self.counts.calls += 1
	if type(callback) ~= "function" then
		self:RecordFailure(serviceName, operation, "Callback is not a function.")
		return false, "Callback is not a function.", "Callback is not a function."
	end
	local packed = table.pack(pcall(callback, ...))
	local ok = packed[1] == true
	local now = os.time()
	local service = clean(serviceName ~= "" and serviceName or self.serviceName)
	local op = clean(operation)
	if ok then
		self.lastSuccess = {service = service, operation = op, at = now}
		return table.unpack(packed, 1, packed.n)
	end

	local err = clean(packed[2])
	local trace = err
	if debug and type(debug.traceback) == "function" then
		local traceOk, traceResult = pcall(debug.traceback, err, 2)
		if traceOk then trace = clean(traceResult) end
	end
	self.counts.failures += 1
	self.lastFailure = {service = service, operation = op, error = err, traceback = trace, at = now}
	local record = table.clone(self.lastFailure)
	table.insert(self.records, 1, record)
	while #self.records > MAX_RECORDS do table.remove(self.records) end

	local signature = service .. "|" .. op .. "|" .. err
	if shouldWarn(self, signature, now) then
		warn("[ClubMusic][SafeCall] Operation failed; service=" .. service
			.. "; operation=" .. op .. "; error=" .. err)
	end
	return false, err, trace
end

function SafeCall:RecordFailure(serviceName: string, operation: string, detail: any)
	local now = os.time()
	local service = clean(serviceName)
	local op = clean(operation)
	local err = clean(detail)
	self.counts.failures += 1
	self.lastFailure = {service = service, operation = op, error = err, traceback = err, at = now}
	table.insert(self.records, 1, table.clone(self.lastFailure))
	while #self.records > MAX_RECORDS do table.remove(self.records) end
	local signature = service .. "|" .. op .. "|" .. err
	if shouldWarn(self, signature, now) then
		warn("[ClubMusic][SafeCall] Operation reported failure; service=" .. service
			.. "; operation=" .. op .. "; detail=" .. err)
	end
end

function SafeCall:RecordRecovery(serviceName: string, operation: string)
	self.counts.recovered += 1
	local record = {service = clean(serviceName), operation = clean(operation), at = os.time()}
	self.lastSuccess = record
	print("[ClubMusic][SafeCall] Operation recovered; service=" .. record.service .. "; operation=" .. record.operation)
end

function SafeCall:GetRecent(limit: number?): {any}
	local count = math.clamp(math.floor(tonumber(limit) or 20), 1, MAX_RECORDS)
	local out = {}
	for index = 1, math.min(count, #self.records) do
		out[index] = table.clone(self.records[index])
	end
	return out
end

function SafeCall:GetStatus(): {[string]: any}
	local warningKeyCount = 0
	for _ in pairs(self.lastWarnings) do warningKeyCount += 1 end
	return {
		service = self.serviceName,
		warningKeyCount = warningKeyCount,
		maxWarningKeys = MAX_WARNING_KEYS,
		warningTtlSeconds = WARNING_TTL,
		calls = self.counts.calls,
		failures = self.counts.failures,
		recovered = self.counts.recovered,
		lastSuccess = if self.lastSuccess then table.clone(self.lastSuccess) else nil,
		lastFailure = if self.lastFailure then table.clone(self.lastFailure) else nil,
		recentFailureCount = #self.records,
	}
end

return SafeCall
