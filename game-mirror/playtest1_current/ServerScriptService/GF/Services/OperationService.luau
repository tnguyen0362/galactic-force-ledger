--!strict
-- OperationService: authoritative operation generation and runtime — layer 3 of the
-- hybrid architecture (geography / composition / operation, owner directive 2026-11-26).
--
-- The operation layer ORCHESTRATES existing systems through their interfaces:
--   GeographyService — terrain foundation + terrain analysis (placement candidates)
--   MissionSites     — physical site construction (stronghold, prereqs, optionals)
--   EncounterDirector — garrisons, patrols, reinforcement economy
--   ExtractionService — voting, transport, defense (unchanged)
--   ObjectiveService mechanics patterns — reused, not extended (singleton stays legacy)
--
-- Core concepts (directive sections 8-10):
--   * OperationDefinition: versioned seed-reproducible manifest
--   * Objective dependency DAG with topological validation
--   * explicit states Locked/Available/Active/Completed/Failed, server-authoritative
--   * idempotent event processing (ProcessedEvents guard)
--   * consequence events: ReinforcementPermissionChanged, DefensiveSystemDisabled,
--     PrimaryObjectiveUnlocked — no arbitrary mutation of enemy internals

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local OperationService = {}

local GENERATOR_VERSION = "op-1.0"

-- ============ types ============

export type ObjectiveNode = {
	id: string,
	mechanic: string,          -- capture | destroy | disable | recover | defend | eliminate | locate | restore
	siteType: string,          -- MissionSites constructor key
	position: Vector3,
	requires: { string }?,     -- objective ids that must complete first (AND)
	requiresAny: { { string } }?, -- alternative prerequisite sets (OR of ANDs)
	optional: boolean?,
	state: string,             -- Locked | Available | Active | Completed | Failed
	progress: number,
	site: Model?,
	consequences: { string }?, -- event names fired on completion
	label: string,
}

export type OperationDefinition = {
	operationId: string,
	operationSeed: number,
	generatorVersion: string,
	geographyId: string,
	missionFamily: string,
	missionVariant: string,
	difficulty: string,
	deploymentRegion: Vector3,
	primaryObjective: string,
	objectives: { ObjectiveNode },
	extractionRegion: Vector3,
	missionTimeLimit: number,
	circumstance: string,
}

-- ============ module state ============

local current: OperationDefinition? = nil
local processedEvents: { [string]: boolean } = {}
local listeners: { RBXScriptConnection } = {}
local rng: Random? = nil

-- dependency-injected services (bound at init to avoid require cycles)
local Services: any = {}

function OperationService.bind(svcs: any)
	Services = svcs
end

-- ============ DAG utilities ============

local function requiresMet(node: ObjectiveNode, byId: { [string]: ObjectiveNode }): boolean
	if node.requiresAny then
		for _, set in node.requiresAny do
			local all = true
			for _, req in set do
				local r = byId[req]
				if not r or r.state ~= "Completed" then all = false break end
			end
			if all then return true end
		end
		return false
	end
	if node.requires then
		for _, req in node.requires do
			local r = byId[req]
			if not r or r.state ~= "Completed" then return false end
		end
	end
	return true
end

-- topological validation: no cycles, all prerequisites exist
function OperationService.validateGraph(nodes: { ObjectiveNode }): (boolean, string?)
	local byId: { [string]: ObjectiveNode } = {}
	for _, n in nodes do
		if byId[n.id] then return false, "duplicate objective id " .. n.id end
		byId[n.id] = n
	end
	for _, n in nodes do
		local reqs = n.requires or {}
		if n.requiresAny then
			for _, set in n.requiresAny do
				for _, r in set do table.insert(reqs, r) end
			end
		end
		for _, r in reqs do
			if not byId[r] then return false, n.id .. " requires missing " .. r end
		end
	end
	-- cycle detection via iterative deepening walk
	for _, n in nodes do
		local seen = {}
		local stack = { n }
		local guard = 0
		while #stack > 0 do
			guard += 1
			if guard > 64 then return false, "dependency cycle involving " .. n.id end
			local cur = table.remove(stack)
			if cur then
				if seen[cur.id] then return false, "dependency cycle involving " .. n.id end
				seen[cur.id] = true
				for _, r in (cur.requires or {}) do
					local rn = byId[r]
					if rn then table.insert(stack, rn) end
				end
			end
		end
	end
	return true, nil
end

-- ============ operation generation ============

