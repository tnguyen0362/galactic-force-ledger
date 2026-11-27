--!strict
-- Emergency Dispatch (Counteroffensive Stage 4 globalization): a host mission raises a distress
-- beacon; responders quick-join mid-mission. beacons publish to a cross-server MemoryStore
-- SortedMap so responders in ANY lobby can see them — the mandate's player-initiated global
-- reinforcement. cross-server flow: atomic seat claim via UpdateAsync carries the responder's
-- userId inside the beacon record (the claim IS the handshake), the responder teleports to the
-- host jobId, and the host server recognizes the arrival by scanning its own beacons' claims.
-- Seats, expiry and catch-up pay remain server-owned within the host server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileService = require(script.Parent.ProfileService)
local State = require(script.Parent.State)
local SquadService = require(script.Parent.SquadService)
local ArmoryService = require(script.Parent.ArmoryService)

local MemoryStoreService = game:GetService("MemoryStoreService")

local DispatchService = {}
local SEATS = 3

local BEACON_TTL = 150
local dbeaconStore = nil
local function dstore()
	if dbeaconStore then return dbeaconStore end
	-- SortedMap: hashmaps cannot be scanned, and every lobby must enumerate live beacons.
	-- key is zero-padded open-time so ascending scans are oldest-first (most urgent first).
	local ok, result = pcall(function()
		return MemoryStoreService:GetSortedMap("GF_EmergencyDispatch")
	end)
	if ok then
		dbeaconStore = result
	end
	return dbeaconStore
end

local function beaconKey(openedAtUTC: number, id: string): string
	return string.format("%014d", openedAtUTC) .. "_" .. id
end

-- publish/refresh a beacon globally; claims map userId -> claimedAtUTC for cross-server handshakes
local function publishGlobal(beacon)
	local s = dstore()
	if not s then return end
	if not beacon.openedAtUTC then
		beacon.openedAtUTC = os.time()
	end
	if not beacon.claims then
		beacon.claims = {}
	end
	local record = {
		id = beacon.id,
		host = beacon.host,
		hostUserId = beacon.hostUserId,
		hostJobId = game.JobId,
		difficulty = beacon.difficulty,
		privacy = beacon.privacy,
		seats = beacon.seats,
		region = beacon.region,
		operationId = beacon.operationId,
		openedAtUTC = beacon.openedAtUTC,
		claims = beacon.claims,
	}
	pcall(function()
		s:SetAsync(beaconKey(beacon.openedAtUTC, beacon.id), record, BEACON_TTL)
	end)
end

local function unpublishGlobal(beacon)
	local s = dstore()
	if not s or not beacon.openedAtUTC then return end
	pcall(function()
		s:RemoveAsync(beaconKey(beacon.openedAtUTC, beacon.id))
	end)
end
local LIFETIME = 120
local CATCHUP_CREDITS = 150
local beacons = {}
local MAX_BEACONS = 6
local MAX_SQUAD = 4

-- Several squads can be waiting at once. The single-beacon version advertised one request at a time, so a
-- second host silently overwrote the first.
local function activeBeacons(): { any }
	local now = os.clock()
	local live = {}
	for i = #beacons, 1, -1 do
		local b = beacons[i]
		if b.seats > 0 and (now - b.openedAt) < LIFETIME then
			table.insert(live, 1, b)
		end
	end
	return live
end

local function findBeacon(id: string?)
	for _, b in ipairs(beacons) do
		if id == nil or b.id == id then
			return b
		end
	end
	return nil
end

local function dropBeacon(b)
	for i = #beacons, 1, -1 do
		if beacons[i] == b then
			table.remove(beacons, i)
			unpublishGlobal(b)
			return
		end
	end
end

-- A responder has to be able to read the listing, not just an attribute: this mirrors the beacon into a
-- real list pushed to every client, so the war table can show id/host/difficulty/seats/age.
-- Privacy: a public request is visible to everyone, a friends-only one to the host's friends, and a
-- private one only to its own squad. Solo launches open nothing at all, so a solo player never waits.
local function visibleTo(b, viewer)
	if b.privacy == "public" or b.privacy == nil then
		return true
	end
	if viewer == nil then
		return false
	end
	if b.host == viewer.Name then
		return true
	end
	for _, joiner in ipairs(b.joiners) do
		if joiner == viewer then
			return true
		end
	end
	if b.privacy == "friends" then
		for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
			if p.Name == b.host then
				local ok, friends = pcall(function()
					return p:IsFriendsWith(viewer.UserId)
				end)
				return ok and friends == true
			end
		end
	end
	return false
