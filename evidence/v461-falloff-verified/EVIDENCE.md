# Falloff verified at range; bosses no longer linger (build 461)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Why every long shot missed
Two 199–200-stud shots in the previous batch "missed". They were not missing: a **Bastion Walker was standing in the way**, left over from an earlier elimination mission. The client raycast named it plainly — `firstHit = BastionWalker` — while the shot still consumed ammo and dealt nothing.

`EnemyService.clearAll()` only cleared `actors`, and boss models live at the workspace root (`Workspace.BastionWalker`, `Workspace.HighMarshalVeyr`), so they survived every mission change and physically blocked sightlines.

Fixed: `clearAll` now destroys those two root models too and records `GF_BossCleared`. Verified directly — Walker present, `clearAll()`, Walker gone.

## Falloff, measured
With the lane clear, one shot at **226 studs**:

| | Value |
|---|---|
| `GFDebug.LastDamage` | **10.674** |
| Formula with window 90/240, min 0.55 | **10.66** |
| Base damage | 18 |

Two-decimal agreement. That confirms three things at once: the `falloffEnd` fix from last batch is live, the authored window is what the code uses, and near the end of the window damage has fallen about 40% as designed.

## Also confirmed
Client and server agreed on positions to the stud (player z = −7, target z = −107, distance 99–100), so teleport replication itself is fine — the earlier misses were obstruction, not drift.

## Limits
- **The 0.55 floor is not measured.** No clear target exists beyond 270 studs in the relay compound, so I could not confirm that damage clamps rather than continuing to fall.
- One weapon, one range, one shot. Body hits only; the 2× head multiplier was read from the function, not fired.
- The floor needs an open lane or a purpose-built test target.
