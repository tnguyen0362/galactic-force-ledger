--!nonstrict
-- Hack skill-check ring. The server owns the challenge, the window and the hit test (HackingService);
-- this only draws it and reports presses. Design notes (researched against Dead-by-Daylight-style checks):
--  * the success window RE-ROLLS after every press, always ahead of the needle, so it cannot be memorised;
--  * the needle speeds up slightly on every hit (server side), a gold "perfect" core sits inside the window;
--  * the press carries the synced-clock time it happened, so latency never costs the player the hit;
--  * feedback is immediate: ring flash, result word, pips, short sound, miss shake;
--  * the panel is OFF-CENTRE (right of the reticle) in its own non-inset ScreenGui - it never covers the aim point;
--  * inputs: E / RMB / gamepad X or R2 / tap the panel. They are sunk while a hack is live (RMB no longer aims).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local Tokens = require(ReplicatedStorage.GF.Shared.UI.Tokens)
local HackState = Remotes:WaitForChild("HackState")
local HackAttempt = Remotes:WaitForChild("HackAttempt")

local RING_R, TICKS = 88, 120
local GOLD = Color3.fromRGB(255, 214, 92)
local WHITE = Color3.fromRGB(245, 250, 255)
local DIM = Tokens.Color.textDisabled
local GREEN = Tokens.Color.success
local RED = Tokens.Color.danger

local gui = Instance.new("ScreenGui")
gui.Name = "GF_HackGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Name = "Panel"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.66, 0.58)
root.Size = UDim2.fromOffset(250, 318)
root.BackgroundColor3 = Tokens.Color.panelInset
root.BackgroundTransparency = 0.18
root.BorderSizePixel = 0
root.Parent = gui
local rootStroke = Instance.new("UIStroke")
rootStroke.Color = Tokens.Color.techCyan
rootStroke.Transparency = 0.35
rootStroke.Thickness = 1.5
rootStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
rootStroke.Parent = root
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function makeLabel(text, size, pos, textSize, color, bold)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Text = text
	l.TextSize = textSize
	l.TextColor3 = color
	l.Font = bold and Tokens.Type.fontBold or Enum.Font.GothamMedium
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.Parent = root
	return l
end

local title = makeLabel("SIGNAL OVERRIDE", UDim2.fromOffset(250, 24), UDim2.fromOffset(0, 8), 16, Tokens.Color.techCyan, true)
local resultLabel = makeLabel("", UDim2.fromOffset(250, 22), UDim2.fromOffset(0, 32), 16, WHITE, true)
local hint = makeLabel("", UDim2.fromOffset(250, 20), UDim2.fromOffset(0, 292), 13, Tokens.Color.textSecondary, false)

-- ring: 120 thin ticks read as a smooth circle; the success window is the lit segment
local ringHolder = Instance.new("Frame")
ringHolder.Name = "Ring"
ringHolder.AnchorPoint = Vector2.new(0.5, 0.5)
ringHolder.Position = UDim2.fromOffset(125, 152)
ringHolder.Size = UDim2.fromOffset(2 * RING_R + 30, 2 * RING_R + 30)
ringHolder.BackgroundTransparency = 1
ringHolder.Parent = root

local flash = Instance.new("Frame")
flash.AnchorPoint = Vector2.new(0.5, 0.5)
flash.Position = UDim2.fromScale(0.5, 0.5)
flash.Size = UDim2.fromOffset(2 * RING_R - 6, 2 * RING_R - 6)
flash.BackgroundColor3 = WHITE
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 1
flash.Parent = ringHolder
local flashCorner = Instance.new("UICorner")
flashCorner.CornerRadius = UDim.new(0.5, 0)
flashCorner.Parent = flash

