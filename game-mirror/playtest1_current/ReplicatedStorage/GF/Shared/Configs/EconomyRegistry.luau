--!strict
-- AUTHORITATIVE ECONOMIC PARAMETER REGISTRY (economy spec §134 deliverable 1, §101 versioning).
-- Single consolidated location for every tunable economic parameter, each tagged with provenance:
--   "spec-fixed"      — value mandated by the economy spec; changing it requires spec amendment
--   "spec-input"      — spec calls it an initial research input; calibration may revise within spec
--   "provisional"     — legacy value carried forward; calibration target, not yet validated
--   "derived"         — computed from other registry values, never edited directly
-- Consumers should migrate to reading this registry; legacy configs (Economy/Caches/Requisitions)
-- remain live during migration and are cross-validated by EconomyChecks.
local EconomyRegistry = {}

EconomyRegistry.VERSION = "1.0.0"
EconomyRegistry.CHANGELOG = {
	{ version = "1.0.0", date = "2026-11-27", note = "Initial consolidation from legacy configs. Values unchanged; provenance tagged. No player-facing change." },
}

-- ---------------------------------------------------------------------------
-- §7 CURRENCY ARCHITECTURE — five resources, no additions without authorization.
-- Every resource carries machine-readable sources and sinks so scarcity analysis
-- (§58-61) can enumerate flows without scraping code.
-- ---------------------------------------------------------------------------
EconomyRegistry.Currencies = {
	credits = {
		displayName = "Credits",
		purpose = "Standard military equipment purchases",
		provenance = "spec-fixed",
		sources = {
			{ id = "mission_payout", kind = "mission", note = "difficulty-scaled base payout" },
			{ id = "squad_bonus", kind = "mission", note = "+25% when full squad extracts together" },
			{ id = "service_commendation", kind = "progression", note = "assist milestones" },
		},
		sinks = {
			{ id = "weapons", note = "one-time permanent ownership, never repurchased" },
			{ id = "grenades", note = "unlock purchases" },
			{ id = "armor", note = "armor set purchases" },
			{ id = "abilities", note = "support ability purchases" },
			{ id = "requisition_entries", note = "requisition items priced in credits" },
			{ id = "capacity_expansion", note = "augment inventory capacity steps" },
		},
	},
	scrap = {
		displayName = "Scrap",
		purpose = "Augment rerolling and equipment recovery",
		provenance = "spec-fixed",
		sources = {
			{ id = "enemy_drops", kind = "combat", note = "per-enemy lootScrap, tier-differentiated" },
			{ id = "mission_baseline", kind = "mission", note = "LootPerStandardMission" },
			{ id = "augment_dismantle", kind = "transaction", note = "dismantling returns scrap" },
			{ id = "requisition_kits", kind = "purchase", note = "resource kit entries" },
		},
		sinks = {
			{ id = "augment_reroll", note = "25/50/100/200 by rarity — spec-fixed" },
			{ id = "trait_locking", note = "1.5x reroll cost surcharge Epic/Legendary — spec-fixed 50%" },
		},
	},
	energyCells = {
		displayName = "Energy Cells",
		purpose = "Approved advanced technological equipment requirements",
		provenance = "spec-fixed",
		sources = {
			{ id = "enemy_drops", kind = "combat", note = "lootEnergyChance 0.05-1.0 by enemy tier" },
			{ id = "mission_baseline", kind = "mission", note = "LootPerStandardMission" },
		},
		sinks = {
			{ id = "capacity_expansion", note = "10 per step — only live sink" },
			{ id = "requisition_kits", note = "field kit entries" },
		},
		designGap = "§10: no equipment unlock requires cells. Documented for calibration — see Stage 10 alternatives analysis.",
	},
	militaryTechnology = {
		displayName = "Military Technology",
		purpose = "Approved advanced equipment and rare technology requirements",
		provenance = "spec-fixed",
		sources = {
			{ id = "elite_drops", kind = "combat", note = "lootTechChance 0.15-1.0, elites/vehicles/bosses" },
			{ id = "mission_baseline", kind = "mission", note = "LootPerStandardMission" },
		},
		sinks = {
			{ id = "capacity_expansion", note = "3 per step — only live sink" },
		},
		designGap = "same class as energyCells; §11 requires alternative acquisition paths and non-boss availability — boss-exclusive acquisition already avoided.",
	},
	warCredits = {
		displayName = "War Credits",
		purpose = "Permanent Requisitions access and approved premium purchases",
		provenance = "spec-fixed",
		sources = {
			{ id = "extraction_award", kind = "mission", note = "success+objective only, fixed per difficulty, NEVER squad-bonus multiplied" },
		},
		sinks = {
			{ id = "premium_requisition_access", note = "Siege Division 1000 — earnable alternative to purchase" },
		},
	},
}

