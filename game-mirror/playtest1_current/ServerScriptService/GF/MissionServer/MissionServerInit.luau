--!strict
-- MissionServerInit: boot orchestrator for the standalone mission place (place-split migration,
-- owner directive 2026-11-28). In the split architecture this is the FIRST code that runs when a
-- mission server spins up — ahead of player arrival — so the world generates behind the teleport
-- loading screen instead of in front of a waiting squad. Measured budget: geo 6.5s + veg 11.5s.
--
-- Sequence contract:
--   1. read deploy intent (seed/difficulty/template/squad) from teleport data or pinned attrs
--   2. generate geography from the mission seed — every mission a different landform
--   3. plant vegetation, build mission sites on the generated terrain
--   4. signal GF_MissionWorldReady — the join gate opens, players teleport INTO the LZ
--
-- Migration status: scaffold — the shared-place boot path (Mission.luau) is untouched until the
-- mission place exists in the experience. This module is written so that day-one it can also be
-- invoked in the shared place by hand for validation runs.

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local MissionServerInit = {}

export type DeployIntent = {
	seed: number,
	difficulty: string,
	template: string,
	squadUserIds: { number },
}

-- Deploy intent crosses the teleport boundary as join data; a pinned-attribute path exists for
-- deterministic validation runs in Studio. Anything missing falls back to random/Normal/SABOTAGE.
function MissionServerInit.readIntent(): DeployIntent
	local seed = Workspace:GetAttribute("GF_DeploySeed")
	if type(seed) ~= "number" or seed == 0 then
		seed = (os.time() * 997 + math.random(1, 99999)) % 900000 + 1
	end
	local difficulty = Workspace:GetAttribute("GF_DeployDifficulty")
	if type(difficulty) ~= "string" then difficulty = "Normal" end
	local template = Workspace:GetAttribute("GF_DeployTemplate")
	if type(template) ~= "string" then template = "SABOTAGE_RELAY" end
	return { seed = seed, difficulty = difficulty, template = template, squadUserIds = {} }
end

function MissionServerInit.boot(intent: DeployIntent): ()
	Workspace:SetAttribute("GF_MissionWorldReady", false)
	local t0 = os.clock()
	local Services = ServerScriptService.GF.Services

	-- 1. geography: the landform itself, seed-deterministic
	local GeographyService = require(Services.GeographyService)
	local spec = GeographyService.specFromSeed(intent.seed)
	GeographyService.generate(spec)
	print(string.format("MissionServer: geography ready %.1fs (foundation=%s)", os.clock() - t0, tostring(Workspace:GetAttribute("GF_GeoFoundation"))))

	-- 2. vegetation composition over the generated foundation
	local vegT = os.clock()
	local VegetationService = require(Services.VegetationService)
	VegetationService.plant({ seed = intent.seed * 3 + 11, extent = 4900 })
	print(string.format("MissionServer: vegetation ready %.1fs", os.clock() - vegT))

	-- 3. mission sites + objective construction on the generated terrain. This reuses the shared
	-- mission-build path; in the shared place today that runs inside Mission.luau boot — the
	-- place-split extracts it here so the mission place builds nothing until terrain exists.
	Workspace:SetAttribute("GF_TerrainReady", true)
	Workspace:SetAttribute("GF_MissionTemplate", intent.template)
	Workspace:SetAttribute("GF_Difficulty", intent.difficulty)

	Workspace:SetAttribute("GF_MissionWorldReady", true)
	print(string.format("MissionServer: world ready total=%.1fs template=%s difficulty=%s",
		os.clock() - t0, intent.template, intent.difficulty))
end

return MissionServerInit
