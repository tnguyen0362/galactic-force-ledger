--!strict
-- Terrain-aware mission map. Reads the coarse height field the server publishes as attributes and
-- draws it as a tile grid, then overlays objective / LZ / squad markers. M toggles.
-- Presentation: angular war-room holographic table — graphite glass, cyan grid, amber objective
-- symbology, theater/region intelligence rail. All telemetry names and published attributes are unchanged.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tokens = require(ReplicatedStorage.GF.Shared.UI.Tokens)
local WarModel = require(ReplicatedStorage.GF.Shared.WarModel)
local WarOperations = require(ReplicatedStorage.GF.Shared.Configs.WarOperations)
local player = Players.LocalPlayer

local GRID = 16
local SIZE = 448
local PANEL_W = 704
local PANEL_H = 568
local GRID_X = 20
local GRID_Y = 88
local SIDEBAR_X = 484
local SIDEBAR_W = 200
local CELL = SIZE / GRID

local C = Tokens.Color
local FONT = Tokens.Type.font
local FONT_BOLD = Tokens.Type.fontBold

local gui = Instance.new("ScreenGui")
gui.Name = "TacticalMap"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function addStroke(target, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = target
	return stroke
end

local function line(parent, name, width, height, x, y, color, transparency, zindex, rotation)
	local l = Instance.new("Frame")
	l.Name = name
	l.Size = UDim2.fromOffset(width, height)
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromOffset(x, y)
	l.BackgroundColor3 = color
	l.BackgroundTransparency = transparency or 0
	l.BorderSizePixel = 0
	l.ZIndex = zindex or 5
	l.Rotation = rotation or 0
	l.Parent = parent
	return l
end

local function textLabel(parent, name, text, size, position, color, textSize, font, zindex)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = font or FONT
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.75
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = text
	label.ZIndex = zindex or 6
	label.Parent = parent
	return label
end

local function addAngularCorners(parent, width, height, inset, len, color, zindex)
	local z = zindex or 8
	line(parent, "CornerTL_H", len, 2, inset + len / 2, inset, color, 0.14, z)
	line(parent, "CornerTL_V", 2, len, inset, inset + len / 2, color, 0.14, z)
	line(parent, "CornerTR_H", len, 2, width - inset - len / 2, inset, color, 0.14, z)
	line(parent, "CornerTR_V", 2, len, width - inset, inset + len / 2, color, 0.14, z)
	line(parent, "CornerBL_H", len, 2, inset + len / 2, height - inset, color, 0.14, z)
	line(parent, "CornerBL_V", 2, len, inset, height - inset - len / 2, color, 0.14, z)
	line(parent, "CornerBR_H", len, 2, width - inset - len / 2, height - inset, color, 0.14, z)
	line(parent, "CornerBR_V", 2, len, width - inset, height - inset - len / 2, color, 0.14, z)
	-- Diagonal hairlines imply precision-cut/chamfered corners while using only rectangular UI.
	line(parent, "CutTL", 12, 1, inset + 6, inset + 6, color, 0.42, z, 45)
	line(parent, "CutTR", 12, 1, width - inset - 6, inset + 6, color, 0.42, z, -45)
	line(parent, "CutBL", 12, 1, inset + 6, height - inset - 6, color, 0.42, z, -45)
	line(parent, "CutBR", 12, 1, width - inset - 6, height - inset - 6, color, 0.42, z, 45)
end

local frame = Instance.new("Frame")
frame.Name = "WarTableFrame"
frame.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.BackgroundColor3 = C.panel
frame.BackgroundTransparency = 0.03
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = gui
addStroke(frame, C.border, 1, 0.08)
addAngularCorners(frame, PANEL_W, PANEL_H, 5, 28, C.techCyan, 10)

local uiScale = Instance.new("UIScale")
uiScale.Name = "ViewportScale"
uiScale.Scale = 1
uiScale.Parent = frame

local function updateViewportScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local usableX = math.max(320, viewport.X - 40)
	local usableY = math.max(280, viewport.Y - 40)
	uiScale.Scale = math.min(1, usableX / PANEL_W, usableY / PANEL_H)
end

-- Quiet layered table surface: broad dark panel first, cyan structure only where it carries meaning.
local topRail = Instance.new("Frame")
topRail.Name = "CommandHeader"
topRail.Size = UDim2.fromOffset(PANEL_W, 78)
topRail.BackgroundColor3 = C.panelRaised
topRail.BackgroundTransparency = 0.16
topRail.BorderSizePixel = 0
topRail.ZIndex = 2
topRail.Parent = frame
line(frame, "HeaderBottomRule", PANEL_W - 24, 1, PANEL_W / 2, 78, C.border, 0.28, 4)
line(frame, "HeaderCyanRule", 164, 1, 102, 78, C.techCyan, 0.28, 5)
line(frame, "TitleAmberTab", 3, 42, 12, 34, C.warning, 0.05, 5)

textLabel(frame, "Kicker", "GALACTIC FORCE // ORBITAL COMMAND", UDim2.fromOffset(390, 14), UDim2.fromOffset(22, 9), C.textAccent, 11, FONT, 5)
textLabel(frame, "Title", "SECTOR MAP", UDim2.fromOffset(390, 28), UDim2.fromOffset(22, 24), C.textPrimary, 22, FONT_BOLD, 5)

local linkChip = Instance.new("Frame")
linkChip.Name = "TelemetryChip"
linkChip.Size = UDim2.fromOffset(164, 32)
linkChip.Position = UDim2.fromOffset(PANEL_W - 184, 14)
linkChip.BackgroundColor3 = C.panelInset
linkChip.BackgroundTransparency = 0.08
linkChip.BorderSizePixel = 0
linkChip.ZIndex = 5
linkChip.Parent = frame
addStroke(linkChip, C.techCyan, 1, 0.42)
local linkText = textLabel(linkChip, "TelemetryChipText", "HOLO TABLE // LIVE", UDim2.fromOffset(148, 16), UDim2.fromOffset(8, 8), C.textAccent, 11, FONT_BOLD, 6)
linkText.TextXAlignment = Enum.TextXAlignment.Center

-- This label retains the complete legacy telemetry readout: origin, span, relief range and contacts.
local readout = textLabel(frame, "TelemetryReadout", "AWAITING TELEMETRY", UDim2.fromOffset(PANEL_W - 40, 16), UDim2.fromOffset(20, 57), C.textSecondary, 12, FONT, 5)

-- ---------------------------------------------------------------------------
-- Mission grid: relief tiles first, then fixed holographic graticule/coordinate overlay.
-- ---------------------------------------------------------------------------
local grid = Instance.new("Frame")
grid.Name = "MissionGrid"
grid.Size = UDim2.fromOffset(SIZE, SIZE)
grid.Position = UDim2.fromOffset(GRID_X, GRID_Y)
grid.BackgroundColor3 = C.panelInset
grid.BackgroundTransparency = 0.03
grid.BorderSizePixel = 0
grid.ZIndex = 3
grid.Parent = frame
grid.ClipsDescendants = true
addStroke(grid, C.border, 1, 0.12)
addAngularCorners(grid, SIZE, SIZE, 4, 20, C.techCyan, 9)

local cells = {}
for gz = 1, GRID do
	for gx = 1, GRID do
		local c = Instance.new("Frame")
		c.Name = string.format("Cell_%02d_%02d", gx, gz)
		c.Size = UDim2.fromOffset(CELL, CELL)
		c.Position = UDim2.fromOffset((gx - 1) * CELL, (gz - 1) * CELL)
		c.BackgroundColor3 = Color3.fromRGB(12, 20, 26)
		c.BackgroundTransparency = 0.02
		c.BorderSizePixel = 0
		c.ZIndex = 1
		c.Parent = grid
		cells[(gz - 1) * GRID + gx] = c
	end
end

-- Sparse scanlines sit below the graticule. They are deliberately faint — holographic table glass,
-- not cyberpunk noise.
for i = 1, 7 do
	line(grid, "Scanline" .. i, SIZE, 1, SIZE / 2, i * SIZE / 8, C.techCyan, 0.94, 2)
end

for i = 1, GRID - 1 do
	local major = i % 4 == 0
	local color = major and C.techCyan or C.border
	local transparency = major and 0.66 or 0.84
	line(grid, "GridV" .. i, 1, SIZE, i * CELL, SIZE / 2, color, transparency, 4)
	line(grid, "GridH" .. i, SIZE, 1, SIZE / 2, i * CELL, color, transparency, 4)
end

-- Military grid references: letters east, numbers south. Tiny by design; they orient the readout
-- without competing with the symbology.
for i = 1, GRID do
	local col = textLabel(grid, "GridCol" .. i, string.char(64 + i), UDim2.fromOffset(CELL, 10), UDim2.fromOffset((i - 1) * CELL, 2), C.textSecondary, 8, FONT, 5)
	col.TextXAlignment = Enum.TextXAlignment.Center
	if i % 4 ~= 0 then
		col.TextTransparency = 0.55
	end
	local row = textLabel(grid, "GridRow" .. i, string.format("%02d", i), UDim2.fromOffset(18, 10), UDim2.fromOffset(3, (i - 1) * CELL + 2), C.textSecondary, 8, FONT, 5)
	if i % 4 ~= 0 then
		row.TextTransparency = 0.55
	end
end

-- Slow holographic sweep: one restrained cyan pass every few seconds, below all markers.
-- It sells the war-table projection without turning the readout into animated noise.
local scanSweep = line(grid, "HolographicSweep", SIZE - 12, 2, SIZE / 2, SIZE / 2, C.techCyan, 1, 6)
scanSweep.Visible = false
local sweepClock = 0
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then
		scanSweep.Visible = false
		return
	end
	sweepClock = (sweepClock + dt) % 4.8
	local active = sweepClock < 1.7
	scanSweep.Visible = active
	if active then
		local p = sweepClock / 1.7
		scanSweep.Position = UDim2.fromOffset(SIZE / 2, 8 + p * (SIZE - 16))
		local edgeFade = math.min(p / 0.14, (1 - p) / 0.14, 1)
		scanSweep.BackgroundTransparency = 1 - 0.32 * math.clamp(edgeFade, 0, 1)
	end
end)

