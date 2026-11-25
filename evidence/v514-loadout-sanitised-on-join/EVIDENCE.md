# Saved loadouts are now repaired on join (place 514)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 514**.

## The gap this closes

Place 512 enforced augment compatibility at **equip** time. But a loadout saved before that change keeps its effect until the player unequips —
nothing validated slots on load. So a player who had equipped a shotgun augment on a rifle before the fix would still be carrying it.

## Change

`AugmentService.sanitiseLoadout(profile)` clears any slot whose augment no longer fits the equipped primary, and `ArmoryService` calls it on
`PlayerAdded` before serving the loadout, marking the profile dirty when it clears anything.

Three placement decisions worth stating:

- **It lives in `AugmentService`, not `ProfileService`.** `AugmentService` already requires `ProfileService`, so hooking it on load would create a
  circular require. `ArmoryService` sits above both and is the right caller.
- **Slots are one table per loadout**, not per weapon, so the equipped **primary** is the weapon a slot is judged against.
- **It is idempotent and only removes**, never reassigns — a mismatched augment is dropped rather than silently moved to another weapon.

## Measured

```
before: 1=Choke,2=StabilityCompensator      (primary=SMG03)
cleared=1
after:  2=StabilityCompensator
secondRunCleared=0
```

The shotgun-only `Choke` was removed from an SMG primary, the `Universal` `StabilityCompensator` survived untouched, and a second call cleared
nothing — so the repair cannot loop or strip legitimate augments.

## Limits

- The `PlayerAdded` path itself was **not** exercised: the probe called `sanitiseLoadout` directly. I verified the repair logic, not that a real
  rejoin triggers it — that needs a client disconnect/reconnect or a fresh server.
- Removal is silent to the player. `GF_AugmentSanitised` and `GF_AugmentSanitisedCount` record it for a developer, but a returning player whose
  augment vanished gets no explanation. A message would be better and is not implemented.
- The augment stays **owned** — only the slot is cleared — so it can be re-equipped on a compatible weapon. That is intentional but unverified from
  the player's side.
- Nothing validates `loadout.abilityAugment` (the ability socket) in this pass.
- If the primary weapon is missing from config, `primary` is nil and every `Category` augment is cleared. Defensive, but it would strip valid slots
  in a data error — worth knowing before adding weapons.
