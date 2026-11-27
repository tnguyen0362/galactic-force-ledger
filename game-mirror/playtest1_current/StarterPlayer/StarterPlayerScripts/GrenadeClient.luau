--!strict
-- LC-007 client half: G throws Frag, H throws EMP. Aim comes from the mouse ray so the arc lands
-- where the player is looking rather than at a fixed distance.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.GF.Shared.Remotes)
local Economy = require(ReplicatedStorage.GF.Shared.Configs.Economy)
local Audio = require(script.Parent:WaitForChild("GFAudio"))
local VFX = require(script.Parent:WaitForChild("VFX"))
local remotes = ReplicatedStorage:WaitForChild("GF"):WaitForChild("Remotes")
local player = Players.LocalPlayer
local throwRemote = remotes:WaitForChild("ThrowGrenade") :: RemoteEvent
local lastThrow = 0

-- kind-keyed presentation: the arc, the marker, the bomb light and the detonation all speak
-- the same color language, so a glance at the preview says which grenade is in hand.
local KIND_STYLE = {
	Frag = { color = Color3.fromRGB(255, 200, 120), fuse = 2.5 },
	EMP = { color = Color3.fromRGB(120, 208, 255), fuse = 1.9 },
}
local function styleOf(kind: string)
	return KIND_STYLE[kind] or KIND_STYLE.Frag
end
local function blastRadius(kind: string): number
	for _, g in ipairs(Economy.Grenades or {}) do
		if g.id == kind then
			return tonumber(g.radius) or 12
		end
	end
	return 12
end

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
	-- release foley: a low fabric-and-lob thwip. quiet on purpose — the explosion is the voice
	-- of this weapon, the throw is just its breath in. with no charges the server will reject
	-- the throw, so the hand-off sound would be a lie — answer with the dry click instead.
	if (tonumber(player:GetAttribute("GrenadeCharges")) or 0) > 0 then
		Audio.play("footstep", nil, 1.2, 0.62)
	else
		Audio.play("reload_start", nil, 0.5, 1.5)
	end
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
	if charging[kind] then
		local rem = game:GetService("ReplicatedStorage"):FindFirstChild("GF")
		rem = rem and rem:FindFirstChild("Remotes")
		local ch = rem and rem:FindFirstChild("GrenadeChargeNotify")
		if ch then ch:FireServer(false) end
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
	-- landing marker: a flat ring exactly where the blast will center — no guessing.
	-- sized to the TRUE blast radius (the fixed 7-stud ring used to promise a surgical strike
	-- and deliver a 30-stud fireball); transparency stays high so it reads as a zone, not a wall.
	if not c.marker then
		local m = Instance.new("Part")
		m.Shape = Enum.PartType.Cylinder
		m.Material = Enum.Material.Neon
		m.Anchored = true
		m.CanCollide = false
		m.CanQuery = false
		m.CastShadow = false
		m.Parent = workspace
		c.marker = m
	end
	local diameter = blastRadius(kind) * 2
	c.marker.Size = Vector3.new(0.15, diameter, diameter)
	c.marker.Color = styleOf(kind).color
	-- slow pulse: the marker is a live commitment, not painted terrain
	c.marker.Transparency = 0.68 + 0.1 * math.sin(os.clock() * 6)
	c.marker.CFrame = CFrame.new(target + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
end
local function startCharge(kind: string)
	clearPreview(kind)
	local style = styleOf(kind)
	local dots = {}
	for i = 1, 8 do
		local dot = Instance.new("Part")
		dot.Shape = Enum.PartType.Ball
		dot.Material = Enum.Material.Neon
		dot.Color = style.color
		-- tail-end emphasis: the last dot is the landing commitment, the flight dots stay quiet
		local last = i == 8
		dot.Size = last and Vector3.new(0.46, 0.46, 0.46) or Vector3.new(0.3, 0.3, 0.3)
		dot.Transparency = last and 0.12 or 0.34
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CastShadow = false
		dot.Parent = workspace
		dots[i] = dot
	end
	charging[kind] = { startAt = os.clock(), dots = dots }
	-- pin-pull tell: the charge starting is a decision moment, it deserves a click.
	-- silent when the pouch is empty — foley must never promise inventory the server will deny.
	if (tonumber(player:GetAttribute("GrenadeCharges")) or 0) > 0 then
		Audio.play("reload_start", nil, 0.6, 1.35)
	end
	-- uplink charge state for the server animator's precision-hold pose (spec sec.57)
	local rem = game:GetService("ReplicatedStorage"):FindFirstChild("GF")
	rem = rem and rem:FindFirstChild("Remotes")
	local ch = rem and rem:FindFirstChild("GrenadeChargeNotify")
	if ch then ch:FireServer(true) end
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
			-- leak guard: dying or losing the character mid-charge used to strand the arc dots
			-- in the world forever — release only clears them when the key comes up, and dead
			-- fingers don't come up. the preview dies with the hand that holds it.
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not character or not humanoid or humanoid.Health <= 0 then
				clearPreview(kind)
			else
				updatePreview(kind)
			end
		end
	end
end)

