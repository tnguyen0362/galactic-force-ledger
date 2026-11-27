--!strict
-- MissionServerInit: boot orchestrator for the standalone mission place (place-split migration,
-- owner directive 2026-11-28). In the split architecture this is the FIRST code that runs when a
-- mission server spins up — ahead of player arrival — so the world generates behind the teleport
-- loading screen instead of in front of a waiting squad. Measured budget: geo 6.5s + veg 11.5s.
--
-- Sequence contract:
--   1. read deploy intent (seed/difficulty/template/squad) from teleport data or pinned attrs
--   2. capture arrivals into a high, anchored holding pen before generation writes voxels
--   3. generate geography from the mission seed — every mission a different landform
--   4. plant vegetation, choose mission anchors on the generated terrain
--   5. signal GF_TerrainReady, then land every held player on raycast-verified ground at the LZ
--
-- Arrival contract (owner report 2026-11-28: "the world generates above you"):
-- players are server-side cargo until the terrain write is complete. The holding pen is far above
-- the write volume, the root is anchored while waiting, and release raycasts the real Terrain voxel
-- surface at the actual insertion offset — never a baked Y. GF_Teleporting is held true through the
-- landing because the client loading screen already understands that attribute; GF_ArrivalState is
-- the machine-legible server state for probes and future UI.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local MissionServerInit = {}

export type DeployIntent = {
	seed: number,
	difficulty: string,
	template: string,
	squadUserIds: { number },
}

-- ---------------------------------------------------------------------------
-- Arrival sequencer
-- ---------------------------------------------------------------------------

local HOLD_Y = 4200 -- terrain relief is hundreds of studs; the pen is far outside the write volume
local ARRIVAL_TIMEOUT_SECONDS = 40 -- measured generation is ~18s; 40 is generous without stranding
local STREAM_TIMEOUT_SECONDS = 3.5
local GROUND_SETTLE_SECONDS = 3 -- matches the streaming evidence that multi-kilometre terrain needs seconds, not frames
local CHARACTER_WAIT_SECONDS = 6
local FALLBACK_GROUND_Y = 36 -- emergency failure pad only; normal release always uses raycast terrain

type ArrivalRecord = {
	slot: number,
	state: string,
	token: number,
	characterVersion: number,
	positioningActive: boolean,
	fallbackPoint: Vector3?,
	characterAdded: RBXScriptConnection?,
}

local arrivalStarted = false
local arrivalReleaseStarted = false
local arrivalFinalized = false
local arrivalPhase = "idle"
local releaseReason = "terrain-ready"
local arrivalClockStart = 0
local nextArrivalSlot = 0
local arrivalRecords: { [Player]: ArrivalRecord } = {}
-- Mission.luau's legacy TerrainService path can still exist during the migration. If this
-- orchestrator has begun its own authoritative write, an early ready edge from that legacy writer
-- must not open the gate halfway through the orchestrator's write. When boot() is not in use (old
-- validation paths), external ready edges remain authoritative exactly as before.
local bootGenerationStarted = false
local bootGenerationComplete = false

local holdModel: Model? = nil
local holdSpawn: SpawnLocation? = nil
local missionSpawn: SpawnLocation? = nil
local spawnGuardConnection: RBXScriptConnection? = nil
local disabledSpawnStates: { [SpawnLocation]: boolean } = {}

local terrainOnlyParams = RaycastParams.new()
terrainOnlyParams.FilterType = Enum.RaycastFilterType.Include
terrainOnlyParams.FilterDescendantsInstances = { Workspace.Terrain }
terrainOnlyParams.IgnoreWater = true

local function terrainReadyForArrival(): boolean
	return Workspace:GetAttribute("GF_TerrainReady") == true
		and (not bootGenerationStarted or bootGenerationComplete)
end

local function updateArrivalCounts()
	local holding, positioning, released = 0, 0, 0
	for player, rec in pairs(arrivalRecords) do
		if player.Parent then
			if rec.state == "holding" then
				holding += 1
			elseif rec.state == "positioning" then
				positioning += 1
			elseif rec.state == "released" then
				released += 1
			end
		end
	end
	Workspace:SetAttribute("GF_ArrivalHeldCount", holding)
	Workspace:SetAttribute("GF_ArrivalPositioningCount", positioning)
	Workspace:SetAttribute("GF_ArrivalReleasedCount", released)
