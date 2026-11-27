--!strict
-- CameraController: the single authority over the gameplay camera.
-- One write point per frame. Modes blend continuously; rotation input is applied raw
-- (no input-side smoothing); only position/offset/FOV parameters are damped.
-- Feel layers (shake/bob/recoil/landing) are additive post-passes that never accumulate.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.GF.Shared.Constants)
local Input = require(script.Parent:WaitForChild("Input"))

local M = Constants.Movement
local CAM = Constants.Camera

local player = Players.LocalPlayer

local CameraController = {}

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------
local yaw = 0
local pitch = math.rad(-8)
local initialized = false

-- instrumentation capture state (bounded ring buffer, dev-only)
local inputEventCount = 0 -- per-frame event counter (reset each consume)
local lastMouseEventTime = 0
local rawAccumulatedMag = 0
local frameRawMouse = Vector2.zero
local frameLogicalYaw, frameLogicalPitch = 0, 0
local captureRing = {}
local captureIdx = 0
local CAPTURE_MAX = 600

-- continuous mode blends (0..1), each with its own transition tau pair
local blends = {
	aim = 0,
	sprint = 0,
	dodge = 0,
	downed = 0,
}

-- occlusion state: current additional inward compression beyond the preset distance
local occlusionDistance = 0 -- studs pulled inward right now
local occluded = false

-- feel state
local trauma = 0
local recoilPitch = 0 -- additive decaying camera kick (climb)
local recoilYaw = 0
local bobPhase = 0
local bobAmplitude = 0
local landingDip = 0
local noiseSeed = math.random() * 1000

-- external requests: cinematic/photo ownership mirrors existing attribute contract
local externallyOwned = false

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local character: Model? = nil

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function dampenAlpha(dt: number, tau: number): number
	return 1 - math.exp(-dt / math.max(tau, 1e-4))
end

local function shakeEnabled(): boolean
	if player:GetAttribute("GF_Setting_CameraShake") == false then
		return false
	end
	if player:GetAttribute("GF_Setting_ReducedMotion") == true then
		return false
	end
	return true
end

function CameraController.shake(intensity: number)
	trauma = math.min(1, trauma + math.max(0, tonumber(intensity) or 0))
end

function CameraController.shakeAt(intensity: number, position: Vector3?, fullRange: number?)
	if typeof(position) ~= "Vector3" then
		CameraController.shake(intensity)
		return
	end
	if not root then
		return
	end
	local dist = (root.Position - position).Magnitude
	local range = tonumber(fullRange) or 60
	if dist < range then
		CameraController.shake(intensity * (1 - dist / range))
	end
end

-- recoil impulse: climb = camera kick, drift handled by weapon layer separately.
-- recovery is passive decay — it never fights active player correction because the
-- impulse is additive on top of raw input rather than a spring back to a fixed point.
function CameraController.recoil(vertical: number, horizontal: number)
	recoilPitch += vertical
	recoilYaw += horizontal
end

function CameraController.land(severity: number)
	landingDip = math.min(landingDip + severity, 1)
end

function CameraController.getYawPitch(): (number, number)
	return yaw, pitch
end

-- ---------------------------------------------------------------------------
-- dev-only frame capture (bounded ring, aggregated on demand — never console spam)
-- ---------------------------------------------------------------------------
local function captureFrame(dt, pivot, resolvedPos, desiredPos, fov)
	captureIdx += 1
	local cam = workspace.CurrentCamera
	-- only record input-active frames (plus the frame right after motion stops) —
	-- idle frames are provably static (zeroInputMotion=0) and would flood the ring
	local activeInput = frameRawMouse.Magnitude > 0.01
	if not activeInput then
		-- idle frame: leave the ring untouched so active frames survive indefinitely
		frameLogicalYaw, frameLogicalPitch = yaw, pitch
		return
	end
	captureRing[captureIdx % CAPTURE_MAX + 1] = {
		f = captureIdx, t = os.clock(), dt = dt,
		events = inputEventCount,
		rawMag = frameRawMouse.Magnitude,
		rawX = frameRawMouse.X, rawY = frameRawMouse.Y,
		yaw = frameLogicalYaw, pitch = frameLogicalPitch,
		rootPos = root and root.Position or Vector3.zero,
		pivot = pivot, resolved = resolvedPos, desired = desiredPos, fov = fov,
		camPos = cam and cam.CFrame.Position or Vector3.zero,
	}
	inputEventCount = 0
