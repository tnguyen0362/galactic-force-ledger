--!strict
-- Server boot: remotes, config validation, then services in dependency order.
local ServerScriptService = game:GetService("ServerScriptService")

-- The world container must exist before any service places an actor, otherwise
-- ArtService.place errors out and aborts the whole boot.
local worldRoot = workspace:FindFirstChild("ActiveActors")
if not worldRoot then
	worldRoot = Instance.new("Folder")
	worldRoot.Name = "ActiveActors"
	worldRoot.Parent = workspace
end

local RemoteService = require(ServerScriptService.GF.Services.RemoteService)
local created = RemoteService.ensureRemotes()
print(string.format("[GF] boot: %d remotes ensured", created))

local check = require(ServerScriptService.GF.Test.CheckRunner)
local result = check.run()
if result.ok then
	print(string.format("[GF] boot: config check PASS (%d assertions)", result.passed))
else
	warn(string.format("[GF] boot: config check FAIL (%d failed)", result.failed))
	for _, e in result.errors do warn("  - " .. e) end
end

local ProfileService = require(ServerScriptService.GF.Services.ProfileService)
local VitalsService = require(ServerScriptService.GF.Services.VitalsService)
local CombatService = require(ServerScriptService.GF.Services.CombatService)
local MovementService = require(ServerScriptService.GF.Services.MovementService)
local EnemyService = require(ServerScriptService.GF.Services.EnemyService)
local AbilityService = require(ServerScriptService.GF.Services.AbilityService)
local PlayerService = require(ServerScriptService.GF.Services.PlayerService)
local ArmoryService = require(ServerScriptService.GF.Services.ArmoryService)
local StationWarTable = require(ServerScriptService.GF.Services.StationWarTable)
local TacticalMapService = require(ServerScriptService.GF.Services.TacticalMapService)
local DispatchService = require(ServerScriptService.GF.Services.DispatchService)
local TutorialService = require(ServerScriptService.GF.Services.TutorialService)
local SettingsService = require(ServerScriptService.GF.Services.SettingsService)
local GalacticWarService = require(ServerScriptService.GF.Services.GalacticWarService)
local MonetizationService = require(ServerScriptService.GF.Services.MonetizationService)

ProfileService.start()
MonetizationService.start()
VitalsService.start()
CombatService.start()
MovementService.start()
EnemyService.start()
require(script.Parent.Services.GFTelemetry).start()
require(script.Parent.Services.HackingService).start()
require(script.Parent.Services.OptionalService).start()
require(script.Parent.Services.CacheService).start()
require(script.Parent.Services.BastionTank).start()
require(script.Parent.Services.LeviathanWalker).start()
require(script.Parent.Services.EliteOperations).start()
require(script.Parent.Services.EncounterTestHarness).start()
require(script.Parent.Services.TroopVisuals).start()
AbilityService.start()
PlayerService.start()
task.defer(function()
	local ok, err = pcall(TacticalMapService.start)
	if not ok then warn("[GF] tactical map failed: " .. tostring(err)) end
end)
ArmoryService.start()
	-- Safety net: one boot produced no Station at all because Mission errored before its build call.
	-- If the shell is still missing after boot settles, build it here rather than shipping an empty
	-- galaxy to the player.
	task.delay(6, function()
		if workspace:FindFirstChild("Station") then
			return
		end
		warn("[GF] station missing after boot; rebuilding from Main")
		local ok, err = pcall(function()
			require(ServerScriptService.GF.Services.StationService).build()
		end)
		if not ok then
			warn("[GF] station rebuild failed: " .. tostring(err))
		end
	end)
	local CrewService = require(ServerScriptService.GF.Services.CrewService)
	task.defer(function()
		local ok, err = pcall(CrewService.build)
		if not ok then warn("[GF] crew build failed: " .. tostring(err)) end
	end)
DispatchService.start()
-- hybrid matchmaking (Counteroffensive Stage 4): heartbeat keeps listings alive, the
-- quick-deploy drain forms cross-server matches on a 5s cadence
pcall(function()
	require(ServerScriptService.GF.Services.MatchmakingService).start()
end)
GalacticWarService.start()
-- Theater of War authoritative layer: coexists with the legacy scalar campaign during
-- cutover, building multidimensional regional state in parallel (mandate Stage 3)
task.defer(function()
	local ok, err = pcall(function()
		require(ServerScriptService.GF.Services.WarStateService).start()
	end)
	if not ok then warn("[GF] war state service failed: " .. tostring(err)) end
end)
	SettingsService.start()
TutorialService.start()
require(ServerScriptService.GF.Services.SupplyService).start()
require(ServerScriptService.GF.Services.OperationService).start()
task.defer(function()
	local ok, err = pcall(StationWarTable.start)
	if not ok then warn("[GF] war table dressing failed: " .. tostring(err)) end
end)

print("[GF] boot: services online (persistence=" .. ProfileService.getPersistenceMode() .. ")")

_G.GF = {
	EnemyService = EnemyService,
	PlayerService = PlayerService,
	State = require(ServerScriptService.GF.Services.State),
	Check = check,
}

