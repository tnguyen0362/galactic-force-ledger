--!strict
-- Allocates enemies. Patrols guard the objective; extraction adds pressure.
-- Budget is capped so a long fight cannot overpopulate the map.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnemyService = require(script.Parent.EnemyService)
local ObjectiveService = require(script.Parent.ObjectiveService)
local NPCSquads = require(script.Parent.NPCSquads)
local Enemies = require(ReplicatedStorage.GF.Shared.Configs.Enemies)
local EncounterHierarchy = require(ReplicatedStorage.GF.Shared.Configs.EncounterHierarchy)
local EncounterDirector = {}
local MAX_ACTIVE = 8
local PATROL_COUNT = 4
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
local REFILL_RATE = 0.22 -- tokens/s base; wave cadence, not a continuous trickle. Scaled by P^0.7 * pressure * phase * alert.
local TOKEN_BURST_CAP = 8
local ALERT_DECAY_PER_S = 2.0
local ALERT_DECAY_LOCKDOWN_PER_S = 0.8
local SPAWN_MIN_PLAYER_DIST = 65
local SPAWN_MAX_PLAYER_DIST = 140
local WAVE_TELEGRAPH_LEAD = 7
local WAVE_MIN_INTERVAL = 18
local WAVE_MAX_INTERVAL = 34

local tokens = TOKEN_BURST_CAP
local alert = 0
local alertSource = "quiet"
local lastRefillAt = os.clock()
local lastGunfireAlarmAt = 0
local missionPhase = "idle"
local escalationTier = 0
local reconUntil = 0
local waveSerial = 0
local wavesLaunched = 0
local nextWaveAt = 0
local pendingWave: any = nil
local eventWaveQueue: { any } = {}
local reservedSeats = 0
local missionStartedAt = 0
local lastObjectiveProgress = 0
local lastObjectiveStage = ""
local reinforcementZones: { any } = {}
local quietZones: { any } = {}
local extractionZone: any = nil

local function connectedPlayers(): number
	local anyParticipant = false
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("GF_MissionParticipant") == true then
			anyParticipant = true
			break
		end
	end
	local n = 0
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("GF_Aboard") ~= true and (not anyParticipant or p:GetAttribute("GF_MissionParticipant") == true) then
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
		return EncounterHierarchy.enemyPressureCost("BastionWalker") + 4 -- boss body plus escort seats
	end
	return 0
end

local function phaseScalar(): number
	-- Authored pacing replaces the old always-on trickle: recon is intentionally quiet, contact is
	-- intermittent, objective assault is sustained, extraction is the loudest economy in the mission.
	if missionPhase == "recon" then
		return 0.22
	elseif missionPhase == "contact" then
		return 0.62
	elseif missionPhase == "assault" then
		return 1.05
	elseif missionPhase == "extraction" then
		return 1.25
	end
	return 0.5
end

local function threatName(): string
	if alert >= 70 then return "Lockdown" end
	if alert >= 40 then return "Mobilizing" end
	if alert >= 15 then return "Investigating" end
	return "Unaware"
end

local function publishAlert()
	workspace:SetAttribute("GF_ThreatLevel", threatName())
	workspace:SetAttribute("GF_ThreatAlert", math.floor(alert))
	workspace:SetAttribute("GF_AlertSource", alertSource)
end

local function raiseAlert(amount: number, source: string, cap: number?)
	local sourceCap = cap or 100
	if alert < sourceCap then
		alert = math.min(sourceCap, alert + amount)
	else
		alert = math.min(100, alert + amount * 0.15)
	end
	alertSource = source
	publishAlert()
end

-- EnemyService forwards unsuppressed ballistic noise here. Gunfire is evidence, not an instant alarm:
-- a few loud shots start Investigating, sustained fighting/decaying evidence pushes Mobilizing.
function EncounterDirector.noteGunfire(position: Vector3?)
	-- Rate-limit individual ballistic noise: one shot is evidence, sustained fire is escalation.
	-- Without this, any automatic weapon hit Lockdown in a few seconds purely through event count.
	local now = os.clock()
	if now - lastGunfireAlarmAt < 0.35 then
		return
	end
	lastGunfireAlarmAt = now
	raiseAlert(2.8, "gunfire", 58)
end

-- Integration point for other lanes: silent objective interactions should use noteEvidence, while
-- tripped alarms/scout transmissions use noteAlarm. Position is accepted for future directional UI.
function EncounterDirector.noteEvidence(amount: number?, source: string?)
	raiseAlert(amount or 8, source or "evidence", 45)
end

