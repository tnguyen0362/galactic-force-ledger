--!strict
-- Mission controller: wires services for a single generated operation.

-- place-split role gate: when the split is LIVE and this server is provably the LOBBY
-- place, generating a mission world here is pure cost — 5000 studs of terrain, thousands
-- of vegetation instances, encounter director, the whole memory footprint the split
-- exists to avoid. detection: the lobby knows the mission place id, and it is not this
-- place. in every other configuration (split flag off, ids unconfigured, direct Studio
-- run) the legacy shared-place behavior is preserved exactly.
do
	local splitLive = workspace:GetAttribute("GF_PlaceSplitLive") == true
	local missionPlaceId = workspace:GetAttribute("GF_MissionPlaceId")
	if splitLive and type(missionPlaceId) == "number" and missionPlaceId ~= game.PlaceId then
		print("[GF] lobby place detected (split live) — mission world generation skipped")
		-- the gate skips WORLD generation only. the player-facing half of this script is still the
		-- lobby's: StationService.start wires the deploy/squad-browser remotes, prompts and zone
		-- tracking (Main's 6s fallback only calls build(), which makes geometry with no handlers),
		-- AppearanceService dresses the armor kit, SquadService seats players. without these the
		-- lobby had no armor and nothing interactive (owner report 2026-11-27).
		local LobbyPlayers = game:GetService("Players")
		local LobbyServices = script.Parent:WaitForChild("Services")
		local function lobbyStart(label: string, fn: () -> ())
			local ok, err = pcall(fn)
			if not ok then
				warn("[GF] lobby boot: " .. label .. " failed: " .. tostring(err))
			end
		end
		lobbyStart("StationService", function()
			require(LobbyServices.StationService).start()
		end)
		lobbyStart("AppearanceService", function()
			require(LobbyServices.AppearanceService).start()
		end)
		lobbyStart("SquadService", function()
			local LobbySquad = require(LobbyServices.SquadService)
			local function hook(player: Player)
				LobbySquad.join(player)
				player.CharacterAdded:Connect(function() LobbySquad.join(player) end)
			end
			LobbyPlayers.PlayerAdded:Connect(hook)
			for _, player in LobbyPlayers:GetPlayers() do
				hook(player)
			end
			LobbyPlayers.PlayerRemoving:Connect(function(player) LobbySquad.leave(player) end)
		end)
		return
	end
end

-- mission-place arrival control (owner report: "the world generates above you"): requiring
-- MissionServerInit starts the hold AT MODULE EVALUATION — players are cargo above the write
-- volume until terrain is verified, then landed on raycast ground. require-only integration:
-- generation stays on TerrainService.build below; the orchestrator watches GF_TerrainReady.
-- mission-place only — in any other configuration this script's legacy flow is untouched.
do
	local lobbyId = workspace:GetAttribute("GF_LobbyPlaceId")
	local missionId = workspace:GetAttribute("GF_MissionPlaceId")
	local amMissionPlace = (type(lobbyId) == "number" and lobbyId ~= game.PlaceId)
		or (type(missionId) == "number" and missionId == game.PlaceId)
	if amMissionPlace then
		local ok, err = pcall(function()
			require(script.Parent:WaitForChild("MissionServer").MissionServerInit)
		end)
		if not ok then warn("[GF] arrival control failed to start: " .. tostring(err)) end
	end
end

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

-- Memory directive (owner 2026-11-28): the place carries a 5000-stud terrain + thousands of
-- vegetation instances, and nothing anywhere enabled streaming — every client downloaded and
-- held the entire world (measured 3.4GB+ in Studio before generation even ran). Streaming is
-- mandatory for the Counteroffensive player counts. Set at the earliest boot line so it applies
-- before clients finish joining; radii bias large because sightlines matter in a shooter, but
-- bounded so low-end devices actually shed memory. Persistent models (objective/extraction/
-- enemies) replicate regardless of distance where the gameplay contract demands it.
pcall(function()
	workspace.StreamingEnabled = true
	workspace.StreamingMinRadius = 512
	workspace.StreamingTargetRadius = 1024
	workspace.StreamingPauseMode = Enum.StreamingPauseMode.Default
	print("Streaming: enabled min=512 target=1024 (memory directive)")
end)

require(Services.ProfileService).start()
LootService.start()
ObjectiveService.start()
require(Services.BoundaryService).start()
require(Services.PerformanceTelemetry).start()

-- ---------------------------------------------------------------------------
-- PLACE-SPLIT BOOTSTRAP (the mission side of the deploy contract).
-- when this server is a mission-place instance, the squad's intent arrives in the first
-- player's join data: seed, template, difficulty, squad roster, lobby return address,
-- and the war operation/region bindings. generation must not begin before the contract
-- is read — the seed IS the world. fallback after timeout: self-generated intent, so a
-- direct Studio run of this place still boots a playable mission.
-- ---------------------------------------------------------------------------
local DeployContract = require(game:GetService("ReplicatedStorage").GF.Shared.DeployContract)
local contractIntent: any = nil
do
	-- place-role detection: either direction of the id pair proves the split
	local lobbyId = workspace:GetAttribute("GF_LobbyPlaceId")
	local missionId = workspace:GetAttribute("GF_MissionPlaceId")
	local amMissionPlace = (type(lobbyId) == "number" and lobbyId ~= game.PlaceId)
		or (type(missionId) == "number" and missionId == game.PlaceId)
	if amMissionPlace then
		workspace:SetAttribute("GF_AmMissionPlace", true)
		local arrived = false
		local function tryRead(player: Player)
			if arrived then return end
			local intent = DeployContract.fromPlayer(player)
			if intent then
				arrived = true
				contractIntent = intent
				print(string.format("[GF] deploy contract received: template=%s difficulty=%s seed=%s squad=%d",
					tostring(intent.template), tostring(intent.difficulty), tostring(intent.seed),
					type(intent.squadUserIds) == "table" and #intent.squadUserIds or 0))
			end
		end
		-- players already present beat the PlayerAdded hook (server exists because they teleported)
		for _, plr in ipairs(Players:GetPlayers()) do
			tryRead(plr)
		end
		local conn
		conn = Players.PlayerAdded:Connect(function(plr)
			tryRead(plr)
			if arrived and conn then conn:Disconnect() end
		end)
		-- bounded wait: generation cannot stall forever on a missing/late contract
		local tWait = os.clock()
		while not arrived and os.clock() - tWait < 10 do
			task.wait(0.25)
		end
		if conn then conn:Disconnect() end
		if not arrived then
			warn("[GF] no deploy contract within 10s — falling back to self-generated intent (Studio/direct-run path)")
		end
		-- the contract's lobby address is authoritative for return teleports; the Studio-set
		-- attribute is only a fallback when no contract exists (direct-run)
		if contractIntent and type(contractIntent.lobbyPlaceId) == "number" then
			workspace:SetAttribute("GF_LobbyPlaceId", contractIntent.lobbyPlaceId)
		end
		-- war bindings: contribution crediting at primary completion reads these exact tags
		if contractIntent then
			if type(contractIntent.operationId) == "string" and contractIntent.operationId ~= "" then
				workspace:SetAttribute("GF_OperationId", contractIntent.operationId)
			end
			if type(contractIntent.regionId) == "string" and contractIntent.regionId ~= "" then
				workspace:SetAttribute("GF_RegionId", contractIntent.regionId)
			end
		end
	end
end

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
local biomes = { "Forest", "Arid", "Tundra", "Industrial", "Jungle" } -- Phase 15 + Jungle (owner directive 2026-11-28)
-- owner directive 2026-11-28: everything is jungle — rotation suspended, biome pinned
local biome = "Jungle"
workspace:SetAttribute("GF_Biome", biome)
-- The mission place never ran Environment.apply("mission") (only the lobby's deploy path did), so the
-- biome look (Jungle haze/grade/terrain palette) was never written and the place file's cold grey
-- lighting showed through. Apply it now; WeatherService below snapshots it as its baseline.
do
	local okEnv, errEnv = pcall(function()
		require(Services.Environment).apply("mission")
	end)
	if not okEnv then
		warn("[GF] Environment.apply(mission) failed: " .. tostring(errEnv))
	end
end
local missionSeed = (contractIntent and type(contractIntent.seed) == "number" and contractIntent.seed)
	or (os.time() * 997 + math.floor(os.clock() * 1000) + math.random(1, 99999)) % 900000 + 1
workspace:SetAttribute("GF_MapSeed", missionSeed)
if contractIntent then
	print("[GF] world generation driven by contract seed " .. tostring(missionSeed))
end
local columns = TerrainService.build(missionSeed)
-- Runtime geographical generation is now the default terrain path (owner directive 2026-11-28):
-- generation dispatches async inside build() and takes ~7-20s behind the loading window. Every
-- mission-world construction below grounds objects by raycast, so it must not run before the
-- terrain exists. Baked/fallback paths set GF_TerrainReady near-instantly, so this wait is a
-- no-op there; the timeout guarantees boot can never hang even if generation is killed.
do
	local tWait = os.clock()
	while workspace:GetAttribute("GF_TerrainReady") ~= true and os.clock() - tWait < 35 do
		task.wait(0.25)
	end
	if workspace:GetAttribute("GF_TerrainReady") ~= true then
		warn("Mission: terrain not ready after 35s — proceeding anyway (generation failure?)")
	end
end
print("[GF] terrain columns: " .. columns)

-- place-split: when THIS place is the mission place (lobby id set and differs), players arrive
-- by teleport while generation may still be finishing. Position them at the LZ once the world
-- is ready; the lobby's spawn brick doesn't exist here so the default spawn is their holding pen.
do
	local lobbyId = workspace:GetAttribute("GF_LobbyPlaceId")
	if type(lobbyId) == "number" and lobbyId ~= game.PlaceId then
		workspace:SetAttribute("GF_AmMissionPlace", true)
		-- legacy sky-drop positioning removed: MissionServerInit owns arrival (held cargo ->
		-- ground-truthed LZ). keeping this path active raced the orchestrator and dropped players
		-- into half-written terrain.
		do end
		print("[GF] mission-place boot mode active")
	end
end
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
		-- generated geography: fixed legacy Y buries props in slopes or floats them in air
		-- (authored for the flat baked site). Ground to terrain by raycast; sky dressing keeps altitude.
		local grounded = pos
		if name ~= "DistantMoon" and name ~= "SmokeColumn" then
			local hit = workspace:Raycast(Vector3.new(pos.X, 800, pos.Z), Vector3.new(0, -1000, 0))
			if hit then
				grounded = Vector3.new(pos.X, hit.Position.Y + size.Y * 0.5 - 0.5, pos.Z)
			end
		end
		p.CFrame = CFrame.new(grounded) * CFrame.Angles(0, math.rad((pos.X * 7 + pos.Z * 13) % 360), 0)
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
-- Legacy compact layout: objective/relay at z=-120, drop zone at z=+120 (MISSION_SPAWN=(0,8,118)).
-- These were swapped, which put the objective directly on the landing zone. Generated geography
-- publishes GF_Anchor* (TerrainService) and wins over the legacy points.
local lzAnchor = Vector3.new(0, 0, 120)
local objAnchor = Vector3.new(0, 0, -120)
do
	local aLZ = workspace:GetAttribute("GF_AnchorLZ")
	local aObj = workspace:GetAttribute("GF_AnchorObjective")
	if typeof(aLZ) == "Vector3" and typeof(aObj) == "Vector3" then
		lzAnchor = Vector3.new(aLZ.X, 0, aLZ.Z)
		objAnchor = Vector3.new(aObj.X, 0, aObj.Z)
		print(string.format("[GF] terrain-analysis anchors: lz=(%.0f,%.0f) objective=(%.0f,%.0f)",
			lzAnchor.X, lzAnchor.Z, objAnchor.X, objAnchor.Z))
	end
end
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
-- contract-driven mission identity: template selects the objective mechanics, difficulty
-- scales everything downstream. both publish as attributes AND mission context so every
-- consumer (legacy and contract-aware) reads the same truth.
local missionTemplate = (contractIntent and type(contractIntent.template) == "string" and contractIntent.template)
	or "SABOTAGE_RELAY"
local missionDifficulty = (contractIntent and type(contractIntent.difficulty) == "string" and contractIntent.difficulty)
	or "Normal"
workspace:SetAttribute("GF_OperationTemplate", missionTemplate)
workspace:SetAttribute("GF_OperationDifficulty", missionDifficulty)
do
	local State = require(Services.State)
	if not State.getMission() then
		State.setMission({
			seed = missionSeed,
			difficulty = missionDifficulty,
			tickets = 0,
			startedAt = os.time(),
			softDeadline = os.time() + 15 * 60,
			objectiveComplete = false,
			extractionCalled = false,
		})
	end
end
ObjectiveService.setup(objAnchor, missionTemplate)
local dressed = require(Services.WorldDressing).build(objAnchor, lzAnchor)
print("[GF] world dressing parts: " .. dressed)
do
	local missionState = require(Services.State).getMission()
	workspace:SetAttribute("GF_Difficulty", (missionState and missionState.difficulty) or missionDifficulty)
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


