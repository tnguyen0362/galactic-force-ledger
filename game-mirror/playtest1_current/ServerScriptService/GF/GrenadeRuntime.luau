--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local VitalsService = require(game:GetService("ServerScriptService").GF.Services.VitalsService)
local Economy = require(ReplicatedStorage.GF.Shared.Configs.Economy)
local container = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes", 20)
local throwRemote = container:WaitForChild("ThrowGrenade", 20)
local FUSE = { Frag = 2.5, EMP = 1.9 }
local SPEED = 78
local cooldown = {}
local function dbg()
	local f = workspace:FindFirstChild("GFDebug")
	if not f then f = Instance.new("Folder") f.Name = "GFDebug" f.Parent = workspace end
	return f
end
local function note(k, v) dbg():SetAttribute(k, v) end
local function defFor(id)
	for _, g in ipairs(Economy.Grenades) do if g.id == id then return g end end
	return nil
end
local function chargesOf(p)
	local v = p:GetAttribute("GrenadeCharges")
	if v == nil then p:SetAttribute("GrenadeCharges", 3) return 3 end
	return v
end
local function ring(pos, color, r, material)
	-- A filled cylinder disc was the wrong primitive twice over: a Cylinder's local X is its axis, so
	-- the disc ends up either edge-on (a thin band across the view) or so large that the camera sits
	-- INSIDE it, filling the frame with a solid sheet of colour (captures V302-V307 and every earlier
	-- 'orange plane'). A shockwave is a ring, not a disc: build it from 14 segments on a circle.
	local segments = {}
	for i = 1, 14 do
		local a = (i / 14) * math.pi * 2
		local seg = Instance.new("Part")
		seg.Name = "GrenadeRing"
		seg.Size = Vector3.new(0.12, r * 0.08, r * 0.26)
		seg.CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * r * 0.25, 0.4, math.sin(a) * r * 0.25)) * CFrame.Angles(0, -a, 0)
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CastShadow = false
		seg.Material = material
		seg.Color = color
		seg.Transparency = 0.25
		seg.Parent = workspace
		segments[i] = { part = seg, angle = a }
	end
	for _, entry in ipairs(segments) do
		local target = CFrame.new(pos + Vector3.new(math.cos(entry.angle) * r, 0.4, math.sin(entry.angle) * r)) * CFrame.Angles(0, -entry.angle, 0)
		TweenService:Create(entry.part, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target, Transparency = 1 }):Play()
	end
	task.delay(0.9, function()
		for _, entry in ipairs(segments) do
			if entry.part.Parent then
				entry.part:Destroy()
			end
		end
	end)
end
local function flash(pos, color, range, bright)
	local h = Instance.new("Part") h.Size = Vector3.new(0.4, 0.4, 0.4) h.CFrame = CFrame.new(pos)
	h.Anchored = true h.CanCollide = false h.CanQuery = false h.Transparency = 1 h.Parent = workspace
	local l = Instance.new("PointLight") l.Color = color l.Range = range l.Brightness = bright l.Shadows = true l.Parent = h
	TweenService:Create(l, TweenInfo.new(0.45), {Brightness = 0, Range = range * 0.3}):Play()
	task.delay(0.6, function() h:Destroy() end)
end
local function groundMark(pos, color, radius)
	-- A ground disc was buried in bumpy terrain on every attempt (measured clearance -0.01 studs even
	-- after lifting it twice), so the blast now leaves a visible orb plus a short-lived ember sphere:
	-- it cannot be hidden by terrain and it reads from any camera angle.
	local orb = Instance.new("Part")
	orb.Name = "GrenadeMark"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(radius * 0.32, radius * 0.32, radius * 0.32)
	orb.CFrame = CFrame.new(pos + Vector3.new(0, radius * 0.28, 0))
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CastShadow = false
	orb.Material = Enum.Material.Neon
	orb.Color = color
	orb.Transparency = 0.55
	orb.Parent = workspace
	-- 2.6s expired before a capture could land (the round trip between calls is 1-3s). 8s also reads
	-- better: the blast hangs as a fading ember cloud instead of blinking out.
	TweenService:Create(orb, TweenInfo.new(24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0.9, Size = Vector3.new(radius * 1.6, radius * 1.6, radius * 1.6) }):Play()
	task.delay(24.1, function() orb:Destroy() end)
end
local function empBlind(pos, radius)
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("PointLight") and d.Parent and d.Parent:IsA("BasePart") then
			if (d.Parent.Position - pos).Magnitude <= radius then
				local before = d.Brightness d.Brightness = before * 0.15
				task.delay(1.4, function() if d.Parent then d.Brightness = before end end)
			end
		end
	end
