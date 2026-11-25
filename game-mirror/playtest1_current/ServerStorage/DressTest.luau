--!strict
-- EnvironmentDressing: deterministic, rule-based scatter of authored art assets.
-- Rules (not random spray): cliffs on steep ground, flora on gentle ground,
-- military props only inside authored footprints, mountains outside the play space.

local ArtService = require(script.Parent.ArtService)

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
	if ArtService.exists("MountainRidge") then
		local ring = 10
		for i = 1, ring do
			local ang = (i / ring) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
			local dist = half * rng:NextNumber(1.05, 1.35)
			local x = center.X + math.cos(ang) * dist
			local z = center.Z + math.sin(ang) * dist
			local h = select(1, groundAt(x, z, ignore)) or center.Y
			local m = ArtService.place("MountainRidge", Vector3.new(x, h, z), {
				parent = folder,
				scale = rng:NextNumber(3.0, 4.6),
				yaw = rng:NextNumber(0, math.pi * 2),
				sink = 18,
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

	-- Faceted cliff outcrops on steeper ground.
	if ArtService.exists("RockCliff") then
		local attempts = 0
		local target = 46
		while counts.cliff < target and attempts < 600 do
			attempts += 1
			local x = center.X + rng:NextNumber(-half * 0.94, half * 0.94)
			local z = center.Z + rng:NextNumber(-half * 0.94, half * 0.94)
			local y, normal = groundAt(x, z, ignore)
			if y then
				local slope = normal and (1 - normal.Y) or 0
				local nearObjective = objective and (Vector3.new(x, y, z) - objective).Magnitude < 34
				if slope > 0.18 and not nearObjective then
					local m = ArtService.place("RockCliff", Vector3.new(x, y, z), {
						parent = folder,
						scale = rng:NextNumber(1.4, 3.4),
						yaw = rng:NextNumber(0, math.pi * 2),
						sink = rng:NextNumber(2, 7),
					})
					if m then
						m.Name = "Cliff" .. counts.cliff
						counts.cliff += 1
					end
				end
			end
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
					scale = rng:NextNumber(0.7, 1.5),
					yaw = rng:NextNumber(0, math.pi * 2),
					sink = 0.6,
				})
				if m then
					m.Name = "Flora" .. counts.flora
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
		if ArtService.exists("HumanCrate") then
			for i = 1, 6 do
				local ang = (i / 6) * math.pi * 2
				local x = objective.X + math.cos(ang) * rng:NextNumber(13, 22)
				local z = objective.Z + math.sin(ang) * rng:NextNumber(13, 22)
				local y = select(1, groundAt(x, z, ignore))
				if y then
					local m = ArtService.place("HumanCrate", Vector3.new(x, y, z), {
						parent = folder,
						scale = rng:NextNumber(1.0, 1.35),
						yaw = rng:NextNumber(0, math.pi * 2),
					})
					if m then counts.crate += 1 end
				end
			end
		end
		if ArtService.exists("AscendancyBarricade") then
			for i = 1, 8 do
				local ang = (i / 8) * math.pi * 2 + 0.3
				local x = objective.X + math.cos(ang) * rng:NextNumber(26, 38)
				local z = objective.Z + math.sin(ang) * rng:NextNumber(26, 38)
				local y = select(1, groundAt(x, z, ignore))
				if y then
					local m = ArtService.place("AscendancyBarricade", Vector3.new(x, y, z), {
						parent = folder,
						scale = rng:NextNumber(1.5, 2.3),
						yaw = ang + math.pi * 0.5,
					})
					if m then
						m.Name = "Barricade" .. i
						counts.barricade += 1
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

