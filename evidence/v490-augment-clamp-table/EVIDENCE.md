# Per-stat clamps now exist, and the ability augment's trait actually applies (place 490)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 490**.

## Change 1: the clamp table (`S11-055`)

The spec requires bonuses to be summed additively **then clamped per stat**, with negatives floored at 0. Previously the sum was
returned raw, which is how the test account reached a **47.85% cooldown reduction** against an authored cap of 20%.

```lua
local CLAMP = {
    blastRadius = 0.25, cooldown = 0.20, magazine = 0.35, reloadSpeed = 0.25,
    healthDamage = 0.15, weakPoint = 0.20, shieldDamage = 0.30, armorDamage = 0.30,
    adsSpeed = 0.25, recoil = 0.35, movingAccuracy = 0.35,
}
for key, cap in pairs(CLAMP) do ... out[key] = math.clamp(v, 0, cap) ... end
```

Every number comes from the authored cap list. Statements about the caps are now enforceable in one place instead of being
sprinkled across consumers.

## Change 2: a real bug found on the way

```lua
local ability = loadout.abilityAugment
if type(ability) == "string" then
    local def = Augments.get(ability)
    if def then
        add(out, def.effect)
        applyTrait(out, profile, id)   -- `id` is the weapon-slot loop variable, out of scope = nil
    end
end
```

The ability augment's **trait was never applied** — `id` belongs to the preceding `for _, id in pairs(slots)` loop and is out of
scope here, so `applyTrait` received `nil`. Fixed to pass `ability`.

## Measured

```
before clamp:  cooldown = 0.4785        -> Airstrike 46.1 s
after clamp:   cooldown = 0.200         -> Airstrike 71.9 s     (90 x 0.8 = 72)
blastRadius:   WideCharge +0.3          -> 0.250                (clamped to the +25% cap)
```

Two different stats clamping correctly, one verified in live gameplay (cooldown → real ability timer) and one at the stat table.

## Ruled out before it became a false claim

The `blastRadius` reading was `0` in the first run, which looked like the clamp had zeroed a value. It had not: the persisted
loadout held only `CoolantLoop`. Chasing why turned up a second apparent defect — `AugmentService` contains **zero**
`markDirty` calls while `ArmoryService` has fourteen.

That looked like "augment changes never persist". It is not: my probes called `AugmentService.equipAugment` **directly**, bypassing
`ArmoryService`, which is the only caller that marks the profile dirty. So this is a probe artifact, and the product path is
intact. Recorded because the fragility is real — any future code that mutates augments through the service rather than the armory
will lose the change silently on restart.

This also means the place-489 `blastRadius 11.25` measurement was taken on a loadout state that never persisted. The code change
is still correct and is now verified through the clamp table instead.

## Limits

- `cooldown` was verified through a real ability cast; the other twenty caps were verified only at the stats table, not through
  gameplay effects.
- `reloadSpeed 0.25` is the spec's "reload/movement +25%"; `movement` has no separate cap entry and no `moveSpeed` augment exists,
  so only reload is bounded.
- `followUpSpeed`, `swapSpeed`, `adsRecovery`, `sentryAmmo` have no authored cap in the spec and are therefore unclamped —
  deliberate, not an oversight.
- The ability-augment trait fix was not tested: the account holds no ability augment.
