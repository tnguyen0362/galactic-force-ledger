# Heavy charged blast verified; the "no damage" scare was grace (build 444)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## The previous batch's alarm was a test artefact
Build 443 reported "no enemy dealt damage — possible regression". That was wrong, and the cause was my own instrumentation:

1. I set `GF_DeployGraceUntil = os.clock() + 900` to stop the player dying, which **absorbs every incoming hit**. Damage was landing; the log never saw it.
2. Earlier runs also had the player at **y ≈ 767** (station deck) while the enemy was at **y ≈ 37** (mission) — a 746-stud gap, measured with a raycast — so `engaged = 0` was correct behaviour, not a fault.

With `GF_LastAttackAttempt` instrumented at entry / LOS-fail / LOS-pass / hit, and grace cleared for a short window:

| Reading | Value |
|---|---|
| `GF_LastAttackAttempt` | `hit` |
| Heavy damage events | **32.0, 32.0** |
| `GF_LastCharge` | `Heavy:1.4` |
| `ChargingUntil` | set, then expired 2 s later |

So the attack path works, the Heavy's authored 32 damage lands, and its 1.4 s charge is real and observable.

## Implemented this batch
- `Configs/Enemies` Heavy: `chargeTime = 1.4`, `recovery = 4.0`.
- `EnemyService`: `windUp = def.chargeTime or def.telegraph or 0.55` used for the telegraph delay, next attack extended by `def.recovery`, and `ChargingUntil` / `GF_LastCharge` published while a charge is pending.
- `GF_LastAttackAttempt` (entry / los-fail / los-pass / hit) left in place as a permanent diagnostic — it answered in one run what three blind runs could not.

## Limits
- The **4 s recovery** was not timed shot-to-shot; two hits in 9 s is consistent with it but does not prove the interval.
- Damage was measured at 14 studs with the player anchored; no cover, no movement during the charge.
- The Heavy still has no visual charge tell beyond the shared `EnemyTelegraph` event.
- Grace absorbing damage is *correct* behaviour, but it means any damage test must clear it — worth remembering.

## Process note
Three separate instrumentation choices produced false negatives this session: an attribute set from the client (doesn't replicate), a single-value attribute overwritten by a later write, and now deploy grace swallowing damage. The fix is always the same: read the state the code actually mutates, and clear the safety rails before measuring.
