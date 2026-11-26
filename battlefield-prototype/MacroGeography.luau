--!strict
-- MacroGeography: per-archetype landform composers. Each composer produces a SAMPLER
-- (x,z) -> height plus a HINTS table describing macro structure the layout solver needs
-- (valley centerlines, plateau centers, basin cells). Pure math — no Instances, no raycasts.
--
-- Composition contract per the brief:
--   H(x,z) = Macro(x,z) + Detail(x,z) + Ridge(x,z) + Feature(x,z)
-- Macro is the deliberate archetype structure; Detail is roughness-modulated octaves;
-- Ridge is directional ridged crests; Feature is deliberate valleys/plateaus/excavations.

local NoiseKit = require(script.Parent.NoiseKit)

local MacroGeography = {}

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Shared detail layer: mid+fine octaves modulated by the spatially-variable roughness field.
local function detailLayer(x: number, z: number, seed: number, def: any): number
	local r = NoiseKit.roughness(x, z, def.roughScale, seed + 40, def.roughLo, def.roughHi)
	local mid = NoiseKit.fbm(x, z, 74, seed + 7, 3) * 15
	local fine = NoiseKit.fbm(x, z, 28, seed + 13, 2) * 5
	return r * (mid + fine)
end

-- Shared terrace pass honoring the brief: preserve angular stylization, prevent staircase
-- artifacts by leaving a smooth fraction.
local function terrace(h: number, def: any): number
	if def.terraceStep <= 0 or def.terraceStrength <= 0 then
		return h
	end
	local step = def.terraceStep
	local q = math.floor(h / step) * step
	local frac = (h - q) / step
	-- sharp base level + smoothed partial rise; strength controls how sharp the strata read
	local terraced = q + frac * step * (1 - def.terraceStrength) + (frac > 0.85 and (frac - 0.85) / 0.15 or 0) * step * def.terraceStrength * 0.4
	return h * (1 - def.terraceStrength) + terraced * def.terraceStrength
end

-- Seeded wander line: a gently meandering polyline across the map used as valley/canyon axes.
-- Deterministic in seed; waypoint count low so the curve stays readable at macro scale.
local function wanderAxis(seed: number, extent: number, waypoints: number, meander: number, angle: number): { number }
	local rng = Random.new(seed)
	local pts = {}
	local c, s = math.cos(angle), math.sin(angle)
	for i = 0, waypoints do
		local t = i / waypoints
		local along = (t - 0.5) * extent * 1.15
		local across = (rng:NextNumber() - 0.5) * 2 * meander * math.sin(math.pi * t)
		local x = along * c - across * s
		local z = along * s + across * c
		table.insert(pts, x)
		table.insert(pts, z)
	end
	return pts
end

-- Each composer receives (seed, def, extent) and returns (sampler, hints).
local composers = {}

-- HIGHLAND VALLEY: two warped parallel ridgelines enclosing a traversable lowland.
-- Valley axis wanders across the map; ridges rise with distance from the axis; side re-entrants
-- come free from domain warping + noise modulation of valley width.
composers.highland_valley = function(seed: number, def: any, extent: number)
	local angle = def.ridgeAngle + (NoiseKit.hash(1, 1, seed) - 0.5) * math.rad(40)
	local axis = wanderAxis(seed + 3, extent, 5, extent * 0.16, angle)
	local function sampler(x: number, z: number): number
		local wx, wz = NoiseKit.warp2(x, z, def.warpScale, def.warpAmp, seed)
		-- valley cross-distance drives the main landform
		local d = NoiseKit.polylineDistance(wx, wz, axis)
		local halfWidth = 150 + 70 * NoiseKit.n2(wx, wz, 240, seed + 21)
		local wallT = smoothstep((d - halfWidth) / 190)
		-- ridged crest detail along the enclosing ranges, anisotropic along valley axis
		local ridgeMask = wallT
		local crest = NoiseKit.directionalRidged(wx, wz, 130, seed + 21, angle, def.ridgeAniso) ^ 3
		local macro = wallT * def.relief + crest * 22 * ridgeMask
		-- valley floor gently undulates but stays low
		local floor = NoiseKit.warpedFbm(x, z, 200, seed + 5, 2, def.warpScale, def.warpAmp) * 5 * (1 - wallT)
		return def.baseHeight + macro + floor + detailLayer(x, z, seed, def)
	end
	return sampler, { axis = axis, axisAngle = angle, kind = "valley" }
