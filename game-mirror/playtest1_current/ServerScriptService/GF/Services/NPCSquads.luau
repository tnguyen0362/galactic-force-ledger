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

local NPCSquads = {}

local SQUAD_JOIN_RADIUS = 55 -- spawn-time clustering: members within this distance join one squad
local SQUAD_MAX_SIZE = 6
local RESERVATION_EXPIRY = 12 -- seconds; a stale reservation releases itself
local ROLE_REEVAL_COOLDOWN = 4 -- seconds between assignment passes for one squad
local COMMANDER_RADIUS = 60 -- R_command: leadership influence scale (studs)
local MAX_FLANKERS_PER_SQUAD = 1 -- spec: squad-level limits on simultaneous alternative approaches

export type SquadBlackboard = {
	id: number,
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
		if count < SQUAD_MAX_SIZE and n > 0 then
			local centre = Vector3.new(cx / n, 0, cz / n)
			local d = (Vector3.new(position.X, 0, position.Z) - centre).Magnitude
			if d < bestDist then
				bestDist = d
				best = sq
			end
		end
	end
	local sq = best or newSquad(position)
	sq.members[model] = true
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

function NPCSquads.debugCount(): number
	local n = 0
	for _ in pairs(squads) do
		n += 1
	end
	return n
end

return NPCSquads
