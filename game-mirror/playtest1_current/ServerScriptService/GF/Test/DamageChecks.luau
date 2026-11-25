--!strict
-- Regression checks for the CombatService damage model (S04-018, S04-021).
-- Runs headless: builds a scratch Model carrying only the attributes damageEnemy reads, so no rig,
-- no mission and no player vitals are involved. The real numeric paths are exercised, which is the
-- point - the shield maths was verified by hand-probe twice and had no guard against regression.
local ServerScriptService = game:GetService("ServerScriptService")
local DamageChecks = {}

local function scratch(health: number, shield: number, armorFactor: number): Model
	local model = Instance.new("Model")
	model.Name = "DamageCheckScratch"
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", health)
	model:SetAttribute("Shield", shield)
	model:SetAttribute("MaxShield", shield)
	model:SetAttribute("ArmorFactor", armorFactor)
	model:SetAttribute("Dead", false)
	return model
end

-- returns { healthLost, shieldLost }
local function hit(model: Model, amount: number, mult: number): { number }
	local combat = require(ServerScriptService.GF.Services.CombatService)
	local h0 = model:GetAttribute("Health") or 0
	local s0 = model:GetAttribute("Shield") or 0
	combat.damageEnemy(model, amount, nil, "Torso", mult)
	return { h0 - (model:GetAttribute("Health") or 0), s0 - (model:GetAttribute("Shield") or 0) }
end

