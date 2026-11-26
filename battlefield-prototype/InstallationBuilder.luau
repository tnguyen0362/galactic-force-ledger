--!strict
-- InstallationBuilder: turns generated installation plan data (template id, world position,
-- rotation) into physical military structures. Interpretation layer over Templates.luau's
-- design contract — perimeter walls with gaps at entrance sockets, family-scaled core
-- structures, sandbag lines at defensive positions. All parts server-built, anchored,
-- budgeted (~40-90 parts per installation depending on family), grouped per installation
-- for clean teardown on regeneration.
--
-- Art direction follows the existing military palette (dropship grays + cyan accents).
-- Premium environmental art pass is explicitly deferred per owner brief; these structures
-- prioritize tactical readability: entrances visible as gaps, defense positions real cover,
-- cores readable from distance.

local Templates = require(script.Parent.Templates)

local InstallationBuilder = {}

local METAL = Enum.Material.Metal
local PLATE = Enum.Material.DiamondPlate
local CONCRETE = Enum.Material.Concrete

local WALL_C = Color3.fromRGB(70, 76, 84)
local CORE_C = Color3.fromRGB(82, 90, 100)
local DARK_C = Color3.fromRGB(50, 55, 62)
local ACCENT = Color3.fromRGB(120, 210, 255)
local SANDBAG = Color3.fromRGB(96, 92, 78)

local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function rotXZ(lx: number, lz: number, yaw: number): (number, number)
	local c, s = math.cos(yaw), math.sin(yaw)
	return lx * c - lz * s, lx * s + lz * c
end

-- Perimeter wall ring with gaps at entrance sockets. Wall segments of fixed arc width,
-- height 5, thickness 1.6 — tall enough to block fire, low enough to vault/see over from elevation.
local function buildPerimeter(folder: Instance, baseCF: CFrame, def: any, yaw: number, groundY: (number, number) -> number)
	local radius = def.footprintRadius * 0.82
	local segs = math.max(10, math.floor(radius * 0.9))
	local written = 0
	for i = 0, segs - 1 do
		local ang = (i / segs) * math.pi * 2
		-- skip segments inside an entrance arc
		local lx, lz = math.cos(ang) * radius, math.sin(ang) * radius
		local blocked = false
		for _, ent in def.entrances do
			local ex, ez = ent.x, ent.z
			-- entrances are defined in template local space at the perimeter-ish ring; match by proximity
			local exx, ezz = math.clamp(ex, -radius, radius), math.clamp(ez, -radius, radius)
			local mag = math.sqrt(exx * exx + ezz * ezz)
			if mag > 1 then
				exx, ezz = exx / mag * radius, ezz / mag * radius
				local dd = math.sqrt((lx - exx) ^ 2 + (lz - ezz) ^ 2)
				if dd < (ent.width or 6) * 0.5 + 2 then
					blocked = true
					break
				end
			end
		end
		if not blocked then
			local wx, wz = rotXZ(lx, lz, yaw)
			local wxw, wzw = baseCF.X + wx, baseCF.Z + wz
			local gy = groundY(wxw, wzw)
			local segLen = (math.pi * 2 * radius) / segs + 0.4
			local cf = CFrame.new(wxw, gy + 2.2, wzw) * CFrame.Angles(0, -ang - yaw + math.pi / 2, 0)
			mk(folder, "Wall", Vector3.new(segLen, 4.4, 1.6), cf, WALL_C, CONCRETE)
			written += 1
		end
	end
	return written
end

-- Sandbag defensive lines: low cover arcs at template defensive positions.
local function buildDefense(folder: Instance, baseCF: CFrame, def: any, yaw: number, groundY: (number, number) -> number)
	for i, dp in def.defensivePositions do
		local wx, wz = rotXZ(dp.x, dp.z, yaw)
		local wxw, wzw = baseCF.X + wx, baseCF.Z + wz
		local gy = groundY(wxw, wzw)
		-- face outward from center
		local faceYaw = math.atan2(wz, wx)
		local cf = CFrame.new(wxw, gy + 1.0, wzw) * CFrame.Angles(0, -faceYaw, 0)
		mk(folder, "Sandbag" .. i, Vector3.new(5.5, 2.0, 1.4), cf, SANDBAG, Enum.Material.Fabric)
	end
end

