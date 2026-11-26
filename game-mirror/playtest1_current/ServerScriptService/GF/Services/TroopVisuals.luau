--!strict
-- TroopVisuals v3: archetype armor-package system for Ascendancy infantry.
--
-- Architecture — LANE-SAFE: EnemyService spawns the naked articulated rig (AscendancyTrooper
-- asset) and never knows about armor. This module observes spawns and welds archetype-specific
-- armor packages onto rig limbs server-side, once per spawn — pieces replicate with the model
-- and articulate with animation because they weld to animated limbs.
--
-- All armor is refined primitives (wedges for bevels, layered plates, recessed joints):
-- generated-mesh content provably does not replicate to clients, so primitives are the
-- production visual path. Piece design follows the faction direction: obsidian alloy,
-- violet-gray metal, selective ivory plating, restrained bronze, recessed violet optics.
--
-- Hitbox doctrine unchanged: semantic parts stay invisible-but-queryable; armor is CanQuery false.

local Workspace = game:GetService("Workspace")

local TroopVisuals = {}

local OBSIDIAN = Color3.fromRGB(36, 33, 42)
local OBSIDIAN2 = Color3.fromRGB(24, 22, 30) -- spectre deep-matte
local VIOLETGRAY = Color3.fromRGB(81, 70, 94)
local IVORY = Color3.fromRGB(214, 203, 180)
local BRONZE = Color3.fromRGB(110, 88, 62)
local ENERGY = Color3.fromRGB(169, 99, 233)

-- piece spec: shape Box/Wedge/Cylinder/Ball, size, limb attachment, offset in limb frame,
-- rotation (degrees XYZ), color, material, optional neon
export type Piece = {
	shape: string?,
	size: Vector3,
	limb: string,
	offset: Vector3?,
	rot: Vector3?,
	color: Color3?,
	mat: Enum.Material?,
}

local function P(shape, sx, sy, sz, limb, ox, oy, oz, color, rx, ry, rz, mat): Piece
	return {
		shape = shape,
		size = Vector3.new(sx, sy, sz),
		limb = limb,
		offset = Vector3.new(ox or 0, oy or 0, oz or 0),
		rot = Vector3.new(rx or 0, ry or 0, rz or 0),
		color = color,
		mat = mat,
	}
end