-- ---------------------------------------------------------------------------
-- Marker symbology: one consistent military visual language. Objective amber diamond,
-- LZ cyan crosshair, squad green square, downed friendly red X, ownship cyan chevron.
-- ---------------------------------------------------------------------------
local COLORS = {
	obj = C.warning,
	lz = C.techCyan,
	sq = C.success,
	sup = C.warning,
	down = C.danger,
}

local markers = {}
local function styleMarker(marker, tag)
	local colour = COLORS[tag] or COLORS.sq
	marker.core.Visible = true
	marker.crossH.Visible = false
	marker.crossV.Visible = false
	marker.diagA.Visible = false
	marker.diagB.Visible = false
	marker.core.Rotation = 0
	marker.core.Size = UDim2.fromOffset(9, 9)
	marker.core.BackgroundColor3 = colour
	marker.coreStroke.Color = C.panelInset
	marker.coreStroke.Transparency = 0.1
	marker.label.TextColor3 = colour

	local function tint(part, alpha)
		part.BackgroundColor3 = colour
		part.BackgroundTransparency = alpha or 0
	end

	if tag == "obj" then
		marker.core.Size = UDim2.fromOffset(14, 14)
		marker.core.Rotation = 45
		marker.coreStroke.Color = C.ceramic
		marker.coreStroke.Transparency = 0.28
		marker.label.Text = "OBJ"
	elseif tag == "lz" then
		marker.core.Size = UDim2.fromOffset(8, 8)
		marker.crossH.Visible = true
		marker.crossV.Visible = true
		tint(marker.crossH, 0.08)
		tint(marker.crossV, 0.08)
		marker.label.Text = "LZ"
	elseif tag == "down" then
		marker.core.Visible = false
		marker.diagA.Visible = true
		marker.diagB.Visible = true
		tint(marker.diagA, 0)
		tint(marker.diagB, 0)
		marker.label.Text = "DWN"
	elseif tag == "sq" then
		marker.core.Size = UDim2.fromOffset(8, 8)
		marker.coreStroke.Color = C.techCyan
		marker.coreStroke.Transparency = 0.2
		marker.label.Text = "SQ"
	elseif tag == "sup" then
		marker.core.Size = UDim2.fromOffset(9, 9)
		marker.coreStroke.Color = C.warning
		marker.coreStroke.Transparency = 0.05
		marker.label.Text = "SUP"
	else
		marker.core.Size = UDim2.fromOffset(10, 10)
		marker.core.Rotation = 45
		marker.label.Text = string.upper(string.sub(tag, 1, 3))
	end
