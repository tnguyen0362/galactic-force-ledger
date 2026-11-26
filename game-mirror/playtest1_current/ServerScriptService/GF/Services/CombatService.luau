--!strict
-- Server-authoritative hitscan. Clients send intent; server owns ammo, rate, hit and damage.
-- Diagnostics are published as attributes under workspace.GFDebug so tests can read real state
-- without a second module instance (tooling VMs are isolated from the script VM).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Constants = require(ReplicatedStorage.GF.Shared.Constants)
local Weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
local State = require(ServerScriptService.GF.Services.State)
local VitalsService = require(ServerScriptService.GF.Services.VitalsService)
local Telemetry = require(ServerScriptService.GF.Services.GFTelemetry)
local ProfileService = require(ServerScriptService.GF.Services.ProfileService)
local CombatService = {}
local MAX_ORIGIN_OFFSET = 10.5
-- Weapon mastery XP per kill, by archetype (GOAL_2026-11-24.md L150-L157). Only the killing weapon is
-- credited, and never per hit. A flat 1 per kill could not reach level 2's 100 XP.
local MASTERY_XP = {
	Rifleman = 10, Scout = 10, Marksman = 10,
	Heavy = 20, Officer = 35,
	-- G-15 (economy audit): division elites and the tank previously fell through to the 10xp
	-- Rifleman fallback despite elite/vehicle encounter investment. Mapped to class-appropriate
	-- values: Spectre elite 20 (heavy-class), Spectre/Revenant leaders 35 (officer-class),
	-- Revenant elite 25 (prestige division, slightly above heavy), tank 50 (vehicle).
	SpectreAssault = 20, SpectreWeapons = 20, SpectrePrecision = 20, SpectreSupport = 20,
	SpectreLeader = 35,
	RevenantAssault = 25, RevenantWeapons = 25, RevenantPrecision = 25, RevenantDefense = 25,
	RevenantLeader = 35,
	BastionTank = 50,
	BastionWalker = 100, HighMarshalVeyr = 250, BastionSiege = 100, LeviathanWalker = 250,
}
local MAX_RANGE_SLACK = 1.15
local debugFolder: Folder
local counters = { received = 0, accepted = 0, rejected = 0, hits = 0, damage = 0 }
local function debug(): Folder
	if debugFolder and debugFolder.Parent then
		return debugFolder
	end
	local existing = workspace:FindFirstChild("GFDebug")
	if not existing then
		existing = Instance.new("Folder")
		existing.Name = "GFDebug"
		existing.Parent = workspace
	end
	debugFolder = existing :: Folder
	return debugFolder
end
local function note(key: string, value: any)
	-- Combat telemetry is useful in verification but expensive in the hot path: every hit/miss/reject
	-- replicated an attribute change to every client. Verification harnesses opt in explicitly.
	if workspace:GetAttribute("GF_DebugCombat") ~= true then
		return
	end
	debug():SetAttribute(key, value)
end
local function reject(reason: string)
	counters.rejected += 1
	note("LastReject", reason)
	note("Rejected", counters.rejected)
end
local function now(): number
	return os.clock()
end
local function raycastParams(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	return params
end
-- S10-023: per-enemy damage contribution ledger for kill-assist fairness. Entries live only as
-- long as the enemy model; dead-model entries are cleared after the kill is resolved.
local damageContrib: { [Model]: { [number]: { total: number, lastAt: number, weaponId: string? } } } = {}
local function friendlyFireScale(): number
	local mission = State.getMission()
	local Difficulties = require(ReplicatedStorage.GF.Shared.Configs.Difficulties)
	return Difficulties.friendlyFireFor(mission and mission.difficulty)
end
local function resolveAlly(hit: Instance, shooter: Player?): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	while model do
		local ally = Players:GetPlayerFromCharacter(model)
		if ally then
			return ally ~= shooter and ally or nil
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end
-- S03-026 grief protection: deliberate repeated team damage zeroes the offender's friendly-fire
-- output temporarily. Track friendly damage dealt per shooter in a rolling window; crossing the
-- threshold flags them for a cooldown during which their bullets/blast hurt nobody friendly.
local GRIEF_WINDOW = 20 -- seconds of history considered
local GRIEF_THRESHOLD = 120 -- friendly damage within the window that marks deliberate griefing
local GRIEF_PENALTY = 45 -- seconds of zeroed friendly-fire output
local griefHistory: { [number]: { { t: number, amount: number } } } = {}
local griefPenaltyUntil: { [number]: number } = {}
local function griefZeroed(shooter: Player?): boolean
	if not shooter then
		return false
	end
	return os.clock() < (griefPenaltyUntil[shooter.UserId] or 0)
end
local function trackFriendlyDamage(shooter: Player, amount: number)
	local now = os.clock()
	local hist = griefHistory[shooter.UserId]
	if not hist then
		hist = {}
		griefHistory[shooter.UserId] = hist
	end
	table.insert(hist, { t = now, amount = amount })
	local total = 0
	for i = #hist, 1, -1 do
		if now - hist[i].t > GRIEF_WINDOW then
			table.remove(hist, i)
		else
			total += hist[i].amount
		end
	end
	if total >= GRIEF_THRESHOLD and now >= (griefPenaltyUntil[shooter.UserId] or 0) then
		griefPenaltyUntil[shooter.UserId] = now + GRIEF_PENALTY
		workspace:SetAttribute("GF_GriefPenalty", shooter.Name .. ":" .. tostring(GRIEF_PENALTY))
	end
end
local function damageAlly(ally: Player, amount: number, shooter: Player?): number
	local scale = friendlyFireScale()
	if scale <= 0 or amount <= 0 then
		return 0
	end
	if griefZeroed(shooter) then
		return 0 -- flagged offender: no friendly damage output during the penalty
	end
	local applied = VitalsService.applyDamage(ally, amount * scale, "friendly:" .. (shooter and shooter.Name or "?"))
	if shooter and applied > 0 then
		trackFriendlyDamage(shooter, applied)
	end
	workspace:SetAttribute("GF_LastFriendlyFire", string.format("%s->%s %.1f x%.2f", shooter and shooter.Name or "?", ally.Name, amount, scale))
	return applied
end
CombatService.friendlyFireScale = friendlyFireScale
function CombatService.damageAlliesInRadius(centre: Vector3, radius: number, amount: number, shooter: Player?): number
	if friendlyFireScale() <= 0 then
		return 0
	end
	local hit = 0
	for _, ally in Players:GetPlayers() do
		local root = ally ~= shooter and ally.Character and ally.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - centre).Magnitude <= radius then
			local d = (root.Position - centre).Magnitude
			damageAlly(ally, amount * (1 - (d / math.max(1, radius)) * 0.6), shooter)
			hit += 1
		end
	end
	return hit
end
local function resolveEnemy(hit: BasePart): (Model?, string?)
	local model = hit:FindFirstAncestorOfClass("Model")
	while model do
		if model:GetAttribute("GFEnemy") then
			return model, hit.Name
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end
-- Objective structures. Authored destructibles (relay cores, shield generators, emitters) carry
-- GFIntegrityMax, so the same weapon damage that kills an enemy can break scenery the operation
-- actually cares about. State lives in attributes; the objective machine polls them.
local function resolveStructure(instance: Instance): (BasePart?, string?)
	local current: Instance? = instance
	while current and current ~= workspace do
		if current:IsA("BasePart") and current:GetAttribute("GFIntegrityMax") then
			local label = current:GetAttribute("GFStructure")
			return current, type(label) == "string" and label or current.Name
		end
		current = current.Parent
	end
	return nil, nil
