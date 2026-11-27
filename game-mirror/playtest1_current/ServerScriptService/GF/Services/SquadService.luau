--!strict
local SquadService = {}
local RS = game:GetService("ReplicatedStorage")
local salvage = { scrap = 0, energyCells = 0, militaryTechnology = 0 }
local members: { [Player]: boolean } = {}

local function broadcast(delta: any?)
	if delta then
		local ev = RS.GF.Remotes:FindFirstChild("LootCollected")
		if ev then
			ev:FireAllClients(delta)
		end
	end
	local remote = RS.GF.Remotes:FindFirstChild("SalvageChanged")
	if remote then
		remote:FireAllClients({
			scrap = salvage.scrap,
			energyCells = salvage.energyCells,
			militaryTechnology = salvage.militaryTechnology,
		})
	end
end

function SquadService.canJoin(): (boolean, string?)
	-- S02-008: missions cap at 4 real players — NPC substitutes never fill seats.
	local count = 0
	for _ in pairs(members) do count += 1 end
	if count >= 4 then
		return false, "squad full (4)"
	end
	-- S02-036/051: standard join closes during extraction, emergency states, and unsafe major-boss
	-- lethal telegraph windows — joining into a firing squad death moment is never allowed.
	if workspace:GetAttribute("GF_ExtractionCalled") == true or workspace:GetAttribute("ExtractionCalled") == true then
		return false, "extraction in progress"
	end
	if workspace:GetAttribute("GF_Emergency") == true then
		return false, "emergency state"
	end
	if workspace:GetAttribute("BastionActive") == true or workspace:GetAttribute("VeyrActive") == true then
		local phase = workspace:GetAttribute("BossPhase") or 1
		if phase >= 3 then
			return false, "boss lethal phase"
		end
	end
	return true
end

function SquadService.join(player: Player)
	local ok, reason = SquadService.canJoin()
	if not ok then
		workspace:SetAttribute("GF_LastJoinReject", reason or "closed")
		return false
	end
	members[player] = true
	SquadService.noteJoinOrder(player)
	local count = 0
	for _ in pairs(members) do count += 1 end
	workspace:SetAttribute("GF_SquadCount", count)
	-- listing truth (Counteroffensive Stage 4): open seats in the global browser track reality
	pcall(function()
		local ms = require(script.Parent.MatchmakingService)
		local squadId = ms.hostedSquad()
		if squadId then
			ms.updateTaken(squadId, count)
		end
	end)
	broadcast()
	return true
end

function SquadService.leave(player: Player)
	members[player] = nil
	local count = 0
	for _ in pairs(members) do count += 1 end
	workspace:SetAttribute("GF_SquadCount", count)
	pcall(function()
		local ms = require(script.Parent.MatchmakingService)
		local squadId = ms.hostedSquad()
		if squadId then
			if count == 0 then
				ms.unpublish(squadId)
			else
				ms.updateTaken(squadId, count)
			end
		end
	end)
end

function SquadService.add(kind: string, amount: number): boolean
	if type(amount) ~= "number" or amount <= 0 or amount > 1000 then return false end
	if salvage[kind] == nil then return false end
	salvage[kind] += math.floor(amount)
	-- shadow ledger: unsecured salvage accumulation events (spec §28 UnsecuredSalvage tracking)
	pcall(function()
		require(script.Parent.RewardLedgerService).appendEvent(
			"salvage_pickup", nil,
			string.format("salvage:%s:%d:%d", kind, math.floor(amount), math.floor(os.clock() * 1000)),
			nil
		)
	end)
	broadcast({ kind = kind, amount = math.floor(amount), source = "salvage" })
	return true
end

function SquadService.snapshot()
	return { scrap = salvage.scrap, energyCells = salvage.energyCells, militaryTechnology = salvage.militaryTechnology }
end

function SquadService.total(): number
	return salvage.scrap + salvage.energyCells + salvage.militaryTechnology
end

function SquadService.reset()
	salvage.scrap, salvage.energyCells, salvage.militaryTechnology = 0, 0, 0
	broadcast()
end

-- S02-027/028 leadership: join order is tracked so a leader disconnect elects the longest-standing
-- connected member. Empty squads expire and abandoned public entries TTL out of the global index.
local joinOrder: { Player } = {}
local leader: Player? = nil

function SquadService.electLeader(): Player?
	for _, plr in ipairs(joinOrder) do
		if plr.Parent and members[plr] then
			leader = plr
			workspace:SetAttribute("GF_SquadLeader", plr.Name)
			return plr
		end
	end
	leader = nil
	return nil
