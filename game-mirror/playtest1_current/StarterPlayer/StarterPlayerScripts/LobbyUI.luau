--!nonstrict
-- LobbyUI — the station's persistent interface shell. Until now the lobby showed nothing but
-- health bars: no rank, no currencies, no navigation, no loadout — owner review versus the
-- reference lobby: "you see how shit our ui looks rn". This is the always-on lobby chrome:
-- rank plate, currency counters, nav rail into the menu surfaces, loadout strip, theater
-- status panel. angular amber-on-dark language per the owner-approved art spec (Tokens).
--
-- mission-only inverse of HUD.luau's combat chrome: everything here hides the moment
-- GF_InMission is set, and everything hides while a full-screen menu owns the display.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tokens = require(ReplicatedStorage.GF.Shared.UI.Tokens)
local Economy = require(ReplicatedStorage.GF.Shared.Configs.Economy)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")

local gui = Instance.new("ScreenGui")
gui.Name = "GF_LobbyUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 3
gui.Enabled = true
gui.Parent = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------
-- palette — derived from Tokens, tuned for the reference's amber-on-navy read.
-- ---------------------------------------------------------------------------
local C = Tokens.Color
local AMBER = C.accentSelect            -- #D8A858 committed/interactive accent
local CYAN = C.techCyan
local PANEL = Color3.fromRGB(0x0C, 0x12, 0x1A)
local PANEL_HI = Color3.fromRGB(0x14, 0x1D, 0x28)
local EDGE = C.border
local TEXT = C.ceramic
local TEXT_DIM = Color3.fromRGB(0x8E, 0x9B, 0xA8)

local FONT = Tokens.Type.font
local FONT_B = Tokens.Type.fontBold

-- ---------------------------------------------------------------------------
-- angular plate chrome: quiet navy ground, steel border, amber edge rail, and the
-- signature chamfer — a rotated corner square that reads as a cut corner at distance.
-- ---------------------------------------------------------------------------
local function chamfer(parent: Instance, cornerX: number, cornerY: number, color: Color3?)
	local ch = Instance.new("Frame")
	ch.Name = "Chamfer"
	ch.Size = UDim2.fromOffset(10, 2)
	ch.Rotation = 45
	ch.AnchorPoint = Vector2.new(0.5, 0.5)
	ch.Position = UDim2.new(cornerX, cornerX == 1 and -4 or 4, cornerY, cornerY == 1 and -4 or 4)
	ch.BackgroundColor3 = color or AMBER
	ch.BorderSizePixel = 0
	ch.Parent = parent
	return ch
end