-- ============ SHARED BASE PACKAGE — every soldier wears this ============
-- offsets are in LIMB-local frames; -Z is the character's front.
local function basePackage(): { Piece }
	return {
		-- === HELMET v2 — enclosed angular shell, elongated alien rear profile ===
		-- wedge slope runs along the part X axis: rotY 90 makes it descend forward (-Z)
		P("Wedge", 1.05, 0.45, 0.95, "Head", 0, 0.28, -0.12, OBSIDIAN, 0, -90, 0),
		P("Box", 0.95, 0.4, 1.0, "Head", 0, 0.42, 0.05, OBSIDIAN),
		-- elongated rear taper — the alien silhouette signature
		P("Wedge", 0.85, 0.5, 0.55, "Head", 0, 0.15, 0.45, OBSIDIAN, 0, 90, 0),
		-- cheek guards — small angled side plates
		P("Wedge", 0.2, 0.4, 0.5, "Head", -0.45, -0.1, -0.1, VIOLETGRAY, 0, 0, 0),
		P("Wedge", 0.2, 0.4, 0.5, "Head", 0.45, -0.1, -0.1, VIOLETGRAY, 0, 180, 0),
		-- recessed visor housing — dark slot the glow sits inside
		P("Box", 0.7, 0.2, 0.15, "Head", 0, 0.05, -0.42, OBSIDIAN2),

		-- === TORSO — tapered shell with angular pectoral wedges ===
		P("Box", 1.9, 0.7, 0.35, "UpperTorso", 0, 0.25, -0.55, OBSIDIAN),
		P("Wedge", 0.8, 0.55, 0.3, "UpperTorso", -0.48, -0.18, -0.55, OBSIDIAN, 0, 180, 0),
		P("Wedge", 0.8, 0.55, 0.3, "UpperTorso", 0.48, -0.18, -0.55, OBSIDIAN, 0, 0, 0),
		-- abdominal segment — narrower, recessed
		P("Box", 1.45, 0.45, 0.3, "UpperTorso", 0, -0.42, -0.5, VIOLETGRAY),
		-- back plate with spine channel
		P("Box", 1.8, 0.85, 0.28, "UpperTorso", 0, 0.1, 0.55, VIOLETGRAY),
		P("Box", 0.3, 0.7, 0.12, "UpperTorso", 0, 0.15, 0.72, OBSIDIAN),
		-- waist belt — bronze transition band
		P("Box", 1.7, 0.35, 1.1, "LowerTorso", 0, 0.35, 0, BRONZE, 0, 0, 0, Enum.Material.Metal),
		-- hip guards — small side plates at the belt line
		P("Wedge", 0.25, 0.5, 0.7, "LowerTorso", -0.85, 0.15, 0, OBSIDIAN, 0, 0, 0),
		P("Wedge", 0.25, 0.5, 0.7, "LowerTorso", 0.85, 0.15, 0, OBSIDIAN, 0, 180, 0),

		-- === PAULDRONS — sloped caps over shoulders, layered ===
		P("Wedge", 0.8, 0.45, 0.85, "UpperArmL", -0.06, 0.55, 0, OBSIDIAN, 0, 0, 0),
		P("Wedge", 0.8, 0.45, 0.85, "UpperArmR", 0.06, 0.55, 0, OBSIDIAN, 0, 180, 0),
		-- trim line under the shell — violet-gray separation layer
		P("Box", 0.6, 0.12, 0.7, "UpperArmL", -0.02, 0.32, 0, VIOLETGRAY),
		P("Box", 0.6, 0.12, 0.7, "UpperArmR", 0.02, 0.32, 0, VIOLETGRAY),

		-- === ARMS — bracers with elbow articulation gap ===
		P("Box", 0.56, 0.6, 0.56, "LowerArmL", 0, -0.05, 0, OBSIDIAN),
		P("Box", 0.56, 0.6, 0.56, "LowerArmR", 0, -0.05, 0, OBSIDIAN),
		-- elbow caps — mechanical joint detail
		P("Ball", 0.42, 0.42, 0.42, "LowerArmL", 0, 0.45, 0, VIOLETGRAY),
		P("Ball", 0.42, 0.42, 0.42, "LowerArmR", 0, 0.45, 0, VIOLETGRAY),

		-- === LEGS — knee-articulated plating ===
		P("Wedge", 0.8, 0.85, 0.82, "UpperLegL", 0, 0.05, -0.02, OBSIDIAN, 0, 90, 0),
		P("Wedge", 0.8, 0.85, 0.82, "UpperLegR", 0, 0.05, -0.02, OBSIDIAN, 0, 90, 0),
		-- knee caps — mechanical joint read
		P("Ball", 0.5, 0.5, 0.5, "LowerLegL", 0, 0.55, -0.05, OBSIDIAN),
		P("Ball", 0.5, 0.5, 0.5, "LowerLegR", 0, 0.55, -0.05, OBSIDIAN),
		-- shin guards — forward sloped plates
		P("Wedge", 0.62, 0.9, 0.4, "LowerLegL", 0, 0, -0.3, OBSIDIAN, 0, 90, 0),
		P("Wedge", 0.62, 0.9, 0.4, "LowerLegR", 0, 0, -0.3, OBSIDIAN, 0, 90, 0),

		-- === ASCENDANCY ENERGY RIFLE — alien industrial language: tapered angular housing,
		-- shrouded barrel, recessed violet energy channel, swept rear assembly ===
		-- tapered main housing: wedge nose sloping down-forward, layered over the receiver core
		P("Wedge", 0.28, 0.34, 1.1, "HandR", 0, 0.06, -0.85, OBSIDIAN, 0, -90, 0, Enum.Material.Metal),
		P("Box", 0.24, 0.3, 0.7, "HandR", 0, 0.02, -0.35, OBSIDIAN, 0, 0, 0, Enum.Material.Metal),
		-- angular barrel shroud — the barrel is encased, not exposed (alien manufacturing)
		P("Wedge", 0.18, 0.2, 0.85, "HandR", 0, 0.1, -1.55, VIOLETGRAY, 0, -90, 0, Enum.Material.Metal),
		P("Cylinder", 0.09, 0.3, 0.09, "HandR", 0, 0.1, -1.95, OBSIDIAN2, 90, 0, 0, Enum.Material.Metal),
		-- recessed violet energy channel — a slit of light along the flank, not a bolted box
		P("Box", 0.03, 0.06, 0.8, "HandR", -0.13, 0.08, -0.7, ENERGY, 0, 0, 0, Enum.Material.Neon),
		P("Box", 0.03, 0.06, 0.8, "HandR", 0.13, 0.08, -0.7, ENERGY, 0, 0, 0, Enum.Material.Neon),
		-- swept rear assembly — angular, echoing the elongated helmet profile
		P("Wedge", 0.22, 0.28, 0.5, "HandR", 0, 0, 0.18, OBSIDIAN, 0, 90, 0, Enum.Material.Metal),
		P("Box", 0.16, 0.2, 0.3, "HandR", 0, -0.12, 0.05, OBSIDIAN2),
	}
