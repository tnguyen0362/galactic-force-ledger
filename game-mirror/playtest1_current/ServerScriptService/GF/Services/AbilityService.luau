--!strict
-- Cooldown-based support abilities. Client sends aim point; server validates range, LOS, cooldown and budget.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TweenService = game:GetService("TweenService")local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Abilities = require(ReplicatedStorage.GF.Shared.Configs.Abilities)
local Constants = require(ReplicatedStorage.GF.Shared.Constants)
local State = require(ServerScriptService.GF.Services.State)
local VitalsService = require(ServerScriptService.GF.Services.VitalsService)
local EnemyService = require(ServerScriptService.GF.Services.EnemyService)
local AbilityService = {}
local function now(): number
	return os.clock()
end
-- One place that starts an ability cooldown. The `cooldown` augment stat (Coolant Loop 0.25,
-- Overclocked Core 0.4, Extended Sentry Magazine 0.2) was declared in the allow-list and read by
-- nothing; four call sites did the arithmetic inline instead. All three values are POSITIVE
-- reductions, so the multiplier is 1 - bonus.
local function supportStats(player)
	local damageBonus, radiusBonus, sentryHPBonus = 0, 0, 0
	pcall(function()
		local augs = require(script.Parent.AugmentService).forPlayer(player)
		damageBonus = tonumber(augs and augs.supportDamage) or 0
		radiusBonus = tonumber(augs and augs.blastRadius) or 0
		sentryHPBonus = tonumber(augs and augs.sentryHP) or 0
	end)
	return math.clamp(1 + damageBonus, 0.65, 1.15), math.clamp(1 + radiusBonus, 0.65, 1.25), math.clamp(1 + sentryHPBonus, 0.65, 1.30)
end

-- S05-017: boss damage from any single ability cast is capped at 12% of the boss's scaled starting
-- HP (total per cast, accumulated across all blast ticks of that cast), and ability damage cannot
-- pass through unbreached opaque world geometry. Keyed per cast so sequential casts each get their
-- own allowance.
local bossCastDamage: { [string]: { [Model]: number } } = {}
local function abilityDamageEnemy(castId: string, enemy: Model, amount: number, player: Player, blastPoint: Vector3?)
	-- geometry: no damage through opaque world geometry between blast origin and target
	if blastPoint then
		local root = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
		if root then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { enemy }
			local dir = root.Position - blastPoint
			local hit = workspace:Raycast(blastPoint, dir, params)
			if hit and hit.Instance and hit.Instance.CanCollide and hit.Instance.Transparency < 1 then
				return -- blocked by unbreached geometry
			end
		end
	end
	if enemy:GetAttribute("Boss") then
		local maxHP = tonumber(enemy:GetAttribute("MaxHealth")) or tonumber(enemy:GetAttribute("Health")) or 1
		local cap = maxHP * 0.12
		local perCast = bossCastDamage[castId]
		if not perCast then
			perCast = {}
			bossCastDamage[castId] = perCast
		end
		local already = perCast[enemy] or 0
		if already >= cap then
			return
		end
		amount = math.min(amount, cap - already)
		perCast[enemy] = already + amount
	end
	require(ServerScriptService.GF.Services.CombatService).damageEnemy(enemy, amount, player)
end
-- lazy cleanup so the table cannot grow unbounded across a long session
task.spawn(function()
	while true do
		task.wait(120)
		table.clear(bossCastDamage)
	end
end)

local function beginCooldown(player, s, ability)
	local bonus = 0
	pcall(function()
		local augs = require(script.Parent.AugmentService).forPlayer(player)
		bonus = tonumber(augs and augs.cooldown) or 0
	end)
	s.cooldowns[ability.id] = now() + ability.cooldown * math.max(0.25, 1 - bonus)
	-- S05-007: cooldown survives death AND rejoin — persist the end time on the player object so a
	-- reconnecting player restores the same gate instead of resetting to ready.
	player:SetAttribute("CD_" .. ability.id, s.cooldowns[ability.id])
end
local function enemiesInRadius(center: Vector3, radius: number): { Model }
	local found = {}
	local folder = workspace:FindFirstChild("ActiveActors")
	if not folder then
		return found
	end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("GFEnemy") and not model:GetAttribute("Dead") then
			local root = model.PrimaryPart
			if root and (root.Position - center).Magnitude <= radius then
				table.insert(found, model)
			end
		end
	end
	return found
end
local function boom(at: Vector3, volume: number, pitch: number)
	local host = Instance.new("Part")
	host.Name = "OrbitalSound"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.Transparency = 1
	host.Size = Vector3.new(1, 1, 1)
	host.CFrame = CFrame.new(at)
	host.Parent = workspace
	local s = Instance.new("Sound")
	s.SoundId = "rbxasset://sounds/bass.wav"
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.RollOffMaxDistance = 600
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Parent = host
	s:Play()
	task.delay(3, function() host:Destroy() end)
end
local function shockRing(pos: Vector3, color: Color3, radius: number, count: number)
	local segments = {}
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local seg = Instance.new("Part")
		seg.Name = "OrbitalWave"
		seg.Size = Vector3.new(0.2, radius * 0.06, radius * 0.28)
		seg.CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * radius * 0.2, 0.4, math.sin(a) * radius * 0.2)) * CFrame.Angles(0, -a, 0)
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.Material = Enum.Material.Neon
		seg.Color = color
		seg.Transparency = 0.2
		seg.Parent = workspace
		segments[i] = { part = seg, angle = a }
	end
	for _, e in ipairs(segments) do
		local target = CFrame.new(pos + Vector3.new(math.cos(e.angle) * radius, 0.4, math.sin(e.angle) * radius)) * CFrame.Angles(0, -e.angle, 0)
		TweenService:Create(e.part, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target, Transparency = 1 }):Play()
	end
	task.delay(0.9, function()
		for _, e in ipairs(segments) do if e.part.Parent then e.part:Destroy() end end
	end)
end
local function reportReject(player: Player, reason: string)
	local dbg = workspace:FindFirstChild("GFDebug")
	if dbg then
		dbg:SetAttribute("LastCastRejected", reason)
		dbg:SetAttribute("LastCastRejectedAt", os.clock())
	end
	local ok = pcall(function()
		ReplicatedStorage.GF.Remotes.AbilityStateChanged:FireClient(player, { abilityId = "", rejected = reason })
	end)
	return ok
end
local function emergencyActive(): boolean
	return workspace:GetAttribute("GF_EmergencyExtraction") == true
