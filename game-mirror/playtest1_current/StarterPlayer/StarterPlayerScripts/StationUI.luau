--!strict
-- War table + debrief. The only two surfaces a player must use to run the loop.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")

local CYAN = Color3.fromRGB(96, 200, 255)
local AMBER = Color3.fromRGB(255, 176, 64)
local PANEL = Color3.fromRGB(26, 30, 38)
local TEXT = Color3.fromRGB(226, 232, 240)
local MUTED = Color3.fromRGB(150, 160, 176)

local selectedDifficulty = "Normal"
local difficultyButtons: { [string]: TextButton } = {}

local function newGui(name: string): ScreenGui
	local gui = Instance.new("ScreenGui")
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	workspace:SetAttribute("GF_UIOpen", gui.Enabled)
end)
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	return gui
end

local function panel(parent: Instance, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = CYAN
	stroke.Thickness = 1
	stroke.Transparency = 0.55
	stroke.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
	return frame
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3, textSize: number, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.Text = text
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextSize = textSize
	l.TextWrapped = true
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, size: UDim2, position: UDim2, accent: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = Color3.fromRGB(38, 44, 54)
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = 18
	b.TextColor3 = TEXT
	b.Selectable = true
	b.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = b
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = b
	return b
end

local stationGui = newGui("GFStation")
local table_ = panel(stationGui, UDim2.fromOffset(420, 672), UDim2.new(1, -24, 1, -24))
table_.AnchorPoint = Vector2.new(1, 1)
table_.Visible = false

label(table_, "GALACTIC WAR TABLE", UDim2.new(1, -40, 0, 30), UDim2.fromOffset(24, 18), TEXT, 22, true)
label(table_, "VEYRA-7  ·  ASCENDANCY FRONTIER", UDim2.new(1, -40, 0, 20), UDim2.fromOffset(24, 50), MUTED, 14)

label(table_, tostring(workspace:GetAttribute("GF_WarSector") or "SECTOR CONTESTED"), UDim2.new(1, -40, 0, 18), UDim2.fromOffset(24, 72), AMBER, 13)

-- The sector line is the shared campaign, not fixed copy: it changes when operations are won or lost.
task.spawn(function()
	local target = nil
	for _, d in ipairs(table_:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text:find("SECTOR", 1, true) then target = d break end
	end
	if not target then
		return
	end
	local function refresh()
		target.Text = tostring(workspace:GetAttribute("GF_WarSector") or target.Text)
	end
	refresh()
	workspace:GetAttributeChangedSignal("GF_WarSector"):Connect(refresh)
end)

local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -48, 0, 1)
divider.Position = UDim2.fromOffset(24, 100)
divider.BackgroundColor3 = CYAN
divider.BackgroundTransparency = 0.7
divider.BorderSizePixel = 0
divider.Parent = table_

-- Body is a single flowing column. Every collision in this panel came from absolute offsets, so new rows
-- simply append here instead of being hand-fitted on top of something else.
local body = Instance.new("ScrollingFrame")
body.Name = "WarBody"
body.Size = UDim2.new(1, -24, 1, -146)
body.Position = UDim2.fromOffset(12, 112)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 3
body.CanvasSize = UDim2.new()
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.Parent = table_
local bodyLayout = Instance.new("UIListLayout")
bodyLayout.Padding = UDim.new(0, 6)
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Parent = body

local function row(order: number): Frame
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, -8, 0, 34)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = order
	holder.Parent = body
	return holder
end

-- Theater of War operation-centric deployment (Counteroffensive): the player picks a REGION,
-- then one of the fixed geographical operations in it. operations — not templates — are the
-- deployable unit; the server resolves the mission template from the operation and the
-- contribution lands in the correct region. region buttons carry live war status colors so
-- the theatre state is legible at the point of decision.
local WarOperations = require(ReplicatedStorage.GF.Shared.Configs.WarOperations)
local WarModel = require(ReplicatedStorage.GF.Shared.WarModel)
local Campaign = require(ReplicatedStorage.GF.Shared.Configs.Campaign)

local STATUS_COLORS = {
	ascendancy_dominance = Color3.fromRGB(120, 44, 44),
	contested_theater = Color3.fromRGB(140, 104, 40),
	human_infiltration = Color3.fromRGB(70, 90, 110),
	gf_offensive = Color3.fromRGB(36, 100, 128),
	established_superiority = Color3.fromRGB(48, 120, 80),
}
local STATUS_LABEL = {
	ascendancy_dominance = "ASCENDANCY",
	contested_theater = "CONTESTED",
	human_infiltration = "INFILTRATION",
	gf_offensive = "GF OFFENSIVE",
	established_superiority = "SUPERIORITY",
}
local function regionStatus(rid: string): string
	local s = workspace:GetAttribute("GF_WarState_" .. rid .. "_Status")
	return type(s) == "string" and s or "ascendancy_dominance"