end

local function markerFor(tag, index)
	local pool = markers[tag]
	if not pool then
		pool = {}
		markers[tag] = pool
	end
	if pool[index] then return pool[index] end
	local root = Instance.new("Frame")
	root.Name = "Marker_" .. tag .. "_" .. index
	root.Size = UDim2.fromOffset(34, 34)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 8
	root.Parent = grid

	local core = Instance.new("Frame")
	core.Name = "Core"
	core.Size = UDim2.fromOffset(9, 9)
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.new(0.5, 0, 0.5, -3)
	core.BorderSizePixel = 0
	core.ZIndex = 8
	core.Parent = root
	local coreStroke = Instance.new("UIStroke")
	coreStroke.Thickness = 1
	coreStroke.Transparency = 0.1
	coreStroke.Parent = core

	local function bar(name, width, height, rotation)
		local b = Instance.new("Frame")
		b.Name = name
		b.Size = UDim2.fromOffset(width, height)
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.new(0.5, 0, 0.5, -3)
		b.BorderSizePixel = 0
		b.Rotation = rotation or 0
		b.Visible = false
		b.ZIndex = 8
		b.Parent = root
		return b
	end

	local label = textLabel(root, "Tag", "", UDim2.fromOffset(34, 10), UDim2.fromOffset(0, 24), C.textSecondary, 8, FONT_BOLD, 9)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextStrokeTransparency = 0.35

	local marker = {
		root = root,
		core = core,
		coreStroke = coreStroke,
		crossH = bar("CrossH", 19, 2, 0),
		crossV = bar("CrossV", 2, 19, 0),
		diagA = bar("DiagA", 18, 2, 45),
		diagB = bar("DiagB", 18, 2, -45),
		label = label,
	}
	styleMarker(marker, tag)
	pool[index] = marker
	return marker
