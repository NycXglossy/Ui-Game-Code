--!strict
-- Disabled optional server discovery registry.
-- Minimal-storage mode deliberately writes no per-server records to MemoryStore.
local Service = {}
Service.__index = Service

function Service.new(dependencies)
	assert(type(dependencies) == "table" and type(dependencies.isEnabled) == "function",
		"Registry dependencies missing")
	return setmetatable({
		dependencies = dependencies,
		running = false,
		state = "Disabled",
		lastHeartbeat = 0,
		lastError = "Server discovery is disabled to keep MemoryStore usage minimal.",
		capacityLimited = true,
	}, Service)
end

function Service:Heartbeat()
	self.state = "Disabled"
	return false
end

function Service:GetServers(_limit)
	return false, {}, "Server discovery is disabled in minimal MemoryStore mode."
end

function Service:GetStatus()
	return {
		state = "Disabled",
		lastHeartbeat = 0,
		lastError = self.lastError,
		capacityLimited = true,
		ttlSeconds = 0,
	}
end

function Service:Start()
	self.running = false
	self.state = "Disabled"
	return true
end

function Service:Stop()
	self.running = false
end

return Service
