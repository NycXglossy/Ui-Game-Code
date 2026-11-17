--!strict
-- Server-local runtime health observations for ClubMusic.
-- This module never performs recovery, enforcement, or cross-server communication.

local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Service = {}
Service.__index = Service

local SAMPLE_WINDOW_SECONDS = 60
local MEMORY_SAMPLE_SECONDS = 30
local SLOW_FRAME_SECONDS = 0.05
local SEVERE_FRAME_SECONDS = 0.1
local SLOW_FRAME_LIMIT = 8
local DEFAULT_MEMORY_WARNING_MB = 0 -- 0 disables an arbitrary hard memory threshold
local MAX_MEMORY_SAMPLES = 20
local MEMORY_STALE_SECONDS = 90

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

function Service.new(options: {[string]: any}?)
	options = if typeof(options) == "table" then options else {}
	local memoryWarningMb = if finite(options.memoryWarningMb) then options.memoryWarningMb else DEFAULT_MEMORY_WARNING_MB
	return setmetatable({
		memoryWarningMb = memoryWarningMb,
		running = false,
		connection = nil,
		memoryThread = nil,
		frameBuckets = {},
		lastPruneSecond = -1,
		lastFrameAt = 0,
		memoryMb = nil,
		memorySampleAt = nil,
		memoryError = nil,
		memorySamples = {},
		lastMemoryAttemptAt = nil,
		startedAt = 0,
		lastWarningSignature = "",
	}, Service)
end

function Service:_recordFrame(deltaTime: number)
	local now = os.clock()
	self.lastFrameAt = now
	local second = math.floor(now)
	local bucket = self.frameBuckets[second]
	if not bucket then
		bucket = {count = 0, total = 0, max = 0, slow = 0, severe = 0}
		self.frameBuckets[second] = bucket
	end
	bucket.count += 1
	bucket.total += deltaTime
	bucket.max = math.max(bucket.max, deltaTime)
	if deltaTime >= SLOW_FRAME_SECONDS then bucket.slow += 1 end
	if deltaTime >= SEVERE_FRAME_SECONDS then bucket.severe += 1 end
	if self.lastPruneSecond ~= second then
		self.lastPruneSecond = second
		for key in pairs(self.frameBuckets) do
			if now - key > SAMPLE_WINDOW_SECONDS then self.frameBuckets[key] = nil end
		end
	end
end

function Service:_sampleMemory()
	self.lastMemoryAttemptAt = os.time()
	local ok, value = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	if ok and finite(value) then
		self.memoryMb = value
		self.memorySampleAt = os.time()
		self.memoryError = nil
		table.insert(self.memorySamples, {at = self.memorySampleAt, usageMb = value})
		while #self.memorySamples > MAX_MEMORY_SAMPLES do table.remove(self.memorySamples, 1) end
	else
		self.memoryError = string.sub(tostring(value or "Memory statistics unavailable."), 1, 180)
	end
end

function Service:Start(): boolean
	if self.running then return false end
	self.running = true
	self.startedAt = os.clock()
	self.connection = RunService.Heartbeat:Connect(function(deltaTime)
		if finite(deltaTime) then self:_recordFrame(deltaTime) end
	end)
	self.memoryThread = task.spawn(function()
		while self.running do
			self:_sampleMemory()
			task.wait(MEMORY_SAMPLE_SECONDS)
		end
	end)
	return true
end

function Service:GetStatus(): {[string]: any}
	local now = os.clock()
	local frameCount = 0
	local frameTotal = 0
	local frameMax = 0
	local slow = 0
	local severe = 0
	for second, bucket in pairs(self.frameBuckets) do
		if now - second <= SAMPLE_WINDOW_SECONDS then
			frameCount += bucket.count
			frameTotal += bucket.total
			frameMax = math.max(frameMax, bucket.max)
			slow += bucket.slow
			severe += bucket.severe
		end
	end
	local average = if frameCount > 0 then frameTotal / frameCount else nil
	local memoryAge = if self.memorySampleAt then math.max(0, os.time() - self.memorySampleAt) else nil
	local memoryWarning = self.memoryWarningMb > 0 and self.memoryMb ~= nil and self.memoryMb >= self.memoryWarningMb
	local memoryTotal, memoryMin, memoryMax = 0, math.huge, 0
	for _, sample in ipairs(self.memorySamples) do
		memoryTotal += sample.usageMb
		memoryMin = math.min(memoryMin, sample.usageMb)
		memoryMax = math.max(memoryMax, sample.usageMb)
	end
	local memoryCount = #self.memorySamples
	local firstMemory = self.memorySamples[1]
	local lastMemory = self.memorySamples[memoryCount]
	local memoryTrend = if memoryCount >= 2 and firstMemory and lastMemory
		then lastMemory.usageMb - firstMemory.usageMb else nil
	local memoryStale = memoryAge ~= nil and memoryAge > MEMORY_STALE_SECONDS
	local frameDegraded = severe >= SLOW_FRAME_LIMIT
	local state = if frameDegraded or memoryWarning then "Degraded"
		elseif frameCount == 0 then "Starting" else "Healthy"
	local issues = {}
	if frameDegraded then table.insert(issues, "Repeated severe server Heartbeat delays detected.") end
	if memoryWarning then table.insert(issues, "Server memory exceeded the configured warning threshold.") end
	return {
		state = state,
		scope = "ServerLocal",
		observationalOnly = true,
		detail = if #issues > 0 then table.concat(issues, " ") else "Server runtime observations are within configured thresholds.",
		heartbeat = {
			sampleCount = frameCount,
			averageDeltaSeconds = average,
			maxDeltaSeconds = frameMax,
			slowFrameCount = slow,
			severeFrameCount = severe,
			windowSeconds = SAMPLE_WINDOW_SECONDS,
		},
		memory = {
			state = if self.memoryError then "Unavailable" elseif memoryStale then "Stale"
				elseif self.memoryMb ~= nil then "Measured" else "Starting",
				usageMb = self.memoryMb,
				sampledAt = self.memorySampleAt,
				lastAttemptAt = self.lastMemoryAttemptAt,
				ageSeconds = memoryAge,
				sampleCount = memoryCount,
				maxSamples = MAX_MEMORY_SAMPLES,
				averageMb = if memoryCount > 0 then memoryTotal / memoryCount else nil,
				minimumMb = if memoryCount > 0 then memoryMin else nil,
				maximumMb = if memoryCount > 0 then memoryMax else nil,
				changeSinceOldestSampleMb = memoryTrend,
				staleAfterSeconds = MEMORY_STALE_SECONDS,
				warningThresholdMb = if self.memoryWarningMb > 0 then self.memoryWarningMb else nil,
				lastError = self.memoryError,
		},
		uptimeSeconds = if self.startedAt > 0 then math.max(0, now - self.startedAt) else 0,
		updatedAt = os.time(),
	}
end

function Service:Stop()
	self.running = false
	if self.connection then
		pcall(function() self.connection:Disconnect() end)
		self.connection = nil
	end
	if self.memoryThread then
		pcall(task.cancel, self.memoryThread)
		self.memoryThread = nil
	end
end

return Service
