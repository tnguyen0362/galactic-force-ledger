--!nonstrict
-- Objective: template-driven. Before this, the service hard-coded the Ascendancy relay, so two of
-- the three configured mission templates (RECOVER_TECH, DEFEND_BEACON) had no objective object,
-- no interaction and no completion condition at all -- they could not be played.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ArtService = require(script.Parent.ArtService)
local OutpostService = require(script.Parent.OutpostService)
local TweenService = game:GetService("TweenService")
local State = require(script.Parent.State)
local EnemyService = require(script.Parent.EnemyService)
local BastionWalker = require(script.Parent.Parent.BastionWalker)
local Veyr = require(script.Parent.Parent.Veyr)

local ObjectiveService = {}
local SABOTAGE_HOLD = 2.5
local RECOVER_HOLD = 7.0
local DEFEND_ACTIVATE = 2.5
local DEFEND_TIME = 60
local INTERACT_RANGE = 9 -- spec: interact instant on valid range <=9 studs

local objective: Model? = nil
local templateId = "SABOTAGE_RELAY"
local progress = 0
local complete = false
local holding = {}
local carrying: { [Player]: boolean } = {}
local carryModels: { [Player]: Model } = {}
local deliveryRing: Part? = nil

-- The carried case and the delivery patch are what make a fetch-and-carry readable. Without them the only
-- feedback was one line of text, which is not a mechanic a player can perceive.
local function attachCase(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or carryModels[player] then
		return
	end
	local model = Instance.new("Model")
	model.Name = "CarriedCase"
	local case = Instance.new("Part")
	case.Name = "Case"
	case.Size = Vector3.new(1.6, 1.1, 0.7)
	case.Color = Color3.fromRGB(255, 176, 64)
	case.Material = Enum.Material.Metal
	case.CanCollide = false
	case.CanQuery = false
	case.Massless = true
	case.CFrame = root.CFrame * CFrame.new(0, -0.2, 1.1)
	case.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = case
	weld.Parent = case
	model.PrimaryPart = case
	model.Parent = character
	carryModels[player] = model
end

local function dropCase(player: Player)
	local model = carryModels[player]
	if model then
		model:Destroy()
		carryModels[player] = nil
	end
end

local function showDeliveryRing()
	if deliveryRing and deliveryRing.Parent then
		return
	end
	local lz = workspace:GetAttribute("GF_LZ")
	if typeof(lz) ~= "Vector3" then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = "DeliveryPatch"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 36, 36)
	ring.CFrame = CFrame.new(lz + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(120, 210, 255)
	ring.Transparency = 0.75
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Parent = workspace
	deliveryRing = ring
end
local defending = false
local defendEndsAt = 0
local hint = ""

local function remote(name) return ReplicatedStorage.GF.Remotes:FindFirstChild(name) end

-- Marker source. Elimination points at the nearest living target (it changes as they die); every
-- other template points at its own objective. Clients decide whether that reads as approximate or
-- exact from their own distance.
-- Declared here because currentMarker (defined above the family builders) needs the same table.
local elimTargets: { [Model]: boolean } = {}

local function currentMarker(): (Vector3?, string)
	if templateId == "ELIM_COMMANDER" or templateId == "ELIM_WALKER" or templateId == "ELIM_TALON" then
		for model in pairs(elimTargets) do
			if model.Parent and model:GetAttribute("Dead") ~= true then
				local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
				if part then
					return part.Position, "TARGET"
				end
			end
		end
	end
	local part = objective and objective.PrimaryPart
	if part then
		return part.Position, "OBJECTIVE"
	end
	return nil, ""
end

local function publish()
	local r = remote("ObjectiveProgress")
	if r then
		local spot, label = currentMarker()
		r:FireAllClients({
			progress = progress,
			complete = complete,
			template = templateId,
			hint = hint,
			marker = complete and nil or (spot and { position = spot, label = label } or nil),
		})
	end
end

local function partOf(model, size, offset, color, material, position)
	local p = Instance.new("Part")
	p.Size = size; p.Position = position + offset
	p.Color = color; p.Material = material; p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function ground(position)
	local TerrainService = require(script.Parent.TerrainService)
	return Vector3.new(position.X, TerrainService.groundSurface(position.X, position.Z) + 0.4, position.Z)
end

local function buildRelay(position)
	local model = Instance.new("Model")
	model.Name = "AscendancyRelay"
	model:SetAttribute("GFObjective", "Relay")
	local base = partOf(model, Vector3.new(16, 2, 16), Vector3.new(0, 1, 0), Color3.fromRGB(38, 38, 44), Enum.Material.Slate, position)
	base.Transparency = 1
	local plinth = partOf(model, Vector3.new(15, 1.4, 15), Vector3.new(0, 0.7, 0), Color3.fromRGB(44, 43, 50), Enum.Material.Slate, position)
	plinth.Name = "Plinth"
	local tower = ArtService.place("AscendancyRelay", position + Vector3.new(0, 0.9, 0), { height = 30 })
	if tower then
		tower.Name = "RelayTower"
		tower.Parent = model
		ArtService.reskin(tower, Color3.fromRGB(58, 54, 70), Enum.Material.Metal)
		for _, d in tower:GetDescendants() do if d:IsA("BasePart") then d.CanCollide = true end end
	else
		partOf(model, Vector3.new(4, 18, 4), Vector3.new(0, 10, 0), Color3.fromRGB(52, 50, 58), Enum.Material.Metal, position)
		partOf(model, Vector3.new(2.5, 8, 2.5), Vector3.new(0, 22, 0), Color3.fromRGB(60, 56, 66), Enum.Material.Metal, position)
	end
	local core = partOf(model, Vector3.new(2.2, 2.2, 2.2), Vector3.new(0, 16, 0), Color3.fromRGB(96, 214, 232), Enum.Material.Neon, position)
	core.Name = "CoreGlow"
	local light = Instance.new("PointLight")
	light.Shadows = false; light.Color = Color3.fromRGB(96, 214, 232); light.Brightness = 1.5; light.Range = 26
	light.Parent = core
	local deck = partOf(model, Vector3.new(7, 0.6, 5), Vector3.new(0, 0.3, 11), Color3.fromRGB(62, 62, 72), Enum.Material.DiamondPlate, position)
	deck.Name = "ConsoleDeck"
	local terminal = partOf(model, Vector3.new(2.6, 3.0, 1.4), Vector3.new(0, 2.1, 11), Color3.fromRGB(34, 38, 48), Enum.Material.Metal, position)
	local screen = partOf(model, Vector3.new(2.0, 1.4, 0.12), Vector3.new(0, 2.9, 10.25), Color3.fromRGB(90, 220, 255), Enum.Material.Neon, position)
	screen.Name = "TerminalScreen"; screen.CanCollide = false
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "Relay")
	terminal:SetAttribute("InteractPrompt", "Sabotage Relay")
	-- Dressing pass: the compound read as a bare slab of grey. Deck seams, hazard chevrons and a lit perimeter
	-- give the objective an edge and a scale reference without adding lights (which are the expensive thing).
	local hazard = Color3.fromRGB(198, 158, 44)
	local plate = Color3.fromRGB(78, 84, 96)
	for i = -3, 3 do
		local seam = partOf(model, Vector3.new(0.35, 0.12, 26), Vector3.new(i * 3.4, 0.62, 6), plate, Enum.Material.Metal, position)
		seam.Name = "DeckSeam"
		seam.CanCollide = false
	end
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + math.pi / 4
		local chevron = partOf(model, Vector3.new(4.2, 0.14, 1.1), Vector3.new(math.cos(a) * 9, 0.62, math.sin(a) * 9 + 6), hazard, Enum.Material.SmoothPlastic, position)
		chevron.Name = "HazardChevron"
		chevron.CanCollide = false
		chevron.CFrame = chevron.CFrame * CFrame.Angles(0, -a, 0)
	end
	for i = 1, 4 do
		local edge = (i % 2 == 0) and 1 or -1
		local strip = partOf(model, Vector3.new(0.3, 0.2, 26), Vector3.new(edge * 11.5, 0.66, 6), Color3.fromRGB(96, 214, 232), Enum.Material.Neon, position)
		strip.Name = "PerimeterStrip"
		strip.CanCollide = false
	end
	for i = 1, 2 do
		local stanchion = partOf(model, Vector3.new(0.5, 4.2, 0.5), Vector3.new(i == 1 and -6 or 6, 2.1, 15), plate, Enum.Material.Metal, position)
		stanchion.Name = "Stanchion"
		local lamp = partOf(model, Vector3.new(0.7, 0.3, 0.7), Vector3.new(stanchion.Position.X, 4.3, 15), Color3.fromRGB(255, 214, 140), Enum.Material.Neon, position)
		lamp.Name = "StanchionLamp"
		lamp.CanCollide = false
	end
	model.PrimaryPart = base
	model.Parent = workspace.ActiveActors
	workspace:SetAttribute("GF_RelayDressing", #model:GetChildren())
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

local function buildBlackBox(position)
	local model = Instance.new("Model")
	model.Name = "ScientificTransport"
	model:SetAttribute("GFObjective", "BlackBox")
	-- the downed transport: fuselage, wing, scorch, and the black box on the ground beside it
	local hull = partOf(model, Vector3.new(22, 7, 9), Vector3.new(0, 3.5, 0), Color3.fromRGB(72, 76, 86), Enum.Material.Metal, position)
	hull.Name = "Fuselage"
	hull.CFrame = CFrame.new(position + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, math.rad(18), math.rad(-7))
	local wing = partOf(model, Vector3.new(16, 0.8, 5), Vector3.new(-3, 4.2, 0), Color3.fromRGB(64, 68, 78), Enum.Material.Metal, position)
	wing.CFrame = CFrame.new(position + Vector3.new(-3, 4.2, 0)) * CFrame.Angles(0, math.rad(18), math.rad(14))
	local crate = partOf(model, Vector3.new(4.2, 3.2, 3.4), Vector3.new(8, 1.9, 3), Color3.fromRGB(28, 30, 36), Enum.Material.Metal, position)
	crate.Name = "BlackBox"
	local lid = partOf(model, Vector3.new(4.0, 0.3, 3.2), Vector3.new(8, 3.6, 3), Color3.fromRGB(232, 168, 64), Enum.Material.Neon, position)
	lid.Name = "Lid"
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(232, 168, 64); glow.Brightness = 1.1; glow.Range = 18; glow.Shadows = false
	glow.Parent = lid
	local terminal = partOf(model, Vector3.new(1.8, 2.2, 1.0), Vector3.new(8, 1.1, 5.4), Color3.fromRGB(34, 38, 48), Enum.Material.Metal, position)
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "BlackBox")
	terminal:SetAttribute("InteractPrompt", "Extract Black Box")
	model.PrimaryPart = crate
	model.Parent = workspace.ActiveActors
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

