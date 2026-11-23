--!strict
-- Small lifecycle owner for connections, threads, instances, and cleanup callbacks.
local Janitor = {}
Janitor.__index = Janitor

function Janitor.new()
	return setmetatable({items = {}, cleaned = false}, Janitor)
end

function Janitor:Add(resource: any, method: any?)
	if resource == nil then return resource end
	local cleanupMethod = method
	if cleanupMethod == nil then
		if typeof(resource) == "RBXScriptConnection" then cleanupMethod = "Disconnect"
		elseif typeof(resource) == "Instance" then cleanupMethod = "Destroy"
		elseif type(resource) == "thread" then cleanupMethod = "Cancel"
		elseif type(resource) == "function" then cleanupMethod = true end
	end
	if self.cleaned then
		self:_cleanupOne(resource, cleanupMethod)
	else
		table.insert(self.items, {resource = resource, method = cleanupMethod})
	end
	return resource
end

function Janitor:_cleanupOne(resource: any, method: any)
	local ok, err = pcall(function()
		if method == true then
			resource()
		elseif method == "Cancel" then
			if coroutine.status(resource) ~= "dead" then task.cancel(resource) end
		elseif type(method) == "string" then
			local callback = resource[method]
			if type(callback) == "function" then callback(resource) end
		elseif type(method) == "function" then
			method(resource)
		end
	end)
	if not ok then warn("[SecurityJanitor] Cleanup failed: " .. tostring(err)) end
end

function Janitor:Remove(resource: any, shouldCleanup: boolean?)
	for index = #self.items, 1, -1 do
		local item = self.items[index]
		if item.resource == resource then
			table.remove(self.items, index)
			if shouldCleanup == true then self:_cleanupOne(item.resource, item.method) end
			return true
		end
	end
	return false
end

function Janitor:Cleanup()
	if self.cleaned then return end
	self.cleaned = true
	for index = #self.items, 1, -1 do
		local item = self.items[index]
		self:_cleanupOne(item.resource, item.method)
		self.items[index] = nil
	end
end

return Janitor
