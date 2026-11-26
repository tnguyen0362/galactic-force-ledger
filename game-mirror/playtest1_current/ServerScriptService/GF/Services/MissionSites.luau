--!strict
-- MissionSites: physical construction library for operation objective sites.
-- Representative blockout construction (final art deferred per owner directive): simple
-- block/cylinder parts, dark military materials, cyan/amber energy accents, and no terrain
-- mutation. Structures are placed from live terrain probes so perimeter pieces step with slopes
-- instead of floating as a single rigid layout.

local Workspace = game:GetService("Workspace")

local MissionSites = {}

local TAU = math.pi * 2
local EMBED = 0.42

local METAL_DARK = Color3.fromRGB(42, 44, 52)
local METAL = Color3.fromRGB(56, 60, 70)
local ARMOR = Color3.fromRGB(70, 74, 82)
local CONCRETE = Color3.fromRGB(60, 64, 72)
local SANDBAG = Color3.fromRGB(94, 88, 72)
local CRATE = Color3.fromRGB(82, 76, 60)
local CRATE_DARK = Color3.fromRGB(58, 56, 50)
local CAMO = Color3.fromRGB(54, 66, 56)
local CYAN = Color3.fromRGB(96, 214, 232)
local AMBER = Color3.fromRGB(255, 198, 146)

-- TerrainService is present in the game tree, but keeping the require behind pcall makes this
-- construction library safe to load in isolation. Its sampler is only a fallback there; the
-- raycasts below intentionally use the same real-terrain-first contract.
local TerrainService: any = nil
do
	local ok, service = pcall(function()
		return require(script.Parent.TerrainService)
	end)
	if ok then
		TerrainService = service
	end
end

local fallbackGroundY = 0

local function ground(x: number, z: number): number
	if TerrainService and type(TerrainService.groundSurface) == "function" then
		local ok, result = pcall(function()
			return TerrainService.groundSurface(x, z)
		end)
		if ok and type(result) == "number" then
			return result
		end
	end

	local terrainParams = RaycastParams.new()
	terrainParams.FilterType = Enum.RaycastFilterType.Include
	terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
	terrainParams.IgnoreWater = true
	local terrainHit = Workspace:Raycast(Vector3.new(x, 1600, z), Vector3.new(0, -2400, 0), terrainParams)
	if terrainHit then
		return terrainHit.Position.Y
	end

	-- Non-terrain fallback for isolated test places/baseplates. Mission-site parts are parented
	-- only after construction, so this raycast cannot mistake the site currently being built for ground.
	local worldParams = RaycastParams.new()
	worldParams.FilterType = Enum.RaycastFilterType.Exclude
	worldParams.FilterDescendantsInstances = {}
	worldParams.IgnoreWater = true
	local worldHit = Workspace:Raycast(Vector3.new(x, 1600, z), Vector3.new(0, -2400, 0), worldParams)
	if worldHit then
		return worldHit.Position.Y
	end
	return fallbackGroundY
end

-- Rotate a local x/z offset exactly like a positive Roblox yaw rotation.
local function rotateXZ(lx: number, lz: number, yaw: number): (number, number)
	local c = math.cos(yaw)
	local s = math.sin(yaw)
	return lx * c + lz * s, -lx * s + lz * c
end

local function localXZ(center: Vector3, yaw: number, lx: number, lz: number): (number, number)
	local rx, rz = rotateXZ(lx, lz, yaw)
	return center.X + rx, center.Z + rz
end

-- Yaw that makes a part's local +X axis point along direction (dx, dz).
local function yawForXDirection(dx: number, dz: number): number
	return math.atan2(-dz, dx)
end

-- Yaw that makes a part's local +Z axis point along direction (dx, dz).
local function yawForZDirection(dx: number, dz: number): number
	return math.atan2(dx, dz)
end

local function tangentYaw(center: Vector3, siteYaw: number, lx: number, lz: number): number
	local rx, rz = rotateXZ(lx, lz, siteYaw)
	local mag = math.sqrt(rx * rx + rz * rz)
	if mag < 0.001 then
		return siteYaw
	end
	return yawForXDirection(-rz / mag, rx / mag)
end

local function angleDelta(a: number, b: number): number
	return math.atan2(math.sin(a - b), math.cos(a - b))
end

local function mkPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, canCollide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	if canCollide == nil then
		p.CanCollide = true
	else
		p.CanCollide = canCollide
	end
	if canCollide == false then
		p.CanQuery = false
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function partAtWorld(parent: Instance, x: number, y: number, z: number, size: Vector3, orientation: number, name: string, color: Color3, material: Enum.Material, canCollide: boolean?): Part
	return mkPart(parent, name, size, CFrame.new(x, y, z) * CFrame.Angles(0, orientation, 0), color, material, canCollide)
