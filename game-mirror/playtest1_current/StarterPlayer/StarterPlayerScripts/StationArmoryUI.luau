--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local requestLoadout = remotes:WaitForChild("RequestLoadout")
local setLoadout = remotes:WaitForChild("SetLoadout")

local Tokens = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Tokens"))
local Components = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Components"))
local WeaponVisuals = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("WeaponVisuals"))
local WeaponsConfig = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("Weapons"))
local ClassesConfig = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("Classes"))
local AbilitiesConfig = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("Abilities"))
local ArmorConfig = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("Armor"))
local EconomyConfig = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("Economy"))
local AugmentsConfig = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("Augments"))
local cacheCfg = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("Caches"))

local CYAN = Tokens.Color.techCyan
local AMBER = Tokens.Color.accentSelect
local INK = Tokens.Color.panelInset
local PANEL = Tokens.Color.panel
local PANEL_RAISED = Tokens.Color.panelRaised
local PANEL_INSET = Tokens.Color.panelInset
local BORDER = Tokens.Color.border
local MUTED = Tokens.Color.textSecondary
local DISABLED = Tokens.Color.textDisabled
local WHITE = Tokens.Color.textPrimary
local SUCCESS = Tokens.Color.success
local DANGER = Tokens.Color.danger
local OPEN_RANGE = 46

local RARITY_COLORS = {
	Common = Color3.fromRGB(180, 185, 195),
	Rare = Color3.fromRGB(90, 160, 255),
	Epic = Color3.fromRGB(180, 110, 255),
	Legendary = Color3.fromRGB(255, 190, 80),
}

local gui
local prompt
local isOpen = false
local state = nil
local anchor = nil
local selectedWeaponId = nil
local selectedArmorId = nil
local activeSection = "LOADOUT"
local CACHE_CATEGORIES = { "ANY", "Universal", "AR", "SMG", "LMG", "Shotgun", "Marksman", "Launcher", "Pistol", "Support" }
local cacheCategoryIndex = 1
local rerollLockChoices = {}
local BULK_RARITIES = { "ALL", "Common", "Rare", "Epic", "Legendary" }
local bulkRarityIndex = 1
local bulkCategoryIndex = 1
local bulkPreview = nil
local fusionPreview = nil
local render
local renderWeaponList, renderWeaponDetail, renderAugmentSockets, renderArmor

-- P-1 targeting cost display: mirrors CacheService — 25 scrap per augment the tier rolls,
-- first targeted open per profile free. Untargeted (ANY) stays free.
local function targetingCostLabel(tierId)
	local sel = CACHE_CATEGORIES[cacheCategoryIndex] or "ANY"
	if sel == "ANY" then
		return "CAT ANY"
	end
	local tier = cacheCfg.get and cacheCfg.get(tierId) or nil
	local n = tier and tonumber(tier.augments) or 1
	if state and state.freeTargetedOpenAvailable then
		return string.format("CAT %s · FREE 1ST", sel)
	end
	return string.format("CAT %s · %dS", sel, 25 * n)
end

local function selectedCacheCategory()
	local value = CACHE_CATEGORIES[cacheCategoryIndex] or "ANY"
	return value ~= "ANY" and value or nil
end

-- ---------------------------------------------------------------------------
-- Sharp UI construction. The Armory deliberately uses no UICorner: controlled
-- bevels are communicated with thin borders, cut-corner ticks, and diagonal
-- accents rather than friendly rounded rectangles.
-- ---------------------------------------------------------------------------
local function plainFrame(parent, name, size, position, color, transparency)
	local f = Instance.new("Frame")
	f.Name = name or "Frame"
	f.BackgroundColor3 = color or PANEL_INSET
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Size = size
	f.Position = position or UDim2.fromOffset(0, 0)
	f.Parent = parent
	return f
end

local function addStroke(object, color, transparency, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or BORDER
	stroke.Transparency = transparency or 0.25
	stroke.Thickness = thickness or 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = object
	return stroke
end

local function cornerTicks(parent, color, length)
	local c = color or CYAN
	local l = length or 18
	local function tick(name, size, pos, anchor)
		local t = plainFrame(parent, name, size, pos, c, 0)
		t.AnchorPoint = anchor or Vector2.new(0, 0)
		t.ZIndex = 4
		return t
	end
	tick("Tick_TL_H", UDim2.fromOffset(l, 1), UDim2.fromOffset(0, 0))
	tick("Tick_TL_V", UDim2.fromOffset(1, l), UDim2.fromOffset(0, 0))
	tick("Tick_BR_H", UDim2.fromOffset(l, 1), UDim2.new(1, 0, 1, 0), Vector2.new(1, 1))
	tick("Tick_BR_V", UDim2.fromOffset(1, l), UDim2.new(1, 0, 1, 0), Vector2.new(1, 1))
end

local function panelFrame(parent, name, size, position, color)
	local f = plainFrame(parent, name, size, position, color or PANEL_RAISED, 0)
	addStroke(f, BORDER, 0.22, 1)
	cornerTicks(f, BORDER, 16)
	return f
end

local function cardFrame(parent, name, size, order, color)
	local f = plainFrame(parent, name, size, UDim2.fromOffset(0, 0), color or PANEL_INSET, 0)
	f.LayoutOrder = order or 1
	addStroke(f, BORDER, 0.48, 1)
	return f
end

local function makeText(parent, content, role, size, position, color, bold)
	local label = Components.text(parent, content, role or "caption", size, position)
	label.TextColor3 = color or (role == "caption" and MUTED or WHITE)
	label.Font = bold and Tokens.Type.fontBold or Tokens.Type.font
	label.TextYAlignment = Enum.TextYAlignment.Center
	return label
end

local function makeButton(parent, label, kind, size, position, onClick)
	local button = Components.button(parent, label, kind or "ghost")
	button.Size = size
	if position then
		button.Position = position
	end
	button.TextSize = Tokens.Type.sizeSmall
	button.Font = Tokens.Type.fontBold
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

local function makeScroll(parent, name, size, position)
	local scroll = Components.list(parent, size, position)
	scroll.Name = name
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = BORDER
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Tokens.Space.sm + 2)
	padding.PaddingRight = UDim.new(0, Tokens.Space.sm + 2)
	padding.PaddingTop = UDim.new(0, Tokens.Space.sm)
	padding.PaddingBottom = UDim.new(0, Tokens.Space.sm)
	padding.Parent = scroll
	return scroll
end

local function clearScroll(scroll)
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("ViewportFrame") then
			child:Destroy()
		end
	end
end

local function sectionHeader(parent, text, order)
	local row = plainFrame(parent, "Section_" .. text, UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 0), PANEL_INSET, 1)
	row.LayoutOrder = order or 1
	plainFrame(row, "Rule", UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1), BORDER, 0.15)
	makeText(row, string.upper(text), "caption", UDim2.new(1, -4, 1, -4), UDim2.fromOffset(2, 2), CYAN, true)
	return row
end

local function addCheckIcon(parent, position, color)
	local c = color or CYAN
	local holder = plainFrame(parent, "CheckIcon", UDim2.fromOffset(20, 16), position, PANEL_INSET, 1)
	local a = plainFrame(holder, "CheckA", UDim2.fromOffset(8, 2), UDim2.fromOffset(1, 10), c, 0)
	a.Rotation = 42
	local b = plainFrame(holder, "CheckB", UDim2.fromOffset(15, 2), UDim2.fromOffset(6, 6), c, 0)
	b.Rotation = -48
	return holder
end

local function addLockIcon(parent, position, color)
	local c = color or MUTED
	local holder = plainFrame(parent, "LockIcon", UDim2.fromOffset(16, 18), position, PANEL_INSET, 1)
	plainFrame(holder, "LockBody", UDim2.fromOffset(13, 10), UDim2.fromOffset(1, 7), c, 0)
	plainFrame(holder, "LockTop", UDim2.fromOffset(9, 2), UDim2.fromOffset(3, 1), c, 0)
	plainFrame(holder, "LockLeft", UDim2.fromOffset(2, 7), UDim2.fromOffset(3, 2), c, 0)
	plainFrame(holder, "LockRight", UDim2.fromOffset(2, 7), UDim2.fromOffset(10, 2), c, 0)
	plainFrame(holder, "LockKey", UDim2.fromOffset(2, 4), UDim2.fromOffset(7, 10), PANEL_INSET, 0)
	return holder
end

local function statusTag(parent, kind, text, position, width)
	local color = kind == "locked" and MUTED or kind == "selected" and AMBER or CYAN
	if kind == "warning" then
		color = AMBER
	elseif kind == "danger" then
		color = DANGER
	elseif kind == "success" then
		color = SUCCESS
	end
	local tag = plainFrame(parent, "Status_" .. text, UDim2.fromOffset(width or 104, 24), position, PANEL_INSET, 0)
	addStroke(tag, color, 0.25, 1)
	if kind == "locked" then
		addLockIcon(tag, UDim2.fromOffset(7, 4), color)
	elseif kind == "owned" or kind == "equipped" or kind == "success" then
		addCheckIcon(tag, UDim2.fromOffset(7, 13), color)
	end
	local inset = (kind == "locked" or kind == "owned" or kind == "equipped" or kind == "success") and 26 or 8
	makeText(tag, string.upper(text), "caption", UDim2.new(1, -inset - 4, 1, 0), UDim2.fromOffset(inset, 0), color, true)
	return tag
end

local function masteryPips(parent, level, position, width, height)
	local clamped = math.clamp(tonumber(level) or 0, 0, 5)
	local gap = 4
	local pipWidth = math.max(8, math.floor((width - gap * 4) / 5))
	for index = 1, 5 do
		local x = position.X.Offset + (index - 1) * (pipWidth + gap)
		local filled = index <= clamped
		local pip = plainFrame(parent, "MasteryPip" .. index, UDim2.fromOffset(pipWidth, height), UDim2.fromOffset(x, position.Y.Offset), filled and CYAN or PANEL_RAISED, filled and 0 or 0.1)
		addStroke(pip, filled and CYAN or BORDER, filled and 0.1 or 0.55, 1)
		if index == 5 and filled then
			pip.BackgroundColor3 = AMBER
		end
	end
end

local function qualityBar(parent, quality, position, width)
	local q = math.clamp(tonumber(quality) or 0, 0, 1000)
	local back = plainFrame(parent, "QualityTrack", UDim2.fromOffset(width, 5), position, Color3.fromRGB(45, 52, 61), 0)
	local fill = plainFrame(back, "QualityFill", UDim2.fromOffset(math.max(1, math.floor(width * q / 1000)), 5), UDim2.fromOffset(0, 0), q >= 1000 and Color3.fromRGB(255, 210, 80) or CYAN, 0)
	fill.Name = "QualityFill"
	return back
end

local function statCell(parent, label, value, position, size)
	local cellSize = typeof(size) == "UDim2" and size or UDim2.fromOffset(size, 52)
	local cell = plainFrame(parent, "Stat_" .. label, cellSize, position, PANEL_RAISED, 0)
	addStroke(cell, BORDER, 0.55, 1)
	makeText(cell, string.upper(label), "caption", UDim2.new(1, -12, 0, 15), UDim2.fromOffset(6, 5), MUTED, false)
	makeText(cell, tostring(value), "body", UDim2.new(1, -12, 0, 24), UDim2.fromOffset(6, 22), WHITE, true)
	return cell
end

-- 3D weapon previews: premium library models render inside ViewportFrames.
-- Framing follows the bounding-box math from the visual directive: camera distance is
-- derived from model extents and viewport FOV, not hard-coded per weapon.
local function buildWeaponPreview(parent: Frame, weaponId: string, size: UDim2, pos: UDim2)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "WeaponPreview_" .. tostring(weaponId)
	vp.Size = size
	vp.Position = pos
	vp.BackgroundColor3 = Color3.fromRGB(10, 14, 20)
	vp.BorderSizePixel = 0
	vp.ZIndex = 1
	vp.Parent = parent
	addStroke(vp, BORDER, 0.42, 1)
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local model = WeaponVisuals.build(weaponId)
	if model then
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
			end
		end
		model.Parent = world
		model:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(115), 0))
		local cf, sizeV = model:GetBoundingBox()
		local radius = math.max(sizeV.X, sizeV.Y, sizeV.Z) * 0.5
		local fov = 40
		local dist = radius / math.tan(math.rad(fov * 0.5)) * 1.45 + 0.4
		local cam = Instance.new("Camera")
		cam.FieldOfView = fov
		cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist * 0.35, dist * 0.45, -dist), cf.Position)
		cam.Parent = vp
		vp.CurrentCamera = cam
		vp.Ambient = Color3.fromRGB(200, 205, 215)
		vp.LightColor = Color3.fromRGB(255, 245, 235)
		vp.LightDirection = Vector3.new(-1, -2, -1)
	end
	local scan = plainFrame(vp, "Scanline", UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 0.62, 0), CYAN, 0.82)
	scan.ZIndex = 3
	local slash = plainFrame(vp, "CutAccent", UDim2.fromOffset(24, 1), UDim2.new(1, -28, 0, 8), AMBER, 0.15)
	slash.Rotation = -28
	slash.ZIndex = 3
	return vp
