--!strict
-- Character rim: the player and crew are dark navy on a dark deck, so from behind they are almost
-- invisible (review V255). A Highlight is one instance, no lighting cost, and lifts the silhouette.
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local CYAN = Color3.fromRGB(120, 206, 255)

local function rim(model, outline, fill)
	if not model then
		return nil
	end
	local h = model:FindFirstChild("GFRim")
	if not h then
		h = Instance.new("Highlight")
		h.Name = "GFRim"
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = model
	end
	h.FillColor = Color3.fromRGB(24, 34, 48)
	h.FillTransparency = fill
	h.OutlineColor = outline
	h.OutlineTransparency = 0.35
	return h
end

local function onCharacter(character)
	-- A fully transparent fill left only the hairline outline; in the armoury the body still merged
	-- with the deck. 0.86 is a subtle dark-blue lift, not a glow-through-walls effect.
	rim(character, CYAN, 0.86)
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

-- crew get a dimmer outline so they read as background, not squadmates
task.spawn(function()
	local crewFolder = workspace:WaitForChild("Crew", 30)
	if not crewFolder then
		return
	end
	for _, rig in ipairs(crewFolder:GetChildren()) do
		if rig:IsA("Model") and rig:GetAttribute("GFCrew") then
			rim(rig, Color3.fromRGB(120, 150, 176), 0.94)
		end
	end
end)

workspace:SetAttribute("GF_CharRim", true)