local ticks, baseColor, tickAngle = {}, {}, {}
for i = 1, TICKS do
	local t = Instance.new("Frame")
	local angle = (i - 1) / TICKS * 360
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.BorderSizePixel = 0
	t.Size = UDim2.fromOffset(4, 8)
	t.BackgroundColor3 = DIM
	t.BackgroundTransparency = 0.25
	t.Rotation = angle
	local rad = math.rad(angle - 90)
	t.Position = UDim2.new(0.5, math.cos(rad) * RING_R, 0.5, math.sin(rad) * RING_R)
	t.ZIndex = 2
	t.Parent = ringHolder
	ticks[i], baseColor[i], tickAngle[i] = t, DIM, angle
end

local needle = Instance.new("Frame")
needle.AnchorPoint = Vector2.new(0.5, 1)
needle.Position = UDim2.fromScale(0.5, 0.5)
needle.Size = UDim2.fromOffset(3, RING_R - 8)
needle.BackgroundColor3 = WHITE
needle.BorderSizePixel = 0
needle.ZIndex = 5
needle.Parent = ringHolder
local head = Instance.new("Frame")
head.AnchorPoint = Vector2.new(0.5, 0.5)
head.Position = UDim2.fromScale(0.5, 0)
head.Size = UDim2.fromOffset(11, 11)
head.Rotation = 45
head.BackgroundColor3 = WHITE
head.BorderSizePixel = 0
head.ZIndex = 6
head.Parent = needle
local hub = Instance.new("Frame")
hub.AnchorPoint = Vector2.new(0.5, 0.5)
hub.Position = UDim2.fromScale(0.5, 0.5)
hub.Size = UDim2.fromOffset(10, 10)
hub.Rotation = 45
hub.BackgroundColor3 = Tokens.Color.techCyan
hub.BorderSizePixel = 0
hub.ZIndex = 6
hub.Parent = ringHolder

local stageLabel = Instance.new("TextLabel")
stageLabel.BackgroundTransparency = 1
stageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
stageLabel.Position = UDim2.new(0.5, 0, 0.5, 34)
stageLabel.Size = UDim2.fromOffset(80, 30)
stageLabel.Font = Tokens.Type.fontBold
stageLabel.TextSize = 26
stageLabel.TextColor3 = WHITE
stageLabel.Text = "0/3"
stageLabel.ZIndex = 3
stageLabel.Parent = ringHolder

local pips = {}
for i = 1, 3 do
	local p = Instance.new("Frame")
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Size = UDim2.fromOffset(14, 14)
	p.Rotation = 45
	p.Position = UDim2.fromOffset(125 + (i - 2) * 34, 274)
	p.BackgroundColor3 = DIM
	p.BorderSizePixel = 0
	p.Parent = root
	pips[i] = p
end

local press = Instance.new("TextButton") -- tap target for touch / mouse
press.BackgroundTransparency = 1
press.Size = UDim2.fromScale(1, 1)
press.Text = ""
press.ZIndex = 20
press.Parent = root

-- ---------------------------------------------------------------------------------------------
local hack = nil
local lastAttempts = 0
local session = 0
local function interactKey()
	if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		return "TAP"
	elseif UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		return "X"
	end
	return "E / RMB"
end

local function ping(good)
	local s = Instance.new("Sound")
	s.SoundId = good and "rbxasset://sounds/electronicpingshort.wav" or "rbxasset://sounds/uuhhh.mp3"
	s.Volume = good and 0.5 or 0.35
	s.PlaybackSpeed = good and 1.25 or 1.6
	s.Parent = SoundService
	s:Play()
	task.delay(1.2, function()
		s:Destroy()
	end)
end

local function shake()
	task.spawn(function()
		local base = root.Position
		for i = 1, 6 do
			local dx = (i % 2 == 0 and 1 or -1) * (8 - i)
			root.Position = base + UDim2.fromOffset(dx, 0)
			task.wait(0.03)
		end
		root.Position = base
	end)
end

