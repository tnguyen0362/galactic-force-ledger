--!strict
-- NPCSquads: squad coordination for Ascendancy soldiers (spec sections 24/25).
-- Enemies fight as units, not independent agents competing for the same cover and target.
-- This module owns the squad blackboard: shared reports, cover reservations, role assignment,
-- coordination limits, morale-relevant loss tracking, and Commander influence.
--
-- Design constraints from the spec:
--   squads are LOCAL (3-6 ordinary units), formed by spatial proximity — not global armies
--   communication is explicit reports with timestamps, never instant perfect broadcast
--   role assignment is bounded greedy suitability, re-evaluated on meaningful events only
--   coordination LIMITS produce coherent pressure: not everyone flanks, not everyone advances
--   Commander influence falls off with distance and dies with the Commander

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EncounterHierarchy = require(ReplicatedStorage.GF.Shared.Configs.EncounterHierarchy)

local NPCSquads = {}

local SQUAD_JOIN_RADIUS = 55 -- spawn-time clustering: members within this distance join one squad
local SQUAD_MAX_SIZE = 6
local RESERVATION_EXPIRY = 12 -- seconds; a stale reservation releases itself
local ROLE_REEVAL_COOLDOWN = 4 -- seconds between assignment passes for one squad
local COMMANDER_RADIUS = 60 -- R_command: leadership influence scale (studs)
local MAX_FLANKERS_PER_SQUAD = 1 -- spec: squad-level limits on simultaneous alternative approaches

export type SquadBlackboard = {
	id: number,
	centre: Vector3, -- last-known squad centre: founding position, updated as members move
	members: { [Model]: boolean },
	roles: { [Model]: string },
	reportedTargets: { [Player]: { position: Vector3, observedAt: number, confidence: number, observer: Model? } },
	reservedCover: { [Model]: Vector3 }, -- member -> reserved position
	recentLosses: number, -- count of squad members lost recently
	lossTimer: number, -- when the most recent loss occurred
	objective: string, -- "defend" | "assault" | "patrol" | freeform
	createdAt: number,
	lastRolePass: number,
	commander: Model?, -- the squad's Officer if any
	flankerActive: Model?, -- the member currently executing an alternative approach
}

local squads: { [number]: SquadBlackboard } = {}
local membership: { [Model]: number } = {}
local nextId = 0

local function newSquad(position: Vector3): SquadBlackboard
	nextId += 1
	local sq: SquadBlackboard = {
		id = nextId,
		centre = position,
		members = {},
		roles = {},
		reportedTargets = {},
		reservedCover = {},
		recentLosses = 0,
		lossTimer = 0,
		objective = "defend",
		createdAt = os.clock(),
		lastRolePass = 0,
		commander = nil,
		flankerActive = nil,
	}
	squads[nextId] = sq
	return sq
end

-- ---------------------------------------------------------------------------
-- membership: a spawning soldier joins the nearest squad with capacity, or founds one.
-- ---------------------------------------------------------------------------
function NPCSquads.assign(model: Model, position: Vector3, archetype: string): SquadBlackboard
	local best: SquadBlackboard? = nil
	local bestDist = SQUAD_JOIN_RADIUS
	for _, sq in pairs(squads) do
		local count = 0
		local cx, cz, n = 0, 0, 0
		for member in pairs(sq.members) do
			count += 1
			if member.PrimaryPart then
				cx += member.PrimaryPart.Position.X
				cz += member.PrimaryPart.Position.Z
				n += 1
			end
		end
		if count < SQUAD_MAX_SIZE then
			-- use live member positions when available; the stored centre otherwise — spawn-time
			-- races must not fragment a cluster into single-member squads
			local centre = n > 0 and Vector3.new(cx / n, 0, cz / n) or Vector3.new(sq.centre.X, 0, sq.centre.Z)
			local d = (Vector3.new(position.X, 0, position.Z) - centre).Magnitude
			if d < bestDist then
				bestDist = d
				best = sq
			end
		end
	end
	local sq = best or newSquad(position)
	sq.members[model] = true
	sq.centre = position -- newest member position keeps the centre honest during formation
	membership[model] = sq.id
	if archetype == "Commander" and not sq.commander then
		sq.commander = model
	end
	return sq
end

function NPCSquads.squadOf(model: Model): SquadBlackboard?
	local id = membership[model]
	return id and squads[id] or nil
end

