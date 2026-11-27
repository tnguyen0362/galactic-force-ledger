--!strict
-- Single registry. Server creates these; client fetches by name. Unknown names fail closed.
local Remotes = {}

-- Typed remote contract (GOAL_2026-11-24.md L220): every payload in either direction carries an
-- action/id field or a documented shape pinned by this version. Bump when a payload shape changes
-- incompatibly; probes assert the booted build still speaks the version the ledger verified.
Remotes.ContractVersion = 1

Remotes.Names = {

	"ThrowGrenade",
	"GrenadeDetonated",
	"VitalsUpdated",
	"AmmoUpdated",
	"WeaponEquipped",
	"ShieldBroken",
	"DirectionalHit",
	"DownedChanged",
	"DodgeUpdated",
	"AbilityCast",
	"AbilityImpact",
	"EnemyTelegraph",
	"EnemyFired",
	"ProjectileFired",
	"ProjectileDetonated",
	"RequestDodge",
	"ClaimStarter",
	"SprintChanged",
	"AimChanged",
	"CrouchChanged",

	"RequestProfile",
	"ProfileUpdated",
	"RequestLoadout",
	"SetLoadout",
	"FireWeapon",
	"ReloadWeapon",
	"ReloadCancelled",
	"EquipWeapon",
	"UseAbility",
	"AbilityConfirmed",
	"AbilityStateChanged",
	"RequestInteract",
	"ReportState",
	"RequestExtractionVote",
	"CastVote",
	"VoteStateChanged",
	"RequestExtraction",
	"MissionStateChanged",
	"HackState",
	"HackAttempt",
	"ZoneState",
	"MissionEvent",
	"SalvageUpdated",
	"RewardsGranted",
	"RequestDeploy",
	"DeployStateChanged",
	"DamageFeedback",
	"DialogueEvent",
	"InteractRequest",
	"ObjectiveProgress",
	"ObjectiveComplete",
	"ExtractionRequest",
	"MarkIntroSeen",
	"OpenArmoryPanel",
	"RequestSettings",
	"DispatchListing",
	"RequestDispatchJoin",
	"RequestQuickDeploy",
	"SettingsChanged",
	"RequestSettings",
	"SettingsChanged",
	"RequestIntroReplay",
	"IntroReplay",
	"ExtractionState",
	"MissionComplete",
	"SalvageChanged",
	"LootCollected",
	-- the debrief RETURN TO STATION button fires this. It used to be created ad hoc inside
	-- StationService.start, which left an unregistered remote in the folder and failed GF.Check.
	"RequestReturn",
}

Remotes.Functions = {
	"RequestDeployOptions",
	"RequestDebrief",
}

function Remotes.serverContainer(): Folder
	local RS = game:GetService("ReplicatedStorage")
	local gf = RS:FindFirstChild("GF")
	assert(gf, "GF folder missing in ReplicatedStorage")
	local c = gf:FindFirstChild("Remotes")
	assert(c, "Remotes folder missing")
	return c :: Folder
end

function Remotes.get(name: string): Instance
	assert(table.find(Remotes.Names, name) or table.find(Remotes.Functions, name), "Unknown remote: " .. tostring(name))
	local c = Remotes.serverContainer()
	local r = c:FindFirstChild(name)
	assert(r, "Remote not created: " .. name)
	return r
end

function Remotes.server(name: string): RemoteEvent
	local r = Remotes.get(name)
	assert(r:IsA("RemoteEvent"), name .. " is not a RemoteEvent")
	return r
end

function Remotes.func(name: string): RemoteFunction
	local r = Remotes.get(name)
	assert(r:IsA("RemoteFunction"), name .. " is not a RemoteFunction")
	return r
end

return Remotes

