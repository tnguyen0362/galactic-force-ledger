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
local ArtService = require(ServerScriptService.GF.Services.ArtService)

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
	local target, targetDist = nearestVisiblePlayer(model, origin, def, actor)
	-- Perception bookkeeping: fresh sightings pin exact position; lost targets decay by exp(-age/4).
	local nowClock = os.clock()
	if target then
		actor.lastSeenPos = target.Character and target.Character:FindFirstChild("HumanoidRootPart") and (target.Character:FindFirstChild("HumanoidRootPart") :: BasePart).Position or actor.lastSeenPos
		actor.lastSeenAt = nowClock
		-- S06-011 radio knowledge: a fresh sighting is shared with same-group hostiles within 100 studs
		-- after a 0.5s radio delay. What propagates is a jittered, partial-confidence estimate — the
		-- receiver investigates the area rather than snapping onto exact omniscient tracking.
		if (actor.confidence or 0) < 0.9 and actor.lastSeenPos then
			local seenPos = actor.lastSeenPos
			local myOrigin = origin
			task.delay(0.5, function()
				for other, otherActor in pairs(actors) do
					if other ~= model and other.Parent and other:GetAttribute("Dead") ~= true then
						local otherRoot = other.PrimaryPart
						if otherRoot and (otherRoot.Position - myOrigin).Magnitude <= 100 then
							if (otherActor.confidence or 0) < 0.6 then
								local jitter = Vector3.new((math.random() - 0.5) * 14, 0, (math.random() - 0.5) * 14)
								otherActor.lastSeenPos = seenPos + jitter
								otherActor.lastSeenAt = os.clock()
								otherActor.confidence = math.max(otherActor.confidence or 0, 0.55)
							end
						end
					end
				end
			end)
		end
		actor.confidence = 1
	else
		local age = nowClock - (actor.lastSeenAt or 0)
		actor.confidence = if actor.lastSeenAt then math.exp(-age / CONFIDENCE_TAU) else 0
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
				root.CFrame = CFrame.lookAt(origin, origin + flatToSentry.Unit, Vector3.yAxis)
			end
			if sentryDist > def.attackRange then
				root.CFrame = root.CFrame + flatToSentry.Unit * math.min(def.speed * dt, sentryDist - def.attackRange * 0.85)
				return
			end
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
					workspace:SetAttribute("GF_SentryShotsTaken", (workspace:GetAttribute("GF_SentryShotsTaken") or 0) + 1)
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
				if math.random() < 0.25 and os.clock() >= actor.nextAttack and EnemyService.claimFireSlot(model) then
					actor.nextAttack = os.clock() + def.attackCooldown
					ReplicatedStorage.GF.Remotes.EnemyTelegraph:FireAllClients(model, windUp)
	if def.chargeTime then
		model:SetAttribute("ChargingUntil", os.clock() + windUp)
		workspace:SetAttribute("GF_LastCharge", model.Name .. ":" .. tostring(windUp))
	end
					task.delay(windUp, function()
						if model:GetAttribute("Dead") then
							return
						end
						if structure.Parent and structure:GetAttribute("GFDestroyed") ~= true then
							-- Structure fire is deliberately weaker than anti-personnel fire: measured at full damage, eight
							-- hostiles took a 600 HP generator from full to zero inside the defend window.
							require(script.Parent.CombatService).damageStructure(structure, def.damage * 0.25, nil)
							workspace:SetAttribute("GF_StructureShots", (workspace:GetAttribute("GF_StructureShots") or 0) + 1)
						end
					end)
					EnemyService.releaseFireSlot(model)
					return
				end
			end
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
								workspace:SetAttribute("GF_SuppressionShots", (workspace:GetAttribute("GF_SuppressionShots") or 0) + 1)
							end
						end)
					end
				end
				local step = def.speed * dt
				root.CFrame = root.CFrame + flatSeen.Unit * math.min(step, flatSeen.Magnitude)
			else
				-- Search: small deterministic wander around the last known position while confidence decays.
				model:SetAttribute("GFState", "Search")
				if (actor.nextSearchStep or 0) <= nowClock then
					local angle = math.rad((nowClock * 137) % 360) -- deterministic-ish spread, no rng state needed
					actor.searchDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
					actor.nextSearchStep = nowClock + 0.9
				end
				if actor.searchDir then
					local step = def.speed * 0.45 * dt
					local candidate = root.Position + actor.searchDir * step
					if (Vector3.new(candidate.X, 0, candidate.Z) - Vector3.new(actor.lastSeenPos.X, 0, actor.lastSeenPos.Z)).Magnitude <= SEARCH_RADIUS then
						root.CFrame = root.CFrame + actor.searchDir * step
					else
						actor.searchDir = -actor.searchDir
					end
				end
			end
			return
		end
		-- Return: confidence expired; drift home, then Guard idle.
		local toHome = actor.home - origin
		if toHome.Magnitude > 4 then
			model:SetAttribute("GFState", "Return")
			local step = def.speed * 0.5 * dt
			root.CFrame = root.CFrame + toHome.Unit * math.min(step, toHome.Magnitude)
		else
			model:SetAttribute("GFState", "Guard")
		end
		return
	end
	-- S06-019 stuck detection: track positional progress. If the actor wanted to move but covered
	-- <0.5 studs over 2s it is stuck — recalculate by clearing its cover claim and picking a fresh
	-- approach offset. If still stuck after 6s, retreat toward home (a safe reachable node) instead
	-- of grinding against geometry forever. No visible teleporting: retreat is walked.
	do
		local nowC = os.clock()
		if actor.lastPos then
			local moved = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(actor.lastPos.X, 0, actor.lastPos.Z)).Magnitude
			if moved < 0.05 then
				actor.stuckSince = actor.stuckSince or nowC
			else
				actor.stuckSince = nil
				actor.stuckLevel = 0
			end
		end
		actor.lastPos = root.Position
		if actor.stuckSince then
			local stuckFor = nowC - actor.stuckSince
			if stuckFor > 6 then
				-- retreat: walk home, clear all engagement memory — the fight is abandoned
				actor.coverPos = nil
				actor.target = nil
				actor.engagementStarted = false
				actor.confidence = 0
				actor.stuckSince = nil
				model:SetAttribute("GFState", "Return")
				workspace:SetAttribute("GF_StuckRetreats", (workspace:GetAttribute("GF_StuckRetreats") or 0) + 1)
				return
			elseif stuckFor > 2 then
				-- recalc: drop the current cover claim so the next tick picks a fresh node
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
	if (def.speed or 13) >= 16 then
		if not actor.flankSide then
			actor.flankSide = (math.random() < 0.5) and 1 or -1
		end
	else
		actor.flankSide = nil
	end

	local flat = (targetRoot.Position - origin) * Vector3.new(1, 0, 1)
	-- S06-015/016 cover behavior: a ranged hostile that is not yet firing claims a cover node — a
	-- position within 24 studs where world geometry breaks the target's line of sight. Nodes are
	-- claimed per-enemy so a squad spreads across distinct positions instead of stacking on one rock.
	-- While relocating it keeps facing the target; once the fire slot opens it sidesteps out to shoot.
	if flat.Magnitude > def.attackRange * 0.55 and (os.clock() < (actor.nextAttack or 0) - 0.4 or flat.Magnitude > def.attackRange) then
		if not actor.coverPos or (actor.coverPos - origin).Magnitude < 2 or (os.clock() - (actor.coverAt or 0)) > 6 then
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
						-- blocked sightline = cover; score prefers nearer nodes and ones no squadmate holds
						local claimed = false
						for other, otherActor in pairs(actors) do
							if other ~= model and other.Parent and otherActor.coverPos and (otherActor.coverPos - cand).Magnitude < 4 then
								claimed = true
								break
							end
						end
						local score = (claimed and 0 or 10) + (24 - reach)
						if score > bestScore then
							bestScore = score
							bestPos = cand
						end
					end
				end
			end
			if bestPos then
				actor.coverPos = bestPos
				actor.coverAt = os.clock()
			end
		end
		if actor.coverPos then
			local toCover = (actor.coverPos - origin) * Vector3.new(1, 0, 1)
			if toCover.Magnitude > 1.5 then
				model:SetAttribute("GFState", "TakeCover")
				root.CFrame = root.CFrame + toCover.Unit * math.min(def.speed * dt, toCover.Magnitude)
				return
			end
		end
	end
	local distance = flat.Magnitude
	if distance < 0.1 then
		return
	end
	root.CFrame = CFrame.lookAt(origin, origin + flat.Unit, Vector3.yAxis)

	local now = os.clock()

	if actor.telegraphUntil > now then
		if actor.telegraphTarget == target and distance <= def.attackRange * 1.25 then
			-- hold the shot; player can break LOS or dodge out during the windup
		end
		return
	end

	-- Behaviour layer: `def.behavior` existed in the enemy config and nothing read it, so every hostile was a
	-- stationary turret. Cover-type hostiles now slide laterally after a couple of shots and hold for a moment,
	-- which breaks the sight picture. No pathfinding: a fixed-direction strafe on the ground plane.
	if now < (actor.repositionUntil or 0) and actor.repositionDir then
		local dir = actor.repositionDir :: Vector3
		local slide = dir * (def.speed * 0.55 * dt)
		local groundParams = RaycastParams.new()
		groundParams.FilterType = Enum.RaycastFilterType.Exclude
		groundParams.FilterDescendantsInstances = { model }
		local ahead = root.Position + slide + Vector3.new(0, 12, 0)
		local hit = workspace:Raycast(ahead, Vector3.new(0, -40, 0), groundParams)
		root.CFrame = CFrame.lookAt(hit and Vector3.new(ahead.X, hit.Position.Y + root.Size.Y / 2, ahead.Z) or (root.Position + slide), targetRoot.Position, Vector3.yAxis)
		return
	end

	if distance > def.attackRange then
		local step = def.speed * dt
		-- flank arc: a flanking hostile blends a perpendicular swing into its approach while still
		-- outside 1.6x attack range, then closes directly once the arc has it on the target's side.
		local approachDir = flat.Unit
		if actor.flankSide and distance > def.attackRange * 1.6 then
			local perp = Vector3.new(-flat.Unit.Z, 0, flat.Unit.X) * actor.flankSide
			approachDir = (flat.Unit * 0.55 + perp * 0.85).Unit
		end
		local move = approachDir * math.min(step, distance - def.attackRange * 0.85)
		root.CFrame = root.CFrame + move
		return
	end

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
							VitalsService.applyDamage(plr, 24 * (tonumber(model:GetAttribute("DamageMultiplier")) or 1), "OfficerSweep", sweepOrigin)
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
		workspace:SetAttribute("GF_LastAttackAttempt", "entry")
			if model:GetAttribute("Dead") then
				return
			end
			local stillTarget = target.Character
			local stillRoot = stillTarget and stillTarget:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not stillRoot then
				return
			end
			if not lineOfSight(root.Position, stillRoot.Position, { model, stillTarget }) then
				return
			workspace:SetAttribute("GF_LastAttackAttempt", "los-fail")
			end
			workspace:SetAttribute("GF_LastAttackAttempt", "los-pass")
			local d = (stillRoot.Position - root.Position).Magnitude
			if d > def.attackRange * 1.35 then
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
					workspace:SetAttribute("GF_LastShotPos", liveRoot.Position)
					local dmgMult = tonumber(model:GetAttribute("DamageMultiplier")) or 1
					VitalsService.applyDamage(target, def.damage * dmgMult, def.id, liveRoot.Position)
					workspace:SetAttribute("GF_LastAttackAttempt", "hit")
					workspace:SetAttribute("GF_EnemyHits", (workspace:GetAttribute("GF_EnemyHits") or 0) + 1)
				else
					-- visible miss: tracer lands wide of the target so the shot reads as a near miss
					local missOffset = Vector3.new((math.random() - 0.5) * 8, math.random() * 3, (math.random() - 0.5) * 8)
					ReplicatedStorage.GF.Remotes.EnemyFired:FireAllClients(model, liveRoot.Position + missOffset)
					workspace:SetAttribute("GF_LastAttackAttempt", rolling and "dodged" or (blocked and "cover" or "miss"))
					workspace:SetAttribute("GF_EnemyMisses", (workspace:GetAttribute("GF_EnemyMisses") or 0) + 1)
				end
				if interval > 0 and shot < shots then
					task.wait(interval)
				end
			end
			EnemyService.releaseFireSlot(model)
			actor.shotsSinceMove = (actor.shotsSinceMove or 0) + 1
			local wantsCover = string.find(string.lower(actor.behavior or ""), "cover") ~= nil
				or string.find(string.lower(actor.behavior or ""), "guard") ~= nil
			if wantsCover and actor.shotsSinceMove >= 2 then
				local side = (math.random() < 0.5) and 1 or -1
				local perp = Vector3.new(-(stillRoot.Position - root.Position).Unit.Z, 0, (stillRoot.Position - root.Position).Unit.X) * side
				actor.repositionDir = perp.Unit
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
		workspace:SetAttribute("GF_FireSlotsHeld", count)
		return false
	end
	firing[model] = now
	workspace:SetAttribute("GF_FireSlotsHeld", count + 1)
	return true
