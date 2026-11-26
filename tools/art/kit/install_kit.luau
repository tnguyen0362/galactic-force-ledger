-- Phase 15: run in Studio EDIT datamodel (execute_luau) when a Studio claim is held. Idempotent. NOT YET RUN.
-- Installs each uploaded kit asset as ServerStorage.GF.Art.<Kit_Faction_Piece> (Model with PrimaryPart "Mesh").
-- Import facts (same as veg): 1 m = 1 stud, TextureID palette set. Kit meshes are authored at game scale
-- (metres x 3.57), so NO ScaleTo is needed. Pieces are origin-at-bottom-centre.
local IS = game:GetService("InsertService")
local SS = game:GetService("ServerStorage")
local gf = SS:FindFirstChild("GF") or Instance.new("Folder", SS)
gf.Name = "GF"
local art = gf:FindFirstChild("Art") or Instance.new("Folder", gf)
art.Name = "Art"

local IDS = {
	Kit_Human_Wall = 78145619866293, Kit_Human_Pillar = 111910159887747, Kit_Human_Bunker = 104250208921145,
	Kit_Human_Watchtower = 77836466169070, Kit_Human_Barrier = 85967161570983, Kit_Human_Hedgehog = 130834263337906,
	Kit_Human_Crate = 137824519792014, Kit_Human_Crates = 96912439161712, Kit_Human_FuelTank = 116803000293681,
	Kit_Human_Generator = 109771967204366, Kit_Human_CommMast = 85691648944984,
	Kit_Ascendancy_Monolith = 91015425713994, Kit_Ascendancy_Gate = 94664697958999,
	Kit_Ascendancy_Bulwark = 72636059338655, Kit_Ascendancy_Spire = 78931911662518,
	Kit_Ascendancy_Rubble = 119761555911079,
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
	mesh.Name = "Mesh"
	mesh.Parent = model
	model.PrimaryPart = mesh
	model:SetAttribute("GF_AssetId", id)
	model:SetAttribute("GF_ArtSource", "Blender gen_kit.py")
	model.Parent = art
	loaded:Destroy()
	installed += 1
end
print(("install_kit: installed=%d failed=%d"):format(installed, #failed))
for _, f in failed do warn(f) end
