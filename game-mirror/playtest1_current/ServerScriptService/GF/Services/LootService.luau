--!strict
-- Physical salvage pickups, collected by proximity (identical on touch, pad and PC).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SquadService = require(script.Parent.SquadService)
local Enemies = require(ReplicatedStorage.GF.Shared.Configs.Enemies)
local RewardSources = require(ReplicatedStorage.GF.Shared.Configs.RewardSources)

local LootService = {}
local MAX_ACTIVE = 40
local COLLECT_RADIUS = 7
local LIFETIME = 90

local COLORS = {
	ammo = Color3.fromRGB(255, 214, 130),
	grenade = Color3.fromRGB(140, 220, 140),
	scrap = Color3.fromRGB(150, 160, 175),
	energyCells = Color3.fromRGB(255, 176, 68),
	militaryTechnology = Color3.fromRGB(120, 210, 255),
}

type Pickup = { part: BasePart, kind: string, amount: number, bornAt: number }
local pickups: { Pickup } = {}
local watched: { [Model]: boolean } = {}
local heartbeat: RBXScriptConnection? = nil

local function spawnPickup(kind: string, position: Vector3, amount: number): BasePart?
	if amount <= 0 or #pickups >= MAX_ACTIVE then
		return nil
	end
	-- A salvage find has to look like a thing you could pick up and be findable at night, so it is a
	-- two-part canister with a lit cap, a faint ground glow and a slow bob, not a floating ball.
	local base = position + Vector3.new(0, 1.6, 0)
	local part = Instance.new("Part")
	part.Name = "Salvage_" .. kind
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(2.6, 1.9, 1.9)
	part.Material = Enum.Material.Metal
	part.Color = Color3.fromRGB(46, 52, 62)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(base) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = workspace
	local cap = Instance.new("Part")
	cap.Name = "Cap"
	cap.Shape = Enum.PartType.Cylinder
	cap.Size = Vector3.new(0.35, 1.95, 1.95)
	cap.Material = Enum.Material.Neon
	cap.Color = COLORS[kind] or Color3.new(1, 1, 1)
	cap.Anchored = true
	cap.CanCollide = false
	cap.CanQuery = false
	cap.CanTouch = false
	cap.CFrame = CFrame.new(base + Vector3.new(1.45, 0, 0)) * CFrame.Angles(0, 0, math.rad(90))
	cap.Parent = part
	local glow = Instance.new("PointLight")
	glow.Color = COLORS[kind] or Color3.new(1, 1, 1)
	glow.Brightness = 1.6
	glow.Range = 16
	glow.Shadows = false
	glow.Parent = part
	part:SetAttribute("GFLoot", true)
	part:SetAttribute("LootKind", kind)
	part:SetAttribute("LootAmount", amount)
	part:SetAttribute("GFBaseY", base.Y)
	table.insert(pickups, { part = part, kind = kind, amount = amount, bornAt = os.clock() })
	return part
end

local function rollDistribution(dist: any): number
	-- §19 Bernoulli events and fixed quantities, resolved from the reward source registry.
	if type(dist) ~= "table" then
		return 0
	end
	if dist.kind == "fixed" then
		return math.max(0, math.floor(tonumber(dist.amount) or 0))
	end
	if dist.kind == "bernoulli" then
		if math.random() < (tonumber(dist.p) or 0) then
			return math.max(0, math.floor(tonumber(dist.amount) or 0))
		end
	end
	return 0
end

local function dropFrom(defId: string, position: Vector3)
	local def = Enemies.get(defId)
	if not def then
		return
	end
	local source = RewardSources.forEnemy(defId, def)
	local dist = source and source.ResourceQuantityDistributions or nil
	if not dist then
		return
	end
	local scrap = rollDistribution(dist.scrap)
	if scrap > 0 then
		spawnPickup("scrap", position, scrap)
	end
	local cells = rollDistribution(dist.energyCells)
	if cells > 0 then
		spawnPickup("energyCells", position + Vector3.new(1.4, 0, 0.6), cells)
	end
	local tech = rollDistribution(dist.militaryTechnology)
	if tech > 0 then
		spawnPickup("militaryTechnology", position + Vector3.new(-1.4, 0, 0.6), tech)
	end
end

