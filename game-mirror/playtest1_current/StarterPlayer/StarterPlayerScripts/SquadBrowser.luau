--!strict
-- Squad browser (Counteroffensive Stage 4 client surface, built on the Stage 5 design
-- system per owner directive). global listings + dispatch beacons in one scannable surface:
-- the player sees every forming squad across ALL servers and every active distress beacon,
-- and joins with one interaction. cross-server joins teleport; same-server joins are instant.
-- refresh cadence 5s while open — MemoryStore read budgets are sized for this.
local Tokens = require(game:GetService("ReplicatedStorage").GF.Shared.UI.Tokens)
local Components = require(game:GetService("ReplicatedStorage").GF.Shared.UI.Components)
local MenuShell = require(game:GetService("ReplicatedStorage").GF.Shared.UI.MenuShell)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")

local shell = MenuShell.new("GF_SquadBrowser", 10)
require(game:GetService("ReplicatedStorage").GF.Shared.UI.MenuController).register(shell)

-- war roster for the deploy/form pickers
local WarModel = require(game:GetService("ReplicatedStorage").GF.Shared.WarModel)
local WarOperations = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.WarOperations)

-- ---------------------------------------------------------------------------
-- squads section: global listings, most urgent beacons pinned on top
-- ---------------------------------------------------------------------------
local browserState = {
	listContainer = nil :: ScrollingFrame?,
	statusLine = nil :: TextLabel?,
	refreshToken = 0, -- stale-async guard: slower responses never overwrite newer data
}

shell:registerSection("SQUADS", "◈", function(page)
	Components.text(page, "ACTIVE OPERATIONS — ALL SERVERS", "title",
		UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 0))
	local statusLine = Components.text(page, "", "caption",
		UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 34))
	browserState.statusLine = statusLine
	local list = Components.list(page,
		UDim2.new(1, 0, 1, -60), UDim2.new(0, 0, 0, 58))
	browserState.listContainer = list
end)

-- ---------------------------------------------------------------------------
-- DEPLOY section: the mission screen rework (owner directive — the legacy cramped panel is
-- replaced, not reskinned). full-screen theatre-first layout: regions with live war status
-- down the left, the region's operations center-stage, difficulty + deploy at the bottom.
-- fires the exact wire payload the legacy panel did — server behavior unchanged.
-- ---------------------------------------------------------------------------
local deployState = {
	region = "VerdantReach",
	operationId = nil :: string?,
	difficulty = "Normal",
	opButtons = {} :: { [string]: TextButton },
	regionButtons = {} :: { [string]: TextButton },
	diffButtons = {} :: { [string]: TextButton },
	statusLine = nil :: TextLabel?,
	opList = nil :: ScrollingFrame?,
}

