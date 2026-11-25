# Mastery now shows in the Armory too; `S10-039` complete (place 472)

Studio `1c1ed90d-eb6a-4c27-acb1-7d3870877de6`, place `Playtest1`, Play mode, one local client. Place saved as **version 472**.

## The remaining half

Place 471 shipped the debrief line. The spec asks for *"display progress in debrief/**Armory**"*, and the Armory showed nothing.

The server side was nearly there already: `ArmoryService.state` built a `masteries` table of raw XP per weapon and exported it.
Nothing rendered it, and raw XP is not what a player wants — the spec's progress reading is per **level**.

## The change

| file | change |
|---|---|
| `ArmoryService.state` | alongside `masteries`, build `masteryLevels[weaponId]` via `ProfileService.masteryLevel`, exported as `masteryLevel` |
| `StationArmoryUI` | the weapon stat line now appends `· MASTERY <level> (<xp> XP)` when a level is present |

Both compile.

## Measured

Probe `Script` in `ServerScriptService` set SMG03 to the level-5 cap and opened the panel via the documented `GF_ArmoryOpen` switch.
Server side: `SMG03 xp=650 level=5`.

Rendered client labels, read from `PlayerGui`:

```
Rifle · 18 DMG · 28 MAG · Auto · MASTERY 5 (650 XP)
Pistol · 22 DMG · 12 MAG · Semi · MASTERY 1 (0 XP)
Shotgun · 96 DMG · 6 MAG · Semi · MASTERY 1 (0 XP)
Marksman · 51 DMG · 12 MAG · Semi · MASTERY 1 (0 XP)
LMG · 17 DMG · 75 MAG · Auto · MASTERY 1 (5 XP)
SMG · 13 DMG · 36 MAG · Auto · MASTERY 5 (650 XP)
Launcher · 110 DMG · 4 MAG · Semi · MASTERY 1 (0 XP)
Launcher · 205 DMG · 1 MAG · Semi · MASTERY 1 (0 XP)
```

Eight weapons, eight rows, levels and XP both correct. Two weapons read level 5 because earlier batches in this session pushed
Rifle to the 650 cap (the ladder test) and this probe pushed SMG to it.

## Side effects, stated

- SMG03 is now at **650 XP / level 5** on the test account, which also unlocks its second augment socket. The Rifle was already
  there from the ladder test.
- `GF_ArmoryOpen` was set for the capture and cleared afterwards.
- The Armory panel was opened by attribute rather than by walking to the station, so the proximity prompt path is not what was
  exercised.

## What this closes

`S10-039` is now met on both surfaces named in the spec, and the whole mastery chain is observable end to end: earn → bucket →
settle on a completed primary → persist → publish on join → level → socket → debrief → armory.

## Still open in this area

- No "level 5 is max" annotation; a maxed weapon reads `MASTERY 5 (650 XP)` with no indication it cannot go further.
- No progress bar or "next level at N XP", so the number is informative but not a target.
- Only looked at with tabular `newLabel` rows; no capture at another resolution or input family.
