# HUD reserve display: wired but NOT verified (place 539)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 539**.

## What was attempted

`S04-027` requires limited ammo/reserve to be real in play. Reserve reloading works (verified last batch), but the player cannot see a reserve count. This batch
wired the display end to end:

- `HUD.setAmmo(ammo, magazine, reserve?)` renders `"27 / 28  ·  168"` when reserve is a number, and falls back to `"28 / 28"` when it is not.
- All **six** client `HUD.setAmmo` call sites now pass `state.reserve` (they previously passed two arguments, so a third would have been ignored).
- The client stores `state.reserve` from both `AmmoUpdated` and `WeaponEquipped` payloads.
- The server now includes `reserve` in the `WeaponEquipped` payload, in both single-line `AmmoUpdated` payloads, and in the reload commit payload.
- `State`'s default reserve is seeded from the AR01 catalogue value instead of a literal `0`.
- `CombatService.ensureReserve(s, weapon)` centralises lazy seeding, called from `fire`, the reload handler and `publishAmmo`.

## What was observed

| run | label |
|---|---|
| initial | `28 / 28` |
| after client fire | `27 / 28` |
| after passing reserve through HUD | `27 / 28  ·  0` ← suffix appeared, value wrong |
| after seeding fixes | `28 / 28` — no suffix, and the shot did not register (`28`, not `27`) |

An instrumented read at the moment of firing showed the actual cause of the `· 0`:

```
weapon=AR01  catalogReserve=168  s.reserve=0
```

`s.reserve` was **already 0**, not nil, so `ensureReserve` (which only fills nil) never seeded it. `State`'s default had set `reserve = 0`, defeating the lazy path. That
default is now seeded from the catalogue — but the run after that fix did not produce a verified positive result: the label reverted to the two-part form and the
shot did not register.

**I am therefore not claiming the HUD reserve display works.** The suffix formatting was seen working (`· 0`), the plumbing compiles in all four scripts, and the
root cause of the `0` was identified and fixed — but no run ended with a non-zero reserve visible.

## Why this batch was stopped

Six iterations on the same display, each surfacing a new wiring gap (call sites → payload → defaults → lazy seed). The last observation (shot not registering) is a
*different* symptom from the one being chased, which means diagnosis restarted rather than progressed. Continuing would have burned budget without a verified claim.

## Current risk

The `State` default now calls into `ReplicatedStorage.GF.Shared.Configs.Weapons` inside a function expression during state construction. It compiles and the place
saved, but a require cycle or ordering problem there would only surface at runtime for a **new** player state — and no run since has exercised a fresh state with a
fresh spawn cleanly.

## Next step when resuming

1. Confirm a fresh spawn produces `s.reserve = 168` (one reader script, no firing).
2. Then confirm one client shot yields `27 / 28  ·  168`.
3. Then restore the reserve-limited and empty-reserve live cases that were left inconclusive two batches ago.

## Not done

- Supply crates and drops still do not replenish reserve — there is no supply-crate system at all, only comments referencing one.
- No cap on reserve accumulation.
