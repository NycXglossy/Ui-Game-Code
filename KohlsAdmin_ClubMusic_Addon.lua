--!strict
-- Kohl's Admin shared addon for Firebeach Music Festival Club.
-- Install as a ModuleScript in Kohl's Admin > Config > Addons.
-- Keep the module name shared (do not append Server or Client).
--
-- Security boundary:
--   1. Kohl's Admin applies its configured role/group access before run().
--   2. The server-only BindableFunction is unavailable to clients.
--   3. ClubMusic independently checks its own staff/admin rank.
--   4. The controller applies its existing action budgets, cooldowns, and handlers.
--
-- Kohl's Admin uses its built-in command groups for role authorization.
-- General is normally available to moderators; Administration to admins.
-- ClubMusic then independently applies its own staff/admin rank checks.
-- This addon intentionally exposes a small fixed command set. It does not provide
-- arbitrary action names, queue IDs, player targets, asset IDs, or raw payloads.

return function(_K: any)
	local function submit(context: any, operation: string): string?
		local caller = context and context.fromPlayer
		if typeof(caller) ~= "Instance" or not caller:IsA("Player") then
			return "This command requires an online player caller."
		end

		local serverStorage = game:GetService("ServerStorage")
		local bridge = serverStorage:FindFirstChild("ClubMusicAdminBridge")
		if not bridge or not bridge:IsA("BindableFunction") then
			return "ClubMusic admin bridge is unavailable. Check the server controller installation."
		end

		local ok, accepted, message = pcall(function()
			return bridge:Invoke(caller, operation)
		end)
		if not ok then
			warn("[ClubMusic Kohl's Admin] Bridge invocation failed: " .. tostring(accepted))
			return "ClubMusic could not process that command."
		end
		if accepted ~= true then
			return if typeof(message) == "string" then message else "ClubMusic rejected that command."
		end
		return if typeof(message) == "string" then message else "ClubMusic action submitted."
	end

	local function register(name: string, description: string, group: string, operation: string, aliases: {string}?)
		_K.Registry.registerCommand(_K, {
			name = name,
			aliases = aliases,
			description = description,
			group = group,
			noLog = false,
			args = {},
			run = function(context)
				return submit(context, operation)
			end,
		})
	end

	register("clubmusic-skip", "Skip the current ClubMusic track.", "General", "Skip", {"cmskip"})
	register("clubmusic-pause", "Toggle ClubMusic playback pause/resume.", "General", "TogglePause", {"cmpause"})
	register("clubmusic-restart", "Restart the current ClubMusic track.", "General", "Restart", {"cmrestart"})
	register("clubmusic-lock", "Toggle ClubMusic song requests lock.", "General", "ToggleRequestLock", {"cmlock"})
	register("clubmusic-clearqueue", "Clear the ClubMusic request queue (ClubMusic admin required).", "Administration", "ClearQueue", {"cmclear"})
end
