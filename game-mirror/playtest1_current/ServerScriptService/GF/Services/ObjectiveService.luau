--!nonstrict
-- Objective: template-driven. Before this, the service hard-coded the Ascendancy relay, so two of
-- the three configured mission templates (RECOVER_TECH, DEFEND_BEACON) had no objective object,
-- no interaction and no completion condition at all -- they could not be played.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ArtService = require(script.Parent.ArtService)
local OutpostService = require(script.Parent.OutpostService)
local TweenService = game:GetService("TweenService")
local State = require(script.Parent.State)
local EnemyService = require(script.Parent.EnemyService)
local BastionWalker = require(script.Parent.Parent.BastionWalker)
local Veyr = require(script.Parent.Parent.Veyr)
local MissionSites = require(script.Parent.MissionSites)
local Missions = require(ReplicatedStorage.GF.Shared.Configs.Missions)
local Constants = require(ReplicatedStorage.GF.Shared.Constants)

local ObjectiveService = {}
local SABOTAGE_HOLD = 2.5
local DEFEND_ACTIVATE = 2.5
local DEFEND_TIME = 60
local INTERACT_RANGE = 9 -- spec: interact instant on valid range <=9 studs

-- Template tuning is data-driven through Missions.luau (`objective` subtable). Every key is
-- optional; these accessors supply the family defaults so a template that declares nothing
-- still plays exactly the mechanics, just with stock numbers.
local function ocfg(): any
	local def = Missions.get(templateId)
	return (def and def.objective) or {}
end
local function cfgNum(key: string, fallback: number): number
	local v = ocfg()[key]
	return type(v) == "number" and v or fallback
end
local function cfgList(key: string): { any }
	local v = ocfg()[key]
	return type(v) == "table" and v or {}
end

local objective: Model? = nil
local templateId = "SABOTAGE_RELAY"
local progress = 0
local complete = false
local holding = {}
-- Forward declarations. Lua resolves names lexically at the reference site, so the mechanic
-- closures below (case system, wave scheduler, family handlers) would bind these as globals
-- without an early local in scope: hint/publish are defined after currentMarker, and the zone
-- service loads defensively because test harnesses may not carry it.
local hint = ""
local publish
local ZoneControlService = nil
do
	local ok, z = pcall(function()
		return require(script.Parent.ZoneControlService)
	end)
	if ok then
		ZoneControlService = z
	end
end
local HackingService = require(script.Parent.HackingService)

-- ============ carry system ============
-- The mission object is a physical thing the squad hauls: it is welded to the carrier (who is
-- slowed below sprint and cannot pretend otherwise), it drops where the carrier falls, any
-- squadmate can recover the drop, and it only scores at its destination. This is the difference
-- between "escort the object" pressure and a timer with extra steps.
--
-- cases[caseId] = {
--   id, label, state = "site"|"carried"|"dropped"|"delivered", part (world pickup part),
--   carrier, destType = "lz"|"point", destPos, destRadius, color, prompt,
--   lastPos (carrier's last healthy footing — the drop spot when they go down or vanish),
--   onPickup, onDeliver (per-template hooks, fire exactly once per event)
-- }
local cases: { [string]: any } = {}
local carrying: { [Player]: string } = {}
local carryModels: { [Player]: Model } = {}
local deliveryRing: Part? = nil
local blackboxHackRunning = false

local function missionEvent(text: string, kind: string?)
	local ev = ReplicatedStorage.GF.Remotes:FindFirstChild("MissionEvent")
	if ev then
		ev:FireAllClients({ text = text, kind = kind or "objective" })
	end
end

local function voss(text: string, kind: string?)
	pcall(function()
		require(script.Parent.DialogueService).say(text, kind or "objective")
	end)
end

local function carryCap(): number
	return cfgNum("carrySpeed", 15)
end

-- Re-resolve the stance speed the movement layer would have chosen. applyStance is private to
-- MovementService, so releasing a carry re-derives the same truth from the same attributes
-- (downed / aiming / sprinting); the next genuine stance change re-asserts it exactly anyway.
local function restoreSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local st = State.get(player)
	if st and st.downed then
		humanoid.WalkSpeed = Constants.Movement.DownedSpeed
	elseif character and character:GetAttribute("Aiming") == true then
		humanoid.WalkSpeed = Constants.Movement.AdsSpeed
	elseif character and character:GetAttribute("Sprinting") == true then
		humanoid.WalkSpeed = Constants.Movement.SprintSpeed
	else
		humanoid.WalkSpeed = Constants.Movement.WalkSpeed
	end
end

-- The world pickup part: what players see, walk up to and grab. Re-created every time the case
-- hits the ground (site or drop), destroyed while carried so the interact scan cannot offer a
-- ghost pickup at the wreck while the case is physically on a squadmate's back.
local function caseSpawnWorldPart(record)
	if record.part and record.part.Parent then
		record.part:Destroy()
	end
	local part = Instance.new("Part")
	part.Name = "MissionCase_" .. record.id
	part.Size = Vector3.new(1.9, 1.3, 1.3)
	part.Color = record.color
	part.Material = Enum.Material.Metal
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CFrame = CFrame.new(record.homePos) * CFrame.Angles(0, math.rad((record.seed or 0) * 137), 0)
	part:SetAttribute("GFInteract", "MissionCase")
	part:SetAttribute("InteractPrompt", record.prompt)
	local stripe = Instance.new("Part")
	stripe.Name = "Lid"
	stripe.Size = Vector3.new(1.7, 0.22, 1.1)
	stripe.Color = Color3.fromRGB(120, 210, 255)
	stripe.Material = Enum.Material.Neon
	stripe.CanCollide = false
	stripe.CanQuery = false
	stripe.Anchored = true
	stripe.CFrame = part.CFrame * CFrame.new(0, 0.72, 0)
	stripe.Parent = part
	local glow = Instance.new("PointLight")
	glow.Color = record.color
	glow.Brightness = 1.1
	glow.Range = 14
	glow.Shadows = false
	glow.Parent = part
	part.Parent = workspace
	record.part = part
	return part
end

-- Register a carry object. homePos is where it first sits; destType "lz" scores at the landing
-- zone ring, destType "point" scores at destPos within destRadius.
local function caseRegister(id: string, homePos: Vector3, opts: any)
	local record = {
		id = id,
		label = (opts and opts.label) or "case",
		state = "site",
		homePos = homePos,
		color = (opts and opts.color) or Color3.fromRGB(255, 176, 64),
		prompt = (opts and opts.prompt) or ocfg().carryPrompt or "Take the case",
		destType = (opts and opts.destType) or "lz",
		destPos = opts and opts.destPos,
		destRadius = (opts and opts.destRadius) or ((opts and opts.destType) == "point" and 10 or 18),
		seed = math.random(0, 359),
		lastPos = homePos,
		part = nil,
		carrier = nil,
		onPickup = opts and opts.onPickup,
		onDeliver = opts and opts.onDeliver,
	}
	cases[id] = record
	if opts and opts.part then
		-- adopt a baked world part (convoy crates, archive canisters): the prop itself becomes the
		-- pickup. Pickup destroys it like any case part; a later drop respawns the standard shell.
		record.part = opts.part
		opts.part:SetAttribute("GFInteract", "MissionCase")
		opts.part:SetAttribute("InteractPrompt", record.prompt)
	elseif opts and opts.hidden then
		-- the case exists in state but not yet in the world; caseReveal spawns the physical part
		record.state = "sealed"
	else
		caseSpawnWorldPart(record)
	end
	return record
end

-- Reveal a sealed case into the world (the decrypt/open beat that precedes the carry).
local function caseReveal(id: string)
	local record = cases[id]
	if record and record.state == "sealed" then
		record.state = "site"
		caseSpawnWorldPart(record)
	end
end

-- The carried case and the delivery patch are what make a fetch-and-carry readable. Without them the only
-- feedback was one line of text, which is not a mechanic a player can perceive.
local function attachCase(player: Player, record)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or carryModels[player] then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "CarriedCase"
	local case = Instance.new("Part")
	case.Name = "Case"
	case.Size = Vector3.new(1.6, 1.1, 0.7)
	case.Color = record.color
	case.Material = Enum.Material.Metal
	case.CanCollide = false
	case.CanQuery = false
	case.Massless = true
	case.CFrame = root.CFrame * CFrame.new(0, -0.2, 1.1)
	case.Parent = model
	local stripe = Instance.new("Part")
	stripe.Name = "Lid"
	stripe.Size = Vector3.new(1.45, 0.18, 0.55)
	stripe.Color = Color3.fromRGB(120, 210, 255)
	stripe.Material = Enum.Material.Neon
	stripe.CanCollide = false
	stripe.CanQuery = false
	stripe.Massless = true
	stripe.CFrame = case.CFrame * CFrame.new(0, 0.62, 0)
	stripe.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = case
	weld.Part1 = stripe
	weld.Parent = stripe
	local weldRoot = Instance.new("WeldConstraint")
	weldRoot.Part0 = root
	weldRoot.Part1 = case
	weldRoot.Parent = case
	model.PrimaryPart = case
	model.Parent = character
	carryModels[player] = model
	return true
end

local function dropCaseVisual(player: Player)
	local model = carryModels[player]
	if model then
		model:Destroy()
		carryModels[player] = nil
	end
end

-- Pick up a case off the ground. Instant: the carry itself is the cost, so the grab stays snappy.
local function casePickup(player: Player, record): boolean
	if not record or record.carrier or (record.state ~= "site" and record.state ~= "dropped") then
		return false
	end
	if carrying[player] then
		return false -- one object per pair of hands
	end
	if not attachCase(player, record) then
		return false
	end
	if record.part then
		record.part:Destroy()
		record.part = nil
	end
	record.state = "carried"
	record.carrier = player
	carrying[player] = record.id
	if record.onPickup then
		task.spawn(record.onPickup, player, record)
	end
	return true
end

-- Drop the case where the carrier last had healthy footing. The drop is a physical object again:
-- same pickup contract, same light, recoverable by anyone including the player who lost it.
local function caseDrop(player: Player)
	local caseId = carrying[player]
	if not caseId then
		return
	end
	carrying[player] = nil
	dropCaseVisual(player)
	restoreSpeed(player)
	local record = cases[caseId]
	if not record then
		return
	end
	record.carrier = nil
	record.state = "dropped"
	record.homePos = record.lastPos
	caseSpawnWorldPart(record)
end

-- Deliver at the destination. Visuals die; the per-template hook decides what the objective does.
local function caseDeliver(record)
	if record.state == "delivered" then
		return
	end
	local player = record.carrier
	if player then
		carrying[player] = nil
		dropCaseVisual(player)
		restoreSpeed(player)
	end
	record.carrier = nil
	record.state = "delivered"
	if record.part then
		record.part:Destroy()
		record.part = nil
	end
	if record.onDeliver then
		task.spawn(record.onDeliver, player, record)
	end
end

-- Recovery interact: nearest live case part in range wins, same discrimination pattern as the
-- relay shield nodes — the squad never thinks about which object the prompt means.
local function caseRequest(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local best, bestDist = nil, INTERACT_RANGE + 2
	for _, record in pairs(cases) do
		if (record.state == "site" or record.state == "dropped") and record.part then
			local d = (root.Position - record.part.Position).Magnitude
			if d <= bestDist then
				best = record
				bestDist = d
			end
		end
	end
	if best then
		if casePickup(player, best) then
			hint = string.format("%s secured — haul it to the %s", best.label, best.destType == "lz" and "landing zone" or "sled")
			publish()
		end
	end
end

local function showDeliveryRing()
	if deliveryRing and deliveryRing.Parent then
		return
	end
	local lz = workspace:GetAttribute("GF_LZ")
	if typeof(lz) ~= "Vector3" then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = "DeliveryPatch"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 36, 36)
	ring.CFrame = CFrame.new(lz + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(120, 210, 255)
	ring.Transparency = 0.75
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Parent = workspace
	deliveryRing = ring
end

-- ============ assault telegraphing ============
-- A wave you cannot read is noise; a wave you can read is a fight. Every scripted assault is
-- announced by compass direction, marked with a flare column at the massing point, and given a
-- few seconds of warning before the hostiles actually materialize — the squad can choose to
-- reposition, not just react.
local function compassOf(dx: number, dz: number): string
	local angle = math.atan2(dx, -dz)
	local names = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }
	local idx = math.floor((angle + math.pi / 8) / (math.pi / 4)) % 8
	return names[idx + 1]
end

local function flareAt(position: Vector3, seconds: number?)
	local flare = Instance.new("Part")
	flare.Name = "AssaultFlare"
	flare.Shape = Enum.PartType.Cylinder
	flare.Size = Vector3.new(42, 2.6, 2.6)
	flare.CFrame = CFrame.new(position + Vector3.new(0, 21, 0)) * CFrame.Angles(0, 0, math.rad(90))
	flare.Material = Enum.Material.Neon
	flare.Color = Color3.fromRGB(255, 96, 84)
	flare.Transparency = 0.25
	flare.Anchored = true
	flare.CanCollide = false
	flare.CanQuery = false
	flare.CastShadow = false
	flare.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 96, 84)
	light.Brightness = 2
	light.Range = 30
	light.Shadows = false
	light.Parent = flare
	local life = seconds or 7
	TweenService:Create(flare, TweenInfo.new(life), { Transparency = 1 }):Play()
	task.delay(life + 0.2, function()
		if flare.Parent then
			flare:Destroy()
		end
	end)
	return flare
end

-- Telegraph-then-spawn: direction first, flare second, hostiles last. `close` waves mass inside
-- the perimeter lip instead of out on the approach — the "they're already here" beat.
local function telegraphWave(center: Vector3, count: number, close: boolean?)
	task.spawn(function()
		local bearing = math.random() * math.pi * 2
		local dir = Vector3.new(math.cos(bearing), 0, math.sin(bearing))
		local dist = close and 30 or 58
		local spawnPos = center + dir * dist
		local compass = compassOf(dir.X, dir.Z)
		flareAt(spawnPos, 7)
		if close then
			voss("Contacts inside the perimeter — close defense, now!", "warning")
			missionEvent("Hostiles inside the perimeter!", "warning")
		else
			voss(string.format("Contacts massing %s of your position. Stand by.", compass), "warning")
			missionEvent(string.format("Hostiles massing %s — assault inbound", compass), "warning")
		end
		workspace:SetAttribute("GF_WaveTelegraph", string.format("%s:%d:%d", compass, count, math.floor(os.clock())))
		task.wait(4.5)
		if complete then
			return
		end
		local ok, EncounterDirector = pcall(function()
			return require(script.Parent.EncounterDirector)
		end)
		if ok and EncounterDirector and EncounterDirector.spawnAround then
			EncounterDirector.spawnAround(spawnPos, close and 10 or 14, count)
		end
	end)
end

