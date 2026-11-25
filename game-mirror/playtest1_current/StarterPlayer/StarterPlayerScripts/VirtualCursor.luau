--!strict
-- S03-009/010/012 controller virtual cursor: when a UI opens on gamepad, a free-moving cursor appears
-- and the right stick moves it smoothly — never snap-between-buttons navigation. Closing the last UI
-- restores camera control and hides the cursor.
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

if not UserInputService.GamepadEnabled or UserInputService.KeyboardEnabled then
	return -- kbm present: real mouse cursor already exists
end

local gui = Instance.new("ScreenGui")
gui.Name = "VirtualCursor"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local cursor = Instance.new("ImageLabel")
cursor.Size = UDim2.new(0, 24, 0, 24)
cursor.BackgroundTransparency = 1
cursor.Image = "rbxasset://textures/ArrowCursor.png"
cursor.Visible = false
cursor.ZIndex = 100
cursor.Parent = gui

local pos = Vector2.new(0.5, 0.5)
local active = false
local VirtualInputManager = game:GetService("VirtualInputManager")

local function setActive(on: boolean)
	active = on
	cursor.Visible = on
	workspace:SetAttribute("GF_VirtualCursor", on and 1 or 0)
end

-- a UI is "open" when the game already gates input for station/mission panels
task.spawn(function()
	while true do
		task.wait(0.25)
		local uiOpen = workspace:GetAttribute("GF_UIOpen") == true or workspace:GetAttribute("StationUIOpen") == true
		if uiOpen and not active then
			setActive(true)
		elseif not uiOpen and active then
			setActive(false)
		end
	end
end)

-- right stick drives the cursor smoothly; thumbpress/A clicks at the cursor position
RunService.RenderStepped:Connect(function(dt)
	if not active then return end
	local state = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
	for _, input in ipairs(state) do
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			pos += Vector2.new(input.Position.X, -input.Position.Y) * dt * 0.9
			pos = Vector2.new(math.clamp(pos.X, 0, 1), math.clamp(pos.Y, 0, 1))
		end
	end
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
	cursor.Position = UDim2.new(pos.X, -12, pos.Y, -12)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not active then return end
	if input.KeyCode == Enum.KeyCode.ButtonA then
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
		local x, y = pos.X * vp.X, pos.Y * vp.Y
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
		task.delay(0.05, function()
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
		end)
	end
end)