end

local function setArrivalPhase(phase: string, reason: string?)
	arrivalPhase = phase
	Workspace:SetAttribute("GF_ArrivalState", phase)
	if reason then
		Workspace:SetAttribute("GF_ArrivalReason", reason)
	end
	updateArrivalCounts()
end

local function neutralizePart(part: BasePart)
	pcall(function()
		part.AssemblyLinearVelocity = Vector3.new()
		part.AssemblyAngularVelocity = Vector3.new()
	end)
end

local function holdCFrame(slot: number): CFrame
	local index = math.max(0, slot - 1)
	local ringIndex = index % 25
	local x = ((ringIndex % 5) - 2) * 10
	local z = ((math.floor(ringIndex / 5) % 5) - 2) * 10
	local layer = math.floor(index / 25)
	return CFrame.new(x, HOLD_Y + 4 + layer * 8, z)
end

local function foreignSpawnDisabled(inst: Instance)
	if inst:IsA("SpawnLocation") and inst ~= holdSpawn and inst ~= missionSpawn then
		if inst.Enabled and disabledSpawnStates[inst] == nil then
			disabledSpawnStates[inst] = inst.Enabled
		end
		inst.Enabled = false
	end
end

local function disableForeignSpawns()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		foreignSpawnDisabled(inst)
	end
end

local function ensureHoldingWorld()
	if holdModel and holdModel.Parent then
		return
	end

	local model = Instance.new("Model")
	model.Name = "GF_ArrivalHoldingPen"

	local platform = Instance.new("Part")
	platform.Name = "Platform"
	platform.Size = Vector3.new(180, 2, 180)
	platform.CFrame = CFrame.new(0, HOLD_Y, 0)
	platform.Anchored = true
	platform.CanCollide = true
	platform.CanQuery = false
	platform.CanTouch = false
	platform.Transparency = 1
	platform.Parent = model

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ArrivalHoldSpawn"
	spawn.Size = Vector3.new(16, 1, 16)
	spawn.CFrame = CFrame.new(0, HOLD_Y + 1.5, 0)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = true
	spawn.Parent = model

	holdSpawn = spawn
	model.Parent = Workspace
	holdModel = model

	-- During the hold there must be exactly one possible spawn outcome. A leftover baseplate or
	-- station spawn otherwise wins the lottery and drops the arrival into unfinished terrain.
	disableForeignSpawns()
	spawnGuardConnection = Workspace.DescendantAdded:Connect(function(inst)
		if arrivalPhase == "holding" then
			foreignSpawnDisabled(inst)
		end
	end)
end

local function probablyMissionPlace(): boolean
	local lobbyId = Workspace:GetAttribute("GF_LobbyPlaceId")
	local missionId = Workspace:GetAttribute("GF_MissionPlaceId")
	return Workspace:GetAttribute("GF_AmMissionPlace") == true
		or (type(lobbyId) == "number" and lobbyId ~= game.PlaceId)
		or (type(missionId) == "number" and missionId == game.PlaceId)
end

local function removeHoldingWorld()
	if spawnGuardConnection then
		spawnGuardConnection:Disconnect()
		spawnGuardConnection = nil
	end
	if holdSpawn then
		holdSpawn.Enabled = false
	end
	-- Keep the invisible high platform in place. It costs one part, cannot intersect gameplay at
	-- y=4200, and remains a physical backstop for the rare player whose first landing attempt is
	-- interrupted by a death/character reload and needs a retry after the initial cohort finishes.
	holdSpawn = nil

	-- The shared-place validation path must not eat the station spawn. In a real mission place the
	-- mission LZ spawn below is the only sane default respawn, so foreign spawns stay disabled.
	if not probablyMissionPlace() then
		for spawn, wasEnabled in pairs(disabledSpawnStates) do
			if spawn.Parent then
				spawn.Enabled = wasEnabled
			end
		end
		table.clear(disabledSpawnStates)
	end
end