-- ---------------------------------------------------------------------------
-- PAYOUT TABLES (Economy.luau consolidation)
-- ---------------------------------------------------------------------------
EconomyRegistry.PayoutByDifficulty = {
	Easy = { credits = 250, xp = 330, provenance = "spec-input" },
	Normal = { credits = 450, xp = 600, provenance = "spec-input" },
	Hard = { credits = 700, xp = 950, provenance = "spec-input" },
	Extreme = { credits = 950, xp = 1350, provenance = "spec-input" },
}

EconomyRegistry.LootPerStandardMission = { scrap = 12, energyCells = 4, militaryTechnology = 1, provenance = "provisional" }

-- §32: full-squad extraction bonus. Solo always qualifies. War credits excluded per spec.
EconomyRegistry.SquadBonus = {
	multiplier = 0.25,
	appliesTo = { "credits", "xp", "scrap", "energyCells", "militaryTechnology" },
	excludes = { "warCredits" },
	integerFloorPerResource = true,
	provenance = "spec-fixed",
}

-- §12: fixed per difficulty, success+objective only, research inputs pending calibration
EconomyRegistry.WarCreditAward = {
	Easy = 5, Normal = 10, Hard = 15, Extreme = 25,
	requiresSuccessAndObjective = true,
	provenance = "spec-input",
}

-- ---------------------------------------------------------------------------
-- §9 AUGMENT REROLL ECONOMY — spec-fixed, no escalating costs ever
-- ---------------------------------------------------------------------------
EconomyRegistry.RerollCosts = {
	Common = 25, Rare = 50, Epic = 100, Legendary = 200,
	traitLockMultiplier = 1.5,
	traitLockEligibleRarities = { "Epic", "Legendary" },
	escalatingCostsForbidden = true,
	provenance = "spec-fixed",
}

-- ---------------------------------------------------------------------------
-- §22-23 CACHE RARITY MATRICES — P(augment rarity | cache tier), quantity per tier,
-- per-enemy-class drop chances, mission cap. Mirrors Caches.luau (live truth until migration).
-- ---------------------------------------------------------------------------
EconomyRegistry.CacheTiers = {
	Common = {
		augments = 1,
		rarityWeights = { Common = 82, Rare = 16, Epic = 1.9, Legendary = 0.1 },
		enemyChance = { infantry = 0.01, heavy = 0.04, commander = 0.07 },
		provenance = "provisional",
	},
	Rare = {
		augments = 2,
		rarityWeights = { Common = 48, Rare = 43, Epic = 8, Legendary = 1 },
		enemyChance = { infantry = 0.01, heavy = 0.05, commander = 0.09 },
		provenance = "provisional",
	},
	Epic = {
		augments = 3,
		rarityWeights = { Common = 18, Rare = 48, Epic = 30, Legendary = 4 },
		enemyChance = { infantry = 0.00, heavy = 0.02, commander = 0.05 },
		provenance = "provisional",
	},
	Legendary = {
		augments = 4,
		rarityWeights = { Common = 0, Rare = 30, Epic = 55, Legendary = 15 },
		enemyChance = { infantry = 0.00, heavy = 0.00, commander = 0.00 },
		provenance = "provisional",
	},
}

EconomyRegistry.CacheDropRules = {
	missionCapNonBoss = 3,
	bossGuaranteed = true,
	tierScalesWithDifficulty = true,
	provenance = "provisional",
}

