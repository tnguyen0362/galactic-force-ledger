--!strict
local Enemies = {}

Enemies.List = {
	{
		id = "Rifleman", displayName = "Ascendancy Rifleman", telegraph = 0.55,
		armorFactor = 1.0,
		tier = "Standard",
		health = 240, shield = 80, damage = 8, attackRange = 70, attackCooldown = 1.6,
		speed = 13, sightRange = 110, lootScrap = 2, lootEnergyChance = 0.10, lootTechChance = 0.0,
		behavior = "GuardCover", weakPointMultiplier = 1.0, hitProb = 0.42,
	 damage = 8,
		burst = { count = 3, interval = 0.18 },
	},
	{
		id = "Scout", displayName = "Ascendancy Scout", telegraph = 0.55,
		armorFactor = 1.0,
		tier = "Standard",
		health = 210, shield = 60, damage = 6, attackRange = 46, attackCooldown = 1.1,
		speed = 18, sightRange = 110, lootScrap = 1, lootEnergyChance = 0.05, lootTechChance = 0.0,
		behavior = "FlankBeacon", weakPointMultiplier = 1.2, hitProb = 0.38,
	 damage = 6,
		burst = { count = 4, interval = 0.15 },
	},
	{
		id = "Marksman", displayName = "Ascendancy Marksman", telegraph = 0.55,
		chargeTime = 1.1, -- spec S11: marksman warning must be >=1s of visible targeting beam
		armorFactor = 1.0,
		tier = "Specialist",
		health = 210, shield = 60, damage = 38, attackRange = 180, attackCooldown = 3.0,
		speed = 11, sightRange = 200, lootScrap = 2, lootEnergyChance = 0.15, lootTechChance = 0.02,
		behavior = "ChargedShot", weakPointMultiplier = 1.4, hitProb = 0.75,
		burst = { count = 1, interval = 0 },
	},
	{
		id = "Heavy", displayName = "Ascendancy Heavy", telegraph = 0.55,
		chargeTime = 1.4, recovery = 4.0,
		armorFactor = 0.75,
		tier = "Elite",
		health = 620, shield = 180, damage = 32, attackRange = 80, attackCooldown = 2.6,
		speed = 8, sightRange = 120, lootScrap = 4, lootEnergyChance = 0.60, lootTechChance = 0.10,
		behavior = "AreaBurst", weakPointMultiplier = 2.0, hitProb = 0.5,
		burst = { count = 1, interval = 0 },
	},
	{
		id = "Officer", displayName = "Ascendancy Officer", telegraph = 0.55,
		armorFactor = 0.9,
		tier = "Elite",
		health = 420, shield = 160, damage = 12, attackRange = 90, attackCooldown = 2.2,
		speed = 12, sightRange = 130, lootScrap = 3, lootEnergyChance = 0.35, lootTechChance = 0.20,
		behavior = "CommandSquad", weakPointMultiplier = 1.5, hitProb = 0.45,
		burst = { count = 2, interval = 2.0 },
	},
	{
		id = "BastionWalker", displayName = "Bastion Walker", telegraph = 0.55,
		tier = "Boss",
		health = 3600, shield = 400, damage = 35, attackRange = 200, attackCooldown = 3.0,
		speed = 7, sightRange = 220, lootScrap = 12, lootEnergyChance = 1.0, lootTechChance = 0.75,
		behavior = "WalkerPhases", weakPointMultiplier = 2.5,
	},
	{
		id = "HighMarshalVeyr", displayName = "High Marshal Veyr", telegraph = 0.55,
		tier = "Boss",
		health = 7200, shield = 1500, damage = 40, attackRange = 220, attackCooldown = 2.4,
		speed = 11, sightRange = 260, lootScrap = 25, lootEnergyChance = 1.0, lootTechChance = 1.0,
		behavior = "CommanderPhases", weakPointMultiplier = 1.8,
	},
}

Enemies.ById = {}
for _, e in Enemies.List do Enemies.ById[e.id] = e end

function Enemies.get(id: string)
	return Enemies.ById[id]
end

return Enemies

