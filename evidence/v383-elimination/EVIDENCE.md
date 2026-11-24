# Elimination family — measured evidence (place version 383)

Session: 2026-11-24, Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, place `Playtest1` (120646942844931), Play mode, one local client.

## What was broken before this batch
`Configs/Missions` and `StationService.VALID_TEMPLATES` contained `ELIM_COMMANDER`, `ELIM_WALKER`, `ELIM_TALON`, and `StationUI` rendered three buttons, but `ObjectiveService` had **no** elimination builder. `string.grep` for "elim" returned zero matches inside `ObjectiveService`. Deploying an elimination operation fell through to `buildRelay`, so the mission was a sabotage hold with an elimination label — the `targets=0 complete=false` result recorded at pause time was this, not a spawn failure.

## Implemented
`ServerScriptService/GF/Services/ObjectiveService`:
- `elimAdd` tags each spawned model with `GF_ObjectiveTarget`, `elimTotal` counts them.
- `elimTick` polls 0.5 s, counts models whose `Dead` attribute is true or whose instance is gone, publishes `progress = killed/total` and `hint = "<label> n / total down"`, and calls `ObjectiveService.complete()` when all are down. A generation counter (`elimRunId`) stops a previous mission's tracker from completing a later one.
- `elimSite` builds a 22×22 pad, pennant pole and two crates at the objective position, plus `OutpostService.build`.
- `buildElimination` rosters: `ELIM_COMMANDER` = Officer + 2 Rifleman; `ELIM_WALKER` = `BastionWalker.spawn`; `ELIM_TALON` = Marksman + Heavy + Officer.
- `setup` destroys the previous mission's tagged targets before building, then starts the tracker **after** `objective` is assigned.

## Measured results (server attributes, `execute_luau` Server datamodel)
| Variant | `GF_DeployRejected` | `GF_ElimTargets` | Tagged models | 2 of 3 dead | All dead |
|---|---|---|---|---|---|
| `ELIM_TALON` | nil | 3 | Marksman, Heavy, Officer | `GF_ObjectiveComplete=false` | `true` |
| `ELIM_COMMANDER` | nil | 3 | Officer, Rifleman, Rifleman | `false` | `true` |
| `ELIM_WALKER` | nil | 1 | BastionWalker, Health 4200, Boss=true | — | `true`, `BastionActive=false` |

Capture `ScreenCapture_ELIM_COMMANDER`: objective banner reads `PRIMARY OBJECTIVE COMPLETE / Extraction authorized` while the player stands on the elimination pad, with the Bastion Walker silhouette behind it and the space skybox visible.

## Second defect found while verifying: bosses leaked across deployments
`StationService.resetMission` order is `ObjectiveService.setup` (line 368) → `EncounterDirector.reset` (369) → `beginMission` (380). The old sweep in `EncounterDirector.reset` only destroyed models with a `Humanoid`, and `BastionWalker`/`Veyr` models have none. Measured **five** `BastionWalker` models alive in `workspace` after five deployments (Y positions 37, 45, 4799, 4849, 20130), each still running its own mortar loop.

Fixes:
1. `EncounterDirector.reset` now also destroys `Boss`-attributed models **except** `GF_ObjectiveTarget` ones, and clears `BastionActive`/`BossHealth`/`BastionDefeated`.
2. `ObjectiveService.setup` destroys the previous mission's tagged targets, so a stale tagged boss cannot survive a redeploy.
3. `EncounterDirector.beginMission` no longer spawns the optional field boss when the template is `ELIM_WALKER` — measured `walkerCount = 1` (the objective's) after the fix, versus 2 before.

## Limits of this evidence
- Kills were applied by setting the `Dead` attribute, which is exactly what `CombatService` writes on a lethal hit (line 105), but the weapon → damage → kill path itself was not re-exercised this batch.
- No second player; solo only.
- No target marker system exists, so `S08-033` remains MISSING: the site is found by walking and by the objective line, not by a marker.
- Missing stages: commander's optional relay, Walker's "secure battlefield", Talon's "linked encounter".
