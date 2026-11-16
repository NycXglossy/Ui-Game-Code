--!strict
-- Server-local diagnostics coordinator.
-- Observation only: no DataStore, MemoryStore, MessagingService, remotes, or control actions.
-- Optional subsystem failures are represented as unavailable/degraded data and never
-- prevent the owning ClubMusic services from starting.

local Service = {}
Service.__index = Service

local MAX_METRICS = 64
local MAX_ERROR_RECORDS = 20
local CHECK_INTERVAL_SECONDS = 60

local function safeRead(callback: any, ...)
	if type(callback) ~= "function" then return false, nil end
	local ok, result = pcall(callback, ...)
	if not ok then return false, nil end
	return true, result
end

local function cloneTable(value: any, depth: number?, seen: {[any]: any}?): any
	if typeof(value) ~= "table" then return value end
	local level = depth or 0
	if level >= 6 then return "<depth-limit>" end
	local visited = seen or {}
	if visited[value] then return "<cycle>" end
	local result = {}
	visited[value] = result
	local count = 0
	for key, item in pairs(value) do
		count += 1
		if count > 256 then result.truncated = true; break end
		local safeKey = if typeof(key) == "string" or typeof(key) == "number" then key else tostring(key)
		if typeof(item) == "table" then
			result[safeKey] = cloneTable(item, level + 1, visited)
		elseif typeof(item) == "string" then
			result[safeKey] = string.sub(item, 1, 2048)
		elseif typeof(item) == "number" or typeof(item) == "boolean" then
			result[safeKey] = item
		end
	end
	visited[value] = nil
	return result
end

local function statusFallback(label: string, detail: string?): {[string]: any}
	return {
		state = "Unavailable",
		detail = detail or (label .. " status is unavailable."),
		available = false,
	}
end

function Service.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table" and type(dependencies.isEnabled) == "function",
		"Diagnostics dependencies missing")
	return setmetatable({
		d = dependencies,
		running = false,
		status = {
			state = "Starting",
			detail = "Waiting for the first local diagnostics pass.",
			localState = "Starting",
			localDetail = "Initial check pending.",
			serviceState = "Starting",
			recoveryState = "Starting",
			recoveryDetail = "Recovery status is not available yet.",
			syncState = "LocalOnly",
			syncDetail = "Diagnostics are isolated to this server.",
			updatedAt = os.time(),
		},
		metrics = {},
		lastSignature = "",
		lastCheckAt = 0,
		lastCheckError = nil,
	}, Service)
end

function Service:Record(name: any, value: any, latencySeconds: any): boolean
	if typeof(name) ~= "string" or #name == 0 or #name > 48
		or not string.match(name, "^[%w_:%-%.]+$") then return false end
	local amount = if type(value) == "number" and value == value and value >= 0 and value < math.huge then value else 1
	local item = self.metrics[name]
	if item == nil then
		local metricCount = 0
		for _ in pairs(self.metrics) do metricCount += 1 end
		if metricCount >= MAX_METRICS then return false end
		item = {count = 0, latencyCount = 0, latencyTotal = 0, latencyMax = 0}
	end
	item.count = math.min(1000000000, item.count + amount)
	if type(latencySeconds) == "number" and latencySeconds == latencySeconds
		and latencySeconds >= 0 and latencySeconds <= 120 then
		item.latencyCount += 1
		item.latencyTotal = math.min(1000000000, item.latencyTotal + latencySeconds)
		item.latencyMax = math.max(item.latencyMax, latencySeconds)
	end
	self.metrics[name] = item
	return true
end

function Service:_readStatus(name: string, callback: any): {[string]: any}
	if type(callback) ~= "function" then
		return {state = "NotInstalled", detail = name .. " probe is not installed.", available = false}
	end
	local ok, result = safeRead(callback)
	if ok and typeof(result) == "table" then return cloneTable(result) end
	return statusFallback(name, if ok then nil else (name .. " status callback failed."))
end