end

-- ============ ARCHETYPE PACKAGES — silhouette-first differentiation ============
-- each entry: add = extra pieces, remove = substrate pieces to skip (by index into base),
-- recolor = optional substrate tint shift, scaleMul per-piece scaling handled at build.
local PACKAGES: { [string]: any } = {
	Rifleman = {}, -- reference: base package as-is

	-- VANGUARD (Scout): lightweight aggressive — strip pauldrons, slim plates, aerodynamic fin
	Scout = {
		removeIndexes = { 16, 17, 18, 19 }, -- pauldron shells + trim
		add = {
			-- swept helmet fin — speed read
			P("Wedge", 0.2, 0.5, 0.9, "Head", 0, 0.55, 0.35, VIOLETGRAY, -25, 180, 0),
			-- compact carbine instead of rifle (shorter barrel added; base rifle pieces recolored light)
		},
		recolor = VIOLETGRAY, -- lighter violet-gray dominance
	},
	Vanguard = {
		removeIndexes = { 16, 17, 18, 19 },
		add = {
			P("Wedge", 0.2, 0.5, 0.9, "Head", 0, 0.55, 0.35, VIOLETGRAY, -25, 180, 0),
		},
		recolor = VIOLETGRAY,
	},

	-- HEAVY: broad reinforced everything — massive pauldrons, thick chest, support weapon
	Heavy = {
		add = {
			-- second-layer pauldrons, notably wider
			P("Wedge", 1.0, 0.6, 1.0, "UpperArmL", -0.12, 0.62, 0, OBSIDIAN, 0, 90, 0),
			P("Wedge", 1.0, 0.6, 1.0, "UpperArmR", 0.12, 0.62, 0, OBSIDIAN, 0, -90, 0),
			-- reinforced chest slab
			P("Box", 2.2, 0.5, 0.3, "UpperTorso", 0, 0.35, -0.72, OBSIDIAN),
			-- respirator-style faceplate
			P("Box", 0.55, 0.35, 0.25, "Head", 0, -0.25, -0.55, BRONZE, 0, 0, 0, Enum.Material.Metal),
			-- heavy support weapon: big receiver + drum
			P("Box", 0.45, 0.55, 1.9, "HandR", 0, 0.02, -0.95, OBSIDIAN, 0, 0, 0, Enum.Material.Metal),
			P("Cylinder", 0.5, 0.4, 0.5, "HandR", 0, -0.3, -1.1, VIOLETGRAY, 0, 0, 90, Enum.Material.Metal),
		},
		removeIndexes = { 30, 31, 32, 33, 34, 35, 36, 37 }, -- remove base rifle pieces (heavy weapon replaces)
	},

	-- MARKSMAN: compact armor + advanced optics + long precision weapon
	Marksman = {
		add = {
			-- optic sensor block over right eye — the signature
			P("Cylinder", 0.3, 0.35, 0.3, "Head", 0.3, 0.15, -0.5, OBSIDIAN, 90, 0, 0, Enum.Material.Metal),
			P("Cylinder", 0.18, 0.1, 0.18, "Head", 0.3, 0.15, -0.62, ENERGY, 90, 0, 0, Enum.Material.Neon),
			-- long precision barrel extension
			P("Cylinder", 0.1, 1.6, 0.1, "HandR", 0, 0.12, -2.9, OBSIDIAN, 90, 0, 0, Enum.Material.Metal),
			-- stabilized stock
			P("Box", 0.2, 0.35, 0.6, "HandR", 0, -0.05, 0.1, VIOLETGRAY),
		},
		removeIndexes = { 16, 17, 18, 19 }, -- no pauldrons — lean silhouette
	},

	-- OFFICER/COMMANDER: refined armor + comms + rank identification
	Officer = {
		add = {
			-- ivory chest inlay — command plating
			P("Box", 1.2, 0.5, 0.15, "UpperTorso", 0, 0.2, -0.78, IVORY, 0, 0, 0, Enum.Material.Metal),
			-- comms antenna
			P("Cylinder", 0.05, 1.1, 0.05, "Head", -0.45, 0.65, 0.2, BRONZE, 0, 0, 12, Enum.Material.Metal),
			-- bronze rank vane on right pauldron
			P("Box", 0.12, 0.5, 0.4, "UpperArmR", 0.3, 0.6, 0, BRONZE, 0, 0, 0, Enum.Material.Metal),
		},
	},
	Commander = {
		add = {
			P("Box", 1.2, 0.5, 0.15, "UpperTorso", 0, 0.2, -0.78, IVORY, 0, 0, 0, Enum.Material.Metal),
			P("Cylinder", 0.05, 1.1, 0.05, "Head", -0.45, 0.65, 0.2, BRONZE, 0, 0, 12, Enum.Material.Metal),
			P("Box", 0.12, 0.5, 0.4, "UpperArmR", 0.3, 0.6, 0, BRONZE, 0, 0, 0, Enum.Material.Metal),
		},
	},
}

