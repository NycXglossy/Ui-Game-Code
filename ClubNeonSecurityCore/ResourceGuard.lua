--!strict
-- Per-server resource ceilings shared by private security modules.
-- This module is local-only: it creates no DataStore or MemoryStore records.
local Guard = {}
local active: {[string]: number} = {}
local acquired: {[string]: number} = {}
local rejected: {[string]: number} = {}
local DEFAULT_LIMITS = {
	MemoryStoreWrite = 2,
	MemoryStoreRead = 2,
	SecurityFlush = 1,
	IncidentWrite = 1,
}

function Guard.TryAcquire(name: string, requestedLimit: number?): (boolean, (() -> ())?)
	if type(name) ~= "string" or #name < 1 or #name > 40 then return false, nil end
	local limit = requestedLimit or DEFAULT_LIMITS[name] or 1
	if type(limit) ~= "number" or limit % 1 ~= 0 or limit < 1 or limit > 32 then return false, nil end
	local count = active[name] or 0
	if count >= limit then
		rejected[name] = (rejected[name] or 0) + 1
		return false, nil
	end
	active[name] = count + 1
	acquired[name] = (acquired[name] or 0) + 1
	local released = false
	return true, function()
		if released then return end
		released = true
		active[name] = math.max(0, (active[name] or 1) - 1)
	end
end

function Guard.GetStatus()
	local lanes = {}
	for name, limit in pairs(DEFAULT_LIMITS) do
		lanes[name] = {
			active = active[name] or 0,
			limit = limit,
			acquired = acquired[name] or 0,
			rejected = rejected[name] or 0,
		}
	end
	return {scope = "PerServerOnly", createsStorageRecords = false, lanes = lanes}
end

return Guard
