# Shield model rewritten to the authored formula (place 527)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 527**.

## The two defects being fixed

Both were measured in the previous batch and both were **ordering** bugs inside `CombatService.damageEnemy`:

1. **The head multiplier was applied to shields** — a headshot drained 36 from a shield instead of 18, against the spec's *"no ordinary head bonus on shield"*.
2. **The armour factor was applied to shield damage** — `amount = amount * armorFactor` ran *before* the shield branch, so a shielded Heavy had shields 25% tougher
   than authored, against *"Enemy armor multiplier on health only"*.

## What the code now does

`S04-018`'s formula, implemented directly:

```lua
local hitMultiplier = tonumber(mult) or 1
local raw = amount / hitMultiplier          -- fire() passed base * falloff * hitMultiplier
-- augments that scale damage, applied to raw
if shield > 0 then
    local shieldRaw = raw * (1 + augs.shieldDamage)
    local absorbed = math.min(shield, shieldRaw)
    shield -= absorbed
    shieldRaw -= absorbed
    healthDamage = shieldRaw * hitMultiplier * armorFactor     -- only the overflow sees mult + armour
else
    healthDamage = raw * hitMultiplier * armorFactor
end
```

Recovering `raw` by dividing out the hit multiplier is what makes the spec's two-phase model expressible: the shield takes pre-multiplier damage, health takes
post-multiplier-and-armour damage, and the same raw damage is never charged twice.

## Measured after the change

```
head + shield 100:              shield 100 -> 82   health untouched      (-18, no head bonus)
body + armour 0.5 + shield 100: shield 100 -> 82   health untouched      (-18, armour not on shield)
body + armour 0.5 + health:     health 5000 -> 4991                     (-9 = 18 × 0.5)
overflow: shield 10, armour .5: shield 10 -> 0, health 5000 -> 4996      (-4 = (18-10) × 0.5)
```

Every case matches the authored rule, including the overflow case the spec spells out explicitly (*"consume only `shieldBefore/shieldFactor` raw damage, then
apply hitMultiplier and armorFactor to remaining raw"*).

## Behaviour change to expect

- **Shields break faster.** Against `ArmorFactor 0.75` enemies the shield layer is now 25% weaker than before this change, which is the authored value.
- **Headshots no longer shred shields** — 18 instead of 36 against a shielded Rifleman, so breaking an 80-point shield takes 5 body shots / 5 headshots rather
  than 3.
- **Every shielded TTK figure recorded earlier in this project is now stale.** Unshielded numbers are unchanged (the `else` branch reproduces the old maths
  exactly, which case 3 confirms).

## Not done

- **No `shieldFactor` field exists.** The spec's `shieldFactor` is treated as **1**; the only shield-side modifier is the `shieldDamage` augment. If a
  per-archetype shield factor is intended, it needs authoring.
- **`S04-021` still asks for unit tests.** This is verified by ad-hoc probe, not by a regression test, so a future edit could silently undo it. That gap is
  unchanged and now more important, because the maths is more intricate.

## Limits

- One archetype, one weapon, one range; armour forced to 0.5 for the test rather than using a real Heavy's 0.75.
- Overseer conditions: `GF_InMission` forced true, rig anchored, aim origins found by search rather than by a player aiming.
- Damage read from `Health`/`Shield` attributes; augment-scaled paths (`weakPoint`, `armorDamage`, `healthDamage`, `shieldDamage`) were **not** exercised with a
  player carrying augments.
