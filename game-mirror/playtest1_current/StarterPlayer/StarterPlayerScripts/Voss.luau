--!nonstrict
-- Voss portrait and subtitles. DialogueEvent had no receiver, so no dispatch line was ever shown.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local remotes = game:GetService("ReplicatedStorage").GF.Remotes

local gui = Instance.new("ScreenGui")
gui.Name = "GF_Voss"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(310, 64)
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 14, 1, -96)
panel.BackgroundColor3 = Color3.fromRGB(10, 16, 24)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = panel

-- Portrait: a helmet silhouette built from shapes, no art asset required.
local portrait = Instance.new("Frame")
portrait.Size = UDim2.fromOffset(52, 52)
portrait.Position = UDim2.fromOffset(6, 6)
portrait.BackgroundColor3 = Color3.fromRGB(26, 34, 44)
portrait.BorderSizePixel = 0
portrait.Parent = panel
local portraitCorner = Instance.new("UICorner")
portraitCorner.CornerRadius = UDim.new(0, 3)
portraitCorner.Parent = portrait
local visor = Instance.new("Frame")
visor.Size = UDim2.fromOffset(38, 12)
visor.Position = UDim2.fromOffset(7, 20)
visor.BackgroundColor3 = Color3.fromRGB(96, 200, 255)
visor.BorderSizePixel = 0
visor.Parent = portrait
local visorCorner = Instance.new("UICorner")
visorCorner.CornerRadius = UDim.new(0, 6)
visorCorner.Parent = visor

local name = Instance.new("TextLabel")
name.Text = "VOSS"
name.Size = UDim2.fromOffset(240, 16)
name.Position = UDim2.fromOffset(66, 8)
name.BackgroundTransparency = 1
name.Font = Enum.Font.GothamBold
name.TextSize = 13
name.TextColor3 = Color3.fromRGB(255, 200, 120)
name.TextXAlignment = Enum.TextXAlignment.Left
name.Parent = panel

local line = Instance.new("TextLabel")
line.Text = ""
line.Size = UDim2.fromOffset(236, 36)
line.Position = UDim2.fromOffset(66, 24)
line.BackgroundTransparency = 1
line.Font = Enum.Font.GothamMedium
line.TextSize = 13
line.TextWrapped = true
line.TextYAlignment = Enum.TextYAlignment.Top
line.TextColor3 = Color3.fromRGB(225, 235, 245)
line.TextXAlignment = Enum.TextXAlignment.Left
line.Parent = panel

local queue = {}
local showing = false

local function present(entry)
	showing = true
	name.Text = entry.speaker or "VOSS"
	line.Text = entry.text
	line.TextTransparency = 0
	panel.Visible = true
	gui:SetAttribute("GF_VossText", line.Text)
	gui:SetAttribute("GF_VossSpeaker", name.Text)
	gui:SetAttribute("GF_VossVisible", true)
	task.delay(6, function()
		panel.Visible = false
		showing = false
		gui:SetAttribute("GF_VossVisible", false)
		local nextEntry = table.remove(queue, 1)
		if nextEntry then
			present(nextEntry)
		end
	end)
end

remotes.DialogueEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or type(payload.text) ~= "string" then
		return
	end
	if showing then
		table.insert(queue, { speaker = payload.speaker, text = payload.text })
		return
	end
	present({ speaker = payload.speaker, text = payload.text })
end)

