--!strict
-- Mission HUD: objective, salvage, extraction, interact prompt, debrief.
-- Built standalone so it cannot break the existing vitals HUD.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local Tokens = require(ReplicatedStorage.GF.Shared.UI.Tokens)

local gui = Instance.new("ScreenGui")
gui.Name = "GFMissionHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- Angular mission chrome. Panels stay broad and quiet; information is carried by thin
-- steel strokes, cyan rails, and independent corner brackets. No rounded UI anywhere.
local function addAngularChrome(frame, accent)
	local accentColor = accent or Tokens.Color.techCyan
	local stroke = Instance.new("UIStroke")
	stroke.Name = "PanelStroke"
	stroke.Color = Tokens.Color.border
	stroke.Transparency = 0.32
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	local rail = Instance.new("Frame")
	rail.Name = "AccentRail"
	rail.Size = UDim2.new(0, 3, 1, -14)
	rail.Position = UDim2.fromOffset(0, 7)
	rail.BackgroundColor3 = accentColor
	rail.BackgroundTransparency = 0.08
	rail.BorderSizePixel = 0
	rail.ZIndex = 3
	rail.Parent = frame

	local inset, len, thick = 3, 12, 2
	local specs = {
		{ UDim2.fromOffset(inset, inset), UDim2.fromOffset(len, thick) },
		{ UDim2.fromOffset(inset, inset), UDim2.fromOffset(thick, len) },
		{ UDim2.new(1, -(inset + len), 0, inset), UDim2.fromOffset(len, thick) },
		{ UDim2.new(1, -(inset + thick), 0, inset), UDim2.fromOffset(thick, len) },
		{ UDim2.new(0, inset, 1, -(inset + len)), UDim2.fromOffset(thick, len) },
		{ UDim2.new(0, inset, 1, -(inset + thick)), UDim2.fromOffset(len, thick) },
		{ UDim2.new(1, -(inset + len), 1, -(inset + thick)), UDim2.fromOffset(len, thick) },
		{ UDim2.new(1, -(inset + thick), 1, -(inset + len)), UDim2.fromOffset(thick, len) },
	}
	for index, spec in ipairs(specs) do
		local corner = Instance.new("Frame")
		corner.Name = "Corner" .. index
		corner.Position = spec[1]
		corner.Size = spec[2]
		corner.BackgroundColor3 = accentColor
		corner.BackgroundTransparency = 0.1
		corner.BorderSizePixel = 0
		corner.ZIndex = 4
		corner.Parent = frame
	end
end

