--!strict
-- BakeTerrain: offline terrain reconstruction from a heightfield sampler (edit-mode tooling).
-- Optimizations vs the legacy runtime writer:
--  * shell fill: only SHELL voxels below the surface are written solid - deep interior
--    stays air. Nobody sees inside the mass; collision/rendering only care about the
--    surface. Cuts voxel writes by an order of magnitude on tall relief.
--  * per-tile adaptive vertical bounds: each 128-stud tile computes its own min/max
--    terrain height from coarse sampler probes, so flat valley tiles don't pay for
--    mountain-height regions.
--  * fractional-occupancy surface voxels (smooth slopes, spec section 29).
-- Shell thickness of 8 voxels (32 studs) covers p99 adjacent-column cliff discontinuities.

local Terrain = workspace.Terrain
local BakeTerrain = {}
local CELL = 4
local SHELL = 8

function BakeTerrain.write(opts)
	local center: Vector3 = opts.center
	local half = opts.size * 0.5
	local sample = opts.sampler
	local tileStuds = 128
	local tiles = math.ceil((half * 2) / tileStuds)
	local t0 = os.clock()
	local written, skipped = 0, 0
	-- optional tile-range slicing: bake in resumable slices across multiple invocations
	local tx0i, tx1i = opts.tx0 or 0, opts.tx1 or (tiles - 1)
	local tz0i, tz1i = opts.tz0 or 0, opts.tz1 or (tiles - 1)

	for tx = tx0i, tx1i do
		for tz = tz0i, tz1i do
			local x0 = center.X - half + tx * tileStuds
			local z0 = center.Z - half + tz * tileStuds
			local x1 = math.min(x0 + tileStuds, center.X + half)
			local z1 = math.min(z0 + tileStuds, center.Z + half)
			-- probe tile height range (coarse 5x5)
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
			if x1 - x0 >= CELL and z1 - z0 >= CELL and yMax > yMin then
				local region = Region3.new(Vector3.new(x0, yMin, z0), Vector3.new(x1, yMax, z1)):ExpandToGrid(CELL)
				local w = math.floor(region.Size.X / CELL + 0.5)
				local hh = math.floor(region.Size.Y / CELL + 0.5)
				local d = math.floor(region.Size.Z / CELL + 0.5)
				local origin = region.CFrame.Position - region.Size * 0.5

				local mats = table.create(w)
				local occ = table.create(w)
				for cx = 1, w do
					local col = table.create(hh)
					local occCol = table.create(hh)
					for cy = 1, hh do
						col[cy] = table.create(d, Enum.Material.Air)
						occCol[cy] = table.create(d, 0)
					end
					mats[cx] = col
					occ[cx] = occCol
				end

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
							local topCell = math.min(math.ceil(rel / CELL), hh)
							local bottomCell = math.max(1, topCell - SHELL)
							for cy = topCell, bottomCell, -1 do
								local voxBottom = (cy - 1) * CELL
								local fill = (rel - voxBottom) / CELL
								local m
								if fill >= 1 then
									occCol[cy][cz] = 1
									local depth = rel - cy * CELL
									if depth > 14 or slope > 0.55 then
										m = Enum.Material.Rock
									else
										m = Enum.Material.Ground
									end
								elseif fill > 0 then
									occCol[cy][cz] = fill
									if slope > 0.72 then
										m = Enum.Material.Rock
									elseif H > 620 then
										-- high country: exposed pale rock/snow above the treeline zone
										m = slope > 0.3 and Enum.Material.Rock or Enum.Material.Snow
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
				written += 1
			else
				skipped += 1
			end
			if (tx * tiles + tz) % 25 == 0 then
				task.wait()
			end
		end
	end
	print(string.format("BakeTerrain: %d tiles written, %d skipped, %.1fs (tx %d..%d tz %d..%d)", written, skipped, os.clock() - t0, tx0i, tx1i, tz0i, tz1i))
end

return BakeTerrain
