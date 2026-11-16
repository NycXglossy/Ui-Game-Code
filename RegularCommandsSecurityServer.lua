--!strict
-- Server-only Kohl's Admin integration for Tiki Tide SecurityCore.
-- Install as ServerScriptService > Kohl's Admin > Addons > RegularCommandsSecurityServer.
-- Does not modify Kohl's Admin core or the existing ClubMusic add-on.
--
-- This adapter uses the installed Kohl's Process.addCommandFilter enforcement point.
-- It authorizes before command-request splitting, then wraps only the matched server
-- handler so movement authority is recorded only after the original handler returns.

return function(_K: any)
	if _K.IsServer ~= true then return end
	if not (_K.Process and type(_K.Process.addCommandFilter) == "function") then
		warn("[Tiki Tide Security][Kohl's] Process.addCommandFilter is unavailable; regular command security was not installed.")
		return
	end

	local Players = game:GetService("Players")
	local ServerStorage = game:GetService("ServerStorage")
	local AUTHORIZER_NAME = "ClubMusicAuthorizationResolver"
	local AUTHORITY_NAME = "TikiTideMovementAuthority"

	local POLICY: {[string]: {permission: string, property: string, valueArg: number?, targetArg: number?, global: boolean?}} = {
		gravity = {permission = "GlobalConfig", property = "WorldGravity", valueArg = 1, global = true},
		starterspeed = {permission = "GlobalConfig", property = "StarterWalkSpeed", valueArg = 1, global = true},
		speed = {permission = "GlobalModeration", property = "WalkSpeed", valueArg = 2, targetArg = 1},
		jumppower = {permission = "GlobalModeration", property = "JumpPower", valueArg = 2, targetArg = 1},
		jump = {permission = "GlobalModeration", property = "JumpImpulse", targetArg = 1},
		setgravity = {permission = "GlobalModeration", property = "PersonalGravity", valueArg = 2, targetArg = 1},
		size = {permission = "GlobalModeration", property = "BodyScale", valueArg = 2, targetArg = 1},
		fly = {permission = "GlobalModeration", property = "Flight", valueArg = 0, targetArg = 1},
		unfly = {permission = "GlobalModeration", property = "Flight", valueArg = 0, targetArg = 1},
		freeze = {permission = "GlobalModeration", property = "Frozen", valueArg = 0, targetArg = 1},
		thaw = {permission = "GlobalModeration", property = "Frozen", valueArg = 0, targetArg = 1},
	}

	local VALUE_LIMITS: {[string]: {min: number, max: number}} = {
		WorldGravity = {min = 0, max = 500},
		StarterWalkSpeed = {min = 0, max = 100},
		WalkSpeed = {min = 0, max = 100},
		JumpPower = {min = 0, max = 250},
		PersonalGravity = {min = 0, max = 5},
		BodyScale = {min = 0.1, max = 10},
	}

	local function finiteNumber(value: any): boolean
		return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
	end

	local function actorUserId(command: any): number?
		local player = command.fromPlayer
		if typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players then
			return player.UserId
		end
		return nil
	end

	-- Prime trusted permission snapshots outside the synchronous command filter.
	-- Process.addCommandFilter must not yield; expired/missing snapshots deny.
	local permissionCache: {[number]: {GlobalModeration: boolean, GlobalConfig: boolean, expiresAt: number}} = {}
	local function refreshAuthorization(player: Player)
		task.spawn(function()
			local resolver = ServerStorage:FindFirstChild(AUTHORIZER_NAME)
			if not resolver or not resolver:IsA("BindableFunction") or resolver.Parent ~= ServerStorage then
				permissionCache[player.UserId] = nil
				return
			end
			local moderationOk, moderation = pcall(function() return resolver:Invoke(player.UserId, "GlobalModeration") end)
			local configOk, config = pcall(function() return resolver:Invoke(player.UserId, "GlobalConfig") end)
			if player.Parent ~= Players then return end
			permissionCache[player.UserId] = {
				GlobalModeration = moderationOk and moderation == true,
				GlobalConfig = configOk and config == true,
				expiresAt = os.clock() + 15,
			}
		end)
	end
	local function authorize(userId: number, permission: string): boolean
		local cached = permissionCache[userId]
		return cached ~= nil and cached.expiresAt > os.clock() and cached[permission] == true
	end
	Players.PlayerAdded:Connect(refreshAuthorization)
	for _, player in ipairs(Players:GetPlayers()) do refreshAuthorization(player) end
	task.spawn(function()
		while true do
			task.wait(10)
			for _, player in ipairs(Players:GetPlayers()) do refreshAuthorization(player) end
		end
	end)

	-- Local per-server token bucket. It deliberately creates no MemoryStore entries.
	local buckets: {[number]: {tokens: number, updatedAt: number}} = {}
	local function consumeBudget(userId: number): boolean
		local now = os.clock()
		local entry = buckets[userId]
		if not entry then
			entry = {tokens = 5, updatedAt = now}
			buckets[userId] = entry
		end
		entry.tokens = math.min(5, entry.tokens + math.max(0, now - entry.updatedAt) / 2)
		entry.updatedAt = now
		if entry.tokens < 1 then return false end
		entry.tokens -= 1
		return true
	end

	Players.PlayerRemoving:Connect(function(player)
		buckets[player.UserId] = nil
		permissionCache[player.UserId] = nil
	end)

	-- Server-only, bounded, in-memory movement authorization ledger. Other server
	-- systems can use the BindableFunction to register their own approved changes.
	local authorityEntries: {[string]: {actor: number, target: number, property: string, value: any, origin: string, expiresAt: number}} = {}
	local AUTHORIZED_PROPERTIES = {
		WorldGravity = true, StarterWalkSpeed = true, WalkSpeed = true, JumpPower = true,
		JumpImpulse = true, PersonalGravity = true, BodyScale = true, Flight = true, Frozen = true,
		JumpHeight = true, Anchored = true,
	}
	local function authorityKey(targetUserId: number, property: string): string
		return tostring(targetUserId) .. ":" .. property
	end
	local authority = ServerStorage:FindFirstChild(AUTHORITY_NAME)
	if authority and not authority:IsA("BindableFunction") then
		warn("[Tiki Tide Security][Kohl's] TikiTideMovementAuthority exists with the wrong class; movement ledger unavailable.")
		authority = nil
	end
	if not authority then
		authority = Instance.new("BindableFunction")
		authority.Name = AUTHORITY_NAME
		authority.Parent = ServerStorage
	end
	(authority :: BindableFunction).OnInvoke = function(operation: any, actorId: any, targetId: any, property: any, value: any, origin: any, ttl: any)
		if operation == "Register" then
			if not finiteNumber(actorId) or actorId < 1 or actorId % 1 ~= 0
				or not finiteNumber(targetId) or targetId < 0 or targetId % 1 ~= 0
				or typeof(property) ~= "string" or not AUTHORIZED_PROPERTIES[property]
				or (typeof(value) ~= "boolean" and value ~= "DEFAULT" and not finiteNumber(value))
				or typeof(origin) ~= "string" or #origin < 1 or #origin > 32 then
				return false, "Invalid movement authorization record."
			end
			local lifetime = if finiteNumber(ttl) then math.clamp(ttl, 5, 600) else 120
			local now = os.clock()
			local count = 0
			local oldestKey, oldestExpiry = nil, math.huge
			for key, entry in pairs(authorityEntries) do
				if entry.expiresAt <= now then
					authorityEntries[key] = nil
				else
					count += 1
					if entry.expiresAt < oldestExpiry then oldestKey, oldestExpiry = key, entry.expiresAt end
				end
			end
			if count >= 256 then
				if oldestKey then authorityEntries[oldestKey] = nil else return false, "Movement authorization ledger is full." end
			end
			authorityEntries[authorityKey(math.floor(targetId), property)] = {
				actor = math.floor(actorId), target = math.floor(targetId), property = property,
				value = value, origin = origin, expiresAt = now + lifetime,
			}
			return true
		elseif operation == "Check" then
			if not finiteNumber(targetId) or targetId < 0 or targetId % 1 ~= 0
				or typeof(property) ~= "string" or not AUTHORIZED_PROPERTIES[property] then
				return false
			end
			local key = authorityKey(math.floor(targetId), property)
			local entry = authorityEntries[key]
			if not entry then return false end
			if entry.expiresAt <= os.clock() then authorityEntries[key] = nil; return false end
			if typeof(value) == "number" and typeof(entry.value) == "number" then
				return math.abs(value - entry.value) <= 0.05, entry.origin
			end
			return entry.value == "DEFAULT" or value == entry.value, entry.origin
		elseif operation == "Status" then
			local count = 0
			for key, entry in pairs(authorityEntries) do
				if entry.expiresAt <= os.clock() then authorityEntries[key] = nil else count += 1 end
			end
			return {tracked = count, capacity = 256, scope = "PerServerOnly", createsStorageRecords = false}
		end
		return false, "Unknown movement authority operation."
	end

	local function logAction(command: any, policy: any, targets: {Player}, value: any)
		if type(_K.log) ~= "function" then return end
		local id = actorUserId(command)
		local targetCount = #targets
		local valueText = if value == nil then "default" elseif typeof(value) == "boolean" then tostring(value) else tostring(value)
		local message = string.format(
			"Security-authorized Kohl's command: command=%s property=%s targets=%d value=%s",
			tostring(command.definition.name), policy.property, targetCount, string.sub(valueText, 1, 24)
		)
		local ok, err = pcall(_K.log, message, "COMMAND", id)
		if not ok then warn("[Tiki Tide Security][Kohl's] Audit log failed: " .. tostring(err)) end
	end

	local wrappedDefinitions = setmetatable({}, {__mode = "k"})
	local function wrapHandler(command: any, policy: any)
		local definition = command.definition
		if wrappedDefinitions[definition] then return end
		local original = definition.run
		if type(original) ~= "function" then return end
		wrappedDefinitions[definition] = true
		definition.run = function(context: any, ...)
			local args = table.pack(...)
			local result = table.pack(original(context, table.unpack(args, 1, args.n)))
			local targets: {Player} = {}
			local targetArg = policy.targetArg
			if targetArg then
				local rawTargets = args[targetArg]
				if typeof(rawTargets) == "Instance" and rawTargets:IsA("Player") then
					table.insert(targets, rawTargets)
				elseif typeof(rawTargets) == "table" then
					for _, target in ipairs(rawTargets) do
						if typeof(target) == "Instance" and target:IsA("Player") then table.insert(targets, target) end
					end
				end
			end
			local value = if policy.valueArg == 0 then false elseif policy.valueArg then args[policy.valueArg] else true
			if value == nil then value = "DEFAULT" end
			if command.alias == "unfly" or command.alias == "thaw" then value = false
			elseif command.alias == "fly" or command.alias == "freeze" then value = true end
			local actorId = actorUserId(context)
			if actorId then
				if policy.global then
					local globalValue = value
					if globalValue == nil and policy.property == "WorldGravity" and context.env then globalValue = context.env.gravity end
					local registerOk = (authority :: BindableFunction):Invoke("Register", actorId, 0, policy.property, globalValue, "KohlsAdmin", 120)
					if registerOk ~= true then warn("[Tiki Tide Security][Kohl's] Could not register global movement authority.") end
				else
					for _, target in ipairs(targets) do
						local targetValue = value
						if policy.property == "JumpImpulse" then targetValue = true end
						local registerOk = (authority :: BindableFunction):Invoke("Register", actorId, target.UserId, policy.property, targetValue, "KohlsAdmin", 120)
						if registerOk ~= true then warn("[Tiki Tide Security][Kohl's] Could not register target movement authority.") end
					end
				end
				logAction(context, policy, targets, value)
			end
			return table.unpack(result, 1, result.n)
		end
	end

	local function getNumericArgument(command: any, index: number?): any
		if not index then return nil end
		local prepared = command.preparedArgs
		return typeof(prepared) == "table" and prepared[index] or nil
	end

	local filter = function(command: any): (boolean, string?)
		if typeof(command) ~= "table" or typeof(command.definition) ~= "table" then return true end
		local commandName = string.lower(tostring(command.definition.name or ""))
		local policy = POLICY[commandName]
		if not policy then return true end

		local actorId = actorUserId(command)
		if not actorId then return false, "This administrative command requires a live server player." end
		if not authorize(actorId, policy.permission) then
			return false, if policy.permission == "GlobalConfig"
				then "Tiki Tide owner/co-owner authorization is required for global movement settings."
				else "Tiki Tide administrator authorization is required for player movement commands."
		end
		if not consumeBudget(actorId) then
			return false, "Regular administrative commands are being rate-limited. Wait a moment and retry."
		end

		local value = getNumericArgument(command, policy.valueArg)
		if policy.property == "JumpImpulse" then
			value = true
		elseif policy.property == "Flight" or policy.property == "Frozen" then
			value = commandName == "fly" or commandName == "freeze"
		elseif value ~= nil then
			local limits = VALUE_LIMITS[policy.property]
			if not finiteNumber(value) or (limits and (value < limits.min or value > limits.max)) then
				return false, string.format("The requested %s value is outside the permitted range.", policy.property)
			end
		end

		wrapHandler(command, policy)
		return true
	end

	local ok, removeFilter = pcall(_K.Process.addCommandFilter, filter)
	if not ok or type(removeFilter) ~= "function" then
		warn("[Tiki Tide Security][Kohl's] Failed to register regular-command security filter: " .. tostring(removeFilter))
		return
	end

	print("[Tiki Tide Security][Kohl's] Regular command security filter ready. Movement authorization ledger is server-local.")
end
