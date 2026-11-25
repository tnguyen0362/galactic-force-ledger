# The shotgun now fires eight pellets (place 508)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 508**.

## What was wrong

`SG-04` was authored as **8 pellets × 12 damage** but fired a **single ray applying 96**. No graded damage at range, no per-pellet falloff,
no pellet scatter — either 96 landed or nothing did.

## The decision, resolved from the data rather than guessed

Pellets needed a ruling on whether partial hits stack. The spec settles it: `12/pellet × 8 = 96`, and the config already carries
`damage = 96`. For the point-blank total to be 96, all eight pellets must stack on the same target. So `damagePerPellet = damage / pellets`
reproduces the authored total exactly while making each pellet independent.

## Change

`Configs/Weapons`: `SG04` gains `pellets = 8`.

`CombatService.fire`: the raycast-and-damage section is now a loop over `pellets`:

- pellet 1 uses the already-spread direction; pellets 2..N scatter around it using the weapon's own `adsSpread`/`spreadBase`
- each pellet raycasts independently, resolves its own enemy or structure, and applies its own falloff
- damage per pellet is `weapon.damage / pellets`
- non-pellet weapons have `pellets = 1`, so `damagePerPellet == weapon.damage` and the path is behaviourally identical to before

## Measured

```
SG04 pellets field=8  damage=96
pellet markers observed=8   first=8/8 hit=false dmgEach=12.00   last=8/8 hit=false dmgEach=12.00
```

Eight independent rays fired from one trigger pull, each carrying **12.00** damage — exactly the authored per-pellet figure, summing to the
authored 96. The probe fired into empty space, so `hit=false` throughout is correct.

## A mistake made and fixed inside this batch

The splice inserted five lines with a literal `[[` prefix, producing `Expected identifier when parsing expression, got malformed string` at
line 424. `loadstring` caught it before anything ran; the prefixes were stripped and the file recompiled. The cause was my own multi-line
string assembly, not the edit logic — and it briefly left `CombatService` unparseable, which is why the compile check after every edit matters
even for "mechanical" changes.

The first verification also reported `pellet markers observed=0`, which looked like the loop not running. It was my instrumentation: the marker
was published inside the `enemyModel` branch, so a shot into empty space produced nothing. Moved to the ray itself.

## Limits

- **Not measured against a real enemy.** No target was in front of the muzzle, so I verified 8 rays × 12 damage were *emitted*, not that a target
  receives 96 or that partial pellet hits damage correctly. That is the honest boundary of this evidence.
- Per-pellet **penetration, headshots and weak-point multipliers** interact with `weakMultiplier` per pellet and were not tested.
- Shootgun TTK evidence recorded earlier in this project is now **stale** — it was measured when one ray dealt 96.
- Pellets were added only to `SG04`; no other weapon sets the field.
