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

-- operational circumstances (directive stage 8): the same template plays differently under
-- different conditions. Selection is seeded — deterministic per operation seed — and weighted
-- toward harsher conditions at higher difficulties. Effects apply at activation: lighting,
-- garrison composition, patrol distribution.
local CIRCUMSTANCES: { [string]: { weight: number, minRank: number } } = {
	standard = { weight = 38, minRank = 0 },
	night_assault = { weight = 15, minRank = 0 },
	storm = { weight = 14, minRank = 0 },
	entrenched = { weight = 12, minRank = 0 },
	alerted = { weight = 12, minRank = 0 },
	fortified = { weight = 9, minRank = 3 },
}
local DIFFICULTY_RANKS: { [string]: number } = { Easy = 1, Normal = 3, Hard = 6, Extreme = 14 }

local function pickCircumstance(seed: number, difficulty: string): string
	local stream = Random.new(seed * 7919 + 31)
	local rank = DIFFICULTY_RANKS[difficulty] or 1
	local total = 0
	local eligible = {}
	for id, c in CIRCUMSTANCES do
		-- harder operations skew hostile: at Hard+ the standard weight halves
		local w = c.weight
		if id == "standard" and rank >= 6 then w = math.floor(w / 2) end
		if rank >= c.minRank then
			total += w
			eligible[id] = w
		end
	end
	local roll = stream:NextInteger(1, math.max(1, total))
	for id, w in eligible do
		roll -= w
		if roll <= 0 then return id end
	end
	return "standard"
end

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
	template: string?,
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

	-- 5. extraction region: 300-900 studs from primary, off the deployment axis. Constraint is
	-- enforced relative to the primary itself — unconstrained fallback snapped onto the primary
	-- bench in validation (85 studs, unacceptable: extraction must be its own decision).
	local extX = bestPrimary.x + px * (stream:NextInteger(0, 1) * 2 - 1) * 500
	local extZ = bestPrimary.z + pz * (stream:NextInteger(0, 1) * 2 - 1) * 500
	local function clearOfPrimary(s: any, minD: number): boolean
		local dx, dz = s.x - bestPrimary.x, s.z - bestPrimary.z
		return math.sqrt(dx * dx + dz * dz) >= minD
	end
	local extSite = nil
	do
		-- candidates near the perpendicular target, filtered by the distance band
		local bestD = math.huge
		for _, pool in ipairs({ analysis.valleyFloor, analysis.sites }) do
			for _, s in pool do
				local dx, dz = s.x - extX, s.z - extZ
				local d = math.sqrt(dx * dx + dz * dz)
				local pd = math.sqrt((s.x - bestPrimary.x) ^ 2 + (s.z - bestPrimary.z) ^ 2)
				if d < bestD and pd >= 300 and pd <= 1100 then
					bestD = d
					extSite = s
				end
			end
			if extSite then break end
		end
		-- fallback: any site in the band, closest to the target direction
		if not extSite then
			local bestScore2 = -math.huge
			for _, s in analysis.sites do
				local pd = math.sqrt((s.x - bestPrimary.x) ^ 2 + (s.z - bestPrimary.z) ^ 2)
				if pd >= 300 and pd <= 1100 then
					if s.score > bestScore2 then
						bestScore2 = s.score
						extSite = s
					end
				end
			end
		end
	end

	if not extSite then
		local bestScore3 = -math.huge
		for _, s in analysis.sites do
			local pd = math.sqrt((s.x - bestPrimary.x) ^ 2 + (s.z - bestPrimary.z) ^ 2)
			if pd >= 200 and s.score > bestScore3 then
				bestScore3 = s.score
				extSite = s
			end
		end
	end
	if not (shieldSite and commsSite and extSite) then return nil end

	local circumstance = pickCircumstance(seed, difficulty)

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
		template = "CONQUEST_DOMINION",
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
			-- defend objectives self-start on unlock: the assault begins when the asset is live
			if n.mechanic == "defend" then
				OperationService.startDefend(n, n.defendSeconds or 90)
			end
		end
	end
	-- multi-primary rule: parallel-objective families complete when every required objective
	-- completes; single-terminus families complete on the primary node
	local allRequiredComplete = true
	for _, n in current.objectives do
		if not n.optional and n.state ~= "Completed" then
			allRequiredComplete = false
			break
		end
	end
	if id == current.primaryObjective or allRequiredComplete then
		if Services.ObjectiveService and Services.ObjectiveService.complete then
			pcall(function() Services.ObjectiveService.complete() end)
		else
			Workspace:SetAttribute("GF_ObjectiveComplete", true)
		end
	end
	OperationService.publishState()
