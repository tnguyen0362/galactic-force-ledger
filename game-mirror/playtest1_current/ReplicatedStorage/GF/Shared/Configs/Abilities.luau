--!strict
local Abilities = {}

Abilities.List = {
	{
		id = "Airstrike", displayName = "Tactical Airstrike", unlockRank = 1, cost = 0,
		cooldown = 90, duration = 3, radius = 40, damage = 140, maxActive = 2, range = 90,
		domeHealth = 600,
		targeting = "Ground",
	},
	{
		id = "DomeShield", displayName = "Dome Shield", unlockRank = 1, cost = 0,
		cooldown = 70, duration = 10, radius = 14, damage = 0, maxActive = 1, range = 90,
		domeHealth = 600,
		targeting = "Self",
	},
	{
		id = "Sentry", displayName = "Automated Sentry", unlockRank = 4, cost = 900,
		cooldown = 100, duration = 30, radius = 65, damage = 10, maxActive = 1, range = 90,
		domeHealth = 600,
		targeting = "Ground",
	},
	{
		id = "OrbitalStrike", displayName = "Orbital Precision Strike", unlockRank = 8, cost = 1800,
		cooldown = 150, duration = 3, radius = 13, damage = 390, maxActive = 1, range = 90,
		domeHealth = 600,
		targeting = "Ground",
	},
	{
		id = "OrbitalLance", displayName = "Orbital Lance", unlockRank = 10, cost = 0,
		cooldown = 165, duration = 3, radius = 6, damage = 420, maxActive = 1, range = 90,
		domeHealth = 600,
		targeting = "Ground",
		experimental = true,
	},
	{
		id = "ReflectiveBarrier", displayName = "Reflective Barrier", unlockRank = 10, cost = 0,
		cooldown = 85, duration = 7, radius = 10, damage = 0, maxActive = 1, range = 90,
		domeHealth = 600,
		targeting = "Self",
		experimental = true,
	},
}

Abilities.ById = {}
for _, a in Abilities.List do Abilities.ById[a.id] = a end

function Abilities.get(id: string)
	return Abilities.ById[id]
end

return Abilities

