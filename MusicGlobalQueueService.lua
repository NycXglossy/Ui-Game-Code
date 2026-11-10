--!strict
-- MusicGlobalQueueService
-- Place as ModuleScript: ServerStorage/MusicGlobalQueueService
-- Atomic shared queue/playback state. This module does not play audio and never
-- trusts client data; callers must pass server-validated queue entries.
--
-- All state mutations use DataStore UpdateAsync. MessagingService is only an
-- invalidation/notification fast path; callers must reconcile from GetSnapshot.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local MusicGlobalQueueService = {}

local STORE = DataStoreService:GetDataStore("ClubMusic_GlobalQueue_v1")
local KEY = "globalState"
local SCHEMA_VERSION = 1
local MAX_QUEUE = 80
local MAX_ID = 64
local MAX_TEXT = 100
local MAX_SOUND_ID = 64
local MAX_DURATION = 3600
local MAX_SAFE_INTEGER = 9007199254740991

export type QueueEntry = {
	id: string,
	trackId: string,
	title: string,
	artist: string,
	genre: string,
	duration: number,
	requestedBy: string,
	userId: number,
	source: string,
	vip: boolean,
	passTier: number,
	soundId: string,
	queuedAt: number,
}

export type Playback = {
	paused: boolean,
	position: number,
	anchorTime: number,
	trackRevision: number,
	restartRevision: number,
}

export type Rotation = {enabled: boolean, id: string, name: string, trackIds: {string}, cursor: number}
type State = {
	schemaVersion: number,
	revision: number,
	queue: {QueueEntry},
	current: QueueEntry?,
	playback: Playback,
	rotation: Rotation,
	autoQueueHold: boolean,
	catalogRevision: number,
	catalogChangeTrackId: string?,
	catalogChangeKind: string?,
	updatedAt: number,
	updatedBy: number,
}

local cachedSnapshot: State? = nil
local cachedSnapshotAt = 0
local SNAPSHOT_CACHE_SECONDS = 3

-- Serialize this server's queue-store calls and wait for Roblox's real request
-- budget before touching the shared key. The MemoryStore limiter above this
-- module is aggregate protection; it is not a substitute for DataStore budget.
local storeOperationBusy = false

local function withStoreOperation(requestType: Enum.DataStoreRequestType, callback: () -> any): (boolean, any)
	local lockStartedAt = os.clock()
	while storeOperationBusy do
		if os.clock() - lockStartedAt >= 8 then
			return false, "Timed out waiting for the local global-queue store lock."
		end
		task.wait(0.05)
	end
	storeOperationBusy = true

	local budgetStartedAt = os.clock()
	while true do
		local budgetOk, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(requestType)
		end)
		if budgetOk and budget >= 1 then break end
		if os.clock() - budgetStartedAt >= 5 then
			storeOperationBusy = false
			return false, "Roblox DataStore request budget is temporarily unavailable."
		end
		task.wait(0.1)
	end

	local callOk, result = pcall(callback)
	storeOperationBusy = false
	if not callOk then return false, result end
	return true, result
end

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function cleanText(value: any, maxLength: number): string?
	if typeof(value) ~= "string" or #value < 1 or #value > maxLength or string.find(value, "[%c]") then
		return nil
	end
	return value
end

local function sanitizeEntry(raw: any): QueueEntry?
	if typeof(raw) ~= "table" then return nil end
	local id = cleanText(raw.id, MAX_ID)
	local trackId = cleanText(raw.trackId, 32)
	local title = cleanText(raw.title, MAX_TEXT)
	local artist = cleanText(raw.artist, MAX_TEXT)
	local genre = cleanText(raw.genre, 48)
	local requestedBy = cleanText(raw.requestedBy, MAX_TEXT)
	local soundId = if typeof(raw.soundId) == "string" then raw.soundId else ""
	if not id or not string.match(id, "^[%w%-_]+$")
		or not trackId or not string.match(trackId, "^[%w%-_]+$")
		or not title or not artist or not genre or not requestedBy
		or #soundId > MAX_SOUND_ID
		or (soundId ~= "" and not string.match(soundId, "^rbxassetid://%d+$")) then return nil end
	if not finite(raw.duration) or raw.duration < 1 or raw.duration > MAX_DURATION then return nil end
	if not finite(raw.userId) or raw.userId < 0 or raw.userId % 1 ~= 0 or raw.userId > MAX_SAFE_INTEGER then return nil end
	if not finite(raw.passTier) or raw.passTier < 0 or raw.passTier > 3 or raw.passTier % 1 ~= 0 then return nil end
	if typeof(raw.vip) ~= "boolean" then return nil end
	local source = raw.source
	if source ~= "player" and source ~= "auto" and source ~= "playlist" then return nil end
	return {
		id = id, trackId = trackId, title = title, artist = artist, genre = genre,
		duration = math.floor(raw.duration), requestedBy = requestedBy,
		userId = math.floor(raw.userId), source = source, vip = raw.vip,
		passTier = math.floor(raw.passTier), soundId = soundId,
		queuedAt = if finite(raw.queuedAt) then math.max(0, math.floor(raw.queuedAt)) else os.time(),
	}