shell:registerSection("DEPLOY", "\u{25bc}", function(page)
	-- helldivers 2 war-table structure, copied from the reference per owner directive:
	-- theater strip across the top, operation panels with mission intel down the left,
	-- theater status readout right (control bar = liberation-bar equivalent), difficulty
	-- bar across the bottom in fixed order with amber selection, wide deploy confirmation
	-- at the very bottom. no invention.
	Components.text(page, "DEPLOYMENT", "title",
		UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 0))
	local statusLine = Components.text(page, "", "caption",
		UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 38))
	deployState.statusLine = statusLine

	-- theater strip: regions as a horizontal selector row across the top — hd2 picks the
	-- theater then the operation in one read, no nested list-of-lists
	local theaterRow = Instance.new("Frame")
	theaterRow.Name = "TheaterRow"
	theaterRow.Size = UDim2.new(1, 0, 0, 44)
	theaterRow.Position = UDim2.new(0, 0, 0, 60)
	theaterRow.BackgroundTransparency = 1
	theaterRow.Parent = page
	local theaterLayout = Instance.new("UIListLayout")
	theaterLayout.FillDirection = Enum.FillDirection.Horizontal
	theaterLayout.Padding = UDim.new(0, Tokens.Space.xs)
	theaterLayout.SortOrder = Enum.SortOrder.LayoutOrder
	theaterLayout.Parent = theaterRow

	-- operations column (left, wide): one panel per operation, intel visible on the row
	local opList = Components.list(page,
		UDim2.new(1, -290, 1, -270), UDim2.new(0, 0, 0, 112))
	deployState.opList = opList

	-- theater status panel (right, narrow): the war read for the selected region
	local intelPanel = Components.panel(page,
		UDim2.new(0, 280, 1, -270), UDim2.new(1, -280, 0, 112))
	Components.text(intelPanel, "THEATER STATUS", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 18), UDim2.new(0, Tokens.Space.md, 0, Tokens.Space.sm))
	local intelBody = Components.text(intelPanel, "", "body",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 120), UDim2.new(0, Tokens.Space.md, 0, 34))
	intelBody.TextWrapped = true
	intelBody.TextXAlignment = Enum.TextXAlignment.Left
	intelBody.TextYAlignment = Enum.TextYAlignment.Top
	-- control bar: thin sharp track, amber fill — the liberation read
	local barTrack = Instance.new("Frame")
	barTrack.Name = "ControlTrack"
	barTrack.Size = UDim2.new(1, -Tokens.Space.md * 2, 0, 6)
	barTrack.Position = UDim2.new(0, Tokens.Space.md, 0, 160)
	barTrack.BackgroundColor3 = Tokens.Color.panelInset
	barTrack.BorderSizePixel = 0
	barTrack.Parent = intelPanel
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(0.5, 0, 1, 0)
	barFill.BackgroundColor3 = Tokens.Color.accentSelect
	barFill.BorderSizePixel = 0
	barFill.Parent = barTrack
	local barLabel = Components.text(intelPanel, "", "caption",
		UDim2.new(1, -Tokens.Space.md * 2, 0, 16), UDim2.new(0, Tokens.Space.md, 0, 172))

	-- difficulty bar across the bottom: the reference's signature row. fixed order,
	-- equal segments, amber selection.
	local diffBar = Instance.new("Frame")
	diffBar.Name = "DifficultyBar"
	diffBar.Size = UDim2.new(1, 0, 0, 52)
	diffBar.Position = UDim2.new(0, 0, 1, -112)
	diffBar.BackgroundTransparency = 1
	diffBar.Parent = page
	local diffLayout = Instance.new("UIListLayout")
	diffLayout.FillDirection = Enum.FillDirection.Horizontal
	diffLayout.Padding = UDim.new(0, Tokens.Space.xs)
	diffLayout.SortOrder = Enum.SortOrder.LayoutOrder
	diffLayout.Parent = diffBar

	-- wide deploy confirmation at the very bottom — the hellpod-equivalent commitment
	local deployBtn = Components.button(page, "DEPLOY", "primary")
	deployBtn.Size = UDim2.new(1, 0, 0, 52)
	deployBtn.Position = UDim2.new(0, 0, 1, -54)
	deployBtn.TextSize = Tokens.Type.sizeTitle
	deployBtn.Activated:Connect(function()
		if not deployState.operationId then
			statusLine.Text = "SELECT AN OPERATION"
			return
		end
		remotes.RequestDeploy:FireServer({
			difficulty = deployState.difficulty,
			operationId = deployState.operationId,
		})
		shell:close()
	end)

	local function refreshDiffSelection()
		for d, b in pairs(deployState.diffButtons) do
			if d == deployState.difficulty then
				b.BackgroundColor3 = Tokens.Color.accentSelect
				b.TextColor3 = Tokens.Color.panelInset
			else
				b.BackgroundColor3 = Tokens.Color.panelRaised
				b.TextColor3 = Tokens.Color.textPrimary
			end
		end
	end
	for diffIdx, diff in ipairs({ "Easy", "Normal", "Hard", "Extreme" }) do
		local chip = Components.button(diffBar, string.upper(diff), "ghost")
		chip.Size = UDim2.new(0.25, -Tokens.Space.xs, 1, 0)
		chip.LayoutOrder = diffIdx
		deployState.diffButtons[diff] = chip
		chip.Activated:Connect(function()
			deployState.difficulty = diff
			refreshDiffSelection()
		end)
	end

	local selectRegion
	selectRegion = function(rid: string)
		deployState.region = rid
		deployState.operationId = nil
		deployState.opButtons = {}
		for _, child in ipairs(opList:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		-- theater intel: the war read, straight from the live attributes
		local control = workspace:GetAttribute("GF_WarControl_" .. rid)
		local front = workspace:GetAttribute("GF_WarFront_" .. rid)
		local pct = type(control) == "number" and math.floor(control * 100 + 0.5) or nil
		intelBody.Text = string.format(
			"REGION %s\nCONTROL: %s\nFRONT: %s\n\nOperations in this theater feed the war effort directly. Mission success shifts control.",
			string.upper(rid),
			pct and (pct .. "%") or "CONTESTED",
			front and string.upper(tostring(front)) or "ACTIVE")
		if pct then
			barFill.Size = UDim2.new(math.clamp(control or 0.5, 0, 1), 0, 1, 0)
			barLabel.Text = string.format("CONTROL %d%%", pct)
		else
			barFill.Size = UDim2.new(0.5, 0, 1, 0)
			barLabel.Text = "CONTROL CONTESTED"
		end
		for r, b in pairs(deployState.regionButtons) do
			b.BackgroundColor3 = r == rid and Tokens.Color.accentSelect or Tokens.Color.panelRaised
			b.TextColor3 = r == rid and Tokens.Color.panelInset or Tokens.Color.textPrimary
		end
		local order = 0
		for opId, def in pairs(WarModel.OPERATIONS) do
			if (def.region or "?") == rid then
				order += 1
				local name = (WarOperations.DisplayName and WarOperations.DisplayName[opId]) or opId
				local row = Components.row(opList, string.upper(name),
					string.format("%s — %s", string.lower(def.family or "combat operation"), string.upper(def.template or "standard engagement")))
				row.LayoutOrder = order
				local pick = Components.button(row, "SELECT", "ghost")
				pick.Size = UDim2.new(0, 96, 0, Tokens.Size.buttonHeight - 12)
				pick.Position = UDim2.new(1, -Tokens.Space.sm, 0.5, 0)
				pick.AnchorPoint = Vector2.new(1, 0.5)
				pick.TextSize = Tokens.Type.sizeSmall
				deployState.opButtons[opId] = pick
				local opName = name
				pick.Activated:Connect(function()
					deployState.operationId = opId
					for id, b in pairs(deployState.opButtons) do
						if id == opId then
							b.BackgroundColor3 = Tokens.Color.accentSelect
							b.TextColor3 = Tokens.Color.panelInset
						else
							b.BackgroundColor3 = Tokens.Color.panelRaised
							b.TextColor3 = Tokens.Color.textPrimary
						end
					end
					statusLine.Text = string.upper(string.format("%s — %s theater — %s difficulty", opName, rid, deployState.difficulty))
				end)
			end
		end
		if order == 0 then
			statusLine.Text = "NO OPERATIONS IN THEATER"
		end
	end

	-- theater buttons populate once; selection state rides on top
	local regions = {}
	for _opId, def in pairs(WarModel.OPERATIONS) do
		local r = def.region or "?"
		if not table.find(regions, r) then
			table.insert(regions, r)
		end
	end
	table.sort(regions)
	for rIdx, r in ipairs(regions) do
		local btn = Components.button(theaterRow, string.upper(r), "ghost")
		btn.Size = UDim2.new(0, 150, 1, 0)
		btn.LayoutOrder = rIdx
		deployState.regionButtons[r] = btn
		btn.Activated:Connect(function()
			selectRegion(r)
		end)
	end

	refreshDiffSelection()
	-- initial selection: terminal preselection if set, else the first theater
	local initial = deployState.region
	if not table.find(regions, initial) then
		initial = regions[1]
	end
	if initial then
		selectRegion(initial)
	end
end)

