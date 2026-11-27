-- Run in Studio EDIT datamodel (execute_luau) with a Studio claim held. Idempotent (replaces Hero_Asc_Rifleman). NOT YET RUN.
-- Generated: tools/art/hero/make_install.sh = this template + rifleman_data.luau + asset id.
-- Builds ServerStorage.GF.Art.Hero_Asc_Rifleman from the uploaded GLB (rigid MeshParts, bind pose from Blender).
-- Rig contract = RigBuilder.luau (AscendancyTrooper) so EnemyAnimClient v2 can drive it unchanged:
--   parts  HumanoidRootPart LowerTorso UpperTorso Head UpperArmL/R LowerArmL/R HandL/R UpperLegL/R LowerLegL/R FootL/R
--   joints RootJoint Waist Neck ShoulderL/R ElbowL/R WristL/R HipL/R KneeL/R AnkleL/R  (Motor6D, parented to Part0)
--   C0/C1 = partBind^-1 * pivot, exactly like RigBuilder, so Transform rotates about the real anatomical pivot.
-- Extra: Rifle (Motor6D RifleGrip on HandR), Glow_* neon accent parts (GlowJoint on their segment).
-- Authored facing -Z, feet at y=0, ~6.9 studs tall (R15 ~5.4): :ScaleTo() to tune. Right-handed shooter (rifle in HandR).
local ASSET_ID = 133853824795485
-- GENERATED from Hero_Ascendancy_Rifleman_rig.json (Blender export). Studs, feet at y=0, model faces -Z.
local DATA = {
	parts = {
		["LowerTorso"] = { center = Vector3.new(-0.0005, 3.3802, -0.0515), size = Vector3.new(2.1195, 2.3654, 1.4686), tris = 710 },
		["UpperTorso"] = { center = Vector3.new(0.0008, 5.2479, 0.1050), size = Vector3.new(1.7742, 2.4990, 1.8723), tris = 788 },
		["UpperLegL"] = { center = Vector3.new(-0.5421, 2.7016, -0.2693), size = Vector3.new(0.9475, 1.5919, 1.2374), tris = 258 },
		["LowerLegL"] = { center = Vector3.new(-0.4487, 1.2611, -0.4670), size = Vector3.new(0.7253, 1.7261, 0.8924), tris = 256 },
		["UpperArmL"] = { center = Vector3.new(-1.2444, 5.0394, -0.5917), size = Vector3.new(0.7676, 1.2463, 1.7344), tris = 258 },
		["LowerArmL"] = { center = Vector3.new(-0.6507, 4.6959, -1.8072), size = Vector3.new(1.2349, 0.8815, 1.3715), tris = 294 },
		["HandL"] = { center = Vector3.new(-0.0007, 5.0448, -2.5223), size = Vector3.new(0.4961, 0.4179, 0.4803), tris = 160 },
		["UpperLegR"] = { center = Vector3.new(0.4225, 2.6890, -0.0379), size = Vector3.new(0.9055, 1.5009, 1.0685), tris = 258 },
		["LowerLegR"] = { center = Vector3.new(0.6257, 1.2831, 0.2724), size = Vector3.new(0.6930, 1.8037, 1.1149), tris = 256 },
		["UpperArmR"] = { center = Vector3.new(1.1465, 4.9191, -0.2782), size = Vector3.new(0.5554, 1.3282, 1.0237), tris = 198 },
		["LowerArmR"] = { center = Vector3.new(0.7907, 4.5451, -0.9368), size = Vector3.new(1.1647, 1.0070, 1.0517), tris = 294 },
		["HandR"] = { center = Vector3.new(0.1595, 5.0265, -1.4356), size = Vector3.new(0.5051, 0.4678, 0.4200), tris = 160 },
		["Glow_UpperTorso"] = { center = Vector3.new(0.0000, 4.8552, 0.9103), size = Vector3.new(0.3509, 0.4238, 0.0653), tris = 78 },
		["FootL"] = { center = Vector3.new(-0.5319, 0.3915, -0.4632), size = Vector3.new(0.6477, 0.7729, 1.4088), tris = 258 },
		["FootR"] = { center = Vector3.new(0.6071, 0.3922, 0.4294), size = Vector3.new(0.6459, 0.7709, 1.4089), tris = 258 },
		["Rifle"] = { center = Vector3.new(0.0399, 4.8048, -2.1123), size = Vector3.new(1.1608, 1.2554, 3.2813), tris = 512 },
		["Glow_Rifle"] = { center = Vector3.new(0.1654, 4.9781, -1.6308), size = Vector3.new(0.4240, 0.5098, 1.0458), tris = 78 },
		["Head"] = { center = Vector3.new(-0.0001, 6.2206, -0.0563), size = Vector3.new(1.2227, 1.4981, 1.7895), tris = 1082 },
		["Glow_Head"] = { center = Vector3.new(-0.0000, 6.1082, -0.7422), size = Vector3.new(0.4266, 0.0200, 0.0481), tris = 96 },
	},
	pivots = {
		["HumanoidRootPart"] = { head = Vector3.new(-0.0000, 3.1416, -0.0000), parent = nil },
		["LowerTorso"] = { head = Vector3.new(-0.0000, 3.4986, -0.0000), parent = "HumanoidRootPart" },
		["UpperTorso"] = { head = Vector3.new(-0.0000, 4.2126, -0.0000), parent = "LowerTorso" },
		["Head"] = { head = Vector3.new(-0.0000, 5.4264, -0.2499), parent = "UpperTorso" },
		["UpperArmL"] = { head = Vector3.new(-1.1067, 5.3193, -0.1071), parent = "UpperTorso" },
		["LowerArmL"] = { head = Vector3.new(-1.0710, 4.4982, -1.4280), parent = "UpperArmL" },
		["HandL"] = { head = Vector3.new(-0.1428, 4.9266, -2.2848), parent = "LowerArmL" },
		["UpperArmR"] = { head = Vector3.new(1.1067, 5.3193, -0.1071), parent = "UpperTorso" },
		["LowerArmR"] = { head = Vector3.new(1.1781, 4.2840, -0.7140), parent = "UpperArmR" },
		["HandR"] = { head = Vector3.new(0.2142, 4.9444, -1.2495), parent = "LowerArmR" },
		["Rifle"] = { head = Vector3.new(0.2392, 4.9659, -1.3780), parent = "HandR" },
		["UpperLegL"] = { head = Vector3.new(-0.4641, 3.4629, 0.0000), parent = "LowerTorso" },
		["LowerLegL"] = { head = Vector3.new(-0.5355, 1.9635, -0.7140), parent = "UpperLegL" },
		["FootL"] = { head = Vector3.new(-0.5355, 0.3927, -0.3927), parent = "LowerLegL" },
		["UpperLegR"] = { head = Vector3.new(0.4641, 3.4629, -0.0000), parent = "LowerTorso" },
		["LowerLegR"] = { head = Vector3.new(0.5355, 1.9278, -0.1428), parent = "UpperLegR" },
		["FootR"] = { head = Vector3.new(0.6069, 0.3927, 0.4998), parent = "LowerLegR" },
	},
}
local IS = game:GetService("InsertService")
local SS = game:GetService("ServerStorage")
local gf = SS:FindFirstChild("GF") or Instance.new("Folder", SS)
gf.Name = "GF"
local art = gf:FindFirstChild("Art") or Instance.new("Folder", gf)
art.Name = "Art"
local old = art:FindFirstChild("Hero_Asc_Rifleman")
if old then old:Destroy() end

