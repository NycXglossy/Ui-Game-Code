--!strict
-- Server-local observational watchdog for ClubMusic subsystem progress.
-- It never advances playback, refills queues, retries services, or enforces moderation.

local Watchdog = {}
Watchdog.__index = Watchdog

local MAX_DETAIL = 140

local DEFAULT_PROBES = {
	Playback = {expected = true, staleAfter = 12},
	AutoDJ = {expected = true, staleAfter = 900},
	Queue = {expected = true, staleAfter = 900},
	Moderation = {expected = false, staleAfter = 0},
	Recovery = {expected = false, staleAfter = 0},
}

local function validName(name: any): boolean
	return typeof(name) == "string" and DEFAULT_PROBES[name] ~= nil
end

local function cleanText(value: any): string
	local ok, result = pcall(tostring, value)
	if not ok then return "unavailable" end
	result = string.gsub(result, "[%c]", " ")
	return string.sub(result, 1, MAX_DETAIL)
end

function Watchdog.new()
	local probes = {}
	for name, defaults in pairs(DEFAULT_PROBES) do
		probes[name] = {
			expected = defaults.expected,
			staleAfter = defaults.staleAfter,
			lastAt = nil,
			lastDetail = "Awaiting first progress signal.",
			count = 0,
			lastHealthy = true,
			metadata = {},
		}
	end
	return setmetatable({
		probes = probes,
		startedAt = os.clock(),
		updatedAt = os.time(),
	}, Watchdog)
end

function Watchdog:SetExpected(name: any, expected: any, detail: any?): boolean
	if not validName(name) or typeof(expected) ~= "boolean" then return false end
	local probe = self.probes[name]
	probe.expected = expected
	probe.lastDetail = cleanText(detail or (if expected then "Monitoring enabled." else "Monitoring paused."))
	self.updatedAt = os.time()
	return true
end

function Watchdog:Pulse(name: any, detail: any?, healthy: any?, metadata: any?): boolean
	if not validName(name) then return false end
	local probe = self.probes[name]
	probe.lastAt = os.clock()
	probe.lastDetail = cleanText(detail or "Progress observed.")
	probe.count = math.min(1000000000, probe.count + 1)
	probe.lastHealthy = healthy ~= false
	probe.metadata = {}
	if typeof(metadata) == "table" then
		for key, value in pairs(metadata) do
			if typeof(key) == "string" and #key <= 24
				and (typeof(value) == "string" or typeof(value) == "number" or typeof(value) == "boolean") then
					probe.metadata[key] = if typeof(value) == "string" then cleanText(value) else value
			end
		end
	end
	self.updatedAt = os.time()
	return true
end

function Watchdog:GetStatus(): {[string]: any}
	local now = os.clock()
	local result = {}
	local issues = {}
	local pending = {}
	local count = 0
	for name, probe in pairs(self.probes) do
		count += 1
		local age = if probe.lastAt then math.max(0, now - probe.lastAt) else nil
		local state = "Disabled"
		if probe.expected then
			if not probe.lastAt then
				state = if now - self.startedAt < 30 then "Starting" else "Unavailable"
				table.insert(pending, name .. " has not reported progress (" .. string.lower(state) .. ").")
			elseif not probe.lastHealthy then
				state = "Degraded"
				table.insert(issues, name .. ": " .. probe.lastDetail)
			elseif probe.staleAfter > 0 and age and age > probe.staleAfter then
				state = "Degraded"
				table.insert(issues, name .. " progress is stale (" .. tostring(math.floor(age)) .. "s).")
			else
				state = "Healthy"
			end
		elseif probe.lastAt then
			state = if probe.lastHealthy then "Healthy" else "Degraded"
			if state == "Degraded" then table.insert(issues, name .. ": " .. probe.lastDetail) end
		end
		result[name] = {
			state = state,
			expected = probe.expected,
			lastAt = probe.lastAt,
			ageSeconds = age,
			staleAfterSeconds = probe.staleAfter,
			count = probe.count,
			detail = probe.lastDetail,
			metadata = table.clone(probe.metadata),
		}
	end
	table.sort(issues)
	table.sort(pending)
	local state = if #issues > 0 then "Degraded" elseif #pending > 0 then "Starting" else "Healthy"
	return {
		state = state,
		scope = "ServerLocal",
		observationalOnly = true,
		detail = if #issues > 0 then table.concat(issues, "; ")
			elseif #pending > 0 then table.concat(pending, "; ")
			else "Observed subsystem progress is within configured windows.",
		issues = issues,
		pending = pending,
		probeCount = count,
		probes = result,
		updatedAt = self.updatedAt,
	}
end

return Watchdog
