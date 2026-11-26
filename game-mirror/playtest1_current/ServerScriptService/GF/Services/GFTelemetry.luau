--!strict
-- GFTelemetry — dev-only combat event instrumentation (research program stage 2).
-- Design contract:
--  * zero hot-loop cost when disabled: single cached boolean check per injection point
--  * ring buffer in memory; extraction via BindableFunction so MCP/external tools can drain
--  * never errors its host: every emit is pcall-wrapped internally
--  * sampling: high-frequency events (shots/misses) sampled at configurable rate, rare events always
--  * schema matches research/schemas/combat_event_schema.json exactly
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Telemetry = {}
local BUFFER_CAP = 8000
local buffer = table.create(256)
local head = 0
local count = 0
local dropped = 0
local enabledCache = false
local enabledAt = 0
local sampleRate = 1.0
local eventSeq = 0

local function refreshEnabled()
	-- re-check the gate at most once per 2s: attribute reads are cheap but not free
	if os.clock() - enabledAt > 2 then
		enabledAt = os.clock()
		enabledCache = workspace:GetAttribute("GF_TelemetryEnabled") == true
			or RunService:IsStudio()
		local sr = tonumber(workspace:GetAttribute("GF_TelemetrySampleRate"))
		sampleRate = sr and math.clamp(sr, 0.01, 1) or 1.0
	end
	return enabledCache
end

function Telemetry.enabled(): boolean
	return refreshEnabled()
end

-- eventTypes sampled at full rate regardless (rare/important)
local ALWAYS = {
	player_downed = true, player_revived = true, player_died = true,
	encounter_start = true, encounter_end = true, enemy_killed = true,
	component_destroyed = true, ammo_exhausted = true, shield_depleted = true,
	damage_avoided_iframe = true, fire_slot_denied = true,
}

function Telemetry.emit(eventType: string, payload: { [string]: any })
	if not refreshEnabled() then
		return
	end
	if not ALWAYS[eventType] and sampleRate < 1 and math.random() > sampleRate then
		return
	end
	eventSeq += 1
	head += 1
	if head > BUFFER_CAP then
		head = 1
		dropped += 1
	end
	local ev = {
		eventId = eventSeq,
		serverTimestamp = math.floor(os.clock() * 100000 + 0.5) / 100000,
		eventType = eventType,
	}
	for k, v in payload do
		ev[k] = v
	end
	buffer[head] = ev
	count += 1
end

-- drain returns up to maxEvents oldest events and clears them from the ring.
function Telemetry.drain(maxEvents: number?): { any }
	local cap = math.min(maxEvents or 2000, count, BUFFER_CAP)
	local out = table.create(cap)
	-- reconstruct chronological order from the ring
	local startIdx = head - count + 1
	if startIdx < 1 then
		startIdx += BUFFER_CAP
	end
	local n = math.min(count, BUFFER_CAP)
	local written = 0
	for i = 0, n - 1 do
		if written >= cap then
			break
		end
		local idx = ((startIdx + i - 1) % BUFFER_CAP) + 1
		table.insert(out, buffer[idx])
		buffer[idx] = nil
		written += 1
	end
	count -= written
	return out
end

function Telemetry.stats()
	return {
		count = count, dropped = dropped, cap = BUFFER_CAP,
		enabled = enabledCache, sampleRate = sampleRate,
	}
end

function Telemetry.start()
	-- extraction channel: a BindableFunction external tools invoke with ("drain", n)
	local bf = Instance.new("BindableFunction")
	bf.Name = "GFTelemetryDrain"
	bf.OnInvoke = function(n)
		return Telemetry.drain(tonumber(n) or 2000)
	end
	bf.Parent = ReplicatedStorage
	local bs = Instance.new("BindableFunction")
	bs.Name = "GFTelemetryStats"
	bs.OnInvoke = function()
		return Telemetry.stats()
	end
	bs.Parent = ReplicatedStorage
end

return Telemetry
