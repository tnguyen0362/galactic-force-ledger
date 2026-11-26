--!strict
-- Topology: mission graph construction and least-cost routing over the region grid.
-- Routes are DISCOVERED over the generated geography — never manufactured by flattening.
-- If two meaningfully-separated viable routes exist naturally, the geography ships as-is.

local RegionAnalysis = require(script.Parent.RegionAnalysis)

local Topology = {}

-- Binary min-heap keyed by f-score. A* over a ~200x200 grid without a heap is too slow.
local function newHeap()
	return { items = {}, keys = {}, n = 0 }
end
local function heapPush(h, key, item)
	h.n += 1
	local i = h.n
	h.items[i] = item
	h.keys[i] = key
	while i > 1 do
		local p = math.floor(i / 2)
		if h.keys[p] <= h.keys[i] then break end
		h.keys[p], h.keys[i] = h.keys[i], h.keys[p]
		h.items[p], h.items[i] = h.items[i], h.items[p]
		i = p
	end
end
local function heapPop(h)
	if h.n == 0 then return nil end
	local top = h.items[1]
	h.items[1] = h.items[h.n]
	h.keys[1] = h.keys[h.n]
	h.items[h.n] = nil
	h.keys[h.n] = nil
	h.n -= 1
	local i = 1
	while true do
		local l, r = i * 2, i * 2 + 1
		local smallest = i
		if l <= h.n and h.keys[l] < h.keys[smallest] then smallest = l end
		if r <= h.n and h.keys[r] < h.keys[smallest] then smallest = r end
		if smallest == i then break end
		h.keys[i], h.keys[smallest] = h.keys[smallest], h.keys[i]
		h.items[i], h.items[smallest] = h.items[smallest], h.items[i]
		i = smallest
	end
	return top
end

local function cellIndex(grid, i, j)
	return (i - 1) * grid.nz + j
end
local function indexCell(grid, idx)
	local i = math.floor((idx - 1) / grid.nz) + 1
	local j = (idx - 1) % grid.nz + 1
	return i, j
end

-- A* least-cost path between world points over the cost grid.
-- extraCost: optional (i,j) -> number additive cost field for redundancy forcing.
-- Returns path as flat worldwaypoints {x1,z1,...}, total cost, or nil if unreachable.
function Topology.route(grid, ax, az, bx, bz, maxSlope, extraCost)
	local si, sj = RegionAnalysis.cellAt(grid, ax, az)
	local ti, tj = RegionAnalysis.cellAt(grid, bx, bz)
	local start = cellIndex(grid, si, sj)
	local goal = cellIndex(grid, ti, tj)
	if start == goal then
		return { ax, az, bx, bz }, 0
	end
	local open = newHeap()
	local gScore = {}
	local cameFrom = {}
	local closed = {}
	gScore[start] = 0
	local function heuristic(idx)
		local i, j = indexCell(grid, idx)
		-- octile distance in cell units, weighted by minimum possible cost per cell
		local di, dj = math.abs(i - ti), math.abs(j - tj)
		return (math.max(di, dj) + 0.4142 * math.min(di, dj)) * grid.step
	end
	heapPush(open, heuristic(start), start)
	local iterations = 0
	local maxIterations = grid.nx * grid.nz * 2
	while open.n > 0 do
		iterations += 1
		if iterations > maxIterations then
			return nil, math.huge
		end
		local current = heapPop(open)
		if current == goal then
			-- reconstruct
			local rev = {}
			local node = current
			while node do
				local i, j = indexCell(grid, node)
				table.insert(rev, 1, grid.originZ + (j - 0.5) * grid.step)
				table.insert(rev, 1, grid.originX + (i - 0.5) * grid.step)
				node = cameFrom[node]
			end
			return rev, gScore[current]
		end
		if closed[current] then
			continue
		end
		closed[current] = true
		local ci, cj = indexCell(grid, current)
		for di = -1, 1 do
			for dj = -1, 1 do
				if di ~= 0 or dj ~= 0 then
					local ni, nj = ci + di, cj + dj
					if ni >= 1 and ni <= grid.nx and nj >= 1 and nj <= grid.nz then
						local neighbor = cellIndex(grid, ni, nj)
						if not closed[neighbor] then
							local wx = grid.originX + (ni - 0.5) * grid.step
							local wz = grid.originZ + (nj - 0.5) * grid.step
							local stepLen = grid.step * ((di ~= 0 and dj ~= 0) and 1.4142 or 1)
							local cost = RegionAnalysis.costAt(grid, wx, wz, maxSlope)
							if extraCost then
								cost += extraCost(ni, nj)
							end
							-- penalize climbing/descending steep transitions between cells specifically:
							-- grid slope is per-cell; large inter-cell jumps are cliff steps
							local dh = math.abs(grid.heights[ni][nj] - grid.heights[ci][cj])
							if dh / stepLen > math.tan(math.rad(maxSlope or 30)) then
								cost += 40
							end
							local tentative = gScore[current] + stepLen * cost
							if gScore[neighbor] == nil or tentative < gScore[neighbor] then
								gScore[neighbor] = tentative
								cameFrom[neighbor] = current
								heapPush(open, tentative + heuristic(neighbor), neighbor)
							end
						end
					end
				end
			end
		end
	end
	return nil, math.huge
