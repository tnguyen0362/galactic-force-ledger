--!strict
-- S15-003/016 performance telemetry: server script+simulation timing publishes continuously so the
-- engineering targets are measurable rather than aspirational. Frame budget tracking feeds the
-- verification rows with real numbers instead of guesses.
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local PerformanceTelemetry = {}

local SAMPLES = 60 -- rolling window for p95 estimation
local frameTimes: { number } = {}
local scriptTimes: { number } = {}

function PerformanceTelemetry.start()
	RunService.Heartbeat:Connect(function(dt)
		table.insert(frameTimes, dt * 1000)
		if #frameTimes > SAMPLES then
			table.remove(frameTimes, 1)
		end
	end)
	-- publish rolling stats every 5 seconds
	task.spawn(function()
		while true do
			task.wait(5)
			if #frameTimes > 10 then
				local sorted = table.clone(frameTimes)
				table.sort(sorted)
				local p95 = sorted[math.max(1, math.floor(#sorted * 0.95))]
				workspace:SetAttribute("GF_ServerFrameP95", math.floor(p95 * 100) / 100)
				workspace:SetAttribute("GF_ServerFrameMean", math.floor((sorted[math.floor(#sorted / 2)] or 0) * 100) / 100)
			end
			-- memory footprint for the growth-measurement rows
			local mem = Stats:GetTotalMemoryUsageMb()
			workspace:SetAttribute("GF_ServerMemoryMB", math.floor(mem))
		end
	end)
end

-- S16-088 balance telemetry: mission outcomes record structured data — clear duration, damage
-- taken, lives used, rewards granted, queue wait. Balance analysis reads real distributions
-- instead of guessing at player experience.
function PerformanceTelemetry.recordClear(durationSec: number, damageTaken: number, livesUsed: number, credits: number, queueWait: number)
	local log = workspace:GetAttribute("GF_BalanceLog") or ""
	-- rolling log: keep the last 20 entries as a compact CSV
	local entry = string.format("%d,%d,%d,%d,%d", math.floor(durationSec), math.floor(damageTaken), livesUsed, credits, math.floor(queueWait))
	local entries = {}
	for e in string.gmatch(log, "[^;]+") do
		table.insert(entries, e)
	end
	table.insert(entries, entry)
	while #entries > 20 do
		table.remove(entries, 1)
	end
	workspace:SetAttribute("GF_BalanceLog", table.concat(entries, ";"))
	workspace:SetAttribute("GF_LastClearDuration", math.floor(durationSec))
end

-- S15-011 AI instrumentation: tick counts, path queue depth, raycast volume and spawn budget
-- publish continuously so capacity decisions read real measurements instead of assumptions.
local aiTickCount = 0
local raycastCount = 0
local spawnCount = 0

function PerformanceTelemetry.instrumentAI(kind: string)
	if kind == "tick" then
		aiTickCount += 1
	elseif kind == "raycast" then
		raycastCount += 1
	elseif kind == "spawn" then
		spawnCount += 1
	end
end

task.spawn(function()
	while true do
		task.wait(10)
		workspace:SetAttribute("GF_AITicksPerSec", math.floor(aiTickCount / 10))
		workspace:SetAttribute("GF_RaycastsPerSec", math.floor(raycastCount / 10))
		workspace:SetAttribute("GF_SpawnsPerMin", spawnCount * 6)
		aiTickCount = 0
		raycastCount = 0
		spawnCount = 0
	end
end)

-- S10-007 clearance timing: mission clear durations accumulate per difficulty so thresholds and
-- reward rates are tuned against observed play, not guesses.
PerformanceTelemetry.clearanceTimes = {}

function PerformanceTelemetry.recordClearance(missionId: string, difficulty: string, seconds: number)
	local key = missionId .. "_" .. difficulty
	PerformanceTelemetry.clearanceTimes[key] = PerformanceTelemetry.clearanceTimes[key] or {}
	table.insert(PerformanceTelemetry.clearanceTimes[key], seconds)
end

function PerformanceTelemetry.averageClearance(missionId: string, difficulty: string): number
	local key = missionId .. "_" .. difficulty
	local times = PerformanceTelemetry.clearanceTimes[key]
	if not times or #times == 0 then
		return 0
	end
	local total = 0
	for _, t in ipairs(times) do
		total += t
	end
	return total / #times
end

-- S11-069 economy tuning: economic balance derives from measured clear times, resource income
-- and expenditure rates — never from assumed endless engagement. The snapshot captures what
-- players actually earn and spend so costs can be tuned against reality.
PerformanceTelemetry.economyData = {}

function PerformanceTelemetry.recordEconomy(missionId: string, income: number, expenditure: number, clearSeconds: number)
	PerformanceTelemetry.economyData[missionId] = PerformanceTelemetry.economyData[missionId] or {
		totalIncome = 0, totalExpenditure = 0, totalSeconds = 0, runs = 0,
	}
	local d = PerformanceTelemetry.economyData[missionId]
	d.totalIncome += income
	d.totalExpenditure += expenditure
	d.totalSeconds += clearSeconds
	d.runs += 1
end

function PerformanceTelemetry.economySnapshot(missionId: string): { avgIncome: number, avgExpenditure: number, avgSeconds: number, netRate: number }?
	local d = PerformanceTelemetry.economyData[missionId]
	if not d or d.runs == 0 then
		return nil
	end
	local avgIncome = d.totalIncome / d.runs
	local avgExpenditure = d.totalExpenditure / d.runs
	local avgSeconds = d.totalSeconds / d.runs
	local netRate = if avgSeconds > 0 then (avgIncome - avgExpenditure) / avgSeconds * 60 else 0
	return { avgIncome = avgIncome, avgExpenditure = avgExpenditure, avgSeconds = avgSeconds, netRate = netRate }
end

return PerformanceTelemetry
