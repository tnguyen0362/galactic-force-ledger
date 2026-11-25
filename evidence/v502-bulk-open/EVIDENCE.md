# Bulk cache opening: bounded to 10, space computed before the draw (place 502)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 502**.

## `S11-035` had nothing to bound

A project-wide search for `bulk` / `openAll` / `openMulti` returned 22 hits — **all of them station bulkheads**, geometry parts. There
was no bulk-open path at all, so "bounded 10 caches/action" had nothing to constrain.

Rather than record it as absent, I implemented it, since the spec authors both the limit and the ordering.

## The change

```lua
function CacheService.openMany(player, tierId, count)
    local space = math.max(0, capacity - ownedCount)     -- computed BEFORE any draw
    local held  = profile.caches[tier.id] or 0
    local wanted = math.clamp(tonumber(count) or 1, 1, 10)
    local budget = math.min(wanted, held, space)
    for _ = 1, budget do ... end
end
```

Three bounds applied up front: the per-action cap of 10, the caches actually held, and the free inventory space. Doing the arithmetic
before the loop is the point — a partially-fitting batch must stop rather than grant some caches and consume the rest.

## Measured

```
held before = 20
openMany(50)  -> wanted=10  opened=10  held 20 -> 10   space=200     (per-action cap)
space-limited -> wanted=10  opened=2   held 10 -> 8    space=2       (space bound)
```

The first call asked for 50 and opened exactly **10**, proving the cap. The second ran with capacity for only two more augments and
opened exactly **2**, leaving the remaining 8 caches held rather than consuming them.

## What is not done

- **No UI.** The action is a service function; nothing calls it from a client. So a player cannot bulk-open through the interface
  yet, which means the feature is real but unreachable in play.
- The per-action cap of 10 is applied to the **requested** count, but there is no rate limiting or cooldown between bulk actions — a
  client could call it repeatedly.
- No partial-failure reporting: if `openFromInventory` breaks mid-loop for an unexpected reason, the function returns the count opened
  so far and the caller has no list of what succeeded.
- Not tested with a tier that has few unowned augments left, where `roll` returning fewer items would shrink the effective batch.

## Disclosed

The probe replaced `ownedAugments`, `augmentCapacity`, `caches` and `cacheInstances` on the test profile, then restored all four.