end

local function partAtLocal(parent: Instance, center: Vector3, siteYaw: number, lx: number, lz: number, y: number, size: Vector3, orientation: number, name: string, color: Color3, material: Enum.Material, canCollide: boolean?): Part
	local wx, wz = localXZ(center, siteYaw, lx, lz)
	return partAtWorld(parent, wx, y, wz, size, orientation, name, color, material, canCollide)
end

-- Places the underside of a part EMBED studs into the terrain at its centre. Small modular
-- pieces therefore remain grounded on slopes; thin pads may receive a small positive lift.
local function partOnGround(parent: Instance, center: Vector3, siteYaw: number, lx: number, lz: number, size: Vector3, orientation: number, name: string, color: Color3, material: Enum.Material, canCollide: boolean?, lift: number?): Part
	local wx, wz = localXZ(center, siteYaw, lx, lz)
	local gy = ground(wx, wz)
	local y = gy + size.Y * 0.5 - EMBED + (lift or 0)
	return partAtWorld(parent, wx, y, wz, size, orientation, name, color, material, canCollide)
end

-- Vertical support whose bottom is embedded in the local terrain and whose top reaches a
-- requested world Y. Used under flat landing pads without flattening or otherwise editing terrain.
local function supportUnder(parent: Instance, center: Vector3, siteYaw: number, lx: number, lz: number, topY: number, sizeX: number, sizeZ: number, orientation: number, name: string, color: Color3, material: Enum.Material): Part
	local wx, wz = localXZ(center, siteYaw, lx, lz)
	local gy = ground(wx, wz)
	local bottom = gy - EMBED
	local height = math.max(0.8, topY - bottom)
	local y = bottom + height * 0.5
	return partAtWorld(parent, wx, y, wz, Vector3.new(sizeX, height, sizeZ), orientation, name, color, material, true)
end

