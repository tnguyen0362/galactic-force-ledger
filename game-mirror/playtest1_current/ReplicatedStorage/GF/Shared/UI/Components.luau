--!strict
-- Component library (Counteroffensive Stage 5 foundation). every interactive surface composes
-- from these — no new UI may hand-roll buttons, rows, or panels. components enforce the token
-- contract: touch-target minimums, type scale, focus states, restrained motion.
-- cross-platform by construction: Activated works for touch/click, and components expose
-- focus hooks for the console virtual-cursor/gamepad navigation layer.
local Tokens = require(script.Parent.Tokens)

local Components = {}

local function tween(obj: GuiObject, props: { [string]: any }, duration: number?)
	local info = TweenInfo.new(duration or Tokens.Motion.fast, Tokens.Motion.easing, Tokens.Motion.direction)
	game:GetService("TweenService"):Create(obj, info, props):Play()
end

-- ---------------------------------------------------------------------------
-- panel: the ground every surface sits on. rounded corners are OFF — the art direction
-- is controlled bevels and military precision, not friendly mobile-app rounding.
-- ---------------------------------------------------------------------------
function Components.panel(parent: Instance, size: UDim2, position: UDim2): Frame
	local f = Instance.new("Frame")
	f.Name = "Panel"
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = Tokens.Color.panel
	f.BorderSizePixel = 0
	f.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = Tokens.Color.border
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Tokens.Space.md)
	pad.PaddingRight = UDim.new(0, Tokens.Space.md)
	pad.PaddingTop = UDim.new(0, Tokens.Space.md)
	pad.PaddingBottom = UDim.new(0, Tokens.Space.md)
	pad.Parent = f
	return f
end

-- ---------------------------------------------------------------------------
-- text: token-locked typography. roles: title/body/caption. never smaller than 13px.
-- ---------------------------------------------------------------------------
function Components.text(parent: Instance, content: string, role: string?, size: UDim2?, position: UDim2?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = "Text_" .. role
	l.BackgroundTransparency = 1
	l.Font = Tokens.Type.font
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	if role == "title" then
		l.TextSize = Tokens.Type.sizeTitle
		l.TextColor3 = Tokens.Color.textPrimary
		l.Font = Tokens.Type.fontBold
	elseif role == "caption" then
		l.TextSize = Tokens.Type.sizeSmall
		l.TextColor3 = Tokens.Color.textSecondary
	else
		l.TextSize = Tokens.Type.sizeBody
		l.TextColor3 = Tokens.Color.textPrimary
	end
	l.Text = content
	l.Size = size or UDim2.new(1, 0, 0, l.TextSize + Tokens.Space.sm)
	l.Position = position or UDim2.new(0, 0, 0, 0)
	l.Parent = parent
	return l
end

-- ---------------------------------------------------------------------------
-- button: the single interactive element. states: rest/hover/pressed/disabled/focused.
-- enforces the 52px touch minimum on its shortest dimension. style: quiet broad surface
-- with a cyan edge when active — restraint per the art direction.
-- kind: "primary" (cyan frame), "ghost" (steel frame), "danger" (red frame)
-- ---------------------------------------------------------------------------
function Components.button(parent: Instance, label: string, kind: string?): TextButton
	local b = Instance.new("TextButton")
	b.Name = "Btn_" .. label:sub(1, 12)
	b.Size = UDim2.new(1, 0, 0, Tokens.Size.buttonHeight)
	b.BackgroundColor3 = Tokens.Color.panelRaised
	b.BorderSizePixel = 0
	b.Font = Tokens.Type.font
	b.TextSize = Tokens.Type.sizeBody
	b.Text = label
	b.AutoButtonColor = false -- we own all feedback states
	b.Parent = parent

	local frameColor = kind == "danger" and Tokens.Color.danger
		or kind == "primary" and Tokens.Color.techCyan
		or Tokens.Color.steel
	b.TextColor3 = kind == "primary" and Tokens.Color.textAccent or Tokens.Color.textPrimary

	local stroke = Instance.new("UIStroke")
	stroke.Color = frameColor
	stroke.Transparency = kind == "primary" and 0.45 or 0.7 -- quiet at rest
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b

	-- state feedback: hover/focus tightens the frame and brightens — never a color carnival
	b.MouseEnter:Connect(function()
		tween(stroke, { Transparency = 0.1 })
		tween(b, { BackgroundColor3 = Tokens.Color.navy })
	end)
	b.MouseLeave:Connect(function()
		tween(stroke, { Transparency = kind == "primary" and 0.45 or 0.7 })
		tween(b, { BackgroundColor3 = Tokens.Color.panelRaised })
	end)
	-- gamepad/virtual-cursor focus gets the same treatment — one visual language
	b.SelectionGained:Connect(function()
		tween(stroke, { Transparency = 0.1 })
		tween(b, { BackgroundColor3 = Tokens.Color.navy })
	end)
	b.SelectionLost:Connect(function()
		tween(stroke, { Transparency = kind == "primary" and 0.45 or 0.7 })
		tween(b, { BackgroundColor3 = Tokens.Color.panelRaised })
	end)
	return b
end

-- ---------------------------------------------------------------------------
-- row: a list entry — primary line + caption, optional right-side status chip.
-- rows are the backbone of browsers/rosters; they must be scannable at a glance.
-- ---------------------------------------------------------------------------
function Components.row(parent: Instance, primary: string, caption: string?): Frame
	local r = Instance.new("Frame")
	r.Name = "Row"
	r.Size = UDim2.new(1, 0, 0, Tokens.Size.rowHeight)
	r.BackgroundColor3 = Tokens.Color.panelInset
	r.BorderSizePixel = 0
	r.Parent = parent

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Tokens.Space.sm + Tokens.Space.xs)
	pad.PaddingRight = UDim.new(0, Tokens.Space.sm + Tokens.Space.xs)
	pad.PaddingTop = UDim.new(0, Tokens.Space.xs)
	pad.PaddingBottom = UDim.new(0, Tokens.Space.xs)
	pad.Parent = r

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, Tokens.Space.xs)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = r

	local p = Components.text(r, primary, "body")
	p.LayoutOrder = 1
	if caption then
		local c = Components.text(r, caption, "caption")
		c.LayoutOrder = 2
	end
	return r
