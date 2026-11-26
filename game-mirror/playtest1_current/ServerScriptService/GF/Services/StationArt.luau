--!strict
-- StationArt: the GFS VANGUARD concourse shell.
-- Built as geometry + materials + lighting only: the station must read as the interior of a
-- real military ship with windows into space, per V2-23. Palette follows the art bible:
-- graphite / navy / steel / off-white with restrained cyan, amber only for caution.
local StationArt = {}

local GRAPHITE = Color3.fromRGB(58, 64, 72)
-- Bulkheads at 46,56,72 rendered as pure black from inside: no fixture reaches a wall 100 studs from
-- the ceiling grid, and ambient at 0.25 cannot lift an albedo that dark. Lifting the albedo is free;
-- adding wall-wash lights is not (each one costs a shadow pass on Xbox One).
local NAVY = Color3.fromRGB(84, 96, 112)
local STEEL = Color3.fromRGB(134, 140, 150)
-- deck plating: at 170 albedo under ~36 overlapping fixtures the floor clipped to white
local PLATE = Color3.fromRGB(116, 124, 134)
local OFFWHITE = Color3.fromRGB(222, 226, 228)
local CYAN = Color3.fromRGB(88, 184, 207)
local AMBER = Color3.fromRGB(224, 167, 84)
local GLASS = Color3.fromRGB(150, 196, 224)
-- caution red at module scope: the bay beacon was being handed a nil colour",
local RED = Color3.fromRGB(198, 74, 62)

local HALF_X = 100
local HALF_Z = 76
local WALL_H = 36

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

local function sign(parent: Instance, text: string, size: Vector2, cf: CFrame, color: Color3): Part
	local panel = part(parent, "Sign_" .. text, Vector3.new(size.X / 40, size.Y / 40, 0.4), cf, Color3.fromRGB(18, 22, 28), Enum.Material.SmoothPlastic)
	panel.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(size.X, size.Y)
	gui.LightInfluence = 0
	gui.Parent = panel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.Parent = gui
	return panel
end

