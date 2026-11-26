--!strict
-- NoiseKit: pure-math noise/field primitives for battlefield generation.
-- No Instances, no workspace access — everything here is deterministic analytic math over
-- math.noise, composable into archetype landforms. All functions are seed-stable: same inputs
-- always produce the same outputs on the same machine (math.noise is deterministic per seed).

local NoiseKit = {}

-- Basic 2D octave sample in [-1, 1].
function NoiseKit.n2(x: number, z: number, scale: number, seed: number): number
	return math.noise(x / scale, z / scale, seed)
end

-- Fractal octave stack. octaves controls layering; lacunarity scales frequency per octave,
-- persistence scales amplitude. Returns roughly [-1, 1] for typical parameters.
function NoiseKit.fbm(x: number, z: number, scale: number, seed: number, octaves: number, lacunarity: number?, persistence: number?): number
	local lac = lacunarity or 2.0
	local pers = persistence or 0.5
	local amp = 1
	local freq = 1
	local sum = 0
	local norm = 0
	for _ = 1, octaves do
		sum += amp * math.noise(x / (scale / freq), z / (scale / freq), seed)
		norm += amp
		amp *= pers
		freq *= lac
		seed += 101
	end
	return sum / math.max(norm, 1e-6)
end

-- Ridged noise: sharp crest lines instead of rolling bumps. Returns [0, 1]; 1 at crests.
function NoiseKit.ridged(x: number, z: number, scale: number, seed: number): number
	return 1 - math.abs(math.noise(x / scale, z / scale, seed))
end

-- Directional ridged noise: samples in rotated, anisotropically compressed coordinates so ridges
-- elongate along `angle`. aniso ~3-4 gives convincing ranges; 1 is isotropic.
function NoiseKit.directionalRidged(x: number, z: number, scale: number, seed: number, angle: number, aniso: number): number
	local c, s = math.cos(angle), math.sin(angle)
	local rx = x * c - z * s
	local rz = x * s + z * c
	-- compress across-ridge axis so features elongate along the ridge direction
	return NoiseKit.ridged(rx, rz / math.max(aniso, 1e-3), scale, seed)
end

-- Domain warp: returns warped coordinates (wx, wz). amplitude in studs, scale controls meander
-- wavelength. Two independent channels so the vector field isn't diagonal-biased.
function NoiseKit.warp2(x: number, z: number, scale: number, amplitude: number, seed: number): (number, number)
	local wx = x + amplitude * math.noise(x / scale, z / scale, seed + 811)
	local wz = z + amplitude * math.noise(x / scale + 137.3, z / scale - 91.7, seed + 1229)
	return wx, wz
end

-- Warped fbm: the workhorse. Sample fbm at domain-warped coordinates.
function NoiseKit.warpedFbm(x: number, z: number, scale: number, seed: number, octaves: number, warpScale: number, warpAmp: number): number
	local wx, wz = NoiseKit.warp2(x, z, warpScale, warpAmp, seed)
	return NoiseKit.fbm(wx, wz, scale, seed, octaves)
end

