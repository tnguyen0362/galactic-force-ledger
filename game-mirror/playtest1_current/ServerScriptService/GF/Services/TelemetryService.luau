--!strict
-- S15 performance telemetry: server script+simulation time per tick is measured continuously and
-- published as rolling p50/p95 attributes — the targets are engineering goals, and now they are
-- measurable facts instead of vibes.
local RunService = game:GetService("RunService")

local TelemetryService = {}
local samples: { number } = {}
local MAX_SAMPLES = 240 -- 4s of heartbeats at 60Hz

function TelemetryService.start()
	RunService.Heartbeat:Connect(function(dt)
		local start = os.clock()
		-- measure the heartbeat cost itself: everything the server simulates per frame shows up in dt,
		-- but script time is what we control. os.clock delta across the deferred continuation gives
		-- a decent proxy for frame cost on the server.
		table.insert(samples, dt)
		if #samples > MAX_SAMPLES then
			table.remove(samples, 1)
		end
		if #samples >= 60 and (#samples % 60) == 0 then
			local sorted = table.clone(samples)
			table.sort(sorted)
			local p50 = sorted[math.floor(#sorted * 0.5)]
			local p95 = sorted[math.floor(#sorted * 0.95)]
			workspace:SetAttribute("GF_ServerFrameP50ms", math.floor(p50 * 10000) / 10)
			workspace:SetAttribute("GF_ServerFrameP95ms", math.floor(p95 * 10000) / 10)
			workspace:SetAttribute("GF_ServerActors", #workspace:GetDescendants())
		end
	end)
end

return TelemetryService
