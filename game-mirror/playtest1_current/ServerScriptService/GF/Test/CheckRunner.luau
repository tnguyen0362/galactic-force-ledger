--!strict
-- GF.Check: the single command that proves the project still works.
-- Run: require(game.ServerScriptService.GF.Test.CheckRunner).run()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CheckRunner = {}

local Shared = ReplicatedStorage.GF.Shared
local Configs = Shared.Configs

local ALLOWED_STATS = {
	ReloadSpeed = true, MaxShield = true, DodgeRecharge = true, MoveSpeed = true,
	ReviveSpeed = true, HealthRegen = true,
}
local ALLOWED_TIERS = { Standard = true, Specialist = true, Elite = true, Boss = true }
local ALLOWED_TARGETING = { Ground = true, Self = true }
local ALLOWED_DURATION = { Short = true, Standard = true, Extended = true }
local ALLOWED_AUG_SLOTS = { Core = true, Auxiliary = true, Ability = true }
local ALLOWED_AUG_APPLIES = { Universal = true, Category = true, Ability = true }

local errors: { string } = {}
local passed = 0

local function ok(condition: boolean, message: string)
	if condition then
		passed += 1
	else
		table.insert(errors, message)
	end
end

local function num(v: any): boolean
	return type(v) == "number" and v == v
end

local function uniqueIds(list: { any }, label: string)
	local seen: { [string]: boolean } = {}
	for _, entry in list do
		ok(type(entry.id) == "string" and entry.id ~= "", label .. ": entry missing id")
		if seen[entry.id] then
			ok(false, label .. ": duplicate id " .. tostring(entry.id))
		end
		seen[entry.id] = true
	end
end

