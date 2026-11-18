--!strict
-- Phase 32: server-authoritative moderation actions.
-- Install as a ModuleScript under ServerStorage.ClubMusicSecurityCore.
-- The caller must inject the existing SecurityCore Authorization service.
-- No client remote should call this module directly.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Service = {}
Service.__index = Service

local MAX_HISTORY = 50
local RETENTION_SECONDS = 180 * 24 * 60 * 60
local MAX_REASON_LENGTH = 240
local MIN_TEMP_BAN_SECONDS = 60
local MAX_TEMP_BAN_SECONDS = 365 * 24 * 60 * 60
local MAX_RESTRICTION_KEYS = 12
local VALID_RESTRICTIONS = {
	Chat = true,
	MusicRequests = true,
	CustomText = true,
	DJFeatures = true,
	Announcements = true,
	Trading = true,
}

local function validUserId(value: any): boolean
	return typeof(value) == "number" and value == value and value > 0
		and value < math.huge and value % 1 == 0 and value <= 9007199254740991
end

local function cleanString(value: any, maximum: number): string?
	if typeof(value) ~= "string" then return nil end
	local cleaned = string.gsub(value, "[%c]", " ")
	cleaned = string.match(cleaned, "^%s*(.-)%s*$") or ""
	if #cleaned < 1 or #cleaned > maximum then return nil end
	return cleaned
end

local function hasPermission(authorization: any, actor: Player, permission: string): boolean
	if not authorization or type(authorization.Check) ~= "function" then return false end
	local ok, allowed = pcall(function()
		return authorization:Check(actor.UserId, permission)
	end)
	return ok and allowed == true and actor.Parent == Players
end

function Service.new(options: {[string]: any})
	assert(typeof(options) == "table", "ModerationPunishmentService options are required")
	assert(typeof(options.authorization) == "table", "SecurityCore Authorization is required")
	local storeName = if typeof(options.dataStoreName) == "string" and #options.dataStoreName >= 3
		and #options.dataStoreName <= 50 then options.dataStoreName else "TikiTideModeration_v1"
	return setmetatable({
		authorization = options.authorization,
		store = DataStoreService:GetDataStore(storeName),
		onAudit = if type(options.onAudit) == "function" then options.onAudit else function() end,
		onNotify = if type(options.onNotify) == "function" then options.onNotify else function() end,
		started = false,
		lastError = nil,
		restrictionCache = {} :: {[number]: {expiresAt: number, restricted: {[string]: boolean}}},
	}, Service)
end

function Service:_audit(kind: string, actorUserId: number, targetUserId: number, caseId: string, detail: string)
	pcall(self.onAudit, {
		kind = kind, actorUserId = actorUserId, targetUserId = targetUserId,
		caseId = caseId, at = os.time(), detail = string.sub(detail, 1, 120),
	})
end

function Service:_update(userId: number, transform: (any) -> any): (boolean, any)
	local ok, result = pcall(function()
		return self.store:UpdateAsync(tostring(userId), function(previous)
			local record = if typeof(previous) == "table" then previous else {schema = 1, active = {}, history = {}}
			if typeof(record.active) ~= "table" then record.active = {} end
			if typeof(record.history) ~= "table" then record.history = {} end
			local now = os.time()
			local retained = {}
			for _, item in ipairs(record.history) do
				if typeof(item) == "table" and typeof(item.at) == "number"
					and now - item.at <= RETENTION_SECONDS then
					table.insert(retained, item)
				end
			end
			record.history = retained
			for caseId, item in pairs(record.active) do
				if typeof(item) == "table" and typeof(item.expiresAt) == "number"
					and item.expiresAt > 0 and item.expiresAt <= now then
					record.active[caseId] = nil
				end
			end
			return transform(record)
		end)
	end)
	if not ok then
		self.lastError = string.sub(tostring(result), 1, 180)
		return false, nil
	end
	self.lastError = nil
	return true, result
end

function Service:_appendHistory(record: any, item: {[string]: any})
	table.insert(record.history, item)
	while #record.history > MAX_HISTORY do table.remove(record.history, 1) end
end

