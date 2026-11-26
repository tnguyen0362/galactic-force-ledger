--!strict
-- Templates: installation template definitions. Data-first — each template declares its footprint,
-- foundation requirements, entrance sockets, internal zones, defensive positions, reinforcement
-- access, objective interaction points, supply points, sightline requirements and validity rules.
-- Composition (actual parts) is done by the builder pass; this module is the design contract.
--
-- Coordinates are template-local: x/z offsets in studs relative to the template anchor at yaw=0.
-- Orientation variation = rotating this frame; the placement scorer validates rotated footprints.

export type Socket = { x: number, z: number, dir: number, width: number } -- dir radians, world-relative after rotation
export type Zone = { kind: string, x: number, z: number, r: number }
export type TemplateDef = {
	id: string,
	family: string,        -- small | outpost | base | primary
	footprintRadius: number,
	foundationSlopeMax: number,   -- max mean slope across footprint for placement validity
	foundationFlatten: number,    -- radius of terrain leveling applied if placed
	entrances: { Socket },
	zones: { Zone },              -- interior areas: muster/storage/work/defense/objective/supply
	defensivePositions: { { x: number, z: number } },
	reinforcementAccess: { Socket },
	sightlineMin: number,  -- at least one entrance-to-core sightline must reach this length
	archetypeFit: { [string]: number }, -- multiplier per archetype; missing = 1
	weight: number,
}

local T: { [string]: TemplateDef } = {}

-- SMALL DEFENSIVE POSITIONS ------------------------------------------------

T.guard_post = {
	id = "guard_post", family = "small",
	footprintRadius = 16, foundationSlopeMax = 14, foundationFlatten = 12,
	entrances = { { x = 0, z = 12, dir = math.rad(180), width = 6 } },
	zones = {
		{ kind = "defense", x = 0, z = 0, r = 8 },
	},
	defensivePositions = { { x = -5, z = -4 }, { x = 5, z = -4 } },
	reinforcementAccess = {},
	sightlineMin = 30,
	archetypeFit = { open_plains = 1.6, highland_valley = 1.2 },
	weight = 3,
}

T.checkpoint = {
	id = "checkpoint", family = "small",
	footprintRadius = 22, foundationSlopeMax = 12, foundationFlatten = 16,
	entrances = {
		{ x = 0, z = 16, dir = math.rad(180), width = 8 },
		{ x = 0, z = -16, dir = math.rad(0), width = 8 },
	},
	zones = {
		{ kind = "defense", x = 0, z = 0, r = 10 },
		{ kind = "muster", x = 6, z = 4, r = 5 },
	},
	defensivePositions = { { x = -6, z = 8 }, { x = 6, z = 8 }, { x = 0, z = -8 } },
	reinforcementAccess = {},
	sightlineMin = 55, -- checkpoints exist to control a road sightline
	archetypeFit = { canyon_network = 1.5, highland_valley = 1.3 },
	weight = 2,
}

T.observation_post = {
	id = "observation_post", family = "small",
	footprintRadius = 14, foundationSlopeMax = 16, foundationFlatten = 10,
	entrances = { { x = 8, z = 8, dir = math.rad(225), width = 5 } },
	zones = {
		{ kind = "defense", x = 0, z = 0, r = 7 },
	},
	defensivePositions = { { x = 0, z = 0 } },
	reinforcementAccess = {},
	sightlineMin = 90, -- observation requires commanding sightlines
	archetypeFit = { fortified_plateau = 1.5, highland_valley = 1.3, open_plains = 0.6 },
	weight = 2,
}

-- OUTPOSTS -----------------------------------------------------------------

T.supply_depot = {
	id = "supply_depot", family = "outpost",
	footprintRadius = 34, foundationSlopeMax = 11, foundationFlatten = 26,
	entrances = {
		{ x = 0, z = 26, dir = math.rad(180), width = 10 },
		{ x = -22, z = -12, dir = math.rad(60), width = 7 },
	},
	zones = {
		{ kind = "storage", x = 0, z = -8, r = 12 },
		{ kind = "supply", x = 0, z = -8, r = 8 },
		{ kind = "defense", x = 0, z = 14, r = 8 },
		{ kind = "muster", x = 10, z = 4, r = 6 },
	},
	defensivePositions = { { x = -8, z = 16 }, { x = 8, z = 16 }, { x = -14, z = -16 } },
	reinforcementAccess = { { x = 24, z = 10, dir = math.rad(270), width = 8 } },
	sightlineMin = 35,
	archetypeFit = { open_plains = 1.4 },
	weight = 2,
}