local function setPanelAccent(frame, color)
	local stroke = frame:FindFirstChild("PanelStroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = color
		stroke.Transparency = 0.42
	end
	for _, child in frame:GetChildren() do
		if child:IsA("Frame") and (child.Name == "AccentRail" or child.Name:sub(1, 6) == "Corner") then
			child.BackgroundColor3 = color
		end
	end
end

local function addSegments(back, count)
	for index = 1, count - 1 do
		local divider = Instance.new("Frame")
		divider.Name = "Segment" .. index
		divider.Size = UDim2.new(0, 1, 1, 0)
		divider.Position = UDim2.fromScale(index / count, 0)
		divider.BackgroundColor3 = Tokens.Color.panelInset
		divider.BackgroundTransparency = 0.05
		divider.BorderSizePixel = 0
		divider.ZIndex = 3
		divider.Parent = back
	end
end

local function panel(parent, size, position, anchor)
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.new(0, 0)
	frame.BackgroundColor3 = Tokens.Color.panelInset
	frame.BackgroundTransparency = 0.18
	frame.BorderSizePixel = 0
	frame.Parent = parent
	addAngularChrome(frame, Tokens.Color.techCyan)
	return frame
end

local function label(parent, text, size, position, textSize, color)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = Tokens.Type.font
	l.TextSize = math.max(13, textSize)
	l.TextColor3 = color or Tokens.Color.textPrimary
	l.TextStrokeTransparency = 0.72
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

-- objective: structured command tracker. Caption, objective line, numeric progress and a
-- segmented bar are separate reads so the state is legible at console distance.
local objectiveFrame = panel(gui, UDim2.fromScale(0.34, 0.088), UDim2.fromScale(0.33, 0.03), Vector2.new(0.5, 0))
local objectiveTitle = label(objectiveFrame, "PRIMARY OBJECTIVE", UDim2.fromScale(0.58, 0.24), UDim2.fromScale(0.045, 0.07), 14, Tokens.Color.warning)
objectiveTitle.Font = Tokens.Type.fontBold
local objectivePercent = label(objectiveFrame, "0%", UDim2.fromScale(0.25, 0.22), UDim2.fromScale(0.70, 0.08), 14, Tokens.Color.textAccent)
objectivePercent.TextXAlignment = Enum.TextXAlignment.Right
local objectiveText = label(objectiveFrame, "SABOTAGE THE ASCENDANCY RELAY", UDim2.fromScale(0.90, 0.34), UDim2.fromScale(0.045, 0.38), 16)
objectiveText.Font = Tokens.Type.fontBold
local barBg = Instance.new("Frame")
barBg.Size = UDim2.fromScale(0.91, 0.1)
barBg.Position = UDim2.fromScale(0.045, 0.82)
barBg.BackgroundColor3 = Tokens.Color.panelRaised
barBg.BorderSizePixel = 0
barBg.Parent = objectiveFrame
local barStroke = Instance.new("UIStroke")
barStroke.Color = Tokens.Color.border
barStroke.Transparency = 0.55
barStroke.Thickness = 1
barStroke.Parent = barBg
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Tokens.Color.techCyan
barFill.BorderSizePixel = 0
barFill.ZIndex = 2
barFill.Parent = barBg
addSegments(barBg, 10)
objectiveFrame.Visible = false

-- salvage
local salvageFrame = panel(gui, UDim2.fromScale(0.2, 0.058), UDim2.fromScale(0.015, 0.72), Vector2.new(0, 0))
salvageFrame.BackgroundTransparency = 0.28
local salvageText = label(salvageFrame, "SALVAGE  0 · 0 · 0", UDim2.fromScale(0.86, 1), UDim2.fromScale(0.07, 0), 15)
salvageText.TextXAlignment = Enum.TextXAlignment.Center

-- extraction banner
local banner = panel(gui, UDim2.fromScale(0.36, 0.064), UDim2.fromScale(0.5, 0.12), Vector2.new(0.5, 0))
setPanelAccent(banner, Tokens.Color.success)
local bannerText = label(banner, "", UDim2.fromScale(0.92, 1), UDim2.fromScale(0.5, 0), 16, Tokens.Color.success)
bannerText.Font = Tokens.Type.fontBold
bannerText.TextXAlignment = Enum.TextXAlignment.Center
banner.Visible = false

-- interact prompt
-- Interact prompt sits above the controls line: at 0.8 it printed straight through "Fire [LMB] Aim [RMB] ..."
local prompt = panel(gui, UDim2.fromScale(0.26, 0.052), UDim2.fromScale(0.5, 0.135), Vector2.new(0.5, 0))
prompt.BackgroundTransparency = 0.28
setPanelAccent(prompt, Tokens.Color.warning)
local promptText = label(prompt, "", UDim2.fromScale(0.92, 1), UDim2.fromScale(0.5, 0), 15)
promptText.TextXAlignment = Enum.TextXAlignment.Center
prompt.Visible = false

-- debrief
local debrief = panel(gui, UDim2.fromScale(0.44, 0.36), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
-- S13-017: the debrief closes with the galactic war snapshot — cached front state, how fresh the
-- data is, and what this mission contributed. Stale cache still renders with its age labeled.
local warRow = Instance.new("TextLabel")
warRow.Name = "WarSnapshot"
warRow.BackgroundColor3 = Tokens.Color.panelRaised
warRow.BackgroundTransparency = 0.22
warRow.BorderSizePixel = 0
warRow.Size = UDim2.new(1, -40, 0, 22)
warRow.Position = UDim2.new(0, 20, 0.76, 0)
warRow.Font = Tokens.Type.font
warRow.TextSize = 13
warRow.TextColor3 = Tokens.Color.textAccent
warRow.TextStrokeTransparency = 0.75
warRow.TextXAlignment = Enum.TextXAlignment.Left
warRow.Text = ""
warRow.Parent = debrief

-- S02-044/045 priority dispatch: a HUD side button, never a physical terminal. PC/touch click or
-- tap; controller binding routes through the semantic input layer like every other action.
local dispatchButton = Instance.new("TextButton")
dispatchButton.Name = "PriorityDispatch"
dispatchButton.Size = UDim2.fromOffset(190, 52)
dispatchButton.Position = UDim2.new(1, -214, 0.5, -26)
dispatchButton.BackgroundColor3 = Tokens.Color.panelRaised
dispatchButton.BackgroundTransparency = 0.12
dispatchButton.BorderSizePixel = 0
dispatchButton.AutoButtonColor = false
dispatchButton.TextColor3 = Tokens.Color.textAccent
dispatchButton.Font = Tokens.Type.fontBold
dispatchButton.TextSize = 14
dispatchButton.Text = "PRIORITY DISPATCH"
dispatchButton.Parent = gui
addAngularChrome(dispatchButton, Tokens.Color.warning)
dispatchButton.Activated:Connect(function()
	workspace:SetAttribute("GF_PriorityDispatchRequest", os.clock())
end)
task.spawn(function()
	while true do
		task.wait(2)
		if debrief.Visible then
			local front = workspace:GetAttribute("GF_WarFront") or "unknown"
			local contrib = workspace:GetAttribute("GF_WarContribution") or 0
			local age = workspace:GetAttribute("GF_WarSnapshotAge") or 0
			warRow.Text = string.format("WAR FRONT: %s  |  CONTRIBUTION +%s  |  data %ds old", tostring(front), tostring(contrib), math.floor(age))
		end
	end
end)
debrief.BackgroundTransparency = 0.08
local debriefTitle = label(debrief, "MISSION COMPLETE", UDim2.fromScale(0.9, 0.13), UDim2.fromScale(0.05, 0.05), 24, Tokens.Color.success)
debriefTitle.Font = Tokens.Type.fontBold
debriefTitle.TextXAlignment = Enum.TextXAlignment.Center
local titleRule = Instance.new("Frame")
titleRule.Name = "TitleRule"
titleRule.Size = UDim2.fromScale(0.86, 0.006)
titleRule.Position = UDim2.fromScale(0.07, 0.19)
titleRule.BackgroundColor3 = Tokens.Color.border
titleRule.BackgroundTransparency = 0.25
titleRule.BorderSizePixel = 0
titleRule.Parent = debrief
local debriefBody = label(debrief, "", UDim2.fromScale(0.86, 0.52), UDim2.fromScale(0.07, 0.22), 15)
-- Rank-up flourish: an XP threshold crossing is the one moment a debrief should move.
local rankUpLabel = label(debrief, "", UDim2.fromScale(0.9, 0.085), UDim2.fromScale(0.05, 0.87), 22, Tokens.Color.warning)
rankUpLabel.Font = Tokens.Type.fontBold
rankUpLabel.TextXAlignment = Enum.TextXAlignment.Center
rankUpLabel.Visible = false

local function playRankUp(fromRank, toRank, count)
	local before = math.max(1, fromRank)
	rankUpLabel.Text = (count and count > 1) and string.format("RANK UP  %d → %d  (x%d)", before, toRank, count) or string.format("RANK UP  %d → %d", before, toRank)
	rankUpLabel.Visible = true
	rankUpLabel.TextTransparency = 0
	rankUpLabel.TextSize = 14
	local grow = TweenService:Create(rankUpLabel, TweenInfo.new(0.35, Tokens.Motion.easing, Tokens.Motion.direction), { TextSize = 22 })
	grow:Play()
	task.delay(2.6, function()
		local fade = TweenService:Create(rankUpLabel, TweenInfo.new(0.5), { TextTransparency = 1 })
		fade:Play()
		task.delay(0.6, function()
			rankUpLabel.Visible = false
			rankUpLabel.TextTransparency = 0
		end)
	end)
	debrief:SetAttribute("GF_RankUpPlayed", rankUpLabel.Text)
end
debriefBody.TextYAlignment = Enum.TextYAlignment.Top
debriefBody.TextWrapped = true
debrief.Visible = false

-- input-device aware prompt label
local function interactKey(): string
	if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		return "TAP"
	elseif UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		return "X"
	end
	return "E"
end

local objectiveComplete = false

local markerWorld = nil
local markerKind = "OBJECTIVE"

local function setProgress(payload)
	objectiveFrame.Visible = true
	if type(payload.marker) == "table" and typeof(payload.marker.position) == "Vector3" then
		markerWorld = payload.marker.position
		markerKind = payload.marker.label or "OBJECTIVE"
	else
		markerWorld = nil
	end
	if payload.complete then
		objectiveComplete = true
		objectiveTitle.Text = "PRIMARY OBJECTIVE COMPLETE"
		objectiveTitle.TextColor3 = Tokens.Color.success
		objectiveText.Text = "EXTRACTION AUTHORIZED"
		objectivePercent.Text = "100%"
		objectivePercent.TextColor3 = Tokens.Color.success
		barFill.BackgroundColor3 = Tokens.Color.success
		setPanelAccent(objectiveFrame, Tokens.Color.success)
		barFill.Size = UDim2.fromScale(1, 1)
	else
		if objectiveComplete then
			-- A new deployment republishes complete=false. Without this the tracker kept the previous
			-- mission's green COMPLETE title while the new objective was still running (captured).
			objectiveComplete = false
			objectiveTitle.Text = "PRIMARY OBJECTIVE"
			objectiveTitle.TextColor3 = Tokens.Color.warning
		end
		local progress = math.clamp(payload.progress or 0, 0, 1)
		objectivePercent.Text = string.format("%d%%", math.floor(progress * 100 + 0.5))
		objectivePercent.TextColor3 = Tokens.Color.textAccent
		barFill.BackgroundColor3 = Tokens.Color.techCyan
		setPanelAccent(objectiveFrame, Tokens.Color.techCyan)
		barFill.Size = UDim2.fromScale(progress, 1)
		-- The tracker text used to be fixed, so a RECOVER carry still read "Sabotage the Ascendancy relay"
		-- while the mechanic on the ground was carrying a case. The published hint is the objective line.
		if type(payload.hint) == "string" and payload.hint ~= "" then
			objectiveText.Text = string.upper(payload.hint)
		end
	end
end

local function setSalvage(payload)
	salvageText.Text = string.format("SALVAGE  %d · %d · %d", payload.scrap or 0, payload.energyCells or 0, payload.militaryTechnology or 0)
end

local function setExtraction(payload)
	if payload.landed then
		banner.Visible = true
		bannerText.Text = "TRANSPORT LANDED — BOARD NOW"
		bannerText.TextColor3 = Tokens.Color.success
		setPanelAccent(banner, Tokens.Color.success)
	elseif payload.called then
		banner.Visible = true
		bannerText.Text = string.format("EXTRACTION INBOUND — %ds", payload.remaining or 0)
		bannerText.TextColor3 = Tokens.Color.warning
		setPanelAccent(banner, Tokens.Color.warning)
	else
		banner.Visible = false
	end
end

Remotes.ObjectiveProgress.OnClientEvent:Connect(setProgress)
Remotes.SalvageChanged.OnClientEvent:Connect(setSalvage)
-- Extraction vote banner: the vote had no visible surface at all, so a squad could be voting with nothing on
-- screen. Y confirms with the interact key, N declines with the reload key.
local voteLabel = label(gui, "", UDim2.fromOffset(740, 34), UDim2.new(0.5, -370, 0, 136), 15, Tokens.Color.warning)
voteLabel.TextXAlignment = Enum.TextXAlignment.Center
voteLabel.BackgroundColor3 = Tokens.Color.panelInset
voteLabel.BackgroundTransparency = 0.18
voteLabel.BorderSizePixel = 0
addAngularChrome(voteLabel, Tokens.Color.warning)
voteLabel.Visible = false
-- Bind the keys the banner advertises. Without this the banner told players to press Y/N and nothing listened.
local voteActive = false
local voteEndsAt = 0
task.spawn(function()
	while true do
		task.wait(1)
		if voteActive and voteLabel.Visible then
			local left = math.max(0, math.floor(voteEndsAt - os.clock()))
			voteLabel.Text = voteLabel.Text:gsub("%d+s$", string.format("%ds", left))
			if left <= 0 then
				voteActive = false
				voteLabel.Visible = false
			end
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not voteActive then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.Y or key == Enum.KeyCode.ButtonY or key == Enum.KeyCode.DPadUp then
		Remotes.CastVote:FireServer(true)
	elseif key == Enum.KeyCode.N or key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.DPadDown then
		Remotes.CastVote:FireServer(false)
	end
end)

Remotes.VoteStateChanged.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.active ~= true then
		voteLabel.Visible = false
		voteActive = false
		return
	end
	voteActive = true
	voteEndsAt = os.clock() + (tonumber(payload.remaining) or 0)
	voteLabel.Visible = true
	voteLabel.Text = string.format("EXTRACT VOTE %d/%d  ·  Y CONFIRM  ·  N DECLINE  ·  %ds", tonumber(payload.yes) or 0, tonumber(payload.needed) or 1, tonumber(payload.remaining) or 0)
end)

Remotes.ExtractionState.OnClientEvent:Connect(setExtraction)

Remotes.MissionComplete.OnClientEvent:Connect(function(payload)
	banner.Visible = false
	prompt.Visible = false
	debrief.Visible = true
	local title = payload.success and "EXTRACTION SUCCESSFUL" or "EXTRACTION FAILED"
	debriefTitle.Text = title
	debriefTitle.TextColor3 = payload.success and Tokens.Color.success or Tokens.Color.danger
	setPanelAccent(debrief, payload.success and Tokens.Color.success or Tokens.Color.danger)
	local lines = {}
	table.insert(lines, string.format("Credits  base %d  +  squad bonus %d", payload.baseCredits or payload.credits or 0, payload.bonusCredits or 0))
	table.insert(lines, string.format("Military XP  base %d  +  squad bonus %d", payload.baseXp or payload.xp or 0, payload.bonusXp or 0))
	if type(payload.mastery) == "table" and payload.mastery.weaponId then
		table.insert(lines, string.format("Mastery  %s  level %d  (%d XP)",
			tostring(payload.mastery.weaponId), payload.mastery.level or 1, payload.mastery.xp or 0))
	end
	table.insert(lines, string.format("Primary objective: %s", payload.objectiveComplete and "COMPLETE" or "INCOMPLETE"))
	table.insert(lines, string.format("Extraction: %s", payload.success and "SUCCESSFUL" or "FAILED"))
	local bonusSalvage = payload.bonusSalvage
	if type(bonusSalvage) == "table" then
		table.insert(lines, string.format("Salvage bonus  +%d scrap  +%d cells  +%d tech", bonusSalvage.scrap or 0, bonusSalvage.energyCells or 0, bonusSalvage.militaryTechnology or 0))
	end
	table.insert(lines, payload.carriedLost and "Carried salvage LOST" or "Carried salvage secured")
	local s = payload.salvage or {}
	table.insert(lines, string.format("Salvage: %d scrap · %d energy cells · %d tech", s.scrap or 0, s.energyCells or 0, s.militaryTechnology or 0))
	table.insert(lines, string.format("Military Rank: %d", payload.rank or 1))
	if payload.rankUps and payload.rankUps > 0 then
		table.insert(lines, string.format("RANK UP  +%d", payload.rankUps))
	end
	debriefBody.Text = table.concat(lines, "\n")
	if (payload.rankUps or 0) > 0 then
		playRankUp(payload.rankBefore or ((payload.rank or 1) - (payload.rankUps or 0)), payload.rank or 1, payload.rankUps)
	end
	task.delay(9, function()
		debrief.Visible = false
	end)
end)

-- proximity interact prompt (works on every input device)
task.spawn(function()
	while true do
		task.wait(0.25)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			prompt.Visible = false
			continue
		end
		local nearest, nearestLabel = nil, nil
		for _, model in workspace:GetDescendants() do
			if model:IsA("BasePart") and model:GetAttribute("GFInteract") then
				local d = (root.Position - model.Position).Magnitude
				if d <= 16 and (not nearest or d < nearest) then
					nearest = d
					nearestLabel = model:GetAttribute("InteractPrompt") or "Interact"
				end
			end
		end
		if nearestLabel then
			prompt.Visible = true
			promptText.Text = interactKey() .. "  " .. nearestLabel
		else
			prompt.Visible = false
		end
	end
end)

-- Objective marker: a diamond on the objective (or on the nearest living elimination target), clamped
-- to the screen edge when it is behind or outside the view, with a live distance. This is the marker
-- the spec asks for; before it the only locator was one line of text.
local markerDot = Instance.new("Frame")
markerDot.Size = UDim2.fromOffset(16, 16)
markerDot.BackgroundColor3 = Tokens.Color.techCyan
markerDot.BorderSizePixel = 0
markerDot.Rotation = 45
markerDot.Visible = false
markerDot.Parent = gui
local markerStroke = Instance.new("UIStroke")
markerStroke.Color = Tokens.Color.panelInset
markerStroke.Thickness = 1
markerStroke.Transparency = 0.1
markerStroke.Parent = markerDot
local markerCore = Instance.new("Frame")
markerCore.Name = "Core"
markerCore.AnchorPoint = Vector2.new(0.5, 0.5)
markerCore.Position = UDim2.fromScale(0.5, 0.5)
markerCore.Size = UDim2.fromOffset(6, 6)
markerCore.BackgroundColor3 = Tokens.Color.panelInset
markerCore.BorderSizePixel = 0
markerCore.Parent = markerDot
local markerText = label(gui, "", UDim2.fromOffset(200, 20), UDim2.fromOffset(0, 0), 14, Tokens.Color.textAccent)
markerText.TextXAlignment = Enum.TextXAlignment.Center
markerText.Visible = false

game:GetService("RunService").RenderStepped:Connect(function()
	if not markerWorld then
		markerDot.Visible = false
		markerText.Visible = false
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local point, onScreen = camera:WorldToViewportPoint(markerWorld)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local distance = root and math.floor((root.Position - markerWorld).Magnitude) or 0
	local margin = 46
	local x = math.clamp(point.X, margin, math.max(margin, viewport.X - margin))
	local y = math.clamp(point.Y, margin, math.max(margin, viewport.Y - margin))
	local behind = (not onScreen) or point.Z <= 0
	markerDot.Visible = true
	markerDot.Position = UDim2.fromOffset(math.floor(x) - 8, math.floor(y) - 8)
	markerDot.BackgroundTransparency = behind and 0.55 or 0
	markerCore.BackgroundTransparency = behind and 0.55 or 0.05
	markerText.Visible = true
	markerText.Position = UDim2.fromOffset(math.floor(x) - 100, math.floor(y) + 13)
	-- Approximate until close: the label says where the marker is, not what is behind cover.
	markerText.Text = string.format("%s%s  %d m", string.upper(tostring(markerKind)), behind and " (BEHIND)" or "", distance)
end)

-- Hacking overlay. The server owns the challenge, the arc and the hit test; this only draws the
-- needle and reports the press. Both sides derive the angle from workspace:GetServerTimeNow(), so
-- the arc the player sees is the arc the server scores.
local hack = nil
local hackFrame = Instance.new("Frame")
hackFrame.Size = UDim2.fromOffset(220, 220)
hackFrame.Position = UDim2.new(0.5, -110, 0.5, 30)
hackFrame.BackgroundColor3 = Tokens.Color.panelInset
hackFrame.BackgroundTransparency = 0.12
hackFrame.BorderSizePixel = 0
hackFrame.Visible = false
hackFrame.Parent = gui
addAngularChrome(hackFrame, Tokens.Color.techCyan)
local hackMarks = {}
for index = 1, 24 do
	local mark = Instance.new("Frame")
	mark.Size = UDim2.fromOffset(4, 14)
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.BorderSizePixel = 0
	mark.BackgroundColor3 = Tokens.Color.textDisabled
	mark.ZIndex = 2
	mark.Parent = hackFrame
	hackMarks[index] = mark
end
local hackNeedle = Instance.new("Frame")
hackNeedle.Size = UDim2.new(0, 3, 0, 84)
hackNeedle.AnchorPoint = Vector2.new(0.5, 1)
hackNeedle.Position = UDim2.new(0.5, 0, 0.5, 0)
hackNeedle.BackgroundColor3 = Tokens.Color.warning
hackNeedle.BorderSizePixel = 0
hackNeedle.ZIndex = 5
hackNeedle.Parent = hackFrame
local hackPivot = Instance.new("Frame")
hackPivot.Size = UDim2.fromOffset(12, 12)
hackPivot.AnchorPoint = Vector2.new(0.5, 0.5)
hackPivot.Position = UDim2.new(0.5, 0, 0.5, 0)
hackPivot.BackgroundColor3 = Tokens.Color.warning
hackPivot.BorderSizePixel = 0
hackPivot.Rotation = 45
hackPivot.ZIndex = 6
hackPivot.Parent = hackFrame
local hackLabel = label(hackFrame, "", UDim2.fromOffset(216, 20), UDim2.new(0, 2, 1, -25), 14, Tokens.Color.warning)
hackLabel.TextXAlignment = Enum.TextXAlignment.Center

local function paintHack(payload)
	local arcStart = payload.arcStart or 0
	local arcWidth = payload.arcWidth or 90
	for index, mark in ipairs(hackMarks) do
		local angle = (index - 1) / #hackMarks * 360
		local delta = math.abs((angle - arcStart + 180) % 360 - 180)
		mark.BackgroundColor3 = (delta <= arcWidth / 2) and Tokens.Color.success or Tokens.Color.textDisabled
		mark.Rotation = angle
		local radians = math.rad(angle - 90)
		mark.Position = UDim2.new(0.5, math.cos(radians) * 82, 0.5, math.sin(radians) * 82)
	end
	hackLabel.Text = string.format("HACK  %d / 3   %s", payload.stage or 1, interactKey())
end

Remotes.HackState.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.active ~= true then
		hack = nil
		hackFrame.Visible = false
		return
	end
	hack = payload
	hackFrame.Visible = true
	paintHack(payload)
end)