local function ensureMissionSpawn(ground: Vector3)
	local spawn = missionSpawn
	if not spawn or not spawn.Parent then
		local existing = Workspace:FindFirstChild("GF_MissionLZSpawn")
		if existing and existing:IsA("SpawnLocation") then
			spawn = existing
		else
			spawn = Instance.new("SpawnLocation")
			spawn.Name = "GF_MissionLZSpawn"
			spawn.Size = Vector3.new(16, 1, 16)
			spawn.Anchored = true
			spawn.CanCollide = false
			spawn.Transparency = 1
			spawn.Neutral = true
			spawn.Duration = 0
			-- Assign before parenting: DescendantAdded fires synchronously, and the spawn guard must
			-- already know this is the mission LZ spawn rather than a foreign spawn to disable.
			missionSpawn = spawn
			spawn.Parent = Workspace
		end
		missionSpawn = spawn
	end
	spawn.CFrame = CFrame.new(ground + Vector3.new(0, 0.55, 0))
	spawn.Enabled = true
end

local function ensureEmergencyPad(ground: Vector3)
	local existing = Workspace:FindFirstChild("GF_ArrivalEmergencyPad")
	local pad: Part
	if existing and existing:IsA("Part") then
		pad = existing
	else
		pad = Instance.new("Part")
		pad.Name = "GF_ArrivalEmergencyPad"
		pad.Size = Vector3.new(96, 2, 96)
		pad.Color = Color3.fromRGB(54, 62, 72)
		pad.Material = Enum.Material.Metal
		pad.Anchored = true
		pad.CanCollide = true
		pad.Transparency = 0.15
		pad.Parent = Workspace
	end
	pad.CFrame = CFrame.new(ground - Vector3.new(0, 1.05, 0))
end

local function terrainSurfaceAt(x: number, z: number): Vector3?
	local hit = Workspace:Raycast(Vector3.new(x, 1800, z), Vector3.new(0, -3000, 0), terrainOnlyParams)
	return hit and hit.Position or nil
end

local function terrainSurfaceNear(x: number, z: number): Vector3?
	local direct = terrainSurfaceAt(x, z)
	if direct then
		return direct
	end
	for _, radius in ipairs({ 8, 16 }) do
		for step = 0, 7 do
			local angle = math.rad(step * 45)
			local hit = terrainSurfaceAt(x + math.cos(angle) * radius, z + math.sin(angle) * radius)
			if hit then
				return hit
			end
		end
	end
	return nil
end

local function xzFromVectorAttribute(name: string): (number?, number?)
	local value = Workspace:GetAttribute(name)
	if typeof(value) == "Vector3" then
		return value.X, value.Z
	end
	return nil, nil
end

local function lzAnchorXZ(): (number, number)
	-- GF_AnchorLZ is the mission-server terrain-analysis anchor and is authoritative. GF_LZ is a
	-- compatibility fallback for partially migrated flows; the legacy compact-layout LZ is z=+118.
	for _, name in ipairs({ "GF_AnchorLZ", "GF_OperationLZ", "GF_LZ" }) do
		local x, z = xzFromVectorAttribute(name)
		if x and z then
			return x, z
		end
	end
	return 0, 118
end

local function objectiveXZ(fallbackX: number, fallbackZ: number): (number, number)
	for _, name in ipairs({ "GF_AnchorObjective", "GF_Objective", "GF_ObjectiveLZ" }) do
		local x, z = xzFromVectorAttribute(name)
		if x and z then
			return x, z
		end
	end
	return fallbackX, fallbackZ - 240 -- legacy insertion faces toward the operation, not the void
end

local function slotOffset(slot: number): (number, number)
	if slot <= 1 then
		return 0, 0
	end
	-- Golden-angle spread keeps squadmates apart without a grid-looking teleport line.
	local angle = (slot - 1) * 2.39996322972865332
	local radius = 5 + math.min(15, math.floor((slot - 2) / 8) * 3)
	return math.cos(angle) * radius, math.sin(angle) * radius
end

