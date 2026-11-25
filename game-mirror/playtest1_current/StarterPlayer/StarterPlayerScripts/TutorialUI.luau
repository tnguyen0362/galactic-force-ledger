--!strict
-- First Spear prompt panel + world marker for the current objective.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Tutorial"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(420, 74)
panel.Position = UDim2.new(0.5, 0, 0, 96)
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = gui
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(96, 160, 190)
stroke.Thickness = 1
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 22)
title.Position = UDim2.new(0, 12, 0, 10)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(120, 200, 225)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "OPERATION FIRST SPEAR"
title.Parent = panel

local body = Instance.new("TextLabel")
body.Size = UDim2.new(1, -24, 0, 20)
body.Position = UDim2.new(0, 12, 0, 30)
body.BackgroundTransparency = 1
body.Font = Enum.Font.GothamMedium
body.TextSize = 15
body.TextColor3 = Color3.fromRGB(232, 238, 244)
body.TextXAlignment = Enum.TextXAlignment.Left
body.Text = ""
body.Parent = panel

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -24, 0, 16)
hint.Position = UDim2.new(0, 12, 0, 50)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 12
hint.TextColor3 = Color3.fromRGB(150, 170, 180)
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = ""
hint.Parent = panel

local marker = Instance.new("Part")
marker.Name = "TutorialMarker"
marker.Shape = Enum.PartType.Cylinder
marker.Size = Vector3.new(0.3, 9, 9)
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.Material = Enum.Material.Neon
marker.Color = Color3.fromRGB(96, 220, 255)
marker.Transparency = 0.45
marker.Parent = workspace

local beam = Instance.new("Part")
beam.Name = "TutorialBeam"
beam.Size = Vector3.new(0.6, 26, 0.6)
beam.Anchored = true
beam.CanCollide = false
beam.CanQuery = false
beam.Material = Enum.Material.Neon
beam.Color = Color3.fromRGB(96, 220, 255)
beam.Transparency = 0.7
beam.Parent = workspace

-- Glyphs per input family, not a combined string: "WASD / left stick" tells a gamepad player to use a
-- keyboard and vice versa. The card shows only the control the player can actually press.
local HINTS = {
	kbm = { move = "W A S D", shoot = "Hold LMB on the target", reload = "R", dodge = "Left Control", ability = "Q" },
	pad = { move = "Left thumbstick", shoot = "Hold RT on the target", reload = "X", dodge = "B", ability = "Right bumper" },
	touch = { move = "Drag the left thumb pad", shoot = "Tap FIRE on the target", reload = "Tap RELOAD", dodge = "Tap ROLL", ability = "Tap AIR" },
}

local function currentDevice(): string
	-- A server-set override lets the glyph path be verified in Studio without hardware.
	local forced = workspace:GetAttribute("GF_InputDevice")
	if type(forced) == "string" and HINTS[forced] then
		return forced
	end
	local kind = game:GetService("UserInputService"):GetLastInputType()
	if kind == Enum.UserInputType.Touch then
		return "touch"
	elseif kind == Enum.UserInputType.Gamepad1 or kind == Enum.UserInputType.Gamepad2 or kind == Enum.UserInputType.Gamepad3 or kind == Enum.UserInputType.Gamepad4 then
		return "pad"
	end
	return "kbm"
end

local starterFrame = nil
local function paint()
	local total = workspace:GetAttribute("Tutorial_Total")
	local step = workspace:GetAttribute("Tutorial_Step")
	local id = workspace:GetAttribute("Tutorial_Id")
	local complete = workspace:GetAttribute("Tutorial_Complete")
	if complete == true then
		-- S10-009: one free starter pick after completion. Shown once; the server validates and is the
		-- authority, so a stale client cannot double-claim.
		local claimed = tostring(workspace:GetAttribute("GF_StarterClaimState")):sub(1, 8) == "claimed:"
		if not claimed and not starterFrame then
			local remotes = game:GetService("ReplicatedStorage").GF:FindFirstChild("Remotes")
			local ev = remotes and remotes:FindFirstChild("ClaimStarter")
			starterFrame = Instance.new("Frame")
			starterFrame.Name = "StarterPick"
			starterFrame.Size = UDim2.fromOffset(360, 40)
			starterFrame.Position = UDim2.new(0.5, -180, 0.5, 60)
			starterFrame.BackgroundColor3 = Color3.fromRGB(14, 19, 25)
			-- Parented to the PlayerGui root, not `gui`: demoted above, `gui.Enabled = false` four seconds after
			-- completion would otherwise hide the pick before a player could choose.
			starterFrame.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromOffset(120, 40)
			label.Position = UDim2.fromOffset(8, 0)
			label.BackgroundTransparency = 1
			label.TextColor3 = Color3.fromRGB(230, 235, 240)
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Font = Enum.Font.Gotham
			label.TextSize = 13
			label.Text = "STARTER PICK"
			label.Parent = starterFrame
			for index, entry in ipairs({ { id = "AR01", label = "AR" }, { id = "SMG03", label = "SMG" }, { id = "LMG12", label = "LMG" } }) do
				local button = Instance.new("TextButton")
				button.Size = UDim2.fromOffset(72, 28)
				button.Position = UDim2.fromOffset(128 + (index - 1) * 76, 6)
				button.BackgroundColor3 = Color3.fromRGB(28, 38, 50)
				button.TextColor3 = Color3.fromRGB(235, 240, 245)
				button.Font = Enum.Font.GothamMedium
				button.TextSize = 12
				button.Text = entry.label
				button.Parent = starterFrame
				button.Activated:Connect(function()
					if ev then
						ev:FireServer(entry.id)
						starterFrame:Destroy()
						starterFrame = nil
					end
				end)
			end
		end
		body.Text = "First Spear complete"
		hint.Text = "Deploy when ready"
		gui.Enabled = true
		marker.Transparency = 1
		beam.Transparency = 1
		task.delay(4, function()
			gui.Enabled = false
		end)
		return
	end
	if type(total) ~= "number" or type(step) ~= "number" or step <= 0 then
		gui.Enabled = false
		marker.Transparency = 1
		beam.Transparency = 1
		return
	end
	gui.Enabled = true
	title.Text = string.format("OPERATION FIRST SPEAR  %d/%d", step, total)
	body.Text = tostring(workspace:GetAttribute("Tutorial_Text"))
	local table_ = HINTS[currentDevice()] or HINTS.kbm
	hint.Text = table_[id] or ""
	local point = workspace:GetAttribute("Tutorial_Marker")
	if typeof(point) == "Vector3" and id == "move" then
		marker.CFrame = CFrame.new(point + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		beam.CFrame = CFrame.new(point + Vector3.new(0, 13, 0))
		marker.Transparency = 0.45
		beam.Transparency = 0.7
	else
		marker.Transparency = 1
		beam.Transparency = 1
	end
end

RunService.Heartbeat:Connect(function()
	paint()
end)

