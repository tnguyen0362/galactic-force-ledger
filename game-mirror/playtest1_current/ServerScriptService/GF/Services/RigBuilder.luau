--!strict
-- RigBuilder v2: constructs the AscendancyTrooper rig asset in ServerStorage.GF.Art.
-- Run once in Edit mode — the asset persists with the place; enemies pick it up through
-- the existing ArtService.clone path in EnemyService (zero behavior edits).
--
-- v2 refinement (user directive — no chunky boxes, anatomically correct joints):
--   * Motor6D C0/C1 positioned at ANATOMICAL JOINT LOCATIONS so Transform rotations
--     pivot at shoulders/hips/elbows/knees — required for correct procedural animation.
--   * Tapered proportions: waist narrower than chest, limbs slim with layered armor
--     pieces adding the bulk instead of the body blocks themselves.
--   * Layered armor shells: overlapping plates with small gaps read as manufactured
--     armor rather than single rectangular masses.
--   * Armor articulates with limbs (welded), mesh plating from GFTroopKit on top.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RigBuilder = {}

local OBSIDIAN = Color3.fromRGB(36, 33, 42)
local VIOLETGRAY = Color3.fromRGB(81, 70, 94)
local IVORY = Color3.fromRGB(214, 203, 180)
local BRONZE = Color3.fromRGB(150, 120, 84)
local ENERGY = Color3.fromRGB(169, 99, 233)

-- limb definition: size + world CFrame in bind pose + joint positions.
-- all heights: feet at y=0, total height ~5.3 studs before tier scaling.
export type LimbDef = {
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	jointIn: Vector3?, -- world position where this limb's incoming joint pivots
}

local LIMBS: { [string]: LimbDef } = {
	HumanoidRootPart = { size = Vector3.new(1.6, 0.9, 0.9), cframe = CFrame.new(0, 3.05, 0), color = OBSIDIAN },
	-- torso: chest broad, waist tapered — silhouette reads armored, not box
	LowerTorso = { size = Vector3.new(1.55, 1.0, 1.0), cframe = CFrame.new(0, 3.05, 0), color = VIOLETGRAY, jointIn = Vector3.new(0, 3.5, 0) },
	UpperTorso = { size = Vector3.new(1.95, 1.15, 1.1), cframe = CFrame.new(0, 4.05, 0), color = OBSIDIAN, jointIn = Vector3.new(0, 4.62, 0) },
	Head = { size = Vector3.new(0.95, 1.0, 1.0), cframe = CFrame.new(0, 5.35, 0), color = OBSIDIAN },
	-- arms slim at the core — armor pieces add the bulk
	UpperArmL = { size = Vector3.new(0.52, 1.15, 0.52), cframe = CFrame.new(-1.32, 4.02, 0), color = OBSIDIAN, jointIn = Vector3.new(-1.28, 4.5, 0) },
	LowerArmL = { size = Vector3.new(0.46, 1.05, 0.46), cframe = CFrame.new(-1.34, 2.95, -0.08), color = VIOLETGRAY, jointIn = Vector3.new(-1.33, 3.5, 0) },
	HandL = { size = Vector3.new(0.42, 0.5, 0.42), cframe = CFrame.new(-1.34, 2.32, -0.14), color = OBSIDIAN, jointIn = Vector3.new(-1.34, 2.55, -0.1) },
	UpperArmR = { size = Vector3.new(0.52, 1.15, 0.52), cframe = CFrame.new(1.32, 4.02, 0), color = OBSIDIAN, jointIn = Vector3.new(1.28, 4.5, 0) },
	LowerArmR = { size = Vector3.new(0.46, 1.05, 0.46), cframe = CFrame.new(1.1, 3.3, -0.55), color = VIOLETGRAY, jointIn = Vector3.new(1.26, 3.55, -0.15) },
	HandR = { size = Vector3.new(0.42, 0.5, 0.42), cframe = CFrame.new(0.8, 3.55, -0.95), color = OBSIDIAN, jointIn = Vector3.new(0.95, 3.45, -0.75) },
	-- legs: armored segmentation — thigh slimmer, shin with plate bulk
	UpperLegL = { size = Vector3.new(0.68, 1.25, 0.72), cframe = CFrame.new(-0.48, 1.95, 0), color = OBSIDIAN, jointIn = Vector3.new(-0.48, 2.55, 0) },
	LowerLegL = { size = Vector3.new(0.58, 1.2, 0.62), cframe = CFrame.new(-0.48, 0.75, 0.02), color = VIOLETGRAY, jointIn = Vector3.new(-0.48, 1.35, 0) },
	FootL = { size = Vector3.new(0.6, 0.32, 0.95), cframe = CFrame.new(-0.48, 0.16, -0.12), color = OBSIDIAN, jointIn = Vector3.new(-0.48, 0.32, 0) },
	UpperLegR = { size = Vector3.new(0.68, 1.25, 0.72), cframe = CFrame.new(0.48, 1.95, 0), color = OBSIDIAN, jointIn = Vector3.new(0.48, 2.55, 0) },
	LowerLegR = { size = Vector3.new(0.58, 1.2, 0.62), cframe = CFrame.new(0.48, 0.75, 0.02), color = VIOLETGRAY, jointIn = Vector3.new(0.48, 1.35, 0) },
	FootR = { size = Vector3.new(0.6, 0.32, 0.95), cframe = CFrame.new(0.48, 0.16, -0.12), color = OBSIDIAN, jointIn = Vector3.new(0.48, 0.32, 0) },
}