-- Scripted reaction squad: spawned from the template's responseRoster after a telegraphed delay.
-- Unlike director waves these are exact compositions — the pursuit squad, the hunter team, the
-- depot reaction force — because their size IS the tuning.
local function spawnResponseSquad(center: Vector3, label: string)
	local roster = cfgList("responseRoster")
	if #roster == 0 then
		return {}
	end
	local spawned = {}
	for index, enemyId in ipairs(roster) do
		local angle = (index / #roster) * math.pi * 2
		local pos = center + Vector3.new(math.cos(angle) * 10, 0, math.sin(angle) * 10)
		local model = EnemyService.spawn(enemyId, pos)
		if model then
			table.insert(spawned, model)
		end
	end
	if #spawned > 0 then
		voss(label, "warning")
	end
	return spawned
end

-- Wave escalation scheduler: hold stages arm a plan keyed to live zone progress; each trigger
-- fires exactly once. The plan dies when the zone completes or the stage ends.
local waveWatch: any = { zoneId = nil, center = nil, waves = nil }

local function armWaves(zoneId: string, center: Vector3)
	local defs = cfgList("waves")
	if #defs == 0 or not ZoneControlService then
		waveWatch.zoneId = nil
		waveWatch.waves = nil
		return
	end
	local plan = {}
	for _, w in ipairs(defs) do
		if type(w) == "table" and type(w.at) == "number" and type(w.count) == "number" then
			table.insert(plan, { at = w.at, count = w.count, close = w.close == true, fired = false })
		end
	end
	table.sort(plan, function(a, b)
		return a.at < b.at
	end)
	waveWatch.zoneId = zoneId
	waveWatch.center = center
	waveWatch.waves = plan
end

local function disarmWaves()
	waveWatch.zoneId = nil
	waveWatch.waves = nil
end

task.spawn(function()
	while true do
		task.wait(0.75)
		if waveWatch.zoneId and waveWatch.waves and not complete and ZoneControlService then
			local zone = ZoneControlService.get(waveWatch.zoneId)
			if zone then
				for _, w in ipairs(waveWatch.waves) do
					if not w.fired and zone.progress >= w.at then
						w.fired = true
						telegraphWave(waveWatch.center or zone.center, w.count, w.close)
					end
				end
			else
				disarmWaves()
			end
		end
	end
end)

-- Alarm consequences: a missed hack press trips intrusion detection and the garrison responds.
-- Capped per site key so a struggling player is pressured, not buried.
local alarmTrips: { [string]: number } = {}
local function tripAlarm(key: string, position: Vector3, count: number, cap: number?)
	alarmTrips[key] = (alarmTrips[key] or 0)
	if alarmTrips[key] >= (cap or 2) then
		return false
	end
	alarmTrips[key] += 1
	task.defer(function()
		local ok, EncounterDirector = pcall(function()
			return require(script.Parent.EncounterDirector)
		end)
		if ok and EncounterDirector and EncounterDirector.spawnAround then
			EncounterDirector.spawnAround(position, 20, count)
		end
	end)
	missionEvent("Alarm tripped — defenders converging!", "warning")
	return true
end
local defending = false
-- Sabotage breach state: the relay is shielded by three field nodes that must be hacked
-- (ring challenge per node, alarms on misses) before the core terminal accepts the charge.
local shieldNodes: { any } = {}
local nodesBreached = 0
local beaconZoneDone = false
local beaconResyncPending = false
local beaconResynced = false
local defendEndsAt = 0

local function remote(name) return ReplicatedStorage.GF.Remotes:FindFirstChild(name) end

-- Marker source. Elimination points at the nearest living REVEALED target (it changes as they
-- die and as identities confirm); while the hunt is still blind the marker stays on the sweep
-- area. During a carry the marker tracks the object — the case is the objective now. Everything
-- else points at the objective site. Clients decide whether that reads as approximate or exact
-- from their own distance.
-- Declared here because currentMarker (defined above the family builders) needs the same table.
local elimTargets: { [Model]: any } = {}

local function currentMarker(): (Vector3?, string)
	-- a carried or dropped mission object outranks everything: while carried the squad needs the
	-- destination, and once the object is on the ground recovering it IS the current play
	for _, record in pairs(cases) do
		if record.state == "carried" and record.carrier then
			if record.destType == "point" and typeof(record.destPos) == "Vector3" then
				return record.destPos, "DELIVER"
			end
			local lz = workspace:GetAttribute("GF_LZ")
			if typeof(lz) == "Vector3" then
				return lz, "DELIVER"
			end
		elseif record.state == "dropped" and record.part and record.part.Parent then
			return record.part.Position, "CASE"
		end
	end
	if templateId == "ELIM_COMMANDER" or templateId == "ELIM_WALKER" or templateId == "ELIM_TALON" then
		for model, record in pairs(elimTargets) do
			if type(record) == "table" and record.revealed and model.Parent and model:GetAttribute("Dead") ~= true then
				local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
				if part then
					return part.Position, "TARGET"
				end
			end
		end
		-- hunt still blind: the marker stays on the sweep area, labelled honestly
		local part = objective and objective.PrimaryPart
		if part then
			return part.Position, "SWEEP"
		end
	end
	local part = objective and objective.PrimaryPart
	if part then
		return part.Position, "OBJECTIVE"
	end
	return nil, ""
end

publish = function()
	local r = remote("ObjectiveProgress")
	if r then
		local spot, label = currentMarker()
		r:FireAllClients({
			progress = progress,
			complete = complete,
			template = templateId,
			hint = hint,
			marker = complete and nil or (spot and { position = spot, label = label } or nil),
		})
	end
end

local function partOf(model, size, offset, color, material, position)
	local p = Instance.new("Part")
	p.Size = size; p.Position = position + offset
	p.Color = color; p.Material = material; p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function ground(position)
	local TerrainService = require(script.Parent.TerrainService)
	return Vector3.new(position.X, TerrainService.groundSurface(position.X, position.Z) + 0.4, position.Z)
end

local function buildRelay(position)
	local model = Instance.new("Model")
	model.Name = "AscendancyRelay"
	model:SetAttribute("GFObjective", "Relay")
	local base = partOf(model, Vector3.new(16, 2, 16), Vector3.new(0, 1, 0), Color3.fromRGB(38, 38, 44), Enum.Material.Slate, position)
	base.Transparency = 1
	local plinth = partOf(model, Vector3.new(15, 1.4, 15), Vector3.new(0, 0.7, 0), Color3.fromRGB(44, 43, 50), Enum.Material.Slate, position)
	plinth.Name = "Plinth"
	-- Authored kit relay first: split-shaft obsidian tower with bronze inlay and violet seams.
	-- Kit pieces keep their baked palette (never reskin); legacy art keeps the old tint path;
	-- box columns remain the last-resort silhouette.
	workspace:SetAttribute("GF_RelayKitPlaced", false)
	local kitTower = ArtService.placeKit("Kit_Ascendancy_Relay", position + Vector3.new(0, 0.9, 0), {
		height = 30,
		parent = model,
		collide = true,
	})
	if kitTower then
		kitTower.Name = "RelayTower"
		workspace:SetAttribute("GF_RelayKitPlaced", true)
	else
		local tower = ArtService.place("AscendancyRelay", position + Vector3.new(0, 0.9, 0), { height = 30 })
		if tower then
			tower.Name = "RelayTower"
			tower.Parent = model
			ArtService.reskin(tower, Color3.fromRGB(58, 54, 70), Enum.Material.Metal)
			for _, d in tower:GetDescendants() do if d:IsA("BasePart") then d.CanCollide = true end end
		else
			partOf(model, Vector3.new(4, 18, 4), Vector3.new(0, 10, 0), Color3.fromRGB(52, 50, 58), Enum.Material.Metal, position)
			partOf(model, Vector3.new(2.5, 8, 2.5), Vector3.new(0, 22, 0), Color3.fromRGB(60, 56, 66), Enum.Material.Metal, position)
		end
	end
	local core = partOf(model, Vector3.new(2.2, 2.2, 2.2), Vector3.new(0, 16, 0), Color3.fromRGB(96, 214, 232), Enum.Material.Neon, position)
	core.Name = "CoreGlow"
	local light = Instance.new("PointLight")
	light.Shadows = false; light.Color = Color3.fromRGB(96, 214, 232); light.Brightness = 1.5; light.Range = 26
	light.Parent = core
	local deck = partOf(model, Vector3.new(7, 0.6, 5), Vector3.new(0, 0.3, 11), Color3.fromRGB(62, 62, 72), Enum.Material.DiamondPlate, position)
	deck.Name = "ConsoleDeck"
	local terminal = partOf(model, Vector3.new(2.6, 3.0, 1.4), Vector3.new(0, 2.1, 11), Color3.fromRGB(34, 38, 48), Enum.Material.Metal, position)
	local screen = partOf(model, Vector3.new(2.0, 1.4, 0.12), Vector3.new(0, 2.9, 10.25), Color3.fromRGB(90, 220, 255), Enum.Material.Neon, position)
	screen.Name = "TerminalScreen"; screen.CanCollide = false
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "Relay")
	terminal:SetAttribute("InteractPrompt", "Sabotage Relay")
	-- Dressing pass: the compound read as a bare slab of grey. Deck seams, hazard chevrons and a lit perimeter
	-- give the objective an edge and a scale reference without adding lights (which are the expensive thing).
	local hazard = Color3.fromRGB(198, 158, 44)
	local plate = Color3.fromRGB(78, 84, 96)
	for i = -3, 3 do
		local seam = partOf(model, Vector3.new(0.35, 0.12, 26), Vector3.new(i * 3.4, 0.62, 6), plate, Enum.Material.Metal, position)
		seam.Name = "DeckSeam"
		seam.CanCollide = false
	end
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + math.pi / 4
		local chevron = partOf(model, Vector3.new(4.2, 0.14, 1.1), Vector3.new(math.cos(a) * 9, 0.62, math.sin(a) * 9 + 6), hazard, Enum.Material.SmoothPlastic, position)
		chevron.Name = "HazardChevron"
		chevron.CanCollide = false
		chevron.CFrame = chevron.CFrame * CFrame.Angles(0, -a, 0)
	end
	for i = 1, 4 do
		local edge = (i % 2 == 0) and 1 or -1
		local strip = partOf(model, Vector3.new(0.3, 0.2, 26), Vector3.new(edge * 11.5, 0.66, 6), Color3.fromRGB(96, 214, 232), Enum.Material.Neon, position)
		strip.Name = "PerimeterStrip"
		strip.CanCollide = false
	end
	for i = 1, 2 do
		local stanchion = partOf(model, Vector3.new(0.5, 4.2, 0.5), Vector3.new(i == 1 and -6 or 6, 2.1, 15), plate, Enum.Material.Metal, position)
		stanchion.Name = "Stanchion"
		local lamp = partOf(model, Vector3.new(0.7, 0.3, 0.7), Vector3.new(stanchion.Position.X, 4.3, 15), Color3.fromRGB(255, 214, 140), Enum.Material.Neon, position)
		lamp.Name = "StanchionLamp"
		lamp.CanCollide = false
	end
	-- Breach shield nodes: three field pylons in a triangle around the relay. Each is a
	-- hacking target (ring challenge); all three must fall before the core terminal accepts
	-- the demolition charge. Authored kit beacon when installed, part console otherwise.
	shieldNodes = {}
	nodesBreached = 0
	for i = 1, 3 do
		local a = math.rad(30 + i * 120)
		local nx = position.X + math.cos(a) * 17
		local nz = position.Z + math.sin(a) * 17
		local nodePos = Vector3.new(nx, position.Y, nz)
		local node = Instance.new("Model")
		node.Name = "ShieldNode" .. i
		local console = nil
		if ArtService.exists("Kit_Ascendancy_Beacon") then
			console = ArtService.placeKit("Kit_Ascendancy_Beacon", nodePos, { height = 7, yaw = -a, parent = node, collide = true })
		end
		if not console then
			partOf(node, Vector3.new(2.2, 1.2, 2.2), Vector3.new(0, 0.6, 0), Color3.fromRGB(44, 46, 56), Enum.Material.Metal, nodePos)
			partOf(node, Vector3.new(1.2, 3.6, 1.2), Vector3.new(0, 2.6, 0), Color3.fromRGB(52, 56, 68), Enum.Material.Metal, nodePos)
		end
		-- the interactable face plate: players target this, not the sculpture
		local plate = partOf(node, Vector3.new(1.6, 2.2, 0.6), Vector3.new(0, 1.6, 1.4), Color3.fromRGB(34, 38, 48), Enum.Material.Metal, nodePos)
		plate.Name = "Terminal"
		plate:SetAttribute("GFInteract", "ShieldNode")
		plate:SetAttribute("InteractPrompt", "Breach shield node")
		local core = partOf(node, Vector3.new(1.1, 1.1, 1.1), Vector3.new(0, 4.6, 0), Color3.fromRGB(169, 99, 233), Enum.Material.Neon, nodePos)
		core.Name = "NodeCore"
		core.CanCollide = false
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(169, 99, 233); glow.Brightness = 1.2; glow.Range = 16; glow.Shadows = false
		glow.Parent = core
		node.Parent = model
		shieldNodes[i] = { model = node, core = core, glow = glow, plate = plate, breached = false, busy = nil, alarms = 0, position = nodePos }
	end
	model.PrimaryPart = base
	model.Parent = ArtService.actorsFolder()
	workspace:SetAttribute("GF_RelayDressing", #model:GetChildren())
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

local function buildBlackBox(position)
	local model = Instance.new("Model")
	model.Name = "ScientificTransport"
	model:SetAttribute("GFObjective", "BlackBox")
	-- the downed transport: fuselage, wing, scorch, and the black box on the ground beside it
	local hull = partOf(model, Vector3.new(22, 7, 9), Vector3.new(0, 3.5, 0), Color3.fromRGB(72, 76, 86), Enum.Material.Metal, position)
	hull.Name = "Fuselage"
	hull.CFrame = CFrame.new(position + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, math.rad(18), math.rad(-7))
	local wing = partOf(model, Vector3.new(16, 0.8, 5), Vector3.new(-3, 4.2, 0), Color3.fromRGB(64, 68, 78), Enum.Material.Metal, position)
	wing.CFrame = CFrame.new(position + Vector3.new(-3, 4.2, 0)) * CFrame.Angles(0, math.rad(18), math.rad(14))
	local crate = partOf(model, Vector3.new(4.2, 3.2, 3.4), Vector3.new(8, 1.9, 3), Color3.fromRGB(28, 30, 36), Enum.Material.Metal, position)
	crate.Name = "BlackBox"
	local lid = partOf(model, Vector3.new(4.0, 0.3, 3.2), Vector3.new(8, 3.6, 3), Color3.fromRGB(232, 168, 64), Enum.Material.Neon, position)
	lid.Name = "Lid"
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(232, 168, 64); glow.Brightness = 1.1; glow.Range = 18; glow.Shadows = false
	glow.Parent = lid
	local terminal = partOf(model, Vector3.new(1.8, 2.2, 1.0), Vector3.new(8, 1.1, 5.4), Color3.fromRGB(34, 38, 48), Enum.Material.Metal, position)
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "BlackBox")
	terminal:SetAttribute("InteractPrompt", "Extract Black Box")
	-- the flight recorder starts sealed inside the encryption: the ring hack cracks it, and only then
	-- does the case physically exist to be grabbed. Delivered at the landing zone, it completes the op.
	blackboxHackRunning = false
	caseRegister("blackboxcase", crate.Position, {
		label = "Flight recorder",
		prompt = ocfg().carryPrompt or "Take the flight recorder",
		color = Color3.fromRGB(232, 168, 64),
		destType = "lz",
		hidden = true,
		onPickup = function()
			showDeliveryRing()
			progress = 0.5
			hint = "Carry the flight recorder to the landing zone"
			publish()
			missionEvent("Flight recorder secured. Get it to the landing zone.", "objective")
		end,
		onDeliver = function()
			if deliveryRing then
				deliveryRing:Destroy()
				deliveryRing = nil
			end
			ObjectiveService.complete()
		end,
	})
	model.PrimaryPart = crate
	model.Parent = ArtService.actorsFolder()
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

local function buildBeacon(position)
	local model = Instance.new("Model")
	model.Name = "CommBeacon"
	model:SetAttribute("GFObjective", "Beacon")
	local base = partOf(model, Vector3.new(12, 1.2, 12), Vector3.new(0, 0.6, 0), Color3.fromRGB(40, 44, 52), Enum.Material.Slate, position)
	base.Name = "BeaconBase"
	local mast = partOf(model, Vector3.new(2, 16, 2), Vector3.new(0, 8.6, 0), Color3.fromRGB(58, 62, 72), Enum.Material.Metal, position)
	mast.Name = "Mast"
	local dish = partOf(model, Vector3.new(6, 0.6, 6), Vector3.new(0, 17, 0), Color3.fromRGB(70, 76, 88), Enum.Material.Metal, position)
	dish.CFrame = CFrame.new(position + Vector3.new(0, 17, 0)) * CFrame.Angles(math.rad(-28), 0, 0)
	local lamp = partOf(model, Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 18.6, 0), Color3.fromRGB(96, 214, 232), Enum.Material.Neon, position)
	lamp.Name = "BeaconLamp"
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(96, 214, 232); light.Brightness = 0.2; light.Range = 24; light.Shadows = false
	light.Parent = lamp
	local terminal = partOf(model, Vector3.new(2.4, 2.6, 1.4), Vector3.new(0, 1.8, 7), Color3.fromRGB(34, 38, 48), Enum.Material.Metal, position)
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "Beacon")
	terminal:SetAttribute("InteractPrompt", "Activate Beacon")
	model.PrimaryPart = base
	model.Parent = ArtService.actorsFolder()
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

