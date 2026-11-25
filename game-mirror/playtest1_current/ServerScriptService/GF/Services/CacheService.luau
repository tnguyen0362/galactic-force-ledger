--!nonstrict
-- Cache opening. A cache yields its tier's count of independent Augments drawn from the category pools
-- at the tier's rarity weights, duplicate archetypes remain valid because each result is a distinct item instance. Each cache is claimed once.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Caches = require(ReplicatedStorage.GF.Shared.Configs.Caches)
local Augments = require(ReplicatedStorage.GF.Shared.Configs.Augments)
local AugmentService = require(script.Parent.AugmentService)
local Enemies = require(ReplicatedStorage.GF.Shared.Configs.Enemies)

local CacheService = {}

local function profileOf(player: Player)
	local ProfileService = require(script.Parent.ProfileService)
	return ProfileService.get(player)
end

-- S11-030: cache outcomes resolve through a dedicated Random object seeded from server-clock entropy
-- rather than the process-global math.random stream - the stronger platform primitive, since the
-- global stream's seed is shared and influenced by unrelated callers. Deterministic only when a test
-- passes an rng explicitly.
local cacheRng = Random.new((os.time() + math.floor(os.clock() * 1e6)) % 2147483647)
local function defaultRng()
	return cacheRng:NextNumber()
end

