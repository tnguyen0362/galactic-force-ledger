local BattlefieldService = require("./BattlefieldService")
local SeedStream = require("./SeedStream")
local Archetypes = require("./Archetypes")
-- scan seeds, find canyon selections, report first-attempt failure reasons
local reasons = {}
local tested = 0
for s = 1, 120 do
	local masterSeed = 1000 + s * 131
	local archRng = SeedStream.stream(masterSeed, "archetype")
	local predicted = Archetypes.select("SABOTAGE_RELAY", "Highland", archRng, nil)
	if predicted == "canyon_network" and tested < 8 then
		tested += 1
		local plan, reason = BattlefieldService.tryGenerate(masterSeed, "SABOTAGE_RELAY", "Normal")
		if plan then
			print("seed", masterSeed, "PASS")
		else
			print("seed", masterSeed, "FAIL:", tostring(reason))
			local key = tostring(reason):match("^%a[_%a]*") or "unknown"
			reasons[key] = (reasons[key] or 0) + 1
		end
	end
end
print("summary:")
for k, v in reasons do print("  ", k, v) end
