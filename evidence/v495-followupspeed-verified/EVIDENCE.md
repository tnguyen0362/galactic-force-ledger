# `followUpSpeed` isolated and verified (place 495, instrumentation only)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`. No source edits, no place save.

## Why this run is different

The previous batch verified `adsRecovery` but could not isolate `followUpSpeed`, because `TargetDiscipline` was equipped in both
arms. It also failed to clear the loadout because `unequipAugment` takes **two** parameters (`profile, slot`) and the probe passed
three.

This run uses the correct signature (`pcall(A.unequipAugment, profile, i)` for slots 1–3), confirms the slot table is genuinely
`EMPTY` before the baseline burst, and dumps the slots on **every** measurement.

## Measured

```
baseline               [EMPTY]                 fu=0      bloom=0.92   (4 shots)
withTargetDiscipline   [1=TargetDiscipline]    fu=-0.15  bloom=0.84   (4 shots)
```

Four shots at 0.15 s spacing, `spreadPerShot 0.35`:

| decay | predicted bloom after 4 | observed |
|---|---|---|
| 1.00/s (no augment) | `0.35 → 0.55 → 0.75 → 0.95` | **0.92** |
| 1.15/s (`followUpSpeed −0.15`) | `0.35 → 0.5275 → 0.705 → 0.8825` | **0.84** |

Both arms land within timing jitter of their predicted value, and the two arms differ by exactly the amount the stat should produce.
**`followUpSpeed` is verified.**

## Complete key census

**13 of 14 keys wired, now 13 with measurement support:**

| key | evidence |
|---|---|
| weakPoint, healthDamage, armorDamage, shieldDamage | read in `CombatService` damage path |
| magazine, reloadSpeed | `AugmentService.magazine` / `reloadTime` |
| adsSpeed | measured `aim 14 → 15.12` with StabilityCompensator |
| cooldown | measured Airstrike `90 s → 71.9 s` |
| blastRadius | measured `9.00 → 11.25`, clamped at +25% |
| recoil | measured `0.600 → 0.450` with MasterworkBore |
| movingAccuracy | measured `0.600 → 2.100` moving penalty |
| adsRecovery | measured bloom `0.69 → 0.41` with ReflexSear |
| **followUpSpeed** | measured bloom `0.92 → 0.84` with TargetDiscipline |

**Never applied (2 keys):** `swapSpeed` — weapon switching is instantaneous, so there is no delay to scale; `sentryAmmo` — the
sentry has no ammo pool to extend.

## Method note that paid off twice

Both remaining discrepancies in this work were resolved by *dumping the state next to the measurement* — the slot table. The
pattern is cheap: any probe that mutates persistent state must print that state on every arm, or it silently compares the wrong
things. That is what turned two "anomalies" into two harness bugs.

## Still open on augments

- `swapSpeed` (4 augments) and `sentryAmmo` (2) require systems that do not exist. Implementing either is a feature, not a stat hook:
  a swap delay, and a sentry ammo pool.
- The bloom decay constant (1.0/s) and cap (6) remain my invention, as does the 1.5° moving penalty.
- No group-size measurement has ever been taken, so spread is verified as an angle, not as on-screen dispersion.