-- Smoothstep remap of a noise field into [0,1] — useful for masks (valley floors, basin regions).
function NoiseKit.mask(x: number, z: number, scale: number, seed: number, lo: number, hi: number): number
	local v = math.noise(x / scale, z / scale, seed) * 0.5 + 0.5
	local t = math.clamp((v - lo) / math.max(hi - lo, 1e-6), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Voronoi F1/F2 fields over a jittered lattice. Returns (f1, f2, cellSeed) where f1 is distance to
-- nearest feature point, f2 to second nearest (in lattice units of `scale`). Border regions are
-- where f2 - f1 is small — used for canyon channels and basin rims.
-- Lattice hashing is deterministic per integer cell + seed without Random.new allocations.
local function hash2i(ix: number, iz: number, seed: number): number
	local h = (ix * 374761393 + iz * 668265263 + seed * 2246822519) % 4294967296
	h = (h * 3266489917) % 4294967296
	return (h % 1048576) / 1048576
end

function NoiseKit.voronoi(x: number, z: number, scale: number, seed: number, jitter: number?): (number, number, number)
	local j = jitter or 0.85
	local px, pz = x / scale, z / scale
	local cx, cz = math.floor(px), math.floor(pz)
	local f1, f2 = math.huge, math.huge
	local cellSeed = 0
	for ox = -1, 1 do
		for oz = -1, 1 do
			local gx, gz = cx + ox, cz + oz
			local hx = hash2i(gx, gz, seed)
			local hz = hash2i(gx, gz, seed + 7)
			local fx = gx + 0.5 + (hx - 0.5) * 2 * j
			local fz = gz + 0.5 + (hz - 0.5) * 2 * j
			local d = math.sqrt((px - fx) ^ 2 + (pz - fz) ^ 2)
			if d < f1 then
				f2 = f1
				f1 = d
				cellSeed = hash2i(gx, gz, seed + 13)
			elseif d < f2 then
				f2 = d
			end
		end
	end
	return f1, f2, cellSeed
end

-- Spatially variable roughness field in [lo, hi]: low-frequency smooth control over how much
-- high-frequency detail a region receives. Plains vs crags from one continuous field.
function NoiseKit.roughness(x: number, z: number, scale: number, seed: number, lo: number, hi: number): number
	local v = math.noise(x / scale, z / scale, seed + 3071) * 0.5 + 0.5
	local t = v * v * (3 - 2 * v)
	return lo + (hi - lo) * t
end

-- Spline channel distance: minimum distance from (x,z) to a polyline defined by points.
-- Points as flat array {x1,z1,x2,z2,...}. Used for carving canyons/roads along authored-ish
-- but seeded wandering paths. Returns distance and parametric position t in [0,1] along path.
function NoiseKit.polylineDistance(x: number, z: number, points: { number }): (number, number)
	local best = math.huge
	local bestT = 0
	local totalLen = 0
	local segs = {}
	for i = 1, #points - 3, 2 do
		local ax, az = points[i], points[i + 1]
		local bx, bz = points[i + 2], points[i + 3]
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		table.insert(segs, { ax = ax, az = az, bx = bx, bz = bz, len = len, start = totalLen })
		totalLen += len
	end
	for _, sg in segs do
		local dx, dz = sg.bx - sg.ax, sg.bz - sg.az
		local len2 = dx * dx + dz * dz
		local t = len2 > 1e-6 and math.clamp(((x - sg.ax) * dx + (z - sg.az) * dz) / len2, 0, 1) or 0
		local px, pz = sg.ax + dx * t, sg.az + dz * t
		local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		if d < best then
			best = d
			bestT = totalLen > 1e-6 and (sg.start + sg.len * t) / totalLen or 0
		end
	end
	return best, bestT
end

-- Terrace quantization with continuity preservation: quantize most of the way but keep a smooth
-- fraction so terraces read as angular strata rather than pure staircases. strength in [0,1].
function NoiseKit.terrace(h: number, step: number, strength: number): number
	local q = math.floor(h / step) * step
	local frac = (h - q) / step
	-- sharp terrace fraction pulled toward integer levels, residual smooth fraction preserved
	local sharp = math.floor(h / step) * step
	local smoothH = h
	return sharp * strength + smoothH * (1 - strength) + frac * 0 -- frac folds into smoothH term
end

-- Least-cost path support: gradient estimate of any sampler by central difference.
function NoiseKit.gradient(sampler: (number, number) -> number, x: number, z: number, eps: number?): (number, number)
	local e = eps or 2
	local hx1 = sampler(x + e, z)
	local hx0 = sampler(x - e, z)
	local hz1 = sampler(x, z + e)
	local hz0 = sampler(x, z - e)
	return (hx1 - hx0) / (2 * e), (hz1 - hz0) / (2 * e)
end

-- Slope in degrees at a point on the sampler.
function NoiseKit.slopeDeg(sampler: (number, number) -> number, x: number, z: number, eps: number?): number
	local gx, gz = NoiseKit.gradient(sampler, x, z, eps)
	return math.deg(math.atan(math.sqrt(gx * gx + gz * gz)))
end

-- Deterministic per-cell hash noise in [0,1) — used where math.noise continuity is unwanted
-- (e.g. per-region ids, cover jitter) and for seed stream mixing.
function NoiseKit.hash(x: number, z: number, seed: number): number
	return hash2i(math.floor(x), math.floor(z), seed)
end

return NoiseKit