end

-- hold tracking: one interaction per player at a time, cancelled by range/death/disconnect
local holdingPlayers: { [Player]: boolean } = {}

function OperationService.interact(player: Player, targetString: string)
	if not current then return end
	if holdingPlayers[player] then return end
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
				if node.mechanic == "capture" and not requiresMet(node, ids) then
					Workspace:SetAttribute("GF_OpHint", "The stronghold shield is still active")
					return
				end
				-- hold-to-complete: capture 4s (primary gravity), disable/recover 2.5s.
				-- range re-checks every 0.15s; leaving/downing/disconnecting releases the hold.
				local holdTime = node.mechanic == "capture" and 4 or 2.5
				node.state = "Active"
				OperationService.publishState()
				holdingPlayers[player] = true
				local opId = current and current.operationId
				task.spawn(function()
					local held = 0
					local ok = true
					while held < holdTime do
						task.wait(0.15)
						held += 0.15
						-- cancellation conditions (directive: idempotent, lifecycle-safe)
						if not current or current.operationId ~= opId then ok = false break end
						if node.state == "Completed" then ok = false break end
						local c = player.Character
						local r = c and c:FindFirstChild("HumanoidRootPart")
						local h = c and c:FindFirstChild("Humanoid")
						if not r or not h or h.Health <= 0 then ok = false break end
						if player:GetAttribute("GFDowned") == true then ok = false break end
						if (r.Position - d.Position).Magnitude > 16 then ok = false break end
					end
					holdingPlayers[player] = nil
					if ok and current and current.operationId == opId and node.state ~= "Completed" then
						OperationService.completeObjective(node.id, "interact")
					elseif not ok and node.state == "Active" then
						-- released: back to available so the hint reflects reality
						node.state = "Available"
						OperationService.publishState()
					end
				end)
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

-- ============ extended mechanics runtime ============

-- eliminate: spawn tagged targets at the site when the objective activates; completion when
-- all tagged targets die. Untagged enemies never count (audit-proven pattern).
local eliminateWatchers: { [string]: boolean } = {}

