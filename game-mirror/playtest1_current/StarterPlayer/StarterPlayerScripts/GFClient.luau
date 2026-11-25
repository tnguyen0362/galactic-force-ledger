--!strict
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent

local Input = require(Client.Input)
local HUD = require(Client.HUD)
local Weapon = require(Client.Weapon)
local Camera = require(Client.CameraCtl)

Input.init()
HUD.init()
Weapon.init()
Camera.init()

UserInputService.LastInputTypeChanged:Connect(function(kind)
	HUD.setDevice(kind)
	Input.setDevice(kind)
end)
HUD.setDevice(UserInputService:GetLastInputType())
Input.setDevice(UserInputService:GetLastInputType())

print("[GF] client online")