end

local function buildArmorPreview(parent: Frame, suitId: string, size: UDim2, pos: UDim2)
	local suit = ArmorConfig.get and ArmorConfig.get(suitId) or nil
	local plate = suit and suit.plate or Color3.fromRGB(198, 206, 214)
	local fatigue = suit and suit.fatigue or Color3.fromRGB(38, 44, 58)
	local accent = suit and suit.accent or CYAN
	local dark = suit and suit.dark or Color3.fromRGB(26, 30, 40)
	local steel = suit and suit.steel or Color3.fromRGB(86, 94, 108)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "ArmorPreview_" .. tostring(suitId)
	vp.Size = size
	vp.Position = pos
	vp.BackgroundColor3 = Color3.fromRGB(10, 14, 20)
	vp.BorderSizePixel = 0
	vp.Parent = parent
	addStroke(vp, BORDER, 0.42, 1)
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local model = Instance.new("Model")
	model.Name = "ArmorMannequin"
	model.Parent = world
	local function part(name, partSize, cf, color)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.Metal
		p.Color = color
		p.Size = partSize
		p.CFrame = cf
		p.Parent = model
		return p
	end
	part("Torso", Vector3.new(1.45, 1.55, 0.72), CFrame.new(0, 2.7, 0), plate)
	part("ChestPlate", Vector3.new(1.16, 0.52, 0.08), CFrame.new(0, 2.95, -0.41), accent)
	part("Pelvis", Vector3.new(1.18, 0.55, 0.66), CFrame.new(0, 1.82, 0), steel)
	part("Helmet", Vector3.new(0.82, 0.78, 0.78), CFrame.new(0, 3.85, 0), plate)
	part("Visor", Vector3.new(0.58, 0.16, 0.08), CFrame.new(0, 3.88, -0.43), accent)
	part("Crest", Vector3.new(0.12, 0.92, 0.84), CFrame.new(0.34, 3.92, 0), dark)
	for side = -1, 1, 2 do
		part("Shoulder" .. side, Vector3.new(0.72, 0.42, 0.86), CFrame.new(side * 1.02, 3.22, 0) * CFrame.Angles(0, 0, math.rad(side * -8)), plate)
		part("Arm" .. side, Vector3.new(0.42, 1.25, 0.48), CFrame.new(side * 1.1, 2.35, 0), fatigue)
		part("Gauntlet" .. side, Vector3.new(0.5, 0.42, 0.54), CFrame.new(side * 1.1, 1.55, 0), steel)
		part("Leg" .. side, Vector3.new(0.48, 1.15, 0.52), CFrame.new(side * 0.38, 1.0, 0), fatigue)
		part("Boot" .. side, Vector3.new(0.55, 0.35, 0.72), CFrame.new(side * 0.38, 0.28, -0.05), dark)
	end
	part("Base", Vector3.new(3.2, 0.18, 2.4), CFrame.new(0, 0, 0), BORDER)
	model:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(18), 0))
	local cam = Instance.new("Camera")
	cam.FieldOfView = 34
	cam.CFrame = CFrame.lookAt(Vector3.new(4.3, 3.3, -6.4), Vector3.new(0, 2.05, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Ambient = Color3.fromRGB(190, 198, 208)
	vp.LightColor = Color3.fromRGB(255, 244, 232)
	vp.LightDirection = Vector3.new(-1, -2, -1)
	return vp
end

-- Returns the part, not a cached Vector3: the station is rebuilt during boot, and a cached position
-- kept pointing at the destroyed rack, so the Armory silently refused to open anywhere.
local function findAnchor()
	local station = workspace:FindFirstChild("Station")
	if not station then
		return nil
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local best, bestDist = nil, math.huge
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "ArmoryRack" then
			local dist = root and (root.Position - d.Position).Magnitude or 0
			if dist < bestDist then
				best = d
				bestDist = dist
			end
		end
	end
	return best
end

local ui = {
	pages = {},
	nav = {},
}

local function setSection(name)
	activeSection = name
	for key, page in pairs(ui.pages) do
		page.Visible = key == name
	end
	for key, item in pairs(ui.nav) do
		Components.setNavActive(item, key == name)
	end
end

local function pageHeading(page, title, subtitle)
	makeText(page, title, "title", UDim2.new(0.72, 0, 0, 30), UDim2.fromOffset(0, 0), WHITE, true)
	makeText(page, subtitle, "caption", UDim2.new(0.72, 0, 0, 18), UDim2.fromOffset(0, 32), MUTED, false)
	plainFrame(page, "HeaderRule", UDim2.new(1, 0, 0, 1), UDim2.fromOffset(0, 52), BORDER, 0.2)
end

local function buildLoadoutPage(page)
	pageHeading(page, "LOADOUT // WEAPON SYSTEMS", "Select a weapon on the left; inspection, mastery, sockets, and ownership resolve side by side.")
	local listPanel = panelFrame(page, "WeaponListPane", UDim2.new(0.27, 0, 1, -58), UDim2.new(0, 0, 0, 58), PANEL_RAISED)
	makeText(listPanel, "WEAPONRY", "caption", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 7), CYAN, true)
	ui.weaponList = makeScroll(listPanel, "WeaponList", UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 30))

	local detailPanel = panelFrame(page, "WeaponDetailPane", UDim2.new(0.39, 0, 1, -58), UDim2.new(0.28, 0, 0, 58), PANEL_RAISED)
	makeText(detailPanel, "INSPECTION", "caption", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 7), CYAN, true)
	ui.weaponDetail = makeScroll(detailPanel, "WeaponDetail", UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 30))

	local systemsPanel = panelFrame(page, "CombatSystemsPane", UDim2.new(0.32, 0, 1, -58), UDim2.new(0.68, 0, 0, 58), PANEL_RAISED)
	makeText(systemsPanel, "COMBAT SYSTEMS", "caption", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 7), CYAN, true)
	ui.loadoutSide = makeScroll(systemsPanel, "CombatSystems", UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 30))
end

local function buildAugmentsPage(page)
	pageHeading(page, "AUGMENT FOUNDRY", "Core and auxiliary sockets, global instance inventory, reroll/fusion operations, and the compatible catalog.")
	local socketPanel = panelFrame(page, "SocketPane", UDim2.new(0.28, 0, 1, -58), UDim2.new(0, 0, 0, 58), PANEL_RAISED)
	makeText(socketPanel, "SOCKET MATRIX", "caption", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 7), CYAN, true)
	ui.augmentSockets = makeScroll(socketPanel, "SocketMatrix", UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 30))

	local inventoryPanel = panelFrame(page, "InventoryPane", UDim2.new(0.42, 0, 1, -58), UDim2.new(0.29, 0, 0, 58), PANEL_RAISED)
	makeText(inventoryPanel, "GLOBAL AUGMENT INVENTORY", "caption", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 7), CYAN, true)
	ui.augmentInventory = makeScroll(inventoryPanel, "AugmentInventory", UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 30))

	local opsPanel = panelFrame(page, "AugmentOpsPane", UDim2.new(0.28, 0, 1, -58), UDim2.new(0.72, 0, 0, 58), PANEL_RAISED)
	makeText(opsPanel, "OPERATIONS // CATALOG", "caption", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 7), CYAN, true)
	ui.augmentOps = makeScroll(opsPanel, "AugmentOperations", UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 30))
end

local function buildArmorPage(page)
	pageHeading(page, "ARMOR CUSTOMIZATION", "Kit selection with material channels, rank and credit requirements, ownership state, and a live color preview.")
	local listPanel = panelFrame(page, "ArmorListPane", UDim2.new(0.34, 0, 1, -58), UDim2.new(0, 0, 0, 58), PANEL_RAISED)
	makeText(listPanel, "ARMOR KITS", "caption", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 7), CYAN, true)
	ui.armorList = makeScroll(listPanel, "ArmorList", UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 30))

	local detailPanel = panelFrame(page, "ArmorDetailPane", UDim2.new(0.65, 0, 1, -58), UDim2.new(0.35, 0, 0, 58), PANEL_RAISED)
	makeText(detailPanel, "FITTING BAY", "caption", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 7), CYAN, true)
	ui.armorDetail = makeScroll(detailPanel, "ArmorDetail", UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 30))
end

local function buildSupplyPage(page)
	pageHeading(page, "SUPPLY // REQUISITIONS", "Caches, targeting, odds disclosure, inventory expansion, and military requisition catalogs in one flat surface.")
	local cachePanel = panelFrame(page, "CachePane", UDim2.new(0.34, 0, 1, -104), UDim2.new(0, 0, 0, 58), PANEL_RAISED)
	makeText(cachePanel, "CACHE OPERATIONS", "caption", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 7), CYAN, true)
	ui.cacheList = makeScroll(cachePanel, "CacheOperations", UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 30))

	local reqPanel = panelFrame(page, "RequisitionPane", UDim2.new(0.65, 0, 1, -104), UDim2.new(0.35, 0, 0, 58), PANEL_RAISED)
	makeText(reqPanel, "MILITARY REQUISITIONS", "caption", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 7), CYAN, true)
	ui.requisitionList = makeScroll(reqPanel, "Requisitions", UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 30))

	local statusStrip = panelFrame(page, "SupplyStatusStrip", UDim2.new(1, 0, 0, 38), UDim2.new(0, 0, 1, -40), PANEL_INSET)
	makeText(statusStrip, "STATUS", "caption", UDim2.fromOffset(64, 18), UDim2.fromOffset(12, 10), MUTED, true)
	ui.statusLabel = makeText(statusStrip, "READY", "caption", UDim2.new(1, -96, 0, 18), UDim2.fromOffset(84, 10), CYAN, true)
end

