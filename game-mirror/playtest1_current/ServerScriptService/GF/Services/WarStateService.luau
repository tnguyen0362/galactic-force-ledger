--!strict
-- WarStateService — authoritative Theater of War persistence layer.
-- Implements the authority-free lazy-integration architecture (gf-research/strategic/
-- PERSISTENCE_ARCHITECTURE.md): per-region DataStore keys, integration inside UpdateAsync
-- transforms, deterministic counteroffensive seeding, exactly-once contribution idempotency,
-- MemoryStore snapshot cache. Dynamics come from WarModel (diff-tested against the Python
-- reference — do not modify semantics here).
--
-- TRANSITION STATE: coexists with legacy GalacticWarService during cutover. Legacy scalar
-- counters still feed the old war table; this service builds the authoritative
-- multidimensional state in parallel. Region resolution uses the primary binding of each
-- mission template until the deploy flow becomes region-aware (Stage 4/7).
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WarModel = require(ReplicatedStorage.GF.Shared.WarModel)

local WarStateService = {}

local CAMPAIGN_GEN = 1
local SCHEMA = 1
local STORE_PREFIX = "GF_War2_c" .. CAMPAIGN_GEN .. "_"
local META_KEY = "GF_War2Meta_c" .. CAMPAIGN_GEN
local SNAP_KEY_PREFIX = "GF_WarSnap_"
local IDEMPOTENCY_RING = 200
local MAX_CATCHUP_HOURS = 24 * 45 -- cap integration cost per transform; beyond this the war compresses

local storeMeta = nil
local snapCache = nil
local regionStores = {} -- rid -> DataStore (lazily acquired, nil-tolerant)
local started = false

local P = WarModel.PARAMS

-- ---------------- utilities ----------------
local function warnf(fmt, ...)
	warn("[GF-War] " .. string.format(fmt, ...))
end

-- deterministic window seed: FNV-1a-ish hash over campaignSeed/region/window, 31-bit positive
local function windowSeed(campaignSeed: number, rid: string, window: number): number
	local h = 2166136261
	local function mix(x)
		h = bit32.band(bit32.bxor(h, x % 2147483648) * 16777619, 2147483647)
	end
	mix(campaignSeed)
	for i = 1, #rid do
		mix(string.byte(rid, i))
	end
	mix(window)
	return h
end

local function regionKey(rid: string): string
	return STORE_PREFIX .. rid
end

local function getRegionStore(rid: string)
	if regionStores[rid] ~= nil then
		return regionStores[rid] or nil -- cached false-negative as false
	end
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(regionKey(rid))
	end)
	if ok then
		regionStores[rid] = s
		return s
	end
	regionStores[rid] = false
	return nil
end

local function defaultRecord(rid: string): {}
	-- cold-war initial conditions: frontline regions start hot (the war is ongoing)
	local hot = {AshenDivide = {0.65, 0.6, 0.22, 0.25, 0.08}, VerdantReach = {0.7, 0.65, 0.16, 0.2, 0.05}}
	local iv = hot[rid] or {0.75, 0.7, 0.05, 0.1, 0.0}
	return {
		schema = SCHEMA,
		x = {E = iv[1], L = iv[2], H = iv[3], I = iv[4], S = iv[5]},
		t_integrated = os.time(),
		version = 0,
		recentOps = {},
		lastCoAt = 0,
		coCount = 0,
		actEWMA = 0.0, -- successful ops/day regional estimator state
		actT = os.time(),
		status = "ascendancy_dominance",
		statusSince = os.time(),
		contribTotals = {ops = 0, byDifficulty = {}},
	}
end

-- ---------------- meta record (campaign seed, adaptation state) ----------------
local metaState = nil -- cached copy; refreshed lazily

local function loadMeta()
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(META_KEY)
	end)
	if not ok then
		return nil
	end
	storeMeta = s
	local got, rec = pcall(function()
		return s:GetAsync("meta")
	end)
	if got and type(rec) == "table" then
		metaState = rec
		return rec
	end
	-- initialize
	metaState = {
		schema = SCHEMA,
		campaignSeed = math.random(1, 2147483646),
		startedAt = os.time(),
		adapt = {g = 1.0, sc = 1.0, actEWMA = 0.0, actT = os.time()},
	}
	pcall(function()
		s:SetAsync("meta", metaState)
	end)
	return metaState
end