T.comms_relay_outpost = {
	id = "comms_relay_outpost", family = "outpost",
	footprintRadius = 38, foundationSlopeMax = 12, foundationFlatten = 28,
	entrances = {
		{ x = 0, z = 30, dir = math.rad(180), width = 9 },
		{ x = 24, z = -18, dir = math.rad(300), width = 7 },
	},
	zones = {
		{ kind = "objective", x = 0, z = -6, r = 8 },   -- relay core interaction
		{ kind = "work", x = -10, z = 2, r = 8 },
		{ kind = "defense", x = 0, z = 18, r = 9 },
		{ kind = "muster", x = 12, z = -12, r = 6 },
	},
	defensivePositions = { { x = -9, z = 20 }, { x = 9, z = 20 }, { x = 18, z = -6 }, { x = -18, z = -10 } },
	reinforcementAccess = { { x = -26, z = 8, dir = math.rad(90), width = 8 } },
	sightlineMin = 40,
	archetypeFit = { highland_valley = 1.3, canyon_network = 1.1 },
	weight = 2,
}

T.radar_station = {
	id = "radar_station", family = "outpost",
	footprintRadius = 32, foundationSlopeMax = 10, foundationFlatten = 24,
	entrances = { { x = 0, z = 24, dir = math.rad(180), width = 8 } },
	zones = {
		{ kind = "work", x = 0, z = -4, r = 10 },
		{ kind = "defense", x = 0, z = 12, r = 8 },
	},
	defensivePositions = { { x = -7, z = 14 }, { x = 7, z = 14 } },
	reinforcementAccess = { { x = -20, z = -14, dir = math.rad(45), width = 7 } },
	sightlineMin = 80, -- radar wants height/visibility
	archetypeFit = { fortified_plateau = 1.4, open_plains = 1.2 },
	weight = 1,
}

-- BASES --------------------------------------------------------------------

T.fortified_compound = {
	id = "fortified_compound", family = "base",
	footprintRadius = 55, foundationSlopeMax = 10, foundationFlatten = 40,
	entrances = {
		{ x = 0, z = 42, dir = math.rad(180), width = 12 },
		{ x = -38, z = -20, dir = math.rad(60), width = 9 },
	},
	zones = {
		{ kind = "defense", x = 0, z = 24, r = 14 },
		{ kind = "storage", x = -14, z = -8, r = 12 },
		{ kind = "work", x = 14, z = -8, r = 12 },
		{ kind = "muster", x = 0, z = 2, r = 10 },
		{ kind = "supply", x = -14, z = -8, r = 8 },
	},
	defensivePositions = {
		{ x = -10, z = 30 }, { x = 10, z = 30 }, { x = -30, z = 6 }, { x = 30, z = 6 },
		{ x = -20, z = -26 }, { x = 20, z = -26 },
	},
	reinforcementAccess = { { x = 42, z = -10, dir = math.rad(270), width = 10 } },
	sightlineMin = 45,
	archetypeFit = { fortified_plateau = 1.5, open_plains = 1.1 },
	weight = 2,
}

T.artillery_installation = {
	id = "artillery_installation", family = "base",
	footprintRadius = 60, foundationSlopeMax = 9, foundationFlatten = 44,
	entrances = {
		{ x = 0, z = 46, dir = math.rad(180), width = 12 },
		{ x = 40, z = 22, dir = math.rad(300), width = 9 },
	},
	zones = {
		{ kind = "work", x = 0, z = -10, r = 20 },   -- gun pit line
		{ kind = "storage", x = -20, z = 8, r = 10 }, -- munitions
		{ kind = "defense", x = 0, z = 28, r = 12 },
		{ kind = "muster", x = 16, z = 6, r = 8 },
	},
	defensivePositions = {
		{ x = -12, z = 34 }, { x = 12, z = 34 }, { x = -34, z = 0 }, { x = 34, z = -4 },
	},
	reinforcementAccess = { { x = -42, z = -18, dir = math.rad(60), width = 10 } },
	sightlineMin = 50,
	archetypeFit = { open_plains = 1.5, fortified_plateau = 1.2 },
	weight = 1,
}

-- PRIMARY INSTALLATIONS ----------------------------------------------------

