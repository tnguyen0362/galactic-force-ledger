--!strict
-- Armory: the only writer of ownedWeapons / selectedLoadout / selectedClass.
-- Before this service, RequestLoadout/SetLoadout were remotes with zero server listeners, so
-- every armory row (LC-005/006/009/015) was unprovable regardless of UI quality.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GF = ReplicatedStorage:FindFirstChild("GF") :: Folder
local Weapons = require(GF.Shared.Configs.Weapons)
local Classes = require(GF.Shared.Configs.Classes)
local ProfileService = require(ServerScriptService.GF.Services.ProfileService)
local RequisitionService = require(ServerScriptService.GF.Services.RequisitionService)
local EconomyTransactionService = require(ServerScriptService.GF.Services.EconomyTransactionService)

local ArmoryService = {}
local PRIMARY = { Rifle = true, Shotgun = true, Marksman = true, LMG = true, Energy = true }
local function remotes(): Folder return ReplicatedStorage.GF.Remotes end

local function profileOf(player: Player): any
	local byUser = ProfileService.getByUserId(player.UserId)
	if type(byUser) == "table" then return byUser end
	local ok, byPlayer = pcall(function() return ProfileService.get(player) end)
	if ok and type(byPlayer) == "table" then return byPlayer end
	return nil
end

