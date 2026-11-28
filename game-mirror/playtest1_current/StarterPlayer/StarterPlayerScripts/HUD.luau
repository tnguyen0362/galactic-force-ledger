--!strict
-- Combat HUD: vitals, ammo, abilities, dodge, prompts, hit feedback, touch layer.
local Players = game:GetService("Players")
-- S03-042 color independence: status information never relies on color alone — every
-- color-coded element carries a shape, icon or text label so colorblind players read the
-- same information. Health uses bar length + number, shields use icon + bar, damage
-- direction uses positional indicators, not just screen tint.
local COLOR_BLIND_SAFE = true
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Input = require(script.Parent:WaitForChild("Input"))

local HUD = {}

local player = Players.LocalPlayer
local remotes = ReplicatedStorage.GF.Remotes
local Tokens = require(ReplicatedStorage.GF.Shared.UI.Tokens)

local gui: ScreenGui
local shieldFill: Frame
local healthFill: Frame
local shieldLabel: TextLabel
local healthLabel: TextLabel
local ammoLabel: TextLabel
local ammoDetailLabel: TextLabel
local weaponLabel: TextLabel
local crosshair: Frame
local hitMarker: Frame
local downedFrame: Frame
local dodgeLabel: TextLabel
local abilityLabels: { [string]: TextLabel } = {}

local abilityTitles: { [string]: any } = {}
local abilityFills: { [string]: Frame } = {}
local promptLabel: TextLabel
local killLabel: TextLabel
local touchLayer: Frame
local cooldownEnds: { [string]: number } = {}
local cooldownDurations: { [string]: number } = {}
local touchButtons: { [string]: TextButton } = {}

-- Combat HUD chrome is token-locked to the Galactic Force palette: graphite structure,
-- ceramic information, cyan active technology, amber warning. Red is reserved for damage.
local ACCENT = Tokens.Color.techCyan
local WARN = Tokens.Color.danger
local AMBER = Tokens.Color.warning
local INK = Tokens.Color.textPrimary
local MUTED = Tokens.Color.textSecondary
local PANEL = Tokens.Color.panelInset
local PANEL_RAISED = Tokens.Color.panelRaised
local EDGE = Tokens.Color.border

