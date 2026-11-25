--!strict
-- Terrain-aware mission map. Reads the coarse height field the server publishes as attributes and
-- draws it as a tile grid, then overlays objective / LZ / squad markers. M toggles.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local GRID = 16
local SIZE = 480
local gui = Instance.new("ScreenGui")
gui.Name = "TacticalMap"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(SIZE + 28, SIZE + 64)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.BackgroundColor3 = Color3.fromRGB(10, 14, 20)
frame.BackgroundTransparency = 0.08
frame.BorderSizePixel = 0
frame.Parent = gui

local border = Instance.new("UIStroke")
border.Color = Color3.fromRGB(64, 116, 148)
border.Thickness = 2
border.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -28, 0, 26)
title.Position = UDim2.new(0, 14, 0, 8)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamMedium
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(190, 220, 235)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "SECTOR MAP"
title.Parent = frame

local readout = Instance.new("TextLabel")
readout.Size = UDim2.new(1, -28, 0, 18)
readout.Position = UDim2.new(0, 14, 0, 30)
readout.BackgroundTransparency = 1
readout.Font = Enum.Font.Gotham
readout.TextSize = 12
readout.TextColor3 = Color3.fromRGB(120, 160, 180)
readout.TextXAlignment = Enum.TextXAlignment.Left
readout.Text = "awaiting telemetry"
readout.Parent = frame

local grid = Instance.new("Frame")
grid.Size = UDim2.fromOffset(SIZE, SIZE)
grid.Position = UDim2.new(0, 14, 0, 56)
grid.BackgroundColor3 = Color3.fromRGB(6, 9, 13)
grid.BorderSizePixel = 0
grid.Parent = frame
grid.ClipsDescendants = true

local cells = {}
for gz = 1, GRID do
	for gx = 1, GRID do
		local c = Instance.new("Frame")
		c.Size = UDim2.fromOffset(SIZE / GRID - 1, SIZE / GRID - 1)
		c.Position = UDim2.fromOffset((gx - 1) * (SIZE / GRID), (gz - 1) * (SIZE / GRID))
		c.BackgroundColor3 = Color3.fromRGB(20, 26, 30)
		c.BorderSizePixel = 0
		c.Parent = grid
		cells[(gz - 1) * GRID + gx] = c
	end
end

local markers = {}
local function markerFor(tag)
	if markers[tag] then return markers[tag] end
	local box = Instance.new("Frame")
	box.Size = UDim2.fromOffset(10, 10)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.BorderSizePixel = 0
	box.BackgroundColor3 = Color3.fromRGB(255, 190, 80)
	box.Parent = grid
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = box
	markers[tag] = box
	return box
end

local COLORS = {
	obj = Color3.fromRGB(255, 96, 72),
	lz = Color3.fromRGB(96, 220, 255),
	sq = Color3.fromRGB(120, 255, 160),
	down = Color3.fromRGB(255, 210, 90),
}

local function paint()
	local heightsRaw = workspace:GetAttribute("GF_MapHeights")
	local metaRaw = workspace:GetAttribute("GF_MapMeta")
	if type(heightsRaw) ~= "string" or type(metaRaw) ~= "string" then
		readout.Text = "no mission telemetry"
		return
	end
	local ox, oz, span, minH, maxH = metaRaw:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
	ox, oz, span, minH, maxH = tonumber(ox), tonumber(oz), tonumber(span), tonumber(minH), tonumber(maxH)
	if not (ox and oz and span and minH and maxH) then
		readout.Text = "bad telemetry"
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
			local shade = 0.16 + t * 0.42
			cell.BackgroundColor3 = Color3.new(shade * 0.55, shade * 0.78, shade * 0.62)
		end
	end
	local markerRaw = workspace:GetAttribute("GF_MapMarkers")
	local placed = 0
	for tag, x, z in (type(markerRaw) == "string") and markerRaw:gmatch("([^,;]+),([^,;]+),([^,;]+)") or function() return nil end do
		local wx, wz = tonumber(x), tonumber(z)
		if wx and wz then
			local u = math.clamp((wx - (ox - span / 2)) / span, 0, 1)
			local v = math.clamp((wz - (oz - span / 2)) / span, 0, 1)
			local box = markerFor(tag)
			box.Position = UDim2.fromOffset(u * SIZE, v * SIZE)
			box.BackgroundColor3 = COLORS[tag] or COLORS.sq
			box.Visible = true
			placed += 1
		end
	end
	for tag, box in pairs(markers) do
		if not markerRaw or not markerRaw:find(tag .. ",", 1, true) then
			box.Visible = false
		end
	end
	readout.Text = string.format("origin %.0f,%.0f  span %.0fm  relief %.0f-%.0f  contacts %d", ox, oz, span, minH, maxH, placed)
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

