--!strict
-- Squad browser (Counteroffensive Stage 4 client surface, built on the Stage 5 design
-- system per owner directive). global listings + dispatch beacons in one scannable surface:
-- the player sees every forming squad across ALL servers and every active distress beacon,
-- and joins with one interaction. cross-server joins teleport; same-server joins are instant.
-- refresh cadence 5s while open — MemoryStore read budgets are sized for this.
local Tokens = require(game:GetService("ReplicatedStorage").GF.Shared.UI.Tokens)
local Components = require(game:GetService("ReplicatedStorage").GF.Shared.UI.Components)
local MenuShell = require(game:GetService("ReplicatedStorage").GF.Shared.UI.MenuShell)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")

local shell = MenuShell.new("GF_SquadBrowser", 10)
require(game:GetService("ReplicatedStorage").GF.Shared.UI.MenuController).register(shell)

-- war roster for the deploy/form pickers
local WarModel = require(game:GetService("ReplicatedStorage").GF.Shared.WarModel)
local WarOperations = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.WarOperations)
local Missions = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Missions)

-- ---------------------------------------------------------------------------
-- squads section: global listings, most urgent beacons pinned on top
-- ---------------------------------------------------------------------------
local browserState = {
	listContainer = nil :: ScrollingFrame?,
	statusLine = nil :: TextLabel?,
	refreshToken = 0, -- stale-async guard: slower responses never overwrite newer data
}

shell:registerSection("SQUADS", "◈", function(page)
	Components.text(page, "ACTIVE OPERATIONS — ALL SERVERS", "title",
		UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 0))
	local statusLine = Components.text(page, "", "caption",
		UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 34))
	browserState.statusLine = statusLine
	local list = Components.list(page,
		UDim2.new(1, 0, 1, -60), UDim2.new(0, 0, 0, 58))
	browserState.listContainer = list
end)

-- ---------------------------------------------------------------------------
-- DEPLOY section: the mission screen rework (owner directive — the legacy cramped panel is
-- replaced, not reskinned). full-screen theatre-first layout: regions with live war status
-- down the left, the region's operations center-stage, difficulty + deploy at the bottom.
-- fires the exact wire payload the legacy panel did — server behavior unchanged.
-- ---------------------------------------------------------------------------
local DIFFICULTIES = { "Easy", "Normal", "Hard", "Extreme" }
-- Presentation mirror of StationService's server-side rank gates. The server remains
-- authoritative; when the profile push has not arrived yet every segment stays selectable
-- and the refusal path explains the gate instead of pretending knowledge the client lacks.
local DIFFICULTY_RANK = { Easy = 1, Normal = 3, Hard = 6, Extreme = 14 }

local STATUS_SHORT = {
	ascendancy_dominance = "ASCENDANCY",
	contested_theater = "CONTESTED",
	human_infiltration = "INFILTRATION",
	gf_offensive = "GF OFFENSIVE",
	established_superiority = "SUPERIORITY",
}

local BIOME_FEATURES = {
	forest = { "the northern ridge", "the black-canopy approaches", "the riverine chokepoint" },
	ash = { "the cinder flats", "the basalt ridge", "the ash-storm corridor" },
	frost = { "the glacier line", "the whiteout pass", "the frozen causeway" },
	iron = { "the foundry sprawl", "the slag-yard perimeter", "the magnetite ridge" },
}

local FAMILY_FLAVOR = {
	Conquest = {
		"Command wants the ground intact — expect immediate counterpressure once the perimeter breaks.",
		"Orbital fire cannot hold terrain. Boots on the console decide whether this theater moves.",
		"Every captured meter becomes a firebase; the Ascendancy will answer fast.",
	},
	Recovery = {
		"The payload degrades under enemy custody; recovery teams go in fast, loud, and together.",
		"Fleet intelligence is still tracing the beacon. Whatever survived cannot remain behind the line.",
		"Time in hostile hands compounds the loss. Extract the asset before the cordon closes.",
	},
	Elimination = {
		"The target is a command multiplier. Remove it and the local front loses coordination.",
		"High-value assets rarely stay exposed. This window closes the moment the first shot lands.",
		"Kill teams report overlapping escorts; expect resistance to spike after the first confirmation.",
	},
	Sabotage = {
		"Logistics nodes are hardened but brittle — one clean breach cascades through the front.",
		"Blackout teams have mapped the supply lattice. Cutting it here starves the counteroffensive.",
		"The target feeds multiple forward sectors. Expect reinforced patrols and little margin for noise.",
	},
	Defense = {
		"Losing the site collapses local coverage. Hold long enough for fleet guns to reposition.",
		"The line bends here tonight. Every second held buys evacuation corridors behind you.",
		"Enemy pressure is converging on the position; a clean defense turns their momentum.",
	},
	Default = {
		"Theater command has marked this as a decisive commitment. Expect contact soon after insertion.",
	},
}

local SITUATION_LINES = {
	enemy = {
		"Ascendancy resistance stiffening along %s; forward squads report overlapping fire lanes.",
		"Enemy reinforcement columns are massing beyond %s while pickets probe our screen.",
		"Occupation batteries are registering %s; expect interdiction fire on approach.",
	},
	contested = {
		"Neither line holds for long near %s; artillery fire is walking the approaches.",
		"Ascendancy counterattacks probe %s while GF fireteams contest every crossing.",
		"Signals traffic spiked around %s. Both sides are feeding reserves into the same corridor.",
	},
	infiltration = {
		"Small GF cells are testing the perimeter near %s; occupation forces are reacting piecemeal.",
		"Reconnaissance teams have blind spots opening around %s, but the enemy net is still intact.",
		"Forward observers are quietly marking targets across %s ahead of the next push.",
	},
	human = {
		"GF forward elements are exploiting gaps around %s; enemy withdrawal signs are visible.",
		"Firebases have overlapping coverage past %s, and resistance is fragmenting.",
		"Ascendancy fallback traffic is bunching near %s under sustained orbital interdiction.",
	},
}

local function stableHash(text: string): number
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + string.byte(text, i)) % 2147483647
	end
	return h
end

local function regionDisplayName(rid: string): string
	return string.upper((rid:gsub("(%l)(%u)", "%1 %2")))
end

local function upperWords(text: string): string
	return string.upper((text:gsub("_", " ")))
end

local function statusShort(status: string): string
	return STATUS_SHORT[status] or upperWords(status)
end

local function liveStatus(rid: string): string
	local raw = workspace:GetAttribute("GF_WarState_" .. rid .. "_Status")
	if type(raw) == "string" and raw ~= "" then
		return raw
	end
	return "ascendancy_dominance"
end

