--!strict
-- TerrainAnalysis: placement intelligence over generated geography. After GeographyService
-- reconstructs a foundation, this scans the decoded heightfield and produces the spatial
-- metadata the operation generator consumes (directive section 23: placement feasibility):
--   * flat candidate sites tagged by footprint size (stronghold 85 studs vs outpost 34)
--   * valley-floor / slope / elevation classification
--   * route-axis positions between deployment and primary
--   * extraction candidates with landing clearance
-- Everything derives from the live heightfield — works for any seed/orientation.
-- Deterministic per foundation: same geography -> same analysis.

local TerrainAnalysis = {}

export type Site = {
	x: number,
	z: number,
	y: number,
	slope: number,       -- mean gradient magnitude in neighborhood
	flatness: number,    -- 0..1 fraction of neighborhood below slope threshold
	elevation: number,   -- y for convenience
	region: string,      -- "valley" | "lowland" | "highland" | "peak"
	score: number,
}

export type Analysis = {
	sites: { Site },          -- placement-feasible candidates, sorted by score desc
	valleyFloor: { Site },    -- subset in lowlands
	highGround: { Site },     -- subset on high ground
	sampleSpacing: number,
	halfExtent: number,
	minY: number,
	maxY: number,
}

-- analyze a heightfield sampler over the extent; resolution 40 studs (fine enough for
-- footprint decisions, cheap enough for boot-time compute)
function TerrainAnalysis.analyze(sample: (number, number) -> number, halfExtent: number, resolution: number?): Analysis
	local res = resolution or 40
	local n = math.floor((halfExtent * 2) / res)
	local minY, maxY = math.huge, -math.huge

	-- first pass: height+classify grid
	local H = table.create(n)
	for ix = 0, n - 1 do
		H[ix] = table.create(n)
		for iz = 0, n - 1 do
			local x = -halfExtent + (ix + 0.5) * res
			local z = -halfExtent + (iz + 0.5) * res
			local h = sample(x, z)
			H[ix][iz] = h
			minY = math.min(minY, h)
			maxY = math.max(maxY, h)
		end
	end

	local relief = maxY - minY
	local sites: { Site } = {}
	local valley: { Site } = {}
	local high: { Site } = {}

	for ix = 1, n - 2 do
		for iz = 1, n - 2 do
			local h = H[ix][iz]
			-- slope from 3x3 neighborhood
			local gx = (H[ix + 1][iz] - H[ix - 1][iz]) / (2 * res)
			local gz = (H[ix][iz + 1] - H[ix][iz - 1]) / (2 * res)
			local slope = math.sqrt(gx * gx + gz * gz)
			-- flatness: fraction of neighborhood within +-3 studs of center height
			local flat = 0
			local cnt = 0
			for dx = -1, 1 do
				for dz = -1, 1 do
					cnt += 1
					if math.abs(H[ix + dx][iz + dz] - h) < 3 then flat += 1 end
				end
			end
			flat = flat / cnt
			local x = -halfExtent + (ix + 0.5) * res
			local z = -halfExtent + (iz + 0.5) * res
			-- region classification by elevation band
			local band = (h - minY) / math.max(relief, 1)
			local region = "valley"
			if band > 0.75 then region = "peak"
			elseif band > 0.5 then region = "highland"
			elseif band > 0.25 then region = "lowland" end
			-- placement score: flatness dominates, slope rejects
			if slope < 0.22 and flat > 0.66 then
				local score = flat * 2 - slope * 3
				local site: Site = {
					x = x, z = z, y = h, slope = slope, flatness = flat,
					elevation = h, region = region, score = score,
				}
				table.insert(sites, site)
				if region == "valley" or region == "lowland" then
					table.insert(valley, site)
				end
				if region == "highland" then
					table.insert(high, site)
				end
			end
		end
	end

	table.sort(sites, function(a, b) return a.score > b.score end)
	table.sort(valley, function(a, b) return a.score > b.score end)
	table.sort(high, function(a, b) return a.score > b.score end)

	return {
		sites = sites,
		valleyFloor = valley,
		highGround = high,
		sampleSpacing = res,
		halfExtent = halfExtent,
		minY = minY,
		maxY = maxY,
	}
end

-- pick spatially-distributed sites: greedy selection enforcing minimum separation
function TerrainAnalysis.distributed(sites: { Site }, count: number, minSeparation: number): { Site }
	local chosen: { Site } = {}
	for _, s in sites do
		if #chosen >= count then break end
		local ok = true
		for _, c in chosen do
			local dx, dz = s.x - c.x, s.z - c.z
			if math.sqrt(dx * dx + dz * dz) < minSeparation then
				ok = false
				break
			end
		end
		if ok then table.insert(chosen, s) end
	end
	return chosen
end

-- find a site nearest to a target position meeting constraints
function TerrainAnalysis.nearest(sites: { Site }, x: number, z: number, minDist: number?, maxDist: number?): Site?
	local best: Site? = nil
	local bestD = math.huge
	for _, s in sites do
		local dx, dz = s.x - x, s.z - z
		local d = math.sqrt(dx * dx + dz * dz)
		if (not minDist or d >= minDist) and (not maxDist or d <= maxDist) and d < bestD then
			best = s
			bestD = d
		end
	end
	return best
end

return TerrainAnalysis
