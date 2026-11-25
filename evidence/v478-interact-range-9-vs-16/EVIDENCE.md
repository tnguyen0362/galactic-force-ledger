# Interact range is 16 studs against an authored 9 — and `Combat.InteractRange` is dead (place 478)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, `ObjectiveService` and `Constants` read in Edit mode. No source
changes.

## What I set out to resolve

The previous batch left this open rather than guessing:

> *"`Combat.InteractRange` — not pinned numerically anywhere I could find. `v388`'s evidence mentions `INTERACT_RANGE (16
> studs)` while `Constants.Combat.InteractRange` is **10**."*

## What is actually true

There are **two separate things**, and only one of them is used:

| symbol | value | referenced by |
|---|---|---|
| `ObjectiveService` local `INTERACT_RANGE` | **16** | 7 call sites: crates, terminals, charge pads, and one at `+4` (= 20) |
| `Constants.Combat.InteractRange` | **10** | **nothing** — no module in `ServerScriptService.GF` reads it |

A full-text scan for `interact_range` / `interactrange` across every `LuaSourceContainer` under `ServerScriptService.GF` returned
seven hits, **all inside `ObjectiveService`**, all on its own local. The `Constants` entry is dead configuration.

So `v388` was right about 16 and `Constants` is simply unused — the two numbers were never in conflict, they were never both live.

## But 16 is wrong against the spec

`GOAL_2026-11-24.md`, verbatim:

> *"Interact instant on valid range **<=9 studs**/LOS except hacking/revive"*

The build allows objective interaction at **16 studs**, and one terminal path at **`INTERACT_RANGE + 4` = 20 studs**. That is
between 1.8× and 2.2× the authored reach.

Consequences worth stating plainly:

- A player can start a crate pickup, terminal hack or charge placement from nearly twice the intended distance, which makes
  objective interaction feel loose and lets a player avoid closing the distance the level design expects.
- The spec's "except hacking/revive" carve-out suggests those two are allowed a longer range; the build applies 16 uniformly to
  crates, pads and terminals alike, so the distinction is not implemented either way.
- `v388` measured crates as *"instant pickups inside `INTERACT_RANGE` (16 studs)"* — it verified the code's number, not the
  spec's. The behaviour was measured and still wrong.

## Not changed

Interaction distance is a feel parameter: tightening 16 → 9 means players must walk closer to every objective, which changes
pacing and combat pressure. Same class as launcher radius and boss HP — recorded with exact numbers, left for the owner.

Also deliberately not "fixed" by wiring the dead `Constants.Combat.InteractRange` (10) in: 10 is also wrong against 9, so
connecting it would have created a second wrong number in a live path while looking like a tidy-up.

## Addendum 2026-11-24

This row was previously marked ASSESSED with "interact instant on valid range <=9 studs/LOS except hacking/revive; two players
interacting simultaneously must not double-apply". That last clause — **two players interacting simultaneously must not
double-apply** — was not tested this batch and remains unproven.
