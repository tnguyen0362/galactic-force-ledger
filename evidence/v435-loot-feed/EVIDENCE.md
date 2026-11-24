# Loot feed with stacking, squad count (build 435)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Implemented
- `SquadService.broadcast(delta)` now fires the **delta** on `LootCollected` (`{kind, amount, source}`), not just totals on `SalvageChanged`.
- `SquadService.join/leave` publish `GF_SquadCount`.
- `StatusStrip` gained a four-line loot feed that **stacks identical consecutive pickups** (`+75 scrap x3`) and fades entries after 4 s, plus a `SQUAD n` label.
- Studio-only `grantSalvage` action (guarded by `GF_TestHooks`) so the feed can be exercised without hunting a canister.

## Measured
| Check | Result |
|---|---|
| Three `grantSalvage` 25-scrap grants | feed reads **`+75 scrap x3`** (one stacked entry) |
| Salvage broadcast | `{scrap = 75, energyCells = 0, militaryTechnology = 0}` |
| Server push | `action = grantSalvage` |
| Squad label | `SQUAD 1` |

Stacking is the requirement ("compact loot feed stacks repeated pickups") and it demonstrably collapses three pickups into one line.

## A regression I caused and fixed
While adding the delta broadcast I put the delta code **above** `local RS = game:GetService("ReplicatedStorage")` inside `broadcast`, so `RS` was nil at that point and every salvage pickup errored — **salvage collection was broken for two builds**. The tool-VM probe did not catch it because it ran against its own module instance after the code was already wrong.

Fixed by hoisting `RS` to file scope. Verified: the three grants produced a real broadcast and a real total of 75.

## Test-harness error, again
Two failed attempts came from setting `GF_TestHooks` **from the Client datamodel**, where attribute writes do not replicate. Setting it from the **Server** datamodel made the hook work immediately. This is a rule already in `WORK_STATE.md` and I violated it twice in a row.

## Limits
- Only one player exists, so `SQUAD 1` is the only value ever seen; the count never changed and the multi-member path is unverified.
- Feed entries were driven by the test hook, not by a real canister pickup.
- The 4-second fade was not observed; only the stacked text was read.
