--!strict
-- Prototype monetization boundary (GOAL §12). There are deliberately no real product ids here:
-- 0 is a sentinel placeholder that can never be charged by Roblox. The only configured product is
-- non-random convenience access to Siege Division, matching the earnable War Credits unlock.
local Monetization = {}

Monetization.LivePaymentsEnabled = false
Monetization.PlaceholderProductId = 0

Monetization.Products = {
	{
		id = "SiegeDivisionAccess",
		displayName = "Siege Division Access",
		productId = Monetization.PlaceholderProductId,
		kind = "requisitionUnlock",
		grantRequisition = "SiegeDivision",
		entitlement = "SiegeDivision",
		nonRandom = true,
		approvedConvenience = true,
		enabled = false,
		placeholder = true,
		description = "Prototype placeholder for permanent access to the non-random Siege Division requisition.",
	},
}

Monetization.ById = {}
Monetization.ByProductId = {}
for _, product in ipairs(Monetization.Products) do
	Monetization.ById[product.id] = product
	Monetization.ByProductId[product.productId] = product
end

function Monetization.get(id: string)
	return Monetization.ById[id]
end

function Monetization.productForId(productId: number)
	return Monetization.ByProductId[productId]
end

return Monetization