function EncounterDirector.noteAlarm(amount: number?, source: string?)
	raiseAlert(amount or 24, source or "alarm", 90)
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
	-- S06-047 burst/breather cadence: sustained fighting is metered into pressure windows followed by
	-- relief. The wave scheduler owns major timing; this scalar still prevents the trickle economy from
	-- becoming an unbroken hose during long objective fights.
	if tokens >= TOKEN_BURST_CAP * 0.85 and alert >= 15 and (EncounterDirector.burstStartedAt or 0) == 0 then
		EncounterDirector.burstStartedAt = now
	end
	if alert < 8 then
		EncounterDirector.burstStartedAt = 0
	end
	if (EncounterDirector.burstStartedAt or 0) > 0 and now - EncounterDirector.burstStartedAt >= 25 then
		EncounterDirector.burstStartedAt = 0
		EncounterDirector.breatherUntil = now + 20 + math.random() * 12
		workspace:SetAttribute("GF_Breather", true)
	end
	local breather = now < (EncounterDirector.breatherUntil or 0)
	if not breather then
		workspace:SetAttribute("GF_Breather", false)
	end
	local breatherScalar = breather and 0.34 or 1
	local rate = REFILL_RATE * (p ^ 0.7) * pressure * phaseScalar() * (0.5 + alert / 100) * cut * breatherScalar
	-- Pause refill at the active cap (reserved seats count) and never punish a full squad wipe-in-progress.
	local cap = math.max(0, EncounterDirector.activeCap(difficulty) - EncounterDirector.bossSeats() - reservedSeats)
	if EnemyService.count() < cap and not squadAllDowned() then
		tokens = math.min(TOKEN_BURST_CAP, tokens + rate * dt)
	end
	-- Alert is mission-wide evidence with memory. Lockdown decays slowly; quiet recon can genuinely
	-- return to Unaware if players disengage and stop feeding the alarm.
	local decay = alert >= 70 and ALERT_DECAY_LOCKDOWN_PER_S or ALERT_DECAY_PER_S
	alert = math.max(0, alert - decay * dt)
	if alert <= 0 then
		alertSource = "quiet"
	end
	-- Scout transmissions are a spec-listed threat trigger: a completed transmission is not noise,
	-- it is the enemy command net acting on a sighting.
	local transmits = tonumber(workspace:GetAttribute("GF_ScoutTransmits")) or 0
	if transmits > (EncounterDirector.lastTransmitCount or 0) then
		EncounterDirector.lastTransmitCount = transmits
		raiseAlert(30, "scout_transmission", 90)
	end
	publishAlert()

	-- Escalation tier combines alert with phase floor. Recon can sit at 0; contact is at least 1;
	-- objective assault at least 2; extraction is the mission's maximum-pressure infantry tier.
	local phaseFloor = missionPhase == "extraction" and 3 or (missionPhase == "assault" and 2 or (missionPhase == "contact" and 1 or 0))
	local alertTier = alert >= 70 and 3 or (alert >= 40 and 2 or (alert >= 15 and 1 or 0))
	local tier = math.max(phaseFloor, alertTier)
	if workspace:GetAttribute("GF_EmergencyExtraction") == true then
		tier = 3
	end
	escalationTier = tier
	workspace:SetAttribute("GF_EscalationTier", tier)
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
	return EncounterHierarchy.enemyPressureCost(id)
end

-- Spawn validity (S06-044): 65-140 studs from every active player and outside every player's line of sight.
-- S06-049: never feed the endless chase — a spawn point directly behind a lone moving player
-- (opposite their movement direction, in the trail they just ran through) is rejected even when
-- line-of-sight rules pass, because popping pursuers into a fleeing player's wake is cheap pressure.
local function isChaseFeed(position: Vector3): boolean
	local anyParticipant = false
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("GF_MissionParticipant") == true then
			anyParticipant = true
			break
		end
	end
	local playerCount = 0
	local moving: { { root: BasePart, vel: Vector3 } } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and player:GetAttribute("GF_Aboard") ~= true and (not anyParticipant or player:GetAttribute("GF_MissionParticipant") == true) then
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
	local anyParticipant = false
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("GF_MissionParticipant") == true then
			anyParticipant = true
			break
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and player:GetAttribute("GF_Aboard") ~= true and (not anyParticipant or player:GetAttribute("GF_MissionParticipant") == true) then
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

local function committedCount(): number
	-- A telegraphed wave has already promised its seats. Counting the reservation prevents the
	-- trickle spawner and the wave executor from both spending the same concurrency headroom.
	return EnemyService.count() + reservedSeats
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

