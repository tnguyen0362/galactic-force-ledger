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

local TAU = math.pi * 2
local phase = 0
local elapsed = 0
local moveBlend = 0
local strafeBlend = 0
local lastPos = root.Position

local wasRolling = false
local rollEdgeClock = 0

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

RunService.Heartbeat:Connect(function(dt)
	character:SetAttribute("GF_AnimatorTick", (character:GetAttribute("GF_AnimatorTick") or 0) + 1)
	if not root.Parent or humanoid.Health <= 0 then return end
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
	if grounded then
		-- Legs: hip swing + knee bend on the trailing leg.
		setJoint("LeftHip", CFrame.Angles(swing * 0.62, 0, 0))
		setJoint("RightHip", CFrame.Angles(-swing * 0.62, 0, 0))
		setJoint("LeftKnee", CFrame.Angles(math.min(0, swing) * 0.85 - 0.05, 0, 0))
		setJoint("RightKnee", CFrame.Angles(math.min(0, -swing) * 0.85 - 0.05, 0, 0))
		setJoint("LeftAnkle", CFrame.Angles(-swing * 0.22, 0, 0))
		setJoint("RightAnkle", CFrame.Angles(swing * 0.22, 0, 0))

		if aiming then
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
		setJoint("Waist", CFrame.Angles(math.rad(2) * moveBlend - lean, -strafeBlend * 0.18, strafeBlend * 0.06))
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

end)

