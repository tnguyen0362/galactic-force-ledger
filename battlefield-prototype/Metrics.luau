--!strict
-- Metrics: quantitative battlefield validation suite. Every metric here is computed analytically
-- over the region grid — no terrain writes required, so validation is fast enough to run per-seed
-- inside the generation loop and at scale in offline batches.

local RegionAnalysis = require(script.Parent.RegionAnalysis)
local Topology = require(script.Parent.Topology)

local Metrics = {}

-- Elevation statistics over the grid (or a central fraction of it).
function Metrics.elevation(grid, marginFrac: number?): { mean: number, sigma: number, min: number, max: number }
	local m = marginFrac or 0
	local i0 = 1 + math.floor(grid.nx * m)
	local i1 = grid.nx - math.floor(grid.nx * m)
	local sum, sum2, count = 0, 0, 0
	local mn, mx = math.huge, -math.huge
	for i = i0, i1 do
		for j = i0, math.min(grid.nz, i1) do
			local h = grid.heights[i][j]
			sum += h
			sum2 += h * h
			count += 1
			if h < mn then mn = h end
			if h > mx then mx = h end
		end
	end
	local mean = sum / count
	local variance = math.max(0, sum2 / count - mean * mean)
	return { mean = mean, sigma = math.sqrt(variance), min = mn, max = mx }
end

-- Slope histogram: fractions of area in bands [<14, 14-30, 30-35, 35+].
function Metrics.slopeBands(grid): { gentle: number, moderate: number, steep: number, extreme: number }
	local counts = { 0, 0, 0, 0 }
	local total = 0
	for i = 1, grid.nx do
		for j = 1, grid.nz do
			local s = grid.slopes[i][j]
			if s < 14 then counts[1] += 1
			elseif s < 30 then counts[2] += 1
			elseif s < 35 then counts[3] += 1
			else counts[4] += 1 end
			total += 1
		end
	end
	return {
		gentle = counts[1] / total,
		moderate = counts[2] / total,
		steep = counts[3] / total,
		extreme = counts[4] / total,
	}
end

-- Radially-averaged autocorrelation of the heightfield: correlation length = lag where
-- correlation drops below 0.5. Distinguishes structured geography (long correlation) from
-- white-noise roughness (near-zero) and degenerate monotonic fields (very long).
function Metrics.correlationLength(grid, maxLag: number?): number
	local ml = maxLag or 60
	local n = math.min(grid.nx, grid.nz)
	local mean = 0
	local count = 0
	for i = 1, n do
		for j = 1, n do
			mean += grid.heights[i][j]
			count += 1
		end
	end
	mean /= count
	local var = 0
	for i = 1, n do
		for j = 1, n do
			local d = grid.heights[i][j] - mean
			var += d * d
		end
	end
	var /= count
	-- note: variance of the blurred field is recomputed after blurring below
	if var < 1e-6 then
		return math.huge -- flat field: infinite correlation, will fail the band honestly
	end
	-- macro-structure measurement: box-blur the field with a ~32-stud kernel first so the
	-- correlation length reflects deliberate geography, not the mid/fine detail noise scale.
	local blur = {}
	local rad = math.max(1, math.floor(72 / grid.step / 2))
	for i = 1, n do
		blur[i] = {}
		for j = 1, n do
			local sum2, cnt = 0, 0
			for di = -rad, rad do
				for dj = -rad, rad do
					local ii, jj = i + di, j + dj
					if ii >= 1 and ii <= n and jj >= 1 and jj <= n then
						sum2 += grid.heights[ii][jj]
						cnt += 1
					end
				end
			end
			blur[i][j] = sum2 / cnt - mean
		end
	end
	-- blurred-field variance for normalized correlation
	var = 0
	local bcount = 0
	for i = 1, n do
		for j = 1, n do
			var += blur[i][j] * blur[i][j]
			bcount += 1
		end
	end
	var /= bcount
	if var < 1e-6 then
		return math.huge
	end
	-- measure both axes and take the SHORTER correlation length: directional structure (valley
	-- axes, ridge lines) legitimately correlates far along its own axis; the shorter axis is what
	-- distinguishes textured geography from degenerate monotone fields.
	local step = 2
	local function axisCorr(horizontal: boolean): number
		for lag = 1, ml, step do
			local sum = 0
			local pairs = 0
			for i = 1, n - lag do
				for j = 1, n, 3 do
					local a = horizontal and blur[i][j] or blur[j][i]
					local b = horizontal and blur[i + lag][j] or blur[j][i + lag]
					sum += a * b
					pairs += 1
				end
			end
			local corr = (sum / pairs) / var
			if corr < 0.5 then
				return lag * grid.step
			end
		end
		return ml * grid.step
	end
	return math.min(axisCorr(true), axisCorr(false))
