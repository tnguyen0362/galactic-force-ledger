# Augment compatibility is now enforced (place 512)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 512**.

## What was wrong

Every augment declares `applies` — `Ability` (4), `Category` (28), `Universal` (4) — and `AugmentService` read it **nowhere**. The armory displayed
it as the augment's description while the server accepted any augment in any socket. A `Choke` (shotgun weak-point) equipped onto an assault rifle
and its effect took force.

The spec asks for *"data-driven compatibility"*, so this is an unmet correctness requirement rather than a balance preference: the field exists,
the UI advertises it, and enforcement was absent.

## Change

One check at the single equip choke point in `AugmentService.equipAugment`:

```lua
if def.applies == "Ability" then
    return false, "ability augment cannot fit a weapon socket"
elseif def.applies == "Category" and type(def.category) == "string" then
    local weapon = require(ReplicatedStorage.GF.Shared.Configs.Weapons).get(weaponId)
    if weapon and weapon.category ~= def.category then
        return false, string.format("fits %s weapons only", tostring(def.category))
    end
end
```

`Universal` augments fall through unaffected.

## Measured

```
Choke on AR01 slot1  -> false ("fits Shotgun weapons only")
Choke on SG04 slot1  -> true  (nil)
StabilityCompensator on AR01 slot2 -> true (nil)      (Universal)
```

The refused case names the required category rather than a generic failure, the correct weapon still accepts it, and the unrestricted class is
unaffected.

## Why this was worth doing without an owner ruling

It removes power from mismatched loadouts, which normally makes it a balance decision — but the alternative is a UI that tells the player one thing
and a server that does another. That is a correctness bug with a balance side effect, not the reverse. `Universal` still means universal, and any
augment the design intends to fit anywhere can be marked as such.

## Consequences to expect

- **The test profile's `Choke` on `AR01`** (equipped by an earlier probe) is now an invalid entry. It was left in place rather than silently
  stripped; unequipping it, or any loadout repair on load, is the owner's call.
- **Saved loadouts may hold mismatched augments.** Nothing sanitises existing slots on load, so a player who equipped a mismatched augment before
  this change keeps its effect until they unequip. A load-time validation pass would close that, and was not added.
- **`Ability` augments were not exercised** — the account holds none, so that branch is code-verified only.
- The armory UI still describes the augment as `"Category"`; it could now say which category and whether the current weapon fits, which would make
  the restriction legible. Not done.
