--!strict
-- Adaptive, server-local workload budgets for optional security operations.
-- Essential validation, authorization, rate limiting, receipt processing,
-- moderation, and security-event recording are never throttled by this module.
-- No storage, remotes, task loops, or automatic enforcement are created.

local RunService = game:GetService("RunService")

local Service = {}
Service.__index = Service

local SAMPLE_WINDOW_SECONDS = 5
local MAX_FRAME_DELTA = 2
local TASK_POLICIES = {
	DiagnosticsSampling = {
		Normal = {rate = 2, burst = 4},
		Reduced = {rate = 0.5, burst = 1},
		Critical = {rate = 0, burst = 0},
	},
	ReplayQueries = {
		Normal = {rate = 0.5, burst = 2},
		Reduced = {rate = 0.1, burst = 1},
		Critical = {rate = 0, burst = 0},
	},
	ThreatReviewQueries = {
		Normal = {rate = 0.5, burst = 2},
		Reduced = {rate = 0.1, burst = 1},
		Critical = {rate = 0, burst = 0},
	},
	AnalyticsAggregation = {
		Normal = {rate = 2, burst = 4},
		Reduced = {rate = 0.5, burst = 1},
		Critical = {rate = 0, burst = 0},
	},
	BackgroundMaintenance = {
		Normal = {rate = 0.1, burst = 1},
		Reduced = {rate = 0.02, burst = 1},
		Critical = {rate = 0, burst = 0},
	},
}
local ESSENTIAL_TASKS = {
	EssentialSecurityValidation = true,
	RemoteAuthorization = true,
	RateLimiting = true,
	PurchaseReceiptProcessing = true,
	ModerationEnforcement = true,
	SecurityEventRecording = true,
}

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

function Service.new(dependencies: {[string]: any}?)
	local d = if typeof(dependencies) == "table" then dependencies else {}
	return setmetatable({
		d = d,
		mode = "Normal",
		started = false,
		connection = nil,
		windowElapsed = 0,
		windowFrames = 0,
		windowDelta = 0,
		windowMaxDelta = 0,
		sampleCount = 0,
		overloadStreak = 0,
		criticalStreak = 0,
		healthyStreak = 0,
		transitions = 0,
		lastAverageDelta = 0,
		lastMaxDelta = 0,
		lastSampleAt = 0,
		lastTransitionAt = 0,
		lastTransitionReason = "Startup default",
		buckets = {},
	}, Service)
end

function Service:_policy(taskName: string)
	local policies = TASK_POLICIES[taskName]
	return policies and policies[self.mode] or nil
end

function Service:_transition(nextMode: string, reason: string)
	if nextMode == self.mode then return end
	local previous = self.mode
	self.mode = nextMode
	self.transitions += 1
	self.lastTransitionAt = os.time()
	self.lastTransitionReason = string.sub(reason, 1, 96)
	for taskName, bucket in pairs(self.buckets) do
		local policy = self:_policy(taskName)
		if policy then bucket.tokens = math.min(bucket.tokens, policy.burst) end
	end
	if type(self.d.onModeChanged) == "function" then
		pcall(self.d.onModeChanged, previous, nextMode, self.lastAverageDelta, self.lastMaxDelta, self.lastTransitionReason)
	end
end

function Service:_evaluate(averageDelta: number, maxDelta: number)
	self.sampleCount += 1
	self.lastAverageDelta = averageDelta
	self.lastMaxDelta = maxDelta
	self.lastSampleAt = os.time()

	local critical = averageDelta >= 0.20 or maxDelta >= 0.75
	local overloaded = averageDelta >= 0.10 or maxDelta >= 0.45
	local healthy = averageDelta <= 0.07 and maxDelta <= 0.25

	self.criticalStreak = if critical then self.criticalStreak + 1 else 0
	self.overloadStreak = if overloaded then self.overloadStreak + 1 else 0
	self.healthyStreak = if healthy then self.healthyStreak + 1 else 0

	if self.criticalStreak >= 2 then
		self:_transition("Critical", "Sustained severe server heartbeat delay")
	elseif self.mode == "Normal" and self.overloadStreak >= 3 then
		self:_transition("Reduced", "Sustained elevated server heartbeat delay")
	elseif self.mode == "Reduced" and self.overloadStreak >= 6 then
		self:_transition("Critical", "Persistent elevated server heartbeat delay")
	elseif self.mode == "Critical" and self.healthyStreak >= 4 then
		self:_transition("Reduced", "Server heartbeat recovered; staged recovery")
		self.healthyStreak = 0
	elseif self.mode == "Reduced" and self.healthyStreak >= 6 then
		self:_transition("Normal", "Server heartbeat stable; normal budgets restored")
	end
