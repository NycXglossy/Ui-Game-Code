--!strict
-- Centralized, server-local movement authorization ledger.
-- No DataStore or MemoryStore usage. The Kohl's adapter exposes the legacy
-- TikiTideMovementAuthority BindableFunction and delegates to this module.

local Players = game:GetService("Players")
local MovementAuthority = {}

local CAPACITY = 256
local AUTHORIZED_PROPERTIES: {[string]: boolean} = {
	WorldGravity = true, StarterWalkSpeed = true, WalkSpeed = true, JumpPower = true,
	JumpImpulse = true, PersonalGravity = true, BodyScale = true, Flight = true, Frozen = true,
	JumpHeight = true, Anchored = true, Teleport = true, Fling = true,
}
type Entry = {
	actor: number,
	target: number,
	property: string,
	value: any,
	origin: string,
	expiresAt: number,
}
local entries: {[string]: Entry} = {}
local started = false

local function finiteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function keyFor(targetUserId: number, property: string): string
	return tostring(targetUserId) .. ":" .. property
end

local function prune(now: number): number
	local count = 0
	for key, entry in pairs(entries) do
		if entry.expiresAt <= now then
			entries[key] = nil
		else
			count += 1
		end
	end
	return count
end

function MovementAuthority.Start()
	if started then return true end
	started = true
	Players.PlayerRemoving:Connect(function(player)
		for key, entry in pairs(entries) do
			if entry.actor == player.UserId or entry.target == player.UserId then
				entries[key] = nil
			end
		end
	end)
	return true
end

function MovementAuthority.Register(actorId: any, targetId: any, property: any, value: any, origin: any, ttl: any)
	if not finiteNumber(actorId) or actorId < 1 or actorId % 1 ~= 0
		or not finiteNumber(targetId) or targetId < 0 or targetId % 1 ~= 0
		or typeof(property) ~= "string" or not AUTHORIZED_PROPERTIES[property]
		or (typeof(value) ~= "boolean" and value ~= "DEFAULT" and not finiteNumber(value))
		or typeof(origin) ~= "string" or #origin < 1 or #origin > 32 then
		return false, "Invalid movement authorization record."
	end
	local actorPlayer = Players:GetPlayerByUserId(math.floor(actorId))
	if not actorPlayer or actorPlayer.Parent ~= Players then
		return false, "Movement authority actor is not active."
	end
	if targetId > 0 then
		local targetPlayer = Players:GetPlayerByUserId(math.floor(targetId))
		if not targetPlayer or targetPlayer.Parent ~= Players then
			return false, "Movement authority target is not active."
		end
	end

	local lifetime = if finiteNumber(ttl) then math.clamp(ttl, 5, 600) else 120
	local now = os.clock()
	local count = prune(now)
	if count >= CAPACITY then
		local oldestKey, oldestExpiry = nil, math.huge
		for key, entry in pairs(entries) do
			if entry.expiresAt < oldestExpiry then
				oldestKey, oldestExpiry = key, entry.expiresAt
			end
		end
		if oldestKey then
			entries[oldestKey] = nil
		else
			return false, "Movement authorization ledger is full."
		end
	end

	entries[keyFor(math.floor(targetId), property)] = {
		actor = math.floor(actorId),
		target = math.floor(targetId),
		property = property,
		value = value,
		origin = origin,
		expiresAt = now + lifetime,
	}
	return true
end

function MovementAuthority.Check(targetId: any, property: any, value: any): (boolean, string?)
	if not finiteNumber(targetId) or targetId < 0 or targetId % 1 ~= 0
		or typeof(property) ~= "string" or not AUTHORIZED_PROPERTIES[property] then
		return false
	end
	local key = keyFor(math.floor(targetId), property)
	local entry = entries[key]
	if not entry then return false end
	if entry.expiresAt <= os.clock() then
		entries[key] = nil
		return false
	end
	-- Player-scoped grants are invalid as soon as the target leaves, even if
	-- PlayerRemoving cleanup has not run yet. WorldGravity uses target ID 0.
	if targetId > 0 then
		local targetPlayer = Players:GetPlayerByUserId(math.floor(targetId))
		if not targetPlayer or targetPlayer.Parent ~= Players then
			entries[key] = nil
			return false
		end
	end
	-- "ANY" is intentionally restricted to the Fling marker used by
	-- CharacterPhysicsGuard. It must never act as a wildcard for other properties.
	if value == "ANY" then
		if property ~= "Fling" then return false end
		return true, entry.origin
	end
	if typeof(value) == "number" and typeof(entry.value) == "number" then
		return math.abs(value - entry.value) <= 0.05, entry.origin
	end
	return entry.value == "DEFAULT" or value == entry.value, entry.origin
end

function MovementAuthority.Status()
	return {
		tracked = prune(os.clock()),
		capacity = CAPACITY,
		scope = "PerServerOnly",
		createsStorageRecords = false,
	}
end

-- Stable BindableFunction contract:
--   Invoke("Register", actorId, targetId, property, value, origin, ttl)
--   Invoke("Check", targetId, property, value)
--   Invoke("Status")
-- The previous dispatcher treated Check's targetId as actorId, shifting every
-- remaining argument. CharacterPhysicsGuard therefore never reached Check's
-- intended target/property/value tuple. Keep Check's three-argument public
-- shape while retaining the seven-slot Register shape.
function MovementAuthority.Invoke(operation: any, first: any, second: any, third: any, fourth: any, fifth: any, sixth: any)
	if operation == "Register" then
		return MovementAuthority.Register(first, second, third, fourth, fifth, sixth)
	elseif operation == "Check" then
		return MovementAuthority.Check(first, second, third)
	elseif operation == "Status" then
		return MovementAuthority.Status()
	end
	return false, "Unknown movement authority operation."
end

MovementAuthority.Start()
return MovementAuthority
