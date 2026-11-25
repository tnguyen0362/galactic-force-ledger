# place 572 — once-per-mission payout settlement

`RewardsService.grant` now records `profile.settledMissions[missionId]` (pruned to 30) before paying and returns `duplicate=true` with zero payout on a repeat settlement for the same mission id.

A temporary real-server probe opened ledger mission `settle-test` and called `Rewards.grant` twice for the same player. It then restored credits/XP and removed the settlement key.

```text
[GF] boot: config check PASS (688 assertions)
[GF] payout ROBLOXISUS101 difficulty=Normal success=true objective=true credits=450 xp=600
[GF_SETTLETEST] PASS mission=m1-1795591987-settle-test first=+450 second=+0 duplicate=true
[GF_SETTLECLEAN] restored credits=1350
```

Not yet verified: settlement surviving a server crash mid-payout (the key and credits share one profile save), and pending-recovery debrief.
