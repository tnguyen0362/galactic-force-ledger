--!nonstrict
-- Minimap. The server publishes a 16x16 height field and a marker list as workspace attributes
-- (GF_MapMeta / GF_MapHeights / GF_MapMarkers); nothing drew them before this.
-- Visual language: compact angular military HUD — graphite/slate ground, restrained cyan frame,
-- amber objective symbology, no rounded UI chrome.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tokens = require(ReplicatedStorage.GF.Shared.UI.Tokens)
local player = Players.LocalPlayer

local RADIUS = 54 -- tactical readout, not a screen hijack: keep the recently-shrunk 108px footprint
local SIZE = RADIUS * 2
-- Heading-up rotation needs an oversized backing field. Without it, rotating a square map leaves
-- empty triangular corners; the viewport itself remains the same compact 108px readout.
local MAP_SCALE_BOOST = 1.42
local FIELD_SIZE = math.ceil(SIZE * 1.56)
local FIELD_CENTER = FIELD_SIZE / 2

local C = Tokens.Color
local FONT = Tokens.Type.font
local FONT_BOLD = Tokens.Type.fontBold

local gui = Instance.new("ScreenGui")
gui.Name = "GF_Minimap"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 4
gui.Parent = player:WaitForChild("PlayerGui")

local function hudLine(parent, name, width, height, x, y, color, transparency, zindex, rotation)
	local line = Instance.new("Frame")
	line.Name = name
	line.Size = UDim2.fromOffset(width, height)
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromOffset(x, y)
	line.BackgroundColor3 = color
	line.BackgroundTransparency = transparency or 0
	line.BorderSizePixel = 0
	line.ZIndex = zindex or 5
	line.Rotation = rotation or 0
	line.Parent = parent
	return line
end

local function hudText(parent, name, text, size, position, color, textSize, zindex)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.65
	label.Text = text
	label.ZIndex = zindex or 8
	label.Parent = parent
	return label
end

local frame = Instance.new("CanvasGroup")
frame.Name = "MinimapFrame"
frame.Size = UDim2.fromOffset(SIZE, SIZE)
frame.AnchorPoint = Vector2.new(1, 0)
frame.Position = UDim2.new(1, -14, 0, 12)
frame.BackgroundColor3 = C.panelInset
frame.BackgroundTransparency = 0.04
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.GroupTransparency = 0
frame.Parent = gui

local outerStroke = Instance.new("UIStroke")
outerStroke.Color = C.border
outerStroke.Thickness = 1
outerStroke.Transparency = 0.08
outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
outerStroke.Parent = frame

-- Hairline inner bezel: a second, quieter edge gives the readout a manufactured HUD frame
-- without rounding or bulky chrome.
local innerBezel = Instance.new("Frame")
innerBezel.Name = "InnerBezel"
innerBezel.Size = UDim2.fromOffset(SIZE - 8, SIZE - 8)
innerBezel.Position = UDim2.fromOffset(4, 4)
innerBezel.BackgroundTransparency = 1
innerBezel.ZIndex = 7
innerBezel.Parent = frame
local innerStroke = Instance.new("UIStroke")
innerStroke.Color = C.techCyan
innerStroke.Transparency = 0.78
innerStroke.Thickness = 1
innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
innerStroke.Parent = innerBezel

