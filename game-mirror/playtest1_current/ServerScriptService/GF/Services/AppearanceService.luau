--!strict
-- Galactic Force player kit: open-face SEAL-style operator gear on a normalised R15 body.
--  1. normalizeBody(): every player is reset to the default blocky R15 (their face, skin and body colours are kept),
--     so bundle helmets / dynamic heads / odd proportions never fight the armour and the face is always visible.
--  2. dress(): clones the per-limb kit meshes from ServerStorage.GF.Art.PlayerKit (built from the Blender asset by
--     tools/art/player/install_player_kit.luau), scales them by limb.Size / reference size, welds them to the limbs
--     and tints them by suit. Colour groups: carrier, pouch, hardware, helmet, glove, boot.
-- MeshPart.MeshId cannot be set from a server script, so dress() only clones template MeshParts.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local AppearanceService = {}

local Armor = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Armor)
local DEFAULT_SUIT = Armor.get("STANDARD")

-- Armor ids are uppercase canon, but the legacy fresh-profile default was the title-case
-- string "Standard". Treat input as case-insensitive here rather than letting every new
-- soldier bounce back to STANDARD while the retry loop compares unlike strings.
local function canonicalSuitId(suitId: string?): string
	local raw = tostring(suitId or "")
	if raw == "" then
		return "STANDARD"
	end
	return string.upper(raw)
end

local function suitFor(suitId: string?)
	return Armor.get(canonicalSuitId(suitId)) or DEFAULT_SUIT
end

-- Whole-body scale applied after the reset. Classic R15 is ~5.3 studs; the old avatar bundle stood ~6.9, and
-- hit volumes / camera / cover heights were tuned for that, so keep the same presence.
local PLAYER_SCALE = 1.28
local DEFAULT_FACE = 144080495

-- SEAL-style base palette (coyote carrier, ranger-green pouches, gunmetal hardware, tan helmet shell).
local PALETTE = {
	carrier = Color3.fromRGB(108, 90, 63),
	pouch = Color3.fromRGB(54, 62, 44),
	hardware = Color3.fromRGB(26, 27, 30),
	helmet = Color3.fromRGB(122, 104, 76),
	glove = Color3.fromRGB(28, 28, 31),
	boot = Color3.fromRGB(40, 33, 26),
	fatigue = Color3.fromRGB(72, 78, 57),
}
local MATERIAL = {
	carrier = Enum.Material.Fabric,
	pouch = Enum.Material.Fabric,
	hardware = Enum.Material.SmoothPlastic,
	helmet = Enum.Material.Plastic,
	glove = Enum.Material.Fabric,
	boot = Enum.Material.Fabric,
}
-- S01-018: suit variants still change the silhouette (torso width/depth) and nudge the colours toward the suit.
local SHAPE = {
	STANDARD = { x = 1.0, z = 1.0 },
	RECON = { x = 0.9, z = 0.92 },
	SIEGE = { x = 1.14, z = 1.12 },
	VANGUARD = { x = 1.04, z = 1.04 },
	TROPHY = { x = 1.0, z = 1.0 },
	BLACKSTAR = { x = 1.0, z = 1.0 },
}
-- how far each group is pulled toward the suit palette (carrier/helmet toward plate; pouch/fatigue toward fatigue)
local TINT = { carrier = 0.32, helmet = 0.32, pouch = 0.45, fatigue = 0.5 }

local LIMB_PART: { [string]: string } = {
	Head = "Head", UpperTorso = "UpperTorso", LowerTorso = "LowerTorso",
	UpperArmR = "RightUpperArm", LowerArmR = "RightLowerArm", HandR = "RightHand",
	UpperArmL = "LeftUpperArm", LowerArmL = "LeftLowerArm", HandL = "LeftHand",
	UpperLegR = "RightUpperLeg", LowerLegR = "RightLowerLeg", FootR = "RightFoot",
	UpperLegL = "LeftUpperLeg", LowerLegL = "LeftLowerLeg", FootL = "LeftFoot",
}

local function kitFolder(): Folder?
	local gf = ServerStorage:FindFirstChild("GF")
	local art = gf and gf:FindFirstChild("Art")
	local f = art and art:FindFirstChild("PlayerKit")
	return if f and f:IsA("Folder") then f else nil
end