function Service:_readRecord(userId: number): (boolean, any)
	local ok, result = pcall(function() return self.store:GetAsync(tostring(userId)) end)
	if not ok then
		self.lastError = string.sub(tostring(result), 1, 180)
		return false, nil
	end
	if typeof(result) ~= "table" then return true, nil end
	local now = os.time()
	local needsPrune = false
	if typeof(result.history) == "table" then
		for _, item in ipairs(result.history) do
			if typeof(item) ~= "table" or typeof(item.at) ~= "number"
				or now - item.at > RETENTION_SECONDS then
				needsPrune = true
				break
			end
		end
	end
	if typeof(result.active) == "table" then
		for _, item in pairs(result.active) do
			if typeof(item) == "table" and typeof(item.expiresAt) == "number"
				and item.expiresAt > 0 and item.expiresAt <= now then
				needsPrune = true
				break
			end
		end
	end
	if needsPrune then
		local pruneOk, pruned = self:_update(userId, function(record) return record end)
		if not pruneOk then return false, nil end
		result = pruned
	end
	self.lastError = nil
	return true, result
end

function Service:Issue(actor: Player, targetUserId: number, action: {[string]: any}): (boolean, string?, string?)
	if typeof(actor) ~= "Instance" or not actor:IsA("Player") or actor.Parent ~= Players
		or not validUserId(targetUserId) or typeof(action) ~= "table" then
		return false, "Invalid actor, target, or action.", nil
	end
	local kind = action.kind
	if kind ~= "Warn" and kind ~= "Restrict" and kind ~= "TempBan" and kind ~= "PermanentBan" then
		return false, "Unsupported punishment type.", nil
	end
	local reason = cleanString(action.reason, MAX_REASON_LENGTH)
	if not reason then return false, "A bounded moderation reason is required.", nil end

	local permission = "GlobalModeration"
	local propagateAlt = action.propagateAltAccounts == true
	if kind == "PermanentBan" and propagateAlt then
		-- Roblox's native suspected-alt propagation is a senior-reviewed choice.
		if action.confirmAltPropagation ~= true
			or not hasPermission(self.authorization, actor, "IncidentResponse") then
			return false, "Permanent-ban alt propagation requires senior-staff confirmation.", nil
		end
	elseif kind == "PermanentBan" and action.confirmAltPropagation == true then
		return false, "Alt propagation confirmation was supplied without enabling propagation.", nil
	end
	if not hasPermission(self.authorization, actor, permission) then
		return false, "GlobalModeration permission is required.", nil
	end

	local duration = 0
	if kind == "TempBan" then
		if typeof(action.durationSeconds) ~= "number" or action.durationSeconds % 1 ~= 0
			or action.durationSeconds < MIN_TEMP_BAN_SECONDS or action.durationSeconds > MAX_TEMP_BAN_SECONDS then
			return false, "Temporary ban duration must be between 60 seconds and 365 days.", nil
		end
		duration = action.durationSeconds
	elseif kind == "PermanentBan" then
		duration = -1
	end

	local restriction = nil
	if kind == "Restrict" then
		if typeof(action.restrictions) ~= "table" then return false, "Restriction list is required.", nil end
		local seen = {}
		for _, key in ipairs(action.restrictions) do
			if typeof(key) ~= "string" or not VALID_RESTRICTIONS[key] or seen[key] then
				return false, "Restriction list contains an unsupported or duplicate feature.", nil
			end
			seen[key] = true
		end
		if #action.restrictions < 1 or #action.restrictions > MAX_RESTRICTION_KEYS then
			return false, "Restriction list is empty or exceeds its limit.", nil
		end
		restriction = table.clone(action.restrictions)
	end

	local caseId = HttpService:GenerateGUID(false)
	local now = os.time()
	local sanction = {
		caseId = caseId, kind = kind, status = "Pending", reason = reason,
		actorUserId = actor.UserId, targetUserId = targetUserId, at = now,
		expiresAt = if duration > 0 then now + duration else 0,
		durationSeconds = duration, restrictions = restriction,
		altPropagationRequested = propagateAlt,
	}
	local writeOk = self:_update(targetUserId, function(record)
		if typeof(record.active) ~= "table" then record.active = {} end
		if kind ~= "Warn" then record.active[caseId] = sanction end
		self:_appendHistory(record, table.clone(sanction))
		return record
	end)
	if not writeOk then return false, "Moderation evidence could not be saved; no punishment was applied.", nil end

	if kind == "TempBan" or kind == "PermanentBan" then
		local enabledOk, enabled = pcall(function() return Players.BanningEnabled end)
		if not enabledOk or enabled ~= true then
			self:_update(targetUserId, function(record)
				if record.active then record.active[caseId] = nil end
				self:_appendHistory(record, {caseId = caseId, kind = "BanApplyFailed", status = "Failed",
					actorUserId = actor.UserId, targetUserId = targetUserId, at = os.time(),
					reason = "Players.BanningEnabled is disabled or unavailable."})
				return record
			end)
			return false, "Roblox experience bans are disabled in Studio settings; no ban was applied.", caseId
		end
		local config = {
			UserIds = {targetUserId},
			Duration = duration,
			DisplayReason = "You are suspended from FireBeach Tiki Tide Music Festival Club. You may appeal through the experience's published appeal process.",
			PrivateReason = "Tiki Tide moderation case " .. caseId,
			ExcludeAltAccounts = not propagateAlt,
			ApplyToUniverse = true,
		}
		local banOk, banError = pcall(function() Players:BanAsync(config) end)
		if not banOk then
			self:_update(targetUserId, function(record)
				if record.active then record.active[caseId] = nil end
				self:_appendHistory(record, {caseId = caseId, kind = "BanApplyFailed", status = "Failed",
					actorUserId = actor.UserId, targetUserId = targetUserId, at = os.time(),
					reason = string.sub(tostring(banError), 1, MAX_REASON_LENGTH)})
				return record
			end)
			return false, "Roblox BanAsync failed; the sanction was not recorded as active.", caseId
		end
	end

	local activateOk = self:_update(targetUserId, function(record)
		local current = record.active and record.active[caseId]
		if current then
			current.status = "Active"
			-- Detailed reasons remain in the bounded 180-day history only.
			current.reason = nil
		end
		self:_appendHistory(record, {caseId = caseId, kind = kind, status = "Active",
			actorUserId = actor.UserId, targetUserId = targetUserId, at = os.time(),
			reason = reason, altPropagationRequested = propagateAlt})
		return record
	end)
	if not activateOk then
		-- Native BanAsync, when used, remains authoritative even if the follow-up
		-- bookkeeping write fails. Never report a successful durable case update.
		self:_audit("ModerationPersistenceDegraded", actor.UserId, targetUserId, caseId, "Activation write failed after native action.")
		return false, "Punishment was submitted, but final evidence confirmation failed. Escalate this case.", caseId
	end

	self.restrictionCache[targetUserId] = nil
	self:_audit("PunishmentIssued", actor.UserId, targetUserId, caseId, kind)
	local target = Players:GetPlayerByUserId(targetUserId)
	if kind == "Warn" and target then
		-- Notification is presentation only; the warning remains in durable case history.
		pcall(self.onNotify, target, "warn", "A moderator has issued a formal warning. Please review the experience rules.")
	elseif kind == "Restrict" and target then
		pcall(self.onNotify, target, "warn", "One or more experience features have been restricted by moderation.")
	end
	return true, "Punishment recorded.", caseId