local function addCornerBrackets(parent, width, height)
	local inset = 3
	local len = 15
	local z = 10
	-- Horizontal/vertical L-brackets.
	hudLine(parent, "CornerTL_H", len, 2, inset + len / 2, inset, C.techCyan, 0.18, z)
	hudLine(parent, "CornerTL_V", 2, len, inset, inset + len / 2, C.techCyan, 0.18, z)
	hudLine(parent, "CornerTR_H", len, 2, width - inset - len / 2, inset, C.techCyan, 0.18, z)
	hudLine(parent, "CornerTR_V", 2, len, width - inset, inset + len / 2, C.techCyan, 0.18, z)
	hudLine(parent, "CornerBL_H", len, 2, inset + len / 2, height - inset, C.techCyan, 0.18, z)
	hudLine(parent, "CornerBL_V", 2, len, inset, height - inset - len / 2, C.techCyan, 0.18, z)
	hudLine(parent, "CornerBR_H", len, 2, width - inset - len / 2, height - inset, C.techCyan, 0.18, z)
	hudLine(parent, "CornerBR_V", 2, len, width - inset, height - inset - len / 2, C.techCyan, 0.18, z)
	-- Short diagonal cuts just inside each bracket imply the controlled chamfers from the art
	-- direction while remaining plain Roblox UI geometry.
	hudLine(parent, "CutTL", 9, 1, inset + 5, inset + 5, C.techCyan, 0.48, z, 45)
	hudLine(parent, "CutTR", 9, 1, width - inset - 5, inset + 5, C.techCyan, 0.48, z, -45)
	hudLine(parent, "CutBL", 9, 1, inset + 5, height - inset - 5, C.techCyan, 0.48, z, -45)
	hudLine(parent, "CutBR", 9, 1, width - inset - 5, height - inset - 5, C.techCyan, 0.48, z, 45)
end

local disc = Instance.new("Frame")
disc.Name = "TacticalViewport"
disc.Size = UDim2.fromOffset(SIZE, SIZE)
disc.BackgroundColor3 = C.panelInset
disc.BackgroundTransparency = 0.1
disc.BorderSizePixel = 0
disc.ClipsDescendants = true
disc.ZIndex = 1
disc.Parent = frame

local field = Instance.new("Frame")
field.Name = "Field"
field.Size = UDim2.fromOffset(FIELD_SIZE, FIELD_SIZE)
field.AnchorPoint = Vector2.new(0.5, 0.5)
field.Position = UDim2.fromScale(0.5, 0.5)
field.BackgroundTransparency = 1
field.ZIndex = 2
field.Parent = disc

-- Fixed reticle/grid overlay. The terrain rotates under this grid in heading-up mode, matching
-- military navigation displays: ownship stays centered and the compass moves around it.
local overlay = Instance.new("Frame")
overlay.Name = "ReticleOverlay"
overlay.Size = UDim2.fromOffset(SIZE, SIZE)
overlay.BackgroundTransparency = 1
overlay.ZIndex = 5
overlay.Parent = disc

for i = 1, 3 do
	local p = math.floor(SIZE * i / 4 + 0.5)
	local major = i == 2
	local color = major and C.techCyan or C.border
	local transparency = major and 0.78 or 0.86
	hudLine(overlay, "GridV" .. i, 1, SIZE - 12, p, SIZE / 2, color, transparency, 5)
	hudLine(overlay, "GridH" .. i, SIZE - 12, 1, SIZE / 2, p, color, transparency, 5)
end

-- Compass ticks around the square rim. These are deliberately small: structure, not decoration.
for i = 0, 7 do
	local angle = math.rad(i * 45)
	local x = SIZE / 2 + math.sin(angle) * (RADIUS - 8)
	local y = SIZE / 2 - math.cos(angle) * (RADIUS - 8)
	hudLine(overlay, "CompassTick" .. i, 1, 5, x, y, i % 2 == 0 and C.steel or C.border, 0.42, 5, math.deg(angle))
end

addCornerBrackets(frame, SIZE, SIZE)

local modeLabel = hudText(frame, "ModeLabel", "TACNET", UDim2.fromOffset(36, 10), UDim2.fromOffset(20, 3), C.textAccent, 8, 9)
modeLabel.TextXAlignment = Enum.TextXAlignment.Left

local north = Instance.new("TextLabel")
north.Name = "North"
north.Text = "N"
north.Size = UDim2.fromOffset(14, 14)
north.AnchorPoint = Vector2.new(0.5, 0.5)
north.Position = UDim2.fromOffset(SIZE / 2, 10)
north.BackgroundTransparency = 1
north.Font = FONT_BOLD
north.TextSize = 10
north.TextColor3 = C.warning
north.TextStrokeTransparency = 0.45
north.ZIndex = 9
north.Parent = frame

