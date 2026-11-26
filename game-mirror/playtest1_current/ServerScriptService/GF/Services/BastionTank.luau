--!strict
-- BastionTank: the Ascendancy's standard heavy armored military vehicle (spec sections 26-39).
-- Integrates: modular construction, ComponentService destructible components, VehicleLocomotion
-- hull movement, independent turret articulation, AttackScheduler attack lifecycles, legitimate
-- perception. Placeholder hard-surface geometry now; mesh shells swap onto the same attachment
-- semantics during visual production (stage 3/5) — architecture first, art second.
--
-- One controller instance per vehicle, stepped at 12Hz tactical / per-step movement integration.
-- No workspace scans in the hot loop: everything registered once at spawn.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local ComponentService = require(script.Parent.ComponentService)
local VehicleLocomotion = require(script.Parent.VehicleLocomotion)
local AttackScheduler = require(script.Parent.AttackScheduler)
local Vitals = require(script.Parent.VitalsService)

local BastionTank = {}

-- faction material identity (spec section 7)
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

--========== construction (modular, attachment-correct) ==========
-- layout dimensions for Standard Bastion: length 28, width 17, height ~11.
-- coordinate frame: hull PrimaryPart at center mass; +Z is REAR in Roblox convention (front = -Z).
function BastionTank.build(position: Vector3, variant: string?): (Model, any)
	local Hierarchy = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.EncounterHierarchy)
	local vcfg = Hierarchy.BastionVariants[variant or "Standard"] or Hierarchy.BastionVariants.Standard
	local dims = vcfg.dimensions
	local L, W, H = dims.length, dims.width, dims.height

	local model = Instance.new("Model")
	model.Name = "BastionTank"
	local base = CFrame.new(position)

	-- hull root: invisible kinematic anchor
	local root = part(model, "Root", Vector3.new(2, 2, 2), base, OBSIDIAN)
	root.Transparency = 1
	root.CanQuery = false
	model.PrimaryPart = root

	-- chassis: broad low armored hull, sloped frontal suggestion
	local chassis = part(model, "Chassis", Vector3.new(W, H * 0.55, L), base * CFrame.new(0, H * 0.32, 0), OBSIDIAN)
	part(model, "GlacisPlate", Vector3.new(W * 0.92, H * 0.4, L * 0.24), base * CFrame.new(0, H * 0.42, -L * 0.38) * CFrame.Angles(math.rad(-18), 0, 0), VIOLETGRAY)
	part(model, "HullSideL", Vector3.new(1.6, H * 0.45, L * 0.86), base * CFrame.new(-W * 0.5 + 0.8, H * 0.36, 0), VIOLETGRAY)
	part(model, "HullSideR", Vector3.new(1.6, H * 0.45, L * 0.86), base * CFrame.new(W * 0.5 - 0.8, H * 0.36, 0), VIOLETGRAY)

	-- propulsion assemblies: enclosed armored side housings (visual track suggestion)
	local propL = part(model, "PropulsionL", Vector3.new(2.6, H * 0.5, L * 0.92), base * CFrame.new(-W * 0.5 - 1.0, H * 0.22, 0), OBSIDIAN)
	local propR = part(model, "PropulsionR", Vector3.new(2.6, H * 0.5, L * 0.92), base * CFrame.new(W * 0.5 + 1.0, H * 0.22, 0), OBSIDIAN)
	for i = 0, 5 do
		-- road-wheel suggestions along each housing
		part(model, "WheelL" .. i, Vector3.new(2.8, 1.8, 1.8), base * CFrame.new(-W * 0.5 - 1.0, H * 0.1, -L * 0.36 + i * (L * 0.72 / 5)), BRONZE, Enum.Material.Metal)
		part(model, "WheelR" .. i, Vector3.new(2.8, 1.8, 1.8), base * CFrame.new(W * 0.5 + 1.0, H * 0.1, -L * 0.36 + i * (L * 0.72 / 5)), BRONZE, Enum.Material.Metal)
	end

	-- front armor panel: the protector component, destroyed exposes the core
	local frontArmor = part(model, "FrontArmorPanel", Vector3.new(W * 0.6, H * 0.5, 1.4), base * CFrame.new(0, H * 0.42, -L * 0.5 + 0.6), IVORY)
	-- energy core: recessed behind the front armor, visible violet chamber when exposed
	local core = part(model, "EnergyCore", Vector3.new(W * 0.34, H * 0.3, 2.2), base * CFrame.new(0, H * 0.4, -L * 0.5 + 2.4), ENERGY, Enum.Material.Neon)

	-- turret assembly: independent articulation group. parts positioned relative to turret frame.
	local turretYaw0 = 0
	local turretHousing = part(model, "TurretHousing", Vector3.new(W * 0.62, H * 0.42, L * 0.4), base * CFrame.new(0, H * 0.78, L * 0.05), OBSIDIAN)
	part(model, "TurretArmorL", Vector3.new(1.2, H * 0.3, L * 0.3), base * CFrame.new(-W * 0.32, H * 0.78, L * 0.05), IVORY)
	part(model, "TurretArmorR", Vector3.new(1.2, H * 0.3, L * 0.3), base * CFrame.new(W * 0.32, H * 0.78, L * 0.05), IVORY)
	-- main cannon: long reinforced energy weapon, mounted forward of the turret
	local cannon = part(model, "MainCannon", Vector3.new(1.6, 1.6, L * 0.52), base * CFrame.new(0, H * 0.78, -L * 0.32), VIOLETGRAY)
	part(model, "CannonChamber", Vector3.new(2.2, 2.2, 3.2), base * CFrame.new(0, H * 0.78, -L * 0.12), ENERGY, Enum.Material.Neon)
	part(model, "MuzzleBrake", Vector3.new(2.0, 2.0, 1.4), base * CFrame.new(0, H * 0.78, -L * 0.57), BRONZE)
	-- secondary weapon: compact coaxial mount
	local secondary = part(model, "SecondaryWeapon", Vector3.new(0.9, 0.9, L * 0.22), base * CFrame.new(W * 0.18, H * 0.62, -L * 0.18), BRONZE)
	-- sensor assembly: recessed optic cluster on the turret roof
	local sensor = part(model, "SensorAssembly", Vector3.new(2.4, 1.2, 2.4), base * CFrame.new(-W * 0.16, H * 1.02, L * 0.1), OBSIDIAN)
	part(model, "SensorOptic", Vector3.new(0.7, 0.7, 0.4), base * CFrame.new(-W * 0.16, H * 1.02, L * 0.1 - 1.2), ENERGY, Enum.Material.Neon)
	-- cooling assembly: rear mechanical detail
	part(model, "CoolingAssembly", Vector3.new(W * 0.5, H * 0.3, 2.6), base * CFrame.new(0, H * 0.5, L * 0.44), BRONZE)

	-- articulation registry: which parts follow the turret frame
	local turretParts = {
		turretHousing, cannon, secondary, sensor,
		model.TurretArmorL, model.TurretArmorR, model.CannonChamber, model.MuzzleBrake, model.SensorOptic,
	}
	-- store offsets relative to the turret pivot (hull top center)
	local turretPivot = base * CFrame.new(0, H * 0.78, L * 0.05)
	local turretOffsets = {}
	for _, p in turretParts do
		turretOffsets[p] = turretPivot:ToObjectSpace(p.CFrame)
	end
	-- hull-follow offsets for every part (rigid attachment to hull frame)
	local hullOffsets = {}
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p ~= root then
			hullOffsets[p] = base:ToObjectSpace(p.CFrame)
		end
	end

	model:SetAttribute("GFEnemy", true)
	local enemyKey = (variant == "Siege") and "BastionSiege" or "BastionTank"
	model:SetAttribute("EnemyId", enemyKey)
	model:SetAttribute("Tier", "Vehicle")
	model:SetAttribute("Variant", variant or "Standard")
	model:SetAttribute("Dead", false)
	model:SetAttribute("Boss", variant == "Siege")
	local folder = Workspace:FindFirstChild("ActiveActors") or Instance.new("Folder")
	folder.Name = "ActiveActors"
	folder.Parent = Workspace
	model.Parent = folder

	return model, {
		vcfg = vcfg,
		turretPivot0 = turretPivot,
		turretOffsets = turretOffsets,
		hullOffsets = hullOffsets,
		turretParts = turretParts,
		parts = {
			chassis = chassis, frontArmor = frontArmor, core = core,
			cannon = cannon, secondary = secondary, sensor = sensor,
			propL = propL, propR = propR, turretHousing = turretHousing,
		},
		dims = dims,
	}
