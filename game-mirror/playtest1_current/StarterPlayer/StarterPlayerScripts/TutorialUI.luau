--!strict
-- First Spear prompt panel + world marker for the current objective.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tokens = require(ReplicatedStorage.GF.Shared.UI.Tokens)
local Components = require(ReplicatedStorage.GF.Shared.UI.Components)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local COLOR = Tokens.Color
local TYPE = Tokens.Type
local MONO_FONT = (TYPE :: any).fontMono or TYPE.font
local MONO_BOLD = (TYPE :: any).fontMonoBold or TYPE.fontBold

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

local function cornerBracket(parent: Instance, corner: string, color: Color3, length: number, inset: number, zindex: number?)
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
	local notch = makeFrame(parent, corner .. "_N", UDim2.new(0, math.max(10, length * 0.34), 0, 2), UDim2.new(ax, left and x + 11 or x - 11, ay, topSide and y + 11 or y - 11), color, 0.1, zindex or 8)
	notch.AnchorPoint = Vector2.new(0.5, 0.5)
	notch.Rotation = (left == topSide) and 45 or -45
end

local gui = Instance.new("ScreenGui")
gui.Name = "Tutorial"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = makeFrame(gui, "ObjectivePanel", UDim2.new(0.78, 0, 0, 88), UDim2.new(0.5, 0, 0, 96), COLOR.panelInset, 0.08, 2)
panel.AnchorPoint = Vector2.new(0.5, 0)
local panelConstraint = Instance.new("UISizeConstraint")
panelConstraint.MinSize = Vector2.new(320, 88)
panelConstraint.MaxSize = Vector2.new(480, 96)
panelConstraint.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = COLOR.border
stroke.Transparency = 0.18
stroke.Thickness = 1
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = panel
cornerBracket(panel, "TL", COLOR.techCyan, 34, 7, 6)
cornerBracket(panel, "TR", COLOR.techCyan, 34, 7, 6)
cornerBracket(panel, "BL", COLOR.techCyan, 34, 7, 6)
cornerBracket(panel, "BR", COLOR.techCyan, 34, 7, 6)
makeFrame(panel, "CommandSpine", UDim2.new(0, 4, 1, 0), UDim2.new(0, 0, 0, 0), COLOR.techCyan, 0.08, 5)
makeFrame(panel, "CommandAmber", UDim2.new(0, 4, 0, 24), UDim2.new(0, 0, 0, 34), COLOR.warning, 0.08, 6)

local title = makeLabel(panel, "Title", "OPERATION FIRST SPEAR", UDim2.new(1, -122, 0, 18), UDim2.new(0, 18, 0, 9), COLOR.textAccent, TYPE.sizeSmall, true)
title.Font = MONO_BOLD
local modeTag = makeLabel(panel, "ModeTag", "ACTIVE", UDim2.new(0, 82, 0, 18), UDim2.new(1, -96, 0, 9), COLOR.warning, TYPE.sizeSmall, true)
modeTag.Font = MONO_BOLD
modeTag.TextXAlignment = Enum.TextXAlignment.Right

local body = makeLabel(panel, "Body", "", UDim2.new(1, -36, 0, 20), UDim2.new(0, 18, 0, 31), COLOR.textPrimary, TYPE.sizeBody, true)
local hint = makeLabel(panel, "Hint", "", UDim2.new(1, -36, 0, 16), UDim2.new(0, 18, 0, 54), COLOR.textSecondary, TYPE.sizeSmall, false)
hint.Font = MONO_FONT

local progressBack = makeFrame(panel, "ProgressBack", UDim2.new(1, -36, 0, 3), UDim2.new(0, 18, 0, 76), COLOR.graphite, 0.05, 5)
local progressFill = makeFrame(progressBack, "ProgressFill", UDim2.new(0, 0, 1, 0), UDim2.new(0, 0, 0, 0), COLOR.techCyan, 0.04, 6)

local marker = Instance.new("Part")
marker.Name = "TutorialMarker"
marker.Shape = Enum.PartType.Cylinder
marker.Size = Vector3.new(0.3, 9, 9)
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.Material = Enum.Material.Neon
marker.Color = COLOR.techCyan
marker.Transparency = 1
marker.Parent = workspace

local beam = Instance.new("Part")
beam.Name = "TutorialBeam"
beam.Size = Vector3.new(0.6, 26, 0.6)
beam.Anchored = true
beam.CanCollide = false
beam.CanQuery = false
beam.Material = Enum.Material.Neon
beam.Color = COLOR.techCyan
beam.Transparency = 1
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

