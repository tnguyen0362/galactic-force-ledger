--!strict
-- VERSIONED REWARD SOURCE REGISTRY (economy spec §17, Stage 3).
-- Single authoritative location for every drop rate, reward composition and cache probability.
-- Before this module, drop rates were scattered: per-enemy loot fields in Enemies.luau, cache
-- chances in Caches.luau tier tables, mission baselines in Economy.luau. Those remain live
-- during migration; this registry consolidates them with the full §17 schema so the reward
-- system is maintainable and mathematically inspectable (§18-20 compound-process analysis
-- reads these tables directly).
--
-- Initial values preserve live behavior exactly (migration, not regression); division-level
-- cache/technology identity per §16 is NEW and tagged provisional for Stage 10 calibration.
local RewardSources = {}

RewardSources.REWARD_VERSION = "1.0.0"

-- ---------------------------------------------------------------------------
-- ENCOUNTER CATEGORIES (§16 source identity)
-- ordinary_infantry / heavy_infantry / spectre_division / revenant_division /
-- standard_bastion / bastion_siege / major_war_machine / installation
-- ---------------------------------------------------------------------------

-- Cache probability class tables preserve the live design: the dropped cache tier is the
-- mission's difficulty-indexed tier, and the drop CHANCE depends on that tier (higher-tier
-- missions drop fewer, better caches). Values mirror Caches.luau enemyChance exactly.
local CACHE_CHANCE_BY_TIER = {
	--           infantry  heavy  commander
	Common =    { 0.01,    0.04,  0.07 },
	Rare =      { 0.01,    0.05,  0.09 },
	Epic =      { 0.00,    0.02,  0.05 },
	Legendary = { 0.00,    0.00,  0.00 },
}

-- §16 division identity (NEW, provisional): Spectre improved cache opportunities,
-- Revenant rare prestigious technology and superior cache opportunities.
local DIVISION_CACHE_MULTIPLIER = { Spectre = 1.5, Revenant = 2.0 }
local DIVISION_RARITY_IMPROVEMENT = { Revenant = 1.5 } -- non-Common rarity weight multiplier at roll time

RewardSources.ClassDefaults = {
	ordinary_infantry = {
		SourceCategory = "enemy",
		EncounterCategory = "ordinary_infantry",
		cacheClass = "infantry",
		blueprintEligible = false,
	},
	heavy_infantry = {
		SourceCategory = "enemy",
		EncounterCategory = "heavy_infantry",
		cacheClass = "heavy",
		blueprintEligible = false,
	},
	commander = {
		SourceCategory = "enemy",
		EncounterCategory = "heavy_infantry",
		cacheClass = "commander",
		blueprintEligible = false,
	},
	vehicle = {
		SourceCategory = "enemy",
		EncounterCategory = "standard_bastion",
		cacheClass = "heavy",
		blueprintEligible = false,
	},
	boss = {
		SourceCategory = "enemy",
		EncounterCategory = "major_war_machine",
		cacheClass = "boss", -- guaranteed drop, uncapped
		blueprintEligible = true, -- pity floor 5 qualifying extracted kills (existing LootService)
	},
}

-- ---------------------------------------------------------------------------
-- PER-ENEMY RESOURCE DISTRIBUTIONS — exact consolidation of live Enemies.luau values.
-- Bernoulli model per §19: energyCells/militaryTechnology are Bernoulli(p) x 1 unit events,
-- scrap is a fixed quantity per kill. Joint structure (§18): independent marginal rolls,
-- documented here so the compound-process model uses correct per-source parameters.
-- ---------------------------------------------------------------------------
local function bernoulli(p: number, amount: number)
	return { kind = "bernoulli", p = p, amount = amount }
end
local function fixed(amount: number)
	return { kind = "fixed", amount = amount }
end

