--!nonstrict
-- GalaxyMap v1: the DEPLOY screen as a full-screen Helldivers-2-style galactic war map.
-- builds its own ScreenGui overlay (so it can take the whole screen, like HD2's war table) and
-- shows it whenever the shell is open on the DEPLOY page. layout is authored on a virtual canvas
-- and uniformly scaled (UIScale), so it reads the same on a 1080p monitor and a phone.
--
-- structure (from the HD2 references): left column = war title + liberation + stats + sector
-- card (with the operation list); right column = tabs + Command Order panel; centre = ringed
-- theater map with territory zones, supply lanes, planets; bottom centre = difficulty selector
-- + DEPLOY (HD2's QUICKPLAY slot); bottom left = BACK.
--
-- wire contract is UNCHANGED from the legacy panel:
--   RequestDeploy:FireServer({difficulty=, operationId=})   -- server resolves template
--   DeployStateChanged {ok=boolean, reason=string?}         -- verdicts; zone publications carry no ok
-- all war data is read from workspace attributes the server already publishes. nothing here
-- invents war numbers.
--
-- usage: local map = GalaxyMap.mount(page, { shell = shell, remotes = remotes })

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GF = ReplicatedStorage:WaitForChild("GF")
local Tokens = require(GF.Shared.UI.Tokens)
local WarModel = require(GF.Shared.WarModel)
local WarOperations = require(GF.Shared.Configs.WarOperations)

local C = Tokens.Color
local T = Tokens.Type

local GalaxyMap = {}

-- ---------------------------------------------------------------------------
-- static presentation data
-- ---------------------------------------------------------------------------
-- polar placement on the ring map: angle in degrees clockwise from straight up, radius as a
-- fraction of the map radius. kept off the bottom-centre so the deploy cluster never covers a
-- planet.
local POLAR = {
	-- ring radius 0.68: adjacent-plate chord 0.59R vs plate width 0.42R — guaranteed
	-- separation (the 0.52 ring was mathematically overlapping: chord 0.45R < width 0.52R).
	-- the planet face reaches 0.82R, so plates at 0.68 sit on the surface — correct fiction
	-- for territories of one world.
	AshenDivide = { 257, 0.68 },
	VerdantReach = { 309, 0.68 },
	ThornBasin = { 0, 0.68 },
	IronMarch = { 51, 0.68 },
	FoundryBelt = { 103, 0.68 },
	WhiteRidge = { 154, 0.68 },
	RedMesa = { 206, 0.68 },
	Frostline = { 0, 0 },
}

local BIOME_TINT = {
	forest = Color3.fromRGB(0x2C, 0x5A, 0x3A),
	ash = Color3.fromRGB(0x6A, 0x42, 0x2C),
	frost = Color3.fromRGB(0x4A, 0x6E, 0x84),
	iron = Color3.fromRGB(0x58, 0x5C, 0x66),
}

local BIOME_NAMES = {
	forest = "ETHEREAL JUNGLE",
	ash = "ACIDIC BADLANDS",
	frost = "ICY GLACIERS",
	iron = "DEADLANDS",
}

local BIOME_CONDITIONS = {
	forest = { "THICK FOG", "RAINSTORMS", "ATMOSPHERIC SPORES" },
	ash = { "INTENSE HEAT", "VOLCANIC ACTIVITY", "FIRE TORNADOS" },
	frost = { "EXTREME COLD", "BLIZZARDS", "ION STORMS" },
	iron = { "TREMORS", "ION STORMS", "METEOR STORMS" },
}

local FAMILY_COLOR = {
	Conquest = C.techCyan,
	Recovery = C.success,
	Elimination = C.danger,
	Sabotage = C.warning,
	Defense = C.steel,
}

local STATUS_TEXT = {
	ascendancy_dominance = "ASCENDANCY DOMINANCE",
	contested_theater = "CONTESTED THEATER",
	human_infiltration = "HUMAN INFILTRATION",
	gf_offensive = "GF OFFENSIVE",
	established_superiority = "ESTABLISHED SUPERIORITY",
}

-- presentation mirror of StationService's rank gates; the server stays authoritative
local DIFFICULTIES = { "Easy", "Normal", "Hard", "Extreme" }
local DIFFICULTY_RANK = { Easy = 1, Normal = 3, Hard = 6, Extreme = 14 }

local REGION_ORDER = {
	"VerdantReach", "ThornBasin", "AshenDivide", "RedMesa",
	"Frostline", "WhiteRidge", "IronMarch", "FoundryBelt",
}

local BG = Color3.fromRGB(0x06, 0x0A, 0x0F)
local CARD = Color3.fromRGB(0x04, 0x07, 0x0A)

-- ---------------------------------------------------------------------------
-- pure helpers
-- ---------------------------------------------------------------------------
local function regionName(rid: string): string
	return string.upper((rid:gsub("(%l)(%u)", "%1 %2")))
end

local function prettyId(id: string): string
	return string.upper((id:gsub("_", " ")))
end

local function stableHash(text: string): number
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + string.byte(text, i)) % 2147483647
	end
	return h
end

local function biomeOf(rid: string): string
	local terr = WarModel.TERRITORIES[rid]
	return (terr and terr.biome) or "forest"
end

local function opDisplayName(opId: string): string
	return (WarOperations.DisplayName and WarOperations.DisplayName[opId]) or prettyId(opId)
end

local function hex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- GF_WarTerritories = "Id:progress:State[:FRONT];..." covers all 8 regions, unlike the
-- GF_WarState_* matrix which only publishes some of them.
local function parseTerritories()
	local out = {}
	local raw = workspace:GetAttribute("GF_WarTerritories")
	if type(raw) == "string" then
		for entry in raw:gmatch("[^;]+") do
			local id, progress, state, front = entry:match("^([^:]+):(-?%d+):([^:]*):?(.*)$")
			if id then
				out[id] = { progress = tonumber(progress) or 0, state = state or "", front = front == "FRONT" }
			end
		end
	end
	return out
end

local function legacyStatus(state: string): string
	local s = string.lower(state or "")
	if s:find("contest") then
		return "contested_theater"
	elseif s:find("liberat") or s:find("secur") or s:find("superior") then
		return "established_superiority"
	elseif s:find("offens") then
		return "gf_offensive"
	elseif s:find("infiltr") then
		return "human_infiltration"
	end
	return "ascendancy_dominance"
end

local function regionInfo(rid: string, territories)
	local terr = territories[rid]
	local rawStatus = workspace:GetAttribute("GF_WarState_" .. rid .. "_Status")
	local H = tonumber(workspace:GetAttribute("GF_WarState_" .. rid .. "_H"))
	local E = tonumber(workspace:GetAttribute("GF_WarState_" .. rid .. "_E"))
	local info = {
		rid = rid,
		front = terr ~= nil and terr.front or false,
		H = H,
		E = E,
		live = type(rawStatus) == "string" and rawStatus ~= "",
	}
	if info.live then
		info.status = rawStatus
	elseif terr then
		info.status = legacyStatus(terr.state)
	else
		info.status = "ascendancy_dominance"
	end
	-- liberation = GF force share H/(H+E); regions the matrix does not publish fall back to the
	-- legacy territory progress (0-100)
	local control = tonumber(workspace:GetAttribute("GF_WarControl_" .. rid))
	if control then
		if control > 1 then
			control = control / 100
		end
	elseif H and E and H + E > 0 then
		control = H / (H + E)
	elseif terr then
		control = terr.progress / 100
	end
	info.control = control and math.clamp(control, 0, 1) or nil
	return info
end

local function statusColor(status: string): Color3
	return Tokens.StatusColor[status] or C.steel
end

-- ---------------------------------------------------------------------------
-- tiny UI builders
-- ---------------------------------------------------------------------------
local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function stroke(parent: Instance, color: Color3, thickness: number?, transparency: number?): UIStroke
	return make("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function label(parent: Instance, text: string, size: number, color: Color3, bold: boolean?, align: Enum.TextXAlignment?): TextLabel
	return make("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextColor3 = color,
		Font = bold and T.fontBold or T.font,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, size + 4),
	}, parent)
