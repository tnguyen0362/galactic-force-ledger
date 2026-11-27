--!strict
-- Allocates enemies. Patrols guard the objective; extraction adds pressure.
-- Budget is capped so a long fight cannot overpopulate the map.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnemyService = require(script.Parent.EnemyService)
local ObjectiveService = require(script.Parent.ObjectiveService)
local State = require(script.Parent.State)
local Enemies = require(ReplicatedStorage.GF.Shared.Configs.Enemies)
local EncounterDirector = {}
local MAX_ACTIVE = 8
local PATROL_COUNT = 4
local EXTRACTION_WAVE_INTERVAL = 9
local EXTRACTION_WAVE_SIZE = 2
local spawnedThisMission = 0
-- S06-035: the spec requires authored waves with a patrol BUDGET, "not infinite spawning". Measured at place
-- 551: MAX_ACTIVE capped concurrency at 8 but nothing capped the total, so killing enemies freed capacity and
-- the count climbed 5 -> 13 -> 17 -> 21 without limit. This budget bounds a whole mission. The value is a
-- tunable multiple of the concurrency cap, not a balance figure invented here.
local MISSION_SPAWN_BUDGET = MAX_ACTIVE * 4

-- Reinforcement economy (S06-036..044): player-scaled concurrent cap, threat-costed spawns, alert-driven
-- token refill, phase scalar, off-screen validated spawn positions. The flat MAX_ACTIVE above stays as an
-- absolute safety ceiling; the economy cap is usually tighter.
local DIFFICULTY_PRESSURE = { Easy = 0.7, Normal = 1.0, Hard = 1.3, Extreme = 1.6 }
local THREAT_COST = { Rifleman = 1, Scout = 1, Marksman = 1.5, Heavy = 2.5, Officer = 2, BastionWalker = 6, HighMarshalVeyr = 6 }
local REFILL_RATE = 0.12 -- tokens/s base; scaled by P^0.7 * pressure * phase * (0.5 + A/100)
local TOKEN_BURST_CAP = 8
local ALERT_DECAY_PER_S = 2
local ALERT_PER_GUNFIRE = 6
local SPAWN_MIN_PLAYER_DIST = 65
local SPAWN_MAX_PLAYER_DIST = 140

local tokens = TOKEN_BURST_CAP
local alert = 0
local lastRefillAt = os.clock()

local function connectedPlayers(): number
	local n = 0
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("GF_Aboard") ~= true then
			n += 1
		end
	end
	return math.max(1, n)
end

-- round(4+2*(P-1)) scaled by difficulty pressure (S06-036/038): solo Normal 4, 4-player Normal 10, Extreme 16.
-- difficulty resolution (S06-038): the spawn economy must see the mission's actual difficulty,
-- not behave as perpetual Normal. Cached briefly; mission difficulty changes are rare.
local cachedDifficulty: string? = nil
local difficultyCachedAt = 0
local function currentDifficulty(): string
	local now = os.clock()
	if cachedDifficulty and now - difficultyCachedAt < 5 then
		return cachedDifficulty :: string
	end
	local d = "Normal"
	pcall(function()
		local mission = require(script.Parent.State).getMission()
		if mission and mission.difficulty then
			d = mission.difficulty
		end
	end)
	cachedDifficulty = d
	difficultyCachedAt = now
	return d
end

function EncounterDirector.activeCap(difficulty: string?): number
	local p = connectedPlayers()
	local base = math.round(4 + 2 * (p - 1))
	local pressure = DIFFICULTY_PRESSURE[difficulty or "Normal"] or 1
	return math.min(MAX_ACTIVE * 2, math.max(1, math.round(base * pressure)))
end
-- S06-037: boss arena seat reservation — while a boss is active its threat cost plus a retinue of adds
-- is carved out of the spawn cap before regular waves draw from it, so the arena never starves the boss.
function EncounterDirector.bossSeats(): number
	if workspace:GetAttribute("BastionActive") == true or workspace:GetAttribute("VeyrActive") == true then
		return THREAT_COST.BastionWalker + 4 -- boss body plus four seats of escort adds
	end
	return 0
