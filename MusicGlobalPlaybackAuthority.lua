--!strict
-- Playback-only cross-server authority. Queue data is deliberately not represented here.
local Workspace = game:GetService("Workspace")

local PlaybackAuthority = {}
PlaybackAuthority.__index = PlaybackAuthority

local LEASE_KEY = "playbackLeader_v1"
local SNAPSHOT_KEY = "playbackSnapshot_v1"
local LEASE_TTL = 24
local MAX_TRACK_TEXT = 120
local MAX_DURATION = 24 * 60 * 60

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function cleanText(value: any, maxLength: number): string?
	if typeof(value) ~= "string" or #value < 1 or #value > maxLength or string.find(value, "[%c]") then return nil end
	return value
end

local function sanitizeTrack(raw: any): {[string]: any}?
	if raw == nil then return nil end
	if typeof(raw) ~= "table" then return nil end
	local trackId = cleanText(raw.trackId, 32)
	local title = cleanText(raw.title, MAX_TRACK_TEXT)
	local artist = cleanText(raw.artist, MAX_TRACK_TEXT)
	local soundId = raw.soundId
	if not trackId or not title or not artist or typeof(soundId) ~= "string"
		or #soundId > 64 or not string.match(soundId, "^rbxassetid://%d+$")
		or not finite(raw.duration) or raw.duration < 1 or raw.duration > MAX_DURATION then
		return nil
	end
	return {
		trackId = trackId,
		title = title,
		artist = artist,
		soundId = soundId,
		duration = math.floor(raw.duration),
	}
end

local function allowStoreOperation(self: any): boolean
	if type(self.allowStoreOperation) ~= "function" then return true end
	local ok, allowed = pcall(self.allowStoreOperation)
	return ok and allowed == true
end

local function sanitizeSnapshot(raw: any): {[string]: any}
	local state = {
		schemaVersion = 1,
		revision = 0,
		trackRevision = 0,
		current = nil,
		paused = false,
		position = 0,
		anchorTime = Workspace:GetServerTimeNow(),
		leaderJobId = "",
		leaderToken = "",
		leaderGeneration = 0,
		updatedAt = os.time(),
	}
	if typeof(raw) ~= "table" or raw.schemaVersion ~= 1 then return state end
	state.revision = if finite(raw.revision) then math.max(0, math.floor(raw.revision)) else 0
	state.trackRevision = if finite(raw.trackRevision) then math.max(0, math.floor(raw.trackRevision)) else 0
	state.current = sanitizeTrack(raw.current)
	state.paused = raw.paused == true
	state.position = if finite(raw.position) then math.clamp(raw.position, 0, MAX_DURATION) else 0
	state.anchorTime = if finite(raw.anchorTime) then raw.anchorTime else Workspace:GetServerTimeNow()
	state.leaderJobId = if typeof(raw.leaderJobId) == "string" then string.sub(raw.leaderJobId, 1, 128) else ""
	state.leaderToken = if typeof(raw.leaderToken) == "string" then string.sub(raw.leaderToken, 1, 64) else ""
	state.leaderGeneration = if finite(raw.leaderGeneration) then math.max(0, math.floor(raw.leaderGeneration)) else 0
	state.updatedAt = if finite(raw.updatedAt) then math.max(0, math.floor(raw.updatedAt)) else os.time()
	return state
end

function PlaybackAuthority.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table", "PlaybackAuthority dependencies are required")
	return setmetatable({
		safeCall = dependencies.safeCall,
		dataStoreService = dependencies.dataStoreService,
		memoryStoreService = dependencies.memoryStoreService,
		jobId = tostring(dependencies.jobId or ""),
		guid = dependencies.guid,
		publish = dependencies.publish,
		allowStoreOperation = dependencies.allowStoreOperation,
		store = nil,
		leaseMap = nil,
		leaseToken = nil,
		leaseExpiresAt = 0,
		leaderGeneration = nil,
		leadershipReady = false,
		lastError = nil,
		started = false,
	}, PlaybackAuthority)
end

function PlaybackAuthority:_safeCall(operation: string, callback: (...any) -> ...any, ...: any): ...any
	if self.safeCall and type(self.safeCall.Run) == "function" then
		return self.safeCall:Run("PlaybackAuthority", operation, callback, ...)
	end
	return pcall(callback, ...)
end

function PlaybackAuthority:Start(): (boolean, string?)
	if self.started then return true, nil end
	local ok, result = self:_safeCall("DataStoreAndMemoryStore.Initialize", function()
		self.store = self.dataStoreService:GetDataStore("ClubMusic_GlobalPlaybackOnly_v1")
		self.leaseMap = self.memoryStoreService:GetHashMap("ClubMusic_GlobalPlaybackLeader_v1")
	end)
	if not ok then return false, tostring(result) end
	self.started = true
	return true, nil
