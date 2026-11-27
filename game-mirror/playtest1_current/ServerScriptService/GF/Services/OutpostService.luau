--!strict
-- OutpostService: composes the Ascendancy relay compound as a modular kit.
-- Deterministic: the same seed always yields the same layout, so the outpost reads as
-- architecture rather than as scattered props.

local ArtService = require(script.Parent.ArtService)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OutpostService = {}

local WALL_RADIUS = 38
local WALL_COUNT = 12
local GATE_SEGMENTS = { [4] = true, [10] = true }
local TOWER_RADIUS = 44

local DECK = Color3.fromRGB(62, 62, 72)
local HULL = Color3.fromRGB(44, 44, 54)
local AMBER = Color3.fromRGB(104, 208, 226) -- Ascendancy energy signature: cold cyan, not hazard orange

-- Deterministic 32-bit LCG: layout must not change between sessions for the same seed.
local function rng(seed: number)
	local state = seed % 2147483647
	if state <= 0 then state += 2147483646 end
	return function(): number
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
end

local function ignoreList(extra: Instance?): { Instance }
	local list: { Instance } = {}
	if extra then table.insert(list, extra) end
	for _, name in { "ActiveActors", "Dressing" } do
		local found = workspace:FindFirstChild(name)
		if found and found ~= extra then table.insert(list, found) end
	end
	return list
end

local function groundY(position: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 140, 0), Vector3.new(0, -300, 0), params)
	return hit and hit.Position.Y or position.Y
end