end

local function paintButton(b: TextButton)
	local s = b:FindFirstChildOfClass("UIStroke")
	local locked = b:GetAttribute("locked") == true
	local hover = b:GetAttribute("hover") == true
	local primary = b:GetAttribute("primary") == true
	local vstate = b:GetAttribute("vstate")
	local bg, fg, sc, st = CARD, C.textPrimary, C.border, 0.1
	if primary then
		-- HD2's QUICKPLAY slot: black fill, amber frame, amber caps
		bg, fg, sc, st = CARD, C.warning, C.warning, 0
		if vstate == "pending" then
			bg, fg, sc = C.accentSelect, CARD, C.accentSelect
		elseif vstate == "accepted" then
			bg, fg, sc = C.success, CARD, C.success
		elseif vstate == "refused" then
			fg, sc = C.warning, C.danger
		elseif hover then
			bg = Color3.fromRGB(0x2A, 0x22, 0x10)
		end
	elseif locked then
		fg, sc, st = C.textDisabled, C.border, 0.6
	elseif hover then
		bg, sc, st = C.navy, C.techCyan, 0.1
	end
	b.BackgroundColor3 = bg
	b.TextColor3 = fg
	if s then
		s.Color = sc
		s.Transparency = st
	end
end

local function button(parent: Instance, text: string, textSize: number): TextButton
	local b = make("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = CARD,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Text = text,
		TextSize = textSize,
		TextColor3 = C.textPrimary,
		Font = T.fontBold,
		TextWrapped = true,
	}, parent)
	stroke(b, C.border, 1, 0.1)
	b.MouseEnter:Connect(function()
		b:SetAttribute("hover", true)
		paintButton(b)
	end)
	b.MouseLeave:Connect(function()
		b:SetAttribute("hover", false)
		paintButton(b)
	end)
	paintButton(b)
	return b
end

