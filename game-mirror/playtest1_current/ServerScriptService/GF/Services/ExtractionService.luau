--!strict
-- Extraction: squad consensus → validated LZ → inbound gunship → committed boarding → settlement → return.
--
-- Authority rules implemented here:
--   * strict-majority vote of active eligible participants (1/1, 2/2, 2/3, 3/4), 20s window;
--   * AFK (~90s), disconnected and empty slots never block a vote or departure;
--   * boarding is a server volume commitment. Once committed there is no exit/re-enter exploit;
--   * one eligible living boarder secures the full shared salvage pool for every qualifying participant;
--   * settlement is completed and durably captured BEFORE any return teleport is attempted.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")

local State = require(script.Parent.State)
local ArtService = require(script.Parent.ArtService)
local EnemyService = require(script.Parent.EnemyService)
local ObjectiveService = require(script.Parent.ObjectiveService)
local RewardsService = require(script.Parent.RewardsService)
local SquadService = require(script.Parent.SquadService)
local EncounterDirector = require(script.Parent.EncounterDirector)
local ReturnTeleportService = require(script.Parent.ReturnTeleportService)
local DebriefService = require(script.Parent.DebriefService)

-- StationService requires this module even in the lobby place. Starting DebriefService here is the
-- owned boot path that lets the same binary receive return-debrief packages there without editing the
-- shared boot scripts; start() itself is idempotent and harmless in the mission place.
DebriefService.start()

local ExtractionService = {}

local COUNTDOWN = math.clamp(tonumber((require(ReplicatedStorage.GF.Shared.Constants).Mission or {}).ExtractionCountdown) or 75, 60, 90)
local BOARD_RANGE = 14
local CABIN_HALF = 8
local CABIN_HEIGHT = 14
local HARD_DEADLINE = 240
local FIRST_BOARD_GRACE = 30
local EMERGENCY_FIRST_BOARD_GRACE = 20
local EMERGENCY_GRACE = 150 -- soft-limit protocol allows roughly 2–3 minutes to board
local DEPART_TIME = 6
local SQUAD_WARNING = 2
local VOTE_WINDOW = 20
local VOTE_COOLDOWN = 30
local AFK_TIMEOUT = 90
local RETURN_DELAY_SUCCESS = 4.0
local RETURN_DELAY_FAILURE = 1.25

local called = false
local landed = false
local remaining = 0
local dropship: Model? = nil
local dropshipBasePivot: CFrame? = nil
local dropshipStartOffset = Vector3.new(0, 132, -136)
local lzPosition: Vector3? = nil
local countdownEndsAt: number? = nil
local countdownDuration = COUNTDOWN
local completing = false
local finishing = false
local settled = false
local emergency = false
local landedAt: number? = nil
local firstBoardAt: number? = nil
local departing = false
local squadPending = false
local autoCommandCalled = false
local graceExtended = false

local aboard: { [Player]: boolean } = {}
local extracted: { [Player]: boolean } = {}
local aboardOffsets: { [Player]: CFrame } = {}
local departureSnapshot: any = nil
local beacon: BasePart? = nil

local roster: { [number]: boolean } = {}
local rosterLocked = false
local lastActivity: { [number]: number } = {}
local lastPositions: { [number]: Vector3 } = {}

local vote: any = nil
local voteCooldownUntil = 0
local started = false

local function finite(value: any, fallback: number?): number
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return fallback or 0
	end
	return n
end