-- The starter pick deliberately lives outside `gui`: the objective panel is demoted a few seconds
-- after completion, while the pick must remain available until the player chooses.
local starterGui = Instance.new("ScreenGui")
starterGui.Name = "StarterPickPrompt"
starterGui.ResetOnSpawn = false
starterGui.Enabled = false
starterGui.DisplayOrder = 18
starterGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
starterGui.Parent = playerGui

local starterFrame = nil
local completionHideScheduled = false
local completionDismissed = false

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
			local remotes = ReplicatedStorage.GF:FindFirstChild("Remotes")
			local ev = remotes and remotes:FindFirstChild("ClaimStarter")
			starterFrame = makeFrame(starterGui, "StarterPick", UDim2.new(0.9, 0, 0, 64), UDim2.new(0.5, 0, 0.5, 60), COLOR.panelInset, 0.06, 3)
			starterFrame.AnchorPoint = Vector2.new(0.5, 0)
			local starterConstraint = Instance.new("UISizeConstraint")
			starterConstraint.MinSize = Vector2.new(300, 64)
			starterConstraint.MaxSize = Vector2.new(392, 64)
			starterConstraint.Parent = starterFrame
			local starterStroke = Instance.new("UIStroke")
			starterStroke.Color = COLOR.borderFocus
			starterStroke.Transparency = 0.3
			starterStroke.Thickness = 1
			starterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			starterStroke.Parent = starterFrame
			cornerBracket(starterFrame, "TL", COLOR.techCyan, 28, 6, 7)
			cornerBracket(starterFrame, "TR", COLOR.techCyan, 28, 6, 7)
			cornerBracket(starterFrame, "BL", COLOR.techCyan, 28, 6, 7)
			cornerBracket(starterFrame, "BR", COLOR.techCyan, 28, 6, 7)
			makeFrame(starterFrame, "PickSpine", UDim2.new(0, 3, 1, -12), UDim2.new(0, 6, 0, 6), COLOR.warning, 0.08, 6)

			local label = makeLabel(starterFrame, "PickLabel", "STARTER PICK", UDim2.new(0.27, -8, 0, 52), UDim2.new(0.04, 0, 0, 6), COLOR.textPrimary, TYPE.sizeSmall, true)
			label.Font = MONO_BOLD
			label.TextXAlignment = Enum.TextXAlignment.Left
			for index, entry in ipairs({ { id = "AR01", label = "AR" }, { id = "SMG03", label = "SMG" }, { id = "LMG12", label = "LMG" } }) do
				local button = Components.button(starterFrame, entry.label, "ghost")
				button.Size = UDim2.new(0.2, 0, 0, 52)
				button.Position = UDim2.new(0.33 + (index - 1) * 0.22, 0, 0, 6)
				button.Activated:Connect(function()
					if ev and ev:IsA("RemoteEvent") then
						ev:FireServer(entry.id)
						starterFrame:Destroy()
						starterFrame = nil
						starterGui.Enabled = false
					end
				end)
			end
			starterGui.Enabled = true
		end

		progressFill.Size = UDim2.new(1, 0, 1, 0)
		progressFill.BackgroundColor3 = COLOR.techCyan
		modeTag.Text = "COMPLETE"
		modeTag.TextColor3 = COLOR.textAccent
		body.Text = "First Spear complete"
		hint.Text = "Deploy when ready"
		marker.Transparency = 1
		beam.Transparency = 1

		if completionDismissed then
			gui.Enabled = false
			return
		end
		gui.Enabled = true
		if not completionHideScheduled then
			completionHideScheduled = true
			task.delay(4, function()
				completionHideScheduled = false
				if workspace:GetAttribute("Tutorial_Complete") == true then
					completionDismissed = true
					gui.Enabled = false
				end
			end)
		end
		return
	end

	completionDismissed = false
	if type(total) ~= "number" or type(step) ~= "number" or step <= 0 then
		gui.Enabled = false
		marker.Transparency = 1
		beam.Transparency = 1
		return
	end
	gui.Enabled = true
	title.Text = string.format("OPERATION FIRST SPEAR  %d/%d", step, total)
	modeTag.Text = "ACTIVE"
	modeTag.TextColor3 = COLOR.warning
	body.Text = tostring(workspace:GetAttribute("Tutorial_Text"))
	local table_ = HINTS[currentDevice()] or HINTS.kbm
	hint.Text = table_[id] or ""
	progressFill.BackgroundColor3 = COLOR.techCyan
	progressFill.Size = UDim2.new(math.clamp(step / math.max(total, 1), 0, 1), 0, 1, 0)
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