-- ---------------------------------------------------------------------------
-- loss tracking: death releases everything the member held and records the loss.
-- Commander elimination is readable battlefield information: the squad loses coordination
-- bonuses and the blackboard remembers the disruption window.
-- ---------------------------------------------------------------------------
function NPCSquads.release(model: Model)
	local id = membership[model]
	membership[model] = nil
	if not id then
		return
	end
	local sq = squads[id]
	if not sq then
		return
	end
	sq.members[model] = nil
	sq.roles[model] = nil
	sq.reservedCover[model] = nil
	if sq.flankerActive == model then
		sq.flankerActive = nil
	end
	if sq.commander == model then
		sq.commander = nil
		-- leadership disruption (spec section 25): the loss is recorded; affected units fight on
		-- with degraded coordination rather than collapsing or instantly replacing command.
		sq.lossTimer = os.clock()
	end
	sq.recentLosses += 1
	sq.lossTimer = os.clock()
	-- empty squads dissolve
	local any = false
	for _ in pairs(sq.members) do
		any = true
		break
	end
	if not any then
		squads[id] = nil
	end
end

-- ---------------------------------------------------------------------------
-- role assignment (spec section 24): bounded greedy suitability. Re-evaluated at most once
-- per few seconds or on meaningful events — never several times per second.
-- roles: anchor (holds position, heavy/rifleman), engager (default pressure), flanker
-- (vanguard-class alternative approach), precision (marksman overwatch), leader (commander).
-- ---------------------------------------------------------------------------
local ROLE_SUITABILITY = {
	anchor = { Heavy = 3, Rifleman = 2, Commander = 1, Marksman = 0.5, Vanguard = 0 },
	engager = { Rifleman = 2, Vanguard = 1.5, Heavy = 1.5, Commander = 1, Marksman = 0.5 },
	flanker = { Vanguard = 3, Rifleman = 1.5, Marksman = 0, Heavy = 0, Commander = 0 },
	precision = { Marksman = 3, Rifleman = 1, Officer = 0.5, Heavy = 0, Vanguard = 0 },
	leader = { Commander = 3, Heavy = 0.5, Rifleman = 0.5, Marksman = 0, Vanguard = 0 },
}