-- Reset a character to the default R15 body keeping the player's face, skin tones and body colours.
function AppearanceService.normalizeBody(player: Player, character: Model): boolean
	if character:GetAttribute("GF_BodyNormalized") == true then
		return true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return false
	end
	-- StarterPlayer.StarterCharacter is already a default blocky R15 (GF_DefaultR15): nothing to swap, just scale.
	if character:GetAttribute("GF_DefaultR15") == true then
		pcall(function()
			character:ScaleTo(PLAYER_SCALE)
		end)
		character:SetAttribute("GF_BodyNormalized", true)
		return true
	end
	local desc = Instance.new("HumanoidDescription")
	local okSrc, src = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if okSrc and src then
		local s = src :: HumanoidDescription
		desc.HeadColor = s.HeadColor
		desc.TorsoColor = s.TorsoColor
		desc.LeftArmColor = s.LeftArmColor
		desc.RightArmColor = s.RightArmColor
		desc.LeftLegColor = s.LeftLegColor
		desc.RightLegColor = s.RightLegColor
		desc.Face = if s.Face ~= 0 then s.Face else DEFAULT_FACE
	else
		desc.Face = DEFAULT_FACE
	end
	-- part ids, clothing and accessories stay 0 (default blocky R15); scales stay neutral
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	desc.HeightScale = 1
	desc.WidthScale = 1
	desc.DepthScale = 1
	desc.HeadScale = 1
	local ok, err = pcall(function()
		humanoid:ApplyDescription(desc)
	end)
	desc:Destroy()
	if not ok then
		warn("[AppearanceService] normalizeBody failed: " .. tostring(err))
		return false
	end
	if character.Parent then
		pcall(function()
			character:ScaleTo(PLAYER_SCALE)
		end)
		character:SetAttribute("GF_BodyNormalized", true)
	end
	return character.Parent ~= nil
end

local function recolor(character: Model, partName: string, color: Color3, material: Enum.Material)
	local part = character:FindFirstChild(partName)
	if part and part:IsA("BasePart") then
		part.Color = color
		part.Material = material
	end
end

function AppearanceService.dress(character: Model, suitId: string?)
	local suit = suitFor(suitId)
	for _, existing in ipairs(character:GetDescendants()) do
		if existing:IsA("BasePart") and (existing:GetAttribute("GF_KitPart") == true) then
			existing:Destroy()
		end
	end
	local oldInsignia = character:FindFirstChild("GF_InsigniaGold")
	if oldInsignia then
		oldInsignia:Destroy()
	end
	local shape = (SHAPE :: any)[suit.id] or SHAPE.STANDARD
	character:SetAttribute("GF_SuitShape", shape.x)
	character:SetAttribute("GF_ArmorSuit", suit.id)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	-- Authored avatar rigs carry their own sculpted armour and PBR textures; leave textured ones alone.
	if character:GetAttribute("GF_Rigged") == true then
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("MeshPart") and d.TextureID ~= "" then
				return
			end
		end
	end

	for _, child in character:GetChildren() do
		if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") or child:IsA("Accessory") then
			child:Destroy()
		end
	end

	-- suit colours: the SEAL palette nudged toward the suit's own plate/fatigue colours
	local color = {} :: { [string]: Color3 }
	for group, base in PALETTE do
		local toward = if group == "carrier" or group == "helmet" then suit.plate else suit.fatigue
		color[group] = base:Lerp(toward, TINT[group] or 0)
	end
	color.hardware = PALETTE.hardware
	color.glove = PALETTE.glove
	color.boot = PALETTE.boot

	-- the base limbs show through the gaps: combat-shirt fabric on the body, glove/boot colour on hands/feet.
	-- Head keeps the player's own skin tone and face.
	for _, name in { "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
		"LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" } do
		recolor(character, name, color.fatigue, Enum.Material.Fabric)
	end
	for _, name in { "LeftHand", "RightHand" } do
		recolor(character, name, color.glove, Enum.Material.Fabric)
	end
	for _, name in { "LeftFoot", "RightFoot" } do
		recolor(character, name, color.boot, Enum.Material.Fabric)
	end

	local folder = kitFolder()
	if not folder then
		warn("[AppearanceService] ServerStorage.GF.Art.PlayerKit missing - run tools/art/player/install_player_kit.luau")
		return
	end
	for _, tmpl in folder:GetChildren() do
		if not tmpl:IsA("MeshPart") then
			continue
		end
		local limb = tmpl:GetAttribute("GF_Limb")
		local side = tmpl:GetAttribute("GF_Side")
		if type(limb) ~= "string" or type(side) ~= "string" then
			continue
		end
		local partName = LIMB_PART[limb .. side]
		local target = partName and character:FindFirstChild(partName)
		local ref = folder:GetAttribute("Ref_" .. limb)
		if not (target and target:IsA("BasePart") and typeof(ref) == "Vector3") then
			continue
		end
		if math.abs(ref.X) < 0.0001 or math.abs(ref.Y) < 0.0001 or math.abs(ref.Z) < 0.0001 then
			continue
		end
		local ratio = Vector3.new(target.Size.X / ref.X, target.Size.Y / ref.Y, target.Size.Z / ref.Z)
		if limb == "UpperTorso" or limb == "LowerTorso" then
			ratio = ratio * Vector3.new(shape.x, 1, shape.z)
		end
		local center = tmpl:GetAttribute("GF_Center")
		if typeof(center) ~= "Vector3" then
			continue
		end
		local group = tmpl:GetAttribute("GF_Group")
		if type(group) ~= "string" then
			group = "carrier"
		end
		local part = tmpl:Clone()
		part.Name = tmpl.Name
		part:SetAttribute("GF_KitPart", true)
		part:SetAttribute("GF_KitTemplate", nil)
		part.Size = tmpl.Size * ratio
		-- Roblox's glTF import arrives rotated 180deg about Y (same fix as the hero rigs)
		part.CFrame = target.CFrame * CFrame.new(center * ratio) * CFrame.Angles(0, math.pi, 0)
		part.Color = color[group] or PALETTE.carrier
		part.Material = MATERIAL[group] or Enum.Material.Fabric
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Parent = character
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = target
		weld.Part1 = part
		weld.Parent = part
	end

	-- S01-009 muted gold rank chevron on the front carrier plate: the only gold on the kit.
	local chest = character:FindFirstChild("UpperTorso")
	if chest and chest:IsA("BasePart") then
		local k = chest.Size.X / 2.0
		local chevron = Instance.new("Part")
		chevron.Name = "GF_InsigniaGold"
		chevron:SetAttribute("GF_KitPart", true)
		chevron.Size = Vector3.new(0.3, 0.12, 0.05) * k
		chevron.Color = Color3.fromRGB(176, 148, 92)
		chevron.Material = Enum.Material.Metal
		chevron.CanCollide = false
		chevron.CanQuery = false
		chevron.CanTouch = false
		chevron.Massless = true
		chevron.CFrame = chest.CFrame * CFrame.new(-0.5 * k * shape.x, 0.5 * k, -0.74 * k * shape.z)
		chevron.Parent = character
		local w = Instance.new("WeldConstraint")
		w.Part0 = chest
		w.Part1 = chevron
		w.Parent = chevron
	end
