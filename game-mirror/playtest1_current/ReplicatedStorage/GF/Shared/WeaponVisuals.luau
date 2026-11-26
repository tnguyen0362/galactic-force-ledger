--!strict
-- WeaponVisuals — premium primitive weapon model library for Galactic Force.
-- Coordinate convention: -Z forward (barrel), +Z rearward (stock), -Y down (magazine).
-- Grip root is PrimaryPart; Weapon.luau positions it exactly like the placeholder root,
-- so hip/ADS posing and combat behavior are untouched. All parts cosmetic-only.

local WeaponVisuals = {}

local GRAPHITE = Color3.fromRGB(37, 45, 53)
local NAVY = Color3.fromRGB(59, 77, 96)
local STEEL = Color3.fromRGB(131, 144, 155)
local CERAMIC = Color3.fromRGB(216, 220, 217)
local CYAN = Color3.fromRGB(88, 200, 240)
local POLYMER = Color3.fromRGB(23, 27, 32)

local METAL = Enum.Material.Metal
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon

local function P(shape, sx, sy, sz, x, y, z, color, rx, ry, rz, material, name)
	return {
		shape = shape, sx = sx, sy = sy, sz = sz,
		x = x, y = y, z = z, color = color,
		rx = rx or 0, ry = ry or 0, rz = rz or 0,
		material = material, name = name,
	}
end

-- SERVICE RIFLE (AR01) — the reference weapon
local function buildAR01()
	return {
		P("Box", 0.14, 0.2, 0.9, 0, 0, -0.25, GRAPHITE, 0, 0, 0, METAL, "Receiver"),
		P("Wedge", 0.13, 0.09, 0.7, 0, 0.14, -0.28, GRAPHITE, 0, 90, 0, METAL),
		P("Box", 0.02, 0.13, 0.5, -0.08, 0.01, -0.3, CERAMIC, 0, 0, 0, SMOOTH),
		P("Box", 0.02, 0.13, 0.5, 0.08, 0.01, -0.3, CERAMIC, 0, 0, 0, SMOOTH),
		P("Box", 0.11, 0.14, 0.6, 0, 0, -0.92, NAVY, 0, 0, 0, METAL, "Handguard"),
		P("Box", 0.12, 0.03, 0.4, 0, 0.08, -0.92, GRAPHITE),
		P("Cylinder", 0.05, 0.5, 0.05, 0, 0.01, -1.42, STEEL, 90, 0, 0, METAL),
		P("Cylinder", 0.07, 0.14, 0.07, 0, 0.01, -1.66, GRAPHITE, 90, 0, 0, METAL, "Muzzle"),
		P("Box", 0.06, 0.09, 0.22, 0, 0.22, -0.3, NAVY, 0, 0, 0, METAL),
		P("Box", 0.045, 0.05, 0.02, 0, 0.22, -0.4, CYAN, 0, 0, 0, NEON),
		P("Box", 0.09, 0.26, 0.11, 0, -0.2, 0.08, POLYMER, 18, 0, 0, SMOOTH),
		P("Box", 0.09, 0.2, 0.13, 0, -0.21, -0.32, GRAPHITE, 8, 0, 0, METAL, "CosmeticMagazine"),
		P("Box", 0.08, 0.14, 0.12, 0, -0.38, -0.3, GRAPHITE, 20, 0, 0, METAL),
		P("Box", 0.1, 0.15, 0.45, 0, -0.02, 0.42, NAVY, 0, 0, 0, METAL),
		P("Box", 0.09, 0.18, 0.06, 0, -0.03, 0.66, CERAMIC, 0, 0, 0, SMOOTH),
		P("Box", 0.02, 0.02, 0.2, -0.075, 0.08, -0.15, CYAN, 0, 0, 0, NEON),
	}
end

