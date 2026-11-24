# Full-loop regression pass found a client break (build 453)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client. Goal loop had been editing this place for ~20 builds without a clean end-to-end run, so this batch ran one and read both logs.

## The run
Deploy `SABOTAGE_RELAY` on Normal → hold the relay → request extraction → board → settlement.

| Check | Result |
|---|---|
| Boot: services online | 41 service modules |
| Server errors during the whole run | **1**, and it is the Roblox plugin (`Game is not a valid member of ReplicatedStorage`), not game code |
| Objective | `GF_ObjectiveComplete = true` |
| Dropship | landed, boarded |
| Debrief | `credits base 450 + bonus 0`, `xp 600`, `PRIMARY OBJECTIVE: COMPLETE`, `Extraction: SUCCESSFUL`, `Carried salvage secured`, rank 15 |

## A real client-side break, found only by reading the client log
First pass, client log:

```
Players.…PlayerScripts.StationUI:472: attempt to call a nil value
```

`showDebrief` calls `setFocus(back)` at line 472, but `setFocus` was declared `local function` at line **480** — below its only caller. So the focus hand-back on closing the debrief threw every time.

Fixed by making it a global (`function setFocus(...)`) rather than moving 22 lines, then re-running the loop: the error is gone, and the only remaining client error is the same plugin noise.

This is the **third** forward-reference bug of the same shape this session (two of mine in `EnemyService`, this one pre-existing in `StationUI`). In Luau a local function used above its declaration compiles fine and fails at runtime; `loadstring` will not tell you.

## Limits
- One difficulty, one mission family, one player. The other 14 variants were not re-run in this pass.
- The debrief's focus ring was not visually confirmed, only that the error stopped.
- Plugin error remains and is out of scope for game code, but it does pollute every error read.
