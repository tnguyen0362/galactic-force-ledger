--!strict
-- Mission payout. Server computes every number; clients only display.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ProfileService = require(script.Parent.ProfileService)
local SquadService = require(script.Parent.SquadService)
local State = require(script.Parent.State)
local Economy = require(ReplicatedStorage.GF.Shared.Configs.Economy)

local RewardsService = {}
local FALLBACK = { credits = 450, xp = 600 }

local function tableFor(difficulty: string)
	local byDiff = Economy.PayoutByDifficulty
	if type(byDiff) == "table" then
		local row = byDiff[difficulty] or byDiff.Normal
		if type(row) == "table" and type(row.credits) == "number" then
			return { credits = row.credits, xp = row.xp or FALLBACK.xp }
		end
	end
	local ok, res = pcall(function()
		return Economy.payout(difficulty)
	end)
	if ok and type(res) == "table" and type(res.credits) == "number" then
		return { credits = res.credits, xp = res.xp or FALLBACK.xp }
	end
	return FALLBACK
end

function RewardsService.compute(difficulty: string, success: boolean, objectiveComplete: boolean, squadBonus: boolean?)
	local base = tableFor(difficulty)
	local empty = { scrap = 0, energyCells = 0, militaryTechnology = 0 }
	if not objectiveComplete then
		return { credits = 0, xp = 0, salvage = empty }
	end
	if not success then
		return { credits = base.credits, xp = base.xp, salvage = empty }
	end
	-- Full-squad bonus: +25% when every eligible survivor commits together via Extract Squad (solo always
	-- qualifies). ExtractionService decides eligibility; individual early extraction passes false.
	local full = squadBonus == true
	local bonusCredits = full and math.floor(base.credits * 0.25) or 0
	local bonusXp = full and math.floor(base.xp * 0.25) or 0
	local salvaged = SquadService.snapshot()
	local awarded = { scrap = salvaged.scrap, energyCells = salvaged.energyCells, militaryTechnology = salvaged.militaryTechnology }
	local bonusSalvage = { scrap = 0, energyCells = 0, militaryTechnology = 0 }
	if full then
		-- The spec applies the full-squad bonus to integer salvage too, floored per resource.
		for key, value in pairs(awarded) do
			local extra = math.floor(value * 0.25)
			bonusSalvage[key] = extra
			awarded[key] = value + extra
		end
	end
	return {
		credits = base.credits + bonusCredits,
		xp = base.xp + bonusXp,
		salvage = awarded,
		baseSalvage = salvaged,
		bonusSalvage = bonusSalvage,
		baseCredits = base.credits,
		baseXp = base.xp,
		bonusCredits = bonusCredits,
		bonusXp = bonusXp,
		fullSquad = full,
	}
end
-- Kill XP (S10-006): the spec's 650-900 XP band is "including kills". Mastery XP accrues per kill and
-- settles into weapon mastery before payout; the same amounts also count as rank XP so a fight-heavy
-- mission out-earns a quiet one. ExtractionService reports the per-player totals here at settle time.
local killXpByUserId: { [number]: number } = {}

function RewardsService.setKillXp(player: Player, amount: number)
	killXpByUserId[player.UserId] = amount
end