-- JACKAL SMG (SMG03) — compact, aggressive, own identity
local function buildSMG03()
	return {
		P("Box", 0.12, 0.17, 0.55, 0, 0, -0.15, GRAPHITE, 0, 0, 0, METAL, "Receiver"),
		P("Wedge", 0.1, 0.13, 0.35, 0, -0.01, -0.55, NAVY, 0, 90, 0, METAL, "Handguard"),
		P("Cylinder", 0.045, 0.25, 0.045, 0, 0, -0.82, STEEL, 90, 0, 0, METAL),
		P("Cylinder", 0.06, 0.08, 0.06, 0, 0, -0.94, GRAPHITE, 90, 0, 0, METAL, "Muzzle"),
		P("Box", 0.05, 0.06, 0.12, 0, 0.13, -0.18, GRAPHITE, 0, 0, 0, METAL),
		P("Box", 0.035, 0.035, 0.015, 0, 0.13, -0.235, CYAN, 0, 0, 0, NEON),
		P("Box", 0.08, 0.22, 0.1, 0, -0.18, 0.05, POLYMER, 25, 0, 0, SMOOTH),
		P("Box", 0.07, 0.3, 0.1, 0, -0.24, -0.28, GRAPHITE, -6, 0, 0, METAL, "CosmeticMagazine"),
		P("Box", 0.1, 0.13, 0.14, 0, -0.01, 0.18, NAVY, 0, 0, 0, METAL),
		P("Box", 0.015, 0.015, 0.08, -0.065, 0.05, -0.1, CYAN, 0, 0, 0, NEON),
	}
end

-- SUPPRESSOR LMG (LMG12) — broad, heavy, sustained pressure
local function buildLMG12()
	return {
		P("Box", 0.2, 0.26, 0.95, 0, 0, -0.2, GRAPHITE, 0, 0, 0, METAL, "Receiver"),
		P("Box", 0.18, 0.08, 0.8, 0, 0.16, -0.2, NAVY, 0, 0, 0, METAL),
		P("Box", 0.14, 0.16, 0.7, 0, 0, -0.95, NAVY, 0, 0, 0, METAL, "Handguard"),
		P("Box", 0.15, 0.04, 0.5, 0, 0.09, -0.95, GRAPHITE),
		P("Cylinder", 0.07, 0.5, 0.07, 0, 0, -1.5, STEEL, 90, 0, 0, METAL),
		P("Cylinder", 0.09, 0.16, 0.09, 0, 0, -1.75, GRAPHITE, 90, 0, 0, METAL, "Muzzle"),
		P("Box", 0.24, 0.3, 0.4, 0, -0.28, -0.15, NAVY, 0, 0, 0, METAL, "CosmeticMagazine"),
		P("Box", 0.2, 0.05, 0.35, 0, -0.44, -0.15, GRAPHITE),
		P("Box", 0.13, 0.2, 0.5, 0, -0.04, 0.45, GRAPHITE, 0, 0, 0, METAL),
		P("Box", 0.11, 0.22, 0.07, 0, -0.05, 0.72, POLYMER, 0, 0, 0, SMOOTH),
		P("Box", 0.07, 0.18, 0.09, 0, -0.17, -0.85, POLYMER, 12, 0, 0, SMOOTH),
		P("Box", 0.02, 0.02, 0.15, -0.105, 0.1, -0.1, CYAN, 0, 0, 0, NEON),
	}
end

-- BREACHER SHOTGUN (SG04) — broad front profile, powerful
local function buildSG04()
	return {
		P("Box", 0.16, 0.2, 0.7, 0, 0, -0.1, GRAPHITE, 0, 0, 0, METAL, "Receiver"),
		P("Cylinder", 0.09, 0.7, 0.09, 0, 0.02, -0.85, STEEL, 90, 0, 0, METAL),
		P("Cylinder", 0.11, 0.12, 0.11, 0, 0.02, -1.2, GRAPHITE, 90, 0, 0, METAL, "Muzzle"),
		P("Cylinder", 0.06, 0.6, 0.06, 0, -0.09, -0.8, NAVY, 90, 0, 0, METAL),
		P("Box", 0.1, 0.1, 0.24, 0, -0.09, -0.6, POLYMER, 0, 0, 0, SMOOTH),
		P("Box", 0.02, 0.14, 0.4, -0.09, 0, -0.15, CERAMIC, 0, 0, 0, SMOOTH),
		P("Box", 0.02, 0.14, 0.4, 0.09, 0, -0.15, CERAMIC, 0, 0, 0, SMOOTH),
		P("Box", 0.09, 0.22, 0.1, 0, -0.19, 0.12, POLYMER, 20, 0, 0, SMOOTH),
		P("Box", 0.11, 0.16, 0.4, 0, -0.03, 0.42, GRAPHITE, 0, 0, 0, METAL),
		P("Box", 0.1, 0.18, 0.06, 0, -0.04, 0.63, POLYMER, 0, 0, 0, SMOOTH),
		P("Box", 0.03, 0.05, 0.05, 0, 0.13, -0.5, STEEL, 0, 0, 0, METAL),
	}
