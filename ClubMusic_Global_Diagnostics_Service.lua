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
local MAX_HEALTH_TRANSITIONS = 20

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
		healthHistory = {},
		lastHealthState = nil,
		healthStateSince = os.time(),
		degradedSince = nil,
		lastRecoveredAt = nil,
		consecutiveDegradedChecks = 0,
		healthTransitionCount = 0,
	}, Service)
end

function Service:Record(name: any, value: any, latencySeconds: any, outcome: any): boolean
	if typeof(name) ~= "string" or #name == 0 or #name > 48
		or not string.match(name, "^[%w_:%-%.]+$")
		or (outcome ~= nil and outcome ~= "Success" and outcome ~= "Failure" and outcome ~= "Observed") then return false end
	local amount = if type(value) == "number" and value == value and value >= 0 and value < math.huge then value else 1
	local item = self.metrics[name]
	if item == nil then
		local metricCount = 0
		for _ in pairs(self.metrics) do metricCount += 1 end
		if metricCount >= MAX_METRICS then return false end
		item = {count = 0, latencyCount = 0, latencyTotal = 0, latencyMax = 0, successCount = 0, failureCount = 0, lastSuccessAt = nil, lastFailureAt = nil, lastOutcome = "Observed"}
	end
	item.count = math.min(1000000000, item.count + amount)
	if outcome == "Success" then
		item.successCount = math.min(1000000000, item.successCount + amount)
		item.lastSuccessAt = os.time()
		item.lastOutcome = "Success"
	elseif outcome == "Failure" then
		item.failureCount = math.min(1000000000, item.failureCount + amount)
		item.lastFailureAt = os.time()
		item.lastOutcome = "Failure"
	elseif outcome == "Observed" or outcome == nil then
		item.lastOutcome = "Observed"
	end
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

function Service:_recordHealthState(state: string, detail: string)
	local now = os.time()
	local previous = self.lastHealthState
	if previous ~= state then
		table.insert(self.healthHistory, {
			from = previous or "Unknown",
			to = state,
			at = now,
			durationSeconds = math.max(0, now - (self.healthStateSince or now)),
			detail = string.sub(tostring(detail or state), 1, 180),
		})
		while #self.healthHistory > MAX_HEALTH_TRANSITIONS do table.remove(self.healthHistory, 1) end
		self.lastHealthState = state
		self.healthStateSince = now
		self.healthTransitionCount = math.min(1000000000, self.healthTransitionCount + 1)
		if previous == "Degraded" and state ~= "Degraded" then self.lastRecoveredAt = now end
	end
	if state == "Degraded" then
		self.degradedSince = self.degradedSince or now
		self.consecutiveDegradedChecks = math.min(1000000000, self.consecutiveDegradedChecks + 1)
	else
		self.degradedSince = nil
		self.consecutiveDegradedChecks = 0
	end
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
		self:_recordHealthState("Degraded", self.status.detail)
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
		self:_recordHealthState("Disabled", self.status.detail)
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
	self:_recordHealthState(state, detail)
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
	status.healthHistory = cloneTable(self.healthHistory)
	status.healthHistoryCapacity = MAX_HEALTH_TRANSITIONS
	status.healthTransitionCount = self.healthTransitionCount
	status.stateDurationSeconds = math.max(0, os.time() - (self.healthStateSince or os.time()))
	status.degradedDurationSeconds = if self.degradedSince then math.max(0, os.time() - self.degradedSince) else 0
	status.consecutiveDegradedChecks = self.consecutiveDegradedChecks
	status.lastRecoveredAt = self.lastRecoveredAt
	status.scope = "ServerLocal"
	status.observationalOnly = true
	return status
end