function ArmoryService.state(player: Player)
	local profile = profileOf(player)
	if not profile then return nil end
	local rows = {}
	for _, row in ipairs(Weapons.List) do
		local reqTierLocked, reqTier = RequisitionService.premiumTierLocked(profile, "weapon", row.id)
		rows[#rows + 1] = {
			id = row.id, name = row.displayName, category = row.category, cost = row.cost,
			rank = row.unlockRank, damage = row.damage, magazine = row.magazine, mode = row.fireMode,
			owned = profile.ownedWeapons[row.id] == true,
			equipped = profile.selectedLoadout.primary == row.id or profile.selectedLoadout.secondary == row.id,
			premiumLocked = RequisitionService.premiumLocked(profile, "weapon", row.id),
			requisitionTierLocked = reqTierLocked,
			requisitionTier = reqTier,
		}
	end
	local classList = {}
	for _, c in ipairs(Classes.List) do
		classList[#classList + 1] = { id = c.id, name = c.displayName, selected = profile.selectedClass == c.id }
	end
	-- Augment state: sockets allowed per weapon come from the mastery rule, and the slotted ids come from
	-- the loadout. Without this the UI had nothing to draw, which is why augments had no surface at all.
	local AugmentService = require(script.Parent.AugmentService)
	local masteries = {}
	local masteryLevels = {}
	local sockets = {}
	for _, row in ipairs(Weapons.List) do
		local mastery = 0
		if type(profile.weaponMastery) == "table" then
			mastery = tonumber(profile.weaponMastery[row.id]) or 0
		end
		masteries[row.id] = mastery
		-- Level, not raw XP, is what the armory row shows: the spec's progress reading is per level.
		masteryLevels[row.id] = require(script.Parent.ProfileService).masteryLevel(player, row.id)
		sockets[row.id] = AugmentService.socketsFor(profile, row.id)
	end
	local ownedAugments = {}
	local catalogRows = {}
	local catalog = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Augments)
	for _, def in ipairs(catalog.List or {}) do
		local owned = profile.ownedAugments and profile.ownedAugments[def.id] == true
		local row = {
			id = def.id,
			name = def.displayName or def.id,
			role = def.slot,
			description = def.applies or "",
			cost = tonumber(def.cost) or 0,
			owned = owned == true,
		}
		if owned then
			ownedAugments[#ownedAugments + 1] = row
		end
		catalogRows[#catalogRows + 1] = row
	end
	workspace:SetAttribute("GF_Ability1", profile.selectedLoadout.ability1)
	workspace:SetAttribute("GF_Ability2", profile.selectedLoadout.ability2)
	-- per-player truth: workspace globals are shared across every client in the session, so one
	-- player's armory visit used to overwrite the ability bindings everyone else read.
	player:SetAttribute("GF_Ability1", profile.selectedLoadout.ability1)
	player:SetAttribute("GF_Ability2", profile.selectedLoadout.ability2)
	local requisitionState = RequisitionService.stateFor(player)
	return {
		weapons = rows,
		classes = classList,
		abilities = (function()
			local AbilitiesConfig = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Abilities)
			local rows = {}
			for _, def in ipairs(AbilitiesConfig.List or {}) do
				table.insert(rows, { id = def.id, name = def.displayName or def.id, rank = tonumber(def.unlockRank or def.rank) or 1, cost = tonumber(def.cost) or 0, owned = profile.ownedAbilities and profile.ownedAbilities[def.id] == true })
			end
			return rows
		end)(),
		ownedGrenades = (function()
			local rows = {}
			for id, owned in pairs(profile.ownedGrenades or {}) do
				if owned then
					table.insert(rows, id)
				end
			end
			table.sort(rows)
			return rows
		end)(),
		grenades = (function()
			local EconomyConfig = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Economy)
			local rows = {}
			for _, entry in pairs(EconomyConfig.Grenades or {}) do
				local entryId = type(entry) == "table" and (entry.id or entry.name) or entry
				table.insert(rows, entryId)
			end
			table.sort(rows)
			return rows
		end)(),
		caches = (function()
			local CachesConfig = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Caches)
			local held = profile.caches or {}
			local rows = {}
			for _, tier in ipairs(CachesConfig.Tiers) do
				table.insert(rows, { id = tier.id, name = tier.displayName, held = held[tier.id] or 0 })
			end
			return rows
		end)(),
		armor = (function()
			local ArmorConfig = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Armor)
			local rows = {}
			for _, suit in ipairs(ArmorConfig.List) do
				local reqTierLocked, reqTier = RequisitionService.premiumTierLocked(profile, "armor", suit.id)
				table.insert(rows, {
					id = suit.id, name = suit.displayName, tier = suit.tier, cost = suit.cost,
					rank = suit.unlockRank,
					owned = profile.ownedArmor and profile.ownedArmor[suit.id] == true,
					equipped = profile.selectedLoadout.armor == suit.id,
					premiumLocked = RequisitionService.premiumLocked(profile, "armor", suit.id),
					requisitionTierLocked = reqTierLocked,
					requisitionTier = reqTier,
				})
			end
			return rows
		end)(),		loadout = profile.selectedLoadout,
		selectedClass = profile.selectedClass,
		credits = profile.credits,
		warCredits = requisitionState and requisitionState.warCredits or (tonumber(profile.warCredits) or 0),
		requisitions = requisitionState and requisitionState.requisitions or {},
		xp = profile.xp or 0,
		xpForNext = (require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Economy).RankXp or {})[profile.rank + 1],
		rank = profile.rank,
		mastery = masteries,
		-- Held cache counts by tier, while `caches` remains the display row array.
		cacheCounts = profile.caches or {},
		-- True odds for the tier held in the greatest quantity, so the UI can disclose them (S11-027).
		cacheOdds = (function()
			local CacheSvc = require(script.Parent.CacheService)
			local list = {}
			for tierId, count in pairs(profile.caches or {}) do
				if type(count) == "number" and count > 0 then
					local odds = CacheSvc.oddsFor(tierId)
					if odds then
						odds.held = count
						table.insert(list, odds)
					end
				end
			end
			-- Most-held first, so the panel leads with the tier the player is actually opening.
			table.sort(list, function(a, b) return (a.held or 0) > (b.held or 0) end)
			return (#list > 0) and list or nil
		end)(),
		masteryLevel = masteryLevels,
		sockets = sockets,
		augments = ownedAugments,
		augmentItems = AugmentService.inventoryRows(profile),
		augmentCapacity = tonumber(profile.augmentCapacity) or AugmentService.BASELINE_CAPACITY,
		augmentCount = AugmentService.inventoryCount(profile),
		pendingReroll = profile.pendingReroll,
		scrap = (profile.salvage and tonumber(profile.salvage.scrap)) or 0,
		energyCells = (profile.salvage and tonumber(profile.salvage.energyCells)) or 0,
		freeTargetedOpenAvailable = profile.freeTargetedOpenUsed ~= true,
		militaryTechnology = (profile.salvage and tonumber(profile.salvage.militaryTechnology)) or 0,
		augmentCatalog = catalogRows,
		-- AUGMENT-V2 transitional shape: sockets are stored per-weapon (weaponAugments[weaponId][slot])
		-- post-migration, but the current client UI reads a flat slot index for the selected weapon.
		-- `slotted` stays flat for the primary weapon so the existing UI keeps working unchanged;
		-- `slottedByWeapon` carries the full nested truth for the Stage-9 UI rebuild.
		slotted = (function()
			local wa = profile.selectedLoadout.weaponAugments
			if type(wa) ~= "table" then
				return {}
			end
			local primary = tostring(profile.selectedLoadout.primary or "AR01")
			local perWeapon = wa[primary]
			if type(perWeapon) == "table" then
				return perWeapon
			end
			-- pre-migration legacy shape: numeric keys at top level
			local legacy = {}
			for key, value in pairs(wa) do
				if type(key) == "number" then
					legacy[key] = value
				end
			end
			return legacy
		end)(),
		slottedByWeapon = profile.selectedLoadout.weaponAugments or {},
	}
end

local function push(player: Player, payload: any) remotes().RequestLoadout:FireClient(player, payload) end
local MISSION_LOCKED_ACTIONS = {
	equip = true, equipAbility = true, equipGrenade = true, equipArmor = true, loadLoadout = true,
	class = true, augment = true, augmentRerollAccept = true,
}

local function fail(player: Player, reason: string)
	-- Every armory refusal is now visible to tests; augmentBuy used to fail silently because only the
	-- augment action recorded a reason.
	workspace:SetAttribute("GF_ArmoryRejected", reason)
	push(player, { ok = false, reason = reason })
