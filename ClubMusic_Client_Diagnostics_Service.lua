--!strict
-- Opt-in client-local telemetry for FPS, frame spikes, memory, and ping.
-- Measurements are untrusted client observations. This module sends nothing
-- to the server and never reads or exposes server-side errors or private state.

local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local SoundService = game:GetService("SoundService")

local Service = {}
Service.__index = Service

local SAMPLE_WINDOW_SECONDS = 60
local MEMORY_SAMPLE_SECONDS = 15
local PING_SAMPLE_SECONDS = 5
local AUDIO_SAMPLE_SECONDS = 10
local SLOW_FRAME_SECONDS = 0.05
local SEVERE_FRAME_SECONDS = 0.1
local MAX_BUCKETS = 64
local MEMORY_STALE_SECONDS = 45
local PING_STALE_SECONDS = 15

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

function Service.new()
	assert(RunService:IsClient(), "ClientDiagnostics can only run on a client.")
	return setmetatable({
		running = false,
		connection = nil,
		samplerThread = nil,
		buckets = {},
		lastBucketSecond = -1,
		memoryMb = nil,
		memorySampleAt = nil,
		memoryError = nil,
		pingMs = nil,
		pingSampleAt = nil,
		pingError = nil,
		audioSnapshot = {state = "Starting", playing = false, timePositionSeconds = nil, sourceCount = 0},
		audioSampleAt = nil,
		audioError = nil,
		startedAt = 0,
	}, Service)
end

function Service:_recordFrame(deltaTime: number)
	if not finite(deltaTime) then return end
	local now = os.clock()
	local second = math.floor(now)
	local bucket = self.buckets[second]
	if not bucket then
		bucket = {frames = 0, totalDelta = 0, maxDelta = 0, slowFrames = 0, severeFrames = 0}
		self.buckets[second] = bucket
	end
	bucket.frames += 1
	bucket.totalDelta += deltaTime
	bucket.maxDelta = math.max(bucket.maxDelta, deltaTime)
	if deltaTime >= SLOW_FRAME_SECONDS then bucket.slowFrames += 1 end
	if deltaTime >= SEVERE_FRAME_SECONDS then bucket.severeFrames += 1 end

	if self.lastBucketSecond ~= second then
		self.lastBucketSecond = second
		local count = 0
		for key in pairs(self.buckets) do
			if now - key > SAMPLE_WINDOW_SECONDS then
				self.buckets[key] = nil
			else
				count += 1
			end
		end
		if count > MAX_BUCKETS then
			local oldestKey, oldestAt = nil, math.huge
			for key in pairs(self.buckets) do
				if key < oldestAt then oldestKey, oldestAt = key, key end
			end
			if oldestKey then self.buckets[oldestKey] = nil end
		end
	end
end

function Service:_sampleMemory()
	local ok, value = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	if ok and finite(value) then
		self.memoryMb = value
		self.memorySampleAt = os.time()
		self.memoryError = nil
	else
		self.memoryError = string.sub(tostring(value or "Client memory statistics unavailable."), 1, 160)
	end
end

function Service:_samplePing()
	local ok, value = pcall(function()
		local network = Stats:FindFirstChild("Network")
		local serverStats = network and network:FindFirstChild("ServerStatsItem")
		local dataPing = serverStats and serverStats:FindFirstChild("Data Ping")
		if not dataPing then error("Data Ping statistic is unavailable.") end
		return dataPing:GetValue()
	end)
	if ok and finite(value) then
		self.pingMs = value
		self.pingSampleAt = os.time()
		self.pingError = nil
	else
		self.pingError = string.sub(tostring(value or "Client ping statistics unavailable."), 1, 160)
	end
end

-- Observe only the replicated, controller-owned modern AudioPlayer graph.
-- AudioPlayer has no Sound.PlaybackLoudness property; do not invent a loudness
-- value or add an AudioAnalyzer graph solely for diagnostics.
function Service:_sampleAudio()
	local selectedPlayer = nil
	local playingPlayer = nil
	local sourceCount = 0
	local readErrors = 0

	local ok, result = pcall(function()
		for _, root in ipairs(SoundService:GetChildren()) do
			if root:GetAttribute("ManagedByClubMusicAudioBackend") == true then
				local player = root:FindFirstChild("AudioPlayer")
				if player and player:IsA("AudioPlayer") then
					sourceCount += 1
					local stateOk, isPlaying = pcall(function() return player.IsPlaying end)
					if not stateOk then
						readErrors += 1
					elseif isPlaying == true then
						playingPlayer = player
					elseif not selectedPlayer then
						selectedPlayer = player
					end
				end
			end
		end
	end)

	if not ok then
		self.audioError = string.sub(tostring(result), 1, 160)
		self.audioSnapshot = {state = "Unavailable", playing = false, timePositionSeconds = nil, sourceCount = 0}
		self.audioSampleAt = os.time()
		return
	end

	local activePlayer = playingPlayer or selectedPlayer
	local position = nil
	if activePlayer then
		local positionOk, value = pcall(function() return activePlayer.TimePosition end)
		if positionOk and finite(value) then
			position = value
		else
			readErrors += 1
		end
	end

	self.audioSnapshot = {
		state = if sourceCount == 0 then "NotFound" elseif readErrors > 0 then "Partial" else "Measured",
		playing = playingPlayer ~= nil,
		timePositionSeconds = position,
		sourceCount = sourceCount,
		sourceType = if activePlayer then "ModernAudioPlayer" else nil,
		loudness = nil,
		loudnessState = "Unsupported: AudioPlayer does not expose Sound.PlaybackLoudness",
	}
	self.audioError = if readErrors > 0 then "One or more AudioPlayer properties could not be read." else nil
	self.audioSampleAt = os.time()

	if playingPlayer then
		print(string.format(
			"[ClubMusic][ClientAudioDiagnostics] Source: Modern AudioPlayer | Time: %s s | Client Ping: %s ms | Loudness: unsupported",
			if position then string.format("%.2f", position) else "n/a",
			if self.pingMs then tostring(math.floor(self.pingMs + 0.5)) else "n/a"
		))
	end