end

local function aggregateCapture(): string
	local n = math.min(captureIdx, CAPTURE_MAX)
	if n < 10 then
		return "insufficient capture"
	end
	local parts = {}
	local first = captureIdx - math.min(n, 240) + 1
	for i = first, captureIdx do
		local r = captureRing[i % CAPTURE_MAX + 1]
		if r then
			parts[#parts+1] = string.format("%d|%.1f|%.1f|%.4f|%.4f",
				r.f, r.rawX or 0, r.rawY or 0, r.yaw or 0, r.pitch or 0)
		end
	end
	return table.concat(parts, ";")
end

workspace:GetAttributeChangedSignal("GF_CamDumpNow"):Connect(function()
	if workspace:GetAttribute("GF_CamDumpNow") == true then
		workspace:SetAttribute("GF_CamDumpNow", false)
		workspace:SetAttribute("GF_CamCapture", aggregateCapture())
	end
end)

-- ---------------------------------------------------------------------------
-- input
-- ---------------------------------------------------------------------------
local padLook = Vector2.zero
local touchLook = Vector2.zero
local mouseDelta = Vector2.zero -- accumulated between frames, consumed raw
-- input method: "delta" = GetMouseDelta sampled once per frame (default),
-- "events" = InputChanged accumulation. Mutually exclusive, attribute-switched for A/B validation.
local function inputMethod(): string
	local m = workspace:GetAttribute("GF_CamInputMethod")
	return if m == "events" then "events" else "delta"
end

local function diagMode(): boolean
	return workspace:GetAttribute("GF_CameraDiag") == true
end

local function clearPendingInput()
	mouseDelta = Vector2.zero
	padLook = Vector2.zero
	touchLook = Vector2.zero
end

-- input hygiene: stale input never survives focus loss, menu open, or device silence
UserInputService.WindowFocusReleased:Connect(clearPendingInput)
workspace:GetAttributeChangedSignal("GF_UIOpen"):Connect(function()
	if workspace:GetAttribute("GF_UIOpen") == true then
		clearPendingInput()
	end
end)

local function radialDeadzone(stick: Vector2, deadzone: number, gamma: number): Vector2
	local mag = stick.Magnitude
	if mag < deadzone or mag < 1e-4 then
		return Vector2.zero
	end
	local adjusted = math.clamp((mag - deadzone) / (1 - deadzone), 0, 1)
	return (stick / mag) * adjusted ^ gamma
end

-- logical look orientation: updated EXACTLY ONCE per frame, here and nowhere else.
-- Runs at Input priority (before movement) so movement uses current-frame logical direction.
-- hoisted above first use: reads before these declarations previously resolved to nil globals
local aimAssistActive = false
local assistFrictionActive = false

local function consumeInput(dt: number)
	local sensitivity
	if diagMode() then
		sensitivity = 1 -- diagnostic: user multiplier excluded by design
	else
		sensitivity = tonumber(player:GetAttribute("GF_Setting_AimSensitivity")) or 1
	end
	local aimScale = blends.aim > 0.5 and M.AimSensitivityScale or 1
	local invert = player:GetAttribute("GF_Setting_InvertY") == true and -1 or 1
	local baseSens = diagMode() and (tonumber(workspace:GetAttribute("GF_CamDiagSens")) or 0.0018) or CAM.MouseSensitivity

	-- mouse displacement: one method or the other, never both
	local rawMouse = Vector2.zero
	if inputMethod() == "delta" then
		rawMouse = UserInputService:GetMouseDelta()
		mouseDelta = Vector2.zero -- drain any stray events so methods never combine
	else
		rawMouse = mouseDelta
		mouseDelta = Vector2.zero
	end
	frameRawMouse = rawMouse -- instrumentation

	local dYaw = -rawMouse.X * baseSens * sensitivity * aimScale
	local dPitch = -rawMouse.Y * baseSens * sensitivity * invert * aimScale

	-- device arbitration: gamepad/touch contribute only when the mouse has been silent —
	-- stale cross-device input never leaks into the active device's frame
	local mouseActive = os.clock() - lastMouseEventTime < 1.0
	if not mouseActive then
		local stick = radialDeadzone(padLook, CAM.StickDeadzone, CAM.StickGamma)
		if stick.Magnitude > 0 then
			local rate = CAM.StickLookSpeed * sensitivity * aimScale
			dYaw -= stick.X * rate * dt
			dPitch -= stick.Y * rate * dt * invert
		end
		if touchLook.Magnitude > 0 then
			dYaw -= touchLook.X * CAM.TouchSensitivity * sensitivity * aimScale
			dPitch -= touchLook.Y * CAM.TouchSensitivity * sensitivity * invert * aimScale
			touchLook = Vector2.zero
		end
	else
		touchLook = Vector2.zero
	end

	if assistFrictionActive then
		dYaw *= CAM.AimAssistFriction
		dPitch *= CAM.AimAssistFriction
	end

	-- exactly-once logical update: zero displacement means zero change, by construction
	if dYaw ~= 0 or dPitch ~= 0 then
		yaw = (yaw + dYaw) % (math.pi * 2)
		pitch = math.clamp(pitch + dPitch, CAM.PitchMin, CAM.PitchMax)
	end
	frameLogicalYaw, frameLogicalPitch = yaw, pitch -- instrumentation export point
