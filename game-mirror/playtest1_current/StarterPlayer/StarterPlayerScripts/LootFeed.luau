--!strict
-- S08-049 shared loot feed: recent squad loot scrolls at the screen edge — rare blueprint/cache
-- drops get a tier icon and a distinct sound; merged resource lines collapse repeats instead of
-- spamming one entry per scrap.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Tokens = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Tokens"))

local Audio: any = nil
do
	local ok, result = pcall(function()
		return require(script.Parent.GFAudio)
	end)
	if ok then
		Audio = result
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "LootFeed"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local container = Instance.new("Frame")
container.Name = "FeedContainer"
container.Size = UDim2.new(0, 286, 0, 172)
container.Position = UDim2.new(1, -302, 0.44, 0)
container.BackgroundTransparency = 1
container.Parent = gui
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0, 4)
layout.Parent = container

local STEEL = Tokens.Color.steel
local CYAN = Tokens.Color.techCyan
local AMBER = Tokens.Color.warning
local CERAMIC = Tokens.Color.ceramic
local INSET = Tokens.Color.panelInset
local BORDER = Tokens.Color.border

local KIND_DISPLAY = {
	scrap = { icon = "▸", color = STEEL, label = "SCRAP" },
	energyCells = { icon = "▮", color = CYAN, label = "ENERGY CELL" },
	militaryTechnology = { icon = "◆", color = AMBER, label = "MILITARY TECH" },
	blueprint = { icon = "◈", color = AMBER, label = "BLUEPRINT" },
	cache = { icon = "▣", color = CERAMIC, label = "CACHE" },
}

-- merged resource lines: same-kind pickups within 4s merge into one growing entry
local open: { [string]: { label: TextLabel, total: number, at: number } } = {}

local function playRareSound()
	-- distinct rare chime through the audio runtime if present, else a workspace attribute ping
	if Audio then
		pcall(function()
			Audio.play("rare_loot")
		end)
	end
	workspace:SetAttribute("GF_RareLootSoundAt", os.clock())
end

local function paintEntry(entry: TextLabel, color: Color3)
	entry.BackgroundColor3 = INSET
	entry.BackgroundTransparency = 0.16
	entry.BorderSizePixel = 0
	entry.Font = Tokens.Type.font
	entry.TextSize = Tokens.Type.sizeSmall
	entry.TextXAlignment = Enum.TextXAlignment.Left
	entry.TextColor3 = color
	entry.TextTruncate = Enum.TextTruncate.AtEnd

	local stroke = Instance.new("UIStroke")
	stroke.Color = BORDER
	stroke.Transparency = 0.68
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = entry

	local edge = Instance.new("Frame")
	edge.Name = "TierEdge"
	edge.Size = UDim2.new(0, 3, 1, -8)
	edge.Position = UDim2.fromOffset(0, 4)
	edge.BackgroundColor3 = color
	edge.BackgroundTransparency = 0.18
	edge.BorderSizePixel = 0
	edge.Parent = entry

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = entry
end

local function addEntry(kind: string, amount: number)
	local display = KIND_DISPLAY[kind] or KIND_DISPLAY.scrap
	local now = os.clock()
	local existing = open[kind]
	if existing and now - existing.at < 4 and kind ~= "blueprint" and kind ~= "cache" then
		existing.total += amount
		existing.at = now
		existing.label.Text = string.format("%s  %s +%d", display.icon, display.label, existing.total)
		return
	end
	local entry = Instance.new("TextLabel")
	entry.Name = "Loot_" .. kind
	entry.Size = UDim2.new(1, 0, 0, 24)
	entry.Text = string.format("%s  %s +%d", display.icon, display.label, amount)
	paintEntry(entry, display.color)
	entry.Parent = container
	open[kind] = { label = entry, total = amount, at = now }
	if kind == "blueprint" or kind == "cache" or kind == "militaryTechnology" then
		playRareSound()
	end
	task.delay(6, function()
		if entry.Parent then
			entry:Destroy()
		end
		if open[kind] and open[kind].label == entry then
			open[kind] = nil
		end
	end)
end

local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local loot = remotes:WaitForChild("LootCollected")
loot.OnClientEvent:Connect(function(delta)
	if type(delta) == "table" and delta.kind and delta.amount then
		addEntry(tostring(delta.kind), tonumber(delta.amount) or 1)
	end
end)