-- ============ ELITE DIVISION PACKAGES ============
-- applied as OVERRIDES on top of role archetypes when Tier == Elite.
local function spectreTreatment()
	-- deep matte obsidian, compact sensor package, bronze identification notch
	return {
		bodyTint = OBSIDIAN2,
		add = {
			-- wide sensor visor band — special-operations read
			P("Box", 0.85, 0.18, 0.12, "Head", 0, 0.12, -0.52, ENERGY, 0, 0, 0, Enum.Material.Neon),
			-- compact backpack sensor
			P("Box", 0.6, 0.7, 0.3, "UpperTorso", 0.3, 0.25, 0.72, OBSIDIAN2),
			P("Cylinder", 0.04, 0.7, 0.04, "UpperTorso", 0.45, 0.9, 0.72, BRONZE, 0, 0, 0, Enum.Material.Metal),
		},
	}
end

local REVENANT_ROLE_PIECES: { [string]: { Piece } } = {
	-- Leader: command vane + ivory inlay + antenna array
	Leader = {
		P("Box", 1.3, 0.55, 0.15, "UpperTorso", 0, 0.2, -0.78, IVORY, 0, 0, 0, Enum.Material.Metal),
		P("Cylinder", 0.05, 1.3, 0.05, "Head", -0.45, 0.7, 0.2, BRONZE, 0, 0, 12, Enum.Material.Metal),
		P("Wedge", 0.15, 0.7, 0.5, "Head", 0, 0.75, 0.3, BRONZE, -20, 180, 0, Enum.Material.Metal),
	},
	-- Assault: reinforced chest + mobility pack nozzles
	Assault = {
		P("Box", 2.15, 0.5, 0.3, "UpperTorso", 0, 0.35, -0.72, IVORY, 0, 0, 0, Enum.Material.Metal),
		P("Cylinder", 0.22, 0.5, 0.22, "UpperTorso", -0.4, 0.3, 0.75, OBSIDIAN, 0, 0, 0, Enum.Material.Metal),
		P("Cylinder", 0.22, 0.5, 0.22, "UpperTorso", 0.4, 0.3, 0.75, OBSIDIAN, 0, 0, 0, Enum.Material.Metal),
		P("Cylinder", 0.12, 0.2, 0.12, "UpperTorso", -0.4, 0.05, 0.78, ENERGY, 0, 0, 0, Enum.Material.Neon),
		P("Cylinder", 0.12, 0.2, 0.12, "UpperTorso", 0.4, 0.05, 0.78, ENERGY, 0, 0, 0, Enum.Material.Neon),
	},
	-- Weapons specialist: heavy gun + ammo pack
	Weapons = {
		P("Box", 0.45, 0.55, 2.0, "HandR", 0, 0.02, -1.0, OBSIDIAN, 0, 0, 0, Enum.Material.Metal),
		P("Box", 0.7, 0.8, 0.35, "UpperTorso", -0.35, 0.15, 0.72, VIOLETGRAY),
		P("Box", 0.15, 0.5, 0.15, "UpperTorso", -0.35, 0.15, 0.55, BRONZE, 0, 0, 0, Enum.Material.Metal),
	},
	-- Precision specialist: long rifle + advanced optic crown
	Precision = {
		P("Cylinder", 0.09, 1.8, 0.09, "HandR", 0, 0.12, -3.0, OBSIDIAN, 90, 0, 0, Enum.Material.Metal),
		P("Cylinder", 0.32, 0.4, 0.32, "Head", 0.28, 0.2, -0.5, OBSIDIAN, 90, 0, 0, Enum.Material.Metal),
		P("Cylinder", 0.2, 0.1, 0.2, "Head", 0.28, 0.2, -0.66, ENERGY, 90, 0, 0, Enum.Material.Neon),
	},
	-- Defense specialist: barrier projector backpack + shoulder shield plates
	Defense = {
		P("Box", 0.9, 1.0, 0.4, "UpperTorso", 0, 0.3, 0.75, VIOLETGRAY),
		P("Cylinder", 0.15, 0.3, 0.15, "UpperTorso", 0, 0.9, 0.75, ENERGY, 0, 0, 0, Enum.Material.Neon),
		P("Wedge", 0.9, 0.55, 0.25, "UpperArmL", -0.2, 0.5, -0.15, IVORY, 15, 90, 0, Enum.Material.Metal),
		P("Wedge", 0.9, 0.55, 0.25, "UpperArmR", 0.2, 0.5, -0.15, IVORY, 15, -90, 0, Enum.Material.Metal),
	},
}

