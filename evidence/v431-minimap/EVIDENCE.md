# Minimap HUD (build 431)

Studio `a828ce66-ff1a-43c5-b662-dc096996bcc4`, Play mode, one local client. Frame `ScreenCapture_MINIMAP`.

## The gap
`TacticalMapService` has published a 16×16 terrain height field (`GF_MapMeta`, `GF_MapHeights`), a marker list (`GF_MapMarkers`: `obj`, `lz`, `sq`, `down`) and a marker count for a long time. **Nothing on the client read any of it** — there was no minimap at all, despite `S03-037` asking for a permanent circular minimap with heading rotation and a north tick.

## Implemented
A standalone `LocalScript` (`StarterPlayerScripts.Minimap`) building its own `ScreenGui`:
- 16×16 terrain cells coloured by height, placed player-relative and scaled to the published span.
- Blips for every marker, colour-coded: objective amber, LZ green, squad blue, downed red.
- A fixed player arrow at the centre; terrain and blips live in a field frame rotated by camera yaw (heading-up).
- A north tick that orbits the rim with heading.
- Diagnostics: `GF_MinimapCells`, `GF_MinimapBlips`, `GF_MinimapHeading` as ScreenGui attributes.

## Measured
| Check | Result |
|---|---|
| Terrain cells drawn | `GF_MinimapCells = 256` |
| Blips drawn | `GF_MinimapBlips = 2` (objective + LZ at the station) |
| Field children | 258 (256 cells + 2 blips) |
| Frame | visible, 156×156, top-right |

The capture confirms it renders in the corner with terrain blocks and the `N` tick.

## Two defects this batch exposed
1. **The circular mask does not clip.** The frame has `UICorner` radius 0.5 and `ClipsDescendants`, but the capture shows a **square** panel with terrain filling the corners. Roblox does not clip children to a rounded rectangle through `UICorner` alone; it needs a `CanvasGroup` or a mask image.
2. **Heading rotation is unverified.** Writing `workspace.CurrentCamera.CFrame` had no effect in this session (look vector unchanged before and after, even with `CameraType = Scriptable`), and rotating the character did not move the camera either. So `field.Rotation` stayed at 0 and the orbiting north tick was never observed moving.

## Limits
- Terrain cells are re-placed only when the height field changes, so they do **not** follow the player between updates — the map drifts when the player moves more than a cell before the next publish.
- Blips rebuild on every marker publish (~1 Hz), which rebuilds a few frames; acceptable at 2–8 markers, wasteful if markers grow.
- No zoom, no rotation lock, no enemy blips, no POI discovery state.
