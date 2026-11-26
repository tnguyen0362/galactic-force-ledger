--!strict
-- GFDevBridge — Studio-only experiment bridge into the TRUE server VM.
-- The MCP execute_luau channel runs in the Assistant plugin sandbox, which has its OWN module
-- registry: anything spawned from there never registers in the game VM's module state
-- (E-001 discovery 2026-11-27: MCP-spawned enemies never tick — actors tables are per-VM).
-- This bridge boots inside the game VM and dispatches verb commands posted to GF_DevCmd.
-- Protocol: workspace attribute GF_DevCmd = "verb|arg|arg|..." ; result string in GF_DevResult.
-- Extend the vocabulary by redeploying this script between sessions.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local EnemyService = require(ServerScriptService.GF.Services.EnemyService)

local function parseVec(s: string): Vector3?
	local parts = string.split(s, ",")
	if #parts ~= 3 then
		return nil
	end
	local x, y, z = tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])
	if not x or not y or not z then
		return nil
	end
	return Vector3.new(x, y, z)
end

local function playerRoot(): BasePart?
	local plr = Players:GetPlayers()[1]
	local char = plr and plr.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- experiment state
local healConn: RBXScriptConnection? = nil
local moveConn: RBXScriptConnection? = nil

local verbs = {}

verbs.ping = function()
	return "pong"
end

-- spawn|EnemyId|x,y,z  — spawn through the REAL game-VM EnemyService
verbs.spawn = function(enemyId: string, posStr: string)
	local pos = parseVec(posStr)
	if not pos then
		return "bad pos"
	end
	local m = EnemyService.spawn(enemyId, pos)
	if not m then
		return "spawn nil"
	end
	-- face the player if present
	local proot = playerRoot()
	local eroot = m.PrimaryPart
	if proot and eroot then
		m:PivotTo(CFrame.lookAt(eroot.Position, Vector3.new(proot.Position.X, eroot.Position.Y, proot.Position.Z)))
	end
	return "spawned " .. m.Name
end

-- clearenemies — destroy all live GFEnemy models within radius of the player (default huge)
verbs.clearenemies = function(radiusStr: string?)
	local radius = tonumber(radiusStr or "") or 1e9
	local proot = playerRoot()
	local center = proot and proot.Position or Vector3.zero
	local n = 0
	for _, m in ipairs(workspace:GetDescendants()) do
		if m:IsA("Model") and m:GetAttribute("GFEnemy") then
			local p = m.PrimaryPart and m.PrimaryPart.Position
			if p and (p - center).Magnitude <= radius then
				m:Destroy()
				n += 1
			end
		end
	end
	return "cleared " .. n
end

-- teleport|x,y,z
verbs.teleport = function(posStr: string)
	local pos = parseVec(posStr)
	if not pos then
		return "bad pos"
	end
	local plr = Players:GetPlayers()[1]
	if plr and plr.Character then
		plr.Character:PivotTo(CFrame.new(pos))
		return "teleported"
	end
	return "no character"
end

-- networkown — server takes physics ownership of the player assembly (required for server-driven movement)
verbs.networkown = function()
	local proot = playerRoot()
	if not proot then
		return "no root"
	end
	local ok, err = pcall(function()
		proot:SetNetworkOwner(nil)
	end)
	return ok and "owned" or ("err " .. tostring(err):sub(1, 60))
end

-- healon / healoff — invulnerability loop for measurement windows
verbs.healon = function()
	if healConn then
		return "already"
	end
	healConn = RunService.Heartbeat:Connect(function()
		local plr = Players:GetPlayers()[1]
		local hum = plr and plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health < hum.MaxHealth then
			hum.Health = hum.MaxHealth
		end
	end)
	return "heal on"
end

verbs.healoff = function()
	if healConn then
		healConn:Disconnect()
		healConn = nil
	end
	return "heal off"
end

-- movepattern|speed|strafeSeconds|stillSeconds|halfPeriod — server-driven oscillating strafe:
-- speed studs/s perpendicular to nearest-enemy bearing, square-wave reversal every halfPeriod,
-- alternating strafeSeconds of movement with stillSeconds of standing. movepattern|0 stops.
verbs.movepattern = function(speedStr: string, strafeStr: string, stillStr: string, halfStr: string)
	if moveConn then
		moveConn:Disconnect()
		moveConn = nil
	end
	local speed = tonumber(speedStr) or 0
	if speed <= 0 then
		return "movement off"
	end
	local strafeT = tonumber(strafeStr) or 20
	local stillT = tonumber(stillStr) or 10
	local halfP = tonumber(halfStr) or 0.6
	local t0 = os.clock()
	moveConn = RunService.Heartbeat:Connect(function()
		local proot = playerRoot()
		if not proot then
			return
		end
		local elapsed = os.clock() - t0
		local cycleT = elapsed % (strafeT + stillT)
		if cycleT >= strafeT then
			return -- stationary window: no horizontal drive
		end
		-- nearest enemy bearing
		local bestD, bestPos = math.huge, nil
		for _, m in ipairs(workspace:GetDescendants()) do
			if m:IsA("Model") and m:GetAttribute("GFEnemy") and m:GetAttribute("Dead") ~= true then
				local p = m.PrimaryPart and m.PrimaryPart.Position
				if p then
					local d = (p - proot.Position).Magnitude
					if d < bestD then
						bestD = d
						bestPos = p
					end
				end
			end
		end
		if not bestPos then
			return
		end
		local toEnemy = (bestPos - proot.Position) * Vector3.new(1, 0, 1)
		if toEnemy.Magnitude < 1 then
			return
		end
		local perp = Vector3.new(-toEnemy.Unit.Z, 0, toEnemy.Unit.X)
		local sign = (elapsed % (halfP * 2)) < halfP and 1 or -1
		local v = perp * sign * speed
		proot.AssemblyLinearVelocity = Vector3.new(v.X, proot.AssemblyLinearVelocity.Y, v.Z)
	end)
	return string.format("movement on speed=%.1f strafe=%.0fs still=%.0fs half=%.2fs", speed, strafeT, stillT, halfP)