end

function ArmoryService.buy(player: Player, id: string)
	if workspace:GetAttribute("GF_InMission") == true then
		return fail(player, "armory unavailable in mission")
	end
	local profile = profileOf(player)
	if not profile then return fail(player, "no profile") end
	local row = Weapons.ById[id]
	if not row then return fail(player, "unknown weapon") end
	if profile.ownedWeapons[id] then return fail(player, "already owned") end
	if RequisitionService.premiumLocked(profile, "weapon", id) then return fail(player, "requires Siege Division requisition") end
	local reqTierLocked, reqTier = RequisitionService.premiumTierLocked(profile, "weapon", id)
	if reqTierLocked then return fail(player, string.format("requires Siege Division tier %d", reqTier)) end
	if profile.rank < row.unlockRank then return fail(player, string.format("requires rank %d", row.unlockRank)) end
	if profile.credits < row.cost then return fail(player, string.format("needs %d credits", row.cost)) end
	local applied, txnResult, txnErr = EconomyTransactionService.apply(player, {
		id = "purchase:weapon:" .. id,
		type = "purchase",
		sourceId = "armory",
		inputs = { credits = row.cost },
		outputs = { ["weapon:" .. id] = 1 },
	}, function(p)
		-- re-validate inside the mutation: the debit and the ownership grant are one transaction
		if (p.credits or 0) < row.cost then
			return false, "insufficient credits at apply time"
		end
		if p.ownedWeapons[id] then
			return false, "already owned at apply time"
		end
		p.credits -= row.cost
		p.ownedWeapons[id] = true
		RequisitionService.recordSharedPurchase(p, "weapon", id, row.cost)
		return true
	end)
	if not applied then
		return fail(player, "transaction " .. txnResult .. ": " .. tostring(txnErr))
	end
	push(player, { ok = true, action = "buy", id = id, state = ArmoryService.state(player) })
end

function ArmoryService.unlockRequisition(player: Player, reqId: any)
	local wanted = tostring(reqId or "")
	local ok, reason = RequisitionService.unlock(player, wanted)
	if not ok then
		return fail(player, tostring(reason))
	end
	ProfileService.save(player)
	push(player, { ok = true, action = "reqUnlock", id = wanted, state = ArmoryService.state(player) })
end

function ArmoryService.buyRequisition(player: Player, reqId: any, key: any)
	local wantedReq = tostring(reqId or "")
	local wantedKey = tostring(key or "")
	local ok, reason = RequisitionService.buy(player, wantedReq, wantedKey)
	if not ok then
		return fail(player, tostring(reason))
	end
	ProfileService.save(player)
	push(player, { ok = true, action = "reqBuy", id = wantedKey, reqId = wantedReq, state = ArmoryService.state(player) })
end

-- applyLoadout() calls this through a pcall. It did not exist, so equipping changed the menu and the
-- profile but never the live session weapon, and the pcall hid the failure.
function ArmoryService.selection(player: Player)
	local profile = profileOf(player)
	if not profile then
		return nil
	end
	return profile.selectedLoadout
end

-- Saved loadouts. The profile carried a `savedLoadouts` field that nothing ever wrote, so the spec's
-- three slots did not exist. A slot is a copy of the live loadout; loading restores it and re-applies
-- the weapon so the change is visible in hand, not just in the menu.
local function copyLoadout(source: any)
	local out = {}
	for key, value in pairs(source or {}) do
		if type(value) == "table" then
			local inner = {}
			for innerKey, innerValue in pairs(value) do
				inner[innerKey] = innerValue
			end
			out[key] = inner
		else
			out[key] = value
		end
	end
	return out
end

function ArmoryService.saveLoadout(player: Player, slot: any)
	local profile = profileOf(player)
	if not profile then
		return fail(player, "no profile")
	end
	local index = tonumber(slot) or 0
	if index < 1 or index > 3 then
		return fail(player, "loadout slot must be 1-3")
	end
	profile.savedLoadouts = profile.savedLoadouts or {}
	profile.savedLoadouts[tostring(index)] = copyLoadout(profile.selectedLoadout)
	ProfileService.markDirty(player)
	ProfileService.save(player)
	workspace:SetAttribute("GF_LoadoutSaved", index)
	push(player, { ok = true, action = "saveLoadout", slot = index, state = ArmoryService.state(player) })
end

-- Armour. Six kits exist as config; buying and wearing them is what makes them real, and re-dressing
-- strips the previous kit so plates cannot stack.
local ArmorConfig = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Armor)

-- Abilities and grenades. Both existed in config and in the profile, but the armory had no way to
-- change either, so a player was stuck with the two starting abilities for the whole game.
local AbilitiesConfig = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Abilities)
local EconomyConfig = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Economy)