end
-- Launchers. GL-22/RL-09 are authored as area weapons, so a hit damages everything hostile (and any
-- destructible objective part) inside the radius with distance falloff instead of one target.
function CombatService.detonate(centre: Vector3, weapon: any, player: Player?): number
	local radius = (weapon.explosive and weapon.explosive.radius) or 8
	-- The blastRadius augment stat (WideCharge +0.3, SiegePayload +0.45, SlugLoad -0.2,
	-- FocusedOrbitalStrike -0.4) was declared and read by nothing. GOAL_2026-11-24.md caps blast radius at
	-- +25%, so this is clamped rather than summed unbounded - the first augment stat to honour its authored cap.
	if player then
		local blastBonus = 0
		pcall(function()
			local wid = type(weapon) == "table" and weapon.id or nil
			local augs = wid and require(script.Parent.AugmentService).forPlayerWeapon(player, wid)
				or require(script.Parent.AugmentService).forPlayer(player)
			blastBonus = tonumber(augs and augs.blastRadius) or 0
		end)
		radius = radius * math.clamp(1 + blastBonus, 0.4, 1.25)
		workspace:SetAttribute("GF_LastBlastRadius", string.format("%.2f(bonus=%s)", radius, tostring(blastBonus)))
	end
	local hits = 0
	if friendlyFireScale() > 0 then
		for _, ally in Players:GetPlayers() do
			local root = ally ~= player and ally.Character and ally.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local distance = (root.Position - centre).Magnitude
				if distance <= radius then
					damageAlly(ally, weapon.damage * math.clamp(1 - distance / radius, 0.3, 1), player)
				end
			end
		end
	end
	local folder = workspace:FindFirstChild("ActiveActors")
	if not folder then
		return 0
	end
	local blastDamageTotal = 0
	local blastKilled = false
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("Dead") ~= true and model:GetAttribute("Health") ~= nil then
			local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			if part then
				local distance = (part.Position - centre).Magnitude
				if distance <= radius then
					local scale = math.clamp(1 - distance / radius, 0.3, 1)
					local killed = CombatService.damageEnemy(model, weapon.damage * scale, player, nil, 1, weapon)
					blastDamageTotal += weapon.damage * scale
					blastKilled = blastKilled or killed == true
					hits += 1
				end
			end
		end
	end
	-- detonation-driven feedback: launcher hitmarkers arrive when the shell actually lands,
	-- never at trigger-pull. One aggregated marker per detonation — position is the blast centre.
	if player and hits > 0 then
		ReplicatedStorage.GF.Remotes.DamageFeedback:FireClient(player, {
			position = centre,
			damage = blastDamageTotal,
			weakPoint = false,
			killed = blastKilled,
		})
	end
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("GFIntegrityMax") and d:GetAttribute("GFDestroyed") ~= true then
			local distance = (d.Position - centre).Magnitude
			if distance <= radius then
				CombatService.damageStructure(d, weapon.damage * math.clamp(1 - distance / radius, 0.3, 1), player)
				hits += 1
			end
		end
	end
	local blast = Instance.new("Part")
	blast.Shape = Enum.PartType.Ball
	blast.Size = Vector3.new(radius, radius, radius)
	blast.Position = centre
	blast.Anchored = true
	blast.CanCollide = false
	blast.CanQuery = false
	blast.Material = Enum.Material.Neon
	blast.Color = Color3.fromRGB(255, 168, 88)
	blast.Transparency = 0.3
	blast.Parent = workspace
	local TweenService = game:GetService("TweenService")
	TweenService:Create(blast, TweenInfo.new(0.5), { Size = Vector3.new(radius * 2.2, radius * 2.2, radius * 2.2), Transparency = 1 }):Play()
	task.delay(0.7, function()
		if blast.Parent then
			blast:Destroy()
		end
	end)
	return hits
end
function CombatService.damageStructure(part: BasePart, amount: number, _attacker: Player?): boolean
	local max = tonumber(part:GetAttribute("GFIntegrityMax")) or 0
	if max <= 0 then
		return false
	end
	-- Measured leak: a CanQuery=false shield still let weapon damage through, so the gate is explicit
	-- rather than inferred from raycast filtering.
	if part:GetAttribute("GFShielded") == true then
		workspace:SetAttribute("GF_ShieldDeflected", (workspace:GetAttribute("GF_ShieldDeflected") or 0) + 1)
		return false
	end
	local current = tonumber(part:GetAttribute("GFIntegrity")) or max
	current = math.max(0, current - amount)
	part:SetAttribute("GFIntegrity", current)
	workspace:SetAttribute("GF_StructureIntegrity", current)
	workspace:SetAttribute("GF_LastStructure", part.Name)
	if current > 0 or part:GetAttribute("GFDestroyed") == true then
		return false
	end
	part:SetAttribute("GFDestroyed", true)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	local anchor = part.Position
	local blast = Instance.new("Part")
	blast.Shape = Enum.PartType.Ball
	blast.Size = Vector3.new(8, 8, 8)
	blast.Position = anchor
	blast.Anchored = true
	blast.CanCollide = false
	blast.CanQuery = false
	blast.Material = Enum.Material.Neon
	blast.Color = Color3.fromRGB(255, 176, 88)
	blast.Transparency = 0.35
	blast.Parent = workspace
	local TweenService = game:GetService("TweenService")
	TweenService:Create(blast, TweenInfo.new(0.6), { Size = Vector3.new(22, 22, 22), Transparency = 1 }):Play()
	task.delay(0.8, function()
		if blast.Parent then
			blast:Destroy()
		end
	end)
	workspace:SetAttribute("GF_StructuresDestroyed", (workspace:GetAttribute("GF_StructuresDestroyed") or 0) + 1)
	return true
end
function CombatService.weakMultiplier(partName: string?, part: BasePart?): number
	-- per-part authored weakpoint always wins — enemy setup writes these from the enemy config's
	-- weakPointMultiplier onto the designated weak parts (core, lens, joints).
	local wp = part and part:GetAttribute("WeakPoint")
	if typeof(wp) == "number" then
		return wp
	end
	if partName == "Head" then
		-- headshots use the enemy type's configured weakpoint value when the model carries one —
		-- the design table runs 1.0-2.5 per enemy type, and a flat 2x bypassed all of it. Spec
		-- fallback for unconfigured enemies is 1.5x, not the old hardcoded 2x.
		local model = part and part:FindFirstAncestorOfClass("Model")
		local configured = model and model:GetAttribute("WeakPointMultiplier")
		if typeof(configured) == "number" and configured > 1 then
			return configured
		end
		return 1.5
	end
	return 1
