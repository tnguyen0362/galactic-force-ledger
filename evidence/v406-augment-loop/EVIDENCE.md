# Augment purchase loop, HUD magazine, and a retraction (build 406)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`. Server and `PlayerGui` reads.

## Retraction: the "repeat purchases fail" defect was wrong
Build 404's evidence claimed that after the first purchase in a category, further `augmentBuy` calls did nothing. That was an **instrumentation error**: `GF_AugmentBought` records only the last purchase, so three successful buys looked like one.

Measured ownership after the buys shows the loop works and the roll excludes owned archetypes:
`Choke`, `ShellRack`, `SlugLoad` (Shotgun) · `PrecisionChamber`, `StableStock` (Marksman) · `BeltFeed` (LMG) · `WideCharge`, `ShapedWarhead`, `ArmorPiercer` (Launcher/Marksman) · `StabilityCompensator` — 10 owned, no duplicates within a category.

## Real fix 1: armory refusals were silent
`fail()` pushed a client message but recorded nothing server-side, and only the `augment` action wrote `GF_AugmentRejected`. Every refusal now sets `GF_ArmoryRejected`.
Measured with an exhausted pool: a fourth Shotgun purchase returned `GF_ArmoryRejected = "no augment left in that category"` and left the owned set unchanged.

## Real fix 2: the HUD divided by the wrong magazine
`WeaponEquipped` sent `magazine = weapon.magazine` (catalog 75 for LMG-12) while `ammo` was the augment-modified capacity (**116**), so the ammo bar would read `116 / 75`. `applyLoadout` now computes the effective capacity once and sends it for both fields.
Measured after the fix: `{ ammo = 116, magazine = 116, weaponId = "LMG12" }` — same shot, HUD denominator correct.

## Also learned
A `string.find` on `s.ammo = require(...).magazine(...)` matched the **reload branch inside `fire()`** first, not `applyLoadout`, so the first patch fixed nothing and left `effectiveMagazine` nil in the payload (the field silently disappeared from the RemoteEvent table). Anchor on surrounding context, not on a line that exists twice.

## Limits
- Rarity still changes only cost and roll weight (`S11-037` unverified).
- Cache tiers do not consume these pools.
- No Armory category selector in the UI; category arrives on the payload.
- Rolled trait values are applied to stats but never shown to the player.
