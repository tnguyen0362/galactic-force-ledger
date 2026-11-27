--!strict
-- Full-screen menu architecture (Counteroffensive mandate: vertical sidebar navigation,
-- full-screen menus). this is the shell every station menu lives in — sections register
-- into the sidebar rail, content fills the screen. replaces the legacy cramped side-panel
-- pattern surface-by-surface.
-- structure: [sidebar rail | header + content area]. sidebar is always visible while the
-- menu is open; content swaps by section. gamepad/virtual-cursor focus moves rail -> content
-- and back — one navigation language across every menu.
-- chrome follows the owner frame directive: angular bracketed edges, thin steel/cyan rules,
-- letterspaced military headers, no rounding, no image dependence.
local Tokens = require(script.Parent.Tokens)
local Components = require(script.Parent.Components)

local MenuShell = {}
MenuShell.__index = MenuShell

export type Shell = {
	gui: ScreenGui,
	root: Frame,
	rail: Frame,
	content: Frame,
	sections: { [string]: { button: TextButton, page: Frame, builder: (Frame) -> () } },
	active: string?,
	setActive: (self: any, name: string) -> (),
	registerSection: (self: any, name: string, glyph: string, builder: (Frame) -> ()) -> (),
	open: (self: any) -> (),
	close: (self: any) -> (),
	visible: boolean,

	-- additive chrome handles for consumers that need to annotate the shell header
	header: Frame?,
	headerTitle: TextLabel?,
	headerMeta: TextLabel?,
	contentBackdrop: Frame?,
	chrome: Frame?,
}

local function applyPanelMaterial(frame: Frame)
	local material = Instance.new("UIGradient")
	material.Rotation = 90
	material.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(218, 226, 230)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 184, 191)),
	})
	material.Parent = frame
end

