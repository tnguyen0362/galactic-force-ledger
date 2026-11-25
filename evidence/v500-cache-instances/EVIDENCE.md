# Cache instances have identity, and a bug I shipped at place 499 is fixed (place 500)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 500**.

## The bug first — my own, from last batch

Place 499 added a capacity gate inside `CacheService.open`, which returns early. But `openFromInventory` decremented the held
count **before** calling `open`. So with a full inventory, opening a cache would have **eaten it**: counted as consumed, nothing
granted, no refund.

That is exactly the class of defect this project keeps producing — a guard placed at the wrong layer. The gate belonged before the
consumption, and now is:

```lua
if ownedCount >= capacity then
    workspace:SetAttribute("GF_CacheRejected", string.format("inventory full %d/%d", ownedCount, capacity))
    return {}
end
```

Measured: `full inventory: rolled=0  held 1→1  rejected="inventory full 1/1"` — the cache survives.

## Then `S11-031`: caches now have identity

`profile.caches` was **counts per tier** and nothing else, so "which cache was this" was unanswerable. Each grant now also records:

```lua
{ uid = "Common-1795574978-1", tier = "Common", source = "mission:test", obtainedAt = 1795574978 }
```

and `openFromInventory` consumes the oldest matching instance, passing its **uid as the draw's sourceId**.

### Measured

```
granted 2 instances
  first uid=Common-1795574978-1  tier=Common  src=mission:test  ts=1795574978
  held Common=2

opened: rolled=1  held=1  instances left=1
  GF_CacheOpened = "Common:1:Common-1795574978-1"      <- the draw names the instance
```

So a draw is traceable to the specific cache it came from, and the draw is computed **once** and handed to `open` as `preRolled`.

## What `S11-031` still lacks

Marked **PARTIAL** rather than VERIFIED, deliberately:

- **"idempotent transaction"** — the consume-before-open ordering gives at-most-once behaviour (a retry finds no instance and no held
  count), but it is not a crash-atomic transaction and there is no journal. If the server died between removing the instance and
  granting the augment, the cache would be lost with no record to reconcile.
- **"if UI disconnects, results already in inventory"** — true because grants happen server-side before any client response, but not
  deliberately tested by killing the client mid-open.
- **The 50-instance cap is my invention.** Instances are an audit window, not an authoritative ledger; older caches silently lose their
  identity from the list while their count remains.
- Instances live in the profile, so they persist — but a profile that predates this change has counts with no matching instances, and
  `openFromInventory` then falls back to `"unknown"` as the draw source.

## Disclosed

The probe replaced `ownedAugments` with an empty table, set capacity to 200 then to the owned count, and restored both. It also wrote
`cacheInstances` and `caches.Common` on the test profile.

## Ledger

`625 UNKNOWN · 157 PARTIAL · 33 VERIFIED · 0 ABSENT` — the ABSENT bucket is now empty for the first time. That is worth stating
plainly: it does not mean nothing is missing, only that everything missing is now *understood and recorded* rather than unknown.
