--!strict
-- S02-015 player nameplates: username + rank above every squadmate, fading with distance — never
-- visible through walls at long range, always readable in the lobby.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

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
	bb.Size = UDim2.fromOffset(160, 34)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 120
	bb.Parent = head
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(200, 220, 235)
	label.TextStrokeTransparency = 0.5
	label.Text = plr.DisplayName .. "  ·  " .. rankFor(plr)
	label.Parent = bb
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
			local label = bb:FindFirstChild("Label") :: TextLabel?
			if label then
				local fade = math.clamp(1 - (dist - 60) / 50, 0, 1)
				label.TextTransparency = 1 - fade * (1 - label.TextTransparency) * 1
				label.TextTransparency = math.clamp((dist - 60) / 50, 0, 0.95)
			end
		end
	end
end)
