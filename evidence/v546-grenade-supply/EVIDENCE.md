# Grenades were already server-authoritative; the crate now refills them (place 546)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 546**.

## A false alarm I raised and then corrected

While auditing, my first search for the grenade throw handler returned **nothing**, and I was one step from recording *"grenades are client-side only, no server
authority"*. That would have been wrong: I had searched `GF.Services`, `StarterPlayer` and `ReplicatedStorage` — but `GrenadeRuntime` is a **`Script` at
`GF.GrenadeRuntime`**, outside the `Services` folder.

Reading it, the grenade system is **server-authoritative and complete**: `GrenadeCharges` per-player attribute, ownership check against `profile.ownedGrenades`, a
0.8 s throw cooldown, charge consumption on throw, a deterministic lob tween, fuse timing, and real damage — `CombatService.damageEnemy` for Frag,
shield/self-damage for EMP.

So the only thing actually missing was `+2 grenades` from the supply crate.

## Change

`SupplyService` gained:

```lua
function SupplyService.grenadePlan(current, max): number
    return math.min(cap, math.max(0, current) + GRENADES_PER_CRATE)   -- GRENADES_PER_CRATE = 2
end
```

`consume()` now reads the player's equipped grenade from `selectedLoadout.grenade`, takes its authored `count` (3) as the cap, and writes back to the same
`GrenadeCharges` attribute that `GrenadeRuntime` consumes from — so the two systems share one source of truth rather than duplicating it.

## Verified

```
charges 0 -> 2 -> 3 -> 3   (three crates in a row; max 3)
detail: Frag ... (max 3)
```

The first crate gives +2, the second tops to the cap, the third changes nothing. Three unit checks added (`0→2`, `2→3` capped, `3→3` never exceeds) — suite now
**`passed=667 failed=17 nonDrift=0`**.

## `S08-047` clause by clause

| clause | status |
|---|---|
| enemy drops no weapons | holds — no weapon-drop code exists anywhere; enemies roll caches via `enemyChance` |
| ammo/grenades personal | `State.reserve` per player; `GrenadeCharges` per-player attribute |
| per-player one-use crate | verified — second consume refused `"already used"`, crate destroyed |
| full mag + reserve to +60% | verified — ammo 4→28, reserve 20→188, cap 268 |
| +2 grenades | verified — 0→2→3→3 |
| no repeated use | verified |

Row moves to VERIFIED.

## Limits

- One player, one equipped grenade kind (`Frag`); the EMP path was not exercised through the crate.
- The crate writes `GrenadeCharges` directly rather than calling `GrenadeRuntime`'s own refill helper (`_G.GrenadeRefill`, which refills to max). That keeps
  "+2 capped" distinct from "full refill", but means two code paths can now touch the same attribute.
- `S04-053` (grenade damage/radius/fuse stats) is unaffected and stays PARTIAL.
