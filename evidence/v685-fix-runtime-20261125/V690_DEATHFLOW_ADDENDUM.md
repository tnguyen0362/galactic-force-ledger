# v690 death/end-screen addendum — 2026-11-25

## Deployment

v690 deployed all 95 scripts, zero compile failures, saved as cloud version **690**. Raw log: `raw/deploy_v690_deathflow.log`.

## Fixes

1. `StationUI.luau` no longer disables the entire base combat HUD in the station; only the mission objective HUD is mission-gated. This closes the conflict that could hide the lobby ability/dodge readout after returning home.
2. Downed overlay now distinguishes `DOWNED` from `K.I.A.` and shows live automatic-redeploy countdown text instead of leaving the player at a static full-screen word.
3. Server now publishes the redeploy countdown continuously.
4. Squad elimination is carried into the mission-end payload as `endReason`.
5. Debrief end screen now titles that terminal state **SQUAD ELIMINATED** and explicitly says automatic redeploys were exhausted.
6. Mission reset clears the previous end reason.

## Runtime evidence

Artifacts:

- `raw/v690_forced_failure_debrief_0.jpg`
- `raw/v690_deathflow_check.json`

A server-forced squad-elimination failure after a real Easy deployment produced a visible client debrief with:

- title: `SQUAD ELIMINATED`
- explanation: automatic redeploys exhausted / squad eliminated
- primary objective incomplete warning
- return-to-station button

This verifies the terminal end-screen path. It is honest evidence for the forced failure path, not yet proof of the full natural two-death solo sequence.

## Transition/loading note

The immediate post-deploy query read `GF_Teleporting=false` because the MCP round trip occurred after the short teleport window. Therefore v690 still does **not** prove the loading screen is seen during deployment. This remains open.
