--!strict
-- Traveling launcher projectiles (S04-048): server-simulated kinematic shells consistent with the
-- kinematic enemy architecture - no physics ownership, deterministic stepping, collision-or-lifetime
-- detonation. GL arcs under gravity; RL flies flatter and faster. Clients get one fire remote with the
-- ballistic parameters and animate the visual shell along the same math.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProjectileService = {}

-- Tunables. Speeds chosen for readable arcs at the authored ranges (GL 180, RL 260).
local MUZZLE = {
	GL22 = { speed = 95, gravity = 65, lifetime = 6 },
	RL09 = { speed = 150, gravity = 4, lifetime = 4 },
}
local DEFAULTS = { speed = 70, gravity = 20, lifetime = 5 }

type Shell = {
	position: Vector3,
	velocity: Vector3,
	gravity: number,
	age: number,
	lifetime: number,
	weapon: any,
	shooter: Player?,
}

local shells: { Shell } = {}
local stepping = false

local function step(dt: number)
	for i = #shells, 1, -1 do
		local shell = shells[i]
		shell.age += dt
		-- integrate: gravity pulls the arc down over time
		shell.velocity = shell.velocity - Vector3.new(0, shell.gravity * dt, 0)
		local displacement = shell.velocity * dt
		-- collision: raycast along this step; terrain, structures, enemies all stop the shell
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { workspace:FindFirstChild("ActiveActors") == nil and workspace or nil, shell.shooter and shell.shooter.Character }
		-- enemies must NOT be excluded from collision - a direct hit detonates on contact. But their
		-- hit volumes live in ActiveActors, so only the folder itself cannot be a filter target here.
		params.FilterDescendantsInstances = { shell.shooter and shell.shooter.Character }
		local hit = workspace:Raycast(shell.position, displacement, params)
		local detonateAt: Vector3? = nil
		if hit then
			detonateAt = hit.Position
		elseif shell.age >= shell.lifetime then
			detonateAt = shell.position + displacement -- lifetime airburst
		end
		if detonateAt then
			table.remove(shells, i)
			local CombatService = require(ServerScriptService.GF.Services.CombatService)
			local hits = CombatService.detonate(detonateAt, shell.weapon, shell.shooter)
			workspace:SetAttribute("GF_ProjectileDetonated", string.format("%s@%.1fs hits=%d", shell.weapon.id or "?", shell.age, hits))
			local Remotes = ReplicatedStorage.GF:FindFirstChild("Remotes")
			local ev = Remotes and Remotes:FindFirstChild("ProjectileDetonated")
			if ev and ev:IsA("RemoteEvent") then
				ev:FireAllClients(detonateAt, shell.weapon.id)
			end
		else
			shell.position = shell.position + displacement
		end
	end
	if #shells == 0 then
		stepping = false
	end
end

function ProjectileService.launch(shooter: Player?, weapon: any, origin: Vector3, direction: Vector3)
	local spec = MUZZLE[weapon.id or ""] or DEFAULTS
	-- projectileVelocity augment stat: scales muzzle speed per shooter+weapon. The scaled velocity is
	-- what gets broadcast to clients, so the visual arc stays in sync with server ballistics for free.
	local speed = spec.speed
	if shooter then
		pcall(function()
			local augs = require(script.Parent.AugmentService).forPlayerWeapon(shooter, weapon.id)
			speed = speed * math.max(0.5, 1 + (tonumber(augs and augs.projectileVelocity) or 0))
		end)
	end
	local shell: Shell = {
		position = origin,
		velocity = direction.Unit * speed,
		gravity = spec.gravity,
		age = 0,
		lifetime = spec.lifetime,
		weapon = weapon,
		shooter = shooter,
	}
	table.insert(shells, shell)
	workspace:SetAttribute("GF_ProjectileLaunched", tostring(weapon.id))
	-- tell clients to animate the visual along the same ballistic parameters
	local Remotes = ReplicatedStorage.GF:FindFirstChild("Remotes")
	local ev = Remotes and Remotes:FindFirstChild("ProjectileFired")
	if ev and ev:IsA("RemoteEvent") then
		ev:FireAllClients(origin, shell.velocity, spec.gravity, spec.lifetime, weapon.id)
	end
	if not stepping then
		stepping = true
		task.spawn(function()
			while stepping do
				local dt = task.wait(1 / 30)
				step(dt)
			end
		end)
	end
	return true
end

function ProjectileService.activeCount(): number
	return #shells
end

-- exposed for tests
function ProjectileService.muzzle(weaponId: string)
	return MUZZLE[weaponId] or DEFAULTS
end

return ProjectileService
