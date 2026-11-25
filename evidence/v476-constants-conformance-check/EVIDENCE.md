# The conformance check now covers `Constants` (place 476)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, fresh Play VM. Place saved as **version 476**.

## The gap this closes

The previous batch found `Combat.DownedTimeout = 45` against a spec bleedout of 60, and `Combat.ReviveDuration = 3.5` against
*"hold revive 3s"*. Both had survived every build since they were written.

They survived because `CheckRunner`'s spec-conformance section only asserted **`Configs`** modules. `Constants` — movement,
vitals, downed/revive — was never compared against the specification at all.

## What was added

A tenth section, same pattern as the config one: transcribe the authored value, assert, record drift.

| asserted | spec |
|---|---|
| `WalkSpeed` | ~17–18 |
| `SprintSpeed` | 24 |
| `AdsSpeed` | ~12–14 |
| `RollCharges` | 2 |
| `RollDuration` | 0.55 s |
| `RollDistance` | ~14–17 |
| `HealthMax` / `ShieldMax` | 100 / 100 |
| `ShieldRegenDelay` / `HealthRegenDelay` | 4 s / 9 s |
| `DownedTimeout` | 60 s |
| `ReviveDuration` | 3 s |

Ranges are asserted where the spec gives a range (`~17–18`), exact values where it gives one. Results feed the same
`errors`, `passed` and `GF_SpecDrift` as the config section, so drift stays in one place.

## Measured

```
before:  ok=false  passed=625  failed=12      (config drifts only)
after:   ok=false  passed=635  failed=14
         CONST DRIFT: DownedTimeout = 45, spec 60-60
         CONST DRIFT: ReviveDuration = 3.5, spec 3-3
other failures: 12                            (the pre-existing config drifts)
```

`+10` passing assertions are the constants that do conform; `+2` are the real drifts, now impossible to miss at boot. The
two previously silent defects are the only new failures, which is exactly the intended behaviour.

## Why this is worth more than the two fixes would be

Fixing `DownedTimeout = 60` and `ReviveDuration = 3` is four characters and changes how the game plays — bleedout and revive
timing are felt. That is the owner's call, same as the twelve config drifts.

Closing the **detection gap** is not: it is additive, it changes no behaviour, and it converts a class of defect that required
a human to notice into one that fails loudly on every boot. Two batches ago the same work found `OrbitalStrike` radius/damage
and `Sentry` radius/damage that twelve manual audit passes had missed.

## Still open

- The twelve **config** drifts remain red by design (balance values: launcher radii, four ability cooldowns/radii/damage, boss
  HP).
- The two **constants** drifts are now red as well; both are owner decisions.
- `BOSS_PITY` / `BOSS_BLUEPRINT_CHANCE` remain unassertable (locals inside `ProfileService`), so the 3-vs-5 and 0.34-vs-0.15
  deviations are still detected only by reading the file.
- Other `Constants` groups are not yet covered: `Combat.EnemyBudgetCap`, `MaxActiveEnemiesPerPlayer`, `InteractRange`,
  `RollRecharge`, and the regen **rates** (only the delays are asserted).
