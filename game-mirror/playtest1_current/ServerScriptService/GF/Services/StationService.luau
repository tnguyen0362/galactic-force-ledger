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
local function addInteriorLighting(shell: Instance, base: CFrame?)
	-- Fallback safety only. StationArt and StationConcourse now carry their own authored fixture
	-- grids; adding a second bounding-box grid on top clipped the deck to white. If those modules
	-- ever fail to build, this still guarantees a readable station with twelve restrained fixtures.
	local existing = 0
	for _, d in ipairs(shell:GetDescendants()) do
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			existing += 1
		end
	end
	if existing >= 8 then
		return
	end
	local origin = base or CFrame.new(0, 760, 0)
	local folder = Instance.new("Folder")
	folder.Name = "InteriorLights"
	folder.Parent = shell
	for ix = 0, 2 do
		for iz = 0, 3 do
			local x = -66 + ix * 66
			local z = -54 + iz * 36
			local fixture = Instance.new("Part")
			fixture.Name = "CeilingFixture"
			fixture.Anchored = true
			fixture.CanCollide = false
			fixture.CanQuery = false
			fixture.CastShadow = false
			fixture.Material = Enum.Material.Neon
			fixture.Color = Color3.fromRGB(238, 232, 218)
			fixture.Size = Vector3.new(6, 0.35, 1.6)
			fixture.CFrame = origin * CFrame.new(x, 32.8, z)
			fixture.Parent = folder
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(232, 226, 214)
			light.Brightness = 1.2
			light.Range = 42
			light.Shadows = false
			light.Parent = fixture
		end
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
local straySpawnConnection: RBXScriptConnection? = nil

