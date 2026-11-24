# Objective markers (`S08-033`) — measured evidence (build 399)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client. UI read directly from `PlayerGui`.

## What was added
- **Server** (`ObjectiveService`): `currentMarker()` chooses a position per template — the nearest living tagged target for the three Elimination variants, otherwise the objective's `PrimaryPart`. It is attached to both the broadcast and the per-player `ObjectiveProgress` payload as `marker = { position, label }`, and is `nil` once the objective completes.
- **Client** (`MissionHUD`): a rotated diamond plus a text label projected with `WorldToViewportPoint`, clamped to a 46-pixel margin when the point is off-screen or behind the camera (label gains `(behind)`), with distance recomputed every frame from the player's root.

## Measured
| Step | Result |
|---|---|
| Deploy `ELIM_TALON`, player 45 studs from a target | label reads `TARGET  45 m` |
| Kill the Heavy | label stayed `TARGET  45 m` — the other two spawn within a few studs, and the marker always picks the first living entry rather than the nearest |
| Move the player ~75 studs away | label updated live to `TARGET  87 m` |
| Kill the last two targets | objective complete and the marker label became invisible (`visibleMarkers = []`) |
| Before the fix (station, 752 m from the site) | `OBJECTIVE (behind)  752 m` — the fallback label, never `TARGET` |

## Defect found while verifying
The marker read the **wrong `elimTargets`**: `currentMarker` is defined near the top of `ObjectiveService`, but `local elimTargets` was declared ~600 lines later, so the earlier function captured a *global* of that name (nil) instead of the module's table. The elimination branch therefore always fell through to the objective fallback: the first measurement read `OBJECTIVE (behind) 752 m` even while three tagged Talons were alive, and it never changed when one died. Fixed with a forward declaration (`local elimTargets` near the top; the family block now assigns instead of re-declaring). Re-measured: `TARGET 45 m` and live updates.

This is the same class of bug as the earlier `conqEnterStage(4)` case: an ordering mistake that compiles, runs, and silently produces plausible-but-wrong output. `loadstring` cannot catch it; only reading the value did.

## Limits
- The marker is **always exact**; the spec's "approximate position until discovered, then update" is not implemented — there is no fog/discovery state, only a `(behind)` note for off-view.
- Elimination markers pick the first living target in table order, not the nearest to the player.
- No off-screen arrow direction, only a clamped diamond.
- No distance-tier styling, no squad-shared marker ownership, no minimap integration.
- Solo only; one client.
