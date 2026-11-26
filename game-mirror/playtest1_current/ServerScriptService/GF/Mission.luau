--!strict
-- Mission controller: wires services for a single generated operation.
local Players = game:GetService("Players")
local Services = script.Parent:WaitForChild("Services")
local State = require(Services.State)
local SquadService = require(Services.SquadService)
local LootService = require(Services.LootService)
local ObjectiveService = require(Services.ObjectiveService)
local ExtractionService = require(Services.ExtractionService)
local EncounterDirector = require(Services.EncounterDirector)

-- The station is built first, on purpose: this script used to call StationService at the very end,
-- so any error above it left the whole game with no shell at all (a boot with zero Station parts).
 -- StationService is idempotent: build() destroys any previous Station before rebuilding.
require(Services.StationService).start()

local function onCharacter(player: Player)
	SquadService.join(player)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function() onCharacter(player) end)
end)
for _, player in Players:GetPlayers() do
	onCharacter(player)
	player.CharacterAdded:Connect(function() onCharacter(player) end)
end
Players.PlayerRemoving:Connect(function(player) SquadService.leave(player) end)

workspace:SetAttribute("GF_ObjectiveComplete", false)
workspace:SetAttribute("GF_ExtractionState", "idle")
workspace:SetAttribute("BastionActive", false)
workspace:SetAttribute("VeyrActive", false)
workspace:SetAttribute("BossHealth", 0)
workspace:SetAttribute("BossPhase", 1)
-- The cloud place once carried a saved root-level Bastion artifact into non-boss missions. Boot
-- must never trust untagged workspace residue; elimination objectives retag legitimate targets.
for _, child in ipairs(workspace:GetChildren()) do
	if child:IsA("Model") and child:GetAttribute("Boss") == true and child:GetAttribute("GF_ObjectiveTarget") ~= true then
		child:Destroy()
	end
end
workspace:SetAttribute("GF_MissionSeed", 1234)
-- S07-014 generation provenance: deterministic server seed with explicit generator version —
-- same seed + version reproduces the same world, which is what makes verification possible.
local GENERATOR_VERSION = "1.4"
workspace:SetAttribute("GF_GeneratorVersion", GENERATOR_VERSION)

-- No operation exists while the player is still in the orbital station. A boot-time Normal mission
-- context here made lobby deaths/extraction logic behave as if an operation were already active and
-- poisoned the first ticket count published after deploy.
workspace:SetAttribute("GF_ReinforcementTickets", 0)

require(Services.ProfileService).start()
LootService.start()
ObjectiveService.start()
require(Services.BoundaryService).start()
require(Services.PerformanceTelemetry).start()

-- S08-006 mission timer: 15 minute default guidance — a pacing reference for the squad, never a
-- forced playtime floor. Missions end by objective resolution, not by the clock.
task.spawn(function()
	local MISSION_TIMER = 15 * 60
	local startedAt = os.clock()
	workspace:SetAttribute("GF_MissionTimerDuration", MISSION_TIMER)
	while true do
		task.wait(1)
		local elapsed = os.clock() - startedAt
		workspace:SetAttribute("GF_MissionTimer", math.max(0, MISSION_TIMER - elapsed))
	end
end)
ExtractionService.start()
local DownedService = require(Services.DownedService)
DownedService.start()
require(Services.AppearanceService).start()
-- Phase 2 world: seeded terrain first, then all dressing sits on it.
local TerrainService = require(Services.TerrainService)
-- Battlefield mode (GF_BattlefieldGen): anchors come from the generated plan — LZ/primary
-- are feature-placed nodes hundreds of studs apart; legacy mode keeps the compact layout.
-- registerFlat calls below only affect the legacy sampler (battlefield build drops them).
local BF_LZ = Vector3.new(0, 0, -120)
local BF_OBJ = Vector3.new(0, 0, 120)
do
	local bfOn = workspace:GetAttribute("GF_BattlefieldGen") == true
	if bfOn then
		-- TerrainService.build hasn't run yet; plan nodes are only knowable after build, so the
		-- flats are registered inside the battlefield build path itself. Here we pre-compute
		-- nothing — anchors finalize after build below.
	end
