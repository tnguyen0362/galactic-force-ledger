# Component-damage checks close `S04-021` (place 530)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 530**.

## What was missing

`S04-021` names three cases: *partial shield overflow, shield-only hits and **component damage*** so the same raw damage is never charged twice. The first two were
covered last batch; component damage — bosses and multipart targets — had no check.

## Added

Three assertions driving the real `CombatService.detonate`, against scratch models placed in `ActiveActors` (the folder `detonate` walks):

1. A **5-part target** at the blast centre loses **100 health — once**, not 500.
2. A second target **outside** the radius loses **0**.
3. `detonate` reports **1 hit**.

`detonate` resolves each model through its `PrimaryPart` and damages the model once, so multi-part targets cannot stack. The checks assert that behaviour rather
than trusting the reading.

## A wrong expectation, caught by the run

My first version placed every part — including `Body1`, the `PrimaryPart` — offset from the centre:

```lua
part.Position = origin + Vector3.new(index * 0.5, 0, 0)   -- Body1 sits 0.5 studs out
```

The check then failed with **health −97.5, expected −100**. That was **correct code**: `detonate` scales by `math.clamp(1 - distance / radius, 0.3, 1)`, so 0.5
studs inside a 20-stud blast gives exactly 0.975. The fixture was wrong, not the game — the same class of mistake that has produced most of the false findings
in this project. Fixed by putting `Body1` exactly on the centre and leaving a comment explaining why the offset breaks the expectation.

## Result

```
passed=653  failed=17  nonDrift=0
```

Eleven damage checks now run inside `CheckRunner.run()`: unshielded body, shield absorbs, headshot vs shield, headshot vs health, armour vs shield, armour vs
health, overflow, no-double-charge, area-once, out-of-radius, and hit count. All remaining failures are the 17 catalogued **spec drifts** awaiting owner
decisions.

## `S04-021` → VERIFIED

All three named cases are tested and passing, and the "never charged twice" invariant is asserted directly (shield + health lost = 18 exactly).

## Limits

- **Augment-scaled branches remain untested** — no player attacker is passed, so `weakPoint`, `armorDamage`, `healthDamage` and `shieldDamage` never run in
  these checks. That is the largest remaining hole in the damage suite.
- Only `detonate`'s model-level path is tested; projectile weapons that call it repeatedly are not.
- Boss-specific part coefficients (`S06-053`) are not modelled.
- Checks run on `CheckRunner.run()`, not automatically at server start.