function CacheService.roll(tierId: string, owned: { [string]: boolean }?, rng: (number) -> number?, categoryChoice: string?, weightsOverride: { [string]: number }?): { any }
	local tier = Caches.get(tierId)
	if not tier then
		return {}
	end
	local picker = rng or defaultRng
	if weightsOverride then
		tier = table.clone(tier)
		tier.weights = weightsOverride
	end
	local picked = {}
	for _ = 1, tier.augments do
		local rarity = Caches.rollRarity(tier, picker)
		local category = categoryChoice
		if type(category) ~= "string" or not Augments.ByCategory[category] then
			category = Augments.Categories[math.floor(picker() * #Augments.Categories) + 1]
		end
		-- Duplicate archetypes are legal and necessary for fusion. Rarity restricts the candidate set;
		-- category is the player's opening choice when one is supplied.
		local pool = {}
		for _, entry in ipairs(Augments.forCategory(category)) do
			if entry.rarity == rarity then
				table.insert(pool, entry)
			end
		end
		if #pool == 0 then
			for _, entry in ipairs(Augments.forCategory(category)) do
				table.insert(pool, entry)
			end
		end
		if #pool == 0 then
			for _, other in ipairs(Augments.Categories) do
				for _, entry in ipairs(Augments.forCategory(other)) do
					if entry.rarity == rarity then
						table.insert(pool, entry)
					end
				end
			end
		end
		if #pool > 0 then
			local entry = pool[math.floor(picker() * #pool) + 1]
			table.insert(picked, { id = entry.id, rarity = entry.rarity, category = entry.category })
		end
	end
	return picked
end

-- Inventory. A cache used to roll the instant it was awarded, so a player never saw one and could not
-- choose when to open it. Awards now stack per tier; opening is an explicit action.
function CacheService.grantToInventory(player: Player, tierId: string, sourceId: string?): boolean
	local profile = profileOf(player)
	local tier = Caches.get(tierId)
	if not profile or not tier then
		return false
	end
	profile.caches = profile.caches or {}
	profile.caches[tier.id] = (profile.caches[tier.id] or 0) + 1
	-- Per-cache identity (S11-031). Counts alone cannot answer "which cache was this", and a count is what
	-- lets a disconnect re-roll the same cache. Each grant now carries uid/tier/source/timestamp.
	profile.cacheInstances = profile.cacheInstances or {}
	local dropDifficulty, dropBoss = nil, nil
	local enemyDef = type(sourceId) == "string" and Enemies.ById and Enemies.ById[sourceId] or nil
	if enemyDef then
		dropBoss = enemyDef.tier == "Boss" or nil
	end
	-- Difficulty is recorded for every mission-context grant (enemy drops AND completion caches):
	-- the rarity mix of both is difficulty-indexed by the spec source tables.
	do
		local ok, mission = pcall(function()
			return require(script.Parent.State).getMission()
		end)
		if ok and mission and mission.difficulty then
			dropDifficulty = mission.difficulty
		elseif enemyDef then
			dropDifficulty = "Normal"
		end
	end
	table.insert(profile.cacheInstances, {
		uid = "cache_" .. string.lower(string.gsub(HttpService:GenerateGUID(false), "-", "")),
		tier = tier.id,
		source = tostring(sourceId or "manual"),
		difficulty = dropDifficulty,
		boss = enemyDef and enemyDef.tier == "Boss" or nil,
		obtainedAt = os.time(),
	})
	while #profile.cacheInstances > 50 do
		table.remove(profile.cacheInstances, 1)
	end
	require(script.Parent.ProfileService).markDirty(player)
	workspace:SetAttribute("GF_CacheHeld", string.format("%s:%d", tier.id, profile.caches[tier.id]))
	workspace:SetAttribute("GF_CacheLastSource", tostring(sourceId or "manual"))
	return true
end

function CacheService.openFromInventory(player: Player, tierId: string, categoryChoice: string?): { any }
	local profile = profileOf(player)
	local tier = Caches.get(tierId)
	if not profile or not tier then
		return {}
	end
	CacheService.reconcileProfile(profile)
	profile.caches = profile.caches or {}
	local held = profile.caches[tier.id] or 0
	if held <= 0 then
		workspace:SetAttribute("GF_CacheRejected", "no " .. tier.id .. " cache held")
		return {}
	end
	local AugSvc = require(script.Parent.AugmentService)
	local capacity = tonumber(profile.augmentCapacity) or AugSvc.BASELINE_CAPACITY
	local ownedCount = AugSvc.inventoryCount(profile)
	if ownedCount >= capacity then
		workspace:SetAttribute("GF_CacheRejected", string.format("inventory full %d/%d", ownedCount, capacity))
		return {}
	end
	profile.cacheInstances = profile.cacheInstances or {}
	local instanceIndex, instance = nil, nil
	for i, inst in ipairs(profile.cacheInstances) do
		if inst.tier == tier.id then
			instanceIndex, instance = i, inst
			break
		end
	end
	-- Legacy profiles can have tier counts without matching instances. Keep the old count usable, but give
	-- the open a stable synthetic receipt id so it is still deduplicated.
	local instanceUid = instance and tostring(instance.uid) or string.format("legacy-%s-%d", tier.id, held)
	profile.cacheOpenJournal = profile.cacheOpenJournal or {}
	local journal = profile.cacheOpenJournal[instanceUid]
	local rolled = nil
	if type(journal) == "table" and type(journal.rolled) == "table" then
		-- A retry after disconnect/crash must reuse the committed draw, never reroll it.
		rolled = journal.rolled
	else
		local weightsOverride = nil
		if instance and instance.difficulty then
			if type(instance.source) == "string" and Enemies.ById and Enemies.ById[instance.source] then
				weightsOverride = CacheService.enemyDropWeights(instance.source, instance.difficulty)
			elseif instance.source == "mission" then
				weightsOverride = CacheService.missionSourceWeights(instance.difficulty)
			end
			if not weightsOverride then
				weightsOverride = CacheService.scaledWeights(tier.id, instance.difficulty, instance.boss == true)
			end
		end
		rolled = CacheService.roll(tier.id, profile.ownedAugments, nil, categoryChoice, weightsOverride)
		if #rolled == 0 then
			workspace:SetAttribute("GF_CacheRejected", "nothing left to roll")
			return {}
		end
		-- First mission Rare guarantee: the first successful mission cache contains at least one Rare+ item.
		if instance and instance.guaranteedRare == true then
			local hasRarePlus = false
			for _, item in ipairs(rolled) do
				if item.rarity ~= "Common" then
					hasRarePlus = true
					break
				end
			end
			if not hasRarePlus then
				for _, other in ipairs(Augments.Categories) do
					local rarePool = {}
					for _, entry in ipairs(Augments.forCategory(other)) do
						if entry.rarity == "Rare" then
							table.insert(rarePool, entry)
						end
					end
					if #rarePool > 0 then
						local entry = rarePool[math.floor(defaultRng() * #rarePool) + 1]
						rolled[1] = { id = entry.id, rarity = entry.rarity, category = entry.category, guaranteedRare = true }
						break
					end
				end
			end
		end
		-- Hydrate the draw before the durable commit: item UID and traits are part of the receipt, so a
		-- crash after commit can recover exactly the same results instead of losing or duplicating them.
		for _, item in ipairs(rolled) do
			item.uid = AugSvc.newUid()
			local def = Augments.get(item.id)
			item.traits = def and Augments.rollTraits(def) or {}
		end
		journal = {
			uid = instanceUid,
			tier = tier.id,
			category = categoryChoice,
			source = instance and tostring(instance.source) or "inventory",
			createdAt = os.time(),
			status = "committed",
			rolled = rolled,
			consumed = false,
		}
		profile.cacheOpenJournal[instanceUid] = journal
	end
	if journal.consumed ~= true then
		if instanceIndex then
			table.remove(profile.cacheInstances, instanceIndex)
		end
		profile.caches[tier.id] = math.max(0, held - 1)
		journal.consumed = true
	end
	-- Critical receipt first. If the save fails, roll back the in-memory consumption and leave the cache
	-- closed rather than silently losing it; if it succeeds, recovery can materialize the exact results.
	local ProfileService = require(script.Parent.ProfileService)
	local saved = ProfileService.save(player)
	if not saved then
		if journal.consumed == true then
			profile.caches[tier.id] = held
			if instance and instanceIndex then
				table.insert(profile.cacheInstances, math.min(instanceIndex, #profile.cacheInstances + 1), instance)
			end
			journal.consumed = false
		end
		workspace:SetAttribute("GF_CacheRejected", "receipt save failed")
		return {}
	end
	local results = CacheService.open(player, tier.id, instanceUid, rolled)
	if #results > 0 then
		journal.status = "completed"
		journal.completedAt = os.time()
		ProfileService.markDirty(player)
		ProfileService.save(player)
	end
	workspace:SetAttribute("GF_CacheHeld", string.format("%s:%d", tier.id, profile.caches[tier.id]))
	return results
end

-- Bulk opening (S11-035): bounded to 10 caches per action, and the free space is calculated BEFORE any draw
-- so a partially-fitting batch stops instead of granting some and eating the rest.
function CacheService.openMany(player: Player, tierId: string, count: number?, categoryChoice: string?): number
	local profile = profileOf(player)
	local tier = Caches.get(tierId)
	if not profile or not tier then
		return 0
	end
	local AugSvc = require(script.Parent.AugmentService)
	local capacity = tonumber(profile.augmentCapacity) or AugSvc.BASELINE_CAPACITY
	local ownedCount = 0
	ownedCount = AugSvc.inventoryCount(profile)
	local space = math.max(0, capacity - ownedCount)
	profile.caches = profile.caches or {}
	local held = profile.caches[tier.id] or 0
	local wanted = math.clamp(tonumber(count) or 1, 1, 10)
	local budget = math.min(wanted, held, space)
	local opened = 0
	for _ = 1, budget do
		local rolled = CacheService.openFromInventory(player, tier.id, categoryChoice)
		if #rolled == 0 then
			break
		end
		opened += 1
	end
	workspace:SetAttribute("GF_CacheBulk", string.format("%s wanted=%d opened=%d held=%d space=%d", tier.id, wanted, opened, profile.caches[tier.id] or 0, space))
	return opened
end

function CacheService.open(player: Player, tierId: string, sourceId: string?, preRolled: { any }?): { any }
	local profile = profileOf(player)
	if not profile then
		return {}
	end
	local rolled = preRolled or CacheService.roll(tierId, profile.ownedAugments)
	-- Capacity gate (S11-033): block OPENING only when the result cannot fit. Deployment and receiving a
	-- cache reward are deliberately not gated - a full inventory must never strand a squad or deny a cache.
	local AugSvc = require(script.Parent.AugmentService)
	local capacity = tonumber(profile.augmentCapacity) or AugSvc.BASELINE_CAPACITY
	local ownedCount = 0
	ownedCount = AugSvc.inventoryCount(profile)
	local inventory = AugSvc.ensureInventory(profile)
	local missing = 0
	for _, item in ipairs(rolled) do
		if type(item.uid) ~= "string" or inventory[item.uid] == nil then
			missing += 1
		end
	end
	if ownedCount + missing > capacity then
		workspace:SetAttribute("GF_CacheBlocked", string.format("full %d/%d needs %d", ownedCount, capacity, missing))
		return {}
	end
	for _, item in ipairs(rolled) do
		local uid = AugmentService.grantAugment(profile, item.id, { source = sourceId or "cache", uid = item.uid, traits = item.traits })
		item.uid = uid
	end
	profile.cachesOpened = (profile.cachesOpened or 0) + 1
	local ProfileService = require(script.Parent.ProfileService)
	ProfileService.markDirty(player)
	workspace:SetAttribute("GF_CacheOpened", string.format("%s:%d:%s", tierId, #rolled, tostring(sourceId or "manual")))
	workspace:SetAttribute("GF_CacheOpens", (workspace:GetAttribute("GF_CacheOpens") or 0) + 1)
	workspace:SetAttribute("GF_CacheLastSource", tostring(sourceId or "manual"))
	local ev = ReplicatedStorage.GF.Remotes:FindFirstChild("MissionEvent")
	if ev then
		local names = {}
		for _, item in ipairs(rolled) do
			table.insert(names, item.id)
		end
		ev:FireAllClients({ text = string.format("%s cache: %s", tierId, #names > 0 and table.concat(names, ", ") or "nothing new"), kind = "loot" })
	end
	return rolled
end

-- Guaranteed mission cache: called from objective completion so a successful primary always pays.
function CacheService.grantMission(tierId: string)
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		local profile = profileOf(player)
		local firstMission = profile ~= nil and profile.firstMissionBonusClaimed ~= true
		if CacheService.grantToInventory(player, tierId, "mission") and firstMission and profile then
			profile.firstMissionBonusClaimed = true
			-- First completed mission bonus (GOAL §10): guaranteed Rare cache plus a one-time 200 Credits.
			profile.credits = (profile.credits or 0) + 200
			workspace:SetAttribute("GF_FirstMissionCredits", player.Name)
			local instances = profile.cacheInstances
			local inst = instances and instances[#instances]
			if inst and inst.source == "mission" then
				inst.guaranteedRare = true
			end
			require(script.Parent.ProfileService).markDirty(player)
			workspace:SetAttribute("GF_FirstMissionRare", player.Name)
		end
	end
end

-- Enemy drops. Spec chances: infantry 1%, heavy 4%, Commander 7%, bosses 100%. The per-mission cap of
-- three excludes boss drops. GF_CacheDropForce makes every eligible kill drop, for tests only.
local MISSION_CAP = 3
local missionDrops = 0

-- Single source of truth for difficulty -> cache tier; the objective no longer maps it separately.
	-- True odds for a tier (S11-027/S11-028): per-draw share from the same weight table rollRarity consumes, plus
	-- the at-least-one probability across the tier's own draw count using 1-(1-p)^n. Published, not guessed, so
	-- the displayed number cannot drift from the table that actually decides outcomes.
	function CacheService.oddsFor(tierId: string)
		local tier = Caches.get(tierId)
		if not tier or type(tier.weights) ~= "table" then
			return nil
		end
		local total = 0
		for _, w in pairs(tier.weights) do
			total += tonumber(w) or 0
		end
		if total <= 0 then
			return nil
		end
		local draws = tonumber(tier.augments) or 1
		local perDraw, atLeastOne = {}, {}
		local sum = 0
		for rarity, w in pairs(tier.weights) do
			local p = (tonumber(w) or 0) / total
			perDraw[rarity] = p * 100
			sum += p
			atLeastOne[rarity] = (1 - (1 - p) ^ draws) * 100
		end
		return { tier = tier.id, draws = draws, perDraw = perDraw, atLeastOne = atLeastOne, sumPercent = sum * 100,
			-- The drop chance this tier's caches actually roll at, per enemy class (S11-027 disclosure).
			dropChance = tier.enemyChance }
	end
	function CacheService.tierForDifficulty(difficulty: string?): string
	if difficulty == "Normal" then
		return "Rare"
	elseif difficulty == "Hard" then
		return "Epic"
	elseif difficulty == "Extreme" then
		return "Legendary"
	end
	return "Common"
end

local function missionTier(): string
	local difficulty = "Normal"
	local ok, mission = pcall(function()
		return require(script.Parent.State).getMission()
	end)
	if ok and type(mission) == "table" and type(mission.difficulty) == "string" then
		difficulty = mission.difficulty
	end
	if difficulty == "Normal" then
		return "Rare"
	elseif difficulty == "Hard" then
		return "Epic"
	elseif difficulty == "Extreme" then
		return "Legendary"
	end
	return "Common"
end

-- GOAL §11 L181: enemy-drop caches on non-Normal difficulties scale non-Common weights
-- (Easy .65, Hard 1.35, Extreme 1.7) before renormalization; boss drops never roll Common.
local DROP_SCALE = { Easy = 0.65, Normal = 1, Hard = 1.35, Extreme = 1.7 }
-- Spec drop tables for enemy-source caches (S11-016..019): the rarity mix of an enemy-dropped cache
-- is governed by the enemy class, not the mission cache tier. Values are the Normal baseline; other
-- difficulties scale non-Common weights by DROP_SCALE and renormalize.
local ENEMY_DROP_WEIGHTS = {
	infantry = { Common = 85, Rare = 14, Epic = 1, Legendary = 0 },
	elite = { Common = 55, Rare = 35, Epic = 9, Legendary = 1 },
	BastionWalker = { Common = 0, Rare = 70, Epic = 28, Legendary = 2 },
	HighMarshalVeyr = { Common = 0, Rare = 40, Epic = 50, Legendary = 10 },
}

local function enemyDropClass(enemyId: string): string?
	local def = Enemies.ById and Enemies.ById[enemyId]
	if not def then
		return nil
	end
	if enemyId == "BastionWalker" or enemyId == "HighMarshalVeyr" then
		return enemyId
	end
	if def.tier == "Elite" or def.tier == "Boss" then
		return "elite"
	end
	return "infantry"
end

-- Spec source tables for mission-completion caches (S11-012..015): the rarity mix keys off the
-- mission difficulty, not the cache tier's own table.
local MISSION_SOURCE_WEIGHTS = {
	Easy = { Common = 80, Rare = 18, Epic = 2, Legendary = 0 },
	Normal = { Common = 65, Rare = 29, Epic = 5.5, Legendary = 0.5 },
	Hard = { Common = 40, Rare = 43, Epic = 15, Legendary = 2 },
	Extreme = { Common = 20, Rare = 43, Epic = 30, Legendary = 7 },
}

function CacheService.missionSourceWeights(difficulty: string?): { [string]: number }?
	local w = MISSION_SOURCE_WEIGHTS[tostring(difficulty or "Normal")]
	if not w then
		return nil
	end
	return table.clone(w)
end

function CacheService.enemyDropWeights(enemyId: string, difficulty: string?): { [string]: number }?
	local class = enemyDropClass(enemyId)
	local base = class and ENEMY_DROP_WEIGHTS[class] or nil
	if not base then
		return nil
	end
	local scale = DROP_SCALE[tostring(difficulty or "Normal")] or 1
	local scaled, total = {}, 0
	for rarity, weight in pairs(base) do
		local w = tonumber(weight) or 0
		if rarity ~= "Common" then
			w = w * scale
		end
		scaled[rarity] = w
		total += w
	end
	if total <= 0 then
		return nil
	end
	local out = {}
	for rarity, weight in pairs(scaled) do
		out[rarity] = weight / total * 100
	end
	return out
end

function CacheService.scaledWeights(tierId: string, difficulty: string?, boss: boolean?): { [string]: number }?
	local tier = Caches.get(tierId)
	if not tier or type(tier.weights) ~= "table" then
		return nil
	end
	local scale = DROP_SCALE[tostring(difficulty or "Normal")] or 1
	local out = {}
	for rarity, weight in pairs(tier.weights) do
		local w = tonumber(weight) or 0
		if rarity ~= "Common" and scale ~= 1 then
			w = w * scale
		end
		if boss == true and rarity == "Common" then
			w = 0
		end
		out[rarity] = w
	end
	return out
end

function CacheService.chanceFor(def: any): number
	local tier = Caches.get(missionTier())
	local chance = tier and tier.enemyChance or { infantry = 0.01, heavy = 0.04, commander = 0.07 }
	if def and def.tier == "Boss" then
		return 1
	end
	if def and def.id == "Officer" then
		return chance.commander or 0.07
	end
	if def and def.tier == "Elite" then
		return chance.heavy or 0.04
	end
	return chance.infantry or 0.01
end

function CacheService.onEnemyKilled(model: Model, killer: Player?)
	local def = model and Enemies.ById and Enemies.ById[model.Name] or nil
	if not def then
		return false
	end
	local boss = def.tier == "Boss"
	if not boss and missionDrops >= MISSION_CAP then
		workspace:SetAttribute("GF_CacheDropCapped", true)
		return false
	end
	local forced = workspace:GetAttribute("GF_CacheDropForce") == true
	if not forced and defaultRng() > CacheService.chanceFor(def) then
		return false
	end
	if not boss then
		missionDrops += 1
	end
	workspace:SetAttribute("GF_CachesDropped", missionDrops)
	local target = killer or game:GetService("Players"):GetPlayers()[1]
	if target then
		CacheService.grantToInventory(target, missionTier(), def.id)
	end
	return true
end

-- Boss drops are driven from the objective tracker instead of the boss module: an attribute-set kill
-- was measured to complete the objective without the boss's own death handler paying out.
function CacheService.onBossKilled(model: Model?)
	local def = model and Enemies.ById and Enemies.ById[model.Name] or nil
	if not def or def.tier ~= "Boss" then
		return false
	end
	local target = game:GetService("Players"):GetPlayers()[1]
	if target then
		CacheService.grantToInventory(target, missionTier(), def.id)
	end
	workspace:SetAttribute("GF_BossCacheDropped", def.id)
	return true
end

function CacheService.resetMission()
	missionDrops = 0
	workspace:SetAttribute("GF_CachesDropped", 0)
	workspace:SetAttribute("GF_CacheDropCapped", false)
end

-- Materialize committed cache receipts exactly once. This is intentionally idempotent: the pre-generated
-- item UID is the dedup key, so a crash after granting some results cannot duplicate them on recovery.
function CacheService.reconcileProfile(profile): number
	if type(profile) ~= "table" or type(profile.cacheOpenJournal) ~= "table" then
		return 0
	end
	local AugSvc = require(script.Parent.AugmentService)
	local recovered = 0
	for journalUid, journal in pairs(profile.cacheOpenJournal) do
		if type(journal) == "table" and journal.status == "committed" and type(journal.rolled) == "table" then
			local any = false
			for _, item in ipairs(journal.rolled) do
				local uid = AugSvc.grantAugment(profile, item.id, { source = "recovered:" .. tostring(journalUid), uid = item.uid, traits = item.traits })
				any = any or uid ~= nil
			end
			if any then
				journal.status = "completed"
				journal.completedAt = os.time()
				recovered += 1
			end
		end
	end
	-- Keep enough completed receipts for audit/recovery without letting DataStore profiles grow forever.
	local completed = {}
	for key, journal in pairs(profile.cacheOpenJournal) do
		if type(journal) == "table" and journal.status == "completed" then
			table.insert(completed, { key = key, at = tonumber(journal.completedAt) or tonumber(journal.createdAt) or 0 })
		end
	end
	table.sort(completed, function(a, b) return a.at < b.at end)
	while #completed > 50 do
		local victim = table.remove(completed, 1)
		profile.cacheOpenJournal[victim.key] = nil
	end
	if recovered > 0 then
		workspace:SetAttribute("GF_CacheRecovered", recovered)
	end
	return recovered
end

function CacheService.start()
	local Players = game:GetService("Players")
	local function recover(player)
		task.delay(2, function()
			if not player.Parent then return end
			local profile = profileOf(player)
			local recovered = CacheService.reconcileProfile(profile)
			if recovered > 0 then
				require(script.Parent.ProfileService).markDirty(player)
				require(script.Parent.ProfileService).save(player)
			end
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do recover(player) end
	Players.PlayerAdded:Connect(recover)
	local r = ReplicatedStorage.GF.Remotes:FindFirstChild("SetLoadout")
	if r then
		r.OnServerEvent:Connect(function(player, payload)
			if type(payload) ~= "table" or payload.action ~= "openCache" then
				return
			end
			if workspace:GetAttribute("GF_TestHooks") ~= true then
				return
			end
			CacheService.open(player, tostring(payload.tier or "Common"), "test")
		end)
	end
end

return CacheService

