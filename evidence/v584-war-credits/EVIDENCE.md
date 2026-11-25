# place 584 — War Credits and first-mission Credits bonus

Before this change, `warCredits` did not exist anywhere in the codebase, and the one-time first-mission +200 Credits bonus (GOAL §10) was missing.

Changes:
- `RewardsService.grant`: on a successful extraction with the primary complete, awards fixed War Credits by difficulty (Easy 5 / Normal 10 / Hard 15 / Extreme 25). The award is inside the settle-once block, so a duplicate settlement cannot pay it twice. It is never multiplied by the full-squad bonus. The debrief payload now carries `warCredits`.
- `CacheService.grantMission`: the first unclaimed mission cache also grants the one-time +200 Credits (`GF_FirstMissionCredits`), alongside the existing guaranteed-Rare tag.

Probe:

```text
[GF] boot: config check PASS (688 assertions)
[GF_WC] PASS wcNormal=10 wcDup=0 fmCredits=200 fmFlag=true fmCredits2=0
```

Test currencies, flags, cache instances and settlement keys were restored afterward.
