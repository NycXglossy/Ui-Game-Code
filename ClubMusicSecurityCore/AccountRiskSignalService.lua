--!strict
-- Phase 32: advisory-only account risk signals from platform data and
-- authorized moderation history. Never identifies a person or punishes.
local Players = game:GetService("Players")

local Service = {}
Service.__index = Service

local MAX_HISTORY_TO_SCORE = 20
local MAX_SCORE = 100
local NEW_ACCOUNT_DAYS = 14
local REPEAT_WINDOW_SECONDS = 30 * 24 * 60 * 60

local function validUserId(value: any): boolean
	return typeof(value) == "number" and value == value and value > 0
		and value < math.huge and value % 1 == 0 and value <= 9007199254740991
end

function Service.new(options: {[string]: any})
	assert(typeof(options) == "table" and type(options.getAuthorizedHistory) == "function",
		"AccountRiskSignalService requires an authorized moderation-history provider")
	return setmetatable({
		getAuthorizedHistory = options.getAuthorizedHistory,
		maxHistory = if typeof(options.maxHistory) == "number" then math.clamp(math.floor(options.maxHistory), 1, MAX_HISTORY_TO_SCORE) else MAX_HISTORY_TO_SCORE,
		queries = 0,
		failures = 0,
	}, Service)
end

function Service:GetSignals(userId: number): (boolean, any)
	if not validUserId(userId) then return false, nil end
	self.queries += 1
	local historyOk, history = pcall(self.getAuthorizedHistory, userId, self.maxHistory)
	if not historyOk or typeof(history) ~= "table" then
		self.failures += 1
		return false, nil
	end

	local now = os.time()
	local verifiedRecent = 0
	local repeatCategories: {[string]: number} = {}
	local seenCases: {[string]: boolean} = {}
	for index = 1, math.min(#history, self.maxHistory) do
		local item = history[index]
		local unique = typeof(item) == "table" and (typeof(item.caseId) ~= "string" or not seenCases[item.caseId])
		if typeof(item) == "table" and typeof(item.caseId) == "string" then seenCases[item.caseId] = true end
		if unique and typeof(item) == "table" and item.verified == true
			and typeof(item.at) == "number" and now - item.at >= 0
			and now - item.at <= REPEAT_WINDOW_SECONDS then
			verifiedRecent += 1
			if typeof(item.category) == "string" and #item.category <= 48 then
				repeatCategories[item.category] = (repeatCategories[item.category] or 0) + 1
			end
		end
	end

	local player = Players:GetPlayerByUserId(userId)
	local accountAgeDays = if player and player.Parent == Players then player.AccountAge else nil
	local signals = {}
	local score = 0
	if typeof(accountAgeDays) == "number" and accountAgeDays < NEW_ACCOUNT_DAYS then
		score += 10
		table.insert(signals, {type = "NewAccountAge", confidence = "Low", accountAgeDays = accountAgeDays})
	end
	if verifiedRecent > 0 then
		local repeatScore = math.min(verifiedRecent * 10, 60)
		score += repeatScore
		table.insert(signals, {type = "VerifiedRecentModeration", confidence = "Verified", eventCount = verifiedRecent})
	end
	for category, count in pairs(repeatCategories) do
		if count >= 2 then
			score += 10
			table.insert(signals, {type = "RepeatedVerifiedCategory", confidence = "Verified", category = category, eventCount = count})
		end
	end
	return true, {
		userId = userId,
		score = math.min(score, MAX_SCORE),
		signals = signals,
		windowSeconds = REPEAT_WINDOW_SECONDS,
		accountLinkage = "Unavailable unless explicitly supplied by an authorized Roblox platform API",
		decision = "Investigation clue only; no automatic punishment",
	}
end

function Service:GetStatus(): {[string]: any}
	return {state = "Ready", queries = self.queries, failures = self.failures,
		accountLinkage = "Platform-authorized only", automaticEnforcement = false}
end

return Service
