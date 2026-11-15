--!strict
-- Lightweight, server-local diagnostics. No MemoryStore/DataStore writes and no control actions.
local Service = {}
Service.__index = Service

local function clone(value)
	return if typeof(value) == "table" then table.clone(value) else value
end

function Service.new(dependencies)
	assert(type(dependencies) == "table" and type(dependencies.isEnabled) == "function", "Diagnostics dependencies missing")
	return setmetatable({
		d = dependencies,
		running = false,
		status = {
			state = "Starting",
			detail = "Waiting for the first lightweight diagnostics pass.",
			localState = "Starting",
			localDetail = "Initial check pending.",
			serviceState = "Starting",
			recoveryState = "Starting",
			recoveryDetail = "Recovery status is not available yet.",
			syncState = "Starting",
			syncDetail = "Synchronization status is not available yet.",
			updatedAt = os.time(),
		},
		metrics = {},
		lastSignature = "",
	}, Service)
end

function Service:Record(name, value, latencySeconds)
	if type(name) ~= "string" or #name == 0 or #name > 48 then return false end
	local amount = if type(value) == "number" and value == value and value >= 0 and value < math.huge then value else 1
	local item = self.metrics[name] or {count = 0, latencyCount = 0, latencyTotal = 0, latencyMax = 0}
	item.count = math.min(1000000000, item.count + amount)
	if type(latencySeconds) == "number" and latencySeconds == latencySeconds and latencySeconds >= 0 and latencySeconds <= 120 then
		item.latencyCount += 1
		item.latencyTotal += latencySeconds
		item.latencyMax = math.max(item.latencyMax, latencySeconds)
	end
	self.metrics[name] = item
	return true
end

function Service:Check()
	local enabledOk, enabled = pcall(self.d.isEnabled)
	if not enabledOk or enabled ~= true then
		self.status = {
			state = "Disabled", detail = "Global service is disabled in this server.",
			localState = "Disabled", localDetail = "Global service is disabled.",
			serviceState = "Disabled", recoveryState = "Disabled", recoveryDetail = "Not running.",
			syncState = "Disabled", syncDetail = "Cross-server service is disabled.",
			updatedAt = os.time(),
		}
		return true
	end

	local checks = {}
	local apiFolder = self.d.apiFolder
	checks.Api = apiFolder ~= nil and apiFolder.Parent == game:GetService("ServerStorage")
	local queueModule = self.d.queueModule
	checks.QueueModule = queueModule ~= nil and queueModule:IsA("ModuleScript") and queueModule.Parent ~= nil

	local recovery
	if type(self.d.getRecoveryStatus) == "function" then
		local ok, result = pcall(self.d.getRecoveryStatus)
		if ok and typeof(result) == "table" then recovery = result end
	end
	local sync
	if type(self.d.getSyncStatus) == "function" then
		local ok, result = pcall(self.d.getSyncStatus)
		if ok and typeof(result) == "table" then sync = result end
	end

	local issues = {}
	for name, ok in pairs(checks) do
		if ok ~= true then table.insert(issues, name .. " dependency is unavailable.") end
	end
	local pending = {}
	local recoveryState = if recovery then tostring(recovery.state or "Unavailable") else "Unavailable"
	local recoveryDetail = if recovery then tostring(recovery.detail or recoveryState) else "Recovery status is unavailable."
	if recoveryState == "Starting" or recoveryState == "Unavailable" then
		table.insert(pending, recoveryDetail)
	elseif recoveryState ~= "Healthy" and recoveryState ~= "Disabled" then
		table.insert(issues, "Recovery: " .. recoveryDetail)
	end

	local syncState = if sync then tostring(sync.state or "Unavailable") else "Unavailable"
	local syncDetail = if sync then tostring(sync.detail or syncState) else "Synchronization status is unavailable."
	if syncState == "Starting" or syncState == "Unverified" or syncState == "Unavailable" then
		table.insert(pending, syncDetail)
	elseif syncState ~= "Healthy" and syncState ~= "Disabled" then
		table.insert(issues, "Synchronization: " .. syncDetail)
	end

	local state = if #issues > 0 then "Degraded" elseif #pending > 0 then "Starting" else "Healthy"
	local detail = if #issues > 0 then table.concat(issues, "; ")
		elseif #pending > 0 then table.concat(pending, "; ")
		else "Core service dependencies and current synchronization status are healthy."
	local localState = if checks.Api and checks.QueueModule then "Healthy" else "Degraded"
	local localDetail = if localState == "Healthy" then "Local service dependencies are available."
		else "One or more local service dependencies are unavailable."

	self.status = {
		state = state,
		detail = detail,
		localState = localState,
		localDetail = localDetail,
		serviceState = if enabled then "Enabled" else "Disabled",
		recoveryState = recoveryState,
		recoveryDetail = recoveryDetail,
		syncState = syncState,
		syncDetail = syncDetail,
		syncStatus = sync,
		checks = checks,
		updatedAt = os.time(),
	}
	local signature = state .. "|" .. detail
	if signature ~= self.lastSignature then
		self.lastSignature = signature
		if state == "Degraded" then warn("[ClubMusic Diagnostics] " .. detail) end
	end
	return state ~= "Degraded"
