-- Phase 15: BASEKIT trim-atlas installer. Run in a Studio EDIT datamodel (execute_luau) while holding the Studio claim.
-- Installs ServerStorage.GF.Art.Kit_BK_<piece> (Model: body MeshPart "Mesh" = PrimaryPart, optional Neon "Glow").
-- Textures: SurfaceAppearance must use STANDALONE Image assets (GLB-embedded image ids render flat in SA).
-- Idempotent per piece unless FORCE = true (then the existing Kit_BK_<piece> is replaced).
local FORCE = false
local IS = game:GetService("InsertService")
local SS = game:GetService("ServerStorage")
local gf = SS:FindFirstChild("GF") or Instance.new("Folder", SS)
gf.Name = "GF"
local art = gf:FindFirstChild("Art") or Instance.new("Folder", gf)
art.Name = "Art"

local TEX = { Color = 70699179471119, Normal = 77699624816558, Rough = 122940078634629, Metal = 92499342026501 }
local ACCENT = Color3.fromRGB(255, 105, 10) -- deep amber (Neon blows lighter colours out to lemon yellow); cyan = 51,217,255

local IDS = {
	Antenna = 86314391703891, Barricade = 138613836851922, Blast_Door = 99482046061272, Boom_Gate = 136222637296647,
	Container = 104862505228358, Corner_Column = 129302291819145, Crates = 85947267167216, Door_Frame = 102163583704200,
	Floor_Panel = 107727360615353, Fuel_Tank = 124593221744118, Generator = 122445098205141, Howitzer = 133390130330840,
	Light_Mast = 106163827808375, Radar = 76691293892787, Railing = 97055550864130, Roof_Gable = 101740703236807,
	Roof_Slab = 102778747874944, Shield_Emitter = 89196824091659, Stairs = 74995798933346, Turret = 70995542463113,
	Wall_Vent = 92341203928238, Wall_Window = 93520992025156, Wall_Solid = 99138559032129,
}

local installed, failed = 0, {}
for piece, id in IDS do
	local name = "Kit_BK_" .. piece
	local old = art:FindFirstChild(name)
	if old then
		if not FORCE then continue end
		old:Destroy()
	end
	local ok, loaded = pcall(function() return IS:LoadAsset(id) end)
	if not ok then table.insert(failed, name .. ": " .. tostring(loaded)); continue end
	local body, glow
	for _, d in loaded:GetDescendants() do
		if d:IsA("MeshPart") then
			if d.Name:find("^Glow") then glow = d else body = body or d end
		end
	end
	if not body then table.insert(failed, name .. ": no body MeshPart"); loaded:Destroy(); continue end
	local model = Instance.new("Model")
	model.Name = name
	for _, p in { body, glow } do
		p.Anchored = true
		for _, c in p:GetChildren() do
			if c:IsA("SurfaceAppearance") then c:Destroy() end
		end
	end
	body.Name = "Mesh"
	local sa = Instance.new("SurfaceAppearance")
	sa.ColorMap = "rbxassetid://" .. TEX.Color
	sa.NormalMap = "rbxassetid://" .. TEX.Normal
	sa.RoughnessMap = "rbxassetid://" .. TEX.Rough
	sa.MetalnessMap = "rbxassetid://" .. TEX.Metal
	sa.Parent = body
	body.Parent = model
	if glow then
		glow.Name = "Glow"
		glow.Material = Enum.Material.Neon
		glow.Color = ACCENT
		glow.CastShadow = false
		glow.CanCollide = false
		glow.Parent = model
	end
	model.PrimaryPart = body
	-- pivot: bottom-centre of the whole model's bbox (Roblox recentres each mesh on its own bbox centre)
	-- NOTE: WorldPivot is ignored once PrimaryPart is set, so the pivot must live in body.PivotOffset.
	local cf, size = model:GetBoundingBox()
	body.PivotOffset = body.CFrame:ToObjectSpace(cf * CFrame.new(0, -size.Y / 2, 0))
	body.RenderFidelity = Enum.RenderFidelity.Automatic
	model:SetAttribute("GF_AssetId", id)
	model:SetAttribute("GF_ArtSource", "Blender bk_bake.py trim-atlas")
	model.Parent = art
	loaded:Destroy()
	installed += 1
end
print(("install_bk: installed=%d failed=%d"):format(installed, #failed))
for _, f in failed do warn(f) end