end
local function cancelForEmergency(player: Player, abilityId: string): boolean
	if not emergencyActive() then
		return false
	end
	workspace:SetAttribute("GF_LastStrikeCancelled", abilityId .. ":" .. player.Name)
	reportReject(player, "strike cancelled: emergency withdrawal")
	return true
end
local function warnDangerClose(abilityName: string)
	local ok, scale = pcall(function()
		return require(ServerScriptService.GF.Services.CombatService).friendlyFireScale()
	end)
	if not ok or (tonumber(scale) or 0) <= 0 then
		return
	end
	workspace:SetAttribute("GF_LastDangerCloseWarning", abilityName)
	local ev = ReplicatedStorage.GF.Remotes:FindFirstChild("MissionEvent")
	if ev then
		ev:FireAllClients({ text = string.format("DANGER CLOSE: %s inbound - friendly fire %d%%. Clear the red zone.", abilityName, math.floor(scale * 100 + 0.5)), kind = "fail" })
	end
end
local airstrikeCastCounter = 0
local function airstrike(player: Player, s: any, position: Vector3)
	-- one id per cast so the 12%-of-boss-HP cap accumulates across all five blast steps of THIS cast
	airstrikeCastCounter += 1
	local castId = "airstrike" .. tostring(player.UserId) .. ":" .. tostring(airstrikeCastCounter)
	-- spec: no more than 280 total per target across the 3 impacts of one cast. Without this a
	-- stationary target at the strike center eats all three impacts for 420 — 50% over budget.
	local PER_TARGET_CAP = 280
	local hitTotals: { [Model]: number } = {}
	local ability = Abilities.get("Airstrike")
	if not ability then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local offset = position - root.Position
	if offset.Magnitude > (ability.range or 90) then
		reportReject(player, "out of range")
		return
	end
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { character }
	local ground = workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), groundParams)
	local point = ground and ground.Position or position
	beginCooldown(player, s, ability)
	warnDangerClose("Airstrike")
	ReplicatedStorage.GF.Remotes.AbilityConfirmed:FireAllClients(player, ability.id, point)
	ReplicatedStorage.GF.Remotes.AbilityStateChanged:FireClient(player, { abilityId = ability.id, duration = ability.cooldown })
	-- Aircraft: the strike needs a source the player can see. Parts are collected in a list so the whole
	-- craft can be tweened as one unit, or parked for a capture, and every part still expires.
	local flightAxis = Vector3.new(1, 0, 0)
	local entry = point - flightAxis * 150 + Vector3.new(0, 40, 0)
	local craft = Instance.new("Model")
	craft.Name = "AirstrikeCraft"
	local function craftPart(name: string, size: Vector3, color: Color3, material: Enum.Material, offset: CFrame): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CFrame = CFrame.new(entry) * offset
		p.Parent = craft
		return p
	end
	-- Silhouette, not a single box: a tapered nose, a spine, swept wingtips, a fin and a tailplane read as
	-- an aircraft from the ground even in near-darkness. Steel is light enough to catch the rim light.
	local hull = craftPart("Hull", Vector3.new(16, 3.2, 5), Color3.fromRGB(104, 114, 128), Enum.Material.Metal, CFrame.new())
	craftPart("Nose", Vector3.new(5, 2.2, 3.2), Color3.fromRGB(92, 100, 114), Enum.Material.Metal, CFrame.new(10.4, 0, 0))
	craftPart("Spine", Vector3.new(8, 1.6, 2.6), Color3.fromRGB(88, 96, 108), Enum.Material.Metal, CFrame.new(-3.5, 1.7, 0))
	craftPart("Wing", Vector3.new(6, 1, 24), Color3.fromRGB(96, 106, 120), Enum.Material.Metal, CFrame.new(0, 0, 0))
	craftPart("WingSweepL", Vector3.new(5, 1, 8), Color3.fromRGB(84, 92, 104), Enum.Material.Metal, CFrame.new(-2.4, 0, -12) * CFrame.Angles(0, math.rad(30), 0))
	craftPart("WingSweepR", Vector3.new(5, 1, 8), Color3.fromRGB(84, 92, 104), Enum.Material.Metal, CFrame.new(-2.4, 0, 12) * CFrame.Angles(0, math.rad(-30), 0))
	craftPart("Fin", Vector3.new(4, 4.2, 0.9), Color3.fromRGB(88, 96, 108), Enum.Material.Metal, CFrame.new(-7.6, 3.4, 0))
	craftPart("Tailplane", Vector3.new(2.2, 0.9, 9), Color3.fromRGB(84, 92, 104), Enum.Material.Metal, CFrame.new(-7.6, 0.8, 0))
	craftPart("Canopy", Vector3.new(3.6, 1.5, 3), Color3.fromRGB(64, 92, 118), Enum.Material.Glass, CFrame.new(5, 2, 0))
	craftPart("Thrust", Vector3.new(1.6, 1.6, 3.6), Color3.fromRGB(255, 178, 104), Enum.Material.Neon, CFrame.new(-8.6, 0, 0))
	local strobe = craftPart("Strobe", Vector3.new(1.2, 1.2, 1.2), Color3.fromRGB(255, 96, 96), Enum.Material.Neon, CFrame.new(0, 2.2, 0))
	local strobeLight = Instance.new("PointLight")
	strobeLight.Color = Color3.fromRGB(255, 96, 96)
	strobeLight.Brightness = 2
	strobeLight.Range = 16
	strobeLight.Parent = strobe
	local rim = Instance.new("PointLight")
	rim.Color = Color3.fromRGB(186, 214, 255)
	rim.Brightness = 1.6
	rim.Range = 34
	rim.Shadows = false
	rim.Parent = hull
	craft.PrimaryPart = hull
	craft.Parent = workspace
	local parts = {}
	for _, p in ipairs(craft:GetChildren()) do
		if p:IsA("BasePart") then
			table.insert(parts, p)
		end
	end
	if workspace:GetAttribute("GF_HoldCraft") == true then
		-- capture hook: park the whole craft at a fixed point so a frame can be taken of it
		local park = point - flightAxis * 70 + Vector3.new(0, 30, 0)
		for _, p in ipairs(parts) do
			p.CFrame = p.CFrame + (park - entry)
		end
		craft:SetAttribute("GFHeld", true)
	else
		for _, p in ipairs(parts) do
			TweenService:Create(p, TweenInfo.new(10, Enum.EasingStyle.Linear), { CFrame = p.CFrame + flightAxis * 340 }):Play()
		end
	end
	boom(point + Vector3.new(0, 4, 0), 0.35, 1.4)
	craft:SetAttribute("GFParts", #parts)
	-- A held craft is a capture fixture, so it outlives the ordinary 12s window; a flying one does not.
	local lifetime = workspace:GetAttribute("GF_HoldCraft") == true and 300 or 12
	task.delay(lifetime, function() if craft.Parent then craft:Destroy() end end)

	-- Aircraft flyover, then a linear bomb pattern along the strike axis.
	task.delay(1.15, function()
		if cancelForEmergency(player, "Airstrike") then
			return
		end
		local axis = Vector3.new(1, 0, 0)
		-- S05-011: exactly 3 missile impacts spaced along a ~36-stud line (-18/0/+18), radius 12 each.
		for idx, step in ipairs({ -18, 0, 18 }) do
			task.delay(0.09 * (idx - 1), function()
				local center = point + axis * step
				local blastParams = RaycastParams.new()
				blastParams.FilterType = Enum.RaycastFilterType.Exclude
				local blast = workspace:Raycast(center + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), blastParams)
				local blastPoint = blast and blast.Position or center
				ReplicatedStorage.GF.Remotes.AbilityImpact:FireAllClients("Airstrike", blastPoint)
				-- Each blast gets its own short-lived flash and ember; nothing outlives 1.6s so the strike
				-- cannot obscure combat (recorded as LastAirstrikeBlasts / LastAirstrikeVfxClear).
				local flash = Instance.new("Part")
				flash.Name = "AirstrikeBlast"
				flash.Shape = Enum.PartType.Ball
				flash.Size = Vector3.new(9, 9, 9)
				flash.CFrame = CFrame.new(blastPoint + Vector3.new(0, 6.5, 0))
				flash.Anchored = true
				flash.CanCollide = false
				flash.CanQuery = false
				flash.Material = Enum.Material.Neon
				flash.Color = Color3.fromRGB(255, 176, 96)
				flash.Transparency = 0.25
				flash.Parent = workspace
				-- Hold a solid core for 1.6s, then fade. A one-way fade from 0.35 is invisible to any observer
				-- (and to any capture) within about a second, which is how this effect went unphotographed.
				flash.Transparency = 0.55
				-- bright core: small, hot, and gone in a third of a second - reads as an impact without
				-- flooding the viewport the way a large opaque shell did
				local core = Instance.new("Part")
				core.Name = "AirstrikeCore"
				core.Shape = Enum.PartType.Ball
				core.Size = Vector3.new(4.5, 4.5, 4.5)
				core.CFrame = CFrame.new(blastPoint + Vector3.new(0, 5, 0))
				core.Material = Enum.Material.Neon
				core.Color = Color3.fromRGB(255, 244, 214)
				core.Transparency = 0.05
				core.Anchored = true
				core.CanCollide = false
				core.CanQuery = false
				core.Parent = workspace
				TweenService:Create(core, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
				task.delay(0.4, function() if core.Parent then core:Destroy() end end)
				-- debris: six chunks thrown outward, each cleaned up within 1.2s
				for i = 1, 6 do
					local angle = (i / 6) * math.pi * 2
					local chunk = Instance.new("Part")
					chunk.Name = "AirstrikeDebris"
					chunk.Size = Vector3.new(0.6, 0.6, 1.1)
					chunk.Material = Enum.Material.Slate
					chunk.Color = Color3.fromRGB(58, 52, 48)
					chunk.CFrame = CFrame.new(blastPoint + Vector3.new(math.cos(angle) * 2, 4, math.sin(angle) * 2))
					chunk.Anchored = true
					chunk.CanCollide = false
					chunk.CanQuery = false
					chunk.Parent = workspace
					local target = CFrame.new(blastPoint + Vector3.new(math.cos(angle) * 11, 1.5, math.sin(angle) * 11))
					TweenService:Create(chunk, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target, Transparency = 1 }):Play()
					task.delay(1.0, function() if chunk.Parent then chunk:Destroy() end end)
				end
				task.delay(1.6, function()
					if flash.Parent then
						TweenService:Create(flash, TweenInfo.new(2.4), { Transparency = 1, Size = Vector3.new(15, 15, 15) }):Play()
					end
				end)
				task.delay(3.6, function() if flash.Parent then flash:Destroy() end end)
				local lamp = Instance.new("Part")
				lamp.Name = "AirstrikeFlash"
				lamp.Size = Vector3.new(1, 1, 1)
				lamp.CFrame = CFrame.new(blastPoint + Vector3.new(0, 6, 0))
				lamp.Anchored = true
				lamp.CanCollide = false
				lamp.CanQuery = false
				lamp.Transparency = 1
				lamp.Parent = workspace
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(255, 196, 140)
				light.Brightness = 3.5
				light.Range = 26
				light.Shadows = true
				light.Parent = lamp
				TweenService:Create(light, TweenInfo.new(2.6), { Brightness = 0 }):Play()
				task.delay(2.8, function() if lamp.Parent then lamp:Destroy() end end)
				-- smoke column: a blast needs volume and a rising silhouette, not just a fading sphere
				local smoke = Instance.new("Part")
				smoke.Name = "AirstrikeSmoke"
				smoke.Shape = Enum.PartType.Ball
				smoke.Size = Vector3.new(5, 5, 5)
				smoke.CFrame = CFrame.new(blastPoint + Vector3.new(0, 7, 0))
				smoke.Anchored = true
				smoke.CanCollide = false
				smoke.CanQuery = false
				smoke.Material = Enum.Material.Slate
				smoke.Color = Color3.fromRGB(44, 40, 38)
				smoke.Transparency = 0.2
				smoke.Parent = workspace
				TweenService:Create(smoke, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					CFrame = CFrame.new(blastPoint + Vector3.new(0, 22, 0)),
					Size = Vector3.new(15, 20, 15),
					Transparency = 0.75,
				}):Play()
				task.delay(5.2, function() if smoke.Parent then smoke:Destroy() end end)
				local dbg2 = workspace:FindFirstChild("GFDebug")
				if dbg2 then
					dbg2:SetAttribute("LastAirstrikeBlasts", (dbg2:GetAttribute("LastAirstrikeBlasts") or 0) + 1)
					dbg2:SetAttribute("LastAirstrikeVfxClear", os.clock() + 3.7)
				end
				local supportDamageScale, supportRadiusScale = supportStats(player)
				require(ServerScriptService.GF.Services.CombatService).damageAlliesInRadius(blastPoint, 12 * supportRadiusScale, ability.damage * supportDamageScale, player)
				for _, enemy in enemiesInRadius(blastPoint, 11 * supportRadiusScale) do
					local armor = enemy:GetAttribute("Tier")
					local mult = (armor == "Elite" or armor == "Boss") and 0.5 or 1
					local room = PER_TARGET_CAP - (hitTotals[enemy] or 0)
					if room > 0 then
						local amount = math.min(ability.damage * mult * supportDamageScale, room)
						hitTotals[enemy] = (hitTotals[enemy] or 0) + amount
						abilityDamageEnemy(castId, enemy, amount, player, blastPoint)
					end
				end
			end)
		end
	end)