local function collect(index: number, player: Player)
	local pickup = pickups[index]
	if not pickup then
		return
	end
	table.remove(pickups, index)
	-- Personal pickups (S08-048): ammo refills the collector's own reserve by 20% of the catalog
	-- reserve for their current weapon; grenade grants +1 charge capped at the authored max. Neither
	-- touches the shared squad pool.
	if pickup.kind == "ammo" or pickup.kind == "grenade" then
		local State = require(game:GetService("ServerScriptService").GF.Services.State)
		local Weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
		local state = State.get(player)
		if pickup.kind == "ammo" and state then
			local weapon = Weapons.get(state.weaponId or "AR01")
			if weapon then
				local catalogReserve = tonumber(weapon.reserve) or 0
				local grant = math.max(1, math.floor(catalogReserve * 0.2 + 0.5))
				local cap = math.floor(catalogReserve * 1.6)
				local before = tonumber(state.reserve) or 0
				state.reserve = math.min(cap, before + grant)
				local ev = ReplicatedStorage.GF.Remotes:FindFirstChild("AmmoUpdated")
				if ev then
					ev:FireClient(player, { ammo = state.ammo or 0, magazine = weapon.magazine, reserve = state.reserve })
				end
				workspace:SetAttribute("GF_AmmoPickup", string.format("%s %d->%d (+%d)", player.Name, before, state.reserve, grant))
			end
		elseif pickup.kind == "grenade" then
			local Economy = require(ReplicatedStorage.GF.Shared.Configs.Economy)
			local maxCharges = 3
			local before = tonumber(player:GetAttribute("GrenadeCharges")) or maxCharges
			local after = math.min(maxCharges, before + 1)
			player:SetAttribute("GrenadeCharges", after)
			workspace:SetAttribute("GF_GrenadePickup", string.format("%s %d->%d", player.Name, before, after))
		end
	else
		local ok = SquadService.add(pickup.kind, pickup.amount)
		if not ok then
			warn("[GF] loot add rejected: " .. tostring(pickup.kind) .. " x" .. tostring(pickup.amount))
		end
	end
	local fx = ReplicatedStorage.GF.Remotes:FindFirstChild("LootCollected")
	if fx then
		fx:FireClient(player, pickup.kind, pickup.amount, pickup.part.Position)
	end
	-- discovery feedback: a short confirm tone at the pickup and a recorded find, so a salvage
	-- pickup is something that happened rather than a sphere that vanished.
	if pickup.part.Parent then
		local host = Instance.new("Part")
		host.Name = "SalvageChime"
		host.Size = Vector3.new(1, 1, 1)
		host.Transparency = 1
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.Position = pickup.part.Position
		host.Parent = workspace
		local chime = Instance.new("Sound")
		chime.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		chime.Volume = 0.6
		chime.PlaybackSpeed = 1.15
		chime.Parent = host
		chime:Play()
		local lamp = Instance.new("PointLight")
		lamp.Color = COLORS[pickup.kind] or Color3.new(1, 1, 1)
		lamp.Brightness = 8
		lamp.Range = 22
		lamp.Parent = host
		game:GetService("TweenService"):Create(lamp, TweenInfo.new(0.9), { Brightness = 0 }):Play()
		task.delay(1.2, function() if host.Parent then host:Destroy() end end)
		pickup.part:Destroy()
	end
	local dbg = workspace:FindFirstChild("GFDebug")
	if dbg then
		dbg:SetAttribute("SalvageFound", (dbg:GetAttribute("SalvageFound") or 0) + 1)
		dbg:SetAttribute("LastSalvageKind", pickup.kind)
		dbg:SetAttribute("LastSalvageAmount", pickup.amount)
	end
end

local function tick()
	local now = os.clock()
	for i = #pickups, 1, -1 do
		local pickup = pickups[i]
		if not pickup.part.Parent then
			table.remove(pickups, i)
		elseif now - pickup.bornAt > LIFETIME then
			pickup.part:Destroy()
			table.remove(pickups, i)
		else
			-- cheap bob and spin: the heartbeat already walks every pickup, so this costs no new loop
			local baseY = pickup.part:GetAttribute("GFBaseY")
			if typeof(baseY) == "number" then
				local bob = math.sin(now * 1.8 + pickup.bornAt) * 0.22
				pickup.part.CFrame = CFrame.new(Vector3.new(pickup.part.Position.X, baseY + bob, pickup.part.Position.Z))
			end
			local pos = pickup.part.Position
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (root.Position - pos).Magnitude <= COLLECT_RADIUS then
					collect(i, player)
					break
				end
			end
		end
	end
end

