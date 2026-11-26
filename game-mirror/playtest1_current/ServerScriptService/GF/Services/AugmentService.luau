--!nonstrict
-- Server-authoritative augment inventory and lifecycle. Instances are keyed by UID; archetype ids only
-- identify the catalog template. This is what allows duplicate copies, reroll offers, dismantle/fusion
-- protection and exact persisted trait rolls.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Augments = require(ReplicatedStorage.GF.Shared.Configs.Augments)
local ProfileService = require(script.Parent.ProfileService)

local AugmentService = {}
local KEYS = {
	"recoil", "adsSpeed", "reloadSpeed", "magazine", "shieldDamage", "healthDamage",
	"weakPoint", "followUpSpeed", "swapSpeed", "adsRecovery", "movingAccuracy",
	"sentryAmmo", "cooldown", "blastRadius", "armorDamage", "range", "supportDamage", "sentryHP",
	-- registry v2 additions: without these, add() silently dropped the newly wired stats at resolution
	"fireRate", "spreadHip", "spreadAds", "reserveAmmo", "projectileVelocity", "componentDamage",
}

local REROLL_COST = { Common = 25, Rare = 50, Epic = 100, Legendary = 200 }
local DISMANTLE_SCRAP = { Common = 8, Rare = 18, Epic = 40, Legendary = 85 }
local NEXT_RARITY = { Common = "Rare", Rare = "Epic", Epic = "Legendary" }
local SECOND_SOCKET_XP = 650

local function empty()
	local out = {}
	for _, k in ipairs(KEYS) do
		out[k] = 0
	end
	return out
end

local function add(out, key, value)
	if out[key] ~= nil and type(value) == "number" and value == value and math.abs(value) ~= math.huge then
		out[key] += value
	end
end

local function countKeys(t)
	local n = 0
	for _ in pairs(t or {}) do
		n += 1
	end
	return n
end

local function copyTrait(row)
	return {
		key = tostring(row.key or ""),
		value = tonumber(row.value) or 0,
		quality = math.clamp(math.floor(tonumber(row.quality) or 0), 0, 1000),
		polarity = row.polarity == "negative" and "negative" or "positive",
		defining = row.defining == true,
		locked = row.locked == true,
	}
end

local function copyTraits(rows)
	local out = {}
	for _, row in ipairs(rows or {}) do
		if type(row) == "table" and type(row.key) == "string" then
			table.insert(out, copyTrait(row))
		end
	end
	return out
end

local function newUid()
	return "aug_" .. string.lower(string.gsub(HttpService:GenerateGUID(false), "-", ""))
end

function AugmentService.newUid()
	return newUid()
end

local function itemFromDef(def, traits, source)
	return {
		uid = newUid(),
		archetypeId = def.id,
		category = def.category,
		rarity = def.rarity,
		traits = copyTraits(traits),
		favorite = false,
		source = tostring(source or "unknown"),
		obtainedAt = os.time(),
	}
end

-- Migrates legacy one-copy-per-archetype profiles into the instance inventory without deleting the old
-- ownership index. ownedAugments remains a coarse "have ever owned this archetype" marker for catalog UI.
function AugmentService.ensureInventory(profile)
	if type(profile) ~= "table" then
		return {}
	end
	if type(profile.augmentInventory) ~= "table" then
		profile.augmentInventory = {}
	end
	local inventory = profile.augmentInventory
	if type(profile.ownedAugments) == "table" then
		for archetypeId, owned in pairs(profile.ownedAugments) do
			if owned == true and type(archetypeId) == "string" then
				local exists = false
				for _, item in pairs(inventory) do
					if type(item) == "table" and item.archetypeId == archetypeId then
						exists = true
						break
					end
				end
				if not exists then
					local def = Augments.get(archetypeId)
					if def then
						local traits = {}
						local legacy = profile.augmentTraits and profile.augmentTraits[archetypeId]
						if type(legacy) == "table" and type(legacy.key) == "string" then
							traits = { {
								key = legacy.key,
								value = tonumber(legacy.value) or 0,
								quality = math.clamp(math.floor(tonumber(legacy.quality) or 500), 0, 1000),
								polarity = "positive",
								defining = true,
							} }
						else
							traits = Augments.rollTraits(def)
						end
						local item = itemFromDef(def, traits, "legacy migration")
						item.uid = "legacy-" .. archetypeId
						inventory[item.uid] = item
					end
				end
			end
		end
	end
	return inventory
