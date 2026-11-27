--!strict
-- Versioned profile with DataStore persistence, memory fallback, and safe defaults.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.GF.Shared.Configs.Economy)
local Weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
local Abilities = require(ReplicatedStorage.GF.Shared.Configs.Abilities)

local ProfileService = {}

local STORE_NAME = "GF_Profiles_v1"
local SCHEMA_VERSION = 1

local store: DataStore? = nil
local persistenceMode = "memory"
local profiles: { [number]: any } = {}
local dirty: { [number]: boolean } = {}

function ProfileService.defaults(userId: number)
	return {
		schemaVersion = SCHEMA_VERSION,
		userId = userId,
		rank = 1,
		xp = 0,
		credits = 0,
		ownedWeapons = { ["AR01"] = true, ["P01"] = true },
		ownedAbilities = { Airstrike = true, DomeShield = true },
		ownedAugments = {},
		-- Per-instance inventory keyed by UID; ownedAugments is only a legacy/catalog archetype index.
		augmentInventory = {},
		pendingReroll = nil,
		-- Explicit on load rather than relying on 'or BASELINE_CAPACITY' at read time (GOAL: 200 baseline, 400 cap).
		augmentCapacity = 200,
		ownedArmor = { STANDARD = true },
		ownedGrenades = { Frag = true },
	caches = {},
	warCredits = 0,
	unlockedRequisitions = {},
	requisitionSpend = {},
	purchasedEntries = {},
	entitlements = {},
	processedReceipts = {},
	-- S10-009: one free starter pick (AR/SMG/LMG) after the tutorial, claimed once.
	starterClaimed = false,
		weaponMastery = {},
		bossResearch = {},
		salvage = { scrap = 0, energyCells = 0, militaryTechnology = 0 },
		selectedClass = "Assault",
		selectedLoadout = {
			primary = "AR01",
			secondary = "P01",
			grenade = "Frag",
			-- one support ability slot (Counteroffensive contract revision); owned abilities
			-- are never lost — the equipment contract collapsed, not the collection
			ability = "Airstrike",
			armor = "STANDARD",
			weaponAugments = {},
			abilityAugment = nil,
		},
		savedLoadouts = {},
		cosmetics = {},
		settings = { aimSensitivity = 1, invertY = false, sprintToggle = false, reducedMotion = false, subtitles = true },
		tutorialCompleted = false,
		introWatched = false,
		dispatchStats = { qualifyingAssists = 0, claimedMilestones = 0 },
		dispatchAssistMissions = {},
		careerStats = { kills = 0, extractions = 0, missions = 0 },
		commendations = {},
		commandServiceStats = { missionsLed = 0 },
		transactionJournalVersion = 1,
		lastSaveTime = 0,
		-- L222 schema fields that were absent outright. revision backs the optimistic-concurrency fence
		-- in save(); tutorialProgress is the stage index First Spear resumes from; recentTransactionIds
		-- is the umbrella dedup journal (specialized detail tables: processedReceipts, settledMissions).
		revision = 0,
		tutorialProgress = 0,
		firstMissionBonusClaimed = false,
		settledMissions = {},
		ownedBlueprints = {},
		recentTransactionIds = {},
	}
end

-- Repairs a loaded profile against defaults so a partial/older save cannot crash a service.
-- Numeric coercion helper: NaN and infinities collapse to the fallback rather than surviving, which
-- raw math.max/math.clamp cannot guarantee (NaN comparisons are false).
local function finiteOr(v: any, fallback: number): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return n
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in pairs(value) do
		out[key] = deepCopy(child)
	end
	return out
end

-- A profile is only useful if its active/preset loadouts reference gear the profile actually owns.
-- Corrupt or pre-fix documents degrade to the free starter build rather than equipping unpurchased
-- equipment or failing the entire load.
local function sanitizeLoadout(rawLoadout: any, profile: any): any
	local out = {
		primary = "AR01",
		secondary = "P01",
		grenade = "Frag",
		ability = "Airstrike",
		armor = "STANDARD",
		weaponAugments = {},
		abilityAugment = nil,
	}
	if type(rawLoadout) == "table" then
		for key, value in pairs(rawLoadout) do
			out[key] = deepCopy(value)
		end
	end
	local function owns(mapName: string, id: any): boolean
		return type(id) == "string" and type(profile[mapName]) == "table" and profile[mapName][id] == true
	end
	local primary = Weapons.get(out.primary)
	if not owns("ownedWeapons", out.primary) or not primary or primary.category == "Pistol" then
		out.primary = "AR01"
	end
	local secondary = Weapons.get(out.secondary)
	if not owns("ownedWeapons", out.secondary) or not secondary or secondary.category ~= "Pistol" then
		out.secondary = "P01"
	end
	local grenadeValid = false
	for _, grenade in ipairs(Economy.Grenades or {}) do
		if grenade.id == out.grenade then
			grenadeValid = true
			break
		end
	end
	if not grenadeValid or not owns("ownedGrenades", out.grenade) then
		out.grenade = "Frag"
	end
	if not Abilities.get(out.ability) or not owns("ownedAbilities", out.ability) then
		out.ability = "Airstrike"
	end
	if type(out.armor) ~= "string" or not owns("ownedArmor", out.armor) then
		out.armor = "STANDARD"
	end
	if type(out.weaponAugments) ~= "table" then
		out.weaponAugments = {}
	end
	if type(out.abilityAugment) ~= "string" then
		out.abilityAugment = nil
	end
	return out
