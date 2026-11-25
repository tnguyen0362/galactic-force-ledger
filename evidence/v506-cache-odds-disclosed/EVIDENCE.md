# Cache odds are now disclosed in the armory (place 506)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 506**.

## What was missing

The previous batch established there was **no odds display anywhere** — a keyword scan of every client script returned 81 hits, all of them
`string.format` calls. So `S11-027`, `S11-028` and `S11-029` were ABSENT despite the underlying weights being honest.

## Implemented

**Server** — `CacheService.oddsFor(tierId)` computes from the *same* weight table `rollRarity` consumes:

```lua
perDraw[rarity]     = w / total * 100
atLeastOne[rarity]  = (1 - (1 - p) ^ draws) * 100     -- draws = tier.augments
```

Returning `{tier, draws, perDraw, atLeastOne, sumPercent}` so the display cannot drift from the table that decides outcomes.

**State** — `ArmoryService.state.cacheOdds` supplies odds for the tier held in greatest quantity.

**UI** — a dedicated row under the action buttons rendering tier, draw count, per-draw percentages and the whole-cache Legendary rate.

## Measured

```
Rare x2  ·  Common 48.0% · Rare 43.0% · Epic 8.0% · Legendary 1.0%  ·  Legendary in this cache 2.0%
```

Checked against the config by hand: Rare weights are `48/43/8/1`, so per-draw shares are exactly 48/43/8/1%, and `1-(0.99)² = 1.99%`
displays as 2.0%. **The numbers shown are the numbers used.**

## A measurement error worth recording

My first verification reported `ODDS=0` and I nearly recorded the feature as broken. The scan searched for the substring `"ODDS"`, but the
live text begins `"Rare x2 · …"` — `"ODDS"` only appears in the *empty* state (`"ODDS  no cache held"`). The feature had worked on the first
attempt; my test was looking for the wrong string.

This is the third time this session a false negative came from a probe rather than the code, and the pattern is identical each time:
**the check encoded an assumption about the output format instead of the property being tested.** Searching for `"Legendary in this cache"`
— a substring that only the real display produces — found it immediately.

## Still open on these rows

- **Only the most-held tier is disclosed.** A player holding Common and Legendary sees whichever they have more of, not both.
- **Enemy drop chances are not shown** (0.01/0.04/0.07 by class), which matters as much as cache odds for expectation-setting.
- `S11-029` is met only in the narrow sense that this one display labels a probability rather than a guarantee; the broader "do not imply
  guarantees" audit across all UI (shop, pity, blueprint) is not done.
- Weights displayed are the **config** weights — which the earlier audit showed disagree with the authored per-difficulty table. So the
  disclosure is honest about a distribution that is itself off-spec.
