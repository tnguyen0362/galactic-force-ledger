--!strict
-- The station shell is StationArt's job and it already builds 374 parts of hangar (BayDoor,
-- DeployPad, Dropship, FloorPlate, pad rings). What it never provided was a continuous floor under
-- the spawn point, so the player spawned and fell ~620 studs into empty space, and the shell had no
-- Light instances at all so the interior was unlit. This module adds exactly those two things plus a
-- single deterministic spawn pad; it deliberately does NOT build a second room.
local Concourse = {}

local DECK_Y = 760

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

function Concourse.build(parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Concourse"

	-- Walkable deck: one plate under the whole bay, big enough that no spawn or camera lands off it.
	local deck = part(model, "HangarDeck", Vector3.new(200, 2, 190), CFrame.new(0, DECK_Y, 0), Color3.fromRGB(58, 64, 72), Enum.Material.Metal)
	deck:SetAttribute("Walkable", true)

	-- Deck guide markings in the shell's amber, so the floor ties into StationArt's palette.
	part(model, "GuideStripe", Vector3.new(1.8, 0.12, 170), CFrame.new(0, DECK_Y + 1.02, 0), Color3.fromRGB(112, 96, 64), Enum.Material.SmoothPlastic, false)
	for _, x in ipairs({ -48, 48 }) do
		part(model, "LaneStripe", Vector3.new(0.7, 0.12, 160), CFrame.new(x, DECK_Y + 1.02, 0), Color3.fromRGB(72, 96, 106), Enum.Material.SmoothPlastic, false)
	end

	-- Ceiling light grid: warm, unshadowed, cheap. 15 fixtures for the whole bay.
	local lights = Instance.new("Folder")
	lights.Name = "Lights"
	lights.Parent = model
	local CEIL_Y = DECK_Y + 34
	local shadowBudget = 6
	for ix = -1, 1 do
		for iz = -2, 2 do
			local fixture = part(lights, "CeilingFixture", Vector3.new(11, 0.4, 2.4), CFrame.new(ix * 46, CEIL_Y, iz * 26), Color3.fromRGB(214, 196, 170), Enum.Material.Neon, false)
			fixture.CastShadow = false
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 231, 196)
			light.Brightness = 2.6
			light.Range = 48
			light.Shadows = shadowBudget > 0
			shadowBudget -= 1
			light.Parent = fixture
		end
	end

	-- Bay furniture at player scale: the deck between the deploy pad and the operations terminal was
	-- completely empty, which made the hangar read as a corridor rather than a working station.
	local crate = Color3.fromRGB(56, 58, 62)
	local crateTrim = Color3.fromRGB(38, 40, 45)
	local function crateStack(cx: number, cz: number, rows: number)
		for row = 0, rows - 1 do
			for slot = 0, 1 do
				if not (row == rows - 1 and slot == 1) then
					local box = part(model, "CargoCrate", Vector3.new(8, 6, 8), CFrame.new(cx + slot * 9.6, DECK_Y + 4 + row * 6.4, cz), crate, Enum.Material.Metal)
					box.CFrame = CFrame.new(cx + slot * 9.6, DECK_Y + 4 + row * 6.4, cz) * CFrame.Angles(0, math.rad((row + slot) * 4), 0)
					part(model, "CrateBand", Vector3.new(8.6, 0.4, 8.6), CFrame.new(cx + slot * 9.6, DECK_Y + 6.9 + row * 6.4, cz), crateTrim, Enum.Material.Metal, false)
				end
			end
		end
	end
	crateStack(-34, -22, 2)
	crateStack(36, -30, 1)
	crateStack(52, 24, 2)
	for _, spec in ipairs({ { -30, 30 }, { 30, 30 } }) do
		local bench = part(model, "Bench", Vector3.new(14, 1.2, 4), CFrame.new(spec[1], DECK_Y + 3, spec[2]), Color3.fromRGB(70, 74, 82), Enum.Material.Metal)
		bench.CanCollide = true
		part(model, "BenchLeg", Vector3.new(1.4, 2.4, 3.4), CFrame.new(spec[1] - 5, DECK_Y + 1.6, spec[2]), crateTrim, Enum.Material.Metal)
		part(model, "BenchLeg", Vector3.new(1.4, 2.4, 3.4), CFrame.new(spec[1] + 5, DECK_Y + 1.6, spec[2]), crateTrim, Enum.Material.Metal)
	end
	for _, z in ipairs({ -10, 10 }) do
		local trolley = part(model, "CargoTrolley", Vector3.new(7, 1, 11), CFrame.new(-54, DECK_Y + 2.2, z), Color3.fromRGB(96, 88, 66), Enum.Material.Metal)
		trolley.CanCollide = true
		part(model, "TrolleyLoad", Vector3.new(6, 3.4, 8), CFrame.new(-54, DECK_Y + 4.4, z), crate, Enum.Material.Metal)
	end

	-- The window bays are real geometry but there was nothing outside them: no planet, no traffic, no
	-- stars reachable through glass, so the station read as a sealed bunker. The vista is placed along
	-- the averaged window normal so it stays correct if the shell's bay geometry moves.
	local stationFolder = parent:FindFirstChild("Station")
	if stationFolder then
		local bays = {}
		local sumPos, sumNormal, n = Vector3.new(), Vector3.new(), 0
		for _, d in ipairs(stationFolder:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "WindowBay" then
				bays[#bays+1] = d
				sumPos += d.Position
				sumNormal += d.CFrame.LookVector
				n += 1
			end
		end
		if n > 0 then
			local centre = sumPos / n
			local outward = (sumNormal.Unit)
			local vista = Instance.new("Model")
			vista.Name = "OrbitVista"
			-- distant vista geometry sits thousands of studs out; without persistent streaming the
			-- client never receives it and the windows show empty skybox (capture-audit 2026-11).
			vista.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
			vista.Parent = model

			local function vistaPart(name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, transparency: number): Part
				local p = Instance.new("Part")
				p.Name = name
				p.Shape = shape
				p.Size = size
				p.CFrame = cframe
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CastShadow = false
				p.Color = color
				p.Material = material
				p.Transparency = transparency
				p.Parent = vista
				return p
			end

			-- Planet: tuned for a visible atmospheric limb. Earlier pass sat 9000 studs out with a
			-- 5200-stud Neon ball, which read as a flat navy disc with no limb and no terminator
			-- (capture V184_vista_planet_first). Bring it to 2400 studs and 2800 across so the
			-- silhouette curves inside the window, dark body, three shell limb bands. Ball parts clamp at
			-- 2048 studs, so the body is 1900 and the shells step up to 2020 - the first pass had every
			-- shell at the same clamped 2048 and they z-fought inside the body (capture V191).
			local planetAt = centre + outward * 2400 + Vector3.new(300, 900, 0)
			vistaPart("Planet", Enum.PartType.Ball, Vector3.new(1900, 1900, 1900), CFrame.new(planetAt), Color3.fromRGB(150, 178, 206), Enum.Material.SmoothPlastic, 0)
			vistaPart("PlanetClouds", Enum.PartType.Ball, Vector3.new(1920, 1920, 1920), CFrame.new(planetAt), Color3.fromRGB(212, 226, 242), Enum.Material.SmoothPlastic, 0.62)
			vistaPart("PlanetLimbInner", Enum.PartType.Ball, Vector3.new(1945, 1945, 1945), CFrame.new(planetAt), Color3.fromRGB(238, 249, 255), Enum.Material.Neon, 0.10)
			vistaPart("PlanetLimb", Enum.PartType.Ball, Vector3.new(1975, 1975, 1975), CFrame.new(planetAt), Color3.fromRGB(122, 196, 246), Enum.Material.Neon, 0.55)
			vistaPart("PlanetHaze", Enum.PartType.Ball, Vector3.new(2020, 2020, 2020), CFrame.new(planetAt), Color3.fromRGB(62, 132, 204), Enum.Material.SmoothPlastic, 0.86)
			-- A moon and freight silhouettes keep the sky from being one shape.
			vistaPart("Moon", Enum.PartType.Ball, Vector3.new(620, 620, 620), CFrame.new(centre + outward * 1800 + Vector3.new(-1500, 1080, 0)), Color3.fromRGB(148, 148, 142), Enum.Material.SmoothPlastic, 0)
			-- The right-hand bay pointed at empty sky: the planet sits left of centre, so a third of the
			-- window wall showed nothing (V238). A second moon on the right gives every bay a subject.
			vistaPart("MoonRight", Enum.PartType.Ball, Vector3.new(760, 760, 760), CFrame.new(centre + outward * 2100 + Vector3.new(1750, 900, 0)), Color3.fromRGB(120, 126, 136), Enum.Material.SmoothPlastic, 0)
			vistaPart("MoonRightHalo", Enum.PartType.Ball, Vector3.new(784, 784, 784), CFrame.new(centre + outward * 2100 + Vector3.new(1750, 900, 0)), Color3.fromRGB(92, 140, 186), Enum.Material.Neon, 0.88)
			-- A distant orbital platform silhouette, so the right bay is not only a rock.
			for k = 1, 3 do
				vistaPart("OrbitRing" .. k, Enum.PartType.Block, Vector3.new(220 - k * 30, 5, 26), CFrame.new(centre + outward * (1250 + k * 60) + Vector3.new(1500 + k * 40, 620 - k * 55, 0)) * CFrame.Angles(0, math.rad(12 * k), math.rad(4 * k)), Color3.fromRGB(46, 52, 62), Enum.Material.Metal, 0)
			end
			-- Freight traffic: slow silhouettes crossing the bay at different depths.
			for i, spec in ipairs({ { 520, -420, 300 }, { -700, 260, 900 }, { 120, 620, 1500 } }) do
				local at = centre + outward * spec[3] + Vector3.new(spec[1], spec[2], 0)
				vistaPart("Freighter" .. i, Enum.PartType.Block, Vector3.new(220, 60, 90), CFrame.lookAt(at, at + outward) * CFrame.Angles(0, math.rad(18 * i), 0), Color3.fromRGB(44, 48, 56), Enum.Material.Metal, 0.05)
				vistaPart("FreighterLight" .. i, Enum.PartType.Block, Vector3.new(34, 34, 34), CFrame.new(at + Vector3.new(0, 46, 0)), Color3.fromRGB(255, 198, 146), Enum.Material.Neon, 0)
			end

			-- The skybox asset is a violet nebula, but the brief is deep black-blue starfield and no
			-- original texture can be uploaded yet (capture-audit 2026-11). Stagecraft instead: a
			-- black-blue backdrop slab beyond every vista element, with authored star points scattered
			-- across its face. From the concourse the glass now reads as deep space, not purple haze.
			local backdropAt = centre + outward * 500
			local backdropCf = CFrame.lookAt(backdropAt, centre)
			-- parts clamp at 2048 studs per axis: one 9600-wide slab silently shrank to a quarter of
			-- the sky and the nebula bled through everywhere else (probe-audit 2026-11). Tile it.
			local right0 = backdropCf.RightVector
			local up0 = backdropCf.UpVector
			-- 5x3 tiles left the oblique sightlines through the side bays uncovered: standing at the
			-- left window and looking out-left misses a centered plane entirely (capture audit
			-- 2026-11). 9x5 covers roughly 60 degrees off-axis horizontally and 40 vertically.
			for tx = -4, 4 do
				for ty = -2, 2 do
					local tileAt = backdropAt + right0 * (tx * 590) + up0 * (ty * 440)
					vistaPart("StarfieldBackdrop" .. tx .. "_" .. ty, Enum.PartType.Block, Vector3.new(590, 440, 4), CFrame.lookAt(tileAt, tileAt - outward), Color3.fromRGB(5, 8, 18), Enum.Material.SmoothPlastic, 0)
				end
			end
			local starRng = Random.new(20261124)
			local right = backdropCf.RightVector
			local up = backdropCf.UpVector
			for i = 1, 170 do
				local u = (starRng:NextNumber() - 0.5) * 5100
				local v = (starRng:NextNumber() - 0.5) * 1900
				local size = 1.6 + starRng:NextNumber() * 3.2
				local bright = starRng:NextNumber()
				local starAt = backdropAt + right * u + up * v - outward * 6
				local tint = 200 + math.floor(bright * 55)
				vistaPart("Star" .. i, Enum.PartType.Ball, Vector3.new(size, size, size), CFrame.new(starAt), Color3.fromRGB(math.floor(tint * 0.82), math.floor(tint * 0.88), tint), Enum.Material.SmoothPlastic, bright * 0.2)
			end
		end
	end

			-- The bay openings had no glazing and no mullions, so from inside they read as holes cut in
			-- the wall rather than windows (capture V127_01_window_vista). Rebuild each bay as glazing:
			-- three vertical mullions, a transom, and tinted panes inset from the structural opening.
			-- bays was a local of the vista block above and out of scope here, so this loop errored on
-- every boot and nothing after it in build() ran. Collect the bay parts again in this scope.
-- `vista` was also declared inside the block above, so every part created here was parented to
-- nil and the glazing pass died on `glass.Parent = vista` - the reason no mullion, hull edge,
-- shelf or railing has ever existed in the place. Re-collect the folder in this scope.
local windowBays = {}
local vista = model:FindFirstChild("OrbitVista")
if not vista then
	vista = Instance.new("Model")
	vista.Name = "OrbitVista"
	vista.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	vista.Parent = model
end
for _, d in ipairs(stationFolder and stationFolder:GetDescendants() or {}) do
	if d:IsA("BasePart") and d.Name == "WindowBay" then
		windowBays[#windowBays + 1] = d
	end
end
			for _, bay in ipairs(windowBays) do
				local size = bay.Size
				local cf = bay.CFrame
				local function framePart(name, sz, offset, color, material, transparency)
					local p = Instance.new("Part")
					p.Name = name
					p.Size = sz
					p.CFrame = cf * CFrame.new(offset)
					p.Anchored = true
					-- Glazing must stop the player: with CanCollide false the bays were open holes and a
					-- player could walk straight out of the hull into space (MICRO-020).
					p.CanCollide = true
					p.CanQuery = false
					p.CastShadow = true
					p.Color = color
					p.Material = material
					p.Transparency = transparency or 0
					p.Parent = vista
					return p
				end
				local STEEL = Color3.fromRGB(96, 102, 112)
				local HULL = Color3.fromRGB(66, 72, 82)
				-- glazing sits inset from the structural opening
				framePart("WindowGlass", Vector3.new(size.X - 0.6, size.Y - 0.6, 0.12), Vector3.new(0, 0, 0), Color3.fromRGB(96, 138, 168), Enum.Material.SmoothPlastic, 0.93)
				-- four heavy mullions, not three thin ones: the old 0.5-stud bars were invisible at 10 studs
				for i = 1, 4 do
					local offset = (i / 5 - 0.5) * size.X
					framePart("WindowMullion", Vector3.new(1.4, size.Y, 1.6), Vector3.new(offset, 0, 0.35), STEEL, Enum.Material.Metal)
				end
				-- transoms: one at 18% height, one at the sill line, so the pane reads as a grid
				framePart("WindowTransom", Vector3.new(size.X, 0.8, 1.6), Vector3.new(0, size.Y * 0.18, 0.35), STEEL, Enum.Material.Metal)
				framePart("WindowTransom", Vector3.new(size.X, 1.1, 1.6), Vector3.new(0, -size.Y * 0.34, 0.35), STEEL, Enum.Material.Metal)
				-- thick hull edges around the opening: this is what gives the wall its thickness in frame
				framePart("WindowHullEdge", Vector3.new(size.X + 5, 2.6, 4.2), Vector3.new(0, size.Y / 2 + 1.1, 1.2), HULL, Enum.Material.Metal)
				framePart("WindowHullEdge", Vector3.new(size.X + 5, 2.6, 4.2), Vector3.new(0, -size.Y / 2 - 1.1, 1.2), HULL, Enum.Material.Metal)
				framePart("WindowHullEdge", Vector3.new(2.6, size.Y + 5, 4.2), Vector3.new(-size.X / 2 - 1.1, 0, 1.2), HULL, Enum.Material.Metal)
				framePart("WindowHullEdge", Vector3.new(2.6, size.Y + 5, 4.2), Vector3.new(size.X / 2 + 1.1, 0, 1.2), HULL, Enum.Material.Metal)
				-- sill shelf players can see their own reflection in, plus a rail they stand behind
				framePart("WindowShelf", Vector3.new(size.X + 5, 0.6, 3.2), Vector3.new(0, -size.Y / 2 - 1.6, 2.4), STEEL, Enum.Material.Metal)
				framePart("ObservationRailing", Vector3.new(size.X + 5, 0.32, 0.32), Vector3.new(0, -size.Y / 2 - 4.6, 3.4), STEEL, Enum.Material.Metal)
				for i = 0, 8 do
					local offset = (i / 8 - 0.5) * (size.X + 4)
					framePart("RailingPost", Vector3.new(0.28, 3.2, 0.28), Vector3.new(offset, -size.Y / 2 - 6.1, 3.4), STEEL, Enum.Material.Metal)
				end
			end

	-- Single spawn pad, on the deck, facing the bay door (-Z).
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ConcourseSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.lookAt(Vector3.new(0, DECK_Y + 1.6, 26), Vector3.new(0, DECK_Y + 4, -40))
	spawn.Color = Color3.fromRGB(74, 80, 90)
	spawn.Material = Enum.Material.Slate
	spawn.Transparency = 0.15
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = model

	-- Floor language: the deck was one continuous dark plane from wall to wall, which is why the
	-- concourse read as an empty box no matter how the lights were tuned (review V217). Painted
	-- lanes, a ring around the war table, hazard chevrons at the pod and plate seams give the eye
	-- something to measure the room with.
	-- 126,104,52 read as olive paint, not safety marking; 198,158,44 is a hazard yellow that still reads
	-- under the 0.35 sun.
	local PAINT_AMBER = Color3.fromRGB(198, 158, 44)
	local PAINT_DARK = Color3.fromRGB(38, 42, 50)
	local PAINT_TRIM = Color3.fromRGB(88, 148, 168)
	-- war table ring (table sits at z = -34, 34 studs square)
	for _, spec in ipairs({ { 46, 1.1, 0, -34 + 23 }, { 46, 1.1, 0, -34 - 23 }, { 1.1, 46, 23, -34 }, { 1.1, 46, -23, -34 } }) do
		part(model, "DeckRing", Vector3.new(spec[1], 0.08, spec[2]), CFrame.new(spec[3], DECK_Y + 1.03, spec[4]), PAINT_AMBER, Enum.Material.Metal, false)
	end
	-- hangar lanes toward the windows
	for _, x in ipairs({ -34, -17, 17, 34 }) do
		part(model, "DeckLane", Vector3.new(0.6, 0.08, 96), CFrame.new(x, DECK_Y + 1.03, -18), PAINT_DARK, Enum.Material.SmoothPlastic, false)
	end
	-- hazard chevrons where the drop pod loads
	for i = 0, 5 do
		local cx = -15 + i * 6
		local chevron = part(model, "HazardChevron", Vector3.new(2.6, 0.1, 5), CFrame.new(cx, DECK_Y + 1.04, 47) * CFrame.Angles(0, math.rad(45), 0), PAINT_AMBER, Enum.Material.SmoothPlastic, false)
		chevron.Transparency = 0.1
	end
	-- deck plate seams: long thin shadow lines that read as separately laid plates
	for i = -3, 3 do
		part(model, "DeckSeam", Vector3.new(0.22, 0.06, 150), CFrame.new(i * 26, DECK_Y + 1.04, 0), Color3.fromRGB(24, 27, 33), Enum.Material.SmoothPlastic, false)
	end
	-- wall dado: a waist-height trim band so the bulkheads have a horizon
	for _, sx in ipairs({ -1, 1 }) do
		part(model, "WallDado", Vector3.new(0.5, 1.6, 150), CFrame.new(sx * 99.4, DECK_Y + 9, 0), PAINT_DARK, Enum.Material.Metal, false)
		part(model, "WallTrim", Vector3.new(0.3, 0.2, 150), CFrame.new(sx * 99.2, DECK_Y + 9.9, 0), PAINT_TRIM, Enum.Material.SmoothPlastic, false)
	end

	model.Parent = parent
	return model
end

return Concourse