function MenuShell.new(guiName: string, displayOrder: number?): any
	local self = setmetatable({}, MenuShell)

	local gui = Instance.new("ScreenGui")
	gui.Name = guiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder or 10
	gui.IgnoreGuiInset = true -- full-screen means full-screen; the shell owns its own safe margins
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

	-- dim ground: menus are full-screen modal surfaces — the world stays faintly visible
	-- behind them (players should never feel teleported away from the station)
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Tokens.Color.panelInset
	dim.BackgroundTransparency = Tokens.Transparency.dim
	dim.BorderSizePixel = 0
	dim.ZIndex = 1
	dim.Parent = gui

	local dimMaterial = Instance.new("UIGradient")
	dimMaterial.Rotation = 90
	dimMaterial.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.52, Color3.fromRGB(218, 226, 230)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(142, 154, 162)),
	})
	dimMaterial.Parent = dim

	-- restrained scan texture: twelve nearly-invisible horizontal lines distributed over
	-- the modal ground. it reads as a military console refresh scan without neon noise.
	local scanTexture = Components.scanlineField(dim, 12, nil, Tokens.Color.techCyan)
	scanTexture.Name = "MenuScanlines"
	scanTexture.ZIndex = 1

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.new(1, -Tokens.Size.panelMargin * 2, 1, -Tokens.Size.panelMargin * 2)
	root.Position = UDim2.new(0, Tokens.Size.panelMargin, 0, Tokens.Size.panelMargin)
	root.BackgroundTransparency = 1
	root.ZIndex = 2
	root.Parent = dim

	-- full-shell manufactured backing: quiet graphite fill, thin navy-steel rectangle,
	-- and opposing layers of vertical falloff. the angular silhouette comes from the
	-- large external corner brackets below rather than rounded clipping.
	local chrome = Instance.new("Frame")
	chrome.Name = "OuterAngularFrame"
	chrome.Size = UDim2.fromScale(1, 1)
	chrome.BackgroundColor3 = Tokens.Color.panelInset
	chrome.BackgroundTransparency = 0.03
	chrome.BorderSizePixel = 0
	chrome.ZIndex = 1
	chrome.Parent = root
	applyPanelMaterial(chrome)

	local chromeStroke = Instance.new("UIStroke")
	chromeStroke.Color = Tokens.Color.border
	chromeStroke.Transparency = 0.08
	chromeStroke.Thickness = Tokens.Frame.borderThickness
	chromeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	chromeStroke.Parent = chrome

	-- large outer brackets are the signature Destiny/HD2 frame read. they are direct
	-- children of root (which never has a UILayout), so they cannot disturb consumer layout.
	for _, corner in ipairs({ "topLeft", "topRight", "bottomLeft", "bottomRight" }) do
		local bracket = Components.cornerBracket(root, corner, 28, Tokens.Color.borderStrong,
			Tokens.Frame.cornerThickness, 0)
		bracket.ZIndex = 5
	end

	-- one sparse cyan hairline across the top edge; interaction color appears once here
	-- and then only where the player can actually act.
	local topScan = Components.scanline(root,
		UDim2.new(1, -72, 0, Tokens.Size.scanlineHeight),
		Tokens.Color.techCyan, 0.54)
	topScan.Name = "TopScanline"
	topScan.Position = UDim2.new(0, 36, 0, 5)
	topScan.ZIndex = 3

	local inner = Tokens.Space.sm
	local railWidth = Tokens.Size.sidebarWidth
	local contentX = inner + railWidth + inner
	local contentY = inner + Tokens.Size.headerHeight + inner

	-- vertical sidebar rail: the mandate's primary navigation. fixed width, full height.
	local rail = Components.panel(root,
		UDim2.new(0, railWidth, 1, -inner * 2),
		UDim2.new(0, inner, 0, inner))
	rail.Name = "SidebarRail"
	rail.ZIndex = 2

	-- rail uses tighter padding than content panels so the 88px mandate rail keeps a
	-- usable 64px hit/label column rather than collapsing under double inset
	local railPadding = rail:FindFirstChildOfClass("UIPadding")
	if railPadding then
		local padding = railPadding :: UIPadding
		padding.PaddingLeft = UDim.new(0, Tokens.Space.sm)
		padding.PaddingRight = UDim.new(0, Tokens.Space.sm)
		padding.PaddingTop = UDim.new(0, Tokens.Space.sm)
		padding.PaddingBottom = UDim.new(0, Tokens.Space.sm)
	end

	-- compact command mark at the top of the rail. it is part of the rail layout at
	-- order 0; registered sections begin at 1 and flow beneath it as before.
	local brand = Instance.new("Frame")
	brand.Name = "RailBrand"
	brand.Size = UDim2.new(1, -Tokens.Space.sm, 0, 56)
	brand.BackgroundTransparency = 1
	brand.BorderSizePixel = 0
	brand.LayoutOrder = 0
	brand.Parent = rail

	local brandMark = Components.text(brand, "GF", "display",
		UDim2.new(1, 0, 0, 25), UDim2.new(0, 0, 0, 0))
	brandMark.Name = "BrandMark"
	brandMark.TextXAlignment = Enum.TextXAlignment.Center
	brandMark.TextSize = 22
	brandMark.TextColor3 = Tokens.Color.textPrimary

	local brandLabel = Components.text(brand, "OPS LINK", "label",
		UDim2.new(1, 0, 0, 14), UDim2.new(0, 0, 0, 27))
	brandLabel.Name = "BrandLabel"
	brandLabel.TextXAlignment = Enum.TextXAlignment.Center
	brandLabel.TextSize = Tokens.Type.sizeMicro
	brandLabel.TextColor3 = Tokens.Color.textSecondary

	local brandLine = Components.scanline(brand,
		UDim2.new(0.58, 0, 0, 1), Tokens.Color.techCyan, 0.42)
	brandLine.AnchorPoint = Vector2.new(0.5, 0)
	brandLine.Position = UDim2.new(0.5, 0, 1, -3)

	local railLayout = Instance.new("UIListLayout")
	railLayout.FillDirection = Enum.FillDirection.Vertical
	railLayout.Padding = UDim.new(0, Tokens.Space.sm)
	railLayout.SortOrder = Enum.SortOrder.LayoutOrder
	railLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	railLayout.Parent = rail

	-- header strip: letterspaced active section title, sparse cyan terminal detail,
	-- context readout on the right. content pages begin below this shared chrome.
	local header = Instance.new("Frame")
	header.Name = "HeaderStrip"
	header.Size = UDim2.new(1, -(contentX + inner), 0, Tokens.Size.headerHeight)
	header.Position = UDim2.new(0, contentX, 0, inner)
	header.BackgroundColor3 = Tokens.Color.panelInset
	header.BackgroundTransparency = 0.02
	header.BorderSizePixel = 0
	header.ClipsDescendants = true
	header.ZIndex = 2
	header.Parent = root
	applyPanelMaterial(header)

	local headerStroke = Instance.new("UIStroke")
	headerStroke.Color = Tokens.Color.border
	headerStroke.Transparency = 0.18
	headerStroke.Thickness = Tokens.Frame.borderThickness
	headerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	headerStroke.Parent = header

	Components.cornerBracket(header, "topRight", 11, Tokens.Color.borderStrong, 1, 3)
	Components.cornerBracket(header, "bottomLeft", 11, Tokens.Color.borderStrong, 1, 3)
	local headerCut = Components.chamferAccent(header, "topRight", 12, Tokens.Color.techCyan, 1)
	headerCut.BackgroundTransparency = 0.28

	local sectionTick = Instance.new("Frame")
	sectionTick.Name = "SectionTick"
	sectionTick.Size = UDim2.new(0, 3, 0, 29)
	sectionTick.Position = UDim2.new(0, 11, 0, 12)
	sectionTick.BackgroundColor3 = Tokens.Color.techCyan
	sectionTick.BorderSizePixel = 0
	sectionTick.Parent = header

	local headerTitle = Components.text(header, "STANDBY", "header",
		UDim2.new(0.58, -28, 0, 28), UDim2.new(0, 24, 0, 5))
	headerTitle.Name = "SectionTitle"
	headerTitle.TextSize = Tokens.Type.sizeSubtitle - 1
	headerTitle.TextColor3 = Tokens.Color.textPrimary

	local headerMeta = Components.text(header, "OPERATIONS COMMAND", "caption",
		UDim2.new(0.38, -24, 0, 15), UDim2.new(0.62, 0, 0, 10))
	headerMeta.Name = "HeaderMeta"
	headerMeta.TextXAlignment = Enum.TextXAlignment.Right
	headerMeta.TextColor3 = Tokens.Color.textSecondary

	local headerSubMeta = Components.text(header, "GF-Orbit // tactical interface", "mono",
		UDim2.new(0.38, -24, 0, 13), UDim2.new(0.62, 0, 0, 28))
	headerSubMeta.Name = "HeaderSubMeta"
	headerSubMeta.TextXAlignment = Enum.TextXAlignment.Right
	headerSubMeta.TextSize = Tokens.Type.sizeMicro
	headerSubMeta.TextColor3 = Tokens.Color.textDisabled

	local headerRule = Components.divider(header, "horizontal", 1, Tokens.Color.border)
	headerRule.Position = UDim2.new(0, 0, 1, -1)
	headerRule.BackgroundTransparency = 0.48

	-- content backing panel supplies the quiet raised graphite surface; the actual
	-- content frame remains transparent so existing page builders own their layout exactly.
	local contentSize = UDim2.new(1, -(contentX + inner), 1, -(contentY + inner))
	local contentPosition = UDim2.new(0, contentX, 0, contentY)
	local contentBackdrop = Components.panel(root, contentSize, contentPosition)
	contentBackdrop.Name = "ContentBackdrop"
	contentBackdrop.ZIndex = 1

	-- page builders still own the full content rectangle they receive, but that rectangle
	-- is inset inside the visible backing panel so type and rows never touch the frame line
	local contentInset = Tokens.Space.md
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -(contentX + inner + contentInset * 2), 1, -(contentY + inner + contentInset * 2))
	content.Position = UDim2.new(0, contentX + contentInset, 0, contentY + contentInset)
	content.BackgroundTransparency = 1
	content.ZIndex = 3
	content.Parent = root

	self.gui = gui
	self.root = root
	self.rail = rail
	self.content = content
	self.sections = {}
	self.active = nil
	self.visible = false
	self.header = header
	self.headerTitle = headerTitle
	self.headerMeta = headerMeta
	self.contentBackdrop = contentBackdrop
	self.chrome = chrome
	return self
