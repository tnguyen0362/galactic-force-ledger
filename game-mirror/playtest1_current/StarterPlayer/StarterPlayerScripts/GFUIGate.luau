--!strict
-- Station vs mission UI gating. The vitals HUD and the mission HUD belong to a live operation; on the
-- concourse the player should only see station UI. GF_EnvironmentPreset is authoritative (Environment
-- sets it on every preset swap), so gate on that rather than on mission internals.
local Players = game:GetService("Players")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local MISSION_ONLY = { "GF_HUD", "GFMissionHUD" }

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

