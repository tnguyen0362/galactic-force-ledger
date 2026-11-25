--!strict
-- S15-012/013 graphics presets: Low/Balanced/High control presentation cost — shadows, weather
-- density, foliage detail. Gameplay visibility never changes: hitboxes, occlusion and enemy
-- readability stay identical across presets because competitive integrity is not a graphics setting.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local PRESETS = {
	Low = {
		shadows = false,
		weatherDensity = 0.3,
		foliageDetail = 0.4,
		fogEnd = 600,
	},
	Balanced = {
		shadows = true,
		weatherDensity = 0.7,
		foliageDetail = 0.8,
		fogEnd = 900,
	},
	High = {
		shadows = true,
		weatherDensity = 1.0,
		foliageDetail = 1.0,
		fogEnd = 1400,
	},
}

local function applyPreset(name: string)
	local preset = PRESETS[name] or PRESETS.Balanced
	Lighting.GlobalShadows = preset.shadows
	Lighting.FogEnd = preset.fogEnd
	workspace:SetAttribute("GF_WeatherDensity", preset.weatherDensity)
	workspace:SetAttribute("GF_FoliageDetail", preset.foliageDetail)
	workspace:SetAttribute("GF_GraphicsPreset", name)
end

-- default: Balanced — the spec baseline
applyPreset("Balanced")

-- player selection flows through the settings attribute
workspace:GetAttributeChangedSignal("GF_PlayerGraphicsChoice"):Connect(function()
	local choice = workspace:GetAttribute("GF_PlayerGraphicsChoice")
	if type(choice) == "string" and PRESETS[choice] then
		applyPreset(choice)
	end
end)