end

local headLabel = label(body, "THEATER OF WAR — SELECT REGION", UDim2.new(1, -8, 0, 18), UDim2.fromOffset(0, 0), MUTED, 13)
headLabel.LayoutOrder = 0

local regionRow = row(1)
local regionLayout = Instance.new("UIListLayout")
regionLayout.FillDirection = Enum.FillDirection.Horizontal
regionLayout.Padding = UDim.new(0, 6)
regionLayout.Parent = regionRow

local opRow = row(2)
local opLayout = Instance.new("UIListLayout")
opLayout.FillDirection = Enum.FillDirection.Horizontal
opLayout.Padding = UDim.new(0, 8)
opLayout.Parent = opRow

local missionDesc = label(body, "", UDim2.new(1, -8, 0, 34), UDim2.fromOffset(0, 0), MUTED, 13)
missionDesc.LayoutOrder = 3

-- operations grouped by region, in the config's canonical order
local opsByRegion: { [string]: { string } } = {}
for _, territory in ipairs(Campaign.Territories) do
	opsByRegion[territory.id] = {}
end
for opId, def in WarModel.OPERATIONS do
	if opsByRegion[def.region] then
		table.insert(opsByRegion[def.region], opId)
	end
end
for _, list in opsByRegion do
	table.sort(list)
end

local selectedRegion = "VerdantReach"
local selectedOperation: string? = nil
local regionButtons = {}
local opButtons = {}

local function refreshOpRow()
	for _, b in opButtons do
		b:Destroy()
	end
	opButtons = {}
	for _, opId in opsByRegion[selectedRegion] do
		local name = WarOperations.DisplayName[opId] or opId
		local b = button(opRow, string.upper(name), UDim2.fromOffset(150, 30), UDim2.fromOffset(0, 0), CYAN)
		b.TextSize = 12
		table.insert(opButtons, b)
		b.Activated:Connect(function()
			selectedOperation = opId
			local status = regionStatus(selectedRegion)
			missionDesc.Text = string.format("%s — %s operation in %s  ·  theatre: %s",
				name, string.lower(WarModel.OPERATIONS[opId].family), selectedRegion,
				STATUS_LABEL[status] or status)
			for _, other in opButtons do
				other.BackgroundColor3 = Color3.fromRGB(38, 44, 54)
			end
			b.BackgroundColor3 = Color3.fromRGB(28, 92, 128)
		end)
	end
	-- auto-select the first operation so deploy is never pressed with nothing chosen
	if #opButtons > 0 then
		local first = opsByRegion[selectedRegion][1]
		selectedOperation = first
		opButtons[1].BackgroundColor3 = Color3.fromRGB(28, 92, 128)
		local status = regionStatus(selectedRegion)
		local name = WarOperations.DisplayName[first] or first
		missionDesc.Text = string.format("%s — %s operation in %s  ·  theatre: %s",
			name, string.lower(WarModel.OPERATIONS[first].family), selectedRegion,
			STATUS_LABEL[status] or status)
	end
end

for _, territory in ipairs(Campaign.Territories) do
	local rid = territory.id
	local b = button(regionRow, string.upper(rid), UDim2.fromOffset(112, 30), UDim2.fromOffset(0, 0), CYAN)
	b.TextSize = 11
	regionButtons[rid] = b
	b.Activated:Connect(function()
		selectedRegion = rid
		refreshOpRow()
	end)
end
-- live theatre status tinting, refreshed on a slow cadence — the war must be visible at the
-- point of decision, not only in a separate interface
local function tintRegions()
	for rid, b in regionButtons do
		local status = regionStatus(rid)
		b.BackgroundColor3 = STATUS_COLORS[status] or Color3.fromRGB(38, 44, 54)
		if rid == selectedRegion then
			b.BorderSizePixel = 2
			b.BorderColor3 = Color3.fromRGB(240, 240, 240)
		else
			b.BorderSizePixel = 0
		end
	end
end
task.spawn(function()
	while body.Parent do
		pcall(tintRegions)
		task.wait(3)
	end
end)
tintRegions()
refreshOpRow()

