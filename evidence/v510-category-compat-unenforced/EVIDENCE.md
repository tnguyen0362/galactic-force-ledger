# Category compatibility is never enforced: a shotgun augment works on a rifle (place 510)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. No source changes.

## The finding

Every augment carries an `applies` field with one of three values:

```
Ability(4)   Category(28)   Universal(4)
```

`AugmentService` contains **zero** checks involving `applies` or `incompatible`. Its only consumer anywhere is cosmetic:

```lua
description = def.applies or "",
```

So the field is validated as a legal string by `CheckRunner` (`ALLOWED_AUG_APPLIES[a.applies] == true`) and then never used to restrict anything.

## Verified, not inferred

```
aug=Choke  applies=Category  cat=Shotgun
weapon=AR01  cat=Rifle
equipAccepted=true   why=nil   effectsInForce=1
```

`Choke` is a shotgun weak-point augment. It equipped onto an **assault rifle** and its effect took force. 28 of the 36 archetypes are `Category`
augments, so this is the majority of the catalog behaving as universal.

## Why it matters

- **Weapon identity collapses.** A shotgun-only weak-point bonus on a rifle is exactly the kind of thing that makes build choice meaningless — the
  restriction exists in data and is invisible in play.
- **It is a paid-trait problem in reverse.** Earlier this session I found augments that *do nothing*; this is the mirror: augments that *do
  something they were explicitly not meant to*.
- **The UI shows the restriction and does not enforce it.** `ArmoryService` displays `applies` as the augment description, so the player is told
  "Category" — or the category name — while the server accepts it anywhere. That is worse than silence.

## What enforcement would need

A check in `AugmentService.equipAugment`: when `def.applies == "Category"`, require the target weapon's `category` to match `def.category`; when
`applies == "Ability"`, require the slot's owner to be an ability. That is a handful of lines at a single choke point which already exists.

## Not implemented

Deliberately. Enforcing it **removes power from every existing loadout holding a mismatched augment** — including the test profile, which now
carries a shotgun `Choke` on `AR01` from this very probe. That is a behaviour change a player would feel immediately, and it belongs with the
balance pass rather than an autonomous edit. Recorded with the exact repro.

## Confidence

High — the equip returned `true` with no reason and `forPlayer` reported the effect live. Not tested: the `Ability` variant on a weapon slot, and
whether any UI path bypasses `equipAugment` entirely.
