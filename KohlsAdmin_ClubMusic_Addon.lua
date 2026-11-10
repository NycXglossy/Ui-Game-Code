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
--
-- Audit refinement:
-- Actual bridge outcomes are logged here, where accepted/rejected is known.
-- Do not use postCommand to infer whether a ClubMusic action succeeded.

return function(_K: any)
	local function getActorUserId(context: any): number?
		if typeof(context) ~= "table" then
			return nil
		end

		local player = context.fromPlayer
		if typeof(player) == "Instance" and player:IsA("Player") then
			return player.UserId
		end

		local from = context.from
		if typeof(from) == "number"
			and from > 0
			and from % 1 == 0
			and from <= 9007199254740991 then
			return from
		end

		return nil
	end

	local function logOutcome(context: any, operation: string, outcome: string)
		if _K.IsServer ~= true or typeof(_K.log) ~= "function" then
			return
		end

		local level = if outcome == "accepted" then "INFO"
			elseif outcome == "error" then "ERROR"
			else "WARN"

		local actorUserId = getActorUserId(context)
		-- Keep audit records metadata-only. Bridge response text can contain
		-- queue identifiers, track details, or other command-specific data.
		local logMessage = string.format(
			"ClubMusic bridge outcome: operation=%s result=%s",
			operation,
			outcome
		)

		local ok, err = pcall(_K.log, logMessage, level, actorUserId)
		if not ok then
			warn("[ClubMusic Kohl's Admin] Could not write outcome audit log: " .. tostring(err))
		end
	end

	local function finish(context: any, operation: string, outcome: string, message: string): string?
		logOutcome(context, operation, outcome)
		-- Kohl's Admin treats every non-nil string returned by run() as an
		-- error notification. Successful ClubMusic actions already send their
		-- own Notice toast, so only rejected/failed commands return text here.
		return if outcome == "accepted" then nil else message
	end

	-- Read-only inspection has a separate, lightweight throttle because Status and
	-- Queue intentionally bypass mutation cooldowns in the controller. This keeps
	-- repeated queue refreshes from becoming an avoidable server workload.
	local INSPECTION_COOLDOWN_SECONDS = 1.5
	local lastInspectionAt: {[number]: number} = {}
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		lastInspectionAt[player.UserId] = nil
	end)

	local function submit(context: any, operation: string, argument: string?): string?
		local caller = context and context.fromPlayer
		if typeof(caller) ~= "Instance" or not caller:IsA("Player") then
			return finish(context, operation, "rejected", "This command requires an online player caller.")
		end

		if operation == "Status" or operation == "Queue" then
			local now = os.clock()
			local previous = lastInspectionAt[caller.UserId] or 0
			if previous > 0 and now - previous < INSPECTION_COOLDOWN_SECONDS then
				return finish(context, operation, "rejected", "ClubMusic inspection is cooling down. Try again shortly.")
			end
			lastInspectionAt[caller.UserId] = now
		end

		local serverStorage = game:GetService("ServerStorage")
		local bridge = serverStorage:FindFirstChild("ClubMusicAdminBridge")
		-- The shared addon can initialize before the ClubMusic controller finishes
		-- starting. Give the server-only bridge a short, bounded readiness window
		-- instead of failing an otherwise-valid first command during startup.
		if not bridge then
			local waitOk, waitedBridge = pcall(function()
				return serverStorage:WaitForChild("ClubMusicAdminBridge", 5)
			end)
			if waitOk then bridge = waitedBridge end
		end
		-- Waiting for startup can yield long enough for the caller to leave or
		-- for the controller to replace its bridge. Re-resolve both references
		-- immediately before invocation so a stale command cannot use a detached
		-- bridge or continue on behalf of a departed player.
		if caller.Parent ~= game:GetService("Players") then
			return finish(context, operation, "rejected", "The command caller left before ClubMusic could process the command.")
		end
		bridge = serverStorage:FindFirstChild("ClubMusicAdminBridge")
		if not bridge or not bridge:IsA("BindableFunction") or bridge.Parent ~= serverStorage then
			return finish(context, operation, "error", "ClubMusic admin bridge is unavailable. Check the server controller installation and startup Output.")
		end

		local ok, accepted, message = pcall(function()
			return bridge:Invoke(caller, operation, argument)
		end)
		if not ok then
			-- Keep implementation details in the server Output, not in a command
			-- response visible to every caller with access to Kohl's Admin.
			warn("[ClubMusic Kohl's Admin] Bridge invocation failed for operation="
				.. operation .. ": " .. tostring(accepted))
			return finish(context, operation, "error", "ClubMusic bridge invocation failed. Check the server Output for details.")
		end

		if accepted ~= true then
			local rejectionMessage = if typeof(message) == "string" then message else "ClubMusic rejected that command."
			return finish(context, operation, "rejected", rejectionMessage)
		end

		local successMessage = if typeof(message) == "string" then message else "ClubMusic action submitted."
		-- Read-only commands have no ClubMusic state-change Notice, so display
		-- their result through Kohl's Admin's supported informational toast API.
		if operation == "Status" or operation == "Queue" then
			local notifyOk, notifyError = pcall(function()
				_K.Remote.Notify:Fire(caller, {
					From = caller.UserId,
					Text = successMessage,
					Duration = 8,
				})
			end)
			if not notifyOk then
				warn("[ClubMusic Kohl's Admin] Could not display read-only result: " .. tostring(notifyError))
			end
		end
		return finish(context, operation, "accepted", successMessage)
	end

	local function register(name: string, description: string, group: string, operation: string, aliases: {string}?, argumentDefinitions: {any}?)
		_K.Registry.registerCommand(_K, {
			name = name,
			aliases = aliases,
			description = description,
			group = group,
			noLog = false,
			args = argumentDefinitions or {},
			run = function(context, argument: string?)
				return submit(context, operation, argument)
			end,
		})
	end

	register("clubmusic-skip", "Skip the current ClubMusic track.", "General", "Skip", {"cmskip"})
	register("clubmusic-pause", "Toggle ClubMusic playback pause/resume.", "General", "TogglePause", {"cmpause"})
	register("clubmusic-restart", "Restart the current ClubMusic track.", "General", "Restart", {"cmrestart"})
	register("clubmusic-lock", "Toggle ClubMusic song requests lock.", "General", "ToggleRequestLock", {"cmlock"})
	register("clubmusic-clearqueue", "Clear the ClubMusic request queue (ClubMusic admin required).", "Administration", "ClearQueue", {"cmclear"})
	register("clubmusic-status", "Show current ClubMusic playback and request status.", "General", "Status", {"cmstatus"})
	register("clubmusic-queue", "List queued ClubMusic tracks and their removal IDs.", "General", "Queue", {"cmqueue"})
	register("clubmusic-remove", "Remove one queued ClubMusic track by its ID.", "General", "RemoveQueueEntry", {"cmremove"}, {
		{type = "string", name = "QueueId", description = "Queue entry ID copied from ;cmqueue.", optional = false},
	})
end
