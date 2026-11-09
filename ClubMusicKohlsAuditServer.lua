--!strict
-- Server-only Kohl's Admin audit addon for Firebeach Music Festival Club.
-- Install as a ModuleScript in Kohl's Admin > Config > Addons.
-- The ModuleScript name MUST contain "Server" so Kohl's keeps it server-only.
--
-- This addon is observational only. It does not grant/revoke roles, ban players,
-- invoke ClubMusic actions, or synchronize Kohl's roles into ClubMusic permissions.

return function(_K: any)
	local hooks = _K and _K.Hook
	if typeof(hooks) ~= "table" then
		warn("[ClubMusic Kohl's Audit] Kohl's Admin hook API is unavailable.")
		return
	end

	local function writeLog(message: string, level: string, actorUserId: number?)
		if typeof(_K.log) ~= "function" then
			warn("[ClubMusic Kohl's Audit] " .. message)
			return
		end
		local ok, err = pcall(_K.log, message, level, actorUserId)
		if not ok then
			warn("[ClubMusic Kohl's Audit] Could not write Kohl's log: " .. tostring(err))
		end
	end

	local function connectHook(hookName: string, callback: (...any) -> ())
		local signal = hooks[hookName]
		if signal == nil or typeof(signal.Connect) ~= "function" then
			warn("[ClubMusic Kohl's Audit] Hook unavailable: " .. hookName)
			return
		end
		local ok, err = pcall(function()
			signal:Connect(callback)
		end)
		if not ok then
			warn("[ClubMusic Kohl's Audit] Could not connect " .. hookName .. ": " .. tostring(err))
		end
	end

	local function actorUserId(command: any): number?
		if typeof(command) ~= "table" then return nil end
		local from = command.from
		if typeof(from) == "number" and from > 0 and from % 1 == 0 and from <= 9007199254740991 then
			return from
		end
		if typeof(from) == "Instance" and from:IsA("Player") then
			return from.UserId
		end
		return nil
	end

	local CLUB_MUSIC_ALIASES: {[string]: boolean} = {
		["clubmusic-skip"] = true,
		["cmskip"] = true,
		["clubmusic-pause"] = true,
		["cmpause"] = true,
		["clubmusic-restart"] = true,
		["cmrestart"] = true,
		["clubmusic-lock"] = true,
		["cmlock"] = true,
		["clubmusic-clearqueue"] = true,
		["cmclear"] = true,
		["clubmusic-status"] = true,
		["cmstatus"] = true,
	}

	connectHook("postCommand", function(command: any)
		if typeof(command) ~= "table" then return end
		local alias = command.alias
		if typeof(alias) ~= "string" or not CLUB_MUSIC_ALIASES[string.lower(alias)] then return end
		local userId = actorUserId(command)
		local safeAlias = string.sub(alias, 1, 40)
		writeLog("ClubMusic admin command executed: " .. safeAlias, "COMMAND", userId)
	end)

	local function safeRoleLabel(role: any): string
		if typeof(role) ~= "table" then return "unknown" end
		local label = role.id
		if typeof(label) ~= "string" then label = role.name end
		if typeof(label) ~= "string" then return "unknown" end
		return string.sub(string.gsub(label, "[^%w_%-]", ""), 1, 32)
	end

	connectHook("roleAdded", function(userId: any, role: any)
		if typeof(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then return end
		writeLog("Kohl's role granted: role=" .. safeRoleLabel(role) .. " targetUserId=" .. tostring(userId), "WARN", nil)
	end)

	connectHook("roleRemoved", function(userId: any, role: any)
		if typeof(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then return end
		writeLog("Kohl's role removed: role=" .. safeRoleLabel(role) .. " targetUserId=" .. tostring(userId), "WARN", nil)
	end)

	connectHook("ban", function(key: any, _banData: any)
		if typeof(key) ~= "string" and typeof(key) ~= "number" then return end
		local target = string.sub(tostring(key), 1, 32)
		writeLog("Kohl's moderation ban event: targetKey=" .. target, "WARN", nil)
	end)

	connectHook("unban", function(key: any, _banData: any)
		if typeof(key) ~= "string" and typeof(key) ~= "number" then return end
		local target = string.sub(tostring(key), 1, 32)
		writeLog("Kohl's moderation unban event: targetKey=" .. target, "WARN", nil)
	end)
end