end

function Service:GetActive(targetUserId: number): (boolean, any)
	if not validUserId(targetUserId) then return false, nil end
	local readOk, result = self:_readRecord(targetUserId)
	if not readOk then return false, nil end
	if typeof(result) ~= "table" or typeof(result.active) ~= "table" then return true, {} end
	local now = os.time()
	local active = {}
	for caseId, item in pairs(result.active) do
		if typeof(item) == "table" and item.status == "Active"
			and (item.expiresAt == 0 or (typeof(item.expiresAt) == "number" and item.expiresAt > now)) then
			table.insert(active, {
				caseId = caseId, kind = item.kind, restrictions = item.restrictions,
				expiresAt = item.expiresAt, at = item.at,
			})
		end
	end
	return true, active
end

function Service:IsRestricted(targetUserId: number, restrictionKey: string): (boolean, boolean)
	if not validUserId(targetUserId) or typeof(restrictionKey) ~= "string" or not VALID_RESTRICTIONS[restrictionKey] then
		return false, false
	end
	local now = os.clock()
	local cached = self.restrictionCache[targetUserId]
	if cached and cached.expiresAt > now then
		return true, cached.restricted[restrictionKey] == true
	end
	local ok, active = self:GetActive(targetUserId)
	if not ok then return false, false end
	local restrictedKeys: {[string]: boolean} = {}
	for _, item in ipairs(active) do
		if item.kind == "Restrict" and typeof(item.restrictions) == "table" then
			for _, key in ipairs(item.restrictions) do
				if VALID_RESTRICTIONS[key] then restrictedKeys[key] = true end
			end
		end
	end
	self.restrictionCache[targetUserId] = {expiresAt = now + 5, restricted = restrictedKeys}
	return true, restrictedKeys[restrictionKey] == true