end

--========== perception (legitimate, spec section 35) ==========
local function visibleTarget(state: any): (Player?, number, boolean)
	local best, bestDist, bestLos = nil, math.huge, false
	local origin = state.model.PrimaryPart.Position + Vector3.new(0, 6, 0)
	for _, pl in Players:GetPlayers() do
		local ch = pl.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if hum and hum.Health > 0 and root then
			local d = (root.Position - origin).Magnitude
			if d < bestDist and d < 260 then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { state.model, ch }
				local blocked = Workspace:Raycast(origin, root.Position - origin, params)
				best = pl
				bestDist = d
				bestLos = blocked == nil
			end
		end
	end
	return best, bestDist, bestLos
end

--========== attack implementations ==========
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
	ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.55
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Parent = fxFolder()
	task.delay(life + 0.2, function() if ring.Parent then ring:Destroy() end end)
end

-- heavy cannon: projectile with readable travel — damage at legitimate impact, never before (spec 35)
local function fireHeavyCannon(state: any, ctx: any)
	local target = ctx.target
	if not target or not target.root then return end
	local muzzle = state.model:FindFirstChild("MainCannon")
	if not muzzle then return end
	local origin = muzzle.CFrame * Vector3.new(0, 0, -muzzle.Size.Z / 2)
	local aimPoint = target.root.Position
	-- projectile: visible shell, arc-free direct flight, impact detonation
	local shell = Instance.new("Part")
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(1.6, 1.6, 1.6)
	shell.Color = ENERGY
	shell.Material = Enum.Material.Neon
	shell.CanCollide = false
	shell.Anchored = false
	shell.CanQuery = false
	shell.CFrame = CFrame.new(origin)
	shell.Parent = fxFolder()
	local dir = (aimPoint - origin)
	local speed = 130
	shell.AssemblyLinearVelocity = dir.Unit * speed
	local detonated = false
	local function detonate(at: Vector3)
		if detonated then return end
		detonated = true
		if shell.Parent then shell:Destroy() end
		telegraphRing(at, 13, 0.5, Color3.fromRGB(255, 140, 80))
		for _, pl in Players:GetPlayers() do
			local ch = pl.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local d = (root.Position - at).Magnitude
				if d <= 13 then
					local falloff = 1 - (d / 13) * 0.5
					Vitals.applyDamage(pl, math.floor(52 * falloff), "BastionCannon")
				end
			end
		end
	end
	shell.Touched:Connect(function(hit)
		if hit:IsDescendantOf(state.model) then return end
		local pl = Players:GetPlayerFromCharacter(hit.Parent)
		if pl or hit.CanCollide then
			detonate(shell.Position)
		end
	end)
	-- fused regardless: detonate at aim point expiry
	task.delay(dir.Magnitude / speed + 0.35, function()
		detonate(shell.Parent and shell.Position or aimPoint)
	end)