-- ---------------- integration core ----------------
-- Integrate a region record forward to nowSec inside the UpdateAsync transform.
-- Deterministic counteroffensives: each hour-window's RNG derives from the campaign seed,
-- so replaying the same window against the same state produces identical events.
-- neighborL: snapshot of neighbor logistics levels for network coupling (piecewise-constant
-- approximation — documented in the architecture spec).
local function integrateRecord(rec, rid: string, nowSec: number, campaignSeed: number, indBoost: number, netLog: number)
	local x = rec.x
	local region = {E = x.E, L = x.L, H = x.H, I = x.I, S = x.S, status = rec.status, statusSince = rec.statusSince}
	local t = rec.t_integrated
	local elapsed = math.max(0, nowSec - t)
	local hours = math.min(MAX_CATCHUP_HOURS, math.floor(elapsed / 3600))
	if hours < 1 then
		return region, rec, 0
	end
	-- pressure lever: adaptation scales enemy recovery/reinforcement rates AND event
	-- frequency (never contest/security — validated sim semantics). table copy once per
	-- integration, not per hour.
	local g = (metaState and metaState.adapt and metaState.adapt.g) or 1.0
	local pe = P
	if g ~= 1.0 then
		pe = table.clone(P)
		pe.rE = P.rE * g
		pe.rL = P.rL * g
		pe.lambda0 = P.lambda0 * g
	end
	for h = 1, hours do
		local hourIndex = math.floor((t + h * 3600) / 3600)
		-- endogenous step: THE validated semantics, with coupling inputs frozen from the
		-- neighbor snapshot read before the transform (piecewise-constant approximation,
		-- spec sec.2.2 — indBoost/netLog are neighbor-only functions, own-L is live)
		WarModel.stepRegion(region, pe, 1.0, indBoost, netLog)
		-- deterministic counteroffensive roll for this window
		if (t + h * 3600) - (rec.lastCoAt or 0) >= pe.min_interval_hours * 3600 then
			local rng = Random.new(windowSeed(campaignSeed, rid, hourIndex))
			local hazard = WarModel.counteroffensiveHazard(region, pe)
			if rng:NextNumber() < hazard then
				WarModel.applyCounteroffensive(region, P, rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber())
				rec.lastCoAt = t + h * 3600
				rec.coCount = (rec.coCount or 0) + 1
			end
		end
		-- classification with hysteresis (hourIndex units, consistent within integration)
		WarModel.classify(region, hourIndex, P)
	end
	rec.t_integrated = t + hours * 3600
	rec.x = {E = region.E, L = region.L, H = region.H, I = region.I, S = region.S}
	rec.status = region.status
	rec.statusSince = region.statusSince or rec.statusSince
	return region, rec, hours
end

-- read neighbor logistics levels for the piecewise-constant coupling approximation.
-- direct GetAsync reads (never inside the transform — transforms cannot yield).
local function readNeighborCoupling(rid: string): (number, number)
	local neighborL = {}
	for _, n in ipairs(WarModel.TERRITORIES[rid].neighbors) do
		local L = 0.7 -- cold-start default if unreadable
		local store = getRegionStore(n)
		if store then
			local ok, rec = pcall(function()
				return store:GetAsync("state")
			end)
			if ok and type(rec) == "table" and type(rec.x) == "table" then
				L = rec.x.L
			end
		end
		neighborL[n] = L
	end
	return WarModel.couplingInputs(rid, function(n)
		return neighborL[n] or 0.7
	end)
end

-- ---------------- public API ----------------

-- read the current snapshot for a region, integrating forward opportunistically.
-- returns the snapshot table or nil on failure. cached in MemoryStore for fan-out cost.
function WarStateService.getRegionSnapshot(rid: string)
	local store = getRegionStore(rid)
	if not store then
		return nil
	end
	local nowSec = os.time()
	local seed = (metaState and metaState.campaignSeed) or 1
	local indBoost, netLog = readNeighborCoupling(rid)
	local ok, result = pcall(function()
		return store:UpdateAsync("state", function(old)
			local rec = if type(old) == "table" then old else defaultRecord(rid)
			integrateRecord(rec, rid, nowSec, seed, indBoost, netLog)
			rec.version = (rec.version or 0) + 1
			return rec
		end)
	end)
	if not ok or type(result) ~= "table" then
		return nil
	end
	return {
		rid = rid,
		x = result.x,
		status = result.status,
		coCount = result.coCount or 0,
		lastCoAt = result.lastCoAt or 0,
		t = result.t_integrated,
		version = result.version,
	}