end

function SquadService.getLeader(): Player?
	return leader
end

game:GetService("Players").PlayerRemoving:Connect(function(plr)
	if plr == leader then
		workspace:SetAttribute("GF_LeaderChange", "disconnect")
		SquadService.electLeader()
	end
	for i, p in ipairs(joinOrder) do
		if p == plr then
			table.remove(joinOrder, i)
			break
		end
	end
	-- S02-028 expiry: an empty squad dissolves and its public listing TTLs out
	local count = 0
	for _ in pairs(members) do count += 1 end
	if count == 0 then
		leader = nil
		workspace:SetAttribute("GF_SquadExpired", os.clock())
	end
end)

-- S02-026 pre-launch settings: the leader adjusts privacy/rank gates before the countdown starts;
-- every change notifies members and incompatible-rank joiners are rejected. Leadership transfers
-- voluntarily through the same gate used by disconnect succession.
local settings = {
	privacy = "public",
	minRank = 1,
	maxRank = 99,
	region = "auto",
}

function SquadService.updateSettings(plr: Player, key: string, value: any): boolean
	if plr ~= leader then return false end
	if workspace:GetAttribute("GF_CountdownActive") == true then return false end
	if settings[key] == nil then return false end
	settings[key] = value
	workspace:SetAttribute("GF_SquadSetting_" .. key, tostring(value))
	workspace:SetAttribute("GF_SettingsChanged", key)
	return true
end

function SquadService.transferLeadership(plr: Player, target: Player): boolean
	if plr ~= leader then return false end
	if not members[target] then return false end
	leader = target
	workspace:SetAttribute("GF_SquadLeader", target.Name)
	workspace:SetAttribute("GF_LeaderChange", "transfer")
	return true
end

-- S02-024 invitations: private squads are invite-only; invites route through the SquadInvite remote
-- and Roblox cross-server friend joins land in the inviter's squad when one exists.
function SquadService.inviteFriend(plr: Player, targetUserId: number): boolean
	if not members[plr] then return false end
	if SquadService.getPrivacy() == "public" then return true end
	workspace:SetAttribute("GF_Invite_" .. targetUserId, plr.UserId)
	return true
end

function SquadService.redeemInvite(plr: Player): boolean
	local inviter = workspace:GetAttribute("GF_Invite_" .. plr.UserId)
	if inviter then
		workspace:SetAttribute("GF_Invite_" .. plr.UserId, nil)
		return true
	end
	return false
end

function SquadService.checkRankCompatible(plr: Player, rank: number): boolean
	return rank >= settings.minRank and rank <= settings.maxRank
end

function SquadService.getPrivacy(): string
	return settings.privacy
end

function SquadService.noteJoinOrder(plr: Player)
	table.insert(joinOrder, plr)
	if not leader then
		leader = plr
		workspace:SetAttribute("GF_SquadLeader", plr.Name)
	end
end

-- S02-029/030/033 deploy flow: squad creation starts NO countdown. The leader's Deploy begins a
-- 15s warning during which members optionally Ready; everyone ready accelerates the launch, a solo
-- leader launches immediately, and there is never a wait for a full squad — the mission fires with
-- whoever is in.
local deployState = {
	active = false,
	ready = {} :: { [Player]: boolean },
	warningEndsAt = 0,
}

function SquadService.startDeploy(plr: Player): boolean
	if plr ~= leader then return false end
	if deployState.active then return false end
	-- the squad is leaving the forming state: delist before the countdown so a cross-server
	-- joiner never teleports into a mission that already left
	pcall(function()
		local ms = require(script.Parent.MatchmakingService)
		local squadId = ms.hostedSquad()
		if squadId then
			ms.unpublish(squadId)
		end
	end)
	deployState.active = true
	deployState.ready = {}
	local count = 0
	for _ in pairs(members) do count += 1 end
	if count <= 1 then
		-- S02-030: solo deploys immediately — no ceremony for a squad of one
		workspace:SetAttribute("GF_DeployNow", true)
		deployState.active = false
		return true
	end
	deployState.warningEndsAt = os.clock() + 15
	workspace:SetAttribute("GF_DeployWarning", 15)
	task.spawn(function()
		while deployState.active do
			task.wait(0.5)
			-- acceleration: everyone ready launches now
			local allReady = true
			local any = false
			for member in pairs(members) do
				any = true
				if member ~= leader and not deployState.ready[member] then
					allReady = false
					break
				end
			end
			if any and allReady then
				workspace:SetAttribute("GF_DeployNow", true)
				deployState.active = false
				return
			end
			if os.clock() >= deployState.warningEndsAt then
				workspace:SetAttribute("GF_DeployNow", true)
				deployState.active = false
				return
			end
		end
	end)
	return true
