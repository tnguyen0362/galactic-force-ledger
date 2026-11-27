--!strict
-- VegetationService (Phase 15 rewrite): biome-driven ecology over the baked geographical foundation.
-- Kept from the previous version: stratified 24-stud cell scan, low-frequency forest-region noise,
-- noise-modulated treeline, terrain-raycast slope rejection, valley moisture proxy, frame slicing.
-- New: species come from authored mesh models in ServerStorage.GF.Art (via ArtService), chosen per
-- biome and role. NO part-built trees: if a role has no authored species it is simply not planted
-- (owner rule 2026-11-25: "quality assets or nothing"). Shrub/stone roles keep a palette-tinted
-- primitive fallback so the ground is never bare while the mesh library is being produced.
--
-- Species naming contract (ServerStorage.GF.Art): Veg_<Biome>_<Role>_<Letter>, e.g.
--   Veg_Forest_Canopy_A, Veg_Tundra_Mid_B, Veg_Arid_Scrub_A, Veg_Industrial_Rock_A
-- Roles: Canopy (tall tree), Mid (understory tree), Scrub (bush), Ground (clutter), Rock (boulder).
-- Letters A..F are probed in order until one is missing.
--
-- Every planted instance carries attribute GF_VegTier (1 always visible, 2 Balanced+, 3 High only)
-- so a client quality script can cull density per tier without the server knowing the device.

local VegetationService = {}

local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain

local ArtService = require(script.Parent:WaitForChild("ArtService"))

-- ===================== ecology per biome =====================
type Role = { budget: number, minH: number, maxH: number }
type Eco = {
	forestScale: number, -- noise wavelength of forest regions (studs)
	forestK: number, -- sigmoid sharpness of region edges
	forestBase: number, -- background chance outside regions
	treeline: number, -- elevation where canopy vanishes
	roles: { Canopy: Role, Mid: Role, Scrub: Role, Ground: Role, Rock: Role },
	tint: { stone: Color3, shrub: Color3 },
}

local function role(budget: number, minH: number, maxH: number): Role
	return { budget = budget, minH = minH, maxH = maxH }
end

local ECO: { [string]: Eco } = {
	-- dense verdant basin: big continuous canopy with clearings, thick understory
	Forest = {
		forestScale = 420, forestK = 6, forestBase = 0.18, treeline = 430,
		roles = {
			Canopy = role(1500, 30, 46), Mid = role(900, 12, 20), Scrub = role(1400, 3, 6),
			Ground = role(1200, 1, 2.5), Rock = role(500, 3, 10),
		},
		tint = { stone = Color3.fromRGB(96, 94, 86), shrub = Color3.fromRGB(58, 96, 62) },
	},
	-- mountain/frozen: sparse hardy conifers low on the slopes, dead snags, lots of rock
	Tundra = {
		forestScale = 300, forestK = 4, forestBase = 0.10, treeline = 300,
		roles = {
			Canopy = role(520, 24, 38), Mid = role(260, 8, 14), Scrub = role(500, 2, 4),
			Ground = role(500, 0.8, 1.8), Rock = role(800, 4, 14),
		},
		tint = { stone = Color3.fromRGB(120, 126, 134), shrub = Color3.fromRGB(110, 128, 120) },
	},
	-- arid highlands: scattered scrub trees and succulents, strata-coloured boulders
	Arid = {
		forestScale = 260, forestK = 3, forestBase = 0.12, treeline = 520,
		roles = {
			Canopy = role(180, 12, 22), Mid = role(260, 5, 10), Scrub = role(900, 2, 5),
			Ground = role(700, 0.8, 2), Rock = role(900, 4, 16),
		},
		tint = { stone = Color3.fromRGB(150, 116, 88), shrub = Color3.fromRGB(142, 130, 84) },
	},
	-- industrial wasteland: no living canopy; dead snags, scrap clusters, rubble
	Industrial = {
		forestScale = 200, forestK = 3, forestBase = 0.08,
		treeline = 600,
		roles = {
			Canopy = role(120, 10, 18), Mid = role(100, 4, 8), Scrub = role(240, 1.5, 3),
			Ground = role(600, 0.8, 2), Rock = role(700, 3, 9),
		},
		tint = { stone = Color3.fromRGB(104, 98, 92), shrub = Color3.fromRGB(100, 96, 80) },
	},
	-- hilly jungle (owner directive 2026-11-28): wall-to-wall broadleaf canopy, heavy mid
	-- layer and thick scrub understory — the density IS the biome. Higher treeline than
	-- forest: jungle climbs the hills. Budgets above Forest but below 2x — streaming sheds
	-- the far field, and the memory roadmap caps how far this can be pushed.
	Jungle = {
		forestScale = 520, forestK = 7, forestBase = 0.42, treeline = 520,
		roles = {
			Canopy = role(1900, 34, 52), Mid = role(1300, 14, 24), Scrub = role(1900, 3, 7),
			Ground = role(1600, 1, 3), Rock = role(350, 3, 8),
		},
		tint = { stone = Color3.fromRGB(88, 92, 80), shrub = Color3.fromRGB(34, 108, 52) },
	},
}
ECO.Volcanic = ECO.Industrial -- legacy name: never in rotation, avoid nil lookups

