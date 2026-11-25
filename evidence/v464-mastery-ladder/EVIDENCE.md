# Mastery was unreachable: cap 10 against a level-2 threshold of 100 (place 464)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 464**.

## The defect, and a correction to my own previous note

My previous batch recorded mastery as *"+1 per hit"*. That was **wrong**. The award sits inside the
`if newHealth <= 0 then` branch of `CombatService.damageEnemy`, so it is **+1 per kill**, and the code comment
(*"Per-weapon mastery grows from kills with that weapon"*) is accurate. The specification also forbids per-hit credit
(*"no XP per hit"*, L161), so the structure was right.

What was broken was the arithmetic:

```lua
local updated = math.min(10, current + math.floor(amount))   -- ProfileService.addMastery
```

`GOAL_2026-11-24.md` L165 sets five levels at thresholds `[0, 100, 240, 420, 650]` with **XP capped at level 5**. A hard cap
of 10 sits below the 100 needed for level 2, so **no weapon could ever leave level 1**. The second permanent augment socket,
gated on level 5, was unreachable by construction.

There was also no level ladder at all: the thresholds appeared nowhere in the project.

## The change

| file | change |
|---|---|
| `ProfileService.addMastery` | cap `10` → `650` (the level-5 threshold, per "XP capped at level5") |
| `ProfileService` | new `MASTERY_THRESHOLDS = { 0, 100, 240, 420, 650 }` and `ProfileService.masteryLevel(player, weaponId)` publishing `GF_MasteryLevel_<weaponId>` |
| `CombatService` | module-level `MASTERY_XP` table, awarding the authored amount per archetype instead of a flat 1 |

Authored per-kill mastery XP (`GOAL_2026-11-24.md` L150–L157): Rifleman/Vanguard/Marksman **10**, Heavy **20**, Commander
**35**, Walker **100**, Veyr **250**. Mapped to the config's ids: `Rifleman`, `Scout` (Vanguard), `Marksman` = 10;
`Heavy` = 20; `Officer` (Commander) = 35; `BastionWalker` = 100; `HighMarshalVeyr` = 250.

A flat 1 could not reach 100 either, so the rate and the cap had to move together — fixing only the cap would still have left
level 2 needing 100 kills.

## Measured

Probe `Script` in `ServerScriptService` sharing the live module instances, real loaded profile:

```
thresholds=0,100,240,420,650
start                                   xp=0    lvl=1
after +10                               xp=15   lvl=1
after +90   (expect 100 -> lvl 2)       xp=105  lvl=2
after +140  (expect 240 -> lvl 3)       xp=245  lvl=3
after +10000 (expect cap 650 -> lvl 5)  xp=650  lvl=5
```

`xp=15` after a +10 request because the profile already held 5 from an earlier test hook; the award itself is exact. Every
boundary behaves: 100 crosses to level 2, 240 to level 3, and the cap clamps at 650 instead of overflowing.

## A mistake I made and caught

The first insertion of the ladder was spliced with an off-by-one (`string.sub(src, b)` instead of `b + 1`), duplicating the
final `}` of the anchor and producing `Expected identifier when parsing expression, got '}'`. It compiled-failed immediately
and was repaired before anything ran. This is exactly the silent-edit hazard `HANDOFF.md` records (*"a broken edit fails
silently until the log is read"*) — which is why every edit in this session is checked with `loadstring` before Play.

## Still open on mastery

- **`S09-034` settlement is untouched.** Mastery still accrues per kill *during* the mission and is written to the profile
  immediately, so a player who fails the primary keeps it. The specification settles mastery on mission completion only. That
  needs an in-mission bucket and a settlement hook, not a constant change.
- The second augment socket is not verified to unlock at level 5.
- "Independently track every **owned** weapon" is not enforced — a mastery key is written for whatever weapon id is on the
  session state.
- The level-up toast/UI the spec asks for was not added.

## Reproduce

Call `ProfileService.masteryThresholds()` and compare to `[0,100,240,420,650]`, then `addMastery(player, "AR01", n)` for
n = 10, 90, 140, 10000 and read `GF_Mastery_AR01` / `GF_MasteryLevel_AR01` after each.