local function revenantTreatment(role: string?)
	-- prestigious obsidian + selective ivory + bronze identification + role equipment
	return {
		bodyTint = OBSIDIAN2,
		add = (function()
			local pieces = {
				-- shared revenant signature: ivory faceplate accent + bronze chest notch
				P("Box", 0.7, 0.3, 0.12, "Head", 0, -0.1, -0.55, IVORY, 0, 0, 0, Enum.Material.Metal),
				P("Box", 0.3, 0.18, 0.1, "UpperTorso", 0, 0.45, -0.75, BRONZE, 0, 0, 0, Enum.Material.Metal),
				-- recessed violet visor band
				P("Box", 0.8, 0.14, 0.1, "Head", 0, 0.12, -0.5, ENERGY, 0, 0, 0, Enum.Material.Neon),
			}
			if role and REVENANT_ROLE_PIECES[role] then
				for _, p in REVENANT_ROLE_PIECES[role] do
					table.insert(pieces, p)
				end
			end
			return pieces
		end)(),
	}
end

-- ============ CONSTRUCTION ============

local function limbOf(rig: Model, name: string): BasePart?
	local p = rig:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

local function buildPiece(piece: Piece, rig: Model, scale: number, tint: Color3?): BasePart?
	local limb = limbOf(rig, piece.limb)
	if not limb then return nil end
	local className = "Part"
	if piece.shape == "Wedge" then
		className = "WedgePart"
	end
	local a = Instance.new(className)
	a.Name = "GFArm_" .. piece.limb
	if piece.shape == "Cylinder" then
		-- cylinder approximation via smooth cylindrical part shape
		a.Shape = Enum.PartType.Cylinder
	end
	if piece.shape == "Ball" then
		a.Shape = Enum.PartType.Ball
	end
	a.Size = piece.size * scale
	local rot = piece.rot or Vector3.new()
	a.CFrame = limb.CFrame
		* CFrame.new(piece.offset * scale)
		* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
	a.Color = tint and piece.color == OBSIDIAN and tint or (piece.color or OBSIDIAN)
	a.Material = piece.mat or Enum.Material.SmoothPlastic
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Anchored = false
	a.Massless = true
	a.CastShadow = true
	a.Parent = rig
	local w = Instance.new("WeldConstraint")
	w.Part0 = limb
	w.Part1 = a
	w.Parent = a
	return a
