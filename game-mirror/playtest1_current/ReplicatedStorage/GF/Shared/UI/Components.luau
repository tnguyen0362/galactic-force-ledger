--!strict
-- Component library (Counteroffensive Stage 5 foundation). every interactive surface composes
-- from these — no new UI may hand-roll buttons, rows, or panels. components enforce the token
-- contract: touch-target minimums, type scale, focus states, restrained motion.
-- cross-platform by construction: Activated works for touch/click, and components expose
-- focus hooks for the console virtual-cursor/gamepad navigation layer.
-- visual language: angular military chrome. no UICorner, no soft shadows, no rounding;
-- depth comes from thin steel/cyan lines, corner brackets, and small chamfer accents.
local Tokens = require(script.Parent.Tokens)

local Components = {}

local function tween(obj: Instance, props: { [string]: any }, duration: number?)
	local length = duration or Tokens.Motion.fast
	if length <= 0 then
		for key, value in pairs(props) do
			(obj :: any)[key] = value
		end
		return
	end
	local info = TweenInfo.new(length, Tokens.Motion.easing, Tokens.Motion.direction)
	game:GetService("TweenService"):Create(obj, info, props):Play()
end

local function makeStrip(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, transparency: number?, rotation: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Rotation = rotation or 0
	f.Parent = parent
	return f
end

-- UILayout-safe decoration scope. Roblox Folders form their own UI layout context,
-- so chrome inside this folder will not be treated as a list item when a consumer
-- puts UIListLayout directly inside a panel.
local function chromeFolder(parent: Instance): Folder
	local existing = parent:FindFirstChild("AngularChrome")
	if existing and existing:IsA("Folder") then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = "AngularChrome"
	folder.Parent = parent
	return folder
end

local function normalizedCorner(corner: string?): string
	local key = string.lower(corner or "topLeft")
	key = key:gsub("[%s_%-]", "")
	if key == "topleft" or key == "tl" then
		return "topLeft"
	elseif key == "topright" or key == "tr" then
		return "topRight"
	elseif key == "bottomleft" or key == "bl" then
		return "bottomLeft"
	elseif key == "bottomright" or key == "br" then
		return "bottomRight"
	end
	return "topLeft"
end

local function findFrame(parent: Instance, name: string): Frame?
	local child = parent:FindFirstChild(name)
	if child and child:IsA("Frame") then
		return child :: Frame
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- letterspace: Roblox has no tracking property. this inserts real spaces between
-- UTF-8 characters for short military headers: DEPLOY -> D E P L O Y. use only on
-- headers/labels; long body copy should never be tracked.
-- ---------------------------------------------------------------------------
function Components.letterspace(content: string, spacing: number?): string
	local gapWidth = spacing or 1
	if gapWidth <= 0 or #content <= 1 then
		return content
	end

	local gap = string.rep(" ", gapWidth)
	local wordGap = string.rep(" ", gapWidth + 2)
	local parts: { string } = {}
	local index = 1
	local needsGap = false

	while index <= #content do
		local byte = string.byte(content, index)
		local characterLength = 1
		if byte then
			if byte >= 0xF0 then
				characterLength = 4
			elseif byte >= 0xE0 then
				characterLength = 3
			elseif byte >= 0xC0 then
				characterLength = 2
			end
		end

		local character = string.sub(content, index, index + characterLength - 1)
		if character == " " then
			table.insert(parts, wordGap)
			needsGap = false
		else
			if needsGap then
				table.insert(parts, gap)
			end
			table.insert(parts, character)
			needsGap = true
		end
		index += characterLength
	end

	return table.concat(parts)
end

-- ---------------------------------------------------------------------------
-- cornerBracket: a cheap Destiny/HD2-style right-angle corner accent. one holder
-- plus two thin strips per corner — no polygon clipping and no image assets.
-- corner accepts topLeft/topRight/bottomLeft/bottomRight (also tl/tr/bl/br).
-- ---------------------------------------------------------------------------
function Components.cornerBracket(parent: Instance, corner: string?, length: number?, color: Color3?, thickness: number?, inset: number?): Frame
	local resolved = normalizedCorner(corner)
	local bracketLength = length or Tokens.Frame.cornerLength
	local bracketThickness = thickness or Tokens.Frame.cornerThickness
	local bracketInset = inset or 0
	local bracketColor = color or Tokens.Color.borderStrong

	local holder = Instance.new("Frame")
	holder.Name = "Bracket_" .. resolved
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(bracketLength, bracketLength)

	if resolved == "topLeft" then
		holder.AnchorPoint = Vector2.new(0, 0)
		holder.Position = UDim2.fromOffset(bracketInset, bracketInset)
	elseif resolved == "topRight" then
		holder.AnchorPoint = Vector2.new(1, 0)
		holder.Position = UDim2.new(1, -bracketInset, 0, bracketInset)
	elseif resolved == "bottomLeft" then
		holder.AnchorPoint = Vector2.new(0, 1)
		holder.Position = UDim2.new(0, bracketInset, 1, -bracketInset)
	else
		holder.AnchorPoint = Vector2.new(1, 1)
		holder.Position = UDim2.new(1, -bracketInset, 1, -bracketInset)
	end
	holder.Parent = parent

	local xAnchor = (resolved == "topRight" or resolved == "bottomRight") and 1 or 0
	local yAnchor = (resolved == "bottomLeft" or resolved == "bottomRight") and 1 or 0

	local horizontal = makeStrip(holder, "Horizontal",
		UDim2.fromOffset(bracketLength, bracketThickness),
		UDim2.fromScale(xAnchor, yAnchor),
		bracketColor, 0)
	horizontal.AnchorPoint = Vector2.new(xAnchor, yAnchor)

	local vertical = makeStrip(holder, "Vertical",
		UDim2.fromOffset(bracketThickness, bracketLength),
		UDim2.fromScale(xAnchor, yAnchor),
		bracketColor, 0)
	vertical.AnchorPoint = Vector2.new(xAnchor, yAnchor)

	return holder
end

-- frameBrackets decorates all four corners inside a UILayout-safe Folder. use this
-- on panels and menu chrome that may later receive UIListLayout children.
function Components.frameBrackets(parent: Instance, color: Color3?, length: number?, thickness: number?, inset: number?): { Frame }
	local scope = chromeFolder(parent)
	local bracketLength = length or Tokens.Frame.cornerLength
	local bracketThickness = thickness or Tokens.Frame.cornerThickness
	local bracketInset = inset
	if bracketInset == nil then
		bracketInset = Tokens.Frame.cornerInset
	end
	return {
		Components.cornerBracket(scope, "topLeft", bracketLength, color, bracketThickness, bracketInset),
		Components.cornerBracket(scope, "topRight", bracketLength, color, bracketThickness, bracketInset),
		Components.cornerBracket(scope, "bottomLeft", bracketLength, color, bracketThickness, bracketInset),
		Components.cornerBracket(scope, "bottomRight", bracketLength, color, bracketThickness, bracketInset),
	}
end

-- chamferAccent: a single rotated hairline clipped by its parent. it reads as the
-- angled cut on sharp military hardware while costing exactly one Frame.
function Components.chamferAccent(parent: Instance, corner: string?, length: number?, color: Color3?, thickness: number?): Frame
	local resolved = normalizedCorner(corner)
	local chamferLength = length or Tokens.Frame.chamferLength
	local chamferThickness = thickness or Tokens.Frame.borderThickness
	local chamferColor = color or Tokens.Color.borderStrong

	local isRight = resolved == "topRight" or resolved == "bottomRight"
	local isBottom = resolved == "bottomLeft" or resolved == "bottomRight"
	local xScale = isRight and 1 or 0
	local yScale = isBottom and 1 or 0
	local xOffset = isRight and -2 or 2
	local yOffset = isBottom and -2 or 2
	local rotation = (resolved == "topRight" or resolved == "bottomLeft") and 45 or -45

	local line = makeStrip(parent, "Chamfer_" .. resolved,
		UDim2.fromOffset(math.floor(chamferLength * 1.5 + 0.5), chamferThickness),
		UDim2.new(xScale, xOffset, yScale, yOffset),
		chamferColor, 0, rotation)
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	return line
end

-- ---------------------------------------------------------------------------
-- divider: thin structural rule. horizontal by default; pass "vertical" for a
-- rail divider. a short cyan terminal segment gives the line a manufactured end.
-- ---------------------------------------------------------------------------
function Components.divider(parent: Instance, orientation: string?, thickness: number?, color: Color3?): Frame
	local vertical = orientation == "vertical" or orientation == "v"
	local lineThickness = thickness or Tokens.Size.dividerHeight
	local line = Instance.new("Frame")
	line.Name = vertical and "Divider_Vertical" or "Divider_Horizontal"
	line.Size = vertical and UDim2.new(0, lineThickness, 1, 0) or UDim2.new(1, 0, 0, lineThickness)
	line.BackgroundColor3 = color or Tokens.Color.border
	line.BackgroundTransparency = Tokens.Transparency.line
	line.BorderSizePixel = 0
	line.ClipsDescendants = true
	line.Parent = parent

	makeStrip(line, "Terminal",
		vertical and UDim2.new(1, 0, 0, Tokens.Space.lg) or UDim2.new(0, Tokens.Space.xl, 1, 0),
		UDim2.fromScale(0, 0),
		Tokens.Color.techCyan, 0.18)

	return line
end

-- ---------------------------------------------------------------------------
-- scanline: one horizontal hairline whose ends fade out through a UIGradient.
-- cheap CRT/console accent — use sparingly, not as a repeating neon texture.
-- ---------------------------------------------------------------------------
function Components.scanline(parent: Instance, size: UDim2?, color: Color3?, transparency: number?): Frame
	local line = Instance.new("Frame")
	line.Name = "Scanline"
	line.Size = size or UDim2.new(1, 0, 0, Tokens.Size.scanlineHeight)
	line.BackgroundColor3 = color or Tokens.Color.techCyan
	line.BackgroundTransparency = 0
	line.BorderSizePixel = 0
	line.Parent = parent

	local visibleTransparency = transparency or 0.32
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.16, visibleTransparency),
		NumberSequenceKeypoint.new(0.5, math.max(0, visibleTransparency - 0.12)),
		NumberSequenceKeypoint.new(0.84, visibleTransparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = line
	return line
end

-- scanlineField: a restrained static grid/scan texture for large menu grounds.
-- count stays low by default; this is atmosphere, not a full CRT overlay.
function Components.scanlineField(parent: Instance, lineCount: number?, spacing: number?, color: Color3?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "ScanlineField"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	holder.Parent = parent

	local count = math.floor(math.max(1, lineCount or 8))
	local lineColor = color or Tokens.Color.techCyan
	for index = 1, count do
		-- nil spacing distributes the lines proportionally across the surface; explicit
		-- spacing is a fixed pixel cadence for smaller readout panels
		local position = spacing and UDim2.fromOffset(0, (index - 1) * spacing)
			or UDim2.new(0, 0, (index - 0.5) / count, 0)
		makeStrip(holder, "Scanline_" .. tostring(index),
			UDim2.new(1, 0, 0, 1),
			position,
			lineColor, Tokens.Transparency.scanline)
	end
	return holder
end

-- ---------------------------------------------------------------------------
-- panel: the ground every surface sits on. rounded corners are OFF — the art direction
-- is controlled bevels and military precision, not friendly mobile-app rounding.
-- panel chrome is steel, not cyan: accents stay sparse and interactive.
-- ---------------------------------------------------------------------------
function Components.panel(parent: Instance, size: UDim2, position: UDim2): Frame
	local f = Instance.new("Frame")
	f.Name = "Panel"
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = Tokens.Color.panel
	f.BackgroundTransparency = Tokens.Transparency.panel
	f.BorderSizePixel = 0
	f.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Tokens.Color.border
	stroke.Transparency = 0.16
	stroke.Thickness = Tokens.Frame.borderThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f

	-- quiet vertical material falloff: broad surfaces remain matte, not glossy
	local material = Instance.new("UIGradient")
	material.Rotation = 90
	material.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.58, Color3.fromRGB(224, 231, 234)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 199, 204)),
	})
	material.Parent = f

	-- layout-safe angular accents at opposing corners. two brackets carry the cut-metal
	-- read without doubling instance cost on dense browsers; frameBrackets remains
	-- available when a hero panel needs all four corners dressed.
	local scope = chromeFolder(f)
	Components.cornerBracket(scope, "topLeft", Tokens.Frame.cornerLength,
		Tokens.Color.borderStrong, Tokens.Frame.cornerThickness, Tokens.Frame.cornerInset)
	Components.cornerBracket(scope, "bottomRight", Tokens.Frame.cornerLength,
		Tokens.Color.borderStrong, Tokens.Frame.cornerThickness, Tokens.Frame.cornerInset)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Tokens.Space.md)
	pad.PaddingRight = UDim.new(0, Tokens.Space.md)
	pad.PaddingTop = UDim.new(0, Tokens.Space.md)
	pad.PaddingBottom = UDim.new(0, Tokens.Space.md)
	pad.Parent = f
	return f
