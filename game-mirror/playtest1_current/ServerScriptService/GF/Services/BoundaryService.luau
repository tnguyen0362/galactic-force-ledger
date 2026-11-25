--!strict
-- S03-022 natural boundaries: cliffs and terrain edges bound the play space. Players who push past
-- the boundary get a warning first, then reposition to their last safe point — never an artificial
-- death plane or invisible kill wall.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BoundaryService = {}

local WARN_SECONDS = 2.5
local CHECK_INTERVAL = 0.4
local lastSafe: { [Player]: Vector3 } = {}
local warnStarted: { [Player]: number } = {}

local BOUNDS_CENTER = Vector3.new(0, 0, 0)
local BOUNDS_RADIUS = 900 -- studs — the mission valley rim

local function insideBounds(pos: Vector3): boolean
	local flat = Vector3.new(pos.X, 0, pos.Z)
	local center = Vector3.new(BOUNDS_CENTER.X, 0, BOUNDS_CENTER.Z)
	return (flat - center).Magnitude <= BOUNDS_RADIUS
end

function BoundaryService.start()
	RunService.Heartbeat:Connect(function()
		-- throttle: only evaluate a few times per second
		if os.clock() % CHECK_INTERVAL > 0.03 then return end
		for _, plr in ipairs(Players:GetPlayers()) do
			local character = plr.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root then continue end
			local pos = root.Position
			if insideBounds(pos) then
				lastSafe[plr] = pos
				if warnStarted[plr] then
					warnStarted[plr] = nil
					plr:SetAttribute("GF_BoundaryWarning", false)
				end
			else
				if not warnStarted[plr] then
					warnStarted[plr] = os.clock()
					plr:SetAttribute("GF_BoundaryWarning", true)
				elseif os.clock() - warnStarted[plr] >= WARN_SECONDS then
					-- reposition to last safe point — the cliff wins, not a death plane
					local safe = lastSafe[plr]
					if safe then
						root.CFrame = CFrame.new(safe + Vector3.new(0, 2, 0))
					else
						root.CFrame = CFrame.new(BOUNDS_CENTER + Vector3.new(0, 10, 0))
					end
					warnStarted[plr] = nil
					plr:SetAttribute("GF_BoundaryWarning", false)
				end
			end
		end
	end)
end

Players.PlayerRemoving:Connect(function(plr)
	lastSafe[plr] = nil
	warnStarted[plr] = nil
end)

return BoundaryService