end
TerrainService.registerFlat(Vector3.new(0, 0, -120), 74)
TerrainService.registerFlat(Vector3.new(0, 0, 120), 52)
TerrainService.registerFlat(Vector3.new(74, 0, -54), 44)
TerrainService.registerFlat(Vector3.new(-78, 0, -152), 44)
TerrainService.registerFlat(Vector3.new(38, 0, 26), 34)
-- S07-006: multiple map seeds per biome — the seed rotates per mission instance instead of the fixed
-- 1234 every deploy. Seeds are published so clients/probes can verify rotation across missions.
-- Phase 15: biome is chosen BEFORE terrain/vegetation build so ecology and palette can follow it.
local biomes = { "Forest", "Arid", "Tundra", "Industrial" } -- Phase 15: four approved biomes (Volcanic retired)
local biomeIdx = ((workspace:GetAttribute("GF_MissionCount") or 0)) % #biomes + 1
local biome = biomes[biomeIdx]
workspace:SetAttribute("GF_Biome", biome)
local missionSeed = math.floor(os.clock() * 1000) % 100000 + math.random(1, 9999)
workspace:SetAttribute("GF_MapSeed", missionSeed)
local columns = TerrainService.build(missionSeed)
print("[GF] terrain columns: " .. columns)
-- S07-009: nonhostile alien wildlife at the mission site — 3 ambient creatures that flee gunfire.
local WildlifeService = require(Services.WildlifeService)
WildlifeService.clear()
WildlifeService.spawnForSite(Vector3.new(0, 0, -120), 3)
WildlifeService.start()
-- S07-011: biome-appropriate weather with gradual transitions.
local WeatherService = require(Services.WeatherService)
WeatherService.start()
-- S07-004: biome selection per mission — rotates across the four launch biome kits.
WeatherService.setBiome(biome)
-- S07-012: auto sliding doors at the outpost entries — valid collisions open and closed.
local DoorService = require(Services.DoorService)
DoorService.registerDoor(Vector3.new(0, 3, -120 + 30))
DoorService.registerDoor(Vector3.new(14, 3, -120 + 22))
DoorService.start()

-- S07-008 human remnants: the war predates the squad — scattered cargo, a downed ship hull, and an
-- emergency beacon tell that story without a word of text. Alien conduits mark their installations.
do
	local function prop(name, size, pos, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = true
		p.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad((pos.X * 7 + pos.Z * 13) % 360), 0)
		p.Parent = workspace
		return p
	end
	-- cargo scatter: crashed supply crates along the approach
	for i = 1, 6 do
		local angle = math.rad(i * 61)
		prop("HumanCargo", Vector3.new(2.4, 1.8, 2.4), Vector3.new(math.cos(angle) * (30 + i * 8), 1, -60 + math.sin(angle) * 40), Color3.fromRGB(110, 100, 80), Enum.Material.Metal)
	end
	-- downed ship: a hull fragment half-buried off the main path
	local hull = prop("DownedShipHull", Vector3.new(18, 6, 8), Vector3.new(-70, 2, -60), Color3.fromRGB(70, 76, 86), Enum.Material.Metal)
	hull.CFrame = hull.CFrame * CFrame.Angles(math.rad(6), math.rad(40), math.rad(-9))
	-- emergency beacon: still blinking after the crash — survivors didn't make it
	local beacon = prop("EmergencyBeacon", Vector3.new(0.8, 5, 0.8), Vector3.new(-64, 2.5, -54), Color3.fromRGB(255, 80, 60), Enum.Material.Neon)
	task.spawn(function()
		while beacon.Parent do
			beacon.Transparency = 0.1
			task.wait(0.7)
			beacon.Transparency = 0.75
			task.wait(0.7)
		end
	end)
	-- alien conduits: angular channels running toward the relay installation
	for i = 1, 4 do
		local conduit = prop("AlienConduit", Vector3.new(1.4, 1.4, 14), Vector3.new(-20 + i * 9, 0.8, -100 + i * 3), Color3.fromRGB(60, 50, 80), Enum.Material.SmoothPlastic)
		conduit.CFrame = conduit.CFrame * CFrame.Angles(0, math.rad(70), 0)
	end
	-- S07-010 ambient: distant moons in the skybox sphere range and smoke columns on the horizon
	for i, offset in ipairs({ Vector3.new(400, 260, -500), Vector3.new(-450, 300, -350) }) do
		local moon = prop("DistantMoon", Vector3.new(40 + i * 18, 40 + i * 18, 40 + i * 18), offset, Color3.fromRGB(200 - i * 30, 200 - i * 20, 220), Enum.Material.SmoothPlastic)
		moon.Shape = Enum.PartType.Ball
		moon.CanCollide = false
	end
	for i = 1, 3 do
		local smoke = prop("SmokeColumn", Vector3.new(4, 60 + i * 20, 4), Vector3.new(150 - i * 90, 30, -300 - i * 40), Color3.fromRGB(60, 58, 56), Enum.Material.SmoothPlastic)
		smoke.Transparency = 0.6
		smoke.CanCollide = false
	end