end

-- apply a validated operation contribution. exactly-once via idempotency ring.
-- opInstanceId: key into WarModel.OPERATIONS. difficulty: Easy/Normal/Hard/Extreme.
-- uniqueOpId: stable id of this specific mission run (for dedup across retry/crash).
-- squadMult: sqrt(P_qualified) computed by the caller from validated participation.
-- returns (applied:boolean, committedStateOrNil)
function WarStateService.recordOperation(rid: string, opInstanceId: string, difficulty: string, uniqueOpId: string, squadMult: number)
	local store = getRegionStore(rid)
	if not store then
		warnf("no datastore for %s; contribution of %s DROPPED-QUEUED(unchecked)", rid, uniqueOpId)
		return false, nil
	end
	local opdef = WarModel.OPERATIONS[opInstanceId]
	if not opdef or opdef.region ~= rid then
		warnf("op %s not bound to %s; contribution rejected", opInstanceId, rid)
		return false, nil
	end
	if not P.w[difficulty] then
		warnf("bad difficulty %s", tostring(difficulty))
		return false, nil
	end
	local nowSec = os.time()
	local seed = (metaState and metaState.campaignSeed) or 1
	local indBoost, netLog = readNeighborCoupling(rid)
	local applied = false
	local ok, result = pcall(function()
		return store:UpdateAsync("state", function(old)
			local rec = if type(old) == "table" then old else defaultRecord(rid)
			-- idempotency: reject duplicates inside the atomic transform
			for _, seen in ipairs(rec.recentOps or {}) do
				if seen == uniqueOpId then
					return nil -- abort write; already applied
				end
			end
			integrateRecord(rec, rid, nowSec, seed, indBoost, netLog)
			-- contribution: adaptation input lever is global; squad mult from caller
			local sc = (metaState and metaState.adapt and metaState.adapt.sc) or 1.0
			local region = {E = rec.x.E, L = rec.x.L, H = rec.x.H, I = rec.x.I, S = rec.x.S}
			WarModel.applyContribution(region, opInstanceId, difficulty, P, sc * math.max(1.0, squadMult or 1.0))
			rec.x = {E = region.E, L = region.L, H = region.H, I = region.I, S = region.S}
			-- activity estimator: decayed per-op EWMA (exactly-once with the contribution)
			local dtDays = math.max(0, nowSec - (rec.actT or nowSec)) / 86400
			local decay = math.exp(-P.alpha_act * dtDays)
			rec.actEWMA = (rec.actEWMA or 0) * decay + 1
			rec.actT = nowSec
			-- idempotency ring
			rec.recentOps = rec.recentOps or {}
			table.insert(rec.recentOps, uniqueOpId)
			while #rec.recentOps > IDEMPOTENCY_RING do
				table.remove(rec.recentOps, 1)
			end
			rec.contribTotals = rec.contribTotals or {ops = 0, byDifficulty = {}}
			rec.contribTotals.ops += 1
			rec.contribTotals.byDifficulty[difficulty] = (rec.contribTotals.byDifficulty[difficulty] or 0) + 1
			rec.version = (rec.version or 0) + 1
			applied = true
			return rec
		end)
	end)
	if not ok then
		warnf("UpdateAsync failed for %s op %s", rid, uniqueOpId)
		return false, nil
	end
	if result == nil then
		return false, nil -- duplicate
	end
	if applied then
		WarStateService.publishSnapshot(rid, result)
	end
	return applied, result
end

-- publish the committed state to the MemoryStore snapshot cache + workspace attributes
function WarStateService.publishSnapshot(rid: string, rec)
	if snapCache then
		pcall(function()
			snapCache:SetAsync(SNAP_KEY_PREFIX .. rid, {
				x = rec.x,
				status = rec.status,
				lastCoAt = rec.lastCoAt or 0,
				t = rec.t_integrated,
			}, 600)
		end)
	end
	-- workspace attributes: compact transition-era snapshot for clients/UI
	local prefix = "GF_WarState_" .. rid .. "_"
	workspace:SetAttribute(prefix .. "E", math.floor(rec.x.E * 100) / 100)
	workspace:SetAttribute(prefix .. "L", math.floor(rec.x.L * 100) / 100)
	workspace:SetAttribute(prefix .. "H", math.floor(rec.x.H * 100) / 100)
	workspace:SetAttribute(prefix .. "I", math.floor(rec.x.I * 100) / 100)
	workspace:SetAttribute(prefix .. "S", math.floor(rec.x.S * 100) / 100)
	workspace:SetAttribute(prefix .. "Status", rec.status)
	workspace:SetAttribute(prefix .. "T", rec.t_integrated)
