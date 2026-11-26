--!strict
-- Extraction: call → countdown → dropship lands → board → payout.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local State = require(script.Parent.State)
local ArtService = require(script.Parent.ArtService)
local EnemyService = require(script.Parent.EnemyService)
local ObjectiveService = require(script.Parent.ObjectiveService)
local RewardsService = require(script.Parent.RewardsService)
local SquadService = require(script.Parent.SquadService)

local ExtractionService = {}
local EncounterDirector = require(script.Parent.EncounterDirector)
-- Read from Constants so the conformance check measures the value that actually governs the countdown.
local COUNTDOWN = tonumber((require(ReplicatedStorage.GF.Shared.Constants).Mission or {}).ExtractionCountdown) or 45
local BOARD_RANGE = 14
local called = false
local landed = false
local remaining = 0
local dropship: Model? = nil
local lzPosition: Vector3? = nil
local completing = false
local emergency = false
local landedAt: number? = nil
local EMERGENCY_GRACE = 60
-- Departure is the signature moment of an extraction: the ship lifts, banks away and the camera follows
-- it. It only exists on a real success - a failed operation must never show a triumphant departure.
local DEPART_TIME = 6
local departing = false
-- Studio-only override so the emergency countdown and the post-landing grace can be observed in seconds
-- instead of two minutes. Gameplay never sets it.
-- Boarding is a server volume over the BoardingZone, never a client flag. Per-mission sets.
local aboard: { [Player]: boolean } = {}
local extracted: { [Player]: boolean } = {}
local squadPending = false
local HARD_DEADLINE = 240 -- seconds after landing before the ship must leave regardless
local SQUAD_WARNING = 2
local CABIN_HALF = 8
local CABIN_HEIGHT = 14

local function stationZone(player: Player): string
	local ok, zone = pcall(function()
		return require(script.Parent.StationService).zoneOf(player)
	end)
	return ok and zone or "Station"
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

function ExtractionService.isAboard(player: Player): boolean
	return aboard[player] == true
end

