--!strict
-- Phase 32 composition root. Require only from a server Script.
-- This composes existing SecurityCore Authorization with the Phase 32 services;
-- it does not create remotes or grant client access.
local Players = game:GetService("Players")
local Authorization = require(script.Parent:WaitForChild("Authorization"))
local ModerationPunishmentService = require(script.Parent:WaitForChild("ModerationPunishmentService"))
local AccountRiskSignalService = require(script.Parent:WaitForChild("AccountRiskSignalService"))
local ChatAbuseDetectionService = require(script.Parent:WaitForChild("ChatAbuseDetectionService"))

local Bundle = {}
Bundle.__index = Bundle

function Bundle.new(options: {[string]: any}?)
	local config = if typeof(options) == "table" then options else {}
	local authorization = Authorization.GetShared()
	local punishments = ModerationPunishmentService.new({
		authorization = authorization,
		dataStoreName = config.dataStoreName,
		onAudit = config.onAudit,
		onNotify = config.onNotify,
	})
	local risk = AccountRiskSignalService.new({
		authorization = authorization,
		getAuthorizedHistory = function(userId: number, limit: number)
			return punishments:GetRiskHistory(userId, limit)
		end,
		maxHistory = config.maxRiskHistory,
	})
	local chat = ChatAbuseDetectionService.new({
		onVerifiedViolation = function(userId: number, category: string, evidenceReference: string)
			return punishments:RecordVerifiedViolation(userId, category, evidenceReference)
		end,
	})
	return setmetatable({
		authorization = authorization,
		Punishments = punishments,
		Risk = risk,
		Chat = chat,
	}, Bundle)
end

function Bundle:Issue(actor: Player, targetUserId: number, action: {[string]: any})
	return self.Punishments:Issue(actor, targetUserId, action)
end

function Bundle:Unban(actor: Player, targetUserId: number, reason: string)
	return self.Punishments:Unban(actor, targetUserId, reason)
end

function Bundle:RevokeRestrictions(actor: Player, targetUserId: number, reason: string)
	return self.Punishments:RevokeRestrictions(actor, targetUserId, reason)
end

function Bundle:RecordVerifiedViolation(player: Player, category: string, evidenceReference: string)
	return self.Chat:RecordVerifiedViolation(player, category, evidenceReference)
end

function Bundle:GetHistory(actor: Player, targetUserId: number, limit: number)
	return self.Punishments:GetHistory(actor, targetUserId, limit)
end

function Bundle:GetRiskSignals(actor: Player, targetUserId: number)
	return self.Risk:GetSignals(actor, targetUserId)
end

function Bundle:FilterBroadcast(player: Player, rawText: any)
	return self.Chat:FilterBroadcast(player, rawText)
end

function Bundle:IsRestricted(targetUserId: number, restrictionKey: string)
	return self.Punishments:IsRestricted(targetUserId, restrictionKey)
end

function Bundle:Destroy()
	self.Chat:Destroy()
end

return Bundle
