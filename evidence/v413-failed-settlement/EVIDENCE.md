# Failed-mission boarding now settles as failure (build 413)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## The defect
`ExtractionService.board()` called `ExtractionService.finish(true)` **unconditionally**. A squad that lost the primary, waited for the emergency dropship and boarded it was paid as a success: `GF_ExtractionState = "complete"`, no carried-salvage loss, and a full reward settlement.

## The fix
`board()` now asks the objective who won:

```lua
local objectiveDone = false
pcall(function() objectiveDone = require(script.Parent.ObjectiveService).isComplete() == true end)
ExtractionService.finish(objectiveDone)
```

`finish(success)` already had the correct failure branches (`GF_ExtractionState = "failed"`, `GF_CarriedLost = not success`, `RewardsService.grantAll(success, ...)`, `GalacticWarService.recordMission(template, success)`); they were simply never reached from a loss.

## Measured (full failed round trip)
1. Deployed `DEFENSE_POWER` on Normal, restored the generator, destroyed it → `GF_ObjectiveFailed = true`, emergency extraction offered.
2. Waited for the dropship: `GF_ExtractionLanded = true`, boarding zone at `0, 33.8, 129`, player moved onto it.
3. Fired `InteractRequest("Extract")`.

Client settlement payload:

```json
{ "success": false, "credits": 0, "xp": 0, "rankUps": 0, "objectiveComplete": false,
  "salvage": { "scrap": 0, "energyCells": 0, "militaryTechnology": 0 } }
```

Server state afterwards: `GF_ExtractionState = "failed"`, `GF_CarriedLost = true`, `GF_InMission = false`, `GF_DeparturePlayed = "none"`.

So the loss path pays nothing, keeps no carried salvage, and does not play the success departure.

## Limits
- One player, one difficulty. The full-squad bonus and the per-player split were not exercised.
- `GF_ExtractionState` still reads `"idle"` while a boarding is pending; only the terminal states were checked.
- War-credit contribution on a loss was not read back (`GalacticWarService.recordMission` was called with `false`, but the campaign total was not inspected).
- The other four mission families still have no failure trigger, so this path only exists for `DEFENSE_POWER`.
