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
-- Calibrated curve (2026-11-28, RANK_CALIBRATION_REPORT.md): power-law marginal cost
-- m(r) = 545 * r^0.58, independently validated to hit owner targets — median ordinary
-- player reaches rank 6 (Hard) at ~2.3h and rank 14 (Extreme) at ~8.4h, with early ranks
-- preserved fast (rank 4 inside the first hour) and no uniform scaling of the early curve.
-- Replaces the original spec formula 300*(r-1) + 55*r*(r-1) which saturated rank 14 at ~5h.
Economy.RankXp = { [1] = 0 }
do
	local acc = 0
	for r = 2, 30 do
		acc = acc + 545 * (r ^ 0.58)
		Economy.RankXp[r] = math.floor(acc + 0.5)
	end
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