function StationArt.buildShell(station: Instance, base: CFrame)	-- V91 review: the station's only SpawnLocation sat at z=+120 on the baseplate 760 studs below,
	-- so players never arrived on the deck. Every shell build places a spawn on the concourse itself.
	task.defer(function()
		if not station.Parent then
			return
		end
		if not station:FindFirstChild("StationSpawn") then
			local spawn = Instance.new("SpawnLocation")
			spawn.Name = "StationSpawn"
			spawn.Size = Vector3.new(9, 0.6, 9)
			spawn.CFrame = base * CFrame.new(-8, 1.05, 40)
			spawn.Anchored = true
			spawn.Neutral = true
			spawn.Transparency = 1
			spawn.CanCollide = false
			spawn.Duration = 0
			spawn.Parent = station
		end
		-- The station UI advertised a "GALACTIC WAR TABLE" that did not exist in the build: the only
		-- table code lived in StationService.build, which is never called. Build the table here so the
		-- deploy surface is a real object the camera and the proximity gate can find.
		if not station:FindFirstChild("WarTableBase") then
			local tableCF = base * CFrame.new(0, 0, -34)
			part(station, "WarTableBase", Vector3.new(30, 3.4, 30), tableCF * CFrame.new(0, 1.7, 0),
				Color3.fromRGB(56, 62, 72), Enum.Material.Metal)
			part(station, "WarTableTop", Vector3.new(34, 0.8, 34), tableCF * CFrame.new(0, 3.6, 0),
				Color3.fromRGB(124, 130, 138), Enum.Material.Metal)
			local holo = part(station, "WarHolo", Vector3.new(20, 0.16, 20), tableCF * CFrame.new(0, 4.15, 0),
				Color3.fromRGB(96, 214, 255), Enum.Material.Neon)
			holo.Transparency = 0.8
			-- Every part of the war table sat at 0.08-0.22 albedo, so the room's focal point read as a
			-- black silhouette with a blue ball on it. One soft local light makes it the lit object the
			-- "GALACTIC WAR TABLE" text promises.
			local lamp = Instance.new("PointLight")
			lamp.Brightness = 1.6
			lamp.Range = 36
			lamp.Color = Color3.fromRGB(150, 210, 255)
			lamp.Shadows = false
			lamp.Parent = holo
			holo.CanCollide = false
			local globe = part(station, "WarPlanet", Vector3.new(6, 6, 6), tableCF * CFrame.new(0, 11, 0),
				Color3.fromRGB(38, 74, 96), Enum.Material.SmoothPlastic)
			globe.Shape = Enum.PartType.Ball
			globe.CanCollide = false
			for i = 1, 6 do
				local ang = (i / 6) * math.pi * 2
				local pin = part(station, "WarPin", Vector3.new(1.2, 1.2, 1.2),
					tableCF * CFrame.new(math.cos(ang) * 11, 5.4, math.sin(ang) * 11),
					Color3.fromRGB(255, 186, 92), Enum.Material.Neon)
				pin.CanCollide = false
			end
			for _, side in ipairs({ 1, -1 }) do
				local rim = part(station, "WarRim", Vector3.new(24, 0.12, 0.5), tableCF * CFrame.new(0, 4.05, side * 12),
					Color3.fromRGB(120, 220, 255), Enum.Material.Neon)
				rim.CanCollide = false
			end
			local glow = Instance.new("PointLight")
			glow.Shadows = false
			glow.Color = Color3.fromRGB(90, 200, 255)
			glow.Brightness = 0.9
			glow.Range = 26
			glow.Parent = holo
			local spot = Instance.new("SpotLight")
			spot.Shadows = false
			spot.Color = Color3.fromRGB(210, 232, 255)
			spot.Brightness = 0.35
			spot.Range = 30
			spot.Angle = 100
			spot.Face = Enum.NormalId.Bottom
			spot.Parent = part(station, "TableLamp", Vector3.new(10, 0.6, 10), tableCF * CFrame.new(0, 26, 0),
				Color3.fromRGB(200, 220, 240), Enum.Material.Neon)
		end

		for _, other in ipairs(workspace:GetDescendants()) do
			if other:IsA("SpawnLocation") and not other:IsDescendantOf(station) then
				other.Enabled = false
			end
		end
		-- The character spawns at PlayerAdded, before the shell finishes building, so a player who joins
		-- during startup lands on the baseplate 760 studs below. Lift anyone below the deck onto it.
		local function reseat(player: Player, character: Model)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not humanoid or not root then
				return
			end
			-- The rescue exists for players who spawn before the shell and land on the empty baseplate
			-- below. It must never touch a deployed player: the mission terrain sits 700 studs under the
			-- deck, so an altitude-only test yanked the squad out of every operation that started before
			-- the shell finished (probe-verified). Mission-zone players are exempt, whatever their altitude.
			local okZone, zone = pcall(function()
				return require(game:GetService("ServerScriptService").GF.Services.StationService).zoneOf(player)
			end)
			if okZone and zone == "Mission" then
				return
			end
			-- mission participants are exempt whatever the zone table says (validation 2026-11-27:
			-- operation deployments land ~2000 studs away at low altitude; an altitude-only rescue
			-- yanked the squad back to the deck seconds after every deployment). The participant
			-- attribute is set at server-confirmed deploy and survives any require-ordering failure.
			if player:GetAttribute("GF_MissionParticipant") == true then
				return
			end
			if root.Position.Y < base.Y - 10 then
				print("[GF] reseat lifting " .. player.Name .. " zone=" .. tostring(zone) .. " participant=" .. tostring(player:GetAttribute("GF_MissionParticipant")))
				root.CFrame = base * CFrame.new(-8, 5, 40) * CFrame.Angles(0, math.rad(180), 0)
			end
		end
		for _, player in ipairs(game.Players:GetPlayers()) do
			if player.Character then
				task.spawn(reseat, player, player.Character)
			end
			player.CharacterAdded:Connect(function(character)
				task.wait(0.35)
				reseat(player, character)
			end)
		end
	end)


	-- ── floor: plates with seams, not one slab ────────────────────────────────
	part(station, "Subfloor", Vector3.new(HALF_X * 2 + 8, 6, HALF_Z * 2 + 8), base * CFrame.new(0, -3, 0), GRAPHITE, Enum.Material.Metal)
	-- Deck shades are their own values: reusing GRAPHITE for two thirds of the plates made a
	-- black-and-white checkerboard that read as holes from eye level.
	local DECK_DARK = Color3.new(0.38, 0.40, 0.43)
	local DECK_LIGHT = Color3.new(0.56, 0.58, 0.60)
	local px, pz = 10, 7
	local cellX, cellZ = (HALF_X * 2) / px, (HALF_Z * 2) / pz
	for ix = 1, px do
		for iz = 1, pz do
			local x = -HALF_X + cellX * (ix - 0.5)
			local z = -HALF_Z + cellZ * (iz - 0.5)
			local shade = if (ix + iz) % 3 == 0 then DECK_LIGHT else DECK_DARK
			local plate = part(station, "FloorPlate", Vector3.new(cellX - 0.6, 0.7, cellZ - 0.6), base * CFrame.new(x, 0.35, z), shade, Enum.Material.Metal)
			plate.CanCollide = true
		end
	end
	-- deck markings: a centre line to the war table and hazard band at the bay
	local deckLine = part(station, "DeckLine", Vector3.new(1.1, 0.12, 74), base * CFrame.new(0, 0.75, 24), AMBER, Enum.Material.SmoothPlastic)
	deckLine.CanCollide = false
	for i = -2, 2 do
		part(station, "DeckChevron", Vector3.new(5, 0.12, 1.1), base * CFrame.new(i * 7, 0.75, 60), AMBER, Enum.Material.SmoothPlastic)
	end

	-- ── side bulkheads with ribs and panel variation ─────────────────────────
	for _, sx in { -1, 1 } do
		part(station, "Bulkhead", Vector3.new(3, WALL_H, HALF_Z * 2), base * CFrame.new(sx * HALF_X, WALL_H / 2, 0), NAVY, Enum.Material.Metal)
		part(station, "BulkheadBase", Vector3.new(4.5, 5, HALF_Z * 2), base * CFrame.new(sx * HALF_X, 2.5, 0), STEEL, Enum.Material.Metal)
		for iz = -3, 3 do
			local z = iz * 20
			part(station, "Rib", Vector3.new(2.6, WALL_H, 2.6), base * CFrame.new(sx * (HALF_X - 2.2), WALL_H / 2, z), STEEL, Enum.Material.Metal)
			-- 0.25-transparency neon bars on both walls blew out through Bloom and smeared a warm wash across
			-- the deck paint (captures V240-V244). 0.55 keeps the accent and stops the glow.
			neon(station, "RibLight", Vector3.new(0.28, 20, 0.28), base * CFrame.new(sx * (HALF_X - 3.6), 17, z), CYAN).Transparency = 0.55
		end
		-- maintenance panels and cable runs
		for iz = -2, 2 do
			part(station, "ServicePanel", Vector3.new(0.5, 8, 10), base * CFrame.new(sx * (HALF_X - 1.6), 8, iz * 26 + 8), Color3.fromRGB(96, 102, 112), Enum.Material.Metal)
		end
	end

	-- ── rear bulkhead with the deployment bay ────────────────────────────────
	part(station, "RearWall", Vector3.new(HALF_X * 2, WALL_H, 3), base * CFrame.new(0, WALL_H / 2, HALF_Z), NAVY, Enum.Material.Metal)
	local doorCF = base * CFrame.new(0, 0, HALF_Z - 1.4)
	part(station, "BayDoor", Vector3.new(30, 22, 2.2), doorCF * CFrame.new(0, 11, 0), GRAPHITE, Enum.Material.Metal)
	neon(station, "BayDoorSeal", Vector3.new(31, 0.7, 0.6), doorCF * CFrame.new(0, 22.2, -0.6), AMBER).Transparency = 0.2
	for _, sx in { -1, 1 } do
		neon(station, "BayDoorSealV", Vector3.new(0.7, 22, 0.6), doorCF * CFrame.new(sx * 15.2, 11, -0.6), AMBER).Transparency = 0.2
	end
	sign(station, "BAY 02", Vector2.new(600, 140), doorCF * CFrame.new(0, 26, -1.2) * CFrame.Angles(0, math.pi, 0), OFFWHITE)

	-- ── ceiling: girders + light strips ──────────────────────────────────────
	part(station, "Ceiling", Vector3.new(HALF_X * 2 + 6, 2, HALF_Z * 2 + 6), base * CFrame.new(0, WALL_H, 0), GRAPHITE, Enum.Material.Metal)
	for iz = -3, 3 do
		local z = iz * 20
		part(station, "Girder", Vector3.new(HALF_X * 2, 2.4, 3), base * CFrame.new(0, WALL_H - 1.4, z), STEEL, Enum.Material.Metal)
	end
	-- fixtures: thin warm strips with real downward spots. Wide emissive panels were washing
	-- the whole room blue and killing every material; shadows on the middle pair give the
	-- floor depth instead of a flat glow.
	for ix = -2, 2 do
		for iz = -2, 2 do
			local cf = base * CFrame.new(ix * 36, WALL_H - 2.4, iz * 28)
			local panel = part(station, "CeilingPanel", Vector3.new(9, 0.5, 5), cf, Color3.fromRGB(255, 248, 236), Enum.Material.SmoothPlastic)
			panel.CanCollide = false
			local glow = neon(station, "PanelGlow", Vector3.new(8.2, 0.2, 4.2), cf * CFrame.new(0, -0.3, 0), Color3.fromRGB(255, 246, 232))
			-- 0.22 emissive panels plus ~20 overlapping point lights blew the concourse to pure white
			glow.Transparency = 0.62
			if math.abs(ix) <= 1 and math.abs(iz) <= 1 then
				local lamp = Instance.new("PointLight")
				lamp.Color = Color3.fromRGB(255, 242, 224)
				lamp.Brightness = 0.6
				lamp.Range = 30
				lamp.Shadows = (ix == 0 and iz == 0)
				lamp.Parent = glow
			end
		end
	end
	for _, spec in { { Vector3.new(0, 26, -34), 1.6, 70 }, { Vector3.new(0, 26, 56), 1.4, 60 } } do
		local bulb = neon(station, "LightPool", Vector3.new(3, 0.4, 3), base * CFrame.new(spec[1]), Color3.fromRGB(255, 238, 214))
		bulb.Transparency = 0.05
		local pl = Instance.new("PointLight")
		pl.Color = Color3.fromRGB(255, 236, 210)
		pl.Brightness = spec[2] * 0.8
		pl.Range = spec[3] * 0.7
		pl.Shadows = false
		pl.Parent = bulb
	end

	-- ── observation wall: three contiguous angled bays ───────────────────────
	local windowZ = -HALF_Z + 1.5
	local sillY, headY = 2, 30
	local bayW, mullionW = 52, 6
	for bay = -1, 1 do
		local cx = bay * (bayW + mullionW)
		local glass = part(station, "WindowBay", Vector3.new(bayW, headY - sillY, 1.2),
			base * CFrame.new(cx, (sillY + headY) / 2, windowZ) * CFrame.Angles(math.rad(-4), 0, 0), GLASS, Enum.Material.ForceField)
		glass.Transparency = 0.94
		glass.CanCollide = true
		glass.CastShadow = false
		-- frame: sill, head, jambs
		part(station, "WindowSill", Vector3.new(bayW + 2, 1.6, 4), base * CFrame.new(cx, sillY - 0.4, windowZ + 1.2), STEEL, Enum.Material.Metal)
		part(station, "WindowHead", Vector3.new(bayW + 2, 1.6, 4), base * CFrame.new(cx, headY + 0.4, windowZ + 1.2), STEEL, Enum.Material.Metal)
		for _, sx in { -1, 1 } do
			part(station, "WindowJamb", Vector3.new(1.8, headY - sillY + 2, 4), base * CFrame.new(cx + sx * (bayW / 2 + 0.9), (sillY + headY) / 2, windowZ + 1.2), STEEL, Enum.Material.Metal)
		end
		-- A 0.3-transparency neon strip 50+ studs wide blooms into a pale green slab across the window bay
		-- (capture V135_01); the sill only needs to catch light.
		neon(station, "WindowGlow", Vector3.new(bayW, 0.2, 0.3), base * CFrame.new(cx, sillY + 0.2, windowZ + 2.6), CYAN).Transparency = 0.62
	end
	-- mullions between bays, and the outer wall segments either side
	for bay = -1, 1 do
		local cx = bay * (bayW + mullionW)
		part(station, "Mullion", Vector3.new(mullionW, WALL_H, 3.4), base * CFrame.new(cx + (bayW + mullionW) / 2, WALL_H / 2, windowZ + 1), STEEL, Enum.Material.Metal)
	end
	for _, sx in { -1, 1 } do
		part(station, "WindowPier", Vector3.new(HALF_X - (bayW * 1.5 + mullionW * 1.5), WALL_H, 3.4), base * CFrame.new(sx * (HALF_X - (HALF_X - (bayW * 1.5 + mullionW * 1.5)) / 2), WALL_H / 2, windowZ + 1), NAVY, Enum.Material.Metal)
	end
	part(station, "WindowSpandrel", Vector3.new(HALF_X * 2, WALL_H - headY - 2, 3.4), base * CFrame.new(0, (WALL_H + headY) / 2 + 1, windowZ + 1), NAVY, Enum.Material.Metal)
	-- observation rail, set back from the glass
	local rail = part(station, "ObservationRail", Vector3.new(HALF_X * 2 - 24, 0.9, 0.9), base * CFrame.new(0, 4.2, windowZ + 9), STEEL, Enum.Material.Metal)
	rail.CanCollide = false
	for ix = -4, 4 do
		part(station, "RailPost", Vector3.new(0.6, 4.2, 0.6), base * CFrame.new(ix * 22, 2.1, windowZ + 9), STEEL, Enum.Material.Metal)
	end
	sign(station, "GFS VANGUARD", Vector2.new(900, 130), base * CFrame.new(0, 32.4, windowZ + 2.6) * CFrame.Angles(0, math.pi, 0), OFFWHITE)

	-- ── zone signage ─────────────────────────────────────────────────────────
	-- Was rotated 180 degrees like the rear-wall signage, but this wall faces the player: the panel
	-- showed its back and the text read mirrored across the bay (V135_02).
	sign(station, "OPERATIONS", Vector2.new(620, 150), base * CFrame.new(0, 24, -30) * CFrame.new(0, 0, 1.2), OFFWHITE)
	sign(station, "ARMORY", Vector2.new(460, 130), base * CFrame.new(-HALF_X + 2.6, 20, -18) * CFrame.Angles(0, math.rad(90), 0), OFFWHITE)
	sign(station, "DISPATCH", Vector2.new(460, 130), base * CFrame.new(HALF_X - 2.6, 20, -18) * CFrame.Angles(0, math.rad(-90), 0), OFFWHITE)

	-- ── outside: planet limb, atmosphere, stars, one drifting transport ──────
	-- Veyra-7 fills the lower half of the observation bays: the station orbits it, and the
	-- planet is the only thing that says "we are in space" at a glance.
	-- Veyra-7 was at z=-900, about 950 studs from the spawn camera: outside the streaming radius, so
	-- the bays rendered as pure black rectangles (V135_02) even though the planet "existed". It is now
	-- 300 studs past the observation glass, close enough to stream and large enough to fill the bays.
	local planet = part(station, "Veyra7", Vector3.new(220, 220, 220), base * CFrame.new(60, -70, windowZ - 300), Color3.fromRGB(58, 82, 96), Enum.Material.SmoothPlastic)
	planet.Shape = Enum.PartType.Ball
	planet.CanCollide = false
	planet.CastShadow = false
	local atmo = part(station, "Veyra7Atmo", Vector3.new(234, 234, 234), planet.CFrame, Color3.fromRGB(122, 176, 220), Enum.Material.Neon)
	atmo.Shape = Enum.PartType.Ball
	atmo.CanCollide = false
	atmo.CastShadow = false
	atmo.Transparency = 0.9
	local belt = part(station, "Veyra7Belt", Vector3.new(224, 46, 224), planet.CFrame * CFrame.Angles(0, 0, math.rad(14)), Color3.fromRGB(78, 104, 118), Enum.Material.SmoothPlastic)
	belt.CanCollide = false
	belt.CastShadow = false
	belt.Transparency = 0.25
	local halo = part(station, "Veyra7Halo", Vector3.new(248, 248, 248), planet.CFrame, Color3.fromRGB(96, 150, 196), Enum.Material.Neon)
	halo.Transparency = 0.965

	for _, lx in ipairs({ -46, 0, 46 }) do
		for _, lz in ipairs({ -22, 18, 52 }) do
			local lamp = Instance.new("PointLight")
			lamp.Color = Color3.fromRGB(214, 228, 255)
			-- the hull blocks all sky/outdoor contribution, so the interior is lit only by these
			-- fixtures: at 0.34 the room rendered pitch black instead of merely dark
			lamp.Brightness = 1.1
			lamp.Range = 38
			lamp.Shadows = false
			lamp.Parent = part(station, "CeilingLampAnchor", Vector3.new(1, 1, 1),
				base * CFrame.new(lx, WALL_H - 3, lz), Color3.fromRGB(20, 22, 26), Enum.Material.SmoothPlastic)
		end
	end

	-- Stars as geometry, not Sky.StarCount: 20000 Sky stars render nothing through the bay glass, and
	-- an orbital command station with a black window is not a space station. Kept inside the streaming
	-- radius, deterministic positions so the sky is stable between builds.
	local starRng = Random.new(20261123)
	for i = 1, 90 do
		local sx = starRng:NextNumber(-320, 320)
		local sy = starRng:NextNumber(-30, 150)
		local sz = windowZ - starRng:NextNumber(240, 420)
		local size = starRng:NextNumber(1.1, 2.6)
		local star = part(station, "VistaStar", Vector3.new(size, size, size), base * CFrame.new(sx, sy, sz), Color3.fromRGB(212, 228, 255), Enum.Material.Neon)
		star.Shape = Enum.PartType.Ball
		star.CanCollide = false
		star.CastShadow = false
		star.Transparency = starRng:NextNumber(0, 0.35)
	end
	-- Exterior navigation beacons. Neon balls only, no PointLight: they must read as distant hull lights
	-- through the glazing without washing the interior, so brightness comes from colour and strobe timing.
	local beacons = {}
	local function beacon(name: string, size: number, cf: CFrame, color: Color3, period: number, phase: number, bright: number)
		local b = part(station, name, Vector3.new(size, size, size), cf, color, Enum.Material.Neon)
		b.Shape = Enum.PartType.Ball
		b.CanCollide = false
		b.CastShadow = false
		beacons[#beacons + 1] = { part = b, period = period, phase = phase, bright = bright }
		return b
	end
	local deckY = 776 - base.Position.Y
	for index, bayX in ipairs({ -58, 0, 58 }) do
		beacon("NavBeaconPort", 1.5, base * CFrame.new(bayX - 27, deckY, windowZ - 5), Color3.fromRGB(255, 92, 92), 2.2, index * 0.4, 0.2)
		beacon("NavBeaconStarboard", 1.5, base * CFrame.new(bayX + 27, deckY, windowZ - 5), Color3.fromRGB(96, 255, 148), 2.2, index * 0.4 + 1.1, 0.2)
		beacon("NavStrobe", 1.2, base * CFrame.new(bayX, deckY + 15, windowZ - 5), Color3.fromRGB(226, 238, 255), 3.4, index * 0.7, 0.15)
	end
	for index, markerX in ipairs({ -210, 150, 330 }) do
		beacon("NavMarker", 3.2, base * CFrame.new(markerX, deckY - 6 + index * 3, windowZ - 120), Color3.fromRGB(255, 186, 96), 4 + index, index * 1.3, 0.25)
	end
	task.spawn(function()
		while beacons[1] and beacons[1].part.Parent do
			local t = os.clock()
			for _, b in ipairs(beacons) do
				local pulse = 0.5 + 0.5 * math.sin((t / b.period + b.phase) * math.pi * 2)
				b.part.Transparency = b.bright + (0.95 - b.bright) * pulse
			end
			task.wait(1 / 8)
		end
	end)

	-- Armory alcove (MICRO-008). The ARMORY sign existed at x -97 but the alcove behind it was empty deck,
	-- so nothing marked it as a place where weapons live. Racks, a kit mannequin and an inspection bench.
	local armory = Instance.new("Folder")
	armory.Name = "ArmoryDressing"
	armory.Parent = station
	local deckTop = 3.7 -- floor plate top, in base-local studs
	local function fixture(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): BasePart
		local p = part(armory, name, size, cf, color, material)
		p.CanCollide = false
		return p
	end
	-- three wall racks, each holding three rifles so the alcove reads as an armoury from the concourse
	for rackIndex = 1, 3 do
		local rz = -34 + (rackIndex - 1) * 8
		local rackCF = base * CFrame.new(-96.4, deckTop, rz) * CFrame.Angles(0, math.rad(-90), 0)
		fixture("RackUpright", Vector3.new(0.7, 9, 0.7), rackCF * CFrame.new(0, 4.5, -2.8), Color3.fromRGB(58, 66, 78), Enum.Material.Metal)
		fixture("RackUpright", Vector3.new(0.7, 9, 0.7), rackCF * CFrame.new(0, 4.5, 2.8), Color3.fromRGB(58, 66, 78), Enum.Material.Metal)
		fixture("RackRail", Vector3.new(0.5, 0.5, 6.4), rackCF * CFrame.new(0, 8.8, 0), Color3.fromRGB(72, 80, 92), Enum.Material.Metal)
		fixture("RackBoard", Vector3.new(0.3, 3.4, 6), rackCF * CFrame.new(-0.2, 6.6, 0), Color3.fromRGB(26, 32, 40), Enum.Material.SmoothPlastic)
		for slot = 1, 3 do
			local sz = (slot - 2) * 2
			local rifle = fixture("RackRifle", Vector3.new(0.4, 1.1, 4.6), rackCF * CFrame.new(0.15, 6.6, sz), Color3.fromRGB(94, 102, 114), Enum.Material.Metal)
			rifle.CFrame = rifle.CFrame * CFrame.Angles(math.rad(90), 0, 0)
			fixture("RackScope", Vector3.new(0.5, 0.5, 0.9), rifle.CFrame * CFrame.new(0, 0.55, 0.6), CYAN, Enum.Material.Neon)
		end
		fixture("RackLabel", Vector3.new(0.18, 0.3, 3.8), rackCF * CFrame.new(-0.35, 9.4, 0), Color3.fromRGB(96, 200, 255), Enum.Material.Neon)
	end
	-- kit mannequin: the same graphite/off-white palette as the deployed soldier, on a plinth
	local mannequinCF = base * CFrame.new(-89.5, deckTop, -12) * CFrame.Angles(0, math.rad(20), 0)
	fixture("MannequinPlinth", Vector3.new(4.4, 0.4, 4.4), mannequinCF * CFrame.new(0, 0.2, 0), Color3.fromRGB(44, 50, 60), Enum.Material.Metal)
	fixture("MannequinTorso", Vector3.new(2.4, 2.6, 1.3), mannequinCF * CFrame.new(0, 3.6, 0), Color3.fromRGB(62, 70, 88), Enum.Material.Fabric)
	fixture("MannequinPlate", Vector3.new(2.3, 1.5, 0.35), mannequinCF * CFrame.new(0, 4.1, -0.7), Color3.fromRGB(222, 222, 214), Enum.Material.SmoothPlastic)
	fixture("MannequinHead", Vector3.new(1.3, 1.3, 1.3), mannequinCF * CFrame.new(0, 5.5, 0), Color3.fromRGB(62, 70, 88), Enum.Material.Fabric)
	fixture("MannequinVisor", Vector3.new(1.05, 0.32, 0.2), mannequinCF * CFrame.new(0, 5.6, -0.65), CYAN, Enum.Material.Neon)
	fixture("MannequinLegL", Vector3.new(0.9, 2.6, 0.9), mannequinCF * CFrame.new(-0.62, 1.5, 0), Color3.fromRGB(62, 70, 88), Enum.Material.Fabric)
	fixture("MannequinLegR", Vector3.new(0.9, 2.6, 0.9), mannequinCF * CFrame.new(0.62, 1.5, 0), Color3.fromRGB(62, 70, 88), Enum.Material.Fabric)
	fixture("MannequinArmL", Vector3.new(0.7, 2.2, 0.7), mannequinCF * CFrame.new(-1.55, 3.5, 0), Color3.fromRGB(62, 70, 88), Enum.Material.Fabric)
	fixture("MannequinArmR", Vector3.new(0.7, 2.2, 0.7), mannequinCF * CFrame.new(1.55, 3.5, 0), Color3.fromRGB(62, 70, 88), Enum.Material.Fabric)
	fixture("MannequinPauldronL", Vector3.new(1.1, 0.6, 1.2), mannequinCF * CFrame.new(-1.55, 4.7, 0), Color3.fromRGB(222, 222, 214), Enum.Material.SmoothPlastic)
	fixture("MannequinPauldronR", Vector3.new(1.1, 0.6, 1.2), mannequinCF * CFrame.new(1.55, 4.7, 0), Color3.fromRGB(222, 222, 214), Enum.Material.SmoothPlastic)
	-- inspection bench with a rifle stripped on the mat
	local benchCF = base * CFrame.new(-88.5, deckTop, -22) * CFrame.Angles(0, math.rad(-90), 0)
	fixture("BenchTop", Vector3.new(11, 0.45, 4), benchCF * CFrame.new(0, 3.1, 0), Color3.fromRGB(78, 86, 98), Enum.Material.Metal)
	fixture("BenchLeg", Vector3.new(0.5, 3, 0.5), benchCF * CFrame.new(-5, 1.5, -1.6), Color3.fromRGB(52, 58, 68), Enum.Material.Metal)
	fixture("BenchLeg", Vector3.new(0.5, 3, 0.5), benchCF * CFrame.new(5, 1.5, -1.6), Color3.fromRGB(52, 58, 68), Enum.Material.Metal)
	fixture("BenchLeg", Vector3.new(0.5, 3, 0.5), benchCF * CFrame.new(-5, 1.5, 1.6), Color3.fromRGB(52, 58, 68), Enum.Material.Metal)
	fixture("BenchLeg", Vector3.new(0.5, 3, 0.5), benchCF * CFrame.new(5, 1.5, 1.6), Color3.fromRGB(52, 58, 68), Enum.Material.Metal)
	fixture("BenchMat", Vector3.new(9.4, 0.1, 3.2), benchCF * CFrame.new(0, 3.4, 0), Color3.fromRGB(30, 46, 56), Enum.Material.Fabric)
	local stripped = fixture("BenchRifle", Vector3.new(5.6, 0.5, 0.9), benchCF * CFrame.new(-0.6, 3.75, 0.3), Color3.fromRGB(104, 112, 124), Enum.Material.Metal)
	fixture("BenchBarrel", Vector3.new(2.4, 0.28, 0.28), stripped.CFrame * CFrame.new(3.9, 0.05, 0), Color3.fromRGB(120, 128, 140), Enum.Material.Metal)
	fixture("BenchLamp", Vector3.new(0.5, 0.5, 6), benchCF * CFrame.new(0, 8.4, -1.4) * CFrame.Angles(math.rad(58), 0, 0), Color3.fromRGB(58, 66, 78), Enum.Material.Metal)
	fixture("BenchLampHead", Vector3.new(2.2, 1.2, 0.5), benchCF * CFrame.new(0, 6.6, -3.4), Color3.fromRGB(240, 246, 255), Enum.Material.Neon)

	-- The concourse ceiling run stops at the bay line, so the alcove sat in near-darkness (caught in
	-- V143_04). Two pendant housings plus one short-range fill bring the racks and bench back.
	for pendantIndex = 1, 2 do
		local pz = -34 + (pendantIndex - 1) * 12
		fixture("ArmoryPendantRod", Vector3.new(0.25, 6, 0.25), base * CFrame.new(-93, 19.5, pz), Color3.fromRGB(64, 72, 84), Enum.Material.Metal)
		fixture("ArmoryPendantHousing", Vector3.new(9, 0.45, 1), base * CFrame.new(-93, 16.4, pz), Color3.fromRGB(74, 82, 94), Enum.Material.Metal)
		local strip = fixture("ArmoryPendantStrip", Vector3.new(8.4, 0.2, 0.5), base * CFrame.new(-93, 16.1, pz), Color3.fromRGB(238, 244, 255), Enum.Material.Neon)
		-- V588 audit: the alcove still read as a black pocket because these bright strips were emissive
		-- geometry only. Give each pendant a small practical, marked so the global fixture tamer caps
		-- it at 2 instead of flattening it to the concourse-wide 0.8 ceiling.
		local pendantLight = Instance.new("PointLight")
		pendantLight.Name = "ArmoryPendantLight"
		pendantLight:SetAttribute("GFPractical", true)
		pendantLight.Color = Color3.fromRGB(226, 236, 255)
		pendantLight.Brightness = 1.35
		pendantLight.Range = 24
		pendantLight.Shadows = false
		pendantLight.Parent = strip
	end
	local armoryFill = Instance.new("PointLight")
	armoryFill.Name = "ArmoryFill"
	armoryFill:SetAttribute("GFPractical", true)
	armoryFill.Range = 30
	armoryFill.Brightness = 1.45
	armoryFill.Color = Color3.fromRGB(226, 236, 255)
	armoryFill.Shadows = false
	armoryFill.Parent = fixture("ArmoryLampBody", Vector3.new(1, 0.3, 1), base * CFrame.new(-92, 15.9, -28), Color3.fromRGB(240, 246, 255), Enum.Material.Neon)

	-- Dispatch alcove (MICRO-009). Mirror of the armoury problem: the DISPATCH sign hung over empty deck.
	-- A dispatch point needs an operator position, a live signal and a queue lane.
	local dispatch = Instance.new("Folder")
	dispatch.Name = "DispatchDressing"
	dispatch.Parent = station
	local function dfix(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): BasePart
		local p = part(dispatch, name, size, cf, color, material)
		p.CanCollide = false
		return p
	end
	local deskCF = base * CFrame.new(94.2, deckTop, -26) * CFrame.Angles(0, math.rad(90), 0)
	dfix("DispatchCounter", Vector3.new(16, 0.5, 4.4), deskCF * CFrame.new(0, 3.4, 0), Color3.fromRGB(82, 90, 102), Enum.Material.Metal)
	dfix("DispatchKick", Vector3.new(15.4, 2.9, 0.8), deskCF * CFrame.new(0, 1.7, -1.8), Color3.fromRGB(52, 58, 68), Enum.Material.Metal)
	dfix("DispatchReturn", Vector3.new(4.4, 0.5, 6.4), deskCF * CFrame.new(6.6, 3.4, 5.4) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(82, 90, 102), Enum.Material.Metal)
	dfix("DispatchHood", Vector3.new(16, 4.4, 1.6), deskCF * CFrame.new(0, 9.2, -2.2) * CFrame.Angles(math.rad(-14), 0, 0), Color3.fromRGB(58, 66, 78), Enum.Material.Metal)
	for terminalIndex = 1, 2 do
		local tx = (terminalIndex - 2.5) * 4.6
		dfix("TerminalBody", Vector3.new(3.4, 0.6, 2.2), deskCF * CFrame.new(tx, 3.9, 0), Color3.fromRGB(46, 52, 62), Enum.Material.SmoothPlastic)
		dfix("TerminalScreen", Vector3.new(3, 1.9, 0.16), deskCF * CFrame.new(tx, 5.1, -0.55) * CFrame.Angles(math.rad(-18), 0, 0), Color3.fromRGB(12, 30, 44), Enum.Material.SmoothPlastic)
		dfix("TerminalBezel", Vector3.new(3.3, 2.2, 0.1), deskCF * CFrame.new(tx, 5.1, -0.64) * CFrame.Angles(math.rad(-18), 0, 0), Color3.fromRGB(44, 86, 108), Enum.Material.SmoothPlastic)
	end
	for barIndex = 1, 9 do
		local bar = dfix("SignalBar", Vector3.new(0.6, 1, 0.28), deskCF * CFrame.new(-3.2 + (barIndex - 1) * 0.8, 1.3, -2.32), Color3.fromRGB(64, 178, 214), Enum.Material.Neon)
		bar:SetAttribute("BarIndex", barIndex)
	end
	dfix("SignalTray", Vector3.new(7.4, 4.2, 0.2), deskCF * CFrame.new(0, 3.1, -2.4), Color3.fromRGB(30, 36, 46), Enum.Material.Metal)
	dfix("CommsMast", Vector3.new(0.6, 12, 0.6), deskCF * CFrame.new(8.4, 6, 4.6), Color3.fromRGB(64, 72, 84), Enum.Material.Metal)
	local dish = dfix("CommsDish", Vector3.new(3.6, 0.5, 3.6), deskCF * CFrame.new(8.4, 11.4, 4.6) * CFrame.Angles(math.rad(-40), 0, 0), Color3.fromRGB(96, 104, 116), Enum.Material.Metal)
	dish.Shape = Enum.PartType.Cylinder
	local mastLamp = dfix("CommsLamp", Vector3.new(0.9, 0.9, 0.9), deskCF * CFrame.new(8.4, 12.6, 4.6), AMBER, Enum.Material.Neon)
	mastLamp.Shape = Enum.PartType.Ball
	for postIndex = 1, 3 do
		dfix("QueuePost", Vector3.new(0.7, 3.4, 0.7), base * CFrame.new(86, deckTop + 1.7, -18 - postIndex * 4), Color3.fromRGB(118, 126, 138), Enum.Material.Metal)
		dfix("QueueCap", Vector3.new(0.85, 0.35, 0.85), base * CFrame.new(86, deckTop + 3.45, -18 - postIndex * 4), Color3.fromRGB(120, 104, 56), Enum.Material.Metal)
		dfix("QueueLamp", Vector3.new(0.24, 0.14, 0.24), base * CFrame.new(86, deckTop + 3.68, -18 - postIndex * 4), AMBER, Enum.Material.Neon)
	end
	for dPendant = 1, 2 do
		local dz = -30 + (dPendant - 1) * 10
		dfix("DispatchPendantRod", Vector3.new(0.25, 6, 0.25), base * CFrame.new(91.5, 19.5, dz), Color3.fromRGB(64, 72, 84), Enum.Material.Metal)
		dfix("DispatchPendantHousing", Vector3.new(8, 0.45, 1), base * CFrame.new(91.5, 16.4, dz), Color3.fromRGB(74, 82, 94), Enum.Material.Metal)
		dfix("DispatchPendantStrip", Vector3.new(7.4, 0.2, 0.5), base * CFrame.new(91.5, 16.1, dz), Color3.fromRGB(238, 244, 255), Enum.Material.Neon)
	end
	local dispatchFill = Instance.new("PointLight")
	dispatchFill.Name = "DispatchFill"
	dispatchFill.Range = 28
	dispatchFill.Brightness = 1.1
	dispatchFill.Color = Color3.fromRGB(226, 236, 255)
	dispatchFill.Shadows = true
	dispatchFill.Parent = dfix("DispatchLampBody", Vector3.new(1, 0.3, 1), base * CFrame.new(92, 15.9, -26), Color3.fromRGB(240, 246, 255), Enum.Material.Neon)
	dfix("QueueGuide", Vector3.new(0.18, 0.06, 20), base * CFrame.new(84.6, deckTop + 0.04, -28), Color3.fromRGB(196, 168, 60), Enum.Material.SmoothPlastic)
	task.spawn(function()
		while dispatch.Parent do
			local t = os.clock()
			for _, bar in ipairs(dispatch:GetChildren()) do
				if bar.Name == "SignalBar" then
					local idx = bar:GetAttribute("BarIndex") or 1
					local level = 0.5 + 0.5 * math.sin(t * 4.4 + idx * 0.9) * math.sin(t * 1.3 + idx * 0.4)
					local h = 0.5 + level * 3.2
					bar.Size = Vector3.new(0.42, h, 0.3)
					bar.CFrame = deskCF * CFrame.new(-3.2 + (idx - 1) * 0.8, 1.05 + h * 0.5, -2.32)
				end
			end
			mastLamp.Transparency = 0.15 + 0.55 * (0.5 + 0.5 * math.sin(t * 3.1))
			task.wait(0.1)
		end
	end)

	-- Deployment bay (MICRO-010). The BayDoor was a 30x22 slab with no seam, no seals and no rails, so the
	-- one place a player boards a drop pod looked like a wall. Built as: split sealed bulkhead + hydraulics,
	-- loading rails into the bay, and a pod actually sitting on the cradle.
	local deployment = Instance.new("Folder")
	deployment.Name = "DeploymentBay"
	deployment.Parent = station
	-- deck surface height: the hazard band and rails are placed off it
	local DECK_Y = 761.05
	local function wf(name: string, size: Vector3, x: number, y: number, z: number, color: Color3, material: Enum.Material, rot: CFrame?)
		local cf = base * CFrame.new(base:PointToObjectSpace(Vector3.new(x, y, z)))
		if rot then cf = cf * rot end
		local p = part(deployment, name, size, cf, color, material)
		p.CanCollide = false
		return p
	end
	for leaf = 1, 2 do
		local lx = (leaf == 1) and -7.4 or 7.4
		wf("BulkheadLeaf", Vector3.new(14.4, 21, 1.7), lx, 771, 73.2, Color3.fromRGB(92, 100, 112), Enum.Material.Metal)
		wf("BulkheadRib", Vector3.new(0.5, 20, 0.5), lx, 771, 72.2, Color3.fromRGB(132, 140, 152), Enum.Material.Metal)
		wf("BulkheadRib", Vector3.new(0.5, 20, 0.5), lx - 5.4, 771, 72.2, Color3.fromRGB(132, 140, 152), Enum.Material.Metal)
		wf("BulkheadRib", Vector3.new(0.5, 20, 0.5), lx + 5.4, 771, 72.2, Color3.fromRGB(132, 140, 152), Enum.Material.Metal)
		wf("BulkheadRibH", Vector3.new(14.4, 0.5, 0.5), lx, 776, 72.2, Color3.fromRGB(132, 140, 152), Enum.Material.Metal)
		wf("BulkheadRibH", Vector3.new(14.4, 0.5, 0.5), lx, 766, 72.2, Color3.fromRGB(132, 140, 152), Enum.Material.Metal)
	end
	wf("BulkheadSeam", Vector3.new(0.5, 20.6, 0.35), 0, 771, 72.1, AMBER, Enum.Material.Neon)
	wf("BulkheadLintel", Vector3.new(31.5, 2.4, 2.6), 0, 782.6, 72.8, Color3.fromRGB(74, 82, 94), Enum.Material.Metal)
	wf("BulkheadPost", Vector3.new(2.6, 23, 2.6), -15.6, 771, 72.8, Color3.fromRGB(74, 82, 94), Enum.Material.Metal)
	wf("BulkheadPost", Vector3.new(2.6, 23, 2.6), 15.6, 771, 72.8, Color3.fromRGB(74, 82, 94), Enum.Material.Metal)
	for ram = 1, 2 do
		local rx = (ram == 1) and -9.5 or 9.5
		local ramBarrel = wf("HydraulicRam", Vector3.new(1.5, 8, 1.5), rx, 779.6, 71.4, Color3.fromRGB(150, 158, 170), Enum.Material.Metal, CFrame.Angles(math.rad(28), 0, 0))
		ramBarrel.Shape = Enum.PartType.Cylinder
		ramBarrel.CFrame = ramBarrel.CFrame * CFrame.Angles(0, 0, math.rad(90))
		wf("HydraulicPiston", Vector3.new(0.9, 5.4, 0.9), rx + 1.1, 775.4, 69.4, Color3.fromRGB(196, 202, 214), Enum.Material.Metal, CFrame.Angles(math.rad(28), 0, 0))
	end
	local bulkheadBeacon = wf("BulkheadBeacon", Vector3.new(1.5, 1.1, 1.5), 0, 784.4, 71.6, RED, Enum.Material.Neon)
	bulkheadBeacon.Shape = Enum.PartType.Ball
	for stripe = 1, 15 do
		local sx = -14.7 + (stripe - 1) * 2.1
		local isYellow = (stripe % 2 == 1)
		wf("HazardStripe", Vector3.new(2.05, 0.16, 2.2), sx, DECK_Y + 0.05, 71.6, isYellow and Color3.fromRGB(212, 176, 60) or Color3.fromRGB(32, 34, 38), Enum.Material.SmoothPlastic)
	end
	for side = 1, 2 do
		local rx = (side == 1) and -6 or 6
		wf("LoadingRail", Vector3.new(1.1, 0.55, 17), rx, DECK_Y + 0.28, 63, Color3.fromRGB(104, 112, 124), Enum.Material.Metal)
		wf("LoadingRailLip", Vector3.new(0.25, 0.2, 17), rx - 0.5, DECK_Y + 0.62, 63, CYAN, Enum.Material.Neon)
		wf("LoadingRailLip", Vector3.new(0.25, 0.2, 17), rx + 0.5, DECK_Y + 0.62, 63, CYAN, Enum.Material.Neon)
	end
	for tie = 1, 5 do
		wf("RailTie", Vector3.new(12.4, 0.3, 1.1), 0, DECK_Y + 0.16, 56 + tie * 2.8, Color3.fromRGB(56, 62, 72), Enum.Material.Metal)
	end
	local podZ = 63.4
	wf("PodCradle", Vector3.new(13.6, 0.8, 14.4), 0, DECK_Y + 0.9, podZ, Color3.fromRGB(62, 68, 78), Enum.Material.Metal)
	wf("PodHull", Vector3.new(11, 8.6, 12.4), 0, DECK_Y + 5.4, podZ, Color3.fromRGB(138, 146, 158), Enum.Material.Metal)
	wf("PodHullPlate", Vector3.new(11.4, 1.2, 8.4), 0, DECK_Y + 6.6, podZ, Color3.fromRGB(158, 166, 178), Enum.Material.Metal)
	wf("PodNose", Vector3.new(8.6, 3.2, 6.4), 0, DECK_Y + 10.8, podZ + 1.4, Color3.fromRGB(120, 128, 140), Enum.Material.Metal)
	wf("PodHatchFrame", Vector3.new(5.6, 6.4, 0.5), 0, DECK_Y + 4.6, podZ - 6.3, Color3.fromRGB(96, 104, 116), Enum.Material.Metal)
	wf("PodHatch", Vector3.new(4.8, 5.6, 0.36), 0, DECK_Y + 4.6, podZ - 6.55, Color3.fromRGB(52, 60, 72), Enum.Material.Metal)
	wf("PodHatchLamp", Vector3.new(4.2, 0.24, 0.2), 0, DECK_Y + 7.5, podZ - 6.5, AMBER, Enum.Material.Neon)
	wf("PodSideStripe", Vector3.new(0.3, 1.1, 9), -5.55, DECK_Y + 5.2, podZ, CYAN, Enum.Material.Neon)
	wf("PodSideStripe", Vector3.new(0.3, 1.1, 9), 5.55, DECK_Y + 5.2, podZ, CYAN, Enum.Material.Neon)
	wf("PodStep", Vector3.new(4.4, 0.5, 2.6), 0, DECK_Y + 0.55, podZ - 7.6, Color3.fromRGB(74, 82, 94), Enum.Material.Metal)
	for thruster = 1, 4 do
		local tx = ((thruster - 1) % 2 == 0) and -3.4 or 3.4
		local tz = (thruster <= 2) and podZ - 3.6 or podZ + 4.2
		local nozzle = wf("PodThruster", Vector3.new(2.2, 2.2, 2.6), tx, DECK_Y + 1.5, tz, Color3.fromRGB(58, 64, 76), Enum.Material.Metal)
		nozzle.Shape = Enum.PartType.Cylinder
		nozzle.CFrame = nozzle.CFrame * CFrame.Angles(0, 0, math.rad(90))
	end
	wf("GantryBeam", Vector3.new(26, 1.4, 1.4), 0, 787.4, podZ, Color3.fromRGB(88, 96, 108), Enum.Material.Metal)
	wf("GantryChain", Vector3.new(0.28, 6.4, 0.28), 0, 783.4, podZ, Color3.fromRGB(120, 128, 140), Enum.Material.Metal)
	wf("GantryHook", Vector3.new(1.5, 1.1, 1.5), 0, 780.1, podZ, Color3.fromRGB(150, 158, 170), Enum.Material.Metal)
	wf("GantryFlood", Vector3.new(1.2, 0.4, 1.2), -9.5, 786.6, podZ, Color3.fromRGB(240, 244, 255), Enum.Material.Neon)
	wf("GantryFlood", Vector3.new(1.2, 0.4, 1.2), 9.5, 786.6, podZ, Color3.fromRGB(240, 244, 255), Enum.Material.Neon)
	local bayFill = Instance.new("PointLight")
	bayFill.Name = "BayFill"
	bayFill.Range = 34
	bayFill.Brightness = 1.2
	bayFill.Color = Color3.fromRGB(228, 238, 255)
	bayFill.Shadows = true
	bayFill.Parent = wf("BayFillBody", Vector3.new(1.4, 0.4, 1.4), 0, 786.2, podZ, Color3.fromRGB(244, 248, 255), Enum.Material.Neon)
	task.spawn(function()
		while deployment.Parent do
			bulkheadBeacon.Transparency = 0.1 + 0.6 * (0.5 + 0.5 * math.sin(os.clock() * 2.2))
			task.wait(0.12)
		end
	end)

	-- A box that never moves is a prop, not traffic. The exterior life requirement needs a readable hull
	-- that actually travels past the bays, so the transport is a small welded model on a slow 150 s loop.
	local flyby = Instance.new("Model")
	flyby.Name = "TransportFlyby"
	flyby.Parent = station
	local shipOrigin = base * CFrame.new(0, 0, windowZ - 190)
	local function shipPart(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, glow: boolean)
		local p = part(flyby, name, size, shipOrigin * offset, color, material)
		p.CanCollide = false
		p.CastShadow = false
		if glow then
			p.Material = Enum.Material.Neon
		end
		return p
	end
	shipPart("Hull", Vector3.new(54, 5.6, 13), CFrame.new(0, 0, 0), Color3.fromRGB(134, 142, 156), Enum.Material.SmoothPlastic, false)
	shipPart("HullTop", Vector3.new(40, 0.5, 1.4), CFrame.new(0, 3.1, 0), Color3.fromRGB(150, 208, 240), Enum.Material.Neon, true)
	shipPart("Spine", Vector3.new(30, 3.6, 8.6), CFrame.new(-2, 4.1, 0), Color3.fromRGB(158, 166, 180), Enum.Material.SmoothPlastic, false)
	shipPart("Bridge", Vector3.new(10, 3.2, 7.4), CFrame.new(22, 2.9, 0), Color3.fromRGB(104, 114, 128), Enum.Material.SmoothPlastic, false)
	shipPart("Canopy", Vector3.new(4.4, 1.2, 5.4), CFrame.new(25, 4.4, 0), Color3.fromRGB(120, 210, 255), Enum.Material.Neon, true)
	shipPart("WingLeft", Vector3.new(18, 1.4, 34), CFrame.new(-9, -0.6, 14), Color3.fromRGB(112, 120, 134), Enum.Material.SmoothPlastic, false)
	shipPart("WingRight", Vector3.new(18, 1.4, 34), CFrame.new(-9, -0.6, -14), Color3.fromRGB(112, 120, 134), Enum.Material.SmoothPlastic, false)
	shipPart("EngineLeft", Vector3.new(8, 3.2, 3.2), CFrame.new(-25, -0.4, 3.8), CYAN, Enum.Material.Neon, true)
	shipPart("EngineRight", Vector3.new(8, 3.2, 3.2), CFrame.new(-25, -0.4, -3.8), CYAN, Enum.Material.Neon, true)
	local plume = shipPart("Plume", Vector3.new(14, 2, 2), CFrame.new(-35, -0.4, 0), Color3.fromRGB(120, 208, 255), Enum.Material.Neon, true)
	plume.Transparency = 0.45
	local navPort = shipPart("NavPort", Vector3.new(1.6, 1.6, 1.6), CFrame.new(12, 1.6, 6.4), Color3.fromRGB(255, 96, 96), Enum.Material.Neon, true)
	local navStarboard = shipPart("NavStarboard", Vector3.new(1.6, 1.6, 1.6), CFrame.new(12, 1.6, -6.4), Color3.fromRGB(96, 255, 150), Enum.Material.Neon, true)
	flyby:PivotTo(shipOrigin)
	-- FLYBY_SECONDS is the whole pass; the ship is ~5.5 studs/s so the motion reads as distant traffic
	-- rather than a model sliding across the glass.
	local FLYBY_SECONDS = 150
	local startedAt = os.clock()
	task.spawn(function()
		local strobe = 0
		while flyby.Parent do
			local t = ((os.clock() - startedAt) % FLYBY_SECONDS) / FLYBY_SECONDS
			local px = -400 + 830 * t
			-- window opening spans y 762.4-789.6 (deck is 756), so the pass sits in the lower two thirds of
			-- the glazing instead of sliding along behind the hull above it
			local py = 20 - 9 * t
			flyby:PivotTo(base * CFrame.new(px, py, windowZ - 190) * CFrame.Angles(0, math.rad(-4), math.rad(1.5)))
			strobe = (strobe + 1) % 12
			local blink = strobe < 3 and 0.2 or 1
			navPort.Transparency = blink
			navStarboard.Transparency = blink
			task.wait(1 / 12)
		end
	end)
	return station
end

return StationArt

