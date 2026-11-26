--!strict
-- Server-owned Ascendancy actors: kinematic (CFrame-stepped) models, one throttled AI tick each.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Constants = require(ReplicatedStorage.GF.Shared.Constants)
local Enemies = require(ReplicatedStorage.GF.Shared.Configs.Enemies)
local Difficulties = require(ReplicatedStorage.GF.Shared.Configs.Difficulties)
local State = require(ServerScriptService.GF.Services.State)
local VitalsService = require(ServerScriptService.GF.Services.VitalsService)
local debugAttr -- forward declaration: used by closures throughout the module, defined near the bottom
local ArtService = require(ServerScriptService.GF.Services.ArtService)
local NPCLocomotion = require(ServerScriptService.GF.Services.NPCLocomotion)

-- config ids map onto the spec's five archetypes: Scout is the Vanguard implementation,
-- Officer is the Commander implementation (S06-archetype reconciliation, audit 2026-11-26).
local ARCHETYPE = {
	Rifleman = "Rifleman",
	Scout = "Vanguard",
	Marksman = "Marksman",
	Heavy = "Heavy",
	Officer = "Commander",
	BastionWalker = "Heavy",
	HighMarshalVeyr = "Commander",
}
local function locoProfile(def: any)
	return NPCLocomotion.profileFor(ARCHETYPE[def.id] or "Default")
end

-- Tactical profiles (spec sections 21/22/27): how each archetype fights. These are weights and
-- preferences, not scripts — the same decision machinery produces visibly different behavior:
--   preferredRange: fraction of attackRange the soldier tries to hold (gaussian center d0).
--   minRangeFrac: below this fraction the position is actively bad (marksmen hate close fights).
--   repositionUrgency: how readily they slide/reposition under pressure (0..1).
--   coverCommit: how long they exploit a cover node before re-evaluating (seconds, base).
--   flankArc: width of the flanking swing (0 = no flanking).
--   suppressionShrug: fraction of suppression impulses ignored (heavies are hard to suppress).
--   retreatHpFrac: below this health fraction they fall back instead of holding (0 = never).
local TACTICAL = {
	Rifleman = { preferredRange = 0.75, minRangeFrac = 0.15, repositionUrgency = 0.5, coverCommit = 5, flankArc = 0.85, suppressionShrug = 0.2, retreatHpFrac = 0.2 },
	Vanguard = { preferredRange = 0.45, minRangeFrac = 0.0, repositionUrgency = 0.85, coverCommit = 2.5, flankArc = 1.3, suppressionShrug = 0.35, retreatHpFrac = 0.0 },
	Marksman = { preferredRange = 0.9, minRangeFrac = 0.45, repositionUrgency = 0.65, coverCommit = 6, flankArc = 0.4, suppressionShrug = 0.1, retreatHpFrac = 0.35 },
	Heavy = { preferredRange = 0.7, minRangeFrac = 0.1, repositionUrgency = 0.15, coverCommit = 8, flankArc = 0.0, suppressionShrug = 0.8, retreatHpFrac = 0.0 },
	Commander = { preferredRange = 0.7, minRangeFrac = 0.2, repositionUrgency = 0.4, coverCommit = 6, flankArc = 0.5, suppressionShrug = 0.3, retreatHpFrac = 0.3 },
	Default = { preferredRange = 0.75, minRangeFrac = 0.15, repositionUrgency = 0.5, coverCommit = 5, flankArc = 0.7, suppressionShrug = 0.2, retreatHpFrac = 0.2 },
}
local function tacticalProfile(def: any)
	return TACTICAL[ARCHETYPE[def.id] or "Default"] or TACTICAL.Default
end

-- range quality (spec section 22): gaussian preference around the archetype's preferred distance.
-- Asymmetric: marksmen penalize too-close far more strongly than too-far.
local function rangeQuality(dist: number, attackRange: number, prof: any): number
	local d0 = attackRange * prof.preferredRange
	local sigma = attackRange * 0.25
	local delta = dist - d0
	if delta < 0 and dist < attackRange * prof.minRangeFrac then
		sigma = sigma * 0.5 -- inside the minimum: penalty tightens sharply
	end
	return math.exp(-(delta * delta) / (2 * sigma * sigma))
end

-- suppression (spec section 23): impulse-decay state. incoming fire events add impulses;
-- between events the pressure bleeds off exponentially. affects decisions, never the player.
local SUPPRESS_DECAY = 0.55 -- per second exponential decay constant
local SUPPRESS_MAX = 1.0
local SUPPRESS_ACT = 0.55 -- above this the soldier's behavior visibly changes
local function tickSuppression(actor: any, dt: number)
	actor.suppression = (actor.suppression or 0) * math.exp(-SUPPRESS_DECAY * dt)
end
local function addSuppression(actor: any, impulse: number, prof: any)
	actor.suppression = math.min(SUPPRESS_MAX, (actor.suppression or 0) + impulse * (1 - prof.suppressionShrug))
end
local NPCNavigation = require(ServerScriptService.GF.Services.NPCNavigation)
local NPCPerception = require(ServerScriptService.GF.Services.NPCPerception)
local NPCSquads = require(ServerScriptService.GF.Services.NPCSquads)

