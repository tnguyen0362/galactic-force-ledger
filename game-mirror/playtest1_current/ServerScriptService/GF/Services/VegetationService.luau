--!strict
-- VegetationService: environment-conditioned vegetation for the baked geographical
-- foundation (spec section 14). Real mountain ecology instead of random spray:
--   * forest REGIONS come from a low-frequency noise field (sigmoid-clustered), not
--     per-tree randomness — forests read as ecosystems with clearings and edges
--   * treeline: canopy species thin out with elevation and vanish above a noise-modulated
--     treeline; high country falls back to stone/shrub alpine texture
--   * slope rejection from live terrain raycast normals — trees don't grow on cliff faces
--   * valley-bottom moisture proxy (low elevation + convergence) raises density
--   * trees are BIG (16-34 studs): they establish the visual scale of the forest
-- Placement budget is frame-sliced at boot; everything static, anchored, non-shadowed.

local VegetationService = {}

local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain

local TRUNK_C = Color3.fromRGB(58, 50, 44)
local CANOPY_DEEP = Color3.fromRGB(38, 74, 58)
local CANOPY_MID = Color3.fromRGB(48, 92, 66)
local SHRUB_C = Color3.fromRGB(56, 78, 58)
local STONE_C = Color3.fromRGB(92, 88, 82)
local ALPINE_C = Color3.fromRGB(112, 108, 96)

local function hash01(x: number, z: number, salt: number): number
	local v = math.sin(x * 12.9898 + z * 78.233 + salt * 37.719) * 43758.5453
	return v - math.floor(v)
end

local function noise2(x: number, z: number, scale: number, seed: number): number
	return math.noise(x / scale, z / scale, seed)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { Terrain }

local function ground(x: number, z: number): (number?, Vector3?)
	local hit = Workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -2200, 0), rayParams)
	if hit then
		return hit.Position.Y, hit.Normal
	end
	return nil, nil
end

local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = collide
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- alien highland conifer: tapered trunk + layered angular canopy slabs, slight lean
local function buildTree(folder: Instance, x: number, z: number, gy: number, s: number, seedsalt: number)
	local yaw = hash01(x, z, seedsalt) * math.pi * 2
	local lean = (hash01(x, z, seedsalt + 3) - 0.5) * 0.12
	local h = 20 * s
	local trunkH = h * 0.5
	mk(folder, "Trunk", Vector3.new(1.1 * s, trunkH, 1.1 * s),
		CFrame.new(x, gy + trunkH * 0.5 - 0.5, z) * CFrame.Angles(lean, yaw, lean * 0.6), TRUNK_C, Enum.Material.Wood, true)
	local slabs = 3 + math.floor(hash01(x, z, seedsalt + 5) * 2)
	for i = 1, slabs do
		local t = i / slabs
		local w = (6.2 - t * 3.6) * s
		local cy = gy + trunkH * 0.55 + h * 0.5 * t
		local c = (i % 2 == 0) and CANOPY_MID or CANOPY_DEEP
		mk(folder, "Canopy" .. i, Vector3.new(w, 1.6 * s, w),
			CFrame.new(x + lean * cy * 0.4, cy, z) * CFrame.Angles(0.02, yaw + i * 0.9, -0.015),
			c, Enum.Material.Grass, false)
	end
end

local function buildShrub(folder: Instance, x: number, z: number, gy: number, s: number)
	local yaw = hash01(x, z, 13) * math.pi * 2
	mk(folder, "Shrub", Vector3.new(2.2 * s, 1.3 * s, 2.0 * s),
		CFrame.new(x, gy + 0.5 * s, z) * CFrame.Angles(0.05, yaw, 0.07), SHRUB_C, Enum.Material.Grass, false)
end

local function buildStone(folder: Instance, x: number, z: number, gy: number, s: number)
	local yaw = hash01(x, z, 17) * math.pi * 2
	mk(folder, "Stone", Vector3.new(1.4 * s, 0.9 * s, 1.1 * s),
		CFrame.new(x, gy + 0.35 * s, z) * CFrame.Angles(0.08, yaw, 0.05), STONE_C, Enum.Material.Slate, false)
end

-- sigmoid for forest-region membership thresholding
local function sigmoid(v: number, k: number): number
	return 1 / (1 + math.exp(-k * v))