shell:registerSection("FORM", "▲", function(page)
	Components.text(page, "FORM OPERATION — FLEET-WIDE LISTING", "title",
		UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 0))
	local statusLine = Components.text(page, "select an operation, difficulty, and visibility", "caption",
		UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 34))
	formState.statusLine = statusLine

	local scroll = Components.list(page, UDim2.new(1, 0, 1, -60), UDim2.new(0, 0, 0, 58))

	-- operations grouped by region — the fixed-geography mandate made visible in the picker
	local byRegion: { [string]: { string } } = {}
	local regionOrder: { string } = {}
	for opId, def in pairs(WarModel.OPERATIONS) do
		local region = def.region or "?"
		if not byRegion[region] then
			byRegion[region] = {}
			table.insert(regionOrder, region)
		end
		table.insert(byRegion[region], opId)
	end
	table.sort(regionOrder)
	local order = 0
	for _, region in ipairs(regionOrder) do
		table.sort(byRegion[region])
		order += 1
		local header = Components.text(scroll, string.upper(region), "caption")
		header.LayoutOrder = order
		header.TextColor3 = Tokens.Color.textAccent
		for _, opId in ipairs(byRegion[region]) do
			order += 1
			local def = WarModel.OPERATIONS[opId]
			local name = WarOperations.DisplayName[opId] or opId
			local row = Components.row(scroll, name, string.format("%s · %s", string.lower(def.family or "operation"), region))
			row.LayoutOrder = order
			local pick = Components.button(row, "SELECT", "ghost")
			pick.Size = UDim2.new(0, 100, 0, Tokens.Size.buttonHeight - 10)
			pick.Position = UDim2.new(1, -Tokens.Space.sm, 0.5, 0)
			pick.AnchorPoint = Vector2.new(1, 0.5)
			formState.opButtons[opId] = pick
			pick.Activated:Connect(function()
				formState.operationId = opId
				refreshChips()
				statusLine.Text = string.format("%s — %s", name, region)
				statusLine.TextColor3 = Tokens.Color.textSecondary
			end)
		end
	end

	-- difficulty chips
	order += 1
	local diffHeader = Components.text(scroll, "DIFFICULTY", "caption")
	diffHeader.LayoutOrder = order
	diffHeader.TextColor3 = Tokens.Color.textAccent
	local diffRow = Instance.new("Frame")
	diffRow.Size = UDim2.new(1, 0, 0, Tokens.Size.chipHeight + 8)
	diffRow.BackgroundTransparency = 1
	order += 1
	diffRow.LayoutOrder = order
	diffRow.Parent = scroll
	local diffLayout = Instance.new("UIListLayout")
	diffLayout.FillDirection = Enum.FillDirection.Horizontal
	diffLayout.Padding = UDim.new(0, Tokens.Space.sm)
	diffLayout.Parent = diffRow
	for _, diff in ipairs({ "Easy", "Normal", "Hard", "Extreme" }) do
		local chip = Components.button(diffRow, string.upper(diff), "ghost")
		chip.Size = UDim2.new(0, 110, 0, Tokens.Size.chipHeight)
		chip.TextSize = Tokens.Type.sizeSmall
		formState.diffButtons[diff] = chip
		chip.Activated:Connect(function()
			formState.difficulty = diff
			refreshChips()
		end)
	end

	-- visibility chips
	order += 1
	local privHeader = Components.text(scroll, "VISIBILITY", "caption")
	privHeader.LayoutOrder = order
	privHeader.TextColor3 = Tokens.Color.textAccent
	local privRow = Instance.new("Frame")
	privRow.Size = UDim2.new(1, 0, 0, Tokens.Size.chipHeight + 8)
	privRow.BackgroundTransparency = 1
	order += 1
	privRow.LayoutOrder = order
	privRow.Parent = scroll
	local privLayout = Instance.new("UIListLayout")
	privLayout.FillDirection = Enum.FillDirection.Horizontal
	privLayout.Padding = UDim.new(0, Tokens.Space.sm)
	privLayout.Parent = privRow
	for _, spec in ipairs({ { key = "public", label = "PUBLIC — FLEET-WIDE" }, { key = "private", label = "SQUAD-ONLY" } }) do
		local chip = Components.button(privRow, spec.label, "ghost")
		chip.Size = UDim2.new(0, 200, 0, Tokens.Size.chipHeight)
		chip.TextSize = Tokens.Type.sizeSmall
		formState.privButtons[spec.key] = chip
		chip.Activated:Connect(function()
			formState.public = spec.key == "public"
			refreshChips()
		end)
	end

	-- the form action
	order += 1
	local formBtn = Components.button(scroll, "FORM OPERATION", "primary")
	formBtn.LayoutOrder = order
	formBtn.Activated:Connect(function()
		if not formState.operationId then
			statusLine.Text = "select an operation first"
			statusLine.TextColor3 = Tokens.Color.warning
			return
		end
		local def = WarModel.OPERATIONS[formState.operationId]
		statusLine.Text = "PUBLISHING FLEET-WIDE…"
		statusLine.TextColor3 = Tokens.Color.textAccent
		local form = remotes:FindFirstChild("FormSquad")
		if form then
			form:FireServer({
				operationId = formState.operationId,
				difficulty = formState.difficulty,
				capacity = 4,
				public = formState.public,
				region = def and def.region or nil,
			})
			statusLine.Text = string.format("LISTED — report to the %s terminal; joiners arrive fleet-wide",
				tostring(def and def.region or "deployment"))
			statusLine.TextColor3 = Tokens.Color.success
		end
	end)

	refreshChips()
