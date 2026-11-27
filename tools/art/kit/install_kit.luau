-- Phase 15: run in Studio EDIT datamodel (execute_luau) when a Studio claim is held. Idempotent. NOT YET RUN.
-- Installs each uploaded kit asset as ServerStorage.GF.Art.<Kit_Faction_Piece> (Model with PrimaryPart "Mesh").
-- Import facts (same as veg): 1 m = 1 stud, TextureID palette set. Kit meshes are authored at game scale
-- (metres x 3.57), so NO ScaleTo is needed. Pieces are origin-at-bottom-centre EXCEPT Kit_Human_GunshipRamp (bbox centre), BlastDoorLeaf (hinge edge), TurretGun (yaw axis). ArtService.reskin() must NOT be applied to kit pieces (strips palette).
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
	Kit_Ascendancy_Rubble = 119761555911079, Kit_Ascendancy_Wall = 137704617030736,
	Kit_Human_LandingPad = 130364919966412,
	Kit_Human_Gunship = 128690203609542,
	Kit_Human_GunshipRamp = 107077273504853,
	Kit_Ascendancy_Relay = 133828914278357,
	Kit_Ascendancy_Tower = 88788862757244,
	Kit_Ascendancy_WallCorner = 71779102986154,
	Kit_Ascendancy_Pier = 85042288065460,
	Kit_Human_FloorPlate = 97305584175693,
	Kit_Human_FloorGrate = 127884111503109,
	Kit_Human_CeilingPanel = 95833875302317,
	Kit_Human_Column = 130064632448054,
	Kit_Human_DoorFrame = 96503316734031,
	Kit_Human_BlastDoorLeaf = 121220651296746,
	Kit_Human_Stairs = 127524845654464,
	Kit_Human_Ramp = 84578160809686,
	Kit_Human_Railing = 91159395547681,
	Kit_Human_Catwalk = 90733699554496,
	Kit_Human_Platform = 88779171207018,
	Kit_Human_RepairGantry = 70662674231587,
	Kit_Human_TurretBase = 77670551074469,
	Kit_Human_TurretGun = 100580723558746,
	Kit_Human_PowerCore = 125177824968295,
	Kit_Human_ShieldEmitter = 103026983945289,
	Kit_Human_SensorTower = 78028626801649,
	Kit_Human_Dish = 79309093127804,
	Kit_Human_Pipe = 130382979757561,
	Kit_Human_PipeElbow = 116667540602108,
	Kit_Human_Vent = 126196328557725,
	Kit_Human_WallWindow = 119351133355346,
	Kit_Terrain_RockSmall = 132856641722192,
	Kit_Terrain_RockMid = 99966241140889,
	Kit_Terrain_RockBig = 135526172298796,
	Kit_Terrain_RockSlab = 124492621134866,
	Kit_Terrain_RockSpire = 98006750538159,
	Kit_Terrain_RockCluster = 102541734725843,
	Kit_Terrain_CliffA = 111614282873274,
	Kit_Terrain_CliffB = 137427220698617,
	Kit_Terrain_CliffC = 101442340061140,
	Kit_Terrain_CliffD = 91518764273022,
	Kit_Human_WarTableDais = 132856999347984,
	Kit_Human_HoloPlanet = 72493783218850,
	Kit_Human_HoloSlotRing = 70823226131866,
	Kit_Human_HangarBulkhead = 111761384149237,
	Kit_Human_HangarMouth = 101790449389240,
	Kit_Human_ConcourseWindow = 85713375767099,
	Kit_Human_ConcourseTerminal = 106737154685238,
	Kit_Human_CargoStack = 110620806024823,
	Kit_Human_DeckLightBar = 83957025602894,
	Kit_Human_SquadBench = 110435381074739,
	Kit_Terrain_PlanetLimb = 108848160969818,
	Kit_Terrain_PlanetAtmo = 134039085072232,
	Kit_Ascendancy_TurretBase = 75897332876073,
	Kit_Ascendancy_TurretHead = 131733213303934,
	Kit_Ascendancy_Stairs = 109096700875261,
	Kit_Ascendancy_Beacon = 80268716113949,
	Kit_Ascendancy_Barricade = 79110412007725,
	Kit_Ascendancy_Crate = 99470302551969,
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
