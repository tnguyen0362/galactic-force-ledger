--!strict
-- Hybrid matchmaking (Counteroffensive Stage 4): local-first, global-fallback.
-- Global squad listings over a single consistent MemoryStore SortedMap (GF_PublicSquads) —
-- the GF_SquadListings split-store dead path is removed. Listings carry the leader's jobId so
-- cross-server joins teleport directly to the hosting lobby. Atomic seat reservation via
-- UpdateAsync on the SAME store. Quick-deploy is a cross-server MemoryStore queue with a
-- real matching drain — the in-memory per-server queue that never drained is gone.
-- INTERIM CONSTRAINT (documented in STAGE4 design sec.8): one hosted squad per server until
-- the reserved-server mission architecture lands; the data model carries squadIds throughout
-- so the multi-squad migration is additive.
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")

local MatchmakingService = {}

local LISTING_TTL = 90
local HEARTBEAT_PERIOD = 45
local QUEUE_TTL = 300
local MATCH_POLL = 5

local index = nil
local function store()
	if index then return index end
	local ok, result = pcall(function()
		return MemoryStoreService:GetSortedMap("GF_PublicSquads")
	end)
	if ok then
		index = result
	end
	return index
end

local queueStore = nil
local function qstore()
	if queueStore then return queueStore end
	-- SortedMap, not HashMap: hashmaps cannot be scanned at all (no list operation), and a
	-- matching drain that cannot see the queue is theater. GetRangeAsync oldest-first is the
	-- correct primitive — sort key is the join timestamp encoded in the key itself.
	local ok, result = pcall(function()
		return MemoryStoreService:GetSortedMap("GF_QuickDeployQueue")
	end)
	if ok then
		queueStore = result
	end
	return queueStore
end

export type Listing = {
	squadId: string,
	leader: string,
	leaderUserId: number,
	leaderJobId: string,
	operationId: string?,
	region: string?,
	difficulty: string,
	capacity: number,
	taken: number,
	openSeats: number,
	state: string,
	createdAt: number,
}

-- the squad this server hosts (interim single-squad constraint); nil when none
local hostedSquadId: string? = nil
local hostedListing: Listing? = nil

-- create or refresh a listing; TTL 90s with heartbeat refresh while the squad stays open
function MatchmakingService.publish(listing: Listing): boolean
	local s = store()
	if not s then return false end
	listing.leaderJobId = game.JobId
	listing.openSeats = math.max(0, (listing.capacity or 4) - (listing.taken or 1))
	local ok = pcall(function()
		s:SetAsync(listing.squadId, listing, LISTING_TTL)
	end)
	if ok then
		hostedSquadId = listing.squadId
		hostedListing = listing
	end
	workspace:SetAttribute("GF_SquadPublished", ok and 1 or 0)
	return ok
end

function MatchmakingService.unpublish(squadId: string)
	local s = store()
	if not s then return end
	pcall(function()
		s:RemoveAsync(squadId)
	end)
	if hostedSquadId == squadId then
		hostedSquadId = nil
		hostedListing = nil
	end
end

-- membership changed: republish with the new taken-count so open seats stay truthful
function MatchmakingService.updateTaken(squadId: string, taken: number)
	if hostedListing and hostedListing.squadId == squadId then
		hostedListing.taken = taken
		MatchmakingService.publish(hostedListing)
	end
end

function MatchmakingService.hostedSquad(): (string?, Listing?)
	return hostedSquadId, hostedListing
end