end

-- RANGER MARKSMAN RIFLE (MR07) — long, refined, precision
local function buildMR07()
	return {
		P("Box", 0.11, 0.16, 0.85, 0, 0, -0.2, GRAPHITE, 0, 0, 0, METAL, "Receiver"),
		P("Box", 0.08, 0.1, 0.8, 0, 0, -0.95, NAVY, 0, 0, 0, METAL, "Handguard"),
		P("Cylinder", 0.04, 0.7, 0.04, 0, 0.01, -1.6, STEEL, 90, 0, 0, METAL),
		P("Cylinder", 0.055, 0.12, 0.055, 0, 0.01, -1.92, GRAPHITE, 90, 0, 0, METAL, "Muzzle"),
		P("Cylinder", 0.07, 0.45, 0.07, 0, 0.2, -0.3, GRAPHITE, 90, 0, 0, METAL),
		P("Cylinder", 0.075, 0.03, 0.075, 0, 0.2, -0.52, CYAN, 90, 0, 0, NEON),
		P("Box", 0.04, 0.08, 0.1, 0, 0.12, -0.3, NAVY, 0, 0, 0, METAL),
		P("Box", 0.08, 0.22, 0.1, 0, -0.18, 0.08, POLYMER, 20, 0, 0, SMOOTH),
		P("Box", 0.07, 0.18, 0.11, 0, -0.2, -0.28, GRAPHITE, 10, 0, 0, METAL, "CosmeticMagazine"),
		P("Box", 0.08, 0.13, 0.45, 0, -0.02, 0.42, NAVY, 0, 0, 0, METAL),
		P("Box", 0.07, 0.06, 0.25, 0, 0.06, 0.42, CERAMIC, 0, 0, 0, SMOOTH),
		P("Box", 0.07, 0.15, 0.05, 0, -0.04, 0.66, POLYMER, 0, 0, 0, SMOOTH),
	}
end

-- ARCUS GRENADE LAUNCHER (GL22) — ordnance drum identity
local function buildGL22()
	return {
		P("Box", 0.15, 0.2, 0.6, 0, 0, 0, GRAPHITE, 0, 0, 0, METAL, "Receiver"),
		P("Cylinder", 0.28, 0.22, 0.28, 0, -0.04, -0.25, NAVY, 0, 0, 90, METAL, "CosmeticMagazine"),
		P("Cylinder", 0.3, 0.06, 0.3, 0, -0.04, -0.25, GRAPHITE, 0, 0, 90, METAL),
		P("Cylinder", 0.13, 0.55, 0.13, 0, 0.04, -0.62, STEEL, 90, 0, 0, METAL),
		P("Cylinder", 0.15, 0.1, 0.15, 0, 0.04, -0.9, GRAPHITE, 90, 0, 0, METAL, "Muzzle"),
		P("Wedge", 0.14, 0.12, 0.4, 0, 0.12, -0.2, GRAPHITE, 0, 90, 0, METAL),
		P("Box", 0.06, 0.08, 0.14, 0, 0.19, -0.45, NAVY, 0, 0, 0, METAL),
		P("Box", 0.04, 0.04, 0.02, 0, 0.19, -0.52, CYAN, 0, 0, 0, NEON),
		P("Box", 0.09, 0.22, 0.11, 0, -0.2, 0.15, POLYMER, 22, 0, 0, SMOOTH),
		P("Box", 0.1, 0.15, 0.35, 0, -0.03, 0.42, GRAPHITE, 0, 0, 0, METAL),
		P("Box", 0.09, 0.17, 0.06, 0, -0.04, 0.61, POLYMER, 0, 0, 0, SMOOTH),
		P("Box", 0.07, 0.16, 0.09, 0, -0.16, -0.55, POLYMER, 15, 0, 0, SMOOTH),
	}
end

