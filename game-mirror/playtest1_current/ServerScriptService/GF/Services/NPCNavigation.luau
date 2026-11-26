--!strict
-- NPCNavigation: the tactical-path layer between intent and locomotion (spec sections 8/14/41).
-- Tactical code asks "how do I get to X"; this module answers with cached waypoints when valid
-- or queues an asynchronous compute. ComputeAsync yields, so computes NEVER run inside decision
-- ticks or the locomotion loop — they run in dedicated spawned threads bounded by a global budget.
--
-- Budget discipline (spec section 41): concurrent computes capped, per-agent recompute cooldown,
-- cache reuse while the destination hasn't moved meaningfully and the path isn't stale. When the
-- budget denies a request the caller steers directly — never block a soldier on pathing latency.
--
-- Scope note: this is the LOCAL tactical tier (a few hundred studs). The strategic regional tier
-- for battlefield-scale travel arrives with Stage 8's regional graph; ComputeAsync cannot span
-- a 5000-stud battlefield in one request and is never asked to.

local PathfindingService = game:GetService("PathfindingService")

local NPCNavigation = {}

local MAX_CONCURRENT = 2 -- hard cap on simultaneous ComputeAsync threads
local PER_AGENT_COOLDOWN = 1.2 -- seconds between computes for the same agent
local STALE_AFTER = 4 -- seconds before a cached path is recomputed even if the destination held
local REDESTINATION_DELTA = 10 -- studs of destination movement that force a recompute
local MAX_PATH_DISTANCE = 400 -- beyond this the local tier refuses; caller uses direct steering
local QUEUE_MAX = 24 -- pending request cap; overflow drops lowest priority

type AgentPath = {
	waypoints: { Vector3 },
	destination: Vector3,
	computedAt: number,
	blocked: boolean,
}

local agentPaths: { [Model]: AgentPath } = {}
local lastCompute: { [Model]: number } = {}
local inFlight: { [Model]: boolean } = {}
local activeComputes = 0

type NavRequest = {
	agent: Model,
	from: Vector3,
	to: Vector3,
	priority: number,
	queuedAt: number,
}
local queue: { NavRequest } = {}

local function waypointList(from: Vector3, to: Vector3): { Vector3 }?
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentCanClimb = true,
	})
	local ok = pcall(function()
		path:ComputeAsync(from, to)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local waypoints = {}
	for _, wp in ipairs(path:GetWaypoints()) do
		table.insert(waypoints, wp.Position)
	end
	if #waypoints == 0 then
		return nil
	end
	return waypoints
end

-- worker: drains the priority queue whenever compute capacity is free. Runs as its own thread
-- started lazily on the first request; yields are contained here, never in game loops.
local workerRunning = false
local function worker()
	if workerRunning then
		return
	end
	workerRunning = true
	task.spawn(function()
		while true do
			if #queue == 0 or activeComputes >= MAX_CONCURRENT then
				task.wait(0.15)
				continue
			end
			-- highest priority first; ties broken by age (older first)
			table.sort(queue, function(a, b)
				if a.priority ~= b.priority then
					return a.priority > b.priority
				end
				return a.queuedAt < b.queuedAt
			end)
			local req = table.remove(queue, 1)
			local agent = req.agent
			if not agent.Parent or inFlight[agent] then
				continue
			end
			inFlight[agent] = true
			activeComputes += 1
			task.spawn(function()
				local wps = waypointList(req.from, req.to)
				if wps then
					agentPaths[agent] = {
						waypoints = wps,
						destination = req.to,
						computedAt = os.clock(),
						blocked = false,
					}
				else
					-- remember the failure briefly so we don't hot-loop computes against an
					-- unreachable target; direct steering continues in the meantime
					agentPaths[agent] = {
						waypoints = {},
						destination = req.to,
						computedAt = os.clock(),
						blocked = true,
					}
				end
				lastCompute[agent] = os.clock()
				inFlight[agent] = nil
				activeComputes -= 1
			end)
		end
	end)
end

-- the one question tactical code asks: "what waypoints get me toward `to`?" Returns cached
-- waypoints when valid, nil otherwise — and queues a compute when the cache misses so the
-- answer exists on a later tick. Never yields.
function NPCNavigation.waypointsFor(agent: Model, from: Vector3, to: Vector3, priority: number?): { Vector3 }?
	local dist = (to - from).Magnitude
	if dist > MAX_PATH_DISTANCE then
		return nil -- outside the local tier: direct steering (strategic tier arrives in Stage 8)
	end
	local existing = agentPaths[agent]
	if existing and not existing.blocked and #existing.waypoints > 0 then
		local destMoved = (existing.destination - to).Magnitude
		local stale = (os.clock() - existing.computedAt) > STALE_AFTER
		if destMoved <= REDESTINATION_DELTA and not stale then
			return existing.waypoints
		end
	end
	-- cache miss: queue a compute if the agent is compute-eligible
	if not inFlight[agent] then
		local lastT = lastCompute[agent] or 0
		if os.clock() - lastT >= PER_AGENT_COOLDOWN then
			if #queue < QUEUE_MAX then
				table.insert(queue, {
					agent = agent,
					from = from,
					to = to,
					priority = priority or 1,
					queuedAt = os.clock(),
				})
				worker()
			end
		end
	end
	return nil
end

-- a path exists and is fresh enough to use right now, without triggering any queue work
function NPCNavigation.cached(agent: Model): { Vector3 }?
	local existing = agentPaths[agent]
	if existing and not existing.blocked and #existing.waypoints > 0 then
		if (os.clock() - existing.computedAt) <= STALE_AFTER then
			return existing.waypoints
		end
	end
	return nil
end

function NPCNavigation.invalidate(agent: Model)
	agentPaths[agent] = nil
end

function NPCNavigation.cleanup(agent: Model)
	agentPaths[agent] = nil
	lastCompute[agent] = nil
	inFlight[agent] = nil
end

-- test instrumentation
function NPCNavigation.stats(): (number, number, number)
	return #queue, activeComputes, QUEUE_MAX
end

return NPCNavigation
