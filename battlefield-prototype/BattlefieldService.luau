--!strict
-- BattlefieldService: orchestrator. seed + missionTemplate + difficulty in -> validated
-- BattlefieldPlan out. Pure data, no Instances — the plan is consumed by Mission/Terrain/
-- placement services which do the actual world building.

local SeedStream = require(script.Parent.SeedStream)
local Archetypes = require(script.Parent.Archetypes)
local MacroGeography = require(script.Parent.MacroGeography)
local RegionAnalysis = require(script.Parent.RegionAnalysis)
local Topology = require(script.Parent.Topology)
local Metrics = require(script.Parent.Metrics)
local Templates = require(script.Parent.Templates)
local Placement = require(script.Parent.Placement)
local Cover = require(script.Parent.Cover)
local EncounterZones = require(script.Parent.EncounterZones)

local BattlefieldService = {}

-- 1664 studs baseline extent per program doc; routing grid at 8-stud resolution (208x208 cells).
local EXTENT = 1664
local GRID_STEP = 8
local MAX_SLOPE = 30
local MAX_SEED_ATTEMPTS = 8

export type Plan = {
	seed: number,
	archetype: string,
	extent: number,
	sampler: (number, number) -> number,
	grid: any,
	hints: any,
	nodes: any,
	routes: any,
	report: any,
	generatorVersion: string,
}

local GENERATOR_VERSION = "2.0-alpha"

-- Node spacing/validity specs for the mandatory mission topology. Optional nodes (outposts,
-- defensive positions) are placed by the installation pass later — these are the skeleton.
local function nodeSpecs()
	return {
		{ id = "lz", minSpacing = 0, maxSlope = 18 },
		{ id = "primary", minSpacing = 760, maxSlope = 16 },
		{ id = "extraction", minSpacing = 200, maxSlope = 18 },
	}
end

