--!strict
-- Environmental interaction sites (Counteroffensive contract revision — formerly the optional
-- objective system). These are NOT objectives: no contract states, no reward-ledger events, no
-- HUD/debrief framing. They are informal tactical texture — small sites near the fight whose
-- interaction applies an in-mission effect: relay cuts future reinforcements x0.75, generator
-- disables linked turrets/field barriers, supply outpost grants shared resources. In operation
-- mode this service does not spawn at all: the operation DAG carries its own supply cache node
-- and relay/generator prerequisites, and double-spawning was a latent bug.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local OptionalService = {}

local DISCOVERY_RADIUS = 80
local MAX_SITES = 2

type Site = {
	part: BasePart,
	siteType: string,
	discovered: boolean,
	completed: boolean,
	id: string,
}

local sites: { Site } = {}
local heartbeat: RBXScriptConnection? = nil
local siteCounter = 0

local SITE_TYPES = { "relay", "generator", "supply" }

local function publish()
	local discovered = {}
	for _, site in ipairs(sites) do
		if site.discovered and not site.completed then
			table.insert(discovered, string.format("%s@%.0f,%.0f", site.siteType, site.part.Position.X, site.part.Position.Z))
		end
	end
	workspace:SetAttribute("GF_OptionalSites", table.concat(discovered, ";"))
	local completedCount = 0
	for _, site in ipairs(sites) do
		if site.completed then
			completedCount += 1
		end
	end
	workspace:SetAttribute("GF_OptionalsCompleted", completedCount)
end

-- The relay's authored effect: future reinforcement refills run at x0.75 (S08-045).
local function applyRelayCut()
	workspace:SetAttribute("GF_ReinforcementCut", 0.75)
end

-- The generator's authored effect: linked turrets and field barriers power down. Anything tagged
-- GFTurret/GFFieldBarrier in the mission space is disabled (damage output stops, barrier collision
-- drops) - a no-op set when the mission spawned none.
local function applyGeneratorDisable()
	local disabled = 0
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:GetAttribute("GFTurret") == true then
			inst:SetAttribute("Disabled", true)
			disabled += 1
		elseif inst:GetAttribute("GFFieldBarrier") == true and inst:IsA("BasePart") then
			inst.CanCollide = false
			inst.Transparency = 0.85
			disabled += 1
		end
	end
	workspace:SetAttribute("GF_GeneratorDisabled", disabled)
end

-- The supply outpost's authored effect: a shared resource grant into the squad pool.
local function applySupplyGrant()
	local SquadService = require(ServerScriptService.GF.Services.SquadService)
	SquadService.add("scrap", 6)
	SquadService.add("energyCells", 2)
	workspace:SetAttribute("GF_SupplyOutpostGrant", "scrap6 cells2")
end

local function complete(site: Site, player: Player?)
	if site.completed then
		return
	end
	site.completed = true
	if site.siteType == "relay" then
		applyRelayCut()
	elseif site.siteType == "generator" then
		applyGeneratorDisable()
	elseif site.siteType == "supply" then
		applySupplyGrant()
	end
	-- no reward-ledger event: environmental interactions are not objectives and pay nothing
	-- (Counteroffensive contract revision — and the legacy append used a mismatched event key
	-- against a ledger settlement never read, so it was doubly dead)
	if site.part.Parent then
		local prompt = site.part:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end
		site.part.Color = Color3.fromRGB(90, 200, 130)
	end
	workspace:SetAttribute("GF_OptionalCompleted", site.siteType)
	publish()
end

local function spawnSite(siteType: string, position: Vector3): Site
	siteCounter += 1
	local part = Instance.new("Part")
	part.Name = "OptionalSite_" .. siteType
	part.Size = Vector3.new(4, 5, 4)
	part.Anchored = true
	part.CanCollide = true
	part.Position = position + Vector3.new(0, 2.5, 0)
	part.Color = siteType == "relay" and Color3.fromRGB(200, 90, 90)
		or siteType == "generator" and Color3.fromRGB(220, 180, 80)
		or Color3.fromRGB(110, 160, 220)
	part.Material = Enum.Material.Metal
	part:SetAttribute("GFOptionalSite", siteType)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = siteType == "relay" and "Sabotage relay" or siteType == "generator" and "Disable generator" or "Collect supplies"
	-- environmental framing, not an objective: no "Optional:" contract label
	prompt.ObjectText = siteType == "relay" and "Ascendancy relay" or siteType == "generator" and "Field generator" or "Supply cache"
	prompt.HoldDuration = 1.5
	prompt.MaxActivationDistance = 9
	prompt.Parent = part

	part.Parent = workspace
	local site: Site = { part = part, siteType = siteType, discovered = false, completed = false, id = siteType .. siteCounter }
	prompt.Triggered:Connect(function(player)
		complete(site, player)
	end)
	return site
end

local function groundAt(position: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	local hit = workspace:Raycast(position + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), params)
	if hit then
		return hit.Position
	end
	return nil
end

-- Sites ring the fight: placed 60-110 studs off the squad insertion in spread directions so they are
-- nearby but never on the primary path.
function OptionalService.placeSites(centre: Vector3)
	OptionalService.clear()
	workspace:SetAttribute("GF_ReinforcementCut", nil)
	local rng = Random.new()
	local count = MAX_SITES
	local shuffled = table.clone(SITE_TYPES)
	-- rotate which types appear so successive missions differ
	local offset = rng:NextInteger(1, #SITE_TYPES)
	local placed = 0
	for i = 1, math.min(count, #shuffled) do
		local siteType = shuffled[((i + offset - 1) % #shuffled) + 1]
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local dist = rng:NextNumber(60, 110)
		local candidate = centre + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local ground = groundAt(candidate)
		if ground then
			table.insert(sites, spawnSite(siteType, ground))
			placed += 1
		end
	end
	workspace:SetAttribute("GF_OptionalSitesPlaced", placed)
	publish()
	return placed
end

function OptionalService.clear()
	for _, site in ipairs(sites) do
		if site.part.Parent then
			site.part:Destroy()
		end
	end
	sites = {}
	workspace:SetAttribute("GF_OptionalSites", "")
	workspace:SetAttribute("GF_OptionalsCompleted", 0)
	workspace:SetAttribute("GF_OptionalSitesPlaced", 0)
end

local function tick()
	-- proximity discovery: any live player inside 80 studs reveals the site squad-wide
	for _, site in ipairs(sites) do
		if not site.discovered and site.part.Parent then
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - site.part.Position).Magnitude <= DISCOVERY_RADIUS then
					site.discovered = true
					workspace:SetAttribute("GF_OptionalDiscovered", site.siteType)
					publish()
					break
				end
			end
		end
	end
end

function OptionalService.start()
	workspace:GetAttributeChangedSignal("GF_InMission"):Connect(function()
		if workspace:GetAttribute("GF_InMission") == true then
			-- operation mode carries its own DAG supply cache and relay/generator prerequisites —
			-- spawning here too was a latent double-spawn bug. legacy-mode missions only.
			if workspace:GetAttribute("GF_OperationMode") == true then
				return
			end
			-- place around the squad insertion once deployment lands
			task.delay(2, function()
				local lz = workspace:GetAttribute("GF_LZ")
				local centre = nil
				for _, player in ipairs(Players:GetPlayers()) do
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root then
						centre = root.Position
						break
					end
				end
				if centre then
					OptionalService.placeSites(centre)
				end
			end)
		else
			OptionalService.clear()
		end
	end)
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(tick)
	end
end

function OptionalService.countSites(): number
	return #sites
end

return OptionalService