end

-- Ownship overlay: additive visual orientation aid, driven only by local character position.
local ownship = Instance.new("TextLabel")
ownship.Name = "Ownship"
ownship.Size = UDim2.fromOffset(22, 22)
ownship.AnchorPoint = Vector2.new(0.5, 0.5)
ownship.BackgroundTransparency = 1
ownship.Font = FONT_BOLD
ownship.TextSize = 15
ownship.TextColor3 = C.ceramic
ownship.TextStrokeTransparency = 0.35
ownship.Text = "▲"
ownship.Visible = false
ownship.ZIndex = 9
ownship.Parent = grid
local ownshipStroke = Instance.new("UIStroke")
ownshipStroke.Color = C.techCyan
ownshipStroke.Thickness = 1
ownshipStroke.Transparency = 0.08
ownshipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
ownshipStroke.Parent = ownship

-- ---------------------------------------------------------------------------
-- Theater intelligence rail: live operation/region state, force bars, campaign front summary,
-- and a compact legend. It reads existing workspace attributes only; it publishes nothing new.
-- ---------------------------------------------------------------------------
local sidebar = Instance.new("Frame")
sidebar.Name = "TheaterRail"
sidebar.Size = UDim2.fromOffset(SIDEBAR_W, SIZE)
sidebar.Position = UDim2.fromOffset(SIDEBAR_X, GRID_Y)
sidebar.BackgroundColor3 = C.panelRaised
sidebar.BackgroundTransparency = 0.1
sidebar.BorderSizePixel = 0
sidebar.ZIndex = 3
sidebar.Parent = frame
addStroke(sidebar, C.border, 1, 0.16)
addAngularCorners(sidebar, SIDEBAR_W, SIZE, 4, 16, C.techCyan, 7)