-- reference operation: Conquest - Stronghold (directive section 45). deployment ~1km
-- from primary; 1-2 logically-connected prerequisites; optional installation; extraction
-- positioned to avoid full-map backtracking.
local function generateConquestStronghold(seed: number, difficulty: string, analysis: any, geographyId: string): OperationDefinition?
	local stream = Random.new(seed * 31337 + 7)

	-- 1. deployment region: flat valley/lowland near one edge of the map
	local edge = stream:NextInteger(1, 4) -- 1:S 2:N 3:E 4:W
	local deployTargetX, deployTargetZ = 0, 1900
	if edge == 2 then deployTargetX, deployTargetZ = 0, -1900
	elseif edge == 3 then deployTargetX, deployTargetZ = 1900, 0
	elseif edge == 4 then deployTargetX, deployTargetZ = -1900, 0 end
	-- small rotational jitter so edge choice isn't exact
	deployTargetX += stream:NextInteger(-400, 400)
	deployTargetZ += stream:NextInteger(-400, 400)

	local TerrainAnalysis = require(script.Parent.TerrainAnalysis)
	local deploySite = TerrainAnalysis.nearest(analysis.valleyFloor, deployTargetX, deployTargetZ, nil, 900)
		or TerrainAnalysis.nearest(analysis.sites, deployTargetX, deployTargetZ, nil, 1200)
	if not deploySite then return nil end
	local deployment = Vector3.new(deploySite.x, deploySite.y, deploySite.z)

	-- 2. primary stronghold: large flat site 800-1200m (2860-4290 studs) from deployment
	--    the directive's reference is ~1km; the 5000-stud map constrains placement.
	local bestPrimary: any = nil
	local bestScore = -math.huge
	for _, s in analysis.sites do
		local dx, dz = s.x - deploySite.x, s.z - deploySite.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d >= 2600 and d <= 4200 then
			-- prefer highland/lowland stronghold positions (tactical elevation), big flatness
			local score = s.score + (s.region == "highland" and 0.5 or 0) + (s.region == "lowland" and 0.3 or 0)
			if score > bestScore then
				bestScore = score
				bestPrimary = s
			end
		end
	end
	if not bestPrimary then
		-- relax: accept 2200-4400 if the map geometry demands
		for _, s in analysis.sites do
			local dx, dz = s.x - deploySite.x, s.z - deploySite.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d >= 2200 and d <= 4400 and s.score > bestScore then
				bestScore = s.score
				bestPrimary = s
			end
		end
	end
	if not bestPrimary then return nil end
	local primaryPos = Vector3.new(bestPrimary.x, bestPrimary.y, bestPrimary.z)

	-- 3. prerequisite sites: mid-route between deployment and primary, separated from
	--    each other. shield generator + comms relay (the classic fortified configuration).
	local midX = (deploySite.x + bestPrimary.x) / 2
	local midZ = (deploySite.z + bestPrimary.z) / 2
	-- offset perpendicular so the route isn't a straight line
	local dx, dz = bestPrimary.x - deploySite.x, bestPrimary.z - deploySite.z
	local len = math.sqrt(dx * dx + dz * dz)
	local px, pz = -dz / len, dx / len
	local off1 = stream:NextInteger(400, 700)
	local off2 = -stream:NextInteger(400, 700)
	local shieldSite = TerrainAnalysis.nearest(analysis.sites, midX + px * off1, midZ + pz * off1, nil, 800)
	local commsSite = TerrainAnalysis.nearest(analysis.sites, midX + px * off2, midZ + pz * off2, nil, 800)

	-- 4. optional supply cache: off-axis, roughly 60% along the route
	local optX = deploySite.x + dx * 0.6 + px * stream:NextInteger(-900, 900)
	local optZ = deploySite.z + dz * 0.6 + pz * stream:NextInteger(-900, 900)
	local supplySite = TerrainAnalysis.nearest(analysis.sites, optX, optZ, nil, 700)

	-- 5. extraction region: flat, 300-700 studs from primary, off the deployment axis
	local extX = bestPrimary.x + px * (stream:NextInteger(0, 1) * 2 - 1) * 500
	local extZ = bestPrimary.z + pz * (stream:NextInteger(0, 1) * 2 - 1) * 500
	local extSite = TerrainAnalysis.nearest(analysis.valleyFloor, extX, extZ, nil, 800)
		or TerrainAnalysis.nearest(analysis.sites, extX, extZ, nil, 900)

	if not (shieldSite and commsSite and extSite) then return nil end

	local circumstance = "fortified"

	local objectives: { ObjectiveNode } = {
		{
			id = "disable_shield",
			mechanic = "destroy",
			siteType = "shield_generator",
			position = Vector3.new(shieldSite.x, shieldSite.y, shieldSite.z),
			state = "Available",
			progress = 0,
			consequences = { "DefensiveSystemDisabled" },
			label = "Destroy the shield generator",
		},
		{
			id = "disable_comms",
			mechanic = "disable",
			siteType = "comms_relay",
			position = Vector3.new(commsSite.x, commsSite.y, commsSite.z),
			state = "Available",
			progress = 0,
			consequences = { "ReinforcementPermissionChanged" },
			label = "Disable the comms relay",
		},
		{
			id = "capture_stronghold",
			mechanic = "capture",
			siteType = "stronghold",
			position = primaryPos,
			requires = { "disable_shield" },
			state = "Locked",
			progress = 0,
			consequences = { "InstallationCaptured", "PrimaryObjectiveUnlocked" },
			label = "Capture the stronghold",
		},
	}
	if supplySite then
		table.insert(objectives, {
			id = "supply_cache",
			mechanic = "recover",
			siteType = "supply_cache",
			position = Vector3.new(supplySite.x, supplySite.y, supplySite.z),
			state = "Available",
			progress = 0,
			optional = true,
			label = "Secure the supply cache",
		})
	end

	return {
		operationId = string.format("OP-%d", seed),
		operationSeed = seed,
		generatorVersion = GENERATOR_VERSION,
		geographyId = geographyId,
		missionFamily = "Conquest",
		missionVariant = "Stronghold",
		difficulty = difficulty,
		deploymentRegion = deployment,
		primaryObjective = "capture_stronghold",
		objectives = objectives,
		extractionRegion = Vector3.new(extSite.x, extSite.y, extSite.z),
		missionTimeLimit = 1500,
		circumstance = circumstance,
	}