RewardSources.Enemies = {
	Rifleman =          { class = "ordinary_infantry", scrap = fixed(2),  energyCells = bernoulli(0.10, 1), militaryTechnology = bernoulli(0.00, 1) },
	Scout =             { class = "ordinary_infantry", scrap = fixed(1),  energyCells = bernoulli(0.05, 1), militaryTechnology = bernoulli(0.00, 1) },
	Marksman =          { class = "ordinary_infantry", scrap = fixed(2),  energyCells = bernoulli(0.15, 1), militaryTechnology = bernoulli(0.02, 1) },
	Heavy =             { class = "heavy_infantry",    scrap = fixed(4),  energyCells = bernoulli(0.60, 1), militaryTechnology = bernoulli(0.10, 1) },
	Officer =           { class = "commander",         scrap = fixed(3),  energyCells = bernoulli(0.35, 1), militaryTechnology = bernoulli(0.20, 1) },
	-- Spectre Division: specialized technology focus (§16)
	SpectreLeader =     { class = "heavy_infantry", division = "Spectre", scrap = fixed(4), energyCells = bernoulli(0.50, 1), militaryTechnology = bernoulli(0.25, 1) },
	SpectreAssault =    { class = "heavy_infantry", division = "Spectre", scrap = fixed(3), energyCells = bernoulli(0.35, 1), militaryTechnology = bernoulli(0.12, 1) },
	SpectreWeapons =    { class = "heavy_infantry", division = "Spectre", scrap = fixed(4), energyCells = bernoulli(0.60, 1), militaryTechnology = bernoulli(0.15, 1) },
	SpectrePrecision =  { class = "heavy_infantry", division = "Spectre", scrap = fixed(3), energyCells = bernoulli(0.40, 1), militaryTechnology = bernoulli(0.15, 1) },
	SpectreSupport =    { class = "heavy_infantry", division = "Spectre", scrap = fixed(3), energyCells = bernoulli(0.45, 1), militaryTechnology = bernoulli(0.20, 1) },
	-- Revenant Division: prestigious technology (§16)
	RevenantLeader =    { class = "heavy_infantry", division = "Revenant", scrap = fixed(6), energyCells = bernoulli(0.75, 1), militaryTechnology = bernoulli(0.40, 1) },
	RevenantAssault =   { class = "heavy_infantry", division = "Revenant", scrap = fixed(5), energyCells = bernoulli(0.60, 1), militaryTechnology = bernoulli(0.30, 1) },
	RevenantWeapons =   { class = "heavy_infantry", division = "Revenant", scrap = fixed(6), energyCells = bernoulli(0.80, 1), militaryTechnology = bernoulli(0.35, 1) },
	RevenantPrecision = { class = "heavy_infantry", division = "Revenant", scrap = fixed(5), energyCells = bernoulli(0.65, 1), militaryTechnology = bernoulli(0.35, 1) },
	RevenantDefense =   { class = "heavy_infantry", division = "Revenant", scrap = fixed(5), energyCells = bernoulli(0.70, 1), militaryTechnology = bernoulli(0.40, 1) },
	-- Bastion vehicles and war machines (§16: substantial encounter-specific rewards)
	BastionTank =       { class = "vehicle", scrap = fixed(8),  energyCells = bernoulli(1.00, 1), militaryTechnology = bernoulli(0.50, 1) },
	BastionWalker =     { class = "boss",    scrap = fixed(12), energyCells = bernoulli(1.00, 1), militaryTechnology = bernoulli(0.75, 1) },
	BastionSiege =      { class = "boss",    scrap = fixed(14), energyCells = bernoulli(1.00, 1), militaryTechnology = bernoulli(0.80, 1) },
	LeviathanWalker =   { class = "boss",    scrap = fixed(30), energyCells = bernoulli(1.00, 1), militaryTechnology = bernoulli(1.00, 1) },
	HighMarshalVeyr =   { class = "boss",    scrap = fixed(25), energyCells = bernoulli(1.00, 1), militaryTechnology = bernoulli(1.00, 1) },
}

-- ---------------------------------------------------------------------------
-- INSTALLATION REWARD IDENTITY (§16 — NEW, provisional). Composition follows the
-- installation's purpose: comms = advanced electronics (militaryTechnology),
-- power/shield = energy cells, logistics/supply = scrap, stronghold = miltech + caches.
-- Delivered through lootable installation crates (integration in LootService).
-- ---------------------------------------------------------------------------
RewardSources.Installations = {
	comms_relay = {
		displayName = "Communications Relay",
		composition = { militaryTechnology = bernoulli(0.85, 1), energyCells = bernoulli(0.35, 1), scrap = fixed(1) },
		cacheChance = 0.04,
		cratesPerSite = 2,
	},
	shield_generator = {
		displayName = "Shield Generator",
		composition = { energyCells = bernoulli(0.9, 2), militaryTechnology = bernoulli(0.15, 1), scrap = fixed(1) },
		cacheChance = 0.02,
		cratesPerSite = 2,
	},
	supply_cache = {
		displayName = "Supply Cache",
		composition = { scrap = fixed(4), energyCells = bernoulli(0.25, 1) },
		cacheChance = 0.03,
		cratesPerSite = 3,
	},
	stronghold = {
		displayName = "Stronghold",
		composition = { militaryTechnology = bernoulli(0.6, 1), scrap = fixed(2), energyCells = bernoulli(0.4, 1) },
		cacheChance = 0.08,
		cratesPerSite = 4,
	},
	artillery = {
		displayName = "Artillery Emplacement",
		composition = { scrap = fixed(3), militaryTechnology = bernoulli(0.3, 1) },
		cacheChance = 0.03,
		cratesPerSite = 2,
	},
	extraction_pad = {
		displayName = "Extraction Pad",
		composition = { scrap = fixed(1) },
		cacheChance = 0.0,
		cratesPerSite = 0, -- non-lootable: the extraction pad is the way out, not a reward source
	},
}

