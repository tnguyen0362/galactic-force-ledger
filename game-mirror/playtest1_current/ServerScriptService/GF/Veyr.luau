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
	-- E1: see BastionWalker — boss identity normalization for the shared damage pipeline.
	model:SetAttribute("GFEnemy", true)
	model:SetAttribute("EnemyId", "HighMarshalVeyr")
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
	-- Gate F articulation registry: every body part's offset in torso space at build time.
	-- Parts are independently anchored — without this the limbs never follow the torso when
	-- the boss moves (they were left behind at the build site). The articulate() pass each
	-- tick repositions everything from the torso frame, then layers pose channels on top.
	local offsets = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p ~= torso and not p.Name:find("Pylon") then
			offsets[p] = torso.CFrame:Inverse() * p.CFrame
		end
	end
	model:SetAttribute("Articulated", true)
	return model, rifle, offsets
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
local function groundY(pos, model)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	params.IgnoreWater = true
	-- terrain-inclusive pass: vegetation canopy otherwise reports false footing
	local hit = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -220, 0), params)
	if hit and hit.Instance and not hit.Instance:IsA("Terrain") then
		local params2 = RaycastParams.new()
		params2.FilterType = Enum.RaycastFilterType.Include
		params2.FilterDescendantsInstances = { workspace.Terrain }
		local hit2 = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -220, 0), params2)
		if hit2 then return hit2.Position.Y end
	end
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
-- Gate F mechanical articulation: reposition all registered parts from the torso frame
-- each tick, then layer pose channels — helmet target tracking, rifle pitch aim, cape
-- billow with velocity, alternating leg stride, arm raise during attack windows.
local function articulate(state, dt)
	local root = state.root
	if not root.Parent then return end
	local F = root.CFrame
	state.walkClock = (state.walkClock or 0) + dt
	local moving = state.lastPos and (root.Position - state.lastPos).Magnitude > 0.01
	state.lastPos = root.Position
	local wphase = state.walk or 0

	-- pose inputs: target direction in torso space
	local yawT, pitchT = 0, 0
	if state.target and state.target.root and state.target.root.Parent then
		local toT = state.target.root.Position - root.Position
		local local_ = F:VectorToObjectSpace(toT)
		yawT = math.clamp(math.atan2(-local_.X, -local_.Z), -0.7, 0.7)
		local flat = Vector3.new(local_.X, 0, local_.Z).Magnitude
		pitchT = math.clamp(math.atan2(local_.Y, math.max(flat, 0.1)), -0.4, 0.5)
	end
	state.aimYaw = state.aimYaw and state.aimYaw + (yawT - state.aimYaw) * math.min(1, dt * 4) or yawT
	state.aimPitch = state.aimPitch and state.aimPitch + (pitchT - state.aimPitch) * math.min(1, dt * 4) or pitchT

	-- attack raise: busy window means an attack telegraph is running
	local attacking = os.clock() < (state.busyUntil or 0)
	local armRaise = attacking and -1.15 or 0
	state.armBlend = (state.armBlend or 0) + ((attacking and 1 or 0) - (state.armBlend or 0)) * math.min(1, dt * 6)

	-- cape billow: backward angle scales with movement, plus idle flutter
	local speedFrac = moving and 1 or 0
	state.capeSpeed = (state.capeSpeed or 0) + (speedFrac - (state.capeSpeed or 0)) * math.min(1, dt * 3)
	local flutter = math.sin(state.walkClock * 2.3) * 0.05
	local capeAngle = state.capeSpeed * 0.5 + flutter

	for p, offset in pairs(state.offsets or {}) do
		if not p.Parent then continue end
		local cf = F * offset
		local n = p.Name
		if n == "Helmet" or n == "Visor" or n == "Crest" then
			cf = cf * CFrame.Angles(state.aimPitch * 0.35, state.aimYaw * 0.55, 0)
		elseif n == "Rifle" or n == "RifleMuzzle" then
			-- rifle pitches toward target and lifts with the attack raise
			cf = cf * CFrame.Angles(-state.aimPitch * 0.7 - state.armBlend * 0.5, 0, 0)
		elseif n:sub(1, 3) == "Arm" then
			local side = tonumber(n:sub(4)) or 1
			local swing = moving and math.sin(wphase + (side > 0 and 0 or math.pi)) * 0.15 or 0
			cf = cf * CFrame.Angles(armRaise * state.armBlend + swing, 0, side * 0.06)
		elseif n:sub(1, 3) == "Leg" or n:sub(1, 4) == "Boot" then
			-- part names are Leg-1/Leg1/Boot-1/Boot1 — sign lives after the prefix
			local numStr = n:match("%-?1$") or "1"
			local sideSign = tonumber(numStr) or 1
			local ph = wphase + (sideSign > 0 and 0 or math.pi)
			local stride = moving and math.sin(ph) * 0.9 or 0
			cf = cf * CFrame.new(0, math.max(0, math.cos(ph)) * (moving and 0.5 or 0), stride)
		elseif n == "Cape" or n == "CapeTrim" then
			cf = cf * CFrame.Angles(capeAngle, 0, 0)
		end
		p.CFrame = cf
	end
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
		-- bounded turning: bosses rotate at a deliberate rate instead of snapping
		local wantYaw = math.atan2(-flat.X, -flat.Z)
		local curYaw = select(2, root.CFrame:ToOrientation())
		local diff = (wantYaw - curYaw + math.pi) % (2 * math.pi) - math.pi
		local maxStep = 1.6 * dt -- rad/s turn rate: heavy deliberate commander
		local stepYaw = math.clamp(diff, -maxStep, maxStep)
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, curYaw + stepYaw, 0)
	end
	if phase == 2 and now >= state.nextLance then
		state.nextLance = now + 7
		lance(state)
		return
	end
	-- Engagement gate: no burst fire at a squad that is still at the landing zone.
	local nearestPl, nearestDist = nearest(state)
	local engaged = nearestPl ~= nil and nearestDist < 120
	if engaged and now >= state.nextBurst then
		state.nextBurst = now + (phase == 2 and 2.4 or 3.4)
		burst(state)
		return
	end
	if dist > 26 then
		local move = flat.Unit * math.min(state.speed * dt, dist - 24)
		local next = root.Position + move
		root.CFrame = CFrame.new(next.X, groundY(next, state.model) + 9, next.Z) * (root.CFrame - root.CFrame.Position)
		state.walk = (state.walk or 0) + dt * 6
	end
end
function Veyr.spawn(position, player)
	if player and not Veyr.canSpawn(player) then
		return nil, "rank"
	end
	local model, rifle, offsets = Veyr.build(position)
	local state = {
		model = model,
		root = model.PrimaryPart,
		rifle = rifle,
		speed = 9,
		busyUntil = 0,
		nextBurst = os.clock() + 1.6,
		nextLance = os.clock() + 8,
		dead = false,
		offsets = offsets,
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
			if not state.dead then
				local ok2, err2 = pcall(articulate, state, stepDt)
				if not ok2 and not state.artErr then
					warn("[GF] veyr articulate error: " .. tostring(err2))
					state.artErr = true
				end
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