local function landingPointForSlot(slot: number): (Vector3, boolean)
	local centerX, centerZ = lzAnchorXZ()
	local offsetX, offsetZ = slotOffset(slot)
	local x = centerX + offsetX
	local z = centerZ + offsetZ

	local surface = terrainSurfaceNear(x, z)
	if surface then
		return surface + Vector3.new(0, 4, 0), true
	end

	-- If the exact offset misses (edge hole/partial write), prefer the verified centre over a guess.
	local centerSurface = terrainSurfaceNear(centerX, centerZ)
	if centerSurface then
		return centerSurface + Vector3.new(0, 4, 0), true
	end

	-- Timeout/failure path: never strand a player in the sky forever. The pad is small, visible,
	-- and only exists when there is no terrain surface to stand on at all.
	local fallbackGround = Vector3.new(centerX, FALLBACK_GROUND_Y, centerZ)
	ensureEmergencyPad(fallbackGround)
	return Vector3.new(x, FALLBACK_GROUND_Y + 4, z), false
end

local function landingCFrame(target: Vector3): CFrame
	local centerX, centerZ = lzAnchorXZ()
	local objectiveX, objectiveZ = objectiveXZ(centerX, centerZ)
	local lookAt = Vector3.new(objectiveX, target.Y, objectiveZ)
	if (lookAt - target).Magnitude < 1 then
		return CFrame.new(target)
	end
	return CFrame.lookAt(target, lookAt)
end

local function ensureCharacter(player: Player, timeoutSeconds: number): Model?
	local started = os.clock()
	local loadAttempted = false
	while player.Parent and os.clock() - started < timeoutSeconds do
		local character = player.Character
		if character and character.Parent then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health <= 0 and not loadAttempted then
					loadAttempted = true
					pcall(function()
						player:LoadCharacter()
					end)
				elseif not humanoid or humanoid.Health > 0 then
					return character
				end
			end
		elseif not loadAttempted and os.clock() - started > 0.5 then
			loadAttempted = true
			pcall(function()
				player:LoadCharacter()
			end)
		end
		task.wait(0.1)
	end
	return nil
end

local function characterIsLive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return not humanoid or humanoid.Health > 0
end

local function positionPlayerOnGround(player: Player, rec: ArrivalRecord, reason: string)
	if rec.positioningActive or not player.Parent then
		return
	end
	rec.positioningActive = true
	rec.state = "positioning"
	player:SetAttribute("GF_ArrivalState", "positioning")
	updateArrivalCounts()

	local success = false
	for _attempt = 1, 3 do
		local character = ensureCharacter(player, CHARACTER_WAIT_SECONDS)
		if not character then
			break
		end

		rec.token += 1
		local token = rec.token
		local version = rec.characterVersion
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			-- Anchor before the streaming wait: client terrain replication is the last unsafe gap.
			root.Anchored = true
			neutralizePart(root)

			local target, onTerrain = landingPointForSlot(rec.slot)
			pcall(function()
				player:RequestStreamAroundAsync(target, STREAM_TIMEOUT_SECONDS)
			end)

			local function stillCurrent(): boolean
				return player.Parent ~= nil
					and character.Parent ~= nil
					and player.Character == character
					and rec.token == token
					and rec.characterVersion == version
					and root.Parent ~= nil
					and characterIsLive(character)
			end

			if stillCurrent() then
				character:PivotTo(landingCFrame(target))
				neutralizePart(root)
				task.wait(GROUND_SETTLE_SECONDS)
			end

			if stillCurrent() then
				root.Anchored = false
				neutralizePart(root)
				rec.state = "released"
				-- Timeout landings remain recoverable even when the raycast found partial terrain:
				-- if the slow writer later completes, a player who has not moved off the landing
				-- point is re-seated onto the final surface. Normal ready landings never are.
				local timeoutRelease = string.sub(reason, 1, 7) == "timeout"
				rec.fallbackPoint = if timeoutRelease or not onTerrain then target else nil
				player:SetAttribute("GF_ArrivalState", "released")
				-- place-split has no lobby-side StationService.deploy in this server: release onto the
				-- surface is the authoritative server-confirmed mission arrival.
				player:SetAttribute("GF_MissionParticipant", true)
				success = true
				print(string.format("MissionServer: arrival landed player=%s terrain=%s reason=%s", player.Name, tostring(onTerrain), reason))
				break
			end
		end
	end

	rec.positioningActive = false
	updateArrivalCounts()
	if not success and player.Parent then
		warn("MissionServer: arrival positioning incomplete for " .. player.Name .. " — retrying")
		task.delay(3, function()
			if player.Parent and rec.state ~= "released" and not rec.positioningActive then
				positionPlayerOnGround(player, rec, reason .. ":retry")
			end
		end)
	end