function Service:Check(): boolean
	local enabledOk, enabled = safeRead(self.d.isEnabled)
	if not enabledOk then
		self.status = {
			state = "Degraded",
			detail = "Global service enabled state could not be read.",
			localState = "Healthy",
			localDetail = "Diagnostics coordinator is running locally.",
			serviceState = "Unknown",
			recoveryState = "Unavailable",
			recoveryDetail = "Recovery status is unavailable.",
			syncState = "LocalOnly",
			syncDetail = "Diagnostics do not use cross-server synchronization.",
			updatedAt = os.time(),
		}
		return false
	end
	if enabled ~= true then
		self.status = {
			state = "Disabled",
			detail = "Cross-server ClubMusic services are disabled in this server.",
			localState = "Healthy",
			localDetail = "Local diagnostics remain available.",
			serviceState = "Disabled",
			recoveryState = "Disabled",
			recoveryDetail = "Global recovery is not running.",
			syncState = "LocalOnly",
			syncDetail = "Diagnostics are isolated to this server.",
			updatedAt = os.time(),
		}
		self.lastCheckAt = os.clock()
		return true
	end

	local apiFolder = self.d.apiFolder
	local apiOk = false
	if typeof(apiFolder) == "Instance" then
		local ok, result = pcall(function()
			return apiFolder.Parent == game:GetService("ServerStorage")
		end)
		apiOk = ok and result == true
	end
	local queueModule = self.d.queueModule
	local queueConfigured = queueModule ~= nil
	local queueOk = not queueConfigured
	if queueConfigured and typeof(queueModule) == "Instance" then
		local ok, result = pcall(function()
			return queueModule:IsA("ModuleScript") and queueModule.Parent ~= nil
		end)
		queueOk = ok and result == true
	end

	local recovery = self:_readStatus("Recovery", self.d.getRecoveryStatus)
	local sync = self:_readStatus("Synchronization", self.d.getSyncStatus)
	local registry = self:_readStatus("ServiceRegistry", self.d.getRegistryStatus)
	local serverHealth = self:_readStatus("ServerHealth", self.d.getServerHealthStatus)
	local watchdog = self:_readStatus("Watchdog", self.d.getWatchdogStatus)

	local issues = {}
	if not apiOk then table.insert(issues, "Global API folder is unavailable.") end
	if queueConfigured and not queueOk then table.insert(issues, "Configured global queue module is unavailable.") end
	for _, entry in ipairs({{name = "Recovery", data = recovery}, {name = "ServiceRegistry", data = registry},
		{name = "ServerHealth", data = serverHealth}, {name = "Watchdog", data = watchdog}}) do
		local state = tostring(entry.data.state or "Unavailable")
		if state == "Degraded" or state == "Unhealthy" or state == "Failed" then
			table.insert(issues, entry.name .. ": " .. tostring(entry.data.detail or state))
		end
	end

	local pending = {}
	for _, entry in ipairs({{name = "Recovery", data = recovery}, {name = "ServiceRegistry", data = registry},
		{name = "ServerHealth", data = serverHealth}, {name = "Watchdog", data = watchdog}}) do
		local state = tostring(entry.data.state or "Unavailable")
		if state == "Starting" or state == "Unavailable" or state == "NotInstalled" then
			table.insert(pending, entry.name .. " status is " .. string.lower(state) .. ".")
		end
	end

	local state = if #issues > 0 then "Degraded" elseif #pending > 0 then "Starting" else "Healthy"
	local detail = if #issues > 0 then table.concat(issues, "; ")
		elseif #pending > 0 then table.concat(pending, "; ")
		else "Local diagnostics dependencies and available health probes are healthy."
	local localState = if apiOk and queueOk then "Healthy" else "Degraded"
	local performanceState = if serverHealth.state == "Unavailable" or serverHealth.state == "NotInstalled"
		then "NotInstalled" else tostring(serverHealth.state or "Unknown")
	local watchdogState = if watchdog.state == "Unavailable" or watchdog.state == "NotInstalled"
		then "NotInstalled" else tostring(watchdog.state or "Unknown")

	self.status = {
		state = state,
		detail = detail,
		localState = localState,
		crossServerState = if enabled == true then "Enabled" else "Disabled",
		crossServerDetail = if enabled == true
			then "Reports this server's global-service availability only; no peer-server diagnostics are collected."
			else "Cross-server services are disabled in this server.",
		performanceState = performanceState,
		watchdogState = watchdogState,
		localDetail = if localState ~= "Healthy" then "One or more configured local service dependencies are unavailable."
			elseif queueConfigured then "Local API and configured queue dependency are available."
			else "Local API is available; no separate global queue ModuleScript is configured.",
		serviceState = "Enabled",
		recoveryState = tostring(recovery.state or "Unavailable"),
		recoveryDetail = tostring(recovery.detail or recovery.state or "Recovery status is unavailable."),
		syncState = "LocalOnly",
		syncDetail = "Diagnostics are server-local; cross-server peer state is intentionally not collected.",
		checks = {Api = apiOk, QueueModule = queueOk, QueueModuleConfigured = queueConfigured},
		serviceRegistry = registry,
		serverHealth = serverHealth,
		watchdog = watchdog,
		updatedAt = os.time(),
	}
	self.lastCheckAt = os.clock()
	self.lastCheckError = nil
	local signature = state .. "|" .. detail
	if signature ~= self.lastSignature then
		self.lastSignature = signature
		if state == "Degraded" then warn("[ClubMusic Diagnostics] " .. detail) end
	end
	return state ~= "Degraded"
