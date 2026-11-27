--!strict
-- S02-054 cross-place loading: consistent custom presentation across every teleport — the same
-- GF-branded screen whether heading to the station or the surface. The theatre treatment is
-- deliberately indeterminate: terrain generation has no percent feed, so motion carries progress.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local player = Players.LocalPlayer

local Tokens = require(ReplicatedStorage.GF.Shared.UI.Tokens)
local Missions = require(ReplicatedStorage.GF.Shared.Configs.Missions)
local WarOperations = require(ReplicatedStorage.GF.Shared.Configs.WarOperations)
local DeployContract = require(ReplicatedStorage.GF.Shared.DeployContract)

local COLOR = Tokens.Color
local TYPE = Tokens.Type
-- Mono is terminal metadata in the upgraded token API; the fallback keeps this surface compatible
-- with the original smaller token table while that parallel UI migration settles.
local MONO_FONT = (TYPE :: any).fontMono or TYPE.font
local MONO_BOLD = (TYPE :: any).fontMonoBold or TYPE.fontBold

-- The client-side arrival API is different from the server-side Player:GetJoinData path used by
-- the mission server. TeleportData itself is still the same DeployContract JSON string.
local deployIntent: any = nil
do
	local ok, data = pcall(function()
		return TeleportService:GetLocalPlayerTeleportData()
	end)
	if ok and type(data) == "string" then
		local decodedOk, decoded = pcall(function()
			return DeployContract.decode(data)
		end)
		if decodedOk and type(decoded) == "table" then
			deployIntent = decoded
		end
	elseif ok and type(data) == "table" and (data :: any).v == 1 then
		-- Tolerate legacy/native teleport-data tables without changing the v1 JSON contract.
		deployIntent = data
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "GFLoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function makeFrame(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, transparency: number?, zindex: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.ZIndex = zindex or 1
	f.Parent = parent
	return f
end

local function makeLabel(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, color: Color3, textSize: number, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = bold == true and TYPE.fontBold or TYPE.font
	l.TextSize = textSize
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = text
	l.ZIndex = 10
	l.Parent = parent
	return l
end

local pulsePieces: { Frame } = {}
local function cornerBracket(parent: Instance, corner: string, color: Color3, length: number, inset: number, zindex: number?, pulsing: boolean?)
	local left = corner == "TL" or corner == "BL"
	local topSide = corner == "TL" or corner == "TR"
	local ax = left and 0 or 1
	local ay = topSide and 0 or 1
	local x = left and inset or -inset
	local y = topSide and inset or -inset

	local horizontal = makeFrame(parent, corner .. "_H", UDim2.new(0, length, 0, 2), UDim2.new(ax, x, ay, y), color, 0.18, zindex or 8)
	horizontal.AnchorPoint = Vector2.new(ax, ay)
	local vertical = makeFrame(parent, corner .. "_V", UDim2.new(0, 2, 0, length), UDim2.new(ax, x, ay, y), color, 0.18, zindex or 8)
	vertical.AnchorPoint = Vector2.new(ax, ay)

	local notch = makeFrame(parent, corner .. "_N", UDim2.new(0, math.max(12, length * 0.34), 0, 2), UDim2.new(ax, left and x + 14 or x - 14, ay, topSide and y + 14 or y - 14), color, 0.1, zindex or 8)
	notch.AnchorPoint = Vector2.new(0.5, 0.5)
	notch.Rotation = (left == topSide) and 45 or -45

	if pulsing == true then
		table.insert(pulsePieces, horizontal)
		table.insert(pulsePieces, vertical)
		table.insert(pulsePieces, notch)
	end
end

local frame = Instance.new("Frame")
frame.Name = "Root"
frame.Size = UDim2.fromScale(1, 1)
frame.BackgroundColor3 = COLOR.panelInset
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = gui

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, COLOR.panelInset),
	ColorSequenceKeypoint.new(0.58, COLOR.panel),
	ColorSequenceKeypoint.new(1, COLOR.graphite),
})
gradient.Rotation = 112
gradient.Parent = frame

-- Quiet cartography/grid texture: broad surfaces stay calm, but never read as a frozen solid.
for index, y in ipairs({ 0.16, 0.32, 0.68, 0.84 }) do
	local gridLine = makeFrame(frame, "GridH" .. index, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, y, 0), COLOR.navy, 0.88, 1)
	gridLine.BackgroundTransparency = 0.88