end

local function migrate(raw: any, userId: number)
	local base = ProfileService.defaults(userId)
	if type(raw) ~= "table" then
		return base
	end
	for k, v in base do
		if raw[k] == nil then
			raw[k] = v
		elseif type(v) == "table" and type(raw[k]) == "table" then
			for k2, v2 in v do
				if raw[k][k2] == nil then
					raw[k][k2] = v2
				end
			end
		end
	end
	-- one-slot support ability migration (Counteroffensive contract): collapse legacy
	-- ability1/ability2 into the single slot. rule: slot 1 wins when set — owned abilities
	-- are unaffected, and the freed choice is re-equippable in seconds, so no player-facing
	-- migration prompt is warranted. saved loadouts transform identically.
	local function collapseAbilities(loadout)
		if type(loadout) ~= "table" then
			return
		end
		-- legacy fields win when present: the defaults-fill above injects ability="Airstrike"
		-- into pre-migration saves before this transform runs, so testing ability == nil here
		-- would never fire and the player's real slot-1 choice would be silently flattened to
		-- the default. legacy ability1/ability2 only exist in old saves, so preferring them is
		-- exactly the migration semantic; fresh profiles never carry them.
		loadout.ability = loadout.ability1 or loadout.ability2 or loadout.ability or "Airstrike"
		loadout.ability1 = nil
		loadout.ability2 = nil
	end
	collapseAbilities(raw.selectedLoadout)
	if type(raw.savedLoadouts) == "table" then
		for _, loadout in raw.savedLoadouts do
			collapseAbilities(loadout)
		end
	end
	raw.schemaVersion = SCHEMA_VERSION
	raw.userId = userId
	raw.rank = math.clamp(math.floor(finiteOr(raw.rank, 1)), 1, Economy.MaxRank)
	raw.xp = math.max(0, finiteOr(raw.xp, 0))
	raw.credits = math.max(0, finiteOr(raw.credits, 0))
	raw.warCredits = math.max(0, finiteOr(raw.warCredits, 0))
	if type(raw.unlockedRequisitions) ~= "table" then
		raw.unlockedRequisitions = {}
	end
	if type(raw.purchasedEntries) ~= "table" then
		raw.purchasedEntries = {}
	end
	if type(raw.entitlements) ~= "table" then
		raw.entitlements = {}
	end
	if type(raw.processedReceipts) ~= "table" then
		raw.processedReceipts = {}
	end
	if type(raw.requisitionSpend) ~= "table" then
		raw.requisitionSpend = {}
	end
	for reqId, amount in raw.requisitionSpend do
		raw.requisitionSpend[reqId] = math.max(0, finiteOr(amount, 0))
	end
	if type(raw.salvage) ~= "table" then
		raw.salvage = { scrap = 0, energyCells = 0, militaryTechnology = 0 }
	end
	for k, v in raw.salvage do
		raw.salvage[k] = math.max(0, finiteOr(v, 0))
	end
	-- Deep validation (L222: type/range validation on load). Anything malformed is dropped or clamped
	-- rather than trusted, so a corrupted document cannot crash services or inject impossible state.
	raw.revision = math.max(0, math.floor(finiteOr(raw.revision, 0)))
	raw.tutorialProgress = math.max(0, math.floor(finiteOr(raw.tutorialProgress, 0)))
	raw.firstMissionBonusClaimed = raw.firstMissionBonusClaimed == true
	if type(raw.settledMissions) ~= "table" then
		raw.settledMissions = {}
	end
	if type(raw.ownedBlueprints) ~= "table" then
		raw.ownedBlueprints = {}
	end
	if type(raw.recentTransactionIds) ~= "table" then
		raw.recentTransactionIds = {}
	end
	-- Ownership maps are boolean-set tables; anything else is corrupt. The free starter kit is then
	-- re-asserted: a migration must never produce a profile with no valid equipable build.
	for _, key in { "ownedWeapons", "ownedArmor", "ownedAbilities", "ownedGrenades" } do
		if type(raw[key]) ~= "table" then
			raw[key] = {}
		else
			for itemId, owned in raw[key] do
				if type(itemId) ~= "string" or owned ~= true then
					raw[key][itemId] = nil
				end
			end
		end
	end
	raw.ownedWeapons.AR01 = true
	raw.ownedWeapons.P01 = true
	raw.ownedGrenades.Frag = true
	raw.ownedAbilities.Airstrike = true
	raw.ownedAbilities.DomeShield = true
	raw.ownedArmor.STANDARD = true
	-- Active and preset loadouts are equipment references, not a second inventory. Strip references
	-- to unpurchased/unknown gear here so even legacy or corrupted documents cannot bypass ownership.
	raw.selectedLoadout = sanitizeLoadout(raw.selectedLoadout, raw)
	if type(raw.savedLoadouts) ~= "table" then
		raw.savedLoadouts = {}
	else
		local cleanSaved = {}
		for key, loadout in pairs(raw.savedLoadouts) do
			if (key == "1" or key == "2" or key == "3") and type(loadout) == "table" then
				cleanSaved[key] = sanitizeLoadout(loadout, raw)
			end
		end
		raw.savedLoadouts = cleanSaved
	end
	if type(raw.dispatchStats) ~= "table" then
		raw.dispatchStats = { qualifyingAssists = 0, claimedMilestones = 0 }
	else
		raw.dispatchStats.qualifyingAssists = math.max(0, math.floor(finiteOr(raw.dispatchStats.qualifyingAssists, 0)))
		raw.dispatchStats.claimedMilestones = math.max(0, math.floor(finiteOr(raw.dispatchStats.claimedMilestones, 0)))
	end
	if type(raw.dispatchAssistMissions) ~= "table" then
		raw.dispatchAssistMissions = {}
	end
	if type(raw.careerStats) ~= "table" then
		raw.careerStats = { kills = 0, extractions = 0, missions = 0 }
	else
		for _, metric in { "kills", "extractions", "missions" } do
			raw.careerStats[metric] = math.max(0, math.floor(finiteOr(raw.careerStats[metric], 0)))
		end
	end
	if type(raw.commendations) ~= "table" then
		raw.commendations = {}
	else
		for id, earned in raw.commendations do
			if type(id) ~= "string" or earned ~= true then
				raw.commendations[id] = nil
			end
		end
	end
	-- augmentInventory entries must carry the authored shape or they are dropped.
	if type(raw.augmentInventory) == "table" then
		for uid, entry in raw.augmentInventory do
			if type(entry) ~= "table" or type(entry.archetypeId) ~= "string" or type(entry.category) ~= "string" then
				raw.augmentInventory[uid] = nil
			end
		end
	else
		raw.augmentInventory = {}
	end
	raw.augmentCapacity = math.clamp(math.floor(tonumber(raw.augmentCapacity) or 200), 1, 400)
	if type(raw.weaponMastery) ~= "table" then
		raw.weaponMastery = {}
	else
		for weaponId, xp in raw.weaponMastery do
			raw.weaponMastery[weaponId] = math.clamp(math.floor(finiteOr(xp, 0)), 0, 650)
		end
	end
	return raw