function DamageChecks.run(ok: (boolean, string) -> ())
	-- 1. unshielded body hit takes the whole amount
	local m1 = scratch(1000, 0, 1)
	local r1 = hit(m1, 18, 1)
	ok(math.abs(r1[1] - 18) < 1e-6, string.format("unshielded body: health -%.3f, expected -18", r1[1]))
	m1:Destroy()

	-- 2. a shield absorbs raw damage and leaves health untouched
	local m2 = scratch(1000, 100, 1)
	local r2 = hit(m2, 18, 1)
	ok(math.abs(r2[2] - 18) < 1e-6 and r2[1] == 0,
		string.format("shield absorbs: shield -%.3f health -%.3f, expected -18 / -0", r2[2], r2[1]))
	m2:Destroy()

	-- 3. the hit multiplier must NOT apply to shields (spec: no ordinary head bonus on shield)
	local m3 = scratch(1000, 100, 1)
	local r3 = hit(m3, 36, 2) -- fire() would pass base*mult
	ok(math.abs(r3[2] - 18) < 1e-6 and r3[1] == 0,
		string.format("head vs shield: shield -%.3f health -%.3f, expected -18 / -0 (not -36)", r3[2], r3[1]))
	m3:Destroy()

	-- 4. the hit multiplier DOES apply to unshielded health
	local m4 = scratch(1000, 0, 1)
	local r4 = hit(m4, 36, 2)
	ok(math.abs(r4[1] - 36) < 1e-6, string.format("head vs health: health -%.3f, expected -36", r4[1]))
	m4:Destroy()

	-- 5. armour applies to health, never to shield
	local m5 = scratch(1000, 100, 0.5)
	local r5 = hit(m5, 18, 1)
	ok(math.abs(r5[2] - 18) < 1e-6, string.format("armour vs shield: shield -%.3f, expected -18 (armour is health-only)", r5[2]))
	m5:Destroy()

	local m6 = scratch(1000, 0, 0.5)
	local r6 = hit(m6, 18, 1)
	ok(math.abs(r6[1] - 9) < 1e-6, string.format("armour vs health: health -%.3f, expected -9", r6[1]))
	m6:Destroy()

	-- 6. overflow consumes only what the shield could not, then applies mult and armour
	local m7 = scratch(1000, 10, 0.5)
	local r7 = hit(m7, 18, 1)
	ok(math.abs(r7[2] - 10) < 1e-6 and math.abs(r7[1] - 4) < 1e-6,
		string.format("overflow: shield -%.3f health -%.3f, expected -10 / -4", r7[2], r7[1]))
	m7:Destroy()

	-- 9/10. component damage: an area hit must damage one target ONCE no matter how many of its parts are
	-- inside the blast. detonate() walks ActiveActors and uses PrimaryPart distance, so this asserts the
	-- rule holds through the real code rather than by inspection.
	local folder = workspace:FindFirstChild("ActiveActors")
	local createdFolder = false
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ActiveActors"
		folder.Parent = workspace
		createdFolder = true
	end
	local function areaTarget(name: string, origin: Vector3, parts: number): Model
		local model = scratch(1000, 0, 1)
		model.Name = name
		for index = 1, parts do
			local part = Instance.new("Part")
			part.Name = "Body" .. index
			part.Size = Vector3.new(1, 1, 1)
			part.Anchored = true
			part.CanCollide = false
			-- Body1 sits exactly on the blast centre so the falloff scale is 1 and the expected damage is
			-- the weapon's full 100. Offsetting every part (the first version of this check) put the primary
			-- 0.5 studs out and produced 97.5, which was correct code and a wrong expectation.
			part.Position = origin + Vector3.new((index - 1) * 0.5, 0, 0)
			part.Parent = model
		end
		model.PrimaryPart = model:FindFirstChild("Body1")
		model.Parent = folder
		return model
	end
	local combat = require(ServerScriptService.GF.Services.CombatService)
	local blast = { damage = 100, explosive = { radius = 20 } }
	local near = areaTarget("DamageCheckNear", Vector3.new(0, 500, 0), 5)
	local far = areaTarget("DamageCheckFar", Vector3.new(0, 500, 80), 3)
	local hits = combat.detonate(Vector3.new(0, 500, 0), blast, nil)
	local nearLost = 1000 - (near:GetAttribute("Health") or 0)
	local farLost = 1000 - (far:GetAttribute("Health") or 0)
	ok(math.abs(nearLost - 100) < 1e-6,
		string.format("area hit on a 5-part target: health -%.1f, expected -100 (damaged once, not per part)", nearLost))
	ok(farLost == 0, string.format("target outside blast radius: health -%.1f, expected -0", farLost))
	ok(hits == 1, string.format("detonate hit count = %d, expected 1 (one target in radius)", hits))
	near:Destroy()
	far:Destroy()
	if createdFolder then
		folder:Destroy()
	end

	-- 11-13. reload arithmetic (S04-025): n = min(capacity - magazine, reserve). Pure function, so these
	-- are exact assertions rather than live probes. Before this existed the handler filled the magazine
	-- unconditionally and nothing consumed a reserve, i.e. ammunition was infinite.
	local combatReload = require(ServerScriptService.GF.Services.CombatService)
	ok(combatReload.reloadPlan(20, 28, 168) == 8, "reload plan: 20/28 with 168 reserve -> 8")
	ok(combatReload.reloadPlan(0, 28, 10) == 10, "reload plan: empty mag with 10 reserve -> 10 (reserve-limited)")
	ok(combatReload.reloadPlan(28, 28, 168) == 0, "reload plan: full magazine -> 0")
	ok(combatReload.reloadPlan(5, 28, 0) == 0, "reload plan: no reserve -> 0 (cannot reload from nowhere)")

	-- 14-16. state construction (place 539 regression guard). A throw inside the defaults table made
	-- State.create fail for EVERY player while the only symptom was "no state" wherever something read it.
	local stateOk, builtOrErr = pcall(function()
		return require(ServerScriptService.GF.Services.State).buildDefaults()
	end)
	ok(stateOk, "state defaults construct without error: " .. tostring(builtOrErr))
	if stateOk and type(builtOrErr) == "table" then
		local built = builtOrErr
		ok(type(built.ammo) == "number" and type(built.reserve) == "number",
			string.format("state defaults carry numeric ammo/reserve (ammo=%s reserve=%s)",
				tostring(built.ammo), tostring(built.reserve)))
		ok((tonumber(built.reserve) or 0) > 0,
			string.format("state defaults seed reserve from the catalogue (reserve=%s, expected 168)", tostring(built.reserve)))
	end

	-- 17-20. supply crate refill (S04-027): full magazine, reserve topped by one catalogue charge, capped
	-- at +60%, and never reduced. Pure function, so these are exact.
	local supply = require(ServerScriptService.GF.Services.SupplyService)
	local refill = supply.refillPlan(3, 28, 0, 168)
	ok(refill.ammo == 28, string.format("supply refills magazine: ammo %d, expected 28", refill.ammo))
	ok(refill.reserve == 168, string.format("supply tops reserve: %d, expected 168", refill.reserve))
	local capped = supply.refillPlan(0, 28, 260, 168)
	ok(capped.reserve == 268 and capped.reserve <= math.floor(168 * 1.6) + 168,
		string.format("supply respects the +60%% reserve cap: %d", capped.reserve))
	local noLoss = supply.refillPlan(28, 28, 268, 168)
	ok(noLoss.reserve == 268 and noLoss.ammo == 28,
		string.format("supply never reduces: ammo %d reserve %d", noLoss.ammo, noLoss.reserve))

	-- 21-23. grenade resupply (S08-047): a crate adds +2 charges, capped at the authored max of 3.
	local grenadePlan = require(ServerScriptService.GF.Services.SupplyService).grenadePlan
	ok(grenadePlan(0, 3) == 2, string.format("grenades: 0 -> %d, expected 2", grenadePlan(0, 3)))
	ok(grenadePlan(2, 3) == 3, string.format("grenades: 2 -> %d, expected 3 (capped)", grenadePlan(2, 3)))
	ok(grenadePlan(3, 3) == 3, string.format("grenades: 3 -> %d, expected 3 (never exceeds max)", grenadePlan(3, 3)))

	-- 24-26. EMP disable (S04-053). EMPStunUntil was written by GrenadeRuntime and read NOWHERE, so the
	-- "disable turret/robot subsystem" clause had no implementation. EnemyService.isStunned is now the single
	-- definition consumed by the enemy tick.
	local enemyService = require(ServerScriptService.GF.Services.EnemyService)
	local probe = Instance.new("Folder")
	probe:SetAttribute("EMPStunUntil", 100)
	ok(enemyService.isStunned(probe, 50) == true, "EMP stun is active before its expiry")
	ok(enemyService.isStunned(probe, 150) == false, "EMP stun ends after its expiry")
	ok(probe:GetAttribute("EMPStunUntil") == nil, "expired stun attribute is cleared, not left stale")
	probe:Destroy()
	local plain = Instance.new("Folder")
	ok(enemyService.isStunned(plain, 50) == false, "no stun attribute means not stunned")
	plain:Destroy()

	-- 7. the same raw damage is never charged twice
	local m8 = scratch(1000, 10, 1)
	local r8 = hit(m8, 18, 1)
	ok(math.abs((r8[1] + r8[2]) - 18) < 1e-6,
		string.format("no double charge: shield+health lost = %.3f, expected 18 total", r8[1] + r8[2]))
	m8:Destroy()
end

return DamageChecks