local function buildCacheReveal()
	local revealFrame = panelFrame(gui, "CacheReveal", UDim2.fromOffset(360, 132), UDim2.new(0.5, -180, 0.5, -66), Color3.fromRGB(12, 16, 22))
	revealFrame.Visible = false
	revealFrame.ZIndex = 50
	local revealGlow = plainFrame(revealFrame, "RevealGlow", UDim2.new(1, 0, 0, 7), UDim2.fromOffset(0, 0), Color3.fromRGB(90, 160, 255), 0)
	revealGlow.ZIndex = 51
	local revealLabel = makeText(revealFrame, "OPENING CACHE", "body", UDim2.fromOffset(328, 30), UDim2.fromOffset(16, 24), WHITE, true)
	revealLabel.ZIndex = 52
	local revealResult = makeText(revealFrame, "", "caption", UDim2.fromOffset(328, 48), UDim2.fromOffset(16, 62), MUTED, false)
	revealResult.TextWrapped = true
	revealResult.TextYAlignment = Enum.TextYAlignment.Top
	revealResult.ZIndex = 52
	ui.revealFrame = revealFrame
	ui.revealGlow = revealGlow
	ui.revealLabel = revealLabel
	ui.revealResult = revealResult
	ui.revealSkip = false
	revealFrame.InputBegan:Connect(function()
		ui.revealSkip = true
	end)
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "GF_Armory"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Enabled = true
	gui.Parent = playerGui

	prompt = panelFrame(gui, "ArmoryPrompt", UDim2.fromOffset(286, 52), UDim2.new(0.5, -143, 1, -188), PANEL_INSET)
	prompt.Visible = false
	plainFrame(prompt, "PromptEdge", UDim2.fromOffset(4, 34), UDim2.fromOffset(0, 9), CYAN, 0)
	makeText(prompt, "ARMORY  //  ACCESS [E]", "body", UDim2.fromOffset(250, 24), UDim2.fromOffset(18, 14), CYAN, true)

	local panel = panelFrame(gui, "Panel", UDim2.new(1, -48, 1, -48), UDim2.new(0.5, 0, 0.5, 0), PANEL)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(1480, 920)
	constraint.Parent = panel

	plainFrame(panel, "TopCyanRule", UDim2.new(1, 0, 0, 2), UDim2.fromOffset(0, 0), CYAN, 0)
	makeText(panel, "ARMORY", "title", UDim2.fromOffset(180, 28), UDim2.fromOffset(18, 12), CYAN, true)
	makeText(panel, "GALACTIC FORCE REQUISITION SYSTEM", "caption", UDim2.fromOffset(250, 16), UDim2.fromOffset(20, 40), MUTED, false)

	ui.creditsLabel = makeText(panel, "", "body", UDim2.new(0.38, 0, 0, 22), UDim2.new(0.34, 0, 0, 12), AMBER, true)
	ui.creditsLabel.Name = "Credits"
	ui.walletLabel = makeText(panel, "", "caption", UDim2.new(0.52, -110, 0, 18), UDim2.new(0.34, 0, 0, 38), Color3.fromRGB(200, 205, 215), false)
	ui.walletLabel.Name = "Wallet"
	ui.walletLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local xpTrack = plainFrame(panel, "XpTrack", UDim2.new(0.18, 0, 0, 5), UDim2.new(0.70, 0, 0, 58), PANEL_INSET, 0)
	addStroke(xpTrack, BORDER, 0.55, 1)
	ui.xpFill = plainFrame(xpTrack, "Fill", UDim2.new(0, 0, 1, 0), UDim2.fromOffset(0, 0), CYAN, 0)
	ui.xpLabel = makeText(panel, "", "caption", UDim2.new(0.1, -12, 0, 16), UDim2.new(0.89, 8, 0, 52), MUTED, false)

	ui.closeButton = makeButton(panel, "CLOSE [E]", "ghost", UDim2.fromOffset(116, 36), UDim2.new(1, -130, 0, 12), nil)
	ui.closeButton.Name = "Close"

	local rail = panelFrame(panel, "SectionRail", UDim2.new(0, 76, 1, -94), UDim2.fromOffset(12, 82), PANEL_INSET)
	local railLayout = Instance.new("UIListLayout")
	railLayout.FillDirection = Enum.FillDirection.Vertical
	railLayout.Padding = UDim.new(0, Tokens.Space.sm)
	railLayout.SortOrder = Enum.SortOrder.LayoutOrder
	railLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	railLayout.Parent = rail
	local railPadding = Instance.new("UIPadding")
	railPadding.PaddingTop = UDim.new(0, Tokens.Space.sm)
	railPadding.Parent = rail

	local content = plainFrame(panel, "Content", UDim2.new(1, -112, 1, -94), UDim2.fromOffset(100, 82), PANEL, 1)
	ui.content = content

	local sectionDefs = {
		{ name = "LOADOUT", glyph = "01", builder = buildLoadoutPage },
		{ name = "AUGMENTS", glyph = "02", builder = buildAugmentsPage },
		{ name = "ARMOR", glyph = "03", builder = buildArmorPage },
		{ name = "SUPPLY", glyph = "04", builder = buildSupplyPage },
	}
	for index, def in ipairs(sectionDefs) do
		local navItem = Components.sidebarItem(rail, def.glyph, def.name)
		navItem.LayoutOrder = index
		navItem.Size = UDim2.new(1, -10, 0, 66)
		ui.nav[def.name] = navItem
		navItem.Activated:Connect(function()
			setSection(def.name)
		end)
		local page = plainFrame(content, "Page_" .. def.name, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), PANEL, 1)
		page.Visible = false
		ui.pages[def.name] = page
		def.builder(page)
	end

	buildCacheReveal()
	setSection("LOADOUT")
	return panel, ui.creditsLabel, ui.walletLabel
end

local panel, creditsLabel, walletLabel = buildGui()

-- ---------------------------------------------------------------------------
-- State helpers. These only reshape data already present in the existing
-- payload/configs; remote names and payload fields are unchanged.
-- ---------------------------------------------------------------------------
local function weaponState(id)
	for _, weapon in ipairs((state and state.weapons) or {}) do
		if weapon.id == id then
			return weapon
		end
	end
	return nil
end

local function ensureSelections()
	if not state then
		return
	end
	if not selectedWeaponId or not weaponState(selectedWeaponId) then
		selectedWeaponId = state.loadout and state.loadout.primary or nil
		if not selectedWeaponId or not weaponState(selectedWeaponId) then
			local first = state.weapons and state.weapons[1]
			selectedWeaponId = first and first.id or nil
		end
	end
	if not selectedArmorId then
		selectedArmorId = state.loadout and state.loadout.armor or nil
	end
	local armorFound = false
	for _, suit in ipairs(state.armor or {}) do
		if suit.id == selectedArmorId then
			armorFound = true
		end
	end
	if not armorFound then
		local first = state.armor and state.armor[1]
		selectedArmorId = first and first.id or nil
	end
end

local function abilityConfig(id)
	return AbilitiesConfig.ById and AbilitiesConfig.ById[id] or nil
end

local function abilityState(id)
	for _, row in ipairs((state and state.abilities) or {}) do
		if row.id == id then
			return row
		end
	end
	return nil
end

local function grenadeConfig(id)
	for _, entry in ipairs(EconomyConfig.Grenades or {}) do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

local function armorConfig(id)
	return ArmorConfig.get and ArmorConfig.get(id) or nil
end

local function augmentItemByUid(uid)
	for _, item in ipairs((state and state.augmentItems) or {}) do
		if item.uid == uid or item.id == uid or item.archetypeId == uid then
			return item
		end
	end
	return nil
end

local function augmentName(ref)
	local item = augmentItemByUid(ref)
	if item then
		return item.name or item.id or tostring(ref)
	end
	return tostring(ref or "EMPTY")
end

local function slottedFor(weaponId, slot)
	if not state then
		return nil
	end
	local perWeapon = state.slottedByWeapon and state.slottedByWeapon[weaponId]
	if type(perWeapon) == "table" then
		return perWeapon[slot]
	end
	if state.loadout and weaponId == state.loadout.primary and type(state.slotted) == "table" then
		return state.slotted[slot]
	end
	return nil
end

local function compatibleAugments(weapon)
	local rows = {}
	if not weapon then
		return rows
	end
	for _, item in ipairs((state and state.augmentItems) or {}) do
		local category = tostring(item.category or "")
		if category == "Universal" or category == tostring(weapon.category) then
			table.insert(rows, item)
		end
	end
	return rows
end

local function lockReasons(row, rank)
	local locks = {}
	if row.premiumLocked then
		table.insert(locks, "SIEGE DIVISION")
	end
	if row.requisitionTierLocked then
		table.insert(locks, "TIER " .. tostring(row.requisitionTier or "?"))
	end
	if type(row.rank) == "number" and row.rank > (rank or 1) then
		table.insert(locks, string.format("RANK %d", row.rank))
	end
	return locks
end

local function prettyStat(stat)
	local text = tostring(stat or "STAT")
	text = text:gsub("(%l)(%u)", "%1 %2")
	return string.upper(text)
end

local function passiveText(passive)
	if type(passive) ~= "table" then
		return "NO PASSIVE"
	end
	local value = tonumber(passive.value) or 0
	local sign = value >= 0 and "+" or ""
	return string.format("%s%d%% %s", sign, math.floor(value * 100 + 0.5), prettyStat(passive.stat))
end

local function fireSocketCycle(weapon, slot)
	local owned = compatibleAugments(weapon)
	if #owned == 0 then
		return
	end
	local slotted = slottedFor(weapon.id, slot)
	local nextIndex = 1
	for index, def in ipairs(owned) do
		if def.uid == slotted then
			nextIndex = index % #owned + 1
		end
	end
	setLoadout:FireServer({ action = "augment", weapon = weapon.id, slot = slot, id = owned[nextIndex].uid })
end

local function addSocketInterface(parent, weapon, order, compact)
	local masteryLevel = state.masteryLevel and state.masteryLevel[weapon.id] or 0
	local masteryXp = state.mastery and state.mastery[weapon.id] or 0
	local sockets = state.sockets and state.sockets[weapon.id] or 1
	local card = cardFrame(parent, "SocketInterface", UDim2.new(1, 0, 0, compact and 138 or 164), order, PANEL_RAISED)
	makeText(card, "AUGMENT SOCKETS", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	makeText(card, string.format("MASTERY %d · %d XP · %d SOCKET%s", masteryLevel, masteryXp, sockets, sockets == 1 and "" or "S"), "caption", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 28), MUTED, false)
	for slot = 1, 2 do
		local allowed = weapon.owned == true and slot <= sockets
		local slotted = slottedFor(weapon.id, slot)
		local slotButton = Instance.new("TextButton")
		slotButton.Name = slot == 1 and "CoreSocket" or "AuxiliarySocket"
		slotButton.Size = UDim2.new(0.5, -18, 0, compact and 72 or 82)
		slotButton.Position = slot == 1 and UDim2.fromOffset(12, compact and 52 or 60) or UDim2.new(0.5, 6, 0, compact and 52 or 60)
		slotButton.BackgroundColor3 = allowed and Color3.fromRGB(26, 34, 44) or Color3.fromRGB(24, 22, 24)
		slotButton.BorderSizePixel = 0
		slotButton.AutoButtonColor = false
		slotButton.Font = Tokens.Type.fontBold
		slotButton.TextSize = Tokens.Type.sizeSmall
		slotButton.TextWrapped = true
		slotButton.TextColor3 = allowed and (slotted and CYAN or WHITE) or DISABLED
		local slotName = slot == 1 and "CORE" or "AUXILIARY"
		local detail = slotted and augmentName(slotted) or (allowed and "EMPTY // CYCLE" or (weapon.owned ~= true and "LOCKED // OWNERSHIP" or "LOCKED // MASTERY 5"))
		slotButton.Text = string.format("%s\n%s", slotName, string.upper(detail))
		slotButton.Parent = card
		addStroke(slotButton, allowed and (slotted and CYAN or BORDER) or DISABLED, allowed and 0.25 or 0.55, 1)
		if not allowed then
			addLockIcon(slotButton, UDim2.fromOffset(8, 8), MUTED)
		end
		if allowed then
			slotButton.Activated:Connect(function()
				fireSocketCycle(weapon, slot)
			end)
		end
	end
	return order + 1
end