local function plate(parent: Instance, position: Vector3, size: Vector3, yaw: number, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Anchored = true
	part.Color = color
	part.Material = material
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Places an art model on the ground, falling back to a plain slab so the compound never
-- loses its silhouette if an asset is missing. Accepts a preference list of candidate ids:
-- authored Kit_* pieces (Blender, palette-textured, bottom-centre pivots) are placed via
-- placeKit and NEVER reskinned — reskin strips the baked palette, which is what made wired
-- art read as flat grey plastic. Legacy un-prefixed assets keep the old reskin behaviour.
local function piece(ids: any, parent: Instance, position: Vector3, yaw: number, height: number, fallback: Vector3): Model
	local list: { string } = if type(ids) == "string" then { ids } else ids
	local id = ArtService.firstExists(list)
	if id then
		if string.sub(id, 1, 4) == "Kit_" then
			local placed = ArtService.placeKit(id, position, {
				height = height,
				yaw = yaw,
				parent = parent,
				collide = true,
			})
			if placed then return placed end
		else
			local placed = ArtService.place(id, position, {
				height = height,
				yaw = yaw,
				parent = parent,
			})
			if placed then
				placed.Parent = parent
				for _, d in placed:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = true
					end
				end
				ArtService.reskin(placed, HULL, Enum.Material.Metal)
				return placed
			end
		end
	end
	local model = Instance.new("Model")
	model.Name = list[1] .. "_fallback"
	model.Parent = parent
	local slab = plate(model, position + Vector3.new(0, fallback.Y * 0.5, 0), fallback, yaw, HULL, Enum.Material.Slate)
	model.PrimaryPart = slab
	return model
end

local function lightMast(parent: Instance, position: Vector3): Part
	local mast = plate(parent, position + Vector3.new(0, 5.5, 0), Vector3.new(0.5, 11, 0.5), 0, HULL, Enum.Material.Metal)
	mast.Name = "LightMast"
	local lamp = plate(parent, position + Vector3.new(0, 11.4, 0), Vector3.new(1.5, 1.5, 1.5), 0, AMBER, Enum.Material.Neon)
	lamp.Name = "Lamp"
	lamp.CanCollide = false
	local light = Instance.new("PointLight")
	light.Shadows = false
	light.Color = AMBER
	light.Brightness = 2.4
	light.Range = 38
	light.Parent = lamp
	return mast
end

function OutpostService.build(center: Vector3, seed: number?): Model
	local folder = Instance.new("Model")
	folder.Name = "AscendancyOutpost"
	folder:SetAttribute("GFOutpost", true)
	folder:SetAttribute("OutpostSeed", seed or 20260621)

	local ignore = ignoreList(folder)
	local base = Vector3.new(center.X, groundY(center, ignore), center.Z)
	local random = rng(seed or 20260621)
	local pieces = 0

	-- Level the compound: a plateau under the ring, so the wall modules sit on one
	-- plane instead of stepping down the hillside like scattered blocks.
	local terrain = workspace.Terrain
	local padRadius = WALL_RADIUS + 14
	local padCenter = Vector3.new(base.X, base.Y, base.Z)
	terrain:FillCylinder(CFrame.new(padCenter + Vector3.new(0, 8, 0)), 40, padRadius, Enum.Material.Air)
	terrain:FillCylinder(CFrame.new(padCenter - Vector3.new(0, 18, 0)), 36, padRadius, Enum.Material.Rock)

	-- Perimeter: authored masonry walls chained edge-to-edge along the ring's wall arcs, with
	-- monumental gates closing the two entrance sockets. Piece length is measured at runtime
	-- and pieces are uniformly scaled so each contiguous arc closes exactly — joints overlap
	-- slightly rather than opening sight-line gaps. Slab modules remain the fallback.
	local wallId = ArtService.firstExists({ "Kit_Ascendancy_Wall", "AscendancyOutpostWall" })
	local wallSize = if wallId then ArtService.measure(wallId :: string) else nil
	local useKitWall = wallId ~= nil and string.sub(wallId :: string, 1, 4) == "Kit_" and wallSize ~= nil

	if useKitWall and wallSize then
		local segAng = math.pi * 2 / WALL_COUNT
		-- contiguous runs of non-gate segments; a trailing run wraps into a leading one
		local runs: { { number } } = {}
		local run: { number } = {}
		for i = 1, WALL_COUNT do
			if not GATE_SEGMENTS[i] then
				table.insert(run, i)
			elseif #run > 0 then
				table.insert(runs, run)
				run = {}
			end
		end
		if #run > 0 then
			if #runs > 0 and not GATE_SEGMENTS[1] then
				local merged = table.clone(run)
				for _, s in ipairs(runs[1]) do table.insert(merged, s) end
				runs[1] = merged
			else
				table.insert(runs, run)
			end
		end
		-- wall length axis: the long horizontal dimension, chained tangent to the ring
		local lenAxisX = wallSize.X >= wallSize.Z
		local nativeLen = math.max(wallSize.X, wallSize.Z)
		local nativeH = wallSize.Y
		for _, segs in ipairs(runs) do
			local arcSpan = #segs * segAng
			local arcLen = arcSpan * WALL_RADIUS
			local nPieces = math.max(1, math.round(arcLen / nativeLen))
			local scaledLen = arcLen / nPieces
			local factor = scaledLen / nativeLen
			local targetH = nativeH * factor
			local startAng = (segs[1] - 1) * segAng - segAng * 0.5
			for j = 1, nPieces do
				local theta = startAng + (j - 0.5) / nPieces * arcSpan
				local dir = Vector3.new(math.cos(theta), 0, math.sin(theta))
				local wallPos = base + dir * WALL_RADIUS
				-- tangent alignment: length axis along the ring; axis-dependent yaw
				local yaw = if lenAxisX then -theta - math.pi * 0.5 else -theta
				piece({ wallId :: string }, folder, Vector3.new(wallPos.X, base.Y, wallPos.Z), yaw, targetH,
					Vector3.new(scaledLen, targetH, 6))
				pieces += 1
			end
		end
	else
		for i = 1, WALL_COUNT do
			if not GATE_SEGMENTS[i] then
				local angle = (i - 1) / WALL_COUNT * math.pi * 2
				-- three modules per bay, each yawed tangent to the ring at its own angle, so the
				-- modules meet edge to edge instead of leaving sight-line gaps
				local arc = math.pi * 2 / WALL_COUNT
				for _, bias in { -0.333, 0, 0.333 } do
					local theta = angle + arc * bias
					local dir = Vector3.new(math.cos(theta), 0, math.sin(theta))
					local wallPos = base + dir * WALL_RADIUS
					piece({ "AscendancyOutpostWall" }, folder, Vector3.new(wallPos.X, base.Y, wallPos.Z), theta + math.pi * 0.5, 9,
						Vector3.new(9, 9, 8))
					pieces += 1
				end
			end
		end
	end

	-- Monumental gates close the two entrance sockets — the compound's approach reads from
	-- across the field instead of being an unmarked gap in the ring. Kit-only: without the
	-- authored piece the sockets stay open (a fallback slab here would wall off the entrance).
	if ArtService.exists("Kit_Ascendancy_Gate") then
		for i in pairs(GATE_SEGMENTS) do
			local angle = (i - 1) / WALL_COUNT * math.pi * 2
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local gatePos = base + dir * WALL_RADIUS
			piece({ "Kit_Ascendancy_Gate" }, folder, Vector3.new(gatePos.X, base.Y, gatePos.Z), -angle - math.pi * 0.5, 20,
				Vector3.new(14, 12, 4))
			pieces += 1
		end
	end

	-- Watchtowers on the diagonals so they frame the compound without blocking the gates.
	for i = 0, 3 do
		local angle = math.pi * 0.25 + i * math.pi * 0.5
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local towerPos = base + radial * TOWER_RADIUS
		piece({ "Kit_Ascendancy_Tower", "AscendancyWatchtower" }, folder, Vector3.new(towerPos.X, base.Y, towerPos.Z), -angle + math.pi, 30,
			Vector3.new(9, 30, 9))
		pieces += 1
	end

	-- Approach: a plated causeway from the primary gate to the relay deck, flanked by barricades.
	local approachYaw = math.pi * 0.5
	for step = 0, 5 do
		local z = base.Z + 26 + step * 7
		local y = groundY(Vector3.new(base.X, base.Y, z), ignore)
		plate(folder, Vector3.new(base.X, y + 0.35, z), Vector3.new(14, 0.7, 7.2), 0, DECK, Enum.Material.DiamondPlate)
	end
	for _, side in { -1, 1 } do
		piece({ "Kit_Ascendancy_Barricade", "AscendancyBarricade" }, folder, Vector3.new(base.X + side * 9, groundY(Vector3.new(base.X + side * 9, base.Y, base.Z + 34), ignore), base.Z + 34), approachYaw, 4.5,
			Vector3.new(2.5, 4.5, 9))
		piece({ "Kit_Ascendancy_Barricade", "AscendancyBarricade" }, folder, Vector3.new(base.X + side * 9, groundY(Vector3.new(base.X + side * 9, base.Y, base.Z + 48), ignore), base.Z + 48), approachYaw, 4.5,
			Vector3.new(2.5, 4.5, 9))
		pieces += 2
	end

	-- Yard clutter: crates clustered where a squad would stage, never in the firing lanes.
	for i = 1, 4 do
		local angle = 1.1 + i * 0.42
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local spot = base + radial * (20 + random() * 7)
		local y = groundY(Vector3.new(spot.X, base.Y, spot.Z), ignore)
		piece({ "Kit_Ascendancy_Crate", "Kit_Human_Crate", "HumanCrate" }, folder, Vector3.new(spot.X, y, spot.Z), random() * math.pi, 3.4,
			Vector3.new(3, 3.4, 3))
		pieces += 1
	end

	-- Four lamps only: the lighting budget is shared with the relay core and weapon VFX.
	for i = 0, 3 do
		local angle = math.pi * 0.25 + i * math.pi * 0.5
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local spot = base + radial * 24
		lightMast(folder, Vector3.new(spot.X, groundY(Vector3.new(spot.X, base.Y, spot.Z), ignore), spot.Z))
	end

	folder.PrimaryPart = folder:FindFirstChildWhichIsA("BasePart", true)
	folder.Parent = ArtService.actorsFolder()
	folder:SetAttribute("OutpostPieces", pieces)
	-- S07-030/032 functional props: the compound reads as a military installation — a power switch
	-- feeding the relay shield, an ammo depot of stacked sealed crates, and the split-spire relay
	-- emitter as the tallest silhouette. Layout communicates function at a glance.
	do
		-- power switch: a pedestal with a glowing breaker handle near the relay; hacking it first
		-- drops the relay shield faster (the tactical choice the spec wants legible)
		local switch = plate(folder, base + Vector3.new(6, 1.2, 6), Vector3.new(1.6, 2.4, 1.6), 0, Color3.fromRGB(60, 70, 84), Enum.Material.Metal)
		switch.Name = "PowerSwitch"
		switch:SetAttribute("GFSwitch", true)
		local handle = plate(folder, base + Vector3.new(6, 2.9, 6), Vector3.new(0.4, 1.0, 0.4), 0, Color3.fromRGB(255, 190, 80), Enum.Material.Neon)
		handle.Name = "PowerSwitchHandle"
		-- ammo depot: stacked sealed crates in a corner cluster
		for i = 1, 5 do
			local layer = math.floor((i - 1) / 2)
			local crate = plate(folder, base + Vector3.new(-9 + (i % 2) * 2.2, 1 + layer * 1.6, -8), Vector3.new(2, 1.5, 2), (i % 3) * 0.2, Color3.fromRGB(96, 84, 64), Enum.Material.Wood)
			crate.Name = "AmmoCrate" .. i
			crate:SetAttribute("AmmoDepot", true)
		end
		-- split-spire relay emitter: two tall spires flanking the relay — the outpost's dominant
		-- silhouette so players read "this is the relay site" from across the field. Authored kit
		-- spires taper to ivory tips and echo the relay's own split shafts; slab spires + arc
		-- remain the fallback.
		if workspace:GetAttribute("GF_RelayKitPlaced") == true then
			-- the authored relay is itself the dominant split-shaft silhouette; flanking
			-- spires would clip into it, so the composition stays clean
		elseif ArtService.exists("Kit_Ascendancy_Spire") then
			for _, side in ipairs({ -1, 1 }) do
				piece({ "Kit_Ascendancy_Spire" }, folder, base + Vector3.new(side * 5, 0, -3), math.rad(side * 8), 20,
					Vector3.new(1.2, 18, 1.2))
			end
		else
			for _, side in ipairs({ -1, 1 }) do
				local spire = plate(folder, base + Vector3.new(side * 3.5, 9, -2), Vector3.new(1.2, 18, 1.2), 0, Color3.fromRGB(70, 80, 96), Enum.Material.Metal)
				spire.Name = "RelaySpire" .. (side == -1 and "L" or "R")
				spire.CFrame = spire.CFrame * CFrame.Angles(0, 0, math.rad(side * -8))
			end
			local arc = plate(folder, base + Vector3.new(0, 17.5, -2), Vector3.new(0.5, 2.2, 0.5), 0, Color3.fromRGB(140, 220, 255), Enum.Material.Neon)
			arc.Name = "RelayArc"
		end
	end

	return folder
end

return OutpostService

