# Shield routing is correct; two authored shield rules are violated (place 522)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Verification only; no source changes.

## Method

Same combat harness as the headshot batch: mission active, rig anchored, player stood beside the target, and an aim origin chosen only where the **first**
raycast hit is the intended part. Three shield states and two armour states measured on one `Rifleman`, AR01 (18 base).

## What is correct

```
overflow(shield 10):   shield 10 -> 0    health 5000 -> 4992    (-8 exactly = 18 - 10)
shieldOnly(shield 40): shield 40 -> 22   health 5000 -> 5000    (-18, health untouched)
noShield(shield 0):    shield 0 -> 0     health 5000 -> 4982    (-18)
```

- **Shield absorbs first** and health is untouched while any shield remains.
- **Overflow is exact**: 18 damage against 10 shield removes the shield and takes exactly 8 from health, with no double-charging.
- Body damage against health is the base value.

That satisfies the arithmetic half of `S04-015` and the "same raw damage is never charged twice" intent of `S04-021`.

## What is wrong — two authored rules violated

**1. The head multiplier IS applied to shields.**

```
HEAD vs shield 100:  shield 100 -> 64     (-36, i.e. 18 × 2.00)
```

The spec is explicit: *"Shield first, **no ordinary head bonus on shield**; overflow damage to health."* A headshot should drain **18** from a shield, not 36.
Because `fire` pre-multiplies damage and `damageEnemy` receives the final amount, the head bonus is baked in before the shield branch ever runs.

**2. The armour factor IS applied to shield damage.**

```
ARMOR 0.5 + shield 100:  shield 100 -> 91   (-9, i.e. 18 × 0.5)
ARMOR 0.5 + health:      health 5000 -> 4991 (-9)
```

Spec line 47: *"Enemy **armor multiplier on health only**."* Here armour halves shield damage too. The cause is ordering in `damageEnemy`:

```lua
local armorFactor = tonumber(model:GetAttribute("ArmorFactor"))
if armorFactor and armorFactor > 0 and armorFactor < 1 then
    amount = amount * armorFactor          -- applied BEFORE the shield branch
end
if shield > 0 then ... absorb ... end
```

**3. There is no `shieldFactor` at all.** `S04-018` describes *"Apply shield-specific factor to raw damage against shield first; if shield breaks, consume
only `shieldBefore/shieldFactor` raw damage, then apply hitMultiplier and armorFactor to remaining raw damage against health."* The build has no shield
factor field and no raw-versus-mentioned-damage split; it applies augment `shieldDamage`, then armour, then absorbs. The spec's formula is unimplemented in
structure, not merely mistuned in value.

## Why this matters in play

Against a shielded Heavy (`ArmorFactor 0.75`) the build's shields are **25% tougher than authored** while its health is correct, and headshots against shields
are worth **double**. Both make the shield-break phase — the part of a Heavy fight that is supposed to be the fast opening — slower than authored. On the
Rifleman measured here, breaking 80 shield takes 4 AR shots as built versus 3 as authored.

## Not changed

Fixing this reorders `damageEnemy`'s maths: armour must move after absorption, and hit multiplier must be excluded from the shield portion. That changes every
TTK number against shielded enemies — including figures already recorded in this project — so it belongs with the owner's balance pass, not an autonomous
edit. The measurements are the contribution.

## Limits

- One archetype (`Rifleman`, `ArmorFactor` forced to 0.5 for the armour case), one weapon, one range, shield-only and health-only states.
- Overseer conditions apply: `GF_InMission` forced true, rig anchored, origin searched rather than aimed by a player.
- Damage numbers were read from `Health`/`Shield` attributes, not from the damage feedback remote.
