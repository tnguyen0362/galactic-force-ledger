# Supply crates now spawn with missions — supply is reachable in play (place 545)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 545**.

## What was missing

Last batch built a working crate but found that **nothing spawned one**: a search for `SupplyService` outside its own module returned only the test suite. The
mechanism existed and was unreachable.

## Integration added

`SupplyService` gained a mission lifecycle:

- **`placeMissionCrates()`** — places **3** crates around the squad's insertion point, each snapped to the ground by raycast. Placement is relative to the first
  player's position rather than authored POIs, because no objective position feed is published for arbitrary objectives; three per mission matches the authored
  sparse-supply feel.
- **`clearCrates()`** — destroys any surviving crates and resets the count.
- **`count()`** — live crate count for tests.
- **`start()`** — watches `GF_InMission`: true places crates, false clears them.

Wired into `Main` alongside the other service starts.

## Verified

```
in mission:  attribute=3  count=3  inWorld=3
after end:   attribute=0  inWorld=0
```

Crates appear when a mission begins and are cleaned up when it ends — no leftover props across missions.

Combined with last batch's live test (`ammo 4 → 28`, `reserve 20 → 188`, second use refused, crate destroyed), the full player-facing path now exists:
mission starts → crates appear → a player at low ammo presses Resupply → magazine fills, reserve tops up to the +60% cap → the crate is gone.

## `S04-027` → VERIFIED

All three clauses hold: limited ammo/reserve (refill, reserve-limited, empty-refusal, HUD display), **supply** (spawns per mission, one-use, capped), and no paid ammo
advantages (zero monetisation anywhere).

## What this does *not* cover

- **Grenade resupply** belongs to `S08-047` ("ammo/grenades personal, per-player one-use supply crates … +2 grenades") and `S04-053` (grenade caps), both still
  open. There is **no grenade-charge state in the project at all**, so `+2 grenades` cannot be given yet — that needs the state invented first.
- Crates are placed once per mission start; there is no drop-based supply, no per-crate contents variation, and no visual/audio feedback beyond the prompt.
- Only one player position is used as the anchor, so in co-op a distant player could spawn far from the crates. Single-player verified only.
