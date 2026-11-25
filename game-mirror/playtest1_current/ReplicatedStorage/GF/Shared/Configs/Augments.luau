--!strict

-- S11-042 documented magnitude ranges per rarity tier (C/R/E/L), as fractions:
-- recoil reduction 3-6/5-9/8-13/10-17%, reload speed 2-4/3-6/5-9/7-12%, magazine 3-6/5-10/8-15/12-20%.
-- Rarity shifts the magnitude band, never a rarity-based raw damage multiplier (S11-038).
local RARITY_MAGNITUDE = {
	recoil = { C = { 0.03, 0.06 }, R = { 0.05, 0.09 }, E = { 0.08, 0.13 }, L = { 0.10, 0.17 } },
	reloadSpeed = { C = { 0.02, 0.04 }, R = { 0.03, 0.06 }, E = { 0.05, 0.09 }, L = { 0.07, 0.12 } },
	magazine = { C = { 0.03, 0.06 }, R = { 0.05, 0.10 }, E = { 0.08, 0.15 }, L = { 0.12, 0.20 } },
}

local Augments = {}

-- Category pools. The player picks a category at the Armory; every category has at least three
-- distinct archetypes, each with a rarity and a trait range rolled at purchase. Effect keys must stay
-- inside AugmentService.KEYS or they are silently ignored.
local function entry(id, name, category, rarity, cost, effect, trait)
	return {
		id = id, displayName = name, category = category, rarity = rarity,
		slot = (category == "Support") and "Ability" or "Core",
		applies = (category == "Universal") and "Universal" or ((category == "Support") and "Ability" or "Category"),
		cost = cost, effect = effect, trait = trait,
	}
end

Augments.Categories = { "Universal", "AR", "SMG", "LMG", "Shotgun", "Marksman", "Launcher", "Pistol", "Support" }