end

-- ---------------------------------------------------------------------------
-- chip: a compact state indicator (status, seats, region). read-only.
-- ---------------------------------------------------------------------------
function Components.chip(parent: Instance, text: string, color: Color3?): Frame
	local c = Instance.new("Frame")
	c.Name = "Chip"
	c.Size = UDim2.new(0, 0, 0, Tokens.Size.chipHeight)
	c.AutomaticSize = Enum.AutomaticSize.X
	c.BackgroundColor3 = Tokens.Color.panelInset
	c.BorderSizePixel = 0
	c.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Tokens.Color.steel
	stroke.Transparency = 0.4
	stroke.Thickness = 1
	stroke.Parent = c
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Tokens.Space.sm)
	pad.PaddingRight = UDim.new(0, Tokens.Space.sm)
	pad.Parent = c
	local t = Components.text(c, text, "caption")
	t.Position = UDim2.new(0, 0, 0.5, 0)
	t.AnchorPoint = Vector2.new(0, 0.5)
	t.TextColor3 = color or Tokens.Color.textSecondary
	return c
end

-- ---------------------------------------------------------------------------
-- list: vertical scrolling container with consistent layout. rows/children flow —
-- absolute offsets inside lists are prohibited (the legacy panel collision pattern).
-- ---------------------------------------------------------------------------
function Components.list(parent: Instance, size: UDim2, position: UDim2?): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Name = "List"
	s.Size = size
	s.Position = position or UDim2.new(0, 0, 0, 0)
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 4
	s.ScrollBarImageColor3 = Tokens.Color.steel
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new(0, 0, 0, 0)
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, Tokens.Space.sm)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = s
	return s
end

-- ---------------------------------------------------------------------------
-- sidebarItem: vertical-rail navigation entry — icon glyph + micro-label, the primary
-- navigation unit of the full-screen menu architecture (mandate vertical sidebar).
-- ---------------------------------------------------------------------------
function Components.sidebarItem(parent: Instance, glyph: string, name: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = "Nav_" .. name
	b.Size = UDim2.new(1, 0, 0, 64)
	b.BackgroundColor3 = Tokens.Color.panelInset
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Text = ""
	b.Parent = parent

	local g = Instance.new("TextLabel")
	g.Name = "Glyph"
	g.Size = UDim2.new(1, 0, 0, 28)
	g.Position = UDim2.new(0, 0, 0, Tokens.Space.sm)
	g.BackgroundTransparency = 1
	g.Font = Tokens.Type.font
	g.TextSize = 22
	g.TextColor3 = Tokens.Color.textSecondary
	g.Text = glyph
	g.Parent = b

	local n = Instance.new("TextLabel")
	n.Name = "Label"
	n.Size = UDim2.new(1, 0, 0, 14)
	n.Position = UDim2.new(0, 0, 0, 40)
	n.BackgroundTransparency = 1
	n.Font = Tokens.Type.font
	n.TextSize = Tokens.Type.sizeSmall - 2
	n.TextColor3 = Tokens.Color.textSecondary
	n.Text = string.upper(name)
	n.Parent = b

	local bar = Instance.new("Frame") -- active indicator: the cyan edge, left side
	bar.Name = "ActiveBar"
	bar.Size = UDim2.new(0, 3, 1, -Tokens.Space.md)
	bar.Position = UDim2.new(0, 0, 0, Tokens.Space.sm)
	bar.BackgroundColor3 = Tokens.Color.techCyan
	bar.Visible = false
	bar.BorderSizePixel = 0
	bar.Parent = b

	b.SelectionGained:Connect(function()
		g.TextColor3 = Tokens.Color.textAccent
		n.TextColor3 = Tokens.Color.textAccent
	end)
	b.SelectionLost:Connect(function()
		if not bar.Visible then
			g.TextColor3 = Tokens.Color.textSecondary
			n.TextColor3 = Tokens.Color.textSecondary
		end
	end)
	return b
end

function Components.setNavActive(item: TextButton, active: boolean)
	local bar = item:FindFirstChild("ActiveBar")
	local g = item:FindFirstChild("Glyph")
	local n = item:FindFirstChild("Label")
	if bar then
		local barFrame = bar :: Frame
		barFrame.Visible = active
	end
	if g and n then
		local gl = g :: TextLabel
		local nl = n :: TextLabel
		gl.TextColor3 = active and Tokens.Color.textAccent or Tokens.Color.textSecondary
		nl.TextColor3 = active and Tokens.Color.textAccent or Tokens.Color.textSecondary
	end
	item.BackgroundTransparency = active and 0 or 1
	item.BackgroundColor3 = Tokens.Color.panelRaised
end

return Components
