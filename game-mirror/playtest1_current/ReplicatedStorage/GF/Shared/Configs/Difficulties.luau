--!strict
local Difficulties = {}

Difficulties.List = {
	{
		id = "Easy", displayName = "Easy", friendlyFire = 0, unlockRank = 1, rewardMultiplier = 1.0,
		enemyBudget = 8, eliteFrequency = 0.10, reactionMultiplier = 1.4,
		ticketBase = 3, ticketPerPlayer = 2,
	},
	{
		id = "Normal", displayName = "Normal", friendlyFire = 0, unlockRank = 1, rewardMultiplier = 1.7,
		enemyBudget = 12, eliteFrequency = 0.35, reactionMultiplier = 1.0,
		ticketBase = 2, ticketPerPlayer = 2,
	},
	{
		id = "Hard", displayName = "Hard", friendlyFire = 0.5, unlockRank = 6, rewardMultiplier = 2.6,
		enemyBudget = 16, eliteFrequency = 0.70, reactionMultiplier = 0.8,
		ticketBase = 1, ticketPerPlayer = 1,
	},
	{
		id = "Extreme", displayName = "Extreme", friendlyFire = 1.0, unlockRank = 14, rewardMultiplier = 3.5,
		enemyBudget = 18, eliteFrequency = 1.0, reactionMultiplier = 0.65,
		ticketBase = 0, ticketPerPlayer = 1,
	},
}

Difficulties.ById = {}
for _, d in Difficulties.List do Difficulties.ById[d.id] = d end

function Difficulties.get(id: string)
	return Difficulties.ById[id]
end

-- Reinforcement tickets = base + perPlayer * squadSize (spec: Easy 3+2P, Normal 2+2P, Hard 1+P, Extreme P)
function Difficulties.ticketsFor(difficultyId: string, playerCount: number): number
	local d = Difficulties.ById[difficultyId]
	if not d then return 0 end
	local n = math.clamp(playerCount, 1, 4)
	return d.ticketBase + d.ticketPerPlayer * n
end

-- S06-032 authored combat modifiers: (HP, damage, attack cadence, reinforcement pressure). Cadence is a RATE
-- multiplier, so a value below 1 means slower attacks (Easy .85) - intervals are divided by it.
local MODIFIERS = {
	Easy = { hp = 0.70, damage = 0.60, cadence = 0.85, pressure = 0.65 },
	Normal = { hp = 1, damage = 1, cadence = 1, pressure = 1 },
	Hard = { hp = 1.50, damage = 1.30, cadence = 1.10, pressure = 1.25 },
	Extreme = { hp = 2, damage = 1.60, cadence = 1.20, pressure = 1.50 },
}
-- Direct weapon/explosive damage scale applied to allies (GOAL §3: Easy/Normal off, Hard 50%, Extreme 100%).
function Difficulties.friendlyFireFor(difficultyId: string?): number
	local d = Difficulties.ById[tostring(difficultyId or "Normal")]
	return d and tonumber(d.friendlyFire) or 0
end

function Difficulties.modifiersFor(difficultyId: string?)
	return MODIFIERS[tostring(difficultyId or "Normal")] or MODIFIERS.Normal
end
return Difficulties

