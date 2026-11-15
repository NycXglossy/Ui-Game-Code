--!strict
-- Centralized protected-call diagnostics for ClubMusic global services.
-- This module observes failures only; it never changes authorization or recovery policy.
local SafeCall = {}
SafeCall.__index = SafeCall

local MAX_RECORDS = 50
local MAX_TEXT = 240
local WARN_COOLDOWN = 30

local function clean(value: any): string
	local text = tostring(value or "")
	text = string.gsub(text, "[%c]", " ")
	return string.sub(text, 1, MAX_TEXT)
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
	local lastWarn = self.lastWarnings[signature] or 0
	if now - lastWarn >= WARN_COOLDOWN then
		self.lastWarnings[signature] = now
		warn("[ClubMusic][SafeCall] Operation failed; service=" .. service
			.. "; operation=" .. op .. "; error=" .. err)
	end
	return false, err, trace
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
	return {
		service = self.serviceName,
		calls = self.counts.calls,
		failures = self.counts.failures,
		recovered = self.counts.recovered,
		lastSuccess = if self.lastSuccess then table.clone(self.lastSuccess) else nil,
		lastFailure = if self.lastFailure then table.clone(self.lastFailure) else nil,
		recentFailureCount = #self.records,
	}
end

return SafeCall
