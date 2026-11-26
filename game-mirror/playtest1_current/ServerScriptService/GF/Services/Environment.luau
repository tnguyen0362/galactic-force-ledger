--!strict
-- Environment: the lighting presets. The station is a dark interior in space (its light must
-- come from fixtures and the windows, not a bright sky) and the mission is a dusty daytime
-- planet. Keeping them as data makes the difference auditable and reversible per zone.
local Lighting = game:GetService("Lighting")

local Environment = {}

type Preset = {
	clock: number,
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	envDiffuse: number,
	envSpecular: number,
	exposure: number,
	fogEnd: number,
	fogColor: Color3,
	atmoDensity: number,
	atmoHaze: number,
	atmoColor: Color3,
	atmoDecay: Color3,
}

local PRESETS: { [string]: Preset } = {
	station = {
		-- 13.5 put the sun low enough to paint the whole deck orange through the glass (V229/V233).
		-- Noon puts it overhead: white light, no colour cast on the deck.
		clock = 12,
		-- V107_01: overexposed white void. V120_01: the blue ambient (120,126,138) plus a blue
		-- atmosphere decay (40,46,60) tinted every ceiling and wall blue, so the hangar read as a
		-- nightclub. Neutral-warm ambient with a grey decay keeps the "lit by fixtures" intent.
		-- 1.30 let the sun beam through the bays and paint the deck orange in waves (V256). The station is
		-- fixture-lit; 0.35 keeps the windows bright and the deck neutral.
		brightness = 0.35,
		-- graphite walls (58,64,72 albedo) at 152 ambient read as near-black in V129_01: at midnight
		-- the fixtures only pool on the deck. Grey ambient lifts the shell without tinting it.
		ambient = Color3.fromRGB(52, 56, 66),
		outdoor = Color3.fromRGB(96, 104, 120),
		envDiffuse = 0.18,
		envSpecular = 0, -- see note below: sky specular on the flat Metal deck produced the orange wash
		exposure = -0.15,
		fogEnd = 24000,
		fogColor = Color3.fromRGB(10, 11, 14),
		atmoDensity = 0.012,
		atmoHaze = 0,
		atmoColor = Color3.fromRGB(196, 197, 199),
		-- Warm atmosphere decay (122,120,116) tinted the whole deck orange at grazing angles. With
		-- every light disabled the deck went black, and zeroing only the decay removed the orange
		-- (capture V217). Cold decay keeps the deck blue-grey.
		atmoDecay = Color3.fromRGB(26, 30, 40),
	},
	mission = {
		-- Spec S27: late afternoon cool-warm light is the default session. 16.8 drops the sun
		-- toward the horizon for longer scenic shadows without going dusk-dark.
		clock = 16.8,
		brightness = 1.9,
		-- character and props read as black silhouettes against the compound deck at 96/92/84
		ambient = Color3.fromRGB(122, 116, 104),
		outdoor = Color3.fromRGB(142, 136, 122),
		envDiffuse = 0.6,
		envSpecular = 0, -- see note below: sky specular on the flat Metal deck produced the orange wash
		exposure = 0.0,
		-- Spec S27 sky: pale blue-green upper atmosphere, lightly dusty cream near the horizon.
		-- Fog carries the cream horizon band; the atmosphere Color/Decay pair tints the dome.
		-- scaled for the 5000-stud baked battlefield: peaks at 2000+ studs must stay visible.
		-- depth softness comes from the atmosphere haze, not a hard fog wall (spec section 18).
		fogEnd = 9000,
		fogColor = Color3.fromRGB(216, 208, 188),
		atmoDensity = 0.3,
		atmoHaze = 1.6,
		atmoColor = Color3.fromRGB(158, 196, 184),
		atmoDecay = Color3.fromRGB(222, 210, 186),
	},
}

-- The station needs stars but part-based stars sit outside streaming range and never reach the
-- client. A Sky with StarCount gives a starfield for free; the station preset swaps in the space
-- skybox, the mission preset restores the default sky.
local SPACE_SKYBOX = {
	SkyboxBk = "rbxassetid://159454299",
	SkyboxDn = "rbxassetid://159454296",
	SkyboxFt = "rbxassetid://159454293",
	SkyboxLf = "rbxassetid://159454286",
	SkyboxRt = "rbxassetid://159454300",
	SkyboxUp = "rbxassetid://159454288",
}

local function ensureSky(): Sky
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
	end
	return sky
end