local function addPointLight(part: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
end

type Entrance = {
	angle: number,
	width: number,
}

-- Fixed-arc perimeter wall. Entrances are true omissions in the ring; the extra half-segment
-- margin prevents adjacent wall ends from encroaching into the opening.
local function addWallRing(parent: Instance, center: Vector3, siteYaw: number, radius: number, height: number, thickness: number, segmentCount: number, entrances: { Entrance }, namePrefix: string): number
	local segmentAngle = TAU / segmentCount
	local segmentLength = TAU * radius / segmentCount + 0.45
	local written = 0
	for i = 0, segmentCount - 1 do
		local angle = i * segmentAngle
		local blocked = false
		for _, entrance in ipairs(entrances) do
			local threshold = entrance.width / (2 * radius) + segmentAngle * 1.05
			if math.abs(angleDelta(angle, entrance.angle)) < threshold then
				blocked = true
				break
			end
		end
		if not blocked then
			local lx = math.cos(angle) * radius
			local lz = math.sin(angle) * radius
			local orientation = tangentYaw(center, siteYaw, lx, lz)
			partOnGround(parent, center, siteYaw, lx, lz, Vector3.new(segmentLength, height, thickness), orientation, namePrefix .. tostring(i), ARMOR, Enum.Material.Concrete, true)
			written += 1
		end
	end
	return written
end

-- Three-piece shallow sandbag arc. The centre bag is tangent to the site radius and the flank
-- bags turn back slightly, producing real infantry cover facing away from the installation.
local function addSandbagNest(parent: Instance, center: Vector3, siteYaw: number, angle: number, radius: number, index: number)
	local ux = math.cos(angle)
	local uz = math.sin(angle)
	local tx = -uz
	local tz = ux
	local rtx, rtz = rotateXZ(tx, tz, siteYaw)
	local baseOrientation = yawForXDirection(rtx, rtz)

	local lx = ux * radius
	local lz = uz * radius
	partOnGround(parent, center, siteYaw, lx, lz, Vector3.new(5.6, 1.8, 1.3), baseOrientation, "Sandbag" .. index .. "C", SANDBAG, Enum.Material.Fabric, true)

	for _, side in ipairs({ -1, 1 }) do
		local sideLx = ux * (radius - 1.1) + tx * side * 3.1
		local sideLz = uz * (radius - 1.1) + tz * side * 3.1
		local orientation = baseOrientation + side * math.rad(28)
		partOnGround(parent, center, siteYaw, sideLx, sideLz, Vector3.new(4.4, 1.75, 1.25), orientation, "Sandbag" .. index .. (side < 0 and "L" or "R"), SANDBAG, Enum.Material.Fabric, true)
	end
end

local function addSingleSandbag(parent: Instance, center: Vector3, siteYaw: number, angle: number, radius: number, name: string)
	local lx = math.cos(angle) * radius
	local lz = math.sin(angle) * radius
	local orientation = tangentYaw(center, siteYaw, lx, lz)
	partOnGround(parent, center, siteYaw, lx, lz, Vector3.new(5.5, 1.8, 1.35), orientation, name, SANDBAG, Enum.Material.Fabric, true)
end

-- Interaction terminal pair: the named pedestal carries the interaction contract; the thin neon
-- screen is decorative and nonblocking. lift lets a terminal stand on a prepared dais/pad.
local function addTerminal(parent: Instance, center: Vector3, siteYaw: number, lx: number, lz: number, facingYaw: number, terminalName: string, interact: string, prompt: string, lift: number?): Part
	local wx, wz = localXZ(center, siteYaw, lx, lz)
	local gy = ground(wx, wz)
	local baseLift = lift or 0
	local orientation = siteYaw + facingYaw
	local height = 2.8
	local terminalY = gy + height * 0.5 - EMBED + baseLift
	local terminal = partAtWorld(parent, wx, terminalY, wz, Vector3.new(2.45, height, 1.45), orientation, terminalName, METAL_DARK, Enum.Material.Metal, true)
	terminal:SetAttribute("GFInteract", interact)
	terminal:SetAttribute("InteractPrompt", prompt)

	local fx, fz = rotateXZ(0, 0.82, orientation)
	partAtWorld(parent, wx + fx, gy + 1.82 + baseLift, wz + fz, Vector3.new(1.85, 1.08, 0.16), orientation, terminalName .. "Screen", CYAN, Enum.Material.Neon, false)
	return terminal
end

local function crateStack(parent: Instance, center: Vector3, siteYaw: number, lx: number, lz: number, levels: number, size: Vector3, crateYaw: number, name: string)
	local wx, wz = localXZ(center, siteYaw, lx, lz)
	local gy = ground(wx, wz)
	for level = 0, levels - 1 do
		local y = gy + size.Y * 0.5 - EMBED + level * (size.Y - 0.12)
		local color = CRATE_DARK
		if level % 2 == 0 then
			color = CRATE
		end
		partAtWorld(parent, wx, y, wz, size, siteYaw + crateYaw, name .. tostring(level + 1), color, Enum.Material.WoodPlanks, true)
	end
end

local function newSiteModel(siteType: string, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "MissionSite_" .. siteType
	model:SetAttribute("GFMissionSite", true)
	model:SetAttribute("SiteType", siteType)
	model:SetAttribute("SitePosition", position)
	return model
end

local function finishSite(model: Model, parent: Instance, primaryPart: BasePart?): Model
	local partCount = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			partCount += 1
		end
	end
	model:SetAttribute("SitePartCount", partCount)
	model.PrimaryPart = primaryPart
	model.Parent = parent
	return model
end

local function addWatchtower(parent: Instance, center: Vector3, siteYaw: number, angle: number, radius: number, index: number)
	local lx = math.cos(angle) * radius
	local lz = math.sin(angle) * radius
	local wx, wz = localXZ(center, siteYaw, lx, lz)
	local gy = ground(wx, wz)
	partAtWorld(parent, wx, gy + 0.53, wz, Vector3.new(7, 1.9, 7), siteYaw, "WatchtowerBase" .. index, CONCRETE, Enum.Material.Concrete, true)
	partAtWorld(parent, wx, gy + 7.3, wz, Vector3.new(3.8, 12, 3.8), siteYaw, "WatchtowerShaft" .. index, METAL_DARK, Enum.Material.Metal, true)
	partAtWorld(parent, wx, gy + 9.7, wz, Vector3.new(8.2, 0.8, 8.2), siteYaw, "WatchtowerDeck" .. index, METAL, Enum.Material.DiamondPlate, true)
	partAtWorld(parent, wx, gy + 13.1, wz, Vector3.new(8.8, 0.7, 8.8), siteYaw, "WatchtowerRoof" .. index, METAL_DARK, Enum.Material.Metal, true)
	partAtWorld(parent, wx, gy + 13.95, wz, Vector3.new(1.1, 1.0, 1.1), siteYaw, "WatchtowerLamp" .. index, AMBER, Enum.Material.Neon, false)
end

local function buildStronghold(position: Vector3, siteYaw: number, parent: Instance): Model
	local model = newSiteModel("stronghold", position)
	model:SetAttribute("FootprintRadius", 85)

	-- Perimeter ring at r=66; the three gates echo command_stronghold's south/diagonal approach
	-- sockets. Ring segments are individually terrain-settled, so the wall steps with slopes.
	local entrances: { Entrance } = {
		{ angle = math.rad(90), width = 14 },
		{ angle = math.rad(225), width = 11 },
		{ angle = math.rad(315), width = 11 },
	}
	local wallRadius = 66
	addWallRing(model, position, siteYaw, wallRadius, 5.4, 2.2, 48, entrances, "WallSegment")

	-- Gate posts form explicit clear widths: inner faces are exactly entrance.width studs apart,
	-- comfortably above the 8-stud player/enemy minimum even though the omitted ring arc is wider.
	for gateIndex, entrance in ipairs(entrances) do
		local ux = math.cos(entrance.angle)
		local uz = math.sin(entrance.angle)
		local tx = -uz
		local tz = ux
		local rtx, rtz = rotateXZ(tx, tz, siteYaw)
		local orientation = yawForXDirection(rtx, rtz)
		for _, side in ipairs({ -1, 1 }) do
			local tangentOffset = side * (entrance.width * 0.5 + 1.1)
			local lx = ux * wallRadius + tx * tangentOffset
			local lz = uz * wallRadius + tz * tangentOffset
			partOnGround(model, position, siteYaw, lx, lz, Vector3.new(2.2, 6.2, 2.2), orientation, "GatePost" .. gateIndex .. (side < 0 and "L" or "R"), METAL_DARK, Enum.Material.Metal, true)
		end
	end

	-- Seven outward-facing defensive nests inside the wall, kept clear of the three approach lanes.
	for index, angle in ipairs({ math.rad(35), math.rad(65), math.rad(125), math.rad(165), math.rad(200), math.rad(260), math.rad(340) }) do
		addSandbagNest(model, position, siteYaw, angle, 50, index)
	end

	-- Four perimeter watchtowers, rotated off the gate centre-lines so they flank rather than plug approaches.
	for index, angle in ipairs({ math.rad(0), math.rad(135), math.rad(180), math.rad(270) }) do
		addWatchtower(model, position, siteYaw, angle, 74, index)
	end

	-- Tiered central keep. The keep is offset toward the rear, leaving a readable capture court
	-- on the south/entrance side while retaining a central fortress silhouette.
	local keepLx = 0
	local keepLz = -9
	local keepX, keepZ = localXZ(position, siteYaw, keepLx, keepLz)
	local keepGround = ground(keepX, keepZ)
	partAtLocal(model, position, siteYaw, keepLx, keepLz, keepGround + 3.6, Vector3.new(26, 8, 18), siteYaw, "KeepBase", METAL, Enum.Material.Concrete, true)
	partAtLocal(model, position, siteYaw, keepLx, keepLz, keepGround + 10.4, Vector3.new(18, 6, 13), siteYaw, "KeepMid", ARMOR, Enum.Material.Metal, true)
	partAtLocal(model, position, siteYaw, keepLx, keepLz, keepGround + 15.7, Vector3.new(11, 5, 8), siteYaw, "KeepTop", METAL_DARK, Enum.Material.DiamondPlate, true)

	-- Grounded corner buttresses visually pin the large keep into uneven terrain.
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			partOnGround(model, position, siteYaw, keepLx + sx * 11, keepLz + sz * 7, Vector3.new(3.2, 3.2, 3.2), siteYaw, "KeepButtress", CONCRETE, Enum.Material.Concrete, true)
		end
	end

	-- Battlements and front-door detailing make the tiered blockout readable at battlefield range.
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			partAtLocal(model, position, siteYaw, keepLx + sx * 4.2, keepLz + sz * 2.8, keepGround + 18.9, Vector3.new(2, 1.4, 2), siteYaw, "KeepBattlement", ARMOR, Enum.Material.Metal, true)
		end
	end
	partAtLocal(model, position, siteYaw, 0, 0.28, keepGround + 2.3, Vector3.new(5.2, 4.8, 0.5), siteYaw, "KeepDoor", METAL_DARK, Enum.Material.Metal, false)
	partAtLocal(model, position, siteYaw, 0, 0.58, keepGround + 5.15, Vector3.new(4.8, 0.35, 0.18), siteYaw, "KeepDoorLight", CYAN, Enum.Material.Neon, false)

	-- Communications mast rising from the top tier.
	partAtLocal(model, position, siteYaw, keepLx, keepLz, keepGround + 19.0, Vector3.new(2.2, 1.6, 2.2), siteYaw, "CommMastBase", ARMOR, Enum.Material.Metal, true)
	partAtLocal(model, position, siteYaw, keepLx, keepLz, keepGround + 27.1, Vector3.new(1.0, 15.0, 1.0), siteYaw, "CommMast", METAL_DARK, Enum.Material.Metal, true)
	local mastTip = partAtLocal(model, position, siteYaw, keepLx, keepLz, keepGround + 34.9, Vector3.new(1.8, 1.8, 1.8), siteYaw, "CommMastTip", CYAN, Enum.Material.Neon, false)
	addPointLight(mastTip, CYAN, 28, 1.2)

	-- Capture dais and console in the open court. The console itself is the model PrimaryPart.
	partOnGround(model, position, siteYaw, 0, 8, Vector3.new(7.5, 0.7, 7.5), siteYaw, "CaptureDais", METAL, Enum.Material.DiamondPlate, true, 0.15)
	local console = addTerminal(model, position, siteYaw, 0, 8, 0, "CaptureConsole", "CaptureConsole", "Secure the stronghold", 0.85)

	-- Interior supply clutter, arranged away from firing lanes and the capture console.
	crateStack(model, position, siteYaw, -20, 4, 2, Vector3.new(2.7, 2.2, 2.5), 0.2, "StrongholdCrateA")
	crateStack(model, position, siteYaw, 21, -2, 2, Vector3.new(2.5, 2.0, 2.4), -0.35, "StrongholdCrateB")
	crateStack(model, position, siteYaw, -15, -21, 1, Vector3.new(3.0, 2.3, 2.6), 0.55, "StrongholdCrateC")
	crateStack(model, position, siteYaw, 16, -20, 1, Vector3.new(2.4, 2.0, 2.4), -0.2, "StrongholdCrateD")

	return finishSite(model, parent, console)
end

local function buildShieldGenerator(position: Vector3, siteYaw: number, parent: Instance): Model
	local model = newSiteModel("shield_generator", position)
	model:SetAttribute("FootprintRadius", 30)
	local gy = ground(position.X, position.Z)

	partOnGround(model, position, siteYaw, 0, 0, Vector3.new(12, 0.7, 12), siteYaw, "EmitterPad", METAL, Enum.Material.DiamondPlate, true, 0.15)
	partAtLocal(model, position, siteYaw, 0, 0, gy + 0.83, Vector3.new(8, 2.5, 8), siteYaw, "EmitterBase", METAL, Enum.Material.Concrete, true)
	partAtLocal(model, position, siteYaw, 0, 0, gy + 6.15, Vector3.new(3.8, 8.5, 3.8), siteYaw, "EmitterTower", ARMOR, Enum.Material.Metal, true)

	-- Visible destructible emitter core. Corner rails frame it without hiding the cyan volume.
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			partAtLocal(model, position, siteYaw, sx * 2.1, sz * 2.1, gy + 11.6, Vector3.new(0.55, 6.2, 0.55), siteYaw, "EmitterFrame", METAL_DARK, Enum.Material.Metal, true)
		end
	end
	local core = partAtLocal(model, position, siteYaw, 0, 0, gy + 11.8, Vector3.new(3.4, 3.4, 3.4), siteYaw, "EmitterCore", CYAN, Enum.Material.Neon, true)
	core:SetAttribute("GFStructure", true)
	core:SetAttribute("GFIntegrity", 400)
	core:SetAttribute("GFIntegrityMax", 400)
	addPointLight(core, CYAN, 24, 1.5)
	partAtLocal(model, position, siteYaw, 0, 0, gy + 14.9, Vector3.new(5.2, 0.8, 5.2), siteYaw, "EmitterCrown", METAL_DARK, Enum.Material.Metal, true)

	-- Three radial power conduit runs with junction boxes at their ends.
	for index, angle in ipairs({ math.rad(20), math.rad(140), math.rad(260) }) do
		local ux = math.cos(angle)
		local uz = math.sin(angle)
		local rx, rz = rotateXZ(ux, uz, siteYaw)
		local conduitYaw = yawForZDirection(rx, rz)
		partOnGround(model, position, siteYaw, ux * 7.2, uz * 7.2, Vector3.new(1.1, 0.55, 8.0), conduitYaw, "PowerConduit" .. index, METAL_DARK, Enum.Material.Metal, true, 0.25)
		partOnGround(model, position, siteYaw, ux * 12.5, uz * 12.5, Vector3.new(2.0, 1.6, 2.0), siteYaw, "ConduitJunction" .. index, ARMOR, Enum.Material.Metal, true)
	end

	-- Light defense: three sandbags plus four low perimeter barriers.
	for index, angle in ipairs({ math.rad(55), math.rad(175), math.rad(295) }) do
		addSingleSandbag(model, position, siteYaw, angle, 15, "ShieldSandbag" .. index)
	end
	for index, angle in ipairs({ math.rad(0), math.rad(90), math.rad(180), math.rad(270) }) do
		local lx = math.cos(angle) * 18
		local lz = math.sin(angle) * 18
		partOnGround(model, position, siteYaw, lx, lz, Vector3.new(5.0, 1.5, 1.1), tangentYaw(position, siteYaw, lx, lz), "ShieldBarrier" .. index, ARMOR, Enum.Material.Concrete, true)
	end
	crateStack(model, position, siteYaw, -8, 7, 2, Vector3.new(2.2, 1.8, 2.1), 0.3, "MaintenanceCrate")

	return finishSite(model, parent, core)
end

local function buildCommsRelay(position: Vector3, siteYaw: number, parent: Instance): Model
	local model = newSiteModel("comms_relay", position)
	model:SetAttribute("FootprintRadius", 35)
	local gy = ground(position.X, position.Z)

	partOnGround(model, position, siteYaw, 0, 0, Vector3.new(11, 0.7, 11), siteYaw, "RelayPad", METAL, Enum.Material.DiamondPlate, true, 0.15)
	partAtLocal(model, position, siteYaw, 0, 0, gy + 0.78, Vector3.new(6, 2.4, 6), siteYaw, "RelayBase", METAL, Enum.Material.Concrete, true)
	partAtLocal(model, position, siteYaw, 0, 0, gy + 7.3, Vector3.new(2.6, 11, 2.6), siteYaw, "RelayMastLower", ARMOR, Enum.Material.Metal, true)
	partAtLocal(model, position, siteYaw, 0, 0, gy + 15.4, Vector3.new(1.7, 7, 1.7), siteYaw, "RelayMastUpper", METAL_DARK, Enum.Material.Metal, true)
	partAtLocal(model, position, siteYaw, 0, 0, gy + 14.5, Vector3.new(5.0, 0.45, 0.45), siteYaw, "RelayCrossarmA", METAL_DARK, Enum.Material.Metal, true)
	partAtLocal(model, position, siteYaw, 0, 0, gy + 17.2, Vector3.new(4.0, 0.45, 0.45), siteYaw + math.pi * 0.5, "RelayCrossarmB", METAL_DARK, Enum.Material.Metal, true)

	local dish = partAtLocal(model, position, siteYaw, 1.8, -0.4, gy + 16.2, Vector3.new(0.8, 7.0, 7.0), siteYaw + math.pi * 0.5, "RelayDish", ARMOR, Enum.Material.Metal, true)
	dish.Shape = Enum.PartType.Cylinder
	dish.CFrame = dish.CFrame * CFrame.Angles(0, 0, math.rad(14))
	local beacon = partAtLocal(model, position, siteYaw, 0, 0, gy + 19.6, Vector3.new(1.3, 1.3, 1.3), siteYaw, "RelayBeacon", CYAN, Enum.Material.Neon, false)
	addPointLight(beacon, CYAN, 22, 1.0)

	local terminal = addTerminal(model, position, siteYaw, 4, 8, 0, "RelayTerminal", "CommsRelay", "Disable relay", 0)

	-- Low perimeter wall with two wide access omissions; it is a small outpost enclosure, not a fortress.
	addWallRing(model, position, siteYaw, 24, 2.3, 1.4, 16, {
		{ angle = math.rad(90), width = 9 },
		{ angle = math.rad(292.5), width = 8 },
	}, "RelayWall")
	addSandbagNest(model, position, siteYaw, math.rad(75), 17.5, 1)

	crateStack(model, position, siteYaw, -9, 3, 2, Vector3.new(2.4, 2.0, 2.3), 0.2, "RelayCrateA")
	crateStack(model, position, siteYaw, -11, -2, 1, Vector3.new(2.2, 1.9, 2.1), -0.4, "RelayCrateB")
	crateStack(model, position, siteYaw, 8, -7, 2, Vector3.new(2.3, 1.8, 2.2), 0.55, "RelayCrateC")

	return finishSite(model, parent, terminal)
end

local function buildSupplyCache(position: Vector3, siteYaw: number, parent: Instance): Model
	local model = newSiteModel("supply_cache", position)
	model:SetAttribute("FootprintRadius", 20)
	local gy = ground(position.X, position.Z)

	partOnGround(model, position, siteYaw, 0, 0, Vector3.new(12, 0.7, 10), siteYaw, "CachePad", METAL, Enum.Material.DiamondPlate, true, 0.15)

	-- Ten crates in varied low stacks; all are plain rectangular placeholders but arranged as a cache.
	crateStack(model, position, siteYaw, -4.0, -3.0, 2, Vector3.new(3.0, 2.2, 2.6), 0.1, "SupplyCrateA")
	crateStack(model, position, siteYaw, -0.5, -3.5, 1, Vector3.new(2.6, 2.0, 2.4), -0.25, "SupplyCrateB")
	crateStack(model, position, siteYaw, 3.0, -2.0, 2, Vector3.new(2.8, 2.0, 2.5), 0.45, "SupplyCrateC")
	crateStack(model, position, siteYaw, -4.5, 1.0, 1, Vector3.new(2.4, 1.9, 2.2), -0.5, "SupplyCrateD")
	crateStack(model, position, siteYaw, 0.5, 0.5, 3, Vector3.new(2.2, 1.75, 2.1), 0.25, "SupplyCrateE")
	crateStack(model, position, siteYaw, 4.0, 1.5, 1, Vector3.new(2.5, 2.0, 2.3), -0.15, "SupplyCrateF")

	local terminal = addTerminal(model, position, siteYaw, 6.2, 3.2, 0, "SupplyTerminal", "SupplyCache", "Secure supplies", 0)

	-- Minimal defense props: two sandbag lips covering the most natural approaches.
	addSingleSandbag(model, position, siteYaw, math.rad(80), 12, "CacheSandbagA")
	addSingleSandbag(model, position, siteYaw, math.rad(265), 12, "CacheSandbagB")

	-- Lightweight camouflage canopy: four grounded posts and a thin nonblocking fabric roof.
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			partOnGround(model, position, siteYaw, sx * 5, sz * 4, Vector3.new(0.45, 6.5, 0.45), siteYaw, "CanopyPost", METAL_DARK, Enum.Material.Metal, true)
		end
	end
	local canopy = partAtLocal(model, position, siteYaw, 0, 0, gy + 5.9, Vector3.new(12.5, 0.28, 10.5), siteYaw, "CacheCanopy", CAMO, Enum.Material.Fabric, false)
	canopy.Transparency = 0.28
	partAtLocal(model, position, siteYaw, 0, 0, gy + 6.25, Vector3.new(1.1, 0.45, 1.1), siteYaw, "CacheLamp", AMBER, Enum.Material.Neon, false)

	return finishSite(model, parent, terminal)
end

local function buildExtractionPad(position: Vector3, siteYaw: number, parent: Instance): Model
	local model = newSiteModel("extraction_pad", position)
	model:SetAttribute("FootprintRadius", 30)
	local gy = ground(position.X, position.Z)
	local padThickness = 1.1
	local padCenterY = gy + padThickness * 0.5 - EMBED
	local padBottom = padCenterY - padThickness * 0.5
	local padTop = padCenterY + padThickness * 0.5

	-- The pad itself is intentionally flat. Dynamic perimeter supports contact sloping terrain,
	-- preserving a clear aircraft landing surface without mutating voxels.
	local pad = partAtLocal(model, position, siteYaw, 0, 0, padCenterY, Vector3.new(padThickness, 56, 56), siteYaw, "LandingPad", ARMOR, Enum.Material.DiamondPlate, true)
	pad.Shape = Enum.PartType.Cylinder
	pad.CFrame = pad.CFrame * CFrame.Angles(0, 0, math.rad(90))

	for index = 0, 9 do
		local angle = index / 10 * TAU
		local lx = math.cos(angle) * 25.5
		local lz = math.sin(angle) * 25.5
		partAtLocal(model, position, siteYaw, lx, lz, padTop + 0.16, Vector3.new(4.2, 0.28, 0.7), tangentYaw(position, siteYaw, lx, lz), "PadLight" .. index, CYAN, Enum.Material.Neon, false)
	end

	-- Flush amber H marking; it is visual only and leaves the centre physically unobstructed.
	partAtLocal(model, position, siteYaw, -2.0, 0, padTop + 0.07, Vector3.new(0.9, 0.12, 6.0), siteYaw, "PadMarkL", AMBER, Enum.Material.Neon, false)
	partAtLocal(model, position, siteYaw, 2.0, 0, padTop + 0.07, Vector3.new(0.9, 0.12, 6.0), siteYaw, "PadMarkR", AMBER, Enum.Material.Neon, false)
	partAtLocal(model, position, siteYaw, 0, 0, padTop + 0.07, Vector3.new(4.0, 0.12, 0.9), siteYaw, "PadMarkH", AMBER, Enum.Material.Neon, false)

	for index = 0, 7 do
		local angle = index / 8 * TAU
		supportUnder(model, position, siteYaw, math.cos(angle) * 22, math.sin(angle) * 22, padBottom + 0.15, 1.5, 1.5, siteYaw, "PadSupport" .. index, METAL_DARK, Enum.Material.Metal)
	end

	return finishSite(model, parent, pad)
end

local function buildArtillery(position: Vector3, siteYaw: number, parent: Instance): Model
	local model = newSiteModel("artillery", position)
	model:SetAttribute("FootprintRadius", 30)
	local gy = ground(position.X, position.Z)

	-- Low berm ring with one rear access opening; low enough not to interfere with the gun silhouette.
	addWallRing(model, position, siteYaw, 22, 2.2, 1.5, 12, {
		{ angle = math.rad(270), width = 10 },
	}, "ArtilleryBerm")

	partOnGround(model, position, siteYaw, 0, 0, Vector3.new(14, 0.8, 14), siteYaw, "GunPitPad", METAL, Enum.Material.DiamondPlate, true, 0.15)
	partAtLocal(model, position, siteYaw, 0, 0, gy + 1.43, Vector3.new(6, 1.8, 6), siteYaw, "GunBase", CONCRETE, Enum.Material.Concrete, true)

	-- The breech itself is the visible destruction target and carries the structure integrity contract.
	local gun = partAtLocal(model, position, siteYaw, 0, 0, gy + 3.7, Vector3.new(4.0, 3.0, 4.0), siteYaw, "ArtilleryGun", ARMOR, Enum.Material.Metal, true)
	gun:SetAttribute("GFStructure", true)
	gun:SetAttribute("GFIntegrity", 500)
	gun:SetAttribute("GFIntegrityMax", 500)

	local barrel = partAtLocal(model, position, siteYaw, 0, 5.8, gy + 4.7, Vector3.new(1.5, 1.5, 11.0), siteYaw, "ArtilleryBarrel", METAL_DARK, Enum.Material.Metal, true)
	barrel.CFrame = barrel.CFrame * CFrame.Angles(math.rad(-8), 0, 0)
	partAtLocal(model, position, siteYaw, 0, 11.2, gy + 5.0, Vector3.new(2.2, 2.0, 1.2), siteYaw, "ArtilleryMuzzle", METAL, Enum.Material.Metal, true)
	for _, side in ipairs({ -1, 1 }) do
		partAtLocal(model, position, siteYaw, side * 1.4, 0.7, gy + 3.1, Vector3.new(0.5, 0.8, 5.0), siteYaw, "RecoilRail" .. (side < 0 and "L" or "R"), METAL_DARK, Enum.Material.Metal, true)
		partAtLocal(model, position, siteYaw, side * 2.55, 2.3, gy + 3.9, Vector3.new(0.7, 2.6, 3.5), siteYaw, "GunShield" .. (side < 0 and "L" or "R"), ARMOR, Enum.Material.Metal, true)
	end

	-- Munitions staged behind the gun, outside the recoil path.
	crateStack(model, position, siteYaw, -7, -5, 2, Vector3.new(2.2, 1.8, 2.0), 0.15, "AmmoCrateA")
	crateStack(model, position, siteYaw, 7, -5, 2, Vector3.new(2.1, 1.8, 2.0), -0.25, "AmmoCrateB")
	crateStack(model, position, siteYaw, 4, -9, 1, Vector3.new(2.5, 2.0, 2.2), 0.5, "AmmoCrateC")

	addSandbagNest(model, position, siteYaw, math.rad(90), 15, 1)
	addSingleSandbag(model, position, siteYaw, math.rad(210), 15, "ArtillerySandbagL")
	addSingleSandbag(model, position, siteYaw, math.rad(330), 15, "ArtillerySandbagR")

	return finishSite(model, parent, gun)
end

local builders: { [string]: (Vector3, number, Instance) -> Model } = {
	stronghold = buildStronghold,
	shield_generator = buildShieldGenerator,
	comms_relay = buildCommsRelay,
	supply_cache = buildSupplyCache,
	extraction_pad = buildExtractionPad,
	artillery = buildArtillery,
}

function MissionSites.build(siteType: string, position: Vector3, opts: any?): Model
	local builder = builders[siteType]
	if not builder then
		error("MissionSites: unknown site type " .. tostring(siteType), 2)
	end

	local parent: Instance = Workspace
	local siteYaw = 0
	if opts ~= nil and type(opts) == "table" then
		local requestedParent = opts.parent
		if typeof(requestedParent) == "Instance" then
			parent = requestedParent
		end
		local requestedYaw = opts.yaw
		if type(requestedYaw) == "number" then
			siteYaw = requestedYaw
		end
	end

	-- Used only if neither real terrain nor any workspace ground is hit (for example in an empty
	-- harness); normal battlefield construction always raycasts actual terrain first.
	fallbackGroundY = position.Y
	return builder(position, siteYaw, parent)
end

function MissionSites.destroy(site: Instance?)
	if site then
		site:Destroy()
	end
end

return MissionSites