Augments.List = {
	-- Universal
	entry("StabilityCompensator", "Stability Compensator", "Universal", "Common", 300,
		{ recoil = -0.15, adsSpeed = -0.08 }, { key = "recoil", min = -0.17, max = -0.12 }),
	entry("QuickFeed", "Quick Feed", "Universal", "Rare", 350,
		{ reloadSpeed = 0.12, magazine = -0.10 }, { key = "reloadSpeed", min = 0.10, max = 0.16 }),
	entry("TargetDiscipline", "Target Discipline", "Universal", "Epic", 600,
		{ weakPoint = 0.20, followUpSpeed = -0.15 }, { key = "weakPoint", min = 0.16, max = 0.26 }),

	-- Assault rifles
	entry("BorePolish", "Bore Polish", "AR", "Common", 280,
		{ recoil = -0.12 }, { key = "recoil", min = -0.14, max = -0.09 }),
	entry("MatchTrigger", "Match Trigger", "AR", "Rare", 420,
		{ healthDamage = 0.12 }, { key = "healthDamage", min = 0.09, max = 0.16 }),
	entry("LongBarrel", "Long Barrel", "AR", "Epic", 620,
		{ weakPoint = 0.15, movingAccuracy = -0.05 }, { key = "weakPoint", min = 0.12, max = 0.2 }),

	-- SMGs
	entry("LightBolt", "Light Bolt", "SMG", "Common", 260,
		{ recoil = -0.10 }, { key = "recoil", min = -0.12, max = -0.07 }),
	entry("FastHands", "Fast Hands", "SMG", "Rare", 380,
		{ swapSpeed = 0.25 }, { key = "swapSpeed", min = 0.2, max = 0.32 }),
	entry("CQCRounds", "CQC Rounds", "SMG", "Epic", 560,
		{ healthDamage = 0.18, weakPoint = -0.05 }, { key = "healthDamage", min = 0.14, max = 0.22 }),

	-- LMGs
	entry("BeltFeed", "Belt Feed", "LMG", "Common", 320,
		{ magazine = 0.25 }, { key = "magazine", min = 0.2, max = 0.32 }),
	entry("HeatSink", "Heat Sink", "LMG", "Rare", 440,
		{ recoil = -0.18 }, { key = "recoil", min = -0.2, max = -0.14 }),
	entry("Bipod", "Bipod", "LMG", "Epic", 640,
		{ movingAccuracy = 0.2, swapSpeed = -0.1 }, { key = "movingAccuracy", min = 0.16, max = 0.26 }),

	-- Shotguns
	entry("Choke", "Choke", "Shotgun", "Common", 300,
		{ weakPoint = 0.2 }, { key = "weakPoint", min = 0.16, max = 0.24 }),
	entry("ShellRack", "Shell Rack", "Shotgun", "Rare", 400,
		{ reloadSpeed = 0.2 }, { key = "reloadSpeed", min = 0.16, max = 0.26 }),
	entry("SlugLoad", "Slug Load", "Shotgun", "Epic", 600,
		{ healthDamage = 0.2, blastRadius = -0.2 }, { key = "healthDamage", min = 0.16, max = 0.26 }),

	-- Marksman
	entry("PrecisionChamber", "Precision Chamber", "Marksman", "Common", 500,
		{ weakPoint = 0.2, followUpSpeed = -0.15 }, { key = "weakPoint", min = 0.16, max = 0.25 }),
	entry("StableStock", "Stable Stock", "Marksman", "Rare", 430,
		{ recoil = -0.2 }, { key = "recoil", min = -0.24, max = -0.16 }),
	entry("ArmorPiercer", "Armor Piercer", "Marksman", "Epic", 700,
		{ armorDamage = 0.25 }, { key = "armorDamage", min = 0.2, max = 0.32 }),

	-- Launchers
	entry("WideCharge", "Wide Charge", "Launcher", "Common", 520,
		{ blastRadius = 0.3 }, { key = "blastRadius", min = 0.24, max = 0.38 }),
	entry("ShapedWarhead", "Shaped Warhead", "Launcher", "Rare", 660,
		{ armorDamage = 0.35 }, { key = "armorDamage", min = 0.28, max = 0.42 }),
	entry("QuickLoad", "Quick Load", "Launcher", "Epic", 780,
		{ reloadSpeed = 0.25 }, { key = "reloadSpeed", min = 0.2, max = 0.32 }),

	-- Pistols
	entry("QuickDraw", "Quick Draw", "Pistol", "Common", 250,
		{ swapSpeed = 0.3 }, { key = "swapSpeed", min = 0.24, max = 0.36 }),
	entry("MatchGrade", "Match Grade", "Pistol", "Rare", 360,
		{ healthDamage = 0.15 }, { key = "healthDamage", min = 0.12, max = 0.2 }),
	entry("PistolFastHands", "Fast Hands (Pistol)", "Pistol", "Epic", 480,
		{ reloadSpeed = 0.2, adsRecovery = 0.15 }, { key = "reloadSpeed", min = 0.16, max = 0.24 }),

	-- Support abilities
	entry("ExtendedSentryMagazine", "Extended Sentry Magazine", "Support", "Common", 600,
		{ sentryAmmo = 0.5, cooldown = 0.2 }, { key = "sentryAmmo", min = 0.4, max = 0.6 }),
	entry("FocusedOrbitalStrike", "Focused Orbital Strike", "Support", "Rare", 800,
		{ blastRadius = -0.4, armorDamage = 0.35 }, { key = "blastRadius", min = -0.45, max = -0.35 }),
	entry("CoolantLoop", "Coolant Loop", "Support", "Epic", 720,
		{ cooldown = 0.25 }, { key = "cooldown", min = 0.2, max = 0.3 }),

	-- Authored spec identities (S11-047/048): every category carries its named archetypes.
	-- Universal authored five
	entry("ExtendedMagazine", "Extended Magazine", "Universal", "Common", 300,
		{ magazine = 0.18 }, { key = "magazine", min = 0.14, max = 0.24 }),
	entry("QuickDrawUniversal", "Quick Draw", "Universal", "Rare", 350,
		{ swapSpeed = 0.2 }, { key = "swapSpeed", min = 0.16, max = 0.26 }),
	-- AR authored three
	entry("ARPrecisionChamber", "Precision Chamber", "AR", "Common", 300,
		{ weakPoint = 0.15 }, { key = "weakPoint", min = 0.12, max = 0.2 }),
	entry("LongBore", "Long Bore", "AR", "Rare", 420,
		{ range = 0.2 }, { key = "range", min = 0.16, max = 0.26 }),
	entry("ShieldDisruptorAR", "Shield Disruptor", "AR", "Epic", 600,
		{ shieldDamage = 0.25 }, { key = "shieldDamage", min = 0.2, max = 0.32 }),
	-- SMG authored three
	entry("CloseQuarters", "Close Quarters", "SMG", "Common", 280,
		{ healthDamage = 0.12 }, { key = "healthDamage", min = 0.09, max = 0.16 }),
	entry("SMGQuickFeed", "Quick Feed", "SMG", "Rare", 380,
		{ reloadSpeed = 0.15 }, { key = "reloadSpeed", min = 0.12, max = 0.2 }),
	entry("ControlSpringSMG", "Control Spring", "SMG", "Epic", 560,
		{ recoil = -0.22 }, { key = "recoil", min = -0.26, max = -0.18 }),
	-- LMG authored three
	entry("BeltExtension", "Belt Extension", "LMG", "Common", 320,
		{ magazine = 0.28 }, { key = "magazine", min = 0.22, max = 0.34 }),
	entry("BracedReceiver", "Braced Receiver", "LMG", "Rare", 440,
		{ recoil = -0.2, movingAccuracy = -0.1 }, { key = "recoil", min = -0.24, max = -0.16 }),
	entry("ShieldDisruptorLMG", "Shield Disruptor", "LMG", "Epic", 620,
		{ shieldDamage = 0.25 }, { key = "shieldDamage", min = 0.2, max = 0.32 }),
	-- Shotgun authored three
	entry("TightPattern", "Tight Pattern", "Shotgun", "Common", 300,
		{ weakPoint = 0.15, movingAccuracy = 0.1 }, { key = "weakPoint", min = 0.12, max = 0.2 }),
	entry("TubularFeed", "Tubular Feed", "Shotgun", "Rare", 400,
		{ magazine = 0.3 }, { key = "magazine", min = 0.24, max = 0.36 }),
	entry("CloseBreach", "Close Breach", "Shotgun", "Epic", 600,
		{ healthDamage = 0.22 }, { key = "healthDamage", min = 0.18, max = 0.28 }),
	-- Marksman authored three
	entry("MRPrecisionChamber", "Precision Chamber", "Marksman", "Common", 500,
		{ weakPoint = 0.2 }, { key = "weakPoint", min = 0.16, max = 0.24 }),
	entry("MRLongBore", "Long Bore", "Marksman", "Rare", 430,
		{ range = 0.25 }, { key = "range", min = 0.2, max = 0.3 }),
	entry("WeakpointFocus", "Weakpoint Focus", "Marksman", "Epic", 700,
		{ weakPoint = 0.3 }, { key = "weakPoint", min = 0.24, max = 0.36 }),
	-- Launcher authored three
	entry("FocusedCharge", "Focused Charge", "Launcher", "Common", 520,
		{ blastRadius = -0.2, healthDamage = 0.25 }, { key = "healthDamage", min = 0.2, max = 0.3 }),
	entry("BlastJacket", "Blast Jacket", "Launcher", "Rare", 660,
		{ blastRadius = 0.25 }, { key = "blastRadius", min = 0.2, max = 0.32 }),
	entry("QuickLoader", "Quick Loader", "Launcher", "Epic", 780,
		{ reloadSpeed = 0.25 }, { key = "reloadSpeed", min = 0.2, max = 0.32 }),
	-- Pistol authored three
	entry("PistolQuickDraw", "Quick Draw", "Pistol", "Common", 250,
		{ swapSpeed = 0.3 }, { key = "swapSpeed", min = 0.24, max = 0.36 }),
	entry("ControlSpringPistol", "Control Spring", "Pistol", "Rare", 360,
		{ recoil = -0.18 }, { key = "recoil", min = -0.22, max = -0.14 }),
	entry("PistolLongBore", "Long Bore", "Pistol", "Epic", 480,
		{ range = 0.2 }, { key = "range", min = 0.16, max = 0.24 }),
	-- Support authored four
	entry("FocusedStrike", "Focused Strike", "Support", "Common", 600,
		{ blastRadius = -0.25, supportDamage = 0.3 }, { key = "supportDamage", min = 0.24, max = 0.36 }),
	entry("ShieldExpansion", "Shield Expansion", "Support", "Rare", 700,
		{ blastRadius = 0.3 }, { key = "blastRadius", min = 0.24, max = 0.36 }),
	entry("SentryReinforcement", "Sentry Reinforcement", "Support", "Epic", 800,
		{ sentryHP = 0.5 }, { key = "sentryHP", min = 0.4, max = 0.6 }),
	entry("CommandLink", "Command Link", "Support", "Rare", 650,
		{ cooldown = 0.2 }, { key = "cooldown", min = 0.16, max = 0.24 }),

	-- Legendary tier. The Legendary cache weights existed with nothing of that rarity to roll, so its
	-- weighting fell through to Epic every time (measured 0 Legendary in 120 rolls).
	entry("MasterworkBore", "Masterwork Bore", "Universal", "Legendary", 1400,
		{ recoil = -0.25, weakPoint = 0.12 }, { key = "weakPoint", min = 0.1, max = 0.16 }),
	entry("SiegeChamber", "Siege Chamber", "AR", "Legendary", 1500,
		{ healthDamage = 0.2, armorDamage = 0.15 }, { key = "healthDamage", min = 0.16, max = 0.24 }),
	entry("ExecutionerOptic", "Executioner Optic", "Marksman", "Legendary", 1600,
		{ weakPoint = 0.35 }, { key = "weakPoint", min = 0.28, max = 0.4 }),
	entry("SiegePayload", "Siege Payload", "Launcher", "Legendary", 1700,
		{ blastRadius = 0.45, armorDamage = 0.3 }, { key = "blastRadius", min = 0.36, max = 0.52 }),
	entry("OverclockedCore", "Overclocked Core", "Support", "Legendary", 1600,
		{ cooldown = 0.4, sentryAmmo = 0.4 }, { key = "cooldown", min = 0.32, max = 0.46 }),
	entry("RazorBolt", "Razor Bolt", "SMG", "Legendary", 1500,
		{ healthDamage = 0.24, recoil = -0.12 }, { key = "healthDamage", min = 0.2, max = 0.3 }),
	entry("CounterweightDrum", "Counterweight Drum", "LMG", "Legendary", 1600,
		{ magazine = 0.4, recoil = -0.14 }, { key = "magazine", min = 0.32, max = 0.48 }),
	entry("BreachChoke", "Breach Choke", "Shotgun", "Legendary", 1500,
		{ weakPoint = 0.28, healthDamage = 0.12 }, { key = "weakPoint", min = 0.22, max = 0.34 }),
	entry("ReflexSear", "Reflex Sear", "Pistol", "Legendary", 1400,
		{ swapSpeed = 0.4, adsRecovery = 0.25 }, { key = "swapSpeed", min = 0.32, max = 0.46 }),
}