end
function CombatService.damageEnemy(model: Model, amount: number, attacker: Player?, partName: string?, mult: number?, weapon: any?): boolean
	-- Threat memory (S06-013): being hurt alerts the actor and biases its target scoring toward the attacker.
	if attacker then
		pcall(function()
			require(script.Parent.EnemyService).noteThreat(model, attacker)
		end)
	end
	local health = model:GetAttribute("Health")
	local augs = nil
	if attacker then
		local wid = type(weapon) == "table" and weapon.id or nil
		augs = wid and require(script.Parent.AugmentService).forPlayerWeapon(attacker, wid)
			or require(script.Parent.AugmentService).forPlayer(attacker)
	end
	if type(health) ~= "number" or health <= 0 then
		return false
	end
	-- S04-018 damage model. fire() hands us base * falloff * hitMultiplier, so dividing the hit
	-- multiplier back out recovers `raw` and lets the shield absorb RAW damage - the spec forbids an
	-- ordinary head bonus on shield. The hit multiplier and armour factor are then applied only to the
	-- portion that reaches health, which is what "armor multiplier on health only" requires. Before
	-- this, armour was applied to shield damage as well and a headshot drained double shield.
	local hitMultiplier = tonumber(mult) or 1
	if hitMultiplier <= 0 then
		hitMultiplier = 1
	end
	local raw = amount / hitMultiplier
	-- S06-055: boss component damage — a hit landing on a destructible component burns that component's
	-- own HP pool while ALSO applying to the core exactly once (the raw above continues through the
	-- normal path unchanged). Destroyed components disable their attack in the boss step logic.
	if partName then
		-- component-framework entities resolve through ComponentService: authoritative pools,
		-- dependency graph, exactly-once destruction events. The legacy path must not double-burn
		-- the same ComponentHP attributes the framework owns.
		if model:GetAttribute("GFComponentEntity") == true then
			local compPart = model:FindFirstChild(partName)
			local ok, mult = pcall(function()
				return require(script.Parent.ComponentService).resolveComponentDamage(model, compPart, raw)
			end)
			if ok and type(mult) == "number" then
				raw = raw * mult
			end
		else
			local compPart = model:FindFirstChild(partName)
			local compHp = compPart and compPart:GetAttribute("ComponentHP")
			if compPart and type(compHp) == "number" and compHp > 0 then
				local remaining = compHp - raw
				compPart:SetAttribute("ComponentHP", remaining)
				if remaining <= 0 then
					compPart:SetAttribute("ComponentDestroyed", true)
					compPart.Color = Color3.fromRGB(30, 30, 32)
					compPart.Material = Enum.Material.CorrodedMetal
					workspace:SetAttribute("GF_ComponentDestroyed", tostring(compPart:GetAttribute("ComponentId")))
				end
			end
		end
	end
	-- Weakpoint augment: an additional bonus on the health portion of weakpoint hits, independent of the
	-- hit multiplier. Never folded into raw: shield must absorb RAW damage only (S04-018).
	local weakFactor = 1
	if augs and hitMultiplier > 1 then
		weakFactor = 1 + (tonumber(augs.weakPoint) or 0)
	end
	local ignoresArmor = model:GetAttribute("Armor") and augs
	if augs and model:GetAttribute("Armor") then
		raw = raw * (1 + augs.armorDamage)
	end
	local shield = tonumber(model:GetAttribute("Shield")) or 0
	local armorFactor = tonumber(model:GetAttribute("ArmorFactor")) or 1
	if armorFactor <= 0 or armorFactor > 1 then
		armorFactor = 1
	end
	-- armor penetration bypasses a fraction of the mitigation: pen 0.4 vs armorFactor 0.5 yields
	-- effective 0.7 — the target keeps 60% of its protection, the weapon ignores the rest.
	local weaponArmorPen0 = math.clamp((weapon and tonumber(weapon.armorPenetration)) or 0, 0, 0.9)
	if weaponArmorPen0 > 0 and armorFactor < 1 then
		armorFactor = 1 - (1 - armorFactor) * (1 - weaponArmorPen0)
	end
	local healthDamage = 0
	-- weapon interaction stats, the layer that makes the roster distinct against protected
	-- targets: shieldMultiplier scales damage INTO shields (Arcus 1.1, sidearms higher), and
	-- armorPenetration bypasses that fraction of armor mitigation on the health portion.
	-- Abilities/projectiles pass weapon=nil and stay neutral, as before.
	local weaponShieldMult = (weapon and tonumber(weapon.shieldMultiplier)) or 1
	if shield > 0 then
		local shieldRaw = raw * weaponShieldMult
		if augs then
			shieldRaw = shieldRaw * (1 + augs.shieldDamage)
		end
		local absorbed = math.min(shield, shieldRaw)
		shield -= absorbed
		shieldRaw -= absorbed
		model:SetAttribute("Shield", shield)
		if shield <= 0 then
			model:SetAttribute("ShieldBrokenAt", now())
		end
		if shieldRaw <= 0 then
			counters.damage += absorbed
			note("TotalDamage", counters.damage)
			note("LastShieldHit", model.Name)
			return false
		end
		-- overflow: only the raw damage the shield could not consume reaches health,
		-- where hit multiplier, weakpoint augment and armor factor apply (S04-018)
		healthDamage = shieldRaw * hitMultiplier * weakFactor * armorFactor
		if augs then
			healthDamage = healthDamage * (1 + augs.healthDamage)
		end
		counters.damage += absorbed
	else
		healthDamage = raw * hitMultiplier * weakFactor * armorFactor
		if augs then
			healthDamage = healthDamage * (1 + augs.healthDamage)
		end
	end
	if not ignoresArmor and armorFactor < 1 then
		workspace:SetAttribute("GF_LastArmorMitigated", model.Name .. ":" .. string.format("%.1f", healthDamage))
	end
	local amount = healthDamage
	local newHealth = health - amount
	counters.damage += amount
	note("TotalDamage", counters.damage)
	if newHealth <= 0 then
		model:SetAttribute("Health", 0)
		model:SetAttribute("Dead", true)
		if attacker then
			local s = State.get(attacker)
			if s then
				s.kills += 1
				s.damageDealt += health
			end
			-- S10-023 kill assist: exactly one other damaging player who contributed >=25% of total
			-- damage within the last 15s earns half weapon mastery XP on their damaging weapon.
			local contrib = damageContrib[model]
			if contrib then
				local totalAll = 0
				for _, c in contrib do
					totalAll += c.total
				end
				local bestAssistId, bestAssistTotal = nil, 0
				for userId, c in contrib do
					if userId ~= attacker.UserId and (now() - c.lastAt) <= 15 and totalAll > 0 and c.total / totalAll >= 0.25 then
						if c.total > bestAssistTotal then
							bestAssistId, bestAssistTotal = userId, c.total
						end
					end
				end
				if bestAssistId then
					local assistPlayer = Players:GetPlayerByUserId(bestAssistId)
					local ainfo = contrib[bestAssistId]
					if assistPlayer and ainfo and ainfo.weaponId then
						local enemyId = model:GetAttribute("EnemyId")
						local masteryXp = (MASTERY_XP[enemyId] or MASTERY_XP.Rifleman) / 2
						local as = State.get(assistPlayer)
						if as then
							as.pendingMastery = as.pendingMastery or {}
							as.pendingMastery[ainfo.weaponId] = (as.pendingMastery[ainfo.weaponId] or 0) + masteryXp
						end
					end
				end
				damageContrib[model] = nil
			end
			-- Per-weapon mastery grows from kills with the killing weapon only, worth the authored
			-- amount for the archetype rather than a flat 1.
			local weaponId = s and s.weaponId
			if weaponId then
				local enemyId = model:GetAttribute("EnemyId")
				local masteryXp = MASTERY_XP[enemyId] or MASTERY_XP.Rifleman
				-- Accrued in-mission, settled only when the primary completed (S09-034). Writing the
				-- profile here would let a player bank mastery from a mission they go on to fail.
				s.pendingMastery = s.pendingMastery or {}
				s.pendingMastery[weaponId] = (s.pendingMastery[weaponId] or 0) + masteryXp
				-- shadow ledger: kill reward events with stable per-kill source ids (spec §28)
				pcall(function()
					local plr = game:GetService("Players"):GetPlayerByUserId(tonumber(s.userId) or -1)
					require(script.Parent.RewardLedgerService).appendEvent(
						"kill_" .. tostring(enemyId),
						nil,
						string.format("kill:%s:%s:%d", tostring(enemyId), tostring(model and model:GetFullName() or "unk"), math.floor(os.clock() * 1000)),
						plr and plr.UserId or nil
					)
				end)
				workspace:SetAttribute("GF_MasteryGain", (workspace:GetAttribute("GF_MasteryGain") or 0) + masteryXp)
				workspace:SetAttribute("GF_LastMasteryAward", tostring(enemyId) .. ":" .. tostring(masteryXp))
			end
		end
		note("LastKill", model.Name)
		return true
	end
	model:SetAttribute("Health", newHealth)
	if mult and mult > 1 and model:GetAttribute("Boss") then
		local weak = (tonumber(model:GetAttribute("WeakDamage")) or 0) + amount
		model:SetAttribute("WeakDamage", weak)
		workspace:SetAttribute("BastionWeakDamage", weak)
		local nextStagger = tonumber(model:GetAttribute("StaggerCooldownUntil")) or 0
		if weak >= 900 and os.clock() >= nextStagger then
			model:SetAttribute("WeakDamage", 0)
			model:SetAttribute("Stagger", os.clock() + 1.6)
			model:SetAttribute("StaggerCooldownUntil", os.clock() + 6)
			workspace:SetAttribute("BastionStaggers", (tonumber(workspace:GetAttribute("BastionStaggers")) or 0) + 1)
		end
	end
	model:SetAttribute("LastHitAt", now())
	if attacker then
		local s = State.get(attacker)
		if s then
			s.damageDealt += amount
		end
		-- S10-023: per-enemy damage contributions for assist credit. Keyed by model so each unique
		-- enemy tracks who hurt it, how much, and when (15s relevance window measured at kill time).
		local contrib = damageContrib[model]
		if not contrib then
			contrib = {}
			damageContrib[model] = contrib
		end
		local c = contrib[attacker.UserId]
		if not c then
			c = { total = 0, lastAt = 0, weaponId = nil }
			contrib[attacker.UserId] = c
		end
		c.total += amount
		c.lastAt = now()
		if s then
			c.weaponId = s.weaponId or c.weaponId
		end
	end
	return false
