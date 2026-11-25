--!strict
-- Soft classes: every class grants one personal modifier to its owner and one team modifier to the
-- whole squad. Stacking is capped by Configs.Classes.ModifierCaps so four Supports cannot break regen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.GF.Shared.Constants)
local Classes = require(ReplicatedStorage.GF.Shared.Configs.Classes)
local State = require(script.Parent.State)
local ProfileService = require(script.Parent.ProfileService)
local ClassService = {}
local STATS = { "ReloadSpeed", "MoveSpeed", "MaxShield", "HealthRegen", "ReviveSpeed", "DodgeRecharge" }
local function profileOf(player)
	local profile = ProfileService.get(player)
	if profile then
		return profile
	end
	return ProfileService.ensure(player)
end
local function classOf(player)
	local profile = profileOf(player)
	if not profile then
		return nil
	end
	return Classes.ById[profile.selectedClass or "Assault"]
end
function ClassService.modifiersFromIds(ids)
	local out = {}
	for _, stat in ipairs(STATS) do
		out[stat] = 0
	end
	for index, id in ipairs(ids) do
		local c = Classes.ById[id]
		if c then
			if index == 1 then
				out[c.personal.stat] += c.personal.value
			end
			out[c.team.stat] += c.team.value
		end
	end
	for stat, cap in pairs(Classes.ModifierCaps) do
		out[stat] = math.min(out[stat], cap)
	end
	return out
end

function ClassService.modifiersFor(player)
	local out = {}
	for _, stat in ipairs(STATS) do
		out[stat] = 0
	end
	local mine = classOf(player)
	if mine then
		out[mine.personal.stat] += mine.personal.value
	end
	-- Spec: each active class aura applies ONCE per squad including its owner, never duplicate-stacked.
	-- Two Assaults in one squad still grant only +5% team reload, not +10%.
	local seenTeam = {}
	for _, other in ipairs(Players:GetPlayers()) do
		-- S04-063: the buff roster is connected active/pending-redeploy soldiers only. A permanently
		-- dead or extracted soldier no longer projects their class aura; disconnected players are
		-- inherently absent from GetPlayers.
		local ost = State.get(other)
		local excluded = ost and (ost.permanentlyDead == true or ost.extracted == true)
		local c = not excluded and classOf(other)
		if c and not seenTeam[c.id] then
			seenTeam[c.id] = true
			out[c.team.stat] += c.team.value
		end
	end
	for stat, cap in pairs(Classes.ModifierCaps) do
		out[stat] = math.min(out[stat], cap)
	end
	return out
end
function ClassService.apply(player)
	local s = State.get(player)
	if not s then
		return nil
	end
	local mods = ClassService.modifiersFor(player)
	if s.baseShieldMax == nil then
		s.baseShieldMax = s.shieldMax
	end
	s.shieldMax = math.floor(s.baseShieldMax * (1 + mods.MaxShield) + 0.5)
	if s.shield > s.shieldMax then
		s.shield = s.shieldMax
	end
	s.classMods = mods
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local base = s.sprinting == true and Constants.Movement.SprintSpeed or Constants.Movement.WalkSpeed
		humanoid.WalkSpeed = base * (1 + mods.MoveSpeed)
	end
	workspace:SetAttribute("GF_ClassMods", string.format("%s:move=%.2f:reload=%.2f:shield=%.2f:regen=%.2f",
		(profileOf(player) and profileOf(player).selectedClass) or "Assault",
		mods.MoveSpeed, mods.ReloadSpeed, mods.MaxShield, mods.HealthRegen))
	return mods
end
function ClassService.applyAll()
	for _, player in ipairs(Players:GetPlayers()) do
		ClassService.apply(player)
	end
end
function ClassService.reloadFactor(player)
	local mods = ClassService.modifiersFor(player)
	return 1 / (1 + mods.ReloadSpeed)
end
function ClassService.regenFactor(player)
	local mods = ClassService.modifiersFor(player)
	return 1 + mods.HealthRegen
end
function ClassService.start()
	local function hook(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			ClassService.apply(player)
		end)
		if player.Character then
			task.defer(function()
				ClassService.apply(player)
			end)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function()
		task.defer(ClassService.applyAll)
	end)
end
ClassService.start()
return ClassService