end

-- CANYON NETWORK: voronoi border channels carved into a plateau — branching ravines with
-- elevated inter-channel plateaus. f2-f1 small => near a border => carve down.
composers.canyon_network = function(seed: number, def: any, extent: number)
	local cellScale = 300
	local function sampler(x: number, z: number): number
		local wx, wz = NoiseKit.warp2(x, z, def.warpScale, def.warpAmp * 0.7, seed)
		local f1, f2 = NoiseKit.voronoi(wx, wz, cellScale, seed + 31)
		local border = 1 - math.clamp((f2 - f1) / 0.55, 0, 1) -- 1 at channel centerline
		local channel = border ^ 1.6
		-- plateau tops at cell interiors, warped ridged noise gives rim character
		local interior = 1 - channel
		local crest = NoiseKit.ridged(wx, wz, 90, seed + 37) ^ 2
		local macro = interior * def.relief * 0.62 + crest * 8 * interior - channel * def.relief * 0.38
		return def.baseHeight + macro + detailLayer(x, z, seed, def) * (0.4 + 0.6 * interior)
	end
	return sampler, { cellScale = cellScale, kind = "canyon" }
end

-- FORTIFIED PLATEAU: a dominant elevated bench/mesa occupying a broad region, terraced slopes,
-- lower surrounding apron. The plateau center is seeded off-center so approaches differ per seed.
composers.fortified_plateau = function(seed: number, def: any, extent: number)
	local rng = Random.new(seed + 41)
	local pa = rng:NextNumber() * math.pi * 2
	local pd = rng:NextNumber() * extent * 0.14
	local cx, cz = math.cos(pa) * pd, math.sin(pa) * pd
	local radius = extent * rng:NextNumber(0.22, 0.30)
	local function sampler(x: number, z: number): number
		local wx, wz = NoiseKit.warp2(x, z, def.warpScale, def.warpAmp, seed)
		local d = math.sqrt((wx - cx) ^ 2 + (wz - cz) ^ 2)
		-- plateau edge softens over ~140 studs, warped so the rim isn't circular
		local rimNoise = NoiseKit.n2(wx, wz, 120, seed + 43) * 60
		local t = smoothstep(1 - (d - rimNoise) / (radius * 1.35))
		local bench = smoothstep((radius - d + rimNoise) / 150)
		local macro = bench * def.relief * 1.25
		-- exposed slope character: directional ridges radiating outward faintly
		local apron = NoiseKit.warpedFbm(x, z, 180, seed + 47, 2, def.warpScale, def.warpAmp) * 7
		return def.baseHeight + macro + apron + detailLayer(x, z, seed, def)
	end
	return sampler, { center = { cx, cz }, radius = radius, kind = "plateau" }
end

-- OPEN PLAINS: low-relief rolling warped fbm with occasional isolated ridge lines.
composers.open_plains = function(seed: number, def: any, extent: number)
	local angle = NoiseKit.hash(2, 5, seed) * math.pi
	local function sampler(x: number, z: number): number
		local wx, wz = NoiseKit.warp2(x, z, def.warpScale, def.warpAmp, seed)
		local rolling = NoiseKit.fbm(wx, wz, 210, seed + 53, 3) * def.relief * 1.35
		-- sparse isolated ridges: ridged noise gated by a low-frequency mask so most of the
		-- field stays open and only some bands carry elevation
		local gate = NoiseKit.mask(wx, wz, 420, seed + 59, 0.62, 0.86)
		local crest = NoiseKit.directionalRidged(wx, wz, 150, seed + 61, angle, def.ridgeAniso) ^ 3
		local macro = rolling + crest * 18 * gate
		return def.baseHeight + macro + detailLayer(x, z, seed, def)
	end
	return sampler, { ridgeAngle = angle, kind = "plains" }
end

