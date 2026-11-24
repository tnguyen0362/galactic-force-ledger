# Both enemy diagnostics now honest (build 452)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## `GF_EnemiesTracked` was also lying
Build 450 fixed `GF_EnemiesEngaged` (now "fired within 3 s") but left `GF_EnemiesTracked` reading **13 with the player on the station** — it counted actors whose `target` pointer had never been cleared, and dormant actors never tick, so no clear ever ran for them.

Two changes:
- `tickActor` clears `actor.target` when no target is found.
- The counter now requires a **live, in-range** target: the target's character must exist with a `HumanoidRootPart`, and the model must be within 260 studs.

## Measured
| State | `GF_EnemiesEngaged` | `GF_EnemiesTracked` |
|---|---|---|
| Under fire, 8 studs from a Rifleman | **5** | **10** |
| Six seconds after leaving to the station | **0** | **0** |

Both counters now move in both directions, so either can be trusted in a test.

## Two self-inflicted bugs in this batch
1. **A `local function` declared after its use** — `replicatedStorageFire(...)` in `tickActor` → `attempt to call a nil value` twelve times, all hostile fire stopped, `loadstring` reported nothing.
2. **A loop-variable mismatch** — the counter block referenced `model` while its loop bound `_`, so `model` resolved to a global and `model.PrimaryPart` threw inside the Heartbeat, which silently killed every tick and pinned both counters at 0. Fixed by making the loop `for model, a in pairs(actors)`.

Both compiled cleanly and both only failed at runtime. That is the recurring shape of trouble in this module: **`loadstring` is not a test.**

## Limits
- The 260-stud range is my choice, not a spec value; it exists so the counter means "close enough to matter".
- Verified in one mission with one player; not under multi-squad conditions.
- `GF_EnemiesEngaged`'s 3 s window is likewise an authored choice.
