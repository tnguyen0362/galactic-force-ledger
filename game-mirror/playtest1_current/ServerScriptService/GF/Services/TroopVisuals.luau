--!strict
-- TroopVisuals: rigged-body visual system for Ascendancy infantry (user directive:
-- real articulated rigs, arms at sides, no static box bodies).
--
-- Architecture — LANE-SAFE, zero EnemyService edits:
--   EnemyService spawns primitive bodies moved rigidly via PivotTo. This layer replaces the
--   primitive VISUALS post-spawn with an articulated humanoid rig: anchored limb parts whose
--   CFrames are procedurally updated each heartbeat relative to the model root pivot.
--   Walk articulation is driven by actual root displacement — AI movement code untouched.
--
-- Hitbox doctrine — CRITICAL: semantic parts (Head/Torso/Root) stay exactly in place with
-- CanQuery TRUE — hitscan, headshot multipliers, weakpoint logic untouched. They are invisible.
-- All rig visual parts are CanQuery FALSE: rays pass through them into the semantic hitboxes.
--
-- Armor articulation: mesh kit pieces attach to RIG LIMB frames — pauldrons swing with arms,
-- greaves articulate with knees, the rifle rides the weapon-hold arm.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TroopVisuals = {}

local OBSIDIAN = Color3.fromRGB(36, 33, 42)
local VIOLETGRAY = Color3.fromRGB(81, 70, 94)
local ENERGY = Color3.fromRGB(169, 99, 233)

type LimbSpec = {
	name: string,
	size: Vector3,
	bind: Vector3,
	parent: string?,
	swing: number?,
	phase: number?,
	axis: string?,
}

local function rigPlan(scale: number): { LimbSpec }
	local s = scale
	return {
		{ name = "UpperTorso", size = Vector3.new(2.0*s, 1.35*s, 1.25*s), bind = Vector3.new(0, 0.55*s, 0) },
		{ name = "LowerTorso", size = Vector3.new(1.85*s, 1.2*s, 1.15*s), bind = Vector3.new(0, -0.75*s, 0), parent = "UpperTorso" },
		{ name = "HeadVis", size = Vector3.new(1.0*s, 1.05*s, 1.05*s), bind = Vector3.new(0, 2.05*s, 0), parent = "UpperTorso" },
		{ name = "UpperArmL", size = Vector3.new(0.68*s, 1.25*s, 0.68*s), bind = Vector3.new(-1.42*s, 0.35*s, 0), parent = "UpperTorso", swing = 14, phase = 180, axis = "arm" },
		{ name = "LowerArmL", size = Vector3.new(0.6*s, 1.15*s, 0.6*s), bind = Vector3.new(-1.45*s, -0.75*s, -0.15*s), parent = "UpperArmL", axis = "forearm" },
		{ name = "UpperArmR", size = Vector3.new(0.68*s, 1.25*s, 0.68*s), bind = Vector3.new(1.42*s, 0.35*s, 0), parent = "UpperTorso", swing = 10, phase = 0, axis = "arm" },
		{ name = "LowerArmR", size = Vector3.new(0.6*s, 1.15*s, 0.6*s), bind = Vector3.new(1.3*s, -0.5*s, -0.6*s), parent = "UpperArmR", axis = "hold" },
		{ name = "UpperLegL", size = Vector3.new(0.85*s, 1.35*s, 0.9*s), bind = Vector3.new(-0.55*s, -2.05*s, 0), swing = 26, phase = 0, axis = "leg" },
		{ name = "LowerLegL", size = Vector3.new(0.78*s, 1.3*s, 0.82*s), bind = Vector3.new(-0.55*s, -3.4*s, 0.02*s), parent = "UpperLegL", axis = "knee", phase = 0 },
		{ name = "UpperLegR", size = Vector3.new(0.85*s, 1.35*s, 0.9*s), bind = Vector3.new(0.55*s, -2.05*s, 0), swing = 26, phase = 180, axis = "leg" },
		{ name = "LowerLegR", size = Vector3.new(0.78*s, 1.3*s, 0.82*s), bind = Vector3.new(0.55*s, -3.4*s, 0.02*s), parent = "UpperLegR", axis = "knee", phase = 180 },
	}
end