end

function EnemyService.releaseFireSlot(model: Model)
	firing[model] = nil
end

-- Hearing (S06-008): unsuppressed gunfire within HEARING_RANGE alerts a hostile for several seconds -
-- alerted hostiles perceive in all directions and investigate the noise position if idle.
function EnemyService.hearGunfire(position: Vector3)
	pcall(function()
		require(script.Parent.EncounterDirector).noteGunfire()
	end)
	local now = os.clock()
	for model, actor in pairs(actors) do
		if model.Parent and model:GetAttribute("Dead") ~= true and model.PrimaryPart then
			local dist = (model.PrimaryPart.Position - position).Magnitude
			if dist <= HEARING_RANGE then
				actor.alertedUntil = now + 8
				if not actor.target and not actor.lastSeenPos then
					actor.lastSeenPos = position
					actor.lastSeenAt = now - 1 -- moderate confidence: worth investigating, decays normally
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

function EnemyService.callState()
	local rows = {}
	for model, state in pairs(calls) do
		rows[#rows + 1] = (model.Name or "?") .. ":" .. tostring(state.cancelled and "cancelled" or (state.at and "pending" or "idle"))
	end
	return table.concat(rows, ",")
end

function EnemyService.startCalls()
	task.spawn(function()
		while true do
			task.wait(0.5)
			local relay
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:GetAttribute("GFInteract") == "Relay" then
					relay = d
					break
				end
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
		local budget = 0
		local maxThinking = 14
		for model, actor in actors do
			if budget >= maxThinking then
				break
			end
			budget += 1
			local ok, err = pcall(tickActor, model, actor, step)
			if not ok then
				warn("[GF] enemy tick error: " .. tostring(err))
				actors[model] = nil
			elseif model.Parent then
				model:SetAttribute("GFState", resolveSpecState(model, actor))
			end
		end
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
		local boss = workspace:FindFirstChild(bossName)
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