end

function Service:RevokeRestrictions(actor: Player, targetUserId: number, reason: string): (boolean, string)
	if typeof(actor) ~= "Instance" or not actor:IsA("Player") or actor.Parent ~= Players
		or not validUserId(targetUserId) then return false, "Invalid actor or target." end
	local cleanReasonValue = cleanString(reason, MAX_REASON_LENGTH)
	if not cleanReasonValue then return false, "A bounded reversal reason is required." end
	if not hasPermission(self.authorization, actor, "GlobalModeration") then
		return false, "GlobalModeration permission is required."
	end
	local writeOk = self:_update(targetUserId, function(record)
		for caseId, item in pairs(record.active) do
			if typeof(item) == "table" and item.kind == "Restrict" and item.status == "Active" then
				record.active[caseId] = nil
				self:_appendHistory(record, {caseId = caseId, kind = "RestrictionReversed", status = "Reversed",
					actorUserId = actor.UserId, targetUserId = targetUserId, at = os.time(), reason = cleanReasonValue})
			end
		end
		return record
	end)
	if not writeOk then return false, "Restriction reversal could not be saved; restrictions remain in force." end
	self.restrictionCache[targetUserId] = nil
	self:_audit("RestrictionsReversed", actor.UserId, targetUserId, "unknown", cleanReasonValue)
	return true, "Active feature restrictions were reversed."
end

function Service:Unban(actor: Player, targetUserId: number, reason: string): (boolean, string)
	if typeof(actor) ~= "Instance" or not actor:IsA("Player") or actor.Parent ~= Players
		or not validUserId(targetUserId) then return false, "Invalid actor or target." end
	local cleanReasonValue = cleanString(reason, MAX_REASON_LENGTH)
	if not cleanReasonValue then return false, "A bounded reversal reason is required." end
	if not hasPermission(self.authorization, actor, "GlobalModeration") then
		return false, "GlobalModeration permission is required."
	end
	local fetchOk, existing = self:_readRecord(targetUserId)
	if not fetchOk then return false, "Punishment history is unavailable; unban denied." end
	local requiresSenior = false
	if typeof(existing) == "table" and typeof(existing.active) == "table" then
		for _, item in pairs(existing.active) do
			if typeof(item) == "table" and item.kind == "PermanentBan" and item.altPropagationRequested == true then
				requiresSenior = true
			end
		end
	end
	if requiresSenior and not hasPermission(self.authorization, actor, "IncidentResponse") then
		return false, "Senior IncidentResponse permission is required to reverse this propagated permanent ban."
	end
	local unbanOk, unbanError = pcall(function()
		Players:UnbanAsync({UserIds = {targetUserId}, ApplyToUniverse = true})
	end)
	if not unbanOk then return false, "Roblox UnbanAsync failed: " .. string.sub(tostring(unbanError), 1, 120) end
	local writeOk = self:_update(targetUserId, function(record)
		for caseId, item in pairs(record.active) do
			if typeof(item) == "table" and (item.kind == "TempBan" or item.kind == "PermanentBan") then
				record.active[caseId] = nil
				self:_appendHistory(record, {caseId = caseId, kind = "BanReversed", status = "Reversed",
					actorUserId = actor.UserId, targetUserId = targetUserId, at = os.time(), reason = cleanReasonValue})
			end
		end
		return record
	end)
	if not writeOk then
		self:_audit("UnbanPersistenceDegraded", actor.UserId, targetUserId, "unknown", "Roblox unban succeeded but evidence update failed.")
		return false, "Roblox unban succeeded, but evidence update failed. Escalate for reconciliation."
	end
	self.restrictionCache[targetUserId] = nil
	self:_audit("PunishmentReversed", actor.UserId, targetUserId, "unknown", cleanReasonValue)
	return true, "Active Roblox ban reversed and moderation history retained."
