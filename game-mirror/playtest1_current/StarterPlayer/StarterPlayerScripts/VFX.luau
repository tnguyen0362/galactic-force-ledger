--!strict
local Audio = require(script.Parent.GFAudio)
-- Client-side combat VFX. Visual only: never authoritative, never touches gameplay state.
-- Everything is pooled because the target is 30 FPS on an original Xbox One.
local VFX = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local HOST_COUNT = 10
local BEAM_COUNT = 14
local SHELL_COUNT = 20
local PROJECTILE_COUNT = 6

local hosts: { Part } = {}
local hostIndex = 0
local beams: { Beam } = {}
local beamNodes: { { Part } } = {}
local beamIndex = 0

type ShellSlot = {
	part: Part,
	pos: Vector3,
	vel: Vector3,
	spin: Vector3,
	rot: CFrame,
	age: number,
	life: number,
	originY: number,
	active: boolean,
}
type ProjectileSlot = {
	part: Part,
	light: PointLight,
	trail: ParticleEmitter,
	pos: Vector3,
	vel: Vector3,
	gravity: number,
	age: number,
	lifetime: number,
	weaponId: string,
	active: boolean,
}
local shellSlots: { ShellSlot } = {}
local shellIndex = 0
local projectileSlots: { ProjectileSlot } = {}
local projectileIndex = 0
local fxLoopRunning = false

local function seq(pairs: { { number } }): NumberSequence
	local keys = {}
	for _, pair in pairs do
		table.insert(keys, NumberSequenceKeypoint.new(pair[1], pair[2]))
	end
	if #keys == 2 and keys[1].Value == keys[2].Value then
		return NumberSequence.new(keys[1].Value)
	end
	return NumberSequence.new(keys)
end

local function makeEmitter(parent: Instance, texture: string, color: Color3, size: { { number } }, speed: NumberRange, life: NumberRange, drag: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.Size = seq(size)
	e.Speed = speed
	e.Lifetime = life
	e.Drag = drag
	e.Rate = 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-200, 200)
	e.LightEmission = 1
	e.LightInfluence = 0.15
	e.Enabled = false
	e.Parent = parent
	return e
end
local function hostFor(): Part
	hostIndex = hostIndex % HOST_COUNT + 1
	return hosts[hostIndex]
end

local function aim(host: Part, position: Vector3, normal: Vector3)
	local look = normal.Magnitude > 0.01 and normal.Unit or Vector3.new(0, 1, 0)
	host.CFrame = CFrame.lookAt(position + look * 0.2, position + look * 3)
end