-- ===================== helpers =====================
local function hash01(x: number, z: number, salt: number): number
	local v = math.sin(x * 12.9898 + z * 78.233 + salt * 37.719) * 43758.5453
	return v - math.floor(v)
end

local function noise2(x: number, z: number, scale: number, seed: number): number
	return math.noise(x / scale, z / scale, seed)
end

local function sigmoid(v: number, k: number): number
	return 1 / (1 + math.exp(-k * v))
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

-- authored species discovery: Veg_<Biome>_<Role>_A.. (stops at first gap)
local LETTERS = { "A", "B", "C", "D", "E", "F" }
type Species = { id: string, height: number, bottom: number }
local specCache: { [string]: { Species } } = {}

local function speciesFor(biome: string, roleName: string): { Species }
	local key = biome .. "_" .. roleName
	local cached = specCache[key]
	if cached then return cached end
	local list: { Species } = {}
	for _, letter in LETTERS do
		local id = string.format("Veg_%s_%s_%s", biome, roleName, letter)
		if not ArtService.exists(id) then break end
		local tpl = ArtService.clone(id)
		if tpl then
			local cf, size = tpl:GetBoundingBox()
			local pivot = tpl:GetPivot()
			table.insert(list, {
				id = id,
				height = math.max(size.Y, 0.1),
				bottom = pivot.Position.Y - (cf.Position.Y - size.Y * 0.5), -- pivot height above model base
			})
			tpl:Destroy()
		end
	end
	if #list == 0 and biome ~= "Forest" then
		-- no authored species for this biome/role: inherit Forest assets. The biome identity
		-- comes from ecology (density/heights/regions) + tint, not the meshes themselves —
		-- authored jungle species replace this fallback when the art lands.
		list = speciesFor("Forest", roleName)
	end
	specCache[key] = list
	return list
end

function VegetationService.resetCache()
	specCache = {}
end

local function placeMesh(folder: Instance, sp: Species, x: number, z: number, gy: number, targetH: number, tier: number, collide: boolean, seedsalt: number)
	local m = ArtService.clone(sp.id)
	if not m then return end
	local factor = targetH / sp.height
	m:ScaleTo(factor)
	local yaw = hash01(x, z, seedsalt) * math.pi * 2
	local lean = (hash01(x, z, seedsalt + 3) - 0.5) * 0.08
	m:PivotTo(CFrame.new(x, gy + sp.bottom * factor - 0.35, z) * CFrame.Angles(lean, yaw, lean * 0.6))
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CastShadow = targetH > 12 -- only big silhouettes cast; keeps shadow cost bounded
		end
	end
	m:SetAttribute("GF_VegTier", tier)
	m.Parent = folder
	if collide then
		-- one invisible trunk collider keeps cover/line-of-sight behaviour of the old trunks
		local c = Instance.new("Part")
		c.Name = "TrunkCollider"
		c.Size = Vector3.new(math.max(1.2, targetH * 0.05), targetH * 0.55, math.max(1.2, targetH * 0.05))
		c.CFrame = CFrame.new(x, gy + c.Size.Y * 0.5 - 0.3, z)
		c.Transparency = 1
		c.Anchored = true
		c.CanCollide = true
		c.CanTouch = false
		c.CastShadow = false
		c:SetAttribute("GF_VegTier", 1)
		c.Parent = m
	end
