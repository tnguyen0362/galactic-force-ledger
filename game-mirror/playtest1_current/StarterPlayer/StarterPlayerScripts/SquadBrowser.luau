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
local TweenService = game:GetService("TweenService")

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
-- Presentation mirror of StationService's server-side rank gates. The server remains
-- authoritative; the HD2 tier row is presentation over the four internal wire values.
-- When the profile push has not arrived yet every tier stays selectable and the refusal
-- path explains the gate instead of pretending knowledge the client lacks.
local DIFFICULTY_RANK = { Easy = 1, Normal = 3, Hard = 6, Extreme = 14 }

-- HD2's ten spoken difficulty tiers, mapped onto the four internal server difficulties.
-- Wire values remain Easy/Normal/Hard/Extreme exactly; the extra tiers are presentation.
local DIFFICULTY_TIERS = {
	{ number = 1, name = "TRIVIAL", wire = "Easy" },
	{ number = 2, name = "EASY", wire = "Easy" },
	{ number = 3, name = "MEDIUM", wire = "Easy" },
	{ number = 4, name = "CHALLENGING", wire = "Normal" },
	{ number = 5, name = "HARD", wire = "Normal" },
	{ number = 6, name = "EXTREME", wire = "Hard" },
	{ number = 7, name = "SUICIDE MISSION", wire = "Hard" },
	{ number = 8, name = "IMPOSSIBLE", wire = "Extreme" },
	{ number = 9, name = "HELLDIVE", wire = "Extreme" },
	{ number = 10, name = "SUPER HELLDIVE", wire = "Extreme" },
}

local function tierIndexForWire(wire: string): number
	for index, spec in ipairs(DIFFICULTY_TIERS) do
		if spec.wire == wire then
			return index
		end
	end
	return 4
end

local function tierLabel(index: number): string
	local spec = DIFFICULTY_TIERS[index] or DIFFICULTY_TIERS[4]
	return string.format("%d %s", spec.number, spec.name)
end

-- HD2 reference palette, scoped to the war table only. GF cyan/amber remain the
-- interactive/selection accent family; blue/red are reserved exclusively for contested
-- liberation shares so the two-tone bar reads exactly like the reference.
local HOLO_GROUND = Color3.fromRGB(0x04, 0x07, 0x0B)
local PANEL_NAVY = Color3.fromRGB(0x0B, 0x22, 0x33)
local SUPER_EARTH_BLUE = Color3.fromRGB(0x41, 0x63, 0x9C)
local ENEMY_RED = Color3.fromRGB(0xFF, 0x3B, 0x30)

-- Presentation-only sector frame: the fixed geography already clusters cleanly by biome
-- and neighbor graph. Those clusters borrow the spec's sector names; region ids remain the
-- authoritative server data and no extra planet/sector state is invented.
local BIOME_SECTORS = {
	forest = "SEVERIN",
	ash = "XZAR",
	frost = "YMIR",
	iron = "HYDRA",
}

local HD2_OPERATION_COPY = {
	Conquest = { "PEACEKEEPING OPERATION", "PROTECT LIBERTY" },
	Recovery = { "PEACEKEEPING OPERATION", "DEFEND FREEDOM" },
	Elimination = { "PROTECT LIBERTY", "PEACEKEEPING OPERATION" },
	Sabotage = { "DEFEND FREEDOM", "PROTECT LIBERTY" },
	Defense = { "DEFEND PLANET", "DEFEND FREEDOM" },
	Default = { "PEACEKEEPING OPERATION" },
}

local HD2_MISSION_COPY = {
	Conquest = { "SPREAD DEMOCRACY" },
	Recovery = { "RETRIEVE VALUABLE DATA", "EVACUATE HIGH-VALUE ASSETS", "CONDUCT GEOLOGICAL SURVEY" },
	Elimination = { "BLITZ: SEARCH AND DESTROY", "DESTROY COMMAND BUNKERS" },
	Sabotage = { "TERMINATE ILLEGAL BROADCAST", "SABOTAGE SUPPLY BASES", "NEUTRALISE ORBITAL DEFENSES" },
	Defense = { "EMERGENCY EVACUATION", "EVACUATE HIGH-VALUE ASSETS" },
	Default = { "SPREAD DEMOCRACY" },
}

local STATUS_TEXT = {
	ascendancy_dominance = "ASCENDANCY DOMINANCE",
	contested_theater = "CONTESTED FRONT",
	human_infiltration = "SUPER EARTH INFILTRATION",
	gf_offensive = "SUPER EARTH OFFENSIVE",
	established_superiority = "ESTABLISHED CONTROL",
}

local BIOME_NAMES = {
	forest = "ETHEREAL JUNGLE",
	ash = "ACIDIC BADLANDS",
	frost = "ICY GLACIERS",
	iron = "DEADLANDS",
}

local BIOME_FEATURES = {
	forest = { "the northern canopy ridge", "the black-jungle approaches", "the riverine chokepoint" },
	ash = { "the cinder flats", "the basalt ridge", "the ash-storm corridor" },
	frost = { "the glacier line", "the whiteout pass", "the frozen causeway" },
	iron = { "the foundry sprawl", "the slag-yard perimeter", "the magnetite ridge" },
}

-- HD2-style EFFECTS readouts. These are deterministic theater intel flavor, not claims
-- about additional server mechanics; they make the planet panel read like the reference.
local BIOME_CONDITIONS = {
	forest = {
		{ "THICK FOG", "Canopy occlusion degrades long-range observation." },
		{ "RAINSTORMS", "Sensor contrast is degraded across forward approaches." },
		{ "ATMOSPHERIC SPORES", "Airborne spores corrupt orbital telemetry." },
	},
	ash = {
		{ "INTENSE HEAT", "Thermal haze distorts optics and drone tracking." },
		{ "VOLCANIC ACTIVITY", "Ash plumes interfere with orbital plotting." },
		{ "FIRE TORNADOS", "Firestorms close lanes without warning." },
	},
	frost = {
		{ "EXTREME COLD", "Exposure slows field repairs and equipment handling." },
		{ "BLIZZARDS", "Whiteout conditions compress visibility." },
		{ "ION STORMS", "Charged precipitation scrambles sensors." },
	},
	iron = {
		{ "TREMORS", "Seismic shock interrupts precision work." },
		{ "ION STORMS", "Industrial charge interferes with telemetry." },
		{ "METEOR STORMS", "Orbital debris forces intermittent cover windows." },
	},
}