end

-- secondary fire: bounded sustained pressure pulses
local function fireSecondary(state: any, ctx: any)
	local target = ctx.target
	if not target or not target.root then return end
	local weapon = state.model:FindFirstChild("SecondaryWeapon")
	if not weapon then return end
	task.spawn(function()
		for shot = 1, 4 do
			if state.dead then return end
			task.wait(0.22)
			local t = ctx.target
			if not (t and t.root and t.root.Parent) then break end
			local origin = weapon.CFrame * Vector3.new(0, 0, -weapon.Size.Z / 2)
			local dir = t.root.Position - origin
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { state.model, t.root.Parent }
			local blocked = Workspace:Raycast(origin, dir, params)
			-- dispersion: the secondary is pressure, not precision
			if not blocked and math.random() < 0.55 then
				Vitals.applyDamage(t.player, 9, "BastionSecondary")
			end
		end
	end)
end

--========== controller ==========

function BastionTank.spawn(position: Vector3, variant: string?): Model?
	local model, build = BastionTank.build(position, variant)
	local Hierarchy = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.EncounterHierarchy)
	local compDefs = Hierarchy.BastionComponents

	-- component registration: explicit hitboxes, dependency graph, capability mapping
	local entity = ComponentService.registerEntity(model, {
		hullHealth = build.vcfg.hullHealth,
		components = {
			FrontArmor = {
				part = build.parts.frontArmor, health = compDefs.FrontArmor.health,
				eta = compDefs.FrontArmor.eta, protects = compDefs.FrontArmor.protects, enables = {},
			},
			EnergyCore = {
				part = build.parts.core, health = compDefs.EnergyCore.health,
				eta = compDefs.EnergyCore.eta, protectedBy = compDefs.EnergyCore.protectedBy,
				damageMultiplier = compDefs.EnergyCore.damageMultiplier, enables = {},
			},
			MainCannon = {
				part = build.parts.cannon, health = compDefs.MainCannon.health,
				eta = compDefs.MainCannon.eta, enables = compDefs.MainCannon.enables,
			},
			SensorAssembly = {
				part = build.parts.sensor, health = compDefs.SensorAssembly.health,
				eta = compDefs.SensorAssembly.eta, enables = compDefs.SensorAssembly.enables,
			},
			LeftPropulsion = {
				part = build.parts.propL, health = compDefs.LeftPropulsion.health,
				eta = compDefs.LeftPropulsion.eta, enables = compDefs.LeftPropulsion.enables,
			},
			RightPropulsion = {
				part = build.parts.propR, health = compDefs.RightPropulsion.health,
				eta = compDefs.RightPropulsion.eta, enables = compDefs.RightPropulsion.enables,
			},
			SecondaryWeapon = {
				part = build.parts.secondary, health = compDefs.SecondaryWeapon.health,
				eta = compDefs.SecondaryWeapon.eta, enables = compDefs.SecondaryWeapon.enables,
			},
		},
	}, {
		onComponentDestroyed = function(ent, componentId)
			local state = active[ent.model]
			if not state then return end
			-- capability invalidation with behavioral consequence (spec section 36)
			if componentId == "MainCannon" then
				AttackScheduler.interrupt(state.scheduler, "cannon destroyed")
			elseif componentId == "SensorAssembly" then
				state.sensorDestroyed = true -- acquisition degradation applied in targeting
			end
			-- mobility: handled continuously through capabilityHealth in the movement step
		end,
	})

	-- attack portfolio: lifecycle-defined, pressure-budgeted (spec sections 35/48)
	local scheduler = AttackScheduler.new({
		{
			id = "HeavyCannonAttack",
			requiredCapability = "HeavyCannonAttack",
			minRange = 20, maxRange = 190,
			telegraphTime = 1.6, activeTime = 0.2, recoveryTime = 2.4, cooldown = 7,
			pressureCost = 2, weight = 3,
			requiresLineOfSight = true,
			fire = function(ctx, target) fireHeavyCannon(active[model], ctx) end,
		},
		{
			id = "SecondaryFire",
			requiredCapability = "SecondaryFire",
			minRange = 0, maxRange = 90,
			telegraphTime = 0.7, activeTime = 0.9, recoveryTime = 1.4, cooldown = 5,
			pressureCost = 1, weight = 2,
			fire = function(ctx, target) fireSecondary(active[model], ctx) end,
		},
	}, 2)

	local locoState = VehicleLocomotion.newState(CFrame.new(position))
	local state = {
		model = model,
		build = build,
		entity = entity,
		scheduler = scheduler,
		loco = locoState,
		turretYawRel = 0,
		targetMemory = nil, -- last legitimately perceived position + time
		memoryDuration = 7,
		sensorDestroyed = false,
		dead = false,
		terrainHalf = Vector3.new(build.dims.width / 2, 4, build.dims.length / 2),
	}
	active[model] = state
	model:SetAttribute("Health", build.vcfg.hullHealth)
	model:SetAttribute("MaxHealth", build.vcfg.hullHealth)
	return model