end
for index, x in ipairs({ 0.18, 0.5, 0.82 }) do
	local gridLine = makeFrame(frame, "GridV" .. index, UDim2.new(0, 1, 1, 0), UDim2.new(x, 0, 0, 0), COLOR.navy, 0.91, 1)
	gridLine.BackgroundTransparency = 0.91
end

local scanBand = makeFrame(frame, "ScanBand", UDim2.new(1, 0, 0.14, 0), UDim2.new(0, 0, -0.14, 0), COLOR.techCyan, 0.86, 2)
local scanGradient = Instance.new("UIGradient")
scanGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.48, 0.58),
	NumberSequenceKeypoint.new(1, 1),
})
scanGradient.Rotation = 90
scanGradient.Parent = scanBand

-- Outer command frame, held in steel rather than arcade-bright cyan.
cornerBracket(frame, "TL", COLOR.steel, 78, 18, 3, false)
cornerBracket(frame, "TR", COLOR.steel, 78, 18, 3, false)
cornerBracket(frame, "BL", COLOR.steel, 78, 18, 3, false)
cornerBracket(frame, "BR", COLOR.steel, 78, 18, 3, false)

local commandLeft = makeLabel(frame, "CommandLeft", "GALACTIC FORCE  //  EXPEDITIONARY COMMAND", UDim2.new(0, 430, 0, 18), UDim2.new(0, 28, 0, 24), COLOR.textAccent, TYPE.sizeSmall, true)
commandLeft.Font = MONO_BOLD
local commandRight = makeLabel(frame, "CommandRight", "SECURE UPLINK", UDim2.new(0, 220, 0, 18), UDim2.new(1, -248, 0, 24), COLOR.textSecondary, TYPE.sizeSmall, false)
commandRight.Font = MONO_FONT
commandRight.TextXAlignment = Enum.TextXAlignment.Right

local floorLeft = makeLabel(frame, "FloorLeft", "TRANSITION CONTROL  //  VEYRA-7 THEATRE", UDim2.new(0, 390, 0, 16), UDim2.new(0, 28, 1, -42), COLOR.textSecondary, TYPE.sizeSmall, false)
floorLeft.Font = MONO_FONT
floorLeft.TextTransparency = 0.18
local floorRight = makeLabel(frame, "FloorRight", "ASCENDANCY FRONTIER", UDim2.new(0, 250, 0, 16), UDim2.new(1, -278, 1, -42), COLOR.warning, TYPE.sizeSmall, true)
floorRight.Font = MONO_BOLD
floorRight.TextXAlignment = Enum.TextXAlignment.Right
floorRight.TextTransparency = 0.12

local panel = makeFrame(frame, "TransitionPanel", UDim2.new(0.84, 0, 0, 288), UDim2.new(0.5, 0, 0.52, 0), COLOR.panelInset, 0.06, 5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.ClipsDescendants = true
local panelConstraint = Instance.new("UISizeConstraint")
panelConstraint.MinSize = Vector2.new(320, 288)
panelConstraint.MaxSize = Vector2.new(780, 328)
panelConstraint.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLOR.border
panelStroke.Transparency = 0.22
panelStroke.Thickness = 1
panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
panelStroke.Parent = panel

local headerBand = makeFrame(panel, "HeaderBand", UDim2.new(1, 0, 0, 88), UDim2.new(0, 0, 0, 0), COLOR.navy, 0.86, 5)
local headerGradient = Instance.new("UIGradient")
headerGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.18),
	NumberSequenceKeypoint.new(1, 1),
})
headerGradient.Parent = headerBand

local spine = makeFrame(panel, "CommandSpine", UDim2.new(0, 4, 1, 0), UDim2.new(0, 0, 0, 0), COLOR.techCyan, 0.08, 8)
makeFrame(panel, "SpineAmber", UDim2.new(0, 4, 0, 30), UDim2.new(0, 0, 0, 44), COLOR.warning, 0.05, 9)
cornerBracket(panel, "TL", COLOR.techCyan, 54, 10, 9, true)
cornerBracket(panel, "TR", COLOR.techCyan, 54, 10, 9, true)
cornerBracket(panel, "BL", COLOR.techCyan, 54, 10, 9, true)
cornerBracket(panel, "BR", COLOR.techCyan, 54, 10, 9, true)

