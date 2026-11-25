--!strict
-- Procedural station-crew animation.
-- Humanoid animation assets are unusable here: LoadAnimation on the classic R15 idle id returns a
-- track with Length 0 (measured), so the crew is driven by Motor6D C0 offsets instead. Everything
-- runs on the client; the server only places anchored, non-colliding rigs.
--
-- Replication order is the trap this script has to survive: the Crew folder arrives before its
-- children, and the children arrive before their parts. A one-shot scan found one rig with one
-- Motor6D, so the crew walked (PivotTo worked) while no limb ever moved. The tracked list now
-- refreshes until every rig has a full set of motors.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local function waitFor(folder, name, seconds)
	local deadline = os.clock() + (seconds or 20)
	while os.clock() < deadline do
		local f = folder:FindFirstChild(name)
		if f then
			return f
		end
		task.wait(0.1)
	end
	return nil
end

local crew = waitFor(workspace, "Crew", 40)
if not crew then
	return
end

local actors = {}
local tracked = {}

local function motorSnapshot(rig)
	local motors = {}
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("Motor6D") then
			motors[d.Name] = { motor = d, base = d.C0 }
		end
	end
	return motors
end

local byRig = {}

local function refresh()
	for _, rig in ipairs(crew:GetChildren()) do
		if rig:IsA("Model") and rig:GetAttribute("GFCrew") then
			local actor = byRig[rig]
			if not actor then
				local motors = motorSnapshot(rig)
				if next(motors) ~= nil then
					local root = rig:FindFirstChild("HumanoidRootPart", true)
					actor = {
						rig = rig,
						motors = motors,
						role = rig:GetAttribute("CrewRole") or "idle",
						phase = math.random() * math.pi * 2,
						root = root,
						origin = root and root.CFrame or CFrame.new(),
						applied = 0,
					}
					byRig[rig] = actor
					tracked[rig] = true
					actors[#actors + 1] = actor
				end
			else
				-- A rig can arrive with only some of its joints replicated. Top the map up instead of
				-- locking in the first partial snapshot (that is why only 38 of 90 motors animated).
				for name, entry in pairs(motorSnapshot(rig)) do
					if actor.motors[name] == nil then
						actor.motors[name] = entry
					end
				end
			end
		end
	end
end

refresh()

local function offset(motors, name, rx, ry, rz)
	local entry = motors[name]
	if not entry then
		return
	end
	entry.motor.C0 = entry.base * CFrame.Angles(rx or 0, ry or 0, rz or 0)
end

local t = 0
local sinceRefresh = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt
	sinceRefresh += dt
	if sinceRefresh > 1 then
		sinceRefresh = 0
		refresh()
	end
	for _, a in ipairs(actors) do
		local m = a.motors
		local speed = (a.role == "patrol") and 4.2 or ((a.role == "rest") and 1.1 or 1.6)
		local amp = (a.role == "patrol") and 0.42 or 0.10
		local s = math.sin(t * speed + a.phase)
		local c = math.cos(t * speed + a.phase)
		offset(m, "LeftHip", s * amp, 0, 0)
		offset(m, "RightHip", -s * amp, 0, 0)
		offset(m, "LeftKnee", math.max(0, -c) * amp * 1.6, 0, 0)
		offset(m, "RightKnee", math.max(0, c) * amp * 1.6, 0, 0)
		-- The source rig rests in an A-pose with the arms out. Without a rest correction the crew
		-- read as T-posing statues no matter how well the joints animate (capture V212).
		local ARM_DOWN = 1.15
		offset(m, "LeftShoulder", -s * amp * 0.8, 0, ARM_DOWN)
		offset(m, "RightShoulder", s * amp * 0.8, 0, -ARM_DOWN)
		offset(m, "LeftElbow", 0.12 + math.max(0, s) * 0.18, 0, 0)
		offset(m, "RightElbow", 0.12 + math.max(0, -s) * 0.18, 0, 0)
		offset(m, "Neck", 0, math.sin(t * 0.5 + a.phase) * 0.18, 0)
		offset(m, "Waist", 0, s * amp * 0.18, 0)
		a.applied += 1
		if a.role == "patrol" and a.root then
			local travel = math.sin(t * 0.35 + a.phase)
			local dir = Vector3.new(math.cos(a.phase), 0, math.sin(a.phase))
			a.rig:PivotTo(a.origin * CFrame.new(dir * travel * 8) * CFrame.Angles(0, travel * 0.6, 0))
		end
	end
end)

workspace:SetAttribute("GF_CrewAnim", true)
task.spawn(function()
	while true do
		task.wait(1)
		local motors, applied = 0, 0
		for _, a in ipairs(actors) do
			for _ in pairs(a.motors) do
				motors += 1
			end
			applied += a.applied
		end
		workspace:SetAttribute("GF_CrewDiag", string.format("actors=%d motors=%d applied=%d", #actors, motors, applied))
	end
end)

