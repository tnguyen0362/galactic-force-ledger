--!strict
-- RegionAnalysis: samples the analytic heightfield into grids used by routing, placement and
-- validation. One grid build is shared across all consumers per generation — no repeated
-- sampling. Pure math over the sampler; no Instances.
--
-- Grid convention: cell (i,j) center is world (originX + (i-0.5)*step, originZ + (j-0.5)*step).

local NoiseKit = require(script.Parent.NoiseKit)

local RegionAnalysis = {}

export type Grid = {
	nx: number,
	nz: number,
	step: number,
	originX: number,
	originZ: number,
	heights: { { number } },
	slopes: { { number } },
}

function RegionAnalysis.build(sampler: (number, number) -> number, extent: number, step: number): Grid
	local half = extent / 2
	local n = math.floor(extent / step)
	local heights = table.create(n)
	local slopes = table.create(n)
	for i = 1, n do
		heights[i] = table.create(n)
		slopes[i] = table.create(n)
		local x = -half + (i - 0.5) * step
		for j = 1, n do
			local z = -half + (j - 0.5) * step
			heights[i][j] = sampler(x, z)
		end
	end
	-- slope from grid central differences (cheaper than per-cell sampler re-evaluation and
	-- consistent with what the voxel terrain will actually look like after quantization)
	for i = 1, n do
		for j = 1, n do
			local xm = heights[math.max(1, i - 1)][j]
			local xp = heights[math.min(n, i + 1)][j]
			local zm = heights[i][math.max(1, j - 1)]
			local zp = heights[i][math.min(n, j + 1)]
			local gx = (xp - xm) / (2 * step)
			local gz = (zp - zm) / (2 * step)
			slopes[i][j] = math.deg(math.atan(math.sqrt(gx * gx + gz * gz)))
		end
	end
	return {
		nx = n, nz = n, step = step,
		originX = -half, originZ = -half,
		heights = heights, slopes = slopes,
	}
end

function RegionAnalysis.cellAt(grid: Grid, x: number, z: number): (number, number)
	local i = math.floor((x - grid.originX) / grid.step) + 1
	local j = math.floor((z - grid.originZ) / grid.step) + 1
	return math.clamp(i, 1, grid.nx), math.clamp(j, 1, grid.nz)
end

function RegionAnalysis.height(grid: Grid, x: number, z: number): number
	local i, j = RegionAnalysis.cellAt(grid, x, z)
	return grid.heights[i][j]
end

function RegionAnalysis.slope(grid: Grid, x: number, z: number): number
	local i, j = RegionAnalysis.cellAt(grid, x, z)
	return grid.slopes[i][j]
end

-- Movement cost for routing. Base 1; slope adds quadratically past the comfort band; cells beyond
-- the hard navigability limit (default 30 deg per brief) are near-impassable but not infinite —
-- infinite costs produce pathological A* behavior when a region is fully enclosed.
function RegionAnalysis.costAt(grid: Grid, x: number, z: number, maxSlope: number?): number
	local s = RegionAnalysis.slope(grid, x, z)
	local limit = maxSlope or 30
	if s >= limit then
		return 50 + (s - limit) * 4
	end
	local comfort = 14
	if s <= comfort then
		return 1 + (s / comfort) * 0.5
	end
	local t = (s - comfort) / (limit - comfort)
	return 1.5 + t * t * 8
end

-- Local maxima above minProminence: candidate high-ground tactical landmarks.
function RegionAnalysis.highGround(grid: Grid, minHeight: number, radiusCells: number?): { { x: number, z: number, h: number } }
	local r = radiusCells or 3
	local out = {}
	for i = 1 + r, grid.nx - r do
		for j = 1 + r, grid.nz - r do
			local h = grid.heights[i][j]
			if h >= minHeight then
				local isMax = true
				for di = -r, r do
					for dj = -r, r do
						if (di ~= 0 or dj ~= 0) and grid.heights[i + di][j + dj] > h then
							isMax = false
							break
						end
					end
					if not isMax then break end
				end
				if isMax then
					table.insert(out, {
						x = grid.originX + (i - 0.5) * grid.step,
						z = grid.originZ + (j - 0.5) * grid.step,
						h = h,
					})
				end
			end
		end
	end
	return out
end

-- Heightfield line-of-sight step test: sample the heightfield along the segment at `step`
-- intervals; blocked if terrain rises above the eye-level line anywhere in between.
-- Eye heights default to standing (5 studs) at both ends.
function RegionAnalysis.losClear(grid: Grid, ax: number, az: number, bx: number, bz: number, step: number?, eyeHeight: number?): boolean
	local st = step or 6
	local eye = eyeHeight or 5
	local dx, dz = bx - ax, bz - az
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 1e-3 then
		return true
	end
	local ha = RegionAnalysis.height(grid, ax, az) + eye
	local hb = RegionAnalysis.height(grid, bx, bz) + eye
	local n = math.max(2, math.floor(dist / st))
	for k = 1, n - 1 do
		local t = k / n
		local x = ax + dx * t
		local z = az + dz * t
		local lineH = ha + (hb - ha) * t
		if RegionAnalysis.height(grid, x, z) > lineH then
			return false
		end
	end
	return true
end

-- Exposure at a point: fraction of `rays` radial directions in which LOS extends past `range`
-- unobstructed. High exposure = dangerous open ground; low exposure = covered/concealed.
function RegionAnalysis.exposure(grid: Grid, x: number, z: number, rays: number, range: number): number
	local open = 0
	for k = 0, rays - 1 do
		local a = (k / rays) * math.pi * 2
		local ex = x + math.cos(a) * range
		local ez = z + math.sin(a) * range
		if RegionAnalysis.losClear(grid, x, z, ex, ez, 8) then
			open += 1
		end
	end
	return open / rays
end

return RegionAnalysis
