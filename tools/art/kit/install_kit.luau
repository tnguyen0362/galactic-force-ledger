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
	Kit_Ascendancy_Monolith = 79384435228762, Kit_Ascendancy_Gate = 130661898006546,
	Kit_Ascendancy_Bulwark = 121647017919492, Kit_Ascendancy_Spire = 82534411847979,
	Kit_Ascendancy_Rubble = 90454573295782, Kit_Ascendancy_Wall = 126063438873050,
	Kit_Human_LandingPad = 130364919966412,
	Kit_Human_Gunship = 124907466467290,
	Kit_Human_GunshipRamp = 107077273504853,
	Kit_Ascendancy_Relay = 130393613543036,
	Kit_Ascendancy_Tower = 123847265121458,
	Kit_Ascendancy_WallCorner = 111302061110258,
	Kit_Ascendancy_Pier = 73541002728384,
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
	Kit_Terrain_CliffA = 135542369389356,
	Kit_Terrain_CliffB = 88019398864267,
	Kit_Terrain_CliffC = 127694446868499,
	Kit_Terrain_CliffD = 92498727312542,
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
	Kit_Terrain_PlanetLimb = 102713134664027,
	Kit_Terrain_PlanetAtmo = 105654515100507,
	Kit_Ascendancy_TurretBase = 123651944227342,
	Kit_Ascendancy_TurretHead = 92211831617381,
	Kit_Ascendancy_Stairs = 105052819068398,
	Kit_Ascendancy_Beacon = 86661763952078,
	Kit_Ascendancy_Barricade = 98618217376700,
	Kit_Ascendancy_Crate = 140107669419232,
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