end

-- Exported so the malformed-document contract (L222) is unit-testable without a Player or DataStore.
ProfileService.validateAndMigrate = migrate

-- Pure lease-fence decision, exported for the same reason: should a session holding `myToken` with
-- documents loaded at `baseRevision` write over `stored`? True means a newer different session owns
-- the profile and the write must abort.
function ProfileService.leaseConflict(stored: any, myToken: string?, baseRevision: number): boolean
	if type(stored) ~= "table" then
		return false
	end
	local storedRev = tonumber(stored.revision) or 0
	local storedToken = type(stored.sessionLease) == "table" and stored.sessionLease.token or nil
	return storedRev > (tonumber(baseRevision) or 0) and storedToken ~= nil and storedToken ~= myToken
end

-- Boss rewards: credits, XP, and a blueprint with a pity floor. GOAL §10 fixes the protection at
-- 25% per qualifying clear and a guarantee on the third qualifying extraction. The shared Constants
-- table still carries the superseded 5/15% values, so these spec values are intentionally local.
local BOSS_PITY = 3
local BOSS_BLUEPRINT_CHANCE = 0.25
-- Once the blueprint is owned, a repeated rare drop is converted into useful advanced research
-- salvage rather than vanishing. The exact conversion is deliberately conservative: roughly one
-- high-value operation's rare-material yield, not a second progression ladder.
local DUPLICATE_BLUEPRINT_SALVAGE = { energyCells = 2, militaryTechnology = 1 }

-- Boss kills happen mid-mission, but boss progression is only earned by a qualifying clear:
-- meaningful participation, boss defeated, and successful team extraction. Queue the kill in memory
-- and settle it from RewardsService at the same critical-write point as the operation payout. A crash
-- or failed extraction therefore cannot bank boss credits/XP/blueprints early.
local pendingBossRewards: { [number]: { any } } = {}

local function currentLedgerMissionId(): string?
	local missionId = nil
	pcall(function()
		missionId = require(script.Parent.RewardLedgerService).missionId()
	end)
	return type(missionId) == "string" and missionId or nil
end

local function bossResearchRecord(profile: any, bossId: string): any
	if type(profile.bossResearch) ~= "table" then
		profile.bossResearch = {}
	end
	local rec = profile.bossResearch[bossId]
	if type(rec) ~= "table" then
		rec = { kills = 0, pity = 0, blueprintUnlocked = false }
		profile.bossResearch[bossId] = rec
	end
	return rec
end

local function bossPendingResult(profile: any, bossId: string, credits: number, xp: number): any
	local rec = bossResearchRecord(profile, bossId)
	return {
		kills = tonumber(rec.kills) or 0,
		pity = tonumber(rec.pity) or 0,
		blueprintUnlocked = rec.blueprintUnlocked == true,
		granted = false,
		credits = credits,
		xp = xp,
		pending = true,
	}
end