local function copyTable(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in pairs(value) do
		out[key] = copyTable(child)
	end
	return out
end

local function remote(name: string)
	local gf = ReplicatedStorage:FindFirstChild("GF")
	local remotes = gf and gf:FindFirstChild("Remotes")
	return remotes and remotes:FindFirstChild(name)
end

local function missionEvent(text: string, kind: string?)
	local ev = remote("MissionEvent")
	if ev and ev:IsA("RemoteEvent") then
		ev:FireAllClients({ text = text, kind = kind or "info" })
	end
end

local function isMissionPlace(): boolean
	if Workspace:GetAttribute("GF_AmMissionPlace") == true then
		return true
	end
	local lobbyId = Workspace:GetAttribute("GF_LobbyPlaceId")
	return type(lobbyId) == "number" and lobbyId > 0 and lobbyId ~= game.PlaceId
end

local function stationZone(player: Player): string
	local ok, zone = pcall(function()
		return require(script.Parent.StationService).zoneOf(player)
	end)
	return ok and zone or "Station"
end

local function touchActivity(player: Player)
	lastActivity[player.UserId] = os.clock()
end

local function registerParticipant(player: Player)
	if player:GetAttribute("GF_MissionParticipant") ~= true then
		return false
	end
	local userId = player.UserId
	if rosterLocked and roster[userId] ~= true then
		return false
	end
	roster[userId] = true
	if lastActivity[userId] == nil then
		lastActivity[userId] = os.clock()
	end
	return true
end

local function registerParticipants()
	for _, player in ipairs(Players:GetPlayers()) do
		registerParticipant(player)
	end
end

-- Qualifying participants are connected players whose mission arrival was confirmed before extraction
-- started. In the mission place there is no StationService zone table, so the participant attribute is
-- authoritative there. In the shared place the station zone check still excludes lobby sitters.
local function participating(player: Player): boolean
	if not registerParticipant(player) then
		return false
	end
	if isMissionPlace() then
		return true
	end
	return stationZone(player) == "Mission"
end

local function qualifyingParticipants(): { Player }
	registerParticipants()
	local out = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if participating(player) then
			table.insert(out, player)
		end
	end
	return out
end

local function afkTimeout(): number
	return tonumber(Workspace:GetAttribute("GF_AFKTimeoutOverride")) or AFK_TIMEOUT
end

local function playerActive(player: Player): boolean
	if not player.Parent then
		return false
	end
	local last = lastActivity[player.UserId]
	if type(last) ~= "number" then
		lastActivity[player.UserId] = os.clock()
		return true
	end
	return os.clock() - last < afkTimeout()
end

-- Deterministic validation hook (also useful for future moderation tooling): normal gameplay never
-- needs it because movement/combat/input remotes refresh the same timestamp.
function ExtractionService.noteActivity(player: Player, atTime: number?)
	lastActivity[player.UserId] = tonumber(atTime) or os.clock()
end

local function isDowned(player: Player): boolean
	local state = State.get(player)
	return state ~= nil and state.downed == true
end

local function inCabin(player: Player): boolean
	if not landed or not dropship then
		return false
	end
	local zone = dropship:FindFirstChild("BoardingZone") :: BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not zone or not root then
		return false
	end
	local rel = zone.CFrame:PointToObjectSpace(root.Position)
	return math.abs(rel.X) <= CABIN_HALF and math.abs(rel.Z) <= CABIN_HALF and rel.Y >= -2 and rel.Y <= CABIN_HEIGHT
end

local function aboardCount(): number
	local count = 0
	for player in pairs(extracted) do
		if player.Parent then
			count += 1
		end
	end
	return count
end

local function publish()
	Workspace:SetAttribute("GF_ExtractionCalled", called == true)
	Workspace:SetAttribute("ExtractionCalled", called == true) -- compatibility mirror used by join gates
	Workspace:SetAttribute("GF_ExtractionLanded", landed == true)
	Workspace:SetAttribute("GF_ExtractionRemaining", math.max(0, math.floor(remaining)))
	Workspace:SetAttribute("GF_ExtractionEmergency", emergency == true)
	Workspace:SetAttribute("GF_ExtractionCommittedCount", aboardCount())
	local r = remote("ExtractionState")
	if r and r:IsA("RemoteEvent") then
		r:FireAllClients({
			called = called,
			landed = landed,
			remaining = math.max(0, math.floor(remaining)),
			position = lzPosition,
			emergency = emergency,
			aboard = aboardCount(),
			firstBoardAt = firstBoardAt,
		})
	end
end

-- Full-squad truth for the bonus/departure decision. Aboard players count even though they can no
-- longer move; uncommitted inactive players are explicitly non-blocking. Downed players count until
-- they have been inactive long enough to satisfy the AFK rule.
local function fullSquadState(): (boolean, number, number)
	local committed = 0
	local activeEligible = 0
	for _, player in ipairs(qualifyingParticipants()) do
		if extracted[player] then
			committed += 1
			activeEligible += 1
		elseif playerActive(player) then
			activeEligible += 1
		end
	end
	return activeEligible > 0 and committed == activeEligible, committed, activeEligible
end

local function lockRoster()
	registerParticipants()
	rosterLocked = true
end

-- ---------------------------------------------------------------------------
-- Landing-zone validation and signaling
-- ---------------------------------------------------------------------------

local function groundAt(position: Vector3): Vector3?
	local exclusions = {}
	if dropship then
		table.insert(exclusions, dropship)
	end
	if beacon then
		table.insert(exclusions, beacon)
	end

	-- Prefer voxel terrain so a tree canopy, outpost roof or wreck cannot masquerade as a landing pad.
	local terrainParams = RaycastParams.new()
	terrainParams.FilterType = Enum.RaycastFilterType.Include
	terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
	terrainParams.IgnoreWater = true
	local terrainHit = Workspace:Raycast(position + Vector3.new(0, 600, 0), Vector3.new(0, -1800, 0), terrainParams)
	local hit = terrainHit
	if not hit then
		-- Shared-place/test maps may use ordinary baseplate parts rather than Terrain voxels.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = exclusions
		hit = Workspace:Raycast(position + Vector3.new(0, 600, 0), Vector3.new(0, -1800, 0), params)
	end
	if not hit or hit.Normal.Y < 0.55 then
		return nil
	end
	-- Clearance probe: the gunship is large. If a solid non-terrain object occupies the approach
	-- cylinder immediately above the touchdown point, this candidate is not a valid LZ.
	local clearanceParams = RaycastParams.new()
	clearanceParams.FilterType = Enum.RaycastFilterType.Exclude
	clearanceParams.FilterDescendantsInstances = exclusions
	local obstruction = Workspace:Raycast(hit.Position + Vector3.new(0, 3, 0), Vector3.new(0, 42, 0), clearanceParams)
	if obstruction and obstruction.Instance ~= Workspace.Terrain then
		return nil
	end
	return hit.Position
end

local function validateLZ(candidate: Vector3): Vector3?
	local direct = groundAt(candidate)
	if direct then
		return direct
	end
	for _, radius in ipairs({ 10, 20, 34, 52 }) do
		for step = 0, 11 do
			local angle = math.rad(step * 30)
			local probe = candidate + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			local ground = groundAt(probe)
			if ground then
				return ground
			end
		end
	end
	return nil
end

local function squadCentroid(fallback: Vector3?): Vector3
	local sum = Vector3.zero
	local count = 0
	for _, player in ipairs(qualifyingParticipants()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			sum += root.Position
			count += 1
		end
	end
	if count > 0 then
		return sum / count
	end
	return fallback or Vector3.zero
end

local function clearBeacon()
	if beacon and beacon.Parent then
		beacon:Destroy()
	end
	beacon = nil
end

local function markLZ(position: Vector3)
	Workspace:SetAttribute("GF_ExtractionLZ", position)
	Workspace:SetAttribute("GF_ExtractionLZValidated", true)
	Workspace:SetAttribute("GF_ExtractionLZMarkedAt", os.clock())
	clearBeacon()
	local p = Instance.new("Part")
	p.Name = "GF_ExtractionBeacon"
	p.Size = Vector3.new(2.2, 42, 2.2)
	p.CFrame = CFrame.new(position + Vector3.new(0, 21, 0))
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 0.45
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(96, 220, 255)
	p.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(96, 220, 255)
	light.Range = 55
	light.Brightness = 2.2
	light.Parent = p
	beacon = p
end

-- Server chooses the published/prevalidated LZ when it is still valid. Otherwise it scans authored
-- ExtractionZones by distance to the squad centroid, then falls back to safe ground near the squad.
local function resolveLZ(player: Player?): Vector3?
	local fallbackPosition: Vector3? = nil
	if player and player.Character then
		local root = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			fallbackPosition = root.Position
		end
	end
	local centroid = squadCentroid(fallbackPosition)
	local published = Workspace:GetAttribute("GF_ExtractionLZ") or Workspace:GetAttribute("GF_LZ")
	if typeof(published) == "Vector3" then
		local valid = validateLZ(published)
		if valid then
			return valid
		end
	end
	local zones = Workspace:FindFirstChild("ExtractionZones")
	local best: Vector3? = nil
	local bestDistance = math.huge
	if zones then
		for _, zone in ipairs(zones:GetChildren()) do
			if zone:IsA("BasePart") and zone:GetAttribute("Invalid") ~= true then
				local valid = validateLZ(zone.Position)
				if valid then
					local distance = (valid - centroid).Magnitude
					if distance < bestDistance then
						bestDistance = distance
						best = valid
					end
				end
			end
		end
	end
	if best then
		return best
	end
	-- Last-resort softlock protection: use the squad centroid even when geometry interrogation cannot
	-- prove a slope. The ship/boarding remains server functional and the failure is visible in telemetry
	-- rather than trapping a completed operation without any extraction path.
	local validCentroid = validateLZ(centroid)
	if validCentroid then
		return validCentroid
	end
	Workspace:SetAttribute("GF_ExtractionLZFallbackUnvalidated", true)
	return centroid
end

-- Correct replacement for the legacy reveal helper: nearest valid zone is measured from the squad,
-- not from world origin. Kept public because OperationService/test harnesses call the old API.
function ExtractionService.revealNearestZone()
	local zones = Workspace:FindFirstChild("ExtractionZones")
	if not zones then
		return
	end
	local centroid = squadCentroid(nil)
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, zone in ipairs(zones:GetChildren()) do
		if zone:IsA("BasePart") and zone:GetAttribute("Invalid") ~= true and validateLZ(zone.Position) then
			local distance = (zone.Position - centroid).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = zone
			end
		end
	end
	if best then
		Workspace:SetAttribute("GF_RevealedZone", best.Name)
		Workspace:SetAttribute("GF_ZoneRevealedAt", os.clock())
		markLZ((validateLZ(best.Position) or best.Position))
	end
end

-- ---------------------------------------------------------------------------
-- Gunship construction and motion
-- ---------------------------------------------------------------------------

local function buildDropship(position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "ExtractionDropship"

	local function part(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Position = position + offset
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	local ship = nil
	if ArtService.exists("Kit_Human_Gunship") then
		ship = ArtService.placeKit("Kit_Human_Gunship", position + Vector3.new(0, 6, 0), { parent = model, collide = false })
	end
	if not ship then
		ship = ArtService.place("Dropship", position + Vector3.new(0, 11, 0), { scale = 1.7, sink = 0 })
	end
	if ship then
		ship.Name = "Hull"
		ship.Parent = model
		for _, descendant in ipairs(ship:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.CanCollide = false
				descendant.Anchored = true
			end
		end
	else
		part("Body", Vector3.new(16, 6, 26), Vector3.new(0, 9, 0), Color3.fromRGB(74, 82, 92), Enum.Material.Metal)
		part("Wing", Vector3.new(26, 1.2, 10), Vector3.new(0, 9, 2), Color3.fromRGB(64, 72, 82), Enum.Material.Metal)
		part("Nose", Vector3.new(10, 4, 7), Vector3.new(0, 8.5, -16), Color3.fromRGB(205, 209, 204), Enum.Material.Metal)
	end

	local ramp = part("Ramp", Vector3.new(8, 0.8, 12), Vector3.new(0, 4.5, 13), Color3.fromRGB(58, 64, 72), Enum.Material.DiamondPlate)
	for index = 1, 4 do
		local angle = math.rad(index * 90 + 45)
		part("GearStrut" .. index, Vector3.new(0.7, 4.5, 0.7), Vector3.new(math.cos(angle) * 6, -2.5, math.sin(angle) * 6), Color3.fromRGB(50, 55, 62), Enum.Material.Metal)
	end
	local dust = Instance.new("Part")
	dust.Name = "LandingDust"
	dust.Shape = Enum.PartType.Ball
	dust.Size = Vector3.new(4, 2, 4)
	dust.Transparency = 0.65
	dust.Color = Color3.fromRGB(150, 138, 120)
	dust.Material = Enum.Material.SmoothPlastic
	dust.Anchored = true
	dust.CanCollide = false
	dust.Parent = model
	task.delay(0.4, function()
		if dust.Parent then
			TweenService:Create(dust, TweenInfo.new(1.4), { Size = Vector3.new(34, 5, 34), Transparency = 1 }):Play()
		end
	end)
	local rampCenter = position + Vector3.new(0, 4.5, 13)
	local hingeWorld = rampCenter + Vector3.new(0, 0, -6)
	ramp.CFrame = CFrame.new(hingeWorld) * CFrame.Angles(math.rad(-75), 0, 0) * CFrame.new(0, 0, 6)
	model:SetAttribute("GFRampDeployed", false)
	local engine = part("Engine", Vector3.new(3, 3, 3), Vector3.new(0, 9, -14), Color3.fromRGB(120, 210, 255), Enum.Material.Neon)
	engine.CanCollide = false
	local thruster = Instance.new("PointLight")
	thruster.Color = Color3.fromRGB(120, 210, 255)
	thruster.Brightness = 2.4
	thruster.Range = 34
	thruster.Parent = engine
	local flood = part("LandingFloodlight", Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 4, -10), Color3.fromRGB(170, 235, 255), Enum.Material.Neon)
	flood.CanCollide = false
	local floodLight = Instance.new("SpotLight")
	floodLight.Color = Color3.fromRGB(170, 235, 255)
	floodLight.Brightness = 3
	floodLight.Range = 70
	floodLight.Angle = 62
	floodLight.Face = Enum.NormalId.Bottom
	floodLight.Parent = flood

	local board = part("BoardingZone", Vector3.new(12, 1, 12), Vector3.new(0, 0.8, 11), Color3.fromRGB(120, 210, 255), Enum.Material.ForceField)
	board.Transparency = 0.72
	board.CanCollide = false
	board:SetAttribute("GFInteract", "Extract")
	board:SetAttribute("InteractPrompt", "BOARD TRANSPORT")
	model.PrimaryPart = board
	local parent = Workspace:FindFirstChild("ActiveActors") or Workspace
	model.Parent = parent
	return model
end

local function updateAboardCharacters(targetPivot: CFrame)
	for player in pairs(extracted) do
		if player.Parent then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local offset = aboardOffsets[player]
			if root and offset then
				root.CFrame = targetPivot * offset
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end

function ExtractionService.playDeparture(outcome: string?): boolean
	if departing or not dropship then
		return false
	end
	departing = true
	local ship = dropship
	local result = outcome or "success"
	Workspace:SetAttribute("GF_DeparturePlayed", result)
	Workspace:SetAttribute("GF_DepartureAt", os.clock())
	local base = ship:GetPivot()
	local engine = ship:FindFirstChild("Engine")
	local distance = 0
	task.spawn(function()
		local elapsed = 0
		while elapsed < DEPART_TIME and ship.Parent do
			local dt = 0.1
			task.wait(dt)
			elapsed += dt
			local t = elapsed / DEPART_TIME
			local lift = 6 + 90 * t * t
			local away = 46 * t * t * t
			distance = lift
			local target = base * CFrame.new(0, lift, -away) * CFrame.Angles(math.rad(-12 * t), 0, math.rad(18 * t))
			ship:PivotTo(target)
			updateAboardCharacters(target)
			if engine and engine:IsA("BasePart") then
				engine.Transparency = math.max(0, 0.15 - t * 0.15)
			end
			local camPos = (target * CFrame.new(0, 11, 42)).Position
			Workspace:SetAttribute("GF_CamPos", camPos)
			Workspace:SetAttribute("GF_CamLook", target.Position + Vector3.new(0, -3, 0))
		end
		Workspace:SetAttribute("GF_DepartureHeight", math.floor(distance))
		Workspace:SetAttribute("GF_DepartureFinishedAt", os.clock())
		if ship.Parent then
			ship:Destroy()
		end
		departing = false
	end)
	return true
end

local function beginCountdown(position: Vector3, seconds: number)
	called = true
	landed = false
	landedAt = nil
	firstBoardAt = nil
	graceExtended = false
	remaining = seconds
	countdownDuration = math.max(1, seconds)
	countdownEndsAt = os.clock() + countdownDuration
	lzPosition = position
	local mission = State.getMission()
	if mission then
		mission.extractionCalled = true
	end
	if dropship then
		dropship:Destroy()
	end
	dropship = buildDropship(position)
	dropshipBasePivot = dropship:GetPivot()
	dropship:PivotTo(dropshipBasePivot + dropshipStartOffset)
	markLZ(position)
	publish()
	missionEvent(string.format("Transport inbound. ETA %ds. Hold the marked landing zone.", math.floor(seconds)), "extraction")
	task.spawn(function()
		while called and countdownEndsAt and os.clock() < countdownEndsAt do
			local left = math.max(0, countdownEndsAt - os.clock())
			remaining = math.ceil(left)
			-- Final approach occupies the last fifth of the ETA. Before that the ship is a distant
			-- inbound silhouette; during it the craft visibly descends and translates onto the pad.
			if dropship and dropship.Parent and dropshipBasePivot then
				local elapsedFraction = 1 - (left / countdownDuration)
				local approach = math.clamp((elapsedFraction - 0.78) / 0.22, 0, 1)
				local smooth = approach * approach * (3 - 2 * approach)
				dropship:PivotTo(dropshipBasePivot + dropshipStartOffset * (1 - smooth))
			end
			publish()
			task.wait(0.25)
		end
		if called then
			remaining = 0
			landed = true
			landedAt = os.clock()
			if dropship and dropship.Parent and dropshipBasePivot then
				dropship:PivotTo(dropshipBasePivot)
				local ramp = dropship:FindFirstChild("Ramp")
				if ramp and ramp:IsA("BasePart") then
					local rc = position + Vector3.new(0, 4.5, 13)
					TweenService:Create(ramp, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(rc) }):Play()
				end
				dropship:SetAttribute("GFRampDeployed", true)
			end
			Workspace:SetAttribute("GF_HardDeadline", os.clock() + HARD_DEADLINE)
			Workspace:SetAttribute("GF_NoBoardingCountdown", true)
			missionEvent("Transport on final approach. Board through the rear ramp.", "extraction")
			publish()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Vote consensus
-- ---------------------------------------------------------------------------

local function voterPool(): { Player }
	local out = {}
	for _, player in ipairs(qualifyingParticipants()) do
		if playerActive(player) and player.Character and not isDowned(player) then
			table.insert(out, player)
		end
	end
	return out
end

local function publishVote(result: string?)
	local r = remote("VoteStateChanged")
	if not r or not r:IsA("RemoteEvent") then
		return
	end
	if not vote then
		r:FireAllClients({ active = false, result = result, cooldown = math.max(0, math.floor(voteCooldownUntil - os.clock())) })
		return
	end
	local voterNames = {}
	local pool = voterPool()
	local inPool = {}
	for _, player in ipairs(pool) do
		inPool[player.UserId] = true
	end
	local yesCount, noCount = 0, 0
	for userId in pairs(vote.yes) do
		if inPool[userId] then
			yesCount += 1
			local player = Players:GetPlayerByUserId(userId)
			table.insert(voterNames, player and player.Name or tostring(userId))
		end
	end
	for userId in pairs(vote.no) do
		if inPool[userId] then
			noCount += 1
		end
	end
	local needed = math.max(1, math.floor(#pool / 2) + 1)
	r:FireAllClients({
		active = true,
		starter = vote.starter,
		yes = yesCount,
		no = noCount,
		needed = needed,
		eligible = #pool,
		voters = voterNames,
		remaining = math.max(0, math.floor(vote.endsAt - os.clock())),
	})
end

local function voteCountsInPool(pool: { Player }): (number, number, number)
	local inPool = {}
	for _, player in ipairs(pool) do
		inPool[player.UserId] = true
	end
	local yes, no = 0, 0
	for userId in pairs(vote and vote.yes or {}) do
		if inPool[userId] then
			yes += 1
		end
	end
	for userId in pairs(vote and vote.no or {}) do
		if inPool[userId] then
			no += 1
		end
	end
	return yes, no, math.max(1, math.floor(#pool / 2) + 1)
end

local function failVote(result: string)
	vote = nil
	voteCooldownUntil = os.clock() + VOTE_COOLDOWN
	Workspace:SetAttribute("GF_ExtractionVote", result)
	publishVote(result)
end

local function evaluateVote()
	if not vote then
		return
	end
	local pool = voterPool()
	if #pool == 0 then
		failVote("expired:no active voters")
		return
	end
	local yes, no, needed = voteCountsInPool(pool)
	if yes >= needed then
		local caller = Players:GetPlayerByUserId(vote.starterUserId)
		if not caller or not caller.Parent then
			caller = pool[1]
		end
		vote = nil
		Workspace:SetAttribute("GF_ExtractionVote", "passed")
		publishVote("passed")
		missionEvent("Extraction request approved. Landing zone assigned.", "vote")
		ExtractionService.call(caller)
	elseif no >= needed or yes + math.max(0, #pool - yes - no) < needed then
		-- A no vote does not need to be a majority to end the request when it makes the required
		-- strict yes-majority mathematically impossible (the duo 1�1 deadlock is the important case).
		failVote("rejected")
	elseif os.clock() >= vote.endsAt then
		failVote("expired")
	else
		publishVote()
	end
end

function ExtractionService.requestVote(player: Player): boolean
	touchActivity(player)
	if called or completing or finishing then
		return false
	end
	if vote then
		-- A teammate may cancel their own pending request only before anyone else has committed.
		if vote.starterUserId == player.UserId then
			local yes, no = voteCountsInPool(voterPool())
			if yes <= 1 and no == 0 then
				vote = nil
				Workspace:SetAttribute("GF_ExtractionVote", "cancelled")
				publishVote("cancelled")
				return true
			end
		end
		return false
	end
	if os.clock() < voteCooldownUntil then
		Workspace:SetAttribute("GF_ExtractionVote", "cooldown")
		publishVote("cooldown")
		return false
	end
	if Workspace:GetAttribute("GF_InMission") ~= true and not isMissionPlace() then
		return false
	end
	if not ObjectiveService.isComplete() then
		Workspace:SetAttribute("GF_ExtractionVote", "objective open")
		return false
	end
	local pool = voterPool()
	if #pool == 0 then
		return false
	end
	local requesterEligible = false
	for _, voter in ipairs(pool) do
		if voter == player then
			requesterEligible = true
			break
		end
	end
	if not requesterEligible then
		Workspace:SetAttribute("GF_ExtractionVote", "requester ineligible")
		return false
	end
	if #pool == 1 then
		Workspace:SetAttribute("GF_ExtractionVote", "solo immediate")
		return ExtractionService.call(player)
	end
	vote = {
		starter = player.Name,
		starterUserId = player.UserId,
		yes = { [player.UserId] = true },
		no = {},
		endsAt = os.clock() + VOTE_WINDOW,
	}
	Workspace:SetAttribute("GF_ExtractionVote", string.format("%s:1/%d", player.Name, math.floor(#pool / 2) + 1))
	publishVote()
	missionEvent(string.format("%s requested extraction — approve or decline.", tostring(player.DisplayName)), "vote")
	return true
end

function ExtractionService.castVote(player: Player, agrees: boolean)
	touchActivity(player)
	if not vote then
		return
	end
	-- Only active eligible squad members may influence consensus. Input from the player refreshes
	-- their AFK timestamp, but downed soldiers, station spectators and post-call joiners stay excluded.
	local allowed = false
	for _, voter in ipairs(voterPool()) do
		if voter == player then
			allowed = true
			break
		end
	end
	if not allowed then
		return
	end
	if agrees then
		vote.no[player.UserId] = nil
		vote.yes[player.UserId] = true
	else
		vote.yes[player.UserId] = nil
		vote.no[player.UserId] = true
	end
	evaluateVote()
end

function ExtractionService.voteState()
	if not vote then
		return nil
	end
	-- Public compatibility shape: the pre-refactor service exposed yes as an array of Player objects.
	-- Internally votes are user-id keyed so disconnects cannot corrupt them; expose the old inspection
	-- shape without weakening that authority.
	local pool = voterPool()
	local inPool = {}
	for _, player in ipairs(pool) do
		inPool[player.UserId] = true
	end
	local yesPlayers, noPlayers = {}, {}
	for userId in pairs(vote.yes) do
		local player = Players:GetPlayerByUserId(userId)
		if player and inPool[userId] then
			table.insert(yesPlayers, player)
		end
	end
	for userId in pairs(vote.no) do
		local player = Players:GetPlayerByUserId(userId)
		if player and inPool[userId] then
			table.insert(noPlayers, player)
		end
	end
	return {
		starter = vote.starter,
		starterUserId = vote.starterUserId,
		yes = yesPlayers,
		no = noPlayers,
		needed = math.max(1, math.floor(#pool / 2) + 1),
		endsAt = vote.endsAt,
	}
end

-- ---------------------------------------------------------------------------
-- Standard and emergency calls
-- ---------------------------------------------------------------------------

function ExtractionService.call(player: Player): boolean
	if called or completing or finishing or settled then
		return false
	end
	if not ObjectiveService.isComplete() then
		Workspace:SetAttribute("GF_ExtractionRejected", "objective incomplete")
		return false
	end
	lockRoster()
	local position = resolveLZ(player)
	if not position then
		Workspace:SetAttribute("GF_ExtractionRejected", "no valid LZ")
		missionEvent("No validated landing zone is available. Command is re-tasking the transport.", "fail")
		return false
	end
	local seconds = tonumber(Workspace:GetAttribute("GF_ExtractionCountdownOverride")) or COUNTDOWN
	beginCountdown(position, seconds)
	return true
end

function ExtractionService.emergency(): boolean
	if called or completing or finishing or settled then
		return false
	end
	if Workspace:GetAttribute("GF_InMission") ~= true and not isMissionPlace() then
		return false
	end
	lockRoster()
	local position = resolveLZ(nil)
	if not position then
		local fallback = squadCentroid(nil)
		position = validateLZ(fallback)
	end
	if not position then
		return false
	end
	emergency = true
	Workspace:SetAttribute("GF_EmergencyExtraction", true)
	Workspace:SetAttribute("GF_Emergency", true)
	Workspace:SetAttribute("GF_EmergencyAt", os.clock())
	missionEvent("Support window closed. Emergency evacuation authorized — board the transport.", "fail")
	beginCountdown(position, tonumber(Workspace:GetAttribute("GF_EmergencyArrivalOverride")) or 10)
	return true
end

function ExtractionService.isEmergency(): boolean
	return emergency
end

function ExtractionService.isCalled(): boolean
	return called
end

function ExtractionService.isLanded(): boolean
	return landed
end

-- ---------------------------------------------------------------------------
-- Boarding and departure
-- ---------------------------------------------------------------------------

function ExtractionService.isAboard(player: Player): boolean
	return extracted[player] == true or aboard[player] == true
end

function ExtractionService.commitFreeze(player: Player)
	player:SetAttribute("GF_ExtractionCommitted", true)
	player:SetAttribute("GF_Untargetable", true)
	Workspace:SetAttribute("GF_LedgerFrozen_" .. player.UserId, os.clock())
	local actors = Workspace:FindFirstChild("ActiveActors")
	if actors then
		for _, enemy in ipairs(actors:GetChildren()) do
			if enemy:IsA("Model") and enemy:GetAttribute("GFEnemy") and enemy:GetAttribute("TargetPlayer") == player.Name then
				enemy:SetAttribute("TargetPlayer", nil)
			end
		end
	end
end

local function securePlayerInShip(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and dropship then
		aboardOffsets[player] = dropship:GetPivot():ToObjectSpace(root.CFrame)
		root.Anchored = true
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

local function enforceAboardCharacters()
	if not dropship or not dropship.Parent then
		return
	end
	local pivot = dropship:GetPivot()
	for player in pairs(extracted) do
		if player.Parent then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local offset = aboardOffsets[player]
			if root and offset then
				-- A reset/recharactered boarded player is still committed. They are restored to the
				-- secure interior rather than being allowed to exit and re-enter for advantage.
				root.CFrame = pivot * offset
				root.Anchored = true
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end

local function evaluateDeparture()
	if completing or finishing or settled or not landed or squadPending then
		return
	end
	local all, count = fullSquadState()
	if all and count > 0 then
		squadPending = true
		Workspace:SetAttribute("GF_SquadDeparture", "pending")
		missionEvent(string.format("All active squad members secure. Departing in %ds.", SQUAD_WARNING), "extraction")
		task.delay(SQUAD_WARNING, function()
			squadPending = false
			if completing or finishing or settled or not landed then
				return
			end
			local stillAll, stillCount = fullSquadState()
			if stillAll and stillCount > 0 then
				ExtractionService.commitDeparture("full_squad")
			end
		end)
	end
end

function ExtractionService.board(player: Player): boolean
	touchActivity(player)
	if completing or finishing or settled or not landed or not dropship then
		return false
	end
	if extracted[player] then
		return true
	end
	if not participating(player) or isDowned(player) then
		Workspace:SetAttribute("GF_ExtractRejected", player.Name .. ":not eligible")
		return false
	end
	if not inCabin(player) then
		Workspace:SetAttribute("GF_ExtractRejected", player.Name .. ":not aboard")
		return false
	end
	aboard[player] = true
	extracted[player] = true
	player:SetAttribute("GF_Aboard", true)
	securePlayerInShip(player)
	ExtractionService.commitFreeze(player)
	if not firstBoardAt then
		firstBoardAt = os.clock()
		missionEvent(string.format("%s is aboard. Transport departs in %ds unless the squad completes boarding.", tostring(player.DisplayName), emergency and EMERGENCY_FIRST_BOARD_GRACE or FIRST_BOARD_GRACE), "extraction")
	end
	pcall(function()
		local Ledger = require(script.Parent.RewardLedgerService)
		Ledger.markParticipant(player.UserId)
		Ledger.lockPlayer(player.UserId, "extracted")
	end)
	local all, count, total = fullSquadState()
	Workspace:SetAttribute("GF_ExtractSplit", string.format("%d/%d aboard", count, total))
	Workspace:SetAttribute("GF_BoardedCount", count)
	publish()
	evaluateDeparture()
	return true
end

function ExtractionService.commitDeparture(reason: string?): boolean
	if completing or finishing or settled then
		return false
	end
	local all, count, total = fullSquadState()
	if count <= 0 then
		return false
	end
	local userIds = {}
	for player in pairs(extracted) do
		table.insert(userIds, player.UserId)
	end
	departureSnapshot = {
		count = count,
		userIds = userIds,
		fullSquad = all,
		eligibleCount = total,
		reason = reason or "departure",
		at = os.clock(),
	}
	completing = true
	Workspace:SetAttribute("GF_SquadDeparture", "committed")
	missionEvent(if all then "Transport departing with the full squad." else "Transport departing. Salvage is secured for qualifying personnel.", "extraction")
	ExtractionService.playDeparture("success")
	ExtractionService.finish(true, all, reason or "departure")
	return true
end

local function missDeparture(reason: string)
	if completing or finishing or settled then
		return
	end
	completing = true
	departureSnapshot = {
		count = 0,
		userIds = {},
		fullSquad = false,
		eligibleCount = select(3, fullSquadState()),
		reason = reason,
		at = os.clock(),
	}
	Workspace:SetAttribute("GF_SquadDeparture", "missed")
	missionEvent("Transport has departed. Command cannot recover unsecured salvage.", "fail")
	ExtractionService.playDeparture("missed")
	ExtractionService.finish(false, false, reason)
end

-- ---------------------------------------------------------------------------
-- Settlement. This is the critical economic ordering: every ledger, mastery, reward,
-- cache and debrief commit completes before the return transport is even attempted.
-- ---------------------------------------------------------------------------

local function parseWarPoints(): number
	local pointsText = Workspace:GetAttribute("GF_WarPoints")
	if type(pointsText) == "string" then
		local points = tonumber(string.match(pointsText, "%+([%d%.]+)="))
		if points then
			return math.max(0, math.floor(points + 0.5))
		end
	end
	local direct = tonumber(Workspace:GetAttribute("GF_WarContribution"))
	if direct and direct == direct and math.abs(direct) ~= math.huge then
		return math.max(0, math.floor(direct + 0.5))
	end
	return 0
end

local function buildWarContext(participantCount: number): any
	-- GF_WarPoints is a front-level rolling display string and can survive into the next shared-place
	-- mission. It is evidence for THIS debrief only when the current primary actually committed.
	local committed = Workspace:GetAttribute("GF_WarCommitted") == true
	local points = committed and parseWarPoints() or 0
	return {
		points = points,
		operationId = Workspace:GetAttribute("GF_OperationId") or "",
		regionId = Workspace:GetAttribute("GF_RegionId") or "",
		status = Workspace:GetAttribute("GF_WarStatus") or Workspace:GetAttribute("GF_WarFront") or "contested",
		sector = Workspace:GetAttribute("GF_WarSector") or Workspace:GetAttribute("GF_WarFront") or "",
		applied = committed or points > 0,
		participants = math.max(1, participantCount),
	}
end

local function releaseAboardCharacters()
	for player in pairs(extracted) do
		if player.Parent then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.Anchored = false
			end
			player:SetAttribute("GF_Aboard", false)
		end
	end
end

local function cleanupMissionActors()
	pcall(function()
		EncounterDirector.reset()
		EnemyService.clearAll()
	end)
end

local function fallbackPosition(): Vector3
	if lzPosition then
		return lzPosition + Vector3.new(0, 5, 0)
	end
	local lz = Workspace:GetAttribute("GF_ExtractionLZ") or Workspace:GetAttribute("GF_LZ")
	if typeof(lz) == "Vector3" then
		return lz + Vector3.new(0, 5, 0)
	end
	return squadCentroid(nil) + Vector3.new(0, 5, 0)
end

local lastReturnPackage: string? = nil
local lastResultsByUser: { [number]: any } = {}

local function recoverFailedReturn(players: { Player }, reason: string)
	Workspace:SetAttribute("GF_ReturnDelayed", true)
	Workspace:SetAttribute("GF_ReturnDelayReason", reason)
	local fallback = fallbackPosition()
	for index, player in ipairs(players) do
		if player.Parent then
			releaseAboardCharacters()
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.Anchored = false
				player.Character:PivotTo(CFrame.new(fallback + Vector3.new((index - 1) * 3, 0, 0)))
			end
			player:SetAttribute("GF_ReturnDelayed", true)
			local row = lastResultsByUser[player.UserId]
			if row then
				DebriefService.publishLocal(player, row)
			end
		end
	end
	missionEvent("TRANSFER DELAYED — results are secured. Use RETURN TO STATION to retry.", "fail")
end

local function scheduleSplitReturn(delaySeconds: number)
	task.delay(delaySeconds, function()
		local home = {}
		for _, player in ipairs(Players:GetPlayers()) do
			table.insert(home, player)
		end
		if #home == 0 then
			return
		end
		local ok = false
		local lastError = "unknown"
		for attempt = 1, 2 do
			ok = ReturnTeleportService.sendHome(home, lastReturnPackage)
			if ok then
				break
			end
			lastError = "teleport attempt " .. attempt .. " failed"
			task.wait(1.5)
		end
		if not ok then
			-- A single vanished/ineligible player can poison a group teleport. Results are per-user rows,
			-- so individual fallback retains squad-independent delivery without any economic risk.
			local stranded = {}
			for _, player in ipairs(home) do
				if player.Parent then
					local individualOk = ReturnTeleportService.sendHome({ player }, lastReturnPackage)
					if not individualOk then
						table.insert(stranded, player)
					end
				end
			end
			if #stranded > 0 then
				recoverFailedReturn(stranded, lastError)
			end
		end
	end)
end

local function returnSharedPlacePlayers()
	releaseAboardCharacters()
	pcall(function()
		local station = require(script.Parent.StationService)
		for _, player in ipairs(Players:GetPlayers()) do
			if station.zoneOf(player) == "Mission" then
				station.returnToStation(player)
			end
		end
	end)
end

function ExtractionService.finish(requestedSuccess: boolean, requestedSquadBonus: boolean?, reason: string?): boolean
	if finishing or settled then
		return false
	end
	finishing = true
	registerParticipants()

	local mission = State.getMission()
	local payoutDifficulty = (mission and mission.difficulty) or tostring(Workspace:GetAttribute("GF_MissionDifficulty") or "Normal")
	local payoutObjective = ObjectiveService.isComplete()
	local payoutTemplate = (mission and mission.objectiveTemplate) or tostring(Workspace:GetAttribute("GF_OperationTemplate") or "SABOTAGE_RELAY")
	local snapshot = departureSnapshot
	local committedCount = snapshot and math.floor(finite(snapshot.count)) or aboardCount()
	-- Internal gameplay derives success exclusively from a committed eligible boarder. A bare
	-- finish(true) with no extraction flow at all remains a legacy validation-harness shortcut, but a
	-- true value can never convert a real no-boarding departure into salvage success.
	local legacyDirectSuccess = requestedSuccess == true and not called and not landed and departureSnapshot == nil
	local extractionSuccess = committedCount > 0 or legacyDirectSuccess
	local fullSquad = extractionSuccess and ((snapshot and snapshot.fullSquad == true) or (not snapshot and requestedSquadBonus == true))
	local participants = qualifyingParticipants()
	-- Validation harnesses sometimes drive ObjectiveService directly before a formal deploy writes the
	-- live participation attribute. In that case the immutable primary/kill ledger is the only safe
	-- roster evidence. This fallback is additive only when the live roster is empty; it never re-adds a
	-- permanently eliminated player to an otherwise living roster.
	if #participants == 0 then
		pcall(function()
			local Ledger = require(script.Parent.RewardLedgerService)
			local ids = {}
			for _, userId in ipairs(Ledger.participantUserIds()) do
				ids[userId] = true
			end
			for _, player in ipairs(Players:GetPlayers()) do
				if ids[player.UserId] == true then
					table.insert(participants, player)
				end
			end
		end)
	end
	-- Failed legacy probes with no reward events at all still expect a zero-value closeout rather than
	-- silence. Positive objective income remains blocked when no participant evidence exists.
	if #participants == 0 and not payoutObjective then
		for _, player in ipairs(Players:GetPlayers()) do
			table.insert(participants, player)
		end
	end
	local participantCount = #participants

	local carriedSalvage = SquadService.snapshot()
	local carriedTotal = SquadService.total()
	Workspace:SetAttribute("GF_CarriedAtFinish", carriedTotal)
	Workspace:SetAttribute("GF_CarriedLost", not extractionSuccess)

	local priorEndReason = Workspace:GetAttribute("GF_MissionEndReason")
	local endReason
	if priorEndReason == "squad_eliminated" then
		endReason = priorEndReason
	elseif not payoutObjective then
		endReason = emergency and "emergency_objective_incomplete" or (reason == "squad_eliminated" and reason or "mission_failed")
	elseif extractionSuccess and fullSquad then
		endReason = "extraction_success"
	elseif extractionSuccess then
		endReason = "partial_extraction"
	else
		endReason = "extraction_failed"
	end
	Workspace:SetAttribute("GF_MissionEndReason", tostring(endReason))
	Workspace:SetAttribute("GF_ExtractionState", if extractionSuccess then "complete" else "failed")
	print("[GF] extraction finish success=" .. tostring(extractionSuccess) .. " objective=" .. tostring(payoutObjective))

	local beforeByPlayer = {}
	for _, player in ipairs(participants) do
		beforeByPlayer[player] = DebriefService.captureBefore(player)
	end

	-- A completed primary already committed campaign points at ObjectiveService.complete. Only an
	-- operation whose primary never completed is recorded as a loss here; never double-credit.
	if not payoutObjective then
		pcall(function()
			require(script.Parent.GalacticWarService).recordMission(payoutTemplate, false)
		end)
	end

	-- Shadow reconciliation metrics retained from the previous implementation.
	pcall(function()
		local Ledger = require(script.Parent.RewardLedgerService)
		local snap = Ledger.snapshot()
		local salvageEvents, killEvents, cacheEvents, blueprintEvents = 0, 0, 0, 0
		local killXpByPlayer = {}
		for _, event in ipairs(snap.events) do
			if event.eventType == "salvage_pickup" then
				salvageEvents += 1
			elseif event.eventType == "cache_entitlement" then
				cacheEvents += 1
			elseif event.eventType == "blueprint_entitlement" then
				blueprintEvents += 1
			elseif string.sub(tostring(event.eventType), 1, 5) == "kill_" then
				killEvents += 1
				if event.userId then
					killXpByPlayer[event.userId] = (killXpByPlayer[event.userId] or 0) + (tonumber(event.mastery) or 0)
				end
			end
		end
		Workspace:SetAttribute("GF_ReconcileSalvage", string.format("events=%d", salvageEvents))
		Workspace:SetAttribute("GF_ReconcileKills", string.format("events=%d caches=%d blueprints=%d", killEvents, cacheEvents, blueprintEvents))
		local parts = {}
		for userId, xp in pairs(killXpByPlayer) do
			table.insert(parts, userId .. "=" .. string.format("%.0f", xp))
		end
		Workspace:SetAttribute("GF_ReconcileKillXp", table.concat(parts, ","))
	end)

	-- Weapon mastery settles once when the primary completed, even if extraction later failed.
	pcall(function()
		local settledMastery = 0
		for _, player in ipairs(participants) do
			local playerState = State.get(player)
			if playerState and playerState.pendingMastery then
				local playerTotal = 0
				for _, amount in pairs(playerState.pendingMastery) do
					playerTotal += finite(amount)
				end
				if payoutObjective then
					for weaponId, amount in pairs(playerState.pendingMastery) do
						require(script.Parent.ProfileService).addMastery(player, weaponId, finite(amount))
						settledMastery += finite(amount)
					end
					RewardsService.setKillXp(player, playerTotal)
				end
				playerState.pendingMastery = {}
			end
		end
		Workspace:SetAttribute("GF_MasterySettled", settledMastery)
	end)

	local missionId = tostring(Workspace:GetAttribute("GF_MissionId") or "")
	pcall(function()
		local Ledger = require(script.Parent.RewardLedgerService)
		if missionId == "" then
			missionId = tostring(Ledger.missionId() or "mission")
		end
		Ledger.appendEvent(if extractionSuccess then "extraction_success" else "extraction_failed", payoutDifficulty, "extraction:" .. tostring(payoutTemplate))
	end)

	local extractedUserIds = {}
	local participantStatuses = {}
	pcall(function()
		local Ledger = require(script.Parent.RewardLedgerService)
		for _, player in ipairs(participants) do
			Ledger.markParticipant(player.UserId)
			local status
			if extractionSuccess and extracted[player] then
				status = "extracted"
			elseif extractionSuccess then
				status = "mission_complete_not_aboard"
			else
				status = "mission_failed"
			end
			Ledger.lockPlayer(player.UserId, status)
			participantStatuses[player.UserId] = status
			if extracted[player] then
				extractedUserIds[player.UserId] = true
			end
		end
	end)

	local warContribution = buildWarContext(participantCount)
	local context = {
		missionId = missionId ~= "" and missionId or "mission",
		template = payoutTemplate,
		difficulty = payoutDifficulty,
		seed = tonumber(Workspace:GetAttribute("GF_MissionSeed")) or (mission and mission.seed) or 0,
		extractionSuccess = extractionSuccess,
		objectiveComplete = payoutObjective,
		salvageSecured = extractionSuccess,
		carriedLost = not extractionSuccess,
		emergency = emergency,
		endReason = tostring(endReason),
		fullSquad = fullSquad,
		extractedUserIds = extractedUserIds,
		participantStatuses = participantStatuses,
		aboardCount = committedCount,
		eligibleCount = (snapshot and math.floor(finite(snapshot.eligibleCount))) or participantCount,
		participantCount = participantCount,
		carriedSalvage = copyTable(carriedSalvage),
		warContribution = warContribution,
		completedAt = os.time(),
	}

	-- RewardsService.grant is intentionally invoked per participant here (rather than grantAll) so the
	-- exact returned settlement rows can be captured for the return debrief without editing RewardsService.
	local results = {}
	local payoutsByPlayer = {}
	lastResultsByUser = {}
	for _, player in ipairs(participants) do
		local ok, payout = pcall(function()
			return RewardsService.grant(player, payoutDifficulty, extractionSuccess, payoutObjective, fullSquad)
		end)
		if not ok then
			warn("[GF] settlement error for " .. player.Name .. ": " .. tostring(payout))
			payout = { credits = 0, xp = 0, salvage = { scrap = 0, energyCells = 0, militaryTechnology = 0 }, settlementError = true }
		end
		payoutsByPlayer[player] = payout
	end

	-- Guaranteed mission cache only when the primary succeeded and at least one eligible boarder
	-- secured extraction. Failure affects unsecured salvage; it never consumes the cache entitlement.
	if extractionSuccess and payoutObjective then
		local okGrant, grantErr = pcall(function()
			local Cache = require(script.Parent.CacheService)
			local ProfileService = require(script.Parent.ProfileService)
			local tier = Cache.tierForDifficulty(payoutDifficulty)
			-- Grant exactly to the settlement roster computed above. CacheService.grantMission uses a
			-- broad ledger union for legacy compatibility; here the live qualifying roster is authoritative,
			-- so a permanently eliminated player who already left cannot receive a posthumous cache.
			for _, player in ipairs(participants) do
				local profile = ProfileService.get(player)
				local granted = Cache.grantToInventory(player, tier, "mission")
				local firstMission = profile ~= nil and profile.firstMissionBonusClaimed ~= true
				if granted and firstMission and profile then
					profile.firstMissionBonusClaimed = true
					profile.credits = (profile.credits or 0) + 200
					Workspace:SetAttribute("GF_FirstMissionCredits", player.Name)
					local instances = profile.cacheInstances
					local inst = instances and instances[#instances]
					if inst and inst.source == "mission" then
						inst.guaranteedRare = true
					end
					ProfileService.markDirty(player)
					Workspace:SetAttribute("GF_FirstMissionRare", player.Name)
				end
				if granted then
					ProfileService.markDirty(player)
					local persisted = ProfileService.saveWithRetry(player)
					Workspace:SetAttribute("GF_MissionCachePersisted", player.Name .. ":" .. tostring(persisted))
				end
			end
		end)
		Workspace:SetAttribute("GF_MissionCacheResult", okGrant and "granted" or ("error: " .. tostring(grantErr)))
	else
		Workspace:SetAttribute("GF_MissionCacheResult", string.format("skipped success=%s objective=%s", tostring(extractionSuccess), tostring(payoutObjective)))
	end

	-- Build debrief rows only after cache/first-mission writes as well, so totals shown in the report
	-- match the full committed settlement rather than only the RewardsService portion.
	for _, player in ipairs(participants) do
		local payout = payoutsByPlayer[player] or { credits = 0, xp = 0, salvage = { scrap = 0, energyCells = 0, militaryTechnology = 0 } }
		local rowOk, row = pcall(function()
			return DebriefService.buildPlayerResult(player, payout, beforeByPlayer[player], context)
		end)
		if not rowOk then
			warn("[GF] debrief row error for " .. player.Name .. ": " .. tostring(row))
			row = {
				userId = player.UserId,
				missionId = context.missionId,
				success = extractionSuccess,
				objectiveComplete = payoutObjective,
				credits = finite(payout.credits),
				xp = finite(payout.xp),
				salvage = copyTable(payout.salvage),
				rank = 1,
				rankUps = 0,
				endReason = context.endReason,
				debriefError = true,
			}
		end
		table.insert(results, row)
		lastResultsByUser[player.UserId] = row
	end

	-- Publish/cache the rich after-action rows before transport. In the lobby these rows are restored
	-- from teleport data; in shared-place/failure fallback they are available immediately.
	for _, player in ipairs(participants) do
		local row = lastResultsByUser[player.UserId]
		if row then
			DebriefService.cache(player, row)
		end
	end
	local packageOk, package = pcall(function()
		return DebriefService.makeReturnPackage(context, results)
	end)
	if packageOk then
		lastReturnPackage = DebriefService.encodePackage(package)
	else
		warn("[GF] debrief package error: " .. tostring(package))
		lastReturnPackage = nil
	end
	Workspace:SetAttribute("GF_DebriefPackaged", lastReturnPackage ~= nil)
	Workspace:SetAttribute("GF_DebriefRows", #results)

	-- Mission world cleanup happens only after every economic fact has been captured. A departure in
	-- flight owns and destroys its own craft; any other closeout must remove the ship rather than
	-- leaving an interactable extraction pad behind after settlement.
	if dropship and not departing then
		dropship:Destroy()
		dropship = nil
		dropshipBasePivot = nil
	end
	cleanupMissionActors()
	Workspace:SetAttribute("GF_InMission", false)
	called = false
	landed = false
	landedAt = nil
	firstBoardAt = nil
	emergency = false
	remaining = 0
	countdownEndsAt = nil
	vote = nil
	autoCommandCalled = false
	Workspace:SetAttribute("GF_EmergencyExtraction", false)
	Workspace:SetAttribute("GF_Emergency", false)
	Workspace:SetAttribute("ExtractionCalled", false)
	clearBeacon()
	publish()

	-- Clear per-operation runtime facts only after payout. Late-join suppression is per-operation.
	for _, player in ipairs(Players:GetPlayers()) do
		local playerState = State.get(player)
		if playerState and playerState.joinedLate then
			playerState.joinedLate = false
		end
		player:SetAttribute("GF_MissionParticipant", nil)
	end
	pcall(function()
		SquadService.reset()
	end)
	squadPending = false
	settled = true
	finishing = false

	-- Return transport is deliberately last. A teleport exception can now only strand the player in a
	-- safe post-settlement state; it can never skip rewards or double-grant them.
	if ReturnTeleportService.enabled() then
		for _, player in ipairs(participants) do
			local row = lastResultsByUser[player.UserId]
			if row then
				DebriefService.cache(player, row)
			end
		end
		scheduleSplitReturn(if extractionSuccess then RETURN_DELAY_SUCCESS else RETURN_DELAY_FAILURE)
	else
		for _, player in ipairs(participants) do
			local row = lastResultsByUser[player.UserId]
			if row then
				DebriefService.publishLocal(player, row)
			end
		end
		returnSharedPlacePlayers()
	end
	return true
end

function ExtractionService.reset()
	called = false
	landed = false
	landedAt = nil
	firstBoardAt = nil
	graceExtended = false
	emergency = false
	remaining = 0
	completing = false
	finishing = false
	settled = false
	departing = false
	squadPending = false
	autoCommandCalled = false
	countdownEndsAt = nil
	departureSnapshot = nil
	vote = nil
	voteCooldownUntil = 0
	rosterLocked = false
	table.clear(roster)
	table.clear(aboard)
	table.clear(extracted)
	table.clear(aboardOffsets)
	table.clear(lastActivity)
	table.clear(lastPositions)
	table.clear(lastResultsByUser)
	lastReturnPackage = nil
	Workspace:SetAttribute("GF_EmergencyExtraction", false)
	Workspace:SetAttribute("GF_Emergency", false)
	Workspace:SetAttribute("ExtractionCalled", false)
	Workspace:SetAttribute("GF_ReturnDelayed", false)
	if dropship then
		dropship:Destroy()
		dropship = nil
	end
	dropshipBasePivot = nil
	clearBeacon()
	publish()
end

function ExtractionService.armHardDeadline()
	Workspace:SetAttribute("GF_HardDeadline", os.clock() + HARD_DEADLINE)
	Workspace:SetAttribute("GF_NoBoardingCountdown", true)
end

-- ---------------------------------------------------------------------------
-- Watchdogs, activity tracking, remote wiring
-- ---------------------------------------------------------------------------

local function trackMovementActivity()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("GF_MissionParticipant") == true then
			registerParticipant(player)
		end
		if extracted[player] then
			continue
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local userId = player.UserId
			local previous = lastPositions[userId]
			if previous and (root.Position - previous).Magnitude > 1.5 then
				touchActivity(player)
			elseif not previous then
				lastActivity[userId] = lastActivity[userId] or os.clock()
			end
			lastPositions[userId] = root.Position
		end
	end
end

local function boardingGrace(): number
	if emergency then
		return tonumber(Workspace:GetAttribute("GF_EmergencyBoardGraceOverride")) or EMERGENCY_FIRST_BOARD_GRACE
	end
	return tonumber(Workspace:GetAttribute("GF_FirstBoardGraceOverride")) or FIRST_BOARD_GRACE
end

local function watchdog()
	while true do
		task.wait(0.5)
		trackMovementActivity()
		evaluateVote()
		evaluateDeparture()
		local mission = State.getMission()
		local inMission = Workspace:GetAttribute("GF_InMission") == true or isMissionPlace()
		if mission and inMission and not finishing and not settled then
			local override = tonumber(Workspace:GetAttribute("GF_SoftDeadlineOverride"))
			local deadline = override or tonumber(mission.softDeadline)
			if override then
				mission.softDeadline = override
			end
			if deadline then
				-- Legacy mission bootstrap used os.time while deploy reset uses os.clock. Normalize by
				-- magnitude so either clock family yields the same remaining support window.
				local now = deadline > 1000000 and os.time() or os.clock()
				local timeLeft = deadline - now
				-- Command override near support withdrawal prevents an AFK/griefer veto from softlocking
				-- a completed operation. Emergency itself remains the final incomplete-objective override.
				if not autoCommandCalled and timeLeft <= 45 and timeLeft > 0 and ObjectiveService.isComplete() and not called and not completing then
					autoCommandCalled = true
					vote = nil
					local pool = voterPool()
					local caller = pool[1] or qualifyingParticipants()[1]
					if caller then
						missionEvent("Command has authorized extraction. Transport inbound.", "extraction")
						ExtractionService.call(caller)
					end
				end
				if now >= deadline and not called and not completing then
					vote = nil
					ExtractionService.emergency()
				end
			end
			-- Missing-craft self-heal: a destroyed/reparented model must not softlock a voted extraction.
			if called and not completing and (not dropship or not dropship.Parent) and lzPosition then
				dropship = buildDropship(lzPosition)
				dropshipBasePivot = dropship:GetPivot()
				if not landed then
					dropship:PivotTo(dropshipBasePivot + dropshipStartOffset * 0.25)
				end
				Workspace:SetAttribute("GF_ExtractionCraftRecovered", os.clock())
			end
			if landed and landedAt and not completing then
				local sinceLanding = os.clock() - landedAt
				local sinceFirstBoard = firstBoardAt and (os.clock() - firstBoardAt) or nil
				if emergency and sinceLanding > (tonumber(Workspace:GetAttribute("GF_EmergencyGraceOverride")) or EMERGENCY_GRACE) then
					if aboardCount() > 0 then
						ExtractionService.commitDeparture("emergency_deadline")
					else
						missDeparture("emergency_expired")
					end
				elseif sinceFirstBoard and sinceFirstBoard > boardingGrace() then
					-- A teammate already in the approach zone gets one short extension rather than being
					-- punished by a first boarder who committed early. Emergency extraction stays harsher.
					local approaching = false
					if not emergency and not graceExtended and lzPosition then
						for _, player in ipairs(qualifyingParticipants()) do
							if not extracted[player] and playerActive(player) then
								local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
								if root and (root.Position - lzPosition).Magnitude <= 80 then
									approaching = true
									break
								end
							end
						end
					end
					if approaching then
						graceExtended = true
						firstBoardAt = os.clock() - boardingGrace() + 12
						missionEvent("Teammate in the approach zone � final boarding extension.", "extraction")
					else
						ExtractionService.commitDeparture("boarding_grace")
					end
				elseif sinceLanding > HARD_DEADLINE then
					if aboardCount() > 0 then
						ExtractionService.commitDeparture("hard_deadline")
					else
						missDeparture("boarding_deadline")
					end
				end
			end
		end
	end
end

local function hookActivityRemote(name: string)
	local instance = remote(name)
	if instance and instance:IsA("RemoteEvent") then
		instance.OnServerEvent:Connect(function(player)
			touchActivity(player)
		end)
	end
end

local function retryReturn(player: Player)
	if not isMissionPlace() or player:GetAttribute("GF_ReturnDelayed") ~= true then
		return
	end
	touchActivity(player)
	if not ReturnTeleportService.enabled() then
		return
	end
	Workspace:SetAttribute("GF_ReturnRetry", player.Name)
	local ok = ReturnTeleportService.sendHome({ player }, lastReturnPackage)
	if ok then
		player:SetAttribute("GF_ReturnDelayed", nil)
	else
		player:SetAttribute("GF_ReturnDelayed", true)
		missionEvent("Return transfer is still delayed. Results remain secured; retry shortly.", "fail")
	end
end

function ExtractionService.start()
	if started then
		return
	end
	started = true
	DebriefService.start()
	task.spawn(watchdog)

	-- Boarding poll: the volume is authoritative, but once committed a player remains committed.
	task.spawn(function()
		while true do
			task.wait(0.25)
			if landed and dropship and not completing and not finishing and not settled then
				enforceAboardCharacters()
				for _, player in ipairs(qualifyingParticipants()) do
					if not extracted[player] and not isDowned(player) and inCabin(player) then
						ExtractionService.board(player)
					end
				end
			end
			if dropship and dropship.Parent then
				local zone = dropship:FindFirstChild("BoardingZone")
				if zone and zone:IsA("BasePart") then
					local all, count, total = fullSquadState()
					zone:SetAttribute("InteractPrompt", if all then string.format("EXTRACT SQUAD (%d aboard, +25%% bonus)", count) else string.format("BOARD TRANSPORT (%d/%d active aboard; all aboard = +25%%)", count, total))
				end
			end
			Workspace:SetAttribute("GF_BoardedCount", aboardCount())
		end
	end)

	for _, name in ipairs({ "FireWeapon", "ReloadWeapon", "EquipWeapon", "UseAbility", "RequestDodge", "ThrowGrenade", "InteractRequest", "SprintChanged", "AimChanged", "CrouchChanged", "ReportState" }) do
		hookActivityRemote(name)
	end

	local request = remote("RequestExtractionVote")
	if request and request:IsA("RemoteEvent") then
		request.OnServerEvent:Connect(function(player)
			if not require(script.Parent.NetGuard).allow(player, "interact") then
				return
			end
			ExtractionService.requestVote(player)
		end)
	end
	local cast = remote("CastVote")
	if cast and cast:IsA("RemoteEvent") then
		cast.OnServerEvent:Connect(function(player, agrees)
			if not require(script.Parent.NetGuard).allow(player, "interact") then
				return
			end
			ExtractionService.castVote(player, agrees == true)
		end)
	end
	-- Legacy ExtractionRequest is a proposal, not a silent bypass around squad consensus.
	local callRemote = remote("ExtractionRequest")
	if callRemote and callRemote:IsA("RemoteEvent") then
		callRemote.OnServerEvent:Connect(function(player)
			if not require(script.Parent.NetGuard).allow(player, "interact") then
				return
			end
			ExtractionService.requestVote(player)
		end)
	end
	local interact = remote("InteractRequest")
	if interact and interact:IsA("RemoteEvent") then
		interact.OnServerEvent:Connect(function(player, target)
			if target == "Extract" then
				if not require(script.Parent.NetGuard).allow(player, "interact") then
					return
				end
				ExtractionService.board(player)
			end
		end)
	end
	local returnRemote = remote("RequestReturn")
	if returnRemote and returnRemote:IsA("RemoteEvent") then
		returnRemote.OnServerEvent:Connect(function(player)
			if require(script.Parent.NetGuard).allow(player, "interact") then
				retryReturn(player)
			end
		end)
	end
	pcall(function()
		TeleportService.TeleportInitFailed:Connect(function(player)
			-- TeleportAsync can report initial success and still fail asynchronously for one traveler.
			-- That failure is transport-only: mark the already-settled row delayed and let the same
			-- RETURN TO STATION retry path recover without any second settlement.
			if player.Parent and isMissionPlace() and settled then
				player:SetAttribute("GF_ReturnDelayed", true)
				Workspace:SetAttribute("GF_ReturnDelayed", true)
				local row = lastResultsByUser[player.UserId]
				if row then
					DebriefService.publishLocal(player, row)
				end
				missionEvent("TRANSFER DELAYED � results are secured. Use RETURN TO STATION to retry.", "fail")
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPositions[player.UserId] = nil
		-- Committed extraction rows deliberately survive until settlement: a disconnect after boarding
		-- must neither duplicate nor erase the resolution that was already locked.
		if vote then
			vote.yes[player.UserId] = nil
			vote.no[player.UserId] = nil
			evaluateVote()
		end
	end)
end

return ExtractionService
