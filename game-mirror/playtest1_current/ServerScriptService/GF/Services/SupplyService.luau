--!strict
-- Per-player one-use supply crates (S04-027). The spec's supply model: a crate refills the magazine and
-- tops reserve up to +60%, and cannot be reused. Enemy drops carry no weapons; this is the only ammo
-- source besides starting loadout, so without it a player who runs dry can never recover in a mission.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SupplyService = {}

local RESERVE_CAP_MULTIPLIER = 1.6
local GRENADES_PER_CRATE = 2

-- Pure: a crate adds two grenade charges, never exceeding the grenade's authored max (count = 3).
function SupplyService.grenadePlan(current: number, max: number): number
	local cap = math.max(0, tonumber(max) or 0)
	return math.min(cap, math.max(0, tonumber(current) or 0) + GRENADES_PER_CRATE)
end

-- Pure so it can be unit-tested: returns the ammo and reserve a crate should leave behind.
function SupplyService.refillPlan(ammo: number, magazine: number, reserve: number, catalogReserve: number): { ammo: number, reserve: number }
	local cap = math.floor(math.max(0, tonumber(catalogReserve) or 0) * RESERVE_CAP_MULTIPLIER)
	local newAmmo = math.max(tonumber(ammo) or 0, tonumber(magazine) or 0)
	local newReserve = math.min(cap, (tonumber(reserve) or 0) + math.max(0, tonumber(catalogReserve) or 0))
	return { ammo = newAmmo, reserve = newReserve }
end

-- Applies one crate to a player. Separate from the prompt so tests can drive it without input plumbing.
function SupplyService.consume(player: Player, crate: BasePart?): (boolean, string?)
	local State = require(ServerScriptService.GF.Services.State)
	local ProfileService = require(ServerScriptService.GF.Services.ProfileService)
	local Weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
	local state = State.get(player)
	if not state then
		return false, "no state"
	end
	if crate and crate:GetAttribute("Consumed") == true then
		return false, "already used"
	end
	local weapon = Weapons.get(state.weaponId or "AR01")
	if not weapon then
		return false, "no weapon"
	end
	local plan = SupplyService.refillPlan(state.ammo or 0, weapon.magazine or 0, state.reserve or 0, weapon.reserve or 0)
	state.ammo = plan.ammo
	state.reserve = plan.reserve
	state.reloading = false
	-- Grenades: +2 capped at the authored max. GrenadeRuntime owns the charge attribute, so this reads
	-- and writes the same place the throw path consumes from.
	local grenadeId = "Frag"
	do
		local okProfile, ProfileService = pcall(require, ServerScriptService.GF.Services.ProfileService)
		local profile = okProfile and ProfileService and ProfileService.get(player)
		local loadout = profile and profile.selectedLoadout
		if type(loadout) == "table" and type(loadout.grenade) == "string" then
			grenadeId = loadout.grenade
		end
	end
	local Economy = require(ReplicatedStorage.GF.Shared.Configs.Economy)
	local maxCharges = 3
	for _, entry in pairs(Economy.Grenades or {}) do
		if entry.id == grenadeId then
			maxCharges = tonumber(entry.count) or 3
		end
	end
	local before = tonumber(player:GetAttribute("GrenadeCharges")) or maxCharges
	local after = SupplyService.grenadePlan(before, maxCharges)
	player:SetAttribute("GrenadeCharges", after)
	workspace:SetAttribute("GF_SupplyGrenades", string.format("%s %d->%d (max %d)", grenadeId, before, after, maxCharges))
	if crate then
		crate:SetAttribute("Consumed", true)
		crate:Destroy()
	end
	workspace:SetAttribute("GF_SupplyRefill", string.format("%s ammo=%d reserve=%d", player.Name, plan.ammo, plan.reserve))
	ReplicatedStorage.GF.Remotes.AmmoUpdated:FireClient(player, {
		ammo = plan.ammo,
		magazine = weapon.magazine,
		reserve = plan.reserve,
	})
	return true, nil
end

-- Spawns a one-use crate at a world position with a proximity prompt.
function SupplyService.spawn(position: Vector3): BasePart
	local crate = Instance.new("Part")
	crate.Name = "SupplyCrate"
	crate.Size = Vector3.new(2, 1.6, 2)
	crate.Position = position
	crate.Anchored = true
	crate.Material = Enum.Material.Metal
	crate.Color = Color3.fromRGB(70, 82, 96)
	crate:SetAttribute("GFSupplyCrate", true)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Resupply"
	prompt.ObjectText = "Ammunition"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = crate
	prompt.Triggered:Connect(function(player)
		SupplyService.consume(player, crate)
	end)

	crate.Parent = workspace
	return crate
end

local CRATES_PER_MISSION = 3
local crates: { [BasePart]: boolean } = {}

-- S04-027 integration: crates must exist inside a mission or "supply" is unreachable in play. Placed near
-- the squad's insertion point rather than at authored POIs, because no objective position feed is published
-- for arbitrary objectives; three per mission matches the authored sparse-supply feel.
function SupplyService.placeMissionCrates()
	SupplyService.clearCrates()
	local Players = game:GetService("Players")
	local centre = nil
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			centre = root.Position
			break
		end
	end
	if not centre then
		return 0
	end
	local offsets = {
		Vector3.new(6, 0, 4),
		Vector3.new(-7, 0, 5),
		Vector3.new(2, 0, -8),
	}
	local placed = 0
	for index = 1, math.min(CRATES_PER_MISSION, #offsets) do
		local position = centre + offsets[index]
		local groundParams = RaycastParams.new()
		groundParams.FilterType = Enum.RaycastFilterType.Exclude
		groundParams.FilterDescendantsInstances = { }
		local ground = workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), groundParams)
		if ground then
			position = ground.Position + Vector3.new(0, 1, 0)
		end
		local crate = SupplyService.spawn(position)
		crates[crate] = true
		placed += 1
	end
	workspace:SetAttribute("GF_SupplyCrates", placed)
	return placed
end

function SupplyService.clearCrates()
	for crate in pairs(crates) do
		if crate.Parent then
			crate:Destroy()
		end
	end
	crates = {}
	workspace:SetAttribute("GF_SupplyCrates", 0)
end

function SupplyService.count(): number
	local n = 0
	for crate in pairs(crates) do
		if crate.Parent then
			n += 1
		end
	end
	return n
end

function SupplyService.start()
	workspace:GetAttributeChangedSignal("GF_InMission"):Connect(function()
		if workspace:GetAttribute("GF_InMission") == true then
			SupplyService.placeMissionCrates()
		else
			SupplyService.clearCrates()
		end
	end)
end

return SupplyService