local eyebrow = makeLabel(panel, "Eyebrow", "EXPEDITIONARY TRANSITION  //  ORBITAL INSERTION WINDOW", UDim2.new(1, -56, 0, 16), UDim2.new(0, 28, 0, 18), COLOR.textAccent, TYPE.sizeSmall, true)
eyebrow.Font = MONO_BOLD
local operationTitle = makeLabel(panel, "OperationTitle", "GALACTIC FORCE // COUNTEROFFENSIVE", UDim2.new(1, -56, 0, 28), UDim2.new(0, 28, 0, 40), COLOR.textPrimary, TYPE.sizeTitle, true)
local operationMeta = makeLabel(panel, "OperationMeta", "EXPEDITIONARY COMMAND  //  VEYRA-7", UDim2.new(1, -230, 0, 18), UDim2.new(0, 28, 0, 70), COLOR.textSecondary, TYPE.sizeSmall, false)
operationMeta.Font = MONO_FONT
local difficultyTag = makeLabel(panel, "DifficultyTag", "LINK OPEN", UDim2.new(0, 170, 0, 18), UDim2.new(1, -198, 0, 70), COLOR.textAccent, TYPE.sizeSmall, true)
difficultyTag.Font = MONO_BOLD
difficultyTag.TextXAlignment = Enum.TextXAlignment.Right

makeFrame(panel, "Divider", UDim2.new(1, -56, 0, 1), UDim2.new(0, 28, 0, 98), COLOR.border, 0.35, 7)
makeFrame(panel, "DividerHot", UDim2.new(0, 128, 0, 2), UDim2.new(0, 28, 0, 97), COLOR.techCyan, 0.18, 8)

local status = makeLabel(panel, "Status", "ESTABLISHING COMMAND LINK", UDim2.new(1, -56, 0, 22), UDim2.new(0, 28, 0, 112), COLOR.textPrimary, TYPE.sizeBody, true)
local flavor = makeLabel(panel, "Flavor", "ESTABLISHING ORBITAL UPLINK…", UDim2.new(1, -56, 0, 18), UDim2.new(0, 28, 0, 138), COLOR.textSecondary, TYPE.sizeSmall, false)
flavor.Font = MONO_FONT

local progressBack = makeFrame(panel, "ProgressBack", UDim2.new(1, -56, 0, 8), UDim2.new(0, 28, 0, 172), COLOR.graphite, 0, 7)
progressBack.ClipsDescendants = true
local progressStroke = Instance.new("UIStroke")
progressStroke.Color = COLOR.border
progressStroke.Transparency = 0.42
progressStroke.Thickness = 1
progressStroke.Parent = progressBack
local progressFill = makeFrame(progressBack, "ProgressFill", UDim2.new(0.24, 0, 1, 0), UDim2.new(-0.24, 0, 0, 0), COLOR.techCyan, 0.04, 8)
for index = 1, 15 do
	local tick = makeFrame(progressBack, "Tick" .. index, UDim2.new(0, 1, 1, 0), UDim2.new(index / 16, 0, 0, 0), COLOR.panelInset, 0.12, 9)
	tick.AnchorPoint = Vector2.new(0.5, 0)
end

local phaseLabel = makeLabel(panel, "PhaseLabel", "UPLINK T+000.0", UDim2.new(0, 150, 0, 15), UDim2.new(1, -178, 0, 188), COLOR.textSecondary, TYPE.sizeSmall, false)
phaseLabel.Font = MONO_FONT
phaseLabel.TextXAlignment = Enum.TextXAlignment.Right
local progressCaption = makeLabel(panel, "ProgressCaption", "INDETERMINATE TRANSITION  //  THEATRE WRITE IN PROGRESS", UDim2.new(1, -220, 0, 15), UDim2.new(0, 28, 0, 188), COLOR.textSecondary, TYPE.sizeSmall, false)
progressCaption.Font = MONO_FONT
progressCaption.TextTransparency = 0.12

local spinnerBox = makeFrame(panel, "SpinnerBox", UDim2.new(0, 38, 0, 38), UDim2.new(0, 28, 0, 216), COLOR.panelRaised, 0.08, 8)
local spinnerStroke = Instance.new("UIStroke")
spinnerStroke.Color = COLOR.techCyan
spinnerStroke.Transparency = 0.32
spinnerStroke.Thickness = 1
spinnerStroke.Parent = spinnerBox
local spinner = Instance.new("TextLabel")
spinner.Name = "Spinner"
spinner.Size = UDim2.fromScale(1, 1)
spinner.BackgroundTransparency = 1
spinner.Font = MONO_FONT
spinner.TextSize = TYPE.sizeTitle
spinner.TextColor3 = COLOR.textAccent
spinner.Text = "◢"
spinner.ZIndex = 10
spinner.Parent = spinnerBox

