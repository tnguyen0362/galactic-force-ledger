--!nonstrict
-- Mission clock and grenade charges. Both existed in server state and neither was on screen: the timer
-- only lived inside mission state, and grenade charges were an invisible player attribute.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tokens = require(ReplicatedStorage.GF.Shared.UI.Tokens)
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "GF_StatusStrip"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 4
gui.Parent = player:WaitForChild("PlayerGui")

-- Hard-edged readout plate: graphite ground, steel rule, cyan rail, and a small angled
-- end mark. The strip is compact, but every state line clears console-distance readability.
local function applyStripChrome(label, accent)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Tokens.Color.border
	stroke.Transparency = 0.36
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label
	local rail = Instance.new("Frame")
	rail.Name = "AccentRail"
	rail.Size = UDim2.new(0, 3, 1, -8)
	rail.Position = UDim2.fromOffset(0, 4)
	rail.BackgroundColor3 = accent or Tokens.Color.techCyan
	rail.BorderSizePixel = 0
	rail.Parent = label
	local endMark = Instance.new("Frame")
	endMark.Name = "EndMark"
	endMark.Size = UDim2.fromOffset(13, 2)
	endMark.Position = UDim2.new(1, -17, 0, 4)
	endMark.Rotation = -32
	endMark.BackgroundColor3 = accent or Tokens.Color.techCyan
	endMark.BackgroundTransparency = 0.15
	endMark.BorderSizePixel = 0
	endMark.Parent = label
end

local function setStripAccent(label, color)
	for _, child in label:GetChildren() do
		if child:IsA("Frame") and (child.Name == "AccentRail" or child.Name == "EndMark") then
			child.BackgroundColor3 = color
		end
	end
end

local function makeLabel(text, position, colour, size, accent)
	local label = Instance.new("TextLabel")
	label.Text = text
	label.Size = UDim2.fromOffset(size.X, size.Y)
	label.Position = position
	label.BackgroundColor3 = Tokens.Color.panelInset
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.Font = Tokens.Type.fontBold
	label.TextSize = 15
	label.TextColor3 = colour
	label.TextStrokeTransparency = 0.68
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = gui
	applyStripChrome(label, accent)
	return label
end

local timerLabel = makeLabel("MISSION --:--", UDim2.new(1, -236, 0, 12 + 108 + 6), Tokens.Color.textPrimary, Vector2.new(220, 28), Tokens.Color.warning)
local grenadeLabel = makeLabel("GRENADE -", UDim2.new(1, -236, 0, 12 + 108 + 34), Tokens.Color.textAccent, Vector2.new(220, 28), Tokens.Color.techCyan)

-- Loot feed: stacking deltas from SalvageChanged (LootCollected carries the same payload), plus a squad
-- count. Both were invisible before: the HUD had a running total and nothing else.
local squadLabel = makeLabel("SQUAD 1", UDim2.new(1, -236, 0, 12 + 108 + 62), Tokens.Color.textPrimary, Vector2.new(220, 26), Tokens.Color.steel)
local feedRows = {}
for index = 1, 4 do
	local row = Instance.new("TextLabel")
	row.Size = UDim2.fromOffset(220, 19)
	row.Position = UDim2.new(1, -236, 0, 12 + 108 + 92 + (index - 1) * 20)
	row.BackgroundTransparency = 1
	row.Font = Tokens.Type.font
	row.TextSize = 13
	row.TextColor3 = Tokens.Color.textAccent
	row.TextStrokeTransparency = 0.68
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

game:GetService("ReplicatedStorage").GF.Remotes.LootCollected.OnClientEvent:Connect(function(payload, amount)
	if type(payload) == "table" then
		pushLoot(payload.kind or "salvage", tonumber(payload.amount) or 0)
	else
		-- LootService fires (kind, amount, position) as positional remote arguments.
		pushLoot(payload, tonumber(amount) or 0)
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
		local tickets = tonumber(workspace:GetAttribute("GF_ReinforcementTickets")) or 0
		-- plain language (owner report: "wtf is a ticket"): the number is the squad's shared
		-- respawn budget — when it hits zero, death is final this operation
		squadLabel.Text = string.format("SQUAD %d · RESPAWNS %d", tonumber(squad) or 1, tickets)
		local squadColor = tickets <= 0 and Tokens.Color.danger or (tickets <= 2 and Tokens.Color.warning or Tokens.Color.textPrimary)
		squadLabel.TextColor3 = squadColor
		setStripAccent(squadLabel, squadColor)
		gui:SetAttribute("GF_SquadText", squadLabel.Text)
	end
end)

local AMBER = Tokens.Color.warning
local RED = Tokens.Color.danger
local NORMAL = Tokens.Color.textPrimary

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
			local timerColor = (remaining <= 60 and RED) or (remaining <= 300 and AMBER) or NORMAL
			timerLabel.Text = string.format("MISSION %d:%02d", minutes, seconds)
			timerLabel.TextColor3 = timerColor
			setStripAccent(timerLabel, timerColor)
			timerLabel.Visible = true
		elseif participant then
			timerLabel.Text = "MISSION --:--"
			timerLabel.TextColor3 = NORMAL
			setStripAccent(timerLabel, AMBER)
			timerLabel.Visible = true
		else
			timerLabel.Visible = false
		end
		local charges = player:GetAttribute("GrenadeCharges")
		local chargeCount = tonumber(charges) or 0
		grenadeLabel.Visible = participant
		grenadeLabel.Text = string.format("GRENADE x%d", chargeCount)
		grenadeLabel.TextColor3 = chargeCount > 0 and Tokens.Color.textAccent or Tokens.Color.textDisabled
		setStripAccent(grenadeLabel, chargeCount > 0 and Tokens.Color.techCyan or Tokens.Color.textDisabled)
		gui:SetAttribute("GF_TimerText", timerLabel.Text)
		gui:SetAttribute("GF_TimerColor", math.floor(timerLabel.TextColor3.R * 255) .. "," .. math.floor(timerLabel.TextColor3.G * 255) .. "," .. math.floor(timerLabel.TextColor3.B * 255))
		gui:SetAttribute("GF_GrenadeText", grenadeLabel.Text)
	end
end)

