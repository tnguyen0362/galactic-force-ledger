--!nonstrict
-- Minimap. The server publishes a 16x16 height field and a marker list as workspace attributes
-- (GF_MapMeta / GF_MapHeights / GF_MapMarkers); nothing drew them before this.
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local RADIUS = 78
local gui = Instance.new("ScreenGui")
gui.Name = "GF_Minimap"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 4
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("CanvasGroup")
frame.Size = UDim2.fromOffset(RADIUS * 2, RADIUS * 2)
frame.AnchorPoint = Vector2.new(1, 0)
frame.Position = UDim2.new(1, -14, 0, 12)
frame.BackgroundColor3 = Color3.fromRGB(6, 12, 18)
frame.BackgroundTransparency = 1
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.GroupTransparency = 0
frame.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)
corner.Parent = frame

local disc = Instance.new("Frame")
disc.Name = "Disc"
disc.Size = UDim2.fromOffset(RADIUS * 2, RADIUS * 2)
disc.BackgroundColor3 = Color3.fromRGB(8, 14, 20)
disc.BackgroundTransparency = 0.15
disc.BorderSizePixel = 2
disc.BorderColor3 = Color3.fromRGB(70, 110, 140)
disc.Parent = frame
local discCorner = Instance.new("UICorner")
discCorner.CornerRadius = UDim.new(0.5, 0)
discCorner.Parent = disc

local field = Instance.new("Frame")
field.Name = "Field"
field.Size = UDim2.fromOffset(RADIUS * 2, RADIUS * 2)
field.AnchorPoint = Vector2.new(0.5, 0.5)
field.Position = UDim2.fromScale(0.5, 0.5)
field.BackgroundTransparency = 1
field.Parent = frame

local north = Instance.new("TextLabel")
north.Text = "N"
north.Size = UDim2.fromOffset(14, 14)
north.BackgroundTransparency = 1
north.Font = Enum.Font.GothamBold
north.TextSize = 12
north.TextColor3 = Color3.fromRGB(255, 220, 140)
north.Parent = frame

local arrow = Instance.new("Frame")
arrow.Size = UDim2.fromOffset(6, 14)
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.Position = UDim2.fromScale(0.5, 0.5)
arrow.BackgroundColor3 = Color3.fromRGB(240, 250, 255)
arrow.BorderSizePixel = 0
arrow.Parent = frame


-- Station mode: the mission radar was a blank/irrelevant disc on the concourse. Draw a compact deck
-- plan instead, with the four places a player actually needs: war table, armoury, dispatch and pod bay.
local stationLayer = Instance.new("Frame")
stationLayer.Name = "StationLayout"
stationLayer.Size = UDim2.fromOffset(RADIUS * 2, RADIUS * 2)
stationLayer.BackgroundTransparency = 1
stationLayer.Visible = false
stationLayer.Parent = field

local function stationMapOffset(x, z)
	return RADIUS + x * 0.56, RADIUS + (z - 20) * 0.56
end

local function stationBox(name, x, z, w, h, color, transparency)
	local cx, cy = stationMapOffset(x, z)
	local box = Instance.new("Frame")
	box.Name = name
	box.Size = UDim2.fromOffset(w, h)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromOffset(cx, cy)
	box.BackgroundColor3 = color
	box.BackgroundTransparency = transparency or 0.72
	box.BorderSizePixel = 1
	box.BorderColor3 = Color3.fromRGB(72, 104, 126)
	box.Parent = stationLayer
	return box
end

-- Simplified architectural footprint: central concourse, west/east alcoves, and the deployment bay.
stationBox("MainConcourse", 0, 18, 118, 48, Color3.fromRGB(24, 38, 48), 0.78)
stationBox("WestAlcove", -82, 0, 44, 64, Color3.fromRGB(32, 42, 50), 0.78)
stationBox("EastAlcove", 82, -18, 44, 58, Color3.fromRGB(32, 42, 50), 0.78)
stationBox("DeploymentBay", 0, 66, 70, 34, Color3.fromRGB(28, 48, 56), 0.74)