end

function Service:GetStatus(): {[string]: any}
	local status = cloneTable(self.status)
	status.lastCheckAgeSeconds = if self.lastCheckAt > 0
		then math.max(0, os.clock() - self.lastCheckAt) else nil
	status.lastCheckError = self.lastCheckError
	status.checkIntervalSeconds = CHECK_INTERVAL_SECONDS
	return status
end

function Service:GetMetrics(): {[string]: any}
	local counters = {}
	local structuredCounters = {}
	for name, values in pairs(self.metrics) do
		structuredCounters[name] = table.clone(values)
		counters[name] = values.count
	end
	return {
		state = "Available",
		scope = "ServerLocal",
		counters = structuredCounters,
		aggregate = {scope = "ServerLocal", counters = counters},
		updatedAt = os.time(),
	}
end

function Service:GetSnapshot(): {[string]: any}
	local recovery = self:_readStatus("Recovery", self.d.getRecoveryStatus)
	local sync = self:_readStatus("Synchronization", self.d.getSyncStatus)
	local errors, errorsAvailable = {}, false
	local errorsOk, recent = safeRead(self.d.getRecentErrors)
	if errorsOk and typeof(recent) == "table" then
		errorsAvailable = true
		local first = math.max(1, #recent - MAX_ERROR_RECORDS + 1)
		for index = first, #recent do
			if typeof(recent[index]) == "table" then table.insert(errors, table.clone(recent[index])) end
		end
	end
	local enabledOk, enabled = safeRead(self.d.isEnabled)
	local serviceRegistry = self:_readStatus("ServiceRegistry", self.d.getRegistryStatus)
	local serverHealth = self:_readStatus("ServerHealth", self.d.getServerHealthStatus)
	local watchdog = self:_readStatus("Watchdog", self.d.getWatchdogStatus)
	local metrics = self:GetMetrics()

	local health = self:GetStatus()
	local healthAvailable = typeof(health) == "table"
		and health.state ~= "Unavailable" and health.state ~= "NotInstalled"
	local metricsAvailable = typeof(metrics) == "table" and metrics.state == "Available"
	return {
		generatedAt = os.time(),
		serviceEnabled = enabledOk and enabled == true,
		healthAvailable = healthAvailable,
		health = health,
		recoveryAvailable = recovery.state ~= "Unavailable" and recovery.state ~= "NotInstalled",
		recovery = recovery,
		syncStatus = sync,
		errorHistoryAvailable = errorsAvailable,
		recentErrors = errors,
		metrics = metrics,
		metricsAvailable = metricsAvailable,
		operationalServices = {
			memoryStore = self:_readStatus("MemoryStore", self.d.getMemoryStoreStatus),
			diagnostics = self:GetStatus(),
			serviceRegistry = serviceRegistry,
			serverHealth = serverHealth,
			watchdog = watchdog,
			securityMonitor = self:_readStatus("SecurityMonitor", self.d.getSecurityMonitorStatus),
			messageValidation = self:_readStatus("MessageValidation", self.d.getMessageValidationStatus),
			idempotency = self:_readStatus("Idempotency", self.d.getIdempotencyStatus),
			errorHistory = self:_readStatus("ErrorHistory", self.d.getErrorHistoryStatus),
		},
	}
end

function Service:Start(): boolean
	if self.running then return false end
	self.running = true
	task.spawn(function()
		while self.running do
			local ok, err = pcall(self.Check, self)
			if not ok then
				self.lastCheckError = string.sub(tostring(err), 1, 240)
				warn("[ClubMusic Diagnostics] Check failed: " .. self.lastCheckError)
			end
			task.wait(CHECK_INTERVAL_SECONDS)
		end
	end)
	return true
end

function Service:Stop()
	self.running = false
end

return Service