Augments.ById = {}
Augments.ByCategory = {}
for _, a in Augments.List do
	Augments.ById[a.id] = a
	local list = Augments.ByCategory[a.category]
	if not list then
		list = {}
		Augments.ByCategory[a.category] = list
	end
	table.insert(list, a)
end

-- Rarity weights used when a cache or a category purchase rolls an archetype.
Augments.RarityWeight = { Common = 55, Rare = 28, Epic = 13, Legendary = 4 }

function Augments.get(id: string)
	Augments.RARITY_MAGNITUDE = RARITY_MAGNITUDE
return Augments.ById[id]
end

function Augments.forCategory(category: string): { any }
	return Augments.ByCategory[category] or {}
end

function Augments.countFor(category: string): number
	local list = Augments.ByCategory[category]
	return list and #list or 0
end

-- Weighted pick from one category pool, skipping ids the caller already owns.
function Augments.roll(category: string, owned: { [string]: boolean }?, rng: (number) -> number?): any
	local pool = {}
	local total = 0
	for _, entry in ipairs(Augments.forCategory(category)) do
		if not (owned and owned[entry.id]) then
			local weight = Augments.RarityWeight[entry.rarity] or 10
			total += weight
			table.insert(pool, { entry = entry, weight = weight })
		end
	end
	if total <= 0 then
		return nil
	end
	local picker = rng or math.random
	local target = picker() * total
	local acc = 0
	for _, item in ipairs(pool) do
		acc += item.weight
		if target <= acc then
			return item.entry
		end
	end
	return pool[#pool].entry
end

-- Instance generation (S11). Rarity controls the number of trait entries and their magnitude band;
-- it is not a separate raw damage multiplier. Values are normalized through a quantized quality
-- integer 0..1000 so the exact roll can be displayed and persisted without floating-point drift.
Augments.RarityRank = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }
Augments.TraitCount = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }

local function band(commonMin, commonMax, rareMin, rareMax, epicMin, epicMax, legendaryMin, legendaryMax)
	return {
		Common = { commonMin, commonMax },
		Rare = { rareMin, rareMax },
		Epic = { epicMin, epicMax },
		Legendary = { legendaryMin, legendaryMax },
	}
end

-- Authored percent magnitudes from GOAL_2026-11-24.md §11, expressed as multipliers.
-- Keys absent from the runtime stat allow-list are deliberately not generated yet.
Augments.TraitBands = {
	recoil = band(-0.06, -0.03, -0.09, -0.05, -0.13, -0.08, -0.17, -0.10),
	reloadSpeed = band(0.02, 0.04, 0.03, 0.06, 0.05, 0.09, 0.07, 0.12),
	magazine = band(0.03, 0.06, 0.05, 0.10, 0.08, 0.15, 0.12, 0.20),
	adsSpeed = band(-0.05, -0.03, -0.08, -0.04, -0.11, -0.07, -0.15, -0.10),
	healthDamage = band(0.01, 0.02, 0.02, 0.03, 0.03, 0.05, 0.04, 0.07),
	weakPoint = band(0.02, 0.03, 0.03, 0.05, 0.04, 0.07, 0.06, 0.10),
	shieldDamage = band(0.03, 0.05, 0.05, 0.08, 0.08, 0.12, 0.10, 0.16),
	armorDamage = band(0.03, 0.05, 0.05, 0.08, 0.08, 0.12, 0.10, 0.16),
	blastRadius = band(0.03, 0.05, 0.05, 0.08, 0.07, 0.11, 0.10, 0.15),
	cooldown = band(0.02, 0.03, 0.03, 0.05, 0.04, 0.07, 0.06, 0.10),
	-- Universal swap reduction uses the reload band by specification.
	swapSpeed = band(0.02, 0.04, 0.03, 0.06, 0.05, 0.09, 0.07, 0.12),
	-- Moving accuracy is the implemented ADS-spread/stat family in this build; use the ADS spread band.
	movingAccuracy = band(0.03, 0.05, 0.04, 0.08, 0.07, 0.11, 0.10, 0.15),
	-- Sentry ammunition is the implemented support-sustain stat; use the sentry durability magnitude band.
	sentryAmmo = band(0.03, 0.06, 0.05, 0.09, 0.08, 0.13, 0.10, 0.17),
	-- These legacy keys are retained so old archetypes remain valid, mapped to the nearest authored family.
	followUpSpeed = band(-0.04, -0.02, -0.06, -0.03, -0.09, -0.05, -0.12, -0.07),
	adsRecovery = band(0.02, 0.04, 0.03, 0.06, 0.05, 0.09, 0.07, 0.12),
}

