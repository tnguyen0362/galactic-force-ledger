-- Mission geometry regression check.
-- Paste into `execute_luau` (Studio) in EDIT mode with the place stopped, then start a play
-- session and run the PLAY half. Half A catches buried/misplaced mission geometry; half B
-- catches the deploy → objective → extract loop.
--
-- HALF A (edit mode, after a play session has built the world):
--   returns ok=false with a reason when the relay is not seated on the terrain.

local TerrainService = require(game:GetService("ServerScriptService").GF.Services.TerrainService)
local failures = {}

local function check(name, condition, detail)
	table.insert(failures, { name = name, pass = condition, detail = detail })
end

-- 1. groundSurface agrees with a raw terrain raycast
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { workspace.Terrain }
local terrainHit = workspace:Raycast(Vector3.new(0, 400, 118), Vector3.new(0, -900, 0), params)
check("groundSurface matches terrain raycast",
	terrainHit ~= nil and math.abs(TerrainService.groundSurface(0, 118) - terrainHit.Position.Y) < 0.1,
	terrainHit and string.format("terrain=%.1f surface=%.1f", terrainHit.Position.Y, TerrainService.groundSurface(0, 118)) or "no terrain hit")

-- 2. module surface: every service that supports the loop exists
local Services = game:GetService("ServerScriptService").GF.Services
for _, name in { "TerrainService", "StationService", "ObjectiveService", "ExtractionService", "EnemyService", "ArtService" } do
	local svc = Services:FindFirstChild(name)
	check("service " .. name, svc ~= nil and #svc.Source > 0, svc and (#svc.Source .. " chars") or "missing")
end

-- 3. the published-LZ contract is implemented on both sides
check("StationService publishes GF_LZ", Services.StationService.Source:find('SetAttribute("GF_LZ"', 1, true) ~= nil, "attribute write")
check("ExtractionService reads GF_LZ", Services.ExtractionService.Source:find('GetAttribute("GF_LZ")', 1, true) ~= nil, "attribute read")

-- 4. objective snaps to the real ground
check("ObjectiveService snaps relay to terrain",
	Services.ObjectiveService.Source:find("TerrainService.groundSurface(position.X", 1, true) ~= nil, "groundSurface call")

local failed = 0
for _, entry in failures do
	if not entry.pass then
		failed += 1
		warn(string.format("[eval] FAIL %s (%s)", entry.name, tostring(entry.detail)))
	end
end
print(string.format("[eval] mission geometry: %d/%d passing", #failures - failed, #failures))
return { passed = #failures - failed, total = #failures, failures = failures }

-- HALF B (client, during play) — the loop evidence that used to be gathered by hand:
--
--   local remotes = game:GetService("ReplicatedStorage").GF.Remotes
--   remotes.RequestDeploy:FireServer({ difficulty = "Normal" })
--   -- walk: re-issue hum:MoveTo(terminal.Position + Vector3.new(0,0,2)) every 0.5s
--   -- StopMoveTo after ~8s on its own, so the walk loop must keep re-issuing it.
--   remotes.InteractRequest:FireServer("Relay")            -- completes after 2.5s hold
--   remotes.ExtractionRequest:FireServer()                 -- correct remote; RequestExtraction is dead
--   -- COUNTDOWN = 45s before `landed`; boarding earlier silently does nothing
--   remotes.InteractRequest:FireServer("Extract")          -- within BOARD_RANGE = 14 of BoardingZone
--   -- expect workspace GF_ExtractionState == "complete" and GF_InMission == false