-- High-tier OPERATION MODIFIERS use the reference vocabulary verbatim. Like the biome
-- EFFECTS above, they are deterministic readout flavor until the simulation owns them.
local OPERATION_MODIFIERS = {
	{ "POOR INTEL", "Orbital outlines arrive incomplete; expect contact beyond marked lanes." },
	{ "COMPLEX STRATAGEM PLOTTING", "Fire-support plotting is slower under theater jamming." },
	{ "ORBITAL FLUCTUATIONS", "Super Destroyer support windows drift out of phase." },
	{ "ATMOSPHERIC SPORES", "Airborne corruption degrades helmet telemetry." },
}

local FAMILY_FLAVOR = {
	Conquest = {
		"Super Earth demands the ground intact — Liberty is measured in captured meters.",
		"Orbital fire cannot hold terrain. Helldivers on the console decide whether this planet moves.",
		"Every captured meter becomes a firebase for Managed Democracy; the Ascendancy will answer fast.",
	},
	Recovery = {
		"Valuable data is in enemy custody. Retrieve it before the Ascendancy learns what Freedom cost.",
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
		"Super Earth High Command has marked this as a decisive commitment. Expect contact soon after insertion.",
	},
}

local SITUATION_LINES = {
	enemy = {
		"Ascendancy resistance stiffening along %s; Helldiver squads report overlapping fire lanes.",
		"Enemy reinforcement columns are massing beyond %s while pickets probe the Super Earth screen.",
		"Occupation batteries are registering %s; expect interdiction fire on approach.",
	},
	contested = {
		"Neither line holds for long near %s; artillery fire is walking the approaches.",
		"Ascendancy counterattacks probe %s while Helldiver fireteams contest every crossing.",
		"Signals traffic spiked around %s. Both sides are feeding reserves into the same corridor.",
	},
	infiltration = {
		"Small Helldiver cells are testing the perimeter near %s; occupation forces are reacting piecemeal.",
		"Reconnaissance teams have blind spots opening around %s, but the enemy net is still intact.",
		"Forward observers are quietly marking targets across %s ahead of the next push for Liberty.",
	},
	human = {
		"Super Earth forward elements are exploiting gaps around %s; enemy withdrawal signs are visible.",
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

local function statusLabel(status: string): string
	return STATUS_TEXT[status] or upperWords(status)
end

local function formatTMinus(seconds: number): string
	local total = math.max(0, math.floor(seconds + 0.5))
	local minutes = math.floor(total / 60)
	local remainder = total % 60
	return string.format("T-%02d:%02d", minutes, remainder)
end

local function regionBiome(rid: string): string
	local territory = WarModel.TERRITORIES[rid]
	return (territory and territory.biome) or "forest"
end

local function biomeDisplayName(rid: string): string
	return BIOME_NAMES[regionBiome(rid)] or BIOME_NAMES.forest
end

local function sectorDisplayName(rid: string): string
	return BIOME_SECTORS[regionBiome(rid)] or "ORION"
end

local function hd2OperationCopy(opId: string, family: string): string
	local pool = HD2_OPERATION_COPY[family] or HD2_OPERATION_COPY.Default
	return pool[(stableHash(opId .. "|operation") % #pool) + 1]
end

local function hd2MissionCopy(templateId: string?, family: string): string
	local pool = HD2_MISSION_COPY[family] or HD2_MISSION_COPY.Default
	return pool[(stableHash((templateId or family) .. "|mission") % #pool) + 1]
end

local function biomeEffectPair(rid: string, seed: number)
	local conditions = BIOME_CONDITIONS[regionBiome(rid)] or BIOME_CONDITIONS.forest
	local firstIndex = (seed % #conditions) + 1
	local secondIndex = ((math.floor(seed / 7) + 1) % #conditions) + 1
	if secondIndex == firstIndex then
		secondIndex = (firstIndex % #conditions) + 1
	end
	return conditions[firstIndex], conditions[secondIndex]
end

local function operationModifierForSeed(seed: number)
	return OPERATION_MODIFIERS[(math.floor(seed / 13) % #OPERATION_MODIFIERS) + 1]
end

local function tweenVisual(instance: Instance, properties: { [string]: any }, duration: number?)
	TweenService:Create(instance, TweenInfo.new(
		duration or Tokens.Motion.fast,
		Tokens.Motion.easing,
		Tokens.Motion.direction
	), properties):Play()
end

-- Current Components.row marks its composed labels with GFRowText rather than exposing
-- a stable child-name contract. All row surgery in this file must use these attributes.
local function findRowText(row: Frame, kind: string): TextLabel?
	for _, child in ipairs(row:GetChildren()) do
		if child:IsA("TextLabel") and child:GetAttribute("GFRowText") == kind then
			return child
		end
	end
	return nil
end

-- GF_WarTerritories = "Id:progress:State[:FRONT];..." (GalacticWarService legacy snapshot).
-- It covers the fixed campaign geography even where the newer GF_WarState matrix is sparse.
local function territorySnapshot()
	local out = {}
	local raw = workspace:GetAttribute("GF_WarTerritories")
	if type(raw) == "string" then
		for entry in raw:gmatch("[^;]+") do
			local id, progress, state, front = entry:match("^([^:]+):(-?%d+):([^:]*):?(.*)$")
			if id then
				out[id] = {
					progress = tonumber(progress) or 0,
					state = state or "",
					front = front == "FRONT",
				}
			end
		end
	end
	return out
end

local function legacyStatus(state: string): string
	local lowered = string.lower(state or "")
	if string.find(lowered, "contest") then
		return "contested_theater"
	elseif string.find(lowered, "liberat") or string.find(lowered, "secur") or string.find(lowered, "superior") then
		return "established_superiority"
	elseif string.find(lowered, "offens") then
		return "gf_offensive"
	elseif string.find(lowered, "infiltr") then
		return "human_infiltration"
	elseif string.find(lowered, "human") or string.find(lowered, "held") then
		return "established_superiority"
	end
	return "ascendancy_dominance"
end

local function liveStatus(rid: string): string
	local raw = workspace:GetAttribute("GF_WarState_" .. rid .. "_Status")
	if type(raw) == "string" and raw ~= "" then
		return raw
	end
	local territory = territorySnapshot()[rid]
	if territory then
		return legacyStatus(territory.state)
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
	-- The legacy campaign snapshot publishes real per-planet progress (0-100) for regions
	-- the newer force matrix does not cover. Use it before admitting telemetry is absent.
	local territory = territorySnapshot()[rid]
	if territory then
		return math.clamp(territory.progress / 100, 0, 1)
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
	local territory = territorySnapshot()[rid]
	if territory and territory.front then
		return "active front"
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
	if control ~= nil
		or workspace:GetAttribute("GF_WarState_" .. rid .. "_Status") ~= nil
		or territorySnapshot()[rid] ~= nil
	then
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
		assessment = "Telemetry incomplete — treat this planet as contested until the next fleet snapshot."
	elseif pct >= 65 then
		assessment = "Super Earth holds the initiative; another successful operation can break this planet open."
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
	button.ClipsDescendants = true
	button.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = Tokens.Color.steel
	stroke.Transparency = 0.7
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local edge = Instance.new("Frame")
	edge.Name = "AccentEdge"
	edge.Size = UDim2.new(0, Tokens.Frame.cornerThickness, 1, -Tokens.Space.sm)
	edge.Position = UDim2.new(0, 0, 0, Tokens.Space.xs)
	edge.BackgroundColor3 = Tokens.Color.techCyan
	edge.BackgroundTransparency = 0.52
	edge.BorderSizePixel = 0
	edge.Parent = button
	local chamfer = Components.chamferAccent(button, "topRight", Tokens.Frame.chamferLength,
		Tokens.Color.techCyan, Tokens.Frame.borderThickness)
	chamfer.BackgroundTransparency = 0.42
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
	local edge = button:FindFirstChild("AccentEdge")
	local chamfer = button:FindFirstChild("Chamfer_topRight")
	local hover = button:GetAttribute("GF_Hover") == true or button:GetAttribute("GF_Focused") == true
	local pressed = button:GetAttribute("GF_Pressed") == true

	local background = Tokens.Color.panelRaised
	local text = Tokens.Color.textPrimary
	local lineColor = Tokens.Color.steel
	local lineTransparency = 0.7
	local lineThickness = 1
	local accent = Tokens.Color.techCyan
	local accentTransparency = 0.52

	if locked == true then
		background = Tokens.Color.panelInset
		text = Tokens.Color.textDisabled
		lineColor = Tokens.Color.danger
		lineTransparency = 0.72
		accent = Tokens.Color.steel
		accentTransparency = 0.86
	elseif selected then
		background = Tokens.Color.accentSelect
		text = Tokens.Color.panelInset
		lineColor = Tokens.Color.accentSelect
		lineTransparency = 0
		lineThickness = 2
		accent = Tokens.Color.textOnAccent
		accentTransparency = 0.05
	elseif pressed then
		background = Tokens.Color.navy
		text = Tokens.Color.textAccent
		lineColor = Tokens.Color.borderFocus
		lineTransparency = 0.05
		accentTransparency = 0.05
	elseif hover then
		background = Tokens.Color.navy
		text = Tokens.Color.textPrimary
		lineColor = Tokens.Color.borderFocus
		lineTransparency = 0.25
		accentTransparency = 0.18
	end

	-- HD2 rule: state changes animate, even when the motion is only a fast console snap.
	tweenVisual(button, { BackgroundColor3 = background, TextColor3 = text }, Tokens.Motion.fast)
	if stroke then
		tweenVisual(stroke, {
			Color = lineColor,
			Transparency = lineTransparency,
			Thickness = lineThickness,
		}, Tokens.Motion.fast)
	end
	if edge and edge:IsA("Frame") then
		tweenVisual(edge, { BackgroundColor3 = accent, BackgroundTransparency = accentTransparency }, Tokens.Motion.fast)
	end
	if chamfer and chamfer:IsA("Frame") then
		tweenVisual(chamfer, { BackgroundColor3 = accent, BackgroundTransparency = math.min(0.92, accentTransparency + 0.08) }, Tokens.Motion.fast)
	end
end

local function operationDisplayName(opId: string): string
	return (WarOperations.DisplayName and WarOperations.DisplayName[opId]) or opId
end

local deployState = {
	region = "VerdantReach",
	operationId = nil :: string?,
	difficulty = "Normal", -- wire value only; HD2 tier presentation rides on difficultyTier
	difficultyTier = 4, -- 4 CHALLENGING, the lowest tier mapped onto internal Normal
	rank = nil :: number?,
	committing = false,
	commitToken = 0,
	opButtons = {} :: { [string]: TextButton },
	opRows = {} :: { [string]: Frame },
	regionButtons = {} :: { [string]: TextButton },
	regionStripes = {} :: { [string]: Frame },
	diffButtons = {} :: { [number]: TextButton },
	statusLine = nil :: TextLabel?,
	opList = nil :: ScrollingFrame?,
}

shell:registerSection("WAR TABLE", "\u{25bc}", function(page)
	-- HD2 war-table hierarchy within the data the game actually owns: planet selector
	-- across the top, planet intel center-left, operations/missions on the right, the
	-- ten-tier difficulty selector bottom-center, and READY UP / PREPARE TO DIVE at bottom.
	page.BackgroundColor3 = HOLO_GROUND
	page.BackgroundTransparency = 0
	page.BorderSizePixel = 0
	page.ClipsDescendants = true
	local groundScan = Components.scanlineField(page, 32, nil, Tokens.Color.techCyan)
	groundScan.ZIndex = 1
	Components.frameBrackets(page, Tokens.Color.borderStrong, 18, Tokens.Frame.cornerThickness, 2)
	Components.text(page, "GALACTIC WAR", "header",
		UDim2.new(0.58, 0, 0, 24), UDim2.new(0, 0, 0, 0))
	local sectorReadout = Components.text(page, "", "mono",
		UDim2.new(0.42, 0, 0, 24), UDim2.new(0.58, 0, 0, 0))
	sectorReadout.TextSize = Tokens.Type.sizeSmall
	sectorReadout.TextColor3 = Tokens.Color.textAccent
	sectorReadout.TextXAlignment = Enum.TextXAlignment.Right
	sectorReadout.TextTruncate = Enum.TextTruncate.AtEnd
	local statusLine = Components.text(page, "", "mono",
		UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 30))
	statusLine.TextSize = Tokens.Type.sizeSmall
	statusLine.TextColor3 = Tokens.Color.textSecondary
	deployState.statusLine = statusLine

	local function setStatus(text: string, color: Color3?)
		statusLine.Text = text
		statusLine.TextColor3 = color or Tokens.Color.textSecondary
	end

	-- PLANET strip: the existing theaters are the war's selectable planets. Sector names are
	-- a presentation-only projection of the fixed biome/neighbor clusters; region ids remain authoritative.
	local theaterRow = Instance.new("ScrollingFrame")
	theaterRow.Name = "PlanetRow"
	theaterRow.Size = UDim2.new(1, 0, 0, 56)
	theaterRow.Position = UDim2.new(0, 0, 0, 54)
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

	local contentTop = 122

	-- PLANET panel center-left: near-black holographic surface, cyan scan treatment, full
	-- state words, LIBERATION/DEFENSE and EFFECTS in the reference vocabulary.
	local intelPanel = Components.panel(page,
		UDim2.new(0, 300, 1, -242), UDim2.new(0, 0, 0, contentTop))
	intelPanel.BackgroundColor3 = PANEL_NAVY
	intelPanel.BackgroundTransparency = 0.02
	local panelPadding = intelPanel:FindFirstChildOfClass("UIPadding")
	if panelPadding then
		panelPadding:Destroy()
	end
	local scanTexture = Components.scanlineField(intelPanel, 32, 22, Tokens.Color.techCyan)
	scanTexture.ZIndex = 1
	local topScan = Components.scanline(intelPanel,
		UDim2.new(1, -Tokens.Space.md * 2, 0, Tokens.Size.scanlineHeight), Tokens.Color.techCyan, 0.48)
	topScan.Position = UDim2.new(0, Tokens.Space.md, 0, 5)
	topScan.ZIndex = 2
	Components.cornerBracket(intelPanel, "topRight", 13, Tokens.Color.techCyan, 1, 3)
	Components.cornerBracket(intelPanel, "bottomLeft", 13, Tokens.Color.borderStrong, 1, 3)

	local intelScroll = Instance.new("ScrollingFrame")
	intelScroll.Name = "PlanetIntelScroll"
	intelScroll.Size = UDim2.new(1, 0, 1, 0)
	intelScroll.BackgroundTransparency = 1
	intelScroll.BorderSizePixel = 0
	intelScroll.ScrollBarThickness = 2
	intelScroll.ScrollBarImageColor3 = Tokens.Color.steel
	intelScroll.ScrollBarImageTransparency = 0.3
	intelScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	intelScroll.CanvasSize = UDim2.new(0, 0, 0, 500)
	intelScroll.ZIndex = 3
	intelScroll.Parent = intelPanel

	Components.text(intelScroll, "PLANET STATUS", "overline",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 10))
	local regionTitle = Components.text(intelScroll, "", "body",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 24), UDim2.new(0, Tokens.Space.md, 0, 30))
	regionTitle.Font = Tokens.Type.fontBold
	regionTitle.TextSize = Tokens.Type.sizeBodyLarge
	local biomeLabel = Components.text(intelScroll, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 56))
	local stateLabel = Components.text(intelScroll, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 76))
	local campaignLabel = Components.text(intelScroll, "", "metric",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 28), UDim2.new(0, Tokens.Space.md, 0, 98))
	campaignLabel.TextSize = Tokens.Type.sizeSubtitle

	-- two-tone contested control bar: Super Earth blue/cyan against hostile red on
	-- a dark backing. The fills meet at the current control boundary instead of using one
	-- optimistic status color across the whole bar.
	local barTrack = Instance.new("Frame")
	barTrack.Name = "LiberationTrack"
	barTrack.Size = UDim2.new(1, -Tokens.Space.md * 2, 0, 10)
	barTrack.Position = UDim2.new(0, Tokens.Space.md, 0, 132)
	barTrack.BackgroundColor3 = Tokens.Color.panelInset
	barTrack.BackgroundTransparency = 0.08
	barTrack.BorderSizePixel = 0
	barTrack.ClipsDescendants = true
	barTrack.Parent = intelScroll
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = Tokens.Color.borderStrong
	trackStroke.Transparency = 0.38
	trackStroke.Thickness = 1
	trackStroke.Parent = barTrack
	local liberationFill = Instance.new("Frame")
	liberationFill.Name = "LiberationFill"
	liberationFill.Size = UDim2.new(0, 0, 1, 0)
	liberationFill.BackgroundColor3 = SUPER_EARTH_BLUE
	liberationFill.BorderSizePixel = 0
	liberationFill.ZIndex = 1
	liberationFill.Parent = barTrack
	local occupationFill = Instance.new("Frame")
	occupationFill.Name = "OccupationFill"
	occupationFill.Size = UDim2.new(0, 0, 1, 0)
	occupationFill.Position = UDim2.new(1, 0, 0, 0)
	occupationFill.AnchorPoint = Vector2.new(1, 0)
	occupationFill.BackgroundColor3 = ENEMY_RED
	occupationFill.BorderSizePixel = 0
	occupationFill.ZIndex = 1
	occupationFill.Parent = barTrack
	local midpoint = Instance.new("Frame")
	midpoint.Name = "Midpoint"
	midpoint.Size = UDim2.new(0, 1, 1, 0)
	midpoint.Position = UDim2.new(0.5, 0, 0, 0)
	midpoint.BackgroundColor3 = Tokens.Color.textPrimary
	midpoint.BackgroundTransparency = 0.25
	midpoint.BorderSizePixel = 0
	midpoint.ZIndex = 3
	midpoint.Parent = barTrack

	local barLabel = Components.text(intelScroll, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 148))
	local frontLabel = Components.text(intelScroll, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 170))
	local forceLabel = Components.text(intelScroll, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 190))
	local divider = Components.divider(intelScroll, "horizontal", 1, Tokens.Color.border)
	divider.Size = UDim2.new(1, -Tokens.Space.md * 2, 0, 1)
	divider.Position = UDim2.new(0, Tokens.Space.md, 0, 216)

	Components.text(intelScroll, "EFFECTS", "overline",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 228))
	local effectOne = Components.text(intelScroll, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 44), UDim2.new(0, Tokens.Space.md, 0, 248))
	effectOne.TextWrapped = true
	effectOne.TextYAlignment = Enum.TextYAlignment.Top
	effectOne.TextColor3 = Tokens.Color.warning
	effectOne.TextSize = Tokens.Type.sizeMicro
	local effectTwo = Components.text(intelScroll, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 44), UDim2.new(0, Tokens.Space.md, 0, 296))
	effectTwo.TextWrapped = true
	effectTwo.TextYAlignment = Enum.TextYAlignment.Top
	effectTwo.TextColor3 = Tokens.Color.techCyan
	effectTwo.TextSize = Tokens.Type.sizeMicro
	local situationDivider = Components.divider(intelScroll, "horizontal", 1, Tokens.Color.border)
	situationDivider.Size = UDim2.new(1, -Tokens.Space.md * 2, 0, 1)
	situationDivider.Position = UDim2.new(0, Tokens.Space.md, 0, 350)
	Components.text(intelScroll, "SITUATION READOUT", "overline",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 362))
	local situationBody = Components.text(intelScroll, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 92), UDim2.new(0, Tokens.Space.md, 0, 382))
	situationBody.TextWrapped = true
	situationBody.TextXAlignment = Enum.TextXAlignment.Left
	situationBody.TextYAlignment = Enum.TextYAlignment.Top
	situationBody.TextColor3 = Tokens.Color.textPrimary

	-- operations/missions column on the RIGHT, matching the HD2 planet-view anchor.
	-- The deep-navy backing makes this a manufactured command panel rather than rows floating
	-- on the hologram ground.
	local operationsPanel = Components.panel(page,
		UDim2.new(1, -312, 1, -242), UDim2.new(0, 312, 0, contentTop))
	operationsPanel.Name = "OperationsPanel"
	operationsPanel.BackgroundColor3 = PANEL_NAVY
	operationsPanel.BackgroundTransparency = 0.04
	local operationsPadding = operationsPanel:FindFirstChildOfClass("UIPadding")
	if operationsPadding then
		operationsPadding:Destroy()
	end
	Components.text(operationsPanel, "OPERATIONS // MISSIONS", "overline",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 9))
	local operationsRule = Components.scanline(operationsPanel,
		UDim2.new(1, -Tokens.Space.md * 2, 0, 1), Tokens.Color.techCyan, 0.58)
	operationsRule.Position = UDim2.new(0, Tokens.Space.md, 0, 30)
	local opList = Components.list(operationsPanel,
		UDim2.new(1, -Tokens.Space.md * 2, 1, -42), UDim2.new(0, Tokens.Space.md, 0, 38))
	opList.ScrollBarImageColor3 = Tokens.Color.techCyan
	deployState.opList = opList

	local function updateTheaterIntel(rid: string)
		local sectorStatus = workspace:GetAttribute("GF_WarStatus")
		local sectorLine = workspace:GetAttribute("GF_WarSector")
		if type(sectorStatus) == "string" and type(sectorLine) == "string" and sectorLine ~= "" then
			sectorReadout.Text = string.upper("SECTOR — " .. sectorStatus .. " // " .. sectorLine)
		elseif type(sectorLine) == "string" and sectorLine ~= "" then
			sectorReadout.Text = string.upper("SECTOR — " .. sectorLine)
		else
			sectorReadout.Text = "SECTOR — " .. sectorDisplayName(rid) .. " // GALACTIC WAR"
		end

		local control = liveControl(rid)
		local front = liveFront(rid)
		local status = liveStatus(rid)
		local pct = control and math.floor(control * 100 + 0.5) or nil
		local statusColor = Tokens.StatusColor[status] or Tokens.Color.textSecondary
		local frontKey = string.lower(front)
		local defenseOpen = workspace:GetAttribute("GF_WarDefenseOpen") == rid
		-- HD2 semantics: DEFENSE means Super Earth already holds enough ground to defend it;
		-- enemy-dominated planets remain LIBERATION campaigns even when resistance is heavy.
		local defense = defenseOpen
			or status == "established_superiority"
			or status == "gf_offensive"
			or (control ~= nil and control >= 0.55)
		local campaign = defense and "DEFENSE" or "LIBERATION"

		regionTitle.Text = regionDisplayName(rid)
		biomeLabel.Text = "SECTOR — " .. sectorDisplayName(rid) .. " · BIOME — " .. biomeDisplayName(rid)
		biomeLabel.TextSize = Tokens.Type.sizeMicro
		biomeLabel.TextColor3 = Tokens.Color.textSecondary
		stateLabel.Text = "STATE — " .. statusLabel(status)
		stateLabel.TextColor3 = statusColor

		local defenseRemaining = tonumber(workspace:GetAttribute("GF_WarDefenseSeconds_" .. rid))
		local defenseEnd = tonumber(workspace:GetAttribute("GF_WarDefenseEnd_" .. rid))
		local defenseClock = nil :: string?
		if defenseRemaining then
			defenseClock = formatTMinus(defenseRemaining)
		elseif defenseEnd then
			defenseClock = formatTMinus(defenseEnd - os.time())
		end
		campaignLabel.Text = pct and string.format("%s %d%%", campaign, pct) or campaign
		if defense and defenseClock then
			campaignLabel.Text = campaignLabel.Text .. " · " .. defenseClock
		end
		campaignLabel.TextColor3 = defense and Tokens.Color.warning or Tokens.Color.techCyan

		-- Unknown telemetry still leaves a contested two-tone hologram rather than pretending
		-- either side owns the bar; the words underneath remain honest about the missing snapshot.
		local liberation = control or 0.5
		local occupation = 1 - liberation
		tweenVisual(liberationFill, { Size = UDim2.new(liberation, 0, 1, 0) }, Tokens.Motion.medium)
		tweenVisual(occupationFill, { Size = UDim2.new(occupation, 0, 1, 0) }, Tokens.Motion.medium)
		barLabel.Text = pct and string.format("SUPER EARTH %d%% · ASCENDANCY %d%%", pct, 100 - pct)
			or "AWAITING ORBITAL TELEMETRY"
		barLabel.TextColor3 = pct and Tokens.Color.textSecondary or Tokens.Color.textDisabled
		frontLabel.Text = "FRONT — " .. string.upper(front)
		if string.find(frontKey, "enemy") or string.find(frontKey, "contested") or string.find(frontKey, "active front") then
			frontLabel.TextColor3 = Tokens.Color.warning
		elseif string.find(frontKey, "gf") or string.find(frontKey, "advance") then
			frontLabel.TextColor3 = Tokens.Color.techCyan
		else
			frontLabel.TextColor3 = Tokens.Color.textSecondary
		end

		local human = tonumber(workspace:GetAttribute("GF_WarState_" .. rid .. "_H"))
		local enemy = tonumber(workspace:GetAttribute("GF_WarState_" .. rid .. "_E"))
		if human and enemy then
			forceLabel.Text = string.format("FORCE BALANCE — SUPER EARTH %.2f · ASCENDANCY %.2f", human, enemy)
		else
			forceLabel.Text = "FORCE BALANCE — NO SNAPSHOT"
		end
		forceLabel.TextColor3 = Tokens.Color.textSecondary

		local effectBand = math.floor((pct or 50) / 10)
		local effectSeed = stableHash(table.concat({ rid, status, front, tostring(effectBand) }, "|") .. "|effects")
		local firstEffect = biomeEffectPair(rid, effectSeed)
		effectOne.Text = string.format("ENVIRONMENTAL CONDITIONS — %s: %s", firstEffect[1], firstEffect[2])
		local modifierLine = "NONE REPORTED"
		if (deployState.difficultyTier or 4) >= 6 then
			local modifier = operationModifierForSeed(effectSeed)
			modifierLine = string.format("%s: %s", modifier[1], modifier[2])
		end
		effectTwo.Text = "OPERATION MODIFIERS — " .. modifierLine
		situationBody.Text = situationReadout(rid, control, front, status)
	end

	local function paintTheaterButtons()
		for rid, button in pairs(deployState.regionButtons) do
			local status = liveStatus(rid)
			button.Text = regionDisplayName(rid) .. "\n"
				.. sectorDisplayName(rid) .. " SECTOR\n"
				.. statusLabel(status)
			paintWarButton(button, rid == deployState.region, false)
			local strip = deployState.regionStripes[rid]
			if strip then
				local control = liveControl(rid) or 0.5
				local liberation = strip:FindFirstChild("LiberationFill")
				local occupation = strip:FindFirstChild("OccupationFill")
				if liberation and liberation:IsA("Frame") then
					tweenVisual(liberation, { Size = UDim2.new(control, 0, 1, 0) }, Tokens.Motion.fast)
				end
				if occupation and occupation:IsA("Frame") then
					tweenVisual(occupation, { Size = UDim2.new(1 - control, 0, 1, 0) }, Tokens.Motion.fast)
				end
			end
		end
	end

	local function paintOperationRows()
		for opId, button in pairs(deployState.opButtons) do
			local selected = opId == deployState.operationId
			button.Text = selected and "MISSION\nLOCKED" or "SELECT\nMISSION"
			paintWarButton(button, selected, false)
			local row = deployState.opRows[opId]
			if row then
				-- The design-system row painter owns the amber committed-selection material;
				-- custom operation lines are then recolored within that contract.
				Components.setRowSelected(row, selected)
				local edge = row:FindFirstChild("SelectionEdge")
				if edge and edge:IsA("Frame") then
					edge.Visible = selected
				end
				local tierHasModifiers = (deployState.difficultyTier or 4) >= 6
				for _, child in ipairs(row:GetChildren()) do
					if child:IsA("TextLabel") then
						local textKind = child:GetAttribute("GFOperationText")
						if textKind == "modifier" then
							child.Text = tierHasModifiers
								and tostring(child:GetAttribute("GFModifierText") or child.Text)
								or "OPERATION MODIFIERS — NONE REPORTED"
						end
						if selected then
							child.TextColor3 = Tokens.Color.textOnAccent
						else
							if textKind == "operation" or textKind == "mission" then
								child.TextColor3 = Tokens.Color.textAccent
							elseif textKind == "objective" then
								child.TextColor3 = Tokens.Color.warning
							elseif textKind == "modifier" then
								child.TextColor3 = tierHasModifiers and Tokens.Color.warning or Tokens.Color.textDisabled
							elseif textKind == "dispatch" then
								child.TextColor3 = Tokens.Color.textSecondary
							else
								child.TextColor3 = Tokens.Color.textPrimary
							end
						end
					end
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
			setStatus(string.upper(string.format("MISSION COORDINATES LOCKED — %s // PLANET %s // %s",
				name, regionDisplayName(deployState.region), tierLabel(deployState.difficultyTier or tierIndexForWire(deployState.difficulty)))), Tokens.Color.warning)
		else
			setStatus("SELECT AN OPERATION — SUPER EARTH IS COUNTING ON YOU", Tokens.Color.textSecondary)
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

	-- HD2's cycled bottom-center difficulty selector, expanded here into a scrollable
	-- ten-tier strip so every tier remains readable as NUMBER + NAME on narrow screens.
	local diffBar = Instance.new("ScrollingFrame")
	diffBar.Name = "DifficultySelector"
	diffBar.Size = UDim2.new(0.86, 0, 0, 52)
	diffBar.Position = UDim2.new(0.5, 0, 1, -112)
	diffBar.AnchorPoint = Vector2.new(0.5, 0)
	diffBar.BackgroundTransparency = 1
	diffBar.BorderSizePixel = 0
	diffBar.ScrollBarThickness = 0
	diffBar.ScrollingDirection = Enum.ScrollingDirection.X
	diffBar.AutomaticCanvasSize = Enum.AutomaticSize.X
	diffBar.CanvasSize = UDim2.new(0, 0, 0, 0)
	diffBar.ClipsDescendants = true
	diffBar.Parent = page
	local diffLayout = Instance.new("UIListLayout")
	diffLayout.FillDirection = Enum.FillDirection.Horizontal
	diffLayout.Padding = UDim.new(0, Tokens.Space.xs)
	diffLayout.SortOrder = Enum.SortOrder.LayoutOrder
	diffLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	diffLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	diffLayout.Parent = diffBar

	local function difficultyLocked(difficulty: string): boolean
		local rank = deployState.rank
		return rank ~= nil and rank < (DIFFICULTY_RANK[difficulty] or 1)
	end

	local function tierLocked(index: number): boolean
		local spec = DIFFICULTY_TIERS[index]
		return spec ~= nil and difficultyLocked(spec.wire)
	end

	local function refreshDiffSelection()
		-- A late profile push can reveal that the preselected tier is locked. Fall back to
		-- the highest open HD2 tier; because tiers are grouped, the wire difficulty follows.
		if difficultyLocked(deployState.difficulty) then
			for index = #DIFFICULTY_TIERS, 1, -1 do
				if not tierLocked(index) then
					deployState.difficultyTier = index
					deployState.difficulty = DIFFICULTY_TIERS[index].wire
					break
				end
			end
		end
		for index, spec in ipairs(DIFFICULTY_TIERS) do
			local chip = deployState.diffButtons[index]
			if chip then
				local needed = DIFFICULTY_RANK[spec.wire] or 1
				local locked = tierLocked(index)
				local access
				if deployState.rank == nil then
					access = "RANK " .. tostring(needed)
				elseif locked then
					access = "LOCKED · RANK " .. tostring(needed)
				else
					access = "OPEN · RANK " .. tostring(needed)
				end
				chip.Text = string.format("%d %s\n%s", spec.number, spec.name, access)
				paintWarButton(chip, index == deployState.difficultyTier, locked)
			end
		end
	end

	for diffIdx, spec in ipairs(DIFFICULTY_TIERS) do
		local tierIndex = diffIdx
		local tierSpec = spec
		local chip = createWarButton(diffBar, string.format("%d %s", tierSpec.number, tierSpec.name), Tokens.Type.sizeSmall)
		chip.Size = UDim2.new(0, 148, 1, 0)
		chip.LayoutOrder = tierIndex
		chip.Font = Tokens.Type.fontMono
		chip.TextSize = Tokens.Type.sizeMicro
		deployState.diffButtons[tierIndex] = chip
		bindWarButton(chip, refreshDiffSelection)
		chip.Activated:Connect(function()
			if deployState.committing then
				return
			end
			if tierLocked(tierIndex) then
				setStatus(string.upper(string.format("%s locked — requires military rank %d",
					tierLabel(tierIndex), DIFFICULTY_RANK[tierSpec.wire] or 1)), Tokens.Color.warning)
				return
			end
			deployState.difficultyTier = tierIndex
			deployState.difficulty = tierSpec.wire
			refreshDiffSelection()
			updateTheaterIntel(deployState.region)
			paintOperationRows()
			updateCommitmentStatus()
		end)
	end

	-- bottom-center dive commitment — HD2's READY UP / PREPARE TO DIVE ritual surface
	local deployBtn = createWarButton(page, "PREPARE TO DIVE", Tokens.Type.sizeTitle)
	deployBtn.Size = UDim2.new(0.52, 0, 0, 52)
	deployBtn.Position = UDim2.new(0.5, 0, 1, -54)
	deployBtn.AnchorPoint = Vector2.new(0.5, 0)
	local deployVisualState = "ready"

	local function paintDeployButton()
		local stroke = deployBtn:FindFirstChildOfClass("UIStroke")
		local edge = deployBtn:FindFirstChild("AccentEdge")
		local chamfer = deployBtn:FindFirstChild("Chamfer_topRight")
		local hover = deployBtn:GetAttribute("GF_Hover") == true or deployBtn:GetAttribute("GF_Focused") == true
		local background = hover and Tokens.Color.navy or Tokens.Color.panelRaised
		local text = Tokens.Color.textAccent
		local lineColor = Tokens.Color.techCyan
		local lineTransparency = hover and 0.1 or 0.4
		local accent = Tokens.Color.techCyan
		local accentTransparency = hover and 0.12 or 0.34

		if deployVisualState == "pending" then
			background = Tokens.Color.accentSelect
			text = Tokens.Color.textOnAccent
			lineColor = Tokens.Color.accentSelect
			lineTransparency = 0
			accent = Tokens.Color.textOnAccent
			accentTransparency = 0.04
		elseif deployVisualState == "accepted" then
			background = Tokens.Color.success
			text = Tokens.Color.textOnAccent
			lineColor = Tokens.Color.success
			lineTransparency = 0
			accent = Tokens.Color.textOnAccent
			accentTransparency = 0.04
		elseif deployVisualState == "refused" then
			background = Tokens.Color.panelRaised
			text = Tokens.Color.warning
			lineColor = Tokens.Color.danger
			lineTransparency = 0.15
			accent = Tokens.Color.danger
			accentTransparency = 0.08
		end

		tweenVisual(deployBtn, { BackgroundColor3 = background, TextColor3 = text }, Tokens.Motion.fast)
		if stroke then
			tweenVisual(stroke, { Color = lineColor, Transparency = lineTransparency, Thickness = 2 }, Tokens.Motion.fast)
		end
		if edge and edge:IsA("Frame") then
			tweenVisual(edge, { BackgroundColor3 = accent, BackgroundTransparency = accentTransparency }, Tokens.Motion.fast)
		end
		if chamfer and chamfer:IsA("Frame") then
			tweenVisual(chamfer, { BackgroundColor3 = accent, BackgroundTransparency = math.min(0.92, accentTransparency + 0.08) }, Tokens.Motion.fast)
		end
	end

	local function armDeployButton()
		deployState.committing = false
		deployVisualState = "ready"
		deployBtn.Text = "PREPARE TO DIVE"
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
			setStatus("SELECT AN OPERATION — MISSION COORDINATES NOT LOCKED", Tokens.Color.warning)
			return
		end
		if difficultyLocked(deployState.difficulty) then
			setStatus(string.upper(string.format("%s locked — requires military rank %d",
				tierLabel(deployState.difficultyTier or tierIndexForWire(deployState.difficulty)), DIFFICULTY_RANK[deployState.difficulty] or 1)), Tokens.Color.warning)
			return
		end

		deployState.commitToken += 1
		local token = deployState.commitToken
		local commitStartedAt = os.clock()
		deployState.committing = true
		deployVisualState = "pending"
		deployBtn.Text = "READY UP — T-00:08"
		deployBtn.Active = false
		paintDeployButton()
		setStatus("READY UP TRANSMITTED — COMMAND RESPONSE T-00:08", Tokens.Color.warning)
		task.spawn(function()
			while deployState.committing
				and deployState.commitToken == token
				and deployVisualState == "pending"
			do
				local remaining = math.max(0, 8 - (os.clock() - commitStartedAt))
				deployBtn.Text = "READY UP — " .. formatTMinus(remaining)
				setStatus("READY UP TRANSMITTED — COMMAND RESPONSE " .. formatTMinus(remaining), Tokens.Color.warning)
				task.wait(0.25)
			end
		end)
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
				deployBtn.Text = "PREPARE TO DIVE — RETRY"
				deployBtn.Active = true
				paintDeployButton()
				setStatus("DIVE UNCONFIRMED — SUPER EARTH COMMAND DID NOT RESPOND", Tokens.Color.warning)
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
					deployBtn.Text = "HELLPODS PRIMED"
					deployBtn.Active = false
					paintDeployButton()
					setStatus("HELLPODS PRIMED — DIVE INBOUND", Tokens.Color.success)
					task.delay(0.8, function()
						if deployState.commitToken == token and deployVisualState == "accepted" then
							if shell.visible then
								shell:close()
							end
							armDeployButton()
						end
					end)
				else
					local reason = string.upper(tostring(payload.reason or "unknown reason"))
					deployState.committing = false
					deployVisualState = "refused"
					deployBtn.Text = "PREPARE TO DIVE — RETRY"
					deployBtn.Active = true
					paintDeployButton()
					setStatus("MISSION PREPARATION ABORTED — " .. reason, Tokens.Color.danger)
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
				updateTheaterIntel(deployState.region)
				paintOperationRows()
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
				updateTheaterIntel(deployState.region)
				paintOperationRows()
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
			local objective = mission and mission.primary or "COMMAND ORDERS UNAVAILABLE"
			local family = def.family or "Default"
			local operationCopy = hd2OperationCopy(opId, family)
			local missionCopy = hd2MissionCopy(templateId, family)
			local modifier = operationModifierForSeed(stableHash(opId .. "|" .. rid .. "|modifier"))

			local row = Components.row(opList, string.upper(name), nil)
			row.LayoutOrder = order
			row.Size = UDim2.new(1, 0, 0, 124)
			-- Current Components.row is already manually composed and carries RowBorder;
			-- do not add a second layout constraint or border here.
			local edge = Instance.new("Frame")
			edge.Name = "SelectionEdge"
			edge.Size = UDim2.new(0, 4, 1, 0)
			edge.Position = UDim2.new(0, 0, 0, 0)
			edge.BackgroundColor3 = Tokens.Color.textOnAccent
			edge.BorderSizePixel = 0
			edge.Visible = false
			edge.ZIndex = 2
			edge.Parent = row

			local titleLabel = findRowText(row, "primary")
			if titleLabel then
				titleLabel.Text = "OPERATION — " .. operationCopy .. " // " .. string.upper(name)
				titleLabel:SetAttribute("GFOperationText", "operation")
				titleLabel.Position = UDim2.new(0, Tokens.Space.md, 0, 8)
				titleLabel.Size = UDim2.new(1, -168, 0, 20)
				titleLabel.Font = Tokens.Type.fontBold
				titleLabel.TextXAlignment = Enum.TextXAlignment.Left
			end

			local metaLabel = Components.text(row, string.format("MISSION — %s // %s · %s · %s",
				missionCopy, string.upper(templateName), string.upper(family), string.upper(duration)), "caption")
			metaLabel.Position = UDim2.new(0, Tokens.Space.md, 0, 32)
			metaLabel.Size = UDim2.new(1, -168, 0, 15)
			metaLabel.TextColor3 = Tokens.Color.textAccent
			metaLabel:SetAttribute("GFOperationText", "mission")

			local objectiveLabel = Components.text(row, "MAIN OBJECTIVE — " .. objective, "caption")
			objectiveLabel.Position = UDim2.new(0, Tokens.Space.md, 0, 50)
			objectiveLabel.Size = UDim2.new(1, -168, 0, 15)
			objectiveLabel.TextColor3 = Tokens.Color.warning
			objectiveLabel:SetAttribute("GFOperationText", "objective")

			local modifierText = string.format("OPERATION MODIFIERS — %s: %s", modifier[1], modifier[2])
			local modifierLabel = Components.text(row, modifierText, "caption")
			modifierLabel.Position = UDim2.new(0, Tokens.Space.md, 0, 68)
			modifierLabel.Size = UDim2.new(1, -168, 0, 15)
			modifierLabel.TextColor3 = Tokens.Color.warning
			modifierLabel:SetAttribute("GFOperationText", "modifier")
			modifierLabel:SetAttribute("GFModifierText", modifierText)

			local flavorLabel = Components.text(row, "DISPATCH — " .. operationFlavor(opId, family, rid), "caption")
			flavorLabel.Position = UDim2.new(0, Tokens.Space.md, 0, 86)
			flavorLabel.Size = UDim2.new(1, -168, 0, 30)
			flavorLabel.TextWrapped = true
			flavorLabel.TextYAlignment = Enum.TextYAlignment.Top
			flavorLabel.TextColor3 = Tokens.Color.textSecondary
			flavorLabel:SetAttribute("GFOperationText", "dispatch")

			-- The intel panel itself is part of the mission-selection target, like clicking a
			-- mission card on the war table. The visible SELECT MISSION button remains the focus.
			local rowHit = Instance.new("TextButton")
			rowHit.Name = "OperationHitTarget"
			rowHit.Size = UDim2.new(1, -158, 1, 0)
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

			local pick = createWarButton(row, "SELECT\nMISSION", Tokens.Type.sizeSmall)
			pick.Size = UDim2.new(0, 128, 0, Tokens.Size.buttonHeight)
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
			setStatus("NO OPERATIONS AVAILABLE ON THIS PLANET", Tokens.Color.warning)
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
		button.Size = UDim2.new(0, 210, 1, -4)
		button.LayoutOrder = rIdx
		button.TextSize = Tokens.Type.sizeMicro
		local buttonPadding = Instance.new("UIPadding")
		buttonPadding.PaddingBottom = UDim.new(0, Tokens.Space.sm)
		buttonPadding.Parent = button
		deployState.regionButtons[rid] = button
		local stripe = Instance.new("Frame")
		stripe.Name = "LiberationStrip"
		stripe.Size = UDim2.new(1, -Tokens.Space.sm * 2, 0, 4)
		stripe.Position = UDim2.new(0, Tokens.Space.sm, 1, -6)
		stripe.BackgroundColor3 = Tokens.Color.panelInset
		stripe.BackgroundTransparency = 0.08
		stripe.BorderSizePixel = 0
		stripe.ClipsDescendants = true
		stripe.Parent = button
		local liberation = Instance.new("Frame")
		liberation.Name = "LiberationFill"
		liberation.Size = UDim2.new(0.5, 0, 1, 0)
		liberation.BackgroundColor3 = SUPER_EARTH_BLUE
		liberation.BorderSizePixel = 0
		liberation.Parent = stripe
		local occupation = Instance.new("Frame")
		occupation.Name = "OccupationFill"
		occupation.Size = UDim2.new(0.5, 0, 1, 0)
		occupation.Position = UDim2.new(1, 0, 0, 0)
		occupation.AnchorPoint = Vector2.new(1, 0)
		occupation.BackgroundColor3 = ENEMY_RED
		occupation.BorderSizePixel = 0
		occupation.Parent = stripe
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
			if shell.visible and shell.active == "WAR TABLE" then
				updateTheaterIntel(deployState.region)
				paintTheaterButtons()
			end
		end
	end)
