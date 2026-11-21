--!strict
-- Isolated receipt reward processing. Roblox receipt authority and durable
-- transaction ownership remain in their existing services.
return function(context: {[string]: any})
	local ServerStorage = context.ServerStorage
	local Players = context.Players
	local profiles = context.profiles
	local purchaseDiagnostics = context.purchaseDiagnostics
	local RunService = context.RunService
	local ControllerFunctions = context.ControllerFunctions
	local notify = context.notify
	local publishState = context.publishState
	local USE_STUDIO_MEMORY_PROFILES = context.USE_STUDIO_MEMORY_PROFILES
	local getStudioXpBoostState = context.getStudioXpBoostState
	local setStudioXpBoostState = context.setStudioXpBoostState
	local getReceiptTransactions = context.getReceiptTransactions

local function recordReceiptReplayEvent(eventType: string, userId: number, productId: number, severity: string, outcome: string)
	-- Never place PurchaseId or other receipt secrets in replay metadata.
	local replay = ServerStorage:FindFirstChild("ClubNeonSecurityReplay")
	if replay and replay:IsA("BindableFunction") then
		pcall(function()
			replay:Invoke("Record", eventType, userId, 0, severity, "PurchaseReceipt", {
				productId = productId,
				outcome = outcome,
			})
		end)
	end
end

