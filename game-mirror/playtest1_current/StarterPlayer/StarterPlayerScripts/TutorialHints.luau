--!strict
-- S01-025 tutorial drop: contextual hints teach the core loop on the first mission — movement,
-- sprint/vault, telegraphed dodge, aim/fire/reload, shield break/regen, loot, abilities, hacking.
-- Each hint fires once per player, triggered by live game events rather than a fixed script,
-- so the teaching tracks what the player is actually doing.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tokens = require(ReplicatedStorage.GF.Shared.UI.Tokens)
local player = Players.LocalPlayer

local COLOR = Tokens.Color
local TYPE = Tokens.Type
local MONO_BOLD = (TYPE :: any).fontMonoBold or TYPE.fontBold

local function makeFrame(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, transparency: number?, zindex: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.ZIndex = zindex or 1
	f.Parent = parent
	return f
end

local function makeLabel(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, color: Color3, textSize: number, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = bold == true and TYPE.fontBold or TYPE.font
	l.TextSize = textSize
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = text
	l.ZIndex = 10
	l.Parent = parent
	return l
end

local function cornerBracket(parent: Instance, corner: string, color: Color3, length: number, inset: number, zindex: number?)
	local left = corner == "TL" or corner == "BL"
	local topSide = corner == "TL" or corner == "TR"
	local ax = left and 0 or 1
	local ay = topSide and 0 or 1
	local x = left and inset or -inset
	local y = topSide and inset or -inset
	local horizontal = makeFrame(parent, corner .. "_H", UDim2.new(0, length, 0, 2), UDim2.new(ax, x, ay, y), color, 0.18, zindex or 8)
	horizontal.AnchorPoint = Vector2.new(ax, ay)
	local vertical = makeFrame(parent, corner .. "_V", UDim2.new(0, 2, 0, length), UDim2.new(ax, x, ay, y), color, 0.18, zindex or 8)
	vertical.AnchorPoint = Vector2.new(ax, ay)
	local notch = makeFrame(parent, corner .. "_N", UDim2.new(0, math.max(10, length * 0.34), 0, 2), UDim2.new(ax, left and x + 10 or x - 10, ay, topSide and y + 10 or y - 10), color, 0.1, zindex or 8)
	notch.AnchorPoint = Vector2.new(0.5, 0.5)
	notch.Rotation = (left == topSide) and 45 or -45
end

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialHints"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local hintFrame = makeFrame(gui, "HintFrame", UDim2.new(0.78, 0, 0, 76), UDim2.new(0.5, 0, 0.68, 0), COLOR.panelInset, 0.08, 3)
hintFrame.AnchorPoint = Vector2.new(0.5, 0.5)
hintFrame.Visible = false
local hintConstraint = Instance.new("UISizeConstraint")
hintConstraint.MinSize = Vector2.new(320, 76)
hintConstraint.MaxSize = Vector2.new(760, 84)
hintConstraint.Parent = hintFrame
local stroke = Instance.new("UIStroke")
stroke.Color = COLOR.border
stroke.Transparency = 0.2
stroke.Thickness = 1
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = hintFrame
cornerBracket(hintFrame, "TL", COLOR.techCyan, 28, 6, 7)
cornerBracket(hintFrame, "TR", COLOR.techCyan, 28, 6, 7)
cornerBracket(hintFrame, "BL", COLOR.techCyan, 28, 6, 7)
cornerBracket(hintFrame, "BR", COLOR.techCyan, 28, 6, 7)
local spine = makeFrame(hintFrame, "AdvisorySpine", UDim2.new(0, 4, 1, 0), UDim2.new(0, 0, 0, 0), COLOR.warning, 0.08, 6)

local tag = makeLabel(hintFrame, "AdvisoryTag", "FIELD ADVISORY", UDim2.new(0, 180, 0, 14), UDim2.new(0, 18, 0, 6), COLOR.textAccent, TYPE.sizeSmall, true)
tag.Font = MONO_BOLD
tag.TextTransparency = 0.08
local label = makeLabel(hintFrame, "HintText", "", UDim2.new(1, -40, 0, 42), UDim2.new(0, 18, 0, 22), COLOR.textPrimary, TYPE.sizeSmall, false)
label.TextWrapped = true
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextStrokeTransparency = 0.78

local timeBack = makeFrame(hintFrame, "TimeBack", UDim2.new(1, -36, 0, 2), UDim2.new(0, 18, 1, -8), COLOR.graphite, 0.12, 5)
local timeFill = makeFrame(timeBack, "TimeFill", UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), COLOR.techCyan, 0.04, 6)

local shown: { [string]: boolean } = {}
local queue: { string } = {}
local displaying = false
local hintShownAt = 0

local function hintOnce(id: string, text: string)
	if shown[id] then return end
	shown[id] = true
	table.insert(queue, text)
end

-- display queue: one hint at a time, 4.5s each
task.spawn(function()
	while true do
		task.wait(0.5)
		if not displaying and #queue > 0 then
			displaying = true
			local text = table.remove(queue, 1)
			label.Text = text
			hintShownAt = os.clock()
			timeFill.Size = UDim2.new(1, 0, 1, 0)
			hintFrame.Visible = true
			task.wait(4.5)
			hintFrame.Visible = false
			displaying = false
		end
	end
end)

-- restrained motion: enough to read as active command furniture, never a flashing arcade popup
task.spawn(function()
	while gui.Parent do
		if hintFrame.Visible then
			local remaining = math.clamp(1 - ((os.clock() - hintShownAt) / 4.5), 0, 1)
			timeFill.Size = UDim2.new(remaining, 0, 1, 0)
			spine.BackgroundTransparency = 0.08 + 0.12 * (0.5 + 0.5 * math.sin(os.clock() * 2.4))
		end
		task.wait(0.08)
	end
end)

local function isFirstMission(): boolean
	return workspace:GetAttribute("GF_InMission") == true and not shown._done
end

-- drop: movement/camera/sprint hints when the mission begins
local missionWas = false
task.spawn(function()
	while true do
		task.wait(1)
		local inMission = workspace:GetAttribute("GF_InMission") == true
		if inMission and not missionWas then
			missionWas = true
			if player:GetAttribute("GF_TutorialDone") ~= true then
				hintOnce("move", "WASD to move — mouse to look. SHIFT to sprint.")
				task.delay(6, function()
					hintOnce("vault", "Jump toward low cover to vault over it automatically.")
				end)
				task.delay(12, function()
					hintOnce("aim", "Right-click to aim down sights. Watch your reticle bloom.")
				end)
				task.delay(20, function()
					hintOnce("ability", "You carry support abilities — try the Airstrike or Dome Shield when pressed.")
				end)
			end
		end
		missionWas = inMission
	end
end)

-- dodge hint on first enemy telegraph
local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local telegraph = remotes:FindFirstChild("EnemyTelegraph")
if telegraph then
	telegraph.OnClientEvent:Connect(function()
		if isFirstMission() then
			hintOnce("dodge", "Enemy wind-up! CTRL to dodge out of the line — the tell never lies.")
		end
	end)
end

-- reload hint when ammo low
task.spawn(function()
	while true do
		task.wait(2)
		if isFirstMission() then
			local ammo = workspace:GetAttribute("GF_Ammo") or 999
			if ammo <= 4 then
				hintOnce("reload", "Magazine low — R to reload before the next push.")
			end
		end
	end
end)

-- shield break/regen explanation
task.spawn(function()
	local broke = false
	while true do
		task.wait(1)
		if isFirstMission() then
			local shield = workspace:GetAttribute("GF_Shield") or 100
			if shield <= 0 and not broke then
				broke = true
				hintOnce("shield", "Shield down! Break line of sight — it regenerates after a few seconds out of fire.")
			end
		end
	end
end)

-- loot hint on first pickup
workspace:GetAttributeChangedSignal("GF_LastPickup"):Connect(function()
	if isFirstMission() then
		hintOnce("loot", "Salvage collected automatically — it's shared with your squad.")
	end
end)

-- hacking hint near the relay
task.spawn(function()
	while true do
		task.wait(3)
		if isFirstMission() then
			local dist = workspace:GetAttribute("GF_RelayDist") or 999
			if dist < 30 then
				hintOnce("hack", "Relay ahead — hold E at the console to hack it. Stay close, it takes a moment.")
			end
		end
	end
end)
