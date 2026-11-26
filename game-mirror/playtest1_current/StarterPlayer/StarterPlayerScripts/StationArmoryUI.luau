--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local requestLoadout = remotes:WaitForChild("RequestLoadout")
local setLoadout = remotes:WaitForChild("SetLoadout")

local CYAN = Color3.fromRGB(120, 226, 255)
local AMBER = Color3.fromRGB(255, 186, 84)
local INK = Color3.fromRGB(8, 12, 18)
local PANEL = Color3.fromRGB(14, 19, 26)
local MUTED = Color3.fromRGB(150, 166, 182)
local WHITE = Color3.fromRGB(232, 240, 248)
local OPEN_RANGE = 46

local gui
local prompt
local isOpen = false
local state = nil
local anchor = nil
local CACHE_CATEGORIES = { "ANY", "Universal", "AR", "SMG", "LMG", "Shotgun", "Marksman", "Launcher", "Pistol", "Support" }
local cacheCategoryIndex = 1
local rerollLockChoices = {}
local BULK_RARITIES = { "ALL", "Common", "Rare", "Epic", "Legendary" }
local bulkRarityIndex = 1
local bulkCategoryIndex = 1
local bulkPreview = nil
local fusionPreview = nil

local function selectedCacheCategory()
	local value = CACHE_CATEGORIES[cacheCategoryIndex] or "ANY"
	return value ~= "ANY" and value or nil
end

local function newFrame(parent, props)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = props.color or PANEL
	f.BackgroundTransparency = props.transparency or 0
	f.BorderSizePixel = 0
	f.Size = props.size
	f.Position = props.pos or UDim2.fromOffset(0, 0)
	f.Parent = parent
	if props.radius then local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, props.radius); c.Parent = f end
	return f
end

local function newLabel(parent, text, size, pos, color, textSize)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Size = size
	l.Position = pos
	l.TextColor3 = color or WHITE
	l.TextSize = textSize or 14
	l.Font = Enum.Font.GothamMedium
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

-- 3D weapon previews: the premium library models render inside row ViewportFrames.
-- Framing follows the bounding-box math from the visual directive: camera distance is
-- derived from the model extents and the viewport FOV, not hard-coded per weapon.
local WeaponVisuals = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("WeaponVisuals"))

local function buildWeaponPreview(parent: Frame, weaponId: string, size: UDim2, pos: UDim2)
	local vp = Instance.new("ViewportFrame")
	vp.Size = size
	vp.Position = pos
	vp.BackgroundColor3 = Color3.fromRGB(10, 14, 20)
	vp.BorderSizePixel = 0
	vp.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = vp
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local model = WeaponVisuals.build(weaponId)
	if not model then
		return vp
	end
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

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "GF_Armory"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Enabled = true
	gui.Parent = playerGui

	prompt = newFrame(gui, { size = UDim2.fromOffset(240, 34), pos = UDim2.new(0.5, -120, 1, -178), radius = 4, transparency = 0.15 })
	prompt.Visible = false
	newLabel(prompt, "ARMORY  [E]", UDim2.fromOffset(228, 30), UDim2.fromOffset(14, 7), CYAN, 16)

	local panel = newFrame(gui, { size = UDim2.fromOffset(560, 430), pos = UDim2.new(0.5, -280, 0.5, -215), radius = 6 })
	panel.Name = "Panel"
	panel.Visible = false
	
	newFrame(panel, { size = UDim2.fromOffset(560, 3), color = CYAN })
	newLabel(panel, "ARMORY", UDim2.fromOffset(200, 22), UDim2.fromOffset(20, 14), CYAN, 18)
	local credits = newLabel(panel, "", UDim2.fromOffset(290, 20), UDim2.fromOffset(190, 16), AMBER, 13)
	credits.Name = "Credits"
	newLabel(panel, "CLOSE [E]", UDim2.fromOffset(84, 20), UDim2.fromOffset(494, 16), MUTED, 11)
	-- Unified wallet strip (economy spec §92): all five resources in one labeled row so players
	-- never memorize abstract icons. Sits under the title row; the list shifted down to make room.
	local wallet = newLabel(panel, "", UDim2.fromOffset(524, 16), UDim2.fromOffset(18, 34), Color3.fromRGB(200, 205, 215), 11)
	wallet.Name = "Wallet"

	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromOffset(524, 272)
	list.Position = UDim2.fromOffset(18, 58)
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	
	return panel, list, credits, wallet
end

local panel, list, creditsLabel, walletLabel = buildGui()

local function rowButton(parent, text, color, layoutOrder, onClick, xPos, width)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width or 92, 30)
	b.Position = UDim2.fromOffset(xPos or 420, 9)
	b.BackgroundColor3 = Color3.fromRGB(24, 34, 46)
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = color
	b.TextSize = 13
	b.Font = Enum.Font.GothamBold
	b.LayoutOrder = layoutOrder
	b.Parent = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 3); c.Parent = b
	b.MouseButton1Click:Connect(onClick)
	return b