local loaded = IS:LoadAsset(ASSET_ID)
local ENERGY = Color3.fromRGB(169, 99, 233)
local meshes = {}
local seen = {}
for _, d in loaded:GetDescendants() do
	if d:IsA("MeshPart") then
		local n = d.Name:gsub("%.%d+$", "")
		meshes[n] = d
		table.insert(seen, n)
	end
end
-- glTF object names are the Blender export names: LeftUpperArm -> UpperArmL etc.
local MAP = { LeftUpperArm = "UpperArmL", LeftLowerArm = "LowerArmL", LeftHand = "HandL", RightUpperArm = "UpperArmR",
	RightLowerArm = "LowerArmR", RightHand = "HandR", LeftUpperLeg = "UpperLegL", LeftLowerLeg = "LowerLegL",
	LeftFoot = "FootL", RightUpperLeg = "UpperLegR", RightLowerLeg = "LowerLegR", RightFoot = "FootR" }
local byRig = {}
for n, m in meshes do byRig[MAP[n] or n] = m end

local rig = Instance.new("Model")
rig.Name = "Hero_Asc_Rifleman"
local parts = {}
local report = { missing = {}, sizeDev = {}, tris = 0 }
local PARENT_OF_GLOW = { Glow_Head = "Head", Glow_UpperTorso = "UpperTorso", Glow_Rifle = "Rifle" }

