--!strict
-- RareEncounters: seeded rare-encounter opportunities in procedural operations (spec sections
-- 54-59). Encounters emerge through the mission structure with legible generation — the seed
-- explains what was chosen. Rarity is real: most operations have none of the rare tiers.
--
-- Generation budget (spec section 54, one roll per operation, difficulty-shaped):
--   Spectre squad   — uncommon: the elevated baseline threat of elite opposition
--   Revenant squad  — rare: one special-operations encounter, highest infantry value
--   Bastion patrol  — uncommon at higher difficulties: armored presence
--   Bastion Siege   — rare: an escalation encounter at hardened sites
--   Leviathan       — very rare, and never below Hard: a major operation-level event
--
-- Deployment plausibility: encounters deploy where such forces would credibly deploy — near
-- sites, along the stronghold approach, at hardened positions. Never floating random geometry.

local Workspace = game:GetService("Workspace")

local Hierarchy = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.EncounterHierarchy)

local RareEncounters = {}

-- probabilities per difficulty, shaped so rarity is meaningful but reachable (spec section 57)
local RATES = {
	Easy = { spectre = 0.25, revenant = 0.0, bastion = 0.0, siege = 0.0, leviathan = 0.0 },
	Normal = { spectre = 0.4, revenant = 0.12, bastion = 0.15, siege = 0.05, leviathan = 0.0 },
	Hard = { spectre = 0.55, revenant = 0.22, bastion = 0.3, siege = 0.12, leviathan = 0.06 },
	Extreme = { spectre = 0.7, revenant = 0.32, bastion = 0.4, siege = 0.2, leviathan = 0.1 },
}

local function groundProbe(pos: Vector3, ignore: { Instance }?): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local hit = Workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	if hit then
		return Vector3.new(pos.X, hit.Position.Y, pos.Z)
	end
	return nil
end

-- main entry: called by OperationService after garrison generation. def = operation definition,
-- rng = operation-seeded stream (deterministic per operation seed).
function RareEncounters.planAndSpawn(def: any, rng: Random, Services: any)
	local rates = RATES[def.difficulty] or RATES.Normal
	local roll = function(p: number) return rng:NextNumber() < p end
	local circ = def.circumstance or "standard"
	-- fortified/entrenched circumstances raise armored likelihood modestly; night assault thins it
	local armorBias = (circ == "fortified" or circ == "entrenched") and 1.25 or (circ == "night_assault" and 0.8 or 1)
	local seed = (def.seed or 0) + 7331
	local spawned = {}

	-- deployment plausibility: elites anchor near the stronghold or mid-route positions
	local stronghold, primary, secondary
	for _, node in def.objectives do
		if node.siteType == "stronghold" then stronghold = node end
		if node.id == def.primaryObjective then primary = node end
		if node.optional == true and not secondary then secondary = node end
	end
	if not stronghold then return spawned end

	-- Spectre squad: uncommon elite presence, deployed at the stronghold approach
	if roll(rates.spectre) then
		local pos = stronghold.position + Vector3.new(rng:NextInteger(-40, 40), 4, rng:NextInteger(-40, 40))
		local ground = groundProbe(pos)
		if ground and Services.EliteOperations then
			local id = Services.EliteOperations.spawnDivision("Spectre", ground + Vector3.new(0, 2, 0), seed + 1)
			if id then table.insert(spawned, { kind = "Spectre", id = id, position = ground }) end
		end
	end

	-- Revenant squad: rare special-operations presence — the squad is the objective-level threat
	if roll(rates.revenant) then
		-- Revenants guard the stronghold core: plausible special-operations deployment
		local pos = stronghold.position + Vector3.new(rng:NextInteger(-16, 16), 4, rng:NextInteger(-16, 16))
		local ground = groundProbe(pos)
		if ground and Services.EliteOperations then
			local id = Services.EliteOperations.spawnDivision("Revenant", ground + Vector3.new(0, 2, 0), seed + 2)
			if id then table.insert(spawned, { kind = "Revenant", id = id, position = ground }) end
		end
	end

	-- Bastion patrol: armored presence patrolling the stronghold perimeter
	if roll(rates.bastion * armorBias) and Services.BastionTank then
		local a = rng:NextNumber() * math.pi * 2
		local pos = stronghold.position + Vector3.new(math.cos(a) * 70, 6, math.sin(a) * 70)
		local ground = groundProbe(pos)
		if ground then
			local variant = rng:NextNumber() < 0.7 and "Standard" or (rng:NextNumber() < 0.5 and "Vanguard" or "Bulwark")
			local model = Services.BastionTank.spawn(ground + Vector3.new(0, 4, 0), variant)
			if model then table.insert(spawned, { kind = "Bastion", variant = variant, position = ground }) end
		end
	end

	-- Bastion Siege: rare escalation — a siege-configured vehicle at the hardened stronghold
	if roll(rates.siege * armorBias) and circ == "fortified" or (roll(rates.siege) and circ ~= "night_assault") then
		if Services.BastionTank then
			local pos = stronghold.position + Vector3.new(rng:NextInteger(-24, 24), 6, rng:NextInteger(-24, 24))
			local ground = groundProbe(pos)
			if ground then
				local model = Services.BastionTank.spawn(ground + Vector3.new(0, 4, 0), "Siege")
				if model then table.insert(spawned, { kind = "Siege", position = ground }) end
			end
		end
	end

	-- Leviathan: the major event. very rare, Hard+ only, and never in night/storm — the machine
	-- deploys where it dominates: the open approach to the stronghold. presence is announced.
	if rates.leviathan > 0 and roll(rates.leviathan) and circ ~= "night_assault" and circ ~= "storm" then
		if Services.LeviathanWalker then
			local dx = stronghold.position.X - def.deploymentRegion.X
			local dz = stronghold.position.Z - def.deploymentRegion.Z
			-- the walker holds the middle of the approach corridor — the squad must deal with it
			local pos = Vector3.new(
				stronghold.position.X - dx * 0.35,
				stronghold.position.Y,
				stronghold.position.Z - dz * 0.35
			)
			local ground = groundProbe(pos)
			if ground then
				local model = Services.LeviathanWalker.spawn(ground + Vector3.new(0, 3, 0))
				if model then
					table.insert(spawned, { kind = "Leviathan", position = ground })
					local ev = game:GetService("ReplicatedStorage"):FindFirstChild("GF")
						and game:GetService("ReplicatedStorage").GF:FindFirstChild("Remotes")
						and game:GetService("ReplicatedStorage").GF.Remotes:FindFirstChild("MissionEvent")
					if ev then
						task.delay(6, function()
							ev:FireAllClients({ text = "Ascendancy heavy walker detected on the approach. Siege-pattern energy signatures — this is the main event.", kind = "warning" })
						end)
					end
				end
			end
		end
	end

	-- legible generation: the operation record carries what the seed produced (spec section 54)
	if #spawned > 0 then
		local summary = {}
		for _, s in spawned do table.insert(summary, s.kind .. (s.variant and (":" .. s.variant) or "")) end
		print(string.format("[GF] rare encounters (seed %d): %s", seed, table.concat(summary, ", ")))
		Workspace:SetAttribute("GF_RareEncounters", table.concat(summary, ","))
	end
	return spawned
end

return RareEncounters
