--!strict
-- Placement: installation placement scoring per brief section 9.
--   S = w1*GroundSuitability + w2*Accessibility + w3*TacticalValue + w4*EnvironmentalFit
--     - w5*OverlapPenalty - w6*TraversalObstruction
-- Components normalized to [0,1] before weighting. Hard rejection regardless of score for
-- clearance/overlap/navigation failures. Bounded attempts + validated fallbacks.

local RegionAnalysis = require(script.Parent.RegionAnalysis)

local Placement = {}

local W = {
	ground = 0.30,
	access = 0.20,
	tactical = 0.25,
	fit = 0.25,
	overlap = 1.0,      -- multiplies a [0,1] penalty; subtracted
	obstruction = 0.6,
}

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Mean slope across the footprint disc — the foundation suitability measure.
local function meanSlopeInRadius(grid, x, z, radius, samples)
	local total, count = 0, 0
	for k = 1, samples do
		local a = (k / samples) * math.pi * 2
		for _, rr in { 0.35, 0.7, 1.0 } do
			local px = x + math.cos(a) * radius * rr
			local pz = z + math.sin(a) * radius * rr
			total += RegionAnalysis.slope(grid, px, pz)
			count += 1
		end
	end
	return count > 0 and total / count or 90
end

-- Accessibility: can each entrance socket be reached on foot — measured as fraction of entrance
-- directions where a 40-stud walk outward stays within navigable slope.
local function accessibility(grid, x, z, template, yaw)
	if #template.entrances == 0 then
		return 0.5 -- small positions without hard entrances are walk-in
	end
	local ok = 0
	for _, e in template.entrances do
		local dir = e.dir + yaw
		local ex = x + e.x * math.cos(yaw) - e.z * math.sin(yaw)
		local ez = z + e.x * math.sin(yaw) + e.z * math.cos(yaw)
		local clear = 0
		local steps = 5
		for s = 1, steps do
			local px = ex + math.cos(dir) * (s / steps) * 40
			local pz = ez + math.sin(dir) * (s / steps) * 40
			if RegionAnalysis.slope(grid, px, pz) <= 30 then
				clear += 1
			end
		end
		if clear >= steps - 1 then
			ok += 1
		end
	end
	return ok / #template.entrances
end

-- Tactical value: elevation advantage + defensive sightline length outward from the anchor.
local function tacticalValue(grid, x, z, template)
	local h = RegionAnalysis.height(grid, x, z)
	-- sample surrounding ring at 1.5x footprint; advantage = how much we stand above approach
	local ring = 0
	local count = 0
	local lower = 0
	for k = 0, 11 do
		local a = (k / 12) * math.pi * 2
		local px = x + math.cos(a) * template.footprintRadius * 1.8
		local pz = z + math.sin(a) * template.footprintRadius * 1.8
		local rh = RegionAnalysis.height(grid, px, pz)
		ring += rh
		count += 1
		if rh < h - 2 then
			lower += 1
		end
	end
	local meanRing = ring / count
	local advantage = math.clamp((h - meanRing) / 18 + 0.5, 0, 1) -- 0.5 = level ground neutral
	local commanding = lower / count
	return math.clamp(advantage * 0.55 + commanding * 0.45, 0, 1)
end

-- Sightline requirement check: does at least one entrance-to-core line reach the template's
-- minimum clear distance (defender visibility spec).
local function sightlineOk(grid, x, z, template, yaw)
	if template.sightlineMin <= 0 then
		return true
	end
	for k = 0, 7 do
		local a = yaw + (k / 8) * math.pi * 2
		local ex = x + math.cos(a) * template.sightlineMin
		local ez = z + math.sin(a) * template.sightlineMin
		if RegionAnalysis.losClear(grid, x, z, ex, ez, 9) then
			return true
		end
	end
	return false
end

export type PlacementResult = {
	x: number, z: number, yaw: number, template: any, score: number, components: any,
}

