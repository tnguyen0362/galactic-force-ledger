# Falloff fully verified — window, curve and floor (build 461)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## Three points, one curve
AR-01, window 90/240, minimum 0.55, base damage 18:

| Distance | `LastDamage` | Predicted | Delta |
|---|---|---|---|
| 12 studs | **18** | 18 (inside the window) | exact |
| 226 studs | **10.674** | 10.66 | 0.01 |
| **299 studs** | **9.90** | **9.90** (18 × 0.55 floor) | exact |

The floor clamps rather than continuing to fall, so the whole falloff contract — start, slope, end and clamp — is now measured through the real fire path.

## How the 299-stud shot was possible
The relay compound has no ground-level sightline beyond about 226 studs: every attempt from 260–320 studs hit `Workspace.Terrain` first, and lifting the shooter 10–100 studs above ground did not help because the ray then started inside terrain.

What worked: **move both the target and the shooter into open air** — target pivoted to `lz.Y + 220`, shooter at the same altitude 300 studs away. Nothing can intercept, and the fire path does not care that the target is floating (it is anchored). First hit came back as `ActiveActors.Rifleman.Torso`, distance 299.

## Harness fact worth keeping
`TerrainService.groundSurface(x, z)` returns a **number** (the height), not a `Vector3`. Calling `ground + Vector3.new(...)` throws `attempt to perform arithmetic (add) on number and Vector3`.

## Limits
- The far measurements used a floating, anchored dummy — hit registration and falloff are real, but nothing about gravity, cover or a moving target is exercised.
- Still AR-01 only. The other five ballistic weapons changed but were not re-fired.
- The floor is verified at 299 studs; damage at exactly 240 (the boundary) was not sampled.
