--!strict
-- Global tunables. Every number here is a prototype value from the master directive.
local Constants = {}

Constants.Movement = {
	-- speeds (movement/camera refinement spec table; class modifiers apply downstream)
	WalkSpeed = 17,
	SprintSpeed = 24,
	AdsSpeed = 12.8,
	BackwardSpeed = 12,
	DownedSpeed = 4,
	-- jump: Power 45 = ~5.2 studs with default gravity, inside the spec's 5-6 stud band
	JumpPower = 45,
	-- roll (server-authoritative)
	RollDuration = 0.55,
	RollDistance = 12,
	RollCharges = 2,
	RollRecharge = 5,
	RollRecovery = 0.08,
	RollSpeed = 26,
	CrouchSpeed = 8, -- legacy, unused; crouch is a spec exclusion
	-- acceleration model: alpha = 1 - exp(-dt/tau); braking faster than acceleration
	AccelTau = 0.09,
	DecelTau = 0.055,
	MinStartSpeed = 0.35,
	-- automatic sprint hysteresis band
	SprintEnterMagnitude = 0.85,
	SprintEnterDot = 0.65,
	SprintExitMagnitude = 0.5,
	SprintExitDot = 0.45,
	-- orientation: shortest-path yaw smoothing with a rate cap
	TurnTauLocomotion = 0.09,
	TurnTauCombat = 0.06,
	MaxTurnRate = math.rad(720),
	-- vault / climb envelope
	VaultForward = 4.5,
	VaultMinHeight = 0.8,
	VaultMaxHeight = 4,
	ClimbMaxHeight = 7,
	VaultLandingDepth = 3,
	-- aim sensitivity scale while ADS (multiplies the user setting)
	AimSensitivityScale = 0.8,
}

Constants.Camera = {
	Explore = { Distance = 9.0, RightOffset = 2.0, PivotHeight = 2.2, FOV = 70 },
	Sprint = { Distance = 10.0, RightOffset = 1.7, PivotHeight = 2.2, FOV = 76 },
	Aim = { Distance = 5.5, RightOffset = 2.1, PivotHeight = 2.3, FOV = 58 },
	Dodge = { Distance = 9.5, RightOffset = 1.8, PivotHeight = 2.0, FOV = 73 },
	Downed = { Distance = 7.5, RightOffset = 1.8, PivotHeight = 1.0, FOV = 68 },
	PitchMin = math.rad(-75),
	PitchMax = math.rad(75),
	MouseSensitivity = 0.0006,
	TouchSensitivity = 0.0042,
	StickDeadzone = 0.14,
	StickGamma = 1.5,
	StickLookSpeed = 2.6,
	TauEnterAim = 0.06,
	TauExitAim = 0.075,
	TauEnterSprint = 0.085,
	TauExitSprint = 0.055,
	TauDodge = 0.07,
	TauDowned = 0.12,
	OcclusionRadius = 0.35,
	OcclusionMargin = 0.25,
	OcclusionMinDistance = 1.2,
	OcclusionInTau = 0.03,
	OcclusionOutTau = 0.35,
	BobAmplitude = 0.045,
	RecoilRecoveryTau = 0.09,
	LandingDipAngle = math.rad(4.5),
	LandingRecoveryTau = 0.14,
	ShakeAmplitude = 0.035,
	AimAssistConeDegrees = 5,
	AimAssistRange = 120,
	AimAssistTau = 0.14,
	AimAssistStrength = 0.5,
	AimAssistFriction = 0.45,
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

