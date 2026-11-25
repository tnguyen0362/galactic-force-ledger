--!strict
-- Controller: the missing control layer.
-- This place has no engine PlayerModule (no ControlModule, no CameraModule), so WASD,
-- mouse-look and jump do not exist unless something provides them. This script provides
-- movement and camera, and binds the input actions that had no listener at all:
-- Jump, Sprint, Dodge, Ability1, Ability2.
--
-- Bindings go through the shared Input module (Input.onPress / onRelease) rather than raw
-- keys, so one code path serves keyboard, gamepad and the HUD's touch layer alike. Fire,
-- Reload, SwapWeapon and Interact already have owners (Weapon, MissionHUD) and are not
-- duplicated here. The server stays authoritative for speed, damage, abilities and hits.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local Input = require(script.Parent:WaitForChild("Input"))

local LOOK_SENS = 0.0026
local PITCH_MIN, PITCH_MAX = math.rad(-72), math.rad(58)
local ZOOM_MIN, ZOOM_MAX = 8, 12
local PAD_LOOK_SPEED = 2.4

local yaw, pitch, zoom = 0, math.rad(-10), 10
local looking = false
local padMove = Vector2.zero
local padLook = Vector2.zero
local touchMove = Vector2.zero
local sprinting = false
local touchMode = UserInputService.TouchEnabled

local humanoid: Humanoid? = nil
local root: BasePart? = nil

local function bindCharacter(character: Model)
	humanoid = character:WaitForChild("Humanoid") :: Humanoid
	root = character:WaitForChild("HumanoidRootPart") :: BasePart
end

if player.Character then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

local function flatForward(): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

local function flatRight(): Vector3
	return Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
end

local function updateCamera()
	local cam = workspace.CurrentCamera
	if not cam or not root then
		return
	end
	-- external camera override: lets the harness and (later) the cinematic take the camera
	-- without the control loop fighting it. Cleared by removing the attributes.
	-- The override must also take the camera TYPE, not just its CFrame. Writing CFrame while the
	-- camera is still Custom lets the built-in camera recompute it later in the frame and win, which
	-- is why every external vantage was silently ignored. Scriptable makes the write authoritative.
	local camPos = workspace:GetAttribute("GF_CamPos")
	local camLook = workspace:GetAttribute("GF_CamLook")
	local photoPos = workspace:GetAttribute("GF_PhotoCam")
	local photoLook = workspace:GetAttribute("GF_PhotoCamLook")
	if typeof(camPos) ~= "Vector3" and typeof(photoPos) == "Vector3" then
		camPos = photoPos
	end
	if typeof(camLook) ~= "Vector3" and typeof(photoLook) == "Vector3" then
		camLook = photoLook
	end
	if typeof(camPos) == "Vector3" and typeof(camLook) == "Vector3" then
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CameraSubject = nil
		end
		cam.CFrame = CFrame.lookAt(camPos, camLook)
		if workspace:GetAttribute("GF_PhotoCamActive") ~= true then
			workspace:SetAttribute("GF_PhotoCamActive", true)
		end
		return
	end
	if cam.CameraType == Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Custom
		cam.CameraSubject = humanoid or cam.CameraSubject
		workspace:SetAttribute("GF_PhotoCamActive", false)
	end
	local focus = root.Position + Vector3.new(0, 1.55, 0)
	local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	cam.CFrame = CFrame.lookAt(focus - rot.LookVector * zoom, focus)
end