end

-- per-frame-ish articulation: hull parts rigidly follow the loco cframe; turret parts follow the
-- turret frame composed on top of hull frame. Stepped at controller rate (12Hz) — smooth enough
-- for heavy machinery, cheap enough for multiple vehicles.
local function poseModel(state: any)
	local hullCf = state.loco.cframe
	for part, offset in state.build.hullOffsets do
		if part.Parent then
			part.CFrame = hullCf * offset
		end
	end
	-- turret frame: hull frame * pivot offset * turret yaw rotation
	local pivotLocal = state.build.hullOffsets[state.build.parts.turretHousing]
	if pivotLocal then
		local pivotWorld = hullCf * CFrame.new(pivotLocal.Position) * CFrame.Angles(0, state.turretYawRel, 0)
		for part, offset in state.build.turretOffsets do
			if part.Parent then
				part.CFrame = pivotWorld * offset
			end
		end
	end
end

function BastionTank.step(dt: number)
	for model, state in active do
		if not model.Parent then
			active[model] = nil
			continue
		end
		if state.dead then continue end
		if model:GetAttribute("Health") <= 0 or state.entity.dead then
			BastionTank.kill(state)
			continue
		end
		-- aggression from health fraction (spec section 52)
		local frac = state.entity.hullHealth / state.entity.hullMaxHealth
		AttackScheduler.updateAggression(state.scheduler, frac, 1, 1.55, 1.4)

		-- legitimate perception with memory decay
		local target, dist, los = visibleTarget(state)
		if target and los then
			local ch = target.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if root then
				state.targetMemory = { position = root.Position, at = os.clock(), player = target }
			end
		elseif state.targetMemory and os.clock() - state.targetMemory.at > state.memoryDuration then
			state.targetMemory = nil -- memory expires — no omniscient tracking (spec section 35)
		end
		local mem = state.targetMemory

		-- movement: close to engagement range or hold; mobility degrades with propulsion loss
		local mobilityFrac = ComponentService.capabilityHealth(model, "MobilityLeft") * 0.5
			+ ComponentService.capabilityHealth(model, "MobilityRight") * 0.5
		local desiredDir, speedFrac = nil, 0
		if mem and mobilityFrac > 0 then
			local toTarget = mem.position - state.loco.cframe.Position
			local planar = Vector3.new(toTarget.X, 0, toTarget.Z)
			if planar.Magnitude > 95 then
				desiredDir = planar.Unit
				speedFrac = 0.85 * mobilityFrac
			elseif planar.Magnitude < 40 then
				-- too close: reverse-out pressure (vehicles don't crushdance infantry)
				desiredDir = -planar.Unit
				speedFrac = 0.4 * mobilityFrac
			end
		end
		VehicleLocomotion.step(state.loco, {
			maxSpeed = state.build.vcfg.speed,
			accel = state.build.vcfg.accel,
			brake = state.build.vcfg.brake,
			hullOmegaMax = state.build.vcfg.hullOmegaMax,
			footprintHalf = state.terrainHalf,
			groundClearance = 3.4,
		}, desiredDir, speedFrac, dt, { model })

		-- turret articulation: track the remembered target position, never instant (spec section 32)
		if mem then
			local toT = mem.position - state.loco.cframe.Position
			local worldYaw = math.atan2(-toT.X, -toT.Z)
			-- sensor destruction degrades tracking: the turret hunts with error and lag
			local tauTurret = state.sensorDestroyed and 2.8 or 0.9
			state.turretYawRel = VehicleLocomotion.articulateStep(
				state.turretYawRel, worldYaw, state.loco.yaw,
				state.build.vcfg.turretOmegaMax, tauTurret, dt)
		end
		poseModel(state)

		-- attack scheduler: legitimate target info only — turret roughly on target, los required for cannon
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

function BastionTank.kill(state: any)
	if state.dead then return end
	state.dead = true
	state.model:SetAttribute("Dead", true)
	state.model:SetAttribute("Health", 0)
	-- destruction sequence (spec section 77): systems shut down, instability, bounded explosion,
	-- wreck persists as terrain evidence
	local pos = state.loco.cframe.Position
	telegraphRing(pos, 16, 0.9, Color3.fromRGB(255, 170, 90))
	for _, p in state.model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanQuery = false
			if p.Material ~= Enum.Material.Neon then
				p.Color = p.Color:Lerp(Color3.fromRGB(20, 20, 22), 0.55)
			end
		end
	end
	-- kill credit flows through the standard enemy-killed pipeline
	pcall(function()
		require(script.Parent.CacheService).onEnemyKilled(state.model, nil)
	end)
	task.delay(30, function()
		if state.model.Parent then state.model:Destroy() end
		active[state.model] = nil
		ComponentService.unregister(state.model)
	end)
end

function BastionTank.start()
	task.spawn(function()
		while true do
			local dt = 1 / 12
			task.wait(dt)
			BastionTank.step(dt)
		end
	end)
end

function BastionTank.stateOf(model: Model): any?
	return active[model]
end

return BastionTank
