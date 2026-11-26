--!strict
-- ShellService: deterministic projectile flight for heavy vehicle/boss weapons (spec section 35:
-- readable projectile travel, damage at legitimate impact). Unanchored physics shells drop with
-- gravity and detonate on incidental contact — unacceptable for aimed heavy weapons. These shells
-- are anchored and step-integrated at fixed speed with raycast impact detection along each step:
-- flight is true, impact is exact, travel time is readable.

local Workspace = game:GetService("Workspace")

local ShellService = {}

local ENERGY = Color3.fromRGB(169, 99, 233)

local function fxFolder()
	local f = Workspace:FindFirstChild("GF_FX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GF_FX"
		f.Parent = Workspace
	end
	return f
end

-- fire a shell from origin toward aimPoint at fixed speed.
-- options: size, speed, color, ignoreList, maxTime
-- onDetonate(position, hitInstance) called exactly once at impact or fuse expiry.
function ShellService.fireShell(origin: Vector3, aimPoint: Vector3, options: any, onDetonate: (Vector3, Instance?) -> ())
	local size = options.size or 2
	local speed = options.speed or 130
	local shell = Instance.new("Part")
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(size, size, size)
	shell.Color = options.color or ENERGY
	shell.Material = Enum.Material.Neon
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.Anchored = true
	shell.CFrame = CFrame.new(origin)
	shell.Parent = fxFolder()

	local dir = (aimPoint - origin)
	local dist = dir.Magnitude
	if dist < 1 then
		shell:Destroy()
		onDetonate(aimPoint, nil)
		return
	end
	local unit = dir.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = options.ignoreList or {}

	local traveled = 0
	local pos = origin
	local detonated = false
	local maxTime = options.maxTime or (dist / speed + 1.5)
	local clock = 0
	local stepDt = 1 / 30

	local function finish(at: Vector3, hit: Instance?)
		if detonated then return end
		detonated = true
		if shell.Parent then shell:Destroy() end
		onDetonate(at, hit)
	end

	task.spawn(function()
		while not detonated do
			task.wait(stepDt)
			clock += stepDt
			local stepLen = speed * stepDt
			-- raycast along this step: terrain, structures, characters all legitimate impacts
			local hit = Workspace:Raycast(pos, unit * stepLen, params)
			if hit then
				finish(hit.Position, hit.Instance)
				return
			end
			pos = pos + unit * stepLen
			traveled += stepLen
			if shell.Parent then
				shell.CFrame = CFrame.new(pos)
			else
				return
			end
			if traveled >= dist or clock >= maxTime then
				-- reached the aim point or fused out: detonate at current position
				finish(pos, nil)
				return
			end
		end
	end)
end

return ShellService
