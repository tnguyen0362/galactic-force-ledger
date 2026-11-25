--!strict
-- Downed / revive / redeploy. A soldier who runs out of health goes down, not dead:
-- an ally can revive them, otherwise they bleed out and spend a reinforcement ticket.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = require(script.Parent.State)
local VitalsService = require(script.Parent.VitalsService)
local SquadService = require(script.Parent.SquadService)

local DownedService = {}

-- These lived as service-local literals while Constants.Combat carried the same names with no consumer at
-- all, so CheckRunner was asserting values nothing read. DownedService now reads the shared constants, so
-- there is one source of truth and the conformance check measures what actually governs behaviour.
-- Values are unchanged (45 / 3.5 / 12) - this is centralisation, not retuning.
local CombatConstants = require(ReplicatedStorage.GF.Shared.Constants).Combat or {}
local BLEEDOUT = tonumber(CombatConstants.DownedTimeout) or 45
local SOLO_REDEPLOY_DELAY = 10
-- Spec (S03-030): ONE automatic redeploy after the first permanent death, 8s countdown, safe pod,
-- full HP/shield/ammo/grenades, ability cooldowns preserved, salvage unaffected. Second permanent
-- death returns the player to debrief/lobby. The old ticket system is retired: reinforcement was
-- never a spec concept.
local REDEPLOY_COUNTDOWN = 8
local redeployUsed: { [Player]: boolean } = {}
local pendingRedeploy: { [Player]: number } = {}
local REVIVE_TIME = tonumber(CombatConstants.ReviveDuration) or 3.5
local REVIVE_RANGE = tonumber(CombatConstants.ReviveRange) or 12

-- S03-028 revive discipline: the hold breaks if the reviver moves beyond range or the downed
-- target slides away — revives are positional commitments, not remote interactions.
function DownedService.breakRevive(reviver: Player, target: Player): boolean
	local rRoot = reviver.Character and reviver.Character:FindFirstChild("HumanoidRootPart")
	local tRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not rRoot or not tRoot then
		return true -- character gone, revive impossible
	end
	return (rRoot.Position - tRoot.Position).Magnitude > REVIVE_RANGE
end

local MOVE_TOLERANCE = 3

local reviving: { [Player]: { by: Player, endsAt: number, anchor: Vector3 } } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function hasRescuer(downed: Player): boolean
	local downedRoot = rootOf(downed)
	if not downedRoot then
		return false
	end
	for _, other in Players:GetPlayers() do
		if other ~= downed then
			local s = State.get(other)
			local otherRoot = rootOf(other)
			if s and not s.downed and otherRoot and (otherRoot.Position - downedRoot.Position).Magnitude <= REVIVE_RANGE * 2 then
				return true
			end
		end
	end
	return false
end