end

function PlaybackAuthority:GetLeader(): (boolean, {[string]: any}?, string?)
	if not self.started or not self.leaseMap then return false, nil, "Playback authority is not started." end
	local ok, value = self:_safeCall("MemoryStore.GetLeaderLease", function() return self.leaseMap:GetAsync(LEASE_KEY) end)
	if not ok then return false, nil, tostring(value) end
	if typeof(value) ~= "table" or not finite(value.expiresAt) or value.expiresAt <= os.time()
		or typeof(value.jobId) ~= "string" or typeof(value.token) ~= "string" then
		return true, nil, nil
	end
	return true, {jobId = value.jobId, token = value.token, expiresAt = value.expiresAt}, nil
end

function PlaybackAuthority:AcquireOrRenewLeadership(): (boolean, {[string]: any}?, string?)
	if not self.started or not self.leaseMap then return false, nil, "Playback authority is not started." end
	local now = os.time()
	local proposedToken = self.leaseToken or self.guid()
	local alreadyFencedLeader = self.leadershipReady == true and self.leaseToken == proposedToken and self.leaderGeneration ~= nil
	local ok, value = self:_safeCall("MemoryStore.AcquireOrRenewLease", function()
		return self.leaseMap:UpdateAsync(LEASE_KEY, function(old)
			if typeof(old) == "table" and finite(old.expiresAt) and old.expiresAt > now then
				if old.jobId == self.jobId and old.token == self.leaseToken then
					return {jobId = self.jobId, token = self.leaseToken, expiresAt = now + LEASE_TTL}
				end
				return old
			end
			return {jobId = self.jobId, token = proposedToken, expiresAt = now + LEASE_TTL}
		end, LEASE_TTL)
	end)
	if not ok then return false, nil, tostring(value) end
	if typeof(value) ~= "table" or value.jobId ~= self.jobId or value.token ~= proposedToken then
		self.leaseToken = nil
		self.leaseExpiresAt = 0
		return false, if typeof(value) == "table" then value else nil, "Another server currently owns global playback."
	end
	self.leaseToken = proposedToken
	self.leaseExpiresAt = value.expiresAt
	self.leadershipReady = alreadyFencedLeader

	-- Claim a monotonically increasing generation in the same durable record
	-- that playback commits update. Once this claim wins, older generations
	-- can no longer commit, even if an old server wakes after a long stall.
	local claimed: any = nil
	if alreadyFencedLeader then
		local snapshotOk, snapshot, snapshotError = self:GetSnapshot()
		if not snapshotOk or not snapshot or snapshot.leaderToken ~= proposedToken or snapshot.leaderJobId ~= self.jobId
			or snapshot.leaderGeneration ~= self.leaderGeneration then
			self.leadershipReady = false
			self.lastError = tostring(snapshotError or "Durable leadership fence no longer matches this lease.")
			return false, nil, self.lastError
		end
		claimed = snapshot
	else
		if not allowStoreOperation(self) then
			self.lastError = "Per-server DataStore operation budget unavailable."
			return false, nil, self.lastError
		end
		local claimOk, claimResult = self:_safeCall("DataStore.ClaimLeaderFence", function()
			return self.store:UpdateAsync(SNAPSHOT_KEY, function(old)
				local state = sanitizeSnapshot(old)
				state.leaderGeneration += 1
				state.leaderJobId = self.jobId
				state.leaderToken = proposedToken
				state.revision += 1
				state.updatedAt = os.time()
				return state
			end)
		end)
		if not claimOk or typeof(claimResult) ~= "table" then
			self.lastError = tostring(claimResult)
			return false, nil, "Could not claim playback fencing generation: " .. tostring(claimResult)
		end
		claimed = claimResult
	end
	local currentOk, currentLease = self:GetLeader()
	if not currentOk or not currentLease or currentLease.jobId ~= self.jobId or currentLease.token ~= proposedToken then
		self.leaseToken = nil
		self.leaseExpiresAt = 0
		self.leaderGeneration = nil
		return false, currentLease, "Leadership lease changed during fencing claim."
	end
	self.leaderGeneration = math.floor(claimed.leaderGeneration or 0)
	self.leadershipReady = self.leaderGeneration > 0
	self.lastError = nil
	return self.leadershipReady, {jobId = self.jobId, token = proposedToken, generation = self.leaderGeneration, expiresAt = value.expiresAt}, if self.leadershipReady then nil else "Fencing generation was not established."
