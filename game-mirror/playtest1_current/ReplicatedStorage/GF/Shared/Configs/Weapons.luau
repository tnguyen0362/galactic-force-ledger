--!strict
-- Prototype balance values from the master directive. Tune via playtest, never in logic files.
local Weapons = {}

Weapons.List = {
	{
		id = "AR01", displayName = "Service Rifle", category = "Rifle",
		displayCategory = "Assault Rifle",
		unlockRank = 1, cost = 0,
		damage = 18, armorPenetration = 0.35, shieldMultiplier = 1.0,
		fireMode = "Auto", rpm = 600, magazine = 28, reserve = 168, reloadTime = 2.1,
		spreadBase = 2.0, spreadPerShot = 0.35, recoil = 1.0, adsSpread = 0.55,
		range = 400, falloffStart = 90, falloffEnd = 240, falloffMin = 0.55, adsZoom = 2.2, coreAugmentSlots = 1,
	},
	{
		id = "P01", displayName = "Service Pistol", category = "Pistol",
		displayCategory = "Pistol",
		unlockRank = 1, cost = 0,
		damage = 22, armorPenetration = 0.2, shieldMultiplier = 1.0,
		fireMode = "Semi", rpm = 300, magazine = 12, reserve = 72, reloadTime = 1.5,
		spreadBase = 2.2, spreadPerShot = 0.5, recoil = 0.8, adsSpread = 0.7,
		range = 250, falloffStart = 55, falloffEnd = 170, falloffMin = 0.50, adsZoom = 1.6, coreAugmentSlots = 1,
	},
	{
		id = "SG04", displayName = "Breacher", category = "Shotgun",
		displayCategory = "Shotgun",
		unlockRank = 2, cost = 500,
		damage = 96, armorPenetration = 0.25, shieldMultiplier = 0.9,
		fireMode = "Semi", rpm = 72, magazine = 6, reserve = 42, reloadTime = 2.8,
		spreadBase = 4.5, spreadPerShot = 0.2, recoil = 2.0, adsSpread = 3.2,
		range = 90, falloffStart = 22, falloffEnd = 75, falloffMin = 0.25, adsZoom = 1.3, coreAugmentSlots = 1,
		pellets = 8,
	},
	{
		id = "MR07", displayName = "Ranger", category = "Marksman",
		displayCategory = "Marksman Rifle",
		unlockRank = 4, cost = 850,
		damage = 51, armorPenetration = 0.6, shieldMultiplier = 1.1,
		fireMode = "Semi", rpm = 150, magazine = 12, reserve = 72, reloadTime = 2.4,
		spreadBase = 0.6, spreadPerShot = 0.6, recoil = 1.6, adsSpread = 0.18,
		range = 600, falloffStart = 150, falloffEnd = 350, falloffMin = 0.70, adsZoom = 3.4, coreAugmentSlots = 1,
	},
	{
		id = "LMG12", displayName = "Suppressor", category = "LMG",
		displayCategory = "LMG",
		unlockRank = 1, cost = 750,
		damage = 17, armorPenetration = 0.3, shieldMultiplier = 1.0,
		fireMode = "Auto", rpm = 660, magazine = 75, reserve = 225, reloadTime = 3.7,
		spreadBase = 2.2, spreadPerShot = 0.3, recoil = 1.2, adsSpread = 0.75,
		range = 420, falloffStart = 85, falloffEnd = 230, falloffMin = 0.50, adsZoom = 1.8, coreAugmentSlots = 1,
	},
	{
		id = "SMG03", displayName = "Jackal", category = "SMG",
		displayCategory = "SMG",
		unlockRank = 1, cost = 600,
		damage = 13, armorPenetration = 0.15, shieldMultiplier = 1.0,
		fireMode = "Auto", rpm = 850, magazine = 36, reserve = 216, reloadTime = 1.7,
		spreadBase = 1.5, spreadPerShot = 0.4, recoil = 0.7, adsSpread = 0.85,
		range = 150, falloffStart = 45, falloffEnd = 150, falloffMin = 0.40, adsZoom = 1.4, coreAugmentSlots = 1,
	},
	{
		id = "GL22", displayName = "Arcus", category = "Launcher",
		displayCategory = "Grenade Launcher",
		unlockRank = 4, cost = 1200,
		damage = 110, armorPenetration = 0.4, shieldMultiplier = 1.1,
		fireMode = "Semi", rpm = 50, magazine = 4, reserve = 16, reloadTime = 3.1,
		spreadBase = 0.8, spreadPerShot = 0.3, recoil = 2.6, adsSpread = 0.8,
		range = 180, falloffStart = 180, falloffEnd = 180, adsZoom = 1.5, coreAugmentSlots = 1,
		explosive = { radius = 13 },
	},
	{
		id = "RL09", displayName = "Atlas", category = "Launcher",
		displayCategory = "Rocket Launcher",
		unlockRank = 7, cost = 1500,
		damage = 205, armorPenetration = 0.65, shieldMultiplier = 1.0,
		fireMode = "Semi", rpm = 24, magazine = 1, reserve = 7, reloadTime = 3.4,
		spreadBase = 0.4, spreadPerShot = 0.6, recoil = 3.2, adsSpread = 0.4,
		range = 260, falloffStart = 260, falloffEnd = 260, adsZoom = 1.8, coreAugmentSlots = 1,
		explosive = { radius = 10 },
	},
}

Weapons.ByCategory = {}
Weapons.ById = {}
for _, w in Weapons.List do
	Weapons.ById[w.id] = w
	local list = Weapons.ByCategory[w.category]
	if not list then list = {}; Weapons.ByCategory[w.category] = list end
	table.insert(list, w)
end

function Weapons.get(id: string)
	return Weapons.ById[id]
end

return Weapons