-- Data-driven compatibility pools. Launchers intentionally exclude magazine capacity because RL09 is
-- one-shot; Support excludes weapon-only handling stats. These pools are also the reroll pool.
Augments.PositivePool = {
	Universal = { "recoil", "reloadSpeed", "magazine", "adsSpeed", "weakPoint", "swapSpeed" },
	AR = { "recoil", "reloadSpeed", "magazine", "healthDamage", "weakPoint", "armorDamage", "range" },
	SMG = { "recoil", "reloadSpeed", "magazine", "healthDamage", "movingAccuracy", "swapSpeed" },
	LMG = { "recoil", "reloadSpeed", "magazine", "healthDamage", "armorDamage", "movingAccuracy" },
	Shotgun = { "weakPoint", "reloadSpeed", "magazine", "healthDamage", "blastRadius" },
	Marksman = { "recoil", "weakPoint", "armorDamage", "healthDamage", "adsSpeed", "range" },
	Launcher = { "blastRadius", "armorDamage", "reloadSpeed", "healthDamage" },
	Pistol = { "recoil", "reloadSpeed", "healthDamage", "swapSpeed", "adsRecovery", "range" },
	Support = { "cooldown", "sentryAmmo", "blastRadius", "armorDamage", "supportDamage", "sentryHP" },
}