for name, def in DATA.parts do
	local src = byRig[name]
	if not src then table.insert(report.missing, name) continue end
	local p = src:Clone()
	p.Name = name
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.RenderFidelity = Enum.RenderFidelity.Automatic
	p.CollisionFidelity = Enum.CollisionFidelity.Box
	for _, c in p:GetChildren() do c:Destroy() end
	-- Roblox's glTF importer rotates the mesh 180deg about Y vs the Blender export (loaded positions are (-x,y,-z) of the manifest).
	-- Keep the loaded mesh, rotate each part about its own centre so the baked geometry faces -Z again.
	p.CFrame = CFrame.new(def.center) * CFrame.Angles(0, math.pi, 0)
	report.posDev = (report.posDev or 0) + (Vector3.new(-src.Position.X, src.Position.Y, -src.Position.Z) - def.center).Magnitude
	report.sizeDev[name] = (p.Size - def.size).Magnitude
	report.tris += def.tris
	if name:find("^Glow_") then
		p.Material = Enum.Material.Neon
		p.Color = ENERGY
		p.TextureID = ""
		p.CastShadow = false
	end
	p.Parent = rig
	parts[name] = p
end

local hrp = Instance.new("Part")
hrp.Name = "HumanoidRootPart"
hrp.Size = Vector3.new(1.6, 0.9, 0.9)
hrp.CFrame = CFrame.new(0, 3.05, 0)
hrp.Transparency = 1
hrp.CanCollide = false
hrp.CanQuery = false
hrp.CanTouch = false
hrp.Massless = true
hrp.Parent = rig
parts.HumanoidRootPart = hrp

local function joint(jname, p0n, p1n, pivot)
	local p0, p1 = parts[p0n], parts[p1n]
	if not (p0 and p1) then table.insert(report.missing, jname) return end
	local m = Instance.new("Motor6D")
	m.Name = jname
	m.Part0, m.Part1 = p0, p1
	m.C0 = p0.CFrame:Inverse() * CFrame.new(pivot)
	m.C1 = p1.CFrame:Inverse() * CFrame.new(pivot)
	m.Parent = p0
end
local P = function(n) return DATA.pivots[n].head end
joint("RootJoint", "HumanoidRootPart", "LowerTorso", P("LowerTorso"))
joint("Waist", "LowerTorso", "UpperTorso", P("UpperTorso"))
joint("Neck", "UpperTorso", "Head", P("Head"))
for _, s in { "L", "R" } do
	joint("Shoulder" .. s, "UpperTorso", "UpperArm" .. s, P("UpperArm" .. s))
	joint("Elbow" .. s, "UpperArm" .. s, "LowerArm" .. s, P("LowerArm" .. s))
	joint("Wrist" .. s, "LowerArm" .. s, "Hand" .. s, P("Hand" .. s))
	joint("Hip" .. s, "LowerTorso", "UpperLeg" .. s, P("UpperLeg" .. s))
	joint("Knee" .. s, "UpperLeg" .. s, "LowerLeg" .. s, P("LowerLeg" .. s))
	joint("Ankle" .. s, "LowerLeg" .. s, "Foot" .. s, P("Foot" .. s))
end
-- fixed attachments (rigid): rifle -> HandR, glow parts -> their segment
local function fixed(jname, p0n, p1n)
	local p0, p1 = parts[p0n], parts[p1n]
	if not (p0 and p1) then table.insert(report.missing, jname) return end
	local m = Instance.new("Motor6D")
	m.Name = jname
	m.Part0, m.Part1 = p0, p1
	m.C0 = p0.CFrame:Inverse() * p1.CFrame
	m.C1 = CFrame.new()
	m.Parent = p0
end
fixed("RifleGrip", "HandR", "Rifle")
for g, seg in PARENT_OF_GLOW do fixed("GlowJoint_" .. g, seg, g) end

local hum = Instance.new("Humanoid")
hum.RigType = Enum.HumanoidRigType.R15
hum.Parent = rig
rig.PrimaryPart = hrp
rig:SetAttribute("GF_AssetId", ASSET_ID)
rig:SetAttribute("GF_ArtSource", "Blender hero_wip asc_rifleman_v6_nocape")
rig.Parent = art
loaded:Destroy()

local lines = { string.format("Hero_Asc_Rifleman built: parts=%d tris=%d missing=%s posDevSum=%.3f", #rig:GetChildren(), report.tris, table.concat(report.missing, ","), report.posDev or -1) }
for n, dev in report.sizeDev do if dev > 0.08 then table.insert(lines, string.format("SIZE DEV %s %.3f", n, dev)) end end
table.insert(lines, "meshes found in asset: " .. table.concat(seen, ","))
warn(table.concat(lines, "\n"))