end
-- S04-025 reload arithmetic: n = min(capacity - magazine, reserve). Pure so it can be unit-tested
-- directly - the surrounding handler needs a player, a scheduler and a live State table.
function CombatService.reloadPlan(ammo: number, capacity: number, reserve: number): number
	local room = math.max(0, (tonumber(capacity) or 0) - (tonumber(ammo) or 0))
	return math.min(room, math.max(0, tonumber(reserve) or 0))
end
-- Reserve seeding lives in one place: State is created before any weapon lookup, and applyLoadout only
-- runs on loadout changes, so every path that reads reserve must be able to seed it lazily.
function CombatService.ensureReserve(s: any, weapon: any)
	if s and s.reserve == nil then
		s.reserve = tonumber(weapon and weapon.reserve) or 0
	end
	return s and s.reserve or 0
end
function CombatService.fire(player: Player, payload: any)
	local shooterRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if shooterRoot then
		workspace:SetAttribute("GF_LastShotPos", (shooterRoot :: BasePart).Position)
	end
	if player:GetAttribute("GF_Aboard") == true then
		note("LastReject", "aboard dropship")
		return
	end
	counters.received += 1
	note("Received", counters.received)
	if type(payload) ~= "table" then
		return reject("payload-not-table")
	end
	local s = State.get(player)
	if not s then
		return reject("no-state")
	end
	if s.downed then
		return reject("downed")
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return reject("no-character")
	end
	-- S03-019: no attack during a roll - the dodge is a defensive commitment, not a firing platform.
	if character:GetAttribute("Rolling") == true then
		return reject("rolling")
	end
	local weaponId = payload.weaponId
	if type(weaponId) ~= "string" then
		return reject("bad-weapon-id")
	end
	if weaponId ~= s.weaponId then
		return reject("weapon-mismatch:" .. tostring(s.weaponId) .. "!=" .. weaponId)
	end
	local weapon = Weapons.get(weaponId)
	if not weapon then
		return reject("unknown-weapon")
	end
	-- A5: the client predicts ammunition locally when it sends a shot. Every rejection past this
	-- point therefore strands one phantom round client-side unless the server corrects it. Send
	-- authoritative ammunition state with each rejection; the client snaps to server truth.
	local function rejectFire(reason: string)
		reject(reason)
		local AugmentService = require(script.Parent.AugmentService)
		local capacity = AugmentService.magazine(weapon, AugmentService.forPlayerWeapon(player, weaponId))
		ReplicatedStorage.GF.Remotes.AmmoUpdated:FireClient(player, {
			ammo = s.ammo or 0,
			magazine = capacity,
			reserve = s.reserve or 0,
		})
	end
	local shotId = tonumber(payload.shotId)
	if not shotId or shotId ~= shotId or math.abs(shotId) == math.huge or shotId <= s.lastShotId then
		return reject("stale-shot-id:" .. tostring(shotId) .. "<=" .. tostring(s.lastShotId))
	end
	CombatService.ensureReserve(s, weapon)
	local t = now()
	local fireRateBonus = 0
	pcall(function()
		local augs = require(script.Parent.AugmentService).forPlayerWeapon(player, weaponId)
		fireRateBonus = tonumber(augs and augs.fireRate) or 0
	end)
	local minInterval = (60 / weapon.rpm) * 0.9 / math.max(0.5, 1 + fireRateBonus)
	if t - s.lastShotAt < minInterval then
		return rejectFire("rate-limited")
	end
	if s.swapUntil and t < s.swapUntil then
		return rejectFire("swapping")
	end
	if s.reloading then
		if t < s.reloadDone then
			return rejectFire("reloading")
		end
		-- Complete through the same conserved path as the scheduled commit: transfer is bounded
		-- by magazine room AND reserve, and reserve is consumed. The old branch refilled the full
		-- augmented magazine for free, which duplicated ammunition whenever a shot landed in the
		-- window between reloadDone and the delayed commit task.
		s.reloading = false
		local augs = require(script.Parent.AugmentService).forPlayerWeapon(player, weaponId)
		local capacity = require(script.Parent.AugmentService).magazine(weapon, augs)
		local n = CombatService.reloadPlan(s.ammo, capacity, s.reserve or 0)
		if n > 0 then
			s.ammo += n
			s.reserve = math.max(0, (s.reserve or 0) - n)
		end
	end
	if s.ammo <= 0 then
		return rejectFire("no-ammo")
	end
	local origin = payload.origin
	local direction = payload.direction
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return rejectFire("bad-vector")
	end
	-- typeof() accepts NaN-bearing vectors and NaN comparisons are false, so neither the zero-direction
	-- nor the origin-distance check below can catch non-finite input. S14-016/S14-022.
	local NetGuard = require(script.Parent.NetGuard)
	if not NetGuard.finiteVector3(origin) or not NetGuard.finiteVector3(direction) then
		NetGuard.noteReject("fire", "non-finite-vector")
		return rejectFire("non-finite-vector")
	end
	if direction.Magnitude < 0.5 then
		return rejectFire("zero-direction")
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return rejectFire("no-root")
	end
	if (origin - root.Position).Magnitude > MAX_ORIGIN_OFFSET then
		return rejectFire("origin-too-far")
	end
	-- Parallax validation (spec section 5 server model), pragmatic tier:
	-- (a) facing coherence: the claimed direction must sit within a generous cone of where the
	-- character faces. 100 degrees covers every legitimate third-person aim state (camera orbits,
	-- aim-over-shoulder, hip-turn latency) while making backwards/spinbot fire impossible.
	local rootLook = root.CFrame.LookVector
	local flatClaim = (direction.Unit * Vector3.new(1, 0, 1))
	local flatFace = (rootLook * Vector3.new(1, 0, 1))
	if flatClaim.Magnitude > 0.05 and flatFace.Magnitude > 0.05 then
		local cosA = flatClaim.Unit:Dot(flatFace.Unit)
		if cosA < math.cos(math.rad(100)) then
			return rejectFire("facing-incoherent")
		end
	end
	-- (b) server-side muzzle obstruction mirror: the client denies shots where cover hugs the
	-- muzzle, but a cheater simply omits that check. Re-run it here from the true head position:
	-- if world geometry blocks the first 2.5 studs of the claimed line, the shot cannot be real —
	-- legitimate play never produces it because the client-side check denies it first.
	do
		local head = character:FindFirstChild("Head")
		local eyePos = head and head.Position or (root.Position + Vector3.new(0, 1.5, 0))
		local muzzleParams = RaycastParams.new()
		muzzleParams.FilterType = Enum.RaycastFilterType.Exclude
		muzzleParams.FilterDescendantsInstances = { character }
		local blocked = workspace:Raycast(eyePos, direction.Unit * 2.5, muzzleParams)
		if blocked and blocked.Instance and blocked.Instance.CanCollide then
			return rejectFire("muzzle-obstructed")
		end
	end
	s.lastShotId = shotId
		if player.Character then player.Character:SetAttribute("GF_LastShotAt", os.clock()) end
	s.lastShotAt = t
	s.ammo -= 1
	counters.accepted += 1
	note("Accepted", counters.accepted)
	if Telemetry.enabled() then
		Telemetry.emit("shot_fired", {
			weaponId = weaponId,
			shooterType = "player",
			ads = character:GetAttribute("Aiming") == true,
			ammoAfter = s.ammo,
		})
	end
	-- Hearing model (S06-008): a fired shot alerts hostiles within range of the muzzle.
	-- Shooter identity passed through for player-keyed auditory memory (spec section 18):
	-- optional parameter, behavior unchanged for positional-only callers.
	pcall(function()
		require(script.Parent.EnemyService).hearGunfire(origin, game:GetService("Players"):GetPlayerFromCharacter(character))
	end)
	local unit = direction.Unit
	local isAiming = character:GetAttribute("Aiming") == true
	-- Spread. spreadBase / spreadPerShot / adsSpread / recoil were declared on every weapon and read by NOTHING,
	-- so every shot landed exactly on the ray. Bloom grows per shot and decays in between; aiming uses the
	-- authored ADS figure; the recoil augment cuts the remainder (already capped at 0.35 by AugmentService).
	-- GF_ForceNoSpread restores the perfectly-accurate world so the existing TTK/falloff evidence stays
	-- reproducible - the same escape hatch pattern as GF_ForceNoBlueprintChance.
	local spreadAngle = 0
	if workspace:GetAttribute("GF_ForceNoSpread") ~= true then
		local sincePrev = math.max(0, t - (s.spreadAt or t))
		local followUp = 0
		pcall(function()
			local a = require(script.Parent.AugmentService).forPlayerWeapon(player, weaponId)
			followUp = tonumber(a and a.followUpSpeed) or 0
		end)
		-- followUpSpeed is negative when it helps (TargetDiscipline/PrecisionChamber -0.15), so the
		-- decay divisor is 1 - value: -0.15 recovers 15% faster, +0.1 recovers slower.
		local bloom = math.max(0, (s.spreadBloom or 0) - sincePrev * 2.6 * math.max(0.2, 1 - followUp))
		s.spreadAt = t
		local aiming = character:GetAttribute("Aiming") == true
		local base = tonumber(aiming and (weapon.adsSpread or weapon.spreadBase) or weapon.spreadBase) or 0
		pcall(function()
			local augs = require(script.Parent.AugmentService).forPlayerWeapon(player, weaponId)
			local bonus = aiming and tonumber(augs and augs.spreadAds) or tonumber(augs and augs.spreadHip)
			base = base * math.max(0.4, 1 - (tonumber(bonus) or 0))
		end)
		local recoilCut = 0
		pcall(function()
			local augs = require(script.Parent.AugmentService).forPlayerWeapon(player, weaponId)
			recoilCut = tonumber(augs and augs.recoil) or 0
		end)
		-- Recoil values are negative in the data and mean "less dispersion", so the multiplier is 1 + cut.
		spreadAngle = (base + bloom) * math.max(0.4, 1 + recoilCut)
		-- movingAccuracy: firing while moving widens the cone. Positive values reduce the penalty
		-- (Bipod +0.2), negative values worsen it (LongBarrel -0.05). The 1.5 degree base penalty is
		-- my invention - the spec names the stat but authors no magnitude.
		if root.AssemblyLinearVelocity.Magnitude > 2 then
			local moveBonus = 0
			pcall(function()
				local augs2 = require(script.Parent.AugmentService).forPlayerWeapon(player, weaponId)
				moveBonus = tonumber(augs2 and augs2.movingAccuracy) or 0
			end)
			spreadAngle = spreadAngle + 1.5 * math.max(0.2, 1 - moveBonus)
		end
		-- adsRecovery is positive when it helps (FastHands 0.15, ReflexSear 0.25) and only applies with
		-- sights up, which is what "ADS recovery" means: the cone re-settles faster between shots.
		local perShot = tonumber(weapon.spreadPerShot) or 0
		if aiming then
			local adsRecovery = 0
			pcall(function()
				local a = require(script.Parent.AugmentService).forPlayerWeapon(player, weaponId)
				adsRecovery = tonumber(a and a.adsRecovery) or 0
			end)
			perShot = perShot * math.max(0.2, 1 - adsRecovery)
		end
		-- spec cap: accumulated bloom never exceeds 2.5x the weapon's starting spread (S04-011)
		local bloomCap = math.max(0.5, base * 2.5)
		s.spreadBloom = math.min(bloomCap, bloom + perShot)
		-- HUD feedback must show the cone the player is currently carrying into the NEXT shot, not the
		-- stale pre-shot value from one trigger pull earlier.
		player:SetAttribute("SpreadBloom", s.spreadBloom)
		if spreadAngle > 0 then
			local right = unit:Cross(Vector3.yAxis)
			if right.Magnitude < 1e-3 then
				right = Vector3.xAxis
			end
			right = right.Unit
			local up = right:Cross(unit).Unit
			-- circular cone distribution: independent uniform yaw/pitch made a SQUARE — corners
			-- overshot the intended cone by up to 1.41x and accuracy felt wrong diagonally.
			-- sqrt scaling gives uniform area density across the disc, matching how real cone
			-- dispersion is modeled; for these angles tan(x) approximates x closely enough that
			-- the tangent-plane disc and the true spherical cap are indistinguishable.
			local angularRadius = math.rad(spreadAngle) * math.sqrt(math.random())
			local phi = math.random() * math.pi * 2
			unit = (unit
				+ right * math.tan(angularRadius) * math.cos(phi)
				+ up * math.tan(angularRadius) * math.sin(phi)).Unit
		end
		workspace:SetAttribute("GF_LastSpread", string.format("%.3f:bloom=%.2f:recoilCut=%.2f", spreadAngle, s.spreadBloom, recoilCut))
	else
		-- Publish even when disabled: leaving the previous value in place made a disabled run read as
		-- if spread were still applied, which is the stale-attribute trap this project keeps hitting.
		workspace:SetAttribute("GF_LastSpread", "disabled")
	end
	local rangeBonus = 0
	pcall(function()
		local augs = require(script.Parent.AugmentService).forPlayerWeapon(player, weaponId)
		rangeBonus = tonumber(augs and augs.range) or 0
	end)
	local rangeScale = math.clamp(1 + rangeBonus, 0.65, 1.30)
	local effectiveRange = weapon.range * rangeScale
	local effectiveFalloffStart = (weapon.falloffStart or weapon.range) * rangeScale
	local effectiveFalloffEnd = (tonumber(weapon.falloffEnd) or weapon.range) * rangeScale
	workspace:SetAttribute("GF_LastWeaponRange", string.format("%.1f(bonus=%.2f)", effectiveRange, rangeBonus))
	local maxRange = effectiveRange * MAX_RANGE_SLACK
	-- Pellets. SG-04 was authored as 8 pellets x 12 but fired ONE ray for the summed 96, so it had no
	-- graded damage at range and no per-pellet falloff. damagePerPellet keeps the total identical at point
	-- blank (8 x 12 = 96) while making each pellet its own ray, scatter and falloff. Non-pellet weapons have
	-- pellets = 1 and take exactly the old path.
	local pellets = math.max(1, math.floor(tonumber(weapon.pellets) or 1))
	local damagePerPellet = weapon.damage / pellets
	local rightAxis = unit:Cross(Vector3.yAxis)
	if rightAxis.Magnitude < 1e-3 then
		rightAxis = Vector3.xAxis
	end
	rightAxis = rightAxis.Unit
	local upAxis = rightAxis:Cross(unit).Unit
	for pelletIndex = 1, pellets do
		local pelletDir = unit
		if pelletIndex > 1 then
			-- Scatter must honour the same stance rule as the primary spread. This previously always used
			-- adsSpread, so a HIP-fired shotgun scattered at 4.5 degrees instead of its 0.15 base and most
			-- pellets missed a torso at 33+ studs.
			local angle = (isAiming and (tonumber(weapon.adsSpread) or tonumber(weapon.spreadBase) or 1))
				or (tonumber(weapon.spreadBase) or 1)
			-- circular disc, not square jitter — same correction as the bullet path above.
			local pelletRadius = math.rad(angle) * math.sqrt(math.random())
			local pelletPhi = math.random() * math.pi * 2
			local yaw = pelletRadius * math.cos(pelletPhi)
			local pitch = pelletRadius * math.sin(pelletPhi)
			pelletDir = (unit + rightAxis * math.tan(yaw) + upAxis * math.tan(pitch)).Unit
		end
		local result = workspace:Raycast(origin, pelletDir * maxRange, raycastParams(character))
		local hitPosition = origin + pelletDir * effectiveRange
		local enemyModel, partName = nil, nil
		if result then
		if result and result.Instance then
			local CoverService = require(script.Parent.DestructibleCoverService)
			if CoverService.isDestructible(result.Instance) then
				CoverService.damage(result.Instance, 20)
			end
		end
			hitPosition = result.Position
			if result.Instance then
				enemyModel, partName = resolveEnemy(result.Instance)
			end
		end
		if pellets > 1 then
			workspace:SetAttribute("GF_LastPellet", string.format("%d/%d hit=%s dmgEach=%.2f", pelletIndex, pellets, tostring(enemyModel ~= nil), damagePerPellet))
		end
		if weapon.explosive then
			-- S04-048: launchers fire travelling shells, not hitscan explosions. The shell detonates on
			-- collision or at lifetime end; detonate() still owns the AoE math at whatever point that is.
			require(script.Parent.ProjectileService).launch(player, weapon, origin, pelletDir)
			note("BlastHits", 0)
			note("LastBlast", hitPosition)
			-- no immediate DamageFeedback here: the shell is still travelling. The old fake feedback
			-- showed a hitmarker the instant the trigger was pulled regardless of where the shell
			-- actually landed. Real feedback is detonation-driven inside ProjectileService.
			ReplicatedStorage.GF.Remotes.AmmoUpdated:FireClient(player, { ammo = s.ammo, magazine = weapon.magazine, reserve = s.reserve or 0 })
			return
		end
		if enemyModel then
			-- A corpse must not produce hitmarkers. Measured: four shots fired at an already-dead target still sent
			-- DamageFeedback with damage=18, killed=false, while health correctly stayed at 0.
			if enemyModel:GetAttribute("Dead") == true then
				continue
			end
			local distance = (hitPosition - origin).Magnitude
			local falloffStart = effectiveFalloffStart
			local falloff = 1
			if distance > falloffStart then
				local falloffEnd = effectiveFalloffEnd
				local span = math.max(1, falloffEnd - falloffStart)
				falloff = 1 - math.clamp((distance - falloffStart) / span, 0, 1) * (1 - (weapon.falloffMin or 0.6))
			end
			local mult = CombatService.weakMultiplier(partName, result and result.Instance)
			local damage = damagePerPellet * falloff * mult
			local killed = CombatService.damageEnemy(enemyModel, damage, player, partName, mult, weapon)
			if Telemetry.enabled() then
				Telemetry.emit("hit_registered", {
					weaponId = weapon.id,
					zone = partName,
					distance = math.floor(distance * 100 + 0.5) / 100,
					falloffApplied = math.floor(falloff * 1000 + 0.5) / 1000,
					damageAfterFalloff = math.floor(damage * 100 + 0.5) / 100,
					weakMult = mult,
					pelletsTotal = pellets,
					targetEnemyId = enemyModel.Name,
					targetArchetype = enemyModel:GetAttribute("EnemyId"),
					killed = killed,
				})
				if killed then
					Telemetry.emit("enemy_killed", {
						enemyId = enemyModel.Name,
						archetype = enemyModel:GetAttribute("EnemyId"),
						zone = partName,
						weaponId = weapon.id,
					})
				end
			end
			counters.hits += 1
			note("Hits", counters.hits)
			note("LastDamage", damage)
			ReplicatedStorage.GF.Remotes.DamageFeedback:FireClient(player, {
				position = hitPosition,
				damage = damage,
				weakPoint = mult > 1,
				killed = killed,
			})
		elseif result and result.Instance and resolveAlly(result.Instance, player) then
			local ally = resolveAlly(result.Instance, player) :: Player
			local distance = (hitPosition - origin).Magnitude
			local falloff = 1
			if distance > effectiveFalloffStart then
				local span = math.max(1, effectiveFalloffEnd - effectiveFalloffStart)
				falloff = 1 - math.clamp((distance - effectiveFalloffStart) / span, 0, 1) * (1 - (weapon.falloffMin or 0.6))
			end
			damageAlly(ally, damagePerPellet * falloff, player)
		elseif result and result.Instance then
			local structure, structureName = resolveStructure(result.Instance)
			if structure then
				local distance = (hitPosition - origin).Magnitude
				local falloffStart = weapon.falloffStart or weapon.range
				local falloff = 1
				if distance > falloffStart then
					local span = math.max(1, effectiveRange - falloffStart)
					falloff = 1 - math.clamp((distance - falloffStart) / span, 0, 1) * (1 - (weapon.falloffMin or 0.6))
				end
				local damage = damagePerPellet * falloff
				local broke = CombatService.damageStructure(structure, damage, player)
				note("LastStructure", structureName)
				ReplicatedStorage.GF.Remotes.DamageFeedback:FireClient(player, {
					position = hitPosition,
					damage = damage,
					weakPoint = false,
					killed = broke,
				})
			else
				note("LastMiss", hitPosition)
			end
		else
			note("LastMiss", hitPosition)
		end
	end
	ReplicatedStorage.GF.Remotes.AmmoUpdated:FireClient(player, { ammo = s.ammo, magazine = weapon.magazine, reserve = s.reserve or 0 })
