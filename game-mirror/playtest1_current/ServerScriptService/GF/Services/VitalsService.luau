--!strict
-- Server-authoritative shield/health. Shield absorbs first; both regen after their own delays.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.GF.Shared.Constants)
local State = require(ServerScriptService.GF.Services.State)

local VitalsService = {}

local function now(): number
	return os.clock()
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

function VitalsService.publish(player: Player)
	local s = State.get(player)
	if not s then
		return
	end
	local remotes = ReplicatedStorage.GF.Remotes
	local humanoid = humanoidOf(player)
	if workspace:GetAttribute("GF_DebugVitals") == true then
		print(string.format("[GF] vitals publish shield=%s downed=%s humanoid=%s", tostring(s.shield), tostring(s.downed), tostring(humanoid ~= nil)))
	end
	remotes.VitalsUpdated:FireClient(player, {
		shield = s.shield,
		shieldMax = s.shieldMax,
		health = humanoid and humanoid.Health or 0,
		healthMax = humanoid and humanoid.MaxHealth or 0,
		downed = s.downed,
	})
end

local function restorePreDownedCollision(character: Model?)
	if not character then
		return
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			local previous = part:GetAttribute("GF_PreDownedCanCollide")
			if typeof(previous) == "boolean" then
				part.CanCollide = previous
				part:SetAttribute("GF_PreDownedCanCollide", nil)
			end
		end
	end
end

function VitalsService.reset(player: Player)
	local s = State.ensure(player)
	s.shield = s.shieldMax
	s.lastDamage = 0
	s.downed = false
	s.downedAt = nil
	ReplicatedStorage.GF.Remotes.DownedChanged:FireClient(player, false)
	-- persistent character attribute mirror (movement/camera refinement): the client movement
	-- state machine polls this; the remote alone is a one-shot event respawns can miss.
	if player.Character then
		player.Character:SetAttribute("Downed", false)
	end
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	restorePreDownedCollision(player.Character)
	VitalsService.publish(player)
end

-- Returns the damage actually applied to vitals.
function VitalsService.applyDamage(player: Player, amount: number, _source: string?, sourcePos: Vector3?): number
	if player:GetAttribute("GF_Aboard") == true then
		return 0
	end
	if workspace:GetAttribute("GF_InMission") == false then
		return 0
	end
	-- Deploy grace: measured shield 100 -> 74 -> 48 -> 22 -> 0 within seconds of arriving, because the
	-- squad is dropped inside engagement range and shot before they can move. A short immunity window
	-- after touchdown is the minimum fix; the spawn placement itself is the real problem.
	local graceUntil = tonumber(workspace:GetAttribute("GF_DeployGraceUntil"))
	if graceUntil and os.clock() < graceUntil then
		workspace:SetAttribute("GF_GraceAbsorbed", (workspace:GetAttribute("GF_GraceAbsorbed") or 0) + 1)
		return 0
	end
	local s = State.get(player)
	if not s or s.downed or amount <= 0 then
		return 0
	end
	-- Roll i-frames (movement/camera refinement): full invulnerability during the active roll
	-- window. MovementService sets State.invulnerableUntil server-side when the roll begins;
	-- the window is authoritative here, never client-claimed.
	if (s :: any).invulnerableUntil and os.clock() < (s :: any).invulnerableUntil then
		return 0
	end
	-- Damage attribution behind a switch: it was the only way to name the landing-zone attacker, but it must
	-- not spam a live server's log.
	if workspace:GetAttribute("GF_DebugDamage") == true then
		print(string.format("[GF] damage player=%s amount=%.1f source=%s", player.Name, amount, tostring(_source)))
	end
	-- The console projects a hardlight screen over whoever is jacked in. Without it the objective is
	-- unwinnable: hostiles now hold posts with verified sightlines, and a stationary player went from
	-- 100 to 11 health in seconds. Mitigation only while the hold is actually running, so camping
	-- next to the console gains nothing.
	if s.atConsole then
		amount = amount * 0.5
		workspace:SetAttribute("GF_ConsoleMitigated", (workspace:GetAttribute("GF_ConsoleMitigated") or 0) + 1)
	end
	local humanoid = humanoidOf(player)
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end

	-- A deployed dome absorbs damage for anyone standing inside it.
	local dome = s.activeDome
	if dome and dome.Parent then
		local domeHealth = dome:GetAttribute("DomeHealth")
		local radius = dome:GetAttribute("Radius") or 10
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if type(domeHealth) == "number" and domeHealth > 0 and root and (root.Position - dome.Position).Magnitude <= radius then
			dome:SetAttribute("DomeHealth", math.max(0, domeHealth - amount))
			s.lastDamage = now()
			if domeHealth - amount <= 0 then
				dome:Destroy()
				s.activeDome = nil
			end
			VitalsService.publish(player)
			return 0
		end
	end

	local remaining = amount
	local applied = 0

	if s.shield > 0 then
		local absorbed = math.min(s.shield, remaining)
		s.shield -= absorbed
		remaining -= absorbed
		applied += absorbed
		if s.shield <= 0 then
			ReplicatedStorage.GF.Remotes.ShieldBroken:FireClient(player)
		end
	end
	-- S04-058 directional damage: tell the victim which direction the hit came from so the HUD can
	-- arc the indicator. sourcePos is the attacker's position when the caller knows it.
	if sourcePos then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local dir = (sourcePos - root.Position)
			local flat = Vector3.new(dir.X, 0, dir.Z)
			if flat.Magnitude > 0.1 then
				local look = root.CFrame.LookVector
				local flatLook = Vector3.new(look.X, 0, look.Z).Unit
				local flatUnit = flat.Unit
				local angle = math.deg(math.atan2(flatUnit:Cross(flatLook).Y, flatUnit:Dot(flatLook)))
				local r = ReplicatedStorage.GF.Remotes:FindFirstChild("DirectionalHit")
				if r then
					r:FireClient(player, { angle = angle, amount = amount })
				end
			end
		end
	end

	if remaining > 0 then
		local lethal = humanoid.Health - remaining <= 0
		if lethal then
			-- Downed instead of instant death; health floors at 1 until revive or bleed-out.
			humanoid.Health = 1
			applied += humanoid.Health
			VitalsService.downPlayer(player)
		else
			humanoid.Health = humanoid.Health - remaining
			applied += remaining
		end
	end

	s.lastDamage = now()
	VitalsService.publish(player)
	return applied
