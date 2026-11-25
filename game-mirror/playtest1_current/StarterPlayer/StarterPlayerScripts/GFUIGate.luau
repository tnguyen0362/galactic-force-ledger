--!strict
-- Station vs mission UI gating. The operation objective HUD belongs to a live operation; the base
-- combat HUD stays available on the concourse so ability loadout and dodge charges remain visible.
-- GF_EnvironmentPreset is authoritative (Environment sets it on every preset swap).
local Players = game:GetService("Players")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local MISSION_ONLY = { "GFMissionHUD" }

local function apply()
	local inMission = workspace:GetAttribute("GF_EnvironmentPreset") == "mission"
	for _, name in MISSION_ONLY do
		local gui = playerGui:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") and gui.Enabled ~= inMission then
			gui.Enabled = inMission
		end
	end
end

apply()
workspace:GetAttributeChangedSignal("GF_EnvironmentPreset"):Connect(apply)

-- GUIs can be created after this script runs; re-apply when one appears.
playerGui.ChildAdded:Connect(function()
	task.delay(0.2, apply)
end)

