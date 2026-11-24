# Debrief breakdown + full-squad bonus (build 438)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Two gaps
1. `S09-041` wants the debrief to show success/failure, primary, extraction, **base vs bonus** and secured/lost. The payload carried only totals, and the panel printed two lines.
2. `S09-037` wants a **+25% full-squad bonus** on credits and XP. `RewardsService` had no such bonus at all — the multiplier did not exist.

## Implemented
- `RewardsService.compute(difficulty, success, objectiveComplete, squadSize)` now returns `baseCredits`, `baseXp`, `bonusCredits`, `bonusXp`, `fullSquad` beside the totals. The bonus is 25% at four or more players, floored.
- The `MissionComplete` payload carries those fields plus `carriedLost` (from `GF_CarriedLost`).
- `MissionHUD` debrief renders the split, the primary result, the extraction result and whether carried salvage was secured or lost; the duplicate "Credits secured" line was removed.

## Measured
Pure maths, called directly on the server:

| Squad | Base credits | Bonus | Total | Base XP | Bonus XP | Total |
|---|---|---|---|---|---|---|
| 1 | 450 | 0 | 450 | 600 | 0 | 600 |
| 4 | 450 | **112** | 562 | 600 | **150** | 750 |

25% of 450 floors to 112; 25% of 600 is 150 — both correct.

In-game debrief after a real solo extraction:

```
Credits  base 450  +  squad bonus 0
Military XP  base 600  +  squad bonus 0
Primary objective: COMPLETE
Extraction: SUCCESSFUL
Carried salvage secured
Salvage: 0 scrap · 0 energy cells · 0 tech
Military Rank: 15
```

## Limits
- **The bonus has never paid out.** Only one client can exist here, so the four-player path is arithmetic, not a live settlement.
- `carriedLost` was only seen as `false` (successful run); the "Carried salvage LOST" branch has not rendered.
- Salvage is not multiplied — the spec asks for a bonus on credits/XP and *integer salvage resources*, and the salvage half is not implemented.
- No XP rank-up animation was added; the row still lists that as unmet.