end)

-- Current Components.row composes its text manually and marks it with GFRowText
-- ("primary"/"caption") instead of offering a stable child-name contract. Action rows only
-- need to reserve horizontal space for the right-side control; the defensive layout cleanup
-- remains for legacy rows created before that contract change.
local function prepareActionRow(row: Frame, rightReserve: number)
	local rowLayout = row:FindFirstChildOfClass("UIListLayout")
	if rowLayout then
		rowLayout:Destroy()
	end
	local rowPadding = row:FindFirstChildOfClass("UIPadding")
	if rowPadding then
		rowPadding:Destroy()
	end
	local textWidthOffset = -(rightReserve + Tokens.Space.md)
	local primary = findRowText(row, "primary")
	if primary then
		primary.Position = UDim2.new(0, Tokens.Space.md, 0, 5)
		primary.Size = UDim2.new(1, textWidthOffset, 0, Tokens.Type.sizeBody + Tokens.Space.xs)
		primary.TextXAlignment = Enum.TextXAlignment.Left
	end
	local caption = findRowText(row, "caption")
	if caption then
		caption.Position = UDim2.new(0, Tokens.Space.md, 0, 29)
		caption.Size = UDim2.new(1, textWidthOffset, 0, Tokens.Type.sizeSmall + Tokens.Space.xs)
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
		-- The design-system selection painter owns the angular state machine now; manual
		-- amber painting is only the compatibility fallback for legacy surfaces.
		Components.setButtonSelected(b, selected)
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
			local heading = string.format("SOS BEACON — %s", string.upper(tostring(beacon.region or beacon.id or "UNKNOWN")))
			local caption = string.format("%s · %d SEATS · %s ELAPSED",
				string.upper(tostring(beacon.difficulty or "?")), tonumber(beacon.seats) or 0, formatTMinus(tonumber(beacon.age) or 0))
			local key = string.format("%014d", tonumber(beacon.openedAtUTC) or 0) .. "_" .. tostring(beacon.id)
			joinRow(list, order, heading, caption, Tokens.Color.warning, function()
				if browserState.statusLine then
					browserState.statusLine.Text = "ANSWERING SOS BEACON…"
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
							browserState.statusLine.Text = result.teleporting and "GAME FOUND — DIVE INBOUND" or "JOINED — INSERTION INBOUND"
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
		browserState.statusLine.Text = "No forming squads or active SOS beacons across the fleet — form one and it appears here for everyone."
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
local Input = require(script.Parent:WaitForChild("Input"))

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