local tip = makeLabel(panel, "Tip", "SQUAD TIP: RESUPPLY CRATES RESTORE AMMUNITION AND GRENADES", UDim2.new(1, -104, 0, 18), UDim2.new(0, 78, 0, 220), COLOR.textSecondary, TYPE.sizeSmall, false)
tip.Font = MONO_FONT
tip.TextTransparency = 0.08
local theatreFooter = makeLabel(panel, "TheatreFooter", "DROP PROTOCOL ACTIVE  //  SQUAD TELEMETRY SEALED", UDim2.new(1, -104, 0, 15), UDim2.new(0, 78, 0, 242), COLOR.textSecondary, TYPE.sizeSmall, false)
theatreFooter.Font = MONO_FONT
theatreFooter.TextTransparency = 0.42

-- Compact viewports get the same hierarchy with fewer secondary readouts; nothing overlaps the
-- operation name or difficulty, which are the two pieces of mission context the screen exists to carry.
local function applyResponsiveLayout()
	local width = frame.AbsoluteSize.X
	if width <= 0 and workspace.CurrentCamera then
		width = workspace.CurrentCamera.ViewportSize.X
	end
	local compact = width > 0 and width < 640
	commandLeft.Size = UDim2.new(0, compact and 250 or 430, 0, 18)
	commandRight.Visible = not compact
	floorLeft.Visible = width == 0 or width >= 560
	floorRight.Visible = width == 0 or width >= 440
	panel.Size = UDim2.new(compact and 0.94 or 0.84, 0, 0, 288)
	operationTitle.TextSize = compact and TYPE.sizeBody or TYPE.sizeTitle
	status.TextSize = compact and TYPE.sizeSmall or TYPE.sizeBody
	operationMeta.Size = UDim2.new(1, compact and -184 or -230, 0, 18)
	difficultyTag.Size = UDim2.new(0, compact and 126 or 170, 0, 18)
	difficultyTag.Position = UDim2.new(1, compact and -154 or -198, 0, 70)
	progressCaption.Text = compact and "INDETERMINATE TRANSITION" or "INDETERMINATE TRANSITION  //  THEATRE WRITE IN PROGRESS"
	theatreFooter.Visible = not compact
end
frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyResponsiveLayout)
task.defer(applyResponsiveLayout)

local function uppercaseClean(value: any): string?
	if type(value) == "string" and value ~= "" then
		return string.upper((string.gsub(value, "_", " ")))
	end
	return nil
end

local function refreshOperation()
	local template = workspace:GetAttribute("GF_OperationTemplate")
	local difficulty = workspace:GetAttribute("GF_OperationDifficulty")
	local operationId = workspace:GetAttribute("GF_OperationId")
	if deployIntent then
		if type(deployIntent.template) == "string" then
			template = deployIntent.template
		end
		if type(deployIntent.difficulty) == "string" then
			difficulty = deployIntent.difficulty
		end
		if type(deployIntent.operationId) == "string" then
			operationId = deployIntent.operationId
		end
	end

	local operationName = nil
	local missionDef = nil
	if type(operationId) == "string" then
		operationName = WarOperations.DisplayName[operationId]
	end
	if type(template) == "string" then
		missionDef = Missions.get(template)
		if operationName == nil and missionDef then
			operationName = missionDef.displayName
		end
	end
	if operationName == nil and type(template) == "string" then
		operationName = uppercaseClean(template)
	end

	if operationName then
		operationTitle.Text = string.upper(tostring(operationName))
		local family = missionDef and uppercaseClean(missionDef.family) or "EXPEDITIONARY"
		local durationClass = missionDef and uppercaseClean(missionDef.durationClass) or "STANDARD"
		operationMeta.Text = string.format("%s OPERATION  //  %s PROFILE", tostring(family), tostring(durationClass))
	elseif workspace:GetAttribute("GF_Teleporting") == true then
		if workspace:GetAttribute("GF_InMission") == true then
			operationTitle.Text = "PLANETARY INSERTION"
			operationMeta.Text = "DESCENT PROFILE  //  VEYRA-7 SURFACE"
		else
			operationTitle.Text = "ORBITAL STATION RETURN"
			operationMeta.Text = "ASCENT PROFILE  //  COMMAND HANDSHAKE"
		end
	else
		operationTitle.Text = "GALACTIC FORCE // COUNTEROFFENSIVE"
		operationMeta.Text = "EXPEDITIONARY COMMAND  //  VEYRA-7"
	end

	local difficultyText = uppercaseClean(difficulty)
	if difficultyText then
		difficultyTag.Text = "DIFFICULTY " .. difficultyText
		difficultyTag.TextColor3 = (difficultyText == "HARD" or difficultyText == "EXTREME") and COLOR.warning or COLOR.textAccent
	else
		difficultyTag.Text = workspace:GetAttribute("GF_Teleporting") == true and "PRIORITY TRANSIT" or "LINK OPEN"
		difficultyTag.TextColor3 = COLOR.textSecondary
	end
