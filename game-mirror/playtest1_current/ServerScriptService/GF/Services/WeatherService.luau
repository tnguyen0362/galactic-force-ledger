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

-- Relative modifiers applied on top of the BiomeLook baseline (see `base` below). The absolute
-- PROFILES above predate BiomeLook and overwrote it with cold blue-grey outdoor ambient and
-- a 1400-stud fog wall, which is what made every Rain/Overcast mission look icy.
local REL: { [string]: { bright: number, fog: number, fogS: number, dens: number } } = {
	Clear    = { bright = 1.0,  fog = 1.0,  fogS = 1.0, dens = 1.0 },
	Overcast = { bright = 0.82, fog = 0.7,  fogS = 0.8, dens = 1.25 },
	Fog      = { bright = 0.62, fog = 0.14, fogS = 0.1, dens = 1.8 },
	Rain     = { bright = 0.7,  fog = 0.4,  fogS = 0.5, dens = 1.4 },
	Snow     = { bright = 0.9,  fog = 0.25, fogS = 0.3, dens = 1.6 },
	Dust     = { bright = 0.95, fog = 0.2,  fogS = 0.3, dens = 1.7 },
}
local SHADE_MIX = 0.15 -- how far weather nudges the biome's outdoor ambient toward the profile colour

-- biome-appropriate weather tables: each biome weights what fits its climate
local BIOME_WEATHER = {
	Jungle = { "Clear", "Clear", "Overcast", "Rain" },
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

-- Snapshot of the BiomeLook values taken when weather starts; nil when no biome look was applied
-- (legacy absolute profiles then apply unchanged).
local base: { density: number, fogEnd: number, fogStart: number, brightness: number, outdoor: Color3 }? = nil

local function apply()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	local fromP = PROFILES[current]
	local toP = PROFILES[target]
	local t = blend
	if base then
		local f, g = REL[current], REL[target]
		local function mix(k: string): number
			return (f :: any)[k] + ((g :: any)[k] - (f :: any)[k]) * t
		end
		atmosphere.Density = base.density * mix("dens")
		Lighting.FogEnd = base.fogEnd * mix("fog")
		Lighting.FogStart = base.fogStart * mix("fogS")
		Lighting.Brightness = base.brightness * mix("bright")
		Lighting.OutdoorAmbient = lerpColor(base.outdoor, lerpColor(fromP.outdoor, toP.outdoor, t), SHADE_MIX)
		return
	end
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
	local lookAtmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if workspace:GetAttribute("GF_BiomeLook") ~= nil and lookAtmo then
		base = {
			density = lookAtmo.Density,
			fogEnd = Lighting.FogEnd,
			fogStart = Lighting.FogStart,
			brightness = Lighting.Brightness,
			outdoor = Lighting.OutdoorAmbient,
		}
	end
	RunService.Heartbeat:Connect(function(dt)
		if blend < 1 then
			blend = math.min(1, blend + dt / TRANSITION_SECONDS)
			apply()
		end
	end)
	apply()
end

return WeatherService
