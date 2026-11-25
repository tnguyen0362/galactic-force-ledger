--!strict
-- Global tunables. Every number here is a prototype value from the master directive.
local Constants = {}

Constants.Movement = {
	WalkSpeed = 17,
	SprintSpeed = 24,
	-- Spec states this as a RATIO: ADS is 0.8x walk. 0.8 * WalkSpeed 17.5 = 14 exactly, so the
	-- literal 13 implemented 0.74x instead. Kept as a literal because Constants cannot reference
	-- its own sibling field during table construction.
	AdsSpeed = 14,
	JumpPower = 50,
	RollSpeed = 30,
	CrouchSpeed = 8,
	RollDuration = 0.55,
	RollDistance = 13,
	RollCharges = 2,
	RollRecharge = 5,
}

Constants.Vitals = {
	ShieldMax = 100,
	HealthMax = 100,
	ShieldRegenDelay = 4,
	ShieldRegenRate = 25,
	HealthRegenDelay = 9,
	HealthRegenRate = 8,
}

Constants.Combat = {
	ReviveDuration = 3,
	ReviveRange = 12,
	DownedTimeout = 60,
	MaxActiveEnemiesPerPlayer = 3,
	EnemyBudgetCap = 12,
}

Constants.Squad = {
	MaxPlayers = 4,
	ExtractionVoteWindow = 20,
	ExtractionGrace = 45,
	ExtractionHold = 60,
	AfkTimeout = 90,
}

Constants.Mission = {
	DurationShort = 660,
	DurationStandard = 990,
	DurationExtended = 1350,
	SoftLimitWarning = 300,
	SoftLimitBoardWindow = 150,
	-- Extraction defense countdown. Authoritative spec: 'defense countdown 75s default (60-90 by
	-- difficulty/variant)'. Moved here from an ExtractionService local so CheckRunner can see it.
	ExtractionCountdown = 75,
}

Constants.Progression = {
	MaxRank = 30,
	MasteryMaxLevel = 5,
	MasteryXpPerLevel = 1200,
	BossGuaranteedClearCount = 3,
}

Constants.World = {
	MapSizeStuds = 1100,
	MapMinRouteDistance = 300,
	MapMaxRouteDistance = 650,
	PoiMin = 4,
	PoiMax = 7,
	GenerationChunkStuds = 256,
}

-- Boss blueprint pity lived as two locals inside ProfileService, which is why the deviation from the
-- authored 5 clears / 15% could only be found by reading that file. Moving the numbers here makes them
-- assertable by CheckRunner. Values below are what the build already used - moved, not retuned.
Constants.Pity = {
	Target = 5,
	Chance = 0.15,
}
Constants.Net = {
	FireRateLimitPerSecond = 20,
	MaxRemoteBytesPerSecond = 4096,
}

table.freeze(Constants)
return Constants

