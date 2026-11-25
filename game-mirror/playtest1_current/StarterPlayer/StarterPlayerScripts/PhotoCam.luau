--!strict
-- Photo camera: a dev-only viewport control so a frame can be captured from a chosen vantage.
-- The third-person camera will not hold an arbitrary yaw in this place (mouse drags do not rotate it),
-- and every visual row needs an in-frame capture, so the place exposes this instead. It is inert unless
-- workspace.GF_PhotoCam is set, and it always hands control back to the humanoid when cleared.
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function restore()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid
end

workspace:GetAttributeChangedSignal("GF_PhotoCam"):Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local from = workspace:GetAttribute("GF_PhotoCam")
	local to = workspace:GetAttribute("GF_PhotoCamLook")
	if typeof(from) == "CFrame" and typeof(to) == "Vector3" then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(from.Position, to)
		workspace:SetAttribute("GF_PhotoCamActive", true)
	elseif typeof(from) == "Vector3" and typeof(to) == "Vector3" then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(from, to)
		workspace:SetAttribute("GF_PhotoCamActive", true)
	else
		workspace:SetAttribute("GF_PhotoCamActive", false)
		restore()
	end
end)

-- Hold the chosen vantage every frame. A one-shot CFrame write is overwritten by the third-person
-- controller on the next frame, which is why several captures came back from the wrong place.
local RunService = game:GetService("RunService")
-- The vantage is applied by Controller.updateCamera, which owns CameraType. This script only keeps
-- GF_PhotoCam present as an attribute; writing the camera here raced the controller and lost.
return