local function buildBeacon(position)
	local model = Instance.new("Model")
	model.Name = "CommBeacon"
	model:SetAttribute("GFObjective", "Beacon")
	local base = partOf(model, Vector3.new(12, 1.2, 12), Vector3.new(0, 0.6, 0), Color3.fromRGB(40, 44, 52), Enum.Material.Slate, position)
	base.Name = "BeaconBase"
	local mast = partOf(model, Vector3.new(2, 16, 2), Vector3.new(0, 8.6, 0), Color3.fromRGB(58, 62, 72), Enum.Material.Metal, position)
	mast.Name = "Mast"
	local dish = partOf(model, Vector3.new(6, 0.6, 6), Vector3.new(0, 17, 0), Color3.fromRGB(70, 76, 88), Enum.Material.Metal, position)
	dish.CFrame = CFrame.new(position + Vector3.new(0, 17, 0)) * CFrame.Angles(math.rad(-28), 0, 0)
	local lamp = partOf(model, Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 18.6, 0), Color3.fromRGB(96, 214, 232), Enum.Material.Neon, position)
	lamp.Name = "BeaconLamp"
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(96, 214, 232); light.Brightness = 0.2; light.Range = 24; light.Shadows = false
	light.Parent = lamp
	local terminal = partOf(model, Vector3.new(2.4, 2.6, 1.4), Vector3.new(0, 1.8, 7), Color3.fromRGB(34, 38, 48), Enum.Material.Metal, position)
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "Beacon")
	terminal:SetAttribute("InteractPrompt", "Activate Beacon")
	model.PrimaryPart = base
	model.Parent = workspace.ActiveActors
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

-- Elimination family. Three variants that all end in a body rather than a hold: a commander with
-- guards, a siege walker that must die here, and three named operatives. Only tagged models count,
-- so patrols from the EncounterDirector cannot stall or fake completion.
elimTargets = {}
local elimTotal = 0
local elimKilled = 0
local elimRunning = false
local elimRunId = 0
local elimLabel = "Hostiles"

local function elimAdd(model: Model?)
	if not model then
		return
	end
	model:SetAttribute("GF_ObjectiveTarget", true)
	elimTargets[model] = true
	elimTotal += 1
end

local function elimTick()
	if elimRunning then
		return
	end
	elimRunning = true
	local runId = elimRunId
	task.spawn(function()
		while not complete do
			if runId ~= elimRunId then
				break
			end
			if not objective or not objective.Parent then
				break
			end
			local gone = {}
			for model in pairs(elimTargets) do
				if model.Parent == nil or model:GetAttribute("Dead") == true then
					table.insert(gone, model)
				end
			end
			for _, model in ipairs(gone) do
				elimTargets[model] = nil
				elimKilled += 1
				pcall(function()
					require(script.Parent.CacheService).onBossKilled(model)
				end)
			end
			if elimTotal > 0 then
				progress = math.clamp(elimKilled / elimTotal, 0, 1)
				hint = string.format("%s %d / %d down", elimLabel, elimKilled, elimTotal)
				publish()
			end
			if elimTotal > 0 and elimKilled >= elimTotal then
				ObjectiveService.complete()
				break
			end
			task.wait(0.5)
		end
		elimRunning = false
	end)
end

