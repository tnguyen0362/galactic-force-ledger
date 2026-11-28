--!strict
-- VegetationService (Phase 15 rewrite): biome-driven ecology over the baked geographical foundation.
-- Kept from the previous version: stratified 24-stud cell scan, low-frequency forest-region noise,
-- noise-modulated treeline, slope rejection, valley moisture proxy, frame slicing. Runtime-generated
-- foundations use the in-memory heightfield for ground/slope; baked fallback paths still raycast.
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
local ServerStorage = game:GetService("ServerStorage")
local Terrain = Workspace.Terrain

local ArtService = require(script.Parent:WaitForChild("ArtService"))

-- ===================== ecology per biome =====================
type Role = { budget: number, minH: number, maxH: number }
type Eco = {
	forestScale: number, -- noise wavelength of forest regions (studs)
	forestK: number, -- sigmoid sharpness of region edges
	forestBase: number, -- background chance outside regions
	treeline: number, -- elevation where canopy vanishes
	denseR: number?, -- corridor radius that gets the 8-stud probe grid
	understory: number?, -- multiplies scrub/ground weight
	forestFloor: number?, -- minimum forest factor (no bald regions)
	roles: { Canopy: Role, Mid: Role, Scrub: Role, Ground: Role, Rock: Role, Log: Role? },
	rockBoost: number?, -- multiplies rock probability (rocky biomes)
	rockScale: { number }?, -- {min,max} multiplier on the authored rock's native size (instead of minH/maxH)
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
		denseR = 260, understory = 1.6, forestFloor = 0.72,
		roles = {
			Canopy = role(2400, 34, 52), Mid = role(1900, 14, 24), Scrub = role(3800, 3, 7),
			Ground = role(3400, 1, 3), Rock = role(650, 3, 8), Log = role(420, 9, 18),
		},
		-- authored kit rocks keep their native proportions: 0.55x..1.5x of a 4-10 stud boulder
		rockBoost = 2.4, rockScale = { 0.55, 1.5 },
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

-- Analytic ground for runtime-generated foundations. Terrain is written from heights on
-- the 4-stud writer lattice; reconstructing that lattice bilinearly gives the same local
-- surface to within the sub-voxel smoothing error, while slope comes from the patch's
-- exact derivatives. This replaces thousands of 3700-stud terrain raycasts with four
-- in-memory heightfield samples per probe, and allocates no vectors in the hot loop.
local function heightfieldGround(sample: (number, number) -> number): (number, number) -> (number, number)
	local firstCenter = -2498
	local cells = 1250
	local cell = 4
	return function(x: number, z: number): (number, number)
		local qx = (x - firstCenter) / cell
		local qz = (z - firstCenter) / cell
		local ix = math.clamp(math.floor(qx), 0, cells - 2)
		local iz = math.clamp(math.floor(qz), 0, cells - 2)
		local fx = math.clamp(qx - ix, 0, 1)
		local fz = math.clamp(qz - iz, 0, 1)
		local x0 = firstCenter + ix * cell
		local z0 = firstCenter + iz * cell
		local h00 = sample(x0, z0)
		local h10 = sample(x0 + cell, z0)
		local h01 = sample(x0, z0 + cell)
		local h11 = sample(x0 + cell, z0 + cell)
		local gx = ((h10 - h00) * (1 - fz) + (h11 - h01) * fz) / cell
		local gz = ((h01 - h00) * (1 - fx) + (h11 - h10) * fx) / cell
		local h = h00 * (1 - fx) * (1 - fz) + h10 * fx * (1 - fz) + h01 * (1 - fx) * fz + h11 * fx * fz
		return h, 1 / math.sqrt(1 + gx * gx + gz * gz)
	end
end

local function raycastGround(x: number, z: number): (number?, number?)
	local hit = Workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -2200, 0), rayParams)
	if hit then
		return hit.Position.Y, hit.Normal.Y
	end
	return nil, nil
end

