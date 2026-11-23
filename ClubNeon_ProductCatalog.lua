--!strict
-- ServerStorage/ClubNeon_ProductCatalog.lua
-- Builds the controller-owned developer-product lookup without owning receipt processing.

type ProductData = {
	type: "Donation" | "Item" | "TitleSlot" | "XPBoost",
	productId: number?,
	perk: string?,
	amount: number?,
	name: string?,
	costCoins: number?,
	slot: number?,
	multiplier: number?,
	duration: number?,
}

local ProductCatalog = {}

function ProductCatalog.new(CONFIG: any, titleSlotCount: number): {[number]: ProductData}
	-- Replace each 0 with a UNIQUE Developer Product ID from Creator Dashboard.
	-- A zero ID is intentionally ignored so unconfigured products cannot collide.
	local productIds = {
		-- Donations / Tips
		Coconut = CONFIG.DonationProductIds.Coconut,
		Pineapple = CONFIG.DonationProductIds.Pineapple,
		NeonTorch = CONFIG.DonationProductIds.NeonTorch,
		Volcano = CONFIG.DonationProductIds.Volcano,
		IslandLegend = CONFIG.DonationProductIds.IslandLegend,
		IslandRoyalty = CONFIG.DonationProductIds.IslandRoyalty,
		ClubNeonLegacy = CONFIG.DonationProductIds.ClubNeonLegacy,

		-- Shop Items
		Glowsticks = 0,
		NeonMask = 0,
		NeonAura = 0,
		NeonLei = 0,
		LEDShades = 0,
		XPBoost2x = CONFIG.XPBoost2xProductId,
		XPBoost4x = CONFIG.XPBoost4xProductId,
	}

	local productMap: {[number]: ProductData} = {}
	local function registerProduct(productId: number, data: ProductData)
		if productId <= 0 then
			return -- Not configured yet.
		end
		if productMap[productId] then
			error(string.format("[ClubMusic] Duplicate Developer Product ID: %d", productId))
		end
		data.productId = productId
		productMap[productId] = data
	end

	-- Donations / Tips
	registerProduct(productIds.Coconut, {
		type = "Donation", perk = "Coconut", amount = 10,
	})
	registerProduct(productIds.Pineapple, {
		type = "Donation", perk = "Pineapple", amount = 50,
	})
	registerProduct(productIds.NeonTorch, {
		type = "Donation", perk = "Neon Torch", amount = 100,
	})
	registerProduct(productIds.Volcano, {
		type = "Donation", perk = "Volcano", amount = 500,
	})
	registerProduct(productIds.IslandLegend, {
		type = "Donation", perk = "Island Legend", amount = 1000,
	})
	registerProduct(productIds.IslandRoyalty, {
		type = "Donation", perk = "Island Royalty", amount = 5000,
	})
	registerProduct(productIds.ClubNeonLegacy, {
		type = "Donation", perk = "Club Neon Legacy", amount = 10000,
	})

	-- Shop Items
	registerProduct(productIds.Glowsticks, {
		type = "Item", name = "Glowsticks", costCoins = 75,
	})
	registerProduct(productIds.NeonMask, {
		type = "Item", name = "Neon Mask", costCoins = 250,
	})
	registerProduct(productIds.NeonAura, {
		type = "Item", name = "Neon Aura", costCoins = 600,
	})
	registerProduct(productIds.NeonLei, {
		type = "Item", name = "Neon Lei", costCoins = 150,
	})
	registerProduct(productIds.LEDShades, {
		type = "Item", name = "LED Shades", costCoins = 320,
	})
	registerProduct(productIds.XPBoost2x, { type = "XPBoost", multiplier = 2, duration = 900, name = "2x XP Boost" })
	registerProduct(productIds.XPBoost4x, { type = "XPBoost", multiplier = 4, duration = 1800, name = "4x XP Boost" })

	-- Title slots (slot 1 is free; slots 2 and 3 are paid)
	for slotNumber = 2, titleSlotCount do
		registerProduct(CONFIG.TitleSlotProductIds[slotNumber] or 0, {
			type = "TitleSlot", slot = slotNumber, name = "Title Slot " .. tostring(slotNumber),
		})
	end

	return productMap
end

return ProductCatalog
