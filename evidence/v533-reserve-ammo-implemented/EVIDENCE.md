# Reserve ammo implemented; the live commit still doesn't fire (place 533)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 533**.

## What changed

**`State`** gains `reserve`. **Equip** seeds it from the catalog (`weapon.reserve`), so the authored figures stop being dead data. **Reload** now uses the authored
arithmetic:

```lua
function CombatService.reloadPlan(ammo, capacity, reserve): number
    local room = math.max(0, (capacity or 0) - (ammo or 0))
    return math.min(room, math.max(0, reserve or 0))
end
```

The commit adds only `n` and consumes `n` from reserve; the handler also refuses to start a reload when the plan returns 0 (empty reserve); and `AmmoUpdated`
now publishes `reserve`.

`reloadPlan` is deliberately **pure** — the surrounding handler needs a player, a scheduler and a live state table, which is why the arithmetic has never been
testable before.

## Tested: arithmetic is sound

Four assertions added to `DamageChecks`, inside `CheckRunner.run()`:

```
reloadPlan(20, 28, 168) == 8      partial magazine, ample reserve
reloadPlan(0, 28, 10)   == 10     reserve-limited
reloadPlan(28, 28, 168) == 0      full magazine
reloadPlan(5, 28, 0)    == 0      no reserve
```

Result: **`passed=657 failed=17 nonDrift=0`** — four more passes than before, all 17 failures still the catalogued spec drifts.

## Not proven: the commit path

Driving a real reload through the `ReloadWeapon` remote with `ammo=19, reserve=168`:

```
reloadCount = 1        the handler ran and scheduled the commit
ammo = 19              unchanged
reserve = 168          unchanged
commit = nil           the instrumented commit line was never reached
```

So the handler starts a reload, and the delayed callback **never gets as far as** `live.reloading = false`. Two candidate causes, neither confirmed:

- the guard `if not live or live ~= s then return end` — if `State` replaces the table during the ~2 s window (respawn, loadout apply, profile load), the
  callback silently aborts; or
- `live.reloading` was already cleared by another path (equip sets `s.reloading = false`).

Either way this is a **real behavioural risk independent of reserve**: a reload can silently no-op if the state table is replaced mid-reload. The old code had
the same guard, so infinite ammo was masking it — a full magazine refill on an aborted commit still looked like "nothing happened, still full".

## Not done

- HUD: `reserve` is published but no client reads it, so the player still cannot see a reserve count.
- Supply crates and drops do not replenish reserve.
- No ceiling on reserve; nothing caps accumulation.

## Ledger effect

`S04-025` and `S04-027` stay **PARTIAL**: the arithmetic now exists and is unit-tested, but a live reload neither refills nor consumes, so the end-to-end claim is
not earned.

## Limits

- One weapon, one player; the reload was triggered by remote rather than by pressing a key.
- The instrumentation only reported that the commit line was never reached; it does not distinguish between the two candidate causes.
