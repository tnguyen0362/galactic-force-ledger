--!strict
-- Design tokens (Counteroffensive Stage 5 foundation — pulled forward per owner directive
-- "make sure the ui is by the spec"). single source of truth for every color, type size,
-- spacing, and motion value in the interface. per-file ad-hoc constants are prohibited for
-- new UI; migration of legacy surfaces happens surface-by-surface.
-- palette is grounded in the owner-approved art direction (art-direction-v1.md):
-- GF graphite/navy/steel/ceramic/tech-cyan, sophistication through restraint.
local Tokens = {}

-- ---------------------------------------------------------------------------
-- color — Galactic Force faction palette (human military) + semantic roles
-- ---------------------------------------------------------------------------
Tokens.Color = {
	-- base structure
	graphite = Color3.fromRGB(0x25, 0x2D, 0x35), -- deepest panel chrome
	navy = Color3.fromRGB(0x3B, 0x4D, 0x60),     -- raised surfaces, selection frames
	steel = Color3.fromRGB(0x83, 0x90, 0x9B),    -- secondary text, borders, inactive
	ceramic = Color3.fromRGB(0xD8, 0xDC, 0xD9),  -- primary text
	techCyan = Color3.fromRGB(0x58, 0xC8, 0xF0), -- the ONE accent: interactive, active, focus

	-- derived panel roles (detail hierarchy: broad surfaces stay quiet)
	panel = Color3.fromRGB(0x1B, 0x22, 0x29),    -- full-screen menu ground
	panelRaised = Color3.fromRGB(0x25, 0x2D, 0x35),
	panelInset = Color3.fromRGB(0x14, 0x1A, 0x20), -- wells, list rows, input fields
	border = Color3.fromRGB(0x3B, 0x4D, 0x60),
	borderFocus = Color3.fromRGB(0x58, 0xC8, 0xF0),

	-- text roles
	textPrimary = Color3.fromRGB(0xD8, 0xDC, 0xD9),
	textSecondary = Color3.fromRGB(0x83, 0x90, 0x9B),
	textAccent = Color3.fromRGB(0x58, 0xC8, 0xF0),
	textDisabled = Color3.fromRGB(0x4A, 0x54, 0x5E),

	-- semantic feedback — restrained, never neon
	success = Color3.fromRGB(0x6E, 0xC8, 0x8F),
	warning = Color3.fromRGB(0xD8, 0xA8, 0x58),
	danger = Color3.fromRGB(0xC8, 0x6E, 0x6E),
	ascendancy = Color3.fromRGB(0xA9, 0x63, 0xE9), -- enemy-faction violet, strategic display only
}

-- theater status colors: the war-state taxonomy gets fixed semantic colors everywhere
Tokens.StatusColor = {
	ascendancy_dominance = Color3.fromRGB(0xA9, 0x63, 0xE9),  -- ascendancy violet: it is THEIR color
	contested_theater = Color3.fromRGB(0xD8, 0xA8, 0x58),     -- amber warning
	human_infiltration = Color3.fromRGB(0x83, 0x90, 0x9B),    -- steel: early presence
	gf_offensive = Color3.fromRGB(0x58, 0xC8, 0xF0),          -- tech cyan: our push
	established_superiority = Color3.fromRGB(0x6E, 0xC8, 0x8F) -- success green: secured
}

-- ---------------------------------------------------------------------------
-- typography — RobotoMono throughout: the military terminal voice. three sizes only.
-- ---------------------------------------------------------------------------
Tokens.Type = {
	font = Enum.Font.RobotoMono,
	fontBold = Enum.Font.Code, -- RobotoMono has no bold variant in engine; Code reads as emphasis
	sizeSmall = 13,   -- captions, metadata, secondary readouts
	sizeBody = 16,    -- default interactive text
	sizeTitle = 22,   -- section headers, panel titles
	-- minimum readable sizes per platform are enforced in components, not here
}

-- ---------------------------------------------------------------------------
-- spacing — 4px grid, consistent rhythm
-- ---------------------------------------------------------------------------
Tokens.Space = {
	xs = 4,
	sm = 8,
	md = 16,
	lg = 24,
	xl = 40,
}

-- ---------------------------------------------------------------------------
-- sizing — cross-platform interaction minimums (mandate: extremely mobile-friendly).
-- touch targets never below 52px on their shortest dimension; console focus targets
-- share the same floor since the virtual cursor is not pixel-precise.
-- ---------------------------------------------------------------------------
Tokens.Size = {
	touchMin = 52,
	buttonHeight = 52,
	rowHeight = 56,      -- list rows: target + one metadata line
	sidebarWidth = 88,   -- vertical sidebar rail (icons + micro-labels)
	chipHeight = 36,
	panelMargin = 24,
}

-- ---------------------------------------------------------------------------
-- motion — restrained, functional. nothing bounces in a military interface.
-- ---------------------------------------------------------------------------
Tokens.Motion = {
	instant = 0,
	fast = 0.12,   -- hover/focus feedback
	medium = 0.22, -- panel open/close
	easing = Enum.EasingStyle.Quad,
	direction = Enum.EasingDirection.Out,
}

-- ---------------------------------------------------------------------------
-- accessibility — contrast floor: interactive text on panel grounds must clear
-- 4.5:1 against its background; the palette above is chosen so the default
-- pairings (ceramic-on-panel, cyan-on-panelInset) all pass. verified by construction:
-- no component may recolor text outside these roles.
-- ---------------------------------------------------------------------------

return Tokens
