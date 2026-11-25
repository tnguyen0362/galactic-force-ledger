# v687 stabilization addendum — 2026-11-25

## Deployment

v687 deployed all 95 mirror scripts successfully with zero compile failures and saved to Roblox as cloud version **687**. Raw log: `raw/deploy_v687_stabilization.log`.

## Fixes in this batch

1. `Weapon.luau`: client now actually handles the semantic `Aim` action, updates `state.aiming`, and sends `AimChanged` to the server. Previously RMB changed server/camera state only in limited circumstances while the client weapon state never became true.
2. `Controller.luau`: mouse look no longer requires holding RMB on keyboard/mouse; normal play uses `MouseBehavior.LockCenter`. RMB is aim, not the general camera-lock button.
3. `Controller.luau`: lobby/station camera receives a small additional zoom-out bonus. Measured hip back distance is now `7.63` rather than v686's `6.40`.
4. `StatusStrip.luau`: grenade count is hidden unless the player is a mission participant.
5. `StationService.luau`: fixture shadows disabled as a first performance measure; lighting brightness/range remain at the v686 readability values.
6. `StationService.luau` + `LoadingScreen.luau`: server teleportation now publishes `GF_Teleporting`, activating the existing loading screen path. The loading screen no longer calls `PreloadAsync({workspace})`, which was an unbounded and potentially severe startup cost.

## Runtime verification captured

Artifacts:

- `raw/v687_station_baseline_0.jpg`
- `raw/v687_input_driven_ads_0.jpg`
- `raw/v687_input_aim_check.json`

Measured in the live client:

- station hip camera: `right=2.10`, `back=7.63`, `FOV=70`
- mouse behavior: `Enum.MouseBehavior.LockCenter`
- grenade label scan: `GRENADE x2:false` (present but not effectively visible in lobby)
- actual MCP-driven right-mouse-button hold:
  - character `Aiming=true`
  - workspace `GF_PlayerAiming=true`
  - camera `right=1.35`, `back=5.76`, `FOV=57`

This is real input-driven aim verification, not merely source inspection.

## Still open / not yet proven

- Loading screen visibility during an actual deploy/return transition still needs a frame/video capture; v687 only proves the activation path is wired and the initial loading GUI exists.
- FPS impact of disabling light shadows is not yet measured.
- Dodging, death/end screen, minimap usefulness, natural Scout/Officer end-to-end visuals, weak-core hit precision, and broad general bug hunt remain open.
