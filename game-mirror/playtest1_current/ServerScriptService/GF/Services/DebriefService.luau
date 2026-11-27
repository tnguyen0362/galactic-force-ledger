--!strict
-- DebriefService: authoritative after-action result packaging and lobby-arrival delivery.
--
-- The mission server owns settlement. This module captures the post-settlement truth, reduces it
-- to a compact teleport-safe package, and (when this module is also running in the lobby place)
-- expands only the returning player's own row back into the public MissionComplete payload.
-- Teleport data is display evidence, never an award grant: Credits/XP/salvage are committed in the
-- mission server before the return teleport is attempted.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local ProfileService = require(script.Parent.ProfileService)
local State = require(script.Parent.State)

local DebriefService = {}

local CACHE_TTL = 1800
local PACKAGE_TAG = "gfdb"
local PACKAGE_VERSION = 1
local TELEPORT_SOFT_LIMIT = 3500 -- keep margin below the platform teleport-data cap

local latestByUserId: { [number]: { at: number, payload: any } } = {}
local started = false
local wired = false

local function bool01(value: any): number
	return value == true and 1 or 0
end

local function truthy01(value: any): boolean
	return value == true or value == 1
end

local function finite(value: any, fallback: number?): number
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return fallback or 0
	end
	return n
end

local function copyTable(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in pairs(value) do
		out[key] = copyTable(child)
	end
	return out
end

local function salvageCopy(source: any): { scrap: number, energyCells: number, militaryTechnology: number }
	source = type(source) == "table" and source or {}
	return {
		scrap = math.floor(finite(source.scrap)),
		energyCells = math.floor(finite(source.energyCells)),
		militaryTechnology = math.floor(finite(source.militaryTechnology)),
	}
end

local function remoteEvent(name: string): RemoteEvent?
	local gf = ReplicatedStorage:FindFirstChild("GF")
	local remotes = gf and gf:FindFirstChild("Remotes")
	local found = remotes and remotes:FindFirstChild(name)
	if found and found:IsA("RemoteEvent") then
		return found
	end
	return nil
end

local function remoteFunction(name: string): RemoteFunction?
	local gf = ReplicatedStorage:FindFirstChild("GF")
	local remotes = gf and gf:FindFirstChild("Remotes")
	local found = remotes and remotes:FindFirstChild(name)
	if found and found:IsA("RemoteFunction") then
		return found
	end
	return nil
end

local function sharedConfig(name: string): any
	local ok, result = pcall(function()
		return require(ReplicatedStorage.GF.Shared.Configs[name])
	end)
	return ok and result or nil
end

local function economy(): any
	return sharedConfig("Economy") or { RankXp = { [1] = 0 }, MaxRank = 30, Grenades = {} }
end

-- Next-unlock is data-derived rather than hardcoded: weapons, abilities, armor, grenades and
-- difficulty bands all carry unlockRank in shared configs. The nearest lock above the player's
-- post-settlement rank is the debrief's forward-looking beat.
local function nextUnlockFor(rank: number): any?
	local entries = {}
	local function addRows(rows: any, kind: string)
		if type(rows) ~= "table" then
			return
		end
		for _, row in ipairs(rows) do
			if type(row) == "table" and type(row.unlockRank) == "number" then
				table.insert(entries, {
					kind = kind,
					id = tostring(row.id or row.displayName or "unknown"),
					displayName = tostring(row.displayName or row.id or "Unknown unlock"),
					rank = row.unlockRank,
					cost = math.floor(finite(row.cost)),
				})
			end
		end
	end
	local Weapons = sharedConfig("Weapons")
	local Abilities = sharedConfig("Abilities")
	local Armor = sharedConfig("Armor")
	local Difficulties = sharedConfig("Difficulties")
	addRows(Weapons and Weapons.List, "weapon")
	addRows(Abilities and (Abilities.List or Abilities), "ability")
	addRows(Armor and (Armor.List or Armor), "armor")
	addRows(Difficulties and (Difficulties.List or Difficulties), "difficulty")
	addRows(economy().Grenades, "grenade")
	table.sort(entries, function(a, b)
		if a.rank == b.rank then
			if a.cost == b.cost then
				return a.displayName < b.displayName
			end
			return a.cost < b.cost
		end
		return a.rank < b.rank
	end)
	for _, entry in ipairs(entries) do
		if entry.rank > rank then
			return entry
		end
	end
	return nil
end

-- Capture the mutable profile facts that RewardsService is about to change. The boss report is
-- copied because the payout flow consumes profile.lastBossReward while building its legacy payload.
function DebriefService.captureBefore(player: Player): any
	local profile = ProfileService.get(player)
	local live = State.get(player)
	local weaponId = live and live.weaponId or nil
	local masteryBefore = 0
	if profile and weaponId and type(profile.weaponMastery) == "table" then
		masteryBefore = math.floor(finite(profile.weaponMastery[weaponId]))
	end
	local pendingMastery = 0
	local pendingByWeapon = {}
	if live and type(live.pendingMastery) == "table" then
		for pendingWeaponId, amount in pairs(live.pendingMastery) do
			pendingByWeapon[pendingWeaponId] = finite(amount)
			pendingMastery += finite(amount)
		end
	end
	return {
		credits = profile and math.floor(finite(profile.credits)) or 0,
		xp = profile and math.floor(finite(profile.xp)) or 0,
		rank = profile and math.floor(finite(profile.rank, 1)) or 1,
		warCredits = profile and math.floor(finite(profile.warCredits)) or 0,
		salvage = salvageCopy(profile and profile.salvage),
		boss = profile and copyTable(profile.lastBossReward) or nil,
		weaponId = weaponId,
		masteryXp = masteryBefore,
		pendingMastery = math.floor(pendingMastery),
		pendingMasteryByWeapon = pendingByWeapon,
		joinedLate = live and live.joinedLate == true or false,
	}
end

local function rankProgress(profile: any): (number, number, number)
	local econ = economy()
	local xp = profile and math.floor(finite(profile.xp)) or 0
	local rank = profile and math.floor(finite(profile.rank, 1)) or 1
	local floorXp = finite(econ.RankXp and econ.RankXp[rank])
	local nextXp = econ.RankXp and econ.RankXp[rank + 1]
	if type(nextXp) ~= "number" then
		return xp, 0, math.max(0, xp - floorXp)
	end
	return xp, math.max(0, nextXp - xp), math.max(0, xp - floorXp)
end

local function masteryAfterFallback(profile: any, weaponId: string, fallback: number): number
	if profile and type(profile.weaponMastery) == "table" then
		return math.floor(finite(profile.weaponMastery[weaponId], fallback))
	end
	return math.floor(finite(fallback))
end

-- Expand one settlement into the rich internal debrief row. `payout` is the table returned by
-- RewardsService.grant; context carries mission-level truth captured before mission teardown.
function DebriefService.buildPlayerResult(player: Player, payout: any, before: any, context: any): any
	payout = type(payout) == "table" and payout or {}
	before = type(before) == "table" and before or {}
	context = type(context) == "table" and context or {}
	local profile = ProfileService.get(player)
	local live = State.get(player)
	local rank = profile and math.floor(finite(profile.rank, 1)) or math.floor(finite(before.rank, 1))
	local xpTotal, xpForNext, xpInto = rankProgress(profile)
	local weaponId = before.weaponId or (live and live.weaponId)
	local mastery = nil
	if weaponId then
		local masteryXp = masteryAfterFallback(profile, weaponId, before.masteryXp)
		mastery = {
			weaponId = weaponId,
			xp = masteryXp,
			level = ProfileService.masteryLevel(player, weaponId),
			earned = context.objectiveComplete == true and math.floor(finite(type(before.pendingMasteryByWeapon) == "table" and before.pendingMasteryByWeapon[weaponId] or before.pendingMastery)) or 0,
		}
	end
	local statuses = type(context.participantStatuses) == "table" and context.participantStatuses or {}
	local userId = player.UserId
	local extracted = type(context.extractedUserIds) == "table" and context.extractedUserIds[userId] == true
	local row = {
		v = PACKAGE_VERSION,
		debriefId = tostring(context.missionId or "mission") .. ":" .. tostring(userId),
		transactionId = "settle:" .. tostring(context.missionId or "mission"),
		missionId = tostring(context.missionId or "unknown"),
		template = tostring(context.template or "UNKNOWN"),
		difficulty = tostring(context.difficulty or "Normal"),
		seed = math.floor(finite(context.seed)),
		userId = userId,
		playerName = player.Name,
		success = context.extractionSuccess == true,
		extractionSuccess = context.extractionSuccess == true,
		objectiveComplete = context.objectiveComplete == true,
		primaryComplete = context.objectiveComplete == true,
		salvageSecured = context.salvageSecured == true,
		carriedLost = context.carriedLost == true,
		emergency = context.emergency == true,
		endReason = context.endReason,
		fullSquad = context.fullSquad == true,
		extracted = extracted,
		participantStatus = statuses[userId] or (extracted and "extracted" or "participating"),
		participationMetrics = {
			status = statuses[userId] or (extracted and "extracted" or "participating"),
			extracted = extracted,
			lateJoin = before.joinedLate == true,
			activeEligibleCount = math.floor(finite(context.eligibleCount)),
			participantCount = math.floor(finite(context.participantCount)),
		},
		aboardCount = math.floor(finite(context.aboardCount)),
		eligibleCount = math.floor(finite(context.eligibleCount)),
		participantCount = math.floor(finite(context.participantCount)),
		credits = math.floor(finite(payout.credits)),
		xp = math.floor(finite(payout.xp)),
		baseCredits = math.floor(finite(payout.baseCredits, finite(payout.credits))),
		baseXp = math.floor(finite(payout.baseXp, finite(payout.xp))),
		bonusCredits = math.floor(finite(payout.bonusCredits)),
		bonusXp = math.floor(finite(payout.bonusXp)),
		killXp = math.floor(finite(payout.killXp)),
		salvage = salvageCopy(payout.salvage),
		baseSalvage = salvageCopy(payout.baseSalvage or context.carriedSalvage),
		bonusSalvage = salvageCopy(payout.bonusSalvage),
		carriedSalvage = salvageCopy(context.carriedSalvage),
		rank = rank,
		rankBefore = math.floor(finite(before.rank, rank)),
		rankUps = math.max(0, math.floor(tonumber(workspace:GetAttribute("GF_ForceRankUps")) or (rank - math.floor(finite(before.rank, rank))))),
		xpTotal = xpTotal,
		xpForNextRank = xpForNext,
		xpIntoRank = xpInto,
		creditsTotal = profile and math.floor(finite(profile.credits)) or 0,
		firstMissionBonusCredits = math.max(0, (profile and math.floor(finite(profile.credits)) or 0) - math.floor(finite(before.credits)) - math.floor(finite(payout.credits))),
		warCredits = profile and math.floor(finite(profile.warCredits)) or 0,
		warCreditsEarned = math.max(0, (profile and math.floor(finite(profile.warCredits)) or 0) - math.floor(finite(before.warCredits))),
		nextUnlock = nextUnlockFor(rank),
		mastery = mastery,
		boss = before.boss,
		lateJoin = before.joinedLate == true,
		-- Legacy consumers expect warContribution to be the numeric per-mission point contribution.
		-- The richer operation/region context travels additively under warDetail.
		warContribution = math.floor(finite((type(context.warContribution) == "table" and context.warContribution.points) or context.warContribution)),
		warDetail = copyTable(context.warContribution or {}),
		completedAt = math.floor(finite(context.completedAt, os.time())),
	}
	if payout.duplicate == true then
		row.duplicateSettlement = true
	end
	return row
end

local function compactSalvage(value: any): any
	local s = salvageCopy(value)
	return { sc = s.scrap, ec = s.energyCells, mt = s.militaryTechnology }
end

local function expandSalvage(value: any): any
	value = type(value) == "table" and value or {}
	return {
		scrap = math.floor(finite(value.scrap or value.sc)),
		energyCells = math.floor(finite(value.energyCells or value.ec)),
		militaryTechnology = math.floor(finite(value.militaryTechnology or value.mt)),
	}
end

local function compactResult(row: any): any
	local out = {
		u = row.userId,
		pn = row.playerName,
		tx = row.transactionId,
		cr = row.credits,
		xp = row.xp,
		bc = row.baseCredits,
		bx = row.baseXp,
		boc = row.bonusCredits,
		box = row.bonusXp,
		kx = row.killXp,
		s = compactSalvage(row.salvage),
		bs = compactSalvage(row.baseSalvage),
		bos = compactSalvage(row.bonusSalvage),
		rk = row.rank,
		rb = row.rankBefore,
		ru = row.rankUps,
		xt = row.xpTotal,
		xn = row.xpForNextRank,
		xi = row.xpIntoRank,
		ct = row.creditsTotal,
		fmb = row.firstMissionBonusCredits,
		wc = row.warCredits,
		we = row.warCreditsEarned,
		ex = bool01(row.extracted),
		st = row.participantStatus,
		lj = bool01(row.lateJoin),
	}
	if row.mastery then
		out.m = { id = row.mastery.weaponId, xp = row.mastery.xp, lv = row.mastery.level, e = row.mastery.earned }
	end
	if row.nextUnlock then
		out.nu = { k = row.nextUnlock.kind, id = row.nextUnlock.id, n = row.nextUnlock.displayName, r = row.nextUnlock.rank, c = row.nextUnlock.cost }
	end
	if row.boss then
		out.bo = {
			id = row.boss.bossId,
			k = row.boss.kills,
			g = bool01(row.boss.granted),
			u = bool01(row.boss.blueprintUnlocked),
			p = row.boss.pity,
			pt = row.boss.pityTarget,
		}
	end
	return out
end

-- Build the compact cross-place package. Additive schema rule: v=1 consumers ignore unknown keys.
function DebriefService.makeReturnPackage(context: any, results: { any }): any
	local rows = {}
	for _, row in ipairs(results) do
		if type(row) == "table" and type(row.userId) == "number" then
			table.insert(rows, compactResult(row))
		end
	end
	local war = copyTable((context and context.warContribution) or {})
	return {
		v = PACKAGE_VERSION,
		t = PACKAGE_TAG,
		id = tostring(context.missionId or "unknown"),
		tpl = tostring(context.template or "UNKNOWN"),
		df = tostring(context.difficulty or "Normal"),
		seed = math.floor(finite(context.seed)),
		ok = bool01(context.extractionSuccess),
		obj = bool01(context.objectiveComplete),
		ss = bool01(context.salvageSecured),
		cl = bool01(context.carriedLost),
		em = bool01(context.emergency),
		fs = bool01(context.fullSquad),
		er = context.endReason,
		ab = math.floor(finite(context.aboardCount)),
		el = math.floor(finite(context.eligibleCount)),
		pc = math.floor(finite(context.participantCount)),
		ca = compactSalvage(context.carriedSalvage),
		war = {
			p = math.floor(finite(war.points)),
			op = war.operationId,
			rg = war.regionId,
			st = war.status,
			sec = war.sector,
			ap = bool01(war.applied),
			pq = math.floor(finite(war.participants)),
		},
		at = math.floor(finite(context.completedAt, os.time())),
		rows = rows,
	}
end

function DebriefService.encodePackage(package: any): string?
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(package)
	end)
	if not ok or type(encoded) ~= "string" then
		return nil
	end
	-- Teleport data has a hard platform budget. Optional explanatory rows are sacrificed first;
	-- the core credits/XP/salvage/rank/war numbers never are.
	if #encoded > TELEPORT_SOFT_LIMIT and type(package.rows) == "table" then
		for _, row in ipairs(package.rows) do
			row.nu = nil
			row.bo = nil
		end
		encoded = HttpService:JSONEncode(package)
	end
	if #encoded > TELEPORT_SOFT_LIMIT and type(package.rows) == "table" then
		for _, row in ipairs(package.rows) do
			row.m = nil
		end
		encoded = HttpService:JSONEncode(package)
	end
	if #encoded > 8000 then
		warn(string.format("[GF] debrief teleport package large (%d bytes)", #encoded))
	end
	return encoded
end

local function decodeRaw(data: any): any?
	if type(data) == "table" then
		if data.t == PACKAGE_TAG and data.v == PACKAGE_VERSION then
			return data
		end
		return nil
	end
	if type(data) ~= "string" or #data == 0 then
		return nil
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(data)
	end)
	if ok and type(decoded) == "table" and decoded.t == PACKAGE_TAG and decoded.v == PACKAGE_VERSION then
		return decoded
	end
	return nil
end

function DebriefService.decodePackage(data: any): any?
	return decodeRaw(data)
end

local function expandRow(package: any, row: any): any?
	if type(package) ~= "table" or type(row) ~= "table" then
		return nil
	end
	local mastery = nil
	if type(row.m) == "table" then
		mastery = {
			weaponId = row.m.id,
			xp = math.floor(finite(row.m.xp)),
			level = math.floor(finite(row.m.lv, 1)),
			earned = math.floor(finite(row.m.e)),
		}
	end
	local nextUnlock = nil
	if type(row.nu) == "table" then
		nextUnlock = {
			kind = row.nu.k,
			id = row.nu.id,
			displayName = row.nu.n,
			rank = math.floor(finite(row.nu.r)),
			cost = math.floor(finite(row.nu.c)),
		}
	end
	local boss = nil
	if type(row.bo) == "table" then
		boss = {
			bossId = row.bo.id,
			kills = row.bo.k,
			granted = truthy01(row.bo.g),
			blueprintUnlocked = truthy01(row.bo.u),
			pity = row.bo.p,
			pityTarget = row.bo.pt,
		}
	end
	local war = type(package.war) == "table" and package.war or {}
	local success = truthy01(package.ok)
	local objectiveComplete = truthy01(package.obj)
	local salvageSecured = truthy01(package.ss)
	local userId = math.floor(finite(row.u))
	return {
		v = PACKAGE_VERSION,
		debriefId = tostring(package.id) .. ":" .. tostring(userId),
		transactionId = row.tx or ("settle:" .. tostring(package.id)),
		missionId = tostring(package.id),
		template = tostring(package.tpl),
		difficulty = tostring(package.df),
		seed = math.floor(finite(package.seed)),
		userId = userId,
		playerName = row.pn,
		success = success,
		extractionSuccess = success,
		objectiveComplete = objectiveComplete,
		primaryComplete = objectiveComplete,
		salvageSecured = salvageSecured,
		carriedLost = truthy01(package.cl),
		emergency = truthy01(package.em),
		endReason = package.er,
		fullSquad = truthy01(package.fs),
		extracted = truthy01(row.ex),
		participantStatus = row.st or "participating",
		participationMetrics = {
			status = row.st or "participating",
			extracted = truthy01(row.ex),
			lateJoin = truthy01(row.lj),
			activeEligibleCount = math.floor(finite(package.el)),
			participantCount = math.floor(finite(package.pc)),
		},
		aboardCount = math.floor(finite(package.ab)),
		eligibleCount = math.floor(finite(package.el)),
		participantCount = math.floor(finite(package.pc)),
		credits = math.floor(finite(row.cr)),
		xp = math.floor(finite(row.xp)),
		baseCredits = math.floor(finite(row.bc)),
		baseXp = math.floor(finite(row.bx)),
		bonusCredits = math.floor(finite(row.boc)),
		bonusXp = math.floor(finite(row.box)),
		killXp = math.floor(finite(row.kx)),
		salvage = expandSalvage(row.s),
		baseSalvage = expandSalvage(row.bs),
		bonusSalvage = expandSalvage(row.bos),
		carriedSalvage = expandSalvage(package.ca),
		rank = math.floor(finite(row.rk, 1)),
		rankBefore = math.floor(finite(row.rb, row.rk or 1)),
		rankUps = math.floor(finite(row.ru)),
		xpTotal = math.floor(finite(row.xt)),
		xpForNextRank = math.floor(finite(row.xn)),
		xpIntoRank = math.floor(finite(row.xi)),
		creditsTotal = math.floor(finite(row.ct)),
		firstMissionBonusCredits = math.floor(finite(row.fmb)),
		warCredits = math.floor(finite(row.wc)),
		warCreditsEarned = math.floor(finite(row.we)),
		nextUnlock = nextUnlock,
		mastery = mastery,
		boss = boss,
		lateJoin = truthy01(row.lj),
		warContribution = math.floor(finite(war.p)),
		warDetail = {
			points = math.floor(finite(war.p)),
			operationId = war.op,
			regionId = war.rg,
			status = war.st,
			sector = war.sec,
			applied = truthy01(war.ap),
			participants = math.floor(finite(war.pq, 1)),
		},
		completedAt = math.floor(finite(package.at, os.time())),
		transport = "teleport",
	}
end

function DebriefService.expandForUser(package: any, userId: number): any?
	if type(package) ~= "table" or type(package.rows) ~= "table" then
		return nil
	end
	for _, row in ipairs(package.rows) do
		if math.floor(finite(row.u)) == userId then
			return expandRow(package, row)
		end
	end
	return nil
end

local function pruneCache()
	local now = os.time()
	for userId, entry in pairs(latestByUserId) do
		if now - entry.at > CACHE_TTL then
			latestByUserId[userId] = nil
		end
	end
end

function DebriefService.cache(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	pruneCache()
	latestByUserId[player.UserId] = { at = os.time(), payload = payload }
	player:SetAttribute("GF_DebriefMissionId", tostring(payload.missionId or ""))
	player:SetAttribute("GF_DebriefPending", true)
	workspace:SetAttribute("GF_DebriefReady_" .. tostring(player.UserId), tostring(payload.missionId or ""))
end

function DebriefService.deliver(player: Player, payload: any, delaySeconds: number?)
	if not player.Parent or type(payload) ~= "table" then
		return
	end
	DebriefService.cache(player, payload)
	local function fire()
		if not player.Parent then
			return
		end
		local remote = remoteEvent("MissionComplete")
		if remote then
			remote:FireClient(player, payload)
		end
	end
	-- Client scripts race server PlayerAdded after a teleport. A second identical delivery is
	-- idempotent for a well-formed debrief UI because debriefId identifies the same settlement.
	task.delay(delaySeconds or 1.0, fire)
	task.delay((delaySeconds or 1.0) + 3.0, fire)
end

-- Mission-side direct publication (shared-place fallback and transfer-failure path).
function DebriefService.publishLocal(player: Player, payload: any)
	DebriefService.deliver(player, payload, 0.15)
end

local function handleArrival(player: Player)
	task.defer(function()
		local ok, joinData = pcall(function()
			return player:GetJoinData()
		end)
		if not ok or type(joinData) ~= "table" then
			return
		end
		local package = decodeRaw((joinData :: any).TeleportData)
		if not package then
			return
		end
		local payload = DebriefService.expandForUser(package, player.UserId)
		if not payload then
			warn("[GF] return debrief package had no row for " .. player.Name)
			return
		end
		DebriefService.deliver(player, payload, 0.8)
		print(string.format("[GF] debrief restored for %s mission=%s", player.Name, tostring(payload.missionId)))
	end)
end

local function wireRemotes()
	if wired then
		return
	end
	wired = true
	local request = remoteFunction("RequestDebrief")
	if request then
		request.OnServerInvoke = function(player: Player)
			local entry = latestByUserId[player.UserId]
			if entry and os.time() - entry.at <= CACHE_TTL then
				return entry.payload
			end
			return nil
		end
	end
end

function DebriefService.start()
	if started then
		return
	end
	started = true
	-- RemoteService normally creates the folder before service boot. The retry keeps this safe in
	-- edit-mode checks and in any future boot ordering change.
	task.spawn(function()
		for _ = 1, 40 do
			if remoteFunction("RequestDebrief") then
				break
			end
			task.wait(0.25)
		end
		wireRemotes()
	end)
	Players.PlayerAdded:Connect(handleArrival)
	for _, player in ipairs(Players:GetPlayers()) do
		handleArrival(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- Keep the cache briefly across a crash/teleport boundary. A normal leave expiry is enough;
		-- deleting immediately would defeat reconnect recovery.
		player:SetAttribute("GF_DebriefPending", nil)
	end)
end

function DebriefService.cached(player: Player): any?
	local entry = latestByUserId[player.UserId]
	if entry and os.time() - entry.at <= CACHE_TTL then
		return entry.payload
	end
	return nil
end

return DebriefService