end

function PlaybackAuthority:ReleaseLeadership(): boolean
	local token = self.leaseToken
	if not token or not self.leaseMap then return true end
	local ok = self:_safeCall("MemoryStore.ReleaseLeadership", function()
		self.leaseMap:UpdateAsync(LEASE_KEY, function(old)
			if typeof(old) == "table" and old.jobId == self.jobId and old.token == token then return nil end
			return old
		end, LEASE_TTL)
	end)
	if ok then self.leaseToken = nil; self.leaseExpiresAt = 0; self.leaderGeneration = nil; self.leadershipReady = false end
	return ok
end

function PlaybackAuthority:GetSnapshot(): (boolean, {[string]: any}?, string?)
	if not self.started or not self.store then return false, nil, "Playback authority is not started." end
	if not allowStoreOperation(self) then return false, nil, "Per-server DataStore operation budget unavailable." end
	local ok, raw = self:_safeCall("DataStore.GetPlaybackSnapshot", function() return self.store:GetAsync(SNAPSHOT_KEY) end)
	if not ok then return false, nil, tostring(raw) end
	return true, sanitizeSnapshot(raw), nil
end

function PlaybackAuthority:CommitPlayback(raw: any, expectedRevision: any): (boolean, {[string]: any}?, string?)
	if not self.leaseToken or not self.leadershipReady or not self.leaderGeneration then return false, nil, "This server has no active fenced playback leadership." end
	if not finite(expectedRevision) or expectedRevision < 0 then return false, nil, "Invalid playback revision." end
	if typeof(raw) ~= "table" then return false, nil, "Invalid playback snapshot." end
	local track = sanitizeTrack(raw.current)
	if raw.current ~= nil and not track then return false, nil, "Invalid current track metadata." end
	if typeof(raw.paused) ~= "boolean" or not finite(raw.position) or raw.position < 0 or raw.position > MAX_DURATION then
		return false, nil, "Invalid playback position or pause state."
	end
	local leaseOk, lease = self:GetLeader()
	if not leaseOk or not lease or lease.jobId ~= self.jobId or lease.token ~= self.leaseToken then
		self.leaseToken = nil
		self.leaseExpiresAt = 0
		return false, nil, "Playback leader lease expired or was replaced."
	end
	local token = self.leaseToken
	if not allowStoreOperation(self) then return false, nil, "Per-server DataStore operation budget unavailable." end
	local accepted = false
	local ok, result = self:_safeCall("DataStore.CommitPlayback", function()
		return self.store:UpdateAsync(SNAPSHOT_KEY, function(old)
			accepted = false
			local state = sanitizeSnapshot(old)
			if state.revision ~= math.floor(expectedRevision) then return old end
			if state.leaderGeneration ~= self.leaderGeneration or state.leaderToken ~= token or state.leaderJobId ~= self.jobId then return old end
			-- The durable generation/token check fences every prior leader after takeover.
			state.revision += 1
			state.trackRevision = if finite(raw.trackRevision) then math.max(state.trackRevision, math.floor(raw.trackRevision)) else state.trackRevision
			state.current = track
			state.paused = raw.paused
			state.position = math.clamp(raw.position, 0, MAX_DURATION)
			state.anchorTime = if finite(raw.anchorTime) then raw.anchorTime else Workspace:GetServerTimeNow()
			state.leaderJobId = self.jobId
			state.leaderToken = token
			state.updatedAt = os.time()
			accepted = true
			return state
		end)
	end)
	if not ok then return false, nil, tostring(result) end
	local snapshot = sanitizeSnapshot(result)
	if not accepted then return false, snapshot, "Playback revision changed or this leader was fenced out." end
	if typeof(self.publish) == "function" then self:_safeCall("Messaging.PublishPlaybackChanged", self.publish, {kind = "PlaybackChanged", revision = snapshot.revision, trackRevision = snapshot.trackRevision}) end
	return true, snapshot, nil
end

function PlaybackAuthority:GetStatus(): {[string]: any}
	local leaderOk, leader, leaderError = self:GetLeader()
	return {
		enabled = self.started,
		isLeader = self.leadershipReady == true and self.leaseToken ~= nil and leaderOk and leader ~= nil and leader.jobId == self.jobId and leader.token == self.leaseToken,
		leadershipReady = self.leadershipReady == true,
		leaderGeneration = self.leaderGeneration,
		lastError = self.lastError,
		leaderJobId = if leader then leader.jobId else nil,
		leaseExpiresAt = if leader then leader.expiresAt else nil,
		error = leaderError,
	}
end

return PlaybackAuthority
