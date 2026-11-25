--!strict
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Vitals = require(script.Parent.Services.VitalsService)
local ProfileService = require(script.Parent.Services.ProfileService)
local EnemyService = require(script.Parent.Services.EnemyService)
local Veyr = {}
local active = {}
local REQUIRED_RANK = 3
local PAYLOAD = { credits = 450, xp = 900 }
local ARMOR = Color3.fromRGB(38, 34, 44)
local TRIM = Color3.fromRGB(188, 148, 72)
local CLOTH = Color3.fromRGB(96, 32, 44)
local GLOW = Color3.fromRGB(255, 96, 84)
local function part(model, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or ARMOR
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end
function Veyr.canSpawn(player)
	if not player then
		return false
	end
	local profile = ProfileService.get(player)
	return profile ~= nil and profile.rank >= REQUIRED_RANK
end
function Veyr.build(position)
	local model = Instance.new("Model")
	model.Name = "HighMarshalVeyr"
	local base = CFrame.new(position)
	local torso = part(model, "Torso", Vector3.new(6.4, 7.2, 3.6), base * CFrame.new(0, 9, 0), ARMOR)
	model.PrimaryPart = torso
	part(model, "PauldronL", Vector3.new(3.2, 3.4, 4), base * CFrame.new(-4.4, 11.4, 0), TRIM)
	part(model, "PauldronR", Vector3.new(3.2, 3.4, 4), base * CFrame.new(4.4, 11.4, 0), TRIM)
	part(model, "Cape", Vector3.new(7.6, 9.6, 0.4), base * CFrame.new(0, 8.6, 2.2), CLOTH, Enum.Material.Fabric)
	part(model, "CapeTrim", Vector3.new(7.8, 0.6, 0.5), base * CFrame.new(0, 4.2, 2.2), TRIM)
	part(model, "Helmet", Vector3.new(4.2, 3.4, 4.4), base * CFrame.new(0, 13.9, 0.2), ARMOR)
	part(model, "Visor", Vector3.new(3.4, 0.9, 0.4), base * CFrame.new(0, 14.1, 2.3), GLOW, Enum.Material.Neon)
	part(model, "Crest", Vector3.new(0.5, 3.2, 3.6), base * CFrame.new(0, 16.2, 0), TRIM)
	part(model, "Backpack", Vector3.new(4.4, 5, 2.4), base * CFrame.new(0, 9.6, -2.6), ARMOR)
	part(model, "CorePlate", Vector3.new(2.6, 2.6, 0.6), base * CFrame.new(0, 9.4, 1.9), GLOW, Enum.Material.Neon)
	part(model, "CoreFrame", Vector3.new(3.6, 3.6, 0.5), base * CFrame.new(0, 9.4, 1.55), TRIM)
	local core = part(model, "WeakPoint_Core", Vector3.new(2.2, 2.2, 0.9), base * CFrame.new(0, 9.4, 2.1), GLOW, Enum.Material.Neon)
	core:SetAttribute("WeakPoint", 1.6)
	for _, side in ipairs({ -1, 1 }) do
		part(model, "Arm" .. side, Vector3.new(1.8, 6.4, 1.8), base * CFrame.new(side * 4.2, 7.4, 0.4), ARMOR)
		part(model, "Leg" .. side, Vector3.new(2.4, 7, 2.4), base * CFrame.new(side * 1.8, 2.6, 0), ARMOR)
		part(model, "Boot" .. side, Vector3.new(2.8, 1.4, 4), base * CFrame.new(side * 1.8, 0.2, 0.8), TRIM)
	end
	local rifle = part(model, "Rifle", Vector3.new(1.1, 1.1, 7.4), base * CFrame.new(3.4, 8.6, 3.2), ARMOR)
	part(model, "RifleMuzzle", Vector3.new(1.4, 1.4, 1.2), base * CFrame.new(3.4, 8.6, 7.1), GLOW, Enum.Material.Neon)
	model:SetAttribute("ArmorFactor", 0.65)
	model:SetAttribute("Health", 7200)
	model:SetAttribute("MaxHealth", 7200)

	-- S06-066 command plaza pylons: two destructible power pylons flank the arena — each active
	-- pylon feeds Veyr 5% bonus damage, so killing them is a real tactical trade against the
	-- time it costs. 350 HP each, independently targetable.
	for i = 1, 2 do
		local pylon = part(model, "Pylon" .. i, Vector3.new(2.5, 12, 2.5), base * CFrame.new((i == 1) and 18 or -18, 6, -14), OBSIDIAN)
		pylon:SetAttribute("ComponentHP", 350)
		pylon:SetAttribute("ComponentMaxHP", 350)
		pylon:SetAttribute("ComponentId", "Pylon" .. i)
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(200, 120, 255)
		glow.Brightness = 2
		glow.Range = 14
		glow.Parent = pylon
	end

	model:SetAttribute("Shield", 0)
	model:SetAttribute("MaxShield", 420)
	model:SetAttribute("Dead", false)
	model:SetAttribute("Boss", true)
	model:SetAttribute("Phase", 1)
	model.Parent = workspace
	return model, rifle
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
local function nearest(state)
	local best, bestDist = nil, math.huge
	for _, e in ipairs(alivePlayers()) do
		local d = (e.root.Position - state.root.Position).Magnitude
		if d < bestDist then best, bestDist = e, d end
	end
	return best, bestDist
end
local function groundY(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -220, 0), params)
	return hit and hit.Position.Y or pos.Y
