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
	-- ══ Spectre Division: uncommon elite infantry (spec section 12/13). Compatible variants of
	-- established roles — same AI machinery, next-level parameters: faster acquisition (lower
	-- telegraph), better accuracy (hitProb), stronger repositioning. NOT ordinary soldiers with
	-- double health — competence, not bulk. EliteDivision tag drives visual armor + squad spawning.
	{
		id = "SpectreLeader", displayName = "Spectre Squad Leader", telegraph = 0.34,
		armorFactor = 0.9, tier = "Elite", division = "Spectre", role = "leader",
		health = 520, shield = 220, damage = 15, attackRange = 95, attackCooldown = 1.8,
		speed = 13.5, sightRange = 150, lootScrap = 4, lootEnergyChance = 0.5, lootTechChance = 0.25,
		behavior = "CommandSquad", weakPointMultiplier = 1.5, hitProb = 0.58,
		burst = { count = 2, interval = 1.6 },
	},
	{
		id = "SpectreAssault", displayName = "Spectre Assault Operator", telegraph = 0.3,
		armorFactor = 0.95, tier = "Elite", division = "Spectre", role = "assault",
		health = 380, shield = 170, damage = 10, attackRange = 52, attackCooldown = 0.95,
		speed = 19.5, sightRange = 140, lootScrap = 3, lootEnergyChance = 0.35, lootTechChance = 0.12,
		behavior = "FlankBeacon", weakPointMultiplier = 1.3, hitProb = 0.5,
		burst = { count = 4, interval = 0.14 },
	},
	{
		id = "SpectreWeapons", displayName = "Spectre Weapons Operator", telegraph = 0.38,
		armorFactor = 0.8, tier = "Elite", division = "Spectre", role = "weapons",
		health = 560, shield = 200, damage = 30, attackRange = 85, attackCooldown = 2.2,
		speed = 10.5, sightRange = 140, lootScrap = 4, lootEnergyChance = 0.6, lootTechChance = 0.15,
		behavior = "AreaBurst", weakPointMultiplier = 1.8, hitProb = 0.55,
		burst = { count = 1, interval = 0 },
	},
	{
		id = "SpectrePrecision", displayName = "Spectre Precision Operator", telegraph = 0.4,
		chargeTime = 0.95,
		armorFactor = 1.0, tier = "Elite", division = "Spectre", role = "precision",
		health = 320, shield = 150, damage = 40, attackRange = 190, attackCooldown = 2.6,
		speed = 12, sightRange = 220, lootScrap = 3, lootEnergyChance = 0.4, lootTechChance = 0.15,
		behavior = "ChargedShot", weakPointMultiplier = 1.4, hitProb = 0.78,
		burst = { count = 1, interval = 0 },
	},
	{
		id = "SpectreSupport", displayName = "Spectre Support Operator", telegraph = 0.36,
		armorFactor = 1.0, tier = "Elite", division = "Spectre", role = "support",
		health = 360, shield = 190, damage = 9, attackRange = 75, attackCooldown = 1.4,
		speed = 14, sightRange = 140, lootScrap = 3, lootEnergyChance = 0.45, lootTechChance = 0.2,
		behavior = "GuardCover", weakPointMultiplier = 1.3, hitProb = 0.52,
		burst = { count = 3, interval = 0.16 },
	},
	-- ══ Revenant Division: rare five-member miniboss squad (spec sections 15-17). Each operator
	-- is individually lethal; the squad capability vector is the encounter. Stronger than Spectres
	-- in every dimension but still soldiers, not tanks.
	{
		id = "RevenantLeader", displayName = "Revenant Leader", telegraph = 0.28,
		armorFactor = 0.85, tier = "Elite", division = "Revenant", role = "leader",
		health = 780, shield = 420, damage = 18, attackRange = 100, attackCooldown = 1.5,
		speed = 14, sightRange = 170, lootScrap = 6, lootEnergyChance = 0.75, lootTechChance = 0.4,
		behavior = "CommandSquad", weakPointMultiplier = 1.6, hitProb = 0.64,
		burst = { count = 2, interval = 1.4 },
	},
	{
		id = "RevenantAssault", displayName = "Revenant Assault Specialist", telegraph = 0.24,
		armorFactor = 0.95, tier = "Elite", division = "Revenant", role = "assault",
		health = 620, shield = 340, damage = 13, attackRange = 55, attackCooldown = 0.8,
		speed = 21, sightRange = 150, lootScrap = 5, lootEnergyChance = 0.6, lootTechChance = 0.3,
		behavior = "FlankBeacon", weakPointMultiplier = 1.4, hitProb = 0.56,
		burst = { count = 5, interval = 0.12 },
	},
	{
		id = "RevenantWeapons", displayName = "Revenant Weapons Specialist", telegraph = 0.32,
		armorFactor = 0.75, tier = "Elite", division = "Revenant", role = "weapons",
		health = 900, shield = 380, damage = 36, attackRange = 90, attackCooldown = 2.0,
		speed = 10, sightRange = 150, lootScrap = 6, lootEnergyChance = 0.8, lootTechChance = 0.35,
		behavior = "AreaBurst", weakPointMultiplier = 2.0, hitProb = 0.6,
		burst = { count = 1, interval = 0 },
	},
	{
		id = "RevenantPrecision", displayName = "Revenant Precision Specialist", telegraph = 0.34,
		chargeTime = 0.85,
		armorFactor = 1.0, tier = "Elite", division = "Revenant", role = "precision",
		health = 520, shield = 300, damage = 48, attackRange = 210, attackCooldown = 2.2,
		speed = 12.5, sightRange = 240, lootScrap = 5, lootEnergyChance = 0.65, lootTechChance = 0.35,
		behavior = "ChargedShot", weakPointMultiplier = 1.5, hitProb = 0.82,
		burst = { count = 1, interval = 0 },
	},
	{
		id = "RevenantDefense", displayName = "Revenant Defense Specialist", telegraph = 0.34,
		armorFactor = 0.85, tier = "Elite", division = "Revenant", role = "defense",
		health = 700, shield = 460, damage = 11, attackRange = 80, attackCooldown = 1.6,
		speed = 12, sightRange = 150, lootScrap = 5, lootEnergyChance = 0.7, lootTechChance = 0.4,
		behavior = "GuardCover", weakPointMultiplier = 1.5, hitProb = 0.55,
		burst = { count = 3, interval = 0.15 },
	},
	-- ══ Component-framework vehicle/boss loot entries (spec section 60). These enemies are
	-- driven by their own controllers (BastionTank/LeviathanWalker services), not EnemyService —
	-- the entries exist so rewards resolve by EnemyId. Boss tier bypasses the mission drop cap;
	-- encounter-tier kills pay meaningful operation-relevant loot.
	{
		id = "BastionTank", displayName = "Bastion Heavy Vehicle", telegraph = 1.6,
		tier = "Vehicle",
		health = 1400, shield = 0, damage = 52, attackRange = 190, attackCooldown = 7,
		speed = 14, sightRange = 260, lootScrap = 8, lootEnergyChance = 1.0, lootTechChance = 0.5,
		behavior = "VehicleController", weakPointMultiplier = 2.0,
	},
	{
		id = "BastionSiege", displayName = "Bastion Siege Variant", telegraph = 1.6,
		tier = "Boss",
		health = 1900, shield = 0, damage = 62, attackRange = 220, attackCooldown = 6,
		speed = 9, sightRange = 280, lootScrap = 14, lootEnergyChance = 1.0, lootTechChance = 0.8,
		behavior = "VehicleController", weakPointMultiplier = 2.0,
	},
	{
		id = "LeviathanWalker", displayName = "Leviathan Siege Walker", telegraph = 1.8,
		tier = "Boss",
		health = 26000, shield = 0, damage = 68, attackRange = 240, attackCooldown = 9,
		speed = 6.5, sightRange = 300, lootScrap = 30, lootEnergyChance = 1.0, lootTechChance = 1.0,
		behavior = "VehicleController", weakPointMultiplier = 2.2,
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