local function liveControl(rid: string): number?
	local raw = workspace:GetAttribute("GF_WarControl_" .. rid)
	local control = tonumber(raw)
	if control then
		if control > 1 then
			control = control / 100
		end
		return math.clamp(control, 0, 1)
	end
	-- Transition-era fallback: WarStateService publishes the underlying force values even
	-- when the compact control roll-up is absent. H/(H+E) is the force-ratio read the war
	-- model itself classifies from, and it keeps the table live instead of inventing data.
	local human = tonumber(workspace:GetAttribute("GF_WarState_" .. rid .. "_H"))
	local enemy = tonumber(workspace:GetAttribute("GF_WarState_" .. rid .. "_E"))
	if human and enemy and human + enemy > 0 then
		return math.clamp(human / (human + enemy), 0, 1)
	end
	return nil
end

local function liveFront(rid: string): string
	local raw = workspace:GetAttribute("GF_WarFront_" .. rid)
	if type(raw) == "string" and raw ~= "" then
		return string.lower((raw:gsub("_", " ")))
	end
	if raw ~= nil then
		return string.lower(tostring(raw))
	end
	local control = liveControl(rid)
	if control then
		if control >= 0.65 then
			return "gf advance"
		end
		if control <= 0.35 then
			return "enemy pressure"
		end
	end
	return "contested"
end