local function plate(parent: Instance, name: string, size: UDim2, pos: UDim2, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor or Vector2.new(0, 0)
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.12
	f.BorderSizePixel = 0
	f.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = EDGE
	stroke.Transparency = 0.35
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f

	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.Size = UDim2.new(0, 3, 1, -10)
	rail.Position = UDim2.new(0, 0, 0, 5)
	rail.BackgroundColor3 = AMBER
	rail.BorderSizePixel = 0
	rail.Parent = f

	chamfer(f, 1, 0)
	return f
end

local function caption(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3?, textSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Text = text
	l.Font = FONT_B
	l.TextSize = textSize or 11
	l.TextColor3 = color or TEXT_DIM
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

-- ---------------------------------------------------------------------------
-- visibility: lobby-only chrome. hidden in missions, hidden while a menu owns the screen.
-- ---------------------------------------------------------------------------
local root = Instance.new("Frame")
root.Name = "LobbyRoot"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = gui

local function computeVisible()
	local inMission = workspace:GetAttribute("GF_InMission") == true
	local menuOpen = workspace:GetAttribute("GF_UIOpen") == true
	root.Visible = not inMission and not menuOpen
end
workspace:GetAttributeChangedSignal("GF_InMission"):Connect(computeVisible)
workspace:GetAttributeChangedSignal("GF_UIOpen"):Connect(computeVisible)
computeVisible()

-- ---------------------------------------------------------------------------
-- rank plate (top-left, below the health cluster): rank number, xp bar, progress text.
-- ---------------------------------------------------------------------------
local rankPlate = plate(root, "RankPlate", UDim2.fromOffset(210, 64), UDim2.fromOffset(28, 70))
caption(rankPlate, "RANK", UDim2.fromOffset(60, 14), UDim2.fromOffset(14, 8), TEXT_DIM, 10)
local rankNumber = caption(rankPlate, "--", UDim2.fromOffset(70, 34), UDim2.fromOffset(14, 20), TEXT, 28)
rankNumber.Font = FONT_B

-- chevron mark — three stacked amber ticks, the rank-insignia read
for i = 0, 2 do
	local tick = Instance.new("Frame")
	tick.Size = UDim2.fromOffset(16, 3)
	tick.Position = UDim2.fromOffset(96, 16 + i * 7)
	tick.Rotation = -24
	tick.BackgroundColor3 = AMBER
	tick.BorderSizePixel = 0
	tick.Parent = rankPlate
end

local xpBarBg = Instance.new("Frame")
xpBarBg.Size = UDim2.new(1, -28, 0, 5)
xpBarBg.Position = UDim2.new(0, 14, 1, -22)
xpBarBg.BackgroundColor3 = PANEL_HI
xpBarBg.BorderSizePixel = 0
xpBarBg.Parent = rankPlate
local xpFill = Instance.new("Frame")
xpFill.Size = UDim2.fromScale(0, 1)
xpFill.BackgroundColor3 = AMBER
xpFill.BorderSizePixel = 0
xpFill.Parent = xpBarBg
local xpText = caption(rankPlate, "", UDim2.new(1, -28, 0, 12), UDim2.new(0, 14, 1, -16), TEXT_DIM, 9)

local cachedRank, cachedXp = nil, nil
local function refreshRank()
	local rank = player:GetAttribute("GF_Rank") or cachedRank
	local xp = player:GetAttribute("GF_XP") or cachedXp
	if type(rank) == "number" then
		rankNumber.Text = tostring(math.floor(rank))
		if type(xp) == "number" and Economy.RankXp then
			local cur = Economy.RankXp[math.floor(rank)] or 0
			local nxt = Economy.RankXp[math.floor(rank) + 1]
			if nxt and nxt > cur then
				local frac = math.clamp((xp - cur) / (nxt - cur), 0, 1)
				xpFill.Size = UDim2.fromScale(frac, 1)
				xpText.Text = string.format("%d / %d XP", math.floor(math.max(0, xp - cur)), math.floor(nxt - cur))
			else
				xpFill.Size = UDim2.fromScale(1, 1)
				xpText.Text = "MAX RANK"
			end
		end
	end
end
player:GetAttributeChangedSignal("GF_Rank"):Connect(refreshRank)
player:GetAttributeChangedSignal("GF_XP"):Connect(refreshRank)
local profileUpdated = remotes:FindFirstChild("ProfileUpdated")
if profileUpdated and profileUpdated:IsA("RemoteEvent") then
	profileUpdated.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			if type(payload.rank) == "number" then cachedRank = payload.rank end
			if type(payload.xp) == "number" then cachedXp = payload.xp end
			refreshRank()
		end
	end)
end
refreshRank()

-- ---------------------------------------------------------------------------
-- currency plates (top-right): credits and scrap, angular counters.
-- ---------------------------------------------------------------------------
local function currencyPlate(name: string, xOffset: number, label: string, icon: string)
	local p = plate(root, name, UDim2.fromOffset(150, 40), UDim2.new(1, xOffset, 0, 14), Vector2.new(1, 0))
	local ic = caption(p, icon, UDim2.fromOffset(24, 40), UDim2.fromOffset(14, 0), AMBER, 16)
	ic.TextYAlignment = Enum.TextYAlignment.Center
	caption(p, label, UDim2.fromOffset(100, 12), UDim2.fromOffset(38, 6), TEXT_DIM, 9)
	local val = caption(p, "0", UDim2.fromOffset(100, 20), UDim2.fromOffset(38, 16), TEXT, 17)
	val.Font = FONT_B
	return val
end
local creditsVal = currencyPlate("CreditsPlate", -150, "CREDITS", "$")
local scrapVal = currencyPlate("ScrapPlate", -310, "SCRAP", "S")

local function refreshCurrencies()
	creditsVal.Text = tostring(math.floor(player:GetAttribute("GF_Credits") or 0))
	scrapVal.Text = tostring(math.floor(player:GetAttribute("GF_Scrap") or 0))
end
player:GetAttributeChangedSignal("GF_Credits"):Connect(refreshCurrencies)
player:GetAttributeChangedSignal("GF_Scrap"):Connect(refreshCurrencies)
refreshCurrencies()

-- ---------------------------------------------------------------------------
-- nav rail (left edge, vertically centered): the way into every menu surface.
-- angular buttons, amber chevron, hover lift.
-- ---------------------------------------------------------------------------
local rail = Instance.new("Frame")
rail.Name = "NavRail"
rail.Size = UDim2.fromOffset(190, 260)
rail.Position = UDim2.new(0, 16, 0.5, -130)
rail.BackgroundTransparency = 1
rail.Parent = root

local menuController = require(ReplicatedStorage.GF.Shared.UI.MenuController)

local navItems = {
	{ label = "DEPLOY", detail = "war table · mission select", action = function()
		menuController.open("WAR TABLE")
	end },
	{ label = "ARMORY", detail = "weapons · armor · equip", action = function()
		workspace:SetAttribute("GF_ArmoryOpen", true)
	end },
	{ label = "SQUAD", detail = "form · join · manage", action = function()
		menuController.open("SQUADS")
	end },
	{ label = "LOADOUT", detail = "saved kits · augments", action = function()
		workspace:SetAttribute("GF_ArmoryOpen", true)
	end },
}

for i, item in ipairs(navItems) do
	local btn = Instance.new("TextButton")
	btn.Name = "Nav_" .. item.label
	btn.Size = UDim2.fromOffset(190, 52)
	btn.Position = UDim2.fromOffset(0, (i - 1) * 60)
	btn.BackgroundColor3 = PANEL
	btn.BackgroundTransparency = 0.12
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.Parent = rail

	local stroke = Instance.new("UIStroke")
	stroke.Color = EDGE
	stroke.Transparency = 0.35
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = btn

	local btnRail = Instance.new("Frame")
	btnRail.Size = UDim2.new(0, 3, 1, -10)
	btnRail.Position = UDim2.new(0, 0, 0, 5)
	btnRail.BackgroundColor3 = AMBER
	btnRail.BorderSizePixel = 0
	btnRail.Parent = btn

	local lbl = caption(btn, item.label, UDim2.new(1, -50, 0, 18), UDim2.fromOffset(16, 9), TEXT, 15)
	lbl.Font = FONT_B
	caption(btn, item.detail, UDim2.new(1, -50, 0, 12), UDim2.fromOffset(16, 29), TEXT_DIM, 9)

	local chev = caption(btn, ">", UDim2.fromOffset(20, 52), UDim2.new(1, -28, 0, 0), AMBER, 20)
	chev.TextXAlignment = Enum.TextXAlignment.Center
	chev.TextYAlignment = Enum.TextYAlignment.Center
	chamfer(btn, 1, 0)

	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = PANEL_HI
		stroke.Color = AMBER
		stroke.Transparency = 0.1
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = PANEL
		stroke.Color = EDGE
		stroke.Transparency = 0.35
	end)
	btn.Activated:Connect(function()
		item.action()
	end)
