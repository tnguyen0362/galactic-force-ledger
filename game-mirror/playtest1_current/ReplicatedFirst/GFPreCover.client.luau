--!strict
-- Earliest-possible cover for the mission place. The real loading screen (StarterPlayerScripts/
-- LoadingScreen) can only appear once the character scripts load, which left a visible gap where the
-- raw world (hold altitude, sky, half-streamed terrain) showed between Roblox's own loading screen
-- and ours. This runs from ReplicatedFirst, drops a solid cover over the screen immediately, and
-- releases it as soon as the GF loading screen is actually visible underneath (or after a failsafe).
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local player = Players.LocalPlayer
if not player then
	return
end
local playerGui = player:WaitForChild("PlayerGui")

-- parent our cover FIRST, then drop Roblox's default screen: removing it before the cover exists
-- opens a frame-or-more gap where the raw world shows.
local gui = Instance.new("ScreenGui")
gui.Name = "GFPreCover"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.Parent = playerGui

local cover = Instance.new("Frame")
cover.Name = "Cover"
cover.Size = UDim2.fromScale(1, 1)
cover.BackgroundColor3 = Color3.fromRGB(8, 11, 16)
cover.BorderSizePixel = 0
cover.Parent = gui

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local started = os.clock()
local FAILSAFE = 45
while gui.Parent do
	local screen = playerGui:FindFirstChild("GFLoadingScreen")
	local root = screen and screen:FindFirstChild("Root")
	if root and root:IsA("GuiObject") and root.Visible then
		-- our screen is up; hold the cover one more frame so the swap can't flash
		task.wait()
		break
	end
	-- the screen script ran but chose not to show (lobby): nothing to hand off to
	if screen and root and not root.Visible and os.clock() - started > 4 then
		break
	end
	if os.clock() - started > FAILSAFE then
		break
	end
	task.wait()
end
gui:Destroy()
