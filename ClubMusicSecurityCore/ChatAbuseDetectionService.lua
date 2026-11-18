--!strict
-- Phase 32: safe server-side filtering for custom broadcast text.
-- Filtered output is never interpreted as proof of evasion. In particular,
-- '#' masking is not a strike signal. Callers must not display raw input.
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local Service = {}
Service.__index = Service

local MAX_BYTES = 120
local MAX_CODEPOINTS = 120
local MIN_INTERVAL = 1.25
local MAX_COUNTER = 9007199254740991

local function validLivePlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
		and player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

function Service.new(options: {[string]: any}?)
	local config = if typeof(options) == "table" then options else {}
	return setmetatable({
		lastSubmit = {} :: {[number]: number},
		submissions = 0,
		rejected = 0,
		filterFailures = 0,
		lastError = nil :: string?,
		onVerifiedViolation = if type(config.onVerifiedViolation) == "function" then config.onVerifiedViolation else nil,
	}, Service)
end

function Service:FilterBroadcast(player: Player, rawText: any): (boolean, string?, string?)
	if not validLivePlayer(player) then return false, nil, "A live player is required." end
	if typeof(rawText) ~= "string" or #rawText < 1 or #rawText > MAX_BYTES then
		self.rejected = math.min(self.rejected + 1, MAX_COUNTER)
		return false, nil, "Text is empty or exceeds the size limit."
	end
	local codepoints = utf8.len(rawText)
	if not codepoints or codepoints < 1 or codepoints > MAX_CODEPOINTS then
		self.rejected = math.min(self.rejected + 1, MAX_COUNTER)
		return false, nil, "Text is not valid bounded UTF-8."
	end
	local now = os.clock()
	local previous = self.lastSubmit[player.UserId] or 0
	if previous > 0 and now - previous < MIN_INTERVAL then
		self.rejected = math.min(self.rejected + 1, MAX_COUNTER)
		return false, nil, "Please wait before submitting more text."
	end
	self.lastSubmit[player.UserId] = now

	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(rawText, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(filtered) ~= "string" then
		self.filterFailures = math.min(self.filterFailures + 1, MAX_COUNTER)
		self.lastError = string.sub(tostring(filtered), 1, 160)
		-- Fail closed: do not return raw input or a partially filtered result.
		return false, nil, "Roblox text filtering is unavailable. Please try again."
	end
	if player.Parent ~= Players then return false, nil, "The submitting player disconnected." end
	self.submissions = math.min(self.submissions + 1, MAX_COUNTER)
	self.lastError = nil
	-- A hash-heavy result is valid filtered output, not a violation verdict.
	return true, filtered, nil
end

-- This method is intentionally not called from FilterBroadcast. Only trusted
-- server moderation code may report a separately verified policy violation.
function Service:RecordVerifiedViolation(player: Player, category: string, evidenceReference: string): boolean
	if not validLivePlayer(player) or typeof(category) ~= "string" or #category < 1 or #category > 48
		or typeof(evidenceReference) ~= "string" or #evidenceReference < 1 or #evidenceReference > 96 then
		return false
	end
	if type(self.onVerifiedViolation) ~= "function" then return false end
	local ok = pcall(self.onVerifiedViolation, player.UserId, category, evidenceReference, os.time())
	return ok
end

function Service:RemovePlayer(player: Player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		self.lastSubmit[player.UserId] = nil
	end
end

function Service:GetStatus(): {[string]: any}
	return {
		state = "Ready",
		submissions = self.submissions,
		rejected = self.rejected,
		filterFailures = self.filterFailures,
		trackedSubmitters = (function()
			local count = 0
			for _ in pairs(self.lastSubmit) do count += 1 end
			return count
		end)(),
		lastError = self.lastError,
		filtering = "TextService:FilterStringAsync + GetNonChatStringForBroadcastAsync",
		punishmentInference = "Disabled",
	}
end

return Service
