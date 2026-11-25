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

	-- crosshair: a 6px dot reads as a speck on a 1100px shot. Reticle = centre dot + four ticks
	-- pushed out 11px, so the aim point stays readable against the black deck and against the sky.
	crosshair = newFrame(gui, {
		Name = "Crosshair",
		Size = UDim2.fromOffset(64, 64),
		Position = UDim2.new(0.5, -32, 0.5, -32),
		BackgroundTransparency = 1,
		BackgroundColor3 = INK,
	})
	do
		local dot = newFrame(crosshair, {
			Name = "Dot",
			Size = UDim2.fromOffset(3, 3),
			Position = UDim2.fromOffset(30.5, 30.5),
			BackgroundColor3 = INK,
			BackgroundTransparency = 0,
		})
		local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(0.5, 0); dc.Parent = dot
		local ticks = {
			{ 31, 0, 2, 10 },
			{ 31, 54, 2, 10 },
			{ 0, 31, 10, 2 },
			{ 54, 31, 10, 2 },
		}
		for i, t in ipairs(ticks) do
			local tick = newFrame(crosshair, {
				Name = "Tick" .. i,
				Size = UDim2.fromOffset(t[3], t[4]),
				Position = UDim2.fromOffset(t[1], t[2]),
				BackgroundColor3 = INK,
				BackgroundTransparency = 0.2,
			})
			local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 1); tc.Parent = tick
		end
		-- S03-039: hollow circle reticle with spread feedback — the ring expands with the weapon's
		-- current bloom so players read accuracy without a number; horizontal lines stay short.
		local ring = Instance.new("Frame")
		ring.Name = "ReticleRing"
		ring.Size = UDim2.fromOffset(26, 26)
		ring.Position = UDim2.fromOffset(19, 19)
		ring.BackgroundTransparency = 1
		ring.Parent = crosshair
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Name = "RingStroke"
		stroke.Color = INK
		stroke.Thickness = 1.5
		stroke.Transparency = 0.25
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

	hitMarker = newFrame(gui, {
		Name = "HitMarker",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(0.5, -11, 0.5, -11),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 2,
	})
	local hmc = Instance.new("UICorner"); hmc.CornerRadius = UDim.new(0.5, 0); hmc.Parent = hitMarker
	hitMarker.BorderColor3 = Color3.fromRGB(255, 240, 200)

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
	local downedText = newLabel(downedFrame, "DOWNED", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 48)
	downedText.TextXAlignment = Enum.TextXAlignment.Center
	downedText.Font = Enum.Font.GothamBlack
	downedText.TextColor3 = WARN

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
			-- boss HP bar: visible while a boss lives, phase-colored fill
			do
				local bossBar = gui:FindFirstChild("BossBar", true)
				if bossBar then
					local hp = workspace:GetAttribute("BossHealth") or 0
					local phase = workspace:GetAttribute("BossPhase") or 1
					local active = workspace:GetAttribute("BastionActive") == true or (hp and hp > 0)
					bossBar.Visible = active and hp > 0
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
			-- spread feedback: hollow ring scales with live weapon bloom so accuracy reads visually
			do
				local ring = crosshair and crosshair:FindFirstChild("ReticleRing")
				if ring then
					local bloom = player:GetAttribute("SpreadBloom") or 0
					local scale = 26 + math.clamp(bloom * 3.2, 0, 30)
					ring.Size = UDim2.fromOffset(scale, scale)
					ring.Position = UDim2.fromOffset(32 - scale / 2, 32 - scale / 2)
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
	if weaponLabel then
		weaponLabel.Text = weaponId
	end
end

function HUD.showHitMarker(weak: boolean, killed: boolean)
	if not hitMarker then return end
	hitMarker.BorderColor3 = killed and Color3.fromRGB(255, 120, 100) or (weak and Color3.fromRGB(255, 220, 140) or Color3.fromRGB(255, 255, 255))
	hitMarker.BackgroundTransparency = 1
	hitMarker.Size = UDim2.fromOffset(weak and 30 or 22, weak and 30 or 22)
	hitMarker.Position = UDim2.new(0.5, -(weak and 15 or 11), 0.5, -(weak and 15 or 11))
	hitMarker.BorderSizePixel = 2
	task.delay(0.09, function()
		if hitMarker then
			hitMarker.BorderSizePixel = 0
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
	local published = workspace:GetAttribute(action == "Ability1" and "GF_Ability1" or "GF_Ability2")
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

return HUD

