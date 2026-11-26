-- raw correlation-length distributions per archetype, bypassing validation
local MacroGeography = require("./MacroGeography")
local RegionAnalysis = require("./RegionAnalysis")
local Metrics = require("./Metrics")
local Archetypes = require("./Archetypes")

local EXTENT = 1500
for _, arch in { "fortified_plateau", "open_plains", "highland_valley", "broken_basin", "canyon_network", "industrial_wasteland" } do
	local def = Archetypes.get(arch)
	local vals = {}
	for s = 1, 6 do
		local sampler = MacroGeography.compose(arch, 77000 + s * 101, EXTENT)
		-- compose returns (sampler, hints, def) - check signature
		if type(sampler) == "function" then
			-- build a coarse grid manually
			local grid = RegionAnalysis.build(sampler, EXTENT, 8)
			local cl = Metrics.correlationLength(grid)
			table.insert(vals, cl)
		else
			print(arch, "compose did not return sampler as first value")
			break
		end
	end
	if #vals > 0 then
		table.sort(vals)
		print(string.format("%s: corrLen min/med/max = %.0f/%.0f/%.0f  band=[%.0f,%.0f]",
			arch, vals[1], vals[math.ceil(#vals/2)], vals[#vals], def.correlationLength.min, def.correlationLength.max))
	end
end
