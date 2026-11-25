# Odds disclosure completed: every held tier and the enemy drop chances (place 507)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 507**.

## What was left over from place 506

The first odds display disclosed only the **most-held** tier and said nothing about enemy drop chances — both listed as gaps in that
batch's evidence.

## Change

- `CacheService.oddsFor` now also returns `dropChance`, read from the **same** `tier.enemyChance` table `onEnemyKilled` rolls against.
- `ArmoryService.state.cacheOdds` returns a **list** of every held tier (sorted most-held first), each carrying its held count — instead of
  a single entry.
- The UI renders all tiers on one line and adds a second line for the drop chances of the leading tier.

## Measured

```
Rare x2 held 13  ·  Common 48.0% · Rare 43.0% · Epic 8.0% · Legendary 1.0%  ·  Leg 2.0%
  ||  Common x1 held 1  ·  Common 82.0% · Rare 16.0% · Epic 1.9% · Legendary 0.1%  ·  Leg 0.1%

DROP Rare  ·  infantry 1% · heavy 5% · commander 9%
```

Every number checks against config by hand:

| shown | config | ✓ |
|---|---|---|
| Rare 48/43/8/1 % | `weights 48/43/8/1` | ✓ |
| Common 82/16/1.9/0.1 % | `weights 82/16/1.9/0.1` | ✓ |
| Leg 2.0% on 2 draws | `1-(0.99)² = 1.99%` | ✓ |
| Leg 0.1% on 1 draw | `1-(0.999)¹ = 0.1%` | ✓ |
| infant 1% / heavy 5% / commander 9% | `Rare.enemyChance 0.01/0.05/0.09` | ✓ |

Both held tiers appear, most-held first, and the drop line names the tier it belongs to.

## Where this still falls short of the spec

- **The whole-cache figure is computed per *tier* draw count, not per actual cache contents.** A `Rare x2` cache rolls two augments from a
  shared pool *without* replacement across opens — so the true per-cache probability depends on what the player already owns, which this
  display ignores. It reads a `1-(1-p)^n` with replacement. That is the standard reading of "whole-cache odds" but it is an approximation,
  and the spec's wording (*"true per-draw and whole-cache odds"*) arguably asks for the exact conditional figure.
- **Disclosed weights remain the config's**, which disagree with the authored per-difficulty table — so the display is honest about numbers
  that are themselves off-spec.
- The drop line shows only the leading tier's chances; a player holding two tiers sees drop percentages for one of them.
- No UI test of the line at narrow resolutions; the odds line is long and may clip on small screens.

## Method note

Verification scanned for `"Leg "` and `"DROP "` — substrings that **only** the real display produces. After three false negatives earlier this
session from scans that matched placeholder text (`"ODDS"`), matching on content unique to the live output is now the default.
