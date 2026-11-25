--!strict
-- S06-003 shared spatial grid: 64-stud cells partition the playspace so perception, spawn validation
-- and relay systems all query the same broad-phase instead of scanning the workspace independently.
local SpatialGrid = {}

local CELL = 64
local grid: { [string]: { any } } = {}

local function key(x: number, z: number): string
	return math.floor(x / CELL) .. ":" .. math.floor(z / CELL)
end

function SpatialGrid.clear()
	grid = {}
end

function SpatialGrid.insert(obj: any, position: Vector3)
	local k = key(position.X, position.Z)
	grid[k] = grid[k] or {}
	table.insert(grid[k], obj)
end

function SpatialGrid.remove(obj: any, position: Vector3)
	local k = key(position.X, position.Z)
	local cell = grid[k]
	if cell then
		for i, v in ipairs(cell) do
			if v == obj then
				table.remove(cell, i)
				break
			end
		end
	end
end

-- query all objects within radius of position: touches only the overlapping cells
function SpatialGrid.query(position: Vector3, radius: number): { any }
	local out = {}
	local minX = math.floor((position.X - radius) / CELL)
	local maxX = math.floor((position.X + radius) / CELL)
	local minZ = math.floor((position.Z - radius) / CELL)
	local maxZ = math.floor((position.Z + radius) / CELL)
	for cx = minX, maxX do
		for cz = minZ, maxZ do
			local cell = grid[cx .. ":" .. cz]
			if cell then
				for _, obj in ipairs(cell) do
					table.insert(out, obj)
				end
			end
		end
	end
	return out
end

function SpatialGrid.cellSize(): number
	return CELL
end

return SpatialGrid