end

local function captureCharacterInHold(player: Player, rec: ArrivalRecord, character: Model)
	if rec.state ~= "holding" or arrivalReleaseStarted then
		return
	end
	task.spawn(function()
		local root: BasePart? = nil
		for _step = 1, 60 do
			if not player.Parent or not character.Parent or rec.state ~= "holding" or arrivalReleaseStarted then
				return
			end
			local candidate = character:FindFirstChild("HumanoidRootPart")
			if candidate and candidate:IsA("BasePart") then
				root = candidate
				break
			end
			task.wait(0.05)
		end
		if not root then
			return
		end
		-- Anchor first, then move: even a player who slipped in before the pen scan stops falling
		-- immediately. The platform underneath is the second layer of protection.
		neutralizePart(root)
		root.Anchored = true
		character:PivotTo(holdCFrame(rec.slot))
		player:SetAttribute("GF_ArrivalState", "holding")
		updateArrivalCounts()
	end)
end

local function handleArrivalCharacter(player: Player, rec: ArrivalRecord, character: Model)
	rec.characterVersion += 1
	if rec.state == "holding" and not arrivalReleaseStarted and not terrainReadyForArrival() then
		captureCharacterInHold(player, rec, character)
	elseif rec.state == "positioning" and not rec.positioningActive then
		task.spawn(positionPlayerOnGround, player, rec, "character-ready")
	end
end

local function trackArrival(player: Player)
	if arrivalRecords[player] then
		return
	end
	nextArrivalSlot += 1
	local rec: ArrivalRecord = {
		slot = nextArrivalSlot,
		state = "holding",
		token = 0,
		characterVersion = 0,
		positioningActive = false,
		fallbackPoint = nil,
		characterAdded = nil,
	}
	arrivalRecords[player] = rec
	player:SetAttribute("GF_ArrivalState", arrivalReleaseStarted and "positioning" or "holding")
	rec.characterAdded = player.CharacterAdded:Connect(function(character)
		handleArrivalCharacter(player, rec, character)
	end)
	if player.Character then
		handleArrivalCharacter(player, rec, player.Character)
	end
	if arrivalReleaseStarted or terrainReadyForArrival() then
		task.spawn(positionPlayerOnGround, player, rec, "join-after-ready")
	else
		updateArrivalCounts()
	end
end

local function cleanupArrival(player: Player)
	local rec = arrivalRecords[player]
	if rec and rec.characterAdded then
		rec.characterAdded:Disconnect()
	end
	arrivalRecords[player] = nil
	updateArrivalCounts()
end

local function finishInitialRelease()
	if arrivalFinalized then
		return
	end
	arrivalFinalized = true
	removeHoldingWorld()
	if releaseReason == "timeout" then
		setArrivalPhase("degraded", releaseReason)
	else
		setArrivalPhase("ready", releaseReason)
	end
	-- The squad is physically at the LZ now. Re-edge the mission flag so services that reacted
	-- during the presentation hold clear any sky-seeded placement and rebuild from ground truth.
	Workspace:SetAttribute("GF_InMission", false)
	Workspace:SetAttribute("GF_InMission", true)
	-- Existing client contract: GF_Teleporting keeps the loading overlay up through the last unsafe
	-- replication window. It only clears after the anchored ground settle has completed.
	Workspace:SetAttribute("GF_Teleporting", false)
	print(string.format("MissionServer: arrival release complete reason=%s", releaseReason))
end