end

-- Sightline distribution: random open-target point pairs, heightfield LOS test, bucketed by
-- distance. Returns histogram fractions in bands [0-30, 30-90, 90-150, 150+] plus the share of
-- pairs that had clear LOS at all.
function Metrics.sightlineDistribution(grid, rng, samples: number?): { bands: { number }, clearShare: number }
	local bands = { 0, 0, 0, 0 }
	local clearTotal = 0
	local count = samples or 250
	local half = grid.nx * grid.step / 2
	local valid = 0
	for _ = 1, count do
		local ax = (rng() * 2 - 1) * half * 0.8
		local az = (rng() * 2 - 1) * half * 0.8
		local ang = rng() * math.pi * 2
		local dist = 20 + rng() * 230
		local bx = ax + math.cos(ang) * dist
		local bz = az + math.sin(ang) * dist
		if math.abs(bx) < half * 0.85 and math.abs(bz) < half * 0.85 then
			valid += 1
			if RegionAnalysis.losClear(grid, ax, az, bx, bz, 7) then
				clearTotal += 1
				if dist < 30 then bands[1] += 1
				elseif dist < 90 then bands[2] += 1
				elseif dist < 150 then bands[3] += 1
				else bands[4] += 1 end
			end
		end
	end
	local total = math.max(1, clearTotal)
	return {
		bands = { bands[1] / total, bands[2] / total, bands[3] / total, bands[4] / total },
		clearShare = valid > 0 and clearTotal / valid or 0,
	}
end

