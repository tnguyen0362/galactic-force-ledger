# SELF — capabilities gained

## Eval harness for mission geometry (`.goal/evals/mission_geometry.luau`)
- Before: every "is the mission reachable?" check was a bespoke sequence of 6-10 tool calls
  (deploy, walk, probe colliders, read attributes), and it was easy to misread a `MoveTo`
  timeout as a physics bug.
- After: one paste into `execute_luau` (edit mode) returns 10 pass/fail lines
  (groundSurface vs terrain, six services loadable, GF_LZ contract on both sides, relay snap).
  Measured: ~10 tool calls -> 1 call.
- Regression value: catches the buried-relay and lost-LZ classes mechanically.

## Verified loop recipe (client half of the eval)
Deploy -> walk (re-issue MoveTo) -> Interact("Relay") -> ExtractionRequest -> wait 45 s ->
Interact("Extract") -> expect `GF_ExtractionState = complete`, `GF_InMission = false`.
Turns a 60-minute manual playtest into ~90 seconds of scripted evidence.