end

-- primitive fallbacks for ground cover only (never trees)
local function mkPrim(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("GF_VegTier", 1)
	p.Parent = parent
end

export type VegOpts = {
	seed: number?,
	center: Vector3?,
	extent: number?,
	biome: string?,
	budgetScale: number?, -- multiplies every role budget (tier/perf knob)
	treeline: number?,
}

function VegetationService.plant(opts: VegOpts?): Folder
	local o = opts or {} :: any
	local seed = o.seed or 4201
	local center = o.center or Vector3.new(0, 0, 0)
	local extent = o.extent or 4900
	local biomeName = o.biome or (Workspace:GetAttribute("GF_Biome") :: any) or "Forest"
	local eco = ECO[biomeName] or ECO.Forest
	local bscale = o.budgetScale or 1
	local treeline = o.treeline or eco.treeline

	local old = Workspace:FindFirstChild("GFVegetation")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "GFVegetation"
	folder:SetAttribute("GF_Biome", biomeName)
	folder.Parent = Workspace

	local sp = {
		Canopy = speciesFor(biomeName, "Canopy"),
		Mid = speciesFor(biomeName, "Mid"),
		Scrub = speciesFor(biomeName, "Scrub"),
		Ground = speciesFor(biomeName, "Ground"),
		Rock = speciesFor(biomeName, "Rock"),
	}
	local counts = { Canopy = 0, Mid = 0, Scrub = 0, Ground = 0, Rock = 0 }
	local function cap(r: string): number
		return math.floor((eco.roles :: any)[r].budget * bscale)
	end

	local half = extent / 2
	local t0 = os.clock()
	local probes = 0
	local cell = 24
	local n = math.floor(extent / cell)

	local function pick(list: { Species }, x: number, z: number, salt: number): Species?
		if #list == 0 then return nil end
		return list[1 + math.floor(hash01(x, z, salt) * #list) % #list]
	end
	local function height(r: string, x: number, z: number, salt: number): number
		local rr = (eco.roles :: any)[r] :: Role
		return rr.minH + (rr.maxH - rr.minH) * hash01(x, z, salt)
	end
	local function tierOf(x: number, z: number, salt: number): number
		local h = hash01(x, z, salt)
		return h < 0.55 and 1 or (h < 0.8 and 2 or 3)
	end

	-- visit cells in a seeded shuffled order so the per-role budgets spread over the WHOLE map
	-- (a linear scan exhausted every budget in the first strip and left the rest of the map bare)
	local order: { number } = table.create(n * n)
	for i = 0, n * n - 1 do order[i + 1] = i end
	local rng = Random.new(seed + 977)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end

	for oi = 1, #order do
		do
			local cx = order[oi] // n
			local cz = order[oi] % n
			local bx = center.X - half + (cx + 0.5) * cell
			local bz = center.Z - half + (cz + 0.5) * cell
			local x = bx + (hash01(bx, bz, 31) - 0.5) * cell * 0.8
			local z = bz + (hash01(bx, bz, 37) - 0.5) * cell * 0.8
			local forestN = noise2(x, z, eco.forestScale, seed + 11) * 0.72 + noise2(x, z, eco.forestScale * 0.36, seed + 23) * 0.28
			local forest = sigmoid(forestN, eco.forestK)
			if hash01(x, z, 41) > forest + eco.forestBase then
				continue
			end
			probes += 1
			local gy, normal = ground(x, z)
			if not gy or not normal then continue end
			local slope = 1 - (normal :: Vector3).Y
			local tlNoise = noise2(x, z, 260, seed + 31) * 60
			local tl = treeline + tlNoise
			local elev = gy :: number
			local highT = math.clamp(1 - (elev - (tl - 120)) / 120, 0, 1)
			local moist = math.clamp(1 - (elev - 24) / 260, 0, 1)
			local slopeTree = math.exp(-((slope / 0.34) ^ 2))
			local slopeShrub = math.exp(-((slope / 0.55) ^ 2))
			local slopeRock = math.exp(-((slope / 0.8) ^ 2))

			local r = hash01(x, z, 53)
			local treeP = forest * slopeTree * highT * (0.35 + 0.65 * moist)
			local midP = forest * slopeTree * highT * 0.55
			local scrubP = slopeShrub * (0.25 + 0.45 * moist) * (1 - forest * 0.3)
			local groundP = slopeShrub * (0.2 + forest * 0.5)
			local rockP = slopeRock * (1 - moist * 0.5) * 0.24 + (elev > tl and 0.3 or 0)
			local total = treeP + midP + scrubP + groundP + rockP
			if total <= 0 then continue end
			local roll = r * math.max(total, 1)

			local acc = treeP
			if roll < acc then
				local s = counts.Canopy < cap("Canopy") and pick(sp.Canopy, x, z, 71)
				if s then
					placeMesh(folder, s :: Species, x, z, gy, height("Canopy", x, z, 61), 1, true, 71)
					counts.Canopy += 1
				end
			else
				acc += midP
				if roll < acc then
					local s = counts.Mid < cap("Mid") and pick(sp.Mid, x, z, 73)
					if s then
						placeMesh(folder, s :: Species, x, z, gy, height("Mid", x, z, 63), tierOf(x, z, 5), true, 73)
						counts.Mid += 1
					end
				else
					acc += scrubP
					if roll < acc then
						if counts.Scrub < cap("Scrub") then
							local s = pick(sp.Scrub, x, z, 79)
							local h = height("Scrub", x, z, 67)
							if s then
								placeMesh(folder, s, x, z, gy, h, tierOf(x, z, 7), false, 79)
							else
								mkPrim(folder, "Shrub", Vector3.new(h * 0.9, h * 0.55, h * 0.8),
									CFrame.new(x, gy + h * 0.25, z) * CFrame.Angles(0.05, hash01(x, z, 13) * 6.28, 0.07),
									eco.tint.shrub, Enum.Material.Grass)
							end
							counts.Scrub += 1
						end
					else
						acc += groundP
						if roll < acc then
							local s = counts.Ground < cap("Ground") and pick(sp.Ground, x, z, 83)
							if s then
								placeMesh(folder, s :: Species, x, z, gy, height("Ground", x, z, 69), tierOf(x, z, 9), false, 83)
								counts.Ground += 1
							end
						elseif roll < acc + rockP then
							if counts.Rock < cap("Rock") then
								local s = pick(sp.Rock, x, z, 89)
								local h = height("Rock", x, z, 71)
								if s then
									placeMesh(folder, s, x, z, gy, h, 1, true, 89)
								else
									mkPrim(folder, "Stone", Vector3.new(h * 0.9, h * 0.6, h * 0.7),
										CFrame.new(x, gy + h * 0.25, z) * CFrame.Angles(0.08, hash01(x, z, 17) * 6.28, 0.05),
										eco.tint.stone, Enum.Material.Slate)
								end
								counts.Rock += 1
							end
						end
					end
				end
			end
		end
		if oi % 400 == 0 then task.wait() end
	end

	workspace:SetAttribute("GF_VegCounts", string.format("c%d m%d s%d g%d r%d", counts.Canopy, counts.Mid, counts.Scrub, counts.Ground, counts.Rock))
	print(string.format("VegetationService[%s]: canopy=%d mid=%d scrub=%d ground=%d rock=%d probes=%d species=%d/%d/%d/%d/%d in %.1fs",
		biomeName, counts.Canopy, counts.Mid, counts.Scrub, counts.Ground, counts.Rock, probes,
		#sp.Canopy, #sp.Mid, #sp.Scrub, #sp.Ground, #sp.Rock, os.clock() - t0))
	return folder
end

return VegetationService
