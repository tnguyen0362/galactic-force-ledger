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
-- FORM section: declare an operation publicly and the listing goes fleet-wide.
-- operation picker is region-grouped from the shared war roster — the same source the
-- deploy terminals use, so what you form is exactly what you deploy. after forming, the
-- leader physically reports to their region's terminal to launch when the squad fills.
-- ---------------------------------------------------------------------------
local WarModel = require(game:GetService("ReplicatedStorage").GF.Shared.WarModel)
local WarOperations = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.WarOperations)
local Difficulties = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Difficulties)

local formState = {
	operationId = nil :: string?,
	difficulty = "Normal",
	public = true,
	statusLine = nil :: TextLabel?,
	opButtons = {} :: { [string]: TextButton },
	diffButtons = {} :: { [string]: TextButton },
	privButtons = {} :: { [string]: TextButton },
}

local function refreshChips()
	for opId, btn in pairs(formState.opButtons) do
		local sel = opId == formState.operationId
		btn.BackgroundColor3 = sel and Tokens.Color.navy or Tokens.Color.panelInset
	end
	for diff, btn in pairs(formState.diffButtons) do
		btn.BackgroundColor3 = diff == formState.difficulty and Tokens.Color.navy or Tokens.Color.panelInset
	end
	for key, btn in pairs(formState.privButtons) do
		btn.BackgroundColor3 = (key == "public") == formState.public and Tokens.Color.navy or Tokens.Color.panelInset
	end
end

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
