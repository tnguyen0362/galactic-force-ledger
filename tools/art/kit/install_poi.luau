-- Mission POI props (gen_poi.py). Run in Studio EDIT datamodel under a Studio claim. Idempotent, additive.
-- Installs ServerStorage.GF.Art.Kit_POI_<Name> (Model, PrimaryPart "Mesh", bottom-centre pivot).
-- Same import facts as install_kit.luau: authored at game scale, Roblox recentres mesh on bbox centre.
local IS = game:GetService("InsertService")
local SS = game:GetService("ServerStorage")
local gf = SS:FindFirstChild("GF") or Instance.new("Folder", SS)
gf.Name = "GF"
local art = gf:FindFirstChild("Art") or Instance.new("Folder", gf)
art.Name = "Art"

local IDS = {
	Kit_POI_SupplyCache = 89624137012148,
	Kit_POI_LootCase = 90107990160994,
	Kit_POI_RepairConsole = 95930127812262,
	Kit_POI_RadarTower = 127402216387685,
	Kit_POI_AlarmBeacon = 113886209475137,
}
-- Collision: lattice tower keeps precise (Default) collision so players/bullets pass between the legs.
local COLLISION = {
	Kit_POI_SupplyCache = Enum.CollisionFidelity.Hull,
	Kit_POI_LootCase = Enum.CollisionFidelity.Box,
	Kit_POI_RepairConsole = Enum.CollisionFidelity.Hull,
	Kit_POI_RadarTower = Enum.CollisionFidelity.Default,
	Kit_POI_AlarmBeacon = Enum.CollisionFidelity.Hull,
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
	if mesh.PivotOffset == CFrame.new() then
		mesh.PivotOffset = CFrame.new(0, -mesh.Size.Y / 2, 0)
	end
	mesh.RenderFidelity = Enum.RenderFidelity.Automatic
	mesh.CollisionFidelity = COLLISION[name]
	if name == "Kit_POI_LootCase" then mesh.CastShadow = false end
	model:SetAttribute("GF_AssetId", id)
	model:SetAttribute("GF_ArtSource", "Blender gen_poi.py")
	model.Parent = art
	loaded:Destroy()
	installed += 1
end
print(("install_poi: installed=%d failed=%d"):format(installed, #failed))
for _, f in failed do warn(f) end
