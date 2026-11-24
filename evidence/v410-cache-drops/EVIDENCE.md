# Enemy cache drops, mission cap, boss exemption (build 410)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Added
- `CacheService.chanceFor(def)`: bosses 100%, `Officer` 7%, any `Elite` 4%, everything else 1% — matches the spec's infantry/heavy/commander/boss ladder.
- `CacheService.onEnemyKilled(model, killer)`: rolls the chance, respects a **per-mission cap of 3** that excludes bosses, opens a cache for the killer (or the first player), and increments `GF_CachesDropped`.
- `CacheService.onBossKilled(model)`: separate boss path, called from the Elimination tracker, because a boss killed by attribute was measured to complete the objective **without** the boss module's own death handler paying out.
- `CacheService.resetMission()`, called from `StationService.resetMission`, so the cap is per mission.
- `GF_CacheDropForce` test switch, `GF_CacheOpens` running counter, `GF_CacheLastSource`, `GF_CacheDropCapped`, `GF_BossCacheDropped`.
- Four more Legendary archetypes (SMG, LMG, Shotgun, Pistol) for one per category.

## Measured
| Check | Result |
|---|---|
| Kill 3 tagged hostiles with `GF_CacheDropForce` | `GF_CachesDropped = 3` |
| Kill a 4th hostile | drops stay 3, `GF_CacheDropCapped = true` |
| Kill the Bastion Walker | `GF_BossCacheDropped = "BastionWalker"`, `GF_CacheOpens` 0 → **2** (boss cache + guaranteed mission cache), last source `mission` |
| Legendary cache, 9 Legendary archetypes, 400 draws | Common 0 / Rare **29.5** / Epic 57.5 / Legendary 13.0 against spec 0/30/55/15 |

## Two instrumentation errors, both mine
1. **Drops appeared to be zero** on the first attempt: I had hooked `CombatService.damageEnemy`, which only runs for weapon kills, while the test set `Dead` directly. Moved the hook to `EnemyService.die` — the single funnel every hostile death passes through.
2. **The boss drop appeared missing** after it had actually fired: `GF_CacheOpened` records only the newest open, so the mission cache overwrote the boss cache one line later. Added `GF_CacheOpens` as a counter. This is the third time a single overwritten attribute produced a false negative; the counter is the fix.

## Limits
- Natural drop rates (1% / 4% / 7%) are configured but were **not** statistically measured; all drop tests used the force switch.
- The cap counts only non-boss drops and resets per mission — measured, but not across a full multi-mission session.
- Cache contents still go straight to the profile: no unopened inventory, no drop object in the world.
- Legendary share reads 13.0 vs 15.0 on 400 draws; that is within sampling noise, not proof of exact calibration.
