--!strict
-- LeviathanWalker: the Ascendancy's heavy siege walker — the reference major war machine
-- (spec sections 41-53). A monumental quadrupedal military machine: four articulated legs with
-- phase-offset gait, component dependency graph, attack lifecycle scheduling, damage-driven
-- capability loss, health-scaled aggression. NO arbitrary invulnerability — armor protects
-- specific components, the hull always takes transfer damage, defeat is always possible.
--
-- Architecture shares ComponentService/AttackScheduler with the Bastion family; locomotion is
-- walker-specific: simplified hull motion + synchronized procedural gait (spec section 46).

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local ComponentService = require(script.Parent.ComponentService)
local VehicleLocomotion = require(script.Parent.VehicleLocomotion)
local AttackScheduler = require(script.Parent.AttackScheduler)
local Vitals = require(script.Parent.VitalsService)
local ShellService = require(script.Parent.ShellService)

local LeviathanWalker = {}

local OBSIDIAN = Color3.fromRGB(36, 33, 42)
local VIOLETGRAY = Color3.fromRGB(81, 70, 94)
local BRONZE = Color3.fromRGB(150, 120, 84)
local IVORY = Color3.fromRGB(214, 203, 180)
local ENERGY = Color3.fromRGB(169, 99, 233)

local active: { [Model]: any } = {}

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or OBSIDIAN
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

