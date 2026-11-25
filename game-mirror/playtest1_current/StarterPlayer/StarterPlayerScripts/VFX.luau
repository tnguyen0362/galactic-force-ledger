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

local hosts: { Part } = {}
local hostIndex = 0
local beams: { Beam } = {}
local beamNodes: { { Part } } = {}
local beamIndex = 0

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
end

local DUSTY: { [string]: boolean } = {
	Slate = true, Concrete = true, Rock = true, Granite = true, Pebble = true, Pavement = true,
	Asphalt = true, Ground = true, Sand = true, Sandstone = true, Fabric = true, Plastic = true,
	Wood = true, WoodPlanks = true, Grass = true, LeafyGrass = true, Ice = true, Snow = true,
	Mud = true, Limestone = true, ClayRoofTiles = true, RoofShingles = true, Cardboard = true,
	Carpet = true, Rubber = true, Leather = true, Plaster = true, CeramicTiles = true, Brick = true,
	Salt = true, Basalt = true, CrackedLava = true, Cobblestone = true,
}

local function emit(kind: string, position: Vector3, normal: Vector3, count: number)
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
			light.Brightness = kind == "flash" and 3.4 or 1.8
			task.delay(0.06, function()
				if light.Parent then light.Brightness = 0 end
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

function VFX.muzzle(position: Vector3, direction: Vector3)
	emit("flash", position, direction, 5)
	emit("dust", position, direction, 1)
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

function VFX.init()
	if #hosts > 0 then
		return
	end
	buildPools()
	nameEmitters()
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

return VFX
