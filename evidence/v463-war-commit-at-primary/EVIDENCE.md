# War points commit at primary success, independent of extraction (place 463)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1` (placeId 120646942844931), Play mode, one local client.
Place saved as **version 463**.

## The defect

`S09-035` / `GOAL_2026-11-24.md` L145: *"War points committed once at primary success, independent of extraction."*

The measured path did the opposite. `ExtractionService.finish(success)` called
`GalacticWarService.recordMission(template, success)` where `success` was the **extraction** outcome, so:

- complete the primary, then lose the dropship → the campaign was recorded as a **loss**
- lose the primary, then force an emergency extraction → recorded as a **win**

Neither is what the specification asks for. The commitment was tied to the way out, not to the operation.

## The change

Four edits, each guarded against ambiguous text matching (the batch asserts exactly one occurrence before
replacing, because a previous session lost a patch to a line that existed twice):

| file | change |
|---|---|
| `GalacticWarService` | new `commitPrimary(template)` — refuses if `GF_WarCommitted` is already true, then `recordMission(template, true)` |
| `ObjectiveService.setup` | clears `GF_WarCommitted` for the fresh mission |
| `ObjectiveService.complete` | calls `commitPrimary(templateId)` — `complete()` already had a once-only guard |
| `ExtractionService.finish` | no longer credits the campaign for a completed primary; records a loss **only** when the primary never completed |

All three modified modules pass `loadstring` before running.

Verification ran in a temporary `Script` parented into `ServerScriptService` so it shared the live module
instances — a tool-VM `require` gets its own copies and would have proved nothing (the trap recorded in
`HANDOFF.md` and repeated in v404, v412 and v422). The script was deleted after the run.

## Measured

```
before                     [w=13 l=7  c=false]
afterSetup                 [w=13 l=7  c=false]   marker cleared for the new mission
afterComplete              [w=14 l=7  c=true ]   war point committed AT PRIMARY  <- w 13 -> 14
afterComplete2             [w=14 l=7  c=true ]   idempotent, no double credit
afterFail_primaryDone      [w=14 l=7  c=true ]   failed extraction did NOT touch the campaign
afterSetup2                [w=14 l=7  c=false]   marker cleared again
afterFail_primaryIncomplete[w=14 l=8  c=false]   loss recorded ONLY when the primary never completed
```

All four required behaviours hold: commit at primary success, exactly once, unaffected by a failed extraction, and a loss
only for a genuinely incomplete primary. `afterFail_primaryDone` is the row that fixes the defect — before this change
that line would have read `l=8`.

## Side effects, stated plainly

- **The campaign counters moved.** This test wrote one win and one loss into `GalacticWarService`'s DataStore
  (`missionsWon` 13 → 14, `missionsLost` 7 → 8). That is a real, persisted side effect of testing the real path, not a
  simulation. The war score is cosmetic, but the numbers are no longer the pre-test values.
- The place was saved as version 463 with these three module changes.
- `ObjectiveService.setup` ran twice against `Vector3.new(0,0,0)`, so any objective geometry it built was transient and is
  not part of the saved place.

## Not covered

- Only `SABOTAGE_RELAY` was exercised as the template. `RECOVER_TECH` and `DEFEND_BEACON` take the same code path but were
  not run.
- Normal difficulty, solo, one stage machine. No co-op and no `CONQUEST_*`/`ELIMINATION_*` template.
- A genuinely completed primary followed by a real emergency extraction was simulated at the service boundary
  (`ExtractionService.finish(false)`), not played through the dropship.