end
local function dome(player: Player, s: any, position: Vector3)
	local ability = Abilities.get("DomeShield")
	if not ability then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	if (position - root.Position).Magnitude > (ability.range or 90) then
		return
	end
	-- One dome per owner: a new valid deployment replaces the old one.
	if s.activeDome and s.activeDome.Parent then
		s.activeDome:Destroy()
		workspace:SetAttribute("GF_LastDomeReplaced", player.Name)
	end
	local _, supportRadiusScale = supportStats(player)
	local effectiveRadius = (ability.radius or 14) * supportRadiusScale
	local sphere = Instance.new("Part")
	sphere.Name = "DomeShield"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(effectiveRadius * 2, effectiveRadius * 2, effectiveRadius * 2)
	sphere.Position = position
	sphere.Anchored = true
	-- Queryable so projectiles collide with the shell; still non-colliding so players can walk through.
	sphere.CanCollide = false
	sphere.CanQuery = true
	sphere.CanTouch = false
	sphere.Material = Enum.Material.ForceField
	sphere.Color = Color3.fromRGB(90, 190, 255)
	sphere.Transparency = 0.55
	-- Gate G deployment animation: the shell expands from a seed point over 0.45s with a
	-- slight overshoot, then breathes at low amplitude while active — reads as projected
	-- energy rather than a static prop.
	do
		local fullSize = sphere.Size
		local bornAt = os.clock()
		sphere.Size = fullSize * 0.08
		task.spawn(function()
			while sphere.Parent do
				local t = os.clock() - bornAt
				if t < 0.45 then
					local f = t / 0.45
					local ease = 1 - (1 - f) ^ 3
					local overshoot = f > 0.7 and (1 + 0.06 * math.sin((f - 0.7) / 0.3 * math.pi)) or 1
					sphere.Size = fullSize * (0.08 + 0.92 * ease) * overshoot
				else
					sphere.Size = fullSize * (1 + 0.015 * math.sin(os.clock() * 2.4))
				end
				task.wait(0.05)
			end
		end)
	end
	sphere:SetAttribute("DomeHealth", (ability.domeHealth or 600))
	sphere:SetAttribute("Radius", effectiveRadius)
	local host = workspace:FindFirstChild("GameplayEffects") or workspace
	sphere.Parent = host
	-- A single ForceField sphere at 0.55 was invisible against a dark room (V314). Give it an outer
	-- rim shell and a ring of base posts so the boundary can be seen and walked to.
	local rim = Instance.new("Part")
	rim.Name = "DomeShieldRim"
	rim.Shape = Enum.PartType.Ball
	rim.Size = sphere.Size * 1.015
	rim.Position = position
	rim.Anchored = true
	rim.CanCollide = false
	rim.CanQuery = false
	rim.Material = Enum.Material.Neon
	rim.Color = Color3.fromRGB(150, 214, 255)
	rim.Transparency = 0.86
	rim.Parent = sphere
	for i = 1, 14 do
		local a = (i / 14) * math.pi * 2
		local post = Instance.new("Part")
		post.Name = "DomePost"
		post.Size = Vector3.new(0.5, 2.2, 0.5)
		post.Position = position + Vector3.new(math.cos(a) * effectiveRadius, 0.9, math.sin(a) * effectiveRadius)
		post.Anchored = true
		post.CanCollide = false
		post.CanQuery = false
		post.Material = Enum.Material.Neon
		post.Color = Color3.fromRGB(120, 200, 255)
		post.Transparency = 0.2
		post.Parent = sphere
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = sphere
		weld.Part1 = post
		weld.Parent = post
	end
	local rimWeld = Instance.new("WeldConstraint")
	rimWeld.Part0 = sphere
	rimWeld.Part1 = rim
	rimWeld.Parent = rim
	s.activeDome = sphere
	beginCooldown(player, s, ability)
	ReplicatedStorage.GF.Remotes.AbilityStateChanged:FireClient(player, { abilityId = ability.id, duration = ability.cooldown })
	task.delay(ability.duration, function()
		if sphere.Parent then
			sphere:Destroy()
		end
		if s.activeDome == sphere then
			s.activeDome = nil
		end
	end)
