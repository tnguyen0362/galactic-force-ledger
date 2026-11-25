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
-- Spec (S03-030/S03-031): permanent deaths consume the squad's shared reinforcement-ticket
-- budget. While a ticket remains, redeploy is automatic after an 8s countdown with full HP/shield,
-- ammo and grenades; when the budget is empty the soldier is out of the operation and a squad with
-- nobody left fails. Ability cooldowns and shared salvage are preserved through redeploy.
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

local function trace(message: string)
	-- Death flow crosses half a dozen services; without a compact server-side breadcrumb the difference
	-- between "no failure branch", "failure payload lost" and "unexpected redeploy" is invisible in playtests.
	local text = string.format("%.1f %s", os.clock(), message)
	workspace:SetAttribute("GF_LastDeathTrace", text)
	print("[GF] deathflow " .. message)
end

local function countAttr(name: string): number
	local value = (workspace:GetAttribute(name) or 0) + 1
	workspace:SetAttribute(name, value)
	return value
end

local function publishTickets()
	local mission = State.getMission()
	workspace:SetAttribute("GF_ReinforcementTickets", mission and math.max(0, tonumber(mission.tickets) or 0) or 0)
end

local function consumeTicket(): boolean
	local mission = State.getMission()
	if not mission or (tonumber(mission.tickets) or 0) <= 0 then
		publishTickets()
		return false
	end
	mission.tickets = math.max(0, (tonumber(mission.tickets) or 0) - 1)
	publishTickets()
	countAttr("GF_TicketsSpent")
	return true
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

