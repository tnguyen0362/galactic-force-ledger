--!strict
-- RigBuilder: one-shot constructor for the AscendancyTrooper rig asset in ServerStorage.GF.Art.
-- Run once in Edit mode — the asset persists with the place. Enemies pick it up through the
-- existing ArtService.clone path in EnemyService (zero behavior edits).
--
-- Rig doctrine: R15-style Motor6D hierarchy, arms at sides, right arm in weapon-hold pose,
-- violet visor slit, mesh plating welded to limbs so armor articulates with animation.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RigBuilder = {}

function RigBuilder.build()
	local SS = ServerStorage
	local gf = SS:FindFirstChild("GF") or Instance.new("Folder")
	gf.Name = "GF"
	gf.Parent = SS
	local art = gf:FindFirstChild("Art") or Instance.new("Folder")
	art.Name = "Art"
	art.Parent = gf
	local old = art:FindFirstChild("AscendancyTrooper")
	if old then old:Destroy() end

	local OBSIDIAN = Color3.fromRGB(36, 33, 42)
	local VIOLETGRAY = Color3.fromRGB(81, 70, 94)
	local ENERGY = Color3.fromRGB(169, 99, 233)

	local rig = Instance.new("Model")
	rig.Name = "AscendancyTrooper"

	local function limb(name, size, cf, color)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color or OBSIDIAN
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Anchored = false
		p.Parent = rig
		return p
	end

	local root = limb("HumanoidRootPart", Vector3.new(2, 1, 1), CFrame.new(0, 3.1, 0))
	root.Transparency = 1
	local lowerTorso = limb("LowerTorso", Vector3.new(1.85, 1.1, 1.1), CFrame.new(0, 3.1, 0), VIOLETGRAY)
	local upperTorso = limb("UpperTorso", Vector3.new(2.0, 1.3, 1.2), CFrame.new(0, 4.15, 0))
	local head = limb("Head", Vector3.new(1.0, 1.0, 1.0), CFrame.new(0, 5.45, 0))
	local upperArmL = limb("UpperArmL", Vector3.new(0.65, 1.2, 0.65), CFrame.new(-1.42, 4.1, 0))
	local lowerArmL = limb("LowerArmL", Vector3.new(0.58, 1.1, 0.58), CFrame.new(-1.45, 3.0, -0.1), VIOLETGRAY)
	local handL = limb("HandL", Vector3.new(0.5, 0.55, 0.5), CFrame.new(-1.45, 2.3, -0.18), VIOLETGRAY)
	local upperArmR = limb("UpperArmR", Vector3.new(0.65, 1.2, 0.65), CFrame.new(1.42, 4.1, 0))
	local lowerArmR = limb("LowerArmR", Vector3.new(0.58, 1.1, 0.58), CFrame.new(1.05, 3.35, -0.75), VIOLETGRAY)
	local handR = limb("HandR", Vector3.new(0.5, 0.55, 0.5), CFrame.new(0.75, 3.6, -1.1), VIOLETGRAY)
	local upperLegL = limb("UpperLegL", Vector3.new(0.8, 1.3, 0.85), CFrame.new(-0.52, 1.95, 0))
	local lowerLegL = limb("LowerLegL", Vector3.new(0.72, 1.25, 0.78), CFrame.new(-0.52, 0.72, 0.02), VIOLETGRAY)
	local footL = limb("FootL", Vector3.new(0.72, 0.35, 1.0), CFrame.new(-0.52, 0.18, -0.1), VIOLETGRAY)
	local upperLegR = limb("UpperLegR", Vector3.new(0.8, 1.3, 0.85), CFrame.new(0.52, 1.95, 0))
	local lowerLegR = limb("LowerLegR", Vector3.new(0.72, 1.25, 0.78), CFrame.new(0.52, 0.72, 0.02), VIOLETGRAY)
	local footR = limb("FootR", Vector3.new(0.72, 0.35, 1.0), CFrame.new(0.52, 0.18, -0.1), VIOLETGRAY)

	local function bindJoint(name, p0, p1)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = CFrame.new()
		m.C1 = p0.CFrame:Inverse() * p1.CFrame
		m.Parent = p0
		return m
	end

	bindJoint("RootJoint", root, lowerTorso)
	bindJoint("Waist", lowerTorso, upperTorso)
	bindJoint("Neck", upperTorso, head)
	bindJoint("ShoulderL", upperTorso, upperArmL)
	bindJoint("ElbowL", upperArmL, lowerArmL)
	bindJoint("WristL", lowerArmL, handL)
	bindJoint("ShoulderR", upperTorso, upperArmR)
	bindJoint("ElbowR", upperArmR, lowerArmR)
	bindJoint("WristR", lowerArmR, handR)
	bindJoint("HipL", lowerTorso, upperLegL)
	bindJoint("KneeL", upperLegL, lowerLegL)
	bindJoint("AnkleL", lowerLegL, footL)
	bindJoint("HipR", lowerTorso, upperLegR)
	bindJoint("KneeR", upperLegR, lowerLegR)
	bindJoint("AnkleR", lowerLegR, footR)

	local visor = limb("VisorSlit", Vector3.new(0.7, 0.13, 0.08), head.CFrame * CFrame.new(0, 0.05, -0.5), ENERGY)
	visor.Material = Enum.Material.Neon
	bindJoint("VisorJoint", head, visor)

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.Parent = rig
	rig.PrimaryPart = root

	local kit = ReplicatedStorage:FindFirstChild("GFTroopKit")
	local plated = 0
	if kit then
		local function plate(kitName, parentLimb, offset, rotY)
			local t = kit:FindFirstChild(kitName)
			if not t then return end
			local piece = t:Clone()
			piece.Name = "Plate_" .. kitName .. "_" .. parentLimb.Name
			local anchor = nil
			for _, d in piece:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.Anchored = false
					d.Material = Enum.Material.Metal
					d.Massless = true
					if not anchor then anchor = d end
				end
			end
			piece:PivotTo(parentLimb.CFrame * CFrame.new(offset) * CFrame.Angles(0, math.rad(rotY or 0), 0))
			piece.Parent = rig
			if anchor then
				local w = Instance.new("WeldConstraint")
				w.Part0 = parentLimb
				w.Part1 = anchor
				w.Parent = anchor
				plated += 1
			end
		end
		plate("RifleHelmet", head, Vector3.new(0, 0.05, 0))
		plate("ChestArmor", upperTorso, Vector3.new(0, 0.05, 0))
		plate("Pauldron", upperArmL, Vector3.new(-0.15, 0.45, 0))
		plate("Pauldron", upperArmR, Vector3.new(0.15, 0.45, 0), 180)
		plate("Greave", lowerLegL, Vector3.new(0, 0.1, 0))
		plate("Greave", lowerLegR, Vector3.new(0, 0.1, 0), 180)
		plate("EnergyRifle", handR, Vector3.new(0, 0.1, -0.4))
	end

	rig.Parent = art
	return "RIG BUILT plated=" .. plated
end

return RigBuilder