end

-- theater snapshot for the planetary UI: all regions, best-effort
function WarStateService.getTheaterSnapshot()
	local out = {}
	for rid in pairs(WarModel.TERRITORIES) do
		out[rid] = WarStateService.getRegionSnapshot(rid)
	end
	return out
end

-- adaptation pass: aggregate regional activity estimators into the theater-wide rate,
-- move pressure/contribution levers toward targets at the bounded rate (spec sec.7).
-- Â = sum over regions of decayed per-op EWMA × alpha — ops/day. runs every few hours;
-- movement is bounded per elapsed day so cadence variation cannot destabilize the levers.
function WarStateService.updateAdaptation()
	if not storeMeta or not metaState then
		return
	end
	local nowSec = os.time()
	local actSum = 0.0
	for rid in pairs(WarModel.TERRITORIES) do
		local store = getRegionStore(rid)
		if store then
			local ok, rec = pcall(function()
				return store:GetAsync("state")
			end)
			if ok and type(rec) == "table" then
				local dtDays = math.max(0, nowSec - (rec.actT or nowSec)) / 86400
				actSum += (rec.actEWMA or 0) * math.exp(-P.alpha_act * dtDays)
			end
		end
	end
	local activity = actSum * P.alpha_act -- equilibrium inversion: W = R/alpha per day
	local ok = pcall(function()
		storeMeta:UpdateAsync("meta", function(old)
			local rec = if type(old) == "table" then old else metaState
			rec.adapt = rec.adapt or {g = 1.0, sc = 1.0, actT = nowSec}
			local elapsedDays = math.max(0, nowSec - (rec.adapt.actT or nowSec)) / 86400
			local gTarget = math.min(P.g_max, math.max(P.g_min, activity / P.A0))
			local scTarget = math.min(P.sc_max, math.max(1.0, (P.A0 / math.max(activity, 1.0)) ^ 0.5))
			-- bounded approach: adapt_rate fraction of current value per elapsed day
			local function approach(cur, target)
				local maxMove = P.adapt_rate * elapsedDays * cur
				local delta = target - cur
				return cur + math.min(maxMove, math.max(-maxMove, delta))
			end
			rec.adapt.g = approach(rec.adapt.g or 1.0, gTarget)
			rec.adapt.sc = approach(rec.adapt.sc or 1.0, scTarget)
			rec.adapt.actEWMA = activity
			rec.adapt.actT = nowSec
			return rec
		end)
	end)
	if ok then
		loadMeta() -- refresh cache
	end
end

-- keepalive: integrate one random region on a randomized timer so counteroffensives
-- surface theater-wide within tens of minutes even at low population (spec sec.6).
function WarStateService.start()
	if started then
		return
	end
	started = true
	loadMeta()
	pcall(function()
		snapCache = MemoryStoreService:GetHashMap("GF_WarSnapshots")
	end)
	-- initial publish of all regions (lazy integration touches each once)
	task.spawn(function()
		for rid in pairs(WarModel.TERRITORIES) do
			local snap = WarStateService.getRegionSnapshot(rid)
			if snap then
				WarStateService.publishSnapshot(rid, {x = snap.x, status = snap.status, lastCoAt = snap.lastCoAt, t_integrated = snap.t})
			end
			task.wait(1) -- spread datastore pressure
		end
	end)
	-- keepalive loop
	task.spawn(function()
		local rids = {}
		for rid in pairs(WarModel.TERRITORIES) do
			table.insert(rids, rid)
		end
		local lastAdapt = os.time()
		while true do
			task.wait(480 + math.random(0, 240)) -- 8-12 min randomized
			local rid = rids[math.random(1, #rids)]
			local snap = WarStateService.getRegionSnapshot(rid)
			if snap then
				WarStateService.publishSnapshot(rid, {x = snap.x, status = snap.status, lastCoAt = snap.lastCoAt, t_integrated = snap.t})
			end
			-- adaptation cadence: every ~3 hours (levers move at days-scale; this is ample)
			if os.time() - lastAdapt >= 3 * 3600 then
				lastAdapt = os.time()
				WarStateService.updateAdaptation()
			end
		end
	end)
end

return WarStateService
