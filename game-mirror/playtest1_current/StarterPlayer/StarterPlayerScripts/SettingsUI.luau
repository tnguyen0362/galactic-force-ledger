--!strict
-- Settings: sensitivity, subtitles, reduced motion and master volume. Values live in the profile (server
-- authoritative) and are mirrored onto player attributes, which is what the camera, captions and audio read.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local request = remotes:WaitForChild("RequestSettings")
local changed = remotes:WaitForChild("SettingsChanged")
local Tokens = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Tokens"))

local CYAN = Tokens.Color.techCyan
local AMBER = Tokens.Color.warning
local PANEL = Tokens.Color.panel
local RAISED = Tokens.Color.panelRaised
local INSET = Tokens.Color.panelInset
local BORDER = Tokens.Color.border
local TEXT = Tokens.Color.textPrimary
local MUTED = Tokens.Color.textSecondary

local values = {}
local isOpen = false

local gui = Instance.new("ScreenGui")
gui.Name = "GF_Settings"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function cornerBrackets(frame: Frame, color: Color3, transparency: number?)
	for _, x in ipairs({ 0, 1 }) do
		for _, y in ipairs({ 0, 1 }) do
			local horizontal = Instance.new("Frame")
			horizontal.Name = "FrameCornerH"
			horizontal.AnchorPoint = Vector2.new(x, y)
			horizontal.Position = UDim2.fromScale(x, y)
			horizontal.Size = UDim2.fromOffset(18, 2)
			horizontal.BackgroundColor3 = color
			horizontal.BackgroundTransparency = transparency or 0.24
			horizontal.BorderSizePixel = 0
			horizontal.Parent = frame

			local vertical = Instance.new("Frame")
			vertical.Name = "FrameCornerV"
			vertical.AnchorPoint = Vector2.new(x, y)
			vertical.Position = UDim2.fromScale(x, y)
			vertical.Size = UDim2.fromOffset(2, 18)
			vertical.BackgroundColor3 = color
			vertical.BackgroundTransparency = transparency or 0.24
			vertical.BorderSizePixel = 0
			vertical.Parent = frame
		end
	end
end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromScale(0.86, 0.78)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.03
panel.BorderSizePixel = 0
panel.Parent = gui
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MinSize = Vector2.new(320, 300)
sizeLimit.MaxSize = Vector2.new(620, 640)
sizeLimit.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = BORDER
panelStroke.Transparency = 0.22
panelStroke.Thickness = 1
panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
panelStroke.Parent = panel
cornerBrackets(panel, CYAN, 0.18)

local topRule = Instance.new("Frame")
topRule.Name = "CommandTopRule"
topRule.Size = UDim2.new(1, 0, 0, 2)
topRule.BackgroundColor3 = CYAN
topRule.BackgroundTransparency = 0.42
topRule.BorderSizePixel = 0
topRule.Parent = panel

local headerRail = Instance.new("Frame")
headerRail.Name = "HeaderRail"
headerRail.Size = UDim2.fromOffset(3, 34)
headerRail.Position = UDim2.fromOffset(14, 14)
headerRail.BackgroundColor3 = CYAN
headerRail.BackgroundTransparency = 0.18
headerRail.BorderSizePixel = 0
headerRail.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -32, 0, 26)
title.Position = UDim2.fromOffset(24, 12)
title.BackgroundTransparency = 1
title.Font = Tokens.Type.fontBold
title.TextSize = Tokens.Type.sizeTitle
title.TextColor3 = TEXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "SETTINGS"
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -32, 0, 15)
subtitle.Position = UDim2.fromOffset(24, 39)
subtitle.BackgroundTransparency = 1
subtitle.Font = Tokens.Type.font
subtitle.TextSize = Tokens.Type.sizeSmall
subtitle.TextColor3 = MUTED
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Text = "// COMMAND INTERFACE CONFIGURATION"
subtitle.Parent = panel

local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -32, 0, 1)
divider.Position = UDim2.fromOffset(16, 60)
divider.BackgroundColor3 = BORDER
divider.BackgroundTransparency = 0.32
divider.BorderSizePixel = 0
divider.Parent = panel

local dividerAccent = Instance.new("Frame")
dividerAccent.Size = UDim2.fromOffset(72, 2)
dividerAccent.Position = UDim2.fromOffset(16, 59)
dividerAccent.BackgroundColor3 = CYAN
dividerAccent.BackgroundTransparency = 0.34
dividerAccent.BorderSizePixel = 0
dividerAccent.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Name = "SettingsList"
list.Position = UDim2.fromOffset(16, 72)
list.Size = UDim2.new(1, -32, 1, -98)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = BORDER
list.ScrollBarImageTransparency = 0.2
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.Padding = UDim.new(0, 7)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local footer = Instance.new("TextLabel")
footer.Size = UDim2.new(1, -32, 0, 14)
footer.Position = UDim2.new(0, 16, 1, -22)
footer.BackgroundTransparency = 1
footer.Font = Tokens.Type.font
footer.TextSize = 11
footer.TextColor3 = MUTED
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.Text = "SERVER-VALIDATED  //  PROFILE PERSISTED"
footer.Parent = panel

local HINTS = {
	aimSensitivity = "MOUSE / STICK LOOK SPEED",
	volume = "MASTER OUTPUT LEVEL",
	subtitles = "MISSION AND CINEMATIC CAPTIONS",
	reducedMotion = "REDUCE CAMERA MOTION AND FLASHES",
	musicVolume = "MUSIC AND AMBIENT BED LEVEL",
	sfxVolume = "WEAPONS, IMPACTS, INTERFACE",
	voiceVolume = "COMMANDER AND SQUAD VOICE",
	cameraShake = "IMPACT CAMERA SHAKE",
	damageNumbers = "FLOATING COMBAT READOUTS",
}