end
-- Sentry: a deployable that only fires at enemies it can actually see. The requirement is explicit
-- that it must not shoot through rocks, so every candidate is line-of-sight tested from the barrel
-- and the sentry publishes its target/blocked counts for verification.
local SENTRY_TICK = 0.2 -- spec: 300 RPM = 5 shots/sec (was 150 RPM)
local function sentry(player: Player, s: any, position: Vector3)
	local ability = Abilities.get("Sentry")
	if not ability then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	if (position - root.Position).Magnitude > (ability.range or 90) then
		return
	end
	-- One sentry per owner: a new valid deployment replaces the old one.
	if s.activeSentry and s.activeSentry.Parent then
		s.activeSentry:Destroy()
		workspace:SetAttribute("GF_LastSentryReplaced", player.Name)
	end
	local folder = workspace:FindFirstChild("GameplayEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "GameplayEffects"
		folder.Parent = workspace
	end
	local model = Instance.new("Model")
	model.Name = "Sentry"
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(2.2, 0.4, 2.2)
	base.CFrame = CFrame.new(position + Vector3.new(0, 0.4, 0))
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.Color = Color3.fromRGB(58, 64, 76)
	base.Material = Enum.Material.Metal
	base.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.0, 0.9, 1.2)
	head.CFrame = CFrame.new(position + Vector3.new(0, 1.3, 0))
	head.Anchored = true
	head.CanCollide = false
	head.CanQuery = false
	head.Color = Color3.fromRGB(96, 104, 120)
	head.Material = Enum.Material.Metal
	head.Parent = model
	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.3, 0.3, 1.6)
	barrel.CFrame = CFrame.new(position + Vector3.new(0, 1.3, -1.2))
	barrel.Anchored = true
	barrel.CanCollide = false
	barrel.CanQuery = false
	barrel.Color = Color3.fromRGB(30, 34, 42)
	barrel.Material = Enum.Material.Metal
	barrel.Parent = model
	local lens = Instance.new("Part")
	lens.Name = "Lens"
	lens.Size = Vector3.new(0.28, 0.28, 0.1)
	lens.CFrame = CFrame.new(position + Vector3.new(0, 1.3, -0.66))
	lens.Anchored = true
	lens.CanCollide = false
	lens.CanQuery = false
	lens.Color = Color3.fromRGB(255, 96, 72)
	lens.Material = Enum.Material.Neon
	lens.Parent = model
	model.PrimaryPart = base
	model.Parent = folder
	local supportDamageScale, _, sentryHPScale = supportStats(player)
	local sentryHealth = math.floor(180 * sentryHPScale + 0.5)
	s.activeSentry = model
	model:SetAttribute("GFSentryOwner", player.UserId)
	model:SetAttribute("Health", sentryHealth)
	model:SetAttribute("MaxHealth", sentryHealth)
	model:SetAttribute("GFSentryDestructible", true)
	model:SetAttribute("GFSentryShots", 0)
	model:SetAttribute("GFSentryBlocked", 0)
	beginCooldown(player, s, ability)
	ReplicatedStorage.GF.Remotes.AbilityStateChanged:FireClient(player, { abilityId = ability.id, duration = ability.cooldown })
	-- spec acquisition radius is 65 (ability.radius) — ability.range is the 90-stud placement
	-- reach. The sentry used to scan 38% wider than designed because the two fields were conflated.
	local radius = ability.radius or 65
	local expires = os.clock() + (ability.duration or 25)
	local Combat = require(ServerScriptService.GF.Services.CombatService)
	task.spawn(function()
		while model.Parent and os.clock() < expires do
			task.wait(SENTRY_TICK)
			local best, bestDist, blocked = nil, math.huge, 0
			for _, enemy in ipairs(workspace.ActiveActors:GetChildren()) do
				if enemy:GetAttribute("GFEnemy") == true and (enemy:GetAttribute("Health") or 1) > 0 then
					local target = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
					if target then
						local dist = (target.Position - barrel.Position).Magnitude
						if dist <= radius then
							local params = RaycastParams.new()
							params.FilterType = Enum.RaycastFilterType.Exclude
							params.FilterDescendantsInstances = { model, player.Character }
							local ray = workspace:Raycast(barrel.Position, target.Position - barrel.Position, params)
							local visible = ray == nil or ray.Instance:IsDescendantOf(enemy)
							if visible then
								if dist < bestDist then
									best, bestDist = enemy, dist
								end
							else
								blocked += 1
							end
						end
					end
				end
			end
			if blocked > 0 then
				model:SetAttribute("GFSentryBlocked", (model:GetAttribute("GFSentryBlocked") or 0) + 1)
			end
			if best then
				local target = best:FindFirstChild("HumanoidRootPart") or best.PrimaryPart
				head.CFrame = CFrame.lookAt(head.Position, Vector3.new(target.Position.X, head.Position.Y, target.Position.Z))
				barrel.CFrame = CFrame.lookAt(head.Position + (target.Position - head.Position).Unit * 1.2, target.Position)
				model:SetAttribute("GFSentryTarget", best.Name)
				model:SetAttribute("GFSentryShots", (model:GetAttribute("GFSentryShots") or 0) + 1)
				ReplicatedStorage.GF.Remotes.AbilityImpact:FireAllClients("SentryShot", barrel.Position)
				-- visible shot: a short neon tracer plus a muzzle pip, so a firing sentry reads at range
				local dir = (target.Position - barrel.Position)
				if dir.Magnitude > 0.1 then
					local tracer = Instance.new("Part")
					tracer.Name = "SentryTracer"
					tracer.Anchored = true
					tracer.CanCollide = false
					tracer.CanQuery = false
					tracer.CanTouch = false
					tracer.Material = Enum.Material.Neon
					tracer.Color = Color3.fromRGB(255, 140, 96)
					tracer.Size = Vector3.new(0.12, 0.12, dir.Magnitude)
					tracer.CFrame = CFrame.lookAt(barrel.Position + dir * 0.5, target.Position)
					tracer.Parent = folder
					local pip = Instance.new("Part")
					pip.Name = "SentryPip"
					pip.Shape = Enum.PartType.Ball
					pip.Size = Vector3.new(0.5, 0.5, 0.5)
					pip.Anchored = true
					pip.CanCollide = false
					pip.CanQuery = false
					pip.Material = Enum.Material.Neon
					pip.Color = Color3.fromRGB(255, 208, 150)
					pip.CFrame = CFrame.new(barrel.Position + dir.Unit * 0.4)
					pip.Parent = folder
					game:GetService("Debris"):AddItem(tracer, 0.12)
					game:GetService("Debris"):AddItem(pip, 0.08)
				end
				pcall(function()
					Combat.damageEnemy(best, ability.damage * supportDamageScale, player)
				end)
			else
				model:SetAttribute("GFSentryTarget", "")
			end
		end
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- Orbital strike: a telegraphed column from orbit. Everything runs on the server so it works without
-- any client handler: telegraph ring, a descending beam, a heavy shockwave and a deep boom, then
-- damage with falloff. Attributes record what happened for verification.
local ORBITAL_DELAY = 5.0 -- spec: 5s telegraph before the strike lands (was 1.8 — unreactable)
local function orbital(player: Player, s: any, position: Vector3)
	local ability = Abilities.get("OrbitalStrike")
	if not ability then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if (position - root.Position).Magnitude > (ability.range or 200) then reportReject(player, "out of range") return end
	local supportDamageScale, supportRadiusScale = supportStats(player)
	local radius = (ability.radius or 26) * supportRadiusScale
	beginCooldown(player, s, ability)
	warnDangerClose("Orbital Strike")
	ReplicatedStorage.GF.Remotes.AbilityStateChanged:FireClient(player, { abilityId = ability.id, duration = ability.cooldown })
	-- telegraph: a wide ring and a rising tone for the delay so the strike is readable before it lands
	shockRing(position, Color3.fromRGB(255, 120, 90), radius * 0.55, 20)
	boom(position, 0.25, 0.45)
	task.delay(ORBITAL_DELAY, function()
		if cancelForEmergency(player, "OrbitalStrike") then
			return
		end
		-- beam column
		local beam = Instance.new("Part")
		beam.Name = "OrbitalBeam"
		beam.Shape = Enum.PartType.Cylinder
		beam.Size = Vector3.new(220, radius * 0.5, radius * 0.5)
		beam.CFrame = CFrame.new(position + Vector3.new(0, 110, 0)) * CFrame.Angles(0, 0, math.rad(90))
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.Material = Enum.Material.Neon
		beam.Color = Color3.fromRGB(255, 236, 200)
		beam.Transparency = 0.15
		beam.Parent = workspace
		TweenService:Create(beam, TweenInfo.new(0.55), { Transparency = 1, Size = Vector3.new(220, radius * 1.6, radius * 1.6) }):Play()
		task.delay(0.7, function() if beam.Parent then beam:Destroy() end end)
		-- flash light
		local flash = Instance.new("Part")
		flash.Name = "OrbitalFlash"
		flash.Size = Vector3.new(1, 1, 1)
		flash.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanQuery = false
		flash.Transparency = 1
		flash.Parent = workspace
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 226, 180)
		light.Brightness = 24
		light.Range = radius * 3
		light.Shadows = true
		light.Parent = flash
		TweenService:Create(light, TweenInfo.new(0.9), { Brightness = 0, Range = radius }):Play()
		task.delay(1.1, function() if flash.Parent then flash:Destroy() end end)
		-- ember orb + heavy shockwave
		local orb = Instance.new("Part")
		orb.Name = "OrbitalScorch"
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(radius * 0.5, radius * 0.5, radius * 0.5)
		orb.CFrame = CFrame.new(position + Vector3.new(0, radius * 0.25, 0))
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanQuery = false
		orb.Material = Enum.Material.Neon
		orb.Color = Color3.fromRGB(255, 170, 90)
		orb.Transparency = 0.45
		orb.Parent = workspace
		TweenService:Create(orb, TweenInfo.new(20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0.92, Size = Vector3.new(radius * 1.5, radius * 1.5, radius * 1.5) }):Play()
		task.delay(20.1, function() if orb.Parent then orb:Destroy() end end)
		shockRing(position, Color3.fromRGB(255, 236, 200), radius, 24)
		boom(position, 0.9, 0.35)
		-- damage with falloff, bosses resist
		require(ServerScriptService.GF.Services.CombatService).damageAlliesInRadius(position, radius, ability.damage * supportDamageScale, player)
		local hits, total = 0, 0
		for _, enemy in ipairs(workspace.ActiveActors:GetChildren()) do
			if enemy:IsA("Model") and enemy:GetAttribute("GFEnemy") == true then
				local target = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
				if target then
					local d = (target.Position - position).Magnitude
					if d <= radius then
						local tier = enemy:GetAttribute("Tier")
						local mult = (tier == "Elite" or tier == "Boss") and 0.55 or 1
						local dmg = ability.damage * supportDamageScale * mult * (1 - (d / radius) * 0.6)
						local ok = pcall(function()
							require(ServerScriptService.GF.Services.CombatService).damageEnemy(enemy, dmg, player)
						end)
						if ok then hits += 1; total += dmg end
					end
				end
			end
		end
		local dbg = workspace:FindFirstChild("GFDebug")
		if dbg then
			dbg:SetAttribute("LastOrbital", true)
			dbg:SetAttribute("LastOrbitalTargets", hits)
			dbg:SetAttribute("LastOrbitalDamage", math.floor(total))
			dbg:SetAttribute("LastOrbitalPos", position)
		end
	end)