end

function Service:GetStatus()
	local result = table.clone(self.status)
	if typeof(self.status.syncStatus) == "table" then result.syncStatus = table.clone(self.status.syncStatus) end
	if typeof(self.status.checks) == "table" then result.checks = table.clone(self.status.checks) end
	return result
end

function Service:GetMetrics()
	local counters = {}
	for name, values in pairs(self.metrics) do counters[name] = table.clone(values) end
	return {state = "Healthy", scope = "ServerLocal", counters = counters, updatedAt = os.time()}
end

function Service:GetSnapshot()
	local recovery = nil
	if type(self.d.getRecoveryStatus) == "function" then
		local ok, result = pcall(self.d.getRecoveryStatus)
		if ok and typeof(result) == "table" then recovery = result end
	end
	local errors, errorsAvailable = {}, false
	if type(self.d.getRecentErrors) == "function" then
		local ok, result = pcall(self.d.getRecentErrors)
		if ok and typeof(result) == "table" then
			errorsAvailable = true
			for index = math.max(1, #result - 19), #result do
				if typeof(result[index]) == "table" then table.insert(errors, table.clone(result[index])) end
			end
		end
	end
	return {
		generatedAt = os.time(),
		serviceEnabled = self.d.isEnabled(),
		healthAvailable = true,
		health = self:GetStatus(),
		recoveryAvailable = recovery ~= nil,
		recovery = recovery,
		syncStatus = if type(self.d.getSyncStatus) == "function" then self.d.getSyncStatus() else nil,
		errorHistoryAvailable = errorsAvailable,
		recentErrors = errors,
		operationalServices = {
			memoryStore = if type(self.d.getMemoryStoreStatus) == "function" then self.d.getMemoryStoreStatus() else nil,
			diagnostics = self:GetStatus(),
			securityMonitor = if type(self.d.getSecurityMonitorStatus) == "function" then self.d.getSecurityMonitorStatus() else nil,
			messageValidation = if type(self.d.getMessageValidationStatus) == "function" then self.d.getMessageValidationStatus() else nil,
			idempotency = if type(self.d.getIdempotencyStatus) == "function" then self.d.getIdempotencyStatus() else nil,
		},
	}
end

function Service:Start()
	if self.running then return false end
	self.running = true
	task.spawn(function()
		while self.running do
			local ok, err = pcall(self.Check, self)
			if not ok then warn("[ClubMusic Diagnostics] Check failed: " .. tostring(err)) end
			task.wait(60)
		end
	end)
	return true
end

function Service:Stop()
	self.running = false
end

return Service
