# CheckRunner now enforces authored spec conformance (place 465)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, fresh Play VM. Place saved as **version 465**.

## Why

Seven defects found across this audit were the same shape: **a config number silently disagreed with the specification**,
and nobody had compared them. Launcher radii, ability cooldowns, boss HP, blueprint pity, mastery cap. Every one was found by
a human reading a ledger, which is not a control.

`ServerScriptService.GF.Test.CheckRunner` already ran 369 assertions at boot and `Main` already printed pass/fail. It simply
had no idea what the specification says.

## What was added

A ninth section in `CheckRunner.run()` that transcribes the authored tables and asserts config against them:

- **8 weapons** — damage, RPM, magazine, reserve, reload, falloff start/end, falloff minimum (and explosive radius for launchers).
- **6 abilities** — the cooldowns and radii the spec states numerically (`GOAL_2026-11-24.md` L75–L78).
- **2 bosses** — base HP (`L101`–`L102`).

It publishes `GF_SpecDriftCount` and a readable `GF_SpecDrift` string, so drift is machine-readable rather than a log line
someone has to notice.

**Rank and cost are deliberately excluded.** The authored weapon table (`L52`–`L59`) and the prose arsenal list
(`L393`–`L397`) contradict each other on rank and cost for AR-01, SG-04, MR-07 and LMG-12 — for example the table gives
LMG-12 as rank 1 / 750 credits while the prose says rank 7 / ~1,400. The config follows the prose. Asserting those fields
would have produced four false positives and taught everyone to ignore the check.

## Measured result

`passed=625 failed=13` in a fresh Play VM.

```
- Augments: duplicate id FastHands
- spec drift: RL09.radius = 12, spec says 10
- spec drift: GL22.radius = 9, spec says 13
- spec drift: OrbitalStrike.radius = 12, spec says 13
- spec drift: OrbitalStrike.damage = 400, spec says 390
- spec drift: Sentry.radius = 60, spec says 65
- spec drift: Sentry.damage = 12, spec says 10
- spec drift: ReflectiveBarrier.cooldown = 95, spec says 85
- spec drift: ReflectiveBarrier.radius = 12, spec says 10
- spec drift: OrbitalLance.cooldown = 180, spec says 165
- spec drift: OrbitalLance.damage = 550, spec says 420
- spec drift: HighMarshalVeyr.health = 4000, spec says 7200
- spec drift: BastionWalker.health = 1200, spec says 3600
```

All eight weapons otherwise conform on every asserted field, so the weapon data realigned at build 441/457 holds.

**Two drift rows are new** — not previously recorded by the audit: `OrbitalStrike.radius` 12 vs 13 with damage 400 vs 390,
and `Sentry.radius` 60 vs 65 with damage 12 vs 10.

## A pre-existing failure this surfaced

`Augments: duplicate id FastHands` — this comes from the **existing** augment checks, not the new section. Two augment
archetypes share the id `FastHands`, which is exactly what `S11-054` asks to be impossible (*"Archetype IDs separate from
display labels and UID, so duplicates detectable"*). Found during the 32-archetype rebuild (build 408) and never noticed
because `CheckRunner.run()`'s result was only ever printed, never asserted against.

## Honest limits

- The drift list is **reported**, and `run()` returns `ok = false`, but `Main` only warns. Boot is not blocked. That is
  deliberate for now: ten real drifts would otherwise halt every playtest until the owner rules on them. Making it fatal is a
  one-line change once the list is clear.
- `BOSS_PITY` and `BOSS_BLUEPRINT_CHANCE` are locals inside `ProfileService`, so they are **not** assertable from
  `CheckRunner`. The known 3-vs-5 and 0.34-vs-0.15 deviations are therefore still detected only by reading the file.
- The spec values are transcribed by hand into `CheckRunner`. That is a second place for the number to live, so a spec change
  needs two edits. A generated table would be better and is not what this batch did.
- No `create_place`-style regeneration: the conformance section is appended inside `run()` and shares its `ok`/`passed`
  counters, so assertion numbering shifts by the number of spec checks.

## Reproduce

In a fresh Play VM: `require(game.ServerScriptService.GF.Test.CheckRunner).run()` and read
`workspace:GetAttribute("GF_SpecDrift")`.