-- Family-scaled core structures at the anchor.
local function buildCore(folder: Instance, baseCF: CFrame, def: any, yaw: number, groundY: (number, number) -> number)
	local gy = groundY(baseCF.X, baseCF.Z)
	local center = CFrame.new(baseCF.X, gy, baseCF.Z) * CFrame.Angles(0, -yaw, 0)
	local family = def.family
	if family == "small" then
		-- watch post: legs + platform + roof
		local topY = 6.5
		for sx = -1, 1, 2 do
			for sz = -1, 1, 2 do
				mk(folder, "PostLeg", Vector3.new(0.7, topY, 0.7), center * CFrame.new(sx * 2.4, topY / 2, sz * 2.4), DARK_C, METAL)
			end
		end
		mk(folder, "Platform", Vector3.new(6.4, 0.5, 6.4), center * CFrame.new(0, topY, 0), CORE_C, PLATE)
		mk(folder, "Roof", Vector3.new(7.2, 0.4, 7.2), center * CFrame.new(0, topY + 3.4, 0), DARK_C, METAL)
		mk(folder, "Beacon", Vector3.new(0.6, 1.6, 0.6), center * CFrame.new(0, topY + 4.2, 0), ACCENT, Enum.Material.Neon).CanCollide = false
	elseif family == "outpost" then
		-- depot block + comm mast
		mk(folder, "Depot", Vector3.new(10, 5, 8), center * CFrame.new(-3, 2.5, 0), CORE_C, METAL)
		mk(folder, "DepotRoof", Vector3.new(11, 0.5, 9), center * CFrame.new(-3, 5.2, 0), DARK_C, PLATE)
		mk(folder, "Mast", Vector3.new(0.8, 14, 0.8), center * CFrame.new(5, 7, -2), DARK_C, METAL)
		mk(folder, "MastTip", Vector3.new(1.4, 1.4, 1.4), center * CFrame.new(5, 14.6, -2), ACCENT, Enum.Material.Neon).CanCollide = false
		mk(folder, "Crate1", Vector3.new(2.4, 2.4, 2.4), center * CFrame.new(4, 1.2, 4), SANDBAG, PLATE)
		mk(folder, "Crate2", Vector3.new(2.4, 2.4, 2.4), center * CFrame.new(4, 3.6, 4), SANDBAG, PLATE)
	elseif family == "base" then
		-- compound: HQ block + two annexes + mast
		mk(folder, "HQ", Vector3.new(14, 7, 10), center * CFrame.new(0, 3.5, -4), CORE_C, METAL)
		mk(folder, "HQRoof", Vector3.new(15, 0.5, 11), center * CFrame.new(0, 7.2, -4), DARK_C, PLATE)
		mk(folder, "Annex1", Vector3.new(8, 4.5, 6), center * CFrame.new(-8, 2.25, 6), WALL_C, METAL)
		mk(folder, "Annex2", Vector3.new(8, 4.5, 6), center * CFrame.new(8, 2.25, 6), WALL_C, METAL)
		mk(folder, "Mast", Vector3.new(0.9, 18, 0.9), center * CFrame.new(0, 9, -10), DARK_C, METAL)
		mk(folder, "MastTip", Vector3.new(1.6, 1.6, 1.6), center * CFrame.new(0, 18.8, -10), ACCENT, Enum.Material.Neon).CanCollide = false
	else -- primary
		-- stronghold keep: tiered fortress silhouette
		mk(folder, "KeepBase", Vector3.new(22, 8, 18), center * CFrame.new(0, 4, 0), CORE_C, CONCRETE)
		mk(folder, "KeepMid", Vector3.new(16, 6, 12), center * CFrame.new(0, 11, 0), WALL_C, METAL)
		mk(folder, "KeepTop", Vector3.new(9, 5, 7), center * CFrame.new(0, 16.5, 0), DARK_C, PLATE)
		mk(folder, "Mast", Vector3.new(1, 22, 1), center * CFrame.new(0, 27, 0), DARK_C, METAL)
		mk(folder, "MastTip", Vector3.new(2, 2, 2), center * CFrame.new(0, 38.5, 0), ACCENT, Enum.Material.Neon).CanCollide = false
		for sx = -1, 1, 2 do
			mk(folder, "Turret", Vector3.new(3, 3.5, 3), center * CFrame.new(sx * 10, 9.5, 7), DARK_C, METAL)
		end
	end
end

-- groundY: function(x, z) -> y of terrain surface (TerrainService.groundSurface in practice).
-- Returns the folder holding all built structures for the installation.
function InstallationBuilder.build(inst: any, groundY: (number, number) -> number, parent: Instance): Instance?
	local def = inst.template or (inst.templateId and Templates.get(inst.templateId)) or nil
	if not def then
		warn("InstallationBuilder: unknown template", inst.templateId)
		return nil
	end
	local yaw = inst.yaw or inst.rotation or 0
	local baseCF = CFrame.new(inst.x, 0, inst.z)
	local folder = Instance.new("Folder")
	folder.Name = "BFInst_" .. tostring(def.id) .. "_" .. tostring(inst.role or "x")
	buildPerimeter(folder, baseCF, def, yaw, groundY)
	buildDefense(folder, baseCF, def, yaw, groundY)
	buildCore(folder, baseCF, def, yaw, groundY)
	folder.Parent = parent
	return folder
end

return InstallationBuilder
