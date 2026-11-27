--!strict
-- Design tokens (Counteroffensive Stage 5 foundation — pulled forward per owner directive
-- "make sure the ui is by the spec"). single source of truth for every color, type size,
-- spacing, and motion value in the interface. per-file ad-hoc constants are prohibited for
-- new UI; migration of legacy surfaces happens surface-by-surface.
-- palette is grounded in the owner-approved art direction (art-direction-v1.md):
-- GF graphite/navy/steel/ceramic/tech-cyan, sophistication through restraint.
local Tokens = {}

-- ---------------------------------------------------------------------------
-- faction palettes — exact owner-approved art-spec colors. these are the source
-- values; semantic UI roles below are derived from them and stay more restrained.
-- ---------------------------------------------------------------------------
local GF_GRAPHITE = Color3.fromRGB(0x25, 0x2D, 0x35) -- #252D35
local GF_NAVY = Color3.fromRGB(0x3B, 0x4D, 0x60)     -- #3B4D60
local GF_STEEL = Color3.fromRGB(0x83, 0x90, 0x9B)    -- #83909B
local GF_CERAMIC = Color3.fromRGB(0xD8, 0xDC, 0xD9)  -- #D8DCD9
local GF_TECH_CYAN = Color3.fromRGB(0x58, 0xC8, 0xF0) -- #58C8F0

local ASC_OBSIDIAN = Color3.fromRGB(0x24, 0x21, 0x2A) -- #24212A
local ASC_SLATE = Color3.fromRGB(0x51, 0x46, 0x5E)    -- #51465E
local ASC_BRONZE = Color3.fromRGB(0x96, 0x78, 0x54)   -- #967854
local ASC_IVORY = Color3.fromRGB(0xD6, 0xCB, 0xB4)    -- #D6CBB4
local ASC_TECH_VIOLET = Color3.fromRGB(0xA9, 0x63, 0xE9) -- #A963E9

local galacticForcePalette = {
	graphite = GF_GRAPHITE,
	navy = GF_NAVY,
	steel = GF_STEEL,
	ceramic = GF_CERAMIC,
	techCyan = GF_TECH_CYAN,
	cyan = GF_TECH_CYAN,
}

local ascendancyPalette = {
	obsidian = ASC_OBSIDIAN,
	slate = ASC_SLATE,
	bronze = ASC_BRONZE,
	ivory = ASC_IVORY,
	techViolet = ASC_TECH_VIOLET,
	violet = ASC_TECH_VIOLET,
}

Tokens.Faction = {
	GF = galacticForcePalette,
	GalacticForce = galacticForcePalette,
	galacticForce = galacticForcePalette,
	Ascendancy = ascendancyPalette,
	ascendancy = ascendancyPalette,
}
Tokens.FactionPalette = Tokens.Faction

-- ---------------------------------------------------------------------------
-- color — semantic interface roles. broad surfaces stay quiet; cyan identifies
-- interactive/informational elements, amber identifies committed selection.
-- ---------------------------------------------------------------------------
local PANEL = Color3.fromRGB(0x17, 0x1F, 0x27)       -- low-contrast blue-graphite ground
local PANEL_RAISED = GF_GRAPHITE                     -- quiet raised military surface
local PANEL_INSET = Color3.fromRGB(0x10, 0x16, 0x1C) -- recessed wells and list rows
local BORDER = Color3.fromRGB(0x3B, 0x4D, 0x60)      -- desaturated navy-steel line
local BORDER_STRONG = Color3.fromRGB(0x67, 0x78, 0x86)
local SELECT_AMBER = Color3.fromRGB(0xD8, 0xA8, 0x58) -- #D8A858
local TEXT_INVERSE = Color3.fromRGB(0x11, 0x18, 0x20)

Tokens.Color = {
	-- base structure (existing keys — stable API)
	graphite = GF_GRAPHITE,
	navy = GF_NAVY,
	steel = GF_STEEL,
	ceramic = GF_CERAMIC,
	techCyan = GF_TECH_CYAN,

	-- derived panel roles (existing keys — stable API)
	panel = PANEL,
	panelRaised = PANEL_RAISED,
	panelInset = PANEL_INSET,
	border = BORDER,
	borderFocus = GF_TECH_CYAN,
	accentSelect = SELECT_AMBER,

	-- text roles (existing keys — stable API)
	textPrimary = GF_CERAMIC,
	textSecondary = GF_STEEL,
	textAccent = GF_TECH_CYAN,
	textDisabled = Color3.fromRGB(0x4A, 0x54, 0x5E),

	-- semantic feedback (existing keys — stable API)
	success = Color3.fromRGB(0x6E, 0xC8, 0x8F),
	warning = SELECT_AMBER,
	danger = Color3.fromRGB(0xC8, 0x6E, 0x6E),
	ascendancy = ASC_TECH_VIOLET,

	-- additive semantic aliases for new consumer surfaces
	accent = GF_TECH_CYAN,
	cyan = GF_TECH_CYAN,
	amber = SELECT_AMBER,
	selection = SELECT_AMBER,
	selected = SELECT_AMBER,
	selectionText = TEXT_INVERSE,
	textOnAccent = TEXT_INVERSE,
	textInverse = TEXT_INVERSE,
	textMuted = GF_STEEL,
	textBright = GF_CERAMIC,
	onAccent = TEXT_INVERSE,
	onSelection = TEXT_INVERSE,
	borderStrong = BORDER_STRONG,
	borderQuiet = BORDER,
	panelBorder = BORDER,
	line = BORDER,
	lineStrong = BORDER_STRONG,
	surface = PANEL,
	surfaceRaised = PANEL_RAISED,
	surfaceInset = PANEL_INSET,
	background = PANEL_INSET,
	overlay = PANEL_INSET,
	info = GF_TECH_CYAN,
	interactive = GF_TECH_CYAN,
	focus = GF_TECH_CYAN,
	ally = GF_TECH_CYAN,
	enemy = ASC_TECH_VIOLET,
	factionCyan = GF_TECH_CYAN,
	factionViolet = ASC_TECH_VIOLET,
}