end

local function phaseScalar(): number
	if workspace:GetAttribute("GF_ExtractionCalled") == true then
		return 1.5
	end
	if workspace:GetAttribute("GF_ObjectiveComplete") == true then
		return 1.4
	end
	-- skirmish once any hostile is alerted/engaged, travel before contact
	if (tonumber(workspace:GetAttribute("GF_AlertedCount")) or 0) > 0 then
		return 1
	end
	return 0.6
end

function EncounterDirector.noteGunfire()
	alert = math.min(100, alert + ALERT_PER_GUNFIRE)
end

-- Every connected mission participant is downed (or worse): true only when at least one participant
-- exists and nobody is still up. Spectators/lobby players do not count.
local function squadAllDowned(): boolean
	local anyParticipant = false
	local anyStanding = false
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("GF_MissionParticipant") == true then
			anyParticipant = true
			local character = player.Character
			local downed = character and character:GetAttribute("GFDowned") == true
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and not downed then
				anyStanding = true
			end
		end
	end
	return anyParticipant and not anyStanding
end

local function refillTokens(difficulty: string?)
	local now = os.clock()
	local dt = math.min(5, now - lastRefillAt)
	lastRefillAt = now
	local p = connectedPlayers()
	local pressure = DIFFICULTY_PRESSURE[difficulty or "Normal"] or 1
	local cut = tonumber(workspace:GetAttribute("GF_ReinforcementCut")) or 1
	-- S06-047 burst/breather cadence: sustained fighting is metered into 20-45s pressure windows
	-- followed by 15-35s relief. During a breather token refill slows to a third, so squads get
	-- real travel/recovery space between fights instead of an unbroken spawn hose.
	local nowB = os.clock()
	if tokens >= TOKEN_BURST_CAP * 0.85 and (EncounterDirector.burstStartedAt or 0) == 0 then
		EncounterDirector.burstStartedAt = nowB
	end
	if (EncounterDirector.burstStartedAt or 0) > 0 and nowB - EncounterDirector.burstStartedAt >= 25 then
		-- pressure window complete: enter the breather and reset the burst clock
		EncounterDirector.burstStartedAt = 0
		EncounterDirector.breatherUntil = nowB + 20 + math.random() * 12
		workspace:SetAttribute("GF_Breather", true)
	end
	local breather = nowB < (EncounterDirector.breatherUntil or 0)
	if not breather then
		workspace:SetAttribute("GF_Breather", false)
	end
	local breatherScalar = breather and 0.34 or 1
	local rate = REFILL_RATE * (p ^ 0.7) * pressure * phaseScalar() * (0.5 + alert / 100) * cut * breatherScalar
	-- pause refill at the active cap (S06-042); and suppress new waves entirely while every
	-- connected participant is downed - a squad bleeding out is never further punished
	if EnemyService.count() < math.max(0, EncounterDirector.activeCap(difficulty) - EncounterDirector.bossSeats()) and not squadAllDowned() then
		tokens = math.min(TOKEN_BURST_CAP, tokens + rate * dt)
	end
	alert = math.max(0, alert - ALERT_DECAY_PER_S * dt)
	-- S11 threat trigger: a completed scout transmission is a sighting the enemy acted on — it
	-- spikes territorial alert regardless of gunfire, per the spec's trigger list.
	local transmits = tonumber(workspace:GetAttribute("GF_ScoutTransmits")) or 0
	if transmits > (EncounterDirector.lastTransmitCount or 0) then
		EncounterDirector.lastTransmitCount = transmits
		alert = math.min(100, alert + 30)
	end
	-- S11 named threat tiers: Unaware / Investigating / Mobilizing / Lockdown, published for HUD
	-- and validation. The numeric thresholds are the pre-existing escalation bands.
	local tier = alert >= 70 and 3 or (alert >= 40 and 2 or (alert >= 15 and 1 or 0))
	local THREAT_NAMES = { [0] = "Unaware", [1] = "Investigating", [2] = "Mobilizing", [3] = "Lockdown" }
	workspace:SetAttribute("GF_ThreatLevel", THREAT_NAMES[tier])
	workspace:SetAttribute("GF_ThreatAlert", math.floor(alert))
	if tier > (EncounterDirector.lastEscalationTier or 0) then
		local nowW = os.clock()
		if nowW - (EncounterDirector.escalationWarnedAt or 0) >= 45 then
			EncounterDirector.escalationWarnedAt = nowW
			local lines = {
				[1] = "Voss: movement in your sector — expect contact.",
				[2] = "Voss: enemy activity is building. Tighten up.",
				[3] = "Voss: heavy escalation — they're massing on your position!",
			}
			pcall(function()
				require(script.Parent.DialogueService).say(lines[tier] or lines[1], "escalation")
			end)
		end
	end
	EncounterDirector.lastEscalationTier = tier