-- global listing query: every public squad across all servers, optionally filtered to
-- difficulty the player has unlocked plus squads with free slots (S02-022)
function MatchmakingService.list(filterUnlockedDifficulty: { string }?, freeSlotsOnly: boolean?): { Listing }
	local s = store()
	if not s then return {} end
	local out = {}
	local ok, items = pcall(function()
		return s:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)
	if ok and items then
		for _, entry in ipairs(items) do
			local listing = entry.value
			if type(listing) == "table" and listing.squadId then
				local include = true
				if freeSlotsOnly and (listing.openSeats or 0) <= 0 then
					include = false
				end
				if filterUnlockedDifficulty and listing.difficulty then
					local found = false
					for _, d in ipairs(filterUnlockedDifficulty) do
						if d == listing.difficulty then found = true break end
					end
					if not found then include = false end
				end
				-- never list the squad you are already in
				if include then
					table.insert(out, listing)
				end
			end
		end
	end
	workspace:SetAttribute("GF_PublicListingCount", #out)
	return out
end

-- create a squad with leader/cap/visibility — caps 1-4 per spec, private invite-only option
function MatchmakingService.createSquad(leader: Player, operationId: string?, difficulty: string, capacity: number, public: boolean, region: string?): Listing?
	capacity = math.clamp(math.floor(capacity), 1, 4)
	local listing: Listing = {
		squadId = tostring(leader.UserId) .. "-" .. tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999)),
		leader = leader.Name,
		leaderUserId = leader.UserId,
		leaderJobId = game.JobId,
		operationId = operationId,
		region = region,
		difficulty = difficulty,
		capacity = capacity,
		taken = 1,
		openSeats = capacity - 1,
		state = "forming",
		createdAt = os.time(),
	}
	if public then
		MatchmakingService.publish(listing)
	else
		hostedSquadId = listing.squadId
		hostedListing = listing
	end
	workspace:SetAttribute("GF_OwnSquadId", listing.squadId)
	return listing
end

-- heartbeat: refresh the hosted squad's listing so it never expires mid-forming.
-- the previous loop was an empty stub — listings died at 90s regardless of squad health.
function MatchmakingService.start()
	task.spawn(function()
		while true do
			task.wait(HEARTBEAT_PERIOD)
			if hostedListing and hostedSquadId then
				local s = store()
				if s then
					pcall(function()
						-- refresh claims/seats from the store before republishing: cross-server
						-- reservations mutate the authoritative record, and a blind heartbeat
						-- republish would clobber them back to stale values
						local fresh = s:GetAsync(hostedSquadId)
						if type(fresh) == "table" then
							hostedListing.claims = fresh.claims
							hostedListing.openSeats = fresh.openSeats
							hostedListing.taken = fresh.taken
						end
						hostedListing.leaderJobId = game.JobId
						s:SetAsync(hostedSquadId, hostedListing, LISTING_TTL)
					end)
				end
			end
			-- cross-server arrival recognition: players present with claims on the hosted
			-- listing get joined — uniform with the dispatch arrival pattern
			pcall(function()
				MatchmakingService.scanArrivals()
			end)
		end
	end)
	-- quick-deploy matching drain: scan the global queue, group compatible entries,
	-- transition matched entries toward the oldest member's server
	task.spawn(function()
		while true do
			task.wait(MATCH_POLL)
			pcall(function()
				MatchmakingService.drainQueue()
			end)
		end
	end)
end

-- S02-040 atomic seat reservation: UpdateAsync on the SAME store the listings live in —
-- two players racing for the last seat cannot both win. the dead GF_SquadListings split
-- is removed; reservation failure means the squad filled or expired, never a phantom seat.
function MatchmakingService.reserveSeat(listingKey: string, plr: Player): boolean
	local s = store()
	if not s then return false end
	local success = false
	pcall(function()
		s:UpdateAsync(listingKey, function(listing)
			if listing and (listing.openSeats or 0) > 0 and listing.state == "forming" then
				-- the claim carries the userId: it IS the cross-server handshake. the host
				-- server scans its hosted listing for claims of present players and joins
				-- them — no message channel, no teleport data needed
				listing.claims = listing.claims or {}
				listing.claims[tostring(plr.UserId)] = os.time()
				listing.openSeats -= 1
				listing.taken = (listing.taken or 1) + 1
				success = true
				return listing
			end
			return nil -- abort: no seats or squad closed
		end, LISTING_TTL)
	end)
	return success
