--!strict
local Audio = require(script.Parent.GFAudio)
-- Client-side weapon feel. The server owns ammo, rate and damage; this module owns responsiveness.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
local Input = require(script.Parent.Input)
local HUD = require(script.Parent.HUD)
local VFX = require(script.Parent.VFX)

local Weapon = {}

local player = Players.LocalPlayer
local remotes = ReplicatedStorage.GF.Remotes

local state = {
	weaponId = "AR01",
	ammo = 28,
	magazine = 28,
	reloading = false,
	shotId = 0,
	lastSent = 0,
	firing = false,
	aiming = false,
}

local function characterParts(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head") :: BasePart?
	return character, humanoid, head
end

local function muzzleOrigin(head: BasePart): Vector3
	local camera = workspace.CurrentCamera
	local look = camera and camera.CFrame.LookVector or head.CFrame.LookVector
	return head.Position + look * 1.6 + Vector3.new(0, -0.15, 0)
end

local function tracer(from: Vector3, to: Vector3)
	local distance = (to - from).Magnitude
	if distance < 1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "Tracer"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(120, 220, 255)
	beam.Size = Vector3.new(0.08, 0.08, distance)
	beam.CFrame = CFrame.lookAt(from + (to - from) * 0.5, to)
	beam.Transparency = 0.25
	beam.Parent = workspace
	Debris:AddItem(beam, 0.07)
end

local function muzzleFlash(head: BasePart)
	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(180, 240, 255)
	flash.Size = Vector3.new(0.35, 0.35, 0.35)
	flash.Shape = Enum.PartType.Ball
	local camera = workspace.CurrentCamera
	local look = camera and camera.CFrame.LookVector or head.CFrame.LookVector
	flash.CFrame = CFrame.new(head.Position + look * 1.7)
	flash.Parent = workspace
	Debris:AddItem(flash, 0.05)
end

-- Muzzle position: the flash used to be emitted at the ray origin, which is the camera, so it
-- appeared in the middle of the player's torso instead of at the barrel (MICRO-026). Derive the
-- barrel tip from the right hand and the character's facing; keep the hit ray on the camera.
local function muzzlePosition(): Vector3?
	local char = player.Character
	if not char then
		return nil
	end
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("RightLowerArm")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hand or not root then
		return nil
	end
	-- prefer the viewmodel's actual muzzle part when the premium library is in use —
	-- fx originate at the real barrel tip instead of a hand+facing approximation
	if viewmodel then
		local muzzlePart = viewmodel:FindFirstChild("Muzzle", true)
		if muzzlePart and muzzlePart:IsA("BasePart") then
			return muzzlePart.Position
		end
	end
	local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if facing.Magnitude < 0.01 then
		facing = Vector3.new(0, 0, -1)
	end
	local pos = hand.Position + facing.Unit * 1.15 + Vector3.new(0, 0.06, 0)
	char:SetAttribute("GF_LastMuzzle", pos)
	return pos
end

-- Weapon ergonomics (Helldivers-lite): the visual/actual aim direction converges toward the
-- camera's intended direction with a per-category time constant. Small taus only — feedback,
-- never disconnection. The reticle's hollow ring renders this direction; hitscan uses it.
-- F1: instant weapon tracking per owner spec. The previous ergonomics layer converged the shot
-- direction toward the camera with a per-category time constant — at a 180deg/s turn that meant
-- 8-16 degrees of invisible lag, and the per-shot jitter below added further hidden dispersion the
-- reticle never showed. Exactly the "delayed weapon alignment" the spec forbids. The intended aim
-- is the camera look direction, always, immediately.
function Weapon.getAimDir(): Vector3
	local camera = workspace.CurrentCamera
	return (camera and camera.CFrame.LookVector) or Vector3.zAxis
end

local function tryFire()
	if state.reloading then
		return
	end
	local weapon = Weapons.get(state.weaponId)
	if not weapon then
		return
	end
	if state.ammo <= 0 then
		Weapon.reload()
		return
	end
	local now = os.clock()
	if now - state.lastSent < (60 / weapon.rpm) * 0.95 then
		return
	end
	local character, humanoid, head = characterParts()
	if not character or not humanoid or not head or humanoid.Health <= 0 then
		return
	end
	local camera = workspace.CurrentCamera
	local look = Weapon.getAimDir()
	-- Hitscan follows the rendered reticle. A parallel ray from the head missed the crosshair horizontally
	-- because the camera is deliberately offset over the right shoulder; use the camera ray for truth and
	-- keep the muzzle purely as the visual emitter. Camera collision already keeps this origin out of walls.
	local origin = camera and camera.CFrame.Position or muzzleOrigin(head)

	-- Muzzle obstruction validation runs BEFORE any state mutation: a denied shot must cost
	-- nothing. The old order consumed shotId/ammo/shake first, so obstructed shots silently ate
	-- predicted ammunition the server never knew about. (Geometry itself is upgraded with the
	-- server-side muzzle-to-point model in the parallax pack.)
	local muzzlePos = muzzlePosition()
	if muzzlePos then
		local muzzleParams = RaycastParams.new()
		muzzleParams.FilterType = Enum.RaycastFilterType.Exclude
		muzzleParams.FilterDescendantsInstances = { character }
		local toCamHit = (origin + look * 1e-3) - muzzlePos
		-- cast toward where the camera ray will travel; obstruction within the first stretch blocks
		local probe = workspace:Raycast(muzzlePos, look * math.max(4, toCamHit.Magnitude), muzzleParams)
		if probe and probe.Instance and not probe.Instance:IsDescendantOf(character) then
			local preHit = workspace:Raycast(origin, look * weapon.range, muzzleParams)
			if preHit and (probe.Position - origin).Magnitude < (preHit.Position - origin).Magnitude then
				return -- muzzle is behind cover the camera sees over: deny the shot entirely
			end
		end
	end

	state.shotId += 1
	state.lastSent = now
	state.ammo = math.max(0, state.ammo - 1)

	pcall(function()
		-- coherent recoil kick, not noise: the camera climbs by a small readable impulse per shot
		-- and recovers passively (CameraController additive decay — it never fights player input,
		-- never hides dispersion inside the aim math). Owner calibration: restrained, not a fight —
		-- 0.004 rad base x recoil scalar puts the AR at ~0.23deg/shot, launchers ~0.6-0.75deg single
		-- kicks. Horizontal gets a small random fraction for life — visible kick, not hidden jitter.
		local ctl = require(script.Parent.CameraCtl)
		local r = tonumber(weapon.recoil) or 1
		local vertical = 0.004 * r
		local horizontal = vertical * (math.random() - 0.5) * 0.4
		ctl.recoil(vertical, horizontal)
	end)

	remotes.FireWeapon:FireServer({
		weaponId = state.weaponId,
		shotId = state.shotId,
		origin = origin,
		direction = look,
	})

	-- local, immediate, never authoritative
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(origin, look * weapon.range, params)
	local endPoint = hit and hit.Position or (origin + look * weapon.range)

	local muzzle = muzzlePosition()
	VFX.muzzle(muzzle or origin, look)

	-- distinct voice per weapon class — the roster used to share one rifle crack, flattening
	-- identity no matter what the stats said. Variants are pitch/volume-shaped in GFAudio.
	do
		local cat = weapon.category
		local snd = (cat == "Shotgun" and "shotgun_fire")
			or (cat == "Pistol" and "pistol_fire")
			or (cat == "Marksman" and "marksman_fire")
			or (cat == "LMG" and "lmg_fire")
			or (cat == "SMG" and "smg_fire")
			or (cat == "Launcher" and "launcher_fire")
			or "rifle_fire"
		Audio.play(snd, origin)
	end
	if weapon.explosive then
		-- launchers: no hitscan impact theatre — the shell is a real travelling projectile and
		-- feedback arrives at detonation. A short tracer toward the first stretch of flight is
		-- honest visual texture; fake impact sparks at the hitscan endpoint were not.
		VFX.tracer(muzzle or origin, (muzzle or origin) + look * 24)
		HUD.setAmmo(state.ammo, state.magazine, state.reserve)
		return
	end
	VFX.tracer(muzzle or origin, endPoint)
	if hit and hit.Instance.Name == "DomeShield" then
		-- Projectile rule: a dome shell stops bullets. The dome is queryable but not collidable, so it
		-- blocks projectiles while players still walk through it.
		local dome = hit.Instance
		local domeHealth = tonumber(dome:GetAttribute("DomeHealth")) or 0
		dome:SetAttribute("DomeHealth", math.max(0, domeHealth - (weapon.damage or 10)))
		VFX.impact(hit.Position, hit.Normal, "SmoothPlastic", true)
		if domeHealth - (weapon.damage or 10) <= 0 then
			VFX.shieldBreak(hit.Position, hit.Normal)
			dome:Destroy()
		end
		HUD.setAmmo(state.ammo, state.magazine, state.reserve)
		return
	end
	if hit then
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		local isEnemy = model ~= nil and model:GetAttribute("GFEnemy") == true
		local shielded = isEnemy and (tonumber(model:GetAttribute("Shield")) or 0) > 0
		VFX.impact(hit.Position, hit.Normal, hit.Material.Name, shielded)
		-- Terrain and props are not flesh: the old fallback played the organic hit cue for every
		-- surface in the world, which made ordinary misses sound like wet enemy hits.
		if isEnemy then
			Audio.play(shielded and "hit_shield" or "hit_flesh", hit.Position)
		else
			Audio.play("hit_surface", hit.Position)
		end
	end
	HUD.setAmmo(state.ammo, state.magazine, state.reserve)
end

function Weapon.reload()
	local weapon = Weapons.get(state.weaponId)
	if not weapon or state.reloading or state.ammo >= weapon.magazine then
		return
	end
	state.reloading = true
	remotes.ReloadWeapon:FireServer({})
	Audio.play("reload_start")
	task.delay(weapon.reloadTime, function()
		state.reloading = false
		state.ammo = weapon.magazine
		Audio.play("reload")
		HUD.setAmmo(state.ammo, state.magazine, state.reserve)
	end)
end

-- Viewmodel: the character carried no weapon mesh at all, so the muzzle flash hung in the air and
-- nothing in the hands read as a rifle (MICRO-025). Built from parts, welded to a root that is
-- re-anchored to the right hand every frame, so it follows the arm through walk, aim and reload.
local RunService = game:GetService("RunService")
local viewmodel: Model? = nil

local function clearViewmodel()
	if viewmodel then
		viewmodel:Destroy()
		viewmodel = nil
	end
end

local WeaponVisuals = require(game:GetService("ReplicatedStorage"):WaitForChild("GF"):WaitForChild("Shared"):WaitForChild("WeaponVisuals"))

local function buildViewmodel(weapon: any)
	clearViewmodel()
	local char = player.Character
	if not char then
		return
	end
	-- premium per-weapon library: distinct silhouettes, faction palette, muzzle parts.
	-- the returned model uses the same Grip-root/PrimaryPart convention as the legacy
	-- placeholder, so updateViewmodel positioning and all combat behavior are untouched.
	local premium = WeaponVisuals.build(weapon.id)
	if premium then
		premium.Parent = char
		viewmodel = premium
		local length = tonumber(weapon.range) and math.clamp(weapon.range / 60, 1.4, 2.4) or 1.8
		char:SetAttribute("GF_ViewmodelLength", length)
		return
	end
	local model = Instance.new("Model")
	model.Name = "GF_Viewmodel"
	local root = Instance.new("Part")
	root.Name = "Grip"
	root.Size = Vector3.new(0.16, 0.22, 0.5)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Parent = model
	model.PrimaryPart = root
	local length = tonumber(weapon.range) and math.clamp(weapon.range / 60, 1.4, 2.4) or 1.8
	local function piece(name, size, offset, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CFrame = root.CFrame * CFrame.new(offset)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
		return p
	end
	piece("Body", Vector3.new(0.1, 0.16, length * 0.5), Vector3.new(0, 0, -length * 0.25), Color3.fromRGB(38, 42, 52), Enum.Material.Metal)
	piece("Barrel", Vector3.new(0.07, 0.07, length * 0.55), Vector3.new(0, 0.02, -length * 0.62), Color3.fromRGB(26, 28, 34), Enum.Material.Metal)
	piece("Stock", Vector3.new(0.08, 0.12, 0.42), Vector3.new(0, -0.02, length * 0.34), Color3.fromRGB(52, 46, 40), Enum.Material.Wood)
	piece("Magazine", Vector3.new(0.08, 0.24, 0.14), Vector3.new(0, -0.18, -0.06), Color3.fromRGB(44, 48, 56), Enum.Material.Metal)
	piece("Sight", Vector3.new(0.05, 0.09, 0.12), Vector3.new(0, 0.14, -0.1), Color3.fromRGB(96, 200, 255), Enum.Material.Neon)
	piece("Muzzle", Vector3.new(0.06, 0.06, 0.1), Vector3.new(0, 0.02, -length * 0.92), Color3.fromRGB(120, 220, 255), Enum.Material.Neon)
	model.Parent = char
	viewmodel = model
	char:SetAttribute("GF_ViewmodelLength", length)
end

local viewmodelAimLerp = 0
local VIEWMODEL_HIP = Vector3.new(0.62, -0.95, -0.85)
local VIEWMODEL_ADS = Vector3.new(0.36, -0.58, -1.02)
local function updateViewmodel(dt: number?)
	local char = player.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("RightLowerArm"))
	if not viewmodel or not hand or not viewmodel.PrimaryPart then
		return
	end
	-- Body-relative, not hand-relative: this rig's hand CFrame carries an inherited rotation and
	-- offsetting in hand space put the muzzle 9 studs from the hand (measured). The hand sits at
	-- (0.82, -1.11, 0.24) in root space, so the rifle is placed just inside that.
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	-- ADS pose: the weapon visibly rises inward toward the shoulder line instead of staying pinned at
	-- the hip while the camera tightens. This is presentation-only; the authoritative ray remains the reticle ray.
	viewmodelAimLerp += ((state.aiming and 1 or 0) - viewmodelAimLerp) * math.min(1, (dt or 1/60) * 10)
	local offset = VIEWMODEL_HIP:Lerp(VIEWMODEL_ADS, viewmodelAimLerp)
	-- PivotTo rigidly transforms the whole assembly; direct PrimaryPart assignment left
	-- welded pieces behind (and unanchored assemblies fell through the world entirely)
	viewmodel:PivotTo(root.CFrame * CFrame.new(offset))
	char:SetAttribute("GF_WeaponGrip", viewmodel.PrimaryPart.Position)
	char:SetAttribute("GF_ViewmodelAimLerp", viewmodelAimLerp)
end

function Weapon.equip(weaponId: string)
	local weapon = Weapons.get(weaponId)
	if not weapon then
		return
	end
	-- optimistic presentation only. Ammunition is authoritative server-side per-weapon now; the
	-- old local refill-to-full fabricated a fresh magazine on every swap.
	state.weaponId = weaponId
	state.reloading = false
	remotes.EquipWeapon:FireServer({ weaponId = weaponId })
	buildViewmodel(weapon)
	-- publish the zoom factor for the camera's per-weapon aim FOV (adsZoom was dead config data:
	-- every weapon aimed at the same fixed 58 FOV regardless of being a marksman or an SMG)
	game:GetService("Players").LocalPlayer:SetAttribute("GF_AdsZoom", tonumber(weapon.adsZoom) or 1.2)
