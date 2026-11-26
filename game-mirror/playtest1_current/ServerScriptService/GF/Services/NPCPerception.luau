--!strict
-- NPCPerception: legitimate awareness for Ascendancy soldiers (spec sections 17-20).
-- The server knows where players are; soldiers only know what they have seen, heard, or been
-- told. This module owns that boundary. Everything the tactical layer believes about players
-- flows through these records — never raw character positions.
--
-- Core model:
--   visual detection is EVIDENCE ACCUMULATION, not binary cone+LOS. Exposure, distance, angle,
--   target motion, and alertness scale the rate. A soldier glancing at a half-hidden distant
--   player needs time to recognise the threat; one staring at a sprinting close target snaps on.
--   memory is a TargetMemory record per player with confidence decay, uncertainty growth, and
--   bounded velocity extrapolation. Hidden movement is never tracked.
--   auditory events write approximate positions with distance-scaled spatial error.
--   allied reports preserve the original observation timestamp and uncertainty — a radio
--   relay does not turn stale guesswork into fresh perfect positions.

local NPCPerception = {}

-- ---------------------------------------------------------------------------
-- tuning constants (spec section 17 with initial-reference calibration; Stage 9 difficulty
-- scaling multiplies some of these — keep them in one place)
-- ---------------------------------------------------------------------------
local DETECT_THRESHOLD = 1.0 -- evidence required for full detection
local EVIDENCE_DECAY = 0.25 -- per second evidence bleed when the target is not visible
local BASE_DETECT_RATE = 1.4 -- evidence/sec for an ideal exposure (close, centered, fully visible)
local CONFIDENCE_TAU = 5.0 -- memory confidence decay time constant (seconds)
local UNCERTAINTY_GROWTH = 1.1 -- studs of additional position uncertainty per second of staleness
local UNCERTAINTY_BASE = 2.0 -- floor uncertainty even for a fresh direct sighting
local PREDICTION_MAX_AGE = 2.5 -- velocity extrapolation is bounded: soldiers anticipate a few
-- seconds of continued movement, not indefinite travel
local REPORT_CONFIDENCE_CAP = 0.65 -- allied reports never exceed this confidence
local PERIPHERAL_ALIGNMENT = -0.2 -- cos(theta) floor for any visual detection at all (~101 deg half-angle)

export type TargetMemory = {
	position: Vector3,
	velocity: Vector3,
	observedAt: number,
	confidence: number, -- confidence AT observation time; decayed on read
	uncertainty: number, -- spatial uncertainty at observation time (studs)
	obsType: string, -- "visual" | "audio" | "report"
	threat: number, -- damage-driven hostility weighting
}

export type PerceptionState = {
	evidence: { [Player]: number },
	memory: { [Player]: TargetMemory },
	alertness: number, -- 0 relaxed .. 1 combat-alert; raised by contact/events, slow decay
	lastVisible: { [Player]: number }, -- os.clock() of last direct visual contact
}

function NPCPerception.newState(): PerceptionState
	return {
		evidence = {},
		memory = {},
		alertness = 0,
		lastVisible = {},
	}
end

-- ---------------------------------------------------------------------------
-- memory reads: time-aware accessors. These are the ONLY ways tactical code should
-- consume memory — raw fields are observation-time snapshots, not current knowledge.
-- ---------------------------------------------------------------------------
function NPCPerception.confidenceNow(mem: TargetMemory, now: number): number
	local age = now - mem.observedAt
	return mem.confidence * math.exp(-age / CONFIDENCE_TAU)
end

function NPCPerception.uncertaintyNow(mem: TargetMemory, now: number): number
	local age = now - mem.observedAt
	return mem.uncertainty + UNCERTAINTY_GROWTH * age
end

-- estimated current position: bounded velocity extrapolation. Soldiers anticipate continued
-- movement for a couple of seconds, then the estimate just grows fuzzier — never infinite leads.
function NPCPerception.estimatePosition(mem: TargetMemory, now: number): Vector3
	local age = now - mem.observedAt
	local extrapolate = math.min(age, PREDICTION_MAX_AGE)
	return mem.position + mem.velocity * extrapolate
end

-- ---------------------------------------------------------------------------
-- visual evidence accumulation. exposure is the weighted visibility computed by the caller's
-- raycasts (0..1); alignment is facing dot direction (-1..1); targetSpeed in studs/sec.
-- Returns the new evidence level.
-- ---------------------------------------------------------------------------
function NPCPerception.accumulate(
	state: PerceptionState,
	player: Player,
	exposure: number,
	alignment: number,
	distance: number,
	sightRange: number,
	targetSpeed: number,
	dt: number
): number
	local now = os.clock()
	if exposure <= 0 or alignment < PERIPHERAL_ALIGNMENT then
		-- not visible at all: evidence bleeds
		local e = (state.evidence[player] or 0) - EVIDENCE_DECAY * dt
		state.evidence[player] = math.max(0, e)
		return state.evidence[player]
	end
	-- rate factors (spec: lambda = base * F_distance * F_angle * F_visibility * F_alertness [*F_motion])
	local fDistance = math.clamp(1.6 - distance / math.max(1, sightRange), 0.25, 1.6)
	local fAngle = 0.35 + 0.65 * math.clamp((alignment - PERIPHERAL_ALIGNMENT) / (1 - PERIPHERAL_ALIGNMENT), 0, 1)
	local fVisibility = math.clamp(exposure, 0.05, 1)
	local fMotion = targetSpeed > 14 and 1.3 or (targetSpeed > 2 and 1.0 or 0.65)
	local fAlertness = 0.65 + 0.7 * state.alertness
	local lambda = BASE_DETECT_RATE * fDistance * fAngle * fVisibility * fMotion * fAlertness
	local e = (state.evidence[player] or 0) + lambda * dt
	-- already-detected targets stay detected while visible (evidence pinned above threshold)
	state.evidence[player] = math.min(1.35, e)
	return state.evidence[player]