end

function CameraController.feedTouchLook(delta: Vector2)
	touchLook += delta
end

-- ---------------------------------------------------------------------------
-- aim assist (gamepad/touch only): input-layer friction + gentle attraction.
-- implemented here — inside the authority — rather than as a competing camera writer.
-- never active on mouse; respects visibility, cone, range, and active player input.
-- ---------------------------------------------------------------------------
local aimAssistParams: RaycastParams? = nil
local function assistedTargetPoint(camPos: Vector3, look: Vector3): Vector3?
	if not character then
		return nil
	end
	local folder = workspace:FindFirstChild("ActiveActors")
	if not folder then
		return nil
	end
	if not aimAssistParams then
		aimAssistParams = RaycastParams.new()
		aimAssistParams.FilterType = Enum.RaycastFilterType.Exclude
		aimAssistParams.IgnoreWater = true
	end
	local best: Vector3? = nil
	local bestAngle = math.rad(CAM.AimAssistConeDegrees)
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("GFEnemy") and not model:GetAttribute("Dead") then
			local targetRoot = model.PrimaryPart
			if targetRoot then
				local toTarget = targetRoot.Position - camPos
				local dist = toTarget.Magnitude
				if dist <= CAM.AimAssistRange and dist > 1 then
					local angle = math.acos(math.clamp(look:Dot(toTarget.Unit), -1, 1))
					if angle < bestAngle then
						aimAssistParams.FilterDescendantsInstances = { character, model }
						local hit = workspace:Raycast(camPos, toTarget, aimAssistParams)
						if not hit then
							bestAngle = angle
							best = targetRoot.Position
						end
					end
				end
			end
		end
	end
	return best
end

aimAssistActive = false
assistFrictionActive = false
local function applyAimAssist(dt: number)
	-- platform gate: mouse never receives assistance
	local gamepad = UserInputService.GamepadEnabled and not UserInputService.MouseEnabled
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	aimAssistActive = (gamepad or touch) and Input.isHeld("Aim")
	if not aimAssistActive then
		assistFrictionActive = false
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local look = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0).LookVector
	local target = assistedTargetPoint(camPos, look)
	if not target then
		assistFrictionActive = false
		return
	end
	assistFrictionActive = true
	-- attraction: small additional rotation toward the target, frame-rate independent
	local toTarget = (target - camPos).Unit
	local desiredYaw = math.atan2(-toTarget.X, -toTarget.Z)
	local desiredPitch = math.asin(math.clamp(toTarget.Y, -1, 1))
	local function angleDelta(a: number, b: number): number
		local d = (b - a) % (math.pi * 2)
		if d > math.pi then
			d -= math.pi * 2
		elseif d < -math.pi then
			d += math.pi * 2
		end
		return d
	end
	local strength = 1 - math.exp(-dt / CAM.AimAssistTau)
	yaw += angleDelta(yaw, desiredYaw) * strength * CAM.AimAssistStrength
	pitch += math.clamp((desiredPitch - pitch) * strength * CAM.AimAssistStrength, -0.02, 0.02)
end

