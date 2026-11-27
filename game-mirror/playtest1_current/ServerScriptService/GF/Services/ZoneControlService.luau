--!strict
-- ZoneControlService: capture-zone objective mechanic. A zone is a visible ringed volume the
-- squad must hold: progress accrues while live players are inside and no enemies contest it,
-- pauses while contested, and bleeds slowly back when abandoned. The ring itself is the UI —
-- its colour is the zone state (cyan capturing, red contested, dim when empty) so a player
-- read the situation from across the field without looking at the HUD.
--
-- Server-authoritative: occupancy is scanned server-side every 0.4s, progress never moves
-- on client say-so. Enemies are detected by the GFEnemy tag in ActiveActors. Visual cost is
-- bounded: 20 ring segments + one forcefield cylinder per zone, no per-frame work.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ZoneControlService = {}

export type ZoneOpts = {
	center: Vector3,
	radius: number?,
	label: string?,
	rate: number?, -- progress/sec while held (default 1/75)
	decay: number?, -- progress/sec bleed while empty (default 1/160)
	paused: boolean?, -- spawn paused (events can pause/resume)
	onComplete: ((zone: any) -> ())?,
	onStateChange: ((zone: any, state: string) -> ())?,
}

local RING_SEGMENTS = 20
local active: { any } = {}
local tickStarted = false

local CYAN = Color3.fromRGB(96, 214, 232)
local RED = Color3.fromRGB(255, 96, 84)
local DIM = Color3.fromRGB(72, 84, 96)

local function remote(name: string)
	local gf = ReplicatedStorage:FindFirstChild("GF")
	local remotes = gf and gf:FindFirstChild("Remotes")
	return remotes and remotes:FindFirstChild(name)
end

-- Segmented ring + a low forcefield wall: the boundary must read at a glance in combat.
local function buildRing(zone): Model
	local model = Instance.new("Model")
	model.Name = "ZoneRing_" .. zone.id
	local center, radius = zone.center, zone.radius
	local y = center.Y
	for i = 1, RING_SEGMENTS do
		local a = (i / RING_SEGMENTS) * math.pi * 2
		local seg = Instance.new("Part")
		seg.Name = "RingSeg"
		seg.Shape = Enum.PartType.Cylinder
		seg.Size = Vector3.new(0.35, 1.1, 1.1)
		seg.Material = Enum.Material.Neon
		seg.Color = DIM
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CastShadow = false
		local pos = Vector3.new(center.X + math.cos(a) * radius, y + 0.4, center.Z + math.sin(a) * radius)
		seg.CFrame = CFrame.new(pos) * CFrame.Angles(0, -a, math.pi / 2)
		seg.Parent = model
	end
	local wall = Instance.new("Part")
	wall.Name = "ZoneWall"
	wall.Shape = Enum.PartType.Cylinder
	wall.Size = Vector3.new(5, radius * 2, radius * 2)
	wall.Material = Enum.Material.ForceField
	wall.Color = CYAN
	wall.Transparency = 0.92
	wall.Anchored = true
	wall.CanCollide = false
	wall.CanQuery = false
	wall.CastShadow = false
	wall.CFrame = CFrame.new(Vector3.new(center.X, y + 2.5, center.Z))
	wall.Parent = model
	zone.ringSegs = {}
	for _, s in model:GetChildren() do
		if s.Name == "RingSeg" then
			table.insert(zone.ringSegs, s)
		end
	end
	zone.wall = wall
	model.Parent = workspace
	return model
end

local function paintZone(zone)
	local color = if zone.state == "capturing" then CYAN elseif zone.state == "contested" then RED else DIM
	for _, s in zone.ringSegs do
		s.Color = color
	end
	if zone.wall then
		zone.wall.Color = color
		zone.wall.Transparency = zone.state == "empty" and 0.97 or 0.88
	end
end

local function occupants(zone): (number, number)
	local playersIn = 0
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local delta = root.Position - zone.center
			if Vector3.new(delta.X, 0, delta.Z).Magnitude <= zone.radius and math.abs(delta.Y) < 14 then
				playersIn += 1
			end
		end
	end
	local enemiesIn = 0
	local actors = workspace:FindFirstChild("ActiveActors")
	if actors then
		for _, model in actors:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("GFEnemy") == true then
				local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
				if primary then
					local delta = primary.Position - zone.center
					if Vector3.new(delta.X, 0, delta.Z).Magnitude <= zone.radius and math.abs(delta.Y) < 16 then
						enemiesIn += 1
					end
				end
			end
		end
	end
	return playersIn, enemiesIn