-- theater status colors: the war-state taxonomy gets fixed semantic colors everywhere
Tokens.StatusColor = {
	ascendancy_dominance = ASC_TECH_VIOLET,   -- ascendancy violet: it is THEIR color
	contested_theater = SELECT_AMBER,         -- amber warning
	human_infiltration = GF_STEEL,            -- steel: early presence
	gf_offensive = GF_TECH_CYAN,              -- tech cyan: our push
	established_superiority = Color3.fromRGB(0x6E, 0xC8, 0x8F), -- success green: secured
}

-- ---------------------------------------------------------------------------
-- typography — Gotham is the primary military-sans voice. RobotoMono remains
-- available for numeric readouts and terminal-flavored metadata. existing keys
-- are stable; the larger ramp is additive.
-- ---------------------------------------------------------------------------
Tokens.Type = {
	font = Enum.Font.GothamMedium,
	fontBold = Enum.Font.GothamBold,
	fontDisplay = Enum.Font.GothamBlack,
	fontMono = Enum.Font.RobotoMono,
	fontMonoBold = Enum.Font.Code,

	-- additive readability aliases
	fontBody = Enum.Font.GothamMedium,
	fontHeader = Enum.Font.GothamBold,
	fontTerminal = Enum.Font.RobotoMono,

	sizeSmall = 13,   -- captions, metadata, secondary readouts
	sizeBody = 16,    -- default interactive text
	sizeTitle = 22,   -- section headers, panel titles

	-- additive ramp for the full menu hierarchy
	sizeMicro = 12,       -- rail micro-labels only; never below this in new UI
	sizeCaption = 13,
	sizeLabel = 14,
	sizeBodyLarge = 18,
	sizeSubtitle = 20,
	sizeHeader = 24,
	sizeDisplay = 30,
	sizeHero = 36,
}

-- ---------------------------------------------------------------------------
-- spacing — 4px grid, consistent rhythm
-- ---------------------------------------------------------------------------
Tokens.Space = {
	xxs = 2,
	xs = 4,
	sm = 8,
	md = 16,
	lg = 24,
	xl = 40,
	xxl = 56,
	xxxl = 72,
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

	-- additive chrome measurements for the angular menu frame language
	headerHeight = 54,
	navItemHeight = 64,
	dividerHeight = 1,
	scanlineHeight = 2,
	bracketLength = 16,
	bracketThickness = 2,
	chamferLength = 12,
	borderThickness = 1,
	borderThicknessStrong = 2,
}

-- sharp frame geometry in one place. no UICorner anywhere: depth comes from
-- thin border lines, bracketed corners, chamfer accents, and layered dark fills.
Tokens.Frame = {
	cornerLength = Tokens.Size.bracketLength,
	cornerThickness = Tokens.Size.bracketThickness,
	cornerInset = 2,
	chamferLength = Tokens.Size.chamferLength,
	borderThickness = Tokens.Size.borderThickness,
	borderThicknessStrong = Tokens.Size.borderThicknessStrong,
}

-- Roblox transparency values (0 opaque, 1 invisible). panels should read as
-- manufactured surfaces, not glass; translucency is reserved for menu overlays.
Tokens.Transparency = {
	solid = 0,
	panel = 0.03,
	raised = 0,
	inset = 0,
	overlay = 0.10,
	dim = 0.08,
	line = 0.28,
	lineQuiet = 0.48,
	scanline = 0.90,
	disabled = 0.62,
}

-- ---------------------------------------------------------------------------
-- motion — restrained, functional. nothing bounces in a military interface.
-- ---------------------------------------------------------------------------
Tokens.Motion = {
	instant = 0,
	fast = 0.12,   -- hover/focus feedback
	medium = 0.22, -- panel open/close
	slow = 0.34,   -- shell-scale transitions only
	easing = Enum.EasingStyle.Quad,
	direction = Enum.EasingDirection.Out,
	easingInOut = Enum.EasingDirection.InOut,
}

-- ---------------------------------------------------------------------------
-- accessibility — contrast floor: interactive text on panel grounds must clear
-- 4.5:1 against its background; the palette above is chosen so the default
-- pairings (ceramic-on-panel, cyan-on-panelInset, inverse-on-amber) all pass.
-- verified by construction: no component may recolor text outside these roles.
-- ---------------------------------------------------------------------------

return Tokens
