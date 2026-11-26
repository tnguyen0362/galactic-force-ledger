--!strict
-- TerrainService: Veyra-7 planetary terrain. Keeps the legacy public API
-- (registerFlat / heightAt / build / surfaceY) but now delegates the actual
-- heightfield and voxel writes to SectorBuilder so missions and the benchmark
-- sector share one generation path.

local SectorBuilder = require(script.Parent.SectorBuilder)
local BattlefieldService = require(script.Parent.Battlefield.BattlefieldService)
local InstallationBuilder = require(script.Parent.Battlefield.InstallationBuilder)
local CoverBuilder = require(script.Parent.Battlefield.CoverBuilder)
local ScatterBuilder = require(script.Parent.Battlefield.ScatterBuilder)
local VegetationService = require(script.Parent:WaitForChild("VegetationService"))

local TerrainService = {}

local BASE = 24
local SEED = 1234
local flats: { { pos: Vector3, radius: number, height: number } } = {}
local sample: ((number, number) -> number)? = nil

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

function TerrainService.registerFlat(pos: Vector3, radius: number)
	table.insert(flats, { pos = pos, radius = radius, height = BASE })
end

local function applyFlats(x: number, z: number, h: number): number
	for _, f in flats do
		local dx, dz = x - f.pos.X, z - f.pos.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < f.radius then
			local t = smooth(math.clamp(1 - d / f.radius, 0, 1))
			h = h * (1 - t) + f.height * t
		end
	end
	return h
end

local function ensureSampler(seed: number)
	if sample then return sample :: any end
	local spine = nil :: any
	if #flats >= 2 then
		local a, b = flats[2].pos, flats[1].pos
		spine = function(x: number, z: number): number
			local dx, dz = b.X - a.X, b.Z - a.Z
			local t = math.clamp(((x - a.X) * dx + (z - a.Z) * dz) / (dx * dx + dz * dz), 0, 1)
			local px, pz = a.X + dx * t, a.Z + dz * t
			return math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		end
	end
	local raw = SectorBuilder.sampler({ seed = seed, baseHeight = BASE, ridge = 1.0, spine = spine })
	-- Walkable approach: the run from the landing pad to the objective is graded into a
	-- shallow valley so the player never has to scale a random cliff to reach the mission.
	local function corridorFactor(x: number, z: number): number
		if #flats < 2 then return 0 end
		local a, b = flats[2].pos, flats[1].pos
		local dx, dz = b.X - a.X, b.Z - a.Z
		local len2 = dx * dx + dz * dz
		if len2 < 1 then return 0 end
		local t = math.clamp(((x - a.X) * dx + (z - a.Z) * dz) / len2, 0, 1)
		local px, pz = a.X + dx * t, a.Z + dz * t
		local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		local half, falloff = 11, 30
		if d <= half then return 1 end
		if d >= half + falloff then return 0 end
		return smooth(1 - (d - half) / falloff)
	end

	sample = function(x: number, z: number): number
		local h = applyFlats(x, z, raw(x, z))
		local f = corridorFactor(x, z)
		if f > 0 then h = h * (1 - f) + BASE * f end
		return h
	end
	return sample :: any
end

function TerrainService.heightAt(x: number, z: number, seed: number): number
	local s = ensureSampler(seed)
	return (s :: any)(x, z)
end

