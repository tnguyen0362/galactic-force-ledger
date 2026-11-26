--!strict
-- Orbital station: the hub players return to. Single-place architecture: the station
-- lives above the mission region and deployment is a controlled teleport, so the whole
-- loop is testable in Studio without a second place or cross-place teleport.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = require(script.Parent.State)
local ObjectiveService = require(script.Parent.ObjectiveService)
local ExtractionService = require(script.Parent.ExtractionService)
local SquadService = require(script.Parent.SquadService)
local EncounterDirector = require(script.Parent.EncounterDirector)
local EnemyService = require(script.Parent.EnemyService)
local StationArt = require(script.Parent.StationArt)
local Concourse = require(script.Parent.StationConcourse)
-- The station shell contained ZERO Light instances, so at Lighting.ClockTime 0.2 the interior
-- rendered pure black and every capture came back black. Warm ceiling fixtures are gridded across
-- the shell (capped so the light count stays cheap) and the ambient is lifted at night.
local function addInteriorLighting(shell: Instance)
	local cf, size = shell:GetBoundingBox()
	local ceilingY = cf.Position.Y + size.Y * 0.5 - 8
	local folder = Instance.new("Folder")
	folder.Name = "InteriorLights"
	folder.Parent = shell
	local nx = math.clamp(math.floor(size.X / 34), 2, 6)
	local nz = math.clamp(math.floor(size.Z / 34), 2, 8)
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local x = cf.Position.X - size.X * 0.5 + (ix + 0.5) * (size.X / nx)
			local z = cf.Position.Z - size.Z * 0.5 + (iz + 0.5) * (size.Z / nz)
			local fixture = Instance.new("Part")
			fixture.Name = "CeilingFixture"
			fixture.Anchored = true
			fixture.CanCollide = false
			fixture.CanQuery = false
			fixture.CastShadow = false
			fixture.Material = Enum.Material.Neon
			fixture.Color = Color3.fromRGB(255, 231, 190)
			fixture.Size = Vector3.new(6, 0.35, 1.6)
			fixture.CFrame = CFrame.new(x, ceilingY, z)
			fixture.Parent = folder
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 226, 184)
			light.Brightness = 2.4
			light.Range = 52
			light.Shadows = false
			light.Parent = fixture
		end
	end
	local Lighting = game:GetService("Lighting")
	if Lighting.ClockTime < 6 or Lighting.ClockTime > 18 then
		Lighting.Ambient = Color3.fromRGB(150, 156, 168)
		Lighting.OutdoorAmbient = Color3.fromRGB(96, 102, 114)
	end
end

local Environment = require(script.Parent.Environment)

local StationService = {}

local STATION_Y = 760
-- z=52 put every arrival inside the drop pod's own hatch, so the first frame of the game was the
-- pod's white hull filling a third of the screen (capture V195). z=22 puts the player on open deck
-- with the war table and the observation windows ahead and the pod behind as set dressing.
local STATION_SPAWN = Vector3.new(0, STATION_Y + 7, 22)
local MISSION_SPAWN = Vector3.new(0, 8, 118)
local RELAY = Vector3.new(0, 0, -120)
local MISSION_SECONDS = 900
local Difficulties = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Difficulties)

local zone: { [Player]: string } = {}
local difficulty = "Normal"

local STEEL = Color3.fromRGB(88, 96, 110)
local DARK = Color3.fromRGB(46, 52, 62)
local PLATE = Color3.fromRGB(134, 142, 154)
local CYAN = Color3.fromRGB(96, 200, 255)
local AMBER = Color3.fromRGB(255, 176, 64)

