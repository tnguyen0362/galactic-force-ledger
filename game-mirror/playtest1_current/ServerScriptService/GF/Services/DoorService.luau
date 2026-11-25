--!strict
-- S07-012 auto sliding doors: proximity-triggered panels with valid collisions in both states —
-- closed doors block movement and sightlines, open doors never leave phantom collision.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local DoorService = {}
local doors: { { frame: Model, panel: BasePart, closedCFrame: CFrame, openCFrame: CFrame, openAmount: number, target: number } } = {}

function DoorService.registerDoor(position: Vector3, width: number?, height: number?): Model
	local w = width or 8
	local h = height or 7
	local frame = Instance.new("Model")
	frame.Name = "AutoDoor"
	local panel = Instance.new("Part")
	panel.Name = "Panel"
	panel.Size = Vector3.new(w, h, 0.8)
	panel.Color = Color3.fromRGB(70, 80, 95)
	panel.Material = Enum.Material.Metal
	panel.Anchored = true
	panel.CanCollide = true
	panel.CFrame = CFrame.new(position)
	panel.Parent = frame
	-- frame jambs
	for _, side in ipairs({ -1, 1 }) do
		local jamb = Instance.new("Part")
		jamb.Size = Vector3.new(0.8, h, 1.2)
		jamb.Color = Color3.fromRGB(40, 46, 55)
		jamb.Material = Enum.Material.Metal
		jamb.Anchored = true
		jamb.CanCollide = true
		jamb.CFrame = CFrame.new(position) * CFrame.new(side * (w / 2 + 0.4), 0, 0)
		jamb.Parent = frame
	end
	frame.PrimaryPart = panel
	frame:SetAttribute("AutoDoor", true)
	frame.Parent = workspace
	local closedCFrame = panel.CFrame
	local openCFrame = closedCFrame * CFrame.new(0, h - 0.6, 0) -- slides up into the header
	doors[#doors + 1] = { frame = frame, panel = panel, closedCFrame = closedCFrame, openCFrame = openCFrame, openAmount = 0, target = 0 }
	return frame
end

local TRIGGER_RANGE = 12

function DoorService.start()
	RunService.Heartbeat:Connect(function(dt)
		if #doors == 0 then return end
		for _, door in ipairs(doors) do
			-- any live player within range opens the door
			local near = false
			for _, plr in ipairs(Players:GetPlayers()) do
				local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - door.panel.Position).Magnitude < TRIGGER_RANGE then
					near = true
					break
				end
			end
			door.target = near and 1 or 0
			if math.abs(door.openAmount - door.target) > 0.001 then
				door.openAmount += math.sign(door.target - door.openAmount) * math.min(dt * 2.2, math.abs(door.target - door.openAmount))
				door.panel.CFrame = door.closedCFrame:Lerp(door.openCFrame, door.openAmount)
				-- collision stays valid in every intermediate state because the panel itself is the collider
			end
		end
	end)
end

function DoorService.count(): number
	return #doors
end

return DoorService
