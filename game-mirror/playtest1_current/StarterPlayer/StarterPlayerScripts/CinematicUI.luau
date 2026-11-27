--!strict
-- Plays the opening cinematic: scripted camera, letterbox, subtitles, skip and replay.
-- Publishes Cinematic_* attributes so playback timing can be checked from the server.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cinematic = require(ReplicatedStorage.GF.Shared.Configs.Cinematic)
local Tokens = require(ReplicatedStorage.GF.Shared.UI.Tokens)
local player = Players.LocalPlayer

local COLOR = Tokens.Color
local TYPE = Tokens.Type
local MONO_FONT = (TYPE :: any).fontMono or TYPE.font
local MONO_BOLD = (TYPE :: any).fontMonoBold or TYPE.fontBold

-- Subtitles setting: captions are part of the accessibility contract, but a player who turned them off
-- should not see them. One accessor so every caption path obeys it.
local function subtitlesEnabled(): boolean
	return player:GetAttribute("GF_Setting_Subtitles") ~= false
end

local gui = Instance.new("ScreenGui")
gui.Name = "Cinematic"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.DisplayOrder = 40
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

	local horizontal = makeFrame(parent, corner .. "_H", UDim2.new(0, length, 0, 2), UDim2.new(ax, x, ay, y), color, 0.22, zindex or 8)
	horizontal.AnchorPoint = Vector2.new(ax, ay)
	local vertical = makeFrame(parent, corner .. "_V", UDim2.new(0, 2, 0, length), UDim2.new(ax, x, ay, y), color, 0.22, zindex or 8)
	vertical.AnchorPoint = Vector2.new(ax, ay)
	local notch = makeFrame(parent, corner .. "_N", UDim2.new(0, math.max(12, length * 0.34), 0, 2), UDim2.new(ax, left and x + 13 or x - 13, ay, topSide and y + 13 or y - 13), color, 0.14, zindex or 8)
	notch.AnchorPoint = Vector2.new(0.5, 0.5)
	notch.Rotation = (left == topSide) and 45 or -45
	if pulsing == true then
		table.insert(pulsePieces, horizontal)
		table.insert(pulsePieces, vertical)
		table.insert(pulsePieces, notch)
	end
end

local top = makeFrame(gui, "TopLetterbox", UDim2.new(1, 0, 0, 92), UDim2.new(0, 0, 0, 0), COLOR.panelInset, 0, 2)
local bottom = makeFrame(gui, "BottomLetterbox", UDim2.new(1, 0, 0, 92), UDim2.new(0, 0, 1, -92), COLOR.panelInset, 0, 2)

local topGradient = Instance.new("UIGradient")
topGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, COLOR.graphite),
	ColorSequenceKeypoint.new(1, COLOR.panelInset),
})
topGradient.Rotation = 90
topGradient.Parent = top
local bottomGradient = Instance.new("UIGradient")
bottomGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, COLOR.panelInset),
	ColorSequenceKeypoint.new(1, COLOR.graphite),
})
bottomGradient.Rotation = 90
bottomGradient.Parent = bottom

makeFrame(top, "InnerCyan", UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1), COLOR.techCyan, 0.32, 4)
makeFrame(top, "InnerAmberL", UDim2.new(0, 112, 0, 2), UDim2.new(0, 32, 1, -5), COLOR.warning, 0.28, 4)
makeFrame(top, "InnerAmberR", UDim2.new(0, 112, 0, 2), UDim2.new(1, -144, 1, -5), COLOR.warning, 0.28, 4)
makeFrame(bottom, "InnerCyan", UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 0, 0), COLOR.techCyan, 0.32, 4)
makeFrame(bottom, "InnerAmberL", UDim2.new(0, 112, 0, 2), UDim2.new(0, 32, 0, 4), COLOR.warning, 0.28, 4)
makeFrame(bottom, "InnerAmberR", UDim2.new(0, 112, 0, 2), UDim2.new(1, -144, 0, 4), COLOR.warning, 0.28, 4)

