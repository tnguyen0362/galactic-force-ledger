--!strict
-- GF_CharacterAnimator: server-side procedural locomotion for the authored R15 rig.
-- Runs per character so limb motion replicates to every client (no animation assets needed).

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local character = script.Parent :: Model
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
if humanoid.HipHeight < 0.5 then
	local feetY, rootY = math.huge, 0
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			local bottom = d.Position.Y - d.Size.Y * 0.5
			if d.Name:find("Foot") then feetY = math.min(feetY, bottom) end
			if d.Name == "HumanoidRootPart" then rootY = d.Position.Y - d.Size.Y * 0.5 end
		end
	end
	if feetY == math.huge then feetY = 0 end
	humanoid.HipHeight = math.max(1.5, rootY - feetY)
	print(string.format("[GF] animator: hip height corrected to %.2f", humanoid.HipHeight))
end

local root = character:WaitForChild("HumanoidRootPart") :: BasePart

type Joint = { motor: Motor6D, base: CFrame }
local joints: { [string]: Joint } = {}

local function collect()
	joints = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			joints[d.Name] = { motor = d, base = d.C0 }
		end
	end
end
collect()
character.DescendantAdded:Connect(function(d)
	if d:IsA("Motor6D") then
		joints[d.Name] = { motor = d, base = d.C0 }
	end
end)

local function setJoint(name: string, rot: CFrame?, offset: Vector3?)
	local joint = joints[name]
	if not joint then return end
	local c0 = joint.base
	if offset then c0 = c0 * CFrame.new(offset) end
	if rot then c0 = c0 * rot end
	joint.motor.C0 = c0
end

-- === PHASE 12: arm inverse kinematics for weapon contact (spec §33-35) ===
-- The weapon pose leads (WeaponPose module, shared with the client viewmodel); arms solve onto
-- the grip points. Two-bone analytical IK: shoulder anchor + measured segment lengths.
local WeaponPose = require(game:GetService("ReplicatedStorage"):WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("WeaponPose"))

-- joint-to-joint spacing measured from live rig C0s: elbow sits -1.19 down the upper arm,
-- wrist -0.68 down the lower arm; palm center extends ~0.45 past the wrist joint.
local ARM_L1 = 1.19
local ARM_L2 = 0.68 + 0.45

-- Solve rotation that takes restDir to targetDir (both unit vectors, torso-local).
local function rotationBetween(restDir: Vector3, targetDir: Vector3): CFrame
	local axis = restDir:Cross(targetDir)
	local mag = axis.Magnitude
	if mag < 1e-4 then
		if restDir:Dot(targetDir) > 0 then
			return CFrame.new()
		end
		return CFrame.Angles(math.pi, 0, 0) -- opposite: flip 180 around X (rare degenerate)
	end
	local angle = math.acos(math.clamp(restDir:Dot(targetDir), -1, 1))
	return CFrame.fromAxisAngle(axis / mag, angle)
end

-- CCD (cyclic coordinate descent) IK — iteration 4. Robust replacement for the analytical
-- decomposition: works directly against the ACTUAL Motor6D forward kinematics measured live,
-- so no frame-convention assumptions can poison it. Each step rotates one joint by the world-space
-- rotation aligning (endEffector - jointPos) with (target - jointPos), conjugated into part0 frame.
-- Runs every heartbeat, so even partial per-frame convergence compounds to lock-on within frames.

local function worldRotBetween(fromVec: Vector3, toVec: Vector3): CFrame
	local axis = fromVec:Cross(toVec)
	local mag = axis.Magnitude
	if mag < 1e-5 then
		return CFrame.new()
	end
	local angle = math.acos(math.clamp(fromVec.Unit:Dot(toVec.Unit), -1, 1))
	return CFrame.fromAxisAngle(axis / mag, math.min(angle, 0.6)) -- clamp per-step rotation for stability
end

-- Rotate one Motor6D so its downstream chain turns by world rotation R about the joint pivot.
-- forward kinematics (C1 measured identity): Part1.CFrame = Part0.CFrame * C0.
local function applyWorldRotation(motorName: string, R: CFrame)
	local joint = joints[motorName]
	if not joint then return end
	local motor = joint.motor
	local p0 = motor.Part0
	if not p0 then return end
	local p0r = p0.CFrame.Rotation
	-- conjugate world rotation into part0's frame, then pre-compose onto current C0 rotation
	local Rlocal = p0r:Inverse() * R * p0r
	local cur = motor.C0
	motor.C0 = CFrame.new(joint.base.Position) * (Rlocal * cur.Rotation)