local detonated = remotes:WaitForChild("GrenadeDetonated") :: RemoteEvent
detonated.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	local pos = payload.position
	if typeof(pos) ~= "Vector3" then return end
	-- the old implementation wrote invisible marker parts into a folder nothing read — the
	-- explosion was silent and the camera never moved. all of it lives in VFX.explosion now:
	-- pooled burst, positional voice, distance-shaped camera impulse through CameraCtl.
	local kind = type(payload.kind) == "string" and payload.kind or "Frag"
	VFX.explosion(pos, kind)
end)

-- ---------------------------------------------------------------------------
-- fuse readability: the server bomb is a small dark ball sitting still for up to 2.5s —
-- practically invisible in a firefight, yet it decides who dies. every bomb gets a kind-colored
-- light and an accelerating electronic chirp as the fuse burns down, so a grenade at your feet
-- is a thing you can READ and act on. the light rides inside the bomb itself, so cleanup is
-- automatic when the server destroys it at detonation; the chirp loop self-terminates with it.
-- ---------------------------------------------------------------------------
do
	local RunService = game:GetService("RunService")
	local active: { [BasePart]: boolean } = {}

	-- fuse durations mirror the server throw model (GrenadeRuntime FUSE) — reading them here is
	-- presentation timing only; the server owns the actual detonation moment either way.
	local function fuseFor(model: string): number
		local kind = model == "Grenade_EMP" and "EMP" or "Frag"
		return styleOf(kind).fuse
	end

	local function attach(bomb: BasePart)
		if active[bomb] then return end
		active[bomb] = true
		local isEMP = bomb.Name == "Grenade_EMP"
		local color = isEMP and Color3.fromRGB(120, 208, 255) or Color3.fromRGB(255, 196, 110)
		local light = Instance.new("PointLight")
		light.Name = "FuseLight"
		light.Color = color
		light.Range = 7
		light.Brightness = 0
		light.Parent = bomb
		local bornAt = os.clock()
		local fuse = fuseFor(bomb.Name)
		local nextBeep = 0
		-- blink+beep scheduler: one heartbeat connection per live bomb (never more than a few
		-- in flight — throws are cooldown-gated). interval compresses as the fuse burns:
		-- slow pulse on landing, urgent chatter in the last half-second.
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if not bomb.Parent then
				conn:Disconnect()
				active[bomb] = nil
				return
			end
			local elapsed = os.clock() - bornAt
			local frac = math.clamp(elapsed / fuse, 0, 1)
			-- replication latency means the bomb appears partway into flight; the schedule is
			-- approximate by a throw's width, but the acceleration shape is what the player reads
			local interval = 0.5 - 0.38 * frac -- 0.5s early, ~0.12s at the end
			if os.clock() >= nextBeep then
				nextBeep = os.clock() + interval
				light.Brightness = 2.6
				-- quiet electronic chirp, pitched up as urgency rises. positioned at the bomb so
				-- directionality is free: you can HEAR where it is without seeing it.
				Audio.play("hit_shield", bomb.Position, 0.4, 1.3 + frac * 0.7)
				task.delay(0.07, function()
					if light.Parent then light.Brightness = 0 end
				end)
			end
		end)
	end

	local function scanDescendant(inst: Instance)
		if inst:IsA("BasePart") and (inst.Name == "Grenade_Frag" or inst.Name == "Grenade_EMP") then
			attach(inst)
		end
	end
	workspace.DescendantAdded:Connect(scanDescendant)
	for _, d in workspace:GetDescendants() do
		scanDescendant(d)
	end
end
