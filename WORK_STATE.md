# WORK_STATE — last verified 2026-11-24, place version 383

## Current build
- Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, place `Playtest1` (placeId 120646942844931), saved as **version 383**.
- Spec `.goal/GOAL_2026-11-24.md`; ledger `REQUIREMENT_COVERAGE.csv` **815 rows, 9 populated, 806 UNKNOWN**.
- Ledger state: PARTIAL 8 | MISSING 1 | VERIFIED 0 | OWNER_ACCEPTED 0.

## Verified this batch (evidence/v383-elimination/EVIDENCE.md)
The Elimination family is **playable and completing**:
| Variant | Roster | Targets | Completion |
|---|---|---|---|
| Head of the Spear (`ELIM_COMMANDER`) | Officer + 2 Rifleman | 3 | only at 3/3; 2/3 leaves it open |
| Siege Breaker (`ELIM_WALKER`) | Bastion Walker, 4200 HP | 1 | on the walker's death; one walker in the world, not two |
| Broken Talon (`ELIM_TALON`) | Marksman + Heavy + Officer | 3 | only at 3/3 |

Frame `ScreenCapture_ELIM_COMMANDER` shows `PRIMARY OBJECTIVE COMPLETE / Extraction authorized` over the elimination pad.

Root cause of the earlier `targets=0` null result: `ObjectiveService` never had an elimination builder — the deploy fell through to `buildRelay`. It was not a spawn or whitelist failure.

Two defects found while verifying, both fixed:
1. The tracker started before `setup` assigned `objective`, so it broke out of its first iteration and never completed. Now started from `setup` with a generation counter (`elimRunId`) that also stops a stale tracker completing a later mission.
2. Bosses leaked across deployments: `EncounterDirector.reset` only removed models with a `Humanoid`, and boss models have none. Measured **five** `BastionWalker` models alive after five deployments. Reset now sweeps `Boss` models but spares `GF_ObjectiveTarget`; `setup` destroys the previous mission's tagged targets; `beginMission` skips the optional field boss when the template is `ELIM_WALKER`.

## Known gaps in what was just built
- No target marker system anywhere in the build (`S08-033` MISSING). Sites are found by walking.
- Missing authored stages: commander's optional relay, Walker's "secure battlefield", Talon's "linked encounter".
- Kills in the verification were applied by setting the `Dead` attribute — the same write `CombatService` performs on a lethal hit — so weapon → damage → kill was not re-exercised.
- Solo only; no second client.

## Next highest-value work
1. **Conquest family** — the only family with zero content (`Forward Dominion`, `Iron Foundry`, `Thronefall`); Thronefall uses the existing High Marshal Veyr boss. Closes families to 5/5 and variants to 9/15.
2. **Target markers** (`S08-033`) — affects every mission, not just Elimination.
3. Sabotage/Recovery/Defense second and third variants (`S08-003`).

## Environment
`.goal/PAUSE` removed; ledger and evidence committed. Studio left in Edit mode.
