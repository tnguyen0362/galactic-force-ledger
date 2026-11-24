# Three saved loadouts (build 417)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## What existed
`ProfileService.defaults` carried a `savedLoadouts = {}` field, and **nothing ever wrote or read it** — there were no loadout slots at all, only the single `selectedLoadout`. Three saved loadouts is a core-inventory item.

## Implemented
In `ArmoryService`:
- `saveLoadout(player, slot)` copies the live loadout into `profile.savedLoadouts[slot]` (1–3) and persists.
- `loadLoadout(player, slot)` restores the copy into `selectedLoadout` and calls `CombatService.applyLoadout`, so the weapon in hand changes — not just the menu.
- Both are reachable through `SetLoadout` as `{ action = "saveLoadout", slot = n }` and `{ action = "loadLoadout", slot = n }`.
- Slot bounds are refused (`loadout slot must be 1-3`), and an unused slot is refused (`loadout slot is empty`).

Copy semantics are per-key with a one-level table copy, so the two slots do not share the `weaponAugments` table.

## Measured
| Step | Result |
|---|---|
| Equip `SMG03` | `WeaponEquipped.weaponId = "SMG03"` |
| Save slot 1 | `GF_LoadoutSaved = 1` |
| Equip `AR01` | `WeaponEquipped.weaponId = "AR01"` |
| Load slot 1 | `GF_LoadoutLoaded = 1`, `WeaponEquipped.weaponId = "SMG03"` |
| Load slot 2 (never saved) | `ok=false`, `loadout slot is empty` |
| Save slot 4 | `ok=false`, `loadout slot must be 1-3` |
| Save `AR01` to slot 2, then load slot 2 | `ok=true` |
| Load slot 1 again | weapon returns to `SMG03` — slot 1 was not overwritten by slot 2 |

## Limits
- Loading has been driven **only through the `SetLoadout` payload**; the Armory UI has no slot buttons yet, so a player cannot reach this.
- No UI indicates which slot is active, and no slot is labelled.
- Persistence across a rejoin was not tested — `savedLoadouts` is written to the profile and marked dirty, but no reconnect occurred.
- Only weapons and the tables they carry were exercised; class, grenade and armor fields are copied but unverified.
- Equipping the same augment across two loadouts (`S10-040`) and loadout validity on dismantle (`S10-042`) are untouched.