-- Unlocking. Four of six abilities had no acquisition path at all: their config carried rank and cost
-- and nothing ever charged for them.
function ArmoryService.buyAbility(player: Player, id: string)
	local profile = profileOf(player)
	if not profile then
		return fail(player, "no profile")
	end
	local def = nil
	for _, entry in ipairs(AbilitiesConfig.List or {}) do
		if entry.id == tostring(id or "") then
			def = entry
		end
	end
	if not def then
		return fail(player, "unknown ability")
	end
	profile.ownedAbilities = profile.ownedAbilities or {}
	if profile.ownedAbilities[def.id] then
		return fail(player, "already owned")
	end
	local rankNeeded = tonumber(def.unlockRank or def.rank) or 1
	if (profile.rank or 1) < rankNeeded then
		return fail(player, string.format("requires rank %d", rankNeeded))
	end
	local price = tonumber(def.cost) or 0
	if (profile.credits or 0) < price then
		return fail(player, string.format("needs %d credits", price))
	end
	profile.credits -= price
	profile.ownedAbilities[def.id] = true
	RequisitionService.recordSharedPurchase(profile, "ability", def.id, price)
	ProfileService.markDirty(player)
	ProfileService.save(player)
	workspace:SetAttribute("GF_AbilityBought", def.id .. ":" .. tostring(price))
	push(player, { ok = true, action = "buyAbility", id = def.id, state = ArmoryService.state(player) })
end

function ArmoryService.equipAbility(player: Player, slot: any, id: string)
	if workspace:GetAttribute("GF_InMission") == true then
		return fail(player, "loadout locked in mission")
	end
	local profile = profileOf(player)
	if not profile then
		return fail(player, "no profile")
	end
	local index = tonumber(slot) or 0
	if index ~= 1 and index ~= 2 then
		return fail(player, "ability slot must be 1 or 2")
	end
	local def = AbilitiesConfig.ById and AbilitiesConfig.ById[tostring(id or "")]
	if not def then
		for _, entry in ipairs(AbilitiesConfig.List or {}) do
			if entry.id == id then
				def = entry
			end
		end
	end
	if not def then
		return fail(player, "unknown ability")
	end
	if not (profile.ownedAbilities and profile.ownedAbilities[def.id]) then
		return fail(player, "ability not owned")
	end
	local key = index == 1 and "ability1" or "ability2"
	local otherKey = index == 1 and "ability2" or "ability1"
	if profile.selectedLoadout[otherKey] == def.id then
		return fail(player, "ability already in the other slot")
	end
	profile.selectedLoadout[key] = def.id
	workspace:SetAttribute("GF_AbilityEquipped", string.format("%d:%s", index, def.id))
	-- The client reads these to decide which ability a slot fires; the ids were hardcoded before.
	workspace:SetAttribute("GF_Ability" .. index, def.id)
	player:SetAttribute("GF_Ability" .. index, def.id)
	ProfileService.markDirty(player)
	pcall(function()
		require(script.Parent.AbilityService).apply(player)
	end)
	push(player, { ok = true, action = "equipAbility", id = def.id, slot = index, state = ArmoryService.state(player) })
end

function ArmoryService.buyGrenade(player: Player, id: string)
	local profile = profileOf(player)
	if not profile then
		return fail(player, "no profile")
	end
	local def = nil
	for _, entry in ipairs(EconomyConfig.Grenades or {}) do
		if entry.id == tostring(id or "") then
			def = entry
		end
	end
	if not def then
		return fail(player, "unknown grenade")
	end
	profile.ownedGrenades = profile.ownedGrenades or { Frag = true }
	if profile.ownedGrenades[def.id] then
		return fail(player, "already owned")
	end
	local rankNeeded = tonumber(def.unlockRank) or 1
	if (profile.rank or 1) < rankNeeded then
		return fail(player, string.format("requires rank %d", rankNeeded))
	end
	local price = tonumber(def.cost) or 0
	if (profile.credits or 0) < price then
		return fail(player, string.format("needs %d credits", price))
	end
	profile.credits -= price
	profile.ownedGrenades[def.id] = true
	RequisitionService.recordSharedPurchase(profile, "grenade", def.id, price)
	ProfileService.markDirty(player)
	ProfileService.save(player)
	workspace:SetAttribute("GF_GrenadeBought", def.id .. ":" .. tostring(price))
	push(player, { ok = true, action = "buyGrenade", id = def.id, state = ArmoryService.state(player) })
end

function ArmoryService.equipGrenade(player: Player, id: string)
	if workspace:GetAttribute("GF_InMission") == true then
		return fail(player, "loadout locked in mission")
	end
	local profile = profileOf(player)
	if not profile then
		return fail(player, "no profile")
	end
	local wanted = tostring(id or "")
	local found = false
	for _, entry in pairs(EconomyConfig.Grenades or {}) do
		local entryId = type(entry) == "table" and (entry.id or entry.name) or entry
		if entryId == wanted then
			found = true
		end
	end
	if not found then
		return fail(player, "unknown grenade")
	end
	profile.selectedLoadout.grenade = wanted
	workspace:SetAttribute("GF_GrenadeEquipped", wanted)
	ProfileService.markDirty(player)
	push(player, { ok = true, action = "equipGrenade", id = wanted, state = ArmoryService.state(player) })