local function watch(model: Model)
	if watched[model] then
		return
	end
	watched[model] = true
	local defId = model:GetAttribute("EnemyId")
	model:GetAttributeChangedSignal("Dead"):Connect(function()
		if model:GetAttribute("Dead") ~= true then
			return
		end
		local root = model.PrimaryPart
		local position = root and root.Position or model:GetPivot().Position
		if defId then
			dropFrom(defId, position)
		end
		-- personal resupply drops (S08-048): chance-based, independent of the salvage roll
		if math.random() < 0.20 then
			spawnPickup("ammo", position + Vector3.new(0.8, 0, -0.8), 1)
		end
		if math.random() < 0.08 then
			spawnPickup("grenade", position + Vector3.new(-0.8, 0, 0.8), 1)
		end
		watched[model] = nil
	end)
end

-- ---------------------------------------------------------------------------
-- INSTALLATION LOOT (economy spec §16, Stage 3): installations reward composition matching
-- their purpose. Zero-touch integration: existing decorative crate props inside MissionSite
-- models are converted into lootable containers — positions come from the site layouts that
-- already exist, no edits to MissionSites. If crate naming changes upstream the conversion
-- simply finds nothing and degrades without errors. Visual refinement of the containers
-- themselves is Stage 8 territory; for now a warm glow marks them as interactive.
-- ---------------------------------------------------------------------------
local CONTAINER_COLLECT_RADIUS = 8
local lootedContainers: { [BasePart]: boolean } = {}
local convertedSites: { [Model]: boolean } = {}
local activeContainers: { { part: BasePart, siteType: string } } = {}

local function convertSiteCrates(siteModel: Model)
	if convertedSites[siteModel] then
		return
	end
	convertedSites[siteModel] = true
	local siteType = siteModel:GetAttribute("SiteType")
	if type(siteType) ~= "string" then
		return
	end
	local source = RewardSources.forInstallation(siteType)
	if not source or (source._cratesPerSite or 0) <= 0 then
		return
	end
	-- collect decorative crate parts: layout names end in CrateX<level> (SupplyCrateA1, StrongholdCrateB2...)
	local crates = {}
	for _, desc in siteModel:GetDescendants() do
		if desc:IsA("BasePart") and string.match(desc.Name, "Crate%l?%d+$") then
			table.insert(crates, desc)
		end
	end
	table.sort(crates, function(a, b) return a.Name < b.Name end)
	local converted = 0
	for _, crate in crates do
		if converted >= source._cratesPerSite then
			break
		end
		-- only convert ground-level crates (level suffix 1) so every container is reachable
		if not string.match(crate.Name, "1$") then
			continue
		end
		converted += 1
		crate:SetAttribute("GFLootContainer", true)
		crate:SetAttribute("SiteType", siteType)
		local lamp = Instance.new("PointLight")
		lamp.Color = Color3.fromRGB(255, 200, 110)
		lamp.Brightness = 1.4
		lamp.Range = 12
		lamp.Parent = crate
		table.insert(activeContainers, { part = crate, siteType = siteType })
	end
	if converted > 0 then
		workspace:SetAttribute("GF_InstallationLoot", string.format("%s:%d", siteType, converted))
	end
end

local function scanSites()
	for _, child in workspace:GetChildren() do
		if child:IsA("Model") and string.match(child.Name, "^MissionSite_") then
			convertSiteCrates(child)
		end
	end
end

local function collectContainer(index: number, player: Player)
	local container = activeContainers[index]
	if not container or lootedContainers[container.part] then
		return
	end
	lootedContainers[container.part] = true
	table.remove(activeContainers, index)
	local source = RewardSources.forInstallation(container.siteType)
	if not source then
		return
	end
	-- composition rolls feed the shared squad pool exactly like enemy salvage (spec §15)
	local dist = source.ResourceQuantityDistributions
	local yields = {}
	for resource, d in pairs(dist) do
		local amount = rollDistribution(d)
		if amount > 0 then
			yields[resource] = amount
		end
	end
	for resource, amount in pairs(yields) do
		SquadService.add(resource, amount)
	end
	-- cache opportunity per container (§16 installation cache composition)
	local cacheGranted = false
	if math.random() < (source.CacheProbability or 0) then
		local ok, CacheService = pcall(function()
			return require(script.Parent.CacheService)
		end)
		if ok and CacheService then
			local tier = "Common"
			pcall(function()
				local mission = require(script.Parent.State).getMission()
				local diff = mission and mission.difficulty or "Normal"
				tier = ({ Easy = "Common", Normal = "Rare", Hard = "Epic", Extreme = "Legendary" })[diff] or "Rare"
			end)
			cacheGranted = CacheService.grantToInventory(player, tier, container.siteType) == true
		end
	end
	-- visual feedback: the container dims and its lamp dies — opened, not vanished
	local lamp = container.part:FindFirstChildOfClass("PointLight")
	if lamp then
		lamp.Brightness = 0
	end
	container.part.Color = Color3.fromRGB(70, 64, 56)
	local parts = {}
	for resource, amount in pairs(yields) do
		table.insert(parts, resource .. " x" .. amount)
	end
	if cacheGranted then
		table.insert(parts, "cache")
	end
	workspace:SetAttribute("GF_ContainerLooted", string.format("%s:%s", container.siteType, table.concat(parts, ",")))
	local fx = ReplicatedStorage.GF.Remotes:FindFirstChild("LootCollected")
	if fx then
		fx:FireClient(player, "container:" .. container.siteType, 1, container.part.Position)
	end
