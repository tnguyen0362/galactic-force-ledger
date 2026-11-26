-- Dump one passing plan per archetype to STDOUT (CLI has no io); python splits/renders.
local BattlefieldService = require("./BattlefieldService")
local SeedStream = require("./SeedStream")
local Archetypes = require("./Archetypes")

local wanted = { highland_valley=true, canyon_network=true, fortified_plateau=true, open_plains=true, broken_basin=true, industrial_wasteland=true }
local s = 0
while next(wanted) and s < 400 do
	s += 1
	local masterSeed = 1000 + s * 131
	local archRng = SeedStream.stream(masterSeed, "archetype")
	local predicted = Archetypes.select("SABOTAGE_RELAY", "Highland", archRng, nil)
	if wanted[predicted] then
		local plan = BattlefieldService.plan(masterSeed, "SABOTAGE_RELAY", "Normal")
		if plan and plan.archetype == predicted then
			wanted[predicted] = nil
			local grid = plan.grid
			print(string.format("BEGIN arch=%s seed=%d nx=%d nz=%d step=%.1f extent=1500", plan.archetype, plan.seed, grid.nx, grid.nz, grid.step))
			for _, key in { "lz", "primary", "extraction" } do
				local n = plan.nodes[key]
				if n then print(string.format("node %s %.1f %.1f", key, n.x, n.z)) end
			end
			for _, inst in plan.installations or {} do
				print(string.format("inst %s %.1f %.1f %.1f", tostring((type(inst.template) == "table" and (inst.template.id or inst.template.name)) or inst.template or inst.id or "?"), inst.x, inst.z, (type(inst.template) == "table" and inst.template.footprintRadius) or inst.footprint or 30))
			end
			for _, rname in { "primary", "alternate" } do
				local r = plan.routes and plan.routes[rname]
				if r and r.points then
					local parts = { "route " .. rname }
					for k = 1, #r.points, 2 do
						parts[#parts+1] = string.format("%.1f,%.1f", r.points[k], r.points[k+1])
					end
					print(table.concat(parts, " "))
				end
			end
			for _, c in plan.cover or {} do
				print(string.format("cover %s %.1f %.1f", tostring(c.kind or "rock"), c.x, c.z))
			end
			for _, z in plan.encounterZones or {} do
				print(string.format("zone %s %.1f %.1f %.1f", tostring(z.kind or "?"), z.x, z.z, z.radius or 30))
			end
			print("heights")
			for i = 1, grid.nx do
				local row = {}
				for j = 1, grid.nz do
					row[#row+1] = string.format("%.1f", grid.heights[i][j])
				end
				print(table.concat(row, " "))
			end
			print("END")
		end
	end
end
print("ALLDONE")