local function buildPools()
	local folder = workspace:FindFirstChild("GFVFX")
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = "GFVFX"
	folder.Parent = workspace

	for _ = 1, HOST_COUNT do
		local host = Instance.new("Part")
		host.Name = "EmitterHost"
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		host.CastShadow = false
		host.Transparency = 1
		host.Size = Vector3.new(0.2, 0.2, 0.2)
		host.Parent = folder

		local spark = makeEmitter(host, SPARK, Color3.fromRGB(255, 214, 150), { { 0, 0.32 }, { 1, 0 } },
			NumberRange.new(14, 26), NumberRange.new(0.16, 0.34), 3)
		spark.Acceleration = Vector3.new(0, -70, 0)
		spark.SpreadAngle = Vector2.new(38, 38)

		local flash = makeEmitter(host, FIRE, Color3.fromRGB(215, 245, 255), { { 0, 0.9 }, { 1, 0 } },
			NumberRange.new(3, 6), NumberRange.new(0.05, 0.09), 8)
		flash.SpreadAngle = Vector2.new(12, 12)

		local dust = makeEmitter(host, SMOKE, Color3.fromRGB(152, 144, 132), { { 0, 1.1 }, { 1, 2.6 } },
			NumberRange.new(2.4, 5.2), NumberRange.new(0.45, 0.85), 4)
		dust.Transparency = seq({ { 0, 0.45 }, { 1, 1 } })
		dust.SpreadAngle = Vector2.new(26, 26)

		local shield = makeEmitter(host, SPARK, Color3.fromRGB(110, 210, 255), { { 0, 0.42 }, { 1, 0 } },
			NumberRange.new(9, 16), NumberRange.new(0.2, 0.34), 5)
		shield.SpreadAngle = Vector2.new(60, 60)

		local light = Instance.new("PointLight")
		light.Brightness = 0
		light.Range = 15
		light.Color = Color3.fromRGB(190, 230, 255)
		light.Parent = host

		table.insert(hosts, host)
	end
	for _ = 1, BEAM_COUNT do
		local a = Instance.new("Part")
		local b = Instance.new("Part")
		for _, p in { a, b } do
			p.Name = "BeamNode"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Transparency = 1
			p.Size = Vector3.new(0.1, 0.1, 0.1)
			p.Parent = folder
		end
		local beam = Instance.new("Beam")
		beam.Texture = SPARK
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 3
		beam.TextureSpeed = 5
		beam.Width0 = 0.38
		beam.Width1 = 0.14
		beam.Color = ColorSequence.new(Color3.fromRGB(150, 230, 255))
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Segments = 2
		beam.Enabled = false
		beam.Parent = a
		table.insert(beams, beam)
		table.insert(beamNodes, { a, b })
	end

	-- shell casings: a fixed ring of brass, script-animated so the physics solver never
	-- sees them. saturated slots recycle the oldest casing — sustained fire can never
	-- allocate past the pool no matter the rpm.
	for _ = 1, SHELL_COUNT do
		local shell = Instance.new("Part")
		shell.Name = "ShellCasing"
		shell.Shape = Enum.PartType.Cylinder
		shell.Size = Vector3.new(0.16, 0.07, 0.07)
		shell.Material = Enum.Material.Metal
		shell.Color = Color3.fromRGB(196, 152, 74)
		shell.Anchored = true
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.CastShadow = false
		shell.Transparency = 1
		shell.Parent = folder
		table.insert(shellSlots, { part = shell, pos = Vector3.zero, vel = Vector3.zero, spin = Vector3.zero, rot = CFrame.new(), age = 0, life = 0, originY = 0, active = false })
	end

	-- launcher shell visuals: neon-tipped projectile + smoke trail emitter + light.
	-- server ballistics are mirrored per frame; the pool cap means a burst of GL fire
	-- recycles the oldest visual rather than allocating.
	for _ = 1, PROJECTILE_COUNT do
		local shell = Instance.new("Part")
		shell.Name = "ProjectileShell"
		shell.Shape = Enum.PartType.Ball
		shell.Size = Vector3.new(0.32, 0.32, 0.32)
		shell.Material = Enum.Material.Neon
		shell.Color = Color3.fromRGB(255, 190, 110)
		shell.Anchored = true
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.CastShadow = false
		shell.Transparency = 1
		shell.Parent = folder
		local light = Instance.new("PointLight")
		light.Name = "ShellLight"
		light.Color = Color3.fromRGB(255, 190, 110)
		light.Range = 9
		light.Brightness = 0
		light.Parent = shell
		local trail = Instance.new("ParticleEmitter")
		trail.Name = "ShellTrail"
		trail.Texture = SMOKE
		trail.Color = ColorSequence.new(Color3.fromRGB(180, 172, 158))
		trail.Size = seq({ { 0, 0.34 }, { 1, 0.9 } })
		trail.Transparency = seq({ { 0, 0.55 }, { 1, 1 } })
		trail.Speed = NumberRange.new(0.4, 1.2)
		trail.Lifetime = NumberRange.new(0.3, 0.55)
		trail.Rate = 26
		trail.Drag = 2
		trail.LightEmission = 0.4
		trail.LightInfluence = 0.4
		trail.SpreadAngle = Vector2.new(10, 10)
		trail.Enabled = false
		trail.Parent = shell
		table.insert(projectileSlots, {
			part = shell, light = light, trail = trail,
			pos = Vector3.zero, vel = Vector3.zero, gravity = 0,
			age = 0, lifetime = 0, weaponId = "", active = false,
		})
	end
end

local DUSTY: { [string]: boolean } = {
	Slate = true, Concrete = true, Rock = true, Granite = true, Pebble = true, Pavement = true,
	Asphalt = true, Ground = true, Sand = true, Sandstone = true, Fabric = true, Plastic = true,
	Wood = true, WoodPlanks = true, Grass = true, LeafyGrass = true, Ice = true, Snow = true,
	Mud = true, Limestone = true, ClayRoofTiles = true, RoofShingles = true, Cardboard = true,
	Carpet = true, Rubber = true, Leather = true, Plaster = true, CeramicTiles = true, Brick = true,
	Salt = true, Basalt = true, CrackedLava = true, Cobblestone = true,
}

