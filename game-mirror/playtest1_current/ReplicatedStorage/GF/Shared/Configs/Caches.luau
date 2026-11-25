--!nonstrict
-- Four cache tiers. A tier decides how many independent Augments a cache yields and how the rarity of
-- those Augments is weighted; the Augments themselves still come from the category pools.
local Caches = {}

Caches.Tiers = {
	{
		id = "Common", displayName = "Common Cache", augments = 1,
		weights = { Common = 82, Rare = 16, Epic = 1.9, Legendary = 0.1 },
		enemyChance = { infantry = 0.01, heavy = 0.04, commander = 0.07 },
		color = Color3.fromRGB(150, 158, 170),
	},
	{
		id = "Rare", displayName = "Rare Cache", augments = 2,
		weights = { Common = 48, Rare = 43, Epic = 8, Legendary = 1 },
		enemyChance = { infantry = 0.01, heavy = 0.05, commander = 0.09 },
		color = Color3.fromRGB(96, 186, 255),
	},
	{
		id = "Epic", displayName = "Epic Cache", augments = 3,
		weights = { Common = 18, Rare = 48, Epic = 30, Legendary = 4 },
		enemyChance = { infantry = 0.00, heavy = 0.02, commander = 0.05 },
		color = Color3.fromRGB(186, 128, 255),
	},
	{
		id = "Legendary", displayName = "Legendary Cache", augments = 4,
		weights = { Common = 0, Rare = 30, Epic = 55, Legendary = 15 },
		enemyChance = { infantry = 0.00, heavy = 0.00, commander = 0.00 },
		color = Color3.fromRGB(255, 196, 96),
	},
}

Caches.ById = {}
for _, tier in Caches.Tiers do
	Caches.ById[tier.id] = tier
end

function Caches.get(id: string)
	return Caches.ById[id]
end

-- Weighted rarity pick for one cache slot.
function Caches.rollRarity(tier: any, rng: (number) -> number?): string
	local weights = tier and tier.weights or { Common = 1 }
	local total = 0
	for _, weight in pairs(weights) do
		total += weight
	end
	if total <= 0 then
		return "Common"
	end
	local picker = rng or math.random
	local target = picker() * total
	local acc = 0
	local last = "Common"
	for rarity, weight in pairs(weights) do
		acc += weight
		last = rarity
		if target <= acc then
			return rarity
		end
	end
	return last
end

return Caches