end

export type VegOpts = {
	seed: number?,
	center: Vector3?,
	extent: number?,
	treeBudget: number?,
	shrubBudget: number?,
	stoneBudget: number?,
	treeline: number?, -- studs elevation where canopy species vanish
}

function VegetationService.plant(opts: VegOpts?): Folder
	local o = opts or {} :: any
	local seed = o.seed or 4201
	local center = o.center or Vector3.new(0, 0, 0)
	local extent = o.extent or 4900
	local treeBudget = o.treeBudget or 1300
	local shrubBudget = o.shrubBudget or 1400
	local stoneBudget = o.stoneBudget or 700
	local treeline = o.treeline or 430

	local old = Workspace:FindFirstChild("GFVegetation")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "GFVegetation"
	folder.Parent = Workspace

	local half = extent / 2
	local t0 = os.clock()
	local trees, shrubs, stones, probes = 0, 0, 0, 0

	-- STRATIFIED SCAN: 24-stud cells across the map; per-cell species decision.
	-- forest membership: low-frequency noise field sigmoided — regions, not noise spray.
	local cell = 24
	local n = math.floor(extent / cell)
	local budget = treeBudget + shrubBudget + stoneBudget
	local spent = 0
	for cx = 0, n - 1 do
		for cz = 0, n - 1 do
			if spent >= budget then break end
			local bx = center.X - half + (cx + 0.5) * cell
			local bz = center.Z - half + (cz + 0.5) * cell
			-- jitter inside cell
			local x = bx + (hash01(bx, bz, 31) - 0.5) * cell * 0.8
			local z = bz + (hash01(bx, bz, 37) - 0.5) * cell * 0.8
			-- forest region field: two scales so edges feather naturally
			local forestN = noise2(x, z, 420, seed + 11) * 0.72 + noise2(x, z, 150, seed + 23) * 0.28
			local forest = sigmoid(forestN, 6)
			-- cheap pre-filter: only raycast where anything could grow
			local interest = forest + 0.18
			if hash01(x, z, 41) > interest then
				continue
			end
			probes += 1
			local gy, normal = ground(x, z)
			if not gy or not normal then continue end
			local slope = 1 - (normal :: Vector3).Y
			-- elevation suitability: canopy below treeline, thinning approaching it
			local tlNoise = (noise2(x, z, 260, seed + 31)) * 60
			local tl = treeline + tlNoise
			local elev = gy :: number
			local highT = math.clamp(1 - (elev - (tl - 120)) / 120, 0, 1) -- 1 below treeline-120, 0 above tl
			-- valley-bottom moisture proxy: lower elevations in the local range grow denser
			local moist = math.clamp(1 - (elev - 24) / 260, 0, 1)
			-- slope suitability (spec): exp falloff; trees tolerate less than shrubs
			local slopeTree = math.exp(-((slope / 0.34) ^ 2))
			local slopeShrub = math.exp(-((slope / 0.55) ^ 2))
			-- species selection
			local r = hash01(x, z, 53)
			local treeP = forest * slopeTree * highT * (0.35 + 0.65 * moist)
			local shrubP = slopeShrub * (0.25 + 0.45 * moist) * (1 - forest * 0.4)
			local stoneP = slopeShrub * (1 - moist * 0.5) * 0.24 + (elev > tl and 0.30 or 0)
			if trees < treeBudget and r < treeP then
				local s = 0.8 + hash01(x, z, 61) * 0.9
				buildTree(folder, x, z, gy, s, 71)
				trees += 1
				spent += 1
			elseif shrubs < shrubBudget and r < treeP + shrubP then
				buildShrub(folder, x, z, gy, 0.8 + hash01(x, z, 67) * 0.8)
				shrubs += 1
				spent += 1
			elseif stones < stoneBudget and r < treeP + shrubP + stoneP then
				buildStone(folder, x, z, gy, 0.8 + hash01(x, z, 71) * 1.4)
				stones += 1
				spent += 1
			end
		end
		if cx % 30 == 0 then task.wait() end
	end
	print(string.format("VegetationService: trees=%d shrubs=%d stones=%d probes=%d in %.1fs",
		trees, shrubs, stones, probes, os.clock() - t0))
	return folder
end

return VegetationService