end)

local function clearList()
	local list = browserState.listContainer
	if not list then return end
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function joinRow(parent: Instance, order: number, heading: string, caption: string, accent: Color3?, onJoin: () -> ()): ()
	local row = Components.row(parent, heading, caption)
	row.LayoutOrder = order
	local joinBtn = Components.button(row, "JOIN", "primary")
	joinBtn.Size = UDim2.new(0, 110, 0, Tokens.Size.buttonHeight - 10)
	joinBtn.Position = UDim2.new(1, -Tokens.Space.sm, 0.5, 0)
	joinBtn.AnchorPoint = Vector2.new(1, 0.5)
	joinBtn.Activated:Connect(onJoin)
	if accent then
		-- status accent: thin left edge, same language as the sidebar active bar
		local edge = Instance.new("Frame")
		edge.Size = UDim2.new(0, 3, 1, 0)
		edge.BackgroundColor3 = accent
		edge.BorderSizePixel = 0
		edge.Parent = row
	end
end

local function renderBrowser(data: any)
	clearList()
	local list = browserState.listContainer
	if not list then return end
	local order = 0
	local count = 0

	-- distress beacons first: they are time-critical by definition
	for _, beacon in ipairs(data.beacons or {}) do
		if (tonumber(beacon.seats) or 0) > 0 then
			order += 1
			count += 1
			local heading = string.format("⚠ DISTRESS — %s", tostring(beacon.region or beacon.id or "UNKNOWN"))
			local caption = string.format("%s · %d seat(s) · %ds elapsed",
				tostring(beacon.difficulty or "?"), tonumber(beacon.seats) or 0, tonumber(beacon.age) or 0)
			local key = string.format("%014d", tonumber(beacon.openedAtUTC) or 0) .. "_" .. tostring(beacon.id)
			joinRow(list, order, heading, caption, Tokens.Color.warning, function()
				if browserState.statusLine then
					browserState.statusLine.Text = "RESPONDING TO DISTRESS…"
					browserState.statusLine.TextColor3 = Tokens.Color.textAccent
				end
				task.spawn(function()
					local respond = remotes:FindFirstChild("RespondDispatch")
					if not respond then return end
					local ok, result = pcall(function()
						return respond:InvokeServer(key)
					end)
					if browserState.statusLine then
						if ok and type(result) == "table" and result.ok then
							browserState.statusLine.Text = result.teleporting and "DEPLOYING — good hunting" or "JOINED — insertion inbound"
						else
							local reason = type(result) == "table" and tostring(result.reason) or "failed"
							browserState.statusLine.Text = "RESPONSE FAILED — " .. reason
							browserState.statusLine.TextColor3 = Tokens.Color.danger
						end
					end
				end)
			end)
		end
	end

	-- forming squads across all servers (server contract field: `squads`)
	for _, squad in ipairs(data.squads or {}) do
		if squad.state == "forming" and (tonumber(squad.openSeats) or 0) > 0 then
			order += 1
			count += 1
			local sameServer = squad.leaderJobId == game.JobId
			local heading = string.format("%s — %s", tostring(squad.leader or "SQUAD"), tostring(squad.operationName or squad.operationId or "OPERATION"))
			local caption = string.format("%s · %s · %d/%d seats%s",
				tostring(squad.region or "?"), tostring(squad.difficulty or "?"),
				tonumber(squad.taken) or 1, tonumber(squad.capacity) or 4,
				sameServer and " · THIS SERVER" or "")
			local listingKey = tostring(squad.squadId)
			joinRow(list, order, heading, caption, nil, function()
				if browserState.statusLine then
					browserState.statusLine.Text = "JOINING SQUAD…"
					browserState.statusLine.TextColor3 = Tokens.Color.textAccent
				end
				task.spawn(function()
					local join = remotes:FindFirstChild("JoinSquad")
					if not join then return end
					local ok, result = pcall(function()
						return join:InvokeServer(listingKey)
					end)
					if browserState.statusLine then
						if ok and type(result) == "table" and result.ok then
							browserState.statusLine.Text = result.teleporting and "TRANSFERRING TO SQUAD SERVER…" or "JOINED — report to your squad"
						else
							local reason = type(result) == "table" and tostring(result.reason) or "failed"
							browserState.statusLine.Text = "JOIN FAILED — " .. reason
							browserState.statusLine.TextColor3 = Tokens.Color.danger
						end
					end
				end)
			end)
		end
	end

	if count == 0 and browserState.statusLine then
		browserState.statusLine.Text = "No forming squads or distress calls across the fleet — form one and it appears here for everyone."
		browserState.statusLine.TextColor3 = Tokens.Color.textSecondary
	elseif browserState.statusLine and browserState.statusLine.TextColor3 ~= Tokens.Color.danger then
		browserState.statusLine.Text = string.format("%d open operation(s) fleet-wide · refreshes every 5s", count)
		browserState.statusLine.TextColor3 = Tokens.Color.textSecondary
	end
