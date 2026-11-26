--!strict
-- Archetypes: data-driven definitions of the six battlefield geographical archetypes.
-- Everything tuneable about an archetype lives here as data — MacroGeography interprets the
-- parameters; nothing in this module computes terrain itself.
--
-- Parameter semantics:
--   relief:        overall height amplitude multiplier for the macro structure
--   warpScale/Amp: domain-warp control — meander wavelength/strength of large landforms
--   roughScale:    wavelength of the spatially-variable roughness control field
--   roughLo/Hi:    roughness output range — low = smooth aprons, high = rugged crags
--   terraceStep:   strata quantization interval in studs (0 disables)
--   terraceStrength: 0..1 how sharp terraces are (1 = hard angular, spec's angular low-poly style)
--   ridgeAngle:    primary directional axis for elongated landforms (radians, jittered per seed)
--   ridgeAniso:    anisotropic compression factor for directional ridged noise
--   masks:         named analytic masks the archetype exposes for layout validation
--   envelopes:     validation acceptance bands used by Metrics
--   weights:       selection weight per mission template family

export type Envelope = { min: number, max: number }

export type ArchetypeDef = {
	id: string,
	relief: number,
	baseHeight: number,
	warpScale: number,
	warpAmp: number,
	roughScale: number,
	roughLo: number,
	roughHi: number,
	terraceStep: number,
	terraceStrength: number,
	ridgeAngle: number,
	ridgeAniso: number,
	-- validation envelopes
	elevationSigma: Envelope,
	slopeGentle14: Envelope, -- fraction of area under 14 degrees
	slopeSteep35: Envelope,  -- fraction of area above 35 degrees (must stay small)
	coverDensity: Envelope,
	correlationLength: Envelope,
	-- mission-template selection weights
	weights: { [string]: number },
	-- composition hints consumed by dressing layer later
	composition: { floraDensity: number, rockDensity: number, wreckDensity: number },
}

local Archetypes: { [string]: ArchetypeDef } = {

	highland_valley = {
		id = "highland_valley",
		relief = 88,
		baseHeight = 24,
		warpScale = 320, warpAmp = 68,
		roughScale = 260, roughLo = 0.35, roughHi = 1.0,
		terraceStep = 4.5, terraceStrength = 0.75,
		ridgeAngle = 0.0, ridgeAniso = 3.4,
		elevationSigma = { min = 20, max = 80 },
		slopeGentle14 = { min = 0.2, max = 0.7 },
		slopeSteep35 = { min = 0.0, max = 0.22 },
		coverDensity = { min = 0.08, max = 0.28 },
		correlationLength = { min = 70, max = 220 },
		weights = { SABOTAGE_RELAY = 3, RECOVER_TECH = 2, DEFEND_BEACON = 1, ELIMINATION = 2, CONQUEST = 2 },
		composition = { floraDensity = 0.5, rockDensity = 0.9, wreckDensity = 0.3 },
	},

	canyon_network = {
		id = "canyon_network",
		relief = 82,
		baseHeight = 30,
		warpScale = 260, warpAmp = 80,
		roughScale = 200, roughLo = 0.4, roughHi = 1.0,
		terraceStep = 4.5, terraceStrength = 0.35,
		ridgeAngle = 0.0, ridgeAniso = 2.2,
		elevationSigma = { min = 16, max = 85 },
		slopeGentle14 = { min = 0.12, max = 0.6 },
		slopeSteep35 = { min = 0.0, max = 0.3 },
		coverDensity = { min = 0.10, max = 0.32 },
		correlationLength = { min = 60, max = 180 },
		weights = { SABOTAGE_RELAY = 3, RECOVER_TECH = 3, DEFEND_BEACON = 1, ELIMINATION = 2, CONQUEST = 1 },
		composition = { floraDensity = 0.25, rockDensity = 1.0, wreckDensity = 0.25 },
	},

	fortified_plateau = {
		id = "fortified_plateau",
		relief = 78,
		baseHeight = 26,
		warpScale = 340, warpAmp = 55,
		roughScale = 240, roughLo = 0.3, roughHi = 0.9,
		terraceStep = 5.0, terraceStrength = 0.8,
		ridgeAngle = 0.0, ridgeAniso = 2.8,
		elevationSigma = { min = 15, max = 80 },
		slopeGentle14 = { min = 0.18, max = 0.65 },
		slopeSteep35 = { min = 0.0, max = 0.25 },
		coverDensity = { min = 0.06, max = 0.24 },
		correlationLength = { min = 80, max = 240 },
		weights = { SABOTAGE_RELAY = 1, RECOVER_TECH = 2, DEFEND_BEACON = 3, ELIMINATION = 2, CONQUEST = 3 },
		composition = { floraDensity = 0.3, rockDensity = 0.8, wreckDensity = 0.3 },
	},

	open_plains = {
		id = "open_plains",
		relief = 46,
		baseHeight = 22,
		warpScale = 380, warpAmp = 45,
		roughScale = 320, roughLo = 0.15, roughHi = 0.55,
		terraceStep = 3.5, terraceStrength = 0.45,
		ridgeAngle = 0.0, ridgeAniso = 2.0,
		elevationSigma = { min = 7, max = 40 },
		slopeGentle14 = { min = 0.4, max = 0.9 },
		slopeSteep35 = { min = 0.0, max = 0.1 },
		coverDensity = { min = 0.04, max = 0.16 },
		correlationLength = { min = 100, max = 260 },
		weights = { SABOTAGE_RELAY = 1, RECOVER_TECH = 1, DEFEND_BEACON = 2, ELIMINATION = 3, CONQUEST = 2 },
		composition = { floraDensity = 0.4, rockDensity = 0.35, wreckDensity = 0.4 },
	},

	broken_basin = {
		id = "broken_basin",
		relief = 64,
		baseHeight = 24,
		warpScale = 300, warpAmp = 60,
		roughScale = 220, roughLo = 0.3, roughHi = 0.95,
		terraceStep = 4.5, terraceStrength = 0.55,
		ridgeAngle = 0.0, ridgeAniso = 2.4,
		elevationSigma = { min = 12, max = 70 },
		slopeGentle14 = { min = 0.16, max = 0.68 },
		slopeSteep35 = { min = 0.0, max = 0.24 },
		coverDensity = { min = 0.09, max = 0.3 },
		correlationLength = { min = 70, max = 200 },
		weights = { SABOTAGE_RELAY = 2, RECOVER_TECH = 2, DEFEND_BEACON = 3, ELIMINATION = 2, CONQUEST = 2 },
		composition = { floraDensity = 0.6, rockDensity = 0.7, wreckDensity = 0.3 },
	},

	industrial_wasteland = {
		id = "industrial_wasteland",
		relief = 66,
		baseHeight = 22,
		warpScale = 300, warpAmp = 40,
		roughScale = 240, roughLo = 0.25, roughHi = 0.7,
		terraceStep = 4.0, terraceStrength = 0.6,
		ridgeAngle = 0.0, ridgeAniso = 2.0,
		elevationSigma = { min = 10, max = 60 },
		slopeGentle14 = { min = 0.55, max = 0.85 },
		slopeSteep35 = { min = 0.0, max = 0.07 },
		coverDensity = { min = 0.10, max = 0.34 },
		correlationLength = { min = 80, max = 220 },
		weights = { SABOTAGE_RELAY = 2, RECOVER_TECH = 3, DEFEND_BEACON = 1, ELIMINATION = 2, CONQUEST = 3 },
		composition = { floraDensity = 0.1, rockDensity = 0.4, wreckDensity = 1.0 },
	},
}

-- Biome compatibility: Veyra-7 launch biome is highland; the matrix exists so future biomes can
-- exclude archetypes that make no physical sense (frozen canyon yes, volcanic basin maybe not).
local BIOME_COMPAT: { [string]: { string } } = {
	Highland = { "highland_valley", "canyon_network", "fortified_plateau", "open_plains", "broken_basin", "industrial_wasteland" },
	Forest = { "highland_valley", "broken_basin", "open_plains" },
	Arid = { "canyon_network", "fortified_plateau", "open_plains", "industrial_wasteland" },
	Frozen = { "highland_valley", "fortified_plateau", "open_plains" },
}

local ArchetypesModule = {}

function ArchetypesModule.get(id: string): ArchetypeDef
	return Archetypes[id]
end

function ArchetypesModule.all(): { [string]: ArchetypeDef }
	return Archetypes
end

-- Weighted archetype selection for a mission template inside a biome. rng is a stream function
-- returning [0,1). recentIds optionally down-weights the last few played archetypes (x0.35) for
-- light anti-repetition without history infrastructure.
function ArchetypesModule.select(template: string, biome: string?, rng: () -> number, recentIds: { string }?): string
	local compat = BIOME_COMPAT[biome or "Highland"] or BIOME_COMPAT.Highland
	local total = 0
	local weighted = {}
	for _, id in compat do
		local def = Archetypes[id]
		local w = (def.weights[template] or 1)
		if recentIds then
			for _, r in recentIds do
				if r == id then
					w *= 0.35
					break
				end
			end
		end
		if w > 0 then
			total += w
			table.insert(weighted, { id = id, w = w, acc = total })
		end
	end
	local roll = rng() * total
	for _, entry in weighted do
		if roll <= entry.acc then
			return entry.id
		end
	end
	return compat[1]
end

return ArchetypesModule
