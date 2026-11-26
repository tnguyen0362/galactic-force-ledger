--!strict
-- NPCLocomotion: the authoritative movement executor for Ascendancy actors (spec section 11/12/15).
-- The tactical layer decides WHERE the NPC wants to go; this module decides HOW it gets there.
-- Enemies are kinematic CFrame-stepped models — no Humanoid physics — so this module implements
-- the movement mathematics explicitly: velocity convergence, bounded turning, braking-distance
-- arrival, look-ahead path following, surface-aligned slope movement, and neighbor separation.
--
-- Ownership contract: this is the ONLY writer of actor root CFrame during ordinary movement.
-- Tactical code never steps the root directly; it submits desired destinations/velocities here.

local RunService = game:GetService("RunService")

local NPCLocomotion = {}

-- ---------------------------------------------------------------------------
-- Archetype movement parameters (spec section 11 table, studs/sec).
-- walk = patrol/unaware, combat = engaged maneuvering, relocate = urgent repositioning.
-- tauAccel/tauDecel: velocity convergence time constants; omegaMax: turn rate cap rad/s;
-- tauTurn: turn damping time constant.
-- ---------------------------------------------------------------------------
export type LocomotionProfile = {
	walk: number,
	combat: number,
	relocate: number,
	tauAccel: number,
	tauDecel: number,
	omegaMax: number,
	tauTurn: number,
	maxSlopeDeg: number,
	radius: number, -- body radius for separation/clearance
}

local PROFILES: { [string]: LocomotionProfile } = {
	Rifleman = { walk = 8, combat = 11.5, relocate = 16, tauAccel = 0.22, tauDecel = 0.16, omegaMax = 4.2, tauTurn = 0.14, maxSlopeDeg = 45, radius = 1.6 },
	Vanguard = { walk = 9, combat = 15, relocate = 20, tauAccel = 0.18, tauDecel = 0.15, omegaMax = 5.0, tauTurn = 0.12, maxSlopeDeg = 48, radius = 1.6 },
	Heavy = { walk = 6, combat = 7.5, relocate = 11.5, tauAccel = 0.34, tauDecel = 0.24, omegaMax = 2.4, tauTurn = 0.22, maxSlopeDeg = 38, radius = 2.0 },
	Marksman = { walk = 7, combat = 9.5, relocate = 14.5, tauAccel = 0.24, tauDecel = 0.17, omegaMax = 3.8, tauTurn = 0.15, maxSlopeDeg = 42, radius = 1.6 },
	Commander = { walk = 8, combat = 10.5, relocate = 15.5, tauAccel = 0.22, tauDecel = 0.16, omegaMax = 4.0, tauTurn = 0.14, maxSlopeDeg = 45, radius = 1.7 },
	Default = { walk = 8, combat = 11, relocate = 15, tauAccel = 0.22, tauDecel = 0.16, omegaMax = 4.0, tauTurn = 0.14, maxSlopeDeg = 45, radius = 1.6 },
}

function NPCLocomotion.profileFor(archetype: string?): LocomotionProfile
	return PROFILES[archetype or ""] or PROFILES.Default
end

-- ---------------------------------------------------------------------------
-- Velocity convergence (spec section 11): exponential approach to desired velocity with
-- bounded acceleration. Separate accel/decel taus — soldiers start slower than they stop.
-- ---------------------------------------------------------------------------
function NPCLocomotion.convergeVelocity(current: Vector3, desired: Vector3, dt: number, tauAccel: number, tauDecel: number, maxAccel: number?): Vector3
	local tau = (desired.Magnitude >= current.Magnitude) and tauAccel or tauDecel
	local alpha = 1 - math.exp(-dt / math.max(tau, 1e-3))
	local next = current + (desired - current) * alpha
	if maxAccel then
		local dv = next - current
		local cap = maxAccel * dt
		if dv.Magnitude > cap then
			next = current + dv.Unit * cap
		end
	end
	return next
end

-- ---------------------------------------------------------------------------
-- Bounded damped turning (spec section 11): shortest-arc yaw error, damped approach,
-- hard rate cap. No more instantaneous 180-degree snaps.
-- Returns the new yaw given current yaw, desired yaw, dt, profile.
-- ---------------------------------------------------------------------------
function NPCLocomotion.turnYaw(currentYaw: number, desiredYaw: number, dt: number, tauTurn: number, omegaMax: number): number
	local e = math.atan2(math.sin(desiredYaw - currentYaw), math.cos(desiredYaw - currentYaw))
	local damped = e * (1 - math.exp(-dt / math.max(tauTurn, 1e-3)))
	local cap = omegaMax * dt
	local delta = math.clamp(damped, -cap, cap)
	return currentYaw + delta
