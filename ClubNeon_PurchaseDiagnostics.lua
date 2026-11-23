--!strict
-- Club Neon bounded, server-local purchase and moderation telemetry.
-- Client prompt reports are unverified telemetry; only server receipt callbacks are authoritative.
return function(deps: any)
	local Players = deps.Players
	local CONFIG = deps.CONFIG
	local purchaseDiagnosticRemote = deps.PurchaseDiagnosticRemote

	local purchaseDiagnosticEntries: {any} = {}
	local purchaseDiagnosticRate: {[number]: {windowAt: number, count: number}} = {}
	local PURCHASE_DIAGNOSTIC_CAPACITY = 30
	local purchaseDiagnosticStats = {
		totalEvents = 0, promptEvents = 0, receiptEvents = 0, receiptCallbacks = 0,
		granted = 0, pending = 0, failures = 0, duplicates = 0, lastOutcome = nil, lastAt = nil,
		lastSuccessAt = nil, lastPendingAt = nil, lastFailureAt = nil,
	}
	local moderationDiagnosticStats = {
		totalLookups = 0, joinLookups = 0, retryLookups = 0,
		successfulLookups = 0, failedLookups = 0, pendingChecks = 0,
		bannedResults = 0, blockedResults = 0, lastLookupAt = nil,
		lastSuccessAt = nil, lastFailureAt = nil,
	}

	local api = {
		PurchaseEntries = purchaseDiagnosticEntries,
		PurchaseStats = purchaseDiagnosticStats,
		ModerationStats = moderationDiagnosticStats,
	}

	function api.RecordModeration(source: string, succeeded: boolean, banned: boolean?, blocked: boolean?)
		moderationDiagnosticStats.totalLookups += 1
		if source == "Join" then moderationDiagnosticStats.joinLookups += 1
		else moderationDiagnosticStats.retryLookups += 1 end
		moderationDiagnosticStats.lastLookupAt = os.time()
		if succeeded then
			moderationDiagnosticStats.successfulLookups += 1
			moderationDiagnosticStats.lastSuccessAt = moderationDiagnosticStats.lastLookupAt
			if banned == true then moderationDiagnosticStats.bannedResults += 1 end
			if blocked == true then moderationDiagnosticStats.blockedResults += 1 end
		else
			moderationDiagnosticStats.failedLookups += 1
			moderationDiagnosticStats.pendingChecks += 1
			moderationDiagnosticStats.lastFailureAt = moderationDiagnosticStats.lastLookupAt
		end
	end

	function api.RecordPurchase(source: string, userId: number, itemId: number, outcome: string, detail: string?)
		local now = os.time()
		purchaseDiagnosticStats.totalEvents += 1
		purchaseDiagnosticStats.lastOutcome = string.sub(outcome, 1, 48)
		purchaseDiagnosticStats.lastAt = now
		if source == "ServerReceipt" then
			purchaseDiagnosticStats.receiptEvents += 1
			if outcome == "ProcessReceiptReached" then purchaseDiagnosticStats.receiptCallbacks += 1 end
		else
			purchaseDiagnosticStats.promptEvents += 1
		end
		if outcome == "ReceiptGranted" then
			purchaseDiagnosticStats.granted += 1
			purchaseDiagnosticStats.lastSuccessAt = now
		elseif outcome == "AwaitingPlayerProfile" or outcome == "XPBoostActivationFailed"
			or outcome == "ReceiptPersistenceFailed" or outcome == "ReceiptConcurrentRetry"
			or outcome == "ReceiptConcurrencyCapacity" then
			purchaseDiagnosticStats.pending += 1
			purchaseDiagnosticStats.lastPendingAt = now
			if outcome == "XPBoostActivationFailed" or outcome == "ReceiptPersistenceFailed" then
				purchaseDiagnosticStats.failures += 1
				purchaseDiagnosticStats.lastFailureAt = now
			end
		elseif outcome == "RejectedUnregisteredProduct" or outcome == "MalformedReceipt"
			or outcome == "ReceiptHandlerFailed" or outcome == "ReceiptInvalidDecision" then
			purchaseDiagnosticStats.failures += 1
			purchaseDiagnosticStats.lastFailureAt = now
		elseif outcome == "ReceiptDuplicate" then
			purchaseDiagnosticStats.duplicates += 1
		end
		table.insert(purchaseDiagnosticEntries, {
			at = os.time(), source = source, userId = userId, itemId = itemId,
			outcome = string.sub(outcome, 1, 48),
			detail = string.sub(tostring(detail or ""), 1, 140),
		})
		while #purchaseDiagnosticEntries > PURCHASE_DIAGNOSTIC_CAPACITY do
			table.remove(purchaseDiagnosticEntries, 1)
		end
	end

	local function classifyConfiguredPurchaseId(promptType: string, itemId: number): string
		if promptType == "GamePass" then
			if itemId == CONFIG.VipGamePassId or itemId == CONFIG.VvipGamePassId or itemId == CONFIG.ClubNeonPassId
				or itemId == CONFIG.PersonalXP2xPassId or itemId == CONFIG.PersonalXP4xPassId
				or itemId == CONFIG.MountPassId or itemId == CONFIG.CompanionPassId
				or itemId == CONFIG.StageClubLightingPassId then
				return "ConfiguredClubMusicGamePass"
			end
		elseif itemId == CONFIG.XPBoost2xProductId or itemId == CONFIG.XPBoost4xProductId
			or itemId == CONFIG.TitleSlotProductIds[2] or itemId == CONFIG.TitleSlotProductIds[3]
			or itemId == 0 or itemId == 0 or itemId == 0
			or itemId == 0 or itemId == 0 or itemId == 0
			or itemId == 0 then
			return "ConfiguredClubMusicDeveloperProduct"
		end
		return "UnrecognizedByClubMusicConfig"
	end

	purchaseDiagnosticRemote.OnServerEvent:Connect(function(player: Player, promptType: any, itemId: any, eventKind: any, payload: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players
			or (promptType ~= "GamePass" and promptType ~= "DeveloperProduct")
			or typeof(itemId) ~= "number" or not (itemId > 0 and itemId <= 9007199254740991) or itemId % 1 ~= 0 then
			return
		end
		local isLegacyCallback = typeof(eventKind) == "boolean"
		local isPromptRequest = eventKind == "PromptRequested" and typeof(payload) == "string" and #payload <= 128
		local isPromptFinished = eventKind == "PromptFinished" and typeof(payload) == "boolean"
		if not isLegacyCallback and not isPromptRequest and not isPromptFinished then return end

		local now = os.clock()
		local rate = purchaseDiagnosticRate[player.UserId]
		if not rate or now - rate.windowAt >= 60 then
			rate = {windowAt = now, count = 0}
			purchaseDiagnosticRate[player.UserId] = rate
		end
		if rate.count >= 12 then return end
		rate.count += 1

		local idClass = classifyConfiguredPurchaseId(promptType, itemId)
		if isPromptRequest then
			api.RecordPurchase("ClientPromptRequestUnverified", player.UserId, itemId, "PromptRequested",
				promptType .. " | source=" .. string.sub(payload, 1, 48) .. " | " .. idClass .. "; request telemetry only")
		else
			local wasPurchased = if isLegacyCallback then eventKind else payload
			api.RecordPurchase("ClientPromptUnverified", player.UserId, itemId,
				if wasPurchased then "PromptReportedPurchased" else "PromptClosedWithoutPurchase",
				promptType .. " prompt callback | " .. idClass .. "; client telemetry is not proof of a completed transaction")
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		purchaseDiagnosticRate[player.UserId] = nil
	end)

	return api
end