end

function ArmoryService.buyArmor(player: Player, id: string)
	local profile = profileOf(player)
	if not profile then
		return fail(player, "no profile")
	end
	local suit = ArmorConfig.get(tostring(id or ""))
	if not suit then
		return fail(player, "unknown armor")
	end
	profile.ownedArmor = profile.ownedArmor or { STANDARD = true }
	if profile.ownedArmor[suit.id] then
		return fail(player, "already owned")
	end
	if RequisitionService.premiumLocked(profile, "armor", suit.id) then
		return fail(player, "requires Siege Division requisition")
	end
	local reqTierLocked, reqTier = RequisitionService.premiumTierLocked(profile, "armor", suit.id)
	if reqTierLocked then
		return fail(player, string.format("requires Siege Division tier %d", reqTier))
	end
	if (profile.rank or 1) < suit.unlockRank then
		return fail(player, string.format("requires rank %d", suit.unlockRank))
	end
	if (profile.credits or 0) < suit.cost then
		return fail(player, string.format("needs %d credits", suit.cost))
	end
	profile.credits -= suit.cost
	profile.ownedArmor[suit.id] = true
	RequisitionService.recordSharedPurchase(profile, "armor", suit.id, suit.cost)
	ProfileService.markDirty(player)
	ProfileService.save(player)
	workspace:SetAttribute("GF_ArmorBought", suit.id .. ":" .. tostring(suit.cost))
	push(player, { ok = true, action = "buyArmor", id = suit.id, state = ArmoryService.state(player) })
end

function ArmoryService.equipArmor(player: Player, id: string)
	if workspace:GetAttribute("GF_InMission") == true then
		return fail(player, "loadout locked in mission")
	end
	local profile = profileOf(player)
	if not profile then
		return fail(player, "no profile")
	end
	local suit = ArmorConfig.get(tostring(id or ""))
	if not suit then
		return fail(player, "unknown armor")
	end
	profile.ownedArmor = profile.ownedArmor or { STANDARD = true }
	if not profile.ownedArmor[suit.id] then
		return fail(player, "not owned")
	end
	profile.selectedLoadout.armor = suit.id
	ProfileService.markDirty(player)
	local ok = pcall(function()
		local character = player.Character
		if character then
			require(script.Parent.AppearanceService).dress(character, suit.id)
		end
	end)
	workspace:SetAttribute("GF_ArmorEquipped", suit.id .. ":" .. tostring(ok))
	push(player, { ok = true, action = "equipArmor", id = suit.id, state = ArmoryService.state(player) })
end

function ArmoryService.loadLoadout(player: Player, slot: any)
	local profile = profileOf(player)
	if not profile then
		return fail(player, "no profile")
	end
	local index = tonumber(slot) or 0
	local saved = profile.savedLoadouts and profile.savedLoadouts[tostring(index)]
	if type(saved) ~= "table" then
		return fail(player, "loadout slot is empty")
	end
	profile.selectedLoadout = copyLoadout(saved)
	ProfileService.markDirty(player)
	local ok = pcall(function()
		require(script.Parent.CombatService).applyLoadout(player)
	end)
	workspace:SetAttribute("GF_LoadoutLoaded", index)
	workspace:SetAttribute("GF_LoadoutLoadOk", ok)
	push(player, { ok = true, action = "loadLoadout", slot = index, state = ArmoryService.state(player) })
end

local function missionLocked(player: Player): boolean
	-- S03-036: loadouts lock for the whole mission including redeploys; class passives fixed throughout.
	return workspace:GetAttribute("GF_InMission") == true
end

function ArmoryService.equip(player: Player, id: string)
	if missionLocked(player) then
		return fail(player, "loadout locked in mission")
	end
	local profile = profileOf(player)
	if not profile then return fail(player, "no profile") end
	local row = Weapons.ById[id]
	if not row then return fail(player, "unknown weapon") end
	if not profile.ownedWeapons[id] then return fail(player, "not owned") end
	local slot = row.category == "Pistol" and "secondary" or "primary"
	profile.selectedLoadout[slot] = id
	ProfileService.markDirty(player)
	push(player, { ok = true, action = "equip", id = id, state = ArmoryService.state(player) })
	-- swap the live session weapon too, otherwise equipping only changed a menu label
	local ok = pcall(function()
		require(ServerScriptService.GF.Services.CombatService).applyLoadout(player)
	end)
	if not ok then
		warn("[GF] ArmoryService: applyLoadout failed")
	end
end

