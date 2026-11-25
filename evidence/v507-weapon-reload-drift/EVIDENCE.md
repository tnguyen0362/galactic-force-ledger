# Weapon stats conform except reload — which is systematically longer (place 507)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level config vs the authored weapon table. No place changes.

## Two misreadings I caught before reporting them

1. I first read the authored table's last column as **unlock rank** — it is **reload seconds**. AR-01 carries rank 1 in config but shows `2` in the
   table, and its reload is 2.1 s. Reading it as rank would have produced five false "rank drift" findings.
2. I then suspected GL-22 of a large drift (`110` damage vs an authored `40`). The `40 | 1 | 1/8 | 2` row belongs to a *different* launcher. GL-22 is
   `110 | 50 | 4/16` in the spec and the config says damage 110, rpm 50, mag 4/16 — an exact match.

## What conforms

| weapon | spec dmg / rpm / mag/reserve | config | |
|---|---|---|---|
| AR-01 | 18 / 600 / 28/168 | 18 / 600 / 28/168 | ✓ |
| SMG-03 | 13 / 850 / 36/216 | 13 / 850 / 36/216 | ✓ |
| LMG-12 | 17 / 660 / 75/225 | 17 / 660 / 75/225 | ✓ |
| SG-04 | 12/pellet (8) / 72 / 6/42 | 96 total / 72 / 6/42 | ✓ |
| MR-07 | 51 / 150 / 12/72 | 51 / 150 / 12/72 | ✓ |
| GL-22 | 110 / 50 / 4/16 | 110 / 50 / 4/16 | ✓ |
| P-01 | 22 / 300 / 12/72 | 22 / 300 / 12/72 | ✓ |

Every ballistic stat matches, and SG-04's 96 is exactly 8 pellets × 12.

## What does not: reload times

| weapon | authored reload | config `reloadTime` | delta |
|---|---|---|---|
| AR-01 | 2 s | **2.1** | +0.1 |
| MR-07 | 2 s | **2.4** | +0.4 |
| SMG-03 | 1 s | **1.7** | **+0.7** |
| LMG-12 | 3 s | **3.7** | **+0.7** |
| SG-04 | 2 s | **2.8** | **+0.8** |

**Every one is longer, never shorter**, by 0.1–0.8 s. That is not a transcription slip — a slip would scatter in both directions. A uniform upward
bias across all five is a deliberate tuning choice standing in for the authored table, the same signature as the cache weight tables.

Consequence: sustained DPS is lower than authored for every weapon, and disproportionately for SMG-03 and SG-04 — the two classes whose identity
is close-quarters throughput. SMG-03 authored reload is 1 s, the single fastest in the game; at 1.7 s its "close mobility" identity is
half-eroded.

## Not changed

Reload is a core combat feel parameter and interacts with the `reloadSpeed` augment stat (which is live and verified). Same owner queue.

## Confidence

High on the comparisons — printouts on both sides, and the two misreadings above are exactly why the column meanings were checked twice. Not
measured: actual reload duration in play, which would need timing a live reload rather than reading config.