local function platingPlan(scale: number): { any }
	local s = scale
	return {
		{ kit = "RifleHelmet", limb = "HeadVis", offset = Vector3.new(0, 0.05*s, 0) },
		{ kit = "ChestArmor", limb = "UpperTorso", offset = Vector3.new(0, 0.05*s, 0) },
		{ kit = "Pauldron", limb = "UpperArmL", offset = Vector3.new(-0.12*s, 0.45*s, 0) },
		{ kit = "Pauldron", limb = "UpperArmR", offset = Vector3.new(0.12*s, 0.45*s, 0), rotY = 180 },
		{ kit = "Greave", limb = "LowerLegL", offset = Vector3.new(0, 0.1*s, 0) },
		{ kit = "Greave", limb = "LowerLegR", offset = Vector3.new(0, 0.1*s, 0), rotY = 180 },
		{ kit = "EnergyRifle", limb = "LowerArmR", offset = Vector3.new(0, -0.35*s, -0.5*s) },
	}
end

local function kitFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("GFTroopKit")
end

type Rig = {
	model: Model,
	root: BasePart,
	torsoCenterOffset: Vector3,
	limbs: { [string]: BasePart },
	specs: { [string]: LimbSpec },
	plating: { any },
	scale: number,
	phase: number,
	lastPos: Vector3?,
	speed: number,
}
local rigs: { [Model]: Rig } = {}

function TroopVisuals.restyle(model: Model)
	if model:GetAttribute("GFVisualStyled") == true then return end
	if model:GetAttribute("GFEnemy") ~= true then return end
	-- art-rigged enemies (AscendancyTrooper asset) carry their own visual body — this layer
	-- only animates their joints (future) rather than building a parallel rig
	if model:GetAttribute("HasRig") == true then return end
	local tier = model:GetAttribute("Tier")
	if tier == "Vehicle" or tier == "Boss" then return end
	if model.Name:match("^Bastion") or model.Name:match("^Leviathan") then return end
	local torso = model:FindFirstChild("Torso")
	local root = model.PrimaryPart
	if not (torso and torso:IsA("BasePart") and root) then return end
	model:SetAttribute("GFVisualStyled", true)

	local scale = (tier == "Elite") and 1.25 or 1
	local s = scale

	-- 1. primitive semantic parts: invisible hitboxes, positions untouched
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "Root" then
			p.Transparency = 1
		end
	end

	local torsoCF = torso.CFrame
	local rootCF = model:GetPivot()
	local torsoOffset = rootCF:Inverse() * torsoCF.Position

	-- 2. articulated rig limbs — anchored, CanQuery false, premium materials
	local limbs: { [string]: BasePart } = {}
	local specs: { [string]: LimbSpec } = {}
	for _, spec in rigPlan(scale) do
		specs[spec.name] = spec
		local part = Instance.new("Part")
		part.Name = "GFRig_" .. spec.name
		part.Size = spec.size
		if spec.name == "LowerTorso" or spec.axis == "knee" or spec.axis == "forearm" or spec.axis == "hold" then
			part.Color = VIOLETGRAY
		else
			part.Color = OBSIDIAN
		end
		part.Material = Enum.Material.SmoothPlastic
		part.CanQuery = false
		part.CanCollide = false
		part.CanTouch = false
		part.Anchored = true
		part.CFrame = torsoCF * CFrame.new(spec.bind)
		part.Parent = model
		limbs[spec.name] = part
	end

	-- violet visor slit — faction identity glow
	local visor = Instance.new("Part")
	visor.Name = "GFRig_VisorSlit"
	visor.Size = Vector3.new(0.72*s, 0.14*s, 0.1*s)
	visor.Color = ENERGY
	visor.Material = Enum.Material.Neon
	visor.CanQuery = false
	visor.CanCollide = false
	visor.CanTouch = false
	visor.Anchored = true
	visor.Parent = model

	-- 3. mesh plating rides limb frames
	local plating: { any } = {}
	local kit = kitFolder()
	if kit then
		for _, spec in platingPlan(scale) do
			local template = kit:FindFirstChild(spec.kit)
			if template and limbs[spec.limb] then
				local piece = template:Clone()
				piece.Name = "GFVis_" .. spec.kit .. "_" .. spec.limb
				for _, d in piece:GetDescendants() do
					if d:IsA("BasePart") then
						d.CanQuery = false
						d.CanCollide = false
						d.CanTouch = false
						d.Anchored = true
						d.Material = Enum.Material.Metal
					end
				end
				piece.Parent = model
				table.insert(plating, { part = piece, limb = spec.limb, offset = spec.offset, rotY = spec.rotY or 0 })
			end
		end
	end

	rigs[model] = {
		model = model,
		root = root,
		torsoCenterOffset = torsoOffset,
		limbs = limbs,
		specs = specs,
		plating = plating,
		scale = scale,
		phase = math.random() * math.pi * 2,
		lastPos = nil,
		speed = 0,
	}
	model.Destroying:Connect(function()
		rigs[model] = nil
	end)
