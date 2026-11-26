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
	-- collect prerequisite ids without mutating node tables
	local function reqsOf(n: ObjectiveNode): { string }
		local out = {}
		for _, r in (n.requires or {}) do table.insert(out, r) end
		if n.requiresAny then
			for _, set in n.requiresAny do
				for _, r in set do table.insert(out, r) end
			end
		end
		return out
	end
	for _, n in nodes do
		for _, r in reqsOf(n) do
			if not byId[r] then return false, n.id .. " requires missing " .. r end
		end
	end
	-- cycle detection: iterative DFS with white/gray/black coloring. Gray-on-revisit = cycle.
	-- Diamond dependencies (shared prerequisites) must NOT false-positive: black nodes are safe.
	local color: { [string]: string } = {}
	for _, n in nodes do color[n.id] = "white" end
	for _, start in nodes do
		if color[start.id] ~= "white" then continue end
		-- stack entries: {node, childIndex}; gray while on stack
		local stack: { { node: ObjectiveNode, next: number } } = { { node = start, next = 1 } }
		color[start.id] = "gray"
		local guard = 0
		while #stack > 0 do
			guard += 1
			if guard > 4096 then return false, "dependency graph too deep to validate" end
			local top = stack[#stack]
			local reqs = reqsOf(top.node)
			if top.next > #reqs then
				color[top.node.id] = "black"
				table.remove(stack)
				continue
			end
			local childId = reqs[top.next]
			top.next += 1
			local child = byId[childId]
			if not child then continue end
			if color[childId] == "gray" then
				return false, "dependency cycle involving " .. childId
			elseif color[childId] == "white" then
				color[childId] = "gray"
				table.insert(stack, { node = child, next = 1 })
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
		or TerrainAnalysis.nearest(analysis.valleyFloor, deployTargetX, deployTargetZ, nil, 1600)
		or TerrainAnalysis.nearest(analysis.sites, deployTargetX, deployTargetZ, nil, 1600)
		or TerrainAnalysis.nearest(analysis.sites, deployTargetX, deployTargetZ)
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
	if not bestPrimary then
		-- final fallback: maximize separation — the farthest flat site from deployment.
		-- operation generation must degrade gracefully, never fail on geography alone.
		local farD = 0
		for _, s in analysis.sites do
			local dx, dz = s.x - deploySite.x, s.z - deploySite.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > farD then
				farD = d
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
		or TerrainAnalysis.nearest(analysis.sites, midX + px * off1, midZ + pz * off1)
	local commsSite = TerrainAnalysis.nearest(analysis.sites, midX + px * off2, midZ + pz * off2, nil, 800)
		or TerrainAnalysis.nearest(analysis.sites, midX + px * off2, midZ + pz * off2)
	-- separation enforcement: sparse candidate fields can collapse both prereqs onto the same
	-- flat spot. If too close, search the comms side excluding the shield neighborhood.
	if shieldSite and commsSite then
		local sdx, sdz = shieldSite.x - commsSite.x, shieldSite.z - commsSite.z
		if math.sqrt(sdx * sdx + sdz * sdz) < 350 then
			-- repair: nearest site to the comms target that clears the shield separation,
			-- unconstrained by the original radius — sparse geography must not collapse the pair.
			local alt = nil
			local bestD = math.huge
			for _, s in analysis.sites do
				local dx2, dz2 = s.x - (midX + px * off2), s.z - (midZ + pz * off2)
				local d = math.sqrt(dx2 * dx2 + dz2 * dz2)
				local fx, fz = s.x - shieldSite.x, s.z - shieldSite.z
				if d < bestD and math.sqrt(fx * fx + fz * fz) >= 350 then
					bestD = d
					alt = s
				end
			end
			if alt then commsSite = alt end
		end
	end

	-- 4. optional supply cache: off-axis, roughly 60% along the route
	local optX = deploySite.x + dx * 0.6 + px * stream:NextInteger(-900, 900)
	local optZ = deploySite.z + dz * 0.6 + pz * stream:NextInteger(-900, 900)
	local supplySite = TerrainAnalysis.nearest(analysis.sites, optX, optZ, nil, 700)
		or TerrainAnalysis.nearest(analysis.sites, optX, optZ)

	-- 5. extraction region: flat, 300-700 studs from primary, off the deployment axis
	local extX = bestPrimary.x + px * (stream:NextInteger(0, 1) * 2 - 1) * 500
	local extZ = bestPrimary.z + pz * (stream:NextInteger(0, 1) * 2 - 1) * 500
	local extSite = TerrainAnalysis.nearest(analysis.valleyFloor, extX, extZ, nil, 800)
		or TerrainAnalysis.nearest(analysis.sites, extX, extZ, nil, 900)
		or TerrainAnalysis.nearest(analysis.sites, extX, extZ)

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

	-- extraction console: the legitimate initiation path (audit P0). Interact -> squad vote ->
	-- dropship. Positioned at the operation extraction region, not the deployment LZ.
	local console = Instance.new("Part")
	console.Name = "ExtractionConsole"
	console.Size = Vector3.new(2.2, 3.6, 1.4)
	console.Position = def.extractionRegion + Vector3.new(6, 2.2, 6)
	console.Anchored = true
	console.Material = Enum.Material.Metal
	console.Color = Color3.fromRGB(52, 56, 66)
	console:SetAttribute("GFInteract", "ExtractCall")
	console:SetAttribute("InteractPrompt", "Call extraction")
	console.Parent = sitesFolder
	local lamp = Instance.new("Part")
	lamp.Name = "ConsoleLamp"
	lamp.Size = Vector3.new(1.6, 0.4, 0.8)
	lamp.Position = console.Position + Vector3.new(0, 2.1, 0)
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.Material = Enum.Material.Neon
	lamp.Color = Color3.fromRGB(96, 214, 232)
	lamp.Parent = sitesFolder

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

	-- garrisons: scripted mission-critical spawns direct through EnemyService (audit posture:
	-- the director's spawnAround validity rules require 65-140 studs from players — impossible
	-- for sites a kilometer from deployment). Proximity clustering forms squads automatically.
	-- Composition scales with difficulty; elites only at the stronghold.
	if Services.EnemyService then
		local diff = def.difficulty
		for _, node in def.objectives do
			if node.optional then continue end
			local comp: { string }
			if node.siteType == "stronghold" then
				comp = { "Rifleman", "Rifleman", "Scout", "Marksman" }
				if diff == "Hard" or diff == "Extreme" then
					table.insert(comp, "Heavy")
					table.insert(comp, "Officer")
				elseif diff == "Normal" then
					table.insert(comp, "Officer")
				end
			else
				comp = { "Rifleman", "Rifleman" }
				if diff ~= "Easy" then table.insert(comp, "Scout") end
			end
			local idx = 0
			task.delay(2, function()
				pcall(function()
					for _, enemyId in comp do
						idx += 1
						local a = (idx / #comp) * math.pi * 2
						local r = 14 + (idx % 3) * 6
						local pos = node.position + Vector3.new(math.cos(a) * r, 4, math.sin(a) * r)
						Services.EnemyService.spawn(enemyId, pos)
					end
				end)
			end)
		end
	end

	OperationService.publishState()
	OperationService.publishProgress()
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

-- compose the player-facing objective picture: nearest available objective as the marker,
-- hint text covering all active work. Shaped exactly like the legacy payload so the existing
-- HUD renders operations without client changes.
function OperationService.publishProgress(player: Player?)
	if not current then return end
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local remotes = ReplicatedStorage:FindFirstChild("GF") and ReplicatedStorage.GF:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("ObjectiveProgress")
	if not remote then return end

	local available: { ObjectiveNode } = {}
	local completedCount = 0
	local totalRequired = 0
	for _, n in current.objectives do
		if n.state == "Completed" then completedCount += 1 end
		if not n.optional then totalRequired += 1 end
		if n.state == "Available" or n.state == "Active" then
			table.insert(available, n)
		end
	end
	-- progress: fraction of required objectives complete
	local progress = totalRequired > 0 and (completedCount / totalRequired) or 0
	-- hint: enumerate available work, or direct to extraction when primary done
	local hint
	local primary = nil
	for _, n in current.objectives do
		if n.id == current.primaryObjective then primary = n end
	end
	if primary and primary.state == "Completed" then
		hint = "Primary complete — proceed to extraction"
	elseif #available > 0 then
		local labels = {}
		for _, n in available do table.insert(labels, n.label) end
		hint = table.concat(labels, "  |  ")
	else
		-- everything remaining is locked: point at the prereq chain
		for _, n in current.objectives do
			if n.state == "Locked" then
				hint = n.label .. " (locked — complete prerequisites)"
				break
			end
		end
	end
	-- marker: first available required objective, else the primary position
	local marker = nil
	for _, n in current.objectives do
		if (n.state == "Available" or n.state == "Active") and not n.optional then
			marker = { position = n.position, label = n.state == "Active" and "OBJECTIVE" or "TARGET" }
			break
		end
	end
	if not marker and primary and primary.state ~= "Completed" then
		marker = { position = primary.position, label = "OBJECTIVE" }
	elseif not marker and primary then
		marker = { position = current.extractionRegion, label = "EXTRACT" }
	end
	local payload = {
		progress = progress,
		complete = primary and primary.state == "Completed" or false,
		template = current.missionFamily .. " — " .. current.missionVariant,
		hint = hint,
		marker = marker,
	}
	if player then
		remote:FireClient(player, payload)
	else
		remote:FireAllClients(payload)
	end
end

function OperationService.publishState()
	if not current then return end
	local parts = {}
	for _, n in current.objectives do
		table.insert(parts, string.format("%s:%s", n.id, n.state))
	end
	Workspace:SetAttribute("GF_OperationState", table.concat(parts, ";"))
	OperationService.publishProgress()
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
	ExtractCall = true,
}

function OperationService.start()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
	local interact = remotes:WaitForChild("InteractRequest")
	interact.OnServerEvent:Connect(function(player, targetString)
		if type(targetString) ~= "string" or not OP_TARGETS[targetString] then return end
		if not current then return end
		if targetString == "ExtractCall" then
			-- range-validate against the physical console, then route through the squad vote —
			-- never the direct call path (audit: vote bypass defect)
			local sitesFolder = Workspace:FindFirstChild("OperationSites")
			local console = sitesFolder and sitesFolder:FindFirstChild("ExtractionConsole")
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not (console and root) then return end
			if (root.Position - console.Position).Magnitude > 14 then return end
			pcall(function()
				require(script.Parent.ExtractionService).requestVote(player)
			end)
			return
		end
		OperationService.interact(player, targetString)
	end)
	-- services bound for garrison spawns + completion handoff
	pcall(function()
		OperationService.bind({
			EncounterDirector = require(script.Parent.EncounterDirector),
			ObjectiveService = require(script.Parent.ObjectiveService),
			EnemyService = require(script.Parent.EnemyService),
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