--========== construction: monumental quadruped (spec sections 43/44) ==========
-- dimensions: length ~55, width ~38, height ~36. legs at four corners, broad central body.
function LeviathanWalker.build(position: Vector3): (Model, any)
	local model = Instance.new("Model")
	model.Name = "LeviathanWalker"
	local base = CFrame.new(position)
	local L, W, H = 55, 38, 36

	local root = part(model, "Root", Vector3.new(2, 2, 2), base, OBSIDIAN)
	root.Transparency = 1
	root.CanQuery = false
	model.PrimaryPart = root

	-- central body: the greatest mass, broad elongated armored chassis riding high on the legs
	local bodyY = H * 0.62
	local body = part(model, "CentralBody", Vector3.new(W * 0.72, H * 0.3, L * 0.7), base * CFrame.new(0, bodyY, 0), OBSIDIAN)
	part(model, "UpperArmorFront", Vector3.new(W * 0.6, H * 0.14, L * 0.24), base * CFrame.new(0, bodyY + H * 0.2, -L * 0.18), IVORY)
	part(model, "UpperArmorRear", Vector3.new(W * 0.6, H * 0.14, L * 0.2), base * CFrame.new(0, bodyY + H * 0.2, L * 0.18), IVORY)
	part(model, "LowerStructure", Vector3.new(W * 0.5, H * 0.16, L * 0.55), base * CFrame.new(0, bodyY - H * 0.2, 0), VIOLETGRAY)
	-- front sensor assembly: the machine's face — recessed optic cluster
	local sensorAsm = part(model, "FrontSensorAssembly", Vector3.new(W * 0.34, H * 0.12, 3.2), base * CFrame.new(0, bodyY + H * 0.05, -L * 0.36), OBSIDIAN)
	part(model, "SensorOpticMain", Vector3.new(2.6, 1.4, 0.8), base * CFrame.new(0, bodyY + H * 0.05, -L * 0.36 - 1.6), ENERGY, Enum.Material.Neon)
	-- primary weapon: heavy dorsal cannon assembly
	local primWeapon = part(model, "PrimaryWeapon", Vector3.new(3.4, 3.4, L * 0.42), base * CFrame.new(0, bodyY + H * 0.24, -L * 0.08), VIOLETGRAY)
	part(model, "PrimaryChamber", Vector3.new(4.4, 4.4, 5), base * CFrame.new(0, bodyY + H * 0.24, L * 0.12), ENERGY, Enum.Material.Neon)
	-- secondary weapons: flank mounts
	local secL = part(model, "SecondaryWeaponL", Vector3.new(2, 2, L * 0.3), base * CFrame.new(-W * 0.32, bodyY + H * 0.08, -L * 0.1), BRONZE)
	local secR = part(model, "SecondaryWeaponR", Vector3.new(2, 2, L * 0.3), base * CFrame.new(W * 0.32, bodyY + H * 0.08, -L * 0.1), BRONZE)
	-- protected energy core: ventral, armored over initially
	local coreArmor = part(model, "CoreArmorPanel", Vector3.new(W * 0.3, 2.2, L * 0.2), base * CFrame.new(0, bodyY - H * 0.3, L * 0.05), IVORY)
	local core = part(model, "ProtectedEnergyCore", Vector3.new(W * 0.2, H * 0.1, L * 0.13), base * CFrame.new(0, bodyY - H * 0.3 + 1.8, L * 0.05), ENERGY, Enum.Material.Neon)
	-- cooling modules aft
	part(model, "CoolingL", Vector3.new(4, 5, 6), base * CFrame.new(-W * 0.22, bodyY + H * 0.1, L * 0.3), BRONZE)
	part(model, "CoolingR", Vector3.new(4, 5, 6), base * CFrame.new(W * 0.22, bodyY + H * 0.1, L * 0.3), BRONZE)

	-- legs: four substantial mechanical assemblies. upper/lower/foot segments with joint structure.
	local legs = {}
	local legPositions = {
		{ x = -W * 0.42, z = -L * 0.3, id = "FL" }, -- front-left
		{ x = W * 0.42, z = -L * 0.3, id = "FR" },
		{ x = -W * 0.42, z = L * 0.3, id = "RL" },
		{ x = W * 0.42, z = L * 0.3, id = "RR" },
	}
	for _, lp in legPositions do
		local hipY = bodyY - H * 0.1
		local upper = part(model, "LegUpper" .. lp.id, Vector3.new(4.6, H * 0.3, 4.6), base * CFrame.new(lp.x, hipY - H * 0.12, lp.z), VIOLETGRAY)
		local lower = part(model, "LegLower" .. lp.id, Vector3.new(3.4, H * 0.3, 3.4), base * CFrame.new(lp.x * 1.08, hipY - H * 0.4, lp.z), OBSIDIAN)
		local foot = part(model, "Foot" .. lp.id, Vector3.new(7, 2.2, 8), base * CFrame.new(lp.x * 1.1, 1.2, lp.z), OBSIDIAN)
		part(model, "JointCover" .. lp.id, Vector3.new(5.2, 3, 5.2), base * CFrame.new(lp.x * 1.04, hipY - H * 0.26, lp.z), BRONZE)
		-- forward leg knee joints are weakpoint-exposed mechanical regions
		table.insert(legs, {
			id = lp.id, upper = upper, lower = lower, foot = foot,
			ox = lp.x, oz = lp.z,
			-- diagonal gait pairs: FL+RR and FR+RL alternate (spec section 46 phase offsets)
			phase = (lp.id == "FL" or lp.id == "RR") and 0 or math.pi,
		})
	end

	model:SetAttribute("GFEnemy", true)
	model:SetAttribute("EnemyId", "LeviathanWalker")
	model:SetAttribute("Tier", "Boss")
	model:SetAttribute("Boss", true)
	model:SetAttribute("Dead", false)
	local folder = Workspace:FindFirstChild("ActiveActors") or Instance.new("Folder")
	folder.Name = "ActiveActors"
	folder.Parent = Workspace
	model.Parent = folder

	-- rigid hull offsets for body-group parts; legs articulate separately
	local hullOffsets = {}
	local legParts = {}
	for _, leg in legs do
		legParts[leg.upper] = true
		legParts[leg.lower] = true
		legParts[leg.foot] = true
		legParts[model:FindFirstChild("JointCover" .. leg.id)] = true
	end
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p ~= root and not legParts[p] then
			hullOffsets[p] = base:ToObjectSpace(p.CFrame)
		end
	end

	return model, {
		legs = legs,
		hullOffsets = hullOffsets,
		bodyY = bodyY,
		dims = { length = L, width = W, height = H },
		parts = {
			body = body, sensorAsm = sensorAsm, primWeapon = primWeapon,
			secL = secL, secR = secR, coreArmor = coreArmor, core = core,
		},
	}
