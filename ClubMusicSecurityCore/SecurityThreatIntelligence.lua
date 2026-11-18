--!strict
-- Bounded server-local threat correlation for staff review.
-- Correlation only: no persistence, cross-server writes, kicks, bans, restrictions, or gameplay changes.

local Players = game:GetService("Players")

local Service = {}
Service.__index = Service

local WINDOW_SECONDS = 600
local INCIDENT_TTL_SECONDS = 1800
local MAX_SUBJECTS = 256
local MAX_INCIDENTS = 256
local MAX_SIGNALS_PER_SUBJECT = 12
local MAX_QUERY = 30
local MAX_USER_ID = 9007199254740991

local CATEGORY_WEIGHT = {
	Movement = 2,
	Audio = 2,
	Social = 2,
	Avatar = 1,
	Purchase = 3,
	Messaging = 2,
	Authorization = 1,
	Remote = 2,
	Watchdog = 2,
	SafeCall = 2,
	Diagnostics = 2,
	Monitor = 2,
	Other = 1,
}

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local function validUserId(value: any): boolean
	return finite(value) and value % 1 == 0 and value >= 0 and value <= MAX_USER_ID
end

local function cleanCode(value: any, maxLength: number): string?
	if typeof(value) ~= "string" or #value < 1 or #value > maxLength
		or not string.match(value, "^[%w_%-]+$") then return nil end
	return value
end

local function classify(signal: string): string
	local value = string.lower(signal)
	if string.find(value, "movement", 1, true) or string.find(value, "physics", 1, true) then return "Movement" end
	if string.find(value, "audio", 1, true) or string.find(value, "asset", 1, true) then return "Audio" end
	if string.find(value, "teleport", 1, true) then return "Social" end
	if string.find(value, "avatar", 1, true) or string.find(value, "accessory", 1, true) then return "Avatar" end
	if string.find(value, "purchase", 1, true) or string.find(value, "receipt", 1, true) then return "Purchase" end
	if string.find(value, "message", 1, true) or string.find(value, "messaging", 1, true) then return "Messaging" end
	if string.find(value, "admin", 1, true) or string.find(value, "privilege", 1, true) then return "Authorization" end
	if string.find(value, "remote", 1, true) or string.find(value, "request", 1, true) then return "Remote" end
	if string.find(value, "watchdog", 1, true) then return "Watchdog" end
	if string.find(value, "safe_call", 1, true) then return "SafeCall" end
	if string.find(value, "diagnostic", 1, true) or string.find(value, "server_health", 1, true) then return "Diagnostics" end
	if string.find(value, "security_monitor", 1, true) then return "Monitor" end
	return "Other"
end

local function confidenceFor(bucket): string
	local categories = 0
	for _ in pairs(bucket.categories) do categories += 1 end
	local signals = 0
	for _ in pairs(bucket.signals) do signals += 1 end
	if categories >= 3 and signals >= 3 and bucket.score >= 8 then return "High" end
	if categories >= 2 and signals >= 2 and bucket.score >= 4 then return "Medium" end
	return "Low"
end

local function sortedKeys(source): {string}
	local result = {}
	for key in pairs(source) do table.insert(result, key) end
	table.sort(result)
	return result
end

function Service.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table" and type(dependencies.authorize) == "function",
		"SecurityThreatIntelligence requires an authorization callback")
	return setmetatable({
		d = dependencies,
		started = false,
		buckets = {},
		incidents = {},
		incidentsById = {},
		nextPruneAt = 0,
		nextIncidentId = 0,
		totalSignals = 0,
		droppedSignals = 0,
		openedForReview = 0,
		deniedQueries = 0,
	}, Service)
end

function Service:Start(): boolean
	self.started = true
	return true
end

function Service:_prune(now: number)
	-- Expiry is bounded to a five-second sweep cadence instead of scanning
	-- every retained subject and incident for every incoming signal.
	if now < self.nextPruneAt then return end
	self.nextPruneAt = now + 5
	for key, bucket in pairs(self.buckets) do
		if now - bucket.lastAt > WINDOW_SECONDS then
			if bucket.incidentId then self.incidentsById[bucket.incidentId] = nil end
			self.buckets[key] = nil
		end
	end
	for index = #self.incidents, 1, -1 do
		local item = self.incidents[index]
		if now - item.lastAt > INCIDENT_TTL_SECONDS then
			self.incidentsById[item.id] = nil
			table.remove(self.incidents, index)
		end
	end
end