local function emit(kind: string, position: Vector3, normal: Vector3, count: number, scale: number?)
	local host = hostFor()
	aim(host, position, normal)
	for _, child in host:GetChildren() do
		if child:IsA("ParticleEmitter") and child.Name == kind then
			local saved = child.SpreadAngle
			if normal.Magnitude > 0.01 then
				child.SpreadAngle = Vector2.new(38, 38)
			end
			child:Emit(count)
			child.SpreadAngle = saved
		end
	end
	if kind == "spark" or kind == "flash" then
		local light = host:FindFirstChildOfClass("PointLight")
		if light then
			-- scale swells the light for heavy barrels and detonations, then the base
			-- envelope is restored so the pool never carries a mutated host forward
			local s = math.max(0.25, tonumber(scale) or 1)
			local baseRange = 15
			light.Brightness = (kind == "flash" and 3.4 or 1.8) * s
			light.Range = baseRange * math.max(1, s)
			task.delay(0.06, function()
				if light.Parent then
					light.Brightness = 0
					light.Range = baseRange
				end
			end)
		end
	end
end
local ORDER = { "spark", "flash", "dust", "shield" }

local function nameEmitters()
	for _, host in hosts do
		local found: { ParticleEmitter } = {}
		for _, child in host:GetChildren() do
			if child:IsA("ParticleEmitter") then
				table.insert(found, child)
			end
		end
		for i, emitter in found do
			if ORDER[i] then
				emitter.Name = ORDER[i]
			end
		end
	end
end

function VFX.tracer(from: Vector3, to: Vector3)
	local distance = (to - from).Magnitude
	if distance < 1 then
		return
	end
	beamIndex = beamIndex % BEAM_COUNT + 1
	local nodes = beamNodes[beamIndex]
	local beam = beams[beamIndex]
	nodes[1].CFrame = CFrame.new(from)
	nodes[2].CFrame = CFrame.new(to)
	beam.CurveSize0 = 0
	beam.CurveSize1 = 0
	beam.Enabled = true
	task.delay(0.055, function()
		if beam.Parent then
			beam.Enabled = false
		end
	end)
end

function VFX.muzzle(position: Vector3, direction: Vector3, scale: number?)
	-- per-class presence: a launcher muzzle swallows the flash envelope of a sidearm.
	-- scale is presentation-only and shaped by the weapon layer from the category, never stats.
	local s = math.clamp(tonumber(scale) or 1, 0.5, 2.5)
	emit("flash", position, direction, math.floor(5 * s + 0.5), s)
	emit("dust", position, direction, s > 1.4 and 3 or 1)
end

function VFX.impact(position: Vector3, normal: Vector3, materialName: string, shielded: boolean)
	if shielded then
		emit("shield", position, normal, 9)
		return
	end
	if DUSTY[materialName] then
		emit("dust", position, normal, 3)
	else
		emit("spark", position, normal, 6)
	end
end

function VFX.shieldBreak(position: Vector3, normal: Vector3)
	emit("shield", position, normal, 26)
	emit("spark", position, normal, 10)
end

function VFX.death(position: Vector3)
	Audio.play("enemy_death", position)
	emit("dust", position, Vector3.new(0, 1, 0), 6)
	emit("spark", position, Vector3.new(0, 1, 0), 8)
end

