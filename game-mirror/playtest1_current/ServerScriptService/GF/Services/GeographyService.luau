--!strict
-- GeographyService: runtime geographical generation — layer 1 of the hybrid procedural
-- architecture (owner directive 2026-11-25). Deterministic stream G selects:
--   * geographical foundation (real-world elevation crops, genuinely distinct landforms)
--   * orientation (rotation x mirror — legitimate coherence-preserving transforms)
--   * controlled deformation (conservative height-scale jitter, +/-5% max)
-- and reconstructs the terrain at mission init via adaptive-region WriteVoxels.
--
-- Performance notes (2026-11-27 optimization pass): the writer still emits the same
-- fractional-occupancy shell voxels as BakeTerrain, including the original 128-stud tile
-- boundary behaviour for slope/material continuity and adaptive clipping. The hot path is
-- reorganized rather than redesigned:
--   * delta+b85 decode avoids the temporary multi-megabyte concatenated string copy
--   * heightfield sampling is direct buffer arithmetic (no per-sample closure allocation)
--   * each 4-stud height sample is computed once per tile instead of up to five times
--   * empty z-columns inside WriteVoxels input arrays are shared immutable rows, so the
--     writer no longer allocates and populates hundreds of thousands of all-air tables
--   * write regions follow the surface: large rectangles in flat country, recursively
--     split rectangles in high-relief country. This cuts dense input volume roughly in
--     half without changing any non-air voxel.
-- Memory remains bounded by the decoded heightfield plus one small tile cache; there is
-- no persistent world-sized copy.

local Terrain = workspace.Terrain
local ServerScriptService = game:GetService("ServerScriptService")

local GeographyService = {}

