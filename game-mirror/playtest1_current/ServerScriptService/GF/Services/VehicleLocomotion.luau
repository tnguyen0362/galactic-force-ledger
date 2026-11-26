--!strict
-- VehicleLocomotion: hull movement controller for armored vehicles (spec sections 31/32/33/34).
-- NOT a humanoid walking controller — kinematic hull motion with mechanical weight:
-- bounded acceleration/braking, smooth hull rotation, terrain alignment from multi-point sampling,
-- slope limits, stuck detection/recovery. Turret articulation is separate (see articulateStep).
--
-- Cost model: one mover per vehicle, stepped from the owning controller's tick (10-20Hz tactical,
-- movement presentation integrated per-step). No per-frame global loops.

local Workspace = game:GetService("Workspace")

local VehicleLocomotion = {}

export type LocoConfig = {
	maxSpeed: number,
	accel: number,
	brake: number,
	hullOmegaMax: number, -- hull yaw rate cap rad/s
	tauSpeed: number?, -- speed convergence time constant
	maxSlopeDeg: number?, -- navigable slope limit
	groundClearance: number?, -- hull bottom offset above terrain
	footprintHalf: Vector3?, -- bounded footprint for clearance checks
	terrainAlign: boolean?,
}

export type LocoState = {
	cframe: CFrame,
	velocity: Vector3,
	speed: number,
	yaw: number,
	pitch: number,
	roll: number,
	stuckTime: number,
	lastProgress: Vector3,
	groundY: number,
}

function VehicleLocomotion.newState(startCFrame: CFrame): LocoState
	local _, yaw = startCFrame:ToEulerAnglesYXZ()
	return {
		cframe = startCFrame,
		velocity = Vector3.zero,
		speed = 0,
		yaw = yaw,
		pitch = 0,
		roll = 0,
		stuckTime = 0,
		lastProgress = startCFrame.Position,
		groundY = startCFrame.Position.Y,
	}
end