local function applyBossReward(player: Player, bossId: string, credits: number, xp: number): any
	local profile = ProfileService.ensure(player)
	if not profile then
		return nil
	end
	local rec = bossResearchRecord(profile, bossId)
	rec.kills = (tonumber(rec.kills) or 0) + 1
	rec.pity = (tonumber(rec.pity) or 0) + 1
	local granted = false
	local duplicateConverted = false
	-- A test switch so the pity rule can be proven deterministically: with chance disabled only pity
	-- can grant, which is what the acceptance check is about.
	local chanceAllowed = workspace:GetAttribute("GF_ForceNoBlueprintChance") ~= true
	if not rec.blueprintUnlocked then
		if rec.pity >= BOSS_PITY or (chanceAllowed and math.random() < BOSS_BLUEPRINT_CHANCE) then
			rec.blueprintUnlocked = true
			rec.pity = 0
			granted = true
			profile.ownedBlueprints = type(profile.ownedBlueprints) == "table" and profile.ownedBlueprints or {}
			profile.ownedBlueprints[bossId] = true
		end
	elseif chanceAllowed and math.random() < BOSS_BLUEPRINT_CHANCE then
		duplicateConverted = true
		profile.salvage = type(profile.salvage) == "table" and profile.salvage or { scrap = 0, energyCells = 0, militaryTechnology = 0 }
		for resource, amount in pairs(DUPLICATE_BLUEPRINT_SALVAGE) do
			profile.salvage[resource] = (tonumber(profile.salvage[resource]) or 0) + amount
		end
	end
	local awardResult = ProfileService.award(player, credits, xp)
	ProfileService.markDirty(player)
	player:SetAttribute("BossKills", rec.kills)
	player:SetAttribute("BossBlueprint", rec.blueprintUnlocked)
	player:SetAttribute("BossPity", rec.pity)
	player:SetAttribute("BossBlueprintGranted", granted)
	workspace:SetAttribute("GF_LastBossReward", string.format("%s:%s:kills=%d:pity=%d:bp=%s:credits=%d", player.Name, bossId, rec.kills, rec.pity, tostring(rec.blueprintUnlocked), credits))
	-- Stash the outcome on the profile so the mission debrief can report it. It is consumed by the
	-- debrief and then cleared so a later ordinary mission cannot repeat old news.
	profile.lastBossReward = {
		bossId = bossId,
		kills = rec.kills,
		pity = rec.pity,
		pityTarget = BOSS_PITY,
		blueprintUnlocked = rec.blueprintUnlocked,
		granted = granted,
		duplicateConverted = duplicateConverted,
		duplicateSalvage = duplicateConverted and DUPLICATE_BLUEPRINT_SALVAGE or nil,
		credits = credits,
	}
	-- shadow ledger: blueprint entitlement events (spec §28 BlueprintEntitlements)
	pcall(function()
		if granted or duplicateConverted then
			require(script.Parent.RewardLedgerService).appendEvent(
				duplicateConverted and "blueprint_duplicate_salvage" or "blueprint_entitlement", nil,
				string.format("blueprint:%s:%s:%d", tostring(bossId), tostring(player and player.UserId or "unknown"), math.floor(os.clock() * 1000)),
				player and player.UserId or nil
			)
		end
	end)
	return {
		kills = rec.kills,
		pity = rec.pity,
		blueprintUnlocked = rec.blueprintUnlocked,
		granted = granted,
		duplicateConverted = duplicateConverted,
		duplicateSalvage = duplicateConverted and DUPLICATE_BLUEPRINT_SALVAGE or nil,
		credits = credits,
		xp = xp,
		rankUps = tonumber(awardResult and awardResult.rankUps) or 0,
	}
end

function ProfileService.grantBossReward(player: Player, bossId: string, credits: number, xp: number): any
	local profile = ProfileService.ensure(player)
	if not profile then
		return nil
	end
	-- Outside an operation this function is a Studio/test path and remains immediate. In a live
	-- operation it is only evidence of a boss defeat; extraction settlement decides whether it qualifies.
	if workspace:GetAttribute("GF_InMission") ~= true then
		return applyBossReward(player, bossId, credits, xp)
	end
	local missionId = currentLedgerMissionId()
	local list = pendingBossRewards[player.UserId]
	if type(list) ~= "table" then
		list = {}
		pendingBossRewards[player.UserId] = list
	end
	for _, pending in ipairs(list) do
		if pending.bossId == bossId and pending.missionId == missionId then
			return bossPendingResult(profile, bossId, credits, xp)
		end
	end
	table.insert(list, {
		bossId = tostring(bossId),
		credits = math.max(0, math.floor(tonumber(credits) or 0)),
		xp = math.max(0, math.floor(tonumber(xp) or 0)),
		missionId = missionId,
	})
	workspace:SetAttribute("GF_BossRewardPending", player.Name .. ":" .. tostring(bossId))
	return bossPendingResult(profile, bossId, credits, xp)
end

-- Called once per participant during mission settlement. qualifying=false discards the in-memory
-- evidence; qualifying=true applies it inside the same critical-write window as the payout. Entries
-- keyed to another mission are stale crash/reset residue and are dropped rather than paid late.
function ProfileService.settlePendingBossRewards(player: Player, qualifying: boolean, missionId: string?): any
	local list = pendingBossRewards[player.UserId]
	pendingBossRewards[player.UserId] = nil
	local out = { rankUps = 0, applied = 0, dropped = 0, results = {} }
	if type(list) ~= "table" then
		return out
	end
	if qualifying == true then
		for _, pending in ipairs(list) do
			if pending.missionId == nil or missionId == nil or pending.missionId == missionId then
				local result = applyBossReward(player, pending.bossId, pending.credits, pending.xp)
				if result then
					out.applied += 1
					out.rankUps += tonumber(result.rankUps) or 0
					table.insert(out.results, result)
				end
			else
				out.dropped += 1
			end
		end
	else
		out.dropped = #list
	end
	if out.applied > 0 or out.dropped > 0 then
		workspace:SetAttribute("GF_BossRewardSettled", string.format("%s:applied=%d:dropped=%d", player.Name, out.applied, out.dropped))
	end
	return out
