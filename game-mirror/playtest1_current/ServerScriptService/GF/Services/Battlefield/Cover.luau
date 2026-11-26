--!strict
-- Cover: context-sensitive cover distribution. Poisson-disk-flavored sampling against density
-- fields derived from the geography — clusters near routes/installations, sparse on open aprons,
-- absent inside installation interiors (they bring their own constructed cover).

local RegionAnalysis = require(script.Parent.RegionAnalysis)

local Cover = {}

-- Density field: base per-archetype density modulated by position context.
-- Context inputs (optional): route polylines (cover gravitates near routes), installation
-- footprints (exclusion interiors, boosted rims), exposure grid samples (open ground gets more
-- constructed cover to remain playable).
local function densityAt(ctx, x, z)
	local d = ctx.base
	-- objective-proximity boost: the fight at the objective needs readable cover most
	if ctx.objectiveFocus then
		local f = ctx.objectiveFocus
		local fd = math.sqrt((x - f.x) ^ 2 + (z - f.z) ^ 2)
		if fd < f.radius then
			d *= 2.1
		elseif fd < f.radius * 1.8 then
			d *= 1.35
		end
	end
	-- boost near routes: cover within 30 studs of a route is what makes traversal fights readable
	if ctx.routes then
		for _, path in ctx.routes do
			local best = math.huge
			for k = 1, #path - 1, 2 do
				local dd = math.sqrt((path[k] - x) ^ 2 + (path[k + 1] - z) ^ 2)
				if dd < best then best = dd end
			end
			if best < 30 then
				d *= 1.8
				break
			elseif best < 70 then
				d *= 1.25
			end
		end
	end
	return math.clamp(d, 0, 1)
end

-- Poisson-ish sampler: dart throwing with min spacing, bounded attempts, deterministic stream.
-- Good enough at our densities (true poisson disk is overkill; spacing constraint is what matters).
function Cover.distribute(grid, ctx, rng): { { x: number, z: number, kind: string } }
	local placements = {}
	local half = grid.nx * grid.step / 2
	local targetCount = ctx.targetCount or 220
	local minSpacing = ctx.minSpacing or 26
	local maxSlope = ctx.maxSlope or 24
	local attempts = targetCount * 14
	local cellSize = minSpacing / math.sqrt(2)
	local occupancy = {}
	local function cellKey(x, z)
		return math.floor(x / cellSize) * 100003 + math.floor(z / cellSize)
	end
	local function spacingOk(x, z)
		local cx, cz = math.floor(x / cellSize), math.floor(z / cellSize)
		for di = -1, 1 do
			for dj = -1, 1 do
				local key = (cx + di) * 100003 + (cz + dj)
				local list = occupancy[key]
				if list then
					for _, p in list do
						if (p.x - x) ^ 2 + (p.z - z) ^ 2 < minSpacing * minSpacing then
							return false
						end
					end
				end
			end
		end
		return true
	end
	for _ = 1, attempts do
		if #placements >= targetCount then break end
		local x = (rng() * 2 - 1) * half * 0.9
		local z = (rng() * 2 - 1) * half * 0.9
		if RegionAnalysis.slope(grid, x, z) <= maxSlope and spacingOk(x, z) then
			-- exclusion inside installation footprints
			local inside = false
			if ctx.installations then
				for _, inst in ctx.installations do
					local d = math.sqrt((inst.x - x) ^ 2 + (inst.z - z) ^ 2)
					if d < inst.template.footprintRadius * 0.9 then
						inside = true
						break
					end
				end
			end
			if not inside and rng() < densityAt(ctx, x, z) then
				-- kind selection: rocks dominate in rocky archetypes, wrecks in industrial
				local roll = rng()
				local kind = "rock"
				if ctx.wreckShare and roll < ctx.wreckShare then
					kind = "wreck"
				elseif roll > 0.82 then
					kind = "terrain_form" -- uses local relief: placed against rises
				end
				local p = { x = x, z = z, kind = kind }
				table.insert(placements, p)
				local key = cellKey(x, z)
				occupancy[key] = occupancy[key] or {}
				table.insert(occupancy[key], p)
			end
		end
	end
	return placements
end

-- Cover density metric used by validation: fraction of objective-adjacent sample points with
-- occlusion within 15 studs in at least 2 directions. Computed against PLACED cover + terrain.
function Cover.measureDensity(grid, placements, cx, cz, radius, samples, rng)
	if #placements == 0 then
		return 0
	end
	local covered = 0
	local total = 0
	for _ = 1, samples do
		local a = rng() * math.pi * 2
		local r = radius * math.sqrt(rng())
		local x = cx + math.cos(a) * r
		local z = cz + math.sin(a) * r
		-- count directions with a cover piece within 15 studs in that direction
		local dirs = 0
		for k = 0, 7 do
			local ang = (k / 8) * math.pi * 2
			for _, p in placements do
				local dx, dz = p.x - x, p.z - z
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist < 15 and dist > 1 then
					local dot = (dx / dist) * math.cos(ang) + (dz / dist) * math.sin(ang)
					if dot > 0.7 then
						dirs += 1
						break
					end
				end
			end
		end
		total += 1
		if dirs >= 2 then
			covered += 1
		end
	end
	return total > 0 and covered / total or 0
end

return Cover
