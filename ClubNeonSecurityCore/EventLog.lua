--!strict
-- Compatibility facade: operational events are stored by the unified security Audit service.
-- This module deliberately creates no MemoryStore map and owns no independent retention.
local Service = {}
Service.__index = Service

function Service.new(dependencies)
	assert(type(dependencies) == "table", "EventLog dependencies must be a table")
	assert(type(dependencies.isEnabled) == "function", "EventLog requires isEnabled")
	assert(type(dependencies.auditService) == "table"
		and type(dependencies.auditService.RecordEvent) == "function",
		"EventLog requires the unified Audit service")
	return setmetatable({
		d = dependencies,
		count = 0,
		lastError = nil,
	}, Service)
end

function Service:Record(kind, detail, severity)
	if not self.d.isEnabled() then return false end
	local ok, result = pcall(
		self.d.auditService.RecordEvent,
		self.d.auditService,
		kind,
		detail,
		severity
	)
	if not ok then
		self.lastError = string.sub(tostring(result), 1, 180)
		return false
	end
	if result == true then
		self.count += 1
		self.lastError = nil
		return true
	end
	return false
end

function Service:GetRecent(limit)
	if not self.d.isEnabled() then return false, {} end
	return self.d.auditService:GetRecent(limit)
end

function Service:GetStatus()
	local auditStatus = self.d.auditService:GetStatus()
	return {
		state = if self.d.isEnabled() then auditStatus.state else "Disabled",
		backend = "UnifiedSecurityAudit",
		independentMemoryStoreMap = false,
		writtenThroughFacade = self.count,
		retentionSeconds = auditStatus.ttlSeconds,
		lastError = self.lastError,
	}
end

function Service:Start()
	return true
end

function Service:Stop()
end

return Service
