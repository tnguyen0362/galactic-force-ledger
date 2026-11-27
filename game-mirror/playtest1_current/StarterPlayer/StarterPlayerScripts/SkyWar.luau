--!strict
-- SkyWar (Phase 15, COSMETIC ONLY, client-side): the planetary war overhead, Helldivers-2 flavoured.
-- Layered over the existing daylight dome (Environment deliberately destroys the Sky in missions, Spec S27):
--   * burning horizon: a few persistent smoke columns with flickering fire glow at the edge of the fog
--   * missile salvos: 3-5 missiles arcing across the sky with long vapour trails
--   * orbital strikes: light column + flash + smoke bloom on the far ground
--   * flak bursts, high-altitude streaks, and the occasional capital ship crossing
-- Everything lives in a client-only folder, non-collidable/non-queryable/no shadows, never touches gameplay,
-- and sits at a fraction of Lighting.FogEnd so the biome fog dissolves it.
-- PERFORMANCE: hard cap on live effects (1 part per flak, <=2 per missile, ~5 per strike), persistent columns
-- are re-anchored to the camera only after it moves, nothing allocates per frame, and everything scales down
-- with the graphics preset (Low = fully off). Typical live part count: 15 columns + <=25 effect parts.
-- Palette: Human fleet graphite #252D35 / cyan #58C8F0; Ascendancy obsidian #24212A / bronze #967854 with a
-- restrained violet engine glow. Fire/strikes warm amber; smoke dark ash.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local rng = Random.new()
local folder = Instance.new("Folder")
folder.Name = "GFSkyWar"
folder.Parent = workspace

type Effect = { step: (t: number, origin: Vector3) -> boolean, destroy: () -> () }
local effects: { Effect } = {}
local startedAt: { [Effect]: number } = {}
local shipAlive = false

local ASH = Color3.fromRGB(52, 47, 45)
local FIRE = Color3.fromRGB(255, 150, 70)
local WARM = Color3.fromRGB(255, 190, 120)
local CYAN = Color3.fromRGB(88, 200, 240)

local function tier(): number
	-- 0 off, 1 light, 2 default, 3 full
	local g = workspace:GetAttribute("GF_GraphicsPreset")
	if g == "Low" then return 0 end
	if g == "Balanced" or g == nil then return 2 end
	if g == "Medium" then return 1 end
	return 3
end

local function enabled(): boolean
	if workspace:GetAttribute("GF_EnvironmentPreset") ~= "mission" then return false end
	return tier() > 0
end

local function skyDist(): number
	return math.clamp(Lighting.FogEnd * 0.55, 1200, 3200)
end

