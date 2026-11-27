--!strict
-- EnemyAnimClient v2 — authoritative client-side procedural animation for Ascendancy infantry.
--
-- Architecture (per assignment): enemy rigs are kinematic server actors. All joint animation is
-- computed HERE on each client from observed replicated displacement — zero additional network
-- traffic, no server C0 churn, animation presentation fully separate from authoritative AI.
-- The server never writes joint transforms; this is the ONE authoritative animation writer.
--
-- Locomotion math (per spec):
--   GaitFrequency = |v| / L     (L = reference stride length)
--   Phase += 2π · GaitFrequency · dt
--   blending: x += (x_target - x) · (1 - exp(-dt/τ))   — frame-rate independent
--
-- Layered pose: lower body = locomotion (hips/knees/ankles), upper body = weapon-hold + aim
-- (waist/neck/shoulders independent of locomotion), so enemies move while tracking targets.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- stride length L in studs — tuned to the rig's leg length (~2.6 stud inseam)
local STRIDE = 2.4
local TAU_GAIT = 0.18 -- amplitude blend time constant
local TAU_AIM = 0.12

type JointMap = { [string]: { motor: Motor6D, base: CFrame } }
type RigState = {
	joints: JointMap,
	phase: number,
	last: Vector3,
	speed: number, -- smoothed
	amp: number, -- blended gait amplitude 0..1
	aimYaw: number, -- blended aim yaw relative to body
	aimPitch: number,
	profile: any,
	rig: Model,
	health: number,
	hitPulse: number,
	firePulse: number,
	deathT: number?, -- time since death started, nil while alive
	prevPos: Vector3?,
	hero: boolean?,
}

local tracked: { [Model]: RigState } = {}

-- archetype animation personalities (spec §4) — multipliers on the shared infrastructure
local PROFILES = {
	Rifleman = { freqMul = 1.0, ampMul = 1.0, bobMul = 1.0, armSwing = 1.0, aimSharp = 1.0 },
	Scout = { freqMul = 1.25, ampMul = 1.1, bobMul = 1.15, armSwing = 1.2, aimSharp = 1.2 }, -- vanguard: athletic
	Vanguard = { freqMul = 1.25, ampMul = 1.1, bobMul = 1.15, armSwing = 1.2, aimSharp = 1.2, leanBias = 0.09 }, -- assault posture: forward intent
	Heavy = { freqMul = 0.8, ampMul = 0.85, bobMul = 1.3, armSwing = 0.6, aimSharp = 0.7, stanceRoll = 0.06 }, -- planted wide stance
	Marksman = { freqMul = 0.95, ampMul = 0.9, bobMul = 0.7, armSwing = 0.7, aimSharp = 1.4 }, -- stable aim
	Officer = { freqMul = 0.9, ampMul = 0.85, bobMul = 0.8, armSwing = 0.8, aimSharp = 1.1 }, -- composed
	Commander = { freqMul = 0.9, ampMul = 0.85, bobMul = 0.8, armSwing = 0.8, aimSharp = 1.1 },
	-- Gate D expansion: Spectre profiles — precision operatives: tight gait, minimal
	-- wasted motion, fast aim acquisition. Support is the most deliberate of the five.
	SpectreLeader = { freqMul = 1.0, ampMul = 0.85, bobMul = 0.65, armSwing = 0.7, aimSharp = 1.35 },
	SpectreAssault = { freqMul = 1.15, ampMul = 0.95, bobMul = 0.8, armSwing = 0.85, aimSharp = 1.25 },
	SpectreWeapons = { freqMul = 0.9, ampMul = 0.9, bobMul = 1.0, armSwing = 0.6, aimSharp = 1.2 },
	SpectrePrecision = { freqMul = 0.85, ampMul = 0.8, bobMul = 0.5, armSwing = 0.55, aimSharp = 1.5 },
	SpectreSupport = { freqMul = 0.95, ampMul = 0.85, bobMul = 0.75, armSwing = 0.7, aimSharp = 1.15 },
	-- Revenant profiles — specialist hunters: aggressive cadence, sharp directional
	-- commitment, the fastest aim in the roster. Defense is anchored and heavy.
	RevenantLeader = { freqMul = 1.05, ampMul = 0.9, bobMul = 0.6, armSwing = 0.75, aimSharp = 1.5 },
	RevenantAssault = { freqMul = 1.3, ampMul = 1.05, bobMul = 0.9, armSwing = 0.95, aimSharp = 1.4 },
	RevenantWeapons = { freqMul = 0.95, ampMul = 0.95, bobMul = 1.05, armSwing = 0.6, aimSharp = 1.3 },
	RevenantPrecision = { freqMul = 0.9, ampMul = 0.85, bobMul = 0.45, armSwing = 0.5, aimSharp = 1.65 },
	RevenantDefense = { freqMul = 0.75, ampMul = 0.8, bobMul = 1.2, armSwing = 0.5, aimSharp = 1.1 },
}
local ELITE_MUL = { freqMul = 1.05, ampMul = 0.9, bobMul = 0.75, armSwing = 0.85, aimSharp = 1.3 } -- spectre/revenant precision

