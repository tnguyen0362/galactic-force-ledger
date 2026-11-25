# v693 aim/supply/audio addendum — 2026-11-25

## Deployment

v693 deployed all **125/125** mirror scripts with zero compile failures and saved as cloud version **693**. Raw log: `raw/deploy_v693_aim_supply.log`.

## Fixes

1. Hitscan now uses the actual camera/reticle ray instead of a parallel ray from the head. This addresses the core over-the-shoulder aim mismatch: the previous ray could never converge on the crosshair because the camera is deliberately offset.
2. Server origin validation adjusted for the legitimate OTS camera envelope.
3. ADS input is read locally/immediately for camera response instead of waiting for the 0.1s published attribute.
4. ADS mouse sensitivity is reduced to 72% for controllable precision aim.
5. While aiming or firing, the character body now rotates to camera yaw, keeping rifle/body/reticle direction coherent.
6. Hurt audio no longer uses the stock `uuhhh.mp3` vocal cue; it uses a non-vocal impact cue.
7. Supply crates are now authored around the published mission LZ, with the first crate at spawn. Crates have a visible amber cap and `RESUPPLY` billboard.
8. `GF_LZ` is published before `GF_InMission` so crate placement cannot seed from the pre-teleport station position.

## Runtime evidence

Artifacts:

- `raw/v693_mission_spawn_supply_0.jpg`
- `raw/v693_mission_input_ads_0.jpg`
- `raw/v693_supply_aim_initial.json`

Measured:

- Supply crates placed around LZ:
  - distances from player approximately `5.2`, `9.3`, and `9.9` studs
  - all with `SupplyLabel=true`
  - capture visibly shows the spawn crate and `RESUPPLY` label
- Actual right-mouse-button hold in mission:
  - `GF_PlayerAiming=true`
  - character `Aiming=true`
  - camera/body horizontal alignment `1.0000`
  - ADS camera `right=1.35`, `back=4.53`, `FOV=57`
- Actual left-mouse click:
  - server fire counters `received=1`, `accepted=1`
  - no rejection
  - spread system active: `0.527:bloom=0.35`

## Honest caveats

- The hitscan correction is implemented and the real click is server-accepted, but precision crosshair-to-target impact still needs a controlled target comparison.
- The first supply crate is visible at spawn, but capture shows the cap reads overly bright/flat and may be partially embedded in the landing pad; spawn-pad/terrain integration is still open.
- The mission-start capture exposed additional bugs now in the active work queue: stale Bastion boss bar, poor mission minimap readability, ugly spawn baseplate, sky/lighting mismatch, and HUD text overlap.
