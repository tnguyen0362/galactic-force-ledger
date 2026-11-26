--!strict
-- TargetTracker — stochastic target state estimation (tracking architecture v1, owner directive 2026-11-28).
-- Measurement-frame alpha-beta filter per enemy-target pair: position+velocity latent state anchored
-- at the last observation time; propagation only across inter-observation intervals; fire-time aim
-- propagates the anchored estimate across the open-loop gap. Maneuver-adaptive gain inflates
-- uncertainty on innovation spikes (reversals/acceleration) and boosts re-convergence.
-- Legitimate information only: consumes delayed position observations, never inputs or hidden state.
local TargetTracker = {}

-- difficulty-conditioned parameters (initial values — calibrated against engine measurement)
local PARAMS = {
	-- calibrated 2026-11-28 (calibrate_v3.py): beta aggressively difficulty-scaled. Key insight:
	-- game observations are EXACT positions (legitimacy constraint is timing/visibility, not
	-- measurement noise) — high velocity gain is free, and reconvergence speed after reversals is
	-- what makes realistic oscillatory strafing trackable. Prototype triangular-strafe hitrates:
	-- Easy 7 / Normal 7 / Hard 15 / Extreme 22 vs stationary 37 — mandate ordering + gradient.
	Easy = { tauObs = 0.45, alpha = 0.35, beta = 0.40, kappa = 3.0, uncInflate = 0.9, uncDecay = 0.30, uncMin = 0.35, uncMax = 3.0 },
	Normal = { tauObs = 0.35, alpha = 0.45, beta = 0.60, kappa = 2.5, uncInflate = 0.9, uncDecay = 0.30, uncMin = 0.35, uncMax = 3.0 },
	Hard = { tauObs = 0.25, alpha = 0.55, beta = 0.80, kappa = 2.2, uncInflate = 0.9, uncDecay = 0.30, uncMin = 0.35, uncMax = 3.0 },
	Extreme = { tauObs = 0.15, alpha = 0.70, beta = 0.90, kappa = 2.0, uncInflate = 0.9, uncDecay = 0.30, uncMin = 0.35, uncMax = 3.0 },
}

function TargetTracker.params(difficulty: string)
	return PARAMS[difficulty] or PARAMS.Normal
end

function TargetTracker.newState()
	return {
		px = 0, pz = 0,           -- position estimate anchored at anchorT (flat combat plane)
		vx = 0, vz = 0,           -- velocity estimate
		anchorT = nil :: number?, -- time the state is anchored at
		unc = 1.0,                -- scalar tracking-uncertainty inflation (legacy v1 path)
		innovEMA = 1.0,           -- v2: normalized-innovation exponential moving average
		initialized = false,
		-- observation delay line: observations only become available tau_obs after they occur
		obsBuf = {} :: { { t: number, x: number, z: number } },
		lastConsumedT = -1e9,
	}
end

