--!strict
-- EnvironmentDressing: deterministic, rule-based scatter of authored art assets.
-- Rules (not random spray): cliffs on steep ground, flora on gentle ground,
-- military props only inside authored footprints, mountains outside the play space.

local ArtService = require(game:GetService("ServerScriptService").GF.Services.ArtService)

local EnvironmentDressing = {}

local RAY_UP = Vector3.new(0, 400, 0)

local function groundAt(x: number, z: number, ignore: {Instance}?): (number?, Vector3?)
	local origin = Vector3.new(x, 400, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local hit = workspace:Raycast(origin, Vector3.new(0, -800, 0), params)
	if hit then
		return hit.Position.Y, hit.Normal
	end
	return nil, nil
end

-- Kit scatter placement: the dressing clauses are written in scale factors, so the native
-- height is measured once and converted. Pieces go through placeKit (authored pivot, palette
-- preserved, correct uniform ScaleTo) and are NEVER tinted here — reskin/tint strips baked
-- textures. Terrain pieces ship neutral and read correctly on any biome without it.
local function kitScatter(ids: { string }, position: Vector3, scaleFactor: number, yaw: number, sink: number?, parent: Instance): Model?
	if type(ArtService.firstExists) ~= "function" or type(ArtService.placeKit) ~= "function" then
		return nil
	end
	local id = ArtService.firstExists(ids)
	if not id then
		return nil
	end
	local size = type(ArtService.measure) == "function" and ArtService.measure(id) or nil
	if not size or size.Y < 0.01 then
		return nil
	end
	return ArtService.placeKit(id, position, {
		yaw = yaw,
		height = size.Y * scaleFactor,
		sink = sink,
		parent = parent,
	})
end

local CLIFF_VARIANTS = { "Kit_Terrain_CliffA", "Kit_Terrain_CliffB", "Kit_Terrain_CliffC", "Kit_Terrain_CliffD" }

local function cliffPick(rng: Random): { string }
	local variants = {}
	for _, id in ipairs(CLIFF_VARIANTS) do
		if ArtService.exists(id) then
			table.insert(variants, id)
		end
	end
	if #variants == 0 then
		return { "RockCliff" }
	end
	return { variants[rng:NextInteger(1, #variants)] }
end

function EnvironmentDressing.dress(opts)
	local seed = opts.seed or 1
	local center = opts.center :: Vector3
	local size = opts.size :: number
	local half = size * 0.5
	local parent = (opts.parent :: Instance?) or workspace.ActiveActors
	local roster = opts.roster or {}
	local objective = opts.objective :: Vector3?

	local folder = Instance.new("Folder")
	folder.Name = "Dressing"
	folder.Parent = parent

	local rng = Random.new(seed)
	local ignore = { folder }

	local counts = { cliff = 0, flora = 0, crate = 0, barricade = 0, mountain = 0 }

	-- Distant mountain backdrop: a ring beyond the playable edge, sunk into the world.
	if ArtService.exists("MountainRidge") or ArtService.exists("Kit_Terrain_CliffA") then
		local ring = 9
		for i = 1, ring do
			local ang = (i / ring) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
			local dist = half * rng:NextNumber(1.45, 1.85)
			local x = center.X + math.cos(ang) * dist
			local z = center.Z + math.sin(ang) * dist
			local h = select(1, groundAt(x, z, ignore)) or center.Y
			local mscale = rng:NextNumber(1.5, 2.1)
			local myaw = rng:NextNumber(0, math.pi * 2)
			local msink = rng:NextNumber(24, 34)
			-- scaled-up cliff formations stand in as the horizon ring; the dedicated ridge asset
			-- never shipped, and authored rock reads as distant mountains once sunk and scaled.
			local m = kitScatter(cliffPick(rng), Vector3.new(x, h, z), mscale, myaw, msink, folder)
				or ArtService.place("MountainRidge", Vector3.new(x, h, z), {
					parent = folder,
					scale = mscale,
					yaw = myaw,
					sink = msink,
				})
			if m then
				m.Name = "Mountain" .. i
				counts.mountain += 1
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then d.CanCollide = false; d.CastShadow = false end
				end
			end
		end
	end

	-- Faceted cliff outcrops: pieces are grouped into 2-4 piece formations that
	-- share an orientation, so they read as broken rock rather than scattered dice.
	if ArtService.exists("RockCliff") or ArtService.exists("Kit_Terrain_CliffA") then
		local debugMaxSlope = -1
		local attempts = 0
		local outcrops = 0
		local target = 16
		while outcrops < target and attempts < 500 do
			attempts += 1
			local cx = center.X + rng:NextNumber(-half * 0.92, half * 0.92)
			local cz = center.Z + rng:NextNumber(-half * 0.92, half * 0.92)
			local cy, cnormal = groundAt(cx, cz, ignore)
			if cy then
				local slope = cnormal and (1 - cnormal.Y) or 0
				debugMaxSlope = math.max(debugMaxSlope or -1, slope)
				local nearObjective = objective and (Vector3.new(cx, cy, cz) - objective).Magnitude < 48
				if slope > 0.26 and not nearObjective then
					local pieces = rng:NextInteger(2, 4)
					local yaw = rng:NextNumber(0, math.pi * 2)
					local placed = 0
					for piece = 1, pieces do
						local ang = yaw + rng:NextNumber(-0.5, 0.5)
						local rad = rng:NextNumber(2.5, 9)
						local x = cx + math.cos(ang) * rad
						local z = cz + math.sin(ang) * rad
						local y = select(1, groundAt(x, z, ignore))
						if y then
							local cscale = rng:NextNumber(0.16, 0.38)
							local cyaw = yaw + rng:NextNumber(-0.35, 0.35)
							local csink = rng:NextNumber(1.5, 4)
							local kitM = kitScatter(cliffPick(rng), Vector3.new(x, y, z), cscale, cyaw, csink, folder)
							if kitM then
								kitM.Name = "Outcrop" .. outcrops .. "_" .. piece
								counts.cliff += 1
								placed += 1
							else
								local m = ArtService.place("RockCliff", Vector3.new(x, y, z), {
									parent = folder,
									scale = cscale,
									yaw = cyaw,
									sink = csink,
								})
								if m then
									m.Name = "Outcrop" .. outcrops .. "_" .. piece
									ArtService.tint(m, Color3.fromRGB(96, 100, 114), Enum.Material.Slate)
									counts.cliff += 1
									placed += 1
								end
							end
						end
					end
					if placed > 0 then outcrops += 1 end
				end
			end
		folder:SetAttribute("cliffDebug", string.format("attempts=%d outcrops=%d pieces=%d maxSlope=%.3f center=%s half=%.0f", attempts, outcrops, counts.cliff, debugMaxSlope or -1, tostring(center), half))
		end
	end

	-- Alien flora on gentle ground, denser in hollows.
	if ArtService.exists("AlienFlora") then
		local attempts = 0
		while counts.flora < 130 and attempts < 900 do
			attempts += 1
			local x = center.X + rng:NextNumber(-half * 0.9, half * 0.9)
			local z = center.Z + rng:NextNumber(-half * 0.9, half * 0.9)
			local y, normal = groundAt(x, z, ignore)
			if y and normal and normal.Y > 0.93 then
				local m = ArtService.place("AlienFlora", Vector3.new(x, y, z), {
					parent = folder,
					scale = rng:NextNumber(0.32, 0.55),
					yaw = rng:NextNumber(0, math.pi * 2),
					sink = 0.6,
				})
				if m then
					m.Name = "Flora" .. counts.flora
					-- Palette is an argument at construction, not a post-processing filter. The previous
					-- hardcoded teal belonged to a snow-lit dev world; on Veyra-7 it read as green plants
					-- on a violet planet. Recolouring the scene afterwards swept 136 unrelated parts and
					-- turned the compound near-black (V413), so the colour lives here instead.
					local floraTint = opts and opts.floraTint
					if not floraTint then
						-- Measured: reading GF_EnvironmentPreset here returned "station" because dressing runs
						-- before the mission environment is applied, so every spore still came out teal. Outdoor
						-- dressing is the mission palette by definition; the station passes its own tint if it
						-- ever wants one.
						floraTint = Color3.fromRGB(86, 74, 118)
					end
					ArtService.tint(m, floraTint, Enum.Material.SmoothPlastic)
					m:SetAttribute("GF_FloraTint", true)
					counts.flora += 1
					for _, d in m:GetDescendants() do
						if d:IsA("BasePart") then d.CanCollide = false end
					end
				end
			end
		end
	end

	-- Military props around the objective footprint.
	if objective then
		if ArtService.exists("HumanCrate") or ArtService.exists("Kit_Human_Crate") or ArtService.exists("Kit_Ascendancy_Crate") then
			for i = 1, 6 do
				local ang = (i / 6) * math.pi * 2
				local x = objective.X + math.cos(ang) * rng:NextNumber(13, 22)
				local z = objective.Z + math.sin(ang) * rng:NextNumber(13, 22)
				local y = select(1, groundAt(x, z, ignore))
				if y then
					local m = kitScatter({ "Kit_Ascendancy_Crate", "Kit_Human_Crate", "Kit_Human_Crates", "HumanCrate" },
						Vector3.new(x, y, z), rng:NextNumber(1.0, 1.35), rng:NextNumber(0, math.pi * 2), nil, folder)
						or ArtService.place("HumanCrate", Vector3.new(x, y, z), {
							parent = folder,
							scale = rng:NextNumber(1.0, 1.35),
							yaw = rng:NextNumber(0, math.pi * 2),
						})
					if m then counts.crate += 1 end
				end
			end
		end
		if ArtService.exists("AscendancyBarricade") or ArtService.exists("Kit_Ascendancy_Barricade") then
			for i = 1, 6 do
				local ang = ((i - 1) / 6) * math.pi * 2
				local x = objective.X + math.cos(ang) * rng:NextNumber(29, 39)
				local z = objective.Z + math.sin(ang) * rng:NextNumber(29, 39)
				local y = select(1, groundAt(x, z, ignore))
				if y then
					local kitM = kitScatter({ "Kit_Ascendancy_Barricade" }, Vector3.new(x, y, z),
						rng:NextNumber(0.62, 0.8), ang + math.pi * 0.5, nil, folder)
					if kitM then
						kitM.Name = "Barricade" .. i
						counts.barricade += 1
					else
						local m = ArtService.place("AscendancyBarricade", Vector3.new(x, y, z), {
							parent = folder,
							scale = rng:NextNumber(0.62, 0.8),
							yaw = ang + math.pi * 0.5,
						})
						if m then
							m.Name = "Barricade" .. i
							ArtService.tint(m, Color3.fromRGB(74, 72, 86), Enum.Material.Metal)
							counts.barricade += 1
						end
					end
				end
			end
		end
	end

	return counts, folder
end

function EnvironmentDressing.clear()
	for _, c in workspace:GetChildren() do
		if c:IsA("Folder") and c.Name == "Dressing" then c:Destroy() end
	end
	for _, c in workspace.ActiveActors:GetChildren() do
		if c:IsA("Folder") and c.Name == "Dressing" then c:Destroy() end
	end
end

return EnvironmentDressing