-- authored species discovery: Veg_<Biome>_<Role>_A.. (stops at first gap)
local LETTERS = { "A", "B", "C", "D", "E", "F" }
type Species = { id: string, height: number, length: number, bottom: number, template: Model?, proto: Model? }
type PlaceOpts = { scale: number?, yaw: number?, pitch: number?, sink: number? }
local specCache: { [string]: { Species } } = {}

local function artTemplate(id: string): Model?
	local gf = ServerStorage:FindFirstChild("GF")
	local art = gf and gf:FindFirstChild("Art")
	local template = art and art:FindFirstChild(id)
	return if template and template:IsA("Model") then template else nil
end

-- Species ids that stand in for a missing Veg_<Biome>_<Role>_<Letter> series. Jungle rocks are the
-- authored Kit_Terrain boulders (hull-collision meshes with real textures), not the Forest pebbles.
local ALIASES: { [string]: { string } } = {
	Jungle_Rock = { "Kit_Terrain_RockBig", "Kit_Terrain_RockMid", "Kit_Terrain_RockCluster", "Kit_Terrain_RockSlab", "Kit_Terrain_RockSmall", "Kit_Terrain_RockMid" },
}
-- roles whose Forest fallback does NOT fit the biome (pines / blob crowns read as 'cheap trees' in a
-- jungle): plant nothing until authored Veg_Jungle_<role> species exist (owner: quality assets or nothing).
local NO_FOREST_FALLBACK: { [string]: boolean } = {
	Jungle_Canopy = true, Jungle_Mid = true, Jungle_Scrub = true, Jungle_Ground = true, -- Veg_Jungle_* authored (Blender gen_jungle.py)
	Jungle_Log = true,
}

local function speciesFor(biome: string, roleName: string): { Species }
	local key = biome .. "_" .. roleName
	local cached = specCache[key]
	if cached then return cached end
	local list: { Species } = {}
	local ids: { string } = {}
	local alias = ALIASES[key]
	if alias then
		for _, id in alias do table.insert(ids, id) end
	else
		for _, letter in LETTERS do table.insert(ids, string.format("Veg_%s_%s_%s", biome, roleName, letter)) end
	end
	for _, id in ids do
		local tpl = artTemplate(id)
		if not tpl then break end
		local cf, size = tpl:GetBoundingBox()
		local pivot = tpl:GetPivot()
		table.insert(list, {
			id = id,
			height = math.max(size.Y, 0.1),
			length = math.max(size.X, size.Z, 0.1), -- longest horizontal extent (logs author their long axis along X)
			bottom = pivot.Position.Y - (cf.Position.Y - size.Y * 0.5), -- pivot height above model base
			template = tpl,
			proto = nil,
		})
	end
	if #list == 0 and biome ~= "Forest" and not NO_FOREST_FALLBACK[key] then
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

