# Supply crates exist — but nothing spawns them yet (place 543)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 543**.

## Why

`S04-027` requires *"limited ammo/reserve **and supply**"*. After the reserve work the first half was verified, but there was **no supply system at all** — only
comments referring to one. That made the build stricter than authored: a player who runs dry can never recover.

## Built

`ServerScriptService.GF.Services.SupplyService`:

- **`refillPlan(ammo, magazine, reserve, catalogReserve)`** — pure. Fills the magazine and adds one catalogue charge of reserve, capped at **+60%**
  (`RESERVE_CAP_MULTIPLIER = 1.6`), never reducing either value.
- **`consume(player, crate)`** — applies the plan to live `State`, clears `reloading`, marks the crate `Consumed`, destroys it, publishes
  `GF_SupplyRefill`, and pushes `AmmoUpdated` so the HUD reflects the new reserve.
- **`spawn(position)`** — a one-use crate part with a `ProximityPrompt` ("Resupply / Ammunition", 0.4 s hold, 8 stud range) whose `Triggered` calls `consume`.

## Verified live

```
before:  ammo 4   reserve 20
consume: ok=true  ammo 28  reserve 188        (20 + 168, under the 268 cap)
consume again: ok=false  why="already used"   crate destroyed
```

Ammo refilled to the magazine, reserve topped by exactly one catalogue charge, and the second attempt on the same crate was refused.

## Verified by unit checks

Four assertions added to `DamageChecks` (suite now **`passed=664 failed=17 nonDrift=0`**): magazine refill, reserve top-up, the +60% cap, and "never reduces".

## The gap that keeps this PARTIAL

**Nothing spawns a crate in a mission.** A search for `SupplyService` outside its own module returns exactly one hit — `DamageChecks`. So the mechanism is real
and tested, but **unreachable in play**: no mission, loot table or encounter places a crate.

That distinction matters: `S04-027`'s "supply" clause is now *implemented* but not *integrated*. Recording it as PARTIAL rather than VERIFIED for that reason.

## Also still missing

- **Grenades are not refilled.** There is no grenade-charge state anywhere in the project (`State` has none; a comment referencing "three throws then empty"
  in a module that does not exist). Adding `+2 grenades` would require inventing that state first — deliberately not done, since the cap and consumption rules
  are unspecified in the code.
- Crates are not cleaned up between missions (they are destroyed on use, but an unused crate persists).
- No visual/audio feedback on resupply beyond the prompt itself.

## Next step

Wire `SupplyService.spawn` into mission setup or the loot path so crates actually appear, then verify a player can run dry and recover in a live mission.