-- EnvironmentSpecularScale is deliberately 0 in every preset. A/B measured on the concourse deck:
-- spec=0.04, diff=0.18 -> solid orange wash across the whole floor (V354); spec=0, diff=0.18 -> clean
-- navy deck with the same lights and the same camera (V355, V356). This place sits under a saturated
-- orange/magenta nebula sky, and Roblox samples the sky for specular on Metal, so any large flat Metal
-- surface mirrors it at grazing angles. The DiamondPlate ban on the deck was the same problem seen
-- through a different material; this is the root of it.
function Environment.apply(zone: string)
	local p = PRESETS[zone] or PRESETS.mission
	-- Kill the sun for the duration of the swap. Writing ambient/clock/brightness as separate
	-- properties leaves the renderer a frame where the new high sun meets the old warm ambient -
	-- the intermittent orange wash that survived every value change (V271 caught it, V272 did not,
	-- from the same camera angle and identical Lighting values).
	Lighting.Brightness = 0
	-- Ambient first, sun second. The other order leaves a frame or two where a high sun lights the
	-- deck with the previous (warm grey) ambient, which is the intermittent orange wash seen on
	-- arrival and after every teleport (captures V240, V246, V236).
	Lighting.Ambient = p.ambient
	Lighting.OutdoorAmbient = p.outdoor
	Lighting.EnvironmentDiffuseScale = p.envDiffuse
	Lighting.EnvironmentSpecularScale = p.envSpecular
	Lighting.ExposureCompensation = p.exposure
	Lighting.Brightness = p.brightness
	Lighting.ClockTime = p.clock
	Lighting.FogEnd = p.fogEnd
	Lighting.FogColor = p.fogColor
	-- operational circumstances (stage 8): the operation layer publishes its rolled condition;
	-- lighting stays owned here so the ordering rules above keep their invariants.
	if zone == "mission" then
		local circ = workspace:GetAttribute("GF_OpCircumstance")
		if circ == "night_assault" then
			Lighting.ClockTime = 0.5
			Lighting.Ambient = Color3.fromRGB(28, 34, 52)
			Lighting.OutdoorAmbient = Color3.fromRGB(38, 48, 72)
			Lighting.Brightness = 0.6
			Lighting.FogColor = Color3.fromRGB(14, 18, 30)
		elseif circ == "storm" then
			Lighting.FogEnd = 1400
			Lighting.FogColor = Color3.fromRGB(120, 128, 140)
			Lighting.Brightness = math.max(0.8, p.brightness - 1)
			local atmo2 = Lighting:FindFirstChildOfClass("Atmosphere")
			if atmo2 then
				atmo2.Density = 0.55
				atmo2.Haze = 6
			end
		end
	end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		atmo.Density = p.atmoDensity
		atmo.Haze = p.atmoHaze
		atmo.Color = p.atmoColor
		atmo.Decay = p.atmoDecay
		atmo.Glare = 0
	end
	local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = "GFEnvironmentGrade"
		colorCorrection.Parent = Lighting
	end
	if zone == "mission" then
		-- The engine daylight dome is unavoidably saturated blue. Grade it toward the spec's pale
		-- blue-green/cream world instead of fighting per-object colours one at a time.
		colorCorrection.TintColor = Color3.fromRGB(218, 232, 218)
		colorCorrection.Saturation = -0.16
		colorCorrection.Contrast = 0.02
		colorCorrection.Brightness = 0
	else
		colorCorrection.TintColor = Color3.fromRGB(255, 255, 255)
		colorCorrection.Saturation = -0.04
		colorCorrection.Contrast = 0.01
		colorCorrection.Brightness = 0
	end
	local sky = ensureSky()
	if zone == "station" then
		for key, id in SPACE_SKYBOX do
			(sky :: any)[key] = id
		end
		-- 2600 stars read as roughly one dot in a 6-stud-wide window bay (V127_01). The window is
		-- the station's only view of space, so the sky needs density, not a token starfield.
		sky.StarCount = 20000		sky.CelestialBodiesShown = false
	else
		-- Spec S27 overrides the old nebula decision: Veyra-7 is a habitable frontier world with a
		-- pale blue-green sky and dusty cream horizon, not a nebula-veiled void. The violet drift
		-- came from keeping the space skybox planetside; removing the Sky object lets the engine
		-- render its daylight dome, which the blue-green Atmosphere then shifts toward the spec
		-- palette. The original objection ("snow under blue sky", V402) was a TERRAIN tint problem,
		-- fixed below with the spec palette rather than by darkening the sky.
		-- Empty texture strings do NOT clear a skybox: the renderer keeps the last valid texture
		-- and the nebula survived every blanking attempt (probe 2026-11: client bk="" yet nebula
		-- rendered). Destroying the Sky object is the only thing that restores the engine daylight
		-- dome, proven in capture v2026_sky_delete_test. The station branch recreates it on return.
		sky:Destroy()
	end
	-- Terrain palette. Measured at the relay and the beacon: white ground with pale rocks under a
	-- blue sky. Voxel terrain keeps its own material colours, so re-tinting it is the only way the
	-- ground agrees with the sky.
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		if zone == "station" then
			terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(58, 56, 66))
			terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(48, 46, 56))
			terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(64, 60, 70))
		else
			-- Spec S26 palette: sage scrub #7D8C79, shale charcoal #484D51, warm rock #9A8876,
			-- subdued oxidized red #7F5B55. The violet set below was compensating for the nebula
			-- sky; with the planetary sky restored the terrain rejoins the spec.
			terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(112, 122, 104))
			terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(154, 136, 118))
			terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(160, 142, 118))
			terrain:SetMaterialColor(Enum.Material.Snow, Color3.fromRGB(150, 146, 138))
			terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(125, 140, 121))
			terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(118, 134, 114))
			terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(96, 82, 68))
			terrain:SetMaterialColor(Enum.Material.Slate, Color3.fromRGB(72, 77, 81))
			terrain:SetMaterialColor(Enum.Material.Basalt, Color3.fromRGB(62, 66, 70))
			terrain:SetMaterialColor(Enum.Material.CrackedLava, Color3.fromRGB(127, 91, 85))
		end
		workspace:SetAttribute("GF_TerrainTint", zone)
	end
	workspace:SetAttribute("GF_EnvironmentPreset", zone)
	return p
end

return Environment