end

-- One CCD pass over a two-joint chain. jointInner/Outer names, endEffector part, target world pos.
local function ccdPass(inner: string, outer: string, endPart: BasePart, targetPos: Vector3, innerPart: BasePart, outerPart: BasePart)
	for _, spec in ipairs({ { outer, outerPart }, { inner, innerPart } }) do
		local jointPos = spec[2].Position
		local toEnd = endPart.Position - jointPos
		local toTarget = targetPos - jointPos
		if toEnd.Magnitude > 1e-4 and toTarget.Magnitude > 1e-4 then
			local R = worldRotBetween(toEnd, toTarget)
			applyWorldRotation(spec[1], R)
		end
	end
end

-- Compute grip targets and solve both arms. Called from the heartbeat when a weapon is equipped.
local function solveWeaponArms(aiming: boolean, aimPitch: number?, sprinting: boolean?)
	local torso = character:FindFirstChild("UpperTorso")
	local rua = character:FindFirstChild("RightUpperArm")
	local rla = character:FindFirstChild("RightLowerArm")
	local rhand = character:FindFirstChild("RightHand")
	local lua = character:FindFirstChild("LeftUpperArm")
	local lla = character:FindFirstChild("LeftLowerArm")
	local lhand = character:FindFirstChild("LeftHand")
	if not (torso and rua and rla and rhand and lua and lla and lhand) then return end
	local reloading = character:GetAttribute("GF_Reloading") == true
	local wid = character:GetAttribute("GF_EquippedWeapon")
	if wid ~= lastWeaponId then
		lastWeaponId = wid
		switchClock = os.clock()
	end
	local switchT = switchClock and (os.clock() - switchClock) or 99
	-- blend dips down then back up across the 0.55s window: 0->1->0 triangle
	local switchBlend = 0
	if switchT < 0.55 then
		switchBlend = switchT < 0.27 and (switchT / 0.27) or (1 - (switchT - 0.27) / 0.28)
	end
	local weaponCf = WeaponPose.weaponWorld(root.CFrame, aiming, nil, aimPitch, sprinting, reloading, switchBlend)
	local profile = WeaponPose.gripProfile(character:GetAttribute("GF_EquippedWeapon") or "")
	local primaryTarget = WeaponPose.gripWorld(weaponCf, profile.primaryGrip)
	local supportTarget = WeaponPose.gripWorld(weaponCf, profile.supportGrip)
	if reloading and profile.magazineGrip then
		supportTarget = WeaponPose.gripWorld(weaponCf, profile.magazineGrip)
	end
	-- two CCD passes per arm per heartbeat: converges over a few frames, self-correcting.
	-- end effector tracked is the hand part center; palm refinement is a later calibration step.
	local throwAt2 = character:GetAttribute("GF_GrenadeThrowAt")
	local throwActive = throwAt2 and (os.clock() - throwAt2) < 0.55
	if not throwActive then
		for _ = 1, 2 do
			ccdPass("RightShoulder", "RightElbow", rhand, primaryTarget, rua, rla)
		end
	end
	if sprinting then
		-- sprint carry: weapon rides one-handed in the right hand; left arm pumps with the stride.
		-- the swing needs the gait phase — read it from the shared phase state set in the heartbeat.
		local swing = math.sin((sharedPhase or 0)) * 0.55
		setJoint("LeftShoulder", CFrame.Angles(-swing, 0, math.rad(4)))
		setJoint("LeftElbow", CFrame.Angles(-0.9 - math.max(0, swing) * 0.3, 0, 0))
	elseif profile.twoHanded ~= false then
		for _ = 1, 2 do
			ccdPass("LeftShoulder", "LeftElbow", lhand, supportTarget, lua, lla)
		end
	else
		-- one-handed sidearm: left arm returns to natural swing
		setJoint("LeftShoulder", CFrame.Angles(0, 0, math.rad(3)))
		setJoint("LeftElbow", CFrame.Angles(-0.18, 0, 0))
	end
end

