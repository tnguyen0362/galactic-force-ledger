--!strict
-- S02-054 cross-place loading: consistent custom presentation across every teleport — the same
-- GF-branded screen whether heading to the station or the surface. Content preloads during the
-- screen so arrival never hitches on missing assets.
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "GFLoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = gui

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 10, 16)),
	ColorSequenceKeypoint.new(0.62, Color3.fromRGB(14, 18, 28)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 42, 54)),
})
gradient.Rotation = 90
gradient.Parent = frame

local function line(y: number, transparency: number)
	local l = Instance.new("Frame")
	l.BorderSizePixel = 0
	l.BackgroundColor3 = Color3.fromRGB(96, 200, 255)
	l.BackgroundTransparency = transparency
	l.Size = UDim2.new(0.42, 0, 0, 2)
	l.Position = UDim2.new(0.29, 0, y, 0)
	l.Parent = frame
end
line(0.37, 0.25)
line(0.68, 0.55)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 620, 0, 40)
title.Position = UDim2.new(0.5, -310, 0.405, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.RobotoMono
title.TextSize = 28
title.TextColor3 = Color3.fromRGB(140, 210, 255)
title.Text = "GALACTIC FORCE // COUNTEROFFENSIVE"
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(0, 460, 0, 22)
status.Position = UDim2.new(0.5, -230, 0.49, 0)
status.BackgroundTransparency = 1
status.Font = Enum.Font.RobotoMono
status.TextSize = 14
status.TextColor3 = Color3.fromRGB(160, 176, 196)
status.Text = "ESTABLISHING COMMAND LINK"
status.Parent = frame

local progressBack = Instance.new("Frame")
progressBack.BorderSizePixel = 0
progressBack.BackgroundColor3 = Color3.fromRGB(24, 34, 46)
progressBack.Size = UDim2.new(0, 360, 0, 5)
progressBack.Position = UDim2.new(0.5, -180, 0.565, 0)
progressBack.Parent = frame
local progressFill = Instance.new("Frame")
progressFill.BorderSizePixel = 0
progressFill.BackgroundColor3 = Color3.fromRGB(96, 210, 255)
progressFill.Size = UDim2.new(0.12, 0, 1, 0)
progressFill.Parent = progressBack

local spinner = Instance.new("TextLabel")
spinner.Size = UDim2.new(0, 60, 0, 34)
spinner.Position = UDim2.new(0.5, -30, 0.605, 0)
spinner.BackgroundTransparency = 1
spinner.Font = Enum.Font.RobotoMono
spinner.TextSize = 24
spinner.TextColor3 = Color3.fromRGB(96, 210, 255)
spinner.Text = "◢"
spinner.Parent = frame

local tip = Instance.new("TextLabel")
tip.Size = UDim2.new(0, 620, 0, 18)
tip.Position = UDim2.new(0.5, -310, 0.72, 0)
tip.BackgroundTransparency = 1
tip.Font = Enum.Font.RobotoMono
tip.TextSize = 12
tip.TextColor3 = Color3.fromRGB(110, 126, 146)
tip.Text = "SQUAD TIP: RESUPPLY CRATES RESTORE AMMUNITION AND GRENADES"
tip.Parent = frame

-- show during teleport transitions; hide once the world is ready
local function refreshStatus()
	if workspace:GetAttribute("GF_Teleporting") ~= true then
		status.Text = "ESTABLISHING COMMAND LINK"
	elseif workspace:GetAttribute("GF_InMission") == true then
		status.Text = "DEPLOYING TO VEYRA-7  //  ORBITAL INSERTION"
	else
		status.Text = "RETURNING TO ORBITAL STATION"
	end
end
workspace:GetAttributeChangedSignal("GF_Teleporting"):Connect(function()
	frame.Visible = workspace:GetAttribute("GF_Teleporting") == true
	refreshStatus()
end)
workspace:GetAttributeChangedSignal("GF_InMission"):Connect(refreshStatus)
task.spawn(function()
	local glyphs = { "◢", "◣", "◤", "◥" }
	local index = 1
	while gui.Parent do
		if frame.Visible then
			spinner.Text = glyphs[index]
			index = index % #glyphs + 1
			local phase = (os.clock() % 1.4) / 1.4
			progressFill.Position = UDim2.new(phase * 0.88, 0, 0, 0)
		end
		task.wait(0.12)
	end
end)

-- initial presentation: brief display while first content loads
frame.Visible = true
task.spawn(function()
	task.wait(0.8)
	if workspace:GetAttribute("GF_Teleporting") ~= true then
		frame.Visible = false
	end
end)