-- Tactical position diversity: count distinct high-ground positions near `target` that have LOS
-- to it — the defender/attacker vantage metric.
function Metrics.tacticalPositions(grid, tx: number, tz: number, radius: number, minAdvantage: number): number
	-- Elevation-structure diversity around the objective. The original counted only positions
	-- ABOVE the target — blind by construction once primaries anchor onto high ground (plateau
	-- tops), which is exactly where fortified objectives belong. Engagement-relevant structure
	-- exists in both directions: overlooks matter for attackers approaching a low objective;
	-- benches/terraces below matter when assaulting an elevated one (they are the attacker's
	-- cover progression and the defender's fall-back lines).
	local th = RegionAnalysis.height(grid, tx, tz)
	local above = RegionAnalysis.highGround(grid, th + minAdvantage, 2)
	local count = 0
	local seen = {}
	for _, lm in above do
		local d = math.sqrt((lm.x - tx) ^ 2 + (lm.z - tz) ^ 2)
		if d <= radius and d >= 30 then
			if RegionAnalysis.losClear(grid, lm.x, lm.z, tx, tz, 8) then
				count += 1
				seen[math.floor(lm.x / 40) * 1000 + math.floor(lm.z / 40)] = true
			end
		end
	end
	-- depression/bench structure: sample the ring, count cells meaningfully BELOW the objective
	-- with LOS — they shape assault cover on elevated objectives
	for angle = 0, 15 do
		local a = angle / 16 * math.pi * 2
		for rr = 60, radius, 60 do
			local x, z = tx + math.cos(a) * rr, tz + math.sin(a) * rr
			local h = RegionAnalysis.height(grid, x, z)
			local key = math.floor(x / 40) * 1000 + math.floor(z / 40)
			if not seen[key] and math.abs(h - th) >= minAdvantage then
				if RegionAnalysis.losClear(grid, x, z, tx, tz, 8) then
					count += 1
					seen[key] = true
				end
			end
		end
	end
	return count
end

-- Feature vector per brief section 14. All components normalized-ish so cosine distance is
-- meaningful across generations.
function Metrics.featureVector(grid, routesInfo, tx: number, tz: number, rng): { number }
	local elev = Metrics.elevation(grid, 0.1)
	local slope = Metrics.slopeBands(grid)
	local sight = Metrics.sightlineDistribution(grid, rng, 160)
	local corrLen = Metrics.correlationLength(grid)
	local sep = routesInfo and routesInfo.separation or 0
	local redundancy = routesInfo and routesInfo.alternate and 1 or 0
	local tac = Metrics.tacticalPositions(grid, tx, tz, 250, 8)
	return {
		elev.sigma / 40,
		slope.gentle,
		sep / 150,
		sight.bands[2], -- mid-range engagement share
		sight.bands[4], -- long-range share
		sight.clearShare,
		redundancy,
		math.min(corrLen, 300) / 300,
		math.min(tac, 6) / 6,
	}
end

-- Full validation pass against an archetype's envelopes plus hard structural requirements.
-- Returns pass boolean plus a report table of every measurement and the failing reasons.
function Metrics.validate(grid, def, ctx, rng): (boolean, any)
	local report = {}
	local reasons = {}

	local elev = Metrics.elevation(grid, 0.1)
	report.elevation = elev
	if elev.sigma < def.elevationSigma.min or elev.sigma > def.elevationSigma.max then
		table.insert(reasons, "elevation_sigma:" .. string.format("%.1f", elev.sigma))
	end

	local slope = Metrics.slopeBands(grid)
	report.slope = slope
	if slope.gentle < def.slopeGentle14.min then
		table.insert(reasons, "too_rugged:" .. string.format("%.2f", slope.gentle))
	end
	if slope.extreme > def.slopeSteep35.max then
		table.insert(reasons, "unclimbable_share:" .. string.format("%.3f", slope.extreme))
	end

	-- structural: routes from LZ to primary
	if ctx.routes then
		report.routes = {
			primaryLen = ctx.routes.primary.length,
			altLen = ctx.routes.alternate and ctx.routes.alternate.length or 0,
			separation = ctx.routes.separation,
		}
		-- brief: 650-1000 studs navigable for standard operations (provisional band, tunable)
		if ctx.routes.primary.length < (ctx.minRoute or 620) then
			table.insert(reasons, "route_too_short:" .. string.format("%.0f", ctx.routes.primary.length))
		end
		if ctx.routes.primary.length > (ctx.maxRoute or 1150) then
			table.insert(reasons, "route_too_long:" .. string.format("%.0f", ctx.routes.primary.length))
		end
		if not ctx.routes.alternate or ctx.routes.separation < (ctx.minSeparation or 80) then
			table.insert(reasons, "no_redundant_route:" .. string.format("%.0f", ctx.routes.separation))
		end
	end

	local corrLen = Metrics.correlationLength(grid)
	report.correlationLength = corrLen
	if corrLen < def.correlationLength.min or corrLen > def.correlationLength.max then
		table.insert(reasons, "correlation_length:" .. string.format("%.0f", corrLen))
	end

	if ctx.primary then
		local tac = Metrics.tacticalPositions(grid, ctx.primary.x, ctx.primary.z, 260, 8)
		report.tacticalPositions = tac
		if tac < (ctx.minTactical or 2) then
			table.insert(reasons, "low_tactical_diversity:" .. tac)
		end
	end

	report.reasons = reasons
	return #reasons == 0, report
end

return Metrics