local TAU = math.pi * 2
local phase = 0
local elapsed = 0
local moveBlend = 0
local strafeBlend = 0
local lastPos = root.Position

local wasRolling = false
local lastHealth = nil
local lastWeaponId = nil
local deathClock = nil
local perfPublishClock = nil
local sharedPhase = nil
local switchClock = nil
local wasDowned = false
local reviveClock = nil
local flinchClock = nil
local flinchMag = 0
local rollEdgeClock = 0

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

RunService.Heartbeat:Connect(function(dt)
	local perfT0 = os.clock()
	character:SetAttribute("GF_AnimatorTick", (character:GetAttribute("GF_AnimatorTick") or 0) + 1)
	if not root.Parent then return end
	if humanoid.Health <= 0 then
		-- death collapse: authored fall instead of a frozen cut — body pitches backward,
		-- limbs go slack, staged over 0.9s then held. the humanoid death teardown takes
		-- over from the engine side regardless; this covers the visible window.
		deathClock = deathClock or os.clock()
		local f = math.min(1, (os.clock() - deathClock) / 0.9)
		local e = 1 - (1 - f) * (1 - f)
		setJoint("Root", CFrame.Angles(-e * 1.35, 0, e * 0.12), Vector3.new(0, -e * 1.6, 0))
		setJoint("LeftHip", CFrame.Angles(e * 0.4, 0, 0))
		setJoint("RightHip", CFrame.Angles(e * 0.25, 0, 0))
		setJoint("LeftKnee", CFrame.Angles(-e * 0.6, 0, 0))
		setJoint("RightKnee", CFrame.Angles(-e * 0.5, 0, 0))
		setJoint("Waist", CFrame.Angles(-e * 0.3, 0, 0))
		setJoint("Neck", CFrame.Angles(-e * 0.45, 0, e * 0.1))
		setJoint("LeftShoulder", CFrame.Angles(e * 0.5, 0, math.rad(14) * e))
		setJoint("RightShoulder", CFrame.Angles(e * 0.55, 0, -math.rad(14) * e))
		setJoint("LeftElbow", CFrame.Angles(-e * 0.2, 0, 0))
		setJoint("RightElbow", CFrame.Angles(-e * 0.2, 0, 0))
		return
	end
	deathClock = nil
	elapsed += dt

	-- Speed comes from replicated position deltas: the server never receives
	-- AssemblyLinearVelocity for a client-owned character.
	local pos = root.Position
	local delta = pos - lastPos
	lastPos = pos
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local speed = math.min(flat.Magnitude / math.max(dt, 1e-3), 40)
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local aiming = character:GetAttribute("Aiming") == true

	-- Blend weights smoothed so state changes do not snap.
	moveBlend = lerp(moveBlend, math.clamp(speed / 14, 0, 1), math.min(1, dt * 9))
	local local_ = character:GetPivot():VectorToObjectSpace(flat)
	strafeBlend = lerp(strafeBlend, math.clamp(local_.X / 14, -1, 1), math.min(1, dt * 7))

	local stride = lerp(9, 11.5, moveBlend)
	phase += dt * stride * math.max(moveBlend, 0.08)
	local swing = math.sin(phase) * moveBlend
	local bob = math.abs(math.cos(phase)) * 0.06 * moveBlend
	local breathe = math.sin(elapsed * 1.7) * 0.012

	local crouching = character:GetAttribute("Crouching") == true
	local rolling = character:GetAttribute("Rolling") == true
	local prevRolling = wasRolling
	local sprinting = character:GetAttribute("Sprinting") == true
	if rolling then
		-- TFD-style combat roll: the tucked body performs exactly one full rotation over the
		-- roll window, flip axis perpendicular to travel in the character's local frame —
		-- forward rolls pitch forward, backward rolls backward, laterals barrel sideways.
		-- visual-only (Root joint pose); the physics capsule is never rotated.
		if not wasRolling then
			rollEdgeClock = os.clock()
		end
		wasRolling = true  -- the early return below skips the bottom-of-loop update
		local rollFrac = math.clamp((os.clock() - rollEdgeClock) / 0.55, 0, 1)
		local eased = rollFrac * rollFrac * (3 - 2 * rollFrac)
		local angle = eased * math.pi * 2
		local rollDirWorld = Vector3.new(
			character:GetAttribute("GFRollDirX") or 0, 0,
			character:GetAttribute("GFRollDirZ") or 0)
		if rollDirWorld.Magnitude < 0.1 then
			rollDirWorld = root.CFrame.LookVector
		end
		-- travel direction in character-local space: X = pitch rate, Z = barrel rate
		local pivot = character:GetPivot()
		local ld = pivot:VectorToObjectSpace(rollDirWorld.Unit)
		local pitchRate = ld.Z  -- forward travel (ld.Z=-1) yields negative X angle = forward flip
		local barrelRate = -ld.X
		setJoint("Root",
			CFrame.Angles(pitchRate * angle, 0, barrelRate * angle),
			Vector3.new(0, -0.55 - math.sin(rollFrac * math.pi) * 0.25, 0))
		setJoint("LeftHip", CFrame.Angles(1.25, 0, 0))
		setJoint("RightHip", CFrame.Angles(1.05, 0, 0))
		setJoint("LeftKnee", CFrame.Angles(-2.1, 0, 0))
		setJoint("RightKnee", CFrame.Angles(-1.95, 0, 0))
		setJoint("LeftShoulder", CFrame.Angles(-0.9, 0, math.rad(12)))
		setJoint("RightShoulder", CFrame.Angles(-0.9, 0, math.rad(-12)))
		setJoint("LeftElbow", CFrame.Angles(-1.1, 0, 0))
		setJoint("RightElbow", CFrame.Angles(-1.1, 0, 0))
		setJoint("Waist", CFrame.Angles(0.35, 0, 0))
		return
	end
	-- GATE C lifecycle layer: downed / grenade / damage-flinch / revival.
	-- Priority: downed overrides everything; grenade throw and flinch overlay the base pose.
	local downed = character:GetAttribute("GFDowned") == true
	if wasDowned and not downed then
		reviveClock = os.clock()
	end
	wasDowned = downed
	if downed then
		-- collapsed kneel: hips folded deep, torso slumped, head down, arms limp at sides
		setJoint("Root", nil, Vector3.new(0, -1.35, 0))
		setJoint("LeftHip", CFrame.Angles(1.9, 0, 0))
		setJoint("RightHip", CFrame.Angles(0.35, 0, 0))
		setJoint("LeftKnee", CFrame.Angles(-2.2, 0, 0))
		setJoint("RightKnee", CFrame.Angles(-1.9, 0, 0))
		setJoint("LeftAnkle", CFrame.Angles(0.6, 0, 0))
		setJoint("RightAnkle", CFrame.Angles(0.6, 0, 0))
		local slump = math.sin(elapsed * 2.2) * 0.03  -- shallow breathing while downed
		setJoint("Waist", CFrame.Angles(0.55 + slump, 0.12, 0))
		setJoint("Neck", CFrame.Angles(0.5, 0, 0))
		setJoint("LeftShoulder", CFrame.Angles(0.25, 0, math.rad(10)))
		setJoint("RightShoulder", CFrame.Angles(0.3, 0, math.rad(-10)))
		setJoint("LeftElbow", CFrame.Angles(-0.25, 0, 0))
		setJoint("RightElbow", CFrame.Angles(-0.25, 0, 0))
		return
	end

	-- revive channel: kneeling over the downed ally, hands working — progress attribute
	-- is already replicated server-side by DownedService (GFReviveProgress 0..1).
	local reviveProgress = character:GetAttribute("GFReviveProgress")
	if reviveProgress then
		local work = math.sin(elapsed * 5) * 0.12  -- hands working rhythm
		setJoint("Root", nil, Vector3.new(0, -1.1, 0))
		setJoint("LeftHip", CFrame.Angles(1.7, 0, 0))
		setJoint("RightHip", CFrame.Angles(0.3, 0, 0))
		setJoint("LeftKnee", CFrame.Angles(-2.1, 0, 0))
		setJoint("RightKnee", CFrame.Angles(-1.7, 0, 0))
		setJoint("Waist", CFrame.Angles(0.45, 0, 0))
		setJoint("Neck", CFrame.Angles(0.35, 0, 0))
		setJoint("LeftShoulder", CFrame.Angles(-0.7 - work, 0.2, math.rad(8)))
		setJoint("RightShoulder", CFrame.Angles(-0.75 + work, -0.2, math.rad(-8)))
		setJoint("LeftElbow", CFrame.Angles(-0.9 - work, 0, 0))
		setJoint("RightElbow", CFrame.Angles(-0.85 + work, 0, 0))
		return
	end

	-- ability cast: airstrike raises the designator arm skyward; dome projects both arms out.
	local castAt = character:GetAttribute("GF_AbilityCastAt")
	local castT = castAt and (os.clock() - castAt) or 99
	if castT < 0.7 then
		local f = castT / 0.7
		local pulse = math.sin(math.min(f * 1.4, 1) * math.pi)
		local abil = character:GetAttribute("GF_AbilityId") or ""
		if abil == "Airstrike" then
			setJoint("RightShoulder", CFrame.Angles(-2.9 * pulse, 0, math.rad(-10) * pulse))
			setJoint("RightElbow", CFrame.Angles(-0.2 * pulse, 0, 0))
			setJoint("Waist", CFrame.Angles(-0.12 * pulse, 0.15 * pulse, 0))
			setJoint("Neck", CFrame.Angles(-0.35 * pulse, 0, 0))
		else
			-- dome / generic project: both arms thrust forward-out
			setJoint("RightShoulder", CFrame.Angles(-1.5 * pulse, -0.2 * pulse, math.rad(-14) * pulse))
			setJoint("LeftShoulder", CFrame.Angles(-1.5 * pulse, 0.2 * pulse, math.rad(14) * pulse))
			setJoint("RightElbow", CFrame.Angles(-0.3 * pulse, 0, 0))
			setJoint("LeftElbow", CFrame.Angles(-0.3 * pulse, 0, 0))
			setJoint("Waist", CFrame.Angles(0.1 * pulse, 0, 0))
		end
		return
	end

	-- traversal: vault (low obstacle hop) and climb (ledge pull-up) — attribute edge-driven.
	-- vault: legs tuck forward, torso pitches over the obstacle. climb: arms reach high, legs draw up.
	local vaultAt = character:GetAttribute("GF_VaultAt")
	local vaultKind = character:GetAttribute("GF_VaultKind") or "vault"
	local vaultT = vaultAt and (os.clock() - vaultAt) or 99
	local vaultDur = vaultKind == "climb" and 0.6 or 0.42
	if vaultT < vaultDur then
		local f = vaultT / vaultDur
		if vaultKind == "climb" then
			-- climb: arms overhead pulling, knees drawn high, torso upright against the face
			local pull = math.sin(f * math.pi)
			setJoint("LeftShoulder", CFrame.Angles(-2.6 + f * 0.8, 0, math.rad(12)))
			setJoint("RightShoulder", CFrame.Angles(-2.6 + f * 0.8, 0, math.rad(-12)))
			setJoint("LeftElbow", CFrame.Angles(-0.4 - pull * 1.2, 0, 0))
			setJoint("RightElbow", CFrame.Angles(-0.4 - pull * 1.2, 0, 0))
			setJoint("LeftHip", CFrame.Angles(1.4 * pull, 0, 0))
			setJoint("RightHip", CFrame.Angles(1.2 * pull, 0, 0))
			setJoint("LeftKnee", CFrame.Angles(-1.8 * pull, 0, 0))
			setJoint("RightKnee", CFrame.Angles(-1.6 * pull, 0, 0))
			setJoint("Waist", CFrame.Angles(-0.15 * pull, 0, 0))
		else
			-- vault: legs sweep forward through the middle of the window, torso leans over
			local sweep = math.sin(f * math.pi)
			setJoint("LeftHip", CFrame.Angles(1.1 * sweep, 0, 0))
			setJoint("RightHip", CFrame.Angles(1.3 * sweep, 0, 0))
			setJoint("LeftKnee", CFrame.Angles(-1.5 * sweep, 0, 0))
			setJoint("RightKnee", CFrame.Angles(-1.3 * sweep, 0, 0))
			setJoint("Waist", CFrame.Angles(0.4 * sweep, 0, 0))
			setJoint("LeftShoulder", CFrame.Angles(-0.6 * sweep, 0, math.rad(8)))
			setJoint("RightShoulder", CFrame.Angles(-0.7 * sweep, 0, math.rad(-8)))
		end
		return
	end

	-- revival rise: after downed clears, blend up from the kneel over 1.1s
	local reviveT = reviveClock and (os.clock() - reviveClock) or 99
	if reviveT < 1.1 then
		local k = 1 - reviveT / 1.1  -- 1 at start, 0 when risen
		setJoint("Root", nil, Vector3.new(0, -1.35 * k, 0))
		setJoint("LeftHip", CFrame.Angles(1.9 * k, 0, 0))
		setJoint("RightHip", CFrame.Angles(0.35 * k, 0, 0))
		setJoint("LeftKnee", CFrame.Angles(-2.2 * k, 0, 0))
		setJoint("RightKnee", CFrame.Angles(-1.9 * k, 0, 0))
		setJoint("Waist", CFrame.Angles(0.55 * k, 0.12 * k, 0))
		setJoint("Neck", CFrame.Angles(0.5 * k, 0, 0))
		-- arms push up off the ground during the first half, then recover
		local push = math.max(0, k * 2 - 1)
		setJoint("LeftShoulder", CFrame.Angles(-0.9 * push + 0.25 * k, 0, math.rad(10)))
		setJoint("RightShoulder", CFrame.Angles(-0.9 * push + 0.3 * k, 0, math.rad(-10)))
		return
	end

	-- damage flinch: health drops trigger a brief torso twitch, decaying over 0.35s
	local hp = humanoid.Health
	if hp < (lastHealth or hp) - 0.5 then
		flinchClock = os.clock()
		flinchMag = math.min(1, ((lastHealth or hp) - hp) / 25)
	end
	lastHealth = hp
	local flinchT = os.clock() - (flinchClock or 0)
	local flinch = flinchT < 0.35 and (1 - flinchT / 0.35) * (flinchMag or 0.5) or 0

	-- grenade throw: edge attribute carries the throw timestamp; right arm sweeps overhead
	local throwAt = character:GetAttribute("GF_GrenadeThrowAt")
	local throwT = throwAt and (os.clock() - throwAt) or 99
	local throwing = throwT < 0.55

	character:SetAttribute("GF_DbgAnim", string.format("downed=%s grounded=%s tick=%d", tostring(downed), tostring(grounded), elapsed % 1000))
	if grounded then
		-- Legs: hip swing + knee bend on the trailing leg.
		setJoint("LeftHip", CFrame.Angles(swing * 0.62, 0, 0))
		setJoint("RightHip", CFrame.Angles(-swing * 0.62, 0, 0))
		setJoint("LeftKnee", CFrame.Angles(math.min(0, swing) * 0.85 - 0.05, 0, 0))
		setJoint("RightKnee", CFrame.Angles(math.min(0, -swing) * 0.85 - 0.05, 0, 0))
		setJoint("LeftAnkle", CFrame.Angles(-swing * 0.22, 0, 0))
		setJoint("RightAnkle", CFrame.Angles(swing * 0.22, 0, 0))

		local hasWeapon = character:GetAttribute("GF_EquippedWeapon") ~= nil
		if hasWeapon then
			-- Phase 12: weapon leads, arms solve onto grip points via two-bone IK.
			-- Replaces both the old free-swing and the static aim pose whenever armed.
			local cam = workspace.CurrentCamera
			local pitch = 0
			if aiming and cam then
				pitch = math.asin(math.clamp(cam.CFrame.LookVector.Y, -1, 1))
			end
			sharedPhase = phase
			solveWeaponArms(aiming, pitch, sprinting)
		elseif aiming then
			setJoint("RightShoulder", CFrame.Angles(-1.35, 0, math.rad(-8)))
			setJoint("RightElbow", CFrame.Angles(-0.35, 0, 0))
			setJoint("LeftShoulder", CFrame.Angles(-1.15, 0, math.rad(26)))
			setJoint("LeftElbow", CFrame.Angles(-0.55, 0, 0))
		else
			setJoint("LeftShoulder", CFrame.Angles(-swing * 0.42, 0, math.rad(3) + breathe * 0.4))
			setJoint("RightShoulder", CFrame.Angles(swing * 0.42, 0, math.rad(-3) - breathe * 0.4))
			setJoint("LeftElbow", CFrame.Angles(-0.18 - math.max(0, swing) * 0.3, 0, 0))
			setJoint("RightElbow", CFrame.Angles(-0.18 - math.max(0, -swing) * 0.3, 0, 0))
		end

		local lean = sprinting and 0.13 or 0
		-- Bladed stance when armed (Phase 12): torso yawed 25 deg brings the left shoulder
		-- forward so the support grip is reachable — solved offline with the pose constants.
		local stanceYaw = hasWeapon and math.rad(-25) or 0
		if aiming then
			local cam2 = workspace.CurrentCamera
			if cam2 then
				lean = lean - math.asin(math.clamp(cam2.CFrame.LookVector.Y, -1, 1)) * 0.3
			end
		end
		setJoint("Waist", CFrame.Angles(math.rad(2) * moveBlend - lean, stanceYaw - strafeBlend * 0.18, strafeBlend * 0.06))
		if flinch > 0 then
			setJoint("Waist", CFrame.Angles(math.rad(2) * moveBlend - lean + flinch * 0.28, (stanceYaw or 0) - strafeBlend * 0.18 + flinch * 0.15, strafeBlend * 0.06))
			setJoint("Neck", CFrame.Angles(-math.rad(2) * moveBlend - flinch * 0.2, 0, 0))
		end
		if throwing then
			-- overhead throw sweep: arm cocks back then whips forward over the window
			local f = throwT / 0.55
			local armAngle = f < 0.4 and lerp(-0.5, 1.6, f / 0.4) or lerp(1.6, -2.2, (f - 0.4) / 0.6)
			setJoint("RightShoulder", CFrame.Angles(armAngle, 0, math.rad(-15)))
			setJoint("RightElbow", CFrame.Angles(f < 0.4 and -1.8 or -0.3, 0, 0))
		end
		if crouching then
			-- Crouch: hips and knees fold, torso pitches forward, arms tuck in.
			setJoint("Root", nil, Vector3.new(0, -0.85, 0))
			setJoint("LeftHip", CFrame.Angles(0.85, 0, 0))
			setJoint("RightHip", CFrame.Angles(0.72, 0, 0))
			setJoint("LeftKnee", CFrame.Angles(-1.5, 0, 0))
			setJoint("RightKnee", CFrame.Angles(-1.3, 0, 0))
			setJoint("LeftAnkle", CFrame.Angles(0.55, 0, 0))
			setJoint("RightAnkle", CFrame.Angles(0.5, 0, 0))
			setJoint("Waist", CFrame.Angles(0.28 - lean, -strafeBlend * 0.12, 0))
			setJoint("Neck", CFrame.Angles(-0.22, 0, 0))
			setJoint("LeftShoulder", CFrame.Angles(-0.5, 0, math.rad(16)))
			setJoint("RightShoulder", CFrame.Angles(-0.5, 0, math.rad(-16)))
			setJoint("LeftElbow", CFrame.Angles(-0.85, 0, 0))
			setJoint("RightElbow", CFrame.Angles(-0.85, 0, 0))
		end
		setJoint("Neck", CFrame.Angles(-math.rad(2) * moveBlend, 0, 0))
		setJoint("Root", nil, Vector3.new(0, bob + breathe * 0.4, 0))
	else
		-- Airborne: tuck legs, raise arms.
		setJoint("LeftHip", CFrame.Angles(0.52, 0, 0))
		setJoint("RightHip", CFrame.Angles(0.30, 0, 0))
		setJoint("LeftKnee", CFrame.Angles(-0.95, 0, 0))
		setJoint("RightKnee", CFrame.Angles(-0.55, 0, 0))
		setJoint("LeftShoulder", CFrame.Angles(-0.45, 0, math.rad(18)))
		setJoint("RightShoulder", CFrame.Angles(-0.45, 0, math.rad(-18)))
		setJoint("LeftElbow", CFrame.Angles(-0.5, 0, 0))
		setJoint("RightElbow", CFrame.Angles(-0.5, 0, 0))
		setJoint("Waist", CFrame.Angles(-0.08, 0, 0))
	end
	wasRolling = rolling
	-- Gate H perf instrumentation: heartbeat cost published ~1Hz for the performance harness
	if os.clock() - (perfPublishClock or 0) > 1 then
		perfPublishClock = os.clock()
		character:SetAttribute("GF_AnimPerfMs", (os.clock() - perfT0) * 1000)
	end

end)