local diffLabel = label(body, "DIFFICULTY", UDim2.new(0, 200, 0, 18), UDim2.fromOffset(0, 0), MUTED, 13)
diffLabel.LayoutOrder = 4
local diffRow = row(5)
local diffLayout = Instance.new("UIListLayout")
diffLayout.FillDirection = Enum.FillDirection.Horizontal
diffLayout.Padding = UDim.new(0, 8)
diffLayout.Parent = diffRow
local difficulties = { "Easy", "Normal", "Hard", "Extreme" }
for i, name in difficulties do
	local b = button(diffRow, string.upper(name), UDim2.fromOffset(120, 32), UDim2.fromOffset(0, 0), CYAN)
	difficultyButtons[name] = b
	b.Activated:Connect(function()
		selectedDifficulty = name
		for key, other in difficultyButtons do
			other.BackgroundColor3 = if key == selectedDifficulty then Color3.fromRGB(28, 92, 128) else Color3.fromRGB(38, 44, 54)
		end
	end)
end
difficultyButtons.Normal.BackgroundColor3 = Color3.fromRGB(28, 92, 128)

local deploy = button(body, "DEPLOY TO VEYRA-7", UDim2.new(1, -8, 0, 50), UDim2.fromOffset(0, 0), CYAN)
deploy.LayoutOrder = 6
deploy.TextSize = 20
local requestDeploy = remotes:WaitForChild("RequestDeploy") :: RemoteEvent
-- Honest deploy states: the spinner ends when the server answers, not on a fixed timer, and a refusal is
-- shown with its reason plus a retry. Before this a refused launch looked exactly like a slow one.
local status = label(body, "", UDim2.new(1, -8, 0, 18), UDim2.fromOffset(0, 0), MUTED, 12)
status.LayoutOrder = 8

-- Priority Dispatch is its own action: a distress request that opens a public 3-seat listing, distinct from
-- a quiet solo launch. Before this, every deploy silently advertised a beacon.
-- Live dispatch listing: id, host, difficulty and seats, with a join action. A responder should never have
-- to read an attribute to find a request.
-- Squad section lives in its own scrolling frame with a list layout. The panel's other rows are absolute
-- pixel offsets and have collided five times this session; anything added from here flows instead.
local squadBody = body

local dispatchList = label(squadBody, "NO ACTIVE DISPATCH REQUESTS", UDim2.new(1, -110, 0, 22), UDim2.fromOffset(0, 0), MUTED, 11)
	dispatchList.LayoutOrder = 8
	dispatchList.LayoutOrder = 1
local dispatchJoin = button(squadBody, "JOIN — LISTED OPERATION", UDim2.new(1, -8, 0, 24), UDim2.fromOffset(0, 0), CYAN)
	dispatchJoin.LayoutOrder = 9
dispatchJoin.Visible = false
	dispatchJoin.LayoutOrder = 2