-- nav-aware movement intent (spec section 14): short hops steer directly; longer moves request
-- tactical waypoints from the navigation cache. When the cache misses the compute is queued and
-- the soldier steers directly meanwhile — nobody waits on pathfinding latency. Priority scales
-- with urgency: engaged 3, investigate 2, everything else 1.
-- patrol routes (spec section 30): geographically plausible loops around the squad's home region —
-- perimeter walks, not random wandering. waypoints are ground-snapped at generation time so the
-- route follows the terrain; the locomotion/nav layer handles local obstacles en route.
local function generatePatrolLoop(home: Vector3): { Vector3 }
	local wps = {}
	local radius = 26 + math.random() * 14
	local count = 4 + math.random(2) -- 4-6 points
	local baseAngle = math.random() * math.pi * 2
	local patrolParams = RaycastParams.new()
	patrolParams.FilterType = Enum.RaycastFilterType.Exclude
	local actorsFolder = workspace:FindFirstChild("ActiveActors")
	patrolParams.FilterDescendantsInstances = actorsFolder and { actorsFolder } or {}
	patrolParams.IgnoreWater = true
	for i = 1, count do
		local angle = baseAngle + (i / count) * math.pi * 2
		local candidate = home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		-- ground snap: probe down through vegetation-free space; waypoints sit on real terrain.
		-- deep probe: baked terrain relief spans hundreds of studs (Teton 24-1156), so a shallow
		-- probe silently drops every downhill waypoint and the loop collapses empty.
		local probe = workspace:Raycast(candidate + Vector3.new(0, 120, 0), Vector3.new(0, -500, 0), patrolParams)
		if probe then
			wps[#wps + 1] = Vector3.new(candidate.X, probe.Position.Y, candidate.Z)
		end
	end
	return wps
end

local function navMove(actor: any, model: Model, destination: Vector3, speedClass: string, stopRadius: number, priority: number?)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local dist = (destination - root.Position).Magnitude
	if dist > 30 then
		local wps = NPCNavigation.waypointsFor(model, root.Position, destination, priority or 1)
		if wps and #wps > 1 then
			NPCLocomotion.followPath(actor.locomotion, wps, speedClass, stopRadius)
			return
		end
	end
	NPCLocomotion.moveTo(actor.locomotion, destination, speedClass, stopRadius)
end

local EnemyService = {}

local TICK = 0.2
local actors: { [Model]: any } = {}
local folder: Folder? = nil

-- Perception model (S06-008..014): 110 deg sight cone unless alerted, near proximity bypasses the cone,
-- unsuppressed gunfire alerts within hearing range, stale positions decay with exp(-age/4) confidence.
local SIGHT_CONE_COS = math.cos(math.rad(55)) -- half-angle of the 110 deg cone
local PROXIMITY_RANGE = 14
local HEARING_RANGE = 90
local CONFIDENCE_TAU = 4 -- seconds; confidence = exp(-age/4)
-- Reaction delay bands per difficulty (S06-009): uniform sample applied once when a hostile first
-- transitions into Engage, so Easy hostiles telegraph their reaction and Extreme ones snap.
local REACTION_BANDS = {
	Easy = { 0.5, 0.9 },
	Normal = { 0.25, 0.6 },
	Hard = { 0.2, 0.45 },
	Extreme = { 0.15, 0.35 },
}
local CONFIDENCE_GIVE_UP = 0.2 -- below this (~6.4s stale) the actor returns home
local SEARCH_RADIUS = 14
local SEARCH_MAX_AGE = 10

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = workspace:FindFirstChild("ActiveActors")
	if not f then
		f = Instance.new("Folder"); f.Name = "ActiveActors"; f.Parent = workspace
	end
	folder = f :: Folder
	return folder :: Folder
end

local PALETTE = {
	Standard = { armor = Color3.fromRGB(38, 40, 52), plate = Color3.fromRGB(224, 219, 205), light = Color3.fromRGB(196, 138, 58) },
	Specialist = { armor = Color3.fromRGB(30, 32, 44), plate = Color3.fromRGB(228, 222, 208), light = Color3.fromRGB(170, 120, 200) },
	Elite = { armor = Color3.fromRGB(24, 26, 36), plate = Color3.fromRGB(236, 230, 214), light = Color3.fromRGB(206, 120, 60) },
	Boss = { armor = Color3.fromRGB(18, 20, 28), plate = Color3.fromRGB(240, 234, 220), light = Color3.fromRGB(214, 96, 44) },
}

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function buildModel(def: any, cframe: CFrame): Model
	local palette = PALETTE[def.tier] or PALETTE.Standard
	local scale = def.tier == "Boss" and 2.2 or (def.tier == "Elite" and 1.25 or 1)

	local model = Instance.new("Model")
	model.Name = def.id

	local root = part("Root", Vector3.new(2, 2, 1) * scale, palette.armor, Enum.Material.Metal)
	root.CFrame = cframe
	root.Anchored = true
	root.Transparency = 1
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root

	local torso = part("Torso", Vector3.new(2.1, 2.4, 1.2) * scale, palette.armor, Enum.Material.Metal)
	torso.CFrame = cframe * CFrame.new(0, 0, 0)
	torso.Parent = model

	local plate = part("ChestPlate", Vector3.new(1.7, 1.3, 0.5) * scale, palette.plate, Enum.Material.Slate)
	plate.CFrame = cframe * CFrame.new(0, 0.35 * scale, -0.6 * scale)
	plate.Parent = model

	local head = part("Head", Vector3.new(1.15, 1.35, 1.15) * scale, palette.armor, Enum.Material.Metal)
	head.CFrame = cframe * CFrame.new(0, 1.85 * scale, 0)
	head.Parent = model

	local visor = part("Visor", Vector3.new(0.85, 0.3, 0.2) * scale, palette.light, Enum.Material.Neon)
	visor.CFrame = cframe * CFrame.new(0, 1.85 * scale, -0.55 * scale)
	visor.Parent = model

	local shoulderL = part("ShoulderL", Vector3.new(0.85, 0.7, 1.0) * scale, palette.plate, Enum.Material.Slate)
	shoulderL.CFrame = cframe * CFrame.new(-1.25 * scale, 0.85 * scale, 0)
	shoulderL.Parent = model

	local shoulderR = part("ShoulderR", Vector3.new(0.85, 0.7, 1.0) * scale, palette.plate, Enum.Material.Slate)
	shoulderR.CFrame = cframe * CFrame.new(1.25 * scale, 0.85 * scale, 0)
	shoulderR.Parent = model

	local legL = part("LegL", Vector3.new(0.7, 1.9, 0.8) * scale, palette.armor, Enum.Material.Metal)
	legL.CFrame = cframe * CFrame.new(-0.5 * scale, -2.05 * scale, 0)
	legL.Parent = model

	local legR = part("LegR", Vector3.new(0.7, 1.9, 0.8) * scale, palette.armor, Enum.Material.Metal)
	legR.CFrame = cframe * CFrame.new(0.5 * scale, -2.05 * scale, 0)
	legR.Parent = model

	local weapon = part("Weapon", Vector3.new(0.28, 0.28, 1.9) * scale, palette.armor, Enum.Material.Metal)
	weapon.CFrame = cframe * CFrame.new(0.85 * scale, -0.2 * scale, -0.9 * scale)
	weapon.Parent = model

	-- S11 exposed weak point: archetypes whose config carries a bonus multiplier grow a visible
	-- power core — a glowing vulnerable node offset high on the back plate, so flanking or
	-- precision fire is rewarded per spec. The combat service reads the WeakPoint attribute on hit.
	if (tonumber(def.weakPointMultiplier) or 1) > 1 then
		local core = part("WeakCore", Vector3.new(0.68, 0.68, 0.42) * scale, palette.light, Enum.Material.Neon)
		core.CFrame = cframe * CFrame.new(0, 0.55 * scale, 0.82 * scale)
		core.Transparency = 0
		core.Anchored = false
		core:SetAttribute("WeakPoint", tonumber(def.weakPointMultiplier))
		core.Parent = model
		local coreWeld = Instance.new("WeldConstraint")
		coreWeld.Part0 = root
		coreWeld.Part1 = core
		coreWeld.Parent = core
	end
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p ~= root and p.Name ~= "WeakCore" then
			p.Anchored = false
			-- Hit volumes only: the authored rig supplies all visible geometry.
			p.Transparency = 1
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
		end
	end

	-- Authored character rig is the visible body; primitive parts are invisible hit volumes.
	-- Do not make them visible: the rig replaces the block silhouette entirely.
	local rig = nil
	rig = ArtService.clone("AscendancyTrooper")
	if rig then
		local rigScale = scale
		rig:PivotTo(cframe * CFrame.Angles(0, math.rad(180), 0))
		local hum = rig:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.MaxHealth = math.huge
			hum.Health = math.huge
			hum.WalkSpeed = 0
			hum.JumpPower = 0
		end
		-- Seat the rig on the same ground plane the logic root uses so feet never
		-- sink into terrain regardless of tier scale.
		local bcf, bsize = rig:GetBoundingBox()
		local feetY = bcf.Position.Y - bsize.Y * 0.5
		local groundY = root.Position.Y - 3.1 * scale
		if math.abs(groundY - feetY) > 0.05 then
			rig:PivotTo(rig:GetPivot() + Vector3.new(0, groundY - feetY, 0))
		end
		local rigRoot = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rigRoot then
			rigRoot.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = rigRoot
			weld.Parent = rigRoot
		end
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
				if rigScale ~= 1 then d.Size = d.Size * rigScale end
			end
		end
		rig.Parent = model
		rig:SetAttribute("GFEnemyRig", true)
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p ~= root and p.Name ~= "WeakCore" then p.Transparency = 1 end
		end
		model:SetAttribute("HasRig", true)
	end

	model:SetAttribute("GFEnemy", true)
	model:SetAttribute("EnemyId", def.id)
	model:SetAttribute("Tier", def.tier)
	model:SetAttribute("Health", def.health)
	model:SetAttribute("MaxHealth", def.health)
	model:SetAttribute("Shield", def.shield or 0)
	model:SetAttribute("MaxShield", def.shield or 0)
	model:SetAttribute("Dead", false)
	model:SetAttribute("Scale", scale)
	-- Armour mitigation is per archetype in the spec (Heavy 0.75, Commander 0.9).
	model:SetAttribute("ArmorFactor", tonumber(def.armorFactor) or 1)
	model.Parent = getFolder()

	return model
end

-- S04-053: the EMP disable. Pure over the attribute and a clock reading so both the live tick path and the
-- unit checks use exactly one definition of "stunned".
function EnemyService.isStunned(model: Instance, now: number?): boolean
	local untilValue = model and model:GetAttribute("EMPStunUntil")
	if type(untilValue) ~= "number" then
		return false
	end
	local clock = now or os.clock()
	if clock < untilValue then
		return true
	end
	-- Expire it so a stale attribute cannot look like a permanent stun to anything that later reads it.
	model:SetAttribute("EMPStunUntil", nil)
	return false
end
function EnemyService.spawn(enemyId: string, position: Vector3): Model?
	local def = Enemies.get(enemyId)
	if not def then
		warn("[GF] unknown enemy " .. tostring(enemyId))
		return nil
	end
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	local ground = workspace:Raycast(position + Vector3.new(0, 40, 0), Vector3.new(0, -160, 0), groundParams)
	-- S06-035: the ray starts 40 studs up, so under a low roof its first hit is the roof's TOP surface and the
	-- enemy is placed on the ceiling (measured: six of six spawns landed ~31 studs above the player indoors).
	-- A "ground" above the requested point is never valid ground, so fall back to the requested height.
	local groundY = ground and ground.Position.Y or position.Y
	if groundY > position.Y + 2 then
		groundY = position.Y
	end
	local scaleHint = def.tier == "Boss" and 2.2 or (def.tier == "Elite" and 1.25 or 1)
	local model = buildModel(def, CFrame.new(Vector3.new(position.X, groundY + 3.1 * scaleHint, position.Z)))
	-- S06-032: difficulty scales enemy HP, damage and attack cadence (rate). Applied at spawn so a mid-mission
	-- difficulty change cannot retroactively alter already-spawned enemies.
	local mods = Difficulties.modifiersFor(workspace:GetAttribute("GF_OperationDifficulty"))
	local scaledHealth = math.max(1, math.floor((tonumber(def.health) or 1) * mods.hp + 0.5))
	model:SetAttribute("Health", scaledHealth)
	model:SetAttribute("MaxHealth", scaledHealth)
	model:SetAttribute("DamageMultiplier", mods.damage)
	model:SetAttribute("CadenceRate", mods.cadence)
	model:SetAttribute("Difficulty", tostring(workspace:GetAttribute("GF_OperationDifficulty") or "Normal"))
	model:SetAttribute("SpawnSeed", math.random() * 997)
	local scaleNum = def.tier == "Boss" and 2.2 or (def.tier == "Elite" and 1.25 or 1)
	actors[model] = {
		def = def,
		home = position,
		nextTick = os.clock() + math.random() * TICK,
		nextAttack = 0,
		target = nil :: Player?,
		telegraphUntil = 0,
		telegraphTarget = nil :: Player?,
		behavior = def.behavior or "Guard",
		repositionUntil = 0,
		repositionDir = nil :: Vector3?,
		shotsSinceMove = 0,
		deadAt = 0,
		groundOffset = 3.1 * scaleNum,
		locomotion = NPCLocomotion.newState(model.PrimaryPart and (model.PrimaryPart :: BasePart).Position or position, 0),
		perception = NPCPerception.newState(),
		squad = NPCSquads.assign(model, position, ARCHETYPE[def.id] or "Default"),
	}
	return model
end

local function lineOfSight(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local delta = to - from
	local result = workspace:Raycast(from, delta, params)
	if not result then
		return true
	end
	return (result.Position - to).Magnitude < 3
end

local function nearestSentry(model: Model, origin: Vector3, def: any): (Model?, number)
	local folder = workspace:FindFirstChild("GameplayEffects")
	local best, bestDist = nil, math.huge
	if not folder then
		return nil, bestDist
	end
	for _, sentry in folder:GetChildren() do
		if sentry:IsA("Model") and sentry:GetAttribute("GFSentryDestructible") == true and (tonumber(sentry:GetAttribute("Health")) or 0) > 0 then
			local base = sentry.PrimaryPart
			if base then
				local dist = (base.Position - origin).Magnitude
				if dist <= def.sightRange and dist < bestDist then
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { model }
					local hit = workspace:Raycast(origin, base.Position - origin, params)
					if hit == nil or hit.Instance:IsDescendantOf(sentry) then
						best, bestDist = sentry, dist
					end
				end
			end
		end
	end
	return best, bestDist
end

function EnemyService.damageSentry(sentry: Model, amount: number, sourceId: string?)
	local health = (tonumber(sentry:GetAttribute("Health")) or 0) - math.max(0, amount)
	sentry:SetAttribute("Health", math.max(0, health))
	sentry:SetAttribute("GFSentryLastHitBy", sourceId)
	if health <= 0 and sentry.Parent then
		workspace:SetAttribute("GF_LastSentryDestroyed", string.format("%s:%s", sentry.Name, tostring(sourceId)))
		sentry:Destroy()
	end
end

local SpatialGrid = require(script.Parent.SpatialGrid)
-- S06-003: player positions feed the shared spatial grid once per heartbeat; perception then reads
-- the grid's broad-phase cells instead of scanning the full player list per hostile per tick.
task.spawn(function()
	while true do
		task.wait(0.25)
		SpatialGrid.clear()
		for _, plr in ipairs(Players:GetPlayers()) do
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if root then
				SpatialGrid.insert(plr, (root :: BasePart).Position)
			end
		end
	end
end)

-- Exposure sampling (spec section 17): two representative points — head and upper torso.
-- V is the weighted visibility 0..1. Cheap filters run before any raycast: range, FOV periphery.
local exposureParams = RaycastParams.new()
exposureParams.FilterType = Enum.RaycastFilterType.Exclude
exposureParams.IgnoreWater = true
local function sampleExposure(model: Model, origin: Vector3, character: Model, targetRoot: BasePart): number
	local head = character:FindFirstChild("Head")
	exposureParams.FilterDescendantsInstances = { model, character }
	local visible = 0
	local samples = 0
	-- eye height offset: soldiers look from their head, not their center
	local eye = origin + Vector3.new(0, 1.6, 0)
	for _, samplePart in ipairs({ head, targetRoot }) do
		if samplePart and samplePart:IsA("BasePart") then
			samples += 1
			local aim = (samplePart :: BasePart).Position + Vector3.new(0, samplePart == head and 0.3 or 1.0, 0)
			local hit = workspace:Raycast(eye, aim - eye, exposureParams)
			-- strict obstruction: any hit before the target blocks (no more 3-stud tolerance)
			if not hit or (aim - hit.Position).Magnitude < 0.6 then
				visible += 1
			end
		end
	end
	if samples == 0 then
		return 0
	end
	return visible / samples
end

-- perceiveTargets (spec sections 17/20): evidence-accumulation detection with threat selection.
-- Returns the best currently-visible detected target and its distance. Side effects: evidence
-- accumulates per candidate, visual observations refresh memory, alertness rises on contact.
local function perceiveTargets(model: Model, origin: Vector3, def: any, actor: any, dt: number): (Player?, number?)
	local perception = actor.perception
	if not perception then
		return nil, nil
	end
	local forward = model.PrimaryPart and model.PrimaryPart.CFrame.LookVector or Vector3.zAxis
	local flatFwd = Vector3.new(forward.X, 0, forward.Z)
	local now = os.clock()
	local best: Player? = nil
	local bestDist = math.huge
	local bestScore = -math.huge
	for _, player in SpatialGrid.query(origin, def.sightRange) do
		local character = player.Character
		if player:GetAttribute("GF_Aboard") == true then
			continue
		end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid or humanoid.Health <= 0 then
			continue
		end
		local st = State.get(player)
		if st and st.downed then
			continue
		end
		local targetRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not targetRoot then
			continue
		end
		local dist = (targetRoot.Position - origin).Magnitude
		if dist > def.sightRange then
			continue
		end
		-- alignment: flat FOV cone. proximity bypasses facing (soldiers feel nearby presence).
		local toTarget = targetRoot.Position - origin
		local flatTo = Vector3.new(toTarget.X, 0, toTarget.Z)
		local alignment = -1
		if flatTo.Magnitude > 0.1 and flatFwd.Magnitude > 0.1 then
			alignment = flatTo.Unit:Dot(flatFwd.Unit)
		end
		local inProximity = dist <= PROXIMITY_RANGE
		if inProximity then
			alignment = 1 -- proximity presence: full attention regardless of facing
		end
		-- exposure sampling only when cheap filters pass (spec: expensive checks last)
		local exposure = 0
		if alignment >= -0.2 or inProximity then
			if lineOfSight(origin, targetRoot.Position, { model, character }) then
				exposure = sampleExposure(model, origin, character, targetRoot)
			end
		end
		-- evidence accumulation (spec detection-rate model)
		local targetSpeed = targetRoot.AssemblyLinearVelocity.Magnitude
		NPCPerception.accumulate(perception, player, exposure, alignment, dist, def.sightRange, targetSpeed, dt)
		if NPCPerception.isDetected(perception, player) and exposure > 0 then
			-- direct visual contact: refresh memory with the legitimate observation
			NPCPerception.observeVisual(perception, player, targetRoot.Position, targetRoot.AssemblyLinearVelocity)
			-- threat selection (spec section 20): damage threat + visibility + distance + confidence,
			-- persistence bonus for the current target so soldiers don't flicker between victims
			local threat = 0
			if actor.recentThreat and actor.recentThreat[player] then
				threat = math.exp(-(now - actor.recentThreat[player]) / 8)
			end
			local distanceSuitability = 1 - math.clamp(dist / math.max(1, def.sightRange), 0, 1)
			local persistence = (actor.target == player) and 0.18 or 0
			local score = 0.30 * threat + 0.25 * exposure + 0.20 * distanceSuitability + 0.25 * 1.0 + persistence
			if score > bestScore then
				best = player
				bestDist = dist
				bestScore = score
			end
		end
	end
	return best, bestDist
end

local function nearestVisiblePlayer(model: Model, origin: Vector3, def: any, actor: any?): (Player?, number?)
	local best: Player? = nil
	local bestDist = math.huge
	local bestScore = 0
	local now = os.clock()
	local alerted = actor ~= nil and now < (actor.alertedUntil or 0)
	local forward = model.PrimaryPart and model.PrimaryPart.CFrame.LookVector or Vector3.zAxis
	for _, player in SpatialGrid.query(origin, def.sightRange) do
		local character = player.Character
		if player:GetAttribute("GF_Aboard") == true then
			continue
		end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid or humanoid.Health <= 0 then
			continue
		end
		local s = State.get(player)
		if s and s.downed then
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		local dist = (root.Position - origin).Magnitude
		if dist > def.sightRange then
			continue
		end
		-- Sight perception: inside the 110 deg cone unless alerted, or inside near proximity regardless of facing.
		local inProximity = dist <= PROXIMITY_RANGE
		if not alerted and not inProximity then
			local toTarget = (root.Position - origin)
			local flatTo = Vector3.new(toTarget.X, 0, toTarget.Z)
			local flatFwd = Vector3.new(forward.X, 0, forward.Z)
			if flatTo.Magnitude > 0.1 and flatFwd.Magnitude > 0.1 then
				local cosAngle = flatTo.Unit:Dot(flatFwd.Unit)
				if cosAngle < SIGHT_CONE_COS then
					continue
				end
			end
		end
		if lineOfSight(origin, root.Position, { model, character }) then
			-- Target scoring (S06-013): visibility + proximity + recency of being attacked by them.
			local visibility = 1
			local proximity = 1 - math.clamp(dist / math.max(1, def.sightRange), 0, 1)
			local threat = 0
			if actor and actor.recentThreat and actor.recentThreat[player] then
				local age = now - actor.recentThreat[player]
				threat = math.exp(-age / 8)
			end
			local score = 0.40 * visibility + 0.25 * proximity + 0.20 * threat + 0.15 * 0.5
			if score > bestScore or (score == bestScore and dist < bestDist) then
				best = player
				bestDist = dist
				bestScore = score
			end
		end
	end
	return best, bestDist
end

-- S04-057: corpses collapse and persist 12-25s with collisions off, capped at 12 nearby so a big
-- fight cannot pile up permanent body physics. When the cap is exceeded the oldest corpse goes early.
local corpses: { { model: Model, born: number } } = {}
local CORPSE_CAP = 12
local function die(model: Model, actor: any)
	NPCNavigation.cleanup(model)
	NPCSquads.release(model)
	actor.deadAt = os.clock()
	pcall(function()
		require(script.Parent.CacheService).onEnemyKilled(model, nil)
	end)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanQuery = false
			p.CanCollide = false
			p.Anchored = true
		end
	end
	-- randomized 12-25s corpse lifetime per spec
	local lifetime = 12 + math.random() * 13
	actor.corpseUntil = actor.deadAt + lifetime
	table.insert(corpses, { model = model, born = actor.deadAt })
	-- cap enforcement: drop the oldest corpse early when the pile exceeds 12
	while #corpses > CORPSE_CAP do
		local oldest = table.remove(corpses, 1)
		if oldest.model and oldest.model.Parent and oldest.model ~= model then
			local a = actors[oldest.model]
			if a then
				a.corpseUntil = os.clock() + 0.5 -- sink out almost immediately
			end
		end
	end
	task.delay(lifetime + 1.5, function()
		actors[model] = nil
		if model.Parent then
			model:Destroy()
		end
	end)
end


-- S11 FSM conformance: the spec names thirteen behaviour states. The tick already performs these
-- behaviours but never labelled them, which made live hostiles read nil-state and unverifiable.
-- The resolver derives the spec vocabulary from what the actor is actually doing this tick and
-- publishes it on every live hostile every tick. Priority order matters: transient combat states
-- outrank movement states, which outrank awareness states.
local function resolveSpecState(model: Model, actor: any): string
	if model:GetAttribute("Dead") then
		return "Dead"
	end
	if EnemyService.isStunned(model) then
		return "Stunned"
	end
	if model:GetAttribute("CallingUntil") ~= nil then
		return "CallReinforcements"
	end
	if actor.retreating == true then
		return "Retreat"
	end
	local now = os.clock()
	if actor.telegraphUntil and now < actor.telegraphUntil then
		return "Attack"
	end
	if actor.suppressingUntil and now < actor.suppressingUntil then
		return "Suppress"
	end
	local hasLiveTarget = actor.target ~= nil
		and actor.target.Character ~= nil
		and actor.target.Character:FindFirstChild("HumanoidRootPart") ~= nil
	if hasLiveTarget then
		if actor.coverPos ~= nil and actor.coverAt ~= nil and (now - actor.coverAt) < 6 then
			local root = model.PrimaryPart
			if root and (actor.coverPos - root.Position).Magnitude > 2 then
				return "TakeCover"
			end
		end
		if actor.flankSide ~= nil then
			local root = model.PrimaryPart
			local targetRoot = actor.target.Character:FindFirstChild("HumanoidRootPart")
			if root and targetRoot and ((targetRoot :: BasePart).Position - root.Position).Magnitude > (actor.def.attackRange or 40) * 1.2 then
				return "Flank"
			end
		end
		return "Advance"
	end
	-- no live target: awareness-driven states
	local conf = actor.confidence or 0
	if conf > 0.35 and actor.lastSeenPos ~= nil then
		return "Investigate"
	end
	if conf > 0.08 then
		return "Suspicious"
	end
	if actor.behavior == "Patrol" or actor.patrolling == true then
		return "Patrol"
	end
	return "Idle"
end


-- S11 scout beacon: FlankBeacon hostiles channel a visible reinforcement transmission when they
-- hold partial knowledge but cannot engage. The channel publishes TransmissionUntil so clients can
-- render the rising icon; taking damage or having a player close within 24 studs cancels it.
local SCOUT_CHANNEL_TIME = 4.0
local function tickScoutBeacon(model: Model, actor: any, def: any)
	if def.behavior ~= "FlankBeacon" then
		return
	end
	if actor.target ~= nil or model:GetAttribute("Dead") then
		-- challenged: cancel any running channel
		if actor.beaconUntil then
			actor.beaconUntil = nil
			model:SetAttribute("TransmissionUntil", nil)
			workspace:SetAttribute("GF_BeaconCancels", (workspace:GetAttribute("GF_BeaconCancels") or 0) + 1)
		end
		return
	end
	local conf = actor.confidence or 0
	if conf < 0.35 then
		return
	end
	local now = os.clock()
	-- damaged recently cancels: health dropped since channel start
	if actor.beaconUntil then
		local hp = tonumber(model:GetAttribute("Health")) or 0
		if hp < (actor.beaconStartHP or hp) then
			actor.beaconUntil = nil
			model:SetAttribute("TransmissionUntil", nil)
			workspace:SetAttribute("GF_BeaconCancels", (workspace:GetAttribute("GF_BeaconCancels") or 0) + 1)
			return
		end
		if now >= actor.beaconUntil then
			actor.beaconUntil = nil
			model:SetAttribute("TransmissionUntil", nil)
			local root = model.PrimaryPart
			if root then
				EnemyService.spawn("Rifleman", root.Position + Vector3.new(5, 0, 3))
				workspace:SetAttribute("GF_Reinforcements", (workspace:GetAttribute("GF_Reinforcements") or 0) + 1)
				workspace:SetAttribute("GF_BeaconCompletions", (workspace:GetAttribute("GF_BeaconCompletions") or 0) + 1)
				-- scout transmit escalates territorial threat (spec S11 threat triggers)
				workspace:SetAttribute("GF_ScoutTransmits", (workspace:GetAttribute("GF_ScoutTransmits") or 0) + 1)
			end
		end
		return
	end
	-- start a channel if cooled down
	if now >= (actor.beaconCooldownUntil or 0) then
		actor.beaconUntil = now + SCOUT_CHANNEL_TIME
		actor.beaconStartHP = tonumber(model:GetAttribute("Health")) or 0
		actor.beaconCooldownUntil = now + SCOUT_CHANNEL_TIME + 20
		model:SetAttribute("TransmissionUntil", actor.beaconUntil)
		workspace:SetAttribute("GF_BeaconChannels", (workspace:GetAttribute("GF_BeaconChannels") or 0) + 1)
	end
end

local function tickActor(model: Model, actor: any, dt: number)
	local def = actor.def
	local root = model.PrimaryPart
	if not root or not root.Parent then
		actors[model] = nil
		return
	end

	if model:GetAttribute("Dead") then
		if actor.deadAt == 0 then
			die(model, actor)
		end
		-- collapse: tip over in the first half second, then lie still until the corpse lifetime ends,
		-- when it sinks below the ground and is removed. No permanent body physics (parts anchored).
		local age = os.clock() - actor.deadAt
		if age < 0.5 then
			root.CFrame = root.CFrame * CFrame.Angles(math.rad(11), 0, 0) * CFrame.new(0, -0.05, 0)
		elseif actor.corpseUntil and os.clock() > actor.corpseUntil - 1.0 then
			root.CFrame = root.CFrame * CFrame.new(0, -0.12, 0)
		end
		return
	end

	-- S04-053: EMP briefly disables a hostile. GrenadeRuntime wrote EMPStunUntil and NOTHING read it, so
	-- the disable did nothing at all. Consumed here: while stunned the actor does not move or fire.
	if EnemyService.isStunned(model) then
		return
	end
	tickScoutBeacon(model, actor, def)
	local origin = root.Position
	tickSuppression(actor, dt)
	local prof = tacticalProfile(def)
	-- squad blackboard pull (spec section 24): members ingest the shared picture through their own
	-- perception — timestamps preserved, so a stale board entry never reads as fresh knowledge.
	-- periodic role reevaluation is bounded (internal cooldown) and event-driven.
	if actor.squad then
		NPCSquads.reevaluateRoles(actor.squad, function(m)
			local a = actors[m]
			return a and (ARCHETYPE[a.def.id] or "Default") or "Default"
		end)
		for player, report in pairs(actor.squad.reportedTargets) do
			if actor.perception and player.Character then
				NPCPerception.receiveReport(actor.perception, player, {
					position = report.position,
					velocity = Vector3.zero,
					observedAt = report.observedAt,
					confidence = report.confidence,
					uncertainty = 8,
					obsType = "report",
					threat = 0,
				})
			end
		end
	end
	local target, targetDist = perceiveTargets(model, origin, def, actor, dt)
	-- memory bridge: the legacy investigate/search/return FSM consumes lastSeenPos/confidence.
	-- Derive those from the richest current memory record so the FSM runs on legitimate,
	-- uncertainty-aware information (spec section 19) rather than perfect positions.
	local nowClock = os.clock()
	NPCPerception.cooldown(actor.perception, dt)
	do
		local bestMem: any = nil
		local bestConf = 0
		for player, mem in pairs(actor.perception.memory) do
			local c = NPCPerception.confidenceNow(mem, nowClock)
			if c > bestConf then
				bestConf = c
				bestMem = mem
			end
		end
		if bestMem then
			-- the investigate target is the ESTIMATED position: bounded velocity extrapolation,
			-- never perfect hidden tracking
			actor.lastSeenPos = NPCPerception.estimatePosition(bestMem, nowClock)
			actor.lastSeenAt = bestMem.observedAt + (5 - 4) -- approximate legacy timing semantics
			actor.confidence = bestConf
		else
			actor.lastSeenPos = nil
			actor.confidence = 0
		end
	end
	if target and target.Character then
		-- radio knowledge sharing (spec section 19/24): a fresh sighting propagates to nearby allies
		-- after a 0.5s radio delay as a REPORT — preserving the original observation timestamp and
		-- uncertainty. Receivers investigate a fuzzy area; nobody gets perfect positions by radio.
		local targetRoot3 = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot3 and actor.perception.memory[target] then
			local mem = actor.perception.memory[target]
			-- squad blackboard (spec section 24): explicit local reports with original timestamps.
			-- the board is the squad's shared picture — distribution, not truth override.
			if actor.squad then
				NPCSquads.postReport(actor.squad, target, mem.position, mem.observedAt, mem.confidence, model)
			end
			local myOrigin = origin
			task.delay(0.5, function()
				if not model.Parent or model:GetAttribute("Dead") then
					return -- spotter died or lost contact before the transmission completed
				end
				for other, otherActor in pairs(actors) do
					if other ~= model and other.Parent and other:GetAttribute("Dead") ~= true then
						local otherRoot = other.PrimaryPart
						if otherRoot and (otherRoot.Position - myOrigin).Magnitude <= 100 and otherActor.perception then
							NPCPerception.receiveReport(otherActor.perception, target, mem)
						end
					end
				end
			end)
		end
	end
	model:SetAttribute("PerceptionConfidence", math.floor((actor.confidence or 0) * 100) / 100)
	-- Sentries are destructible: a hostile engages a visible sentry when it is nearer than its player target.
	local sentry, sentryDist = nearestSentry(model, origin, def)
	if sentry then
		local playerRoot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local playerDist = playerRoot and (playerRoot.Position - origin).Magnitude or math.huge
		if sentryDist < playerDist then
			actor.target = nil
			local sentryPos = (sentry.PrimaryPart :: BasePart).Position
			local flatToSentry = (sentryPos - origin) * Vector3.new(1, 0, 1)
			if flatToSentry.Magnitude > 0.1 then
				actor.locomotion.aimYaw = NPCLocomotion.yawOf(flatToSentry)
			end
			if sentryDist > def.attackRange then
				navMove(actor, model, sentryPos, "combat", def.attackRange * 0.85, 3)
				return
			end
			NPCLocomotion.stop(actor.locomotion)
			local now = os.clock()
			if now >= actor.nextAttack and EnemyService.claimFireSlot(model) then
				actor.nextAttack = now + def.attackCooldown + (tonumber(def.recovery) or 0)
				local windUp = tonumber(def.telegraph) or 0.55
				ReplicatedStorage.GF.Remotes.EnemyTelegraph:FireAllClients(model, windUp)
				task.delay(windUp, function()
					EnemyService.releaseFireSlot(model)
					if model:GetAttribute("Dead") or not sentry.Parent then
						return
					end
					local burst = def.burst
					local shots = (type(burst) == "table" and tonumber(burst.count)) or 1
					local dmgMult = tonumber(model:GetAttribute("DamageMultiplier")) or 1
					ReplicatedStorage.GF.Remotes.EnemyFired:FireAllClients(model, sentryPos)
					EnemyService.damageSentry(sentry, def.damage * dmgMult * shots, def.id)
					debugAttr("GF_SentryShotsTaken", (workspace:GetAttribute("GF_SentryShotsTaken") or 0) + 1)
				end)
			end
			return
		end
	end
	-- Defence objects: when no player is visible, a hostile may turn on the objective itself. The
	-- structure is published by ObjectiveService, so this stays one attribute read per hostile per tick
	-- instead of a workspace scan. Measured need: every defend stage was a countdown nothing could end.
	if not target then
		local structureModel = workspace:GetAttribute("GF_DefenseModel")
		local folder = workspace:FindFirstChild("ActiveActors")
		local structure = nil
		if type(structureModel) == "string" and folder then
			local holder = folder:FindFirstChild(structureModel)
			local partName = workspace:GetAttribute("GF_DefensePart")
			if holder and type(partName) == "string" then
				structure = holder:FindFirstChild(partName)
			end
		end
		-- Only while the defence is actually being held: a squad that abandons the objective should find it
		-- waiting, not sacked. Measured: with no gate, eight hostiles took a 600 HP generator to zero in 22 s.
		if structure and structure:IsA("BasePart") and structure.Parent and structure:GetAttribute("GFDestroyed") ~= true and workspace:GetAttribute("GF_DefenseEngaged") == true then
			local toStructure = structure.Position - origin
			-- lineOfSight() rejects a hit that lands more than 3 studs from the aim point, which is correct
			-- for a humanoid-sized target and wrong for a 7x9x7 generator: the measured result was every
			-- hostile refusing to shoot the objective it was standing in front of. Raycast the structure
			-- itself instead and accept a hit on it or its own model.
			local sightParams = RaycastParams.new()
			sightParams.FilterType = Enum.RaycastFilterType.Exclude
			sightParams.FilterDescendantsInstances = { model }
			sightParams.IgnoreWater = true
			local sightHit = workspace:Raycast(origin, toStructure, sightParams)
			local structureVisible = sightHit ~= nil and (sightHit.Instance == structure or sightHit.Instance:IsDescendantOf(holder))
			if toStructure.Magnitude <= def.attackRange and structureVisible then
				NPCLocomotion.stop(actor.locomotion) -- structure in range: plant and fire
				if math.random() < 0.25 and os.clock() >= actor.nextAttack and EnemyService.claimFireSlot(model) then
					actor.nextAttack = os.clock() + def.attackCooldown
					-- windUp was previously undefined in this scope: any Marksman/Heavy reaching this
					-- branch errored out of tickActor and was permanently dropped from the actor table.
					local windUp = tonumber(def.chargeTime) or tonumber(def.telegraph) or 0.55
					ReplicatedStorage.GF.Remotes.EnemyTelegraph:FireAllClients(model, windUp)
					if def.chargeTime then
						model:SetAttribute("ChargingUntil", os.clock() + windUp)
						workspace:SetAttribute("GF_LastCharge", model.Name .. ":" .. tostring(windUp))
					end
					task.delay(windUp, function()
						EnemyService.releaseFireSlot(model)
						if model:GetAttribute("Dead") then
							return
						end
						if structure.Parent and structure:GetAttribute("GFDestroyed") ~= true then
							-- Structure fire is deliberately weaker than anti-personnel fire: measured at full damage, eight
							-- hostiles took a 600 HP generator from full to zero inside the defend window.
							require(script.Parent.CombatService).damageStructure(structure, def.damage * 0.25, nil)
							debugAttr("GF_StructureShots", (workspace:GetAttribute("GF_StructureShots") or 0) + 1)
						end
					end)
					return
				end
			end
		end
	end

	-- territorial leash (spec section 30): legitimate local pursuit is allowed, but a defensive
	-- squad never abandons its region indefinitely. beyond the leash the soldier breaks off —
	-- the memory of the target persists, so it re-engages if the player re-enters the territory.
	do
		local leashRadius = 130
		local fromHome = Vector3.new(origin.X - actor.home.X, 0, origin.Z - actor.home.Z).Magnitude
		if fromHome > leashRadius and not actor.retreating then
			actor.target = nil
			actor.engagementStarted = false
			actor.confidence = math.min(actor.confidence or 0, 0.15) -- low enough to trigger return
			model:SetAttribute("GFState", "Return")
		end
	end

	actor.target = target

	if not target then
		-- A target that is gone must not stay on the actor: GF_EnemiesTracked counted stale pointers
		-- (13 while the player stood on the station), which made it useless as a "who is hunting me" signal.
		actor.target = nil
		actor.engagementStarted = false
		-- FSM (S06-004): Investigate the last known position while confidence holds, Search around it
		-- on arrival, Return home when confidence decays below the give-up threshold, Guard/idle at home.
		local conf = actor.confidence or 0
		local seenAge = nowClock - (actor.lastSeenAt or 0)
		if actor.lastSeenPos and conf >= CONFIDENCE_GIVE_UP and seenAge <= SEARCH_MAX_AGE then
			local toSeen = actor.lastSeenPos - origin
			local flatSeen = Vector3.new(toSeen.X, 0, toSeen.Z)
			if flatSeen.Magnitude > 3 then
				-- Investigate: move to the last known position at full speed.
				model:SetAttribute("GFState", "Investigate")
				-- Suppress (S11): a ranged hostile with firm knowledge fires denial lanes at the
				-- last-known position while closing. Bounded by the shared fire-slot economy, no
				-- damage to anything — the lane is a readable tracer threat, not a free hit.
				if conf >= 0.5 and flatSeen.Magnitude <= def.attackRange * 1.5 and (def.attackRange or 0) >= 60 then
					local now = os.clock()
					if now >= (actor.nextSuppress or 0) and EnemyService.claimFireSlot(model) then
						actor.nextSuppress = now + 2.8 + math.random() * 1.4
						actor.suppressingUntil = now + 0.6
						local targetPos = actor.lastSeenPos + Vector3.new((math.random() - 0.5) * 6, 1.2, (math.random() - 0.5) * 6)
						ReplicatedStorage.GF.Remotes.EnemyTelegraph:FireAllClients(model, 0.5)
						task.delay(0.5, function()
							EnemyService.releaseFireSlot(model)
							if model.Parent and not model:GetAttribute("Dead") then
								ReplicatedStorage.GF.Remotes.EnemyFired:FireAllClients(model, targetPos)
								debugAttr("GF_SuppressionShots", (workspace:GetAttribute("GF_SuppressionShots") or 0) + 1)
							end
						end)
					end
				end
				actor.locomotion.aimYaw = nil -- face the direction of travel while investigating
				navMove(actor, model, actor.lastSeenPos, "relocate", 2.5, 2)
			else
				-- Search: small deterministic wander around the last known position while confidence decays.
				model:SetAttribute("GFState", "Search")
				if (actor.nextSearchStep or 0) <= nowClock then
					local angle = math.rad((nowClock * 137) % 360) -- deterministic-ish spread, no rng state needed
					actor.searchDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
					actor.nextSearchStep = nowClock + 0.9
				end
				if actor.searchDir then
					local probeDist = 4
					local candidate = root.Position + actor.searchDir * probeDist
					if (Vector3.new(candidate.X, 0, candidate.Z) - Vector3.new(actor.lastSeenPos.X, 0, actor.lastSeenPos.Z)).Magnitude <= SEARCH_RADIUS then
						actor.locomotion.aimYaw = nil
						NPCLocomotion.moveTo(actor.locomotion, candidate, "walk", 0.8)
					else
						actor.searchDir = -actor.searchDir
					end
				end
			end
			return
		end
		-- Return: confidence expired; drift home, then resume the squad's patrol.
		-- stale memory is consumed the moment the actor gives up: reaching this branch means any
		-- lastSeenPos is below the confidence threshold (a fresh one would have taken the
		-- investigate branch above). Clearing here lets hearGunfire write new positions again.
		actor.lastSeenPos = nil
		actor.lastSeenAt = nil
		local toHome = actor.home - origin
		if toHome.Magnitude > 4 then
			model:SetAttribute("GFState", "Return")
			actor.locomotion.aimYaw = nil
			navMove(actor, model, actor.home, "walk", 3, 1)
		else
			-- patrol (spec section 30): territorial military presence. squad members share a loop
			-- generated around their common home, each walking it with a positional phase offset —
			-- recognizable group movement without rigid formation lock. narrow passages compress
			-- naturally because each soldier navigates independently to its own phase point.
			if not actor.patrolLoop then
				actor.patrolLoop = generatePatrolLoop(actor.home)
				-- phase offset by squad membership order hash: stable spread along the loop
				actor.patrolIndex = 1 + (math.abs(math.floor(origin.X + origin.Z)) % math.max(1, #actor.patrolLoop))
			end
			local loop = actor.patrolLoop
			if loop and #loop > 0 then
				model:SetAttribute("GFState", "Patrol")
				-- scan pause (spec readability): soldiers halt at some waypoints and face outward —
				-- the patrol reads as soldiers watching their sector, not bots orbiting a track.
				if (actor.patrolPauseUntil or 0) > nowClock then
					local outward = Vector3.new(origin.X - actor.home.X, 0, origin.Z - actor.home.Z)
					if outward.Magnitude > 1 then
						actor.locomotion.aimYaw = NPCLocomotion.yawOf(outward)
					end
					NPCLocomotion.stop(actor.locomotion)
					return
				end
				local wp = loop[actor.patrolIndex]
				local flatToWp = Vector3.new(wp.X - origin.X, 0, wp.Z - origin.Z)
				if flatToWp.Magnitude < 3.5 then
					actor.patrolIndex = (actor.patrolIndex % #loop) + 1
					if math.random() < 0.35 then
						actor.patrolPauseUntil = nowClock + 2 + math.random() * 2.5
						return
					end
				end
				actor.locomotion.aimYaw = nil
				NPCLocomotion.moveTo(actor.locomotion, loop[actor.patrolIndex], "walk", 2.5)
			else
				model:SetAttribute("GFState", "Guard")
				actor.locomotion.aimYaw = nil
				NPCLocomotion.stop(actor.locomotion)
			end
		end
		return
	end
	-- stuck detection (spec section 15): intent-aware via the locomotion controller — locoStuck
	-- only engages when desired movement is significant but actual progress is not. A stationary
	-- shooter holding a fire position is never "stuck". Recovery follows the spec sequence:
	-- local correction (drop the cover claim) first, persistent failure retreats home — walked,
	-- never teleported.
	do
		local nowC = os.clock()
		if actor.locoStuck then
			actor.stuckSince = actor.stuckSince or nowC
		else
			actor.stuckSince = nil
		end
		if actor.stuckSince then
			local stuckFor = nowC - actor.stuckSince
			if stuckFor > 6 then
				actor.coverPos = nil
				actor.target = nil
				actor.engagementStarted = false
				actor.confidence = 0
				actor.stuckSince = nil
				NPCLocomotion.stop(actor.locomotion)
				model:SetAttribute("GFState", "Return")
				workspace:SetAttribute("GF_StuckRetreats", (workspace:GetAttribute("GF_StuckRetreats") or 0) + 1)
				return
			elseif stuckFor > 2 then
				actor.coverPos = nil
				workspace:SetAttribute("GF_StuckRecalcs", (workspace:GetAttribute("GF_StuckRecalcs") or 0) + 1)
			end
		end
	end
	model:SetAttribute("GFState", "Engage")
	if not actor.engagementStarted then
		actor.engagementStarted = true
		-- First tick of engagement: sample the difficulty reaction band once, so a hostile never
		-- instant-fires the moment it spots someone. cadence cannot shorten heavy/marksman warnings
		-- below 0.9s regardless (spec), which the telegraph path already enforces separately.
		local difficulty = "Normal"
		pcall(function()
			local mission = require(script.Parent.State).getMission()
			if mission and mission.difficulty then
				difficulty = mission.difficulty
			end
		end)
		local band = REACTION_BANDS[difficulty] or REACTION_BANDS.Normal
		local delay = band[1] + math.random() * (band[2] - band[1])
		-- commander influence (spec section 25): coordination speed scales with exp falloff —
		-- organization improves under leadership, never raw damage. soldiers near their officer
		-- react up to 25% faster; losing the officer visibly degrades this.
		local influence = NPCSquads.commanderInfluence(actor.squad, origin)
		delay = delay * math.clamp(1 - 0.25 * influence, 0.75, 1)
		local engNow = os.clock()
		if engNow < actor.nextAttack or actor.nextAttack == 0 then
			actor.nextAttack = engNow + delay
		end
		model:SetAttribute("ReactionDelay", math.floor(delay * 100) / 100)
	end

	local targetCharacter = target.Character
	local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then
		return
	end
	-- S06-015 flank routes: fast movers (Vanguard-type, speed 16+) approach through a flanking arc
	-- rather than the direct line — they pick a side once per engagement and swing wide before
	-- closing, so players face crossing pressure instead of a single-file conga line.
	-- flanking (spec section 22/24): alternative approaches are squad-limited — one flanker at a
	-- time per squad so the player faces coherent pressure instead of simultaneous abandons.
	if (def.speed or 13) >= 16 then
		if not actor.flankSide then
			local role = NPCSquads.roleOf(model)
			if (role == "flanker" or role == "engager") and NPCSquads.requestFlank(model) then
				actor.flankSide = (math.random() < 0.5) and 1 or -1
			end
		end
	else
		if actor.flankSide then
			NPCSquads.endFlank(model)
		end
		actor.flankSide = nil
	end

	local flat = (targetRoot.Position - origin) * Vector3.new(1, 0, 1)
	-- S06-015/016 cover behavior: a ranged hostile that is not yet firing claims a cover node — a
	-- position within 24 studs where world geometry breaks the target's line of sight. Nodes are
	-- claimed per-enemy so a squad spreads across distinct positions instead of stacking on one rock.
	-- While relocating it keeps facing the target; once the fire slot opens it sidesteps out to shoot.
	if flat.Magnitude > def.attackRange * 0.55 and (os.clock() < (actor.nextAttack or 0) - 0.4 or flat.Magnitude > def.attackRange) then
		-- cover commitment (spec sections 21/23): archetype base duration, extended while suppressed —
		-- pinned soldiers stay in cover rather than re-exposing; no rapid repetitive peeking.
		local coverHoldTime = prof.coverCommit * ((actor.suppression or 0) >= SUPPRESS_ACT and 2.2 or 1)
		if not actor.coverPos or (actor.coverPos - origin).Magnitude < 2 or (os.clock() - (actor.coverAt or 0)) > coverHoldTime then
			local bestPos, bestScore = nil, -1
			local perp = Vector3.new(-flat.Unit.Z, 0, flat.Unit.X)
			for _, side in ipairs({ 1, -1 }) do
				for _, reach in ipairs({ 8, 16, 24 }) do
					local cand = origin + perp * side * reach + flat.Unit * math.min(flat.Magnitude * 0.4, 12)
					-- cover test: geometry between candidate eye height and the target's chest
					local testParams = RaycastParams.new()
					testParams.FilterType = Enum.RaycastFilterType.Exclude
					testParams.FilterDescendantsInstances = { model, targetCharacter }
					testParams.IgnoreWater = true
					local eye = cand + Vector3.new(0, 2.5, 0)
					local chest = targetRoot.Position + Vector3.new(0, 1.5, 0)
					local coverHit = workspace:Raycast(eye, chest - eye, testParams)
					if coverHit then
						-- blocked sightline = cover; score prefers nearer nodes. squad blackboard
						-- reservations (spec section 21) replace the old proximity scan: claims are
						-- owned, expire, and release on death rather than being positional guesses.
						local claimed = NPCSquads.coverConflict(model, cand)
						local score = (claimed and 0 or 10) + (24 - reach)
						if score > bestScore then
							bestScore = score
							bestPos = cand
						end
					end
				end
			end
			if bestPos then
				NPCSquads.claimCover(model, bestPos)
				actor.coverPos = bestPos
				actor.coverAt = os.clock()
			end
		end
		if actor.coverPos then
			local toCover = (actor.coverPos - origin) * Vector3.new(1, 0, 1)
			if toCover.Magnitude > 1.5 then
				model:SetAttribute("GFState", "TakeCover")
				-- face the threat while relocating: upper body tracks the target, legs do the walking
				local targetCharacter2 = target and target.Character
				local targetRoot2 = targetCharacter2 and targetCharacter2:FindFirstChild("HumanoidRootPart")
				if targetRoot2 then
					local toT = (targetRoot2 :: BasePart).Position - origin
					actor.locomotion.aimYaw = NPCLocomotion.yawOf(toT)
				end
				NPCLocomotion.moveTo(actor.locomotion, actor.coverPos, "combat", 1.5)
				return
			end
		end
	end
	local distance = flat.Magnitude
	if distance < 0.1 then
		return
	end
	-- facing is owned by the locomotion controller: bounded damped turning toward the target
	-- rather than the old instantaneous lookAt snap.
	actor.locomotion.aimYaw = NPCLocomotion.yawOf(flat)

	local now = os.clock()

	if actor.telegraphUntil > now then
		-- hold the shot; player can break LOS or dodge out during the windup. The actor plants
		-- but keeps tracking with upper-body aim so the telegraph reads as a winding weapon.
		NPCLocomotion.stop(actor.locomotion)
		return
	end

	-- Behaviour layer: `def.behavior` existed in the enemy config and nothing read it, so every hostile was a
	-- stationary turret. Cover-type hostiles now slide laterally after a couple of shots and hold for a moment,
	-- which breaks the sight picture. No pathfinding: a fixed-direction strafe on the ground plane.
	if now < (actor.repositionUntil or 0) and actor.repositionDir then
		-- lateral repositioning: convert the fixed-duration slide into a single locomotion intent.
		-- the destination is projected ahead along the slide direction; arrival braking eases the
		-- stop instead of the old hard cut-off. upper body keeps the target in aim.
		local dir = actor.repositionDir :: Vector3
		if not actor.repositionGoal then
			local slideTime = math.max(0.2, (actor.repositionUntil or 0) - now)
			actor.repositionGoal = root.Position + dir * (def.speed * 0.55 * slideTime)
		end
		actor.locomotion.aimYaw = NPCLocomotion.yawOf(flat)
		NPCLocomotion.moveTo(actor.locomotion, actor.repositionGoal, "combat", 0.8)
		return
	end
	actor.repositionGoal = nil
	if distance > def.attackRange then
		-- approach through the locomotion controller with arrival braking at the engagement
		-- standoff. flanking fast movers first swing through a perpendicular arc waypoint, then
		-- close directly once the arc has them on the target's flank.
		if actor.flankSide and prof.flankArc > 0 and distance > def.attackRange * 1.6 then
			local perp = Vector3.new(-flat.Unit.Z, 0, flat.Unit.X) * actor.flankSide
			local arcPoint = origin + (flat.Unit * 0.55 + perp * 0.85 * prof.flankArc).Unit * math.min(distance * 0.6, 24)
			NPCLocomotion.moveTo(actor.locomotion, arcPoint, "combat", 2.5)
		else
			local targetPos = (targetRoot :: BasePart).Position
			navMove(actor, model, targetPos, "combat", def.attackRange * prof.preferredRange, 3)
		end
		return
	end
	-- archetype anti-close behavior (spec section 22/27): a soldier inside its minimum comfortable
	-- range falls back while facing the threat rather than accepting a bad fight. Marksmen feel this
	-- most strongly; vanguards not at all. Bounded: a fallback slide, not a rout.
	local minComfort = def.attackRange * prof.minRangeFrac
	if distance < minComfort and not (now < (actor.repositionUntil or 0)) then
		local away = -(flat.Unit)
		actor.repositionDir = away + Vector3.new(-flat.Unit.Z, 0, flat.Unit.X) * 0.4 * ((math.random() < 0.5) and 1 or -1)
		actor.repositionDir = actor.repositionDir.Unit
		actor.repositionUntil = now + 1.2
		actor.repositionGoal = nil
		workspace:SetAttribute("GF_Fallbacks", (workspace:GetAttribute("GF_Fallbacks") or 0) + 1)
		return -- next tick picks up the reposition intent below
	end
	-- in range: hold position and fire. movement intents stop; facing continues via aimYaw.
	NPCLocomotion.stop(actor.locomotion)

	-- S11 officer energy sweep: the signature crowd-control attack — a clearly telegraphed radial
	-- burst that punishes clustered squads. Long windup (1.6s) with a published attribute clients
	-- render as a growing ring; dodging out of the radius is the counterplay.
	if def.behavior == "Commander" or def.id == "Officer" then
		if distance <= 34 and now >= (actor.nextSweep or 0) then
			actor.nextSweep = now + 14 + math.random() * 6
			actor.sweepUntil = now + 1.6
			model:SetAttribute("SweepTelegraphUntil", actor.sweepUntil)
			local sweepOrigin = Vector3.new(origin.X, origin.Y, origin.Z)
			task.delay(1.6, function()
				if model:GetAttribute("Dead") or not model.Parent then
					return
				end
				model:SetAttribute("SweepTelegraphUntil", nil)
				workspace:SetAttribute("GF_OfficerSweeps", (workspace:GetAttribute("GF_OfficerSweeps") or 0) + 1)
				ReplicatedStorage.GF.Remotes.EnemyFired:FireAllClients(model, sweepOrigin + Vector3.new(0, 1, 0))
				for _, plr in ipairs(Players:GetPlayers()) do
					local char = plr.Character
					local plrRoot = char and char:FindFirstChild("HumanoidRootPart")
					if plrRoot and ((plrRoot :: BasePart).Position - sweepOrigin).Magnitude <= 30 then
						local hum = char:FindFirstChildOfClass("Humanoid")
						if hum and hum.Health > 0 then
							workspace:SetAttribute("GF_SweepHits", (workspace:GetAttribute("GF_SweepHits") or 0) + 1)
							VitalsService.applyDamage(plr, 24 * (tonumber(model:GetAttribute("DamageMultiplier")) or 1), "OfficerSweep", sweepOrigin, model)
						end
					end
				end
			end)
		end
	end
	-- Fairness rule: only a couple of hostiles may be firing at once. Measured at the objective, four of them put
	-- 22 hits into a stationary player in seven seconds, which is a firing squad rather than a fight.
	if now >= actor.nextAttack and EnemyService.claimFireSlot(model) then
		local auraRate = EnemyService.auraRate(model)
		model:SetAttribute("AuraRate", auraRate)
		local cadenceRate = tonumber(model:GetAttribute("CadenceRate")) or 1
		actor.nextAttack = now + ((def.attackCooldown + (tonumber(def.recovery) or 0)) * auraRate) / math.max(0.1, cadenceRate)
		local windUp = tonumber(def.chargeTime) or tonumber(def.telegraph) or 0.55
	actor.telegraphUntil = now + windUp
	if def.chargeTime then
		model:SetAttribute("ChargingUntil", now + windUp)
		workspace:SetAttribute("GF_LastCharge", model.Name .. ":" .. tostring(windUp))
	end
		actor.telegraphTarget = target
		ReplicatedStorage.GF.Remotes.EnemyTelegraph:FireAllClients(model, windUp)
		task.delay(windUp, function()
		debugAttr("GF_LastAttackAttempt", "entry")
			-- the fire slot must release on EVERY exit path: early returns previously leaked it,
			-- and since slots cap at 2 globally, two leaked slots silenced all hostile fire for 3s.
			if model:GetAttribute("Dead") then
				EnemyService.releaseFireSlot(model)
				return
			end
			local stillTarget = target.Character
			local stillRoot = stillTarget and stillTarget:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not stillRoot then
				EnemyService.releaseFireSlot(model)
				return
			end
			if not lineOfSight(root.Position, stillRoot.Position, { model, stillTarget }) then
				debugAttr("GF_LastAttackAttempt", "los-fail")
				EnemyService.releaseFireSlot(model)
				return
			end
			debugAttr("GF_LastAttackAttempt", "los-pass")
			local d = (stillRoot.Position - root.Position).Magnitude
			if d > def.attackRange * 1.35 then
				EnemyService.releaseFireSlot(model)
				return
			end
			-- Burst fire: the authored patterns are 8x3, 6x4, 32x1, 38x1 and 12x2.
			local burst = def.burst
			local shots = (type(burst) == "table" and tonumber(burst.count)) or 1
			local interval = (type(burst) == "table" and tonumber(burst.interval)) or 0
			for shot = 1, shots do
				if model:GetAttribute("Dead") then
					break
				end
				local liveRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
				if not liveRoot or (liveRoot.Position - root.Position).Magnitude > def.attackRange * 1.35 then
					break
				end
				actor.lastFiredAt = os.clock()
				-- Hit resolution (S06-028/029/030): per-shot probability at preferred range falling off with
				-- distance; a rolling target consistently dodges aimed fire; a target that broke line of
				-- sight since the telegraph is fully safe. Misses still visibly animate - the tracer goes
				-- wide - so suppression reads as suppression rather than silence.
				local liveCharacter = target.Character
				local rolling = liveCharacter and liveCharacter:GetAttribute("Rolling") == true
				local dist = (liveRoot.Position - root.Position).Magnitude
				local preferred = def.attackRange * 0.6
				local baseProb = tonumber(def.hitProb) or 0.5
				local rangeFactor = dist <= preferred and 1 or math.max(0.35, 1 - (dist - preferred) / math.max(1, def.attackRange - preferred))
				local hitChance = baseProb * rangeFactor
				local blocked = not lineOfSight(root.Position, liveRoot.Position, { model, liveCharacter })
				actor.rngCounter = (actor.rngCounter or 0) + 1
				local roll = (math.sin((actor.rngCounter * 12.9898) + (model:GetAttribute("SpawnSeed") or 0)) * 43758.5453) % 1
				local isHit = (not rolling) and (not blocked) and (roll < hitChance)
				if isHit then
					ReplicatedStorage.GF.Remotes.EnemyFired:FireAllClients(model, liveRoot.Position)
					debugAttr("GF_LastShotPos", liveRoot.Position)
					local dmgMult = tonumber(model:GetAttribute("DamageMultiplier")) or 1
					VitalsService.applyDamage(target, def.damage * dmgMult, def.id, liveRoot.Position, model)
					debugAttr("GF_LastAttackAttempt", "hit")
					debugAttr("GF_EnemyHits", (workspace:GetAttribute("GF_EnemyHits") or 0) + 1)
				else
					-- visible miss: tracer lands wide of the target so the shot reads as a near miss
					local missOffset = Vector3.new((math.random() - 0.5) * 8, math.random() * 3, (math.random() - 0.5) * 8)
					ReplicatedStorage.GF.Remotes.EnemyFired:FireAllClients(model, liveRoot.Position + missOffset)
					debugAttr("GF_LastAttackAttempt", rolling and "dodged" or (blocked and "cover" or "miss"))
					debugAttr("GF_EnemyMisses", (workspace:GetAttribute("GF_EnemyMisses") or 0) + 1)
				end
				if interval > 0 and shot < shots then
					task.wait(interval)
				end
			end
			EnemyService.releaseFireSlot(model)
			actor.shotsSinceMove = (actor.shotsSinceMove or 0) + 1
			local wantsCover = string.find(string.lower(actor.behavior or ""), "cover") ~= nil
				or string.find(string.lower(actor.behavior or ""), "guard") ~= nil
			-- reposition cadence (spec section 27): how many shots before sliding again scales with
			-- archetype urgency — vanguards skate constantly, heavies plant like turrets.
			local moveThreshold = math.max(1, math.round(3 - prof.repositionUrgency * 2.5))
			if wantsCover and actor.shotsSinceMove >= moveThreshold then
				local side = (math.random() < 0.5) and 1 or -1
				local perp = Vector3.new(-(stillRoot.Position - root.Position).Unit.Z, 0, (stillRoot.Position - root.Position).Unit.X) * side
				-- retreat behavior (spec section 23 morale-lite): below the archetype's retreat
				-- threshold a wounded soldier's slides bias away from the threat — falling back
				-- while fighting, not routing. heavies/vanguards never do (threshold 0).
				local hum = model:FindFirstChildOfClass("Humanoid")
				local hpFrac = hum and hum.Health / math.max(1, hum.MaxHealth) or 1
				local retreatBias = Vector3.zero
				if hpFrac < prof.retreatHpFrac then
					retreatBias = -(stillRoot.Position - root.Position).Unit * 0.6
				end
				actor.repositionDir = (perp.Unit + retreatBias).Unit
				actor.repositionUntil = os.clock() + 1.4
				actor.shotsSinceMove = 0
				workspace:SetAttribute("GF_Repositions", (workspace:GetAttribute("GF_Repositions") or 0) + 1)
			end
		end)
	elseif now >= actor.nextAttack then
		-- Denied a firing slot. A queued hostile that just stands there reads as broken, so it sidesteps instead -
		-- this is also the only branch that moves hostiles that never win the slot.
		actor.holdsSinceMove = (actor.holdsSinceMove or 0) + 1
		if actor.holdsSinceMove >= 2 then
			local side = (math.random() < 0.5) and 1 or -1
			local toUs = (targetRoot.Position - root.Position)
			local perp = Vector3.new(-toUs.Z, 0, toUs.X)
			if perp.Magnitude > 0.1 then
				actor.repositionDir = perp.Unit * side
				actor.repositionUntil = os.clock() + 1.1
			end
			actor.holdsSinceMove = 0
			workspace:SetAttribute("GF_Repositions", (workspace:GetAttribute("GF_Repositions") or 0) + 1)
		end
	end
end

-- Simultaneous-fire budget: at most MAX_FIRING hostiles may be mid-attack at once.
local MAX_FIRING = 2
local firing: { [Model]: number } = {}

-- Commander aura: +10% fire rate for allies within 45 studs, no stacking (single nearest Officer is
-- enough), and it disappears the moment the Officer dies because it reads live models each call.
function EnemyService.auraRate(model: Model): number
	local selfPosition = model.PrimaryPart and model.PrimaryPart.Position
	if not selfPosition then
		return 1
	end
	for other in pairs(actors) do
		if other ~= model and other.Parent and other:GetAttribute("Dead") ~= true and other.Name == "Officer" then
			local part = other.PrimaryPart
			if part and (part.Position - selfPosition).Magnitude <= 45 then
				return 0.9
			end
		end
	end
	return 1
end

function EnemyService.claimFireSlot(model: Model): boolean
	local now = os.clock()
	for other, at in pairs(firing) do
		if not other.Parent or now - at > 3 then
			firing[other] = nil
		end
	end
	if firing[model] then
		return false
	end
	local count = 0
	for _ in pairs(firing) do
		count += 1
	end
	if count >= MAX_FIRING then
		debugAttr("GF_FireSlotsHeld", count)
		return false
	end
	firing[model] = now
	debugAttr("GF_FireSlotsHeld", count + 1)
	return true
end

function EnemyService.releaseFireSlot(model: Model)
	firing[model] = nil
end

-- Hearing (S06-008): unsuppressed gunfire within HEARING_RANGE alerts a hostile for several seconds -
-- alerted hostiles perceive in all directions and investigate the noise position if idle.
function EnemyService.hearGunfire(position: Vector3, player: Player?)
	pcall(function()
		require(script.Parent.EncounterDirector).noteGunfire()
	end)
	local now = os.clock()
	for model, actor in pairs(actors) do
		if model.Parent and model:GetAttribute("Dead") ~= true and model.PrimaryPart then
			local dist = (model.PrimaryPart.Position - position).Magnitude
			if dist <= HEARING_RANGE then
				actor.alertedUntil = now + 8
				-- auditory perception (spec section 18): approximate source with distance-scaled
				-- spatial error and loudness attenuation — never exact positions by sound alone.
				if actor.perception then
					local loudness = math.clamp(1 - dist / HEARING_RANGE, 0.15, 1)
					NPCPerception.hearEvent(actor.perception, position, dist, loudness, player)
				end
				-- nearby gunfire is suppressive pressure even when it misses: rounds cracking within
				-- a few studs of the position are what pins soldiers (spec section 23).
				if dist <= 18 then
					addSuppression(actor, 0.09 * (1 - dist / 18), tacticalProfile(actor.def))
				end
				workspace:SetAttribute("GF_AlertedCount", (workspace:GetAttribute("GF_AlertedCount") or 0) + 1)
			end
		end
	end
end

-- Damage threat memory (S06-013 recentThreat): scoring prefers players who recently hurt the actor.
function EnemyService.noteThreat(model: Model, player: Player)
	local actor = actors[model]
	if actor then
		actor.recentThreat = actor.recentThreat or {}
		actor.recentThreat[player] = os.clock()
		actor.alertedUntil = os.clock() + 8
		-- damage awareness (spec section 17): pain is unambiguous — the soldier knows roughly
		-- where the fire came from without needing to see the shooter.
		if actor.perception and player.Character then
			local shooterRoot = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if shooterRoot then
				NPCPerception.noteDamage(actor.perception, player, shooterRoot.Position)
			end
		end
		-- suppression impulse (spec section 23): actually taking a hit is the strongest pressure event
		addSuppression(actor, 0.45, tacticalProfile(actor.def))
	end
end

-- Commander relay call. Spec: a 2 s call when a relay is active; death clears the pending call.
-- Kept out of tickActor so the attack path stays untouched.
local calls = {}
local relayCallUsed = false

function EnemyService.resetCalls()
	relayCallUsed = false
	workspace:SetAttribute("GF_RelayCallUsed", false)
end
local CALL_TIME = 2
local CALL_RANGE = 70


debugAttr = function(key: string, value: any)
	if workspace:GetAttribute("GF_DebugEnemy") == true then
		workspace:SetAttribute(key, value)
	end
end

function EnemyService.callState()
	local rows = {}
	for model, state in pairs(calls) do
		rows[#rows + 1] = (model.Name or "?") .. ":" .. tostring(state.cancelled and "cancelled" or (state.at and "pending" or "idle"))
	end
	return table.concat(rows, ",")
end

function EnemyService.startCalls()
	task.spawn(function()
		local cachedRelay: Instance? = nil
		while true do
			task.wait(0.5)
			local relay = cachedRelay
			if not relay or relay.Parent == nil then
				relay = nil
				for _, d in ipairs(workspace:GetDescendants()) do
					if d:GetAttribute("GFInteract") == "Relay" then
						relay = d
						break
					end
				end
				cachedRelay = relay
			end
			for model in pairs(actors) do
				if model.Name == "Officer" then
					local live = model.Parent ~= nil and model:GetAttribute("Dead") ~= true
					local state = calls[model]
					if not live then
						if state and state.at and not state.cancelled then
							state.cancelled = true
							workspace:SetAttribute("GF_CallCancelled", (workspace:GetAttribute("GF_CallCancelled") or 0) + 1)
						end
						calls[model] = state or { cancelled = true }
					elseif relay and model.PrimaryPart and not (state and state.done) then
						local distance = (model.PrimaryPart.Position - relay.Position).Magnitude
						if distance <= CALL_RANGE then
							state = state or {}
							calls[model] = state
							if not state.at and not state.cancelled and not relayCallUsed then
								state.at = os.clock() + CALL_TIME
								model:SetAttribute("CallingUntil", state.at)
								workspace:SetAttribute("GF_LastCall", model.Name .. ":started")
							elseif state.at and not state.done and os.clock() >= state.at then
								if relayCallUsed then
									state.done = true
									state.cancelled = true
								else
								state.done = true
								relayCallUsed = true
								workspace:SetAttribute("GF_RelayCallUsed", true)
								model:SetAttribute("CallingUntil", nil)
								local centre = model.PrimaryPart.Position
								EnemyService.spawn("Rifleman", centre + Vector3.new(4, 0, 2))
								EnemyService.spawn("Rifleman", centre + Vector3.new(-4, 0, 2))
								workspace:SetAttribute("GF_Reinforcements", (workspace:GetAttribute("GF_Reinforcements") or 0) + 2)
								workspace:SetAttribute("GF_LastCall", model.Name .. ":reinforcements")
								workspace:SetAttribute("GF_CallCompletedBy", tostring(workspace:GetAttribute("GF_CallCompletedBy") or "") .. model.Name .. "@" .. string.format("%.1f", os.clock()) .. ";")
								end
							end
						end
					end
				end
			end
			workspace:SetAttribute("GF_CallState", EnemyService.callState())
		end
	end)
end

function EnemyService.start()
	EnemyService.startCalls()
	-- Locomotion loop (spec section 8/11): movement integration is decoupled from the decision
	-- tick. Position/velocity/facing update every frame through NPCLocomotion — the 5Hz tactical
	-- layer only submits intents (moveTo/followPath/stop/aimYaw). One writer owns each root.
	local frameCount = 0
	RunService.Heartbeat:Connect(function(dt)
		if dt > 0.1 then
			dt = 0.1
		end
		frameCount += 1
		-- neighbor positions for separation, refreshed every 3rd frame to bound the O(n^2) pass
		if frameCount % 3 == 1 then
			local positions = {}
			for model, actor in pairs(actors) do
				local root = model.PrimaryPart
				if model.Parent and root and not model:GetAttribute("Dead") then
					positions[model] = root.Position
				end
			end
			for model, actor in pairs(actors) do
				local myPos = positions[model]
				if not myPos then
					continue
				end
				local near = {}
				for other, otherPos in pairs(positions) do
					if other ~= model then
						local d = (otherPos - myPos).Magnitude
						if d < 9 then
							near[#near + 1] = { position = otherPos, radius = 1.6 }
						end
					end
				end
				actor.locoNeighbors = near
			end
		end
		for model, actor in pairs(actors) do
			local root = model.PrimaryPart
			if not model.Parent or not root or not actor.locomotion then
				continue
			end
			if model:GetAttribute("Dead") then
				continue -- death presentation owns the root once the actor is dead
			end
			if EnemyService.isStunned(model) then
				continue -- EMP freeze: intents are stateful, so stepping here would keep moving
			end
			local stuck = NPCLocomotion.step(
				actor.locomotion,
				locoProfile(actor.def),
				root,
				dt,
				actor.locoNeighbors or {},
				{ model },
				actor.groundOffset or 3.1
			)
			actor.locoStuck = stuck
		end
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TICK then
			return
		end
		local step = accumulator
		accumulator = 0
		local engaged, withTarget = 0, 0
		for model, a in pairs(actors) do
		local liveTarget = a.target and a.target.Character and a.target.Character:FindFirstChild("HumanoidRootPart")
		local closeEnough = liveTarget ~= nil and model.PrimaryPart ~= nil and (liveTarget.Position - model.PrimaryPart.Position).Magnitude <= 260
		if closeEnough then withTarget += 1 end
			if a.lastFiredAt and os.clock() - a.lastFiredAt <= 3 then engaged += 1 end
		end
		workspace:SetAttribute("GF_EnemiesEngaged", engaged)
		workspace:SetAttribute("GF_EnemiesTracked", withTarget)
		-- scheduler: every actor thinks every tick. The old 14-actor hard break starved actors
		-- deterministically (no rotation). Cost is bounded by the population cap; tick duration
		-- is published so Stage 10 simulation tiering works from measurement rather than guesses.
		local tickStart = os.clock()
		local ticked = 0
		for model, actor in actors do
			ticked += 1
			local ok, err = pcall(tickActor, model, actor, step)
			if not ok then
				-- error tolerance: transient failures (a target's character mid-respawn, a raycast
				-- against a half-streamed world) must not permanently kill the brain. three strikes
				-- in a row before the actor is dropped; a clean tick resets the count.
				actor.tickErrors = (actor.tickErrors or 0) + 1
				warn("[GF] enemy tick error (" .. actor.tickErrors .. "): " .. tostring(err))
				if actor.tickErrors >= 3 then
					NPCNavigation.cleanup(model)
					actors[model] = nil
				end
			else
				actor.tickErrors = 0
				if model.Parent then
					model:SetAttribute("GFState", resolveSpecState(model, actor))
				end
			end
		end
		workspace:SetAttribute("GF_AITickMs", math.floor((os.clock() - tickStart) * 1000 * 100) / 100)
		workspace:SetAttribute("GF_AITicked", ticked)
	end)
end

function EnemyService.clearAll()
	for model in actors do
		if model.Parent then
			model:Destroy()
		end
	end
	actors = {}
	for _, bossName in ipairs({ "BastionWalker", "HighMarshalVeyr" }) do
		local actors = workspace:FindFirstChild("ActiveActors")
		local boss = (actors and actors:FindFirstChild(bossName)) or workspace:FindFirstChild(bossName)
		if boss then
			boss:Destroy()
			workspace:SetAttribute("GF_BossCleared", bossName)
		end
	end
end

function EnemyService.engaged(): number
	local n = 0
	for _, actor in pairs(EnemyService.debugActors and EnemyService.debugActors() or {}) do
		if actor.target then
			n += 1
		end
	end
	return n
end

function EnemyService.debugActors()
	return actors
end

function EnemyService.count(): number
	local n = 0
	for model in actors do
		if model:GetAttribute("Dead") ~= true then
			n += 1
		end
	end
	return n
end

require(script.Parent.EnemyAnimation)

return EnemyService

