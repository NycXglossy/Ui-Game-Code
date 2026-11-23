--!strict
-- Server-observed, profile-backed dance-floor rewards. No client-provided activity or payout data.
return function(context: {[string]: any})
	local ControllerFunctions = context.ControllerFunctions
	local Players = context.Players
	local profiles = context.profiles
	local controllerScript = context.controllerScript
	local getServerShuttingDown = context.getServerShuttingDown
	ControllerFunctions.startDanceFloorRewards = function()
		if ControllerFunctions.DanceFloorRewardsStarted == true then return end
		ControllerFunctions.DanceFloorRewardsStarted = true
	
		local CollectionService = game:GetService("CollectionService")
		local Workspace = game:GetService("Workspace")
		local ZONE_TAG = "ClubNeonDanceFloorZone"
		local TICK_INTERVAL = 10
		local BASE_PAYOUT = 15
		local IDLE_CUTOFF_SECONDS = 180
		local SAVE_INTERVAL_SECONDS = 30
		local MAX_TAGGED_INSTANCES_TO_INSPECT = 64
		local MAX_ZONES = 16
		local MAX_ANIMATION_TRACKS_TO_INSPECT = 64
		local playerStates: {[number]: any} = {}
		local warnedMissingZone = false
	
		local function hasDanceFloorActivity(humanoid: Humanoid, moved: boolean): boolean
			if moved or humanoid.MoveDirection.Magnitude >= 0.05 then return true end
			local ok, tracks = pcall(function()
				return humanoid:GetPlayingAnimationTracks()
			end)
			if not ok or typeof(tracks) ~= "table" then return false end
			for index = 1, math.min(#tracks, MAX_ANIMATION_TRACKS_TO_INSPECT) do
				local track = tracks[index]
				if track and track.IsPlaying == true
					and track.Priority.Value >= Enum.AnimationPriority.Movement.Value then
					return true
				end
			end
			return false
		end
	
		local function isInsideDanceFloor(rootPart: BasePart, zones: {BasePart}): boolean
			for _, zone in ipairs(zones) do
				local halfSize = zone.Size * 0.5
				if halfSize.X > 0 and halfSize.Y > 0 and halfSize.Z > 0 then
					local relative = zone.CFrame:PointToObjectSpace(rootPart.Position)
					if math.abs(relative.X) <= halfSize.X
						and math.abs(relative.Z) <= halfSize.Z
						and math.abs(relative.Y) <= halfSize.Y + 10 then
						return true
					end
				end
			end
			return false
		end
	
		task.spawn(function()
			while controllerScript.Parent and not getServerShuttingDown() do
				task.wait(TICK_INTERVAL)
				if getServerShuttingDown() then break end
				local tagged = CollectionService:GetTagged(ZONE_TAG)
				local zones: {BasePart} = {}
				for index, instance in ipairs(tagged) do
					if index > MAX_TAGGED_INSTANCES_TO_INSPECT or #zones >= MAX_ZONES then break end
					if instance:IsA("BasePart") and instance:IsDescendantOf(Workspace) then
						table.insert(zones, instance)
					end
				end
	
				if #zones == 0 then
					if not warnedMissingZone then
						warnedMissingZone = true
						warn("[ClubMusic][DanceFloorRewards] No valid BasePart tagged ClubNeonDanceFloorZone; rewards are disabled until the map zone is configured.")
					end
				else
					warnedMissingZone = false
				end
	
				local nowClock = os.clock()
				local nowUnix = os.time()
				for _, player in ipairs(Players:GetPlayers()) do
					local userId = player.UserId
					local character = player.Character
					local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
					local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
					if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
						local existing = playerStates[userId]
						if existing then
							existing.character = nil
							existing.lastPosition = nil
						end
						continue
					end
	
					local state = playerStates[userId]
					if not state or state.character ~= character then
						-- A respawn resets the position sample, not the AFK timer; repeatedly
						-- resetting characters must not keep an inactive player reward-eligible.
						state = {
							character = character,
							lastPosition = root.Position,
							lastActivityClock = if state then state.lastActivityClock else nowClock,
							lastSaveClock = if state then state.lastSaveClock else nowClock,
						}
						playerStates[userId] = state
					else
						local moved = if state.lastPosition
							then (root.Position - state.lastPosition).Magnitude >= 0.5 else false
						if hasDanceFloorActivity(humanoid, moved) then
							state.lastActivityClock = nowClock
						end
						state.lastPosition = root.Position
					end
	
					if #zones == 0 or nowClock - state.lastActivityClock > IDLE_CUTOFF_SECONDS
						or not isInsideDanceFloor(root, zones) then
						continue
					end
	
					local profile = profiles[userId]
					if not profile then continue end
					local lastRewardAt = profile.danceFloorLastRewardAt
					if not ControllerFunctions.isFiniteNumber(lastRewardAt) then lastRewardAt = 0 end
					if nowUnix - lastRewardAt < TICK_INTERVAL then continue end
	
					-- Membership is resolved through Security Core, not the replicated IsVIP attribute.
					local multiplier = if ControllerFunctions.passTier(player) >= 1 then 2 else 1
					local reward = BASE_PAYOUT * multiplier
					if not ControllerFunctions.isFiniteNumber(profile.coins)
						or profile.coins < 0 or profile.coins > 9007199254740000 - reward then
						continue
					end
	
					-- Balance and interval marker are included in the same existing profile
					-- snapshot. Once persisted, the timestamp prevents rapid duplicate grants across service restarts.
					profile.coins += reward
					profile.danceFloorLastRewardAt = nowUnix
					player:SetAttribute("Coins", profile.coins)
					if nowClock - state.lastSaveClock >= SAVE_INTERVAL_SECONDS then
						state.lastSaveClock = nowClock
						ControllerFunctions.scheduleProfileSave(player)
					end
				end
			end
		end)
	
		Players.PlayerRemoving:Connect(function(player)
			playerStates[player.UserId] = nil
		end)
	end
	
end
