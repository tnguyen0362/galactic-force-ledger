--!strict
-- Soft classes: one personal + one squad passive. Weapons are NOT class-locked.
local Classes = {}

Classes.List = {
	{
		id = "Assault", displayName = "Assault",
		personal = { stat = "ReloadSpeed", value = 0.10 },
		team = { stat = "ReloadSpeed", value = 0.05 },
		suggested = { primary = "AR01", ability = "Airstrike" },
	},
	{
		id = "Heavy", displayName = "Heavy",
		personal = { stat = "MaxShield", value = 0.15 },
		team = { stat = "MaxShield", value = 0.05 },
		suggested = { primary = "LMG12", ability = "DomeShield" },
	},
	{
		id = "Recon", displayName = "Recon",
		personal = { stat = "DodgeRecharge", value = 0.15 },
		team = { stat = "MoveSpeed", value = 0.05 },
		suggested = { primary = "MR07", ability = "Airstrike" },
	},
	{
		id = "Support", displayName = "Support",
		personal = { stat = "ReviveSpeed", value = 0.20 },
		team = { stat = "HealthRegen", value = 0.10 },
		suggested = { primary = "AR01", ability = "Sentry" },
	},
}

-- Hard cap on stacked modifiers so squads cannot exploit speed/reload.
-- Spec caps: movement/reload rate modifiers cap at +25% including Augments; shield capacity cap +25%.
Classes.ModifierCaps = {
	ReloadSpeed = 0.25,
	MoveSpeed = 0.25,
	MaxShield = 0.25,
	HealthRegen = 0.25,
	ReviveSpeed = 0.35,
	DodgeRecharge = 0.30,
}

Classes.ById = {}
for _, c in Classes.List do Classes.ById[c.id] = c end

function Classes.get(id: string)
	return Classes.ById[id]
end

return Classes

