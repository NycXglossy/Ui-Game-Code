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
		denials = {},
		deniedActions = 0,
	}, Service)
end

function Service:Start(): boolean
	-- Do not require DataStore, MemoryStore, MessagingService, or global enablement.
	self.started = true
	return true
end

function Service:_recordDenied(actorUserId: any, permission: string)
	if not validActor(actorUserId) then return end
	local now=os.clock()
	local key=tostring(math.floor(actorUserId))..":"..permission
	local entry=self.denials[key]
	if not entry then
		local count=0
		local oldestKey,oldestAt=nil,math.huge
		for existingKey,value in pairs(self.denials) do
			count+=1
			if value.updated<oldestAt then oldestAt=value.updated; oldestKey=existingKey end
		end
		if count>=256 and oldestKey then self.denials[oldestKey]=nil end
		entry={count=0,windowStart=now,updated=now,reportedAt=0}
		self.denials[key]=entry
	end
	if now-entry.windowStart>60 then entry.count=0; entry.windowStart=now end
	entry.count+=1
	entry.updated=now
	self.deniedActions+=1
	if entry.count>=3 and now-entry.reportedAt>=60 then
		entry.reportedAt=now
		if type(self.dependencies.onDenied)=="function" then
			pcall(self.dependencies.onDenied,math.floor(actorUserId),permission,entry.count)
		end
	end
end

function Service:Check(actorUserId: any, permission: any): (boolean, string?)
	if not validActor(actorUserId) or typeof(permission) ~= "string"
		or not ALLOWED_PERMISSIONS[permission] then
		self.denied += 1
		if typeof(permission)=="string" and ALLOWED_PERMISSIONS[permission] then self:_recordDenied(actorUserId,permission) end
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
		self:_recordDenied(actorUserId,permission)
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
		deniedActions = self.deniedActions,
		trackedDenialKeys = (function() local n=0; for _ in pairs(self.denials) do n+=1 end; return n end)(),
		maxTrackedDenialKeys = 256,
		lastError = self.lastError or availabilityError,
		default = "Deny",
	}
end

function Service:Stop()
	self.started = false
end

return Service