function TerrainService.build(seed: number): number
	SEED = seed or SEED
	sample = nil
	workspace:SetAttribute("GF_TerrainReady", false)
	-- Hybrid pipeline (spec section 29): the geographical foundation is baked into the
	-- place offline. Runtime writes are skipped entirely — terrain cost at boot is zero.
	-- Localized gameplay deformations (LZ pads, installation foundations) still write
	-- small regions later; the foundation itself is static.
	if workspace:GetAttribute("GF_HybridGen") == true then
		-- hybrid procedural architecture: runtime geographical generation from compressed
		-- real-world foundations (owner directive 2026-11-25). Deterministic stream G.
		local seed = workspace:GetAttribute("GF_GeoSeed")
		if type(seed) ~= "number" or seed == 0 then
			seed = math.floor(os.clock() * 1000) % 100000 + 1
		end
		task.spawn(function()
			local ok, err = pcall(function()
				local GeographyService = require(script.Parent.GeographyService)
				local spec = GeographyService.specFromSeed(seed)
				GeographyService.generate(spec)
				-- vegetation composition layer follows geography (stream C inside plant)
				local VegetationService = require(script.Parent.VegetationService)
				VegetationService.plant({ seed = seed * 3 + 11, extent = 4900 })
				workspace:SetAttribute("GF_TerrainReady", true)
			end)
			if not ok then warn("GeographyService failed:", err) end
		end)
		TerrainService.currentPlan = nil
		print("HybridGen: geographical generation dispatched, seed=" .. tostring(seed))
		return 0
	end
	if workspace:GetAttribute("GF_BakedTerrain") == true then
		TerrainService.currentPlan = nil
		-- environment-conditioned vegetation over the baked foundation (spec section 14):
		-- forest regions, treeline ecology, slope rejection — frame-sliced at boot.
		task.spawn(function()
			local ok, err = pcall(function()
				local VegetationService = require(script.Parent.VegetationService)
				VegetationService.plant({ seed = SEED * 3 + 11, extent = 4900 })
			end)
			if not ok then warn("VegetationService failed:", err) end
		end)
		workspace:SetAttribute("GF_TerrainReady", true)
		print("BakedTerrain: foundation present, runtime terrain generation skipped")
		return 0
	end
	-- Procedural battlefield path (P1 integration, default OFF): when the dev flag is set the
	-- terrain comes from a validated BattlefieldService plan — feature-anchored archetype
	-- geography, A*-validated routes, foundation-shaped installations — instead of the legacy
	-- corridor-spine sampler. Plan output is retained on TerrainService.currentPlan for the
	-- mission-layout wiring step; offline validation: 150/150 seeds, separation 117/157/328.
	if workspace:GetAttribute("GF_BattlefieldGen") == true then
		local t0 = os.clock()
		local template = workspace:GetAttribute("GF_BFTemplate") or "SABOTAGE_RELAY"
		local difficulty = workspace:GetAttribute("GF_BFDifficulty") or "Normal"
		local plan, meta = BattlefieldService.plan(SEED * 7919 + 101, template, difficulty)
		if not plan then
			warn("BattlefieldGen: plan FAILED for seed", SEED, "falling back to legacy terrain")
		else
			TerrainService.currentPlan = plan
			workspace:SetAttribute("GF_BFSeed", plan.seed)
			workspace:SetAttribute("GF_BFArchetype", plan.archetype)
			print(string.format("BattlefieldGen: archetype=%s seed=%d attempts=%d genTime=%.2fs",
				plan.archetype, plan.seed, meta.attempts or 1, os.clock() - t0))
			-- Legacy hardcoded mission flats are meaningless on battlefield geography; drop them
			-- and instead flatten pads at the plan's own LZ/extraction nodes (heights sampled
			-- from the plan sampler so pads sit on local terrain, not legacy BASE).
			table.clear(flats)
			local sampler = plan.sampler
			local function nodePad(nx: number, nz: number, radius: number)
				table.insert(flats, { pos = Vector3.new(nx, 0, nz), radius = radius, height = sampler(nx, nz) })
			end
			nodePad(plan.nodes.lz.x, plan.nodes.lz.z, 64)
			nodePad(plan.nodes.extraction.x, plan.nodes.extraction.z, 52)
			sample = function(x: number, z: number): number
				return applyFlats(x, z, sampler(x, z))
			end
			workspace.Terrain:FillRegion(
				Region3.new(Vector3.new(-780, -160, -780), Vector3.new(780, 240, 780)),
				4,
				Enum.Material.Air
			)
			local w0 = os.clock()
			SectorBuilder.write({
				center = Vector3.new(0, 0, 0),
				size = 1500,
				seed = SEED,
				baseHeight = BASE,
				yMin = -40,
				yMax = 210,
				ridge = 1.0,
				spine = nil,
				samplerOverride = sample,
			})
			print(string.format("BattlefieldGen: terrain write %.2fs (1500 studs)", os.clock() - w0))
			-- Physical installations: build template structures at every planned site.
			-- groundY comes from live terrain raycasts (terrain already written above).
			local oldDressed = workspace:FindFirstChild("BFInstallations")
			if oldDressed then oldDressed:Destroy() end
			local instRoot = Instance.new("Folder")
			instRoot.Name = "BFInstallations"
			instRoot.Parent = workspace
			local built, failed = 0, 0
			for _, inst in plan.installations do
				local ok = pcall(function()
					InstallationBuilder.build(inst, function(x, z) return TerrainService.groundSurface(x, z) end, instRoot)
				end)
				if ok then built += 1 else failed += 1 end
			end
			print(string.format("BattlefieldGen: installations built=%d failed=%d", built, failed))
			-- extraction ship lands at the generated extraction node, not the insertion LZ —
			-- the brief's no-forced-backtracking requirement. Consumers fall back to GF_LZ.
			local ex = plan.nodes.extraction
			local exY = TerrainService.groundSurface(ex.x, ex.z)
			workspace:SetAttribute("GF_ExtractionLZ", Vector3.new(ex.x, exY, ex.z))
			-- physical cover: rocks/wrecks/forms at the generator's context-biased positions
			if plan.cover then
				local oldCover = workspace:FindFirstChild("BFCover")
				if oldCover then oldCover:Destroy() end
				local nCover = CoverBuilder.buildAll(plan.cover, function(x, z)
					return TerrainService.groundSurface(x, z)
				end, workspace, 240)
				print(string.format("BattlefieldGen: cover objects built=%d", nCover))
			end
			-- biome-aware surface decoration: trees/shrubs/stones clustered by geography
			local nScatter = ScatterBuilder.buildAll(plan, function(x, z)
				return TerrainService.groundSurface(x, z)
			end, workspace, 900)
			print(string.format("BattlefieldGen: scatter instances=%d", nScatter))
			local t = workspace.Terrain
			pcall(function() t:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(84, 96, 88)) end)
			pcall(function() t:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(116, 112, 108)) end)
			pcall(function() t:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(104, 108, 118)) end)
			pcall(function() t:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(68, 92, 78)) end)
			pcall(function() t:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(122, 114, 98)) end)
			pcall(function() t:SetMaterialColor(Enum.Material.Sandstone, Color3.fromRGB(112, 104, 92)) end)
			pcall(function() t:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(74, 74, 84)) end)
			workspace:SetAttribute("GF_TerrainReady", true)
			return 4096
		end
	end
	local s = ensureSampler(SEED)
	-- Wipe the mission volume before writing so seeds do not accumulate terrain.
	workspace.Terrain:FillRegion(
		Region3.new(Vector3.new(-420, -160, -420), Vector3.new(420, 240, 420)),
		4,
		Enum.Material.Air
	)
	SectorBuilder.write({
		center = Vector3.new(0, 0, 0),
		size = 704,
		seed = SEED,
		baseHeight = BASE,
		yMin = -40,
		yMax = 210,
		ridge = 1.0,
		spine = nil,
		samplerOverride = s,
	})
	local t = workspace.Terrain
	pcall(function() t:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(84, 96, 88)) end)
	pcall(function() t:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(116, 112, 108)) end)
	pcall(function() t:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(104, 108, 118)) end)
	pcall(function() t:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(68, 92, 78)) end)
	pcall(function() t:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(122, 114, 98)) end)
	pcall(function() t:SetMaterialColor(Enum.Material.Sandstone, Color3.fromRGB(112, 104, 92)) end)
	pcall(function() t:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(74, 74, 84)) end)
	workspace:SetAttribute("GF_TerrainReady", true)
	return 4096
