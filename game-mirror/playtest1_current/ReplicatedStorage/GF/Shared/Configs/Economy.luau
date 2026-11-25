--!strict
local Economy = {}

-- Payouts for a completed standard operation, before difficulty multiplier.
Economy.BasePayout = { credits = 450, xp = 600 }
Economy.LootPerStandardMission = { scrap = 12, energyCells = 4, militaryTechnology = 1 }

Economy.PayoutByDifficulty = {
	Easy = { credits = 250, xp = 330 },
	Normal = { credits = 450, xp = 600 },
	Hard = { credits = 700, xp = 950 },
	Extreme = { credits = 950, xp = 1350 },
}

-- Rank thresholds. Rank gates access; it does not inflate player power.
-- Spec formula (S10-004): XPthreshold(r) = 300*(r-1) + 55*r*(r-1); rank6 = 3150, rank14 = 13910.
Economy.RankXp = { [1] = 0 }
for r = 2, 30 do
	Economy.RankXp[r] = 300 * (r - 1) + 55 * r * (r - 1)
end

Economy.MaxRank = 30

Economy.Grenades = {
	{ id = "Frag", displayName = "Frag Grenade", unlockRank = 1, cost = 0, damage = 135, radius = 15, count = 3 },
	{ id = "EMP", displayName = "EMP Grenade", unlockRank = 4, cost = 550, damage = 15, radius = 13, count = 3, shieldDamage = 90 },
}

Economy.ServiceCommendation = { assistsPerMilestone = 5, creditsPerMilestone = 150 }

function Economy.payout(difficultyId: string, objectiveCompleted: boolean)
	local base = Economy.PayoutByDifficulty[difficultyId] or Economy.PayoutByDifficulty.Normal
	if not objectiveCompleted then
		return { credits = 0, xp = 0 }
	end
	return { credits = base.credits, xp = base.xp }
end

function Economy.rankForXp(xp: number): number
	local rank = 1
	for r = 1, 30 do
		local need = Economy.RankXp[r]
		if need and xp >= need then rank = r else break end
	end
	return rank
end

return Economy

