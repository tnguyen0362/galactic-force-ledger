--!strict
-- CameraCtl: compatibility shim. Historically this module owned the camera (and fought
-- three other writers for it). The authoritative implementation is now CameraController +
-- PlayerController; this shim exists so existing callers (Weapon, VFX, abilities) keep
-- working unchanged: CameraCtl.shake/shakeAt forward into the new feel layer, and init
-- boots the two authoritative controllers exactly once.
local Players = game:GetService("Players")

local CameraController = require(script.Parent.CameraController)
local PlayerController = require(script.Parent.PlayerController)

local CameraCtl = {}

function CameraCtl.shake(intensity: number)
	CameraController.shake(intensity)
end

function CameraCtl.shakeAt(intensity: number, position: Vector3?, fullRange: number?)
	CameraController.shakeAt(intensity, position, fullRange)
end

function CameraCtl.recoil(vertical: number, horizontal: number)
	CameraController.recoil(vertical, horizontal)
end

function CameraCtl.init()
	local player = Players.LocalPlayer
	-- no free zoom into first person: per-mode distances govern the camera envelope
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = 5
	player.CameraMaxZoomDistance = 10
	-- wire the cross-module providers, then start both controllers (order matters:
	-- the camera needs the movement state feed before its first frame)
	PlayerController.setCameraYawProvider(function()
		local yaw, _ = CameraController.getYawPitch()
		return yaw
	end)
	CameraController.setMoveStateProvider(function()
		return PlayerController.getState()
	end)
	PlayerController.start()
	CameraController.start()
end

return CameraCtl
