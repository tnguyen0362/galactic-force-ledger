# Weapons have no spread at all — the spread fields are declared and unread (place 490)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, plugin-level source scan. No place changes.

## What I set out to do

Two dead augment stats remained plausible to wire: `swapSpeed` (4 augments) and `recoil` (8 augments, the biggest remaining win).

- **`swapSpeed` is blocked by design absence:** a project-wide search for `swap` finds nine references and **no swap delay anywhere**.
  Weapon switching is instantaneous (`Weapon:283` handles the key, no timing). There is nothing for a speed multiplier to modify.
- **`recoil` led to something worse.**

## The finding

`Configs/Weapons` declares spread and recoil on every weapon:

```
AR-01   spreadBase 0.6   spreadPerShot 0.35  recoil 1.0
SMG-03  spreadBase 0.8   spreadPerShot 0.5   recoil 0.8
LMG-12  spreadBase 3.2   spreadPerShot 0.2   recoil 2.0
SG-04   spreadBase 0.15  spreadPerShot 0.6   recoil 1.6
MR-07   spreadBase 1.0   spreadPerShot 0.3   recoil 1.2
```

A scan of `ServerScriptService` and `StarterPlayer` for `spreadBase`, `spreadPerShot` and `adsSpread` returns **zero consumers**.

So:

1. **Every weapon in the game is perfectly accurate.** No shot is perturbed. There is no bloom, no per-shot growth, no aim penalty.
2. **The spec's "ADS spread" column is unimplemented** — the authored values (0.55, .85, 4.5, .18, 1.0 …) are in the config and
   nothing reads them.
3. **`recoil` (8 augments) and `movingAccuracy` (2) cannot apply**, because there is no spread model for them to modify. That is
   10 of the 36 augments blocked on one missing system — a third of the catalog behind a single absence.

This also re-reads an earlier row: `S04-036` was recorded as "aimed spread **missing from the data table**". It is not missing from
the table; it is present and unused, which is a different and worse problem — the data looks done.

## Why this is recorded rather than implemented

Adding a spread model changes **hit registration**. Every existing measurement — the 18-shot TTK, the 90/240 falloff curve read
from `ActiveActors.Rifleman.Torso`, the `v461` falloff verification, the arc-of-fire tests — was taken in a world where aimed shots
land exactly where the ray points. Introducing angular jitter would:

- make exact-shot evidence irreproducible without a determinism hook
- change every damage-per-magazine calculation the ledger already records
- alter time-to-kill, which the contract tests (`S04-046`, `S04-047`) rest on

That is a combat-model decision with wide consequences, not a stat hook. It belongs with the other owner calls (boss HP, bleedout,
mission length, ADS ratio) rather than in an autonomous batch.

## What an implementation would need

1. A spread accumulator per player+weapon in `State` (bloom grows per shot by `spreadPerShot`, decays over time).
2. Angular jitter applied at `CombatService.fire` to the computed direction, scaled by `spreadBase`, reduced by `adsSpread` while
   `Aiming` is true, cut by `augs.recoil` (capped at 0.35 by the clamp table already in place).
3. A determinism switch (`GF_ForceNoSpread`) so the existing exact-shot evidence can still be reproduced — the same pattern already
   used by `GF_ForceNoBlueprintChance` and `GF_ForceRankUps`.
4. Recapture of the TTK and falloff evidence afterwards.

## Confidence

`DEAD` means "no occurrence anywhere in script sources"; a computed access would be missed, so this is a lower bound. But the
weapon config is a plain table read by id, and `CombatService.fire` composes its direction from camera/character geometry with no
perturbation step, so the conclusion is well supported.
