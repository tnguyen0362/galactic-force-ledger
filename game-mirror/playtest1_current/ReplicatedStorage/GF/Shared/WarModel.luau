--!strict
-- WarModel.luau — Theater of War strategic dynamics, production port of the validated
-- Python reference (gf-research/strategic/model.py + sim.py classification/availability).
-- VALIDATION GATE: must diff-match the Python reference on seeded trajectories before
-- any production use. Do not tune values here without re-running the Python battery —
-- parameters live in the validated registry (params_v1.json) and mirror into Configs.
--
-- State per region: x = {E,L,H,I,S} in [0,1]. See THEATER_OF_WAR_SPEC.md for full semantics.

local WarModel = {}

-- ----------------------------- geography -----------------------------
WarModel.TERRITORIES = {
	VerdantReach = {biome = "forest", neighbors = {"ThornBasin", "AshenDivide"}, industrial = 0.2},
	ThornBasin   = {biome = "forest", neighbors = {"VerdantReach", "IronMarch"}, industrial = 0.3},
	AshenDivide  = {biome = "ash",    neighbors = {"VerdantReach", "RedMesa", "Frostline"}, industrial = 0.4},
	RedMesa      = {biome = "ash",    neighbors = {"AshenDivide", "WhiteRidge"}, industrial = 0.5},
	Frostline    = {biome = "frost",  neighbors = {"AshenDivide", "WhiteRidge", "IronMarch"}, industrial = 0.4},
	WhiteRidge   = {biome = "frost",  neighbors = {"RedMesa", "Frostline", "FoundryBelt"}, industrial = 0.6},
	IronMarch    = {biome = "iron",   neighbors = {"ThornBasin", "Frostline", "FoundryBelt"}, industrial = 0.9},
	FoundryBelt  = {biome = "iron",   neighbors = {"WhiteRidge", "IronMarch"}, industrial = 1.0},
}

-- operation instances; templates may serve multiple regions (coverage arithmetic —
-- see spec sec.8). vector order: {dE, dL, dH, dI, dS}
WarModel.OPERATIONS = {
	FORWARD_DOMINION  = {region = "VerdantReach", family = "Conquest",    b = {-.01, 0, .07, 0, .02}},
	ALIEN_LEGACY      = {region = "VerdantReach", family = "Recovery",    b = {0, 0, 0, .07, 0}},
	BROKEN_TALON      = {region = "VerdantReach", family = "Elimination", b = {-.05, 0, 0, 0, .01}},
	FALLEN_CONVOY     = {region = "ThornBasin",   family = "Recovery",    b = {0, 0, .05, 0, .01}},
	HEAD_OF_SPEAR     = {region = "ThornBasin",   family = "Elimination", b = {-.06, 0, 0, .01, 0}},
	SEVER_SIGNAL_TB   = {region = "ThornBasin",   family = "Sabotage",    b = {-.02, -.06, 0, .01, 0}},
	SEVER_SIGNAL      = {region = "AshenDivide",  family = "Sabotage",    b = {-.02, -.06, 0, .01, 0}},
	HOLD_THE_LINE     = {region = "AshenDivide",  family = "Defense",     b = {-.01, 0, .01, 0, .07}},
	SHATTERED_AEGIS   = {region = "RedMesa",      family = "Sabotage",    b = {-.03, -.05, 0, 0, .01}},
	SIEGE_BREAKER     = {region = "RedMesa",      family = "Elimination", b = {-.07, -.01, 0, 0, 0}},
	SILENT_ARCHIVE    = {region = "Frostline",    family = "Recovery",    b = {0, 0, 0, .08, 0}},
	BURN_ARSENAL_FR   = {region = "Frostline",    family = "Sabotage",    b = {-.01, -.07, 0, 0, 0}},
	BROKEN_TALON_FR   = {region = "Frostline",    family = "Elimination", b = {-.05, 0, 0, 0, .01}},
	LAST_TRANSMISSION = {region = "WhiteRidge",   family = "Defense",     b = {0, 0, .02, .02, .04}},
	THRONEFALL        = {region = "WhiteRidge",   family = "Conquest",    b = {-.03, 0, .08, 0, .05}},
	HEAD_OF_SPEAR_WR  = {region = "WhiteRidge",   family = "Elimination", b = {-.06, 0, 0, .01, 0}},
	BURN_ARSENAL      = {region = "IronMarch",    family = "Sabotage",    b = {-.01, -.07, 0, 0, 0}},
	SIEGE_BREAKER_IM  = {region = "IronMarch",    family = "Elimination", b = {-.07, -.01, 0, 0, 0}},
	POWER_UNDER_FIRE  = {region = "FoundryBelt",  family = "Defense",     b = {0, 0, .03, 0, .05}},
	IRON_FOUNDRY      = {region = "FoundryBelt",  family = "Conquest",    b = {-.01, -.04, .05, 0, .02}},
	SHATTERED_AEGIS_FB = {region = "FoundryBelt", family = "Sabotage",    b = {-.03, -.05, 0, 0, .01}},
}