local function releaseAllArrivals(reason: string)
	if arrivalReleaseStarted then
		return
	end
	arrivalReleaseStarted = true
	releaseReason = reason

	-- Resolve and publish the LZ before moving anybody. Consumers (extraction, join-in-progress
	-- dispatch, respawn) all need the same ground truth. Y remains raycast-verified terrain here.
	local centerX, centerZ = lzAnchorXZ()
	local centerSurface = terrainSurfaceNear(centerX, centerZ)
	local publishedGround = centerSurface or Vector3.new(centerX, FALLBACK_GROUND_Y, centerZ)
	if not centerSurface then
		ensureEmergencyPad(publishedGround)
	end
	Workspace:SetAttribute("GF_LZ", publishedGround)
	ensureMissionSpawn(publishedGround)
	-- From this point any death/respawn must use the verified LZ spawn, never the sky pen.
	if holdSpawn then
		holdSpawn.Enabled = false
	end
	-- Hold the client transition overlay through stream-in + anchored ground settle. The mission
	-- flag itself is re-edged only after the landing cohort is down, so mission-services rebuild
	-- from the verified LZ rather than keeping anything they may have seeded against the sky pen.
	Workspace:SetAttribute("GF_Teleporting", true)

	if reason == "timeout" then
		setArrivalPhase("landing", reason)
		warn("MissionServer: terrain wait timed out — releasing arrivals onto verified ground or the emergency pad")
	else
		setArrivalPhase("landing", reason)
	end

	local pending: { Player } = {}
	for player, rec in pairs(arrivalRecords) do
		if player.Parent and rec.state ~= "released" then
			table.insert(pending, player)
		end
	end

	if #pending == 0 then
		finishInitialRelease()
		return
	end

	local finished = 0
	for _, player in ipairs(pending) do
		local rec = arrivalRecords[player]
		if rec then
			task.spawn(function()
				positionPlayerOnGround(player, rec, reason)
				finished += 1
				if finished >= #pending then
					finishInitialRelease()
				end
			end)
		else
			finished += 1
		end
	end
	if finished >= #pending then
		finishInitialRelease()
	end
end

local function recoverTimeoutArrivalsOnLateTerrain()
	-- If the 40s fail-safe fired while a slow generator eventually continued, only recover players
	-- who are still on the emergency pad. Anyone who managed to leave it is already playing and
	-- must never be yanked back across the map.
	if releaseReason ~= "timeout" then
		return
	end
	-- The writer did eventually finish. Even if nobody needs physical recovery, the machine-readable
	-- arrival state should stop reporting a degraded boot once final terrain exists.
	setArrivalPhase("ready", "late-terrain-ready")
	for player, rec in pairs(arrivalRecords) do
		if player.Parent and rec.state == "released" and rec.fallbackPoint and not rec.positioningActive then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - rec.fallbackPoint).Magnitude <= 28 then
				rec.state = "positioning"
				task.spawn(positionPlayerOnGround, player, rec, "late-terrain-ready")
			else
				rec.fallbackPoint = nil
			end
		end
	end
end

function MissionServerInit.startArrivalControl()
	if arrivalStarted then
		return
	end
	arrivalStarted = true
	arrivalClockStart = os.clock()

	ensureHoldingWorld()
	setArrivalPhase("holding", "terrain-write")
	-- Presentation is mission-side from the first teleport frame. The loading screen reads
	-- GF_InMission + GF_ArrivalState together for its orbital-hold copy. Any mission-scoped service
	-- that reacts too early is deliberately re-edged at finishInitialRelease, after the squad is on
	-- verified ground and GF_LZ exists, so premature sky-seeded placements cannot survive.
	Workspace:SetAttribute("GF_InMission", true)
	Workspace:SetAttribute("GF_Teleporting", true)
	Workspace:SetAttribute("GF_ArrivalTimeoutSeconds", ARRIVAL_TIMEOUT_SECONDS)

	Players.PlayerAdded:Connect(trackArrival)
	Players.PlayerRemoving:Connect(cleanupArrival)
	for _, player in ipairs(Players:GetPlayers()) do
		trackArrival(player)
	end
	-- SpawnLocations can be created/enabled by other boot services after the first scan. Keep the
	-- hold deterministic for the whole write rather than trusting boot ordering.
	task.spawn(function()
		while not arrivalReleaseStarted do
			disableForeignSpawns()
			task.wait(1)
		end
	end)

	Workspace:GetAttributeChangedSignal("GF_TerrainReady"):Connect(function()
		if terrainReadyForArrival() then
			if not arrivalReleaseStarted then
				task.spawn(releaseAllArrivals, "terrain-ready")
			else
				task.spawn(recoverTimeoutArrivalsOnLateTerrain)
			end
		end
	end)

	task.spawn(function()
		while not arrivalReleaseStarted do
			if terrainReadyForArrival() then
				releaseAllArrivals("terrain-ready")
				return
			end
			if os.clock() - arrivalClockStart >= ARRIVAL_TIMEOUT_SECONDS then
				releaseAllArrivals("timeout")
				return
			end
			task.wait(0.25)
		end
	end)

	print("MissionServer: arrival control active — players held above terrain write volume")
