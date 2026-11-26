--!strict
-- ScatterBuilder: biome-aware ground decoration — the battlefield's missing surface texture.
-- Three density layers per the brief's cover/sightline section:
--   trees:      angular alien flora (trunk + slab canopy), clustered by geography kind
--   shrubs:     low non-collidable tufts/rocks — visual texture, zero gameplay obstruction
--   debris:     small scattered stones/wreck fragments
-- Placement derives from the same plan data the generator validated: basin floors, valley
-- floors, and route corridors get density; mesa tops and steep slopes stay sparse. Cheap
-- parts only, instance-budgeted, static — premium art pass replaces meshes later.

local NoiseKit = require(script.Parent.NoiseKit)

local ScatterBuilder = {}

local TRUNK_C = Color3.fromRGB(64, 54, 48)
local CANOPY_C = Color3.fromRGB(54, 92, 74)
local CANOPY_C2 = Color3.fromRGB(46, 78, 66)
local SHRUB_C = Color3.fromRGB(62, 84, 64)
local STONE_C = Color3.fromRGB(88, 84, 78)

local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = collide
	p.CastShadow = false -- perf: hundreds of scatter parts shouldn't tax shadow maps
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function hash01(x: number, z: number, salt: number): number
	local v = math.sin(x * 12.9898 + z * 78.233 + salt * 37.719) * 43758.5453
	return v - math.floor(v)
end

local function buildTree(folder: Instance, x: number, z: number, gy: number, s: number)
	local yaw = hash01(x, z, 11) * math.pi * 2
	local h = 10 * s
	-- angular alien conifer: tapered trunk + 3 shrinking rotated canopy slabs
	mk(folder, "Trunk", Vector3.new(0.9 * s, h * 0.55, 0.9 * s),
		CFrame.new(x, gy + h * 0.27, z) * CFrame.Angles(0, yaw, 0.04), TRUNK_C, Enum.Material.Wood, true)
	for i = 1, 3 do
		local w = (4.6 - i * 1.1) * s
		local cy = gy + h * (0.42 + i * 0.18)
		mk(folder, "Canopy" .. i, Vector3.new(w, 1.1 * s, w),
			CFrame.new(x, cy, z) * CFrame.Angles(0.03, yaw + i * 0.8, -0.02), i % 2 == 0 and CANOPY_C or CANOPY_C2, Enum.Material.Grass, false)
	end
end

local function buildShrub(folder: Instance, x: number, z: number, gy: number, s: number)
	local yaw = hash01(x, z, 13) * math.pi * 2
	mk(folder, "Shrub", Vector3.new(1.8 * s, 1.1 * s, 1.6 * s),
		CFrame.new(x, gy + 0.45 * s, z) * CFrame.Angles(0.05, yaw, 0.07), SHRUB_C, Enum.Material.Grass, false)
end

local function buildStone(folder: Instance, x: number, z: number, gy: number, s: number)
	local yaw = hash01(x, z, 17) * math.pi * 2
	mk(folder, "Stone", Vector3.new(1.1 * s, 0.7 * s, 0.9 * s),
		CFrame.new(x, gy + 0.3 * s, z) * CFrame.Angles(0.08, yaw, 0.05), STONE_C, Enum.Material.Slate, false)
end

-- Density field per archetype: how much vegetation belongs where.
-- Returns tree/shrub/stone density multipliers for a height relative to the local range
-- and the archetype character.
local function archetypeDensity(archetype: string): (number, number, number)
	if archetype == "broken_basin" then
		return 1.6, 1.4, 1.2 -- vegetated basin floors (forested flavor)
	elseif archetype == "highland_valley" then
		return 1.3, 1.2, 1.0 -- valley floor clusters
	elseif archetype == "open_plains" then
		return 0.5, 1.5, 0.9 -- few trees, abundant grass-shrubs
	elseif archetype == "canyon_network" then
		return 0.7, 0.9, 1.4 -- sparse trees in channels, stony mesas
	elseif archetype == "industrial_wasteland" then
		return 0.25, 0.5, 1.6 -- dead land, debris instead
	else -- fortified_plateau
		return 0.8, 1.0, 1.1
	end
end

-- groundY(x,z): live terrain height. sampler(x,z): analytic height for slope estimates.
-- extent: half-width of the battlefield square. Budget caps total instances.
function ScatterBuilder.buildAll(plan: any, groundY: (number, number) -> number, parent: Instance, budget: number?): number
	local root = Instance.new("Folder")
	root.Name = "BFScatter"
	root.Parent = parent
	local maxInst = budget or 900
	local extent = 720
	local step = 34 -- scatter sampling lattice
	local treeD, shrubD, stoneD = archetypeDensity(plan.archetype or "")
	local seed = plan.seed or 1
	local built = 0
	-- deterministic lattice with hash jitter — stable across rebuilds, no RNG stream needed
	for gx = -extent, extent, step do
		for gz = -extent, extent, step do
			if built >= maxInst then
				break
			end
			local jx = gx + (hash01(gx, gz, 1) - 0.5) * step * 0.9
			local jz = gz + (hash01(gx, gz, 2) - 0.5) * step * 0.9
			-- micro noise gate: clustered distribution, not uniform lattice
			local densityNoise = NoiseKit.fbm(jx, jz, 170, seed + 91, 2) + 0.5
			local roll = hash01(gx, gz, 3)
			if roll < densityNoise * 0.55 then
				-- slope rejection: skip steep ground (estimate by sampling neighbors)
				local gy = groundY(jx, jz)
				local gx2 = groundY(jx + 6, jz)
				local gz2 = groundY(jx, jz + 6)
				if gy and gx2 and gz2 then
					local slope = math.max(math.abs(gx2 - gy), math.abs(gz2 - gy)) / 6
					if slope < 0.55 then
						local kindRoll = hash01(gx, gz, 4)
						local s = 0.8 + hash01(gx, gz, 5) * 0.7
						if kindRoll < 0.2 * treeD then
							buildTree(root, jx, jz, gy, s)
							built += 4
						elseif kindRoll < 0.2 * treeD + 0.45 * shrubD then
							buildShrub(root, jx, jz, gy, s)
							built += 1
						elseif kindRoll < 0.2 * treeD + 0.45 * shrubD + 0.35 * stoneD then
							buildStone(root, jx, jz, gy, s)
							built += 1
						end
					end
				end
			end
		end
	end
	return built
end

return ScatterBuilder