end

function Weapon.getState()
	return state
end

function Weapon.init()
	VFX.init()
	RunService.RenderStepped:Connect(updateViewmodel)
	local function rebuildForCharacter(character: Model)
		task.defer(function()
			if player.Character ~= character then
				return
			end
			local weapon = Weapons.get(state.weaponId)
			if weapon then
				buildViewmodel(weapon)
			end
		end)
	end
	player.CharacterAdded:Connect(rebuildForCharacter)
	if player.Character then
		rebuildForCharacter(player.Character)
	end
	Input.onPress("Aim", function()
		state.aiming = true
		workspace:SetAttribute("GF_PlayerAiming", true)
		remotes.AimChanged:FireServer(true)
	end)
	Input.onRelease("Aim", function()
		state.aiming = false
		workspace:SetAttribute("GF_PlayerAiming", false)
		remotes.AimChanged:FireServer(false)
	end)
	Input.onPress("Fire", function()
		state.firing = true
		state.fireEdge = true
	end)
	Input.onRelease("Fire", function()
		state.firing = false
	end)
	Input.onPress("Reload", function()
		Weapon.reload()
	end)
	Input.onPress("SwapWeapon", function()
		-- resolve against the server-published loadout slots — the hardcoded AR01/P01 toggle
		-- stranded anyone carrying anything else (the toggle fired equip requests the server
		-- correctly rejected as not-in-loadout, so swap silently did nothing).
		local player = game:GetService("Players").LocalPlayer
		local primary = player:GetAttribute("GF_PrimaryWeapon") or "AR01"
		local secondary = player:GetAttribute("GF_SecondaryWeapon") or "P01"
		local target = (state.weaponId == primary) and secondary or primary
		if target ~= state.weaponId then
			Weapon.equip(target)
		end
	end)

	remotes.AmmoUpdated.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if type(payload.ammo) == "number" then
			state.ammo = payload.ammo
		end
		if type(payload.magazine) == "number" then
			state.magazine = payload.magazine
		end
		if type(payload.reserve) == "number" then
			state.reserve = payload.reserve
		end
		HUD.setAmmo(state.ammo, state.magazine, state.reserve)
	end)
	remotes.WeaponEquipped.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local changed = type(payload.weaponId) == "string" and payload.weaponId ~= state.weaponId
		state.weaponId = payload.weaponId or state.weaponId
		state.ammo = payload.ammo or state.ammo
		state.magazine = payload.magazine or state.magazine
		if type(payload.reserve) == "number" then
			state.reserve = payload.reserve
		end
		state.reloading = false
		if changed or not viewmodel then
			local weapon = Weapons.get(state.weaponId)
			if weapon then
				buildViewmodel(weapon)
			end
		end
		HUD.setAmmo(state.ammo, state.magazine, state.reserve)
		HUD.setWeapon(state.weaponId)
	end)
	remotes.DamageFeedback.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.killed then
			HUD.showKill()
			-- death burst + enemy_death cue: VFX.death existed but nothing ever called it
			if typeof(payload.position) == "Vector3" then
				VFX.death(payload.position)
			end
		end
		if type(payload) == "table" then
			HUD.showHitMarker(payload.weakPoint == true, payload.killed == true)
			if type(payload.damage) == "number" then
				HUD.showDamageNumber(payload.damage, payload.position, payload.weakPoint == true)
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if not state.firing then
			return
		end
		-- semi-automatic weapons require discrete trigger activations: exactly one shot attempt per
		-- press. The edge is consumed whether or not the shot clears the cadence gate, so holding
		-- the trigger never queues additional shots.
		local weapon = Weapons.get(state.weaponId)
		if weapon and weapon.fireMode ~= "Auto" then
			if state.fireEdge then
				state.fireEdge = false
				tryFire()
			end
		else
			tryFire()
		end
	end)

	HUD.setWeapon(state.weaponId)
	HUD.setAmmo(state.ammo, state.magazine, state.reserve)
end

-- publish ADS state for aim assist and HUD consumers
task.spawn(function()
	local last = nil
	while true do
		task.wait(0.1)
		if state.aiming ~= last then
			last = state.aiming
			workspace:SetAttribute("GF_PlayerAiming", last == true)
		end
	end
end)

return Weapon