end
function ProfileService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok and result then
		store = result
		persistenceMode = "datastore"
	else
		warn("[GF] DataStore unavailable, profiles are session-only: " .. tostring(result))
	end
end

function ProfileService.getPersistenceMode(): string
	return persistenceMode
end

-- Load fencing. When a load fails (or the document is unusable) the player still gets a session,
-- but the profile is flagged unpersisted: save() refuses it for the rest of the session, so the
-- good durable document can never be overwritten by a default or partial one (L222). Before this,
-- one player's failed GetAsync nilled the GLOBAL store and silently dropped everyone's persistence.
local unpersisted: { [number]: boolean } = {}

function ProfileService.isUnpersisted(userId: number): boolean
	return unpersisted[userId] == true
end

function ProfileService.load(player: Player): any
	local userId = player.UserId
	local profile = nil
	local loadFailed = false
	if store then
		local ok, result = pcall(function()
			return store:GetAsync("p_" .. userId)
		end)
		if ok then
			profile = result
		else
			loadFailed = true
			warn("[GF] profile load failed for " .. userId .. ": " .. tostring(result))
		end
	end
	if loadFailed then
		unpersisted[userId] = true
		player:SetAttribute("GF_PersistenceMode", "session-only")
		warn("[GF] " .. player.Name .. " is in session-only safe mode; durable profile will NOT be overwritten")
	end
	local migrated = migrate(profile, userId)
	if not migrated then
		migrated = ProfileService.defaults(userId)
	end
	migrated.baseRevision = tonumber(migrated.revision) or 0
	migrated.sessionLease = {
		token = game:GetService("HttpService"):GenerateGUID(false),
		issuedAt = os.time(),
	}
	profiles[userId] = migrated
	print("[GF] profile ready " .. userId .. " credits=" .. tostring(migrated.credits))
	-- Load is the single choke point every caller goes through (PlayerService calls it directly), which is
	-- why syncing IntroSeen inside ensure() never ran: ensure() was not on the join path at all.
	local okSync, syncErr = pcall(function()
		player:SetAttribute("IntroSeen", migrated.introWatched == true)
	end)
	-- Publish mastery on join so the attribute agrees with the profile. Until place 468 the only writer of
	-- GF_Mastery_<weapon> was addMastery, so a returning player's attribute read nil even though the XP was
	-- safely stored -- which is indistinguishable from lost progress, and is exactly what made a previous
	-- batch report mastery as not persisting when it had persisted all along.
	pcall(function()
		for weaponId, xp in pairs(migrated.weaponMastery or {}) do
			player:SetAttribute("GF_Mastery_" .. tostring(weaponId), xp)
		end
	end)

	-- A returning player who has seen the intro but never finished First Spear still owes the tutorial;
	-- without this they would never be offered it, because the cinematic is what used to start it.
	if migrated.introWatched == true and migrated.tutorialCompleted ~= true then
		task.delay(6, function()
			if player.Parent == nil or workspace:GetAttribute("Tutorial_Active") == true then
				return
			end
			local okTutorial, TutorialService = pcall(require, game:GetService("ServerScriptService").GF.Services.TutorialService)
			if okTutorial and TutorialService and TutorialService.begin then
				pcall(TutorialService.begin, player)
			end
		end)
	end
	if not okSync then
		warn("[GF] intro sync failed: " .. tostring(syncErr))
	end
	return migrated
end

function ProfileService.get(player: Player): any?
	return profiles[player.UserId]
end

function ProfileService.getByUserId(userId: number): any?
	return profiles[userId]
end

function ProfileService.markDirty(player: Player)
	dirty[player.UserId] = true
end

function ProfileService.save(player: Player): boolean
	local profile = profiles[player.UserId]
	if not profile then
		return false
	end
	if unpersisted[player.UserId] then
		-- Load failed this session: writing defaults over the durable document would be data loss.
		return false
	end
	profile.lastSaveTime = os.time()
	if not store then
		return true
	end
	-- Optimistic concurrency with a session-lease fence (L222). The revision increments every write;
	-- the transform aborts (nil) when the durable document carries a NEWER revision under a DIFFERENT
	-- session token, which is exactly the teleport-handoff/double-session case. Single-session play
	-- never trips it because the token matches.
	profile.revision = (tonumber(profile.revision) or 0) + 1
	profile.sessionLease = profile.sessionLease or {}
	if not profile.sessionLease.token then
		profile.sessionLease.token = game:GetService("HttpService"):GenerateGUID(false)
		profile.sessionLease.issuedAt = os.time()
	end
	local myToken = profile.sessionLease.token
	local baseRevision = tonumber(profile.baseRevision) or 0
	local ok, err = pcall(function()
		return store:UpdateAsync("p_" .. player.UserId, function(stored)
			if ProfileService.leaseConflict(stored, myToken, baseRevision) then
				-- A newer session owns this profile. Refuse the write rather than clobber it.
				workspace:SetAttribute("GF_LeaseConflict", player.Name .. ":" .. tostring(os.time()))
				return nil
			end
			return profile
		end)
	end)
	if not ok then
		warn("[GF] profile save failed for " .. player.UserId .. ": " .. tostring(err))
		return false
	end
	dirty[player.UserId] = nil
	return true
end