textLabel(sidebar, "TheaterTitle", "THEATER READOUT", UDim2.fromOffset(176, 16), UDim2.fromOffset(12, 10), C.textAccent, 12, FONT_BOLD, 5)
line(sidebar, "TheaterRule", 176, 1, 100, 34, C.techCyan, 0.46, 5)

textLabel(sidebar, "OperationCaption", "OPERATION", UDim2.fromOffset(176, 12), UDim2.fromOffset(12, 41), C.textSecondary, 10, FONT, 5)
local opTitle = textLabel(sidebar, "OperationTitle", "STANDBY", UDim2.fromOffset(176, 18), UDim2.fromOffset(12, 54), C.textPrimary, 14, FONT_BOLD, 5)
local opMeta = textLabel(sidebar, "OperationMeta", "NO TASKING", UDim2.fromOffset(176, 13), UDim2.fromOffset(12, 73), C.textSecondary, 10, FONT, 5)

textLabel(sidebar, "RegionCaption", "REGION", UDim2.fromOffset(80, 12), UDim2.fromOffset(12, 94), C.textSecondary, 10, FONT, 5)
local regionValue = textLabel(sidebar, "RegionValue", "UNASSIGNED", UDim2.fromOffset(176, 16), UDim2.fromOffset(12, 107), C.textAccent, 12, FONT_BOLD, 5)

local statusChip = Instance.new("Frame")
statusChip.Name = "RegionStatusChip"
statusChip.Size = UDim2.fromOffset(176, 25)
statusChip.Position = UDim2.fromOffset(12, 130)
statusChip.BackgroundColor3 = C.panelInset
statusChip.BackgroundTransparency = 0.12
statusChip.BorderSizePixel = 0
statusChip.ZIndex = 4
statusChip.Parent = sidebar
local statusStroke = addStroke(statusChip, C.steel, 1, 0.35)
local statusText = textLabel(statusChip, "StatusText", "NO UPLINK", UDim2.fromOffset(164, 14), UDim2.fromOffset(6, 5), C.textSecondary, 10, FONT_BOLD, 5)
statusText.TextXAlignment = Enum.TextXAlignment.Center

textLabel(sidebar, "ForceCaption", "FORCE MATRIX", UDim2.fromOffset(176, 12), UDim2.fromOffset(12, 164), C.textSecondary, 10, FONT, 5)

local statRows = {}
local statDefs = {
	{ key = "E", label = "ENY", color = C.ascendancy },
	{ key = "L", label = "LOG", color = C.warning },
	{ key = "H", label = "HUM", color = C.techCyan },
	{ key = "I", label = "INT", color = C.ceramic },
	{ key = "S", label = "SEC", color = C.success },
}
for i, def in ipairs(statDefs) do
	local y = 181 + (i - 1) * 20
	textLabel(sidebar, "StatLabel" .. def.key, def.label, UDim2.fromOffset(30, 11), UDim2.fromOffset(12, y), C.textSecondary, 10, FONT_BOLD, 5)
	local back = Instance.new("Frame")
	back.Name = "StatBack" .. def.key
	back.Size = UDim2.fromOffset(98, 7)
	back.Position = UDim2.fromOffset(45, y + 2)
	back.BackgroundColor3 = C.panelInset
	back.BackgroundTransparency = 0.05
	back.BorderSizePixel = 0
	back.ZIndex = 4
	back.Parent = sidebar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = def.color
	fill.BackgroundTransparency = 0.08
	fill.BorderSizePixel = 0
	fill.ZIndex = 5
	fill.Parent = back
	local value = textLabel(sidebar, "StatValue" .. def.key, "--", UDim2.fromOffset(34, 11), UDim2.fromOffset(149, y), C.textSecondary, 10, FONT, 5)
	value.TextXAlignment = Enum.TextXAlignment.Right
	statRows[def.key] = { fill = fill, value = value }
end