end

-- ============ objective runtime ============

local function byId(def: OperationDefinition): { [string]: ObjectiveNode }
	local t = {}
	for _, n in def.objectives do t[n.id] = n end
	return t
end

local function fireConsequence(eventName: string, node: ObjectiveNode)
	if eventName == "ReinforcementPermissionChanged" then
		Workspace:SetAttribute("GF_ReinforcementCut", 0.45)
	elseif eventName == "DefensiveSystemDisabled" then
		Workspace:SetAttribute("GF_StrongholdShieldDown", true)
	elseif eventName == "InstallationCaptured" then
		Workspace:SetAttribute("GF_StrongholdCaptured", true)
	end
end

function OperationService.completeObjective(id: string, source: string)
	if not current then return end
	local eventId = id .. ":" .. current.operationId
	if processedEvents[eventId] then return end
	local ids = byId(current)
	local node = ids[id]
	if not node or node.state == "Completed" then return end
	if node.state == "Locked" then return end
	processedEvents[eventId] = true
	node.state = "Completed"
	node.progress = 1
	Workspace:SetAttribute("GF_OpEvent_" .. id, "Completed")
	if node.consequences then
		for _, c in node.consequences do
			fireConsequence(c, node)
		end
	end
	for _, n in current.objectives do
		if n.state == "Locked" and requiresMet(n, ids) then
			n.state = "Available"
			Workspace:SetAttribute("GF_OpEvent_" .. n.id, "Available")
		end
	end
	if id == current.primaryObjective then
		if Services.ObjectiveService and Services.ObjectiveService.complete then
			pcall(function() Services.ObjectiveService.complete() end)
		else
			Workspace:SetAttribute("GF_ObjectiveComplete", true)
		end
	end
	OperationService.publishState()
end

function OperationService.interact(player: Player, targetString: string)
	if not current then return end
	local ids = byId(current)
	for _, node in current.objectives do
		if node.state == "Completed" or node.state == "Locked" then continue end
		local site = node.site
		if not site then continue end
		for _, d in site:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("GFInteract") == targetString then
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if not root then return end
				if (root.Position - d.Position).Magnitude > 14 then return end
				node.state = "Active"
				if node.mechanic == "capture" then
					if not requiresMet(node, ids) then
						Workspace:SetAttribute("GF_OpHint", "The stronghold shield is still active")
						return
					end
					OperationService.completeObjective(node.id, "interact")
				elseif node.mechanic == "disable" or node.mechanic == "recover" then
					OperationService.completeObjective(node.id, "interact")
				end
				return
			end
		end
	end
