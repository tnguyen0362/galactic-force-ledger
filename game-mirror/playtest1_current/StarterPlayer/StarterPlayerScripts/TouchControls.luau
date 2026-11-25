--!strict
-- S03-007 touch controls: left half drag = movement stick, right half drag = camera, large buttons
-- for fire/reload/dodge/jump/interact. >=44 logical px targets, no overlapping core actions.
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

if not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled then
	return -- real keyboard+mouse present: touch UI stays hidden
end

local gui = Instance.new("ScreenGui")
gui.Name = "TouchControls"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function mkButton(label: string, x: number, y: number, size: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, size, 0, size)
	b.Position = UDim2.new(1, -x, 1, -y)
	b.BackgroundColor3 = Color3.fromRGB(20, 26, 32)
	b.BackgroundTransparency = 0.35
	b.TextColor3 = Color3.fromRGB(230, 236, 240)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.Text = label
	b.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = b
	return b
end

-- large action buttons (>=56px — over the 44px floor)
local fire = mkButton("FIRE", 90, 170, 64)
local reload = mkButton("R", 165, 110, 52)
local dodge = mkButton("DODGE", 90, 90, 52)
local jump = mkButton("JUMP", 165, 190, 52)
local interact = mkButton("USE", 240, 140, 52)

-- wire buttons into the semantic input layer by firing the same virtual inputs other scripts read
local VirtualInputManager = game:GetService("VirtualInputManager")
local function bindKey(button: TextButton, key: Enum.KeyCode)
	button.InputBegan:Connect(function()
		VirtualInputManager:SendKeyEvent(true, key, false, game)
	end)
	button.InputEnded:Connect(function()
		VirtualInputManager:SendKeyEvent(false, key, false, game)
	end)
end
bindKey(reload, Enum.KeyCode.R)
bindKey(dodge, Enum.KeyCode.LeftControl)
bindKey(jump, Enum.KeyCode.Space)
bindKey(interact, Enum.KeyCode.E)
fire.InputBegan:Connect(function()
	VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
end)
fire.InputEnded:Connect(function()
	VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
end)

-- camera drag on the right half of the screen
UserInputService.TouchMoved:Connect(function(touch, processed)
	if processed then return end
	local pos = touch.Position
	if pos.X > workspace.CurrentCamera.ViewportSize.X * 0.45 then
		local camera = workspace.CurrentCamera
		if camera then
			local delta = touch.Delta
			camera.CFrame = camera.CFrame * CFrame.Angles(0, -delta.X * 0.005, 0) * CFrame.Angles(-delta.Y * 0.005, 0, 0)
		end
	end
end)