T.command_stronghold = {
	id = "command_stronghold", family = "primary",
	footprintRadius = 85, foundationSlopeMax = 9, foundationFlatten = 62,
	entrances = {
		{ x = 0, z = 66, dir = math.rad(180), width = 14 },
		{ x = -56, z = -26, dir = math.rad(60), width = 10 },
		{ x = 56, z = -26, dir = math.rad(300), width = 10 },
	},
	zones = {
		{ kind = "objective", x = 0, z = -18, r = 14 },  -- command core
		{ kind = "defense", x = 0, z = 36, r = 18 },
		{ kind = "work", x = -22, z = -4, r = 12 },
		{ kind = "storage", x = 22, z = -4, r = 12 },
		{ kind = "muster", x = 0, z = 8, r = 12 },
		{ kind = "supply", x = 22, z = -4, r = 8 },
	},
	defensivePositions = {
		{ x = -14, z = 44 }, { x = 14, z = 44 }, { x = -42, z = 16 }, { x = 42, z = 16 },
		{ x = -30, z = -34 }, { x = 30, z = -34 }, { x = 0, z = -48 },
	},
	reinforcementAccess = {
		{ x = -62, z = 20, dir = math.rad(90), width = 10 },
		{ x = 62, z = 20, dir = math.rad(270), width = 10 },
	},
	sightlineMin = 50,
	archetypeFit = { fortified_plateau = 1.4, highland_valley = 1.1 },
	weight = 1,
}

T.weapons_facility = {
	id = "weapons_facility", family = "primary",
	footprintRadius = 80, foundationSlopeMax = 10, foundationFlatten = 58,
	entrances = {
		{ x = 0, z = 60, dir = math.rad(180), width = 13 },
		{ x = -52, z = 18, dir = math.rad(90), width = 9 },
	},
	zones = {
		{ kind = "objective", x = 0, z = -14, r = 16 },  -- central equipment/relay
		{ kind = "work", x = -18, z = -10, r = 12 },
		{ kind = "storage", x = 18, z = -10, r = 12 },
		{ kind = "defense", x = 0, z = 32, r = 16 },
		{ kind = "muster", x = -8, z = 10, r = 10 },
	},
	defensivePositions = {
		{ x = -12, z = 40 }, { x = 12, z = 40 }, { x = -38, z = 8 }, { x = 38, z = 8 },
		{ x = -24, z = -32 }, { x = 24, z = -32 },
	},
	reinforcementAccess = { { x = 58, z = -8, dir = math.rad(270), width = 10 } },
	sightlineMin = 45,
	archetypeFit = { canyon_network = 1.3, industrial_wasteland = 1.4 },
	weight = 1,
}

T.industrial_complex = {
	id = "industrial_complex", family = "primary",
	footprintRadius = 90, foundationSlopeMax = 11, foundationFlatten = 66,
	entrances = {
		{ x = 0, z = 68, dir = math.rad(180), width = 15 },
		{ x = -60, z = -10, dir = math.rad(90), width = 11 },
		{ x = 48, z = -40, dir = math.rad(330), width = 9 },
	},
	zones = {
		{ kind = "objective", x = -10, z = -16, r = 15 },
		{ kind = "work", x = 16, z = -12, r = 16 },
		{ kind = "storage", x = -24, z = 8, r = 12 },
		{ kind = "defense", x = 0, z = 36, r = 16 },
		{ kind = "muster", x = 8, z = 12, r = 10 },
		{ kind = "supply", x = -24, z = 8, r = 8 },
	},
	defensivePositions = {
		{ x = -14, z = 46 }, { x = 14, z = 46 }, { x = -44, z = 18 }, { x = 44, z = 18 },
		{ x = -30, z = -36 }, { x = 30, z = -36 },
	},
	reinforcementAccess = { { x = 64, z = 8, dir = math.rad(270), width = 11 } },
	sightlineMin = 40,
	archetypeFit = { industrial_wasteland = 1.6, canyon_network = 1.1 },
	weight = 1,
}

local Templates = {}

function Templates.get(id: string): TemplateDef
	return T[id]
end

function Templates.all(): { [string]: TemplateDef }
	return T
end

function Templates.byFamily(family: string): { TemplateDef }
	local out = {}
	for _, t in T do
		if t.family == family then
			table.insert(out, t)
		end
	end
	return out
end

return Templates