end

-- refresh loop: only while open — MemoryStore read budgets are real
task.spawn(function()
	while true do
		task.wait(5)
		if shell.visible then
			browserState.refreshToken += 1
			local token = browserState.refreshToken
			task.spawn(function()
				local browser = remotes:FindFirstChild("RequestSquadBrowser")
				if not browser then return end
				local ok, data = pcall(function()
					return browser:InvokeServer()
				end)
				-- stale responses never overwrite newer state
				if ok and type(data) == "table" and token == browserState.refreshToken then
					renderBrowser(data)
				end
			end)
		end
	end
end)

-- ---------------------------------------------------------------------------
-- open/close wiring: the deploy-terminal proximity opens this browser; the legacy
-- quick-deploy path stays live during migration. keyboard shortcut for kbm, and the
-- browser closes on B/esc per the semantic input layer.
-- ---------------------------------------------------------------------------
local Input = require(script.Parent.Input)

local function toggleBrowser()
	if shell.visible then
		shell:close()
	else
		shell:open()
		shell:setActive("SQUADS")
		-- immediate refresh on open rather than waiting for the cadence
		browserState.refreshToken += 1
		local token = browserState.refreshToken
		task.spawn(function()
			local browser = remotes:FindFirstChild("RequestSquadBrowser")
			if not browser then return end
			local ok, data = pcall(function()
				return browser:InvokeServer()
			end)
			if ok and type(data) == "table" and token == browserState.refreshToken then
				renderBrowser(data)
			end
		end)
	end
end

-- squad browser keybind: lobby context (same exclusivity logic as quick-response —
-- in-mission this input is dead)
Input.onPress("SquadBrowser", function()
	if workspace:GetAttribute("GF_InMission") == true then
		return
	end
	toggleBrowser()
end)

-- close on menu-back when open
Input.onPress("MenuBack", function()
	if shell.visible then
		shell:close()
	end
end)

print("[GF] squad browser online")
