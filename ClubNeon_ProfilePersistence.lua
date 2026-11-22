--!strict
-- Profile loading, validation, session ownership, snapshots, and coalesced persistence.
-- All mutable controller state is injected by reference; shutdown state is read via a closure.
return function(context: {[string]: any})
	local ControllerFunctions = context.ControllerFunctions
	local Players = context.Players
	local getServerShuttingDown = context.getServerShuttingDown
	local USE_STUDIO_MEMORY_PROFILES = context.USE_STUDIO_MEMORY_PROFILES
	local filteredTitleTextByUserId = context.filteredTitleTextByUserId
	local store = context.store
	local SESSION_TOKEN = context.SESSION_TOKEN
	local SESSION_LOCK_SECONDS = context.SESSION_LOCK_SECONDS
	local TAGS = context.TAGS
	local CONFIG = context.CONFIG
	local TITLE_SLOT_COUNT = context.TITLE_SLOT_COUNT
	local TRACK_BY_ID = context.TRACK_BY_ID
	local TITLE_COLORS = context.TITLE_COLORS
	local TITLE_STYLES = context.TITLE_STYLES
	local profiles = context.profiles
	local receiptTransactions = context.receiptTransactions
	local saveQueued = context.saveQueued
	local saveAgain = context.saveAgain
	local saveQueueTokens = context.saveQueueTokens
	ControllerFunctions.defaultProfile = function(): any
		return {
			tickets = 0,
			coins = 0,
			loginStreak = 1,
			lastClaimDay = 0,
			claimedToday = false,
			equippedTag = nil,
			ownedTags = {},
			clubPlaySeconds = 0,
			danceFloorLastRewardAt = 0,
			titleTagUnlocksVersion = 2,
			titleSlots = {},
			unlockedSlots = 1,
			activeSlot = 1,
			showCustomTitle = true,
			rewardedPassTier = 0,
			glowsticks = 0,
			skipTokens = 0,
			neonTrail = false,
			favorites = {},
			xp = 0,
		}
	end
	
	ControllerFunctions.loadProfile = function(player: Player)
		local userId = player.UserId
		if player.Parent ~= Players or serverShuttingDown then return false end
		local profile = ControllerFunctions.defaultProfile()
		local data = nil
		local ok = false
		local lastError = "Profile session is already active on another server."
		local function abandonDepartedLoad(): boolean
			filteredTitleTextByUserId[userId] = nil
			-- The join can finish its yielding DataStore/TextService work after
			-- PlayerRemoving has already run. Retain the lease until its normal expiry:
			-- SESSION_TOKEN is server-scoped, so an immediate same-server rejoin could
			-- otherwise acquire the same owner token and have this stale load clear it.
			return false
		end
	
		if USE_STUDIO_MEMORY_PROFILES then
			-- Studio test profile: keep all existing gameplay/profile features usable
			-- without attempting a DataStore request or requiring API access.
			data = {}
			ok = true
		else
			for attempt = 1, 5 do
				if player.Parent ~= Players or player.UserId ~= userId or serverShuttingDown then return abandonDepartedLoad() end
				if not ControllerFunctions.waitForDataStoreBudget(20) then
					lastError = "Server DataStore request budget is busy."
					break
				end
				-- Serialize load-lock acquisition with local saves and receipt commits.
				-- SESSION_TOKEN is server-scoped, so a rapid same-server rejoin must not
				-- read the old snapshot while that Player's final/periodic write is active.
				local loadWriteLockToken = ControllerFunctions.acquireProfileWriteLock(userId)
				if not loadWriteLockToken then
					lastError = "Profile is busy with another local write."
					break
				end
				local invalidStoredRecord = false
				local callOk, result = pcall(function()
					return store:UpdateAsync(tostring(userId), function(oldData)
						if oldData ~= nil and typeof(oldData) ~= "table" then
							invalidStoredRecord = true
							return nil -- Never replace a corrupt/non-profile value with a default record.
						end
						local current = if typeof(oldData) == "table" then table.clone(oldData) else {}
						local lock = current.sessionLock
						if lock ~= nil then
							local expiresAt = if typeof(lock) == "table" then lock.expiresAt else nil
							if typeof(lock) ~= "table" or typeof(lock.owner) ~= "string" or lock.owner == ""
								or typeof(expiresAt) ~= "number" or expiresAt ~= expiresAt
								or expiresAt <= 0 or expiresAt >= math.huge then
								invalidStoredRecord = true
								return nil -- A malformed lease is ambiguous; fail closed.
							end
							if lock.owner ~= SESSION_TOKEN and expiresAt > os.time() then
								return nil -- Another live server owns this profile.
							end
						end
						current.sessionLock = { owner = SESSION_TOKEN, expiresAt = os.time() + SESSION_LOCK_SECONDS }
						return current
					end)
				end)
				ControllerFunctions.releaseProfileWriteLock(userId, loadWriteLockToken)
				if player.Parent ~= Players or player.UserId ~= userId or serverShuttingDown then return abandonDepartedLoad() end
				if callOk and typeof(result) == "table" then
					data = result
					ok = true
					break
				end
				if invalidStoredRecord then
					lastError = "Stored profile or session lock is malformed; refusing to overwrite it."
				elseif not callOk then
					lastError = tostring(result)
				end
				if attempt < 5 then
					task.wait(2)
					if player.Parent ~= Players or player.UserId ~= userId or serverShuttingDown then return abandonDepartedLoad() end
				end
			end
		end
		if not ok then
			warn("[ClubMusic] Profile load/lock failed for " .. player.Name .. ": " .. lastError .. ". Profile remains unavailable; refusing to save defaults.")
			return false
		end
		filteredTitleTextByUserId[userId] = {}
		if typeof(data) == "table" then
			profile.xp = math.clamp(math.floor(tonumber(data.xp) or 0), 0, 9007199254740000)
			profile.tickets = math.max(0, tonumber(data.tickets) or 0)
			profile.coins = math.max(0, tonumber(data.coins) or 0)
			profile.loginStreak = math.clamp(math.floor(tonumber(data.loginStreak) or 1), 1, 7)
			profile.lastClaimDay = math.max(0, math.floor(tonumber(data.lastClaimDay) or 0))
			profile.claimedToday = data.claimedToday == true
			profile.equippedTag = if typeof(data.equippedTag) == "string" and TAGS[data.equippedTag] == true then data.equippedTag else nil
			profile.showCustomTitle = data.showCustomTitle ~= false
			profile.rewardedPassTier = math.clamp(math.floor(tonumber(data.rewardedPassTier) or 0), 0, 3)
			profile.glowsticks = math.max(0, math.floor(tonumber(data.glowsticks) or 0))
			profile.skipTokens = math.max(0, math.floor(tonumber(data.skipTokens) or 0))
			profile.neonTrail = data.neonTrail == true
			profile.clubPlaySeconds = math.clamp(math.floor(tonumber(data.clubPlaySeconds) or 0), 0, 9007199254740000)
			local savedDanceFloorRewardAt = tonumber(data.danceFloorLastRewardAt)
			profile.danceFloorLastRewardAt = if ControllerFunctions.isFiniteNumber(savedDanceFloorRewardAt)
				then math.max(0, math.floor(savedDanceFloorRewardAt)) else 0
			profile.titleTagUnlocksVersion = math.max(0, math.floor(tonumber(data.titleTagUnlocksVersion) or 0))
			if typeof(data.ownedTags) == "table" then
				for id, owned in pairs(data.ownedTags) do
					if TAGS[id] == true and owned == true then profile.ownedTags[id] = true end
				end
			end
			-- One-time migration: the previous defaults falsely marked these tags as owned.
			-- Re-evaluate them below using the real server-side unlock conditions.
			if profile.titleTagUnlocksVersion < 2 then
				profile.ownedTags.vip = nil
				profile.ownedTags.party = nil
				profile.ownedTags.wave = nil
				if profile.equippedTag == "vip" or profile.equippedTag == "party" or profile.equippedTag == "wave" then
					profile.equippedTag = nil
				end
				profile.titleTagUnlocksVersion = 2
			end
			if typeof(data.favorites) == "table" then
				local count = 0
				for id, flag in pairs(data.favorites) do
					if count >= CONFIG.MaxFavorites then break end
					if typeof(id) == "string" and flag == true and TRACK_BY_ID[id] then
						profile.favorites[id] = true
						count += 1
					end
				end
			end
	
			-- Load every valid new-format slot first. Only migrate the legacy title when
			-- none of the new-format slots contains a valid title; this repairs profiles
			-- with an empty/invalid titleSlots table without overwriting newer slot data.
			profile.unlockedSlots = math.clamp(math.floor(tonumber(data.unlockedSlots) or 1), 1, TITLE_SLOT_COUNT)
			local hasValidNewTitle = false
			if typeof(data.titleSlots) == "table" then
				for i = 1, TITLE_SLOT_COUNT do
					local stored = data.titleSlots[tostring(i)] or data.titleSlots[i]
					local clean = ControllerFunctions.sanitizeTitleSlot(stored)
					if clean then
						profile.titleSlots[i] = clean
						hasValidNewTitle = true
					end
				end
			end
	
			if not hasValidNewTitle and typeof(data.customTitle) == "string" and data.customTitle ~= "" then
				local legacyColor = if typeof(data.titleColor) == "string" and TITLE_COLORS[data.titleColor] == true then data.titleColor else "gold"
				local legacyStyle = if typeof(data.titleStyle) == "string" and TITLE_STYLES[data.titleStyle] == true then data.titleStyle else "normal"
				local legacy = ControllerFunctions.sanitizeTitleSlot({
					text = data.customTitle, effect = "fixed", set = legacyColor, font = "gotham", style = legacyStyle,
				})
				if legacy then
					-- Legacy text is player-authored. Re-filter it for broadcast before it
					-- can be placed in replicated player attributes. Never fall back to raw text.
					local filteredText = ControllerFunctions.filterTitleText(player, legacy.text)
					if filteredText and filteredText ~= "" then
						legacy.text = filteredText
						profile.titleSlots[1] = legacy
						filteredTitleTextByUserId[player.UserId][1] = filteredText
					else
						warn("[ClubMusic] Legacy custom title migration was skipped because Roblox text filtering failed for userId " .. tostring(player.UserId))
					end
				else
					warn("[ClubMusic] Legacy custom title migration was skipped because the saved title failed validation for userId " .. tostring(player.UserId))
				end
			end
			profile.activeSlot = math.clamp(math.floor(tonumber(data.activeSlot) or 1), 1, TITLE_SLOT_COUNT)
		end
	
		-- Staff have all three custom-title slots unlocked automatically. Existing
		-- player-owned slots and title data are preserved; this only raises access.
		if ControllerFunctions.isStaff(player) then
			profile.unlockedSlots = TITLE_SLOT_COUNT
		end
	
		-- The active slot must be unlocked and filled; otherwise fall back to the first filled slot.
		if profile.activeSlot > profile.unlockedSlots or profile.titleSlots[profile.activeSlot] == nil then
			profile.activeSlot = ControllerFunctions.firstFilledSlot(profile) or 1
		end
		if profile.titleSlots[profile.activeSlot] then
			-- Only the active title is filtered during join; other slots are filtered
			-- lazily when selected, avoiding up to three TextService calls per player.
			ControllerFunctions.ensureFilteredTitleSlot(player, profile, profile.activeSlot)
		end
		-- Text filtering can yield after the DataStore session lock was acquired.
		-- Do not publish a profile or player attributes for a departed join.
		if player.Parent ~= Players or player.UserId ~= userId or serverShuttingDown then return abandonDepartedLoad() end
	
		local today = math.floor(os.time() / 86400)
		if profile.lastClaimDay < today then
			if profile.lastClaimDay > 0 and today - profile.lastClaimDay == 1 then
				profile.loginStreak = (profile.loginStreak % 7) + 1
			elseif profile.lastClaimDay == 0 or today - profile.lastClaimDay > 1 then
				profile.loginStreak = 1
			end
			profile.claimedToday = false
		end
	
		profiles[userId] = profile
		player:SetAttribute("XP", profile.xp)
		player:SetAttribute("Level", math.floor(profile.xp / CONFIG.XPPerLevel) + 1)
		player:SetAttribute("XPToNextLevel", CONFIG.XPPerLevel - (profile.xp % CONFIG.XPPerLevel))
		player:SetAttribute("Tickets", profile.tickets)
		player:SetAttribute("Coins", profile.coins)
		player:SetAttribute("Glowsticks", profile.glowsticks)
		player:SetAttribute("SkipTokens", profile.skipTokens)
		player:SetAttribute("NeonTrailUnlocked", profile.neonTrail)
		player:SetAttribute("LoginStreak", profile.loginStreak)
		player:SetAttribute("ClaimedToday", profile.claimedToday)
		player:SetAttribute("EquippedTag", profile.equippedTag or "")
		ControllerFunctions.applyTitleAttributes(player, profile)
		return true
	end
	
	local function buildProfileSnapshot(profile: any): {[string]: any}
		local slotsSnapshot: {[string]: any} = {}
		for i = 1, TITLE_SLOT_COUNT do
			local slot = profile.titleSlots[i]
			if slot then
				slotsSnapshot[tostring(i)] = {
					text = slot.text, effect = slot.effect, set = slot.set, font = slot.font,
					style = slot.style, textSize = slot.textSize, height = slot.height, distance = slot.distance,
				}
			end
		end
	
		return {
			tickets = profile.tickets,
			coins = profile.coins,
			loginStreak = profile.loginStreak,
			lastClaimDay = profile.lastClaimDay,
			claimedToday = profile.claimedToday,
			equippedTag = profile.equippedTag,
			ownedTags = table.clone(profile.ownedTags),
			clubPlaySeconds = profile.clubPlaySeconds,
			danceFloorLastRewardAt = profile.danceFloorLastRewardAt,
			titleTagUnlocksVersion = profile.titleTagUnlocksVersion,
			titleSlots = slotsSnapshot,
			unlockedSlots = profile.unlockedSlots,
			activeSlot = profile.activeSlot,
			showCustomTitle = profile.showCustomTitle,
			rewardedPassTier = profile.rewardedPassTier,
			glowsticks = profile.glowsticks,
			skipTokens = profile.skipTokens,
			neonTrail = profile.neonTrail,
			favorites = table.clone(profile.favorites),
			xp = profile.xp,
		}
	end
	
	local function profileSnapshotsEqual(left: any, right: any): boolean
		if typeof(left) ~= "table" or typeof(right) ~= "table" then
			return left == right
		end
		for key, value in pairs(left) do
			if not profileSnapshotsEqual(value, right[key]) then return false end
		end
		for key in pairs(right) do
			if left[key] == nil then return false end
		end
		return true
	end
	
	ControllerFunctions.saveProfile = function(player: Player, lockTimeoutSeconds: number?, budgetTimeoutSeconds: number?)
		-- Studio memory mode intentionally has no durable backend. The in-memory
		-- profile remains authoritative for this test session; never call UpdateAsync.
		if USE_STUDIO_MEMORY_PROFILES then
			return profiles[player.UserId] ~= nil
		end
	
		local userId = player.UserId
		local profile = profiles[userId]
		if not profile then return false end
		local writeLockToken = ControllerFunctions.acquireProfileWriteLock(userId, lockTimeoutSeconds)
		if not writeLockToken then return false end
		profile = profiles[userId]
		if not profile then ControllerFunctions.releaseProfileWriteLock(userId, writeLockToken); return false end
		if not ControllerFunctions.waitForDataStoreBudget(budgetTimeoutSeconds or 8) then
			ControllerFunctions.releaseProfileWriteLock(userId, writeLockToken)
			warn("[ClubMusic] Profile save deferred: server DataStore budget is busy for userId " .. tostring(userId))
			return false
		end
	
		-- Capture a detached snapshot before the yielding UpdateAsync call.
		local snapshot = buildProfileSnapshot(profile)
		local ownershipLost = false
		local ok, result = pcall(function()
			return store:UpdateAsync(tostring(userId), function(oldData)
				if typeof(oldData) ~= "table" or typeof(oldData.sessionLock) ~= "table"
					or oldData.sessionLock.owner ~= SESSION_TOKEN then
					ownershipLost = true
					return nil -- This server no longer owns the profile; never overwrite another session.
				end
				local pendingReceiptId = if typeof(oldData.pendingReceipt) == "string" then oldData.pendingReceipt else nil
				local hasPendingReceiptMemory = if pendingReceiptId and receiptTransactions
					then receiptTransactions:HasPendingMemory(profile, pendingReceiptId) else false
				if hasPendingReceiptMemory then
					-- Do not overwrite a durably applied reward with a stale in-memory snapshot.
					return nil
				end
				local preservedReceipts = {}
				if typeof(oldData) == "table" and typeof(oldData.receiptIds) == "table" then
					for id, value in pairs(oldData.receiptIds) do
						if typeof(id) == "string" and value == true then preservedReceipts[id] = true end
					end
				end
				local preservedPendingReceipt = if typeof(oldData.pendingReceipt) == "string" then oldData.pendingReceipt else nil
				-- Start from the current durable record so fields introduced by an
				-- older/newer profile writer survive this controller's narrower schema.
				-- The validated in-memory snapshot remains authoritative for every field
				-- this controller owns; nested allowlisted collections are replaced below.
				local output = table.clone(oldData)
				for key, value in pairs(snapshot) do
					output[key] = value
				end
				output.ownedTags = table.clone(snapshot.ownedTags)
				output.favorites = table.clone(snapshot.favorites)
				output.receiptIds = preservedReceipts -- legacy entries only; new receipts use the sharded journal.
				output.pendingReceipt = preservedPendingReceipt
				output.sessionLock = { owner = SESSION_TOKEN, expiresAt = os.time() + SESSION_LOCK_SECONDS }
				return output
			end)
		end)
		-- Detect mutations that happened while UpdateAsync was yielding, including
		-- throttled reward/XP paths that do not enqueue on every individual change.
		local profileChangedDuringSave = profiles[userId] == profile
			and not profileSnapshotsEqual(buildProfileSnapshot(profile), snapshot)
		ControllerFunctions.releaseProfileWriteLock(userId, writeLockToken)
		if not ok or typeof(result) ~= "table" then
			warn("[ClubMusic] Profile save failed for " .. player.Name .. ": " .. tostring(result or "profile session ownership lost"))
			if ownershipLost and player.Parent == Players then
				-- A second server now owns this profile. Stop this session from continuing
				-- to mutate a stale in-memory copy that can no longer be saved safely.
				player:Kick("Your profile session moved to another server. Please rejoin.")
			end
			return false
		end
		if profileChangedDuringSave and player.Parent == Players and profiles[userId] == profile then
			ControllerFunctions.scheduleProfileSave(player)
		end
		return true
	end
	
	-- Collapse rapid profile mutations into one save. Queue identity prevents a
	-- delayed callback from an old Player instance clearing a rejoin's new queue.
	ControllerFunctions.scheduleProfileSave = function(player: Player)
		if serverShuttingDown then return end
		local userId = player.UserId
		local scheduledProfile = profiles[userId]
		if not scheduledProfile then return end
		if saveQueued[userId] then
			saveAgain[userId] = true
			return
		end
		local queueToken = {}
		saveQueueTokens[userId] = queueToken
		saveQueued[userId] = true
		task.delay(CONFIG.ProfileSaveQueueDelaySeconds, function()
			if saveQueueTokens[userId] ~= queueToken then return end
			if serverShuttingDown or player.Parent ~= Players or profiles[userId] ~= scheduledProfile then
				saveQueued[userId] = nil
				saveAgain[userId] = nil
				saveQueueTokens[userId] = nil
				return
			end
			ControllerFunctions.saveProfile(player)
			if saveQueueTokens[userId] ~= queueToken then return end
			saveQueued[userId] = nil
			saveQueueTokens[userId] = nil
			if saveAgain[userId] then
				saveAgain[userId] = nil
				if player.Parent == Players and profiles[userId] == scheduledProfile then
					ControllerFunctions.scheduleProfileSave(player)
				end
			end
		end)
	end
	
end