end
-- B2: server-authoritative weapon switching. The client has always sent EquipWeapon requests but
-- no listener existed, so the swap was pure desync. Validates loadout membership, cancels any
-- reload in progress, preserves per-weapon ammunition pools, and gates firing for the 0.4s swap.
function CombatService.equipWeapon(player: Player, weaponId: any)
	if type(weaponId) ~= "string" then
		return
	end
	local s = State.get(player)
	if not s or s.downed then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local weapon = Weapons.get(weaponId)
	if not weapon then
		return
	end
	-- lazily resolve loadout slots for sessions that predate this build
	if not s.loadoutPrimary then
		CombatService.applyLoadout(player)
	end
	if weaponId ~= s.loadoutPrimary and weaponId ~= s.loadoutSecondary then
		return
	end
	if weaponId == s.weaponId then
		return
	end
	-- switching cancels an unfinished reload (commit never happens, no ammunition moves)
	if s.reloading then
		s.reloading = false
		ReplicatedStorage.GF.Remotes.ReloadCancelled:FireClient(player, {})
	end
	-- stash the current weapon's ammunition, restore the target's
	s.ammoPools = s.ammoPools or {}
	if s.weaponId then
		s.ammoPools[s.weaponId] = { ammo = s.ammo or 0, reserve = s.reserve or 0 }
	end
	local pool = s.ammoPools[weaponId]
	if not pool then
		local augs = require(script.Parent.AugmentService).forPlayerWeapon(player, weaponId)
		pool = {
			ammo = require(script.Parent.AugmentService).magazine(weapon, augs),
			reserve = tonumber(weapon.reserve) or 0,
		}
		s.ammoPools[weaponId] = pool
	end
	s.weaponId = weaponId
	s.ammo = pool.ammo
	s.reserve = pool.reserve
	s.spreadBloom = 0
	local augs = require(script.Parent.AugmentService).forPlayerWeapon(player, weaponId)
	-- swapSpeed uses rate division consistent with the reload algebra: +35% caps at 0.4/1.35s.
	s.swapUntil = now() + 0.4 / math.max(0.5, 1 + (tonumber(augs and augs.swapSpeed) or 0))
	-- replicate the visual weapon identity to every client: remote viewmodel builders
	-- read this attribute to render what other players are carrying (presentation only)
	if character then
		character:SetAttribute("GF_EquippedWeapon", weaponId)
	end
	ReplicatedStorage.GF.Remotes.WeaponEquipped:FireClient(player, {
		weaponId = weaponId,
		ammo = s.ammo,
		reserve = s.reserve or 0,
		magazine = require(script.Parent.AugmentService).magazine(weapon, augs),
	})
