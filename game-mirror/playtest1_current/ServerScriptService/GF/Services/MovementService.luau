--!strict
-- Server-authoritative dodge charges + sprint ceiling. Movement stays responsive, exploits stay bounded.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Constants = require(ReplicatedStorage.GF.Shared.Constants)
local State = require(ServerScriptService.GF.Services.State)
local MovementService = {}
local dodge: { [Player]: { charges: number, nextChargeAt: number, nextDodgeAt: number } } = {}
local function entry(player: Player)
	local e = dodge[player]
	if not e then
		e = { charges = Constants.Movement.RollCharges, nextChargeAt = 0, nextDodgeAt = 0 }
		dodge[player] = e
	end
	return e
end
local function publish(player: Player)
	local e = entry(player)
	ReplicatedStorage.GF.Remotes.DodgeUpdated:FireClient(player, { charges = e.charges, max = Constants.Movement.RollCharges })
end
local function doDodge(player: Player, payload: any)
	local s = State.get(player)
	if not s or s.downed then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local e = entry(player)
	local now = os.clock()
	if now < e.nextDodgeAt then
		return
	end
	if e.charges <= 0 then
		return
	end
	local direction = payload and payload.direction
	if typeof(direction) ~= "Vector3" then
		return
	end
	local flat = direction * Vector3.new(1, 0, 1)
	if flat.Magnitude < 0.1 then
		return
	end
	e.charges -= 1
	e.nextDodgeAt = now + Constants.Movement.RollDuration
	if e.charges < Constants.Movement.RollCharges then
		e.nextChargeAt = now + Constants.Movement.RollRecharge
	end
	-- Publish the roll so the animator can tuck the body: without this the dash read as a slide.
	character:SetAttribute("Rolling", true)
	task.delay(Constants.Movement.RollDuration, function()
		if character and character.Parent then
			character:SetAttribute("Rolling", false)
		end
	end)
	-- Spec: the roll covers ~13 studs over 0.55s. Use a planar LinearVelocity: it is a real physics
	-- constraint (so it works with character network ownership), but it constrains only X/Z and leaves
	-- vertical velocity to gravity and impacts. The previous vector constraint targeted Y=0 and made the
	-- roll hover; the direct-velocity replacement was fought by client network ownership and moved only
	-- a few studs. Plane mode is the correct middle ground.
	local rollDirection = flat.Unit
	local rollSpeed = Constants.Movement.RollDistance / Constants.Movement.RollDuration
	local speedScale = 1
	do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(root.Position, rollDirection * 2.8, params)
		if hit then
			speedScale = math.clamp((hit.Distance - 0.8) / 2.8, 0.15, 1)
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "GFDodgeAttachment"
	attachment.Parent = root
	local impulse = Instance.new("LinearVelocity")
	impulse.Name = "GFDodgeVelocity"
	impulse.Attachment0 = attachment
	impulse.RelativeTo = Enum.ActuatorRelativeTo.World
	impulse.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	impulse.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	impulse.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	impulse.PlaneVelocity = Vector2.new(rollDirection.X * rollSpeed * speedScale, rollDirection.Z * rollSpeed * speedScale)
	impulse.MaxForce = math.huge
	impulse.Parent = root
	task.delay(Constants.Movement.RollDuration, function()
		if impulse.Parent then
			impulse:Destroy()
		end
		if attachment.Parent then
			attachment:Destroy()
		end
	end)
	publish(player)
end
-- Fall damage (S03-021): downward landing speed decides - no artificial death pits, just physics.
local FALL_SAFE_SPEED = 55
local FALL_MAX_SPEED = 95
local fallTrack: { [Player]: number } = {}

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	-- Peak downward velocity is the honest impact measure: velocity at freefall entry is near zero and
	-- velocity at the Landed event is already dampened, so sample continuously while airborne.
	local peakFallSpeed = 0
	local falling = false
	game:GetService("RunService").Heartbeat:Connect(function()
		if not root.Parent then
			return
		end
		if falling then
			local vy = root.AssemblyLinearVelocity.Y
			if vy < 0 and -vy > peakFallSpeed then
				peakFallSpeed = -vy
			end
		end
	end)
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Freefall then
			falling = true
			peakFallSpeed = math.max(0, -root.AssemblyLinearVelocity.Y)
		elseif new == Enum.HumanoidStateType.Landed then
			falling = false
			local impact = math.abs(math.min(0, root.AssemblyLinearVelocity.Y))
			-- Landing velocity is often already dampened by the time Landed fires; take the worse of the two.
			impact = math.max(impact, peakFallSpeed)
			if impact <= FALL_SAFE_SPEED then
				return
			end
			-- Spec curve (S03-021): 55-95 linear up to 60 damage; above 95 rises to lethal at 140.
			-- Lethal means the full shield+health pool, so a 140 studs/s landing always kills.
			local damage
			if impact <= FALL_MAX_SPEED then
				damage = (impact - FALL_SAFE_SPEED) / (FALL_MAX_SPEED - FALL_SAFE_SPEED) * 60
			else
				local lethal = humanoid.MaxHealth + 100
				local t2 = math.clamp((impact - FALL_MAX_SPEED) / (140 - FALL_MAX_SPEED), 0, 1)
				damage = 60 + t2 * (lethal - 60)
			end
			if damage > 0 then
				pcall(function()
					require(script.Parent.VitalsService).applyDamage(player, damage, "fall")
				end)
				workspace:SetAttribute("GF_LastFallDamage", string.format("%s:%.0f@%.0f", player.Name, damage, impact))
			end
		end
	end)
