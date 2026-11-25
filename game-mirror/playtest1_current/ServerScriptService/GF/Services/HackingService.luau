--!nonstrict
-- Server-authoritative hacking. The client draws a needle and reports a press; the hit test, the
-- arc, the stage count and the difficulty timing all live here. The angle is derived from the
-- server's own clock (workspace:GetServerTimeNow), so a client cannot claim a window it did not
-- press in, and latency alignment uses the same synchronised clock on both sides.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local State = require(script.Parent.State)

local HackingService = {}
local ARC = { Easy = 110, Normal = 95, Hard = 85, Extreme = 75 }
local PERIOD = { Easy = 1.6, Normal = 1.3, Hard = 1.05, Extreme = 0.85 }
local ALLOWANCE = 7
local active = {}
local nextId = 0

HackingService.onComplete = nil
HackingService.onCancel = nil

-- A challenge is abandoned when the player leaves the console, goes down, or disconnects. Without this
-- the overlay outlived the situation that created it and the console stayed locked.
local function watch(player: Player, state)
	task.spawn(function()
		while active[player] == state do
			task.wait(0.4)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local status = State.get(player)
			local reason = nil
			if not player.Parent or not root then
				reason = "disconnect"
			elseif status and status.downed then
				reason = "downed"
			elseif state.anchor and (root.Position - state.anchor).Magnitude > 26 then
				reason = "range"
			end
			if reason then
				HackingService.cancel(player, reason)
				break
			end
		end
	end)
end

local function remote(name)
	return ReplicatedStorage.GF.Remotes:FindFirstChild(name)
end

local function publish(player, state)
	local r = remote("HackState")
	if not r then
		return
	end
	if not state then
		r:FireClient(player, { active = false })
		return
	end
	r:FireClient(player, {
		active = true,
		id = state.id,
		period = state.period,
		arcStart = state.arcStart,
		arcWidth = state.arcWidth,
		stage = state.stage,
		startedAt = state.startedAt,
	})
end

function HackingService.begin(player: Player, difficulty: string?, anchor: Vector3?)
	nextId += 1
	local key = difficulty or "Normal"
	local state = {
		id = nextId,
		stage = 0,
		misses = 0,
		period = PERIOD[key] or PERIOD.Normal,
		arcWidth = ARC[key] or ARC.Normal,
		arcStart = math.random(0, 359),
		startedAt = workspace:GetServerTimeNow(),
		lastAttempt = 0,
		anchor = anchor,
	}
	active[player] = state
	workspace:SetAttribute("GF_HackStage", 0)
	workspace:SetAttribute("GF_HackHits", 0)
	workspace:SetAttribute("GF_HackMisses", 0)
	publish(player, state)
	watch(player, state)
	return state.id
end

function HackingService.cancel(player: Player, reason: string?)
	local state = active[player]
	if not state then
		return false
	end
	active[player] = nil
	workspace:SetAttribute("GF_HackStage", 0)
	workspace:SetAttribute("GF_HackCancelled", reason or "cancelled")
	publish(player, nil)
	if HackingService.onCancel then
		HackingService.onCancel(player, reason or "cancelled", state.id)
	end
	return true
end

function HackingService.attempt(player: Player, id: number?)
	local state = active[player]
	if not state then
		return false, "no-challenge"
	end
	if id ~= nil and id ~= state.id then
		return false, "stale-challenge"
	end
	local now = workspace:GetServerTimeNow()
	if now - state.lastAttempt < state.period * 0.35 then
		return false, "too-soon"
	end
	state.lastAttempt = now
	local angle = ((now - state.startedAt) / state.period * 360) % 360
	local delta = math.abs((angle - state.arcStart + 180) % 360 - 180)
	local hit = delta <= state.arcWidth / 2 + ALLOWANCE
	if hit then
		state.stage += 1
		workspace:SetAttribute("GF_HackHits", state.stage)
	else
		-- Spec: a miss loses one stage with a floor of zero, not a floor of one.
		state.stage = math.max(0, state.stage - 1)
		state.misses += 1
		workspace:SetAttribute("GF_HackMisses", state.misses)
	end
	workspace:SetAttribute("GF_LastHackDelta", math.floor(delta))
	workspace:SetAttribute("GF_LastHackHit", hit)
	if state.stage >= 3 then
		active[player] = nil
		workspace:SetAttribute("GF_HackStage", 0)
		workspace:SetAttribute("GF_HackComplete", (workspace:GetAttribute("GF_HackComplete") or 0) + 1)
		publish(player, nil)
		if HackingService.onComplete then
			HackingService.onComplete(player, state.id)
		end
		return true, "complete"
	end
	workspace:SetAttribute("GF_HackStage", state.stage)
	publish(player, state)
	return true, hit and "hit" or "miss"
end

function HackingService.start()
	local r = remote("HackAttempt")
	if r then
		r.OnServerEvent:Connect(function(player, id)
			if not require(script.Parent.NetGuard).allow(player, "interact") then
				return
			end
			HackingService.attempt(player, tonumber(id))
		end)
	end
end

return HackingService