-- Ownship is a chevron, not a pip: the one white/cyan element in the pip language.
local arrow = Instance.new("TextLabel")
arrow.Name = "OwnshipChevron"
arrow.Size = UDim2.fromOffset(16, 16)
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.Position = UDim2.fromScale(0.5, 0.5)
arrow.BackgroundTransparency = 1
arrow.Font = FONT_BOLD
arrow.TextSize = 12
arrow.TextColor3 = C.ceramic
arrow.TextStrokeTransparency = 0.45
arrow.Text = "▲"
arrow.ZIndex = 10
arrow.Parent = frame
local arrowStroke = Instance.new("UIStroke")
arrowStroke.Color = C.techCyan
arrowStroke.Thickness = 1
arrowStroke.Transparency = 0.18
arrowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
arrowStroke.Parent = arrow

-- Station mode: the mission radar was a blank/irrelevant readout on the concourse. Draw a compact
-- deck plan instead, with the four places a player actually needs: war table, armoury, dispatch and pod bay.
local stationLayer = Instance.new("Frame")
stationLayer.Name = "StationLayout"
stationLayer.Size = UDim2.fromOffset(SIZE, SIZE)
stationLayer.BackgroundTransparency = 1
stationLayer.Visible = false
stationLayer.ZIndex = 3
stationLayer.Parent = disc

local STATION_SCALE = 0.48
local function stationMapOffset(x, z)
	return RADIUS + x * STATION_SCALE, RADIUS + (z - 20) * STATION_SCALE
end

local function stationBox(name, x, z, w, h, color, transparency)
	local cx, cy = stationMapOffset(x, z)
	local box = Instance.new("Frame")
	box.Name = name
	-- w/h are deck dimensions in world studs, same as x/z; scaling them consistently keeps the
	-- footprint inside the compact viewport instead of clipping the concourse into a solid slab
	box.Size = UDim2.fromOffset(w * STATION_SCALE, h * STATION_SCALE)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromOffset(cx, cy)
	box.BackgroundColor3 = color
	box.BackgroundTransparency = transparency or 0.72
	box.BorderSizePixel = 1
	box.BorderColor3 = C.border
	box.ZIndex = 3
	box.Parent = stationLayer
	return box
end

-- Simplified architectural footprint: central concourse, west/east alcoves, and the deployment bay.
stationBox("MainConcourse", 0, 18, 118, 48, C.navy, 0.66)
stationBox("WestAlcove", -82, 0, 44, 64, C.panelRaised, 0.64)
stationBox("EastAlcove", 82, -18, 44, 58, C.panelRaised, 0.64)
stationBox("DeploymentBay", 0, 66, 70, 34, Color3.fromRGB(28, 48, 56), 0.6)

local stationTitle = Instance.new("TextLabel")
stationTitle.Name = "StationTitle"
stationTitle.Size = UDim2.fromOffset(70, 14)
stationTitle.AnchorPoint = Vector2.new(0.5, 1)
stationTitle.Position = UDim2.new(0.5, 0, 1, -5)
stationTitle.BackgroundTransparency = 1
stationTitle.Font = FONT_BOLD
stationTitle.TextSize = 8
stationTitle.TextColor3 = C.textAccent
stationTitle.TextStrokeTransparency = 0.7
stationTitle.Text = "STATION DECK"
stationTitle.ZIndex = 6
stationTitle.Parent = stationLayer

