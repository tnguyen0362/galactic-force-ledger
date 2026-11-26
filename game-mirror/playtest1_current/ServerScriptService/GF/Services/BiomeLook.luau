--!strict
-- BiomeLook (Phase 15 art): per-biome cinematic lighting, atmosphere, grade and terrain palette.
-- Data only + one apply function. Environment.apply("mission") calls BiomeLook.overlay(preset)
-- AFTER the base mission preset, so the biome look is the last writer at deploy.
-- Gameplay-neutral: touches Lighting, Atmosphere, ColorCorrection and Terrain colours only.
-- Hard rules kept from Environment.luau: EnvironmentSpecularScale stays 0 (sky-specular orange wash,
-- V354-V356) and brightness is written after ambient (arrival wash, V240-V272).
-- Approved biomes (Phase 15): Forest, Tundra (mountain/frozen), Arid, Industrial.
-- Volcanic is legacy/unapproved: kept as data so nothing errors, but not in the mission rotation.

local Lighting = game:GetService("Lighting")

local BiomeLook = {}

export type Look = {
	clock: number,
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	envDiffuse: number,
	exposure: number,
	fogStart: number,
	fogEnd: number,
	fogColor: Color3,
	atmoDensity: number,
	atmoHaze: number,
	atmoColor: Color3,
	atmoDecay: Color3,
	gradeTint: Color3,
	gradeSat: number,
	gradeContrast: number,
	bloomIntensity: number,
	terrain: { [string]: Color3 },
}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

BiomeLook.LOOKS = {
	-- Dense verdant basin: low warm sun through humid haze, deep green shadow, lifted saturation.
	Forest = {
		clock = 16.2, brightness = 2.1,
		ambient = c(92, 110, 98), outdoor = c(126, 140, 122), envDiffuse = 0.6, exposure = 0,
		fogStart = 200, fogEnd = 5200, fogColor = c(176, 196, 184),
		atmoDensity = 0.34, atmoHaze = 1.9, atmoColor = c(150, 190, 176), atmoDecay = c(214, 196, 160),
		gradeTint = c(232, 242, 222), gradeSat = 0.06, gradeContrast = 0.06, bloomIntensity = 0.25,
		terrain = {
			Grass = c(84, 118, 70), LeafyGrass = c(66, 102, 62), Ground = c(88, 78, 60),
			Mud = c(70, 58, 44), Rock = c(112, 106, 96), Slate = c(70, 76, 78), Sand = c(150, 138, 108),
		},
	},
	-- Mountain / frozen: cold clear air, blue shadow, bright snow with a pale blue-white haze.
	Tundra = {
		clock = 14.5, brightness = 2.0,
		ambient = c(116, 130, 148), outdoor = c(150, 164, 184), envDiffuse = 0.62, exposure = 0,
		fogStart = 300, fogEnd = 4200, fogColor = c(208, 220, 232),
		atmoDensity = 0.38, atmoHaze = 1.4, atmoColor = c(176, 200, 224), atmoDecay = c(230, 226, 220),
		gradeTint = c(230, 240, 252), gradeSat = -0.08, gradeContrast = 0.05, bloomIntensity = 0.3,
		terrain = {
			Snow = c(226, 232, 240), Glacier = c(170, 200, 222), Ice = c(150, 190, 215),
			Ground = c(110, 114, 118), Rock = c(120, 124, 132), Slate = c(78, 84, 92), Basalt = c(60, 64, 72),
			Grass = c(120, 134, 124), LeafyGrass = c(104, 124, 112), Mud = c(92, 90, 88), Sand = c(170, 168, 160),
		},
	},
	-- Arid highlands: hot amber light, long dust haze, warm sandstone strata.
	Arid = {
		clock = 15.2, brightness = 2.3,
		ambient = c(140, 118, 92), outdoor = c(172, 146, 112), envDiffuse = 0.58, exposure = 0,
		fogStart = 250, fogEnd = 6500, fogColor = c(226, 196, 156),
		atmoDensity = 0.30, atmoHaze = 2.4, atmoColor = c(214, 170, 120), atmoDecay = c(236, 196, 140),
		gradeTint = c(255, 238, 214), gradeSat = 0.04, gradeContrast = 0.08, bloomIntensity = 0.28,
		terrain = {
			Sand = c(196, 158, 112), Sandstone = c(176, 124, 86), Rock = c(150, 116, 88),
			Ground = c(150, 122, 92), Mud = c(110, 82, 60), Slate = c(98, 80, 66), Basalt = c(72, 62, 56),
			Grass = c(142, 134, 90), LeafyGrass = c(124, 120, 80), Snow = c(210, 200, 186),
		},
	},
	-- Industrial wasteland: low heavy smog, desaturated slate and rust, harder contrast.
	Industrial = {
		clock = 15.6, brightness = 2.1,
		ambient = c(126, 124, 124), outdoor = c(146, 140, 134), envDiffuse = 0.58, exposure = 0.2,
		fogStart = 150, fogEnd = 3800, fogColor = c(158, 150, 142),
		atmoDensity = 0.34, atmoHaze = 2.0, atmoColor = c(142, 138, 132), atmoDecay = c(190, 150, 110),
		gradeTint = c(240, 232, 224), gradeSat = -0.18, gradeContrast = 0.10, bloomIntensity = 0.2,
		terrain = {
			Ground = c(92, 88, 84), Slate = c(66, 68, 70), Basalt = c(58, 58, 60), Rock = c(104, 98, 92),
			Mud = c(86, 72, 60), Sand = c(128, 112, 94), CrackedLava = c(127, 91, 85),
			Grass = c(104, 108, 88), LeafyGrass = c(92, 98, 80), Snow = c(176, 172, 166),
		},
	},
	-- Legacy, not approved for Phase 15 and not in the rotation.
	Volcanic = {
		clock = 17.0, brightness = 1.7,
		ambient = c(104, 92, 90), outdoor = c(128, 108, 100), envDiffuse = 0.55, exposure = 0,
		fogStart = 150, fogEnd = 3800, fogColor = c(120, 100, 94),
		atmoDensity = 0.4, atmoHaze = 2.6, atmoColor = c(150, 120, 110), atmoDecay = c(200, 130, 90),
		gradeTint = c(244, 230, 222), gradeSat = -0.08, gradeContrast = 0.09, bloomIntensity = 0.25,
		terrain = { Basalt = c(55, 50, 52), Rock = c(80, 70, 66), Ground = c(70, 60, 58), CrackedLava = c(180, 80, 50) },
	},
} :: { [string]: Look }