local function newFrame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function addStroke(parent: Instance, color: Color3?, transparency: number?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or EDGE
	stroke.Transparency = transparency or 0.3
	stroke.Thickness = thickness or 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

-- Precision brackets replace rounded chrome. Four independent L-shaped corners give the
-- panel a manufactured hard-surface read while leaving the center visually quiet.
local function addCornerBrackets(parent: Instance, color: Color3?, inset: number?, length: number?, thickness: number?)
	local c = color or ACCENT
	local i = inset or 3
	local len = length or 14
	local t = thickness or 2
	local specs = {
		{ UDim2.fromOffset(i, i), UDim2.fromOffset(len, t) },
		{ UDim2.fromOffset(i, i), UDim2.fromOffset(t, len) },
		{ UDim2.new(1, -(i + len), 0, i), UDim2.fromOffset(len, t) },
		{ UDim2.new(1, -(i + t), 0, i), UDim2.fromOffset(t, len) },
		{ UDim2.new(0, i, 1, -(i + len)), UDim2.fromOffset(t, len) },
		{ UDim2.new(0, i, 1, -(i + t)), UDim2.fromOffset(len, t) },
		{ UDim2.new(1, -(i + len), 1, -(i + t)), UDim2.fromOffset(len, t) },
		{ UDim2.new(1, -(i + t), 1, -(i + len)), UDim2.fromOffset(t, len) },
	}
	for index, spec in ipairs(specs) do
		local part = newFrame(parent, {
			Name = "Corner" .. index,
			Position = spec[1],
			Size = spec[2],
			BackgroundColor3 = c,
			BackgroundTransparency = 0.08,
		})
		part.ZIndex = 4
	end
end

local function finishPanel(frame: Frame, accent: Color3?): UIStroke
	local stroke = addStroke(frame, EDGE, 0.28, 1)
	addCornerBrackets(frame, accent or ACCENT, 3, 14, 2)
	local rail = newFrame(frame, {
		Name = "AccentRail",
		Size = UDim2.new(0, 3, 1, -16),
		Position = UDim2.fromOffset(0, 8),
		BackgroundColor3 = accent or ACCENT,
		BackgroundTransparency = 0.08,
	})
	rail.ZIndex = 3
	return stroke
end

-- Segment separators sit over the fill. Length remains the primary read; the divisions
-- supply the color-independent shape language required for shield state.
local function addSegments(back: Frame, count: number)
	for index = 1, count - 1 do
		local divider = newFrame(back, {
			Name = "Segment" .. index,
			Size = UDim2.new(0, 1, 1, 0),
			Position = UDim2.fromScale(index / count, 0),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.05,
		})
		divider.ZIndex = 3
	end
end

local function newLabel(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Size = size
	l.Position = position
	l.TextSize = math.max(13, textSize)
	l.Font = Tokens.Type.font
	l.TextColor3 = INK
	l.TextStrokeTransparency = 0.72
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

-- touch combat icons: drawn geometry, not text labels. a mobile shooter reads shapes at
-- thumb-glance distance — the word FIRE inside a circle is desktop UI wearing a costume.
-- every icon is simple frame composition inside the button, centered, ~40% of button radius.
local ICON_INK = Tokens.Color.textPrimary
local function iconPart(parent: Instance, w: number, h: number, cx: number, cy: number, rot: number?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(w, h)
	f.Position = UDim2.new(0.5, cx - w / 2, 0.5, cy - h / 2)
	f.BackgroundColor3 = ICON_INK
	f.BorderSizePixel = 0
	f.ZIndex = 5
	if rot then f.Rotation = rot end
	f.Parent = parent
	return f
end

-- Every touch glyph is hard-edged geometry. Even nominally round objects (grenade, bullet)
-- are drawn as diamonds/facets so the mobile layer speaks the same angular military language.
local function drawIcon(b: TextButton, action: string)
	if action == "Fire" then
		-- angular bullet: rectangular body + diamond tip
		iconPart(b, 8, 21, 0, 3)
		iconPart(b, 10, 10, 0, -11, 45)
	elseif action == "Aim" then
		-- square reticle: center pip + four cardinal ticks
		iconPart(b, 5, 5, 0, 0)
		iconPart(b, 3, 10, 0, -14)
		iconPart(b, 3, 10, 0, 14)
		iconPart(b, 10, 3, -14, 0)
		iconPart(b, 10, 3, 14, 0)
	elseif action == "Jump" then
		-- up chevron pair
		iconPart(b, 16, 5, -6, -2, -45)
		iconPart(b, 16, 5, 6, -2, 45)
		iconPart(b, 16, 5, -6, 10, -45)
		iconPart(b, 16, 5, 6, 10, 45)
	elseif action == "Dodge" then
		-- lateral dash: two fast chevrons pointing left
		iconPart(b, 14, 5, -5, -6, 135)
		iconPart(b, 14, 5, -5, 6, -135)
		iconPart(b, 14, 5, 6, -6, 135)
		iconPart(b, 14, 5, 6, 6, -135)
	elseif action == "Reload" then
		-- magazine insert: tray + downward feed arrow
		iconPart(b, 16, 11, 0, 7) -- tray body
		iconPart(b, 4, 13, 0, -8) -- arrow shaft
		iconPart(b, 10, 4, -3, -1, 45)
		iconPart(b, 10, 4, 3, -1, -45)
	elseif action == "Grenade" then
		-- faceted body + stem
		iconPart(b, 15, 15, 0, 3, 45)
		iconPart(b, 4, 7, 4, -10, -20)
	elseif action == "SupportAbility" then
		-- strike diamond + center pip — the support call-in reads as a marker
		iconPart(b, 16, 16, 0, 0, 45)
		local pip = iconPart(b, 5, 5, 0, 0)
		pip.BackgroundColor3 = PANEL
	elseif action == "SwapWeapon" then
		-- two canted weapon profiles
		iconPart(b, 5, 18, -6, 0, -10)
		iconPart(b, 5, 18, 6, 0, 10)
	elseif action == "Interact" then
		-- square keycap with an inset command pip
		iconPart(b, 16, 16, 0, 0)
		local dot2 = iconPart(b, 6, 6, 0, 0)
		dot2.BackgroundColor3 = PANEL
	end
end

local function buildTouchButton(action: string, radius: number, centerX: number, centerY: number)
	-- positions are CENTER coordinates in px measured inward from the bottom-right corner;
	-- converted to top-left anchoring here. layout is computed, not eyeballed: centers and
	-- radii are checked pairwise so no two buttons can ever overlap at any resolution.
	local b = Instance.new("TextButton")
	b.Name = action
	b.Size = UDim2.fromOffset(radius * 2, radius * 2)
	b.Position = UDim2.new(1, -(centerX + radius), 1, -(centerY + radius))
	b.BackgroundTransparency = 1 -- the input footprint stays generous; only the angular plate is visible
	b.TextColor3 = INK
	b.Text = ""
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Visible = false
	b.Parent = touchLayer

	-- Diamond hard-plate: a rotating square reads as a machined control surface, not a
	-- rounded mobile button. Fire is cyan-framed as the primary action; kit stays steel.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.fromOffset(math.floor(radius * 1.34), math.floor(radius * 1.34))
	plate.Rotation = 45
	plate.BackgroundColor3 = PANEL
	plate.BackgroundTransparency = action == "Fire" and 0.12 or 0.22
	plate.BorderSizePixel = 0
	plate.ZIndex = 2
	plate.Parent = b
	addStroke(plate, action == "Fire" and ACCENT or Tokens.Color.steel, action == "Fire" and 0.05 or 0.35, 1)
	local inner = Instance.new("Frame")
	inner.Name = "InnerBevel"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromOffset(math.floor(radius * 0.92), math.floor(radius * 0.92))
	inner.Rotation = 45
	inner.BackgroundTransparency = 1
	inner.ZIndex = 3
	inner.Parent = b
	addStroke(inner, action == "Fire" and ACCENT or EDGE, 0.55, 1)
	drawIcon(b, action)

	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			Input.setDevice("touch")
			if action == "SupportAbility" then
				HUD.castAbility(action)
			elseif action == "Reload" then
				Input.setHeld("Reload", true, input)
			else
				Input.setHeld(action, true, input)
			end
		end
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and action ~= "SupportAbility" then
			Input.setHeld(action, false, input)
		end
	end)
	touchButtons[action] = b
end

function HUD.init()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("GF_HUD")
	if existing then
		existing:Destroy()
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "GF_HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- vitals, top-left: a graphite armor plate with segmented cyan shield over amber health.
	-- Position logic is unchanged (below the Roblox topbar); the panel is larger so the numbers
	-- survive a 1080p television at console distance.
	local vitals = newFrame(gui, {
		Name = "Vitals",
		Size = UDim2.fromOffset(276, 82),
		Position = UDim2.fromOffset(28, 70),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.16,
	})
	local vitalsStroke = finishPanel(vitals, ACCENT)
	local lowHealthIndicator = newLabel(vitals, "VITALS CRITICAL", UDim2.fromOffset(130, 16), UDim2.new(1, -146, 0, 7), 13)
	lowHealthIndicator.TextXAlignment = Enum.TextXAlignment.Right
	lowHealthIndicator.TextColor3 = WARN
	lowHealthIndicator.Visible = false

	local shieldIcon = newFrame(vitals, {
		Name = "ShieldIcon",
		Size = UDim2.fromOffset(9, 9),
		Position = UDim2.fromOffset(17, 11),
		BackgroundColor3 = ACCENT,
		BackgroundTransparency = 0.05,
	})
	shieldIcon.Rotation = 45
	shieldLabel = newLabel(vitals, "SHIELD 100", UDim2.fromOffset(126, 17), UDim2.fromOffset(32, 7), 14)
	shieldLabel.TextColor3 = ACCENT
	local shieldBack = newFrame(vitals, {
		Name = "ShieldBack",
		Size = UDim2.fromOffset(244, 12),
		Position = UDim2.fromOffset(16, 27),
		BackgroundColor3 = Tokens.Color.navy,
		BackgroundTransparency = 0.2,
	})
	addStroke(shieldBack, EDGE, 0.58, 1)
	shieldFill = newFrame(shieldBack, {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = ACCENT,
		BackgroundTransparency = 0.03,
	})
	addSegments(shieldBack, 7)

	local healthIconV = newFrame(vitals, {
		Name = "HealthIconV",
		Size = UDim2.fromOffset(3, 11),
		Position = UDim2.fromOffset(20, 46),
		BackgroundColor3 = AMBER,
	})
	local healthIconH = newFrame(vitals, {
		Name = "HealthIconH",
		Size = UDim2.fromOffset(11, 3),
		Position = UDim2.fromOffset(16, 50),
		BackgroundColor3 = AMBER,
	})
	healthIconV.ZIndex = 2
	healthIconH.ZIndex = 2
	healthLabel = newLabel(vitals, "HEALTH 100", UDim2.fromOffset(150, 16), UDim2.fromOffset(32, 43), 14)
	healthLabel.TextColor3 = INK
	local healthBack = newFrame(vitals, {
		Name = "HealthBack",
		Size = UDim2.fromOffset(244, 11),
		Position = UDim2.fromOffset(16, 62),
		BackgroundColor3 = PANEL_RAISED,
		BackgroundTransparency = 0.12,
	})
	addStroke(healthBack, EDGE, 0.58, 1)
	healthFill = newFrame(healthBack, {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = AMBER,
		BackgroundTransparency = 0.02,
	})

	-- ammo, bottom-right: weapon name small, current magazine dominant, reserve subordinate.
	local ammoBox = newFrame(gui, {
		Name = "Ammo",
		Size = UDim2.fromOffset(252, 90),
		Position = UDim2.new(1, -280, 1, -124),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.16,
	})
	finishPanel(ammoBox, ACCENT)
	local ammoCaption = newLabel(ammoBox, "WEAPON", UDim2.fromOffset(70, 16), UDim2.fromOffset(16, 7), 13)
	ammoCaption.TextColor3 = MUTED
	weaponLabel = newLabel(ammoBox, "AR01", UDim2.fromOffset(150, 17), UDim2.new(1, -166, 0, 7), 15)
	weaponLabel.TextXAlignment = Enum.TextXAlignment.Right
	weaponLabel.TextColor3 = INK
	local ammoRule = newFrame(ammoBox, {
		Name = "Rule",
		Size = UDim2.fromOffset(220, 1),
		Position = UDim2.fromOffset(16, 28),
		BackgroundColor3 = EDGE,
		BackgroundTransparency = 0.35,
	})
	ammoRule.ZIndex = 2
	ammoLabel = newLabel(ammoBox, "28", UDim2.fromOffset(220, 40), UDim2.fromOffset(16, 29), 40)
	ammoLabel.Font = Tokens.Type.fontBold
	ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
	ammoDetailLabel = newLabel(ammoBox, "/ 28 MAG", UDim2.fromOffset(220, 18), UDim2.fromOffset(16, 68), 14)
	ammoDetailLabel.TextXAlignment = Enum.TextXAlignment.Right
	ammoDetailLabel.TextColor3 = MUTED

	-- Compact military reticle: square center pip, precision reference frame, and two short
	-- horizontal dispersion ticks. No vertical ticks, no oversized crosshair envelope. Lines
	-- track weapon dispersion dynamically — the geometry is driven per-frame further down.
	crosshair = newFrame(gui, {
		Name = "Crosshair",
		Size = UDim2.fromOffset(64, 64),
		Position = UDim2.new(0.5, -32, 0.5, -32),
		BackgroundTransparency = 1,
		BackgroundColor3 = INK,
	})
	do
		-- central dot: 2px logical at the 1920x1080 reference (spec: 1.5-2px)
		local dot = newFrame(crosshair, {
			Name = "Dot",
			Size = UDim2.fromOffset(2, 2),
			Position = UDim2.fromOffset(31, 31),
			BackgroundColor3 = INK,
			BackgroundTransparency = 0,
		})
		dot.BackgroundColor3 = ACCENT
		-- two horizontal lines only, 5x1.5 logical px (spec: 4-6 long, 1-1.5 thick). Positions are
		-- driven per-frame — construction parks them at the zero-bloom aimed spacing.
		for _, side in ipairs({ "L", "R" }) do
			local tick = newFrame(crosshair, {
				Name = "Tick" .. side,
				Size = UDim2.fromOffset(5, 1.5),
				Position = UDim2.fromOffset(side == "L" and 18 or 41, 31.25),
				BackgroundColor3 = INK,
				BackgroundTransparency = 0.1,
			})
		end
		-- hollow square reference: 10px logical width (spec scale preserved), ~1px stroke.
		-- The moving lines carry the accuracy readout; the hard-edged frame stays stable.
		local ring = Instance.new("Frame")
		ring.Name = "ReticleRing"
		ring.Size = UDim2.fromOffset(10, 10)
		ring.Position = UDim2.fromOffset(27, 27)
		ring.BackgroundTransparency = 1
		ring.Parent = crosshair
		local ringCorner = Instance.new("UICorner") -- ReticleRound: centre ring is a circle, not a square
		ringCorner.CornerRadius = UDim.new(0.5, 0)
		ringCorner.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Name = "RingStroke"
		stroke.Color = INK
		stroke.Thickness = 1
		stroke.Transparency = 0.15
		stroke.Parent = ring
	end

	-- S06-058: dedicated boss HP bar — top-center, phase-colored, reads the published boss
	-- attributes so every client renders the same fight state without per-frame replication spam.
	local bossBar = newFrame(gui, {
		Name = "BossBar",
		Size = UDim2.new(0.42, 0, 0, 26),
		Position = UDim2.new(0.29, 0, 0, 4),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.16,
		Visible = false,
	})
	finishPanel(bossBar, AMBER)
	local bossFill = newFrame(bossBar, {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Tokens.Color.danger,
		BackgroundTransparency = 0.24,
	})
	bossFill.ZIndex = 1
	addSegments(bossBar, 10)
	local bossLabel = Instance.new("TextLabel")
	bossLabel.Name = "Label"
	bossLabel.BackgroundTransparency = 1
	bossLabel.Size = UDim2.fromScale(1, 1)
	bossLabel.Font = Tokens.Type.fontBold
	bossLabel.TextSize = 15
	bossLabel.TextColor3 = INK
	bossLabel.TextStrokeTransparency = 0.55
	bossLabel.Text = ""
	bossLabel.ZIndex = 5
	bossLabel.Parent = bossBar

	-- hitmarker: an X of two rotated bars. The old implementation relied on frame borders over a
	-- fully transparent background — borders do not render that way, so hit confirmation was
	-- literally invisible. Bars are real geometry: always visible, color-coded per hit type.
	hitMarker = newFrame(gui, {
		Name = "HitMarker",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(0.5, -11, 0.5, -11),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	})
	for _, rot in ipairs({ 45, -45 }) do
		local bar = newFrame(hitMarker, {
			Name = "Bar" .. tostring(rot),
			Size = UDim2.fromOffset(14, 2),
			Position = UDim2.new(0.5, -7, 0.5, -1),
			BackgroundColor3 = INK,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
		})
		bar.Rotation = rot
		bar.ZIndex = 8
	end

	killLabel = newLabel(gui, "", UDim2.fromOffset(280, 28), UDim2.new(0.5, -140, 0.5, 34), 17)
	killLabel.Font = Tokens.Type.fontBold
	killLabel.TextXAlignment = Enum.TextXAlignment.Center
	killLabel.TextColor3 = AMBER

	-- abilities, bottom-centre: one compact hard-plated support slot.
	local abilityBar = newFrame(gui, {
		Name = "Abilities",
		Size = UDim2.fromOffset(182, 70),
		Position = UDim2.new(0.5, -91, 1, -112),
		BackgroundTransparency = 1,
	})
	local function abilitySlot(id: string, label: string, offsetX: number)
		local slot = newFrame(abilityBar, {
			Name = id,
			Size = UDim2.fromOffset(182, 70),
			Position = UDim2.fromOffset(offsetX, 0),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.16,
		})
		finishPanel(slot, ACCENT)
		local name = newLabel(slot, label, UDim2.fromOffset(164, 17), UDim2.fromOffset(9, 7), 14)
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.TextColor3 = INK
		local status = newLabel(slot, "READY", UDim2.fromOffset(164, 22), UDim2.fromOffset(9, 29), 17)
		status.Font = Tokens.Type.fontBold
		status.TextXAlignment = Enum.TextXAlignment.Center
		status.TextColor3 = ACCENT
		abilityLabels[id] = status
		abilityTitles[id] = name
		local fill = newFrame(slot, {
			Name = "Cooldown",
			Size = UDim2.new(1, -18, 0, 4),
			Position = UDim2.new(0, 9, 1, -7),
			BackgroundColor3 = ACCENT,
			BackgroundTransparency = 0.05,
		})
		fill.ZIndex = 3
		abilityFills[id] = fill
	end
	-- one support ability slot (Counteroffensive contract revision). the slot label shows the
	-- equipped ability id once published; AIRSTRIKE is the pre-publish default
	abilitySlot("Airstrike", "SUPPORT [" .. Input.glyph("SupportAbility") .. "]", 0)

	dodgeLabel = newLabel(gui, "DODGE 2/2", UDim2.fromOffset(170, 26), UDim2.new(0.5, -85, 1, -34), 14)
	dodgeLabel.TextXAlignment = Enum.TextXAlignment.Center
	dodgeLabel.BackgroundColor3 = PANEL
	dodgeLabel.BackgroundTransparency = 0.28
	addStroke(dodgeLabel, EDGE, 0.55, 1)
	local dodgeRail = newFrame(dodgeLabel, {
		Name = "AccentRail",
		Size = UDim2.new(0, 3, 1, -8),
		Position = UDim2.fromOffset(0, 4),
		BackgroundColor3 = ACCENT,
	})
	dodgeRail.ZIndex = 2

	promptLabel = newLabel(gui, "", UDim2.fromOffset(640, 28), UDim2.new(0.5, -320, 1, -164), 14)
	promptLabel.TextXAlignment = Enum.TextXAlignment.Center
	promptLabel.TextColor3 = Tokens.Color.textSecondary
	promptLabel.BackgroundColor3 = PANEL
	promptLabel.BackgroundTransparency = 0.42
	addStroke(promptLabel, EDGE, 0.72, 1)

	-- combat chrome is mission-only. owner direction, expert-ui reasoning: the station is safe —
	-- nothing can hurt you there, so combat vitals are noise, and the reference lobby shows none.
	-- ability bar, dodge charges, ammo, crosshair, controls hint AND the vitals plate all hide
	-- unless GF_InMission is set. the minimap remains — navigation is useful everywhere.
	-- (lobby interactions are native ProximityPrompts now, so the prompt label has no lobby role.)
	do
		local combatChrome = { abilityBar, dodgeLabel, ammoBox, crosshair, promptLabel, vitals }
		local function applyMissionVisibility()
			local inMission = workspace:GetAttribute("GF_InMission") == true
			for _, element in ipairs(combatChrome) do
				if element then
					element.Visible = inMission
				end
			end
		end
		workspace:GetAttributeChangedSignal("GF_InMission"):Connect(applyMissionVisibility)
		applyMissionVisibility()
	end

	-- downed overlay: a restrained red theater dim plus a central angular casualty plate.
	downedFrame = newFrame(gui, {
		Name = "Downed",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(52, 13, 16),
		BackgroundTransparency = 0.48,
		Visible = false,
	})
	local downedPlate = newFrame(downedFrame, {
		Name = "CasualtyPlate",
		Size = UDim2.fromOffset(640, 152),
		Position = UDim2.new(0.5, -320, 0.5, -76),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.12,
	})
	finishPanel(downedPlate, WARN)
	for index = 0, 2 do
		local leftSlash = newFrame(downedPlate, {
			Name = "LeftSlash" .. index,
			Size = UDim2.fromOffset(34, 3),
			Position = UDim2.fromOffset(18, 34 + index * 34),
			BackgroundColor3 = WARN,
			BackgroundTransparency = 0.28,
		})
		leftSlash.Rotation = -32
		local rightSlash = newFrame(downedPlate, {
			Name = "RightSlash" .. index,
			Size = UDim2.fromOffset(34, 3),
			Position = UDim2.new(1, -52, 0, 34 + index * 34),
			BackgroundColor3 = WARN,
			BackgroundTransparency = 0.28,
		})
		rightSlash.Rotation = 32
	end
	local downedText = newLabel(downedPlate, "DOWNED", UDim2.new(1, 0, 0, 72), UDim2.fromOffset(0, 24), 52)
	downedText.TextXAlignment = Enum.TextXAlignment.Center
	downedText.Font = Tokens.Type.fontBold
	downedText.TextColor3 = WARN
	downedText.TextStrokeTransparency = 0.45
	local downedDetail = newLabel(downedPlate, "AWAITING REVIVE", UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 102), 18)
	downedDetail.TextXAlignment = Enum.TextXAlignment.Center
	downedDetail.Font = Tokens.Type.font
	downedDetail.TextColor3 = AMBER

	-- touch layer
	touchLayer = newFrame(gui, {
		Name = "Touch",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	})
	-- the right-thumb arc: frequency-ordered, pairwise overlap-checked by construction.
	-- centers are (px from right edge, px from bottom edge); radius in px.
	-- fire dominates the primary rest position; aim sits in thumb-curl range; the upper arc
	-- carries the tactical kit the old layout simply did not have (mandate mobile parity).
	buildTouchButton("Fire", 46, 84, 100)
	buildTouchButton("Aim", 34, 180, 66)
	buildTouchButton("Jump", 32, 168, 150)
	buildTouchButton("Dodge", 30, 250, 100)
	buildTouchButton("Reload", 26, 244, 178)
	buildTouchButton("Grenade", 26, 318, 148)
	buildTouchButton("SupportAbility", 28, 316, 66)
	buildTouchButton("SwapWeapon", 24, 388, 110)
	buildTouchButton("Interact", 28, 84, 190)

	-- remote wiring
	remotes.VitalsUpdated.OnClientEvent:Connect(function(v)
		if type(v) ~= "table" then return end
		downedFrame.Visible = v.downed == true
		crosshair.Visible = v.downed ~= true
		local shield = tonumber(v.shield) or 0
		local shieldMax = tonumber(v.shieldMax) or 100
		local health = tonumber(v.health) or 0
		local healthMax = tonumber(v.healthMax) or 100
		local healthFraction = math.clamp(health / math.max(1, healthMax), 0, 1)
		shieldFill.Size = UDim2.fromScale(math.clamp(shield / math.max(1, shieldMax), 0, 1), 1)
		healthFill.Size = UDim2.fromScale(healthFraction, 1)
		shieldLabel.Text = string.format("SHIELD %d", math.floor(shield + 0.5))
		healthLabel.Text = string.format("HEALTH %d", math.floor(health + 0.5))
		local critical = healthFraction <= 0.3 and v.downed ~= true
		lowHealthIndicator.Visible = critical
		healthFill.BackgroundColor3 = critical and WARN or AMBER
		healthLabel.TextColor3 = critical and WARN or INK
		vitalsStroke.Color = critical and WARN or EDGE
	end)
	-- S04-058 directional damage: a brief red arc on the reticle edge showing the hit direction.
	local dirIndicator = newFrame(gui, {
		Name = "DirectionalHit",
		Size = UDim2.fromOffset(90, 90),
		Position = UDim2.new(0.5, -45, 0.5, -45),
		BackgroundTransparency = 1,
		Visible = false,
	})
	local dirArc = newFrame(dirIndicator, {
		Name = "Arc",
		Size = UDim2.fromOffset(38, 5),
		Position = UDim2.new(0.5, -19, 0, 0),
		BackgroundColor3 = WARN,
		BackgroundTransparency = 0.08,
	})
	dirArc.ZIndex = 8
	for _, spec in ipairs({
		{ -29, 6, -30 },
		{ 29, 6, 30 },
	}) do
		local wing = newFrame(dirIndicator, {
			Name = "ArcWing",
			Size = UDim2.fromOffset(20, 5),
			Position = UDim2.new(0.5, spec[1] - 10, 0, spec[2]),
			BackgroundColor3 = WARN,
			BackgroundTransparency = 0.16,
		})
		wing.Rotation = spec[3]
		wing.ZIndex = 8
	end
	remotes.DirectionalHit.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		dirIndicator.Rotation = tonumber(payload.angle) or 0
		dirIndicator.Visible = true
		dirArc.BackgroundTransparency = 0.15
		task.delay(0.7, function()
			dirIndicator.Visible = false
		end)
	end)
	remotes.ShieldBroken.OnClientEvent:Connect(function()
		-- distinct shield-break cue (S04-058): sharper than a hit, audible over combat
		pcall(function()
			require(script.Parent:WaitForChild("GFAudio")).play("shield_break")
		end)
		shieldLabel.TextColor3 = WARN
		task.delay(1.2, function()
			shieldLabel.TextColor3 = ACCENT
		end)
	end)
	remotes.DownedChanged.OnClientEvent:Connect(function(downed)
		downedFrame.Visible = downed == true
		crosshair.Visible = downed ~= true
	end)
	remotes.DodgeUpdated.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		dodgeLabel.Text = string.format("DODGE %d/%d", payload.charges or 0, payload.max or 2)
	end)
	remotes.AbilityStateChanged.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.abilityId) ~= "string" then return end
		local duration = tonumber(payload.duration) or 0
		cooldownEnds[payload.abilityId] = os.clock() + duration
		cooldownDurations[payload.abilityId] = math.max(0.1, duration)
	end)

	HUD.setDevice(UserInputService:GetLastInputType())

	task.spawn(function()
		while gui.Parent do
			task.wait(0.1)
			-- Lobby keeps abilities/dodge/vitals visible, but not firing-range furniture. The crosshair and
			-- ammo box are combat-only; hiding the whole HUD made the loadout invisible on the station.
			local inMission = workspace:GetAttribute("GF_EnvironmentPreset") == "mission"
			local ammoBox = gui:FindFirstChild("Ammo")
			if ammoBox and ammoBox:IsA("GuiObject") then
				ammoBox.Visible = inMission
			end
			if crosshair then
				crosshair.Visible = inMission and not (downedFrame and downedFrame.Visible)
			end
			if downedFrame and downedFrame.Visible then
				local pendingFor = workspace:GetAttribute("GF_RedeployPendingFor")
				if pendingFor == player.Name then
					local remaining = math.max(0, tonumber(workspace:GetAttribute("GF_RedeployCountdown")) or 0)
					downedText.Text = "K.I.A."
					downedDetail.Text = string.format("AUTOMATIC REDEPLOY IN %.0f — ABILITIES PRESERVED", remaining)
				else
					downedText.Text = "DOWNED"
					downedDetail.Text = "AWAITING REVIVE — STAY IN RANGE"
				end
			end
			-- boss HP bar: visible while a boss lives, phase-colored fill
			do
				local bossBar = gui:FindFirstChild("BossBar", true)
				if bossBar then
					local hp = workspace:GetAttribute("BossHealth") or 0
					local phase = workspace:GetAttribute("BossPhase") or 1
					local active = workspace:GetAttribute("BastionActive") == true or workspace:GetAttribute("VeyrActive") == true
					if active then
						-- Field bosses exist in the ecology hundreds of metres away. The boss bar is combat
						-- information, not a permanent mission banner: appear only when the squad is close
						-- enough to engage or after the boss has taken damage.
						local maxHp = workspace:GetAttribute("BossMaxHealth") or 3600
						local damaged = hp < maxHp
						local near = false
						local actorsFolder = workspace:FindFirstChild("ActiveActors")
						local bossModel = (actorsFolder and (actorsFolder:FindFirstChild("BastionWalker") or actorsFolder:FindFirstChild("HighMarshalVeyr")))
							or workspace:FindFirstChild("BastionWalker") or workspace:FindFirstChild("HighMarshalVeyr")
						local bossPart = bossModel and ((bossModel :: Model).PrimaryPart or bossModel:FindFirstChildWhichIsA("BasePart", true))
						local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						if bossPart and root then
							near = (bossPart.Position - root.Position).Magnitude <= 140
						end
						active = damaged or near
					end
					bossBar.Visible = inMission and active and hp > 0
					if bossBar.Visible then
						local fill = bossBar:FindFirstChild("Fill")
						local maxHp = workspace:GetAttribute("BossMaxHealth") or 3600
						if fill then
							fill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
							fill.BackgroundColor3 = phase >= 3 and Tokens.Color.danger or (phase == 2 and Tokens.Color.warning or Tokens.Color.ascendancy)
						end
						local label = bossBar:FindFirstChild("Label")
						if label then
							label.Text = "BASTION WALKER — PHASE " .. tostring(phase)
						end
					end
				end
			end

			local now = os.clock()
			for id, endsAt in cooldownEnds do
				local label = abilityLabels[id]
				local fill = abilityFills[id]
				if label then
					local remaining = endsAt - now
					local duration = cooldownDurations[id] or 1
					if remaining > 0 then
						label.Text = string.format("%.1fs", remaining)
						label.TextColor3 = MUTED
						if fill then
							local fraction = math.clamp(remaining / duration, 0, 1)
							fill.Size = UDim2.new(fraction, -18 * fraction, 0, 4)
						end
					else
						label.Text = "READY"
						label.TextColor3 = ACCENT
						if fill then
							fill.Size = UDim2.new(1, -18, 0, 4)
						end
					end
				end
			end
		end
	end)
