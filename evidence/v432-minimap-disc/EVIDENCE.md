# Minimap: circular, heading-up, re-centring (build 432)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client. Captures `ScreenCapture_MINIMAP_CIRCLE` (square, before) and `ScreenCapture_MINIMAP_DISC` (circular, after).

## Three fixes
1. **Circular silhouette.** `UICorner` + `ClipsDescendants` did not clip children — neither on a `Frame` nor after switching to a `CanvasGroup`; both captures before the fix showed terrain filling the corners. The circle is now drawn explicitly: a rounded **disc** frame renders as a circle, and cells/blips outside the radius are culled by distance. The capture after the fix shows a disc with no corners.
2. **Heading-up rotation.** Camera `CFrame` writes were inert in this session (look vector identical before and after, even with `CameraType = Scriptable`), so the map never rotated. Heading now comes from the **character's** `LookVector`, which is a valid facing source and is testable.
3. **Drift.** Cells were placed once per height-field publish, so the map lagged the player. They are now re-placed every 0.2 s tick.

## Measured
| Check | Result |
|---|---|
| Circular silhouette | capture shows a disc; corners empty |
| Heading source | character yawed 90° → `GF_MinimapHeading = -90`, `field.Rotation = 90` |
| Re-centring | player moved +20 studs → 90 cells visible inside the disc, sample cell moved from `{0,4},{0,-64}` to `{0,63},{0,13}` |
| Cells / blips | 256 cells built, 2 blips (objective, LZ) |

Culling also means only ~90 of the 256 cells render at once, which is cheaper than drawing the full grid.

## Limits
- The circular clip is a **disc backdrop plus radius culling**, not a true mask: a blip or cell straddling the rim is clipped by visibility, not by pixels, so the edge is quantised to cell size.
- Heading follows the character, not the camera. A player who looks around without turning will not see the map rotate — which may not be what "heading rotation" means in the spec.
- Only 2 markers were present (station). Squad and downed blips were not exercised.
- No zoom, no enemy blips, no POI discovery state, no rotation lock.