cornerBracket(top, "TL", COLOR.steel, 46, 12, 5, false)
cornerBracket(top, "TR", COLOR.steel, 46, 12, 5, false)
cornerBracket(bottom, "BL", COLOR.steel, 46, 12, 5, false)
cornerBracket(bottom, "BR", COLOR.steel, 46, 12, 5, false)

local archiveKicker = makeLabel(top, "ArchiveKicker", "ORBITAL ARCHIVE  //  COMMAND RECORD", UDim2.new(0, 360, 0, 16), UDim2.new(0, 32, 0, 16), COLOR.textAccent, TYPE.sizeSmall, true)
archiveKicker.Font = MONO_BOLD
archiveKicker.TextTransparency = 0.08
local archiveTitle = makeLabel(top, "ArchiveTitle", string.upper(Cinematic.Title), UDim2.new(0, 520, 0, 24), UDim2.new(0, 32, 0, 40), COLOR.textPrimary, TYPE.sizeTitle, true)
local beatReadout = makeLabel(top, "BeatReadout", "ARCHIVE STANDBY", UDim2.new(0, 210, 0, 18), UDim2.new(1, -242, 0, 38), COLOR.textSecondary, TYPE.sizeSmall, false)
beatReadout.Font = MONO_FONT
beatReadout.TextXAlignment = Enum.TextXAlignment.Right

local progressBack = makeFrame(bottom, "ArchiveProgressBack", UDim2.new(1, -64, 0, 3), UDim2.new(0, 32, 0, 12), COLOR.graphite, 0.05, 5)
local progressFill = makeFrame(progressBack, "ArchiveProgressFill", UDim2.new(0, 0, 1, 0), UDim2.new(0, 0, 0, 0), COLOR.techCyan, 0.08, 6)
makeFrame(bottom, "ProgressAmberKey", UDim2.new(0, 44, 0, 3), UDim2.new(0, 32, 0, 12), COLOR.warning, 0.1, 7)

local hint = makeLabel(bottom, "SkipHint", "[ SPACE / ESC ]  SKIP TRANSMISSION", UDim2.new(0, 320, 0, 20), UDim2.new(0.5, -160, 0, 42), COLOR.textSecondary, TYPE.sizeSmall, false)
hint.Font = MONO_FONT
hint.TextXAlignment = Enum.TextXAlignment.Center
local hintAccentL = makeFrame(bottom, "HintAccentL", UDim2.new(0, 28, 0, 2), UDim2.new(0.5, -190, 0, 51), COLOR.techCyan, 0.18, 5)
local hintAccentR = makeFrame(bottom, "HintAccentR", UDim2.new(0, 28, 0, 2), UDim2.new(0.5, 162, 0, 51), COLOR.techCyan, 0.18, 5)

local captionPlate = makeFrame(gui, "CaptionPlate", UDim2.new(0.76, 0, 0, 76), UDim2.new(0.5, 0, 1, -174), COLOR.panelInset, 0.1, 6)
captionPlate.AnchorPoint = Vector2.new(0.5, 0)
captionPlate.Visible = false
local captionConstraint = Instance.new("UISizeConstraint")
captionConstraint.MinSize = Vector2.new(320, 76)
captionConstraint.MaxSize = Vector2.new(920, 92)
captionConstraint.Parent = captionPlate
local captionStroke = Instance.new("UIStroke")
captionStroke.Color = COLOR.border
captionStroke.Transparency = 0.28
captionStroke.Thickness = 1
captionStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
captionStroke.Parent = captionPlate
cornerBracket(captionPlate, "TL", COLOR.techCyan, 32, 7, 8, true)
cornerBracket(captionPlate, "TR", COLOR.techCyan, 32, 7, 8, true)
cornerBracket(captionPlate, "BL", COLOR.techCyan, 32, 7, 8, true)
cornerBracket(captionPlate, "BR", COLOR.techCyan, 32, 7, 8, true)
makeFrame(captionPlate, "CaptionSpine", UDim2.new(0, 3, 1, -18), UDim2.new(0, 9, 0, 9), COLOR.techCyan, 0.12, 8)