end

-- ---------------------------------------------------------------------------
-- theater status (right edge): the war at a glance — one row per territory with the
-- liberation tug bar. reads the same workspace attributes the galaxy map reads.
-- percentages are clamped — the pre-fix theater math once printed 9111%.
-- ---------------------------------------------------------------------------
local opsPanel = plate(root, "TheaterPanel", UDim2.fromOffset(240, 322), UDim2.new(1, -16, 0.5, -161), Vector2.new(1, 0.5))
caption(opsPanel, "VEYRA-7 THEATER", UDim2.fromOffset(200, 16), UDim2.fromOffset(16, 8), TEXT, 12).Font = FONT_B
local theaterState = caption(opsPanel, "", UDim2.fromOffset(200, 12), UDim2.fromOffset(16, 24), TEXT_DIM, 9)

local rowsContainer = Instance.new("Frame")
rowsContainer.Size = UDim2.new(1, -28, 1, -48)
rowsContainer.Position = UDim2.fromOffset(14, 40)
rowsContainer.BackgroundTransparency = 1
rowsContainer.Parent = opsPanel

local territoryRows = {}
local function rebuildRows()
	for _, r in ipairs(territoryRows) do r.frame:Destroy() end
	territoryRows = {}
	local ids = {}
	local attrs = workspace:GetAttributes()
	if attrs then
		for key, _ in pairs(attrs) do
			local rid = key:match("^GF_WarState_(.+)_Status$")
			if rid then
				table.insert(ids, rid)
			end
		end
	end
	table.sort(ids)
	for i, rid in ipairs(ids) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 30)
		row.Position = UDim2.fromOffset(0, (i - 1) * 34)
		row.BackgroundTransparency = 1
		row.Parent = rowsContainer
		local pretty = rid:gsub("_", " "):gsub("(%l)(%u)", "%1 %2"):upper()
		caption(row, pretty, UDim2.new(1, -40, 0, 12), UDim2.fromOffset(0, 0), TEXT, 9)
		local pct = caption(row, "", UDim2.fromOffset(40, 12), UDim2.new(1, -40, 0, 0), CYAN, 9)
		pct.TextXAlignment = Enum.TextXAlignment.Right
		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, 0, 0, 5)
		barBg.Position = UDim2.fromOffset(0, 17)
		barBg.BackgroundColor3 = Color3.fromRGB(0x6E, 0x3D, 0x2A) -- enemy hold: bronze-rust
		barBg.BorderSizePixel = 0
		barBg.Parent = row
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0.5, 1)
		fill.BackgroundColor3 = CYAN
		fill.BorderSizePixel = 0
		fill.Parent = barBg
		territoryRows[i] = { frame = row, fill = fill, pct = pct, rid = rid }
	end