end

-- ---------------------------------------------------------------------------
-- text: token-locked typography. roles: title/body/caption remain stable.
-- additive roles: header (letterspaced small-caps), display, label, mono, metric.
-- ---------------------------------------------------------------------------
function Components.text(parent: Instance, content: string, role: string?, size: UDim2?, position: UDim2?): TextLabel
	local resolvedRole = role or "body"
	local roleKey = string.lower(resolvedRole)
	local output = content

	local l = Instance.new("TextLabel")
	l.Name = "Text_" .. resolvedRole
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = Tokens.Type.font
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l:SetAttribute("GFTextRole", roleKey)

	if roleKey == "title" then
		l.TextSize = Tokens.Type.sizeTitle
		l.TextColor3 = Tokens.Color.textPrimary
		l.Font = Tokens.Type.fontBold
	elseif roleKey == "caption" then
		l.TextSize = Tokens.Type.sizeSmall
		l.TextColor3 = Tokens.Color.textSecondary
	elseif roleKey == "header" then
		l.TextSize = Tokens.Type.sizeLabel
		l.TextColor3 = Tokens.Color.textPrimary
		l.Font = Tokens.Type.fontBold
		output = Components.letterspace(string.upper(content), 1)
	elseif roleKey == "overline" or roleKey == "label" then
		l.TextSize = Tokens.Type.sizeSmall
		l.TextColor3 = Tokens.Color.textSecondary
		l.Font = Tokens.Type.fontBold
		output = string.upper(content)
	elseif roleKey == "display" then
		l.TextSize = Tokens.Type.sizeDisplay
		l.TextColor3 = Tokens.Color.textPrimary
		l.Font = Tokens.Type.fontDisplay
	elseif roleKey == "mono" then
		l.TextSize = Tokens.Type.sizeBody
		l.TextColor3 = Tokens.Color.textPrimary
		l.Font = Tokens.Type.fontMono
	elseif roleKey == "metric" then
		l.TextSize = Tokens.Type.sizeHeader
		l.TextColor3 = Tokens.Color.textAccent
		l.Font = Tokens.Type.fontMonoBold
	else
		l.TextSize = Tokens.Type.sizeBody
		l.TextColor3 = Tokens.Color.textPrimary
	end

	l.Text = output
	l.Size = size or UDim2.new(1, 0, 0, l.TextSize + Tokens.Space.sm)
	l.Position = position or UDim2.new(0, 0, 0, 0)
	l.Parent = parent
	return l