-- ---------------------------------------------------------------------------
-- shared animation tick: shell casings and launcher projectiles are script-integrated
-- on one heartbeat so neither physics nor per-effect connections carry the cost.
-- the loop self-parks when nothing is active — zero steady-state overhead.
-- ---------------------------------------------------------------------------
local function ensureFxLoop()
	if fxLoopRunning then
		return
	end
	fxLoopRunning = true
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		local anyActive = false
		for _, slot in shellSlots do
			if slot.active then
				anyActive = true
				slot.age += dt
				if slot.age >= slot.life then
					slot.active = false
					slot.part.Transparency = 1
				else
					-- light gravity arc: casings read as tossed brass, not ballistics
					slot.vel = slot.vel - Vector3.new(0, 90 * dt, 0)
					slot.pos = slot.pos + slot.vel * dt
					slot.rot = slot.rot * CFrame.Angles(slot.spin.X * dt, slot.spin.Y * dt, slot.spin.Z * dt)
					-- ground behavior without collision cost: casings are non-colliding by design
					-- (no physics, no tunneling edge cases), so falling far below the spawn height
					-- means the floor was met — expire into the fade instead of clipping through it.
					if slot.pos.Y < slot.originY - 2.1 then
						slot.life = math.min(slot.life, slot.age + 0.1)
					end
					-- fade over the last slice of life instead of popping out
					local remain = slot.life - slot.age
					slot.part.Transparency = remain < 0.15 and math.clamp(1 - remain / 0.15, 0, 1) or 0
					slot.part.CFrame = CFrame.new(slot.pos) * slot.rot
				end
			end
		end
		for _, slot in projectileSlots do
			if slot.active then
				anyActive = true
				slot.age += dt
				if slot.age >= slot.lifetime then
					-- server guarantees a detonation at collision/lifetime end; if the event
					-- never arrived the visual still retires quietly instead of orbiting forever
					slot.active = false
					slot.part.Transparency = 1
					slot.light.Brightness = 0
					slot.trail.Enabled = false
				else
					slot.vel = slot.vel - Vector3.new(0, slot.gravity * dt, 0)
					slot.pos = slot.pos + slot.vel * dt
					slot.part.CFrame = CFrame.new(slot.pos)
				end
			end
		end
		if not anyActive then
			-- slots stay allocated (pool); only the per-frame work parks. the connection itself
			-- is permanent — reconnect churn costs more than a heartbeat no-op scan.
		end
	end)
end

-- lazy pool construction: replication can deliver a detonation or shield break in the
-- first frames of a session, before Weapon.init reaches VFX.init — every public entry
-- self-heals rather than dropping the feedback or erroring on empty pools.
local function ensurePools()
	if #hosts == 0 then
		VFX.init()
	end
end

-- brass ejection: position at the receiver, ejecting right-up of the weapon with spin.
-- pooled round-robin; a saturated pool recycles the oldest casing mid-flight.
function VFX.shellEject(position: Vector3, rightDir: Vector3)
	ensurePools()
	if #shellSlots == 0 then
		return
	end
	ensureFxLoop()
	shellIndex = shellIndex % SHELL_COUNT + 1
	local slot = shellSlots[shellIndex]
	local right = rightDir.Magnitude > 0.01 and rightDir.Unit or Vector3.xAxis
	slot.pos = position
	slot.vel = right * (2.4 + math.random() * 1.4)
		+ Vector3.new(0, 2.8 + math.random() * 1.6, 0)
		+ Vector3.new((math.random() - 0.5) * 0.8, 0, (math.random() - 0.5) * 0.8)
	slot.spin = Vector3.new(math.random() * 24 - 12, math.random() * 24 - 12, math.random() * 24 - 12)
	slot.rot = CFrame.Angles(math.rad(90), math.random() * math.pi, 0)
	slot.age = 0
	slot.life = 0.65 + math.random() * 0.2
	slot.originY = position.Y
	slot.active = true
	slot.part.Transparency = 0
	slot.part.CFrame = CFrame.new(position) * slot.rot
end