-- joint graph: name = {part0, part1, worldPivot}
local JOINTS = {
	{ "RootJoint", "HumanoidRootPart", "LowerTorso", Vector3.new(0, 3.5, 0) },
	{ "Waist", "LowerTorso", "UpperTorso", Vector3.new(0, 3.55, 0) },
	{ "Neck", "UpperTorso", "Head", Vector3.new(0, 4.85, 0) },
	{ "ShoulderL", "UpperTorso", "UpperArmL", Vector3.new(-1.05, 4.45, 0) },
	{ "ElbowL", "UpperArmL", "LowerArmL", Vector3.new(-1.33, 3.5, 0) },
	{ "WristL", "LowerArmL", "HandL", Vector3.new(-1.34, 2.55, -0.1) },
	{ "ShoulderR", "UpperTorso", "UpperArmR", Vector3.new(1.05, 4.45, 0) },
	{ "ElbowR", "UpperArmR", "LowerArmR", Vector3.new(1.26, 3.55, -0.15) },
	{ "WristR", "LowerArmR", "HandR", Vector3.new(0.95, 3.45, -0.75) },
	{ "HipL", "LowerTorso", "UpperLegL", Vector3.new(-0.48, 2.55, 0) },
	{ "KneeL", "UpperLegL", "LowerLegL", Vector3.new(-0.48, 1.35, 0) },
	{ "AnkleL", "LowerLegL", "FootL", Vector3.new(-0.48, 0.32, 0) },
	{ "HipR", "LowerTorso", "UpperLegR", Vector3.new(0.48, 2.55, 0) },
	{ "KneeR", "UpperLegR", "LowerLegR", Vector3.new(0.48, 1.35, 0) },
	{ "AnkleR", "LowerLegR", "FootR", Vector3.new(0.48, 0.32, 0) },
}

function RigBuilder.build()
	local gf = ServerStorage:FindFirstChild("GF") or Instance.new("Folder")
	gf.Name = "GF"
	gf.Parent = ServerStorage
	local art = gf:FindFirstChild("Art") or Instance.new("Folder")
	art.Name = "Art"
	art.Parent = gf
	local old = art:FindFirstChild("AscendancyTrooper")
	if old then old:Destroy() end

	local rig = Instance.new("Model")
	rig.Name = "AscendancyTrooper"

	local parts: { [string]: BasePart } = {}
	for name, def in LIMBS do
		local p = Instance.new("Part")
		p.Name = name
		p.Size = def.size
		p.CFrame = def.cframe
		p.Color = def.color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Anchored = false
		p.Parent = rig
		parts[name] = p
	end
	parts.HumanoidRootPart.Transparency = 1

	-- joints with pivots at anatomical locations:
	-- C0/C1 express the SAME world pivot point in each part's bind-frame space.
	for _, j in JOINTS do
		local name, p0n, p1n, pivot = j[1], j[2], j[3], j[4]
		local p0, p1 = parts[p0n], parts[p1n]
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = p0.CFrame:Inverse() * CFrame.new(pivot)
		m.C1 = p1.CFrame:Inverse() * CFrame.new(pivot)
		m.Parent = p0
	end

	-- violet visor slit — recessed into the helmet face
	local head = parts.Head
	local visor = Instance.new("Part")
	visor.Name = "VisorSlit"
	visor.Size = Vector3.new(0.66, 0.12, 0.08)
	visor.CFrame = head.CFrame * CFrame.new(0, 0.08, -0.48)
	visor.Color = ENERGY
	visor.Material = Enum.Material.Neon
	visor.CanCollide = false
	visor.CanQuery = false
	visor.CanTouch = false
	visor.Anchored = false
	visor.Parent = rig
	local vj = Instance.new("Motor6D")
	vj.Name = "VisorJoint"
	vj.Part0 = head
	vj.Part1 = visor
	vj.C0 = head.CFrame:Inverse() * CFrame.new((head.CFrame * CFrame.new(0, 0.08, -0.48)).Position)
	vj.C1 = CFrame.new()
	vj.Parent = head

	-- v3: base asset is the NAKED articulated rig — armor shells are per-archetype packages
	-- applied by TroopVisuals post-spawn (lane-safe server-side attachment, replicates once).
	-- mesh plating removed entirely: generated mesh content does not replicate to clients.

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.Parent = rig
	rig.PrimaryPart = parts.HumanoidRootPart

	rig.Parent = art
	return "RIG v3 BUILT naked"
end

return RigBuilder