end

function NPCLocomotion.yawOf(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z) -- CFrame.lookAt convention: -Z forward
end

-- ---------------------------------------------------------------------------
-- Braking-distance arrival (spec section 15): desired speed decreases so the NPC can stop
-- within the remaining distance rather than oscillating around the destination.
-- ---------------------------------------------------------------------------
function NPCLocomotion.arrivalSpeed(maxSpeed: number, decel: number, distance: number, stopRadius: number): number
	local remaining = math.max(0, distance - stopRadius)
	return math.min(maxSpeed, math.sqrt(2 * decel * remaining))
end

-- ---------------------------------------------------------------------------
-- Look-ahead distance for path following (spec section 15): speed-dependent, so fast
-- movement tracks further ahead on the path and slow turns stay tight.
-- ---------------------------------------------------------------------------
function NPCLocomotion.lookAhead(speed: number): number
	return math.clamp(3 + 0.6 * speed, 4, 14)
end

-- ---------------------------------------------------------------------------
-- Surface-aligned movement (spec section 13): project desired direction onto the ground
-- plane so slope traversal follows the terrain instead of pushing into it or floating.
-- ---------------------------------------------------------------------------
function NPCLocomotion.surfaceAlign(direction: Vector3, groundNormal: Vector3): Vector3
	local aligned = direction - (direction:Dot(groundNormal)) * groundNormal
	if aligned.Magnitude < 1e-4 then
		return direction * Vector3.new(1, 0, 1)
	end
	return aligned.Unit
end

function NPCLocomotion.slopeAngleDeg(normal: Vector3): number
	return math.deg(math.acos(math.clamp(normal:Dot(Vector3.yAxis), -1, 1)))
end

-- ---------------------------------------------------------------------------
-- Separation (spec section 16): bounded repulsion from nearby NPCs so soldiers keep
-- combat spacing without stacking, sliding sideways, or blocking doorways.
-- neighbors: array of {position, radius}; returns a velocity-space correction.
-- ---------------------------------------------------------------------------
function NPCLocomotion.separation(position: Vector3, neighbors: { { position: Vector3, radius: number } }, selfRadius: number, sepRadius: number, strength: number): Vector3
	local force = Vector3.zero
	for _, n in ipairs(neighbors) do
		local delta = position - n.position
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local r = flat.Magnitude
		local minDist = sepRadius + n.radius
		if r < minDist and r > 1e-3 then
			local w = (1 - r / minDist) ^ 2
			force += flat.Unit * w * strength
		elseif r <= 1e-3 then
			-- near-identical positions: deterministic jitter direction from position hash
			local h = (position.X * 37 + position.Z * 17) % 6.283
			force += Vector3.new(math.cos(h), 0, math.sin(h)) * strength * 0.5
		end
	end
	return force
end

-- ---------------------------------------------------------------------------
-- EXECUTOR: per-actor locomotion state. One entry per enemy, owned by the tactical layer
-- but stepped only here. Fields:
--   velocity: current world velocity (converged, never teleported)
--   yaw: current facing (bounded turning)
--   path: optional waypoint array + progress index
--   mode: "idle" | "direct" | "path" — direct = straight-to-destination, path = waypoints
--   speed: target speed class ("walk"|"combat"|"relocate" or explicit number)
--   desiredDir/desiredPos: current movement intent from the tactical layer
-- ---------------------------------------------------------------------------
export type LocomotionState = {
	velocity: Vector3,
	yaw: number,
	path: { Vector3 }?,
	pathIndex: number,
	mode: string,
	destination: Vector3?,
	stopRadius: number,
	speedClass: string,
	arrived: boolean,
	stuckTime: number,
	lastProgress: number,
	lastPosition: Vector3?,
	strafeBias: number, -- -1..1 lateral movement bias during combat orientation separation
	aimYaw: number?, -- combat upper-body aim direction when different from movement facing
	groundY: number?, -- cached terrain height at last probe position
	groundNormal: Vector3?, -- cached terrain normal
	groundProbePos: Vector3?, -- where the cache was sampled
	groundProbeAt: number, -- when the cache was sampled
}