local stationTitle = Instance.new("TextLabel")
stationTitle.Name = "StationTitle"
stationTitle.Size = UDim2.fromOffset(70, 14)
stationTitle.AnchorPoint = Vector2.new(0.5, 1)
stationTitle.Position = UDim2.new(0.5, 0, 1, -5)
stationTitle.BackgroundTransparency = 1
stationTitle.Font = Enum.Font.GothamBold
stationTitle.TextSize = 9
stationTitle.TextColor3 = Color3.fromRGB(142, 188, 210)
stationTitle.Text = "STATION DECK"
stationTitle.Parent = stationLayer

local stationPois = {
	{ text = "WAR", x = 0, z = -34, color = Color3.fromRGB(96, 210, 255) },
	{ text = "ARM", x = -94, z = -2, color = Color3.fromRGB(255, 188, 92) },
	{ text = "DSP", x = 88, z = -28, color = Color3.fromRGB(255, 188, 92) },
	{ text = "POD", x = 0, z = 72, color = Color3.fromRGB(128, 255, 184) },
}
for _, poi in ipairs(stationPois) do
	local px, py = stationMapOffset(poi.x, poi.z)
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(7, 7)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromOffset(px, py)
	dot.BackgroundColor3 = poi.color
	dot.BorderSizePixel = 0
	dot.Parent = stationLayer
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dot
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromOffset(34, 12)
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.fromOffset(px, py + 5)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 8
	text.TextColor3 = poi.color
	text.TextStrokeTransparency = 0.35
	text.Text = poi.text
	text.Parent = stationLayer
end

local stationPlayer = Instance.new("Frame")
stationPlayer.Name = "StationPlayer"
stationPlayer.Size = UDim2.fromOffset(8, 8)
stationPlayer.AnchorPoint = Vector2.new(0.5, 0.5)
stationPlayer.BackgroundColor3 = Color3.fromRGB(245, 252, 255)
stationPlayer.BorderSizePixel = 0
stationPlayer.Visible = false
stationPlayer.Parent = stationLayer
local spCorner = Instance.new("UICorner")
spCorner.CornerRadius = UDim.new(0.5, 0)
spCorner.Parent = stationPlayer

-- Hostile blips: observed or audible only, never a wallhack. Visibility is a client-side raycast from
-- the player's head, so the map cannot know about an enemy the player cannot see; firing makes a
-- hostile "audible" for three seconds. Entries fade out after that.
local hostiles = {}
local HOSTILE_RANGE = 140
local HOSTILE_LINGER = 3

local function markHostile(position, audibleOnly)
	if typeof(position) ~= "Vector3" then
		return
	end
	local key = math.floor(position.X / 4) .. ":" .. math.floor(position.Z / 4)
	hostiles[key] = { position = position, seenAt = os.clock(), audible = audibleOnly and true or false }
end

game:GetService("ReplicatedStorage").GF.Remotes.EnemyFired.OnClientEvent:Connect(function(model, position)
	if typeof(position) == "Vector3" then
		markHostile(position, true)
	elseif model and model.PrimaryPart then
		markHostile(model.PrimaryPart.Position, true)
	end
end)

local function refreshHostiles()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local head = root.Position + Vector3.new(0, 2, 0)
	local folder = workspace:FindFirstChild("ActiveActors")
	if not folder then
		return
	end
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("GFEnemy") == true and model:GetAttribute("Dead") ~= true then
			local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			if part and (part.Position - root.Position).Magnitude <= HOSTILE_RANGE then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { player.Character, model }
				local hit = workspace:Raycast(head, part.Position - head, params)
				if not hit or (hit.Position - part.Position).Magnitude < 4 then
					markHostile(part.Position, false)
				end
			end
		end
	end
end