-- ---------------------------------------------------------------------------
-- presets + blending
-- ---------------------------------------------------------------------------
local function presetFor(): { dist: number, right: number, height: number, fov: number }
	-- base = exploration
	local p = {
		dist = CAM.Explore.Distance,
		right = CAM.Explore.RightOffset,
		height = CAM.Explore.PivotHeight,
		fov = CAM.Explore.FOV,
	}
	-- order matters: each active mode lerps the accumulated preset toward its own
	local function apply(b: number, target: any)
		if b <= 0 then
			return
		end
		p.dist += (target.Distance - p.dist) * b
		p.right += (target.RightOffset - p.right) * b
		p.height += (target.PivotHeight - p.height) * b
		p.fov += (target.FOV - p.fov) * b
	end
	apply(blends.sprint, CAM.Sprint)
	apply(blends.dodge, CAM.Dodge)
	-- per-weapon ADS zoom: the weapon layer publishes GF_AdsZoom (config adsZoom — 1.3 shotgun
	-- through 3.4 marksman). FOV scales inversely: 70/zoom. Missing attribute reproduces the
	-- legacy fixed-58 behavior exactly, so nothing shifts for unweaponed states.
	local zoom = tonumber(game:GetService("Players").LocalPlayer:GetAttribute("GF_AdsZoom")) or 0
	if zoom > 0.5 then
		local aimTarget = { Distance = CAM.Aim.Distance, RightOffset = CAM.Aim.RightOffset, PivotHeight = CAM.Aim.PivotHeight, FOV = math.clamp(CAM.Explore.FOV / zoom, 20, 70) }
		apply(blends.aim, aimTarget)
	else
		apply(blends.aim, CAM.Aim) -- aim last: strongest visual priority
	end
	apply(blends.downed, CAM.Downed) -- downed overrides all when active
	return p
end

-- ---------------------------------------------------------------------------
-- occlusion: spherecast pivot->desired, asymmetric recovery
-- ---------------------------------------------------------------------------
local occlusionParams: RaycastParams? = nil
local function resolveOcclusion(pivot: Vector3, desired: Vector3, dt: number): Vector3
	if not character then
		return desired
	end
	if not occlusionParams then
		occlusionParams = RaycastParams.new()
		occlusionParams.FilterType = Enum.RaycastFilterType.Exclude
		occlusionParams.IgnoreWater = true
	end
	occlusionParams.FilterDescendantsInstances = { character }

	local offset = desired - pivot
	local dist = offset.Magnitude
	if dist < 0.1 then
		return desired
	end
	local dir = offset / dist

	-- shapecast a small sphere so corners don't slip through a hairline ray
	local result = workspace:Spherecast(pivot, CAM.OcclusionRadius, offset, occlusionParams)
	local clearDist = dist
	if result then
		clearDist = math.max(result.Distance - CAM.OcclusionMargin, CAM.OcclusionMinDistance)
	end

	local targetCompression = dist - clearDist
	if targetCompression > occlusionDistance then
		-- inward correction: fast, nearly immediate — never let the camera sit inside a wall
		occlusionDistance += (targetCompression - occlusionDistance) * dampenAlpha(dt, CAM.OcclusionInTau)
	else
		-- outward restoration: slow, kills corner oscillation
		occlusionDistance += (targetCompression - occlusionDistance) * dampenAlpha(dt, CAM.OcclusionOutTau)
	end
	occluded = occlusionDistance > 0.15
	local finalDist = dist - occlusionDistance
	return pivot + dir * math.max(finalDist, CAM.OcclusionMinDistance)
end

