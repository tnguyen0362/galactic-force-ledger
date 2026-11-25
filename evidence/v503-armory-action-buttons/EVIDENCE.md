# The two orphaned actions now have buttons (place 503)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 503**.

## The gap this closes

Two features were implemented and verified over the last three batches but **unreachable in play**:

- augment inventory expansion (`expandAugmentInventory`)
- bulk cache opening (`openMany`)

Both existed only as service functions. A player had no way to invoke either.

## Change

| file | change |
|---|---|
| `ArmoryService.state` | exposes `caches = profile.caches` so the UI can name the tier and count it holds |
| `ArmoryService` | new `bulkOpenCache` action → `CacheService.openMany(player, tierId, 10)`, marks dirty when anything opened |
| `StationArmoryUI` | new action row with **`EXPAND +50`** and **`OPEN 10 · <tier> x<n>`** buttons, the latter reading the tier with the most held |

## Measured

Rendered buttons, read from `PlayerGui` after the documented `GF_ArmoryOpen` switch:

```
EXPAND +50 | OPEN 10 · Rare x14
```

The bulk label reflects real held state rather than a hardcoded tier.

Firing each action from the client:

```
expandResult = "false:already at max capacity"
GF_CacheHeld = "Rare:13"                          (was 14)
GF_CacheBulk = "Rare wanted=10 opened=1 held=13 space=364"
GF_AugmentCapacity = "37/400"
```

Every one of those is correct behaviour, including the two that look underwhelming:

- **`opened=1` with `space=364`** — the batch stopped because **no unowned Rare augments remained**, not because of the cap. This is exactly the "nearly-exhausted tier" case I listed as untested in the bulk-open evidence, and it degrades cleanly instead of erroring or eating caches.
- **`false:already at max capacity`** — the test profile's capacity is 400 from an earlier probe, so the button correctly refused and said why. The refusal message reaching the client is itself useful: the UI is not silently failing.

And `source=unknown` on the opened cache is the documented fallback working as designed — that cache was granted before place 500 added instance records, so it has no uid to name.

## What the buttons do not do

- **No confirmation or cost preview on `EXPAND +50`.** The player is not told it costs 10 Cells + 3 Tech + 1000 Credits before pressing. The server enforces the cost; the UI does not show it.
- **No feedback surface.** Both results go to `workspace` attributes (`GF_AugmentExpandResult`, `GF_BulkOpenResult`) rather than to an on-screen message, so a player still learns nothing from clicking — the wiring is complete but the feedback is not.
- **No held-count refresh** until the panel reopens, so `OPEN 10 · Rare x14` can read stale within a session.
- The test profile is left at `capacity = 400`, `Rare = 13`.
