--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.GF.Shared.Constants)
local Weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
local State = require(ServerScriptService.GF.Services.State)
local ProfileService = require(ServerScriptService.GF.Services.ProfileService)
local VitalsService = require(ServerScriptService.GF.Services.VitalsService)

local PlayerService = {}

local function sendProfile(player: Player)
	local profile = ProfileService.get(player)
	if not profile then
		return
	end
	ReplicatedStorage.GF.Remotes.ProfileUpdated:FireClient(player, profile)
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.MaxHealth = Constants.Vitals.HealthMax
	humanoid.Health = Constants.Vitals.HealthMax
	humanoid.WalkSpeed = Constants.Movement.WalkSpeed
	humanoid.JumpPower = Constants.Movement.JumpPower
	humanoid.UseJumpPower = true
	-- rocks/cliff faces must read as solid: stock 89 deg lets a soldier scale any hull side like stairs
	humanoid.MaxSlopeAngle = 55
	-- Roblox's stock character Health script regenerates health independently of the authored
	-- shield/health model and, worse, keeps healing a downed soldier during the redeploy countdown.
	-- VitalsService owns all regeneration; remove the stock script rather than tuning two systems.
	local stockHealth = character:FindFirstChild("Health")
	if stockHealth and stockHealth:IsA("Script") then
		stockHealth:Destroy()
	end

	local s = State.ensure(player)
	-- B9: apply the persisted loadout at every spawn. Before this, s.weaponId carried the session
	-- default (AR01) regardless of the player's armory selection, per-weapon pools never initialised,
	-- and the loadout slot attributes never published — so weapon switching had nothing to switch to.
	-- applyLoadout owns weapon state, pool initialisation, slot publication and the WeaponEquipped push.
	s.reloading = false
	s.shield = s.shieldMax
	s.downed = false
	s.downedAt = nil
	s.lastShotId = 0
	s.lastShotAt = 0
	s.lastDamage = 0
	pcall(function()
		require(script.Parent.CombatService).applyLoadout(player)
	end)
	local weapon = Weapons.get(s.weaponId)
	VitalsService.publish(player)
	sendProfile(player)
end

function PlayerService.start()
	local function onPlayerAdded(player: Player)
		State.ensure(player)
		local profile = ProfileService.ensure(player)
		ReplicatedStorage.GF.Remotes.ProfileUpdated:FireClient(player, profile)
		player.CharacterAdded:Connect(function(character)
			setupCharacter(player, character)
		end)
		if player.Character then
			setupCharacter(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return PlayerService