-- ---------------------------------------------------------------------------
-- RESOLVER API
-- ---------------------------------------------------------------------------

function RewardSources.enemyClass(enemyDef: any): string
	if not enemyDef then
		return "ordinary_infantry"
	end
	if enemyDef.tier == "Boss" then
		return "boss"
	end
	if enemyDef.tier == "Vehicle" then
		return "vehicle"
	end
	if enemyDef.id == "Officer" then
		return "commander"
	end
	if enemyDef.tier == "Elite" then
		return "heavy_infantry"
	end
	return "ordinary_infantry"
end

-- Full §17-shaped source definition for an enemy id, resolved from per-enemy data + class defaults.
function RewardSources.forEnemy(enemyId: string, enemyDef: any): any
	local entry = RewardSources.Enemies[enemyId]
	local class = entry and entry.class or RewardSources.enemyClass(enemyDef)
	local classDef = RewardSources.ClassDefaults[class] or RewardSources.ClassDefaults.ordinary_infantry
	return {
		SourceId = enemyId,
		SourceCategory = classDef.SourceCategory,
		EncounterCategory = classDef.EncounterCategory,
		Division = entry and entry.division or (enemyDef and enemyDef.division) or nil,
		EligibleResources = {
			scrap = entry ~= nil,
			energyCells = entry ~= nil and (entry.energyCells.p or 0) > 0 or false,
			militaryTechnology = entry ~= nil and (entry.militaryTechnology.p or 0) > 0 or false,
		},
		ResourceQuantityDistributions = entry and {
			scrap = entry.scrap,
			energyCells = entry.energyCells,
			militaryTechnology = entry.militaryTechnology,
		} or nil,
		CacheProbability = nil, -- resolved per-mission-tier via cacheChanceFor()
		CacheRarityDistribution = "missionTier", -- difficulty-indexed, CacheService.missionTier
		BlueprintRules = classDef.blueprintEligible and { pityThreshold = 5, requiresExtraction = true } or nil,
		EligibilityPolicy = "killerSquad",
		ExtractionPolicy = "salvageLostOnFailure", -- spec §30
		RewardVersion = RewardSources.REWARD_VERSION,
		_cacheClass = classDef.cacheClass,
		_division = entry and entry.division or nil,
	}
end

-- Cache drop probability for an enemy, indexed by the mission's cache tier (preserves live design),
-- with §16 division multipliers applied (Spectre 1.5x, Revenant 2.0x, provisional).
function RewardSources.cacheChanceFor(enemyId: string, enemyDef: any, missionCacheTier: string): number
	if enemyDef and enemyDef.tier == "Boss" then
		return 1.0 -- bosses guarantee a cache (live design)
	end
	local resolved = RewardSources.forEnemy(enemyId, enemyDef)
	local tierRow = CACHE_CHANCE_BY_TIER[missionCacheTier] or CACHE_CHANCE_BY_TIER.Common
	local classIdx = if resolved._cacheClass == "commander" then 3 elseif resolved._cacheClass == "heavy" then 2 else 1
	local base = tierRow[classIdx]
	local mult = 1.0
	if resolved._division and DIVISION_CACHE_MULTIPLIER[resolved._division] then
		mult = DIVISION_CACHE_MULTIPLIER[resolved._division]
	end
	return math.min(1.0, base * mult)
end

-- Non-Common rarity weight multiplier when a division improves cache contents at roll time.
function RewardSources.rarityImprovement(enemyId: string): number
	local entry = RewardSources.Enemies[enemyId]
	if entry and entry.division and DIVISION_RARITY_IMPROVEMENT[entry.division] then
		return DIVISION_RARITY_IMPROVEMENT[entry.division]
	end
	return 1.0
end

function RewardSources.forInstallation(siteType: string): any
	local def = RewardSources.Installations[siteType]
	if not def then
		return nil
	end
	return {
		SourceId = "installation:" .. siteType,
		SourceCategory = "installation",
		EncounterCategory = "installation",
		EligibleResources = { scrap = true, energyCells = true, militaryTechnology = true },
		ResourceQuantityDistributions = def.composition,
		CacheProbability = def.cacheChance,
		CacheRarityDistribution = "missionTier",
		BlueprintRules = nil,
		EligibilityPolicy = "squadShared",
		ExtractionPolicy = "salvageLostOnFailure",
		RewardVersion = RewardSources.REWARD_VERSION,
		_cratesPerSite = def.cratesPerSite,
	}
end

return RewardSources
