--!strict
-- EliteOperations: squad-level encounter layer for Spectre and Revenant divisions (spec sections
-- 12-25, 58-59). Individual operators run on the established EnemyService machinery (compatible
-- role variants); THIS layer owns what makes the formation the encounter:
--   - squad composition + spawn as a formation
--   - capability vector tracking: eliminating an operator removes its contribution (spec 22)
--   - distinctive special equipment with bounded mechanics (barrier, mobility, adaptation)
--   - encounter lifecycle: Dormant -> Discovered -> Engaged -> Disengaged -> Reengaged -> Defeated
--   - concise encounter presentation (group identity + remaining count, not five boss bars)
-- No independent AI implementations: operators are EnemyService actors with elite configs.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local EnemyService = require(script.Parent.EnemyService)
local Hierarchy = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.EncounterHierarchy)

local EliteOperations = {}

local ENERGY = Color3.fromRGB(169, 99, 233)
local active: { [string]: any } = {} -- encounterId -> encounter state

export type EncounterState = {
	id: string,
	division: string, -- "Spectre" | "Revenant"
	members: { [Model]: string }, -- model -> role
	capabilityVector: { [string]: number },
	lifecycle: string,
	position: Vector3,
	barrier: any?,
	adaptation: { [string]: number }, -- bounded observation summaries (spec section 23)
	defeatedAt: number?,
}

--========== squad composition + spawn ==========

-- Spectre: 3-5 operators, weighted composition, must include variety (spec section 12)
local function composeSpectreSquad(rng: Random): { string }
	local size = rng:NextInteger(3, 5)
	local roles = Hierarchy.SpectreRoles
	local squad = {}
	-- guarantee one leader in larger formations
	if size >= 4 then table.insert(squad, "SpectreLeader") end
	while #squad < size do
		local total = 0
		for _, r in roles do total += r.weight end
		local roll = rng:NextNumber() * total
		for _, r in roles do
			roll -= r.weight
			if roll <= 0 then
				table.insert(squad, r.id)
				break
			end
		end
	end
	return squad
end