function NPCLocomotion.newState(position: Vector3, yaw: number?): LocomotionState
	return {
		velocity = Vector3.zero,
		yaw = yaw or 0,
		path = nil,
		pathIndex = 1,
		mode = "idle",
		destination = nil,
		stopRadius = 2,
		speedClass = "walk",
		arrived = true,
		stuckTime = 0,
		lastProgress = math.huge,
		lastPosition = nil,
		strafeBias = 0,
		aimYaw = nil,
		groundY = nil,
		groundNormal = nil,
		groundProbePos = nil,
		groundProbeAt = 0,
	}
end

-- submit a direct-move intent: go to position, stop within stopRadius
function NPCLocomotion.moveTo(state: LocomotionState, destination: Vector3, speedClass: string?, stopRadius: number?)
	state.destination = destination
	state.mode = "direct"
	state.speedClass = speedClass or state.speedClass
	state.stopRadius = stopRadius or 2
	state.arrived = false
	state.path = nil
end

-- submit a path-following intent: waypoints array, stop within stopRadius of the final point
function NPCLocomotion.followPath(state: LocomotionState, waypoints: { Vector3 }, speedClass: string?, stopRadius: number?)
	state.path = waypoints
	state.pathIndex = 1
	state.mode = "path"
	state.speedClass = speedClass or state.speedClass
	state.stopRadius = stopRadius or 2
	state.arrived = false
	state.destination = waypoints[#waypoints]
end

function NPCLocomotion.stop(state: LocomotionState)
	state.mode = "idle"
	state.destination = nil
	state.path = nil
	state.arrived = true
end

-- ground probe: raycast down from above the position, returns ground y + normal or nil
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true
local function probeGround(position: Vector3, ignore: { Instance }): (number?, Vector3?)
	groundParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), groundParams)
	if hit then
		return hit.Position.Y, hit.Normal
	end
	return nil, nil
end

-- cached variant: terrain is static within a step, so re-probing every frame wastes raycasts.
-- reuse the sample while the actor has moved < 2.5 planar studs and the sample is < 0.4s old.
local function probeGroundCached(state: any, position: Vector3, ignore: { Instance }): (number?, Vector3?)
	local now = os.clock()
	local pp = state.groundProbePos
	if pp and state.groundY then
		local dx = position.X - pp.X
		local dz = position.Z - pp.Z
		if dx * dx + dz * dz < 6.25 and now - state.groundProbeAt < 0.4 then
			-- plane-corrected height: project the XZ drift onto the cached normal plane
			local n = state.groundNormal or Vector3.yAxis
			local dy = 0
			if math.abs(n.Y) > 1e-3 then
				dy = -(dx * n.X + dz * n.Z) / n.Y
			end
			return (state.groundY :: number) + dy, state.groundNormal
		end
	end
	local gy, gn = probeGround(position, ignore)
	if gy then
		state.groundY = gy
		state.groundNormal = gn
		state.groundProbePos = position
		state.groundProbeAt = now
	end
	return gy, gn
end