local function profileFor(model: Model)
	local id = model:GetAttribute("EnemyId")
	local base = PROFILES[id] or PROFILES.Rifleman
	if model:GetAttribute("Tier") == "Elite" then
		-- elites: blend toward precision profile
		return {
			freqMul = base.freqMul * ELITE_MUL.freqMul,
			ampMul = base.ampMul * ELITE_MUL.ampMul,
			bobMul = base.bobMul * ELITE_MUL.bobMul,
			armSwing = base.armSwing * ELITE_MUL.armSwing,
			aimSharp = base.aimSharp * ELITE_MUL.aimSharp,
		}
	end
	return base
end

local function indexJoints(rig: Model): JointMap
	local joints: JointMap = {}
	for _, d in rig:GetDescendants() do
		if d:IsA("Motor6D") then
			joints[d.Name] = { motor = d, base = d.C0 }
		end
	end
	return joints
end

local function rigOf(model: Model): Model?
	for _, c in model:GetChildren() do
		if c:IsA("Model") and c:GetAttribute("GFEnemyRig") then
			return c
		end
	end
	return nil
end

local function setJoint(joints: JointMap, name: string, rot: CFrame)
	local j = joints[name]
	if j then
		-- Transform rotates at the anatomical pivot (C0 is joint-located in rig v2)
		j.motor.C0 = j.base * rot
	end
end

local function clearJoints(joints: JointMap)
	for _, j in joints do
		j.motor.C0 = j.base
	end
end

-- exponential blend helper: frame-rate independent
local function blend(current: number, target: number, dt: number, tau: number): number
	return target + (current - target) * math.exp(-dt / tau)
end

-- ============================================================================================
-- HERO SQUAD POSE (rigs with GF_HeroBaked): Blender-authored Hero_Asc_* troopers.
-- Joint sign convention MEASURED on these rigs (forward = -Z): +Hip/+Shoulder/+Elbow swing the limb
-- forward/up; KNEE FLEXION IS NEGATIVE; +Waist/+RootJoint lean BACK (forward lean = negative);
-- +Neck looks up; +Ankle = toes up.  Arms are authored in a two-hand rifle-ready bind, so every arm
-- value below is a DELTA from that bind: both shoulders rotate together about the shoulder line, which
-- carries the rifle (RifleGrip on HandR) and the left-hand support grip as one rigid unit.
--
-- Stances come from standard infantry doctrine (FM 3-22.9 / MCRP 3-01A ready + field positions):
--   low ready   muzzle ~30-45deg down, upright           -> patrol / return (relaxed carry)
--   tactical    muzzle slightly down, soft knees, lean   -> investigate / search / guard
--   combat aim  shouldered, hunched forward, knees bent  -> engage (head tracks, torso bladed to target)
--   cover crouch deep crouch, torso up, muzzle on target -> take-cover
--   kneel       marksman holds low when planted
--
-- LOCOMOTION (v2, planted-foot gait).  The old gait ran a 2.4-stud stride at ~5 Hz, so legs flailed.  Here
-- cadence and stride come from speed and leg length, and every leg is posed by closed-form two-bone IK so
-- the stance foot travels backwards at exactly body speed (no foot skating):
--   * f(v)  = (0.75 + 0.07 v) * freqMul cycles/s,  D = v / f studs per cycle,  duty factor 0.60 walk -> 0.36 run
--   * stance: ankle slides +sD/2 -> -sD/2 under the hip (heel strike -> toe off), knee loads then pushes off
--   * swing : ankle returns -sD/2 -> +sD/2 with a knee-lift arc (bigger when running), foot dorsiflexes to clear
--   * pelvis height falls out of the stance leg geometry (bob), flight phase while running lifts it
--   * pelvis yaws with the legs and the waist counter-yaws so the rifle shoulders stay on target
--   * strafe/backpedal: pelvis turns toward the travel line (legs still run "forward"); backwards flips the phase
-- crouch c: knee flex 2h; solving hip for the same ankle target gives hip flex ~h and drops the pelvis by geometry.
-- ============================================================================================
local HERO_STANCE = {
	Rifleman = { crouch = 0, hunch = 0 },
	Scout = { crouch = 0.05, hunch = 0.15 }, -- athletic forward lean
	Marksman = { crouch = 0.15, hunch = -0.1, kneelWhenPlanted = true },
	Heavy = { crouch = 0.1, hunch = 0.25 }, -- braced, weight forward
	Officer = { crouch = -0.1, hunch = -0.2 }, -- upright, commanding
}
-- thigh/shin length (studs) of the Rifleman rig, scaled per role by body height
local THIGH, SHIN = 1.72, 1.68
local LEG_SCALE = { Rifleman = 1.0, Scout = 0.96, Marksman = 1.05, Heavy = 1.09, Officer = 1.05 }
-- sign of pelvis roll toward the swing side (verify in Play: hip should drop on the swing-leg side)
local ROLL_SIGN = 1