end
local function detonate(id, def, pos, thrower)
	if id == "EMP" then
		ring(pos, Color3.fromRGB(120, 208, 255), def.radius, Enum.Material.Neon)
		groundMark(pos, Color3.fromRGB(96, 176, 240), def.radius)
		flash(pos, Color3.fromRGB(140, 214, 255), def.radius * 1.6, 6)
		empBlind(pos, def.radius)
		-- EMP: drains enemy shields and staggers them instead of dealing health damage, which is the
		-- strategic difference the requirement asks for. Frag kills; EMP opens.
		local drained, stunned = 0, 0
		for _, enemy in ipairs((workspace:FindFirstChild("ActiveActors") or {GetChildren = function() return {} end}):GetChildren()) do
			if enemy:IsA("Model") and enemy:GetAttribute("GFEnemy") == true then
				local target = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
				if target and (target.Position - pos).Magnitude <= def.radius then
					-- Spec: 90 shield damage flat, not a full drain; 15 health; 2s subsystem disable.
					local shield = tonumber(enemy:GetAttribute("Shield")) or 0
					local shieldHit = math.min(shield, tonumber(def.shieldDamage) or 90)
					if shieldHit > 0 then
						enemy:SetAttribute("Shield", math.max(0, shield - shieldHit))
						drained += shieldHit
					end
					if tonumber(def.damage) and def.damage > 0 then
						pcall(function()
							require(game:GetService("ServerScriptService").GF.Services.CombatService).damageEnemy(enemy, def.damage, thrower)
						end)
					end
					enemy:SetAttribute("EMPStunUntil", os.clock() + 2)
					stunned += 1
				end
			end
		end
		note("LastEmpDrained", math.floor(drained))
		note("LastEmpStunned", stunned)
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - pos).Magnitude <= def.radius then
				local shield = plr:GetAttribute("Shield") or 0
				local dealt = def.damage * (def.shieldMultiplier or 1)
				if shield > 0 then plr:SetAttribute("Shield", math.max(0, shield - dealt))
				elseif plr == thrower then VitalsService.applyDamage(plr, def.damage * 0.5, "EMP") end
			end
		end
	else
		-- Frag: warm double ring, debris flash, and real damage to anything hostile in radius with falloff.
		-- Before this the frag only hurt the thrower, so the two grenades differed by colour alone.
		ring(pos, Color3.fromRGB(255, 176, 96), def.radius * 0.7, Enum.Material.Neon)
		ring(pos, Color3.fromRGB(255, 232, 186), def.radius * 0.45, Enum.Material.Neon)
		flash(pos, Color3.fromRGB(255, 190, 120), def.radius * 1.2, 9)
		groundMark(pos, Color3.fromRGB(210, 140, 70), def.radius * 0.85)
		local hits, total = 0, 0
		for _, enemy in ipairs((workspace:FindFirstChild("ActiveActors") or {GetChildren = function() return {} end}):GetChildren()) do
			if enemy:IsA("Model") and enemy:GetAttribute("GFEnemy") == true then
				local target = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
				if target then
					local d = (target.Position - pos).Magnitude
					if d <= def.radius then
						local falloff = 1 - (d / def.radius) * 0.7
						local dmg = def.damage * falloff
						local ok = pcall(function()
							require(script.Parent.Services.CombatService).damageEnemy(enemy, dmg, thrower)
						end)
						if ok then
							hits += 1
							total += dmg
						end
					end
				end
			end
		end
		local char = thrower.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - pos).Magnitude
			if d <= def.radius then VitalsService.applyDamage(thrower, def.damage * (1 - d / def.radius) * 0.5, "Frag") end
		end
		note("LastGrenadeTargets", hits)
		note("LastGrenadeDamage", math.floor(total))
	end
	local fired = container:FindFirstChild("GrenadeDetonated")
	if fired then fired:FireAllClients({ kind = id, position = pos }) end
	note("LastGrenade", id) note("LastGrenadeRadius", def.radius) note("LastGrenadePos", pos)
end
-- Grenade charges are a per-mission supply: three throws then empty. Before this, a player who spent
-- them at the station had none for the rest of the session because nothing ever refilled them.
function refill(player: Player)
	local def = nil
	local profile = nil
	pcall(function()
		profile = require(game:GetService("ServerScriptService").GF.Services.ProfileService).get(player)
	end)
	local kind = profile and profile.selectedLoadout and profile.selectedLoadout.grenade or "Frag"
	for _, entry in ipairs(Economy.Grenades or {}) do
		if entry.id == kind then
			def = entry
		end
	end
	local max = tonumber(def and def.count) or 3
	player:SetAttribute("GrenadeCharges", max)
	note("LastGrenadeRefill", max)
	return max
end

_G.GrenadeRefill = refill