end

function AugmentService.inventoryCount(profile)
	return countKeys(AugmentService.ensureInventory(profile))
end

function AugmentService.findItem(profile, ref)
	if type(profile) ~= "table" or type(ref) ~= "string" or ref == "" then
		return nil
	end
	local inventory = AugmentService.ensureInventory(profile)
	local direct = inventory[ref]
	if type(direct) == "table" then
		return direct
	end
	-- Legacy loadouts stored archetype ids rather than UIDs. Resolve those to the first matching copy so
	-- old saves continue to work, then callers can write the concrete UID back.
	for _, item in pairs(inventory) do
		if type(item) == "table" and item.archetypeId == ref then
			return item
		end
	end
	return nil
end

local function traitSummary(item)
	local parts = {}
	for _, trait in ipairs(item and item.traits or {}) do
		local sign = trait.value >= 0 and "+" or ""
		table.insert(parts, string.format("%s %s%.1f%% q%d", tostring(trait.key), sign, (tonumber(trait.value) or 0) * 100, tonumber(trait.quality) or 0))
	end
	return table.concat(parts, " · ")
end

function AugmentService.publicItem(profile, item)
	if type(item) ~= "table" then
		return nil
	end
	local def = Augments.get(item.archetypeId)
	local traits = {}
	for _, trait in ipairs(item.traits or {}) do
		table.insert(traits, copyTrait(trait))
	end
	return {
		uid = item.uid,
		id = item.archetypeId,
		archetypeId = item.archetypeId,
		name = def and def.displayName or item.archetypeId,
		category = item.category,
		rarity = item.rarity,
		traits = traits,
		traitText = traitSummary(item),
		quality = (function()
			local best = 0
			for _, trait in ipairs(item.traits or {}) do
				best = math.max(best, tonumber(trait.quality) or 0)
			end
			return best
		end)(),
		favorite = item.favorite == true,
		protected = AugmentService.isProtected(profile, item.uid),
		pending = AugmentService.isPending(profile, item.uid),
		source = item.source,
		obtainedAt = item.obtainedAt,
	}
end

function AugmentService.inventoryRows(profile)
	local rows = {}
	for _, item in pairs(AugmentService.ensureInventory(profile)) do
		local row = AugmentService.publicItem(profile, item)
		if row then
			table.insert(rows, row)
		end
	end
	table.sort(rows, function(a, b)
		if a.rarity ~= b.rarity then
			return (Augments.RarityRank[b.rarity] or 0) < (Augments.RarityRank[a.rarity] or 0)
		end
		if a.category ~= b.category then
			return tostring(a.category) < tostring(b.category)
		end
		return tostring(a.name) < tostring(b.name)
	end)
	return rows
end

local function applyItem(out, item)
	if type(item) ~= "table" then
		return
	end
	for _, trait in ipairs(item.traits or {}) do
		add(out, trait.key, tonumber(trait.value) or 0)
	end
end