end

function Service:Start(): boolean
	if self.running then return false end
	self.running = true
	self.startedAt = os.clock()
	self.connection = RunService.RenderStepped:Connect(function(deltaTime)
		self:_recordFrame(deltaTime)
	end)
	self.samplerThread = task.spawn(function()
		local nextMemory = 0
		local nextPing = 0
		local nextAudio = 0
		while self.running do
			local now = os.clock()
			if now >= nextMemory then
				self:_sampleMemory()
				nextMemory = now + MEMORY_SAMPLE_SECONDS
			end
			if now >= nextPing then
				self:_samplePing()
				nextPing = now + PING_SAMPLE_SECONDS
			end
			if now >= nextAudio then
				self:_sampleAudio()
				nextAudio = now + AUDIO_SAMPLE_SECONDS
			end
			task.wait(1)
		end
	end)
	return true
end

function Service:GetStatus(): {[string]: any}
	if not self.running then
		return {state = "Disabled", scope = "ClientLocalUntrusted", enabled = false, transmitted = false}
	end
	local now = os.clock()
	local frames, totalDelta, maxDelta, slow, severe = 0, 0, 0, 0, 0
	for second, bucket in pairs(self.buckets) do
		if now - second <= SAMPLE_WINDOW_SECONDS then
			frames += bucket.frames
			totalDelta += bucket.totalDelta
			maxDelta = math.max(maxDelta, bucket.maxDelta)
			slow += bucket.slowFrames
			severe += bucket.severeFrames
		end
	end
	local averageDelta = if frames > 0 then totalDelta / frames else nil
	local fps = if averageDelta and averageDelta > 0 then 1 / averageDelta else nil
	local memoryAge = if self.memorySampleAt then math.max(0, os.time() - self.memorySampleAt) else nil
	local pingAge = if self.pingSampleAt then math.max(0, os.time() - self.pingSampleAt) else nil
	local audioAge = if self.audioSampleAt then math.max(0, os.time() - self.audioSampleAt) else nil
	return {
		state = if frames > 0 then "Available" else "Starting",
		scope = "ClientLocalUntrusted",
		enabled = true,
		transmitted = false,
		untrusted = true,
		windowSeconds = SAMPLE_WINDOW_SECONDS,
		fps = fps,
		averageFrameMs = if averageDelta then averageDelta * 1000 else nil,
		maxFrameMs = if frames > 0 then maxDelta * 1000 else nil,
		slowFrameCount = slow,
		severeFrameCount = severe,
		memory = {
			state = if self.memoryError then "Unavailable" elseif memoryAge and memoryAge > MEMORY_STALE_SECONDS then "Stale"
				elseif self.memoryMb ~= nil then "Measured" else "Starting",
				usageMb = self.memoryMb,
			sampledAt = self.memorySampleAt,
			ageSeconds = memoryAge,
			staleAfterSeconds = MEMORY_STALE_SECONDS,
			lastError = self.memoryError,
		},
		audio = {
			state = if self.audioError then "Partial" else self.audioSnapshot.state,
			playing = self.audioSnapshot.playing,
			timePositionSeconds = self.audioSnapshot.timePositionSeconds,
			sourceCount = self.audioSnapshot.sourceCount,
			sourceType = self.audioSnapshot.sourceType,
			loudness = self.audioSnapshot.loudness,
			loudnessState = self.audioSnapshot.loudnessState,
			sampledAt = self.audioSampleAt,
			ageSeconds = audioAge,
			sampleIntervalSeconds = AUDIO_SAMPLE_SECONDS,
			lastError = self.audioError,
		},
		ping = {
			state = if self.pingError then "Unavailable" elseif pingAge and pingAge > PING_STALE_SECONDS then "Stale"
				elseif self.pingMs ~= nil then "Measured" else "Starting",
			milliseconds = self.pingMs,
			sampledAt = self.pingSampleAt,
			ageSeconds = pingAge,
			staleAfterSeconds = PING_STALE_SECONDS,
			lastError = self.pingError,
		},
		uptimeSeconds = math.max(0, now - self.startedAt),
		updatedAt = os.time(),
	}
end

function Service:Stop()
	self.running = false
	if self.connection then
		pcall(function() self.connection:Disconnect() end)
		self.connection = nil
	end
	if self.samplerThread then
		pcall(task.cancel, self.samplerThread)
		self.samplerThread = nil
	end
end

return Service