end

-- Path length in studs from flat waypoint array.
function Topology.pathLength(points)
	local len = 0
	for i = 1, #points - 3, 2 do
		len += math.sqrt((points[i + 2] - points[i]) ^ 2 + (points[i + 3] - points[i + 1]) ^ 2)
	end
	return len
end

-- Minimum separation between two paths: for each waypoint of path A, min distance to path B,
-- then return the MEAN of those minimums (robust to endpoint convergence — endpoints ARE shared
-- near LZ/objective by design, so mean-separation is the honest redundancy measure).
function Topology.pathSeparation(a, b)
	if not a or not b or #a < 4 or #b < 4 then
		return 0
	end
	local sum = 0
	local count = 0
	-- sample interior of A (skip first/last 15% where convergence is expected)
	local n = math.floor(#a / 2)
	local i0 = math.max(2, math.floor(n * 0.15))
	local i1 = math.min(n - 1, math.ceil(n * 0.85))
	for idx = i0, i1 do
		local ax, az = a[idx * 2 - 1], a[idx * 2]
		local best = math.huge
		for k = 1, #b - 1, 2 do
			local d = math.sqrt((b[k] - ax) ^ 2 + (b[k + 1] - az) ^ 2)
			if d < best then best = d end
		end
		sum += best
		count += 1
	end
	return count > 0 and sum / count or 0
end

-- Redundant routing: find path 1, then re-route with a cost penalty near path 1 and check whether
-- a second path exists at acceptable cost. Returns both paths, their lengths, and separation.
function Topology.redundantRoutes(grid, ax, az, bx, bz, maxSlope, separationRadius)
	local p1, c1 = Topology.route(grid, ax, az, bx, bz, maxSlope)
	if not p1 then
		return nil
	end
	local radius = separationRadius or 55
	local radiusCells = math.ceil(radius / grid.step)
	-- build penalty field lookup from path1 cells
	local penalized = {}
	for k = 1, #p1 - 1, 2 do
		local ci, cj = RegionAnalysis.cellAt(grid, p1[k], p1[k + 1])
		for di = -radiusCells, radiusCells do
			for dj = -radiusCells, radiusCells do
				if di * di + dj * dj <= radiusCells * radiusCells then
					penalized[(ci + di) * 100000 + (cj + dj)] = true
				end
			end
		end
	end
	local extra = function(i, j)
		return penalized[i * 100000 + j] and 25 or 0
	end
	local p2, c2 = Topology.route(grid, ax, az, bx, bz, maxSlope, extra)
	local sep = p2 and Topology.pathSeparation(p1, p2) or 0
	return {
		primary = { points = p1, cost = c1, length = Topology.pathLength(p1) },
		alternate = p2 and { points = p2, cost = c2, length = Topology.pathLength(p2) } or nil,
		separation = sep,
	}
end

-- Node placement by rejection sampling inside validity masks. constraints per node:
-- minSpacing pairwise, validSlope max, optional region predicate. Deterministic in stream rng.
function Topology.placeNodes(grid, specs, rng, maxSlope)
	local placed = {}
	local nodes = {}
	for _, spec in specs do
		local found = nil
		for _ = 1, 120 do
			local x = grid.originX + rng() * (grid.nx - 1) * grid.step
			local z = grid.originZ + rng() * (grid.nz - 1) * grid.step
			-- margin: keep nodes inside the central 80% so routes don't hug the map edge
			local mx, mz = math.abs(x), math.abs(z)
			local halfExtent = grid.nx * grid.step / 2
			if mx < halfExtent * 0.86 and mz < halfExtent * 0.86 then
				local slopeOk = RegionAnalysis.slope(grid, x, z) <= (spec.maxSlope or maxSlope or 22)
				local regionOk = not spec.region or spec.region(x, z)
				if slopeOk and regionOk then
					local spaced = true
					for _, other in placed do
						local d = math.sqrt((other.x - x) ^ 2 + (other.z - z) ^ 2)
						local need = math.max(spec.minSpacing or 0, other.spec.minSpacing or 0)
						if d < need then
							spaced = false
							break
						end
					end
					if spaced then
						found = { x = x, z = z, spec = spec }
						break
					end
				end
			end
		end
		if not found then
			return nil -- caller treats as generation failure -> reject seed
		end
		nodes[spec.id] = { x = found.x, z = found.z, kind = spec.id }
		table.insert(placed, found)
	end
	return nodes
end

return Topology
