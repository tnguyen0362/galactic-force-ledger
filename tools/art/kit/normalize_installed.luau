-- Run once in the Studio EDIT datamodel (execute_luau) when a Studio claim is held.
-- Applies install_kit.luau's normalize() to Kit_* models that were installed BEFORE normalize existed.
-- Idempotent: the pivot is only moved when it is still identity; fidelity/shadow settings are plain assignments.
local art = game:GetService("ServerStorage").GF.Art
local PIVOT_KEEP = { Kit_Human_GunshipRamp = true, Kit_Human_BlastDoorLeaf = true, Kit_Human_TurretGun = true,
	Kit_Terrain_PlanetLimb = true, Kit_Terrain_PlanetAtmo = true, Kit_Human_HoloPlanet = true, Kit_Ascendancy_TurretHead = true }
local n, moved = 0, 0
for _, model in art:GetChildren() do
	local name = model.Name
	if name:sub(1, 4) ~= "Kit_" or not model:IsA("Model") then continue end
	local mesh = model.PrimaryPart
	if not mesh or not mesh:IsA("MeshPart") then continue end
	if not PIVOT_KEEP[name] and mesh.PivotOffset == CFrame.new() then
		mesh.PivotOffset = CFrame.new(0, -mesh.Size.Y / 2, 0)
		moved += 1
	end
	mesh.RenderFidelity = Enum.RenderFidelity.Automatic
	local small = mesh.Size.Magnitude < 12
	if name:find("^Kit_Terrain_") and not name:find("Planet") then
		mesh.CollisionFidelity = small and Enum.CollisionFidelity.Box or Enum.CollisionFidelity.Hull
	end
	if small then mesh.CastShadow = false end
	n += 1
end
print(("normalize_installed: %d kit models, %d pivots moved to bottom-centre"):format(n, moved))