function EncounterDirector.spawnAround(center: Vector3, radius: number, count: number, options: any?): number
	if not missionGrounded(center) then
		return 0
	end
	local opts = options or {}
	-- ObjectiveService's many defender hooks all call this same legacy API. After the opening
	-- placement window those calls are reinforcement EVENTS, so they enter the telegraphed squad-wave
	-- pipeline instead of materializing as immediate random singles. Internal placement callers pass
	-- immediate=true explicitly.
	local openingPlacement = missionStartedAt > 0 and os.clock() - missionStartedAt < 8
	if opts.immediate ~= true and not openingPlacement and workspace:GetAttribute("GF_InMission") == true then
		-- DEFEND_BEACON already emits its own compass/4.5s warning through GF_WaveTelegraph.
		-- Treat that as the first half of the telegraph instead of stacking a second full-length one.
		local telegraphStamp = workspace:GetAttribute("GF_WaveTelegraph")
		local telegraphAge = 999
		if type(telegraphStamp) == "string" then
			local stamp = tonumber(string.match(telegraphStamp, ":(%d+)$"))
			if stamp then
				telegraphAge = os.clock() - stamp
			end
		end
		local alreadyTelegraphed = telegraphAge >= 0 and telegraphAge < 6
		EncounterDirector.requestWave(center, {
			sizeHint = count,
			radius = radius,
			reason = alreadyTelegraphed and "pretelegraphed_assault" or (opts.reason or "objective_response"),
			lead = alreadyTelegraphed and 1.0 or nil,
			silent = alreadyTelegraphed,
		})
		return 0
	end
	-- drain postponed spawns first: each retry gets a fresh validity roll as players move
	if #postponedSpawns > 0 then
		local retry = table.remove(postponedSpawns, 1)
		if retry then
			task.defer(function()
				EncounterDirector.spawnAround(retry.center, retry.radius, retry.count, { immediate = true })
			end)
		end
	end
	local ids = standardIds()
	if #ids == 0 then
		return 0
	end
	local placed = 0
	for i = 1, count do
		if committedCount() >= MAX_ACTIVE or committedCount() >= math.max(0, EncounterDirector.activeCap(currentDifficulty()) - EncounterDirector.bossSeats()) then
			break
		end
		if spawnedThisMission + reservedSeats >= MISSION_SPAWN_BUDGET then
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
			-- S06-034: elite frequency scales with difficulty through EncounterHierarchy —
			-- composition, not hit-point sponge inflation. Standards keep role diversity via uniform pick.
			local eliteChance = EncounterHierarchy.DifficultyEliteFrequency[currentDifficulty()] or 0.10
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
			-- Immediate calls are placements (opening patrols, dormant garrisons, initial defenders):
			-- they were already in the battlespace and do not spend the reinforcement token economy.
			-- Post-opening event responses no longer reach this branch; they use composed waves.
			local isPlacement = opts.immediate == true or openingPlacement
			if isPlacement or tokens >= cost then
				if EnemyService.spawn(id, ground + Vector3.new(0, 3, 0)) then
					if not isPlacement then
						tokens -= cost
					end
					placed += 1
					spawnedThisMission += 1
				end
			end
		end
	end
	return placed
end

-- ---------------------------------------------------------------------------
-- Authored escalation rhythm: mission phase state, directional wave telegraphs, and
-- squad-composed reinforcement execution. This layer deliberately reuses the token
-- economy above instead of creating a second unconstrained spawn system.
-- ---------------------------------------------------------------------------
local function missionEvent(text: string, kind: string?, extra: any?)
	local gf = ReplicatedStorage:FindFirstChild("GF")
	local remotes = gf and gf:FindFirstChild("Remotes")
	local ev = remotes and remotes:FindFirstChild("MissionEvent")
	if ev and ev:IsA("RemoteEvent") then
		local payload = extra or {}
		payload.text = text
		payload.kind = kind or "info"
		ev:FireAllClients(payload)
	end
end

local function setMissionPhase(newPhase: string, reason: string)
	if missionPhase == newPhase then
		return
	end
	missionPhase = newPhase
	workspace:SetAttribute("GF_EncounterPhase", newPhase)
	workspace:SetAttribute("GF_EncounterPhaseReason", reason)
	workspace:SetAttribute("GF_EncounterPhaseAt", os.time())
	-- GF_MissionPhase already has consumers checking extraction_final/emergency. Preserve that
	-- vocabulary for extraction while exposing the richer canonical phase in GF_EncounterPhase.
	local publicPhase = newPhase
	if newPhase == "extraction" then
		publicPhase = "extraction_final"
	end
	workspace:SetAttribute("GF_MissionPhase", publicPhase)

	local now = os.clock()
	if newPhase == "contact" then
		-- MAX, not min: the initial scheduler timestamp is often already in the past when first
		-- contact happens. The first reinforcement should never feel like a spawned-in punishment.
		nextWaveAt = math.max(nextWaveAt, now + 10 + math.random() * 8)
		missionEvent("Voss: hostile patrols are altering course. Contact is likely — watch your approach lanes.", "warning")
	elseif newPhase == "assault" then
		nextWaveAt = math.max(nextWaveAt, now + 6 + math.random() * 6)
		missionEvent("Voss: the objective net is live. Expect coordinated counterattack squads.", "warning")
	elseif newPhase == "extraction" then
		nextWaveAt = math.min(nextWaveAt, now + 2.5)
		-- The enemy commits a held extraction reserve. This is bounded by the same burst cap and
		-- mission spawn budget; it simply prevents the finale from being starved by objective spending.
		tokens = math.min(TOKEN_BURST_CAP, tokens + 2.5)
		raiseAlert(28, "extraction_called", 100)
	end
