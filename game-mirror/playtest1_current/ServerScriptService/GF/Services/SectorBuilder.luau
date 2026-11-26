--!strict
-- SectorBuilder: deterministic angular highland terrain for Veyra-7 sectors.
-- Layered noise -> quantised terraces, carved traversal spine, tile-batched voxel writes.

local Terrain = workspace.Terrain

local SectorBuilder = {}

local RES = 4            -- voxels per stud cell (Roblox voxel grid)
local CELL = 4           -- studs per cell

local function noise2(x: number, z: number, scale: number, seed: number): number
	return math.noise(x / scale, z / scale, seed)
end

-- Height sampler shared by terrain writers and prop placement.
function SectorBuilder.sampler(opts)
	local seed = opts.seed or 1
	local spine = opts.spine or nil :: any
	local ridge = opts.ridge or 1.0
	local base = opts.baseHeight or 22

	return function(x: number, z: number): number
		-- Octave stack: broad landforms, mid ridges, fine rubble.
		local broad = math.noise(x / 170, z / 170, seed) * 30
		local mid = math.noise(x / 74 + 3.1, z / 74 - 1.7, seed + 7) * 15
		local fine = math.noise(x / 28 - 5.3, z / 28 + 2.9, seed + 13) * 5

		-- Ridged crests: sharp faceted ridges instead of rolling hills.
		local crest = 1 - math.abs(math.noise(x / 120 + 11, z / 120 + 7, seed + 21))
		local crestTerm = (crest ^ 4) * 26

		local raw = base + (broad + mid + fine) * ridge + crestTerm * ridge

		if spine then
			local d = spine(x, z)
			local corridor = math.clamp(1 - d / 55, 0, 1)
			-- Soften along the traversal spine but keep genuine relief nearby.
			raw = raw * (1 - corridor * 0.62) + (base + 1) * (corridor * 0.62)
		end

		-- Quantise into terraces for a low-poly, strata-cut silhouette.
		local step = 4.5
		local q = math.floor(raw / step) * step
		local frac = (raw - q) / step
		return q + frac * 0.35
	end
end

function SectorBuilder.clear(center: Vector3, size: number)
	local r = Region3.new(center - Vector3.new(size, 120, size), center + Vector3.new(size, 200, size))
	Terrain:FillRegion(r, 4, Enum.Material.Air)
end

function SectorBuilder.write(opts)
	local center = opts.center :: Vector3
	local half = (opts.size :: number) * 0.5
	local sample = (opts.samplerOverride :: any) or SectorBuilder.sampler(opts)
	local yMin = (opts.yMin or -32) :: number
	local yMax = (opts.yMax or 200) :: number

	local tileStuds = 128
	local tiles = math.ceil((half * 2) / tileStuds)

	for tx = 0, tiles - 1 do
		for tz = 0, tiles - 1 do
			local x0 = center.X - half + tx * tileStuds
			local z0 = center.Z - half + tz * tileStuds
			local x1 = math.min(x0 + tileStuds, center.X + half)
			local z1 = math.min(z0 + tileStuds, center.Z + half)
			if x1 - x0 >= CELL and z1 - z0 >= CELL then
				local region = Region3.new(Vector3.new(x0, yMin, z0), Vector3.new(x1, yMax, z1)):ExpandToGrid(CELL)
				local w = math.floor(region.Size.X / CELL + 0.5)
				local h = math.floor(region.Size.Y / CELL + 0.5)
				local d = math.floor(region.Size.Z / CELL + 0.5)
				local origin = region.CFrame.Position - region.Size * 0.5

				local mats = table.create(w)
				local occ = table.create(w)
				for cx = 1, w do
					local col = table.create(h)
					local occCol = table.create(h)
					for cy = 1, h do
						col[cy] = table.create(d, Enum.Material.Air)
						occCol[cy] = table.create(d, 0)
					end
					mats[cx] = col
					occ[cx] = occCol
				end

			-- Fractional-occupancy write per spec section 29: the surface voxel carries the
			-- sub-cell fill fraction, so smooth-terrain interpolation renders continuous slopes
			-- instead of 4-stud stairs. Binary writes quantized every slope into terraces
			-- (the "ridges stacked on each other" artifact) and erased all sub-4-stud detail.
			-- Materials are slope-aware via backward differences over cached row heights (zero
			-- extra sampler evaluations); a low-frequency material field motleys surface cover.
			local prevRow: { number }? = nil
			for cz = 1, d do
				local wz = origin.Z + (cz - 0.5) * CELL
				local row = table.create(w)
				local prevH: number? = nil
				for cx = 1, w do
					local wx = origin.X + (cx - 0.5) * CELL
					local H = sample(wx, wz)
					row[cx] = H
					local rel = H - origin.Y
					if rel > 0 then
						local dx = prevH and ((H - prevH) / CELL) or 0
						local dz = (prevRow and (prevRow :: any)[cx]) and ((H - (prevRow :: any)[cx]) / CELL) or 0
						local slope = math.sqrt(dx * dx + dz * dz)
						local mnoise = math.noise(wx / 61 + 9.2, wz / 61 - 4.7, 1337)
						local col = mats[cx]
						local occCol = occ[cx]
						local topCell = math.min(math.ceil(rel / CELL), h)
						for cy = 1, topCell do
							local voxBottom = (cy - 1) * CELL
							local fill = (rel - voxBottom) / CELL
							local m
							if fill >= 1 then
								occCol[cy][cz] = 1
								local depth = rel - cy * CELL
								if depth > 14 then
									m = Enum.Material.Slate
								elseif depth > 2 or slope > 0.55 then
									m = Enum.Material.Rock
								else
									m = Enum.Material.Ground
								end
							elseif fill > 0 then
								occCol[cy][cz] = fill
								if slope > 0.72 then
									m = Enum.Material.Rock
								elseif slope > 0.42 then
									m = (mnoise > 0.05) and Enum.Material.Rock or Enum.Material.Ground
								else
									m = (mnoise > -0.18) and Enum.Material.Grass or Enum.Material.Ground
								end
							else
								break
							end
							col[cy][cz] = m
						end
					end
					prevH = H
				end
				prevRow = row
			end

				Terrain:WriteVoxels(region, CELL, mats, occ)
			end
			task.wait()
		end
	end
	return sample
end

return SectorBuilder

