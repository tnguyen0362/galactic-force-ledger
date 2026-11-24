# Relay call cap verified (build 448)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## The ambiguity from build 447 was carry-over
Build 447 measured 4 reinforcements against a one-call cap and I could not say whether that was two calls or a stale counter. Two changes settled it:

- `beginMission` now resets `GF_Reinforcements`, `GF_CallCompletedBy` and `GF_LastCall` alongside `resetCalls()`.
- Each completed call appends `Officer@<clock>;` to `GF_CallCompletedBy`, so completions are **countable** rather than inferred.

## Measured, two consecutive missions in one session
| | Mission 1 | Mission 2 |
|---|---|---|
| `GF_Reinforcements` | **2** | **2** |
| `GF_CallCompletedBy` | `Officer@163478.2;` (one) | `Officer@163501.5;` (one) |
| Officers alive | 3 | 4 |
| Riflemen alive | 5 | 7 |
| Call state | `pending ×2, cancelled` | (calls resolved) |

Exactly one completion per mission, exactly two reinforcements, and no accumulation across missions. The earlier 4 was the counter carrying over — the cap itself was working.

## Full Commander rule now measured
| Behaviour | Evidence |
|---|---|
| +10% ally fire rate within 45 studs | `AuraRate = 0.9` on four archetypes (build 442) |
| Aura cleared on death | back to `1` after the Officer died (build 442) |
| 2 s relay call | `GF_CallState = Officer:pending` then reinforcements (build 446) |
| Call spawns help | 2 Riflemen per call (builds 446–448) |
| Death cancels a pending call | `GF_CallCancelled = 1`, zero reinforcements (build 445) |
| One call per mission | one completion, 2 reinforcements, two missions running (this build) |

## Limits
- The 2 s duration was never timed with a stopwatch; only "pending, then resolved".
- Reinforcement composition is a hardcoded 2 × Rifleman; the spec gives no number, so this remains an authored guess rather than a verified value.
- The extra hostiles were never fought, so the difficulty impact of +2 is unmeasured.
- The guaranteed relay commander is my addition, not a spec requirement; it exists so the rule can fire reliably.