function RewardsService.grant(player: Player, difficulty: string, success: boolean, objectiveComplete: boolean, squadBonus: boolean?)
	-- A late joiner already received a catch-up credit on accepting the dispatch. Paying them the full mission
	-- payout as well would reward the same operation twice.
	local joinerState = require(script.Parent.State).get(player)
	if joinerState and joinerState.joinedLate then
		workspace:SetAttribute("GF_DispatchLatePayout", player.Name)
		local lateRemote = ReplicatedStorage.GF.Remotes:FindFirstChild("MissionComplete")
		if lateRemote then
			lateRemote:FireClient(player, {
				success = success,
				objectiveComplete = objectiveComplete,
				baseCredits = 0,
				baseXp = 0,
				bonusCredits = 0,
				bonusXp = 0,
				bonusSalvage = nil,
				fullSquad = false,
		carriedLost = workspace:GetAttribute("GF_CarriedLost") == true,
				credits = 0,
				xp = 0,
				salvage = { scrap = 0, energyCells = 0, militaryTechnology = 0 },
				rank = (function()
					local prof = ProfileService.get(player)
					return prof and prof.rank or 1
				end)(),
				rankUps = 0,
				lateJoin = true,
			})
		end
		print(string.format("[GF] payout skipped for late joiner %s", player.Name))
		return { credits = 0, xp = 0, salvage = { scrap = 0, energyCells = 0, militaryTechnology = 0 } }
	end
	-- Idempotent settlement: one payout per player per mission id, persisted in the profile so a retry,
	-- double extraction call or rejoin cannot pay the same mission twice.
	local settleProfile = ProfileService.get(player)
	local missionKey = nil
	pcall(function()
		missionKey = require(script.Parent.RewardLedgerService).missionId()
	end)
	if settleProfile and type(missionKey) == "string" then
		settleProfile.settledMissions = settleProfile.settledMissions or {}
		if settleProfile.settledMissions[missionKey] then
			workspace:SetAttribute("GF_PayoutDuplicateBlocked", player.Name .. ":" .. missionKey)
			return { credits = 0, xp = 0, salvage = { scrap = 0, energyCells = 0, militaryTechnology = 0 }, duplicate = true }
		end
		settleProfile.settledMissions[missionKey] = os.time()
		local keys = {}
		for key, at in pairs(settleProfile.settledMissions) do
			table.insert(keys, { key = key, at = tonumber(at) or 0 })
		end
		table.sort(keys, function(a, b) return a.at < b.at end)
		while #keys > 30 do
			settleProfile.settledMissions[table.remove(keys, 1).key] = nil
		end
	end
	local payload = RewardsService.compute(difficulty, success, objectiveComplete, squadBonus)
	print(string.format("[GF] payout %s difficulty=%s success=%s objective=%s credits=%d xp=%d", player.Name, difficulty, tostring(success), tostring(objectiveComplete), payload.credits, payload.xp))
	workspace:SetAttribute("GF_LastPayout", string.format("%s:%d", player.Name, payload.credits))
	local killXp = math.floor(tonumber(killXpByUserId[player.UserId]) or 0)
	killXpByUserId[player.UserId] = nil
	if killXp > 0 and objectiveComplete then
		payload.xp += killXp
		payload.killXp = killXp
	end
	local result = ProfileService.award(player, payload.credits, payload.xp)
	local profile = ProfileService.get(player)
	if profile then
		if type(profile.salvage) == "table" then
			profile.salvage.scrap = (profile.salvage.scrap or 0) + (payload.salvage.scrap or 0)
			profile.salvage.energyCells = (profile.salvage.energyCells or 0) + (payload.salvage.energyCells or 0)
			profile.salvage.militaryTechnology = (profile.salvage.militaryTechnology or 0) + (payload.salvage.militaryTechnology or 0)
		end
		-- War Credits: fixed per difficulty on successful primary extraction, never multiplied by the
		-- full-squad bonus (GOAL §9 explicitly excludes War Credits from the bonus base).
		if success and objectiveComplete then
			local warCreditTable = { Easy = 5, Normal = 10, Hard = 15, Extreme = 25 }
			local warCredits = warCreditTable[difficulty] or 0
			if warCredits > 0 then
				profile.warCredits = (profile.warCredits or 0) + warCredits
				workspace:SetAttribute("GF_WarCreditsAwarded", string.format("%s:+%d", player.Name, warCredits))
			end
		end
		if type(missionKey) == "string" then
			ProfileService.recordTransaction(player, "settle:" .. missionKey)
		end
		ProfileService.markDirty(player)
		-- Settlement is a critical write (L222): bounded backoff absorbs transient datastore failure
		-- before the success debrief is ever shown.
		local persisted = ProfileService.saveWithRetry(player)
		print("[GF] profile persisted=" .. tostring(persisted))
		-- uniform economic journal (spec §96-98): settle:<missionKey> matches the settledMissions
		-- idempotency key exactly, so a blocked duplicate payout can never double-journal either.
		if type(missionKey) == "string" then
			local ok, svc = pcall(function()
				return require(script.Parent.EconomyTransactionService)
			end)
			if ok and svc then
				pcall(function()
					svc.record(player, {
						id = "settle:" .. missionKey,
						type = "mission_settlement",
						sourceId = "mission:" .. tostring(difficulty),
						inputs = {},
						outputs = {
							credits = payload.credits or 0,
							xp = payload.xp or 0,
							scrap = (payload.salvage and payload.salvage.scrap) or 0,
							energyCells = (payload.salvage and payload.salvage.energyCells) or 0,
							militaryTechnology = (payload.salvage and payload.salvage.militaryTechnology) or 0,
							warCredits = (success and objectiveComplete) and (({ Easy = 5, Normal = 10, Hard = 15, Extreme = 25 })[difficulty] or 0) or 0,
						},
						note = string.format("success=%s objective=%s squadBonus=%s killXp=%s", tostring(success), tostring(objectiveComplete), tostring(squadBonus == true), tostring(payload.killXp)),
					})
				end)
			end
		end
	end
	-- Boss research travels with the debrief so a blueprint drop is announced where the player is already
	-- looking. It is cleared after reporting so a later ordinary mission cannot repeat old news.
	local bossReport = nil
	if profile and type(profile.lastBossReward) == "table" then
		bossReport = profile.lastBossReward
		profile.lastBossReward = nil
	end
	-- Mastery progress in the debrief (S10-039), read after settlement so this is the value the player
	-- just earned rather than a stale pre-mission number.
	local masteryReport = nil
	if profile then
		local liveState = State.get(player)
		local weaponId = liveState and liveState.weaponId
		if weaponId then
			masteryReport = {
				weaponId = weaponId,
				xp = tonumber((profile.weaponMastery or {})[weaponId]) or 0,
				level = ProfileService.masteryLevel(player, weaponId),
			}
		end
	end
	local remote = ReplicatedStorage.GF.Remotes:FindFirstChild("MissionComplete")
	if remote then
		remote:FireClient(player, {
			success = success,
			objectiveComplete = objectiveComplete,
			credits = payload.credits,
			xp = payload.xp,
			salvage = payload.salvage,
			baseCredits = payload.baseCredits or payload.credits,
			baseXp = payload.baseXp or payload.xp,
			bonusCredits = payload.bonusCredits or 0,
			bonusXp = payload.bonusXp or 0,
			bonusSalvage = payload.bonusSalvage,
			fullSquad = payload.fullSquad == true,
			carriedLost = workspace:GetAttribute("GF_CarriedLost") == true,
			rank = profile and profile.rank or 1,
			rankUps = (workspace:GetAttribute("GF_ForceRankUps") and tonumber(workspace:GetAttribute("GF_ForceRankUps"))) or result.rankUps,
			warCredits = profile and profile.warCredits or 0,
			boss = bossReport,
			mastery = masteryReport,
			endReason = workspace:GetAttribute("GF_MissionEndReason"),
		})
	end
	return payload
end

function RewardsService.grantAll(success: boolean, difficultyOverride: string?, objectiveOverride: boolean?, squadBonus: boolean?)
	local mission = State.getMission()
	local difficulty = difficultyOverride or (mission and mission.difficulty) or "Normal"
	local objectiveComplete = if objectiveOverride ~= nil then objectiveOverride elseif mission then mission.objectiveComplete else false
	for _, player in Players:GetPlayers() do
		RewardsService.grant(player, difficulty, success, objectiveComplete, squadBonus)
	end
end

return RewardsService