-- Negative entries are explicit tradeoffs, not benefits with confusing signs. Magnitudes follow the
-- authored examples (+8-15% duration/spread, -8-12% magazine, -10-18% range-ish effects).
Augments.NegativePool = {
	Universal = { "reloadSpeed", "magazine", "movingAccuracy" },
	AR = { "reloadSpeed", "magazine", "movingAccuracy", "range" },
	SMG = { "reloadSpeed", "magazine", "movingAccuracy" },
	LMG = { "reloadSpeed", "magazine", "movingAccuracy" },
	Shotgun = { "reloadSpeed", "magazine", "blastRadius" },
	Marksman = { "reloadSpeed", "adsSpeed", "movingAccuracy", "range" },
	Launcher = { "reloadSpeed", "blastRadius" },
	Pistol = { "reloadSpeed", "magazine", "movingAccuracy" },
	Support = { "cooldown", "blastRadius", "supportDamage", "sentryHP" },
}

Augments.TradeoffBands = {
	reloadSpeed = { -0.15, -0.08 },
	magazine = { -0.12, -0.08 },
	movingAccuracy = { -0.15, -0.08 },
	blastRadius = { -0.18, -0.10 },
	cooldown = { -0.15, -0.08 },
	adsSpeed = { 0.08, 0.15 },
	range = { -0.18, -0.10 },
	supportDamage = { -0.12, -0.08 },
	sentryHP = { -0.15, -0.08 },
}

local function pick(rng)
	if rng then
		return rng()
	end
	return math.random()
end

local function quantize01(rng)
	local q = math.floor(math.clamp(pick(rng), 0, 0.999999) * 1000 + 0.5)
	return q / 1000, q
end

local function bandFor(key, rarity)
	local bands = Augments.TraitBands[key]
	return bands and (bands[rarity] or bands.Common) or nil
end