game:GetService("RunService").RenderStepped:Connect(function()
	if not hack then
		return
	end
	local period = hack.period or 1.3
	local angle = ((workspace:GetServerTimeNow() - (hack.startedAt or 0)) / period * 360) % 360
	hackNeedle.Rotation = angle
end)


-- Capture-zone HUD. The ring in the world is the primary read (cyan/red/dim); this bar is the
-- precision instrument — exact progress, state text, and a contested flash so a defender never
-- has to guess why the capture stalled.
local zoneFrame = panel(gui, UDim2.fromScale(0.32, 0.07), UDim2.fromScale(0.5, 0.135), Vector2.new(0.5, 0))
zoneFrame.Visible = false
local zoneTitle = label(zoneFrame, "CONTROL ZONE", UDim2.fromScale(0.45, 0.3), UDim2.fromScale(0.045, 0.1), 14, Tokens.Color.textAccent)
zoneTitle.Font = Tokens.Type.fontBold
local zoneStateText = label(zoneFrame, "", UDim2.fromScale(0.45, 0.3), UDim2.fromScale(0.50, 0.1), 14)
zoneStateText.TextXAlignment = Enum.TextXAlignment.Right
local zoneBarBg = Instance.new("Frame")
zoneBarBg.Size = UDim2.fromScale(0.91, 0.14)
zoneBarBg.Position = UDim2.fromScale(0.045, 0.68)
zoneBarBg.BackgroundColor3 = Tokens.Color.panelRaised
zoneBarBg.BorderSizePixel = 0
zoneBarBg.Parent = zoneFrame
local zoneBarStroke = Instance.new("UIStroke")
zoneBarStroke.Color = Tokens.Color.border
zoneBarStroke.Transparency = 0.55
zoneBarStroke.Thickness = 1
zoneBarStroke.Parent = zoneBarBg
local zoneBarFill = Instance.new("Frame")
zoneBarFill.Size = UDim2.fromScale(0, 1)
zoneBarFill.BackgroundColor3 = Tokens.Color.techCyan
zoneBarFill.BorderSizePixel = 0
zoneBarFill.ZIndex = 2
zoneBarFill.Parent = zoneBarBg
addSegments(zoneBarBg, 8)

