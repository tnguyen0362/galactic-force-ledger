# v700 Mouse Sensitivity and UI-Cursor Input Verification Addendum

Date: 2026-11-25
Live cloud version at capture: v700
Harness: `tools/verification/run_sensitivity_verify.py`
Machine-readable evidence: `raw/sensitivity_cursor_verification.json`

## What changed

- Base mouse look sensitivity was reduced from `0.0026` radians/count to `0.0009` radians/count.
  - At the default sensitivity setting of 1.0, a 100-count horizontal mouse input should rotate approximately `5.16°`, down from approximately `14.90°`.
  - This is roughly a 65% reduction in default sensitivity while preserving the settings multiplier for player adjustment.
- Mouse movement is now ignored as camera input while `UserInputService.MouseBehavior == Enum.MouseBehavior.Default`.
  - This prevents moving a visible cursor across settings, war-table, armory, tactical-map, or debrief UI from rotating the game camera underneath the interface.
- High-frequency deathflow/vitals debug output added during diagnosis is now gated behind explicit debug attributes rather than running continuously.

## Runtime verification

The harness used real Windows mouse input after focusing/clicking the Studio 3D viewport, not merely source inspection or synthetic datamodel state.

Observed locked-camera result:

- Mouse behavior: `Enum.MouseBehavior.LockCenter`
- Input: 100 horizontal mickeys
- Yaw before: `169.067965°`
- Yaw after: `164.839536°`
- Absolute measured rotation: `4.228429°`
- Expected rotation at sensitivity 1.0: `5.156620°`
- Result: pass; measured rotation is now in the reduced sensitivity range. Minor deviation is expected because OS-level mouse injection is not a perfectly controlled DPI device.

Observed visible-cursor/UI result:

- Settings UI open: true
- Mouse behavior: `Enum.MouseBehavior.Default`
- Input: 140 horizontal mickeys
- Yaw before: `164.839536°`
- Yaw after: `164.839536°`
- Delta: `0.0°`
- Result: pass; visible cursor movement no longer rotates the camera.

After settings closed, mouse behavior returned to `Enum.MouseBehavior.LockCenter`.

## Honest remaining aiming gaps

This proves lower default sensitivity and UI cursor isolation. It does **not** close the broader aiming-feel audit: recoil, spread/reticle agreement, ADS transition feel, hit registration, camera collision, input smoothing/acceleration, and live-target verification remain open.