function AugmentService.forProfile(profile)
	local out = empty()
	if type(profile) ~= "table" then
		return out
	end
	local loadout = profile.selectedLoadout
	if type(loadout) ~= "table" then
		return out
	end
	local slots = loadout.weaponAugments
	if type(slots) == "table" then
		for key, entry in pairs(slots) do
			if type(entry) == "table" then
				for _, ref in pairs(entry) do
					applyItem(out, AugmentService.findItem(profile, ref))
				end
			elseif type(entry) == "string" then
				applyItem(out, AugmentService.findItem(profile, entry))
			end
		end
	end
	if type(loadout.abilityAugment) == "string" then
		applyItem(out, AugmentService.findItem(profile, loadout.abilityAugment))
	end
	-- Additive aggregation first, then authored per-stat caps. Signed-benefit stats clamp symmetrically.
	local CLAMP = {
		blastRadius = 0.25, cooldown = 0.20, magazine = 0.35, reloadSpeed = 0.25,
		healthDamage = 0.15, weakPoint = 0.20, shieldDamage = 0.30, armorDamage = 0.30,
		adsSpeed = 0.25, recoil = 0.35, movingAccuracy = 0.35, range = 0.30, supportDamage = 0.15, sentryHP = 0.30,
		fireRate = 0.12, spreadHip = 0.25, spreadAds = 0.25, reserveAmmo = 0.35, swapSpeed = 0.35, projectileVelocity = 0.30,
	}
	local SIGNED = { recoil = true, adsSpeed = true, movingAccuracy = true, fireRate = true, spreadHip = true, spreadAds = true, reserveAmmo = true, swapSpeed = true, projectileVelocity = true }
	for key, cap in pairs(CLAMP) do
		local v = out[key]
		if type(v) == "number" then
			if SIGNED[key] then
				out[key] = math.clamp(v, -cap, cap)
			elseif key == "range" or key == "supportDamage" or key == "sentryHP" then
				-- Negative tradeoffs are legal, but the spec forbids zero/negative baseline intervals.
				out[key] = math.clamp(v, -0.35, cap)
			else
				out[key] = math.clamp(v, 0, cap)
			end
		end
	end
	out.slotsUsed = 0
	if type(slots) == "table" then
		for _, entry in pairs(slots) do
			if type(entry) == "table" then
				for _ in pairs(entry) do
					out.slotsUsed += 1
				end
			elseif type(entry) == "string" then
				out.slotsUsed += 1
			end
		end
	end
	return out
end

AugmentService.BASELINE_CAPACITY = 200
AugmentService.CAPACITY_STEP = 50
AugmentService.CAPACITY_MAX = 400
AugmentService.EXPAND_COST = { energyCells = 10, militaryTechnology = 3, credits = 1000 }

function AugmentService.grantAugment(profile, augmentId, opts)
	local def = type(augmentId) == "string" and Augments.get(augmentId)
	if not def or type(profile) ~= "table" then
		return nil, "unknown augment"
	end
	local inventory = AugmentService.ensureInventory(profile)
	local requestedUid = type(opts) == "table" and type(opts.uid) == "string" and opts.uid or nil
	if requestedUid and type(inventory[requestedUid]) == "table" then
		return requestedUid, inventory[requestedUid]
	end
	local capacity = tonumber(profile.augmentCapacity) or AugmentService.BASELINE_CAPACITY
	local owned = countKeys(inventory)
	if owned >= capacity then
		workspace:SetAttribute("GF_AugmentCapacity", string.format("full %d/%d", owned, capacity))
		return nil, "inventory full"
	end
	local traits = type(opts) == "table" and opts.traits or nil
	if type(traits) ~= "table" then
		traits = Augments.rollTraits(def)
	end
	local item = itemFromDef(def, traits, type(opts) == "table" and opts.source or "unknown")
	if requestedUid then
		item.uid = requestedUid
	end
	inventory[item.uid] = item
	profile.ownedAugments = profile.ownedAugments or {}
	profile.ownedAugments[def.id] = true
	workspace:SetAttribute("GF_AugmentCapacity", string.format("%d/%d", owned + 1, capacity))
	workspace:SetAttribute("GF_AugmentGranted", string.format("%s:%s:%s", item.uid, def.id, def.rarity))
	return item.uid, item
end