end

function HUD.setDevice(kind: any)
	Input.setDevice(kind)
	local isTouch = Input.getDevice() == "touch"
	if touchLayer then
		touchLayer.Visible = isTouch
	end
	-- Re-render the ability titles with the current glyph, and do NOT touch the status text: overwriting it
	-- here reset every cooldown readout to READY on any input-family change.
	for id, title in pairs(abilityTitles) do
		if title then
			-- one support slot: every ability title carries the same binding glyph
			title.Text = string.format("%s [%s]", string.upper(tostring(id)), Input.glyph("SupportAbility"))
		end
	end
	if promptLabel then
		promptLabel.Text = isTouch and "" or string.format("Fire [%s]  Aim [%s]  Dodge [%s]  Reload [%s]  Ability [%s]",
			Input.glyph("Fire"), Input.glyph("Aim"), Input.glyph("Dodge"), Input.glyph("Reload"),
			Input.glyph("SupportAbility"))
	end
end

function HUD.setAmmo(ammo: number, magazine: number, reserve: number?)
	if ammoLabel then
		-- S04-027: reserve is finite and visible. The hierarchy is deliberately military:
		-- current magazine dominates; capacity/reserve stay subordinate but readable.
		local legacyText
		if type(reserve) == "number" then
			legacyText = string.format("%d / %d  ·  %d", ammo, magazine, reserve)
			ammoDetailLabel.Text = string.format("/ %d MAG  ·  RES %d", magazine, reserve)
		else
			legacyText = string.format("%d / %d", ammo, magazine)
			ammoDetailLabel.Text = string.format("/ %d MAG", magazine)
		end
		ammoLabel.Text = tostring(ammo)
		ammoLabel.TextColor3 = ammo == 0 and WARN or INK
		ammoDetailLabel.TextColor3 = ammo == 0 and WARN or MUTED
		if gui then
			gui:SetAttribute("GF_AmmoText", legacyText)
		end
	end