end

function Service:_onHeartbeat(deltaTime: number)
	if not self.started or not finite(deltaTime) or deltaTime <= 0 then return end
	local boundedDelta = math.min(deltaTime, MAX_FRAME_DELTA)
	self.windowElapsed += boundedDelta
	self.windowFrames += 1
	self.windowDelta += boundedDelta
	self.windowMaxDelta = math.max(self.windowMaxDelta, boundedDelta)
	if self.windowElapsed < SAMPLE_WINDOW_SECONDS then return end

	local average = if self.windowFrames > 0 then self.windowDelta / self.windowFrames else 0
	local maximum = self.windowMaxDelta
	self.windowElapsed = 0
	self.windowFrames = 0
	self.windowDelta = 0
	self.windowMaxDelta = 0
	self:_evaluate(average, maximum)
end

function Service:TryConsume(taskName: any, amount: any?): boolean
	if typeof(taskName) ~= "string" or #taskName < 1 or #taskName > 40 then return false end
	if ESSENTIAL_TASKS[taskName] then return true end
	local cost = if amount == nil then 1 else amount
	if not finite(cost) or cost <= 0 or cost > 10 then return false end
	local policy = self:_policy(taskName)
	if not policy or policy.rate <= 0 or policy.burst <= 0 then return false end

	local now = os.clock()
	local bucket = self.buckets[taskName]
	if not bucket then
		bucket = {tokens = policy.burst, updatedAt = now}
		self.buckets[taskName] = bucket
	end
	bucket.tokens = math.min(policy.burst, bucket.tokens + math.max(0, now - bucket.updatedAt) * policy.rate)
	bucket.updatedAt = now
	if bucket.tokens < cost then return false end
	bucket.tokens -= cost
	return true
end

function Service:GetBudget(taskName: any)
	if typeof(taskName) ~= "string" then return nil end
	if ESSENTIAL_TASKS[taskName] then
		return {unlimited = true, throttled = false, reason = "Essential security path"}
	end
	local policy = self:_policy(taskName)
	if not policy then return nil end
	return {ratePerSecond = policy.rate, burst = policy.burst, throttled = policy.rate <= 0}
end

function Service:GetStatus()
	local budgets = {}
	for taskName, policies in pairs(TASK_POLICIES) do
		local policy = policies[self.mode]
		local bucket = self.buckets[taskName]
		budgets[taskName] = {
			ratePerSecond = policy.rate,
			burst = policy.burst,
			tokens = if bucket then bucket.tokens else policy.burst,
		}
	end
	return {
		state = if self.started then "Observing" else "Stopped",
		mode = self.mode,
		sampleWindowSeconds = SAMPLE_WINDOW_SECONDS,
		sampleCount = self.sampleCount,
		lastAverageHeartbeatDelta = self.lastAverageDelta,
		lastMaximumHeartbeatDelta = self.lastMaxDelta,
		lastSampleAt = self.lastSampleAt,
		transitions = self.transitions,
		lastTransitionAt = self.lastTransitionAt,
		lastTransitionReason = self.lastTransitionReason,
		overloadStreak = self.overloadStreak,
		criticalStreak = self.criticalStreak,
		healthyStreak = self.healthyStreak,
		budgets = budgets,
		essentialTasksAlwaysAllowed = true,
		securityEventRecordingThrottled = false,
		storageWrites = 0,
		clientRemotes = 0,
		automaticEnforcement = false,
	}
end

function Service:Start(): boolean
	if self.started then return true end
	self.started = true
	self.connection = RunService.Heartbeat:Connect(function(deltaTime)
		self:_onHeartbeat(deltaTime)
	end)
	return true
end

function Service:Stop()
	self.started = false
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	self.windowElapsed = 0
	self.windowFrames = 0
	self.windowDelta = 0
	self.windowMaxDelta = 0
	table.clear(self.buckets)
end

return Service
