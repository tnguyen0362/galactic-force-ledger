# Elimination verified; redeploy no longer stacks missions (build 456)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## The bug behind "elimination targets=0"
`StationService` called `EnemyService.clearAll()` **without ever requiring EnemyService**. Result:

```
ServerScriptService.GF.Services.StationService:371: attempt to index nil with 'clearAll'
```

That threw on the deploy path *before* `ObjectiveService.setup`, so the objective never built: missions came up with patrols only, no tagged targets, and no completion possible. The earlier "targets=0" reading and the sweep where every template reported 3 stale targets were both downstream of this.

Fixed by adding the missing `local EnemyService = require(script.Parent.EnemyService)`.

## What the clear was for
`EnemyService.clearAll()` previously ran **only** on extraction, so redeploying without extracting left the old mission's hostiles alive. Two missions' worth of actors then shared one `ActiveActors` folder and every count read high. It now runs immediately before `ObjectiveService.setup`.

## Measured
| Pass | `GF_ElimTargets` | Tagged models | Roster |
|---|---|---|---|
| 1 (fresh) | 3 | **3** — `Officer, Rifleman, Rifleman` | 8 hostiles |
| 2 (redeploy, nothing killed) | 3 | **3** — same | **8 hostiles** |

The roster stays at one mission's worth across redeploys instead of accumulating.

Killing all three tagged targets:

```
killed=3  stillAlive=0  GF_ObjectiveComplete=true
```

So the elimination family runs end to end: tags the right archetypes, counts them, and completes when they die.

## Limits
- Only `ELIM_COMMANDER` was driven to completion. `ELIM_WALKER` (Bastion Walker) and `ELIM_TALON` (three elites) were only observed to tag correctly in earlier passes, not completed.
- The template sweep that showed "3 everywhere" was confounded by rejected deploys while a mission was live; it should be re-run with a fresh play session per template.
- `S08-033` asks for approximate-then-updated target markers; the markers still show exact positions.