end

-- ---------------------------------------------------------------------------
-- buttons: sharp rectangular commitment surfaces with a clipped chamfer accent.
-- states: rest/hover/pressed/disabled/focused/selected. cyan means interactive;
-- amber fill + inverse dark text means committed selection.
-- ---------------------------------------------------------------------------
local buttonRefreshers: { [Instance]: (number?) -> () } = {}

local function buttonAccentColor(kind: string): Color3
	if kind == "danger" then
		return Tokens.Color.danger
	elseif kind == "primary" then
		return Tokens.Color.techCyan
	end
	return Tokens.Color.steel
end

local function applyButtonVisual(button: TextButton, state: string, duration: number?)
	local kindValue = button:GetAttribute("GFKind")
	local kind = "ghost"
	if kindValue == "primary" or kindValue == "danger" then
		kind = kindValue
	end

	local accent = buttonAccentColor(kind)
	local background = Tokens.Color.panelRaised
	local text = kind == "primary" and Tokens.Color.textAccent or Tokens.Color.textPrimary
	local lineColor = accent
	local lineTransparency = kind == "primary" and 0.36 or 0.58
	local edgeColor = accent
	local edgeTransparency = kind == "primary" and 0.28 or 0.52
	local chamferColor = accent
	local chamferTransparency = kind == "primary" and 0.22 or 0.52

	if state == "selected" then
		background = Tokens.Color.accentSelect
		text = Tokens.Color.textOnAccent
		lineColor = Tokens.Color.techCyan
		lineTransparency = 0
		edgeColor = Tokens.Color.textOnAccent
		edgeTransparency = 0
		chamferColor = Tokens.Color.textOnAccent
		chamferTransparency = 0.08
	elseif state == "disabled" then
		background = Tokens.Color.panelInset
		text = Tokens.Color.textDisabled
		lineColor = Tokens.Color.steel
		lineTransparency = 0.82
		edgeColor = Tokens.Color.steel
		edgeTransparency = 0.86
		chamferColor = Tokens.Color.steel
		chamferTransparency = 0.86
	elseif state == "pressed" then
		background = Tokens.Color.panelInset
		text = Tokens.Color.textPrimary
		lineTransparency = 0.02
		edgeTransparency = 0
		chamferTransparency = 0.02
	elseif state == "hot" then
		background = Tokens.Color.navy
		text = kind == "primary" and Tokens.Color.textAccent or Tokens.Color.textPrimary
		lineTransparency = 0.04
		edgeTransparency = 0.02
		chamferTransparency = 0.04
	end

	tween(button, {
		BackgroundColor3 = background,
		TextColor3 = text,
	}, duration)

	local strokeObject = button:FindFirstChildOfClass("UIStroke")
	if strokeObject then
		local stroke = strokeObject :: UIStroke
		tween(stroke, {
			Color = lineColor,
			Transparency = lineTransparency,
		}, duration)
	end

	local edge = findFrame(button, "AccentEdge")
	if edge then
		tween(edge, {
			BackgroundColor3 = edgeColor,
			BackgroundTransparency = edgeTransparency,
		}, duration)
	end

	local topChamfer = findFrame(button, "Chamfer_topRight")
	if topChamfer then
		tween(topChamfer, {
			BackgroundColor3 = chamferColor,
			BackgroundTransparency = chamferTransparency,
		}, duration)
	end
	local bottomChamfer = findFrame(button, "Chamfer_bottomLeft")
	if bottomChamfer then
		tween(bottomChamfer, {
			BackgroundColor3 = chamferColor,
			BackgroundTransparency = math.min(0.92, chamferTransparency + 0.22),
		}, duration)
	end
