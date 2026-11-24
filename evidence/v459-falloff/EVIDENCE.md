# Falloff windows aligned; long-range damage not decomposed (build 459)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Aligned to spec
Every weapon's falloff window and minimum now matches its authored row:

| Weapon | Window | Minimum |
|---|---|---|
| AR-01 | **90 / 240** (was 120/320) | **0.55** (was absent → 0.6 default) |
| P-01 | **55 / 170** (was 60/250) | **0.50** |
| SG-04 | **22 / 75** (was 25/90) | **0.25** |
| MR-07 | **150 / 350** (was 250/600) | **0.70** |
| LMG-12 | **85 / 230** (was 130/420) | **0.50** |
| SMG-03 | 45 / 150 (already) | **0.40** |

GL-22 and RL-09 are radial weapons and were left alone.

## What I could measure
- 12 studs: `LastDamage = 18`, shield 160 → 79 over five shots — exactly 5 × 18 × 0.9 armour.
- **199 studs** (target and player both anchored, verified clear raycast): one hit dealt **30.32**.

That 30.32 is *above* the base 18, so a weak-point multiplier is applied on top and it outweighs the falloff loss. I could not decompose the two: the code computes `damage × falloff × weakMultiplier`, but which part the ray struck and what `weakMultiplier` returned were not read.

## Harness notes
- Teleporting the player **without anchoring** put them back at the station mid-measurement (744 studs), the same failure mode as before: `Anchored = true` before any ranged test.
- A 60-stud sightline does not exist on the axis I first tried; the compound is cluttered, so target selection has to search eight directions and several distances, and it found a clear 200-stud line only on a later sweep.
- Targets must be anchored too, or the "distance" measured on the client is stale by the time the shot lands.

## Limits
- Falloff **behaviour** at range is not verified — only the config values.
- Weak-point multiplication is observed but unexplained (30.32 on a base of 18).
- No shot beyond 240 studs (where the 0.55 floor should clamp) has been measured.
