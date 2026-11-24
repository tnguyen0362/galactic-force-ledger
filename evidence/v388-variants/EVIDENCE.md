# Recovery | Fallen Convoy and Defense | Last Transmission — measured evidence (place version 388)

Session: 2026-11-24, Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client, attributes read from Server.

## Fallen Convoy (`RECOVERY_CONVOY`)
Site: wreck (tilted hull, wing, smoke), two tagged crates, `GFInteract = ConvoyCrate`.
Stages: recover both crates → pursuit squad of three spawns → kill the squad → complete.

| Step | Measured |
|---|---|
| Deploy Normal | `GF_DeployRejected` nil, `GF_ConvoyStage=1` |
| Interact crate A (in range) | `GFRecovered=true`, `GF_ConvoyCrates=1`, stage stayed 1 |
| Interact crate B | stage 2, three tagged hostiles spawned: Rifleman, Scout, Heavy |
| Kill 2 of 3 | `GF_ObjectiveComplete=false` |
| Kill 3rd | `true` |

Crates are instant pickups inside `INTERACT_RANGE` (16 studs), so this is not a hold bar.

## Last Transmission (`DEFENSE_UPLINK`)
Site: mast, tilted dish, terminal, unlit lamp.
Stages: activate dish (interact) → defend 75 s → confirm uplink (interact) → complete.

| Step | Measured |
|---|---|
| Deploy Normal | stage 1, terminal prompt `Activate dish` |
| Interact | stage 2, timer started |
| After 50 s | still stage 2 |
| After 78 s | stage 3, terminal prompt changed to `Confirm uplink` |
| Interact to confirm | `GF_ObjectiveComplete=true` |

The 75 s defend uses its own timer; it does not reuse `DEFEND_TIME` (60 s) from the beacon.

## Implementation
Both variants live in `ObjectiveService` next to the existing builders; the pursuit squad reuses the tagged-roster pattern from Elimination, and the defend stage reuses the 0.5 s timer pattern from the beacon. No new remotes, no new interaction system.

## Limits
- `Last Transmission` cannot fail: nothing damages the dish and enemies do not attack it, so the defend is a countdown.
- `Fallen Convoy` has no "locate the wreck" stage (the site is the objective marker) and the spec's alternative "reach a marked safe point" route is not implemented — the pursuit squad is the only exit.
- Neither variant has the authored hacking interaction; `Silent Archive` and the Sabotage hacking variants remain unbuilt.
- Enemy kills were applied through the `Dead` attribute `CombatService` writes, not by firing; structure and weapon paths were verified separately at build 387.
- Solo only.