-- ATLAS ROCKET LAUNCHER (RL09) — elongated anti-armor tube
local function buildRL09()
	return {
		P("Cylinder", 0.19, 1.9, 0.19, 0, 0.06, -0.5, GRAPHITE, 90, 0, 0, METAL, "Receiver"),
		P("Cylinder", 0.21, 0.1, 0.21, 0, 0.06, -0.9, NAVY, 90, 0, 0, METAL),
		P("Cylinder", 0.21, 0.1, 0.21, 0, 0.06, -0.1, NAVY, 90, 0, 0, METAL),
		P("Cylinder", 0.24, 0.18, 0.24, 0, 0.06, -1.5, GRAPHITE, 90, 0, 0, METAL, "Muzzle"),
		P("Box", 0.1, 0.06, 0.5, 0, 0.19, -0.5, CERAMIC, 0, 0, 0, SMOOTH),
		P("Box", 0.08, 0.12, 0.2, -0.14, 0.12, -0.3, NAVY, 0, 0, 0, METAL),
		P("Box", 0.02, 0.06, 0.06, -0.185, 0.12, -0.35, CYAN, 0, 0, 0, NEON),
		P("Box", 0.09, 0.1, 0.3, 0, -0.1, 0.05, GRAPHITE, 0, 0, 0, METAL),
		P("Box", 0.08, 0.2, 0.1, 0, -0.22, 0.12, POLYMER, 20, 0, 0, SMOOTH),
		P("Box", 0.07, 0.16, 0.09, 0, -0.12, -0.55, POLYMER, 10, 0, 0, SMOOTH),
		P("Cylinder", 0.22, 0.15, 0.22, 0, 0.06, 0.5, STEEL, 90, 0, 0, METAL),
	}
end

-- SERVICE PISTOL (P01) — compact refined sidearm
local function buildP01()
	return {
		P("Box", 0.09, 0.1, 0.5, 0, 0.04, -0.1, GRAPHITE, 0, 0, 0, METAL, "Receiver"),
		P("Cylinder", 0.04, 0.1, 0.04, 0, 0.03, -0.38, STEEL, 90, 0, 0, METAL, "Muzzle"),
		P("Box", 0.08, 0.08, 0.42, 0, -0.04, -0.08, NAVY, 0, 0, 0, METAL),
		P("Box", 0.08, 0.24, 0.11, 0, -0.18, 0.08, POLYMER, 15, 0, 0, SMOOTH, "CosmeticMagazine"),
		P("Box", 0.02, 0.03, 0.02, 0, 0.11, -0.3, STEEL, 0, 0, 0, METAL),
		P("Box", 0.05, 0.03, 0.02, 0, 0.11, 0.12, GRAPHITE, 0, 0, 0, METAL),
		P("Box", 0.015, 0.015, 0.05, -0.045, 0.04, -0.05, CYAN, 0, 0, 0, NEON),
		P("Box", 0.02, 0.06, 0.2, 0.05, 0.04, -0.1, CERAMIC, 0, 0, 0, SMOOTH),
	}
end

local BUILDERS = {
	AR01 = buildAR01,
	SMG03 = buildSMG03,
	LMG12 = buildLMG12,
	SG04 = buildSG04,
	MR07 = buildMR07,
	GL22 = buildGL22,
	RL09 = buildRL09,
	P01 = buildP01,
}

function WeaponVisuals.build(weaponId, weldTo)
	local builder = BUILDERS[weaponId]
	if not builder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "GF_Viewmodel"
	local root = Instance.new("Part")
	root.Name = "Grip"
	root.Size = Vector3.new(0.16, 0.22, 0.5)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.CFrame = weldTo and weldTo.CFrame or CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	for _, piece in builder() do
		local p = Instance.new("Part")
		p.Name = piece.name or ("Wep_" .. piece.shape)
		if piece.shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif piece.shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		end
		p.Size = Vector3.new(piece.sx, piece.sy, piece.sz)
		p.Color = piece.color
		p.Material = piece.material or METAL
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CFrame = root.CFrame
			* CFrame.new(piece.x, piece.y, piece.z)
			* CFrame.Angles(math.rad(piece.rx), math.rad(piece.ry), math.rad(piece.rz))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
	end
	return model
end

function WeaponVisuals.has(weaponId)
	return BUILDERS[weaponId] ~= nil
end

return WeaponVisuals