end

for _, key in ipairs({ "GF_OperationTemplate", "GF_OperationDifficulty", "GF_OperationId" }) do
	workspace:GetAttributeChangedSignal(key):Connect(refreshOperation)
end
refreshOperation()

local SURVEY_FLAVOR = {
	"ESTABLISHING ORBITAL UPLINK…",
	"PLOTTING DESCENT VECTOR…",
	"RESOLVING THEATRE GEOMETRY…",
	"SYNCHRONIZING SQUAD TELEMETRY…",
	"CALIBRATING INSERTION TRAJECTORY…",
	"MASKING DROP SIGNATURE…",
}
local DEPLOY_FLAVOR = {
	"COMMITTING DROP COMMAND…",
	"TRANSFERRING OPERATION DOSSIER…",
	"LOCKING SQUAD INSERTION WINDOW…",
	"ROUTING ORBITAL FIRE SUPPORT…",
	"ARMING PLANETFALL PROTOCOL…",
}
local ARRIVAL_WRITE_FLAVOR = {
	"HOLDING INSERTION PATTERN…",
	"WRITING THEATRE GEOMETRY…",
	"VERIFYING LANDING ZONE GEOTELEMETRY…",
	"CONCEALING DROP SIGNATURE…",
}
local ARRIVAL_LANDING_FLAVOR = {
	"RELEASING INSERTION CLAMPS…",
	"RAYCASTING LZ GROUND TRUTH…",
	"SETTLING SQUAD ON SURFACE…",
	"TRANSFERRING CONTROL TO FIELD COMMAND…",
}
local RETURN_FLAVOR = {
	"SECURING SALVAGE MANIFEST…",
	"PLOTTING ORBITAL ASCENT…",
	"TRANSFERRING COMMAND HANDSHAKE…",
	"VERIFYING SQUAD RECOVERY…",
	"SPINNING UP RETURN VECTOR…",
}
local STANDBY_FLAVOR = {
	"MAINTAINING COMMAND LINK…",
	"VERIFYING THEATRE STATE…",
	"HOLDING TRANSITION WINDOW…",
}

local function activeFlavorLines(): { string }
	if workspace:GetAttribute("GF_Teleporting") == true then
		if workspace:GetAttribute("GF_InMission") == true then
			local arrivalState = workspace:GetAttribute("GF_ArrivalState")
			if arrivalState == "holding" then
				return ARRIVAL_WRITE_FLAVOR
			elseif arrivalState == "landing" or arrivalState == "ready" or arrivalState == "degraded" then
				return ARRIVAL_LANDING_FLAVOR
			end
			return DEPLOY_FLAVOR
		end
		return RETURN_FLAVOR
	end
	-- In the mission place the initial hold is terrain generation; in the lobby there is no survey.
	local mp = workspace:GetAttribute("GF_MissionPlaceId")
	if workspace:GetAttribute("GF_PlaceSplitLive") == true and type(mp) == "number" and mp ~= game.PlaceId then
		return STANDBY_FLAVOR
	end
	return SURVEY_FLAVOR
end

-- show during teleport transitions; hide once the world is ready
local function refreshStatus()
	if workspace:GetAttribute("GF_Teleporting") ~= true then
		status.Text = "ESTABLISHING COMMAND LINK"
	elseif workspace:GetAttribute("GF_InMission") == true then
		local arrivalState = workspace:GetAttribute("GF_ArrivalState")
		if arrivalState == "holding" then
			status.Text = "ORBITAL HOLD  //  THEATRE WRITE"
		elseif arrivalState == "landing" then
			status.Text = "LZ DESCENT  //  GROUND VERIFY"
		elseif arrivalState == "ready" then
			status.Text = "INSERTION COMPLETE"
		elseif arrivalState == "degraded" then
			status.Text = "DEGRADED INSERTION  //  EMERGENCY VERIFY"
		else
			status.Text = "DEPLOYING TO VEYRA-7  //  ORBITAL INSERTION"
		end
	else
		status.Text = "RETURNING TO ORBITAL STATION"
	end
	refreshOperation()