local function rollPositive(key, rarity, defining, rng)
	local b = bandFor(key, rarity)
	if not b then
		return nil
	end
	local q, quantized = quantize01(rng)
	local minimum, maximum = b[1], b[2]
	if defining and maximum > minimum then
		-- Signature variants are 1.25x the ordinary defining range ceiling, with tradeoffs supplied by
		-- the normal Rare+ generation path. Ordinary archetypes remain inside the base band.
		maximum = minimum + (maximum - minimum) * 1.0
	end
	return {
		key = key,
		value = minimum + (maximum - minimum) * q,
		quality = quantized,
		polarity = "positive",
		defining = defining == true,
	}
end

local function rollNegative(key, rng)
	local b = Augments.TradeoffBands[key]
	if not b then
		return nil
	end
	local q, quantized = quantize01(rng)
	return {
		key = key,
		value = b[1] + (b[2] - b[1]) * q,
		quality = quantized,
		polarity = "negative",
		defining = false,
	}
end

local function containsKey(rows, key)
	for _, row in ipairs(rows) do
		if row.key == key then
			return true
		end
	end
	return false
end

-- Rolls a complete instance trait list. `lockedTrait` is used by reroll: that exact trait survives and
-- the rest of the list is generated around it without duplicating stat keys.
function Augments.rollTraits(entry: any, rng: (number) -> number?, lockedTrait: any?): { any }
	if type(entry) ~= "table" then
		return {}
	end
	local rarity = tostring(entry.rarity or "Common")
	local count = Augments.TraitCount[rarity] or 1
	local rows = {}
	local lockedKey = type(lockedTrait) == "table" and tostring(lockedTrait.key or "") or ""
	if lockedKey ~= "" and bandFor(lockedKey, rarity) then
		table.insert(rows, {
			key = lockedKey,
			value = tonumber(lockedTrait.value) or 0,
			quality = math.clamp(math.floor(tonumber(lockedTrait.quality) or 0), 0, 1000),
			polarity = lockedTrait.polarity == "negative" and "negative" or "positive",
			defining = lockedTrait.defining == true,
			locked = true,
		})
	end
	local definingKey = type(entry.trait) == "table" and entry.trait.key or nil
	if definingKey and not containsKey(rows, definingKey) then
		local defining = rollPositive(definingKey, rarity, true, rng)
		if defining then
			table.insert(rows, defining)
		end
	end
	local positivePool = Augments.PositivePool[entry.category] or Augments.PositivePool.Universal
	local negativePool = Augments.NegativePool[entry.category] or Augments.NegativePool.Universal
	-- Rare+ items carry an explicit tradeoff whenever there are enough trait slots for one.
	if rarity ~= "Common" and count >= 2 then
		local hasNegative = false
		for _, row in ipairs(rows) do
			if row.polarity == "negative" then hasNegative = true end
		end
		if not hasNegative then
			local start = math.floor(pick(rng) * #negativePool) + 1
			for offset = 0, #negativePool - 1 do
				local key = negativePool[((start + offset - 1) % #negativePool) + 1]
				if not containsKey(rows, key) then
					local negative = rollNegative(key, rng)
					if negative then
						table.insert(rows, negative)
						break
					end
				end
			end
		end
	end
	local guard = 0
	while #rows < count and guard < 64 do
		guard += 1
		local key = positivePool[math.floor(pick(rng) * #positivePool) + 1]
		if key and not containsKey(rows, key) then
			local positive = rollPositive(key, rarity, false, rng)
			if positive then
				table.insert(rows, positive)
			end
		end
	end
	return rows
end

-- Compatibility shim for older callers: return the defining roll from a complete instance roll.
function Augments.rollTrait(entry: any, rng: (number) -> number?): (string?, number?)
	local rows = Augments.rollTraits(entry, rng)
	for _, row in ipairs(rows) do
		if row.defining then
			return row.key, row.value
		end
	end
	local first = rows[1]
	if first then
		return first.key, first.value
	end
	return nil, nil
end

return Augments