local caption = makeLabel(captionPlate, "Caption", "", UDim2.new(1, -52, 1, -20), UDim2.new(0, 26, 0, 10), COLOR.textPrimary, TYPE.sizeBody, false)
caption.TextWrapped = true
caption.TextXAlignment = Enum.TextXAlignment.Center
caption.TextYAlignment = Enum.TextYAlignment.Center
caption.TextStrokeTransparency = 0.75

-- Compact viewports keep the archive chrome but surrender secondary metadata before they collide.
local function applyResponsiveLayout()
	local width = top.AbsoluteSize.X
	if width <= 0 and workspace.CurrentCamera then
		width = workspace.CurrentCamera.ViewportSize.X
	end
	local compact = width > 0 and width < 640
	archiveKicker.Size = UDim2.new(0, compact and 210 or 360, 0, 16)
	archiveTitle.Size = UDim2.new(0, compact and math.max(180, width - 64) or 520, 0, 24)
	archiveTitle.TextSize = compact and TYPE.sizeBody or TYPE.sizeTitle
	beatReadout.Visible = not compact
	hint.Text = compact and "[ SPACE ]  SKIP" or "[ SPACE / ESC ]  SKIP TRANSMISSION"
	hintAccentL.Visible = not compact
	hintAccentR.Visible = not compact
	captionPlate.Size = UDim2.new(compact and 0.92 or 0.76, 0, 0, 76)
end
top:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyResponsiveLayout)
task.defer(applyResponsiveLayout)

local function setCaption(text: string)
	if subtitlesEnabled() then
		caption.Text = text
		captionPlate.Visible = text ~= ""
	else
		caption.Text = ""
		captionPlate.Visible = false
	end
end

-- restrained pulse on the caption frame only; the picture itself remains the focus
task.spawn(function()
	while gui.Parent do
		if gui.Enabled then
			local pulse = 0.18 + 0.1 * (0.5 + 0.5 * math.sin(os.clock() * 2.2))
			for _, piece in ipairs(pulsePieces) do
				piece.BackgroundTransparency = pulse
			end
			hintAccentL.BackgroundTransparency = pulse
			hintAccentR.BackgroundTransparency = pulse
		end
		task.wait(0.1)
	end
end)

local playing, beatIndex, skipRequested = false, 0, false
local savedType, savedFov = nil, nil
local savedSubject = nil

local function setAttr(key, value)
	workspace:SetAttribute("Cinematic_" .. key, value)
end

-- The attribute alone was never persisted, so every rejoin replayed the intro. This is the only place
-- that tells the server the player has seen it.
local function persistIntroSeen()
	player:SetAttribute("IntroSeen", true)
	local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("GF")
	local folder = remotes and remotes:FindFirstChild("Remotes")
	local mark = folder and folder:FindFirstChild("MarkIntroSeen")
	if mark and mark:IsA("RemoteEvent") then
		mark:FireServer()
	end
end

local function stopPlayback(skipped)
	-- Mark the intro as seen here, not only on first run: a skip used to leave IntroSeen unset, so the
	-- next CharacterAdded replayed the whole cinematic and stole the camera with no subject.
	persistIntroSeen()
	playing = false
	gui.Enabled = false
	setCaption("")
	setAttr("Playing", false)
	setAttr("Beat", beatIndex)
	setAttr("Skipped", skipped == true)
	if player.CameraMode ~= Enum.CameraMode.Classic then
		player.CameraMode = Enum.CameraMode.Classic
	end
	local camera = workspace.CurrentCamera
	if camera then
		-- savedType was whatever the camera happened to be when playback started, and once that was
		-- Fixed the player kept a frozen camera after every intro (measured: CameraType=Fixed,
		-- CameraSubject=nil once the cinematic stopped). Always hand control back to the humanoid.
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = savedSubject or humanoid
		camera.FieldOfView = savedFov or 70
	end