local function elimSite(position, accent)
	local model = Instance.new("Model")
	model.Name = "EliminationSite"
	model:SetAttribute("GFObjective", "EliminationSite")
	local pad = partOf(model, Vector3.new(22, 1.2, 22), Vector3.new(0, 0.6, 0), Color3.fromRGB(38, 40, 46), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local pole = partOf(model, Vector3.new(0.7, 18, 0.7), Vector3.new(0, 9.6, 0), Color3.fromRGB(52, 56, 64), Enum.Material.Metal, position)
	pole.Name = "PennantPole"
	local flag = partOf(model, Vector3.new(4.6, 2.4, 0.2), Vector3.new(2.6, 17.4, 0), accent, Enum.Material.Neon, position)
	flag.Name = "Pennant"
	local crateA = partOf(model, Vector3.new(3, 2.2, 2.4), Vector3.new(-6, 1.9, 4), Color3.fromRGB(60, 58, 52), Enum.Material.WoodPlanks, position)
	crateA.Name = "CrateA"
	local crateB = partOf(model, Vector3.new(2.4, 1.8, 2), Vector3.new(-6.4, 1.7, 7.2), Color3.fromRGB(60, 58, 52), Enum.Material.WoodPlanks, position)
	crateB.Name = "CrateB"
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

local function buildElimination(position)
	local site = elimSite(position, Color3.fromRGB(226, 108, 72))
	if templateId == "ELIM_COMMANDER" then
		elimLabel = "Guards"
		elimAdd(EnemyService.spawn("Officer", position + Vector3.new(0, 0, -6)))
		elimAdd(EnemyService.spawn("Rifleman", position + Vector3.new(7, 0, 4)))
		elimAdd(EnemyService.spawn("Rifleman", position + Vector3.new(-7, 0, 4)))
		hint = "Eliminate the commander and his guards"
	elseif templateId == "ELIM_WALKER" then
		elimLabel = "Walker"
		elimAdd(BastionWalker.spawn(position + Vector3.new(0, 0, -8)))
		hint = "Destroy the Bastion Walker"
	else
		elimLabel = "Talon"
		elimAdd(EnemyService.spawn("Marksman", position + Vector3.new(9, 0, -6)))
		elimAdd(EnemyService.spawn("Heavy", position + Vector3.new(-9, 0, -6)))
		elimAdd(EnemyService.spawn("Officer", position + Vector3.new(0, 0, 10)))
		hint = "Eliminate the three Talon operatives"
	end
	workspace:SetAttribute("GF_ElimTargets", elimTotal)
	if elimTotal == 0 then
		warn("[GF] elimination roster empty for " .. tostring(templateId))
		hint = "Objective error: no hostile targets spawned"
		publish()
	end
	return site
end

-- Conquest family. One stage machine, three variants: clear or disable, capture, then hold.
-- Transitions are server-owned; interactive stages are driven by ObjectiveService.request, so a
-- player cannot advance by firing the remote twice.
local CONQUEST = {
	CONQUEST_DOMINION = { defend = 45, stage1 = "clear", roster = { "Rifleman", "Rifleman", "Marksman", "Rifleman" } },
	CONQUEST_FOUNDRY = { defend = 60, stage1 = "interact" },
	CONQUEST_THRONEFALL = { defend = 0, stage1 = "clear", roster = { "Heavy", "Marksman", "Officer" }, boss = true },
}

local conqStage = 0
local conqEndsAt = 0
local conqTagged: { [Model]: boolean } = {}
local conqTotal = 0
local conqRunId = 0

local function conqConfig()
	return CONQUEST[templateId]
end

local function conqKilled()
	local n = 0
	for model in pairs(conqTagged) do
		if model.Parent == nil or model:GetAttribute("Dead") == true then
			n += 1
		end
	end
	return n
end

local function conqTag(model: Model?)
	if not model then
		return
	end
	model:SetAttribute("GF_ObjectiveTarget", true)
	model:SetAttribute("GF_ConquestTarget", true)
	conqTagged[model] = true
	conqTotal += 1
end

local function conqCentre(): Vector3
	local part = objective and objective.PrimaryPart
	return part and part.Position or Vector3.zero
end

local function conqTerminal(label: string, interact: string)
	local terminal = objective and objective:FindFirstChild("Terminal")
	if not terminal then
		return
	end
	terminal:SetAttribute("GFInteract", interact)
	terminal:SetAttribute("InteractPrompt", label)
end

local function conqEnterStage(stage: number)
	if stage > 3 then
		-- Thronefall's command node is the last stage: capturing it completes the operation.
		ObjectiveService.complete()
		return
	end
	conqStage = stage
	local cfg = conqConfig()
	if not cfg then
		return
	end
	progress = 0
	if stage >= 1 and stage <= 2 then
		conqTagged = {}
		conqTotal = 0
	end
	if stage == 1 then
		if cfg.stage1 == "interact" then
			conqTerminal("Cut turret power", "ConquestConsole")
			hint = "Cut the turret power coupling"
		else
			conqTerminal("", "None")
			local centre = conqCentre()
			for _, enemyId in ipairs(cfg.roster or {}) do
				conqTag(EnemyService.spawn(enemyId, centre + Vector3.new(math.random(-14, 14), 0, math.random(-14, 14))))
			end
			hint = string.format("Clear the base defenders (%d)", conqTotal)
		end
	elseif stage == 2 then
		if cfg.boss then
			conqTerminal("", "None")
			local player = game:GetService("Players"):GetPlayers()[1]
			conqTag(Veyr.spawn(conqCentre() + Vector3.new(0, 0, -16), player))
			hint = "Defeat High Marshal Veyr"
		else
			conqTerminal("Capture control point", "ConquestConsole")
			hint = "Capture the control point"
		end
	elseif stage == 3 then
		if cfg.boss then
			conqTerminal("Capture command node", "ConquestNode")
			hint = "Capture the command node"
		else
			conqTerminal("", "None")
			conqEndsAt = os.clock() + (cfg.defend or 45)
			hint = string.format("Hold the position: %d s", cfg.defend or 45)
		end
	end
	workspace:SetAttribute("GF_ConquestStage", stage)
	publish()
end

local function conqInteractive(): boolean
	local cfg = conqConfig()
	if not cfg then
		return false
	end
	if conqStage == 1 and cfg.stage1 == "interact" then
		return true
	end
	if conqStage == 2 and not cfg.boss then
		return true
	end
	if conqStage == 3 and cfg.boss then
		return true
	end
	return false
end

local function conqTick()
	local runId = conqRunId
	task.spawn(function()
		while not complete and runId == conqRunId do
			if not objective or not objective.Parent then
				break
			end
			local cfg = conqConfig()
			if cfg then
				if conqStage == 1 and conqTotal > 0 and conqKilled() >= conqTotal then
					conqEnterStage(2)
				elseif conqStage == 2 and cfg.boss and conqTotal > 0 and conqKilled() >= conqTotal then
					conqEnterStage(3)
				elseif conqStage == 3 and not cfg.boss then
					local duration = cfg.defend or 45
					local left = conqEndsAt - os.clock()
					progress = math.clamp(1 - left / duration, 0, 1)
					hint = string.format("Holding position: %d s", math.max(0, math.ceil(left)))
					publish()
					if left <= 0 then
						ObjectiveService.complete()
						break
					end
				end
			end
			task.wait(0.5)
		end
	end)
end

local function buildConquest(position)
	local model = Instance.new("Model")
	model.Name = "ConquestSite"
	model:SetAttribute("GFObjective", "ConquestSite")
	local pad = partOf(model, Vector3.new(24, 1.2, 24), Vector3.new(0, 0.6, 0), Color3.fromRGB(40, 44, 40), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local pole = partOf(model, Vector3.new(0.7, 20, 0.7), Vector3.new(0, 10.6, 0), Color3.fromRGB(52, 56, 64), Enum.Material.Metal, position)
	pole.Name = "StandardPole"
	local flag = partOf(model, Vector3.new(5, 2.6, 0.2), Vector3.new(2.8, 19.2, 0), Color3.fromRGB(88, 176, 255), Enum.Material.Neon, position)
	flag.Name = "Standard"
	local terminal = partOf(model, Vector3.new(2.6, 3, 1.6), Vector3.new(0, 2.1, 6), Color3.fromRGB(30, 36, 44), Enum.Material.Metal, position)
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "ConquestConsole")
	terminal:SetAttribute("InteractPrompt", "Use console")
	local core = partOf(model, Vector3.new(3.4, 4.4, 3.4), Vector3.new(-6, 2.8, -4), Color3.fromRGB(56, 60, 68), Enum.Material.Metal, position)
	core.Name = "FacilityCore"
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

-- Sabotage | Shattered Aegis. Two linked generators power a shield emitter; the emitter is only
-- exposed once both generators are down. Structures carry GFIntegrityMax, so the weapon damage that
-- kills enemies also breaks them (CombatService.damageStructure), and their state is polled here.
local aegisStage = 0
local aegisRunId = 0

local function aegisPart(model, name, size, offset, color, material, position, integrity)
	local p = partOf(model, size, offset, color, material, position)
	p.Name = name
	p:SetAttribute("GFIntegrityMax", integrity)
	p:SetAttribute("GFIntegrity", integrity)
	p:SetAttribute("GFStructure", name)
	return p
end

local function aegisDown(model, name): boolean
	local part = model and model:FindFirstChild(name)
	return part ~= nil and part:GetAttribute("GFDestroyed") == true
end

local function aegisExpose(model)
	local emitter = model and model:FindFirstChild("ShieldEmitter")
	if not emitter then
		return
	end
	emitter:SetAttribute("GFExposed", true)
	emitter:SetAttribute("GFShielded", false)
	if emitter:IsA("BasePart") then
		emitter.CanQuery = true
		emitter.Transparency = 0.1
	end
	local lamp = model:FindFirstChild("EmitterLamp")
	if lamp and lamp:IsA("BasePart") then
		lamp.Transparency = 0
	end
end

local function aegisTick(model)
	local runId = aegisRunId
	task.spawn(function()
		while not complete and runId == aegisRunId do
			if not model or not model.Parent then
				break
			end
			if aegisStage == 1 then
				local down = 0
				if aegisDown(model, "GeneratorA") then
					down += 1
				end
				if aegisDown(model, "GeneratorB") then
					down += 1
				end
				progress = down / 2
				hint = string.format("Destroy the shield generators (%d / 2)", down)
				publish()
				if down >= 2 then
					aegisStage = 2
					workspace:SetAttribute("GF_AegisStage", 2)
					aegisExpose(model)
					progress = 0
					hint = "Destroy the exposed shield emitter"
					publish()
				end
			elseif aegisStage == 2 then
				local emitter = model:FindFirstChild("ShieldEmitter")
				local max = emitter and tonumber(emitter:GetAttribute("GFIntegrityMax")) or 700
				local current = emitter and tonumber(emitter:GetAttribute("GFIntegrity")) or max
				progress = math.clamp(1 - current / math.max(1, max), 0, 1)
				hint = string.format("Shield emitter integrity %d / %d", math.floor(current), math.floor(max))
				publish()
				if aegisDown(model, "ShieldEmitter") then
					ObjectiveService.complete()
					break
				end
			end
			task.wait(0.4)
		end
	end)
end

local function buildAegis(position)
	local model = Instance.new("Model")
	model.Name = "ShieldCompound"
	model:SetAttribute("GFObjective", "ShieldCompound")
	local pad = partOf(model, Vector3.new(30, 1.2, 30), Vector3.new(0, 0.6, 0), Color3.fromRGB(36, 38, 44), Enum.Material.Slate, position)
	pad.Name = "Pad"
	aegisPart(model, "GeneratorA", Vector3.new(5, 7, 5), Vector3.new(-9, 4.1, 0), Color3.fromRGB(64, 70, 84), Enum.Material.Metal, position, 300)
	aegisPart(model, "GeneratorB", Vector3.new(5, 7, 5), Vector3.new(9, 4.1, 0), Color3.fromRGB(64, 70, 84), Enum.Material.Metal, position, 300)
	local cableA = partOf(model, Vector3.new(1.2, 1.2, 9), Vector3.new(-4.6, 1.6, 0), Color3.fromRGB(28, 32, 40), Enum.Material.Metal, position)
	cableA.Name = "CableA"
	local cableB = partOf(model, Vector3.new(1.2, 1.2, 9), Vector3.new(4.6, 1.6, 0), Color3.fromRGB(28, 32, 40), Enum.Material.Metal, position)
	cableB.Name = "CableB"
	local emitter = aegisPart(model, "ShieldEmitter", Vector3.new(6, 10, 6), Vector3.new(0, 5.6, -10), Color3.fromRGB(120, 190, 235), Enum.Material.ForceField, position, 700)
	emitter.CanQuery = false
	emitter.Transparency = 0.45
	emitter:SetAttribute("GFShielded", true)
	local lamp = partOf(model, Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 11.2, -10), Color3.fromRGB(120, 210, 255), Enum.Material.Neon, position)
	lamp.Name = "EmitterLamp"
	lamp.Transparency = 0.6
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

