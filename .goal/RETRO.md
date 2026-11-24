# RETRO — friction

## F1. Play-mode script edits are silently discarded (cost: ~40 min, 4 patches)
Patching `ModuleScript.Source` through `execute_luau` with `datamodel_type = "Server"` while a
play session is running writes to the running DataModel. Stopping play restores the last saved
place and every patch is gone. Symptom: a fix "doesn't take effect" on the very next playtest.
**Fix (applied):** the loop is always stop -> patch in edit mode -> `save_place` -> play ->
verify. Added to PROGRESS "harness notes".
Candidate artifact: a wrapper snippet that refuses to patch unless `game:GetService("RunService"):IsStudio() and not RunService:IsRunning()`.

## F2. Calling API surface is a guessing game (cost: ~25 min)
Remotes with near-identical names exist and only some have listeners
(`RequestExtraction` vs `ExtractionRequest`, `RequestFire` vs `FireWeapon`), and `Humanoid:MoveTo`
times out after ~8 s, so a naive walk test reports "blocked by geometry" when nothing is blocking.
**Fix (applied):** `.goal/evals/mission_geometry.luau` documents the real remote names, the 45 s
extraction countdown, BOARD_RANGE, and the MoveTo re-issue requirement in one place.

## F3. Two ground authorities disagreed (cost: 2 iterations)
`TerrainService.surfaceY` (analytic) vs real voxels: 49.7 vs 26.0 at spawn. Fixed by making
`groundSurface` (raycast) the single authority. Lesson for new placements: raycast, never sample.

## F5. Tool VMs cannot touch live module state (cost: ~6 wasted probes)
`execute_luau` runs a fresh VM, so `require` hands back a **new module instance**. `State.getMission()`
was `nil` while `GF_InMission` was true, `ProfileService.get(player)` was nil while the profile existed,
`Weapon.getState()` returned defaults while the weapon was equipped, and `VFX.impact` threw because the
instance had no pools. Consequences: server state (tickets, cooldowns, charges) cannot be set up for a
test, and any "it returned nil" observation is meaningless unless it is the live instance.
**Fix (applied):** verify through durable, replicated surfaces only — `workspace` attributes,
`workspace.GFDebug`, `SoundService.GFAudioVoices` `count_*` attributes, HUD text, and the console.
**New rule:** never conclude a product bug from a fresh-instance probe; call `init()` or read a
replicated surface instead. Recorded because it produced four false bug reports.

## F6. `execute_luau` calls over ~50 s time out at 60 s
A 78-second scripted play loop died mid-run and lost its return value. Keep waits under ~45 s and
split long sequences across calls; the game keeps ticking between calls, so nothing is lost.

## 2026-11-24 — Tests must not live in the extension directory

**What happened:** `pi` died at startup for the owner, printing a test suite's PASS/FAIL lines. Cause: I
put `test_goal_loop.ts` and `test_image_gc.ts` in `~/.pi/agent/extensions/`. Pi auto-discovers **every**
`.ts` file in that folder as an extension, so the test's top-level code ran on every launch and its
`process.exit(failed === 0 ? 1 : 0)` terminated Pi. A suite that passes standalone is still a crash on
boot when it is where the loader looks.

**Rule:** test/bench harnesses live in the repo (`.audit/`), never in an extensions directory. After any
extension change, run `.audit/boot_check.mjs`, which imports every file in the extension folder and fails
if one throws or has no default export.