end

--========== perception ==========
local function visibleTarget(state: any, range: number): (Player?, number, boolean)
	local best, bestDist, bestLos = nil, math.huge, false
	local origin = state.model.PrimaryPart.Position + Vector3.new(0, state.build.bodyY, 0)
	for _, pl in Players:GetPlayers() do
		local ch = pl.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if hum and hum.Health > 0 and root then
			local d = (root.Position - origin).Magnitude
			if d < bestDist and d < range then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { state.model, ch }
				local blocked = Workspace:Raycast(origin, root.Position - origin, params)
				best, bestDist, bestLos = pl, d, blocked == nil
			end
		end
	end
	return best, bestDist, bestLos
end

local function fxFolder()
	local f = Workspace:FindFirstChild("GF_FX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GF_FX"
		f.Parent = Workspace
	end
	return f
end

local function telegraphRing(center: Vector3, radius: number, life: number, color: Color3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.5
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Parent = fxFolder()
	task.delay(life + 0.2, function() if ring.Parent then ring:Destroy() end end)
end

--========== attacks (spec section 49: recognizable families) ==========

-- heavy cannon: monumental projectile with readable travel time
local function fireHeavyCannon(state: any, ctx: any)
	local target = ctx.target
	if not (target and target.root) then return end
	local weapon = state.model:FindFirstChild("PrimaryWeapon")
	if not weapon then return end
	local origin = weapon.CFrame * Vector3.new(0, 0, -weapon.Size.Z / 2)
	local aim = target.root.Position
	telegraphRing(aim, 15, 1.1, Color3.fromRGB(255, 110, 70))
	task.delay(1.1, function()
		if state.dead then return end
		ShellService.fireShell(origin, aim, {
			size = 2.6, speed = 110, ignoreList = { state.model },
		}, function(at: Vector3, hit: Instance?)
			telegraphRing(at, 17, 0.6, Color3.fromRGB(255, 150, 80))
			for _, pl in Players:GetPlayers() do
				local ch = pl.Character
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if root and hum and hum.Health > 0 then
					local d = (root.Position - at).Magnitude
					if d <= 17 then
						Vitals.applyDamage(pl, math.floor(68 * (1 - (d / 17) * 0.5)), "LeviathanCannon")
					end
				end
			end
		end)
	end)
end

-- area denial: a pattern of threatened regions detonating after preparation (spec 49)
local function fireAreaDenial(state: any, ctx: any)
	local target = ctx.target
	if not (target and target.root) then return end
	local center = target.root.Position
	local zones = {}
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		local r = (i == 1) and 0 or 16
		local pos = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		table.insert(zones, pos)
		telegraphRing(pos, 11, 1.9, Color3.fromRGB(255, 96, 72))
	end
	task.delay(1.9, function()
		if state.dead then return end
		for _, pos in zones do
			for _, pl in Players:GetPlayers() do
				local ch = pl.Character
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if root and hum and hum.Health > 0 then
					local d = (root.Position - pos).Magnitude
					if d <= 11 then
						Vitals.applyDamage(pl, 34, "LeviathanBarrage")
					end
				end
			end
		end
	end)
end

-- secondary sustained fire: bounded pressure while the main gun recovers
local function fireSecondary(state: any, ctx: any)
	local target = ctx.target
	if not (target and target.root) then return end
	task.spawn(function()
		for shot = 1, 6 do
			if state.dead then return end
			task.wait(0.3)
			local t = ctx.target
			if not (t and t.root and t.root.Parent) then break end
			local side = shot % 2 == 0 and "SecondaryWeaponL" or "SecondaryWeaponR"
			local weapon = state.model:FindFirstChild(side)
			if not weapon then break end
			local origin = weapon.CFrame * Vector3.new(0, 0, -weapon.Size.Z / 2)
			local dir = t.root.Position - origin
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { state.model, t.root.Parent }
			if not Workspace:Raycast(origin, dir, params) and math.random() < 0.5 then
				Vitals.applyDamage(t.player, 11, "LeviathanSecondary")
			end
		end
	end)
end

-- mechanical shockwave: telegraphed stomp when enemies press close (spec 49)
local function fireShockwave(state: any, ctx: any)
	local pos = state.loco.cframe.Position
	telegraphRing(pos, 26, 1.4, Color3.fromRGB(255, 176, 64))
	task.delay(1.4, function()
		if state.dead then return end
		for _, pl in Players:GetPlayers() do
			local ch = pl.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
				if d <= 26 then
					Vitals.applyDamage(pl, 48, "LeviathanShockwave")
				end
			end
		end
	end)
end

--========== spawn + component registration ==========
function LeviathanWalker.spawn(position: Vector3): Model?
	local model, build = LeviathanWalker.build(position)

	local entity = ComponentService.registerEntity(model, {
		hullHealth = 26000,
		components = {
			CoreArmorPanel = {
				part = build.parts.coreArmor, health = 2400, eta = 0.05,
				protects = { "ProtectedEnergyCore" }, enables = {},
			},
			ProtectedEnergyCore = {
				part = build.parts.core, health = 2000, eta = 2.2, damageMultiplier = 2.2,
				protectedBy = "CoreArmorPanel", enables = {},
			},
			PrimaryWeapon = {
				part = build.parts.primWeapon, health = 2600, eta = 0.4,
				enables = { "HeavyCannonAttack" },
			},
			SecondaryWeaponL = {
				part = build.parts.secL, health = 1200, eta = 0.3,
				enables = { "SecondaryFire" },
			},
			SecondaryWeaponR = {
				part = build.parts.secR, health = 1200, eta = 0.3,
				enables = { "SecondaryFire" },
			},
			FrontSensorAssembly = {
				part = build.parts.sensorAsm, health = 1400, eta = 0.5,
				enables = { "AimAcquisition" },
			},
		},
	}, {
		onComponentDestroyed = function(ent, componentId)
			local state = active[ent.model]
			if not state then return end
			if componentId == "PrimaryWeapon" then
				AttackScheduler.interrupt(state.scheduler, "primary destroyed")
			elseif componentId == "FrontSensorAssembly" then
				state.sensorDestroyed = true
			end
			-- leg damage is hull damage in this generation (spec: future component families)
		end,
	})

	local scheduler = AttackScheduler.new({
		{
			id = "HeavyCannonAttack", requiredCapability = "HeavyCannonAttack",
			minRange = 40, maxRange = 240,
			telegraphTime = 1.8, activeTime = 0.3, recoveryTime = 3.2, cooldown = 9,
			pressureCost = 3, weight = 3.2, requiresLineOfSight = true,
			fire = function(ctx) fireHeavyCannon(active[model], ctx) end,
		},
		{
			id = "AreaDenial", requiredCapability = nil, -- the barrage launcher is hull-integral
			minRange = 30, maxRange = 160,
			telegraphTime = 1.9, activeTime = 0.2, recoveryTime = 2.6, cooldown = 12,
			pressureCost = 2, weight = 2.4,
			fire = function(ctx) fireAreaDenial(active[model], ctx) end,
		},
		{
			id = "SecondaryFire", requiredCapability = "SecondaryFire",
			minRange = 0, maxRange = 110,
			telegraphTime = 0.8, activeTime = 1.8, recoveryTime = 1.6, cooldown = 6,
			pressureCost = 1, weight = 2,
			fire = function(ctx) fireSecondary(active[model], ctx) end,
		},
		{
			id = "Shockwave", requiredCapability = nil,
			minRange = 0, maxRange = 30,
			telegraphTime = 1.4, activeTime = 0.2, recoveryTime = 2.2, cooldown = 10,
			pressureCost = 2, weight = 3.5,
			fire = function(ctx) fireShockwave(active[model], ctx) end,
		},
	}, 3)

	local state = {
		model = model,
		build = build,
		entity = entity,
		scheduler = scheduler,
		loco = VehicleLocomotion.newState(CFrame.new(position)),
		targetMemory = nil,
		memoryDuration = 9,
		sensorDestroyed = false,
		dead = false,
		gaitClock = 0,
		gaitFreq = 0.5, -- steps per second scaled — monumental weight means slow cadence
	}
	active[model] = state
	model:SetAttribute("Health", 26000)
	model:SetAttribute("MaxHealth", 26000)
	return model
end

--========== gait + posing (spec sections 46/47) ==========
-- simplified hull motion with synchronized procedural legs: stance feet plant, swing feet follow
-- controlled trajectories. Phase offsets produce diagonal stepping pairs.
local function poseWalker(state: any, dt: number)
	local hullCf = state.loco.cframe
	local root = state.model.PrimaryPart
	if root then root.CFrame = hullCf end
	for part, offset in state.build.hullOffsets do
		if part.Parent then part.CFrame = hullCf * offset end
	end
	-- gait integration: legs cycle only while the hull moves
	local moving = state.loco.speed > 0.6
	if moving then
		state.gaitClock += dt * state.gaitFreq * (state.loco.speed / 6.5)
	end
	for _, leg in state.build.legs do
		local phi = (state.gaitClock * math.pi * 2 + leg.phase) % (math.pi * 2)
		-- swing fraction: foot lifts through the first half of the cycle, plants through the second
		local lift = math.max(0, math.sin(phi)) * 2.2
		local stride = math.cos(phi) * 3.2 * math.min(1, state.loco.speed / 6.5)
		local fwdX = -math.sin(state.loco.yaw)
		local fwdZ = -math.cos(state.loco.yaw)
		local hipPos = hullCf * Vector3.new(leg.ox, state.build.bodyY - state.build.dims.height * 0.1, leg.oz)
		local footBase = hullCf * Vector3.new(leg.ox * 1.1, 1.2, leg.oz)
		-- foot: stride along hull forward + lift arc
		local footPos = footBase + Vector3.new(fwdX * stride, lift, fwdZ * stride)
		-- ground clamp: feet never float far above terrain nor sink
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { state.model }
		local hit = Workspace:Raycast(footPos + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0), params)
		if hit then
			footPos = Vector3.new(footPos.X, math.max(hit.Position.Y + 1.1, footPos.Y - lift) + lift * 0.6, footPos.Z)
		end
		-- segment interpolation: upper hangs from hip, lower bridges hip-to-foot, foot plants
		if leg.upper.Parent then
			leg.upper.CFrame = CFrame.new(hipPos - Vector3.new(0, state.build.dims.height * 0.12, 0))
		end
		if leg.lower.Parent then
			local mid = (hipPos + footPos) / 2
			leg.lower.CFrame = CFrame.new(mid - Vector3.new(0, state.build.dims.height * 0.08, 0))
		end
		if leg.foot.Parent then
			leg.foot.CFrame = CFrame.new(footPos) * CFrame.Angles(0, state.loco.yaw, 0)
		end
	end
end

--========== step ==========
function LeviathanWalker.step(dt: number)
	for model, state in active do
		if not model.Parent then
			active[model] = nil
			continue
		end
		if state.dead then continue end
		if state.entity.dead or model:GetAttribute("Health") <= 0 then
			LeviathanWalker.kill(state)
			continue
		end
		local frac = state.entity.hullHealth / state.entity.hullMaxHealth
		AttackScheduler.updateAggression(state.scheduler, frac, 1, 1.65, 1.4)
		workspace:SetAttribute("BossHealth", state.entity.hullHealth)

		local target, dist, los = visibleTarget(state, 300)
		if target and los then
			local ch = target.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if root then
				state.targetMemory = { position = root.Position, at = os.clock(), player = target }
			end
		elseif state.targetMemory and os.clock() - state.targetMemory.at > state.memoryDuration then
			state.targetMemory = nil
		end
		local mem = state.targetMemory

		-- movement: the walker advances deliberately toward engagement range, hull yaw leads
		local desiredDir, speedFrac = nil, 0
		if mem then
			local toT = mem.position - state.loco.cframe.Position
			local planar = Vector3.new(toT.X, 0, toT.Z)
			if planar.Magnitude > 130 then
				desiredDir = planar.Unit
				speedFrac = 0.9
			elseif planar.Magnitude < 45 then
				desiredDir = -planar.Unit
				speedFrac = 0.35
			else
				-- in range: slow strafe-orbit pressure rather than a static turret
				local perp = Vector3.new(-planar.Z, 0, planar.X).Unit
				desiredDir = perp
				speedFrac = 0.25
			end
		end
		VehicleLocomotion.step(state.loco, {
			maxSpeed = 6.5, accel = 3, brake = 5,
			hullOmegaMax = math.rad(14),
			footprintHalf = Vector3.new(19, 8, 27),
			groundClearance = 2.2,
			maxSlopeDeg = 24,
		}, desiredDir, speedFrac, dt, { model })
		poseWalker(state, dt)

		if mem and target then
			local ch = target.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			local ctx = {
				dist = dist,
				target = root and { player = target, root = root } or nil,
				hasLineOfSight = los,
				capabilityAvailable = function(cap) return ComponentService.capabilityAvailable(model, cap) end,
			}
			AttackScheduler.step(state.scheduler, ctx)
		end
	end
end

function LeviathanWalker.kill(state: any)
	if state.dead then return end
	state.dead = true
	state.model:SetAttribute("Dead", true)
	state.model:SetAttribute("Health", 0)
	workspace:SetAttribute("BossHealth", 0)
	-- defeat sequence (spec section 77): shutdown, instability, bounded collapse, wreck persists
	local pos = state.loco.cframe.Position
	telegraphRing(pos, 30, 1.6, Color3.fromRGB(255, 190, 110))
	task.delay(0.8, function()
		telegraphRing(pos, 22, 1.2, Color3.fromRGB(255, 140, 80))
	end)
	-- the machine settles: hull sags as leg support fails
	for i = 1, 8 do
		task.delay(i * 0.18, function()
			if not state.model.Parent then return end
			state.loco.cframe = state.loco.cframe - Vector3.new(0, 0.55, 0)
			poseWalker(state, 0)
		end)
	end
	for _, p in state.model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanQuery = false
			if p.Material ~= Enum.Material.Neon then
				p.Color = p.Color:Lerp(Color3.fromRGB(18, 18, 20), 0.5)
			end
		end
	end
	pcall(function()
		require(script.Parent.CacheService).onEnemyKilled(state.model, nil)
		local SquadService = require(script.Parent.SquadService)
		SquadService.add("militaryTechnology", 6)
		SquadService.add("energyCells", 9)
	end)
	workspace:SetAttribute("GF_LeviathanDefeated", true)
	task.delay(90, function()
		if state.model.Parent then state.model:Destroy() end
		active[state.model] = nil
		ComponentService.unregister(state.model)
	end)
end

function LeviathanWalker.start()
	task.spawn(function()
		while true do
			local dt = 1 / 12
			task.wait(dt)
			local ok, err = pcall(LeviathanWalker.step, dt)
			if ok then
				Workspace:SetAttribute("GF_LeviathanHeartbeat", os.clock())
			else
				Workspace:SetAttribute("GF_LeviathanHeartbeatError", tostring(err))
			end
		end
	end)
end

function LeviathanWalker.stateOf(model: Model): any?
	return active[model]
end

return LeviathanWalker
