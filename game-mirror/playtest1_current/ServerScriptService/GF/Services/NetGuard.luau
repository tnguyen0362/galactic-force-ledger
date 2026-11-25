--!strict
-- NetGuard: centralized network input defense (GOAL_2026-11-24.md L224).
-- Server-only. Three jobs:
--   1. Per-action token buckets per player (fire capped outer 20/s, interaction 5/s, purchases 2/s,
--      equip 4/s, queue 1/s). Throttled requests are dropped before any expensive work runs.
--   2. Payload validators: finite numbers/vectors (NaN and infinity never pass), bounded string ids,
--      shallow table shape. A Vector3 passes typeof() even with NaN components, and NaN comparisons
--      are false, so range checks alone cannot catch it - these validators can.
--   3. Aggregate rejection logging: counts per action/reason published on workspace.GFDebug so tests
--      read real state, plus throttled warns so an attacker cannot flood the console either.
local Players = game:GetService("Players")

local NetGuard = {}

-- Rates in tokens per second; capacity equals rate (one second of burst). The fire cap is an OUTER
-- bound only: CombatService still enforces the per-weapon RPM interval with latency slack inside.
local RATES: { [string]: number } = {
	fire = 20,
	interact = 5,
	purchase = 2,
	equip = 4,
	queue = 1,
	stance = 20,
	ability = 5,
	reload = 6,
	throw = 6,
	read = 10,
	default = 10,
}

local buckets: { [Player]: { [string]: { tokens: number, at: number } } } = {}
local throttleCounts: { [string]: number } = {}
local rejectReasons: { [string]: number } = {}
local lastWarnAt = 0

local function debugFolder(): Instance?
	return workspace:FindFirstChild("GFDebug")
end

local function publish(key: string, value: any)
	local dbg = debugFolder()
	if dbg then
		dbg:SetAttribute(key, value)
	end
	workspace:SetAttribute("GF_NetGuard_" .. key, value)
end

local function rateFor(action: string): number
	return RATES[action] or RATES.default
end

-- Token bucket: consume `cost` tokens if available. Returns true when the request may proceed.
function NetGuard.allow(player: Player, action: string, cost: number?): boolean
	local rate = rateFor(action)
	local spend = tonumber(cost) or 1
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[action]
	if not bucket then
		bucket = { tokens = rate, at = now }
		perPlayer[action] = bucket
	end
	local elapsed = math.max(0, now - bucket.at)
	bucket.tokens = math.min(rate, bucket.tokens + elapsed * rate)
	bucket.at = now
	if bucket.tokens >= spend then
		bucket.tokens -= spend
		return true
	end
	throttleCounts[action] = (throttleCounts[action] or 0) + 1
	publish("Throttled_" .. action, throttleCounts[action])
	publish("LastThrottle", string.format("%s:%s:%d", player and player.Name or "?", action, math.floor(now)))
	-- Console flooding is itself an abuse vector: aggregate warns at most once per 5 seconds.
	if now - lastWarnAt >= 5 then
		lastWarnAt = now
		warn(string.format("[GF] NetGuard throttling %s on %s (+%d dropped)", action, player and player.Name or "?", throttleCounts[action] or 0))
	end
	return false
end

-- Aggregate rejection reasons, keyed "action:reason". Tests read these instead of parsing console text.
-- Roblox attribute NAMES reject colons, so the published key strips everything outside [%w-_];
-- the readable form survives in the LastReject VALUE and in the in-module table keys.
local function attributeSafe(key: string): string
	return (string.gsub(key, "[^%w%-_]", "_"))
end
function NetGuard.noteReject(action: string, reason: string)
	local key = action .. ":" .. reason
	rejectReasons[key] = (rejectReasons[key] or 0) + 1
	publish("Reject_" .. attributeSafe(key), rejectReasons[key])
	publish("LastReject", key)
end

function NetGuard.throttleCount(action: string): number
	return throttleCounts[action] or 0
end

function NetGuard.rejectCount(action: string, reason: string): number
	return rejectReasons[action .. ":" .. reason] or 0
end

-- Validators. Each returns true only for values that are the right type AND finite AND in range.

function NetGuard.finiteNumber(v: any, minV: number?, maxV: number?): boolean
	if type(v) ~= "number" then
		return false
	end
	if v ~= v or v == math.huge or v == -math.huge then
		return false
	end
	if minV ~= nil and v < minV then
		return false
	end
	if maxV ~= nil and v > maxV then
		return false
	end
	return true
end

-- typeof() accepts NaN-bearing vectors, and NaN magnitude comparisons are false, so this must
-- inspect the components directly.
function NetGuard.finiteVector3(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	return NetGuard.finiteNumber(v.X) and NetGuard.finiteNumber(v.Y) and NetGuard.finiteNumber(v.Z)
end

function NetGuard.stringId(v: any, maxLen: number?): boolean
	if type(v) ~= "string" then
		return false
	end
	local cap = maxLen or 64
	if #v < 1 or #v > cap then
		return false
	end
	-- Control characters have no legitimate use in ids and corrupt logs/attributes.
	if string.find(v, "[%c]") then
		return false
	end
	return true
end

-- Payload root shape: a table with a bounded number of top-level keys. Deep inspection is the
-- handler's job; this stops the cheap amplification attacks before any work happens.
function NetGuard.shallowTable(v: any, maxKeys: number?): boolean
	if type(v) ~= "table" then
		return false
	end
	local cap = maxKeys or 32
	local count = 0
	for _ in v do
		count += 1
		if count > cap then
			return false
		end
	end
	return true
end

-- Byte-size estimate for a serialized payload, used by the coarse MaxRemoteBytesPerSecond budget.
local function estimateBytes(v: any, depth: number?): number
	local d = depth or 0
	if d > 4 then
		return 16
	end
	local t = type(v)
	if t == "string" then
		return #v
	elseif t == "number" or t == "boolean" then
		return 8
	elseif t == "Vector3" or t == "Vector2" then
		return 24
	elseif t == "table" then
		local total = 8
		for key, value in v do
			total += estimateBytes(key, d + 1) + estimateBytes(value, d + 1)
			if total > 65536 then
				return total
			end
		end
		return total
	end
	return 16
end
NetGuard.estimateBytes = estimateBytes

-- Combined entry check for high-value handlers: bucket cost scaled by payload size so a single
-- oversized payload costs more budget. Returns true when the request may proceed.
function NetGuard.allowPayload(player: Player, action: string, payload: any): boolean
	local bytes = estimateBytes(payload)
	if bytes > 8192 then
		NetGuard.noteReject(action, "oversized:" .. tostring(bytes))
		throttleCounts[action] = (throttleCounts[action] or 0) + 1
		publish("Throttled_" .. action, throttleCounts[action])
		return false
	end
	-- One token per 1024 bytes minimum 1: ordinary payloads cost 1, padded payloads burn budget.
	local cost = math.max(1, math.ceil(bytes / 1024))
	return NetGuard.allow(player, action, cost)
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

-- Test/reset support for deterministic probes. Not a gameplay path.
function NetGuard.reset(player: Player?)
	if player then
		buckets[player] = nil
	else
		table.clear(buckets)
	end
end

return NetGuard
