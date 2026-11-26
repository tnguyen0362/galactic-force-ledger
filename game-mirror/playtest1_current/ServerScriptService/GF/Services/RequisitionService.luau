--!strict
-- Military requisitions (GOAL §12). Permanent catalog: the free Frontline Arsenal and the
-- premium Siege Division (1000 War Credits). Unlock grants access, not items; entries are bought
-- with standard Credits. Tiers open by Credits spent inside that requisition (tier2 600, tier3 1600).
-- Ownership is shared with the Armory: buying from either path writes the same owned* table, so
-- nothing is ever charged twice.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Requisitions = require(ReplicatedStorage.GF.Shared.Configs.Requisitions)
local Weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
local ArmorConfig = require(ReplicatedStorage.GF.Shared.Configs.Armor)
local AbilitiesConfig = require(ReplicatedStorage.GF.Shared.Configs.Abilities)
local EconomyConfig = require(ReplicatedStorage.GF.Shared.Configs.Economy)
local CachesConfig = require(ReplicatedStorage.GF.Shared.Configs.Caches)
local ProfileService = require(script.Parent.ProfileService)

local RequisitionService = {}

local function profileOf(player: Player)
	local byUser = ProfileService.getByUserId(player.UserId)
	if type(byUser) == "table" then
		return byUser
	end
	local ok, byPlayer = pcall(function()
		return ProfileService.get(player)
	end)
	if ok and type(byPlayer) == "table" then
		return byPlayer
	end
	return nil
end

local function itemDef(entry: any): any?
	if entry.kind == "weapon" then
		return Weapons.ById[entry.id]
	elseif entry.kind == "armor" then
		return ArmorConfig.get(entry.id)
	elseif entry.kind == "ability" then
		return AbilitiesConfig.get(entry.id)
	elseif entry.kind == "grenade" then
		for _, g in ipairs(EconomyConfig.Grenades or {}) do
			if g.id == entry.id then
				return g
			end
		end
	end
	return nil
end

function RequisitionService.tierForSpend(spend: number): number
	if spend >= Requisitions.TIER_THRESHOLDS[3] then
		return 3
	end
	if spend >= Requisitions.TIER_THRESHOLDS[2] then
		return 2
	end
	return 1
end

function RequisitionService.isUnlocked(profile: any, reqId: string): boolean
	local req = Requisitions.get(reqId)
	if not req then
		return false
	end
	if (req.unlockWarCredits or 0) <= 0 then
		return true
	end
	profile.unlockedRequisitions = profile.unlockedRequisitions or {}
	return profile.unlockedRequisitions[reqId] == true
end

-- Item ownership reads the same tables the Armory writes.
function RequisitionService.owns(profile: any, entry: any): boolean
	if entry.kind == "weapon" then
		return (profile.ownedWeapons or {})[entry.id] == true
	elseif entry.kind == "armor" then
		return (profile.ownedArmor or {})[entry.id] == true
	elseif entry.kind == "ability" then
		return (profile.ownedAbilities or {})[entry.id] == true
	elseif entry.kind == "grenade" then
		return (profile.ownedGrenades or {})[entry.id] == true
	end
	return false
end

function RequisitionService.entryCost(entry: any): number
	if entry.cost ~= nil then
		return entry.cost
	end
	local def = itemDef(entry)
	return (def and tonumber(def.cost)) or 0
end

function RequisitionService.entryRank(entry: any): number
	local def = itemDef(entry)
	return (def and tonumber(def.unlockRank or def.rank)) or 1
end

function RequisitionService.entryName(entry: any): string
	if entry.displayName then
		return entry.displayName
	end
	local def = itemDef(entry)
	return (def and def.displayName) or tostring(entry.id or entry.key)
end

-- Whether Siege Division is required for a plain-Armory purchase of this item.
function RequisitionService.premiumGate(kind: string, id: string): boolean
	local tableFor = Requisitions.PremiumItems[kind]
	return tableFor ~= nil and tableFor[id] == true
end

function RequisitionService.premiumLocked(profile: any, kind: string, id: string): boolean
	-- S10-032/033 resource economy: scrap funds rerolls, energy cells and military technology
