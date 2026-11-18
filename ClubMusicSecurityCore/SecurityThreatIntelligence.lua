--!strict
-- Bounded server-local threat correlation and raid/cohort early warning.
-- Advisory only: no persistence, cross-server writes, kicks, bans, restrictions, or gameplay changes.

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
local MAX_COUNTER = 1000000000
local MAX_EVENT_IDS = 256
local EVENT_ID_TTL = 30
local COHORT_WINDOW_SECONDS = 60
local MAX_COHORT_SUBJECTS = 128
local MAX_RAID_REVIEWS = 32
local MAX_SESSION_EVENTS = 1000

local CATEGORY_WEIGHT = {
	Movement = 2, Audio = 2, Social = 2, Avatar = 1, Purchase = 3,
	Messaging = 2, Authorization = 2, Remote = 2, Watchdog = 2,
	SafeCall = 2, Diagnostics = 1, Monitor = 2, Other = 0,
}

-- Exact, reviewed machine codes only. Unknown codes are retained as zero-weight
-- Other telemetry for diagnostics, but never contribute to confidence or score.
local SIGNALS = {}
local function add(category: string, weight: number, codes: {string})
	for _, code in ipairs(codes) do SIGNALS[code] = {category = category, weight = weight} end
end

add("Movement", 2, {
	"movement_limit_exceeded", "unverified_movement_change",
	"world_physics_limit_exceeded", "unverified_world_physics_change",
})
add("Audio", 2, {"audio_asset_invalid_id", "audio_asset_not_allowlisted"})
add("Avatar", 1, {
	"tool_inventory_observation_cap", "tool_added_after_appearance", "tool_removed_from_inventory",
	"avatar_accessory_added_after_appearance", "avatar_accessory_excessive_parts",
	"avatar_accessory_missing_handle", "avatar_accessory_abnormal_handle_size",
	"avatar_accessory_collidable_handle", "avatar_accessory_observation_cap",
	"avatar_accessory_handle_size_changed", "avatar_accessory_handle_collision_changed",
	"avatar_accessory_rapid_insertion", "avatar_description_unavailable",
	"avatar_accessory_description_invalid", "avatar_accessory_count_exceeded",
	"avatar_accessory_invalid_asset_id", "avatar_accessory_duplicate_asset",
	"avatar_accessory_removed_after_appearance",
	"animation_track_observation_cap", "animation_asset_observation_cap", "animation_asset_observed",
})
add("Remote", 3, {
	"honeypot_admin_privilege_remote", "honeypot_purchase_receipt_remote",
	"honeypot_vip_entitlement_remote", "honeypot_moderation_action_remote",
	"honeypot_admin_command_event", "honeypot_unlock_all_gear_event",
	"honeypot_set_vip_rank_event", "honeypot_give_tip_money_event",
})
add("Authorization", 2, {
	"admin_bridge_invalid_operation", "admin_bridge_access_denied",
	"admin_moderation_access_denied", "admin_security_access_denied",
	"admin_operational_access_denied", "admin_security_access_denied",
})
add("Diagnostics", 1, {
	"client_integrity_observer_heartbeat", "client_walkspeed_observed_change",
	"client_integrity_dependency_missing",
})
add("Watchdog", 2, {"watchdog_unhealthy", "watchdog_degraded"})
add("SafeCall", 2, {"safecall_failure", "safe_call_failure"})
add("Monitor", 2, {"security_monitor_threshold_crossed", "security_monitor_alert"})
add("Messaging", 2, {"message_validation_failed", "invalid_message", "validator_unavailable"})
add("Purchase", 3, {"purchase_receipt_invalid", "purchase_receipt_replay", "purchase_product_unrecognized"})
add("Remote", 2, {"remote_rate_limit_exceeded", "remote_validation_failed"})
add("Social", 1, {"player_report_received", "teleport_validation_failed"})

local ALLOWED_SEVERITY = {Info = true, Warning = true, Critical = true}

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function validUserId(value: any): boolean
	return finite(value) and value % 1 == 0 and value >= 1 and value <= MAX_USER_ID
end

local function cleanCode(value: any, maxLength: number): string?
	if typeof(value) ~= "string" or #value < 1 or #value > maxLength
		or not string.match(value, "^[%w_%-]+$") then return nil end
	return value
end

local function countKeys(source): number
	local count = 0
	for _ in pairs(source) do count += 1 end
	return count
end

local function sortedKeys(source): {string}
	local result = {}
	for key in pairs(source) do table.insert(result, key) end
	table.sort(result)
	return result
end