local function theaterFeature(rid: string, seed: number): string
	local territory = WarModel.TERRITORIES[rid]
	local biome = territory and territory.biome or "forest"
	local features = BIOME_FEATURES[biome] or BIOME_FEATURES.forest
	return features[(seed % #features) + 1]
end

local function operationFlavor(opId: string, family: string, region: string): string
	local lines = FAMILY_FLAVOR[family] or FAMILY_FLAVOR.Default
	return lines[(stableHash(opId .. "|" .. region) % #lines) + 1]
end

-- Short theater readout. The seed deliberately uses a 10% control band rather than the
-- exact value: the sentence changes when the war meaningfully changes, never frame-to-frame.
local function situationReadout(rid: string, control: number?, front: string, status: string): string
	local pct = control and math.floor(control * 100 + 0.5) or 50
	local band = math.floor(pct / 10)
	local seedText = table.concat({ rid, status, front, tostring(band) }, "|")
	local seed = stableHash(seedText)
	local feature = theaterFeature(rid, seed)

	local posture = "contested"
	if control ~= nil or workspace:GetAttribute("GF_WarState_" .. rid .. "_Status") ~= nil then
		if status == "established_superiority" or status == "gf_offensive" or pct >= 65 then
			posture = "human"
		elseif status == "ascendancy_dominance" or pct < 35 then
			posture = "enemy"
		elseif status == "human_infiltration" then
			posture = "infiltration"
		end
	end
	local lines = SITUATION_LINES[posture] or SITUATION_LINES.contested
	local generated = string.format(lines[(math.floor(seed / 11) % #lines) + 1], feature)

	local assessment
	if control == nil then
		assessment = "Telemetry incomplete — treat this theater as contested until the next fleet snapshot."
	elseif pct >= 65 then
		assessment = "GF holds the initiative; another successful operation can break the theater open."
	elseif pct >= 45 then
		assessment = "Control is balanced. Every completed operation visibly moves this front."
	elseif pct >= 25 then
		assessment = "Ascendancy logistics still dominate, but the pressure line is beginning to bend."
	else
		assessment = "Enemy control is entrenched. Expect hardened resistance and limited support windows."
	end
	return assessment .. "\n" .. generated
end

-- The shared Components.button owns hover tweens that deliberately return to the unselected
-- color. Stateful war-table controls therefore use the same token language but paint their
-- own state after input transitions; amber selection would otherwise vanish on mouse-out.
local function createWarButton(parent: Instance, label: string, textSize: number?): TextButton
	local button = Instance.new("TextButton")
	button.Name = "WarTableButton"
	button.Size = UDim2.new(1, 0, 0, Tokens.Size.buttonHeight)
	button.BackgroundColor3 = Tokens.Color.panelRaised
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Active = true
	button.Selectable = true
	button.Font = Tokens.Type.font
	button.TextSize = textSize or Tokens.Type.sizeBody
	button.TextColor3 = Tokens.Color.textPrimary
	button.Text = label
	button.TextWrapped = true
	button.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = Tokens.Color.steel
	stroke.Transparency = 0.7
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	return button
end

local function bindWarButton(button: TextButton, repaint: () -> ())
	button.MouseEnter:Connect(function()
		button:SetAttribute("GF_Hover", true)
		repaint()
	end)
	button.MouseLeave:Connect(function()
		button:SetAttribute("GF_Hover", false)
		button:SetAttribute("GF_Pressed", false)
		repaint()
	end)
	button.MouseButton1Down:Connect(function()
		button:SetAttribute("GF_Pressed", true)
		repaint()
	end)
	button.MouseButton1Up:Connect(function()
		button:SetAttribute("GF_Pressed", false)
		repaint()
	end)
	button.SelectionGained:Connect(function()
		button:SetAttribute("GF_Focused", true)
		repaint()
	end)
	button.SelectionLost:Connect(function()
		button:SetAttribute("GF_Focused", false)
		repaint()
	end)
end

local function paintWarButton(button: TextButton, selected: boolean, locked: boolean?)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	local hover = button:GetAttribute("GF_Hover") == true or button:GetAttribute("GF_Focused") == true
	local pressed = button:GetAttribute("GF_Pressed") == true
	if locked == true then
		button.BackgroundColor3 = Tokens.Color.panelInset
		button.TextColor3 = Tokens.Color.textDisabled
		if stroke then
			stroke.Color = Tokens.Color.danger
			stroke.Transparency = 0.72
			stroke.Thickness = 1
		end
	elseif selected then
		button.BackgroundColor3 = Tokens.Color.accentSelect
		button.TextColor3 = Tokens.Color.panelInset
		if stroke then
			stroke.Color = Tokens.Color.accentSelect
			stroke.Transparency = 0
			stroke.Thickness = 2
		end
	elseif pressed then
		button.BackgroundColor3 = Tokens.Color.navy
		button.TextColor3 = Tokens.Color.textAccent
		if stroke then
			stroke.Color = Tokens.Color.borderFocus
			stroke.Transparency = 0.05
			stroke.Thickness = 1
		end
	elseif hover then
		button.BackgroundColor3 = Tokens.Color.navy
		button.TextColor3 = Tokens.Color.textPrimary
		if stroke then
			stroke.Color = Tokens.Color.borderFocus
			stroke.Transparency = 0.25
			stroke.Thickness = 1
		end
	else
		button.BackgroundColor3 = Tokens.Color.panelRaised
		button.TextColor3 = Tokens.Color.textPrimary
		if stroke then
			stroke.Color = Tokens.Color.steel
			stroke.Transparency = 0.7
			stroke.Thickness = 1
		end
	end
end

local function operationDisplayName(opId: string): string
	return (WarOperations.DisplayName and WarOperations.DisplayName[opId]) or opId
end

local deployState = {
	region = "VerdantReach",
	operationId = nil :: string?,
	difficulty = "Normal",
	rank = nil :: number?,
	committing = false,
	commitToken = 0,
	opButtons = {} :: { [string]: TextButton },
	opRows = {} :: { [string]: Frame },
	regionButtons = {} :: { [string]: TextButton },
	regionStripes = {} :: { [string]: Frame },
	diffButtons = {} :: { [string]: TextButton },
	statusLine = nil :: TextLabel?,
	opList = nil :: ScrollingFrame?,
}

shell:registerSection("DEPLOY", "\u{25bc}", function(page)
	-- helldivers 2 war-table structure, copied from the reference per owner directive:
	-- theater strip across the top, operation panels with mission intel down the left,
	-- theater status readout right (control bar = liberation-bar equivalent), difficulty
	-- bar across the bottom in fixed order with amber selection, wide deploy confirmation
	-- at the very bottom. no invention.
	Components.text(page, "DEPLOYMENT", "title",
		UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 0))
	local statusLine = Components.text(page, "", "caption",
		UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 38))
	deployState.statusLine = statusLine

	local function setStatus(text: string, color: Color3?)
		statusLine.Text = text
		statusLine.TextColor3 = color or Tokens.Color.textSecondary
	end

	-- theater strip: regions as a horizontal selector row across the top — hd2 picks the
	-- theater then the operation in one read, no nested list-of-lists. It scrolls sideways
	-- rather than clipping the farthest regions on narrow screens.
	local theaterRow = Instance.new("ScrollingFrame")
	theaterRow.Name = "TheaterRow"
	theaterRow.Size = UDim2.new(1, 0, 0, 52)
	theaterRow.Position = UDim2.new(0, 0, 0, 60)
	theaterRow.BackgroundTransparency = 1
	theaterRow.BorderSizePixel = 0
	theaterRow.ScrollBarThickness = 3
	theaterRow.ScrollBarImageColor3 = Tokens.Color.steel
	theaterRow.ScrollingDirection = Enum.ScrollingDirection.X
	theaterRow.AutomaticCanvasSize = Enum.AutomaticSize.X
	theaterRow.CanvasSize = UDim2.new(0, 0, 0, 0)
	theaterRow.Parent = page
	local theaterLayout = Instance.new("UIListLayout")
	theaterLayout.FillDirection = Enum.FillDirection.Horizontal
	theaterLayout.Padding = UDim.new(0, Tokens.Space.xs)
	theaterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	theaterLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	theaterLayout.Parent = theaterRow

	-- operations column (left, wide): one panel per operation, intel visible on the row
	local opList = Components.list(page,
		UDim2.new(1, -290, 1, -240), UDim2.new(0, 0, 0, 120))
	deployState.opList = opList

	-- theater status panel (right, narrow): the war read for the selected region
	local intelPanel = Components.panel(page,
		UDim2.new(0, 280, 1, -240), UDim2.new(1, -280, 0, 120))
	local panelPadding = intelPanel:FindFirstChildOfClass("UIPadding")
	if panelPadding then
		panelPadding:Destroy()
	end

	Components.text(intelPanel, "THEATER STATUS", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 10))
	local regionTitle = Components.text(intelPanel, "", "body",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 22), UDim2.new(0, Tokens.Space.md, 0, 30))
	regionTitle.Font = Tokens.Type.fontBold
	local stateLabel = Components.text(intelPanel, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 56))
	local controlLabel = Components.text(intelPanel, "", "title",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 28), UDim2.new(0, Tokens.Space.md, 0, 78))

	-- control bar: thin sharp track, status-colored fill — the liberation read
	local barTrack = Instance.new("Frame")
	barTrack.Name = "ControlTrack"
	barTrack.Size = UDim2.new(1, -Tokens.Space.md * 2, 0, 8)
	barTrack.Position = UDim2.new(0, Tokens.Space.md, 0, 112)
	barTrack.BackgroundColor3 = Tokens.Color.panelInset
	barTrack.BorderSizePixel = 0
	barTrack.Parent = intelPanel
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = Tokens.Color.border
	trackStroke.Transparency = 0.55
	trackStroke.Thickness = 1
	trackStroke.Parent = barTrack
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(0.5, 0, 1, 0)
	barFill.BackgroundColor3 = Tokens.Color.accentSelect
	barFill.BorderSizePixel = 0
	barFill.Parent = barTrack
	local midpoint = Instance.new("Frame")
	midpoint.Name = "Midpoint"
	midpoint.Size = UDim2.new(0, 1, 1, 0)
	midpoint.Position = UDim2.new(0.5, 0, 0, 0)
	midpoint.BackgroundColor3 = Tokens.Color.textSecondary
	midpoint.BackgroundTransparency = 0.35
	midpoint.BorderSizePixel = 0
	midpoint.ZIndex = 2
	midpoint.Parent = barTrack
	local barLabel = Components.text(intelPanel, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 126))
	local frontLabel = Components.text(intelPanel, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 150))
	local forceLabel = Components.text(intelPanel, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 170))
	local divider = Instance.new("Frame")
	divider.Name = "IntelDivider"
	divider.Size = UDim2.new(1, -Tokens.Space.md * 2, 0, 1)
	divider.Position = UDim2.new(0, Tokens.Space.md, 0, 196)
	divider.BackgroundColor3 = Tokens.Color.border
	divider.BackgroundTransparency = 0.35
	divider.BorderSizePixel = 0
	divider.Parent = intelPanel
	Components.text(intelPanel, "SITUATION READOUT", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 206))
	local situationBody = Components.text(intelPanel, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 104), UDim2.new(0, Tokens.Space.md, 0, 226))
	situationBody.TextWrapped = true
	situationBody.TextXAlignment = Enum.TextXAlignment.Left
	situationBody.TextYAlignment = Enum.TextYAlignment.Top
	situationBody.TextColor3 = Tokens.Color.textPrimary

	local function updateTheaterIntel(rid: string)
		local control = liveControl(rid)
		local front = liveFront(rid)
		local status = liveStatus(rid)
		local pct = control and math.floor(control * 100 + 0.5) or nil
		local statusColor = Tokens.StatusColor[status] or Tokens.Color.textSecondary

		regionTitle.Text = regionDisplayName(rid)
		stateLabel.Text = "STATE  " .. statusShort(status)
		stateLabel.TextColor3 = statusColor
		controlLabel.Text = pct and string.format("CONTROL %d%%", pct) or "CONTROL UNKNOWN"
		controlLabel.TextColor3 = pct and Tokens.Color.textPrimary or Tokens.Color.textSecondary
		barFill.Size = UDim2.new(control or 0.5, 0, 1, 0)
		barFill.BackgroundColor3 = statusColor
		barLabel.Text = pct and string.format("LIBERATION INDEX %d%%", pct) or "AWAITING ORBITAL TELEMETRY"
		frontLabel.Text = "FRONT  " .. string.upper(front)
		local frontKey = string.lower(front)
		if string.find(frontKey, "enemy") or string.find(frontKey, "contested") then
			frontLabel.TextColor3 = Tokens.Color.warning
		elseif string.find(frontKey, "gf") or string.find(frontKey, "advance") then
			frontLabel.TextColor3 = Tokens.Color.techCyan
		else
			frontLabel.TextColor3 = Tokens.Color.textSecondary
		end

		local human = tonumber(workspace:GetAttribute("GF_WarState_" .. rid .. "_H"))
		local enemy = tonumber(workspace:GetAttribute("GF_WarState_" .. rid .. "_E"))
		if human and enemy then
			forceLabel.Text = string.format("FORCE BALANCE  GF %.2f · ASC %.2f", human, enemy)
		else
			forceLabel.Text = "FORCE BALANCE  NO SNAPSHOT"
		end
		forceLabel.TextColor3 = Tokens.Color.textSecondary
		situationBody.Text = situationReadout(rid, control, front, status)
	end

	local function paintTheaterButtons()
		for rid, button in pairs(deployState.regionButtons) do
			local status = liveStatus(rid)
			button.Text = regionDisplayName(rid) .. "\n" .. statusShort(status)
			paintWarButton(button, rid == deployState.region, false)
			local stripe = deployState.regionStripes[rid]
			if stripe then
				stripe.BackgroundColor3 = Tokens.StatusColor[status] or Tokens.Color.steel
			end
		end
	end

	local function paintOperationRows()
		for opId, button in pairs(deployState.opButtons) do
			local selected = opId == deployState.operationId
			button.Text = selected and "COMMITTED" or "COMMIT"
			paintWarButton(button, selected, false)
			local row = deployState.opRows[opId]
			if row then
				row.BackgroundColor3 = selected and Tokens.Color.navy or Tokens.Color.panelInset
				local stroke = row:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = selected and Tokens.Color.accentSelect or Tokens.Color.border
					stroke.Transparency = selected and 0 or 0.65
					stroke.Thickness = selected and 2 or 1
				end
				local edge = row:FindFirstChild("SelectionEdge")
				if edge and edge:IsA("Frame") then
					edge.Visible = selected
				end
				local title = row:FindFirstChild("Text_body")
				if title and title:IsA("TextLabel") then
					title.TextColor3 = selected and Tokens.Color.warning or Tokens.Color.textPrimary
				end
			end
		end
	end

	local function updateCommitmentStatus()
		if deployState.committing then
			return
		end
		if deployState.operationId then
			local name = operationDisplayName(deployState.operationId)
			setStatus(string.upper(string.format("%s — %s theater — %s difficulty", name, regionDisplayName(deployState.region), deployState.difficulty)), Tokens.Color.warning)
		else
			setStatus("SELECT A THEATER OPERATION", Tokens.Color.textSecondary)
		end
	end

	local function selectOperation(opId: string)
		if deployState.committing then
			return
		end
		deployState.operationId = opId
		paintOperationRows()
		updateCommitmentStatus()
	end

	-- difficulty bar across the bottom: the reference's signature row. fixed order,
	-- equal segments, amber selection. Rank locks are shown when the profile push has
	-- supplied a rank; otherwise all segments remain selectable and the server verdict
	-- is allowed to explain the gate honestly.
	local diffBar = Instance.new("Frame")
	diffBar.Name = "DifficultyBar"
	diffBar.Size = UDim2.new(1, 0, 0, 52)
	diffBar.Position = UDim2.new(0, 0, 1, -112)
	diffBar.BackgroundTransparency = 1
	diffBar.Parent = page
	local diffLayout = Instance.new("UIListLayout")
	diffLayout.FillDirection = Enum.FillDirection.Horizontal
	diffLayout.Padding = UDim.new(0, Tokens.Space.xs)
	diffLayout.SortOrder = Enum.SortOrder.LayoutOrder
	diffLayout.Parent = diffBar

	local function difficultyLocked(difficulty: string): boolean
		local rank = deployState.rank
		return rank ~= nil and rank < (DIFFICULTY_RANK[difficulty] or 1)
	end

	local function refreshDiffSelection()
		-- A late profile push can reveal that the preselected segment is locked. Fall back to
		-- the highest open difficulty instead of leaving an impossible amber selection.
		if difficultyLocked(deployState.difficulty) then
			for i = #DIFFICULTIES, 1, -1 do
				if not difficultyLocked(DIFFICULTIES[i]) then
					deployState.difficulty = DIFFICULTIES[i]
					break
				end
			end
		end
		for _, difficulty in ipairs(DIFFICULTIES) do
			local chip = deployState.diffButtons[difficulty]
			if chip then
				local needed = DIFFICULTY_RANK[difficulty] or 1
				local locked = difficultyLocked(difficulty)
				local access
				if deployState.rank == nil then
					access = "RANK " .. tostring(needed)
				elseif locked then
					access = "LOCKED · RANK " .. tostring(needed)
				else
					access = "OPEN · RANK " .. tostring(needed)
				end
				chip.Text = string.upper(difficulty) .. "\n" .. access
				paintWarButton(chip, difficulty == deployState.difficulty, locked)
			end
		end
	end

	local segmentOffset = -math.ceil((Tokens.Space.xs * (#DIFFICULTIES - 1)) / #DIFFICULTIES)
	for diffIdx, difficulty in ipairs(DIFFICULTIES) do
		local chip = createWarButton(diffBar, string.upper(difficulty), Tokens.Type.sizeSmall)
		chip.Size = UDim2.new(1 / #DIFFICULTIES, segmentOffset, 1, 0)
		chip.LayoutOrder = diffIdx
		deployState.diffButtons[difficulty] = chip
		bindWarButton(chip, refreshDiffSelection)
		chip.Activated:Connect(function()
			if deployState.committing then
				return
			end
			if difficultyLocked(difficulty) then
				setStatus(string.upper(string.format("%s locked — requires military rank %d", difficulty, DIFFICULTY_RANK[difficulty] or 1)), Tokens.Color.warning)
				return
			end
			deployState.difficulty = difficulty
			refreshDiffSelection()
			updateCommitmentStatus()
		end)
	end

	-- wide deploy confirmation at the very bottom — the hellpod-equivalent commitment
	local deployBtn = createWarButton(page, "DEPLOY", Tokens.Type.sizeTitle)
	deployBtn.Size = UDim2.new(1, 0, 0, 52)
	deployBtn.Position = UDim2.new(0, 0, 1, -54)
	local deployVisualState = "ready"

	local function paintDeployButton()
		local stroke = deployBtn:FindFirstChildOfClass("UIStroke")
		local hover = deployBtn:GetAttribute("GF_Hover") == true or deployBtn:GetAttribute("GF_Focused") == true
		if deployVisualState == "pending" then
			deployBtn.BackgroundColor3 = Tokens.Color.accentSelect
			deployBtn.TextColor3 = Tokens.Color.panelInset
			if stroke then
				stroke.Color = Tokens.Color.accentSelect
				stroke.Transparency = 0
				stroke.Thickness = 2
			end
		elseif deployVisualState == "accepted" then
			deployBtn.BackgroundColor3 = Tokens.Color.success
			deployBtn.TextColor3 = Tokens.Color.panelInset
			if stroke then
				stroke.Color = Tokens.Color.success
				stroke.Transparency = 0
				stroke.Thickness = 2
			end
		elseif deployVisualState == "refused" then
			deployBtn.BackgroundColor3 = Tokens.Color.panelRaised
			deployBtn.TextColor3 = Tokens.Color.warning
			if stroke then
				stroke.Color = Tokens.Color.danger
				stroke.Transparency = 0.15
				stroke.Thickness = 2
			end
		else
			deployBtn.BackgroundColor3 = hover and Tokens.Color.navy or Tokens.Color.panelRaised
			deployBtn.TextColor3 = Tokens.Color.textAccent
			if stroke then
				stroke.Color = Tokens.Color.techCyan
				stroke.Transparency = hover and 0.1 or 0.4
				stroke.Thickness = 2
			end
		end
	end

	local function armDeployButton()
		deployState.committing = false
		deployVisualState = "ready"
		deployBtn.Text = "DEPLOY"
		deployBtn.Active = true
		paintDeployButton()
	end

	bindWarButton(deployBtn, paintDeployButton)
	paintDeployButton()

	deployBtn.Activated:Connect(function()
		if deployState.committing then
			return
		end
		if not deployState.operationId then
			setStatus("SELECT AN OPERATION BEFORE DEPLOYMENT", Tokens.Color.warning)
			return
		end
		if difficultyLocked(deployState.difficulty) then
			setStatus(string.upper(string.format("%s locked — requires military rank %d", deployState.difficulty, DIFFICULTY_RANK[deployState.difficulty] or 1)), Tokens.Color.warning)
			return
		end

		deployState.commitToken += 1
		local token = deployState.commitToken
		deployState.committing = true
		deployVisualState = "pending"
		deployBtn.Text = "DEPLOYING…"
		deployBtn.Active = false
		paintDeployButton()
		setStatus("HELLPOD COMMITMENT TRANSMITTED — AWAITING COMMAND CONFIRMATION", Tokens.Color.warning)
		remotes.RequestDeploy:FireServer({
			difficulty = deployState.difficulty,
			operationId = deployState.operationId,
		})

		-- Watchdog only: command normally answers through DeployStateChanged. If the packet
		-- never comes back, leave the war table open and re-arm instead of faking success.
		task.delay(8, function()
			if deployState.committing and deployState.commitToken == token then
				deployVisualState = "refused"
				deployState.committing = false
				deployBtn.Text = "NO RESPONSE — RETRY"
				deployBtn.Active = true
				paintDeployButton()
				setStatus("NO RESPONSE FROM COMMAND — DEPLOYMENT UNCONFIRMED", Tokens.Color.warning)
			end
		end)
	end)

	-- Honest deploy verdicts. Zone publications use the same remote but carry no boolean ok,
	-- so they are ignored here; only verdicts while this war table has a pending commit apply.
	task.spawn(function()
		local deployStateRemote = remotes:WaitForChild("DeployStateChanged")
		if deployStateRemote and deployStateRemote:IsA("RemoteEvent") then
			deployStateRemote.OnClientEvent:Connect(function(payload)
				if type(payload) ~= "table" or type(payload.ok) ~= "boolean" then
					return
				end
				if not deployState.committing then
					return
				end
				if payload.ok then
					local token = deployState.commitToken
					deployVisualState = "accepted"
					deployBtn.Text = "DEPLOYMENT ACCEPTED"
					deployBtn.Active = false
					paintDeployButton()
					setStatus("HELLPOD LAUNCH CONFIRMED — GOOD HUNTING", Tokens.Color.success)
					task.delay(0.8, function()
						if deployState.commitToken == token and deployVisualState == "accepted" then
							if shell.visible then
								shell:close()
							end
							armDeployButton()
						end
					end)
				else
					local reason = tostring(payload.reason or "unknown reason")
					deployState.committing = false
					deployVisualState = "refused"
					deployBtn.Text = "REFUSED — RETRY"
					deployBtn.Active = true
					paintDeployButton()
					setStatus("DEPLOYMENT REFUSED — " .. reason, Tokens.Color.danger)
				end
			end)
		end
	end)

	-- Rank is presentation-only. The initial profile push normally arrives at spawn; until
	-- it does, gates are labeled by requirement but not enforced locally.
	local profileUpdated = remotes:FindFirstChild("ProfileUpdated")
	if profileUpdated and profileUpdated:IsA("RemoteEvent") then
		profileUpdated.OnClientEvent:Connect(function(payload)
			if type(payload) == "table" and type(payload.rank) == "number" then
				deployState.rank = math.max(1, math.floor(payload.rank))
				refreshDiffSelection()
			end
		end)
	end
	-- Nameplates already understand a GF_Rank player attribute. It is not present in every
	-- build, but when a progression surface publishes it the war table can use it immediately.
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		local function applyAttributeRank()
			local rank = localPlayer:GetAttribute("GF_Rank")
			if type(rank) == "number" then
				deployState.rank = math.max(1, math.floor(rank))
				refreshDiffSelection()
			end
		end
		applyAttributeRank()
		localPlayer:GetAttributeChangedSignal("GF_Rank"):Connect(applyAttributeRank)
	end

	local function selectRegion(rid: string)
		if deployState.committing then
			return
		end
		deployState.region = rid
		deployState.operationId = nil
		deployState.opButtons = {}
		deployState.opRows = {}
		for _, child in ipairs(opList:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		opList.CanvasPosition = Vector2.new(0, 0)
		updateTheaterIntel(rid)
		paintTheaterButtons()

		local operationIds = {}
		for opId, def in pairs(WarModel.OPERATIONS) do
			if (def.region or "?") == rid then
				table.insert(operationIds, opId)
			end
		end
		table.sort(operationIds, function(a, b)
			return operationDisplayName(a) < operationDisplayName(b)
		end)

		for order, opId in ipairs(operationIds) do
			local def = WarModel.OPERATIONS[opId]
			local name = operationDisplayName(opId)
			local templateId = WarOperations.templateFor(opId)
			local mission = templateId and Missions.ById[templateId] or nil
			local templateName = mission and mission.displayName or templateId or "UNKNOWN TEMPLATE"
			local duration = mission and mission.durationClass or "STANDARD"
			local objective = mission and mission.primary or "Theater orders unavailable"

			local row = Components.row(opList, string.upper(name), nil)
			row.LayoutOrder = order
			row.Size = UDim2.new(1, 0, 0, 108)
			local rowLayout = row:FindFirstChildOfClass("UIListLayout")
			if rowLayout then
				rowLayout:Destroy()
			end
			local rowPadding = row:FindFirstChildOfClass("UIPadding")
			if rowPadding then
				rowPadding:Destroy()
			end
			local rowStroke = Instance.new("UIStroke")
			rowStroke.Color = Tokens.Color.border
			rowStroke.Transparency = 0.65
			rowStroke.Thickness = 1
			rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			rowStroke.Parent = row
			local edge = Instance.new("Frame")
			edge.Name = "SelectionEdge"
			edge.Size = UDim2.new(0, 4, 1, 0)
			edge.Position = UDim2.new(0, 0, 0, 0)
			edge.BackgroundColor3 = Tokens.Color.accentSelect
			edge.BorderSizePixel = 0
			edge.Visible = false
			edge.ZIndex = 2
			edge.Parent = row

			local titleLabel = row:FindFirstChild("Text_body") :: TextLabel
			titleLabel.Position = UDim2.new(0, Tokens.Space.md, 0, 8)
			titleLabel.Size = UDim2.new(1, -150, 0, 20)
			titleLabel.Font = Tokens.Type.fontBold
			titleLabel.TextXAlignment = Enum.TextXAlignment.Left

			local metaLabel = Components.text(row, string.format("%s OPERATION · TEMPLATE %s · %s",
				string.upper(def.family or "COMBAT"), string.upper(templateName), string.upper(duration)), "caption")
			metaLabel.Position = UDim2.new(0, Tokens.Space.md, 0, 32)
			metaLabel.Size = UDim2.new(1, -150, 0, 15)
			metaLabel.TextColor3 = Tokens.Color.textAccent

			local objectiveLabel = Components.text(row, "OBJECTIVE — " .. objective, "caption")
			objectiveLabel.Position = UDim2.new(0, Tokens.Space.md, 0, 50)
			objectiveLabel.Size = UDim2.new(1, -150, 0, 15)
			objectiveLabel.TextColor3 = Tokens.Color.textPrimary

			local flavorLabel = Components.text(row, "SITREP — " .. operationFlavor(opId, def.family or "Default", rid), "caption")
			flavorLabel.Position = UDim2.new(0, Tokens.Space.md, 0, 68)
			flavorLabel.Size = UDim2.new(1, -150, 0, 32)
			flavorLabel.TextWrapped = true
			flavorLabel.TextYAlignment = Enum.TextYAlignment.Top
			flavorLabel.TextColor3 = Tokens.Color.textSecondary

			-- The intel panel itself is part of the commit target, like clicking an operation
			-- card on the war table. The visible COMMIT button remains the console/touch focus.
			local rowHit = Instance.new("TextButton")
			rowHit.Name = "OperationHitTarget"
			rowHit.Size = UDim2.new(1, -142, 1, 0)
			rowHit.Position = UDim2.new(0, 0, 0, 0)
			rowHit.BackgroundTransparency = 1
			rowHit.BorderSizePixel = 0
			rowHit.Text = ""
			rowHit.AutoButtonColor = false
			rowHit.Selectable = false
			rowHit.Parent = row
			rowHit.Activated:Connect(function()
				selectOperation(opId)
			end)

			local pick = createWarButton(row, "COMMIT", Tokens.Type.sizeSmall)
			pick.Size = UDim2.new(0, 112, 0, Tokens.Size.buttonHeight)
			pick.Position = UDim2.new(1, -Tokens.Space.sm - 2, 0.5, 0)
			pick.AnchorPoint = Vector2.new(1, 0.5)
			deployState.opButtons[opId] = pick
			deployState.opRows[opId] = row
			bindWarButton(pick, paintOperationRows)
			pick.Activated:Connect(function()
				selectOperation(opId)
			end)
		end

		if #operationIds == 0 then
			setStatus("NO OPERATIONS IN THEATER", Tokens.Color.warning)
		else
			updateCommitmentStatus()
		end
		paintOperationRows()
	end

	-- theater buttons populate once; selection state and live status color ride on top
	local regions = {}
	for _opId, def in pairs(WarModel.OPERATIONS) do
		local rid = def.region or "?"
		if not table.find(regions, rid) then
			table.insert(regions, rid)
		end
	end
	table.sort(regions)
	for rIdx, rid in ipairs(regions) do
		local button = createWarButton(theaterRow, "", Tokens.Type.sizeSmall)
		button.Size = UDim2.new(0, 148, 1, -4)
		button.LayoutOrder = rIdx
		deployState.regionButtons[rid] = button
		local stripe = Instance.new("Frame")
		stripe.Name = "StatusStripe"
		stripe.Size = UDim2.new(1, 0, 0, 3)
		stripe.Position = UDim2.new(0, 0, 1, -3)
		stripe.BackgroundColor3 = Tokens.Color.steel
		stripe.BorderSizePixel = 0
		stripe.Parent = button
		deployState.regionStripes[rid] = stripe
		bindWarButton(button, paintTheaterButtons)
		button.Activated:Connect(function()
			selectRegion(rid)
		end)
	end

	refreshDiffSelection()
	-- initial selection: terminal preselection if set, else the first theater
	local initial = deployState.region
	if not table.find(regions, initial) then
		initial = regions[1]
	end
	if initial then
		selectRegion(initial)
	end

	-- Keep the war read live without rebuilding the operation list (which would destroy the
	-- player's selection). Two seconds is cheap locally and fast enough for attribute updates.
	task.spawn(function()
		while true do
			task.wait(2)
			if shell.visible and shell.active == "DEPLOY" then
				updateTheaterIntel(deployState.region)
				paintTheaterButtons()
			end
		end
	end)
end)

-- Components.row ships with a vertical layout for text-only rows. Rows that carry a right-side
-- action need manual composition instead; otherwise the layout treats the button/accent as another
-- text line and the touch target is clipped. Used lightly by FORM and SQUADS below.
local function prepareActionRow(row: Frame, rightReserve: number)
	local rowLayout = row:FindFirstChildOfClass("UIListLayout")
	if rowLayout then
		rowLayout:Destroy()
	end
	local rowPadding = row:FindFirstChildOfClass("UIPadding")
	if rowPadding then
		rowPadding:Destroy()
	end
	local primary = row:FindFirstChild("Text_body")
	if primary and primary:IsA("TextLabel") then
		primary.Position = UDim2.new(0, Tokens.Space.md, 0, 7)
		primary.Size = UDim2.new(1, -rightReserve, 0, 20)
		primary.TextXAlignment = Enum.TextXAlignment.Left
	end
	local caption = row:FindFirstChild("Text_caption")
	if caption and caption:IsA("TextLabel") then
		caption.Position = UDim2.new(0, Tokens.Space.md, 0, 30)
		caption.Size = UDim2.new(1, -rightReserve, 0, 16)
		caption.TextXAlignment = Enum.TextXAlignment.Left
	end
end

-- FORM section state: these two were referenced below but never declared, which threw
-- "attempt to index nil with 'statusLine'" inside registerSection and killed the whole script
-- (claude hotfix 2026-11-27 — beta, keep or replace).
local formState = {
	operationId = nil :: string?,
	difficulty = "Normal",
	public = true,
	opButtons = {} :: { [string]: TextButton },
	diffButtons = {} :: { [string]: TextButton },
	privButtons = {} :: { [string]: TextButton },
	statusLine = nil :: TextLabel?,
}

local function refreshChips()
	local function paint(b: TextButton, selected: boolean)
		b.BackgroundColor3 = selected and Tokens.Color.accentSelect or Tokens.Color.panelRaised
		b.TextColor3 = selected and Tokens.Color.panelInset or Tokens.Color.textPrimary
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = selected and Tokens.Color.accentSelect or Tokens.Color.steel
			stroke.Transparency = selected and 0 or 0.62
			stroke.Thickness = selected and 2 or 1
		end
	end
	for id, b in pairs(formState.opButtons) do
		paint(b, id == formState.operationId)
	end
	for d, b in pairs(formState.diffButtons) do
		paint(b, d == formState.difficulty)
	end
	for key, b in pairs(formState.privButtons) do
		paint(b, (key == "public") == formState.public)
	end
end

shell:registerSection("FORM", "▲", function(page)
	Components.text(page, "FORM OPERATION — FLEET-WIDE LISTING", "title",
		UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 0))
	local statusLine = Components.text(page, "select an operation, difficulty, and visibility", "caption",
		UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 34))
	formState.statusLine = statusLine

	local scroll = Components.list(page, UDim2.new(1, 0, 1, -60), UDim2.new(0, 0, 0, 58))

	-- operations grouped by region — the fixed-geography mandate made visible in the picker
	local byRegion: { [string]: { string } } = {}
	local regionOrder: { string } = {}
	for opId, def in pairs(WarModel.OPERATIONS) do
		local region = def.region or "?"
		if not byRegion[region] then
			byRegion[region] = {}
			table.insert(regionOrder, region)
		end
		table.insert(byRegion[region], opId)
	end
	table.sort(regionOrder)
	local order = 0
	for _, region in ipairs(regionOrder) do
		table.sort(byRegion[region])
		order += 1
		local header = Components.text(scroll, regionDisplayName(region), "caption")
		header.LayoutOrder = order
		header.TextColor3 = Tokens.Color.textAccent
		for _, opId in ipairs(byRegion[region]) do
			order += 1
			local def = WarModel.OPERATIONS[opId]
			local name = WarOperations.DisplayName[opId] or opId
			local row = Components.row(scroll, name, string.format("%s · %s", string.lower(def.family or "operation"), regionDisplayName(region)))
			row.LayoutOrder = order
			prepareActionRow(row, 132)
			local pick = Components.button(row, "SELECT", "ghost")
			pick.Size = UDim2.new(0, 100, 0, Tokens.Size.buttonHeight)
			pick.Position = UDim2.new(1, -Tokens.Space.sm, 0.5, 0)
			pick.AnchorPoint = Vector2.new(1, 0.5)
			formState.opButtons[opId] = pick
			pick.Activated:Connect(function()
				formState.operationId = opId
				refreshChips()
				statusLine.Text = string.format("%s — %s", name, region)
				statusLine.TextColor3 = Tokens.Color.textSecondary
			end)
		end
	end

	-- difficulty chips
	order += 1
	local diffHeader = Components.text(scroll, "DIFFICULTY", "caption")
	diffHeader.LayoutOrder = order
	diffHeader.TextColor3 = Tokens.Color.textAccent
	local diffRow = Instance.new("Frame")
	diffRow.Size = UDim2.new(1, 0, 0, Tokens.Size.chipHeight + 8)
	diffRow.BackgroundTransparency = 1
	order += 1
	diffRow.LayoutOrder = order
	diffRow.Parent = scroll
	local diffLayout = Instance.new("UIListLayout")
	diffLayout.FillDirection = Enum.FillDirection.Horizontal
	diffLayout.Padding = UDim.new(0, Tokens.Space.sm)
	diffLayout.Parent = diffRow
	for _, diff in ipairs({ "Easy", "Normal", "Hard", "Extreme" }) do
		local chip = Components.button(diffRow, string.upper(diff), "ghost")
		chip.Size = UDim2.new(0, 110, 0, Tokens.Size.chipHeight)
		chip.TextSize = Tokens.Type.sizeSmall
		formState.diffButtons[diff] = chip
		chip.Activated:Connect(function()
			formState.difficulty = diff
			refreshChips()
		end)
	end

	-- visibility chips
	order += 1
	local privHeader = Components.text(scroll, "VISIBILITY", "caption")
	privHeader.LayoutOrder = order
	privHeader.TextColor3 = Tokens.Color.textAccent
	local privRow = Instance.new("Frame")
	privRow.Size = UDim2.new(1, 0, 0, Tokens.Size.chipHeight + 8)
	privRow.BackgroundTransparency = 1
	order += 1
	privRow.LayoutOrder = order
	privRow.Parent = scroll
	local privLayout = Instance.new("UIListLayout")
	privLayout.FillDirection = Enum.FillDirection.Horizontal
	privLayout.Padding = UDim.new(0, Tokens.Space.sm)
	privLayout.Parent = privRow
	for _, spec in ipairs({ { key = "public", label = "PUBLIC — FLEET-WIDE" }, { key = "private", label = "SQUAD-ONLY" } }) do
		local chip = Components.button(privRow, spec.label, "ghost")
		chip.Size = UDim2.new(0, 200, 0, Tokens.Size.chipHeight)
		chip.TextSize = Tokens.Type.sizeSmall
		formState.privButtons[spec.key] = chip
		chip.Activated:Connect(function()
			formState.public = spec.key == "public"
			refreshChips()
		end)
	end

	-- the form action
	order += 1
	local formBtn = Components.button(scroll, "FORM OPERATION", "primary")
	formBtn.LayoutOrder = order
	formBtn.Activated:Connect(function()
		if not formState.operationId then
			statusLine.Text = "select an operation first"
			statusLine.TextColor3 = Tokens.Color.warning
			return
		end
		local def = WarModel.OPERATIONS[formState.operationId]
		statusLine.Text = "PUBLISHING FLEET-WIDE…"
		statusLine.TextColor3 = Tokens.Color.textAccent
		local form = remotes:FindFirstChild("FormSquad")
		if form then
			form:FireServer({
				operationId = formState.operationId,
				difficulty = formState.difficulty,
				capacity = 4,
				public = formState.public,
				region = def and def.region or nil,
			})
			statusLine.Text = string.format("LISTED — report to the %s terminal; joiners arrive fleet-wide",
				tostring(def and def.region or "deployment"))
			statusLine.TextColor3 = Tokens.Color.success
		end
	end)

	refreshChips()
end)

local function clearList()
	local list = browserState.listContainer
	if not list then return end
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function joinRow(parent: Instance, order: number, heading: string, caption: string, accent: Color3?, onJoin: () -> ()): ()
	local row = Components.row(parent, heading, caption)
	row.LayoutOrder = order
	prepareActionRow(row, 142)
	local joinBtn = Components.button(row, "JOIN", "primary")
	joinBtn.Size = UDim2.new(0, 110, 0, Tokens.Size.buttonHeight)
	joinBtn.Position = UDim2.new(1, -Tokens.Space.sm, 0.5, 0)
	joinBtn.AnchorPoint = Vector2.new(1, 0.5)
	joinBtn.Activated:Connect(onJoin)
	if accent then
		-- status accent: thin left edge, same language as the sidebar active bar
		local edge = Instance.new("Frame")
		edge.Size = UDim2.new(0, 3, 1, 0)
		edge.BackgroundColor3 = accent
		edge.BorderSizePixel = 0
		edge.ZIndex = 2
		edge.Parent = row
	end
end

local function renderBrowser(data: any)
	clearList()
	local list = browserState.listContainer
	if not list then return end
	local order = 0
	local count = 0

	-- distress beacons first: they are time-critical by definition
	for _, beacon in ipairs(data.beacons or {}) do
		if (tonumber(beacon.seats) or 0) > 0 then
			order += 1
			count += 1
			local heading = string.format("⚠ DISTRESS — %s", tostring(beacon.region or beacon.id or "UNKNOWN"))
			local caption = string.format("%s · %d seat(s) · %ds elapsed",
				tostring(beacon.difficulty or "?"), tonumber(beacon.seats) or 0, tonumber(beacon.age) or 0)
			local key = string.format("%014d", tonumber(beacon.openedAtUTC) or 0) .. "_" .. tostring(beacon.id)
			joinRow(list, order, heading, caption, Tokens.Color.warning, function()
				if browserState.statusLine then
					browserState.statusLine.Text = "RESPONDING TO DISTRESS…"
					browserState.statusLine.TextColor3 = Tokens.Color.textAccent
				end
				task.spawn(function()
					local respond = remotes:FindFirstChild("RespondDispatch")
					if not respond then return end
					local ok, result = pcall(function()
						return respond:InvokeServer(key)
					end)
					if browserState.statusLine then
						if ok and type(result) == "table" and result.ok then
							browserState.statusLine.Text = result.teleporting and "DEPLOYING — good hunting" or "JOINED — insertion inbound"
						else
							local reason = type(result) == "table" and tostring(result.reason) or "failed"
							browserState.statusLine.Text = "RESPONSE FAILED — " .. reason
							browserState.statusLine.TextColor3 = Tokens.Color.danger
						end
					end
				end)
			end)
		end
	end

	-- forming squads across all servers (server contract field: `squads`)
	for _, squad in ipairs(data.squads or {}) do
		if squad.state == "forming" and (tonumber(squad.openSeats) or 0) > 0 then
			order += 1
			count += 1
			local sameServer = squad.leaderJobId == game.JobId
			local heading = string.format("%s — %s", tostring(squad.leader or "SQUAD"), tostring(squad.operationName or squad.operationId or "OPERATION"))
			local caption = string.format("%s · %s · %d/%d seats%s",
				tostring(squad.region or "?"), tostring(squad.difficulty or "?"),
				tonumber(squad.taken) or 1, tonumber(squad.capacity) or 4,
				sameServer and " · THIS SERVER" or "")
			local listingKey = tostring(squad.squadId)
			joinRow(list, order, heading, caption, nil, function()
				if browserState.statusLine then
					browserState.statusLine.Text = "JOINING SQUAD…"
					browserState.statusLine.TextColor3 = Tokens.Color.textAccent
				end
				task.spawn(function()
					local join = remotes:FindFirstChild("JoinSquad")
					if not join then return end
					local ok, result = pcall(function()
						return join:InvokeServer(listingKey)
					end)
					if browserState.statusLine then
						if ok and type(result) == "table" and result.ok then
							browserState.statusLine.Text = result.teleporting and "TRANSFERRING TO SQUAD SERVER…" or "JOINED — report to your squad"
						else
							local reason = type(result) == "table" and tostring(result.reason) or "failed"
							browserState.statusLine.Text = "JOIN FAILED — " .. reason
							browserState.statusLine.TextColor3 = Tokens.Color.danger
						end
					end
				end)
			end)
		end
	end

	if count == 0 and browserState.statusLine then
		browserState.statusLine.Text = "No forming squads or distress calls across the fleet — form one and it appears here for everyone."
		browserState.statusLine.TextColor3 = Tokens.Color.textSecondary
	elseif browserState.statusLine and browserState.statusLine.TextColor3 ~= Tokens.Color.danger then
		browserState.statusLine.Text = string.format("%d open operation(s) fleet-wide · refreshes every 5s", count)
		browserState.statusLine.TextColor3 = Tokens.Color.textSecondary
	end
end

-- refresh loop: only while open — MemoryStore read budgets are real
task.spawn(function()
	while true do
		task.wait(5)
		if shell.visible then
			browserState.refreshToken += 1
			local token = browserState.refreshToken
			task.spawn(function()
				local browser = remotes:FindFirstChild("RequestSquadBrowser")
				if not browser then return end
				local ok, data = pcall(function()
					return browser:InvokeServer()
				end)
				-- stale responses never overwrite newer state
				if ok and type(data) == "table" and token == browserState.refreshToken then
					renderBrowser(data)
				end
			end)
		end
	end
end)

-- ---------------------------------------------------------------------------
-- open/close wiring: the deploy-terminal proximity opens this browser; the legacy
-- quick-deploy path stays live during migration. keyboard shortcut for kbm, and the
-- browser closes on B/esc per the semantic input layer.
-- ---------------------------------------------------------------------------
local Input = require(script.Parent.Input)

local function toggleBrowser()
	if shell.visible then
		shell:close()
	else
		shell:open()
		shell:setActive("SQUADS")
		-- immediate refresh on open rather than waiting for the cadence
		browserState.refreshToken += 1
		local token = browserState.refreshToken
		task.spawn(function()
			local browser = remotes:FindFirstChild("RequestSquadBrowser")
			if not browser then return end
			local ok, data = pcall(function()
				return browser:InvokeServer()
			end)
			if ok and type(data) == "table" and token == browserState.refreshToken then
				renderBrowser(data)
			end
		end)
	end
end

-- squad browser keybind: lobby context (same exclusivity logic as quick-response —
-- in-mission this input is dead)
Input.onPress("SquadBrowser", function()
	if workspace:GetAttribute("GF_InMission") == true then
		return
	end
	toggleBrowser()
end)

-- close on menu-back when open
Input.onPress("MenuBack", function()
	if shell.visible then
		shell:close()
	end
end)

print("[GF] squad browser online")