-- Feature-anchored mission topology. Visual evidence (test/mapdump renders) showed the old
-- uniform-random placement dropped primaries in terrain irrelevant to the archetype — never on
-- the plateau, never in the valley — and clustered the whole mission footprint in one quadrant.
-- Now: archetypes with a dominant feature anchor the primary AT that feature; the LZ is then
-- placed across the map so traversal crosses the macro geography. Anchorless archetypes keep
-- sampling but must place the primary on the opposing half of the map from the LZ.
local function featureAnchor(hints: any): (number?, number?)
	if not hints then return nil, nil end
	if hints.kind == "plateau" and hints.center then
		return hints.center[1], hints.center[2]
	end
	if hints.kind == "industrial" and hints.excavations and #hints.excavations > 0 then
		local sx, sz, n = 0, 0, 0
		for _, s in hints.excavations do sx += s.x sz += s.z n += 1 end
		return sx / n, sz / n
	end
	if hints.kind == "valley" and hints.axis then
		-- axis is a flat waypoint list; use its midpoint
		local n = math.floor(#hints.axis / 2)
		local mid = math.max(1, math.floor(n / 2)) * 2 - 1
		return hints.axis[mid], hints.axis[mid + 1]
	end
	return nil, nil
end

local function placeTopology(grid, rng, hints: any): any
	local half = grid.nx * grid.step / 2
	local ax, az = featureAnchor(hints)

	local primary = nil
	if ax then
		-- anchored: jitter around the feature so orientation varies per seed
		for _ = 1, 60 do
			local x = ax + (rng() - 0.5) * 130
			local z = az + (rng() - 0.5) * 130
			if math.abs(x) < half * 0.82 and math.abs(z) < half * 0.82
				and RegionAnalysis.slope(grid, x, z) <= 16 then
				primary = { x = x, z = z, kind = "primary" }
				break
			end
		end
		-- anchor terrain may legitimately be steep (plateau rim) — fall back to the exact center
		if not primary and RegionAnalysis.slope(grid, ax, az) <= 20 then
			primary = { x = ax, z = az, kind = "primary" }
		end
	end

	-- LZ: outer band, and when a primary anchor exists, on the FAR side of the map from it
	-- so traversal crosses the battlefield rather than hugging one corner.
	local lz = nil
	for _ = 1, 140 do
		local x = grid.originX + rng() * (grid.nx - 1) * grid.step
		local z = grid.originZ + rng() * (grid.nz - 1) * grid.step
		local r = math.sqrt(x * x + z * z)
		if r > half * 0.55 and r < half * 0.85 and RegionAnalysis.slope(grid, x, z) <= 18 then
			if primary then
				local d = math.sqrt((x - primary.x) ^ 2 + (z - primary.z) ^ 2)
				if d < 620 or d > 950 then continue end
			end
			lz = { x = x, z = z, kind = "lz" }
			break
		end
	end
	if not lz then return nil end

	-- anchorless primary: sample far from LZ AND biased to the opposing half of the map —
	-- kills the single-quadrant mission footprint visible in the pre-fix renders.
	if not primary then
		local lzLen = math.sqrt(lz.x ^ 2 + lz.z ^ 2)
		for _ = 1, 160 do
			local ang = rng() * math.pi * 2
			local dist = 620 + rng() * 300
			local x = lz.x + math.cos(ang) * dist
			local z = lz.z + math.sin(ang) * dist
			if math.abs(x) < half * 0.82 and math.abs(z) < half * 0.82
				and RegionAnalysis.slope(grid, x, z) <= 16 then
				-- opposing-half test: normalized positions must have negative-ish dot product
				local pLen = math.sqrt(x * x + z * z)
				if lzLen > 1 and pLen > 1 then
					local dot = (lz.x * x + lz.z * z) / (lzLen * pLen)
					if dot > 0.1 then continue end
				end
				primary = { x = x, z = z, kind = "primary" }
				break
			end
		end
	end
	if not primary then return nil end

	-- extraction: 220-480 from primary, clearly off the lz-primary axis (35+ degrees —
	-- was 15, which let extractions sit nearly on the backtrack line).
	local extraction = nil
	local dxp, dzp = primary.x - lz.x, primary.z - lz.z
	local dpLen = math.sqrt(dxp * dxp + dzp * dzp)
	for _ = 1, 120 do
		local ang = rng() * math.pi * 2
		local dist = 220 + rng() * 260
		local x = primary.x + math.cos(ang) * dist
		local z = primary.z + math.sin(ang) * dist
		if math.abs(x) < half * 0.84 and math.abs(z) < half * 0.84
			and RegionAnalysis.slope(grid, x, z) <= 18 then
			local ex, ez = x - primary.x, z - primary.z
			local eLen = math.sqrt(ex * ex + ez * ez)
			if eLen > 1 and dpLen > 1 then
				local cosA = (ex * -dxp + ez * -dzp) / (eLen * dpLen)
				if math.deg(math.acos(math.clamp(cosA, -1, 1))) > 35 then
					extraction = { x = x, z = z, kind = "extraction" }
					break
				end
			end
		end
	end
	if not extraction then return nil end

	return { lz = lz, primary = primary, extraction = extraction }
end

-- One generation attempt for a given master seed. Returns plan or nil + reason.
function BattlefieldService.tryGenerate(masterSeed: number, template: string, difficulty: string?, recentArchetypes: { string }?): (any, string?)
	local archRng = SeedStream.stream(masterSeed, "archetype")
	local archetypeId = Archetypes.select(template, "Highland", archRng, recentArchetypes)
	local geoSeed = SeedStream.seed(masterSeed, "geography")
	local sampler0, hints, def = MacroGeography.compose(archetypeId, geoSeed, EXTENT)
	local sampler = sampler0

	-- shared grid build for topology/placement analysis (rebuilt after foundation shaping)
	local grid = RegionAnalysis.build(sampler0, EXTENT, GRID_STEP)

	local layoutRng = SeedStream.stream(masterSeed, "layout")
	local nodes = placeTopology(grid, layoutRng, hints)
	if not nodes then
		return nil, "topology_placement_failed"
	end

	-- preliminary routing on the UNSHAPED field: small-position anchoring needs route geometry
	-- before installations exist to shape anything. Final routing re-runs on the shaped field.
	local prelimRoutes = Topology.redundantRoutes(grid, nodes.lz.x, nodes.lz.z, nodes.primary.x, nodes.primary.z, MAX_SLOPE, 110)
	if not prelimRoutes then
		return nil, "no_route_lz_primary"
	end
	local routes = nil
	local extractionRoute = nil

	-- STAGE 5: installations. The primary installation IS the objective — anchored at the primary
	-- node, oriented toward the dominant approach. Optional outposts scatter in the midfield band
	-- between LZ and primary; small positions sit near route chokepoints. Placement scoring per
	-- brief section 9; failures degrade gracefully (fewer optionals) rather than failing the seed —
	-- but the primary MUST place.
	local instRng = SeedStream.stream(masterSeed, "installations")
	local installations = {}
	local primaryTemplates = { SABOTAGE_RELAY = "weapons_facility", RECOVER_TECH = "industrial_complex", CONQUEST = "command_stronghold", DEFEND_BEACON = "command_stronghold", ELIMINATION = "command_stronghold" }
	local primaryTemplateId = primaryTemplates[template] or "weapons_facility"
	local primaryTemplate = Templates.get(primaryTemplateId)
	-- orientation: face the LZ approach direction
	local approachYaw = math.atan2(nodes.lz.z - nodes.primary.z, nodes.lz.x - nodes.primary.x)
	local score0, _comp0, reject0 = Placement.scoreCandidate(grid, nodes.primary.x, nodes.primary.z, approachYaw, primaryTemplate, archetypeId, installations)
	if score0 <= -100 then
		return nil, "primary_site_invalid:" .. tostring(reject0)
	end
	table.insert(installations, {
		x = nodes.primary.x, z = nodes.primary.z, yaw = approachYaw,
		template = primaryTemplate, score = score0, role = "primary",
	})

	-- optional outposts: 2-4 in the midfield band, count scaled by difficulty
	local diffOutposts = { Easy = 2, Normal = 3, Hard = 3, Extreme = 4 }
	local targetOutposts = diffOutposts[difficulty or "Normal"] or 3
	local outpostPool = Templates.byFamily("outpost")
	local midX = (nodes.lz.x + nodes.primary.x) / 2
	local midZ = (nodes.lz.z + nodes.primary.z) / 2
	local midDist = math.sqrt((nodes.primary.x - nodes.lz.x) ^ 2 + (nodes.primary.z - nodes.lz.z) ^ 2)
	for _ = 1, targetOutposts do
		local placed = nil
		for attempt = 1, 4 do
			local tdef = outpostPool[1 + math.floor(instRng() * #outpostPool) % #outpostPool]
			-- scatter center jittered around midfield, biased off the direct corridor
			local jx = midX + (instRng() - 0.5) * midDist * 0.7
			local jz = midZ + (instRng() - 0.5) * midDist * 0.7
			placed = Placement.place(grid, tdef, { x = jx, z = jz }, midDist * 0.32, archetypeId, installations, instRng, 30)
			if placed then
				placed.role = "outpost"
				table.insert(installations, placed)
				break
			end
		end
	end

	-- small defensive positions: 3-6 near the primary route interior (chokepoint-flavored)
	local smallPool = Templates.byFamily("small")
	local targetSmall = 3 + math.floor(instRng() * 3)
	local rp = prelimRoutes.primary.points
	for k = 1, targetSmall do
		-- anchor near a waypoint along the primary route interior (20-80% of the path)
		local frac = 0.2 + instRng() * 0.6
		local idx = math.max(1, math.min(math.floor(#rp / 2), math.floor(#rp / 2 * frac)))
		local ax = rp[idx * 2 - 1] or midX
		local az = rp[idx * 2] or midZ
		local tdef = smallPool[1 + math.floor(instRng() * #smallPool) % #smallPool]
		local placed = Placement.place(grid, tdef, { x = ax, z = az }, 120, archetypeId, installations, instRng, 25)
		if placed then
			placed.role = "small"
			table.insert(installations, placed)
		end
	end

	-- STAGE 7: foundation shaping. Installation footprints + LZ pad + extraction pad level the
	-- terrain; routing and validation then run against the SHAPED field — the terrain players
	-- will actually walk. This is the brief's "refine terrain around infrastructure" step.
	local flattenSites = {}
	for _, inst in installations do
		table.insert(flattenSites, { x = inst.x, z = inst.z, radius = inst.template.foundationFlatten })
	end
	table.insert(flattenSites, { x = nodes.lz.x, z = nodes.lz.z, radius = 26, falloff = 24 })
	table.insert(flattenSites, { x = nodes.extraction.x, z = nodes.extraction.z, radius = 32, falloff = 26 })
	local shapedSampler = MacroGeography.applyFlattening(sampler, flattenSites)
	local shapedGrid = RegionAnalysis.build(shapedSampler, EXTENT, GRID_STEP)
	-- final routing over shaped terrain
	routes = Topology.redundantRoutes(shapedGrid, nodes.lz.x, nodes.lz.z, nodes.primary.x, nodes.primary.z, MAX_SLOPE, 110)
	if not routes then
		return nil, "no_route_shaped"
	end
	extractionRoute = Topology.route(shapedGrid, nodes.primary.x, nodes.primary.z, nodes.extraction.x, nodes.extraction.z, MAX_SLOPE)
	if not extractionRoute then
		return nil, "no_extraction_route_shaped"
	end
	grid = shapedGrid
	sampler = shapedSampler

	-- STAGE 8: cover distribution (after installations so interiors are excluded)
	local coverRng = SeedStream.stream(masterSeed, "cover")
	local coverPlacements = Cover.distribute(grid, {
		base = def.composition.rockDensity * 0.62,
		targetCount = 330 + math.floor(coverRng() * 110),
		objectiveFocus = { x = nodes.primary.x, z = nodes.primary.z, radius = 250 },
		minSpacing = 26,
		routes = { routes.primary.points, routes.alternate and routes.alternate.points },
		installations = installations,
		wreckShare = def.composition.wreckDensity * 0.3,
	}, coverRng)

	-- STAGE 9: encounter zones — data export for EncounterDirector
	local encRng = SeedStream.stream(masterSeed, "encounters")
	local encounterZones = EncounterZones.build({ nodes = nodes }, installations, encRng)

	local valRng = SeedStream.stream(masterSeed, "validation")
	local pass, report = Metrics.validate(grid, def, {
		routes = routes,
		primary = nodes.primary,
		minRoute = 620,
		maxRoute = 1150,
		minSeparation = 80,
		minTactical = 2,
	}, valRng)
	-- cover density validation against placed cover near the objective
	local coverDensity = Cover.measureDensity(grid, coverPlacements, nodes.primary.x, nodes.primary.z, 240, 120, valRng)
	report.coverDensity = coverDensity
	if coverDensity < def.coverDensity.min then
		table.insert(report.reasons, "cover_too_sparse:" .. string.format("%.3f", coverDensity))
	end
	if coverDensity > def.coverDensity.max then
		table.insert(report.reasons, "cover_too_dense:" .. string.format("%.3f", coverDensity))
	end
	pass = #report.reasons == 0
	if not pass then
		return nil, table.concat(report.reasons, ";")
	end

	return {
		seed = masterSeed,
		archetype = archetypeId,
		extent = EXTENT,
		sampler = sampler,
		grid = grid,
		hints = hints,
		nodes = nodes,
		routes = routes,
		extractionRoute = extractionRoute,
		installations = installations,
		cover = coverPlacements,
		encounterZones = encounterZones,
		report = report,
		generatorVersion = GENERATOR_VERSION,
	}
end

-- Seeded generate/reject loop: tries up to MAX_SEED_ATTEMPTS derived seeds, returns the first
-- passing plan plus the rejection histogram for tuning visibility.
function BattlefieldService.plan(baseSeed: number, template: string, difficulty: string?, recentArchetypes: { string }?): (any, any)
	local rejections = {}
	local attempts = {}
	for attempt = 0, MAX_SEED_ATTEMPTS - 1 do
		local seed = baseSeed + attempt * 7919
		local plan, reason = BattlefieldService.tryGenerate(seed, template, difficulty, recentArchetypes)
		if plan then
			plan.attempts = attempt + 1
			plan.rejections = rejections
			return plan, { attempts = attempt + 1, rejections = rejections, log = attempts }
		end
		local key = reason and reason:match("^%a[_%a]*") or "unknown"
		rejections[key] = (rejections[key] or 0) + 1
		table.insert(attempts, { seed = seed, reason = reason })
	end
	return nil, { attempts = MAX_SEED_ATTEMPTS, rejections = rejections, log = attempts }
end

-- Offline batch validation: N seeds x M templates, pass rates + metric distributions.
-- This is the GOAL.md 100+ seed dry-run harness entry point; caller decides batch size (brief: 150).
function BattlefieldService.batchValidate(count: number, templates: { string }): any
	local results = {}
	local totalPass = 0
	local totalRejectReasons = {}
	for s = 1, count do
		local template = templates[(s - 1) % #templates + 1]
		local plan, meta = BattlefieldService.plan(1000 + s * 131, template)
		if plan then
			totalPass += 1
			table.insert(results, {
				seed = plan.seed, archetype = plan.archetype, pass = true,
				sigma = plan.report.elevation.sigma,
				routeLen = plan.report.routes and plan.report.routes.primaryLen or 0,
				separation = plan.report.routes and plan.report.routes.separation or 0,
				tactical = plan.report.tacticalPositions or 0,
			})
		else
			for k, v in meta.rejections do
				totalRejectReasons[k] = (totalRejectReasons[k] or 0) + v
			end
			table.insert(results, { seed = 1000 + s * 131, pass = false, reasons = meta.rejections })
		end
	end
	return {
		count = count,
		passed = totalPass,
		passRate = totalPass / count,
		rejectReasons = totalRejectReasons,
		results = results,
	}
end

return BattlefieldService
