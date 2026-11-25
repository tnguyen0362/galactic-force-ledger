# The ability socket is validated too (place 515)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 515**.

## What was left open

Place 514's sanitiser repaired **weapon** slots only. `loadout.abilityAugment` — the ability socket — was untouched, so a Category augment parked
there would survive every join.

## Change

Four lines added to `AugmentService.sanitiseLoadout`:

```lua
local abilityId = loadout.abilityAugment
if type(abilityId) == "string" then
    local def = Augments.get(abilityId)
    if def and def.applies == "Category" then
        loadout.abilityAugment = nil
        cleared += 1
    end
end
```

**`Category` is the only refused class.** `Ability` augments obviously belong there, and `Universal` is allowed to fit anything — refusing those
would be inventing a restriction the data does not express.

The cleared value also counts toward `GF_AugmentSanitisedCount`, so a join that repairs both a weapon slot and the ability socket reports `2`, not `1`.

## Measured

```
planted abilityAugment=Choke      (applies = Category)
cleared=1
after  abilityAugment=nil
detail="Choke from ability socket"

valid ExtendedSentryMagazine kept=true  cleared=0     (applies = Ability)
```

The Category augment was removed and the valid Ability augment survived untouched — so the check discriminates rather than clearing the socket
wholesale.

## What is still not right

- **The player is still not told.** `GF_AugmentSanitised` records it for a developer; a returning player whose ability augment vanished gets no
  explanation. Same UX gap as the weapon slots, now on a second socket.
- **Only `Category` is refused.** If the design intends `Universal` augments to be weapon-only, this under-enforces. Nothing in the config says so,
  which is why I did not guess.
- **Mismatches made while connected are still not repaired** — join-time only.
- The `PlayerAdded` path for *this* branch was not re-run across a restart. The weapon-slot equivalent was verified end to end at place 514, and this
  is the same function, but I am not claiming a restart test I did not perform.