local function mk(size: Vector3, color: Color3, neon: boolean, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Locked = true
	if shape then p.Shape = shape end
	p.Parent = folder
	return p
end

local function cleanAll()
	for _, e in effects do e.destroy() end
	table.clear(effects)
	table.clear(startedAt)
	shipAlive = false
end

local function add(e: Effect)
	table.insert(effects, e)
end

---------------------------------------------------------------- burning horizon (persistent)
type Column = { smoke: Part, cap: Part, glow: Part, radial: Vector3, h: number, phase: number }
local columns: { Column } = {}
local lastAnchor: Vector3? = nil
local lastColD = 0

local function destroyColumns()
	for _, c in columns do c.smoke:Destroy() c.cap:Destroy() c.glow:Destroy() end
	table.clear(columns)
	lastAnchor = nil
end

local function buildColumns(d: number, count: number)
	destroyColumns()
	lastColD = d
	-- spread around the full circle with jitter so there is always something burning on any heading
	local base = rng:NextNumber(0, math.pi * 2)
	for i = 1, count do
		local az = base + (i - 1) * (math.pi * 2 / count) + rng:NextNumber(-0.35, 0.35)
		local h = d * rng:NextNumber(0.14, 0.26)
		local w = d * rng:NextNumber(0.012, 0.022)
		local smoke = mk(Vector3.new(h, w, w), ASH, false, Enum.PartType.Cylinder)
		smoke.Transparency = 0.38
		local cap = mk(Vector3.one * (w * 4.2), Color3.fromRGB(70, 64, 62), false, Enum.PartType.Ball)
		cap.Transparency = 0.55
		local glow = mk(Vector3.one * (w * 1.8), FIRE, true, Enum.PartType.Ball)
		glow.Transparency = 0.25
		table.insert(columns, { smoke = smoke, cap = cap, glow = glow, radial = Vector3.new(math.cos(az), 0, math.sin(az)), h = h, phase = rng:NextNumber(0, 6.28) })
	end
end

local function placeColumns(o: Vector3, d: number)
	for _, c in columns do
		local ground = o + c.radial * d + Vector3.new(0, -d * 0.07, 0)
		c.glow.CFrame = CFrame.new(ground + Vector3.new(0, d * 0.004, 0))
		c.smoke.CFrame = CFrame.new(ground + Vector3.new(0, c.h * 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		c.cap.CFrame = CFrame.new(ground + Vector3.new(0, c.h, 0))
	end
	lastAnchor = o
end

local function flickerColumns(now: number)
	for _, c in columns do
		c.glow.Transparency = 0.2 + 0.3 * math.abs(math.sin(now * 5 + c.phase) * math.sin(now * 2.3 + c.phase * 1.7))
	end
end

---------------------------------------------------------------- effects
-- orbital strike: a light column from the sky to the far ground, then flash + smoke bloom
local function spawnStrike(origin: Vector3)
	local d = skyDist()
	local az = rng:NextNumber(0, math.pi * 2)
	local base = origin + Vector3.new(math.cos(az) * d, -d * 0.05, math.sin(az) * d)
	local h = math.min(d * 0.55, 1900)
	local w = d * 0.006
	local col = mk(Vector3.new(w, 1, w), Color3.fromRGB(255, 214, 170), true)
	local flash = mk(Vector3.one * (d * 0.01), FIRE, true, Enum.PartType.Ball)
	local smoke = mk(Vector3.one * (d * 0.01), ASH, false, Enum.PartType.Ball)
	local rel = base - origin
	local life = 3.6
	add({
		step = function(t, o)
			if t > life then return false end
			local pos = o + rel
			local grow = math.min(t / 0.18, 1)
			local colH = h * grow
			col.Size = Vector3.new(w * (1 + t * 1.4), colH, w * (1 + t * 1.4))
			col.CFrame = CFrame.new(pos + Vector3.new(0, colH * 0.5, 0))
			col.Transparency = math.clamp((t - 0.25) / 1.6, 0, 1)
			local f = math.clamp(t / 2.2, 0, 1)
			flash.Size = Vector3.one * (d * (0.01 + 0.09 * f))
			flash.CFrame = CFrame.new(pos + Vector3.new(0, d * 0.02, 0))
			flash.Transparency = math.clamp(0.15 + f, 0, 1)
			local s = math.clamp(t / life, 0, 1)
			smoke.Size = Vector3.one * (d * (0.015 + 0.12 * s))
			smoke.CFrame = CFrame.new(pos + Vector3.new(0, d * (0.03 + 0.05 * s), 0))
			smoke.Transparency = 0.35 + 0.65 * s
			return true
		end,
		destroy = function() col:Destroy() flash:Destroy() smoke:Destroy() end,
	})
end

-- missile salvo: 3-5 missiles on shallow arcs, each with a bright head and a vapour trail that lingers
local function spawnSalvo(origin: Vector3)
	local d = skyDist()
	local az = rng:NextNumber(0, math.pi * 2)
	local radial = Vector3.new(math.cos(az), 0, math.sin(az))
	local tangent = Vector3.new(-math.sin(az), 0, math.cos(az)) * (rng:NextInteger(0, 1) == 0 and 1 or -1)
	local n = rng:NextInteger(3, tier() >= 3 and 6 or 4)
	local fly = rng:NextNumber(4.2, 5.6)
	local span = d * rng:NextNumber(0.5, 0.8)
	local apex = d * rng:NextNumber(0.2, 0.38)
	local startRel = radial * d * rng:NextNumber(0.85, 1.0) + Vector3.new(0, -d * 0.06, 0)
	local lead = 0.2
	local tailLen = 0.26
	local ms: { { head: Part, trail: Part, delay: number, jitter: Vector3 } } = {}
	local hot = rng:NextNumber() < 0.7
	for i = 1, n do
		local head = mk(Vector3.new(d * 0.003, d * 0.003, d * 0.016), hot and WARM or CYAN, true)
		local trail = mk(Vector3.new(d * 0.002, d * 0.002, 1), Color3.fromRGB(200, 196, 190), false)
		table.insert(ms, {
			head = head, trail = trail,
			delay = (i - 1) * rng:NextNumber(0.1, 0.35),
			jitter = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.2, 0.4), rng:NextNumber(-1, 1)) * d * 0.03,
		})
	end
	local function pos(m: { head: Part, trail: Part, delay: number, jitter: Vector3 }, u: number, o: Vector3): Vector3
		return o + startRel + m.jitter + tangent * span * u + Vector3.new(0, apex * 4 * u * (1 - u), 0)
	end
	add({
		step = function(t, o)
			local alive = false
			for _, m in ms do
				local lt = t - m.delay
				if lt < 0 then
					m.head.Transparency = 1
					m.trail.Transparency = 1
					alive = true
					continue
				end
				local u = lt / fly
				if u > 1 + tailLen + 0.4 then
					m.head.Transparency = 1
					m.trail.Transparency = 1
					continue
				end
				alive = true
				local uh = math.min(u, 1)
				local ut = math.clamp(u - lead - tailLen, 0, 1) -- tail trails behind, catches up after impact
				local hp = pos(m, uh, o)
				local tp = pos(m, math.max(ut, 0), o)
				local len = math.max((hp - tp).Magnitude, 1)
				m.trail.Size = Vector3.new(d * 0.002, d * 0.002, len)
				m.trail.CFrame = CFrame.lookAt(tp:Lerp(hp, 0.5), hp)
				m.trail.Transparency = u > 1 and math.clamp((u - 1) / (tailLen + 0.4), 0.45, 1) or 0.45
				local nextP = pos(m, math.min(uh + 0.02, 1), o)
				if (nextP - hp).Magnitude > 0.01 then m.head.CFrame = CFrame.lookAt(hp, nextP) else m.head.CFrame = CFrame.new(hp) end
				m.head.Transparency = u >= 1 and 1 or 0
			end
			return alive
		end,
		destroy = function() for _, m in ms do m.head:Destroy() m.trail:Destroy() end end,
	})
end

-- anti-air flak: a hot flash that cools into a lingering ash puff high in the sky
local function spawnFlak(origin: Vector3)
	local d = skyDist()
	local az = rng:NextNumber(0, math.pi * 2)
	local rel = Vector3.new(math.cos(az) * d * rng:NextNumber(0.8, 1), d * rng:NextNumber(0.12, 0.34), math.sin(az) * d * rng:NextNumber(0.8, 1))
	local flash = mk(Vector3.one * (d * 0.012), WARM, true, Enum.PartType.Ball)
	local puff = mk(Vector3.one * (d * 0.012), ASH, false, Enum.PartType.Ball)
	local life = 4.5
	add({
		step = function(t, o)
			if t > life then return false end
			local p = o + rel
			local f = math.clamp(t / 0.5, 0, 1)
			flash.Size = Vector3.one * (d * (0.012 + 0.02 * f))
			flash.CFrame = CFrame.new(p)
			flash.Transparency = math.clamp(t / 0.6, 0, 1)
			local s = math.clamp(t / life, 0, 1)
			puff.Size = Vector3.one * (d * (0.014 + 0.04 * s))
			puff.CFrame = CFrame.new(p + Vector3.new(0, d * 0.01 * s, 0))
			puff.Transparency = 0.45 + 0.55 * s
			return true
		end,
		destroy = function() flash:Destroy() puff:Destroy() end,
	})
end

-- high-altitude streak (interceptor/strike craft or falling ordnance)
local function spawnStreak(origin: Vector3)
	local d = skyDist()
	local az = rng:NextNumber(0, math.pi * 2)
	local radial = Vector3.new(math.cos(az), 0, math.sin(az))
	local tangent = Vector3.new(-math.sin(az), 0, math.cos(az)) * (rng:NextInteger(0, 1) == 0 and 1 or -1)
	local rel = radial * d + Vector3.new(0, d * rng:NextNumber(0.3, 0.55), 0)
	local vel = (tangent * 0.85 + Vector3.new(0, -0.35, 0) + radial * 0.05).Unit * d * rng:NextNumber(0.3, 0.45)
	local cyan = rng:NextNumber() < 0.35
	local part = mk(Vector3.new(d * 0.004, d * 0.004, d * 0.09), cyan and CYAN or WARM, true)
	local life = 5
	add({
		step = function(t, o)
			if t > life then return false end
			local p = o + rel + vel * t
			part.CFrame = CFrame.lookAt(p, p + vel)
			part.Transparency = math.clamp(math.max((t - 3.8) / 1.2, (0.6 - t) / 0.6), 0, 1)
			return true
		end,
		destroy = function() part:Destroy() end,
	})
end

-- capital ship crossing the sky; faction picks the silhouette
local function spawnShip(origin: Vector3)
	if shipAlive then return end
	shipAlive = true
	local d = skyDist()
	local u = d * 0.01
	local ascendancy = rng:NextNumber() < 0.4
	local az = rng:NextNumber(0, math.pi * 2)
	local radial = Vector3.new(math.cos(az), 0, math.sin(az))
	local tangent = Vector3.new(-math.sin(az), 0, math.cos(az)) * (rng:NextInteger(0, 1) == 0 and 1 or -1)
	local alt = d * rng:NextNumber(0.28, 0.45)
	local startRel = radial * d + Vector3.new(0, alt, 0) - tangent * d * 0.45
	local speed = d * 0.011
	local life = 75

	local parts: { { part: Part, off: CFrame, baseT: number } } = {}
	local function addPart(size: Vector3, off: CFrame, color: Color3, neon: boolean, baseT: number?)
		local p = mk(size, color, neon)
		table.insert(parts, { part = p, off = off, baseT = baseT or 0 })
	end
	if ascendancy then
		local obs, bronze = Color3.fromRGB(36, 33, 42), Color3.fromRGB(150, 120, 84)
		addPart(Vector3.new(u * 1.4, u * 1.0, u * 20), CFrame.new(), obs, false)
		addPart(Vector3.new(u * 0.6, u * 0.5, u * 6), CFrame.new(0, u * 0.7, u * 4), Color3.fromRGB(81, 70, 94), false)
		addPart(Vector3.new(u * 5, u * 0.3, u * 3.2), CFrame.new(0, 0, -u * 4), obs, false)
		addPart(Vector3.new(u * 0.4, u * 0.4, u * 14), CFrame.new(0, -u * 0.65, u * 1), bronze, false)
		addPart(Vector3.new(u * 0.9, u * 0.6, u * 0.3), CFrame.new(0, 0, -u * 10.1), Color3.fromRGB(169, 99, 233), true, 0.45)
	else
		local gra, steel = Color3.fromRGB(37, 45, 53), Color3.fromRGB(131, 144, 155)
		addPart(Vector3.new(u * 3, u * 1.8, u * 14), CFrame.new(), gra, false)
		addPart(Vector3.new(u * 3.4, u * 0.5, u * 11), CFrame.new(0, u * 1.05, -u * 0.5), steel, false)
		addPart(Vector3.new(u * 1.6, u * 1.2, u * 3), CFrame.new(0, u * 1.8, -u * 4), Color3.fromRGB(59, 77, 96), false)
		addPart(Vector3.new(u * 0.9, u * 0.9, u * 0.5), CFrame.new(-u * 0.9, 0, -u * 7.2), CYAN, true)
		addPart(Vector3.new(u * 0.9, u * 0.9, u * 0.5), CFrame.new(u * 0.9, 0, -u * 7.2), CYAN, true)
		addPart(Vector3.new(u * 0.2, u * 0.2, u * 12), CFrame.new(0, u * 1.4, u * 0.5), CYAN, true, 0.6)
	end
	add({
		step = function(t, o)
			if t > life then return false end
			local fade = math.clamp(math.min(t / 6, (life - t) / 6), 0, 1)
			local pos = o + startRel + tangent * speed * t
			local base = CFrame.lookAt(pos, pos + tangent)
			for _, e in parts do
				e.part.CFrame = base * e.off
				e.part.Transparency = math.clamp(e.baseT + (1 - fade), 0, 1)
			end
			return true
		end,
		destroy = function()
			for _, e in parts do e.part:Destroy() end
			shipAlive = false
		end,
	})
end

---------------------------------------------------------------- driver
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local o = cam.CFrame.Position
	if #columns > 0 then
		local a = lastAnchor
		if not a or (o - a).Magnitude > 25 then placeColumns(o, lastColD) end
		flickerColumns(os.clock())
	end
	if #effects == 0 then return end
	local now = os.clock()
	for i = #effects, 1, -1 do
		local e = effects[i]
		local start = startedAt[e]
		if not start then start = now startedAt[e] = now end
		if not e.step(now - start, o) then
			e.destroy()
			startedAt[e] = nil
			table.remove(effects, i)
		end
	end
end)

task.spawn(function()
	task.wait(6)
	while true do
		task.wait(rng:NextNumber(2.5, 6))
		if not enabled() then
			if #effects > 0 then cleanAll() end
			if #columns > 0 then destroyColumns() end
			continue
		end
		local cam = workspace.CurrentCamera
		if not cam then continue end
		local o = cam.CFrame.Position
		local t = tier()
		-- burning horizon: build once per mission (or when fog distance changes a lot)
		local want = t >= 3 and 5 or (t == 2 and 4 or 2)
		local d = skyDist()
		if #columns ~= want or math.abs(d - lastColD) > d * 0.25 then
			buildColumns(d, want)
			placeColumns(o, d)
		end
		local cap = t >= 3 and 6 or (t == 2 and 4 or 3)
		if #effects >= cap then continue end
		local roll = rng:NextNumber()
		if roll < 0.18 then
			spawnStrike(o)
		elseif roll < 0.5 then
			spawnSalvo(o)
		elseif roll < 0.72 then
			spawnFlak(o)
		elseif roll < 0.84 then
			spawnStreak(o)
		else
			spawnShip(o)
		end
	end
end)