end

-- registerSection: name is the nav label, glyph the rail icon, builder fills the page frame
function MenuShell.registerSection(self: any, name: string, glyph: string, builder: (Frame) -> ())
	local order = 1
	for _ in pairs(self.sections) do
		order += 1
	end
	local btn = Components.sidebarItem(self.rail, glyph, name)
	btn.LayoutOrder = order
	btn.Size = UDim2.new(1, -Tokens.Space.sm, 0, Tokens.Size.navItemHeight)

	local page = Instance.new("Frame")
	page.Name = "Page_" .. name
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.Visible = false
	page.Parent = self.content

	builder(page)

	self.sections[name] = { button = btn, page = page, builder = builder }
	btn.Activated:Connect(function()
		self:setActive(name)
	end)
end

function MenuShell.setActive(self: any, name: string)
	for key, section in pairs(self.sections) do
		local isActive = key == name
		section.page.Visible = isActive
		Components.setNavActive(section.button, isActive)
	end
	self.active = name

	-- shared chrome reflects the active section in the military header voice. consumers
	-- no longer need to duplicate a top-level section title inside every page.
	local title = self.headerTitle
	if title then
		title.Text = Components.letterspace(string.upper(name), 1)
	end
	local meta = self.headerMeta
	local section = self.sections[name]
	if meta and section and section.button then
		meta.Text = string.format("OPERATIONS COMMAND // %02d", section.button.LayoutOrder)
	end
end

function MenuShell.open(self: any)
	self.gui.Enabled = true
	self.visible = true
	-- default to the first registered section if none is active; layout order is the
	-- registration order, so first-open behavior is deterministic across sessions
	if not self.active then
		local firstName = nil :: string?
		local firstOrder = math.huge
		for key, section in pairs(self.sections) do
			if section.button.LayoutOrder < firstOrder then
				firstOrder = section.button.LayoutOrder
				firstName = key
			end
		end
		if firstName then
			self:setActive(firstName)
		end
	end
end

function MenuShell.close(self: any)
	self.gui.Enabled = false
	self.visible = false
end

return MenuShell
