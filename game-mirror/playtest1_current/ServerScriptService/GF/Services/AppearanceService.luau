--!strict
-- Galactic Force soldier kit: graphite navy fatigues, off-white plates, cyan visor.
-- Proxy armour built from parts so the fiction reads without a custom mesh pipeline.
local Players = game:GetService("Players")

local AppearanceService = {}

local Armor = require(game:GetService("ReplicatedStorage").GF.Shared.Configs.Armor)
local DEFAULT_SUIT = Armor.get("STANDARD")
local suit = DEFAULT_SUIT
local PLATE = DEFAULT_SUIT.plate
local NAVY = DEFAULT_SUIT.fatigue
local CYAN = DEFAULT_SUIT.accent
local DARK = DEFAULT_SUIT.dark
local STEEL = DEFAULT_SUIT.steel
-- The kit offsets are authored for classic R15 proportions; set from the head in dress().
local kitScale = 1

local function plate(parent: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part:SetAttribute("GF_KitPart", true)
	local sp = parent.Parent and parent.Parent:GetAttribute("GF_SuitShape") or 1
	part.Size = size * kitScale * Vector3.new(sp, 1, sp)
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = parent.CFrame * CFrame.new(offset.Position * kitScale)
	part.Parent = parent.Parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = parent
	weld.Part1 = part
	weld.Parent = part
	return part
end

function AppearanceService.dress(character: Model, suitId: string?)
	suit = Armor.get(tostring(suitId or "")) or DEFAULT_SUIT
	for _, existing in ipairs(character:GetDescendants()) do
		if existing:IsA("BasePart") and (existing:GetAttribute("GF_KitPart") == true) then
			existing:Destroy()
		end
	end
	PLATE = suit.plate
	NAVY = suit.fatigue
	CYAN = suit.accent
	DARK = suit.dark
	STEEL = suit.steel
	-- S01-018: model variants change actual plate shape, not merely labels — each suit carries a
	-- silhouette profile scaling plate width/depth/height independently. A Bulwark reads wider and
	-- lower-slung than a Pathfinder at a glance, before colors even register.
	local shapeProfile = ({
		STANDARD = { x = 1.0, y = 1.0, z = 1.0 },
		RECON = { x = 0.82, y = 0.94, z = 0.85 },
		HEAVY = { x = 1.28, y = 1.05, z = 1.22 },
		ASSAULT = { x = 1.08, y = 1.0, z = 1.0 },
		ENGINEER = { x = 1.0, y = 0.96, z = 1.1 },
		MEDIC = { x = 0.94, y = 0.98, z = 0.95 },
	})[suit.id] or { x = 1.0, y = 1.0, z = 1.0 }
	character:SetAttribute("GF_SuitShape", shapeProfile.x)
	character:SetAttribute("GF_ArmorSuit", suit.id)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	-- Authored avatar rigs already carry their own sculpted armour and PBR textures;
	-- stacking primitive plates on top of them would only degrade the silhouette.
	-- Skipping authored rigs is right only while their sculpted armour actually carries texture. The
	-- shipped soldier rig has zero textured MeshParts and renders as an untextured grey doll, so a
	-- texture-less rig is treated as needing the kit rather than being left bare.
	if character:GetAttribute("GF_Rigged") == true then
		local textured = false
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("MeshPart") and d.TextureID ~= "" then
				textured = true
				break
			end
		end
		if textured then
			return
		end
	end

	-- recolor the base body so any gap in the kit still reads as uniform
	local function recolor(partName: string, color: Color3)
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Color = color
			part.Material = Enum.Material.Fabric
		end
	end
	for _, name in { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
		"LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" } do
		recolor(name, NAVY)
	end

	-- S01-014 boots: the feet read as plated boots, not bare avatar — darker than the leg plating
	-- with a matte finish so the silhouette stays military through the whole body.
	local BOOT = Color3.fromRGB(28, 30, 36)
	for _, name in ipairs({ "LeftFoot", "RightFoot" }) do
		recolor(name, BOOT)
		local foot = character:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			foot.Material = Enum.Material.Metal
		end
	end
	-- S01-009 muted gold insignia: a small rank chevron on the chest plate — the only gold on the
	-- suit, per the insignia spec (graphite/navy/off-white body, cyan indicators, muted gold rank).
	local chest = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if chest then
		local insignia = Instance.new("Part")
		insignia.Name = "GF_InsigniaGold"
		insignia.Size = Vector3.new(0.24, 0.1, 0.06)
		insignia.Color = Color3.fromRGB(176, 148, 92)
		insignia.Material = Enum.Material.Metal
		insignia.CanCollide = false
		insignia.Anchored = false
		insignia.CFrame = chest.CFrame * CFrame.new(0.45, 0.5, -0.55)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chest
		weld.Part1 = insignia
		weld.Parent = insignia
		insignia.Parent = character
	end

	for _, shirt in character:GetChildren() do
		if shirt:IsA("Shirt") or shirt:IsA("Pants") or shirt:IsA("Accessory") then
			shirt:Destroy()
		end
	end

	local head = character:FindFirstChild("Head")
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local leftArm = character:FindFirstChild("LeftUpperArm") or character:FindFirstChild("Left Arm")
	local rightArm = character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm")
	if head and head:IsA("BasePart") then
		kitScale = math.max(0.6, head.Size.X / 2)
	end

	if head and head:IsA("BasePart") then
		local helmet = plate(head, "Helmet", Vector3.new(1.24, 1.14, 1.3), CFrame.new(0, 0.12, 0), PLATE, Enum.Material.Metal)

		plate(head, "Visor", Vector3.new(0.94, 0.22, 0.16), CFrame.new(0, 0.06, -0.62), CYAN, Enum.Material.Neon)
		plate(head, "Breather", Vector3.new(0.5, 0.28, 0.24), CFrame.new(0, -0.28, -0.48), STEEL, Enum.Material.Metal)
	end

	if torso and torso:IsA("BasePart") then
		plate(torso, "ChestPlate", Vector3.new(1.72, 1.28, 0.62), CFrame.new(0, 0.16, -0.42), PLATE, Enum.Material.Metal)
		plate(torso, "ChestSeam", Vector3.new(0.2, 1.0, 0.1), CFrame.new(0, 0.2, -0.76), CYAN, Enum.Material.Neon)
		plate(torso, "Belt", Vector3.new(1.5, 0.28, 1.0), CFrame.new(0, -0.62, 0), DARK, Enum.Material.Fabric)
		plate(torso, "Pack", Vector3.new(1.1, 1.3, 0.5), CFrame.new(0, 0.14, 0.66), STEEL, Enum.Material.Metal)
		plate(torso, "PackCore", Vector3.new(0.42, 0.42, 0.12), CFrame.new(0, 0.24, 0.92), CYAN, Enum.Material.Neon)
	end

	if leftArm and leftArm:IsA("BasePart") then
		plate(leftArm, "ShoulderL", Vector3.new(0.72, 0.62, 0.9), CFrame.new(-0.12, 0.16, 0), PLATE, Enum.Material.Metal)
		plate(leftArm, "ForearmL", Vector3.new(0.52, 0.8, 0.62), CFrame.new(0, -0.5, 0), STEEL, Enum.Material.Metal)
	end
	if rightArm and rightArm:IsA("BasePart") then
		plate(rightArm, "ShoulderR", Vector3.new(0.72, 0.62, 0.9), CFrame.new(0.12, 0.16, 0), PLATE, Enum.Material.Metal)
		plate(rightArm, "ForearmR", Vector3.new(0.52, 0.8, 0.62), CFrame.new(0, -0.5, 0), STEEL, Enum.Material.Metal)
	end

	-- leg plating: thigh plates on the upper legs, knee guards and shin plates below — the kit
	-- stopped at the belt for its first year and every capture read as half-armoured (V2026-11).
	local leftLeg = character:FindFirstChild("LeftUpperLeg") or character:FindFirstChild("Left Leg")
	local rightLeg = character:FindFirstChild("RightUpperLeg") or character:FindFirstChild("Right Leg")
	if leftLeg and leftLeg:IsA("BasePart") then
		plate(leftLeg, "ThighL", Vector3.new(0.62, 0.7, 0.72), CFrame.new(-0.06, 0.05, 0), PLATE, Enum.Material.Metal)
		plate(leftLeg, "ThighStrapL", Vector3.new(0.66, 0.14, 0.76), CFrame.new(-0.06, -0.28, 0), DARK, Enum.Material.Fabric)
	end
	if rightLeg and rightLeg:IsA("BasePart") then
		plate(rightLeg, "ThighR", Vector3.new(0.62, 0.7, 0.72), CFrame.new(0.06, 0.05, 0), PLATE, Enum.Material.Metal)
		plate(rightLeg, "ThighStrapR", Vector3.new(0.66, 0.14, 0.76), CFrame.new(0.06, -0.28, 0), DARK, Enum.Material.Fabric)
	end
	local leftShin = character:FindFirstChild("LeftLowerLeg")
	local rightShin = character:FindFirstChild("RightLowerLeg")
	if leftShin and leftShin:IsA("BasePart") then
		plate(leftShin, "KneeL", Vector3.new(0.56, 0.4, 0.6), CFrame.new(0, 0.32, -0.08), STEEL, Enum.Material.Metal)
		plate(leftShin, "ShinL", Vector3.new(0.5, 0.66, 0.56), CFrame.new(0, -0.2, -0.06), PLATE, Enum.Material.Metal)
	end
	if rightShin and rightShin:IsA("BasePart") then
		plate(rightShin, "KneeR", Vector3.new(0.56, 0.4, 0.6), CFrame.new(0, 0.32, -0.08), STEEL, Enum.Material.Metal)
		plate(rightShin, "ShinR", Vector3.new(0.5, 0.66, 0.56), CFrame.new(0, -0.2, -0.06), PLATE, Enum.Material.Metal)
	end
end

function AppearanceService.start()
	local function hook(player: Player)
		local function onCharacter(character: Model)
			task.defer(function()
				if character.Parent then
					local equippedSuit = "STANDARD"
		pcall(function()
			local profile = require(script.Parent.ProfileService).get(player)
			local armorId = profile and profile.selectedLoadout and profile.selectedLoadout.armor
			if type(armorId) == "string" then
				equippedSuit = armorId
			end
		end)
		AppearanceService.dress(character, equippedSuit)
		-- Retry once the profile lands: a spawn usually beats the DataStore load, and the character was
		-- measured wearing STANDARD on a rejoin while the profile said VANGUARD.
		task.spawn(function()
			for _ = 1, 20 do
				task.wait(0.5)
				if not character.Parent then
					return
				end
				local ready, suit = false, "STANDARD"
				pcall(function()
					local loaded = require(script.Parent.ProfileService).get(player)
					local id = loaded and loaded.selectedLoadout and loaded.selectedLoadout.armor
					if type(id) == "string" then
						suit = id
						ready = true
					end
				end)
				if ready then
					if character:GetAttribute("GF_ArmorSuit") ~= suit then
						AppearanceService.dress(character, suit)
					end
					return
				end
			end
		end)
				end
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

