--!strict
-- Local authorization adapter for ClubMusic global controls.
-- This service is intentionally independent of cross-server enablement and Studio isolation.
-- It always denies by default unless the controller supplies a trusted permission resolver.

local Service = {}
Service.__index = Service

local ALLOWED_PERMISSIONS = {
	GlobalDJ = true,
	GlobalModeration = true,
	GlobalAnnouncement = true,
	GlobalConfig = true,
	SecurityPolicy = true,
	IncidentResponse = true,
}

local function validActor(actorUserId: any): boolean
	return typeof(actorUserId) == "number"
		and actorUserId == actorUserId
		and actorUserId > 0
		and actorUserId < math.huge
		and actorUserId % 1 == 0
end

function Service.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table", "Authorization dependencies missing")
	assert(type(dependencies.resolvePermission) == "function", "Trusted permission resolver is required")

	return setmetatable({
		dependencies = dependencies,
		checks = 0,
		denied = 0,
		lastError = nil,
		started = false,
	}, Service)
end

function Service:Start(): boolean
	-- Do not require DataStore, MemoryStore, MessagingService, or global enablement.
	self.started = true
	return true
end

function Service:Check(actorUserId: any, permission: any): (boolean, string?)
	if not validActor(actorUserId) or typeof(permission) ~= "string"
		or not ALLOWED_PERMISSIONS[permission] then
		self.denied += 1
		return false, "Invalid actor or permission."
	end

	local resolver = self.dependencies.resolvePermission
	if type(resolver) ~= "function" then
		self.denied += 1
		self.lastError = "Trusted permission resolver is unavailable."
		return false, self.lastError
	end

	local ok, allowed = pcall(resolver, math.floor(actorUserId), permission)
	self.checks += 1
	if not ok then
		self.denied += 1
		self.lastError = string.sub(tostring(allowed), 1, 180)
		warn("[ClubMusic][Authorization] Trusted resolver failed; permission=" .. permission
			.. "; error=" .. self.lastError)
		return false, "Authorization resolver failed."
	end
	if allowed ~= true then
		self.denied += 1
		return false, "Permission denied."
	end

	self.lastError = nil
	return true
end

function Service:GetStatus(): {[string]: any}
	local available = false
	local availabilityError = nil
	if type(self.dependencies.isResolverAvailable) == "function" then
		local ok, result = pcall(self.dependencies.isResolverAvailable)
		available = ok and result == true
		if not ok then availabilityError = string.sub(tostring(result), 1, 180) end
	end

	return {
		state = if not self.started then "Stopped" elseif available then "Ready" else "ResolverUnavailable",
		started = self.started,
		resolverAvailable = available,
		checks = self.checks,
		denied = self.denied,
		lastError = self.lastError or availabilityError,
		default = "Deny",
	}
end

function Service:Stop()
	self.started = false
end

return Service
