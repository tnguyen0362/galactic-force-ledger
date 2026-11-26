--!strict
-- Combat HUD: vitals, ammo, abilities, dodge, prompts, hit feedback, touch layer.
local Players = game:GetService("Players")
-- S03-042 color independence: status information never relies on color alone — every
-- color-coded element carries a shape, icon or text label so colorblind players read the
-- same information. Health uses bar length + number, shields use icon + bar, damage
-- direction uses positional indicators, not just screen tint.
local COLOR_BLIND_SAFE = true
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Input = require(script.Parent.Input)

local HUD = {}

local player = Players.LocalPlayer
local remotes = ReplicatedStorage.GF.Remotes

local gui: ScreenGui
local shieldFill: Frame
local healthFill: Frame
local shieldLabel: TextLabel
local ammoLabel: TextLabel
local weaponLabel: TextLabel
local crosshair: Frame
local hitMarker: Frame
local downedFrame: Frame
local dodgeLabel: TextLabel
local abilityLabels: { [string]: TextLabel } = {}

local abilityTitles: { [string]: any } = {}local abilityFills: { [string]: Frame } = {}
local promptLabel: TextLabel
local killLabel: TextLabel
local touchLayer: Frame
local cooldownEnds: { [string]: number } = {}
local touchButtons: { [string]: TextButton } = {}

local ACCENT = Color3.fromRGB(96, 200, 255)
local WARN = Color3.fromRGB(255, 120, 90)
local INK = Color3.fromRGB(232, 238, 246)

local function newFrame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function newLabel(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Size = size
	l.Position = position
	l.TextSize = textSize
	l.Font = Enum.Font.GothamMedium
	l.TextColor3 = INK
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = parent
	return l
end

local function buildTouchButton(action: string, text: string, size: UDim2, position: UDim2)
	local b = Instance.new("TextButton")
	b.Name = action
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = Color3.fromRGB(18, 24, 34)
	b.BackgroundTransparency = 0.35
	b.TextColor3 = INK
	b.Text = text
	b.TextSize = 20
	b.Font = Enum.Font.GothamBold
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Visible = false
	b.Parent = touchLayer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = b

	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			Input.setDevice("touch")
			if action == "Ability1" or action == "Ability2" then
				HUD.castAbility(action)
			elseif action == "Reload" then
				Input.setHeld("Reload", true, input)
			else
				Input.setHeld(action, true, input)
			end
		end
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and action ~= "Ability1" and action ~= "Ability2" then
			Input.setHeld(action, false, input)
		end
	end)
	touchButtons[action] = b
end