local hostileBlips = {}
local function drawHostiles()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local meta = string.split(workspace:GetAttribute("GF_MapMeta") or "", ",")
	local span = tonumber(meta[3]) or 320
	local scale = (RADIUS * 2) / math.max(1, span)
	local index = 0
	local now = os.clock()
	for key, entry in pairs(hostiles) do
		local age = now - entry.seenAt
		if age > HOSTILE_LINGER or not root then
			hostiles[key] = nil
		else
			index += 1
			local blip = hostileBlips[index]
			if not blip then
				blip = Instance.new("Frame")
				blip.Size = UDim2.fromOffset(6, 6)
				blip.AnchorPoint = Vector2.new(0.5, 0.5)
				blip.BorderSizePixel = 0
				blip.Parent = field
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0.5, 0)
				c.Parent = blip
				hostileBlips[index] = blip
			end
			local dx = (entry.position.X - root.Position.X) * scale
			local dz = (entry.position.Z - root.Position.Z) * scale
			blip.Position = UDim2.fromOffset(RADIUS + dx, RADIUS + dz)
			blip.BackgroundColor3 = entry.audible and Color3.fromRGB(255, 170, 90) or Color3.fromRGB(255, 90, 90)
			blip.BackgroundTransparency = math.clamp(age / HOSTILE_LINGER, 0, 0.85)
			blip.Visible = (dx * dx + dz * dz) <= (RADIUS - 4) * (RADIUS - 4)
		end
	end
	for extra = index + 1, #hostileBlips do
		hostileBlips[extra].Visible = false
	end
	gui:SetAttribute("GF_MinimapHostiles", index)
end

local cells = {}
local blips = {}
local heightsSig, markersSig = nil, nil
local lastHeights, lastMeta = nil, nil

local function rebuildCells(heights, meta)
	local ox, oz, span = tonumber(meta[1]), tonumber(meta[2]), tonumber(meta[3])
	local minH, maxH = tonumber(meta[4]) or 0, tonumber(meta[5]) or 1
	if not ox or not oz or not span or span <= 0 then
		return 0
	end
	local grid = 16
	local scale = (RADIUS * 2) / span
	local size = math.ceil(math.max(2, span / grid * scale))
	local spanH = math.max(1, maxH - minH)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local px = root and root.Position.X or ox
	local pz = root and root.Position.Z or oz
	for index = 1, grid * grid do
		local h = tonumber(heights[index]) or minH
		local cell = cells[index]
		if not cell then
			cell = Instance.new("Frame")
			cell.BorderSizePixel = 0
			cell.AnchorPoint = Vector2.new(0.5, 0.5)
			cell.Parent = field
			cells[index] = cell
		end
		local gx = (index - 1) % grid
		local gz = math.floor((index - 1) / grid)
		local wx = ox - span / 2 + (gx + 0.5) / grid * span
		local wz = oz - span / 2 + (gz + 0.5) / grid * span
		local t = math.clamp((h - minH) / spanH, 0, 1)
		cell.Size = UDim2.fromOffset(size, size)
		cell.Position = UDim2.fromOffset(RADIUS + (wx - px) * scale, RADIUS + (wz - pz) * scale)
		cell.BackgroundColor3 = Color3.fromRGB(math.floor(24 + 44 * t), math.floor(32 + 50 * t), math.floor(30 + 40 * t))
		local dx, dz = (wx - px) * scale, (wz - pz) * scale
		cell.Visible = (dx * dx + dz * dz) <= (RADIUS - size) * (RADIUS - size)
	end
	return grid * grid
end