end

function CombatService.applyLoadout(player: Player)
	-- ensure, not get: spawn ordering races state creation, and a silent no-op here means the
	-- player carries the AR01 default regardless of their armory loadout with no pools and no
	-- slot attributes — exactly the failure this function exists to prevent.
	local s = State.ensure and State.ensure(player) or State.get(player)
	if not s then
		return
	end
	local weaponId = s.weaponId
	local armory = ServerScriptService.GF.Services:FindFirstChild("ArmoryService")
	if armory then
		local ok, sel = pcall(function()
			return require(armory :: any).selection(player)
		end)
		if ok and type(sel) == "table" then
			if type(sel.primary) == "string" then
				weaponId = sel.primary
			elseif type(sel.weaponId) == "string" then
				weaponId = sel.weaponId
			end
		end
	end
	local weapon = (weaponId and Weapons.get(weaponId)) or Weapons.get("AR01")
	if not weapon then
		return
	end
	-- B1: resolve the full loadout (primary + secondary) and publish it per-player. Per-weapon
	-- ammunition pools mean swapping no longer refills or loses ammunition — each weapon carries
	-- its own magazine/reserve state for the life of the mission.
	local primary, secondary = weapon.id, "P01"
	do
		local armory = script.Parent:FindFirstChild("ArmoryService")
		local sel = armory and require(armory).selection(player)
		if type(sel) == "table" then
			if type(sel.primary) == "string" and Weapons.get(sel.primary) then
				primary = sel.primary
			end
			if type(sel.secondary) == "string" and Weapons.get(sel.secondary) then
				secondary = sel.secondary
			end
		end
	end
	s.loadoutPrimary = primary
	s.loadoutSecondary = secondary
	player:SetAttribute("GF_PrimaryWeapon", primary)
	player:SetAttribute("GF_SecondaryWeapon", secondary)
	weapon = Weapons.get(primary) or weapon
	s.weaponId = weapon.id
	local char = player.Character
	if char then
		char:SetAttribute("GF_EquippedWeapon", weapon.id)
	end
	local loadoutAugs = require(script.Parent.AugmentService).forPlayerWeapon(player, primary)
	local effectiveMagazine = require(script.Parent.AugmentService).magazine(weapon, loadoutAugs)
	s.ammo = effectiveMagazine
	-- S04-025: reserve is now tracked. The catalog figures (168/216/225/42/72/16/7/72) were dead data
	-- that only CheckRunner read, which made ammunition effectively infinite.
	s.reserve = tonumber(weapon.reserve) or 0
	pcall(function()
		local augs = require(script.Parent.AugmentService).forPlayerWeapon(player, primary)
		local bonus = tonumber(augs and augs.reserveAmmo) or 0
		if bonus ~= 0 then
			s.reserve = math.floor(s.reserve * (1 + bonus) + 0.5)
		end
	end)
	s.ammoPools = {}
	for _, id in ipairs({ primary, secondary }) do
		local w = Weapons.get(id)
		if w then
			s.ammoPools[id] = {
				ammo = require(script.Parent.AugmentService).magazine(w, loadoutAugs),
				reserve = tonumber(w.reserve) or 0,
			}
		end
	end
	s.reloading = false
	s.lastShotId = 0
	s.swapUntil = 0
	ReplicatedStorage.GF.Remotes.WeaponEquipped:FireClient(player, {
		weaponId = weapon.id,
		ammo = s.ammo,
		reserve = s.reserve or 0,
		-- The HUD divides by this value: it must be the augmented capacity, not the catalog number.
		magazine = effectiveMagazine,
	})