end

local function play()
	if playing then
		return
	end
	-- A stop that arrives before the intro starts must not be overwritten by a late play(). The
	-- skip attribute was only consulted by a change handler, so a cinematic that began after the
	-- skip still took the camera and left it Scriptable with no subject (measured CameraType=Fixed,
	-- CameraSubject=nil).
	if workspace:GetAttribute("GF_CinematicStop") == true then
		return
	end
	playing, beatIndex, skipRequested = true, 0, false
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	savedType = camera.CameraType
	savedSubject = camera.CameraSubject
	savedFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	gui.Enabled = true
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	beatReadout.Text = "ARCHIVE RUNNING"
	setAttr("Playing", true)
	setAttr("Skipped", false)
	local totalDuration = Cinematic.totalDuration()
	setAttr("Total", totalDuration)
	local startedAt = os.clock()
	for index, beat in ipairs(Cinematic.Beats) do
		if skipRequested or not playing then
			break
		end
		beatIndex = index
		setAttr("Beat", index)
		setAttr("BeatText", beat.text)
		setAttr("Elapsed", math.floor(os.clock() - startedAt))
		beatReadout.Text = string.format("BEAT %02d/%02d", index, #Cinematic.Beats)
		setCaption(beat.text)
		local start = CFrame.lookAt(beat.from, beat.lookFrom)
		local finish = CFrame.lookAt(beat.to, beat.lookTo)
		camera.CFrame = start
		local tween = TweenService:Create(camera, TweenInfo.new(beat.duration, Enum.EasingStyle.Linear), { CFrame = finish })
		tween:Play()
		local deadline = os.clock() + beat.duration
		while os.clock() < deadline do
			if skipRequested then
				tween:Cancel()
				break
			end
			if totalDuration > 0 then
				local alpha = math.clamp((os.clock() - startedAt) / totalDuration, 0, 1)
				progressFill.Size = UDim2.new(alpha, 0, 1, 0)
			end
			task.wait(0.1)
		end
	end
	setAttr("Duration", math.floor(os.clock() - startedAt))
	stopPlayback(skipRequested)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if playing and not processed and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Escape) then
		skipRequested = true
		setAttr("Skipped", true)
	end
end)

workspace:GetAttributeChangedSignal("GF_CinematicStop"):Connect(function()
	if workspace:GetAttribute("GF_CinematicStop") then
		skipRequested = true
		if playing then
			-- hand the camera back on the same frame the skip arrives, not one beat later
			stopPlayback(true)
		end
	end
end)
workspace:GetAttributeChangedSignal("GF_CinematicPlay"):Connect(function()
	if workspace:GetAttribute("GF_CinematicPlay") then
		play()
	end
end)

task.defer(function()
	task.wait(3)
	local profile = player:FindFirstChild("ProfileLoaded")
	if workspace:GetAttribute("Tutorial_Active") == true and workspace:GetAttribute("Tutorial_Complete") ~= true then
		return
	end
	if workspace:GetAttribute("GF_PlayIntro") == true then
		play()
	elseif not player:GetAttribute("IntroSeen") then
		play()
		persistIntroSeen()
	end
end)

-- Archive replay: the only path that plays the intro for someone who has already seen it.
task.defer(function()
	task.wait(1)
	local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("GF")
	local folder = remotes and remotes:FindFirstChild("Remotes")
	local listen = folder and folder:FindFirstChild("IntroReplay")
	if listen and listen:IsA("RemoteEvent") then
		listen.OnClientEvent:Connect(function()
			play()
		end)
	end
end)

workspace:SetAttribute("Cinematic_Ready", true)
