# Relay call cap — attempted, not airtight (build 447)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Intent
Build 446 measured **6 reinforcements** from a single sabotage mission because three Officers each called once. This batch set out to cap the relay call at **one per mission**.

## What was added
- `EnemyService.resetCalls()` clears a module-level `relayCallUsed` flag and publishes `GF_RelayCallUsed`; called from `EncounterDirector.beginMission`.
- A call may only **start** while `relayCallUsed` is false.
- A call may only **complete** while `relayCallUsed` is false; otherwise it is marked cancelled.

## Measured
| Run | Reinforcements | Officers | Call state |
|---|---|---|---|
| Before the cap (build 446) | **6** | 3 | all pending |
| Start-guard only | **6** | 3 | flag set, but all three had already started |
| Start + completion guard | **4** | 5 | `Officer:pending ×2`, `Officer:cancelled ×3` |

So the cap reduces the over-spawn but **does not enforce one call**: two calls still completed, and I do not have a clean explanation. Two candidates I could not separate:

1. `GF_Reinforcements` is a running counter that is **not reset per mission**, so 4 may include carry-over from an earlier mission in the same session.
2. Two Officers completed inside the same 0.5 s tick, before the flag write from the first was visible to the second — which should not happen in a sequential loop, but is the shape of the evidence.

## Honest state
The cap is **incomplete and unproven**. What I can say with evidence: the mission no longer produces 6. What I cannot say: that it produces exactly 2.

## Next action (one run, one question)
Reset `GF_Reinforcements` at `beginMission`, and stamp `GF_CallCompletedBy` with the Officer's name each time a call resolves. Then a single mission run will show whether 4 is carry-over or two simultaneous completions.

## Process note
This is the fifth time a running counter/last-value attribute has produced an ambiguous reading. Counters need resetting in the same place their mission-scoped peers are reset, or they quietly accumulate across missions.