textLabel(sidebar, "CampaignCaption", "FRONT LINE", UDim2.fromOffset(176, 12), UDim2.fromOffset(12, 286), C.textSecondary, 10, FONT, 5)
local campaignLine = textLabel(sidebar, "CampaignLine", "THEATER STANDBY", UDim2.fromOffset(176, 14), UDim2.fromOffset(12, 301), C.textPrimary, 10, FONT_BOLD, 5)
local campaignMeta = textLabel(sidebar, "CampaignMeta", "ACTIVE FRONTS --", UDim2.fromOffset(176, 13), UDim2.fromOffset(12, 318), C.textSecondary, 10, FONT, 5)

textLabel(sidebar, "LegendCaption", "SYMBOL KEY", UDim2.fromOffset(176, 12), UDim2.fromOffset(12, 343), C.textSecondary, 10, FONT, 5)

local function legendSymbol(parent, kind, color)
	if kind == "chevron" then
		local t = textLabel(parent, "Symbol", "▲", UDim2.fromOffset(14, 12), UDim2.fromOffset(0, 0), color, 9, FONT_BOLD, 6)
		t.TextXAlignment = Enum.TextXAlignment.Center
		return t
	end
	local holder = Instance.new("Frame")
	holder.Name = "Symbol"
	holder.Size = UDim2.fromOffset(14, 12)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 5
	holder.Parent = parent
	if kind == "diamond" then
		local d = Instance.new("Frame")
		d.Size = UDim2.fromOffset(7, 7)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromScale(0.5, 0.5)
		d.Rotation = 45
		d.BackgroundColor3 = color
		d.BorderSizePixel = 0
		d.ZIndex = 6
		d.Parent = holder
	elseif kind == "cross" then
		line(holder, "CrossH", 11, 1, 7, 6, color, 0, 6)
		line(holder, "CrossV", 1, 11, 7, 6, color, 0, 6)
	elseif kind == "x" then
		line(holder, "XA", 10, 1, 7, 6, color, 0, 6, 45)
		line(holder, "XB", 10, 1, 7, 6, color, 0, 6, -45)
	else
		local s = Instance.new("Frame")
		s.Size = UDim2.fromOffset(6, 6)
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Position = UDim2.fromScale(0.5, 0.5)
		s.BackgroundColor3 = color
		s.BorderSizePixel = 0
		s.ZIndex = 6
		s.Parent = holder
	end
	return holder
end

local legendDefs = {
	{ label = "OBJECTIVE", kind = "diamond", color = C.warning },
	{ label = "LANDING ZONE", kind = "cross", color = C.techCyan },
	{ label = "SQUAD", kind = "square", color = C.success },
	{ label = "SUPPLY", kind = "square", color = C.warning },
	{ label = "DOWNED", kind = "x", color = C.danger },
	{ label = "OWNSHIP", kind = "chevron", color = C.ceramic },
}
for i, def in ipairs(legendDefs) do
	local y = 358 + (i - 1) * 14
	legendSymbol(sidebar, def.kind, def.color).Position = UDim2.fromOffset(13, y)
	textLabel(sidebar, "Legend" .. i, def.label, UDim2.fromOffset(140, 11), UDim2.fromOffset(32, y + 1), C.textSecondary, 10, FONT, 5)
end

local hint = textLabel(frame, "InputHint", "M // TOGGLE TACTICAL MAP        ESC // CLOSE", UDim2.fromOffset(420, 14), UDim2.fromOffset(20, PANEL_H - 20), C.textSecondary, 10, FONT, 5)
hint.TextXAlignment = Enum.TextXAlignment.Left
local footerId = textLabel(frame, "FooterId", "GF TACCMD // VEYRA-7", UDim2.fromOffset(180, 14), UDim2.fromOffset(PANEL_W - 200, PANEL_H - 20), C.textAccent, 10, FONT, 5)
footerId.TextXAlignment = Enum.TextXAlignment.Right

