--!strict
-- S01-025 tutorial drop: contextual hints teach the core loop on the first mission — movement,
-- sprint/vault, telegraphed dodge, aim/fire/reload, shield break/regen, loot, abilities, hacking.
-- Each hint fires once per player, triggered by live game events rather than a fixed script,
-- so the teaching tracks what the player is actually doing.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialHints"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Size = UDim2.new(0.5, 0, 0, 30)
label.Position = UDim2.new(0.25, 0, 0.68, 0)
label.BackgroundTransparency = 0.4
label.BackgroundColor3 = Color3.fromRGB(12, 16, 20)
label.TextColor3 = Color3.fromRGB(240, 230, 180)
label.Font = Enum.Font.GothamMedium
label.TextSize = 16
label.TextStrokeTransparency = 0.6
label.Visible = false
label.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = label

local shown: { [string]: boolean } = {}
local queue: { string } = {}
local displaying = false

local function hintOnce(id: string, text: string)
	if shown[id] then return end
	shown[id] = true
	table.insert(queue, text)
end

-- display queue: one hint at a time, 4.5s each
task.spawn(function()
	while true do
		task.wait(0.5)
		if not displaying and #queue > 0 then
			displaying = true
			local text = table.remove(queue, 1)
			label.Text = text
			label.Visible = true
			task.wait(4.5)
			label.Visible = false
			displaying = false
		end
	end
end)

local function isFirstMission(): boolean
	return workspace:GetAttribute("GF_InMission") == true and not shown._done
end

-- drop: movement/camera/sprint hints when the mission begins
local missionWas = false
task.spawn(function()
	while true do
		task.wait(1)
		local inMission = workspace:GetAttribute("GF_InMission") == true
		if inMission and not missionWas then
			missionWas = true
			if player:GetAttribute("GF_TutorialDone") ~= true then
				hintOnce("move", "WASD to move — mouse to look. SHIFT to sprint.")
				task.delay(6, function()
					hintOnce("vault", "Jump toward low cover to vault over it automatically.")
				end)
				task.delay(12, function()
					hintOnce("aim", "Right-click to aim down sights. Watch your reticle bloom.")
				end)
				task.delay(20, function()
					hintOnce("ability", "You carry support abilities — try the Airstrike or Dome Shield when pressed.")
				end)
			end
		end
		missionWas = inMission
	end
end)

-- dodge hint on first enemy telegraph
local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local telegraph = remotes:FindFirstChild("EnemyTelegraph")
if telegraph then
	telegraph.OnClientEvent:Connect(function()
		if isFirstMission() then
			hintOnce("dodge", "Enemy wind-up! CTRL to dodge out of the line — the tell never lies.")
		end
	end)
end

-- reload hint when ammo low
task.spawn(function()
	while true do
		task.wait(2)
		if isFirstMission() then
			local ammo = workspace:GetAttribute("GF_Ammo") or 999
			if ammo <= 4 then
				hintOnce("reload", "Magazine low — R to reload before the next push.")
			end
		end
	end
end)

-- shield break/regen explanation
task.spawn(function()
	local broke = false
	while true do
		task.wait(1)
		if isFirstMission() then
			local shield = workspace:GetAttribute("GF_Shield") or 100
			if shield <= 0 and not broke then
				broke = true
				hintOnce("shield", "Shield down! Break line of sight — it regenerates after a few seconds out of fire.")
			end
		end
	end
end)

-- loot hint on first pickup
workspace:GetAttributeChangedSignal("GF_LastPickup"):Connect(function()
	if isFirstMission() then
		hintOnce("loot", "Salvage collected automatically — it's shared with your squad.")
	end
end)

-- hacking hint near the relay
task.spawn(function()
	while true do
		task.wait(3)
		if isFirstMission() then
			local dist = workspace:GetAttribute("GF_RelayDist") or 999
			if dist < 30 then
				hintOnce("hack", "Relay ahead — hold E at the console to hack it. Stay close, it takes a moment.")
			end
		end
	end
end)
