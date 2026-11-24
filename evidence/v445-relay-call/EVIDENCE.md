# Commander relay call (build 445)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## What was missing
`S06-027` specifies "2 s call if relay active; death clears aura and **pending call**". The aura shipped at build 442; the call did not exist at all.

## Implemented
`EnemyService.startCalls()` runs a 0.5 s loop, deliberately outside `tickActor` so the attack path is untouched:

- Finds a live relay (`GFInteract == "Relay"`).
- Any live `Officer` within **70 studs** of it starts a **2 s** call, publishing `CallingUntil` and `GF_LastCall`.
- When the timer elapses it spawns **2 Riflemen** beside the Officer and counts `GF_Reinforcements`.
- If the Officer dies while a call is pending, it is marked cancelled and counted in `GF_CallCancelled` — nothing spawns.
- `GF_CallState` publishes `rank:pending|cancelled` per Officer.

No Officer spawns in the sabotage roster, so the test used an elimination mission (which includes an Officer) plus an invisible marker part tagged `GFInteract = "Relay"` beside it.

## Measured
| Check | Result |
|---|---|
| Officer within range of a relay | `GF_CallState = "Officer:pending"` |
| Call completes | `GF_Reinforcements = 2`, `GF_LastCall = "Officer:reinforcements"`, Riflemen 2 → 4 |
| Officer killed mid-call | `GF_CallCancelled = 1`, `GF_Reinforcements` stayed **0**, state `Officer:cancelled` |

Both halves of the rule — the call spawning help, and death cancelling it — are observed.

## Limits
- **No real relay exists in the elimination missions.** The test faked one with a hidden part. In the actual sabotage mission there is no Officer at all, so this rule can never fire in the content that has a relay. That is a content gap, not a code gap, and it is worth fixing: an Officer should be part of the sabotage roster for the rule to matter.
- Reinforcement strength is fixed at 2 Riflemen regardless of difficulty; the spec does not specify a number, so this is a guess.
- The 2 s window was not timed precisely — only "pending, then reinforcements appeared within ~5 s".
- `GF_LastCall` is a single attribute and reads a stale value across missions (same trap as `GF_CacheOpened`).