end

function EncounterDirector.phase(): string
	return missionPhase
end

local function isConquestOperation(): boolean
	local opTemplate = workspace:GetAttribute("GF_OperationTemplate")
	return workspace:GetAttribute("GF_OperationMode") == true
		and type(opTemplate) == "string"
		and string.sub(opTemplate, 1, 9) == "CONQUEST_"
end

local function participantCentroid(): Vector3?
	local sum = Vector3.new(0, 0, 0)
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("GF_MissionParticipant") == true and player:GetAttribute("GF_Aboard") ~= true then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				sum += root.Position
				count += 1
			end
		end
	end
	if count == 0 then
		return nil
	end
	return sum / count
end

local function waveAnchor(phaseName: string): Vector3?
	if phaseName == "extraction" then
		local lz = workspace:GetAttribute("GF_ExtractionLZ") or workspace:GetAttribute("GF_LZ")
		if typeof(lz) == "Vector3" then
			return lz
		end
		local centroidForZone = participantCentroid()
		if extractionZone and centroidForZone then
			return Vector3.new(extractionZone.x, centroidForZone.Y, extractionZone.z)
		end
	end
	local centroid = participantCentroid()
	if not centroid then
		return nil
	end
	-- During objective assault the anchor is biased toward the relay when it exists. Players may
	-- already be fighting away from the console, so this is a pull, not a snap, to the objective.
	if phaseName == "assault" then
		local relay = ObjectiveService.getRelay()
		local center = relay and relay.PrimaryPart and relay.PrimaryPart.Position
		if center then
			return centroid:Lerp(center, 0.35)
		end
	end
	return centroid
end

local function insideQuietZone(position: Vector3): boolean
	for _, z in ipairs(quietZones) do
		local d = (Vector3.new(position.X, 0, position.Z) - Vector3.new(z.x, 0, z.z)).Magnitude
		if d <= (z.radius or 120) then
			return true
		end
	end
	return false
end

