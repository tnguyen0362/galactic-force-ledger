--!strict
-- AugmentGenerator: server-authoritative randomized item generation.
-- Mirrors gf-research/augment/pylib/augment_core.py exactly — the Python reference is the
-- validation harness; divergence between the two is a defect by definition (spec §56/90).
-- Implements: weighted sampling without replacement (§34), conflict-aware eligibility (§36),
-- coupled-package atomicity (§25), rarity trait counts (§6).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AugmentTraits = require(ReplicatedStorage.GF.Shared.Configs.AugmentTraits)

local Traits = AugmentTraits.Traits
local RARITY_COUNT = AugmentTraits.RarityCount
local RARITY_SHORT = AugmentTraits.RarityShort
local RARITY_ORDER = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }

local AugmentGenerator = {}

-- Loot randomness stream: server entropy, per spec §88 — never mission seeds, never client input.
local lootRng = Random.new((os.time() + math.floor(os.clock() * 1e6)) % 2147483647)

function AugmentGenerator.lootRandom(): number
	return lootRng:NextNumber()
end

local function rarityIndex(rarity: string): number
	return RARITY_ORDER[rarity] or 0
end

function AugmentGenerator.eligibleTraits(weaponCategory: string, rarity: string, family: string?): { any }
	local short = RARITY_SHORT[rarity]
	local out = {}
	for traitId, t in Traits do
		if t.bands[short] ~= nil and rarityIndex(rarity) >= rarityIndex(t.minRarity) then
			local compatOk = false
			for _, c in t.compat do
				if c == "Universal" or c == weaponCategory then
					compatOk = true
					break
				end
			end
			if compatOk and (family == nil or t.family == family) then
				table.insert(out, { id = traitId, def = t })
			end
		end
	end
	return out
end

local function hasConflictGroup(rows, group)
	for _, row in rows do
		local tdef = Traits[row.traitId]
		if tdef and tdef.conflictGroup == group then
			return true
		end
	end
	return false
end

-- Weighted sampling without replacement, conflict-aware. Locked trait rows survive exactly.
function AugmentGenerator.rollTraits(familyFilter: string?, rarity: string, weaponCategory: string, rng: (() -> number)?, locked: any?): { any }
	local picker = rng or AugmentGenerator.lootRandom
	local count = RARITY_COUNT[rarity] or 1
	local rows = {}
	local used = {}
	if type(locked) == "table" and type(locked.traitId) == "string" then
		table.insert(rows, {
			traitId = locked.traitId,
			key = locked.key,
			value = locked.value,
			quality = locked.quality or 0,
			polarity = locked.polarity or "positive",
			family = locked.family,
			coupled = locked.coupled,
			conditional = locked.conditional,
			locked = true,
		})
		used[locked.traitId] = true
	end
	local pool = AugmentGenerator.eligibleTraits(weaponCategory, rarity, familyFilter)
	local guard = 0
	while #rows < count and guard < 128 do
		guard += 1
		local candidates = {}
		local totalWeight = 0
		for _, entry in pool do
			if not used[entry.id] then
				local grp = entry.def.conflictGroup
				if not grp or not hasConflictGroup(rows, grp) then
					table.insert(candidates, entry)
					totalWeight += entry.def.weight or 1
				end
			end
		end
		if #candidates == 0 then
			break -- feasible pool exhausted: valid documented outcome, never malformed items
		end
		local pick = picker() * totalWeight
		local acc = 0
		local chosen = candidates[#candidates]
		for _, entry in candidates do
			acc += entry.def.weight or 1
			if pick <= acc then
				chosen = entry
				break
			end
		end
		local band = chosen.def.bands[RARITY_SHORT[rarity]]
		local value = band[1] + picker() * (band[2] - band[1])
		local quality = math.floor((value - band[1]) / math.max(band[2] - band[1], 1e-9) * 1000 + 0.5)
		local row = {
			traitId = chosen.id,
			key = chosen.def.stat,
			value = math.floor(value * 10000 + 0.5) / 10000,
			quality = quality,
			polarity = "positive",
			family = chosen.def.family,
		}
		if chosen.def.coupled then
			row.coupled = chosen.def.coupled
		end
		if chosen.def.conditional then
			row.conditional = chosen.def.conditional
		end
		table.insert(rows, row)
		used[chosen.id] = true
	end
	return rows
end

-- Full item generation. definition: {definitionId, family?} — family nil means dominant-family derivation.
function AugmentGenerator.generateItem(definition: any, rarity: string, weaponCategory: string, rng: (() -> number)?): any
	local rows = AugmentGenerator.rollTraits(definition.family, rarity, weaponCategory, rng)
	local dominant = definition.family
	if not dominant then
		local counts = {}
		for _, row in rows do
			local fam = Traits[row.traitId] and Traits[row.traitId].family or "Ballistic"
			counts[fam] = (counts[fam] or 0) + 1
		end
		dominant = "Ballistic"
		local best = -1
		for fam, n in counts do
			if n > best then
				best = n
				dominant = fam
			end
		end
	end
	return {
		definitionId = definition.definitionId,
		rarity = rarity,
		family = dominant,
		compatibility = weaponCategory,
		traits = rows,
		generationVersion = AugmentTraits.RegistryVersion,
	}
end

return AugmentGenerator