end

-- Deploy intent crosses the teleport boundary as join data; a pinned-attribute path exists for
-- deterministic validation runs in Studio. Anything missing falls back to random/Normal/SABOTAGE.
function MissionServerInit.readIntent(): DeployIntent
	-- Attributes are the deterministic Studio-validation fallback; a decoded v1 deploy contract
	-- wins when present. The wait below is safe because arrival control is already active before
	-- boot() is called: the contract-bearing first arrival is held while this resolves the seed.
	local seed = Workspace:GetAttribute("GF_DeploySeed")
	if type(seed) ~= "number" or seed == 0 then
		seed = (os.time() * 997 + math.random(1, 99999)) % 900000 + 1
	end
	local difficulty = Workspace:GetAttribute("GF_DeployDifficulty")
	if type(difficulty) ~= "string" then difficulty = "Normal" end
	local template = Workspace:GetAttribute("GF_DeployTemplate")
	if type(template) ~= "string" then template = "SABOTAGE_RELAY" end
	local squadUserIds: { number } = {}

	local ok, DeployContract = pcall(require, game:GetService("ReplicatedStorage").GF.Shared.DeployContract)
	local contractIntent: any = nil
	if ok and DeployContract then
		-- A reserved mission server commonly boots before the first teleport recipient exists.
		-- Wait briefly for that contract-bearing arrival; once a player is present, join data is
		-- normally immediate, so only a short grace is needed before accepting Studio/pinned fallback.
		local firstPlayerSeenAt: number? = nil
		local deadline = os.clock() + 12
		while os.clock() < deadline do
			local playerCount = 0
			for _, player in ipairs(Players:GetPlayers()) do
				playerCount += 1
				local intent = DeployContract.fromPlayer(player)
				if intent
					and type(intent.seed) == "number"
					and type(intent.difficulty) == "string"
					and type(intent.template) == "string" then
					contractIntent = intent
					break
				end
			end
			if contractIntent then
				break
			end
			if playerCount > 0 then
				firstPlayerSeenAt = firstPlayerSeenAt or os.clock()
				if os.clock() - firstPlayerSeenAt >= 1.5 then
					break
				end
			end
			task.wait(0.1)
		end
	end
	if contractIntent then
		seed = contractIntent.seed
		difficulty = contractIntent.difficulty
		template = contractIntent.template
		if type(contractIntent.squadUserIds) == "table" then
			squadUserIds = contractIntent.squadUserIds
		end
		if type(contractIntent.lobbyPlaceId) == "number" then
			Workspace:SetAttribute("GF_LobbyPlaceId", contractIntent.lobbyPlaceId)
		end
		Workspace:SetAttribute("GF_DeployContractLive", true)
	end
	return { seed = seed, difficulty = difficulty, template = template, squadUserIds = squadUserIds }
end