local function showResult(text, color, good)
	resultLabel.Text = text
	resultLabel.TextColor3 = color
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 0.45
	TweenService:Create(flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	rootStroke.Color = color
	TweenService:Create(rootStroke, TweenInfo.new(0.5), { Color = Tokens.Color.techCyan }):Play()
	ping(good)
	local mine = session
	task.delay(0.7, function()
		if mine == session and hack then
			resultLabel.Text = ""
		end
	end)
end

local function paint(p)
	local arcStart = p.arcStart or 0
	local arcWidth = p.arcWidth or 90
	for i = 1, TICKS do
		local delta = math.abs((tickAngle[i] - arcStart + 180) % 360 - 180)
		local t = ticks[i]
		if delta <= arcWidth * 0.15 then
			baseColor[i] = GOLD
			t.Size = UDim2.fromOffset(6, 22)
			t.BackgroundTransparency = 0
		elseif delta <= arcWidth / 2 then
			baseColor[i] = GREEN
			t.Size = UDim2.fromOffset(5, 17)
			t.BackgroundTransparency = 0.05
		else
			baseColor[i] = DIM
			t.Size = UDim2.fromOffset(3, 8)
			t.BackgroundTransparency = 0.3
		end
		t.BackgroundColor3 = baseColor[i]
	end
	local stage = p.stage or 0
	stageLabel.Text = string.format("%d/3", stage)
	for i = 1, 3 do
		pips[i].BackgroundColor3 = (i <= stage) and GREEN or DIM
	end
	hint.Text = "PRESS " .. interactKey() .. " WHEN THE NEEDLE IS IN THE GREEN"
end

local function sendPress()
	if hack then
		HackAttempt:FireServer(hack.id, workspace:GetServerTimeNow())
	end
end

local function onAction(_, state)
	if state == Enum.UserInputState.Begin then
		sendPress()
	end
	return Enum.ContextActionResult.Sink
end
press.Activated:Connect(sendPress)

local function bind()
	ContextActionService:BindActionAtPriority(
		"GF_HackPress",
		onAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.E,
		Enum.UserInputType.MouseButton2,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.ButtonR2
	)
end

local function close(result)
	session += 1
	local mine = session
	hack = nil
	ContextActionService:UnbindAction("GF_HackPress")
	if result == "complete" then
		stageLabel.Text = "3/3"
		for i = 1, 3 do
			pips[i].BackgroundColor3 = GREEN
		end
		showResult("ACCESS GRANTED", GREEN, true)
		task.delay(0.8, function()
			if mine == session then
				gui.Enabled = false
			end
		end)
	else
		gui.Enabled = false
	end
end

HackState.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.active ~= true then
		if hack then
			close(type(payload) == "table" and payload.result or nil)
		end
		return
	end
	local fresh = hack == nil or hack.id ~= payload.id
	hack = payload
	if fresh then
		session += 1
		lastAttempts = payload.attempts or 0
		resultLabel.Text = ""
		gui.Enabled = true
		bind()
	elseif (payload.attempts or 0) > lastAttempts then
		lastAttempts = payload.attempts
		if payload.lastHit then
			showResult(payload.lastPerfect and "PERFECT" or "HIT", payload.lastPerfect and GOLD or GREEN, true)
		else
			showResult("MISS", RED, false)
			shake()
		end
	end
	paint(payload)
end)

RunService.RenderStepped:Connect(function()
	if not hack then
		return
	end
	local period = hack.period or 1.3
	local angle = ((workspace:GetServerTimeNow() - (hack.startedAt or 0)) / period * 360) % 360
	needle.Rotation = angle
	-- fading comet trail behind the needle so the sweep direction and speed read at a glance
	for i = 1, TICKS do
		local behind = (angle - tickAngle[i]) % 360
		local t = ticks[i]
		if behind < 38 then
			t.BackgroundColor3 = baseColor[i]:Lerp(WHITE, (1 - behind / 38) * 0.75)
		elseif t.BackgroundColor3 ~= baseColor[i] then
			t.BackgroundColor3 = baseColor[i]
		end
	end
end)

local function rescale()
	local camera = workspace.CurrentCamera
	if camera then
		uiScale.Scale = math.clamp(camera.ViewportSize.Y / 1080, 0.75, 1.5)
	end
end
rescale()
local cam = workspace.CurrentCamera
if cam then
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end