-- Bounded exponential backoff with jitter: 3 retries max, 1s/2s/4s base +/-25%, so a transient outage
-- is absorbed while a hard outage surfaces as a logged failure instead of an infinite loop (L222).
function ProfileService.saveWithRetry(player: Player): boolean
	if ProfileService.save(player) then
		return true
	end
	for attempt = 1, 3 do
		local base = 2 ^ (attempt - 1)
		local jitter = base * (0.75 + math.random() * 0.5)
		task.wait(jitter)
		if ProfileService.save(player) then
			workspace:SetAttribute("GF_SaveRecovered", player.Name .. ":" .. attempt)
			return true
		end
	end
	warn("[GF] saveWithRetry exhausted for " .. player.Name)
	workspace:SetAttribute("GF_SaveFailed", player.Name .. ":" .. tostring(os.time()))
	return false
end

-- Umbrella dedup journal write-through (L222 recentTransactionIds). Specialized detail stays in
-- processedReceipts/settledMissions/cacheOpenJournal; this is the cross-operation ring a recovery
-- audit can scan. Ring-capped at 64; entries are never evicted before their specialized settlement
-- record exists, and settled-only eviction is already the invariant there.
function ProfileService.recordTransaction(player: Player, opId: string)
	local profile = profiles[player.UserId]
	if not profile or type(opId) ~= "string" or opId == "" then
		return
	end
	profile.recentTransactionIds = profile.recentTransactionIds or {}
	table.insert(profile.recentTransactionIds, opId)
	while #profile.recentTransactionIds > 64 do
		table.remove(profile.recentTransactionIds, 1)
	end
	ProfileService.markDirty(player)
end

-- Award XP and Credits with rank-up handling. Server-only, amounts never come from a client.
-- Per-weapon mastery. The profile has carried a weaponMastery table with nothing writing to it, so the
-- augment socket gate had no state to read and no way to be satisfied.
function ProfileService.addMastery(player: Player, weaponId: string, amount: number): number
	local profile = profiles[player.UserId]
	if not profile or type(weaponId) ~= "string" or type(amount) ~= "number" or amount <= 0 then
		return 0
	end
	profile.weaponMastery = profile.weaponMastery or {}
	local current = tonumber(profile.weaponMastery[weaponId]) or 0
	-- Capped at the level-5 threshold, not at 10. The old cap of 10 sat below the 100 XP needed for
	-- mastery level 2, so no weapon could ever leave level 1 (GOAL_2026-11-24.md L165).
	local updated = math.min(650, current + math.floor(amount))
	profile.weaponMastery[weaponId] = updated
	ProfileService.markDirty(player)
	player:SetAttribute("GF_Mastery_" .. weaponId, updated)
	return updated
end

-- Mastery levels 1-5 at the authored thresholds (GOAL_2026-11-24.md L165). Level 5 is the cap, so the
-- second permanent augment socket is reachable: the ladder exists, it was simply never written.
local MASTERY_THRESHOLDS = { 0, 100, 240, 420, 650 }
function ProfileService.masteryLevel(player: Player, weaponId: string): number
	local profile = profiles[player.UserId]
	if not profile then
		return 1
	end
	local xp = tonumber((profile.weaponMastery or {})[weaponId]) or 0
	local level = 1
	for i = 2, #MASTERY_THRESHOLDS do
		if xp >= MASTERY_THRESHOLDS[i] then
			level = i
		end
	end
	player:SetAttribute("GF_MasteryLevel_" .. weaponId, level)
	return level
end
function ProfileService.masteryThresholds(): { number }
	return MASTERY_THRESHOLDS
end

function ProfileService.award(player: Player, credits: number, xp: number): { rankUps: number }
	local profile = profiles[player.UserId]
	if not profile then
		return { rankUps = 0 }
	end
	profile.credits = math.max(0, profile.credits + math.max(0, math.floor(credits)))
	profile.xp = math.max(0, profile.xp + math.max(0, math.floor(xp)))
	local before = profile.rank
	profile.rank = math.max(profile.rank, Economy.rankForXp(profile.xp))
	ProfileService.markDirty(player)
	return { rankUps = profile.rank - before }
end

function ProfileService.flushAll()
	for userId in dirty do
		for _, player in Players:GetPlayers() do
			if player.UserId == userId then
				ProfileService.save(player)
			end
		end
	end
end

local loading: { [number]: boolean } = {}

-- Single entry point for profile acquisition. PlayerService and ProfileService.start both
-- called load() directly, so one join could open two data-store sessions for the same key
-- while the first was still in flight.
function ProfileService.ensure(player: Player): any?
	local userId = player.UserId
	if profiles[userId] then
		-- The cached path returns early, so without this the join-time IntroSeen sync never ran for any
		-- player whose profile was already loaded by another service first.
		local cached = profiles[userId]
		if cached and player:GetAttribute("IntroSeen") == nil then
			print("[GF] intro sync (cached) watched=" .. tostring(cached.introWatched))
			player:SetAttribute("IntroSeen", cached.introWatched == true)
		end
		return cached
	end
	if loading[userId] then
		local waited = 0
		while loading[userId] and waited < 10 do
			task.wait(0.05)
			waited += 0.05
		end
		return profiles[userId]
	end
	loading[userId] = true
	local ok, err = pcall(ProfileService.load, player)
	loading[userId] = nil
	-- IntroSeen used to live only as a client attribute, so it reset on every join and a veteran was
	-- shown the opening cinematic again every session. The persisted profile flag is the source of truth.
	local profile = profiles[userId]
	if profile then
		print("[GF] intro sync (loaded) watched=" .. tostring(profile.introWatched))
		player:SetAttribute("IntroSeen", profile.introWatched == true)
	end
	if not ok then
		warn("[GF] profile ensure failed for " .. player.Name .. ": " .. tostring(err))
	end
	return profiles[userId]
