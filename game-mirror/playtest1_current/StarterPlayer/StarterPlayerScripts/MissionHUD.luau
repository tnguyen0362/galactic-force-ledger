--!strict
-- Mission HUD: objective, salvage, extraction, interact prompt, debrief.
-- Built standalone so it cannot break the existing vitals HUD.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")

local gui = Instance.new("ScreenGui")
gui.Name = "GFMissionHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function panel(parent, size, position, anchor)
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor or Vector2.new(0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(16, 20, 26)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 200, 255)
	stroke.Transparency = 0.6
	stroke.Thickness = 1
	stroke.Parent = frame
	return frame
end

local function label(parent, text, size, position, textSize, color)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextSize = textSize
	l.TextColor3 = color or Color3.fromRGB(226, 236, 245)
	l.Text = text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

-- objective
local objectiveFrame = panel(gui, UDim2.fromScale(0.34, 0.075), UDim2.fromScale(0.33, 0.03), Vector2.new(0.5, 0))
local objectiveTitle = label(objectiveFrame, "PRIMARY OBJECTIVE", UDim2.fromScale(1, 0.45), UDim2.fromScale(0.04, 0.05), 14, Color3.fromRGB(255, 186, 92))
local objectiveText = label(objectiveFrame, "Sabotage the Ascendancy relay", UDim2.fromScale(1, 0.45), UDim2.fromScale(0.04, 0.5), 15)
local barBg = Instance.new("Frame")
barBg.Size = UDim2.fromScale(0.92, 0.08)
barBg.Position = UDim2.fromScale(0.04, 0.92)
barBg.BackgroundColor3 = Color3.fromRGB(40, 46, 56)
barBg.BorderSizePixel = 0
barBg.Parent = objectiveFrame
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(90, 200, 255)
barFill.BorderSizePixel = 0
barFill.Parent = barBg
objectiveFrame.Visible = false

-- salvage
local salvageFrame = panel(gui, UDim2.fromScale(0.2, 0.055), UDim2.fromScale(0.015, 0.72), Vector2.new(0, 0))
salvageFrame.BackgroundTransparency = 0.45
local salvageText = label(salvageFrame, "SALVAGE  0 · 0 · 0", UDim2.fromScale(0.92, 1), UDim2.fromScale(0.05, 0), 13)
salvageText.TextXAlignment = Enum.TextXAlignment.Center

-- extraction banner
local banner = panel(gui, UDim2.fromScale(0.36, 0.06), UDim2.fromScale(0.5, 0.12), Vector2.new(0.5, 0))
banner.BackgroundColor3 = Color3.fromRGB(30, 44, 34)
local bannerText = label(banner, "", UDim2.fromScale(0.94, 1), UDim2.fromScale(0.5, 0), 15, Color3.fromRGB(150, 255, 190))
bannerText.TextXAlignment = Enum.TextXAlignment.Center
banner.Visible = false

-- interact prompt
-- Interact prompt sits above the controls line: at 0.8 it printed straight through "Fire [LMB] Aim [RMB] ..."
local prompt = panel(gui, UDim2.fromScale(0.24, 0.05), UDim2.fromScale(0.5, 0.135), Vector2.new(0.5, 0))
prompt.BackgroundTransparency = 0.35
local promptText = label(prompt, "", UDim2.fromScale(0.94, 1), UDim2.fromScale(0.5, 0), 14)
promptText.TextXAlignment = Enum.TextXAlignment.Center
prompt.Visible = false