end

function Components.button(parent: Instance, label: string, kind: string?): TextButton
	local resolvedKind = kind or "ghost"
	if resolvedKind ~= "primary" and resolvedKind ~= "danger" then
		resolvedKind = "ghost"
	end

	local b = Instance.new("TextButton")
	b.Name = "Btn_" .. label:sub(1, 12)
	b.Size = UDim2.new(1, 0, 0, Tokens.Size.buttonHeight)
	b.BackgroundColor3 = Tokens.Color.panelRaised
	b.BorderSizePixel = 0
	b.Font = Tokens.Type.fontBold
	b.TextSize = Tokens.Type.sizeBody
	b.Text = label
	b.TextColor3 = resolvedKind == "primary" and Tokens.Color.textAccent or Tokens.Color.textPrimary
	b.AutoButtonColor = false -- we own all feedback states
	b.ClipsDescendants = true
	b:SetAttribute("GFKind", resolvedKind)
	b:SetAttribute("GFSelected", false)
	b.Parent = parent

	local frameColor = buttonAccentColor(resolvedKind)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "AngularBorder"
	stroke.Color = frameColor
	stroke.Transparency = resolvedKind == "primary" and 0.36 or 0.58
	stroke.Thickness = Tokens.Frame.borderThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b

	-- one left rail plus two clipped diagonal end-cuts: angular without instance spam
	makeStrip(b, "AccentEdge",
		UDim2.new(0, Tokens.Frame.cornerThickness, 1, -Tokens.Space.sm),
		UDim2.new(0, 0, 0, Tokens.Space.xs),
		frameColor, resolvedKind == "primary" and 0.28 or 0.52)
	Components.chamferAccent(b, "topRight", Tokens.Frame.chamferLength, frameColor, Tokens.Frame.borderThickness)
	local bottomCut = Components.chamferAccent(b, "bottomLeft", math.floor(Tokens.Frame.chamferLength * 0.75), frameColor, Tokens.Frame.borderThickness)
	bottomCut.BackgroundTransparency = 0.58

	local hot = false
	local focused = false
	local pressed = false

	local function refresh(duration: number?)
		local state = "rest"
		if not b.Active then
			state = "disabled"
		elseif b:GetAttribute("GFSelected") == true then
			state = "selected"
		elseif pressed then
			state = "pressed"
		elseif hot or focused then
			state = "hot"
		end
		applyButtonVisual(b, state, duration)
	end
	buttonRefreshers[b] = refresh
	b.Destroying:Connect(function()
		buttonRefreshers[b] = nil
	end)

	-- compatibility bridge for legacy consumer code that manually paints selected
	-- buttons amber. once seen, the angular state machine preserves that selection
	-- through hover/focus instead of resetting it to the rest color.
	b:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		local color = b.BackgroundColor3
		if color == Tokens.Color.accentSelect then
			if b:GetAttribute("GFSelected") ~= true then
				b:SetAttribute("GFSelected", true)
				refresh(Tokens.Motion.instant)
			end
		elseif color == Tokens.Color.panelRaised then
			if b:GetAttribute("GFSelected") == true then
				b:SetAttribute("GFSelected", false)
				refresh(Tokens.Motion.instant)
			end
		end
	end)

	b.MouseEnter:Connect(function()
		hot = true
		refresh()
	end)
	b.MouseLeave:Connect(function()
		hot = false
		pressed = false
		refresh()
	end)
	b.MouseButton1Down:Connect(function()
		pressed = true
		refresh(Tokens.Motion.instant)
	end)
	b.MouseButton1Up:Connect(function()
		pressed = false
		refresh(Tokens.Motion.instant)
	end)

	-- gamepad/virtual-cursor focus gets the same treatment — one visual language
	b.SelectionGained:Connect(function()
		focused = true
		refresh()
	end)
	b.SelectionLost:Connect(function()
		focused = false
		refresh()
	end)

	applyButtonVisual(b, "rest", Tokens.Motion.instant)
	return b