function AugmentService.expandCapacity(profile)
	if type(profile) ~= "table" then
		return false, "no profile"
	end
	local current = tonumber(profile.augmentCapacity) or AugmentService.BASELINE_CAPACITY
	if current >= AugmentService.CAPACITY_MAX then
		return false, "already at max capacity"
	end
	local cost = AugmentService.EXPAND_COST
	local salvage = profile.salvage or {}
	local credits = tonumber(profile.credits) or 0
	if (tonumber(salvage.energyCells) or 0) < cost.energyCells then
		return false, "not enough energy cells"
	end
	if (tonumber(salvage.militaryTechnology) or 0) < cost.militaryTechnology then
		return false, "not enough military technology"
	end
	if credits < cost.credits then
		return false, "not enough credits"
	end
	profile.credits = credits - cost.credits
	profile.salvage.energyCells = salvage.energyCells - cost.energyCells
	profile.salvage.militaryTechnology = salvage.militaryTechnology - cost.militaryTechnology
	profile.augmentCapacity = math.min(AugmentService.CAPACITY_MAX, current + AugmentService.CAPACITY_STEP)
	workspace:SetAttribute("GF_AugmentCapacityExpanded", tostring(profile.augmentCapacity))
	return true, tostring(profile.augmentCapacity)
end

function AugmentService.socketsFor(profile, weaponId)
	if type(profile) ~= "table" or type(weaponId) ~= "string" then
		return 0
	end
	local owned = profile.ownedWeapons and profile.ownedWeapons[weaponId] == true
	if not owned then
		return 0
	end
	local mastery = 0
	if type(profile.weaponMastery) == "table" then
		mastery = tonumber(profile.weaponMastery[weaponId]) or 0
	end
	return mastery >= SECOND_SOCKET_XP and 2 or 1
end

function AugmentService.slotTable(profile)
	if type(profile) ~= "table" then
		return nil
	end
	profile.selectedLoadout = profile.selectedLoadout or {}
	local loadout = profile.selectedLoadout
	if type(loadout.weaponAugments) ~= "table" then
		loadout.weaponAugments = {}
	end
	return loadout.weaponAugments
end

-- AUGMENT-V2 socket migration (D-4): legacy shape weaponAugments[slot] becomes
-- weaponAugments[weaponId][slot]. Lazy migration: numeric keys are rehomed under the loadout
-- primary on first access, so existing saves keep working with zero data loss.
function AugmentService.migrateSockets(profile)
	local slots = AugmentService.slotTable(profile)
	if not slots then
		return nil
	end
	local legacyNumeric = false
	for key in pairs(slots) do
		if type(key) == "number" then
			legacyNumeric = true
			break
		end
	end
	if legacyNumeric then
		local loadout = profile.selectedLoadout or {}
		local primary = tostring(loadout.primary or "AR01")
		slots[primary] = slots[primary] or {}
		for key, ref in pairs(slots) do
			if type(key) == "number" then
				if slots[primary][key] == nil then
					slots[primary][key] = ref
				end
				slots[key] = nil
			end
		end
		workspace:SetAttribute("GF_AugmentSocketsMigrated", primary)
	end
	return slots
end

-- per-weapon socket sub-table (never creates inventory-side effects beyond migration)
function AugmentService.weaponSlots(profile, weaponId)
	local slots = AugmentService.migrateSockets(profile)
	if not slots or type(weaponId) ~= "string" or weaponId == "" then
		return nil
	end
	return slots[weaponId]
end

-- resolution for ONE weapon: aggregates only that weapon's socketed traits.
-- This is the canonical combat consumption entry point post-migration.
function AugmentService.forProfileWeapon(profile, weaponId)
	local out = empty()
	if type(profile) ~= "table" then
		return out
	end
	local wslots = AugmentService.weaponSlots(profile, weaponId)
	if type(wslots) == "table" then
		for _, ref in pairs(wslots) do
			applyItem(out, AugmentService.findItem(profile, ref))
		end
	end
	local loadout = profile.selectedLoadout
	if loadout and type(loadout.abilityAugment) == "string" then
		applyItem(out, AugmentService.findItem(profile, loadout.abilityAugment))
	end
	local CLAMP = {
		blastRadius = 0.25, cooldown = 0.20, magazine = 0.35, reloadSpeed = 0.25,
		healthDamage = 0.15, weakPoint = 0.20, shieldDamage = 0.30, armorDamage = 0.30,
		adsSpeed = 0.25, recoil = 0.35, movingAccuracy = 0.35, range = 0.30, supportDamage = 0.15, sentryHP = 0.30,
		fireRate = 0.12, spreadHip = 0.25, spreadAds = 0.25, reserveAmmo = 0.35, swapSpeed = 0.35, projectileVelocity = 0.30,
	}
	local SIGNED = { recoil = true, adsSpeed = true, movingAccuracy = true, fireRate = true, spreadHip = true, spreadAds = true, reserveAmmo = true, swapSpeed = true, projectileVelocity = true }
	for key, cap in pairs(CLAMP) do
		local v = out[key]
		if type(v) == "number" then
			if SIGNED[key] then
				out[key] = math.clamp(v, -cap, cap)
			elseif key == "range" or key == "supportDamage" or key == "sentryHP" then
				out[key] = math.clamp(v, -0.35, cap)
			else
				out[key] = math.clamp(v, 0, cap)
			end
		end
	end
	out.slotsUsed = 0
	if type(wslots) == "table" then
		for _ in pairs(wslots) do
			out.slotsUsed += 1
		end
	end
	return out