local function confidenceFor(bucket): string
	local categories = countKeys(bucket.categories)
	local signals = countKeys(bucket.signals)
	local sources = countKeys(bucket.sources)
	if categories >= 3 and signals >= 3 and sources >= 2 and bucket.score >= 8 then return "High" end
	if categories >= 2 and signals >= 2 and bucket.score >= 4 then return "Medium" end
	return "Low"
end

function Service.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table" and type(dependencies.authorize) == "function",
		"SecurityThreatIntelligence requires an authorization callback")
	local players = dependencies.players or Players
	return setmetatable({
		d = dependencies,
		players = players,
		now = if type(dependencies.now) == "function" then dependencies.now else os.clock,
		started = false,
		buckets = {},
		incidents = {},
		sessions = {},
		joinEvents = {},
		cohortSignals = {},
		cohortCategories = {},
		cohortSources = {},
		cohortCodes = {},
		raidReviews = {},
		recentEventIds = {},
		connections = {},
		nextIncidentId = 0,
		nextRaidId = 0,
		totalSignals = 0,
		droppedSignals = 0,
		openedForReview = 0,
		deniedQueries = 0,
		expiredSubjects = 0,
		expiredReviews = 0,
		subjectEvictions = 0,
		reviewEvictions = 0,
		raidReviewEvictions = 0,
		duplicateEventIds = 0,
		cappedContributions = 0,
		unknownSignals = 0,
		rejectedInputs = 0,
		cohortJoinCount = 0,
		cohortSignalCount = 0,
	}, Service)
end

function Service:_prune(now: number)
	for key, bucket in pairs(self.buckets) do
		if now - bucket.lastAt > WINDOW_SECONDS then
			self.buckets[key] = nil
			self.expiredSubjects = math.min(MAX_COUNTER, self.expiredSubjects + 1)
		end
	end
	for index = #self.incidents, 1, -1 do
		if now - self.incidents[index].lastAt > INCIDENT_TTL_SECONDS then
			table.remove(self.incidents, index)
			self.expiredReviews = math.min(MAX_COUNTER, self.expiredReviews + 1)
		end
	end
	for id, at in pairs(self.recentEventIds) do
		if now - at > EVENT_ID_TTL then self.recentEventIds[id] = nil end
	end
	local cutoff = now - COHORT_WINDOW_SECONDS
	for index = #self.joinEvents, 1, -1 do
		if self.joinEvents[index].at < cutoff then table.remove(self.joinEvents, index) end
	end
	for index = #self.raidReviews, 1, -1 do
		if now - self.raidReviews[index].lastAt > INCIDENT_TTL_SECONDS then
			table.remove(self.raidReviews, index)
			self.expiredReviews = math.min(MAX_COUNTER, self.expiredReviews + 1)
		end
	end
	-- Rebuild cohort evidence from only the active join window. The set is bounded
	-- by the join-event cap, so no long-lived identity history accumulates.
	local joined = {}
	for _, event in ipairs(self.joinEvents) do joined[event.userId] = true end
	table.clear(self.cohortCategories)
	table.clear(self.cohortSources)
	table.clear(self.cohortCodes)
	for userId, evidence in pairs(self.cohortSignals) do
		if not joined[userId] then
			self.cohortSignals[userId] = nil
		else
			for category in pairs(evidence.categories) do self.cohortCategories[category] = true end
			for source in pairs(evidence.sources) do self.cohortSources[source] = true end
			for code in pairs(evidence.codes) do self.cohortCodes[code] = true end
		end
	end
end

function Service:_resetCohort()
	table.clear(self.joinEvents)
	table.clear(self.cohortSignals)
	table.clear(self.cohortCategories)
	table.clear(self.cohortSources)
	table.clear(self.cohortCodes)
end

function Service:_recordJoin(userId: number, now: number)
	self:_prune(now)
	-- A player contributes at most one join to the current rolling cohort window.
	for _, event in ipairs(self.joinEvents) do
		if event.userId == userId then return false end
	end
	if #self.joinEvents >= MAX_COHORT_SUBJECTS then
		table.remove(self.joinEvents, 1)
		self.subjectEvictions = math.min(MAX_COUNTER, self.subjectEvictions + 1)
	end
	table.insert(self.joinEvents, {userId = userId, at = now})
	self.cohortJoinCount = math.min(MAX_COUNTER, self.cohortJoinCount + 1)
	return true
end

function Service:JoinUserId(userId: any): boolean
	if not self.started or not validUserId(userId) then return false end
	local now = self.now()
	local key = tostring(math.floor(userId))
	if not self.sessions[key] then self.sessions[key] = {startedAt = now, eventCount = 0} end
	self:_recordJoin(math.floor(userId), now)
	return true