function BiomeLook.current(): string
	local b = workspace:GetAttribute("GF_Biome")
	return (typeof(b) == "string" and BiomeLook.LOOKS[b]) and b or "Forest"
end

-- Writes the look. Ambient first, brightness second (see header). Returns the look applied.
function BiomeLook.apply(biome: string?): Look
	local name = biome or BiomeLook.current()
	local l = BiomeLook.LOOKS[name] or BiomeLook.LOOKS.Forest

	Lighting.Brightness = 0
	Lighting.Ambient = l.ambient
	Lighting.OutdoorAmbient = l.outdoor
	Lighting.EnvironmentDiffuseScale = l.envDiffuse
	Lighting.EnvironmentSpecularScale = 0
	Lighting.ExposureCompensation = l.exposure
	Lighting.Brightness = l.brightness
	Lighting.ClockTime = l.clock
	Lighting.FogStart = l.fogStart
	Lighting.FogEnd = l.fogEnd
	Lighting.FogColor = l.fogColor

	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		atmo.Density = l.atmoDensity
		atmo.Haze = l.atmoHaze
		atmo.Color = l.atmoColor
		atmo.Decay = l.atmoDecay
		atmo.Glare = 0
	end

	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc then
		cc.TintColor = l.gradeTint
		cc.Saturation = l.gradeSat
		cc.Contrast = l.gradeContrast
		cc.Brightness = 0
	end

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = l.bloomIntensity
	end

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		for matName, color in l.terrain do
			local mat = (Enum.Material :: any)[matName]
			if mat then
				terrain:SetMaterialColor(mat, color)
			end
		end
	end

	workspace:SetAttribute("GF_BiomeLook", name)
	return l
end

return BiomeLook