local stationPois = {
	{ text = "WAR", x = 0, z = -34, color = C.techCyan },
	{ text = "ARM", x = -94, z = -2, color = C.warning },
	{ text = "DSP", x = 88, z = -28, color = C.warning },
	{ text = "POD", x = 0, z = 72, color = C.success },
}
for _, poi in ipairs(stationPois) do
	local px, py = stationMapOffset(poi.x, poi.z)
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(6, 6)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromOffset(px, py)
	dot.BackgroundColor3 = poi.color
	dot.BorderSizePixel = 0
	dot.Rotation = 45
	dot.ZIndex = 6
	dot.Parent = stationLayer
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromOffset(34, 12)
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.fromOffset(px, py + 5)
	text.BackgroundTransparency = 1
	text.Font = FONT_BOLD
	text.TextSize = 8
	text.TextColor3 = poi.color
	text.TextStrokeTransparency = 0.35
	text.Text = poi.text
	text.ZIndex = 6
	text.Parent = stationLayer
end

local stationPlayer = Instance.new("TextLabel")
stationPlayer.Name = "StationPlayer"
stationPlayer.Size = UDim2.fromOffset(12, 12)
stationPlayer.AnchorPoint = Vector2.new(0.5, 0.5)
stationPlayer.BackgroundTransparency = 1
stationPlayer.Font = FONT_BOLD
stationPlayer.TextSize = 10
stationPlayer.TextColor3 = C.ceramic
stationPlayer.TextStrokeTransparency = 0.4
stationPlayer.Text = "▲"
stationPlayer.ZIndex = 8
stationPlayer.Visible = false
stationPlayer.Parent = stationLayer
local stationPlayerStroke = Instance.new("UIStroke")
stationPlayerStroke.Color = C.techCyan
stationPlayerStroke.Thickness = 1
stationPlayerStroke.Transparency = 0.15
stationPlayerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
stationPlayerStroke.Parent = stationPlayer

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