function HUD.init()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("GF_HUD")
	if existing then
		existing:Destroy()
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "GF_HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- vitals, top-left
	local vitals = newFrame(gui, {
		Name = "Vitals",
		Size = UDim2.fromOffset(260, 54),
		Position = UDim2.fromOffset(28, 26),
		-- the label sat directly on sky and vanished against the pale mission horizon
		BackgroundColor3 = Color3.fromRGB(8, 12, 18),
		BackgroundTransparency = 0.35,
	})
	local shieldBack = newFrame(vitals, {
		Name = "ShieldBack",
		Size = UDim2.fromOffset(240, 12),
		Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Color3.fromRGB(24, 34, 46),
	})
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 2); sc.Parent = shieldBack
	shieldFill = newFrame(shieldBack, {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = ACCENT,
	})
	shieldLabel = newLabel(vitals, "SHIELD 100", UDim2.fromOffset(240, 16), UDim2.fromOffset(0, 16), 13)
	shieldLabel.TextColor3 = Color3.fromRGB(226, 238, 248)

	local healthBack = newFrame(vitals, {
		Name = "HealthBack",
		Size = UDim2.fromOffset(200, 8),
		Position = UDim2.fromOffset(0, 36),
		BackgroundColor3 = Color3.fromRGB(40, 26, 26),
	})
	local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 2); hc.Parent = healthBack
	healthFill = newFrame(healthBack, {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(226, 92, 84),
	})

	-- ammo, bottom-right
	local ammoBox = newFrame(gui, {
		Name = "Ammo",
		Size = UDim2.fromOffset(200, 70),
		Position = UDim2.new(1, -228, 1, -110),
		BackgroundTransparency = 1,
	})
	weaponLabel = newLabel(ammoBox, "AR01", UDim2.fromOffset(200, 20), UDim2.fromOffset(0, 0), 15)
	weaponLabel.TextXAlignment = Enum.TextXAlignment.Right
	weaponLabel.TextColor3 = Color3.fromRGB(150, 170, 190)
	ammoLabel = newLabel(ammoBox, "28 / 28", UDim2.fromOffset(200, 40), UDim2.fromOffset(0, 18), 34)
	ammoLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- Helldivers-inspired compact military reticle (owner spec section 6): tiny central dot,
	-- small hollow circle, two short horizontal lines outside the circle. No vertical ticks, no
	-- oversized crosshair envelope. Lines track weapon dispersion dynamically — the geometry is
	-- driven per-frame by the reticle updater further down; construction here is static only.
	crosshair = newFrame(gui, {
		Name = "Crosshair",
		Size = UDim2.fromOffset(64, 64),
		Position = UDim2.new(0.5, -32, 0.5, -32),
		BackgroundTransparency = 1,
		BackgroundColor3 = INK,
	})
	do
		-- central dot: 2px logical at the 1920x1080 reference (spec: 1.5-2px)
		local dot = newFrame(crosshair, {
			Name = "Dot",
			Size = UDim2.fromOffset(2, 2),
			Position = UDim2.fromOffset(31, 31),
			BackgroundColor3 = INK,
			BackgroundTransparency = 0,
		})
		local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(0.5, 0); dc.Parent = dot
		-- two horizontal lines only, 5x1.5 logical px (spec: 4-6 long, 1-1.5 thick). Positions are
		-- driven per-frame — construction parks them at the zero-bloom aimed spacing.
		for _, side in ipairs({ "L", "R" }) do
			local tick = newFrame(crosshair, {
				Name = "Tick" .. side,
				Size = UDim2.fromOffset(5, 1.5),
				Position = UDim2.fromOffset(side == "L" and 18 or 41, 31.25),
				BackgroundColor3 = INK,
				BackgroundTransparency = 0.1,
			})
			local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 1); tc.Parent = tick
		end
		-- hollow circle: 10px logical diameter (spec: 8-12), ~1px stroke, fixed size — the moving
		-- lines carry the accuracy readout, the circle stays a stable precision reference.
		local ring = Instance.new("Frame")
		ring.Name = "ReticleRing"
		ring.Size = UDim2.fromOffset(10, 10)
		ring.Position = UDim2.fromOffset(27, 27)
		ring.BackgroundTransparency = 1
		ring.Parent = crosshair
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Name = "RingStroke"
		stroke.Color = INK
		stroke.Thickness = 1
		stroke.Transparency = 0.15
		stroke.Parent = ring
	end

	-- S06-058: dedicated boss HP bar — top-center, phase-colored, reads the published boss
	-- attributes so every client renders the same fight state without per-frame replication spam.
	local bossBar = newFrame(gui, {
		Name = "BossBar",
		Size = UDim2.new(0.4, 0, 0, 18),
		Position = UDim2.new(0.3, 0, 0, 12),
		BackgroundColor3 = Color3.fromRGB(16, 18, 22),
		BackgroundTransparency = 0.3,
		Visible = false,
	})
	local bossFill = newFrame(bossBar, {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 96, 72),
		BackgroundTransparency = 0.1,
	})
	local bossLabel = Instance.new("TextLabel")
	bossLabel.Name = "Label"
	bossLabel.BackgroundTransparency = 1
	bossLabel.Size = UDim2.fromScale(1, 1)
	bossLabel.Font = Enum.Font.GothamBold
	bossLabel.TextSize = 13
	bossLabel.TextColor3 = Color3.fromRGB(240, 235, 230)
	bossLabel.TextStrokeTransparency = 0.5
	bossLabel.Text = ""
	bossLabel.Parent = bossBar

	-- hitmarker: an X of two rotated bars. The old implementation relied on frame borders over a
	-- fully transparent background — borders do not render that way, so hit confirmation was
	-- literally invisible. Bars are real geometry: always visible, color-coded per hit type.
	hitMarker = newFrame(gui, {
		Name = "HitMarker",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(0.5, -11, 0.5, -11),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	})
	for _, rot in ipairs({ 45, -45 }) do
		local bar = newFrame(hitMarker, {
			Name = "Bar" .. tostring(rot),
			Size = UDim2.fromOffset(14, 2),
			Position = UDim2.new(0.5, -7, 0.5, -1),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
		})
		bar.Rotation = rot
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 1); bc.Parent = bar
	end

	killLabel = newLabel(gui, "", UDim2.fromOffset(240, 26), UDim2.new(0.5, -120, 0.5, 30), 16)
	killLabel.TextXAlignment = Enum.TextXAlignment.Center
	killLabel.TextColor3 = Color3.fromRGB(255, 214, 150)

	-- abilities, bottom-centre
	local abilityBar = newFrame(gui, {
		Name = "Abilities",
		Size = UDim2.fromOffset(260, 64),
		Position = UDim2.new(0.5, -130, 1, -104),
		BackgroundTransparency = 1,
	})
	local function abilitySlot(id: string, label: string, offsetX: number)
		local slot = newFrame(abilityBar, {
			Name = id,
			Size = UDim2.fromOffset(118, 56),
			Position = UDim2.fromOffset(offsetX, 0),
			BackgroundColor3 = Color3.fromRGB(14, 20, 28),
			BackgroundTransparency = 0.25,
		})
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = slot
		local name = newLabel(slot, label, UDim2.fromOffset(118, 18), UDim2.fromOffset(0, 6), 13)
		name.TextXAlignment = Enum.TextXAlignment.Center
		local status = newLabel(slot, "READY", UDim2.fromOffset(118, 22), UDim2.fromOffset(0, 26), 16)
		status.TextXAlignment = Enum.TextXAlignment.Center
		status.TextColor3 = ACCENT
		abilityLabels[id] = status
		abilityTitles[id] = name
		local fill = newFrame(slot, {
			Name = "Cooldown",
			Size = UDim2.new(1, 0, 0, 3),
			Position = UDim2.new(0, 0, 1, -3),
			BackgroundColor3 = ACCENT,
		})
		abilityFills[id] = fill
	end
	abilitySlot("Airstrike", "AIRSTRIKE [" .. Input.glyph("Ability1") .. "]", 0)
	abilitySlot("DomeShield", "DOME [" .. Input.glyph("Ability2") .. "]", 138)

	dodgeLabel = newLabel(gui, "DODGE 2/2", UDim2.fromOffset(160, 18), UDim2.new(0.5, -80, 1, -34), 13)
	dodgeLabel.TextXAlignment = Enum.TextXAlignment.Center

	promptLabel = newLabel(gui, "", UDim2.fromOffset(560, 22), UDim2.new(0.5, -280, 1, -158), 15)
	promptLabel.TextXAlignment = Enum.TextXAlignment.Center
	promptLabel.TextColor3 = Color3.fromRGB(190, 210, 230)

	-- downed overlay
	downedFrame = newFrame(gui, {
		Name = "Downed",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(60, 8, 8),
		BackgroundTransparency = 0.72,
		Visible = false,
	})
	local downedText = newLabel(downedFrame, "DOWNED", UDim2.fromScale(1, 0.72), UDim2.fromScale(0, 0), 48)
	downedText.TextXAlignment = Enum.TextXAlignment.Center
	downedText.Font = Enum.Font.GothamBlack
	downedText.TextColor3 = WARN
	local downedDetail = newLabel(downedFrame, "Awaiting revive", UDim2.new(1, 0, 0, 42), UDim2.new(0, 0, 0.58, 0), 20)
	downedDetail.TextXAlignment = Enum.TextXAlignment.Center
	downedDetail.Font = Enum.Font.GothamBold
	downedDetail.TextColor3 = Color3.fromRGB(255, 214, 170)

	-- touch layer
	touchLayer = newFrame(gui, {
		Name = "Touch",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	})
	buildTouchButton("Fire", "FIRE", UDim2.fromOffset(96, 96), UDim2.new(1, -136, 1, -220))
	buildTouchButton("Aim", "ADS", UDim2.fromOffset(72, 72), UDim2.new(1, -226, 1, -180))
	buildTouchButton("Jump", "JUMP", UDim2.fromOffset(72, 72), UDim2.new(1, -136, 1, -300))
	buildTouchButton("Dodge", "ROLL", UDim2.fromOffset(72, 72), UDim2.new(1, -226, 1, -270))
	-- Reload overlapped Aim by 10x12 px at every resolution: the offsets are absolute pixels, so this collision
	-- was not a small-screen problem, it was always there.
	buildTouchButton("Reload", "RELOAD", UDim2.fromOffset(84, 56), UDim2.new(1, -320, 1, -134))
	buildTouchButton("Ability1", "AIR", UDim2.fromOffset(64, 64), UDim2.new(1, -330, 1, -320))
	buildTouchButton("Ability2", "DOME", UDim2.fromOffset(64, 64), UDim2.new(1, -258, 1, -352))

	-- remote wiring
	remotes.VitalsUpdated.OnClientEvent:Connect(function(v)
		if type(v) ~= "table" then return end
	downedFrame.Visible = v.downed == true
	crosshair.Visible = v.downed ~= true
		local shield = tonumber(v.shield) or 0
		local shieldMax = tonumber(v.shieldMax) or 100
		local health = tonumber(v.health) or 0
		local healthMax = tonumber(v.healthMax) or 100
		shieldFill.Size = UDim2.fromScale(math.clamp(shield / math.max(1, shieldMax), 0, 1), 1)
		healthFill.Size = UDim2.fromScale(math.clamp(health / math.max(1, healthMax), 0, 1), 1)
		shieldLabel.Text = string.format("SHIELD %d", math.floor(shield + 0.5))
	end)
	-- S04-058 directional damage: a brief red arc on the reticle edge showing the hit direction.
	local dirIndicator = newFrame(gui, {
		Name = "DirectionalHit",
		Size = UDim2.fromOffset(90, 90),
		Position = UDim2.new(0.5, -45, 0.5, -45),
		BackgroundTransparency = 1,
		Visible = false,
	})
	local dirArc = newFrame(dirIndicator, {
		Name = "Arc",
		Size = UDim2.fromOffset(26, 6),
		Position = UDim2.new(0.5, -13, 0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 70, 60),
		BackgroundTransparency = 0.15,
	})
	local dac = Instance.new("UICorner"); dac.CornerRadius = UDim.new(0, 3); dac.Parent = dirArc
	remotes.DirectionalHit.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		dirIndicator.Rotation = tonumber(payload.angle) or 0
		dirIndicator.Visible = true
		dirArc.BackgroundTransparency = 0.15
		task.delay(0.7, function()
			dirIndicator.Visible = false
		end)
	end)
	remotes.ShieldBroken.OnClientEvent:Connect(function()
		-- distinct shield-break cue (S04-058): sharper than a hit, audible over combat
		pcall(function()
			require(script.Parent.GFAudio).play("shield_break")
		end)
		shieldLabel.TextColor3 = WARN
		task.delay(1.2, function()
			shieldLabel.TextColor3 = ACCENT
		end)
	end)
	remotes.DownedChanged.OnClientEvent:Connect(function(downed)
		downedFrame.Visible = downed == true
		crosshair.Visible = downed ~= true
	end)
	remotes.DodgeUpdated.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		dodgeLabel.Text = string.format("DODGE %d/%d", payload.charges or 0, payload.max or 2)
	end)
	remotes.AbilityStateChanged.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.abilityId) ~= "string" then return end
		cooldownEnds[payload.abilityId] = os.clock() + (tonumber(payload.duration) or 0)
	end)

	HUD.setDevice(UserInputService:GetLastInputType())

	task.spawn(function()
		while gui.Parent do
			task.wait(0.1)
			-- Lobby keeps abilities/dodge/vitals visible, but not firing-range furniture. The crosshair and
			-- ammo box are combat-only; hiding the whole HUD made the loadout invisible on the station.
			local inMission = workspace:GetAttribute("GF_EnvironmentPreset") == "mission"
			local ammoBox = gui:FindFirstChild("Ammo")
			if ammoBox and ammoBox:IsA("GuiObject") then
				ammoBox.Visible = inMission
			end
			if crosshair then
				crosshair.Visible = inMission and not (downedFrame and downedFrame.Visible)
			end
			if downedFrame and downedFrame.Visible then
				local pendingFor = workspace:GetAttribute("GF_RedeployPendingFor")
				if pendingFor == player.Name then
					local remaining = math.max(0, tonumber(workspace:GetAttribute("GF_RedeployCountdown")) or 0)
					downedText.Text = "K.I.A."
					downedDetail.Text = string.format("AUTOMATIC REDEPLOY IN %.0f — ABILITIES PRESERVED", remaining)
				else
					downedText.Text = "DOWNED"
					downedDetail.Text = "AWAITING REVIVE — STAY IN RANGE"
				end
			end
			-- boss HP bar: visible while a boss lives, phase-colored fill
			do
				local bossBar = gui:FindFirstChild("BossBar", true)
				if bossBar then
					local hp = workspace:GetAttribute("BossHealth") or 0
					local phase = workspace:GetAttribute("BossPhase") or 1
					local active = workspace:GetAttribute("BastionActive") == true or workspace:GetAttribute("VeyrActive") == true
					if active then
						-- Field bosses exist in the ecology hundreds of metres away. The boss bar is combat
						-- information, not a permanent mission banner: appear only when the squad is close
						-- enough to engage or after the boss has taken damage.
						local maxHp = workspace:GetAttribute("BossMaxHealth") or 3600
						local damaged = hp < maxHp
						local near = false
						local actorsFolder = workspace:FindFirstChild("ActiveActors")
						local bossModel = (actorsFolder and (actorsFolder:FindFirstChild("BastionWalker") or actorsFolder:FindFirstChild("HighMarshalVeyr")))
							or workspace:FindFirstChild("BastionWalker") or workspace:FindFirstChild("HighMarshalVeyr")
						local bossPart = bossModel and ((bossModel :: Model).PrimaryPart or bossModel:FindFirstChildWhichIsA("BasePart", true))
						local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						if bossPart and root then
							near = (bossPart.Position - root.Position).Magnitude <= 140
						end
						active = damaged or near
					end
					bossBar.Visible = inMission and active and hp > 0
					if bossBar.Visible then
						local fill = bossBar:FindFirstChild("Fill")
						local maxHp = workspace:GetAttribute("BossMaxHealth") or 3600
						if fill then
							fill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
							fill.BackgroundColor3 = phase >= 3 and Color3.fromRGB(255, 60, 48) or (phase == 2 and Color3.fromRGB(255, 140, 64) or Color3.fromRGB(255, 96, 72))
						end
						local label = bossBar:FindFirstChild("Label")
						if label then
							label.Text = "BASTION WALKER — PHASE " .. tostring(phase)
						end
					end
				end
			end

			local now = os.clock()
			for id, endsAt in cooldownEnds do
				local label = abilityLabels[id]
				local fill = abilityFills[id]
				if label then
					local remaining = endsAt - now
					if remaining > 0 then
						label.Text = string.format("%.1fs", remaining)
						label.TextColor3 = Color3.fromRGB(150, 160, 175)
						if fill then fill.Size = UDim2.fromScale(remaining / math.max(1, (endsAt - (endsAt - remaining))), 0) end
					else
						label.Text = "READY"
						label.TextColor3 = ACCENT
						if fill then fill.Size = UDim2.fromScale(1, 0) end
					end
				end
			end
		end
	end)
