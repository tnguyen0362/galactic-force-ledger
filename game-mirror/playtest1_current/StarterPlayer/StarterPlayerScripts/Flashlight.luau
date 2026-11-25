--!strict
-- S03-023: automatic armor flashlight in dark areas. No battery, no button - visibility is a readability
-- requirement, not a resource minigame. A chest-mounted point light plus a soft forward spot.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local light: PointLight? = nil
local spot: SurfaceLight? = nil

local DARK_AMBIENT_LUMA = 0.35
local CHECK_INTERVAL = 0.5

local function luma(color: Color3): number
	return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

local function isDark(): boolean
	-- Outdoor nighttime or shadowed interiors read as low ambient; clocktime alone misses interiors.
	local ambientLuma = luma(Lighting.Ambient) + luma(Lighting.OutdoorAmbient)
	local brightnessScale = math.clamp((Lighting.Brightness - 1) / 3, 0, 1)
	return (ambientLuma * 0.5 + brightnessScale * 0.5) < DARK_AMBIENT_LUMA
end

local function ensureLights(character: Model)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
	if not torso then
		return
	end
	if not light or not light.Parent then
		local pt = Instance.new("PointLight")
		pt.Name = "ArmorFlashlight"
		pt.Range = 26
		pt.Brightness = 1.6
		pt.Color = Color3.fromRGB(255, 244, 220)
		pt.Shadows = false
		pt.Enabled = false
		pt.Parent = torso
		light = pt
	end
end

local function stripLights(character: Model)
	local existing = character:FindFirstChildWhichIsA("PointLight", true)
	if existing and existing.Name == "ArmorFlashlight" then
		existing:Destroy()
	end
	light = nil
end

local function onCharacter(character: Model)
	task.wait(1)
	ensureLights(character)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < CHECK_INTERVAL then
		return
	end
	elapsed = 0
	local character = player.Character
	if not character then
		return
	end
	if not light or not light.Parent then
		ensureLights(character)
	end
	if light and light.Parent then
		light.Enabled = isDark()
	end
end)