-- foundation registry: fv1 is the approved Teton prototype (regression reference).
-- fv2-fv6 are structurally distinct real-world crops (scan_candidates, gf-geo).
local FOUNDATIONS = {
	{ id = "fv1", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
	{ id = "fv2", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
	{ id = "fv3", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
	{ id = "fv4", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563852 },
	{ id = "fv5", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563852 },
	{ id = "fv6", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
	-- cascades volcanic province (mt rainier region): steeper, younger landforms
	{ id = "fv7", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
	{ id = "fv8", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
	{ id = "fv9", chunks = 36, n = 1250, base = 24.0, quant = 0.25, rawlen = 1563750 },
}

export type GeoSpec = {
	foundation: number,
	rotation: number, -- 0..3 (90-degree steps)
	mirror: boolean,
	heightScale: number, -- 0.95..1.05 controlled deformation
	seed: number,
}

-- deterministic stream G: independent of composition/operation streams
function GeographyService.specFromSeed(seed: number): GeoSpec
	local rng = Random.new(seed * 7919 + 13)
	return {
		foundation = rng:NextInteger(1, #FOUNDATIONS),
		rotation = rng:NextInteger(0, 3),
		mirror = rng:NextInteger(0, 1) == 1,
		heightScale = 1 + (rng:NextNumber() - 0.5) * 0.10,
		seed = seed,
	}
end

-- ===================== fast heightfield decode =====================
-- Same on-disk format as HeightfieldCodec (base85 + row delta). This local decoder is
-- byte-indexed rather than substring-indexed and consumes the 36 modules as a stream of
-- parts, avoiding both millions of tiny string allocations and the temporary concatenated
-- payload copy. The exporter pads the final base85 group to a four-byte boundary; decoding
-- the padded length also preserves the final one-to-three real payload bytes correctly.
local B85 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_`{|}~"
local REV_BYTE: { [number]: number } = {}
for i = 1, #B85 do
	REV_BYTE[string.byte(B85, i)] = i - 1
end

local function b85decodeParts(parts: { string }): buffer
	local totalChars = 0
	for _, s in parts do
		totalChars += #s
	end
	local buf = buffer.create((totalChars // 5) * 4)
	local pos = 0
	-- Localized hot-path globals: one byteswapped u32 write replaces four byte extraction
	-- divisions/writes per group. bit32 arguments are modulo 2^32, exactly matching the
	-- base85 payload contract (five digits encode one unsigned 32-bit big-endian word).
	local rev = REV_BYTE
	local sbyte = string.byte
	local writeu32 = buffer.writeu32
	local byteswap = bit32.byteswap
	for _, s in parts do
		-- export_modules.py uses 55,000-character chunks; 55,000 is divisible by five,
		-- and the total payload is group-aligned, so no carry across chunk boundaries exists.
		assert(#s % 5 == 0, "heightfield chunk is not base85 group aligned")
		local i = 1
		local n = #s
		while i + 4 <= n do
			local c1, c2, c3, c4, c5 = sbyte(s, i, i + 4)
			local v = rev[c1] or 0
			v = v * 85 + (rev[c2] or 0)
			v = v * 85 + (rev[c3] or 0)
			v = v * 85 + (rev[c4] or 0)
			v = v * 85 + (rev[c5] or 0)
			-- big-endian 4 bytes, same as HeightfieldCodec
			writeu32(buf, pos, byteswap(v))
			pos += 4
			i += 5
		end
	end
	return buf
end

local function decodeHeightfield(parts: { string }, n: number, base: number, quant: number, _rawlen: number)
	local packed = b85decodeParts(parts)
	-- reconstruct quantized grid into uint16 buffer (row-major, col0 absolute uint16LE,
	-- then signed byte deltas; escape 127 = followed by absolute uint16LE)
	local grid = buffer.create(n * n * 2)
	local gp = 0
	local pp = 0
	local readu16 = buffer.readu16
	local readu8 = buffer.readu8
	local writeu16 = buffer.writeu16
	for _r = 0, n - 1 do
		local prev = 0
		for c = 0, n - 1 do
			local v
			if c == 0 then
				v = readu16(packed, pp)
				pp += 2
			else
				local b = readu8(packed, pp)
				pp += 1
				if b == 127 then
					v = readu16(packed, pp)
					pp += 2
				else
					local d = if b < 128 then b else b - 256
					v = prev + d
				end
			end
			writeu16(grid, gp, v)
			gp += 2
			prev = v
		end
	end

	local hf: any = {
		n = n,
		base = base,
		quant = quant,
		heights = grid,
	}
	function hf.raw(row: number, col: number): number
		local idx = (row * n + col) * 2
		return base + buffer.readu16(grid, idx) * quant
	end
	-- sample in grid-index space: x,z are fractional grid coordinates 0..n-1, bilinear.
	-- Unlike the generic codec sample this does not allocate a nested rv closure per call.
	function hf.sample(gx: number, gz: number): number
		local x0 = math.clamp(math.floor(gx), 0, n - 2)
		local z0 = math.clamp(math.floor(gz), 0, n - 2)
		local fx = math.clamp(gx - x0, 0, 1)
		local fz = math.clamp(gz - z0, 0, 1)
		local i00 = (z0 * n + x0) * 2
		local h00 = base + buffer.readu16(grid, i00) * quant
		local h10 = base + buffer.readu16(grid, i00 + 2) * quant
		local h01 = base + buffer.readu16(grid, i00 + n * 2) * quant
		local h11 = base + buffer.readu16(grid, i00 + n * 2 + 2) * quant
		return h00 * (1 - fx) * (1 - fz) + h10 * fx * (1 - fz) + h01 * (1 - fx) * fz + h11 * fx * fz
	end
	return hf
end

local function loadFoundation(f: any)
	local dataFolder = ServerScriptService.GF.Bake.Data
	local parts = table.create(f.chunks)
	for i = 0, f.chunks - 1 do
		local mod = dataFolder:FindFirstChild(string.format("%s_d%02d", f.id, i))
		assert(mod, "missing data chunk " .. f.id .. "_d" .. i)
		parts[i + 1] = require(mod)
	end
	local t0 = os.clock()
	local hf = decodeHeightfield(parts, f.n, f.base, f.quant, f.rawlen)
	return hf, os.clock() - t0
end

-- orientation-aware sampler: world x,z -> heightfield lookup with rotation/mirror.
-- heightfield covers 5000 studs centered on origin; spacing 4 studs/sample.
-- This is the exact arithmetic of HeightfieldCodec.sample inlined once, rather than
-- allocating the codec's nested row-read closure for every sample.
local function orientedSampler(hf: any, spec: GeoSpec)
	local n = hf.n
	local grid = hf.heights
	local base = hf.base
	local quant = hf.quant
	local half = 2500
	local scale = spec.heightScale
	local rotation = spec.rotation
	local mirror = spec.mirror
	return function(x: number, z: number): number
		local u = math.clamp((x + half) / 5000, 0, 1)
		local v = math.clamp((z + half) / 5000, 0, 1)
		if mirror then u = 1 - u end
		local fu, fv
		if rotation == 0 then
			fu, fv = u, v
		elseif rotation == 1 then
			fu, fv = v, 1 - u
		elseif rotation == 2 then
			fu, fv = 1 - u, 1 - v
		else
			fu, fv = 1 - v, u
		end
		local gx = fu * (n - 1)
		local gz = fv * (n - 1)
		local x0 = math.clamp(math.floor(gx), 0, n - 2)
		local z0 = math.clamp(math.floor(gz), 0, n - 2)
		local fx = math.clamp(gx - x0, 0, 1)
		local fz = math.clamp(gz - z0, 0, 1)
		local i00 = (z0 * n + x0) * 2
		local h00 = base + buffer.readu16(grid, i00) * quant
		local h10 = base + buffer.readu16(grid, i00 + 2) * quant
		local h01 = base + buffer.readu16(grid, i00 + n * 2) * quant
		local h11 = base + buffer.readu16(grid, i00 + n * 2 + 2) * quant
		return (h00 * (1 - fx) * (1 - fz) + h10 * fx * (1 - fz) + h01 * (1 - fx) * fz + h11 * fx * fz) * scale
	end
end

-- Specialized form of orientedSampler for the writer's exact 4-stud lattice. The
-- orientation transform is still evaluated with the same arithmetic as the continuous
-- sampler, but only once per lattice coordinate instead of once per column. For a
-- 90-degree rotation the axes are swapped at lookup time. Indices are the writer's
-- integer cell coordinates (-1..n inclusive, including its one-cell border), not studs.
local function orientedLatticeSampler(hf: any, spec: GeoSpec)
	local n = hf.n
	local grid = hf.heights
	local base = hf.base
	local quant = hf.quant
	local half = 2500
	local scale = spec.heightScale
	local rotation = spec.rotation
	local mirror = spec.mirror
	local xBytes = table.create(n + 2)
	local xFracs = table.create(n + 2)
	local zBytes = table.create(n + 2)
	local zFracs = table.create(n + 2)
	for q = -1, n do
		local w = -2498 + q * 4
		local u = math.clamp((w + half) / 5000, 0, 1)
		local v = u
		if mirror then u = 1 - u end
		local fu, fv
		if rotation == 0 then
			fu, fv = u, v
		elseif rotation == 1 then
			fu, fv = v, 1 - u
		elseif rotation == 2 then
			fu, fv = 1 - u, 1 - v
		else
			fu, fv = 1 - v, u
		end
		local gx = fu * (n - 1)
		local gz = fv * (n - 1)
		local x0 = math.clamp(math.floor(gx), 0, n - 2)
		local z0 = math.clamp(math.floor(gz), 0, n - 2)
		local qi = q + 2 -- q=-1 maps to Lua index 1
		xBytes[qi] = x0 * 2
		xFracs[qi] = math.clamp(gx - x0, 0, 1)
		zBytes[qi] = z0 * n * 2
		zFracs[qi] = math.clamp(gz - z0, 0, 1)
	end
	local swapped = rotation % 2 == 1
	local rowStrideBytes = n * 2
	return function(gix: number, giz: number): number
		local gxq = if swapped then giz else gix
		local gzq = if swapped then gix else giz
		local xi = gxq + 2
		local zi = gzq + 2
		local i00 = zBytes[zi] + xBytes[xi]
		local fx = xFracs[xi]
		local fz = zFracs[zi]
		local h00 = base + buffer.readu16(grid, i00) * quant
		local h10 = base + buffer.readu16(grid, i00 + 2) * quant
		local h01 = base + buffer.readu16(grid, i00 + rowStrideBytes) * quant
		local h11 = base + buffer.readu16(grid, i00 + rowStrideBytes + 2) * quant
		return (h00 * (1 - fx) * (1 - fz) + h10 * fx * (1 - fz) + h01 * (1 - fx) * fz + h11 * fx * fz) * scale
	end
end

-- ===================== adaptive exact-shell terrain writer =====================
-- The visible/collidable terrain contract is the BakeTerrain shell writer: fractional
-- occupancy at the surface, up to eight solid shell voxels underneath, the same material
-- noise gates, and the same original 128-stud tile-boundary slope behaviour. What changes
-- is only how those voxels are packed into WriteVoxels calls.
local CELL = 4
local SHELL = 8
local WORLD_CELLS = 1250 -- 5000 studs / 4
local WORLD_HALF = 2500
local FIRST_CENTER = -2498
local ORIG_TILE_CELLS = 32 -- original material/clipping tile: 128 studs
local SUPER_CELLS = 64 -- largest write rectangle: 256 studs
local MIN_LEAF_CELLS = 8 -- do not split a dimension below 32 studs
-- Hoisted enum items: the inner writer evaluates millions of voxels, and every
-- Enum.Material.* expression is otherwise a repeated global/userdata lookup.
local MAT_AIR = Enum.Material.Air
local MAT_GRASS = Enum.Material.Grass
local MAT_GROUND = Enum.Material.Ground
local MAT_ROCK = Enum.Material.Rock
local MAT_SNOW = Enum.Material.Snow
-- Cost of one extra WriteVoxels call expressed in dense input voxels. 4096 is deliberately
-- conservative: flat areas stay in large rectangles, while high-relief areas still split.
local CALL_COST_VOXELS = 4096

-- Recursive binary interval trees used by the adaptive writer. They are immutable and
-- depend only on a dimension length (almost always 64), so cache the handful of shapes
-- instead of rebuilding them for every super-tile.
local intervalTreeCache: { [number]: any } = {}
local function intervalTree(len: number)
	local cached = intervalTreeCache[len]
	if cached then return cached end
	local tree: any = {
		starts = {},
		lens = {},
		lefts = {},
		rights = {},
		lookup = {},
		root = 0,
	}
	local function add(start: number, length: number): number
		local id = #tree.starts + 1
		tree.starts[id] = start
		tree.lens[id] = length
		tree.lookup[start * 512 + length] = id
		if length > MIN_LEAF_CELLS then
			local a = length // 2
			tree.lefts[id] = add(start, a)
			tree.rights[id] = add(start + a, length - a)
		else
			tree.lefts[id] = 0
			tree.rights[id] = 0
		end
		return id
	end
	tree.root = add(1, len)
	intervalTreeCache[len] = tree
	return tree
end

local function buildOriginalTileBounds(sample: (number, number) -> number)
	local tileStuds = 128
	local tiles = math.ceil(5000 / tileStuds)
	local bounds = table.create(tiles * tiles)
	for tx = 0, tiles - 1 do
		for tz = 0, tiles - 1 do
			local x0 = -WORLD_HALF + tx * tileStuds
			local z0 = -WORLD_HALF + tz * tileStuds
			local x1 = math.min(x0 + tileStuds, WORLD_HALF)
			local z1 = math.min(z0 + tileStuds, WORLD_HALF)
			-- probe tile height range (coarse 5x5), exactly as the original writer did
			local tmin, tmax = math.huge, -math.huge
			for px = 0, 4 do
				for pz = 0, 4 do
					local h = sample(x0 + (x1 - x0) * px / 4, z0 + (z1 - z0) * pz / 4)
					tmin = math.min(tmin, h)
					tmax = math.max(tmax, h)
				end
			end
			local yMin = math.floor((tmin - SHELL * CELL - 8) / CELL) * CELL
			local yMax = math.ceil((tmax + 8) / CELL) * CELL
			bounds[tx * tiles + tz + 1] = {
				yMin = yMin,
				yMax = yMax,
				gmin = yMin / CELL,
				gmax = yMax / CELL, -- exclusive cell bound
			}
		end
	end
	return bounds, tiles
end

local function writeFoundationTerrain(sample: (number, number) -> number, latticeSample: ((number, number) -> number)?)
	local t0 = os.clock()
	local mathNoise = math.noise
	local bounds, tiles128 = buildOriginalTileBounds(sample)
	local columnSample = latticeSample or function(gix: number, giz: number): number
		return sample(FIRST_CENTER + gix * CELL, FIRST_CENTER + giz * CELL)
	end
	local superTiles = math.ceil(WORLD_CELLS / SUPER_CELLS)
	local writeCalls = 0
	local inputVoxels = 0
	local heightSamples = 0
	local skippedLeaves = 0

	-- Shared immutable all-air z rows. WriteVoxels only reads its input tables; sharing a
	-- row for untouched y-slices is therefore semantically identical to thousands of copies.
	local airRows: { [number]: any } = {}
	local zeroRows: { [number]: any } = {}
	local function sharedRows(depth: number)
		local a = airRows[depth]
		local z = zeroRows[depth]
		if not a then
			a = table.create(depth, MAT_AIR)
			z = table.create(depth, 0)
			airRows[depth] = a
			zeroRows[depth] = z
		end
		return a, z
	end

	for sx = 0, superTiles - 1 do
		for sz = 0, superTiles - 1 do
			local gx0 = sx * SUPER_CELLS
			local gz0 = sz * SUPER_CELLS
			local w = math.min(SUPER_CELLS, WORLD_CELLS - gx0)
			local d = math.min(SUPER_CELLS, WORLD_CELLS - gz0)

			-- Heights on the local 4-stud lattice plus a one-cell border. The old writer
			-- sampled each interior point as H and then again as as many as four neighbours;
			-- this cache preserves identical positions/values with one sample per point.
			-- Flat indexing avoids a second table indirection for every neighbour read.
			local hstride = d + 2
			local heights = table.create((w + 2) * hstride)
			for cx = 0, w + 1 do
				local gix = gx0 + cx - 1
				local hbase = cx * hstride
				for cz = 0, d + 1 do
					heights[hbase + cz + 1] = columnSample(gix, gz0 + cz - 1)
					heightSamples += 1
				end
			end

			-- Exact vertical cell interval that the original writer would emit for each
			-- horizontal column, including the original tile's adaptive clipping bounds.
			local bottoms: { any } = table.create(w * d, false)
			local tops: { any } = table.create(w * d, false)
			for j = 1, d do
				for i = 1, w do
					local idx = (j - 1) * w + i
					local hidx = i * hstride + j + 1
					local H = heights[hidx]
					local gix = gx0 + i - 1
					local giz = gz0 + j - 1
					local tx = gix // ORIG_TILE_CELLS
					local tz = giz // ORIG_TILE_CELLS
					local tile = bounds[tx * tiles128 + tz + 1]
					if H > tile.yMin then
						local drop = math.max(0,
							H - heights[hidx + hstride],
							H - heights[hidx - hstride],
							H - heights[hidx + 1],
							H - heights[hidx - 1])
						local shellN = math.clamp(math.ceil(drop / CELL) + 1, 2, SHELL)
						local rawTop = math.ceil(H / CELL) - 1
						local topK = math.min(rawTop, tile.gmax - 1)
						local bottomK = math.max(tile.gmin, topK - shellN)
						bottoms[idx] = bottomK
						tops[idx] = topK
					end
				end
			end

			-- Hierarchical range aggregates. The old planner rescanned the same columns at
			-- every recursion level (~8.3M cell visits for a typical foundation). The split
			-- lattice is small and regular, so scan each terminal block once and combine
			-- child aggregates upward. Values are exactly the same minima/maxima/counts the
			-- scanner returned; only redundant recomputation is removed.
			local xTree = intervalTree(w)
			local zTree = intervalTree(d)
			local zNodeCount = #zTree.starts
			local aggCount = table.create(#xTree.starts * zNodeCount, -1)
			local aggMin = table.create(#xTree.starts * zNodeCount, 0)
			local aggMax = table.create(#xTree.starts * zNodeCount, 0)
			local computeAgg
			computeAgg = function(xid: number, zid: number): (number, number, number)
				local ai = (xid - 1) * zNodeCount + zid
				local cachedCount = aggCount[ai]
				if cachedCount >= 0 then
					return aggMin[ai], aggMax[ai], cachedCount
				end
				local minK, maxK, count
				if xTree.lefts[xid] == 0 and zTree.lefts[zid] == 0 then
					minK = math.huge
					maxK = -math.huge
					count = 0
					local iend = xTree.starts[xid] + xTree.lens[xid] - 1
					local jend = zTree.starts[zid] + zTree.lens[zid] - 1
					for j = zTree.starts[zid], jend do
						local row = (j - 1) * w
						for i = xTree.starts[xid], iend do
							local b = bottoms[row + i]
							if b ~= false then
								local t = tops[row + i]
								minK = math.min(minK, b)
								maxK = math.max(maxK, t)
								count += 1
							end
						end
					end
				elseif xTree.lefts[xid] ~= 0 then
					local amin, amax, acount = computeAgg(xTree.lefts[xid], zid)
					local bmin, bmax, bcount = computeAgg(xTree.rights[xid], zid)
					minK = math.min(amin, bmin)
					maxK = math.max(amax, bmax)
					count = acount + bcount
				else
					local amin, amax, acount = computeAgg(xid, zTree.lefts[zid])
					local bmin, bmax, bcount = computeAgg(xid, zTree.rights[zid])
					minK = math.min(amin, bmin)
					maxK = math.max(amax, bmax)
					count = acount + bcount
				end
				aggMin[ai] = minK
				aggMax[ai] = maxK
				aggCount[ai] = count
				return minK, maxK, count
			end
			local function scanRange(i0: number, j0: number, lw: number, ld: number): (number, number, number)
				return computeAgg(xTree.lookup[i0 * 512 + lw], zTree.lookup[j0 * 512 + ld])
			end

			local function nodeVolume(lw: number, ld: number, minK: number, maxK: number, count: number): number
				if count == 0 then return 0 end
				return lw * ld * (maxK - minK + 1)
			end

			local function emitLeaf(i0: number, j0: number, lw: number, ld: number, minK: number, maxK: number)
				local gix0 = gx0 + i0 - 1
				local giz0 = gz0 + j0 - 1
				local xMin = -WORLD_HALF + gix0 * CELL
				local zMin = -WORLD_HALF + giz0 * CELL
				local yMin = minK * CELL
				local region = Region3.new(
					Vector3.new(xMin, yMin, zMin),
					Vector3.new(xMin + lw * CELL, (maxK + 1) * CELL, zMin + ld * CELL)
				):ExpandToGrid(CELL)
				local rw = math.floor(region.Size.X / CELL + 0.5)
				local rh = math.floor(region.Size.Y / CELL + 0.5)
				local rd = math.floor(region.Size.Z / CELL + 0.5)
				local origin = region.CFrame.Position - region.Size * 0.5
				local originYCell = math.floor(origin.Y / CELL + 0.5)
				local airRow, zeroRow = sharedRows(rd)

				local mats = table.create(rw)
				local occ = table.create(rw)
				for cx = 1, rw do
					mats[cx] = table.create(rh, airRow)
					occ[cx] = table.create(rh, zeroRow)
				end

				for j = j0, j0 + ld - 1 do
					local zIndex = j - j0 + 1
					for i = i0, i0 + lw - 1 do
						local idx = (j - 1) * w + i
						local bottomK = bottoms[idx]
						if bottomK ~= false then
							local topK = tops[idx]
							local gix = gx0 + i - 1
							local giz = gz0 + j - 1
							local tx = gix // ORIG_TILE_CELLS
							local tz = giz // ORIG_TILE_CELLS
							local tile = bounds[tx * tiles128 + tz + 1]
							local hidx = i * hstride + j + 1
							local H = heights[hidx]

							-- The original writer used prevH/prevRow and therefore reset the
							-- gradient component to zero at each 128-stud tile boundary.
							local dx = 0
							if gix % ORIG_TILE_CELLS ~= 0 then
								dx = (H - heights[hidx - hstride]) / CELL
							end
							local dz = 0
							if giz % ORIG_TILE_CELLS ~= 0 then
								dz = (H - heights[hidx - 1]) / CELL
							end
							local slope = math.sqrt(dx * dx + dz * dz)
							local wx = FIRST_CENTER + gix * CELL
							local wz = FIRST_CENTER + giz * CELL
							local tnoise = mathNoise(wx / 240 + 3.1, wz / 240 - 7.7, 542)
							local mnoise = mathNoise(wx / 61 + 9.2, wz / 61 - 4.7, 1337)
							slope = slope + tnoise * 0.10 + mnoise * 0.07
							local hEff = H + tnoise * 90 + mnoise * 22
							local rel = H - tile.yMin

							local xIndex = i - i0 + 1
							local matCol = mats[xIndex]
							local occCol = occ[xIndex]

							-- Write the top cell separately. Every cell below it is guaranteed
							-- solid by the shell interval construction, so the millions of
							-- interior voxels no longer re-evaluate the fractional-fill branch.
							-- Fill/depth still use the original tile-relative arithmetic, keeping
							-- occupancy fractions and material threshold decisions unchanged.
							local cyOrig = topK - tile.gmin + 1
							local fill = (rel - (cyOrig - 1) * CELL) / CELL
							if fill > 0 then
								local cy = topK - originYCell + 1
								local matRow = matCol[cy]
								local occRow = occCol[cy]
								if matRow == airRow then
									matRow = table.clone(airRow)
									occRow = table.clone(zeroRow)
									matCol[cy] = matRow
									occCol[cy] = occRow
								end
								local m
								if fill >= 1 then
									occRow[zIndex] = 1
									local depth = rel - cyOrig * CELL
									if depth > 14 or slope > 0.58 then
										m = MAT_ROCK
									else
										m = MAT_GROUND
									end
								else
									occRow[zIndex] = fill
									if slope > 0.72 then
										m = MAT_ROCK
									elseif hEff > 620 then
										m = if slope > 0.3 then MAT_ROCK else MAT_SNOW
									elseif slope > 0.42 then
										m = if mnoise > 0.05 then MAT_ROCK else MAT_GROUND
									else
										m = if mnoise > -0.18 then MAT_GRASS else MAT_GROUND
									end
								end
								matRow[zIndex] = m

								local solidRock = slope > 0.58
								for k = topK - 1, bottomK, -1 do
									cyOrig -= 1
									local solidCy = k - originYCell + 1
									local solidMatRow = matCol[solidCy]
									local solidOccRow = occCol[solidCy]
									if solidMatRow == airRow then
										solidMatRow = table.clone(airRow)
										solidOccRow = table.clone(zeroRow)
										matCol[solidCy] = solidMatRow
										occCol[solidCy] = solidOccRow
									end
									solidOccRow[zIndex] = 1
									local depth = rel - cyOrig * CELL
									solidMatRow[zIndex] = if depth > 14 or solidRock then MAT_ROCK else MAT_GROUND
								end
							end
						end
					end
				end

				Terrain:WriteVoxels(region, CELL, mats, occ)
				writeCalls += 1
				inputVoxels += rw * rh * rd
			end

			local function emitRegion(i0: number, j0: number, lw: number, ld: number, minK: number, maxK: number, count: number)
				if count == 0 then
					skippedLeaves += 1
					return
				end
				local volume = nodeVolume(lw, ld, minK, maxK, count)
				local bestMode = 0 -- 0 none, 1 split x, 2 split z
				local bestSplit = 0
				local bestGain = 0
				local b1min, b1max, b1count = 0, 0, 0
				local b2min, b2max, b2count = 0, 0, 0

				if lw > MIN_LEAF_CELLS then
					local a = lw // 2
					local lmin, lmax, lcount = scanRange(i0, j0, a, ld)
					local rmin, rmax, rcount = scanRange(i0 + a, j0, lw - a, ld)
					local lv = nodeVolume(a, ld, lmin, lmax, lcount)
					local rv = nodeVolume(lw - a, ld, rmin, rmax, rcount)
					local nonEmpty = (if lcount > 0 then 1 else 0) + (if rcount > 0 then 1 else 0)
					local gain = volume - lv - rv - CALL_COST_VOXELS * (nonEmpty - 1)
					if gain > bestGain then
						bestGain = gain
						bestMode = 1
						bestSplit = a
						b1min, b1max, b1count = lmin, lmax, lcount
						b2min, b2max, b2count = rmin, rmax, rcount
					end
				end
				if ld > MIN_LEAF_CELLS then
					local a = ld // 2
					local lmin, lmax, lcount = scanRange(i0, j0, lw, a)
					local rmin, rmax, rcount = scanRange(i0, j0 + a, lw, ld - a)
					local lv = nodeVolume(lw, a, lmin, lmax, lcount)
					local rv = nodeVolume(lw, ld - a, rmin, rmax, rcount)
					local nonEmpty = (if lcount > 0 then 1 else 0) + (if rcount > 0 then 1 else 0)
					local gain = volume - lv - rv - CALL_COST_VOXELS * (nonEmpty - 1)
					if gain > bestGain then
						bestGain = gain
						bestMode = 2
						bestSplit = a
						b1min, b1max, b1count = lmin, lmax, lcount
						b2min, b2max, b2count = rmin, rmax, rcount
					end
				end

				if bestMode == 1 then
					local a = bestSplit
					emitRegion(i0, j0, a, ld, b1min, b1max, b1count)
					emitRegion(i0 + a, j0, lw - a, ld, b2min, b2max, b2count)
				elseif bestMode == 2 then
					local a = bestSplit
					emitRegion(i0, j0, lw, a, b1min, b1max, b1count)
					emitRegion(i0, j0 + a, lw, ld - a, b2min, b2max, b2count)
				else
					emitLeaf(i0, j0, lw, ld, minK, maxK)
				end
			end

			local minK, maxK, count = scanRange(1, 1, w, d)
			emitRegion(1, 1, w, d, minK, maxK, count)
		end
		-- Boot-time generation may use longer bursts than runtime gameplay code, but a few
		-- cooperative yields keep the scheduler responsive while terrain is reconstructing.
		if sx % 6 == 5 then task.wait() end
	end
	print(string.format(
		"GeoTerrainWriter: %d adaptive WriteVoxels, %.1fM input voxels, %d height samples, %d empty leaves, %.2fs",
		writeCalls, inputVoxels / 1000000, heightSamples, skippedLeaves, os.clock() - t0))
end

export type GenResult = {
	spec: GeoSpec,
	decodeTime: number,
	writeTime: number,
	totalTime: number,
	memoryBeforeMb: number,
	memoryAfterMb: number,
	probes: { number },
}

function GeographyService.generate(spec: GeoSpec, opts: any?): GenResult
	local Stats = game:GetService("Stats")
	local memBefore = Stats:GetTotalMemoryUsageMb()
	local t0 = os.clock()

	local f = FOUNDATIONS[spec.foundation]
	local hf, decodeTime = loadFoundation(f)
	local sampler = orientedSampler(hf, spec)
	local latticeSampler = orientedLatticeSampler(hf, spec)

	-- clear any prior terrain, then reconstruct
	Terrain:Clear()
	task.wait() -- let the clear flush before writes begin
	local writeStart = os.clock()
	writeFoundationTerrain(sampler, latticeSampler)
	local writeTime = os.clock() - writeStart
	local memAfter = Stats:GetTotalMemoryUsageMb()

	-- structural probes for validation: record heights on a fixed lattice
	local probes = {}
	for px = -2, 2 do
		for pz = -2, 2 do
			local x, z = px * 800, pz * 800
			local hit = workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -2000, 0))
			table.insert(probes, hit and math.floor(hit.Position.Y + 0.5) or -1)
		end
	end

	local result: GenResult = {
		spec = spec,
		decodeTime = decodeTime,
		writeTime = writeTime,
		totalTime = os.clock() - t0,
		memoryBeforeMb = memBefore,
		memoryAfterMb = memAfter,
		probes = probes,
	}
	print(string.format(
		"GeographyService: %s rot%d mirror=%s scale=%.3f | decode=%.1fs write=%.1fs total=%.1fs mem=%.0f->%.0fMB",
		f.id, spec.rotation, tostring(spec.mirror), spec.heightScale,
		decodeTime, writeTime, result.totalTime, memBefore, memAfter))
	workspace:SetAttribute("GF_GeoFoundation", f.id)
	workspace:SetAttribute("GF_GeoSeed", spec.seed)

	-- terrain analysis for operation placement (directive section 23): the operation
	-- generator consumes candidate sites, valley floor, high ground positions. At 40 studs
	-- this is only ~15k direct heightfield samples, so resolution is not a meaningful boot
	-- cost; keep the placement semantics unchanged.
	GeographyService.lastSampler = sampler
	GeographyService.lastSpec = spec
	task.spawn(function()
		local ok, err = pcall(function()
			local TerrainAnalysis = require(script.Parent.TerrainAnalysis)
			GeographyService.analysis = TerrainAnalysis.analyze(sampler, 2450, 40)
			if GeographyService.analysis then
				workspace:SetAttribute("GF_GeoAnalyzed", true)
				print(string.format("TerrainAnalysis: %d feasible sites (%d valley, %d high)",
					#GeographyService.analysis.sites, #GeographyService.analysis.valleyFloor, #GeographyService.analysis.highGround))
			end
		end)
		if not ok then warn("TerrainAnalysis failed:", err) end
	end)
	return result
end

GeographyService.lastSampler = nil
GeographyService.lastSpec = nil
GeographyService.analysis = nil

return GeographyService
