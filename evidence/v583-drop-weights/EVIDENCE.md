# place 583 — enemy-drop weight scaling and first-mission Rare guarantee

GOAL §11 L181: for enemy drops on non-Normal difficulties, non-Common rarity weights scale by Easy .65 / Hard 1.35 / Extreme 1.7 before renormalization, boss drops never roll Common, and the first mission keeps a Rare guarantee.

Before this change, drop caches rolled at the tier's unmodified weights, the instance did not record which difficulty it dropped on, and nothing guaranteed a first-mission Rare.

Changes in `CacheService`:
- `scaledWeights(tierId, difficulty, boss)` applies the difficulty factor to non-Common weights and zeroes Common for boss drops.
- Enemy-drop cache instances record `difficulty` (and `boss`); opening one uses the scaled weights. Mission/shop/manual caches are unaffected.
- `grantMission` tags the first unclaimed mission cache with `guaranteedRare`, sets `profile.firstMissionBonusClaimed`, and the open path upgrades the draw so at least one item is Rare or better.

Probe: three controlled cache instances (Hard Rifleman drop, Bastion Walker boss drop, first-mission grant) opened on a real server. All test artifacts (caches, journals, granted items) were removed afterward.

```text
[GF] boot: config check PASS (688 assertions)
[GF_DROPS] PASS scale=true bossZero=true diffRec=true fmFlag=true fmRare=true bossNoCommon=true rifleJournal=true
[GF_DROPS_DONE] removed=6
```

Not verified: Monte Carlo distribution of the scaled tables; the GOAL note "additionally high-tier odds weight Epic/Legendary relative to Rare" has no numeric factor specified in the source and was not implemented.
