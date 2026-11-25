# Twelve of thirty-six augments are placebo — their stats are never read (place 485)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level source scan. No place changes this batch.

## Method, and two false negatives I had to correct first

For every augment effect key in `Configs/Augments`, I checked whether any gameplay code reads it.

**Correction 1:** my first scan read `e.stats`, but the config field is `e.effect`. That reported *"0 augments use adsSpeed"* — a
false negative. (This is the third field-name false negative this session.)

**Correction 2:** my second scan looked only for `augs.<key>` in caller modules and excluded `AugmentService`, which made
`reloadSpeed` and `magazine` look dead. They are applied — through `AugmentService.reloadTime()` and `AugmentService.magazine()`.
A key's consumer may be the module that owns it.

After both corrections, by counting occurrences *inside* `AugmentService`: a key that appears **once** appears only in the
allow-list literal, which is a declaration, not an application.

## The census

| consumed | where |
|---|---|
| `weakPoint`, `healthDamage`, `armorDamage`, `shieldDamage` | `CombatService` |
| `magazine` | `AugmentService.magazine()` → `CombatService` |
| `reloadSpeed` | `AugmentService.reloadTime()` → `CombatService` |
| `adsSpeed` | `MovementService` (added last batch) |

| **never consumed** | augments rolling it |
|---|---|
| `recoil` | 8 |
| `blastRadius` | 4 |
| `swapSpeed` | 4 |
| `cooldown` | 3 |
| `adsRecovery` | 2 |
| `followUpSpeed` | 2 |
| `movingAccuracy` | 2 |
| `sentryAmmo` | 2 |

Each of those eight appears exactly once in `AugmentService` — inside the allow-list string — and nowhere else.

## Impact: 12 of 36 augments do nothing at all

An augment is placebo when **every** key it rolls is unconsumed:

```
Bipod, BorePolish, CoolantLoop, ExtendedSentryMagazine, FastHands, HeatSink,
LightBolt, OverclockedCore, QuickDraw, ReflexSear, StableStock, WideCharge
```

That is a third of the catalog. They are purchasable with credits and roll traits with real ranges, and none of it changes the
game. `FastHands`, notably, is the archetype whose duplicate id I fixed at place 466 — it was doubly broken: an id collision *and*
an inert effect.

## Related: no cross-slot clamp exists

`S11-055` requires additive bonuses per stat **then clamp**: body damage +15% max across two slots, weakpoint +20%, shield
damage +30%, magazine +35%, reload/movement +25%, recoil/spread ≤35%, range +30%, blast radius +25%, support cooldown +20%,
support damage +15%, negative floor 0.

What exists is per-application flooring only — `math.max(1, floor(...))` in `magazine`, `math.max(0.4, base / ...)` in
`reloadTime` — and no aggregate clamp per stat across sockets, and no negative floor at 0. So two augments rolling the same stat
stack additively with nothing bounding the total.

## Why this was never noticed

Every existing check validates that augments **exist**: ids unique, costs sane, rarity valid, 32 archetypes present, sockets
gated by mastery. All of that passes. None of it asks whether a trait *does anything*. `CheckRunner` has 639 passing assertions
and this was invisible to all of them — the same shape as the dead `Constants` keys: presence is cheap to verify, effect is not.

## Next batch, specified

`cooldown` is the cheapest win: 3 augments, and four identical call sites in `AbilityService`
(`s.cooldowns[ability.id] = now() + ability.cooldown`, lines 96/354/435/528). Centralise those four into one helper that applies
`ability.cooldown * (1 - augs.cooldown)`, then the three augments become real. `recoil` (8 augments) is the highest value but
needs a spread model, which does not currently use augments at all.
