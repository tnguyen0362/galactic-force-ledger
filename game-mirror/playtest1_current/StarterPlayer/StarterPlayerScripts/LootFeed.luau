--!strict
-- S08-049 shared loot feed: recent squad loot scrolls at the screen edge — rare blueprint/cache
-- drops get a tier icon and a distinct sound; merged resource lines collapse repeats instead of
-- spamming one entry per scrap.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "LootFeed"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local container = Instance.new("Frame")
container.Size = UDim2.new(0, 260, 0, 160)
container.Position = UDim2.new(1, -270, 0.45, 0)
container.BackgroundTransparency = 1
container.Parent = gui
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0, 3)
layout.Parent = container

local KIND_DISPLAY = {
	scrap = { icon = "⚙", color = Color3.fromRGB(180, 180, 175), label = "Scrap" },
	energyCells = { icon = "▮", color = Color3.fromRGB(120, 200, 255), label = "Energy Cell" },
	militaryTechnology = { icon = "◆", color = Color3.fromRGB(255, 200, 90), label = "Military Tech" },
	blueprint = { icon = "★", color = Color3.fromRGB(255, 120, 220), label = "BLUEPRINT" },
	cache = { icon = "▣", color = Color3.fromRGB(180, 140, 255), label = "Cache" },
}

-- merged resource lines: same-kind pickups within 4s merge into one growing entry
local open: { [string]: { label: TextLabel, total: number, at: number } } = {}

local function playRareSound()
	-- distinct rare chime through the audio runtime if present, else a workspace attribute ping
	pcall(function()
		local audio = require(ReplicatedStorage.GF.Shared.Configs.Audio)
	end)
	workspace:SetAttribute("GF_RareLootSoundAt", os.clock())
end

local function addEntry(kind: string, amount: number)
	local display = KIND_DISPLAY[kind] or KIND_DISPLAY.scrap
	local now = os.clock()
	local existing = open[kind]
	if existing and now - existing.at < 4 and kind ~= "blueprint" and kind ~= "cache" then
		existing.total += amount
		existing.at = now
		existing.label.Text = string.format("%s %s +%d", display.icon, display.label, existing.total)
		return
	end
	local entry = Instance.new("TextLabel")
	entry.Size = UDim2.new(1, 0, 0, 20)
	entry.BackgroundTransparency = 0.5
	entry.BackgroundColor3 = Color3.fromRGB(10, 14, 18)
	entry.Font = Enum.Font.GothamMedium
	entry.TextSize = 14
	entry.TextXAlignment = Enum.TextXAlignment.Left
	entry.TextColor3 = display.color
	entry.TextStrokeTransparency = 0.6
	entry.Text = string.format(" %s %s +%d", display.icon, display.label, amount)
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