end
-- S07-013: destructible small cover around the mission site — low walls that break under fire,
-- updating LOS/nav for both sides, capped pooled debris, zero persistent physics.
local CoverService = require(Services.DestructibleCoverService)
for i = 1, 8 do
	local angle = math.rad(i * 45)
	local wall = Instance.new("Part")
	wall.Size = Vector3.new(5, 3, 1)
	wall.Color = Color3.fromRGB(110, 100, 90)
	wall.Material = Enum.Material.Concrete
	wall.Anchored = true
	wall.CanCollide = true
	local radius = 26 + (i % 2) * 10
	wall.CFrame = CFrame.new(Vector3.new(math.cos(angle) * radius, 1.5, -120 + math.sin(angle) * radius)) * CFrame.Angles(0, angle, 0)
	wall.Parent = workspace
	CoverService.registerPiece(wall, 90)
end
-- Finalize mission anchors: battlefield mode substitutes plan nodes (lz/primary) for the
-- legacy compact positions; every downstream consumer receives the scaled coordinates.
local lzAnchor = Vector3.new(0, 0, -120)
local objAnchor = Vector3.new(0, 0, 120)
do
	local plan = TerrainService.currentPlan
	if workspace:GetAttribute("GF_BattlefieldGen") == true and plan and plan.nodes then
		lzAnchor = Vector3.new(plan.nodes.lz.x, 0, plan.nodes.lz.z)
		objAnchor = Vector3.new(plan.nodes.primary.x, 0, plan.nodes.primary.z)
		workspace:SetAttribute("GF_BFObjectiveX", objAnchor.X)
		workspace:SetAttribute("GF_BFObjectiveZ", objAnchor.Z)
		print(string.format("[GF] battlefield anchors: lz=(%.0f,%.0f) objective=(%.0f,%.0f) separation=%.0f",
			lzAnchor.X, lzAnchor.Z, objAnchor.X, objAnchor.Z,
			math.sqrt((objAnchor.X - lzAnchor.X)^2 + (objAnchor.Z - lzAnchor.Z)^2)))
	end
end
-- NOTE: legacy layout has the objective/relay at z=-120 and player LZ/spawn at z=+120
-- (MISSION_SPAWN=(0,8,118)); WorldDressing.build(relayPos, spawnPos) and
-- ObjectiveService.setup(relayPos) both key off the OBJECTIVE first. Plan mapping:
-- primary -> relay/objective anchor, lz -> spawn anchor.
ObjectiveService.setup(objAnchor)
local dressed = require(Services.WorldDressing).build(objAnchor, lzAnchor)
print("[GF] world dressing parts: " .. dressed)
do
	local missionState = require(Services.State).getMission()
	workspace:SetAttribute("GF_Difficulty", (missionState and missionState.difficulty) or "Normal")
end
require(Services.TelemetryService).start()
require(Services.TeleportFlowService).start()
require(Services.MatchmakingService).start()
require(Services.BossReplayService).start()
EncounterDirector.beginMission()

-- Extraction pressure begins the moment the squad calls the transport.
task.spawn(function()
	while true do
		task.wait(1)
		if ExtractionService.isCalled() then
			EncounterDirector.startExtractionPressure()
			break
		end
	end
end)

print(string.format("[GF] mission online: %d hostiles, objective + extraction + loot", EncounterDirector.stats().active))