-- ---------------------------------------------------------------------------
-- LOADOUT renderers
-- ---------------------------------------------------------------------------
renderWeaponList = function()
	clearScroll(ui.weaponList)
	for index, weapon in ipairs(state.weapons or {}) do
		local selected = weapon.id == selectedWeaponId
		local row = Instance.new("TextButton")
		row.Name = "WeaponRow_" .. tostring(weapon.id)
		row.Size = UDim2.new(1, 0, 0, 78)
		row.BackgroundColor3 = selected and Color3.fromRGB(48, 39, 27) or (weapon.equipped and Color3.fromRGB(20, 37, 45) or PANEL_INSET)
		row.BorderSizePixel = 0
		row.AutoButtonColor = false
		row.Text = ""
		row.LayoutOrder = index
		row.Parent = ui.weaponList
		addStroke(row, selected and AMBER or (weapon.equipped and CYAN or BORDER), selected and 0 or 0.52, 1)
		if selected then
			plainFrame(row, "SelectionBar", UDim2.fromOffset(4, 62), UDim2.fromOffset(0, 8), AMBER, 0)
		end
		buildWeaponPreview(row, weapon.id, UDim2.fromOffset(82, 52), UDim2.fromOffset(10, 13))
		makeText(row, string.upper(tostring(weapon.name)), "body", UDim2.new(1, -218, 0, 20), UDim2.fromOffset(102, 7), WHITE, true)
		makeText(row, string.format("%s · %d DMG · %d MAG · %s", tostring(weapon.category), tonumber(weapon.damage) or 0, tonumber(weapon.magazine) or 0, tostring(weapon.mode)), "caption", UDim2.new(1, -218, 0, 16), UDim2.fromOffset(102, 29), MUTED, false)
		local masteryLevel = state.masteryLevel and state.masteryLevel[weapon.id] or 0
		masteryPips(row, masteryLevel, UDim2.fromOffset(102, 56), 96, 10)
		local locks = lockReasons(weapon, state.rank or 1)
		local statusKind = weapon.equipped and "equipped" or weapon.owned and "owned" or (#locks > 0 and "locked" or "warning")
		local statusText = weapon.equipped and "EQUIPPED" or weapon.owned and "OWNED" or (#locks > 0 and "LOCKED" or string.format("%d CR", tonumber(weapon.cost) or 0))
		statusTag(row, statusKind, statusText, UDim2.new(1, -110, 0, 8), 100)
		if #locks > 0 then
			local lockText = makeText(row, table.concat(locks, " · "), "caption", UDim2.fromOffset(118, 13), UDim2.new(1, -128, 0, 36), MUTED, false)
			lockText.TextXAlignment = Enum.TextXAlignment.Right
		end
		row.Activated:Connect(function()
			selectedWeaponId = weapon.id
			renderWeaponList()
			renderWeaponDetail()
			renderAugmentSockets()
		end)
	end
end

renderWeaponDetail = function()
	clearScroll(ui.weaponDetail)
	local weapon = weaponState(selectedWeaponId)
	if not weapon then
		return
	end
	local order = 1
	local hero = cardFrame(ui.weaponDetail, "WeaponHero", UDim2.new(1, 0, 0, 236), order, PANEL_RAISED)
	order += 1
	buildWeaponPreview(hero, weapon.id, UDim2.new(1, -20, 1, -58), UDim2.fromOffset(10, 10))
	local overlay = plainFrame(hero, "HeroOverlay", UDim2.new(1, -20, 0, 36), UDim2.new(0, 10, 1, -46), Color3.fromRGB(8, 12, 18), 0.18)
	addStroke(overlay, BORDER, 0.62, 1)
	makeText(overlay, string.upper(tostring(weapon.name)), "body", UDim2.new(0.58, 0, 1, 0), UDim2.fromOffset(10, 0), WHITE, true)
	local config = WeaponsConfig.get and WeaponsConfig.get(weapon.id) or nil
	makeText(overlay, string.upper(tostring((config and config.displayCategory) or weapon.category)), "caption", UDim2.new(0.38, -10, 1, 0), UDim2.new(0.60, 0, 0, 0), CYAN, true)

	local statusCard = cardFrame(ui.weaponDetail, "WeaponStatus", UDim2.new(1, 0, 0, 116), order, PANEL_INSET)
	order += 1
	local locks = lockReasons(weapon, state.rank or 1)
	if weapon.equipped then
		statusTag(statusCard, "equipped", "equipped", UDim2.fromOffset(12, 12), 116)
	elseif weapon.owned then
		statusTag(statusCard, "owned", "owned", UDim2.fromOffset(12, 12), 96)
	elseif #locks > 0 then
		statusTag(statusCard, "locked", "locked", UDim2.fromOffset(12, 12), 104)
	else
		statusTag(statusCard, "warning", "available", UDim2.fromOffset(12, 12), 108)
	end
	if #locks > 0 then
		makeText(statusCard, table.concat(locks, "  ·  "), "caption", UDim2.new(1, -190, 0, 18), UDim2.fromOffset(12, 42), MUTED, true)
	else
		makeText(statusCard, string.format("%d CR  ·  RANK %d", tonumber(weapon.cost) or 0, tonumber(weapon.rank) or 1), "caption", UDim2.new(1, -190, 0, 18), UDim2.fromOffset(12, 42), AMBER, true)
	end
	makeText(statusCard, weapon.owned and "Ownership confirmed in armory ledger." or "Purchase writes to the shared requisition ledger.", "caption", UDim2.new(1, -190, 0, 16), UDim2.fromOffset(12, 66), MUTED, false)
	if weapon.owned and not weapon.equipped then
		local equip = makeButton(statusCard, "EQUIP", "primary", UDim2.fromOffset(142, 52), UDim2.new(1, -154, 0, 20), function()
			setLoadout:FireServer({ action = "equip", id = weapon.id })
		end)
		equip.Name = "Equip"
	elseif not weapon.owned and #locks == 0 then
		local buyLabel = (tonumber(weapon.cost) or 0) > 0 and string.format("BUY %d", tonumber(weapon.cost) or 0) or "CLAIM"
		local buy = makeButton(statusCard, buyLabel, "primary", UDim2.fromOffset(142, 52), UDim2.new(1, -154, 0, 20), function()
			setLoadout:FireServer({ action = "buy", id = weapon.id })
		end)
		buy.Name = "Buy"
		buy.TextColor3 = AMBER
	end

	local stats = cardFrame(ui.weaponDetail, "WeaponStats", UDim2.new(1, 0, 0, 82), order, PANEL_RAISED)
	order += 1
	local statRows = {
		{ label = "cost", value = string.format("%d CR", tonumber(weapon.cost) or 0) },
		{ label = "damage", value = weapon.damage },
		{ label = "magazine", value = weapon.magazine },
		{ label = "mode", value = weapon.mode },
		{ label = "rank req", value = weapon.rank },
	}
	for index, entry in ipairs(statRows) do
		statCell(stats, entry.label, entry.value, UDim2.new((index - 1) * 0.2, 12, 0, 14), UDim2.new(0.2, -16, 0, 52))
	end

	local masteryCard = cardFrame(ui.weaponDetail, "WeaponMastery", UDim2.new(1, 0, 0, 112), order, PANEL_INSET)
	order += 1
	local masteryLevel = state.masteryLevel and state.masteryLevel[weapon.id] or 0
	local masteryXp = state.mastery and state.mastery[weapon.id] or 0
	makeText(masteryCard, "MASTERY 1–5", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	masteryPips(masteryCard, masteryLevel, UDim2.fromOffset(12, 40), 230, 18)
	makeText(masteryCard, string.format("LEVEL %d  ·  %d XP", masteryLevel, masteryXp), "body", UDim2.new(1, -270, 0, 24), UDim2.fromOffset(262, 36), WHITE, true)
	makeText(masteryCard, masteryLevel >= 5 and "AUXILIARY SOCKET UNLOCKED" or "AUXILIARY SOCKET UNLOCKS AT MASTERY 5", "caption", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 74), masteryLevel >= 5 and AMBER or MUTED, true)

	order = addSocketInterface(ui.weaponDetail, weapon, order, false)
	sectionHeader(ui.weaponDetail, "compatible owned augments", order)
	order += 1
	local compatible = compatibleAugments(weapon)
	if #compatible == 0 then
		local empty = cardFrame(ui.weaponDetail, "NoCompatibleAugments", UDim2.new(1, 0, 0, 56), order, PANEL_INSET)
		order += 1
		makeText(empty, "NO OWNED COMPATIBLE AUGMENTS", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 12), MUTED, true)
		makeText(empty, "Caches and the catalog feed this inventory.", "caption", UDim2.new(1, -24, 0, 15), UDim2.fromOffset(12, 32), DISABLED, false)
	else
		for _, item in ipairs(compatible) do
			local row = cardFrame(ui.weaponDetail, "Compatible_" .. tostring(item.uid), UDim2.new(1, 0, 0, 76), order, PANEL_INSET)
			order += 1
			local rarityColor = RARITY_COLORS[item.rarity] or MUTED
			plainFrame(row, "RarityEdge", UDim2.fromOffset(4, 58), UDim2.fromOffset(0, 9), rarityColor, 0)
			makeText(row, string.format("%s · %s %s", tostring(item.name or item.id), tostring(item.rarity or "?"), tostring(item.category or "?")), "body", UDim2.new(1, -150, 0, 19), UDim2.fromOffset(14, 8), WHITE, true)
			makeText(row, tostring(item.traitText or "no traits"), "caption", UDim2.new(1, -150, 0, 16), UDim2.fromOffset(14, 31), MUTED, false)
			qualityBar(row, item.quality, UDim2.fromOffset(14, 58), 150)
			statusTag(row, "owned", "fits", UDim2.new(1, -102, 0, 24), 88)
		end
	end
end

local function renderPresetCard(order)
	local card = cardFrame(ui.loadoutSide, "LoadoutPresets", UDim2.new(1, 0, 0, 214), order, PANEL_INSET)
	makeText(card, "LOADOUT PRESETS", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	makeText(card, "Server-authoritative saved loadouts", "caption", UDim2.new(1, -24, 0, 15), UDim2.fromOffset(12, 27), MUTED, false)
	for slot = 1, 3 do
		local y = 48 + (slot - 1) * 52
		local row = plainFrame(card, "Loadout" .. slot, UDim2.new(1, -24, 0, 44), UDim2.fromOffset(12, y), PANEL_RAISED, 0)
		addStroke(row, BORDER, 0.58, 1)
		makeText(row, string.format("PRESET %d", slot), "caption", UDim2.new(1, -176, 0, 18), UDim2.fromOffset(10, 13), WHITE, true)
		local saveButton = makeButton(row, "SAVE", "ghost", UDim2.fromOffset(70, 34), UDim2.new(1, -152, 0, 5), function()
			setLoadout:FireServer({ action = "saveLoadout", slot = slot })
		end)
		saveButton.Name = "Save"
		saveButton.TextColor3 = AMBER
		local loadButton = makeButton(row, "LOAD", "primary", UDim2.fromOffset(70, 34), UDim2.new(1, -76, 0, 5), function()
			setLoadout:FireServer({ action = "loadLoadout", slot = slot })
		end)
		loadButton.Name = "Load"
	end
	return order + 1
end

local function renderClassCard(order)
	local card = cardFrame(ui.loadoutSide, "ClassPassives", UDim2.new(1, 0, 0, 288), order, PANEL_INSET)
	makeText(card, "CLASS // PERSONAL // TEAM", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	for index, classRow in ipairs(state.classes or {}) do
		local column = (index - 1) % 2
		local rowIndex = math.floor((index - 1) / 2)
		local button = makeButton(card, string.upper(tostring(classRow.name or classRow.id)), classRow.selected and "primary" or "ghost", UDim2.new(0.5, -21, 0, 48), UDim2.new(column * 0.5, column == 0 and 12 or 9, 0, 38 + rowIndex * 54), function()
			setLoadout:FireServer({ action = "class", id = classRow.id })
		end)
		button.Name = "Class_" .. tostring(classRow.id)
		if classRow.selected then
			button.BackgroundColor3 = AMBER
			button.TextColor3 = INK
			local function pinSelected()
				button.BackgroundColor3 = AMBER
				button.TextColor3 = INK
			end
			button.MouseLeave:Connect(pinSelected)
			button.SelectionLost:Connect(pinSelected)
		end
	end
	local passivePanel = plainFrame(card, "PassiveReadout", UDim2.new(1, -24, 0, 118), UDim2.fromOffset(12, 154), PANEL_RAISED, 0)
	addStroke(passivePanel, BORDER, 0.55, 1)
	local selected = nil
	for _, classRow in ipairs(ClassesConfig.List or {}) do
		if classRow.id == state.selectedClass then
			selected = classRow
		end
	end
	makeText(passivePanel, selected and string.upper(tostring(selected.displayName)) or "NO CLASS", "caption", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 8), AMBER, true)
	makeText(passivePanel, "PERSONAL  " .. passiveText(selected and selected.personal), "caption", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 39), CYAN, true)
	makeText(passivePanel, "TEAM      " .. passiveText(selected and selected.team), "caption", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 68), WHITE, true)
	makeText(passivePanel, "Class passives remain fixed for the mission once deployed.", "caption", UDim2.new(1, -20, 0, 15), UDim2.fromOffset(10, 94), MUTED, false)
	return order + 1
end

