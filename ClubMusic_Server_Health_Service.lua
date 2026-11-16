--!strict
-- Server-local runtime health observations for ClubMusic.
-- This module never performs recovery, enforcement, or cross-server communication.

local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Service = {}
Service.__index = Service

local SAMPLE_WINDOW_SECONDS = 60
local MEMORY_SAMPLE_SECONDS = 30
local MAX_FRAME_SAMPLES = 240
local SLOW_FRAME_SECONDS = 0.05
local SEVERE_FRAME_SECONDS = 0.1
local SLOW_FRAME_LIMIT = 8
local DEFAULT_MEMORY_WARNING_MB = 0 -- 0 disables an arbitrary hard memory threshold

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
		frames = {},
		frameTotal = 0,
		slowFrames = 0,
		severeFrames = 0,
		maxFrameSeconds = 0,
		lastFrameAt = 0,
		memoryMb = nil,
		memorySampleAt = nil,
		memoryError = nil,
		startedAt = 0,
		lastWarningSignature = "",
	}, Service)
end

function Service:_recordFrame(deltaTime: number)
	local now = os.clock()
	self.lastFrameAt = now
	self.frameTotal += deltaTime
	self.maxFrameSeconds = math.max(self.maxFrameSeconds, deltaTime)
	if deltaTime >= SLOW_FRAME_SECONDS then self.slowFrames += 1 end
	if deltaTime >= SEVERE_FRAME_SECONDS then self.severeFrames += 1 end
	table.insert(self.frames, {at = now, delta = deltaTime})
	if #self.frames > MAX_FRAME_SAMPLES then table.remove(self.frames, 1) end
	while #self.frames > 0 and now - self.frames[1].at > SAMPLE_WINDOW_SECONDS do
		table.remove(self.frames, 1)
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
	for _, sample in ipairs(self.frames) do
		if now - sample.at <= SAMPLE_WINDOW_SECONDS then
			frameCount += 1
			frameTotal += sample.delta
			frameMax = math.max(frameMax, sample.delta)
			if sample.delta >= SLOW_FRAME_SECONDS then slow += 1 end
			if sample.delta >= SEVERE_FRAME_SECONDS then severe += 1 end
		end
	end
	local average = if frameCount > 0 then frameTotal / frameCount else nil
	local memoryAge = if self.memorySampleAt then math.max(0, os.time() - self.memorySampleAt) else nil
	local memoryWarning = self.memoryWarningMb > 0 and self.memoryMb ~= nil and self.memoryMb >= self.memoryWarningMb
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
			state = if self.memoryError then "Unavailable" elseif self.memoryMb then "Measured" else "Starting",
			usageMb = self.memoryMb,
			sampledAt = self.memorySampleAt,
			ageSeconds = memoryAge,
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
