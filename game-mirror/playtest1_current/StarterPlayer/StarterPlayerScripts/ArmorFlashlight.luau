--!strict
-- S03-023 armor flashlight: automatic in dark areas — no battery management, no button. The suit
-- reads ambient light and the helmet lamp engages on its own, because a soldier fumbling for a
-- flashlight switch in a firefight is a dead soldier.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local player = Players.LocalPlayer

local DARK_THRESHOLD = 0.35 -- ambient brightness below this triggers the lamp

local flashlight: SpotLight? = nil

local function ensureFlashlight(character: Model)
	if flashlight and flashlight.Parent then return end
	local head = character:WaitForChild("Head", 5)
	if not head then return end
	local light = Instance.new("SpotLight")
	light.Name = "ArmorFlashlight"
	light.Brightness = 3
	light.Range = 30
	light.Angle = 55
	light.Color = Color3.fromRGB(220, 230, 255)
	light.Face = Enum.NormalId.Front
	light.Enabled = false
	light.Parent = head
	flashlight = light
end

if player.Character then
	ensureFlashlight(player.Character)
end
player.CharacterAdded:Connect(ensureFlashlight)

RunService.Heartbeat:Connect(function()
	if not flashlight then return end
	-- dark detection: low ambient or outdoor night lighting reads as darkness
	local ambient = Lighting.Ambient
	local outdoorAmbient = Lighting.OutdoorAmbient
	local brightness = (ambient.R + ambient.G + ambient.B + outdoorAmbient.R + outdoorAmbient.G + outdoorAmbient.B) / 6
	local clockTime = Lighting.ClockTime
	local isNight = clockTime < 6 or clockTime > 18.5
	flashlight.Enabled = isNight or brightness < DARK_THRESHOLD
end)
