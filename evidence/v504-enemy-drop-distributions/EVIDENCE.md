# Enemy drops: chance exists, per-source distributions and difficulty scaling do not (place 504)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level inspection. No place changes.

## What exists

`Configs/Caches` gives each **tier** a drop chance per enemy class and one rarity weight table:

```
Common    enemyChance { infantry 0.01, heavy 0.04, commander 0.07 }
Rare      enemyChance { infantry 0.01, heavy 0.05, commander 0.09 }
Epic      enemyChance { infantry 0.00, heavy 0.02, commander 0.05 }
Legendary enemyChance { infantry 0.00, heavy 0.00, commander 0.00 }
```

So an enemy decides *whether* to drop by class, and the resulting cache tier supplies the rarity weights.

## What the spec asks for

The authored table specifies a **distribution per enemy class** — Normal infantry `85/14/1/0`, elite `55/35/9/1`, Walker `0/70/28/2`,
Veyr `0/40/50/10` — plus a difficulty adjustment to the weights: *"For enemy drops on other difficulties, multiply non-Common weights by
Easy .65, Hard 1.35, Extreme 1.7 and renormalize (boss never Common...)"*.

None of those per-class distributions exist: every enemy drop resolves through the same tier table, so an infantryman and a commander
produce identical rarity odds once a cache drops. What differs is only the chance of dropping at all.

**`S11-020` (difficulty multipliers) is not implemented anywhere** — the tier weight tables are static, and no code path scales or
renormalises them by difficulty. **`S11-021` (keep first-mission Rare guarantee) is likewise absent**: a search for
`firstMission`/`first_mission`/`guarantee` finds only the blueprint-pity comment, the mission-cache guarantee and its call site, none of
which grants a first-mission Rare.

## Consequences worth naming

- **The toughest enemies in the game do not drop what they should.** A Veyr has a 10% Legendary share authored; the current path gives it
  whatever the selected tier provides — and the Legendary tier contains **0% Common**, so the "boss never Common" clause is satisfied by
  accident rather than by rule.
- **Difficulty does not make drops better.** Only the mission's cache tier changes with difficulty; enemy drops inside that mission are
  identical on Easy and Extreme, so the authored .65/1.35/1.7 curve has no effect.

## Not changed

Same reasoning as the mission-distribution batch: this is drop-rate tuning, and introducing per-class tables plus a difficulty
multiplier changes loot pacing substantially. Recorded with the exact authored numbers so one owner pass can settle it alongside the
mission distributions, boss HP, cooldowns, mission length and the ADS ratio.

## Confidence

The absence claims are from source inspection of `CacheService.rollRarity`/`onEnemyKilled` and the `Caches` config shape, cross-checked
with a keyword search. No runtime drop was measured — that would need a hundred-plus kills to distinguish distributions, and the
structural difference makes the outcome predictable.