end

function AugmentService.isPending(profile, uid)
	local pending = type(profile) == "table" and profile.pendingReroll or nil
	return type(pending) == "table" and pending.uid == uid
end

function AugmentService.isProtected(profile, uid)
	if type(profile) ~= "table" or type(uid) ~= "string" then
		return true
	end
	local item = AugmentService.findItem(profile, uid)
	if not item then
		return true
	end
	if item.favorite == true or AugmentService.isPending(profile, item.uid) then
		return true
	end
	local function loadoutReferences(loadout)
		if type(loadout) ~= "table" then
			return false
		end
		if loadout.abilityAugment == item.uid or loadout.abilityAugment == item.archetypeId then
			return true
		end
		for key, entry in pairs(loadout.weaponAugments or {}) do
			if type(entry) == "table" then
				for _, ref in pairs(entry) do
					if ref == item.uid or ref == item.archetypeId then
						return true
					end
				end
			elseif entry == item.uid or entry == item.archetypeId then
				return true
			end
		end
		return false
	end
	if loadoutReferences(profile.selectedLoadout) then
		return true
	end
	for _, loadout in pairs(profile.savedLoadouts or {}) do
		if loadoutReferences(loadout) then
			return true
		end
	end
	return false
end

function AugmentService.equipAugment(profile, weaponId, slot, augmentRef)
	if type(profile) ~= "table" then
		return false, "no profile"
	end
	local sockets = AugmentService.socketsFor(profile, weaponId)
	if sockets == 0 then
		return false, "weapon not owned"
	end
	if slot < 1 or slot > sockets then
		if slot == 2 and sockets == 1 then
			return false, string.format("requires mastery level 5 (%d XP)", SECOND_SOCKET_XP)
		end
		return false, "no such socket"
	end
	local item = AugmentService.findItem(profile, augmentRef)
	if not item then
		return false, "augment not owned"
	end
	if AugmentService.isPending(profile, item.uid) then
		return false, "resolve pending reroll first"
	end
	local def = Augments.get(item.archetypeId)
	if def then
		if def.applies == "Ability" then
			return false, "ability augment cannot fit a weapon socket"
		elseif def.applies == "Category" and type(def.category) == "string" then
			local weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
			local weapon = weapons.get(weaponId)
			if weapon and weapon.category ~= def.category then
				return false, string.format("fits %s weapons only", tostring(def.category))
			end
		end
	end
	local slots = AugmentService.migrateSockets(profile)
	if not slots then
		return false, "no loadout"
	end
	local existingPerWeapon = slots[weaponId]
	if type(existingPerWeapon) == "table" then
		for existingSlot, ref in pairs(existingPerWeapon) do
			if existingSlot ~= slot and ref == item.uid then
				return false, "copy already equipped in another active socket"
			end
		end
	end
	local perWeapon = slots[weaponId]
	if type(perWeapon) ~= "table" then
		perWeapon = {}
		slots[weaponId] = perWeapon
	end
	perWeapon[slot] = item.uid
	return true, nil
end