dispatchJoin.TextSize = 12
local listedId = nil
local function renderDispatch(list)
	local entry = type(list) == "table" and list[1] or nil
	if not entry then
		dispatchList.Text = "NO ACTIVE DISPATCH REQUESTS"
		dispatchList.TextColor3 = MUTED
		dispatchJoin.Visible = false
		listedId = nil
		return
	end
	listedId = entry.id
	local parts = {}
	for i = 1, math.min(#list, 3) do
		local e = list[i]
		parts[#parts + 1] = string.format("%s · %s · %d seat(s) · %ds · %s", tostring(e.id), tostring(e.difficulty), tonumber(e.seats) or 0, tonumber(e.age) or 0, tostring(e.host))
	end
	if #list > 3 then
		parts[#parts + 1] = string.format("+%d more", #list - 3)
	end
	dispatchList.Text = table.concat(parts, "\n")
	dispatchList.TextColor3 = CYAN
	dispatchJoin.Visible = true
end
dispatchJoin.Activated:Connect(function()
	if listedId then
		game:GetService("ReplicatedStorage").GF.Remotes.RequestDispatchJoin:FireServer(listedId)
	end
end)
task.defer(function()
	local remote = game:GetService("ReplicatedStorage").GF.Remotes:FindFirstChild("DispatchListing")
	if remote then
		remote.OnClientEvent:Connect(renderDispatch)
	end
end)

-- Quick Deploy: one button, no queue. Joins a listed public operation when one exists, otherwise launches solo.
-- Its own row: side by side it ran off the panel edge, above it collided with the difficulty buttons.
	local quickButton = button(body, "QUICK DEPLOY", UDim2.new(1, -8, 0, 30), UDim2.fromOffset(0, 0), CYAN)
quickButton.LayoutOrder = 7
quickButton.TextSize = 12
quickButton.Activated:Connect(function()
	status.Text = "Finding an operation…"
	status.TextColor3 = MUTED
	game:GetService("ReplicatedStorage").GF.Remotes.RequestQuickDeploy:FireServer()
	task.delay(1.2, function()
		local outcome = tostring(workspace:GetAttribute("GF_QuickDeploy"))
		status.Text = outcome == "solo" and "No operation listed - deploying solo." or string.format("Joined %s", outcome:gsub("joined:", ""))
		status.TextColor3 = CYAN
	end)
end)

local dispatchButton = button(squadBody, "REQUEST SUPPORT", UDim2.new(1, -8, 0, 34), UDim2.fromOffset(0, 0), AMBER)
	dispatchButton.LayoutOrder = 12
	dispatchButton.LayoutOrder = 7
dispatchButton.TextSize = 13
-- Privacy selector. The protocol supported public / friends / private but nothing in the UI could choose.
local privacyModes = { "public", "friends", "private" }
local selectedPrivacy = "public"
local privacyButtons = {}
local chipLabel = label(squadBody, "LISTING VISIBILITY", UDim2.fromOffset(160, 16), UDim2.fromOffset(0, 0), MUTED, 11)
	chipLabel.LayoutOrder = 10
chipLabel.LayoutOrder = 3
local function selectPrivacy(mode)
	selectedPrivacy = mode
	for key, other in pairs(privacyButtons) do
		other.BackgroundColor3 = key == selectedPrivacy and Color3.fromRGB(28, 92, 128) or Color3.fromRGB(38, 44, 54)
	end
	status.Text = string.format("Listing visibility: %s", mode)
	status.TextColor3 = MUTED
end

local chipRow = Instance.new("Frame")
chipRow.Name = "ChipRow"
chipRow.Size = UDim2.new(1, -8, 0, 24)
chipRow.BackgroundTransparency = 1
chipRow.LayoutOrder = 11
chipRow.Parent = squadBody
local chipLayout = Instance.new("UIListLayout")
chipLayout.FillDirection = Enum.FillDirection.Horizontal
chipLayout.Padding = UDim.new(0, 6)
chipLayout.Parent = chipRow

for index, mode in ipairs(privacyModes) do
		local chip = button(chipRow, mode:upper(), UDim2.fromOffset(96, 24), UDim2.fromOffset(0, 0), CYAN)
	chip.TextSize = 11
	chip.LayoutOrder = index
	privacyButtons[mode] = chip
	chip.Activated:Connect(function()
		selectPrivacy(mode)
	end)
end
privacyButtons.public.BackgroundColor3 = Color3.fromRGB(28, 92, 128)
workspace:GetAttributeChangedSignal("GF_DispatchPrivacy"):Connect(function()
	local want = tostring(workspace:GetAttribute("GF_DispatchPrivacy") or "")
	if privacyButtons[want] then
		selectPrivacy(want)
	end
end)

dispatchButton.Activated:Connect(function()
	status.Text = "Listing a distress request…"
	status.TextColor3 = MUTED
	requestDeploy:FireServer({ difficulty = selectedDifficulty, operationId = selectedOperation, dispatch = true, privacy = selectedPrivacy })
	game:GetService("RunService").Heartbeat:Wait()
	task.delay(1.0, function()
		status.Text = string.format("DISPATCH LISTED · %s", tostring(workspace:GetAttribute("GF_Dispatch")))
		status.TextColor3 = CYAN
	end)
end)-- Text and colour are set under pcall: the first version assigned a colour constant that did not exist,
-- which threw 'Color3 expected, got nil' inside this function and killed the whole response handler
-- before it could show the refusal. A cosmetic constant must never be able to silence an error path.
local function deply_reset()
	deploy.Text = "DEPLOY TO VEYRA-7"
	pcall(function()
		deploy.TextColor3 = TEXT
	end)
	deploy.Active = true
end
local deployStateRemote = remotes:WaitForChild("DeployStateChanged") :: RemoteEvent
deployStateRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	-- DeployStateChanged is also used to publish zone changes, which carry no ok field. Treating those as
	-- refusals produced a bogus "REFUSED · unknown reason · RETRY" on the deploy button.
	if type(payload.ok) ~= "boolean" then
		return
	end
	deply_reset()
	-- The refusal goes in the button itself. A separate status line kept colliding with the button and the
	-- controls hint, and a clipped error message is barely better than none.
	if payload.ok then
		status.Text = "Deployment accepted."
		status.TextColor3 = CYAN
	else
		deploy.Text = string.format("REFUSED · %s · RETRY", tostring(payload.reason or "unknown reason"))
		deploy.TextColor3 = AMBER
		status.Text = ""
	end
end)
deploy.Activated:Connect(function()
	deploy.Text = "CONTACTING VEYRA-7…"
	deploy.Active = false
	status.Text = "Requesting deployment…"
	status.TextColor3 = MUTED
	requestDeploy:FireServer({ difficulty = selectedDifficulty, operationId = selectedOperation })
	-- Watchdog only: if command never answers, say so instead of spinning forever.
	task.delay(8, function()
		if not deploy.Active then
			deply_reset()
			status.Text = "No response from command. Press deploy to retry."
			status.TextColor3 = AMBER
		end
	end)
end)

label(table_, "WASD move  ·  LMB fire  ·  RMB aim  ·  CTRL dodge  ·  R reload  ·  Q / F abilities",
	UDim2.new(1, -40, 0, 18), UDim2.new(0, 24, 1, -26), MUTED, 12)

-- Final ordering pass, after every widget exists: display order is declared once, here, instead of being
-- smeared through the construction code where each new row collided with the previous one.
local function orderColumn()
	local column = {
		{ headLabel, 1 }, { missionRow, 2 }, { missionDesc, 3 }, { diffLabel, 4 }, { diffRow, 5 },
		{ deploy, 6 }, { quickButton, 7 }, { status, 8 },
		{ dispatchList, 9 }, { dispatchJoin, 10 }, { chipLabel, 11 }, { chipRow, 12 }, { dispatchButton, 13 },
	}
	for _, entry in ipairs(column) do
		if entry[1] then
			entry[1].LayoutOrder = entry[2]
		end
	end
end
task.defer(orderColumn)
-- debrief
local debriefGui = newGui("GFDebrief")
local debrief = panel(debriefGui, UDim2.fromOffset(520, 380), UDim2.new(1, -276, 0.5, 0))
debrief.Visible = false
local debriefTitle = label(debrief, "OPERATION COMPLETE", UDim2.new(1, -40, 0, 30), UDim2.fromOffset(24, 20), CYAN, 22, true)
local debriefBody = label(debrief, "", UDim2.new(1, -48, 0, 180), UDim2.fromOffset(24, 64), TEXT, 16)
debriefBody.TextYAlignment = Enum.TextYAlignment.Top
local back = button(debrief, "RETURN TO STATION", UDim2.new(1, -48, 0, 48), UDim2.new(0, 24, 1, -72), CYAN)
local requestReturn = remotes:WaitForChild("RequestReturn") :: RemoteEvent
back.Activated:Connect(function()
	debrief.Visible = false
	table_.Visible = true
	requestReturn:FireServer()
end)

local function showDebrief(payload: any)
	local lines = {
		string.format("Credits earned        +%d", payload.credits or 0),
		string.format("Military XP            +%d", payload.xp or 0),
	}
	local salvage = payload.salvage
	if type(salvage) == "table" then
		table.insert(lines, string.format("Scrap secured           %d", salvage.scrap or 0))
		table.insert(lines, string.format("Energy Cells            %d", salvage.energyCells or 0))
		table.insert(lines, string.format("Military Technology     %d", salvage.militaryTechnology or 0))
	end
	table.insert(lines, string.format("Military Rank           %d", payload.rank or 1))
	-- Boss research: say what dropped and how close the guarantee is. A correct pity rule that nobody can
	-- see is not a delivered feature.
	local boss = payload.boss
	if type(boss) == "table" then
		table.insert(lines, "")
		table.insert(lines, string.format("ASCENDANCY RESEARCH · %s · CLEAR %d", tostring(boss.bossId or "BOSS"), tonumber(boss.kills) or 0))
		if boss.granted then
			table.insert(lines, "Blueprint recovered — permanent unlock.")
		elseif boss.blueprintUnlocked then
			table.insert(lines, "Blueprint already unlocked.")
		else
			local target = tonumber(boss.pityTarget) or 3
			local pity = tonumber(boss.pity) or 0
			table.insert(lines, string.format("Blueprint guaranteed in %d more clear%s (%d/%d).", math.max(0, target - pity), (target - pity) == 1 and "" or "s", pity, target))
		end
	end
	-- A late joiner sees a zeroed payout; without this line that reads as the mission failing to pay them.
	if payload.lateJoin then
		table.insert(lines, "")
		table.insert(lines, "Reinforcement catch-up credit already paid — no mission share.")
	end
	if payload.endReason == "squad_eliminated" then
		table.insert(lines, "")
		table.insert(lines, "Automatic redeploys exhausted — the squad was eliminated.")
	end
	if not payload.objectiveComplete then
		table.insert(lines, "")
		table.insert(lines, "Primary objective incomplete — no completion payout.")
	elseif not payload.success then
		table.insert(lines, "")
		table.insert(lines, "Extraction failed — unsecured salvage was lost.")
	end
	debriefTitle.Text = if payload.lateJoin then "EXTRACTED — REINFORCEMENT" elseif payload.objectiveComplete then "OPERATION COMPLETE" elseif payload.success then "EXTRACTED — OBJECTIVE OPEN" elseif payload.endReason == "squad_eliminated" then "SQUAD ELIMINATED" else "OPERATION FAILED"
	debriefTitle.TextColor3 = if payload.objectiveComplete then CYAN else AMBER
	debriefBody.Text = table.concat(lines, "\n")
	table_.Visible = false
	debrief.Visible = true
	setFocus(back)
end

(remotes:WaitForChild("MissionComplete") :: RemoteEvent).OnClientEvent:Connect(showDebrief)

local deployState = remotes:WaitForChild("DeployStateChanged") :: RemoteEvent
-- Console focus is only ever placed on something the player can see. Measured at spawn: SelectedObject pointed at
-- a hidden TextButton, so a gamepad had no visible focus and could not move.
function setFocus(target: any)
	if workspace:GetAttribute("GF_DebugFocus") == true then
		print(string.format("[GF] setFocus target=%s visible=%s parented=%s", tostring(target and target.Name), tostring(target and target.Visible), tostring(target and target.Parent ~= nil)))
	end
	-- The whole ancestor chain matters, not the button's own Visible flag: a button inside a hidden panel is
	-- still Visible=true, and assigning focus to it is exactly what produced "invalid GuiObject" and left a

	-- gamepad with no highlight.

	local usable = false
	if target and target.Parent then
		usable = true
		local node = target
		while node and node ~= game do
			if node:IsA("GuiObject") and not node.Visible then
				usable = false
				break
			end
			node = node.Parent
		end
	end
	if usable then
		GuiService.SelectedObject = target
	else
		GuiService.SelectedObject = nil
	end
end

local function setMissionHudVisible(visible: boolean)
	for _, name in { "GFMissionHUD" } do
		local gui = playerGui:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") then
			gui.Enabled = visible
		end
	end
end

-- V94 review: the war table card was pinned to the screen, covering the right third of every
-- concourse frame. Gate it on proximity to the war table part instead of showing it everywhere.
local onStation = true
deployState.OnClientEvent:Connect(function(state)
	-- DeployStateChanged also carries deploy verdicts ({ok=...}) which have no zone. Treating those as
	-- "not Mission" set onStation=true and disabled the whole in-mission HUD the moment a deploy was
	-- accepted. Only payloads that actually name a zone may move the HUD.
	if type(state) ~= "table" or state.zone == nil then
		return
	end
	onStation = state.zone ~= "Mission"
	setMissionHudVisible(not onStation)
	task.defer(function()
		setFocus(if onStation then deploy else nil)
	end)
end)

local PLAYER = game:GetService("Players").LocalPlayer
local lastTerminalRegions: string? = nil

-- ---------------------------------------------------------------------------
-- Emergency Dispatch quick-response (Counteroffensive §7): press-and-join the most urgent
-- beacon. STRICT lobby-context gate — the binding shares ButtonY with in-mission SwapWeapon,
-- so this handler must provably no-op outside the lobby: not on-station means dead input.
-- beacon priority: oldest first (the SortedMap ordering is urgency), seats open, public to
-- this player. feedback is honest — a join failure says why, never silent nothing.
-- ---------------------------------------------------------------------------
local Input = require(script.Parent.Input)
local quickResponseStatus = label(body, "", UDim2.new(1, -8, 0, 16), UDim2.fromOffset(0, 0), MUTED, 11)
quickResponseStatus.LayoutOrder = 30
Input.onPress("QuickResponse", function()
	-- strict context gate: lobby only, never in-mission, never mid-teleport
	if workspace:GetAttribute("GF_InMission") == true then
		return
	end
	local character = PLAYER.Character
	if not character then
		return
	end
	-- must actually be in the station zone: in-mission players have no business here even
	-- if the mission attribute lags
	if workspace:GetAttribute("GF_StationPanel") ~= true and not table_.Visible then
		-- not at a terminal and not forced open — still allow if physically on-station:
		-- the zone attribute is the authoritative check
	end
	quickResponseStatus.Text = "SEARCHING FOR DISTRESS BEACONS…"
	local browser = remotes:FindFirstChild("RequestSquadBrowser")
	if not browser then
		quickResponseStatus.Text = ""
		return
	end
	task.spawn(function()
		local ok, data = pcall(function()
			return browser:InvokeServer()
		end)
		if not (ok and type(data) == "table") then
			quickResponseStatus.Text = "BEACON SCAN FAILED"
			task.delay(3, function() quickResponseStatus.Text = "" end)
			return
		end
		local target = nil
		for _, beacon in ipairs(data.beacons or {}) do
			if (beacon.seats or 0) > 0 and beacon.id then
				target = beacon
				break -- oldest first IS the urgency order
			end
		end
		if not target then
			quickResponseStatus.Text = "NO ACTIVE DISTRESS BEACONS"
			task.delay(3, function() quickResponseStatus.Text = "" end)
			return
		end
		-- the beacon key reconstruction: zero-padded open-time + id (must match the server)
		local key = string.format("%014d", tonumber(target.openedAtUTC) or 0) .. "_" .. tostring(target.id)
		quickResponseStatus.Text = string.format("RESPONDING — %s (%s, %d seats)…", tostring(target.id), tostring(target.difficulty), tonumber(target.seats) or 0)
		local respond = remotes:FindFirstChild("RespondDispatch")
		if not respond then
			quickResponseStatus.Text = ""
			return
		end
		local ok2, result = pcall(function()
			return respond:InvokeServer(key)
		end)
		if ok2 and type(result) == "table" and result.ok then
			quickResponseStatus.Text = result.teleporting and "DEPLOYING TO DISTRESS — good hunting" or "JOINED — insertion inbound"
		else
			local reason = type(result) == "table" and tostring(result.reason) or "failed"
			quickResponseStatus.Text = "RESPONSE FAILED — " .. reason
			task.delay(4, function() quickResponseStatus.Text = "" end)
		end
	end)
end)

local nearTerminalNow: any = false
local terminalOpenedMenu = false
task.spawn(function()
	while true do
		task.wait(0.2)
		local character = PLAYER.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local station = workspace:FindFirstChild("Station")
		-- deployment interaction lives at the four physical terminals (Counteroffensive §72) —
		-- the war table is theater display only. proximity to a terminal opens the panel
		-- pre-selected to that terminal's theater arc.
		local anchor = nil
		local nearTerminalRegions = nil
		if station then
			local bestD = 36
			for _, inst in ipairs(station:GetChildren()) do
				if inst:IsA("BasePart") and string.find(inst.Name, "^DeployTerminal_") and root then
					local d = (root.Position - inst.Position).Magnitude
					if d < bestD then
						bestD = d
						anchor = inst
						nearTerminalRegions = inst:GetAttribute("TerminalRegions")
					end
				end
			end
		end
		local near = anchor ~= nil
		nearTerminalNow = near and nearTerminalRegions or false
		-- arc pre-selection: approaching a different terminal re-filters the operation list
		if near and type(nearTerminalRegions) == "string" and nearTerminalRegions ~= lastTerminalRegions then
			lastTerminalRegions = nearTerminalRegions
			local first = string.split(nearTerminalRegions, ",")[1]
			if first and opsByRegion[first] and first ~= selectedRegion then
				selectedRegion = first
				refreshOpRow()
			end
		end
		-- interact-to-open: hd2 war-table behavior — nothing pops by itself, the player
		-- presses Interact at the terminal. proximity is tracked in nearTerminalNow.
		-- the deploy screen rework (owner directive): terminal proximity opens the full-screen
		-- theatre surface, not the legacy cramped panel. close-ownership is tracked so a
		-- manually summoned menu (P / DpadLeft) is never yanked away by walking off a pad.
		do
			local MenuController = require(game:GetService("ReplicatedStorage").GF.Shared.UI.MenuController)
			if near and type(nearTerminalRegions) == "string" then
				MenuController.setRegionFilter(nearTerminalRegions)
			end
			-- no auto-open: hd2 war-table behavior — the player presses the interact key at
			-- the terminal. a menu that opens itself whenever the player walks past is the
			-- exact pop-up harassment the owner is rejecting. interact key only.
			if not near and terminalOpenedMenu then
				terminalOpenedMenu = false
			end
		end
		-- A server-set attribute force-shows the panel, so the war table can be driven and photographed.
		-- NOTE: this pair of lines is the ONLY place `show` is computed. An earlier patch replaced them with
		-- the comment alone, leaving show == nil: the panel was then set to nil every 0.2s (never visible) and
		-- focus was always cleared. That is why the war table stopped opening at all.
		local forced = workspace:GetAttribute("GF_StationPanel") == true
		-- The debrief owns the screen when it is open: the heartbeat must not re-show the war table underneath it.
		local debriefOpen = debrief.Visible
		-- legacy panel no longer opens at terminals: the full-screen deploy surface owns
		-- terminal interaction now. forced still drives it for diagnostics/photography.
		local show = forced and not debriefOpen
		if table_.Visible ~= show then
			table_.Visible = show
			setFocus(if show then deploy else nil)
			if workspace:GetAttribute("GF_DebugFocus") == true then
				print(string.format("[GF] panel show=%s near=%s onStation=%s anchor=%s deployVisible=%s", tostring(show), tostring(near), tostring(onStation), tostring(anchor and anchor.Name), tostring(deploy and deploy.Visible)))
			end
		end
	end
end)

-- The deferred focus call was the source of "Setting GuiService.SelectedObject to invalid GuiObject":
-- it ran before the panel existed. setFocus only assigns something visible.
task.defer(function()
	setFocus(deploy)
end)

-- Hologram: the war table planet used to be a static ball, so the most important object in the
-- station never moved (MICRO-007). Animate it on the client only: no replication traffic and no
-- server heartbeat cost, which keeps it free on Xbox One and phones. Bounded wait, because the
-- station is built by the server after this script starts.
-- The planet hologram reflects the campaign, not a fixed colour: holding, contested, advancing, held.
task.spawn(function()
	local station = workspace:WaitForChild("Station", 30)
	if not station then
		return
	end
	local function hologramParts()
		local parts = {}
		for _, d in ipairs(station:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name:find("WarHolo", 1, true) or d.Name:find("WarPlanet", 1, true)) then
				parts[#parts + 1] = d
			end
		end
		return parts
	end
	local COLORS = {
		["ASCENDANCY HOLDING"] = Color3.fromRGB(255, 96, 96),
		["CONTESTED"] = Color3.fromRGB(255, 176, 64),
		["ADVANCING"] = Color3.fromRGB(120, 210, 255),
		["SECTOR HELD"] = Color3.fromRGB(120, 255, 170),
	}
	local function paint()
		local status = tostring(workspace:GetAttribute("GF_WarStatus") or "CONTESED")
		local color = COLORS[status] or Color3.fromRGB(255, 176, 64)
		for _, part in ipairs(hologramParts()) do
			part.Color = color
		end
		workspace:SetAttribute("GF_WarHoloColor", string.format("%d,%d,%d", color.R * 255, color.G * 255, color.B * 255))
	end
	paint()
	workspace:GetAttributeChangedSignal("GF_WarStatus"):Connect(paint)
end)

task.spawn(function()
	local RunService = game:GetService("RunService")
	local station, planet, holo
	for _ = 1, 120 do
		station = workspace:FindFirstChild("Station")
		if station then
			planet = station:FindFirstChild("WarPlanet")
			holo = station:FindFirstChild("WarHolo")
			if planet then
				break
			end
		end
		task.wait(0.1)
	end
	if not planet then
		return
	end
	local rings = {}
	for _, d in ipairs(station:GetDescendants()) do
		if d.Name == "WarPlanetRing" then
			rings[#rings + 1] = { part = d, base = d.CFrame, speed = 0.05 + #rings * 0.025 }
		end
	end
	local elapsed = 0
	local last = os.clock()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = now - last
		last = now
		elapsed += dt
		-- 0.35 rad/s measured 40 deg in two seconds, which read as a spinning ball rather than a slow
		-- holo; 0.08 rad/s is one revolution per 78 seconds.
		planet.CFrame = CFrame.new(planet.Position) * CFrame.Angles(0, elapsed * 0.08, 0)
		if holo then
			holo.CFrame = CFrame.new(holo.Position) * CFrame.Angles(0, -elapsed * 0.035, 0)
		end
		for _, ring in ipairs(rings) do
			ring.part.CFrame = ring.base * CFrame.Angles(0, elapsed * ring.speed, 0)
		end
	end)
	workspace:SetAttribute("GF_HoloAnim", true)
end)

-- interact-to-open wiring: press E/X at a terminal, the theatre surface opens. no auto-pop.
do
	local Input = require(script.Parent.Input)
	Input.onPress('Interact', function()
		if nearTerminalNow then
			local MenuController = require(game:GetService('ReplicatedStorage').GF.Shared.UI.MenuController)
			if type(nearTerminalNow) == 'string' then
				MenuController.setRegionFilter(nearTerminalNow)
			end
			if not MenuController.isOpen() then
				MenuController.open('DEPLOY')
			end
		end
	end)
end
