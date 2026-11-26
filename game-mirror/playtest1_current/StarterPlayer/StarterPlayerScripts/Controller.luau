--!strict
-- Controller: gameplay input bindings + UI gating. Movement and camera live in
-- PlayerController/CameraController (started by CameraCtl.init shim); this script keeps
-- the non-movement glue: ability inputs, UI-open mouse behavior, and the touch stick.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local Input = require(script.Parent:WaitForChild("Input"))
local PlayerController = require(script.Parent:WaitForChild("PlayerController"))

local touchMode = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ---------------------------------------------------------------------------
-- ability inputs (unchanged semantics)
-- ---------------------------------------------------------------------------
local function aimPoint(range: number): Vector3
	local cam = workspace.CurrentCamera
	local origin = cam.CFrame.Position
	local dir = cam.CFrame.LookVector
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = { player.Character }
	end
	local hit = workspace:Raycast(origin, dir * range, params)
	return if hit then hit.Position else origin + dir * range
end

-- ability slots are per-player attributes (workspace globals were shared across the whole
-- session — one player's armory visit overwrote everyone's bindings). Workspace fallback covers
-- the transition window before ArmoryService writes the player attributes.
local function abilitySlot(index: number): string
	local perPlayer = player:GetAttribute("GF_Ability" .. index)
	if type(perPlayer) == "string" then
		return perPlayer
	end
	local shared = workspace:GetAttribute("GF_Ability" .. index)
	if type(shared) == "string" then
		return shared
	end
	return index == 1 and "Airstrike" or "DomeShield"
end

-- the throw target depends on the ability's configured targeting, not on which slot it sits in:
-- Ground abilities land at the aim point, Self abilities center on the caster.
local function abilityTarget(abilityId: string): Vector3
	local Abilities = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Abilities)
	local def = Abilities.get and Abilities.get(abilityId) or nil
	if def and def.targeting == "Self" then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			return root.Position
		end
	end
	return aimPoint(220)
end

Input.onPress("Ability1", function()
	local id = abilitySlot(1)
	remotes.UseAbility:FireServer({ abilityId = id, position = abilityTarget(id) })
end)
Input.onPress("Ability2", function()
	local id = abilitySlot(2)
	remotes.UseAbility:FireServer({ abilityId = id, position = abilityTarget(id) })
end)

-- shoulder swap intentionally removed: spec fixes the camera on the right shoulder.

-- ---------------------------------------------------------------------------
-- UI-open gating: visible cursor means menus own input; gameplay input is suppressed
-- ---------------------------------------------------------------------------
local function interactiveUiOpen(): boolean
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return false
	end
	local station = playerGui:FindFirstChild("GFStation")
	local stationPanel = station and station:FindFirstChildWhichIsA("Frame")
	if stationPanel and stationPanel.Visible then
		return true
	end
	local debrief = playerGui:FindFirstChild("GFDebrief")
	local debriefPanel = debrief and debrief:FindFirstChildWhichIsA("Frame")
	if debriefPanel and debriefPanel.Visible then
		return true
	end
	local armory = playerGui:FindFirstChild("GF_Armory")
	local armoryPanel = armory and armory:FindFirstChild("Panel")
	if armoryPanel and armoryPanel.Visible then
		return true
	end
	local settings = playerGui:FindFirstChild("GF_Settings")
	if settings and settings.Enabled then
		return true
	end
	local tactical = playerGui:FindFirstChild("TacticalMap")
	if tactical and tactical.Enabled then
		return true
	end
	return false
end

task.spawn(function()
	local last = nil
	while true do
		task.wait(0.15)
		local open = interactiveUiOpen()
		if open ~= last then
			last = open
			workspace:SetAttribute("GF_UIOpen", open)
			UserInputService.MouseBehavior = open and Enum.MouseBehavior.Default or Enum.MouseBehavior.LockCurrentPosition
		end
	end
end)

-- ---------------------------------------------------------------------------
-- touch movement stick: the one piece of touch UI owned here; feeds PlayerController
-- ---------------------------------------------------------------------------
local function buildTouchStick()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GFControllerStick"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local base = Instance.new("Frame")
	base.Name = "Stick"
	base.Size = UDim2.fromOffset(150, 150)
	base.Position = UDim2.new(0, 28, 1, -178)
	base.BackgroundColor3 = Color3.fromRGB(18, 28, 38)
	base.BackgroundTransparency = 0.55
	base.BorderSizePixel = 0
	base.Parent = gui
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = base

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(58, 58)
	knob.Position = UDim2.new(0.5, -29, 0.5, -29)
	knob.BackgroundColor3 = Color3.fromRGB(120, 200, 240)
	knob.BackgroundTransparency = 0.25
	knob.BorderSizePixel = 0
	knob.Parent = base
	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(1, 0)
	kc.Parent = knob

	local centre = Vector2.zero
	local held = false
	base.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			held = true
			centre = Vector2.new(base.AbsolutePosition.X + base.AbsoluteSize.X / 2, base.AbsolutePosition.Y + base.AbsoluteSize.Y / 2)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not held or input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local d = Vector2.new(input.Position.X, input.Position.Y) - centre
		local mag = math.min(1, d.Magnitude / 55)
		local n = if d.Magnitude > 0.01 then d.Unit else Vector2.zero
		PlayerController.setTouchMove(n * mag)
		knob.Position = UDim2.fromOffset(75 - 29 + n.X * mag * 44, 75 - 29 + n.Y * mag * 44)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if held and input.UserInputType == Enum.UserInputType.Touch then
			held = false
			PlayerController.setTouchMove(Vector2.zero)
			knob.Position = UDim2.new(0.5, -29, 0.5, -29)
		end
	end)
end

if touchMode then
	buildTouchStick()
end