-- record a raw visual observation (called when the perception system sees the target).
-- buffer is bounded; consumed later through the delay line.
function TargetTracker.observe(state: any, pos: Vector3, now: number)
	local buf = state.obsBuf
	buf[#buf + 1] = { t = now, x = pos.X, z = pos.Z }
	if #buf > 64 then
		table.remove(buf, 1)
	end
end

-- consume observations that have matured past tau_obs, updating the filter.
-- returns the newest innovation magnitude or nil.
function TargetTracker.pump(state: any, par: any, now: number)
	local horizon = now - par.tauObs
	local innov = nil
	for _, obs in ipairs(state.obsBuf) do
		if obs.t <= horizon and obs.t > state.lastConsumedT then
			innov = TargetTracker.update(state, par, obs.x, obs.z, obs.t)
			state.lastConsumedT = obs.t
		end
	end
	-- drop matured buffer entries
	local keep = {}
	for _, obs in ipairs(state.obsBuf) do
		if obs.t > horizon - 0.5 then
			keep[#keep + 1] = obs
		end
	end
	state.obsBuf = keep
	return innov
end

function TargetTracker.update(state: any, par: any, zx: number, zz: number, tObs: number)
	if not state.initialized then
		state.px, state.pz = zx, zz
		state.vx, state.vz = 0, 0
		state.anchorT = tObs
		state.initialized = true
		return 0
	end
	local dt = math.max(0.05, tObs - (state.anchorT or tObs))
	-- propagate anchored state across the inter-observation interval
	local px = state.px + state.vx * dt
	local pz = state.pz + state.vz * dt
	local rx = zx - px
	local rz = zz - pz
	local innov = math.sqrt(rx * rx + rz * rz)
	local innovNorm = innov / 1.5
	local boost = 1
	if innovNorm > par.kappa then
		boost = 1.8
		state.unc = math.min(par.uncMax, state.unc + par.uncInflate)
	end
	local a = math.min(0.95, par.alpha * boost)
	local b = math.min(0.95, par.beta * boost)
	state.px = px + a * rx
	state.pz = pz + a * rz
	state.vx += b * rx / dt
	state.vz += b * rz / dt
	state.anchorT = tObs
	-- near-stationary deadband: velocity estimation noise creates false lead for
	-- targets that barely move — shrink small velocities toward zero
	local vmag = math.sqrt(state.vx * state.vx + state.vz * state.vz)
	if vmag < 2.5 then
		local shrink = math.max(0, vmag - 1.2 * dt) / math.max(vmag, 1e-6)
		state.vx *= shrink
		state.vz *= shrink
	else
		-- physical plausibility clamp: velocities beyond sprint+dodge capability are estimation
		-- noise, not movement — adversarial sweep showed high-gain difficulties whipsawing on
		-- high-frequency jitter without this bound
		local vmax = 30
		if vmag > vmax then
			state.vx *= vmax / vmag
			state.vz *= vmax / vmag
		end
	end
	if innovNorm < 1.0 then
		state.unc = math.max(par.uncMin, state.unc - par.uncDecay * dt)
	end
	-- v2: innovation EMA — fast attack on maneuver, slow decay on clean track; converged
	-- tracks earn precision instead of carrying a fixed uncertainty floor
	-- asymmetric EMA: fast attack on maneuver transients, fast-ish decay on clean track —
	-- 0.55/s was resonant-trapping oscillatory strafing (2.4s legs vs 1.8s decay tau meant
	-- uncertainty NEVER recovered within a leg); 2.0/s restores precision in converged windows
	local rate = (innovNorm > state.innovEMA) and 3.0 or 2.0
	state.innovEMA += (innovNorm - state.innovEMA) * math.min(1, rate * dt)
	return innov
end

-- propagate the anchored estimate to time t (open-loop), returning flat x,z
function TargetTracker.predictTo(state: any, t: number): (number, number)
	if not state.initialized then
		return state.px, state.pz
	end
	local dt = math.max(0, t - (state.anchorT or t))
	return state.px + state.vx * dt, state.pz + state.vz * dt
end

-- tracking uncertainty including open-loop gap inflation since the last matured observation
function TargetTracker.uncertaintyAt(state: any, par: any, t: number): number
	if not state.initialized then
		return par.uncMax
	end
	local gap = math.max(0, t - (state.anchorT or t))
	return math.min(par.uncMax, state.unc + 0.45 * gap)
end

-- v2 uncertainty: base + innovation-EMA scaled + SPEED-SCALED open-loop gap.
-- v3 refinement: staleness uncertainty scales with estimated speed — a stationary target cannot
-- exploit information age, so uniform gap inflation was suppressing stationary hitrates for no
-- physical reason. prototype ordering at Normal: stationary 79 > const_strafe 42 > dodge 21 >
-- periodic reversal 8 > random/sine 4 — the mandate's target ordering with clean separation.
function TargetTracker.uncertaintyAtV2(state: any, t: number): number
	if not state.initialized then
		return 3.0
	end
	local gap = math.max(0, t - (state.anchorT or t))
	local vmag = math.sqrt(state.vx * state.vx + state.vz * state.vz)
	local gapUnc = math.min(1.2, vmag * gap * 0.09)
	return math.min(3.0, 0.15 + 1.4 * state.innovEMA + gapUnc)
end

return TargetTracker