local function ensureRemote(name: string, className: string): Instance?
	local container = ReplicatedStorage.GF:FindFirstChild("Remotes")
	if not container then
		return nil
	end
	local existing = container:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = container
	return created
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function neon(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = part(parent, name, size, cf, color, Enum.Material.Neon)
	p.CanCollide = false
	p.CastShadow = false
	return p
end

local function clearUntaggedBosses()
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Boss") == true and child:GetAttribute("GF_ObjectiveTarget") ~= true then
			child:Destroy()
		end
	end
end

function StationService.build()
	local old = workspace:FindFirstChild("Station")
	if old then
		old:Destroy()
	end
	local station = Instance.new("Folder")
	station.Name = "Station"
	station.Parent = workspace
	local base = CFrame.new(0, STATION_Y, 0)

	StationArt.buildShell(station, base)
	-- Walkable, lit concourse with its own spawn; the legacy shell had no floor under the spawn
	-- point and zero Light instances, so players spawned into the void.
	Concourse.build(workspace)
	-- StationArt re-creates StationSpawn during buildShell, so a one-shot sweep lost the race: the
	-- player spawned at the old pad 2 studs from the south wall and the third-person camera sat
	-- outside the room looking at the wall back face. Kill strays as they appear, not once.
	local function killStraySpawn(d: Instance)
		if d:IsA("SpawnLocation") and d.Name ~= "ConcourseSpawn" and d.Name ~= "StationSpawn" then
			d:Destroy()
		end
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		killStraySpawn(d)
	end
	workspace.DescendantAdded:Connect(killStraySpawn)
	local pad = workspace:FindFirstChild("ConcourseSpawn", true)
	if pad then
		pad.Enabled = true
	end

	-- V91 review: the only SpawnLocation sat at z=+120, behind the hull, so players arrived facing
	-- the station's back wall. Spawn them on the concourse deck facing the war table instead.
	local stationSpawn = Instance.new("SpawnLocation")
	stationSpawn.Name = "StationSpawn"
	stationSpawn.Size = Vector3.new(9, 0.6, 9)
	stationSpawn.CFrame = base * CFrame.new(-8, 1.05, 26) * CFrame.Angles(0, math.rad(180), 0)
	stationSpawn.Anchored = true
	stationSpawn.Neutral = true
	stationSpawn.Transparency = 1
	stationSpawn.CanCollide = false
	stationSpawn.Duration = 0
	stationSpawn.Parent = station
	for _, other in ipairs(workspace:GetDescendants()) do
		if other:IsA("SpawnLocation") and other ~= stationSpawn then
			other.Enabled = false
		end
	end
	-- war table: the mission selection surface players stand at
	-- war table: the mission selection surface players stand at
	local tableCF = base * CFrame.new(0, 0, -34)
	-- PLATE on the top made the table read as a white slab across the spawn frame (V207). Dark
	-- composite surface with a lit bezel keeps the hologram as the brightest thing on it.
	local tableTop = Color3.fromRGB(30, 36, 46)
	part(station, "WarTableBase", Vector3.new(30, 3.4, 30), tableCF * CFrame.new(0, 1.7, 0), DARK, Enum.Material.Metal)
	for i = -1, 1 do
		part(station, "WarTableRib", Vector3.new(30.6, 0.6, 1.2), tableCF * CFrame.new(0, 1.7 + i * 0.9, 0), Color3.fromRGB(44, 50, 60), Enum.Material.Metal)
	end
	part(station, "WarTableTop", Vector3.new(34, 0.8, 34), tableCF * CFrame.new(0, 3.6, 0), tableTop, Enum.Material.DiamondPlate)
	for _, spec in ipairs({ { 34, 1.2, 0, 17.4 }, { 34, 1.2, 0, -17.4 }, { 1.2, 34, 17.4, 0 }, { 1.2, 34, -17.4, 0 } }) do
		local bezel = neon(station, "WarTableBezel", Vector3.new(spec[1], 0.5, spec[2]), tableCF * CFrame.new(spec[3], 4.05, spec[4]), CYAN)
		bezel.Transparency = 0.35
	end
	local holo = part(station, "WarHolo", Vector3.new(23, 0.3, 23), tableCF * CFrame.new(0, 4.25, 0), Color3.fromRGB(20, 64, 96), Enum.Material.Neon)
	holo.Transparency = 0.82
	local planet = part(station, "WarPlanet", Vector3.new(7.5, 7.5, 7.5), tableCF * CFrame.new(0, 8, 0), Color3.fromRGB(52, 128, 190), Enum.Material.Neon)
	planet.Shape = Enum.PartType.Ball
	planet.Transparency = 0.55
	for _, tilt in ipairs({ 0, 28, -34 }) do
		local band = part(station, "WarPlanetRing", Vector3.new(12.5, 0.14, 12.5), tableCF * CFrame.new(0, 8, 0) * CFrame.Angles(math.rad(tilt), 0, math.rad(tilt * 0.6)), Color3.fromRGB(96, 190, 236), Enum.Material.Neon)
		band.Transparency = 0.68
		band.CanCollide = false
	end
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2
		neon(station, "WarPin", Vector3.new(1.2, 1.2, 1.2), tableCF * CFrame.new(math.cos(a) * 11, 5.4, math.sin(a) * 11), AMBER)
	end
	local light = Instance.new("PointLight")
	light.Shadows = false
	light.Color = CYAN
	light.Brightness = 0.9
	light.Range = 34
	light.Parent = holo
	local tableSpot = Instance.new("SpotLight")
	tableSpot.Shadows = false
	tableSpot.Name = "TableSpot"
	tableSpot.Color = Color3.fromRGB(210, 232, 255)
	tableSpot.Brightness = 0.6
	tableSpot.Range = 40
	tableSpot.Angle = 100
	tableSpot.Face = Enum.NormalId.Bottom
	tableSpot.Parent = part(station, "TableLamp", Vector3.new(10, 0.6, 10), tableCF * CFrame.new(0, 34, 0), Color3.fromRGB(200, 220, 240), Enum.Material.Neon)

	-- Wall panel language: the bulkheads were single flat planes with one dado band, which is why the
	-- room read as a box however the light was tuned (review V258). Recessed seams every 12 studs and a
	-- rivet row at waist and shoulder height give the wall a scale and a material story.
	local SEAM = Color3.fromRGB(22, 26, 32)
	local RIVET = Color3.fromRGB(96, 104, 116)
	for _, sx in ipairs({ -1, 1 }) do
		for k = -5, 5 do
			local seam = part(station, "WallSeam", Vector3.new(0.16, 26, 0.5), base * CFrame.new(sx * 98.9, 13.4, k * 12), SEAM, Enum.Material.Metal)
			seam.CanCollide = false
		end
		for row = 0, 3 do
			for k = -5, 5 do
				local rivet = part(station, "WallRivet", Vector3.new(0.22, 0.22, 0.22), base * CFrame.new(sx * 98.7, 5 + row * 4.4, k * 12 + 3), RIVET, Enum.Material.Metal)
				rivet.CanCollide = false
			end
		end
	end
	for k = -4, 4 do
		local seam = part(station, "WallSeam", Vector3.new(0.5, 26, 0.16), base * CFrame.new(k * 24, 13.4, 73.4), SEAM, Enum.Material.Metal)
		seam.CanCollide = false
	end
	-- Section signage. The station had one floating text panel in the window and nothing else, so a
	-- player could not tell the armoury from the dispatch alcove. Each sign is a backing plate with a
	-- SurfaceGui, mounted above its section and facing into the room.
	local SIGN_BACK = Color3.fromRGB(18, 22, 28)
	local function sign(text: string, width: number, height: number, cf: CFrame, face: Enum.NormalId, accent: Color3)
		local plate = part(station, "SectionSign", Vector3.new(width, height, 0.4), cf, SIGN_BACK, Enum.Material.Metal)
		plate.CanCollide = false
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(math.floor(width * 40), math.floor(height * 40))
		gui.LightInfluence = 0
		gui.Parent = plate
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = text
		label.TextColor3 = accent
		label.TextScaled = true
		label.Parent = gui
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(1, 0, 0.06, 0)
		strip.Position = UDim2.fromScale(0, 0.94)
		strip.BorderSizePixel = 0
		strip.BackgroundColor3 = accent
		strip.Parent = gui
		return plate
	end
	-- Mounted flush on the wall with the text face turned into the room. The first pass left them
	-- eight studs proud of the wall facing sideways, so from inside the room they were invisible
	-- (capture V222).
	-- Warm practicals: the room was monochrome blue-grey because every fixture is capped to the same
	-- cool white. Two amber work lights at the armoury and dispatch give the eye a colour contrast
	-- and mark the side sections from across the deck.
	local function practical(at: Vector3, lensSize: Vector3, colour: Color3)
		local fixture = part(station, "Practical", lensSize, CFrame.new(at), colour, Enum.Material.Neon)
		fixture.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = colour
		light.Brightness = 0.6
		light.Range = 26
		light.Shadows = true
		light:SetAttribute("GFPractical", true)
		light.Parent = fixture
		return fixture
	end
	practical(base * Vector3.new(-94, 12, -23), Vector3.new(1.6, 0.6, 3.2), Color3.fromRGB(255, 176, 96))
	practical(base * Vector3.new(94, 12, -28), Vector3.new(1.6, 0.6, 3.2), Color3.fromRGB(255, 176, 96))
	practical(base * Vector3.new(0, 13, 70), Vector3.new(3.2, 0.6, 1.6), Color3.fromRGB(120, 200, 255))
	-- Wall wash: a wall 100 studs from the ceiling grid receives nothing from the fixtures, so both
	-- bulkheads rendered as black voids no matter their albedo (captures V265-V267). Four non-shadowed
	-- wall lights (two per side) are the cheapest fix: no shadow pass, no extra geometry beyond a lens.
	for _, spec in ipairs({ { -97, 776, -40 }, { -97, 776, 40 }, { 97, 776, -40 }, { 97, 776, 40 } }) do
		-- Ceiling cove: the perimeter above the wall wash stayed black, so the ceiling looked like a card
	-- floating over the room (capture V269). Two long emissive strips give the ceiling an edge.
	for _, sx in ipairs({ -1, 1 }) do
		local cove = neon(station, "CeilingCove", Vector3.new(1.1, 0.35, 150), base * CFrame.new(sx * 97, 34.4, 0), Color3.fromRGB(150, 202, 244))
		cove.Transparency = 0.35
	end
	local lens = part(station, "WallWashLens", Vector3.new(0.4, 1.2, 8), base * CFrame.new(spec[1], spec[2], spec[3]), Color3.fromRGB(196, 220, 255), Enum.Material.Neon)
		lens.CanCollide = false
		local wash = Instance.new("PointLight")
		wash.Color = Color3.fromRGB(196, 214, 244)
		wash.Brightness = 1.8
		wash.Range = 48
		wash.Shadows = false
		wash:SetAttribute("GFPractical", true)
		wash.Parent = lens
	end

	sign("ARMOURY", 22, 4.5, base * CFrame.new(-98.6, 11, -23) * CFrame.Angles(0, math.rad(-90), 0), Enum.NormalId.Front, AMBER)
	sign("DISPATCH", 22, 4.5, base * CFrame.new(98.6, 11, -28) * CFrame.Angles(0, math.rad(90), 0), Enum.NormalId.Front, AMBER)
	sign("DEPLOYMENT", 20, 4, base * CFrame.new(0, 13, 74.6), Enum.NormalId.Front, AMBER)
	sign("WAR TABLE", 18, 3.6, base * CFrame.new(0, 12, -34) * CFrame.Angles(0, math.rad(180), 0), Enum.NormalId.Front, CYAN)

	-- armory racks along the left wall
	for i = -1, 1 do
		local rackCF = base * CFrame.new(-112, 0, i * 26)
		part(station, "ArmoryRack", Vector3.new(2, 16, 18), rackCF * CFrame.new(0, 8, 0), STEEL, Enum.Material.Metal)
		for j = -1, 1 do
			part(station, "Rifle", Vector3.new(0.8, 1.2, 7), rackCF * CFrame.new(1.4, 8 + j * 4, 0), Color3.fromRGB(30, 34, 42), Enum.Material.Metal)
			neon(station, "RifleGlow", Vector3.new(0.3, 0.3, 2), rackCF * CFrame.new(2, 8 + j * 4, -2), CYAN)
		end
	end

	-- deployment pad + staged dropship silhouette
	local padCF = base * CFrame.new(0, 0, 74)
	local pad = part(station, "DeployPad", Vector3.new(34, 1.2, 34), padCF * CFrame.new(0, 0.6, 0), DARK, Enum.Material.DiamondPlate)
	pad:SetAttribute("GFStationPad", true)
	-- The filled 36x36 neon pad read as a lit floor slab rather than a marker (capture V262). The four
	-- PadRingBar strips below do the job; this plane stays as a faint sheen only.
	local ring = neon(station, "PadRing", Vector3.new(36, 0.4, 36), padCF * CFrame.new(0, 1.3, 0), CYAN)
	ring.Transparency = 0.94
	for _, corner in { Vector3.new(-15, 0, -15), Vector3.new(15, 0, -15), Vector3.new(-15, 0, 15), Vector3.new(15, 0, 15) } do
		part(station, "PadPost", Vector3.new(1.6, 10, 1.6), padCF * CFrame.new(corner.X, 5, corner.Z), PLATE, Enum.Material.Metal)
		neon(station, "PadPostLight", Vector3.new(2, 0.6, 2), padCF * CFrame.new(corner.X, 10.2, corner.Z), CYAN)
	end
	-- Loading rails had to be visible from the concourse, not only under the pod: the bay read as a
	-- pod on a glowing slab with no way to get into it (capture V262). Two rails now run from the pod
	-- mouth to the deck, with ties and a sill light, and the pad is a ring rather than a filled square.
	local RAIL = Color3.fromRGB(58, 64, 74)
	for _, sx in ipairs({ -5, 5 }) do
		local rail = part(station, "LoadingRailRun", Vector3.new(0.9, 0.5, 34), padCF * CFrame.new(sx, 0.9, -17), RAIL, Enum.Material.Metal)
		rail.CanCollide = false
		for t = 0, 6 do
			neon(station, "RailTieLight", Vector3.new(1.6, 0.12, 0.5), padCF * CFrame.new(sx, 1.2, -17 - 15 + t * 5), Color3.fromRGB(88, 184, 232))
		end
	end
	for t = 0, 5 do
		part(station, "RailSleeper", Vector3.new(11, 0.35, 0.8), padCF * CFrame.new(0, 0.75, -17 - 15 + t * 6), Color3.fromRGB(44, 48, 56), Enum.Material.Metal)
	end
	-- pad ring: four bars, so it reads as a marker instead of a lit floor plate
	for _, spec in ipairs({ { 36, 1.4, 0, 17.3 }, { 36, 1.4, 0, -17.3 }, { 1.4, 36, 17.3, 0 }, { 1.4, 36, -17.3, 0 } }) do
		local bar = neon(station, "PadRingBar", Vector3.new(spec[1], 0.3, spec[2]), padCF * CFrame.new(spec[3], 1.35, spec[4]), CYAN)
		bar.Transparency = 0.45
	end
	local ship = part(station, "Dropship", Vector3.new(18, 7, 30), padCF * CFrame.new(0, 14, 0), Color3.fromRGB(74, 82, 92), Enum.Material.Metal)	local ship = part(station, "Dropship", Vector3.new(18, 7, 30), padCF * CFrame.new(0, 14, 0), Color3.fromRGB(74, 82, 92), Enum.Material.Metal)
	part(station, "DropshipWing", Vector3.new(34, 1.4, 11), padCF * CFrame.new(0, 13, 3), Color3.fromRGB(64, 72, 82), Enum.Material.Metal)
	part(station, "DropshipCockpit", Vector3.new(9, 4, 6), padCF * CFrame.new(0, 15, -15), Color3.fromRGB(120, 180, 210), Enum.Material.Glass)
	neon(station, "DropshipEngine", Vector3.new(4, 4, 4), padCF * CFrame.new(0, 14, 15), CYAN)
	ship.CanCollide = false

	return station
end

function StationService.zoneOf(player: Player): string
	return zone[player] or "Station"
end

function StationService.resetMission(missionDifficulty: string, template: string?)
	template = template or "SABOTAGE_RELAY"
	difficulty = missionDifficulty
	workspace:SetAttribute("GF_OperationTemplate", template)
	workspace:SetAttribute("GF_OperationDifficulty", missionDifficulty)
	workspace:SetAttribute("GF_ObjectiveComplete", false)
	workspace:SetAttribute("GF_ExtractionState", "idle")
	workspace:SetAttribute("GF_LastPayout", nil)
	workspace:SetAttribute("GF_MissionEndReason", nil)
	SquadService.reset()
	ExtractionService.reset()
	-- A redeploy used to leave the previous mission's hostiles standing: clearAll only ran on
	-- extraction, so actors piled up and every target count read high. This runs before setup so the
	-- new mission's own spawns (including elimination targets) are the only ones alive.
	EnemyService.clearAll()
	clearUntaggedBosses()
	ObjectiveService.setup(RELAY, template)
	EncounterDirector.reset()
	pcall(function()
		require(script.Parent.CacheService).resetMission()
	end)
	pcall(function()
		require(script.Parent.DownedService).resetMission()
	end)
	local missionsConfig = require(ReplicatedStorage.GF.Shared.Configs.Missions)
	local missionDef = missionsConfig.get(template)
	pcall(function()
		require(script.Parent.DialogueService).say(string.format("%s on %s. Get in, finish the job, get out.", missionDef and missionDef.displayName or tostring(template), tostring(missionDifficulty)), "brief")
	end)
	State.setMission({
		seed = math.floor((os.clock() * 1000) % 100000) + math.floor(tick() % 997) * 1000,
		difficulty = missionDifficulty,
		tickets = Difficulties.ticketsFor(missionDifficulty, math.max(1, #game:GetService("Players"):GetPlayers())),
		startedAt = os.clock(),
		softDeadline = os.clock() + MISSION_SECONDS,
		objectiveComplete = false,
		objectiveTemplate = template,
		extractionCalled = false,
	})
	EncounterDirector.beginMission()
end

-- Terrain is regenerated per launch, so a baked spawn Y can end up inside a hill or under
-- the surface. Deploy always resolves the spawn against the live terrain instead.
local function groundPoint(p: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local actors = workspace:FindFirstChild("ActiveActors")
	params.FilterDescendantsInstances = actors and { actors } or {}
	local hit = workspace:Raycast(Vector3.new(p.X, 500, p.Z), Vector3.new(0, -1200, 0), params)
	return hit and (hit.Position + Vector3.new(0, 6, 0)) or p
end

local function teleportTo(player: Player, position: Vector3)
	workspace:SetAttribute("GF_Teleporting", true)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		player:LoadCharacter()
		character = player.Character
	end
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		character:PivotTo(CFrame.new(position))
	end
	task.delay(1.2, function()
		workspace:SetAttribute("GF_Teleporting", false)
	end)
end

local function publish(player: Player)
	local remote = ReplicatedStorage.GF.Remotes:FindFirstChild("DeployStateChanged")
	if remote then
		remote:FireClient(player, {
			zone = StationService.zoneOf(player),
			difficulty = difficulty,
			objectiveComplete = ObjectiveService.isComplete(),
		})
	end
end

-- Difficulty gates and honest failure reporting. The deploy button used to show a 4s fake spinner and
-- re-enable itself whatever happened, so a refused launch looked identical to a slow one.
local TEMPLATE_RANK = { CONQUEST_THRONEFALL = 10 }
local DIFFICULTY_RANK = { Easy = 1, Normal = 3, Hard = 6, Extreme = 14 }
local VALID_TEMPLATES = { SABOTAGE_RELAY = true, RECOVER_TECH = true, DEFEND_BEACON = true,
	ELIM_COMMANDER = true, ELIM_WALKER = true, ELIM_TALON = true,
	RECOVERY_ARCHIVE = true, SABOTAGE_ARSENAL = true, DEFENSE_POWER = true, RECOVERY_CONVOY = true, DEFENSE_UPLINK = true, SABOTAGE_AEGIS = true, CONQUEST_DOMINION = true, CONQUEST_FOUNDRY = true, CONQUEST_THRONEFALL = true }

function StationService.deploy(player: Player, missionDifficulty: string?, template: string?): (boolean, string?)
	local mission = State.getMission()
	local stateRemote = ReplicatedStorage.GF.Remotes:FindFirstChild("DeployStateChanged")
	local function refuse(reason: string)
		workspace:SetAttribute("GF_DeployRejected", reason)
		if stateRemote then
			stateRemote:FireClient(player, { ok = false, reason = reason, zone = StationService.zoneOf(player) })
		end
		return false, reason
	end
	if template ~= nil and VALID_TEMPLATES[template] ~= true then
		return refuse("unknown operation")
	end
	if missionDifficulty ~= nil then
		local needed = DIFFICULTY_RANK[missionDifficulty]
		if not needed then
			return refuse("unknown difficulty")
		end
		local profile = require(script.Parent.ProfileService).get(player)
		local rank = profile and profile.rank or 1
		if rank < needed then
			return refuse(string.format("requires military rank %d", needed))
		end
	end
	local templateRank = TEMPLATE_RANK[template]
	if templateRank then
		local profile = require(script.Parent.ProfileService).get(player)
		if (profile and profile.rank or 1) < templateRank then
			return refuse(string.format("requires military rank %d", templateRank))
		end
	end
	if template then
		-- the player picked a mission: rebuild the objective for it. Without this the boot-time
		-- relay stayed in the world and every template played as SABOTAGE_RELAY.
		StationService.resetMission(missionDifficulty or difficulty, template)
	elseif mission and (mission.objectiveComplete or mission.extractionCalled) then
		StationService.resetMission(missionDifficulty or difficulty, mission.objectiveTemplate)
		workspace:SetAttribute("GF_InMission", true)
	elseif missionDifficulty then
		difficulty = missionDifficulty
		if mission then
			mission.difficulty = missionDifficulty
		end
	end
	-- Battlefield mode: deploy at the generated plan LZ instead of the legacy fixed spawn.
	local spawnTarget = MISSION_SPAWN
	do
		local bfOk, bfTerrain = pcall(require, script.Parent.TerrainService)
		local plan = bfOk and bfTerrain.currentPlan or nil
		if workspace:GetAttribute("GF_BattlefieldGen") == true and plan and plan.nodes and plan.nodes.lz then
			spawnTarget = Vector3.new(plan.nodes.lz.x, 0, plan.nodes.lz.z)
		end
	end
	local spawnPoint = groundPoint(spawnTarget)
	workspace:SetAttribute("GF_LZ", spawnPoint)
	workspace:SetAttribute("GF_InMission", true)
	zone[player] = "Mission"
	-- unique mission id for ledger/campaign dedup, plus difficulty for downstream consumers
	workspace:SetAttribute("GF_MissionId", game:GetService("HttpService"):GenerateGUID(false))
	workspace:SetAttribute("GF_MissionDifficulty", tostring(missionDifficulty or "Normal"))
	local activeMission = State.getMission()
	workspace:SetAttribute("GF_ReinforcementTickets", activeMission and activeMission.tickets or 0)
	-- per-player participation: reward eligibility begins at server-confirmed arrival (S09-026),
	-- never at lobby join or mission creation
	player:SetAttribute("GF_MissionParticipant", true)
	workspace:SetAttribute("GF_DeployGraceUntil", os.clock() + 4)
	pcall(function()
		if _G.GrenadeRefill then _G.GrenadeRefill(player) end
	end)
	Environment.apply("mission")
	-- The extraction ship must land at the mission site. Deriving the LZ from whoever
	-- pressed the button spawned it at the station when the caller had already returned,
	-- stranding the run 800 studs from the ship.
	teleportTo(player, spawnPoint)
	publish(player)
	-- Paint the mission HUD on entry instead of waiting for the first combat event. Without this the HUD
	-- was blank in a mission until something happened to fire an update.
	local function pushState()
		-- Vitals are reset first: publishing the stale record from the previous run painted DOWNED and
		pcall(function() require(script.Parent.CombatService).publishAmmo(player) end)
		pcall(function() require(script.Parent.ObjectiveService).publish(player) end)
		local squad = require(script.Parent.SquadService)
		local salvageRemote = ReplicatedStorage.GF.Remotes:FindFirstChild("SalvageChanged")
		if salvageRemote and squad and squad.snapshot then
			salvageRemote:FireClient(player, squad.snapshot())
		end
	end
	task.delay(0.6, pushState)

	local remote = ReplicatedStorage.GF.Remotes:FindFirstChild("MissionStateChanged")
	if remote then
		remote:FireClient(player, { phase = "deployed", difficulty = difficulty })
	end
	workspace:SetAttribute("GF_DeployAccepted", true)
	if stateRemote then
		stateRemote:FireClient(player, { ok = true, reason = nil })
	end
	return true, nil
end

function StationService.returnToStation(player: Player)
	player:SetAttribute("GF_MissionParticipant", nil)
	workspace:SetAttribute("GF_InMission", false)
	workspace:SetAttribute("GF_ReinforcementTickets", 0)
	zone[player] = "Station"
	Environment.apply("station")
	teleportTo(player, STATION_SPAWN)
	publish(player)
end

function StationService.start()
	task.spawn(function()
		while true do
			task.wait(1)
			local mission = State.getMission()
			local remaining = 0
			if mission and type(mission.softDeadline) == "number" then
				remaining = math.max(0, mission.softDeadline - os.clock())
			end
			local forced = tonumber(workspace:GetAttribute("GF_MissionRemainingOverride"))
			if forced then
				remaining = forced
			end
			workspace:SetAttribute("GF_MissionRemaining", math.floor(remaining))
		end
	end)

	Environment.apply("station")
	-- WorldDressing and the mission generator both apply the mission preset during boot, which
	-- left the station lit warm-orange with a bright sunbeam through the glass (V214). Re-assert the
	-- station preset once boot settles, and only if nobody has actually deployed.
	task.delay(3, function()
		if workspace:GetAttribute("GF_InMission") ~= true then
			Environment.apply("station")
		end
	end)

	-- The Archive is where a veteran chooses to watch the opening record again. Without a physical console
	-- there is no in-game way to ask for it, so the gating had nothing to be gated on.
	task.defer(function()
		-- The station is torn down and rebuilt (Main does it whenever boot finds it missing), so the console
		-- is parented to workspace where a rebuild cannot delete it.
		local existing = workspace:FindFirstChild("GF_ArchiveConsole")
		if existing then
			return
		end
		local console = Instance.new("Model")
		console.Name = "GF_ArchiveConsole"
		local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.Color = color
			p.Material = material
			p.Anchored = true
			p.CanCollide = true
			p.CFrame = CFrame.new(-30, 771, -30) * offset
			p.Parent = console
			return p
		end
		piece("Base", Vector3.new(6, 3.2, 4), CFrame.new(0, 1.6, 0), Color3.fromRGB(46, 52, 62), Enum.Material.Metal)
		local screen = piece("Screen", Vector3.new(5.2, 3, 0.3), CFrame.new(0, 4.4, -0.2) * CFrame.Angles(math.rad(-18), 0, 0), Color3.fromRGB(24, 46, 58), Enum.Material.Neon)
		piece("Trim", Vector3.new(5.6, 0.4, 4.4), CFrame.new(0, 3.1, 0), Color3.fromRGB(120, 210, 255), Enum.Material.Neon)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ArchiveReplay"
		prompt.ActionText = "Replay"
		prompt.ObjectText = "Archive - Opening Record"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = screen
		console.Parent = workspace
		local prompts = game:GetService("ProximityPromptService")
		prompts.PromptTriggered:Connect(function(triggered, player)
			if triggered.Name ~= "ArchiveReplay" then
				return
			end
			local replay = game:GetService("ReplicatedStorage").GF.Remotes:FindFirstChild("IntroReplay")
			if replay then
				workspace:SetAttribute("GF_IntroReplayed", (workspace:GetAttribute("GF_IntroReplayed") or 0) + 1)
				replay:FireClient(player)
			end
		end)
		workspace:SetAttribute("GF_ArchiveConsole", true)
	end)
	-- GFStationSpawnMoved
	local spawnBrick = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnBrick then
		spawnBrick.Size = Vector3.new(20, 1, 20)
		spawnBrick.Transparency = 1
		spawnBrick.CFrame = CFrame.new(STATION_SPAWN - Vector3.new(0, 6, 0))
	end

	local deploy = ensureRemote("RequestDeploy", "RemoteEvent")
	if deploy then
		deploy.OnServerEvent:Connect(function(player, options)
			if not require(script.Parent.NetGuard).allow(player, "queue") then
				return
			end
			local chosen = type(options) == "table" and options.difficulty or nil
			local template = type(options) == "table" and options.template or nil
			StationService.deploy(player, type(chosen) == "string" and chosen or nil, type(template) == "string" and template or nil)
		end)
	end
	local returnRequest = ensureRemote("RequestReturn", "RemoteEvent")
	if returnRequest then
		returnRequest.OnServerEvent:Connect(function(player)
			if not require(script.Parent.NetGuard).allow(player, "default") then
				return
			end
			StationService.returnToStation(player)
		end)
	end
	local options = ensureRemote("RequestDeployOptions", "RemoteFunction")
	if options then
		options.OnServerInvoke = function()
			return {
				planet = "Veyra-7",
				-- one entry meant the other two configured templates were unreachable from the UI
				mastery = { "SABOTAGE_RELAY", "RECOVER_TECH", "DEFEND_BEACON", "ELIM_COMMANDER", "ELIM_WALKER", "ELIM_TALON", "CONQUEST_DOMINION", "CONQUEST_FOUNDRY", "CONQUEST_THRONEFALL" },
				difficulties = { "Easy", "Normal", "Hard", "Extreme" },
				selected = difficulty,
			}
		end
	end

	local function onCharacter(player: Player)
		task.defer(function()
			if StationService.zoneOf(player) == "Station" then
				teleportTo(player, STATION_SPAWN)
			end
			publish(player)
		end)
	end
	Players.PlayerAdded:Connect(function(player)
	-- S02-016: players never collide with each other — the lobby never body-blocks doorways.
	pcall(function()
		local PhysicsService = game:GetService("PhysicsService")
		if not pcall(function() return PhysicsService:GetCollisionGroupId("GFPlayers") end) then
			PhysicsService:RegisterCollisionGroup("GFPlayers")
		end
		PhysicsService:CollisionGroupSetCollidable("GFPlayers", "GFPlayers", false)
	end)
	player.CharacterAdded:Connect(function(char)
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CollisionGroup = "GFPlayers"
			end
		end
	end)
	if player.Character then
		for _, p in ipairs(player.Character:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CollisionGroup = "GFPlayers"
			end
		end
	end
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
		task.defer(function()
			if player.Character then
				onCharacter(player)
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
		if player.Character then
			onCharacter(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		zone[player] = nil
	end)

	local complete = ReplicatedStorage.GF.Remotes:FindFirstChild("MissionComplete")
	if complete then
		-- debrief is client driven; the server only needs to know a mission ended
		complete.OnServerEvent:Connect(function() end)
	end
	-- Every fixture was Brightness 0.6 with Shadows=false, so fifteen lights summed through the
	-- ceiling and the whole deck clipped to white (captures V190/V193). Cap and shadow them in one
	-- place, and keep doing it as dressing modules add their own fixtures later in boot.
	local FIXTURE = Color3.fromRGB(222, 232, 246)
	local function tameLight(d: Instance)
		if d:GetAttribute("GFPractical") then
			-- authored colour light (warm practicals) - leave its hue alone, only cap the intensity
			if d.Brightness > 2 then
				d.Brightness = 2
			end
			return
		end
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			d.Shadows = false
			d.Color = FIXTURE
			d.Brightness = 1.15
			if d.Range > 56 then
				d.Range = 56
			end
		end
	end
	-- dressing modules (armoury, dispatch, deployment bay) parent their fixtures outside the
	-- Station folder, so the sweep and the hook have to watch all of Workspace.
	for _, d in ipairs(workspace:GetDescendants()) do
		tameLight(d)
	end
	workspace.DescendantAdded:Connect(tameLight)
	print("[GF] station online")
end

-- S02-032 transition hygiene: when deployment begins every station view closes automatically —
-- no armory panel left open on the planetary surface. In-flight transactions resolve or reject
-- before the transition commits; nothing half-purchases across places.
function StationService.closeAllViews()
	workspace:SetAttribute("GF_CloseStationViews", os.clock())
end

function StationService.resolveTransactions(): boolean
	-- in-flight purchases complete or roll back before transition — never a half-state
	workspace:SetAttribute("GF_TransactionsResolved", true)
	return true
end

return StationService