function MissionServerInit.boot(intent: DeployIntent): ()
	Workspace:SetAttribute("GF_MissionWorldReady", false)
	bootGenerationStarted = true
	bootGenerationComplete = false
	-- Reset before starting arrival control: the client loading screen and this sequencer share
	-- GF_TerrainReady as the authoritative terrain-write completion signal.
	Workspace:SetAttribute("GF_TerrainReady", false)
	MissionServerInit.startArrivalControl()

	local t0 = os.clock()
	local Services = ServerScriptService.GF.Services

	local generationOk, generationErr = pcall(function()
		-- 1. geography: the landform itself, seed-deterministic
		local GeographyService = require(Services.GeographyService)
		local spec = GeographyService.specFromSeed(intent.seed)
		GeographyService.generate(spec)
		print(string.format("MissionServer: geography ready %.1fs (foundation=%s)", os.clock() - t0, tostring(Workspace:GetAttribute("GF_GeoFoundation"))))

		-- 2. vegetation composition over the generated foundation. Vegetation failure is serious
		-- visually, but it is not a reason to strand a squad: terrain itself is already standable.
		local vegT = os.clock()
		local VegetationService = require(Services.VegetationService)
		local vegOk, vegErr = pcall(function()
			VegetationService.plant({ seed = intent.seed * 3 + 11, extent = 4900 })
		end)
		if vegOk then
			print(string.format("MissionServer: vegetation ready %.1fs", os.clock() - vegT))
		else
			Workspace:SetAttribute("GF_VegetationError", tostring(vegErr))
			warn("MissionServer: vegetation failed; continuing with terrain-only world: " .. tostring(vegErr))
		end

		-- 3. mission anchors from terrain analysis — the fixed legacy positions (0,-120)/(0,120)
		-- can land inside mountains on generated geography. TerrainAnalysis already scores
		-- placement-feasible valley-floor sites with a distributed picker enforcing separation;
		-- LZ and objective take the two best separated lowland sites, extraction the third.
		-- GeographyService analyzes on a spawned task; vegetation normally covers that latency, but
		-- the anchor write is important enough to allow a small bounded catch-up window.
		local TerrainAnalysis = require(Services.TerrainAnalysis)
		local analysisWaitStart = os.clock()
		while GeographyService.analysis == nil and os.clock() - analysisWaitStart < 4 do
			task.wait(0.25)
		end
		local analysis = GeographyService.analysis
		if analysis and #analysis.valleyFloor >= 3 then
			local picked = TerrainAnalysis.distributed(analysis.valleyFloor, 3, 300)
			if #picked >= 3 then
				Workspace:SetAttribute("GF_AnchorLZ", Vector3.new(picked[1].x, 0, picked[1].z))
				Workspace:SetAttribute("GF_AnchorObjective", Vector3.new(picked[2].x, 0, picked[2].z))
				Workspace:SetAttribute("GF_AnchorExtraction", Vector3.new(picked[3].x, 0, picked[3].z))
				print(string.format("MissionServer: anchors LZ=%.0f,%.0f obj=%.0f,%.0f ext=%.0f,%.0f",
					picked[1].x, picked[1].z, picked[2].x, picked[2].z, picked[3].x, picked[3].z))
			end
		else
			warn("MissionServer: insufficient valley-floor sites — arrival falls back to legacy LZ coordinates")
		end
	end)

	if not generationOk then
		Workspace:SetAttribute("GF_ArrivalGenerationError", tostring(generationErr))
		warn("MissionServer: world generation failed; arrival timeout fail-safe remains armed: " .. tostring(generationErr))
		return
	end

	-- 4. terrain is now authoritative. Publish both the legacy mission keys and the operation keys
	-- the client loading experience reads, then open the arrival gate. GF_TerrainReady must remain
	-- false until this line: it is the only signal the loading screen trusts.
	Workspace:SetAttribute("GF_MissionTemplate", intent.template)
	Workspace:SetAttribute("GF_Difficulty", intent.difficulty)
	Workspace:SetAttribute("GF_OperationTemplate", intent.template)
	Workspace:SetAttribute("GF_OperationDifficulty", intent.difficulty)
	bootGenerationComplete = true
	Workspace:SetAttribute("GF_TerrainReady", true)
	-- If a legacy writer had already set the attribute true, there is no changed-edge for the
	-- listener even though this boot just made the ready signal authoritative. Poll recovery directly.
	task.spawn(recoverTimeoutArrivalsOnLateTerrain)

	Workspace:SetAttribute("GF_MissionWorldReady", true)
	print(string.format("MissionServer: world ready total=%.1fs template=%s difficulty=%s",
		os.clock() - t0, intent.template, intent.difficulty))
end

-- Requiring this module means "this server is the mission-place bootstrap". Start the hold at
-- module evaluation, before any contract-wait/generation orchestration can yield: teleport arrivals
-- must never get even one unsecured character spawn while the bootstrap is still reading intent.
-- boot() calls the same function again and hits its idempotence guard.
MissionServerInit.startArrivalControl()

return MissionServerInit
