--!strict
-- OperationFamilies: per-template operation generators — the 15-variant expansion (directive
-- stage 7) on the shared architecture. Each family reuses the placement skeleton: deployment
-- at a map edge, primary at kilometer-scale separation, prerequisites mid-route, optional
-- sites off-axis, extraction in a band off the primary. What varies is the DAG shape and the
-- mechanic vocabulary — the operation FEELS different because the structure is different.

local OperationFamilies = {}

-- shared skeleton: given analysis + seed, produce the spatial frame every family builds on.
local function frame(seed: number, analysis: any)
	local TerrainAnalysis = require(script.Parent.TerrainAnalysis)
	local stream = Random.new(seed * 31337 + 7)
	local edge = stream:NextInteger(1, 4)
	local deployTargetX, deployTargetZ = 0, 1900
	if edge == 2 then deployTargetX, deployTargetZ = 0, -1900
	elseif edge == 3 then deployTargetX, deployTargetZ = 1900, 0
	elseif edge == 4 then deployTargetX, deployTargetZ = -1900, 0 end
	deployTargetX += stream:NextInteger(-400, 400)
	deployTargetZ += stream:NextInteger(-400, 400)
	local deploySite = TerrainAnalysis.nearest(analysis.valleyFloor, deployTargetX, deployTargetZ, nil, 900)
		or TerrainAnalysis.nearest(analysis.valleyFloor, deployTargetX, deployTargetZ, nil, 1600)
		or TerrainAnalysis.nearest(analysis.sites, deployTargetX, deployTargetZ)
	if not deploySite then return nil end

	-- primary: farthest-band flat site (kilometer-scale separation)
	local bestPrimary: any = nil
	local bestScore = -math.huge
	for _, s in analysis.sites do
		local dx, dz = s.x - deploySite.x, s.z - deploySite.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d >= 2400 and d <= 4200 then
			local score = s.score + (s.region == "highland" and 0.5 or 0) + (s.region == "lowland" and 0.3 or 0)
			if score > bestScore then bestScore = score bestPrimary = s end
		end
	end
	if not bestPrimary then
		local farD = 0
		for _, s in analysis.sites do
			local dx, dz = s.x - deploySite.x, s.z - deploySite.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > farD then farD = d bestPrimary = s end
		end
	end
	if not bestPrimary then return nil end

	local dx, dz = bestPrimary.x - deploySite.x, bestPrimary.z - deploySite.z
	local len = math.sqrt(dx * dx + dz * dz)
	local px, pz = -dz / len, dx / len

	local function mid(fraction: number, lateralMin: number, lateralMax: number)
		local off = stream:NextInteger(lateralMin, lateralMax) * (stream:NextInteger(0, 1) * 2 - 1)
		return TerrainAnalysis.nearest(analysis.sites,
			deploySite.x + dx * fraction + px * off,
			deploySite.z + dz * fraction + pz * off, nil, 800)
			or TerrainAnalysis.nearest(analysis.sites,
				deploySite.x + dx * fraction + px * off,
				deploySite.z + dz * fraction + pz * off)
	end

	-- extraction in the 300-1100 band off primary
	local extSite = nil
	do
		local bestD = math.huge
		local extX = bestPrimary.x + px * (stream:NextInteger(0, 1) * 2 - 1) * 500
		local extZ = bestPrimary.z + pz * (stream:NextInteger(0, 1) * 2 - 1) * 500
		for _, pool in ipairs({ analysis.valleyFloor, analysis.sites }) do
			for _, s in pool do
				local ddx, ddz = s.x - extX, s.z - extZ
				local d = math.sqrt(ddx * ddx + ddz * ddz)
				local pd = math.sqrt((s.x - bestPrimary.x) ^ 2 + (s.z - bestPrimary.z) ^ 2)
				if d < bestD and pd >= 300 and pd <= 1100 then bestD = d extSite = s end
			end
			if extSite then break end
		end
		if not extSite then
			local bs = -math.huge
			for _, s in analysis.sites do
				local pd = math.sqrt((s.x - bestPrimary.x) ^ 2 + (s.z - bestPrimary.z) ^ 2)
				if pd >= 200 and s.score > bs then bs = s.score extSite = s end
			end
		end
	end

	return {
		stream = stream,
		deploy = Vector3.new(deploySite.x, deploySite.y, deploySite.z),
		primary = Vector3.new(bestPrimary.x, bestPrimary.y, bestPrimary.z),
		primarySite = bestPrimary,
		mid = mid,
		extraction = extSite and Vector3.new(extSite.x, extSite.y, extSite.z) or nil,
	}
end

local function v3(s: any): Vector3
	return Vector3.new(s.x, s.y, s.z)
end

-- ============ SABOTAGE family ============
-- structural identity: destroy critical Ascendancy materiel. parallel targets reward
-- route choice; shielded variants gate the primary behind a prerequisite.