-- Augments are the credit sink: they had a cost in the config and no way to buy one, so credits piled up with
-- nothing to spend them on once the six weapons were owned.
function ArmoryService.buyAugment(player: Player, id: string?, category: string?)
	local profile = profileOf(player)
	if not profile then return fail(player, "no profile") end
	local catalog = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Augments)
	local AugmentService = require(script.Parent.AugmentService)
	local def = nil
	if type(id) == "string" and id ~= "" then
		def = catalog.ById and catalog.ById[id] or nil
	end
	if not def and type(category) == "string" then
		def = catalog.roll(category)
	end
	if not def then return fail(player, "unknown augment") end
	if profile.rank < (tonumber(def.unlockRank) or 1) then
		return fail(player, string.format("requires rank %d", tonumber(def.unlockRank) or 1))
	end
	local cost = tonumber(def.cost) or 0
	if profile.credits < cost then
		return fail(player, string.format("needs %d credits", cost))
	end
	profile.credits -= cost
	local uid, itemOrReason = AugmentService.grantAugment(profile, def.id, { source = "armory purchase" })
	if not uid then
		profile.credits += cost
		return fail(player, tostring(itemOrReason))
	end
	ProfileService.markDirty(player)
	ProfileService.save(player)
	workspace:SetAttribute("GF_AugmentBought", string.format("%s:%s:%s:%d", def.category, def.id, uid, cost))
	push(player, { ok = true, action = "augmentBuy", id = def.id, uid = uid, state = ArmoryService.state(player) })
end

function ArmoryService.setClass(player: Player, id: string)
	local profile = profileOf(player)
	if not profile then return fail(player, "no profile") end
	if not Classes.ById[id] then return fail(player, "unknown class") end
	profile.selectedClass = id
	local ClassService = require(script.Parent.ClassService)
	ClassService.apply(player)
	ProfileService.markDirty(player)
	push(player, { ok = true, action = "class", id = id, state = ArmoryService.state(player) })
end

function ArmoryService.handleRequest(player: Player)
	local state = ArmoryService.state(player)
	if state then push(player, { ok = true, action = "state", state = state }) end
end

function ArmoryService.handleSet(player: Player, payload: any)
	if type(payload) ~= "table" then return fail(player, "bad payload") end
	local action, id = tostring(payload.action or ""), tostring(payload.id or "")
	-- Loadout lock: the deploy snapshot is final, so late loadout changes are rejected while in a mission.
	if MISSION_LOCKED_ACTIONS[action] then
		local okZone, zone = pcall(function()
			return require(script.Parent.StationService).zoneOf(player)
		end)
		if okZone and zone == "Mission" then
			return fail(player, "loadout locked during mission")
		end
	end
	if action == "bossRewardTest" then
		if workspace:GetAttribute("GF_TestHooks") ~= true then
			return fail(player, "test hooks disabled")
		end
		local bossId = tostring(payload.id or "VEYR")
		local result = ProfileService.grantBossReward(player, bossId, 0, 0)
		push(player, { ok = true, action = "bossRewardTest", id = bossId, state = ArmoryService.state(player) })
		return result
	end
	if action == "grantTestAugment" then
		-- Studio-only: grants one augment and mastery 5 on the live weapon so the socket gate can be exercised
		-- end to end. Refuses unless the server itself has set GF_TestHooks, so live play cannot reach it.
		if workspace:GetAttribute("GF_TestHooks") ~= true then
			return fail(player, "test hooks disabled")
		end
		local profile = profileOf(player)
		local AugmentService = require(script.Parent.AugmentService)
		if not profile then
			return fail(player, "no profile")
		end
		local weaponId = tostring(payload.weapon or "AR01")
		local augmentId = tostring(payload.id or "ExtendedMagazine")
		AugmentService.grantAugment(profile, augmentId)
		ProfileService.addMastery(player, weaponId, 5)
		ProfileService.markDirty(player)
		ProfileService.save(player)
		workspace:SetAttribute("GF_TestGrant", weaponId .. ":" .. augmentId)
		push(player, { ok = true, action = "grantTestAugment", id = augmentId, state = ArmoryService.state(player) })
		return
	end
	if action == "augmentBuy" then
		-- S02-063 buy/equip separation: purchasing and equipping are distinct operations — buying adds
-- to inventory without changing the loadout, equipping never spends. Currency spend always
-- requires explicit confirmation with the cost shown.
function ArmoryService.confirmPurchase(plr: Player, itemId: string, cost: number): boolean
	-- confirmation gate: the client sends intent, the server validates funds and confirms
	local credits = plr:GetAttribute("GF_Credits") or 0
	if credits < cost then
		workspace:SetAttribute("GF_InsufficientCurrency", plr.Name)
		return false
	end
	plr:SetAttribute("GF_Credits", credits - cost)
	workspace:SetAttribute("GF_PurchaseConfirmed", itemId)
	return true
end

function ArmoryService.equipWithoutCost(plr: Player, itemId: string): boolean
	-- equip never spends — ownership is the only gate
	local owned = plr:GetAttribute("GF_Owns_" .. itemId)
	if not owned then
		return false
	end
	workspace:SetAttribute("GF_Equipped_" .. plr.UserId, itemId)
	return true
end

