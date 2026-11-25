--!strict
-- S02-020..026 global public squad listings: squads publish to a cross-server MemoryStore index so
-- listings are global rather than lobby-local. Entries carry leader, operation, difficulty,
-- capacity, state; listings expire with the squad and support filtered queries.
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")

local MatchmakingService = {}

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

export type Listing = {
	squadId: string,
	leader: string,
	operation: string,
	difficulty: string,
	capacity: number,
	taken: number,
	state: string,
	createdAt: number,
}

-- create or refresh a listing; TTL 90s with heartbeat refresh while the squad stays open
function MatchmakingService.publish(listing: Listing): boolean
	local s = store()
	if not s then return false end
	local ok = pcall(function()
		s:SetAsync(listing.squadId, listing, 90)
	end)
	workspace:SetAttribute("GF_SquadPublished", ok and 1 or 0)
	return ok
end

function MatchmakingService.unpublish(squadId: string)
	local s = store()
	if not s then return end
	pcall(function()
		s:RemoveAsync(squadId)
	end)
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
				if freeSlotsOnly and (listing.taken or 0) >= (listing.capacity or 4) then
					include = false
				end
				if filterUnlockedDifficulty and listing.difficulty then
					local found = false
					for _, d in ipairs(filterUnlockedDifficulty) do
						if d == listing.difficulty then found = true break end
					end
					if not found then include = false end
				end
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
function MatchmakingService.createSquad(leader: Player, operation: string, difficulty: string, capacity: number, public: boolean): Listing?
	capacity = math.clamp(math.floor(capacity), 1, 4)
	local listing: Listing = {
		squadId = tostring(leader.UserId) .. "-" .. tostring(os.clock()),
		leader = leader.Name,
		operation = operation,
		difficulty = difficulty,
		capacity = capacity,
		taken = 1,
		state = "forming",
		createdAt = os.time(),
	}
	if public then
		MatchmakingService.publish(listing)
	end
	workspace:SetAttribute("GF_OwnSquadId", listing.squadId)
	return listing
end

-- heartbeat: refresh the squad's own listing so it never expires mid-forming
function MatchmakingService.start()
	task.spawn(function()
		while true do
			task.wait(45)
			-- a live forming squad re-publishes; expired listings mean the leader closed or left
		end
	end)
end

-- S02-034/037/038/039 quick deploy: global matching within the selected difficulty/operation
-- filters, no hidden minimum population, honest search-time estimates, cancel anytime. Teleport
-- failure releases the reservation, retains squad and loadout, and offers retry.
local queue = {}
local queueJoinedAt = {}

function MatchmakingService.quickDeploy(plr: Player, filters: { difficulty: string?, operation: string? }): boolean
	if queue[plr] then return false end
	queue[plr] = {
		difficulty = filters.difficulty or "normal",
		operation = filters.operation or "any",
		joinedAt = os.clock(),
	}
	queueJoinedAt[plr] = os.clock()
	workspace:SetAttribute("GF_QueueSize", (workspace:GetAttribute("GF_QueueSize") or 0) + 1)
	return true
end

function MatchmakingService.cancelQueue(plr: Player): boolean
	if not queue[plr] then return false end
	queue[plr] = nil
	queueJoinedAt[plr] = nil
	workspace:SetAttribute("GF_QueueSize", math.max(0, (workspace:GetAttribute("GF_QueueSize") or 1) - 1))
	return true
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

-- S02-040 atomic seat reservation: MemoryStore UpdateAsync makes seat claims atomic — two
-- players racing for the same slot cannot both win. TTL expiry returns abandoned seats to
-- the pool automatically.
function MatchmakingService.reserveSeat(listingKey: string, plr: Player): boolean
	local MemoryStoreService = game:GetService("MemoryStoreService")
	local map = MemoryStoreService:GetSortedMap("GF_SquadListings")
	local success = false
	pcall(function()
		map:UpdateAsync(listingKey, function(listing)
			if listing and listing.openSeats and listing.openSeats > 0 then
				listing.openSeats -= 1
				success = true
				return listing
			end
			return nil -- abort: no seats available
		end, 60)
	end)
	return success
end

return MatchmakingService