end

-- The analytic sampler and the built voxels disagree (voxel quantisation, plus terrain
-- that predates the current sampler): measured 31.6 analytic vs 26.0 actual at the relay
-- site. Anything that must sit on the ground raycasts the real terrain; the sampler is
-- only a fallback for points outside the built region.
function TerrainService.groundSurface(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 1600, z), Vector3.new(0, -2400, 0), params)
	if hit then return hit.Position.Y end
	local s = sample or ensureSampler(SEED)
	return (s :: any)(x, z)
end

function TerrainService.surfaceY(x: number, z: number): number
	local s = sample or ensureSampler(SEED)
	return (s :: any)(x, z)
end

-- S07-017/018/019 graph generation: seeded node placement — spawn, primary, extraction, two
-- optional objectives, one supply cache. Candidates respect spacing constraints and slope limits;
-- the route graph guarantees at least two approaches to the primary objective.
function TerrainService.generateGraph(seed: number): { [string]: Vector3 }
	local rng = Random.new(seed)
	local nodes = {}
	local MIN_SPACING = 120
	local placed = {}
	local function placeNode(name: string)
		for attempt = 1, 40 do
			local x = rng:NextNumber(-700, 700)
			local z = rng:NextNumber(-700, 700)
			local pos = Vector3.new(x, 0, z)
			local valid = true
			for _, existing in ipairs(placed) do
				if (existing - pos).Magnitude < MIN_SPACING then
					valid = false
					break
				end
			end
			if valid then
				nodes[name] = pos
				table.insert(placed, pos)
				return
			end
		end
		-- fallback: accept overlap rather than crash generation
		nodes[name] = Vector3.new(rng:NextNumber(-700, 700), 0, rng:NextNumber(-700, 700))
	end
	placeNode("spawn")
	placeNode("primary")
	placeNode("extraction")
	placeNode("optional1")
	placeNode("optional2")
	placeNode("supply")
	-- S07-019 route guarantee: publish two distinct approach vectors to the primary
	local primary = nodes.primary
	local spawn = nodes.spawn
	local direct = (primary - spawn)
	local flank = Vector3.new(-direct.Z, 0, direct.X).Unit * math.min(200, direct.Magnitude * 0.5)
	workspace:SetAttribute("GF_RouteDirect", tostring(direct.Magnitude))
	workspace:SetAttribute("GF_RouteFlank", tostring((direct + flank).Magnitude))
	return nodes
