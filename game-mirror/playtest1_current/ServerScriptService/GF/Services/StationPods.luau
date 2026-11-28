--!nonstrict
-- StationPods — the four enterable drop pods, the physical front door of the deploy loop.
-- Owner reference: the HD2-style lobby where you step into a pod to host a squad and the
-- mission select opens. Until now the only way into the deploy surface was an unlabeled
-- terminal prompt; the pods make the loop tangible: walk up, enter, you are seated for
-- deployment, the war table opens.
--
-- server owns occupancy (GF_PodIndex on the player is the replicated seat token); the client
-- watches the attribute and opens the deploy surface. the pods are station furniture built
-- in the same part language as StationArt's drop-pod dressing, scaled for one operator.

local Players = game:GetService("Players")

local StationPods = {}

-- hull palette v2 (owner visual review: white plastic read as refrigerators). deep gunmetal
-- mass with lighter armor paneling — the amber stripe carries the identity.
local HULL = Color3.fromRGB(64, 72, 84)
local HULL_DARK = Color3.fromRGB(34, 40, 50)
local PLATE = Color3.fromRGB(96, 106, 118)
local AMBER = Color3.fromRGB(232, 176, 96)
local CYAN = Color3.fromRGB(88, 200, 240)
local INTERIOR = Color3.fromRGB(28, 34, 42)

local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.CastShadow = true
	p.Parent = parent
	return p
end

-- one pod: a stood-upright drop pod with an open hatch facing `lookCF`'s -Z. interior fits
-- one operator standing. the hatch opening is the full front face.
local function buildPod(parent, index, cf)
	local model = Instance.new("Model")
	model.Name = "DropPod" .. index
	model.Parent = parent

	-- cradle: heavy octagonal-ish base ring the pod sits in
	part(model, "Cradle", Vector3.new(8.6, 1.2, 8.6), cf * CFrame.new(0, 0.6, 0), PLATE)
	part(model, "CradleTrim", Vector3.new(9.4, 0.4, 9.4), cf * CFrame.new(0, 0.2, 0), HULL_DARK)

	-- hull: rear shell + side cheeks, open front. interior cavity ~5 wide, 7 deep, 8 tall.
	local hullY = 1.2
	part(model, "HullBack", Vector3.new(7.4, 9.6, 1.2), cf * CFrame.new(0, hullY + 4.8, 3.1), HULL)
	part(model, "HullLeft", Vector3.new(1.2, 9.6, 7.4), cf * CFrame.new(-3.1, hullY + 4.8, 0), HULL)
	part(model, "HullRight", Vector3.new(1.2, 9.6, 7.4), cf * CFrame.new(3.1, hullY + 4.8, 0), HULL)
	part(model, "HullRoof", Vector3.new(7.4, 1.2, 7.4), cf * CFrame.new(0, hullY + 9.6, 0), HULL)
	part(model, "HullFloor", Vector3.new(7.4, 0.6, 7.4), cf * CFrame.new(0, hullY + 0.3, 0), INTERIOR, Enum.Material.DiamondPlate)

	-- nose cap: the pod's tapered crown
	part(model, "Nose", Vector3.new(5.6, 2.4, 5.6), cf * CFrame.new(0, hullY + 11.9, 0), PLATE)
	part(model, "NoseTip", Vector3.new(2.8, 1.2, 2.8), cf * CFrame.new(0, hullY + 13.4, 0), HULL_DARK)

	-- hatch frame around the open mouth + threshold step
	part(model, "HatchLintel", Vector3.new(7.4, 1.0, 0.8), cf * CFrame.new(0, hullY + 9.1, -3.5), PLATE)
	part(model, "HatchStep", Vector3.new(5.6, 0.5, 1.8), cf * CFrame.new(0, hullY + 0.25, -4.4), PLATE, Enum.Material.DiamondPlate)

	-- identity stripe + status lamp — amber when open, cyan when seated
	part(model, "Stripe", Vector3.new(7.5, 0.5, 7.5), cf * CFrame.new(0, hullY + 7.6, 0), AMBER, Enum.Material.Neon).Transparency = 0.15
	local lamp = part(model, "StatusLamp", Vector3.new(1.6, 0.4, 0.4), cf * CFrame.new(0, hullY + 9.9, -3.6), AMBER, Enum.Material.Neon)
	lamp.CanCollide = false

	-- interior fitout: backwall panel, seat cushion, dim utility light
	part(model, "BackPanel", Vector3.new(4.6, 5.4, 0.3), cf * CFrame.new(0, hullY + 4.4, 2.4), INTERIOR, Enum.Material.SmoothPlastic).CanCollide = false
	local glow = part(model, "InteriorGlow", Vector3.new(3.4, 0.2, 0.2), cf * CFrame.new(0, hullY + 7.2, 2.3), CYAN, Enum.Material.Neon)
	glow.CanCollide = false
	glow.Transparency = 0.25

	-- number plate above the mouth
	local plate = Instance.new("BillboardGui")
	plate.Name = "PodPlate"
	plate.Size = UDim2.fromOffset(150, 42)
	plate.StudsOffset = Vector3.new(0, 13.8, 0)
	plate.AlwaysOnTop = false
	local plateText = Instance.new("TextLabel")
	plateText.BackgroundTransparency = 0.3
	plateText.BackgroundColor3 = Color3.fromRGB(6, 10, 14)
	plateText.Size = UDim2.fromScale(1, 1)
	plateText.Font = Enum.Font.GothamBold
	plateText.TextSize = 17
	plateText.TextColor3 = AMBER
	plateText.Text = string.format("%02d · OPEN", index)
	plateText.Parent = plate
	local host = part(model, "PlateHost", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(0, hullY, 0), HULL_DARK)
	host.Transparency = 1
	host.CanCollide = false
	plate.Parent = host

	-- the enter prompt rides the hatch lintel
	local promptHost = model:FindFirstChild("HatchLintel")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Enter Pod"
	prompt.ObjectText = string.format("Drop Pod %02d", index)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = promptHost

	return {
		model = model,
		cf = cf,
		prompt = prompt,
		plateText = plateText,
		lamp = lamp,
		stripe = model:FindFirstChild("Stripe"),
		index = index,
	}