end

function ProfileService.start()
	if ProfileService._started then
		return
	end
	ProfileService._started = true
	ProfileService.init()
	local function onPlayer(player: Player)
		ProfileService.ensure(player)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	-- Marking the intro watched has to reach the server, because the profile is what persists.
	local remotesFolder = game:GetService("ReplicatedStorage"):FindFirstChild("GF")
	local remotes = remotesFolder and remotesFolder:FindFirstChild("Remotes")
	if remotes then
		local mark = remotes:FindFirstChild("MarkIntroSeen")
		if not mark then
			mark = Instance.new("RemoteEvent")
			mark.Name = "MarkIntroSeen"
			mark.Parent = remotes
		end
		print("[GF] intro remotes wired")
		mark.OnServerEvent:Connect(function(player)
			print("[GF] MarkIntroSeen from " .. player.Name)
			local profile = ProfileService.ensure(player)
			if not profile then
				return
			end
			if profile.introWatched ~= true then
				profile.introWatched = true
				ProfileService.markDirty(player)
				ProfileService.save(player)
				workspace:SetAttribute("GF_IntroWatched", true)
			end
			player:SetAttribute("IntroSeen", true)
			-- Skipping the opening cinematic must not erase the required tutorial: the tutorial begins when the
			-- cinematic is done or skipped, which is exactly this moment. Before this, GF_TutorialStart was
			-- written by nothing, so First Spear never started in ordinary play.
			local okTutorial, TutorialService = pcall(require, game:GetService("ServerScriptService").GF.Services.TutorialService)
			if okTutorial and TutorialService and TutorialService.begin then
				if profile.introWatched == true then
					if workspace:GetAttribute("Tutorial_Active") ~= true then
						pcall(TutorialService.begin, player)
					end
				end
			end
		end)
		-- Archive replay: the only way a veteran sees the intro again is by asking for it.
		local replay = remotes:FindFirstChild("RequestIntroReplay")
		if not replay then
			replay = Instance.new("RemoteEvent")
			replay.Name = "RequestIntroReplay"
			replay.Parent = remotes
		end
		replay.OnServerEvent:Connect(function(player)
			local intro = remotes:FindFirstChild("IntroReplay")
			if not intro then
				intro = Instance.new("RemoteEvent")
				intro.Name = "IntroReplay"
				intro.Parent = remotes
			end
			workspace:SetAttribute("GF_IntroReplayed", (workspace:GetAttribute("GF_IntroReplayed") or 0) + 1)
			intro:FireClient(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		ProfileService.save(player)
		profiles[player.UserId] = nil
		unpersisted[player.UserId] = nil
	end)
	if not RunService:IsStudio() then
		task.spawn(function()
			while true do
				-- L222: low-risk autosave buffered at ~60-90s, not the 120s this was.
				task.wait(75)
				ProfileService.flushAll()
			end
		end)
	end
	game:BindToClose(function()
		ProfileService.flushAll()
	end)
end

-- S10-002 service commendations: milestone recognition for career achievements — kills, missions,
-- extractions. They are NEVER spendable: no cost, deduction or purchase path exists for them.
local COMMENDATIONS = {
	{ id = "first_blood", name = "First Blood", threshold = 1, metric = "kills" },
	{ id = "veteran", name = "Veteran", threshold = 100, metric = "kills" },
	{ id = "extractor", name = "Extractor", threshold = 10, metric = "extractions" },
	{ id = "warhero", name = "War Hero", threshold = 50, metric = "missions" },
}

function ProfileService.awardCommendation(plr: Player, metric: string, count: number): { string }
	local profile = profiles[plr.UserId]
	local newlyEarned = {}
	if not profile then
		return newlyEarned
	end
	profile.commendations = type(profile.commendations) == "table" and profile.commendations or {}
	for _, comm in ipairs(COMMENDATIONS) do
		if comm.metric == metric and count >= comm.threshold then
			local key = "GF_Commendation_" .. comm.id
			if profile.commendations[comm.id] ~= true then
				profile.commendations[comm.id] = true
				table.insert(newlyEarned, comm.name)
				workspace:SetAttribute("GF_CommendationAwarded", plr.Name .. ":" .. comm.name)
			end
			-- Attribute mirrors are for live UI/debug only; the profile map is the durable truth.
			plr:SetAttribute(key, true)
		end
	end
	if #newlyEarned > 0 then
		ProfileService.markDirty(plr)
	end
	return newlyEarned
end

-- Career stats are settled once per mission under the same settledMissions idempotency key as the
-- payout, so retries cannot inflate kills/extraction/mission counts. The counters are persistent
-- account progression and drive the non-spendable service medals above.
function ProfileService.recordCareerProgress(plr: Player, deltas: any): { string }
	local profile = profiles[plr.UserId]
	if not profile or type(deltas) ~= "table" then
		return {}
	end
	profile.careerStats = type(profile.careerStats) == "table" and profile.careerStats or { kills = 0, extractions = 0, missions = 0 }
	local awarded = {}
	for _, metric in { "kills", "extractions", "missions" } do
		local delta = math.max(0, math.floor(tonumber(deltas[metric]) or 0))
		if delta > 0 then
			profile.careerStats[metric] = math.max(0, math.floor(tonumber(profile.careerStats[metric]) or 0)) + delta
			plr:SetAttribute("GF_Career_" .. metric, profile.careerStats[metric])
			for _, name in ipairs(ProfileService.awardCommendation(plr, metric, profile.careerStats[metric])) do
				table.insert(awarded, name)
			end
		end
	end
	if awarded or deltas then
		ProfileService.markDirty(plr)
	end
	return awarded
end

function ProfileService.getCommendations(plr: Player): { string }
	local earned = {}
	local profile = profiles[plr.UserId]
	local persisted = profile and type(profile.commendations) == "table" and profile.commendations or {}
	for _, comm in ipairs(COMMENDATIONS) do
		if persisted[comm.id] == true or plr:GetAttribute("GF_Commendation_" .. comm.id) then
			table.insert(earned, comm.name)
		end
	end
	return earned
end

-- Service Commendations are persistent account progression, not a spendable currency. A qualifying
-- Priority Dispatch assist is counted once per mission id; every five successful assists completes
-- another milestone cycle and pays the small configured Credit award.
function ProfileService.recordDispatchAssist(player: Player, missionId: string?, qualified: boolean): any?
	local profile = profiles[player.UserId]
	if not profile or qualified ~= true or type(missionId) ~= "string" or missionId == "" then
		return nil
	end
	profile.dispatchStats = type(profile.dispatchStats) == "table" and profile.dispatchStats or { qualifyingAssists = 0, claimedMilestones = 0 }
	profile.dispatchAssistMissions = type(profile.dispatchAssistMissions) == "table" and profile.dispatchAssistMissions or {}
	if profile.dispatchAssistMissions[missionId] then
		return {
			duplicate = true,
			assists = tonumber(profile.dispatchStats.qualifyingAssists) or 0,
			milestones = tonumber(profile.dispatchStats.claimedMilestones) or 0,
			credits = 0,
		}
	end
	profile.dispatchAssistMissions[missionId] = os.time()
	local ordered = {}
	for key, at in pairs(profile.dispatchAssistMissions) do
		table.insert(ordered, { key = key, at = tonumber(at) or 0 })
	end
	table.sort(ordered, function(a, b) return a.at < b.at end)
	while #ordered > 30 do
		profile.dispatchAssistMissions[table.remove(ordered, 1).key] = nil
	end
	profile.dispatchStats.qualifyingAssists = (tonumber(profile.dispatchStats.qualifyingAssists) or 0) + 1
	local assists = profile.dispatchStats.qualifyingAssists
	local perMilestone = math.max(1, tonumber(Economy.ServiceCommendation and Economy.ServiceCommendation.assistsPerMilestone) or 5)
	local milestone = assists % perMilestone == 0
	local credits = 0
	if milestone then
		profile.dispatchStats.claimedMilestones = (tonumber(profile.dispatchStats.claimedMilestones) or 0) + 1
		credits = math.max(0, math.floor(tonumber(Economy.ServiceCommendation and Economy.ServiceCommendation.creditsPerMilestone) or 150))
		profile.credits = math.max(0, (tonumber(profile.credits) or 0) + credits)
	end
	ProfileService.markDirty(player)
	player:SetAttribute("GF_DispatchAssists", assists)
	player:SetAttribute("GF_DispatchMilestones", tonumber(profile.dispatchStats.claimedMilestones) or 0)
	workspace:SetAttribute("GF_ServiceCommendation", string.format("%s:%d/%d%s", player.Name, assists % perMilestone, perMilestone, milestone and ":milestone" or ""))
	return {
		duplicate = false,
		assists = assists,
		milestones = tonumber(profile.dispatchStats.claimedMilestones) or 0,
		milestone = milestone,
		credits = credits,
		progress = assists % perMilestone,
		needed = perMilestone,
	}
end

-- S14-019 durable awards: pending mission awards write before they grant — a crash between the
-- two steps recovers on reconnect instead of losing the award or granting it twice. The award
-- key is idempotent: the same mission completion never pays out twice.
local pendingAwards: { [number]: { key: string, credits: number, warCredits: number } } = {}

function ProfileService.awardDurable(plr: Player, missionKey: string, credits: number, warCredits: number)
	local awardKey = missionKey .. "_" .. plr.UserId
	-- idempotency: already-granted keys skip silently
	if plr:GetAttribute("GF_Awarded_" .. awardKey) then
		return false
	end
	-- write intent first — crash recovery reads this
	pendingAwards[plr.UserId] = { key = awardKey, credits = credits, warCredits = warCredits }
	plr:SetAttribute("GF_PendingAward", awardKey)
	-- grant
	plr:SetAttribute("GF_Credits", (plr:GetAttribute("GF_Credits") or 0) + credits)
	plr:SetAttribute("GF_WarCredits", (plr:GetAttribute("GF_WarCredits") or 0) + warCredits)
	plr:SetAttribute("GF_Awarded_" .. awardKey, true)
	plr:SetAttribute("GF_PendingAward", nil)
	pendingAwards[plr.UserId] = nil
	return true
end

function ProfileService.recoverPendingAwards(plr: Player)
	-- reconnect recovery: a pending award means the crash happened mid-grant — the idempotency
	-- key decides whether to complete or skip
	local pendingKey = plr:GetAttribute("GF_PendingAward")
	if pendingKey and not plr:GetAttribute("GF_Awarded_" .. pendingKey) then
		workspace:SetAttribute("GF_AwardRecovered", plr.Name)
	end
end

return ProfileService

