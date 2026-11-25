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
	-- Roblox's stock character Health script regenerates health independently of the authored
	-- shield/health model and, worse, keeps healing a downed soldier during the redeploy countdown.
	-- VitalsService owns all regeneration; remove the stock script rather than tuning two systems.
	local stockHealth = character:FindFirstChild("Health")
	if stockHealth and stockHealth:IsA("Script") then
		stockHealth:Destroy()
	end

	local s = State.ensure(player)
	local weapon = Weapons.get(s.weaponId)
	s.ammo = weapon and weapon.magazine or 28
	s.reloading = false
	s.shield = s.shieldMax
	s.downed = false
	s.downedAt = nil
	s.lastShotId = 0
	s.lastShotAt = 0
	s.lastDamage = 0

	ReplicatedStorage.GF.Remotes.WeaponEquipped:FireClient(player, {
		weaponId = s.weaponId,
		ammo = s.ammo,
		magazine = weapon and weapon.magazine or 28,
	})
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