end

local function cast(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	-- Every rejection below used to be a silent return, so a player pressing the ability key got no
	-- feedback at all and had no way to tell a failed cast from a dead keybind. Rejections now
	-- publish a reason the HUD and the evidence trail can both read.
	local function reject(reason: string)
		local dbg = workspace:FindFirstChild("GFDebug")
		if dbg then
			dbg:SetAttribute("LastCastRejected", reason)
			dbg:SetAttribute("LastCastRejectedAt", os.clock())
		end
		ReplicatedStorage.GF.Remotes.AbilityStateChanged:FireClient(player, { abilityId = tostring(payload and payload.abilityId), rejected = reason })
	end
	local s = State.get(player)
	if not s then
		-- A cast can arrive before the profile hook has run for this player. Refusing used to be a
		-- silent dead key; now the cast initialises the state it needs and carries on.
		local okEnsure, ensured = pcall(State.ensure, player)
		s = okEnsure and ensured or nil
		if not s then
			reject("profile not ready")
			return
		end
		local dbg2 = workspace:FindFirstChild("GFDebug")
		if dbg2 then dbg2:SetAttribute("CastStateSelfHealed", true) end
	end
	if s.downed then
		reject("downed")
		return
	end
	local abilityId = payload.abilityId
	if type(abilityId) ~= "string" then
		return
	end
	local ability = Abilities.get(abilityId)
	if not ability then
		return
	end
	-- C1: cast authorization. The remote used to accept any ability id from any client, so an
	-- exploiter could cast rank-locked or unowned support on demand. The loadout is the only
	-- legitimate source: the ability must be owned AND occupy one of the player's two slots.
	do
		local armory = script.Parent:FindFirstChild("ArmoryService")
		local sel = armory and require(armory).selection(player)
		local equipped = type(sel) == "table"
			and (sel.ability1 == abilityId or sel.ability2 == abilityId)
		if not equipped then
			reject("not equipped")
			return
		end
	end
	-- rejoin restore: if this fresh state never saw the cast but the player carries a persisted
	-- cooldown end time, the gate still applies — rejoining never resets cooldowns (S05-007).
	local ready = s.cooldowns[abilityId]
	if ready == nil then
		local restoredCd = player:GetAttribute("CD_" .. tostring(abilityId))
		if type(restoredCd) == "number" and restoredCd > now() then
			ready = restoredCd
			s.cooldowns[abilityId] = restoredCd
		end
	end
	if ready and now() < ready then
		reject("cooling down")
		return
	end
	local position = payload.position
	if typeof(position) ~= "Vector3" then
		return
	end
	-- typeof() passes NaN-bearing vectors; NaN comparisons then corrupt every distance check below.
	if not require(script.Parent.NetGuard).finiteVector3(position) then
		reject("non-finite position")
		return
	end
	-- S05-004 placement validation: the target point must sit in open space — not inside solid
	-- geometry, not below the terrain kill plane, not beyond the mission boundary. Rejecting with a
	-- reason beats silently clamping: the player learns the throw was illegal rather than whiffing.
	do
		local probe = workspace:Raycast(position + Vector3.new(0, 0.5, 0), Vector3.new(0, -1.2, 0))
		local inside = workspace:Raycast(position, Vector3.new(0, 2, 0))
		local solidAbove = inside ~= nil and (position.Y + 1.8) > inside.Position.Y and inside.Instance ~= nil
		if position.Y < -50 then
			reject("placement invalid: out of bounds")
			return
		end
		-- a point buried inside a wall has geometry in every direction; sample three short rays
		local buried = 0
		for _, dir in ipairs({ Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1) }) do
			if workspace:Raycast(position, dir * 1.5) then
				buried += 1
			end
		end
		if buried >= 3 then
			reject("placement invalid: inside geometry")
			return
		end
	end
	if emergencyActive() then
		reject("emergency withdrawal: support disabled")
		return
	end
	if player:GetAttribute("GF_Aboard") == true then
		reject("aboard dropship")
		return
	end
	-- S05-003: every ability deploys from a thrown physical signal flare/device. The flare arcs from
	-- the thrower to the target point (same ballistic family as grenades), visibly burning red, and
	-- the ability effect triggers where it lands rather than at the bare aim point.
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	-- C2a: range preflight at cast time. Implementations re-check at landing; rejecting here saves
	-- the flare animation and gives immediate feedback for illegal throws.
	if (position - root.Position).Magnitude > (tonumber(ability.range) or 90) * 1.15 then
		reject("out of range")
		return
	end
	-- C2b: one in-flight cast per ability per player. Cleared when the flare lands and dispatches,
	-- or if anything errors before that.
	s.castInFlight = s.castInFlight or {}
	if s.castInFlight[abilityId] then
		reject("already deploying")
		return
	end
	s.castInFlight[abilityId] = true
	local flare = Instance.new("Part")
	flare.Name = "SignalFlare"
	flare.Shape = Enum.PartType.Ball
	flare.Size = Vector3.new(0.5, 0.5, 0.5)
	flare.Material = Enum.Material.Neon
	flare.Color = Color3.fromRGB(255, 80, 60)
	flare.CanCollide = false
	flare.Anchored = true
	flare.CFrame = CFrame.new(root.Position + Vector3.new(0, 2, 0))
	flare.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 90, 60)
	light.Range = 10
	light.Brightness = 2
	light.Parent = flare
	local origin = flare.Position
	local travel = math.clamp((position - origin).Magnitude / 55, 0.45, 1.1)
	task.spawn(function()
		-- ballistic arc: quadratic bezier with a height bump, matching grenade trajectory feel
		local mid = (origin + position) / 2 + Vector3.new(0, math.max(6, (position - origin).Magnitude * 0.18), 0)
		local t0 = os.clock()
		while os.clock() - t0 < travel do
			local alpha = (os.clock() - t0) / travel
			local a = origin:Lerp(mid, alpha)
			local b = mid:Lerp(position, alpha)
			flare.CFrame = CFrame.new(a:Lerp(b, alpha))
			task.wait()
		end
		flare.CFrame = CFrame.new(position)
		-- red signal smoke at the landing point so the squad sees where support is coming down
		flare.Size = Vector3.new(1.2, 1.2, 1.2)
		task.delay(1.5, function()
			if flare.Parent then
				flare:Destroy()
			end
		end)
		if abilityId == "Airstrike" then
			airstrike(player, s, position)
		elseif abilityId == "DomeShield" then
			dome(player, s, position)
		elseif abilityId == "Sentry" then
			sentry(player, s, position)
		elseif abilityId == "OrbitalStrike" then
			orbital(player, s, position)
		elseif abilityId == "OrbitalLance" then
			orbitalLance(player, s, position)
		elseif abilityId == "ReflectiveBarrier" then
			reflectiveBarrier(player, s, position)
		end
		local live = State.get(player)
		if live and live.castInFlight then
			live.castInFlight[abilityId] = nil
		end
	end)
