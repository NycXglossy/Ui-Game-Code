--!strict
-- Club Neon local queue primitives.
-- The queue and request accounting tables are supplied by the controller and
-- remain server-local. This module does not create a second queue.

local QueuePrimitives = {}

function QueuePrimitives.create(context: any)
	local ControllerFunctions = context.ControllerFunctions
	local HttpService = context.HttpService
	local CONFIG = context.CONFIG
	local queue = context.queue
	local requestCounts = context.requestCounts
	local RunService = context.RunService
	local queueCounter = 0

	local functions = {}

	function functions.makeEntry(track: any, source: string, player: Player?): any
		queueCounter += 1
		return {
			id = "cm-" .. HttpService:GenerateGUID(false),
			trackId = track.id,
			title = track.title,
			artist = track.artist,
			duration = track.duration,
			requestedBy = if player then player.DisplayName else "Auto DJ",
			userId = if player then player.UserId else 0,
			genre = track.genre,
			source = source,
			vip = if player then ControllerFunctions.isVip(player) else false,
			passTier = if player then ControllerFunctions.passTier(player) else 0,
			soundId = track.soundId or CONFIG.SoundIds[track.id],
		}
	end

	function functions.releaseSlot(entry: any)
		if entry.source == "player" and entry.userId > 0 then
			local remaining = (requestCounts[entry.userId] or 0) - 1
			requestCounts[entry.userId] = if remaining > 0 then remaining else nil
		end
	end

	function functions.countPlayerEntries(): number
		local n = 0
		for _, entry in ipairs(queue) do
			if entry.source == "player" then n += 1 end
		end
		return n
	end

	function functions.findQueueIndex(id: string): number?
		for index, entry in ipairs(queue) do
			if entry.id == id then return index end
		end
		return nil
	end

	-- Priority order: Club Neon, VVIP, VIP, normal player requests, then auto.
	function functions.insertIndex(tier: number): number
		local lastPlayer = 0
		local insertAt = 0
		for index, entry in ipairs(queue) do
			if entry.source == "player" then
				lastPlayer = index
				local existingTier = tonumber(entry.passTier) or (entry.vip and 1 or 0)
				if tier > 0 and existingTier >= tier then insertAt = index end
			end
		end
		if tier > 0 and CONFIG.VipPriority then return insertAt + 1 end
		return lastPlayer + 1
	end

	function functions.isTrackBlocked(trackId: string): boolean
		if typeof(trackId) ~= "string" or #trackId < 1 or #trackId > 64
			or not string.match(trackId, "^[%w%-_]+$") then return true end

		local cache = ControllerFunctions.blockedTrackCache or {}
		ControllerFunctions.blockedTrackCache = cache
		local now = os.clock()
		local cached = cache[trackId]
		if typeof(cached) == "table" and typeof(cached.blocked) == "boolean"
			and typeof(cached.checkedAt) == "number" and now - cached.checkedAt < 300 then
			return cached.blocked
		end

		local callOk, blocked, lookupOk = ControllerFunctions.globalInvoke("IsTrackBlocked", trackId)
		if callOk and lookupOk == true and typeof(blocked) == "boolean" then
			cache[trackId] = {blocked = blocked, checkedAt = now}
			return blocked
		end

		-- Studio can test without the global moderation backend. Live servers
		-- fail closed when no moderation decision is available.
		if cached and cached.blocked == true then return true end
		return not RunService:IsStudio()
	end

	-- Refill only the server-local queue. Playlist entries take precedence while
	-- playlist rotation is active; otherwise use the controller's filtered Auto DJ
	-- selector. Bound attempts so an exhausted playlist/catalog cannot spin.
	function functions.topUpAuto()
		if ControllerFunctions.autoQueueHold == true then return end
		local target = math.clamp(math.floor(tonumber(CONFIG.AutoQueueTarget) or 3), 0, 50)
		local attempts = 0
		while #queue < target and attempts < math.max(6, target * 4) do
			attempts += 1
			local playlistTrack = if typeof(ControllerFunctions.nextPlaylistTrack) == "function"
				then ControllerFunctions.nextPlaylistTrack() else nil
			local track = playlistTrack or ControllerFunctions.pickAutoTrack()
			if not track then break end
			local duplicate = track.id == (ControllerFunctions.currentTrackId or "")
			for _, queuedEntry in ipairs(queue) do
				if queuedEntry.trackId == track.id then duplicate = true; break end
			end
			if not duplicate then
				table.insert(queue, functions.makeEntry(track, if playlistTrack then "playlist" else "auto", nil))
			end
		end
	end

	function functions.clearAutomaticQueue()
		for index = #queue, 1, -1 do
			local entry = queue[index]
			if entry.source ~= "player" then
				table.remove(queue, index)
			end
		end
	end

	-- Expose through the controller table to avoid growing the size-limited
	-- controller source with another wiring block.
	ControllerFunctions.topUpAuto = functions.topUpAuto
	ControllerFunctions.clearAutomaticQueue = functions.clearAutomaticQueue

	return functions
end

return QueuePrimitives
