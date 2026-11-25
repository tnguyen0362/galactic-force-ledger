--!strict
-- The shared campaign. Until now the war table said "SECTOR CONTESTED - counteroffensive in progress" as fixed
-- copy, so nothing the player did changed the galaxy. This owns the counters and publishes them as attributes
-- the station reads; it is server-owned and persisted so a restart does not reset the war.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GalacticWarService = {}

local STORE_NAME = "GF_War_v1"
local KEY = "campaign"
local store = nil

local Campaign = require(ReplicatedStorage.GF.Shared.Configs.Campaign)

local state = {
	missionsWon = 0,
	missionsLost = 0,
	relaysSabotaged = 0,
	recoveries = 0,
	beaconsHeld = 0,
	eliminations = 0,
	-- spec section 13: per-territory liberation. progress is 0-100 derived from points/target;
	-- points accumulate per unique primary completion against the territory's phase target.
	territories = nil, -- lazily initialized from the config so a saved campaign survives config edits
	phaseId = 1,
	phaseStartedAt = 0,
	lastDefenseAt = 0, -- UTC os.time() of the last defense phase opening (S13-014 72h cadence)
	defenseOpenUntil = 0, -- UTC time the current defense window expires; 0 = no open defense phase
	processedMissions = nil, -- mission-id dedup for exactly-once point awards
}

local function initTerritories()
	if type(state.territories) == "table" and next(state.territories) ~= nil then
		return
	end
	state.territories = {}
	for index, territory in ipairs(Campaign.Territories) do
		-- fronts open contested; the first two per the connected map start as active battlefronts
		state.territories[territory.id] = {
			progress = 0,
			points = 0,
			target = Campaign.ColdStartTarget,
			state = "Contested",
			battlefront = index <= 3, -- ~2-3 active fronts at campaign start
			biome = territory.biome,
		}
	end
	state.processedMissions = {}
end

-- Sector standing swings between the Ascendancy holding the frontier and the counteroffensive taking it back.
local function sectorStatus(): (string, string)
	local score = state.missionsWon - state.missionsLost
	if score >= 8 then
		return "SECTOR HELD", "Counteroffensive complete - Veyra-7 is ours."
	elseif score >= 4 then
		return "ADVANCING", string.format("Counteroffensive advancing - %d objectives secured.", state.missionsWon)
	elseif score >= 1 then
		return "CONTESTED", string.format("Sector contested - %d operations won, %d lost.", state.missionsWon, state.missionsLost)
	end
	return "ASCENDANCY HOLDING", "The frontier is theirs. Take an operation back."
end

local function publish()
	initTerritories()
	local status, line = sectorStatus()
	workspace:SetAttribute("GF_WarStatus", status)
	workspace:SetAttribute("GF_WarSector", line)
	workspace:SetAttribute("GF_WarScore", state.missionsWon - state.missionsLost)
	workspace:SetAttribute("GF_WarWins", state.missionsWon)
	workspace:SetAttribute("GF_WarLosses", state.missionsLost)
	-- territory snapshot: compact per-territory progress/state/front for the war table UI
	local parts = {}
	local fronts = 0
	for _, territory in ipairs(Campaign.Territories) do
		local t = state.territories[territory.id]
		if t then
			if t.battlefront then
				fronts += 1
			end
			table.insert(parts, string.format("%s:%d:%s%s", territory.id, math.floor(t.progress + 0.5), t.state, t.battlefront and ":FRONT" or ""))
		end
	end
	workspace:SetAttribute("GF_WarTerritories", table.concat(parts, ";"))
	workspace:SetAttribute("GF_WarFronts", fronts)
	workspace:SetAttribute("GF_WarSnapshotAt", os.time())
end

function GalacticWarService.recordMission(template: string?, success: boolean)
	if success then
		state.missionsWon += 1
		if template == "SABOTAGE_RELAY" then
			state.relaysSabotaged += 1
		elseif template == "RECOVER_TECH" then
			state.recoveries += 1
		elseif template == "DEFEND_BEACON" then
			state.beaconsHeld += 1
		end
	else
		state.missionsLost += 1
	end
	publish()
	GalacticWarService.save()
end

-- War points commit at primary success, not at extraction (GOAL L145 / S09-035): a squad that
-- completes the objective and then loses the dropship still won that operation. Idempotent per
-- mission - ObjectiveService.setup clears the marker for the next one.
-- The active front for contributions: the first battlefront territory still contested. Missions are
-- not territory-keyed in the prototype, so points land on the rotating active front (spec-tagged
-- Studio-only simulation of community focus).
local function activeFront(): string?
	initTerritories()
	for _, territory in ipairs(Campaign.Territories) do
		local t = state.territories[territory.id]
		if t and t.battlefront and t.state ~= "Human" then
			return territory.id
		end
	end
	return nil