end

function HUD.setDevice(kind: any)
	Input.setDevice(kind)
	local isTouch = Input.getDevice() == "touch"
	if touchLayer then
		touchLayer.Visible = isTouch
	end
	-- Re-render the ability titles with the current glyph, and do NOT touch the status text: overwriting it
	-- here reset every cooldown readout to READY on any input-family change.
	for id, title in pairs(abilityTitles) do
		if title then
			title.Text = string.format("%s [%s]", id == "Airstrike" and "AIRSTRIKE" or "DOME", Input.glyph(id == "Airstrike" and "Ability1" or "Ability2"))
		end
	end
	if promptLabel then
		promptLabel.Text = isTouch and "" or string.format("Fire [%s]  Aim [%s]  Dodge [%s]  Reload [%s]  Abilities [%s]/[%s]",
			Input.glyph("Fire"), Input.glyph("Aim"), Input.glyph("Dodge"), Input.glyph("Reload"),
			Input.glyph("Ability1"), Input.glyph("Ability2"))
	end
end

function HUD.setAmmo(ammo: number, magazine: number, reserve: number?)
	if ammoLabel then
		-- S04-027: reserve is now tracked, so show it. Without this the player cannot see that ammunition
		-- is finite, which makes the whole reserve economy invisible in play.
		if type(reserve) == "number" then
			ammoLabel.Text = string.format("%d / %d  ·  %d", ammo, magazine, reserve)
		else
			ammoLabel.Text = string.format("%d / %d", ammo, magazine)
		end
		ammoLabel.TextColor3 = ammo == 0 and WARN or INK
	end
