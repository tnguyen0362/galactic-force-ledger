# Conquest family — measured evidence (place version 385)

Session: 2026-11-24, Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client. Attributes read from the **Server** datamodel.

## Implemented
`ReplicatedStorage/GF/Shared/Configs/Missions`: `CONQUEST_DOMINION`, `CONQUEST_FOUNDRY`, `CONQUEST_THRONEFALL` (`family = "Conquest"`).
`ServerScriptService/GF/Services/ObjectiveService`: `buildConquest` (pad, standard, terminal, facility core), a three-stage machine (`conqEnterStage` / `conqTick`), and `request` gating so only the authored interactive stage advances.
`StationService`: whitelist + mastery list extended; `TEMPLATE_RANK = { CONQUEST_THRONEFALL = 10 }` and a refusal path.
`StationUI`: three operation buttons.

## Measured
| Variant | Stage 1 | Stage 2 | Stage 3 | Result |
|---|---|---|---|---|
| `CONQUEST_DOMINION` | 4 tagged defenders (Rifleman ×2 named roster, Marksman, Rifleman), `GF_ConquestStage=1` | all 4 killed → `stage=2`, console prompt | interact 2.5 s → `stage=3`, 45 s hold | `GF_ObjectiveComplete=true` |
| `CONQUEST_FOUNDRY` | `stage=1`, `GFInteract=ConquestConsole` | interact → `stage=2`, prompt `Capture control point` | interact → `stage=3`, 60 s hold | `true` after 60 s |
| `CONQUEST_THRONEFALL` | 3 tagged (Heavy, Officer, Marksman) | killed → `stage=2`, `HighMarshalVeyr` spawned tagged, Health 3200 | killed → `stage=3`, prompt `Capture command node` | interact → `true` |

Rank gate: `TEMPLATE_RANK` temporarily set to 99, deployment returned exactly `GF_DeployRejected = "requires military rank 99"` and no mission started; restored to 10 and re-saved. The test profile is above rank 10, which is why the successful Thronefall runs were allowed.

## Defects found and fixed during verification
- `conqEnterStage(4)` was reachable from Thronefall's command node and did nothing: the stage counter advanced past the last stage and the mission never completed (measured `stage=4`, `complete=false`). Fixed by completing when the stage number exceeds 3, then re-verified end to end.
- One test-script error worth recording: counting tagged models with `workspace:GetChildren()` misses enemies parented under `workspace.ActiveActors`; the first Thronefall stage test reported "no targets" for that reason, not because of a code fault.

## Limits
- The defend/hold stages have **no failure condition**: nothing damages the objective, so a hold always succeeds even if the squad leaves. `S08-029`, `S08-031` remain open.
- Thronefall's "breach stronghold outer defense" is a three-elite clear, not a fortification breach with its own object HP.
- Kills were applied through the `Dead` attribute that `CombatService` writes on a lethal hit; the weapon path was not re-exercised.
- Solo only; no second client, no marker system.