-- Elimination family — hunt structure. Three variants that all end in a body rather than a hold,
-- but the body has to be FOUND first: priority targets deploy unidentified (the HUD marks the
-- sweep area, not the target) until the squad either closes to proximity-scan range or slices
-- the battle-net intel post at the site. Escorts fight for their target but are never required
-- kills, and the window after first contact is what the clean-hunt commendation measures. Only
-- tagged models count, so patrols from the EncounterDirector cannot stall or fake completion.
elimTargets = {}
local elimTotal = 0
local elimKilled = 0
local elimRunning = false
local elimRunId = 0
local elimLabel = "Hostiles"
local elimHuntStartedAt = 0
local elimIntelUsed = false
local elimIntelConsole: BasePart? = nil

local function elimReveal(model: Model, reason: string)
	local record = elimTargets[model]
	if type(record) ~= "table" or record.revealed then
		return
	end
	record.revealed = true
	model:SetAttribute("GF_ElimRevealed", true)
	if elimHuntStartedAt == 0 then
		elimHuntStartedAt = os.clock()
	end
	-- armor matrix strip: the scan is what makes the walker fight fair. Damage already dealt into
	-- the matrix is not refunded — the strip removes up to `matrix` of what remains.
	local matrix = cfgNum("matrix", 0)
	if matrix > 0 then
		local current = tonumber(model:GetAttribute("Shield")) or 0
		model:SetAttribute("Shield", math.max(0, current - matrix))
		voss(string.format("%s — armor matrix down. Weapons free.", record.label), "objective")
		missionEvent("Armor matrix collapsed — target vulnerable", "objective")
	else
		voss(string.format("Target identity confirmed: %s. Weapons free.", record.label), "objective")
		missionEvent(string.format("Target confirmed — %s", record.label), "objective")
	end
	workspace:SetAttribute("GF_ElimRevealedCount", (workspace:GetAttribute("GF_ElimRevealedCount") or 0) + 1)
end

local function elimRevealAll(reason: string)
	for model in pairs(elimTargets) do
		if model.Parent and model:GetAttribute("Dead") ~= true then
			elimReveal(model, reason)
		end
	end
end

local function elimAdd(model: Model?, label: string)
	if not model then
		return nil
	end
	-- GF_ObjectiveTarget protects the model from mission-reset boss sweeps; it is NOT the reveal.
	-- Reveal state lives in the record and the GF_ElimRevealed attribute.
	model:SetAttribute("GF_ObjectiveTarget", true)
	elimTargets[model] = { revealed = false, scan = 0, label = label }
	elimTotal += 1
	return model
end

-- Hardcoded fallback rosters mirror the pre-config missions exactly, so a template whose config
-- block was stripped still plays the same hunt.
local function elimRoster(): ({ string }, { string })
	local targets = cfgList("targets")
	local escorts = cfgList("escorts")
	if #targets > 0 then
		return targets, escorts
	end
	if templateId == "ELIM_COMMANDER" then
		return { "Officer" }, { "Rifleman", "Rifleman" }
	elseif templateId == "ELIM_WALKER" then
		return { "BastionWalker" }, { "Rifleman", "Heavy" }
	end
	return { "Marksman", "Heavy", "Officer" }, {}
end

local function elimLabelFor(enemyId: string, index: number): string
	if enemyId == "BastionWalker" then
		return "the Bastion Walker"
	elseif templateId == "ELIM_COMMANDER" then
		return "the Ascendancy commander"
	elseif templateId == "ELIM_TALON" then
		return string.format("Talon operative %d", index)
	end
	return enemyId
end

local function elimSpawnOne(enemyId: string, position: Vector3): Model?
	if enemyId == "BastionWalker" then
		return BastionWalker.spawn(position)
	end
	return EnemyService.spawn(enemyId, position)
end

local function elimTick()
	if elimRunning then
		return
	end
	elimRunning = true
	local runId = elimRunId
	task.spawn(function()
		while not complete do
			if runId ~= elimRunId then
				break
			end
			if not objective or not objective.Parent then
				break
			end
			-- proximity scan: continuous exposure inside scanRange confirms identity. Progress
			-- bleeds at half rate when the squad backs off — commitment is rewarded, tag-ins
			-- are not free.
			local scanRange = cfgNum("scanRange", 45)
			local scanTime = cfgNum("scanTime", 4)
			local bestScan = 0
			for model, record in pairs(elimTargets) do
				if type(record) == "table" and not record.revealed and model.Parent and model:GetAttribute("Dead") ~= true then
					local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
					local near = false
					if part then
						for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
							local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
							local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
							if root and humanoid and humanoid.Health > 0 and (root.Position - part.Position).Magnitude <= scanRange then
								near = true
								break
							end
						end
					end
					if near then
						record.scan = math.min(scanTime, record.scan + 0.5)
					else
						record.scan = math.max(0, record.scan - 0.25)
					end
					bestScan = math.max(bestScan, record.scan / math.max(0.1, scanTime))
					if record.scan >= scanTime then
						elimReveal(model, "scan")
					end
				end
			end
			local gone = {}
			for model in pairs(elimTargets) do
				if model.Parent == nil or model:GetAttribute("Dead") == true then
					table.insert(gone, model)
				end
			end
			for _, model in ipairs(gone) do
				elimTargets[model] = nil
				elimKilled += 1
				if elimHuntStartedAt == 0 then
					elimHuntStartedAt = os.clock()
				end
				pcall(function()
					require(script.Parent.CacheService).onBossKilled(model)
				end)
			end
			if elimTotal > 0 then
				progress = math.clamp(elimKilled / elimTotal, 0, 1)
				if bestScan > 0 and bestScan < 1 then
					hint = string.format("Scanning target identity — %d%%", math.floor(bestScan * 100))
				elseif elimKilled == 0 and elimHuntStartedAt == 0 then
					hint = "Sweep the outpost — identify the priority target (scan or slice the intel post)"
				else
					hint = string.format("%s %d / %d down", elimLabel, elimKilled, elimTotal)
				end
				publish()
			end
			if elimTotal > 0 and elimKilled >= elimTotal then
				-- clean-hunt commendation: everything dead inside the window measured from first
				-- contact (first reveal OR first kill). Recorded as an optional_task ledger event —
				-- settlement still belongs to RewardsService, the ledger is the audit trail.
				local window = cfgNum("cleanWindow", 120)
				if elimHuntStartedAt > 0 and (os.clock() - elimHuntStartedAt) <= window then
					local difficulty = (State.getMission() or {}).difficulty or "Normal"
					pcall(function()
						require(script.Parent.RewardLedgerService).appendEvent("optional_task", difficulty, "cleanhunt:" .. tostring(templateId))
					end)
					voss("Clean hunt. Command notes the efficiency.", "objective")
					missionEvent("Clean hunt — commendation recorded", "objective")
					workspace:SetAttribute("GF_CleanHunt", true)
				end
				ObjectiveService.complete()
				break
			end
			task.wait(0.5)
		end
		elimRunning = false
	end)
end

-- Intel slice interact: the battle-net post is the deliberate-reveal path. Hacking it confirms
-- every living target at once; a miss trips the alarm and the post stays live for another try.
local function elimIntelRequest(player: Player)
	if elimIntelUsed then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not elimIntelConsole or not elimIntelConsole.Parent then
		return
	end
	if (root.Position - elimIntelConsole.Position).Magnitude > INTERACT_RANGE then
		return
	end
	local difficulty = (State.getMission() or {}).difficulty or "Normal"
	HackingService.begin(player, difficulty, elimIntelConsole.Position, "elimintel")
	hint = "Slicing the battle-net — press in the green arc"
	publish()
end

