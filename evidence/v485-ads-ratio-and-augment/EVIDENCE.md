# `AdsSpeed` is now exactly 0.8× walk, and the `adsSpeed` augment finally does something (place 485)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 485**.

## Two loose ends from the ADS batch

### 1. `AdsSpeed = 13` was 0.74× walk, not the spec's 0.8×

The specification states a **ratio**: *"ADS speed 0.8× walk"*. `0.8 × 17.5 = 14`, so the literal 13 implemented 0.74×. Changed to
**14** with the arithmetic in a comment. `Constants` cannot reference its own sibling field during table construction, so it
stays a literal — but the derivation is now written down where the number lives.

Measured: `aim on -> true:14` (was `true:13`).

### 2. The `adsSpeed` augment stat was inert — now applied, with a sign decision

**Correction to my own place-482 evidence.** I wrote that no augment effect reached the player and implied the stat could be
rolled but did nothing. Half right: nothing consumed it, and exactly **one** augment rolls it —
`StabilityCompensator = -0.08`. My first scan said "0 augments use adsSpeed", which was a **false negative**: I read
`e.stats`, but the field is `e.effect`. Third time in this session that a wrong field name produced "nothing exists".

Fixed the scan and got the real key census:

```
recoil 8 · weakPoint 8 · healthDamage 7 · armorDamage 5 · blastRadius 4 · reloadSpeed 4 · swapSpeed 4
cooldown 3 · magazine 3 · adsRecovery 2 · followUpSpeed 2 · movingAccuracy 2 · sentryAmmo 2 · adsSpeed 1
```

**The sign convention is a judgement, and I recorded it as one.** `StabilityCompensator` carries a *negative* value and is named a
compensator, so a negative must make aiming *less* restrictive. Hence:

```lua
humanoid.WalkSpeed = Constants.Movement.AdsSpeed * math.max(0.25, 1 - bonus)
```

`1 - bonus`, not `1 + bonus`. The spec says nothing about this stat, so this is my reading, argued from the augment's own name
and value. It is commented in the code as such.

## Measured with the real augment equipped

```
prep:   adsSpeed = -0.08        (grant=false: already owned; equip(AR01)=true)
aim on: true:15.12              = 14 * (1 - (-0.08))
aim off: false:17.5
```

15.12 is the number that proves the whole chain: constant 14 → augment multiplier → walk speed. Before this batch that augment
was a paid item with no effect.

## Honest limits

- **The sign convention is unverified against intent.** If the author meant `adsSpeed = -0.08` to make aiming *slower*, my
  implementation is inverted and one line flips it. Nothing in the spec or the config comment resolves it.
- `math.max(0.25, ...)` floors the modifier at a quarter of ADS speed, which is my invention to avoid a negative or zero
  WalkSpeed from a pathological augment stack. No augment can reach it today.
- Only `AR01` was equipped; the augment is a Core socket so category gating was not exercised.
- The other 13 effect keys remain unconsumed in the movement path — `recoil`, `magazine`, `weakPoint` etc. have consumers
  elsewhere, but I did not verify each one in this batch.
- Practical risk: the test account now **owns and has equipped** `StabilityCompensator` on `AR01`, which persists.
