--!strict
-- EncounterZones: exports spatial encounter structure for EncounterDirector consumption.
-- The battlefield generator never spawns anything — it produces ZONES, ROUTES and ANCHORS as
-- data; EncounterDirector stays the sole spawn authority. Design per brief section 12 and the
-- Helldivers patrol research: intermittent activity, believable patrol routes, quiet intervals,
-- no spawning in the player's face.

local EncounterZones = {}

-- Zone kinds exported:
--   garrison:      stationary defenders tied to an installation; activation radius gates sim cost
--   patrol_route:  polyline loop or path a patrol group marches; biased across likely player
--                  approach lanes but NOT spawning on top of them
--   checkpoint:    stationary small position at a route junction or chokepoint
--   reinforcement: approach region enemy reinforcements arrive through (edges of installations)
--   quiet:         corridors intentionally kept sparse so traversal has tension variance
--   extraction_pressure: region around extraction that heats up when extraction is called

-- Build patrol routes by linking installation anchors through navigable waypoints.
-- Uses the already-computed route graph edges plus ring paths around outposts. Returns zones
-- ready for EncounterDirector.
function EncounterZones.build(plan, installations, rng): { any }
	local zones = {}
	local nodes = plan.nodes

	-- Garrison per installation, sized by family.
	local sizes = { small = 2, outpost = 4, base = 6, primary = 8 }
	for _, inst in installations do
		table.insert(zones, {
			kind = "garrison",
			x = inst.x, z = inst.z,
			radius = inst.template.footprintRadius * 1.3,
			activationRadius = 220, -- dormant until players approach: perf budget guard
			size = sizes[inst.template.family] or 3,
			installationId = inst.template.id,
		})
		-- reinforcement approach regions per template sockets
		for _, ra in inst.template.reinforcementAccess do
			local c, s = math.cos(inst.yaw), math.sin(inst.yaw)
			local wx = inst.x + ra.x * c - ra.z * s
			local wz = inst.z + ra.x * s + ra.z * c
			table.insert(zones, {
				kind = "reinforcement",
				x = wx, z = wz,
				radius = ra.width * 2,
				dir = ra.dir + inst.yaw,
				installationId = inst.template.id,
			})
		end
	end

	-- Patrol routes: connect outposts/defensive positions in pairs through terrain waypoints.
	-- Routes are biased to cross the LZ->primary corridor at distance from spawn (Helldivers
	-- pattern: visible approaching patrols the player chooses to engage or avoid).
	local patrolAnchors = {}
	for _, inst in installations do
		if inst.template.family == "small" or inst.template.family == "outpost" then
			table.insert(patrolAnchors, inst)
		end
	end
	for i = 1, #patrolAnchors - 1 do
		local a, b = patrolAnchors[i], patrolAnchors[i + 1]
		local d = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		if d < 500 and d > 120 then
			table.insert(zones, {
				kind = "patrol_route",
				ax = a.x, az = a.z, bx = b.x, bz = b.z,
				loop = true,
				size = 2 + math.floor(rng() * 2), -- 2-3 strong patrol squads at baseline
				interval = 45 + math.floor(rng() * 30), -- spawn interval seconds, staggered
			})
		end
	end

	-- Quiet corridors: a band around the direct LZ route for the first 40% of its length —
	-- deployment should not instantly contact. EncounterDirector treats spawn avoidance here.
	do
		local lz, primary = nodes.lz, nodes.primary
		local qx = lz.x + (primary.x - lz.x) * 0.25
		local qz = lz.z + (primary.z - lz.z) * 0.25
		table.insert(zones, {
			kind = "quiet",
			x = qx, z = qz,
			radius = 130,
		})
	end

	-- Extraction pressure region.
	table.insert(zones, {
		kind = "extraction_pressure",
		x = nodes.extraction.x, z = nodes.extraction.z,
		radius = 160,
	})

	return zones
end

return EncounterZones