-- fund experimental unlocks. Blueprint-gated experimental abilities cost 12 cells + 3 tech —
-- the blueprint alone is never enough, the resources alone are never enough.
function RequisitionService.unlockExperimental(plr: Player, blueprintId: string): boolean
	if not plr:GetAttribute("GF_Blueprint_" .. blueprintId) then
		return false
	end
	local cells = plr:GetAttribute("GF_EnergyCells") or 0
	local tech = plr:GetAttribute("GF_MilitaryTech") or 0
	if cells < 12 or tech < 3 then
		return false
	end
	plr:SetAttribute("GF_EnergyCells", cells - 12)
	plr:SetAttribute("GF_MilitaryTech", tech - 3)
	plr:SetAttribute("GF_Unlocked_" .. blueprintId, true)
	return true
end

function RequisitionService.fundReroll(plr: Player, cost: number): boolean
	local scrap = plr:GetAttribute("GF_Scrap") or 0
	if scrap < cost then
		return false
	end
	plr:SetAttribute("GF_Scrap", scrap - cost)
	return true
end

-- S12-019 monetization discipline: permanent extra loadout slots, cosmetic armor and inventory
-- expansion are the ONLY premium offerings — no power, no stats, no gameplay advantage is ever
-- sold. Convenience and identity, never strength.
RequisitionService.MONETIZATION_RULES = {
	allowed = { "loadout_slots", "cosmetic_armor", "inventory_expansion" },
	forbidden = { "damage", "health", "stats", "power", "weapons", "abilities" },
}

function RequisitionService.validateOffering(itemId: string, category: string): boolean
	for _, forbidden in ipairs(RequisitionService.MONETIZATION_RULES.forbidden) do
		if category == forbidden then
			return false -- power is never for sale
		end
	end
	for _, allowed in ipairs(RequisitionService.MONETIZATION_RULES.allowed) do
		if category == allowed then
			return true
		end
	end
	return false -- unknown categories default to rejection
end

return RequisitionService.premiumGate(kind, id) and not RequisitionService.isUnlocked(profile, "SiegeDivision")
end

-- Premium catalog rows keep their tier requirement even when bought through the plain Armory surface.
-- Standard rows deliberately do not use this helper: GOAL §12 lets standard rank clearance open standard
-- gear regardless of requisition spend, with tier spend acting as alternate catalog navigation.
function RequisitionService.premiumTierLocked(profile: any, kind: string, id: string): (boolean, number)
	if not RequisitionService.premiumGate(kind, id) then
		return false, 1
	end
	local hit = Requisitions.entryForItem(kind, id)
	if type(profile) ~= "table" or not hit then
		return false, 1
	end
	local spendByReq = type(profile.requisitionSpend) == "table" and profile.requisitionSpend or {}
	local spend = math.max(0, tonumber(spendByReq[hit.requisition.id]) or 0)
	local tier = tonumber(hit.tier) or 1
	return tier > RequisitionService.tierForSpend(spend), tier
end

function RequisitionService.stateFor(player: Player): any
	local profile = profileOf(player)
	if not profile then
		return nil
	end
	profile.requisitionSpend = type(profile.requisitionSpend) == "table" and profile.requisitionSpend or {}
	profile.purchasedEntries = type(profile.purchasedEntries) == "table" and profile.purchasedEntries or {}
	local out = {}
	for _, req in ipairs(Requisitions.List) do
		local spend = math.max(0, tonumber(profile.requisitionSpend[req.id]) or 0)
		local tier = RequisitionService.tierForSpend(spend)
		local unlocked = RequisitionService.isUnlocked(profile, req.id)
		local rows = {}
		for tierIndex, entries in pairs(req.tiers) do
			for _, entry in ipairs(entries) do
				local owned = RequisitionService.owns(profile, entry)
				local onceKey = req.id .. ":" .. entry.key
				local onceUsed = entry.once == true and profile.purchasedEntries[onceKey] == true
				local rank = RequisitionService.entryRank(entry)
				table.insert(rows, {
					key = entry.key,
					kind = entry.kind,
					id = entry.id,
					tier = tierIndex,
					name = RequisitionService.entryName(entry),
					cost = RequisitionService.entryCost(entry),
					rank = rank,
					owned = owned,
					once = entry.once == true,
					onceUsed = onceUsed,
					tierLocked = tierIndex > tier,
					rankLocked = (tonumber(profile.rank) or 1) < rank,
				})
			end
		end
		table.sort(rows, function(a, b)
			if a.tier ~= b.tier then
				return a.tier < b.tier
			end
			return a.key < b.key
		end)
		table.insert(out, {
			id = req.id,
			displayName = req.displayName,
			premium = req.premium == true,
			unlockWarCredits = req.unlockWarCredits or 0,
			unlocked = unlocked,
			spend = spend,
			tier = tier,
			nextTierAt = tier < 3 and (Requisitions.TIER_THRESHOLDS[tier + 1] or 0) or 0,
			entries = rows,
		})
	end
	return {
		requisitions = out,
		warCredits = tonumber(profile.warCredits) or 0,
	}
