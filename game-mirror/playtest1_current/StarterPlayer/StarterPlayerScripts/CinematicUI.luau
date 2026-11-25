--!strict
-- Plays the opening cinematic: scripted camera, letterbox, subtitles, skip and replay.
-- Publishes Cinematic_* attributes so playback timing can be checked from the server.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cinematic = require(ReplicatedStorage.GF.Shared.Configs.Cinematic)
local player = Players.LocalPlayer
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
gui.Parent = player:WaitForChild("PlayerGui")

local top = Instance.new("Frame")
top.Size = UDim2.new(1, 0, 0, 92)
top.BackgroundColor3 = Color3.new(0, 0, 0)
top.BorderSizePixel = 0
top.Parent = gui
local bottom = Instance.new("Frame")
bottom.Size = UDim2.new(1, 0, 0, 92)
bottom.Position = UDim2.new(0, 0, 1, -92)
bottom.BackgroundColor3 = Color3.new(0, 0, 0)
bottom.BorderSizePixel = 0
bottom.Parent = gui

local caption = Instance.new("TextLabel")
caption.Size = UDim2.new(0.8, 0, 0, 64)
caption.Position = UDim2.new(0.1, 0, 1, -156)
caption.BackgroundTransparency = 1
caption.Font = Enum.Font.GothamMedium
caption.TextSize = 20
caption.TextWrapped = true
caption.TextColor3 = Color3.fromRGB(232, 238, 244)
caption.TextStrokeTransparency = 0.6
if subtitlesEnabled() then caption.Text = "" end
caption.Parent = gui

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, 0, 0, 18)
hint.Position = UDim2.new(0, 0, 1, -30)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 12
hint.TextColor3 = Color3.fromRGB(120, 140, 150)
hint.Text = "SPACE to skip"
hint.Parent = gui

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
	if subtitlesEnabled() then caption.Text = "" end
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
	setAttr("Playing", true)
	setAttr("Skipped", false)
	setAttr("Total", Cinematic.totalDuration())
	local startedAt = os.clock()
	for index, beat in ipairs(Cinematic.Beats) do
		if skipRequested or not playing then
			break
		end
		beatIndex = index
		setAttr("Beat", index)
		setAttr("BeatText", beat.text)
		setAttr("Elapsed", math.floor(os.clock() - startedAt))
		if subtitlesEnabled() then caption.Text = beat.text end
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