end
local function burst(state)
	local target = state.target
	if not target then return end
	state.busyUntil = os.clock() + 1.5
	RS.GF.Remotes.EnemyTelegraph:FireAllClients(state.model, 0.7)
	for i = 1, 3 do
		task.delay(0.7 + (i - 1) * 0.22, function()
			if state.dead then return end
			local t = state.target
			if not t or not t.root.Parent then return end
			local from = state.root.Position + Vector3.new(0, 2, 0)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { state.model, t.root.Parent }
			local blocked = workspace:Raycast(from, t.root.Position - from, params)
			if not blocked then
				RS.GF.Remotes.EnemyFired:FireAllClients(state.model, t.root.Position)
				Vitals.applyDamage(t.player, 26, "VeyrBurst")
			end
		end)
	end
end
local function lance(state)
	local target = state.target
	if not target then return end
	local spot = target.root.Position
	local mark = Instance.new("Part")
	mark.Name = "VeyrLanceMark"
	mark.Shape = Enum.PartType.Cylinder
	mark.Size = Vector3.new(0.2, 18, 18)
	mark.CFrame = CFrame.new(spot) * CFrame.Angles(0, 0, math.rad(90))
	mark.Color = GLOW
	mark.Material = Enum.Material.Neon
	mark.Transparency = 0.6
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.Parent = workspace
	state.busyUntil = os.clock() + 2.4
	task.delay(1.4, function()
		if mark.Parent then mark:Destroy() end
		if state.dead then return end
		for _, e in ipairs(alivePlayers()) do
			if (e.root.Position - spot).Magnitude <= 18 then
				Vitals.applyDamage(e.player, 52, "VeyrLance")
			end
		end
	end)
end
local function summon(state)
	state.busyUntil = os.clock() + 2
	local pos = state.root.Position
	for i = 1, 2 do
		local angle = (i / 2) * math.pi * 2
		local spot = pos + Vector3.new(math.cos(angle) * 12, 0, math.sin(angle) * 12)
		EnemyService.spawn(i == 1 and "Rifleman" or "Scout", spot)
	end
	workspace:SetAttribute("VeyrSummons", (tonumber(workspace:GetAttribute("VeyrSummons")) or 0) + 2)
end
local function die(state)
	if state.dead then return end
	state.dead = true
	state.deadAt = os.clock()
	local model = state.model
	model:SetAttribute("Dead", true)
	model:SetAttribute("Health", 0)
	workspace:SetAttribute("VeyrDefeated", true)
	workspace:SetAttribute("VeyrActive", false)
	for _, e in ipairs(alivePlayers()) do
		local out = ProfileService.grantBossReward(e.player, "HighMarshalVeyr", PAYLOAD.credits, PAYLOAD.xp)
		if out then
			workspace:SetAttribute("VeyrLastReward", string.format("kills=%d pity=%d bp=%s", out.kills, out.pity, tostring(out.blueprintUnlocked)))
		end
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanQuery = false
			p.CanCollide = false
		end
	end
	task.delay(5, function()
		if model.Parent then model:Destroy() end
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
	local phase = (frac <= 0.5) and 2 or 1
	if phase ~= model:GetAttribute("Phase") then
		model:SetAttribute("Phase", phase)
		model:SetAttribute("Shield", model:GetAttribute("MaxShield"))
		state.speed = 11
		state.busyUntil = os.clock() + 1
		workspace:SetAttribute("VeyrPhase", phase)
		RS.GF.Remotes.EnemyTelegraph:FireAllClients(model, 1)
		summon(state)
	end
	workspace:SetAttribute("VeyrHealth", health)
	workspace:SetAttribute("VeyrShield", model:GetAttribute("Shield"))
	local now = os.clock()
	if now < state.busyUntil then
		return
	end
	local target, dist = nearest(state)
	state.target = target
	state.dist = dist
	if not target then return end
	local root = state.root
	local flat = (target.root.Position - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > 0.4 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit, Vector3.yAxis)
	end
	if phase == 2 and now >= state.nextLance then
		state.nextLance = now + 7
		lance(state)
		return
	end
	-- Engagement gate: no burst fire at a squad that is still at the landing zone.
	local nearest, nearestDist = nearest(alivePlayers())
	local engaged = nearest ~= nil and nearestDist < 120
	if engaged and now >= state.nextBurst then
		state.nextBurst = now + (phase == 2 and 2.4 or 3.4)
		burst(state)
		return
	end
	if dist > 26 then
		local move = flat.Unit * math.min(state.speed * dt, dist - 24)
		local next = root.Position + move
		root.CFrame = CFrame.new(next.X, groundY(next) + 9, next.Z) * (root.CFrame - root.CFrame.Position)
		state.walk = (state.walk or 0) + dt * 6
	end
end
function Veyr.spawn(position, player)
	if player and not Veyr.canSpawn(player) then
		return nil, "rank"
	end
	local model, rifle = Veyr.build(position)
	local state = {
		model = model,
		root = model.PrimaryPart,
		rifle = rifle,
		speed = 9,
		busyUntil = 0,
		nextBurst = os.clock() + 1.6,
		nextLance = os.clock() + 8,
		dead = false,
	}
	table.insert(active, state)
	workspace:SetAttribute("VeyrActive", true)
	workspace:SetAttribute("VeyrDefeated", false)
	workspace:SetAttribute("VeyrPhase", 1)
	workspace:SetAttribute("VeyrHealth", model:GetAttribute("Health"))
	return model
end
function Veyr.start()
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
				warn("[GF] veyr tick error: " .. tostring(err))
			end
			if state.dead and os.clock() - (state.deadAt or 0) > 6 then
				table.remove(active, i)
			end
		end
	end)
end
function Veyr.count()
	local n = 0
	for _, s in ipairs(active) do
		if not s.dead then n = n + 1 end
	end
	return n
end
Veyr.start()
return Veyr