-- multi-sample terrain orientation (spec section 33): a small set of representative contact points,
-- smoothed — never align a large vehicle to individual voxel normals
local function sampleGround(pos: Vector3, halfX: number, halfZ: number, yaw: number, ignoreList: { Instance }): (number, Vector3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList
	local cosY, sinY = math.cos(yaw), math.sin(yaw)
	local offsets = {
		{ halfX * 0.7, halfZ * 0.7 }, { -halfX * 0.7, halfZ * 0.7 },
		{ halfX * 0.7, -halfZ * 0.7 }, { -halfX * 0.7, -halfZ * 0.7 },
		{ 0, 0 },
	}
	local totalY, count = 0, 0
	local normalSum = Vector3.zero
	for _, off in offsets do
		-- rotate footprint offsets into hull yaw frame
		local ox = off[1] * cosY - off[2] * sinY
		local oz = off[1] * sinY + off[2] * cosY
		local probePos = pos + Vector3.new(ox, 30, oz)
		local hit = Workspace:Raycast(probePos, Vector3.new(0, -160, 0), params)
		if hit then
			totalY += hit.Position.Y
			normalSum += hit.Normal
			count += 1
		end
	end
	if count == 0 then return pos.Y - 30, Vector3.yAxis end
	return totalY / count, (normalSum / count).Unit
end

-- speed convergence (spec section 31): v_next = v_d + (v_current - v_d)*exp(-dt/tau),
-- then bounded by separate accel/brake limits — no instant starts or stops
local function convergeSpeed(current: number, desired: number, accel: number, brake: number, tau: number, dt: number): number
	local target = desired + (current - desired) * math.exp(-dt / tau)
	local delta = target - current
	local limit = (math.abs(delta) > 0 and delta < 0) and brake or accel
	if delta < 0 then
		limit = brake
	else
		limit = accel
	end
	return current + math.clamp(delta, -limit * dt, limit * dt)
end

-- main mover step. Inputs: desired world-space direction (unit, planar) and desired speed fraction.
-- Returns updated state. The controller owns decision-making; this owns mechanical execution.
function VehicleLocomotion.step(state: LocoState, cfg: LocoConfig, desiredDir: Vector3?, desiredSpeedFrac: number, dt: number, ignoreList: { Instance }): LocoState
	local tau = cfg.tauSpeed or 0.9
	local desiredSpeed = (desiredDir ~= nil) and cfg.maxSpeed * math.clamp(desiredSpeedFrac, 0, 1) or 0
	-- hull yaw: bounded convergence toward desired direction of travel
	if desiredDir and desiredDir.Magnitude > 0.05 then
		local targetYaw = math.atan2(-desiredDir.X, -desiredDir.Z)
		local e = math.atan2(math.sin(targetYaw - state.yaw), math.cos(targetYaw - state.yaw))
		local maxTurn = (cfg.hullOmegaMax or math.rad(30)) * dt
		state.yaw += math.clamp(e * (1 - math.exp(-dt / 0.6)), -maxTurn, maxTurn)
		-- speed bleeds while turning hard — heavy vehicles don't pivot at full speed
		local turnDemand = math.abs(e) / math.pi
		desiredSpeed = desiredSpeed * (1 - turnDemand * 0.7)
	end
	state.speed = convergeSpeed(state.speed, desiredSpeed, cfg.accel, cfg.brake, tau, dt)
	-- planar movement in hull yaw direction
	local forward = Vector3.new(-math.sin(state.yaw), 0, -math.cos(state.yaw))
	local pos = state.cframe.Position
	local newPos = pos + forward * state.speed * dt
	-- terrain alignment: ground height + smoothed orientation
	local half = cfg.footprintHalf or Vector3.new(7, 4, 12)
	local groundY, normal = sampleGround(newPos, half.X, half.Z, state.yaw, ignoreList)
	-- slope feasibility (spec section 33): vehicles don't climb everything infantry can
	local slopeDeg = math.deg(math.acos(math.clamp(normal.Y, -1, 1)))
	local maxSlope = cfg.maxSlopeDeg or 30
	if slopeDeg > maxSlope and groundY > pos.Y + 1 then
		-- too steep to climb: kill forward progress, slide-stop
		newPos = pos
		state.speed = math.min(state.speed, 1)
	end
	local clearance = cfg.groundClearance or 4
	newPos = Vector3.new(newPos.X, groundY + clearance, newPos.Z)
	-- pitch/roll from smoothed terrain normal, damped hard
	if cfg.terrainAlign ~= false then
		local localN = CFrame.new(Vector3.zero, forward) -- orientation reference
		-- project normal into pitch/roll relative to hull yaw (simplified: pitch along forward)
		local fwdDot = normal:Dot(forward)
		local targetPitch = math.clamp(math.asin(math.clamp(-fwdDot, -0.6, 0.6)) * 0.8, -0.5, 0.5)
		state.pitch += (targetPitch - state.pitch) * (1 - math.exp(-dt / 0.5))
	end
	state.groundY = groundY
	state.cframe = CFrame.new(newPos) * CFrame.Angles(0, state.yaw, 0) * CFrame.Angles(state.pitch, 0, 0)
	-- stuck detection (spec section 34): inadequate progress while desiring movement
	if desiredSpeed > 1 then
		local progressed = (newPos - state.lastProgress).Magnitude
		if progressed < math.max(0.5, state.speed * dt * 0.3) then
			state.stuckTime += dt
		else
			state.stuckTime = 0
		end
	else
		state.stuckTime = 0
	end
	state.lastProgress = newPos
	return state
end

-- turret articulation (spec section 32): hull yaw and turret yaw are independent; the weapon
-- NEVER snaps. Returns new turret yaw relative to hull.
function VehicleLocomotion.articulateStep(turretYawRel: number, desiredWorldYaw: number, hullYaw: number, omegaMax: number, tauTurret: number, dt: number): number
	local targetRel = desiredWorldYaw - hullYaw
	local e = math.atan2(math.sin(targetRel - turretYawRel), math.cos(targetRel - turretYawRel))
	local delta = math.clamp(e * (1 - math.exp(-dt / tauTurret)), -omegaMax * dt, omegaMax * dt)
	return turretYawRel + delta
end

-- turning clearance reference (spec section 33): conservative planar rotational radius
function VehicleLocomotion.clearanceRadius(length: number, width: number): number
	return 0.5 * math.sqrt(length * length + width * width)
end

-- stuck recovery (spec section 34): bounded correction attempts, no teleporting.
-- Returns a corrected desired direction or nil if unrecoverable (controller should hold position).
function VehicleLocomotion.recoveryDirection(state: LocoState, originalDir: Vector3, attempt: number): Vector3?
	if attempt > 3 then return nil end
	-- bounded alternates: probe increasingly wide angles off the original direction
	local angle = math.rad(35 * attempt) * (attempt % 2 == 0 and 1 or -1)
	local cosA, sinA = math.cos(angle), math.sin(angle)
	return Vector3.new(
		originalDir.X * cosA - originalDir.Z * sinA,
		0,
		originalDir.X * sinA + originalDir.Z * cosA
	)
end

return VehicleLocomotion