-- ---------------------------------------------------------------------------
-- mount
-- ---------------------------------------------------------------------------
function GalaxyMap.mount(page: Frame, ctx)
	local shell = ctx and ctx.shell
	local remotes = ctx and ctx.remotes
	local localPlayer = Players.LocalPlayer
	local conns = {}
	local function track(c)
		table.insert(conns, c)
		return c
	end

	local state = {
		region = "VerdantReach",
		operationId = nil,
		difficulty = "Normal",
		rank = nil,
		committing = false,
		commitToken = 0,
		terminal = {},
		territories = {},
		infos = {},
		scale = 1,
		vx = 1280,
		vy = 720,
		wasVisible = false,
		lastRefresh = 0,
		fronts = "",
	}

	-- ------------------------------------------------------------ overlay shell
	local parentGui = (ctx and ctx.parentGui) or (localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")) or page
	local gui = make("ScreenGui", {
		Name = "GalaxyMapOverlay",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = (ctx and ctx.displayOrder) or 40,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, parentGui)
	local canvas = make("Frame", {
		Name = "Canvas",
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(1280, 720),
		ClipsDescendants = true,
		Active = true, -- swallow clicks so nothing underneath the map reacts
	}, gui)
	local uiScale = make("UIScale", { Scale = 1 }, canvas)

	for i = 1, 90 do
		local h = stableHash("star" .. i)
		local big = h % 7 == 0
		make("Frame", {
			BackgroundColor3 = C.ceramic,
			BackgroundTransparency = 0.55 + (h % 40) / 100,
			BorderSizePixel = 0,
			Position = UDim2.new((h % 997) / 997, 0, ((h // 997) % 991) / 991, 0),
			Size = UDim2.fromOffset(big and 2 or 1, big and 2 or 1),
		}, canvas)
	end

	-- ------------------------------------------------------------ map stage
	local stage = make("Frame", { Name = "Stage", BackgroundTransparency = 1 }, canvas)
	-- arena disc + concentric rings + spokes (the HD2 galactic-war dial)
	local arena = make("Frame", {
		Name = "Arena",
		BackgroundColor3 = Color3.fromRGB(0x0B, 0x12, 0x1A),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.06, 1.06),
		ZIndex = 0,
	}, stage)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, arena)
	stroke(arena, C.techCyan, 3, 0.8)
	-- the one playable planet: Veyra-7. regions are territories on its surface.
	local planet = make("Frame", {
		Name = "Planet", BackgroundColor3 = Color3.fromRGB(0x14, 0x22, 0x2B), BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.82, 0.82), ZIndex = 1,
	}, stage)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, planet)
	stroke(planet, C.steel, 2, 0.3)
	local shade = make("Frame", {
		BackgroundColor3 = C.ceramic, BackgroundTransparency = 0.93, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.42, 0.4), Size = UDim2.fromScale(0.72, 0.72), ZIndex = 1,
	}, planet)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, shade)
	for k = 3, 4 do
		local f = make("Frame", {
			Name = "Ring" .. k,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.9 + (k - 3) * 0.1, 0.9 + (k - 3) * 0.1),
			ZIndex = 1,
		}, stage)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
		stroke(f, C.steel, 1, k == 4 and 0.55 or 0.8)
	end
	for k = 0, -1 do
		make("Frame", {
			Name = "Spoke" .. k,
			BackgroundColor3 = C.steel,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, 1),
			Rotation = k * 30,
			ZIndex = 1,
		}, stage)
	end

	-- hub: GF orbital command (HD2's Super Earth)
	local hub = make("Frame", {
		Name = "Hub",
		BackgroundColor3 = C.navy,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		ZIndex = 4,
	}, stage)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, hub)
	stroke(hub, C.techCyan, 2, 0)
	local hubRing = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(48, 48),
		ZIndex = 4,
	}, stage)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, hubRing)
	stroke(hubRing, C.techCyan, 1, 0.55)
	local hubLabel = label(stage, "GF ORBIT", 12, C.textAccent, true, Enum.TextXAlignment.Center)
	hubLabel.AnchorPoint = Vector2.new(0.5, 0)
	hubLabel.Position = UDim2.new(0.5, 0, 0.5, 30)
	hubLabel.Size = UDim2.fromOffset(120, 16)
	hubLabel.ZIndex = 4
	do -- GF orbital station: parked on the outer orbit ring, off the planet
		local hx = 0.5 + 0.5 * 0.97 * math.sin(math.rad(48))
		local hy = 0.5 - 0.5 * 0.97 * math.cos(math.rad(48))
		hub.Position = UDim2.fromScale(hx, hy)
		hubRing.Position = UDim2.fromScale(hx, hy)
		hub.Size = UDim2.fromOffset(18, 18)
		hubRing.Size = UDim2.fromOffset(30, 30)
		hubLabel.Position = UDim2.new(hx, 0, hy, 18)
		hubLabel.Text = "GF ORBITAL"
	end

	-- supply lanes (one per neighbour edge) + traffic pulse each
	local edges = {}
	local seen = {}
	for _, rid in ipairs(REGION_ORDER) do
		local terr = WarModel.TERRITORIES[rid]
		for _, other in ipairs(terr.neighbors) do
			local key = rid < other and (rid .. "|" .. other) or (other .. "|" .. rid)
			if not seen[key] and WarModel.TERRITORIES[other] then
				seen[key] = true
				local line = make("Frame", {
					Name = "Lane_" .. key,
					BackgroundColor3 = C.steel,
					BackgroundTransparency = 0.55,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					ZIndex = 3,
				}, stage)
				local pulse = make("Frame", {
					Name = "Pulse",
					BackgroundColor3 = C.techCyan,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(5, 5),
					Rotation = 45,
					ZIndex = 3,
				}, stage)
				table.insert(edges, {
					a = rid, b = other, line = line, pulse = pulse,
					phase = (stableHash(key) % 100) / 100,
					speed = 0.10 + (stableHash(key .. "s") % 8) / 100,
					ax = 0, ay = 0, bx = 0, by = 0,
				})
			end
		end
	end

	-- sector nodes: angular region plates (owner direction: regions are territories on ONE
	-- planet — mini planet-orbs are the wrong fiction, and liberation reads as bars, not
	-- percents). the field names are kept so paintNodes/placeMap contracts survive.
	local nodes = {}
	local function buildNode(rid: string)
		-- zone: soft diamond territory shading (angular language, not another circle)
		local zone = make("Frame", {
			Name = "Zone_" .. rid,
			BackgroundColor3 = C.steel,
			BackgroundTransparency = 0.84,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 45,
			ZIndex = 2,
		}, stage)
		local zoneStroke = stroke(zone, C.steel, 1, 0.55)
		local hit = make("TextButton", {
			Name = "Node_" .. rid,
			AutoButtonColor = false,
			Text = "",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 5,
		}, stage)
		-- selection/terminal frames: angular outlines slightly larger than the plate
		local selRing = make("Frame", {
			Name = "SelectRing",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Visible = false,
			ZIndex = 4,
		}, hit)
		stroke(selRing, C.accentSelect, 2, 0)
		local termRing = make("Frame", {
			Name = "TerminalRing",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Visible = false,
			ZIndex = 4,
		}, hit)
		stroke(termRing, C.techCyan, 1, 0.3)
		-- the plate itself (contract name "disc" — now an angular panel, not a planet orb)
		local disc = make("Frame", {
			Name = "Plate",
			BackgroundColor3 = Color3.fromRGB(0x10, 0x18, 0x22),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			ZIndex = 6,
		}, hit)
		local discStroke = stroke(disc, C.steel, 2, 0)
		-- inner edge: a thin inset frame carrying the status color at low key
		local inner = make("Frame", {
			Name = "Inner",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, -6, 1, -6),
			ZIndex = 7,
		}, disc)
		local innerStroke = stroke(inner, C.steel, 1, 0.7)
		-- front tick: angular warning bar across the plate top edge (replaces the front ring)
		local frontRing = make("Frame", {
			Name = "FrontTick",
			BackgroundColor3 = C.warning,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, -3),
			Size = UDim2.new(1, 8, 0, 3),
			Visible = false,
			ZIndex = 8,
		}, disc)
		local frontStroke = stroke(frontRing, C.warning, 1, 1)
		frontStroke.Transparency = 1
		-- region name inside the plate: bigger target, nothing dangling underneath
		local nameLabel = label(disc, regionName(rid), 13, C.textPrimary, true, Enum.TextXAlignment.Center)
		nameLabel.AnchorPoint = Vector2.new(0.5, 0)
		nameLabel.Position = UDim2.new(0.5, 0, 0, 5)
		nameLabel.Size = UDim2.new(1, -10, 0, 15)
		nameLabel.ZIndex = 8
		-- liberation bar along the plate bottom edge — the bar IS the readout, no percent
		local barTrack = make("Frame", {
			Name = "BarTrack",
			BackgroundColor3 = Color3.fromRGB(0x08, 0x0C, 0x12),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 5, 1, -5),
			Size = UDim2.new(1, -10, 0, 4),
			ZIndex = 8,
		}, disc)
		local barFill = make("Frame", {
			Name = "Fill",
			BackgroundColor3 = C.steel,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 0, 1, 0),
			ZIndex = 9,
		}, barTrack)
		nodes[rid] = {
			zone = zone, zoneStroke = zoneStroke, hit = hit, disc = disc, discStroke = discStroke,
			innerStroke = innerStroke, frontRing = frontRing, frontStroke = frontStroke,
			selRing = selRing, termRing = termRing, barTrack = barTrack, barFill = barFill,
			nameLabel = nameLabel, cx = 0, cy = 0, d = 40,
		}
	end
	for _, rid in ipairs(REGION_ORDER) do
		buildNode(rid)
	end

	-- hover card (HD2: black card, amber frame)
	local tooltip = make("Frame", {
		Name = "Tooltip",
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(210, 84),
		Visible = false,
		ZIndex = 60,
	}, canvas)
	stroke(tooltip, C.warning, 2, 0)
	local ttName = label(tooltip, "", 16, C.warning, true)
	ttName.Position = UDim2.fromOffset(10, 6)
	ttName.Size = UDim2.new(1, -20, 0, 20)
	ttName.ZIndex = 61
	local ttStatus = label(tooltip, "", 12, C.steel, true)
	ttStatus.Position = UDim2.fromOffset(10, 28)
	ttStatus.Size = UDim2.new(1, -20, 0, 14)
	ttStatus.ZIndex = 61
	local ttTrack = make("Frame", {
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 48),
		Size = UDim2.new(1, -20, 0, 6),
		ZIndex = 61,
	}, tooltip)
	local ttFill = make("Frame", {
		BackgroundColor3 = C.steel,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 62,
	}, ttTrack)
	local ttPct = label(tooltip, "", 14, C.textPrimary, true)
	ttPct.Position = UDim2.fromOffset(10, 58)
	ttPct.Size = UDim2.new(1, -20, 0, 18)
	ttPct.ZIndex = 61

	-- ------------------------------------------------------------ left column
	local left = make("Frame", { Name = "Left", BackgroundTransparency = 1 }, canvas)
	local titleIcon = make("Frame", {
		BackgroundColor3 = C.warning,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(20, 22),
		Size = UDim2.fromOffset(24, 24),
		Rotation = 45,
	}, left)
	make("Frame", {
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
	}, titleIcon)
	local titleText = label(left, "VEYRA-7 THEATER", 28, C.textPrimary, true)
	titleText.Position = UDim2.fromOffset(54, 0)
	local warSub = label(left, "", 16, C.steel, true)
	warSub.Position = UDim2.fromOffset(54, 34)
	local warLib = label(left, "", 16, C.textPrimary, false)
	warLib.Position = UDim2.fromOffset(54, 56)
	local warTrack = make("Frame", {
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(54, 82),
	}, left)
	stroke(warTrack, C.border, 1, 0.5)
	local warFill = make("Frame", {
		BackgroundColor3 = C.techCyan,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
	}, warTrack)
	local warTail = make("Frame", { -- the contested remainder, HD2's orange stub
		BackgroundColor3 = C.warning,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
	}, warTrack)

	local statRows = {}
	local function statRow(key: string, caption: string)
		local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 44) }, left)
		local cap = label(f, caption, 15, C.textSecondary)
		cap.Size = UDim2.new(1, 0, 0, 18)
		local val = label(f, "", 22, C.textPrimary, true)
		val.Position = UDim2.fromOffset(0, 18)
		val.Size = UDim2.new(1, 0, 0, 26)
		statRows[key] = { frame = f, val = val }
	end
	statRow("online", "Operators Online")
	statRow("wins", "Operations Won")
	statRow("losses", "Operations Lost")

	-- sector card
	local card = make("ScrollingFrame", {
		Name = "SectorCard",
		BackgroundColor3 = CARD,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.warning,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, canvas)
	stroke(card, C.warning, 2, 0)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
	}, card)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, card)

	local function cardRow(order: number, height: number): Frame
		return make("Frame", { BackgroundTransparency = 1, LayoutOrder = order, Size = UDim2.new(1, 0, 0, height) }, card)
	end
	local nameText = label(cardRow(1, 26), "", 22, C.warning, true)
	nameText.Size = UDim2.fromScale(1, 1)
	local statusText = label(cardRow(2, 18), "", 13, C.steel, true)
	statusText.Size = UDim2.fromScale(1, 1)
	local libRow = cardRow(3, 36)
	local libText = label(libRow, "", 16, C.textPrimary, true)
	libText.Size = UDim2.new(1, 0, 0, 20)
	local libTrack = make("Frame", {
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 7),
	}, libRow)
	stroke(libTrack, C.border, 1, 0.5)
	local libFill = make("Frame", { BackgroundColor3 = C.steel, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0) }, libTrack)
	make("Frame", {
		BackgroundColor3 = C.textSecondary,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 1, 1, 0),
		ZIndex = 2,
	}, libTrack)
	local forceText = label(cardRow(4, 16), "", 13, C.textSecondary)
	forceText.Size = UDim2.fromScale(1, 1)
	local biomeText = label(cardRow(5, 16), "", 13, C.textSecondary)
	biomeText.Size = UDim2.fromScale(1, 1)
	local opsHeaderText = label(cardRow(7, 22), "OPERATIONS", 13, C.textAccent, true)
	opsHeaderText.Size = UDim2.fromScale(1, 1)
	opsHeaderText.Position = UDim2.fromOffset(0, 6)

	local opCards = {}

	-- player card + back (bottom left)
	local playerCard = make("Frame", { Name = "PlayerCard", BackgroundTransparency = 1 }, canvas)
	make("Frame", { BackgroundColor3 = C.warning, BorderSizePixel = 0, Size = UDim2.new(0, 3, 1, 0) }, playerCard)
	local playerName = label(playerCard, localPlayer and string.upper(localPlayer.DisplayName) or "OPERATOR", 18, C.textPrimary, true)
	playerName.Position = UDim2.fromOffset(14, 4)
	local playerRank = label(playerCard, "", 13, C.textSecondary)
	playerRank.Position = UDim2.fromOffset(14, 28)
	local backBtn = button(canvas, "ESC   BACK", 16)
	backBtn.TextXAlignment = Enum.TextXAlignment.Left
	make("UIPadding", { PaddingLeft = UDim.new(0, 14) }, backBtn)

	-- ------------------------------------------------------------ right column
	local right = make("Frame", { Name = "Right", BackgroundTransparency = 1 }, canvas)
	local tabSquads = button(right, "SQUADS", 16)
	local tabForm = button(right, "FORM", 16)
	local badgeCaption = label(right, "War status:", 14, C.warning, false, Enum.TextXAlignment.Right)
	local badge = make("Frame", { BackgroundColor3 = C.warning, BorderSizePixel = 0 }, right)
	local badgeText = label(badge, "", 14, CARD, true, Enum.TextXAlignment.Center)
	badgeText.Size = UDim2.fromScale(1, 1)
	local order = make("Frame", {
		Name = "CommandOrder",
		BackgroundColor3 = CARD,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
	}, right)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, order)
	local orderHead = make("Frame", {
		BackgroundColor3 = Color3.fromRGB(0x1A, 0x26, 0x32),
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 40),
	}, order)
	local orderIcon = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
	}, orderHead)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, orderIcon)
	stroke(orderIcon, C.textPrimary, 2, 0)
	make("Frame", {
		BackgroundColor3 = C.textPrimary,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
	}, orderIcon)
	local orderTitle = label(orderHead, "COMMAND ORDER", 20, C.textPrimary, true)
	orderTitle.Position = UDim2.fromOffset(46, 0)
	orderTitle.Size = UDim2.new(1, -56, 1, 0)
	local function orderPad(o)
		local f = make("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = o,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, order)
		make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, f)
		return f
	end
	local orderBody = orderPad(2)
	local orderText = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 15,
		TextColor3 = C.textPrimary,
		Font = T.font,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, orderBody)
	local orderOverview = orderPad(3)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, orderOverview)
	local overviewHead = label(orderOverview, "ORDER OVERVIEW", 14, C.danger, true)
	overviewHead.LayoutOrder = 1
	local objectiveHost = make("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, orderOverview)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, objectiveHost)
	local segHost = make("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 10),
	}, orderOverview)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2) }, segHost)
	local footHost = orderPad(4)
	local orderFoot = label(footHost, "", 13, C.textSecondary)
	orderFoot.Size = UDim2.new(1, 0, 0, 26)

	-- ------------------------------------------------------------ bottom centre
	local dock = make("Frame", { Name = "Dock", BackgroundTransparency = 1 }, canvas)
	local deployBtn = button(dock, "DEPLOY", 24)
	deployBtn:SetAttribute("primary", true)
	paintButton(deployBtn)
	deployBtn:FindFirstChildOfClass("UIStroke").Thickness = 2
	local diffPrev = button(dock, "<", 24)
	local diffNext = button(dock, ">", 24)
	local diffLabel = make("TextLabel", {
		BackgroundTransparency = 0.35,
		BackgroundColor3 = C.navy,
		BorderSizePixel = 0,
		Text = "",
		TextSize = 20,
		TextColor3 = C.textPrimary,
		Font = T.fontBold,
	}, dock)
	local modLine = label(dock, "", 14, C.textPrimary, false, Enum.TextXAlignment.Center)
	local statusLine = label(dock, "", 13, C.textSecondary, false, Enum.TextXAlignment.Center)
	local function setStatus(text: string, color: Color3?)
		statusLine.Text = text
		statusLine.TextColor3 = color or C.textSecondary
	end

	-- ------------------------------------------------------------ state -> visuals
	local function difficultyLocked(d: string): boolean
		return state.rank ~= nil and state.rank < (DIFFICULTY_RANK[d] or 1)
	end

	local function difficultyIndex(): number
		return table.find(DIFFICULTIES, state.difficulty) or 1
	end

	local function refreshDifficulty()
		-- a late profile push can lock the preselected tier; drop to the highest open one
		if difficultyLocked(state.difficulty) then
			for i = #DIFFICULTIES, 1, -1 do
				if not difficultyLocked(DIFFICULTIES[i]) then
					state.difficulty = DIFFICULTIES[i]
					break
				end
			end
		end
		local i = difficultyIndex()
		diffLabel.Text = string.format("%d - %s", i, string.upper(state.difficulty))
		diffPrev:SetAttribute("locked", i <= 1)
		diffNext:SetAttribute("locked", i >= #DIFFICULTIES or difficultyLocked(DIFFICULTIES[i + 1] or "Easy"))
		paintButton(diffPrev)
		paintButton(diffNext)
		playerRank.Text = state.rank and string.format("MILITARY RANK %d", state.rank) or "MILITARY RANK --"
	end

	local function updateCommitStatus()
		if state.committing then
			return
		end
		if state.operationId then
			setStatus(string.upper(string.format("%s — %s", opDisplayName(state.operationId), regionName(state.region))), C.warning)
		else
			setStatus("SELECT A SECTOR, THEN AN OPERATION", C.textSecondary)
		end
	end

	local function paintOpCards()
		for opId, oc in pairs(opCards) do
			local selected = opId == state.operationId
			oc.frame.BackgroundColor3 = selected and Color3.fromRGB(0x1E, 0x2A, 0x38) or Color3.fromRGB(0x0C, 0x12, 0x18)
			oc.stroke.Color = selected and C.warning or C.border
			oc.stroke.Transparency = selected and 0 or 0.4
			oc.stroke.Thickness = selected and 2 or 1
			oc.tag.Text = selected and "COMMITTED" or "COMMIT"
			oc.tag.TextColor3 = selected and C.warning or C.textSecondary
			oc.name.TextColor3 = selected and C.warning or C.textPrimary
		end
	end

	local function selectOperation(opId: string)
		if state.committing then
			return
		end
		state.operationId = opId
		paintOpCards()
		updateCommitStatus()
	end

	local function buildOpCards()
		for _, oc in pairs(opCards) do
			oc.frame:Destroy()
		end
		opCards = {}
		local list = {}
		for opId, def in pairs(WarModel.OPERATIONS) do
			if def.region == state.region then
				table.insert(list, opId)
			end
		end
		table.sort(list)
		for i, opId in ipairs(list) do
			local def = WarModel.OPERATIONS[opId]
			local fam = def.family or "Operation"
			local famColor = FAMILY_COLOR[fam] or C.steel
			local frame = make("TextButton", {
				Name = "Op_" .. opId,
				AutoButtonColor = false,
				Text = "",
				BackgroundColor3 = C.panelInset,
				BorderSizePixel = 0,
				LayoutOrder = 10 + i,
				Size = UDim2.new(1, 0, 0, 56),
			}, card)
			local st = stroke(frame, C.border, 1, 0.4)
			make("Frame", { BackgroundColor3 = famColor, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0) }, frame)
			local name = label(frame, string.upper(opDisplayName(opId)), 16, C.textPrimary, true)
			name.Position = UDim2.fromOffset(14, 7)
			name.Size = UDim2.new(1, -110, 0, 20)
			local tmpl = WarOperations.TemplateFor and WarOperations.TemplateFor[opId]
			local sub = label(frame, string.upper(fam) .. (type(tmpl) == "string" and (" · " .. prettyId(tmpl)) or ""), 12, famColor)
			sub.Position = UDim2.fromOffset(14, 31)
			sub.Size = UDim2.new(1, -110, 0, 16)
			local tag = label(frame, "COMMIT", 12, C.textSecondary, true, Enum.TextXAlignment.Right)
			tag.AnchorPoint = Vector2.new(1, 0.5)
			tag.Position = UDim2.new(1, -10, 0.5, 0)
			tag.Size = UDim2.fromOffset(96, 16)
			opCards[opId] = { frame = frame, stroke = st, name = name, tag = tag }
			frame.MouseEnter:Connect(function()
				if opId ~= state.operationId then
					st.Color = C.techCyan
					st.Transparency = 0.1
				end
			end)
			frame.MouseLeave:Connect(paintOpCards)
			frame.Activated:Connect(function()
				selectOperation(opId)
			end)
		end
		paintOpCards()
	end

	local function overallControl(): number?
		local sum, n = 0, 0
		for _, info in pairs(state.infos) do
			if info.control then
				sum += info.control
				n += 1
			end
		end
		return n > 0 and sum / n or nil
	end

	local function paintNodes()
		for rid, n in pairs(nodes) do
			local info = state.infos[rid]
			if info then
				local col = statusColor(info.status)
				local selected = rid == state.region
				n.discStroke.Color = selected and C.accentSelect or col
				n.discStroke.Thickness = selected and 3 or 2
				n.innerStroke.Color = col
				n.zone.BackgroundColor3 = col
				n.zone.BackgroundTransparency = selected and 0.86 or (info.front and 0.9 or 0.94)
				n.zoneStroke.Color = col
				n.zoneStroke.Transparency = selected and 0.55 or 0.82
				n.barFill.BackgroundColor3 = col
				n.barFill.Size = UDim2.new(info.control or 0, 0, 1, 0)
					n.selRing.Visible = selected
				n.termRing.Visible = state.terminal[rid] == true and not selected
				n.frontRing.Visible = info.front
				n.nameLabel.TextColor3 = selected and C.warning or C.textPrimary
			end
		end
	end

	local function paintPanel()
		local info = state.infos[state.region]
		if not info then
			return
		end
		local col = statusColor(info.status)
		local pct = info.control and math.floor(info.control * 100 + 0.5) or nil
		nameText.Text = regionName(state.region)
		statusText.Text = (STATUS_TEXT[info.status] or prettyId(info.status)) .. (info.front and "  ·  ACTIVE FRONT" or "")
		statusText.TextColor3 = col
		libText.Text = pct and "LIBERATION" or "AWAITING TELEMETRY"
		libFill.BackgroundColor3 = col
		libFill.Size = UDim2.new(info.control or 0, 0, 1, 0)
		if info.H and info.E then
			forceText.Text = string.format("FORCE BALANCE  GF %.2f · ASC %.2f", info.H, info.E)
		else
			forceText.Text = "FORCE BALANCE  NO SNAPSHOT"
		end
		local biome = biomeOf(state.region)
		local terr = WarModel.TERRITORIES[state.region]
		biomeText.Text = string.format("%s · INDUSTRY %d%%", BIOME_NAMES[biome] or "UNKNOWN", math.floor(((terr and terr.industrial) or 0) * 100 + 0.5))
		modLine.Text = table.concat(BIOME_CONDITIONS[biome] or {}, "  •  ")
	end

	local function paintLanes()
		for _, e in ipairs(edges) do
			local ia, ib = state.infos[e.a], state.infos[e.b]
			local touchesSel = e.a == state.region or e.b == state.region
			local frontLane = (ia and ia.front) or (ib and ib.front)
			if touchesSel then
				e.line.BackgroundColor3 = C.techCyan
				e.line.BackgroundTransparency = 0.15
				e.pulse.BackgroundColor3 = C.techCyan
			elseif frontLane then
				e.line.BackgroundColor3 = C.warning
				e.line.BackgroundTransparency = 0.45
				e.pulse.BackgroundColor3 = C.warning
			else
				e.line.BackgroundColor3 = C.steel
				e.line.BackgroundTransparency = 0.7
				e.pulse.BackgroundColor3 = C.steel
			end
		end
	end

	local function rebuildObjectives(fronts)
		for _, c in ipairs(objectiveHost:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for _, c in ipairs(segHost:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if #fronts == 0 then
			make("TextLabel", {
				BackgroundTransparency = 1,
				Text = "No active fronts. Hold the line.",
				TextSize = 15, TextColor3 = C.textSecondary, Font = T.font,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, 0, 0, 20),
			}, objectiveHost)
			return
		end
		for i, f in ipairs(fronts) do
			local secured = f.control ~= nil and f.control >= 0.5
			local row = make("Frame", { BackgroundTransparency = 1, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 22) }, objectiveHost)
			make("TextLabel", {
				BackgroundTransparency = 1,
				RichText = true,
				Text = string.format('Liberate <font color="%s">%s</font>', hex(C.warning), regionName(f.rid)),
				TextSize = 15, TextColor3 = C.textPrimary, Font = T.font,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1, -30, 1, 0),
			}, row)
			local box = make("Frame", {
				BackgroundColor3 = secured and C.success or C.panel,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Size = UDim2.fromOffset(16, 16),
			}, row)
			stroke(box, C.steel, 1, 0.3)
			make("Frame", {
				BackgroundColor3 = secured and C.success or C.techCyan,
				BorderSizePixel = 0,
				Size = UDim2.new(1 / #fronts, -2, 1, 0),
			}, segHost)
		end
	end

	local function paintBanner()
		local sector = workspace:GetAttribute("GF_WarSector")
		local wstatus = workspace:GetAttribute("GF_WarStatus")
		local wins = tonumber(workspace:GetAttribute("GF_WarWins")) or 0
		local losses = tonumber(workspace:GetAttribute("GF_WarLosses")) or 0
		local statusStr = type(wstatus) == "string" and wstatus ~= "" and string.upper(wstatus) or "UNKNOWN"
		warSub.Text = statusStr
		local ov = overallControl()
		local held, total = 0, 0
		for _, info in pairs(state.infos) do
			if info.control then
				total += 1
				if info.control >= 0.5 then held += 1 end
			end
		end
		warLib.Text = total > 0 and string.format("%d OF %d REGIONS SECURED", held, total) or "AWAITING TELEMETRY"
		warFill.Size = UDim2.new(ov or 0, 0, 1, 0)
		warTail.Position = UDim2.new(ov or 0, 0, 0, 0)
		warTail.Size = UDim2.new(math.min(0.08, 1 - (ov or 0)), 0, 1, 0)
		statRows.online.val.Text = tostring(#Players:GetPlayers())
		statRows.wins.val.Text = tostring(wins)
		statRows.losses.val.Text = tostring(losses)
		badgeText.Text = statusStr
		orderText.Text = type(sector) == "string" and sector ~= "" and sector or "Hold the line across every active front."
		orderFoot.Text = string.format("WINS %d · LOSSES %d", wins, losses)
		-- objectives = the active fronts; rebuild only when the set or its secured state changes
		local fronts, sig = {}, {}
		for _, rid in ipairs(REGION_ORDER) do
			local info = state.infos[rid]
			if info and info.front then
				table.insert(fronts, info)
				table.insert(sig, rid .. (info.control and info.control >= 0.5 and "1" or "0"))
			end
		end
		local sigStr = table.concat(sig, ",")
		if sigStr ~= state.fronts then
			state.fronts = sigStr
			rebuildObjectives(fronts)
		end
	end

	local function readData()
		state.territories = parseTerritories()
		for _, rid in ipairs(REGION_ORDER) do
			state.infos[rid] = regionInfo(rid, state.territories)
		end
	end

	local function refreshAll()
		readData()
		paintBanner()
		paintNodes()
		paintLanes()
		paintPanel()
	end

	local function selectRegion(rid: string, autoOp: boolean?)
		if state.committing or not WarModel.TERRITORIES[rid] then
			return
		end
		state.region = rid
		state.operationId = nil
		buildOpCards()
		refreshAll()
		if autoOp ~= false then
			-- one fewer click: the first operation is pre-committed (DEPLOY is still explicit)
			local firstId = nil
			for opId in pairs(opCards) do
				if not firstId or opId < firstId then
					firstId = opId
				end
			end
			if firstId then
				selectOperation(firstId)
			end
		end
		updateCommitStatus()
	end

	-- ------------------------------------------------------------ layout
	local function placeMap(R: number)
		local centers = {}
		-- angular plates: wide enough for the region name to live inside, compact enough
		-- that seven of them ring the planet without crowding (owner: "a little cramped")
		local pw = math.clamp(math.floor(R * 0.42), 100, 140)
		local ph = 38
		local d = pw / 2 -- contract: tooltip offset math treats d as the node half-width scale
		for rid, n in pairs(nodes) do
			local pol = POLAR[rid]
			local a = math.rad(pol[1])
			local cx = R + math.sin(a) * pol[2] * R
			local cy = R - math.cos(a) * pol[2] * R
			centers[rid] = Vector2.new(cx, cy)
			n.cx, n.cy, n.d = cx, cy, d
			n.zone.Position = UDim2.fromOffset(cx, cy)
			n.zone.Size = UDim2.fromOffset(pw * 0.95, pw * 0.95)
			n.hit.Position = UDim2.fromOffset(cx, cy)
			n.hit.Size = UDim2.fromOffset(math.max(pw + 8, 52 / state.scale), math.max(ph + 8, 52 / state.scale))
			n.disc.Size = UDim2.fromOffset(pw, ph)
			n.selRing.Size = UDim2.fromOffset(pw + 8, ph + 8)
			n.selRing.Position = UDim2.new(0.5, 0, 0.5, 0)
			n.termRing.Size = UDim2.fromOffset(pw + 14, ph + 14)
			n.termRing.Position = UDim2.new(0.5, 0, 0.5, 0)
		end
		for _, e in ipairs(edges) do
			local a, b = centers[e.a], centers[e.b]
			if a and b then
				local delta = b - a
				e.ax, e.ay, e.bx, e.by = a.X, a.Y, b.X, b.Y
				e.line.Size = UDim2.fromOffset(delta.Magnitude, 2)
				e.line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
				e.line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
			end
		end
	end

	local function layout()
		local W, H = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
		if W < 200 or H < 150 then
			return
		end
		local s = math.clamp(math.min(W / 1280, H / 720), 0.5, 2)
		local vx, vy = W / s, H / s
		state.scale, state.vx, state.vy = s, vx, vy
		uiScale.Scale = s
		canvas.Size = UDim2.fromOffset(vx, vy)
		local compact = vy < 560
		local m = compact and 16 or 28

		-- left column
		local lw = math.clamp(vx * 0.24, 290, 400)
		left.Position = UDim2.fromOffset(m, m)
		left.Size = UDim2.fromOffset(lw, 100)
		titleText.Size = UDim2.fromOffset(lw - 54, 34)
		warSub.Size = UDim2.fromOffset(lw - 54, 20)
		warLib.Size = UDim2.fromOffset(lw - 54, 20)
		warTrack.Size = UDim2.fromOffset(lw - 54, 6)
		local statsY = 100
		local statsH = 0
		for _, sr in pairs(statRows) do
			sr.frame.Visible = not compact
		end
		if not compact then
			local y = statsY
			for _, key in ipairs({ "online", "wins", "losses" }) do
				local sr = statRows[key]
				sr.frame.Position = UDim2.fromOffset(54, y)
				sr.frame.Size = UDim2.fromOffset(lw - 54, 44)
				y += 44
			end
			statsH = y - statsY + 6
		end
		local backH = 52
		local playerH = 50
		local bottomReserve = backH + 10 + (compact and 0 or (playerH + 10))
		local cardY = m + statsY + statsH
		local cardBottom = vy - m - bottomReserve
		card.Position = UDim2.fromOffset(m, cardY)
		card.Size = UDim2.fromOffset(lw, math.max(120, cardBottom - cardY))
		backBtn.Position = UDim2.fromOffset(m, vy - m - backH)
		backBtn.Size = UDim2.fromOffset(150, backH)
		playerCard.Visible = not compact
		playerCard.Position = UDim2.fromOffset(m, vy - m - backH - 10 - playerH)
		playerCard.Size = UDim2.fromOffset(lw, playerH)

		-- right column
		local rw = math.clamp(vx * 0.27, 300, 380)
		right.Position = UDim2.fromOffset(vx - m - rw, m)
		right.Size = UDim2.fromOffset(rw, 100)
		local tabW = math.floor((rw - 6) / 2)
		tabSquads.Position = UDim2.fromOffset(0, 0)
		tabSquads.Size = UDim2.fromOffset(tabW, 52)
		tabForm.Position = UDim2.fromOffset(tabW + 6, 0)
		tabForm.Size = UDim2.fromOffset(tabW, 52)
		badgeCaption.Position = UDim2.fromOffset(0, 62)
		badgeCaption.Size = UDim2.fromOffset(rw - 170, 22)
		badge.Position = UDim2.fromOffset(rw - 164, 62)
		badge.Size = UDim2.fromOffset(164, 22)
		order.Position = UDim2.fromOffset(0, 94)
		order.Size = UDim2.fromOffset(rw, 0)

		-- bottom centre dock
		local cw = math.clamp(vx * 0.34, 360, 480)
		local dockH = 162
		dock.Position = UDim2.fromOffset(vx / 2 - cw / 2, vy - m - dockH)
		dock.Size = UDim2.fromOffset(cw, dockH)
		deployBtn.Position = UDim2.fromOffset(0, 0)
		deployBtn.Size = UDim2.fromOffset(cw, 52)
		local arrowW = 52
		diffPrev.Position = UDim2.fromOffset(0, 62)
		diffPrev.Size = UDim2.fromOffset(arrowW, 52)
		diffNext.Position = UDim2.fromOffset(cw - arrowW, 62)
		diffNext.Size = UDim2.fromOffset(arrowW, 52)
		diffLabel.Position = UDim2.fromOffset(arrowW + 4, 62)
		diffLabel.Size = UDim2.fromOffset(cw - arrowW * 2 - 8, 52)
		modLine.Position = UDim2.fromOffset(0, 120)
		modLine.Size = UDim2.fromOffset(cw, 18)
		statusLine.Position = UDim2.fromOffset(0, 142)
		statusLine.Size = UDim2.fromOffset(cw, 18)

		-- map stage: between the columns, above the dock
		local cx = vx / 2
		local R = math.clamp(math.min((vy - dockH - m * 2) / 2 * 1.02, (vx / 2) - (m + lw) - 12), 110, 700)
		local cy = m + R + 4
		stage.Position = UDim2.fromOffset(cx - R, cy - R)
		stage.Size = UDim2.fromOffset(R * 2, R * 2)
		placeMap(R)
	end

	-- ------------------------------------------------------------ interaction
	backBtn.Activated:Connect(function()
		if shell and shell.close then
			shell:close()
		end
	end)
	local function gotoSection(name: string)
		if shell and shell.setActive then
			shell:setActive(name)
		elseif shell and shell.select then
			shell:select(name)
		end
	end
	tabSquads.Activated:Connect(function()
		gotoSection("SQUADS")
	end)
	tabForm.Activated:Connect(function()
		gotoSection("FORM")
	end)

	local function stepDifficulty(dir: number)
		if state.committing then
			return
		end
		local nextD = DIFFICULTIES[difficultyIndex() + dir]
		if not nextD then
			return
		end
		if difficultyLocked(nextD) then
			setStatus(string.upper(string.format("%s locked — requires military rank %d", nextD, DIFFICULTY_RANK[nextD] or 1)), C.warning)
			return
		end
		state.difficulty = nextD
		refreshDifficulty()
		updateCommitStatus()
	end
	diffPrev.Activated:Connect(function()
		stepDifficulty(-1)
	end)
	diffNext.Activated:Connect(function()
		stepDifficulty(1)
	end)

	local function setDeployState(vstate: string?, text: string)
		deployBtn:SetAttribute("vstate", vstate)
		deployBtn.Text = text
		deployBtn.Active = vstate ~= "pending" and vstate ~= "accepted"
		paintButton(deployBtn)
	end

	local function armDeploy()
		state.committing = false
		setDeployState(nil, "DEPLOY")
		updateCommitStatus()
	end

	deployBtn.Activated:Connect(function()
		if state.committing then
			return
		end
		if not state.operationId then
			setStatus("SELECT AN OPERATION BEFORE DEPLOYMENT", C.warning)
			return
		end
		if difficultyLocked(state.difficulty) then
			setStatus(string.upper(string.format("%s locked — requires military rank %d",
				state.difficulty, DIFFICULTY_RANK[state.difficulty] or 1)), C.warning)
			return
		end
		if not remotes then
			setStatus("DEPLOYMENT UNAVAILABLE — NO COMMAND LINK", C.danger)
			return
		end
		state.commitToken += 1
		local token = state.commitToken
		state.committing = true
		setDeployState("pending", "DEPLOYING…")
		setStatus("DEPLOYMENT ORDER TRANSMITTED — AWAITING COMMAND CONFIRMATION", C.warning)
		remotes.RequestDeploy:FireServer({
			difficulty = state.difficulty,
			operationId = state.operationId,
		})
		-- watchdog only: command normally answers through DeployStateChanged. If it never does,
		-- leave the screen open and re-arm rather than faking success.
		task.delay(8, function()
			if state.committing and state.commitToken == token then
				state.committing = false
				setDeployState("refused", "NO RESPONSE — RETRY")
				setStatus("NO RESPONSE FROM COMMAND — DEPLOYMENT UNCONFIRMED", C.warning)
			end
		end)
	end)

	-- honest verdicts. zone publications use the same remote but carry no boolean ok, so they are
	-- ignored; only verdicts while this screen has a pending commit apply.
	if remotes then
		task.spawn(function()
			local ev = remotes:WaitForChild("DeployStateChanged", 30)
			if not (ev and ev:IsA("RemoteEvent")) then
				return
			end
			track(ev.OnClientEvent:Connect(function(payload)
				if type(payload) ~= "table" or type(payload.ok) ~= "boolean" or not state.committing then
					return
				end
				if payload.ok then
					local token = state.commitToken
					setDeployState("accepted", "DEPLOYMENT ACCEPTED")
					setStatus("LAUNCH CONFIRMED — GOOD HUNTING", C.success)
					task.delay(0.8, function()
						if state.commitToken == token then
							if shell and shell.visible then
								shell:close()
							end
							armDeploy()
						end
					end)
				else
					state.committing = false
					setDeployState("refused", "REFUSED — RETRY")
					setStatus("DEPLOYMENT REFUSED — " .. tostring(payload.reason or "unknown reason"), C.danger)
				end
			end))
		end)

		local pu = remotes:FindFirstChild("ProfileUpdated")
		if pu and pu:IsA("RemoteEvent") then
			track(pu.OnClientEvent:Connect(function(payload)
				if type(payload) == "table" and type(payload.rank) == "number" then
					state.rank = math.max(1, math.floor(payload.rank))
					refreshDifficulty()
				end
			end))
		end
	end
	if localPlayer then
		local function applyRankAttr()
			local rank = localPlayer:GetAttribute("GF_Rank")
			if type(rank) == "number" then
				state.rank = math.max(1, math.floor(rank))
				refreshDifficulty()
			end
		end
		applyRankAttr()
		track(localPlayer:GetAttributeChangedSignal("GF_Rank"):Connect(applyRankAttr))
	end

	-- node input + hover card
	local function showTooltip(rid: string)
		local n, info = nodes[rid], state.infos[rid]
		if not (n and info) then
			return
		end
		ttName.Text = regionName(rid)
		ttStatus.Text = STATUS_TEXT[info.status] or prettyId(info.status)
		ttStatus.TextColor3 = statusColor(info.status)
		ttFill.BackgroundColor3 = statusColor(info.status)
		ttFill.Size = UDim2.new(info.control or 0, 0, 1, 0)
		ttPct.Text = (info.H and info.E) and string.format("GF %.2f  ·  ASC %.2f", info.H, info.E) or "NO FORCE SNAPSHOT"
		local sp = stage.Position
		local x = sp.X.Offset + n.cx + n.d + 14 -- d is the plate half-width in the angular layout
		local y = sp.Y.Offset + n.cy - 84 - 24
		x = math.clamp(x, 8, state.vx - 218)
		y = math.clamp(y, 8, state.vy - 92)
		tooltip.Position = UDim2.fromOffset(x, y)
		tooltip.Visible = true
	end
	for rid, n in pairs(nodes) do
		n.hit.Activated:Connect(function()
			selectRegion(rid)
		end)
		n.hit.MouseEnter:Connect(function()
			showTooltip(rid)
		end)
		n.hit.MouseLeave:Connect(function()
			tooltip.Visible = false
		end)
	end

	-- terminal arc preselection: the proximity loop writes shell._terminalRegions ("A,B")
	local function applyTerminal()
		state.terminal = {}
		local raw = shell and shell._terminalRegions
		local first = nil
		if type(raw) == "string" then
			for rid in raw:gmatch("[^,%s]+") do
				if WarModel.TERRITORIES[rid] then
					state.terminal[rid] = true
					first = first or rid
				end
			end
		end
		return first
	end

	-- ------------------------------------------------------------ live loop
	track(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	track(RunService.RenderStepped:Connect(function()
		local visible = page.Visible and page:IsDescendantOf(game) and (shell == nil or shell.visible)
		if gui.Enabled ~= visible then
			gui.Enabled = visible
		end
		if not visible then
			state.wasVisible = false
			tooltip.Visible = false
			return
		end
		local now = os.clock()
		if not state.wasVisible then
			-- just opened: lay out, preselect the terminal's first region, repaint everything
			state.wasVisible = true
			layout()
			local first = applyTerminal()
			if first and not state.committing then
				selectRegion(first)
			else
				refreshAll()
			end
		elseif now - state.lastRefresh > 0.5 then
			state.lastRefresh = now
			refreshAll()
		end
		for _, e in ipairs(edges) do
			local t = (now * e.speed + e.phase) % 1
			e.pulse.Position = UDim2.fromOffset(e.ax + (e.bx - e.ax) * t, e.ay + (e.by - e.ay) * t)
		end
		local beat = (math.sin(now * 2.4) + 1) / 2
		for rid, n in pairs(nodes) do
			local info = state.infos[rid]
			if info and info.front then
				n.frontStroke.Transparency = 0.2 + 0.55 * beat
			end
		end
	end))

	-- ------------------------------------------------------------ initial build
	buildOpCards()
	refreshDifficulty()
	setDeployState(nil, "DEPLOY")
	refreshAll()
	selectRegion(state.region)

	local controller = {}
	controller.gui = gui
	controller.refresh = refreshAll
	controller.selectRegion = selectRegion
	controller.layout = layout
	controller.getState = function()
		return state
	end
	controller.destroy = function()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		gui:Destroy()
	end
	return controller
end

return GalaxyMap