end

-- platform|x,y,z|size — build a flat test platform
verbs.platform = function(posStr: string, sizeStr: string?)
	local pos = parseVec(posStr)
	if not pos then
		return "bad pos"
	end
	local size = tonumber(sizeStr or "") or 300
	local old = workspace:FindFirstChild("E001Platform")
	if old then
		old:Destroy()
	end
	local p = Instance.new("Part")
	p.Name = "E001Platform"
	p.Size = Vector3.new(size, 2, size)
	p.Position = pos - Vector3.new(0, 1, 0)
	p.Anchored = true
	p.Color = Color3.fromRGB(120, 120, 120)
	p.Material = Enum.Material.Concrete
	p.Parent = workspace
	-- cover wall for intermittent-exposure validation: the cover_intermittent policy strafes
	-- behind/past this wall so LOS actually interrupts (v3 gap-uncertainty mechanics testing)
	local oldWall = workspace:FindFirstChild("E001CoverWall")
	if oldWall then
		oldWall:Destroy()
	end
	local w = Instance.new("Part")
	w.Name = "E001CoverWall"
	w.Size = Vector3.new(16, 14, 2)
	-- offset toward +z (enemy spawn direction): player strafing along x passes behind it
	w.Position = pos + Vector3.new(0, 6, 12)
	w.Anchored = true
	w.Color = Color3.fromRGB(90, 90, 110)
	w.Material = Enum.Material.Concrete
	w.Parent = workspace
	return "platform built"
end

-- difficulty|Normal — set operation difficulty attribute
verbs.difficulty = function(d: string)
	workspace:SetAttribute("GF_OperationDifficulty", d)
	return "difficulty " .. d
end

-- drain — pull telemetry events through the game-VM buffer and return compact rows
verbs.drain = function(nStr: string?)
	local drain = game:GetService("ReplicatedStorage"):FindFirstChild("GFTelemetryDrain")
	if not drain then
		return "no drain bindable"
	end
	local maxN = tonumber(nStr) or 2000
	local events = drain:Invoke(maxN)
	local rows = {}
	for _, ev in ipairs(events) do
		if ev.eventType == "shot_fired" or ev.eventType == "hit_registered" or ev.eventType == "enemy_killed" then
			local row = ev.eventType:upper()
			for _, k in ipairs({"weaponId", "zone", "distance", "falloffApplied", "damageAfterFalloff", "weakMult", "targetArchetype", "killed", "ads", "ammoAfter", "archetype"}) do
				if ev[k] ~= nil then
					row = row .. ";" .. k .. "=" .. tostring(ev[k])
				end
			end
			table.insert(rows, row)
		elseif ev.eventType == "enemy_attack_hit" or ev.eventType == "enemy_attack_miss" then
			local row = string.format("%s;d=%.1f;sig=%.2f;sf=%.2f;sa=%.2f;sm=%.2f;so=%.2f;ss=%.2f;err=%.2f;q=%.2f;vel=%.1f;tv=%.1f;roll=%s;blk=%s",
				ev.eventType == "enemy_attack_hit" and "HIT" or "MISS",
				ev.distance or -1, ev.sigmaFinal or -1, ev.sigmaFloor or -1, ev.sigmaAcquisition or -1,
				ev.sigmaMotion or -1, ev.sigmaObsUnc or -1, ev.sigmaSuppression or -1,
				ev.aimErrorMag or -1, ev.acquisitionQ or -1, ev.targetVelocityMag or -1,
				ev.targetTransverseSpeed or -1, tostring(ev.rolling), tostring(ev.blocked))
			row = row .. string.format(";t=%.2f;tm=%s", ev.serverTimestamp or -1, tostring(ev.trackingModel or "?"))
			table.insert(rows, row)
		end
	end
	if #rows == 0 then
		return "empty"
	end
	return table.concat(rows, string.char(10))
end

-- actorprobe — readback of game-VM actor state for verification
verbs.actorprobe = function()
	local actors = EnemyService.debugActors()
	local n, parentless = 0, 0
	local targetN = 0
	for m, a in pairs(actors) do
		n += 1
		if not m.Parent then
			parentless += 1
		end
		if a.target then
			targetN += 1
		end
	end
	return string.format("actors=%d parentless=%d targeting=%d ticked=%s", n, parentless, targetN, tostring(workspace:GetAttribute("GF_AITicked")))
end

task.spawn(function()
	while true do
		task.wait(0.25)
		local cmd = workspace:GetAttribute("GF_DevCmd")
		if type(cmd) == "string" and #cmd > 0 then
			workspace:SetAttribute("GF_DevCmd", "")
			local args = string.split(cmd, "|")
			local verb = table.remove(args, 1)
			-- sequence correlation: commands may carry "SEQ<n>" as first arg — echo it in the
			-- result so clients can match responses to their own command despite transport lag
			local seq = ""
			if args[1] and string.match(args[1], "^SEQ%d+$") then
				seq = table.remove(args, 1) .. "|"
			end
			local fn = verb and verbs[verb]
			if fn then
				local ok, res = pcall(fn, table.unpack(args))
				workspace:SetAttribute("GF_DevResult", seq .. (ok and ("OK|" .. tostring(res)) or ("ERR|" .. tostring(res):sub(1, 250))))
			else
				workspace:SetAttribute("GF_DevResult", "BADVERB|" .. tostring(verb))
			end
		end
	end
end)
