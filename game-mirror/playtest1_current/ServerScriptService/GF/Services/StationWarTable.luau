--!strict
-- War-table dressing: crew, wall intel screens, squad slots.
-- VISUAL_REVIEW V98 said the table was correct but the room was empty — no crew, no screens, and
-- nothing on the table showing who you are deploying with.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local SquadService = require(game:GetService("ServerScriptService").GF.Services.SquadService)
local Classes = require(ReplicatedStorage.GF.Shared.Configs.Classes)
local Missions = require(ReplicatedStorage.GF.Shared.Configs.Missions)
local Difficulties = require(ReplicatedStorage.GF.Shared.Configs.Difficulties)

local StationWarTable = {}
local CREW_COLORS = {
	Assault = Color3.fromRGB(196, 214, 232),
	Heavy = Color3.fromRGB(232, 176, 96),
	Recon = Color3.fromRGB(120, 226, 255),
	Support = Color3.fromRGB(150, 232, 176),
}
local STEEL = Color3.fromRGB(38, 44, 52)
local DARK = Color3.fromRGB(20, 24, 30)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = true
	p.Parent = parent
	return p
end

local function weld(partA: BasePart, partB: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = partA
	w.Part1 = partB
	w.Parent = partA
end

-- A crew member is a cheap six-part figure: no rig asset, no animation asset, readable silhouette.
local function buildCrew(parent: Instance, cf: CFrame, className: string, accent: Color3, index: number)
	local model = Instance.new("Model")
	model.Name = "Crew_" .. className
	model.Parent = parent
	local torso = part(model, "Torso", Vector3.new(2, 2.2, 1), cf * CFrame.new(0, 3.6, 0), STEEL, Enum.Material.Metal)
	part(model, "ChestPlate", Vector3.new(1.9, 1.1, 0.3), cf * CFrame.new(0, 4, -0.55), accent, Enum.Material.Neon)
	part(model, "Head", Vector3.new(1.2, 1.2, 1.2), cf * CFrame.new(0, 5.4, 0), Color3.fromRGB(58, 62, 70), Enum.Material.SmoothPlastic)
	part(model, "Visor", Vector3.new(1, 0.3, 0.2), cf * CFrame.new(0, 5.5, -0.6), accent, Enum.Material.Neon)
	local leftArm = part(model, "LeftArm", Vector3.new(0.7, 2, 0.7), cf * CFrame.new(-1.4, 3.5, 0), STEEL, Enum.Material.Metal)
	local rightArm = part(model, "RightArm", Vector3.new(0.7, 2, 0.7), cf * CFrame.new(1.4, 3.5, 0), STEEL, Enum.Material.Metal)
	part(model, "LeftLeg", Vector3.new(0.8, 2.4, 0.8), cf * CFrame.new(-0.55, 1.2, 0), DARK, Enum.Material.Metal)
	part(model, "RightLeg", Vector3.new(0.8, 2.4, 0.8), cf * CFrame.new(0.55, 1.2, 0), DARK, Enum.Material.Metal)
	model.PrimaryPart = torso
	-- idle sway: the room read as mannequins without it
	local phase = index * 0.9
	task.spawn(function()
		while model.Parent do
			local t = tick() + phase
			local sway = CFrame.Angles(math.rad(math.sin(t * 0.7) * 1.6), 0, math.rad(math.sin(t * 0.5) * 1.2))
			local bob = math.sin(t * 1.4) * 0.06
			torso.CFrame = cf * CFrame.new(0, 3.6 + bob, 0) * sway
			leftArm.CFrame = cf * CFrame.new(-1.4, 3.5 + bob, 0) * CFrame.Angles(math.rad(math.sin(t * 0.9) * 4), 0, 0)
			rightArm.CFrame = cf * CFrame.new(1.4, 3.5 + bob, 0) * CFrame.Angles(math.rad(math.cos(t * 0.9) * 4), 0, 0)
			task.wait(1 / 20)
		end
	end)
	return model
end

local function buildScreen(parent: Instance, cf: CFrame, title: string)
	local panel = part(parent, "IntelScreen", Vector3.new(20, 11, 0.4), cf, Color3.fromRGB(6, 10, 14), Enum.Material.SmoothPlastic)
	-- The panels sit on the player side of the table, so the default Front face (normal -Z) showed both
	-- screens mirrored. Back faces the approach and is not mirrored.
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(640, 360)
	gui.LightInfluence = 0
	gui.Parent = panel
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(8, 14, 20)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, -40, 0, 46)
	header.Position = UDim2.fromOffset(20, 16)
	header.Text = title
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Font = Enum.Font.GothamBold
	header.TextSize = 30
	header.TextColor3 = Color3.fromRGB(120, 226, 255)
	header.Parent = bg
	local bodyText = Instance.new("TextLabel")
	bodyText.Name = "Body"
	bodyText.BackgroundTransparency = 1
	bodyText.Size = UDim2.new(1, -40, 1, -80)
	bodyText.Position = UDim2.fromOffset(20, 66)
	bodyText.Text = ""
	bodyText.TextXAlignment = Enum.TextXAlignment.Left
	bodyText.TextYAlignment = Enum.TextYAlignment.Top
	bodyText.Font = Enum.Font.GothamMedium
	bodyText.TextSize = 18
	bodyText.TextWrapped = true
	bodyText.TextColor3 = Color3.fromRGB(198, 212, 226)
	bodyText.Parent = bg
	return bodyText