function NPCSquads.reevaluateRoles(sq: SquadBlackboard, archetypeOf: (Model) -> string)
	local now = os.clock()
	if now - sq.lastRolePass < ROLE_REEVAL_COOLDOWN then
		return
	end
	sq.lastRolePass = now
	-- count live members; tiny squads skip formal roles (everyone is an engager)
	local live = {}
	for member in pairs(sq.members) do
		if member.Parent and not member:GetAttribute("Dead") then
			live[#live + 1] = member
		end
	end
	if #live <= 2 then
		for _, m in ipairs(live) do
			sq.roles[m] = "engager"
		end
		return
	end
	-- greedy pass: assign specialist roles first where suitability is high
	local assigned: { [Model]: boolean } = {}
	local function assignBest(role: string, minSuit: number): Model?
		local bestM: Model? = nil
		local bestS = minSuit
		for _, m in ipairs(live) do
			if not assigned[m] then
				local suit = (ROLE_SUITABILITY[role] or {})[archetypeOf(m)] or 0
				if suit > bestS then
					bestS = suit
					bestM = m
				end
			end
		end
		if bestM then
			assigned[bestM] = true
			sq.roles[bestM] = role
		end
		return bestM
	end
	if sq.commander and sq.commander.Parent then
		assigned[sq.commander] = true
		sq.roles[sq.commander] = "leader"
	end
	assignBest("precision", 2)
	assignBest("flanker", 2)
	assignBest("anchor", 1.5)
	-- everyone else: default pressure role
	for _, m in ipairs(live) do
		if not assigned[m] then
			sq.roles[m] = "engager"
		end
	end
end

function NPCSquads.roleOf(model: Model): string
	local sq = NPCSquads.squadOf(model)
	return (sq and sq.roles[model]) or "engager"
end

-- ---------------------------------------------------------------------------
-- coordination limits: alternative approaches are squad-limited — one flanker at a time.
-- ---------------------------------------------------------------------------
function NPCSquads.requestFlank(model: Model): boolean
	local sq = NPCSquads.squadOf(model)
	if not sq then
		return true -- independent soldier: no squad constraint
	end
	if sq.flankerActive == nil or sq.flankerActive == model then
		sq.flankerActive = model
		return true
	end
	-- the active flanker may be dead or done; validate before denying
	if not sq.flankerActive.Parent or sq.flankerActive:GetAttribute("Dead") then
		sq.flankerActive = model
		return true
	end
	return false
end

function NPCSquads.endFlank(model: Model)
	local sq = NPCSquads.squadOf(model)
	if sq and sq.flankerActive == model then
		sq.flankerActive = nil
	end
end

-- ---------------------------------------------------------------------------
-- cover reservations (spec section 21): position claims with expiry. prevents two soldiers
-- stacking on one rock; releases happen on death (release()), timeout, or explicit release.
-- ---------------------------------------------------------------------------
function NPCSquads.claimCover(model: Model, position: Vector3): boolean
	local sq = NPCSquads.squadOf(model)
	if not sq then
		return true
	end
	local now = os.clock()
	-- conflict check: another member holds a spot within 4 studs of the candidate
	for member, pos in pairs(sq.reservedCover) do
		if member ~= model and (pos - position).Magnitude < 4 then
			if member.Parent and not member:GetAttribute("Dead") then
				return false
			end
			sq.reservedCover[member] = nil -- corpse's claim is void
		end
	end
	sq.reservedCover[model] = position
	return true
end

function NPCSquads.coverConflict(model: Model, position: Vector3): boolean
	local sq = NPCSquads.squadOf(model)
	if not sq then
		return false
	end
	for member, pos in pairs(sq.reservedCover) do
		if member ~= model and (pos - position).Magnitude < 4 and member.Parent and not member:GetAttribute("Dead") then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- shared reports (spec section 24): the blackboard carries observed positions with original
-- timestamps. members read these through their own perception (receiveReport) — the board is
-- a distribution mechanism, not a truth override.
-- ---------------------------------------------------------------------------
function NPCSquads.postReport(sq: SquadBlackboard, player: Player, position: Vector3, observedAt: number, confidence: number, observer: Model?)
	local existing = sq.reportedTargets[player]
	if existing and existing.observedAt >= observedAt then
		return -- staleness never overwrites freshness
	end
	sq.reportedTargets[player] = {
		position = position,
		observedAt = observedAt,
		confidence = confidence,
		observer = observer,
	}
end

function NPCSquads.freshestReport(sq: SquadBlackboard, player: Player)
	return sq.reportedTargets[player]
end

-- ---------------------------------------------------------------------------
-- commander influence (spec section 25): exp falloff with distance, presence-gated.
-- q_effective = clamp(q_base * (1 + k*influence)) — applied to coordination parameters,
-- never raw damage. Returns the influence coefficient 0..1.
-- ---------------------------------------------------------------------------
function NPCSquads.commanderInfluence(sq: SquadBlackboard?, position: Vector3): number
	if not sq or not sq.commander then
		return 0
	end
	local cmdr = sq.commander
	if not cmdr.Parent or cmdr:GetAttribute("Dead") or not cmdr.PrimaryPart then
		return 0
	end
	local d = (cmdr.PrimaryPart.Position - position).Magnitude
	return math.exp(-d / COMMANDER_RADIUS)
end

-- morale input helper: squad loss pressure decays over ~45s — squads steady themselves
function NPCSquads.lossPressure(sq: SquadBlackboard?): number
	if not sq or sq.recentLosses == 0 then
		return 0
	end
	local age = os.clock() - sq.lossTimer
	local decay = math.exp(-age / 45)
	return math.min(1, sq.recentLosses * 0.3) * decay
end

-- ---------------------------------------------------------------------------
-- reinforcement composition (encounter-pacing layer): compose a wave as ONE squad,
-- not a bag of independent single spawns. EncounterDirector chooses when and where;
-- this module owns the infantry-core/support/command/heavy shape and formation offsets.
-- ---------------------------------------------------------------------------
export type WaveRequest = {
	phase: string?,
	escalation: number?,
	difficulty: string?,
	maxCost: number?,
	maxMembers: number?,
	playerCount: number?,
	sizeHint: number?,
	seed: number?,
}

export type WaveMember = {
	id: string,
	role: string,
	offset: Vector3,
}

local ROLE_BY_ID = {
	Rifleman = "infantry",
	Scout = "infantry",
	Marksman = "support",
	Heavy = "heavy",
	Officer = "command",
}

local function rand01(rng: Random?): number
	return rng and rng:NextNumber() or math.random()
end

local function pick(ids: { string }, rng: Random?): string
	if #ids == 0 then
		return "Rifleman"
	end
	if rng then
		return ids[rng:NextInteger(1, #ids)]
	end
	return ids[math.random(1, #ids)]
end

function NPCSquads.costOf(enemyId: string): number
	return EncounterHierarchy.enemyPressureCost(enemyId)
end

function NPCSquads.roleForEnemy(enemyId: string): string
	return ROLE_BY_ID[enemyId] or "infantry"
end

local function formationOffset(role: string, index: number): Vector3
	-- The commander anchors the center, infantry form a tight wedge, support hangs back,
	-- heavies take a forward shoulder. Spawn clustering then naturally puts them in one squad.
	if role == "command" then
		return Vector3.new(0, 0, 0)
	end
	if role == "support" then
		return Vector3.new(index % 2 == 0 and -7 or 7, 0, 11)
	end
	if role == "heavy" then
		return Vector3.new(index % 2 == 0 and -8 or 8, 0, -3)
	end
	local angle = (index / 6) * math.pi * 2
	local radius = 5 + (index % 2) * 2
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

-- Returns (members, pressureCost). The composition is budget-shaped before any spawn happens:
-- infantry first, support second, elite slots last; if the economy cannot pay for elite flavor
-- the squad still arrives as a coherent infantry unit rather than a random singleton.
function NPCSquads.composeWave(request: WaveRequest): ({ WaveMember }, number)
	local phase = request.phase or "contact"
	local doctrine = EncounterHierarchy.waveDoctrine(phase)
	local escalation = math.clamp(math.floor(request.escalation or 0), 0, 3)
	local difficulty = request.difficulty or "Normal"
	local maxCost = math.max(0, request.maxCost or 4)
	local maxMembers = math.max(1, math.min(request.maxMembers or doctrine.maxMembers or 4, SQUAD_MAX_SIZE))
	local rng = request.seed and Random.new(request.seed) or nil
	local eliteFrequency = EncounterHierarchy.DifficultyEliteFrequency[difficulty] or 0.10
	-- Easy keeps elite flavor scarce, Normal is the doctrine baseline, Hard/Extreme receive
	-- visibly combined arms. HP never inflates here — frequency and composition carry difficulty.
	local eliteScale = 0.25 + eliteFrequency * 3 + escalation * 0.10

	local ids: { string } = {}
	local cost = 0
	local function tryAdd(enemyId: string): boolean
		local c = NPCSquads.costOf(enemyId)
		if #ids >= maxMembers or cost + c > maxCost + 0.001 then
			return false
		end
		table.insert(ids, enemyId)
		cost += c
		return true
	end

	local coreRange = doctrine.core or { 2, 3 }
	local coreMin = math.max(1, coreRange[1] or 2)
	local coreMax = math.max(coreMin, coreRange[2] or coreMin)
	local desiredCore = coreMin
	if coreMax > coreMin then
		desiredCore = coreMin + math.floor(rand01(rng) * (coreMax - coreMin + 1))
	end
	if request.sizeHint then
		desiredCore = math.clamp((request.sizeHint or desiredCore) - 1, coreMin, coreMax)
	end
	if (request.playerCount or 1) >= 3 then
		desiredCore = math.min(coreMax, desiredCore + 1)
	end
	desiredCore = math.min(desiredCore, maxMembers)
	for _ = 1, desiredCore do
		tryAdd(pick(doctrine.infantry or { "Rifleman" }, rng))
	end

	-- Support is the readability layer: Marksman overwatch or Scout pressure/flank beacon.
	local supportChance = (doctrine.supportChance or 0) * (phase == "recon" and 0.7 or 1)
	if rand01(rng) < supportChance then
		tryAdd(pick(doctrine.support or { "Marksman" }, rng))
	end

	-- Elite slots are escalation-dependent and deliberately occasional. Officer first in objective
	-- assaults (coordination), Heavy first in extraction (visible hold-or-die pressure).
	local commandChance = (doctrine.commandChance or 0) * eliteScale
	local heavyChance = (doctrine.heavyChance or 0) * eliteScale
	if phase == "extraction" and escalation >= 2 then
		heavyChance += 0.12 * eliteScale
	end
	if phase == "assault" and escalation >= 2 then
		commandChance += 0.12 * eliteScale
	end
	local wantCommand = rand01(rng) < commandChance
	local wantHeavy = rand01(rng) < heavyChance
	if phase == "extraction" then
		if wantHeavy then tryAdd("Heavy") end
		if wantCommand then tryAdd("Officer") end
	else
		if wantCommand then tryAdd("Officer") end
		if wantHeavy then tryAdd("Heavy") end
	end

	-- Spend leftover seats on the infantry core. This keeps timing/composition readable without
	-- inflating concurrent population beyond the existing cap.
	while #ids < maxMembers do
		local before = #ids
		tryAdd(pick(doctrine.infantry or { "Rifleman" }, rng))
		if #ids == before then
			break
		end
	end

	if #ids < 2 then
		return {}, 0
	end
	local members: { WaveMember } = {}
	for i, enemyId in ipairs(ids) do
		local role = NPCSquads.roleForEnemy(enemyId)
		table.insert(members, {
			id = enemyId,
			role = role,
			offset = formationOffset(role, i),
		})
	end
	return members, cost
end

function NPCSquads.debugCount(): number
	local n = 0
	for _ in pairs(squads) do
		n += 1
	end
	return n
end

return NPCSquads
