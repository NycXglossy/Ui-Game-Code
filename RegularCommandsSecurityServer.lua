--!strict
-- Server-only Kohl's Admin integration for Tiki Tide SecurityCore.
-- Install as ServerScriptService > Kohl's Admin > Addons > RegularCommandsSecurityServer.
-- Does not modify Kohl's Admin core or the existing ClubMusic add-on.
--
-- This adapter uses the installed Kohl's Process.addCommandFilter enforcement point.
-- It authorizes before command-request splitting, then wraps only the matched server
-- handlers so movement authority is recorded and moderation actions are audited only after the original handler returns.

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

	local POLICY: {[string]: {permission: string, property: string, valueArg: number?, targetArg: number?, targetArg2: number?, global: boolean?, targetSelf: boolean?, authority: boolean?, auditKind: string?, limitProperty: string?, budget: string?, authorityTTL: number?}} = {
		-- Verified movement/environment commands in the supplied Kohl's Admin export.
		gravity = {permission = "GlobalConfig", property = "WorldGravity", valueArg = 1, global = true, authority = true},
		starterspeed = {permission = "GlobalConfig", property = "StarterWalkSpeed", valueArg = 1, global = true, authority = true},
		speed = {permission = "GlobalModeration", property = "WalkSpeed", valueArg = 2, targetArg = 1, authority = true},
		jumppower = {permission = "GlobalModeration", property = "JumpPower", valueArg = 2, targetArg = 1, authority = true},
		jump = {permission = "GlobalModeration", property = "JumpImpulse", targetArg = 1, authority = true},
		size = {permission = "GlobalModeration", property = "BodyScale", valueArg = 2, targetArg = 1, authority = true},
		fly = {permission = "GlobalModeration", property = "Flight", valueArg = 2, targetArg = 1, authority = true, limitProperty = "FlightSpeed"},
		unfly = {permission = "GlobalModeration", property = "Flight", targetArg = 1, authority = true},
		freeze = {permission = "GlobalModeration", property = "Frozen", targetArg = 1, authority = true},
		thaw = {permission = "GlobalModeration", property = "Frozen", targetArg = 1, authority = true},
		bring = {permission = "GlobalModeration", property = "Teleport", targetArg = 1, authority = true},
		fling = {permission = "GlobalModeration", property = "Fling", valueArg = 2, targetArg = 1, authority = true, limitProperty = "FlingStrength", authorityTTL = 5},
		tp = {permission = "GlobalModeration", property = "Teleport", targetArg = 1, authority = true},
		to = {permission = "GlobalModeration", property = "Teleport", targetSelf = true, authority = true},
		place = {permission = "GlobalConfig", property = "TeleportPlace", targetArg = 1, auditKind = "AdminAction"},

		-- Native moderation enforcement commands retain Kohl's own role/target checks.
		ban = {permission = "GlobalModeration", property = "Ban", targetArg = 1, auditKind = "Moderation"},
		unban = {permission = "GlobalModeration", property = "Unban", targetArg = 1, auditKind = "Moderation"},
		kick = {permission = "GlobalModeration", property = "Kick", targetArg = 1, auditKind = "Moderation"},
		mute = {permission = "GlobalModeration", property = "Mute", targetArg = 1, auditKind = "Moderation"},
		unmute = {permission = "GlobalModeration", property = "Unmute", targetArg = 1, auditKind = "Moderation"},
		punish = {permission = "GlobalModeration", property = "Punish", targetArg = 1, auditKind = "Moderation"},
		unpunish = {permission = "GlobalModeration", property = "Unpunish", targetArg = 1, auditKind = "Moderation"},
		kill = {permission = "GlobalModeration", property = "Kill", targetArg = 1, auditKind = "Moderation"},
		hurt = {permission = "GlobalModeration", property = "Hurt", targetArg = 1, auditKind = "Moderation"},
		health = {permission = "GlobalModeration", property = "Health", targetArg = 1, auditKind = "Moderation"},
		stun = {permission = "GlobalModeration", property = "Stun", targetArg = 1, auditKind = "Moderation"},
		unstun = {permission = "GlobalModeration", property = "Unstun", targetArg = 1, auditKind = "Moderation"},
		blind = {permission = "GlobalModeration", property = "Blind", targetArg = 1, auditKind = "Moderation"},
		unblind = {permission = "GlobalModeration", property = "Unblind", targetArg = 1, auditKind = "Moderation"},

		-- Persistent roles/permissions are owner/co-owner operations.
		role = {permission = "GlobalConfig", property = "RoleAssign", targetArg = 1, auditKind = "AdminAction", budget = "Privilege"},
		temprole = {permission = "GlobalConfig", property = "TemporaryRoleAssign", targetArg = 1, auditKind = "AdminAction", budget = "Privilege"},
		unrole = {permission = "GlobalConfig", property = "RoleRemove", targetArg = 1, auditKind = "AdminAction", budget = "Privilege"},
		removemember = {permission = "GlobalConfig", property = "MemberPermissionsRemove", targetArg = 1, auditKind = "AdminAction", budget = "Privilege"},

		-- Asset/tool grants can introduce executable or persistent content.
		give = {permission = "GlobalConfig", property = "ToolGrant", targetArg = 1, auditKind = "AdminAction", budget = "Asset"},
		startergive = {permission = "GlobalConfig", property = "PersistentToolGrant", targetArg = 1, auditKind = "AdminAction", budget = "Asset"},
		starterremove = {permission = "GlobalConfig", property = "PersistentToolRemove", targetArg = 1, auditKind = "AdminAction", budget = "Asset"},
		copytools = {permission = "GlobalConfig", property = "ToolCopy", targetArg = 1, targetArg2 = 2, auditKind = "AdminAction", budget = "Asset"},
		gear = {permission = "GlobalConfig", property = "AssetGearGrant", valueArg = 2, targetArg = 1, auditKind = "AdminAction", budget = "Asset"},
		btools = {permission = "GlobalConfig", property = "BuildingToolsGrant", targetArg = 1, auditKind = "AdminAction", budget = "Asset"},
		insert = {permission = "GlobalConfig", property = "AssetInsert", valueArg = 1, auditKind = "AdminAction", budget = "Asset"},

		-- Cross-server announcements and local broadcasts are separately permissioned.
		announce = {permission = "GlobalAnnouncement", property = "PersistentAnnouncement", global = true, auditKind = "AdminAction", budget = "Broadcast"},
		unannounce = {permission = "GlobalAnnouncement", property = "PersistentAnnouncementClear", global = true, auditKind = "AdminAction", budget = "Broadcast"},
		hint = {permission = "GlobalAnnouncement", property = "BroadcastHint", auditKind = "AdminAction", budget = "Broadcast"},
		message = {permission = "GlobalAnnouncement", property = "BroadcastMessage", auditKind = "AdminAction", budget = "Broadcast"},
		fullmessage = {permission = "GlobalAnnouncement", property = "FullScreenBroadcast", auditKind = "AdminAction", budget = "Broadcast"},
		privatehint = {permission = "GlobalModeration", property = "PrivateHint", targetArg = 1, auditKind = "AdminAction", budget = "Broadcast"},

		-- Respawn/refresh and destructive world actions are sensitive too.
		respawn = {permission = "GlobalModeration", property = "Respawn", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		refresh = {permission = "GlobalModeration", property = "Refresh", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		removelimbs = {permission = "GlobalModeration", property = "RemoveLimbs", targetArg = 1, auditKind = "Moderation", budget = "Moderation"},
		clean = {permission = "GlobalConfig", property = "AdminCleanup", auditKind = "AdminAction", budget = "World"},
		clearterrain = {permission = "GlobalConfig", property = "ClearTerrain", global = true, auditKind = "AdminAction", budget = "World"},
		time = {permission = "GlobalConfig", property = "LightingTime", auditKind = "AdminAction", budget = "World"},
		brightness = {permission = "GlobalConfig", property = "LightingBrightness", valueArg = 1, limitProperty = "LightingBrightness", auditKind = "AdminAction", budget = "World"},
		colorshift = {permission = "GlobalConfig", property = "LightingColorShift", auditKind = "AdminAction", budget = "World"},
		latitude = {permission = "GlobalConfig", property = "LightingLatitude", auditKind = "AdminAction", budget = "World"},
		diffusescale = {permission = "GlobalConfig", property = "LightingDiffuseScale", auditKind = "AdminAction", budget = "World"},
		exposure = {permission = "GlobalConfig", property = "LightingExposure", auditKind = "AdminAction", budget = "World"},
		disco = {permission = "GlobalConfig", property = "DiscoLighting", auditKind = "AdminAction", budget = "World"},

		-- Server-wide disruptive commands require the highest Tiki Tide permission.
		serverlock = {permission = "GlobalConfig", property = "ServerLock", global = true, auditKind = "AdminAction", budget = "World"},
		unserverlock = {permission = "GlobalConfig", property = "ServerUnlock", global = true, auditKind = "AdminAction", budget = "World"},
		shutdown = {permission = "GlobalConfig", property = "Shutdown", global = true, auditKind = "AdminAction", budget = "World"},
	}

	local BLOCKED_COMMANDS = {
		-- Disable client-crashing/repeated-kill commands and arbitrary cross-server command strings.
		crash = "This command is disabled by Tiki Tide security.",
		loopkill = "This command is disabled by Tiki Tide security.",
		loopfling = "Repeated fling commands are disabled by Tiki Tide security.",
		script = "Arbitrary server script execution is disabled by Tiki Tide security.",
		loadstring = "Arbitrary server script execution is disabled by Tiki Tide security.",
		global = "Native global command strings are disabled; use dedicated Tiki Tide global controls.",
	}

	local VALUE_LIMITS: {[string]: {min: number, max: number}} = {
		WorldGravity = {min = 0, max = 500},
		StarterWalkSpeed = {min = 0, max = 100},
		WalkSpeed = {min = 0, max = 100},
		JumpPower = {min = 0, max = 250},
		BodyScale = {min = 0.1, max = 10},
		FlightSpeed = {min = 0, max = 256},
		FlingStrength = {min = 0.1, max = 5},
		LightingBrightness = {min = 0, max = 10},
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
	local permissionCache: {[number]: {GlobalModeration: boolean, GlobalAnnouncement: boolean, GlobalConfig: boolean, expiresAt: number}} = {}
	local function refreshAuthorization(player: Player)
		task.spawn(function()
			local resolver = ServerStorage:FindFirstChild(AUTHORIZER_NAME)
			if not resolver or not resolver:IsA("BindableFunction") or resolver.Parent ~= ServerStorage then
				permissionCache[player.UserId] = nil
				return
			end
			local snapshotOk, snapshot = pcall(function() return resolver:Invoke(player.UserId, "KohlsAdminSnapshot") end)
			if player.Parent ~= Players then return end
			permissionCache[player.UserId] = {
				GlobalModeration = snapshotOk and typeof(snapshot) == "table" and snapshot.GlobalModeration == true,
				GlobalAnnouncement = snapshotOk and typeof(snapshot) == "table" and snapshot.GlobalAnnouncement == true,
				GlobalConfig = snapshotOk and typeof(snapshot) == "table" and snapshot.GlobalConfig == true,
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

	-- Small per-server buckets are split by risk class so routine moderation
	-- cannot consume the budget reserved for privilege/world-changing operations.
	-- This is synchronous, bounded by active players, and creates no MemoryStore entries.
	local BUDGETS = {
		Moderation = {capacity = 5, refillPerSecond = 0.5},
		Privilege = {capacity = 2, refillPerSecond = 1 / 30},
		Asset = {capacity = 2, refillPerSecond = 1 / 10},
		Broadcast = {capacity = 2, refillPerSecond = 1 / 15},
		World = {capacity = 2, refillPerSecond = 1 / 30},
		General = {capacity = 5, refillPerSecond = 0.5},
	}
	local buckets: {[number]: {[string]: {tokens: number, updatedAt: number}}} = {}
	local function consumeBudget(userId: number, budgetName: string?): boolean
		local config = BUDGETS[budgetName or "General"] or BUDGETS.General
		local userBuckets = buckets[userId]
		if not userBuckets then
			userBuckets = {}
			buckets[userId] = userBuckets
		end
		local now = os.clock()
		local entry = userBuckets[budgetName or "General"]
		if not entry then
			entry = {tokens = config.capacity, updatedAt = now}
			userBuckets[budgetName or "General"] = entry
		end
		entry.tokens = math.min(config.capacity, entry.tokens + math.max(0, now - entry.updatedAt) * config.refillPerSecond)
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
		JumpHeight = true, Anchored = true, Teleport = true, Fling = true,
	}
	local function authorityKey(targetUserId: number, property: string): string
		return tostring(targetUserId) .. ":" .. property
	end
	Players.PlayerRemoving:Connect(function(player)
		for key, entry in pairs(authorityEntries) do
			if entry.actor == player.UserId or entry.target == player.UserId then
				authorityEntries[key] = nil
			end
		end
	end)

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
			local actorPlayer = Players:GetPlayerByUserId(math.floor(actorId))
			if not actorPlayer or actorPlayer.Parent ~= Players then return false, "Movement authority actor is not active." end
			if targetId > 0 then
				local targetPlayer = Players:GetPlayerByUserId(math.floor(targetId))
				if not targetPlayer or targetPlayer.Parent ~= Players then return false, "Movement authority target is not active." end
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

	local auditUnavailableWarned = false
	local function logAction(command: any, policy: any, targets: {Player}, value: any, targetCount: number)
		local id = actorUserId(command)
		local valueText = if value == nil then "default" elseif typeof(value) == "boolean" then tostring(value) else tostring(value)
		local commandName = tostring(command.alias or command.definition.name)
		local message = string.format(
			"Kohl's administrative command invoked: command=%s property=%s targets=%d value=%s",
			commandName, policy.property, targetCount, string.sub(valueText, 1, 24)
		)
		if type(_K.log) == "function" then
			local ok, err = pcall(_K.log, message, "COMMAND", id)
			if not ok then warn("[Tiki Tide Security][Kohl's] Kohl's log failed: " .. tostring(err)) end
		end
		-- Sensitive command invocations enter the existing unified SecurityCore Audit.
		local api = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
		local audit = api and api:IsA("Folder") and api:FindFirstChild("RecordGlobalAuditEvent")
		if audit and audit:IsA("BindableFunction") then
			task.spawn(function()
				local ok = pcall(function()
					return audit:Invoke(policy.auditKind or "AdminAction", id or 0,
						tostring(targetCount) .. " target(s)", "kohls:" .. policy.property)
				end)
				if not ok then warn("[Tiki Tide Security][Kohl's] Unified SecurityCore audit invocation failed for command=" .. commandName) end
			end)
		elseif not auditUnavailableWarned then
			auditUnavailableWarned = true
			warn("[Tiki Tide Security][Kohl's] Unified SecurityCore audit API unavailable; Kohl's command log remains the fallback.")
		end
	end

	local wrappedDefinitions = setmetatable({}, {__mode = "k"})
	local authorityRegistrationWarned = false
	local function wrapHandler(command: any)
		local definition = command.definition
		if wrappedDefinitions[definition] then return end
		local original = definition.run
		if type(original) ~= "function" then return end
		wrappedDefinitions[definition] = true
		definition.run = function(context: any, ...)
			local args = table.pack(...)
			local result = table.pack(original(context, table.unpack(args, 1, args.n)))
			local aliasName = string.lower(tostring(context.alias or definition.name))
			local activePolicy = POLICY[aliasName] or POLICY[string.lower(tostring(definition.name))]
			if not activePolicy then return table.unpack(result, 1, result.n) end

			local targets: {Player} = {}
			local targetCount = if activePolicy.targetSelf then 1 else 0
			for _, targetIndex in ipairs({activePolicy.targetArg, activePolicy.targetArg2}) do
				if targetIndex then
					local rawTargets = args[targetIndex]
					if typeof(rawTargets) == "Instance" and rawTargets:IsA("Player") then
						table.insert(targets, rawTargets)
						targetCount += 1
					elseif typeof(rawTargets) == "table" then
						targetCount += #rawTargets
						for _, target in ipairs(rawTargets) do
							if typeof(target) == "Instance" and target:IsA("Player") then table.insert(targets, target) end
						end
					end
				end
			end

			local value = if activePolicy.valueArg then args[activePolicy.valueArg] else nil
			if activePolicy.property == "JumpImpulse" then value = true end
			if activePolicy.property == "Fling" and value == nil then value = 1 end
			if activePolicy.property == "BodyScale" and (value == nil or context.undo) then value = 1 end
			if activePolicy.property == "Flight" then value = aliasName ~= "unfly" and not context.undo end
			if activePolicy.property == "Frozen" then value = aliasName ~= "thaw" and aliasName ~= "unfreeze" and not context.undo end
			if value == nil then value = "DEFAULT" end

			local actorId = actorUserId(context)
			if actorId then
				if activePolicy.authority == true then
					local function registerAuthority(targetId: number, propertyValue: any)
						local invokeOk, registered = pcall(function()
							return (authority :: BindableFunction):Invoke("Register", actorId, targetId, activePolicy.property, propertyValue, "KohlsAdmin", activePolicy.authorityTTL or 120)
						end)
						if (not invokeOk or registered ~= true) and not authorityRegistrationWarned then
							authorityRegistrationWarned = true
							warn("[Tiki Tide Security][Kohl's] MovementAuthority registration failed; command audit remains active.")
						end
					end
					if activePolicy.targetSelf then
						registerAuthority(actorId, "DEFAULT")
					elseif activePolicy.global then
						local globalValue = value
						if globalValue == "DEFAULT" and activePolicy.property == "WorldGravity" and context.env then globalValue = context.env.gravity end
						registerAuthority(0, globalValue)
					else
						for _, target in ipairs(targets) do registerAuthority(target.UserId, value) end
					end
				end
				logAction(context, activePolicy, targets, value, targetCount)
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
		local commandName = string.lower(tostring(command.alias or command.definition.name or ""))
		local definitionName = string.lower(tostring(command.definition.name or ""))
		local blockedReason = BLOCKED_COMMANDS[commandName] or BLOCKED_COMMANDS[definitionName]
		if blockedReason then
			local actorId = actorUserId(command)
			if actorId then
				task.spawn(function()
					local api = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
					local report = api and api:IsA("Folder") and api:FindFirstChild("ReportSignal")
					if report and report:IsA("BindableFunction") then
						pcall(function() report:Invoke(actorId, "kohls_dangerous_command_blocked", commandName) end)
					end
				end)
			end
			return false, blockedReason
		end
		local policy = POLICY[commandName] or POLICY[definitionName]
		if not policy then return true end

		local actorId = actorUserId(command)
		if not actorId then return false, "This administrative command requires a live server player." end
		if not authorize(actorId, policy.permission) then
			task.spawn(function()
				local api = ServerStorage:FindFirstChild("ClubMusicGlobalAPI")
				local report = api and api:IsA("Folder") and api:FindFirstChild("ReportSignal")
				if report and report:IsA("BindableFunction") then
					pcall(function() report:Invoke(actorId, "kohls_regular_command_denied", commandName) end)
				end
			end)
			return false, if policy.permission == "GlobalConfig"
				then "Tiki Tide owner/co-owner authorization is required for this server-wide command."
				else "Tiki Tide administrator authorization is required for this moderation or player-control command."
		end
		if not consumeBudget(actorId, policy.budget) then
			return false, "Regular administrative commands are being rate-limited. Wait a moment and retry."
		end

		local value = getNumericArgument(command, policy.valueArg)
		local limitProperty = policy.limitProperty or policy.property
		local limits = VALUE_LIMITS[limitProperty]
		if value ~= nil and limits and (not finiteNumber(value) or value < limits.min or value > limits.max) then
			return false, string.format("The requested %s value is outside the permitted range.", limitProperty)
		end
		if policy.property == "JumpImpulse" then
			value = true
		elseif policy.property == "Fling" and value == nil then
			value = 1
		elseif policy.property == "Flight" or policy.property == "Frozen" then
			value = commandName == "fly" or commandName == "freeze"
		elseif value ~= nil and policy.authority == true and not finiteNumber(value) then
			return false, string.format("The requested %s value is invalid.", policy.property)
		end

		wrapHandler(command)
		return true
	end

	local ok, removeFilter = pcall(_K.Process.addCommandFilter, filter)
	if not ok or type(removeFilter) ~= "function" then
		warn("[Tiki Tide Security][Kohl's] Failed to register regular-command security filter: " .. tostring(removeFilter))
		return
	end

	print("[Tiki Tide Security][Kohl's] Regular command security filter ready. Movement authorization ledger is server-local.")
end