end

local function render()
	if not state then return end
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	-- Show where the rank actually is. "RANK 15" with no XP figure told a player nothing about why ER-16 was
-- locked; the header now carries progress to the next rank.
local xpText = "MAX"
if type(state.xp) == "number" and type(state.xpForNext) == "number" then
	xpText = string.format("%d/%d XP", state.xp, state.xpForNext)
end
creditsLabel.Text = string.format("%d CR   ·   RANK %d   ·   %s", state.credits, state.rank, xpText)
	-- §92 unified wallet: every resource named in words, no icon memorization required.
	walletLabel.Text = string.format("WALLET   %d CREDITS · %d SCRAP · %d ENERGY CELLS · %d MILITARY TECH · %d WAR CREDITS",
		tonumber(state.credits) or 0,
		tonumber(state.scrap) or 0,
		tonumber(state.energyCells) or 0,
		tonumber(state.militaryTechnology) or 0,
		tonumber(state.warCredits) or 0)
	local order = 0
	-- Saved loadouts. The server has supported three slots since build 417 and no player could reach
	-- them; these two buttons per slot are the whole surface (Save writes the live loadout, Load restores).
	for slot = 1, 3 do
		order += 1
		local slotRow = newFrame(list, { size = UDim2.fromOffset(516, 40), radius = 3, color = Color3.fromRGB(16, 22, 29) })
		slotRow.Name = string.format("Loadout%d", slot)
		slotRow.LayoutOrder = order
		newLabel(slotRow, string.format("LOADOUT %d", slot), UDim2.fromOffset(160, 18), UDim2.fromOffset(12, 10), WHITE, 14)
		local saveButton = rowButton(slotRow, "SAVE", AMBER, order, function()
			setLoadout:FireServer({ action = "saveLoadout", slot = slot })
		end, 300)
		saveButton.Name = "Save"
		local loadButton = rowButton(slotRow, "LOAD", CYAN, order, function()
			setLoadout:FireServer({ action = "loadLoadout", slot = slot })
		end, 400)
		loadButton.Name = "Load"
	end
	order = 99
	for _, w in ipairs(state.weapons) do
	
	order += 1
		local row = newFrame(list, { size = UDim2.fromOffset(516, 48), radius = 3, color = Color3.fromRGB(20, 27, 35) })
		row.LayoutOrder = order
		buildWeaponPreview(row, w.id, UDim2.fromOffset(76, 44), UDim2.fromOffset(2, 2))
		newLabel(row, w.name, UDim2.fromOffset(230, 18), UDim2.fromOffset(84, 7), WHITE, 15)
		local masteryLevel = state.masteryLevel and state.masteryLevel[w.id]
		local masteryText = masteryLevel and string.format(" · MASTERY %d (%d XP)", masteryLevel, (state.mastery and state.mastery[w.id]) or 0) or ""
		newLabel(row, string.format("%s · %d DMG · %d MAG · %s%s", w.category, w.damage, w.magazine, w.mode, masteryText), UDim2.fromOffset(240, 16), UDim2.fromOffset(84, 26), MUTED, 12)
		if w.equipped then
			newLabel(row, "EQUIPPED", UDim2.fromOffset(110, 18), UDim2.fromOffset(330, 15), CYAN, 12)
		elseif w.owned then
			rowButton(row, "EQUIP", CYAN, order, function() setLoadout:FireServer({ action = "equip", id = w.id }) end)
		else
			-- Rank and requisition access are separate locks; showing only a buy button made the server refusal
			-- look like a broken purchase rather than a distinct premium-catalog gate.
			local locks = {}
			if w.premiumLocked then table.insert(locks, "SIEGE DIVISION") end
			if w.requisitionTierLocked then table.insert(locks, "TIER " .. tostring(w.requisitionTier or "?")) end
			if type(w.rank) == "number" and w.rank > (state.rank or 1) then table.insert(locks, string.format("RANK %d", w.rank)) end
			if #locks > 0 then
				newLabel(row, "LOCKED · " .. table.concat(locks, " · "), UDim2.fromOffset(150, 18), UDim2.fromOffset(320, 15), MUTED, 12)
			else
				rowButton(row, string.format("BUY %d", w.cost), AMBER, order, function() setLoadout:FireServer({ action = "buy", id = w.id }) end)
			end
		end
	end
	-- Augment shop: the catalogue with prices, so credits have somewhere to go and an augment can be acquired
	-- without the Studio hook.
	-- Abilities and grenades: both existed in config but had no armory surface.
	for slot = 1, 2 do
		order += 1
		local abilityRow = newFrame(list, { size = UDim2.fromOffset(516, 40), radius = 3, color = Color3.fromRGB(18, 24, 31) })
		abilityRow.Name = "Ability" .. slot
		abilityRow.LayoutOrder = 4 + slot
		local current = (slot == 1 and (state.loadout and state.loadout.ability1) or (state.loadout and state.loadout.ability2)) or "?"
		newLabel(abilityRow, string.format("ABILITY %d  ·  %s", slot, current), UDim2.fromOffset(330, 18), UDim2.fromOffset(12, 10), WHITE, 14)
		local other = (slot == 1 and (state.loadout and state.loadout.ability2) or (state.loadout and state.loadout.ability1)) or "?"
		local nextOwned, nextBuyable = nil, nil
		for _, ability in ipairs(state.abilities or {}) do
			if ability.id ~= current and ability.id ~= other then
				if ability.owned and not nextOwned then
					nextOwned = ability
				elseif not ability.owned and not nextBuyable and (tonumber(ability.rank) or 1) <= (state.rank or 1) then
					nextBuyable = ability
				end
			end
		end
		if nextOwned then
			local use = rowButton(abilityRow, "USE " .. nextOwned.id, CYAN, order, function()
				setLoadout:FireServer({ action = "equipAbility", slot = slot, id = nextOwned.id })
			end, 300)
			use.Name = "UseAbility"
		elseif nextBuyable then
			local buy = rowButton(abilityRow, string.format("BUY %d", tonumber(nextBuyable.cost) or 0), AMBER, order, function()
				setLoadout:FireServer({ action = "buyAbility", id = nextBuyable.id })
			end, 300)
			buy.Name = "BuyAbility"
		end
	end
	local grenadeOrder = 6
	for _, grenade in ipairs(state.grenades or {}) do
		order += 1
		local grenadeRow = newFrame(list, { size = UDim2.fromOffset(516, 36), radius = 3, color = Color3.fromRGB(16, 22, 29) })
		grenadeRow.Name = "Grenade" .. tostring(grenade)
		grenadeOrder += 1
		grenadeRow.LayoutOrder = grenadeOrder
		newLabel(grenadeRow, string.format("GRENADE  ·  %s", tostring(grenade)), UDim2.fromOffset(300, 18), UDim2.fromOffset(12, 9), WHITE, 13)
		local owned = false
		for _, entry in ipairs(state.ownedGrenades or {}) do
			if entry == grenade then
				owned = true
			end
		end
		if owned then
			local pick = rowButton(grenadeRow, "EQUIP", CYAN, order, function()
				setLoadout:FireServer({ action = "equipGrenade", id = tostring(grenade) })
			end)
			pick.Name = "Equip"
		else
			local buy = rowButton(grenadeRow, "BUY", AMBER, order, function()
				setLoadout:FireServer({ action = "buyGrenade", id = tostring(grenade) })
			end)
			buy.Name = "Buy"
		end
	end

	-- Caches: awarded caches stack here and open only when the player asks.
	local cacheOrder = 9
	for _, cache in ipairs(state.caches or {}) do
		order += 1
		cacheOrder += 1
		local cacheRow = newFrame(list, { size = UDim2.fromOffset(516, 40), radius = 3, color = Color3.fromRGB(18, 24, 31) })
		cacheRow.Name = "Cache" .. cache.id
		cacheRow.LayoutOrder = cacheOrder
		newLabel(cacheRow, string.format("%s  ·  %d held", cache.name, cache.held), UDim2.fromOffset(300, 18), UDim2.fromOffset(12, 10), WHITE, 14)
		if cache.held > 0 then
			local catButton = rowButton(cacheRow, "CAT " .. (CACHE_CATEGORIES[cacheCategoryIndex] or "ANY"), AMBER, order, function()
				cacheCategoryIndex = cacheCategoryIndex % #CACHE_CATEGORIES + 1
				render()
			end, 316, 88)
			catButton.Name = "CacheCategory"
			local openButton = rowButton(cacheRow, "OPEN", CYAN, order, function()
				setLoadout:FireServer({ action = "openCache", tier = cache.id, category = selectedCacheCategory() })
			end, 410, 92)
			openButton.Name = "Open"
		else
			newLabel(cacheRow, "NONE", UDim2.fromOffset(80, 18), UDim2.fromOffset(330, 10), MUTED, 12)
		end
	end

	-- Armour kits: six suits exist in config
	local armorOrder = 19
	-- Armour kits: six suits exist in config; this is the only surface where a player can buy or wear one.
	for _, suit in ipairs(state.armor or {}) do
		order += 1
		armorOrder += 1
		local suitRow = newFrame(list, { size = UDim2.fromOffset(516, 44), radius = 3, color = Color3.fromRGB(18, 24, 31) })
		suitRow.Name = "Armor" .. suit.id
		suitRow.LayoutOrder = armorOrder
		newLabel(suitRow, string.format("%s  ·  %s", suit.name, suit.tier), UDim2.fromOffset(320, 18), UDim2.fromOffset(12, 6), WHITE, 14)
		newLabel(suitRow, string.format("RANK %d  ·  %d CR", suit.rank, suit.cost), UDim2.fromOffset(320, 14), UDim2.fromOffset(12, 24), MUTED, 11)
		if suit.equipped then
			newLabel(suitRow, "WORN", UDim2.fromOffset(110, 18), UDim2.fromOffset(330, 13), CYAN, 12)
		elseif suit.owned then
			local wear = rowButton(suitRow, "WEAR", CYAN, order, function()
				setLoadout:FireServer({ action = "equipArmor", id = suit.id })
			end)
			wear.Name = "Wear"
		else
			local locks = {}
			if suit.premiumLocked then table.insert(locks, "SIEGE DIVISION") end
			if suit.requisitionTierLocked then table.insert(locks, "TIER " .. tostring(suit.requisitionTier or "?")) end
			if suit.rank > (state.rank or 1) then table.insert(locks, string.format("RANK %d", suit.rank)) end
			if #locks > 0 then
				newLabel(suitRow, "LOCKED · " .. table.concat(locks, " · "), UDim2.fromOffset(150, 18), UDim2.fromOffset(320, 13), MUTED, 12)
			else
				local buy = rowButton(suitRow, string.format("BUY %d", suit.cost), AMBER, order, function()
					setLoadout:FireServer({ action = "buyArmor", id = suit.id })
				end)
				buy.Name = "Buy"
			end
		end
	end

	-- Military requisitions: the catalog is visible even while Siege Division is locked so the player can
	-- preview contents; rank locks remain separate from tier locks on every entry row.
	local reqLayout = 30
	for _, req in ipairs(state.requisitions or {}) do
		reqLayout += 1
		local reqRow = newFrame(list, { size = UDim2.fromOffset(516, 48), radius = 3, color = req.premium and Color3.fromRGB(28, 24, 34) or Color3.fromRGB(20, 29, 35) })
		reqRow.Name = "Requisition_" .. tostring(req.id)
		reqRow.LayoutOrder = reqLayout
		newLabel(reqRow, "REQUISITION · " .. string.upper(tostring(req.displayName)), UDim2.fromOffset(330, 18), UDim2.fromOffset(12, 6), req.premium and AMBER or CYAN, 13)
		local progress = (tonumber(req.tier) or 1) >= 3 and "TIER 3 · MAX" or string.format("TIER %d · %d/%d CR", tonumber(req.tier) or 1, tonumber(req.spend) or 0, tonumber(req.nextTierAt) or 0)
		newLabel(reqRow, string.format("%s  ·  %d WC", progress, tonumber(state.warCredits) or 0), UDim2.fromOffset(320, 14), UDim2.fromOffset(12, 27), MUTED, 11)
		if req.unlocked then
			newLabel(reqRow, "UNLOCKED", UDim2.fromOffset(90, 16), UDim2.fromOffset(410, 16), CYAN, 11)
		else
			local unlock = rowButton(reqRow, string.format("UNLOCK %d WC", tonumber(req.unlockWarCredits) or 0), AMBER, order, function()
				setLoadout:FireServer({ action = "reqUnlock", reqId = req.id })
			end, 392, 112)
			unlock.Name = "Unlock"
		end

		for _, entry in ipairs(req.entries or {}) do
			reqLayout += 1
			local entryRow = newFrame(list, { size = UDim2.fromOffset(516, 42), radius = 3, color = Color3.fromRGB(17, 23, 30) })
			entryRow.Name = "RequisitionEntry_" .. tostring(req.id) .. "_" .. tostring(entry.key)
			entryRow.LayoutOrder = reqLayout
			newLabel(entryRow, string.format("T%d · %s", tonumber(entry.tier) or 1, tostring(entry.name)), UDim2.fromOffset(320, 17), UDim2.fromOffset(12, 5), WHITE, 12)
			newLabel(entryRow, string.format("%s · RANK %d · %d CR", string.upper(tostring(entry.kind)), tonumber(entry.rank) or 1, tonumber(entry.cost) or 0), UDim2.fromOffset(320, 13), UDim2.fromOffset(12, 24), MUTED, 10)
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
				newLabel(entryRow, status, UDim2.fromOffset(105, 16), UDim2.fromOffset(397, 13), entry.owned and CYAN or MUTED, 10)
			else
				local buy = rowButton(entryRow, (tonumber(entry.cost) or 0) > 0 and string.format("BUY %d", tonumber(entry.cost) or 0) or "CLAIM", AMBER, order, function()
					setLoadout:FireServer({ action = "reqBuy", reqId = req.id, key = entry.key })
				end)
				buy.Name = "Buy"
			end
		end
	end

	for _, aug in ipairs(state.augmentCatalog or {}) do
		order += 1
		local augRow = newFrame(list, { size = UDim2.fromOffset(516, 40), radius = 3, color = Color3.fromRGB(18, 24, 31) })
		augRow.LayoutOrder = 100 + order
		newLabel(augRow, string.format("%s  ·  %s", aug.name, aug.role or ""), UDim2.fromOffset(330, 18), UDim2.fromOffset(12, 5), WHITE, 13)
		newLabel(augRow, string.format("%s · %s", aug.description or "", aug.id), UDim2.fromOffset(330, 14), UDim2.fromOffset(12, 22), MUTED, 11)
		if aug.owned then
			newLabel(augRow, "OWNED · copies allowed", UDim2.fromOffset(150, 18), UDim2.fromOffset(330, 12), CYAN, 11)
		end
		rowButton(augRow, string.format("BUY %d", aug.cost or 0), AMBER, order, function()
			setLoadout:FireServer({ action = "augmentBuy", id = aug.id })
		end)
	end

	-- Per-instance augment inventory. Rows expose exact persisted trait numbers and quality, not just archetype names.
	if state.pendingReroll then
		order += 1
		local pending = state.pendingReroll
		local pendingRow = newFrame(list, { size = UDim2.fromOffset(516, 64), radius = 3, color = Color3.fromRGB(35, 27, 18) })
		pendingRow.LayoutOrder = 700 + order
		local oldText = "old roll unavailable"
		for _, item in ipairs(state.augmentItems or {}) do
			if item.uid == pending.uid then oldText = item.traitText end
		end
		local newTraits = {}
		for _, trait in ipairs(pending.traits or {}) do
			local sign = (tonumber(trait.value) or 0) >= 0 and "+" or ""
			table.insert(newTraits, string.format("%s %s%.1f%% q%d", tostring(trait.key), sign, (tonumber(trait.value) or 0) * 100, tonumber(trait.quality) or 0))
		end
		newLabel(pendingRow, "PENDING REROLL · cost already paid", UDim2.fromOffset(330, 15), UDim2.fromOffset(12, 5), AMBER, 12)
		newLabel(pendingRow, string.format("OLD %s", oldText), UDim2.fromOffset(390, 13), UDim2.fromOffset(12, 22), MUTED, 10)
		newLabel(pendingRow, string.format("NEW %s", table.concat(newTraits, " · ")), UDim2.fromOffset(390, 13), UDim2.fromOffset(12, 37), WHITE, 10)
		rowButton(pendingRow, "ACCEPT", CYAN, order, function()
			setLoadout:FireServer({ action = "augmentRerollAccept" })
		end, 350, 72)
		rowButton(pendingRow, "KEEP", AMBER, order, function()
			setLoadout:FireServer({ action = "augmentRerollKeep" })
		end, 430, 72)
	end
	for _, item in ipairs(state.augmentItems or {}) do
		order += 1
		local itemRow = newFrame(list, { size = UDim2.fromOffset(516, 76), radius = 3, color = Color3.fromRGB(17, 23, 30) })
		itemRow.LayoutOrder = 500 + order
		newLabel(itemRow, string.format("%s · %s %s", item.name or item.id, item.rarity or "?", item.category or "?"), UDim2.fromOffset(330, 15), UDim2.fromOffset(12, 5), WHITE, 12)
		newLabel(itemRow, string.format("%s", item.traitText or "no traits"), UDim2.fromOffset(390, 14), UDim2.fromOffset(12, 22), MUTED, 10)
		newLabel(itemRow, string.format("uid %s", string.sub(tostring(item.uid), 1, 12)), UDim2.fromOffset(180, 12), UDim2.fromOffset(12, 39), MUTED, 9)
		local q = math.clamp(tonumber(item.quality) or 0, 0, 1000)
		local back = newFrame(itemRow, { size = UDim2.fromOffset(150, 5), pos = UDim2.fromOffset(12, 58), color = Color3.fromRGB(45, 52, 61) })
		local fill = newFrame(back, { size = UDim2.fromOffset(math.max(1, math.floor(150 * q / 1000)), 5), color = q >= 1000 and Color3.fromRGB(255, 210, 80) or CYAN })
		fill.Name = "QualityFill"
		newLabel(itemRow, string.format("q%d/1000%s", q, q >= 1000 and " MAX" or ""), UDim2.fromOffset(74, 12), UDim2.fromOffset(166, 54), q >= 1000 and Color3.fromRGB(255, 210, 80) or MUTED, 9)
		rowButton(itemRow, item.favorite and "UNFAV" or "FAV", AMBER, order, function()
			setLoadout:FireServer({ action = "augmentFavorite", id = item.uid, favorite = not item.favorite })
		end, 252, 60)
		if item.rarity == "Epic" or item.rarity == "Legendary" then
			local lockCount = #(item.traits or {})
			if lockCount > 0 then
				local lockIndex = tonumber(rerollLockChoices[item.uid]) or 0
				local lockButton = rowButton(itemRow, lockIndex == 0 and "LOCK -" or string.format("LOCK %d", lockIndex), AMBER, order, function()
					rerollLockChoices[item.uid] = lockIndex % lockCount + 1
					render()
				end, 186, 58)
				lockButton.Name = "RerollLock"
			end
		end
		rowButton(itemRow, "REROLL", CYAN, order, function()
			local lockIndex = tonumber(rerollLockChoices[item.uid]) or 0
			setLoadout:FireServer({ action = "augmentReroll", id = item.uid, lockIndex = lockIndex > 0 and lockIndex or nil })
		end, 320, 68)
		rowButton(itemRow, "FUSE", CYAN, order, function()
			local inputs = { item.uid }
			for _, other in ipairs(state.augmentItems or {}) do
				if #inputs >= 3 then break end
				if other.uid ~= item.uid and other.rarity == item.rarity and other.category == item.category and not other.protected and not other.pending then
					table.insert(inputs, other.uid)
				end
			end
			setLoadout:FireServer({ action = "augmentFusePreview", inputs = inputs })
		end, 396, 52)
		rowButton(itemRow, "SCRAP", AMBER, order, function()
			setLoadout:FireServer({ action = "augmentDismantle", id = item.uid })
		end, 456, 56)
	end

	if fusionPreview then
		order += 1
		local fuseRow = newFrame(list, { size = UDim2.fromOffset(516, 58), radius = 3, color = Color3.fromRGB(18, 28, 34) })
		fuseRow.LayoutOrder = 690 + order
		local names = {}
		for _, outcome in ipairs(fusionPreview.outcomes or {}) do
			table.insert(names, string.format("%s %.0f%%", tostring(outcome.name), (tonumber(outcome.chance) or 0) * 100))
		end
		newLabel(fuseRow, string.format("FUSE 3 %s %s -> 1 %s", tostring(fusionPreview.fromRarity), tostring(fusionPreview.category), tostring(fusionPreview.toRarity)), UDim2.fromOffset(330, 15), UDim2.fromOffset(12, 6), CYAN, 12)
		newLabel(fuseRow, table.concat(names, " · "), UDim2.fromOffset(340, 14), UDim2.fromOffset(12, 26), MUTED, 10)
		rowButton(fuseRow, "CONFIRM", AMBER, order, function()
			setLoadout:FireServer({ action = "augmentFuse", inputs = fusionPreview.uids })
			fusionPreview = nil
		end, 352, 76)
		rowButton(fuseRow, "CANCEL", CYAN, order, function()
			fusionPreview = nil
			render()
		end, 432, 72)
	end

	-- Bulk dismantle: rarity/category filters, exact count+scrap preview, then an explicit confirm click.
	order += 1
	local bulkRow = newFrame(list, { size = UDim2.fromOffset(516, 42), radius = 3, color = Color3.fromRGB(24, 22, 25) })
	bulkRow.LayoutOrder = 850 + order
	local bulkRarity = BULK_RARITIES[bulkRarityIndex] or "ALL"
	local bulkCategory = CACHE_CATEGORIES[bulkCategoryIndex] or "ANY"
	local rarityButton = rowButton(bulkRow, "R:" .. bulkRarity, AMBER, order, function()
		bulkRarityIndex = bulkRarityIndex % #BULK_RARITIES + 1
		bulkPreview = nil
		render()
	end, 10, 78)
	rarityButton.Name = "BulkRarityFilter"
	local catButton = rowButton(bulkRow, "C:" .. bulkCategory, AMBER, order, function()
		bulkCategoryIndex = bulkCategoryIndex % #CACHE_CATEGORIES + 1
		bulkPreview = nil
		render()
	end, 94, 88)
	catButton.Name = "BulkCategoryFilter"
	rowButton(bulkRow, "PREVIEW", CYAN, order, function()
		setLoadout:FireServer({ action = "augmentDismantleBulk", rarity = bulkRarity, category = bulkCategory })
	end, 188, 82)
	local matches = bulkPreview and bulkPreview.rarity == bulkRarity and bulkPreview.category == bulkCategory
	local label = matches and string.format("%d items · +%d scrap · %d protected", tonumber(bulkPreview.count) or 0, tonumber(bulkPreview.scrap) or 0, tonumber(bulkPreview.skipped) or 0) or "bulk scrap preview"
	newLabel(bulkRow, label, UDim2.fromOffset(150, 14), UDim2.fromOffset(278, 14), matches and WHITE or MUTED, 10)
	if matches and (tonumber(bulkPreview.count) or 0) > 0 then
		local confirm = rowButton(bulkRow, "CONFIRM", AMBER, order, function()
			setLoadout:FireServer({ action = "augmentDismantleBulk", rarity = bulkRarity, category = bulkCategory, confirm = true })
			bulkPreview = nil
		end, 432, 76)
		confirm.Name = "BulkDismantleConfirm"
	end

	-- Two actions that existed only as service functions until now: inventory expansion and bulk cache opening.
	local actionRow = newFrame(list, { size = UDim2.fromOffset(516, 40), radius = 3, color = Color3.fromRGB(16, 22, 29) })
	actionRow.LayoutOrder = order
	local heldTier, heldCount = nil, 0
	for tierId, count in pairs(state.cacheCounts or {}) do
		if type(count) == "number" and count > heldCount then
			heldTier, heldCount = tierId, count
		end
	end
	rowButton(actionRow, "EXPAND +50", AMBER, order, function()
		setLoadout:FireServer({ action = "expandAugmentInventory" })
	end, 12)
	rowButton(actionRow, heldTier and string.format("OPEN 10 · %s x%d", heldTier, heldCount) or "NO CACHES", CYAN, order, function()
		if heldTier then
			setLoadout:FireServer({ action = "bulkOpenCache", id = heldTier, category = selectedCacheCategory() })
		end
	end, 258)
		-- Feedback line: both actions publish results to workspace attributes, which previously nobody surfaced, so a
	-- player pressed a button and learned nothing. This mirrors those attributes into the panel.
	local statusRow = newFrame(list, { size = UDim2.fromOffset(516, 22), radius = 3, color = Color3.fromRGB(14, 19, 25) })
	statusRow.LayoutOrder = order + 1
	local statusLabel = newLabel(statusRow, "READY", UDim2.fromOffset(492, 14), UDim2.fromOffset(12, 4), MUTED, 11)
	-- True odds disclosure (S11-027): the numbers come from the same weight table that decides outcomes, and the
	-- whole-cache figure is 1-(1-p)^n over the tier's own draw count rather than a promise of a guarantee.
	local oddsRow = newFrame(list, { size = UDim2.fromOffset(516, 22), radius = 3, color = Color3.fromRGB(12, 16, 21) })
	oddsRow.LayoutOrder = order + 2
	local oddsList = state.cacheOdds
	local oddsText = "ODDS  no cache held"
	if oddsList and #oddsList > 0 then
		local lines = {}
		for _, odds in ipairs(oddsList) do
			local parts = {}
			for _, rarity in ipairs({ "Common", "Rare", "Epic", "Legendary" }) do
				local per = odds.perDraw and odds.perDraw[rarity]
				if per then
					parts[#parts+1] = string.format("%s %.1f%%", rarity, per)
				end
			end
			local best = odds.atLeastOne and odds.atLeastOne.Legendary
			lines[#lines+1] = string.format("%s x%d held %d  ·  %s  ·  Leg %.1f%%",
				tostring(odds.tier), odds.draws or 1, odds.held or 0, table.concat(parts, " · "), best or 0)
		end
		oddsText = table.concat(lines, "   ||   ")
	end
	newLabel(oddsRow, oddsText, UDim2.fromOffset(492, 14), UDim2.fromOffset(12, 4), MUTED, 10)
	-- Enemy drop chance for the leading tier: the same table the kill handler rolls against.
	if oddsList and oddsList[1] and type(oddsList[1].dropChance) == "table" then
		local drops = {}
		for _, cls in ipairs({ "infantry", "heavy", "commander" }) do
			local c = oddsList[1].dropChance[cls]
			if c then
				drops[#drops+1] = string.format("%s %.0f%%", cls, c * 100)
			end
		end
		local dropRow = newFrame(list, { size = UDim2.fromOffset(516, 22), radius = 3, color = Color3.fromRGB(12, 16, 21) })
		dropRow.LayoutOrder = order + 3
		newLabel(dropRow, string.format("DROP %s  ·  %s", tostring(oddsList[1].tier), table.concat(drops, " · ")),
			UDim2.fromOffset(492, 14), UDim2.fromOffset(12, 4), MUTED, 10)
	end
	local function showStatus(text, colour)
		statusLabel.Text = text
		statusLabel.TextColor3 = colour
	end
	workspace:GetAttributeChangedSignal("GF_AugmentExpandResult"):Connect(function()
		local v = workspace:GetAttribute("GF_AugmentExpandResult")
		if v then
			showStatus("EXPANSION " .. tostring(v), CYAN)
		end
	end)
	-- S11-036: cache open reveal. A ~2s tier-lit flash with a rarity sound, skippable by any click,
	-- then the grouped result line. Deliberately no slot-reel / near-miss theatre: the item is
	-- already rolled server-side before anything animates, so the reveal is presentation only.
	local RARITY_COLORS = {
		Common = Color3.fromRGB(180, 185, 195), Rare = Color3.fromRGB(90, 160, 255),
		Epic = Color3.fromRGB(180, 110, 255), Legendary = Color3.fromRGB(255, 190, 80),
	}
	local revealFrame = newFrame(gui, { size = UDim2.fromOffset(320, 120), radius = 6, color = Color3.fromRGB(12, 16, 22) })
	revealFrame.Position = UDim2.new(0.5, -160, 0.5, -60)
	revealFrame.Visible = false
	revealFrame.ZIndex = 50
	local revealGlow = newFrame(revealFrame, { size = UDim2.fromOffset(320, 8), radius = 3, color = Color3.fromRGB(90, 160, 255) })
	revealGlow.Position = UDim2.fromOffset(0, 0)
	local revealLabel = newLabel(revealFrame, "OPENING CACHE", UDim2.fromOffset(300, 30), UDim2.fromOffset(10, 20), WHITE, 15)
	local revealResult = newLabel(revealFrame, "", UDim2.fromOffset(300, 40), UDim2.fromOffset(10, 56), MUTED, 12)
	local revealSkip = false
	revealFrame.InputBegan:Connect(function()
		revealSkip = true
	end)
	local function playCacheReveal(tierText)
		revealSkip = false
		revealFrame.Visible = true
		revealResult.Text = ""
		local rarity = tostring(tierText):match("(%a+)$") or "Common"
		local col = RARITY_COLORS[rarity] or RARITY_COLORS.Common
		revealGlow.BackgroundColor3 = col
		pcall(function()
			require(script.Parent.GFAudio).play(rarity == "Legendary" and "ui_click" or "ui_click")
		end)
		-- ~2s reveal, skippable
		local t0 = os.clock()
		while os.clock() - t0 < 2.0 and not revealSkip do
			revealGlow.BackgroundTransparency = 0.2 + 0.5 * math.abs(math.sin((os.clock() - t0) * 6))
			task.wait(0.05)
		end
		revealGlow.BackgroundTransparency = 0
		revealLabel.Text = "CACHE OPENED"
	end
	workspace:GetAttributeChangedSignal("GF_CacheOpened"):Connect(function()
		local v = workspace:GetAttribute("GF_CacheOpened")
		if type(v) == "string" and revealFrame.Visible ~= true then
			task.spawn(function()
				playCacheReveal(v)
				revealResult.Text = tostring(v)
				task.delay(2.5, function()
					revealFrame.Visible = false
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
-- Augments section: sockets allowed come from the mastery rule on the server, so the second socket
		-- shows as locked with the mastery it needs instead of simply not existing.
	local equippedId = state.loadout and state.loadout.primary or "AR01"
	local mastery = (state.mastery and state.mastery[equippedId]) or 0
	local sockets = (state.sockets and state.sockets[equippedId]) or 1
	local augRow = newFrame(list, { size = UDim2.fromOffset(516, 62), radius = 3, color = Color3.fromRGB(18, 24, 31) })
	augRow.LayoutOrder = order + 1
	newLabel(augRow, string.format("AUGMENTS · %s · MASTERY %d", equippedId, mastery), UDim2.fromOffset(330, 18), UDim2.fromOffset(12, 6), MUTED, 12)
	for slot = 1, 2 do
		local x = 12 + (slot - 1) * 258
		local slotted = state.slotted and state.slotted[slot]
		local allowed = slot <= sockets
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(246, 26)
		b.Position = UDim2.fromOffset(x, 28)
		b.BackgroundColor3 = allowed and Color3.fromRGB(26, 34, 44) or Color3.fromRGB(24, 22, 24)
		local label = slotted and string.format("SOCKET %d · %s", slot, tostring(slotted)) or (allowed and string.format("SOCKET %d · EMPTY", slot) or string.format("SOCKET %d · LOCKED (MASTERY 5)", slot))
		b.Text = label
		b.TextColor3 = allowed and (slotted and CYAN or WHITE) or MUTED
		b.TextSize = 11
		b.Font = Enum.Font.GothamBold
		b.BorderSizePixel = 0
		b.Parent = augRow
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 3); bc.Parent = b
		if allowed then
			b.MouseButton1Click:Connect(function()
				local owned = state.augmentItems or {}
				if #owned == 0 then return end
				-- cycle through owned augments, so the socket can be changed with one input family
				local nextIndex = 1
				for index, def in ipairs(owned) do
					if def.uid == slotted then nextIndex = index % #owned + 1 end
				end
				setLoadout:FireServer({ action = "augment", weapon = equippedId, slot = slot, id = owned[nextIndex].uid })
			end)
		end
	end
	order += 1
	-- Canvas is automatic now (UIListLayout + AutomaticCanvasSize). The manual CanvasSize that used to be set
	local classRow = newFrame(list, { size = UDim2.fromOffset(516, 44), radius = 3, color = Color3.fromRGB(18, 24, 31) })
	classRow.LayoutOrder = order + 1
	newLabel(classRow, "CLASS", UDim2.fromOffset(60, 18), UDim2.fromOffset(12, 13), MUTED, 12)
	for i, c in ipairs(state.classes) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(96, 26)
		b.Position = UDim2.fromOffset(72 + (i - 1) * 102, 9)
		b.BackgroundColor3 = c.selected and CYAN or Color3.fromRGB(26, 34, 44)
		b.Text = c.name or c.id
		b.TextColor3 = c.selected and INK or WHITE
		b.TextSize = 12
		b.Font = Enum.Font.GothamBold
		b.BorderSizePixel = 0
		b.Parent = classRow
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 3); cc.Parent = b
		b.MouseButton1Click:Connect(function() setLoadout:FireServer({ action = "class", id = c.id }) end)
	end
end

local function setOpen(open)
	isOpen = open
	panel.Visible = open
	if open then render() end
end

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
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.E then return end
	if not anchor then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if isOpen then
		setOpen(false)
	elseif (hrp.Position - anchor.Position).Magnitude <= OPEN_RANGE then
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
	p = nil
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
	while not anchor do task.wait(0.5); anchor = findAnchor() end
	requestLoadout:FireServer()
end)
