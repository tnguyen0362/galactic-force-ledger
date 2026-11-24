# Hacking cancel + full-variant sweep — measured evidence (build 398)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Hacking cancellation (new, `S08-040`)
`HackingService.begin(player, difficulty, anchor)` now starts a 0.4 s watchdog. A challenge is released when:

| Condition | Reason string | Measured |
|---|---|---|
| player leaves the console (>26 studs from the anchor) | `range` | code path |
| player is downed (`State.downed`) | `downed` | **observed**: challenge released, `GF_HackCancelled="downed"`, `GF_HackStage=0`, archive stage stayed 2 |
| character gone / player left | `disconnect` | code path |

`HackingService.onCancel` lets the owning objective react: the archive now rewrites its hint to `Console lock released (<reason>) — break the console again` and the console prompt returns immediately, so the player can retry without redeploying.

## Full verification sweep at build 398
| Variant | Evidence |
|---|---|
| `RECOVER_TECH` | black box interacted, `CarriedCase` appeared on the character, teleported to the LZ, `GF_ObjectiveComplete=true` |
| `DEFEND_BEACON` | activated, hold ran to `GF_ObjectiveComplete=true` while the mission was live |
| `DEFENSE_POWER` | restore → 90 s defence survived with the generator at **520/600** (`GF_DefenseRemaining=0`, stage 3, `GF_ObjectiveFailed=false`) → `PowerStabilise` interaction → `GF_ObjectiveComplete=true` |

With these three, **all 15 configured variants have been played to completion at build 397/398**.

## Harness lesson that cost a run
`StationService.deploy` sets `GF_DeployGraceUntil = os.clock() + 4`. Any test that arms grace *before* deploying has it overwritten; the player then dies to hostiles and respawns at the station, which pauses defence timers and looks like a stuck objective (measured: `GF_DefensePaused=true`, timer 88 → 70 in 45 s). Re-arm grace **after** the deploy call, or re-assert it while the timer runs.

## Limits
- No explicit "exit" input for hacking; releasing the overlay means walking away, being downed or leaving.
- No terminal mutex beyond the per-player challenge.
- The cancel path was observed for `downed` only; `range` and `disconnect` are the same code, not separately measured.
- Solo only; one client.
