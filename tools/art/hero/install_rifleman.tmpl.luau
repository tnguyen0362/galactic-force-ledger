-- Run in Studio EDIT datamodel (execute_luau) with a Studio claim held. Idempotent (replaces Hero_Asc_Rifleman). NOT YET RUN.
-- Generated: tools/art/hero/make_install.sh = this template + rifleman_data.luau + asset id.
-- Builds ServerStorage.GF.Art.Hero_Asc_Rifleman from the uploaded GLB (rigid MeshParts, bind pose from Blender).
-- Rig contract = RigBuilder.luau (AscendancyTrooper) so EnemyAnimClient v2 can drive it unchanged:
--   parts  HumanoidRootPart LowerTorso UpperTorso Head UpperArmL/R LowerArmL/R HandL/R UpperLegL/R LowerLegL/R FootL/R
--   joints RootJoint Waist Neck ShoulderL/R ElbowL/R WristL/R HipL/R KneeL/R AnkleL/R  (Motor6D, parented to Part0)
--   C0/C1 = partBind^-1 * pivot, exactly like RigBuilder, so Transform rotates about the real anatomical pivot.
-- Extra: Rifle (Motor6D RifleGrip on HandR), Glow_* neon accent parts (GlowJoint on their segment).
-- Authored facing -Z, feet at y=0, ~6.6 studs tall (R15 ~5.4): :ScaleTo() to tune. Right-handed shooter (rifle in HandR).
local ASSET_ID = __ASSET_ID__
__DATA__
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
local report = { missing = {}, sizeDev = {}, tris = 0, noSA = {} }
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
	-- keep baked PBR SurfaceAppearance on body parts; glow parts are plain Neon
	local isGlow = name:find("^Glow_") ~= nil
	for _, c in p:GetChildren() do
		if not (c:IsA("SurfaceAppearance") and not isGlow) then c:Destroy() end
	end
	if not isGlow then
		if p:FindFirstChildOfClass("SurfaceAppearance") then report.sa = (report.sa or 0) + 1 else table.insert(report.noSA, name) end
	end
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
rig:SetAttribute("GF_ArtSource", "Blender hero_wip asc_rifleman_v8 anatomical + baked PBR atlas (BC/N/RM)")
rig.Parent = art
loaded:Destroy()

local lines = { string.format("Hero_Asc_Rifleman built: parts=%d tris=%d missing=%s posDevSum=%.3f", #rig:GetChildren(), report.tris, table.concat(report.missing, ","), report.posDev or -1) }
for n, dev in report.sizeDev do if dev > 0.08 then table.insert(lines, string.format("SIZE DEV %s %.3f", n, dev)) end end
table.insert(lines, string.format("SurfaceAppearance on %d body parts; without: %s", report.sa or 0, table.concat(report.noSA, ",")))
table.insert(lines, "meshes found in asset: " .. table.concat(seen, ","))
warn(table.concat(lines, "\n"))