end

local function publish(zone)
	local r = remote("ZoneState")
	if r then
		r:FireAllClients({
			id = zone.id,
			active = true,
			progress = zone.progress,
			state = zone.state,
			label = zone.label,
			center = zone.center,
			radius = zone.radius,
			paused = zone.paused,
		})
	end
	workspace:SetAttribute("GF_ZoneProgress", math.floor(zone.progress * 100))
	workspace:SetAttribute("GF_ZoneState", zone.state)
end

local function destroyVisuals(zone)
	if zone.ringModel and zone.ringModel.Parent then
		-- fade teardown rather than a pop: the ring sinking into the ground reads as the zone closing
		for _, s in zone.ringSegs or {} do
			s.Transparency = 1
		end
		if zone.wall then
			zone.wall.Transparency = 1
		end
		task.delay(0.5, function()
			if zone.ringModel then
				zone.ringModel:Destroy()
			end
		end)
	end
end

function ZoneControlService.create(id: string, opts: ZoneOpts)
	ZoneControlService.destroy(id)
	local zone = {
		id = id,
		center = opts.center,
		radius = opts.radius or 30,
		label = opts.label or "Control zone",
		rate = opts.rate or (1 / 75),
		decay = opts.decay or (1 / 160),
		progress = 0,
		state = "empty",
		paused = opts.paused == true,
		done = false,
		onComplete = opts.onComplete,
		onStateChange = opts.onStateChange,
	}
	zone.ringModel = buildRing(zone)
	active[id] = zone
	paintZone(zone)
	publish(zone)
	if not tickStarted then
		tickStarted = true
		task.spawn(function()
			while true do
				task.wait(0.4)
				ZoneControlService.tick(0.4)
			end
		end)
	end
	return zone
end

function ZoneControlService.tick(dt: number)
	for id, zone in active do
		if not zone.done then
			local playersIn, enemiesIn = occupants(zone)
			local state
			if enemiesIn > 0 then
				state = "contested"
			elseif playersIn > 0 then
				state = "capturing"
			else
				state = "empty"
			end
			if zone.paused then
				state = zone.state == "contested" and "contested" or state
				-- a paused zone still reports occupation state for the ring colour, but never accrues
			end
			if state ~= zone.state then
				zone.state = state
				paintZone(zone)
				if zone.onStateChange then
					zone.onStateChange(zone, state)
				end
			end
			if not zone.paused then
				if state == "capturing" then
					-- each additional squadmate inside speeds the capture, diminishing: 1x/1.5x/1.75x/2x cap
					zone.progress += zone.rate * dt * math.min(2, 1 + 0.5 * (playersIn - 1) + 0.25 * math.max(0, playersIn - 2))
				elseif state == "empty" then
					zone.progress = math.max(0, zone.progress - zone.decay * dt)
				end
			end
			zone.playersIn = playersIn
			zone.enemiesIn = enemiesIn
			publish(zone)
			if zone.progress >= 1 and not zone.done then
				zone.done = true
				workspace:SetAttribute("GF_ZoneProgress", 100)
				local cb = zone.onComplete
				destroyVisuals(zone)
				active[id] = nil
				if cb then
					cb(zone)
				end
			end
		end
	end
end

function ZoneControlService.pause(id: string, paused: boolean)
	local zone = active[id]
	if zone then
		zone.paused = paused
		publish(zone)
	end
end

function ZoneControlService.get(id: string)
	return active[id]
end

function ZoneControlService.destroy(id: string)
	local zone = active[id]
	if zone then
		active[id] = nil
		zone.done = true
		destroyVisuals(zone)
	end
	local r = remote("ZoneState")
	if r then
		r:FireAllClients({ id = id, active = false })
	end
end

function ZoneControlService.destroyAll()
	for id in active do
		ZoneControlService.destroy(id)
	end
end

return ZoneControlService