end

function VitalsService.downPlayer(player: Player)
	local s = State.get(player)
	if not s or s.downed then
		return
	end
	s.downed = true
	s.downedAt = now()
	local character = player.Character
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = 5 -- crawl speed per S03-027
		humanoid.JumpPower = 0
	end
	if character then
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			for _, part in character:GetDescendants() do
				if part:IsA("BasePart") then
					if typeof(part:GetAttribute("GF_PreDownedCanCollide")) ~= "boolean" then
						part:SetAttribute("GF_PreDownedCanCollide", part.CanCollide)
					end
					part.CanCollide = false
				end
			end
		end
	end
	ReplicatedStorage.GF.Remotes.DownedChanged:FireClient(player, true)
	-- persistent character attribute mirror (movement/camera refinement): the client movement
	-- state machine polls this; the remote alone is a one-shot event respawns can miss.
	if player.Character then
		player.Character:SetAttribute("Downed", true)
	end
	VitalsService.publish(player)
end

function VitalsService.revive(player: Player)
	local s = State.get(player)
	if not s or not s.downed then
		return
	end
	s.downed = false
	s.shield = s.shieldMax * 0.5
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.Health = humanoid.MaxHealth * 0.5
		humanoid.WalkSpeed = Constants.Movement.WalkSpeed
		humanoid.JumpPower = Constants.Movement.JumpPower
	end
	restorePreDownedCollision(player.Character)
	ReplicatedStorage.GF.Remotes.DownedChanged:FireClient(player, false)
	-- persistent character attribute mirror (movement/camera refinement): the client movement
	-- state machine polls this; the remote alone is a one-shot event respawns can miss.
	if player.Character then
		player.Character:SetAttribute("Downed", false)
	end
	VitalsService.publish(player)
end

-- One heartbeat drives regen for every player: no per-player loops, no per-frame work.
function VitalsService.start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.25 then
			return
		end
		local step = accumulator
		accumulator = 0
		local t = now()
		for player, s in State.all() do
			if player.Parent == nil or s.downed then
				continue
			end
			local humanoid = humanoidOf(player)
			if not humanoid or humanoid.Health <= 0 then
				continue
			end
			local sinceDamage = t - s.lastDamage
			local changed = false
			if s.shield < s.shieldMax and sinceDamage >= Constants.Vitals.ShieldRegenDelay then
				s.shield = math.min(s.shieldMax, s.shield + Constants.Vitals.ShieldRegenRate * step * require(script.Parent.ClassService).regenFactor(player))
				changed = true
			end
			if humanoid.Health < humanoid.MaxHealth and sinceDamage >= Constants.Vitals.HealthRegenDelay then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + Constants.Vitals.HealthRegenRate * step)
				changed = true
			end
			if changed then
				VitalsService.publish(player)
			end
		end
	end)
end

return VitalsService