local function rebuildBlips(sig)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local meta = string.split(workspace:GetAttribute("GF_MapMeta") or "", ",")
	local span = tonumber(meta[3]) or 320
	local scale = (RADIUS * 2) / math.max(1, span)
	local count = 0
	for entry in string.gmatch(sig or "", "[^;]+") do
		local parts = string.split(entry, ",")
		local tag, wx, wz = parts[1], tonumber(parts[2]), tonumber(parts[3])
		if tag and wx and wz and root then
			count += 1
			local blip = blips[count]
			if not blip then
				blip = Instance.new("Frame")
				blip.Size = UDim2.fromOffset(7, 7)
				blip.AnchorPoint = Vector2.new(0.5, 0.5)
				blip.BorderSizePixel = 0
				blip.Parent = field
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0.5, 0)
				c.Parent = blip
				blips[count] = blip
			end
			local colour = Color3.fromRGB(120, 220, 255)
			if tag == "obj" then
				colour = Color3.fromRGB(255, 196, 96)
			elseif tag == "lz" then
				colour = Color3.fromRGB(120, 255, 180)
			elseif tag == "down" then
				colour = Color3.fromRGB(255, 120, 120)
			end
			blip.BackgroundColor3 = colour
			local bdx, bdz = (wx - root.Position.X) * scale, (wz - root.Position.Z) * scale
			-- Clamp distant markers to the rim. Hiding the objective because it is 200m away made the
			-- minimap a black disc exactly when the player needed direction; rim markers preserve bearing.
			local distance = math.sqrt(bdx * bdx + bdz * bdz)
			local limit = RADIUS - 8
			if distance > limit then
				local shrink = limit / math.max(distance, 0.001)
				bdx *= shrink
				bdz *= shrink
			end
			blip.Position = UDim2.fromOffset(RADIUS + bdx, RADIUS + bdz)
			blip.Visible = true
		end
	end
	for index = count + 1, #blips do
		blips[index].Visible = false
	end
	return count
end

task.spawn(function()
	while true do
		task.wait(0.2)
		local metaRaw = workspace:GetAttribute("GF_MapMeta")
		local heightsRaw = workspace:GetAttribute("GF_MapHeights")
		local markersRaw = workspace:GetAttribute("GF_MapMarkers")
		if type(metaRaw) == "string" and type(heightsRaw) == "string" then
			if heightsRaw ~= heightsSig then
				heightsSig = heightsRaw
				gui:SetAttribute("GF_MinimapCells", #string.split(heightsRaw, ","))
				lastHeights = string.split(heightsRaw, ",")
				lastMeta = string.split(metaRaw, ",")
			end
			if lastHeights then
				rebuildCells(lastHeights, lastMeta)
			end
		end
		local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local inStation = rootPart ~= nil and rootPart.Position.Y > 500
		stationLayer.Visible = inStation
		stationPlayer.Visible = inStation
		arrow.Visible = not inStation
		if inStation then
			-- Deck map is north-up and does not rotate; the player marker moves within the footprint.
			field.Rotation = 0
			for _, cell in ipairs(cells) do
				cell.Visible = false
			end
			for _, blip in ipairs(blips) do
				blip.Visible = false
			end
			for _, blip in ipairs(hostileBlips) do
				blip.Visible = false
			end
			if rootPart then
				local px, py = stationMapOffset(rootPart.Position.X, rootPart.Position.Z)
				stationPlayer.Position = UDim2.fromOffset(math.clamp(px, 8, RADIUS * 2 - 8), math.clamp(py, 8, RADIUS * 2 - 8))
				stationPlayer.Rotation = -math.deg(math.atan2(rootPart.CFrame.LookVector.X, -rootPart.CFrame.LookVector.Z))
			end
			gui:SetAttribute("GF_MinimapStation", true)
			gui:SetAttribute("GF_MinimapBlips", #stationPois)
		else
			gui:SetAttribute("GF_MinimapStation", false)
			if type(markersRaw) == "string" then
				markersSig = markersRaw
				gui:SetAttribute("GF_MinimapBlips", rebuildBlips(markersRaw))
			end
			refreshHostiles()
			drawHostiles()
			local camera = workspace.CurrentCamera
			if camera then
				local look = (rootPart and rootPart.CFrame.LookVector) or camera.CFrame.LookVector
				local heading = math.deg(math.atan2(look.X, -look.Z))
				field.Rotation = -heading
				north.Position = UDim2.new(0.5, -7 + math.sin(math.rad(heading)) * (RADIUS - 14), 0, 6 + (1 - math.cos(math.rad(heading))) * 6)
				gui:SetAttribute("GF_MinimapHeading", math.floor(heading))
			end
		end
	end
end)