function Service:GetMetrics(): {[string]: any}
	if type(self.d.allowAnalyticsAggregation) == "function" then
		local budgetOk, allowed = pcall(self.d.allowAnalyticsAggregation)
		if budgetOk and allowed == false then
			return {
				state = "Deferred",
				scope = "ServerLocal",
				deferred = true,
				detail = "Optional metrics aggregation was deferred by the adaptive workload budget.",
				counters = {},
				aggregate = {scope = "ServerLocal", counters = {}},
				updatedAt = os.time(),
			}
		end
	end
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
	local operationalServices = {
		memoryStore = self:_readStatus("MemoryStore", self.d.getMemoryStoreStatus),
		diagnostics = self:GetStatus(),
		serviceRegistry = serviceRegistry,
		serverHealth = serverHealth,
		watchdog = watchdog,
		authorization = self:_readStatus("Authorization", self.d.getAuthorizationStatus),
		rateLimit = self:_readStatus("RateLimit", self.d.getRateLimitStatus),
		securityPolicy = self:_readStatus("SecurityPolicy", self.d.getSecurityPolicyStatus),
		securityMonitor = self:_readStatus("SecurityMonitor", self.d.getSecurityMonitorStatus),
		messageValidation = self:_readStatus("MessageValidation", self.d.getMessageValidationStatus),
		idempotency = self:_readStatus("Idempotency", self.d.getIdempotencyStatus),
		audit = self:_readStatus("Audit", self.d.getAuditStatus),
		eventLog = self:_readStatus("EventLog", self.d.getEventLogStatus),
		incidentResponse = self:_readStatus("IncidentResponse", self.d.getIncidentResponseStatus),
		errorHistory = self:_readStatus("ErrorHistory", self.d.getErrorHistoryStatus),
		adaptiveLoad = self:_readStatus("AdaptiveLoad", self.d.getAdaptiveLoadStatus),
		securityReplay = self:_readStatus("SecurityReplay", self.d.getSecurityReplayStatus),
		threatIntelligence = self:_readStatus("ThreatIntelligence", self.d.getThreatIntelligenceStatus),
		honeypot = self:_readStatus("Honeypot", self.d.getHoneypotStatus),
		clientIntegrityTelemetry = self:_readStatus("ClientIntegrityTelemetry", self.d.getClientIntegrityStatus),
		controller = self:_readStatus("Controller", self.d.getControllerDiagnostics),
		characterPhysics = self:_readStatus("CharacterPhysics", self.d.getCharacterPhysicsStatus),
		safeCall = self:_readStatus("SafeCall", self.d.getSafeCallStatus),
	}
	local securityStates = {}
	local securityObserved = 0
	local securityUnavailable = 0
	for _, key in ipairs({"authorization", "rateLimit", "securityPolicy", "securityMonitor",
		"messageValidation", "idempotency", "audit", "eventLog", "incidentResponse", "threatIntelligence", "honeypot", "characterPhysics"}) do
		local item = operationalServices[key]
		local itemState = tostring(item.state or "Unknown")
		if itemState == "Unavailable" or itemState == "NotInstalled" then
			securityUnavailable += 1
		else
			securityObserved += 1
			table.insert(securityStates, itemState)
		end
	end
	local securityState = if securityObserved == 0 then "Unavailable"
		elseif table.find(securityStates, "Degraded") or table.find(securityStates, "Failed") then "Degraded"
		elseif table.find(securityStates, "Starting") then "Starting"
		elseif securityUnavailable > 0 then "Partial" else "Observed"
	operationalServices.securityHealth = {
		state = securityState,
		scope = "ServerLocal",
		observationalOnly = true,
		independentOfDiagnostics = true,
		observedComponents = securityObserved,
		unavailableComponents = securityUnavailable,
		totalComponents = securityObserved + securityUnavailable,
		components = {
			authorization = operationalServices.authorization.state,
			rateLimit = operationalServices.rateLimit.state,
			securityPolicy = operationalServices.securityPolicy.state,
			securityMonitor = operationalServices.securityMonitor.state,
			messageValidation = operationalServices.messageValidation.state,
			idempotency = operationalServices.idempotency.state,
			audit = operationalServices.audit.state,
			eventLog = operationalServices.eventLog.state,
			incidentResponse = operationalServices.incidentResponse.state,
			threatIntelligence = operationalServices.threatIntelligence.state,
			honeypot = operationalServices.honeypot.state,
			characterPhysics = operationalServices.characterPhysics.state,
		},
	}
	local observabilityKeys = {"diagnostics", "serviceRegistry", "serverHealth", "watchdog",
		"adaptiveLoad", "securityReplay", "threatIntelligence", "honeypot", "clientIntegrityTelemetry", "controller", "safeCall", "errorHistory"}
	local observabilityCounts = {Healthy = 0, Degraded = 0, Unavailable = 0, NotInstalled = 0, Starting = 0, Other = 0}
	local observabilityIssues = {}
	for _, key in ipairs(observabilityKeys) do
		local item = operationalServices[key]
		local itemState = tostring(item.state or "Unknown")
		if itemState == "Healthy" or itemState == "Ready" or itemState == "Observing" or itemState == "Available" then
			observabilityCounts.Healthy += 1
		elseif itemState == "Degraded" or itemState == "Failed" or itemState == "Stopped" then
			observabilityCounts.Degraded += 1
			table.insert(observabilityIssues, key .. ": " .. tostring(item.detail or itemState))
		elseif itemState == "NotInstalled" then
			observabilityCounts.NotInstalled += 1
		elseif itemState == "Unavailable" then
			observabilityCounts.Unavailable += 1
		elseif itemState == "Starting" then
			observabilityCounts.Starting += 1
		else
			observabilityCounts.Other += 1
		end
	end
	local observabilityState = if observabilityCounts.Degraded > 0 then "Degraded"
		elseif observabilityCounts.Starting > 0 then "Starting"
		elseif observabilityCounts.Healthy == 0 then "Unavailable"
		elseif observabilityCounts.Unavailable + observabilityCounts.NotInstalled > 0 then "Partial"
		else "Healthy"
	operationalServices.observabilityHealth = {
		state = observabilityState,
		scope = "ServerLocal",
		observationalOnly = true,
		components = observabilityCounts,
		componentCount = #observabilityKeys,
		issues = observabilityIssues,
	}

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
		operationalServices = operationalServices,
		clientTelemetry = {
			state = "ClientLocalOptIn",
			scope = "ClientLocalUntrusted",
			transmitted = false,
			deployment = "OptionalReplicatedStorageModuleAndLocalScript",
			bootstrapOptIn = true,
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