local function groundPoint(point: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local actors = workspace:FindFirstChild("ActiveActors")
	params.FilterDescendantsInstances = actors and { actors } or {}
	local hit = workspace:Raycast(point + Vector3.new(0, 500, 0), Vector3.new(0, -1200, 0), params)
	return hit and (hit.Position + Vector3.new(0, 3, 0)) or point
end

local function spawnReinforcementPod(position: Vector3)
	local pod = Instance.new("Model")
	pod.Name = "GF_ReinforcementPod"
	local shell = Instance.new("Part")
	shell.Name = "Shell"
	shell.Shape = Enum.PartType.Cylinder
	shell.Size = Vector3.new(6, 4.5, 4.5)
	shell.CFrame = CFrame.new(position + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shell.Color = Color3.fromRGB(82, 91, 104)
	shell.Material = Enum.Material.Metal
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.Parent = pod
	local glow = Instance.new("Part")
	glow.Name = "Glow"
	glow.Size = Vector3.new(5.2, 0.35, 5.2)
	glow.CFrame = CFrame.new(position + Vector3.new(0, 0.45, 0))
	glow.Color = Color3.fromRGB(120, 210, 255)
	glow.Material = Enum.Material.Neon
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.Parent = pod
	pod.PrimaryPart = shell
	pod.Parent = workspace
	game:GetService("Debris"):AddItem(pod, 7)
end

function DownedService.redeploy(player: Player)
	local mission = State.getMission()
	if not mission then
		trace("redeploy aborted no-mission player=" .. player.Name)
		return
	end
	countAttr("GF_RedeployExecCount")
	trace("automatic redeploy executing player=" .. player.Name)
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
	if target then
		target = groundPoint(target)
		spawnReinforcementPod(target)
	end
	player:LoadCharacter()
	task.defer(function()
		local newRoot = rootOf(player)
		if newRoot and target then
			newRoot.CFrame = CFrame.new(target + Vector3.new(6, 2, 7))
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
		local character = player.Character
		if character then
			local protection = Instance.new("ForceField")
			protection.Name = "GF_RedeployProtection"
			protection.Visible = true
			protection.Parent = character
			game:GetService("Debris"):AddItem(protection, 4)
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
	countAttr("GF_DeathFailCount")
	trace("failMission begin player=" .. player.Name)
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
	trace("failMission extractionRequire=" .. tostring(okExtraction))
	if okExtraction and ExtractionService and ExtractionService.finish then
		ExtractionService.finish(false)
		trace("failMission extractionFinished endReason=" .. tostring(workspace:GetAttribute("GF_MissionEndReason")))
	end
	local okStation, StationService = pcall(require, script.Parent.StationService)
	trace("failMission stationRequire=" .. tostring(okStation))
	if okStation and StationService and StationService.returnToStation then
		pcall(function()
			StationService.returnToStation(player)
		end)
	end
end

-- Permanent-death resolution. Each permanent death consumes one shared squad reinforcement ticket.
-- Tickets are deliberately not per-player: a squad can spend its budget saving the same soldier twice,
-- or distribute it across different casualties. Emergency extraction closes reinforcement support.
function DownedService.reinforceOrFail(player: Player)
	local mission = State.getMission()
	if not mission then
		trace("reinforceOrFail no-mission player=" .. player.Name)
		VitalsService.reset(player)
		return
	end
	local supportClosed = workspace:GetAttribute("GF_EmergencyExtraction") == true
	if supportClosed or not consumeTicket(player) then
		countAttr("GF_SecondDeathCount")
		trace("permanent death with no reinforcement ticket player=" .. player.Name .. " supportClosed=" .. tostring(supportClosed))
		local s = State.get(player)
		if s then
			s.downed = false
		end
		ReplicatedStorage.GF.Remotes.MissionEvent:FireAllClients({
			text = tostring(player.DisplayName) .. " is out of the fight. No reinforcements remain.",
			kind = "eliminated",
		})
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
		local pendingCount = 0
		for _, _ in pairs(pendingRedeploy) do
			pendingCount += 1
		end
		trace("no-ticket resolution anyoneLeft=" .. tostring(anyoneLeft) .. " pendingCount=" .. tostring(pendingCount))
		if not anyoneLeft and pendingCount == 0 then
			DownedService.failMission(player)
			return
		end
		VitalsService.reset(player)
		local okStation, StationService = pcall(require, script.Parent.StationService)
		if okStation and StationService and StationService.returnToStation then
			pcall(function()
				StationService.returnToStation(player)
			end)
		end
		return
	end
	pendingRedeploy[player] = os.clock() + REDEPLOY_COUNTDOWN
	countAttr("GF_FirstDeathCount")
	trace("permanent death; ticketed redeploy pending player=" .. player.Name .. " tickets=" .. tostring(mission.tickets))
	-- Keep the soldier downed through the countdown. Clearing the flag here let the vitals regen
	-- publisher immediately hide the K.I.A. overlay and even regenerate the corpse before redeploy.
	workspace:SetAttribute("GF_RedeployCountdown", REDEPLOY_COUNTDOWN)
	workspace:SetAttribute("GF_RedeployPendingFor", player.Name)
	ReplicatedStorage.GF.Remotes.MissionEvent:FireAllClients({
		text = string.format("%s down. Reinforcement pod in %ds. Tickets remaining: %d.", tostring(player.DisplayName), REDEPLOY_COUNTDOWN, tonumber(mission.tickets) or 0),
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
			-- Studio verification hook: plugin execution runs in a separate Luau VM, so it cannot mutate
			-- the authoritative State module directly. Server-only workspace attributes are the supported bridge.
			local forcedTickets = tonumber(workspace:GetAttribute("GF_DebugReinforcementTickets"))
			local activeMission = State.getMission()
			if forcedTickets and activeMission then
				activeMission.tickets = math.max(0, math.floor(forcedTickets))
				workspace:SetAttribute("GF_DebugReinforcementTickets", nil)
				publishTickets()
			end
			if workspace:GetAttribute("GF_DebugDeathflow") == true then
				workspace:SetAttribute("GF_DownedLoopAlive", now)
			end

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
					if workspace:GetAttribute("GF_DebugDeathflow") == true then
						workspace:SetAttribute("GF_DownedDebug", string.format("%s downed=%s at=%s for=%.1f pending=%s used=%s health=%s", player.Name, tostring(s.downed), tostring(s.downedAt), now - (s.downedAt or now), tostring(pendingRedeploy[player]), tostring(false), tostring(character:FindFirstChildOfClass("Humanoid") and character:FindFirstChildOfClass("Humanoid").Health)))
					end
					if s.downed then
						character:SetAttribute("GFDowned", true)
						if pendingRedeploy[player] == nil then
							local downedFor = now - (s.downedAt or now)
							local rescuePossible = hasRescuer(player)
							if not rescuePossible and downedFor >= SOLO_REDEPLOY_DELAY then
								DownedService.reinforceOrFail(player)
							elseif downedFor >= BLEEDOUT then
								DownedService.reinforceOrFail(player)
							end
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