-- debrief
local debrief = panel(gui, UDim2.fromScale(0.4, 0.34), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
-- S13-017: the debrief closes with the galactic war snapshot — cached front state, how fresh the
-- data is, and what this mission contributed. Stale cache still renders with its age labeled.
local warRow = Instance.new("TextLabel")
warRow.Name = "WarSnapshot"
warRow.BackgroundTransparency = 1
warRow.Size = UDim2.new(1, 0, 0, 18)
warRow.Font = Enum.Font.RobotoMono
warRow.TextSize = 12
warRow.TextColor3 = Color3.fromRGB(120, 180, 255)
warRow.TextXAlignment = Enum.TextXAlignment.Left
warRow.Text = ""
warRow.Parent = debrief

-- S02-044/045 priority dispatch: a HUD side button, never a physical terminal. PC/touch click or
-- tap; controller binding routes through the semantic input layer like every other action.
local dispatchButton = Instance.new("TextButton")
dispatchButton.Name = "PriorityDispatch"
dispatchButton.Size = UDim2.new(0, 130, 0, 34)
dispatchButton.Position = UDim2.new(1, -140, 0.5, 0)
dispatchButton.BackgroundColor3 = Color3.fromRGB(40, 48, 60)
dispatchButton.TextColor3 = Color3.fromRGB(140, 200, 255)
dispatchButton.Font = Enum.Font.RobotoMono
dispatchButton.TextSize = 13
dispatchButton.Text = "PRIORITY DISPATCH"
dispatchButton.Parent = gui
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
debrief.BackgroundTransparency = 0.06
local debriefTitle = label(debrief, "MISSION COMPLETE", UDim2.fromScale(0.9, 0.16), UDim2.fromScale(0.05, 0.06), 22, Color3.fromRGB(150, 255, 190))
debriefTitle.TextXAlignment = Enum.TextXAlignment.Center
local debriefBody = label(debrief, "", UDim2.fromScale(0.9, 0.6), UDim2.fromScale(0.05, 0.26), 16)
-- Rank-up flourish: an XP threshold crossing is the one moment a debrief should move.
local rankUpLabel = label(debrief, "", UDim2.fromScale(0.9, 0.08), UDim2.fromScale(0.05, 0.94), 22, Color3.fromRGB(255, 214, 120))
rankUpLabel.TextXAlignment = Enum.TextXAlignment.Center
rankUpLabel.Visible = false
local TweenService = game:GetService("TweenService")

local function playRankUp(fromRank, toRank, count)
	local before = math.max(1, fromRank)
	rankUpLabel.Text = (count and count > 1) and string.format("RANK UP  %d → %d  (x%d)", before, toRank, count) or string.format("RANK UP  %d → %d", before, toRank)
	rankUpLabel.Visible = true
	rankUpLabel.TextTransparency = 0
	rankUpLabel.TextSize = 14
	local grow = TweenService:Create(rankUpLabel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 22 })
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
		objectiveTitle.TextColor3 = Color3.fromRGB(150, 255, 190)
		objectiveText.Text = "Extraction authorized"
		barFill.Size = UDim2.fromScale(1, 1)
	else
		if objectiveComplete then
			-- A new deployment republishes complete=false. Without this the tracker kept the previous
			-- mission's green COMPLETE title while the new objective was still running (captured).
			objectiveComplete = false
			objectiveTitle.Text = "PRIMARY OBJECTIVE"
			objectiveTitle.TextColor3 = Color3.fromRGB(255, 186, 92)
		end
		barFill.Size = UDim2.fromScale(math.clamp(payload.progress or 0, 0, 1), 1)
		-- The tracker text used to be fixed, so a RECOVER carry still read "Sabotage the Ascendancy relay"
		-- while the mechanic on the ground was carrying a case. The published hint is the objective line.
		if type(payload.hint) == "string" and payload.hint ~= "" then
			objectiveText.Text = payload.hint
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
		bannerText.TextColor3 = Color3.fromRGB(150, 255, 190)
	elseif payload.called then
		banner.Visible = true
		bannerText.Text = string.format("EXTRACTION INBOUND — %ds", payload.remaining or 0)
		bannerText.TextColor3 = Color3.fromRGB(255, 210, 140)
	else
		banner.Visible = false
	end
end

Remotes.ObjectiveProgress.OnClientEvent:Connect(setProgress)
Remotes.SalvageChanged.OnClientEvent:Connect(setSalvage)
-- Extraction vote banner: the vote had no visible surface at all, so a squad could be voting with nothing on
-- screen. Y confirms with the interact key, N declines with the reload key.
local voteLabel = label(gui, "", UDim2.fromOffset(520, 22), UDim2.new(0.5, -260, 0, 82), 15, Color3.fromRGB(255, 210, 140))
voteLabel.TextXAlignment = Enum.TextXAlignment.Center
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
	voteLabel.Text = string.format("EXTRACTION VOTE  %d/%d   ·   Y confirm   ·   N decline   ·   %ds", tonumber(payload.yes) or 0, tonumber(payload.needed) or 1, tonumber(payload.remaining) or 0)
end)

Remotes.ExtractionState.OnClientEvent:Connect(setExtraction)