end

-- apply the archetype visual package to a spawned enemy. Idempotent.
function TroopVisuals.restyle(model: Model)
	if model:GetAttribute("GFVisualStyled") == true then return end
	if model:GetAttribute("GFEnemy") ~= true then return end
	if model:GetAttribute("HasRig") ~= true then return end -- naked-rig path only
	local tier = model:GetAttribute("Tier")
	if tier == "Vehicle" or tier == "Boss" then return end

	local rig = nil
	for _, c in model:GetChildren() do
		if c:IsA("Model") and c:GetAttribute("GFEnemyRig") then
			rig = c
			break
		end
	end
	if not rig then return end
	model:SetAttribute("GFVisualStyled", true)

	local scale = (tier == "Elite") and 1.25 or 1
	local enemyId = model:GetAttribute("EnemyId") or "Rifleman"
	local division = model:GetAttribute("EliteDivision")
	-- revenant roles encode in the EnemyId itself (RevenantLeader etc.), not an attribute
	local role = model:GetAttribute("RevenantRole")
	if not role and type(enemyId) == "string" and enemyId:sub(1, 8) == "Revenant" then
		role = enemyId:sub(9)
	end

	local pkg = PACKAGES[enemyId] or {}
	local treatment = nil
	if division == "Spectre" then
		treatment = spectreTreatment()
	elseif division == "Revenant" then
		treatment = revenantTreatment(role)
	end

	-- assemble final piece list: base minus removals, plus archetype adds, plus elite treatment
	local removeSet = {}
	for _, idx in (pkg.removeIndexes or {}) do
		removeSet[idx] = true
	end
	local pieces: { Piece } = {}
	for i, piece in basePackage() do
		if not removeSet[i] then
			table.insert(pieces, piece)
		end
	end
	for _, piece in (pkg.add or {}) do
		table.insert(pieces, piece)
	end
	if treatment then
		for _, piece in treatment.add do
			table.insert(pieces, piece)
		end
	end

	local tint = treatment and treatment.bodyTint or pkg.recolor
	local built = 0
	for _, piece in pieces do
		if buildPiece(piece, rig, scale, tint) then
			built += 1
		end
	end

	-- elite body tinting: shift the naked rig limbs toward division tones
	if treatment and treatment.bodyTint then
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") and d.Color == OBSIDIAN then
				d.Color = treatment.bodyTint
			end
		end
	end
end

-- spawn observation — lane-safe, no EnemyService edits
local function watchModel(model: Instance)
	if not model:IsA("Model") then return end
	task.defer(function()
		task.wait(0.15) -- spawn construction + rig clone settle
		if model.Parent then
			TroopVisuals.restyle(model)
		end
	end)
end

local folder = Workspace:FindFirstChild("ActiveActors")
if folder then
	for _, m in folder:GetChildren() do
		watchModel(m)
	end
end
Workspace.ChildAdded:Connect(function(c)
	if c.Name == "ActiveActors" then
		folder = c
	end
	watchModel(c)
end)
if folder then
	folder.ChildAdded:Connect(watchModel)
end
-- the folder is created lazily — watch workspace for its appearance
Workspace.ChildAdded:Connect(function(c)
	if c.Name == "ActiveActors" then
		folder = c
		c.ChildAdded:Connect(watchModel)
		for _, m in c:GetChildren() do
			watchModel(m)
		end
	end
end)

function TroopVisuals.init()
	print("[TroopVisuals] archetype armor-package system active")
end

-- boot entrypoint called by Main — watchers connect at module scope on first require,
-- so start is the lifecycle confirmation plus a rescan for anything already present.
function TroopVisuals.start()
	TroopVisuals.init()
	local folder = Workspace:FindFirstChild("ActiveActors")
	if folder then
		for _, m in folder:GetChildren() do
			watchModel(m)
		end
	end
end

return TroopVisuals
