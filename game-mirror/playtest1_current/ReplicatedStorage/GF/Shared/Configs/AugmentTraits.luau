--!strict
-- AugmentTraits: GENERATED from gf-research/augment/trait_registry_v1.json — do not hand-edit.
-- Registry version 1.0.0-draft / balance 2026-11-27.a
-- Single source of truth pipeline: JSON -> this config + Python research mirror.
local AugmentTraits = {}

AugmentTraits.RegistryVersion = "1.0.0-draft"
AugmentTraits.BalanceVersion = "2026-11-27.a"

AugmentTraits.Stats = {
	healthDamage = {
		transform = "multAdditive",
		cap = 0.15,
		domain = { 0, 0.5 },
		displayFormat = "+{v}% damage",
		consumptionVerified = true
	},
	shieldDamage = {
		transform = "multAdditive",
		cap = 0.3,
		domain = { 0, 0.5 },
		displayFormat = "+{v}% shield damage",
		consumptionVerified = true
	},
	armorDamage = {
		transform = "multAdditive",
		cap = 0.3,
		domain = { 0, 0.5 },
		displayFormat = "+{v}% armor damage",
		consumptionVerified = true
	},
	weakPoint = {
		transform = "multAdditive",
		cap = 0.2,
		domain = { 0, 0.5 },
		displayFormat = "+{v}% weakpoint damage",
		consumptionVerified = true
	},
	blastRadius = {
		transform = "multAdditive",
		cap = 0.25,
		domain = { -0.35, 0.5 },
		displayFormat = "+{v}% explosion radius",
		consumptionVerified = true
	},
	magazine = {
		transform = "multAdditive",
		cap = 0.35,
		domain = { -0.3, 0.5 },
		displayFormat = "+{v}% magazine",
		consumptionVerified = true,
		quantization = "nearest"
	},
	reloadSpeed = {
		transform = "rateSpeed",
		cap = 0.25,
		domain = { 0, 0.5 },
		displayFormat = "+{v}% reload speed",
		consumptionVerified = true
	},
	range = {
		transform = "multAdditive",
		cap = 0.3,
		domain = { -0.35, 0.5 },
		displayFormat = "+{v}% effective range",
		consumptionVerified = true
	},
	movingAccuracy = {
		transform = "multAdditive",
		cap = 0.35,
		domain = { -0.35, 0.5 },
		displayFormat = "+{v}% moving accuracy",
		consumptionVerified = true,
		signed = true
	},
	followUpSpeed = {
		transform = "multAdditive",
		cap = 0.35,
		domain = { -0.35, 0.35 },
		displayFormat = "+{v}% follow-up stability",
		consumptionVerified = true,
		inverseBenefit = true,
		signed = true
	},
	adsRecovery = {
		transform = "multAdditive",
		cap = 0.35,
		domain = { 0, 0.5 },
		displayFormat = "+{v}% sustained-aim stability",
		consumptionVerified = true
	},
	recoil = {
		transform = "multAdditive",
		cap = 0.35,
		domain = { -0.35, 0.35 },
		displayFormat = "-{v}% recoil",
		consumptionVerified = true,
		inverseBenefit = true,
		signed = true
	},
	adsSpeed = {
		transform = "multAdditive",
		cap = 0.25,
		domain = { -0.35, 0.5 },
		displayFormat = "+{v}% aim speed",
		consumptionVerified = true,
		signed = true
	},
	swapSpeed = {
		transform = "multAdditive",
		cap = 0.35,
		domain = { 0, 0.5 },
		displayFormat = "+{v}% weapon-switch speed",
		consumptionVerified = false,
		wiringNote = "weapon-switch path unverified"
	},
	fireRate = {
		transform = "multAdditive",
		cap = 0.12,
		domain = { 0, 0.25 },
		displayFormat = "+{v}% fire rate",
		consumptionVerified = false,
		wiringNote = "server rate-limit + client cadence; small cap, requires audit"
	},
	spreadHip = {
		transform = "multAdditive",
		cap = 0.25,
		domain = { 0, 0.4 },
		displayFormat = "-{v}% hip-fire spread",
		consumptionVerified = false,
		inverseBenefit = true,
		wiringNote = "server cone base"
	},
	spreadAds = {
		transform = "multAdditive",
		cap = 0.25,
		domain = { 0, 0.4 },
		displayFormat = "-{v}% aimed spread",
		consumptionVerified = false,
		inverseBenefit = true,
		wiringNote = "server cone adsSpread"
	},
	projectileVelocity = {
		transform = "multAdditive",
		cap = 0.3,
		domain = { 0, 0.5 },
		displayFormat = "+{v}% projectile velocity",
		consumptionVerified = false,
		wiringNote = "launcher projectiles only"
	},
	reserveAmmo = {
		transform = "multAdditive",
		cap = 0.35,
		domain = { 0, 0.6 },
		displayFormat = "+{v}% reserve ammunition",
		consumptionVerified = false,
		quantization = "nearest",
		wiringNote = "server ammo state init"
	},
	componentDamage = {
		transform = "multAdditive",
		cap = 0.3,
		domain = { 0, 0.5 },
		displayFormat = "+{v}% component damage",
		consumptionVerified = false,
		wiringNote = "mechanical component path — beta-validated, coordinate"
	}
}

