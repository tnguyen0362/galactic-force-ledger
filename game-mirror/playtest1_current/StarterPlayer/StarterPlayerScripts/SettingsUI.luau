--!strict
-- Settings: sensitivity, subtitles, reduced motion and master volume. Values live in the profile (server
-- authoritative) and are mirrored onto player attributes, which is what the camera, captions and audio read.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local request = remotes:WaitForChild("RequestSettings")
local changed = remotes:WaitForChild("SettingsChanged")

local INK = Color3.fromRGB(10, 14, 20)
local PANEL = Color3.fromRGB(22, 30, 40)
local ROW = Color3.fromRGB(28, 38, 50)
local CYAN = Color3.fromRGB(120, 210, 255)
local WHITE = Color3.fromRGB(232, 240, 248)
local MUTED = Color3.fromRGB(130, 148, 168)

local values = {}
local isOpen = false

local gui = Instance.new("ScreenGui")
gui.Name = "GF_Settings"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(460, 300)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = PANEL
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 6); corner.Parent = panel
local stroke = Instance.new("UIStroke"); stroke.Color = CYAN; stroke.Transparency = 0.5; stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 28)
title.Position = UDim2.fromOffset(12, 10)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = WHITE
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "SETTINGS"
title.Parent = panel

local rows = {}
local function addRow(order, key, label, kind)
	local row = Instance.new("Frame")
	row.Size = UDim2.fromOffset(436, 48)
	row.Position = UDim2.fromOffset(12, 44 + (order - 1) * 52)
	row.BackgroundColor3 = ROW
	row.BorderSizePixel = 0
	row.Parent = panel
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 4); rc.Parent = row
	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromOffset(240, 18)
	name.Position = UDim2.fromOffset(12, 6)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 14
	name.TextColor3 = WHITE
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = label
	name.Parent = row
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.fromOffset(240, 16)
	hint.Position = UDim2.fromOffset(12, 24)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextColor3 = MUTED
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Parent = row
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.fromOffset(110, 22)
	valueLabel.Position = UDim2.fromOffset(250, 13)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 14
	valueLabel.TextColor3 = CYAN
	valueLabel.Parent = row
	rows[key] = { row = row, value = valueLabel, hint = hint, kind = kind }
	return row
end

local function button(parent, text, x, onClick)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(34, 24)
	b.Position = UDim2.fromOffset(x, 12)
	b.BackgroundColor3 = Color3.fromRGB(40, 54, 70)
	b.Text = text
	b.TextColor3 = WHITE
	b.TextSize = 14
	b.Font = Enum.Font.GothamBold
	b.BorderSizePixel = 0
	b.Parent = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 3); c.Parent = b
	b.MouseButton1Click:Connect(onClick)
	return b
end

addRow(1, "aimSensitivity", "Aim sensitivity", "number")
addRow(2, "volume", "Master volume", "number")
addRow(3, "subtitles", "Subtitles", "boolean")
addRow(4, "reducedMotion", "Reduced motion", "boolean")
addRow(5, "musicVolume", "Music volume", "number")
addRow(6, "sfxVolume", "SFX volume", "number")
addRow(7, "voiceVolume", "Voice volume", "number")
addRow(8, "cameraShake", "Camera shake", "boolean")
addRow(9, "damageNumbers", "Damage numbers", "boolean")

for key, entry in pairs(rows) do
	if entry.kind == "number" then
		button(entry.row, "-", 366, function()
			request:FireServer(key, tonumber(values[key] or 1) - (key == "volume" and 0.1 or 0.25))
		end)
		button(entry.row, "+", 402, function()
			request:FireServer(key, tonumber(values[key] or 1) + (key == "volume" and 0.1 or 0.25))
		end)
	else
		local toggle = button(entry.row, "TOGGLE", 366, function()
			request:FireServer(key, not (values[key] == true))
		end)
		toggle.Size = UDim2.fromOffset(64, 24)
	end
end

local function render()
	for key, entry in pairs(rows) do
		local value = values[key]
		if entry.kind == "number" then
			local shown = key == "volume" and string.format("%d%%", math.floor((tonumber(value) or 0) * 100 + 0.5)) or string.format("%.2fx", tonumber(value) or 1)
			entry.value.Text = shown
			entry.hint.Text = key == "volume" and "UI and world audio" or "Mouse / stick look speed"
		else
			entry.value.Text = value == true and "ON" or "OFF"
			entry.value.TextColor3 = value == true and CYAN or MUTED
			entry.hint.Text = key == "subtitles" and "Mission and cinematic captions" or "Skip camera motion and flashes"
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

