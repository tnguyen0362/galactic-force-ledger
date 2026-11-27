--!strict
-- Mission template roster (Counteroffensive contract revision). Formal optional objectives are
-- removed — no optionalPois, no optional contract states. Tactical-site texture persists as
-- informal environmental interactions, and relay/generator effects live inside mandatory
-- objective DAGs where thematically central. displayName/variant use the canonical operation
-- names; ids are stable persistence keys and never change.
--
-- OBJECTIVE DEPTH SCHEMA (additive, every key optional — ObjectiveService falls back to family
-- defaults when a key is absent, so templates that declare nothing still play):
--
--   objective = {
--     -- CARRY (Recovery family): the mission object is physically hauled to a destination.
--     carrySpeed = number?,        -- WalkSpeed cap while hauling (default 15; sprint is 24)
--     carryPrompt = string?,       -- interact prompt shown on the carry object
--     responseRoster = { string }?,-- enemy ids for the scripted reaction/pursuit squad
--     responseDelay = number?,     -- seconds after the trigger before the reaction squad lands
--
--     -- HUNT (Elimination family): priority targets start unidentified and unmarked.
--     scanRange = number?,         -- proximity-scan reveal radius (default 45)
--     scanTime = number?,          -- continuous proximity seconds to confirm one target (default 4)
--     cleanWindow = number?,       -- seconds from first reveal/kill for the clean-hunt commendation
--     matrix = number?,            -- bonus shield pool on the priority target, stripped when revealed
--     spread = number?,            -- scatter radius for multi-target rosters (default 0 = clustered)
--     targets = { string }?,       -- required-kill enemy roster (EnemyService ids or "BastionWalker")
--     escorts = { string }?,       -- protection detail — they fight but are NOT required kills
--
--     -- HOLD (Defense/Conquest): telegraphed, directional wave escalation during capture stages.
--     waves = { { at = number, count = number, close = boolean? } }?,
--                                  -- wave triggers at zone-progress fractions; close=true spawns
--                                  -- inside the perimeter lip instead of out on the approach
--     holdSeconds = number?,       -- capture/hold duration override
--     ventAt = number?,            -- progress fraction where a hold pauses for a console hack beat
--
--     -- CONQUEST family.
--     stage1 = "clear" | "interact"?, -- first stage flavor (default "clear")
--     roster = { string }?,        -- base defender roster for a "clear" first stage
--     boss = boolean?,             -- mid-stage boss fight (Thronefall)
--     defend = number?,            -- final hold duration seconds
--     capturePoints = number?,     -- simultaneous capture zones in the capture stage (default 1)
--
--     -- SABOTAGE family.
--     plantSeconds = number?,      -- per-charge plant channel time (default 2.5)
--   }
local Missions = {}

