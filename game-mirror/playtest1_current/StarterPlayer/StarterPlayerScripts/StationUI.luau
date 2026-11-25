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

local missionRow = row(1)
local missionLayout = Instance.new("UIListLayout")
missionLayout.FillDirection = Enum.FillDirection.Horizontal
missionLayout.Padding = UDim.new(0, 8)
missionLayout.Parent = missionRow

local headLabel = label(body, "PRIMARY OPERATION", UDim2.new(1, -8, 0, 18), UDim2.fromOffset(0, 0), MUTED, 13)
headLabel.LayoutOrder = 0
local MISSIONS = {
	{ id = "SABOTAGE_RELAY", short = "SABOTAGE", desc = "Move to the Ascendancy relay, disable it, then hold the landing zone for extraction." },
	{ id = "RECOVER_TECH", short = "RECOVER", desc = "Reach the downed scientific transport and extract the flight recorder from its black box." },
	{ id = "DEFEND_BEACON", short = "DEFEND", desc = "Activate the human comm beacon, then hold the position under Ascendancy attack." },
	{ id = "ELIM_COMMANDER", short = "COMMAND", desc = "Locate the Ascendancy commander and eliminate him and his guards." },
	{ id = "ELIM_WALKER", short = "WALKER", desc = "Destroy the Bastion Walker siege mech, then secure the battlefield." },
	{ id = "ELIM_TALON", short = "TALON", desc = "Defeat the three elite Talon operatives in one linked encounter." },
	{ id = "CONQUEST_DOMINION", short = "DOMINION", desc = "Clear the base, seize the console, then hold it for 45 seconds." },
	{ id = "CONQUEST_FOUNDRY", short = "FOUNDRY", desc = "Cut turret power, capture the control point, then hold it for 60 seconds." },
	{ id = "CONQUEST_THRONEFALL", short = "THRONEFALL", desc = "Breach the stronghold, defeat High Marshal Veyr, capture the command node." },
	{ id = "SABOTAGE_AEGIS", short = "AEGIS", desc = "Disable both shield generators, then destroy the exposed emitter." },
	{ id = "RECOVERY_CONVOY", short = "CONVOY", desc = "Recover both convoy crates, then defeat the pursuit squad." },
	{ id = "DEFENSE_UPLINK", short = "UPLINK", desc = "Activate the comms dish, defend the uplink for 75 seconds, then confirm." },
	{ id = "DEFENSE_POWER", short = "POWER", desc = "Restore the generator, defend it for 90 seconds, then stabilise output." },
	{ id = "SABOTAGE_ARSENAL", short = "ARSENAL", desc = "Charge both depot pads, clear the depot, and verify the stockpile is destroyed." },
	{ id = "RECOVERY_ARCHIVE", short = "ARCHIVE", desc = "Reach the intel room, break the data console, and recover the archive." },
}
local missionButtons = {}
local selectedTemplate = "SABOTAGE_RELAY"
local missionDesc = label(body, MISSIONS[1].desc, UDim2.new(1, -8, 0, 34), UDim2.fromOffset(0, 0), MUTED, 13)
missionDesc.LayoutOrder = 2
for i, m in ipairs(MISSIONS) do
	local b = button(missionRow, m.short, UDim2.fromOffset(128, 30), UDim2.fromOffset(0, 0), CYAN)
	b.TextSize = 13
	missionButtons[m.id] = b
	b.Activated:Connect(function()
		selectedTemplate = m.id
		missionDesc.Text = m.desc
		for id, other in missionButtons do
			other.BackgroundColor3 = if id == selectedTemplate then Color3.fromRGB(28, 92, 128) else Color3.fromRGB(38, 44, 54)
		end
	end)
end
missionButtons.SABOTAGE_RELAY.BackgroundColor3 = Color3.fromRGB(28, 92, 128)

local diffLabel = label(body, "DIFFICULTY", UDim2.new(0, 200, 0, 18), UDim2.fromOffset(0, 0), MUTED, 13)
diffLabel.LayoutOrder = 3
local diffRow = row(4)
local diffLayout = Instance.new("UIListLayout")
diffLayout.FillDirection = Enum.FillDirection.Horizontal
diffLayout.Padding = UDim.new(0, 8)
diffLayout.Parent = diffRow
local difficulties = { "Easy", "Normal" }
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
deploy.LayoutOrder = 5
deploy.TextSize = 20
local requestDeploy = remotes:WaitForChild("RequestDeploy") :: RemoteEvent
-- Honest deploy states: the spinner ends when the server answers, not on a fixed timer, and a refusal is
-- shown with its reason plus a retry. Before this a refused launch looked exactly like a slow one.
local status = label(body, "", UDim2.new(1, -8, 0, 18), UDim2.fromOffset(0, 0), MUTED, 12)
status.LayoutOrder = 7

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
quickButton.LayoutOrder = 6
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
	requestDeploy:FireServer({ difficulty = selectedDifficulty, template = selectedTemplate, dispatch = true, privacy = selectedPrivacy })
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
	requestDeploy:FireServer({ difficulty = selectedDifficulty, template = selectedTemplate })
	-- Watchdog only: if command never answers, say so instead of spinning forever.
	task.delay(8, function()
		if not deploy.Active then
			deply_reset()
			status.Text = "No response from command. Press deploy to retry."
			status.TextColor3 = AMBER
		end
	end)
end)

label(table_, "WASD move  ·  LMB fire  ·  RMB aim  ·  Q dodge  ·  R reload  ·  Z / X abilities",
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
	if not payload.objectiveComplete then
		table.insert(lines, "")
		table.insert(lines, "Primary objective incomplete — no completion payout.")
	elseif not payload.success then
		table.insert(lines, "")
		table.insert(lines, "Extraction failed — unsecured salvage was lost.")
	end
	debriefTitle.Text = if payload.lateJoin then "EXTRACTED — REINFORCEMENT" elseif payload.objectiveComplete then "OPERATION COMPLETE" elseif payload.success then "EXTRACTED — OBJECTIVE OPEN" else "OPERATION FAILED"
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
	for _, name in { "GFMissionHUD", "GF_HUD" } do
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

task.spawn(function()
	while true do
		task.wait(0.2)
		local character = PLAYER.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local station = workspace:FindFirstChild("Station")
		local anchor = station and station:FindFirstChild("WarTableBase") :: BasePart?
		local near = false
		if root and anchor then
			near = (root.Position - anchor.Position).Magnitude <= 36
		end
		-- A server-set attribute force-shows the panel, so the war table can be driven and photographed.
		-- NOTE: this pair of lines is the ONLY place `show` is computed. An earlier patch replaced them with
		-- the comment alone, leaving show == nil: the panel was then set to nil every 0.2s (never visible) and
		-- focus was always cleared. That is why the war table stopped opening at all.
		local forced = workspace:GetAttribute("GF_StationPanel") == true
		-- The debrief owns the screen when it is open: the heartbeat must not re-show the war table underneath it.
		local debriefOpen = debrief.Visible
		local show = (forced or (onStation and near)) and not debriefOpen
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