end

function NPCPerception.isDetected(state: PerceptionState, player: Player): boolean
	return (state.evidence[player] or 0) >= DETECT_THRESHOLD
end

-- write a visual observation into memory: direct sightings are high-confidence, low-uncertainty
function NPCPerception.observeVisual(state: PerceptionState, player: Player, position: Vector3, velocity: Vector3)
	state.memory[player] = {
		position = position,
		velocity = velocity,
		observedAt = os.clock(),
		confidence = 1.0,
		uncertainty = UNCERTAINTY_BASE,
		obsType = "visual",
		threat = (state.memory[player] and state.memory[player].threat) or 0,
	}
	state.lastVisible[player] = os.clock()
	state.alertness = math.min(1, state.alertness + 0.4)
end

-- ---------------------------------------------------------------------------
-- auditory perception (spec section 18): approximate source, distance-scaled error.
-- loudness 0..1 is the event strength after conceptual attenuation, computed by the caller.
-- ---------------------------------------------------------------------------
function NPCPerception.hearEvent(state: PerceptionState, sourcePosition: Vector3, distance: number, loudness: number, player: Player?)
	-- spatial error grows with distance: nearby gunfire is located well, distant fire is a direction
	local spatialError = 3 + distance * 0.25
	local jitter = Vector3.new((math.random() - 0.5) * spatialError, 0, (math.random() - 0.5) * spatialError)
	local confidence = math.clamp(0.35 + loudness * 0.4, 0.2, 0.75)
	-- auditory never overrides a fresher visual observation of the same player
	if player then
		local existing = state.memory[player]
		if existing and existing.obsType == "visual" and (os.clock() - existing.observedAt) < 3 then
			state.alertness = math.min(1, state.alertness + 0.25)
			return
		end
		state.memory[player] = {
			position = sourcePosition + jitter,
			velocity = Vector3.zero,
			observedAt = os.clock(),
			confidence = confidence,
			uncertainty = spatialError,
			obsType = "audio",
			threat = (existing and existing.threat) or 0,
		}
	end
	state.alertness = math.min(1, state.alertness + 0.3)
end

-- ---------------------------------------------------------------------------
-- allied reports (spec section 19): preserve original timestamps and uncertainty.
-- Reports never create perfect knowledge — they hand the receiver a fuzzy, aging estimate.
-- ---------------------------------------------------------------------------
function NPCPerception.receiveReport(state: PerceptionState, player: Player, report: TargetMemory)
	local existing = state.memory[player]
	-- only accept if the report is fresher than what we already believe
	if existing and existing.observedAt >= report.observedAt then
		return
	end
	state.memory[player] = {
		position = report.position,
		velocity = report.velocity,
		observedAt = report.observedAt, -- ORIGINAL timestamp preserved: the report ages honestly
		confidence = math.min(report.confidence, REPORT_CONFIDENCE_CAP),
		uncertainty = math.max(report.uncertainty, 6), -- radio compression never sharpens
		obsType = "report",
		threat = report.threat,
	}
	state.alertness = math.min(1, state.alertness + 0.2)
end

-- damage awareness: being shot is unambiguous evidence of a hostile in a direction.
-- Soldiers don't need to see their shooter to know roughly where fire came from.
function NPCPerception.noteDamage(state: PerceptionState, player: Player, estimatedSource: Vector3)
	local existing = state.memory[player]
	state.memory[player] = {
		position = estimatedSource + Vector3.new((math.random() - 0.5) * 8, 0, (math.random() - 0.5) * 8),
		velocity = Vector3.zero,
		observedAt = os.clock(),
		confidence = 0.8, -- pain is convincing but not precise
		uncertainty = 8,
		obsType = "visual", -- treated as firm knowledge for response purposes
		threat = ((existing and existing.threat) or 0) + 1,
	}
	state.evidence[player] = math.max(state.evidence[player] or 0, DETECT_THRESHOLD) -- damage fully detects
	state.alertness = 1
end

-- forget a memory entirely (target left the fight, died, or search exhausted)
function NPCPerception.forget(state: PerceptionState, player: Player)
	state.memory[player] = nil
	state.evidence[player] = nil
	state.lastVisible[player] = nil
end

-- alertness decay: call once per decision tick
function NPCPerception.cooldown(state: PerceptionState, dt: number)
	state.alertness = math.max(0, state.alertness - dt / 30) -- ~30s from full alert to relaxed
end

return NPCPerception