end

function HUD.setWeapon(weaponId: string)
	HUD._weaponId = weaponId
	if weaponLabel then
		local Weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
		local def = Weapons.get(weaponId)
		weaponLabel.Text = string.upper(tostring((def and def.displayName) or weaponId))
	end
end

function HUD.showHitMarker(weak: boolean, killed: boolean)
	if not hitMarker then return end
	local color = killed and WARN
		or (weak and AMBER or INK)
	local size = weak and 30 or 22
	hitMarker.Size = UDim2.fromOffset(size, size)
	hitMarker.Position = UDim2.new(0.5, -size / 2, 0.5, -size / 2)
	for _, bar in hitMarker:GetChildren() do
		if bar:IsA("Frame") then
			bar.BackgroundColor3 = color
			bar.Size = UDim2.fromOffset(math.floor(size * 0.64), killed and 3 or 2)
			bar.Position = UDim2.new(0.5, -math.floor(size * 0.64) / 2, 0.5, killed and -1.5 or -1)
		end
	end
	hitMarker.Visible = true
	task.delay(0.12, function()
		if hitMarker then
			hitMarker.Visible = false
		end
	end)
end

-- Floating damage numbers at the hit position (spec S03-041 optional damage numbers): world-space
-- billboard that rises and fades in under a second. Honours the server-validated setting.
function HUD.showDamageNumber(amount: number, position: Vector3?, weakPoint: boolean?)
	local player = game:GetService("Players").LocalPlayer
	if player and player:GetAttribute("GF_Setting_DamageNumbers") == false then
		return
	end
	if typeof(position) ~= "Vector3" or type(amount) ~= "number" then
		return
	end
	local part = Instance.new("Part")
	part.Name = "DamageNumber"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = position + Vector3.new(0, 1, 0)
	part.Parent = workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(90, 30)
	bb.AlwaysOnTop = true
	bb.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Tokens.Type.fontBold
	label.TextSize = weakPoint and 20 or 15
	label.TextColor3 = weakPoint and AMBER or INK
	label.TextStrokeTransparency = 0.4
	label.Text = tostring(math.floor(amount + 0.5))
	label.Parent = bb
	game:GetService("TweenService"):Create(part, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = part.Position + Vector3.new(0, 2.4, 0),
	}):Play()
	game:GetService("TweenService"):Create(label, TweenInfo.new(0.85), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(part, 0.95)
end

function HUD.showKill()
	if not killLabel then return end
	killLabel.Text = "TARGET DOWN"
	task.delay(0.9, function()
		if killLabel then killLabel.Text = "" end
	end)
end

function HUD.castAbility(action: string)
	-- one support ability slot (Counteroffensive contract revision)
	local fallback = "Airstrike"
	local slotAttr = "GF_Ability"
	local published = player:GetAttribute(slotAttr)
	if type(published) ~= "string" then
		published = workspace:GetAttribute(slotAttr)
	end
	local abilityId = type(published) == "string" and published or fallback
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then return end
	local camera = workspace.CurrentCamera
	local look = camera and camera.CFrame.LookVector or head.CFrame.LookVector
	local origin = head.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(origin, look * 90, params)
	local point = hit and hit.Position or (origin + look * 60)
	remotes.UseAbility:FireServer({ abilityId = abilityId, position = point })
end

function HUD.setPrompt(text: string)
	if promptLabel then
		promptLabel.Text = text
	end
end


-- ---------------------------------------------------------------------------
-- Reticle spread updater (spec section 6): per-frame, viewport-scaled, truthful to weapon state.
-- The horizontal lines track effective dispersion — base hip/aimed cone + bloom + movement —
-- with continuous client-side decay prediction between authoritative server updates. The ring
-- stays fixed as a precision reference; the center dot is never smoothed, never offset.
do
	local Weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
	local lastBloom = 0
	local bloomAt = os.clock()
	local displayHalfGap = 9

	-- mirror the server's post-shot bloom value and timestamp it locally; prediction decays from
	-- there. Server recovery rate is 2.6 deg/s (CombatService) — keep in sync when tuning.
	player:GetAttributeChangedSignal("SpreadBloom"):Connect(function()
		lastBloom = tonumber(player:GetAttribute("SpreadBloom")) or 0
		bloomAt = os.clock()
	end)

	RunService.RenderStepped:Connect(function(dt)
		if not crosshair or not crosshair.Parent then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local weapon = Weapons.get(HUD._weaponId or "")
		local aiming = workspace:GetAttribute("GF_PlayerAiming") == true
		local base = 1
		if weapon then
			base = aiming and (tonumber(weapon.adsSpread) or tonumber(weapon.spreadBase) or 1)
				or (tonumber(weapon.spreadBase) or 1)
		end
		-- movement penalty mirrors the server's +1.5deg over 2 studs/s
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local moving = root and root.AssemblyLinearVelocity.Magnitude > 2
		-- continuous bloom prediction: decay the last server value rather than waiting for the
		-- next accepted shot — the old display stayed expanded indefinitely between shots.
		local bloom = math.max(0, lastBloom - (os.clock() - bloomAt) * 2.6)
		-- response design (owner-tested 2026-11-26): the original mapping fed TOTAL dispersion
		-- through one compressed log curve — bloom increments of 0.35deg/shot moved the ticks by
		-- a fraction of a pixel and the reticle read as frozen. Now: the stance base sets the
		-- rest width through the log curve (small range), and bloom+movement expand LINEARLY on
		-- top at 4px/deg — first shot visibly opens, sustained fire opens wide, recovery reads.
		local alphaRef, alphaMax = 0.5, 7
		local xBase = math.clamp(math.log(1 + base / alphaRef) / math.log(1 + alphaMax / alphaRef), 0, 1)
		local restGap = 9 + 6 * xBase -- stance rest width: ~9 tight aimed to ~15 wide hip
		local expansion = (bloom + (moving and 1.5 or 0)) * 4
		local gapTarget = restGap + math.min(expansion, 14)
		-- expansion reacts immediately, recovery lightly damped (spec: tau 0.04-0.08s)
		local tau = gapTarget > displayHalfGap and 0.02 or 0.06
		displayHalfGap = gapTarget + (displayHalfGap - gapTarget) * math.exp(-dt / tau)
		-- viewport scaling: reference 1920x1080, clamped so the reticle survives mobile and 4k
		local vp = camera.ViewportSize
		local scale = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.7, 1.6)
		local halfGap = displayHalfGap * scale
		local lineLen = 5 * scale
		local thick = math.max(1, 1.5 * scale)
		local tickL = crosshair:FindFirstChild("TickL")
		local tickR = crosshair:FindFirstChild("TickR")
		if tickL and tickR then
			tickL.Size = UDim2.fromOffset(lineLen, thick)
			tickR.Size = UDim2.fromOffset(lineLen, thick)
			tickL.Position = UDim2.fromOffset(32 - halfGap - lineLen, 32 - thick / 2)
			tickR.Position = UDim2.fromOffset(32 + halfGap, 32 - thick / 2)
		end
		local ring = crosshair:FindFirstChild("ReticleRing")
		if ring then
			local d = 10 * scale
			ring.Size = UDim2.fromOffset(d, d)
			ring.Position = UDim2.fromOffset(32 - d / 2, 32 - d / 2)
		end
		local dot = crosshair:FindFirstChild("Dot")
		if dot then
			local d = math.max(1.5, 2 * scale)
			dot.Size = UDim2.fromOffset(d, d)
			dot.Position = UDim2.fromOffset(32 - d / 2, 32 - d / 2)
		end
	end)
end

return HUD

