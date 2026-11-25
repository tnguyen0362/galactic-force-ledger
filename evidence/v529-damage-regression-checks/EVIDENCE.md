# Damage maths now has a regression guard — and CheckRunner caught a bug I shipped (place 529)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 529**.

## Why this batch

The shield model was rewritten last batch and I wrote plainly that its only guard was hand-run probes. A future edit could silently undo it. `S04-021` asks for
exactly this, so I built it.

## `GF.Test.DamageChecks`

A `ModuleScript` that runs **headless** — it builds a scratch `Model` carrying only the attributes `damageEnemy` reads (`Health`, `Shield`, `ArmorFactor`,
`Dead`), so no rig, no mission, no player vitals, no AI. It exercises the real numeric paths:

| # | case | assertion |
|---|---|---|
| 1 | unshielded body | health −18 |
| 2 | shield absorbs | shield −18, health −0 |
| 3 | headshot vs shield | shield −18 (**not** −36) |
| 4 | headshot vs health | health −36 |
| 5 | armour vs shield | shield −18 (armour is health-only) |
| 6 | armour vs health | health −9 |
| 7 | overflow (shield 10, armour 0.5) | shield −10, health −4 |
| 8 | no double charge | shield+health lost = 18 total |

Result: **8/8 passed.**

## Wired into the project's proof command

`CheckRunner.run()` now calls it, so the single run that "proves the project still works" covers combat damage:

```lua
local damageOk, damageErr = pcall(function()
    require(script.Parent.DamageChecks).run(ok)
end)
ok(damageOk, "damage checks failed to run: " .. tostring(damageErr))
```

## And that immediately caught one of mine

The first integrated run reported:

```
passed=648 failed=18
1) unregistered remote in folder: ClaimStarter
2) spec drift: RL09.radius = 12, spec says 10
...
```

**`ClaimStarter` was my own regression** from the starter-pick batch — I added a RemoteEvent without registering it in `Shared.Remotes.Names`, so nothing else
noticed. Fixed properly by registering it in the registry rather than by loosening the check.

I also broke `Remotes` once while fixing it (inserted the name at a quote that was not inside the `Names` table, producing
`Expected ',' after table constructor element`). Reverted by removing my exact insertion and re-applying it with a line-anchored edit.

After the fix:

```
passed=650 failed=17  nonDrift=0
```

All 17 remaining failures are the long-standing **spec drifts** already catalogued as owner decisions — RL09/GL22 radii, OrbitalStrike/Lance, Sentry,
ReflectiveBarrier, boss HP, downed timeout, revive duration, extraction countdown, pity target/chance. **Zero non-drift failures.**

## What `S04-021` still lacks

The row names three cases: *"partial shield overflow, **shield-only hits** and **component damage** so the same raw damage is never charged twice."*

- partial overflow — covered (case 7)
- shield-only hit — covered (case 2)
- **component damage** — **not covered.** Bosses and multi-part targets are not modelled by these checks, so the rule that area/多part damage is not counted
  twice on one target has no test.

That is why `S04-021` stays PARTIAL rather than VERIFIED.

## Limits

- No player attacker is passed, so the **augment-scaled** branches (`weakPoint`, `armorDamage`, `healthDamage`, `shieldDamage`) are not exercised.
- Values are literal expectations transcribed from the spec, not derived from config — correct here, but it means a deliberate retune makes these checks fail
  until updated. That is the intended trade for a regression guard.
- The checks do not run automatically on server start; they run inside `CheckRunner.run()`.