end

-- Profile-local transaction core. Keeping this independent of Player instances makes the rule testable
-- with synthetic profiles instead of consuming real inventory items.
function RequisitionService.unlockProfile(profile: any, reqId: string): (boolean, string?)
	local req = Requisitions.get(reqId)
	if type(profile) ~= "table" or not req then
		return false, "unknown requisition"
	end
	if RequisitionService.isUnlocked(profile, reqId) then
		return false, "already unlocked"
	end
	local cost = req.unlockWarCredits or 0
	if (tonumber(profile.warCredits) or 0) < cost then
		return false, string.format("needs %d war credits", cost)
	end
	profile.warCredits = (tonumber(profile.warCredits) or 0) - cost
	profile.unlockedRequisitions = type(profile.unlockedRequisitions) == "table" and profile.unlockedRequisitions or {}
	profile.unlockedRequisitions[reqId] = true
	return true
end

function RequisitionService.unlock(player: Player, reqId: string): (boolean, string?)
	local profile = profileOf(player)
	local ok, reason = RequisitionService.unlockProfile(profile, reqId)
	if ok then
		ProfileService.markDirty(player)
		workspace:SetAttribute("GF_RequisitionUnlocked", reqId .. ":" .. player.Name)
	end
	return ok, reason
end

local function findEntry(req: any, key: string): (any?, number)
	for tierIndex, entries in pairs(req.tiers) do
		for _, entry in ipairs(entries) do
			if entry.key == key then
				return entry, tierIndex
			end
		end
	end
	return nil, 0
end

-- Buy one catalog row against a profile. `grantCache` is injected by the Player-facing wrapper so the
-- same transaction can be proved against a synthetic profile without touching the real inventory.
-- Uniform economic journaling (spec §96-98): effects here already have specialized idempotency;
-- this records them into the authoritative transaction journal for evidence and versioning.
local function journalTxn(profile, txn)
	local plr = profile and game:GetService("Players"):GetPlayerByUserId(tonumber(profile.userId) or -1)
	if not plr then
		return
	end
	local ok, svc = pcall(function()
		return require(script.Parent.EconomyTransactionService)
	end)
	if ok and svc then
		pcall(function()
			svc.record(plr, txn)
		end)
	end
end