end

-- Spec formula: round(10 * difficultyWeight * typeWeight * (1 + .20 * (Pqualified - 1))). Exactly-once
-- per mission id; no extraction dependency. At 100% liberation the front flips Human and a neighbor
-- opens as the next battlefront.
function GalacticWarService.awardCampaignPoints(missionId: string?, difficulty: string?, family: string?, pqualified: number?): number
	initTerritories()
	local key = tostring(missionId or "")
	if key ~= "" and state.processedMissions[key] then
		return 0 -- atomic mission-id dedup: same primary never contributes twice
	end
	local front = activeFront()
	if not front then
		return 0
	end
	local points = Campaign.pointsFor(difficulty, family, pqualified)
	local t = state.territories[front]
	t.points += points
	t.progress = math.min(100, 100 * t.points / math.max(1, t.target))
	if key ~= "" then
		state.processedMissions[key] = true
	end
	workspace:SetAttribute("GF_WarPoints", string.format("%s+%d=%d/%d", front, points, t.points, t.target))
	if t.progress >= 100 and t.state ~= "Human" then
		t.state = "Human"
		t.battlefront = false
		-- successful stronghold flips the front Human and opens a neighboring front
		local territoryDef = Campaign.ById[front]
		for _, neighbor in ipairs(territoryDef and territoryDef.neighbors or {}) do
			local nt = state.territories[neighbor]
			if nt and nt.state ~= "Human" and not nt.battlefront then
				nt.battlefront = true
				nt.state = "Contested"
				break
			end
		end
		workspace:SetAttribute("GF_WarFlip", front)
		pcall(function()
			require(script.Parent.DialogueService).say(string.format("%s liberated. The counteroffensive advances.", front), "war")
		end)
	end
	publish()
	GalacticWarService.save()
	return points
end

function GalacticWarService.commitPrimary(template: string?)
	if workspace:GetAttribute("GF_WarCommitted") == true then
		return false
	end
	workspace:SetAttribute("GF_WarCommitted", true)
	GalacticWarService.recordMission(template, true)
	-- campaign points commit with the primary, independent of extraction (spec: no extraction dependency)
	local missionId = tostring(workspace:GetAttribute("GF_MissionId") or "")
	local difficulty = tostring(workspace:GetAttribute("GF_MissionDifficulty") or "Normal")
	local family = "Sabotage"
	pcall(function()
		local Missions = require(ReplicatedStorage.GF.Shared.Configs.Missions)
		local def = Missions and Missions.ById and Missions.ById[tostring(template or "")]
		if def and def.family then
			family = def.family
		end
	end)
	GalacticWarService.awardCampaignPoints(missionId, difficulty, family, 1)
	return true
end
function GalacticWarService.snapshot()
	return {
		missionsWon = state.missionsWon,
		missionsLost = state.missionsLost,
		relaysSabotaged = state.relaysSabotaged,
		recoveries = state.recoveries,
		beaconsHeld = state.beaconsHeld,
		status = workspace:GetAttribute("GF_WarStatus"),
	}
end

-- Spec S13-006: if all territories are captured, a periodic bounded counteroffensive reopens one or
-- two fronts at reduced progress - never a full wipe, never touching personal progression. Returns the
-- number of fronts reopened.
-- Spec S13-014: every 72h a human defense phase opens one threatened front. Successful Defense or
-- Conquest contributions stabilize it; if the window expires below target the front reopens contested
-- at 40-60% progress. Never resets the whole campaign, never touches personal progression.
local DEFENSE_PERIOD = 72 * 3600
local DEFENSE_WINDOW = 24 * 3600

local function openDefenseFront(): boolean
	initTerritories()
	-- pick the most-progressed contested/ascendancy front as the threatened one; fall back to any human
	-- territory when the campaign is fully liberated (the counteroffensive pressure never vanishes).
	local threatened, bestProgress = nil, -1
	for _, territory in ipairs(Campaign.Territories) do
		local t = state.territories[territory.id]
		if t and t.state ~= "Contested" and t.progress > bestProgress then
			threatened, bestProgress = territory, t.progress
		end
	end
	if not threatened then
		return false
	end
	local t = state.territories[threatened.id]
	t.battlefront = true
	state.defenseOpenUntil = os.time() + DEFENSE_WINDOW
	state.lastDefenseAt = os.time()
	workspace:SetAttribute("GF_WarDefenseOpen", threatened.id)
	pcall(function()
		require(script.Parent.DialogueService).say(string.format("Defense phase: %s is threatened. Hold it.", threatened.displayName or threatened.id), "war")
	end)
	publish()
	return true
