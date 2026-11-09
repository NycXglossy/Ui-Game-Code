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
	updatedAt: number,
	updatedBy: number,
}

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
	local ok, result = pcall(function()
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
	if not accepted then
		local snapshot: State? = nil
		if typeof(result) == "table" then snapshot = detached(sanitizeState(result)) end
		return false, snapshot, reason
	end
	return true, detached(sanitizeState(result)), nil
end

function MusicGlobalQueueService:GetSnapshot(): (boolean, State?, string?)
	local ok, raw = pcall(function() return STORE:GetAsync(KEY) end)
	if not ok then
		warn("[ClubMusic Global Queue] Snapshot read failed: " .. tostring(raw))
		return false, nil, "Global queue storage is unavailable."
	end
	return true, detached(sanitizeState(raw)), nil
end

function MusicGlobalQueueService:Enqueue(rawEntry: any, maxPlayerRequests: number?): (boolean, State?, string?)
	local entry = sanitizeEntry(rawEntry)
	if not entry then return false, nil, "Invalid queue entry." end
	local playerCap = if finite(maxPlayerRequests) then math.clamp(math.floor(maxPlayerRequests), 1, MAX_QUEUE) else MAX_QUEUE
	return transact(function(state)
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
function MusicGlobalQueueService:Advance(expectedTrackRevision: any, fallbackEntry: any): (boolean, State?, string?)
	if not finite(expectedTrackRevision) or expectedTrackRevision < 0 then return false, nil, "Invalid track revision." end
	local fallback = sanitizeEntry(fallbackEntry)
	return transact(function(state)
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