function RequisitionService.buyProfile(profile: any, reqId: string, key: string, grantCache): (boolean, string?)
	local req = Requisitions.get(reqId)
	if type(profile) ~= "table" or not req then
		return false, "unknown requisition"
	end
	if not RequisitionService.isUnlocked(profile, reqId) then
		return false, "requisition locked"
	end
	local entry, entryTier = findEntry(req, key)
	if not entry then
		return false, "unknown entry"
	end
	profile.requisitionSpend = type(profile.requisitionSpend) == "table" and profile.requisitionSpend or {}
	profile.purchasedEntries = type(profile.purchasedEntries) == "table" and profile.purchasedEntries or {}
	local spend = math.max(0, tonumber(profile.requisitionSpend[reqId]) or 0)
	if entryTier > RequisitionService.tierForSpend(spend) then
		return false, string.format("tier %d locked: spend %d more credits in %s", entryTier, (Requisitions.TIER_THRESHOLDS[entryTier] or 0) - spend, req.displayName)
	end
	local onceKey = reqId .. ":" .. entry.key
	if entry.once == true and profile.purchasedEntries[onceKey] == true then
		return false, "already claimed"
	end
	if RequisitionService.owns(profile, entry) then
		return false, "already owned"
	end
	local rankNeeded = RequisitionService.entryRank(entry)
	if (tonumber(profile.rank) or 1) < rankNeeded then
		return false, string.format("requires rank %d", rankNeeded)
	end
	if entry.kind == "cache" and not CachesConfig.get(entry.tier) then
		return false, "unknown cache tier"
	end
	local cost = math.max(0, RequisitionService.entryCost(entry))
	local oldCredits = math.max(0, tonumber(profile.credits) or 0)
	if oldCredits < cost then
		return false, string.format("needs %d credits", cost)
	end

	local oldOnce = profile.purchasedEntries[onceKey]
	profile.credits = oldCredits - cost
	profile.requisitionSpend[reqId] = spend + cost
	if entry.once then
		profile.purchasedEntries[onceKey] = true
	end

	local granted = true
	local failure = nil
	if entry.kind == "resource" then
		profile.salvage = type(profile.salvage) == "table" and profile.salvage or { scrap = 0, energyCells = 0, militaryTechnology = 0 }
		for resource, amount in pairs(entry.grant or {}) do
			profile.salvage[resource] = (tonumber(profile.salvage[resource]) or 0) + (tonumber(amount) or 0)
		end
	elseif entry.kind == "cache" then
		if type(grantCache) ~= "function" then
			granted = false
			failure = "cache grant unavailable"
		else
			granted = grantCache(entry.tier) == true
			if not granted then
				failure = "cache grant failed"
			end
		end
	elseif entry.kind == "weapon" then
		profile.ownedWeapons = type(profile.ownedWeapons) == "table" and profile.ownedWeapons or {}
		profile.ownedWeapons[entry.id] = true
	elseif entry.kind == "armor" then
		profile.ownedArmor = type(profile.ownedArmor) == "table" and profile.ownedArmor or { STANDARD = true }
		profile.ownedArmor[entry.id] = true
	elseif entry.kind == "ability" then
		profile.ownedAbilities = type(profile.ownedAbilities) == "table" and profile.ownedAbilities or {}
		profile.ownedAbilities[entry.id] = true
	elseif entry.kind == "grenade" then
		profile.ownedGrenades = type(profile.ownedGrenades) == "table" and profile.ownedGrenades or { Frag = true }
		profile.ownedGrenades[entry.id] = true
	end

	if not granted then
		profile.credits = oldCredits
		profile.requisitionSpend[reqId] = spend
		profile.purchasedEntries[onceKey] = oldOnce
		return false, failure
	end
	-- journal key: once-entries dedupe inherently; repeatable entries use the monotonic
	-- post-purchase spend total so every purchase instance journals distinctly and exactly once.
	local outputs = {}
	if entry.kind == "resource" then
		for resource, amount in pairs(entry.grant or {}) do
			outputs[resource] = (outputs[resource] or 0) + (tonumber(amount) or 0)
		end
	elseif entry.kind == "cache" then
		outputs["cache:" .. tostring(entry.tier)] = 1
	elseif entry.kind then
		outputs[tostring(entry.kind) .. ":" .. tostring(entry.id)] = 1
	end
	journalTxn(profile, {
		id = string.format("req:%s:%s:%d", reqId, entry.key, profile.requisitionSpend[reqId] or 0),
		type = "requisition_purchase",
		sourceId = reqId,
		inputs = { credits = cost },
		outputs = outputs,
		note = string.format("entry=%s tier=%d once=%s", entry.key, entryTier, tostring(entry.once == true)),
	})
	return true
end

function RequisitionService.buy(player: Player, reqId: string, key: string): (boolean, string?)
	local profile = profileOf(player)
	local ok, reason = RequisitionService.buyProfile(profile, reqId, key, function(tier: string)
		return require(script.Parent.CacheService).grantToInventory(player, tier, "requisition:" .. reqId)
	end)
	if ok then
		ProfileService.markDirty(player)
		workspace:SetAttribute("GF_RequisitionPurchase", string.format("%s:%s:%s", player.Name, reqId, key))
	end
	return ok, reason
end

-- Armory purchases are alternate navigation into the same catalog. After a successful Armory purchase,
-- credit the matching requisition with the Credits actually spent so either path advances the same ledger.
function RequisitionService.recordSharedPurchase(profile: any, kind: string, id: string, cost: number): (string?, string?)
	local hit = Requisitions.entryForItem(kind, id)
	if type(profile) ~= "table" or not hit then
		return nil, nil
	end
	profile.requisitionSpend = type(profile.requisitionSpend) == "table" and profile.requisitionSpend or {}
	profile.purchasedEntries = type(profile.purchasedEntries) == "table" and profile.purchasedEntries or {}
	local reqId = hit.requisition.id
	profile.requisitionSpend[reqId] = math.max(0, tonumber(profile.requisitionSpend[reqId]) or 0) + math.max(0, tonumber(cost) or 0)
	if hit.entry.once then
		profile.purchasedEntries[reqId .. ":" .. hit.entry.key] = true
	end
	return reqId, hit.entry.key
end

return RequisitionService