-- BROKEN BASIN: voronoi cells as compartments — sunken clearings inside cells, raised rims at
-- borders. Inverse of canyon: you fight IN the clearings and cross rims between them.
composers.broken_basin = function(seed: number, def: any, extent: number)
	local cellScale = 340
	local function sampler(x: number, z: number): number
		local wx, wz = NoiseKit.warp2(x, z, def.warpScale, def.warpAmp * 0.75, seed)
		local f1, f2, cellSeed = NoiseKit.voronoi(wx, wz, cellScale, seed + 67)
		local border = 1 - math.clamp((f2 - f1) / 0.42, 0, 1)
		local rim = border ^ 1.6
		-- per-cell depth variance makes some basins deeper/more open than others
		local depth = 0.55 + cellSeed * 0.65
		local macro = rim * def.relief * 0.85 - (1 - rim) * def.relief * 0.34 * depth
		return def.baseHeight + macro + detailLayer(x, z, seed, def) * (0.5 + 0.5 * rim)
	end
	return sampler, { cellScale = cellScale, kind = "basin" }
end

-- INDUSTRIAL WASTELAND: rolling low terrain plus deliberate excavation basins at seeded sites —
-- large negative features where extraction-era industry cut into the ground.
composers.industrial_wasteland = function(seed: number, def: any, extent: number)
	local rng = Random.new(seed + 71)
	local sites = {}
	for _ = 1, 3 do
		local a = rng:NextNumber() * math.pi * 2
		local d = rng:NextNumber() * extent * 0.3
		table.insert(sites, {
			x = math.cos(a) * d,
			z = math.sin(a) * d,
			r = rng:NextNumber(90, 170),
			depth = rng:NextNumber(10, 20),
		})
	end
	local function sampler(x: number, z: number): number
		local wx, wz = NoiseKit.warp2(x, z, def.warpScale, def.warpAmp, seed)
		local rolling = NoiseKit.fbm(wx, wz, 190, seed + 73, 3) * def.relief * 1.05
		local excav = 0
		for _, s in sites do
			local d = math.sqrt((x - s.x) ^ 2 + (z - s.z) ^ 2)
			local t = smoothstep(1 - d / s.r)
			-- stepped excavation: benches cut into the pit walls
			local pit = t * s.depth
			pit = math.floor(pit / 4) * 4 + (pit % 4) * 0.5
			excav = math.max(excav, pit)
		end
		return def.baseHeight + rolling - excav + detailLayer(x, z, seed, def)
	end
	return sampler, { excavations = sites, kind = "industrial" }
end

-- Compose final sampler: archetype macro + terrace pass. Returns sampler and hints.
function MacroGeography.compose(archetypeId: string, seed: number, extent: number): ((number, number) -> number, any)
	local Archetypes = require(script.Parent.Archetypes)
	local def = Archetypes.get(archetypeId)
	local composer = composers[archetypeId]
	if not composer then
		composer = composers.highland_valley
		def = Archetypes.get("highland_valley")
	end
	local raw, hints = composer(seed, def, extent)
	local function sampler(x: number, z: number): number
		return terrace(raw(x, z), def)
	end
	hints.archetype = def.id
	return sampler, hints, def
end


-- Foundation shaping pass: given the base sampler and a list of flatten sites
-- {x, z, radius, falloff}, produce the shaped sampler that levels installation/LZ footprints.
-- Anchor height is the natural height at the site center — the foundation cuts/fills symmetrically
-- around what the geography already wanted to be, which keeps installations embedded rather than
-- perched. Within `radius` the terrain is fully level; falloff blends outward smoothly.
function MacroGeography.applyFlattening(baseSampler: (number, number) -> number, sites: { { x: number, z: number, radius: number, falloff: number? } }): (number, number) -> number
	if #sites == 0 then
		return baseSampler
	end
	local anchors = {}
	for i, site in sites do
		anchors[i] = baseSampler(site.x, site.z)
	end
	return function(x: number, z: number): number
		local h = baseSampler(x, z)
		for i, site in sites do
			local dx, dz = x - site.x, z - site.z
			local d = math.sqrt(dx * dx + dz * dz)
			local radius = site.radius
			local falloff = site.falloff or radius * 0.7
			if d < radius + falloff then
				local t
				if d <= radius then
					t = 1
				else
					local u = 1 - (d - radius) / falloff
					t = u * u * (3 - 2 * u)
				end
				h = h * (1 - t) + anchors[i] * t
			end
		end
		return h
	end
end

return MacroGeography
