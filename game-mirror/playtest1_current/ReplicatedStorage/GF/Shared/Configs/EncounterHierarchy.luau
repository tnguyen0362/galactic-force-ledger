--!strict
-- Encounter hierarchy: the Ascendancy's complete military opposition ladder (spec sections 4/5/69).
-- One authoritative definition table shared by generation (operation encounter sampling), runtime
-- (pressure budgets, pacing), presentation (encounter identity) and rewards (source ids).
-- Encounter rarity here is MILITARY PRESTIGE — deliberately separate from item/Augment rarity.

local EncounterHierarchy = {}

-- encounter classifications with initial duration targets (seconds) and pressure costs.
-- Pressure cost units feed the director budget (spec section 66): ordinary infantry baseline 1.
EncounterHierarchy.Class = {
	RegularInfantry = {
		rarity = "common",
		durationTarget = { 15, 45 },
		pressureCost = 1,
		rewardSource = "RegularInfantry",
	},
	SpectreDivision = {
		rarity = "uncommon",
		durationTarget = { 45, 90 },
		pressureCost = 4,
		rewardSource = "SpectreEncounter",
	},
	Bastion = {
		rarity = "uncommon",
		durationTarget = { 60, 120 },
		pressureCost = 6,
		rewardSource = "Bastion",
	},
	RevenantDivision = {
		rarity = "rare",
		durationTarget = { 120, 180 },
		pressureCost = 8,
		rewardSource = "RevenantEncounter",
	},
	BastionSiege = {
		rarity = "rare",
		durationTarget = { 120, 180 },
		pressureCost = 10,
		rewardSource = "BastionSiege",
	},
	MajorWarMachine = {
		rarity = "boss",
		durationTarget = { 240, 420 },
		pressureCost = 18,
		rewardSource = "MajorWarMachine",
	},
}

-- spec section 56: provisional per-operation occurrence probability of AT LEAST ONE optional
-- encounter of the type, by difficulty. Operation-level selection (not per-region rolls) —
-- the per-region compounding trap is explicitly called out in spec section 57.
EncounterHierarchy.OccurrenceChance = {
	SpectreDivision = { Easy = 0.15, Normal = 0.30, Hard = 0.45, Extreme = 0.60 },
	Bastion = { Easy = 0.10, Normal = 0.25, Hard = 0.40, Extreme = 0.55 },
	RevenantDivision = { Easy = 0.02, Normal = 0.06, Hard = 0.12, Extreme = 0.18 },
	BastionSiege = { Easy = 0.02, Normal = 0.05, Hard = 0.10, Extreme = 0.15 },
}

-- Spectre squad composition (spec section 12): 3-5 operators, variable composition drawn from
-- role pool. Weights bias toward assault; support is optional.
EncounterHierarchy.SpectreRoles = {
	{ id = "SpectreAssault", weight = 3 },
	{ id = "SpectreWeapons", weight = 2 },
	{ id = "SpectrePrecision", weight = 2 },
	{ id = "SpectreLeader", weight = 1.5 },
	{ id = "SpectreSupport", weight = 1 },
}

-- Revenant reference composition (spec section 16): exactly five, one per role. The squad IS
-- the miniboss — each operator carries a distinct capability vector contribution.
EncounterHierarchy.RevenantRoles = {
	{
		id = "RevenantLeader",
		displayName = "Revenant Leader",
		capabilityVector = { coordination = 1.0, heavyPressure = 0, precisionPressure = 0, mobility = 0.2, defensiveSupport = 0 },
	},
	{
		id = "RevenantAssault",
		displayName = "Revenant Assault Specialist",
		capabilityVector = { coordination = 0, heavyPressure = 0, precisionPressure = 0, mobility = 1.0, defensiveSupport = 0 },
	},
	{
		id = "RevenantWeapons",
		displayName = "Revenant Weapons Specialist",
		capabilityVector = { coordination = 0, heavyPressure = 1.0, precisionPressure = 0, mobility = 0, defensiveSupport = 0 },
	},
	{
		id = "RevenantPrecision",
		displayName = "Revenant Precision Specialist",
		capabilityVector = { coordination = 0, heavyPressure = 0, precisionPressure = 1.0, mobility = 0.2, defensiveSupport = 0 },
	},
	{
		id = "RevenantDefense",
		displayName = "Revenant Defense Specialist",
		capabilityVector = { coordination = 0, heavyPressure = 0, precisionPressure = 0, mobility = 0, defensiveSupport = 1.0 },
	},
}

-- Bastion vehicle family (spec sections 26/28/31): shared chassis architecture, modular variation.
-- Speeds are preliminary references, calibrated against verified player movement.
EncounterHierarchy.BastionVariants = {
	Standard = {
		speed = 12.5, speedRange = { 10, 15 },
		hullHealth = 4200,
		dimensions = { length = 28, width = 17, height = 11 },
		turretOmegaMax = math.rad(50), -- turret yaw rate cap, radians/s
		hullOmegaMax = math.rad(28),
		accel = 6, brake = 10,
	},
	Vanguard = {
		speed = 17, speedRange = { 14, 20 },
		hullHealth = 3200,
		dimensions = { length = 26, width = 16, height = 10 },
		turretOmegaMax = math.rad(65),
		hullOmegaMax = math.rad(36),
		accel = 9, brake = 12,
	},
	Bulwark = {
		speed = 9, speedRange = { 7, 11 },
		hullHealth = 5600,
		dimensions = { length = 29, width = 18, height = 12 },
		turretOmegaMax = math.rad(40),
		hullOmegaMax = math.rad(22),
		accel = 5, brake = 9,
	},
	Siege = {
		speed = 9.5, speedRange = { 7, 12 },
		hullHealth = 9500,
		dimensions = { length = 42, width = 25, height = 19 },
		turretOmegaMax = math.rad(34),
		hullOmegaMax = math.rad(18),
		accel = 4, brake = 8,
	},
}