-- ----------------------------- parameters (validated registry mirror) -----------------------------
WarModel.PARAMS = {
	dt_hours = 1.0,
	rE = 0.004, E_cap = 0.9,
	rL = 0.003, L_cap = 0.85,
	rI = 0.006,
	rH = 0.0008,
	sec_relax = 0.0012, sec_ceiling = 1.0,
	contest_rate = 0.004,
	universal_attrition = 0.015,
	universal_presence = 0.008,
	net_kappa = 0.35,
	contribution_scale = 0.00856, -- throughput-compensated for solved difficulty weights
	lambda0 = 0.005,
	min_interval_hours = 72,
	co_E_surge = 0.10, co_L_surge = 0.05, co_H_damage = 0.12, co_S_damage = 0.18,
	co_mitigation = 0.6,
	A0 = 400.0, alpha_act = 0.05,
	g_min = 0.35, g_max = 2.5,
	adapt_rate = 0.02, sc_max = 1.75,
	w = {Easy = 1.0, Normal = 2.02, Hard = 3.5, Extreme = 5.86},
	class_persist_hours = 48,
}

function WarModel.clamp01(x: number): number
	return math.min(1.0, math.max(0.0, x))
end

function WarModel.clampRegion(reg)
	reg.E = WarModel.clamp01(reg.E)
	reg.L = WarModel.clamp01(reg.L)
	reg.H = WarModel.clamp01(reg.H)
	reg.I = WarModel.clamp01(reg.I)
	reg.S = WarModel.clamp01(reg.S)
end

-- per-region Euler step with EXPLICIT coupling inputs. this is the single source of truth
-- for endogenous dynamics: the theater-wide step computes coupling from live neighbor state;
-- the persistence layer computes it from piecewise-constant neighbor snapshots. both paths
-- execute THIS function so semantics cannot drift.
function WarModel.stepRegion(reg, p, dt, indBoost, netLog)
	local L, E, H, I, S = reg.L, reg.E, reg.H, reg.I, reg.S
	-- reinforcement relaxation: fastest when depleted; sustain = E_cap * L_eff
	local rE_eff = p.rE * (0.4 + 0.6 * L)
	local L_eff = (1 - p.net_kappa) * L + p.net_kappa * netLog
	local dE = rE_eff * (p.E_cap * L_eff - E)
	reg.L_eff = L_eff -- exposed for availability/consolidation logic
	local rL_eff = p.rL * (0.5 + 0.5 * indBoost)
	local dL = rL_eff * (p.L_cap - L)
	local dI = -p.rI * I
	-- contest coupling: enemy strength erodes presence unless security shelters it
	local contest = p.contest_rate * E * math.max(0.0, 1.0 - S)
	local dH = -(p.rH + contest) * H
	-- security relaxes toward presence-scaled ceiling; defense ops are the fast path
	local dS = p.sec_relax * (p.sec_ceiling * H - S)
	reg.E += dE * dt
	reg.L += dL * dt
	reg.H += dH * dt
	reg.I += dI * dt
	reg.S += dS * dt
	WarModel.clampRegion(reg)
end

