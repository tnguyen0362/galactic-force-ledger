# Salvage bonus and the failed-run debrief (build 439)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Fixed: my own payload edit had gone into the wrong branch
At build 438 I added `baseCredits`/`bonusCredits`/`carriedLost` to the settlement payload by anchoring on `objectiveComplete = objectiveComplete,`. That line exists **twice** — once in the late-join branch and once in the real payload — and the edit landed in the late-join one. Round numbers proved it: the 438 debrief showed `base 450` on a squad of one, where `base` should equal the total only by coincidence, and a failed run still read "Carried salvage secured".

Rewrote the actual payload block (lines 126–135) instead of text-matching it.

## Implemented
- Salvage bonus: `compute` now applies +25% to each resource at four players, floored per resource, and returns `bonusSalvage`.
- Debrief renders a `Salvage bonus` line when the payload carries one.

## Measured
Salvage bonus (60 scrap/cells/tech in the squad pool, `compute` called directly):

| Squad | scrap | cells | tech | bonus each |
|---|---|---|---|---|
| 1 | 40 | 40 | 40 | 0 |
| 4 | **50** | **50** | **50** | **10** |

(25% of 40 floors to 10.) Credits still 450 → 562.

Failed-run debrief, after destroying the generator and boarding the emergency dropship:

```
Credits  base 0  +  squad bonus 0
Military XP  base 0  +  squad bonus 0
Primary objective: INCOMPLETE
Extraction: FAILED
Carried salvage LOST
Military Rank: 15
```

Every branch of `S09-041` except the rank-up animation is now observed in a real settlement.

## Limits
- Four-player figures remain arithmetic; only one client exists, so nothing was paid out live.
- The `Salvage bonus` line was added after the solo run, so it has not been rendered — only the arithmetic behind it is measured.
- No XP rank-up animation.
- `S09-041`'s "secured/lost" wording is now correct in both directions, but the salvage total still prints 0 on a loss (it is zeroed before payout), which reads oddly next to "LOST".
