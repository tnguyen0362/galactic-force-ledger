--!strict
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent

local Input = require(Client:WaitForChild("Input"))
local HUD = require(Client:WaitForChild("HUD"))
local Weapon = require(Client:WaitForChild("Weapon"))
local Camera = require(Client:WaitForChild("CameraCtl"))

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

