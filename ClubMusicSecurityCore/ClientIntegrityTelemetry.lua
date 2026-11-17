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
local MAX_COUNTER = 1000000000

local ALLOWED_SIGNALS: {[string]: boolean} = {
	client_integrity_ui_network_missing = true,
	client_integrity_ui_renderer_missing = true,
	client_integrity_remote_folder_missing = true,
	client_integrity_request_remote_missing = true,
	client_integrity_state_remote_missing = true,
	client_integrity_notice_remote_missing = true,
	client_integrity_state_function_missing = true,
	client_integrity_probe_completed = true,
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
		subjects = {},
		acceptedReports = 0,
		rejectedReports = 0,
		duplicateReports = 0,
		throttledReports = 0,
		replayFailures = 0,
		lastReportAt = 0,
	}, Service)
end

function Service:_report(player: Player, signal: any)
	if not self.started or player.Parent ~= Players then return end
	if typeof(signal) ~= "string" or not ALLOWED_SIGNALS[signal] then
		self.rejectedReports = increment(self.rejectedReports)
		return
	end

	local key = tostring(player.UserId)
	local subject = self.subjects[key]
	if not subject then
		local count = 0
		for _ in pairs(self.subjects) do count += 1 end
		if count >= MAX_TRACKED_PLAYERS then
			self.rejectedReports = increment(self.rejectedReports)
			return
		end
		subject = {seen = {}, count = 0, lastAt = 0}
		self.subjects[key] = subject
	end

	if subject.seen[signal] then
		self.duplicateReports = increment(self.duplicateReports)
		return
	end
	local now = os.clock()
	if subject.lastAt > 0 and now - subject.lastAt < MIN_REPORT_INTERVAL then
		self.throttledReports = increment(self.throttledReports)
		return
	end
	if subject.count >= MAX_REPORTS_PER_PLAYER then
		self.rejectedReports = increment(self.rejectedReports)
		return
	end

	subject.seen[signal] = true
	subject.count += 1
	subject.lastAt = now
	self.lastReportAt = now
	self.acceptedReports = increment(self.acceptedReports)

	-- Store only the allowlisted signal code and server-derived Player.UserId.
	-- No client arguments, text, stack traces, paths, or device details are accepted.
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
	local remote = existing
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = ReplicatedStorage
		self.ownsRemote = true
	end
	self.remote = remote
	self.connection = remote.OnServerEvent:Connect(function(player, signal)
		self:_report(player, signal)
	end)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		self.subjects[tostring(player.UserId)] = nil
	end)
	self.started = true
	return true
end

function Service:GetStatus()
	local tracked = 0
	for _ in pairs(self.subjects) do tracked += 1 end
	return {
		state = if self.started then "Observing" else "Stopped",
		scope = "ServerLocal",
		clientReportsUntrusted = true,
		affectsAuthorization = false,
		automaticEnforcement = false,
		acceptedReports = self.acceptedReports,
		rejectedReports = self.rejectedReports,
		duplicateReports = self.duplicateReports,
		throttledReports = self.throttledReports,
		replayFailures = self.replayFailures,
		trackedPlayers = tracked,
		maxTrackedPlayers = MAX_TRACKED_PLAYERS,
		maxReportsPerPlayer = MAX_REPORTS_PER_PLAYER,
		lastReportAgeSeconds = if self.lastReportAt > 0 then math.max(0, os.clock() - self.lastReportAt) else nil,
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