end

local function equippedSuit(player: Player): (boolean, string)
	local ready, suitId = false, "STANDARD"
	pcall(function()
		local profile = require(script.Parent.ProfileService).get(player)
		local armorId = profile and profile.selectedLoadout and profile.selectedLoadout.armor
		if type(armorId) == "string" then
			suitId = canonicalSuitId(armorId)
			ready = true
		end
	end)
	return ready, suitId
end

local appearanceStarted = false

function AppearanceService.start()
	if appearanceStarted then
		return
	end
	appearanceStarted = true
	-- AppearanceService is one of the few player-facing services started by both the lobby boot
	-- branch and the legacy shared-place boot. Use that reliable boot point to bring the dialogue
	-- service online; DialogueService itself is idempotent and guards lobby-only ambience by the
	-- physical station/zone state.
	pcall(function()
		require(script.Parent.DialogueService).start()
	end)
	local function hook(player: Player)
		local function onCharacter(character: Model)
			task.defer(function()
				if not character.Parent then
					return
				end
				-- normalise first: ApplyDescription swaps the limb parts, which would orphan any welds made earlier
				AppearanceService.normalizeBody(player, character)
				if not character.Parent then
					return
				end
				local _, suitId = equippedSuit(player)
				AppearanceService.dress(character, suitId)
				-- Retry once the profile lands: a spawn usually beats the DataStore load, and the character was
				-- measured wearing STANDARD on a rejoin while the profile said VANGUARD.
				task.spawn(function()
					for _ = 1, 20 do
						task.wait(0.5)
						if not character.Parent then
							return
						end
						local ready, suitNow = equippedSuit(player)
						if ready then
							if character:GetAttribute("GF_ArmorSuit") ~= suitNow then
								AppearanceService.dress(character, suitNow)
							end
							return
						end
					end
				end)
			end)
		end
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			onCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
end

return AppearanceService