function AugmentService.sanitiseLoadout(profile)
	if type(profile) ~= "table" then
		return 0
	end
	local slots = AugmentService.migrateSockets(profile)
	if not slots then
		return 0
	end
	local loadout = profile.selectedLoadout or {}
	local weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
	local cleared = 0
	for weaponKey, entry in pairs(slots) do
		if type(entry) == "table" then
			local weaponDef = weapons.get(weaponKey)
			for slot, ref in pairs(entry) do
				local item = AugmentService.findItem(profile, ref)
				if item then
					if ref ~= item.uid then
						entry[slot] = item.uid
					end
					local def = Augments.get(item.archetypeId)
					local fits = true
					if def then
						if def.applies == "Ability" then
							fits = false
						elseif def.applies == "Category" and type(def.category) == "string" then
							fits = (weaponDef and weaponDef.category == def.category) or false
						end
					end
					if not fits then
						entry[slot] = nil
						cleared += 1
					end
				else
					entry[slot] = nil
					cleared += 1
				end
			end
		elseif type(entry) == "string" then
			-- legacy flat entry outside migration reach: drop it, migration rehomes numeric keys only
			slots[weaponKey] = nil
			cleared += 1
		end
	end
	local abilityRef = loadout.abilityAugment
	if type(abilityRef) == "string" then
		local item = AugmentService.findItem(profile, abilityRef)
		if item then
			if abilityRef ~= item.uid then
				loadout.abilityAugment = item.uid
			end
			local def = Augments.get(item.archetypeId)
			if def and def.applies == "Category" then
				loadout.abilityAugment = nil
				cleared += 1
			end
		else
			loadout.abilityAugment = nil
			cleared += 1
		end
	end
	if cleared > 0 then
		workspace:SetAttribute("GF_AugmentSanitisedCount", cleared)
	end
	return cleared
end

function AugmentService.unequipAugment(profile, slot, weaponId)
	local slots = AugmentService.migrateSockets(profile)
	if not slots then
		return false
	end
	if type(weaponId) == "string" and weaponId ~= "" then
		local perWeapon = slots[weaponId]
		if type(perWeapon) == "table" then
			perWeapon[slot] = nil
		end
		return true
	end
	-- backward compatibility: no weaponId clears the slot index across every weapon
	for key, perWeapon in pairs(slots) do
		if type(perWeapon) == "table" then
			perWeapon[slot] = nil
		end
	end
	return true
end

function AugmentService.setFavorite(profile, uid, favorite)
	local item = AugmentService.findItem(profile, uid)
	if not item then
		return false, "augment not owned"
	end
	item.favorite = favorite == true
	return true, item.favorite
end

local function scrap(profile)
	profile.salvage = profile.salvage or { scrap = 0, energyCells = 0, militaryTechnology = 0 }
	profile.salvage.scrap = tonumber(profile.salvage.scrap) or 0
	return profile.salvage.scrap
end

-- Deduct once and persist the generated offer. Accept and Keep both resolve the same persisted offer;
-- disconnecting cannot produce a free retry because the offer is already in the profile.
function AugmentService.reroll(profile, uid, lockIndex)
	if type(profile) ~= "table" then
		return false, "no profile"
	end
	-- S11-063: loadouts are frozen for the whole mission; rerolling an equipped item mid-mission would
	-- mutate the snapshot the soldier deployed with, so the server refuses rerolls until return.
	if workspace:GetAttribute("GF_InMission") == true then
		return false, "loadout frozen in mission"
	end
	if type(profile.pendingReroll) == "table" then
		return false, "another reroll offer is already pending"
	end
	local item = AugmentService.findItem(profile, uid)
	if not item then
		return false, "augment not owned"
	end
	local rarity = tostring(item.rarity or "Common")
	local cost = REROLL_COST[rarity] or 25
	local locked = nil
	if lockIndex ~= nil then
		if rarity ~= "Epic" and rarity ~= "Legendary" then
			return false, "only Epic and Legendary augments can lock a trait"
		end
		lockIndex = math.floor(tonumber(lockIndex) or 0)
		locked = item.traits and item.traits[lockIndex]
		if type(locked) ~= "table" then
			return false, "no such trait to lock"
		end
		cost = math.floor(cost * 1.5 + 0.5)
	end
	if scrap(profile) < cost then
		return false, string.format("needs %d scrap", cost)
	end
	profile.salvage.scrap -= cost
	local def = Augments.get(item.archetypeId)
	if not def then
		return false, "archetype missing"
	end
	local proposed = Augments.rollTraits(def, nil, locked)
	profile.pendingReroll = {
		uid = item.uid,
		archetypeId = item.archetypeId,
		cost = cost,
		lockedIndex = lockIndex,
		traits = copyTraits(proposed),
		createdAt = os.time(),
	}
	workspace:SetAttribute("GF_AugmentRerollPending", string.format("%s:%d", item.uid, cost))
	return true, profile.pendingReroll
