--!strict
-- Third-person camera envelope. Over-the-shoulder rig lands in Phase 2 polish.
local Players = game:GetService("Players")

local CameraCtl = {}

-- Contextual camera shake (spec S15-023/S03-041): trauma-based noise decay with distance falloff,
-- fully disabled by the camera-shake setting or reduced motion. Shake is rotational noise layered
-- over the camera CFrame after the engine update, so it never fights player aim permanently.
local trauma = 0

function CameraCtl.shake(intensity: number)
	trauma = math.min(1, trauma + math.max(0, tonumber(intensity) or 0))
end

-- Distance falloff helper: world events report their position, the shake scales down over range.
function CameraCtl.shakeAt(intensity: number, position: Vector3?, fullRange: number?)
	if typeof(position) ~= "Vector3" then
		CameraCtl.shake(intensity)
		return
	end
	local player = Players.LocalPlayer
	local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local dist = (root.Position - position).Magnitude
	local range = tonumber(fullRange) or 60
	if dist >= range then
		return
	end
	CameraCtl.shake(intensity * (1 - dist / range))
end

local function shakeEnabled(): boolean
	local player = Players.LocalPlayer
	if not player then
		return false
	end
	if player:GetAttribute("GF_Setting_CameraShake") == false then
		return false
	end
	if player:GetAttribute("GF_Setting_ReducedMotion") == true then
		return false
	end
	return true
end

function CameraCtl.init()
	local player = Players.LocalPlayer
	player.CameraMode = Enum.CameraMode.Classic
	-- HD2-feel pass (spec S03/S07): the 8-12 stud envelope read as standard Roblox follow-cam,
	-- high and distant. Helldivers sits close over the shoulder: tight envelope, low line,
	-- strong horizontal offset so the soldier occupies the left third of frame.
	player.CameraMinZoomDistance = 4
	player.CameraMaxZoomDistance = 7
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	local RunService = game:GetService("RunService")

	-- ADS camera tightening: while aiming, the camera pulls closer to the shoulder line and the
	-- FOV narrows — the hip-to-aim transition HD2 uses instead of a scope cutaway. Smoothed with
	-- an exponential approach so the transition reads as a settle, not a snap.
	local aimLerp = 0
	RunService.RenderStepped:Connect(function(dt)
		local aiming = workspace:GetAttribute("GF_PlayerAiming") == true
		aimLerp += ((aiming and 1 or 0) - aimLerp) * math.min(1, dt * 10)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			-- hip: strong right offset, slightly low line. ads: closer to bore line, tighter.
			local x = 2.1 - 0.75 * aimLerp
			local y = 0.5 - 0.05 * aimLerp
			hum.CameraOffset = Vector3.new(x, y, 0)
		end
		local camera = workspace.CurrentCamera
		if camera then
			camera.FieldOfView = 70 - 13 * aimLerp
		end
	end)
	local noiseSeed = math.random() * 1000
	RunService.RenderStepped:Connect(function(dt)
		if trauma <= 0 then
			return
		end
		trauma = math.max(0, trauma - dt * 1.6)
		if not shakeEnabled() then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		-- rotational noise: amplitude scales with trauma squared so small hits stay subtle
		local amp = trauma * trauma * 0.035
		local t = os.clock() * 34 + noiseSeed
		local pitch = math.noise(t, 0) * amp
		local yaw = math.noise(0, t) * amp
		camera.CFrame = camera.CFrame * CFrame.Angles(pitch, yaw, 0)
	end)
end

return CameraCtl

