--!strict
-- LC-007 client half: G throws Frag, H throws EMP. Aim comes from the mouse ray so the arc lands
-- where the player is looking rather than at a fixed distance.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.GF.Shared.Remotes)
local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local player = Players.LocalPlayer
local throwRemote = remotes:WaitForChild("ThrowGrenade") :: RemoteEvent
local lastThrow = 0

local function aimPoint(): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local unitRay = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local hit = workspace:Raycast(unitRay.Origin, unitRay.Direction * 260, params)
	if hit then return hit.Position end
	return unitRay.Origin + unitRay.Direction * 120
end

-- ---------------------------------------------------------------------------
-- SHARED THROW MODEL — client preview and server runtime must be the same math.
-- The server (GrenadeRuntime) lands the bomb exactly at the clamped aim point along a two-phase
-- arc: rise to an apex at midpoint+height then descend to target. Height = max(3, dist*0.18).
-- Aim distance clamps at 70 studs both sides; the server used to REJECT beyond it, leaving the
-- player silently grenade-less — now both sides clamp so the preview never promises a rejection.
local THROW_CAP = 70
local function clampedAim(): Vector3?
	local point = aimPoint()
	if not point then return nil end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return point end
	local delta = point - root.Position
	if delta.Magnitude > THROW_CAP then
		return root.Position + delta.Unit * THROW_CAP
	end
	return point
end
-- quadratic-bezier through start/apex/end — matches the server's rise-then-fall tween pair closely
-- enough that every preview dot sits within a fraction of a stud of the real flight path.
local function arcPosition(startPos: Vector3, target: Vector3, alpha: number): Vector3
	local apex = (startPos + target) * 0.5 + Vector3.new(0, math.max(3, (target - startPos).Magnitude * 0.18), 0)
	local inv = 1 - alpha
	return inv * inv * startPos + 2 * inv * alpha * apex + alpha * alpha * target
end

local function send(kind: string)
	local now = os.clock()
	if now - lastThrow < 0.8 then return end
	lastThrow = now
	local point = clampedAim()
	throwRemote:FireServer({ kind = kind, aim = point })
end

-- S03-005/S04-054: tap = quick throw at the aim point; hold = trajectory preview arc with the throw
-- distance charging toward the 70-stud cap; release throws. No cook/variable fuse anywhere.
local charging: { [string]: { startAt: number, dots: { Part } } } = {}
local function clearPreview(kind: string)
	local c = charging[kind]
	if c then
		for _, d in ipairs(c.dots) do
			if d.Parent then d:Destroy() end
		end
		if c.marker and c.marker.Parent then c.marker:Destroy() end
	end
	charging[kind] = nil
end
local function updatePreview(kind: string)
	local c = charging[kind]
	if not c then return end
	local target = clampedAim()
	if not target then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	-- the bomb spawns 2 studs ahead of the chest — preview from the same origin the server uses
	local startPos = root.Position + root.CFrame.LookVector * 2
	for i, d in ipairs(c.dots) do
		local alpha = i / #c.dots
		d.CFrame = CFrame.new(arcPosition(startPos, target, alpha))
	end
	-- landing marker: a flat ring exactly where the blast will center — no guessing
	if not c.marker then
		local m = Instance.new("Part")
		m.Shape = Enum.PartType.Cylinder
		m.Size = Vector3.new(0.15, 7, 7)
		m.Orientation = Vector3.new(0, 0, 90)
		m.Material = Enum.Material.Neon
		m.Color = kind == "EMP" and Color3.fromRGB(120, 208, 255) or Color3.fromRGB(255, 200, 120)
		m.Transparency = 0.55
		m.Anchored = true
		m.CanCollide = false
		m.CanQuery = false
		m.Parent = workspace
		c.marker = m
	end
	c.marker.CFrame = CFrame.new(target + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
end
local function startCharge(kind: string)
	clearPreview(kind)
	local dots = {}
	for i = 1, 8 do
		local dot = Instance.new("Part")
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.new(0.3, 0.3, 0.3)
		dot.Material = Enum.Material.Neon
		dot.Color = Color3.fromRGB(255, 200, 120)
		dot.Transparency = 0.3
		dot.Anchored = true
		dot.CanCollide = false
		dot.Parent = workspace
		dots[i] = dot
	end
	charging[kind] = { startAt = os.clock(), dots = dots }
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.G then
		startCharge("Frag")
	elseif input.KeyCode == Enum.KeyCode.H then
		startCharge("EMP")
	end
end)
UserInputService.InputEnded:Connect(function(input)
	local kind = input.KeyCode == Enum.KeyCode.G and "Frag" or (input.KeyCode == Enum.KeyCode.H and "EMP" or nil)
	if not kind then return end
	local c = charging[kind]
	clearPreview(kind)
	if c then
		send(kind)
	end
end)
-- preview refresh loop while charging
task.spawn(function()
	while true do
		task.wait(0.05)
		for kind in pairs(charging) do
			updatePreview(kind)
		end
	end
end)

local detonated = remotes:WaitForChild("GrenadeDetonated") :: RemoteEvent
detonated.OnClientEvent:Connect(function(payload)
	local camera = workspace.CurrentCamera
	if not camera or typeof(payload) ~= "table" then return end
	local pos = payload.position
	if typeof(pos) ~= "Vector3" then return end
	local dist = (camera.CFrame.Position - pos).Magnitude
	local strength = math.clamp(1 - dist / 120, 0, 1)
	if strength <= 0 then return end
	-- EMP reads as a hard cold snap, Frag as a hot thump
	local shakeColor = (payload.kind == "EMP") and Color3.fromRGB(120, 208, 255) or Color3.fromRGB(255, 176, 96)
	local folder = workspace:FindFirstChild("GrenadeShake")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "GrenadeShake"
		folder.Parent = workspace
	end
	local marker = Instance.new("Part")
	marker.Name = payload.kind
	marker.Size = Vector3.new(0.2, 0.2, 0.2)
	marker.Transparency = 1
	marker.Anchored = true
	marker.CanCollide = false
	marker.CFrame = CFrame.new(pos)
	marker.Color = shakeColor
	marker:SetAttribute("Strength", strength)
	marker.Parent = folder :: Folder
	task.delay(1, function() marker:Destroy() end)
end)
