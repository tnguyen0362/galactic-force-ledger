--!strict
-- EncounterTestHarness: game-VM validation entry points. execute_luau probes run in a separate
-- plugin VM and CANNOT mutate game-VM module state — so validation drives through workspace
-- attributes (shared instance state). Set GF_TestSpawn to a spawn directive; the harness executes
-- it inside the game VM where the controller step loops actually live.
-- Directives: "bastion" | "siege" | "leviathan" | "spectre" | "revenant" — spawn near the first
-- player (or the deployment fallback). GF_TestSpawnPos overrides position as "x,y,z".

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local BastionTank = require(script.Parent.BastionTank)
local LeviathanWalker = require(script.Parent.LeviathanWalker)
local EliteOperations = require(script.Parent.EliteOperations)

local EncounterTestHarness = {}

local function resolvePosition(): Vector3
	local posStr = Workspace:GetAttribute("GF_TestSpawnPos")
	if type(posStr) == "string" then
		local x, y, z = posStr:match("([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)")
		if x then return Vector3.new(tonumber(x), tonumber(y), tonumber(z)) end
	end
	-- near the first player, offset so spawns don't crush the tester
	local pl = Players:GetPlayers()[1]
	local root = pl and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
	if root then
		return root.Position + Vector3.new(0, 6, -45)
	end
	return Vector3.new(0, 30, 0)
end

-- damage validation: GF_TestDamage = "partName,amount" applies CombatService.damageEnemy — the
-- exact function player weapons call — against the most recent test entity. This exercises the
-- real integration path (component burn + eta transfer + destruction events), not a simulation.
local lastEntity: Model? = nil

function EncounterTestHarness.start()
	Workspace:GetAttributeChangedSignal("GF_TestDamage"):Connect(function()
		local spec = Workspace:GetAttribute("GF_TestDamage")
		if type(spec) ~= "string" or spec == "" then return end
		Workspace:SetAttribute("GF_TestDamage", "")
		if not lastEntity or not lastEntity.Parent then
			Workspace:SetAttribute("GF_TestDamageError", "no test entity")
			return
		end
		local partName, amount = spec:match("([^,]+),([%d%.]+)")
		local ok, err = pcall(function()
			local CombatService = require(script.Parent.CombatService)
			CombatService.damageEnemy(lastEntity, tonumber(amount) or 100, nil, partName, 1, nil)
		end)
		Workspace:SetAttribute("GF_TestDamageDone", ok and (partName or "hull") or ("ERR:" .. tostring(err)))
	end)
	-- targeted damage: GF_TestDamageEx = "modelName,partName,amount" — finds the first actor with
	-- that exact model name and applies the real weapon damage path. Needed for elite members,
	-- which are never lastEntity (squads spawn as formations).
	Workspace:GetAttributeChangedSignal("GF_TestDamageEx"):Connect(function()
		local spec = Workspace:GetAttribute("GF_TestDamageEx")
		if type(spec) ~= "string" or spec == "" then return end
		Workspace:SetAttribute("GF_TestDamageEx", "")
		local modelName, partName, amount = spec:match("([^,]+),([^,]+),([%d%.]+)")
		if not (modelName and partName and amount) then return end
		local folder = Workspace:FindFirstChild("ActiveActors")
		if not folder then return end
		for _, m in folder:GetChildren() do
			if m.Name == modelName then
				local ok, err = pcall(function()
					local CombatService = require(script.Parent.CombatService)
					CombatService.damageEnemy(m, tonumber(amount), nil, partName, 1, nil)
				end)
				Workspace:SetAttribute("GF_TestDamageDone", ok and modelName or ("ERR:" .. tostring(err)))
				return
			end
		end
		Workspace:SetAttribute("GF_TestDamageError", "model not found: " .. modelName)
	end)
	Workspace:GetAttributeChangedSignal("GF_TestSpawn"):Connect(function()
		local directive = Workspace:GetAttribute("GF_TestSpawn")
		if type(directive) ~= "string" or directive == "" then return end
		Workspace:SetAttribute("GF_TestSpawn", "")
		local pos = resolvePosition()
		task.defer(function()
			local ok, err = pcall(function()
				if directive == "bastion" then
					lastEntity = BastionTank.spawn(pos, "Standard")
				elseif directive == "vanguard" then
					lastEntity = BastionTank.spawn(pos, "Vanguard")
				elseif directive == "bulwark" then
					lastEntity = BastionTank.spawn(pos, "Bulwark")
				elseif directive == "siege" then
					lastEntity = BastionTank.spawn(pos, "Siege")
				elseif directive == "leviathan" then
					lastEntity = LeviathanWalker.spawn(pos)
				elseif directive == "spectre" then
					EliteOperations.spawnDivision("Spectre", pos, math.random(10000))
				elseif directive == "revenant" then
					EliteOperations.spawnDivision("Revenant", pos, math.random(10000))
				end
				Workspace:SetAttribute("GF_TestSpawnDone", directive)
			end)
			if not ok then
				Workspace:SetAttribute("GF_TestSpawnError", tostring(err))
			end
		end)
	end)
end

return EncounterTestHarness
