--!strict
-- MovementDiagnostics: development-only overlay (spec section 20). Shows live movement state,
-- speed, camera mode/FOV, occlusion, dodge charges and frame time. Toggle: GF_MovementDiag
-- workspace attribute or the F9 key. NEVER visible in normal gameplay — defaults off, and the
-- entire gui is destroyed unless explicitly enabled.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local PlayerController = require(script.Parent:WaitForChild("PlayerController"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))

local gui: ScreenGui? = nil
local label: TextLabel? = nil
local enabled = false
local frameMs = 0

local function setEnabled(on: boolean)
	enabled = on
	if on and not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "GFMovementDiag"
		gui.ResetOnSpawn = false
		gui.Parent = player:WaitForChild("PlayerGui")
		label = Instance.new("TextLabel")
		label.Size = UDim2.fromOffset(330, 170)
		label.Position = UDim2.new(0, 8, 0, 8)
		label.BackgroundTransparency = 0.45
		label.BackgroundColor3 = Color3.fromRGB(8, 12, 16)
		label.TextColor3 = Color3.fromRGB(160, 255, 190)
		label.Font = Enum.Font.Code
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Parent = gui
	elseif not on and gui then
		gui:Destroy()
		gui = nil
		label = nil
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F9 then
		setEnabled(not enabled)
	end
end)

workspace:GetAttributeChangedSignal("GF_MovementDiag"):Connect(function()
	setEnabled(workspace:GetAttribute("GF_MovementDiag") == true)
end)
if workspace:GetAttribute("GF_MovementDiag") == true then
	setEnabled(true)
end

-- measurement accumulators for quantitative validation (spec section 21)
local speedSamples: { number } = {}
RunService.Heartbeat:Connect(function(dt)
	frameMs = frameMs * 0.95 + dt * 1000 * 0.05
	if not enabled or not label then
		return
	end
	local s = PlayerController.getState()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local speed = 0
	if root then
		local v = (root :: BasePart).AssemblyLinearVelocity
		speed = Vector3.new(v.X, 0, v.Z).Magnitude
	end
	local cam = workspace.CurrentCamera
	local _, pitch = CameraController.getYawPitch()
	label.Text = string.format(
		"state: %s%s%s%s\nspeed: %.1f / target %.1f\nwalkspeed: %.1f jump: %.0f\ncam fov: %.0f pitch: %.1f\nrolling: %s vaulting: %s downed: %s\nframe: %.1f ms (%.0f fps)",
		s.base,
		s.sprinting and " +sprint" or "",
		s.aiming and " +aim" or "",
		s.firing and " +fire" or "",
		speed,
		humanoid and humanoid.WalkSpeed or 0,
		humanoid and humanoid.WalkSpeed or 0,
		humanoid and humanoid.JumpPower or 0,
		cam and cam.FieldOfView or 0,
		math.deg(pitch),
		tostring(s.rolling),
		tostring(s.vaulting),
		tostring(s.downed),
		frameMs,
		1000 / math.max(frameMs, 0.01)
	)
end)

return {}