end

function AugmentService.resolveReroll(profile, accept)
	if type(profile) ~= "table" or type(profile.pendingReroll) ~= "table" then
		return false, "no pending reroll"
	end
	local pending = profile.pendingReroll
	local item = AugmentService.findItem(profile, pending.uid)
	if not item then
		profile.pendingReroll = nil
		return false, "augment no longer exists"
	end
	if accept then
		item.traits = copyTraits(pending.traits)
	end
	profile.pendingReroll = nil
	workspace:SetAttribute("GF_AugmentRerollResolved", string.format("%s:%s", item.uid, accept and "accept" or "keep"))
	return true, accept and "accepted" or "kept"
end

function AugmentService.dismantleCandidates(profile, rarityFilter, categoryFilter)
	local inventory = AugmentService.ensureInventory(profile)
	local result = { count = 0, scrap = 0, skipped = 0, uids = {}, rarity = rarityFilter or "ALL", category = categoryFilter or "ANY" }
	for uid, item in pairs(inventory) do
		local rarityOk = rarityFilter == nil or rarityFilter == "ALL" or tostring(item.rarity) == rarityFilter
		local categoryOk = categoryFilter == nil or categoryFilter == "ANY" or tostring(item.category) == categoryFilter
		if rarityOk and categoryOk then
			if AugmentService.isProtected(profile, uid) then
				result.skipped += 1
			else
				result.count += 1
				result.scrap += DISMANTLE_SCRAP[tostring(item.rarity)] or 0
				table.insert(result.uids, uid)
			end
		end
	end
	table.sort(result.uids)
	return result
end

function AugmentService.dismantle(profile, uids)
	if type(profile) ~= "table" or type(uids) ~= "table" then
		return false, "bad dismantle request"
	end
	local inventory = AugmentService.ensureInventory(profile)
	local total, count, skipped = 0, 0, 0
	local remove = {}
	for _, uid in ipairs(uids) do
		local item = type(uid) == "string" and inventory[uid] or nil
		if item and not AugmentService.isProtected(profile, uid) then
			local value = DISMANTLE_SCRAP[tostring(item.rarity)] or 0
			total += value
			count += 1
			table.insert(remove, uid)
		else
			skipped += 1
		end
	end
	if count == 0 then
		return false, "nothing eligible to dismantle"
	end
	for _, uid in ipairs(remove) do
		inventory[uid] = nil
	end
	profile.salvage = profile.salvage or { scrap = 0, energyCells = 0, militaryTechnology = 0 }
	profile.salvage.scrap = (tonumber(profile.salvage.scrap) or 0) + total
	workspace:SetAttribute("GF_AugmentDismantled", string.format("%d:+%d", count, total))
	return true, { count = count, scrap = total, skipped = skipped }
end