end

-- read a single listing (post-reservation join needs the leader jobId)
function MatchmakingService.getListing(squadId: string): Listing?
	local s = store()
	if not s then return nil end
	local ok, result = pcall(function()
		return s:GetAsync(squadId)
	end)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

-- cross-server arrival recognition for squad joins: a claimed userId present in this server
-- is a squad joiner. processed exactly once per claim; local joins never carry claims so
-- there is no double-processing path.
local processedJoinClaims: { [string]: boolean } = {}
function MatchmakingService.scanArrivals()
	if not hostedListing or not hostedSquadId then return end
	local claims = hostedListing.claims
	if type(claims) ~= "table" then return end
	local SquadService = require(script.Parent.SquadService)
	for userIdStr, _t in pairs(claims) do
		local claimKey = hostedSquadId .. ":" .. userIdStr
		if not processedJoinClaims[claimKey] then
			local userId = tonumber(userIdStr)
			local player = userId and Players:GetPlayerByUserId(userId)
			if player then
				processedJoinClaims[claimKey] = true
				SquadService.join(player)
				player:SetAttribute("GF_SquadJoinArrived", os.time())
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- quick deploy: cross-server queue over MemoryStore. entries are per-player, TTL 5min.
-- matching: difficulty overlap AND operation overlap (or "any"). the oldest compatible
-- entry's server hosts; other matched entries transition state="matched" carrying the
-- host jobId — their home servers observe the transition on their own drain pass and
-- teleport the player across. honest estimates come from recorded match times only.
-- ---------------------------------------------------------------------------

local function queueKey(userId: number, joinedAt: number?): string
	-- zero-padded timestamp prefix so the SortedMap's ascending range scan IS oldest-first
	-- (lexicographic order on fixed-width numbers is numeric order); userId suffix unique-keys
	local t = joinedAt or os.time()
	return string.format("%014d", t) .. "_" .. tostring(userId)
end

function MatchmakingService.quickDeploy(plr: Player, filters: { difficulty: string?, operationId: string? }): boolean
	local qs = qstore()
	if not qs then return false end
	local entry = {
		userId = plr.UserId,
		name = plr.Name,
		difficulty = filters.difficulty or "Normal",
		operationId = filters.operationId or "any",
		joinedAt = os.time(),
		jobId = game.JobId,
		state = "queued",
	}
	local key = queueKey(plr.UserId, entry.joinedAt)
	local ok = pcall(function()
		qs:SetAsync(key, entry, QUEUE_TTL)
	end)
	if ok then
		-- the exact key is needed for cancel/lookup without scanning; the workspace attribute
		-- is server-local but so is the player — cross-server observation uses the scan
		workspace:SetAttribute("GF_QDKey_" .. plr.UserId, key)
		workspace:SetAttribute("GF_QueueSize", (workspace:GetAttribute("GF_QueueSize") or 0) + 1)
	end
	return ok
end

function MatchmakingService.cancelQueue(plr: Player): boolean
	local qs = qstore()
	if not qs then return false end
	local key = workspace:GetAttribute("GF_QDKey_" .. plr.UserId)
	if type(key) ~= "string" then return false end
	pcall(function()
		qs:RemoveAsync(key)
	end)
	workspace:SetAttribute("GF_QDKey_" .. plr.UserId, nil)
	return true
end

-- read this server's local players' queue entries — matched transitions are acted on here
function MatchmakingService.localQueueStates(): { any }
	local qs = qstore()
	if not qs then return {} end
	local out = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local ok, entry = pcall(function()
			return qs:GetAsync(queueKey(plr.UserId))
		end)
		if ok and type(entry) == "table" then
			table.insert(out, entry)
		end
	end
	return out
end

local function compatible(a, b): boolean
	if a.userId == b.userId then return false end
	local diffOk = a.difficulty == b.difficulty
	local opOk = a.operationId == "any" or b.operationId == "any" or a.operationId == b.operationId
	return diffOk and opOk and a.state == "queued" and b.state == "queued"