local function abilityCard(parent, def, order)
	local rowState = abilityState(def.id) or { owned = false, rank = def.unlockRank or 1, cost = def.cost or 0 }
	local equipped = state.loadout and state.loadout.ability == def.id
	local owned = rowState.owned == true
	local rank = tonumber(rowState.rank or def.unlockRank or def.rank) or 1
	local cost = tonumber(rowState.cost or def.cost) or 0
	local locked = rank > (state.rank or 1)
	local card = Instance.new("TextButton")
	card.Name = owned and "UseAbility" or (locked and "AbilityLocked" or "BuyAbility")
	card:SetAttribute("AbilityId", def.id)
	card.Size = UDim2.new(1, 0, 0, 64)
	card.BackgroundColor3 = equipped and Color3.fromRGB(50, 39, 25) or owned and Color3.fromRGB(19, 35, 43) or PANEL_INSET
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Text = ""
	card.LayoutOrder = order
	card.Parent = parent
	addStroke(card, equipped and AMBER or owned and CYAN or locked and DISABLED or AMBER, equipped and 0 or 0.32, 1)
	makeText(card, tostring(def.displayName or def.id), "caption", UDim2.new(1, -42, 0, 17), UDim2.fromOffset(9, 7), WHITE, true)
	makeText(card, string.format("%ds", tonumber(def.cooldown) or 0), "body", UDim2.fromOffset(54, 20), UDim2.new(1, -62, 0, 27), CYAN, true)
	makeText(card, string.format("CD  ·  RANK %d  ·  %d CR", rank, cost), "caption", UDim2.new(1, -82, 0, 14), UDim2.fromOffset(9, 39), locked and MUTED or AMBER, false)
	if equipped or owned then
		addCheckIcon(card, UDim2.new(1, -30, 0, 6), equipped and AMBER or CYAN)
	elseif locked then
		addLockIcon(card, UDim2.new(1, -24, 0, 5), MUTED)
	end
	card.Activated:Connect(function()
		if owned then
			setLoadout:FireServer({ action = "equipAbility", slot = 1, id = def.id })
		elseif not locked then
			setLoadout:FireServer({ action = "buyAbility", id = def.id })
		end
	end)
	return card
end

local function renderAbilityModule(order)
	local card = cardFrame(ui.loadoutSide, "SupportAbility", UDim2.new(1, 0, 0, 448), order, PANEL_INSET)
	makeText(card, "ABILITY PICKERS", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	local currentId = state.loadout and state.loadout.ability or "?"
	local currentDef = abilityConfig(currentId)
	local banner = plainFrame(card, "CurrentAbility", UDim2.new(1, -24, 0, 52), UDim2.fromOffset(12, 32), Color3.fromRGB(19, 35, 43), 0)
	addStroke(banner, CYAN, 0.25, 1)
	makeText(banner, "ACTIVE SUPPORT SLOT", "caption", UDim2.new(0.55, 0, 0, 15), UDim2.fromOffset(10, 7), MUTED, true)
	makeText(banner, string.upper(tostring((currentDef and currentDef.displayName) or currentId)), "caption", UDim2.new(0.62, 0, 0, 18), UDim2.fromOffset(10, 25), CYAN, true)
	makeText(banner, string.format("%ds CD", tonumber(currentDef and currentDef.cooldown) or 0), "body", UDim2.new(0.28, -10, 0, 24), UDim2.new(0.70, 0, 0, 14), AMBER, true)
	makeText(card, "Pickers are grouped by targeting; the current combat contract exposes one active support slot.", "caption", UDim2.new(1, -24, 0, 15), UDim2.fromOffset(12, 88), MUTED, false)
	local columns = {
		{ title = "GROUND PICKER", targeting = "Ground", xScale = 0, xOffset = 12 },
		{ title = "SELF PICKER", targeting = "Self", xScale = 0.5, xOffset = 9 },
	}
	for columnIndex, column in ipairs(columns) do
		local columnFrame = plainFrame(card, column.title, UDim2.new(0.5, -21, 0, 318), UDim2.new(column.xScale, column.xOffset, 0, 112), PANEL_RAISED, 0)
		addStroke(columnFrame, BORDER, 0.55, 1)
		makeText(columnFrame, column.title, "caption", UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 7), columnIndex == 1 and CYAN or AMBER, true)
		local list = Instance.new("Frame")
		list.Name = "AbilityColumnList"
		list.Size = UDim2.new(1, -16, 1, -36)
		list.Position = UDim2.fromOffset(8, 30)
		list.BackgroundTransparency = 1
		list.Parent = columnFrame
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = list
		local subOrder = 1
		for _, def in ipairs(AbilitiesConfig.List or {}) do
			if tostring(def.targeting) == column.targeting then
				abilityCard(list, def, subOrder)
				subOrder += 1
			end
		end
	end
	return order + 1
end

local function renderGrenadeCard(order)
	local card = cardFrame(ui.loadoutSide, "Grenades", UDim2.new(1, 0, 0, 196), order, PANEL_INSET)
	makeText(card, "GRENADES", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	local y = 36
	for index, grenadeId in ipairs(state.grenades or {}) do
		local def = grenadeConfig(grenadeId) or { id = grenadeId, displayName = grenadeId, unlockRank = 1, cost = 0, damage = 0, radius = 0 }
		local owned = false
		for _, entry in ipairs(state.ownedGrenades or {}) do
			if entry == grenadeId then
				owned = true
			end
		end
		local equipped = state.loadout and state.loadout.grenade == grenadeId
		local locked = (tonumber(def.unlockRank) or 1) > (state.rank or 1)
		local row = plainFrame(card, "Grenade" .. tostring(grenadeId), UDim2.new(1, -24, 0, 66), UDim2.fromOffset(12, y), equipped and Color3.fromRGB(50, 39, 25) or PANEL_RAISED, 0)
		addStroke(row, equipped and AMBER or owned and CYAN or BORDER, equipped and 0 or 0.42, 1)
		makeText(row, string.upper(tostring(def.displayName or grenadeId)), "caption", UDim2.new(1, -150, 0, 18), UDim2.fromOffset(10, 8), WHITE, true)
		makeText(row, string.format("%d DMG · %dm RADIUS · RANK %d · %d CR", tonumber(def.damage) or 0, tonumber(def.radius) or 0, tonumber(def.unlockRank) or 1, tonumber(def.cost) or 0), "caption", UDim2.new(1, -150, 0, 15), UDim2.fromOffset(10, 32), locked and MUTED or AMBER, false)
		if equipped then
			statusTag(row, "equipped", "equipped", UDim2.new(1, -120, 0, 20), 108)
		elseif owned then
			local equip = makeButton(row, "EQUIP", "primary", UDim2.fromOffset(92, 40), UDim2.new(1, -102, 0, 13), function()
				setLoadout:FireServer({ action = "equipGrenade", id = tostring(grenadeId) })
			end)
			equip.Name = "Equip"
		elseif not locked then
			local buy = makeButton(row, "BUY", "ghost", UDim2.fromOffset(92, 40), UDim2.new(1, -102, 0, 13), function()
				setLoadout:FireServer({ action = "buyGrenade", id = tostring(grenadeId) })
			end)
			buy.Name = "Buy"
			buy.TextColor3 = AMBER
		else
			statusTag(row, "locked", "locked", UDim2.new(1, -108, 0, 20), 96)
		end
		y += 72
	end
	return order + 1
end

local function renderArmorQuickCard(order)
	local card = cardFrame(ui.loadoutSide, "ArmorQuick", UDim2.new(1, 0, 0, 116), order, PANEL_INSET)
	makeText(card, "ARMOR CUSTOMIZATION", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	local equippedId = state.loadout and state.loadout.armor or "STANDARD"
	local equippedSuit = nil
	for _, suit in ipairs(state.armor or {}) do
		if suit.id == equippedId then
			equippedSuit = suit
		end
	end
	local def = armorConfig(equippedId)
	makeText(card, string.upper(tostring((equippedSuit and equippedSuit.name) or (def and def.displayName) or equippedId)), "body", UDim2.new(1, -150, 0, 22), UDim2.fromOffset(12, 36), WHITE, true)
	makeText(card, string.format("%s kit  ·  armor fitting in section 03", tostring((equippedSuit and equippedSuit.tier) or "Standard")), "caption", UDim2.new(1, -150, 0, 16), UDim2.fromOffset(12, 62), MUTED, false)
	if def then
		local swatches = { def.plate, def.fatigue, def.accent, def.steel }
		for index, color in ipairs(swatches) do
			local swatch = plainFrame(card, "ArmorSwatch" .. index, UDim2.fromOffset(18, 18), UDim2.fromOffset(12 + (index - 1) * 23, 84), color, 0)
			addStroke(swatch, BORDER, 0.2, 1)
		end
	end
	local open = makeButton(card, "OPEN ARMOR", "primary", UDim2.fromOffset(116, 44), UDim2.new(1, -128, 0, 46), function()
		setSection("ARMOR")
	end)
	open.Name = "OpenArmor"
	return order + 1
end

local function renderLoadoutSide()
	clearScroll(ui.loadoutSide)
	local order = 1
	order = renderPresetCard(order)
	order = renderClassCard(order)
	order = renderAbilityModule(order)
	order = renderGrenadeCard(order)
	order = renderArmorQuickCard(order)
end

local function renderLoadout()
	renderWeaponList()
	renderWeaponDetail()
	renderLoadoutSide()
end

-- ---------------------------------------------------------------------------
-- AUGMENT renderers
-- ---------------------------------------------------------------------------
renderAugmentSockets = function()
	clearScroll(ui.augmentSockets)
	local weapon = weaponState(selectedWeaponId)
	if not weapon then
		return
	end
	local order = 1
	local summary = cardFrame(ui.augmentSockets, "SocketWeaponSummary", UDim2.new(1, 0, 0, 128), order, PANEL_RAISED)
	order += 1
	buildWeaponPreview(summary, weapon.id, UDim2.fromOffset(150, 82), UDim2.fromOffset(10, 28))
	makeText(summary, "SELECTED WEAPON", "caption", UDim2.new(1, -184, 0, 16), UDim2.fromOffset(174, 28), MUTED, true)
	makeText(summary, string.upper(tostring(weapon.name)), "body", UDim2.new(1, -184, 0, 24), UDim2.fromOffset(174, 48), WHITE, true)
	masteryPips(summary, state.masteryLevel and state.masteryLevel[weapon.id] or 0, UDim2.fromOffset(174, 86), 120, 12)
	order = addSocketInterface(ui.augmentSockets, weapon, order, true)
	sectionHeader(ui.augmentSockets, "compatible instances", order)
	order += 1
	for _, item in ipairs(compatibleAugments(weapon)) do
		local row = cardFrame(ui.augmentSockets, "SocketCompatible_" .. tostring(item.uid), UDim2.new(1, 0, 0, 68), order, PANEL_INSET)
		order += 1
		local rarityColor = RARITY_COLORS[item.rarity] or MUTED
		plainFrame(row, "RarityEdge", UDim2.fromOffset(4, 50), UDim2.fromOffset(0, 9), rarityColor, 0)
		makeText(row, tostring(item.name or item.id), "caption", UDim2.new(1, -24, 0, 17), UDim2.fromOffset(13, 8), WHITE, true)
		makeText(row, string.format("%s · q%d", tostring(item.rarity or "?"), math.clamp(tonumber(item.quality) or 0, 0, 1000)), "caption", UDim2.new(1, -24, 0, 15), UDim2.fromOffset(13, 30), rarityColor, true)
		makeText(row, tostring(item.traitText or "no traits"), "caption", UDim2.new(1, -24, 0, 14), UDim2.fromOffset(13, 48), MUTED, false)
	end
end

local function renderAugmentInstance(item, order)
	local card = cardFrame(ui.augmentInventory, "AugmentItem_" .. tostring(item.uid), UDim2.new(1, 0, 0, 150), order, item.protected and Color3.fromRGB(38, 30, 22) or PANEL_INSET)
	local rarityColor = RARITY_COLORS[item.rarity] or MUTED
	plainFrame(card, "RarityEdge", UDim2.fromOffset(5, 128), UDim2.fromOffset(0, 11), rarityColor, 0)
	makeText(card, string.format("%s · %s %s", item.name or item.id, item.rarity or "?", item.category or "?"), "body", UDim2.new(1, -150, 0, 20), UDim2.fromOffset(15, 8), WHITE, true)
	if item.favorite then
		statusTag(card, "selected", "fav", UDim2.new(1, -82, 0, 8), 66)
	end
	makeText(card, tostring(item.traitText or "no traits"), "caption", UDim2.new(1, -30, 0, 17), UDim2.fromOffset(15, 34), MUTED, false)
	makeText(card, string.format("uid %s%s%s", string.sub(tostring(item.uid), 1, 12), item.protected and " · PROTECTED" or "", item.pending and " · PENDING" or ""), "caption", UDim2.new(1, -30, 0, 14), UDim2.fromOffset(15, 55), item.pending and AMBER or DISABLED, false)
	local q = math.clamp(tonumber(item.quality) or 0, 0, 1000)
	qualityBar(card, q, UDim2.fromOffset(15, 82), 180)
	makeText(card, string.format("q%d/1000%s", q, q >= 1000 and " MAX" or ""), "caption", UDim2.fromOffset(110, 13), UDim2.fromOffset(204, 76), q >= 1000 and Color3.fromRGB(255, 210, 80) or MUTED, false)

	local actions = plainFrame(card, "Actions", UDim2.new(1, -28, 0, 42), UDim2.fromOffset(14, 96), PANEL_INSET, 1)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = actions
	local actionOrder = 1
	local fav = makeButton(actions, item.favorite and "UNFAV" or "FAV", "ghost", UDim2.fromOffset(62, 40), nil, function()
		setLoadout:FireServer({ action = "augmentFavorite", id = item.uid, favorite = not item.favorite })
	end)
	fav.LayoutOrder = actionOrder
	actionOrder += 1
	fav.TextColor3 = AMBER
	if item.rarity == "Epic" or item.rarity == "Legendary" then
		local lockCount = #(item.traits or {})
		if lockCount > 0 then
			local lockIndex = tonumber(rerollLockChoices[item.uid]) or 0
			local lockButton = makeButton(actions, lockIndex == 0 and "LOCK -" or string.format("LOCK %d", lockIndex), "ghost", UDim2.fromOffset(68, 40), nil, function()
				rerollLockChoices[item.uid] = lockIndex % lockCount + 1
				render()
			end)
			lockButton.Name = "RerollLock"
			lockButton.LayoutOrder = actionOrder
			actionOrder += 1
			lockButton.TextColor3 = AMBER
		end
	end
	local reroll = makeButton(actions, "REROLL", "primary", UDim2.fromOffset(78, 40), nil, function()
		local lockIndex = tonumber(rerollLockChoices[item.uid]) or 0
		setLoadout:FireServer({ action = "augmentReroll", id = item.uid, lockIndex = lockIndex > 0 and lockIndex or nil })
	end)
	reroll.LayoutOrder = actionOrder
	actionOrder += 1
	local fuse = makeButton(actions, "FUSE", "primary", UDim2.fromOffset(58, 40), nil, function()
		local inputs = { item.uid }
		for _, other in ipairs(state.augmentItems or {}) do
			if #inputs >= 3 then break end
			if other.uid ~= item.uid and other.rarity == item.rarity and other.category == item.category and not other.protected and not other.pending then
				table.insert(inputs, other.uid)
			end
		end
		setLoadout:FireServer({ action = "augmentFusePreview", inputs = inputs })
	end)
	fuse.LayoutOrder = actionOrder
	actionOrder += 1
	local scrap = makeButton(actions, "SCRAP", "ghost", UDim2.fromOffset(68, 40), nil, function()
		setLoadout:FireServer({ action = "augmentDismantle", id = item.uid })
	end)
	scrap.LayoutOrder = actionOrder
	scrap.TextColor3 = AMBER
	return order + 1
end

local function renderAugmentInventory()
	clearScroll(ui.augmentInventory)
	local order = 1
	local count = tonumber(state.augmentCount) or #(state.augmentItems or {})
	local capacity = tonumber(state.augmentCapacity) or 0
	local summary = cardFrame(ui.augmentInventory, "InventorySummary", UDim2.new(1, 0, 0, 54), order, PANEL_RAISED)
	order += 1
	makeText(summary, string.format("INSTANCE INVENTORY  ·  %d/%d CAPACITY", count, capacity), "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 9), CYAN, true)
	makeText(summary, "Exact rolled traits and quality are persisted per instance.", "caption", UDim2.new(1, -24, 0, 15), UDim2.fromOffset(12, 30), MUTED, false)
	for _, item in ipairs(state.augmentItems or {}) do
		order = renderAugmentInstance(item, order)
	end
	if #(state.augmentItems or {}) == 0 then
		local empty = cardFrame(ui.augmentInventory, "EmptyInventory", UDim2.new(1, 0, 0, 84), order, PANEL_INSET)
		makeText(empty, "INVENTORY EMPTY", "body", UDim2.new(1, -24, 0, 22), UDim2.fromOffset(12, 18), MUTED, true)
		makeText(empty, "Open caches or buy catalog entries to roll instances.", "caption", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 48), DISABLED, false)
	end
end

local function renderPendingReroll(order)
	if not state.pendingReroll then
		return order
	end
	local pending = state.pendingReroll
	local card = cardFrame(ui.augmentOps, "PendingReroll", UDim2.new(1, 0, 0, 142), order, Color3.fromRGB(35, 27, 18))
	order += 1
	local oldText = "old roll unavailable"
	for _, item in ipairs(state.augmentItems or {}) do
		if item.uid == pending.uid then
			oldText = item.traitText
		end
	end
	local newTraits = {}
	for _, trait in ipairs(pending.traits or {}) do
		local sign = (tonumber(trait.value) or 0) >= 0 and "+" or ""
		table.insert(newTraits, string.format("%s %s%.1f%% q%d", tostring(trait.key), sign, (tonumber(trait.value) or 0) * 100, tonumber(trait.quality) or 0))
	end
	makeText(card, "PENDING REROLL · COST ALREADY PAID", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), AMBER, true)
	makeText(card, "OLD  " .. tostring(oldText), "caption", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 36), MUTED, false)
	makeText(card, "NEW  " .. table.concat(newTraits, " · "), "caption", UDim2.new(1, -24, 0, 32), UDim2.fromOffset(12, 58), WHITE, false).TextWrapped = true
	local accept = makeButton(card, "ACCEPT", "primary", UDim2.new(0.5, -18, 0, 40), UDim2.fromOffset(12, 94), function()
		setLoadout:FireServer({ action = "augmentRerollAccept" })
	end)
	accept.Name = "Accept"
	local keep = makeButton(card, "KEEP", "ghost", UDim2.new(0.5, -18, 0, 40), UDim2.new(0.5, 6, 0, 94), function()
		setLoadout:FireServer({ action = "augmentRerollKeep" })
	end)
	keep.Name = "Keep"
	keep.TextColor3 = AMBER
	return order