local function waveOriginCandidates(anchor: Vector3, phaseName: string): { Vector3 }
	local candidates: { Vector3 } = {}
	if #reinforcementZones > 0 then
		local sorted = {}
		for _, z in ipairs(reinforcementZones) do
			table.insert(sorted, z)
		end
		table.sort(sorted, function(a, b)
			local da = (Vector2.new(a.x, a.z) - Vector2.new(anchor.X, anchor.Z)).Magnitude
			local db = (Vector2.new(b.x, b.z) - Vector2.new(anchor.X, anchor.Z)).Magnitude
			return da < db
		end)
		for i = 1, math.min(3, #sorted) do
			local z = sorted[i]
			table.insert(candidates, Vector3.new(z.x + math.random(-10, 10), anchor.Y, z.z + math.random(-10, 10)))
		end
	end
	for _ = 1, 9 do
		local angle = math.random() * math.pi * 2
		local radius = phaseName == "extraction" and (82 + math.random() * 30) or (92 + math.random() * 34)
		table.insert(candidates, anchor + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	end
	return candidates
end

local function findWaveOrigin(anchor: Vector3, phaseName: string): Vector3?
	for _, candidate in ipairs(waveOriginCandidates(anchor, phaseName)) do
		local ground = groundAt(candidate)
		if ground and missionGrounded(ground) then
			-- Quiet corridors protect the opening route. They are not safe zones during assault or extraction.
			local quietProtected = phaseName ~= "assault" and phaseName ~= "extraction" and insideQuietZone(ground)
			if not quietProtected and EncounterDirector.isSpawnPointValid(ground) then
				return ground
			end
		end
	end
	return nil
end

local function bearingInfo(origin: Vector3, target: Vector3): (number, string)
	local delta = origin - target
	local bearing = (math.deg(math.atan2(delta.X, -delta.Z)) + 360) % 360
	local names = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }
	local index = math.floor(((bearing + 22.5) % 360) / 45) + 1
	return bearing, names[index]
end

local function waveInterval(phaseName: string): number
	if phaseName == "extraction" then
		if workspace:GetAttribute("GF_EmergencyExtraction") == true then
			return 8 + math.random() * 4
		end
		return 11 + math.random() * 6
	elseif phaseName == "assault" then
		return WAVE_MIN_INTERVAL + math.random() * 9
	end
	return 25 + math.random() * (WAVE_MAX_INTERVAL - 25)
end

local function compositionLabel(members: { any }): string
	local hasHeavy = false
	local hasCommand = false
	local hasSupport = false
	for _, member in ipairs(members) do
		if member.role == "heavy" then hasHeavy = true end
		if member.role == "command" then hasCommand = true end
		if member.role == "support" then hasSupport = true end
	end
	if hasHeavy and hasCommand then return "combined arms" end
	if hasHeavy then return "heavy infantry" end
	if hasCommand then return "coordinated infantry" end
	if hasSupport then return "infantry with overwatch" end
	return "infantry"
end

local function clearPendingWave()
	if pendingWave then
		reservedSeats = math.max(0, reservedSeats - #(pendingWave.members or {}))
		tokens = math.min(TOKEN_BURST_CAP, tokens + (pendingWave.cost or 0))
		pendingWave = nil
	end
	workspace:SetAttribute("GF_WaveIncoming", false)
end

-- Public additive hook for objective/alarm lanes. The caller does not spawn anything directly:
-- it requests a response at a meaningful location, and the director schedules a telegraphed squad
-- when the economy/cap can support it. The queue is intentionally tiny; overwhelming the queue
-- drops pressure rather than creating a hidden infinite spawn backlog.
function EncounterDirector.requestWave(center: Vector3, options: any?): boolean
	if workspace:GetAttribute("GF_InMission") ~= true or not missionGrounded(center) then
		return false
	end
	if #eventWaveQueue >= 3 then
		workspace:SetAttribute("GF_WaveRequestsDropped", (tonumber(workspace:GetAttribute("GF_WaveRequestsDropped")) or 0) + 1)
		return false
	end
	local opts = options or {}
	table.insert(eventWaveQueue, {
		center = center,
		sizeHint = math.max(2, math.floor(opts.sizeHint or 3)),
		radius = opts.radius or 24,
		reason = opts.reason or "event_response",
		phase = opts.phase,
		lead = opts.lead,
		silent = opts.silent == true,
		queuedAt = os.clock(),
	})
	workspace:SetAttribute("GF_WaveRequestsQueued", #eventWaveQueue)
	return true
end

local function planWave(now: number, difficulty: string)
	if pendingWave then
		return
	end
	local eventRequest = nil
	if #eventWaveQueue > 0 then
		eventRequest = table.remove(eventWaveQueue, 1)
		workspace:SetAttribute("GF_WaveRequestsQueued", #eventWaveQueue)
	end
	local function restoreEvent()
		if eventRequest then
			eventRequest.attempts = (eventRequest.attempts or 0) + 1
			if eventRequest.attempts < 8 and now - (eventRequest.queuedAt or now) < 35 then
				table.insert(eventWaveQueue, 1, eventRequest)
			else
				workspace:SetAttribute("GF_WaveRequestsDropped", (tonumber(workspace:GetAttribute("GF_WaveRequestsDropped")) or 0) + 1)
			end
			workspace:SetAttribute("GF_WaveRequestsQueued", #eventWaveQueue)
			eventRequest = nil
		end
	end
	if not eventRequest and now < nextWaveAt then
		return
	end
	local phaseForWave = eventRequest and (eventRequest.phase or (missionPhase == "recon" and "contact" or missionPhase)) or missionPhase
	if phaseForWave == "idle" or phaseForWave == "recon" then
		restoreEvent()
		return
	end
	-- Conquest operations already place garrisons/patrols across their objective graph. Preserve
	-- that ownership; the director layers only the signature extraction crush there. Event requests
	-- in operation mode are deliberately dropped rather than double-spawning over the operation layer.
	if isConquestOperation() and phaseForWave ~= "extraction" then
		return
	end
	if squadAllDowned() then
		restoreEvent()
		return
	end
	if not eventRequest and workspace:GetAttribute("GF_Breather") == true and phaseForWave ~= "extraction" then
		return
	end
	local seatsOpen = math.min(
		math.max(0, EncounterDirector.activeCap(difficulty) - EncounterDirector.bossSeats() - activeCount()),
		math.max(0, MISSION_SPAWN_BUDGET - spawnedThisMission)
	)
	if seatsOpen < 2 then
		restoreEvent()
		nextWaveAt = now + 5
		return
	end
	local anchor = eventRequest and eventRequest.center or waveAnchor(phaseForWave)
	if not anchor then
		restoreEvent()
		return
	end
	local origin = findWaveOrigin(anchor, phaseForWave)
	if not origin then
		-- Players sometimes hold fully exposed ground. That is a player win: delay, do not pop in.
		restoreEvent()
		nextWaveAt = now + 5
		return
	end

	local phaseCostCap = phaseForWave == "extraction" and 7.2 or (phaseForWave == "assault" and 5.8 or 4.2)
	phaseCostCap += escalationTier * 0.45
	local maxCost = math.min(tokens, phaseCostCap)
	if maxCost < 2 then
		restoreEvent()
		nextWaveAt = now + 4
		return
	end
	local requestedMembers = eventRequest and math.min(5, eventRequest.sizeHint + 1) or 5
	local members, cost = NPCSquads.composeWave({
		phase = phaseForWave,
		escalation = escalationTier,
		difficulty = difficulty,
		maxCost = maxCost,
		maxMembers = math.min(requestedMembers, seatsOpen),
		playerCount = connectedPlayers(),
		sizeHint = eventRequest and eventRequest.sizeHint or nil,
		seed = math.floor(os.clock() * 1000) + waveSerial * 97,
	})
	if #members < 2 or cost <= 0 then
		restoreEvent()
		nextWaveAt = now + 4
		return
	end

	waveSerial += 1
	local emergency = workspace:GetAttribute("GF_EmergencyExtraction") == true
	local lead = phaseForWave == "extraction" and (emergency and 4.5 or 5.5) or (eventRequest and (eventRequest.lead or 6.0) or WAVE_TELEGRAPH_LEAD)
	tokens -= cost
	reservedSeats += #members
	pendingWave = {
		id = waveSerial,
		members = members,
		cost = cost,
		origin = origin,
		target = anchor,
		spawnAt = now + lead,
		phase = phaseForWave,
		reason = eventRequest and eventRequest.reason or "scheduled_pressure",
		silent = eventRequest and eventRequest.silent == true or false,
	}

	local bearing, direction = bearingInfo(origin, anchor)
	local ids = {}
	for _, member in ipairs(members) do
		table.insert(ids, member.id)
	end
	local comp = compositionLabel(members)
	workspace:SetAttribute("GF_WaveIncoming", true)
	workspace:SetAttribute("GF_WaveId", waveSerial)
	workspace:SetAttribute("GF_WaveETA", math.floor(lead * 10) / 10)
	workspace:SetAttribute("GF_WaveSpawnAt", workspace:GetServerTimeNow() + lead)
	workspace:SetAttribute("GF_WaveOrigin", origin)
	workspace:SetAttribute("GF_WaveTarget", anchor)
	workspace:SetAttribute("GF_WaveBearing", math.floor(bearing + 0.5))
	workspace:SetAttribute("GF_WaveDirection", direction)
	workspace:SetAttribute("GF_WaveSize", #members)
	workspace:SetAttribute("GF_WavePhase", phaseForWave)
	workspace:SetAttribute("GF_WaveReason", pendingWave.reason)
	workspace:SetAttribute("GF_WaveComposition", table.concat(ids, ","))

	local prefix = phaseForWave == "extraction" and "Extraction pressure"
		or (eventRequest and "Reaction squad" or (phaseForWave == "assault" and "Counterattack squad" or "Hostile patrol"))
	if not pendingWave.silent then
		missionEvent(string.format("Voss: %s inbound from the %s — contact in %.0f seconds.", prefix, direction, lead), "warning", {
			waveId = waveSerial,
			origin = origin,
			target = anchor,
			bearing = bearing,
			direction = direction,
			eta = lead,
			spawnAt = workspace:GetServerTimeNow() + lead,
			size = #members,
			composition = comp,
			phase = phaseForWave,
			reason = pendingWave.reason,
		})
	end
end

local function memberSpawnPosition(wave: any, member: any): Vector3?
	for attempt = 1, 6 do
		local jitterRadius = attempt == 1 and 0 or (3 + attempt * 2)
		local jitter = Vector3.new(0, 0, 0)
		if jitterRadius > 0 then
			jitter = Vector3.new(math.random(-jitterRadius, jitterRadius), 0, math.random(-jitterRadius, jitterRadius))
		end
		local ground = groundAt(wave.origin + member.offset + jitter)
		if ground and missionGrounded(ground) and EncounterDirector.isSpawnPointValid(ground) then
			return ground
		end
	end
	return nil
end

local function executePendingWave(now: number)
	local wave = pendingWave
	if not wave or now < wave.spawnAt then
		return
	end
	pendingWave = nil
	reservedSeats = math.max(0, reservedSeats - #wave.members)
	local placed = 0
	local spentCost = 0
	local cap = math.max(0, EncounterDirector.activeCap(currentDifficulty()) - EncounterDirector.bossSeats())
	for _, member in ipairs(wave.members) do
		if activeCount() >= MAX_ACTIVE or activeCount() >= cap then
			break
		end
		if spawnedThisMission >= MISSION_SPAWN_BUDGET then
			break
		end
		local ground = memberSpawnPosition(wave, member)
		if ground then
			local model = EnemyService.spawn(member.id, ground + Vector3.new(0, 3, 0))
			if model then
				model:SetAttribute("GF_WaveId", wave.id)
				model:SetAttribute("GF_WaveRole", member.role)
				placed += 1
				spawnedThisMission += 1
				spentCost += EncounterDirector.threatCost(member.id)
			end
		end
	end
	-- Refund the portion of the reservation that could not be materialized. The reserve is what
	-- guarantees telegraphs are honest without letting failed placement permanently burn the economy.
	tokens = math.min(TOKEN_BURST_CAP, tokens + math.max(0, wave.cost - spentCost))
	workspace:SetAttribute("GF_WaveIncoming", false)
	workspace:SetAttribute("GF_WaveArrived", wave.id)
	workspace:SetAttribute("GF_WaveArrivedSize", placed)
	if placed > 0 then
		wavesLaunched += 1
		workspace:SetAttribute("GF_WavesLaunched", wavesLaunched)
		nextWaveAt = now + waveInterval(wave.phase)
	else
		nextWaveAt = now + 6
	end
end

local function missionTick(now: number, difficulty: string)
	if workspace:GetAttribute("GF_InMission") ~= true then
		return
	end
	executePendingWave(now)

	-- Objective/hack events are read from existing replicated attributes because ObjectiveService
	-- and HackingService belong to other lanes. This keeps the integration additive and event-driven.
	local progress = tonumber(workspace:GetAttribute("GF_ObjectiveProgress")) or 0
	local stage = tostring(workspace:GetAttribute("GF_ObjectiveStage") or "")
	if progress > lastObjectiveProgress then
		raiseAlert(3.5, "objective_progress", 70)
		lastObjectiveProgress = progress
	end
	local misses = tonumber(workspace:GetAttribute("GF_HackMisses")) or 0
	if misses > (EncounterDirector.lastHackMisses or 0) then
		EncounterDirector.lastHackMisses = misses
		raiseAlert(22, "hack_alarm", 90)
		if missionPhase ~= "extraction" then
			setMissionPhase("assault", "hack_alarm")
		end
	end
	local hacks = tonumber(workspace:GetAttribute("GF_HackComplete")) or 0
	if hacks > (EncounterDirector.lastHackCompletes or 0) then
		EncounterDirector.lastHackCompletes = hacks
		raiseAlert(9, "hack_complete", 70)
		if missionPhase == "contact" or missionPhase == "recon" then
			setMissionPhase("assault", "hack_complete")
		end
	end
	-- Scout beacons and Officer relay calls still spawn inside EnemyService (another lane). Count
	-- those already-materialized reinforcements against the mission budget here so bypass spawns
	-- shrink future director waves instead of silently exceeding the patrol budget.
	local reinforcements = tonumber(workspace:GetAttribute("GF_Reinforcements")) or 0
	if reinforcements > (EncounterDirector.lastReinforcementCount or 0) then
		spawnedThisMission += reinforcements - (EncounterDirector.lastReinforcementCount or 0)
		EncounterDirector.lastReinforcementCount = reinforcements
	end

	if workspace:GetAttribute("GF_ExtractionCalled") == true or workspace:GetAttribute("GF_EmergencyExtraction") == true then
		setMissionPhase("extraction", workspace:GetAttribute("GF_EmergencyExtraction") == true and "emergency_extraction" or "extraction_called")
	elseif missionPhase == "recon" then
		local engaged = (tonumber(workspace:GetAttribute("GF_EnemiesEngaged")) or 0) > 0
			or (tonumber(workspace:GetAttribute("GF_EnemiesTracked")) or 0) > 0
		if engaged or alert >= 15 or progress > 0 or now >= reconUntil then
			if engaged then
				raiseAlert(12, "sighting", 60)
			end
			setMissionPhase("contact", engaged and "first_contact" or (progress > 0 and "objective_started" or "time_in_territory"))
		end
	elseif missionPhase == "contact" then
		local stageAdvanced = stage ~= lastObjectiveStage and progress >= 5
		if progress >= 25 or stageAdvanced or alert >= 55 then
			setMissionPhase("assault", progress >= 25 and "objective_progress" or (stageAdvanced and "objective_stage" or "lockdown_pressure"))
		end
	end
	if stage ~= lastObjectiveStage then
		lastObjectiveStage = stage
	end

	planWave(now, difficulty)
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
	clearPendingWave()
	tokens = TOKEN_BURST_CAP
	alert = 0
	alertSource = "quiet"
	lastGunfireAlarmAt = 0
	missionPhase = "idle"
	escalationTier = 0
	reconUntil = 0
	nextWaveAt = 0
	wavesLaunched = 0
	missionStartedAt = 0
	eventWaveQueue = {}
	lastObjectiveProgress = 0
	lastObjectiveStage = ""
	reservedSeats = 0
	workspace:SetAttribute("GF_EncounterPhase", "idle")
	workspace:SetAttribute("GF_MissionPhase", "idle")
	workspace:SetAttribute("GF_WavesLaunched", 0)
	workspace:SetAttribute("GF_WaveIncoming", false)
	workspace:SetAttribute("GF_WaveArrived", 0)
	workspace:SetAttribute("GF_EscalationTier", 0)
	publishAlert()
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

function EncounterDirector.spawnPosts(center: Vector3, count: number): number
	if not missionGrounded(center) then
		return 0
	end
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
					if farEnough and activeCount() < MAX_ACTIVE + 2 and spawnedThisMission < MISSION_SPAWN_BUDGET then
						local id = (placed == 0) and "Marksman" or "Rifleman"
						if EnemyService.spawn(id, ground + Vector3.new(0, 3, 0)) then
							placed += 1
							spawnedThisMission += 1
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
	reinforcementZones = {}
	quietZones = {}
	extractionZone = nil
	if not plan or not plan.encounterZones then
		return 0
	end
	for _, z in plan.encounterZones do
		if z.kind == "reinforcement" then
			table.insert(reinforcementZones, {
				x = z.x, z = z.z,
				radius = z.radius or 24,
				dir = z.dir or 0,
				installationId = z.installationId,
			})
		elseif z.kind == "quiet" then
			table.insert(quietZones, { x = z.x, z = z.z, radius = z.radius or 130 })
		elseif z.kind == "extraction_pressure" then
			extractionZone = { x = z.x, z = z.z, radius = z.radius or 160 }
		elseif z.kind == "garrison" then
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
							EncounterDirector.spawnAround(center, z.radius, z.size, { immediate = true, reason = "battlefield_garrison" })
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
	clearPendingWave()
	tokens = TOKEN_BURST_CAP
	alert = 0
	alertSource = "quiet"
	lastGunfireAlarmAt = 0
	lastRefillAt = os.clock()
	wavesLaunched = 0
	waveSerial = 0
	reconUntil = lastRefillAt + 70
	nextWaveAt = lastRefillAt + 34
	lastObjectiveProgress = tonumber(workspace:GetAttribute("GF_ObjectiveProgress")) or 0
	lastObjectiveStage = tostring(workspace:GetAttribute("GF_ObjectiveStage") or "")
	EncounterDirector.lastHackMisses = tonumber(workspace:GetAttribute("GF_HackMisses")) or 0
	EncounterDirector.lastHackCompletes = tonumber(workspace:GetAttribute("GF_HackComplete")) or 0
	EncounterDirector.lastEscalationTier = 0
	EncounterDirector.lastTransmitCount = tonumber(workspace:GetAttribute("GF_ScoutTransmits")) or 0
	EncounterDirector.lastReinforcementCount = 0
	missionStartedAt = lastRefillAt
	eventWaveQueue = {}
	dormantZones = {}
	reinforcementZones = {}
	quietZones = {}
	extractionZone = nil
	workspace:SetAttribute("GF_WaveRequestsQueued", 0)
	workspace:SetAttribute("GF_WaveRequestsDropped", 0)
	workspace:SetAttribute("GF_ExtractionCalled", false)
	workspace:SetAttribute("GF_WavesLaunched", 0)
	workspace:SetAttribute("GF_WaveArrived", 0)
	workspace:SetAttribute("GF_WaveIncoming", false)
	missionPhase = "idle"
	setMissionPhase("recon", "deployment")
	publishAlert()
	if not refillRunning then
		refillRunning = true
		task.spawn(function()
			while true do
				task.wait(1)
				if workspace:GetAttribute("GF_InMission") == true then
					local difficulty = currentDifficulty()
					refillTokens(difficulty)
					missionTick(os.clock(), difficulty)
					local stats = EncounterDirector.economyStats()
					workspace:SetAttribute("GF_EconomyTokens", stats.tokens)
					workspace:SetAttribute("GF_EconomyAlert", stats.alert)
					workspace:SetAttribute("GF_EconomyCap", stats.cap)
					workspace:SetAttribute("GF_EconomyPhaseScalar", stats.phase)
					workspace:SetAttribute("GF_EconomyPhase", missionPhase)
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
				spawnedThisMission += 1
				workspace:SetAttribute("GF_RelayCommander", true)
			end
		end
		EncounterDirector.spawnAround(center, 34, PATROL_COUNT, { immediate = true, reason = "opening_patrol" })
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
		EncounterDirector.spawnAround(Vector3.new(0, 0, -120), 34, PATROL_COUNT, { immediate = true, reason = "opening_patrol" })
		if ObjectiveService.getTemplate() ~= "ELIM_WALKER" then
			EncounterDirector.spawnBoss(Vector3.new(0, 0, -175))
		end
	end
end
function EncounterDirector.startExtractionPressure(): ()
	workspace:SetAttribute("GF_ExtractionCalled", true)
	-- The extraction crush is event-driven now: beginMission's economy/mission loop observes this
	-- flag, switches phase, telegraphs a composed squad, and schedules escalating follow-up waves.
	-- No parallel flat spawn loop exists here, so there is no second refill or unbounded timer to leak.
	setMissionPhase("extraction", workspace:GetAttribute("GF_EmergencyExtraction") == true and "emergency_extraction" or "extraction_called")
	nextWaveAt = math.min(nextWaveAt, os.clock() + 1.5)
end
function EncounterDirector.stats()
	return {
		active = activeCount(),
		cap = MAX_ACTIVE,
		spawned = spawnedThisMission,
		budget = MISSION_SPAWN_BUDGET,
		phase = missionPhase,
		escalation = escalationTier,
		alert = math.floor(alert),
		waves = wavesLaunched,
	}
end
return EncounterDirector