-- Art-direction palette (GF): graphite / navy / steel / ceramic / tech cyan.
local STEEL = Color3.fromRGB(131, 144, 155)
local DARK = Color3.fromRGB(37, 45, 53)
local NAVY = Color3.fromRGB(59, 77, 96)
local PLATE = Color3.fromRGB(151, 160, 169)
local CERAMIC = Color3.fromRGB(216, 220, 217)
local CYAN = Color3.fromRGB(88, 200, 240)
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
	-- Concourse is the station's deck/vista companion model. Rebuilding Station without rebuilding
	-- it duplicated the deck and every star panel; the pair is one physical place.
	local oldConcourse = workspace:FindFirstChild("Concourse")
	if oldConcourse then
		oldConcourse:Destroy()
	end
	local station = Instance.new("Folder")
	station.Name = "Station"
	station.Parent = workspace
	local base = CFrame.new(0, STATION_Y, 0)

	StationArt.buildShell(station, base)
	-- Walkable, lit concourse with its own spawn; the legacy shell had no floor under the spawn
	-- point and zero Light instances, so players spawned into the void.
	local concourseModel = Concourse.build(workspace)
	-- StationArt still carries two generations of fallback ceiling lights: tiny lamp anchors and
	-- bare floating LightPool bulbs on top of the authored panel grid and Concourse fixtures. They
	-- cost eleven lights without adding readable fixture geometry, and their overlap flattened the
	-- hull into a white box. Remove that legacy layer; the visible panels and pendant practicals stay.
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "CeilingLampAnchor" or d.Name == "LightPool") then
			d:Destroy()
		end
	end
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
	if straySpawnConnection then
		straySpawnConnection:Disconnect()
	end
	straySpawnConnection = workspace.DescendantAdded:Connect(killStraySpawn)
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

	-- Construction helpers local to the command-carrier dressing pass. `part` is structural by
	-- default; `detail` is for paint, lenses, seams, holograms and other geometry players should
	-- never collide with or query.
	local function detail(p: Part): Part
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		return p
	end
	local function flat(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, transparency: number?): Part
		local p = part(station, name, size, cf, color, material or Enum.Material.SmoothPlastic)
		p.Transparency = transparency or 0
		return detail(p)
	end
	local function practical(at: Vector3, lensSize: Vector3, colour: Color3)
		local fixture = part(station, "Practical", lensSize, CFrame.new(at), colour, Enum.Material.Neon)
		fixture.CanCollide = false
		fixture.CanQuery = false
		fixture.CastShadow = false
		local lamp = Instance.new("PointLight")
		lamp.Color = colour
		lamp.Brightness = 0.9
		lamp.Range = 26
		lamp.Shadows = false
		lamp:SetAttribute("GFPractical", true)
		lamp.Parent = fixture
		return fixture
	end
	local function practicalOn(host: BasePart, colour: Color3, brightness: number, range: number)
		local lamp = Instance.new("PointLight")
		lamp.Color = colour
		lamp.Brightness = brightness
		lamp.Range = range
		lamp.Shadows = false
		lamp:SetAttribute("GFPractical", true)
		lamp.Parent = host
		return lamp
	end

	-- Section signage. Every sign is a backed physical plate with a restrained accent rule; the
	-- face is supplied explicitly because wall signs in this build face several different axes.
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
		label.TextStrokeTransparency = 0.8
		label.TextScaled = true
		label.Parent = gui
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(1, 0, 0.055, 0)
		strip.Position = UDim2.fromScale(0, 0.945)
		strip.BorderSizePixel = 0
		strip.BackgroundColor3 = accent
		strip.Parent = gui
		return plate
	end

	-- Keep the lighting fallback honest without stacking another grid over the authored fixtures.
	addInteriorLighting(station, base)

	-- StationArt's armory/dispatch furniture was authored against a phantom deck height of 3.7;
	-- the walkable Concourse deck tops out at local Y=1.0. The result was a 2.7-stud hover under
	-- every rack, bench, counter and queue post. Lower only the deck-derived furniture: pendant
	-- rods and lamp bodies in the same folders are ceiling-height authored and must not come down.
	local DECK_FLOAT_DROP = 2.7
	for _, folderName in ipairs({ "ArmoryDressing", "DispatchDressing" }) do
		local dressing = station:FindFirstChild(folderName)
		if dressing then
			for _, d in ipairs(dressing:GetDescendants()) do
				if d:IsA("BasePart") then
					if d.Name == "SignalBar" then
						-- StationArt's signal-loop rewrites these bars from the phantom height every
						-- frame, so lowering them would last only one frame. Replace them below.
						d:Destroy()
					elseif folderName == "ArmoryDressing" and (string.find(d.Name, "Pendant", 1, true) or d.Name == "ArmoryLampBody") then
						-- The old alcove pendants belong to the sealed pre-portal layout. The new wing
						-- has its own lower, shorter fixtures; keeping these would double-light the door.
						d:Destroy()
					elseif not string.find(d.Name, "Pendant", 1, true) and d.Name ~= "ArmoryLampBody" and d.Name ~= "DispatchLampBody" then
						d.CFrame = d.CFrame + Vector3.new(0, -DECK_FLOAT_DROP, 0)
					end
				end
			end
		end
	end
	-- Move the useful pieces of StationArt's old armory alcove through the new portal instead of
	-- deleting their craftsmanship. The perpendicular rifle racks become outer-wall storage in the
	-- wing; the inspection bench and mannequin occupy the otherwise empty south end. Their original
	-- positions were all inside the concourse/portal throat and fought the new circulation path.
	local armoryDressing = station:FindFirstChild("ArmoryDressing")
	if armoryDressing then
		for _, d in ipairs(armoryDressing:GetDescendants()) do
			if d:IsA("BasePart") then
				if string.sub(d.Name, 1, 4) == "Rack" then
					d.CFrame = d.CFrame + Vector3.new(-27, 0, 0)
					if d.Name == "RackUpright" or d.Name == "RackBoard" then
						d.CanCollide = true
					end
				elseif string.sub(d.Name, 1, 5) == "Bench" then
					d.CFrame = d.CFrame + Vector3.new(-32, 0, 58)
				elseif string.sub(d.Name, 1, 9) == "Mannequin" then
					d.CFrame = d.CFrame + Vector3.new(-20.5, 0, 54)
				end
			end
		end
	end
	local dispatchDressing = station:FindFirstChild("DispatchDressing")
	if dispatchDressing then
		-- Static replacement signal bars at the corrected counter height. They live one level down
		-- so StationArt's direct-child animation loop does not adopt and re-lift them.
		local signalFolder = Instance.new("Folder")
		signalFolder.Name = "SignalBarsCorrected"
		signalFolder.Parent = dispatchDressing
		local signalCF = base * CFrame.new(94.2, 1.0, -26) * CFrame.Angles(0, math.rad(90), 0)
		for index = 1, 9 do
			local h = 0.8 + ((index * 2 + 1) % 5) * 0.48
			local bar = part(signalFolder, "SignalBar", Vector3.new(0.42, h, 0.3), signalCF * CFrame.new(-3.2 + (index - 1) * 0.8, 1.05 + h * 0.5, -2.32), Color3.fromRGB(64, 178, 214), Enum.Material.Neon)
			bar.CanCollide = false
			bar.CanQuery = false
			bar.CastShadow = false
		end
	end

	-- StationArt's plated floor was authored 0.3 studs below the continuous fallback deck, which
	-- made all seventy plates and the amber centreline invisible inside the slab. Lift the shell
	-- floor just above the fallback deck so the large-panel floor system is the visible surface.
	-- The 0.05-stud reveal is enough to read the seams without changing any gameplay footprint.
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "DeckChevron" then
			-- The departure threshold now has its own alternating hazard stripe. Five additional
			-- chevrons in the same approach lane read as paint noise once the floor plates are visible.
			d:Destroy()
		elseif d:IsA("BasePart") and (d.Name == "FloorPlate" or d.Name == "DeckLine") then
			d.CFrame = d.CFrame + Vector3.new(0, 0.35, 0)
		end
	end
	if concourseModel then
		for _, d in ipairs(concourseModel:GetChildren()) do
			if d:IsA("BasePart") and d.Name == "GuideStripe" then
				-- StationArt already owns the amber centreline; keeping both would layer two nearly
				-- identical stripes once the plated floor is visible.
				d:Destroy()
			elseif d:IsA("BasePart") and d.Name == "LaneStripe" then
				d.CFrame = d.CFrame + Vector3.new(0, 0.1, 0)
			end
		end
	end

	-- ---------------------------------------------------------------------------
	-- ORBITAL VISTA NORMALIZATION
	-- StationArt carried an early close-range planet and ninety close stars. Those sit inside the
	-- shared mission volume and also fight the distant Concourse vista. Remove that first-pass sky
	-- and tune the persistent far vista as one coherent layered composition: planet limb below,
	-- terminator shadow, moons, fleet silhouettes, then a deep black-blue starred backdrop.
	-- ---------------------------------------------------------------------------
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "VistaStar" or d.Name == "Veyra7" or d.Name == "Veyra7Atmo" or d.Name == "Veyra7Belt" or d.Name == "Veyra7Halo") then
			d:Destroy()
		end
	end
	local vistaParent: Instance? = nil
	if concourseModel then
		vistaParent = concourseModel:FindFirstChild("OrbitVista")
	end
	if not vistaParent then
		local created = Instance.new("Model")
		created.Name = "OrbitVista"
		created.Parent = station
		vistaParent = created
	end
	if vistaParent and vistaParent:IsA("Model") then
		vistaParent.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end
	if vistaParent then
		-- The original 15x7 backdrop used 105 small tiles because of the 2048-stud primitive clamp.
		-- The same coverage fits in 5x4 large tiles. That saves ninety replicated parts and lets the
		-- parallax layers carry the scene instead of a quilt of cards.
		for _, d in ipairs(vistaParent:GetChildren()) do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 17) == "StarfieldBackdrop" then
				d:Destroy()
			end
		end
		local windowCenter = Vector3.new(0, STATION_Y + 16, -74.5)
		local outward = Vector3.new(0, 0, -1)
		local backdropCenter = windowCenter + outward * 4300
		local backdropCf = CFrame.lookAt(backdropCenter, windowCenter)
		local right = backdropCf.RightVector
		local up = backdropCf.UpVector
		for tx = -2, 2 do
			for ty = -1.5, 1.5, 1 do
				local tileAt = backdropCenter + right * (tx * 1800) + up * (ty * 1400)
				local tile = part(vistaParent, "StarfieldBackdrop", Vector3.new(1800, 1400, 4), CFrame.lookAt(tileAt, windowCenter), Color3.fromRGB(4, 8, 18), Enum.Material.SmoothPlastic)
				tile.CanCollide = false
				tile.CanQuery = false
				tile.CanTouch = false
				tile.CastShadow = false
			end
		end
		-- Re-seed the authored distant stars against the new backdrop instead of preserving their
		-- old offsets. The original field was centered on the tilted 2700-stud plane, so moving those
		-- offsets verbatim pushed the whole field hundreds of studs upward. The modular arithmetic is
		-- deterministic (no Random object needed) and keeps the sky stable between rebuilds.
		for _, d in ipairs(vistaParent:GetChildren()) do
			if d:IsA("BasePart") and string.match(d.Name, "^Star%d+$") then
				local index = tonumber(string.match(d.Name, "%d+")) or 0
				local u = (((index * 7919) % 1000) / 999 - 0.5) * 8500
				local v = (((index * 104729) % 1000) / 999 - 0.5) * 4300
				local starAt = Vector3.new(backdropCenter.X + u, backdropCenter.Y + v, backdropCenter.Z + 8)
				d.CFrame = CFrame.new(starAt)
				-- SmoothPlastic stars vanish in the space lighting environment; every star needs a
				-- small emissive component, with transparency carrying the brightness variation.
				d.Material = Enum.Material.Neon
				d.Transparency = 0.08 + (index % 5) * 0.045
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
			end
		end
		local function ensureVista(name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, transparency: number): Part
			local existing = vistaParent:FindFirstChild(name)
			local p: Part
			if existing and existing:IsA("Part") then
				p = existing
			else
				p = part(vistaParent, name, size, cf, color, material)
			end
			p.Shape = shape
			p.Size = size
			p.CFrame = cf
			p.Color = color
			p.Material = material
			p.Transparency = transparency
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Parent = vistaParent
			return p
		end
		-- Veyra-7 is below the station, not a wall decoration. The primitive size cap keeps the body
		-- under 2048 studs; layered offset shells produce the limb, cloud film and terminator edge.
		-- Keep the upper limb inside the window cone. At y=-650 the planet was geometrically below the
		-- sill for normal eye heights, so the vista read as a black wall with two specks. The body is
		-- emissive at low intensity because sunlight/shadows are not meaningful at 3.7k studs.
		local planetCenter = Vector3.new(250, 400, -3700)
		ensureVista("Planet", Enum.PartType.Ball, Vector3.new(1980, 1980, 1980), CFrame.new(planetCenter), Color3.fromRGB(18, 45, 78), Enum.Material.Neon, 0)
		-- Nested transparent balls do not layer reliably in Roblox: even 80–90% transparency can
		-- occlude the opaque body and turn the planet into a milk-white or black disc. The cloud/haze
		-- shells therefore stay as nearly invisible depth cues; the readable edge comes from the limbs.
		ensureVista("PlanetClouds", Enum.PartType.Ball, Vector3.new(1996, 1996, 1996), CFrame.new(planetCenter + Vector3.new(-24, 12, -8)), Color3.fromRGB(176, 204, 220), Enum.Material.Neon, 0.985)
		ensureVista("PlanetHaze", Enum.PartType.Ball, Vector3.new(1988, 1988, 1988), CFrame.new(planetCenter + Vector3.new(360, 40, 65)), Color3.fromRGB(6, 15, 28), Enum.Material.Neon, 0.985)
		ensureVista("PlanetLimbInner", Enum.PartType.Ball, Vector3.new(2008, 2008, 2008), CFrame.new(planetCenter), Color3.fromRGB(190, 230, 255), Enum.Material.Neon, 0.97)
		ensureVista("PlanetLimb", Enum.PartType.Ball, Vector3.new(2038, 2038, 2038), CFrame.new(planetCenter), Color3.fromRGB(82, 170, 225), Enum.Material.Neon, 0.95)
		ensureVista("Moon", Enum.PartType.Ball, Vector3.new(360, 360, 360), CFrame.new(-1350, 1300, -3400), Color3.fromRGB(112, 116, 112), Enum.Material.Neon, 0.34)
		ensureVista("MoonRight", Enum.PartType.Ball, Vector3.new(440, 440, 440), CFrame.new(1550, 1040, -3500), Color3.fromRGB(96, 106, 122), Enum.Material.Neon, 0.38)
		ensureVista("MoonRightHalo", Enum.PartType.Ball, Vector3.new(456, 456, 456), CFrame.new(1550, 1040, -3500), Color3.fromRGB(82, 140, 186), Enum.Material.Neon, 0.88)
		for k = 1, 3 do
			local at = Vector3.new(1380 + k * 60, 900 - k * 22, -3100 - k * 90)
			ensureVista("OrbitRing" .. k, Enum.PartType.Block, Vector3.new(220 - k * 30, 5, 26), CFrame.lookAt(at, at + Vector3.new(0, 0, 1)) * CFrame.Angles(0, math.rad(12 * k), math.rad(4 * k)), Color3.fromRGB(42, 48, 58), Enum.Material.Metal, 0.05)
		end
		local drift = {}
		for index, spec in ipairs({
			{ 520, 940, -2850 },
			{ -700, 1080, -3200 },
			{ 120, 850, -3500 },
		}) do
			local at = Vector3.new(spec[1], spec[2], spec[3])
			local hull = ensureVista("Freighter" .. index, Enum.PartType.Block, Vector3.new(220, 60, 90), CFrame.lookAt(at, at + Vector3.new(0, 0, 1)) * CFrame.Angles(0, math.rad(18 * index), 0), Color3.fromRGB(38, 44, 54), Enum.Material.Metal, 0.03)
			ensureVista("FreighterLight" .. index, Enum.PartType.Block, Vector3.new(34, 34, 34), CFrame.new(at + Vector3.new(0, 46, 0)), Color3.fromRGB(255, 198, 146), Enum.Material.Neon, 0.08)
			table.insert(drift, { part = hull, home = hull.CFrame, phase = index * 1.73, speed = 0.018 + index * 0.004 })
		end
		for _, d in ipairs(vistaParent:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				-- StationConcourse parents the physical window glazing and railing frames inside
				-- OrbitVista as well as the celestial stagecraft. They are pressure-shell geometry,
				-- not backdrop: stripping collision here reopens the hull and lets players walk into
				-- space (the exact regression MICRO-020 fixed).
				local structural = string.sub(d.Name, 1, 6) == "Window" or d.Name == "ObservationRailing" or d.Name == "RailingPost"
				if structural then
					d.CanCollide = true
					d.CanQuery = false
					d.CastShadow = true
				else
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.CastShadow = false
				end
			end
		end
		task.spawn(function()
			while vistaParent.Parent do
				local t = os.clock()
				for _, item in ipairs(drift) do
					if item.part.Parent then
						item.part.CFrame = item.home * CFrame.new(math.sin(t * item.speed + item.phase) * 90, math.sin(t * item.speed * 0.7 + item.phase) * 16, 0)
					end
				end
				task.wait(0.25)
			end
		end)
	end

	-- ---------------------------------------------------------------------------
	-- OBSERVATION CONCOURSE: the window row already exists in the shell. This pass makes the
	-- structure legible at first glance — heavy angled kingposts, an armored brow, a continuous
	-- inner sill and a dim blue planetary wash. The glazing itself remains solid and collidable.
	-- ---------------------------------------------------------------------------
	local windowZ = -74.5
	part(station, "WindowArmorBrow", Vector3.new(176, 2.1, 4.8), base * CFrame.new(0, 31.15, windowZ + 1.7) * CFrame.Angles(math.rad(-4), 0, 0), STEEL, Enum.Material.Metal)
	part(station, "WindowArmorSill", Vector3.new(176, 1.8, 5.2), base * CFrame.new(0, 1.1, windowZ + 2.2) * CFrame.Angles(math.rad(-4), 0, 0), NAVY, Enum.Material.Metal)
	for _, mx in ipairs({ -29, 29 }) do
		part(station, "WindowKingpost", Vector3.new(4.6, 30, 4.8), base * CFrame.new(mx, 15.7, windowZ + 2.1) * CFrame.Angles(math.rad(-4), 0, 0), STEEL, Enum.Material.Metal)
		local cap = flat("WindowKingpostCap", Vector3.new(0.35, 24, 0.35), base * CFrame.new(mx, 15.5, windowZ + 4.7), CYAN, Enum.Material.Neon, 0.68)
		cap.CastShadow = false
	end
	local planetshine = neon(station, "PlanetshineLens", Vector3.new(10, 0.35, 1.2), base * CFrame.new(0, 7.8, windowZ + 10.5), Color3.fromRGB(100, 174, 218))
	planetshine.Transparency = 0.82
	practicalOn(planetshine, Color3.fromRGB(112, 174, 218), 0.55, 46)
	-- flank the existing GFS VANGUARD plate rather than duplicating it
	for _, sx in ipairs({ -1, 1 }) do
		local flank = neon(station, "VanguardSignFlank", Vector3.new(7, 0.28, 0.28), base * CFrame.new(sx * 15.8, 31.2, windowZ + 3.2), CYAN)
		flank.Transparency = 0.48
	end

	-- ---------------------------------------------------------------------------
	-- PORT ARMORY WING. The interactive ArmoryRack parts are gameplay anchors at x=-112 and must
	-- not move. In the original box they were sealed outside the x=-100 bulkhead, so the armory
	-- prompt could never be reached. Instead of moving the anchors, cut a portal into the shell and
	-- build a compact lower-ceiling armory/research wing around them.
	-- ---------------------------------------------------------------------------
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") then
			local x, z = d.Position.X, d.Position.Z
			if (d.Name == "Bulkhead" or d.Name == "BulkheadBase") and x < -50 then
				d:Destroy()
			elseif (d.Name == "Rib" or d.Name == "RibLight" or d.Name == "ServicePanel") and x < -90 and math.abs(z) < 38 then
				d:Destroy()
			elseif d.Name == "Sign_ARMORY" then
				d:Destroy()
			end
		end
	end
	for _, d in ipairs(concourseModel:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "WallDado" or d.Name == "WallTrim") and d.Position.X < 0 then
			d:Destroy()
		end
	end
	-- reconstruct the main bulkhead around a 76-stud-wide wing portal. The shell's own navy is
	-- intentionally lighter than the interior accent navy; using the accent colour here makes the
	-- cut wall read as a patch instead of the same pressure hull.
	local SHELL_NAVY = Color3.fromRGB(84, 96, 112)
	part(station, "Bulkhead", Vector3.new(3, 36, 38), base * CFrame.new(-100, 18, -57), SHELL_NAVY, Enum.Material.Metal)
	part(station, "Bulkhead", Vector3.new(3, 36, 38), base * CFrame.new(-100, 18, 57), SHELL_NAVY, Enum.Material.Metal)
	part(station, "BulkheadLintel", Vector3.new(3, 14, 76), base * CFrame.new(-100, 29, 0), SHELL_NAVY, Enum.Material.Metal)
	for _, z in ipairs({ -57, 57 }) do
		part(station, "BulkheadBase", Vector3.new(4.5, 5, 38), base * CFrame.new(-100, 2.5, z), STEEL, Enum.Material.Metal)
	end
	for _, z in ipairs({ -38, 38 }) do
		part(station, "ArmoryPortalJamb", Vector3.new(5, 22, 3.2), base * CFrame.new(-99.7, 11, z), STEEL, Enum.Material.Metal)
	end
	part(station, "ArmoryPortalHeader", Vector3.new(5, 3, 79), base * CFrame.new(-99.7, 20.8, 0), STEEL, Enum.Material.Metal)
	local wing = Instance.new("Folder")
	wing.Name = "ArmoryWing"
	wing.Parent = station
	-- End the wing floor exactly at the hall plate edge (x=-100) and put its top at the fallback
	-- deck height. The earlier overlap sank 0.3 studs below the concourse and z-fought/created a
	-- phantom threshold inside the portal.
	part(wing, "ArmoryWingFloor", Vector3.new(27, 0.7, 92), base * CFrame.new(-113.5, 0.65, 0), Color3.fromRGB(55, 63, 72), Enum.Material.Metal)
	part(wing, "ArmoryOuterWall", Vector3.new(2, 22, 92), base * CFrame.new(-127, 11, 0), SHELL_NAVY, Enum.Material.Metal)
	part(wing, "ArmoryEndWall", Vector3.new(28, 22, 2), base * CFrame.new(-113, 11, -46), SHELL_NAVY, Enum.Material.Metal)
	part(wing, "ArmoryEndWall", Vector3.new(28, 22, 2), base * CFrame.new(-113, 11, 46), SHELL_NAVY, Enum.Material.Metal)
	part(wing, "ArmoryWingCeiling", Vector3.new(29, 1.5, 94), base * CFrame.new(-113, 22.7, 0), DARK, Enum.Material.Metal)
	for _, z in ipairs({ -30, 0, 30 }) do
		flat("ArmoryFloorSeam", Vector3.new(25, 0.06, 0.24), base * CFrame.new(-113, 1.04, z), Color3.fromRGB(22, 27, 34), Enum.Material.SmoothPlastic).Parent = wing
	end
	-- a muted guide line pulls the eye from the concourse through the portal
	flat("ArmoryGuide", Vector3.new(24, 0.08, 0.7), base * CFrame.new(-105, 1.1, 0), AMBER, Enum.Material.SmoothPlastic, 0.18).Parent = wing
	-- wall lockers fill the south half of the outer wall; the north half carries the relocated
	-- perpendicular rifle racks, so both storage languages stay readable instead of overlapping
	for index, z in ipairs({ 10, 29 }) do
		part(wing, "ArmoryLocker", Vector3.new(2.4, 10.5, 10), base * CFrame.new(-124.6, 5.95, z), if index % 2 == 0 then NAVY else DARK, Enum.Material.Metal)
		flat("LockerStatus", Vector3.new(0.18, 0.4, 2.2), base * CFrame.new(-123.25, 9.4, z), CYAN, Enum.Material.Neon, 0.45).Parent = wing
	end
	-- research workbench at the quiet end: bench, vice, scanner hologram and a few large tools
	local benchCF = base * CFrame.new(-113, 0, -40.5)
	part(wing, "ResearchBenchTop", Vector3.new(16, 0.7, 4), benchCF * CFrame.new(0, 3.35, 0), STEEL, Enum.Material.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(wing, "ResearchBenchLeg", Vector3.new(0.55, 3.1, 0.55), benchCF * CFrame.new(sx * 7.1, 1.7, sz * 1.45), DARK, Enum.Material.Metal)
		end
	end
	part(wing, "ResearchBackPanel", Vector3.new(15.5, 4.2, 0.5), benchCF * CFrame.new(0, 6.2, -1.9), NAVY, Enum.Material.Metal)
	flat("ResearchBenchMat", Vector3.new(10, 0.1, 3), benchCF * CFrame.new(-1.2, 3.78, 0.1), Color3.fromRGB(30, 46, 56), Enum.Material.Fabric).Parent = wing
	flat("ResearchScanPlane", Vector3.new(7, 0.12, 2.8), benchCF * CFrame.new(-1.2, 5.2, 0.1), CYAN, Enum.Material.Neon, 0.82).Parent = wing
	for index, x in ipairs({ -5.5, -2.8, 2.6 }) do
		part(wing, "ResearchTool", Vector3.new(1.7, 0.34, 0.42), benchCF * CFrame.new(x, 4.05, 0.7 - index * 0.35), if index == 2 then CERAMIC else PLATE, Enum.Material.Metal)
	end
	for _, z in ipairs({ -22, 12 }) do
		local wingLight = practical(base * Vector3.new(-113, 19.5, z), Vector3.new(8, 0.28, 1.2), Color3.fromRGB(238, 226, 204))
		wingLight.Parent = wing
		local wingLamp = wingLight:FindFirstChildOfClass("PointLight")
		if wingLamp then
			-- the wing is a closed side volume; the generic practical level left its deck nearly black
			wingLamp.Brightness = 1.55
			wingLamp.Range = 31
		end
		-- the wing ceiling is lower than the concourse ceiling, so these need a visible housing and
		-- real suspension rods; a bare neon bar floating two studs below the roof reads as a leftover.
		local housing = part(wing, "ArmoryLightHousing", Vector3.new(8.7, 0.42, 1.7), base * CFrame.new(-113, 19.78, z), DARK, Enum.Material.Metal)
		housing.CanCollide = false
		for _, sx in ipairs({ -1, 1 }) do
			local rod = part(wing, "ArmoryLightRod", Vector3.new(0.22, 2.15, 0.22), base * CFrame.new(-113 + sx * 3.3, 20.9, z), STEEL, Enum.Material.Metal)
			rod.CanCollide = false
		end
	end
	practical(base * Vector3.new(-113, 8.45, -39), Vector3.new(4, 0.24, 0.8), Color3.fromRGB(255, 188, 110)).Parent = wing
	sign("ARMORY / RESEARCH", 30, 3.8, base * CFrame.new(-97.7, 17.2, 0) * CFrame.Angles(0, math.rad(-90), 0), Enum.NormalId.Front, AMBER)

	-- war table: the mission selection surface players stand at. The names, positions and sizes of
	-- WarTableBase/WarTableTop/WarHolo/WarPlanet are gameplay and module contracts — do not move them.
	local tableCF = base * CFrame.new(0, 0, -34)
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
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(station, "WarTableCornerCap", Vector3.new(3.8, 0.9, 3.8), tableCF * CFrame.new(sx * 15.3, 4.15, sz * 15.3), STEEL, Enum.Material.Metal)
		end
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
	-- restrained volumetric projection: one translucent cylinder, a scan bar and no particle spam.
	-- Roblox cylinder length is the part's X axis, so the disc must be rolled upright; unrotated it
	-- reads as a horizontal wheel cutting through the globe.
	local projection = part(station, "WarProjectionVolume", Vector3.new(5.1, 15.5, 15.5), tableCF * CFrame.new(0, 6.15, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(76, 170, 216), Enum.Material.Neon)
	projection.Shape = Enum.PartType.Cylinder
	projection.Transparency = 0.94
	projection.CanCollide = false
	projection.CastShadow = false
	local scanBar = part(station, "WarScanBar", Vector3.new(20, 0.1, 0.48), tableCF * CFrame.new(0, 6.2, 0), Color3.fromRGB(116, 216, 255), Enum.Material.Neon)
	scanBar.Transparency = 0.58
	scanBar.CanCollide = false
	scanBar.CastShadow = false
	task.spawn(function()
		while scanBar.Parent do
			scanBar.CFrame = tableCF * CFrame.new(0, 6.2, 0) * CFrame.Angles(0, os.clock() * 0.45, 0)
			task.wait(0.1)
		end
	end)

	-- ---------------------------------------------------------------------------
	-- four deployment terminals (Counteroffensive mandate §72): the central war table is theater
	-- DISPLAY only — deployment interaction happens at physical terminals, one per theater arc.
	-- Names, positions and attributes below are client proximity contracts and are unchanged.
	-- ---------------------------------------------------------------------------
	local TERMINALS = {
		{ id = "T1", arc = "VERDANT ARC", regions = "VerdantReach,ThornBasin", offset = CFrame.new(-30, 0, -34), accent = Color3.fromRGB(90, 200, 130) },
		{ id = "T2", arc = "ASHEN ARC", regions = "AshenDivide,RedMesa", offset = CFrame.new(-24, 0, 6), accent = Color3.fromRGB(220, 150, 80) },
		{ id = "T3", arc = "FROST ARC", regions = "Frostline,WhiteRidge", offset = CFrame.new(30, 0, -34), accent = Color3.fromRGB(130, 200, 240) },
		{ id = "T4", arc = "IRON ARC", regions = "IronMarch,FoundryBelt", offset = CFrame.new(24, 0, 6), accent = Color3.fromRGB(200, 110, 110) },
	}
	for _, term in ipairs(TERMINALS) do
		local tcf = base * term.offset
		local console = part(station, "DeployTerminal_" .. term.id, Vector3.new(8, 4.2, 5), tcf * CFrame.new(0, 2.1, 0), DARK, Enum.Material.Metal)
		console:SetAttribute("TerminalArc", term.arc)
		console:SetAttribute("TerminalRegions", term.regions)
		-- floor socket and cable trace make the console feel installed rather than dropped on deck
		for _, zoff in ipairs({ -3.2, 3.2 }) do
			flat("TerminalFloorSocket", Vector3.new(10, 0.08, 0.55), tcf * CFrame.new(0, 1.1, zoff), STEEL, Enum.Material.Metal, 0.12)
		end
		local accentStrip = neon(station, "TerminalCableStrip", Vector3.new(0.42, 0.08, 7.6), tcf * CFrame.new(-4.8, 1.12, 0), term.accent)
		accentStrip.Transparency = 0.58
		-- broad console cap in the arc's accent color: readable from across the room without a neon slab at full opacity
		local top = part(station, "TerminalTop_" .. term.id, Vector3.new(8.4, 0.5, 5.4), tcf * CFrame.new(0, 4.35, 0), term.accent, Enum.Material.Neon)
		top.Transparency = 0.58
		top.CanCollide = false
		practicalOn(top, term.accent, 0.36, 12)
		-- status screen on the concourse-side rear face: every terminal is forward of the spawn,
		-- so a Front (-Z) GUI put the theater status on the side players never approach first
		local screen = part(station, "TerminalScreen_" .. term.id, Vector3.new(6.5, 3.5, 0.3), tcf * CFrame.new(0, 6.2, 2.2), Color3.fromRGB(10, 16, 22), Enum.Material.SmoothPlastic)
		screen.CanCollide = false
		local mast = part(station, "TerminalMast", Vector3.new(0.36, 4.1, 0.36), tcf * CFrame.new(3.65, 6.2, -1.8), STEEL, Enum.Material.Metal)
		mast.CanCollide = false
		local mastLamp = neon(station, "TerminalMastLamp", Vector3.new(0.72, 0.72, 0.72), tcf * CFrame.new(3.65, 8.45, -1.8), term.accent)
		mastLamp.Shape = Enum.PartType.Ball
		mastLamp.Transparency = 0.25
		local gui = Instance.new("SurfaceGui")
		gui.Name = "TerminalGui"
		gui.Face = Enum.NormalId.Back
		gui.CanvasSize = Vector2.new(650, 350)
		gui.Parent = screen
		local title = Instance.new("TextLabel")
		title.Size = UDim2.fromScale(1, 0.28)
		title.BackgroundTransparency = 1
		title.TextColor3 = term.accent
		title.Text = term.arc .. " DEPLOYMENT"
		title.Font = Enum.Font.RobotoMono
		title.TextSize = 34
		title.Parent = gui
		local regions = Instance.new("TextLabel")
		regions.Size = UDim2.fromScale(1, 0.2)
		regions.Position = UDim2.fromScale(0, 0.3)
		regions.BackgroundTransparency = 1
		regions.TextColor3 = Color3.fromRGB(160, 170, 185)
		regions.Text = string.gsub(term.regions, ",", "  ·  ")
		regions.Font = Enum.Font.RobotoMono
		regions.TextSize = 20
		regions.Parent = gui
		-- live theater status line per region pair, refreshed by the war state publisher —
		-- the terminal face shows the war before the player even interacts
		local statusLine = Instance.new("TextLabel")
		statusLine.Name = "TheaterStatus"
		statusLine.Size = UDim2.fromScale(1, 0.4)
		statusLine.Position = UDim2.fromScale(0, 0.55)
		statusLine.BackgroundTransparency = 1
		statusLine.TextColor3 = Color3.fromRGB(120, 210, 255)
		statusLine.Text = ""
		statusLine.Font = Enum.Font.RobotoMono
		statusLine.TextSize = 16
		statusLine.TextWrapped = true
		statusLine.Parent = gui
	end
	-- live theater status on every terminal face: the war is visible before any interaction.
	-- reads the WarStateService region attributes; degrades to silent-empty before the first
	-- publish rather than showing stale-future text
	task.spawn(function()
		local SHORT = {
			ascendancy_dominance = "ASC",
			contested_theater = "CTD",
			human_infiltration = "INF",
			gf_offensive = "OFF",
			established_superiority = "SUP",
		}
		while station.Parent do
			for _, term in ipairs(TERMINALS) do
				local screen = station:FindFirstChild("TerminalScreen_" .. term.id)
				local gui = screen and screen:FindFirstChild("TerminalGui")
				local line = gui and gui:FindFirstChild("TheaterStatus")
				if line then
					local parts = {}
					for _, rid in ipairs(string.split(term.regions, ",")) do
						local s = workspace:GetAttribute("GF_WarState_" .. rid .. "_Status")
						if type(s) == "string" then
							table.insert(parts, string.format("%s %s", rid, SHORT[s] or s))
						end
					end
					line.Text = table.concat(parts, "\n")
				end
			end
			task.wait(4)
		end
	end)
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

	-- ---------------------------------------------------------------------------
	-- SCALE DETAIL: structural columns, service conduits and sealed side-corridor doors. These are
	-- broad modular pieces (not rivet spam); they imply the carrier continues beyond the accessible
	-- concourse without turning the lobby into a sprawling roleplay station.
	-- ---------------------------------------------------------------------------
	for _, spec in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local sx, sz = spec[1], spec[2]
		local x, z = sx * 72, sz * 42
		part(station, "ConcourseColumn", Vector3.new(3.8, 31.5, 3.8), base * CFrame.new(x, 16.4, z), NAVY, Enum.Material.Metal)
		part(station, "ColumnBase", Vector3.new(6.2, 0.9, 6.2), base * CFrame.new(x, 1.15, z), STEEL, Enum.Material.Metal)
		part(station, "ColumnCapital", Vector3.new(5.8, 2.0, 5.8), base * CFrame.new(x, 32.8, z), STEEL, Enum.Material.Metal)
		local strip = neon(station, "ColumnStatusStrip", Vector3.new(0.18, 15, 1.1), base * CFrame.new(x - sx * 2, 15, z), CYAN)
		strip.Transparency = 0.66
	end
	for _, x in ipairs({ -42, 42 }) do
		part(station, "CeilingCableTray", Vector3.new(4, 0.8, 128), base * CFrame.new(x, 33.2, 0), DARK, Enum.Material.Metal)
		part(station, "CeilingPipe", Vector3.new(0.8, 0.8, 128), base * CFrame.new(x + 2.6, 32.35, 0), STEEL, Enum.Material.Metal)
		for z = -45, 45, 30 do
			part(station, "PipeClamp", Vector3.new(5.4, 0.55, 0.7), base * CFrame.new(x + 1.2, 32.75, z), PLATE, Enum.Material.Metal)
		end
	end
	local function serviceDoor(side: number, z: number, label: string)
		local x = side * 98.15
		part(station, "ServiceCorridorDoor", Vector3.new(0.42, 8.6, 6.4), base * CFrame.new(x, 5.2, z), DARK, Enum.Material.Metal)
		for _, sz in ipairs({ -1, 1 }) do
			part(station, "ServiceDoorFrame", Vector3.new(0.7, 9.6, 0.55), base * CFrame.new(x - side * 0.12, 5.6, z + sz * 3.5), STEEL, Enum.Material.Metal)
		end
		part(station, "ServiceDoorHeader", Vector3.new(0.7, 0.75, 7.6), base * CFrame.new(x - side * 0.12, 10.2, z), STEEL, Enum.Material.Metal)
		local stripe = neon(station, "ServiceDoorStatus", Vector3.new(0.14, 4.6, 0.24), base * CFrame.new(x - side * 0.34, 5.5, z - 2.5), CYAN)
		stripe.Transparency = 0.5
		sign(label, 7.5, 1.55, base * CFrame.new(x - side * 0.45, 11.4, z) * CFrame.Angles(0, if side < 0 then math.rad(-90) else math.rad(90), 0), Enum.NormalId.Front, STEEL)
	end
	-- Keep the port service hatch on the forward wall segment; at z=58 it sat directly behind the
	-- personnel terminal and armor display, turning the whole aft-port corner into one unreadable clump.
	serviceDoor(-1, -58, "SERVICE 01")
	serviceDoor(1, 52, "SERVICE 02")

	-- Warm/cool practical hierarchy: neutral overhead shell lighting, warm work lights at human
	-- stations, cool cyan only where machinery or holography is the subject. Reuse StationArt's
	-- pendant and gantry housings instead of dropping bare neon bars into mid-air.
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "ArmoryPendantStrip" then
				local lamp = d:FindFirstChildOfClass("PointLight")
				if lamp then
					lamp.Color = Color3.fromRGB(255, 196, 128)
					lamp.Brightness = 1.05
					lamp.Range = 27
					lamp:SetAttribute("GFPractical", true)
				else
					practicalOn(d, Color3.fromRGB(255, 196, 128), 0.7, 25)
				end
			elseif d.Name == "DispatchPendantStrip" then
				practicalOn(d, Color3.fromRGB(255, 190, 116), 0.58, 24)
			elseif d.Name == "BayFillBody" then
				local lamp = d:FindFirstChildOfClass("PointLight")
				if lamp then
					lamp.Color = Color3.fromRGB(158, 214, 255)
					lamp.Brightness = 1.0
					lamp.Range = 36
					lamp:SetAttribute("GFPractical", true)
				else
					practicalOn(d, Color3.fromRGB(158, 214, 255), 0.65, 32)
				end
			end
		end
	end
	-- Corrected wall wash: the legacy pass accidentally added STATION_Y twice and placed these at
	-- y=1536. They now sit at the bulkheads and lift the wall planes without extra geometry.
	for _, spec in ipairs({ { -98.25, -40 }, { -98.25, 40 }, { 98.25, -40 }, { 98.25, 40 } }) do
		local lens = part(station, "WallWashLens", Vector3.new(0.4, 1.2, 8), base * CFrame.new(spec[1], 16, spec[2]), Color3.fromRGB(196, 220, 255), Enum.Material.Neon)
		lens.CanCollide = false
		local wash = Instance.new("PointLight")
		wash.Color = Color3.fromRGB(196, 214, 244)
		wash.Brightness = 1.15
		wash.Range = 42
		wash.Shadows = false
		wash:SetAttribute("GFPractical", true)
		wash.Parent = lens
	end
	for _, sx in ipairs({ -1, 1 }) do
		local cove = neon(station, "CeilingCove", Vector3.new(1.1, 0.35, 150), base * CFrame.new(sx * 97, 34.4, 0), Color3.fromRGB(150, 202, 244))
		cove.Transparency = 0.35
	end

	-- Priority dispatch is a readable workstation, not just a word on the wall. The physical desk
	-- itself is StationArt's detailed dispatch alcove; this adds the operational status board.
	local oldDispatchSign = station:FindFirstChild("Sign_DISPATCH")
	if oldDispatchSign then
		oldDispatchSign:Destroy()
	end
	-- x=98.6 put the sign's visible face inside the x=98.5 bulkhead skin; 97.95 leaves a slim
	-- mounted shadow gap while keeping the plate legible from the concourse.
	sign("PRIORITY DISPATCH", 26, 3.7, base * CFrame.new(97.95, 15.5, -28) * CFrame.Angles(0, math.rad(90), 0), Enum.NormalId.Front, AMBER)
	local dispatchBoard = part(station, "DispatchStatusBoard", Vector3.new(0.55, 9.5, 16), base * CFrame.new(98.05, 14.5, -43), Color3.fromRGB(8, 13, 19), Enum.Material.SmoothPlastic)
	dispatchBoard.CanCollide = false
	local dispatchGui = Instance.new("SurfaceGui")
	dispatchGui.Name = "DispatchStatusGui"
	dispatchGui.Face = Enum.NormalId.Left
	dispatchGui.CanvasSize = Vector2.new(520, 300)
	dispatchGui.LightInfluence = 0
	dispatchGui.Parent = dispatchBoard
	local dispatchTitle = Instance.new("TextLabel")
	dispatchTitle.Size = UDim2.new(1, -32, 0, 58)
	dispatchTitle.Position = UDim2.fromOffset(16, 14)
	dispatchTitle.BackgroundTransparency = 1
	dispatchTitle.Font = Enum.Font.GothamBold
	dispatchTitle.TextSize = 28
	dispatchTitle.TextXAlignment = Enum.TextXAlignment.Left
	dispatchTitle.TextColor3 = AMBER
	dispatchTitle.Text = "PRIORITY DISPATCH"
	dispatchTitle.Parent = dispatchGui
	local dispatchBody = Instance.new("TextLabel")
	dispatchBody.Name = "Body"
	dispatchBody.Size = UDim2.new(1, -32, 1, -84)
	dispatchBody.Position = UDim2.fromOffset(16, 74)
	dispatchBody.BackgroundTransparency = 1
	dispatchBody.Font = Enum.Font.RobotoMono
	dispatchBody.TextSize = 18
	dispatchBody.TextWrapped = true
	dispatchBody.TextXAlignment = Enum.TextXAlignment.Left
	dispatchBody.TextYAlignment = Enum.TextYAlignment.Top
	dispatchBody.TextColor3 = Color3.fromRGB(186, 204, 218)
	dispatchBody.Text = "SCANNING RELAY NETWORK"
	dispatchBody.Parent = dispatchGui
	for _, zoff in ipairs({ -8.4, 8.4 }) do
		local edge = neon(station, "DispatchBoardEdge", Vector3.new(0.18, 9.8, 0.28), base * CFrame.new(97.72, 14.5, -43 + zoff), AMBER)
		edge.Transparency = 0.35
	end
	task.spawn(function()
		while dispatchBoard.Parent do
			local count = tonumber(workspace:GetAttribute("GF_DispatchCount")) or 0
			if count > 0 then
				dispatchBody.Text = string.format("LIVE DISTRESS BEACONS  %d\nRESPONSE SEATS ARE CROSS-SERVER\nREPORT TO DEPARTURE PAD AFTER ACCEPT", count)
			else
				dispatchBody.Text = "NO ACTIVE DISTRESS BEACONS\nRELAY NETWORK NOMINAL\nMANUAL REQUEST VIA OPERATIONS MENU"
			end
			task.wait(5)
		end
	end)

	-- Personnel / cosmetics terminal on the port aft wall. It is a physical identity station:
	-- pedestal, scan screen, armor display and a warm work light. (The actual profile UI remains
	-- owned by its services; this is the place where a player expects to use it.)
	local profileCF = base * CFrame.new(-94.8, 0, 52)
	part(station, "ProfileTerminal", Vector3.new(4.8, 3.2, 5.2), profileCF * CFrame.new(0, 1.6, 0), DARK, Enum.Material.Metal)
	part(station, "ProfileTerminalLedge", Vector3.new(2.4, 0.55, 5.8), profileCF * CFrame.new(2.2, 3.35, 0), STEEL, Enum.Material.Metal)
	local profileScreen = part(station, "ProfileTerminalScreen", Vector3.new(0.35, 4.2, 5.8), profileCF * CFrame.new(2.8, 5.7, 0), Color3.fromRGB(8, 15, 22), Enum.Material.SmoothPlastic)
	profileScreen.CanCollide = false
	local profileGui = Instance.new("SurfaceGui")
	profileGui.Face = Enum.NormalId.Right
	profileGui.CanvasSize = Vector2.new(420, 300)
	profileGui.LightInfluence = 0
	profileGui.Parent = profileScreen
	local profileTitle = Instance.new("TextLabel")
	profileTitle.Size = UDim2.new(1, -28, 0, 62)
	profileTitle.Position = UDim2.fromOffset(14, 16)
	profileTitle.BackgroundTransparency = 1
	profileTitle.Font = Enum.Font.GothamBold
	profileTitle.TextSize = 30
	profileTitle.TextXAlignment = Enum.TextXAlignment.Left
	profileTitle.TextColor3 = CYAN
	profileTitle.Text = "PERSONNEL"
	profileTitle.Parent = profileGui
	local profileBody = Instance.new("TextLabel")
	profileBody.Size = UDim2.new(1, -28, 1, -88)
	profileBody.Position = UDim2.fromOffset(14, 82)
	profileBody.BackgroundTransparency = 1
	profileBody.Font = Enum.Font.RobotoMono
	profileBody.TextSize = 18
	profileBody.TextWrapped = true
	profileBody.TextXAlignment = Enum.TextXAlignment.Left
	profileBody.TextYAlignment = Enum.TextYAlignment.Top
	profileBody.TextColor3 = Color3.fromRGB(190, 204, 214)
	profileBody.Text = "SERVICE RECORD\nARMOR COSMETICS\nLOADOUT PROFILE\n\nSCAN REQUIRED"
	profileBody.Parent = profileGui
	flat("ProfileFloorMat", Vector3.new(7.5, 0.08, 8), base * CFrame.new(-91.5, 1.1, 52), NAVY, Enum.Material.SmoothPlastic, 0.08)
	for index = 0, 3 do
		local scan = neon(station, "ProfileScanline", Vector3.new(0.08, 0.08, 4.8), profileCF * CFrame.new(3.02, 4.4 + index * 0.75, 0), CYAN)
		scan.Transparency = 0.42 + index * 0.08
	end
	-- small armor display beside the terminal: ceramic plates over graphite, not a mannequin army
	local displayX, displayZ = -94.3, 61
	part(station, "CosmeticDisplayPlinth", Vector3.new(4.2, 0.45, 4.2), base * CFrame.new(displayX, 1, displayZ), DARK, Enum.Material.Metal)
	part(station, "CosmeticDisplayTorso", Vector3.new(2.1, 2.5, 1.25), base * CFrame.new(displayX, 4.1, displayZ), NAVY, Enum.Material.Fabric)
	part(station, "CosmeticDisplayChest", Vector3.new(0.32, 1.25, 2), base * CFrame.new(displayX + 1.1, 4.35, displayZ), CERAMIC, Enum.Material.SmoothPlastic)
	part(station, "CosmeticDisplayHead", Vector3.new(1.2, 1.2, 1.2), base * CFrame.new(displayX, 6, displayZ), NAVY, Enum.Material.Fabric)
	local visor = neon(station, "CosmeticDisplayVisor", Vector3.new(0.18, 0.28, 0.9), base * CFrame.new(displayX + 0.68, 6.05, displayZ), CYAN)
	visor.Transparency = 0.18
	for _, zoff in ipairs({ -1.45, 1.45 }) do
		part(station, "CosmeticDisplayPauldron", Vector3.new(1, 0.55, 1.1), base * CFrame.new(displayX, 5.05, displayZ + zoff), CERAMIC, Enum.Material.SmoothPlastic)
	end
	practical(base * Vector3.new(-91, 10.5, 56), Vector3.new(3.2, 0.35, 1.2), Color3.fromRGB(255, 204, 145))
	sign("PERSONNEL", 18, 3, base * CFrame.new(-98.55, 13.5, 54) * CFrame.Angles(0, math.rad(-90), 0), Enum.NormalId.Front, CYAN)

	-- Archive replay console is created later by start() at (-30, 771, -30) and cannot move. It is
	-- intentionally dressed as a ceiling-suspended cinematic display above the Verdant terminal,
	-- which both explains its height and keeps the deck clear around the deployment console.
	-- The mast belongs on the console's rear edge. Centering it on the console axis put a dark
	-- column straight through the luminous replay screen, making the suspended display read broken
	-- rather than mounted.
	part(station, "ArchiveSuspensionMast", Vector3.new(1.15, 21.9, 1.15), base * CFrame.new(-30, 23.55, -27.45), DARK, Enum.Material.Metal)
	part(station, "ArchiveCeilingMount", Vector3.new(5.8, 0.8, 5.8), base * CFrame.new(-30, 34.2, -27.45), STEEL, Enum.Material.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		part(station, "ArchiveBrace", Vector3.new(0.5, 4.6, 0.5), base * CFrame.new(-30 + sx * 2.2, 15.2, -27.7) * CFrame.Angles(0, 0, math.rad(sx * 18)), STEEL, Enum.Material.Metal)
	end
	local archiveLamp = neon(station, "ArchiveDownlight", Vector3.new(2.4, 0.28, 2.4), base * CFrame.new(-30, 12.7, -28.35), CYAN)
	archiveLamp.Transparency = 0.34
	practicalOn(archiveLamp, CYAN, 0.5, 16)
	sign("ARCHIVE / CINEMATIC RECORD", 18, 2.4, base * CFrame.new(-30, 18.3, -28.8) * CFrame.Angles(0, math.pi, 0), Enum.NormalId.Front, CYAN)

	-- armory racks in the wing. These positions/sizes/names are interactive contracts:
	-- ArmoryService finds ArmoryRack and clients use nearest-rack proximity. Do not move them.
	-- The contract volume is a solid slab, so add one coarse front frame and shelf rails; without
	-- those edges the three racks read as pale refrigerators rather than weapon storage.
	for i = -1, 1 do
		local rackCF = base * CFrame.new(-112, 0, i * 26)
		part(station, "ArmoryRack", Vector3.new(2, 16, 18), rackCF * CFrame.new(0, 8, 0), NAVY, Enum.Material.Metal)
		for _, zoff in ipairs({ -8.55, 8.55 }) do
			local upright = part(station, "ArmoryRackFrame", Vector3.new(0.34, 15.4, 0.5), rackCF * CFrame.new(1.08, 8, zoff), STEEL, Enum.Material.Metal)
			upright.CanCollide = false
		end
		for _, shelfY in ipairs({ 4, 8, 12 }) do
			local shelf = part(station, "ArmoryRackShelf", Vector3.new(0.34, 0.42, 17.2), rackCF * CFrame.new(1.08, shelfY - 0.75, 0), STEEL, Enum.Material.Metal)
			shelf.CanCollide = false
		end
		for j = -1, 1 do
			part(station, "Rifle", Vector3.new(0.8, 1.2, 7), rackCF * CFrame.new(1.4, 8 + j * 4, 0), Color3.fromRGB(30, 34, 42), Enum.Material.Metal)
			neon(station, "RifleGlow", Vector3.new(0.3, 0.3, 2), rackCF * CFrame.new(2, 8 + j * 4, -2), CYAN)
		end
	end

	-- deployment pad + staged dropship silhouette. DeployPad itself is a gameplay landmark and is
	-- unchanged in name, center and dimensions.
	local padCF = base * CFrame.new(0, 0, 74)
	local pad = part(station, "DeployPad", Vector3.new(34, 1.2, 34), padCF * CFrame.new(0, 0.6, 0), DARK, Enum.Material.DiamondPlate)
	pad:SetAttribute("GFStationPad", true)
	-- Park StationArt's drop-pod dressing to port as a serviced vehicle so the centre of the
	-- formation pad is clear for players and the animated dropship.
	local podShift = {
		PodCradle = true, PodHull = true, PodHullPlate = true, PodNose = true,
		PodHatchFrame = true, PodHatch = true, PodHatchLamp = true, PodSideStripe = true,
		PodStep = true, PodThruster = true, GantryBeam = true, GantryChain = true,
		GantryHook = true, GantryFlood = true, GantryLeg = true,
	}
	local deploymentDressing = station:FindFirstChild("DeploymentBay")
	if deploymentDressing then
		for _, d in ipairs(deploymentDressing:GetDescendants()) do
			if d:IsA("BasePart") and podShift[d.Name] then
				d.CFrame = d.CFrame + Vector3.new(-28, 0, 0)
			end
		end
	end
	-- The filled 36x36 neon pad read as a lit floor slab rather than a marker. A thin sheen plus
	-- three edge bars are enough; the rest of the language is hazard paint and formation ticks.
	local ring = neon(station, "PadRing", Vector3.new(36, 0.4, 18), padCF * CFrame.new(0, 1.3, -9), CYAN)
	ring.Transparency = 0.94
	-- Only the threshold pair belongs inside the room. The nominal aft corners are z=89, behind
	-- the sealed rear hull; posts there were pure invisible part cost.
	for _, corner in { Vector3.new(-15, 0, -15), Vector3.new(15, 0, -15) } do
		part(station, "PadPost", Vector3.new(1.6, 10, 1.6), padCF * CFrame.new(corner.X, 5, corner.Z), PLATE, Enum.Material.Metal)
		neon(station, "PadPostLight", Vector3.new(2, 0.6, 2), padCF * CFrame.new(corner.X, 10.2, corner.Z), CYAN)
	end
	-- a U-shaped marker for the usable half of the pad: front bar plus two short side returns ending
	-- at the door plane. The original fourth bar and most of both returns were inside the rear wall.
	for _, spec in ipairs({ { 36, 1.4, 0, -17.3 }, { 1.4, 17, 17.3, -8.8 }, { 1.4, 17, -17.3, -8.8 } }) do
		local bar = neon(station, "PadRingBar", Vector3.new(spec[1], 0.3, spec[2]), padCF * CFrame.new(spec[3], 1.35, spec[4]), CYAN)
		bar.Transparency = 0.45
	end
	-- rail extensions lead the eye from concourse to the cradle without duplicating StationArt's rails
	for _, sx in ipairs({ -5, 5 }) do
		local rail = part(station, "LoadingRailExtension", Vector3.new(0.9, 0.45, 21), padCF * CFrame.new(sx, 0.92, -31), Color3.fromRGB(58, 64, 74), Enum.Material.Metal)
		rail.CanCollide = false
		for t = 0, 2 do
			neon(station, "RailTieLight", Vector3.new(1.6, 0.12, 0.5), padCF * CFrame.new(sx, 1.19, -39 + t * 6), Color3.fromRGB(88, 184, 232))
		end
	end
	-- hazard threshold where the squad enters the pad
	for index = 0, 9 do
		local x = -15 + index * 3.35
		flat("DepartureHazardStripe", Vector3.new(2.7, 0.09, 1.8), padCF * CFrame.new(x, 1.26, -18.8), if index % 2 == 0 then AMBER else Color3.fromRGB(26, 29, 34), Enum.Material.SmoothPlastic, 0.04)
	end
	-- four squad formation marks: restrained ceramic blocks with one cyan inner tick each
	for index = 0, 3 do
		local x = (index - 1.5) * 6
		flat("SquadFormationMark", Vector3.new(3.2, 0.08, 1), padCF * CFrame.new(x, 1.25, -27), CERAMIC, Enum.Material.SmoothPlastic, 0.28)
		flat("SquadFormationTick", Vector3.new(0.55, 0.09, 3), padCF * CFrame.new(x + 1.3, 1.27, -27), CYAN, Enum.Material.Neon, 0.45)
	end

	-- Compact utility dropship hanging in the bay. It is composed rather than one colored box:
	-- armored hull, glass cockpit, spine, wings, nacelles, tail and restrained engine glow. The
	-- hull is the anchored weld root; the whole craft bobs subtly as a single assembly.
	local shipModel = Instance.new("Model")
	shipModel.Name = "HangarDropship"
	shipModel.Parent = station
	-- Keep the tail clear of the sealed bay leaves: at z=-10 the engine housings ended half inside
	-- the rear bulkhead. Three studs forward leaves a visible maintenance gap and keeps the nose off
	-- the squad formation ticks.
	local shipHome = padCF * CFrame.new(0, 15, -13)
	local shipPieces = {}
	local engineGlows = {}
	local function shipPiece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
		local p = part(shipModel, name, size, shipHome * offset, color, material)
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		table.insert(shipPieces, p)
		return p
	end
	local hull = shipPiece("Dropship", Vector3.new(14, 4.2, 20), CFrame.new(0, 0, 0), NAVY, Enum.Material.Metal)
	shipModel.PrimaryPart = hull
	shipPiece("DropshipNose", Vector3.new(10, 3, 5), CFrame.new(0, -0.1, -11), DARK, Enum.Material.Metal)
	-- Let the glass canopy protrude past the nose instead of sitting fully inside it; from the deck
	-- the canopy is the one cue that reads "aircraft" rather than a pair of floating crates.
	local cockpit = shipPiece("DropshipCockpit", Vector3.new(6.5, 2, 3.5), CFrame.new(0, 0.8, -12.1), Color3.fromRGB(28, 82, 108), Enum.Material.Glass)
	cockpit.Transparency = 0.28
	shipPiece("DropshipSpine", Vector3.new(7, 1.2, 10), CFrame.new(0, 2.55, 1), STEEL, Enum.Material.Metal)
	shipPiece("DropshipKeel", Vector3.new(8, 1, 12), CFrame.new(0, -2.35, 1), DARK, Enum.Material.Metal)
	shipPiece("DropshipCargoHatch", Vector3.new(6, 0.22, 5), CFrame.new(0, -2.95, 0.5), Color3.fromRGB(28, 34, 42), Enum.Material.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		shipPiece("DropshipServiceSkid", Vector3.new(0.8, 0.55, 10), CFrame.new(sx * 4.1, -3.25, -0.5), STEEL, Enum.Material.Metal)
	end
	shipPiece("DropshipTail", Vector3.new(1, 4.5, 5), CFrame.new(0, 4, 6), STEEL, Enum.Material.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		shipPiece("DropshipWing", Vector3.new(11, 1, 7), CFrame.new(sx * 9, -0.4, 2) * CFrame.Angles(0, 0, math.rad(sx * -5)), DARK, Enum.Material.Metal)
		shipPiece("DropshipNacelle", Vector3.new(3.8, 2.8, 6), CFrame.new(sx * 7, -0.2, 7), NAVY, Enum.Material.Metal)
		local glow = shipPiece("DropshipEngine", Vector3.new(2.8, 2, 0.7), CFrame.new(sx * 7, -0.2, 10.4), CYAN, Enum.Material.Neon)
		glow.Transparency = 0.2
		table.insert(engineGlows, glow)
		local tip = shipPiece("DropshipWingtipLight", Vector3.new(0.45, 0.45, 3), CFrame.new(sx * 15, -0.1, 2), if sx < 0 then Color3.fromRGB(255, 105, 96) else Color3.fromRGB(105, 235, 155), Enum.Material.Neon)
		tip.Transparency = 0.18
	end
	shipPiece("DropshipNoseStripe", Vector3.new(5.5, 0.18, 0.28), CFrame.new(0, 0.5, -13.6), CERAMIC, Enum.Material.SmoothPlastic)
	for _, p in ipairs(shipPieces) do
		if p ~= hull then
			p.Anchored = false
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hull
			weld.Part1 = p
			weld.Parent = hull
		end
	end
	task.spawn(function()
		while shipModel.Parent do
			local t = os.clock()
			-- Pivot the model, not just the anchored hull: welding does not guarantee that a direct
			-- hull CFrame write drags every visual piece with it in edit/play validation.
			shipModel:PivotTo(shipHome
				* CFrame.new(0, math.sin(t * 0.65) * 0.28, 0)
				* CFrame.Angles(math.rad(math.sin(t * 0.43) * 0.8), math.rad(math.sin(t * 0.21) * 1.3), math.rad(math.sin(t * 0.5) * 0.6)))
			local pulse = 0.2 + 0.18 * (0.5 + 0.5 * math.sin(t * 5.2))
			for _, glow in ipairs(engineGlows) do
				glow.Transparency = pulse
			end
			task.wait(1 / 10)
		end
	end)
	sign("DEPARTURE PAD", 22, 3.6, base * CFrame.new(0, 25.5, 72.8), Enum.NormalId.Front, AMBER)
	sign("WAR TABLE", 18, 3.2, base * CFrame.new(0, 12, -34) * CFrame.Angles(0, math.rad(180), 0), Enum.NormalId.Front, CYAN)

	return station
end

function StationService.zoneOf(player: Player): string
	return zone[player] or "Station"
end

-- template/difficulty gates hoisted above resetMission: the op-mode gate references
-- VALID_TEMPLATES lexically, and Luau locals are not forward-visible.
local TEMPLATE_RANK = { CONQUEST_THRONEFALL = 10 }
local DIFFICULTY_RANK = { Easy = 1, Normal = 3, Hard = 6, Extreme = 14 }
local VALID_TEMPLATES = { SABOTAGE_RELAY = true, RECOVER_TECH = true, DEFEND_BEACON = true,
	ELIM_COMMANDER = true, ELIM_WALKER = true, ELIM_TALON = true,
	RECOVERY_ARCHIVE = true, SABOTAGE_ARSENAL = true, DEFENSE_POWER = true, RECOVERY_CONVOY = true, DEFENSE_UPLINK = true, SABOTAGE_AEGIS = true, CONQUEST_DOMINION = true, CONQUEST_FOUNDRY = true, CONQUEST_THRONEFALL = true }

function StationService.resetMission(missionDifficulty: string, template: string?)
	template = template or "SABOTAGE_RELAY"
	difficulty = missionDifficulty
	workspace:SetAttribute("GF_OperationTemplate", template)
	workspace:SetAttribute("GF_OperationDifficulty", missionDifficulty)
	workspace:SetAttribute("GF_ObjectiveComplete", false)
	workspace:SetAttribute("GF_ExtractionState", "idle")
	workspace:SetAttribute("GF_LastPayout", nil)
	workspace:SetAttribute("GF_MissionEndReason", nil)
	-- operation layer reset: clears the DAG state and destroys operation sites. Unconditional —
	-- a legacy mission following an operation must not inherit operation structures.
	pcall(function()
		require(script.Parent.OperationService).reset()
	end)
	SquadService.reset()
	ExtractionService.reset()
	-- A redeploy used to leave the previous mission's hostiles standing: clearAll only ran on
	-- extraction, so actors piled up and every target count read high. This runs before setup so the
	-- new mission's own spawns (including elimination targets) are the only ones alive.
	EnemyService.clearAll()
	clearUntaggedBosses()
	-- operation mode: conquest templates are generated as multi-site operations on the real
	-- geography; the legacy single-site objective (and its outpost) must not double-build.
	local opMode = workspace:GetAttribute("GF_OperationMode") == true
		and type(template) == "string" and VALID_TEMPLATES[template] == true
	if not opMode then
		ObjectiveService.setup(RELAY, template)
	else
		-- completion flags still flow through the legacy singleton's complete() handoff,
		-- but no physical objective is constructed — the operation layer owns the sites.
		ObjectiveService.resetState()
		workspace:SetAttribute("GF_WarCommitted", false)
		pcall(function()
			require(script.Parent.RewardLedgerService).begin(template)
		end)
	end
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
	-- elevation-aware origin: mountain-valley geography can exceed the legacy fixed 500-stud
	-- start (high valleys reach 600+). Operation positions carry real terrain elevation in p.Y;
	-- the station underside (~760) bounds how high we may start, so cap the lift there.
	local originY = math.max(500, math.min(p.Y + 80, 740))
	local hit = workspace:Raycast(Vector3.new(p.X, originY, p.Z), Vector3.new(0, -1400, 0), params)
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
	local wasLongMove = false
	if root then
		wasLongMove = (root.Position - position).Magnitude > 500
	end
	if root then
		-- streaming-aware long teleport (validation root cause: 2000-stud operation deployments
		-- exceeded the streaming radius — client-side terrain absent, the character fell through
		-- the world and respawned at the station). For long moves: request streaming at the
		-- destination, anchor through the transition so physics cannot drop the character, and
		-- release only after the stream-in window. The loading overlay already covers this pause.
		local longMove = wasLongMove
		if longMove then
			-- stream FIRST, pivot after: RequestStreamAroundAsync returns when the destination
			-- region has replicated (or the timeout elapses). 2000 studs of mountain terrain
			-- needs seconds, not the original 1.5 — validation evidence: character fell through
			-- unstreamed terrain even with the 1.4s anchor.
			pcall(function()
				player:RequestStreamAroundAsync(position, 3.5)
			end)
		end
		character:PivotTo(CFrame.new(position))
		if longMove then
			root.Anchored = true
			-- hold the anchor through the post-pivot replication settle; the loading overlay
			-- covers the pause. Release is unconditional — a stuck anchor is worse than a fall.
			task.delay(4, function()
				if root.Parent then
					root.Anchored = false
				end
			end)
		end
	end
	-- overlay duration matches the transition: long moves hold the loading screen
	-- until the anchor release, short hops keep the snappy 1.2s
	local overlaySeconds = wasLongMove and 4.2 or 1.2
	task.delay(overlaySeconds, function()
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

function StationService.deploy(player: Player, missionDifficulty: string?, template: string?, operationId: string?): (boolean, string?)
	-- operation-centric deployment (Counteroffensive): when an operation instance is chosen it is
	-- authoritative — the template resolves server-side from the operation definition, so the
	-- client cannot assert a mismatched template/region pair
	if type(operationId) == "string" and operationId ~= "" then
		local resolved = nil
		pcall(function()
			local WarOperations = require(ReplicatedStorage.GF.Shared.Configs.WarOperations)
			resolved = WarOperations.templateFor(operationId)
		end)
		if resolved then
			template = resolved
		else
			operationId = nil -- unknown operation: fall back to template semantics, no war tag
		end
	end
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
		-- join-in-progress (stage 9): when the squad already generated this operation and it
		-- hasn't terminally resolved, a later deployer drops into the SAME operation. The
		-- naive path regenerated on every deploy — a second squadmate deploying wiped the
		-- first player's in-progress operation out from under them.
		local joinExisting = false
		if workspace:GetAttribute("GF_OperationMode") == true then
			local exState = workspace:GetAttribute("GF_ExtractionState")
			if exState ~= "complete" and exState ~= "failed" then
				local opOk, cur = pcall(function()
					return require(script.Parent.OperationService).current()
				end)
				if opOk and cur and cur.template == template then
					joinExisting = true
				end
			end
		end
		if not joinExisting then
			-- the player picked a mission: rebuild the objective for it. Without this the boot-time
			-- relay stayed in the world and every template played as SABOTAGE_RELAY.
			StationService.resetMission(missionDifficulty or difficulty, template)
		end
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
	-- place-split migration: when terrain analysis picked valley-floor anchors (mission-server
	-- boot path), the LZ anchor overrides the legacy fixed spawn. Absent = legacy behavior.
	do
		local lzAnchor = workspace:GetAttribute("GF_AnchorLZ")
		if typeof(lzAnchor) == "Vector3" then
			spawnTarget = lzAnchor
		end
	end
	do
		local bfOk, bfTerrain = pcall(require, script.Parent.TerrainService)
		local plan = bfOk and bfTerrain.currentPlan or nil
		if workspace:GetAttribute("GF_BattlefieldGen") == true and plan and plan.nodes and plan.nodes.lz then
			spawnTarget = Vector3.new(plan.nodes.lz.x, 0, plan.nodes.lz.z)
		end
	end
	-- Operation mode (hybrid procedural operations, directive 2026-11-26): when enabled and the
	-- template is a conquest variant, the authoritative operation layer generates the mission
	-- layout on the real geography — deployment region, objective sites, extraction — and the
	-- player deploys at the operation deployment region (~1km separation from primary).
	if workspace:GetAttribute("GF_OperationMode") == true and template and VALID_TEMPLATES[template] == true then
		local opOk, opErr = pcall(function()
			local OperationService = require(script.Parent.OperationService)
			local seed = math.floor(os.clock() * 1000) % 90000 + 1000
			-- honor a pinned seed for deterministic validation when set
			local pinned = workspace:GetAttribute("GF_OperationSeed")
			if type(pinned) == "number" and pinned > 0 then seed = pinned end
			local def = OperationService.generate(seed, template, tostring(missionDifficulty or difficulty or "Normal"))
			if def then
				OperationService.activate(def)
			else
				warn("OperationService: generation returned nil — falling back to legacy mission")
			end
		end)
		if not opOk then warn("OperationService deploy integration failed:", opErr) end
		local opLZ = workspace:GetAttribute("GF_OperationLZ")
		if typeof(opLZ) == "Vector3" then
			-- preserve elevation: mountain-valley deployment zones carry real terrain Y and
			-- groundPoint's elevation-aware origin depends on it
			spawnTarget = Vector3.new(opLZ.X, opLZ.Y, opLZ.Z)
		end
	end
	-- place-split activation (guarded — GF_PlaceSplitLive default off): when live AND a mission
	-- place exists, deployment teleports the player into a mission server carrying the intent
	-- contract, instead of repositioning inside this shared place. Everything below is the
	-- legacy in-place path and stays authoritative until the flag flips.
	if workspace:GetAttribute("GF_PlaceSplitLive") == true then
		local missionPlaceId = workspace:GetAttribute("GF_MissionPlaceId")
		if type(missionPlaceId) == "number" and missionPlaceId > 0 and missionPlaceId ~= game.PlaceId then
			-- squad-coherent deploy: every member crosses with ONE shared intent contract —
			-- same seed (same generated world), same template/difficulty, full squad roster so
			-- the mission server can reconstruct membership. teleporting the whole squad in a
			-- single TeleportAsync keeps them in the same server instance.
			local squadOk, squad = pcall(function() return require(script.Parent.SquadService).memberList() end)
			if not squadOk or type(squad) ~= "table" then
				warn("[GF] place-split squad enumeration failed:", squad)
				squad = {}
			end
			local travelling = {}
			local userIds = {}
			for _, member in ipairs(squad) do
				table.insert(travelling, member)
				table.insert(userIds, member.UserId)
			end
			-- the deployer is always in the manifest even if squad membership lagged
			if not table.find(userIds, player.UserId) then
				table.insert(travelling, player)
				table.insert(userIds, player.UserId)
			end
			-- resolve war tagging BEFORE encoding: the contract must carry the operation/region
			-- THIS deploy committed to. reading workspace attributes here picks up whatever a
			-- previous deploy left behind — the authoritative writes below happen only after the
			-- teleport has already fired (first deploys sent empty tags; later deploys sent stale ones).
			local contractOperationId = nil
			local contractRegionId = nil
			if type(operationId) == "string" and operationId ~= "" then
				contractOperationId = operationId
				pcall(function()
					local WarModel = require(ReplicatedStorage.GF.Shared.WarModel)
					local opdef = WarModel.OPERATIONS[operationId]
					contractRegionId = opdef and opdef.region or nil
				end)
			end
			local intentSeed = (os.time() * 997 + math.random(1, 99999)) % 900000 + 1
			local payload
			pcall(function()
				local DeployContract = require(game:GetService("ReplicatedStorage").GF.Shared.DeployContract)
				payload = DeployContract.encode({
					v = 1,
					seed = intentSeed,
					difficulty = tostring(missionDifficulty or difficulty or "Normal"),
					template = template or "SABOTAGE_RELAY",
					squadUserIds = userIds,
					lobbyPlaceId = game.PlaceId,
					-- additive contract fields (schema v1 tolerates extras): war contribution
					-- crediting needs the exact operation/region the squad committed to
					operationId = contractOperationId,
					regionId = contractRegionId,
				} :: any)
			end)
			if payload then
				-- TeleportAsync failure is ASYNCHRONOUS: pcall success means nothing; failure arrives
				-- later via TeleportInitFailed. Fire the teleport AND let the legacy in-place deploy
				-- below run regardless — if the teleport lands the squad is gone and the in-place
				-- state is irrelevant; if it silently dies they are deployed, not stranded in the
				-- lobby (verified broken in published game 2026-11-28: return-early stranded players).
				-- TeleportAsync YIELDS for seconds inside the deploy handler — the client's deploy
				-- watchdog fires "no response" at 8s while the server is still parked in the call.
				-- Fire it in its own thread: deploy continues into the in-place path immediately
				-- and the teleport either claims the player or doesn't, on its own clock.
				task.spawn(function()
					local tpOk, tpErr = pcall(function()
						local opts = Instance.new("TeleportOptions")
						pcall(function() (opts :: any).TeleportData = payload end)
						game:GetService("TeleportService"):TeleportAsync(missionPlaceId, travelling, opts)
					end)
					print(string.format("[GF] place-split deploy attempted: squad of %d -> place %d initOk=%s err=%s", #travelling, missionPlaceId, tostring(tpOk), tostring(tpErr)))
				end)
			end
		end
	end
	local spawnPoint = groundPoint(spawnTarget)
	workspace:SetAttribute("GF_LZ", spawnPoint)
	workspace:SetAttribute("GF_InMission", true)
	zone[player] = "Mission"
	-- unique mission id for ledger/campaign dedup, plus difficulty for downstream consumers
	workspace:SetAttribute("GF_MissionId", game:GetService("HttpService"):GenerateGUID(false))
	workspace:SetAttribute("GF_MissionDifficulty", tostring(missionDifficulty or "Normal"))
	-- Theater of War operation tagging (Counteroffensive): operations are fixed geographically,
	-- so the deployed operation instance — not the reusable template — determines which region
	-- the contribution lands in. when an operationId is supplied it is authoritative: the
	-- template is resolved server-side from the operation definition and the client cannot
	-- spoof a mismatch. template-only legacy deploys clear stale tags so they can never
	-- credit the wrong region.
	if type(operationId) == "string" and operationId ~= "" then
		local regionId = nil
		pcall(function()
			local WarModel = require(ReplicatedStorage.GF.Shared.WarModel)
			local opdef = WarModel.OPERATIONS[operationId]
			regionId = opdef and opdef.region or nil
		end)
		workspace:SetAttribute("GF_OperationId", operationId)
		workspace:SetAttribute("GF_RegionId", regionId or "")
	else
		workspace:SetAttribute("GF_OperationId", "")
		workspace:SetAttribute("GF_RegionId", "")
	end
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
		-- op mode: paint the operation DAG picture for the deployer — critical for join-in-progress
		-- players, whose activation-time publish happened before they arrived
		if workspace:GetAttribute("GF_OperationMode") == true then
			pcall(function() require(script.Parent.OperationService).publishProgress(player) end)
		end
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
	-- place-split: this service IS the station. In the mission place there is no station —
	-- building a spawn brick at station altitude strands arrivals in empty sky (verified: first
	-- mission-place boot put the player at 0,766,22). Nothing here may run.
	do
		local lobbyId = workspace:GetAttribute("GF_LobbyPlaceId")
		if type(lobbyId) == "number" and lobbyId ~= game.PlaceId then
			print("[GF] StationService inert — mission place")
			return
		end
	end
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

	-- teleport failure reporting, connected ONCE per server (claude handoff note: wiring this
	-- inside deploy leaked one listener per deploy). any failure surfaces in server logs AND on
	-- the deploying player's console button via the standard refusal channel.
	pcall(function()
		game:GetService("TeleportService").TeleportInitFailed:Connect(function(plr, result, msg)
			warn(string.format("[GF] teleport FAILED for %s result=%s msg=%s", plr.Name, tostring(result), tostring(msg)))
			pcall(function()
				local dsr = ReplicatedStorage.GF.Remotes:FindFirstChild("DeployStateChanged")
				if dsr and plr.Parent then
					dsr:FireClient(plr, { ok = false, reason = "teleport " .. tostring(result) .. ": " .. tostring(msg) })
				end
			end)
		end)
	end)

	local deploy = ensureRemote("RequestDeploy", "RemoteEvent")
	if deploy then
		deploy.OnServerEvent:Connect(function(player, options)
			if not require(script.Parent.NetGuard).allow(player, "queue") then
				return
			end
			local chosen = type(options) == "table" and options.difficulty or nil
			local template = type(options) == "table" and options.template or nil
			local operationId = type(options) == "table" and options.operationId or nil
			StationService.deploy(player, type(chosen) == "string" and chosen or nil, type(template) == "string" and template or nil, type(operationId) == "string" and operationId or nil)
		end)
	end
	-- squad browser data (Counteroffensive Stage 4): global listings + live dispatch beacons
	-- in one query. difficulty filtering uses the caller's unlocked tiers server-side.
	local browser = ensureRemote("RequestSquadBrowser", "RemoteFunction")
	if browser then
		browser.OnServerInvoke = function(player)
			local out = { squads = {}, beacons = {}, estimatedWait = nil }
			pcall(function()
				local ms = require(script.Parent.MatchmakingService)
				out.squads = ms.list(nil, true)
				out.estimatedWait = ms.estimatedWait()
			end)
			pcall(function()
				out.beacons = require(script.Parent.DispatchService).listGlobal()
			end)
			return out
		end
	end
	-- squad formation: the leader declares operation+difficulty+privacy and the listing
	-- publishes globally. formation joins the leader into the server-local squad.
	local form = ensureRemote("FormSquad", "RemoteEvent")
	if form then
		form.OnServerEvent:Connect(function(player, options)
			if not require(script.Parent.NetGuard).allow(player, "default") then
				return
			end
			if type(options) ~= "table" then return end
			pcall(function()
				local ms = require(script.Parent.MatchmakingService)
				local listing = ms.createSquad(
					player,
					type(options.operationId) == "string" and options.operationId or nil,
					type(options.difficulty) == "string" and options.difficulty or "Normal",
					tonumber(options.capacity) or 4,
					options.public ~= false,
					type(options.region) == "string" and options.region or nil
				)
				if listing then
					require(script.Parent.SquadService).join(player)
				end
			end)
		end)
	end
	-- cross-server join: atomically reserve a seat, then hand the caller the host jobId.
	-- the teleport itself is client-invoked (TeleportService client call patterns vary);
	-- the seat is already theirs — a failed teleport releases nothing but also loses nothing,
	-- since the claim expires with the listing TTL and reconcileFailedTeleport covers retry.
	local join = ensureRemote("JoinSquad", "RemoteFunction")
	if join then
		join.OnServerInvoke = function(player, squadId)
			if not require(script.Parent.NetGuard).allow(player, "queue") then
				return { ok = false, reason = "rate limited" }
			end
			if type(squadId) ~= "string" then
				return { ok = false, reason = "bad id" }
			end
			local ms = require(script.Parent.MatchmakingService)
			local reserved = ms.reserveSeat(squadId, player)
			if not reserved then
				return { ok = false, reason = "squad filled or expired" }
			end
			local listing = ms.getListing(squadId)
			if not listing then
				return { ok = false, reason = "listing vanished" }
			end
			if listing.leaderJobId == game.JobId then
				-- same server: no teleport needed, join locally right now
				require(script.Parent.SquadService).join(player)
				return { ok = true, local_ = true }
			end
			-- cross-server: the seat is already theirs (claims carry their userId — the host
			-- server recognizes them on arrival). teleport server-side to the host's jobId;
			-- failure leaves the claim to expire harmlessly with the listing TTL and the
			-- player exactly where they were
			local okTp, err = pcall(function()
				game:GetService("TeleportService"):TeleportToJobId(game.PlaceId, listing.leaderJobId, player)
			end)
			if not okTp then
				warn("[GF] squad join teleport failed: " .. tostring(err))
				require(script.Parent.MatchmakingService).reconcileFailedTeleport(player)
				return { ok = false, reason = "teleport failed — retry offered" }
			end
			return { ok = true, teleporting = true }
		end
	end
	-- Emergency Dispatch response (Counteroffensive §83): claim a beacon seat in ANY server,
	-- teleport the responder across. same-server beacons fall through to the local pod-arrival
	-- path. the claim is atomic and idempotent — retry after a failed teleport loses nothing.
	local respond = ensureRemote("RespondDispatch", "RemoteFunction")
	if respond then
		respond.OnServerInvoke = function(player, beaconKey)
			if not require(script.Parent.NetGuard).allow(player, "queue") then
				return { ok = false, reason = "rate limited" }
			end
			if type(beaconKey) ~= "string" then
				return { ok = false, reason = "bad beacon" }
			end
			local ds = require(script.Parent.DispatchService)
			local claimed, hostJobId, hostPlaceId = ds.claimSeat(player, beaconKey)
			if not claimed then
				return { ok = false, reason = "beacon full or expired" }
			end
			if hostJobId == game.JobId and (hostPlaceId == nil or hostPlaceId == game.PlaceId) then
				-- same server AND same place: the arrival scanner picks the claim up within
				-- seconds — uniform handling, no special case needed here
				return { ok = true, local_ = true }
			end
			-- place-split: the beacon's host place is authoritative (missions live in their own
			-- place now); fall back to this place only for pre-split records without the field
			local targetPlace = hostPlaceId or game.PlaceId
			local okTp, err = pcall(function()
				game:GetService("TeleportService"):TeleportToJobId(targetPlace, hostJobId, player)
			end)
			if not okTp then
				warn("[GF] dispatch response teleport failed: " .. tostring(err))
				require(script.Parent.MatchmakingService).reconcileFailedTeleport(player)
				return { ok = false, reason = "teleport failed — retry offered" }
			end
			return { ok = true, teleporting = true }
		end
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