end
-- Orbital Lance (spec): 4s telegraph, then a narrow sustained beam — 3 pulses over 3 seconds,
-- 140 damage each in radius 6 (420 total if a target eats all three). Unlike the strike's single
-- wide hammer blow, the lance is precise area denial: thin column, long burn, no falloff mercy.
local function orbitalLance(player: Player, s: any, position: Vector3)
	local ability = Abilities.get("OrbitalLance")
	if not ability then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if (position - root.Position).Magnitude > (ability.range or 90) then
		reportReject(player, "out of range")
		return
	end
	local supportDamageScale, supportRadiusScale = supportStats(player)
	local radius = (ability.radius or 6) * supportRadiusScale
	beginCooldown(player, s, ability)
	ReplicatedStorage.GF.Remotes.AbilityStateChanged:FireClient(player, { abilityId = ability.id, duration = ability.cooldown })
	-- 4s telegraph: thin targeting ring + rising tone, distinct from the strike's wide ring
	shockRing(position, Color3.fromRGB(140, 200, 255), radius * 0.8, 14)
	boom(position, 0.2, 0.6)
	local castId = "lance" .. tostring(player.UserId) .. ":" .. tostring(os.clock())
	task.delay(4.0, function()
		if cancelForEmergency(player, "OrbitalLance") then return end
		-- sustained beam column for the full 3s burn
		local beam = Instance.new("Part")
		beam.Name = "OrbitalLanceBeam"
		beam.Shape = Enum.PartType.Cylinder
		beam.Size = Vector3.new(220, radius * 1.2, radius * 1.2)
		beam.CFrame = CFrame.new(position + Vector3.new(0, 110, 0)) * CFrame.Angles(0, 0, math.rad(90))
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.Material = Enum.Material.Neon
		beam.Color = Color3.fromRGB(150, 210, 255)
		beam.Transparency = 0.1
		beam.Parent = workspace
		for pulse = 1, 3 do
			task.delay((pulse - 1) * 1.0, function()
				if not beam.Parent then return end
				-- pulse flash: beam brightens and widens momentarily each second
				beam.Transparency = 0
				beam.Size = Vector3.new(220, radius * 2, radius * 2)
				TweenService:Create(beam, TweenInfo.new(0.5), { Transparency = 0.25, Size = Vector3.new(220, radius * 1.2, radius * 1.2) }):Play()
				boom(position, 0.35, 0.5 + pulse * 0.1)
				ReplicatedStorage.GF.Remotes.AbilityImpact:FireAllClients("OrbitalLance", position)
				local pulseDamage = (ability.damage / 3) * supportDamageScale
				require(ServerScriptService.GF.Services.CombatService).damageAlliesInRadius(position, radius * supportRadiusScale, pulseDamage * 0.5, player)
				for _, enemy in enemiesInRadius(position, radius * supportRadiusScale) do
					abilityDamageEnemy(castId, enemy, pulseDamage, player, position)
				end
			end)
		end
		task.delay(3.2, function() if beam.Parent then beam:Destroy() end end)
	end)