local zoneFlash = 0
game:GetService("RunService").RenderStepped:Connect(function(dt)
	if zoneFlash > 0 then
		zoneFlash = math.max(0, zoneFlash - dt)
		zoneStateText.TextColor3 = (math.floor(zoneFlash * 6) % 2 == 0) and Tokens.Color.danger or Tokens.Color.textPrimary
	end
end)

Remotes.ZoneState.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.active ~= true then
		zoneFrame.Visible = false
		return
	end
	zoneFrame.Visible = true
	zoneTitle.Text = string.upper(payload.label or "CONTROL ZONE")
	local state = payload.state or "empty"
	local pct = math.floor((payload.progress or 0) * 100)
	if payload.paused then
		zoneStateText.Text = string.format("PAUSED — %d%%", pct)
		zoneStateText.TextColor3 = Tokens.Color.warning
		zoneBarFill.BackgroundColor3 = Tokens.Color.warning
		setPanelAccent(zoneFrame, Tokens.Color.warning)
	elseif state == "contested" then
		zoneStateText.Text = string.format("CONTESTED — %d%%", pct)
		zoneStateText.TextColor3 = Tokens.Color.danger
		zoneBarFill.BackgroundColor3 = Tokens.Color.danger
		setPanelAccent(zoneFrame, Tokens.Color.danger)
		zoneFlash = 1.2
	elseif state == "capturing" then
		zoneStateText.Text = string.format("CAPTURING — %d%%", pct)
		zoneStateText.TextColor3 = Tokens.Color.textPrimary
		zoneBarFill.BackgroundColor3 = Tokens.Color.techCyan
		setPanelAccent(zoneFrame, Tokens.Color.techCyan)
	else
		zoneStateText.Text = string.format("EMPTY — BLEEDING %d%%", pct)
		zoneStateText.TextColor3 = Tokens.Color.textSecondary
		zoneBarFill.BackgroundColor3 = Tokens.Color.steel
		setPanelAccent(zoneFrame, Tokens.Color.steel)
	end
	zoneBarFill.Size = UDim2.fromScale(math.clamp(payload.progress or 0, 0, 1), 1)
end)

-- interact input: keyboard E, gamepad X, touch tap on the prompt
local function fireInteract()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hack then
		Remotes.HackAttempt:FireServer(hack.id)
		return
	end
	if not root then
		return
	end
	local best, bestTarget = nil, nil
	for _, model in workspace:GetDescendants() do
		if model:IsA("BasePart") and model:GetAttribute("GFInteract") then
			local d = (root.Position - model.Position).Magnitude
			if d <= 16 and (not best or d < best) then
				best = d
				bestTarget = model:GetAttribute("GFInteract")
			end
		end
	end
	if bestTarget then
		Remotes.InteractRequest:FireServer(bestTarget)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then
		fireInteract()
	end
end)

local touchButton = Instance.new("TextButton")
touchButton.Size = UDim2.fromScale(1, 1)
touchButton.BackgroundTransparency = 1
touchButton.Text = ""
touchButton.Parent = prompt
touchButton.Activated:Connect(fireInteract)