end

function StationPods.start()
	local station = workspace:WaitForChild("Station", 30)
	if not station then
		return
	end
	if station:FindFirstChild("DropPod1") then
		return
	end
	local base = station:WaitForChild("WarTableBase", 20)
	if not base or not base:IsA("BasePart") then
		return
	end

	-- a row of four pods flanking the war-table approach, hatches facing the concourse so the
	-- operator walks up the threshold and turns in. spacing clears the table's collision base.
	local pods = {}
	local podsFolder = Instance.new("Folder")
	podsFolder.Name = "DropPods"
	podsFolder.Parent = station
	for i = 1, 4 do
		local x = (i - 2.5) * 11
		local podCF = base.CFrame * CFrame.new(x, -base.Size.Y * 0.5, 26) * CFrame.Angles(0, math.pi, 0)
		pods[i] = buildPod(podsFolder, i, podCF)
	end

	local occupants = {}

	local function releasePod(player)
		local idx = player:GetAttribute("GF_PodIndex")
		if type(idx) ~= "number" then return end
		local pod = pods[idx]
		if pod and occupants[idx] == player then
			occupants[idx] = nil
			pod.plateText.Text = string.format("%02d · OPEN", idx)
			pod.plateText.TextColor3 = AMBER
			pod.lamp.Color = AMBER
			pod.prompt.ActionText = "Enter Pod"
		end
		player:SetAttribute("GF_PodIndex", nil)
	end

	local function occupyPod(player, idx)
		local pod = pods[idx]
		if not pod then return end
		releasePod(player) -- one seat per operator, always
		occupants[idx] = player
		player:SetAttribute("GF_PodIndex", idx)
		pod.plateText.Text = string.format("%02d · %s", idx, string.upper(player.DisplayName))
		pod.plateText.TextColor3 = CYAN
		pod.lamp.Color = CYAN
		pod.prompt.ActionText = "Exit Pod"
	end

	for i, pod in ipairs(pods) do
		pod.prompt.Triggered:Connect(function(player)
			if occupants[i] == player then
				releasePod(player)
			elseif occupants[i] == nil then
				occupyPod(player, i)
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		releasePod(player)
	end)

	print("[GF] station pods online: 4 drop pods ready for boarding")
end

return StationPods
