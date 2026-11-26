--!strict
-- PlayerController: the single authoritative client movement + orientation runtime.
-- Spec: GALACTIC FORCE movement/locomotion refinement. Design contract:
--  * one input sampler, one movement state machine, one per-frame writer of humanoid:Move
--  * native humanoid physics does the moving — this module never teleports or owns velocity
--  * input response is immediate; acceleration adds subtle weight, never input delay
--  * frame-rate-independent smoothing everywhere: alpha = 1 - exp(-dt/tau)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.GF.Shared.Constants)
local Input = require(script.Parent.Input)

local M = Constants.Movement

local player = Players.LocalPlayer
local remotes = ReplicatedStorage.GF.Remotes

local PlayerController = {}

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------
export type MoveState = "Grounded" | "Airborne" | "Rolling" | "Vaulting" | "Climbing" | "Downed"

local state = {
	base = "Grounded" :: MoveState,
	sprinting = false,
	aiming = false,
	firing = false,
	downed = false,
	rolling = false,
	rollUntil = 0,
	vaulting = false,
	vaultUntil = 0,
	interacting = false,
	uiOpen = false,
	cinematic = false,
}

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local character: Model? = nil

-- input accumulators (written by input listeners, sampled once per frame)
local padMove = Vector2.zero
local padLook = Vector2.zero
local touchMove = Vector2.zero
local lookDelta = Vector2.zero -- mouse, consumed per frame (no dt scaling)

-- orientation state
local bodyYaw = 0 -- current smoothed body yaw
local cameraYaw = 0 -- owned by CameraController but mirrored here for movement basis

-- acceleration ramp: integrates toward input magnitude; direction changes keep the ramp
local speedRamp = 0

-- sprint hysteresis
local sprintLatched = false

-- external camera-yaw provider: CameraController registers itself here
local cameraYawProvider: (() -> number)? = nil
function PlayerController.setCameraYawProvider(fn: () -> number)
	cameraYawProvider = fn
end

function PlayerController.getState()
	return state
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function dampenAlpha(dt: number, tau: number): number
	return 1 - math.exp(-dt / math.max(tau, 1e-4))
end

local function shortestAngleDelta(from: number, to: number): number
	local d = (to - from) % (math.pi * 2)
	if d > math.pi then
		d -= math.pi * 2
	elseif d < -math.pi then
		d += math.pi * 2
	end
	return d
end

local function camYaw(): number
	if cameraYawProvider then
		return cameraYawProvider()
	end
	local cam = workspace.CurrentCamera
	if cam then
		local look = cam.CFrame.LookVector
		return math.atan2(-look.X, -look.Z)
	end
	return 0
end