end

function EncounterDirector.threatCost(id: string): number
	return THREAT_COST[id] or 1
end

-- Spawn validity (S06-044): 65-140 studs from every active player and outside every player's line of sight.
-- S06-049: never feed the endless chase — a spawn point directly behind a lone moving player
-- (opposite their movement direction, in the trail they just ran through) is rejected even when
-- line-of-sight rules pass, because popping pursuers into a fleeing player's wake is cheap pressure.
local function isChaseFeed(position: Vector3): boolean
	local playerCount = 0
	local moving: { { root: BasePart, vel: Vector3 } } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and player:GetAttribute("GF_Aboard") ~= true then
			playerCount += 1
			local vel = root.AssemblyLinearVelocity
			if vel.Magnitude > 8 then
				table.insert(moving, { root = root, vel = vel })
			end
		end
	end
	if playerCount > 1 then return false end -- group pressure is fine; this rule protects solo runners
	for _, m in ipairs(moving) do
		local behind = m.root.Position - (position - m.root.Position).Unit * 1
		local toSpawn = position - m.root.Position
		local moveDir = m.vel.Unit
		-- spawn lies in the player's trailing wake: behind their movement direction within 60 degrees
		if toSpawn.Magnitude > 1 and moveDir:Dot(-toSpawn.Unit) > 0.5 then
			return true
		end
	end
	return false
end

function EncounterDirector.isSpawnPointValid(position: Vector3): boolean
	if isChaseFeed(position) then
		return false
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and player:GetAttribute("GF_Aboard") ~= true then
			local dist = (root.Position - position).Magnitude
			if dist < SPAWN_MIN_PLAYER_DIST or dist > SPAWN_MAX_PLAYER_DIST then
				return false
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { workspace:FindFirstChild("ActiveActors") }
			local eye = root.Position + Vector3.new(0, 4, 0)
			local hit = workspace:Raycast(eye, position + Vector3.new(0, 3, 0) - eye, params)
			if hit == nil then
				return false -- clean line of sight: the player would see the spawn
			end
		end
	end
	return true
end

function EncounterDirector.economyStats()
	return { tokens = math.floor(tokens * 100) / 100, alert = math.floor(alert), cap = EncounterDirector.activeCap(currentDifficulty()), phase = phaseScalar() }
end
local function groundAt(position: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild("ActiveActors") }
	local hit = workspace:Raycast(position + Vector3.new(0, 120, 0), Vector3.new(0, -260, 0), params)
	return hit and hit.Position or nil
end
local function activeCount(): number
	return EnemyService.count()
end
local function standardIds(): { string }
	local ids = {}
	for _, def in Enemies.List do
		-- Only tier == "Standard" was spawned, so Marksman/Heavy/Officer existed as config rows
		-- and models but never appeared in a mission (LC-002). The director fields all five.
		if def.id == "Rifleman" or def.id == "Scout" or def.id == "Marksman" or def.id == "Heavy" or def.id == "Officer" then
			table.insert(ids, def.id)
		end
	end
	return ids
end
-- Hostiles never spawn closer than this to the landing zone; the drop must be survivable.
local SAFE_LANDING_RADIUS = 70

