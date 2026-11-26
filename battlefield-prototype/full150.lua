-- Full acceptance-style offline validation: 150 seeds + determinism + diversity measurement.
local BattlefieldService = require("./BattlefieldService")
local Metrics = require("./Metrics")
local SeedStream = require("./SeedStream")

-- 1) determinism: same master seed twice, compare key outputs
print("=== determinism ===")
local function fingerprint(plan)
	return string.format("%s|%.2f|%.2f|%.2f|%.2f|%d", plan.archetype,
		plan.nodes.lz.x, plan.nodes.lz.z, plan.nodes.primary.x, plan.nodes.primary.z, #plan.installations)
end
local p1 = BattlefieldService.plan(999001, "SABOTAGE_RELAY", "Normal")
local p2 = BattlefieldService.plan(999001, "SABOTAGE_RELAY", "Normal")
print("same-seed identical:", fingerprint(p1) == fingerprint(p2), fingerprint(p1))

-- 2) 150-seed batch across the 5 mission families
print("=== 150-seed batch ===")
local t0 = os.clock()
local batch = BattlefieldService.batchValidate(150, { "SABOTAGE_RELAY", "RECOVER_TECH", "DEFEND_BEACON", "ELIMINATION", "CONQUEST" })
local dt = os.clock() - t0
print(string.format("passRate=%.3f (%d/%d) in %.1fs (%.2fs/seed)", batch.passRate, batch.passed, batch.count, dt, dt / batch.count))
print("reject reasons:")
for k, v in pairs(batch.rejectReasons) do print("  ", k, v) end
local archCount = {}
local routeLens = {}
local seps = {}
for _, r in ipairs(batch.results) do
	if r.pass then
		archCount[r.archetype] = (archCount[r.archetype] or 0) + 1
		table.insert(routeLens, r.routeLen)
		table.insert(seps, r.separation)
	end
end
print("archetype spread:")
for k, v in pairs(archCount) do print("  ", k, v) end
table.sort(routeLens)
table.sort(seps)
if #routeLens > 0 then
	print(string.format("routeLen min/med/max: %.0f / %.0f / %.0f", routeLens[1], routeLens[math.floor(#routeLens/2)], routeLens[#routeLens]))
	print(string.format("separation min/med/max: %.0f / %.0f / %.0f", seps[1], seps[math.floor(#seps/2)], seps[#seps]))
end
-- per-attempt distribution: how many seeds pass on first try
local firstTry = 0
for _, r in ipairs(batch.results) do
	if r.pass then firstTry += 1 end -- batchValidate records only final plans; attempts tracked inside
end