local function smooth01(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- two-bone IK for a straight-ahead sagittal leg: hip pitch that puts the ankle `x` studs ahead of the hip with knee flex k
local function solveHip(x: number, k: number, T: number, S: number): number
	local A = T + S * math.cos(k)
	local B = S * math.sin(k)
	local R = math.sqrt(A * A + B * B)
	return math.atan2(B, A) + math.asin(math.clamp(x / R, -0.92, 0.92))
end

-- one leg's gait channels at cycle position u (0..1): ankle x offset, knee flex, ankle extra, hip lift, ground weight
local function legCycle(u: number, s: number, D: number, r: number): (number, number, number, number, number)
	local kHeel = 0.08 + 0.10 * r
	local kLoad = 0.12 + 0.20 * r
	local kPush = 0.25 + 0.35 * r
	local pushAnkle = -(0.30 + 0.15 * r)
	if u < s then
		local w = u / s
		local x = (s * D * 0.5) * (1 - 2 * w)
		local k = kHeel + kLoad * math.sin(math.pi * math.min(w / 0.7, 1)) + kPush * smooth01((w - 0.7) / 0.3)
		local ank = pushAnkle * smooth01((w - 0.72) / 0.28) + 0.08 * (1 - smooth01(w / 0.15))
		local sw = smooth01(w / 0.20) * smooth01((1 - w) / 0.30)
		return x, k, ank, 0, sw
	end
	local t = (u - s) / (1 - s)
	local x = -(s * D * 0.5) + s * D * smooth01(t) - (0.15 + 0.90 * r) * math.sin(math.pi * t) -- foot trails under the hip: keeps the thigh low
	local kToe = kHeel + kPush
	local k = kToe + (kHeel - kToe) * smooth01(t) + (0.50 + 0.50 * r) * math.sin(math.pi * t ^ 0.8)
	local ank = pushAnkle + (0.12 - pushAnkle) * smooth01(t)
	local lift = (0.05 + 0.12 * r) * math.sin(math.pi * t)
	return x, k, ank, lift, 0
end

local function heroPose(model: Model, state: RigState, dt: number, c: any)
	local st: any = state
	local J = state.joints
	local cfg = HERO_STANCE[c.enemyId] or HERO_STANCE.Rifleman
	local prof = state.profile
	local now = os.clock()

	-- ---- velocity from replicated displacement (positions arrive in network-rate steps, so measure
	-- speed/direction across each ACTUAL position change instead of per frame, then smooth)
	local pos: Vector3 = c.pos
	if not st.hLastPos then
		st.hLastPos, st.hLastT, st.hSpeed, st.hPhase = pos, now, 0, st.phase
		st.hDir, st.hDirSign, st.pYaw = Vector3.zero, 1, 0
	end
	local moved = pos - st.hLastPos
	local flat = Vector3.new(moved.X, 0, moved.Z)
	local rawSpeed = nil
	if flat.Magnitude > 0.02 then
		local span = now - st.hLastT
		if span < 0.3 then
			rawSpeed = flat.Magnitude / math.max(span, 1 / 120)
			st.hDir = st.hDir:Lerp(flat.Unit, 0.5)
		else
			st.hDir = flat.Unit -- first step after standing: no reliable interval yet
		end
		st.hLastPos, st.hLastT = pos, now
	elseif now - st.hLastT > 0.3 then
		rawSpeed = 0
	end
	if rawSpeed then
		st.hSpeed = blend(st.hSpeed, math.min(rawSpeed, 40), dt, 0.14)
	end
	local v: number = st.hSpeed
	local w = smooth01((v - 0.3) / 1.5) -- locomotion weight: 0 idle .. 1 moving
	local look, right = c.pivot.LookVector, c.pivot.RightVector
	local dirU = st.hDir.Magnitude > 0.05 and st.hDir.Unit or Vector3.zero
	local fwd, lat = dirU:Dot(look), dirU:Dot(right) -- lat > 0: travelling to the troop's right
	local alpha = math.atan2(lat, fwd) -- travel angle from facing, + = right
	if st.hDirSign > 0 and math.abs(alpha) > 2.2 then
		st.hDirSign = -1
	elseif st.hDirSign < 0 and math.abs(alpha) < 1.9 then
		st.hDirSign = 1
	end
	local dirSign: number = st.hDirSign
	local alphaFold = dirSign > 0 and alpha or (alpha - math.pi * (alpha > 0 and 1 or -1))
	local pYawTarget = -math.clamp(alphaFold, -1.2, 1.2) * 0.65 * w
	st.pYaw = blend(st.pYaw, pYawTarget, dt, 0.18)

	-- ---- stance targets by authoritative AI state
	local cT, hT, dT = 0, 0, 0
	if c.relaxed then
		cT, hT, dT = 0.03, 0.1, -0.45
	elseif c.investigating then
		cT, hT, dT = 0.25, 0.35, -0.15
	elseif c.guarding then
		cT, hT, dT = 0.3, 0.3, -0.1
	elseif c.inCover then
		cT, hT, dT = 0.85, 0.2, 0
	else
		cT, hT, dT = (v > 1.2 and 0.25 or 0.4), 0.5, 0
	end
	if not c.relaxed and c.engaged then
		dT = state.aimPitch * 0.9
	end
	if cfg.kneelWhenPlanted and v <= 1.2 and not c.relaxed and not c.investigating then
		cT = math.max(cT, 0.75)
	end
	cT = math.clamp(cT + cfg.crouch, 0, 1)
	hT = math.clamp(hT + cfg.hunch, 0, 1)

	st.crouch = blend(st.crouch or 0, cT, dt, 0.3)
	st.hunch = blend(st.hunch or 0, hT, dt, 0.3)
	st.ready = blend(st.ready or dT, dT, dt, 0.15)

	-- ---- gait clock: cadence from speed, direction from travel
	local ls = LEG_SCALE[c.enemyId] or 1
	local T, S = THIGH * ls, SHIN * ls
	local freq = (0.75 + 0.07 * v) * prof.freqMul
	if v > 0.3 then
		st.hPhase += dirSign * 2 * math.pi * freq * dt
	end
	local cyc = st.hPhase / (2 * math.pi)
	local uL = cyc - math.floor(cyc)
	local uR = (cyc + 0.5) - math.floor(cyc + 0.5)
	local r = smooth01((v - 8) / 7) -- walk -> run
	local s = 0.60 - 0.24 * r -- duty factor (stance fraction)
	local D = v / math.max(freq, 0.01) -- studs per full cycle

	local h = st.crouch
	local kc = 2 * h
	local lean = ((0.02 + 0.13 * r) + (prof.leanBias or 0) * 0.5) * w
	local xL, kL, aL, liftL, swL = legCycle(uL, s, D, r)
	local xR, kR, aR, liftR, swR = legCycle(uR, s, D, r)
	local kTotL, kTotR = kL * w + kc, kR * w + kc
	local hipWL = solveHip(xL * w, kTotL, T, S) + liftL * w
	local hipWR = solveHip(xR * w, kTotR, T, S) + liftR * w
	setJoint(J, "HipL", CFrame.Angles(hipWL - lean, 0, 0))
	setJoint(J, "HipR", CFrame.Angles(hipWR - lean, 0, 0))
	setJoint(J, "KneeL", CFrame.Angles(-kTotL, 0, 0))
	setJoint(J, "KneeR", CFrame.Angles(-kTotR, 0, 0))
	setJoint(J, "AnkleL", CFrame.Angles(kTotL - hipWL + aL * w, 0, 0))
	setJoint(J, "AnkleR", CFrame.Angles(kTotR - hipWR + aR * w, 0, 0))

	-- ---- pelvis: height from the stance legs (idle: both legs plant), apex while airborne
	local stanceL = (w < 0.01) and 1 or swL
	local stanceR = (w < 0.01) and 1 or swR
	local hL = T * math.cos(hipWL) + S * math.cos(hipWL - kTotL) - (T + S)
	local hR = T * math.cos(hipWR) + S * math.cos(hipWR - kTotR) - (T + S)
	local hipC = solveHip(0, kc, T, S)
	local flightY = T * math.cos(hipC) + S * math.cos(hipC - kc) - (T + S) + (0.05 + 0.15 * r) * w -- crouch height + airborne rise
	local supported = stanceL + stanceR
	local stanceY = (stanceL * hL + stanceR * hR) / math.max(supported, 1e-3)
	local pelvisY = flightY + (stanceY - flightY) * math.min(supported, 1)
	local side = (swL - swR) * w -- +1 weight on left leg .. -1 on right
	local gaitPhase = ((xL - xR) / math.max(s * D * 0.5, 0.2)) * 0.5 -- +: left foot ahead
	local yawGait = -(0.05 + 0.08 * r) * math.clamp(gaitPhase, -1, 1) * w
	local rollGait = ROLL_SIGN * (0.025 + 0.025 * r) * side
	local sway = -(0.12 - 0.05 * r) * side -- COM shifts over the stance foot
	-- idle weight shifting so a standing troop never freezes
	local idle = 1 - w
	rollGait += idle * 0.018 * math.sin(now * 0.45 + st.phase)
	sway += idle * 0.05 * math.sin(now * 0.45 + st.phase)
	local rootYaw = yawGait + st.pYaw
	setJoint(J, "RootJoint",
		CFrame.new(sway, pelvisY, 0)
			* CFrame.Angles(0, rootYaw, 0)
			* CFrame.Angles(-lean, 0, (prof.stanceRoll or 0))
			* CFrame.Angles(0, 0, rollGait))

	-- ---- upper body: torso counter-rotates the pelvis so the rifle stays on target
	local breath = math.sin(now * 1.4 + st.hPhase) * 0.012
	local hunchAng = st.hunch * 0.35
	local recoil = state.firePulse * state.firePulse
	local hit = state.hitPulse
	local waistYaw = state.aimYaw * 0.7 + c.scanYaw * 0.3 - rootYaw * 0.85
	setJoint(J, "Waist",
		CFrame.Angles(-hunchAng + lean * 0.5 + breath + recoil * 0.04 + hit * 0.18, waistYaw + hit * 0.12, hit * 0.06 - rollGait * 0.7))
	-- head stays level and quiet: undo hunch + lean, soak up the pelvis bob
	setJoint(J, "Neck", CFrame.Angles(hunchAng * 0.9 + lean * 0.4 + state.aimPitch * 0.4 - pelvisY * 0.12, state.aimYaw * 0.2 + c.scanYaw, 0))

	-- arms: rigid rifle carry. delta pitch = state ready angle + compensation for the torso's forward pitch
	local torsoPitch = 0.5 * lean + hunchAng
	local delta = st.ready + torsoPitch * 0.8 + breath + recoil * 0.1 + math.sin(st.hPhase * 2) * 0.012 * w * (1 + r)
	setJoint(J, "ShoulderR", CFrame.Angles(delta, 0, 0))
	setJoint(J, "ShoulderL", CFrame.Angles(delta, 0, 0))
	setJoint(J, "ElbowR", CFrame.Angles(recoil * 0.12, 0, 0))
	setJoint(J, "ElbowL", CFrame.Angles(recoil * 0.05, 0, 0))
	setJoint(J, "WristR", CFrame.Angles(0, 0, 0))
	setJoint(J, "WristL", CFrame.Angles(0, 0, 0))
end

local function poseRig(model: Model, state: RigState, dt: number)
	local pivot = model:GetPivot()
	local pos = pivot.Position

	-- COMBAT STATE CHANNELS — read replicated attributes, zero extra traffic.
	-- hit reaction: health decrease pulses a flinch.
	local hp = model:GetAttribute("Health") or state.health
	if hp < state.health - 0.5 then
		state.hitPulse = 1
	end
	state.health = hp
	state.hitPulse = math.max(0, state.hitPulse - dt * 4)
	-- firing recoil: tracer beams/parts spawning near the enemy pulse the weapon arm.
	-- (detection hook installed below — firePulse decays here)
	state.firePulse = math.max(0, state.firePulse - dt * 7)

	-- DEATH TRANSITION — sequential collapse: legs buckle first, torso folds through the
	-- middle window, head/arms drop last. staged timing reads as weight loss, not scattering.
	local dead = model:GetAttribute("Dead") == true
	if dead then
		state.deathT = (state.deathT or 0) + dt
		-- staged easing: each channel has its own [t0,t1] window within the 1.2s collapse
		local function stage(t0, t1)
			local x = math.clamp((state.deathT - t0) / (t1 - t0), 0, 1)
			return 1 - (1 - x) * (1 - x)
		end
		local legE = stage(0.0, 0.45) -- legs buckle immediately
		local torsoE = stage(0.25, 0.85) -- torso folds through the middle
		local headE = stage(0.55, 1.1) -- head and arms drop last
		if state.hero then
			-- hero collapse (measured signs): knees fold (negative), hips flex, pelvis drops, torso folds forward
			setJoint(state.joints, "KneeL", CFrame.Angles(-legE * 1.6, 0, 0))
			setJoint(state.joints, "KneeR", CFrame.Angles(-legE * 1.4, 0, 0))
			setJoint(state.joints, "HipL", CFrame.Angles(legE * 0.8, 0, 0))
			setJoint(state.joints, "HipR", CFrame.Angles(legE * 0.7, 0, 0))
			setJoint(state.joints, "AnkleL", CFrame.Angles(legE * 0.8, 0, 0))
			setJoint(state.joints, "AnkleR", CFrame.Angles(legE * 0.7, 0, 0))
			setJoint(state.joints, "RootJoint", CFrame.new(0, -(legE * 1.0 + torsoE * 1.2), 0) * CFrame.Angles(-torsoE * 0.9, 0, torsoE * 0.12))
			setJoint(state.joints, "Waist", CFrame.Angles(-torsoE * 0.3, 0, 0))
			setJoint(state.joints, "Neck", CFrame.Angles(headE * 0.4, 0, headE * 0.1))
			setJoint(state.joints, "ShoulderL", CFrame.Angles(headE * 0.3, 0, headE * 0.2))
			setJoint(state.joints, "ShoulderR", CFrame.Angles(headE * 0.3, 0, -headE * 0.2))
			return
		end
		setJoint(state.joints, "KneeL", CFrame.Angles(legE * 1.5, 0, 0))
		setJoint(state.joints, "KneeR", CFrame.Angles(legE * 1.3, 0, 0))
		setJoint(state.joints, "HipL", CFrame.Angles(-legE * 1.2, 0, 0))
		setJoint(state.joints, "HipR", CFrame.Angles(-legE * 1.0, 0, 0))
		setJoint(state.joints, "RootJoint", CFrame.new(0, -legE * 1.3, 0) * CFrame.Angles(torsoE * 0.85, 0, torsoE * 0.12))
		setJoint(state.joints, "Waist", CFrame.Angles(torsoE * 0.65, 0, 0))
		setJoint(state.joints, "Neck", CFrame.Angles(headE * 0.55, 0, headE * 0.1))
		setJoint(state.joints, "ShoulderL", CFrame.Angles(headE * 0.35, 0, headE * 0.25))
		setJoint(state.joints, "ShoulderR", CFrame.Angles(headE * 0.45, 0, -headE * 0.15))
		return -- death terminal: no locomotion, no aim
	end

	-- velocity from replicated displacement
	local instantSpeed = 0
	if dt > 0 then
		instantSpeed = (pos - state.last).Magnitude / dt
	end
	state.last = pos
	state.speed = blend(state.speed, instantSpeed, dt, 0.15)

	local prof = state.profile
	local moving = state.speed > 1.2

	-- gait: frequency from actual velocity, amplitude blended toward target
	local gaitFreq = (state.speed / STRIDE) * prof.freqMul
	if moving then
		state.phase += 2 * math.pi * gaitFreq * dt
	end
	local ampTarget = moving and math.clamp(state.speed / 10, 0.3, 1) or 0
	state.amp = blend(state.amp, ampTarget, dt, TAU_GAIT)

	local phase = state.phase
	local amp = state.amp * prof.ampMul

	-- movement direction in the enemy's facing frame: strafe/backpedal modulation.
	-- forward movement uses the standard gait; lateral movement reduces hip swing and
	-- adds a sideways weight shift; backward motion reverses the gait phase sign.
	local look = pivot.LookVector
	local right = pivot.RightVector
	local vel = (pos - (state.prevPos or pos)) / math.max(dt, 0.001)
	state.prevPos = pos
	local fwdDot = 0
	local latDot = 0
	if state.speed > 1.2 then
		fwdDot = (vel.X * look.X + vel.Z * look.Z) / math.max(state.speed, 0.1)
		latDot = (vel.X * right.X + vel.Z * right.Z) / math.max(state.speed, 0.1)
	end
	local strafeAmt = math.clamp(math.abs(latDot), 0, 1) * amp
	local backpedal = fwdDot < -0.35

	-- LOWER BODY — locomotion layer (radians)
	local hipAmp = 0.55 * amp
	local kneeAmp = 0.7 * amp
	local sinL = math.sin(phase)
	local sinR = math.sin(phase + math.pi)

	-- hips swing contralaterally — reduced amplitude + lateral lean when strafing,
	-- reversed phase sign when backpedaling so feet step with the motion direction
	local dirSign = backpedal and -1 or 1
	local lateralReduction = 1 - strafeAmt * 0.45
	local strafeLean = strafeAmt * 0.12 * (latDot > 0 and -1 or 1)
	setJoint(state.joints, "HipL", CFrame.Angles(-sinL * hipAmp * lateralReduction * dirSign, 0, strafeLean))
	setJoint(state.joints, "HipR", CFrame.Angles(-sinR * hipAmp * lateralReduction * dirSign, 0, strafeLean))
	-- knees flex during the backward/recovery half of each leg's cycle
	local kneeL = math.max(0, -sinL) * kneeAmp + math.max(0, sinL) * kneeAmp * 0.15
	local kneeR = math.max(0, -sinR) * kneeAmp + math.max(0, sinR) * kneeAmp * 0.15
	setJoint(state.joints, "KneeL", CFrame.Angles(kneeL, 0, 0))
	setJoint(state.joints, "KneeR", CFrame.Angles(kneeR, 0, 0))
	-- ankles compensate for terrain contact
	setJoint(state.joints, "AnkleL", CFrame.Angles(sinL * hipAmp * 0.4 - kneeL * 0.5, 0, 0))
	setJoint(state.joints, "AnkleR", CFrame.Angles(sinR * hipAmp * 0.4 - kneeR * 0.5, 0, 0))

	-- cover posture: crouched when holding cover stationary
	if inCover and not moving then
		setJoint(state.joints, "HipL", CFrame.Angles(0.55, 0, 0))
		setJoint(state.joints, "HipR", CFrame.Angles(0.55, 0, 0))
		setJoint(state.joints, "KneeL", CFrame.Angles(0.9, 0, 0))
		setJoint(state.joints, "KneeR", CFrame.Angles(0.9, 0, 0))
	end
	-- torso bob: subtle vertical at 2x gait frequency, scaled by personality
	local bob = math.abs(math.sin(phase)) * 0.05 * amp * prof.bobMul
	-- slight forward lean when moving — weight commitment; vanguard carries assault lean always
	local lean = amp * 0.06 + (prof.leanBias or 0)
	setJoint(state.joints, "RootJoint", CFrame.new(0, bob, 0) * CFrame.Angles(lean, 0, (prof.stanceRoll or 0)))

	-- UPPER BODY — independent aim layer.
	-- aim target: nearest visible player within engagement range (presentation only —
	-- authoritative targeting stays server-side; this orients the weapon cosmetically)
	local enemyId = model:GetAttribute("EnemyId")
	-- spec sec.65 AI-state integration: posture consumes the authoritative replicated state.
	-- patrol/return are relaxed low-carry with scanning; investigate/search semi-raised alert;
	-- guard ready-scanning; engage/takecover full combat posture. no independent decisions.
	-- GFDebugState: client-local art-QA override (set it on the client to preview a stance; the server never writes it)
	local aiState = model:GetAttribute("GFDebugState") or model:GetAttribute("GFState") or "Engage"
	local relaxed = aiState == "Patrol" or aiState == "Return" or aiState == "Idle"
	local investigating = aiState == "Investigate" or aiState == "Search"
	local guarding = aiState == "Guard"
	local inCover = aiState == "TakeCover"
	local aimYawTarget, aimPitchTarget = 0, 0
	local targetPos = nil
	local myPos = pos
	-- spec sec.71: aim at the ACTUAL legitimate target when the server replicates it;
	-- nearest-player remains only the fallback for unreplicated edge cases
	local legit = model:GetAttribute("GFLegitTarget")
	local bestD = 70
	if legit then
		targetPos = legit
		bestD = (legit - myPos).Magnitude  -- proximity measures the real target, not the nearest-player proxy
	else
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local d = (hrp.Position - myPos).Magnitude
				if d < bestD then
					bestD = d
					targetPos = hrp.Position
				end
			end
		end
	end

	if relaxed then
		targetPos = nil  -- relaxed states do not track targets — weapon stays lowered, head scans
	end
	if targetPos then
		-- yaw of target relative to the enemy's facing
		local look = pivot.LookVector
		local toTarget = (targetPos - myPos)
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flat.Magnitude > 0.5 then
			local flatN = flat.Unit
			local cross = look.X * flatN.Z - look.Z * flatN.X
			local dot = math.clamp(look.X * flatN.X + look.Z * flatN.Z, -1, 1)
			aimYawTarget = math.clamp(math.atan2(-cross, dot), -0.9, 0.9)
			aimPitchTarget = math.clamp(math.atan2(toTarget.Y, flat.Magnitude), -0.5, 0.6)
		end
	end

	local sharp = prof.aimSharp
	state.aimYaw = blend(state.aimYaw, aimYawTarget, dt, TAU_AIM / sharp)
	state.aimPitch = blend(state.aimPitch, aimPitchTarget, dt, TAU_AIM / sharp)

	if state.hero then
		local scanYawH = 0
		if relaxed or guarding then
			scanYawH = math.sin(os.clock() * 0.7 + state.phase) * 0.35
		elseif investigating then
			scanYawH = math.sin(os.clock() * 1.3 + state.phase) * 0.55
		end
		heroPose(model, state, dt, {
			enemyId = enemyId,
			moving = moving,
			phase = phase,
			amp = amp,
			relaxed = relaxed,
			investigating = investigating,
			guarding = guarding,
			inCover = inCover,
			engaged = targetPos ~= nil and bestD < 60,
			scanYaw = scanYawH,
			pos = pos,
			pivot = pivot,
		})
		return
	end

	-- state-dependent head behavior: patrol/return scan the environment; investigate/search
	-- scan wider and sharper; combat states hold aim-oriented head
	local scanYaw = 0
	if relaxed or guarding then
		scanYaw = math.sin(os.clock() * 0.7 + state.phase) * 0.35
	elseif investigating then
		scanYaw = math.sin(os.clock() * 1.3 + state.phase) * 0.55
	end
	-- waist yaw toward target (upper body tracks independently of locomotion direction)
	setJoint(state.joints, "Waist", CFrame.Angles(0, state.aimYaw * 0.55 + scanYaw * 0.3, 0))
	setJoint(state.joints, "Neck", CFrame.Angles(state.aimPitch * 0.4, state.aimYaw * 0.35 + scanYaw, 0))

	-- arms: weapon-hold base pose + small counter-swing scaled DOWN while aiming
	-- (spec: no unnatural arm swinging while aiming)
	local aiming = math.abs(state.aimYaw) > 0.06 or (targetPos ~= nil and bestD < 45)
	local swingScale = aiming and 0.15 or prof.armSwing
	local armAmp = 0.35 * amp * swingScale
	-- left arm: counter-swings when free, stabilizes weapon when aiming
	local leftArmBase = aiming and CFrame.Angles(-0.5, 0.5, 0.1) or CFrame.Angles(0, 0, 0.06)
	setJoint(state.joints, "ShoulderL", leftArmBase * CFrame.Angles(-sinR * armAmp, 0, 0))
	setJoint(state.joints, "ElbowL", CFrame.Angles(aiming and -0.9 or -0.35, 0, 0))
	-- right arm: weapon-hold — raised toward aim pitch, minimal swing
	local holdPitch = -0.85 - state.aimPitch * 0.7
	if relaxed then
		holdPitch = -0.3  -- low carry: weapon angled down across the body
	elseif investigating then
		holdPitch = -0.6  -- semi-raised: alert but not engaged
	end
	-- firing recoil: sharp backward snap on the weapon arm, fast recovery
	local recoil = state.firePulse * state.firePulse -- quadratic falloff reads snappy
	local hit = state.hitPulse
	setJoint(state.joints, "ShoulderR",
		CFrame.Angles(holdPitch - recoil * 0.35, -0.15 + state.aimYaw * 0.3, -0.06)
			* CFrame.Angles(-sinL * armAmp * 0.4, 0, 0))
	setJoint(state.joints, "ElbowR", CFrame.Angles(-0.5 - recoil * 0.3, 0, 0))
	-- hit flinch: torso twist + slight stagger, layered over aim
	if hit > 0.01 then
		local waist = state.joints.Waist
		if waist then
			waist.motor.C0 = waist.motor.C0 * CFrame.Angles(-hit * 0.22, hit * 0.15, hit * 0.08)
		end
	end

	-- idle breathing when stationary — prevents dead-mannequin look
	if not moving then
		local breath = math.sin(os.clock() * 1.4 + phase) * 0.015
		local waist = state.joints.Waist
		if waist then
			waist.motor.C0 = waist.base * CFrame.Angles(breath, state.aimYaw * 0.55, 0)
		end
	end
end

-- fire detection: tracers/muzzle effects spawn as workspace parts/beams near the enemy.
-- lane-safe observation — no server edits; pulse the matching rig's recoil.
workspace.DescendantAdded:Connect(function(inst)
	if not (inst:IsA("Beam") or inst:IsA("Part") or inst:IsA("Attachment")) then return end
	if inst:IsA("Part") and not inst.Name:lower():match("tracer") and not inst.Name:lower():match("muzzle") and not inst.Name:lower():match("shot") then
		return
	end
	task.defer(function()
		local pos = nil
		if inst:IsA("BasePart") then
			pos = inst.Position
		elseif inst:IsA("Attachment") then
			pos = inst.WorldPosition
		end
		if not pos then return end
		for model, state in tracked do
			if model.Parent then
				local d = (model:GetPivot().Position - pos).Magnitude
				if d < 8 then
					state.firePulse = 1
					break
				end
			end
		end
	end)
end)

local statClock = os.clock()
RunService.Heartbeat:Connect(function(dt)
	local folder = workspace:FindFirstChild("ActiveActors")
	if not folder then
		return
	end
	if os.clock() - statClock > 1 then
		statClock = os.clock()
		local n = 0
		for _ in tracked do n += 1 end
		workspace:SetAttribute("GF_EnemyAnimTracked", n)
	end
	-- untrack destroyed models
	for model in tracked do
		if not model.Parent then
			tracked[model] = nil
		end
	end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("HasRig") then
			local state = tracked[model]
			if not state then
				local rig = rigOf(model)
				if rig then
					state = {
						joints = indexJoints(rig),
						phase = math.random() * math.pi * 2, -- desynchronize — no robotic uniformity
						last = model:GetPivot().Position,
						speed = 0,
						amp = 0,
						aimYaw = 0,
						aimPitch = 0,
						profile = profileFor(model),
						rig = rig,
						health = model:GetAttribute("Health") or 100,
						hitPulse = 0,
						firePulse = 0,
						deathT = nil,
						prevPos = nil,
						hero = rig:GetAttribute("GF_HeroBaked") == true,
					}
					tracked[model] = state
				end
			end
			if state then
				local ok, err = pcall(poseRig, model, state, dt)
				if not ok then
					-- surface the failure once per model instead of dying silently —
					-- silent untrack-and-recreate loops cost us a diagnosis cycle already
					if not state.errReported then
						warn(string.format("[EnemyAnimClient] poseRig error on %s: %s", model.Name, tostring(err)))
						state.errReported = true
					end
					tracked[model] = nil
				end
			end
		end
	end
end)

print("[EnemyAnimClient] v2-online archetypes=15")