end

local function refreshTheater()
	-- territory attributes replicate in over the first seconds — rescan whenever the live
	-- count differs from what the rows were built with, not just when empty (bug: the panel
	-- froze with only the first-arrived region)
	local liveCount = 0
	local attrs = workspace:GetAttributes()
	if attrs then
		for key, _ in pairs(attrs) do
			if key:match("^GF_WarState_(.+)_Status$") then liveCount = liveCount + 1 end
		end
	end
	if liveCount ~= #territoryRows then rebuildRows() end
	for _, row in ipairs(territoryRows) do
		-- liberation = GF force share H/(H+E) — the galaxy map's own math, clamped
		local H = tonumber(workspace:GetAttribute("GF_WarState_" .. row.rid .. "_H")) or 0
		local E = tonumber(workspace:GetAttribute("GF_WarState_" .. row.rid .. "_E")) or 0
		local frac = (H + E) > 0 and math.clamp(H / (H + E), 0, 1) or 0
		row.fill.Size = UDim2.fromScale(frac, 1)
		row.pct.Text = string.format("%d%%", math.floor(frac * 100 + 0.5))
	end
	local status = workspace:GetAttribute("GF_WarStatus") or workspace:GetAttribute("GF_WarTheaterStatus")
	theaterState.Text = type(status) == "string" and string.upper(status) or "ASCENDANCY HOLDING"
end

task.spawn(function()
	while gui.Parent do
		refreshTheater()
		task.wait(3)
	end
end)

-- ---------------------------------------------------------------------------
-- pod seats: stepping into a drop pod is the physical front door of the deploy loop.
-- the server seats the operator (GF_PodIndex); the seat opens the war table.
-- ---------------------------------------------------------------------------
player:GetAttributeChangedSignal("GF_PodIndex"):Connect(function()
	local idx = player:GetAttribute("GF_PodIndex")
	if type(idx) == "number" then
		menuController.open("WAR TABLE")
	end
end)

-- ---------------------------------------------------------------------------
-- mobile compaction (owner on-device review: "everything is big overlapping"). desktop
-- fixed offsets collide on phone-size viewports; the theater panel is intel that already
-- lives in the deploy surface, the nav rail becomes a horizontal thumb-zone strip, and
-- the chrome plates compact. detection: touch-primary device or a narrow viewport either
-- way — a desktop window resized small gets the same honest treatment.
-- ---------------------------------------------------------------------------
do
	local UserInputService = game:GetService("UserInputService")
	local camera = workspace.CurrentCamera
	local function isMobileLayout()
		local vp = camera and camera.ViewportSize or Vector2.new(1280, 720)
		local touchPrimary = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		return touchPrimary or vp.X < 900
	end
	local function applyLayoutMode()
		local mobile = isMobileLayout()
		opsPanel.Visible = not mobile
		if mobile then
			rail.Size = UDim2.fromOffset(4 * 118, 50)
			rail.Position = UDim2.new(0, 10, 1, -60)
			for i, btn in ipairs(rail:GetChildren()) do
				if btn:IsA("TextButton") then
					btn.Size = UDim2.fromOffset(112, 46)
					btn.Position = UDim2.fromOffset((i - 1) * 118, 0)
				end
			end
			rankPlate.Size = UDim2.fromOffset(160, 50)
			rankPlate.Position = UDim2.fromOffset(10, 8)
		else
			rail.Size = UDim2.fromOffset(190, 260)
			rail.Position = UDim2.new(0, 16, 0.5, -130)
			for i, btn in ipairs(rail:GetChildren()) do
				if btn:IsA("TextButton") then
					btn.Size = UDim2.fromOffset(190, 52)
					btn.Position = UDim2.fromOffset(0, (i - 1) * 60)
				end
			end
			rankPlate.Size = UDim2.fromOffset(210, 64)
			rankPlate.Position = UDim2.fromOffset(28, 70)
		end
	end
	applyLayoutMode()
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayoutMode)
	end
end

print("[GF] lobby shell online")