function OperationFamilies.SABOTAGE_RELAY(seed: number, f: any): { any }?
	local power = f.mid(0.45, 350, 600)
	if not power then return nil end
	return {
		{
			id = "destroy_power", mechanic = "destroy", siteType = "shield_generator",
			position = v3(power), state = "Available", progress = 0,
			consequences = { "DefensiveSystemDisabled" },
			label = "Destroy the relay power station",
		},
		{
			id = "destroy_relay", mechanic = "destroy", siteType = "comms_relay",
			position = f.primary, requires = {}, state = "Available", progress = 0,
			consequences = { "ReinforcementPermissionChanged" },
			label = "Destroy the comms relay",
		},
	}
end

function OperationFamilies.SABOTAGE_ARSENAL(seed: number, f: any): { any }?
	-- parallel destruction: two forward caches then the primary arsenal — any order on the
	-- caches, both required before the arsenal cache is targetable. route choice matters.
	local cache1 = f.mid(0.4, 300, 550)
	local cache2 = f.mid(0.62, 300, 550)
	if not (cache1 and cache2) then return nil end
	return {
		{
			id = "destroy_cache_alpha", mechanic = "destroy", siteType = "artillery",
			position = v3(cache1), state = "Available", progress = 0,
			label = "Destroy cache alpha",
		},
		{
			id = "destroy_cache_beta", mechanic = "destroy", siteType = "artillery",
			position = v3(cache2), state = "Available", progress = 0,
			label = "Destroy cache beta",
		},
		{
			id = "destroy_arsenal", mechanic = "destroy", siteType = "stronghold",
			position = f.primary,
			requires = { "destroy_cache_alpha", "destroy_cache_beta" },
			state = "Locked", progress = 0,
			label = "Destroy the arsenal",
		},
	}
end

function OperationFamilies.SABOTAGE_AEGIS(seed: number, f: any): { any }?
	local shield = f.mid(0.5, 350, 600)
	if not shield then return nil end
	return {
		{
			id = "disable_aegis_shield", mechanic = "destroy", siteType = "shield_generator",
			position = v3(shield), state = "Available", progress = 0,
			consequences = { "DefensiveSystemDisabled" },
			label = "Destroy the aegis shield generator",
		},
		{
			id = "destroy_aegis", mechanic = "destroy", siteType = "stronghold",
			position = f.primary, requires = { "disable_aegis_shield" },
			state = "Locked", progress = 0,
			label = "Destroy the aegis emitter",
		},
	}
end

-- ============ RECOVERY family ============
-- structural identity: find and extract assets. the carry mechanic creates the return leg —
-- recovery operations invert the assault geometry (extraction IS the objective).

function OperationFamilies.RECOVER_TECH(seed: number, f: any): { any }?
	-- tech cache deep in enemy ground; recovery then carry to extraction.
	return {
		{
			id = "recover_tech", mechanic = "recover", siteType = "supply_cache",
			position = f.primary, state = "Available", progress = 0,
			label = "Recover the tech cache",
		},
	}
end

function OperationFamilies.RECOVERY_ARCHIVE(seed: number, f: any): { any }?
	-- the archive is behind a security lockout: disable the lockout relay first, then recover.
	local lockout = f.mid(0.5, 350, 600)
	if not lockout then return nil end
	return {
		{
			id = "disable_lockout", mechanic = "disable", siteType = "comms_relay",
			position = v3(lockout), state = "Available", progress = 0,
			label = "Disable the security lockout",
		},
		{
			id = "recover_archive", mechanic = "recover", siteType = "comms_relay",
			position = f.primary, requires = { "disable_lockout" },
			state = "Locked", progress = 0,
			label = "Recover the archive",
		},
	}
end

function OperationFamilies.RECOVERY_CONVOY(seed: number, f: any): { any }?
	-- two distributed salvage points, either order, both required
	local pt1 = f.mid(0.55, 250, 450)
	local pt2 = f.mid(0.75, 250, 450)
	if not (pt1 and pt2) then return nil end
	return {
		{
			id = "recover_crate_alpha", mechanic = "recover", siteType = "supply_cache",
			position = v3(pt1), state = "Available", progress = 0,
			label = "Recover convoy crate alpha",
		},
		{
			id = "recover_crate_beta", mechanic = "recover", siteType = "supply_cache",
			position = v3(pt2), state = "Available", progress = 0,
			label = "Recover convoy crate beta",
		},
	}
end

-- ============ DEFENSE family ============
-- structural identity: hold ground against pressure. the defend mechanic runs a timer while
-- the director economy escalates — the geography choice (defensible ground) is the strategy.

function OperationFamilies.DEFEND_BEACON(seed: number, f: any): { any }?
	-- activate the beacon at the primary site, then hold it
	return {
		{
			id = "activate_beacon", mechanic = "activate", siteType = "comms_relay",
			position = f.primary, state = "Available", progress = 0,
			label = "Activate the beacon",
		},
		{
			id = "hold_beacon", mechanic = "defend", siteType = "comms_relay",
			position = f.primary, requires = { "activate_beacon" },
			state = "Locked", progress = 0, defendSeconds = 120,
			label = "Hold the beacon",
		},
	}
end

