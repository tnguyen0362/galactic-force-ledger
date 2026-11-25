--!strict
-- Galactic War strategic layer config (spec section 13): eight territories, two per biome, connected
-- map. Each territory carries liberation progress 0-100, a state and a battlefront flag; neighbors
-- open as fronts flip Human. Values here are static geography - the live numbers persist server-side.
local Campaign = {}

Campaign.Territories = {
	{ id = "VerdantReach", biome = "forest", neighbors = { "ThornBasin", "AshenDivide" } },
	{ id = "ThornBasin", biome = "forest", neighbors = { "VerdantReach", "IronMarch" } },
	{ id = "AshenDivide", biome = "ash", neighbors = { "VerdantReach", "RedMesa", "Frostline" } },
	{ id = "RedMesa", biome = "ash", neighbors = { "AshenDivide", "WhiteRidge" } },
	{ id = "Frostline", biome = "frost", neighbors = { "AshenDivide", "WhiteRidge", "IronMarch" } },
	{ id = "WhiteRidge", biome = "frost", neighbors = { "RedMesa", "Frostline", "FoundryBelt" } },
	{ id = "IronMarch", biome = "iron", neighbors = { "ThornBasin", "Frostline", "FoundryBelt" } },
	{ id = "FoundryBelt", biome = "iron", neighbors = { "WhiteRidge", "IronMarch" } },
}

Campaign.ById = {}
for _, territory in ipairs(Campaign.Territories) do
	Campaign.ById[territory.id] = territory
end

-- Campaign point formula constants: round(10 * difficultyWeight * typeWeight * (1 + .20 * (Pqualified - 1)))
Campaign.DifficultyWeight = { Easy = 0.8, Normal = 1, Hard = 1.35, Extreme = 1.7 }
Campaign.FamilyWeight = { Sabotage = 1, Recovery = 1, Defense = 1, Elimination = 1, Conquest = 1.25 }

function Campaign.pointsFor(difficulty: string?, family: string?, pqualified: number?): number
	local dw = Campaign.DifficultyWeight[tostring(difficulty or "Normal")] or 1
	local fw = Campaign.FamilyWeight[tostring(family or "Sabotage")] or 1
	local p = math.clamp(math.floor(tonumber(pqualified) or 1), 1, 4)
	return math.floor(10 * dw * fw * (1 + 0.20 * (p - 1)) + 0.5)
end

-- Cold-start phase target (spec: initial 10/day -> 200 points) until trailing 7-day observation exists.
Campaign.ColdStartTarget = 200
-- Human defense phase cadence in seconds (72h).
Campaign.DefensePhaseSeconds = 72 * 3600

return Campaign