local function elimSite(position, accent)
	local model = Instance.new("Model")
	model.Name = "EliminationSite"
	model:SetAttribute("GFObjective", "EliminationSite")
	local pad = partOf(model, Vector3.new(22, 1.2, 22), Vector3.new(0, 0.6, 0), Color3.fromRGB(38, 40, 46), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local pole = partOf(model, Vector3.new(0.7, 18, 0.7), Vector3.new(0, 9.6, 0), Color3.fromRGB(52, 56, 64), Enum.Material.Metal, position)
	pole.Name = "PennantPole"
	local flag = partOf(model, Vector3.new(4.6, 2.4, 0.2), Vector3.new(2.6, 17.4, 0), accent, Enum.Material.Neon, position)
	flag.Name = "Pennant"
	local crateA = partOf(model, Vector3.new(3, 2.2, 2.4), Vector3.new(-6, 1.9, 4), Color3.fromRGB(60, 58, 52), Enum.Material.WoodPlanks, position)
	crateA.Name = "CrateA"
	local crateB = partOf(model, Vector3.new(2.4, 1.8, 2), Vector3.new(-6.4, 1.7, 7.2), Color3.fromRGB(60, 58, 52), Enum.Material.WoodPlanks, position)
	crateB.Name = "CrateB"
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

local function buildElimination(position)
	local site = elimSite(position, Color3.fromRGB(226, 108, 72))
	elimHuntStartedAt = 0
	elimIntelUsed = false
	workspace:SetAttribute("GF_CleanHunt", false)
	workspace:SetAttribute("GF_ElimRevealedCount", 0)
	local targets, escorts = elimRoster()
	local spread = cfgNum("spread", 0)
	local matrix = cfgNum("matrix", 0)
	-- target layout: clustered honor guard when spread is zero, otherwise an even scatter around
	-- the sweep area — the multi-target variants are the ones that make the squad choose a direction
	local targetPositions = {}
	for index, enemyId in ipairs(targets) do
		local offset
		if #targets > 1 and spread > 0 then
			local angle = (index / #targets) * math.pi * 2 + math.rad(30)
			offset = Vector3.new(math.cos(angle) * spread, 0, math.sin(angle) * spread)
		else
			offset = Vector3.new((index - 1) * 6 - (#targets - 1) * 3, 0, -6)
		end
		local spawnPos = position + offset
		local model = elimSpawnOne(enemyId, spawnPos)
		local added = elimAdd(model, elimLabelFor(enemyId, index))
		if added then
			table.insert(targetPositions, spawnPos)
			if matrix > 0 then
				local base = tonumber(added:GetAttribute("Shield")) or 0
				added:SetAttribute("Shield", base + matrix)
				added:SetAttribute("MaxShield", base + matrix)
				added:SetAttribute("GF_ArmorMatrix", matrix)
			end
		end
	end
	-- escorts fight for the targets but are deliberately untagged: killing them is tactics, not
	-- objective. Round-robin across target positions so every knot of resistance has structure.
	for index, enemyId in ipairs(escorts) do
		local anchor = targetPositions[((index - 1) % math.max(1, #targetPositions)) + 1] or position
		local angle = math.random() * math.pi * 2
		EnemyService.spawn(enemyId, anchor + Vector3.new(math.cos(angle) * 7, 0, math.sin(angle) * 7))
	end
	-- the battle-net intel post: the deliberate-reveal path, tucked at the site edge where reaching
	-- it is a small infiltration problem of its own
	local intelPos = position + Vector3.new(10, 0, 12)
	local _, console = MissionSites.buildIntelPost(intelPos, {
		interact = "IntelConsole",
		prompt = "Slice battle-net terminal",
		parent = workspace:FindFirstChild("ActiveActors") or workspace,
	})
	elimIntelConsole = console
	if templateId == "ELIM_COMMANDER" then
		elimLabel = "Commander"
	elseif templateId == "ELIM_WALKER" then
		elimLabel = "Walker"
	else
		elimLabel = "Talon operatives"
	end
	if matrix > 0 then
		hint = "Sweep the area — scan the walker's armor matrix or slice the intel post"
	else
		hint = "Sweep the outpost — identify the priority target (scan or slice the intel post)"
	end
	workspace:SetAttribute("GF_ElimTargets", elimTotal)
	if elimTotal == 0 then
		warn("[GF] elimination roster empty for " .. tostring(templateId))
		hint = "Objective error: no hostile targets spawned"
	end
	publish()
	return site
end

-- Conquest family. One stage machine, three variants: clear or slice, capture, then hold.
-- The capture stage is the multi-point seize: simultaneous presence-zones spread across the
-- base, every one of which must be held to completion — a squad that stacks captures fast but
-- serially, a squad that splits captures in parallel but thin. The final hold is zone-owned
-- too: enemies inside the perimeter stall it, and the assault waves are telegraphed by
-- direction. Transitions are server-owned; interactive stages are server-authoritative hack
-- slices driven by ObjectiveService.request, so a player cannot advance by firing the remote twice.
local CONQUEST = {
	CONQUEST_DOMINION = { defend = 45, stage1 = "clear", roster = { "Rifleman", "Rifleman", "Marksman", "Rifleman" }, capturePoints = 2 },
	CONQUEST_FOUNDRY = { defend = 60, stage1 = "interact", capturePoints = 2 },
	CONQUEST_THRONEFALL = { defend = 0, stage1 = "clear", roster = { "Heavy", "Marksman", "Officer" }, boss = true, capturePoints = 1 },
}

local conqStage = 0
local conqEndsAt = 0
local conqTagged: { [Model]: boolean } = {}
local conqTotal = 0
local conqRunId = 0
local conqPointPositions: { Vector3 } = {}
local conqPointsDone = 0
local conqPointsTotal = 0
local conqHoldZoneUsed = false

local POINT_NAMES = { "Alpha", "Bravo", "Charlie" }

-- Config first, hardcoded table as the exact pre-config fallback: strip a template's objective
-- block and it plays precisely the mission it shipped with.
local function conqConfig()
	local fallback = CONQUEST[templateId] or {}
	local cfg = ocfg()
	local merged = {}
	for key, value in pairs(fallback) do
		merged[key] = value
	end
	for _, key in ipairs({ "stage1", "roster", "boss", "defend", "capturePoints" }) do
		if cfg[key] ~= nil then
			merged[key] = cfg[key]
		end
	end
	if merged.capturePoints == nil then
		merged.capturePoints = 1
	end
	return merged
end

local function conqKilled()
	local n = 0
	for model in pairs(conqTagged) do
		if model.Parent == nil or model:GetAttribute("Dead") == true then
			n += 1
		end
	end
	return n
end

local function conqTag(model: Model?)
	if not model then
		return
	end
	model:SetAttribute("GF_ObjectiveTarget", true)
	model:SetAttribute("GF_ConquestTarget", true)
	conqTagged[model] = true
	conqTotal += 1
end

local function conqCentre(): Vector3
	local part = objective and objective.PrimaryPart
	return part and part.Position or Vector3.zero
end

local function conqTerminal(label: string, interact: string)
	local terminal = objective and objective:FindFirstChild("Terminal")
	if not terminal then
		return
	end
	terminal:SetAttribute("GFInteract", interact)
	terminal:SetAttribute("InteractPrompt", label)
end

local function conqEnterStage(stage: number)
	if stage > 3 then
		-- Thronefall's command node is the last stage: capturing it completes the operation.
		ObjectiveService.complete()
		return
	end
	conqStage = stage
	local cfg = conqConfig()
	progress = 0
	if stage >= 1 and stage <= 2 then
		conqTagged = {}
		conqTotal = 0
	end
	if stage == 1 then
		if cfg.stage1 == "interact" then
			conqTerminal("Slice turret power coupling", "ConquestConsole")
			hint = "Slice the turret power coupling at the console"
		else
			conqTerminal("", "None")
			local centre = conqCentre()
			for _, enemyId in ipairs(cfg.roster or {}) do
				conqTag(EnemyService.spawn(enemyId, centre + Vector3.new(math.random(-14, 14), 0, math.random(-14, 14))))
			end
			hint = string.format("Clear the base defenders (%d)", conqTotal)
		end
	elseif stage == 2 then
		if cfg.boss then
			conqTerminal("", "None")
			local player = game:GetService("Players"):GetPlayers()[1]
			conqTag(Veyr.spawn(conqCentre() + Vector3.new(0, 0, -16), player))
			hint = "Defeat High Marshal Veyr"
		elseif ZoneControlService and #conqPointPositions > 0 then
			-- multi-point seize: every pylon zone must independently complete. Contested points
			-- freeze, empty points bleed — the squad reads the rings and decides where to be.
			conqTerminal("", "None")
			conqPointsDone = 0
			conqPointsTotal = #conqPointPositions
			for index, pointPos in ipairs(conqPointPositions) do
				local zoneId = "conq" .. index
				local pointName = POINT_NAMES[index] or ("Point " .. index)
				ZoneControlService.create(zoneId, {
					center = pointPos,
					radius = 14,
					label = "Point " .. pointName,
					rate = 1 / 28,
					decay = 1 / 70,
					onComplete = function(_zone)
						if complete or conqStage ~= 2 then
							return
						end
						conqPointsDone += 1
						workspace:SetAttribute("GF_ConquestPoints", conqPointsDone)
						if conqPointsDone >= conqPointsTotal then
							conqEnterStage(3)
						else
							hint = string.format("Point %s secured — %d of %d points", pointName, conqPointsDone, conqPointsTotal)
							missionEvent(string.format("Point %s secured", pointName), "objective")
							publish()
						end
					end,
					onStateChange = function(_zone, state)
						if conqStage ~= 2 then
							return
						end
						if state == "contested" then
							hint = string.format("Point %s contested — clear it out!", pointName)
							publish()
						end
					end,
				})
			end
			hint = string.format("Seize the capture points (0 / %d) — hold every pylon", conqPointsTotal)
			voss("Capture points marked. Split the difference or stack the points — your call.", "objective")
		else
			-- no zone service: the capture degrades to the legacy single-console interact
			conqTerminal("Capture control point", "ConquestConsole")
			hint = "Capture the control point"
		end
	elseif stage == 3 then
		if cfg.boss then
			conqTerminal("Slice command node", "ConquestNode")
			hint = "Slice the command node at the console"
		else
			conqTerminal("", "None")
			local defend = cfg.defend or 45
			if ZoneControlService then
				-- zone-owned hold: the perimeter must be HELD, not just survived. Enemies inside
				-- stall the clock, empty bleeds — and the assault waves are telegraphed inbound.
				conqHoldZoneUsed = true
				local centre = conqCentre()
				ZoneControlService.create("conqhold", {
					center = centre,
					radius = 30,
					label = "Facility perimeter",
					rate = 1 / defend,
					decay = 1 / (defend * 2),
					onComplete = function(_zone)
						if not complete then
							disarmWaves()
							ObjectiveService.complete()
						end
					end,
					onStateChange = function(_zone, state)
						if conqStage ~= 3 then
							return
						end
						if state == "contested" then
							hint = "Perimeter contested — clear it out!"
						elseif state == "capturing" then
							hint = "Holding the facility — stay inside the perimeter"
						else
							hint = "Perimeter empty — the hold is bleeding"
						end
						publish()
					end,
				})
				armWaves("conqhold", centre)
				hint = string.format("Hold the facility perimeter — %d s", defend)
			else
				conqEndsAt = os.clock() + defend
				hint = string.format("Hold the position: %d s", defend)
			end
		end
	end
	workspace:SetAttribute("GF_ConquestStage", stage)
	publish()
end

-- Interactive stages are hack slices now: the foundry power coupling and Thronefall's command
-- node both run the ring challenge. Capture stages are presence zones and never interactable.
local function conqInteractive(): boolean
	local cfg = conqConfig()
	if conqStage == 1 and cfg.stage1 == "interact" then
		return true
	end
	if conqStage == 3 and cfg.boss then
		return true
	end
	-- degraded-capture fallback only: with no zone service the control point is a console hold,
	-- so the interact must stay live or the stage cannot advance
	if conqStage == 2 and not cfg.boss and not ZoneControlService then
		return true
	end
	return false
end

-- Interact on a conquest console: starts the ring hack for the active slice stage. The generic
-- hold path must not run for these — a 2.5 s channel is not how you slice a battle network.
local function conqRequest(player: Player)
	if not conqInteractive() then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local terminal = objective and objective:FindFirstChild("Terminal")
	if not root or not terminal then
		return
	end
	if (root.Position - terminal.Position).Magnitude > INTERACT_RANGE then
		return
	end
	local difficulty = (State.getMission() or {}).difficulty or "Normal"
	HackingService.begin(player, difficulty, terminal.Position, "conqhack")
	hint = "Slicing the network — press in the green arc"
	publish()
end

local function conqTick()
	local runId = conqRunId
	task.spawn(function()
		while not complete and runId == conqRunId do
			if not objective or not objective.Parent then
				break
			end
			local cfg = conqConfig()
			if cfg then
				if conqStage == 1 and conqTotal > 0 and conqKilled() >= conqTotal then
					conqEnterStage(2)
				elseif conqStage == 2 and cfg.boss and conqTotal > 0 and conqKilled() >= conqTotal then
					conqEnterStage(3)
				elseif conqStage == 2 and not cfg.boss and ZoneControlService and conqPointsTotal > 0 then
					-- aggregate capture progress: secured points count whole, active points their fraction
					local sum = conqPointsDone
					for index = 1, conqPointsTotal do
						local zone = ZoneControlService.get("conq" .. index)
						if zone then
							sum += math.clamp(zone.progress, 0, 1)
						end
					end
					progress = math.clamp(sum / conqPointsTotal, 0, 1)
					publish()
				elseif conqStage == 3 and not cfg.boss then
					if conqHoldZoneUsed and ZoneControlService then
						local zone = ZoneControlService.get("conqhold")
						if zone then
							progress = math.clamp(zone.progress, 0, 1)
							workspace:SetAttribute("GF_DefenseEngaged", zone.state == "capturing")
							workspace:SetAttribute("GF_DefensePaused", zone.state ~= "capturing")
							publish()
						end
					else
						local duration = cfg.defend or 45
						local left = conqEndsAt - os.clock()
						progress = math.clamp(1 - left / duration, 0, 1)
						hint = string.format("Holding position: %d s", math.max(0, math.ceil(left)))
						publish()
						if left <= 0 then
							ObjectiveService.complete()
							break
						end
					end
				end
			end
			task.wait(0.5)
		end
	end)
end

local function buildConquest(position)
	local model = Instance.new("Model")
	model.Name = "ConquestSite"
	model:SetAttribute("GFObjective", "ConquestSite")
	local pad = partOf(model, Vector3.new(24, 1.2, 24), Vector3.new(0, 0.6, 0), Color3.fromRGB(40, 44, 40), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local pole = partOf(model, Vector3.new(0.7, 20, 0.7), Vector3.new(0, 10.6, 0), Color3.fromRGB(52, 56, 64), Enum.Material.Metal, position)
	pole.Name = "StandardPole"
	local flag = partOf(model, Vector3.new(5, 2.6, 0.2), Vector3.new(2.8, 19.2, 0), Color3.fromRGB(88, 176, 255), Enum.Material.Neon, position)
	flag.Name = "Standard"
	local terminal = partOf(model, Vector3.new(2.6, 3, 1.6), Vector3.new(0, 2.1, 6), Color3.fromRGB(30, 36, 44), Enum.Material.Metal, position)
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "ConquestConsole")
	terminal:SetAttribute("InteractPrompt", "Use console")
	local core = partOf(model, Vector3.new(3.4, 4.4, 3.4), Vector3.new(-6, 2.8, -4), Color3.fromRGB(56, 60, 68), Enum.Material.Metal, position)
	core.Name = "FacilityCore"
	-- capture pylons: the physical anchors of the multi-point seize, spread wide enough that one
	-- pair of eyes cannot cover two of them — spreading the squad thin is the point of the stage
	conqPointPositions = {}
	conqPointsDone = 0
	conqPointsTotal = 0
	conqHoldZoneUsed = false
	local cfg = conqConfig()
	local pointCount = math.max(1, math.floor(cfg.capturePoints or 1))
	if not cfg.boss then
		local actors = workspace:FindFirstChild("ActiveActors") or workspace
		for index = 1, pointCount do
			local angle = math.rad(60) + (index - 1) * (math.pi * 2 / pointCount)
			local radius = pointCount > 1 and 17 or 8
			local pointPos = position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			MissionSites.buildCapturePylon(pointPos, {
				name = "CapturePylon" .. (POINT_NAMES[index] or index),
				parent = actors,
			})
			table.insert(conqPointPositions, pointPos)
		end
	end
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

-- Sabotage | Shattered Aegis. Two linked generators power a shield emitter; the emitter is only
-- exposed once both generators are down. Structures carry GFIntegrityMax, so the weapon damage that
-- kills enemies also breaks them (CombatService.damageStructure), and their state is polled here.
local aegisStage = 0
local aegisRunId = 0
local aegisRetaliation = false

local function aegisPart(model, name, size, offset, color, material, position, integrity)
	local p = partOf(model, size, offset, color, material, position)
	p.Name = name
	p:SetAttribute("GFIntegrityMax", integrity)
	p:SetAttribute("GFIntegrity", integrity)
	p:SetAttribute("GFStructure", name)
	return p
end

local function aegisDown(model, name): boolean
	local part = model and model:FindFirstChild(name)
	return part ~= nil and part:GetAttribute("GFDestroyed") == true
end

local function aegisExpose(model)
	local emitter = model and model:FindFirstChild("ShieldEmitter")
	if not emitter then
		return
	end
	emitter:SetAttribute("GFExposed", true)
	emitter:SetAttribute("GFShielded", false)
	if emitter:IsA("BasePart") then
		emitter.CanQuery = true
		emitter.Transparency = 0.1
	end
	local lamp = model:FindFirstChild("EmitterLamp")
	if lamp and lamp:IsA("BasePart") then
		lamp.Transparency = 0
	end
end

local function aegisTick(model)
	local runId = aegisRunId
	task.spawn(function()
		while not complete and runId == aegisRunId do
			if not model or not model.Parent then
				break
			end
			if aegisStage == 1 then
				local down = 0
				if aegisDown(model, "GeneratorA") then
					down += 1
				end
				if aegisDown(model, "GeneratorB") then
					down += 1
				end
				-- first generator down is the loud part: the aegis network registers the loss and a
				-- telegraphed retaliator squad converges while the second generator is still up
				if down == 1 and not aegisRetaliation then
					aegisRetaliation = true
					local center = model.PrimaryPart and model.PrimaryPart.Position or Vector3.zero
					voss("Generator loss registered — retaliators inbound. Finish the other one fast.", "warning")
					missionEvent("Retaliator squad inbound!", "warning")
					flareAt(center + Vector3.new(14, 0, 10), 7)
					task.delay(cfgNum("responseDelay", 12), function()
						if complete then
							return
						end
						local roster = cfgList("responseRoster")
						if #roster == 0 then
							roster = { "Rifleman", "Heavy", "Scout" }
						end
						for index, enemyId in ipairs(roster) do
							local angle = (index / #roster) * math.pi * 2
							EnemyService.spawn(enemyId, center + Vector3.new(math.cos(angle) * 15, 0, math.sin(angle) * 15))
						end
					end)
				end
				progress = down / 2
				hint = string.format("Destroy the shield generators (%d / 2)", down)
				publish()
				if down >= 2 then
					aegisStage = 2
					workspace:SetAttribute("GF_AegisStage", 2)
					aegisExpose(model)
					progress = 0
					hint = "Destroy the exposed shield emitter"
					publish()
				end
			elseif aegisStage == 2 then
				local emitter = model:FindFirstChild("ShieldEmitter")
				local max = emitter and tonumber(emitter:GetAttribute("GFIntegrityMax")) or 700
				local current = emitter and tonumber(emitter:GetAttribute("GFIntegrity")) or max
				progress = math.clamp(1 - current / math.max(1, max), 0, 1)
				hint = string.format("Shield emitter integrity %d / %d", math.floor(current), math.floor(max))
				publish()
				if aegisDown(model, "ShieldEmitter") then
					ObjectiveService.complete()
					break
				end
			end
			task.wait(0.4)
		end
	end)
end

local function buildAegis(position)
	local model = Instance.new("Model")
	model.Name = "ShieldCompound"
	model:SetAttribute("GFObjective", "ShieldCompound")
	local pad = partOf(model, Vector3.new(30, 1.2, 30), Vector3.new(0, 0.6, 0), Color3.fromRGB(36, 38, 44), Enum.Material.Slate, position)
	pad.Name = "Pad"
	aegisPart(model, "GeneratorA", Vector3.new(5, 7, 5), Vector3.new(-9, 4.1, 0), Color3.fromRGB(64, 70, 84), Enum.Material.Metal, position, 300)
	aegisPart(model, "GeneratorB", Vector3.new(5, 7, 5), Vector3.new(9, 4.1, 0), Color3.fromRGB(64, 70, 84), Enum.Material.Metal, position, 300)
	local cableA = partOf(model, Vector3.new(1.2, 1.2, 9), Vector3.new(-4.6, 1.6, 0), Color3.fromRGB(28, 32, 40), Enum.Material.Metal, position)
	cableA.Name = "CableA"
	local cableB = partOf(model, Vector3.new(1.2, 1.2, 9), Vector3.new(4.6, 1.6, 0), Color3.fromRGB(28, 32, 40), Enum.Material.Metal, position)
	cableB.Name = "CableB"
	local emitter = aegisPart(model, "ShieldEmitter", Vector3.new(6, 10, 6), Vector3.new(0, 5.6, -10), Color3.fromRGB(120, 190, 235), Enum.Material.ForceField, position, 700)
	emitter.CanQuery = false
	emitter.Transparency = 0.45
	emitter:SetAttribute("GFShielded", true)
	local lamp = partOf(model, Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 11.2, -10), Color3.fromRGB(120, 210, 255), Enum.Material.Neon, position)
	lamp.Name = "EmitterLamp"
	lamp.Transparency = 0.6
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

-- Recovery | Fallen Convoy. The crates are physical hauls now: grabbed off the wreck, carried at
-- a speed cost, dropped where the carrier falls, and only scored on the salvage sled. The pursuit
-- squad is telegraphed the moment the first crate moves — loading the second crate under inbound
-- pressure is the mission, not a timer with extra clicks.
local convoyStage = 0
local convoyRecovered = 0
local convoyRunId = 0
local convoyTagged: { [Model]: boolean } = {}
local convoyTotal = 0
local convoyPursuitSpawned = false
local convoyPursuitAt = 0
local convoySledBed: BasePart? = nil

local uplinkStage = 0
local uplinkEndsAt = 0
local uplinkRunId = 0

local function pursuitTick()
	local runId = convoyRunId
	task.spawn(function()
		while not complete and runId == convoyRunId do
			if not objective or not objective.Parent then
				break
			end
			-- the pursuit lands on its telegraphed timer whether or not the loading is done —
			-- the warning is the pressure, not the kill count
			if not convoyPursuitSpawned and convoyPursuitAt > 0 and os.clock() >= convoyPursuitAt then
				convoyPursuitSpawned = true
				local centre = objective and objective.PrimaryPart and objective.PrimaryPart.Position or Vector3.zero
				local roster = cfgList("responseRoster")
				if #roster == 0 then
					roster = { "Rifleman", "Scout", "Heavy" }
				end
				convoyTagged = {}
				convoyTotal = 0
				for index, enemyId in ipairs(roster) do
					local angle = (index / #roster) * math.pi * 2
					local model = EnemyService.spawn(enemyId, centre + Vector3.new(math.cos(angle) * 14, 0, math.sin(angle) * 14))
					if model then
						model:SetAttribute("GF_ObjectiveTarget", true)
						convoyTagged[model] = true
						convoyTotal += 1
					end
				end
				flareAt(centre + Vector3.new(0, 0, 14), 6)
				voss("Pursuit squad on the ground. Finish loading or fight — pick fast.", "warning")
				if convoyStage == 2 then
					hint = string.format("Defeat the pursuit squad (0 / %d)", convoyTotal)
					publish()
				end
			end
			if convoyStage == 2 and convoyPursuitSpawned then
				local dead = 0
				for model in pairs(convoyTagged) do
					if model.Parent == nil or model:GetAttribute("Dead") == true then
						dead += 1
					end
				end
				progress = convoyTotal > 0 and dead / convoyTotal or 0
				hint = string.format("Defeat the pursuit squad (%d / %d)", dead, convoyTotal)
				publish()
				if convoyTotal > 0 and dead >= convoyTotal then
					ObjectiveService.complete()
					break
				end
			end
			task.wait(0.5)
		end
	end)
end

-- First-crate pickup trigger: the pursuit clock starts here, announced, so the squad knows the
-- price of the grab before they pay it.
local function convoyPursuitTrigger()
	if convoyPursuitAt > 0 or convoyPursuitSpawned then
		return
	end
	local delay = cfgNum("responseDelay", 18)
	convoyPursuitAt = os.clock() + delay
	voss(string.format("Ascendancy recovery team is inbound — %d seconds out. Load and move.", delay), "warning")
	missionEvent("Pursuit squad inbound — finish loading!", "warning")
	hint = "Pursuit inbound — haul the crates to the sled"
	publish()
end

-- Crate delivery onto the sled bed: the crate physically seats on the flatbed, visible proof
-- instead of a vanishing counter.
local function convoyDeliverCrate(player, record)
	convoyRecovered += 1
	workspace:SetAttribute("GF_ConvoyCrates", convoyRecovered)
	if convoySledBed and record.part == nil then
		-- re-seat the physical crate on the sled bed as squad-visible proof of the load
		local seated = Instance.new("Part")
		seated.Name = "SledCrate" .. convoyRecovered
		seated.Size = Vector3.new(2.2, 1.7, 1.8)
		seated.Color = Color3.fromRGB(214, 170, 96)
		seated.Material = Enum.Material.WoodPlanks
		seated.Anchored = true
		seated.CanCollide = false
		seated.CanQuery = false
		seated.CFrame = convoySledBed.CFrame * CFrame.new((convoyRecovered - 1.5) * 2.4, 1.35, 0)
		seated.Parent = workspace
	end
	progress = convoyRecovered / 2 * 0.5
	if convoyRecovered >= 2 then
		convoyStage = 2
		workspace:SetAttribute("GF_ConvoyStage", 2)
		if convoyPursuitSpawned then
			hint = string.format("Defeat the pursuit squad (0 / %d)", convoyTotal)
		else
			hint = "Crates secured — the pursuit is still inbound. Dig in."
		end
		publish()
	else
		hint = "Crate loaded — one more to the sled"
		publish()
		missionEvent("Crate secured on the sled — one remaining", "objective")
	end
end

local function uplinkTick()
	local runId = uplinkRunId
	task.spawn(function()
		while not complete and runId == uplinkRunId do
			if not objective or not objective.Parent then
				break
			end
			if uplinkStage == 2 then
				local left = uplinkEndsAt - os.clock()
				progress = math.clamp(1 - left / 75, 0, 1)
				hint = string.format("Defending the uplink: %d s", math.max(0, math.ceil(left)))
				publish()
				if left <= 0 then
					uplinkStage = 3
					workspace:SetAttribute("GF_UplinkStage", 3)
					hint = "Confirm the uplink at the console"
					local terminal = objective:FindFirstChild("Terminal")
					if terminal then
						terminal:SetAttribute("GFInteract", "UplinkConfirm")
						terminal:SetAttribute("InteractPrompt", "Confirm uplink")
					end
					publish()
					break
				end
			end
			task.wait(0.5)
		end
	end)
end

local function uplinkRequest(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local terminal = objective and objective:FindFirstChild("Terminal")
	if not root or not terminal then
		return
	end
	if (root.Position - terminal.Position).Magnitude > INTERACT_RANGE then
		return
	end
	if uplinkStage == 1 then
		uplinkStage = 2
		workspace:SetAttribute("GF_UplinkStage", 2)
		if ZoneControlService then
			-- The uplink only transmits while the squad holds the control zone around the dish;
			-- enemies inside freeze the upload. The 75-second passive timer becomes a perimeter
			-- hold — same duration contract, radically different play.
			local zoneCenter = objective and objective.PrimaryPart and objective.PrimaryPart.Position or terminal.Position
			ZoneControlService.create("uplink", {
				center = zoneCenter,
				radius = 26,
				label = "Uplink control zone",
				rate = 1 / 75,
				decay = 1 / 160,
				onComplete = function(_zone)
					if complete or uplinkStage ~= 2 then return end
					disarmWaves()
					uplinkStage = 3
					workspace:SetAttribute("GF_UplinkStage", 3)
					hint = "Confirm the uplink at the console"
					local term = objective and objective:FindFirstChild("Terminal")
					if term then
						term:SetAttribute("GFInteract", "UplinkConfirm")
						term:SetAttribute("InteractPrompt", "Confirm uplink")
					end
					publish()
				end,
				onStateChange = function(_zone, state)
					if uplinkStage ~= 2 then return end
					if state == "contested" then
						hint = "Upload frozen — clear the control zone!"
					elseif state == "capturing" then
						hint = "Uploading — hold the control zone"
					else
						hint = "Control zone empty — upload is bleeding"
					end
					publish()
				end,
			})
			hint = "Hold the uplink control zone"
			publish()
			-- telegraphed trace assaults: the uplink is a beacon the Ascendancy triangulates, and
			-- every wave is announced by compass bearing before it lands
			armWaves("uplink", zoneCenter)
			task.spawn(function()
				while uplinkStage == 2 and not complete do
					task.wait(0.5)
					local zone = ZoneControlService.get("uplink")
					if zone then
						progress = math.clamp(zone.progress, 0, 1)
						workspace:SetAttribute("GF_DefenseEngaged", zone.state == "capturing")
						workspace:SetAttribute("GF_DefensePaused", zone.state ~= "capturing")
						publish()
					else
						break
					end
				end
			end)
		else
			uplinkEndsAt = os.clock() + 75
			hint = "Defending the uplink: 75 s"
			publish()
			uplinkTick()
		end
	elseif uplinkStage == 3 then
		disarmWaves()
		ObjectiveService.complete()
	end
end

local function buildConvoy(position)
	local model = Instance.new("Model")
	model.Name = "ConvoyWreck"
	model:SetAttribute("GFObjective", "ConvoyWreck")
	local pad = partOf(model, Vector3.new(26, 1.2, 26), Vector3.new(0, 0.6, 0), Color3.fromRGB(36, 38, 42), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local hull = partOf(model, Vector3.new(12, 5, 20), Vector3.new(-6, 3, -6), Color3.fromRGB(70, 62, 54), Enum.Material.Metal, position)
	hull.Name = "Hull"
	hull.CFrame = CFrame.new(position + Vector3.new(-6, 3, -6)) * CFrame.Angles(math.rad(-8), math.rad(14), math.rad(6))
	local wing = partOf(model, Vector3.new(9, 1, 6), Vector3.new(4, 1.4, -10), Color3.fromRGB(58, 54, 50), Enum.Material.Metal, position)
	wing.Name = "Wing"
	-- crates carry no interact of their own — the case registry owns them as physical hauls
	local crateA = partOf(model, Vector3.new(3, 2.4, 2.6), Vector3.new(6, 1.8, 6), Color3.fromRGB(214, 170, 96), Enum.Material.WoodPlanks, position)
	crateA.Name = "CrateA"
	local crateB = partOf(model, Vector3.new(3, 2.4, 2.6), Vector3.new(10, 1.8, 1), Color3.fromRGB(214, 170, 96), Enum.Material.WoodPlanks, position)
	crateB.Name = "CrateB"
	-- salvage sled parked beside the wreck: the delivery destination, its flatbed large enough
	-- that a carrier can step on and the crates visibly seat on it
	local actors = workspace:FindFirstChild("ActiveActors") or workspace
	local sledPos = position + Vector3.new(2, 0, 14)
	local sled, bed = MissionSites.buildSalvageSled(sledPos, { parent = actors })
	convoySledBed = bed
	if convoySledBed then
		convoySledBed:SetAttribute("GFInteract", "ConvoySled")
		convoySledBed:SetAttribute("InteractPrompt", "Load crate onto sled")
	end
	convoyPursuitSpawned = false
	convoyPursuitAt = 0
	convoyRecovered = 0
	for index, crate in ipairs({ crateA, crateB }) do
		local caseId = "convcase" .. index
		caseRegister(caseId, crate.Position, {
			part = crate,
			label = "Supply crate",
			prompt = "Haul crate",
			destType = "point",
			destPos = convoySledBed and convoySledBed.Position or sledPos,
			destRadius = 11,
			onPickup = function()
				convoyPursuitTrigger()
			end,
			onDeliver = function(player, record)
				convoyDeliverCrate(player, record)
			end,
		})
	end
	local smoke = partOf(model, Vector3.new(2, 2, 2), Vector3.new(-2, 7, -8), Color3.fromRGB(40, 40, 44), Enum.Material.Slate, position)
	smoke.Name = "Smoke"
	smoke.Transparency = 0.4
	model.PrimaryPart = pad
	model.Parent = actors
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

local function buildUplink(position)
	local model = Instance.new("Model")
	model.Name = "UplinkStation"
	model:SetAttribute("GFObjective", "UplinkStation")
	local pad = partOf(model, Vector3.new(24, 1.2, 24), Vector3.new(0, 0.6, 0), Color3.fromRGB(34, 38, 44), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local mast = partOf(model, Vector3.new(1.6, 16, 1.6), Vector3.new(0, 8.8, 0), Color3.fromRGB(60, 66, 76), Enum.Material.Metal, position)
	mast.Name = "Mast"
	local dish = partOf(model, Vector3.new(8, 0.6, 8), Vector3.new(0, 17.4, 0), Color3.fromRGB(78, 86, 98), Enum.Material.Metal, position)
	dish.Name = "Dish"
	dish.CFrame = CFrame.new(position + Vector3.new(0, 17.4, 0)) * CFrame.Angles(math.rad(-34), 0, 0)
	local terminal = partOf(model, Vector3.new(2.6, 3, 1.6), Vector3.new(0, 2.1, 7), Color3.fromRGB(30, 36, 44), Enum.Material.Metal, position)
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "UplinkDish")
	terminal:SetAttribute("InteractPrompt", "Activate dish")
	local lamp = partOf(model, Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 18.8, 0), Color3.fromRGB(120, 210, 255), Enum.Material.Neon, position)
	lamp.Name = "UplinkLamp"
	lamp.Transparency = 0.5
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

-- Defense | Power Under Fire. The first Defence object that can actually be lost: it carries HP,
-- hostiles shoot it when no player is visible, the timer pauses when nobody is within 55 studs,
-- and its destruction fails the primary instead of completing it.
local powerStage = 0
local powerRemaining = 90
local powerAbsent = 0
local powerRunId = 0
local failed = false

local POWER_DURATION = 90
local POWER_HOLD_RADIUS = 55
local POWER_ABSENCE_LIMIT = 10

local function powerGenerator(): BasePart?
	local part = objective and objective:FindFirstChild("Generator")
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function powerIntegrity(): (number, number)
	local generator = powerGenerator()
	if not generator then
		return 0, 0
	end
	return tonumber(generator:GetAttribute("GFIntegrity")) or 0, tonumber(generator:GetAttribute("GFIntegrityMax")) or 0
end

local function powerFail()
	if failed or complete then
		return
	end
	failed = true
	progress = 0
	hint = "Generator destroyed — primary objective failed"
	workspace:SetAttribute("GF_ObjectiveFailed", true)
	pcall(function()
		require(script.Parent.DialogueService).say("You lost the objective. Emergency bird is inbound — move.", "fail")
	end)
	local mission = State.getMission()
	if mission then
		mission.objectiveComplete = false
		mission.failed = true
	end
	publish()
	local r = remote("ObjectiveComplete")
	if r then
		r:FireAllClients({ success = false, template = templateId, reason = "generator destroyed" })
	end
	-- A failed primary must offer the way out: previously it only changed a flag, so the squad was left
	-- in a mission that could never complete.
	pcall(function()
		require(script.Parent.ExtractionService).emergency()
	end)
end

local function powerTick()
	local runId = powerRunId
	task.spawn(function()
		while not complete and not failed and runId == powerRunId do
			local generator = powerGenerator()
			if not generator or not generator.Parent then
				break
			end
			if generator:GetAttribute("GFDestroyed") == true then
				powerFail()
				break
			end
			if powerStage == 2 and not (ZoneControlService and ZoneControlService.get("power")) then
				local occupied = false
				for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root and (root.Position - generator.Position).Magnitude <= POWER_HOLD_RADIUS then
						occupied = true
						break
					end
				end
				if occupied then
					powerAbsent = 0
					powerRemaining = math.max(0, powerRemaining - 0.5)
				else
					powerAbsent += 0.5
				end
				local current, max = powerIntegrity()
				workspace:SetAttribute("GF_DefenseRemaining", math.floor(powerRemaining))
				workspace:SetAttribute("GF_DefensePaused", powerAbsent > POWER_ABSENCE_LIMIT)
				workspace:SetAttribute("GF_DefenseEngaged", occupied)
				if powerAbsent > POWER_ABSENCE_LIMIT then
					hint = string.format("Defense paused — return to the generator (%d / %d)", math.floor(current), math.floor(max))
				else
					hint = string.format("Defending generator: %d s (%d / %d)", math.ceil(powerRemaining), math.floor(current), math.floor(max))
				end
				progress = math.clamp(1 - powerRemaining / POWER_DURATION, 0, 1)
				publish()
				if powerRemaining <= 0 then
					powerStage = 3
					workspace:SetAttribute("GF_PowerStage", 3)
					local terminal = objective:FindFirstChild("Terminal")
					if terminal then
						terminal:SetAttribute("GFInteract", "PowerStabilise")
						terminal:SetAttribute("InteractPrompt", "Stabilise output")
					end
					hint = "Stabilise the generator output"
					publish()
					break
				end
			end
			task.wait(0.5)
		end
	end)
end

local function powerRequest(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local terminal = objective and objective:FindFirstChild("Terminal")
	if not root or not terminal then
		return
	end
	if (root.Position - terminal.Position).Magnitude > INTERACT_RANGE then
		return
	end
	if powerStage == 1 then
		powerStage = 2
		workspace:SetAttribute("GF_PowerStage", 2)
		powerRemaining = POWER_DURATION
		powerAbsent = 0
		if ZoneControlService then
			-- Zone-driven defense: the generator spins up while the squad holds the perimeter
			-- and no enemy stands inside it. decay=0 matches the original pause-not-regress
			-- contract; contest by enemies is the new pressure layer.
			local generator = powerGenerator()
			local zoneCenter = generator and generator.Position or terminal.Position
			ZoneControlService.create("power", {
				center = zoneCenter,
				radius = POWER_HOLD_RADIUS,
				label = "Generator perimeter",
				rate = 1 / POWER_DURATION,
				decay = 0,
				onComplete = function(_zone)
					if complete or powerStage ~= 2 then return end
					disarmWaves()
					powerStage = 3
					workspace:SetAttribute("GF_PowerStage", 3)
					local term = objective and objective:FindFirstChild("Terminal")
					if term then
						term:SetAttribute("GFInteract", "PowerStabilise")
						term:SetAttribute("InteractPrompt", "Stabilise output")
					end
					hint = "Stabilise the generator output"
					publish()
				end,
				onStateChange = function(_zone, state)
					if powerStage ~= 2 then return end
					if state == "contested" then
						hint = "Generator seizing — clear the perimeter!"
					elseif state == "capturing" then
						hint = "Generator spinning up — hold the perimeter"
					else
						hint = "Perimeter empty — spin-up paused"
					end
					publish()
				end,
			})
			hint = "Hold the generator perimeter"
			publish()
			-- the spin-up is loud: telegraphed assault waves hit the perimeter on the vent schedule
			armWaves("power", zoneCenter)
			task.spawn(function()
				-- the vent beat: partway through spin-up the generator must vent pressure. The
				-- capture freezes, the perimeter fills with steam, and the squad holds blind for a
				-- few seconds — the defense mission's mid-hold mixup, on a telegraphed schedule.
				local vented = false
				while powerStage == 2 and not complete and not failed do
					task.wait(0.5)
					local zone = ZoneControlService.get("power")
					if zone then
						local ventAt = cfgNum("ventAt", 0)
						if not vented and ventAt > 0 and zone.progress >= ventAt then
							vented = true
							ZoneControlService.pause("power", true)
							hint = "Generator venting — spin-up frozen, hold the perimeter blind!"
							publish()
							missionEvent("Generator venting — hostiles closing in!", "warning")
							voss("Pressure vent. They'll hit you now — hold fast.", "warning")
							flareAt(zoneCenter, 8)
							task.delay(7, function()
								if powerStage == 2 and not complete and not failed and ZoneControlService then
									ZoneControlService.pause("power", false)
									hint = "Vent complete — spin-up resumed"
									publish()
								end
							end)
						end
						progress = math.clamp(zone.progress, 0, 1)
						workspace:SetAttribute("GF_DefenseEngaged", zone.state == "capturing")
						workspace:SetAttribute("GF_DefensePaused", zone.state ~= "capturing")
						workspace:SetAttribute("GF_DefenseRemaining", math.floor((1 - zone.progress) * POWER_DURATION))
						publish()
					else
						break
					end
				end
			end)
		end
		powerTick() -- still runs: integrity-destruction monitor in both modes, legacy countdown only without zones
	elseif powerStage == 3 then
		disarmWaves()
		ObjectiveService.complete()
	end
end

local function buildPower(position)
	local model = Instance.new("Model")
	model.Name = "PowerStation"
	model:SetAttribute("GFObjective", "PowerStation")
	local pad = partOf(model, Vector3.new(26, 1.2, 26), Vector3.new(0, 0.6, 0), Color3.fromRGB(34, 36, 42), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local difficulty = workspace:GetAttribute("GF_OperationDifficulty") or (State.getMission() or {}).difficulty or "Normal"
	local integrity = 600
	if difficulty == "Easy" then
		integrity = 800
	elseif difficulty == "Hard" or difficulty == "Extreme" then
		integrity = 650
	end
	local generator = partOf(model, Vector3.new(7, 9, 7), Vector3.new(0, 5.6, -8), Color3.fromRGB(72, 78, 90), Enum.Material.Metal, position)
	generator.Name = "Generator"
	generator:SetAttribute("GFIntegrityMax", integrity)
	generator:SetAttribute("GFIntegrity", integrity)
	generator:SetAttribute("GFStructure", "Generator")
	local core = partOf(model, Vector3.new(3, 3, 3), Vector3.new(0, 6, -8), Color3.fromRGB(255, 196, 96), Enum.Material.Neon, position)
	core.Name = "Core"
	local terminal = partOf(model, Vector3.new(2.6, 3, 1.6), Vector3.new(0, 2.1, 6), Color3.fromRGB(30, 36, 44), Enum.Material.Metal, position)
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "PowerRestore")
	terminal:SetAttribute("InteractPrompt", "Restore generator")
	local cable = partOf(model, Vector3.new(1.2, 1, 10), Vector3.new(0, 1.2, -1), Color3.fromRGB(28, 32, 40), Enum.Material.Metal, position)
	cable.Name = "Cable"
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

-- Sabotage | Burn the Arsenal. Two charge pads arm the depot; the stockpile is destroyed by the
-- authored detonation, not by weapon fire, and the player may leave during the 8 s warning.
local arsenalStage = 0
local arsenalPads = 0
local arsenalEndsAt = 0
local arsenalRunId = 0

local ARSENAL_WARNING = 8

-- Depot sabotage: each pad is a plant channel, not a touch. The planter is committed for the
-- duration — moving or going down interrupts the plant — and the first charge going in tripped
-- the depot's silent alarm: a telegraphed reaction squad converges while the second pad is armed.
local arsenalReactionAt = 0
local arsenalReactionSpawned = false

local function arsenalArmPad(pad, padName)
	pad:SetAttribute("GFCharged", true)
	pad.Color = Color3.fromRGB(255, 150, 70)
	arsenalPads += 1
	progress = arsenalPads / 2 * 0.8
	workspace:SetAttribute("GF_ArsenalPads", arsenalPads)
	if arsenalPads >= 2 then
		arsenalStage = 2
		arsenalEndsAt = os.clock() + ARSENAL_WARNING
		workspace:SetAttribute("GF_ArsenalStage", 2)
		hint = "Charges armed — clear the blast radius!"
		missionEvent("Depot charges armed — get clear!", "warning")
	else
		hint = string.format("Charge the depot pads (%d / 2)", arsenalPads)
		missionEvent("First charge planted — the depot is alerting. Expect company.", "warning")
	end
	publish()
end

local function arsenalReactionTrigger(center)
	if arsenalReactionAt > 0 or arsenalReactionSpawned then
		return
	end
	local delay = cfgNum("responseDelay", 16)
	arsenalReactionAt = os.clock() + delay
	voss(string.format("Depot silent alarm is out — reaction squad %d seconds out.", delay), "warning")
	task.delay(delay, function()
		if complete or arsenalStage ~= 1 then
			-- stage 2 means both charges are already in: the reaction squad still comes, the blast
			-- countdown does not wait for them
		end
		if complete then
			return
		end
		arsenalReactionSpawned = true
		local roster = cfgList("responseRoster")
		if #roster == 0 then
			roster = { "Rifleman", "Rifleman", "Scout" }
		end
		flareAt(center, 7)
		for index, enemyId in ipairs(roster) do
			local angle = (index / #roster) * math.pi * 2
			EnemyService.spawn(enemyId, center + Vector3.new(math.cos(angle) * 16, 0, math.sin(angle) * 16))
		end
	end)
end

local function arsenalRequest(player: Player)
	if arsenalStage ~= 1 then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, padName in ipairs({ "ChargePadA", "ChargePadB" }) do
		local pad = objective and objective:FindFirstChild(padName)
		if pad and pad:GetAttribute("GFCharged") ~= true and (root.Position - pad.Position).Magnitude <= INTERACT_RANGE then
			if holding[player] then
				return
			end
			holding[player] = true
			local plantTime = cfgNum("plantSeconds", 4)
			hint = string.format("Arming the depot charge — hold position (%d s)", plantTime)
			publish()
			-- the first plant starts the reaction clock: the second pad is armed under pressure
			arsenalReactionTrigger(pad.Position)
			task.spawn(function()
				local started = os.clock()
				while os.clock() - started < plantTime do
					task.wait(0.1)
					if complete or not player.Parent or not player.Character then
						holding[player] = nil
						return
					end
					local r = player.Character:FindFirstChild("HumanoidRootPart")
					if not r or (r.Position - pad.Position).Magnitude > INTERACT_RANGE + 4 then
						holding[player] = nil
						hint = "Arming interrupted — the pad is still live"
						publish()
						return
					end
				end
				holding[player] = nil
				arsenalArmPad(pad, padName)
			end)
			return
		end
	end
end

local function arsenalTick()
	local runId = arsenalRunId
	task.spawn(function()
		while not complete and runId == arsenalRunId do
			if not objective or not objective.Parent then
				break
			end
			if arsenalStage == 2 then
				local left = arsenalEndsAt - os.clock()
				progress = math.clamp(1 - left / ARSENAL_WARNING, 0, 1)
				hint = string.format("Detonation in %d s — clear the depot", math.max(0, math.ceil(left)))
				publish()
				if left <= 0 then
					arsenalStage = 3
					workspace:SetAttribute("GF_ArsenalStage", 3)
					local stockpile = objective:FindFirstChild("Stockpile")
					if stockpile and stockpile:IsA("BasePart") then
						local blast = Instance.new("Part")
						blast.Shape = Enum.PartType.Ball
						blast.Size = Vector3.new(10, 10, 10)
						blast.Position = stockpile.Position
						blast.Anchored = true
						blast.CanCollide = false
						blast.CanQuery = false
						blast.Material = Enum.Material.Neon
						blast.Color = Color3.fromRGB(255, 168, 72)
						blast.Transparency = 0.25
						blast.Parent = workspace
						TweenService:Create(blast, TweenInfo.new(1.1), { Size = Vector3.new(52, 52, 52), Transparency = 1 }):Play()
						task.delay(1.4, function()
							if blast.Parent then
								blast:Destroy()
							end
						end)
						stockpile.Transparency = 1
						stockpile.CanCollide = false
						stockpile.CanQuery = false
						stockpile:SetAttribute("GFDestroyed", true)
						workspace:SetAttribute("GF_ArsenalDetonated", true)
					end
					hint = "Stockpile destroyed"
					publish()
					ObjectiveService.complete()
					break
				end
			end
			task.wait(0.4)
		end
	end)
end

local function buildArsenal(position)
	local model = Instance.new("Model")
	model.Name = "AmmoDepot"
	model:SetAttribute("GFObjective", "AmmoDepot")
	local pad = partOf(model, Vector3.new(30, 1.2, 30), Vector3.new(0, 0.6, 0), Color3.fromRGB(38, 36, 34), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local stockpile = partOf(model, Vector3.new(12, 6, 9), Vector3.new(0, 4.1, -8), Color3.fromRGB(92, 78, 48), Enum.Material.WoodPlanks, position)
	stockpile.Name = "Stockpile"
	local stack = partOf(model, Vector3.new(8, 2.4, 8), Vector3.new(0, 8.2, -8), Color3.fromRGB(84, 72, 46), Enum.Material.WoodPlanks, position)
	stack.Name = "StockpileTop"
	local chargeA = partOf(model, Vector3.new(3, 0.6, 3), Vector3.new(-9, 1.5, 6), Color3.fromRGB(70, 90, 110), Enum.Material.Metal, position)
	chargeA.Name = "ChargePadA"
	chargeA:SetAttribute("GFInteract", "ArsenalPad")
	chargeA:SetAttribute("InteractPrompt", "Charge pad")
	local chargeB = partOf(model, Vector3.new(3, 0.6, 3), Vector3.new(9, 1.5, 6), Color3.fromRGB(70, 90, 110), Enum.Material.Metal, position)
	chargeB.Name = "ChargePadB"
	chargeB:SetAttribute("GFInteract", "ArsenalPad")
	chargeB:SetAttribute("InteractPrompt", "Charge pad")
	local warning = partOf(model, Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 9.6, -2), Color3.fromRGB(120, 120, 130), Enum.Material.Neon, position)
	warning.Name = "WarningLamp"
	warning.Transparency = 0.4
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

-- Recovery | Silent Archive. Three authored stages: reach the intel room, break the console with
-- the server-authoritative hacking challenge, then haul the decrypted canister back to the landing zone.
local archiveStage = 0
local archiveRunId = 0

local function archiveRequest(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local terminal = objective and objective:FindFirstChild("Terminal")
	if not root or not terminal then
		return
	end
	if (root.Position - terminal.Position).Magnitude > INTERACT_RANGE then
		return
	end
	if archiveStage == 2 then
		local difficulty = (State.getMission() or {}).difficulty or "Normal"
		HackingService.begin(player, difficulty, terminal.Position)
		hint = "Breaking the console — press " .. "E" .. " in the green arc"
		publish()
	end
end

local function archiveTick()
	local runId = archiveRunId
	task.spawn(function()
		while not complete and runId == archiveRunId do
			if not objective or not objective.Parent then
				break
			end
			if archiveStage == 1 then
				local terminal = objective:FindFirstChild("Terminal")
				for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if terminal and root and (root.Position - terminal.Position).Magnitude <= 25 then
						archiveStage = 2
						workspace:SetAttribute("GF_ArchiveStage", 2)
						terminal:SetAttribute("GFInteract", "ArchiveConsole")
						terminal:SetAttribute("InteractPrompt", "Break console")
						hint = "Break the data console"
						publish()
						break
					end
				end
			end
			task.wait(0.5)
		end
	end)
end

local function buildArchive(position)
	local model = Instance.new("Model")
	model.Name = "IntelRoom"
	model:SetAttribute("GFObjective", "IntelRoom")
	local pad = partOf(model, Vector3.new(24, 1.2, 24), Vector3.new(0, 0.6, 0), Color3.fromRGB(32, 34, 40), Enum.Material.Slate, position)
	pad.Name = "Pad"
	local wallA = partOf(model, Vector3.new(24, 10, 1), Vector3.new(0, 5.6, -11), Color3.fromRGB(52, 56, 64), Enum.Material.Metal, position)
	wallA.Name = "WallBack"
	local wallB = partOf(model, Vector3.new(1, 10, 22), Vector3.new(-11, 5.6, 0), Color3.fromRGB(52, 56, 64), Enum.Material.Metal, position)
	wallB.Name = "WallLeft"
	local terminal = partOf(model, Vector3.new(3, 2.6, 2), Vector3.new(0, 2.4, -8), Color3.fromRGB(34, 40, 50), Enum.Material.Metal, position)
	terminal.Name = "Terminal"
	terminal:SetAttribute("GFInteract", "ArchiveConsole")
	terminal:SetAttribute("InteractPrompt", "Inspect console")
	local screen = partOf(model, Vector3.new(2.6, 1.6, 0.2), Vector3.new(0, 3.4, -6.9), Color3.fromRGB(60, 190, 220), Enum.Material.Neon, position)
	screen.Name = "Screen"
	local intel = partOf(model, Vector3.new(2, 1.4, 2), Vector3.new(6, 1.6, 2), Color3.fromRGB(230, 200, 120), Enum.Material.Metal, position)
	intel.Name = "IntelCase"
	intel.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(96, 190, 240); light.Brightness = 0.25; light.Range = 22; light.Shadows = false
	light.Parent = screen
	model.PrimaryPart = pad
	model.Parent = workspace:FindFirstChild("ActiveActors") or workspace
	OutpostService.build(position)
	-- S07-030: small outposts carry 2-4 defenders staggered in cover positions — a garrison, not a
	-- wave. Site-locked inside the spawn cap, distinct from director waves.
	task.delay(2, function()
		local EncounterDirector = require(script.Parent.EncounterDirector)
		local defenderCount = 2 + math.random(0, 2)
		EncounterDirector.spawnAround(position, 22, defenderCount)
		workspace:SetAttribute("GF_OutpostDefenders", defenderCount)
	end)
	return model
end

function ObjectiveService.resetState()
	progress = 0
	complete = false
end

function ObjectiveService.setup(position, template)
	if objective then objective:Destroy() end
	ObjectiveService.resetState()
	shieldNodes = {}
	nodesBreached = 0
	beaconZoneDone = false
	beaconResyncPending = false
	beaconResynced = false
	if ZoneControlService then
		ZoneControlService.destroyAll()
	end
	-- A fresh mission gets its own rewards ledger, so seq restarts and claim-once is scoped per mission.
	pcall(function()
		require(script.Parent.RewardLedgerService).begin(template)
	end)
	-- A fresh mission has not committed its war points yet.
	workspace:SetAttribute("GF_WarCommitted", false)
	holding = {}
	-- setup runs before EncounterDirector.reset, which sweeps boss models, so the previous mission's
	-- tagged targets are removed here and the fresh one is spared by its tag.
	for stale in pairs(elimTargets) do
		if stale.Parent then
			stale:Destroy()
		end
	end
	elimTargets = {}
	elimTotal = 0
	elimKilled = 0
	elimRunning = false
	elimRunId += 1
	conqStage = 0
	conqTagged = {}
	conqTotal = 0
	conqEndsAt = 0
	conqRunId += 1
	aegisStage = 0
	aegisRunId += 1
	aegisRetaliation = false
	convoyStage = 0
	convoyRecovered = 0
	convoyTagged = {}
	convoyTotal = 0
	convoyRunId += 1
	uplinkStage = 0
	uplinkEndsAt = 0
	uplinkRunId += 1
	powerStage = 0
	powerRemaining = POWER_DURATION
	powerAbsent = 0
	powerRunId += 1
	arsenalStage = 0
	arsenalPads = 0
	arsenalReactionAt = 0
	arsenalReactionSpawned = false
	arsenalEndsAt = 0
	arsenalRunId += 1
	archiveStage = 0
	archiveRunId += 1
	-- carry system: every case, carrier weld and delivery patch belongs to the mission that made it
	for player in pairs(carrying) do
		dropCaseVisual(player)
		restoreSpeed(player)
	end
	carrying = {}
	for _, record in pairs(cases) do
		if record.part and record.part.Parent then
			record.part:Destroy()
		end
	end
	cases = {}
	if deliveryRing and deliveryRing.Parent then
		deliveryRing:Destroy()
	end
	deliveryRing = nil
	blackboxHackRunning = false
	-- elimination hunt state
	elimHuntStartedAt = 0
	elimIntelUsed = false
	elimIntelConsole = nil
	workspace:SetAttribute("GF_CleanHunt", false)
	-- conquest multi-point state
	conqPointPositions = {}
	conqPointsDone = 0
	conqPointsTotal = 0
	conqHoldZoneUsed = false
	-- convoy pursuit state
	convoyPursuitSpawned = false
	convoyPursuitAt = 0
	convoySledBed = nil
	disarmWaves()
	failed = false
	workspace:SetAttribute("GF_ObjectiveFailed", false)
	workspace:SetAttribute("GF_DefenseStructure", nil)
	defending = false
	defendEndsAt = 0
	-- callers that only pass a position still get the template the player actually chose
	templateId = template or (function()
		local m = State.getMission()
		return type(m) == "table" and m.objectiveTemplate or nil
	end)() or "SABOTAGE_RELAY"
	local pos = ground(position)
	-- carve + measure the compound pad BEFORE anything is placed, so every builder (and the
	-- outpost kit) sits on the final voxel surface instead of being swallowed by a later carve
	pos = Vector3.new(pos.X, OutpostService.level(pos) + 0.4, pos.Z)
	if templateId == "RECOVER_TECH" then
		objective = buildBlackBox(pos)
		hint = "Decrypt the black box at the crash-site terminal"
	elseif templateId == "DEFEND_BEACON" then
		objective = buildBeacon(pos)
		hint = "Activate the beacon, then hold the position"
	elseif templateId == "RECOVERY_ARCHIVE" then
		objective = buildArchive(pos)
	elseif templateId == "SABOTAGE_ARSENAL" then
		objective = buildArsenal(pos)
	elseif templateId == "DEFENSE_POWER" then
		objective = buildPower(pos)
	elseif templateId == "RECOVERY_CONVOY" then
		objective = buildConvoy(pos)
	elseif templateId == "DEFENSE_UPLINK" then
		objective = buildUplink(pos)
	elseif templateId == "SABOTAGE_AEGIS" then
		objective = buildAegis(pos)
	elseif string.sub(templateId, 1, 8) == "CONQUEST" then
		objective = buildConquest(pos)
	elseif string.sub(templateId, 1, 5) == "ELIM_" then
		objective = buildElimination(pos)
	else
		objective = buildRelay(pos)
		hint = "Breach the three shield nodes, then plant the charge"
	end
	if string.sub(templateId, 1, 5) == "ELIM_" and elimTotal > 0 and not complete then
		elimTick()
	end
	if string.sub(templateId, 1, 8) == "CONQUEST" and not complete then
		conqEnterStage(1)
		conqTick()
	end
	if templateId == "RECOVERY_ARCHIVE" and not complete then
		archiveStage = 1
		workspace:SetAttribute("GF_ArchiveStage", 1)
		hint = "Reach the intel room"
		archiveTick()
		publish()
	end
	if templateId == "SABOTAGE_ARSENAL" and not complete then
		arsenalStage = 1
		workspace:SetAttribute("GF_ArsenalStage", 1)
		hint = "Charge the depot pads (0 / 2)"
		arsenalTick()
		publish()
	end
	if templateId == "DEFENSE_POWER" and not complete then
		powerStage = 1
		workspace:SetAttribute("GF_PowerStage", 1)
		-- Measured: an Instance stored in an attribute comes back as an InstanceHandle, and IsA on it errors
		-- inside the enemy tick. Publish names instead and let the consumer resolve them.
		workspace:SetAttribute("GF_DefenseModel", objective.Name)
		workspace:SetAttribute("GF_DefensePart", "Generator")
		hint = "Restore the generator"
		publish()
	end
	if templateId == "RECOVERY_CONVOY" and not complete then
		convoyStage = 1
		workspace:SetAttribute("GF_ConvoyStage", 1)
		hint = "Haul the convoy crates to the salvage sled (0 / 2)"
		pursuitTick()
		publish()
	end
	if templateId == "DEFENSE_UPLINK" and not complete then
		uplinkStage = 1
		workspace:SetAttribute("GF_UplinkStage", 1)
		hint = "Activate the communications dish"
		publish()
	end
	if templateId == "SABOTAGE_AEGIS" and not complete then
		aegisStage = 1
		workspace:SetAttribute("GF_AegisStage", 1)
		aegisTick(objective)
	end
	local mission = State.getMission()
	if mission then
		mission.objectiveComplete = false
		mission.objectiveTemplate = templateId
	end
	publish()
	return objective
end

local function defendTick()
	task.spawn(function()
		while defending and not complete do
			local left = defendEndsAt - os.clock()
			progress = math.clamp(1 - left / DEFEND_TIME, 0, 1)
			hint = string.format("Holding beacon: %d s", math.max(0, math.ceil(left)))
			publish()
			if left <= 0 then
				ObjectiveService.complete()
				break
			end
			task.wait(0.5)
		end
	end)
end

-- Sabotage breach flow: nodes first (tagged ring hacks), then the charge at the core terminal.
-- Node discrimination is by proximity — the squad never has to think about which console they
-- are standing at, only whether it still glows.
local function sabotageRequest(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	-- nearest unbreached node in range wins over the core terminal
	for i, node in ipairs(shieldNodes) do
		if not node.breached and (root.Position - node.position).Magnitude <= INTERACT_RANGE + 2 then
			if node.busy and node.busy ~= player then
				hint = "Node already being breached — cover your squadmate"
				publish()
				return
			end
			if node.busy == player then
				return -- mid-hack: interacting again must not restart the challenge
			end
			node.busy = player
			local difficulty = (State.getMission() or {}).difficulty or "Normal"
			HackingService.begin(player, difficulty, node.position, "node" .. i)
			hint = string.format("Breaching node %d of 3 — press in the green arc (%d remaining)", i, 3 - nodesBreached)
			publish()
			return
		end
	end
	-- core terminal: blocked until the shield is down, then a 4s charge plant
	local terminal = objective and objective:FindFirstChild("Terminal")
	if not terminal or (root.Position - terminal.Position).Magnitude > INTERACT_RANGE then return end
	if nodesBreached < 3 then
		hint = string.format("Relay shielded — breach the field nodes (%d of 3 remaining)", 3 - nodesBreached)
		publish()
		return
	end
	if holding[player] then return end
	holding[player] = true
	local st = State.get(player)
	if st then st.atConsole = true end
	ObjectiveService.showScreen(true)
	hint = "Planting the demolition charge — hold position"
	publish()
	task.spawn(function()
		local started = os.clock()
		local plantTime = 4
		while os.clock() - started < plantTime do
			task.wait(0.1)
			if complete or not player.Parent or not player.Character then
				holding[player] = nil ObjectiveService.clearScreen(player) return
			end
			local r = player.Character:FindFirstChild("HumanoidRootPart")
			if not r or (r.Position - terminal.Position).Magnitude > INTERACT_RANGE + 4 then
				holding[player] = nil ObjectiveService.clearScreen(player) return
			end
			progress = math.clamp(0.9 + (os.clock() - started) / plantTime * 0.1, 0, 1)
			publish()
		end
		holding[player] = nil
		ObjectiveService.clearScreen(player)
		ObjectiveService.complete()
	end)
end

function ObjectiveService.request(player, target)
	if complete or not objective then return end
	-- case grabs and the battle-net post are self-discriminating interactions: they bypass the
	-- template terminal flow entirely and resolve against their own registries
	if target == "MissionCase" or target == "ConvoySled" then
		return caseRequest(player)
	end
	if target == "IntelConsole" then
		return elimIntelRequest(player)
	end
	if templateId == "SABOTAGE_RELAY" then
		return sabotageRequest(player)
	end
	if templateId == "DEFENSE_UPLINK" then
		return uplinkRequest(player)
	end
	if templateId == "DEFENSE_POWER" then
		return powerRequest(player)
	end
	if templateId == "SABOTAGE_ARSENAL" then
		return arsenalRequest(player)
	end
	if templateId == "RECOVERY_ARCHIVE" then
		return archiveRequest(player)
	end
	local terminal = objective:FindFirstChild("Terminal")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not terminal then return end
	if (root.Position - terminal.Position).Magnitude > INTERACT_RANGE then return end
	if holding[player] then return end
	-- desync re-sync: the capture is paused, one player runs the ring hack at the terminal
	if templateId == "DEFEND_BEACON" and defending and beaconResyncPending then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local terminal = objective and objective:FindFirstChild("Terminal")
		if root and terminal and (root.Position - terminal.Position).Magnitude <= INTERACT_RANGE then
			local difficulty = (State.getMission() or {}).difficulty or "Normal"
			HackingService.begin(player, difficulty, terminal.Position, "beaconresync")
			hint = "Re-syncing — press in the green arc"
			publish()
		end
		return
	end
	if templateId == "DEFEND_BEACON" and defending then return end
	-- RECOVER_TECH: the black box is encrypted — the terminal runs a ring hack to crack it, and only
	-- then does the flight recorder physically exist in the world to be grabbed and hauled. The
	-- decrypt is the infiltration beat; the carry is the extraction beat.
	if templateId == "RECOVER_TECH" then
		local blackbox = cases["blackboxcase"]
		if blackbox and blackbox.state == "sealed" then
			if blackboxHackRunning then
				hint = "Decryption already running — cover your squadmate"
				publish()
				return
			end
			blackboxHackRunning = true
			local difficulty = (State.getMission() or {}).difficulty or "Normal"
			HackingService.begin(player, difficulty, terminal.Position, "blackbox")
			hint = "Decrypting the black box — press in the green arc"
			publish()
		end
		return
	end
	if string.sub(templateId, 1, 8) == "CONQUEST" then
		if not conqInteractive() then
			return
		end
		local cfg = conqConfig()
		local isHackStage = (conqStage == 1 and cfg.stage1 == "interact") or (conqStage == 3 and cfg.boss)
		if isHackStage then
			return conqRequest(player)
		end
		-- otherwise: the no-zone-service capture fallback, which stays a console hold below
	end
	holding[player] = true
	local st = State.get(player)
	if st then
		st.atConsole = true
	end
	ObjectiveService.showScreen(true)
	local holdFor = SABOTAGE_HOLD
	-- RECOVER_TECH is a pickup now, not a 7s hold: the work happens carrying the case back to the landing
	-- zone, so the grab itself is quick.
	if templateId == "RECOVER_TECH" then holdFor = 0.6 end
	if templateId == "DEFEND_BEACON" then holdFor = DEFEND_ACTIVATE end
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < holdFor do
			task.wait(0.1)
			if complete or not player.Parent or not player.Character then
			holding[player] = nil st = nil ObjectiveService.clearScreen(player) return end
			local r = player.Character:FindFirstChild("HumanoidRootPart")
			if not r or (r.Position - terminal.Position).Magnitude > INTERACT_RANGE + 4 then
			holding[player] = nil st = nil ObjectiveService.clearScreen(player) return end
			progress = math.clamp((os.clock() - started) / holdFor, 0, 1)
			publish()
		end
		holding[player] = nil
		ObjectiveService.clearScreen(player)
		if string.sub(templateId, 1, 8) == "CONQUEST" then
			conqEnterStage(conqStage + 1)
			return
		end
		if templateId == "DEFEND_BEACON" then
			defending = true
			-- capture-zone defense: the perimeter must be HELD, not just survived. Progress
			-- accrues while the squad is inside and no enemy contests; at 50% the beacon
			-- desyncs and one player must re-sync it (ring hack) while the rest hold.
			local beaconPos = objective and objective.PrimaryPart and objective.PrimaryPart.Position or terminal.Position
			hint = "Hold the beacon perimeter"
			publish()
			if ZoneControlService then
				ZoneControlService.create("beacon", {
					center = beaconPos,
					radius = 30,
					label = "Beacon perimeter",
					rate = 1 / 75,
					decay = 1 / 160,
					onComplete = function(_zone)
						if not complete then
							progress = 1
							ObjectiveService.complete()
						end
					end,
					onStateChange = function(_zone, state)
						if state == "contested" then
							hint = "Zone contested — clear the perimeter!"
						elseif state == "capturing" then
							hint = "Capturing the perimeter — hold it"
						else
							hint = "Perimeter empty — capture is bleeding"
						end
						publish()
					end,
				})
				-- desync mix at 50%: pause the capture, demand a re-sync hack at the terminal
				task.spawn(function()
					while defending and not complete and not beaconResynced do
						task.wait(0.5)
						local zone = ZoneControlService.get("beacon")
						if zone and zone.progress >= 0.5 then
							beaconResyncPending = true
							ZoneControlService.pause("beacon", true)
							terminal:SetAttribute("InteractPrompt", "Re-sync beacon")
							hint = "Beacon desync — one player re-sync at the terminal, the rest hold the line"
							publish()
							local ev = ReplicatedStorage.GF.Remotes:FindFirstChild("MissionEvent")
							if ev then
								ev:FireAllClients({ text = "Beacon desync! Re-sync at the terminal.", kind = "objective" })
							end
							break
						end
					end
				end)
				-- mirror zone progress into the objective HUD channel
				task.spawn(function()
					while defending and not complete do
						task.wait(0.5)
						local zone = ZoneControlService.get("beacon")
						if zone then
							progress = math.clamp(zone.progress, 0, 1)
							publish()
						else
							break
						end
					end
				end)
			else
				defendEndsAt = os.clock() + DEFEND_TIME
				defendTick()
			end
		else
			ObjectiveService.complete()
		end
	end)
end

-- The carry-system heartbeat. Every half second it does the four jobs that make a carried object
-- physical: caps the carrier's speed (the cost), remembers their last healthy footing (the drop
-- spot), drops the case when the carrier goes down, dies or leaves (the squad-recoverable beat),
-- and scores the delivery when a carrier stands inside the destination (the payoff).
task.spawn(function()
	while true do
		task.wait(0.5)
		if not complete then
			local lz = workspace:GetAttribute("GF_LZ")
			for player, caseId in pairs(carrying) do
				local record = cases[caseId]
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not record or not root or not humanoid then
					-- carrier left the game or reset without a character: the case drops where they were
					if record then
						carrying[player] = nil
						carryModels[player] = nil
						record.carrier = nil
						record.state = "dropped"
						caseSpawnWorldPart(record)
						hint = string.format("The %s was dropped — recover it", record.label)
						publish()
					else
						carrying[player] = nil
					end
				elseif humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then
					caseDrop(player)
					hint = string.format("%s down — the %s is on the ground. Recover it!", player.Name, record.label)
					publish()
					missionEvent(string.format("%s dropped the %s!", player.Name, record.label), "warning")
				elseif player:GetAttribute("GF_Downed") == true then
					caseDrop(player)
					hint = string.format("%s is down — the %s is on the ground. Recover it!", player.Name, record.label)
					publish()
					missionEvent(string.format("%s dropped the %s!", player.Name, record.label), "warning")
				else
					-- speed cap: stance systems re-derive WalkSpeed constantly, so the cap is re-asserted,
					-- not set once — the carrier is slow no matter what they press
					local cap = carryCap()
					if humanoid.WalkSpeed > cap then
						humanoid.WalkSpeed = cap
					end
					-- last healthy footing: only refreshed while standing on the ground, so a drop never
					-- teleports the case mid-air or inside geometry the carrier fell out of
					if humanoid.FloorMaterial ~= Enum.Material.Air then
						record.lastPos = root.Position
					end
					-- delivery: inside the destination ring, the case is scored
					local destPos, destRadius
					if record.destType == "lz" then
						destPos = typeof(lz) == "Vector3" and lz or nil
						destRadius = record.destRadius or 18
					else
						destPos = record.destPos
						destRadius = record.destRadius or 10
					end
					if destPos and (root.Position - destPos).Magnitude <= destRadius then
						caseDeliver(record)
					end
				end
			end
		end
	end
end)

function ObjectiveService.complete()
	if complete then return end
	complete = true
	progress = 1
	local mission = State.getMission()
	if mission then mission.objectiveComplete = true end
	workspace:SetAttribute("GF_ObjectiveComplete", true)
	-- War points commit here, once, at primary success, independent of the way out (S09-035).
	pcall(function()
		require(script.Parent.GalacticWarService).commitPrimary(templateId)
	end)
	-- Record, do not pay: the ledger is append-only and RewardsService still owns the payout.
	pcall(function()
		local ledgerMission = State.getMission()
		local ledgerDifficulty = (ledgerMission and ledgerMission.difficulty) or "Normal"
		require(script.Parent.RewardLedgerService).appendEvent("primary_complete", ledgerDifficulty, "primary:" .. tostring(templateId))
	end)
	pcall(function()
		require(script.Parent.DialogueService).say("Primary objective complete. Wrap it up and get to the ship.", "objective")
	end)
	-- The guaranteed mission cache is paid at successful extraction, not on completion: a squad that
	-- loses the dropship should not keep it. See ExtractionService.finish.
	print("[GF] objective complete (" .. templateId .. ")")
	publish()
	if objective then
		for _, p in objective:GetChildren() do
			if p:IsA("BasePart") and p.Material == Enum.Material.Neon then
				TweenService:Create(p, TweenInfo.new(0.8), { Transparency = 1 }):Play()
			end
		end
		if templateId == "SABOTAGE_RELAY" then
			local boom = Instance.new("Explosion")
			local pivot = objective.PrimaryPart
			boom.Position = pivot and (pivot.Position + Vector3.new(0, 14, 0)) or Vector3.zero
			boom.BlastRadius = 24; boom.BlastPressure = 0; boom.DestroyJointRadiusPercent = 0
			boom.Parent = workspace
			task.delay(1.2, function() if objective then objective:Destroy() objective = nil end end)
		end
	end
	local r = remote("ObjectiveComplete")
	if r then r:FireAllClients(templateId) end
end

function ObjectiveService.isComplete() return complete end
function ObjectiveService.getProgress() return progress end
-- Hardlight screen: a visible barrier that rises between the console and whoever is watching it, so
-- the mitigation is legible rather than an invisible number.
function ObjectiveService.showScreen(visible: boolean)
	local relay = ObjectiveService.getRelay()
	if not relay then
		return
	end
	visible = visible or workspace:GetAttribute("GF_ForceConsoleScreen") == true
	local screen = relay:FindFirstChild("ConsoleScreen")
	if not screen then
		local host = relay.PrimaryPart or relay:FindFirstChildWhichIsA("BasePart")
		if not host then
			return
		end
		screen = Instance.new("Part")
		screen.Name = "ConsoleScreen"
		screen.Size = Vector3.new(9, 4.4, 0.25)
		screen.Anchored = true
		screen.CanCollide = false
		screen.CanQuery = true
		screen.Material = Enum.Material.ForceField
		screen.Color = Color3.fromRGB(96, 214, 232)
		screen.Transparency = 0.35
		screen.CFrame = host.CFrame * CFrame.new(0, 4.2, -9.5)
		screen.Parent = relay
	end
	screen.Transparency = visible and 0.35 or 1
	workspace:SetAttribute("GF_ConsoleScreen", visible)
end

function ObjectiveService.clearScreen(player: Player?)
	if player then
		local st = State.get(player)
		if st then
			st.atConsole = nil
		end
	end
	ObjectiveService.showScreen(false)
end

function ObjectiveService.getRelay() return objective end
function ObjectiveService.getTemplate() return templateId end

function ObjectiveService.start()
	-- Cancellation is a first-class outcome: leaving the console, going down or disconnecting releases it.
	HackingService.onCancel = function(_player, reason, _challengeId, tag)
		if templateId == "RECOVER_TECH" and tag == "blackbox" then
			blackboxHackRunning = false
			hint = string.format("Decryption interrupted (%s) — the black box is still sealed", tostring(reason))
			publish()
			return
		end
		if tag == "elimintel" then
			hint = string.format("Slice interrupted (%s) — the battle-net post stays live", tostring(reason))
			publish()
			return
		end
		if tag == "conqhack" then
			hint = string.format("Slice interrupted (%s) — try the console again", tostring(reason))
			publish()
			return
		end
		if templateId == "SABOTAGE_RELAY" and type(tag) == "string" then
			local idx = tonumber(string.sub(tag, 5))
			local node = idx and shieldNodes[idx]
			if node and node.busy == _player then
				node.busy = nil
				hint = string.format("Breach interrupted (%s) — the node is still up", tostring(reason))
				publish()
			end
			return
		end
		if templateId == "DEFEND_BEACON" and tag == "beaconresync" then
			hint = string.format("Re-sync interrupted (%s) — the capture stays paused", tostring(reason))
			publish()
			return
		end
		if templateId == "RECOVERY_ARCHIVE" and archiveStage == 2 then
			hint = string.format("Console lock released (%s) — break the console again", tostring(reason))
			publish()
		end
	end
	-- Alarm consequence: a missed ring press trips the node's intrusion detection and the
	-- garrison responds. Capped per node so a struggling player is pressured, not buried.
	HackingService.onMiss = function(player, _challengeId, tag)
		if tag == "elimintel" and string.sub(templateId, 1, 5) == "ELIM_" then
			-- a fumbled slice lights up the battle-net: the garrison converges on the post
			if elimIntelConsole and elimIntelConsole.Parent then
				task.defer(function()
					local ok, EncounterDirector = pcall(function()
						return require(script.Parent.EncounterDirector)
					end)
					if ok and EncounterDirector and EncounterDirector.spawnAround then
						EncounterDirector.spawnAround(elimIntelConsole.Position, 18, 2)
					end
				end)
				missionEvent("Slice failed — hostiles converging on the intel post!", "warning")
			end
			return
		end
		if templateId == "SABOTAGE_RELAY" and type(tag) == "string" then
			local idx = tonumber(string.sub(tag, 5))
			local node = idx and shieldNodes[idx]
			if node and not node.breached and node.alarms < 2 then
				node.alarms += 1
				task.defer(function()
					local ok, EncounterDirector = pcall(function()
						return require(script.Parent.EncounterDirector)
					end)
					if ok and EncounterDirector and EncounterDirector.spawnAround then
						EncounterDirector.spawnAround(node.position, 20, 2)
					end
				end)
				hint = "Alarm tripped — defenders converging on the node!"
				publish()
				local ev = ReplicatedStorage.GF.Remotes:FindFirstChild("MissionEvent")
				if ev then
					ev:FireAllClients({ text = "Alarm tripped — defenders inbound!", kind = "warning" })
				end
			end
		end
	end
	-- The hacking challenge owns its own success; the archive objective is told, not polled.
	HackingService.onComplete = function(_player, _challengeId, tag)
		-- black box decrypt: the recorder materialises in the world, ready to be grabbed and hauled
		if templateId == "RECOVER_TECH" and tag == "blackbox" then
			blackboxHackRunning = false
			caseReveal("blackboxcase")
			local crate = objective and objective:FindFirstChild("BlackBox")
			if crate then crate.Transparency = 1 crate.CanQuery = false end
			local lid = objective and objective:FindFirstChild("Lid")
			if lid then lid.Material = Enum.Material.Metal end
			progress = 0.25
			hint = "Black box decrypted — grab the flight recorder"
			publish()
			missionEvent("Black box decrypted — take the flight recorder", "objective")
			return
		end
		-- battle-net slice: every living target is confirmed at once — the deliberate-reveal path
		if tag == "elimintel" and string.sub(templateId, 1, 5) == "ELIM_" then
			elimIntelUsed = true
			elimRevealAll("intel")
			if elimIntelConsole and elimIntelConsole.Parent then
				elimIntelConsole:SetAttribute("InteractPrompt", "Battle-net sliced")
				elimIntelConsole:SetAttribute("GFInteract", "None")
			end
			missionEvent("Battle-net sliced — all targets confirmed", "objective")
			return
		end
		-- conquest slices: the foundry power coupling advances the assault, the thronefall command
		-- node ends the operation
		if tag == "conqhack" and string.sub(templateId, 1, 8) == "CONQUEST" then
			local cfg = conqConfig()
			if conqStage == 1 and cfg.stage1 == "interact" then
				missionEvent("Turret power cut — push into the base", "objective")
				conqEnterStage(2)
			elseif conqStage == 3 and cfg.boss then
				conqEnterStage(4)
			end
			return
		end
		-- sabotage node breach: core goes dark, count toward the shield collapse
		if templateId == "SABOTAGE_RELAY" and type(tag) == "string" then
			local idx = tonumber(string.sub(tag, 5))
			local node = idx and shieldNodes[idx]
			if node and not node.breached then
				node.breached = true
				node.busy = nil
				nodesBreached += 1
				if node.core then
					node.core.Material = Enum.Material.Metal
					node.core.Color = Color3.fromRGB(52, 56, 68)
				end
				if node.glow then
					node.glow.Enabled = false
				end
				if node.plate then
					node.plate:SetAttribute("InteractPrompt", "Node breached")
				end
				progress = math.clamp(nodesBreached / 3 * 0.9, 0, 0.9)
				if nodesBreached >= 3 then
					hint = "Shield down — plant the charge at the relay console"
					local ev = ReplicatedStorage.GF.Remotes:FindFirstChild("MissionEvent")
					if ev then
						ev:FireAllClients({ text = "Relay shield down. Plant the charge.", kind = "objective" })
					end
				else
					hint = string.format("Node down — %d of 3 shield nodes remaining", 3 - nodesBreached)
				end
				publish()
			end
			return
		end
		-- beacon re-sync complete: the capture resumes
		if templateId == "DEFEND_BEACON" and tag == "beaconresync" then
			beaconResyncPending = false
			beaconResynced = true
			if ZoneControlService then
				ZoneControlService.pause("beacon", false)
			end
			local terminal = objective and objective:FindFirstChild("Terminal")
			if terminal then
				terminal:SetAttribute("InteractPrompt", "Beacon")
			end
			hint = "Beacon re-synced — capture resumed, hold the perimeter"
			publish()
			return
		end
		if templateId == "RECOVERY_ARCHIVE" and archiveStage == 2 then
			archiveStage = 3
			workspace:SetAttribute("GF_ArchiveStage", 3)
			-- the console spill decrypts the archive canister: it materialises as a carry object
			-- and the extraction is the walk back to the landing zone, not a second console click
			local intel = objective and objective:FindFirstChild("IntelCase")
			if intel and intel:IsA("BasePart") then
				intel.Transparency = 0
				caseRegister("archivecase", intel.Position, {
					part = intel,
					label = "Archive canister",
					prompt = ocfg().carryPrompt or "Take the archive canister",
					color = Color3.fromRGB(230, 200, 120),
					destType = "lz",
					onPickup = function()
						showDeliveryRing()
						progress = 0.6
						hint = "Carry the archive canister to the landing zone"
						publish()
						missionEvent("Archive secured. Get it to the landing zone.", "objective")
					end,
					onDeliver = function()
						if deliveryRing then
							deliveryRing:Destroy()
							deliveryRing = nil
						end
						ObjectiveService.complete()
					end,
				})
			end
			local terminal = objective and objective:FindFirstChild("Terminal")
			if terminal then
				terminal:SetAttribute("GFInteract", "None")
				terminal:SetAttribute("InteractPrompt", "Console broken")
			end
			hint = "Take the archive canister"
			publish()
		end
	end

	-- Screen watchdog. The hardlight screen is normally driven by the hold itself, but the capture hook
	-- GF_ForceConsoleScreen has to reach the real module instance (a tool VM gets its own copy, so it
	-- cannot raise it from outside).
	task.spawn(function()
		while true do
			task.wait(0.5)
			local busy = false
			for _ in pairs(holding) do
				busy = true
				break
			end
			local force = workspace:GetAttribute("GF_ForceConsoleScreen") == true
			if busy or force then
				ObjectiveService.showScreen(true)
			elseif workspace:GetAttribute("GF_ConsoleScreen") == true then
				ObjectiveService.showScreen(false)
			end
		end
	end)
	local r = remote("InteractRequest")
	if r then
		r.OnServerEvent:Connect(function(player, target)
			if target == "Relay" or target == "ShieldNode" or target == "BlackBox" or target == "Beacon" or target == "ConquestConsole" or target == "ConquestNode" or target == "UplinkDish" or target == "UplinkConfirm" or target == "PowerRestore" or target == "PowerStabilise" or target == "ArsenalPad" or target == "ArchiveConsole" or target == "MissionCase" or target == "IntelConsole" or target == "ConvoySled" then
				if not require(script.Parent.NetGuard).allow(player, "interact") then
					return
				end
				ObjectiveService.request(player, target)
			end
		end)
	end
end

-- Re-publish the current objective state to one player (HUD paint on deploy, and after any reconnect).
function ObjectiveService.publish(player: Player?)
	local spot, label = currentMarker()
	local payload = { progress = progress, complete = complete, template = templateId, marker = complete and nil or (spot and { position = spot, label = label } or nil) }
	local r = ReplicatedStorage.GF.Remotes:FindFirstChild("ObjectiveProgress")
	if not r then
		return
	end
	if player then
		r:FireClient(player, payload)
	else
		r:FireAllClients(payload)
	end
end

-- GF_RelayDist: nearest live player distance to the relay, published once a second for tutorial hints.
task.spawn(function()
	while true do
		task.wait(1)
		local relay = ObjectiveService.getRelay and ObjectiveService.getRelay()
		if relay and relay.PrimaryPart then
			local best = 999
			for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
				local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if root then
					best = math.min(best, ((root :: BasePart).Position - relay.PrimaryPart.Position).Magnitude)
				end
			end
			workspace:SetAttribute("GF_RelayDist", best)
		end
	end
end)

-- S08-012 objective briefing: Voss narrates the objective at mission start and every stage
-- transition — what the squad is doing, how far along they are, and where the next marker is.
-- Progress publishes continuously so the HUD never leaves players guessing.
function ObjectiveService.publishBriefing(stage: string, progress: number, markerPos: Vector3?)
	workspace:SetAttribute("GF_ObjectiveStage", stage)
	workspace:SetAttribute("GF_ObjectiveProgress", math.floor(progress * 100))
	if markerPos then
		workspace:SetAttribute("GF_NextMarkerX", math.floor(markerPos.X))
		workspace:SetAttribute("GF_NextMarkerZ", math.floor(markerPos.Z))
	end
	workspace:SetAttribute("GF_BriefingUpdated", os.clock())
end

return ObjectiveService