local function keyboardMove(): Vector2
	local v = Vector2.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		v += Vector2.new(0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		v += Vector2.new(0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		v += Vector2.new(-1, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		v += Vector2.new(1, 0)
	end
	return v
end

local function setSprint(value: boolean)
	if sprinting == value then
		return
	end
	sprinting = value
	remotes.SprintChanged:FireServer(value)
end

-- Vault/mantle assist (spec S03-017): jumping toward a low obstacle (<=5 studs) with a clear
-- landing tops it smoothly. Detection is two raycasts (waist-height forward, then down onto the
-- obstacle's far side); the boost uses the character's own physics, never a teleport.
local VAULT_MAX_HEIGHT = 5
local VAULT_FORWARD = 4.5
local VAULT_LANDING_DEPTH = 3

local function tryVault()
	if not humanoid or not root then
		return false
	end
	if humanoid:GetState() == Enum.HumanoidStateType.Jumping or humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		return false
	end
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < 0.3 then
		return false
	end
	local flat = Vector3.new(moveDir.X, 0, moveDir.Z).Unit
	local origin = root.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent }
	-- obstacle straight ahead at knee height?
	local hit = workspace:Raycast(origin - Vector3.new(0, 1.5, 0), flat * VAULT_FORWARD, params)
	if not hit then
		return false
	end
	-- how tall is it: probe downward from above the obstacle's far lip
	local lipOrigin = hit.Position + flat * 1.5 + Vector3.new(0, VAULT_MAX_HEIGHT + 1.2, 0)
	local lip = workspace:Raycast(lipOrigin, Vector3.new(0, -(VAULT_MAX_HEIGHT + 2.5), 0), params)
	if not lip then
		return false
	end
	local height = lip.Position.Y - (origin.Y - 3) -- relative to foot level
	if height > VAULT_MAX_HEIGHT or height < 0.8 then
		return false
	end
	-- clear landing beyond the lip?
	local landingOrigin = lip.Position + flat * 1.2 + Vector3.new(0, 0.6, 0)
	local landing = workspace:Raycast(landingOrigin, Vector3.new(0, -VAULT_LANDING_DEPTH, 0), params)
	if not landing then
		return false
	end
	-- mantle: jump plus a forward shove so the arc clears the lip
	humanoid.Jump = true
	task.delay(0.08, function()
		if root and root.Parent then
			root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + flat * 14 + Vector3.new(0, 10, 0)
		end
	end)
	return true
end

local function jump()
	if humanoid and humanoid:GetState() ~= Enum.HumanoidStateType.Jumping then
		if not tryVault() then
			humanoid.Jump = true
		end
	end
end

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

Input.onPress("Jump", function()
	print("[GF] action jump")
	jump()
end)
local function dodge()
	-- the server needs a direction: fall back to camera forward when standing still
	local cam = workspace.CurrentCamera
	local dir = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
	local v = keyboardMove() + padMove + touchMove
	if v.Magnitude > 0.1 then
		dir = flatRight() * v.X + flatForward() * v.Y
	end
	if dir.Magnitude < 0.1 then
		dir = flatForward()
	end
	remotes.RequestDodge:FireServer({ direction = dir.Unit })
end

Input.onPress("Dodge", function()
	print("[GF] action dodge")
	dodge()
end)
Input.onPress("Ability1", function()
	print("[GF] action ability1")
	local slot1 = workspace:GetAttribute("GF_Ability1")
	remotes.UseAbility:FireServer({ abilityId = type(slot1) == "string" and slot1 or "Airstrike", position = aimPoint(220) })
end)
Input.onPress("Ability2", function()
	print("[GF] action ability2")
	local slot2 = workspace:GetAttribute("GF_Ability2")
	remotes.UseAbility:FireServer({ abilityId = type(slot2) == "string" and slot2 or "DomeShield", position = if root then root.Position else aimPoint(24) })
end)
Input.onPress("Sprint", function()
	print("[GF] action sprint-on")
	setSprint(true)
end)
Input.onRelease("Sprint", function()
	setSprint(false)
end)

-- Auto sprint (spec): forward-dominant input at >=0.85 magnitude sprints without a key, unless the
-- player is aiming or firing. Manual sprint input still works; the auto check simply drives the same
-- channel every heartbeat and the aim/fire suppression matches the spec exactly.
game:GetService("RunService").Heartbeat:Connect(function()
	local character = player.Character
	if not character then
		return
	end
	if character:GetAttribute("Aiming") == true or character:GetAttribute("Firing") == true then
		if sprinting then
			setSprint(false)
		end
		return
	end
	local v = keyboardMove() + padMove + touchMove
	local forwardDominant = v.Magnitude >= 0.85 and v.Y > 0 and math.abs(v.Y) >= math.abs(v.X)
	setSprint(forwardDominant)
end)

-- The HUD owns every touch action button; the one control it has no button for is the
-- movement stick, so that is the only UI built here.
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
		touchMove = n * mag
		knob.Position = UDim2.fromOffset(75 - 29 + n.X * mag * 44, 75 - 29 + n.Y * mag * 44)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if held and input.UserInputType == Enum.UserInputType.Touch then
			held = false
			touchMove = Vector2.zero
			knob.Position = UDim2.new(0.5, -29, 0.5, -29)
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		looking = true
		-- RMB is aim-down-sights as well as look; the server owns the speed change.
		remotes.AimChanged:FireServer(true)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and touchMode then
		looking = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		remotes.AimChanged:FireServer(false)
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton1 then
		looking = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if looking then
			-- Settings: sensitivity multiplies mouse look and invertY flips the vertical axis. The profile
			-- stored aimSensitivity and invertY and nothing read them until now.
			local sensitivity = tonumber(player:GetAttribute("GF_Setting_AimSensitivity")) or 1
			local invert = player:GetAttribute("GF_Setting_InvertY") == true and -1 or 1
			yaw -= input.Delta.X * LOOK_SENS * sensitivity
			pitch = math.clamp(pitch - input.Delta.Y * LOOK_SENS * sensitivity * invert, PITCH_MIN, PITCH_MAX)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		zoom = math.clamp(zoom - input.Position.Z, ZOOM_MIN, ZOOM_MAX)
	elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
		padMove = Vector2.new(input.Position.X, input.Position.Y)
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		padLook = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if padLook.Magnitude > 0.08 then
		local sensitivity = tonumber(player:GetAttribute("GF_Setting_AimSensitivity")) or 1
		local invert = player:GetAttribute("GF_Setting_InvertY") == true and -1 or 1
		yaw -= padLook.X * PAD_LOOK_SPEED * sensitivity * dt
		pitch = math.clamp(pitch - padLook.Y * PAD_LOOK_SPEED * sensitivity * invert * dt, PITCH_MIN, PITCH_MAX)
	end
	updateCamera()
	if not humanoid or not root then
		return
	end
	local v = keyboardMove() + padMove + touchMove
	if v.Magnitude > 1 then
		v = v.Unit
	end
	if v.Magnitude > 0.02 then
		humanoid:Move(flatRight() * v.X + flatForward() * v.Y, false)
	else
		humanoid:Move(Vector3.zero, false)
	end
end)

if touchMode then
	buildTouchStick()
end