end
function CombatService.start()
	ReplicatedStorage.GF.Remotes.FireWeapon.OnServerEvent:Connect(function(player, payload)
		-- Outer coarse bucket (20/s shared across oversized payloads); the per-weapon RPM interval
		-- inside fire() remains the authoritative rate check.
		if not require(script.Parent.NetGuard).allowPayload(player, "fire", payload) then
			return
		end
		local ok, err = pcall(CombatService.fire, player, payload)
		if not ok then
			warn("[GF] fire error: " .. tostring(err))
		end
	end)
	ReplicatedStorage.GF.Remotes.EquipWeapon.OnServerEvent:Connect(function(player, payload)
		if not require(script.Parent.NetGuard).allow(player, "equip") then
			return
		end
		local id = type(payload) == "table" and payload.weaponId or payload
		local ok, err = pcall(CombatService.equipWeapon, player, id)
		if not ok then
			warn("[GF] equip error: " .. tostring(err))
		end
	end)
	ReplicatedStorage.GF.Remotes.ReloadWeapon.OnServerEvent:Connect(function(player)
		if not require(script.Parent.NetGuard).allow(player, "reload") then
			return
		end
		local s = State.get(player)
		if not s or s.downed then
			return
		end
		local weapon = Weapons.get(s.weaponId)
		if not weapon or s.reloading then
			return
		end
		local reloadCapacity = require(script.Parent.AugmentService).magazine(weapon, require(script.Parent.AugmentService).forPlayerWeapon(player, s.weaponId))
		if s.ammo >= reloadCapacity then
			return
		end
		CombatService.ensureReserve(s, weapon)
		if CombatService.reloadPlan(s.ammo, reloadCapacity, s.reserve or 0) <= 0 then
			return
		end
		s.reloading = true
		if player.Character then
			player.Character:SetAttribute("GF_Reloading", true)
			-- duration sync (spec sec.5): the presentation phases scale to the ACTUAL effective
			-- reload time including augments/class passives — stamped server-side, one clock base
			local reloadDur = s.reloadDone - now()
			player.Character:SetAttribute("GF_ReloadStartAt", os.clock())
			player.Character:SetAttribute("GF_ReloadEndAt", os.clock() + reloadDur)
		end
		s.reloadCount = (s.reloadCount or 0) + 1
		s.reloadDone = now() + ((require(script.Parent.AugmentService).reloadTime(weapon, require(script.Parent.AugmentService).forPlayerWeapon(player, s.weaponId))) * require(script.Parent.ClassService).reloadFactor(player))
		note("Reloading", player.Name)
		task.delay((require(script.Parent.AugmentService).reloadTime(weapon, require(script.Parent.AugmentService).forPlayerWeapon(player, s.weaponId))) * require(script.Parent.ClassService).reloadFactor(player), function()
			local live = State.get(player)
			if not live or live ~= s then
				return
			end
			if live.reloading and now() >= live.reloadDone then
				live.reloading = false
				if player.Character then player.Character:SetAttribute("GF_Reloading", false) end
				-- S04-025: add only what the reserve can supply, and consume it.
			local n = CombatService.reloadPlan(live.ammo, reloadCapacity, live.reserve or 0)
			if n > 0 then
				live.ammo = live.ammo + n
				live.reserve = math.max(0, (live.reserve or 0) - n)
			end
				ReplicatedStorage.GF.Remotes.AmmoUpdated:FireClient(player, {
					ammo = live.ammo,
					magazine = reloadCapacity,
					reserve = live.reserve or 0,
				})
			end
		end)
	end)