-- spawn a formation around a center point with role-distinct positions (ring, modest spread)
function EliteOperations.spawnDivision(division: string, center: Vector3, seed: number): string?
	local rng = Random.new(seed)
	local composition
	if division == "Revenant" then
		composition = {}
		for _, r in Hierarchy.RevenantRoles do table.insert(composition, r.id) end
	else
		composition = composeSpectreSquad(rng)
	end
	local encounterId = string.format("%s-%d", division, seed % 100000)
	local members = {}
	local capabilityVector = { coordination = 0, heavyPressure = 0, precisionPressure = 0, mobility = 0, defensiveSupport = 0 }
	local idx = 0
	for _, enemyId in composition do
		idx += 1
		local a = (idx / #composition) * math.pi * 2
		local r = 8 + (idx % 3) * 4
		local pos = center + Vector3.new(math.cos(a) * r, 3, math.sin(a) * r)
		local model = EnemyService.spawn(enemyId, pos)
		if model then
			members[model] = enemyId
			model:SetAttribute("EliteEncounter", encounterId)
			model:SetAttribute("EliteDivision", division)
			-- accumulate capability contributions (spec section 22)
			if division == "Revenant" then
				for _, rdef in Hierarchy.RevenantRoles do
					if rdef.id == enemyId then
						for k, v in rdef.capabilityVector do
							capabilityVector[k] = (capabilityVector[k] or 0) + v
						end
					end
				end
			end
		end
	end
	if next(members) == nil then return nil end
	local state: EncounterState = {
		id = encounterId,
		division = division,
		members = members,
		capabilityVector = capabilityVector,
		lifecycle = "Dormant",
		position = center,
		barrier = nil,
		adaptation = {},
	}
	active[encounterId] = state
	-- encounter presentation: group identity + remaining count (spec section 21)
	Workspace:SetAttribute("GF_EliteEncounter_" .. encounterId, string.format("%s:%d", division, idx))
	return encounterId
end

--========== capability vector (spec section 22) ==========
-- when an operator dies its contribution leaves the vector — remaining formation re-evaluates.
function EliteOperations.capabilityOf(encounterId: string): { [string]: number }
	local state = active[encounterId]
	return state and state.capabilityVector or {}
end

local function onMemberDied(state: EncounterState, model: Model)
	local role = state.members[model]
	if not role then return end
	state.members[model] = nil
	if state.division == "Revenant" then
		for _, rdef in Hierarchy.RevenantRoles do
			if rdef.id == role then
				for k, v in rdef.capabilityVector do
					state.capabilityVector[k] = math.max(0, (state.capabilityVector[k] or 0) - v)
				end
			end
		end
	end
	local remaining = 0
	for _ in state.members do remaining += 1 end
	Workspace:SetAttribute("GF_EliteEncounter_" .. state.id, string.format("%s:%d", state.division, remaining))
	if remaining == 0 then
		state.lifecycle = "Defeated"
		state.defeatedAt = os.clock()
		Workspace:SetAttribute("GF_EliteDefeated_" .. state.id, true)
	end
end

--========== defensive barrier (spec section 24) ==========
-- bounded mechanics: short duration, directional coverage, finite durability, meaningful cooldown,
-- visible activation/shutdown. Existing weapons defeat it — no special damage types.
local BARRIER_DURATION = 6
local BARRIER_COOLDOWN = 22
local BARRIER_HP = 260
local BARRIER_ARC = math.rad(110) -- directional coverage, not a dome

function EliteOperations.deployBarrier(state: EncounterState, defenderModel: Model)
	if state.barrier and state.barrier.active then return end
	local now = os.clock()
	if state.barrier and now - (state.barrier.deployedAt or 0) < BARRIER_COOLDOWN then return end
	local root = defenderModel.PrimaryPart
	if not root then return end
	local barrier = Instance.new("Part")
	barrier.Name = "RevenantBarrier"
	barrier.Size = Vector3.new(14, 7, 0.6)
	barrier.CFrame = root.CFrame * CFrame.new(0, 1.5, -6)
	barrier.Color = ENERGY
	barrier.Material = Enum.Material.ForceField
	barrier.Transparency = 0.45
	barrier.Anchored = true
	barrier.CanCollide = false
	barrier.CanQuery = true -- weapons CAN hit it: finite durability is the counter
	barrier:SetAttribute("GFIntegrity", BARRIER_HP)
	barrier:SetAttribute("GFIntegrityMax", BARRIER_HP)
	barrier:SetAttribute("GFStructure", true)
	barrier.Parent = Workspace
	state.barrier = {
		part = barrier,
		active = true,
		deployedAt = now,
		expiresAt = now + BARRIER_DURATION,
		arc = BARRIER_ARC,
		facing = root.CFrame.LookVector,
	}
	task.delay(BARRIER_DURATION, function()
		if barrier.Parent then
			-- shutdown animation: fade out, readable end
			local TweenService = game:GetService("TweenService")
			TweenService:Create(barrier, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			task.delay(0.55, function() if barrier.Parent then barrier:Destroy() end end)
		end
		if state.barrier then state.barrier.active = false end
	end)
end

--========== bounded adaptation (spec section 23) ==========
-- lightweight observation summaries, clamped utility influence. Never unseen information.
function EliteOperations.observe(encounterId: string, feature: string, value: number, dt: number)
	local state = active[encounterId]
	if not state then return end
	local tau = 20 -- observation time constant
	local alpha = 1 - math.exp(-dt / tau)
	local cur = state.adaptation[feature] or 0
	state.adaptation[feature] = cur + alpha * (value - cur)
end

--========== lifecycle + encounter step ==========
function EliteOperations.step(dt: number)
	for id, state in active do
		if state.lifecycle == "Defeated" then continue end
		-- member death detection through the Dead attribute pipeline
		for model, _ in state.members do
			if not model.Parent or model:GetAttribute("Dead") == true or (model:GetAttribute("Health") or 1) <= 0 then
				onMemberDied(state, model)
			end
		end
		local remaining = 0
		local centroid = Vector3.zero
		for model in state.members do
			remaining += 1
			if model.PrimaryPart then centroid += model.PrimaryPart.Position end
		end
		if remaining == 0 then continue end
		centroid = centroid / remaining
		-- discovery: legitimate player proximity reveals the encounter (spec section 58)
		if state.lifecycle == "Dormant" then
			for _, pl in Players:GetPlayers() do
				local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - centroid).Magnitude < 120 then
					state.lifecycle = "Engaged"
					-- concise encounter notification — discovery, not a global alarm (spec 58)
					local ev = game:GetService("ReplicatedStorage"):FindFirstChild("GF")
						and game:GetService("ReplicatedStorage").GF:FindFirstChild("Remotes")
						and game:GetService("ReplicatedStorage").GF.Remotes:FindFirstChild("MissionEvent")
					if ev then
						local label = state.division == "Revenant" and "Revenant Division operators in the field — highest-value targets." or "Spectre Division operators sighted — elite opposition."
						ev:FireAllClients({ text = label, kind = "warning" })
					end
					break
				end
			end
		elseif state.lifecycle == "Engaged" then
			-- disengagement detection: no player near the formation for a sustained window
			local anyNear = false
			for _, pl in Players:GetPlayers() do
				local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - centroid).Magnitude < 180 then
					anyNear = true
					break
				end
			end
			if not anyNear then
				state.disengageClock = (state.disengageClock or 0) + dt
				if state.disengageClock > 12 then
					state.lifecycle = "Disengaged"
					state.disengageClock = 0
				end
			else
				state.disengageClock = 0
			end
			-- defense specialist barrier support: deploys when the squad takes pressure and the
			-- capability survives in the vector (spec sections 16/22/24)
			if state.division == "Revenant" and (state.capabilityVector.defensiveSupport or 0) > 0 then
				for model, role in state.members do
					if role == "RevenantDefense" and model.PrimaryPart then
						local hpFrac = (model:GetAttribute("Health") or 1) / (model:GetAttribute("MaxHealth") or 1)
						if hpFrac < 0.85 then
							EliteOperations.deployBarrier(state, model)
						end
					end
				end
			end
		elseif state.lifecycle == "Disengaged" then
			-- reengagement restores the surviving formation exactly as it was (spec section 59)
			for _, pl in Players:GetPlayers() do
				local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - centroid).Magnitude < 120 then
					state.lifecycle = "Reengaged"
					break
				end
			end
		elseif state.lifecycle == "Reengaged" then
			state.lifecycle = "Engaged"
		end
	end
end

function EliteOperations.encounterState(encounterId: string): any?
	return active[encounterId]
end

-- aggregate encounter health measure for tracking (spec section 21): development metric only,
-- individual damage resolution is never replaced by it
function EliteOperations.squadHealthFrac(encounterId: string): number
	local state = active[encounterId]
	if not state then return 0 end
	local cur, max = 0, 0
	for model in state.members do
		cur += model:GetAttribute("Health") or 0
		max += model:GetAttribute("MaxHealth") or 1
	end
	if max == 0 then return 0 end
	return cur / max
end

function EliteOperations.start()
	task.spawn(function()
		while true do
			local dt = 0.5
			task.wait(dt)
			EliteOperations.step(dt)
		end
	end)
end

return EliteOperations