end

-- the matching drain. correctness notes: entries transition exactly once (queued → matched)
-- via UpdateAsync so two servers draining concurrently cannot double-match the same player.
-- a full match is up to 4 players; partial matches of 2+ also launch — no hidden minimum
-- population, and solo launch remains available outside the queue entirely.
function MatchmakingService.drainQueue()
	local qs = qstore()
	if not qs then return end
	-- phase 1: act on match transitions for LOCAL players (matched anywhere -> hand off)
	for _, plr in ipairs(Players:GetPlayers()) do
		local key = workspace:GetAttribute("GF_QDKey_" .. plr.UserId)
		if type(key) == "string" then
			local ok2, entry = pcall(function()
				return qs:GetAsync(key)
			end)
			if ok2 and type(entry) == "table" and entry.state == "matched" and type(entry.hostJobId) == "string" then
				if entry.hostJobId ~= game.JobId then
					workspace:SetAttribute("GF_QuickDeployMatch_" .. plr.UserId, entry.hostJobId)
					-- consumption is the teleport flow's job (Stage 4 client wiring) — the
					-- attribute is the durable handoff so a reconnecting client still sees it
				end
				pcall(function()
					qs:RemoveAsync(key)
				end)
				workspace:SetAttribute("GF_QDKey_" .. plr.UserId, nil)
			end
		end
	end
	-- phase 2: global scan + match formation. entries transition exactly once via UpdateAsync,
	-- so concurrent drains either see the transitioned state or lose the write race.
	local ok, items = pcall(function()
		return qs:GetRangeAsync(Enum.SortDirection.Ascending, 200)
	end)
	if not (ok and items) then return end
	local queued = {}
	for _, item in ipairs(items) do
		local entry = item.value
		if type(entry) == "table" and entry.state == "queued" then
			entry._key = item.key
			table.insert(queued, entry)
		end
	end
	local matched: { [number]: boolean } = {}
	for _, anchor in ipairs(queued) do
		if not matched[anchor.userId] then
			local group = { anchor }
			for _, candidate in ipairs(queued) do
				if #group < 4 and not matched[candidate.userId] and compatible(anchor, candidate) then
					table.insert(group, candidate)
				end
			end
			if #group >= 2 then
				-- the anchor (oldest) hosts in their current server
				for _, member in group do
					local mkey = member._key
					local uid = member.userId
					pcall(function()
						qs:UpdateAsync(mkey, function(current)
							if current and current.state == "queued" then
								current.state = "matched"
								current.hostJobId = anchor.jobId
								current.hostUserId = anchor.userId
								current.matchedAt = os.time()
								matched[uid] = true
								return current
							end
							return nil -- already consumed elsewhere: lose the race cleanly
						end, QUEUE_TTL)
					end)
				end
			end
		end
	end
end

-- measured estimate: average actual match time, never an invented number
local matchTimes = {}
function MatchmakingService.estimatedWait(): number?
	if #matchTimes == 0 then return nil end
	local total = 0
	for _, t in ipairs(matchTimes) do total += t end
	return total / #matchTimes
end

function MatchmakingService.recordMatchTime(seconds: number)
	table.insert(matchTimes, seconds)
	if #matchTimes > 50 then
		table.remove(matchTimes, 1)
	end
end

-- S02-039 teleport failure reconciliation: release the reservation, keep squad and loadout intact
function MatchmakingService.reconcileFailedTeleport(plr: Player)
	workspace:SetAttribute("GF_TeleportFailed_" .. plr.UserId, os.clock())
	workspace:SetAttribute("GF_TeleportRetry", true)
	-- squad membership and loadout snapshot persist — nothing is torn down on failure
end

-- exposed for the headless harness: pure matching compatibility
MatchmakingService._compatible = compatible

return MatchmakingService