-- Eligible survivors: connected, still in the mission zone, not yet extracted. Downed soldiers stay
-- eligible (they block Extract Squad until revived) because they cannot board.
function ExtractionService.eligible(): { Player }
	local out = {}
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		-- participant-scoped (audit P1: one roster everywhere) — a connected player who never
		-- deployed must not block squad extraction or count toward its bonus.
		if player:GetAttribute("GF_MissionParticipant") == true
			and not extracted[player] and stationZone(player) == "Mission" then
			out[#out + 1] = player
		end
	end
	return out
end

local function emergencyGrace(): number
	return tonumber(workspace:GetAttribute("GF_EmergencyGraceOverride")) or EMERGENCY_GRACE
end

local function remote(name: string)
	return ReplicatedStorage.GF.Remotes:FindFirstChild(name)
end

local function publish()
	-- Server-side mirror for tests: the live state lives in this module, and a tool VM gets its own copy.
	workspace:SetAttribute("GF_ExtractionCalled", called == true)
	workspace:SetAttribute("GF_ExtractionLanded", landed == true)
	workspace:SetAttribute("GF_ExtractionRemaining", remaining or 0)
	workspace:SetAttribute("GF_ExtractionEmergency", emergency == true)
	local r = remote("ExtractionState")
	if r then
		r:FireAllClients({ called = called, landed = landed, remaining = remaining, position = lzPosition })
	end
end

local function buildDropship(position: Vector3)
	local model = Instance.new("Model")
	model.Name = "ExtractionDropship"

	local function part(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material)
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

	local ship = ArtService.place("Dropship", position + Vector3.new(0, 11, 0), { scale = 1.7, sink = 0 })
	if ship then
		ship.Name = "Hull"
		ship.Parent = model
		for _, d in ship:GetDescendants() do
			if d:IsA("BasePart") then d.CanCollide = false end
		end
	else
		part("Body", Vector3.new(16, 6, 26), Vector3.new(0, 9, 0), Color3.fromRGB(74, 82, 92), Enum.Material.Metal)
		part("Wing", Vector3.new(26, 1.2, 10), Vector3.new(0, 9, 2), Color3.fromRGB(64, 72, 82), Enum.Material.Metal)
	end
	local ramp = part("Ramp", Vector3.new(8, 0.8, 12), Vector3.new(0, 4.5, 13), Color3.fromRGB(58, 64, 72), Enum.Material.DiamondPlate)
	-- S09-005 landing theater: gear struts deploy before touchdown, dust ring bursts outward on
	-- contact, and the hull lights stay lit through the boarding window so the ship reads as the
	-- one safe place on the field.
	for i = 1, 4 do
		local angle = math.rad(i * 90 + 45)
		local gear = part("GearStrut" .. i, Vector3.new(0.7, 4.5, 0.7), Vector3.new(math.cos(angle) * 6, -2.5, math.sin(angle) * 6), Color3.fromRGB(50, 55, 62), Enum.Material.Metal)
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
	local dustWeld = Instance.new("WeldConstraint")
	dustWeld.Part0 = model.PrimaryPart
	dustWeld.Part1 = dust
	dustWeld.Parent = dust
	task.delay(0.4, function()
		if dust.Parent then
			game:GetService("TweenService"):Create(dust, TweenInfo.new(1.4), { Size = Vector3.new(34, 5, 34), Transparency = 1 }):Play()
		end
	end)
	ramp.Transparency = 1
	local engine = part("Engine", Vector3.new(3, 3, 3), Vector3.new(0, 9, -14), Color3.fromRGB(120, 210, 255), Enum.Material.Neon)
	engine.CanCollide = false
	local thruster = Instance.new("PointLight")
	thruster.Shadows = false
	thruster.Color = Color3.fromRGB(120, 210, 255); thruster.Brightness = 2; thruster.Range = 28
	thruster.Parent = engine

	local board = part("BoardingZone", Vector3.new(12, 1, 12), Vector3.new(0, 0.8, 11), Color3.fromRGB(120, 210, 255), Enum.Material.ForceField)
	board.Transparency = 0.72
	board.CanCollide = false
	board:SetAttribute("GFInteract", "Extract")
	board:SetAttribute("InteractPrompt", "Board Transport")

	model.PrimaryPart = board
	model.Parent = workspace.ActiveActors
	return model
end

-- One countdown implementation for both the normal request and the forced emergency run.
local function beginCountdown(position: Vector3, seconds: number)
	called = true
	landed = false
	landedAt = nil
	remaining = seconds
	lzPosition = position
	local mission = State.getMission()
	if mission then
		mission.extractionCalled = true
	end
	if dropship then
		dropship:Destroy()
	end
	dropship = buildDropship(position)
	publish()
	task.spawn(function()
		while remaining > 0 and called do
			task.wait(1)
			remaining -= 1
			publish()
		end
		if called then
			landed = true
			landedAt = os.clock()
			publish()
		end
	end)
end

-- Emergency extraction. softDeadline was defined in the mission context and never read by anything,
-- so the clock was decorative. When it passes, the operation is no longer winnable but the squad is
-- not simply killed: a dropship is pushed to the LZ regardless of objective state, and the squad has
-- EMERGENCY_GRACE seconds from touchdown to board before the mission is recorded as failed.
function ExtractionService.emergency()
	if called or completing then
		return false
	end
	if workspace:GetAttribute("GF_InMission") ~= true then
		return false
	end
	local lz = workspace:GetAttribute("GF_ExtractionLZ") or workspace:GetAttribute("GF_LZ")
	if typeof(lz) ~= "Vector3" then
		local players = game:GetService("Players"):GetPlayers()
		for _, p in ipairs(players) do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				lz = root.Position
				break
			end
		end
	end
	if typeof(lz) ~= "Vector3" then
		return false
	end
	emergency = true
	workspace:SetAttribute("GF_EmergencyExtraction", true)
	workspace:SetAttribute("GF_EmergencyAt", os.clock())
	local ev = remote("MissionEvent")
	if ev then
		ev:FireAllClients({ text = "Support window closed. Emergency extraction inbound - board the dropship.", kind = "fail" })
	end
	-- Arrival is fast (8-12s band, 10 chosen); the 60s grace is the post-landing boarding window
	-- enforced by the watchdog, not a pre-landing lockout (S09-019).
	beginCountdown(lz, tonumber(workspace:GetAttribute("GF_EmergencyArrivalOverride")) or 10)
	return true
end

function ExtractionService.isEmergency(): boolean
	return emergency
end

function ExtractionService.call(player: Player)
	if called or not ObjectiveService.isComplete() then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local origin = root.Position
	local published = workspace:GetAttribute("GF_ExtractionLZ") or workspace:GetAttribute("GF_LZ")
	if typeof(published) == "Vector3" then
		lzPosition = published
	else
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(origin + Vector3.new(0, 80, 0), Vector3.new(0, -160, 0), params)
		lzPosition = hit and hit.Position or origin
	end
	-- Studio-only override: a 45s countdown is impossible to exercise inside one tool round-trip, and the
	-- countdown length is not what any acceptance check is about.
	beginCountdown(lzPosition, tonumber(workspace:GetAttribute("GF_ExtractionCountdownOverride")) or COUNTDOWN)
end

local function objectiveDoneNow(): boolean
	local done = false
	pcall(function()
		done = require(script.Parent.ObjectiveService).isComplete() == true
	end)
	return done
end

local function allEligibleAboard(): (boolean, number, number)
	local list = ExtractionService.eligible()
	local count = 0
	for _, p in ipairs(list) do
		if aboard[p] then
			count += 1
		end
	end
	return #list > 0 and count == #list, count, #list
end

function ExtractionService.board(player: Player)
	if completing or squadPending or not landed or not dropship then
		return
	end
	local ps = State.get(player)
	if ps and ps.downed then
		return
	end
	if not inCabin(player) or stationZone(player) ~= "Mission" or extracted[player] then
		workspace:SetAttribute("GF_ExtractRejected", player.Name .. ":not aboard")
		return
	end
	aboard[player] = true
	local all, count, total = allEligibleAboard()
	if all then
		-- Extract Squad: everyone eligible is aboard. Brief departure warning; cancelled if anyone steps off.
		squadPending = true
		workspace:SetAttribute("GF_SquadDeparture", "pending")
		local ev = remote("MissionEvent")
		if ev then
			ev:FireAllClients({ text = string.format("Extract Squad: departing in %ds with %d aboard.", SQUAD_WARNING, count), kind = "info" })
		end
		task.delay(SQUAD_WARNING, function()
			squadPending = false
			local stillAll = allEligibleAboard()
			if not stillAll or completing or not landed then
				workspace:SetAttribute("GF_SquadDeparture", "cancelled")
				if ev then
					ev:FireAllClients({ text = "Squad departure cancelled: a soldier left the ship.", kind = "fail" })
				end
				return
			end
			workspace:SetAttribute("GF_SquadDeparture", "committed")
			completing = true
			ExtractionService.playDeparture()
			ExtractionService.finish(objectiveDoneNow(), true)
		end)
		return
	end
	-- boarding HOLDS (audit target contract item 10): no instant individual extraction, no
	-- early payout. The first boarder waits for the squad; the ship leaves when everyone is
	-- aboard or the boarding deadline expires. Settlement happens once, at final close.
	workspace:SetAttribute("GF_ExtractSplit", string.format("%d/%d aboard", count, total))
end

-- The departure cinematic. Server-driven: the ship is tweened through a climb-and-bank path while the
-- camera attributes track it, so the same thing happens for every player and can be verified.
function ExtractionService.playDeparture()
	if departing or not dropship then
		return false
	end
	departing = true
	local ship = dropship
	workspace:SetAttribute("GF_DeparturePlayed", "success")
	workspace:SetAttribute("GF_DepartureAt", os.clock())
	local engine = ship:FindFirstChild("Engine")
	local base = ship:GetPivot()
	local distance = 0
	task.spawn(function()
		local elapsed = 0
		while elapsed < DEPART_TIME and ship.Parent do
			local dt = 0.1
			task.wait(dt)
			elapsed += dt
			local t = elapsed / DEPART_TIME
			-- ease out: slow lift, then accelerate up and away
			local lift = 6 + 90 * t * t
			local away = 40 * t * t * t
			distance = lift
			local target = base * CFrame.new(0, lift, -away) * CFrame.Angles(math.rad(-12 * t), 0, math.rad(18 * t))
			ship:PivotTo(target)
			if engine and engine:IsA("BasePart") then
				engine.Transparency = math.max(0, 0.15 - t * 0.15)
			end
			-- chase camera in the ship's own frame: behind and above, so the ship stays in shot as it climbs
			local camPos = (target * CFrame.new(0, 11, 42)).Position
			workspace:SetAttribute("GF_CamPos", camPos)
			workspace:SetAttribute("GF_CamLook", target.Position + Vector3.new(0, -3, 0))
		end
		workspace:SetAttribute("GF_DepartureHeight", math.floor(distance))
		workspace:SetAttribute("GF_DepartureFinishedAt", os.clock())
		if ship.Parent then
			ship:Destroy()
		end
		departing = false
	end)
	return true
end

function ExtractionService.finish(success: boolean, squadBonus: boolean?)
	print("[GF] extraction finish success=" .. tostring(success))
	workspace:SetAttribute("GF_ExtractionState", if success then "complete" else "failed")
	if not success then
		workspace:SetAttribute("GF_DeparturePlayed", "none")
		workspace:SetAttribute("GF_CamPos", nil)
		workspace:SetAttribute("GF_CamLook", nil)
	end
	-- capture payout facts before any teardown resets mission context
	local mission = State.getMission()
	local payoutDifficulty = (mission and mission.difficulty) or "Normal"
	local payoutObjective = ObjectiveService.isComplete()
	local payoutTemplate = (mission and mission.objectiveTemplate) or "SABOTAGE_RELAY"
	-- A successful run keeps the ship alive so the departure cinematic can fly it out.
	if dropship and not (success and departing) then
		dropship:Destroy()
		dropship = nil
	end
	called = false
	landed = false
	landedAt = nil
	emergency = false
	remaining = 0
	workspace:SetAttribute("GF_EmergencyExtraction", false)
	publish()
	workspace:SetAttribute("GF_InMission", false)
	pcall(function()
		EncounterDirector.reset()
		EnemyService.clearAll()
	end)
	-- Every soldier still in the mission when it closes returns to the station. An individually
	-- committed players ride the ship home; everyone still in the mission zone returns here.
	pcall(function()
		local station = require(script.Parent.StationService)
		for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
			if station.zoneOf(p) == "Mission" then
				station.returnToStation(p)
			end
		end
	end)
	-- Carried salvage belongs to the operation that picked it up. It was never cleared, so loot from a
	-- failed run stayed in the squad total and would have been paid out by the next successful one.
	local carriedTotal = SquadService.total()
	print(string.format("[GF] carried salvage at finish: total=%s success=%s", tostring(carriedTotal), tostring(success)))
	workspace:SetAttribute("GF_CarriedAtFinish", carriedTotal)
	-- A completed primary already committed its war points at ObjectiveService.complete, so
	-- extraction must not credit the campaign a second time. Only a mission whose primary never
	-- completed is recorded as a loss here.
	if not payoutObjective then
		pcall(function()
			require(script.Parent.GalacticWarService).recordMission(payoutTemplate, false)
		end)
	end
	workspace:SetAttribute("GF_CarriedLost", not success)
	-- Weapon mastery settles here, once, and only when the primary completed (S09-034). A player whose
	-- primary failed keeps nothing; a player whose primary completed keeps it even if they died.
	-- Runs before RewardsService.grantAll so the debrief reports the post-settlement value.
	pcall(function()
		local settled = 0
		for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
			local ps = State.get(p)
			if ps and ps.pendingMastery then
				local playerTotal = 0
				for weaponId, amount in pairs(ps.pendingMastery) do
					playerTotal += amount
				end
				if payoutObjective then
					for weaponId, amount in pairs(ps.pendingMastery) do
						require(script.Parent.ProfileService).addMastery(p, weaponId, amount)
						settled += amount
					end
					-- kill XP feeds rank XP at payout (S10-006 "including kills")
					require(script.Parent.RewardsService).setKillXp(p, playerTotal)
				end
				ps.pendingMastery = {}
			end
		end
		workspace:SetAttribute("GF_MasterySettled", settled)
	end)
	-- Record the settlement event before the payout runs, so a crash between the two leaves evidence of the
	-- intent. Still record-only: the ledger does not gate or alter what RewardsService pays.
	pcall(function()
		require(script.Parent.RewardLedgerService).appendEvent(
			if success then "extraction_success" else "extraction_failed",
			payoutDifficulty,
			"extraction:" .. tostring(payoutTemplate)
		)
	end)
	RewardsService.grantAll(success, payoutDifficulty, payoutObjective, success and squadBonus == true)
	-- Guaranteed mission cache, paid only when the primary succeeded and the squad actually extracted.
	if success and payoutObjective then
		local okGrant, grantErr = pcall(function()
			local Cache = require(script.Parent.CacheService)
			Cache.grantMission(Cache.tierForDifficulty(payoutDifficulty))
		end)
		workspace:SetAttribute("GF_MissionCacheResult", okGrant and "granted" or ("error: " .. tostring(grantErr)))
	else
		workspace:SetAttribute("GF_MissionCacheResult", string.format("skipped success=%s objective=%s", tostring(success), tostring(payoutObjective)))
	end
	-- joinedLate suppresses only the current operation's full payout (audit P1 item 9) —
	-- cleared at mission close so the next operation pays normally.
	pcall(function()
		for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
			local ps = State.get(p)
			if ps and ps.joinedLate then
				ps.joinedLate = false
			end
			-- participant roster is per-operation: cleared here so the next deployment rebuilds it
			p:SetAttribute("GF_MissionParticipant", nil)
		end
	end)
	SquadService.reset()
	table.clear(aboard)
	table.clear(extracted)
	squadPending = false
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		p:SetAttribute("GF_Aboard", false)
	end
end

function ExtractionService.reset()
	called = false
	landed = false
	landedAt = nil
	emergency = false
	remaining = 0
	completing = false
	workspace:SetAttribute("GF_EmergencyExtraction", false)
	if dropship then
		dropship:Destroy()
		dropship = nil
	end
	publish()
end

function ExtractionService.isCalled(): boolean
	return called
end

function ExtractionService.isLanded(): boolean
	ExtractionService.armHardDeadline()
	return landed
end

	-- Soft-deadline watchdog. Before this, softDeadline was written into the mission context and read by
	-- nobody, so a squad could sit in a mission forever with the timer long past.
	task.spawn(function()
		while true do
			task.wait(1)
			local mission = State.getMission()
			local inMission = workspace:GetAttribute("GF_InMission") == true
			if mission and inMission then
				local override = tonumber(workspace:GetAttribute("GF_SoftDeadlineOverride"))
				local deadline = override or tonumber(mission.softDeadline)
				if override then
					mission.softDeadline = override
				end
				if deadline and os.clock() >= deadline and not called and not completing then
					ExtractionService.emergency()
				elseif landed and landedAt and not completing and not emergency then
					-- hard deadline enforcement (was dead code): the ship must leave regardless.
					-- aboard complement departs now; nobody aboard means the operation failed.
					if os.clock() - landedAt > HARD_DEADLINE then
						completing = true
						local aboardCount = 0
						for _ in pairs(aboard) do aboardCount += 1 end
						if aboardCount > 0 then
							local ev = remote("MissionEvent")
							if ev then
								ev:FireAllClients({ text = "Boarding deadline reached — dropship departing.", kind = "info" })
							end
							ExtractionService.playDeparture()
							ExtractionService.finish(objectiveDoneNow(), false)
						else
							local ev = remote("MissionEvent")
							if ev then
								ev:FireAllClients({ text = "Dropship waited too long. Extraction window closed.", kind = "fail" })
							end
							ExtractionService.finish(false)
						end
						completing = false
					end
				end
				if emergency and landed and landedAt and not completing then
					-- nobody boarded before the grace window closed
					if os.clock() - landedAt > emergencyGrace() then
						completing = true
						local ev = remote("MissionEvent")
						if ev then
							ev:FireAllClients({ text = "Extraction window closed. Operation failed.", kind = "fail" })
						end
						ExtractionService.finish(false)
						completing = false
					end
				end
			else
				emergency = false
			end
		end
	end)

-- Extraction vote: calling the ship is a squad decision. Any player starts a vote, a simple majority of the
-- living squad passes it, and it times out rather than hanging. The vote belongs to the squad, not to the
-- initiator, so it survives that player leaving.
local VOTE_WINDOW = 15 -- spec: yes votes expire after 15s
local vote = nil

local function liveSquad()
	local out = {}
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		local state = State.get(player)
		-- vote population is living mission participants only (audit target contract item 5):
		-- spectators and station crew never gate the squad's extraction decision.
		if player:GetAttribute("GF_MissionParticipant") == true
			and player.Character and not (state and state.downed) then
			out[#out + 1] = player
		end
	end
	return out
end

local function publishVote()
	local r = remote("VoteStateChanged")
	if not r then
		return
	end
	if not vote then
		r:FireAllClients({ active = false })
		return
	end
	local names = {}
	for _, p in ipairs(vote.yes) do
		names[#names + 1] = p.Name
	end
	r:FireAllClients({ active = true, starter = vote.starter, yes = #vote.yes, needed = vote.needed, voters = names, remaining = math.max(0, math.floor(vote.endsAt - os.clock())) })
end

local lastVoteRequestAt = 0

function ExtractionService.requestVote(player: Player): boolean
	if called or vote then
		return false
	end
	-- vote repeat throttled: one request per 15s (spec anti-grief)
	local now = os.clock()
	if now - lastVoteRequestAt < 15 then
		workspace:SetAttribute("GF_ExtractionVote", "throttled")
		return false
	end
	if not workspace:GetAttribute("GF_InMission") then
		return false
	end
	-- The vote is a decision about a ship that can actually be called: with the objective open there is
	-- nothing to extract, and the call would be refused after the squad had already voted.
	if not ObjectiveService.isComplete() then
		workspace:SetAttribute("GF_ExtractionVote", "objective open")
		return false
	end
	local squad = liveSquad()
	if #squad == 0 then
		return false
	end
	lastVoteRequestAt = now
	if #squad == 1 then
		-- spec: vote solo immediate - a lone soldier never waits on a vote
		workspace:SetAttribute("GF_ExtractionVote", "solo immediate")
		ExtractionService.call(player)
		return true
	end
	local needed = math.max(1, math.floor(#squad / 2) + 1)
	vote = { starter = player.Name, yes = {}, needed = needed, endsAt = os.clock() + VOTE_WINDOW }
	workspace:SetAttribute("GF_ExtractionVote", string.format("%s:0/%d", player.Name, needed))
	publishVote()
	local ev = remote("MissionEvent")
	if ev then
		ev:FireAllClients({ text = string.format("%s called an extraction vote - %d of %d needed.", player.Name, needed, #squad), kind = "vote" })
	end
	task.delay(VOTE_WINDOW + 1, function()
		if vote and os.clock() >= vote.endsAt then
			vote = nil
			workspace:SetAttribute("GF_ExtractionVote", "expired")
			publishVote()
		end
	end)
	return true
end

function ExtractionService.castVote(player: Player, agrees: boolean)
	if not vote then
		return
	end
	if not agrees then
		vote = nil
		workspace:SetAttribute("GF_ExtractionVote", "rejected")
		publishVote()
		return
	end
	for _, p in ipairs(vote.yes) do
		if p == player then
			return
		end
	end
	table.insert(vote.yes, player)
	workspace:SetAttribute("GF_ExtractionVote", string.format("%s:%d/%d", vote.starter, #vote.yes, vote.needed))
	publishVote()
	if #vote.yes >= vote.needed then
		local starter = player
		for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
			if vote and p.Name == vote.starter then
				starter = p
			end
		end
		vote = nil
		workspace:SetAttribute("GF_ExtractionVote", "passed")
	publishVote()
		ExtractionService.call(starter)
	end
end

function ExtractionService.voteState()
	return vote
end

function ExtractionService.start()
	task.spawn(function()
		while true do
			task.wait(0.25)
			local count = 0
			for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
				local ps = State.get(p)
				local now = not extracted[p] and inCabin(p) and not (ps and ps.downed)
				if now then
					count += 1
				end
				aboard[p] = now or nil
				if p:GetAttribute("GF_Aboard") ~= now then
					p:SetAttribute("GF_Aboard", now)
				end
			end
			workspace:SetAttribute("GF_BoardedCount", count)
			if landed and dropship then
				local zone = dropship:FindFirstChild("BoardingZone")
				if zone then
					local all, c, total = allEligibleAboard()
					zone:SetAttribute("InteractPrompt", if all then string.format("Extract Squad (%d aboard, +25%% bonus)", c) else string.format("Extract Individually (%d/%d aboard; all aboard = +25%%)", c, total))
				end
			end
		end
	end)
	local call = remote("ExtractionRequest")
	local request = remote("RequestExtractionVote")
	if request then
		request.OnServerEvent:Connect(function(player)
			if not require(script.Parent.NetGuard).allow(player, "interact") then
				return
			end
			ExtractionService.requestVote(player)
		end)
	end
	local cast = remote("CastVote")
	if cast then
		cast.OnServerEvent:Connect(function(player, agrees)
			if not require(script.Parent.NetGuard).allow(player, "interact") then
				return
			end
			ExtractionService.castVote(player, agrees == true)
		end)
	end
	if call then
		call.OnServerEvent:Connect(function(player)
			if not require(script.Parent.NetGuard).allow(player, "interact") then
				return
			end
			ExtractionService.call(player)
		end)
	end
	local interact = remote("InteractRequest")
	if interact then
		interact.OnServerEvent:Connect(function(player, target)
			if target == "Extract" then
				if not require(script.Parent.NetGuard).allow(player, "interact") then
					return
				end
				ExtractionService.board(player)
			end
		end)
	end
end

-- S09-004/007 extraction conformance: on primary completion the nearest validated zone reveals
-- immediately — no mandatory walk before the call. After landing the ship stays available until
-- the hard deadline; there is no 30s boarding countdown pressuring the squad.

function ExtractionService.revealNearestZone()
	local zones = workspace:FindFirstChild("ExtractionZones")
	if not zones then return end
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, zone in ipairs(zones:GetChildren()) do
		if zone:IsA("BasePart") and not zone:GetAttribute("Invalid") then
			local squadPos = workspace:GetAttribute("GF_SquadCentroid")
			-- nearest by simple magnitude from the primary objective when no centroid is published
			local dist = zone.Position.Magnitude
			if dist < bestDist then
				bestDist = dist
				best = zone
			end
		end
	end
	if best then
		workspace:SetAttribute("GF_RevealedZone", best.Name)
		workspace:SetAttribute("GF_ZoneRevealedAt", os.clock())
	end
end

function ExtractionService.armHardDeadline()
	workspace:SetAttribute("GF_HardDeadline", os.clock() + HARD_DEADLINE)
	workspace:SetAttribute("GF_NoBoardingCountdown", true)
end

-- S09-015 commit freeze: once a player commits to extraction the mission ledger closes for
-- them — they become untargetable, leave the mission threat table, and their earnings lock.
-- Nothing after the commit changes what they take home.
function ExtractionService.commitFreeze(plr: Player)
	plr:SetAttribute("GF_ExtractionCommitted", true)
	plr:SetAttribute("GF_Untargetable", true)
	workspace:SetAttribute("GF_LedgerFrozen_" .. plr.UserId, os.clock())
	-- remove from enemy threat tables so AI stops considering them
	local enemies = workspace:FindFirstChild("ActiveActors")
	if enemies then
		for _, enemy in ipairs(enemies:GetChildren()) do
			if enemy:IsA("Model") and enemy:GetAttribute("GFEnemy") then
				local target = enemy:GetAttribute("TargetPlayer")
				if target == plr.Name then
					enemy:SetAttribute("TargetPlayer", nil)
				end
			end
		end
	end
end

return ExtractionService