function DownedService.redeploy(player: Player)
	local mission = State.getMission()
	if not mission then
		return
	end
	workspace:SetAttribute("GF_RedeployPendingFor", nil)
	VitalsService.reset(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	-- drop back in beside the squad, not at the original insertion point
	local anchor: Vector3? = nil
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local s = State.get(other)
			local r = rootOf(other)
			if s and not s.downed and r then
				anchor = r.Position
				break
			end
		end
	end
	local target = anchor and (anchor + Vector3.new(math.random(-10, 10), 6, math.random(-10, 10))) or nil
	if not target then
		-- solo: come back at the mission LZ, not on the orbital station 750 studs away
		local lz = workspace:GetAttribute("GF_LZ")
		if typeof(lz) == "Vector3" then
			target = lz + Vector3.new(math.random(-8, 8), 6, math.random(-8, 8))
		end
	end
	player:LoadCharacter()
	task.defer(function()
		local newRoot = rootOf(player)
		if newRoot and target then
			newRoot.CFrame = CFrame.new(target)
		end
		-- Full HP/shield come from VitalsService.reset above; ammo and grenades refill here.
		-- Ability cooldowns are timestamps in player state and are deliberately not touched,
		-- so a cooldown in progress stays in progress through the redeploy as the spec requires.
		pcall(function()
			require(script.Parent.CombatService).applyLoadout(player)
		end)
		if _G.GrenadeRefill then
			pcall(_G.GrenadeRefill, player)
		end
	end)
	ReplicatedStorage.GF.Remotes.MissionEvent:FireAllClients({
		text = tostring(player.DisplayName) .. " redeployed.",
		kind = "redeploy",
	})
end

function DownedService.requestRevive(requester: Player, target: Player)
	local s = State.get(target)
	if not s or not s.downed or reviving[target] then
		return
	end
	local requesterRoot = rootOf(requester)
	local targetRoot = rootOf(target)
	if not requesterRoot or not targetRoot then
		return
	end
	if (requesterRoot.Position - targetRoot.Position).Magnitude > REVIVE_RANGE then
		return
	end
	local requesterState = State.get(requester)
	if not requesterState or requesterState.downed then
		return
	end
	reviving[target] = { by = requester, endsAt = os.clock() + REVIVE_TIME, anchor = requesterRoot.Position }
end

local function nearestDowned(requester: Player): Player?
	local requesterRoot = rootOf(requester)
	if not requesterRoot then
		return nil
	end
	local best: Player? = nil
	local bestDist = math.huge
	for _, other in Players:GetPlayers() do
		if other ~= requester then
			local s = State.get(other)
			local r = rootOf(other)
			if s and s.downed and r then
				local d = (r.Position - requesterRoot.Position).Magnitude
				if d <= REVIVE_RANGE and d < bestDist then
					best = other
					bestDist = d
				end
			end
		end
	end
	return best
end

function DownedService.failMission(player: Player)
	workspace:SetAttribute("GF_MissionEndReason", "squad_eliminated")
	VitalsService.reset(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	ReplicatedStorage.GF.Remotes.MissionEvent:FireAllClients({
		text = "Mission failed. No reinforcements remain.",
		kind = "fail",
	})
	local okExtraction, ExtractionService = pcall(require, script.Parent.ExtractionService)
	if okExtraction and ExtractionService and ExtractionService.finish then
		ExtractionService.finish(false)
	end
	local okStation, StationService = pcall(require, script.Parent.StationService)
	if okStation and StationService and StationService.returnToStation then
		pcall(function()
			StationService.returnToStation(player)
		end)
	end
end

-- Permanent-death resolution (S03-030). First permanent death: one automatic redeploy after an
-- 8-second countdown. Second permanent death: the player returns to debrief/lobby and leaves the
-- mission; if no active or pending-redeploy players remain the mission itself fails.
function DownedService.reinforceOrFail(player: Player)
	local mission = State.getMission()
	if not mission then
		VitalsService.reset(player)
		return
	end
	if redeployUsed[player] then
		-- second permanent death: out of the mission, no spectating
		local s = State.get(player)
		if s then
			s.downed = false
		end
		ReplicatedStorage.GF.Remotes.MissionEvent:FireAllClients({
			text = tostring(player.DisplayName) .. " is out of the fight.",
			kind = "eliminated",
		})
		-- mission failure only when nobody active or pending redeploy remains
		local anyoneLeft = false
		for _, other in Players:GetPlayers() do
			if other ~= player then
				local os2 = State.get(other)
				if os2 and not os2.downed and workspace:GetAttribute("GF_InMission") == true then
					anyoneLeft = true
					break
				end
			end
		end
		if not anyoneLeft and next(pendingRedeploy) == nil then
			DownedService.failMission(player)
			return
		end
		local okStation, StationService = pcall(require, script.Parent.StationService)
		if okStation and StationService and StationService.returnToStation then
			pcall(function()
				StationService.returnToStation(player)
			end)
		end
		return
	end
	redeployUsed[player] = true
	pendingRedeploy[player] = os.clock() + REDEPLOY_COUNTDOWN
	local s = State.get(player)
	if s then
		s.downed = false
	end
	workspace:SetAttribute("GF_RedeployCountdown", REDEPLOY_COUNTDOWN)
	workspace:SetAttribute("GF_RedeployPendingFor", player.Name)
	ReplicatedStorage.GF.Remotes.MissionEvent:FireAllClients({
		text = string.format("%s down. Automatic redeploy in %ds.", tostring(player.DisplayName), REDEPLOY_COUNTDOWN),
		kind = "redeploypending",
	})
end

function DownedService.resetMission()
	table.clear(redeployUsed)
	table.clear(pendingRedeploy)
end

function DownedService.start()
	local interact = ReplicatedStorage.GF.Remotes.InteractRequest
	interact.OnServerEvent:Connect(function(player, target)
		if target == "Revive" then
			-- InteractRequest is fan-out shared; only the owning listener spends bucket tokens.
			if not require(script.Parent.NetGuard).allow(player, "interact") then
				return
			end
			local downed = nearestDowned(player)
			if downed then
				DownedService.requestRevive(player, downed)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()

			for target, progress in reviving do
				local targetState = State.get(target)
				local by = progress.by
				local byRoot = rootOf(by)
				local byState = State.get(by)
				local valid = targetState and targetState.downed and byRoot and byState and not byState.downed
					and (byRoot.Position - progress.anchor).Magnitude <= MOVE_TOLERANCE
				if not valid then
					reviving[target] = nil
				else
					local remaining = progress.endsAt - now
					local byCharacter = by.Character
					if byCharacter then
						byCharacter:SetAttribute("GFReviveProgress", math.clamp(1 - remaining / REVIVE_TIME, 0, 1))
					end
					if remaining <= 0 then
						reviving[target] = nil
						if byCharacter then
							byCharacter:SetAttribute("GFReviveProgress", nil)
						end
						VitalsService.revive(target)
						ReplicatedStorage.GF.Remotes.MissionEvent:FireAllClients({
							text = tostring(target.DisplayName) .. " is back on their feet.",
							kind = "revive",
						})
					end
				end
			end

			for player, executeAt in pairs(pendingRedeploy) do
				if player.Parent == nil then
					pendingRedeploy[player] = nil
				elseif now >= executeAt then
					pendingRedeploy[player] = nil
					workspace:SetAttribute("GF_RedeployCountdown", 0)
					DownedService.redeploy(player)
				else
					workspace:SetAttribute("GF_RedeployCountdown", math.max(0, executeAt - now))
				end
			end

			for _, player in Players:GetPlayers() do
				local s = State.get(player)
				local character = player.Character
				if s and character then
					if s.downed then
						character:SetAttribute("GFDowned", true)
						local downedFor = now - (s.downedAt or now)
						local rescuePossible = hasRescuer(player)
						if not rescuePossible and downedFor >= SOLO_REDEPLOY_DELAY then
							DownedService.reinforceOrFail(player)
						elseif downedFor >= BLEEDOUT then
							DownedService.reinforceOrFail(player)
						end
					elseif character:GetAttribute("GFDowned") then
						character:SetAttribute("GFDowned", nil)
					end
				end
			end
		end
	end)
end

return DownedService