Missions.List = {
	{
		id = "FIRST_SPEAR", displayName = "Operation First Spear", durationClass = "Short",
		family = "Tutorial", variant = "First Spear",
		soloSeed = 42, controlledSeed = true, targetMinutes = { 8, 11 },
		description = "Solo controlled-seed introduction — the first drop every recruit flies.",
		primary = "Complete the insertion drill",
	},
	{
		id = "SABOTAGE_RELAY", displayName = "Sever the Signal", durationClass = "Standard",
		family = "Sabotage", variant = "Sever the Signal",
		primary = "Disable the Ascendancy relay",
	},
	{
		id = "RECOVERY_ARCHIVE", displayName = "Silent Archive", durationClass = "Standard",
		family = "Recovery", variant = "Silent Archive",
		primary = "Break the data console, then carry the archive core back to the landing zone",
		objective = {
			carrySpeed = 15,
			carryPrompt = "Take the archive core",
			responseRoster = { "Rifleman", "Marksman", "Heavy" },
			responseDelay = 14,
		},
	},
	{
		id = "SABOTAGE_ARSENAL", displayName = "Burn the Arsenal", durationClass = "Standard",
		family = "Sabotage", variant = "Burn the Arsenal",
		primary = "Charge both depot pads, clear the blast area, and verify the stockpile is destroyed",
		objective = {
			plantSeconds = 2.5,
			responseRoster = { "Rifleman", "Rifleman", "Marksman" },
			responseDelay = 4,
		},
	},
	{
		id = "DEFENSE_POWER", displayName = "Power Under Fire", durationClass = "Extended",
		family = "Defense", variant = "Power Under Fire",
		primary = "Restore the generator, hold the perimeter while it spins up, then stabilise output",
		objective = {
			holdSeconds = 90,
			ventAt = 0.55,
			waves = {
				{ at = 0.22, count = 2 },
				{ at = 0.62, count = 3 },
				{ at = 0.86, count = 4 },
			},
		},
	},
	{
		id = "RECOVERY_CONVOY", displayName = "Fallen Convoy", durationClass = "Standard",
		family = "Recovery", variant = "Fallen Convoy",
		primary = "Haul both convoy crates to the salvage sled, then defeat the pursuit squad",
		objective = {
			carrySpeed = 15,
			carryPrompt = "Haul the crate",
			responseRoster = { "Rifleman", "Scout", "Heavy" },
			responseDelay = 18,
		},
	},
	{
		id = "DEFENSE_UPLINK", displayName = "Last Transmission", durationClass = "Extended",
		family = "Defense", variant = "Last Transmission",
		primary = "Activate the communications dish, defend the uplink, then confirm it",
		objective = {
			holdSeconds = 75,
			waves = {
				{ at = 0.2, count = 2 },
				{ at = 0.5, count = 3, close = true },
				{ at = 0.78, count = 4 },
			},
		},
	},
	{
		id = "SABOTAGE_AEGIS", displayName = "Shattered Aegis", durationClass = "Standard",
		family = "Sabotage", variant = "Shattered Aegis",
		primary = "Disable both shield generators, then destroy the exposed emitter",
		objective = {
			responseRoster = { "Rifleman", "Rifleman", "Scout" },
			responseDelay = 6,
		},
	},
	{
		id = "RECOVER_TECH", displayName = "Alien Legacy", durationClass = "Standard",
		family = "Recovery", variant = "Alien Legacy",
		primary = "Decrypt the black box cabinet, then carry the flight recorder to the landing zone",
		objective = {
			carrySpeed = 15,
			carryPrompt = "Take the flight recorder",
			responseRoster = { "Rifleman", "Scout", "Marksman" },
			responseDelay = 10,
		},
	},
	{
		id = "DEFEND_BEACON", displayName = "Hold the Line", durationClass = "Extended",
		family = "Defense", variant = "Hold the Line",
		primary = "Activate and hold the human communication beacon",
		objective = {
			holdSeconds = 75,
			waves = {
				{ at = 0.25, count = 2 },
				{ at = 0.6, count = 3 },
				{ at = 0.85, count = 3, close = true },
			},
		},
	},
	-- Elimination family. Three variants, three different fights: a commander with guards, a siege
	-- mech that must die here even though it is optional elsewhere, and three named elites.
	-- Hunt structure: targets deploy unidentified — the HUD marks only the sweep area until a
	-- proximity scan or the battle-net intel console confirms identity. Escorts fight for the
	-- target but are not required kills; speed after first contact earns the clean-hunt commendation.
	{
		id = "ELIM_COMMANDER", displayName = "Head of the Spear", durationClass = "Standard",
		family = "Elimination", variant = "Head of the Spear",
		primary = "Identify and eliminate the Ascendancy commander",
		objective = {
			targets = { "Officer" },
			escorts = { "Rifleman", "Rifleman", "Marksman", "Scout" },
			scanRange = 45,
			scanTime = 4,
			cleanWindow = 120,
		},
	},
	{
		id = "ELIM_WALKER", displayName = "Siege Breaker", durationClass = "Standard",
		family = "Elimination", variant = "Siege Breaker",
		primary = "Scan the Bastion Walker's armor matrix, then destroy it",
		objective = {
			targets = { "BastionWalker" },
			escorts = { "Rifleman", "Heavy", "Marksman" },
			scanRange = 55,
			scanTime = 5,
			matrix = 1800,
			cleanWindow = 210,
		},
	},
	-- Conquest family. Taking ground, then holding it: the same site runs clear -> capture -> hold,
	-- and Thronefall puts the rank-gated High Marshal in the middle stage. The capture stage is a
	-- multi-point seize: every point must be held to completion, spreading the squad across the base.
	{
		id = "CONQUEST_DOMINION", displayName = "Forward Dominion", durationClass = "Standard",
		family = "Conquest", variant = "Forward Dominion",
		primary = "Clear the military base, seize both capture points, then hold the facility",
		objective = {
			stage1 = "clear",
			roster = { "Rifleman", "Rifleman", "Marksman", "Rifleman" },
			defend = 45,
			capturePoints = 2,
			waves = {
				{ at = 0.35, count = 2 },
				{ at = 0.75, count = 3 },
			},
		},
	},
	{
		id = "CONQUEST_FOUNDRY", displayName = "Iron Foundry", durationClass = "Standard",
		family = "Conquest", variant = "Iron Foundry",
		primary = "Slice the turret power coupling, seize both capture points, then hold the foundry",
		objective = {
			stage1 = "interact",
			defend = 60,
			capturePoints = 2,
			waves = {
				{ at = 0.3, count = 2 },
				{ at = 0.7, count = 3 },
			},
		},
	},
	{
		id = "CONQUEST_THRONEFALL", displayName = "Thronefall", durationClass = "Extended",
		family = "Conquest", variant = "Thronefall",
		primary = "Breach the stronghold, defeat High Marshal Veyr, slice the command node",
		objective = {
			stage1 = "clear",
			roster = { "Heavy", "Marksman", "Officer" },
			boss = true,
			capturePoints = 1,
		},
	},
	{
		id = "ELIM_TALON", displayName = "Broken Talon", durationClass = "Standard",
		family = "Elimination", variant = "Broken Talon",
		primary = "Hunt the three elite Talon operatives across the outpost",
		objective = {
			targets = { "Officer", "Marksman", "Heavy" },
			escorts = { "Rifleman", "Rifleman", "Scout" },
			scanRange = 45,
			scanTime = 4,
			spread = 26,
			cleanWindow = 180,
		},
	},
}

Missions.ById = {}
for _, m in Missions.List do Missions.ById[m.id] = m end

function Missions.get(id: string)
	return Missions.ById[id]
end

return Missions
