--!strict
-- RewardLedgerService: the append-only rewards ledger required by GOAL_2026-11-24.md L145
-- ("append immutable events (missionId,seq,eventType,serverTime,eligibleUserIds,resourceDelta,sourceId);
-- per-source claim once").
--
-- This module RECORDS. It deliberately does not change any payout yet: RewardsService still computes and
-- grants exactly as before, so nothing about the economy moves until a later batch drives settlement from
-- the ledger. Recording first means the event shape can be inspected against real missions before it is
-- trusted with money.
--
-- Two invariants it enforces:
--   1. seq is monotonic per mission, so a missing or reordered event is detectable.
--   2. a sourceId can be claimed exactly once, so a retry or a double fire cannot pay twice.
local RewardLedgerService = {}

-- Authored per-event reward table (GOAL_2026-11-24.md L150-L157). Values are the BASE for Normal; the
-- difficulty multipliers below are applied per event and the totals stay fractional. The spec is explicit:
-- "Compute fractional event totals then floor at settlement, no rounding each hit" (L161), so nothing here
-- floors or rounds. Settlement is what floors, and settlement does not read this ledger yet.
local EVENTS = {
	primary_complete = { credits = 300, xp = 350, mastery = 0 },
	extraction_success = { credits = 100, xp = 100, mastery = 0 },
	extraction_failed = { credits = 0, xp = 0, mastery = 0 },
	optional_task = { credits = 50, xp = 65, mastery = 0 },
	kill_Rifleman = { credits = 1, xp = 10, mastery = 10 },
	kill_Scout = { credits = 1, xp = 10, mastery = 10 },
	kill_Marksman = { credits = 1, xp = 10, mastery = 10 },
	kill_Heavy = { credits = 3, xp = 20, mastery = 20 },
	kill_Officer = { credits = 5, xp = 35, mastery = 35 },
	kill_SpectreAssault = { credits = 3, xp = 20, mastery = 20 },
	kill_SpectreWeapons = { credits = 3, xp = 20, mastery = 20 },
	kill_SpectrePrecision = { credits = 3, xp = 20, mastery = 20 },
	kill_SpectreSupport = { credits = 3, xp = 20, mastery = 20 },
	kill_SpectreLeader = { credits = 5, xp = 35, mastery = 35 },
	kill_RevenantAssault = { credits = 4, xp = 25, mastery = 25 },
	kill_RevenantWeapons = { credits = 4, xp = 25, mastery = 25 },
	kill_RevenantPrecision = { credits = 4, xp = 25, mastery = 25 },
	kill_RevenantDefense = { credits = 4, xp = 25, mastery = 25 },
	kill_RevenantLeader = { credits = 5, xp = 35, mastery = 35 },
	kill_BastionTank = { credits = 15, xp = 50, mastery = 50 },
	kill_BastionWalker = { credits = 60, xp = 100, mastery = 100 },
	kill_BastionSiege = { credits = 60, xp = 100, mastery = 100 },
	kill_LeviathanWalker = { credits = 100, xp = 250, mastery = 250 },
	kill_HighMarshalVeyr = { credits = 100, xp = 250, mastery = 250 },
	-- non-kill reward categories: salvage pickups, cache and blueprint entitlements (spec §28)
	salvage_pickup = { credits = 0, xp = 0, mastery = 0 },
	cache_entitlement = { credits = 0, xp = 0, mastery = 0 },
	blueprint_entitlement = { credits = 0, xp = 0, mastery = 0 },
}
local CREDIT_MULT = { Easy = 0.8, Normal = 1, Hard = 1.35, Extreme = 1.65 }
local XP_MULT = { Easy = 1, Normal = 1.25, Hard = 1.75, Extreme = 2.5 }

local MAX_EVENTS = 200

local ledger = {
	missionId = nil,
	seq = 0,
	events = {},
	claimed = {},
	missionCount = 0,
}

local function publish()
	workspace:SetAttribute("GF_LedgerMission", tostring(ledger.missionId))
	workspace:SetAttribute("GF_LedgerCount", #ledger.events)
	workspace:SetAttribute("GF_LedgerSeq", ledger.seq)
	local last = ledger.events[#ledger.events]
	workspace:SetAttribute("GF_LedgerLast", last and string.format("%s:%s:%s", tostring(last.eventType), tostring(last.sourceId), tostring(last.resourceDelta)) or "")
end

-- Starts a fresh mission ledger. Called when a mission begins; a mission id is derived from a counter and
-- the clock so two missions in one session cannot collide.
function RewardLedgerService.begin(context: string?): string
	ledger.missionCount += 1
	ledger.missionId = string.format("m%d-%d-%s", ledger.missionCount, os.time(), tostring(context or "mission"))
	ledger.seq = 0
	ledger.events = {}
	ledger.claimed = {}
	publish()
	return ledger.missionId
end

function RewardLedgerService.missionId(): string?
	return ledger.missionId
end

-- Appends one immutable event. Returns the event, or nil when the sourceId was already claimed.
function RewardLedgerService.append(eventType: string, resourceDelta: number?, sourceId: string?, userId: number?)
	if not ledger.missionId then
		ledger.missionId = string.format("m%d-%d-unbegun", ledger.missionCount + 1, os.time())
	end
	local source = tostring(sourceId or (eventType .. ":" .. tostring(ledger.seq + 1)))
	if ledger.claimed[source] then
		workspace:SetAttribute("GF_LedgerRejected", "duplicate source: " .. source)
		return nil
	end
	ledger.claimed[source] = true
	ledger.seq += 1
	local event = {
		missionId = ledger.missionId,
		seq = ledger.seq,
		eventType = eventType,
		serverTime = os.clock(),
		userId = userId,
		resourceDelta = tonumber(resourceDelta) or 0,
		sourceId = source,
	}
	table.insert(ledger.events, event)
	if #ledger.events > MAX_EVENTS then
		table.remove(ledger.events, 1)
	end
	publish()
	return event
end

-- True when this sourceId has already been recorded for the current mission.
-- Fractional value of one authored event at a difficulty. No flooring, no rounding: the spec floors once at
-- settlement so accumulated per-kill fractions do not each lose a remainder.
-- Eligible participant set (GOAL_2026-11-24.md L145/L027): shared credits and salvage are owed in full to
-- every present active, downed or pending-life participant. A permanently dead soldier who has left, or a
-- player who disconnected, is not eligible. There is no SquadService eligibility notion to call, so this is
-- derived from the live session state: a player with a runtime state is present and still owed.
function RewardLedgerService.eligibleUserIds(): { number }
	local ids = {}
	local ok = pcall(function()
		local SSSv = game:GetService("ServerScriptService")
		local StateMod = require(SSSv.GF.Services.State)
		for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
			local st = StateMod.get(p)
			-- eligibility requires server-confirmed mission arrival (S09-026): lobby sitters and
			-- players who already returned to the station are excluded even though they hold state.
			if st and p:GetAttribute("GF_MissionParticipant") == true then
				table.insert(ids, p.UserId)
			end
		end
	end)
	if not ok then
		return {}
	end
	table.sort(ids)
	return ids
end

function RewardLedgerService.value(eventType: string, difficulty: string?)
	local def = EVENTS[eventType]
	if not def then
		return 0, 0, 0
	end
	local d = tostring(difficulty or "Normal")
	local creditMult = CREDIT_MULT[d] or CREDIT_MULT.Normal
	local xpMult = XP_MULT[d] or XP_MULT.Normal
	return def.credits * creditMult, def.xp * xpMult, def.mastery * xpMult
end

-- Appends an authored event, storing the computed fractional credits/xp/mastery on the event. Record only:
-- nothing here pays the player. Settlement still computes payouts the old way until a later batch switches it.
function RewardLedgerService.appendEvent(eventType: string, difficulty: string?, sourceId: string?, userId: number?)
	local credits, xp, mastery = RewardLedgerService.value(eventType, difficulty)
	local event = RewardLedgerService.append(eventType, credits, sourceId, userId)
	if event then
		event.eligibleUserIds = RewardLedgerService.eligibleUserIds()
		workspace:SetAttribute("GF_LedgerEligible", table.concat(event.eligibleUserIds, ","))
		event.credits = credits
		event.xp = xp
		event.mastery = mastery
		event.difficulty = tostring(difficulty or "Normal")
		workspace:SetAttribute("GF_LedgerLastValue", string.format("%s:%s:cr=%.2f xp=%.2f m=%.2f",
			eventType, tostring(difficulty or "Normal"), credits, xp, mastery))
	end
	return event
end

-- Summed fractional totals for the current mission. Reported only; never granted from here.
function RewardLedgerService.totals()
	local credits, xp, mastery = 0, 0, 0
	for _, e in ipairs(ledger.events) do
		credits += tonumber(e.credits) or 0
		xp += tonumber(e.xp) or 0
		mastery += tonumber(e.mastery) or 0
	end
	return credits, xp, mastery
end

function RewardLedgerService.isClaimed(sourceId: string?): boolean
	local source = tostring(sourceId or "")
	return ledger.claimed[source] == true
end

function RewardLedgerService.snapshot()
	local copy = {}
	for i, e in ipairs(ledger.events) do
		copy[i] = {
			missionId = e.missionId, seq = e.seq, eventType = e.eventType,
			serverTime = e.serverTime, userId = e.userId,
			resourceDelta = e.resourceDelta, sourceId = e.sourceId,
			-- Authored per-event values. Copy them here: a snapshot that drops them makes a working ledger
			-- look like one that never computed anything.
			credits = e.credits, xp = e.xp, mastery = e.mastery, difficulty = e.difficulty,
			eligibleUserIds = e.eligibleUserIds,
		}
	end
	return { missionId = ledger.missionId, seq = ledger.seq, count = #copy, events = copy }
end

function RewardLedgerService.count(): number
	return #ledger.events
end

-- ---------------------------------------------------------------------------
-- §28/§31 per-player extraction status and reward locking. One row per participant per mission;
-- the lock timestamp is the authoritative moment their reward eligibility froze.
-- ---------------------------------------------------------------------------
local playerStatus: { [number]: { status: string, lockedAt: number?, extractedAt: number? } } = {}

function RewardLedgerService.markParticipant(userId: number)
	if not playerStatus[userId] then
		playerStatus[userId] = { status = "participating" }
	end
end

-- An individually extracted player locks NOW: nothing the remaining squad earns later belongs
-- to them, and nothing they already earned is retroactively invalidated (§31).
function RewardLedgerService.lockPlayer(userId: number, status: string)
	playerStatus[userId] = playerStatus[userId] or {}
	playerStatus[userId].status = status
	playerStatus[userId].lockedAt = os.clock()
	if status == "extracted" then
		playerStatus[userId].extractedAt = os.clock()
	end
	workspace:SetAttribute("GF_LedgerLocked", string.format("%d:%s", userId, status))
end

function RewardLedgerService.statusFor(userId: number): string
	local row = playerStatus[userId]
	return row and row.status or "unknown"
end

function RewardLedgerService.isLocked(userId: number): boolean
	local row = playerStatus[userId]
	return row ~= nil and row.lockedAt ~= nil
end

function RewardLedgerService.reset()
	ledger.missionId = nil
	ledger.seq = 0
	ledger.events = {}
	ledger.claimed = {}
	table.clear(playerStatus)
	publish()
end

return RewardLedgerService