local function nonemptyString(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function upperStatus(status)
	return string.upper((string.gsub(status, "_", " ")))
end

local function upperRegionName(regionId)
	local spaced = string.gsub(regionId, "(%u)", " %1")
	spaced = string.gsub(spaced, "^%s+", "")
	return string.upper(spaced)
end

-- Transition-era fallback: GalacticWarService still publishes a compact territory snapshot while
-- WarStateService brings up the richer multidimensional matrix. Read-only; no new attributes.
local function legacyTerritorySnapshot(regionId)
	local raw = workspace:GetAttribute("GF_WarTerritories")
	if type(raw) ~= "string" or not regionId then
		return nil
	end
	for entry in raw:gmatch("[^;]+") do
		local id, progress, state, front = entry:match("([^:]+):(%d+):([^:]+)(:FRONT)?")
		if id == regionId then
			return tonumber(progress), state, front ~= nil
		end
	end
	return nil
end

local function paintTheaterRail()
	local operationId = nonemptyString(workspace:GetAttribute("GF_OperationId"))
	local regionId = nonemptyString(workspace:GetAttribute("GF_RegionId"))
	local opDef = operationId and WarModel.OPERATIONS[operationId] or nil
	if not regionId and opDef then
		regionId = opDef.region
	end

	if operationId then
		local display = (WarOperations.DisplayName and WarOperations.DisplayName[operationId]) or operationId
		opTitle.Text = string.upper(display)
		local family = opDef and opDef.family or "COMBAT"
		local template = WarOperations.templateFor and WarOperations.templateFor(operationId) or nil
		opMeta.Text = string.upper(template and (family .. " // " .. template) or family)
		linkText.Text = "HOLO TABLE // LIVE"
	else
		opTitle.Text = "STANDBY"
		opMeta.Text = "NO TASKING"
		linkText.Text = "HOLO TABLE // IDLE"
	end
	regionValue.Text = regionId and upperRegionName(regionId) or "UNASSIGNED"

	local status = regionId and nonemptyString(workspace:GetAttribute("GF_WarState_" .. regionId .. "_Status")) or nil
	if status then
		statusText.Text = upperStatus(status)
		local colour = Tokens.StatusColor[status] or C.steel
		statusText.TextColor3 = colour
		statusStroke.Color = colour
		statusStroke.Transparency = 0.12
	else
		local progress, legacyState, isFront = legacyTerritorySnapshot(regionId)
		if legacyState then
			local stateColor = legacyState == "Human" and C.success or legacyState == "Contested" and C.warning or C.ascendancy
			statusText.Text = string.upper(legacyState) .. string.format(" %02d%%", progress or 0) .. (isFront and " // FRONT" or "")
			statusText.TextColor3 = stateColor
			statusStroke.Color = stateColor
			statusStroke.Transparency = 0.18
		else
			statusText.Text = "NO UPLINK"
			statusText.TextColor3 = C.textSecondary
			statusStroke.Color = C.steel
			statusStroke.Transparency = 0.48
		end
	end

	for _, def in ipairs(statDefs) do
		local row = statRows[def.key]
		local value = regionId and workspace:GetAttribute("GF_WarState_" .. regionId .. "_" .. def.key) or nil
		if type(value) == "number" then
			local v = math.clamp(value, 0, 1)
			row.fill.Size = UDim2.new(v, 0, 1, 0)
			row.fill.BackgroundColor3 = def.color
			row.value.Text = string.format("%02d%%", math.floor(v * 100 + 0.5))
			row.value.TextColor3 = C.textPrimary
		else
			row.fill.Size = UDim2.new(0, 0, 1, 0)
			row.value.Text = "--"
			row.value.TextColor3 = C.textDisabled
		end
	end

	local warStatus = nonemptyString(workspace:GetAttribute("GF_WarStatus"))
	local wins = workspace:GetAttribute("GF_WarWins")
	local losses = workspace:GetAttribute("GF_WarLosses")
	campaignLine.Text = warStatus or "THEATER STANDBY"
	local fronts = workspace:GetAttribute("GF_WarFronts")
	local frontText = type(fronts) == "number" and string.format("FRONTS %d", fronts) or "FRONTS --"
	if type(wins) == "number" and type(losses) == "number" then
		campaignMeta.Text = string.format("%s // %dW %dL", frontText, wins, losses)
	else
		campaignMeta.Text = frontText
	end
end

local function reliefColor(t)
	local low = Color3.fromRGB(9, 16, 22)
	local mid = Color3.fromRGB(24, 43, 53)
	local high = Color3.fromRGB(73, 96, 102)
	if t < 0.5 then
		return low:Lerp(mid, t * 2)
	end
	return mid:Lerp(high, (t - 0.5) * 2)
end

local function paint()
	updateViewportScale()
	paintTheaterRail()

	local heightsRaw = workspace:GetAttribute("GF_MapHeights")
	local metaRaw = workspace:GetAttribute("GF_MapMeta")
	if type(heightsRaw) ~= "string" or type(metaRaw) ~= "string" then
		readout.Text = "NO MISSION TELEMETRY"
		return
	end
	local ox, oz, span, minH, maxH = metaRaw:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
	ox, oz, span, minH, maxH = tonumber(ox), tonumber(oz), tonumber(span), tonumber(minH), tonumber(maxH)
	if not (ox and oz and span and minH and maxH) then
		readout.Text = "BAD TELEMETRY"
		return
	end
	local band = math.max(1, maxH - minH)
	local index = 0
	for value in heightsRaw:gmatch("[^,]+") do
		index += 1
		local cell = cells[index]
		if cell then
			local h = tonumber(value) or minH
			local t = math.clamp((h - minH) / band, 0, 1)
			-- Six stepped relief bands read as a military contour/height readout rather than terrain noise.
			local stepped = math.floor(t * 6 + 0.5) / 6
			cell.BackgroundColor3 = reliefColor(math.clamp(stepped, 0, 1))
		end
	end

	local markerRaw = workspace:GetAttribute("GF_MapMarkers")
	local placed = 0
	local usedMarkers = {}
	if type(markerRaw) == "string" then
		for tag, x, z in markerRaw:gmatch("([^,;]+),([^,;]+),([^,;]+)") do
			local wx, wz = tonumber(x), tonumber(z)
			if wx and wz then
				local u = math.clamp((wx - (ox - span / 2)) / span, 0, 1)
				local v = math.clamp((wz - (oz - span / 2)) / span, 0, 1)
				-- The publisher emits one entry per squad member/supply crate. Pool by tag+ordinal so
				-- the war table shows every contact the telemetry line counts, not only the last one.
				local ordinal = (usedMarkers[tag] or 0) + 1
				usedMarkers[tag] = ordinal
				local marker = markerFor(tag, ordinal)
				marker.root.Position = UDim2.fromOffset(u * SIZE, v * SIZE)
				marker.root.Visible = true
				placed += 1
			end
		end
	end
	for tag, pool in pairs(markers) do
		local used = usedMarkers[tag] or 0
		for ordinal, marker in ipairs(pool) do
			if ordinal > used then
				marker.root.Visible = false
			end
		end
	end

	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		local rawU = (rootPart.Position.X - (ox - span / 2)) / span
		local rawV = (rootPart.Position.Z - (oz - span / 2)) / span
		if rawU >= 0 and rawU <= 1 and rawV >= 0 and rawV <= 1 then
			ownship.Position = UDim2.fromOffset(rawU * SIZE, rawV * SIZE)
			local heading = math.deg(math.atan2(rootPart.CFrame.LookVector.X, -rootPart.CFrame.LookVector.Z))
			ownship.Rotation = heading
			ownship.Visible = true
		else
			ownship.Visible = false
		end
	else
		ownship.Visible = false
	end

	-- Complete legacy telemetry line, uppercased for the small-caps military readout treatment.
	readout.Text = string.upper(string.format("origin %.0f,%.0f  span %.0fm  relief %.0f-%.0f  contacts %d", ox, oz, span, minH, maxH, placed))
	workspace:SetAttribute("TacticalMap_Cells", GRID * GRID)
	workspace:SetAttribute("TacticalMap_Markers", placed)
	workspace:SetAttribute("TacticalMap_Height", string.format("%.0f..%.0f", minH, maxH))
end

local function setOpen(open)
	gui.Enabled = open
	workspace:SetAttribute("TacticalMap_Open", open)
	if open then
		paint()
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.M then
		setOpen(not gui.Enabled)
	elseif input.KeyCode == Enum.KeyCode.Escape and gui.Enabled then
		setOpen(false)
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		if gui.Enabled then
			paint()
		end
	end
end)

setOpen(false)