end

function GalacticWarService.counteroffensive(): number
	initTerritories()
	local anyContested = false
	for _, territory in ipairs(Campaign.Territories) do
		local t = state.territories[territory.id]
		if t and t.state ~= "Human" then
			anyContested = true
			break
		end
	end
	if anyContested then
		return 0
	end
	local reopened = 0
	for _, territory in ipairs(Campaign.Territories) do
		if reopened >= 2 then
			break
		end
		local t = state.territories[territory.id]
		if t and t.state == "Human" then
			t.state = "Contested"
			t.battlefront = true
			-- bounded: progress falls back to a 40-60% band rather than zeroing the campaign
			t.progress = 50
			t.points = math.floor(t.target * 0.5)
			reopened += 1
		end
	end
	if reopened > 0 then
		workspace:SetAttribute("GF_WarCounteroffensive", reopened)
		pcall(function()
			require(script.Parent.DialogueService).say("Ascendancy counteroffensive reopening the front. Hold what we took.", "war")
		end)
		publish()
		GalacticWarService.save()
	end
	return reopened
end

function GalacticWarService.save()
	if not store then
		return false
	end
	local ok = pcall(function()
		store:SetAsync(KEY, state)
	end)
	return ok
end

function GalacticWarService.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		local loaded = pcall(function()
			local saved = store:GetAsync(KEY)
			if type(saved) == "table" then
				for key, value in pairs(saved) do
					if type(value) == "number" then
						state[key] = value
					end
				end
			end
		end)
		if not loaded then
			warn("[GF] galactic war state unavailable; starting the campaign fresh")
		end
	else
		warn("[GF] no DataStore for the campaign; state is session-local")
	end
	initTerritories()
	publish()
	-- S13-014 scheduler: check the 72h cadence and resolve expired defense windows every few minutes.
	task.spawn(function()
		while true do
			task.wait(300)
			local nowUtc = os.time()
			if state.defenseOpenUntil > 0 and nowUtc >= state.defenseOpenUntil then
				-- window expired: if the threatened front is still below target it falls back contested
				-- at the 40-60% band; successful defense contributions (progress at/above target) stabilize it.
				local openId = workspace:GetAttribute("GF_WarDefenseOpen")
				state.defenseOpenUntil = 0
				for _, territory in ipairs(Campaign.Territories) do
					if territory.id == openId then
						local t = state.territories[territory.id]
						if t and t.progress < 100 then
							t.state = "Contested"
							t.progress = math.clamp(t.progress, 40, 60)
							t.points = math.floor(t.target * (t.progress / 100))
							workspace:SetAttribute("GF_WarDefenseLost", openId)
						end
					end
				end
				publish()
				GalacticWarService.save()
			elseif nowUtc - (state.lastDefenseAt or 0) >= DEFENSE_PERIOD and state.defenseOpenUntil == 0 then
				if openDefenseFront() then
					GalacticWarService.save()
				end
			end
		end
	end)
	print(string.format("[GF] galactic war online: won=%d lost=%d status=%s fronts=%s", state.missionsWon, state.missionsLost, tostring(workspace:GetAttribute("GF_WarStatus")), tostring(workspace:GetAttribute("GF_WarFronts"))))
end

-- S13-017 snapshot publication: cached front state, contribution and freshness age flow to the
-- debrief display through workspace attributes.
task.spawn(function()
	while true do
		task.wait(5)
		local war = GalacticWarService.getWar and GalacticWarService.getWar() or nil
		if war then
			workspace:SetAttribute("GF_WarFront", tostring(war.front or "stable"))
			workspace:SetAttribute("GF_WarContribution", math.floor(war.contribution or 0))
			workspace:SetAttribute("GF_WarSnapshotAge", os.clock() - (war.snapshotAt or os.clock()))
		end
	end
end)

-- S13-012 territory phase targets: each phase target derives from estimated daily qualifying
-- missions — clamp(round(20*estimate), 100, 50000). The formula is explicit so balance tuning
-- adjusts the estimate, never a magic number buried in config.
function GalacticWarService.phaseTarget(estimatedDailyQualifyingMissions: number): number
	local target = math.round(20 * estimatedDailyQualifyingMissions)
	return math.clamp(target, 100, 50000)
end

return GalacticWarService

