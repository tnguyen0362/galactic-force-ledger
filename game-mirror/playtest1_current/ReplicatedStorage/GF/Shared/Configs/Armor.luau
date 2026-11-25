--!nonstrict
-- Six wearable kits: four standard, two requisition. Cosmetic palettes rather than meshes, which the
-- milestone explicitly allows; every suit is a complete recolour of the same plate layout so the
-- silhouette stays readable.
local Armor = {}

Armor.List = {
	{
		id = "STANDARD", displayName = "GF-01 Line Infantry", tier = "Standard", unlockRank = 1, cost = 0,
		plate = Color3.fromRGB(222, 222, 214), fatigue = Color3.fromRGB(38, 44, 58),
		accent = Color3.fromRGB(96, 200, 255), dark = Color3.fromRGB(26, 30, 40),
		steel = Color3.fromRGB(86, 94, 108),
	},
	{
		id = "RECON", displayName = "GF-02 Pathfinder", tier = "Standard", unlockRank = 3, cost = 500,
		plate = Color3.fromRGB(176, 190, 172), fatigue = Color3.fromRGB(44, 52, 42),
		accent = Color3.fromRGB(150, 235, 160), dark = Color3.fromRGB(28, 34, 28),
		steel = Color3.fromRGB(96, 108, 96),
	},
	{
		id = "SIEGE", displayName = "GF-03 Bulwark", tier = "Standard", unlockRank = 5, cost = 850,
		plate = Color3.fromRGB(206, 190, 158), fatigue = Color3.fromRGB(56, 46, 38),
		accent = Color3.fromRGB(255, 170, 90), dark = Color3.fromRGB(34, 28, 24),
		steel = Color3.fromRGB(120, 104, 84),
	},
	{
		id = "VANGUARD", displayName = "GF-04 Vanguard", tier = "Standard", unlockRank = 8, cost = 1200,
		plate = Color3.fromRGB(198, 206, 224), fatigue = Color3.fromRGB(30, 38, 62),
		accent = Color3.fromRGB(120, 160, 255), dark = Color3.fromRGB(22, 26, 42),
		steel = Color3.fromRGB(92, 104, 132),
	},
	{
		id = "TROPHY", displayName = "GF-05 Ash Sentinel", tier = "Requisition", unlockRank = 12, cost = 500,
		plate = Color3.fromRGB(112, 104, 96), fatigue = Color3.fromRGB(35, 34, 32),
		accent = Color3.fromRGB(255, 112, 72), dark = Color3.fromRGB(20, 18, 16),
		steel = Color3.fromRGB(90, 82, 76),
	},
	{
		id = "BLACKSTAR", displayName = "GF-06 Frost Warden", tier = "Requisition", unlockRank = 16, cost = 750,
		plate = Color3.fromRGB(178, 208, 220), fatigue = Color3.fromRGB(28, 44, 58),
		accent = Color3.fromRGB(116, 224, 255), dark = Color3.fromRGB(12, 20, 28),
		steel = Color3.fromRGB(112, 142, 156),
	},
}

Armor.ById = {}
for _, suit in Armor.List do
	Armor.ById[suit.id] = suit
end

function Armor.get(id: string)
	return Armor.ById[id]
end

return Armor

