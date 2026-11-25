# v601 — kill XP feeds rank XP (S10-006/S10-025 resolution)

Spec reading: the 650-900 XP band is "expected earned XP including kills and optional". Kills already
accrued mastery XP (Rifleman/Scout/Marksman 10, Heavy 20, Officer 35, bosses 100/250) but that XP never
fed rank progression, so a successful solo mission paid exactly 600 - below the band floor forever.

Implementation: ExtractionService mastery settle now reports per-player totals to RewardsService.setKillXp;
grant() adds the amount to the rank XP award (annotated payload.killXp, inside the existing idempotent
settlement path so retries cannot double-pay).

`[GF_KXP] PASS kills=5 masteryGain=50 xpGain=650`
- 5 synthetic riflemen killed through the validated fire path: masteryGain exactly 50.
- Settlement paid exactly 650 XP = 600 base + 50 kill XP, precisely the spec band floor.
- Kills now differentiate mission payouts as the spec intends; a typical 10-15 kill mission lands
  700-750, inside 650-900. Rank6 in ~5 missions, rank14 in ~19-21 missions at that rate.
