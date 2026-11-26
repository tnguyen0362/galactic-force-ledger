--!strict
-- MissionSites: physical construction library for operation objective sites.
-- Representative blockout construction (final art deferred per owner directive) —
-- dark military palette, neon accents, ground-adaptive placement on real terrain.

local Workspace = game:GetService("Workspace")

local MissionSites = {}

local METAL = Color3.fromRGB(52, 56, 66)
local METAL_DARK = Color3.fromRGB(38, 40, 48)
local ARMOR = Color3.fromRGB(64, 68, 80)
local NEON_CYAN = Color3.fromRGB(96, 214, 232)
local NEON_AMBER = Color3.fromRGB(255, 198, 146)
local NEON_RED = Color3.fromRGB(232, 96, 96)
local SANDBAG = Color3.fromRGB(96, 88, 72)

-- ground probe: live terrain raycast, fallback flat
local function groundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	local hit = Workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -1200, 0), params)
	if hit then return hit.Position.Y end
	return 24
end

local function part(parent: Instance, name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Anchored = true
	p.Color = color
	p.Material = neon and Enum.Material.Neon or (material or Enum.Material.Metal)
	p.Parent = parent
	return p
end

-- snap a structure part onto terrain: y is ground + halfHeight - embed
local function onGround(parent: Instance, name: string, size: Vector3, x: number, z: number, color: Color3, material: Enum.Material?, embed: number?): Part
	local gy = groundY(x, z)
	return part(parent, name, size, Vector3.new(x, gy + size.Y / 2 - (embed or 0.3), z), color, material)
end

-- sandbag arc facing outward from center
local function sandbags(parent: Instance, cx: number, cz: number, radius: number, count: number, facing: number?)
	for i = 1, count do
		local a = (facing or 0) + (i - count / 2 - 0.5) * 0.5
		local x = cx + math.cos(a) * radius
		local z = cz + math.sin(a) * radius
		local bag = onGround(parent, "Sandbag", Vector3.new(5.5, 2.0, 1.4), x, z, SANDBAG, Enum.Material.Fabric)
		bag.CFrame = CFrame.lookAt(bag.Position, Vector3.new(cx + math.cos(a) * (radius + 10), bag.Position.Y, cz + math.sin(a) * (radius + 10)))
	end
end

-- perimeter wall ring with entrance gaps
local function wallRing(parent: Instance, cx: number, cz: number, radius: number, height: number, gapEvery: number, gapWidth: number)
	local segments = math.floor(radius * 0.9)
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		-- gaps: skip segments near gap angles
		local inGap = false
		for g = 1, gapEvery do
			local gapAngle = (g / gapEvery) * math.pi * 2
			local diff = math.abs((a - gapAngle + math.pi) % (math.pi * 2) - math.pi)
			if diff < (gapWidth / radius) then inGap = true break end
		end
		if inGap then continue end
		local x = cx + math.cos(a) * radius
		local z = cz + math.sin(a) * radius
		local segLen = (math.pi * 2 * radius / segments) + 0.4
		local w = onGround(parent, "Wall", Vector3.new(segLen, height, 1.6), x, z, ARMOR, Enum.Material.Concrete, 0.8)
		w.CFrame = CFrame.lookAt(w.Position, Vector3.new(cx, w.Position.Y, cz))
	end
end

local function watchtower(parent: Instance, x: number, z: number)
	local gy = groundY(x, z)
	part(parent, "TowerLeg", Vector3.new(1.2, 12, 1.2), Vector3.new(x - 1.5, gy + 6, z - 1.5), METAL_DARK)
	part(parent, "TowerLeg", Vector3.new(1.2, 12, 1.2), Vector3.new(x + 1.5, gy + 6, z - 1.5), METAL_DARK)
	part(parent, "TowerLeg", Vector3.new(1.2, 12, 1.2), Vector3.new(x - 1.5, gy + 6, z + 1.5), METAL_DARK)
	part(parent, "TowerLeg", Vector3.new(1.2, 12, 1.2), Vector3.new(x + 1.5, gy + 6, z + 1.5), METAL_DARK)
	part(parent, "TowerDeck", Vector3.new(5.5, 0.8, 5.5), Vector3.new(x, gy + 12.2, z), METAL)
	part(parent, "TowerRoof", Vector3.new(6.5, 0.6, 6.5), Vector3.new(x, gy + 16.5, z), METAL_DARK)
	for _, dx in { -2.6, 2.6 } do
		part(parent, "TowerPost", Vector3.new(0.4, 4, 0.4), Vector3.new(x + dx, gy + 14.4, z - 2.6), METAL_DARK)
		part(parent, "TowerPost", Vector3.new(0.4, 4, 0.4), Vector3.new(x + dx, gy + 14.4, z + 2.6), METAL_DARK)
	end
	part(parent, "TowerLamp", Vector3.new(1, 0.5, 1), Vector3.new(x, gy + 16.1, z), NEON_AMBER, nil, true)
end

local function crate(parent: Instance, x: number, z: number, size: number?)
	local s = size or 2.4
	local c = onGround(parent, "Crate", Vector3.new(s, s, s), x, z, Color3.fromRGB(88, 76, 56), Enum.Material.Wood)
	c.CFrame = c.CFrame * CFrame.Angles(0, math.rad((x * 7 + z * 13) % 40 - 20), 0)
end

-- ============ site builders ============

local builders: { [string]: (Model, Vector3) -> () } = {}

builders.stronghold = function(model: Model, pos: Vector3)
	local cx, cz = pos.X, pos.Z
	local gy = groundY(cx, cz)
	-- tiered central keep
	part(model, "KeepBase", Vector3.new(22, 8, 18), Vector3.new(cx, gy + 4, cz), METAL)
	part(model, "KeepMid", Vector3.new(15, 6, 12), Vector3.new(cx, gy + 11, cz), ARMOR)
	part(model, "KeepTop", Vector3.new(9, 4.5, 7), Vector3.new(cx, gy + 16.2, cz), METAL_DARK)
	-- comm mast
	part(model, "Mast", Vector3.new(1, 22, 1), Vector3.new(cx + 6, gy + 11, cz - 5), METAL_DARK)
	part(model, "MastBeacon", Vector3.new(1.6, 1.6, 1.6), Vector3.new(cx + 6, gy + 22.5, cz - 5), NEON_RED, nil, true)
	-- capture console at keep entrance — THE primary interaction point
	local console = part(model, "CaptureConsole", Vector3.new(2.4, 4, 1.6), Vector3.new(cx, gy + 2, cz + 11), METAL_DARK)
	console:SetAttribute("GFInteract", "CaptureConsole")
	console:SetAttribute("InteractPrompt", "Secure the stronghold")
	part(model, "ConsoleScreen", Vector3.new(1.8, 1.2, 0.2), Vector3.new(cx, gy + 3.2, cz + 11.85), NEON_CYAN, nil, true)
	-- perimeter walls with 3 entrance gaps, radius ~60 (inside the 85 footprint)
	wallRing(model, cx, cz, 58, 4.4, 3, 10)
	-- watchtowers at 2 corners
	watchtower(model, cx + 40, cz + 40)
	watchtower(model, cx - 40, cz - 40)
	-- defensive sandbag arcs facing outward at gap approaches
	sandbags(model, cx + 52, cz, 8, 4)
	sandbags(model, cx - 52, cz, 8, 4)
	sandbags(model, cx, cz - 52, 8, 4)
	-- interior clutter
	for i = 1, 5 do
		crate(model, cx + ((i * 13) % 30) - 15, cz + ((i * 17) % 24) - 12)
	end
	-- banner marker (visible at distance)
	part(model, "Banner", Vector3.new(0.3, 8, 3), Vector3.new(cx, gy + 22, cz + 9), NEON_CYAN, nil, true)
end

builders.shield_generator = function(model: Model, pos: Vector3)
	local cx, cz = pos.X, pos.Z
	local gy = groundY(cx, cz)
	-- emitter tower
	part(model, "EmitterBase", Vector3.new(8, 3, 8), Vector3.new(cx, gy + 1.5, cz), METAL)
	part(model, "EmitterTower", Vector3.new(3, 10, 3), Vector3.new(cx, gy + 8, cz), ARMOR)
	-- THE destruction target — destructible structure part
	local core = part(model, "EmitterCore", Vector3.new(3.6, 3.6, 3.6), Vector3.new(cx, gy + 14.5, cz), NEON_CYAN, nil, true)
	core.Shape = Enum.PartType.Ball
	core.CanCollide = false
	core:SetAttribute("GFStructure", true)
	core:SetAttribute("GFIntegrity", 400)
	core:SetAttribute("GFIntegrityMax", 400)
	-- power conduits
	for i = 1, 3 do
		local a = (i / 3) * math.pi * 2
		local x = cx + math.cos(a) * 9
		local z = cz + math.sin(a) * 9
		part(model, "Conduit", Vector3.new(1.4, 2.5, 1.4), Vector3.new(x, groundY(x, z) + 1.2, z), METAL_DARK)
	end
	-- light perimeter defense
	sandbags(model, cx + 12, cz, 6, 3)
	sandbags(model, cx - 12, cz, 6, 3)
	crate(model, cx + 5, cz + 7)
end

builders.comms_relay = function(model: Model, pos: Vector3)
	local cx, cz = pos.X, pos.Z
	local gy = groundY(cx, cz)
	-- relay tower with dish
	part(model, "RelayBase", Vector3.new(6, 2.5, 6), Vector3.new(cx, gy + 1.2, cz), METAL)
	part(model, "RelayTower", Vector3.new(2.2, 16, 2.2), Vector3.new(cx, gy + 9, cz), ARMOR)
	local dish = part(model, "RelayDish", Vector3.new(7, 7, 1), Vector3.new(cx, gy + 18, cz), METAL)
	dish.Shape = Enum.PartType.Cylinder
	dish.CFrame = CFrame.new(Vector3.new(cx, gy + 18, cz)) * CFrame.Angles(math.rad(30), 0, 0)
	part(model, "RelayBeacon", Vector3.new(1.2, 1.2, 1.2), Vector3.new(cx, gy + 21, cz), NEON_RED, nil, true)
	-- THE interaction terminal
	local terminal = part(model, "RelayTerminal", Vector3.new(2, 3.4, 1.2), Vector3.new(cx + 4, gy + 1.7, cz + 3), METAL_DARK)
	terminal:SetAttribute("GFInteract", "CommsRelay")
	terminal:SetAttribute("InteractPrompt", "Disable relay")
	part(model, "TerminalScreen", Vector3.new(1.5, 1, 0.2), Vector3.new(cx + 4, gy + 2.8, cz + 3.65), NEON_CYAN, nil, true)
	-- small perimeter + props
	sandbags(model, cx, cz + 12, 6, 3)
	crate(model, cx - 5, cz + 4)
	crate(model, cx - 7, cz - 3, 1.8)
end

builders.supply_cache = function(model: Model, pos: Vector3)
	local cx, cz = pos.X, pos.Z
	local gy = groundY(cx, cz)
	-- supply crates arrangement
	crate(model, cx - 3, cz, 3)
	crate(model, cx + 1, cz + 2, 2.6)
	crate(model, cx + 3.5, cz - 1.5, 2.2)
	crate(model, cx - 1, cz - 3, 2)
	crate(model, cx, cz + 4.5, 1.8)
	-- cache terminal
	local terminal = part(model, "SupplyTerminal", Vector3.new(1.8, 3, 1), Vector3.new(cx + 5, gy + 1.5, cz + 1), METAL_DARK)
	terminal:SetAttribute("GFInteract", "SupplyCache")
	terminal:SetAttribute("InteractPrompt", "Secure supplies")
	part(model, "SupplyLamp", Vector3.new(1.2, 0.5, 0.8), Vector3.new(cx + 5, gy + 3.4, cz + 1), NEON_AMBER, nil, true)
	-- camo netting hint: flat panel overhead
	local net = part(model, "Netting", Vector3.new(12, 0.2, 10), Vector3.new(cx, gy + 5, cz), Color3.fromRGB(52, 66, 48), Enum.Material.Fabric)
	net.Transparency = 0.35
	net.CanCollide = false
end

builders.extraction_pad = function(model: Model, pos: Vector3)
	local cx, cz = pos.X, pos.Z
	local gy = groundY(cx, cz)
	-- flat pad surface: wide low cylinder
	local pad = part(model, "Pad", Vector3.new(2, 34, 34), Vector3.new(cx, gy + 0.5, cz), ARMOR, Enum.Material.Concrete)
	pad.Shape = Enum.PartType.Cylinder
	pad.CFrame = CFrame.new(Vector3.new(cx, gy + 0.5, cz)) * CFrame.Angles(0, 0, math.rad(90))
	-- perimeter lights: 8 neon strips around the rim
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local x = cx + math.cos(a) * 15
		local z = cz + math.sin(a) * 15
		part(model, "PadLight", Vector3.new(2.4, 0.3, 0.8), Vector3.new(x, gy + 1.1, z), NEON_CYAN, nil, true)
	end
	-- center hologram marker (thin, noncolliding)
	local holo = part(model, "PadHolo", Vector3.new(4, 0.1, 4), Vector3.new(cx, gy + 1.05, cz), NEON_CYAN, nil, true)
	holo.Transparency = 0.6
	holo.CanCollide = false
end

builders.artillery = function(model: Model, pos: Vector3)
	local cx, cz = pos.X, pos.Z
	local gy = groundY(cx, cz)
	-- gun emplacement: base + pivot + barrel
	part(model, "GunBase", Vector3.new(7, 2.5, 7), Vector3.new(cx, gy + 1.2, cz), METAL)
	part(model, "GunPivot", Vector3.new(4, 3, 4), Vector3.new(cx, gy + 3.8, cz), ARMOR)
	local barrel = part(model, "GunBarrel", Vector3.new(1.6, 1.6, 12), Vector3.new(cx, gy + 5.5, cz - 4), METAL_DARK)
	barrel.CFrame = CFrame.new(Vector3.new(cx, gy + 5.5, cz - 4)) * CFrame.Angles(math.rad(-25), 0, 0)
	-- destruction target: the gun itself
	local gun = part(model, "ArtilleryGun", Vector3.new(4.2, 3.2, 4.2), Vector3.new(cx, gy + 3.8, cz), ARMOR)
	gun.Transparency = 1
	gun.CanCollide = false
	gun:SetAttribute("GFStructure", true)
	gun:SetAttribute("GFIntegrity", 500)
	gun:SetAttribute("GFIntegrityMax", 500)
	-- ammo crates
	crate(model, cx + 5, cz + 3, 2)
	crate(model, cx + 6.5, cz + 1, 1.8)
	crate(model, cx - 5, cz + 4, 2.2)
	sandbags(model, cx, cz + 10, 7, 4)
end

-- ============ public interface ============

function MissionSites.build(siteType: string, position: Vector3, opts: any?): Model
	local builder = builders[siteType]
	if not builder then
		error("MissionSites: unknown site type " .. tostring(siteType))
	end
	local model = Instance.new("Model")
	model.Name = "MissionSite_" .. siteType
	builder(model, position)
	-- anchor the model pivot at the position for distance queries
	model.WorldPivot = CFrame.new(position)
	model.Parent = (opts and opts.parent) or Workspace
	return model
end

function MissionSites.destroy(site: Model)
	if site and site.Parent then
		site:Destroy()
	end
end

return MissionSites
