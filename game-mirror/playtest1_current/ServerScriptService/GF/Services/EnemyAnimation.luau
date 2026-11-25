--!strict
-- EnemyAnimation: procedural locomotion for authored enemy rigs.
-- Enemies are kinematically driven by EnemyService (anchored root + welds), so no
-- Humanoid animation is possible; this module swings the R15-style Motor6D joints
-- from actual per-frame displacement, giving believable walk cycles for free.

local RunService = game:GetService("RunService")

local WALK_AMPLITUDE = 0.62
local ARM_AMPLITUDE = 0.38
local PHASE_PER_STUD = 1.35
local BOB = 0.10

type RigState = {
	rig: Model,
	joints: { [string]: { motor: Motor6D, base: CFrame } },
	phase: number,
	last: Vector3,
}

local tracked: { [Model]: RigState } = {}

local function indexJoints(rig: Model)
	local joints: { [string]: { motor: Motor6D, base: CFrame } } = {}
	for _, d in rig:GetDescendants() do
		if d:IsA("Motor6D") then
			joints[d.Name] = { motor = d, base = d.C0 }
		end
	end
	return joints
end

local function rigOf(model: Model): Model?
	for _, c in model:GetChildren() do
		if c:IsA("Model") and c:GetAttribute("GFEnemyRig") then
			return c
		end
	end
	return nil
end

local function apply(state: RigState, swing: number, phase: number)
	local legs = { { "LeftHip", swing }, { "RightHip", -swing }, { "LeftKnee", -math.abs(swing) * 0.55 }, { "RightKnee", -math.abs(-swing) * 0.55 } }
	local arms = { { "LeftShoulder", -swing * ARM_AMPLITUDE / WALK_AMPLITUDE }, { "RightShoulder", swing * ARM_AMPLITUDE / WALK_AMPLITUDE } }

	for _, entry in legs do
		local joint = state.joints[entry[1]]
		if joint then
			joint.motor.C0 = joint.base * CFrame.Angles(entry[2], 0, 0)
		end
	end
	for _, entry in arms do
		local joint = state.joints[entry[1]]
		if joint then
			joint.motor.C0 = joint.base * CFrame.Angles(entry[2], 0, 0)
		end
	end
	local torso = state.joints["Root"] or state.joints["Waist"]
	if torso then
		torso.motor.C0 = torso.base * CFrame.new(0, math.abs(math.sin(phase * 2)) * BOB, 0)
	end
end

local function rest(state: RigState)
	for _, joint in state.joints do
		joint.motor.C0 = joint.base
	end
end

local function step(dt: number)
	local folder = workspace:FindFirstChild("ActiveActors")
	if not folder then return end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("HasRig") then
			local state = tracked[model]
			if not state then
				local rig = rigOf(model)
				if rig then
					state = { rig = rig, joints = indexJoints(rig), phase = 0, last = model:GetPivot().Position }
					tracked[model] = state
				end
			end
			if state then
				local pos = model:GetPivot().Position
				local moved = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(state.last.X, 0, state.last.Z)).Magnitude
				state.last = pos
				if moved > 0.01 and moved < 30 then
					state.phase += moved * PHASE_PER_STUD
					apply(state, math.sin(state.phase) * WALK_AMPLITUDE, state.phase)
				else
					if math.abs(math.sin(state.phase)) > 0.01 then
						state.phase += dt * 2
						apply(state, math.sin(state.phase) * WALK_AMPLITUDE * 0.12, state.phase)
					else
						rest(state)
					end
				end
			end
		end
	end
	-- forget rigs that were cleaned up
	for model in tracked do
		if not model.Parent then
			tracked[model] = nil
		end
	end
end

-- Server-side C0 writes replicated every joint movement to every client. Enemy locomotion animation is
-- presentation-only, so EnemyAnimClient performs the same procedural joint work locally on each client.
-- This module remains as documentation/shared reference and intentionally does not run a server heartbeat.
-- RunService.Heartbeat:Connect(step)

return { tracked = tracked }

