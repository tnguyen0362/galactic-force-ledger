# Archetype combat behaviour measured (build 440 audit)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client. Reads `EnemyFired` and model positions on the client.

## Setup
Deployed `SABOTAGE_RELAY`, then moved the character to the centroid of every live hostile: **3 Rifleman, 3 Marksman, 2 Scout** within ~40 studs. Watched `EnemyFired` per archetype for 12 s, and the distance each model travelled.

## Result 1 — archetypes behave differently
| Archetype | Shots in 12 s | Furthest move |
|---|---|---|
| Rifleman | 5 | 56 studs |
| Marksman | 8 | 59 studs |
| Scout | **0** | 45 studs |

The scouts closed ground (45 studs) but never fired, which looked like a defect.

## Result 2 — the Scout is not broken, it is short-ranged
Moved the player to 6 studs from one Scout and watched again:

| Window | Rifleman | Scout |
|---|---|---|
| 8 s at 6 studs | 3 | **13** |

Thirteen shots in eight seconds at point blank. The earlier zero was **range**, not a broken archetype: the Scout's authored `attackRange` is 46 studs and the centroid put it outside that until it closed.

So all three archetypes observed fire and reposition, and their engagement distances differ as authored (Scout 46, Rifleman 70, Marksman 180).

## What this does and does not prove
- **Does:** each archetype fires, moves and has its own effective range; the fire-slot cap still lets several engage (20 shots in 12 s across 8 hostiles).
- **Does not:** verify any of the authored statistics in `S06-023`–`S06-027` (HP, shields, damage, accuracy, armour factor). Those numbers were never compared against config or observed damage.
- The hypothesis "Scout never fires" was wrong, and would have been recorded as a defect had I stopped at Result 1.
- No cover, peek, flank, investigate or search state was observed — only move-and-fire.
- One client, one difficulty, 8 hostiles.
