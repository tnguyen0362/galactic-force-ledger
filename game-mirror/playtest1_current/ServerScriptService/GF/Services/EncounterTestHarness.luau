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

function EncounterTestHarness.start()
	Workspace:GetAttributeChangedSignal("GF_TestSpawn"):Connect(function()
		local directive = Workspace:GetAttribute("GF_TestSpawn")
		if type(directive) ~= "string" or directive == "" then return end
		Workspace:SetAttribute("GF_TestSpawn", "")
		local pos = resolvePosition()
		task.defer(function()
			local ok, err = pcall(function()
				if directive == "bastion" then
					BastionTank.spawn(pos, "Standard")
				elseif directive == "vanguard" then
					BastionTank.spawn(pos, "Vanguard")
				elseif directive == "bulwark" then
					BastionTank.spawn(pos, "Bulwark")
				elseif directive == "siege" then
					BastionTank.spawn(pos, "Siege")
				elseif directive == "leviathan" then
					LeviathanWalker.spawn(pos)
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