-- Recovery | Fallen Convoy and Defense | Last Transmission. Both reuse the machinery that already
-- works: tagged finite rosters for the pursuit squad, and the same 0.5 s timer the beacon defend
-- uses. Neither adds a second interaction system.
local convoyStage = 0
local convoyRecovered = 0
local convoyRunId = 0
local convoyTagged: { [Model]: boolean } = {}
local convoyTotal = 0

local uplinkStage = 0
local uplinkEndsAt = 0
local uplinkRunId = 0

local function pursuitTick()
	local runId = convoyRunId
	task.spawn(function()
		while not complete and runId == convoyRunId do
			if not objective or not objective.Parent then
				break
			end
			if convoyStage == 2 then
				local dead = 0
				for model in pairs(convoyTagged) do
					if model.Parent == nil or model:GetAttribute("Dead") == true then
						dead += 1
					end
				end
				progress = convoyTotal > 0 and dead / convoyTotal or 0
				hint = string.format("Defeat the pursuit squad (%d / %d)", dead, convoyTotal)
				publish()
				if convoyTotal > 0 and dead >= convoyTotal then
					ObjectiveService.complete()
					break
				end
			end
			task.wait(0.5)
		end
	end)
end

local function spawnPursuit()
	convoyTagged = {}
	convoyTotal = 0
	local centre = objective and objective.PrimaryPart and objective.PrimaryPart.Position or Vector3.zero
	for _, enemyId in ipairs({ "Rifleman", "Scout", "Heavy" }) do
		local model = EnemyService.spawn(enemyId, centre + Vector3.new(math.random(-12, 12), 0, math.random(-12, 12)))
		if model then
			model:SetAttribute("GF_ObjectiveTarget", true)
			convoyTagged[model] = true
			convoyTotal += 1
		end
	end
end

local function convoyRequest(player: Player)
	if convoyStage ~= 1 then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, crateName in ipairs({ "CrateA", "CrateB" }) do
		local crate = objective and objective:FindFirstChild(crateName)
		if crate and crate:GetAttribute("GFRecovered") ~= true and (root.Position - crate.Position).Magnitude <= INTERACT_RANGE then
			crate:SetAttribute("GFRecovered", true)
			crate.Transparency = 1
			crate.CanCollide = false
			crate.CanQuery = false
			convoyRecovered += 1
			progress = convoyRecovered / 2
			hint = string.format("Recover the convoy crates (%d / 2)", convoyRecovered)
			publish()
			if convoyRecovered >= 2 then
				convoyStage = 2
				workspace:SetAttribute("GF_ConvoyStage", 2)
				spawnPursuit()
				hint = string.format("Defeat the pursuit squad (0 / %d)", convoyTotal)
				publish()
			end
			workspace:SetAttribute("GF_ConvoyCrates", convoyRecovered)
			return
		end
	end
end

local function uplinkTick()
	local runId = uplinkRunId
	task.spawn(function()
		while not complete and runId == uplinkRunId do
			if not objective or not objective.Parent then
				break
			end
			if uplinkStage == 2 then
				local left = uplinkEndsAt - os.clock()
				progress = math.clamp(1 - left / 75, 0, 1)
				hint = string.format("Defending the uplink: %d s", math.max(0, math.ceil(left)))
				publish()
				if left <= 0 then
					uplinkStage = 3
					workspace:SetAttribute("GF_UplinkStage", 3)
					hint = "Confirm the uplink at the console"
					local terminal = objective:FindFirstChild("Terminal")
					if terminal then
						terminal:SetAttribute("GFInteract", "UplinkConfirm")
						terminal:SetAttribute("InteractPrompt", "Confirm uplink")
					end
					publish()
					break
				end
			end
			task.wait(0.5)
		end
	end)
end