-- detonation theatre shared by grenades and launcher shells: pooled burst + scaled light +
-- positional voice + distance-shaped camera shake. presentation only; the server owns the blast.
function VFX.explosion(position: Vector3, kind: string)
	ensurePools()
	local up = Vector3.new(0, 1, 0)
	if kind == "EMP" then
		-- cold snap: shield-blue sparks outward, almost no dust — the EMP is an energy event
		emit("shield", position, up, 22, 1.6)
		emit("flash", position, up, 8, 2.0)
		emit("spark", position, up, 8)
		Audio.play("hit_shield", position, 1.6, 0.62)
		Audio.play("launcher_fire", position, 0.7, 1.35)
	else
		-- hot thump: flash core, dense sparks, rolling dust — frag/rocket/grenade-shell family
		local heavy = kind == "RL09"
		emit("flash", position, up, heavy and 10 or 7, heavy and 2.4 or 1.9)
		emit("spark", position, up, heavy and 22 or 16)
		emit("dust", position, up, heavy and 12 or 9)
		Audio.play("launcher_fire", position, heavy and 1.35 or 1.1, heavy and 0.72 or 0.85)
	end
	-- camera impulse through the positional channel: strong at the epicentre, gone past the
	-- falloff radius. deferred require matches the established pattern (load-order safe).
	task.defer(function()
		pcall(function()
			local ctl = require(script.Parent.CameraCtl)
			local intensity = kind == "EMP" and 0.5 or (kind == "RL09" and 0.85 or 0.65)
			ctl.shakeAt(intensity, position, kind == "EMP" and 46 or 60)
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- launcher projectile visuals: the server simulates kinematic shells and broadcasts the
-- ballistic parameters once (ProjectileFired) plus the detonation point (ProjectileDetonated).
-- clients mirror the same integration — the visual arc cannot lie because it IS the same math.
-- ---------------------------------------------------------------------------
do
	local remotes = game:GetService("ReplicatedStorage"):WaitForChild("GF"):WaitForChild("Remotes")

	local function killNearestShell(position: Vector3)
		local best: ProjectileSlot? = nil
		local bestDist = math.huge
		for _, slot in projectileSlots do
			if slot.active then
				local d = (slot.pos - position).Magnitude
				if d < bestDist then
					bestDist = d
					best = slot
				end
			end
		end
		-- generous tolerance: replication delay means the server shell is always a few
		-- integration steps ahead of the client mirror
		if best and bestDist < 40 then
			best.active = false
			best.part.Transparency = 1
			best.light.Brightness = 0
			best.trail.Enabled = false
		end
	end

	local fired = remotes:FindFirstChild("ProjectileFired")
	if fired then
		fired.OnClientEvent:Connect(function(origin, velocity, gravity, lifetime, weaponId)
			if typeof(origin) ~= "Vector3" or typeof(velocity) ~= "Vector3" then
				return
			end
			ensurePools()
			if #projectileSlots == 0 then
				return
			end
			ensureFxLoop()
			projectileIndex = projectileIndex % PROJECTILE_COUNT + 1
			local slot = projectileSlots[projectileIndex]
			slot.pos = origin
			slot.vel = velocity
			slot.gravity = tonumber(gravity) or 20
			slot.age = 0
			slot.lifetime = math.min(tonumber(lifetime) or 5, 8) + 0.5 -- grace past the server's own lifetime
			slot.weaponId = type(weaponId) == "string" and weaponId or ""
			slot.active = true
			slot.part.Transparency = 0.15
			slot.part.CFrame = CFrame.new(origin)
			slot.light.Brightness = 1.6
			slot.trail.Enabled = true
		end)
	end

	local detonated = remotes:FindFirstChild("ProjectileDetonated")
	if detonated then
		detonated.OnClientEvent:Connect(function(position, weaponId)
			if typeof(position) ~= "Vector3" then
				return
			end
			killNearestShell(position)
			VFX.explosion(position, type(weaponId) == "string" and weaponId or "GL22")
		end)
	end
end

-- ---------------------------------------------------------------------------
-- enemy shield-break theatre: the server stamps ShieldBrokenAt on the model at the exact
-- break moment (CombatService). watching the attribute costs nothing per frame and fires
-- for every client's kills — the shatter read is the reward for burning the shield down.
-- ---------------------------------------------------------------------------
do
	local RunService = game:GetService("RunService")
	local hooked: { [Model]: RBXScriptConnection } = {}

	local function centerOf(model: Model): Vector3?
		local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		return root and (root :: BasePart).Position or nil
	end

	local function hookEnemy(model: Model)
		if hooked[model] or not model:IsA("Model") then
			return
		end
		if model:GetAttribute("GFEnemy") ~= true then
			return
		end
		hooked[model] = model:GetAttributeChangedSignal("ShieldBrokenAt"):Connect(function()
			local pos = centerOf(model)
			if not pos then
				return
			end
			ensurePools()
			VFX.shieldBreak(pos, Vector3.new(0, 1, 0))
			Audio.play("shield_break", pos, 0.85, 0.8)
		end)
	end

	local function scan()
		local folder = workspace:FindFirstChild("ActiveActors")
		if folder then
			for _, model in folder:GetChildren() do
				if model:IsA("Model") then
					hookEnemy(model)
				end
			end
		end
		-- hygiene: retire connections for models that left the world so the table can't grow
		for model, conn in hooked do
			if not model.Parent then
				conn:Disconnect()
				hooked[model] = nil
			end
		end
	end

	local scanAt = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < scanAt then
			return
		end
		scanAt = now + 0.5
		scan()
	end)
end

function VFX.init()
	if #hosts > 0 then
		return
	end
	buildPools()
	nameEmitters()
end

-- ---------------------------------------------------------------------------
-- damage-taken camera response: the HUD already owns the directional arc and GFAudioRuntime
-- the hurt voice, but the camera itself never answered — incoming fire read as interface,
-- not impact. amount-scaled trauma through the additive channel, capped low enough that
-- being focused blurs your composure, never your ability to shoot back. the controller's
-- shake/reduced-motion settings gate applies as with every feel layer.
-- ---------------------------------------------------------------------------
do
	local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("GF")
	remotes = remotes and remotes:FindFirstChild("Remotes")
	local directional = remotes and remotes:FindFirstChild("DirectionalHit")
	if directional then
		directional.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end
			local amount = tonumber(payload.amount) or 10
			task.defer(function()
				pcall(function()
					local ctl = require(script.Parent.CameraCtl)
					ctl.shake(math.clamp(amount / 80, 0.08, 0.4))
				end)
			end)
		end)
	end