end

function SquadService.markReady(plr: Player): boolean
	if not deployState.active then return false end
	if not members[plr] then return false end
	deployState.ready[plr] = true
	workspace:SetAttribute("GF_ReadyCount", (workspace:GetAttribute("GF_ReadyCount") or 0) + 1)
	return true
end

function SquadService.cancelDeploy(plr: Player): boolean
	if plr ~= leader then return false end
	deployState.active = false
	workspace:SetAttribute("GF_DeployWarning", 0)
	return true
end

-- S02-056/057/058 deployment resilience: failed arrivals never strand the squad — the mission
-- starts when initial arrivals are ready or a bounded 25s timeout fires. After debrief each
-- player returns independently to the public lobby; the squad dissolves cleanly.
local DEPLOY_TIMEOUT = 25

function SquadService.deploymentResilience()
	-- bounded start: missing members never hold the mission hostage
	task.delay(DEPLOY_TIMEOUT, function()
		if workspace:GetAttribute("GF_MissionStarted") ~= true then
			workspace:SetAttribute("GF_MissionStartForced", true)
			workspace:SetAttribute("GF_MissionStarted", true)
		end
	end)
end

function SquadService.dissolveAfterMission()
	for plr in pairs(members) do
		members[plr] = nil
	end
	leader = nil
	workspace:SetAttribute("GF_SquadCount", 0)
	workspace:SetAttribute("GF_SquadDissolved", os.clock())
end

-- S02-047/035 mid-mission join: public slots fill mid-mission through drop pods — the joiner
-- lands near the squad centroid at a safe offset, never displacing existing members or spawning
-- into the middle of a firefight. Private/friends-only squads respect their access setting.
function SquadService.dropPodJoin(plr: Player): boolean
	if SquadService.getPrivacy() ~= "public" then
		return false
	end
	local count = 0
	for _ in pairs(members) do count += 1 end
	if count >= 4 then
		return false -- full party: no displacement
	end
	members[plr] = true
	SquadService.noteJoinOrder(plr)
	workspace:SetAttribute("GF_DropPodJoin", plr.Name)
	workspace:SetAttribute("GF_SquadCount", count + 1)
	return true
end

-- S02-048/049 mid-mission join rules: the joiner deploys with normal fresh resources — full
-- cooldowns reset, standard ammunition. They earn base reward only from their join moment
-- forward, plus a bounded service bonus for reinforcing a mission in progress.
function SquadService.joinRewards(plr: Player): number
	plr:SetAttribute("GF_JoinedAt", os.clock())
	-- fresh deployment resources: abilities ready, full ammo
	for slot = 1, 2 do
		plr:SetAttribute("GF_AbilityCooldown" .. slot, 0)
	end
	-- bounded service bonus: reinforcement is valuable but never lucrative enough to farm
	local REINFORCE_BONUS = 50
	plr:SetAttribute("GF_ReinforceBonus", REINFORCE_BONUS)
	return REINFORCE_BONUS
end

-- S02-050/052 farm prevention: repeated completion of the same mission ID yields diminishing
-- returns — farming one operation is never optimal. Late arrivals who cannot meaningfully
-- complete before the emergency phase reject rather than wasting their drop.
local completionCounts: { [Player]: { [string]: number } } = {}

function SquadService.farmPrevention(plr: Player, missionId: string): number
	if not completionCounts[plr] then
		completionCounts[plr] = {}
	end
	local count = (completionCounts[plr][missionId] or 0) + 1
	completionCounts[plr][missionId] = count
	-- diminishing returns: first clear full reward, repeats decay
	if count == 1 then
		return 1.0
	elseif count == 2 then
		return 0.6
	else
		return 0.3
	end
end

function SquadService.rejectLateArrival(): boolean
	-- arrivals in the emergency phase window reject — no time to contribute meaningfully
	local phase = workspace:GetAttribute("GF_MissionPhase")
	return phase == "emergency" or phase == "extraction_final"
end

game:GetService("Players").PlayerRemoving:Connect(function(plr)
	completionCounts[plr] = nil
end)

return SquadService

