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

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 500, 0, 40)
title.Position = UDim2.new(0.5, -250, 0.42, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.RobotoMono
title.TextSize = 28
title.TextColor3 = Color3.fromRGB(140, 200, 255)
title.Text = "GALACTIC FORCE"
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(0, 400, 0, 20)
status.Position = UDim2.new(0.5, -200, 0.52, 0)
status.BackgroundTransparency = 1
status.Font = Enum.Font.RobotoMono
status.TextSize = 14
status.TextColor3 = Color3.fromRGB(120, 130, 150)
status.Text = "TRANSIT IN PROGRESS"
status.Parent = frame

-- show during teleport transitions; hide once the world is ready
workspace:GetAttributeChangedSignal("GF_Teleporting"):Connect(function()
	frame.Visible = workspace:GetAttribute("GF_Teleporting") == true
end)

-- initial presentation: brief display while first content loads
frame.Visible = true
task.spawn(function()
	-- preload critical assets so the world doesn't pop in piecemeal
	pcall(function()
		ContentProvider:PreloadAsync({ workspace })
	end)
	task.wait(1.5)
	if workspace:GetAttribute("GF_Teleporting") ~= true then
		frame.Visible = false
	end
end)
