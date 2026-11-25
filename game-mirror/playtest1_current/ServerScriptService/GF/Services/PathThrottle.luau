--!strict
-- S06-017/018 pathfinding discipline: ComputeAsync is expensive, so requests only happen when the
-- destination moved more than 8 studs, the path is blocked, or the path is stale. A global token
-- bucket caps concurrent computes; between recomputes enemies steer locally around obstacles.
local PathfindingService = game:GetService("PathfindingService")

local PathThrottle = {}

local TOKEN_CAP = 4 -- max concurrent path computes across the whole enemy population
local REFILL_PER_SEC = 2
local tokens = TOKEN_CAP
local lastRefill = os.clock()

local STALE_AFTER = 3 -- seconds before a path is considered stale
local REDESTINATION_DELTA = 8 -- studs of target movement that force a recompute

type AgentPath = {
	waypoints: { Vector3 },
	destination: Vector3,
	computedAt: number,
	index: number,
}

local agentPaths: { [Model]: AgentPath } = {}

local function refillTokens()
	local now = os.clock()
	tokens = math.min(TOKEN_CAP, tokens + (now - lastRefill) * REFILL_PER_SEC)
	lastRefill = now
end

-- returns waypoints or nil when throttled; callers fall back to local steering toward the target
function PathThrottle.requestPath(agent: Model, from: Vector3, to: Vector3): { Vector3 }?
	refillTokens()
	local existing = agentPaths[agent]
	local needsCompute = true
	if existing then
		local destMoved = (existing.destination - to).Magnitude
		local stale = (os.clock() - existing.computedAt) > STALE_AFTER
		if destMoved <= REDESTINATION_DELTA and not stale then
			needsCompute = false
		end
	end
	if not needsCompute then
		return existing and existing.waypoints or nil
	end
	if tokens < 1 then
		return nil -- throttled: caller keeps last path or steers locally
	end
	tokens -= 1
	local root = agent.PrimaryPart
	if not root then return nil end
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
	})
	local ok, err = pcall(function()
		path:ComputeAsync(from, to)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local waypoints = {}
	for _, wp in ipairs(path:GetWaypoints()) do
		table.insert(waypoints, wp.Position)
	end
	agentPaths[agent] = {
		waypoints = waypoints,
		destination = to,
		computedAt = os.clock(),
		index = 1,
	}
	return waypoints
end

function PathThrottle.invalidate(agent: Model)
	agentPaths[agent] = nil
end

function PathThrottle.cleanup(agent: Model)
	agentPaths[agent] = nil
end

return PathThrottle
