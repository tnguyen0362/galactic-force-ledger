--!strict
local Missions = {}

Missions.List = {
	{
			id = "FIRST_SPEAR", displayName = "Operation First Spear", durationClass = "Short",
		family = "Tutorial", variant = "First Spear", optionalPois = 0,
		soloSeed = 42, controlledSeed = true, targetMinutes = { 8, 11 },
		description = "Solo controlled-seed introduction — the first drop every recruit flies.",
id = "SABOTAGE_RELAY", displayName = "Sabotage Relay", durationClass = "Standard",
		primary = "Disable the Ascendancy relay", optionalPois = 2,
		family = "Sabotage",
	},
	{
		id = "RECOVERY_ARCHIVE", displayName = "Silent Archive", durationClass = "Standard",
		family = "Recovery", variant = "Silent Archive", optionalPois = 2,
		primary = "Reach the intel room, break the data console, and recover the archive",
	},
	{
		id = "SABOTAGE_ARSENAL", displayName = "Burn the Arsenal", durationClass = "Standard",
		family = "Sabotage", variant = "Burn the Arsenal", optionalPois = 2,
		primary = "Charge both depot pads, clear the blast area, and verify the stockpile is destroyed",
	},
	{
		id = "DEFENSE_POWER", displayName = "Power Under Fire", durationClass = "Extended",
		family = "Defense", variant = "Power Under Fire", optionalPois = 2,
		primary = "Restore the generator, defend it for 90 seconds, then stabilise output",
	},
	{
		id = "RECOVERY_CONVOY", displayName = "Fallen Convoy", durationClass = "Standard",
		family = "Recovery", variant = "Fallen Convoy", optionalPois = 2,
		primary = "Recover both convoy crates, then defeat the pursuit squad",
	},
	{
		id = "DEFENSE_UPLINK", displayName = "Last Transmission", durationClass = "Extended",
		family = "Defense", variant = "Last Transmission", optionalPois = 2,
		primary = "Activate the communications dish, defend the uplink, then confirm it",
	},
	{
		id = "SABOTAGE_AEGIS", displayName = "Shattered Aegis", durationClass = "Standard",
		family = "Sabotage", variant = "Shattered Aegis", optionalPois = 2,
		primary = "Disable both shield generators, then destroy the exposed emitter",
	},
	{
		id = "RECOVER_TECH", displayName = "Recover Technology", durationClass = "Standard",
		primary = "Recover the downed scientific transport's black box", optionalPois = 2,
		family = "Recovery",
	},
	{
		id = "DEFEND_BEACON", displayName = "Defend Beacon", durationClass = "Extended",
		primary = "Activate and hold the human communication beacon", optionalPois = 2,
		family = "Defense",
	},
	-- Elimination family. Three variants, three different fights: a commander with guards, a siege
	-- mech that must die here even though it is optional elsewhere, and three named elites.
	{
		id = "ELIM_COMMANDER", displayName = "Head of the Spear", durationClass = "Standard",
		family = "Elimination", variant = "Head of the Spear", optionalPois = 2,
		primary = "Locate and eliminate the Ascendancy commander",
	},
	{
		id = "ELIM_WALKER", displayName = "Siege Breaker", durationClass = "Standard",
		family = "Elimination", variant = "Siege Breaker", optionalPois = 2,
		primary = "Destroy the Bastion Walker and secure the battlefield",
	},
	-- Conquest family. Taking ground, then holding it: the same site runs clear -> capture -> hold,
	-- and Thronefall puts the rank-gated High Marshal in the middle stage.
	{
		id = "CONQUEST_DOMINION", displayName = "Forward Dominion", durationClass = "Standard",
		family = "Conquest", variant = "Forward Dominion", optionalPois = 2,
		primary = "Clear the military base, seize the control console, then hold it",
	},
	{
		id = "CONQUEST_FOUNDRY", displayName = "Iron Foundry", durationClass = "Standard",
		family = "Conquest", variant = "Iron Foundry", optionalPois = 2,
		primary = "Cut turret power, capture the control point, then hold it",
	},
	{
		id = "CONQUEST_THRONEFALL", displayName = "Thronefall", durationClass = "Extended",
		family = "Conquest", variant = "Thronefall", optionalPois = 2,
		primary = "Breach the stronghold, defeat High Marshal Veyr, capture the command node",
	},
	{
		id = "ELIM_TALON", displayName = "Broken Talon", durationClass = "Standard",
		family = "Elimination", variant = "Broken Talon", optionalPois = 2,
		primary = "Defeat the three elite Talon operatives",
	},
}

Missions.ById = {}
for _, m in Missions.List do Missions.ById[m.id] = m end

function Missions.get(id: string)
	return Missions.ById[id]
end

return Missions