end

local function renderFusionPreview(order)
	if not fusionPreview then
		return order
	end
	local card = cardFrame(ui.augmentOps, "FusionPreview", UDim2.new(1, 0, 0, 126), order, Color3.fromRGB(18, 28, 34))
	order += 1
	local names = {}
	for _, outcome in ipairs(fusionPreview.outcomes or {}) do
		table.insert(names, string.format("%s %.0f%%", tostring(outcome.name), (tonumber(outcome.chance) or 0) * 100))
	end
	makeText(card, string.format("FUSE 3 %s %s -> 1 %s", tostring(fusionPreview.fromRarity), tostring(fusionPreview.category), tostring(fusionPreview.toRarity)), "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	makeText(card, table.concat(names, " · "), "caption", UDim2.new(1, -24, 0, 30), UDim2.fromOffset(12, 34), MUTED, false).TextWrapped = true
	local confirm = makeButton(card, "CONFIRM", "primary", UDim2.new(0.5, -18, 0, 40), UDim2.fromOffset(12, 76), function()
		setLoadout:FireServer({ action = "augmentFuse", inputs = fusionPreview.uids })
		fusionPreview = nil
	end)
	confirm.Name = "ConfirmFusion"
	confirm.TextColor3 = AMBER
	local cancel = makeButton(card, "CANCEL", "ghost", UDim2.new(0.5, -18, 0, 40), UDim2.new(0.5, 6, 0, 76), function()
		fusionPreview = nil
		render()
	end)
	cancel.Name = "CancelFusion"
	return order
end

local function renderBulkDismantle(order)
	local card = cardFrame(ui.augmentOps, "BulkDismantle", UDim2.new(1, 0, 0, 182), order, Color3.fromRGB(24, 22, 25))
	order += 1
	makeText(card, "BULK DISMANTLE", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), AMBER, true)
	local bulkRarity = BULK_RARITIES[bulkRarityIndex] or "ALL"
	local bulkCategory = CACHE_CATEGORIES[bulkCategoryIndex] or "ANY"
	local rarityButton = makeButton(card, "R:" .. bulkRarity, "ghost", UDim2.new(0.5, -18, 0, 36), UDim2.fromOffset(12, 34), function()
		bulkRarityIndex = bulkRarityIndex % #BULK_RARITIES + 1
		bulkPreview = nil
		render()
	end)
	rarityButton.Name = "BulkRarityFilter"
	rarityButton.TextColor3 = AMBER
	local catButton = makeButton(card, "C:" .. bulkCategory, "ghost", UDim2.new(0.5, -18, 0, 36), UDim2.new(0.5, 6, 0, 34), function()
		bulkCategoryIndex = bulkCategoryIndex % #CACHE_CATEGORIES + 1
		bulkPreview = nil
		render()
	end)
	catButton.Name = "BulkCategoryFilter"
	catButton.TextColor3 = AMBER
	local previewButton = makeButton(card, "PREVIEW", "primary", UDim2.new(1, -24, 0, 36), UDim2.fromOffset(12, 76), function()
		setLoadout:FireServer({ action = "augmentDismantleBulk", rarity = bulkRarity, category = bulkCategory })
	end)
	previewButton.Name = "Preview"
	local matches = bulkPreview and bulkPreview.rarity == bulkRarity and bulkPreview.category == bulkCategory
	local label = matches and string.format("%d items · +%d scrap · %d protected", tonumber(bulkPreview.count) or 0, tonumber(bulkPreview.scrap) or 0, tonumber(bulkPreview.skipped) or 0) or "Run preview before confirmation."
	makeText(card, label, "caption", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 120), matches and WHITE or MUTED, false)
	if matches and (tonumber(bulkPreview.count) or 0) > 0 then
		local confirm = makeButton(card, "CONFIRM", "primary", UDim2.new(1, -24, 0, 36), UDim2.fromOffset(12, 140), function()
			setLoadout:FireServer({ action = "augmentDismantleBulk", rarity = bulkRarity, category = bulkCategory, confirm = true })
			bulkPreview = nil
		end)
		confirm.Name = "BulkDismantleConfirm"
		confirm.TextColor3 = AMBER
	end
	return order
end

local function renderAugmentCatalog(order)
	sectionHeader(ui.augmentOps, "augment catalog", order)
	order += 1
	for _, aug in ipairs(state.augmentCatalog or {}) do
		local def = AugmentsConfig.get and AugmentsConfig.get(aug.id) or nil
		local row = cardFrame(ui.augmentOps, "Catalog_" .. tostring(aug.id), UDim2.new(1, 0, 0, 76), order, PANEL_INSET)
		order += 1
		local isCore = tostring(aug.role or "") == "Core"
		local rarityColor = RARITY_COLORS[def and def.rarity or "Common"] or MUTED
		plainFrame(row, "RoleEdge", UDim2.fromOffset(4, 58), UDim2.fromOffset(0, 9), isCore and CYAN or AMBER, 0)
		makeText(row, string.format("%s  ·  %s", tostring(aug.name), isCore and "CORE" or "AUX"), "caption", UDim2.new(1, -128, 0, 18), UDim2.fromOffset(13, 7), WHITE, true)
		makeText(row, string.format("%s · %s · %s", tostring((def and def.category) or aug.description or "?"), tostring((def and def.rarity) or "?"), tostring(aug.id)), "caption", UDim2.new(1, -128, 0, 15), UDim2.fromOffset(13, 30), rarityColor, false)
		if aug.owned then
			makeText(row, "OWNED · COPIES ALLOWED", "caption", UDim2.new(1, -128, 0, 13), UDim2.fromOffset(13, 51), CYAN, true)
		else
			makeText(row, "UNOWNED ARCHETYPE", "caption", UDim2.new(1, -128, 0, 13), UDim2.fromOffset(13, 51), MUTED, false)
		end
		local buy = makeButton(row, string.format("BUY %d", aug.cost or 0), "ghost", UDim2.fromOffset(96, 42), UDim2.new(1, -108, 0, 17), function()
			setLoadout:FireServer({ action = "augmentBuy", id = aug.id })
		end)
		buy.Name = "Buy"
		buy.TextColor3 = AMBER
	end
	return order