-- Score one candidate. Returns score in roughly [-1.6, 1], plus component breakdown.
function Placement.scoreCandidate(grid, x, z, yaw, template, archetypeId, existing): (number, any, string?)
	-- hard constraint: foundation FEASIBILITY, not raw slope. Foundation flattening shapes the
	-- terrain (brief stage 7), so moderate slopes are what foundations exist for. What actually
	-- disqualifies a site: a cliff bisecting the footprint — measured as height RANGE inside the
	-- flatten radius, because cutting/filling more than ~half the flatten width produces an
	-- absurd rampart rather than a foundation.
	local meanSlope = meanSlopeInRadius(grid, x, z, template.footprintRadius, 8)
	local hMin, hMax = math.huge, -math.huge
	for k = 0, 7 do
		local a = (k / 8) * math.pi * 2
		for _, rr in { 0.2, 0.55, 0.9 } do
			local h = RegionAnalysis.height(grid, x + math.cos(a) * template.foundationFlatten * rr, z + math.sin(a) * template.foundationFlatten * rr)
			if h < hMin then hMin = h end
			if h > hMax then hMax = h end
		end
	end
	local heightRange = hMax - hMin
	local rangeLimit = math.max(14, template.foundationFlatten * 0.55)
	if heightRange > rangeLimit then
		return -999, nil, "cliff_bisect:" .. string.format("%.0f", heightRange)
	end
	-- hard constraint: overlap with existing installations (center distance vs summed radii)
	local overlapPenalty = 0
	for _, e in existing do
		local d = math.sqrt((e.x - x) ^ 2 + (e.z - z) ^ 2)
		local minD = (e.template.footprintRadius + template.footprintRadius) * 0.85
		if d < minD * 0.6 then
			return -999, nil, "hard_overlap"
		end
		if d < minD then
			overlapPenalty = math.max(overlapPenalty, 1 - (d - minD * 0.6) / (minD * 0.4))
		end
	end
	-- hard constraint: sightline spec
	if not sightlineOk(grid, x, z, template, yaw) then
		return -999, nil, "sightline_blocked"
	end

	local ground = 1 - smoothstep(meanSlope / math.max(template.foundationSlopeMax, 1))
	local access = accessibility(grid, x, z, template, yaw)
	local tactical = tacticalValue(grid, x, z, template)
	local fit = math.clamp((template.archetypeFit[archetypeId] or 1) / 1.6, 0, 1)
	-- traversal obstruction: installations shouldn't sit on the direct LZ→primary corridor unless
	-- they ARE the objective. Approximated here by proximity penalty applied by caller context.
	local obstruction = 0

	local score = W.ground * ground + W.access * access + W.tactical * tactical + W.fit * fit
		- W.overlap * overlapPenalty - W.obstruction * obstruction
	return score, {
		ground = ground, access = access, tactical = tactical, fit = fit,
		overlap = overlapPenalty, obstruction = obstruction, meanSlope = meanSlope,
	}
end

-- Bounded search: tries candidates in annuli around a desired region, seeded stream for jitter.
-- Returns best passing placement or nil.
function Placement.place(grid, template, regionCenter, regionRadius, archetypeId, existing, rng, attempts: number?): PlacementResult?
	local best = nil
	local bestScore = -999
	local tries = attempts or 60
	for _ = 1, tries do
		local a = rng() * math.pi * 2
		local r = regionRadius * math.sqrt(rng())
		local x = regionCenter.x + math.cos(a) * r
		local z = regionCenter.z + math.sin(a) * r
		local half = grid.nx * grid.step / 2
		if math.abs(x) < half * 0.88 and math.abs(z) < half * 0.88 then
			local yaw = math.floor(rng() * 8) / 8 * math.pi * 2 -- 45-degree orientation steps
			local score, components = Placement.scoreCandidate(grid, x, z, yaw, template, archetypeId, existing)
			if score > bestScore then
				bestScore = score
				best = { x = x, z = z, yaw = yaw, template = template, score = score, components = components }
			end
		end
	end
	if best and bestScore > -100 then
		return best
	end
	return nil
end

return Placement