end

function OperationService.structureDestroyed(part: BasePart)
	if not current then return end
	for _, node in current.objectives do
		if node.mechanic ~= "destroy" or node.state == "Completed" then continue end
		local site = node.site
		if not site then continue end
		if part:IsDescendantOf(site) then
			OperationService.completeObjective(node.id, "destruction")
			return
		end
	end
end

-- ============ activation ============

function OperationService.activate(def: OperationDefinition): boolean
	local valid, err = OperationService.validateGraph(def.objectives)
	if not valid then
		warn("OperationService: invalid graph:", err)
		return false
	end
	current = def
	processedEvents = {}
	rng = Random.new(def.operationSeed * 17 + 3)

	local MissionSites = require(script.Parent.MissionSites)
	local sitesFolder = Workspace:FindFirstChild("OperationSites")
	if sitesFolder then sitesFolder:Destroy() end
	sitesFolder = Instance.new("Folder")
	sitesFolder.Name = "OperationSites"
	sitesFolder.Parent = Workspace

	for _, node in def.objectives do
		local site = MissionSites.build(node.siteType, node.position, { parent = sitesFolder })
		node.site = site
	end

	MissionSites.build("extraction_pad", def.extractionRegion, { parent = sitesFolder })

	-- destruction wiring: destroy-mechanic objectives complete when their GFStructure part is
	-- destroyed by the shared combat pipeline (listens instead of polling, no CombatService edits)
	for _, node in def.objectives do
		if node.mechanic == "destroy" and node.site then
			for _, d in node.site:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("GFStructure") == true then
					local conn
					conn = d:GetAttributeChangedSignal("GFDestroyed"):Connect(function()
						if d:GetAttribute("GFDestroyed") == true then
							if conn then conn:Disconnect() end
							OperationService.structureDestroyed(d)
						end
					end)
				end
			end
		end
	end

	Workspace:SetAttribute("GF_ExtractionLZ", def.extractionRegion)
	Workspace:SetAttribute("GF_OperationLZ", def.deploymentRegion)
	Workspace:SetAttribute("GF_OperationId", def.operationId)

	if Services.EncounterDirector then
		for _, node in def.objectives do
			if node.optional then continue end
			local count = node.siteType == "stronghold" and 5 or 3
			task.delay(2, function()
				pcall(function()
					Services.EncounterDirector.spawnAround(node.position + Vector3.new(0, 4, 0), 24, count)
				end)
			end)
		end
	end

	OperationService.publishState()
	print(string.format("OperationService: %s activated — %d objectives",
		def.operationId, #def.objectives))
	return true
end

function OperationService.generate(seed: number, variant: string, difficulty: string): OperationDefinition?
	local GeographyService = require(script.Parent.GeographyService)
	local analysis = GeographyService.analysis
	if not analysis or #analysis.sites < 8 then
		warn("OperationService: terrain analysis not ready")
		return nil
	end
	local geographyId = tostring(Workspace:GetAttribute("GF_GeoFoundation") or "unknown")
	return generateConquestStronghold(seed, difficulty, analysis, geographyId)
end

function OperationService.publishState()
	if not current then return end
	local parts = {}
	for _, n in current.objectives do
		table.insert(parts, string.format("%s:%s", n.id, n.state))
	end
	Workspace:SetAttribute("GF_OperationState", table.concat(parts, ";"))
end

function OperationService.current(): OperationDefinition?
	return current
end

-- boot wiring: interaction fan-out for operation-owned target strings. The legacy
-- ObjectiveService whitelist deliberately untouched — operation sites register their own listener.
local OP_TARGETS = {
	CaptureConsole = true,
	CommsRelay = true,
	SupplyCache = true,
}

function OperationService.start()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
	local interact = remotes:WaitForChild("InteractRequest")
	interact.OnServerEvent:Connect(function(player, targetString)
		if type(targetString) ~= "string" or not OP_TARGETS[targetString] then return end
		if not current then return end
		OperationService.interact(player, targetString)
	end)
	-- services bound for garrison spawns + completion handoff
	pcall(function()
		OperationService.bind({
			EncounterDirector = require(script.Parent.EncounterDirector),
			ObjectiveService = require(script.Parent.ObjectiveService),
		})
	end)
end

function OperationService.reset()
	current = nil
	processedEvents = {}
	local sitesFolder = Workspace:FindFirstChild("OperationSites")
	if sitesFolder then sitesFolder:Destroy() end
end

return OperationService
