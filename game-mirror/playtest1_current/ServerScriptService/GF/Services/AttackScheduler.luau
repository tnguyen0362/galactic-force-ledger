--!strict
-- AttackScheduler: shared boss/vehicle attack lifecycle and selection framework (spec sections
-- 25/48/51). Explicit lifecycle states, encounter-level special-pressure budget, health-dependent
-- aggression, anti-repetition with exponential recency penalty, feasibility filtering first.
--
-- Lifecycle: Ready -> Preparation -> Telegraph -> Active -> Recovery -> Cooldown -> Ready
-- Telegraph windows NEVER shrink with aggression — survival-critical tells stay honest (spec 50).
-- Aggression compresses cooldowns and recovery only.

local AttackScheduler = {}

export type AttackDef = {
	id: string,
	requiredCapability: string?, -- component capability gate (nil = always available)
	minRange: number?,
	maxRange: number?,
	telegraphTime: number,
	activeTime: number?,
	recoveryTime: number,
	cooldown: number,
	pressureCost: number,
	weight: number,
	requiresLineOfSight: boolean?,
	fire: (state: any, target: any) -> (), -- controller-provided execution; receives scheduler state
}

export type SchedulerState = {
	attacks: { AttackDef },
	phase: string, -- Ready/Preparation/Telegraph/Active/Recovery
	activeAttack: AttackDef?,
	phaseUntil: number,
	cooldowns: { [string]: number }, -- attack id -> ready-at clock
	history: { { id: string, at: number } },
	pressureActive: number,
	aggression: number, -- 1.0 baseline; >1 as the entity takes damage
	maxPressure: number,
	busy: boolean,
}

local HISTORY_WINDOW = 30 -- seconds of history for recency penalty
local GAMMA = 0.55 -- recency decay per prior use within window
local LAMBDA = 1.6 -- penalty weight

function AttackScheduler.new(attackDefs: { AttackDef }, maxPressure: number): SchedulerState
	return {
		attacks = attackDefs,
		phase = "Ready",
		activeAttack = nil,
		phaseUntil = 0,
		cooldowns = {},
		history = {},
		pressureActive = 0,
		aggression = 1,
		maxPressure = maxPressure or 2,
		busy = false,
	}
end

-- recency penalty R_a = sum gamma^i over recent uses (spec section 51)
local function recencyPenalty(state: SchedulerState, attackId: string, now: number): number
	local penalty = 0
	local idx = 0
	for i = #state.history, 1, -1 do
		local h = state.history[i]
		if now - h.at > HISTORY_WINDOW then break end
		if h.id == attackId then
			penalty += GAMMA ^ idx
			idx += 1
		end
	end
	return penalty
end

-- feasibility first (spec section 51: never select attacks that cannot execute)
function AttackScheduler.feasible(state: SchedulerState, attack: AttackDef, ctx: any): boolean
	local now = os.clock()
	if (state.cooldowns[attack.id] or 0) > now then return false end
	if attack.requiredCapability and ctx.capabilityAvailable then
		if not ctx.capabilityAvailable(attack.requiredCapability) then return false end
	end
	if ctx.dist and attack.minRange and ctx.dist < attack.minRange then return false end
	if ctx.dist and attack.maxRange and ctx.dist > attack.maxRange then return false end
	if attack.requiresLineOfSight and ctx.hasLineOfSight == false then return false end
	if state.pressureActive + attack.pressureCost > state.maxPressure then return false end
	return true
end

-- scoring: weight base, recency penalty, range compatibility bonus (spec section 51 simplified —
-- controllers pass contextual bonuses through ctx.scoreBonus[attackId])
local function score(state: SchedulerState, attack: AttackDef, ctx: any, now: number): number
	local s = attack.weight - LAMBDA * recencyPenalty(state, attack.id, now)
	if ctx.scoreBonus and ctx.scoreBonus[attack.id] then
		s += ctx.scoreBonus[attack.id]
	end
	return s
end

-- main entry: call from the controller's tick. Returns the attack entered Telegraph, or nil.
-- aggression compresses cooldown/recovery but NEVER telegraph (spec section 50: T_warning invariant)
function AttackScheduler.step(state: SchedulerState, ctx: any): AttackDef?
	local now = os.clock()
	if state.phase ~= "Ready" then
		if now >= state.phaseUntil then
			local active = state.activeAttack
			if state.phase == "Telegraph" and active then
				state.phase = "Active"
				state.phaseUntil = now + (active.activeTime or 0.1)
				state.pressureActive += active.pressureCost
				-- fire at the START of active — damage timing matches the visual communication
				active.fire(ctx, ctx.target)
			elseif state.phase == "Active" and active then
				state.phase = "Recovery"
				-- aggression compresses recovery within fair bounds (spec section 52)
				local compressed = active.recoveryTime / math.max(1, state.aggression)
				state.phaseUntil = now + compressed
				state.pressureActive = math.max(0, state.pressureActive - active.pressureCost)
			elseif state.phase == "Recovery" then
				state.phase = "Ready"
				state.activeAttack = nil
				state.busy = false
			end
		end
		return nil
	end
	-- select: feasible only, weighted with recency penalty, controlled stochastic choice
	local feasibleList = {}
	for _, attack in state.attacks do
		if AttackScheduler.feasible(state, attack, ctx) then
			table.insert(feasibleList, attack)
		end
	end
	if #feasibleList == 0 then return nil end
	local best, bestScore = nil, -math.huge
	local totalExp, scores = 0, {}
	for _, attack in feasibleList do
		local s = score(state, attack, ctx, now)
		scores[attack] = s
		if s > bestScore then bestScore = s; best = attack end
	end
	-- softmax with temperature over feasible set (spec section 51), numerically stabilized
	local T = 1.2
	for _, attack in feasibleList do
		totalExp += math.exp((scores[attack] - bestScore) / T)
	end
	local roll = math.random() * totalExp
	local chosen = best
	local acc = 0
	for _, attack in feasibleList do
		acc += math.exp((scores[attack] - bestScore) / T)
		if roll <= acc then chosen = attack break end
	end
	-- enter telegraph: the tell duration is the CONFIGURED duration, never aggression-compressed
	state.activeAttack = chosen
	state.phase = "Telegraph"
	state.phaseUntil = now + chosen.telegraphTime
	state.busy = true
	-- cooldown starts at selection so overlapping windows can't chain
	state.cooldowns[chosen.id] = now + chosen.cooldown / math.max(1, state.aggression * 0.85)
	table.insert(state.history, { id = chosen.id, at = now })
	if #state.history > 24 then table.remove(state.history, 1) end
	return chosen
end

-- cancel the active attack (component destruction interrupts invalid pending actions, spec 37)
function AttackScheduler.interrupt(state: SchedulerState, reason: string?)
	if state.activeAttack then
		state.pressureActive = math.max(0, state.pressureActive - (state.activeAttack.pressureCost or 0))
	end
	state.phase = "Ready"
	state.activeAttack = nil
	state.busy = false
end

-- health-dependent aggression (spec section 52): A(h) = A_min + (A_max - A_min)*(1-h)^p
function AttackScheduler.updateAggression(state: SchedulerState, healthFrac: number, aMin: number?, aMax: number?, p: number?)
	state.aggression = (aMin or 1) + ((aMax or 1.6) - (aMin or 1)) * (1 - healthFrac) ^ (p or 1.4)
end

return AttackScheduler