local function processValidatedReceipt(receiptInfo: any, productData: any): Enum.ProductPurchaseDecision
	local userId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local receiptId = receiptInfo.PurchaseId
	print(string.format("[ClubMusic][PurchaseServer] ProcessReceiptReached | UserId=%s | ProductId=%s | PlaceId=%d | GameId=%d",
		tostring(userId), tostring(productId), game.PlaceId, game.GameId))
	purchaseDiagnostics.RecordPurchase("ServerReceipt", userId, productId, "ProcessReceiptReached", "Roblox dispatched an authoritative Developer Product receipt")
	recordReceiptReplayEvent("receipt_received", userId, productId, "Info", "RobloxReceiptCallback")
	local player = Players:GetPlayerByUserId(userId)
	local profile = profiles[userId]
	if not player or not profile then
		purchaseDiagnostics.RecordPurchase("ServerReceipt", userId, productId, "AwaitingPlayerProfile", "Player or loaded profile is not available; Roblox receipt will retry")
		recordReceiptReplayEvent("receipt_waiting_profile", userId, productId, "Info", "RetryPending")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if productData.type == "XPBoost" then
		if RunService:IsStudio() then
			-- Studio uses session-only boost state because the global service is intentionally disabled.
			local key = productData.multiplier
			if key ~= 2 and key ~= 4 then return Enum.ProductPurchaseDecision.NotProcessedYet end
			local currentMultiplier, currentExpiry = getStudioXpBoostState()
			local previousExpiry = if currentMultiplier == key then currentExpiry else os.time()
			local nextExpiry = math.min(os.time() + 30 * 24 * 60 * 60,
				math.max(os.time(), previousExpiry) + productData.duration)
			setStudioXpBoostState(key, nextExpiry)
			ControllerFunctions.setGlobalXPState(key, nextExpiry)
		else
			local activateOk, activated, expiry, effectiveMultiplier = ControllerFunctions.globalInvoke(
				"ActivateGlobalXPBoost", productData.multiplier, productData.duration, receiptId
			)
			if not activateOk or activated ~= true then
				warn("[ClubMusic] Global XP boost activation failed; receipt will be retried.")
				purchaseDiagnostics.RecordPurchase("ServerReceipt", userId, productId, "XPBoostActivationFailed", "Global XP service rejected or failed activation; Roblox receipt will retry")
				recordReceiptReplayEvent("receipt_activation_failed", userId, productId, "Warning", "RetryPending")
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			if typeof(expiry) == "number" and (effectiveMultiplier == 1 or effectiveMultiplier == 2 or effectiveMultiplier == 4) then
				ControllerFunctions.refreshGlobalXPBoost()
			end
		end
	end
	if productData.type == "XPBoost" then
		-- The global per-PurchaseId journal is authoritative for XP boosts.
		-- Do not write XP receipts into the legacy profile receipt map.
		purchaseDiagnostics.RecordPurchase("ServerReceipt", userId, productId, "ReceiptGranted", "Global XP boost activation completed")
		recordReceiptReplayEvent("receipt_granted", userId, productId, "Info", "XPBoost")
		notify(player, string.format("%dx global XP boost activated!", productData.multiplier), "ok")
		publishState(nil)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if not receiptTransactions then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local ok, alreadyProcessed, err = getReceiptTransactions():Commit(userId, receiptId, productData)
	if not ok then
		warn("[ClubMusic] Receipt persistence failed for userId " .. tostring(userId) .. " productId " .. tostring(productId) .. ": " .. tostring(err))
		purchaseDiagnostics.RecordPurchase("ServerReceipt", userId, productId, "ReceiptPersistenceFailed", tostring(err))
		recordReceiptReplayEvent("receipt_persistence_failed", userId, productId, "Warning", "RetryPending")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- A receipt already in the durable ledger was granted by an earlier callback/server.
	-- The loaded profile already contains its reward, so never apply it twice in memory.
	if alreadyProcessed then
		purchaseDiagnostics.RecordPurchase("ServerReceipt", userId, productId, "ReceiptDuplicate", "Receipt was already committed in the durable ledger")
		recordReceiptReplayEvent("receipt_duplicate", userId, productId, "Info", "AlreadyCommittedInDurableLedger")
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if profiles[userId] ~= profile then
		recordReceiptReplayEvent("receipt_profile_changed", userId, productId, "Warning", "RetryPending")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if USE_STUDIO_MEMORY_PROFILES then ControllerFunctions.applyReceiptToMemory(profile, productData) end
	purchaseDiagnostics.RecordPurchase("ServerReceipt", userId, productId, "ReceiptGranted", "Receipt persistence completed and reward application proceeded")
	recordReceiptReplayEvent("receipt_granted", userId, productId, "Info", "DurableReceiptCommitted")
	player:SetAttribute("Tickets", profile.tickets)
	player:SetAttribute("Coins", profile.coins)
	player:SetAttribute("Glowsticks", profile.glowsticks)
	player:SetAttribute("SkipTokens", profile.skipTokens)
	player:SetAttribute("NeonTrailUnlocked", profile.neonTrail)
	if productData.type == "TitleSlot" then ControllerFunctions.applyTitleAttributes(player, profile) end

	if productData.type == "Donation" then
		local amount = math.max(0, math.floor(tonumber(productData.amount) or 0))
		local perk = productData.perk or "Donation"
		if perk == "Coconut" then ControllerFunctions.broadcast(string.format("🌴 %s sent a Coconut Tip! (+%d Tickets)", player.DisplayName, math.floor(amount * 1.5)), "info")
		elseif perk == "Pineapple" then ControllerFunctions.broadcast(string.format("🎆 %s launched a Pineapple Firework burst!", player.DisplayName), "ok")
		elseif perk == "Neon Torch" then ControllerFunctions.broadcast(string.format("🎊 %s filled the dancefloor with Stage Confetti!", player.DisplayName), "ok")
		elseif perk == "Volcano" then ControllerFunctions.broadcast(string.format("🔥 %s activated the Volcano Light Show!", player.DisplayName), "warn")
		elseif perk == "Island Legend" then ControllerFunctions.broadcast(string.format("👑 LEGENDARY: %s is displayed on the Big Stage Screens!", player.DisplayName), "info")
		elseif perk == "Island Royalty" then ControllerFunctions.broadcast(string.format("👑 ROYAL CELEBRATION: %s has supported the island with an extraordinary gift!", player.DisplayName), "info")
		elseif perk == "Club Neon Legacy" then ControllerFunctions.broadcast(string.format("✨ SULTAN'S LEGACY: %s has made the ultimate island contribution!", player.DisplayName), "ok") end
	elseif productData.type == "Item" then
		notify(player, string.format("Purchase Successful: %s acquired!", productData.name or "Item"), "ok")
	elseif productData.type == "TitleSlot" then
		notify(player, string.format("Title slot %d unlocked!", profile.unlockedSlots), "ok")
	elseif productData.type == "XPBoost" then
		notify(player, string.format("%dx global XP boost activated!", productData.multiplier), "ok")
	end
	publishState(nil)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
	return {
		RecordReceiptReplayEvent = recordReceiptReplayEvent,
		ProcessValidatedReceipt = processValidatedReceipt,
	}
end
