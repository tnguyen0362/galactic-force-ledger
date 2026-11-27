--!strict
export type WeaponCategory = "Rifle" | "Pistol" | "Shotgun" | "Marksman" | "LMG" | "Energy"

export type WeaponDef = {
	id: string,
	displayName: string,
	category: WeaponCategory,
	unlockRank: number,
	cost: number,
	damage: number,
	armorPenetration: number,
	shieldMultiplier: number,
	fireMode: "Auto" | "Semi",
	rpm: number,
	magazine: number,
	reserve: number,
	reloadTime: number,
	spreadBase: number,
	spreadPerShot: number,
	recoil: number,
	range: number,
	falloffStart: number,
	falloffEnd: number,
	adsZoom: number,
	coreAugmentSlots: number,
}

export type EnemyDef = {
	id: string,
	displayName: string,
	tier: "Standard" | "Specialist" | "Elite" | "Boss",
	health: number,
	shield: number,
	damage: number,
	attackRange: number,
	attackCooldown: number,
	speed: number,
	sightRange: number,
	lootScrap: number,
	lootEnergyChance: number,
	lootTechChance: number,
	behavior: string,
	weakPointMultiplier: number,
}

export type AbilityDef = {
	id: string,
	displayName: string,
	unlockRank: number,
	cost: number,
	cooldown: number,
	duration: number,
	radius: number,
	damage: number,
	maxActive: number,
	targeting: "Ground" | "Self",
}

export type ClassDef = {
	id: string,
	displayName: string,
	personal: { stat: string, value: number },
	team: { stat: string, value: number },
	suggested: { primary: string, ability: string },
}

export type DifficultyDef = {
	id: string,
	displayName: string,
	unlockRank: number,
	rewardMultiplier: number,
	enemyBudget: number,
	eliteFrequency: number,
	ticketBase: number,
	ticketPerPlayer: number,
}

export type MissionDef = {
	id: string,
	displayName: string,
	durationClass: "Short" | "Standard" | "Extended",
	primary: string,
	-- formal optional objectives removed (Counteroffensive contract revision)
}

export type Loadout = {
	primary: string,
	secondary: string,
	grenade: string,
	-- one support ability slot (Counteroffensive contract revision)
	ability: string,
	classId: string,
	weaponAugments: { [string]: string },
	abilityAugment: string?,
}

export type Profile = {
	schemaVersion: number,
	rank: number,
	xp: number,
	credits: number,
	ownedWeapons: { [string]: boolean },
	ownedAbilities: { [string]: boolean },
	ownedAugments: { [string]: boolean },
	weaponMastery: { [string]: { level: number, xp: number } },
	bossResearch: { [string]: { clears: number, guaranteed: number, owned: boolean } },
	salvage: { scrap: number, energyCells: number, militaryTechnology: number },
	loadout: Loadout,
	savedLoadouts: { [string]: Loadout },
	tutorialCompleted: boolean,
	introWatched: boolean,
	warContribution: number,
}

return nil