Remotes.MissionComplete.OnClientEvent:Connect(function(payload)
	banner.Visible = false
	prompt.Visible = false
	debrief.Visible = false
	local title = payload.success and "EXTRACTION SUCCESSFUL" or "EXTRACTION FAILED"
	debriefTitle.Text = title
	debriefTitle.TextColor3 = payload.success and Color3.fromRGB(150, 255, 190) or Color3.fromRGB(255, 130, 130)
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
markerDot.Size = UDim2.fromOffset(14, 14)
markerDot.BackgroundColor3 = Color3.fromRGB(120, 220, 255)
markerDot.BorderSizePixel = 0
markerDot.Rotation = 45
markerDot.Visible = false
markerDot.Parent = gui
local markerDotCorner = Instance.new("UICorner")
markerDotCorner.CornerRadius = UDim.new(0, 2)
markerDotCorner.Parent = markerDot
local markerText = label(gui, "", UDim2.fromOffset(180, 16), UDim2.fromOffset(0, 0), 13, Color3.fromRGB(150, 230, 255))
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
	markerDot.Position = UDim2.fromOffset(math.floor(x) - 7, math.floor(y) - 7)
	markerDot.BackgroundTransparency = behind and 0.55 or 0
	markerText.Visible = true
	markerText.Position = UDim2.fromOffset(math.floor(x) - 90, math.floor(y) + 12)
	-- Approximate until close: the label says where the marker is, not what is behind cover.
	markerText.Text = string.format("%s%s  %d m", markerKind, behind and " (behind)" or "", distance)
end)

-- Hacking overlay. The server owns the challenge, the arc and the hit test; this only draws the
-- needle and reports the press. Both sides derive the angle from workspace:GetServerTimeNow(), so
-- the arc the player sees is the arc the server scores.
local hack = nil
local hackFrame = Instance.new("Frame")
hackFrame.Size = UDim2.fromOffset(200, 200)
hackFrame.Position = UDim2.new(0.5, -100, 0.5, 40)
hackFrame.BackgroundColor3 = Color3.fromRGB(12, 18, 24)
hackFrame.BackgroundTransparency = 0.15
hackFrame.BorderSizePixel = 0
hackFrame.Visible = false
hackFrame.Parent = gui
local hackCorner = Instance.new("UICorner")
hackCorner.CornerRadius = UDim.new(0.5, 0)
hackCorner.Parent = hackFrame
local hackMarks = {}
for index = 1, 24 do
	local mark = Instance.new("Frame")
	mark.Size = UDim2.fromOffset(4, 13)
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.BorderSizePixel = 0
	mark.BackgroundColor3 = Color3.fromRGB(64, 72, 84)
	mark.Parent = hackFrame
	hackMarks[index] = mark
end
local hackNeedle = Instance.new("Frame")
hackNeedle.Size = UDim2.new(0, 3, 0, 84)
hackNeedle.AnchorPoint = Vector2.new(0.5, 1)
hackNeedle.Position = UDim2.new(0.5, 0, 0.5, 0)
hackNeedle.BackgroundColor3 = Color3.fromRGB(255, 244, 208)
hackNeedle.BorderSizePixel = 0
hackNeedle.Parent = hackFrame
local hackPivot = Instance.new("Frame")
hackPivot.Size = UDim2.fromOffset(12, 12)
hackPivot.AnchorPoint = Vector2.new(0.5, 0.5)
hackPivot.Position = UDim2.new(0.5, 0, 0.5, 0)
hackPivot.BackgroundColor3 = Color3.fromRGB(255, 244, 208)
hackPivot.BorderSizePixel = 0
hackPivot.Parent = hackFrame
local hackLabel = label(hackFrame, "", UDim2.fromOffset(196, 18), UDim2.new(0, 2, 1, -22), 13, Color3.fromRGB(255, 214, 140))
hackLabel.TextXAlignment = Enum.TextXAlignment.Center

local function paintHack(payload)
	local arcStart = payload.arcStart or 0
	local arcWidth = payload.arcWidth or 90
	for index, mark in ipairs(hackMarks) do
		local angle = (index - 1) / #hackMarks * 360
		local delta = math.abs((angle - arcStart + 180) % 360 - 180)
		mark.BackgroundColor3 = (delta <= arcWidth / 2) and Color3.fromRGB(120, 235, 150) or Color3.fromRGB(64, 72, 84)
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