end

-- committed-selection setter for new consumers. manual amber painting still works,
-- but this API preserves selection robustly across hover/focus/press feedback.
function Components.setSelected(button: TextButton, selected: boolean)
	button:SetAttribute("GFSelected", selected)
	local refresh = buttonRefreshers[button]
	if refresh then
		refresh(Tokens.Motion.fast)
	else
		applyButtonVisual(button, selected and "selected" or "rest", Tokens.Motion.fast)
	end
end
Components.setButtonSelected = Components.setSelected

-- ---------------------------------------------------------------------------
-- row: a list entry — primary line + caption, sharp inset material, tiny steel edge.
-- rows are the backbone of browsers/rosters; they must be scannable at a glance.
-- the row no longer puts a layout constraint around consumer-added action buttons:
-- text is manually composed, leaving the right side free for absolute controls.
-- ---------------------------------------------------------------------------
function Components.row(parent: Instance, primary: string, caption: string?): Frame
	local r = Instance.new("Frame")
	r.Name = "Row"
	r.Size = UDim2.new(1, 0, 0, Tokens.Size.rowHeight)
	r.BackgroundColor3 = Tokens.Color.panelInset
	r.BorderSizePixel = 0
	r.ClipsDescendants = true
	r:SetAttribute("GFSelected", false)
	r.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Name = "RowBorder"
	stroke.Color = Tokens.Color.border
	stroke.Transparency = 0.72
	stroke.Thickness = Tokens.Frame.borderThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = r

	makeStrip(r, "RowAccent",
		UDim2.new(0, 2, 1, -Tokens.Space.sm),
		UDim2.new(0, 0, 0, Tokens.Space.xs),
		Tokens.Color.steel, 0.62)
	makeStrip(r, "RowDivider",
		UDim2.new(1, -Tokens.Space.md, 0, 1),
		UDim2.new(0, Tokens.Space.sm, 1, -1),
		Tokens.Color.border, 0.66)

	local horizontalInset = Tokens.Space.sm + Tokens.Space.xs
	local hasCaption = caption ~= nil and caption ~= ""
	local primaryY = hasCaption and 5 or math.floor((Tokens.Size.rowHeight - (Tokens.Type.sizeBody + Tokens.Space.xs)) / 2)
	local p = Components.text(r, primary, "body",
		UDim2.new(1, -horizontalInset * 2, 0, Tokens.Type.sizeBody + Tokens.Space.xs),
		UDim2.new(0, horizontalInset, 0, primaryY))
	p:SetAttribute("GFRowText", "primary")

	if hasCaption then
		local c = Components.text(r, caption :: string, "caption",
			UDim2.new(1, -horizontalInset * 2, 0, Tokens.Type.sizeSmall + Tokens.Space.xs),
			UDim2.new(0, horizontalInset, 0, 29))
		c:SetAttribute("GFRowText", "caption")
	end
	return r