local function placeMesh(folder: Instance, sp: Species, x: number, z: number, gy: number, targetH: number, tier: number, collide: boolean, seedsalt: number, colliderProto: Instance?, po: PlaceOpts?)
	-- Clone a per-plant prepared prototype when available. Static part properties were
	-- already fixed on that prototype, avoiding thousands of repeated Anchored/CanCollide/
	-- CanTouch writes; the template reference itself is cached, avoiding three art-library
	-- lookups per placed instance. Final instance properties are unchanged.
	local m: any = nil
	local usedProto = sp.proto ~= nil
	if sp.proto then
		m = (sp.proto :: Model):Clone()
	elseif sp.template then
		m = (sp.template :: Model):Clone()
		if m then m:SetAttribute("GF_ArtInstance", true) end
	else
		m = ArtService.clone(sp.id)
	end
	if not m then return end
	local factor = if po and po.scale then po.scale else targetH / sp.height
	m:ScaleTo(factor)
	local yaw = if po and po.yaw then po.yaw else hash01(x, z, seedsalt) * math.pi * 2
	local sink = if po and po.sink then po.sink else 0.35
	if po and po.pitch then
		-- logs: long axis (local X) follows the slope between its two ends
		m:PivotTo(CFrame.new(x, gy + sp.bottom * factor - sink, z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, po.pitch))
	else
		local lean = (hash01(x, z, seedsalt + 3) - 0.5) * 0.08
		m:PivotTo(CFrame.new(x, gy + sp.bottom * factor - sink, z) * CFrame.Angles(lean, yaw, lean * 0.6))
	end
	if usedProto then
		if targetH > 12 then
			-- Prototypes carry CastShadow=false; only large silhouettes need the write.
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and not d.CastShadow then
					d.CastShadow = true
				end
			end
		end
	else
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CastShadow = targetH > 12 -- only big silhouettes cast; keeps shadow cost bounded
			end
		end
	end
	m:SetAttribute("GF_VegTier", tier)
	m.Parent = folder
	if collide then
		-- one invisible trunk collider keeps cover/line-of-sight behaviour of the old trunks
		local c: any
		if colliderProto then
			c = colliderProto:Clone()
		else
			c = Instance.new("Part")
			c.Name = "TrunkCollider"
			c.Transparency = 1
			c.Anchored = true
			c.CanCollide = true
			c.CanTouch = false
			c.CastShadow = false
			c:SetAttribute("GF_VegTier", 1)
		end
		c.Size = Vector3.new(math.max(1.2, targetH * 0.05), targetH * 0.55, math.max(1.2, targetH * 0.05))
		c.CFrame = CFrame.new(x, gy + c.Size.Y * 0.5 - 0.3, z)
		c.Parent = m
	end
end

-- primitive fallbacks for ground cover only (never trees)
local function mkPrim(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, proto: Instance?)
	local p: any
	if proto then
		p = proto:Clone()
	else
		p = Instance.new("Part")
		p.Name = name
		p.Color = color
		p.Material = mat
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p:SetAttribute("GF_VegTier", 1)
	end
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
end

