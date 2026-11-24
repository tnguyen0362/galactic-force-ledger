# Grenade charges refill per deployment (build 429)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## The gap
Charges were a one-way resource: three throws and the player had none for the rest of the session, because nothing ever refilled them. The spec treats three as the per-mission supply.

## Implemented
- `refill(player)` in `GrenadeRuntime` sets `GrenadeCharges` to the equipped grenade's `count` (3 for both types), publishes `GFDebug.LastGrenadeRefill`, and reads the equipped type from the profile with the `Frag` fallback.
- `StationService.deploy` calls it, so every deployment restocks.
- Armory grenade rows now render `BUY` for unowned types and `EQUIP` for owned ones; `state.ownedGrenades` exposes ownership.

## Measured
| Check | Result |
|---|---|
| Throw three Frags at the station | `GrenadeCharges` 3 → 0 |
| Deploy a mission | **`GrenadeCharges = 3`**, `GFDebug.LastGrenadeRefill = 3` |
| `state.grenades` / `state.ownedGrenades` | `{EMP, Frag}` / `{EMP, Frag}` |

So the supply is per deployment now, not per session.

## Limits
- **The BUY branch is unverified.** Both grenade types are already owned on this profile, so every row renders `EQUIP`. The purchase path itself was verified last build through the remote; the *button* for an unowned type has never been seen or clicked.
- Refill happens on deploy only — returning to the station between missions does not restock until the next deployment, which may or may not be the intended cadence.
- The refill runs inside a `pcall` with a `_G` handoff (a Script cannot be required); if it fails it fails silently. Nothing currently proves it would survive a refactor.
- Throw arc, fuse timing and preview remain unmeasured.
