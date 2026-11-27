--!strict
-- Full-screen menu architecture (Counteroffensive mandate: vertical sidebar navigation,
-- full-screen menus). this is the shell every station menu lives in — sections register
-- into the sidebar rail, content fills the screen. replaces the legacy cramped side-panel
-- pattern surface-by-surface.
-- structure: [sidebar rail | content area]. sidebar is always visible while the menu is
-- open; content swaps by section. gamepad/virtual-cursor focus moves rail -> content
-- and back — one navigation language across every menu.
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
}

function MenuShell.new(guiName: string, displayOrder: number?): any
	local self = setmetatable({}, MenuShell)

	local gui = Instance.new("ScreenGui")
	gui.Name = guiName
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder or 10
	gui.IgnoreGuiInset = true -- full-screen means full-screen; the shell owns its own safe margins
	gui.Enabled = false
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

	-- dim ground: menus are full-screen modal surfaces — the world stays faintly visible
	-- behind them (players should never feel teleported away from the station)
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Tokens.Color.panel
	dim.BackgroundTransparency = 0.12
	dim.BorderSizePixel = 0
	dim.Parent = gui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.new(1, -Tokens.Size.panelMargin * 2, 1, -Tokens.Size.panelMargin * 2)
	root.Position = UDim2.new(0, Tokens.Size.panelMargin, 0, Tokens.Size.panelMargin)
	root.BackgroundTransparency = 1
	root.Parent = dim

	-- vertical sidebar rail: the mandate's primary navigation. fixed width, full height.
	local rail = Components.panel(root, UDim2.new(0, Tokens.Size.sidebarWidth, 1, 0), UDim2.new(0, 0, 0, 0))
	rail.Name = "SidebarRail"
	local railLayout = Instance.new("UIListLayout")
	railLayout.FillDirection = Enum.FillDirection.Vertical
	railLayout.Padding = UDim.new(0, Tokens.Space.sm)
	railLayout.SortOrder = Enum.SortOrder.LayoutOrder
	railLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	railLayout.Parent = rail

	-- content area fills everything right of the rail
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -Tokens.Size.sidebarWidth - Tokens.Space.md, 1, 0)
	content.Position = UDim2.new(0, Tokens.Size.sidebarWidth + Tokens.Space.md, 0, 0)
	content.BackgroundTransparency = 1
	content.Parent = root

	self.gui = gui
	self.root = root
	self.rail = rail
	self.content = content
	self.sections = {}
	self.active = nil
	self.visible = false
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
	btn.Size = UDim2.new(1, -Tokens.Space.sm, 0, 64)

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
end

function MenuShell.open(self: any)
	self.gui.Enabled = true
	self.visible = true
	-- default to the first registered section if none is active
	if not self.active then
		for key in pairs(self.sections) do
			self:setActive(key)
			break
		end
	end
end

function MenuShell.close(self: any)
	self.gui.Enabled = false
	self.visible = false
end

return MenuShell