export type VegOpts = {
	seed: number?,
	center: Vector3?,
	extent: number?,
	biome: string?,
	budgetScale: number?, -- multiplies every role budget (tier/perf knob)
	treeline: number?,
	heightSampler: ((number, number) -> number)?, -- internal generation fast path
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
	-- Deliberately parentless during the scan: every clone then assembles outside the
	-- workspace replication/physics pipeline, and the complete batch enters the world in
	-- one parent assignment instead of thousands of separate workspace insertions.

	local sp = {
		Canopy = speciesFor(biomeName, "Canopy"),
		Mid = speciesFor(biomeName, "Mid"),
		Scrub = speciesFor(biomeName, "Scrub"),
		Ground = speciesFor(biomeName, "Ground"),
		Rock = speciesFor(biomeName, "Rock"),
		Log = if eco.roles.Log then speciesFor(biomeName, "Log") else {},
	}
	local logRole = eco.roles.Log

	-- Prepare one unparented archetype per authored species for the duration of this
	-- plant. Archetypes carry the invariant part properties, so production clones only
	-- need scale/pivot (plus CastShadow for large silhouettes). They are destroyed before
	-- return, leaving no persistent memory cost.
	local preparedSpecies: { Species } = {}
	local function prepareSpeciesList(list: { Species }, solid: boolean?)
		for _, s in list do
			if s.template and not s.proto then
				local proto = (s.template :: Model):Clone()
				proto:SetAttribute("GF_ArtInstance", true)
				for _, d in proto:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = solid == true -- rocks / logs collide as their own (hull) mesh
						d.CanTouch = false
						d.CastShadow = false
					end
				end
				s.proto = proto
				table.insert(preparedSpecies, s)
			end
		end
	end
	prepareSpeciesList(sp.Canopy)
	prepareSpeciesList(sp.Mid)
	prepareSpeciesList(sp.Scrub)
	prepareSpeciesList(sp.Ground)
	prepareSpeciesList(sp.Rock, true)
	prepareSpeciesList(sp.Log, true)

	local colliderProto = Instance.new("Part")
	colliderProto.Name = "TrunkCollider"
	colliderProto.Transparency = 1
	colliderProto.Anchored = true
	colliderProto.CanCollide = true
	colliderProto.CanTouch = false
	colliderProto.CastShadow = false
	colliderProto:SetAttribute("GF_VegTier", 1)

	local function primitiveProto(name: string, color: Color3, mat: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Color = color
		p.Material = mat
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p:SetAttribute("GF_VegTier", 1)
		return p
	end
	local shrubProto = primitiveProto("Shrub", eco.tint.shrub, Enum.Material.Grass)
	local stoneProto = primitiveProto("Stone", eco.tint.stone, Enum.Material.Slate)
	stoneProto.CanCollide = true -- fallback boulders are solid too

	-- Runtime geography keeps its decoded heightfield sampler in memory. Use it for the
	-- seed it generated; baked/procedural fallback paths retain exact terrain raycasts.
	local sampler = o.heightSampler
	if type(sampler) ~= "function" then
		local ok, geography = pcall(function()
			local mod = script.Parent:FindFirstChild("GeographyService")
			return mod and require(mod)
		end)
		if ok and geography and geography.lastSampler and geography.lastSpec
			and geography.lastSpec.seed * 3 + 11 == seed then
			sampler = geography.lastSampler
		end
	end
	local ground: (number, number) -> (number?, number?)
	if type(sampler) == "function" then
		local field = heightfieldGround(sampler)
		-- the 4-stud writer lattice leaves the real voxel surface ~2 studs ABOVE the analytic field (measured:
		-- every role sat -2.2 studs under the surface, burying understory and logs). Keep the analytic slope
		-- (density tuning depends on it) but take the height from a short ray seeded just above the field.
		ground = function(x: number, z: number): (number?, number?)
			local h, n = field(x, z)
			local hit = Workspace:Raycast(Vector3.new(x, h + 16, z), Vector3.new(0, -40, 0), rayParams)
			if hit then
				return hit.Position.Y, n
			end
			return h, n
		end
	else
		ground = raycastGround
	end

	local counts = { Canopy = 0, Mid = 0, Scrub = 0, Ground = 0, Rock = 0, Log = 0 }
	local capsFull = {
		Canopy = math.floor(eco.roles.Canopy.budget * bscale),
		Mid = math.floor(eco.roles.Mid.budget * bscale),
		Scrub = math.floor(eco.roles.Scrub.budget * bscale),
		Ground = math.floor(eco.roles.Ground.budget * bscale),
		Rock = math.floor(eco.roles.Rock.budget * bscale),
		Log = math.floor((if logRole then logRole.budget else 0) * bscale),
	}

	-- play-space corridor: LZ -> objective -> extraction. The fixed budget used to be spread evenly over
	-- the whole 4900-stud map (~58 stud spacing = dead space where the squad actually fights). When the
	-- anchors are known, ~85% of every role's budget is spent inside the corridor on a finer grid and the
	-- remainder thins out across the far field. Anchor pads stay clear for the dropship / extraction.
	local anchors: { Vector3 } = {}
	if type(o.anchors) == "table" then
		anchors = o.anchors
	else
		for _, nm in { "GF_AnchorLZ", "GF_AnchorObjective", "GF_AnchorExtraction" } do
			local v = Workspace:GetAttribute(nm)
			if typeof(v) == "Vector3" then table.insert(anchors, v) end
		end
	end
	if #anchors < 2 then
		-- live path: Mission.luau builds the world on the fixed legacy LZ/objective flats (z = +118 / -120),
		-- MissionServerInit.boot (the only anchor writer) is not on this path, so default to those.
		anchors = { Vector3.new(0, 0, 118), Vector3.new(0, 0, -120) }
	end
	local hasCorridor = #anchors >= 2
	local NEAR_R, FAR_R, FAR_W = 480, 1000, 0.1
	local CLEAR_R, CLEAR_SOFT = 55, 95
	local function corridorDist(x: number, z: number): number
		local best = math.huge
		for i = 1, #anchors - 1 do
			local a, b = anchors[i], anchors[i + 1]
			local abx, abz = b.X - a.X, b.Z - a.Z
			local len2 = abx * abx + abz * abz
			local t = if len2 > 0 then math.clamp(((x - a.X) * abx + (z - a.Z) * abz) / len2, 0, 1) else 0
			local dx, dz = x - (a.X + abx * t), z - (a.Z + abz * t)
			best = math.min(best, math.sqrt(dx * dx + dz * dz))
		end
		return best
	end
	local function clearFactor(x: number, z: number): number
		local f = 1
		for _, a in anchors do
			local dx, dz = x - a.X, z - a.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d < CLEAR_SOFT then f = math.min(f, math.max(0, (d - CLEAR_R) / (CLEAR_SOFT - CLEAR_R))) end
		end
		return f
	end
	local caps = capsFull
	if hasCorridor then
		caps = {
			Canopy = math.floor(capsFull.Canopy * 0.85), Mid = math.floor(capsFull.Mid * 0.85),
			Scrub = math.floor(capsFull.Scrub * 0.85), Ground = math.floor(capsFull.Ground * 0.85),
			Rock = math.floor(capsFull.Rock * 0.85), Log = math.floor(capsFull.Log * 0.85),
		}
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

	-- candidate points: corridor cells are subdivided 2x2 (12-stud grid), far cells thin out with distance.
	-- Near points are visited first (shuffled) so the corridor claims its budget share; the far field
	-- (shuffled) then spreads the remaining 15% over the whole map.
	-- a rigid log rests on its highest support point. Sample the ground along its axis, return the tallest residual
-- above the end-to-end slope line (nil when the span leaves a visible gap underneath, i.e. a hollow). Ends-only
-- sampling buried logs that crossed a hump (mesh pivot is the bounding-box centre).
local function logRest(x: number, z: number, hx: number, hz: number, len: number, g1: number, g2: number): number?
	local tanP = (g1 - g2) / (len * 0.9)
	local support, lowest = -math.huge, math.huge
	for k = -4, 4 do
		local f = k / 4
		local gk = ground(x + hx * f, z + hz * f)
		if gk then
			local resid = (gk :: number) - (g1 + g2) * 0.5 - tanP * (f * len * 0.45)
			support = math.max(support, resid)
			lowest = math.min(lowest, resid)
		end
	end
	if support == -math.huge or support - lowest > 1.3 then
		return nil
	end
	return support
end
local rng = Random.new(seed + 977)
	local nearX, nearZ, nearS = {}, {}, {}
	local farX, farZ, farS = {}, {}, {}
	for cx = 0, n - 1 do
		for cz = 0, n - 1 do
			local bx = center.X - half + (cx + 0.5) * cell
			local bz = center.Z - half + (cz + 0.5) * cell
			if not hasCorridor then
				table.insert(farX, bx); table.insert(farZ, bz); table.insert(farS, cell)
			else
				local d = corridorDist(bx, bz)
				if d < (eco.denseR or 0) then
					-- inner play-space: 3x3 subdivision (8-stud grid) so no patch of ground reads as dead space
					for sx = -1, 1 do
						for sz = -1, 1 do
							table.insert(nearX, bx + sx * cell / 3); table.insert(nearZ, bz + sz * cell / 3); table.insert(nearS, cell / 3)
						end
					end
				elseif d < NEAR_R then
					for sx = -1, 1, 2 do
						for sz = -1, 1, 2 do
							table.insert(nearX, bx + sx * cell * 0.25); table.insert(nearZ, bz + sz * cell * 0.25); table.insert(nearS, cell * 0.5)
						end
					end
				else
					local w = math.max(FAR_W, 1 - (d - NEAR_R) / (FAR_R - NEAR_R) * (1 - FAR_W))
					if hash01(bx, bz, 43) < w then
						table.insert(farX, bx); table.insert(farZ, bz); table.insert(farS, cell)
					end
				end
			end
		end
	end
	local function shuffle3(a: { number }, b: { number }, c: { number })
		for i = #a, 2, -1 do
			local j = rng:NextInteger(1, i)
			a[i], a[j] = a[j], a[i]; b[i], b[j] = b[j], b[i]; c[i], c[j] = c[j], c[i]
		end
	end
	shuffle3(nearX, nearZ, nearS)
	shuffle3(farX, farZ, farS)
	local nearN = #nearX
	local px, pz, ps = nearX, nearZ, nearS
	for i = 1, #farX do
		table.insert(px, farX[i]); table.insert(pz, farZ[i]); table.insert(ps, farS[i])
	end
	local totalPts = #px

	for oi = 1, totalPts do
		do
			if hasCorridor and oi == nearN + 1 then caps = capsFull end
			local bx, bz, cs = px[oi], pz[oi], ps[oi]
			local x = bx + (hash01(bx, bz, 31) - 0.5) * cs * 0.8
			local z = bz + (hash01(bx, bz, 37) - 0.5) * cs * 0.8
			if hasCorridor then
				local cf = clearFactor(x, z)
				if cf < 1 and hash01(x, z, 47) > cf then continue end
			end
			local forestN = noise2(x, z, eco.forestScale, seed + 11) * 0.72 + noise2(x, z, eco.forestScale * 0.36, seed + 23) * 0.28
			local forest = sigmoid(forestN, eco.forestK)
			-- jungle is wall-to-wall: noise only modulates DENSITY, never opens bald regions (canopy count swung 5x by seed)
			forest = math.max(forest, eco.forestFloor or 0)
			if hash01(x, z, 41) > forest + eco.forestBase then
				continue
			end
			probes += 1
			local gy, normalY = ground(x, z)
			if not gy or not normalY then continue end
			local slope = 1 - normalY
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
			local under = eco.understory or 1
			local scrubP = slopeShrub * (0.25 + 0.45 * moist) * (1 - forest * 0.3) * under
			local groundP = slopeShrub * (0.2 + forest * 0.5) * under
			local rockP = (slopeRock * (1 - moist * 0.5) * 0.24 + (elev > tl and 0.3 or 0)) * (eco.rockBoost or 1)
			-- logs only on near-level ground (long bodies float or bury on slopes)
			local logP = if #sp.Log > 0 and slope < 0.12 then forest * math.exp(-((slope / 0.07) ^ 2)) * 0.12 else 0
			local total = treeP + midP + scrubP + groundP + rockP + logP
			if total <= 0 then continue end
			local roll = r * math.max(total, 1)

			local acc = treeP
			if roll < acc then
				local s = counts.Canopy < caps.Canopy and pick(sp.Canopy, x, z, 71)
				if s then
					placeMesh(folder, s :: Species, x, z, gy, height("Canopy", x, z, 61), 1, true, 71, colliderProto)
					counts.Canopy += 1
				end
			else
				acc += midP
				if roll < acc then
					local s = counts.Mid < caps.Mid and pick(sp.Mid, x, z, 73)
					if s then
						placeMesh(folder, s :: Species, x, z, gy, height("Mid", x, z, 63), tierOf(x, z, 5), true, 73, colliderProto)
						counts.Mid += 1
					end
				else
					acc += scrubP
					if roll < acc then
						if counts.Scrub < caps.Scrub then
							local s = pick(sp.Scrub, x, z, 79)
							local h = height("Scrub", x, z, 67)
							if s then
								placeMesh(folder, s, x, z, gy, h, tierOf(x, z, 7), false, 79, colliderProto)
							else
								mkPrim(folder, "Shrub", Vector3.new(h * 0.9, h * 0.55, h * 0.8),
									CFrame.new(x, gy + h * 0.25, z) * CFrame.Angles(0.05, hash01(x, z, 13) * 6.28, 0.07),
									eco.tint.shrub, Enum.Material.Grass, shrubProto)
							end
							counts.Scrub += 1
						end
					else
						acc += groundP
						if roll < acc then
							local s = counts.Ground < caps.Ground and pick(sp.Ground, x, z, 83)
							if s then
								placeMesh(folder, s :: Species, x, z, gy, height("Ground", x, z, 69), tierOf(x, z, 9), false, 83, colliderProto)
								counts.Ground += 1
							end
						elseif roll < acc + rockP then
							if counts.Rock < caps.Rock then
								local s = pick(sp.Rock, x, z, 89)
								local h = height("Rock", x, z, 71)
								if s then
									-- solid: the rock's own hull mesh collides (no trunk collider); sunk so slopes show no gap
									local rs = eco.rockScale
									local sc = if rs then rs[1] + (rs[2] - rs[1]) * hash01(x, z, 71) else h / s.height
									placeMesh(folder, s, x, z, gy, s.height * sc, 1, false, 89, colliderProto, { scale = sc, sink = 0.35 + s.height * sc * 0.12 })
								else
									mkPrim(folder, "Stone", Vector3.new(h * 0.9, h * 0.6, h * 0.7),
										CFrame.new(x, gy + h * 0.25, z) * CFrame.Angles(0.08, hash01(x, z, 17) * 6.28, 0.05),
										eco.tint.stone, Enum.Material.Slate, stoneProto)
								end
								counts.Rock += 1
							end
						elseif logRole and roll < acc + rockP + logP then
							if counts.Log < caps.Log then
								local s = pick(sp.Log, x, z, 97)
								if s then
									local len = logRole.minH + (logRole.maxH - logRole.minH) * hash01(x, z, 75)
									local yaw = hash01(x, z, 97) * math.pi * 2
									local hx, hz = math.cos(yaw) * len * 0.45, -math.sin(yaw) * len * 0.45
									local g1 = ground(x + hx, z + hz)
									local g2 = ground(x - hx, z - hz)
										local sup = if g1 and g2 and math.abs(g1 - g2) < len * 0.3 then logRest(x, z, hx, hz, len, g1, g2) else nil
									if g1 and g2 and sup then
										placeMesh(folder, s, x, z, (g1 + g2) * 0.5 + sup, 0, 1, false, 97, colliderProto,
											{ scale = len / s.length, yaw = yaw, pitch = math.atan2(g1 - g2, len * 0.9), sink = 0.3 })
										counts.Log += 1
									end
								end
							end
						end
					end
				end
			end
		end
		-- Boot-time generation owns the scheduler behind the loading screen. Keep only a
		-- small cooperative cadence (10x fewer frame losses than the old 400-cell cadence).
		if oi % 4000 == 0 then task.wait() end
	end

	-- Destroy transient archetypes before publishing the finished batch. Their production
	-- clones are independent copies; clearing the fields also keeps specCache metadata-only.
	for _, s in preparedSpecies do
		local proto = s.proto
		s.proto = nil
		if proto then proto:Destroy() end
	end
	colliderProto:Destroy()
	shrubProto:Destroy()
	stoneProto:Destroy()

	folder.Parent = Workspace
	workspace:SetAttribute("GF_VegCounts", string.format("c%d m%d s%d g%d r%d l%d", counts.Canopy, counts.Mid, counts.Scrub, counts.Ground, counts.Rock, counts.Log))
	print(string.format("VegetationService[%s]: canopy=%d mid=%d scrub=%d ground=%d rock=%d probes=%d species=%d/%d/%d/%d/%d in %.1fs",
		biomeName, counts.Canopy, counts.Mid, counts.Scrub, counts.Ground, counts.Rock, probes,
		#sp.Canopy, #sp.Mid, #sp.Scrub, #sp.Ground, #sp.Rock, os.clock() - t0))
	return folder
end

return VegetationService