end

function Service:GetHistory(actor: Player, targetUserId: number, limit: number): (boolean, {any}?)
	if typeof(actor) ~= "Instance" or not actor:IsA("Player") or actor.Parent ~= Players
		or not validUserId(targetUserId) or typeof(limit) ~= "number" or limit % 1 ~= 0
		or limit < 1 or limit > 20 or not hasPermission(self.authorization, actor, "GlobalModeration") then
		return false, nil
	end
	local readOk, result = self:_readRecord(targetUserId)
	if not readOk then return false, nil end
	if typeof(result) ~= "table" or typeof(result.history) ~= "table" then return true, {} end
	local output = {}
	for index = #result.history, math.max(1, #result.history - limit + 1), -1 do
		local item = result.history[index]
		if typeof(item) == "table" then
			table.insert(output, {
				caseId = item.caseId, kind = item.kind, status = item.status,
				actorUserId = item.actorUserId, targetUserId = item.targetUserId,
				at = item.at, expiresAt = item.expiresAt, reason = item.reason,
				category = item.category, evidenceReference = item.evidenceReference,
				altPropagationRequested = item.altPropagationRequested == true,
			})
		end
	end
	self:_audit("ModerationHistoryViewed", actor.UserId, targetUserId, "history", "Bounded history query.")
	return true, output
end

-- Internal adapter for AccountRiskSignalService. It returns only normalized,
-- verified server-recorded outcomes and omits reasons and evidence text.
function Service:RecordVerifiedViolation(targetUserId: number, category: string, evidenceReference: string): boolean
	-- Trusted server-only callers must verify the violation before invoking this API.
	if not validUserId(targetUserId) or typeof(category) ~= "string" or #category < 1 or #category > 48
		or typeof(evidenceReference) ~= "string" or #evidenceReference < 1 or #evidenceReference > 96 then
		return false
	end
	local caseId = HttpService:GenerateGUID(false)
	local at = os.time()
	local ok, updated = self:_update(targetUserId, function(record)
		for _, existing in ipairs(record.history) do
			if typeof(existing) == "table" and existing.evidenceReference == evidenceReference then
				return record
			end
		end
		self:_appendHistory(record, {
			caseId = caseId, kind = "VerifiedViolation", status = "Active",
			actorUserId = 0, targetUserId = targetUserId, at = at,
			category = category, evidenceReference = evidenceReference,
		})
		return record
	end)
	if not ok or typeof(updated) ~= "table" then return false end
	for _, existing in ipairs(updated.history or {}) do
		if typeof(existing) == "table" and existing.evidenceReference == evidenceReference then
			self:_audit("VerifiedViolationRecorded", 0, targetUserId, tostring(existing.caseId or caseId), category)
			return true
		end
	end
	return false
end

function Service:GetRiskHistory(targetUserId: number, limit: number): (boolean, {any}?)
	if not validUserId(targetUserId) or typeof(limit) ~= "number" or limit % 1 ~= 0
		or limit < 1 or limit > MAX_HISTORY then return false, nil end
	local readOk, result = self:_readRecord(targetUserId)
	if not readOk then return false, nil end
	if typeof(result) ~= "table" or typeof(result.history) ~= "table" then return true, {} end
	local output = {}
	local seenCases: {[string]: boolean} = {}
	for index = #result.history, 1, -1 do
		local item = result.history[index]
		if typeof(item) == "table" and typeof(item.caseId) == "string" and not seenCases[item.caseId] then
			seenCases[item.caseId] = true
			-- A reversal/failed operation is the latest state for its case and
			-- must suppress the older active entry for that same case.
			if item.status == "Active" and typeof(item.at) == "number" then
				table.insert(output, {
					caseId = item.caseId, verified = true,
					category = if typeof(item.category) == "string" then item.category else item.kind,
					at = item.at, kind = item.kind,
				})
				if #output >= limit then break end
			end
		end
	end
	return true, output
end

return Service
