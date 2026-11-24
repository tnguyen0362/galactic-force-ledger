# Heavy charge/recovery — implemented, NOT verified (build 443)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Changed
- `Configs/Enemies` Heavy gained `chargeTime = 1.4, recovery = 4.0`.
- `EnemyService` computes `windUp = def.chargeTime or def.telegraph or 0.55`, uses it for `actor.telegraphUntil`, stamps `ChargingUntil` and `GF_LastCharge` while a charge is pending, and extends the next attack by `def.recovery`.

Verified the config took: Heavy `chargeTime 1.4, recovery 4.0, damage 32, range 80`, and it spawns at 620 HP / 180 shield with `ArmorFactor 0.75`.

## What I could NOT verify
**No enemy dealt damage in either test run of this batch.** Numbers from the second run:

| Reading | Value |
|---|---|
| `GF_EnemiesTracked` | 10 |
| `GF_EnemiesEngaged` (player anchored at +12 studs) | **0** |
| Damage events, any source, 10 s | **0** |
| `GF_EnemiesEngaged` after repositioning to +18 studs, unanchored | 6 |
| Damage events after that, 6 s | **0** |
| `ChargingUntil` / `GF_LastCharge` | never set |

So: enemies acquire targets, and then nothing fires. That is either a **regression I introduced this batch** or a positional artefact — I could not separate the two before stopping.

## Why this is not claimed
The previous batch measured 32-damage Heavy blasts and 6-damage Scout bursts in the same mission template, so the damage path worked two builds ago. Between then and now I edited `EnemyService`'s attack path three times: `windUp`, the `recovery` extension, and the `ChargingUntil` block.

## Next step (do this first)
Instrument the delayed attack callback: write `GF_LastAttackAttempt` at entry, after the LOS test, and after `applyDamage`, then read all three. That will say in one run whether the callback runs, whether LOS rejects, or whether the delay never fires.

## Also noted
My first attempt put the `ChargingUntil` diagnostics into a **different function** (line ~326) than the live attack path (line ~412), because the same `EnemyFireallClients`/telegraph shape appears twice. I moved them, but it is the same "anchor exists twice" mistake as the payload edit at build 438.
