--!strict
-- S02-015 player nameplates: username + rank above every squadmate, fading with distance — never
-- visible through walls at long range, always readable in the lobby.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Tokens = require(ReplicatedStorage:WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Tokens"))

local RANK_NAMES = { "Recruit", "Trooper", "Corporal", "Sergeant", "Lieutenant", "Captain", "Major", "Colonel", "General" }

local tracked: { [Player]: BillboardGui } = {}

local function rankFor(plr: Player): string
	local rank = plr:GetAttribute("GF_Rank") or 1
	local idx = math.clamp(math.floor((rank - 1) / 3) + 1, 1, #RANK_NAMES)
	return RANK_NAMES[idx]
end

local function attach(plr: Player, character: Model)
	if tracked[plr] then tracked[plr]:Destroy() end
	local head = character:WaitForChild("Head", 5) :: BasePart?
	if not head then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "GF_Nameplate"
	bb.Size = UDim2.fromOffset(170, 30)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.35, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 120
	bb.Parent = head

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Tokens.Color.panelInset
	plate.BackgroundTransparency = 0.45
	plate.BorderSizePixel = 0
	plate.Parent = bb

	local stroke = Instance.new("UIStroke")
	stroke.Name = "PlateStroke"
	stroke.Color = Tokens.Color.border
	stroke.Transparency = 0.55
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = plate

	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.Size = UDim2.new(0, 2, 1, -8)
	edge.Position = UDim2.fromOffset(0, 4)
	edge.BackgroundColor3 = Tokens.Color.techCyan
	edge.BackgroundTransparency = 0.28
	edge.BorderSizePixel = 0
	edge.Parent = plate

	local name = Instance.new("TextLabel")
	name.Name = "Label"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -12, 0, 14)
	name.Position = UDim2.fromOffset(6, 2)
	name.Font = Tokens.Type.fontBold
	name.TextSize = 12
	name.TextColor3 = Tokens.Color.ceramic
	name.TextTransparency = 0.08
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.Text = string.upper(plr.DisplayName)
	name.Parent = plate

	local rank = Instance.new("TextLabel")
	rank.Name = "Rank"
	rank.BackgroundTransparency = 1
	rank.Size = UDim2.new(1, -12, 0, 10)
	rank.Position = UDim2.fromOffset(6, 17)
	rank.Font = Tokens.Type.font
	rank.TextSize = 9
	rank.TextColor3 = Tokens.Color.steel
	rank.TextTransparency = 0.12
	rank.TextTruncate = Enum.TextTruncate.AtEnd
	rank.TextXAlignment = Enum.TextXAlignment.Center
	rank.Text = string.upper(rankFor(plr))
	rank.Parent = plate

	tracked[plr] = bb
end

local function watch(plr: Player)
	if plr == player then return end
	plr.CharacterAdded:Connect(function(char)
		attach(plr, char)
	end)
	if plr.Character then
		attach(plr, plr.Character)
	end
end

for _, plr in ipairs(Players:GetPlayers()) do
	watch(plr)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(plr)
	tracked[plr] = nil
end)

-- distance fade: billboards dim smoothly rather than popping at MaxDistance
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	for plr, bb in pairs(tracked) do
		local root = plr.Character and plr.Character:FindFirstChild("Head")
		if root and bb.Parent then
			local dist = (root.Position - cam.CFrame.Position).Magnitude
			local fade = math.clamp(1 - (dist - 45) / 65, 0, 1)
			local plate = bb:FindFirstChild("Plate") :: Frame?
			if plate then
				local name = plate:FindFirstChild("Label") :: TextLabel?
				local rank = plate:FindFirstChild("Rank") :: TextLabel?
				local edge = plate:FindFirstChild("Edge") :: Frame?
				local stroke = plate:FindFirstChild("PlateStroke") :: UIStroke?
				plate.BackgroundTransparency = 1 - fade * 0.55
				if name then
					name.TextTransparency = 1 - fade * 0.92
				end
				if rank then
					local rankText = string.upper(rankFor(plr))
					if rank.Text ~= rankText then
						rank.Text = rankText
					end
					rank.TextTransparency = 1 - fade * 0.88
				end
				if edge then
					edge.BackgroundTransparency = 1 - fade * 0.72
				end
				if stroke then
					stroke.Transparency = 1 - fade * 0.45
				end
			end
		end
	end
end)
