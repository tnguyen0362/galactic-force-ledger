--!nonstrict
-- Mission clock and grenade charges. Both existed in server state and neither was on screen: the timer
-- only lived inside mission state, and grenade charges were an invisible player attribute.
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "GF_StatusStrip"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 4
gui.Parent = player:WaitForChild("PlayerGui")

local function makeLabel(text, position, colour, size)
	local label = Instance.new("TextLabel")
	label.Text = text
	label.Size = UDim2.fromOffset(size.X, size.Y)
	label.Position = position
	label.BackgroundColor3 = Color3.fromRGB(10, 16, 22)
	label.BackgroundTransparency = 0.35
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = colour
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = label
	return label
end

local timerLabel = makeLabel("MISSION --:--", UDim2.new(1, -196, 0, 12 + 156 + 6), Color3.fromRGB(220, 230, 240), Vector2.new(196, 24))
local grenadeLabel = makeLabel("GRENADE -", UDim2.new(1, -196, 0, 12 + 156 + 34), Color3.fromRGB(180, 220, 255), Vector2.new(196, 24))

-- Loot feed: stacking deltas from SalvageChanged (LootCollected carries the same payload), plus a squad
-- count. Both were invisible before: the HUD had a running total and nothing else.
local squadLabel = makeLabel("SQUAD 1", UDim2.new(1, -196, 0, 12 + 156 + 62), Color3.fromRGB(200, 220, 240), Vector2.new(196, 22))
local feedRows = {}
for index = 1, 4 do
	local row = Instance.new("TextLabel")
	row.Size = UDim2.fromOffset(196, 18)
	row.Position = UDim2.new(1, -196, 0, 12 + 156 + 88 + (index - 1) * 19)
	row.BackgroundTransparency = 1
	row.Font = Enum.Font.GothamMedium
	row.TextSize = 12
	row.TextColor3 = Color3.fromRGB(190, 226, 250)
	row.TextXAlignment = Enum.TextXAlignment.Right
	row.Text = ""
	row.Parent = gui
	feedRows[index] = row
end

local entries = {}
local function redrawFeed()
	for index, row in ipairs(feedRows) do
		local entry = entries[index]
		if entry then
			row.Text = entry.count > 1 and string.format("+%d %s x%d", entry.amount, entry.kind, entry.count) or string.format("+%d %s", entry.amount, entry.kind)
			row.TextTransparency = entry.alpha or 0
		else
			row.Text = ""
		end
	end
	local summary = {}
	for _, row in ipairs(feedRows) do
		table.insert(summary, row.Text)
	end
	gui:SetAttribute("GF_LootFeed", table.concat(summary, "|"))
end

local function pushLoot(kind, amount)
	if type(kind) ~= "string" or type(amount) ~= "number" or amount <= 0 then
		return
	end
	local top = entries[1]
	if top and top.kind == kind then
		top.count += 1
		top.amount += amount
		top.born = os.clock()
	else
		table.insert(entries, 1, { kind = kind, amount = amount, count = 1, born = os.clock(), alpha = 0 })
		while #entries > 4 do
			table.remove(entries)
		end
	end
	redrawFeed()
end

game:GetService("ReplicatedStorage").GF.Remotes.LootCollected.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" then
		pushLoot(payload.kind or "salvage", tonumber(payload.amount) or 0)
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		local changed = false
		for _, entry in ipairs(entries) do
			local age = os.clock() - entry.born
			if age > 4 then
				entry.alpha = math.min(1, (age - 4) / 2)
				changed = true
			end
		end
		while entries[#entries] and (entries[#entries].alpha or 0) >= 1 do
			table.remove(entries)
			changed = true
		end
		if changed then
			redrawFeed()
		end
		local squad = workspace:GetAttribute("GF_SquadCount")
		squadLabel.Text = string.format("SQUAD %d", tonumber(squad) or 1)
		gui:SetAttribute("GF_SquadText", squadLabel.Text)
	end
end)

local AMBER = Color3.fromRGB(255, 200, 90)
local RED = Color3.fromRGB(255, 110, 100)
local NORMAL = Color3.fromRGB(220, 230, 240)

task.spawn(function()
	while true do
		task.wait(0.25)
		-- the mission clock is only meaningful to deployed participants; station crew saw a
		-- permanent countdown leaking into the concourse HUD (capture-audit V2026-11).
		local participant = player:GetAttribute("GF_MissionParticipant") == true
		local remaining = tonumber(workspace:GetAttribute("GF_MissionRemaining"))
		if participant and remaining and remaining > 0 then
			local minutes = math.floor(remaining / 60)
			local seconds = remaining % 60
			timerLabel.Text = string.format("MISSION %d:%02d", minutes, seconds)
			timerLabel.TextColor3 = (remaining <= 60 and RED) or (remaining <= 300 and AMBER) or NORMAL
			timerLabel.Visible = true
		elseif participant then
			timerLabel.Text = "MISSION --:--"
			timerLabel.TextColor3 = NORMAL
			timerLabel.Visible = true
		else
			timerLabel.Visible = false
		end
		local charges = player:GetAttribute("GrenadeCharges")
		grenadeLabel.Visible = participant
		grenadeLabel.Text = string.format("GRENADE x%d", tonumber(charges) or 0)
		grenadeLabel.TextColor3 = (tonumber(charges) or 0) > 0 and Color3.fromRGB(180, 220, 255) or Color3.fromRGB(150, 150, 150)
		gui:SetAttribute("GF_TimerText", timerLabel.Text)
		gui:SetAttribute("GF_TimerColor", math.floor(timerLabel.TextColor3.R * 255) .. "," .. math.floor(timerLabel.TextColor3.G * 255) .. "," .. math.floor(timerLabel.TextColor3.B * 255))
		gui:SetAttribute("GF_GrenadeText", grenadeLabel.Text)
	end
end)

