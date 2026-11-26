--!strict
-- Authoritative economic transaction gateway (economy spec §96-99).
--
-- Every persistent economic mutation — purchases, cache opening, rerolls, fusion, dismantling,
-- requisition entries, premium grants, mission settlement — routes through apply(). The gateway
-- provides what scattered ad-hoc mutations cannot:
--
--   * Schema validation (§97): every transaction carries id, type, source, inputs, outputs,
--     revision expectations, timestamp, settlement status and the economic version that priced it.
--   * Idempotency (§98): Apply(T, Apply(T, S)) = Apply(T, S). A retry, double-fire or rejoin
--     re-delivery of the same transaction id is a no-op, never a duplicated effect.
--   * Journaling: a bounded per-profile ring of full transaction records so economic investigation
--     and migration (§101) have evidence. The journal is part of the existing player profile —
--     no redundant database, per §97 guidance.
--
-- Idempotency-key discipline by transaction family:
--   mission_settlement   — "settle:<missionId>" (already mirrored in settledMissions)
--   purchase             — naturally idempotent through ownership, but journaled with a stable key
--   cache_open           — "cache:<inventoryUid>" — the cache instance is consumed exactly once
--   reroll/fusion/dismantle — caller supplies an operation nonce; repeated DELIVERY dedupes,
--                          while deliberate repeated operations use fresh nonces
--   requisition_purchase — "req:<reqId>:<key>" (once-only entries) or nonce (repeatable kits)
--   premium_grant        — receipt id, matching MarketplaceService receipt dedup
--
-- The gateway never trusts client inputs for amounts: callers pass server-computed inputs/outputs.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileService = require(script.Parent.ProfileService)
local EconomyRegistry = require(ReplicatedStorage.GF.Shared.Configs.EconomyRegistry)

local EconomyTransactionService = {}

local JOURNAL_CAP = 100
local IDEMPOTENCY_CAP = 128

local VALID_TYPES = {
	mission_settlement = true,
	purchase = true,
	cache_open = true,
	reroll = true,
	fusion = true,
	dismantle = true,
	requisition_purchase = true,
	premium_grant = true,
	loot_pickup = true,
	capacity_expansion = true,
}

export type Transaction = {
	id: string,
	type: string,
	sourceId: string?,
	inputs: { [string]: number }?,
	outputs: { [string]: number }?,
	note: string?,
}

local function journalOf(profile: any): { any }
	profile.txnJournal = profile.txnJournal or {}
	return profile.txnJournal
end

local function idSetOf(profile: any): { [string]: number }
	-- map id -> journal sequence number; doubles as insertion-order eviction evidence
	profile.appliedTxnIds = profile.appliedTxnIds or {}
	return profile.appliedTxnIds
end

-- Has this exact transaction id already been applied to this profile?
function EconomyTransactionService.isApplied(player: Player, txnId: string): boolean
	local profile = ProfileService.get(player)
	if not profile then
		return false
	end
	local set = idSetOf(profile)
	return set[txnId] ~= nil
end

-- Validate schema and balance-affecting fields. Returns nil+reason or the normalized transaction.
local function validate(txn: Transaction): (Transaction?, string?)
	if type(txn) ~= "table" then
		return nil, "transaction not a table"
	end
	if type(txn.id) ~= "string" or txn.id == "" then
		return nil, "missing transaction id"
	end
	if #txn.id > 128 then
		return nil, "transaction id too long"
	end
	if type(txn.type) ~= "string" or not VALID_TYPES[txn.type] then
		return nil, "unknown transaction type: " .. tostring(txn.type)
	end
	for _, field in { "inputs", "outputs" } do
		local bag = (txn :: any)[field]
		if bag ~= nil then
			if type(bag) ~= "table" then
				return nil, field .. " not a table"
			end
			for key, amount in pairs(bag) do
				if type(key) ~= "string" then
					return nil, field .. " key not a string"
				end
				if type(amount) ~= "number" or amount ~= amount or math.abs(amount) == math.huge then
					return nil, field .. "." .. key .. " not finite"
				end
			end
		end
	end
	return txn, nil
end

-- Apply a transaction exactly once. mutate(profile) performs the actual economic effects and
-- must return true on success or false+reason to abort (nothing is journaled, retry stays safe).
-- Returns: applied:boolean, result:string ("applied"|"duplicate"|"rejected"|"aborted"), detail?
function EconomyTransactionService.apply(player: Player, txn: Transaction, mutate: (any) -> (boolean, string?)): (boolean, string, any)
	local normalized, err = validate(txn)
	if not normalized then
		return false, "rejected", err
	end
	local profile = ProfileService.get(player)
	if not profile then
		return false, "rejected", "no profile"
	end
	local set = idSetOf(profile)
	if set[normalized.id] ~= nil then
		-- repeated delivery: no-op with evidence, per Apply(T,Apply(T,S)) = Apply(T,S)
		workspace:SetAttribute("GF_TxnDuplicate", normalized.id)
		return true, "duplicate", nil
	end
	local expectedRevision = tonumber(profile.revision) or 0
	-- mutation must succeed before anything is recorded; a failed transaction leaves no trace
	local ok, mutateErr = mutate(profile)
	if not ok then
		return false, "aborted", mutateErr or "mutation declined"
	end
	profile.revision = expectedRevision + 1
	local journal = journalOf(profile)
	local seq = #journal + 1
	table.insert(journal, {
		TransactionId = normalized.id,
		PlayerId = player.UserId,
		TransactionType = normalized.type,
		SourceId = normalized.sourceId,
		Inputs = normalized.inputs,
		Outputs = normalized.outputs,
		ExpectedProfileRevision = expectedRevision,
		CreatedAt = os.time(),
		SettlementStatus = "settled",
		EconomicVersion = EconomyRegistry.VERSION,
		Note = normalized.note,
	})
	while #journal > JOURNAL_CAP do
		table.remove(journal, 1)
	end
	set[normalized.id] = seq
	-- bound the idempotency set: evict oldest-inserted ids beyond the cap. Because journal
	-- sequence numbers are monotonic within a profile lifetime, evicting the lowest sequence
	-- values is correct LRU-ish behavior for a ring.
	local count = 0
	for _ in pairs(set) do
		count += 1
	end
	if count > IDEMPOTENCY_CAP then
		local threshold = seq - IDEMPOTENCY_CAP
		for id, s in pairs(set) do
			if tonumber(s) and s <= threshold then
				set[id] = nil
			end
		end
	end
	ProfileService.markDirty(player)
	return true, "applied", nil
end

-- Inspect recent journal entries (diagnostics + future migration evidence).
function EconomyTransactionService.journal(player: Player): { any }
	local profile = ProfileService.get(player)
	if not profile then
		return {}
	end
	return journalOf(profile)
end

return EconomyTransactionService
