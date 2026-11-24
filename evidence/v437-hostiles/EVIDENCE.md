# Minimap hostile blips — observed or audible only (build 437)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client.

## What was added
`StarterPlayerScripts.Minimap` now draws hostile blips, under a rule that forbids wallhacks:

- **Seen:** a client-side raycast from the player's head to each `GFEnemy` within 140 studs. If the ray reaches the enemy (or stops within 4 studs of it), the blip is recorded as *seen* (red).
- **Audible:** `EnemyFired` marks the firing hostile for three seconds even without line of sight (orange).
- **Fading:** entries older than 3 s are dropped; surviving blips fade by age, and blips outside the minimap radius are culled.

The raycast runs on the **client**, so the map cannot learn about an enemy the client cannot see — the information never reaches the client in the first place.

## Measured
| Situation | `GF_MinimapHostiles` |
|---|---|
| Standing 22 studs from a tagged Marksman, in the open | **8** (patrols plus the objective squad, all visible) |
| Moved ~700 studs away, waited 4.5 s | **0** |

Both directions are real: blips appear with line of sight, and they vanish when the enemies are neither seen nor audible. The three-second linger is what the 4.5 s wait covered.

## Limits
- **Occlusion was not isolated.** I tested distance, not cover: no wall test was staged, so "does not show enemies behind a wall at 30 studs" is the design but not a measurement.
- The **audible** path (`EnemyFired` → orange blip without line of sight) is code-only; it was never observed separately from the seen path.
- 8 blips were shown at once; no cap is applied, so a large fight would draw every visible hostile.
- One client, one mission, one difficulty.