end

local function containerTick()
	for i = #activeContainers, 1, -1 do
		local container = activeContainers[i]
		if not container.part.Parent then
			table.remove(activeContainers, i)
		else
			local pos = container.part.Position
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (root.Position - pos).Magnitude <= CONTAINER_COLLECT_RADIUS then
					collectContainer(i, player)
					break
				end
			end
		end
	end
end

function LootService.start()
	local folder = workspace:FindFirstChild("ActiveActors")
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") and child:GetAttribute("GFEnemy") then
				watch(child)
			end
		end
		folder.ChildAdded:Connect(function(child)
			if child:IsA("Model") and child:GetAttribute("GFEnemy") then
				watch(child)
			end
		end)
	end
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(function()
			tick()
			containerTick()
		end)
	end
	-- installations stream in with the mission; scan now and then rescan periodically
	task.defer(scanSites)
	task.spawn(function()
		while true do
			task.wait(5)
			scanSites()
		end
	end)
end

function LootService.spawnPickup(kind: string, position: Vector3, amount: number)
	return spawnPickup(kind, position, amount)
end

function LootService.activeCount(): number
	return #pickups
end

function LootService.clearAll()
	for i = #pickups, 1, -1 do
		if pickups[i].part.Parent then
			pickups[i].part:Destroy()
		end
		table.remove(pickups, i)
	end
end

-- requiring this module is enough; ordering cannot disable pickups
task.defer(function()
	pcall(function()
		LootService.start()
	end)
end)

-- S10-030 deterministic salvage: each enemy rolls salvage once from a seeded RNG keyed on its
-- spawn id — the same enemy always yields the same salvage, no re-roll exploitation, no
-- variance between sessions for the same generated world.
function LootService.seededSalvage(enemySeed: number, enemyKind: string): (number, number)
	local rng = Random.new(enemySeed)
	local scrap = 0
	local tech = 0
	if enemyKind == "infantry" then
		-- normal infantry: 45% 1 scrap, rare tech trace
		if rng:NextNumber() < 0.45 then
			scrap = 1
		end
		if rng:NextNumber() < 0.02 then
			tech = 1
		end
	elseif enemyKind == "elite" then
		-- elites: guaranteed scrap, meaningful tech chance
		scrap = rng:NextInteger(1, 2)
		if rng:NextNumber() < 0.15 then
			tech = 1
		end
	elseif enemyKind == "boss" then
		scrap = rng:NextInteger(8, 12)
		tech = rng:NextInteger(2, 4)
	end
	return scrap, tech
end

-- S09-038 blueprint pity: the pity counter advances only for a qualifying boss kill followed by
-- the player's own successful extraction — dying after the kill or skipping extraction does not
-- bank progress. The pity is earned, not merely witnessed.
-- S06-072 pity guarantee: at 5 qualifying extracted boss kills the blueprint is guaranteed.
-- Earlier drops remain possible through the normal roll — the pity is a floor, not a ceiling.
LootService.PITY_THRESHOLD = 5

function LootService.blueprintPity(plr: Player, bossKilled: boolean, extracted: boolean): number
	local pity = plr:GetAttribute("GF_BlueprintPity") or 0
	if bossKilled and extracted then
		pity += 1
		plr:SetAttribute("GF_BlueprintPity", pity)
		if pity >= LootService.PITY_THRESHOLD then
			plr:SetAttribute("GF_BlueprintGuaranteed", true)
		end
	end
	return pity
end

-- S09-042 pending-save honesty: the UI never reports committed while a save is in flight — the
-- pending state shows honestly so a crash never reads as data loss.
function LootService.saveState(plr: Player): string
	if plr:GetAttribute("GF_SavePending") then
		return "pending"
	end
	return "committed"
end

return LootService