function OperationService.armEliminate(node: ObjectiveNode)
	if eliminateWatchers[node.id] then return end
	eliminateWatchers[node.id] = true
	local opId = current and current.operationId
	task.spawn(function()
		-- spawn the elimination roster at the site
		local comp = node.elimComposition or { "Officer", "Rifleman", "Rifleman" }
		local tagged = {}
		pcall(function()
			for i, id in comp do
				local a = (i / #comp) * math.pi * 2
				local sx = node.position.X + math.cos(a) * 12
				local sz = node.position.Z + math.sin(a) * 12
				local sy = node.position.Y + 4
				local hit = Workspace:Raycast(Vector3.new(sx, 1200, sz), Vector3.new(0, -1400, 0))
				if hit then sy = hit.Position.Y + 3 end
				-- boss ids route to their bespoke modules (audit: config rows alone don't
				-- produce boss behavior — BastionWalker/Veyr are self-running modules)
				local m = nil
				if id == "BastionWalker" then
					pcall(function()
						m = require(game:GetService("ServerScriptService").GF.BastionWalker).spawn(Vector3.new(sx, sy, sz))
					end)
				elseif id == "HighMarshalVeyr" then
					pcall(function()
						m = require(game:GetService("ServerScriptService").GF.Veyr).spawn(Vector3.new(sx, sy, sz))
					end)
				else
					m = Services.EnemyService and Services.EnemyService.spawn(id, Vector3.new(sx, sy, sz))
				end
				if m then
					m:SetAttribute("GF_ObjectiveTarget", true)
					table.insert(tagged, m)
				end
			end
		end)
		if #tagged == 0 then return end
		-- death watch: attribute-driven, checked sparsely (deaths are rare events)
		while current and current.operationId == opId do
			task.wait(1)
			if node.state == "Completed" then break end
			if node.state == "Locked" then continue end
			local alive = 0
			for _, m in tagged do
				if m.Parent and m:GetAttribute("Dead") ~= true then alive += 1 end
			end
			node.progress = 1 - (alive / #tagged)
			if alive == 0 then
				OperationService.completeObjective(node.id, "elimination")
				break
			end
		end
	end)
end

-- defend: once started (by interaction), survive the timer; pressure escalation comes from
-- the director economy (already extraction/objective-aware). Completion at timer end.
function OperationService.startDefend(node: ObjectiveNode, seconds: number)
	local opId = current and current.operationId
	node.state = "Active"
	OperationService.publishState()
	task.spawn(function()
		local t = 0
		while t < seconds do
			task.wait(1)
			t += 1
			if not current or current.operationId ~= opId then return end
			if node.state ~= "Active" then return end
			node.progress = t / seconds
		end
		if current and current.operationId == opId and node.state == "Active" then
			OperationService.completeObjective(node.id, "defend")
		end
	end)
end

-- interact routing extension: mechanic-specific activation behavior
local originalInteract = OperationService.interact

-- ============ activation ============

local lastActivationAt = 0

function OperationService.activate(def: OperationDefinition): boolean
	local valid, err = OperationService.validateGraph(def.objectives)
	if not valid then
		warn("OperationService: invalid graph:", err)
		return false
	end
	-- deploy fan-out can fire twice for one click; regeneration is seeded-identical but the
	-- garrison spawns and site rebuilds are not free. Debounce rapid reactivation.
	if current and os.clock() - lastActivationAt < 5 then
		return true
	end
	lastActivationAt = os.clock()
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
	Workspace:SetAttribute("GF_OpCircumstance", def.circumstance or "standard")
	-- squad-facing condition brief: the circumstance is a fact of the operation, not a secret
	do
		local circ = def.circumstance or "standard"
		if circ ~= "standard" then
			local briefs = {
				night_assault = "Night assault. The dark is cover — the enemy line is thin but the walk is long.",
				storm = "Storm front over the valley. Visibility is short; patrols are thin.",
				entrenched = "Enemy is entrenched. Expect hardened positions at every site.",
				alerted = "The Ascendancy is alerted. Patrol density is high — move fast.",
				fortified = "The stronghold is fortified. Bring everything you have.",
			}
			local ev = game:GetService("ReplicatedStorage"):FindFirstChild("GF") and game:GetService("ReplicatedStorage").GF:FindFirstChild("Remotes") and game:GetService("ReplicatedStorage").GF.Remotes:FindFirstChild("MissionEvent")
			if ev and briefs[circ] then
				ev:FireAllClients({ text = briefs[circ], kind = "info" })
			end
		end
	end

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
			-- circumstance posture: entrenched digs in, fortified hardens the stronghold,
			-- night assault thins the line (the dark is the squad's ally)
			local circ = def.circumstance or "standard"
			if circ == "entrenched" then
				table.insert(comp, "Rifleman")
				table.insert(comp, "Rifleman")
			elseif circ == "fortified" and node.siteType == "stronghold" then
				table.insert(comp, "Heavy")
				table.insert(comp, "Marksman")
			elseif circ == "night_assault" and #comp > 3 then
				table.remove(comp, #comp)
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

	-- route encounter zones: dormant patrols along the deployment->primary corridor
	if Services.EnemyService and rng then
		local primary = nil
		for _, n in def.objectives do
			if n.id == def.primaryObjective then primary = n end
		end
		if primary then
			local zones = {}
			local dx = primary.position.X - def.deploymentRegion.X
			local dz = primary.position.Z - def.deploymentRegion.Z
			local len = math.sqrt(dx * dx + dz * dz)
			local px, pz = -dz / len, dx / len
			-- route variety: alerted operations run denser patrols, storm operations thinner
			local circ2 = def.circumstance or "standard"
			local fractions = { 0.28, 0.52, 0.74 }
			if circ2 == "alerted" then
				fractions = { 0.22, 0.4, 0.58, 0.76 }
			elseif circ2 == "storm" then
				fractions = { 0.35, 0.65 }
			end
			for _, frac in ipairs(fractions) do
				local lateral = rng:NextInteger(-260, 260)
				zones[#zones + 1] = {
					x = def.deploymentRegion.X + dx * frac + px * lateral,
					z = def.deploymentRegion.Z + dz * frac + pz * lateral,
					size = frac > 0.6 and 3 or 2,
					done = false,
					comp = rng:NextInteger(1, 3),
				}
			end
			local opId = def.operationId
			task.spawn(function()
				while current and current.operationId == opId do
					task.wait(3)
					if Workspace:GetAttribute("GF_InMission") ~= true then break end
					local players = game:GetService("Players"):GetPlayers()
					for _, z in zones do
						if z.done then continue end
						for _, pl in players do
							local c = pl.Character
							local r = c and c:FindFirstChild("HumanoidRootPart")
							if r then
								local ddx, ddz = r.Position.X - z.x, r.Position.Z - z.z
								if math.sqrt(ddx * ddx + ddz * ddz) < 200 then
									z.done = true
									-- patrol composition: standard infantry mix, squad-clustered
									task.spawn(function()
										pcall(function()
											-- seeded composition variety: scout parties, infantry lines, heavy teams
											local comp = { "Rifleman", "Scout" }
											if z.comp == 2 then
												comp = { "Scout", "Scout" }
											elseif z.comp == 3 then
												comp = { "Rifleman", "Rifleman", "Marksman" }
											end
											if z.size >= 3 then table.insert(comp, "Rifleman") end
											for i, id in comp do
												local a = (i / #comp) * math.pi * 2
											local sx, sz = z.x + math.cos(a) * 10, z.z + math.sin(a) * 10
											-- terrain-probe first: EnemyService.spawn ground-snaps from +40 down 160,
											-- which starts below mountain surfaces. Probe from high above instead.
											local sy = 60
											local hit = Workspace:Raycast(Vector3.new(sx, 1200, sz), Vector3.new(0, -1400, 0))
											if hit then sy = hit.Position.Y + 3 end
											Services.EnemyService.spawn(id, Vector3.new(sx, sy, sz))
											end
											Workspace:SetAttribute("GF_OpPatrols", (Workspace:GetAttribute("GF_OpPatrols") or 0) + 1)
										end)
									end)
									break
								end
							end
						end
					end
					-- all zones consumed: stop polling
					local anyLeft = false
					for _, z in zones do
						if not z.done then anyLeft = true break end
					end
					if not anyLeft then break end
				end
			end)
		end
	end

	-- arm elimination mechanics: tagged targets exist in the world from activation
	for _, node in def.objectives do
		if node.mechanic == "eliminate" then
			OperationService.armEliminate(node)
		end
	end

	OperationService.publishState()
	OperationService.publishProgress()
	print(string.format("OperationService: %s activated — %d objectives",
		def.operationId, #def.objectives))
	return true
end

-- template metadata: family/variant names per template id for the manifest
local TEMPLATE_META: { [string]: { family: string, variant: string } } = {
	SABOTAGE_RELAY = { family = "Sabotage", variant = "Relay" },
	SABOTAGE_ARSENAL = { family = "Sabotage", variant = "Arsenal" },
	SABOTAGE_AEGIS = { family = "Sabotage", variant = "Aegis" },
	RECOVER_TECH = { family = "Recovery", variant = "Tech" },
	RECOVERY_ARCHIVE = { family = "Recovery", variant = "Archive" },
	RECOVERY_CONVOY = { family = "Recovery", variant = "Convoy" },
	DEFEND_BEACON = { family = "Defense", variant = "Beacon" },
	DEFENSE_POWER = { family = "Defense", variant = "Power" },
	DEFENSE_UPLINK = { family = "Defense", variant = "Uplink" },
	ELIM_COMMANDER = { family = "Elimination", variant = "Commander" },
	ELIM_WALKER = { family = "Elimination", variant = "Walker" },
	ELIM_TALON = { family = "Elimination", variant = "Talon" },
	CONQUEST_DOMINION = { family = "Conquest", variant = "Stronghold" },
	CONQUEST_FOUNDRY = { family = "Conquest", variant = "Foundry" },
	CONQUEST_THRONEFALL = { family = "Conquest", variant = "Thronefall" },
}

-- primary-objective designation per template: terminus node where one exists; for parallel
-- families the multi-primary completion rule (all required complete) governs instead.
local PRIMARY_BY_TEMPLATE: { [string]: string } = {
	SABOTAGE_RELAY = "destroy_relay",
	SABOTAGE_ARSENAL = "destroy_arsenal",
	SABOTAGE_AEGIS = "destroy_aegis",
	RECOVER_TECH = "recover_tech",
	RECOVERY_ARCHIVE = "recover_archive",
	RECOVERY_CONVOY = "recover_crate_beta",
	DEFEND_BEACON = "hold_beacon",
	DEFENSE_POWER = "defend_power",
	DEFENSE_UPLINK = "defend_uplink",
	ELIM_COMMANDER = "eliminate_commander",
	ELIM_WALKER = "eliminate_walker",
	ELIM_TALON = "eliminate_talon_gamma",
	CONQUEST_DOMINION = "capture_stronghold",
	CONQUEST_FOUNDRY = "capture_foundry_beta",
	CONQUEST_THRONEFALL = "eliminate_marshal",
}

function OperationService.generate(seed: number, variant: string, difficulty: string): OperationDefinition?
	local GeographyService = require(script.Parent.GeographyService)
	local analysis = GeographyService.analysis
	if not analysis or #analysis.sites < 8 then
		warn("OperationService: terrain analysis not ready")
		return nil
	end
	local geographyId = tostring(Workspace:GetAttribute("GF_GeoFoundation") or "unknown")
	-- reference operation: the validated Conquest-Stronghold generator
	if variant == "CONQUEST_DOMINION" or variant == nil then
		return generateConquestStronghold(seed, difficulty, analysis, geographyId)
	end
	-- expansion families: shared skeleton, per-template DAG shape
	local meta = TEMPLATE_META[variant]
	if not meta then
		warn("OperationService: unknown template", variant)
		return nil
	end
	local Families = require(script.Parent.OperationFamilies)
	local gen = Families[variant]
	if not gen then
		warn("OperationService: no generator for", variant)
		return nil
	end
	-- one source of truth for the spatial skeleton: the families module owns frame
	-- construction; OperationService builds it and hands it to the family generator.
	local fr = Families.frame(seed, analysis)
	if not fr or not fr.extraction then
		warn("OperationService: frame generation failed for", variant)
		return nil
	end
	local objectives = gen(seed, fr)
	if not objectives then return nil end
	return {
		operationId = string.format("OP-%d", seed),
		operationSeed = seed,
		generatorVersion = GENERATOR_VERSION,
		geographyId = geographyId,
		missionFamily = meta.family,
		missionVariant = meta.variant,
		template = variant,
		difficulty = difficulty,
		deploymentRegion = fr.deploy,
		primaryObjective = PRIMARY_BY_TEMPLATE[variant] or objectives[1].id,
		objectives = objectives,
		extractionRegion = fr.extraction,
		missionTimeLimit = 1500,
		circumstance = pickCircumstance(seed, difficulty),
	}
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
