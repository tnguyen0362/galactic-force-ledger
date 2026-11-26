-- Phase 15: run in Studio EDIT datamodel (execute_luau). Idempotent.
-- Loads each uploaded vegetation asset and installs it as ServerStorage.GF.Art.Veg_<Biome>_<Role>_<Letter>
-- (ArtService/VegetationService naming contract). Import facts verified 2026-11-26: 1 m = 1 stud,
-- TextureID palette set, MeshPart unanchored; VegetationService ScaleTo's and anchors at plant time.
local IS = game:GetService("InsertService")
local SS = game:GetService("ServerStorage")
local gf = SS:FindFirstChild("GF") or Instance.new("Folder", SS)
gf.Name = "GF"
local art = gf:FindFirstChild("Art") or Instance.new("Folder", gf)
art.Name = "Art"

local IDS = {
	Veg_Forest_Canopy_A = 138699870623544, Veg_Forest_Canopy_B = 70862342135386, Veg_Forest_Mid_A = 105212206621348,
	Veg_Forest_Mid_B = 110555934018786, Veg_Forest_Scrub_A = 73105923300767, Veg_Forest_Scrub_B = 99988777872921,
	Veg_Forest_Ground_A = 115445375481407, Veg_Forest_Rock_A = 110764446502472, Veg_Forest_Rock_B = 106825151960291,
	Veg_Tundra_Canopy_A = 88762825924976, Veg_Tundra_Canopy_B = 103551234087461, Veg_Tundra_Mid_A = 124365134748760,
	Veg_Tundra_Scrub_A = 85126312039719, Veg_Tundra_Ground_A = 92087509475684, Veg_Tundra_Rock_A = 74869997238833,
	Veg_Tundra_Rock_B = 81263835738320, Veg_Tundra_Rock_C = 75355749830032,
	Veg_Arid_Canopy_A = 74007424230853, Veg_Arid_Mid_A = 99845954004459, Veg_Arid_Scrub_A = 98576432497996,
	Veg_Arid_Scrub_B = 87827872082950, Veg_Arid_Ground_A = 137048977470084, Veg_Arid_Rock_A = 73717783497249,
	Veg_Arid_Rock_B = 109669179468953, Veg_Arid_Rock_C = 123454110354756,
	Veg_Industrial_Canopy_A = 135068004620977, Veg_Industrial_Mid_A = 71529066284340, Veg_Industrial_Scrub_A = 77645721671866,
	Veg_Industrial_Ground_A = 130721585772696, Veg_Industrial_Rock_A = 106913285719528, Veg_Industrial_Rock_B = 71361548845168,
}

local installed, failed = 0, {}
for name, id in IDS do
	if art:FindFirstChild(name) then continue end
	local ok, loaded = pcall(function() return IS:LoadAsset(id) end)
	if not ok then table.insert(failed, name .. ": " .. tostring(loaded)); continue end
	local mesh
	for _, d in loaded:GetDescendants() do
		if d:IsA("MeshPart") then mesh = d break end
	end
	if not mesh then table.insert(failed, name .. ": no MeshPart"); loaded:Destroy(); continue end
	local model = Instance.new("Model")
	model.Name = name
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.Name = "Mesh"
	mesh.Parent = model
	model.PrimaryPart = mesh
	model:SetAttribute("GF_AssetId", id)
	model:SetAttribute("GF_ArtSource", "Blender gen_veg.py")
	model.Parent = art
	loaded:Destroy()
	installed += 1
end
print(("install_veg: installed=%d failed=%d"):format(installed, #failed))
for _, f in failed do warn(f) end