-- Bastion component layout (spec section 36): fictional game mechanics, not vehicle simulation.
-- Each component: health pool, body-damage transfer coefficient (eta), capabilities it enables,
-- components it protects (exposure chain), hitbox sizing guidance.
EncounterHierarchy.BastionComponents = {
	FrontArmor = {
		health = 900, eta = 0.05, -- armor eats damage, little transfers to hull
		protects = { "EnergyCore" },
		enables = {},
		exposedName = nil,
	},
	EnergyCore = {
		health = 700, eta = 2.0, -- the weakpoint: damage to core transfers amplified
		protects = {},
		enables = {},
		protectedBy = "FrontArmor", -- cannot be hit until the panel is destroyed
		damageMultiplier = 2.0,
	},
	MainCannon = {
		health = 800, eta = 0.4,
		protects = {},
		enables = { "HeavyCannonAttack" },
	},
	SensorAssembly = {
		health = 400, eta = 0.5,
		protects = {},
		enables = { "AimAcquisition" }, -- destruction degrades target acquisition, does not blind
	},
	LeftPropulsion = {
		health = 700, eta = 0.4,
		protects = {},
		enables = { "MobilityLeft" },
	},
	RightPropulsion = {
		health = 700, eta = 0.4,
		protects = {},
		enables = { "MobilityRight" },
	},
	SecondaryWeapon = {
		health = 500, eta = 0.3,
		protects = {},
		enables = { "SecondaryFire" },
		optional = true,
	},
}

-- major war machine identifiers (spec section 42). Leviathan is the reference boss.
EncounterHierarchy.WarMachines = {
	Leviathan = {
		displayName = "Leviathan Siege Walker",
		dimensions = { length = 55, width = 38, height = 36 },
		hullHealth = 26000,
		speed = 6.5,
		family = "HeavySiegeWalker",
	},
	Dreadnought = {
		displayName = "Dreadnought Siege Platform",
		family = "ArmoredSiegePlatform",
		reserved = true, -- design family registered, production deferred (spec: one exceptional boss first)
	},
	Citadel = {
		displayName = "Citadel Mobile Command Fortress",
		family = "MobileCommandFortress",
		reserved = true,
	},
}

-- Per-enemy pressure costs used by the encounter director's reinforcement economy. These are
-- deliberately separate from encounter-class costs above: a Spectre ENCOUNTER costs 4 as a rare
-- operation event, while each spawned operator still occupies infantry seats in the live budget.
-- Ordinary infantry remains the 1-cost baseline (spec section 11/66).
EncounterHierarchy.EnemyPressure = {
	Rifleman = 1,
	Scout = 1,
	Marksman = 1.5,
	Heavy = 2.5,
	Officer = 2,
	SpectreAssault = 1.8,
	SpectreWeapons = 2.4,
	SpectrePrecision = 1.9,
	SpectreLeader = 2.2,
	SpectreSupport = 1.8,
	RevenantLeader = 2.8,
	RevenantAssault = 2.2,
	RevenantWeapons = 2.7,
	RevenantPrecision = 2.3,
	RevenantDefense = 2.4,
	BastionWalker = 6,
	HighMarshalVeyr = 6,
}

-- Difficulty-shaped elite frequency for ordinary reinforcement composition. This mirrors the
-- launch difficulty fantasy (scarce elites low, combined arms high) without scaling hit points.
EncounterHierarchy.DifficultyEliteFrequency = {
	Easy = 0.0,
	Normal = 0.10,
	Hard = 0.22,
	Extreme = 0.34,
}

-- Wave doctrine data. The director owns timing/target selection; NPCSquads owns conversion of
-- these roles into a formation. Waves are squads: an infantry core first, then support, command
-- and heavy slots only when escalation/difficulty justifies them.
EncounterHierarchy.WaveDoctrine = {
	recon = {
		core = { 2, 2 },
		infantry = { "Rifleman", "Scout" },
		support = { "Marksman" },
		supportChance = 0.20,
		commandChance = 0,
		heavyChance = 0,
		maxMembers = 3,
	},
	contact = {
		core = { 2, 3 },
		infantry = { "Rifleman", "Rifleman", "Scout" },
		support = { "Marksman", "Scout" },
		supportChance = 0.55,
		commandChance = 0.10,
		heavyChance = 0.04,
		maxMembers = 4,
	},
	assault = {
		core = { 3, 4 },
		infantry = { "Rifleman", "Rifleman", "Scout" },
		support = { "Marksman", "Scout" },
		supportChance = 0.80,
		commandChance = 0.24,
		heavyChance = 0.16,
		maxMembers = 5,
	},
	extraction = {
		core = { 3, 4 },
		infantry = { "Rifleman", "Rifleman", "Scout" },
		support = { "Marksman", "Scout" },
		supportChance = 0.90,
		commandChance = 0.34,
		heavyChance = 0.34,
		maxMembers = 5,
	},
}

function EncounterHierarchy.classOf(encounterType: string): any
	return EncounterHierarchy.Class[encounterType]
end

function EncounterHierarchy.pressureCost(encounterType: string): number
	local c = EncounterHierarchy.Class[encounterType]
	return c and c.pressureCost or 1
end

function EncounterHierarchy.enemyPressureCost(enemyId: string): number
	return EncounterHierarchy.EnemyPressure[enemyId] or 1
end

function EncounterHierarchy.waveDoctrine(phase: string): any
	return EncounterHierarchy.WaveDoctrine[phase] or EncounterHierarchy.WaveDoctrine.contact
end

return EncounterHierarchy