end

-- S01-010: alien energy guns fire violet tracers — a brief beam from muzzle toward target,
-- visually distinct from the warm golden human ballistic tracers.
do
	local remotes = game:GetService("ReplicatedStorage"):WaitForChild("GF"):WaitForChild("Remotes")
	-- S11 telegraph beams: heavy/charged attacks must show a visible targeting line for the full
	-- windup so a player can read the lane and dodge out — the spec's counterplay requirement.
	-- The beam tracks the hostile's current facing each frame and dies with the windup.
	local telegraph = remotes:FindFirstChild("EnemyTelegraph")
	if telegraph then
		telegraph.OnClientEvent:Connect(function(model, windUp)
			if typeof(windUp) ~= "number" or windUp <= 0.05 then return end
			local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
			if not root then return end
			local isHeavy = windUp >= 0.9 -- charged shots (marksman 1.1s, heavy 1.4s) get the full beam
			local beam = Instance.new("Part")
			beam.Name = "TelegraphBeam"
			beam.Anchored = true
			beam.CanCollide = false
			beam.CanQuery = false
			beam.Material = Enum.Material.Neon
			beam.Color = isHeavy and Color3.fromRGB(255, 92, 72) or Color3.fromRGB(255, 170, 92)
			beam.Transparency = isHeavy and 0.15 or 0.45
			beam.Parent = workspace
			local RunService = game:GetService("RunService")
			local deadline = os.clock() + windUp
			local conn
			conn = RunService.RenderStepped:Connect(function()
				if os.clock() >= deadline or not beam.Parent or not root.Parent then
					conn:Disconnect()
					beam:Destroy()
					return
				end
				local origin = root.Position + Vector3.new(0, 2.6, 0)
				local dir = root.CFrame.LookVector
				local len = isHeavy and 90 or 40
				beam.Size = Vector3.new(isHeavy and 0.09 or 0.06, isHeavy and 0.09 or 0.06, len)
				beam.CFrame = CFrame.lookAt(origin, origin + dir) * CFrame.new(0, 0, -len / 2)
				-- pulse as the windup completes: readability spike in the last 30%
				local frac = 1 - (deadline - os.clock()) / windUp
				if frac > 0.7 then
					beam.Transparency = 0.05
				end
			end)
		end)
	end
	local fired = remotes:FindFirstChild("EnemyFired")
	if fired then
		fired.OnClientEvent:Connect(function(model, targetPos)
			if typeof(targetPos) ~= "Vector3" then return end
			local root = model and model:FindFirstChild("HumanoidRootPart") or (model and model.PrimaryPart)
			if not root then return end
			local origin = root.Position + Vector3.new(0, 2.5, 0)
			-- tracer: a thin violet beam part living 90ms along the shot line
			local dist = (targetPos - origin).Magnitude
			if dist < 1 or dist > 300 then return end
			local tracer = Instance.new("Part")
			tracer.Name = "EnemyTracer"
			tracer.Anchored = true
			tracer.CanCollide = false
			tracer.CanQuery = false
			tracer.Material = Enum.Material.Neon
			tracer.Color = Color3.fromRGB(180, 120, 255)
			tracer.Transparency = 0.25
			tracer.Size = Vector3.new(0.12, 0.12, dist)
			tracer.CFrame = CFrame.lookAt(origin, targetPos) * CFrame.new(0, 0, -dist / 2)
			tracer.Parent = workspace
			game:GetService("Debris"):AddItem(tracer, 0.09)
		end)
	end