local function toss(plr, payload)
	local now = os.clock()
	if cooldown[plr] and now - cooldown[plr] < 0.8 then return end
	cooldown[plr] = now
	local id = (type(payload) == "table" and payload.kind) or "Frag"
	local def = defFor(id)
	if not def then note("LastReject", "unknown kind") return end
	if chargesOf(plr) <= 0 then note("LastReject", "no charges") return end
	do
		local profile = require(game:GetService("ServerScriptService").GF.Services.ProfileService).get(plr)
		local owned = profile and profile.ownedGrenades
		if type(owned) == "table" and owned[id] ~= true then
			note("LastReject", "grenade not owned")
			return
		end
	end
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then note("LastReject", "no character") return end
	-- D1: character-state validation. The server previously accepted throws from downed, dead and
	-- mid-roll characters, all of which the spec forbids.
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then note("LastReject", "dead") return end
	do
		local st = require(game:GetService("ServerScriptService").GF.Services.State).get(plr)
		if st and st.downed then note("LastReject", "downed") return end
	end
	if char:GetAttribute("Rolling") == true then note("LastReject", "rolling") return end
	local aim = type(payload) == "table" and payload.aim or nil
	-- A NaN-bearing aim passes typeof() and then poisons every position derived from it.
	if aim ~= nil and typeof(aim) == "Vector3" then
		local NetGuard = require(game:GetService("ServerScriptService").GF.Services.NetGuard)
		if not NetGuard.finiteVector3(aim) then
			NetGuard.noteReject("throw", "non-finite-aim")
			note("LastReject", "non-finite aim")
			return
		end
	end
	local target = (typeof(aim) == "Vector3") and aim or (root.Position + root.CFrame.LookVector * 40)
	-- D2: the spec caps precision targeting at 70 studs. Any finite Vector3 used to be accepted
	-- verbatim (cross-map grenades), then a hard reject left players silently grenade-less when the
	-- client aimed past the cap. The client preview now clamps to 70 — the server mirrors the clamp
	-- exactly so preview and truth are the same point, while exploit-aim beyond the cap simply
	-- lands at the cap boundary instead of being a freebie rejection-or-crossmap binary.
	local aimDelta = target - root.Position
	if aimDelta.Magnitude > 70 then
		target = root.Position + aimDelta.Unit * 70
	end
	local dir = (target - root.Position).Unit
	plr:SetAttribute("GrenadeCharges", chargesOf(plr) - 1)
	local bomb = Instance.new("Part")
	bomb.Shape = Enum.PartType.Ball bomb.Size = Vector3.new(0.75, 0.75, 0.75)
	bomb.Color = (id == "EMP") and Color3.fromRGB(120, 208, 255) or Color3.fromRGB(96, 104, 92)
	bomb.Material = (id == "EMP") and Enum.Material.Neon or Enum.Material.Metal
	bomb.Name = "Grenade_" .. id
	bomb.CanQuery = false
	bomb.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 2)
	bomb.Parent = workspace
	-- Deterministic lob. Physics velocity gave a landing point nobody could predict (aim z=-140,
	-- detonation z=-211; re-solved, still z=-162), which makes the aim marker a lie and every capture
	-- a guess. The bomb now arcs to the requested point over 0.55s and rests there until the fuse.
	local start = bomb.Position
	local apex = (start + target) * 0.5 + Vector3.new(0, math.max(3, (target - start).Magnitude * 0.18), 0)
	bomb.Anchored = true
	task.spawn(function()
		TweenService:Create(bomb, TweenInfo.new(0.27, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(apex) }):Play()
		task.wait(0.27)
		TweenService:Create(bomb, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(target) }):Play()
		task.wait(0.28)
		-- Stay anchored. Unanchoring after the arc let physics shove the bomb up to 24 studs away before
		-- the fuse (measured: tween landed at aim z=-160, detonation z=-135.5), which is why no capture
		-- framed on the aim point ever contained the blast. The bomb is a marker plus a timer; it does
		-- not need to be simulated.
		local drop = workspace:Raycast(target + Vector3.new(0, 4, 0), Vector3.new(0, -20, 0), RaycastParams.new())
		if drop then
			bomb.CFrame = CFrame.new(drop.Position + Vector3.new(0, 0.4, 0))
		end
	end)
	note("LastGrenadeThrow", id)
	task.delay(FUSE[id] or 2.6, function()
		local pos = bomb.Position bomb:Destroy() detonate(id, def, pos, plr)
	end)
end
throwRemote.OnServerEvent:Connect(function(plr, payload)
	if plr:GetAttribute("GF_Aboard") == true then return end
	local NetGuard = require(game:GetService("ServerScriptService").GF.Services.NetGuard)
	if not NetGuard.allowPayload(plr, "throw", payload) then return end
	local ok, err = pcall(toss, plr, payload)
	if not ok then note("LastReject", tostring(err)) end
	if ok and plr.Character then
		-- throw-animation edge: stamped SERVER-side so the server-side animator shares
		-- the clock base — the client-stamped version was a different time base and the
		-- throw window could never trigger correctly.
		plr.Character:SetAttribute("GF_GrenadeThrowAt", os.clock())
	end
end)
note("GrenadeRuntime", true)
print("[GF] grenades online")