end
workspace:GetAttributeChangedSignal("GF_Teleporting"):Connect(function()
	frame.Visible = workspace:GetAttribute("GF_Teleporting") == true
	refreshStatus()
end)
workspace:GetAttributeChangedSignal("GF_InMission"):Connect(refreshStatus)
workspace:GetAttributeChangedSignal("GF_ArrivalState"):Connect(refreshStatus)

task.spawn(function()
	local glyphs = { "◢", "◣", "◤", "◥" }
	local index = 1
	local flavorIndex = 1
	local flavorSwapAt = 0
	local wasVisible = false
	local visibleSince = os.clock()
	while gui.Parent do
		local now = os.clock()
		if frame.Visible then
			if not wasVisible then
				visibleSince = now
				flavorSwapAt = 0
			end
			wasVisible = true

			-- Absolute failsafe, separate from the terrain wait below: even a wedged teleport flag
			-- cannot hold the player inside a decorative overlay forever.
			if now - visibleSince > 55 then
				frame.Visible = false
			end

			spinner.Text = glyphs[index]
			index = index % #glyphs + 1
			local phase = (now % 1.4) / 1.4
			progressFill.Position = UDim2.new(-0.24 + phase * 1.24, 0, 0, 0)
			scanBand.Position = UDim2.new(0, 0, -0.14 + ((now * 0.11) % 1.28), 0)
			phaseLabel.Text = string.format("UPLINK T+%05.1f", now - visibleSince)

			local pulse = 0.16 + 0.12 * (0.5 + 0.5 * math.sin(now * 2.6))
			for _, piece in ipairs(pulsePieces) do
				piece.BackgroundTransparency = pulse
			end

			if now >= flavorSwapAt then
				local lines = activeFlavorLines()
				if flavorIndex > #lines then
					flavorIndex = 1
				end
				flavor.Text = lines[flavorIndex]
				flavorIndex = flavorIndex % #lines + 1
				flavorSwapAt = now + 2.2
			end
		else
			wasVisible = false
		end
		task.wait(0.08)
	end
end)

-- initial presentation: hold until planetary terrain generation completes server-side.
-- GF_TerrainReady flips true at the end of TerrainService.build — covers the multi-second
-- battlefield write instead of letting players watch voxel tiles pop in. Terrain replication
-- to the client trails the server write slightly, so a short grace follows the ready signal.
-- place-split: the lobby has no planetary survey — terrain generation is mission-side now.
-- showing the survey screen in the lobby is nonsense copy AND it holds for the full 30s cap
-- because GF_TerrainReady never fires there. detect lobby context and skip the hold entirely.
local amLobby = false
do
	local mp = workspace:GetAttribute("GF_MissionPlaceId")
	if workspace:GetAttribute("GF_PlaceSplitLive") == true and type(mp) == "number" and mp ~= game.PlaceId then
		amLobby = true
	end
end
frame.Visible = not amLobby
status.Text = "SURVEYING PLANETARY SURFACE"
if workspace:GetAttribute("GF_Teleporting") == true then
	refreshStatus()
end
refreshOperation()
print(string.format("GFLOAD shown clock=%.2f readyAttr=%s", os.clock(), tostring(workspace:GetAttribute("GF_TerrainReady"))))
local initialDone = false
local function finishInitial()
	if initialDone then
		return
	end
	initialDone = true
	task.wait(1.2) -- replication grace for the last terrain tiles
	if workspace:GetAttribute("GF_Teleporting") ~= true then
		frame.Visible = false
	end
	print(string.format("GFLOAD hidden clock=%.2f", os.clock()))
end
task.spawn(function()
	local elapsed = 0
	while elapsed < 30 do -- hard cap: never trap the player on the screen
		if workspace:GetAttribute("GF_TerrainReady") == true then
			-- flavor: battlefield mode names the geological theater while it finishes
			local arch = workspace:GetAttribute("GF_BFArchetype")
			if arch then
				status.Text = "PLANETARY SURVEY COMPLETE"
			end
			finishInitial()
			return
		end
		task.wait(0.25)
		elapsed += 0.25
	end
	-- fallback: server never signaled (legacy flows) — don't hold the player hostage
	task.wait(0.8)
	if workspace:GetAttribute("GF_Teleporting") ~= true then
		frame.Visible = false
	end
end)
