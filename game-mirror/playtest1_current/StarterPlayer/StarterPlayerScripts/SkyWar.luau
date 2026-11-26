--!strict
-- SkyWar (Phase 15, COSMETIC ONLY, client-side): the planetary war overhead.
-- Helldivers-style backdrop: orbital strikes landing on a far horizon, capital ships crossing a hazy sky,
-- distant flashes. Everything lives in a client-only folder, is non-collidable and non-queryable, never
-- touches gameplay, and fades into the biome fog because it is placed at a fraction of Lighting.FogEnd.
-- Bounded: at most 1 ship + 2 other effects alive. Disabled in the station and on the Low graphics preset.
-- Palette: Human fleet graphite #252D35 / cyan #58C8F0; Ascendancy obsidian #24212A / bronze #967854 with a
-- restrained violet engine glow (#A963E9 at low intensity). Strikes are warm amber/white.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local rng = Random.new()
local folder = Instance.new("Folder")
folder.Name = "GFSkyWar"
folder.Parent = workspace

type Effect = { step: (t: number, origin: Vector3) -> boolean, destroy: () -> () }
local effects: { Effect } = {}
local shipAlive = false

local function enabled(): boolean
	if workspace:GetAttribute("GF_EnvironmentPreset") ~= "mission" then return false end
	return workspace:GetAttribute("GF_GraphicsPreset") ~= "Low"
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
	shipAlive = false
end

-- orbital strike: a light column from the sky to the far ground, then flash + smoke bloom
local function spawnStrike(origin: Vector3)
	local d = skyDist()
	local az = rng:NextNumber(0, math.pi * 2)
	local base = origin + Vector3.new(math.cos(az) * d, -d * 0.05, math.sin(az) * d)
	local h = math.min(d * 0.55, 1900)
	local w = d * 0.006
	local col = mk(Vector3.new(w, 1, w), Color3.fromRGB(255, 214, 170), true)
	local flash = mk(Vector3.one * (d * 0.01), Color3.fromRGB(255, 190, 120), true, Enum.PartType.Ball)
	local smoke = mk(Vector3.one * (d * 0.01), Color3.fromRGB(58, 52, 50), false, Enum.PartType.Ball)
	local rel = base - origin
	local life = 3.6
	table.insert(effects, {
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

-- high-altitude streak (interceptor/strike craft or falling ordnance)
local function spawnStreak(origin: Vector3)
	local d = skyDist()
	local az = rng:NextNumber(0, math.pi * 2)
	local radial = Vector3.new(math.cos(az), 0, math.sin(az))
	local tangent = Vector3.new(-math.sin(az), 0, math.cos(az)) * (rng:NextInteger(0, 1) == 0 and 1 or -1)
	local rel = radial * d + Vector3.new(0, d * rng:NextNumber(0.3, 0.55), 0)
	local vel = (tangent * 0.85 + Vector3.new(0, -0.35, 0) + radial * 0.05).Unit * d * rng:NextNumber(0.3, 0.45)
	local cyan = rng:NextNumber() < 0.35
	local part = mk(Vector3.new(d * 0.004, d * 0.004, d * 0.09), cyan and Color3.fromRGB(88, 200, 240) or Color3.fromRGB(255, 190, 120), true)
	local life = 5
	table.insert(effects, {
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
	local function add(size: Vector3, off: CFrame, color: Color3, neon: boolean, baseT: number?)
		local p = mk(size, color, neon)
		table.insert(parts, { part = p, off = off, baseT = baseT or 0 })
	end
	if ascendancy then
		local obs, bronze = Color3.fromRGB(36, 33, 42), Color3.fromRGB(150, 120, 84)
		add(Vector3.new(u * 1.4, u * 1.0, u * 20), CFrame.new(), obs, false)
		add(Vector3.new(u * 0.6, u * 0.5, u * 6), CFrame.new(0, u * 0.7, u * 4), Color3.fromRGB(81, 70, 94), false)
		add(Vector3.new(u * 5, u * 0.3, u * 3.2), CFrame.new(0, 0, -u * 4), obs, false)
		add(Vector3.new(u * 0.4, u * 0.4, u * 14), CFrame.new(0, -u * 0.65, u * 1), bronze, false)
		add(Vector3.new(u * 0.9, u * 0.6, u * 0.3), CFrame.new(0, 0, -u * 10.1), Color3.fromRGB(169, 99, 233), true, 0.45)
	else
		local gra, steel = Color3.fromRGB(37, 45, 53), Color3.fromRGB(131, 144, 155)
		add(Vector3.new(u * 3, u * 1.8, u * 14), CFrame.new(), gra, false)
		add(Vector3.new(u * 3.4, u * 0.5, u * 11), CFrame.new(0, u * 1.05, -u * 0.5), steel, false)
		add(Vector3.new(u * 1.6, u * 1.2, u * 3), CFrame.new(0, u * 1.8, -u * 4), Color3.fromRGB(59, 77, 96), false)
		add(Vector3.new(u * 0.9, u * 0.9, u * 0.5), CFrame.new(-u * 0.9, 0, -u * 7.2), Color3.fromRGB(88, 200, 240), true)
		add(Vector3.new(u * 0.9, u * 0.9, u * 0.5), CFrame.new(u * 0.9, 0, -u * 7.2), Color3.fromRGB(88, 200, 240), true)
		add(Vector3.new(u * 0.2, u * 0.2, u * 12), CFrame.new(0, u * 1.4, u * 0.5), Color3.fromRGB(88, 200, 240), true, 0.6)
	end
	table.insert(effects, {
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

local t0: { [Effect]: number } = {}

RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	if #effects == 0 then return end
	local o = cam.CFrame.Position
	local now = os.clock()
	for i = #effects, 1, -1 do
		local e = effects[i]
		local start = t0[e]
		if not start then start = now t0[e] = now end
		if not e.step(now - start, o) then
			e.destroy()
			t0[e] = nil
			table.remove(effects, i)
		end
	end
end)

task.spawn(function()
	task.wait(8)
	while true do
		task.wait(rng:NextNumber(4, 9))
		if not enabled() then
			if #effects > 0 then cleanAll() end
			continue
		end
		local cam = workspace.CurrentCamera
		if not cam or #effects >= 3 then continue end
		local o = cam.CFrame.Position
		local roll = rng:NextNumber()
		if roll < 0.4 then
			spawnStrike(o)
		elseif roll < 0.75 then
			spawnStreak(o)
		else
			spawnShip(o)
		end
	end
end)