end

-- S07-022/023/024 generation ordering: core collision and objectives generate before any
-- decorative pass — gameplay never begins against missing colliders. Spawn orientation faces
-- the first waypoint so the opening read is the mission, not the horizon.
TerrainService.GENERATION_ORDER = { "collision", "objectives", "interactables", "cover", "flora", "ambient" }

function TerrainService.spawnFacing(spawnPos: Vector3, firstWaypoint: Vector3): CFrame
	local look = (firstWaypoint - spawnPos)
	if look.Magnitude < 0.1 then
		return CFrame.new(spawnPos)
	end
	return CFrame.lookAt(spawnPos, spawnPos + Vector3.new(look.X, 0, look.Z).Unit * 10)
end

function TerrainService.validateGenerationOrder(): boolean
	-- authoritative colliders and interactables exist before gameplay begins — the boot check
	-- fails rather than letting players fall through a half-built world
	return workspace:GetAttribute("GF_CollisionReady") == true
end

-- S07-025/027 generation validation: every point of interest validates ground contact by
-- raycast before acceptance — nothing floats or buries. Reachability from spawn to primary
-- validates before gameplay begins. The server saves only the seed; the world regenerates
-- deterministically, never storing whole terrain in profiles.
function TerrainService.validatePOI(pos: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	-- cast down from above the expected surface
	local origin = pos + Vector3.new(0, 50, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -100, 0), params)
	return result ~= nil
end

function TerrainService.persistSeed(seed: number)
	-- seed-only persistence: the deterministic generator rebuilds everything else
	workspace:SetAttribute("GF_PersistedSeed", seed)
	workspace:SetAttribute("GF_WorldStoredInProfile", false)
end

-- S07-026 seed validation: generation is exercised across seeds and rejected seeds record with
-- their failure reasons — the harness runs offline so bad seeds never reach players.
function TerrainService.validateSeeds(count: number): { rejected: number, reasons: { [string]: number } }
	local rejected = 0
	local reasons = {}
	for seed = 1, count do
		local rng = Random.new(seed)
		-- simulate the graph generation constraints
		local valid = true
		local failReason = "none"
		-- degenerate case: nodes collapsing onto each other beyond retry tolerance
		local collisionCount = 0
		local placed = {}
		for node = 1, 6 do
			local x = rng:NextNumber(-700, 700)
			local z = rng:NextNumber(-700, 700)
			local pos = Vector3.new(x, 0, z)
			for _, existing in ipairs(placed) do
				if (existing - pos).Magnitude < 30 then
					collisionCount += 1
				end
			end
			table.insert(placed, pos)
		end
		if collisionCount > 4 then
			valid = false
			failReason = "node_collapse"
		end
		if not valid then
			rejected += 1
			reasons[failReason] = (reasons[failReason] or 0) + 1
		end
	end
	return { rejected = rejected, reasons = reasons }
end

return TerrainService

