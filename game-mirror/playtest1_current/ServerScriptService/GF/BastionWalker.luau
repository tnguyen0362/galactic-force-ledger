--!strict
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Vitals = require(script.Parent.Services.VitalsService)
local Bastion = {}
local active = {}
local FXFolder = nil
local function fxFolder()
	if FXFolder and FXFolder.Parent then return FXFolder end
	FXFolder = workspace:FindFirstChild("GF_FX")
	if not FXFolder then
		FXFolder = Instance.new("Folder")
		FXFolder.Name = "GF_FX"
		FXFolder.Parent = workspace
	end
	return FXFolder
end
local DARK = Color3.fromRGB(46, 50, 58)
local STEEL = Color3.fromRGB(96, 106, 120)
local RUST = Color3.fromRGB(112, 74, 56)
local AMBER = Color3.fromRGB(255, 176, 64)
local function part(model, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or DARK
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Parent = model
	return p
end
local function weakpoint(model, name, size, cf, mult)
	local p = part(model, name, size, cf, AMBER, Enum.Material.Neon)
	p:SetAttribute("WeakPoint", mult)
	p:SetAttribute("WeakGlow", true)
	return p
end
function Bastion.build(position)
	local model = Instance.new("Model")
	model.Name = "BastionWalker"
	local base = CFrame.new(position)
	local core = part(model, "Core", Vector3.new(11, 7.5, 13), base * CFrame.new(0, 11.5, 0), DARK)
	core:SetAttribute("Armor", 0.35)
	core:SetAttribute("ArmorFactor", 0.65)
	model.PrimaryPart = core
	part(model, "Hull", Vector3.new(12.5, 3.2, 11), base * CFrame.new(0, 15.6, -0.6), STEEL)
	part(model, "Spine", Vector3.new(9, 1.6, 15), base * CFrame.new(0, 18.2, 0), DARK)
	part(model, "Cockpit", Vector3.new(7.4, 4.6, 6.2), base * CFrame.new(0, 12.4, 7.4), STEEL)
	part(model, "Visor", Vector3.new(6.6, 1.1, 0.5), base * CFrame.new(0, 13.4, 10.4), AMBER, Enum.Material.Neon)
	part(model, "Mantlet", Vector3.new(3.4, 2.2, 2), base * CFrame.new(0, 10.6, 10.2), RUST)
	part(model, "BarrelL", Vector3.new(1.1, 1.1, 6.5), base * CFrame.new(-2.2, 11.2, 13.6), DARK)
	part(model, "BarrelR", Vector3.new(1.1, 1.1, 6.5), base * CFrame.new(2.2, 11.2, 13.6), DARK)
	local rack = part(model, "MortarRack", Vector3.new(5.4, 1.8, 4), base * CFrame.new(0, 19.5, -2), RUST)
	rack:SetAttribute("ComponentHP", 600)
	rack:SetAttribute("ComponentId", "Mortar")
	for i = -1, 1 do
		part(model, "MortarTube" .. tostring(i), Vector3.new(1.2, 1.2, 3.4), base * CFrame.new(i * 1.7, 20.4, -1), DARK)
	end
	local emitter = part(model, "Emitter", Vector3.new(2.6, 2.6, 2.6), base * CFrame.new(0, 9.2, -8.2), AMBER, Enum.Material.Neon)
	emitter:SetAttribute("ComponentHP", 450)
	emitter:SetAttribute("ComponentId", "Laser")
	part(model, "RadiatorFrame", Vector3.new(6, 4.6, 1), base * CFrame.new(0, 11.4, -7.6), RUST)
	weakpoint(model, "WeakPoint_Rear", Vector3.new(4.6, 3.4, 0.8), base * CFrame.new(0, 11.4, -8.3), 2.0)
	local legs = {}
	for _, side in ipairs({ -1, 1 }) do
		for _, front in ipairs({ 1, -1 }) do
			local x = side * 7.2
			local z = front * 4.6
			local thigh = part(model, "Thigh" .. side .. front, Vector3.new(2.2, 6.5, 2.2), base * CFrame.new(x, 10, z), STEEL)
			local shin = part(model, "Shin" .. side .. front, Vector3.new(1.7, 5.5, 1.7), base * CFrame.new(x * 1.25, 5, z * 1.15), DARK)
			local foot = part(model, "Foot" .. side .. front, Vector3.new(3.6, 1.1, 4.6), base * CFrame.new(x * 1.3, 1.6, z * 1.2), DARK)
			part(model, "ArmorPlate" .. side .. front, Vector3.new(2.8, 3.6, 0.7), base * CFrame.new(x * 1.06, 10.6, z * 1.4), RUST)
			thigh:SetAttribute("ox", x)
			thigh:SetAttribute("oz", z)
			shin:SetAttribute("ox", x * 1.25)
			shin:SetAttribute("oz", z * 1.15)
			foot:SetAttribute("ox", x * 1.3)
			foot:SetAttribute("oz", z * 1.2)
			table.insert(legs, { thigh = thigh, shin = shin, foot = foot, phase = (side + 1) * 1.5 + (front + 1) * 0.8 })
			if front == 1 then
				weakpoint(model, "WeakPoint_Joint" .. (side == -1 and "L" or "R"), Vector3.new(1.9, 1.9, 1.9), base * CFrame.new(x * 1.02, 12.6, z), 2.0)
			end
		end
	end
	model:SetAttribute("Health", 3600)
	model:SetAttribute("MaxHealth", 3600)
	model:SetAttribute("Shield", 0)
	model:SetAttribute("Dead", false)
	model:SetAttribute("Boss", true)
	model:SetAttribute("Phase", 1)
	model:SetAttribute("Stagger", 0)
	model:SetAttribute("WeakDamage", 0)
	-- E1: bosses must be ordinary damage targets. Without GFEnemy + ActiveActors parenting the
	-- hitscan resolver and every explosion/ability scanner were blind to the boss entirely.
	model:SetAttribute("GFEnemy", true)
	model:SetAttribute("EnemyId", "BastionWalker")
	model:SetAttribute("Tier", "Boss")
	do
		local folder = workspace:FindFirstChild("ActiveActors")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "ActiveActors"
			folder.Parent = workspace
		end
		model.Parent = folder
	end
	return model, legs
end
local function groundAt(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _, m in ipairs(active) do params.FilterDescendantsInstances = { m.model } end
	local hit = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position.Y or pos.Y
end
local function alivePlayers()
	local list = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if ch and hum and hum.Health > 0 then
			local root = ch:FindFirstChild("HumanoidRootPart")
			if root then table.insert(list, { player = pl, root = root }) end
		end
	end
	return list
end
local function blast(center, radius, damage, source)
	for _, entry in ipairs(alivePlayers()) do
		local d = (entry.root.Position - center).Magnitude
		if d <= radius then
			local falloff = 1 - (d / radius) * 0.45
			Vitals.applyDamage(entry.player, math.floor(damage * falloff), source)
		end
	end
end
local function marker(center, radius, life, color)
	local ring = Instance.new("Part")
	ring.Name = "BossTelegraph"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.55
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Parent = fxFolder()
	task.delay(life, function()
		if ring.Parent then ring:Destroy() end
	end)
	return ring
end
local function beam(from, to, life, color)
	local dist = (to - from).Magnitude
	local p = Instance.new("Part")
	p.Name = "BossBeam"
	p.Size = Vector3.new(0.8, 0.8, dist)
	p.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -dist / 2)
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Parent = fxFolder()
	task.delay(life, function()
		if p.Parent then p:Destroy() end
	end)
	return p
end
local function explode(pos, radius, color)
	local burst = Instance.new("Part")
	burst.Name = "BossBlast"
	burst.Shape = Enum.PartType.Ball
	burst.Size = Vector3.new(radius, radius, radius)
	burst.CFrame = CFrame.new(pos)
	burst.Color = color
	burst.Material = Enum.Material.Neon
	burst.Transparency = 0.25
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.Parent = fxFolder()
	-- Hard deadline independent of the expand loop: when the boss is torn down mid-animation the
	-- spawning coroutine dies with it and these parts used to survive forever as translucent orange
	-- spheres. Three of them were found enclosing the station spawn.
	burst:SetAttribute("GFVfxBorn", os.clock())
	task.delay(0.9, function() if burst.Parent then burst:Destroy() end end)
	task.spawn(function()
		for i = 1, 10 do
			burst.Size = burst.Size + Vector3.new(radius * 0.22, radius * 0.22, radius * 0.22)
			burst.Transparency = math.min(1, 0.25 + i * 0.075)
			task.wait(0.05)
		end
		if burst.Parent then burst:Destroy() end
	end)
end

-- Culls any boss VFX that outlived its owner (mission end, respawn, module teardown).
function Bastion.cullVfx(): number
	local culled = 0
	local now = os.clock()
	for _, d in ipairs(workspace:GetDescendants()) do
		if (d.Name == "BossBlast" or d.Name == "BossBeam") and d:IsA("BasePart") then
			local born = tonumber(d:GetAttribute("GFVfxBorn")) or 0
			if now - born > 1.2 then
				d:Destroy()
				culled += 1
			end
		end
	end
	if culled > 0 then
		workspace:SetAttribute("GF_BossVfxCulled", (workspace:GetAttribute("GF_BossVfxCulled") or 0) + culled)
	end
	return culled
end
-- Culls any boss VFX that outlived its owner (mission end, respawn, module teardown).
local function nearest(state)
	local best, bestDist = nil, math.huge
	for _, entry in ipairs(alivePlayers()) do
		local d = (entry.root.Position - state.root.Position).Magnitude
		if d < bestDist then best, bestDist = entry, d end
	end
	return best, bestDist
end
local function retarget(state)
	local target, dist = nearest(state)
	state.target = target
	state.dist = dist
	return target, dist
end
local function startMortar(state)
	local t = state.target
	if not t then return end
	local aim = t.root.Position
	local landings = {}
	for i = 1, 3 do
		local spread = (i == 1) and 0 or 14
		local offset = Vector3.new(math.random(-spread, spread), 0, math.random(-spread, spread))
		if i == 1 then
			landings[i] = aim
		else
			landings[i] = aim + offset
		end
		marker(landings[i], 12, 1.7, Color3.fromRGB(255, 96, 72))
	end
	state.busyUntil = os.clock() + 2.3
	task.delay(1.7, function()
		if state.dead then return end
		for i = 1, 3 do
			local pos = landings[i]
			local gy = groundAt(pos)
			local at = Vector3.new(pos.X, gy + 0.4, pos.Z)
			explode(at, 7, Color3.fromRGB(255, 132, 64))
			blast(at, 12, 46, "BastionMortar")
		end
	end)
end
local function startLaser(state)
	local t = state.target
	if not t then return end
	local origin = state.root.Position + Vector3.new(0, 10, 0)
	local dir = (t.root.Position - origin)
	local length = math.min(dir.Magnitude + 20, 150)
	local target = origin + dir.Unit * length
	marker(t.root.Position, 4, 1.2, Color3.fromRGB(255, 64, 64))
	state.busyUntil = os.clock() + 3.1
	task.delay(1.2, function()
		if state.dead then return end
		beam(origin, target, 1.6, Color3.fromRGB(255, 96, 72))
		for tick = 1, 5 do
			task.wait(0.3)
			if state.dead then return end
			local entry = state.target
			if entry and entry.root.Parent then
				local toPlayer = entry.root.Position - origin
				local projected = origin + dir.Unit * math.max(0, toPlayer:Dot(dir.Unit))
				local lateral = (entry.root.Position - projected).Magnitude
				if lateral <= 5 then
					local params = RaycastParams.new()
					params.FilterDescendantsInstances = { state.model, entry.root.Parent }
					params.FilterType = Enum.RaycastFilterType.Exclude
					local blocked = workspace:Raycast(origin, entry.root.Position - origin, params)
					if not blocked then
						Vitals.applyDamage(entry.player, 16, "BastionLaser")
					end
				end
			end
		end
	end)
end
local function startStomp(state)
	local pos = state.root.Position
	marker(pos, 13, 1.1, Color3.fromRGB(255, 176, 64))
	state.busyUntil = os.clock() + 1.9
	-- telegraph pose: the walker rears its front legs for the windup second, then slams
	state.stompPoseUntil = os.clock() + 1.0
	task.delay(1.0, function()
		if state.dead then return end
		explode(Vector3.new(pos.X, pos.Y + 1, pos.Z), 10, Color3.fromRGB(255, 176, 64))
		blast(pos, 13, 58, "BastionStomp")
	end)
end
local function die(state)
	if state.dead then return end
	state.dead = true
	state.deadAt = os.clock()
	state.model:SetAttribute("Dead", true)
	pcall(function()
		require(script.Parent.Services.CacheService).onEnemyKilled(state.model, nil)
	end)
	-- S06-058/S08-050: boss loot auto-enters the shared ledger — no pickup scramble, no ninja-looting.
	-- Rare boss drops are squad property pending salvage distribution at extraction.
	pcall(function()
		local SquadService = require(script.Parent.Services.SquadService)
		SquadService.add("militaryTechnology", 4)
		SquadService.add("energyCells", 6)
		workspace:SetAttribute("GF_BossLootShared", true)
	end)
	state.model:SetAttribute("Health", 0)
	-- the workspace attributes are the HUD's only feed: leaving the last health value published
	-- after the walker died kept the boss bar on screen through cleanup and into the next mission.
	workspace:SetAttribute("BossHealth", 0)
	workspace:SetAttribute("BastionActive", false)
	local pos = state.root.Position
	explode(pos + Vector3.new(0, 8, 0), 16, Color3.fromRGB(255, 200, 120))
	for _, p in ipairs(state.model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = false
			p.Anchored = true
		end
	end
	workspace:SetAttribute("BastionDefeated", true)
	task.delay(6, function()
		if state.model.Parent then state.model:Destroy() end
	end)
end
local function step(state, dt)
	local model = state.model
	if model:GetAttribute("Health") <= 0 then
		die(state)
		return
	end
	local health = model:GetAttribute("Health")
	local maxHealth = model:GetAttribute("MaxHealth")
	local frac = health / maxHealth
	-- S06-056: aggression cadence multiplier 1+0.45*(1-HP/HPmax) — attack cooldowns shrink as HP
	-- drops; telegraph windows themselves never shorten because they are survival-critical tells.
	state.aggressionMult = 1 + 0.45 * (1 - frac)
	local phase = 1
	if frac <= 0.33 then phase = 3 elseif frac <= 0.66 then phase = 2 end
	if phase ~= model:GetAttribute("Phase") then
		model:SetAttribute("Phase", phase)
		state.speed = 7 + phase * 1.5
		state.busyUntil = math.max(state.busyUntil, os.clock() + 1.2)
		explode(model.PrimaryPart.Position, 12, Color3.fromRGB(255, 120, 72))
		RS.GF.Remotes.EnemyTelegraph:FireAllClients(model, 1.2)
	end
	workspace:SetAttribute("BossHealth", health)
	workspace:SetAttribute("BossPhase", phase)
	local now = os.clock()
	local stagger = model:GetAttribute("Stagger")
	if stagger > now then
		return
	end
	local target, dist = retarget(state)
	if not target then return end
	local root = state.root
	local flat = (target.root.Position - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit, Vector3.yAxis)
	end
	if now < state.busyUntil then
		return
	end
	-- S06-057: attacks are weighted-selected among ready moves with no immediate repeat — the boss
	-- never chains the same attack twice while alternatives are ready, so the fight reads as varied
	-- pressure rather than a fixed rotation. Tells are unchanged and never shortened.
	local ready = {}
	if dist <= 16 and now >= state.nextStomp then
		table.insert(ready, { id = "Stomp", weight = 3, fire = function()
			state.nextStomp = now + 6.5 / (state.aggressionMult or 1)
			startStomp(state)
		end })
	end
	local function componentDown(model, id)
		for _, p in ipairs(model:GetChildren()) do
			if p:GetAttribute("ComponentId") == id and p:GetAttribute("ComponentDestroyed") == true then
				return true
			end
		end
		return false
	end
	-- S06-062 sweeping cannon: 1.3s tell then 3 pulses of 20 damage over 1s, 6s cooldown. The
	-- telegraph window never shrinks with aggression — survival-critical tells stay honest.
	if dist < 70 and now >= (state.nextCannon or 0) then
		table.insert(ready, { id = "SweepingCannon", weight = 2.8, fire = function()
			state.nextCannon = now + 6 / (state.aggressionMult or 1)
			task.spawn(function()
				local players = game:GetService("Players"):GetPlayers()
				task.wait(1.3) -- the tell: a rising whine and barrel glow, always 1.3s
				-- legitimacy fix (spec scenario D): the cannon sweeps a forward arc, not an
				-- omnidirectional radius. counterplay exists — flank the walker, get behind it,
				-- or break line of sight during the telegraph and the pulses cannot reach you.
				local losParams = RaycastParams.new()
				losParams.FilterType = Enum.RaycastFilterType.Exclude
				losParams.FilterDescendantsInstances = { model }
				losParams.IgnoreWater = true
				for pulse = 1, 3 do
					if not model.Parent or not model.PrimaryPart then
						break
					end
					local origin = model.PrimaryPart.Position
					local forward = model.PrimaryPart.CFrame.LookVector
					-- each pulse sweeps the arc: bearings rotate across a 150-degree frontal fan
					local sweepOffset = (pulse - 2) * math.rad(50)
					local cosHalfArc = math.cos(math.rad(80))
					for _, plr in ipairs(players) do
						local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
						if root and (root.Position - origin).Magnitude < 70 then
							local to = (root.Position - origin)
							local flatTo = Vector3.new(to.X, 0, to.Z)
							local flatFwd = Vector3.new(forward.X, 0, forward.Z)
							if flatTo.Magnitude > 1 and flatFwd.Magnitude > 0.1 then
								-- rotate facing by the sweep offset for this pulse
								local c, sn = math.cos(sweepOffset), math.sin(sweepOffset)
								local rx = flatFwd.X * c - flatFwd.Z * sn
								local rz = flatFwd.X * sn + flatFwd.Z * c
								local dot = (flatTo.Unit).X * rx + (flatTo.Unit).Z * rz
								if dot >= cosHalfArc then
									-- line of sight: cover and terrain genuinely protect
									local eye = origin + Vector3.new(0, 8, 0)
									local hit = workspace:Raycast(eye, root.Position + Vector3.new(0, 1.5, 0) - eye, losParams)
									if hit == nil then
										local humanoid = plr.Character:FindFirstChild("Humanoid")
										if humanoid then
											humanoid:TakeDamage(20)
										end
									end
								end
							end
						end
					end
					if pulse < 3 then
						task.wait(0.5)
					end
				end
			end)
		end })
	end

	if phase >= 2 and not componentDown(model, "Laser") and dist > 22 and dist < 110 and now >= state.nextLaser then
		table.insert(ready, { id = "Laser", weight = 2, fire = function()
			state.nextLaser = now + 9 / (state.aggressionMult or 1)
			startLaser(state)
		end })
	end
	-- Engagement gate: the walker does not shell a squad that has not reached it, and never shells a target
	-- standing in the landing zone. Distance alone was not enough: one volley still reached the drop because
	-- the splashes land where the player is, not where the walker is.
	local lz = workspace:GetAttribute("GF_LZ")
	local inLandingZone = false
	if typeof(lz) == "Vector3" and target and target.root then
		inLandingZone = (target.root.Position - lz).Magnitude < 80
	end
	if dist > 26 and dist < 120 and not inLandingZone and now >= state.nextMortar then
		table.insert(ready, { id = "Mortar", weight = 2.5, fire = function()
			state.mortarPoseUntil = os.clock() + 1.6
			state.nextMortar = now + ((phase == 3 and 5 or 7.5)) / (state.aggressionMult or 1)
			startMortar(state)
		end })
	end
	-- weighted pick with no immediate repeat when alternatives exist
	if #ready > 0 then
		local pool = ready
		if #ready > 1 and state.lastMove then
			pool = {}
			for _, mv in ipairs(ready) do
				if mv.id ~= state.lastMove then
					table.insert(pool, mv)
				end
			end
		end
		local total = 0
		for _, mv in ipairs(pool) do total += mv.weight end
		local roll = math.random() * total
		for _, mv in ipairs(pool) do
			roll -= mv.weight
			if roll <= 0 then
				state.lastMove = mv.id
				mv.fire()
				return
			end
		end
	end
	if dist > 20 then
		local stepDist = state.speed * dt
		local move = flat.Unit * math.min(stepDist, dist - 18)
		local next = root.Position + move
		local gy = groundAt(next)
		root.CFrame = CFrame.new(Vector3.new(next.X, gy + 11.5, next.Z)) * (root.CFrame - root.CFrame.Position)
		state.walkPhase = (state.walkPhase or 0) + dt * 5
		for _, leg in ipairs(state.legs) do
			local swing = math.sin(state.walkPhase + leg.phase) * 0.7
			local lift = math.abs(math.cos(state.walkPhase + leg.phase)) * 0.75
			-- attack telegraph poses layer over the stride cycle
			if os.clock() < (state.stompPoseUntil or 0) and leg.phase < 1.6 then
				lift = lift + 2.6  -- front legs rear high before the slam
			end
			if os.clock() < (state.mortarPoseUntil or 0) then
				lift = lift * 0.3  -- legs plant firm for the mortar launch
			end
			local ox = leg.thigh:GetAttribute("ox")
			local oz = leg.thigh:GetAttribute("oz")
			leg.thigh.CFrame = root.CFrame * CFrame.new(ox, -1.6, oz + swing)
			leg.shin.CFrame = root.CFrame * CFrame.new(ox * 1.25, -6.6 - lift, oz * 1.15 + swing * 1.5)
			leg.foot.CFrame = root.CFrame * CFrame.new(ox * 1.3, -10.1 - lift, oz * 1.2 + swing * 1.9)
		end
	end
end
function Bastion.spawn(position)
	local model, legs = Bastion.build(position)
	local state = {
		model = model,
		root = model.PrimaryPart,
		legs = legs,
		target = nil,
		dist = 999,
		speed = 6.5,
		busyUntil = 0,
		nextMortar = os.clock() + 2.5,
		nextLaser = os.clock() + 6,
		nextStomp = os.clock() + 3,
		walkPhase = 0,
		dead = false,
	}
	table.insert(active, state)
	workspace:SetAttribute("BastionActive", true)
	workspace:SetAttribute("BastionDefeated", false)
	workspace:SetAttribute("BossHealth", model:GetAttribute("Health"))
	workspace:SetAttribute("BossMaxHealth", model:GetAttribute("MaxHealth"))
	workspace:SetAttribute("BossPhase", 1)
	return model
end
function Bastion.start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < 0.1 then return end
		local stepDt = acc
		acc = 0
		for i = #active, 1, -1 do
			local state = active[i]
			local ok, err = pcall(step, state, stepDt)
			if not ok then
				warn("[GF] bastion tick error: " .. tostring(err))
			end
			if state.dead and os.clock() - (state.deadAt or 0) > 8 then
				table.remove(active, i)
			end
		end
	end)
end
function Bastion.count()
	local n = 0
	for _, s in ipairs(active) do
		if not s.dead then n = n + 1 end
	end
	return n
end
Bastion.start()
return Bastion