local function flatForward(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

local function flatRight(yaw: number): Vector3
	return Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
end

local function keyboardMove(): Vector2
	local v = Vector2.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		v += Vector2.new(0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		v += Vector2.new(0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		v += Vector2.new(-1, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		v += Vector2.new(1, 0)
	end
	return v
end

-- raw combined move input, diagonals normalized, analog magnitude preserved
local function moveInput(): Vector2
	local v = keyboardMove() + padMove + touchMove
	if v.Magnitude > 1 then
		v = v.Unit
	end
	return v
end

-- ---------------------------------------------------------------------------
-- character lifecycle
-- ---------------------------------------------------------------------------
local function bindCharacter(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	root = char:WaitForChild("HumanoidRootPart") :: BasePart
	-- orientation is owned ENTIRELY by updateOrientation below: engine AutoRotate would
	-- rotate toward MoveDirection every physics step and fight our writes (two competing
	-- orientation writers — engine physics-step vs render-step — reads as swimming/uncanny).
	(humanoid :: Humanoid).AutoRotate = false
	state.base = "Grounded"
	state.rolling = false
	state.vaulting = false
	state.downed = false
	speedRamp = 0
	sprintLatched = false
	-- jump tuning: JumpPower is server-owned; nothing client-side to do here, but the
	-- humanoid seeding above must re-happen per respawn (references go stale otherwise).
end

-- ---------------------------------------------------------------------------
-- sprint: automatic, hysteresis-latched, suppression-aware
-- ---------------------------------------------------------------------------
local function sprintSuppressed(): boolean
	return state.aiming
		or state.firing
		or state.downed
		or state.rolling
		or state.vaulting
		or state.base == "Rolling"
		or state.base == "Vaulting"
		or state.base == "Climbing"
		or state.uiOpen
		or state.cinematic
end

local function updateSprint(v: Vector2)
	local want = sprintLatched
	if sprintSuppressed() then
		want = false
		sprintLatched = false
	else
		if not sprintLatched then
			-- enter: strong forward-dominant input
			if v.Magnitude >= M.SprintEnterMagnitude then
				local dirDot = if v.Magnitude > 0.01 then (v.Y / v.Magnitude) else 0
				if dirDot >= M.SprintEnterDot then
					sprintLatched = true
					want = true
				end
			end
		else
			-- stay latched until input clearly weakens or leaves forward sector
			local dirDot = if v.Magnitude > 0.01 then (v.Y / v.Magnitude) else 0
			if v.Magnitude < M.SprintExitMagnitude or dirDot < M.SprintExitDot then
				sprintLatched = false
				want = false
			end
		end
	end
	if want ~= state.sprinting then
		state.sprinting = want
		remotes.SprintChanged:FireServer(want)
	end
end

-- ---------------------------------------------------------------------------
-- vault / climb detection (multi-probe, spec heights, landing validated)
-- ---------------------------------------------------------------------------
local function probeVault(): boolean
	if not humanoid or not root or not character then
		return false
	end
	local st = humanoid:GetState()
	if st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall then
		return false
	end
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < 0.3 then
		return false
	end
	local flat = Vector3.new(moveDir.X, 0, moveDir.Z).Unit
	local origin = root.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	-- forward obstruction at knee height
	local kneeHit = workspace:Raycast(origin - Vector3.new(0, 1.5, 0), flat * M.VaultForward, params)
	if not kneeHit then
		return false
	end
	-- measure obstacle height: probe down past the lip
	local lipOrigin = kneeHit.Position + flat * 1.5 + Vector3.new(0, M.ClimbMaxHeight + 1.2, 0)
	local lip = workspace:Raycast(lipOrigin, Vector3.new(0, -(M.ClimbMaxHeight + 2.5), 0), params)
	if not lip then
		return false
	end
	local footY = origin.Y - 3
	local height = lip.Position.Y - footY
	-- ceiling check above the lip: never vault into a solid cap
	local ceiling = workspace:Raycast(lip.Position + Vector3.new(0, 0.3, 0), Vector3.new(0, 3.2, 0), params)
	if ceiling then
		return false
	end
	-- landing beyond the lip must exist and be sane
	local landingOrigin = lip.Position + flat * 1.2 + Vector3.new(0, 0.6, 0)
	local landing = workspace:Raycast(landingOrigin, Vector3.new(0, -M.VaultLandingDepth, 0), params)
	if not landing then
		return false
	end
	-- landing slope sanity: reject excessively steep surfaces
	if landing.Normal.Y < 0.55 then
		return false
	end

	if height >= M.VaultMinHeight and height <= M.VaultMaxHeight then
		-- low vault: physics-assisted hop, momentum preserved
		state.vaulting = true
		state.vaultUntil = os.clock() + 0.42
		humanoid.Jump = true
		task.delay(0.07, function()
			if root and root.Parent then
				root.AssemblyLinearVelocity += flat * 12 + Vector3.new(0, 8.5, 0)
			end
		end)
		task.delay(0.42, function()
			state.vaulting = false
		end)
		return true
	elseif height > M.VaultMaxHeight and height <= M.ClimbMaxHeight then
		-- short ledge climb: stronger vertical assist, still physics-driven
		state.vaulting = true
		state.vaultUntil = os.clock() + 0.6
		humanoid.Jump = true
		task.delay(0.07, function()
			if root and root.Parent then
				root.AssemblyLinearVelocity += flat * 9 + Vector3.new(0, 14, 0)
			end
		end)
		task.delay(0.6, function()
			state.vaulting = false
		end)
		return true
	end
	return false
end

-- ---------------------------------------------------------------------------
-- input bindings
-- ---------------------------------------------------------------------------
local inputBound = false
local function bindInputs()
	if inputBound then
		return
	end
	inputBound = true

	Input.onPress("Jump", function()
		if not humanoid or state.downed or state.rolling then
			return
		end
		if humanoid:GetState() ~= Enum.HumanoidStateType.Jumping then
			if not probeVault() then
				humanoid.Jump = true
			end
		end
	end)

	Input.onPress("Dodge", function()
		if state.downed or state.rolling or state.vaulting or state.uiOpen then
			return
		end
		local v = moveInput()
		local yaw = camYaw()
		local dir
		if v.Magnitude > 0.1 then
			dir = flatRight(yaw) * v.X + flatForward(yaw) * v.Y
		else
			dir = flatForward(yaw)
		end
		if dir.Magnitude < 0.1 then
			dir = flatForward(yaw)
		end
		state.rolling = true -- client-side intent flag; server window is authoritative
		state.rollUntil = os.clock() + M.RollDuration
		task.delay(M.RollDuration + 0.05, function()
			state.rolling = false
		end)
		remotes.RequestDodge:FireServer({ direction = dir.Unit })
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			padMove = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
end

-- touch stick integration: TouchControls/Controller-owned stick writes here
function PlayerController.setTouchMove(v: Vector2)
	touchMove = v
end

-- ---------------------------------------------------------------------------
-- external state feeds (attributes the server/UI own)
-- ---------------------------------------------------------------------------
local function pollExternalState()
	state.aiming = Input.isHeld("Aim")
	state.firing = Input.isHeld("Fire")
	state.uiOpen = workspace:GetAttribute("GF_UIOpen") == true
	state.cinematic = workspace:GetAttribute("GF_PhotoCamActive") == true
	if character then
		-- server is authoritative for downed; replicated state reaches us through StatePublish attrs
		state.downed = character:GetAttribute("Downed") == true
	end
	-- rolling: server-published Rolling attribute corrects the client intent flag
	if character and state.rolling then
		if os.clock() > state.rollUntil and character:GetAttribute("Rolling") ~= true then
			state.rolling = false
		end
	end
end

-- ---------------------------------------------------------------------------
-- movement resolution — runs once per frame
-- ---------------------------------------------------------------------------
local function resolveBaseState()
	if state.downed then
		state.base = "Downed"
	elseif state.rolling then
		state.base = "Rolling"
	elseif state.vaulting then
		state.base = "Vaulting"
	elseif humanoid then
		local st = humanoid:GetState()
		if st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping then
			state.base = "Airborne"
		else
			state.base = "Grounded"
		end
	end
end

local rollActive = false

local function updateMovement(dt: number)
	if not humanoid or not root or not character then
		return
	end
	pollExternalState()
	resolveBaseState()

	-- during a roll the displacement steering owns humanoid:Move — input-driven
	-- movement must not overwrite it frame-after-frame
	if rollActive then
		return
	end
	local v = moveInput()
	updateSprint(v)

	-- movement suppression: menus/cinematics freeze locomotion but not the camera
	if state.uiOpen or state.cinematic then
		humanoid:Move(Vector3.zero, false)
		return
	end

	-- acceleration ramp: integrates toward input magnitude with asymmetric taus.
	-- direction reversals keep the ramp — braking is for stopping, not turning.
	local targetMag = v.Magnitude
	local tau = if targetMag > speedRamp then M.AccelTau else M.DecelTau
	speedRamp += (targetMag - speedRamp) * dampenAlpha(dt, tau)
	if speedRamp < 0.02 and targetMag == 0 then
		speedRamp = 0
	end

	-- world-space move direction from camera basis
	local yaw = camYaw()
	local dir = flatRight(yaw) * v.X + flatForward(yaw) * v.Y

	-- backward movement is slower while in combat posture: scale the backward component
	if state.aiming and v.Magnitude > 0.01 then
		local backwardness = math.clamp(-v.Y / v.Magnitude, 0, 1) -- 1 = straight backward
		local scale = 1 - backwardness * (1 - M.BackwardSpeed / M.AdsSpeed)
		dir *= scale
	end

	-- downed crawl: magnitude passes through, server caps speed at crawl; nothing else allowed
	if state.downed then
		humanoid:Move(dir.Magnitude > 0.01 and dir.Unit * math.min(dir.Magnitude, 1) * speedRamp or Vector3.zero, false)
		return
	end

	-- during roll, movement input is locked out — the server's constraint owns displacement.
	-- humanoid:Move is sticky, so it must be explicitly zeroed or the last input keeps driving.
	if state.rolling then
		humanoid:Move(Vector3.zero, false)
		return
	end

	if dir.Magnitude > 0.02 then
		local mag = math.min(dir.Magnitude, 1) * math.max(speedRamp, M.MinStartSpeed)
		humanoid:Move(dir.Unit * mag, false)
	else
		humanoid:Move(Vector3.zero, false)
	end
end

-- ---------------------------------------------------------------------------
-- orientation — smoothed shortest-path yaw, no snapping
-- ---------------------------------------------------------------------------
local rollVisualDirty = false

local function updateOrientation(dt: number)
	if not root or not humanoid then
		return
	end
	if state.vaulting or state.base == "Airborne" then
		-- vaulting/airborne: leave orientation to physics momentum
		return
	end
	if state.rolling then
		-- roll visual lives in GF_CharacterAnimator (owns the joint poses every heartbeat);
		-- orientation writes skip so displacement physics owns the root
		return
	end	local position = root.Position
	local currentCFrame = root.CFrame
	local look = currentCFrame.LookVector
	bodyYaw = math.atan2(-look.X, -look.Z)

	local targetYaw: number? = nil
	local turnTau = M.TurnTauLocomotion
	if state.aiming or state.firing then
		-- combat posture: converge on camera yaw
		targetYaw = camYaw()
		turnTau = M.TurnTauCombat
	else
		-- locomotion posture: face movement direction when actually moving
		local moveDir = humanoid.MoveDirection
		if moveDir.Magnitude > 0.15 and humanoid.WalkSpeed > 1 then
			targetYaw = math.atan2(-moveDir.X, -moveDir.Z)
		end
	end
	if targetYaw then
		local delta = shortestAngleDelta(bodyYaw, targetYaw)
		local step = delta * dampenAlpha(dt, turnTau)
		-- cap per-frame turn to avoid whip-fast spins on extreme deltas
		local maxStep = M.MaxTurnRate * dt
		step = math.clamp(step, -maxStep, maxStep)
		local newYaw = bodyYaw + step
		root.CFrame = CFrame.lookAt(position, position + flatForward(newYaw))
	end
end

-- ---------------------------------------------------------------------------
-- client-driven roll displacement: the player assembly is network-owned locally, so direct
-- velocity control is exact where server constraints lose ownership fights. Server remains
-- authoritative — it validates, consumes the charge, owns i-frames and publishes the roll
-- vector as attributes; this loop executes the physics it validated.
-- ---------------------------------------------------------------------------
local rollStart = 0
local rollDir = Vector3.zero
local rollProbeParams = RaycastParams.new()
rollProbeParams.FilterType = Enum.RaycastFilterType.Exclude
rollProbeParams.IgnoreWater = true

local function updateRollDisplacement(dt)
	-- engine-native roll displacement: the server grants a high WalkSpeed for the roll
	-- window; the client just steers with humanoid:Move. the engine owns acceleration,
	-- collision response, wall sliding and floor adhesion — zero solver fights.
	if not humanoid or not root or not character then
		return
	end
	local serverRolling = character:GetAttribute("Rolling") == true
	if serverRolling and not rollActive then
		rollActive = true
		rollStart = os.clock()
		rollDir = Vector3.new(
			character:GetAttribute("GFRollDirX") or 0,
			0,
			character:GetAttribute("GFRollDirZ") or 0
		)
		if rollDir.Magnitude < 0.1 then
			rollDir = flatForward(camYaw())
		end
		rollDir = rollDir.Unit
	end
	if not rollActive then
		return
	end
	if not serverRolling then
		rollActive = false
		return
	end
	if os.clock() - rollStart >= M.RollDuration then
		rollActive = false
		return
	end
	humanoid:Move(rollDir, false)
end

-- ---------------------------------------------------------------------------
-- main loop
-- ---------------------------------------------------------------------------
local started = false
function PlayerController.start()
	if started then
		return
	end
	started = true
	if player.Character then
		bindCharacter(player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)
	bindInputs()
	-- movement at input priority: after input sampling, before camera
	RunService:BindToRenderStep("GFMovement", Enum.RenderPriority.Input.Value + 1, function(dt)
		updateRollDisplacement(dt)
		updateMovement(dt)
		updateOrientation(dt)
	end)
end

return PlayerController