return ArmoryService.buyAugment(player, id, type(payload.category) == "string" and payload.category or nil)
	end
	if action == "augment" then
		-- Socket assignment is server-authoritative: the second socket is gated on per-weapon mastery.
		local profile = profileOf(player)
		local AugmentService = require(script.Parent.AugmentService)
		if not profile then
			return fail(player, "no profile")
		end
		local ok, reason = AugmentService.equipAugment(profile, tostring(payload.weapon or ""), tonumber(payload.slot) or 0, id)
		if not ok then
			workspace:SetAttribute("GF_AugmentRejected", tostring(reason))
			return fail(player, tostring(reason))
		end
		workspace:SetAttribute("GF_AugmentRejected", nil)
		workspace:SetAttribute("GF_AugmentEquipped", string.format("%s:%d=%s", tostring(payload.weapon), tonumber(payload.slot) or 0, id))
		ProfileService.markDirty(player)
		ProfileService.save(player)
		push(player, { ok = true, action = "augment", id = id, uid = id, state = ArmoryService.state(player) })
		return
	end
	if action == "augmentFavorite" then
		local profile = profileOf(player)
		if not profile then return fail(player, "no profile") end
		local ok, result = require(script.Parent.AugmentService).setFavorite(profile, id, payload.favorite ~= false)
		if not ok then return fail(player, tostring(result)) end
		ProfileService.markDirty(player)
		ProfileService.save(player)
		push(player, { ok = true, action = action, id = id, state = ArmoryService.state(player) })
		return
	end
	if action == "augmentReroll" then
		local profile = profileOf(player)
		if not profile then return fail(player, "no profile") end
		local ok, result = require(script.Parent.AugmentService).reroll(profile, id, payload.lockIndex)
		if not ok then return fail(player, tostring(result)) end
		ProfileService.markDirty(player)
		ProfileService.save(player)
		workspace:SetAttribute("GF_AugmentRerollOffer", id)
		push(player, { ok = true, action = action, id = id, state = ArmoryService.state(player) })
		return
	end
	if action == "augmentRerollAccept" or action == "augmentRerollKeep" then
		local profile = profileOf(player)
		if not profile then return fail(player, "no profile") end
		local ok, result = require(script.Parent.AugmentService).resolveReroll(profile, action == "augmentRerollAccept")
		if not ok then return fail(player, tostring(result)) end
		ProfileService.markDirty(player)
		ProfileService.save(player)
		push(player, { ok = true, action = action, state = ArmoryService.state(player) })
		return
	end
	if action == "augmentFusePreview" then
		local profile = profileOf(player)
		if not profile then return fail(player, "no profile") end
		local ok, result = require(script.Parent.AugmentService).fusionPreview(profile, payload.inputs)
		if not ok then return fail(player, tostring(result)) end
		push(player, { ok = true, action = action, fusionPreview = result, state = ArmoryService.state(player) })
		return
	end
	if action == "augmentDismantleBulk" then
		local profile = profileOf(player)
		if not profile then return fail(player, "no profile") end
		local rarity = type(payload.rarity) == "string" and payload.rarity or "ALL"
		local category = type(payload.category) == "string" and payload.category or "ANY"
		local preview = require(script.Parent.AugmentService).dismantleCandidates(profile, rarity, category)
		if payload.confirm ~= true then
			push(player, { ok = true, action = action, preview = preview, state = ArmoryService.state(player) })
			return
		end
		local ok, result = require(script.Parent.AugmentService).dismantle(profile, preview.uids)
		if not ok then return fail(player, tostring(result)) end
		ProfileService.markDirty(player)
		ProfileService.save(player)
		push(player, { ok = true, action = action, result = result, state = ArmoryService.state(player) })
		return
	end
	if action == "augmentDismantle" then
		local profile = profileOf(player)
		if not profile then return fail(player, "no profile") end
		local ok, result = require(script.Parent.AugmentService).dismantle(profile, { id })
		if not ok then return fail(player, tostring(result)) end
		ProfileService.markDirty(player)
		ProfileService.save(player)
		push(player, { ok = true, action = action, id = id, result = result, state = ArmoryService.state(player) })
		return
	end
	if action == "augmentFuse" then
		local profile = profileOf(player)
		if not profile then return fail(player, "no profile") end
		local inputs = type(payload.inputs) == "table" and payload.inputs or { id }
		local ok, result = require(script.Parent.AugmentService).fuse(profile, inputs)
		if not ok then return fail(player, tostring(result)) end
		ProfileService.markDirty(player)
		ProfileService.save(player)
		push(player, { ok = true, action = action, result = result, state = ArmoryService.state(player) })
		return
	end
	if action == "bulkOpenCache" then
		local tierId = type(id) == "string" and id or "Common"
		local opened = require(script.Parent.CacheService).openMany(player, tierId, 10, type(payload.category) == "string" and payload.category or nil)
		workspace:SetAttribute("GF_BulkOpenResult", tostring(opened))
		if opened > 0 then ProfileService.markDirty(player) end
	elseif action == "expandAugmentInventory" then
		local profile = profileOf(player)
		local ok, reason = require(script.Parent.AugmentService).expandCapacity(profile)
		workspace:SetAttribute("GF_AugmentExpandResult", tostring(ok) .. ":" .. tostring(reason))
		if ok then ProfileService.markDirty(player) end
	elseif action == "reqUnlock" then ArmoryService.unlockRequisition(player, payload.reqId or id)
	elseif action == "reqBuy" then ArmoryService.buyRequisition(player, payload.reqId, payload.key or id)
	elseif action == "buy" then ArmoryService.buy(player, id)
	elseif action == "equip" then ArmoryService.equip(player, id)
	elseif action == "buyAbility" then ArmoryService.buyAbility(player, id)
	elseif action == "equipAbility" then ArmoryService.equipAbility(player, payload.slot, id)
	elseif action == "grantSalvage" then
		if workspace:GetAttribute("GF_TestHooks") ~= true then
			return fail(player, "test hooks disabled")
		end
		require(script.Parent.SquadService).add(tostring(payload.kind or "scrap"), tonumber(payload.amount) or 10)
		push(player, { ok = true, action = "grantSalvage", state = ArmoryService.state(player) })
	elseif action == "buyGrenade" then ArmoryService.buyGrenade(player, id)
	elseif action == "equipGrenade" then ArmoryService.equipGrenade(player, id)
	elseif action == "openCache" then
		local Cache = require(script.Parent.CacheService)
		local rolled = Cache.openFromInventory(player, tostring(payload.tier or ""), type(payload.category) == "string" and payload.category or nil)
		push(player, { ok = #rolled > 0, action = "openCache", id = tostring(payload.tier or ""), count = #rolled, state = ArmoryService.state(player) })
	elseif action == "buyArmor" then ArmoryService.buyArmor(player, id)
	elseif action == "equipArmor" then ArmoryService.equipArmor(player, id)
	elseif action == "saveLoadout" then ArmoryService.saveLoadout(player, payload.slot)
	elseif action == "loadLoadout" then ArmoryService.loadLoadout(player, payload.slot)
	elseif action == "class" then ArmoryService.setClass(player, id)
	else fail(player, "unknown action") end
end

-- The station is torn down and rebuilt (Main rebuilds it when boot finds it missing), and the rack is
-- recreated with it. A prompt attached once to the old rack goes with it, which is why touching the
-- prompt did nothing. This keeps re-attaching to whatever rack currently exists.
local promptTarget: BasePart? = nil
local function ensureArmoryPrompt()
	local station = workspace:FindFirstChild("Station")
	if not station then
		return
	end
	local rack: BasePart? = nil
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "ArmoryRack" then
			rack = d
			break
		end
	end
	if not rack or rack == promptTarget then
		return
	end
	promptTarget = rack
	local existing = rack:FindFirstChild("OpenArmory")
	local prompt = existing or Instance.new("ProximityPrompt")
	prompt.Name = "OpenArmory"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Armory"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = rack
	if not existing then
		prompt.Triggered:Connect(function(player)
			local remote = remotes().OpenArmoryPanel
			if remote then
				remote:FireClient(player)
			end
		end)
	end
	workspace:SetAttribute("GF_ArmoryPrompt", true)
end

function ArmoryService.start()
	ensureArmoryPrompt()
	-- cheap watchdog: re-attach after a rebuild without polling every frame
	task.spawn(function()
		while true do
			task.wait(2)
			pcall(ensureArmoryPrompt)
		end
	end)
	remotes().RequestLoadout.OnServerEvent:Connect(function(player)
		if not require(script.Parent.NetGuard).allow(player, "read") then
			return
		end
		ArmoryService.handleRequest(player)
	end)
	remotes().SetLoadout.OnServerEvent:Connect(function(player, payload)
		-- SetLoadout mixes purchases and equips in one surface, and the spec authors different rates
		-- for the two (purchases 2/s, equip 4/s), so the bucket follows the declared action.
		local action = (type(payload) == "table" and type(payload.action) == "string") and payload.action or ""
		local ECONOMY = {
			buy = true, buyAbility = true, buyGrenade = true, buyArmor = true,
			reqUnlock = true, reqBuy = true, augmentBuy = true, expandAugmentInventory = true,
			openCache = true, bulkOpenCache = true, augmentReroll = true, augmentRerollAccept = true,
			augmentRerollKeep = true, augmentFuse = true, augmentFusePreview = true,
			augmentDismantle = true, augmentDismantleBulk = true,
		}
		local bucket = ECONOMY[action] and "purchase" or "equip"
		if not require(script.Parent.NetGuard).allowPayload(player, bucket, payload) then
			return
		end
		ArmoryService.handleSet(player, payload)
	end)
	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function()
			if not player.Parent then
				return
			end
			-- repair loadouts saved before compatibility was enforced
			local profile = ProfileService.get(player)
			if profile then
				local cleared = require(script.Parent.AugmentService).sanitiseLoadout(profile)
				if cleared > 0 then
					ProfileService.markDirty(player)
				end
			end
			ArmoryService.handleRequest(player)
		end)
	end)
end

return ArmoryService
