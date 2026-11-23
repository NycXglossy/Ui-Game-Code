--!strict
-- Client-side purchase prompt attribution for Club Neon staff diagnostics.
-- This is telemetry only; Developer Product receipts remain server-authoritative.
return function(dependencies: {[string]: any})
	local Players: Players = dependencies.Players
	local MarketplaceService: MarketplaceService = dependencies.MarketplaceService
	local ReplicatedStorage: ReplicatedStorage = dependencies.ReplicatedStorage
	local purchaseDiagnosticRemote: RemoteEvent? = nil
	local pendingClubMusicPrompts: {[string]: number} = {}

	local function promptKey(promptType: string, itemId: number): string
		return promptType .. ":" .. tostring(itemId)
	end

	if not MarketplaceService:GetAttribute("ClubMusicPurchaseDiagnosticsConnected") then
		MarketplaceService:SetAttribute("ClubMusicPurchaseDiagnosticsConnected", true)
		local purchaseRemotes = ReplicatedStorage:WaitForChild("ClubMusicRemotes", 15)
		local remote = if purchaseRemotes then purchaseRemotes:FindFirstChild("PurchaseDiagnostic") else nil
		purchaseDiagnosticRemote = if remote and remote:IsA("RemoteEvent") then remote else nil
		local function reportPrompt(promptType: string, itemId: number, wasPurchased: boolean)
			if purchaseDiagnosticRemote then
				purchaseDiagnosticRemote:FireServer(promptType, itemId, wasPurchased)
			end
		end
		MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, wasPurchased: boolean)
			if userId ~= Players.LocalPlayer.UserId then return end
			local key = promptKey("DeveloperProduct", productId)
			if not pendingClubMusicPrompts[key] then return end
			pendingClubMusicPrompts[key] = nil
			print(string.format("[ClubMusic][PurchaseClient] DeveloperProductPromptFinished | UserId=%d | ProductId=%d | Purchased=%s | PlaceId=%d | GameId=%d",
				userId, productId, tostring(wasPurchased), game.PlaceId, game.GameId))
			reportPrompt("DeveloperProduct", productId, wasPurchased)
		end)
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, wasPurchased: boolean)
			if player ~= Players.LocalPlayer then return end
			local key = promptKey("GamePass", passId)
			if not pendingClubMusicPrompts[key] then return end
			pendingClubMusicPrompts[key] = nil
			print(string.format("[ClubMusic][PurchaseClient] GamePassPromptFinished | UserId=%d | PassId=%d | Purchased=%s | PlaceId=%d | GameId=%d",
				player.UserId, passId, tostring(wasPurchased), game.PlaceId, game.GameId))
			reportPrompt("GamePass", passId, wasPurchased)
		end)
	end

	local function reportPromptRequest(promptType: string, itemId: number, source: string)
		local key = promptKey(promptType, itemId)
		pendingClubMusicPrompts[key] = os.clock()
		-- Expire abandoned prompts so later unrelated prompts cannot be attributed to Club Neon.
		task.delay(120, function()
			local requestedAt = pendingClubMusicPrompts[key]
			if requestedAt and os.clock() - requestedAt >= 120 then
				pendingClubMusicPrompts[key] = nil
			end
		end)
		if purchaseDiagnosticRemote then
			purchaseDiagnosticRemote:FireServer(promptType, itemId, "PromptRequested", source)
		end
	end

	return {
		reportPromptRequest = reportPromptRequest,
	}
end