function Service:_rememberIncident(bucket, userId: number, now: number)
	local confidence = confidenceFor(bucket)
	if confidence == "Low" then return end
	local item = if bucket.incidentId then self.incidentsById[bucket.incidentId] else nil
	if not item then
		if #self.incidents >= MAX_INCIDENTS then
			local evicted = table.remove(self.incidents, 1)
			if evicted then self.incidentsById[evicted.id] = nil end
		end
		self.nextIncidentId += 1
		item = {
			id = "TTI-" .. tostring(self.nextIncidentId),
			subjectUserId = userId,
			state = "Review",
			firstAt = bucket.firstAt,
			lastAt = now,
			eventCount = 0,
			score = 0,
			confidence = confidence,
			categories = {},
			signals = {},
			sourceCount = 0,
			automaticEnforcement = false,
		}
		table.insert(self.incidents, item)
		self.incidentsById[item.id] = item
		bucket.incidentId = item.id
		self.openedForReview += 1
	end
	local sourceCount = 0
	for _ in pairs(bucket.sources) do sourceCount += 1 end
	item.lastAt = now
	item.eventCount = bucket.eventCount
	item.score = bucket.score
	item.confidence = confidence
	item.categories = sortedKeys(bucket.categories)
	item.signals = sortedKeys(bucket.signals)
	item.sourceCount = sourceCount
end

function Service:Record(signal: any, userId: any, source: any, severity: any): boolean
	if not self.started or not validUserId(userId) then self.droppedSignals += 1; return false end
	local safeSignal = cleanCode(signal, 48)
	local safeSource = cleanCode(source or "Server", 32)
	if not safeSignal or not safeSource then self.droppedSignals += 1; return false end
	local now = os.clock()
	self:_prune(now)
	local key = tostring(math.floor(userId))
	local bucket = self.buckets[key]
	if not bucket then
		local count = 0
		local oldestKey, oldestAt = nil, math.huge
		for existingKey, existing in pairs(self.buckets) do
			count += 1
			if existing.lastAt < oldestAt then oldestAt = existing.lastAt; oldestKey = existingKey end
		end
		if count >= MAX_SUBJECTS then
			if oldestKey then self.buckets[oldestKey] = nil end
			self.droppedSignals += 1
		end
		bucket = {
			firstAt = now, lastAt = now, eventCount = 0, score = 0,
			signals = {}, categories = {}, sources = {}, signalCounts = {}, incidentId = nil,
		}
		self.buckets[key] = bucket
	end
	local category = classify(safeSignal)
	local previousCount = bucket.signalCounts[safeSignal] or 0
	if previousCount < 3 then
		local knownSignals = 0
		for _ in pairs(bucket.signals) do knownSignals += 1 end
		if bucket.signals[safeSignal] or knownSignals < MAX_SIGNALS_PER_SUBJECT then
			local weight = CATEGORY_WEIGHT[category] or 1
			local severityBonus = if severity == "Critical" then 1 else 0
			bucket.score = math.min(100, bucket.score + weight + severityBonus)
			bucket.signalCounts[safeSignal] = previousCount + 1
			bucket.signals[safeSignal] = true
			bucket.categories[category] = true
			bucket.sources[safeSource] = true
		end
	end
	bucket.eventCount = math.min(1000000, bucket.eventCount + 1)
	bucket.lastAt = now
	self.totalSignals = math.min(1000000000, self.totalSignals + 1)
	self:_rememberIncident(bucket, math.floor(userId), now)
	return true
end

function Service:_authorized(actor: any): boolean
	if typeof(actor) ~= "Instance" or not actor:IsA("Player") or actor.Parent ~= Players then return false end
	local ok, allowed = pcall(self.d.authorize, actor.UserId, "GlobalModeration")
	return ok and allowed == true and actor.Parent == Players
end

function Service:Query(actor: any, targetUserId: any, limit: any)
	if not self:_authorized(actor) then
		self.deniedQueries += 1
		return false, {}, "Threat intelligence permission denied."
	end
	if targetUserId ~= nil and not validUserId(targetUserId) then return false, {}, "Invalid target UserId." end
	local now = os.clock()
	self:_prune(now)
	local queryLimit = if finite(limit) then math.clamp(math.floor(limit), 1, MAX_QUERY) else 15
	local result = {}
	for index = #self.incidents, 1, -1 do
		local item = self.incidents[index]
		if targetUserId == nil or item.subjectUserId == math.floor(targetUserId) then
			table.insert(result, table.clone(item))
			if #result >= queryLimit then break end
		end
	end
	return true, result
end

function Service:GetStatus()
	local tracked = 0
	for _ in pairs(self.buckets) do tracked += 1 end
	return {
		state = if self.started then "Observing" else "Stopped",
		scope = "ServerLocal",
		trackedSubjects = tracked,
		maxTrackedSubjects = MAX_SUBJECTS,
		openReviewItems = #self.incidents,
		maxReviewItems = MAX_INCIDENTS,
		totalSignals = self.totalSignals,
		droppedSignals = self.droppedSignals,
		openedForReview = self.openedForReview,
		deniedQueries = self.deniedQueries,
		windowSeconds = WINDOW_SECONDS,
		reviewTtlSeconds = INCIDENT_TTL_SECONDS,
		automaticEnforcement = false,
		persistentWrites = 0,
	}
end

function Service:Stop()
	self.started = false
	table.clear(self.buckets)
	table.clear(self.incidents)
	table.clear(self.incidentsById)
	self.nextPruneAt = 0
end

return Service
