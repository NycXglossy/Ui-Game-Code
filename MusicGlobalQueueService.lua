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
}

export type State = {
	schemaVersion: number,
	revision: number,
	queue: {QueueEntry},
	current: QueueEntry?,
	playback: Playback,
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
	local soundId = cleanText(raw.soundId, MAX_SOUND_ID)
	if not id or not string.match(id, "^[%w%-_]+$")
		or not trackId or not string.match(trackId, "^[%w%-_]+$")
		or not title or not artist or not genre or not requestedBy
		or not soundId or not string.match(soundId, "^rbxassetid://%d+$") then return nil end
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
		playback = {paused = false, position = 0, anchorTime = Workspace:GetServerTimeNow(), trackRevision = 0},
		updatedAt = os.time(),
		updatedBy = 0,
	}
end

local function sanitizeState(raw: any): State
	local state = defaultState()
	if typeof(raw) ~= "table" or raw.schemaVersion ~= SCHEMA_VERSION then return state end
	state.revision = if finite(raw.revision) then math.max(0, math.floor(raw.revision)) else 0
	state.updatedAt = if finite(raw.updatedAt) then math.max(0, math.floor(raw.updatedAt)) else os.time()
	state.updatedBy = if finite(raw.updatedBy) then math.max(0, math.floor(raw.updatedBy)) else 0
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
	if typeof(raw.playback) == "table" then
		local p = raw.playback
		state.playback.paused = p.paused == true
		state.playback.position = if finite(p.position) then math.clamp(p.position, 0, MAX_DURATION) else 0
		state.playback.anchorTime = if finite(p.anchorTime) then p.anchorTime else Workspace:GetServerTimeNow()
		state.playback.trackRevision = if finite(p.trackRevision) then math.max(0, math.floor(p.trackRevision)) else 0
	end
	return state
end

local function detached(state: State): State
	local result = table.clone(state)
	result.queue = {}
	for _, entry in ipairs(state.queue) do table.insert(result.queue, cloneEntry(entry)) end
	result.current = if state.current then cloneEntry(state.current) else nil
	result.playback = table.clone(state.playback)
	return result
end

local function transact(mutator: (State) -> boolean): (boolean, State?, string?)
	local accepted = false
	local reason = "Shared queue update was rejected."
	local ok, result = pcall(function()
		return STORE:UpdateAsync(KEY, function(old)
			accepted = false
			reason = "Shared queue update was rejected."
			local state = sanitizeState(old)
			local changed = mutator(state)
			if changed then
				state.revision += 1
				state.updatedAt = os.time()
				accepted = true
				reason = ""
				return state
			end
			return old or state
		end)
	end)
	if not ok then
		warn("[ClubMusic Global Queue] DataStore transaction failed: " .. tostring(result))
		return false, nil, "Global queue storage is unavailable. No local-only change was applied."
	end
	if not accepted then return false, if typeof(result) == "table" then detached(sanitizeState(result)) else nil, reason end
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
		if #state.queue >= MAX_QUEUE then reason = "Global queue is full." return false end
		if state.current and state.current.trackId == entry.trackId then reason = "That track is already playing globally." return false end
		for _, queued in ipairs(state.queue) do
			if queued.id == entry.id or queued.trackId == entry.trackId then reason = "That track is already queued globally." return false end
		end
		if entry.source == "player" then
			local count = 0
			for _, queued in ipairs(state.queue) do if queued.source == "player" then count += 1 end end
			if count >= playerCap then reason = "The global player-request queue is full." return false end
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
		reason = "Queue entry was not found."
		return false
	end)
end

function MusicGlobalQueueService:Clear(): (boolean, State?, string?)
	return transact(function(state)
		if #state.queue == 0 then reason = "The global queue is already empty." return false end
		table.clear(state.queue)
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
			reason = "Track already advanced by another server."
			return false
		end
		local nextEntry = table.remove(state.queue, 1)
		if not nextEntry then nextEntry = fallback end
		if not nextEntry then reason = "No valid next track is available." return false end
		state.current = cloneEntry(nextEntry)
		state.playback.paused = false
		state.playback.position = 0
		state.playback.anchorTime = Workspace:GetServerTimeNow()
		state.playback.trackRevision += 1
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
			reason = "The global current track changed; refresh and retry."
			return false
		end
		state.playback.position = if restart then 0 else math.clamp(position, 0, state.current.duration)
		state.playback.paused = if restart then false else paused
		state.playback.anchorTime = Workspace:GetServerTimeNow()
		state.playback.trackRevision += 1
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