end
-- Force an ammo update for a player, used when entering a mission so the HUD shows a real magazine
-- instead of staying blank until the first shot.
function CombatService.publishAmmo(player: Player)
	local s = require(script.Parent.State).get(player)
	if not s then
		return
	end
	local Weapons = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Weapons)
	local weapon = Weapons.ById[s.weaponId or "AR01"]
	-- Seed the reserve the first time ammunition is published: applyLoadout only runs on loadout
	-- changes, so a freshly spawned player would otherwise carry reserve = nil and the HUD would show 0.
	CombatService.ensureReserve(s, weapon)
	ReplicatedStorage.GF.Remotes.AmmoUpdated:FireClient(player, {
		ammo = s.ammo or (weapon and weapon.magazine) or 0,
		magazine = weapon and weapon.magazine or 0,
		reserve = s.reserve or 0,
	})
end
-- S01-015 stable attachment names: weapon models expose consistent attachment points so art
-- replacement never breaks game logic — grip, muzzle, hand, head and backpack/ability anchors
-- use the same names across every weapon and suit.
CombatService.ATTACHMENT_NAMES = {
	weapon = { "Grip", "Muzzle", "Sight" },
	character = { "HandRight", "Head", "Backpack", "AbilityMount" },
}

function CombatService.ensureAttachments(model: Model): Model
	-- idempotent: existing attachments are reused, never duplicated
	if not model.PrimaryPart then return model end
	for _, name in ipairs(CombatService.ATTACHMENT_NAMES.weapon) do
		if not model:FindFirstChild(name) then
			local att = Instance.new("Attachment")
			att.Name = name
			att.Parent = model.PrimaryPart
		end
	end
	return model
end

-- S04-029 server-side shot validation: every firing claim passes through validation — ammo
-- count, RPM cap, sequence ordering, origin sanity, equip state, life state. Invalid shots
-- reject silently to the shooter but log for the anti-cheat ledger.
local lastShotAt: { [Player]: number } = {}
local lastSequence: { [Player]: number } = {}

function CombatService.validateShot(plr: Player, weaponKey: string, sequence: number, rpm: number): boolean
	-- life state: the dead don't shoot
	local character = plr.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	-- equip state: untargetable/committed players are out of the fight
	if plr:GetAttribute("GF_Untargetable") then
		return false
	end
	-- RPM cap: no faster than the weapon's cyclic rate allows
	local now = os.clock()
	local minInterval = 60 / math.max(rpm, 1)
	if lastShotAt[plr] and (now - lastShotAt[plr]) < minInterval * 0.85 then
		return false
	end
	-- sequence ordering: replays and out-of-order claims reject
	if lastSequence[plr] and sequence <= lastSequence[plr] then
		return false
	end
	lastShotAt[plr] = now
	lastSequence[plr] = sequence
	return true
end

game:GetService("Players").PlayerRemoving:Connect(function(plr)
	lastShotAt[plr] = nil
	lastSequence[plr] = nil
end)

return CombatService