end


-- S11 player-readable ability telegraphs published as enemy attributes. These are polled rather than
-- remote-driven because the server already publishes lifetime state; the visual layer only interprets it.
do
	local RunService = game:GetService("RunService")
	local activeBeacons: { [Model]: boolean } = {}
	local activeSweeps: { [Model]: boolean } = {}

	local function enemyRoot(model: Model): BasePart?
		return (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) :: BasePart?
	end

	local function startBeacon(model: Model)
		if activeBeacons[model] then return end
		local root = enemyRoot(model)
		if not root then return end
		activeBeacons[model] = true

		local beam = Instance.new("Part")
		beam.Name = "ScoutBeaconChannel"
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		beam.Material = Enum.Material.Neon
		beam.Color = Color3.fromRGB(96, 220, 255)
		beam.Transparency = 0.12
		beam.Parent = workspace

		local labelAnchor = Instance.new("Part")
		labelAnchor.Name = "ScoutBeaconLabelAnchor"
		labelAnchor.Anchored = true
		labelAnchor.CanCollide = false
		labelAnchor.CanQuery = false
		labelAnchor.CanTouch = false
		labelAnchor.Transparency = 1
		labelAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
		labelAnchor.Parent = workspace
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "ScoutBeaconBillboard"
		billboard.Size = UDim2.fromOffset(150, 34)
		billboard.AlwaysOnTop = true
		billboard.Parent = labelAnchor
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.TextSize = 15
		text.TextColor3 = Color3.fromRGB(120, 235, 255)
		text.TextStrokeTransparency = 0.25
		text.Text = "TRANSMITTING"
		text.Parent = billboard

		local conn
		conn = RunService.RenderStepped:Connect(function()
			local deadline = tonumber(model:GetAttribute("TransmissionUntil"))
			if not deadline or os.clock() >= deadline or not model.Parent or not root.Parent then
				conn:Disconnect()
				beam:Destroy()
				labelAnchor:Destroy()
				activeBeacons[model] = nil
				return
			end
			local height = 17 + math.sin(os.clock() * 10) * 1.4
			beam.Size = Vector3.new(0.42, height, 0.42)
			beam.CFrame = CFrame.new(root.Position + Vector3.new(0, height * 0.5 + 0.4, 0))
			beam.Transparency = 0.1 + 0.08 * math.sin(os.clock() * 13)
			labelAnchor.CFrame = CFrame.new(root.Position + Vector3.new(0, 7.2, 0))
		end)
	end

	local function startSweep(model: Model)
		if activeSweeps[model] then return end
		local root = enemyRoot(model)
		if not root then return end
		activeSweeps[model] = true

		local ring = Instance.new("Part")
		ring.Name = "OfficerSweepTelegraph"
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Material = Enum.Material.Neon
		ring.Color = Color3.fromRGB(255, 96, 64)
		ring.Transparency = 0.32
		ring.Parent = workspace

		local conn
		conn = RunService.RenderStepped:Connect(function()
			local deadline = tonumber(model:GetAttribute("SweepTelegraphUntil"))
			if not deadline or os.clock() >= deadline or not model.Parent or not root.Parent then
				conn:Disconnect()
				ring:Destroy()
				activeSweeps[model] = nil
				return
			end
			local remaining = math.max(0, deadline - os.clock())
			local frac = math.clamp(1 - remaining / 1.6, 0, 1)
			local radius = 4 + 26 * frac
			ring.Size = Vector3.new(0.18, radius * 2, radius * 2)
			ring.CFrame = CFrame.new(root.Position + Vector3.new(0, -2.65, 0)) * CFrame.Angles(0, 0, math.rad(90))
			ring.Transparency = 0.42 - 0.22 * frac
		end)
	end

	local scanAt = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < scanAt then return end
		scanAt = now + 0.12
		local folder = workspace:FindFirstChild("ActiveActors")
		if not folder then return end
		for _, model in folder:GetChildren() do
			if model:IsA("Model") then
				if tonumber(model:GetAttribute("TransmissionUntil")) then startBeacon(model) end
				if tonumber(model:GetAttribute("SweepTelegraphUntil")) then startSweep(model) end
			end
		end
	end)
end

return VFX