local postponedSpawns: { { center: Vector3, radius: number, count: number, attempts: number } } = {}

-- The station deck floats at Y~760 above the terrain. Altitude alone can't separate it from
-- legitimate high ground: generated geography has real peaks exceeding 400 studs, and a pure
-- ceiling both mis-flagged mountain enemies in probes and blocked valid spawns. The station is
-- a small structure centered near X0/Z22 at deck level — gate on the station VOLUME instead:
-- high + near the deck's horizontal footprint. Terrain peaks elsewhere stay spawnable.
local STATION_XZ = Vector2.new(0, 22)
local STATION_DECK_Y = 700
local STATION_VOLUME_RADIUS = 260

local function missionGrounded(position: Vector3): boolean
	if position.Y < STATION_DECK_Y then
		return true
	end
	local dxz = (Vector2.new(position.X, position.Z) - STATION_XZ).Magnitude
	return dxz > STATION_VOLUME_RADIUS
end

function EncounterDirector.spawnAround(center: Vector3, radius: number, count: number): number
	if not missionGrounded(center) then
		return 0
	end
	-- drain postponed spawns first: each retry gets a fresh validity roll as players move
	if #postponedSpawns > 0 then
		local retry = table.remove(postponedSpawns, 1)
		if retry then
			task.defer(function()
				EncounterDirector.spawnAround(retry.center, retry.radius, retry.count)
			end)
		end
	end
	local ids = standardIds()
	if #ids == 0 then
		return 0
	end
	local placed = 0
	for i = 1, count do
		if activeCount() >= MAX_ACTIVE or activeCount() >= math.max(0, EncounterDirector.activeCap(currentDifficulty()) - EncounterDirector.bossSeats()) then
			break
		end
		if spawnedThisMission >= MISSION_SPAWN_BUDGET then
			break
		end
		local angle = (i / count) * math.pi * 2 + math.random() * 0.4
		local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local ground = groundAt(center + offset)
		-- Keep pickets out of the drop zone. Measured: the squad lost 100 shield within seconds of landing
		-- because hostiles spawned inside engagement range. A 4s grace only delayed it.
		local lz = workspace:GetAttribute("GF_LZ")
		if ground and typeof(lz) == "Vector3" and (ground - lz).Magnitude < SAFE_LANDING_RADIUS then
			local away = ground - lz
			local push = away.Magnitude > 1 and away.Unit or Vector3.new(1, 0, 0)
			ground = groundAt(lz + push * (SAFE_LANDING_RADIUS + 6)) or ground
		end
		if ground then
			-- Off-screen spawn validation (S06-044): never materialize inside a player's sightline or comfort radius.
			if not EncounterDirector.isSpawnPointValid(ground) then
				-- S06-045: no safe spawn right now — postpone rather than pop into view or vanish.
				-- The retry queue re-attempts each wave tick and gives up after 8 tries, which only
				-- happens when the squad camps a fully exposed position (a deliberate player win).
				if (postponedSpawns[1] and postponedSpawns[1].attempts or 0) < 8 then
					table.insert(postponedSpawns, { center = center, radius = radius + 6, count = 1, attempts = (postponedSpawns[1] and postponedSpawns[1].attempts or 0) + 1 })
				end
				continue
			end
			-- S06-034: elite frequency scales with difficulty — Heavy/Officer appear at ~0/10/20/30% of
			-- spawns on Easy/Normal/Hard/Extreme. Standards keep role diversity via uniform pick.
			local eliteChance = ({ Easy = 0.0, Normal = 0.10, Hard = 0.20, Extreme = 0.30 })[workspace:GetAttribute("GF_Difficulty") or "Normal"] or 0.10
			local id
			if math.random() < eliteChance then
				id = math.random() < 0.5 and "Heavy" or "Officer"
			else
				local standards = {}
				for _, sid in ipairs(ids) do
					if sid ~= "Heavy" and sid ~= "Officer" then
						table.insert(standards, sid)
					end
				end
				id = standards[math.random(1, #standards)]
			end
			local cost = EncounterDirector.threatCost(id)
			if tokens >= cost then
				if EnemyService.spawn(id, ground + Vector3.new(0, 3, 0)) then
					tokens -= cost
					placed += 1
					spawnedThisMission += 1
				end
			end
		end
	end
	return placed
end
function EncounterDirector.spawnVeyr(position: Vector3, player: Player?)
	if workspace:GetAttribute("GF_BossEnabled") == false then
		return nil
	end
	local Veyr = require(script.Parent.Parent.Veyr)
	local model, reason = Veyr.spawn(position, player)
	if reason == "rank" then
		workspace:SetAttribute("VeyrRankBlocked", true)
		return nil
	end
	return model
end

function EncounterDirector.spawnBoss(position: Vector3)
	if not missionGrounded(position) then
		return nil
	end
	if workspace:GetAttribute("GF_BossEnabled") == false then
		return nil
	end
	local Bastion = require(script.Parent.Parent.BastionWalker)
	local model = Bastion.spawn(position)
	if model then
		spawnedThisMission += 1
	end
	return model
end
function EncounterDirector.reset()
	-- clear everything the director owns so the next deployment starts clean
	local actors = workspace:FindFirstChild("ActiveActors")
	if actors then
		for _, model in actors:GetChildren() do
			-- S06-035: enemies have no Humanoid, so filtering on one left every hostile alive across missions
			-- (measured: reset() reported success while 9 enemies remained and blocked the concurrency cap).
			if model:FindFirstChildOfClass("Humanoid") or model:GetAttribute("GFEnemy") == true then
				model:Destroy()
			end
		end
	end
	spawnedThisMission = 0
	-- Boss models have no Humanoid, so the loop above never removed them: five deployments left five
	-- BastionWalkers stacked in the workspace, each still running its own mortar. Measured, not theorised.
	for _, boss in workspace:GetChildren() do
		if boss:IsA("Model") and boss:GetAttribute("Boss") == true and boss:GetAttribute("GF_ObjectiveTarget") ~= true then
			boss:Destroy()
		end
	end
	workspace:SetAttribute("BastionActive", false)
	workspace:SetAttribute("BossHealth", 0)
	workspace:SetAttribute("BastionDefeated", false)

end
-- Overwatch posts. Measured at the relay: 8 hostiles tracked and ZERO acquired the player standing at the console,
-- because the compound's own structure blocked every sightline. The objective was undefended by its defenders.
-- Posts are chosen by raycasting from a candidate vantage point to the console, so a post only exists if it can
-- actually see the thing it is guarding.
local function canSeeConsole(from: Vector3, console: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild("ActiveActors") }
	local hit = workspace:Raycast(from, console - from, params)
	return hit == nil
end

function EncounterDirector.spawnPosts(center: Vector3, count: number)
	if not missionGrounded(center) then
		return 0
	end: number
	local console = center + Vector3.new(0, 4, 0)
	local placed = 0
	local tried = 0
	for i = 1, 12 do
		if placed >= count then
			break
		end
		local angle = (i / 12) * math.pi * 2
		for _, radius in ipairs({ 26, 34, 42 }) do
			local spot = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			local ground = groundAt(spot)
			if ground then
				local eye = ground + Vector3.new(0, 10, 0)
				if canSeeConsole(eye, console) then
					tried += 1
					local lz = workspace:GetAttribute("GF_LZ")
					local farEnough = typeof(lz) ~= "Vector3" or (ground - (lz :: Vector3)).Magnitude > SAFE_LANDING_RADIUS
					if farEnough and activeCount() < MAX_ACTIVE + 2 then
						local id = (placed == 0) and "Marksman" or "Rifleman"
						if EnemyService.spawn(id, ground + Vector3.new(0, 3, 0)) then
							placed += 1
							workspace:SetAttribute("GF_PostLOS", placed)
						end
					end
					break
				end
			end
		end
	end
	workspace:SetAttribute("GF_PostsPlaced", placed)
	workspace:SetAttribute("GF_PostsTried", tried)
	return placed
end

local refillRunning = false
-- Battlefield dormant-zone system (GF_BattlefieldGen): generated garrisons/patrols register
-- as dormant regions, activating only when players close within activation radius.
local dormantZones: { any } = {}
local zoneWatcherStarted = false

function EncounterDirector.registerBattlefieldZones(plan: any): number
	dormantZones = {}
	if not plan or not plan.encounterZones then
		return 0
	end
	for _, z in plan.encounterZones do
		if z.kind == "garrison" then
			table.insert(dormantZones, {
				x = z.x, z = z.z,
				activationRadius = z.activationRadius or 220,
				size = math.min(z.size or 3, 4),
				radius = z.radius or 20,
				kind = "garrison",
				done = false,
			})
		elseif z.kind == "patrol_route" and z.ax then
			table.insert(dormantZones, {
				x = (z.ax + z.bx) * 0.5, z = (z.az + z.bz) * 0.5,
				activationRadius = 190,
				size = 2,
				radius = 16,
				kind = "patrol",
				done = false,
			})
		end
	end
	return #dormantZones
end

local function zoneWatcher()
	if zoneWatcherStarted then
		return
	end
	zoneWatcherStarted = true
	task.spawn(function()
		while task.wait(4) do
			if workspace:GetAttribute("GF_InMission") ~= true then
				continue
			end
			if #dormantZones == 0 then
				continue
			end
			local lz = workspace:GetAttribute("GF_LZ")
			local players = game:GetService("Players"):GetPlayers()
			for _, z in dormantZones do
				if z.done then
					continue
				end
				if typeof(lz) == "Vector3" then
					local dlz = (Vector3.new(z.x, 0, z.z) - Vector3.new(lz.X, 0, lz.Z)).Magnitude
					if dlz < 150 then
						z.done = true
						continue
					end
				end
				for _, plr in players do
					if plr:GetAttribute("GF_MissionParticipant") ~= true then
						continue -- station/lobby players never trip battlefield zones: the station floats above the mission terrain, so X/Z proximity alone would activate zones from the deck
					end
					local char = plr.Character
					local root = char and char:FindFirstChild("HumanoidRootPart")
					if not root then
						continue
					end
					local d = (Vector3.new(z.x, 0, z.z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
					if d <= z.activationRadius then
						z.done = true
						workspace:SetAttribute("GF_BFZonesActivated", (workspace:GetAttribute("GF_BFZonesActivated") or 0) + 1)
						print(string.format("[GF] battlefield zone activated kind=%s at %.0f,%.0f", z.kind, z.x, z.z))
						local center = Vector3.new(z.x, root.Position.Y, z.z)
						task.defer(function()
							EncounterDirector.spawnAround(center, z.radius, z.size)
						end)
						break
					end
				end
			end
		end
	end)
end

function EncounterDirector.beginMission(): ()
	spawnedThisMission = 0
	tokens = TOKEN_BURST_CAP
	alert = 0
	lastRefillAt = os.clock()
	workspace:SetAttribute("GF_ExtractionCalled", false)
	if not refillRunning then
		refillRunning = true
		task.spawn(function()
			while true do
				task.wait(1)
				if workspace:GetAttribute("GF_InMission") == true then
					refillTokens(currentDifficulty())
					local stats = EncounterDirector.economyStats()
					workspace:SetAttribute("GF_EconomyTokens", stats.tokens)
					workspace:SetAttribute("GF_EconomyAlert", stats.alert)
					workspace:SetAttribute("GF_EconomyCap", stats.cap)
				end
			end
		end)
	end
	-- operation mode: the operation layer owns encounter placement (garrisons at objective
	-- sites across the kilometer-scale geography). Legacy relay-centered posts/patrol/boss at
	-- the old 240-stud site must not spawn — but the economy reset above always runs.
	local opTemplate = workspace:GetAttribute("GF_OperationTemplate")
	if workspace:GetAttribute("GF_OperationMode") == true
		and type(opTemplate) == "string" and string.sub(opTemplate, 1, 9) == "CONQUEST_" then
		return
	end
	local relay = ObjectiveService.getRelay()
	local center = relay and relay.PrimaryPart and relay.PrimaryPart.Position
	if center then
		EncounterDirector.spawnPosts(center, 2)
		do
			local bfOk, bfTerrain = pcall(require, script.Parent.TerrainService)
			local plan = bfOk and bfTerrain.currentPlan or nil
			if workspace:GetAttribute("GF_BattlefieldGen") == true and plan then
				local n = EncounterDirector.registerBattlefieldZones(plan)
				zoneWatcher()
				print(string.format("[GF] battlefield zones registered=%d (dormant)", n))
				workspace:SetAttribute("GF_BFZonesRegistered", n)
			end
		end
		EnemyService.resetCalls()
		workspace:SetAttribute("GF_Reinforcements", 0)
		workspace:SetAttribute("GF_CallCompletedBy", "")
		workspace:SetAttribute("GF_LastCall", nil)
		local sabotage = require(script.Parent.ObjectiveService).getTemplate()
		if sabotage == "SABOTAGE_RELAY" then
			local commander = EnemyService.spawn("Officer", center + Vector3.new(10, 3, 10))
			if commander then
				workspace:SetAttribute("GF_RelayCommander", true)
			end
		end
		EncounterDirector.spawnAround(center, 34, PATROL_COUNT)
		-- Bosses are not pickets: measured 40/35/30 damage from BastionMortar and repeated 26 from VeyrBurst
		-- landing on the squad within seconds of a drop, before anything could be done. They are pulled back
		-- beyond artillery range of the landing zone so a mission starts with a chance.
		local lz = workspace:GetAttribute("GF_LZ")
		local function awayFromLz(point: Vector3, minDistance: number): Vector3
			if typeof(lz) ~= "Vector3" then
				return point
			end
			local delta = point - lz
			if delta.Magnitude >= minDistance then
				return point
			end
			local dir = delta.Magnitude > 1 and delta.Unit or Vector3.new(0, 0, -1)
			return lz + dir * minDistance
		end
		-- Bosses are encounters, not pickets. Veyr in particular is a rank-gated major encounter and has no
		-- business standing next to a drop pod: measured 26-damage bursts landing on the squad before they
		-- could move. The field boss still spawns, but far out, and neither engages until the squad closes.
		if ObjectiveService.getTemplate() ~= "ELIM_WALKER" then
			EncounterDirector.spawnBoss(awayFromLz(center + Vector3.new(0, 0, -55), 220))
		end
	else
		EncounterDirector.spawnAround(Vector3.new(0, 0, -120), 34, PATROL_COUNT)
		if ObjectiveService.getTemplate() ~= "ELIM_WALKER" then
			EncounterDirector.spawnBoss(Vector3.new(0, 0, -175))
		end
	end
end
function EncounterDirector.startExtractionPressure(): ()
	workspace:SetAttribute("GF_ExtractionCalled", true)
	-- termination contract (audit defect: the loop previously ran forever): stop when the
	-- mission ends or a new mission supersedes this one. GF_MissionId rotates per deploy.
	local missionId = workspace:GetAttribute("GF_MissionId")
	task.spawn(function()
		while task.wait(EXTRACTION_WAVE_INTERVAL) do
			if workspace:GetAttribute("GF_InMission") ~= true then
				break
			end
			if missionId ~= nil and workspace:GetAttribute("GF_MissionId") ~= missionId then
				break
			end
			local lz = workspace:GetAttribute("GF_ExtractionLZ") or workspace:GetAttribute("GF_LZ")
			if typeof(lz) ~= "Vector3" then
				break
			end
			refillTokens(currentDifficulty())
			if activeCount() >= EncounterDirector.activeCap(currentDifficulty()) then
				continue
			end
			EncounterDirector.spawnAround(lz, 55, EXTRACTION_WAVE_SIZE)
		end
	end)
end
function EncounterDirector.stats()
	return { active = activeCount(), cap = MAX_ACTIVE, spawned = spawnedThisMission, budget = MISSION_SPAWN_BUDGET }
end
return EncounterDirector
