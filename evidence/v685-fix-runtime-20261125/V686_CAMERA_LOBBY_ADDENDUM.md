# v686 camera and lobby lighting addendum — 2026-11-25

## Deployment

After the v685 runtime pass, the custom controller camera was found to ignore `Humanoid.CameraOffset` entirely. v685 therefore had correct numeric camera-offset values but still framed the character near center. v686 fixes the actual custom camera rig and was deployed through the same Windows Studio MCP pipeline:

- `deployed 95 / 95`
- `failures 0`
- saved cloud version: **686**

Raw deploy log: `raw/deploy_v686_attempt1.log`.

## Camera changes

`Controller.luau` now implements the over-the-shoulder rig directly:

- close 6.5-stud hip envelope instead of the prior 8–12 stud follow camera
- right-shoulder lateral camera offset, smooth-tightened while aiming
- camera collision ray with a small surface offset
- shoulder swap through the existing `ShoulderSwap` input (`V` / gamepad R3), published as `GF_CameraShoulder`
- ADS pulls from roughly 6.5 back / 2.1 right to roughly 4.5 back / 1.35 right

Measured live v686 values:

- hip: `right=2.10`, `back=6.40`, `FOV=70`
- forced ADS: `right=1.35`, `back=4.53`, `FOV=57`

Artifacts:

- `raw/v686_camera_check.json`
- `raw/v686_station_hip_0.jpg`
- `raw/v686_station_ads_0.jpg`

The hip capture visibly places the player in the left third of frame with a close Helldivers-like shoulder line rather than the prior centered high follow camera.

## Lobby lighting change

`StationService.luau` fixture normalization now uses brightness `1.15` and range cap `56` instead of brightness `0.80` and range cap `48`. The v686 station hip capture is visibly brighter and more readable than the v684/v685 baselines while retaining the dark sci-fi mood.

## Remaining lobby/camera verification gaps

- Mouse/gamepad input-driven ADS still needs human or input-injection verification; v686 used the same `GF_PlayerAiming` attribute forcing path as v685.
- Shoulder swap is implemented but not yet runtime-captured.
- War-table interaction remains menu-like even though the hologram improved.
- The minimap exists, but still lacks station-specific points of interest.