end

-- Reflective Barrier (spec): 7s bubble around the caster. Enemy fire is intercepted and reflected
-- back at the attacker at half damage, up to 8 reflections. The interception itself lives in
-- VitalsService.applyDamage — the single choke point all enemy damage crosses — querying the
-- registry below. Reflections exhausted or duration ended: the barrier drops visually either way.
local activeBarriers: { [Player]: { model: BasePart, expiresAt: number, reflections: number } } = {}
local function reflectiveBarrier(player: Player, s: any, position: Vector3)
	local ability = Abilities.get("ReflectiveBarrier")
	if not ability then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	beginCooldown(player, s, ability)
	ReplicatedStorage.GF.Remotes.AbilityStateChanged:FireClient(player, { abilityId = ability.id, duration = ability.cooldown })
	if activeBarriers[player] and activeBarriers[player].model.Parent then
		activeBarriers[player].model:Destroy()
	end
	local bubble = Instance.new("Part")
	bubble.Name = "ReflectiveBarrier"
	bubble.Shape = Enum.PartType.Ball
	local radius = ability.radius or 10
	bubble.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CanTouch = false
	bubble.Material = Enum.Material.ForceField
	bubble.Color = Color3.fromRGB(140, 220, 255)
	bubble.Transparency = 0.55
	bubble.CFrame = CFrame.new(root.Position)
	bubble.Parent = workspace
	activeBarriers[player] = { model = bubble, expiresAt = os.clock() + (ability.duration or 7), reflections = 0 }
	workspace:SetAttribute("GF_BarrierActive_" .. player.UserId, true)
	local started = os.clock()
	task.spawn(function()
		while bubble.Parent and os.clock() < activeBarriers[player].expiresAt do
			-- the barrier travels with the caster — it is a personal shield, not a placed dome
			local liveRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if liveRoot then
				bubble.CFrame = CFrame.new(liveRoot.Position)
			end
			task.wait(0.1)
		end
		if bubble.Parent then bubble:Destroy() end
		workspace:SetAttribute("GF_BarrierActive_" .. player.UserId, false)
		if activeBarriers[player] and activeBarriers[player].model == bubble then
			activeBarriers[player] = nil
		end
		workspace:SetAttribute("GF_BarrierLife_" .. player.UserId, os.clock() - started)
	end)