-- ---------------------------------------------------------------------------
-- character lifecycle
-- ---------------------------------------------------------------------------
local function bindCharacter(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	root = char:WaitForChild("HumanoidRootPart") :: BasePart
	occlusionDistance = 0
	occlusionParams = nil
	-- seed yaw behind the character so respawn doesn't whip the camera around
	local look = (root :: BasePart).CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.rad(-8)
	-- landing response: brief severity-proportional dip
	local hum = humanoid :: Humanoid
	hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed then
			local vy = math.abs((root :: BasePart).AssemblyLinearVelocity.Y)
			local severity = math.clamp((vy - 20) / 70, 0, 0.6)
			if severity > 0.02 then
				CameraController.land(severity)
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- mode resolution — blends driven by live gameplay state each frame
-- ---------------------------------------------------------------------------
local moveStateProvider: (() -> any)? = nil
function CameraController.setMoveStateProvider(fn: () -> any)
	moveStateProvider = fn
end

local function updateBlends(dt: number)
	local aiming = Input.isHeld("Aim")
	local sprinting, rolling, downed = false, false, false
	if moveStateProvider then
		local s = moveStateProvider()
		if s then
			sprinting = s.sprinting == true
			rolling = s.rolling == true
			downed = s.downed == true
		end
	end
	-- per-transition taus: fast into aim, slightly slower out (spec timing table)
	local aimTau = if aiming then CAM.TauEnterAim else CAM.TauExitAim
	local sprintTau = if sprinting then CAM.TauEnterSprint else CAM.TauExitSprint
	blends.aim += ((aiming and 1 or 0) - blends.aim) * dampenAlpha(dt, aimTau)
	blends.sprint += ((sprinting and 1 or 0) - blends.sprint) * dampenAlpha(dt, sprintTau)
	blends.dodge += ((rolling and 1 or 0) - blends.dodge) * dampenAlpha(dt, CAM.TauDodge)
	blends.downed += ((downed and 1 or 0) - blends.downed) * dampenAlpha(dt, CAM.TauDowned)
end

-- ---------------------------------------------------------------------------
-- external ownership (photo cam / cinematics): honor the existing attribute contract
-- ---------------------------------------------------------------------------
local function externalOverride(cam: Camera): boolean
	local camPos = workspace:GetAttribute("GF_CamPos")
	local camLook = workspace:GetAttribute("GF_CamLook")
	local photoPos = workspace:GetAttribute("GF_PhotoCam")
	local photoLook = workspace:GetAttribute("GF_PhotoCamLook")
	if typeof(camPos) ~= "Vector3" and typeof(photoPos) == "Vector3" then
		camPos = photoPos
	end
	if typeof(camLook) ~= "Vector3" and typeof(photoLook) == "Vector3" then
		camLook = photoLook
	end
	if typeof(camPos) == "Vector3" and typeof(camLook) == "Vector3" then
		cam.CFrame = CFrame.lookAt(camPos, camLook)
		if workspace:GetAttribute("GF_PhotoCamActive") ~= true then
			workspace:SetAttribute("GF_PhotoCamActive", true)
		end
		externallyOwned = true
		return true
	end
	if externallyOwned then
		externallyOwned = false
		workspace:SetAttribute("GF_PhotoCamActive", false)
	end
	return false
end

-- ---------------------------------------------------------------------------
-- the single write point
-- ---------------------------------------------------------------------------
local function updateCamera(dt: number)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	if externalOverride(cam) then
		return
	end
	if not root or not humanoid or not character then
		return
	end

	-- rotation: raw input, applied immediately — zero input-side smoothing.
	-- while aim assist has a target, stick input is damped (friction half of the spec)
	-- logical orientation was already updated exactly once at Input priority (consumeInput).
	-- this render pass only presents it. aim assist is a gamepad/touch feature and is fully
	-- gated off for mouse users inside applyAimAssist itself.
	applyAimAssist(dt)

	if diagMode() then
		-- DIAGNOSTIC BASELINE: constant framing, no occlusion, no blends, no feel layers,
		-- no dynamic FOV. raw logical orientation + fixed explore offset, nothing else.
		local rot0 = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
		local pivot0 = root.Position + Vector3.new(0, CAM.Explore.PivotHeight, 0)
		local pos0 = pivot0 - rot0.LookVector * CAM.Explore.Distance + rot0.RightVector * CAM.Explore.RightOffset
		cam.CFrame = CFrame.new(pos0) * rot0
		cam.FieldOfView = 70
		captureFrame(dt, pivot0, pos0, pos0, 70)
		return
	end

	updateBlends(dt)
	local preset = presetFor()

	local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local pivot = root.Position + Vector3.new(0, preset.height, 0)
	local shoulderOffset = rot.RightVector * preset.right
	local desired = pivot - rot.LookVector * preset.dist + shoulderOffset

	-- lateral shoulder clearance: keep the offset shoulder out of walls too
	local finalPos = resolveOcclusion(pivot, desired, dt)

	-- compose base transform
	local finalCFrame = CFrame.new(finalPos) * rot

	-- ---- additive feel layers (post-pass, never accumulate into yaw/pitch) ----
	-- bob: subtle, speed-scaled, sprint-weighted; disabled with reduced motion
	local bobOffset = CFrame.new()
	if humanoid and humanoid.MoveDirection.Magnitude > 0.1 and humanoid.FloorMaterial ~= Enum.Material.Air then
		local speed = (humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed)
		bobPhase += dt * math.clamp(speed / 6, 4, 11)
		local targetAmp = CAM.BobAmplitude * (0.4 + 0.6 * blends.sprint)
		bobAmplitude += (targetAmp - bobAmplitude) * dampenAlpha(dt, 0.15)
		if shakeEnabled() then
			local bx = math.sin(bobPhase) * bobAmplitude
			local by = math.abs(math.cos(bobPhase)) * bobAmplitude * 0.7
			bobOffset = CFrame.new(bx, -by, 0)
		end
	else
		bobAmplitude += (0 - bobAmplitude) * dampenAlpha(dt, 0.2)
	end

	-- recoil climb: additive decaying kick, separate from raw input
	local recoilOffset = CFrame.new()
	if math.abs(recoilPitch) > 1e-4 or math.abs(recoilYaw) > 1e-4 then
		recoilOffset = CFrame.Angles(recoilPitch, recoilYaw, 0)
		local decay = dampenAlpha(dt, CAM.RecoilRecoveryTau)
		recoilPitch += (0 - recoilPitch) * decay
		recoilYaw += (0 - recoilYaw) * decay
	end

	-- landing dip: quick in, soft out
	local landOffset = CFrame.new()
	if landingDip > 1e-3 then
		landOffset = CFrame.Angles(landingDip * CAM.LandingDipAngle, 0, 0)
		landingDip += (0 - landingDip) * dampenAlpha(dt, CAM.LandingRecoveryTau)
	end

	-- trauma shake: rotational noise, amplitude = trauma², honors settings
	local shakeOffset = CFrame.new()
	if trauma > 0 then
		trauma = math.max(0, trauma - dt * 1.6)
		if shakeEnabled() then
			local amp = trauma * trauma * CAM.ShakeAmplitude
			local t = os.clock() * 34 + noiseSeed
			shakeOffset = CFrame.Angles(math.noise(t, 0) * amp, math.noise(0, t) * amp, 0)
		end
	end

	cam.CFrame = finalCFrame * recoilOffset * landOffset * shakeOffset * bobOffset
	cam.FieldOfView = preset.fov
	captureFrame(dt, pivot, finalPos, desired, preset.fov)
end

-- ---------------------------------------------------------------------------
-- input listeners
-- ---------------------------------------------------------------------------
local inputBound = false
local function bindInputs()
	if inputBound then
		return
	end
	inputBound = true
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			-- a visible cursor is menu input, not camera input
			if UserInputService.MouseBehavior == Enum.MouseBehavior.Default then
				return
			end
			local delta = Vector2.new(input.Delta.X, input.Delta.Y)
			-- raw linear ingestion: NO compression, NO rejection (per controlled-investigation
			-- directive — nonlinear per-event processing violates input additivity). Stats only.
			inputEventCount += 1
			lastMouseEventTime = os.clock()
			local mag = delta.Magnitude
			rawAccumulatedMag += mag
			if mag > (workspace:GetAttribute("GF_CamDbg_MaxDelta") or 0) then
				workspace:SetAttribute("GF_CamDbg_MaxDelta", mag)
			end
			mouseDelta += delta
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			padLook = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- start
-- ---------------------------------------------------------------------------
local started = false
function CameraController.start()
	if started then
		return
	end
	started = true
	if player.Character then
		bindCharacter(player.Character)
	end
	player.CharacterAdded:Connect(function(char)
		clearPendingInput()
		bindCharacter(char)
	end)
	bindInputs()
	-- logical input consumption BEFORE movement (movement reads current-frame logical look),
	-- camera presentation after everything. Two ordered steps, one logical update.
	RunService:BindToRenderStep("GFCameraInput", Enum.RenderPriority.Input.Value, consumeInput)
	RunService:BindToRenderStep("GFCamera", Enum.RenderPriority.Camera.Value + 1, updateCamera)
end

return CameraController
