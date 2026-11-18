--!strict
-- Server-side receiver for fixed, untrusted client-integrity observations.
-- Client reports are review telemetry only; they never affect authorization or enforcement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Service = {}
Service.__index = Service

local REMOTE_NAME = "TikiTideClientIntegrityTelemetry_v1"
local MAX_TRACKED_PLAYERS = 200
local MAX_REPORTS_PER_PLAYER = 8
local MIN_REPORT_INTERVAL = 1
local HEARTBEAT_MIN_INTERVAL = 20
local HEARTBEAT_STALE_AFTER = 120
local MOVEMENT_MIN_INTERVAL = 30
local MAX_MOVEMENT_REPORTS_PER_PLAYER = 10
local MAX_COUNTER = 1000000000

local HEARTBEAT_SIGNAL = "client_integrity_observer_heartbeat"
local MOVEMENT_SIGNAL = "client_walkspeed_observed_change"

local ALLOWED_SIGNALS: {[string]: boolean} = {
	client_integrity_ui_network_missing = true,
	client_integrity_ui_renderer_missing = true,
	client_integrity_remote_folder_missing = true,
	client_integrity_request_remote_missing = true,
	client_integrity_state_remote_missing = true,
	client_integrity_notice_remote_missing = true,
	client_integrity_state_function_missing = true,
	client_integrity_probe_completed = true,
	[HEARTBEAT_SIGNAL] = true,
	[MOVEMENT_SIGNAL] = true,
}

local function increment(value: number): number
	return math.min(MAX_COUNTER, value + 1)
end

function Service.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table" and type(dependencies.recordReplay) == "function",
		"ClientIntegrityTelemetry requires a replay recorder")
	return setmetatable({
		d = dependencies,
		started = false,
		remote = nil,
		ownsRemote = false,
		connection = nil,
		playerRemovingConnection = nil,
		subjects = {},
		acceptedReports = 0,
		rejectedReports = 0,
		duplicateReports = 0,
		throttledReports = 0,
		replayFailures = 0,
		heartbeatsReceived = 0,
		heartbeatsThrottled = 0,
		movementObservations = 0,
		movementThrottled = 0,
		lastReportAt = 0,
		lastHeartbeatAt = 0,
	}, Service)
end

function Service:_getSubject(player: Player)
	local key = tostring(player.UserId)
	local subject = self.subjects[key]
	if subject then return subject end

	local count = 0
	for _ in pairs(self.subjects) do count += 1 end
	if count >= MAX_TRACKED_PLAYERS then
		self.rejectedReports = increment(self.rejectedReports)
		return nil
	end

	subject = {
		seen = {},
		count = 0,
		lastAt = 0,
		lastHeartbeatAt = 0,
		lastMovementAt = 0,
		movementCount = 0,
	}
	self.subjects[key] = subject
	return subject
end

function Service:_rejectExtraArguments(player: Player)
	if player.Parent == Players then
		self.rejectedReports = increment(self.rejectedReports)
	end
end

function Service:_report(player: Player, signal: any, ...)
	if not self.started or player.Parent ~= Players then return end
	if select("#", ...) > 0 then
		self:_rejectExtraArguments(player)
		return
	end

	if typeof(signal) ~= "string" or #signal > 48 or not ALLOWED_SIGNALS[signal] then
		self.rejectedReports = increment(self.rejectedReports)
		return
	end

	local subject = self:_getSubject(player)
	if not subject then return end
	local now = os.clock()

	-- Heartbeats have their own liveness clock and quota. They do not consume
	-- the unique dependency-report allowance or create replay-history noise.
	if signal == HEARTBEAT_SIGNAL then
		if subject.lastHeartbeatAt > 0 and now - subject.lastHeartbeatAt < HEARTBEAT_MIN_INTERVAL then
			self.heartbeatsThrottled = increment(self.heartbeatsThrottled)
			return
		end
		subject.lastHeartbeatAt = now
		self.lastHeartbeatAt = now
		self.heartbeatsReceived = increment(self.heartbeatsReceived)
		return
	end

	-- Movement observations are independently rate-limited and capped. They
	-- remain a client-local observation, never a server movement verdict.
	if signal == MOVEMENT_SIGNAL then
		if subject.lastMovementAt > 0 and now - subject.lastMovementAt < MOVEMENT_MIN_INTERVAL then
			self.movementThrottled = increment(self.movementThrottled)
			return
		end
		if subject.movementCount >= MAX_MOVEMENT_REPORTS_PER_PLAYER then
			self.rejectedReports = increment(self.rejectedReports)
			return
		end
		subject.lastMovementAt = now
		subject.movementCount += 1
		self.movementObservations = increment(self.movementObservations)
	else
		-- Throttle every dependency-report attempt, including duplicates.
		if subject.lastAt > 0 and now - subject.lastAt < MIN_REPORT_INTERVAL then
			self.throttledReports = increment(self.throttledReports)
			return
		end
		subject.lastAt = now
		if subject.seen[signal] then
			self.duplicateReports = increment(self.duplicateReports)
			return
		end
		if subject.count >= MAX_REPORTS_PER_PLAYER then
			self.rejectedReports = increment(self.rejectedReports)
			return
		end
		subject.seen[signal] = true
		subject.count += 1
	end

	self.lastReportAt = now
	self.acceptedReports = increment(self.acceptedReports)

	-- Store only the allowlisted signal code and server-derived Player.UserId.
	-- No client arguments, values, timestamps, text, paths, or device details.
	local ok, recorded = pcall(self.d.recordReplay, signal, player.UserId)
	if not ok or recorded ~= true then self.replayFailures = increment(self.replayFailures) end