end

-- row selection companion: amber fill + inverse text, cyan edge. consumers that
-- use custom row content can still paint manually; this helper handles standard rows.
function Components.setRowSelected(row: Frame, selected: boolean)
	row:SetAttribute("GFSelected", selected)
	row.BackgroundColor3 = selected and Tokens.Color.accentSelect or Tokens.Color.panelInset

	local strokeObject = row:FindFirstChildOfClass("UIStroke")
	if strokeObject then
		local stroke = strokeObject :: UIStroke
		stroke.Color = selected and Tokens.Color.techCyan or Tokens.Color.border
		stroke.Transparency = selected and 0 or 0.72
	end

	local accent = findFrame(row, "RowAccent")
	if accent then
		accent.BackgroundColor3 = selected and Tokens.Color.textOnAccent or Tokens.Color.steel
		accent.BackgroundTransparency = selected and 0 or 0.62
	end

	for _, child in ipairs(row:GetChildren()) do
		if child:IsA("TextLabel") then
			if selected then
				child.TextColor3 = Tokens.Color.textOnAccent
			else
				local role = child:GetAttribute("GFTextRole")
				child.TextColor3 = role == "caption" and Tokens.Color.textSecondary or Tokens.Color.textPrimary
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- chip: a compact state indicator (status, seats, region). read-only.
-- sharp rectangle, quiet fill, one angled end-cut in the status color.
-- ---------------------------------------------------------------------------
function Components.chip(parent: Instance, text: string, color: Color3?): Frame
	local c = Instance.new("Frame")
	c.Name = "Chip"
	c.Size = UDim2.new(0, 0, 0, Tokens.Size.chipHeight)
	c.AutomaticSize = Enum.AutomaticSize.X
	c.BackgroundColor3 = Tokens.Color.panelInset
	c.BorderSizePixel = 0
	c.ClipsDescendants = true
	c.Parent = parent

	local chipColor = color or Tokens.Color.steel
	local stroke = Instance.new("UIStroke")
	stroke.Color = chipColor
	stroke.Transparency = 0.34
	stroke.Thickness = Tokens.Frame.borderThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = c

	local cut = Components.chamferAccent(c, "topRight", 8, chipColor, Tokens.Frame.borderThickness)
	cut.BackgroundTransparency = 0.24

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
	s.ScrollBarThickness = 3
	s.ScrollBarImageColor3 = Tokens.Color.steel
	s.ScrollBarImageTransparency = 0.18
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new(0, 0, 0, 0)
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.ClipsDescendants = true
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
-- hover/focus is cyan; committed active section is amber with inverse dark text.
-- ---------------------------------------------------------------------------
function Components.sidebarItem(parent: Instance, glyph: string, name: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = "Nav_" .. name
	b.Size = UDim2.new(1, 0, 0, Tokens.Size.navItemHeight)
	b.BackgroundColor3 = Tokens.Color.panelRaised
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Text = ""
	b.ClipsDescendants = true
	b:SetAttribute("GFNavActive", false)
	b.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Name = "NavBorder"
	stroke.Color = Tokens.Color.border
	stroke.Transparency = 0.88
	stroke.Thickness = Tokens.Frame.borderThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b

	local g = Instance.new("TextLabel")
	g.Name = "Glyph"
	g.Size = UDim2.new(1, 0, 0, 27)
	g.Position = UDim2.new(0, 0, 0, Tokens.Space.sm)
	g.BackgroundTransparency = 1
	g.Font = Tokens.Type.fontBold
	g.TextSize = 21
	g.TextColor3 = Tokens.Color.textSecondary
	g.Text = glyph
	g.Parent = b

	local n = Instance.new("TextLabel")
	n.Name = "Label"
	n.Size = UDim2.new(1, -Tokens.Space.xs, 0, 15)
	n.Position = UDim2.new(0, Tokens.Space.xs, 0, 39)
	n.BackgroundTransparency = 1
	n.Font = Tokens.Type.fontBold
	n.TextSize = Tokens.Type.sizeMicro
	n.TextColor3 = Tokens.Color.textSecondary
	n.Text = string.upper(name)
	n.TextTruncate = Enum.TextTruncate.AtEnd
	n.Parent = b

	local bar = makeStrip(b, "ActiveBar",
		UDim2.new(0, 3, 1, -Tokens.Space.md),
		UDim2.new(0, 0, 0, Tokens.Space.sm),
		Tokens.Color.techCyan, 0)
	bar.Visible = false

	local cut = Components.chamferAccent(b, "topRight", 9, Tokens.Color.borderStrong, Tokens.Frame.borderThickness)
	cut.Name = "ActiveChamfer"
	cut.BackgroundTransparency = 0.55
	cut.Visible = false

	local hot = false
	local focused = false
	local function refreshInactive()
		if bar.Visible then
			return
		end
		if hot or focused then
			g.TextColor3 = Tokens.Color.textAccent
			n.TextColor3 = Tokens.Color.textAccent
			b.BackgroundTransparency = 0.24
			stroke.Color = Tokens.Color.techCyan
			stroke.Transparency = 0.34
		else
			g.TextColor3 = Tokens.Color.textSecondary
			n.TextColor3 = Tokens.Color.textSecondary
			b.BackgroundTransparency = 1
			stroke.Color = Tokens.Color.border
			stroke.Transparency = 0.88
		end
	end

	b.MouseEnter:Connect(function()
		hot = true
		refreshInactive()
	end)
	b.MouseLeave:Connect(function()
		hot = false
		refreshInactive()
	end)
	b.SelectionGained:Connect(function()
		focused = true
		refreshInactive()
	end)
	b.SelectionLost:Connect(function()
		focused = false
		refreshInactive()
	end)
	return b
end

function Components.setNavActive(item: TextButton, active: boolean)
	item:SetAttribute("GFNavActive", active)
	local bar = findFrame(item, "ActiveBar")
	local cut = findFrame(item, "ActiveChamfer")
	local g = item:FindFirstChild("Glyph")
	local n = item:FindFirstChild("Label")
	local strokeObject = item:FindFirstChildOfClass("UIStroke")

	if bar then
		bar.Visible = active
		bar.BackgroundColor3 = active and Tokens.Color.techCyan or Tokens.Color.techCyan
	end
	if cut then
		cut.Visible = active
		cut.BackgroundColor3 = active and Tokens.Color.textOnAccent or Tokens.Color.borderStrong
		cut.BackgroundTransparency = active and 0.08 or 0.55
	end
	if g and g:IsA("TextLabel") and n and n:IsA("TextLabel") then
		g.TextColor3 = active and Tokens.Color.textOnAccent or Tokens.Color.textSecondary
		n.TextColor3 = active and Tokens.Color.textOnAccent or Tokens.Color.textSecondary
	end
	if strokeObject then
		local stroke = strokeObject :: UIStroke
		stroke.Color = active and Tokens.Color.techCyan or Tokens.Color.border
		stroke.Transparency = active and 0 or 0.88
	end

	item.BackgroundTransparency = active and 0 or 1
	item.BackgroundColor3 = active and Tokens.Color.accentSelect or Tokens.Color.panelRaised
end

return Components
