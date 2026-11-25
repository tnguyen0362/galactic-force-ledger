# place 587 — premium weapon comparison

Controlled live server probe for `S12-015`. No game source or place data changed; synthetic Rifleman targets were created under `ActiveActors`, destroyed afterward, and the player/profile combat modifiers were restored before play stopped.

Probe output:

```text
[GF] boot: config check PASS (689 assertions)
[GF_PW] PASS ar=18 mr=7 lmg=19 gl=4/r0 rl=2/r1 glCluster=3/251.8 rlCluster=3/425.5 load=2200/1640/3528/5100
[GF_PW_DONE]
```

## Measurement

Target: synthetic Rifleman, 240 Health + 80 Shield, armor factor 1, no weak-point bonus. Spread and equipped augments were disabled for repeatability.

Single-target live shots to kill:

| weapon | live shots | reloads required | nominal time model |
|---|---:|---:|---:|
| AR-01 | 18 | 0 | 1.70 s |
| MR-07 | 7 | 0 | 2.40 s |
| LMG-12 | 19 | 0 | 1.64 s |
| GL-22 | 4 | 0 | 3.60 s |
| RL-09 | 2 | 1 | about 3.40 s (reload-gated) |

The time model combines measured live shots with the authored rpm/reload values; the probe intentionally bypassed rate waiting to keep the run short, so these are controlled comparisons rather than wall-clock human aim tests.

Area performance measured live:

- GL-22 one shot hit all 3 clustered targets for **251.8 total shield/health reduction**.
- RL-09 one shot hit all 3 clustered targets for **425.5 total shield/health reduction**.

Full ammunition-load single-target damage capacity from the same live-verified config rows:

| weapon | ammunition | nominal damage/load |
|---|---:|---:|
| GL-22 | 4+16 | **2200** |
| RL-09 | 1+7 | **1640** |
| AR-01 | 28+168 | **3528** |
| LMG-12 | 75+225 | **5100** |

## Interpretation

The premium launchers are sidegrades rather than a strict combat ceiling: they have high burst and genuine multi-target value, but low magazines/reserves and much lower total damage per ammunition load than standard sustained primaries. RL-09's one-round magazine forced a reload even for a single Rifleman kill. This satisfies the lower-ammo/situational-use comparison at prototype level; it does not measure human aim, target movement, or full mission economy.