AugmentTraits.Traits = {
	TR_DAMAGE = {
		stat = "healthDamage",
		family = "Ballistic",
		displayName = "Kinetic Amplifier",
		compat = { "Universal" },
		minRarity = "Common",
		bands = {
			C = { 0.04, 0.07 },
			R = { 0.05, 0.09 },
			E = { 0.07, 0.11 },
			L = { 0.09, 0.14 }
		},
		weight = 10,
		conflictGroup = "damage_core"
	},
	TR_FIRERATE = {
		stat = "fireRate",
		family = "Ballistic",
		displayName = "Cycler Overclock",
		compat = { "Universal" },
		minRarity = "Rare",
		bands = {
			R = { 0.03, 0.05 },
			E = { 0.04, 0.07 },
			L = { 0.06, 0.1 }
		},
		weight = 6
	},
	TR_WEAKPOINT = {
		stat = "weakPoint",
		family = "Ballistic",
		displayName = "Vulnerability Analyzer",
		compat = { "Universal" },
		minRarity = "Common",
		bands = {
			C = { 0.05, 0.09 },
			R = { 0.07, 0.12 },
			E = { 0.1, 0.16 },
			L = { 0.13, 0.2 }
		},
		weight = 8
	},
	TR_SHIELDDMG = {
		stat = "shieldDamage",
		family = "Ballistic",
		displayName = "Shield Disruptor",
		compat = { "Universal" },
		minRarity = "Common",
		bands = {
			C = { 0.06, 0.1 },
			R = { 0.09, 0.15 },
			E = { 0.13, 0.2 },
			L = { 0.17, 0.26 }
		},
		weight = 7
	},
	TR_ARMORDMG = {
		stat = "armorDamage",
		family = "Ballistic",
		displayName = "Armor Penetrator",
		compat = { "Universal" },
		minRarity = "Common",
		bands = {
			C = { 0.06, 0.1 },
			R = { 0.09, 0.15 },
			E = { 0.13, 0.2 },
			L = { 0.17, 0.26 }
		},
		weight = 7
	},
	TR_COMPONENTDMG = {
		stat = "componentDamage",
		family = "Ballistic",
		displayName = "Component Destructor",
		compat = { "Launcher", "Marksman", "LMG" },
		minRarity = "Rare",
		bands = {
			R = { 0.08, 0.13 },
			E = { 0.12, 0.18 },
			L = { 0.16, 0.25 }
		},
		weight = 6
	},
	TR_CLOSEDMG = {
		stat = "healthDamage",
		family = "Ballistic",
		displayName = "CQC Amplifier",
		compat = { "SMG", "Shotgun", "Pistol" },
		minRarity = "Common",
		bands = {
			C = { 0.05, 0.08 },
			R = { 0.07, 0.11 },
			E = { 0.1, 0.14 },
			L = { 0.12, 0.18 }
		},
		weight = 8,
		conflictGroup = "damage_core"
	},
	TR_RECOIL = {
		stat = "recoil",
		family = "Precision",
		displayName = "Recoil Compensator",
		compat = { "Universal" },
		minRarity = "Common",
		bands = {
			C = { 0.03, 0.06 },
			R = { 0.05, 0.09 },
			E = { 0.08, 0.13 },
			L = { 0.1, 0.17 }
		},
		weight = 10
	},
	TR_SPREAD_HIP = {
		stat = "spreadHip",
		family = "Precision",
		displayName = "Hipfire Stabilizer",
		compat = { "SMG", "Shotgun", "Pistol", "AR" },
		minRarity = "Common",
		bands = {
			C = { 0.04, 0.07 },
			R = { 0.06, 0.1 },
			E = { 0.09, 0.14 },
			L = { 0.12, 0.19 }
		},
		weight = 8
	},
	TR_SPREAD_ADS = {
		stat = "spreadAds",
		family = "Precision",
		displayName = "Precision Optics",
		compat = { "AR", "Marksman", "LMG", "Pistol" },
		minRarity = "Common",
		bands = {
			C = { 0.04, 0.07 },
			R = { 0.06, 0.1 },
			E = { 0.09, 0.14 },
			L = { 0.12, 0.19 }
		},
		weight = 8
	},
	TR_RANGE = {
		stat = "range",
		family = "Precision",
		displayName = "Ballistic Range Finder",
		compat = { "AR", "Marksman", "LMG", "Pistol" },
		minRarity = "Common",
		bands = {
			C = { 0.05, 0.09 },
			R = { 0.08, 0.13 },
			E = { 0.11, 0.18 },
			L = { 0.15, 0.24 }
		},
		weight = 7
	},
	TR_MOVEACC = {
		stat = "movingAccuracy",
		family = "Precision",
		displayName = "Mobile Stabilization",
		compat = { "SMG", "AR", "Pistol" },
		minRarity = "Common",
		bands = {
			C = { 0.05, 0.09 },
			R = { 0.08, 0.13 },
			E = { 0.11, 0.18 },
			L = { 0.15, 0.24 }
		},
		weight = 7
	},
	TR_FOLLOWUP = {
		stat = "followUpSpeed",
		family = "Precision",
		displayName = "Follow-Through Compensator",
		compat = { "Marksman", "AR", "Pistol" },
		minRarity = "Common",
		bands = {
			C = { 0.05, 0.09 },
			R = { 0.08, 0.13 },
			E = { 0.11, 0.18 },
			L = { 0.15, 0.24 }
		},
		weight = 6
	},
	TR_ADSRECOVERY = {
		stat = "adsRecovery",
		family = "Precision",
		displayName = "Sustained-Aim Gyroscope",
		compat = { "Marksman", "AR", "LMG" },
		minRarity = "Rare",
		bands = {
			R = { 0.06, 0.1 },
			E = { 0.09, 0.15 },
			L = { 0.13, 0.2 }
		},
		weight = 6
	},
	TR_MAGAZINE = {
		stat = "magazine",
		family = "Logistics",
		displayName = "Extended Feed System",
		compat = { "Universal" },
		minRarity = "Common",
		bands = {
			C = { 0.03, 0.06 },
			R = { 0.05, 0.1 },
			E = { 0.08, 0.15 },
			L = { 0.12, 0.2 }
		},
		weight = 10
	},
	TR_RELOAD = {
		stat = "reloadSpeed",
		family = "Logistics",
		displayName = "Rapid Feed Processor",
		compat = { "Universal" },
		minRarity = "Common",
		bands = {
			C = { 0.02, 0.04 },
			R = { 0.03, 0.06 },
			E = { 0.05, 0.09 },
			L = { 0.07, 0.12 }
		},
		weight = 10
	},
	TR_RESERVE = {
		stat = "reserveAmmo",
		family = "Logistics",
		displayName = "Ammunition Reserve Matrix",
		compat = { "Universal" },
		minRarity = "Common",
		bands = {
			C = { 0.08, 0.14 },
			R = { 0.12, 0.2 },
			E = { 0.17, 0.28 },
			L = { 0.23, 0.36 }
		},
		weight = 7
	},
	TR_SWAPSPEED = {
		stat = "swapSpeed",
		family = "Logistics",
		displayName = "Quick-Release Mount",
		compat = { "Universal" },
		minRarity = "Common",
		bands = {
			C = { 0.08, 0.14 },
			R = { 0.12, 0.2 },
			E = { 0.17, 0.26 },
			L = { 0.22, 0.33 }
		},
		weight = 6
	},
	TR_ADSSPEED = {
		stat = "adsSpeed",
		family = "Logistics",
		displayName = "Reflex Sight Actuator",
		compat = { "Universal" },
		minRarity = "Common",
		bands = {
			C = { 0.05, 0.09 },
			R = { 0.08, 0.13 },
			E = { 0.11, 0.17 },
			L = { 0.14, 0.22 }
		},
		weight = 6
	},
	TR_BLASTDMG = {
		stat = "healthDamage",
		family = "Ordnance",
		displayName = "Shaped Charge Amplifier",
		compat = { "Launcher" },
		minRarity = "Common",
		bands = {
			C = { 0.05, 0.09 },
			R = { 0.08, 0.13 },
			E = { 0.11, 0.17 },
			L = { 0.14, 0.22 }
		},
		weight = 8,
		conflictGroup = "damage_core"
	},
	TR_BLASTRADIUS = {
		stat = "blastRadius",
		family = "Ordnance",
		displayName = "Wide-Charge Geometry",
		compat = { "Launcher" },
		minRarity = "Common",
		bands = {
			C = { 0.08, 0.13 },
			R = { 0.11, 0.18 },
			E = { 0.15, 0.23 },
			L = { 0.19, 0.3 }
		},
		weight = 8
	},
	TR_PROJVEL = {
		stat = "projectileVelocity",
		family = "Ordnance",
		displayName = "Propellant Accelerator",
		compat = { "Launcher" },
		minRarity = "Common",
		bands = {
			C = { 0.08, 0.13 },
			R = { 0.11, 0.18 },
			E = { 0.15, 0.24 },
			L = { 0.2, 0.3 }
		},
		weight = 7
	},
	TR_IMPACTDMG = {
		stat = "armorDamage",
		family = "Ordnance",
		displayName = "Kinetic Impact Warhead",
		compat = { "Launcher" },
		minRarity = "Rare",
		bands = {
			R = { 0.09, 0.14 },
			E = { 0.12, 0.19 },
			L = { 0.16, 0.25 }
		},
		weight = 6
	},
	TR_COND_KILLRELOAD = {
		stat = "reloadSpeed",
		family = "Adaptive",
		displayName = "Momentum Feed Processor",
		compat = { "Universal" },
		minRarity = "Epic",
		bands = {
			E = { 0.15, 0.22 },
			L = { 0.2, 0.3 }
		},
		weight = 5,
		conditional = {
			trigger = "elimination",
			duration = 6,
			maxStacks = 1,
			refresh = "refreshDuration",
			cooldown = 0
		}
	},
	TR_COND_WPHANDLING = {
		stat = "recoil",
		family = "Adaptive",
		displayName = "Precision Feedback Loop",
		compat = { "AR", "Marksman", "LMG" },
		minRarity = "Epic",
		bands = {
			E = { 0.1, 0.16 },
			L = { 0.14, 0.22 }
		},
		weight = 5,
		conditional = {
			trigger = "weakpointHit",
			duration = 4,
			maxStacks = 2,
			refresh = "addStackRefresh",
			cooldown = 0
		}
	},
	TR_COND_AIMPRECISION = {
		stat = "spreadAds",
		family = "Adaptive",
		displayName = "Sustained-Lock Targeter",
		compat = { "Marksman", "AR" },
		minRarity = "Epic",
		bands = {
			E = { 0.08, 0.13 },
			L = { 0.12, 0.18 }
		},
		weight = 5,
		conditional = {
			trigger = "continuousAim",
			rampTime = 2.5,
			duration = "whileAiming",
			maxStacks = 1,
			refresh = "continuous"
		}
	},
	TR_EXP_GLASSCANNON = {
		stat = "healthDamage",
		family = "Experimental",
		displayName = "Overcharge Chamber",
		compat = { "Universal" },
		minRarity = "Epic",
		bands = {
			E = { 0.1, 0.15 },
			L = { 0.14, 0.2 }
		},
		weight = 4,
		coupled = {
			drawbackStat = "fireRate",
			drawbackRatio = -0.6,
			description = "+damage / -fire rate"
		}
	},
	TR_EXP_DRUMMAG = {
		stat = "magazine",
		family = "Experimental",
		displayName = "Drum Feed Conversion",
		compat = { "AR", "LMG", "SMG" },
		minRarity = "Epic",
		bands = {
			E = { 0.15, 0.22 },
			L = { 0.2, 0.3 }
		},
		weight = 4,
		coupled = {
			drawbackStat = "reloadSpeed",
			drawbackRatio = -0.5,
			description = "+magazine / -reload speed"
		}
	},
	TR_EXP_WIDEWARHEAD = {
		stat = "blastRadius",
		family = "Experimental",
		displayName = "Fragmentation Conversion",
		compat = { "Launcher" },
		minRarity = "Epic",
		bands = {
			E = { 0.18, 0.26 },
			L = { 0.24, 0.35 }
		},
		weight = 4,
		coupled = {
			drawbackStat = "healthDamage",
			drawbackRatio = -0.45,
			description = "+blast radius / -direct damage"
		}
	},
	TR_EXP_HIPCONVERT = {
		stat = "spreadHip",
		family = "Experimental",
		displayName = "Point-Shooting Conversion",
		compat = { "SMG", "Shotgun", "Pistol" },
		minRarity = "Epic",
		bands = {
			E = { 0.15, 0.22 },
			L = { 0.2, 0.3 }
		},
		weight = 4,
		coupled = {
			drawbackStat = "spreadAds",
			drawbackRatio = -0.7,
			description = "+hipfire precision / -aimed precision"
		},
		conflictGroup = "spread_core"
	}
}

AugmentTraits.ConflictGroups = {
	damage_core = {
		members = { "TR_DAMAGE", "TR_CLOSEDMG", "TR_BLASTDMG" },
		maxPerWeapon = 1,
		policy = "highest-applies"
	},
	spread_core = {
		members = { "TR_SPREAD_HIP", "TR_EXP_HIPCONVERT" },
		maxPerWeapon = 1,
		policy = "highest-applies"
	}
}

AugmentTraits.RarityCount = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }
AugmentTraits.RarityShort = { Common = "C", Rare = "R", Epic = "E", Legendary = "L" }

return AugmentTraits
