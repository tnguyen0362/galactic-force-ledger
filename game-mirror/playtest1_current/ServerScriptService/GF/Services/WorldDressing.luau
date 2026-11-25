--!strict
-- WorldDressing: mission-side composition. Authored props come from ArtService;
-- procedural scatter is rule-based (see EnvironmentDressing) instead of random spray.

local ArtService = require(script.Parent.ArtService)
local EnvironmentDressing = require(script.Parent.EnvironmentDressing)

local Workspace = game:GetService("Workspace")

local WorldDressing = {}

local function groundY(x: number, z: number): number
	local TerrainService = require(script.Parent.TerrainService)
	return TerrainService.groundSurface(x, z)
end

local function mark(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, transparency: number?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

-- S07-004 biome kits: four biomes share the alien architecture and lore but carry distinct palettes,
-- flora shapes and ground treatment. The kit is selected per mission and drives every scatter choice.
local BIOME_KITS = {
	Forest = {
		floraColor = Color3.fromRGB(72, 110, 76), floraAccent = Color3.fromRGB(120, 180, 130),
		cliffColor = Color3.fromRGB(88, 84, 76), groundTint = Color3.fromRGB(96, 118, 92),
		floraHeight = 14, floraCount = 26, material = Enum.Material.Grass,
	},
	Arid = {
		floraColor = Color3.fromRGB(160, 120, 70), floraAccent = Color3.fromRGB(200, 170, 110),
		cliffColor = Color3.fromRGB(150, 115, 85), groundTint = Color3.fromRGB(178, 140, 96),
		floraHeight = 7, floraCount = 14, material = Enum.Material.Sand,
	},
	Tundra = {
		floraColor = Color3.fromRGB(140, 160, 175), floraAccent = Color3.fromRGB(210, 225, 235),
		cliffColor = Color3.fromRGB(120, 135, 150), groundTint = Color3.fromRGB(200, 215, 228),
		floraHeight = 9, floraCount = 18, material = Enum.Material.Snow,
	},
	Industrial = {
		-- S07-BIOME-INDUSTRIAL: ruined extraction-era industry — rusted metal flats, sparse dead
		-- flora, slate-grey ground with rust accents; cover reads as wrecked machinery.
		floraColor = Color3.fromRGB(110, 95, 80), floraAccent = Color3.fromRGB(160, 110, 70),
		cliffColor = Color3.fromRGB(95, 92, 90), groundTint = Color3.fromRGB(115, 108, 100),
		floraHeight = 5, floraCount = 8, material = Enum.Material.Metal,
	},
	Volcanic = {
		floraColor = Color3.fromRGB(90, 60, 55), floraAccent = Color3.fromRGB(255, 120, 60),
		cliffColor = Color3.fromRGB(55, 50, 52), groundTint = Color3.fromRGB(70, 60, 58),
		floraHeight = 6, floraCount = 10, material = Enum.Material.Basalt,
	},
}

function WorldDressing.kit(): any
	local biome = workspace:GetAttribute("GF_Biome") or "Forest"
	return BIOME_KITS[biome] or BIOME_KITS.Forest
end

function WorldDressing.build(relayPos: Vector3, spawnPos: Vector3)
	local folder = Workspace:FindFirstChild("WorldDressing")
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = "WorldDressing"
	folder.Parent = Workspace

	local relayY = groundY(relayPos.X, relayPos.Z)
	local spawnY = groundY(spawnPos.X, spawnPos.Z)

	-- Landing pad: low, dark deck with cyan approach strips.
	local pad = Instance.new("Part")
	pad.Name = "LandingPad"
	pad.Size = Vector3.new(14, 0.45, 14)
	pad.CFrame = CFrame.new(Vector3.new(spawnPos.X, spawnY + 0.25, spawnPos.Z))
	pad.Color = Color3.fromRGB(62, 70, 66)
	pad.Material = Enum.Material.Slate
pad.Transparency = 0.18
	pad.Anchored = true
	pad.Parent = folder

	for i = -1, 1, 2 do
		mark(folder, "ApproachStrip", Vector3.new(9, 0.10, 0.42),
			CFrame.new(spawnPos.X + i * 3.4, spawnY + 0.68, spawnPos.Z),
			Color3.fromRGB(88, 196, 232), Enum.Material.Neon)
	end

	-- Corridor markers along the traversal spine (readable, not noisy).
	local steps = 14
	for i = 1, steps do
		local t = i / (steps + 1)
		local x = spawnPos.X + (relayPos.X - spawnPos.X) * t
		local z = spawnPos.Z + (relayPos.Z - spawnPos.Z) * t
		local y = groundY(x, z)
		mark(folder, "SpineMarker", Vector3.new(0.5, 2.6, 0.5),
			CFrame.new(x, y + 1.0, z), Color3.fromRGB(70, 150, 190), Enum.Material.Neon, 0.35)
	end

	-- Objective compound footprint: dark deck so the outpost reads as installed.
	local deck = Instance.new("Part")
	deck.Name = "CompoundDeck"
	deck.Size = Vector3.new(64, 0.8, 64)
	deck.CFrame = CFrame.new(Vector3.new(relayPos.X, relayY + 0.4, relayPos.Z))
	deck.Color = Color3.fromRGB(48, 48, 54)
	deck.Material = Enum.Material.Slate
	deck.Anchored = true
	deck.CanCollide = true
	deck.Parent = folder

	-- Authored scatter: cliffs, flora, barricades, crates, distant mountains.
	local ok, counts = pcall(function()
		return EnvironmentDressing.dress({
			seed = 1234,
			center = Vector3.new(0, 0, 0),
			size = 704,
			parent = Workspace.ActiveActors,
			objective = Vector3.new(relayPos.X, relayY, relayPos.Z),
		})
	end)

	-- Boundary: honest hard edge instead of invisible kill walls.
	local radius = 330
	for i = 1, 24 do
		local ang = (i / 24) * math.pi * 2
		local x = math.cos(ang) * radius
		local z = math.sin(ang) * radius
		mark(folder, "BoundaryPost", Vector3.new(1.2, 6, 1.2),
			CFrame.new(x, groundY(x, z) + 3, z), Color3.fromRGB(190, 132, 64), Enum.Material.Neon, 0.25)
	end

	local total = #folder:GetChildren()
	if ok and counts then
		total += counts.cliff + counts.flora + counts.mountain + counts.crate + counts.barricade
	end
	return total
end

-- S07-020/021 tactical dressing: cover scatters at 18-35 stud intervals along exposed routes —
-- close enough to fight from, spaced enough to force movement decisions. Supply sits near the
-- main objective and extraction route so resupply is a plan, not a scavenger hunt.
function WorldDressing.scatterRouteCover(rng: Random, from: Vector3, to: Vector3, parent: Instance)
	local route = (to - from)
	local length = route.Magnitude
	local direction = route.Unit
	local cursor = 20 -- start inset from the endpoint
	while cursor < length - 20 do
		-- jitter the interval inside the spec band
		cursor += rng:NextNumber(18, 35)
		if cursor >= length - 20 then break end
		-- lateral offset so cover reads as terrain, not a fence line
		local lateral = Vector3.new(-direction.Z, 0, direction.X) * rng:NextNumber(-12, 12)
		local pos = from + direction * cursor + lateral
		local cover = Instance.new("Part")
		cover.Name = "RouteCover"
		cover.Size = Vector3.new(rng:NextNumber(4, 8), rng:NextNumber(3, 5), rng:NextNumber(2, 4))
		cover.Position = Vector3.new(pos.X, cover.Size.Y / 2, pos.Z)
		cover.Anchored = true
		cover.Color = Color3.fromRGB(88, 84, 76)
		cover.Material = Enum.Material.Rock
		cover.Parent = parent
	end
end

function WorldDressing.placeSupply(primaryPos: Vector3, extractionPos: Vector3, parent: Instance)
	-- supply sits at the midpoint favoring the objective — near the fight and the way out
	local midpoint = primaryPos:Lerp(extractionPos, 0.35)
	local cache = Instance.new("Part")
	cache.Name = "SupplyCache"
	cache.Size = Vector3.new(5, 3, 4)
	cache.Position = Vector3.new(midpoint.X, 2, midpoint.Z)
	cache.Anchored = true
	cache.Color = Color3.fromRGB(140, 120, 80)
	cache.Material = Enum.Material.Metal
	cache:SetAttribute("GF_Supply", true)
	cache.Parent = parent
end

-- S15-008 streaming discipline: decorative props beyond the culling distance hide rather than
-- render — the world streams around the player instead of simulating everything always. Fog
-- covers the transition so culling never reads as popping.
local CULL_DISTANCE = 400 -- studs — beyond this decorative props sleep

function WorldDressing.distanceCull(props: { Instance })
	task.spawn(function()
		while true do
			task.wait(2)
			local players = game:GetService("Players"):GetPlayers()
			for _, prop in ipairs(props) do
				if prop:IsA("BasePart") then
					local nearest = math.huge
					for _, plr in ipairs(players) do
						local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
						if root then
							nearest = math.min(nearest, (root.Position - prop.Position).Magnitude)
						end
					end
					-- sleep distant props: transparency 1 and no collision cost
					prop.LocalTransparencyModifier = nearest > CULL_DISTANCE and 1 or 0
				end
			end
		end
	end)
end

-- S07-029 installation visual language: every alien installation shares the same architectural
-- identity — angular sloped alloy walls in obsidian, violet shield conduits tracing power flow,
-- raised walkways connecting structures. The language reads as one civilization's engineering.
WorldDressing.INSTALLATION_STYLE = {
	wallColor = Color3.fromRGB(38, 34, 44),
	wallMaterial = Enum.Material.Metal,
	conduitColor = Color3.fromRGB(180, 100, 255),
	conduitMaterial = Enum.Material.Neon,
	walkwayHeight = 6,
}

function WorldDressing.installationStyle(parent: Instance, center: Vector3, rng: Random)
	local style = WorldDressing.INSTALLATION_STYLE
	-- sloped alloy walls: angular, leaning inward like the architecture is hunched
	for i = 1, 4 do
		local angle = math.rad(i * 90)
		local wall = Instance.new("Part")
		wall.Name = "AlloyWall" .. i
		wall.Size = Vector3.new(14, 10, 1.5)
		wall.Color = style.wallColor
		wall.Material = style.wallMaterial
		wall.Anchored = true
		wall.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * 12, 5, math.sin(angle) * 12))
			* CFrame.Angles(0, -angle, math.rad(12)) -- the slope: walls lean inward
		wall.Parent = parent
	end
	-- violet shield conduits tracing power flow between the walls
	for i = 1, 2 do
		local conduit = Instance.new("Part")
		conduit.Name = "ShieldConduit" .. i
		conduit.Size = Vector3.new(0.6, 0.6, 20)
		conduit.Color = style.conduitColor
		conduit.Material = style.conduitMaterial
		conduit.Anchored = true
		conduit.Position = center + Vector3.new((i - 1.5) * 8, 1, 0)
		conduit.Parent = parent
	end
	-- raised walkway connecting the installation
	local walkway = Instance.new("Part")
	walkway.Name = "RaisedWalkway"
	walkway.Size = Vector3.new(4, 0.8, 22)
	walkway.Color = style.wallColor
	walkway.Material = style.wallMaterial
	walkway.Anchored = true
	walkway.Position = center + Vector3.new(0, style.walkwayHeight, 0)
	walkway.Parent = parent
end

return WorldDressing