-- ---------------------------------------------------------------------------
-- §25/§72-73 GUARANTEED REWARDS + RNG PROTECTION
-- ---------------------------------------------------------------------------
EconomyRegistry.GuaranteedMissionCache = {
	requiresSuccessAndObjective = true,
	provenance = "spec-fixed",
}

EconomyRegistry.BlueprintPity = {
	threshold = 5,
	qualifiesOnlyOnExtractedBossKill = true,
	floorNotCeiling = true,
	provenance = "spec-fixed",
}

-- ---------------------------------------------------------------------------
-- §35-37 RANK PROGRESSION — hybrid quadratic, non-exponential
-- ---------------------------------------------------------------------------
EconomyRegistry.RankCurve = {
	formula = "X(r) = 300*(r-1) + 55*r*(r-1)",
	baseLinear = 300,
	quadraticCoeff = 55,
	maxRank = 30,
	difficultyUnlocks = { Hard = 6, Extreme = 14 },
	provenance = "spec-input",
}

-- ---------------------------------------------------------------------------
-- §41-44 MASTERY
-- ---------------------------------------------------------------------------
EconomyRegistry.Mastery = {
	secondSocketXp = 650,
	settlesOnlyOnObjectiveComplete = true,
	killXpCountsTowardRank = true,
	provenance = "provisional",
}

-- ---------------------------------------------------------------------------
-- §45-50 REQUISITIONS
-- ---------------------------------------------------------------------------
EconomyRegistry.Requisitions = {
	freeTrackId = "FrontlineArsenal",
	premiumTrackId = "SiegeDivision",
	premiumAccessWarCredits = 1000,
	tier2SpendThreshold = 600,
	tier3SpendThreshold = 1600,
	permanent = true,
	neverExpires = true,
	provenance = "spec-input",
}

-- ---------------------------------------------------------------------------
-- COMBAT-SUPPLY SEPARATION (§13) — these never enter the persistent economy
-- ---------------------------------------------------------------------------
EconomyRegistry.CombatSupplyDrops = {
	ammoChance = 0.20,
	grenadeChance = 0.08,
	neverPersistent = true,
	provenance = "provisional",
}

-- ---------------------------------------------------------------------------
-- VALIDATION API — drift detection between registry and live legacy configs.
-- Returns a list of mismatch strings; empty means registry and live config agree.
-- ---------------------------------------------------------------------------
function EconomyRegistry.validateAgainstLive(): { string }
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local mismatches = {}
	local function check(label: string, registryValue: any, liveValue: any)
		if registryValue ~= liveValue then
			table.insert(mismatches, string.format("%s: registry=%s live=%s", label, tostring(registryValue), tostring(liveValue)))
		end
	end
	local okE, Economy = pcall(function()
		return require(ReplicatedStorage.GF.Shared.Configs.Economy)
	end)
	if okE and type(Economy) == "table" and type(Economy.PayoutByDifficulty) == "table" then
		for diff, row in pairs(EconomyRegistry.PayoutByDifficulty) do
			local live = Economy.PayoutByDifficulty[diff]
			if live then
				check("payout." .. diff .. ".credits", row.credits, live.credits)
				check("payout." .. diff .. ".xp", row.xp, live.xp)
			end
		end
	else
		table.insert(mismatches, "Economy config unreadable")
	end
	local okC, Caches = pcall(function()
		return require(ReplicatedStorage.GF.Shared.Configs.Caches)
	end)
	if okC and type(Caches) == "table" and type(Caches.Tiers) == "table" then
		for _, tier in Caches.Tiers do
			local reg = EconomyRegistry.CacheTiers[tier.id]
			if reg then
				check("cache." .. tier.id .. ".augments", reg.augments, tier.augments)
				for rarity, w in pairs(reg.rarityWeights) do
					check("cache." .. tier.id .. ".weights." .. rarity, w, tier.weights[rarity])
				end
				for cls, c in pairs(reg.enemyChance) do
					check("cache." .. tier.id .. ".enemyChance." .. cls, c, tier.enemyChance[cls])
				end
			end
		end
	else
		table.insert(mismatches, "Caches config unreadable")
	end
	return mismatches
end

return EconomyRegistry
