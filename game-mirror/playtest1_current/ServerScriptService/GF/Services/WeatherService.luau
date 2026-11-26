--!strict
-- S07-011 weather: clear/overcast/fog/rain/snow/dust selected per biome, with gradual transitions
-- rather than hard swaps. Atmosphere + lighting properties interpolate over the transition window.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local WeatherService = {}

local PROFILES = {
	Clear =    { fogEnd = 100000, fogStart = 4000, density = 0.0, brightness = 3.0, outdoor = Color3.fromRGB(255, 244, 220) },
	Overcast = { fogEnd = 2600,   fogStart = 300,  density = 0.35, brightness = 1.6, outdoor = Color3.fromRGB(200, 205, 215) },
	Fog =      { fogEnd = 320,    fogStart = 12,   density = 0.6,  brightness = 1.1, outdoor = Color3.fromRGB(180, 190, 200) },
	Rain =     { fogEnd = 1400,   fogStart = 120,  density = 0.45, brightness = 1.3, outdoor = Color3.fromRGB(170, 185, 205) },
	Snow =     { fogEnd = 900,    fogStart = 80,   density = 0.5,  brightness = 1.8, outdoor = Color3.fromRGB(225, 230, 240) },
	Dust =     { fogEnd = 700,    fogStart = 60,   density = 0.55, brightness = 1.9, outdoor = Color3.fromRGB(230, 200, 150) },
}

-- biome-appropriate weather tables: each biome weights what fits its climate
local BIOME_WEATHER = {
	Forest = { "Clear", "Overcast", "Fog", "Rain" },
	Arid =   { "Clear", "Dust", "Dust", "Overcast" },
	Tundra = { "Clear", "Snow", "Fog", "Overcast" },
	Volcanic = { "Clear", "Dust", "Fog", "Overcast" },
	Industrial = { "Overcast", "Fog", "Dust", "Clear" },
}

local current = "Clear"
local target = "Clear"
local blend = 1 -- 0..1 progress toward target
local TRANSITION_SECONDS = 20

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function apply()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	local fromP = PROFILES[current]
	local toP = PROFILES[target]
	local t = blend
	atmosphere.Density = fromP.density + (toP.density - fromP.density) * t
	Lighting.FogEnd = fromP.fogEnd + (toP.fogEnd - fromP.fogEnd) * t
	Lighting.FogStart = fromP.fogStart + (toP.fogStart - fromP.fogStart) * t
	Lighting.Brightness = fromP.brightness + (toP.brightness - fromP.brightness) * t
	Lighting.OutdoorAmbient = lerpColor(fromP.outdoor, toP.outdoor, t)
end

function WeatherService.setBiome(biome: string)
	local table_ = BIOME_WEATHER[biome] or BIOME_WEATHER.Forest
	local pick = table_[math.random(1, #table_)]
	if pick ~= target then
		current = target
		target = pick
		blend = 0
	end
	workspace:SetAttribute("GF_Weather", target)
end

function WeatherService.start()
	RunService.Heartbeat:Connect(function(dt)
		if blend < 1 then
			blend = math.min(1, blend + dt / TRANSITION_SECONDS)
			apply()
		end
	end)
	apply()
end

return WeatherService
