--!strict
-- Per-player runtime (session-scoped, not persisted) + current mission context.
local State = {}

export type PlayerState = {
	shield: number,
	shieldMax: number,
	lastDamage: number,
	downed: boolean,
	downedAt: number,
	weaponId: string,
	ammo: number,
	reserve: number,
	reloading: boolean,
	reloadDone: number,
	invulnerableUntil: number,
	lastShotAt: number,
	lastShotId: number,
	cooldowns: { [string]: number },
	activeDome: Instance?,
	pendingMastery: { [string]: number }?,
	kills: number,
	damageDealt: number,
}

local states: { [Player]: PlayerState } = {}

export type MissionContext = {
	seed: number,
	difficulty: string,
	tickets: number,
	startedAt: number,
	softDeadline: number,
	objectiveComplete: boolean,
	extractionCalled: boolean,
}

local mission: MissionContext? = nil

function State.buildDefaults(): PlayerState
	-- Extracted from ensure() so state CONSTRUCTION can be tested without a Player. A throw in here is
	-- fatal and silent: it made State.create fail for every player at place 539, and the only symptom was
	-- 'no state' from whatever happened to read it first.
	local Constants = require(game:GetService("ReplicatedStorage").GF.Shared.Constants)
	return {
		shield = Constants.Vitals.ShieldMax,
		shieldMax = Constants.Vitals.ShieldMax,
		lastDamage = 0,
		downed = false,
		downedAt = 0,
		weaponId = "AR01",
		ammo = 28,
		-- Seeded from the starting weapon's catalogue reserve. A literal 0 here silently defeated lazy
		-- seeding in CombatService.ensureReserve (which only fills a nil), so the HUD read 0 forever.
		reserve = (function()
			-- NB: this file has no top-level ReplicatedStorage local; use the service directly or the
			-- expression throws 'attempt to index nil with GF' and NO player state is ever created.
			local ok, Weapons = pcall(require, game:GetService("ReplicatedStorage").GF.Shared.Configs.Weapons)
			local weapon = ok and Weapons and Weapons.get and Weapons.get("AR01")
			return (weapon and weapon.reserve) or 0
		end)(),
		reloading = false,
		reloadDone = 0,
		invulnerableUntil = 0,
		lastShotAt = 0,
		lastShotId = 0,
		cooldowns = {},
		activeDome = nil,
		kills = 0,
		damageDealt = 0,
		-- Mastery earned this mission, settled only on completion (S09-034).
		pendingMastery = {},
	}
end
local cooldownsByUser: { [number]: { [string]: number } } = {}
function State.ensure(player: Player): PlayerState
	local existing = states[player]
	if existing then
		return existing
	end
	local s = State.buildDefaults()
	-- Ability cooldowns are keyed by UserId and shared by reference so they survive a rejoin on this server.
	local userId = player.UserId
	cooldownsByUser[userId] = cooldownsByUser[userId] or s.cooldowns
	s.cooldowns = cooldownsByUser[userId]
	states[player] = s
	return s
end

function State.get(player: Player): PlayerState?
	return states[player]
end

function State.clear(player: Player)
	states[player] = nil
end

function State.all(): { [Player]: PlayerState }
	return states
end

function State.setMission(ctx: MissionContext?)
	mission = ctx
end

function State.getMission(): MissionContext?
	return mission
end

return State

