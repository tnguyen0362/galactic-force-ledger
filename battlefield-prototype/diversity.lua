-- Anti-repetition evidence: feature vectors across seeds must differ meaningfully.
-- Measures pairwise cosine distance of the F vector across a batch of passing plans.
local BattlefieldService = require("./BattlefieldService")
local Metrics = require("./Metrics")
local SeedStream = require("./SeedStream")

local function cosine(a, b)
	local dot, na, nb = 0, 0, 0
	for i = 1, #a do
		dot += a[i] * b[i]
		na += a[i] * a[i]
		nb += b[i] * b[i]
	end
	if na < 1e-9 or nb < 1e-9 then return 0 end
	return dot / (math.sqrt(na) * math.sqrt(nb))
end

print("=== feature-vector diversity across 24 plans ===")
local plans = {}
for s = 1, 24 do
	local plan = BattlefieldService.plan(5000 + s * 977, "SABOTAGE_RELAY", "Normal")
	if plan then
		local rng = SeedStream.stream(plan.seed, "validation")
		local fv = Metrics.featureVector(plan.grid, plan.routes, plan.nodes.primary.x, plan.nodes.primary.z, rng)
		table.insert(plans, { seed = plan.seed, arch = plan.archetype, fv = fv })
	end
end
print("plans generated:", #plans)
local sims = {}
for i = 1, #plans do
	for j = i + 1, #plans do
		table.insert(sims, cosine(plans[i].fv, plans[j].fv))
	end
end
table.sort(sims)
local function pct(p)
	return sims[math.max(1, math.floor(#sims * p))]
end
print(string.format("pairwise cosine similarity (lower=more diverse): min=%.3f med=%.3f p90=%.3f max=%.3f",
	sims[1], pct(0.5), pct(0.9), sims[#sims]))
-- within-archetype vs cross-archetype diversity
local withinAcross = { within = {}, across = {} }
for i = 1, #plans do
	for j = i + 1, #plans do
		local c = cosine(plans[i].fv, plans[j].fv)
		if plans[i].arch == plans[j].arch then
			table.insert(withinAcross.within, c)
		else
			table.insert(withinAcross.across, c)
		end
	end
end
local function mean(t)
	local s = 0
	for _, v in t do s += v end
	return #t > 0 and s / #t or 0
end
print(string.format("mean similarity within-archetype=%.3f cross-archetype=%.3f (n=%d/%d)",
	mean(withinAcross.within), mean(withinAcross.across), #withinAcross.within, #withinAcross.across))