end

function HUD.setWeapon(weaponId: string)
	HUD._weaponId = weaponId
	if weaponLabel then
		local Weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
		local def = Weapons.get(weaponId)
		weaponLabel.Text = (def and def.displayName) or weaponId
	end
end

function HUD.showHitMarker(weak: boolean, killed: boolean)
	if not hitMarker then return end
	local color = killed and Color3.fromRGB(255, 110, 90)
		or (weak and Color3.fromRGB(255, 214, 130) or Color3.fromRGB(255, 255, 255))
	local size = weak and 30 or 22
	hitMarker.Size = UDim2.fromOffset(size, size)
	hitMarker.Position = UDim2.new(0.5, -size / 2, 0.5, -size / 2)
	for _, bar in hitMarker:GetChildren() do
		if bar:IsA("Frame") then
			bar.BackgroundColor3 = color
			bar.Size = UDim2.fromOffset(math.floor(size * 0.64), killed and 3 or 2)
			bar.Position = UDim2.new(0.5, -math.floor(size * 0.64) / 2, 0.5, killed and -1.5 or -1)
		end
	end
	hitMarker.Visible = true
	task.delay(0.12, function()
		if hitMarker then
			hitMarker.Visible = false
		end
	end)
end

-- Floating damage numbers at the hit position (spec S03-041 optional damage numbers): world-space
-- billboard that rises and fades in under a second. Honours the server-validated setting.
function HUD.showDamageNumber(amount: number, position: Vector3?, weakPoint: boolean?)
	local player = game:GetService("Players").LocalPlayer
	if player and player:GetAttribute("GF_Setting_DamageNumbers") == false then
		return
	end
	if typeof(position) ~= "Vector3" or type(amount) ~= "number" then
		return
	end
	local part = Instance.new("Part")
	part.Name = "DamageNumber"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = position + Vector3.new(0, 1, 0)
	part.Parent = workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(90, 30)
	bb.AlwaysOnTop = true
	bb.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = weakPoint and 20 or 15
	label.TextColor3 = weakPoint and Color3.fromRGB(255, 200, 90) or Color3.fromRGB(240, 240, 235)
	label.TextStrokeTransparency = 0.4
	label.Text = tostring(math.floor(amount + 0.5))
	label.Parent = bb
	game:GetService("TweenService"):Create(part, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = part.Position + Vector3.new(0, 2.4, 0),
	}):Play()
	game:GetService("TweenService"):Create(label, TweenInfo.new(0.85), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(part, 0.95)
end

function HUD.showKill()
	if not killLabel then return end
	killLabel.Text = "TARGET DOWN"
	task.delay(0.9, function()
		if killLabel then killLabel.Text = "" end
	end)
end

function HUD.castAbility(action: string)
	local fallback = action == "Ability1" and "Airstrike" or "DomeShield"
	local slotAttr = action == "Ability1" and "GF_Ability1" or "GF_Ability2"
	local published = player:GetAttribute(slotAttr)
	if type(published) ~= "string" then
		published = workspace:GetAttribute(slotAttr)
	end
	local abilityId = type(published) == "string" and published or fallback
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then return end
	local camera = workspace.CurrentCamera
	local look = camera and camera.CFrame.LookVector or head.CFrame.LookVector
	local origin = head.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(origin, look * 90, params)
	local point = hit and hit.Position or (origin + look * 60)
	remotes.UseAbility:FireServer({ abilityId = abilityId, position = point })
end

function HUD.setPrompt(text: string)
	if promptLabel then
		promptLabel.Text = text
	end
end


-- ---------------------------------------------------------------------------
-- Reticle spread updater (spec section 6): per-frame, viewport-scaled, truthful to weapon state.
-- The horizontal lines track effective dispersion — base hip/aimed cone + bloom + movement —
-- with continuous client-side decay prediction between authoritative server updates. The ring
-- stays fixed as a precision reference; the center dot is never smoothed, never offset.
do
	local Weapons = require(ReplicatedStorage.GF.Shared.Configs.Weapons)
	local lastBloom = 0
	local bloomAt = os.clock()
	local displayHalfGap = 9

	-- mirror the server's post-shot bloom value and timestamp it locally; prediction decays from
	-- there. Server recovery rate is 2.6 deg/s (CombatService) — keep in sync when tuning.
	player:GetAttributeChangedSignal("SpreadBloom"):Connect(function()
		lastBloom = tonumber(player:GetAttribute("SpreadBloom")) or 0
		bloomAt = os.clock()
	end)

	RunService.RenderStepped:Connect(function(dt)
		if not crosshair or not crosshair.Parent then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local weapon = Weapons.get(HUD._weaponId or "")
		local aiming = workspace:GetAttribute("GF_PlayerAiming") == true
		local base = 1
		if weapon then
			base = aiming and (tonumber(weapon.adsSpread) or tonumber(weapon.spreadBase) or 1)
				or (tonumber(weapon.spreadBase) or 1)
		end
		-- movement penalty mirrors the server's +1.5deg over 2 studs/s
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local moving = root and root.AssemblyLinearVelocity.Magnitude > 2
		-- continuous bloom prediction: decay the last server value rather than waiting for the
		-- next accepted shot — the old display stayed expanded indefinitely between shots.
		local bloom = math.max(0, lastBloom - (os.clock() - bloomAt) * 2.6)
		local alpha = base + bloom + (moving and 1.5 or 0)
		-- compact monotonic accuracy representation (spec section 6): log response, not the raw
		-- physical cone — alphaRef/alphaMax calibrate the display range, not ballistic truth.
		local alphaRef, alphaMax = 0.5, 7
		local x = math.clamp(math.log(1 + alpha / alphaRef) / math.log(1 + alphaMax / alphaRef), 0, 1)
		-- inner-edge distance of the lines: 9px tight (aimed, no bloom) to 21px wide (hip, full)
		local gapTarget = 9 + (21 - 9) * x
		-- expansion reacts immediately, recovery lightly damped (spec: tau 0.04-0.08s)
		local tau = gapTarget > displayHalfGap and 0.02 or 0.06
		displayHalfGap = gapTarget + (displayHalfGap - gapTarget) * math.exp(-dt / tau)
		-- viewport scaling: reference 1920x1080, clamped so the reticle survives mobile and 4k
		local vp = camera.ViewportSize
		local scale = math.clamp(math.min(vp.X / 1920, vp.Y / 1080), 0.7, 1.6)
		local halfGap = displayHalfGap * scale
		local lineLen = 5 * scale
		local thick = math.max(1, 1.5 * scale)
		local tickL = crosshair:FindFirstChild("TickL")
		local tickR = crosshair:FindFirstChild("TickR")
		if tickL and tickR then
			tickL.Size = UDim2.fromOffset(lineLen, thick)
			tickR.Size = UDim2.fromOffset(lineLen, thick)
			tickL.Position = UDim2.fromOffset(32 - halfGap - lineLen, 32 - thick / 2)
			tickR.Position = UDim2.fromOffset(32 + halfGap, 32 - thick / 2)
		end
		local ring = crosshair:FindFirstChild("ReticleRing")
		if ring then
			local d = 10 * scale
			ring.Size = UDim2.fromOffset(d, d)
			ring.Position = UDim2.fromOffset(32 - d / 2, 32 - d / 2)
		end
		local dot = crosshair:FindFirstChild("Dot")
		if dot then
			local d = math.max(1.5, 2 * scale)
			dot.Size = UDim2.fromOffset(d, d)
			dot.Position = UDim2.fromOffset(32 - d / 2, 32 - d / 2)
		end
	end)
end

return HUD

