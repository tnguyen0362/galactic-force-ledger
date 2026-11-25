--!strict
-- Operation First Spear: a guided tutorial that watches what the player actually does.
-- Each step completes from server-observed state (position, damage, ammo, dodge, ability) rather than
-- a client "I did it" message, so the tutorial cannot be skipped by lying.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local State = require(script.Parent.State)
local ProfileService = require(script.Parent.ProfileService)
local TutorialService = {}
local ORIGIN = Vector3.new(0, 0, 120)
local TARGET_HP = 90
local steps = {
	{ id = "move", text = "Move to the marked deck plate", hint = "WASD / left stick" },
	{ id = "shoot", text = "Destroy the training target", hint = "Hold left mouse / right trigger" },
	{ id = "reload", text = "Reload your rifle", hint = "R" },
	{ id = "dodge", text = "Dodge out of the marked zone", hint = "Left Shift / B" },
	{ id = "ability", text = "Call an Airstrike on the range", hint = "Q" },
}
local progress = {}
local dummies = {}
local function publish(player)
	local rec = progress[player]
	local step = rec and steps[rec.index]
	workspace:SetAttribute("Tutorial_Step", rec and math.min(rec.index, #steps) or 0)
	workspace:SetAttribute("Tutorial_Total", #steps)
	workspace:SetAttribute("Tutorial_Id", step and step.id or "done")
	workspace:SetAttribute("Tutorial_Text", step and step.text or "First Spear complete")
	workspace:SetAttribute("Tutorial_Complete", workspace:GetAttribute("Tutorial_Complete") or false)
	if player then
		player:SetAttribute("TutorialStep", rec and rec.index or 0)
	end
end
local function makeDummy(position)
	local model = Instance.new("Model")
	model.Name = "TrainingTarget"
	local post = Instance.new("Part")
	post.Name = "Post"
	post.Size = Vector3.new(1.2, 6, 1.2)
	post.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	post.Anchored = true
	post.Color = Color3.fromRGB(60, 66, 74)
	post.Material = Enum.Material.Metal
	post.Parent = model
	local board = Instance.new("Part")
	board.Name = "Torso"
	board.Size = Vector3.new(4, 5, 0.6)
	board.CFrame = CFrame.new(position + Vector3.new(0, 6.4, 0))
	board.Anchored = true
	board.Color = Color3.fromRGB(196, 158, 92)
	board.Material = Enum.Material.WoodPlanks
	board.Parent = model
	local ring = Instance.new("Part")
	ring.Name = "Head"
	ring.Shape = Enum.PartType.Ball
	ring.Size = Vector3.new(1.8, 1.8, 1.8)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 9.2, 0))
	ring.Anchored = true
	ring.Color = Color3.fromRGB(255, 120, 92)
	ring.Material = Enum.Material.Neon
	ring.Parent = model
	model.PrimaryPart = board
	model:SetAttribute("GFEnemy", true)
	model:SetAttribute("Health", TARGET_HP)
	model:SetAttribute("MaxHealth", TARGET_HP)
	model:SetAttribute("Shield", 0)
	model:SetAttribute("Training", true)
	model:SetAttribute("Dead", false)
	model.Parent = workspace.ActiveActors or workspace
	table.insert(dummies, model)
	return model
end
function TutorialService.buildRange()
	for _, d in ipairs(dummies) do
		if d.Parent then d:Destroy() end
	end
	dummies = {}
	for i = -1, 1 do
		makeDummy(ORIGIN + Vector3.new(i * 9, 0, -26))
	end
	workspace:SetAttribute("Tutorial_Targets", #dummies)
end
local function resetDummies()
	for _, d in ipairs(dummies) do
		if d.Parent then
			d:SetAttribute("Health", TARGET_HP)
			d:SetAttribute("Dead", false)
			d:SetAttribute("MaxHealth", TARGET_HP)
		end
	end
end
local function start(player)
	-- Resume at the persisted step (L222 tutorialProgress): a disconnect mid-First-Spear restarts at
	-- the stage the server last validated, not at zero and never past the end. Each step is a
	-- self-contained training action, so the step index IS the safe stage.
	local resumeIndex = 1
	local profile = ProfileService.ensure(player)
	if profile and profile.tutorialCompleted ~= true then
		local persisted = math.floor(tonumber(profile.tutorialProgress) or 0)
		if persisted > 1 and persisted <= #steps then
			resumeIndex = persisted
		end
	end
	progress[player] = { index = resumeIndex, startPos = ORIGIN, startedAt = os.clock(), dodge = 0, ability = 0 }
	local s = State.get(player)
	if s then
		s.tutorial = true
	end
	resetDummies()
	publish(player)
end
local function finish(player)
	progress[player] = nil
	workspace:SetAttribute("Tutorial_Complete", true)
	workspace:SetAttribute("Tutorial_FinishedAt", math.floor(os.clock()))
	publish(player)
	local profile = ProfileService.ensure(player)
	if profile then
		profile.tutorialCompleted = true
		profile.tutorialProgress = 0
		ProfileService.markDirty(player)
		-- Spec S10-009: 350 Credits, 410 XP, 1 Common cache, plus the free starter pick. The award was
		-- 200/400 with no cache, so two of the four reward components were missing outright.
		ProfileService.award(player, 350, 410)
		profile.caches = profile.caches or {}
		profile.caches.Common = (profile.caches.Common or 0) + 1
	end
	print("[GF] First Spear complete for " .. player.Name)
	ReplicatedStorage.GF.Remotes.MissionEvent:FireAllClients({ kind = "tutorial-complete" })
end
local function completed(player, rec, step)
	local s = State.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if step.id == "move" then
		local marker = workspace:GetAttribute("Tutorial_Marker")
		if typeof(marker) ~= "Vector3" then
			marker = ORIGIN + Vector3.new(0, 0, -12)
			workspace:SetAttribute("Tutorial_Marker", marker)
		end
		return root ~= nil and (root.Position - marker).Magnitude <= 8
	elseif step.id == "shoot" then
		for _, d in ipairs(dummies) do
			if d.Parent and (d:GetAttribute("Health") or 0) <= 0 then
				return true
			end
		end
		return false
	elseif step.id == "reload" then
		return s ~= nil and s.reloadCount ~= nil and s.reloadCount > (rec.reloadBase or 0)
	elseif step.id == "dodge" then
		return s ~= nil and s.dodgeCount ~= nil and s.dodgeCount > (rec.dodgeBase or 0)
	elseif step.id == "ability" then
		return s ~= nil and s.abilityCount ~= nil and s.abilityCount > (rec.abilityBase or 0)
	end
	return false
end
local function baselines(player, rec, step)
	local s = State.get(player)
	if not s then
		return
	end
	if step.id == "reload" then
		rec.reloadBase = s.reloadCount or 0
	elseif step.id == "dodge" then
		rec.dodgeBase = s.dodgeCount or 0
	elseif step.id == "ability" then
		rec.abilityBase = s.abilityCount or 0
	end
end
function TutorialService.start()
	local starterRemote = ReplicatedStorage.GF.Remotes:FindFirstChild("ClaimStarter")
	if starterRemote then
		starterRemote.OnServerEvent:Connect(function(player, weaponId)
			if not require(script.Parent.NetGuard).allow(player, "default") then
				return
			end
			local ok, why = TutorialService.claimStarter(player, weaponId)
			if not ok then
				workspace:SetAttribute("GF_StarterClaimState", "rejected:" .. tostring(why))
			end
		end)
	end
	workspace:GetAttributeChangedSignal("GF_TutorialStart"):Connect(function()
		if workspace:GetAttribute("GF_TutorialStart") then
			local player = Players:GetPlayers()[1]
			if player then
				TutorialService.begin(player)
			end
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(1)
			-- a respawn mid-tutorial must not wipe progress: only start when there is none
			if workspace:GetAttribute("Tutorial_Active") == true and progress[player] == nil then
				start(player)
			end
		end)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		for player, rec in pairs(progress) do
			local step = steps[rec.index]
			if not step then
				finish(player)
			else
				if rec.baselineStep ~= rec.index then
					rec.reloadBase, rec.dodgeBase, rec.abilityBase = nil, nil, nil
					baselines(player, rec, step)
					rec.baselineStep = rec.index
				end
				if completed(player, rec, step) then
					rec.index += 1
					local nextStep = steps[rec.index]
					-- Persist the stage as soon as the server validates it, so a disconnect here still
					-- resumes correctly. completion resets the field to 0 in finish().
					do
						local profile = ProfileService.get(player)
						if profile then
							profile.tutorialProgress = nextStep and rec.index or 0
							ProfileService.markDirty(player)
						end
					end
					if nextStep then
						rec.reloadBase, rec.dodgeBase, rec.abilityBase = nil, nil, nil
						baselines(player, rec, nextStep)
					end
					publish(player)
					ReplicatedStorage.GF.Remotes.MissionEvent:FireAllClients({
						kind = "tutorial-step",
						step = rec.index,
						id = nextStep and nextStep.id or "done",
					})
				end
			end
		end
	end)
	workspace:SetAttribute("Tutorial_Step", 0)
	workspace:SetAttribute("Tutorial_Total", #steps)
	workspace:SetAttribute("Tutorial_Complete", false)
end
-- Studio/QA hook: puts a player back into the fresh-account state (intro unseen, tutorial unfinished) so
-- the onboarding gate can be exercised without wiping a real profile.
function TutorialService.resetForTest(player: Player)
	local okProfile, ProfileService = pcall(require, script.Parent.ProfileService)
	if okProfile and ProfileService then
		local profile = ProfileService.get(player)
		if profile then
			profile.tutorialCompleted = false
			profile.introWatched = false
			ProfileService.markDirty(player)
			ProfileService.save(player)
		end
	end
	player:SetAttribute("IntroSeen", false)
	workspace:SetAttribute("Tutorial_Complete", false)
	workspace:SetAttribute("Tutorial_Active", false)
	progress[player] = nil
	return true
end

-- S10-009: first-time choice of AR/SMG/LMG free after completing the tutorial. Server-validated so the choice
-- cannot be forged, claimed once, and restricted to the three authored options.
local STARTER_CHOICES = { AR01 = true, SMG03 = true, LMG12 = true }
function TutorialService.claimStarter(player: Player, weaponId: string): (boolean, string?)
	local profile = ProfileService.get(player)
	if not profile then
		return false, "no profile"
	end
	if profile.tutorialCompleted ~= true then
		return false, "tutorial not complete"
	end
	if profile.starterClaimed == true then
		return false, "starter already claimed"
	end
	if type(weaponId) ~= "string" or not STARTER_CHOICES[weaponId] then
		return false, "not a starter option"
	end
	profile.ownedWeapons = profile.ownedWeapons or {}
	profile.ownedWeapons[weaponId] = true
	profile.starterClaimed = true
	ProfileService.markDirty(player)
	workspace:SetAttribute("GF_StarterClaim", weaponId)
	workspace:SetAttribute("GF_StarterClaimState", "claimed:" .. weaponId)
	return true, nil
end
function TutorialService.begin(player)
	workspace:SetAttribute("GF_CinematicStop", true)
	workspace:SetAttribute("Tutorial_Active", true)
	TutorialService.buildRange()
	start(player)
end
-- Test hook mirroring resetForTest: drives the completion path so the reward can be measured without
-- playing the whole tutorial.
function TutorialService.finishForTest(player: Player)
	finish(player)
end
function TutorialService.counters()
	return #dummies
end
return TutorialService