end

function Service:Start(): boolean
	if self.started then return true end
	local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	if existing and not existing:IsA("RemoteEvent") then
		warn("[Tiki Tide][ClientIntegrity] Telemetry remote name is occupied by a different class.")
		return false
	end
	local remote: RemoteEvent
	if existing then
		remote = existing :: RemoteEvent
	else
		local created = Instance.new("RemoteEvent")
		created.Name = REMOTE_NAME
		created.Parent = ReplicatedStorage
		remote = created
		self.ownsRemote = true
	end
	self.remote = remote
	self.connection = remote.OnServerEvent:Connect(function(player, signal, ...)
		self:_report(player, signal, ...)
	end)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		self.subjects[tostring(player.UserId)] = nil
	end)
	self.started = true
	return true
end

function Service:GetStatus()
	local tracked = 0
	local heartbeatTracked = 0
	local heartbeatFresh = 0
	local now = os.clock()
	for _, subject in pairs(self.subjects) do
		tracked += 1
		if subject.lastHeartbeatAt > 0 then
			heartbeatTracked += 1
			if now - subject.lastHeartbeatAt <= HEARTBEAT_STALE_AFTER then
				heartbeatFresh += 1
			end
		end
	end
	return {
		state = if self.started then "Observing" else "Stopped",
		scope = "ServerLocal",
		clientReportsUntrusted = true,
		clientReportsTransmitted = true,
		telemetryKind = "DependencyPresenceMovementObservationAndLiveness",
		affectsAuthorization = false,
		automaticEnforcement = false,
		acceptedReports = self.acceptedReports,
		rejectedReports = self.rejectedReports,
		duplicateReports = self.duplicateReports,
		throttledReports = self.throttledReports,
		replayFailures = self.replayFailures,
		movementObservations = self.movementObservations,
		movementThrottled = self.movementThrottled,
		heartbeatsReceived = self.heartbeatsReceived,
		heartbeatsThrottled = self.heartbeatsThrottled,
		heartbeatTrackedPlayers = heartbeatTracked,
		heartbeatFreshPlayers = heartbeatFresh,
		heartbeatStaleAfterSeconds = HEARTBEAT_STALE_AFTER,
		heartbeatMinimumIntervalSeconds = HEARTBEAT_MIN_INTERVAL,
		movementMinimumIntervalSeconds = MOVEMENT_MIN_INTERVAL,
		maxMovementReportsPerPlayer = MAX_MOVEMENT_REPORTS_PER_PLAYER,
		trackedPlayers = tracked,
		maxTrackedPlayers = MAX_TRACKED_PLAYERS,
		maxReportsPerPlayer = MAX_REPORTS_PER_PLAYER,
		lastReportAgeSeconds = if self.lastReportAt > 0 then math.max(0, now - self.lastReportAt) else nil,
		lastHeartbeatAgeSeconds = if self.lastHeartbeatAt > 0 then math.max(0, now - self.lastHeartbeatAt) else nil,
		remoteName = REMOTE_NAME,
	}
end

function Service:Stop()
	self.started = false
	if self.connection then self.connection:Disconnect(); self.connection = nil end
	if self.playerRemovingConnection then self.playerRemovingConnection:Disconnect(); self.playerRemovingConnection = nil end
	if self.ownsRemote and self.remote and self.remote.Parent == ReplicatedStorage then self.remote:Destroy() end
	self.remote = nil
	self.ownsRemote = false
	table.clear(self.subjects)
end

return Service