end

-- VitalsService calls through this: returns the barrier entry when interception should happen.
function AbilityService.barrierFor(player: Player)
	local b = activeBarriers[player]
	if b and b.model.Parent and os.clock() < b.expiresAt and b.reflections < 8 then
		return b
	end
	return nil
end
-- a reflection consumed: count it, flash the bubble, damage the attacker at half strength.
function AbilityService.consumeReflection(player: Player, attacker: Model?, amount: number)
	local b = activeBarriers[player]
	if not b then return end
	b.reflections += 1
	b.model.Color = Color3.fromRGB(255, 255, 255)
	task.delay(0.12, function()
		if b.model.Parent then b.model.Color = Color3.fromRGB(140, 220, 255) end
	end)
	ReplicatedStorage.GF.Remotes.AbilityImpact:FireAllClients("Reflect", b.model.Position)
	if attacker and attacker.Parent then
		local ok = pcall(function()
			require(ServerScriptService.GF.Services.CombatService).damageEnemy(attacker, amount * 0.5, player)
		end)
		workspace:SetAttribute("GF_BarrierReflectDmg_" .. player.UserId, amount * 0.5)
	end
	workspace:SetAttribute("GF_BarrierReflections_" .. player.UserId, b.reflections)
end

function AbilityService.start()
	if AbilityService._connected then
		return
	end
	AbilityService._connected = true
	ReplicatedStorage.GF.Remotes.UseAbility.OnServerEvent:Connect(function(player, payload)
		if not require(script.Parent.NetGuard).allowPayload(player, "ability", payload) then
			return
		end
		local dbg = workspace:FindFirstChild("GFDebug")
		if dbg then
			dbg:SetAttribute("AbilityCastRequests", (dbg:GetAttribute("AbilityCastRequests") or 0) + 1)
		end
		local st = State.get(player)
		if st then st.abilityCount = (st.abilityCount or 0) + 1 end
		local ok, err = pcall(cast, player, payload)
		if not ok then
			warn("[GF] CastAbility error: " .. tostring(err))
		end
	end)
	local dbg = workspace:FindFirstChild("GFDebug")
	if dbg then dbg:SetAttribute("AbilityHandlerConnected", true) end
	print("[GF] ability handler connected")
end
-- Exposed for server-side callers (AI squad, scripted encounters) and for verification: the
-- remote path is one entry point, not the only way an ability can be cast.
AbilityService.cast = cast
-- Studio-only test hook: cooldowns are the one gate that makes an ability impossible to re-exercise in
-- a single session, and the rejection telemetry ("cooling down") already reports when that happens.
function AbilityService.resetCooldowns(player: Player)
	local s = State.get(player)
	if not s then
		return false
	end
	table.clear(s.cooldowns)
	return true
end
AbilityService.reportReject = reportReject

-- S05-019 emergency withdraw: when the squad withdraws the ability layer locks — new calls
-- reject outright and support strikes already in flight cancel before they land. A withdrawing
-- squad is disengaging, not escalating.
local withdrawActive = false

function AbilityService.emergencyWithdraw()
	withdrawActive = true
	workspace:SetAttribute("GF_AbilityLockdown", true)
	-- cancel unlanded support: any strike with a pending impact scrubbed
	workspace:SetAttribute("GF_SupportCancelled", os.clock())
end

function AbilityService.isWithdrawLocked(): boolean
	return withdrawActive
end

function AbilityService.clearWithdraw()
	withdrawActive = false
	workspace:SetAttribute("GF_AbilityLockdown", false)
end

-- S05-002 dual ability slots: every class carries two equipped abilities and both are ready
-- on first deploy — no empty second slot, no warm-up delay on the initial drop.
local equippedSlots: { [Player]: { [number]: string } } = {}

function AbilityService.equipSlot(plr: Player, slot: number, abilityId: string): boolean
	if slot ~= 1 and slot ~= 2 then
		return false
	end
	if not equippedSlots[plr] then
		equippedSlots[plr] = {}
	end
	equippedSlots[plr][slot] = abilityId
	plr:SetAttribute("GF_AbilitySlot" .. slot, abilityId)
	return true
end

function AbilityService.getEquipped(plr: Player): { [number]: string }
	return equippedSlots[plr] or {}
end

function AbilityService.readyOnDeploy(plr: Player)
	-- both slots start off cooldown at first deploy — spec mandates readiness
	for slot = 1, 2 do
		plr:SetAttribute("GF_AbilityCooldown" .. slot, 0)
	end
end

game:GetService("Players").PlayerRemoving:Connect(function(plr)
	equippedSlots[plr] = nil
end)

return AbilityService
