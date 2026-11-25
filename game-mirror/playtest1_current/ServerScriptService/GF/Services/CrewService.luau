--!strict
-- Station crew: real rigs standing in the concourse, animated procedurally on the client.
-- The old audit found four to eight "ambient crew actors" only as mission enemies; the station had
-- none, so every frame was an empty hangar. Humanoid animations need asset ids and the classic R15
-- idle ids load with Length 0 in this place (measured), so the crew is driven by Motor6D offsets
-- instead: no uploads, no assets, and the cost stays on the client.
local CrewService = {}

local CREW = {
	{ name = "Crew_Deck", pos = Vector3.new(-26, 0, 12), face = math.rad(200), role = "idle" },
	{ name = "Crew_Table", pos = Vector3.new(20, 0, -18), face = math.rad(150), role = "idle" },
	{ name = "Crew_Rail", pos = Vector3.new(-44, 0, -52), face = math.rad(20), role = "rest" },
	{ name = "Crew_Rack", pos = Vector3.new(-34, 0, 30), face = math.rad(250), role = "rest" },
	{ name = "Crew_PatrolA", pos = Vector3.new(40, 0, 26), face = math.rad(180), role = "patrol" },
	{ name = "Crew_PatrolB", pos = Vector3.new(46, 0, -6), face = math.rad(90), role = "patrol" },
}

local DECK_Y = 761.05

local function findTemplate()
	-- Crew must not be built from an Ascendancy rig: once the aliens got an original crest, every crew
	-- member inherited it and the station was staffed by hostiles. Prefer the authored human rig.
	local ServerStorage = game:GetService("ServerStorage")
	local art = ServerStorage:FindFirstChild("GF")
	local lib = art and art:FindFirstChild("Art")
	local human = lib and lib:FindFirstChild("GFSoldierRig")
	if human and human:IsA("Model") then
		return human
	end
	local actors = workspace:FindFirstChild("ActiveActors")
	if actors then
		for _, m in ipairs(actors:GetChildren()) do
			if m:IsA("Model") and m:FindFirstChildWhichIsA("Humanoid", true) and not m:FindFirstChild("AscendancyTrooper", true) then
				return m
			end
		end
	end
	return nil
end

local function strip(rig: Model)
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("Humanoid") then
			-- no physics ownership: the crew must never push a player or fight the deck
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			d:ChangeState(Enum.HumanoidStateType.Physics)
		elseif d:IsA("BasePart") then
			-- SurfaceAppearance from the enemy kit keeps the crew looking like hostiles, and it also
			-- overrides Color, so it goes before any recolour.
			for _, child in ipairs(d:GetChildren()) do
				if child:IsA("SurfaceAppearance") or child:IsA("Decal") or child:IsA("Texture") then
					child:Destroy()
				end
			end
			-- Only the root is anchored. Anchored parts ignore their Motor6D, which is why the first
			-- pass produced crew that never moved a limb no matter what C0 was set to (V213).
			d.Anchored = (d.Name == "HumanoidRootPart")
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = false
		end
	end
end

function CrewService.build()
	-- Boot order: StationService and ArtService place their parts on their own defer, so the crew
	-- cannot assume the shell or a rig template already exists. First attempt returned 0 silently
	-- and no crew ever appeared.
	local deadline = os.clock() + 25
	local station, template
	while os.clock() < deadline do
		station = workspace:FindFirstChild("Station")
		template = findTemplate()
		if station and template then
			break
		end
		task.wait(0.25)
	end
	if not station then
		warn("[GF] crew: station never appeared")
		return 0
	end
	if not template then
		warn("[GF] crew: no rig template available")
		return 0
	end
	local old = workspace:FindFirstChild("Crew")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Crew"
	folder.Parent = workspace

	local built = 0
	for _, spec in ipairs(CREW) do
		local cloneOk, rig = pcall(function()
			return template:Clone()
		end)
		if cloneOk and rig then
			strip(rig)
			rig.Name = spec.name
			local pivot = CFrame.new(Vector3.new(spec.pos.X, DECK_Y + 3.0, spec.pos.Z)) * CFrame.Angles(0, spec.face, 0)
			rig:PivotTo(pivot)
			rig:SetAttribute("GFCrew", true)
			rig:SetAttribute("CrewRole", spec.role)
			-- Station uniform: light plating with a cyan shoulder, so crew read as personnel at a
			-- glance instead of as the enemy kit they were cloned from.
			local PAINT = {
				UpperTorso = Color3.fromRGB(96, 108, 124),
				LowerTorso = Color3.fromRGB(78, 88, 102),
				LeftUpperArm = Color3.fromRGB(88, 100, 116),
				RightUpperArm = Color3.fromRGB(88, 100, 116),
				LeftUpperLeg = Color3.fromRGB(72, 82, 96),
				RightUpperLeg = Color3.fromRGB(72, 82, 96),
				LeftLowerLeg = Color3.fromRGB(62, 70, 82),
				RightLowerLeg = Color3.fromRGB(62, 70, 82),
				Head = Color3.fromRGB(148, 156, 168),
				LeftHand = Color3.fromRGB(60, 66, 78),
				RightHand = Color3.fromRGB(60, 66, 78),
			}
			for _, d in ipairs(rig:GetDescendants()) do
				if d:IsA("BasePart") then
					if d.Name == "Visor" then
						d.Color = Color3.fromRGB(96, 200, 255)
						d.Material = Enum.Material.Neon
					elseif PAINT[d.Name] then
						d.Color = PAINT[d.Name]
						d.Material = Enum.Material.SmoothPlastic
					end
				end
			end
			rig.Parent = folder
			-- AppearanceService re-dresses rigs after they are parented, which brings the nested
			-- AscendancyTrooper parts back with CanCollide=true. Enforce again, and keep enforcing.
			local function enforce(d)
				if d:IsA("BasePart") then
					d.Anchored = (d.Name == "HumanoidRootPart")
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.CastShadow = false
				end
			end
			for _, d in ipairs(rig:GetDescendants()) do
				enforce(d)
			end
			rig.DescendantAdded:Connect(enforce)
			built += 1
		end
	end
	workspace:SetAttribute("GF_CrewCount", built)
	-- AppearanceService sets CanCollide back on the parts it dresses, as a property change rather
	-- than a new instance, so DescendantAdded never fires for it. Re-sweep for a few seconds while
	-- boot settles, then stop: a permanent loop here would burn CPU on Xbox One for no gain.
	task.spawn(function()
		for _ = 1, 48 do
			task.wait(0.25)
			for _, rig in ipairs(folder:GetChildren()) do
				for _, d in ipairs(rig:GetDescendants()) do
					if d:IsA("BasePart") then
						d.CanCollide = false
					end
				end
			end
		end
		for _, rig in ipairs(folder:GetChildren()) do
			local stillOn = 0
			for _, d in ipairs(rig:GetDescendants()) do
				if d:IsA("BasePart") and d.CanCollide then
					stillOn += 1
				end
			end
			if stillOn > 0 then
				warn(string.format("[GF] crew: %s still has %d colliding parts", rig.Name, stillOn))
			end
		end
	end)
	print(string.format("[GF] crew: %d actors placed", built))
	return built
end

return CrewService

