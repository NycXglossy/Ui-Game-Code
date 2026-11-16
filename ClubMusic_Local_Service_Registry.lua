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

function Registry:Remove(name: any): boolean
	if not validName(name) or self.services[name] == nil then return false end
	self.services[name] = nil
	self.registered = math.max(0, self.registered - 1)
	self.updatedAt = os.time()
	return true
end

function Registry:Get(name: any): any
	if not validName(name) then return nil end
	local entry = self.services[name]
	return if entry then table.clone(entry) else nil
end

function Registry:GetStatus(): {[string]: any}
	local services = {}
	local counts = {Healthy = 0, Degraded = 0, Unavailable = 0, Starting = 0, Disabled = 0}
	local requiredIssues = {}
	for name, entry in pairs(self.services) do
		local copy = table.clone(entry)
		if typeof(entry.metadata) == "table" then copy.metadata = table.clone(entry.metadata) end
		services[name] = copy
		counts[entry.state] = (counts[entry.state] or 0) + 1
		if entry.required and entry.state ~= "Healthy" and entry.state ~= "Disabled" then
			table.insert(requiredIssues, name .. ": " .. cleanText(entry.detail, 120))
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