end

function MovementService.start()
	game:GetService("Players").PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
	end)
	for _, player in game:GetService("Players"):GetPlayers() do
		if player.Character then
			watchCharacter(player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
	end
	ReplicatedStorage.GF.Remotes.RequestDodge.OnServerEvent:Connect(function(player, payload)
	if not require(script.Parent.NetGuard).allow(player, "default") then
		return
	end
	local st = State.get(player)
	if st then st.dodgeCount = (st.dodgeCount or 0) + 1 end
		pcall(doDodge, player, payload)
	end)
-- Single place that decides WalkSpeed, so crouch, sprint and aim cannot disagree. ADS was previously
-- unimplemented: Constants.Movement.AdsSpeed was read by nothing, so sights-up did not slow movement.
local function applyStance(player, character, humanoid)
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local st = State.get(player)
	if st and st.downed then
		-- Downed soldiers crawl. Stance replication must never promote them back to walk/sprint/ADS speed.
		character:SetAttribute("Sprinting", false)
		character:SetAttribute("Aiming", false)
		humanoid.WalkSpeed = 5
		humanoid.JumpPower = 0
		return
	end
	if character:GetAttribute("Aiming") == true then
		-- The adsSpeed augment stat modifies aim speed specifically. Until now it was listed by
		-- AugmentService but applied by nothing, so a rolled adsSpeed augment did nothing at all.
		local bonus = 0
		pcall(function()
			local augs = require(script.Parent.AugmentService).forPlayer(player)
			bonus = tonumber(augs and augs.adsSpeed) or 0
		end)
		-- Sign convention, explicit because the augment data is the only source of truth here:
		-- StabilityCompensator carries adsSpeed = -0.08 and is named a COMPENSATOR, so a negative value must
		-- make aiming LESS restrictive. Hence 1 - bonus, not 1 + bonus. Spec says nothing about this stat.
		humanoid.WalkSpeed = Constants.Movement.AdsSpeed * math.max(0.25, 1 - bonus)
	elseif character:GetAttribute("Sprinting") == true then
		humanoid.WalkSpeed = Constants.Movement.SprintSpeed
	else
		humanoid.WalkSpeed = Constants.Movement.WalkSpeed
	end
end
ReplicatedStorage.GF.Remotes.AimChanged.OnServerEvent:Connect(function(player, aiming)
	if not require(script.Parent.NetGuard).allow(player, "stance") then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local s = State.get(player)
	local on = aiming == true and not (s and s.downed)
	character:SetAttribute("Aiming", on)
	if on and character:GetAttribute("Sprinting") == true then
		character:SetAttribute("Sprinting", false)
	end
	applyStance(player, character, humanoid)
	workspace:SetAttribute("GF_AimState", tostring(on) .. ":" .. tostring(humanoid.WalkSpeed))
end)
ReplicatedStorage.GF.Remotes.SprintChanged.OnServerEvent:Connect(function(player, sprinting)
		if not require(script.Parent.NetGuard).allow(player, "stance") then
			return
		end
		local s = State.get(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not s or not humanoid then
			return
		end
		if character then
			character:SetAttribute("Sprinting", sprinting == true and not s.downed)
		end
		applyStance(player, character, humanoid)
	end)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, e in dodge do
			if player.Parent == nil then
				dodge[player] = nil
				continue
			end
			if e.charges < Constants.Movement.RollCharges and now >= e.nextChargeAt then
				e.charges += 1
				e.nextChargeAt = now + Constants.Movement.RollRecharge
				publish(player)
			end
		end
	end)
end
return MovementService
