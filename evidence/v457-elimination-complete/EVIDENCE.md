# All three elimination variants complete (build 457)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Results
| Variant | Targets | Played to completion | Final state |
|---|---|---|---|
| `ELIM_COMMANDER` (Head of the Spear) | 3 — Officer + 2 Riflemen | yes (build 456) | `complete = true` |
| `ELIM_WALKER` (Siege Breaker) | 1 — Bastion Walker, 4200 HP | **yes** | Walker 4200 → 0, `Dead = true`, `complete = true` |
| `ELIM_TALON` (Broken Talon) | 3 — Heavy, Marksman, Officer | **yes** | 3 killed, 0 alive, `complete = true` |

The elimination family now runs end to end in every variant: correct archetypes tagged, counted, and the objective completes when they die.

## A harness error I made again
First scan for `ELIM_WALKER` targets looked only inside `workspace.ActiveActors` and found **nothing**, while `GF_ElimTargets` said 1. The Walker lives at `Workspace.BastionWalker`, outside that folder. A whole-workspace walk found it immediately.

**Rule:** boss models are not guaranteed to be children of `ActiveActors`. Scan the workspace, not the folder, when counting targets.

## Limits
- Kills were applied through `CombatService.damageEnemy`, not by shooting them with a weapon. Damage routing, shields and death handling are exercised; **aim, spread and time-to-kill are not**.
- One difficulty (Normal), one player, no squad.
- Extraction after completion was not re-run for Walker and Talon; completion is proven, settlement for those two is inferred from the shared path tested on Sabotage.