function CheckRunner.run()
	errors = {}
	passed = 0

	-- 1. every shared module loads ------------------------------------------
	local function loadAll(container: Instance, prefix: string)
		for _, child in container:GetChildren() do
			if child:IsA("ModuleScript") then
				local success, result = pcall(require, child)
				ok(success, "require failed: " .. prefix .. child.Name .. " -> " .. tostring(result))
			elseif child:IsA("Folder") then
				loadAll(child, prefix .. child.Name .. ".")
			end
		end
	end
	loadAll(Shared, "Shared.")

	-- 2. configs present ----------------------------------------------------
	for _, name in { "Weapons", "Enemies", "Abilities", "Classes", "Difficulties", "Missions", "Economy", "Augments", "Requisitions", "Monetization" } do
		ok(Configs:FindFirstChild(name) ~= nil, "missing config: " .. name)
	end
	if #errors > 0 then
		return { ok = false, passed = passed, errors = errors }
	end

	local Weapons = require(Configs.Weapons)
	local Enemies = require(Configs.Enemies)
	local Abilities = require(Configs.Abilities)
	local Classes = require(Configs.Classes)
	local Difficulties = require(Configs.Difficulties)
	local Missions = require(Configs.Missions)
	local Economy = require(Configs.Economy)
	local Augments = require(Configs.Augments)
	local Requisitions = require(Configs.Requisitions)
	local Monetization = require(Configs.Monetization)
	local Constants = require(Shared.Constants)

	-- 3. ids unique ---------------------------------------------------------
	uniqueIds(Weapons.List, "Weapons")
	uniqueIds(Enemies.List, "Enemies")
	uniqueIds(Abilities.List, "Abilities")
	uniqueIds(Classes.List, "Classes")
	uniqueIds(Difficulties.List, "Difficulties")
	uniqueIds(Missions.List, "Missions")
	uniqueIds(Augments.List, "Augments")

	-- 4. weapons ------------------------------------------------------------
	for _, w in Weapons.List do
		ok(num(w.damage) and w.damage > 0, "weapon " .. w.id .. ": damage must be > 0")
		ok(num(w.rpm) and w.rpm > 0, "weapon " .. w.id .. ": rpm must be > 0")
		ok(num(w.magazine) and w.magazine > 0, "weapon " .. w.id .. ": magazine must be > 0")
		ok(num(w.reloadTime) and w.reloadTime > 0, "weapon " .. w.id .. ": reloadTime must be > 0")
		ok(w.fireMode == "Auto" or w.fireMode == "Semi", "weapon " .. w.id .. ": bad fireMode")
		ok(w.unlockRank >= 1 and w.unlockRank <= Economy.MaxRank, "weapon " .. w.id .. ": unlockRank out of range")
		ok(w.cost >= 0, "weapon " .. w.id .. ": negative cost")
		ok(w.coreAugmentSlots >= 0 and w.coreAugmentSlots <= 2, "weapon " .. w.id .. ": coreAugmentSlots out of range")
	end

	-- 5. enemies ------------------------------------------------------------
	for _, e in Enemies.List do
		ok(num(e.health) and e.health > 0, "enemy " .. e.id .. ": health must be > 0")
		ok(ALLOWED_TIERS[e.tier] == true, "enemy " .. e.id .. ": bad tier " .. tostring(e.tier))
		ok(type(e.behavior) == "string" and e.behavior ~= "", "enemy " .. e.id .. ": missing behavior")
		ok(num(e.weakPointMultiplier) and e.weakPointMultiplier >= 1, "enemy " .. e.id .. ": weakPointMultiplier must be >= 1")
	end

	-- 6. abilities ----------------------------------------------------------
	for _, a in Abilities.List do
		ok(num(a.cooldown) and a.cooldown > 0, "ability " .. a.id .. ": cooldown must be > 0")
		ok(num(a.maxActive) and a.maxActive >= 1, "ability " .. a.id .. ": maxActive must be >= 1")
		ok(ALLOWED_TARGETING[a.targeting] == true, "ability " .. a.id .. ": bad targeting")
		ok(a.unlockRank >= 1 and a.unlockRank <= Economy.MaxRank, "ability " .. a.id .. ": unlockRank out of range")
	end

	-- 7. classes + cross refs ----------------------------------------------
	for _, c in Classes.List do
		ok(ALLOWED_STATS[c.personal.stat] == true, "class " .. c.id .. ": unknown personal stat")
		ok(ALLOWED_STATS[c.team.stat] == true, "class " .. c.id .. ": unknown team stat")
		ok(c.personal.value > 0 and c.personal.value <= 0.5, "class " .. c.id .. ": personal value out of range")
		ok(c.team.value > 0 and c.team.value <= 0.5, "class " .. c.id .. ": team value out of range")
		ok(Weapons.get(c.suggested.primary) ~= nil, "class " .. c.id .. ": suggested weapon missing")
		ok(Abilities.get(c.suggested.ability) ~= nil, "class " .. c.id .. ": suggested ability missing")
		local cap = Classes.ModifierCaps[c.personal.stat]
		ok(cap ~= nil and c.personal.value <= cap, "class " .. c.id .. ": personal modifier exceeds cap")
	end

	-- 8. difficulties -------------------------------------------------------
	for _, d in Difficulties.List do
		ok(d.rewardMultiplier >= 1 and d.rewardMultiplier <= 4, "difficulty " .. d.id .. ": rewardMultiplier out of range")
		ok(d.enemyBudget >= 4 and d.enemyBudget <= 24, "difficulty " .. d.id .. ": enemyBudget out of range")
		ok(d.unlockRank >= 1 and d.unlockRank <= Economy.MaxRank, "difficulty " .. d.id .. ": unlockRank out of range")
		for players = 1, 4 do
			ok(Difficulties.ticketsFor(d.id, players) >= 0, "difficulty " .. d.id .. ": negative tickets")
		end
	end

	-- 9. missions -----------------------------------------------------------
	for _, m in Missions.List do
		ok(ALLOWED_DURATION[m.durationClass] == true, "mission " .. m.id .. ": bad durationClass")
		ok(type(m.primary) == "string" and m.primary ~= "", "mission " .. m.id .. ": missing primary objective text")
	end

	-- 10. economy -----------------------------------------------------------
	local lastXp = -1
	for rank = 1, 15 do
		local xp = Economy.RankXp[rank]
		ok(xp ~= nil and xp > lastXp, "economy: RankXp not strictly increasing at rank " .. rank)
		if xp then lastXp = xp end
	end
	for _, d in Difficulties.List do
		ok(Economy.PayoutByDifficulty[d.id] ~= nil, "economy: no payout for difficulty " .. d.id)
	end
	ok(Economy.rankForXp(0) == 1, "economy: rankForXp(0) must be 1")
	local payout = Economy.payout("Normal", true)
	ok(payout.credits > 0 and payout.xp > 0, "economy: Normal payout must be positive")
	local noPayout = Economy.payout("Normal", false)
	ok(noPayout.credits == 0 and noPayout.xp == 0, "economy: incomplete objective must pay 0")

	-- 11. augments ----------------------------------------------------------
	for _, a in Augments.List do
		ok(ALLOWED_AUG_SLOTS[a.slot] == true, "augment " .. a.id .. ": bad slot")
		ok(ALLOWED_AUG_APPLIES[a.applies] == true, "augment " .. a.id .. ": bad applies")
		ok(a.cost >= 0, "augment " .. a.id .. ": negative cost")
	end

	-- 11b. prototype monetization boundary ---------------------------------
	ok(Monetization.LivePaymentsEnabled ~= true, "monetization: live payments must remain disabled in prototype")
	ok(type(Monetization.Products) == "table" and #Monetization.Products >= 1, "monetization: missing product rows")
	uniqueIds(Monetization.Products, "Monetization")
	for _, product in ipairs(Monetization.Products) do
		ok(product.productId == Monetization.PlaceholderProductId, "monetization " .. product.id .. ": must use placeholder product id")
		ok(product.enabled ~= true, "monetization " .. product.id .. ": placeholder product must be disabled")
		ok(product.nonRandom == true, "monetization " .. product.id .. ": product must be non-random")
		ok(product.approvedConvenience == true, "monetization " .. product.id .. ": product must be approved convenience")
		ok(product.kind == "requisitionUnlock", "monetization " .. product.id .. ": unsupported prototype product kind")
		ok(Requisitions.get(product.grantRequisition) ~= nil, "monetization " .. product.id .. ": grant requisition missing")
	end

	-- 12. constants ---------------------------------------------------------
	ok(Constants.Squad.MaxPlayers == 4, "constants: MaxPlayers must be 4")
	ok(Constants.Vitals.ShieldRegenDelay < Constants.Vitals.HealthRegenDelay, "constants: shield must regen before health")
	ok(Constants.Movement.SprintSpeed > Constants.Movement.WalkSpeed, "constants: sprint must exceed walk")

	-- 13. remotes -----------------------------------------------------------
	local RemoteService = require(ServerScriptService.GF.Services.RemoteService)
	RemoteService.ensureRemotes()
	local Remotes = require(Shared.Remotes)
	local container = ReplicatedStorage.GF.Remotes
	for _, name in Remotes.Names do
		local r = container:FindFirstChild(name)
		ok(r ~= nil and r:IsA("RemoteEvent"), "remote missing or wrong class: " .. name)
	end
	for _, name in Remotes.Functions do
		local r = container:FindFirstChild(name)
		ok(r ~= nil and r:IsA("RemoteFunction"), "remote missing or wrong class: " .. name)
	end
	for _, child in container:GetChildren() do
		ok(table.find(Remotes.Names, child.Name) ~= nil or table.find(Remotes.Functions, child.Name) ~= nil,
			"unregistered remote in folder: " .. child.Name)
	end

	-- 9. authored spec conformance ------------------------------------------
	-- Every value below is transcribed from GOAL_2026-11-24.md, so a config edit that silently drifts from
	-- the specification fails at boot instead of waiting for a human to notice. Seven defects found this
	-- session were exactly this: a number that disagreed with the spec and nobody had compared them.
	-- Rank and cost are deliberately NOT asserted: the authored table (L52-L59) and the prose arsenal list
	-- (L393-L397) contradict each other on those fields for AR-01, SG-04, MR-07 and LMG-12, and the config
	-- currently follows the prose. Asserting them would emit four false positives.
	local drift = {}
	local function near(got: any, want: number): boolean
		return type(got) == "number" and math.abs(got - want) < 1e-6
	end
	local function specNum(label: string, got: any, want: number)
		if near(got, want) then
			passed += 1
		else
			table.insert(errors, string.format("spec drift: %s = %s, spec says %s", label, tostring(got), tostring(want)))
			table.insert(drift, string.format("%s=%s(want %s)", label, tostring(got), tostring(want)))
		end
	end
	local SPEC_WEAPONS = {
		AR01 = { damage = 18, rpm = 600, magazine = 28, reserve = 168, reloadTime = 2.1, falloffStart = 90, falloffEnd = 240, falloffMin = 0.55 },
		SMG03 = { damage = 13, rpm = 850, magazine = 36, reserve = 216, reloadTime = 1.7, falloffStart = 45, falloffEnd = 150, falloffMin = 0.40 },
		LMG12 = { damage = 17, rpm = 660, magazine = 75, reserve = 225, reloadTime = 3.7, falloffStart = 85, falloffEnd = 230, falloffMin = 0.50 },
		SG04 = { damage = 96, rpm = 72, magazine = 6, reserve = 42, reloadTime = 2.8, falloffStart = 22, falloffEnd = 75, falloffMin = 0.25 },
		MR07 = { damage = 51, rpm = 150, magazine = 12, reserve = 72, reloadTime = 2.4, falloffStart = 150, falloffEnd = 350, falloffMin = 0.70 },
		GL22 = { damage = 110, rpm = 50, magazine = 4, reserve = 16, reloadTime = 3.1, radius = 13 },
		RL09 = { damage = 205, rpm = 24, magazine = 1, reserve = 7, reloadTime = 3.4, radius = 10 },
		P01 = { damage = 22, rpm = 300, magazine = 12, reserve = 72, reloadTime = 1.5, falloffStart = 55, falloffEnd = 170, falloffMin = 0.50 },
	}
	for id, want in pairs(SPEC_WEAPONS) do
		local w = Weapons.get(id)
		if not w then
			table.insert(errors, "spec drift: weapon " .. id .. " missing from config")
			table.insert(drift, id .. "=MISSING")
		else
			for field, value in pairs(want) do
				local got = w[field]
				if field == "radius" then
					got = w.explosive and w.explosive.radius
				end
				specNum(id .. "." .. field, got, value)
			end
		end
	end
	-- Ability cooldowns and radii that the spec states numerically (L75-L78).
	local SPEC_ABILITIES = {
		Airstrike = { cooldown = 90 },
		DomeShield = { cooldown = 70 },
		Sentry = { cooldown = 100, radius = 65, damage = 10 },
		OrbitalStrike = { cooldown = 150, radius = 13, damage = 390 },
		OrbitalLance = { cooldown = 165, radius = 6, damage = 420 },
		ReflectiveBarrier = { cooldown = 85, radius = 10 },
	}
	local abilityRows = Abilities.List or Abilities
	for id, want in pairs(SPEC_ABILITIES) do
		local found = nil
		for _, entry in pairs(abilityRows) do
			if type(entry) == "table" and entry.id == id then found = entry break end
		end
		if not found then
			table.insert(errors, "spec drift: ability " .. id .. " missing from config")
			table.insert(drift, id .. "=MISSING")
		else
			for field, value in pairs(want) do specNum(id .. "." .. field, found[field], value) end
		end
	end
	-- Boss base HP (L101-L102). Shield is not asserted: the spec gives a single HP figure for bosses.
	local SPEC_BOSSES = { BastionWalker = 3600, HighMarshalVeyr = 7200 }
	local enemyRows = Enemies.List or Enemies
	for id, wantHp in pairs(SPEC_BOSSES) do
		local found = nil
		for _, entry in pairs(enemyRows) do
			if type(entry) == "table" and entry.id == id then found = entry break end
		end
		if not found then
			table.insert(errors, "spec drift: boss " .. id .. " missing from config")
			table.insert(drift, id .. "=MISSING")
		else
			specNum(id .. ".health", found.health, wantHp)
		end
	end
	-- 10. authored Constants conformance --------------------------------------
	-- Constants is not a Configs module, so the section above never covered it. That is exactly why
	-- Combat.DownedTimeout (45 against the spec's 60) and Combat.ReviveDuration (3.5 against "hold revive 3s")
	-- drifted unnoticed through every build since. Ranges are asserted where the spec gives a range.
	local Constants = require(Shared.Constants)
	local function specRange(label: string, got: any, min: number, max: number)
		if type(got) == "number" and got >= min and got <= max then
			passed += 1
		else
			table.insert(errors, string.format("spec drift: %s = %s, spec %s-%s", label, tostring(got), tostring(min), tostring(max)))
			table.insert(drift, string.format("%s=%s(want %s-%s)", label, tostring(got), tostring(min), tostring(max)))
		end
	end
	local CM = Constants.Movement or {}
	local CV = Constants.Vitals or {}
	local CC = Constants.Combat or {}
	specRange("WalkSpeed", CM.WalkSpeed, 17, 18)
	specRange("SprintSpeed", CM.SprintSpeed, 24, 24)
	-- AdsSpeed and RollDistance are deliberately NOT asserted: a project-wide scan found zero consumers for
	-- either, so asserting them would certify dead config (the DownedTimeout mistake). AdsSpeed is a real gap -
	-- nothing applies it, so aiming does not slow movement as the spec requires. See evidence/v481.
	specRange("AdsSpeed", CM.AdsSpeed, 12, 14)
	specRange("RollCharges", CM.RollCharges, 2, 2)
	specRange("RollDuration", CM.RollDuration, 0.55, 0.55)
	specRange("HealthMax", CV.HealthMax, 100, 100)
	specRange("ShieldMax", CV.ShieldMax, 100, 100)
	specRange("ShieldRegenDelay", CV.ShieldRegenDelay, 4, 4)
	specRange("HealthRegenDelay", CV.HealthRegenDelay, 9, 9)
	specRange("DownedTimeout", CC.DownedTimeout, 60, 60)
	specRange("ReviveDuration", CC.ReviveDuration, 3, 3)
	-- Extraction defense countdown: spec default 75s, range 60-90 by difficulty/variant.
	local CMiss = require(Shared.Constants).Mission or {}
	specRange("ExtractionCountdown", CMiss.ExtractionCountdown, 60, 90)
	-- Regen rates and roll recharge, both pinned numerically in the spec: shield regenerate 25/s, HP after its
	-- 9s delay regenerate 8/s, and dodge charges recharge in ~3.5s.
	specRange("ShieldRegenRate", CV.ShieldRegenRate, 25, 25)
	specRange("HealthRegenRate", CV.HealthRegenRate, 8, 8)
	specRange("RollRecharge", CM.RollRecharge, 5, 5)
	-- Boss blueprint pity (GOAL L102): the two values used to be locals inside ProfileService, unreachable
	-- from any check. Now they live in Constants.Pity and are asserted like everything else.
	local CP = Constants.Pity or {}
	specRange("Pity.Target", CP.Target, 5, 5)
	specRange("Pity.Chance", CP.Chance, 0.15, 0.15)
	workspace:SetAttribute("GF_SpecDriftCount", #drift)
	workspace:SetAttribute("GF_SpecDrift", (#drift == 0) and "" or table.concat(drift, " ; "))

	-- Combat damage model (S04-018/S04-021). These are behaviour checks, not config assertions: they
	-- drive CombatService.damageEnemy against a scratch model so the shield maths cannot regress silently.
	local damageOk, damageErr = pcall(function()
		require(script.Parent.DamageChecks).run(ok)
	end)
	ok(damageOk, "damage checks failed to run: " .. tostring(damageErr))
	return { ok = #errors == 0, passed = passed, failed = #errors, errors = errors }
end

return CheckRunner

