--!strict
-- Military requisitions catalog (GOAL §12). Permanent, nonexpiring. Two launch requisitions:
-- the free standard Frontline Arsenal and the premium Siege Division (1000 War Credits).
-- Unlock grants access, not items; entries are bought with standard Credits. Tiers open by
-- Credits spent inside that requisition: tier2 at 600, tier3 at 1600.
local Requisitions = {}

Requisitions.TIER_THRESHOLDS = { [2] = 600, [3] = 1600 }

Requisitions.List = {
	{
		id = "FrontlineArsenal",
		displayName = "Frontline Arsenal",
		premium = false,
		unlockWarCredits = 0,
		tiers = {
			[1] = {
				{ key = "sg04", kind = "weapon", id = "SG04" },
				{ key = "gf02", kind = "armor", id = "RECON" },
				{ key = "fieldkit", kind = "resource", cost = 150, displayName = "Field Kit: 3 Scrap + 2 Cells", grant = { scrap = 3, energyCells = 2 } },
			},
			[2] = {
				{ key = "mr07", kind = "weapon", id = "MR07" },
				{ key = "gf03", kind = "armor", id = "SIEGE" },
				{ key = "emp", kind = "grenade", id = "EMP" },
			},
			[3] = {
				{ key = "sentry", kind = "ability", id = "Sentry" },
				{ key = "orbital", kind = "ability", id = "OrbitalStrike" },
				{ key = "gf04", kind = "armor", id = "VANGUARD" },
				{ key = "resupply", kind = "resource", cost = 350, once = true, displayName = "Resupply: 8 Scrap + 4 Cells + 1 Tech", grant = { scrap = 8, energyCells = 4, militaryTechnology = 1 } },
			},
		},
	},
	{
		id = "SiegeDivision",
		displayName = "Siege Division",
		premium = true,
		unlockWarCredits = 1000,
		tiers = {
			[1] = {
				{ key = "gl22", kind = "weapon", id = "GL22", cost = 1200 },
				{ key = "gf05", kind = "armor", id = "TROPHY", cost = 500 },
			},
			[2] = {
				{ key = "gf06", kind = "armor", id = "BLACKSTAR", cost = 750 },
				{ key = "siegekit", kind = "resource", cost = 300, displayName = "Siege Kit: 6 Scrap + 3 Cells", grant = { scrap = 6, energyCells = 3 } },
			},
			[3] = {
				{ key = "rl09", kind = "weapon", id = "RL09", cost = 1500 },
				-- GOAL leaves the price unspecified; implemented as a free once-only claim and flagged in
				-- the ledger rather than inventing a number.
				{ key = "rarecache", kind = "cache", tier = "Rare", cost = 0, once = true, displayName = "Rare Cache (one-time)" },
			},
		},
	},
}

Requisitions.ById = {}
Requisitions.EntryByItem = {
	weapon = {},
	armor = {},
	ability = {},
	grenade = {},
}
for _, req in ipairs(Requisitions.List) do
	Requisitions.ById[req.id] = req
	for tier, entries in pairs(req.tiers) do
		for _, entry in ipairs(entries) do
			local byKind = Requisitions.EntryByItem[entry.kind]
			if byKind and type(entry.id) == "string" then
				byKind[entry.id] = { requisition = req, entry = entry, tier = tier }
			end
		end
	end
end

function Requisitions.get(id: string)
	return Requisitions.ById[id]
end

function Requisitions.entryForItem(kind: string, id: string)
	local byKind = Requisitions.EntryByItem[kind]
	return byKind and byKind[id] or nil
end

-- Every catalog entry across both requisitions, keyed by requisition then entry key.
function Requisitions.eachEntry(callback: (any, any, number) -> ())
	for _, req in ipairs(Requisitions.List) do
		for tier, entries in pairs(req.tiers) do
			for _, entry in ipairs(entries) do
				callback(req, entry, tier)
			end
		end
	end
end

-- Items that are premium-catalog exclusive: buying them anywhere requires Siege Division access.
Requisitions.PremiumItems = {
	weapon = { GL22 = true, RL09 = true },
	armor = { TROPHY = true, BLACKSTAR = true },
}

return Requisitions
