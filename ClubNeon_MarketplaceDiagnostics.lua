--!strict
-- Non-blocking catalog diagnostics for configured Club Neon monetization IDs.
return function(deps: {[string]: any})
	local MarketplaceService = deps.MarketplaceService
	local CONFIG = deps.CONFIG
	local Enum = deps.Enum
	task.spawn(function()
		local configured = {
			{ label = "VIP Game Pass", id = CONFIG.VipGamePassId, infoType = Enum.InfoType.GamePass },
			{ label = "VVIP Game Pass", id = CONFIG.VvipGamePassId, infoType = Enum.InfoType.GamePass },
			{ label = "Club Neon Game Pass", id = CONFIG.ClubNeonPassId, infoType = Enum.InfoType.GamePass },
			{ label = "2x Personal XP Game Pass", id = CONFIG.PersonalXP2xPassId, infoType = Enum.InfoType.GamePass },
			{ label = "4x Personal XP Game Pass", id = CONFIG.PersonalXP4xPassId, infoType = Enum.InfoType.GamePass },
			{ label = "Island Mount Game Pass", id = CONFIG.MountPassId, infoType = Enum.InfoType.GamePass },
			{ label = "Island Companion Game Pass", id = CONFIG.CompanionPassId, infoType = Enum.InfoType.GamePass },
			{ label = "Stage & Club Lighting Game Pass", id = CONFIG.StageClubLightingPassId, infoType = Enum.InfoType.GamePass },
			{ label = "2x XP Developer Product", id = CONFIG.XPBoost2xProductId, infoType = Enum.InfoType.Product },
			{ label = "4x XP Developer Product", id = CONFIG.XPBoost4xProductId, infoType = Enum.InfoType.Product },
			{ label = "Title Slot 2 Developer Product", id = CONFIG.TitleSlotProductIds[2], infoType = Enum.InfoType.Product },
			{ label = "Title Slot 3 Developer Product", id = CONFIG.TitleSlotProductIds[3], infoType = Enum.InfoType.Product },
			{ label = "Coconut Donation Developer Product", id = CONFIG.DonationProductIds.Coconut, infoType = Enum.InfoType.Product },
			{ label = "Pineapple Donation Developer Product", id = CONFIG.DonationProductIds.Pineapple, infoType = Enum.InfoType.Product },
			{ label = "Neon Torch Donation Developer Product", id = CONFIG.DonationProductIds.NeonTorch, infoType = Enum.InfoType.Product },
			{ label = "Volcano Donation Developer Product", id = CONFIG.DonationProductIds.Volcano, infoType = Enum.InfoType.Product },
			{ label = "Island Legend Donation Developer Product", id = CONFIG.DonationProductIds.IslandLegend, infoType = Enum.InfoType.Product },
			{ label = "Island Royalty Donation Developer Product", id = CONFIG.DonationProductIds.IslandRoyalty, infoType = Enum.InfoType.Product },
			{ label = "Club Neon Legacy Donation Developer Product", id = CONFIG.DonationProductIds.ClubNeonLegacy, infoType = Enum.InfoType.Product },
		}
		for _, entry in ipairs(configured) do
			if typeof(entry.id) ~= "number" or entry.id <= 0 then
				warn(string.format("[ClubMusic][MarketplaceCheck] %s has an invalid/unconfigured ID.", entry.label))
				continue
			end
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(entry.id, entry.infoType)
			end)
			if not ok or typeof(info) ~= "table" then
				warn(string.format("[ClubMusic][MarketplaceCheck] LOOKUP_FAILED | %s | ID=%d | Error=%s",
					entry.label, entry.id, string.sub(tostring(info), 1, 220)))
				continue
			end
			local creator = if typeof(info.Creator) == "table" then info.Creator else {}
			local creatorType = tostring(creator.CreatorType or "unknown")
			local creatorId = tostring(creator.CreatorTargetId or creator.Id or "unknown")
			local saleStatus = if info.IsForSale == true then "ON_SALE" elseif info.IsForSale == false then "NOT_FOR_SALE" else "UNKNOWN"
			local price = tostring(info.PriceInRobux or info.Price or "not-returned")
			local name = tostring(info.Name or info.ProductName or "unnamed")
			print(string.format(
				"[ClubMusic][MarketplaceCheck] LOOKUP_OK | %s | ID=%d | Name=%s | CreatorType=%s | CreatorId=%s | Sale=%s | Price=%s | ExpectedGroup=%d",
				entry.label, entry.id, name, creatorType, creatorId, saleStatus, price, CONFIG.GroupId
			))
		end
	end)
end
