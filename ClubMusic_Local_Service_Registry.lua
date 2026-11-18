--!strict
-- Server-local registry for operational service visibility.
-- This module is observational only: it does not start, stop, repair, or authorize services.
-- No DataStore, MemoryStore, MessagingService, or client-facing APIs are used.

local Registry = {}
Registry.__index = Registry

local MAX_SERVICES = 64
local VALID_STATES = {
	Starting = true,
	Healthy = true,
	Degraded = true,
	Unavailable = true,
	NotInstalled = true,
	Disabled = true,
}

local function cleanText(value: any, maxLength: number): string
	local ok, result = pcall(tostring, value)
	if not ok then return "unavailable" end
	result = string.gsub(result, "[%c]", " ")
	return string.sub(result, 1, maxLength)
end

local function validName(name: any): boolean
	return typeof(name) == "string" and #name > 0 and #name <= 48
		and string.match(name, "^[%w_%-%.]+$") ~= nil
end

function Registry.new()
	return setmetatable({
		services = {},
		registered = 0,
		updatedAt = os.time(),
	}, Registry)
end

function Registry:Register(name: any, instance: any, requiredMethods: any, required: any?): boolean
	if not validName(name) then return false end
	local current = self.services[name]
	if not current and self.registered >= MAX_SERVICES then return false end

	local missing = {}
	local validInstance = typeof(instance) == "table"
	if validInstance and typeof(requiredMethods) == "table" then
		for _, methodName in ipairs(requiredMethods) do
			if typeof(methodName) ~= "string" or type(instance[methodName]) ~= "function" then
				table.insert(missing, cleanText(methodName, 48))
			end
		end
	end
	local state = if not validInstance or #missing > 0 then "Unavailable" else "Healthy"
	self.services[name] = {
		name = name,
		state = state,
		detail = if #missing > 0 then "Missing interface: " .. table.concat(missing, ", ")
			elseif not validInstance then "Service instance is unavailable."
			else "Service interface is registered.",
		required = required == true,
		registeredAt = if current then current.registeredAt else os.time(),
		updatedAt = os.time(),
		methodCount = if typeof(requiredMethods) == "table" then #requiredMethods else 0,
	}
	if not current then self.registered += 1 end
	self.updatedAt = os.time()
	return state == "Healthy"
end

function Registry:SetStatus(name: any, state: any, detail: any, metadata: any?): boolean
	if not validName(name) or not VALID_STATES[state] then return false end
	local current = self.services[name]
	if not current and self.registered >= MAX_SERVICES then return false end
	local entry = current or {
		name = name,
		required = false,
		registeredAt = os.time(),
	}
	entry.state = state
	entry.detail = cleanText(detail or state, 180)
	entry.updatedAt = os.time()
	if typeof(metadata) == "table" then
		entry.metadata = {}
		for key, value in pairs(metadata) do
			if typeof(key) == "string" and #key <= 32
				and (typeof(value) == "string" or typeof(value) == "number" or typeof(value) == "boolean") then
				entry.metadata[key] = if typeof(value) == "string" then cleanText(value, 80) else value
			end
		end
	end
	self.services[name] = entry
	if not current then self.registered += 1 end
	self.updatedAt = os.time()
	return true
end

function Registry:RegisterDependency(name: any, instance: any, expectedClass: any, expectedParent: any, required: any?): boolean
	if not validName(name) or typeof(instance) ~= "Instance"
		or typeof(expectedClass) ~= "string" or #expectedClass == 0 or #expectedClass > 48
		or (expectedParent ~= nil and typeof(expectedParent) ~= "Instance") then return false end
	local current = self.services[name]
	if not current and self.registered >= MAX_SERVICES then return false end
	local classOk, actualClass = pcall(function() return instance.ClassName end)
	local parentOk, actualParent = pcall(function() return instance.Parent end)
	local valid = classOk and parentOk and actualClass == expectedClass and actualParent ~= nil
		and (expectedParent == nil or actualParent == expectedParent)
	self.services[name] = {
		name = name,
		state = if valid then "Healthy" else "Unavailable",
		detail = if valid then "Dependency class and hierarchy are valid."
			else "Dependency is missing, reparented, or has an unexpected class.",
		required = required == true,
		dependency = true,
		instance = instance,
		expectedClass = expectedClass,
		expectedParent = expectedParent,
		registeredAt = if current then current.registeredAt else os.time(),
		updatedAt = os.time(),
	}
	if not current then self.registered += 1 end
	self.updatedAt = os.time()
	return valid
end

function Registry:Remove(name: any): boolean
	if not validName(name) or self.services[name] == nil then return false end
	self.services[name] = nil
	self.registered = math.max(0, self.registered - 1)
	self.updatedAt = os.time()
	return true
end

local function copyEntry(entry: any): any
	local copy = table.clone(entry)
	if entry.dependency == true then
		local ok, className, parent = pcall(function()
			return entry.instance.ClassName, entry.instance.Parent
		end)
		if not ok or parent == nil or className ~= entry.expectedClass
			or (entry.expectedParent ~= nil and parent ~= entry.expectedParent) then
			copy.state = "Unavailable"
			copy.detail = "Dependency is missing, reparented, or has an unexpected class."
		else
			copy.state = "Healthy"
			copy.detail = "Dependency class and hierarchy are valid."
		end
		copy.instance = nil
		copy.expectedParent = nil
	end
	if typeof(copy.metadata) == "table" then copy.metadata = table.clone(copy.metadata) end
	return copy
end

function Registry:Get(name: any): any
	if not validName(name) then return nil end
	local entry = self.services[name]
	return if entry then copyEntry(entry) else nil
end

function Registry:GetStatus(): {[string]: any}
	local services = {}
	local counts = {Healthy = 0, Degraded = 0, Unavailable = 0, NotInstalled = 0, Starting = 0, Disabled = 0}
	local requiredIssues = {}
	local dependencyCount = 0
	for name, entry in pairs(self.services) do
		local copy = copyEntry(entry)
		services[name] = copy
		counts[copy.state] = (counts[copy.state] or 0) + 1
		if entry.dependency == true then dependencyCount += 1 end
		if entry.required and copy.state ~= "Healthy" and copy.state ~= "Disabled" then
			table.insert(requiredIssues, name .. ": " .. cleanText(copy.detail, 120))
		end
	end
	table.sort(requiredIssues)
	local state = if #requiredIssues > 0 then "Degraded" else "Healthy"
	return {
		state = state,
		scope = "ServerLocal",
		observationalOnly = true,
		serviceCount = self.registered,
		counts = counts,
		issues = requiredIssues,
		services = services,
		updatedAt = self.updatedAt,
	}
end

return Registry