end

-- procedural articulation — poses every rig from actual root displacement.
-- hips swing contralaterally, knees flex on back-swing, arms counter-swing hanging
-- at sides, right forearm holds the weapon across the chest.
local ORDER = { "UpperTorso", "LowerTorso", "HeadVis", "UpperArmL", "LowerArmL", "UpperArmR", "LowerArmR", "UpperLegL", "LowerLegL", "UpperLegR", "LowerLegR" }

local function poseRig(rig: Rig, dt: number)
	local model = rig.model
	if not model.Parent then return end
	local rootCF = model:GetPivot()

	local pos = rootCF.Position
	if rig.lastPos then
		local disp = (pos - rig.lastPos).Magnitude
		rig.speed = rig.speed * 0.7 + (disp / math.max(dt, 0.001)) * 0.3
	end
	rig.lastPos = pos

	local moving = rig.speed > 1.5
	if moving then
		rig.phase += dt * math.clamp(rig.speed * 0.9, 4, 11)
	else
		rig.phase += dt * 1.2
	end
	local swingAmp = moving and math.clamp(rig.speed / 12, 0.35, 1) or 0

	local torsoCF = rootCF * CFrame.new(rig.torsoCenterOffset)
	local frames: { [string]: CFrame } = {}

	for _, name in ORDER do
		local spec = rig.specs[name]
		local rot = CFrame.new()
		if spec.axis == "leg" and spec.swing then
			rot = CFrame.Angles(math.rad(spec.swing) * swingAmp * math.sin(rig.phase + math.rad(spec.phase or 0)), 0, 0)
		elseif spec.axis == "arm" and spec.swing then
			local swingA = math.rad(spec.swing) * swingAmp * math.sin(rig.phase + math.rad(spec.phase or 0))
			local cant = math.rad(name == "UpperArmL" and 5 or -5) -- arms tucked at sides, never T-pose
			rot = CFrame.Angles(swingA, 0, cant)
		elseif spec.axis == "knee" then
			local legSwing = math.sin(rig.phase + math.rad(spec.phase or 0))
			rot = CFrame.Angles(-math.max(0, -legSwing) * math.rad(32) * swingAmp, 0, 0)
		elseif spec.axis == "forearm" then
			rot = CFrame.Angles(math.rad(-20), 0, 0)
		elseif spec.axis == "hold" then
			rot = CFrame.Angles(math.rad(-58), math.rad(28), 0) -- weapon-hold across chest
		end

		local frame
		if spec.parent and frames[spec.parent] then
			-- child follows parent frame at its bind-relative offset, then articulates
			frame = frames[spec.parent] * CFrame.new(spec.bind - rig.specs[spec.parent].bind) * rot
		else
			frame = torsoCF * CFrame.new(spec.bind) * rot
		end
		frames[name] = frame
		rig.limbs[name].CFrame = frame
	end

	local visorPart = model:FindFirstChild("GFRig_VisorSlit")
	if visorPart and frames.HeadVis then
		visorPart.CFrame = frames.HeadVis * CFrame.new(0, 0.05*rig.scale, -0.52*rig.scale)
	end

	for _, pl in rig.plating do
		local frame = frames[pl.limb]
		if frame and pl.part.Parent then
			local rotY = pl.rotY ~= 0 and CFrame.Angles(0, math.rad(pl.rotY), 0) or CFrame.new()
			pl.part:PivotTo(frame * CFrame.new(pl.offset) * rotY)
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	for model, rig in rigs do
		if model.Parent then
			local ok, err = pcall(poseRig, rig, dt)
			if not ok then
				rigs[model] = nil
				warn("TroopVisuals rig error: " .. tostring(err))
			end
		else
			rigs[model] = nil
		end
	end
end)

local function watchModel(model: Instance)
	if not model:IsA("Model") then return end
	if model:GetAttribute("GFEnemy") == true then
		task.defer(function()
			task.wait(0.1)
			TroopVisuals.restyle(model)
		end)
	end
end

for _, m in Workspace:GetChildren() do
	watchModel(m)
end
Workspace.ChildAdded:Connect(watchModel)

function TroopVisuals.init()
	print("[TroopVisuals] rigged-body visual layer active")
end

return TroopVisuals