end

local function cloneEntry(entry: QueueEntry): QueueEntry
	return table.clone(entry)
end

local function defaultState(): State
	return {
		schemaVersion = SCHEMA_VERSION,
		revision = 0,
		queue = {},
		current = nil,
		playback = {paused = false, position = 0, anchorTime = Workspace:GetServerTimeNow(), trackRevision = 0, restartRevision = 0},
		rotation = {enabled = false, id = "", name = "", trackIds = {}, cursor = 1},
		autoQueueHold = false,
		catalogRevision = 0,
		catalogChangeTrackId = nil,
		catalogChangeKind = nil,
		updatedAt = os.time(),
		updatedBy = 0,
	}
end

local function sanitizeState(raw: any): State
	local state = defaultState()
	if typeof(raw) ~= "table" or raw.schemaVersion ~= SCHEMA_VERSION then return state end
	state.revision = if finite(raw.revision) then math.clamp(math.floor(raw.revision), 0, MAX_SAFE_INTEGER) else 0
	state.updatedAt = if finite(raw.updatedAt) then math.max(0, math.floor(raw.updatedAt)) else os.time()
	state.updatedBy = if finite(raw.updatedBy) then math.max(0, math.floor(raw.updatedBy)) else 0
	state.autoQueueHold = raw.autoQueueHold == true
	state.catalogRevision = if finite(raw.catalogRevision)
		then math.clamp(math.floor(raw.catalogRevision), 0, MAX_SAFE_INTEGER) else 0
	-- Accept the earlier in-branch reservation field during rollout so an
	-- interrupted removal is not discarded when the service script is updated.
	local pendingCatalogTrackId = if cleanText(raw.catalogChangeTrackId, 32)
		then raw.catalogChangeTrackId
		elseif cleanText(raw.catalogRemovalTrackId, 32) then raw.catalogRemovalTrackId
		else nil
	state.catalogChangeTrackId = pendingCatalogTrackId
	state.catalogChangeKind = if raw.catalogChangeKind == "remove" or raw.catalogChangeKind == "add"
		then raw.catalogChangeKind
		elseif cleanText(raw.catalogRemovalTrackId, 32) then "remove"
		else nil
	if state.catalogChangeTrackId == nil then state.catalogChangeKind = nil end
	state.current = sanitizeEntry(raw.current)
	if typeof(raw.queue) == "table" then
		local seenIds: {[string]: boolean} = {}
		local seenTracks: {[string]: boolean} = {}
		for _, rawEntry in ipairs(raw.queue) do
			if #state.queue >= MAX_QUEUE then break end
			local entry = sanitizeEntry(rawEntry)
			if entry and not seenIds[entry.id] and not seenTracks[entry.trackId]
				and (not state.current or state.current.trackId ~= entry.trackId) then
				table.insert(state.queue, entry)
				seenIds[entry.id] = true
				seenTracks[entry.trackId] = true
			end
		end
	end
	if typeof(raw.rotation) == "table" then
		local rotation = raw.rotation
		local id = cleanText(rotation.id, 64)
		local name = cleanText(rotation.name, 100)
		if rotation.enabled == true and id and name and typeof(rotation.trackIds) == "table" then
			local seenTracks: {[string]: boolean} = {}
			for _, trackId in ipairs(rotation.trackIds) do
				if #state.rotation.trackIds >= 200 then break end
				if typeof(trackId) == "string" and #trackId > 0 and #trackId <= 32
					and string.match(trackId, "^[%w%-_]+$") and not seenTracks[trackId] then
					table.insert(state.rotation.trackIds, trackId); seenTracks[trackId] = true
				end
			end
			if #state.rotation.trackIds > 0 then
				state.rotation.enabled = true; state.rotation.id = id; state.rotation.name = name
				state.rotation.cursor = if finite(rotation.cursor) then math.clamp(math.floor(rotation.cursor), 1, #state.rotation.trackIds) else 1
			end
		end
	end
	if typeof(raw.playback) == "table" then
		local p = raw.playback
		state.playback.paused = p.paused == true
		state.playback.position = if finite(p.position) then math.clamp(p.position, 0, MAX_DURATION) else 0
		state.playback.anchorTime = if finite(p.anchorTime) then p.anchorTime else Workspace:GetServerTimeNow()
		state.playback.trackRevision = if finite(p.trackRevision) then math.max(0, math.floor(p.trackRevision)) else 0
		state.playback.restartRevision = if finite(p.restartRevision) then math.max(0, math.floor(p.restartRevision)) else 0
	end
	return state
end

local function detached(state: State): State
	local result = table.clone(state)
	result.queue = {}
	for _, entry in ipairs(state.queue) do table.insert(result.queue, cloneEntry(entry)) end
	result.current = if state.current then cloneEntry(state.current) else nil
	result.playback = table.clone(state.playback)
	result.rotation = table.clone(state.rotation)
	result.rotation.trackIds = table.clone(state.rotation.trackIds)
	return result
end

local function transact(mutator: (State) -> (boolean, string?)): (boolean, State?, string?)
	local accepted = false
	local reason = "Shared queue update was rejected."
	local ok, result = withStoreOperation(Enum.DataStoreRequestType.UpdateAsync, function()
		return STORE:UpdateAsync(KEY, function(old)
			accepted = false
			reason = "Shared queue update was rejected."
			local state = sanitizeState(old)
			-- DataStore revisions are used as monotonic concurrency markers. Refuse
			-- writes at the exact-integer ceiling rather than silently losing precision.
			if state.revision >= MAX_SAFE_INTEGER then
				reason = "Global queue revision limit reached; writes are paused for safe recovery."
				return old or state
			end
			local changed, message = mutator(state)
			if changed then
				state.revision += 1
				state.updatedAt = os.time()
				accepted = true
				reason = ""
				return state
			end
			reason = message or reason
			return old or state
		end)
	end)
	if not ok then
		warn("[ClubMusic Global Queue] DataStore transaction failed: " .. tostring(result))
		return false, nil, "Global queue storage is unavailable. No local-only change was applied."
	end
	local snapshot: State? = nil
	if typeof(result) == "table" then
		snapshot = detached(sanitizeState(result))
		cachedSnapshot = snapshot
		cachedSnapshotAt = os.clock()
	end
	if not accepted then
		return false, if snapshot then detached(snapshot) else nil, reason
	end
	return true, if snapshot then detached(snapshot) else nil, nil
end

function MusicGlobalQueueService:InvalidateSnapshot()
	cachedSnapshot = nil
	cachedSnapshotAt = 0
end

function MusicGlobalQueueService:GetSnapshot(): (boolean, State?, string?)
	if cachedSnapshot and os.clock() - cachedSnapshotAt < SNAPSHOT_CACHE_SECONDS then
		return true, detached(cachedSnapshot), nil
	end
	local ok, raw = withStoreOperation(Enum.DataStoreRequestType.GetAsync, function()
		return STORE:GetAsync(KEY)
	end)
	if not ok then
		warn("[ClubMusic Global Queue] Snapshot read failed: " .. tostring(raw))
		return false, nil, "Global queue storage is temporarily unavailable."
	end
	cachedSnapshot = detached(sanitizeState(raw))
	cachedSnapshotAt = os.clock()
	return true, detached(cachedSnapshot), nil
end

function MusicGlobalQueueService:Enqueue(rawEntry: any, maxPlayerRequests: number?, expectedCatalogRevision: any): (boolean, State?, string?)
	local entry = sanitizeEntry(rawEntry)
	if not entry then return false, nil, "Invalid queue entry." end
	if not finite(expectedCatalogRevision) or expectedCatalogRevision < 0 then
		return false, nil, "A valid catalog revision is required."
	end
	local playerCap = if finite(maxPlayerRequests) then math.clamp(math.floor(maxPlayerRequests), 1, MAX_QUEUE) else MAX_QUEUE
	return transact(function(state)
		if math.floor(expectedCatalogRevision) ~= state.catalogRevision then
			return false, "Catalog changed on another server; refresh and retry."
		end
		if state.catalogChangeTrackId == entry.trackId then
			return false, "That catalog track is undergoing a change; try again shortly."
		end
		if state.autoQueueHold and entry.source ~= "player" then
			return false, "Automatic queue refill is paused until the current track changes."
		end
		if #state.queue >= MAX_QUEUE then return false, "Global queue is full." end
		if state.current and state.current.trackId == entry.trackId then return false, "That track is already playing globally." end
		for _, queued in ipairs(state.queue) do
			if queued.id == entry.id or queued.trackId == entry.trackId then return false, "That track is already queued globally." end
		end
		if entry.source == "player" then
			local count = 0
			for _, queued in ipairs(state.queue) do if queued.source == "player" then count += 1 end end
			if count >= playerCap then return false, "The global player-request queue is full." end
		end
		local index = #state.queue + 1
		if entry.source == "player" then
			index = 1
			for i, queued in ipairs(state.queue) do
				if queued.source ~= "player" then index = i; break end
				local queuedTier = queued.passTier
				if entry.passTier > queuedTier then index = i; break end
				index = i + 1
			end
		end
		if entry.source == "playlist" then
			if not state.rotation.enabled then return false, "Playlist rotation is not active globally." end
			local expectedTrackId = state.rotation.trackIds[state.rotation.cursor]
			if expectedTrackId ~= entry.trackId then return false, "Playlist rotation advanced on another server; refresh and retry." end
			state.rotation.cursor += 1
			if state.rotation.cursor > #state.rotation.trackIds then state.rotation.cursor = 1 end
		end
		table.insert(state.queue, index, cloneEntry(entry))
		return true
	end)
end


-- Commit automatic refill entries in one transaction. Queue target and playlist
-- cursor are checked inside UpdateAsync, preventing concurrent servers from
-- overfilling the Auto DJ queue or consuming the same rotation positions.
function MusicGlobalQueueService:EnqueueBatch(rawEntries: any, maxQueueSize: any, targetQueueSize: any, expectedCatalogRevision: any): (boolean, State?, string?)
	if not finite(expectedCatalogRevision) or expectedCatalogRevision < 0 then
		return false, nil, "A valid catalog revision is required."
	end
	if typeof(rawEntries) ~= "table" or #rawEntries < 1 or #rawEntries > 10 then
		return false, nil, "Invalid automatic queue batch."
	end
	if not finite(maxQueueSize) or not finite(targetQueueSize) then
		return false, nil, "Invalid automatic queue limits."
	end
	local hardLimit = math.clamp(math.floor(maxQueueSize), 1, MAX_QUEUE)
	local target = math.clamp(math.floor(targetQueueSize), 1, hardLimit)
	local entries: {QueueEntry} = {}
	for index, rawEntry in ipairs(rawEntries) do
		if index > 10 then return false, nil, "Automatic queue batch is too large." end
		local entry = sanitizeEntry(rawEntry)
		if not entry or (entry.source ~= "auto" and entry.source ~= "playlist") then
			return false, nil, "Automatic queue batch contains an invalid entry."
		end
		table.insert(entries, entry)
	end
	if #entries ~= #rawEntries then return false, nil, "Automatic queue batch must be a dense array." end
	return transact(function(state)
		if math.floor(expectedCatalogRevision) ~= state.catalogRevision then
			return false, "Catalog changed on another server; refresh and retry."
		end
		if state.autoQueueHold then return false, "Automatic queue refill is paused until the current track changes." end
		if #state.queue >= target then return false, "The global automatic queue target is already filled." end
		local seenIds: {[string]: boolean} = {}
		local seenTracks: {[string]: boolean} = {}
		if state.current then
			seenIds[state.current.id] = true
			seenTracks[state.current.trackId] = true
		end
		for _, queued in ipairs(state.queue) do
			seenIds[queued.id] = true
			seenTracks[queued.trackId] = true
		end
		local added = 0
		for _, entry in ipairs(entries) do
			if #state.queue >= target or #state.queue >= hardLimit then break end
			if state.catalogChangeTrackId == entry.trackId then
				return false, "An automatic track is undergoing a catalog change; refresh and retry."
			end
			if seenIds[entry.id] or seenTracks[entry.trackId] then
				return false, "Automatic queue batch contains a duplicate or already-playing track."
			end
			if entry.source == "playlist" then
				if not state.rotation.enabled then return false, "Playlist rotation is not active globally." end
				local expectedTrackId = state.rotation.trackIds[state.rotation.cursor]
				if expectedTrackId ~= entry.trackId then
					return false, "Playlist rotation advanced on another server; refresh and retry."
				end
				state.rotation.cursor += 1
				if state.rotation.cursor > #state.rotation.trackIds then state.rotation.cursor = 1 end
			end
			table.insert(state.queue, cloneEntry(entry))
			seenIds[entry.id] = true
			seenTracks[entry.trackId] = true
			added += 1
		end
		if added == 0 then return false, "No automatic queue entries were added." end
		return true
	end)
end
function MusicGlobalQueueService:Remove(entryId: any): (boolean, State?, string?)
	if typeof(entryId) ~= "string" or #entryId < 1 or #entryId > MAX_ID then return false, nil, "Invalid queue entry." end
	return transact(function(state)
		for index, entry in ipairs(state.queue) do
			if entry.id == entryId then table.remove(state.queue, index); return true end
		end
		return false, "Queue entry was not found."
	end)
end

function MusicGlobalQueueService:MoveUp(entryId: any): (boolean, State?, string?)
	if typeof(entryId) ~= "string" or #entryId < 1 or #entryId > MAX_ID then return false, nil, "Invalid queue entry." end
	return transact(function(state)
		for index, entry in ipairs(state.queue) do
			if entry.id == entryId then
				if index <= 1 then return false, "Queue entry is already first." end
				state.queue[index], state.queue[index - 1] = state.queue[index - 1], state.queue[index]
				return true
			end
		end
		return false, "Queue entry was not found."
	end)
end

function MusicGlobalQueueService:RemoveUserEntries(userId: any): (boolean, State?, string?)
	if not finite(userId) or userId < 1 or userId % 1 ~= 0 or userId > MAX_SAFE_INTEGER then
		return false, nil, "Invalid user ID."
	end
	return transact(function(state)
		local filtered = {}
		local removed = 0
		for _, entry in ipairs(state.queue) do
			if entry.source == "player" and entry.userId == userId then removed += 1
			else table.insert(filtered, entry) end
		end
		if removed == 0 then return false, "No queued requests were found for that user." end
		state.queue = filtered
		return true
	end)
end

function MusicGlobalQueueService:SetPlaylistRotation(playlistId: any, playlistName: any, trackIds: any): (boolean, State?, string?)
	if playlistId == nil then
		return transact(function(state)
			state.rotation = {enabled = false, id = "", name = "", trackIds = {}, cursor = 1}
			local filtered = {}
			for _, entry in ipairs(state.queue) do if entry.source == "player" then table.insert(filtered, entry) end end
			state.queue = filtered
			return true
		end)
	end
	local id = cleanText(playlistId, 64)
	local name = cleanText(playlistName, 100)
	if not id or not name or typeof(trackIds) ~= "table" or #trackIds < 1 or #trackIds > 200 then
		return false, nil, "Invalid playlist rotation."
	end
	local cleanIds = {}
	local seen: {[string]: boolean} = {}
	for _, trackId in ipairs(trackIds) do
		if typeof(trackId) ~= "string" or #trackId < 1 or #trackId > 32
			or not string.match(trackId, "^[%w%-_]+$") or seen[trackId] then
			return false, nil, "Invalid playlist track list."
		end
		seen[trackId] = true; table.insert(cleanIds, trackId)
	end
	return transact(function(state)
		state.rotation = {enabled = true, id = id, name = name, trackIds = cleanIds, cursor = 1}
		local filtered = {}
		for _, entry in ipairs(state.queue) do if entry.source == "player" then table.insert(filtered, entry) end end
		state.queue = filtered
		return true
	end)
end

function MusicGlobalQueueService:Clear(): (boolean, State?, string?)
	return transact(function(state)
		-- Clearing an already-empty held queue is an idempotent success.
		-- Keep the hold set so Auto DJ cannot refill it before the next track.
		table.clear(state.queue)
		-- Prevent Auto DJ from immediately repopulating the queue. Advance
		-- releases this hold atomically when the current track changes.
		state.autoQueueHold = true
		return true
	end)
end

-- Compare-and-swap transition: only one server can consume a given current
-- track revision. The caller supplies a server-validated fallback when empty.
function MusicGlobalQueueService:Advance(expectedTrackRevision: any, fallbackEntry: any, expectedCatalogRevision: any): (boolean, State?, string?)
	if not finite(expectedTrackRevision) or expectedTrackRevision < 0 then return false, nil, "Invalid track revision." end
	if not finite(expectedCatalogRevision) or expectedCatalogRevision < 0 then return false, nil, "A valid catalog revision is required." end
	local fallback = sanitizeEntry(fallbackEntry)
	return transact(function(state)
		if math.floor(expectedCatalogRevision) ~= state.catalogRevision then
			return false, "Catalog changed on another server; refresh and retry."
		end
		if state.catalogChangeTrackId ~= nil and fallback and fallback.trackId == state.catalogChangeTrackId then
			return false, "The fallback track is undergoing a catalog change."
		end
		if state.playback.trackRevision ~= math.floor(expectedTrackRevision) then
			return false, "Track already advanced by another server."
		end
		local nextEntry = table.remove(state.queue, 1)
		if not nextEntry then
			if state.rotation.enabled then
				local expectedId = state.rotation.trackIds[state.rotation.cursor]
				if not fallback or fallback.source ~= "playlist" or fallback.trackId ~= expectedId then
					return false, "A playlist track must be selected from the active global rotation."
				end
				state.rotation.cursor += 1
				if state.rotation.cursor > #state.rotation.trackIds then state.rotation.cursor = 1 end
			else
				if fallback and fallback.source == "playlist" then return false, "Global playlist rotation is not active." end
			end
			nextEntry = fallback
		end
		if not nextEntry then return false, "No valid next track is available." end
		state.current = cloneEntry(nextEntry)
		state.playback.paused = false
		state.playback.position = 0
		state.playback.anchorTime = Workspace:GetServerTimeNow()
		state.playback.trackRevision += 1
		state.autoQueueHold = false
		return true
	end)
end

-- Catalog revisions fence stale server-side catalog caches from shared queue writes.
-- A removal reservation is committed in this same DataStore before the separate
-- catalog DataStore is changed. It remains pending until the controller confirms
-- the catalog result, so a server crash cannot reopen the enqueue race.
function MusicGlobalQueueService:ReserveCatalogRemoval(trackId: any, expectedCatalogRevision: any): (boolean, State?, string?)
	if not cleanText(trackId, 32) or not string.match(trackId, "^[%w%-_]+$")
		or not finite(expectedCatalogRevision) or expectedCatalogRevision < 0 then
		return false, nil, "Invalid catalog removal request."
	end
	return transact(function(state)
		if math.floor(expectedCatalogRevision) ~= state.catalogRevision then
			return false, "Catalog changed on another server; refresh and retry."
		end
		if state.catalogChangeTrackId == trackId and state.catalogChangeKind == "remove" then
			return false, "Catalog removal is already reserved for this track."
		end
		if state.catalogChangeTrackId ~= nil then
			return false, if state.catalogChangeTrackId == trackId
				then "A catalog addition is already reserved for this track."
				else "Another catalog change is already in progress."
		end
		if state.current and state.current.trackId == trackId then
			return false, "That track is currently playing globally."
		end
		for _, entry in ipairs(state.queue) do
			if entry.trackId == trackId then return false, "That track is in the shared queue. Remove it first." end
		end
		if state.catalogRevision >= MAX_SAFE_INTEGER then
			return false, "Catalog revision limit reached; removal is paused for safe recovery."
		end
		state.catalogRevision += 1
		state.catalogChangeTrackId = trackId
		state.catalogChangeKind = "remove"
		return true
	end)
end

function MusicGlobalQueueService:CompleteCatalogRemoval(trackId: any): (boolean, State?, string?)
	if not cleanText(trackId, 32) then return false, nil, "Invalid catalog track ID." end
	return transact(function(state)
		if state.catalogChangeTrackId ~= trackId or state.catalogChangeKind ~= "remove" then
			return false, "No matching catalog removal reservation exists."
		end
		state.catalogChangeTrackId = nil
		state.catalogChangeKind = nil
		return true
	end)
end

function MusicGlobalQueueService:ReserveCatalogAddition(trackId: any, expectedCatalogRevision: any): (boolean, State?, string?)
	if not cleanText(trackId, 32) or not string.match(trackId, "^custom%-%d+$")
		or not finite(expectedCatalogRevision) or expectedCatalogRevision < 0 then
		return false, nil, "Invalid catalog addition request."
	end
	return transact(function(state)
		if math.floor(expectedCatalogRevision) ~= state.catalogRevision then
			return false, "Catalog changed on another server; refresh and retry."
		end
		if state.catalogChangeTrackId == trackId and state.catalogChangeKind == "add" then
			return false, "Catalog addition is already reserved for this track."
		end
		if state.catalogChangeTrackId ~= nil then
			return false, if state.catalogChangeTrackId == trackId
				then "A catalog removal is already reserved for this track."
				else "Another catalog change is already in progress."
		end
		if state.current and state.current.trackId == trackId then
			return false, "That track is currently playing globally."
		end
		for _, entry in ipairs(state.queue) do
			if entry.trackId == trackId then return false, "That track is already in the shared queue." end
		end
		if state.catalogRevision >= MAX_SAFE_INTEGER then
			return false, "Catalog revision limit reached; addition is paused for safe recovery."
		end
		state.catalogRevision += 1
		state.catalogChangeTrackId = trackId
		state.catalogChangeKind = "add"
		return true
	end)
end

function MusicGlobalQueueService:CompleteCatalogAddition(trackId: any): (boolean, State?, string?)
	if not cleanText(trackId, 32) then return false, nil, "Invalid catalog track ID." end
	return transact(function(state)
		if state.catalogChangeTrackId ~= trackId or state.catalogChangeKind ~= "add" then
			return false, "No matching catalog addition reservation exists."
		end
		state.catalogChangeTrackId = nil
		state.catalogChangeKind = nil
		return true
	end)
end

function MusicGlobalQueueService:AdvanceCatalogRevision(): (boolean, State?, string?)
	return transact(function(state)
		if state.catalogChangeTrackId ~= nil then
			return false, "A catalog change is still in progress."
		end
		if state.catalogRevision >= MAX_SAFE_INTEGER then
			return false, "Catalog revision limit reached; catalog writes are paused for safe recovery."
		end
		state.catalogRevision += 1
		return true
	end)
end

function MusicGlobalQueueService:SetPlayback(paused: any, position: any, expectedTrackRevision: any, restart: any): (boolean, State?, string?)
	if typeof(paused) ~= "boolean" or not finite(position) or position < 0 or position > MAX_DURATION
		or not finite(expectedTrackRevision) or expectedTrackRevision < 0 or typeof(restart) ~= "boolean" then
		return false, nil, "Invalid playback state."
	end
	return transact(function(state)
		if state.playback.trackRevision ~= math.floor(expectedTrackRevision) or not state.current then
			return false, "The global current track changed; refresh and retry."
		end
		state.playback.position = if restart then 0 else math.clamp(position, 0, state.current.duration)
		state.playback.paused = if restart then false else paused
		state.playback.anchorTime = Workspace:GetServerTimeNow()
		state.playback.restartRevision = if finite(state.playback.restartRevision) then math.floor(state.playback.restartRevision) else 0
		if restart then state.playback.restartRevision += 1 end
		-- trackRevision identifies the current song only; playback controls must
		-- not invalidate another server's in-flight track transition.
		return true
	end)
end

function MusicGlobalQueueService:GetPosition(snapshot: any): number
	if typeof(snapshot) ~= "table" or typeof(snapshot.playback) ~= "table" then return 0 end
	local playback = snapshot.playback
	local position = if finite(playback.position) then playback.position else 0
	if playback.paused ~= true then
		local anchor = if finite(playback.anchorTime) then playback.anchorTime else Workspace:GetServerTimeNow()
		position += math.max(0, Workspace:GetServerTimeNow() - anchor)
	end
	local duration = if typeof(snapshot.current) == "table" and finite(snapshot.current.duration) then snapshot.current.duration else MAX_DURATION
	return math.clamp(position, 0, duration)
end

return MusicGlobalQueueService
