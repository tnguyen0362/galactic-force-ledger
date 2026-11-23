-- CHECK-SEED regression check: same seed -> identical terrain and objective placement.
-- Run: `execute_luau` with datamodel_type = "Server" during a play session, BEFORE deploying.
-- Rebuilds terrain 3x and re-seats the objective twice; leaves the world on the mission seed (1234).
-- Falsifiable: if the different-seed profile matches, the terrain generator ignores its seed.
local Services = game:GetService("ServerScriptService").GF.Services
local TerrainService = require(Services.TerrainService)
local ObjectiveService = require(Services.ObjectiveService)

local SEED = 1234
local results = {}
local function check(name, pass, detail)
	results[#results + 1] = { name = name, pass = pass and true or false, detail = tostring(detail) }
end

-- 64-point surface profile over the built region (inside the +/-352 built area).
local function surfaceProfile()
	local parts = {}
	for i = 0, 7 do
		for j = 0, 7 do
			local x, z = -280 + i * 80, -280 + j * 80
			parts[#parts + 1] = string.format("%d,%d,%.2f", x, z, TerrainService.groundSurface(x, z))
		end
	end
	return table.concat(parts, "|")
end

local bootProfile = surfaceProfile()

local cols = {}
cols.same = TerrainService.build(SEED)
local sameProfile = surfaceProfile()
check("rebuild on the boot seed reproduces boot terrain", bootProfile == sameProfile,
	(#bootProfile .. " chars vs " .. #sameProfile))

cols.other = TerrainService.build(SEED + 1)
local otherProfile = surfaceProfile()
check("a different seed changes the terrain (falsifiable)", otherProfile ~= sameProfile,
	"profiles differ: " .. tostring(otherProfile ~= sameProfile))

cols.restored = TerrainService.build(SEED)
local restoredProfile = surfaceProfile()
check("restoring the seed restores the exact terrain", restoredProfile == bootProfile,
	(#restoredProfile .. " chars vs " .. #bootProfile))

check("column count is seed-independent and equals 4096",
	cols.same == 4096 and cols.other == 4096 and cols.restored == 4096,
	string.format("%d / %d / %d", cols.same, cols.other, cols.restored))

-- Objective placement: two setups on the same terrain must land on the same Y.
local function seatRelay()
	ObjectiveService.setup(Vector3.new(0, 0, -120))
	local model = workspace.ActiveActors:FindFirstChild("AscendancyRelay")
	local terminal = model and model:FindFirstChild("Terminal")
	return terminal and terminal.Position.Y or -1
end
local y1 = seatRelay()
local y2 = seatRelay()
check("objective seats at an identical Y twice in a row", math.abs(y1 - y2) < 1e-6,
	string.format("%.4f vs %.4f", y1, y2))
local expected = TerrainService.groundSurface(0, -120) + 0.4 + 2.1
check("objective Y tracks the terrain surface", math.abs(y1 - expected) < 0.6,
	string.format("terminal=%.2f expected=%.2f", y1, expected))

-- Static: the placement path must not use the global RNG (that is the only way seed can leak out).
for _, name in { "ObjectiveService", "ExtractionService", "StationService", "TerrainService", "SectorBuilder" } do
	local src = Services[name].Source
	check("no unseeded math.random in " .. name, src:find("math.random", 1, true) == nil, "source scan")
end
check("EnvironmentDressing derives its RNG from the mission seed",
	Services.EnvironmentDressing.Source:find("Random.new(seed)", 1, true) ~= nil, "source scan")

local failed = 0
for _, entry in ipairs(results) do
	if not entry.pass then failed += 1 end
	print(string.format("[eval] %s %s (%s)", entry.pass and "PASS" or "FAIL", entry.name, entry.detail))
end
print(string.format("[eval] CHECK-SEED: %d/%d passing", #results - failed, #results))
return { passed = #results - failed, total = #results, results = results }