local rows = {}
local function addRow(order: number, key: string, labelText: string, kind: string)
	local row = Instance.new("Frame")
	row.Name = "Row_" .. key
	row.Size = UDim2.new(1, -5, 0, 68)
	row.BackgroundColor3 = INSET
	row.BackgroundTransparency = 0.1
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = list

	local rowStroke = Instance.new("UIStroke")
	rowStroke.Color = BORDER
	rowStroke.Transparency = 0.62
	rowStroke.Thickness = 1
	rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rowStroke.Parent = row

	local rowEdge = Instance.new("Frame")
	rowEdge.Name = "RowEdge"
	rowEdge.Size = UDim2.new(0, 2, 1, -12)
	rowEdge.Position = UDim2.fromOffset(0, 6)
	rowEdge.BackgroundColor3 = kind == "boolean" and AMBER or CYAN
	rowEdge.BackgroundTransparency = 0.52
	rowEdge.BorderSizePixel = 0
	rowEdge.Parent = row

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -220, 0, 20)
	name.Position = UDim2.fromOffset(14, 8)
	name.BackgroundTransparency = 1
	name.Font = Tokens.Type.fontBold
	name.TextSize = 14
	name.TextColor3 = TEXT
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = labelText
	name.Parent = row

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -220, 0, 16)
	hint.Position = UDim2.fromOffset(14, 32)
	hint.BackgroundTransparency = 1
	hint.Font = Tokens.Type.font
	hint.TextSize = 11
	hint.TextColor3 = MUTED
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	hint.Text = HINTS[key] or ""
	hint.Parent = row

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.fromOffset(56, 22)
	valueLabel.AnchorPoint = Vector2.new(1, 0.5)
	valueLabel.Position = UDim2.new(1, -128, 0.5, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Tokens.Type.fontBold
	valueLabel.TextSize = 13
	valueLabel.TextColor3 = CYAN
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.Parent = row

	rows[key] = { row = row, value = valueLabel, hint = hint, kind = kind }
	return row
end

local function button(parent: Instance, text: string, rightOffset: number, width: number, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, 52)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, rightOffset, 0.5, 0)
	b.BackgroundColor3 = RAISED
	b.Text = text
	b.TextColor3 = TEXT
	b.TextSize = 13
	b.Font = Tokens.Type.fontBold
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Selectable = true
	b.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = BORDER
	stroke.Transparency = 0.48
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	b.MouseEnter:Connect(function()
		stroke.Color = CYAN
		stroke.Transparency = 0.12
	end)
	b.MouseLeave:Connect(function()
		stroke.Color = BORDER
		stroke.Transparency = 0.48
	end)
	b.SelectionGained:Connect(function()
		stroke.Color = CYAN
		stroke.Transparency = 0.12
	end)
	b.SelectionLost:Connect(function()
		stroke.Color = BORDER
		stroke.Transparency = 0.48
	end)
	b.Activated:Connect(onClick)
	return b
end

addRow(1, "aimSensitivity", "AIM SENSITIVITY", "number")
addRow(2, "volume", "MASTER VOLUME", "number")
addRow(3, "subtitles", "SUBTITLES", "boolean")
addRow(4, "reducedMotion", "REDUCED MOTION", "boolean")
addRow(5, "musicVolume", "MUSIC VOLUME", "number")
addRow(6, "sfxVolume", "SFX VOLUME", "number")
addRow(7, "voiceVolume", "VOICE VOLUME", "number")
addRow(8, "cameraShake", "CAMERA SHAKE", "boolean")
addRow(9, "damageNumbers", "DAMAGE NUMBERS", "boolean")

for key, entry in pairs(rows) do
	if entry.kind == "number" then
		button(entry.row, "-", -66, 52, function()
			request:FireServer(key, tonumber(values[key] or 1) - (key == "volume" and 0.1 or 0.25))
		end)
		button(entry.row, "+", -10, 52, function()
			request:FireServer(key, tonumber(values[key] or 1) + (key == "volume" and 0.1 or 0.25))
		end)
	else
		button(entry.row, "TOGGLE", -10, 88, function()
			request:FireServer(key, not (values[key] == true))
		end)
	end
end

local function isVolumeKey(key: string): boolean
	return key == "volume" or key == "musicVolume" or key == "sfxVolume" or key == "voiceVolume"
end

local function render()
	for key, entry in pairs(rows) do
		local value = values[key]
		if entry.kind == "number" then
			local shown = isVolumeKey(key)
				and string.format("%d%%", math.floor((tonumber(value) or 0) * 100 + 0.5))
				or string.format("%.2fx", tonumber(value) or 1)
			entry.value.Text = shown
			entry.hint.Text = HINTS[key] or ""
		else
			entry.value.Text = value == true and "ON" or "OFF"
			entry.value.TextColor3 = value == true and CYAN or MUTED
			entry.hint.Text = HINTS[key] or ""
		end
	end
end

changed.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) == "table" then
		values = snapshot
		render()
	end
end)

local function setOpen(open)
	isOpen = open
	gui.Enabled = open
	if open then
		request:FireServer("read")
	end
end

-- Open hook for QA and for any station console that wants to expose settings.
workspace:GetAttributeChangedSignal("GF_SettingsOpen"):Connect(function()
	setOpen(workspace:GetAttribute("GF_SettingsOpen") == true)
end)

task.spawn(function()
	while true do
		task.wait(2)
		if gui.Enabled and workspace:GetAttribute("GF_SettingsOpen") ~= true then
			setOpen(false)
		end
	end
end)

request:FireServer("read")
workspace:SetAttribute("GF_SettingsReady", true)
