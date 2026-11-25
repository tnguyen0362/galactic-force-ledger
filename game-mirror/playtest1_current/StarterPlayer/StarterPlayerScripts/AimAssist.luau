--!strict
-- S04-012 aim assist: on gamepad/touch, the camera experiences friction (slowdown) and moderate
-- attraction toward a visible enemy within 5 degrees and 120 studs. Never active on mouse —
-- PC aim stays raw. Strength is modest so it reads as assistance, not aimbot.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

-- only meaningful without a mouse
local usingGamepad = UserInputService.GamepadEnabled and not UserInputService.MouseEnabled
local usingTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

if usingGamepad or usingTouch then
	local FRICTION_SLOW = 0.45 -- camera input scaled down while on target
	local ATTRACT_STRENGTH = 0.12 -- gentle pull per frame toward the target
	local CONE_DEGREES = 5
	local MAX_RANGE = 120

	local function assistedTarget(): Vector3?
		local camera = workspace.CurrentCamera
		if not camera then return nil end
		local look = camera.CFrame.LookVector
		local best: Vector3? = nil
		local bestAngle = math.rad(CONE_DEGREES)
		local folder = workspace:FindFirstChild("ActiveActors")
		if not folder then return nil end
		for _, model in ipairs(folder:GetChildren()) do
			if model:IsA("Model") and model:GetAttribute("GFEnemy") and not model:GetAttribute("Dead") then
				local root = model.PrimaryPart
				if root then
					local toTarget = root.Position - camera.CFrame.Position
					local dist = toTarget.Magnitude
					if dist <= MAX_RANGE then
						local angle = math.acos(math.clamp(look:Dot(toTarget.Unit), -1, 1))
						if angle < bestAngle then
							-- visibility: no wall between camera and target
							local params = RaycastParams.new()
							params.FilterType = Enum.RaycastFilterType.Exclude
							params.FilterDescendantsInstances = { player.Character, model }
							local hit = workspace:Raycast(camera.CFrame.Position, toTarget, params)
							if not hit then
								bestAngle = angle
								best = root.Position
							end
						end
					end
				end
			end
		end
		return best
	end

	RunService.RenderStepped:Connect(function(dt)
		if not (usingGamepad or usingTouch) then return end
		-- only while aiming down sights or firing — hip aim stays free
		local aiming = workspace:GetAttribute("GF_PlayerAiming") == true
		if not aiming then return end
		local target = assistedTarget()
		if not target then return end
		local camera = workspace.CurrentCamera
		if not camera then return end
		-- attraction: rotate the camera slightly toward the target each frame
		local toTarget = (target - camera.CFrame.Position).Unit
		local currentLook = camera.CFrame.LookVector
		local blend = currentLook:Lerp(toTarget, ATTRACT_STRENGTH * dt * 60)
		if blend.Magnitude > 0.01 then
			camera.CFrame = CFrame.lookAt(camera.CFrame.Position, camera.CFrame.Position + blend.Unit * 10, camera.CFrame.UpVector)
		end
	end)
end