function OperationFamilies.DEFENSE_POWER(seed: number, f: any): { any }?
	return {
		{
			id = "restore_power", mechanic = "restore", siteType = "shield_generator",
			position = f.primary, state = "Available", progress = 0,
			label = "Restore the generator",
		},
		{
			id = "defend_power", mechanic = "defend", siteType = "shield_generator",
			position = f.primary, requires = { "restore_power" },
			state = "Locked", progress = 0, defendSeconds = 120,
			label = "Defend the generator",
		},
	}
end

function OperationFamilies.DEFENSE_UPLINK(seed: number, f: any): { any }?
	return {
		{
			id = "activate_uplink", mechanic = "activate", siteType = "comms_relay",
			position = f.primary, state = "Available", progress = 0,
			label = "Activate the uplink",
		},
		{
			id = "defend_uplink", mechanic = "defend", siteType = "comms_relay",
			position = f.primary, requires = { "activate_uplink" },
			state = "Locked", progress = 0, defendSeconds = 105,
			label = "Defend the uplink",
		},
	}
end

-- ============ ELIMINATION family ============
-- structural identity: kill valued targets. target quality and distribution vary —
-- the hunt across terrain is the operation.

function OperationFamilies.ELIM_COMMANDER(seed: number, f: any): { any }?
	return {
		{
			id = "eliminate_commander", mechanic = "eliminate", siteType = "stronghold",
			position = f.primary, state = "Available", progress = 0,
			elimComposition = { "Officer", "Rifleman", "Rifleman", "Scout" },
			label = "Eliminate the Ascendancy commander",
		},
	}
end

function OperationFamilies.ELIM_WALKER(seed: number, f: any): { any }?
	return {
		{
			id = "eliminate_walker", mechanic = "eliminate", siteType = "artillery",
			position = f.primary, state = "Available", progress = 0,
			elimComposition = { "BastionWalker" },
			label = "Destroy the Bastion walker",
		},
	}
end

function OperationFamilies.ELIM_TALON(seed: number, f: any): { any }?
	-- three distributed elite targets: the hunt spans the operation area
	local t2 = f.mid(0.5, 300, 500)
	local t3 = f.mid(0.7, 300, 500)
	if not (t2 and t3) then return nil end
	return {
		{
			id = "eliminate_talon_alpha", mechanic = "eliminate", siteType = "comms_relay",
			position = f.primary, state = "Available", progress = 0,
			elimComposition = { "Marksman" },
			label = "Eliminate Talon alpha",
		},
		{
			id = "eliminate_talon_beta", mechanic = "eliminate", siteType = "supply_cache",
			position = v3(t2), state = "Available", progress = 0,
			elimComposition = { "Heavy" },
			label = "Eliminate Talon beta",
		},
		{
			id = "eliminate_talon_gamma", mechanic = "eliminate", siteType = "shield_generator",
			position = v3(t3), state = "Available", progress = 0,
			elimComposition = { "Officer" },
			label = "Eliminate Talon gamma",
		},
	}
end

-- ============ CONQUEST family ============
-- DOMINION is the reference operation (generated by OperationService itself); the variants
-- shift the capture geometry.

function OperationFamilies.CONQUEST_FOUNDRY(seed: number, f: any): { any }?
	-- twin capture: two nodes, either order, both required — the squad splits or sweeps
	local node2 = f.mid(0.68, 300, 520)
	if not node2 then return nil end
	return {
		{
			id = "capture_foundry_alpha", mechanic = "capture", siteType = "stronghold",
			position = f.primary, state = "Available", progress = 0,
			label = "Capture foundry alpha",
		},
		{
			id = "capture_foundry_beta", mechanic = "capture", siteType = "comms_relay",
			position = v3(node2), state = "Available", progress = 0,
			label = "Capture foundry beta",
		},
	}
end

function OperationFamilies.CONQUEST_THRONEFALL(seed: number, f: any): { any }?
	-- the decapitation strike: capture the stronghold, then the Marshal himself takes the field
	local shield = f.mid(0.5, 350, 600)
	if not shield then return nil end
	return {
		{
			id = "disable_shield", mechanic = "destroy", siteType = "shield_generator",
			position = v3(shield), state = "Available", progress = 0,
			consequences = { "DefensiveSystemDisabled" },
			label = "Destroy the throne shield",
		},
		{
			id = "capture_throne", mechanic = "capture", siteType = "stronghold",
			position = f.primary, requires = { "disable_shield" },
			state = "Locked", progress = 0,
			label = "Capture the throne stronghold",
		},
		{
			id = "eliminate_marshal", mechanic = "eliminate", siteType = "stronghold",
			position = f.primary, requires = { "capture_throne" },
			state = "Locked", progress = 0,
			elimComposition = { "HighMarshalVeyr" },
			label = "Eliminate High Marshal Veyr",
		},
	}
end

-- multi-primary families: completion logic — the LAST completed of the family primaries
-- completes the operation. handled by marking every family-primary as a shared primary id
-- in the dispatch layer.

return OperationFamilies