end

local function renderAugmentOps()
	clearScroll(ui.augmentOps)
	local order = 1
	local capacityCard = cardFrame(ui.augmentOps, "InventoryExpansion", UDim2.new(1, 0, 0, 104), order, PANEL_RAISED)
	order += 1
	makeText(capacityCard, "INVENTORY CAPACITY", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	makeText(capacityCard, string.format("%d/%d instances", tonumber(state.augmentCount) or #(state.augmentItems or {}), tonumber(state.augmentCapacity) or 0), "body", UDim2.new(0.48, 0, 0, 24), UDim2.fromOffset(12, 34), WHITE, true)
	local expand = makeButton(capacityCard, "EXPAND +50", "primary", UDim2.fromOffset(128, 44), UDim2.new(1, -140, 0, 34), function()
		setLoadout:FireServer({ action = "expandAugmentInventory" })
	end)
	expand.Name = "Expand"
	expand.TextColor3 = AMBER
	order = renderPendingReroll(order)
	order = renderFusionPreview(order)
	order = renderBulkDismantle(order)
	order = renderAugmentCatalog(order)
end

local function renderAugments()
	renderAugmentSockets()
	renderAugmentInventory()
	renderAugmentOps()
end

-- ---------------------------------------------------------------------------
-- ARMOR renderers
-- ---------------------------------------------------------------------------
local function renderArmorList()
	clearScroll(ui.armorList)
	for index, suit in ipairs(state.armor or {}) do
		local selected = suit.id == selectedArmorId
		local def = armorConfig(suit.id)
		local row = Instance.new("TextButton")
		row.Name = "ArmorRow_" .. tostring(suit.id)
		row.Size = UDim2.new(1, 0, 0, 76)
		row.BackgroundColor3 = selected and Color3.fromRGB(48, 39, 27) or suit.equipped and Color3.fromRGB(20, 37, 45) or PANEL_INSET
		row.BorderSizePixel = 0
		row.AutoButtonColor = false
		row.Text = ""
		row.LayoutOrder = index
		row.Parent = ui.armorList
		addStroke(row, selected and AMBER or suit.equipped and CYAN or BORDER, selected and 0 or 0.52, 1)
		if selected then
			plainFrame(row, "SelectionBar", UDim2.fromOffset(4, 58), UDim2.fromOffset(0, 9), AMBER, 0)
		end
		if def then
			local x = 14
			for _, color in ipairs({ def.plate, def.fatigue, def.accent }) do
				local swatch = plainFrame(row, "KitSwatch", UDim2.fromOffset(22, 42), UDim2.fromOffset(x, 17), color, 0)
				addStroke(swatch, BORDER, 0.35, 1)
				x += 25
			end
		end
		makeText(row, string.upper(tostring(suit.name)), "body", UDim2.new(1, -220, 0, 20), UDim2.fromOffset(98, 10), WHITE, true)
		makeText(row, string.format("%s · RANK %d · %d CR", tostring(suit.tier), tonumber(suit.rank) or 1, tonumber(suit.cost) or 0), "caption", UDim2.new(1, -220, 0, 16), UDim2.fromOffset(98, 36), MUTED, false)
		local locks = lockReasons(suit, state.rank or 1)
		local statusText = suit.equipped and "WORN" or suit.owned and "OWNED" or (#locks > 0 and "LOCKED" or "BUY")
		local statusKind = suit.equipped and "equipped" or suit.owned and "owned" or (#locks > 0 and "locked" or "warning")
		statusTag(row, statusKind, statusText, UDim2.new(1, -104, 0, 12), 92)
		row.Activated:Connect(function()
			selectedArmorId = suit.id
			renderArmor()
		end)
	end
end

local function renderArmorDetail()
	clearScroll(ui.armorDetail)
	local suit = nil
	for _, row in ipairs(state.armor or {}) do
		if row.id == selectedArmorId then
			suit = row
		end
	end
	if not suit then
		return
	end
	local def = armorConfig(suit.id) or {}
	local order = 1
	local hero = cardFrame(ui.armorDetail, "ArmorHero", UDim2.new(1, 0, 0, 330), order, PANEL_RAISED)
	order += 1
	buildArmorPreview(hero, suit.id, UDim2.new(1, -20, 1, -64), UDim2.fromOffset(10, 10))
	local overlay = plainFrame(hero, "ArmorOverlay", UDim2.new(1, -20, 0, 42), UDim2.new(0, 10, 1, -52), Color3.fromRGB(8, 12, 18), 0.18)
	addStroke(overlay, BORDER, 0.62, 1)
	makeText(overlay, string.upper(tostring(suit.name)), "body", UDim2.new(0.65, 0, 1, 0), UDim2.fromOffset(12, 0), WHITE, true)
	makeText(overlay, string.upper(tostring(suit.tier)), "caption", UDim2.new(0.3, -8, 1, 0), UDim2.new(0.68, 0, 0, 0), CYAN, true)

	local statusCard = cardFrame(ui.armorDetail, "ArmorStatus", UDim2.new(1, 0, 0, 124), order, PANEL_INSET)
	order += 1
	local locks = lockReasons(suit, state.rank or 1)
	if suit.equipped then
		statusTag(statusCard, "equipped", "worn", UDim2.fromOffset(12, 12), 92)
	elseif suit.owned then
		statusTag(statusCard, "owned", "owned", UDim2.fromOffset(12, 12), 96)
	elseif #locks > 0 then
		statusTag(statusCard, "locked", "locked", UDim2.fromOffset(12, 12), 104)
	else
		statusTag(statusCard, "warning", "available", UDim2.fromOffset(12, 12), 108)
	end
	makeText(statusCard, string.format("RANK %d  ·  %d CR", tonumber(suit.rank) or 1, tonumber(suit.cost) or 0), "caption", UDim2.new(1, -190, 0, 18), UDim2.fromOffset(12, 44), AMBER, true)
	if #locks > 0 then
		makeText(statusCard, table.concat(locks, "  ·  "), "caption", UDim2.new(1, -190, 0, 16), UDim2.fromOffset(12, 68), MUTED, true)
	else
		makeText(statusCard, "Armor is cosmetic customization; no paid power or passive stat advantage.", "caption", UDim2.new(1, -190, 0, 32), UDim2.fromOffset(12, 66), MUTED, false).TextWrapped = true
	end
	if suit.owned and not suit.equipped then
		local wear = makeButton(statusCard, "WEAR", "primary", UDim2.fromOffset(142, 52), UDim2.new(1, -154, 0, 22), function()
			setLoadout:FireServer({ action = "equipArmor", id = suit.id })
		end)
		wear.Name = "Wear"
	elseif not suit.owned and #locks == 0 then
		local buy = makeButton(statusCard, string.format("BUY %d", tonumber(suit.cost) or 0), "primary", UDim2.fromOffset(142, 52), UDim2.new(1, -154, 0, 22), function()
			setLoadout:FireServer({ action = "buyArmor", id = suit.id })
		end)
		buy.Name = "Buy"
		buy.TextColor3 = AMBER
	end

	local materials = cardFrame(ui.armorDetail, "ArmorMaterials", UDim2.new(1, 0, 0, 150), order, PANEL_RAISED)
	makeText(materials, "MATERIAL CHANNELS", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	local channels = {
		{ name = "PLATE", color = def.plate or WHITE },
		{ name = "FATIGUE", color = def.fatigue or PANEL_RAISED },
		{ name = "ACCENT", color = def.accent or CYAN },
		{ name = "STEEL", color = def.steel or MUTED },
	}
	for index, channel in ipairs(channels) do
		local x = 12 + (index - 1) * 126
		local swatch = plainFrame(materials, "Channel" .. channel.name, UDim2.fromOffset(100, 54), UDim2.fromOffset(x, 42), channel.color, 0)
		addStroke(swatch, BORDER, 0.25, 1)
		makeText(materials, channel.name, "caption", UDim2.fromOffset(100, 16), UDim2.fromOffset(x, 104), WHITE, true)
	end
end

renderArmor = function()
	renderArmorList()
	renderArmorDetail()
end

-- ---------------------------------------------------------------------------
-- SUPPLY / REQUISITION renderers
-- ---------------------------------------------------------------------------
local function cacheOddsText()
	local oddsList = state.cacheOdds
	local oddsText = "ODDS  no cache held"
	if oddsList and #oddsList > 0 then
		local lines = {}
		for _, odds in ipairs(oddsList) do
			local parts = {}
			for _, rarity in ipairs({ "Common", "Rare", "Epic", "Legendary" }) do
				local per = odds.perDraw and odds.perDraw[rarity]
				if per then
					parts[#parts + 1] = string.format("%s %.1f%%", rarity, per)
				end
			end
			local best = odds.atLeastOne and odds.atLeastOne.Legendary
			lines[#lines + 1] = string.format("%s x%d held %d  ·  %s  ·  Leg %.1f%%", tostring(odds.tier), odds.draws or 1, odds.held or 0, table.concat(parts, " · "), best or 0)
		end
		oddsText = table.concat(lines, "   ||   ")
	end
	return oddsText, oddsList
end

local function renderCaches()
	clearScroll(ui.cacheList)
	local order = 1
	local categoryCard = cardFrame(ui.cacheList, "CacheTargeting", UDim2.new(1, 0, 0, 110), order, PANEL_RAISED)
	order += 1
	makeText(categoryCard, "TARGETED CACHE CATEGORY", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	makeText(categoryCard, "Category targeting consumes scrap after the first free targeted open.", "caption", UDim2.new(1, -24, 0, 30), UDim2.fromOffset(12, 28), MUTED, false).TextWrapped = true
	local firstCache = (state.caches or {})[1]
	local catButton = makeButton(categoryCard, firstCache and targetingCostLabel(firstCache.id) or "CAT ANY", "primary", UDim2.new(1, -24, 0, 34), UDim2.fromOffset(12, 66), function()
		cacheCategoryIndex = cacheCategoryIndex % #CACHE_CATEGORIES + 1
		render()
	end)
	catButton.Name = "CacheCategory"
	catButton.TextColor3 = AMBER

	sectionHeader(ui.cacheList, "held caches", order)
	order += 1
	for _, cache in ipairs(state.caches or {}) do
		local row = cardFrame(ui.cacheList, "Cache" .. tostring(cache.id), UDim2.new(1, 0, 0, 96), order, PANEL_INSET)
		order += 1
		makeText(row, string.upper(tostring(cache.name)), "body", UDim2.new(1, -132, 0, 20), UDim2.fromOffset(12, 10), WHITE, true)
		makeText(row, string.format("%d HELD  ·  %s", tonumber(cache.held) or 0, targetingCostLabel(cache.id)), "caption", UDim2.new(1, -132, 0, 16), UDim2.fromOffset(12, 38), AMBER, true)
		makeText(row, "Server roll occurs before reveal presentation.", "caption", UDim2.new(1, -132, 0, 14), UDim2.fromOffset(12, 62), MUTED, false)
		if (tonumber(cache.held) or 0) > 0 then
			local openButton = makeButton(row, "OPEN", "primary", UDim2.fromOffset(96, 48), UDim2.new(1, -108, 0, 24), function()
				setLoadout:FireServer({ action = "openCache", tier = cache.id, category = selectedCacheCategory() })
			end)
			openButton.Name = "Open"
		else
			statusTag(row, "locked", "none", UDim2.new(1, -96, 0, 32), 84)
		end
	end

	local actions = cardFrame(ui.cacheList, "CacheBulkActions", UDim2.new(1, 0, 0, 122), order, PANEL_RAISED)
	order += 1
	makeText(actions, "BULK OPERATIONS", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	local heldTier, heldCount = nil, 0
	for tierId, count in pairs(state.cacheCounts or {}) do
		if type(count) == "number" and count > heldCount then
			heldTier, heldCount = tierId, count
		end
	end
	local bulkOpen = makeButton(actions, heldTier and string.format("OPEN 10 · %s x%d", heldTier, heldCount) or "NO CACHES", "primary", UDim2.new(1, -24, 0, 42), UDim2.fromOffset(12, 34), function()
		if heldTier then
			setLoadout:FireServer({ action = "bulkOpenCache", id = heldTier, category = selectedCacheCategory() })
		end
	end)
	bulkOpen.Name = "BulkOpen"
	makeText(actions, "Results mirror workspace cache attributes into the status strip.", "caption", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 86), MUTED, false)

	local oddsCard = cardFrame(ui.cacheList, "CacheOdds", UDim2.new(1, 0, 0, 142), order, PANEL_INSET)
	order += 1
	makeText(oddsCard, "TRUE ODDS DISCLOSURE", "caption", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 8), CYAN, true)
	local oddsText, oddsList = cacheOddsText()
	local body = makeText(oddsCard, oddsText, "caption", UDim2.new(1, -24, 0, 74), UDim2.fromOffset(12, 32), MUTED, false)
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	if oddsList and oddsList[1] and type(oddsList[1].dropChance) == "table" then
		local drops = {}
		for _, cls in ipairs({ "infantry", "heavy", "commander" }) do
			local c = oddsList[1].dropChance[cls]
			if c then
				drops[#drops + 1] = string.format("%s %.0f%%", cls, c * 100)
			end
		end
		makeText(oddsCard, string.format("DROP %s  ·  %s", tostring(oddsList[1].tier), table.concat(drops, " · ")), "caption", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, 114), AMBER, false)
	end
end

local function renderRequisitions()
	clearScroll(ui.requisitionList)
	local order = 1
	for _, req in ipairs(state.requisitions or {}) do
		local header = cardFrame(ui.requisitionList, "Requisition_" .. tostring(req.id), UDim2.new(1, 0, 0, 96), order, req.premium and Color3.fromRGB(32, 27, 39) or Color3.fromRGB(20, 29, 35))
		order += 1
		plainFrame(header, "ReqEdge", UDim2.fromOffset(5, 76), UDim2.fromOffset(0, 10), req.premium and AMBER or CYAN, 0)
		makeText(header, "REQUISITION · " .. string.upper(tostring(req.displayName)), "body", UDim2.new(1, -190, 0, 21), UDim2.fromOffset(15, 10), req.premium and AMBER or CYAN, true)
		local progress = (tonumber(req.tier) or 1) >= 3 and "TIER 3 · MAX" or string.format("TIER %d · %d/%d CR", tonumber(req.tier) or 1, tonumber(req.spend) or 0, tonumber(req.nextTierAt) or 0)
		makeText(header, string.format("%s  ·  %d WC", progress, tonumber(state.warCredits) or 0), "caption", UDim2.new(1, -190, 0, 16), UDim2.fromOffset(15, 40), MUTED, true)
		makeText(header, "Rank gates remain separate from tier gates.", "caption", UDim2.new(1, -190, 0, 15), UDim2.fromOffset(15, 64), DISABLED, false)
		if req.unlocked then
			statusTag(header, "owned", "unlocked", UDim2.new(1, -142, 0, 22), 124)
		else
			local unlock = makeButton(header, string.format("UNLOCK %d WC", tonumber(req.unlockWarCredits) or 0), "primary", UDim2.fromOffset(150, 52), UDim2.new(1, -164, 0, 22), function()
				setLoadout:FireServer({ action = "reqUnlock", reqId = req.id })
			end)
			unlock.Name = "Unlock"
			unlock.TextColor3 = AMBER
		end
		for _, entry in ipairs(req.entries or {}) do
			local entryRow = cardFrame(ui.requisitionList, "RequisitionEntry_" .. tostring(req.id) .. "_" .. tostring(entry.key), UDim2.new(1, 0, 0, 70), order, PANEL_INSET)
			order += 1
			plainFrame(entryRow, "TierEdge", UDim2.fromOffset(3, 52), UDim2.fromOffset(0, 9), BORDER, 0)
			makeText(entryRow, string.format("T%d · %s", tonumber(entry.tier) or 1, tostring(entry.name)), "caption", UDim2.new(1, -158, 0, 18), UDim2.fromOffset(13, 8), WHITE, true)
			makeText(entryRow, string.format("%s · RANK %d · %d CR", string.upper(tostring(entry.kind)), tonumber(entry.rank) or 1, tonumber(entry.cost) or 0), "caption", UDim2.new(1, -158, 0, 15), UDim2.fromOffset(13, 33), MUTED, false)
			local status = nil
			if entry.onceUsed then
				status = "CLAIMED"
			elseif entry.owned then
				status = "OWNED"
			elseif not req.unlocked then
				status = "PREVIEW"
			elseif entry.tierLocked or entry.rankLocked then
				local locks = {}
				if entry.tierLocked then table.insert(locks, "TIER " .. tostring(entry.tier)) end
				if entry.rankLocked then table.insert(locks, "RANK " .. tostring(entry.rank)) end
				status = "LOCKED · " .. table.concat(locks, " · ")
			end
			if status then
				local color = entry.owned and CYAN or MUTED
				local label = makeText(entryRow, status, "caption", UDim2.fromOffset(142, 18), UDim2.new(1, -152, 0, 26), color, true)
				label.TextXAlignment = Enum.TextXAlignment.Right
			else
				local buy = makeButton(entryRow, (tonumber(entry.cost) or 0) > 0 and string.format("BUY %d", tonumber(entry.cost) or 0) or "CLAIM", "primary", UDim2.fromOffset(124, 42), UDim2.new(1, -136, 0, 14), function()
					setLoadout:FireServer({ action = "reqBuy", reqId = req.id, key = entry.key })
				end)
				buy.Name = "Buy"
				buy.TextColor3 = AMBER
			end
		end
	end
end

local function renderSupply()
	renderCaches()
	renderRequisitions()
end

-- ---------------------------------------------------------------------------
-- Header and top-level render
-- ---------------------------------------------------------------------------
local function renderHeader()
	local xpText = "MAX"
	local xpRatio = 1
	if type(state.xp) == "number" and type(state.xpForNext) == "number" and state.xpForNext > 0 then
		xpText = string.format("%d/%d XP", state.xp, state.xpForNext)
		xpRatio = math.clamp(state.xp / state.xpForNext, 0, 1)
	end
	creditsLabel.Text = string.format("%d CR   ·   RANK %d", tonumber(state.credits) or 0, tonumber(state.rank) or 1)
	walletLabel.Text = string.format("WALLET  %d CREDITS · %d SCRAP · %d ENERGY CELLS · %d MILITARY TECH · %d WAR CREDITS",
		tonumber(state.credits) or 0,
		tonumber(state.scrap) or 0,
		tonumber(state.energyCells) or 0,
		tonumber(state.militaryTechnology) or 0,
		tonumber(state.warCredits) or 0)
	ui.xpLabel.Text = xpText
	ui.xpFill.Size = UDim2.new(xpRatio, 0, 1, 0)
	ui.xpFill.BackgroundColor3 = xpRatio >= 1 and AMBER or CYAN
end

render = function()
	if not state then
		return
	end
	ensureSelections()
	renderHeader()
	renderLoadout()
	renderAugments()
	renderArmor()
	renderSupply()
end

-- ---------------------------------------------------------------------------
-- Attribute feedback and cache reveal. These are connected once outside the
-- render pass; the payload/attribute names are unchanged from the legacy UI.
-- ---------------------------------------------------------------------------
local function showStatus(text, colour)
	if ui.statusLabel then
		ui.statusLabel.Text = text
		ui.statusLabel.TextColor3 = colour
	end
end

workspace:GetAttributeChangedSignal("GF_AugmentExpandResult"):Connect(function()
	local v = workspace:GetAttribute("GF_AugmentExpandResult")
	if v then
		showStatus("EXPANSION " .. tostring(v), CYAN)
	end
end)

local function playCacheReveal(tierText)
	ui.revealSkip = false
	ui.revealFrame.Visible = true
	ui.revealLabel.Text = "OPENING CACHE"
	ui.revealResult.Text = ""
	local rarity = tostring(tierText):match("(%a+)$") or "Common"
	local col = RARITY_COLORS[rarity] or RARITY_COLORS.Common
	ui.revealGlow.BackgroundColor3 = col
	pcall(function()
		require(script.Parent:WaitForChild("GFAudio")).play(rarity == "Legendary" and "ui_click" or "ui_click")
	end)
	local t0 = os.clock()
	while os.clock() - t0 < 2.0 and not ui.revealSkip do
		ui.revealGlow.BackgroundTransparency = 0.2 + 0.5 * math.abs(math.sin((os.clock() - t0) * 6))
		task.wait(0.05)
	end
	ui.revealGlow.BackgroundTransparency = 0
	ui.revealLabel.Text = "CACHE OPENED"
end

workspace:GetAttributeChangedSignal("GF_CacheOpened"):Connect(function()
	local v = workspace:GetAttribute("GF_CacheOpened")
	if type(v) == "string" and ui.revealFrame.Visible ~= true then
		task.spawn(function()
			playCacheReveal(v)
			ui.revealResult.Text = tostring(v)
			task.delay(2.5, function()
				ui.revealFrame.Visible = false
			end)
		end)
	end
end)

workspace:GetAttributeChangedSignal("GF_BulkOpenResult"):Connect(function()
	local v = workspace:GetAttribute("GF_BulkOpenResult")
	if v then
		showStatus(string.format("OPENED %s CACHE(S)", tostring(v)), CYAN)
	end
end)

-- ---------------------------------------------------------------------------
-- Open/close and remote wiring — same remotes, payload actions, and fields.
-- ---------------------------------------------------------------------------
local function setOpen(open)
	isOpen = open
	panel.Visible = open
	if open then
		render()
	end
end

ui.closeButton.Activated:Connect(function()
	setOpen(false)
end)

requestLoadout.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.preview then
		bulkPreview = payload.preview
	end
	if payload.fusionPreview then
		fusionPreview = payload.fusionPreview
	elseif payload.action == "augmentFuse" then
		fusionPreview = nil
	end
	if payload.state then
		state = payload.state
		if isOpen then render() end
	elseif payload.ok == false and isOpen then
		creditsLabel.Text = tostring(payload.reason)
		showStatus(tostring(payload.reason), AMBER)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.E then return end
	if isOpen then
		setOpen(false)
		return
	end
	if not anchor then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if (hrp.Position - anchor.Position).Magnitude <= OPEN_RANGE then
		setOpen(true)
		requestLoadout:FireServer()
	end
end)

RunService.Heartbeat:Connect(function()
	if not anchor or not anchor.Parent then
		anchor = findAnchor()
	end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or not anchor then
		prompt.Visible = false
		return
	end
	local near = (hrp.Position - anchor.Position).Magnitude <= OPEN_RANGE
	-- The Heartbeat is the loop that demonstrably runs; the attribute hook and the prompt both route the
	-- open request through here rather than through a one-shot signal.
	if workspace:GetAttribute("GF_ArmoryOpen") == true and not isOpen then
		setOpen(true)
	end
	prompt.Visible = near and not isOpen
	-- A forced open (QA / scripted onboarding) must not be closed by walking away, otherwise the panel
	-- flickers shut on the next frame whenever the character is not standing at the rack.
	if not near and isOpen and workspace:GetAttribute("GF_ArmoryOpen") ~= true then
		setOpen(false)
	end
end)

-- Touch and gamepad cannot press E, so the rack prompt opens the same panel through this remote.
local openRemote = game:GetService("ReplicatedStorage"):FindFirstChild("GF")
openRemote = openRemote and openRemote:FindFirstChild("Remotes")
openRemote = openRemote and openRemote:FindFirstChild("OpenArmoryPanel")
if openRemote and openRemote:IsA("RemoteEvent") then
	openRemote.OnClientEvent:Connect(function()
		setOpen(true)
		requestLoadout:FireServer()
	end)
end

-- Deterministic open hook: a server-set attribute (used by QA and by any future forced-onboarding flow)
-- opens or closes the panel, so the Armory is not reachable only through a keyboard press.
workspace:GetAttributeChangedSignal("GF_ArmoryOpen"):Connect(function()
	local want = workspace:GetAttribute("GF_ArmoryOpen") == true
	if want ~= isOpen then
		setOpen(want)
		if want then
			requestLoadout:FireServer()
		end
	end
end)

task.spawn(function()
	while not anchor do
		task.wait(0.5)
		anchor = findAnchor()
	end
	requestLoadout:FireServer()
end)