ReplicatedStorage.GF.Remotes.EnemyFired.OnClientEvent:Connect(function(model, position)
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

-- Marker pips are composite but tiny: a transparent carrier counter-rotates against the rotating
-- field so the symbology remains upright/readable while the terrain turns beneath it.
local function newMarkerPip(parent)
	local root = Instance.new("Frame")
	root.Size = UDim2.fromOffset(14, 14)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 7
	root.Parent = parent

	local core = Instance.new("Frame")
	core.Name = "Core"
	core.Size = UDim2.fromOffset(6, 6)
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.BorderSizePixel = 0
	core.ZIndex = 7
	core.Parent = root
	local coreStroke = Instance.new("UIStroke")
	coreStroke.Thickness = 1
	coreStroke.Transparency = 0.2
	coreStroke.Parent = core

	local function bar(name, width, height, rotation)
		local b = Instance.new("Frame")
		b.Name = name
		b.Size = UDim2.fromOffset(width, height)
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromScale(0.5, 0.5)
		b.BorderSizePixel = 0
		b.Rotation = rotation or 0
		b.Visible = false
		b.ZIndex = 8
		b.Parent = root
		return b
	end

	return {
		root = root,
		core = core,
		coreStroke = coreStroke,
		crossH = bar("CrossH", 11, 2, 0),
		crossV = bar("CrossV", 2, 11, 0),
		diagA = bar("DiagA", 11, 2, 45),
		diagB = bar("DiagB", 11, 2, -45),
	}
end

local function configureMarkerPip(pip, tag, colour)
	pip.core.Visible = true
	pip.crossH.Visible = false
	pip.crossV.Visible = false
	pip.diagA.Visible = false
	pip.diagB.Visible = false
	pip.core.Rotation = 0
	pip.core.Size = UDim2.fromOffset(6, 6)
	pip.core.BackgroundColor3 = colour
	pip.core.BackgroundTransparency = 0
	pip.coreStroke.Color = C.panelInset
	pip.coreStroke.Transparency = 0.15

	local function tint(part, color, transparency)
		part.BackgroundColor3 = color
		part.BackgroundTransparency = transparency or 0
	end

	if tag == "obj" then
		-- objective: amber diamond, the highest-priority non-player symbol
		pip.core.Size = UDim2.fromOffset(8, 8)
		pip.core.Rotation = 45
		pip.coreStroke.Color = C.ceramic
		pip.coreStroke.Transparency = 0.35
	elseif tag == "lz" then
		-- landing zone: cyan square plus a fine crosshair
		pip.core.Size = UDim2.fromOffset(5, 5)
		pip.crossH.Visible = true
		pip.crossV.Visible = true
		tint(pip.crossH, colour, 0.12)
		tint(pip.crossV, colour, 0.12)
	elseif tag == "down" then
		-- downed friendly: red X, distinct from hostile triangular contacts
		pip.core.Visible = false
		pip.diagA.Visible = true
		pip.diagB.Visible = true
		tint(pip.diagA, colour, 0)
		tint(pip.diagB, colour, 0)
	elseif tag == "sup" then
		-- supply: small amber square with a bright edge
		pip.core.Size = UDim2.fromOffset(6, 6)
		pip.coreStroke.Color = C.warning
		pip.coreStroke.Transparency = 0
	else
		-- squad/default: compact cyan-framed ceramic square
		pip.core.Size = UDim2.fromOffset(5, 5)
		pip.coreStroke.Color = C.techCyan
		pip.coreStroke.Transparency = 0.25
	end
end

local function newHostilePip(parent)
	local root = Instance.new("Frame")
	root.Size = UDim2.fromOffset(13, 13)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 8
	root.Parent = parent
	local icon = Instance.new("TextLabel")
	icon.Name = "HostileChevron"
	icon.Size = UDim2.fromOffset(13, 13)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.Font = FONT_BOLD
	icon.TextSize = 10
	icon.TextColor3 = C.danger
	icon.TextStrokeTransparency = 0.7
	icon.Text = "▲"
	icon.ZIndex = 8
	icon.Parent = root
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.danger
	stroke.Thickness = 1
	stroke.Transparency = 0.2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = icon
	return { root = root, icon = icon, stroke = stroke }
end

local hostileBlips = {}
local function drawHostiles()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local meta = string.split(workspace:GetAttribute("GF_MapMeta") or "", ",")
	local span = tonumber(meta[3]) or 320
	local scale = (SIZE / math.max(1, span)) * MAP_SCALE_BOOST
	local index = 0
	local now = os.clock()
	for key, entry in pairs(hostiles) do
		local age = now - entry.seenAt
		if age > HOSTILE_LINGER or not root then
			hostiles[key] = nil
		else
			index += 1
			local pip = hostileBlips[index]
			if not pip then
				pip = newHostilePip(field)
				hostileBlips[index] = pip
			end
			local dx = (entry.position.X - root.Position.X) * scale
			local dz = (entry.position.Z - root.Position.Z) * scale
			pip.root.Position = UDim2.fromOffset(FIELD_CENTER + dx, FIELD_CENTER + dz)
			pip.root.Rotation = -field.Rotation
			local fade = math.clamp(age / HOSTILE_LINGER, 0, 0.85)
			local colour = entry.audible and C.warning or C.danger
			pip.icon.TextColor3 = colour
			pip.stroke.Color = colour
			-- Audible-only contacts are hollower/amber; direct line-of-sight contacts are solid red.
			pip.icon.TextTransparency = entry.audible and math.clamp(0.28 + fade, 0, 0.92) or fade * 0.8
			pip.stroke.Transparency = entry.audible and math.clamp(fade * 0.7, 0, 0.85) or math.clamp(0.2 + fade, 0, 0.9)
			pip.root.Visible = math.abs(dx) <= FIELD_CENTER and math.abs(dz) <= FIELD_CENTER
		end
	end
	for extra = index + 1, #hostileBlips do
		hostileBlips[extra].root.Visible = false
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
	local scale = (SIZE / span) * MAP_SCALE_BOOST
	local size = math.ceil(math.max(2, span / math.max(1, grid - 1) * scale))
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
			cell.ZIndex = 1
			cell.Parent = field
			cells[index] = cell
		end
		local gx = (index - 1) % grid
		local gz = math.floor((index - 1) / grid)
		local wx = ox - span / 2 + gx / math.max(1, grid - 1) * span
		local wz = oz - span / 2 + gz / math.max(1, grid - 1) * span
		local t = math.clamp((h - minH) / spanH, 0, 1)
		cell.Size = UDim2.fromOffset(size, size)
		cell.Position = UDim2.fromOffset(FIELD_CENTER + (wx - px) * scale, FIELD_CENTER + (wz - pz) * scale)
		-- Slate/cyan relief ramp: dark low ground, desaturated steel high ground. No green terrain
		-- noise — this is a military sensor readout, not a satellite photo.
		cell.BackgroundColor3 = Color3.fromRGB(
			math.floor(10 + 50 * t),
			math.floor(20 + 68 * t),
			math.floor(27 + 68 * t)
		)
		cell.BackgroundTransparency = 0.04
		cell.Visible = true
	end
	return grid * grid
end

local function rebuildBlips(sig)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local meta = string.split(workspace:GetAttribute("GF_MapMeta") or "", ",")
	local span = tonumber(meta[3]) or 320
	local scale = (SIZE / math.max(1, span)) * MAP_SCALE_BOOST
	local count = 0
	for entry in string.gmatch(sig or "", "[^;]+") do
		local parts = string.split(entry, ",")
		local tag, wx, wz = parts[1], tonumber(parts[2]), tonumber(parts[3])
		if tag and wx and wz and root then
			count += 1
			local pip = blips[count]
			if not pip then
				pip = newMarkerPip(field)
				blips[count] = pip
			end
			local colour = C.techCyan
			if tag == "obj" then
				colour = C.warning
			elseif tag == "lz" then
				colour = C.techCyan
			elseif tag == "down" then
				colour = C.danger
			elseif tag == "sup" then
				colour = C.warning
			end
			configureMarkerPip(pip, tag, colour)
			local bdx, bdz = (wx - root.Position.X) * scale, (wz - root.Position.Z) * scale
			-- Clamp distant markers to the rim. Hiding the objective because it is 200m away made the
			-- minimap a black readout exactly when the player needed direction; rim markers preserve bearing.
			local distance = math.sqrt(bdx * bdx + bdz * bdz)
			local limit = RADIUS - 9
			if distance > limit then
				local shrink = limit / math.max(distance, 0.001)
				bdx *= shrink
				bdz *= shrink
			end
			pip.root.Position = UDim2.fromOffset(FIELD_CENTER + bdx, FIELD_CENTER + bdz)
			pip.root.Rotation = -field.Rotation
			pip.root.Visible = true
		end
	end
	for index = count + 1, #blips do
		blips[index].root.Visible = false
	end
	return count
end

task.spawn(function()
	while true do
		task.wait(0.35)
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
		field.Visible = not inStation
		stationLayer.Visible = inStation
		stationPlayer.Visible = inStation
		arrow.Visible = not inStation
		north.Visible = not inStation
		modeLabel.Text = inStation and "DECK" or "TACNET"
		if inStation then
			-- Deck map is north-up and does not rotate; the player marker moves within the footprint.
			field.Rotation = 0
			for _, pip in ipairs(blips) do
				pip.root.Visible = false
			end
			for _, pip in ipairs(hostileBlips) do
				pip.root.Visible = false
			end
			if rootPart then
				local px, py = stationMapOffset(rootPart.Position.X, rootPart.Position.Z)
				stationPlayer.Position = UDim2.fromOffset(math.clamp(px, 8, SIZE - 8), math.clamp(py, 8, SIZE - 8))
				stationPlayer.Rotation = math.deg(math.atan2(rootPart.CFrame.LookVector.X, -rootPart.CFrame.LookVector.Z))
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
				local compass = math.rad(heading)
				-- In heading-up mode north moves counter to ownship heading: facing east puts north left.
				north.Position = UDim2.fromOffset(
					SIZE / 2 - math.sin(compass) * (RADIUS - 9),
					SIZE / 2 - math.cos(compass) * (RADIUS - 9)
				)
				gui:SetAttribute("GF_MinimapHeading", math.floor(heading))
			end
		end
	end
end)