-- the step: advance one actor by dt. Owns root CFrame entirely.
-- neighbors: separation inputs from the tactical layer's spatial query (may be empty).
-- ignoreList: instances the ground/wall probes must ignore (the enemy model itself).
-- Returns whether the actor is effectively stuck (for tactical recovery decisions).
function NPCLocomotion.step(
	state: LocomotionState,
	profile: LocomotionProfile,
	root: BasePart,
	dt: number,
	neighbors: { { position: Vector3, radius: number } },
	ignoreList: { Instance },
	bodyHeight: number?
): boolean
	local position = root.Position
	local height = bodyHeight or 3.1 -- ground-to-root vertical offset (spawn plane convention)
	local maxSpeed = profile[state.speedClass] or profile.combat
	-- resolve desired direction + arrival-managed speed
	local desiredDir: Vector3? = nil
	local targetSpeed = 0
	if state.mode == "path" and state.path then
		-- advance path index past reached/behind waypoints using look-ahead
		local lookDist = NPCLocomotion.lookAhead(state.velocity.Magnitude)
		while state.pathIndex < #state.path do
			local wp = state.path[state.pathIndex]
			local d = (Vector3.new(wp.X, position.Y, wp.Z) - position).Magnitude
			if d < math.max(lookDist * 0.6, 2) then
				state.pathIndex += 1
			else
				break
			end
		end
		local targetWp = state.path[math.min(state.pathIndex, #state.path)]
		local finalWp = state.path[#state.path]
		local toFinal = (Vector3.new(finalWp.X, position.Y, finalWp.Z) - position)
		if state.pathIndex >= #state.path and toFinal.Magnitude <= state.stopRadius then
			state.arrived = true
			state.mode = "idle"
		else
			local flatTarget = Vector3.new(targetWp.X, position.Y, targetWp.Z)
			local toTarget = flatTarget - position
			if toTarget.Magnitude > 0.05 then
				desiredDir = toTarget.Unit
				targetSpeed = NPCLocomotion.arrivalSpeed(maxSpeed, 30, toFinal.Magnitude, state.stopRadius)
			end
		end
	elseif state.mode == "direct" and state.destination then
		local dest = state.destination
		local flat = Vector3.new(dest.X - position.X, 0, dest.Z - position.Z)
		local d = flat.Magnitude
		if d <= state.stopRadius then
			state.arrived = true
			state.mode = "idle"
		else
			desiredDir = flat.Unit
			targetSpeed = NPCLocomotion.arrivalSpeed(maxSpeed, 30, d, state.stopRadius)
		end
	end
	-- separation blends into the movement command (spec section 16)
	local desired = Vector3.zero
	if desiredDir then
		desired = desiredDir * targetSpeed
		if #neighbors > 0 then
			local sep = NPCLocomotion.separation(position, neighbors, profile.radius, 2.2, maxSpeed * 0.5)
			desired = desired + sep
			local cap = math.max(maxSpeed * 1.15, targetSpeed)
			if desired.Magnitude > cap then
				desired = desired.Unit * cap
			end
		end
	end
	-- velocity convergence (bounded)
	state.velocity = NPCLocomotion.convergeVelocity(state.velocity, desired, dt, profile.tauAccel, profile.tauDecel, 55)
	-- ground probe ahead of the velocity direction for slope alignment + contact
	local stepVec = state.velocity * dt
	local newX, newZ = position.X + stepVec.X, position.Z + stepVec.Z
	local groundY, normal = probeGroundCached(state, Vector3.new(newX, position.Y, newZ), ignoreList)
	local newY
	if groundY then
		-- slope feasibility: refuse movement up slopes beyond the archetype limit (spec section 13)
		local slope = NPCLocomotion.slopeAngleDeg(normal or Vector3.yAxis)
		local climbing = (groundY - position.Y) / math.max(0.5, math.sqrt(stepVec.X ^ 2 + stepVec.Z ^ 2) + 0.01)
		if slope > profile.maxSlopeDeg and climbing > 0.3 and state.velocity.Magnitude > 1 then
			-- too steep: deflect along the contour instead of climbing
			stepVec = Vector3.new(stepVec.Z, 0, -stepVec.X) * 0.6
			newX, newZ = position.X + stepVec.X, position.Z + stepVec.Z
			groundY, normal = probeGroundCached(state, Vector3.new(newX, position.Y, newZ), ignoreList)
		end
		newY = (groundY or position.Y) + height
		-- drop protection: never step into a fall deeper than ~6 studs unless intentional
		if position.Y - newY > 7 and state.velocity.Magnitude > 0.5 then
			stepVec = stepVec * 0.25
			newX, newZ = position.X + stepVec.X, position.Z + stepVec.Z
			local g2 = probeGroundCached(state, Vector3.new(newX, position.Y, newZ), ignoreList)
			if g2 then
				newY = g2 + height
			else
				newX, newZ = position.X, position.Z
				newY = position.Y
			end
		end
	else
		newY = position.Y + stepVec.Y -- no ground info: keep current height
	end
	-- turning: desired yaw comes from movement direction during traversal, or aimYaw in combat
	local moveYaw = state.velocity.Magnitude > 0.5 and NPCLocomotion.yawOf(state.velocity) or state.yaw
	local desiredYaw = state.aimYaw or moveYaw
	state.yaw = NPCLocomotion.turnYaw(state.yaw, desiredYaw, dt, profile.tauTurn, profile.omegaMax)
	-- commit: orientation from yaw, position from stepped velocity — one writer, no snaps
	local newPos = Vector3.new(newX, newY, newZ)
	root.CFrame = CFrame.new(newPos) * CFrame.Angles(0, state.yaw, 0)
	-- stuck detection: significant desired movement but no actual progress
	local stuck = false
	if desired.Magnitude > maxSpeed * 0.3 and state.lastPosition then
		local progress = (position - state.lastPosition).Magnitude / math.max(dt, 1e-3)
		if progress < maxSpeed * 0.12 then
			state.stuckTime += dt
		else
			state.stuckTime = 0
		end
		stuck = state.stuckTime > 1.2
	else
		state.stuckTime = 0
	end
	state.lastPosition = position
	return stuck
end

return NPCLocomotion