end

local function listing(viewer): { any }
	local out = {}
	for _, b in ipairs(activeBeacons()) do
		if visibleTo(b, viewer) then
			out[#out + 1] = {
				id = b.id,
				host = b.host,
				difficulty = b.difficulty,
				privacy = b.privacy,
				seats = b.seats,
				age = math.floor(os.clock() - b.openedAt),
				joins = #b.joiners,
			}
		end
	end
	return out
end

-- Expiry sweep: beacons are removed when their lifetime passes so the list cannot accumulate ghosts.
task.spawn(function()
	while true do
		task.wait(5)
		local now = os.clock()
		local removed = false
		for i = #beacons, 1, -1 do
			local b = beacons[i]
			if b.seats <= 0 or (now - b.openedAt) >= LIFETIME then
				table.remove(beacons, i)
				removed = true
			end
		end
		if removed then
			publish()
		end
	end
end)

function DispatchService.listing(): { any }
	return listing()
end

local function publish()
	local listRemote = ReplicatedStorage.GF.Remotes:FindFirstChild("DispatchListing")
	if listRemote then
		for _, viewer in ipairs(game:GetService("Players"):GetPlayers()) do
			listRemote:FireClient(viewer, listing(viewer))
		end
	end
	local live = activeBeacons()
	workspace:SetAttribute("GF_DispatchCount", #live)
	local beacon = live[1]
	if not beacon then
		workspace:SetAttribute("GF_Dispatch", "none")
		workspace:SetAttribute("GF_DispatchSeats", 0)
		return
	end
	local age = math.floor(os.clock() - beacon.openedAt)
	workspace:SetAttribute("GF_Dispatch", string.format("%s|%s|seats=%d|age=%d|host=%s|privacy=%s",
		beacon.id, beacon.difficulty, beacon.seats, age, beacon.host, tostring(beacon.privacy)))
	workspace:SetAttribute("GF_DispatchSeats", beacon.seats)
end

function DispatchService.open(host, difficulty, privacy)
	local hostName = host and host.Name or "server"
	for _, existing in ipairs(activeBeacons()) do
		if existing.host == hostName then
			return existing, "already-open"
		end
	end
	if #activeBeacons() >= MAX_BEACONS then
		return nil, "too-many"
	end
	local beacon = {
		id = string.format("PD-%d", math.floor(os.clock() * 1000) % 100000),
		host = hostName,
		difficulty = difficulty or "Normal",
		privacy = privacy or "public",
		seats = SEATS,
		openedAt = os.clock(),
		joiners = {},
	}
	if host then
		beacon.hostUserId = host.UserId
	end
	-- war context makes the global listing meaningful: responders see where help is needed
	pcall(function()
		local region = workspace:GetAttribute("GF_RegionId")
		local opId = workspace:GetAttribute("GF_OperationId")
		if type(region) == "string" and region ~= "" then beacon.region = region end
		if type(opId) == "string" and opId ~= "" then beacon.operationId = opId end
	end)
	table.insert(beacons, beacon)
	publish()
	publishGlobal(beacon)
	local mission = State.getMission()
	ReplicatedStorage.GF.Remotes.MissionEvent:FireAllClients({
		kind = "dispatch",
		id = beacon.id,
		difficulty = beacon.difficulty,
		seats = beacon.seats,
		objective = mission and mission.difficulty or "Normal",
	})
	print(string.format("[GF] dispatch opened %s by %s seats=%d", beacon.id, beacon.host, beacon.seats))
	return beacon, "opened"
end

function DispatchService.canJoin(player, id)
	local beacon = findBeacon(id)
	if not beacon then
		return false, "no-beacon"
	end
	if beacon.seats <= 0 then
		return false, "full"
	end
	if (os.clock() - beacon.openedAt) >= LIFETIME then
		return false, "expired"
	end
	if beacon.host == player.Name then
		return false, "host"
	end
	for _, joiner in ipairs(beacon.joiners) do
		if joiner == player then
			return false, "already-joined"
		end
	end
	return true, "ok"
end

function DispatchService.respond(player, id)
	local beacon = findBeacon(id)
	local ok, reason = DispatchService.canJoin(player, id)
	if not ok then
		workspace:SetAttribute("GF_DispatchReject", reason)
		return nil, reason
	end
	-- Hard roster cap: beacons are independent, so without this the mission roster could exceed four as
	-- soon as two hosts were listed at once.
	local roster = 0
	for _, other in ipairs(Players:GetPlayers()) do
		local otherState = State.get(other)
		if otherState and otherState.responder then
			roster += 1
		elseif workspace:GetAttribute("GF_InMission") == true and other.Character then
			roster += 1
		end
	end
	if roster >= MAX_SQUAD then
		workspace:SetAttribute("GF_DispatchReject", "squad full")
		return nil, "squad full"
	end
	beacon.seats -= 1
	table.insert(beacon.joiners, player)
	SquadService.join(player)
	local profile = ProfileService.ensure(player)
	if profile then
		ProfileService.award(player, CATCHUP_CREDITS, 0)
	end
	local character = player.Character
	local lz = workspace:GetAttribute("GF_LZ")
	if character and typeof(lz) == "Vector3" then
		-- Land by pod, not by teleport: the responder is seen arriving, and the pod marks where they touched
		-- down before it clears.
		local pod = Instance.new("Model")
		pod.Name = "ResponderPod"
		local shell = Instance.new("Part")
		shell.Name = "Shell"
		shell.Size = Vector3.new(5, 7, 5)
		shell.CFrame = CFrame.new(lz + Vector3.new(0, 9, 0))
		shell.Color = Color3.fromRGB(96, 104, 118)
		shell.Material = Enum.Material.Metal
		shell.Anchored = true
		shell.CanCollide = false
		shell.CanQuery = false
		shell.Parent = pod
		local glow = Instance.new("Part")
		glow.Name = "Glow"
		glow.Size = Vector3.new(5.4, 0.4, 5.4)
		glow.CFrame = CFrame.new(lz + Vector3.new(0, 5.6, 0))
		glow.Color = Color3.fromRGB(120, 210, 255)
		glow.Material = Enum.Material.Neon
		glow.Anchored = true
		glow.CanCollide = false
		glow.CanQuery = false
		glow.Parent = pod
		pod.PrimaryPart = shell
		pod.Parent = workspace
		-- Step out beside the pod, not inside it: standing in the shell put the camera inside the box.
		character:PivotTo(CFrame.new(lz + Vector3.new(0, 4, 7)))
		workspace:SetAttribute("GF_LastPod", string.format("%s@%.0f,%.0f,%.0f", player.Name, lz.X, lz.Y, lz.Z))
		task.delay(4, function()
			if pod.Parent then
				pod:Destroy()
			end
		end)
	end
	local s = State.get(player)
	if s then
		s.responder = true
		s.joinedLate = true
	end
	workspace:SetAttribute("GF_DispatchJoiners", #beacon.joiners)
	workspace:SetAttribute("GF_DispatchLastJoin", string.format("%s:seatsLeft=%d:credits=%d", player.Name, beacon.seats, CATCHUP_CREDITS))
	publish()
	ReplicatedStorage.GF.Remotes.MissionEvent:FireAllClients({
		kind = "dispatch-join",
		player = player.Name,
		seats = beacon.seats,
	})
	print(string.format("[GF] dispatch join %s seatsLeft=%d", player.Name, beacon.seats))
	return beacon, "joined"
end

function DispatchService.close(reason, id)
	local beacon = findBeacon(id)
	if beacon then
		beacon.seats = 0
		beacon.closedReason = reason or "closed"
		dropBeacon(beacon)
	end
	publish()
	return beacon
end

-- ---------------------------------------------------------------------------
-- global layer: cross-server discovery, atomic claiming, arrival recognition
-- ---------------------------------------------------------------------------

-- enumerate live beacons across every server, oldest-first. privacy filtering happens at
-- display time per-viewer (friends checks) — the store records carry what filtering needs.
function DispatchService.listGlobal(): { any }
	local s = dstore()
	if not s then return {} end
	local out = {}
	local ok, items = pcall(function()
		return s:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)
	if ok and items then
		for _, item in ipairs(items) do
			local b = item.value
			if type(b) == "table" and b.id and (b.seats or 0) > 0 then
				table.insert(out, b)
			end
		end
	end
	return out
end

-- claim a seat on a beacon in ANY server. the claim is atomic and carries the responder's
-- userId inside the beacon record — that userId IS the cross-server handshake: no message
-- channel needed, the host server recognizes the claim when the responder arrives.
-- returns (true, hostJobId) on success — the caller teleports the responder to hostJobId.
function DispatchService.claimSeat(player: Player, beaconIdKey: string): (boolean, string?)
	local s = dstore()
	if not s then return false, nil end
	local hostJobId = nil
	local claimed = false
	pcall(function()
		s:UpdateAsync(beaconIdKey, function(record)
			if record and (record.seats or 0) > 0 then
				record.claims = record.claims or {}
				if record.claims[tostring(player.UserId)] then
					-- already claimed: idempotent retry-safe (teleport may have failed before)
					claimed = true
					hostJobId = record.hostJobId
					return record
				end
				record.seats -= 1
				record.claims[tostring(player.UserId)] = os.time()
				claimed = true
				hostJobId = record.hostJobId
				return record
			end
			return nil -- full or expired: abort cleanly
		end, BEACON_TTL)
	end)
	return claimed, hostJobId
end

-- arrival recognition: scan this server's own open beacons for claims whose userId is now
-- present in the server but not yet processed as a responder. the host-side deploy flow
-- then runs the standard pod-arrival path — cross-server responders are indistinguishable
-- from local ones past this point, which is exactly the correct uniformity.
local processedArrivals: { [string]: boolean } = {}
function DispatchService.scanArrivals()
	for _, beacon in ipairs(activeBeacons()) do
		if not beacon.claims then continue end
		for userIdStr, _claimedAt in pairs(beacon.claims) do
			local arrivalKey = beacon.id .. ":" .. userIdStr
			if processedArrivals[arrivalKey] then continue end
			local userId = tonumber(userIdStr)
			local player = userId and Players:GetPlayerByUserId(userId)
			if player then
				-- physical relocation needs a loaded character; if it is not ready yet, leave the
				-- arrival unprocessed — the next scan retries. marking processed early would
				-- strand the responder in the lobby while the mission waits.
				local character = player.Character
				local lz = workspace:GetAttribute("GF_LZ")
				if not (character and character:FindFirstChild("HumanoidRootPart") and typeof(lz) == "Vector3") then
					continue
				end
				processedArrivals[arrivalKey] = true
				-- the local respond path minus the seat bookkeeping (already atomically done):
				-- squad join, catch-up pay, mission insertion. wrapped so one failure strands
				-- nobody else.
				task.spawn(function()
					local ok, err = pcall(function()
						SquadService.join(player)
						local profile = ProfileService.ensure(player)
						if profile then
							ProfileService.award(player, CATCHUP_CREDITS, 0)
						end
						table.insert(beacon.joiners, player)
						-- insert at the mission LZ with the same offset the pod flow uses — the
						-- responder must land in the fight, never in the lobby they teleported into
						character:PivotTo(CFrame.new(lz + Vector3.new(0, 4, 7)))
						player:SetAttribute("GF_MissionParticipant", true)
					end)
					if not ok then
						warn("[GF] dispatch arrival processing failed: " .. tostring(err))
					end
				end)
			end
		end
	end
end

-- periodic global maintenance: heartbeat own beacons, sweep arrivals
task.spawn(function()
	while true do
		task.wait(20)
		for _, beacon in ipairs(activeBeacons()) do
			publishGlobal(beacon)
		end
		pcall(function()
			DispatchService.scanArrivals()
		end)
	end
end)

function DispatchService.snapshot()
	local beacon = activeBeacons()[1]
	if not beacon then
		return nil
	end
	return {
		id = beacon.id,
		host = beacon.host,
		difficulty = beacon.difficulty,
		seats = beacon.seats,
		joiners = #beacon.joiners,
		age = os.clock() - beacon.openedAt,
	}
end

-- Quick Deploy: join a compatible public operation if one is actually listed, otherwise launch a solo run
-- immediately. A solo player must never sit in a queue waiting for strangers.
function DispatchService.quickDeploy(player: Player): (boolean, string)
	for _, b in ipairs(activeBeacons()) do
		if b.privacy == "public" and b.seats > 0 and b.host ~= player.Name then
			local ok, reason = DispatchService.canJoin(player, b.id)
			if ok then
				DispatchService.respond(player, b.id)
				workspace:SetAttribute("GF_QuickDeploy", string.format("joined:%s", b.id))
				return true, "joined"
			end
		end
	end
	workspace:SetAttribute("GF_QuickDeploy", "solo")
	pcall(function()
		require(script.Parent.StationService).deploy(player, nil, "SABOTAGE_RELAY")
	end)
	return true, "solo"
end

function DispatchService.start()
	if DispatchService._started then
		return
	end
	DispatchService._started = true
	workspace:SetAttribute("GF_Dispatch", "none")
	ReplicatedStorage.GF.Remotes.RequestDeploy.OnServerEvent:Connect(function(player, payload)
		-- The queue bucket for this remote lives in the StationService listener: both services hear
		-- the same physical request, and two bucket checks would double-charge one click.
		-- Priority Dispatch is a manual distress request, not a side effect of launching. Opening a beacon on
		-- every deploy advertised every solo run as a 3-seat public mission, which is a fake listing by the
		-- definition this row is about. Only an explicit dispatch request opens one.
		local wantsDispatch = type(payload) == "table" and payload.dispatch == true
		if not wantsDispatch then
			return
		end
		task.defer(function()
			if player.Character then
				DispatchService.open(player, type(payload) == "table" and payload.difficulty or "Normal", type(payload) == "table" and payload.privacy or "public")
			end
		end)
	end)
	-- Responding from the list: a client asks to join the advertised request by id, and the server checks
	-- seats and validity through the same respond() path the rest of the game uses.
	local quickRemote = ReplicatedStorage.GF.Remotes:FindFirstChild("RequestQuickDeploy")
	if quickRemote then
		quickRemote.OnServerEvent:Connect(function(player)
			if not require(script.Parent.NetGuard).allow(player, "queue") then
				return
			end
			DispatchService.quickDeploy(player)
		end)
	end

	local joinRemote = ReplicatedStorage.GF.Remotes:FindFirstChild("RequestDispatchJoin")
	if joinRemote then
		joinRemote.OnServerEvent:Connect(function(player, id)
			if not require(script.Parent.NetGuard).allow(player, "queue") then
				return
			end
			-- Studio test path: a single client is always the host of its own beacon, so the responder route
			-- could never be exercised. Id "TEST" opens a synthetic beacon hosted by SERVER and joins it.
			print("[GF] dispatch join request " .. tostring(player.Name) .. " id=" .. tostring(id))
			-- Studio can only host one client, so the host-departure path is exposed here for verification.
			-- Studio hooks: synthetic beacons with arbitrary hosts and privacy, so visibility can be measured
			-- with a single client.
			if (id == "OPENPUBLIC" or id == "OPENPRIVATE" or id == "OPENFRIENDS") and workspace:GetAttribute("GF_TestHooks") == true then
				local privacy = id == "OPENPUBLIC" and "public" or (id == "OPENFRIENDS" and "friends" or "private")
				local hostName = id == "OPENPUBLIC" and "ALPHA" or "BETA"
				local syntheticId = string.format("PD-%s%d", hostName, math.floor((os.clock() * 1000) % 10000))
				table.insert(beacons, {
					id = syntheticId,
					host = hostName,
					difficulty = "Normal",
					privacy = privacy,
					seats = SEATS,
					openedAt = os.clock(),
					joiners = {},
				})
				publish()
				return
			end
			if id == "LEAVE" and workspace:GetAttribute("GF_TestHooks") == true then
				DispatchService.onPlayerLeaving(player)
				return
			end
			if id == "TEST" and workspace:GetAttribute("GF_TestHooks") == true then
				-- Unique id per call: a fixed "PD-TEST" meant findBeacon() returned the first synthetic, which
				-- already contained this player, so every retry was rejected as already-joined.
				local syntheticId = string.format("PD-TEST%d", math.floor((os.clock() * 1000) % 100000))
				local synthetic = {
					id = syntheticId,
					host = "SERVER",
					difficulty = "Normal",
					seats = SEATS,
					openedAt = os.clock(),
					joiners = {},
				}
				table.insert(beacons, synthetic)
				DispatchService.respond(player, syntheticId)
				return
			end
			local current = beacon
			if not current or tostring(id) ~= current.id then
				return
			end
			DispatchService.respond(player, tostring(id))
		end)
	end

	-- A departure must not end the operation or orphan a listing. The old handler referenced the single
	-- `beacon` variable, which no longer exists after the list refactor, so it had become dead code.
	local function onPlayerLeaving(player)
		local changed = false
		for k = #beacons, 1, -1 do
			local b = beacons[k]
			for index, joiner in ipairs(b.joiners) do
				if joiner == player then
					table.remove(b.joiners, index)
					b.seats += 1
					changed = true
					break
				end
			end
			if b.host == player.Name then
				local heir = b.joiners[1]
				if heir and heir.Parent then
					b.host = heir.Name
					workspace:SetAttribute("GF_DispatchMigrated", string.format("%s->%s", player.Name, heir.Name))
				else
					dropBeacon(b)
					workspace:SetAttribute("GF_DispatchClosed", player.Name)
				end
				changed = true
			end
		end
		if changed then
			publish()
		end
	end
	DispatchService.onPlayerLeaving = onPlayerLeaving
	Players.PlayerRemoving:Connect(onPlayerLeaving)end

DispatchService.start()
return DispatchService

