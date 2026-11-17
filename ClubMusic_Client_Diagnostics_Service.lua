--!strict
-- Opt-in client-local telemetry for FPS, frame spikes, memory, and ping.
-- Measurements are untrusted client observations. This module sends nothing
-- to the server and never reads or exposes server-side errors or private state.

local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Service = {}
Service.__index = Service

local SAMPLE_WINDOW_SECONDS = 60
local MEMORY_SAMPLE_SECONDS = 15
local PING_SAMPLE_SECONDS = 5
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