end

local function buildSquadSlots(parent: Instance, tableCF: CFrame)
	local slots = {}
	for i = 1, 4 do
		local offset = CFrame.new((i - 2.5) * 3.2, 0.16, 3.4)
		local pad = part(parent, "SquadSlot" .. i, Vector3.new(2.6, 0.12, 2.6), tableCF * offset, Color3.fromRGB(28, 40, 52), Enum.Material.SmoothPlastic)
		local label = Instance.new("BillboardGui")
		label.Name = "Slot" .. i
		label.Size = UDim2.fromOffset(170, 40)
		label.StudsOffset = Vector3.new(0, 1.2, 0)
		label.AlwaysOnTop = false
		label.Parent = pad
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 0.35
		text.BackgroundColor3 = Color3.fromRGB(6, 10, 14)
		text.Size = UDim2.fromScale(1, 1)
		text.Text = "EMPTY"
		text.Font = Enum.Font.GothamBold
		text.TextSize = 15
		text.TextColor3 = Color3.fromRGB(150, 166, 182)
		text.Parent = label
		slots[i] = { pad = pad, text = text }
	end
	return slots
end

function StationWarTable.start()
	local station = workspace:WaitForChild("Station", 30)
	if not station then
		return
	end
	local base = station:WaitForChild("WarTableBase", 20)
	if not base or not base:IsA("BasePart") then
		return
	end
	if station:FindFirstChild("Crew_Assault") then
		return
	end
	local tableCF = base.CFrame * CFrame.new(0, base.Size.Y * 0.5, 0)
	local crewFolder = Instance.new("Folder")
	crewFolder.Name = "Crew"
	crewFolder.Parent = station
	local classIds = {}
	for _, c in ipairs(Classes.List) do classIds[#classIds + 1] = c.id end
	for i = 1, math.min(4, #classIds) do
		local angle = math.rad(-70 + (i - 1) * 46)
		local cf = tableCF * CFrame.new(math.sin(angle) * 13, -tableCF.Position.Y + base.Position.Y - base.Size.Y * 0.5 + 0.2, math.cos(angle) * 13) * CFrame.Angles(0, angle, 0)
		buildCrew(crewFolder, cf, classIds[i], CREW_COLORS[classIds[i]] or Color3.fromRGB(200, 200, 200), i)
	end
	local screenA = buildScreen(station, tableCF * CFrame.new(-9.5, 15, -13) * CFrame.Angles(math.rad(-8), 0, 0), "OPERATION INTEL")
	local screenB = buildScreen(station, tableCF * CFrame.new(9.5, 15, -13) * CFrame.Angles(math.rad(-8), 0, 0), "SQUAD STATUS")
	local slots = buildSquadSlots(station, tableCF)
	local function refresh()
		local rows = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			local snap = SquadService.snapshot(plr)
			local size = type(snap) == "table" and (snap.size or snap.count or 0) or 0
			rows[#rows + 1] = string.format("%s  ·  squad %d", plr.DisplayName, size)
		end
		local text = #rows > 0 and table.concat(rows, "\n") or "no personnel aboard"
		screenB.Text = text
		for i, slot in ipairs(slots) do
			local plr = Players:GetPlayers()[i]
			if plr then
				slot.text.Text = plr.DisplayName
				slot.text.TextColor3 = Color3.fromRGB(120, 226, 255)
				slot.pad.Color = Color3.fromRGB(30, 58, 74)
			else
				slot.text.Text = "OPEN SLOT"
				slot.text.TextColor3 = Color3.fromRGB(150, 166, 182)
				slot.pad.Color = Color3.fromRGB(28, 40, 52)
			end
		end
	end
	local function intelText(): string
		local templateId = workspace:GetAttribute("GF_OperationTemplate")
		local diffId = workspace:GetAttribute("GF_OperationDifficulty")
		if type(diffId) ~= "string" then
			diffId = "Normal"
		end
		local mission = type(templateId) == "string" and Missions.ById[templateId] or nil
		if not mission then
			mission = Missions.List[1]
		end
		local diff = Difficulties.ById[diffId] or Difficulties.List[1]
		local crew = math.max(1, #Players:GetPlayers())
		local tickets = Difficulties.ticketsFor(diffId, crew)
		return string.format(
			"OPERATION  %s\nPRIMARY    %s\nTHREAT     %s  ·  %d hostiles\nRESPAWNS   %d available  ·  +%d per extra operator\nBOUNTY     credits x%.1f\nFAMILY     %s",
			mission.displayName,
			mission.primary,
			diff.displayName,
			diff.enemyBudget,
			tickets,
			diff.ticketPerPlayer,
			diff.rewardMultiplier,
			mission.family or "?"
		)
	end
	local function refreshAll()
		refresh()
		screenA.Text = intelText()
	end
	task.spawn(function()
		while screenB.Parent do
			pcall(refreshAll)
			task.wait(2)
		end
	end)
	print("[GF] war table: crew, intel screens and squad slots online")
end

return StationWarTable