local function uplinkRequest(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local terminal = objective and objective:FindFirstChild("Terminal")
	if not root or not terminal then
		return
	end
	if (root.Position - terminal.Position).Magnitude > INTERACT_RANGE then
		return
	end
	if uplinkStage == 1 then
		uplinkStage = 2
		workspace:SetAttribute("GF_UplinkStage", 2)
		uplinkEndsAt = os.clock() + 75
		hint = "Defending the uplink: 75 s"
		publish()
		uplinkTick()
	elseif uplinkStage == 3 then
		ObjectiveService.complete()
	end
end

local function buildConvoy(position)
	local model = Instance.new("Model")
	model.Name = "ConvoyWreck"
	model:SetAttribute("GFObjective", "ConvoyWreck")
	local pad = partOf(model, Vector3.new(26, 1.2, 26), Vector3.new(0, 0.6, 0), Color3.fromRGB(36, 38, 42), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local hull = partOf(model, Vector3.new(12, 5, 20), Vector3.new(-6, 3, -6), Color3.fromRGB(70, 62, 54), Enum.Material.Metal, position)
	hull.Name = "Hull"
	hull.CFrame = CFrame.new(position + Vector3.new(-6, 3, -6)) * CFrame.Angles(math.rad(-8), math.rad(14), math.rad(6))
	local wing = partOf(model, Vector3.new(9, 1, 6), Vector3.new(4, 1.4, -10), Color3.fromRGB(58, 54, 50), Enum.Material.Metal, position)
	wing.Name = "Wing"
	local crateA = partOf(model, Vector3.new(3, 2.4, 2.6), Vector3.new(6, 1.8, 6), Color3.fromRGB(214, 170, 96), Enum.Material.WoodPlanks, position)
	crateA.Name = "CrateA"
	crateA:SetAttribute("GFInteract", "ConvoyCrate")
	crateA:SetAttribute("InteractPrompt", "Recover crate")
	local crateB = partOf(model, Vector3.new(3, 2.4, 2.6), Vector3.new(10, 1.8, 1), Color3.fromRGB(214, 170, 96), Enum.Material.WoodPlanks, position)
	crateB.Name = "CrateB"
	crateB:SetAttribute("GFInteract", "ConvoyCrate")
	crateB:SetAttribute("InteractPrompt", "Recover crate")
	local smoke = partOf(model, Vector3.new(2, 2, 2), Vector3.new(-2, 7, -8), Color3.fromRGB(40, 40, 44), Enum.Material.Slate, position)
	smoke.Name = "Smoke"
	smoke.Transparency = 0.4
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

local function buildUplink(position)
	local model = Instance.new("Model")
	model.Name = "UplinkStation"
	model:SetAttribute("GFObjective", "UplinkStation")
	local pad = partOf(model, Vector3.new(24, 1.2, 24), Vector3.new(0, 0.6, 0), Color3.fromRGB(34, 38, 44), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local mast = partOf(model, Vector3.new(1.6, 16, 1.6), Vector3.new(0, 8.8, 0), Color3.fromRGB(60, 66, 76), Enum.Material.Metal, position)
	mast.Name = "Mast"
	local dish = partOf(model, Vector3.new(8, 0.6, 8), Vector3.new(0, 17.4, 0), Color3.fromRGB(78, 86, 98), Enum.Material.Metal, position)
	dish.Name = "Dish"
	dish.CFrame = CFrame.new(position + Vector3.new(0, 17.4, 0)) * CFrame.Angles(math.rad(-34), 0, 0)
	local terminal = partOf(model, Vector3.new(2.6, 3, 1.6), Vector3.new(0, 2.1, 7), Color3.fromRGB(30, 36, 44), Enum.Material.Metal, position)
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "UplinkDish")
	terminal:SetAttribute("InteractPrompt", "Activate dish")
	local lamp = partOf(model, Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 18.8, 0), Color3.fromRGB(120, 210, 255), Enum.Material.Neon, position)
	lamp.Name = "UplinkLamp"
	lamp.Transparency = 0.5
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

-- Defense | Power Under Fire. The first Defence object that can actually be lost: it carries HP,
-- hostiles shoot it when no player is visible, the timer pauses when nobody is within 55 studs,
-- and its destruction fails the primary instead of completing it.
local powerStage = 0
local powerRemaining = 90
local powerAbsent = 0
local powerRunId = 0
local failed = false

local POWER_DURATION = 90
local POWER_HOLD_RADIUS = 55
local POWER_ABSENCE_LIMIT = 10

local function powerGenerator(): BasePart?
	local part = objective and objective:FindFirstChild("Generator")
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function powerIntegrity(): (number, number)
	local generator = powerGenerator()
	if not generator then
		return 0, 0
	end
	return tonumber(generator:GetAttribute("GFIntegrity")) or 0, tonumber(generator:GetAttribute("GFIntegrityMax")) or 0
end

local function powerFail()
	if failed or complete then
		return
	end
	failed = true
	progress = 0
	hint = "Generator destroyed — primary objective failed"
	workspace:SetAttribute("GF_ObjectiveFailed", true)
	pcall(function()
		require(script.Parent.DialogueService).say("You lost the objective. Emergency bird is inbound — move.", "fail")
	end)
	local mission = State.getMission()
	if mission then
		mission.objectiveComplete = false
		mission.failed = true
	end
	publish()
	local r = remote("ObjectiveComplete")
	if r then
		r:FireAllClients({ success = false, template = templateId, reason = "generator destroyed" })
	end
	-- A failed primary must offer the way out: previously it only changed a flag, so the squad was left
	-- in a mission that could never complete.
	pcall(function()
		require(script.Parent.ExtractionService).emergency()
	end)
end

local function powerTick()
	local runId = powerRunId
	task.spawn(function()
		while not complete and not failed and runId == powerRunId do
			local generator = powerGenerator()
			if not generator or not generator.Parent then
				break
			end
			if generator:GetAttribute("GFDestroyed") == true then
				powerFail()
				break
			end
			if powerStage == 2 then
				local occupied = false
				for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root and (root.Position - generator.Position).Magnitude <= POWER_HOLD_RADIUS then
						occupied = true
						break
					end
				end
				if occupied then
					powerAbsent = 0
					powerRemaining = math.max(0, powerRemaining - 0.5)
				else
					powerAbsent += 0.5
				end
				local current, max = powerIntegrity()
				workspace:SetAttribute("GF_DefenseRemaining", math.floor(powerRemaining))
				workspace:SetAttribute("GF_DefensePaused", powerAbsent > POWER_ABSENCE_LIMIT)
				workspace:SetAttribute("GF_DefenseEngaged", occupied)
				if powerAbsent > POWER_ABSENCE_LIMIT then
					hint = string.format("Defense paused — return to the generator (%d / %d)", math.floor(current), math.floor(max))
				else
					hint = string.format("Defending generator: %d s (%d / %d)", math.ceil(powerRemaining), math.floor(current), math.floor(max))
				end
				progress = math.clamp(1 - powerRemaining / POWER_DURATION, 0, 1)
				publish()
				if powerRemaining <= 0 then
					powerStage = 3
					workspace:SetAttribute("GF_PowerStage", 3)
					local terminal = objective:FindFirstChild("Terminal")
					if terminal then
						terminal:SetAttribute("GFInteract", "PowerStabilise")
						terminal:SetAttribute("InteractPrompt", "Stabilise output")
					end
					hint = "Stabilise the generator output"
					publish()
					break
				end
			end
			task.wait(0.5)
		end
	end)
end

local function powerRequest(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local terminal = objective and objective:FindFirstChild("Terminal")
	if not root or not terminal then
		return
	end
	if (root.Position - terminal.Position).Magnitude > INTERACT_RANGE then
		return
	end
	if powerStage == 1 then
		powerStage = 2
		workspace:SetAttribute("GF_PowerStage", 2)
		powerRemaining = POWER_DURATION
		powerAbsent = 0
		hint = string.format("Defending generator: %d s", POWER_DURATION)
		publish()
		powerTick()
	elseif powerStage == 3 then
		ObjectiveService.complete()
	end
end

local function buildPower(position)
	local model = Instance.new("Model")
	model.Name = "PowerStation"
	model:SetAttribute("GFObjective", "PowerStation")
	local pad = partOf(model, Vector3.new(26, 1.2, 26), Vector3.new(0, 0.6, 0), Color3.fromRGB(34, 36, 42), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local difficulty = workspace:GetAttribute("GF_OperationDifficulty") or (State.getMission() or {}).difficulty or "Normal"
	local integrity = 600
	if difficulty == "Easy" then
		integrity = 800
	elseif difficulty == "Hard" or difficulty == "Extreme" then
		integrity = 650
	end
	local generator = partOf(model, Vector3.new(7, 9, 7), Vector3.new(0, 5.6, -8), Color3.fromRGB(72, 78, 90), Enum.Material.Metal, position)
	generator.Name = "Generator"
	generator:SetAttribute("GFIntegrityMax", integrity)
	generator:SetAttribute("GFIntegrity", integrity)
	generator:SetAttribute("GFStructure", "Generator")
	local core = partOf(model, Vector3.new(3, 3, 3), Vector3.new(0, 6, -8), Color3.fromRGB(255, 196, 96), Enum.Material.Neon, position)
	core.Name = "Core"
	local terminal = partOf(model, Vector3.new(2.6, 3, 1.6), Vector3.new(0, 2.1, 6), Color3.fromRGB(30, 36, 44), Enum.Material.Metal, position)
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "PowerRestore")
	terminal:SetAttribute("InteractPrompt", "Restore generator")
	local cable = partOf(model, Vector3.new(1.2, 1, 10), Vector3.new(0, 1.2, -1), Color3.fromRGB(28, 32, 40), Enum.Material.Metal, position)
	cable.Name = "Cable"
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

-- Sabotage | Burn the Arsenal. Two charge pads arm the depot; the stockpile is destroyed by the
-- authored detonation, not by weapon fire, and the player may leave during the 8 s warning.
local arsenalStage = 0
local arsenalPads = 0
local arsenalEndsAt = 0
local arsenalRunId = 0

local ARSENAL_WARNING = 8

local function arsenalRequest(player: Player)
	if arsenalStage ~= 1 then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, padName in ipairs({ "ChargePadA", "ChargePadB" }) do
		local pad = objective and objective:FindFirstChild(padName)
		if pad and pad:GetAttribute("GFCharged") ~= true and (root.Position - pad.Position).Magnitude <= INTERACT_RANGE then
			pad:SetAttribute("GFCharged", true)
			pad.Color = Color3.fromRGB(255, 150, 70)
			arsenalPads += 1
			progress = arsenalPads / 2
			hint = string.format("Charge the depot pads (%d / 2)", arsenalPads)
			publish()
			if arsenalPads >= 2 then
				arsenalStage = 2
				arsenalEndsAt = os.clock() + ARSENAL_WARNING
				workspace:SetAttribute("GF_ArsenalStage", 2)
			end
			workspace:SetAttribute("GF_ArsenalPads", arsenalPads)
			return
		end
	end
end

local function arsenalTick()
	local runId = arsenalRunId
	task.spawn(function()
		while not complete and runId == arsenalRunId do
			if not objective or not objective.Parent then
				break
			end
			if arsenalStage == 2 then
				local left = arsenalEndsAt - os.clock()
				progress = math.clamp(1 - left / ARSENAL_WARNING, 0, 1)
				hint = string.format("Detonation in %d s — clear the depot", math.max(0, math.ceil(left)))
				publish()
				if left <= 0 then
					arsenalStage = 3
					workspace:SetAttribute("GF_ArsenalStage", 3)
					local stockpile = objective:FindFirstChild("Stockpile")
					if stockpile and stockpile:IsA("BasePart") then
						local blast = Instance.new("Part")
						blast.Shape = Enum.PartType.Ball
						blast.Size = Vector3.new(10, 10, 10)
						blast.Position = stockpile.Position
						blast.Anchored = true
						blast.CanCollide = false
						blast.CanQuery = false
						blast.Material = Enum.Material.Neon
						blast.Color = Color3.fromRGB(255, 168, 72)
						blast.Transparency = 0.25
						blast.Parent = workspace
						TweenService:Create(blast, TweenInfo.new(1.1), { Size = Vector3.new(52, 52, 52), Transparency = 1 }):Play()
						task.delay(1.4, function()
							if blast.Parent then
								blast:Destroy()
							end
						end)
						stockpile.Transparency = 1
						stockpile.CanCollide = false
						stockpile.CanQuery = false
						stockpile:SetAttribute("GFDestroyed", true)
						workspace:SetAttribute("GF_ArsenalDetonated", true)
					end
					hint = "Stockpile destroyed"
					publish()
					ObjectiveService.complete()
					break
				end
			end
			task.wait(0.4)
		end
	end)
end

local function buildArsenal(position)
	local model = Instance.new("Model")
	model.Name = "AmmoDepot"
	model:SetAttribute("GFObjective", "AmmoDepot")
	local pad = partOf(model, Vector3.new(30, 1.2, 30), Vector3.new(0, 0.6, 0), Color3.fromRGB(38, 36, 34), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local stockpile = partOf(model, Vector3.new(12, 6, 9), Vector3.new(0, 4.1, -8), Color3.fromRGB(92, 78, 48), Enum.Material.WoodPlanks, position)
	stockpile.Name = "Stockpile"
	local stack = partOf(model, Vector3.new(8, 2.4, 8), Vector3.new(0, 8.2, -8), Color3.fromRGB(84, 72, 46), Enum.Material.WoodPlanks, position)
	stack.Name = "StockpileTop"
	local chargeA = partOf(model, Vector3.new(3, 0.6, 3), Vector3.new(-9, 1.5, 6), Color3.fromRGB(70, 90, 110), Enum.Material.Metal, position)
	chargeA.Name = "ChargePadA"
	chargeA:SetAttribute("GFInteract", "ArsenalPad")
	chargeA:SetAttribute("InteractPrompt", "Charge pad")
	local chargeB = partOf(model, Vector3.new(3, 0.6, 3), Vector3.new(9, 1.5, 6), Color3.fromRGB(70, 90, 110), Enum.Material.Metal, position)
	chargeB.Name = "ChargePadB"
	chargeB:SetAttribute("GFInteract", "ArsenalPad")
	chargeB:SetAttribute("InteractPrompt", "Charge pad")
	local warning = partOf(model, Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 9.6, -2), Color3.fromRGB(120, 120, 130), Enum.Material.Neon, position)
	warning.Name = "WarningLamp"
	warning.Transparency = 0.4
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

-- Recovery | Silent Archive. Three authored stages: reach the intel room, break the console with the
-- server-authoritative hacking challenge, then recover the archive by interaction.
local archiveStage = 0
local archiveRunId = 0

local HackingService = require(script.Parent.HackingService)

local function archiveRequest(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local terminal = objective and objective:FindFirstChild("Terminal")
	if not root or not terminal then
		return
	end
	if (root.Position - terminal.Position).Magnitude > INTERACT_RANGE then
		return
	end
	if archiveStage == 2 then
		local difficulty = (State.getMission() or {}).difficulty or "Normal"
		HackingService.begin(player, difficulty, terminal.Position)
		hint = "Breaking the console — press " .. "E" .. " in the green arc"
		publish()
	elseif archiveStage == 3 then
		local intel = objective and objective:FindFirstChild("IntelCase")
		if intel and intel:IsA("BasePart") then
			intel.Transparency = 0
			intel.CanCollide = false
		end
		ObjectiveService.complete()
	end
end

local function archiveTick()
	local runId = archiveRunId
	task.spawn(function()
		while not complete and runId == archiveRunId do
			if not objective or not objective.Parent then
				break
			end
			if archiveStage == 1 then
				local terminal = objective:FindFirstChild("Terminal")
				for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if terminal and root and (root.Position - terminal.Position).Magnitude <= 25 then
						archiveStage = 2
						workspace:SetAttribute("GF_ArchiveStage", 2)
						terminal:SetAttribute("GFInteract", "ArchiveConsole")
						terminal:SetAttribute("InteractPrompt", "Break console")
						hint = "Break the data console"
						publish()
						break
					end
				end
			end
			task.wait(0.5)
		end
	end)
end

local function buildArchive(position)
	local model = Instance.new("Model")
	model.Name = "IntelRoom"
	model:SetAttribute("GFObjective", "IntelRoom")
	local pad = partOf(model, Vector3.new(24, 1.2, 24), Vector3.new(0, 0.6, 0), Color3.fromRGB(32, 34, 40), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local wallA = partOf(model, Vector3.new(24, 10, 1), Vector3.new(0, 5.6, -11), Color3.fromRGB(52, 56, 64), Enum.Material.Metal, position)
	wallA.Name = "WallBack"
	local wallB = partOf(model, Vector3.new(1, 10, 22), Vector3.new(-11, 5.6, 0), Color3.fromRGB(52, 56, 64), Enum.Material.Metal, position)
	wallB.Name = "WallLeft"
	local terminal = partOf(model, Vector3.new(3, 2.6, 2), Vector3.new(0, 2.4, -8), Color3.fromRGB(34, 40, 50), Enum.Material.Metal, position)
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "ArchiveConsole")
	terminal:SetAttribute("InteractPrompt", "Inspect console")
	local screen = partOf(model, Vector3.new(2.6, 1.6, 0.2), Vector3.new(0, 3.4, -6.9), Color3.fromRGB(60, 190, 220), Enum.Material.Neon, position)
	screen.Name = "Screen"
	local intel = partOf(model, Vector3.new(2, 1.4, 2), Vector3.new(6, 1.6, 2), Color3.fromRGB(230, 200, 120), Enum.Material.Metal, position)
	intel.Name = "IntelCase"
	intel.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(96, 190, 240); light.Brightness = 0.25; light.Range = 22; light.Shadows = false
	light.Parent = screen
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

function ObjectiveService.setup(position, template)
	if objective then objective:Destroy() end
	progress = 0
	complete = false
	-- A fresh mission gets its own rewards ledger, so seq restarts and claim-once is scoped per mission.
	pcall(function()
		require(script.Parent.RewardLedgerService).begin(template)
	end)
	-- A fresh mission has not committed its war points yet.
	workspace:SetAttribute("GF_WarCommitted", false)
	holding = {}
	-- setup runs before EncounterDirector.reset, which sweeps boss models, so the previous mission's
	-- tagged targets are removed here and the fresh one is spared by its tag.
	for stale in pairs(elimTargets) do
		if stale.Parent then
			stale:Destroy()
		end
	end
	elimTargets = {}
	elimTotal = 0
	elimKilled = 0
	elimRunning = false
	elimRunId += 1
	conqStage = 0
	conqTagged = {}
	conqTotal = 0
	conqEndsAt = 0
	conqRunId += 1
	aegisStage = 0
	aegisRunId += 1
	convoyStage = 0
	convoyRecovered = 0
	convoyTagged = {}
	convoyTotal = 0
	convoyRunId += 1
	uplinkStage = 0
	uplinkEndsAt = 0
	uplinkRunId += 1
	powerStage = 0
	powerRemaining = POWER_DURATION
	powerAbsent = 0
	powerRunId += 1
	arsenalStage = 0
	arsenalPads = 0
	arsenalEndsAt = 0
	arsenalRunId += 1
	archiveStage = 0
	archiveRunId += 1
	failed = false
	workspace:SetAttribute("GF_ObjectiveFailed", false)
	workspace:SetAttribute("GF_DefenseStructure", nil)
	defending = false
	defendEndsAt = 0
	-- callers that only pass a position still get the template the player actually chose
	templateId = template or (function()
		local m = State.getMission()
		return type(m) == "table" and m.objectiveTemplate or nil
	end)() or "SABOTAGE_RELAY"
	local pos = ground(position)
	if templateId == "RECOVER_TECH" then
		objective = buildBlackBox(pos)
		hint = "Hold E at the black box to extract the flight recorder"
	elseif templateId == "DEFEND_BEACON" then
		objective = buildBeacon(pos)
		hint = "Activate the beacon, then hold the position"
	elseif templateId == "RECOVERY_ARCHIVE" then
		objective = buildArchive(pos)
	elseif templateId == "SABOTAGE_ARSENAL" then
		objective = buildArsenal(pos)
	elseif templateId == "DEFENSE_POWER" then
		objective = buildPower(pos)
	elseif templateId == "RECOVERY_CONVOY" then
		objective = buildConvoy(pos)
	elseif templateId == "DEFENSE_UPLINK" then
		objective = buildUplink(pos)
	elseif templateId == "SABOTAGE_AEGIS" then
		objective = buildAegis(pos)
	elseif string.sub(templateId, 1, 8) == "CONQUEST" then
		objective = buildConquest(pos)
	elseif string.sub(templateId, 1, 5) == "ELIM_" then
		objective = buildElimination(pos)
	else
		objective = buildRelay(pos)
		hint = "Hold E at the console to sabotage the relay"
	end
	if string.sub(templateId, 1, 5) == "ELIM_" and elimTotal > 0 and not complete then
		elimTick()
	end
	if string.sub(templateId, 1, 8) == "CONQUEST" and not complete then
		conqEnterStage(1)
		conqTick()
	end
	if templateId == "RECOVERY_ARCHIVE" and not complete then
		archiveStage = 1
		workspace:SetAttribute("GF_ArchiveStage", 1)
		hint = "Reach the intel room"
		archiveTick()
		publish()
	end
	if templateId == "SABOTAGE_ARSENAL" and not complete then
		arsenalStage = 1
		workspace:SetAttribute("GF_ArsenalStage", 1)
		hint = "Charge the depot pads (0 / 2)"
		arsenalTick()
		publish()
	end
	if templateId == "DEFENSE_POWER" and not complete then
		powerStage = 1
		workspace:SetAttribute("GF_PowerStage", 1)
		-- Measured: an Instance stored in an attribute comes back as an InstanceHandle, and IsA on it errors
		-- inside the enemy tick. Publish names instead and let the consumer resolve them.
		workspace:SetAttribute("GF_DefenseModel", objective.Name)
		workspace:SetAttribute("GF_DefensePart", "Generator")
		hint = "Restore the generator"
		publish()
	end
	if templateId == "RECOVERY_CONVOY" and not complete then
		convoyStage = 1
		workspace:SetAttribute("GF_ConvoyStage", 1)
		hint = "Recover the convoy crates (0 / 2)"
		pursuitTick()
		publish()
	end
	if templateId == "DEFENSE_UPLINK" and not complete then
		uplinkStage = 1
		workspace:SetAttribute("GF_UplinkStage", 1)
		hint = "Activate the communications dish"
		publish()
	end
	if templateId == "SABOTAGE_AEGIS" and not complete then
		aegisStage = 1
		workspace:SetAttribute("GF_AegisStage", 1)
		aegisTick(objective)
	end
	local mission = State.getMission()
	if mission then
		mission.objectiveComplete = false
		mission.objectiveTemplate = templateId
	end
	publish()
	return objective
end

local function defendTick()
	task.spawn(function()
		while defending and not complete do
			local left = defendEndsAt - os.clock()
			progress = math.clamp(1 - left / DEFEND_TIME, 0, 1)
			hint = string.format("Holding beacon: %d s", math.max(0, math.ceil(left)))
			publish()
			if left <= 0 then
				ObjectiveService.complete()
				break
			end
			task.wait(0.5)
		end
	end)
end

function ObjectiveService.request(player)
	if complete or not objective then return end
	if templateId == "RECOVERY_CONVOY" then
		return convoyRequest(player)
	end
	if templateId == "DEFENSE_UPLINK" then
		return uplinkRequest(player)
	end
	if templateId == "DEFENSE_POWER" then
		return powerRequest(player)
	end
	if templateId == "SABOTAGE_ARSENAL" then
		return arsenalRequest(player)
	end
	if templateId == "RECOVERY_ARCHIVE" then
		return archiveRequest(player)
	end
	local terminal = objective:FindFirstChild("Terminal")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not terminal then return end
	if (root.Position - terminal.Position).Magnitude > INTERACT_RANGE then return end
	if holding[player] then return end
	if templateId == "DEFEND_BEACON" and defending then return end
	-- RECOVER_TECH is a carry, not a hold: picking the case up is instant, and the objective only completes
	-- when the carrier reaches the landing zone. Three templates that were only ever different hold times now
	-- have three different interactions (hold / carry / survive).
	if templateId == "RECOVER_TECH" and carrying[player] then
		return
	end
	if string.sub(templateId, 1, 8) == "CONQUEST" and not conqInteractive() then
		return
	end
	holding[player] = true
	local st = State.get(player)
	if st then
		st.atConsole = true
	end
	ObjectiveService.showScreen(true)
	local holdFor = SABOTAGE_HOLD
	-- RECOVER_TECH is a pickup now, not a 7s hold: the work happens carrying the case back to the landing
	-- zone, so the grab itself is quick.
	if templateId == "RECOVER_TECH" then holdFor = 0.6 end
	if templateId == "DEFEND_BEACON" then holdFor = DEFEND_ACTIVATE end
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < holdFor do
			task.wait(0.1)
			if complete or not player.Parent or not player.Character then
			holding[player] = nil st = nil ObjectiveService.clearScreen(player) return end
			local r = player.Character:FindFirstChild("HumanoidRootPart")
			if not r or (r.Position - terminal.Position).Magnitude > INTERACT_RANGE + 4 then
			holding[player] = nil st = nil ObjectiveService.clearScreen(player) return end
			progress = math.clamp((os.clock() - started) / holdFor, 0, 1)
			publish()
		end
		holding[player] = nil
		ObjectiveService.clearScreen(player)
		if templateId == "RECOVER_TECH" then
			carrying[player] = true
			attachCase(player)
			showDeliveryRing()
			progress = 0.5
			hint = "Carry the case to the landing zone"
			publish()
			local ev = ReplicatedStorage.GF.Remotes:FindFirstChild("MissionEvent")
			if ev then
				ev:FireAllClients({ text = "Case secured. Get it to the landing zone.", kind = "objective" })
			end
			return
		end
		if string.sub(templateId, 1, 8) == "CONQUEST" then
			conqEnterStage(conqStage + 1)
			return
		end
		if templateId == "DEFEND_BEACON" then
			defending = true
			defendEndsAt = os.clock() + DEFEND_TIME
			defendTick()
		else
			ObjectiveService.complete()
		end
	end)
end

-- Delivery check for RECOVER_TECH, driven from the same 0.5s tick the defend timer uses.
task.spawn(function()
	while true do
		task.wait(0.5)
		if templateId == "RECOVER_TECH" and not complete then
			local lz = workspace:GetAttribute("GF_LZ")
			for player in pairs(carrying) do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and typeof(lz) == "Vector3" and (root.Position - lz).Magnitude < 18 then
					carrying[player] = nil
					dropCase(player)
					if deliveryRing then
						deliveryRing:Destroy()
						deliveryRing = nil
					end
					ObjectiveService.complete()
					break
				end
			end
		end
	end
end)

function ObjectiveService.complete()
	if complete then return end
	complete = true
	progress = 1
	local mission = State.getMission()
	if mission then mission.objectiveComplete = true end
	workspace:SetAttribute("GF_ObjectiveComplete", true)
	-- War points commit here, once, at primary success, independent of the way out (S09-035).
	pcall(function()
		require(script.Parent.GalacticWarService).commitPrimary(templateId)
	end)
	-- Record, do not pay: the ledger is append-only and RewardsService still owns the payout.
	pcall(function()
		local ledgerMission = State.getMission()
		local ledgerDifficulty = (ledgerMission and ledgerMission.difficulty) or "Normal"
		require(script.Parent.RewardLedgerService).appendEvent("primary_complete", ledgerDifficulty, "primary:" .. tostring(templateId))
	end)
	pcall(function()
		require(script.Parent.DialogueService).say("Primary objective complete. Wrap it up and get to the ship.", "objective")
	end)
	-- The guaranteed mission cache is paid at successful extraction, not on completion: a squad that
	-- loses the dropship should not keep it. See ExtractionService.finish.
	print("[GF] objective complete (" .. templateId .. ")")
	publish()
	if objective then
		for _, p in objective:GetChildren() do
			if p:IsA("BasePart") and p.Material == Enum.Material.Neon then
				TweenService:Create(p, TweenInfo.new(0.8), { Transparency = 1 }):Play()
			end
		end
		if templateId == "SABOTAGE_RELAY" then
			local boom = Instance.new("Explosion")
			local pivot = objective.PrimaryPart
			boom.Position = pivot and (pivot.Position + Vector3.new(0, 14, 0)) or Vector3.zero
			boom.BlastRadius = 24; boom.BlastPressure = 0; boom.DestroyJointRadiusPercent = 0
			boom.Parent = workspace
			task.delay(1.2, function() if objective then objective:Destroy() objective = nil end end)
		end
	end
	local r = remote("ObjectiveComplete")
	if r then r:FireAllClients(templateId) end
end

function ObjectiveService.isComplete() return complete end
function ObjectiveService.getProgress() return progress end
-- Hardlight screen: a visible barrier that rises between the console and whoever is watching it, so
-- the mitigation is legible rather than an invisible number.
function ObjectiveService.showScreen(visible: boolean)
	local relay = ObjectiveService.getRelay()
	if not relay then
		return
	end
	visible = visible or workspace:GetAttribute("GF_ForceConsoleScreen") == true
	local screen = relay:FindFirstChild("ConsoleScreen")
	if not screen then
		local host = relay.PrimaryPart or relay:FindFirstChildWhichIsA("BasePart")
		if not host then
			return
		end
		screen = Instance.new("Part")
		screen.Name = "ConsoleScreen"
		screen.Size = Vector3.new(9, 4.4, 0.25)
		screen.Anchored = true
		screen.CanCollide = false
		screen.CanQuery = true
		screen.Material = Enum.Material.ForceField
		screen.Color = Color3.fromRGB(96, 214, 232)
		screen.Transparency = 0.35
		screen.CFrame = host.CFrame * CFrame.new(0, 4.2, -9.5)
		screen.Parent = relay
	end
	screen.Transparency = visible and 0.35 or 1
	workspace:SetAttribute("GF_ConsoleScreen", visible)
end

function ObjectiveService.clearScreen(player: Player?)
	if player then
		local st = State.get(player)
		if st then
			st.atConsole = nil
		end
	end
	ObjectiveService.showScreen(false)
end

function ObjectiveService.getRelay() return objective end
function ObjectiveService.getTemplate() return templateId end

function ObjectiveService.start()
	-- Cancellation is a first-class outcome: leaving the console, going down or disconnecting releases it.
	HackingService.onCancel = function(_player, reason, _challengeId)
		if templateId == "RECOVERY_ARCHIVE" and archiveStage == 2 then
			hint = string.format("Console lock released (%s) — break the console again", tostring(reason))
			publish()
		end
	end
	-- The hacking challenge owns its own success; the archive objective is told, not polled.
	HackingService.onComplete = function(_player, _challengeId)
		if templateId == "RECOVERY_ARCHIVE" and archiveStage == 2 then
			archiveStage = 3
			workspace:SetAttribute("GF_ArchiveStage", 3)
			local terminal = objective and objective:FindFirstChild("Terminal")
			if terminal then
				terminal:SetAttribute("GFInteract", "ArchiveConsole")
				terminal:SetAttribute("InteractPrompt", "Recover archive")
			end
			hint = "Recover the archive"
			publish()
		end
	end

	-- Screen watchdog. The hardlight screen is normally driven by the hold itself, but the capture hook
	-- GF_ForceConsoleScreen has to reach the real module instance (a tool VM gets its own copy, so it
	-- cannot raise it from outside).
	task.spawn(function()
		while true do
			task.wait(0.5)
			local busy = false
			for _ in pairs(holding) do
				busy = true
				break
			end
			local force = workspace:GetAttribute("GF_ForceConsoleScreen") == true
			if busy or force then
				ObjectiveService.showScreen(true)
			elseif workspace:GetAttribute("GF_ConsoleScreen") == true then
				ObjectiveService.showScreen(false)
			end
		end
	end)
	local r = remote("InteractRequest")
	if r then
		r.OnServerEvent:Connect(function(player, target)
			if target == "Relay" or target == "BlackBox" or target == "Beacon" or target == "ConquestConsole" or target == "ConquestNode" or target == "ConvoyCrate" or target == "UplinkDish" or target == "UplinkConfirm" or target == "PowerRestore" or target == "PowerStabilise" or target == "ArsenalPad" or target == "ArchiveConsole" then
				if not require(script.Parent.NetGuard).allow(player, "interact") then
					return
				end
				ObjectiveService.request(player)
			end
		end)
	end
end

-- Re-publish the current objective state to one player (HUD paint on deploy, and after any reconnect).
function ObjectiveService.publish(player: Player?)
	local spot, label = currentMarker()
	local payload = { progress = progress, complete = complete, template = templateId, marker = complete and nil or (spot and { position = spot, label = label } or nil) }
	local r = ReplicatedStorage.GF.Remotes:FindFirstChild("ObjectiveProgress")
	if not r then
		return
	end
	if player then
		r:FireClient(player, payload)
	else
		r:FireAllClients(payload)
	end
end

-- GF_RelayDist: nearest live player distance to the relay, published once a second for tutorial hints.
task.spawn(function()
	while true do
		task.wait(1)
		local relay = ObjectiveService.getRelay and ObjectiveService.getRelay()
		if relay and relay.PrimaryPart then
			local best = 999
			for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
				local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if root then
					best = math.min(best, ((root :: BasePart).Position - relay.PrimaryPart.Position).Magnitude)
				end
			end
			workspace:SetAttribute("GF_RelayDist", best)
		end
	end
end)

-- S08-012 objective briefing: Voss narrates the objective at mission start and every stage
-- transition — what the squad is doing, how far along they are, and where the next marker is.
-- Progress publishes continuously so the HUD never leaves players guessing.
function ObjectiveService.publishBriefing(stage: string, progress: number, markerPos: Vector3?)
	workspace:SetAttribute("GF_ObjectiveStage", stage)
	workspace:SetAttribute("GF_ObjectiveProgress", math.floor(progress * 100))
	if markerPos then
		workspace:SetAttribute("GF_NextMarkerX", math.floor(markerPos.X))
		workspace:SetAttribute("GF_NextMarkerZ", math.floor(markerPos.Z))
	end
	workspace:SetAttribute("GF_BriefingUpdated", os.clock())
end

return ObjectiveService