local function validateFusion(profile, uids)
	if type(profile) ~= "table" or type(uids) ~= "table" or #uids ~= 3 then
		return false, "fusion requires exactly 3 copies"
	end
	local inventory = AugmentService.ensureInventory(profile)
	local seen, items = {}, {}
	for _, uid in ipairs(uids) do
		if type(uid) ~= "string" or seen[uid] then
			return false, "fusion inputs must be distinct"
		end
		seen[uid] = true
		local item = inventory[uid]
		if not item then
			return false, "fusion input missing"
		end
		if AugmentService.isProtected(profile, uid) then
			return false, "fusion input is protected or equipped"
		end
		table.insert(items, item)
	end
	local rarity, category = tostring(items[1].rarity), tostring(items[1].category)
	if not NEXT_RARITY[rarity] then
		return false, "Legendary augments cannot fuse"
	end
	for _, item in ipairs(items) do
		if tostring(item.rarity) ~= rarity or tostring(item.category) ~= category then
			return false, "fusion inputs must share rarity and category"
		end
	end
	local targetRarity = NEXT_RARITY[rarity]
	local pool = {}
	for _, def in ipairs(Augments.forCategory(category)) do
		if def.rarity == targetRarity then
			table.insert(pool, def)
		end
	end
	if #pool == 0 then
		return false, "no next-rarity archetype in that category"
	end
	return true, { inventory = inventory, items = items, rarity = rarity, category = category, targetRarity = targetRarity, pool = pool }
end

-- Read-only fusion preview: exactly what will be consumed and the possible direct result archetypes.
function AugmentService.fusionPreview(profile, uids)
	local ok, v = validateFusion(profile, uids)
	if not ok then
		return false, v
	end
	local outcomes = {}
	for _, def in ipairs(v.pool) do
		table.insert(outcomes, { id = def.id, name = def.displayName, rarity = def.rarity, category = def.category, chance = 1 / #v.pool })
	end
	local inputs = {}
	for _, item in ipairs(v.items) do
		table.insert(inputs, AugmentService.publicItem(profile, item))
	end
	return true, { inputs = inputs, uids = { uids[1], uids[2], uids[3] }, fromRarity = v.rarity, toRarity = v.targetRarity, category = v.category, outcomes = outcomes }
end

function AugmentService.fuse(profile, uids)
	local ok, v = validateFusion(profile, uids)
	if not ok then
		return false, v
	end
	local inventory, items, pool = v.inventory, v.items, v.pool
	local resultDef = pool[math.floor(math.random() * #pool) + 1]
	for _, uid in ipairs(uids) do
		inventory[uid] = nil
	end
	local uid, item = AugmentService.grantAugment(profile, resultDef.id, { source = "fusion:" .. table.concat(uids, "+") })
	if not uid then
		-- This should be impossible after consuming three items because capacity only increases free space,
		-- but restore inputs rather than losing them if a future capacity rule changes.
		for _, input in ipairs(items) do
			inventory[input.uid] = input
		end
		return false, "fusion result could not be created"
	end
	workspace:SetAttribute("GF_AugmentFused", string.format("%s:%s:%s", table.concat(uids, "+"), uid, resultDef.id))
	return true, item
end

function AugmentService.forPlayer(player)
	-- AUGMENT-V2 D-1 fix: the abandoned prototype that lived here rebound AugmentService.dismantle
	-- to an unprotected naive implementation on every call. The protective profile-safe dismantle
	-- defined earlier in this module is now the only one. Dead weight-table/category-prototype
	-- code removed; zero external references existed (audit-verified 2026-11-27).
	return AugmentService.forProfile(ProfileService.get(player))
end

-- player-facing per-weapon resolution: the canonical combat consumption entry post-migration.
function AugmentService.forPlayerWeapon(player, weaponId)
	return AugmentService.forProfileWeapon(ProfileService.get(player), weaponId)
end

function AugmentService.magazine(weapon, augs)
	if not weapon or not augs then
		return weapon and weapon.magazine or 0
	end
	return math.max(1, math.floor(weapon.magazine * (1 + augs.magazine) + 0.5))
end

function AugmentService.reloadTime(weapon, augs)
	if not weapon then
		return 0
	end
	local base = weapon.reloadTime or 2.2
	if not augs then
		return base
	end
	return math.max(0.4, base / math.max(0.2, 1 + augs.reloadSpeed))
end

AugmentService.REROLL_COST = REROLL_COST
AugmentService.DISMANTLE_SCRAP = DISMANTLE_SCRAP

return AugmentService