end

function Service:PlayerJoined(player: any): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
	return self:JoinUserId(player.UserId)
end

function Service:PlayerRemoving(player: any)
	if typeof(player) == "Instance" and player:IsA("Player") then
		self.sessions[tostring(player.UserId)] = nil
	end
end

function Service:Start(): boolean
	if self.started then return true end
	self.started = true
	for _, player in ipairs(self.players:GetPlayers()) do
		if validUserId(player.UserId) then
			self.sessions[tostring(player.UserId)] = {startedAt = self.now(), eventCount = 0}
		end
	end
	table.insert(self.connections, self.players.PlayerAdded:Connect(function(player)
		self:PlayerJoined(player)
	end))
	table.insert(self.connections, self.players.PlayerRemoving:Connect(function(player)
		self:PlayerRemoving(player)
	end))
	return true
end

function Service:_rememberRaid(now: number)
	local joinCount = #self.joinEvents
	local signaledPlayers = countKeys(self.cohortSignals)
	local categories = countKeys(self.cohortCategories)
	local sources = countKeys(self.cohortSources)
	local codes = countKeys(self.cohortCodes)

	-- Conservative initial tripwire: join burst plus independent player and
	-- signal corroboration. Join volume alone is never a raid review.
	if joinCount < 8 or signaledPlayers < 3 or categories < 2 or sources < 2 then return end

	local confidence = if joinCount >= 15 and signaledPlayers >= 5 and categories >= 3
		and sources >= 3 and codes >= 4 then "High" else "Medium"
	local latest = now
	local existing = self.raidReviews[#self.raidReviews]
	if existing and now - existing.lastAt <= COHORT_WINDOW_SECONDS then
		existing.lastAt = latest
		existing.joinCount = joinCount
		existing.signaledPlayerCount = signaledPlayers
		existing.categoryCount = categories
		existing.sourceCount = sources
		existing.signalCodeCount = codes
		existing.confidence = confidence
		existing.reasons = {"JOIN_BURST", "COHORT_CORROBORATION", "MULTI_CATEGORY", "MULTI_SOURCE"}
		return
	end
	if #self.raidReviews >= MAX_RAID_REVIEWS then
		table.remove(self.raidReviews, 1)
		self.raidReviewEvictions = math.min(MAX_COUNTER, self.raidReviewEvictions + 1)
	end
	self.nextRaidId += 1
	table.insert(self.raidReviews, {
		id = "RAID-" .. tostring(self.nextRaidId),
		kind = "CohortReview",
		state = "Review",
		firstAt = self.joinEvents[1].at,
		lastAt = now,
		joinCount = joinCount,
		signaledPlayerCount = signaledPlayers,
		categoryCount = categories,
		sourceCount = sources,
		signalCodeCount = codes,
		confidence = confidence,
		reasons = {"JOIN_BURST", "COHORT_CORROBORATION", "MULTI_CATEGORY", "MULTI_SOURCE"},
		automaticEnforcement = false,
	})
end

function Service:_rememberIncident(bucket, userId: number, now: number)
	local confidence = confidenceFor(bucket)
	if confidence == "Low" then return end
	local item = nil
	if bucket.incidentId then
		for index = #self.incidents, 1, -1 do
			if self.incidents[index].id == bucket.incidentId then item = self.incidents[index]; break end
		end
	end
	if not item then
		if #self.incidents >= MAX_INCIDENTS then
			table.remove(self.incidents, 1)
			self.reviewEvictions = math.min(MAX_COUNTER, self.reviewEvictions + 1)
		end
		self.nextIncidentId += 1
		item = {
			id = "TTI-" .. tostring(self.nextIncidentId),
			kind = "PlayerReview",
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
			reasons = {},
			automaticEnforcement = false,
		}
		table.insert(self.incidents, item)
		bucket.incidentId = item.id
		self.openedForReview = math.min(MAX_COUNTER, self.openedForReview + 1)
	end
	local categories = sortedKeys(bucket.categories)
	local signals = sortedKeys(bucket.signals)
	local sources = sortedKeys(bucket.sources)
	local reasons = {}
	if #categories >= 2 then table.insert(reasons, "MULTI_CATEGORY") end
	if #sources >= 2 then table.insert(reasons, "MULTI_SOURCE") end
	if bucket.capped then table.insert(reasons, "REPEATED_SIGNAL_CAPPED") end
	item.lastAt = now
	item.eventCount = bucket.eventCount
	item.score = bucket.score
	item.confidence = confidence
	item.categories = categories
	item.signals = signals
	item.sources = sources
	item.sourceCount = #sources
	item.categoryCount = #categories
	item.signalCodeCount = #signals
	item.sessionAgeSeconds = math.max(0, math.floor(now - (bucket.sessionStartedAt or bucket.firstAt)))
	item.sessionEventCount = bucket.sessionEventCount or 0
	item.reasons = reasons
end

function Service:Record(signal: any, userId: any, source: any, severity: any, eventId: any): boolean
	if not self.started or not validUserId(userId) then
		self.droppedSignals = math.min(MAX_COUNTER, self.droppedSignals + 1)
		self.rejectedInputs = math.min(MAX_COUNTER, self.rejectedInputs + 1)
		return false
	end
	local safeSignal = cleanCode(signal, 48)
	local safeSource = cleanCode(source or "Unknown", 32)
	if not safeSignal or not safeSource then
		self.droppedSignals = math.min(MAX_COUNTER, self.droppedSignals + 1)
		self.rejectedInputs = math.min(MAX_COUNTER, self.rejectedInputs + 1)
		return false
	end
	local safeSeverity = if typeof(severity) == "string" and ALLOWED_SEVERITY[severity] then severity else "Info"
	local safeEventId = if eventId ~= nil then cleanCode(eventId, 64) else nil
	if eventId ~= nil and not safeEventId then
		self.rejectedInputs = math.min(MAX_COUNTER, self.rejectedInputs + 1)
		return false
	end

	local now = self.now()
	self:_prune(now)
	if safeEventId then
		if self.recentEventIds[safeEventId] then
			self.duplicateEventIds = math.min(MAX_COUNTER, self.duplicateEventIds + 1)
			return false
		end
		if countKeys(self.recentEventIds) >= MAX_EVENT_IDS then
			local oldestId, oldestAt = nil, math.huge
			for id, at in pairs(self.recentEventIds) do if at < oldestAt then oldestId, oldestAt = id, at end end
			if oldestId then self.recentEventIds[oldestId] = nil end
		end
		self.recentEventIds[safeEventId] = now
	end

	local registry = SIGNALS[safeSignal]
	if not registry then
		self.unknownSignals = math.min(MAX_COUNTER, self.unknownSignals + 1)
	end
	local key = tostring(math.floor(userId))
	local bucket = self.buckets[key]
	if not bucket then
		if countKeys(self.buckets) >= MAX_SUBJECTS then
			local oldestKey, oldestAt = nil, math.huge
			for existingKey, existing in pairs(self.buckets) do
				if existing.lastAt < oldestAt then oldestAt = existing.lastAt; oldestKey = existingKey end
			end
			if oldestKey then
				self.buckets[oldestKey] = nil
				self.subjectEvictions = math.min(MAX_COUNTER, self.subjectEvictions + 1)
			end
		end
		local session = self.sessions[key]
		bucket = {
			firstAt = now, lastAt = now, eventCount = 0, score = 0,
			signals = {}, categories = {}, sources = {}, signalCounts = {},
			categoryScores = {}, sourceScores = {}, incidentId = nil, capped = false,
			sessionStartedAt = if session then session.startedAt else now,
			sessionEventCount = if session then session.eventCount else 0,
		}
		self.buckets[key] = bucket
	end

	bucket.eventCount = math.min(MAX_COUNTER, bucket.eventCount + 1)
	bucket.lastAt = now
	bucket.sessionEventCount = math.min(MAX_SESSION_EVENTS, (bucket.sessionEventCount or 0) + 1)
	local session = self.sessions[key]
	if session then session.eventCount = math.min(MAX_SESSION_EVENTS, session.eventCount + 1) end
	self.totalSignals = math.min(MAX_COUNTER, self.totalSignals + 1)

	-- Unknown codes remain visible in counters but are deliberately excluded from
	-- scoring, category diversity, source diversity, and review thresholds.
	if registry then
		local previousCount = bucket.signalCounts[safeSignal] or 0
		local knownSignals = countKeys(bucket.signals)
		if previousCount >= 3 or (not bucket.signals[safeSignal] and knownSignals >= MAX_SIGNALS_PER_SUBJECT) then
			bucket.capped = true
			self.cappedContributions = math.min(MAX_COUNTER, self.cappedContributions + 1)
		else
			local category = registry.category
			local weight = math.min(3, math.max(0, registry.weight or CATEGORY_WEIGHT[category] or 0))
			local severityBonus = if safeSeverity == "Critical" then 1 else 0
			local categoryScore = bucket.categoryScores[category] or 0
			local sourceScore = bucket.sourceScores[safeSource] or 0
			local contribution = math.min(weight + severityBonus,
				math.max(0, 8 - categoryScore), math.max(0, 8 - sourceScore))
			if contribution <= 0 then
				bucket.capped = true
				self.cappedContributions = math.min(MAX_COUNTER, self.cappedContributions + 1)
			else
				bucket.signalCounts[safeSignal] = previousCount + 1
				bucket.signals[safeSignal] = true
				bucket.categories[category] = true
				bucket.sources[safeSource] = true
				bucket.categoryScores[category] = categoryScore + contribution
				bucket.sourceScores[safeSource] = sourceScore + contribution
				bucket.score = math.min(100, bucket.score + contribution)
			end
		end
	end

	if registry then
		local joinedInWindow = false
		for _, event in ipairs(self.joinEvents) do if event.userId == userId then joinedInWindow = true; break end end
		if joinedInWindow then
			local evidence = self.cohortSignals[userId]
			if not evidence then
				evidence = {count = 0, categories = {}, sources = {}, codes = {}}
				self.cohortSignals[userId] = evidence
			end
			evidence.count = math.min(3, evidence.count + 1)
			evidence.categories[registry.category] = true
			evidence.sources[safeSource] = true
			evidence.codes[safeSignal] = true
			self.cohortCategories[registry.category] = true
			self.cohortSources[safeSource] = true
			self.cohortCodes[safeSignal] = true
			self.cohortSignalCount = math.min(MAX_COUNTER, self.cohortSignalCount + 1)
			self:_rememberRaid(now)
		end
	end
	self:_rememberIncident(bucket, math.floor(userId), now)
	return true
end

function Service:_authorized(actor: any): boolean
	if typeof(actor) ~= "Instance" or not actor:IsA("Player") or actor.Parent ~= self.players then return false end
	local ok, allowed = pcall(self.d.authorize, actor.UserId, "GlobalModeration")
	return ok and allowed == true and actor.Parent == self.players
end

function Service:Query(actor: any, targetUserId: any, limit: any)
	if not self:_authorized(actor) then
		self.deniedQueries = math.min(MAX_COUNTER, self.deniedQueries + 1)
		return false, {}, "Threat intelligence permission denied."
	end
	if targetUserId ~= nil and not validUserId(targetUserId) then return false, {}, "Invalid target UserId." end
	local now = self.now()
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

function Service:QueryRaids(actor: any, limit: any)
	if not self:_authorized(actor) then
		self.deniedQueries = math.min(MAX_COUNTER, self.deniedQueries + 1)
		return false, {}, "Threat intelligence permission denied."
	end
	self:_prune(self.now())
	local queryLimit = if finite(limit) then math.clamp(math.floor(limit), 1, MAX_QUERY) else 10
	local result = {}
	for index = #self.raidReviews, 1, -1 do
		table.insert(result, table.clone(self.raidReviews[index]))
		if #result >= queryLimit then break end
	end
	return true, result
end

function Service:GetStatus()
	local tracked = countKeys(self.buckets)
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
		expiredSubjects = self.expiredSubjects,
		expiredReviews = self.expiredReviews,
		subjectEvictions = self.subjectEvictions,
		reviewEvictions = self.reviewEvictions,
		raidReviewEvictions = self.raidReviewEvictions,
		duplicateEventIds = self.duplicateEventIds,
		cappedContributions = self.cappedContributions,
		unknownSignals = self.unknownSignals,
		rejectedInputs = self.rejectedInputs,
		cohortJoinCount = self.cohortJoinCount,
		cohortWindowJoins = #self.joinEvents,
		cohortSignaledPlayers = countKeys(self.cohortSignals),
		cohortSignalCount = self.cohortSignalCount,
		raidReviewItems = #self.raidReviews,
		cohortWindowSeconds = COHORT_WINDOW_SECONDS,
		cohortJoinThreshold = 8,
		cohortSignaledPlayerThreshold = 3,
		cohortThresholdsProvisional = true,
		sessionTrackedPlayers = countKeys(self.sessions),
		windowSeconds = WINDOW_SECONDS,
		reviewTtlSeconds = INCIDENT_TTL_SECONDS,
		maxEventIds = MAX_EVENT_IDS,
		automaticEnforcement = false,
		persistentWrites = 0,
		crossServerWrites = 0,
	}
end

function Service:Stop()
	self.started = false
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
	table.clear(self.buckets)
	table.clear(self.incidents)
	table.clear(self.sessions)
	table.clear(self.joinEvents)
	table.clear(self.cohortSignals)
	table.clear(self.cohortCategories)
	table.clear(self.cohortSources)
	table.clear(self.cohortCodes)
	table.clear(self.raidReviews)
	table.clear(self.recentEventIds)
end

return Service