-- coupling inputs for a region given a logistics accessor: lOf(rid) -> L. shared by both
-- the theater-wide step and the persistence integration so the formula cannot diverge.
function WarModel.couplingInputs(rid, lOf)
	local terr = WarModel.TERRITORIES[rid]
	local support, netw = 0.0, 0.0
	for _, n in terr.neighbors do
		support += 0.5 * WarModel.TERRITORIES[n].industrial * lOf(n)
		netw += WarModel.TERRITORIES[n].industrial * lOf(n)
	end
	local count = math.max(1, #terr.neighbors)
	return 0.6 * terr.industrial + support / count, netw / count
end

-- one Euler step of endogenous dynamics across all regions. regions: map rid -> mutable
-- state table {E,L,H,I,S,...}. deterministic, no RNG.
function WarModel.endogenousStep(regions, p, dt)
	local inputs = {}
	for rid in WarModel.TERRITORIES do
		local indBoost, netLog = WarModel.couplingInputs(rid, function(n)
			return regions[n].L
		end)
		inputs[rid] = {indBoost, netLog}
	end
	for rid, reg in regions do
		WarModel.stepRegion(reg, p, dt, inputs[rid][1], inputs[rid][2])
	end
end

-- state-dependent counteroffensive hazard (per hour). capability floors low: pacified
-- regions cannot mount regular events.
function WarModel.counteroffensiveHazard(reg, p)
	return p.lambda0 * (0.5 + 1.5 * reg.H) * (0.1 + 0.9 * reg.E) * (0.2 + 0.8 * reg.L)
		* (1.3 - 0.8 * reg.S)
end

-- apply a counteroffensive event. u1..u4 in (0,1) are the random draws (injected so the
-- caller controls the RNG stream — deterministic seeding is a persistence-layer concern)
function WarModel.applyCounteroffensive(reg, p, u1, u2, u3, u4)
	reg.E = WarModel.clamp01(reg.E + p.co_E_surge * (0.7 + 0.6 * u1))
	reg.L = WarModel.clamp01(reg.L + p.co_L_surge * (0.7 + 0.6 * u2))
	local mit = 1.0 - p.co_mitigation * reg.S
	reg.H = WarModel.clamp01(reg.H - p.co_H_damage * mit * (0.7 + 0.6 * u3))
	reg.S = WarModel.clamp01(reg.S - p.co_S_damage * mit * (0.7 + 0.6 * u4))
end

-- apply a successful operation's contribution. scaleMult carries adaptation (input lever)
-- and the sqrt(P) squad multiplier — computed by the caller.
function WarModel.applyContribution(reg, opId, difficulty, p, scaleMult)
	local scale = p.w[difficulty] * p.contribution_scale * scaleMult
	local b = WarModel.OPERATIONS[opId].b
	reg.E = WarModel.clamp01(reg.E + scale * (b[1] - p.universal_attrition))
	reg.L = WarModel.clamp01(reg.L + scale * b[2])
	reg.H = WarModel.clamp01(reg.H + scale * (b[3] + p.universal_presence))
	reg.I = WarModel.clamp01(reg.I + scale * b[4])
	reg.S = WarModel.clamp01(reg.S + scale * b[5])
end

-- memoryless classification (holes eliminated — see spec sec.9)
function WarModel.classifyRaw(reg)
	local E, H, S = reg.E, reg.H, reg.S
	local forceRatio = H / math.max(1e-6, H + E)
	if H >= 0.55 and S >= 0.5 and E <= 0.35 then
		return "established_superiority"
	end
	if forceRatio >= 0.60 and H >= 0.4 then
		return "gf_offensive"
	end
	if H >= 0.30 and E >= 0.30 then
		return "contested_theater"
	end
	if H >= 0.12 then
		return "human_infiltration"
	end
	return "ascendancy_dominance"
end

-- hysteresis wrapper: raw status must persist class_persist_hours before adoption
function WarModel.classify(reg, hoursNow, p)
	local raw = WarModel.classifyRaw(reg)
	if raw == reg.status then
		reg._pending = nil
		return reg.status
	end
	if reg._pending ~= raw then
		reg._pending = raw
		reg._pendingSince = hoursNow
		return reg.status
	end
	if hoursNow - (reg._pendingSince or 0) >= p.class_persist_hours then
		reg.status = raw
		reg.statusSince = hoursNow
		reg._pending = nil
	end
	return reg.status
end

-- operation availability: active while military purpose unsatisfied; consolidation
-- override keeps pacified-but-unsecured regions active until secured
function WarModel.operationActive(reg, opId)
	if reg.status == "established_superiority" then
		return false
	end
	if reg.E < 0.20 and reg.L < 0.40 then
		return true -- consolidation phase
	end
	local fam = WarModel.OPERATIONS[opId].family
	if fam == "Elimination" then
		return reg.E > 0.15
	end
	if fam == "Sabotage" then
		return reg.L > 0.15 or reg.E > 0.30
	end
	if fam == "Recovery" then
		local b = WarModel.OPERATIONS[opId].b
		if b[4] > 0 then
			return reg.I < 0.70
		end
		return reg.H < 0.80
	end
	if fam == "Defense" then
		return (reg.H > 0.20 and reg.S < 0.85) or reg.S < 0.35
	end
	if fam == "Conquest" then
		return reg.H < 0.80 or reg.S < 0.70
	end
	return true
end

return WarModel
