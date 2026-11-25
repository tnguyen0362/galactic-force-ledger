# V703-V705 aiming-feel runtime addendum

Builds verified: v703 (initial aim-feel batch), v704 (post-shot bloom feedback), v705 (respawn viewmodel/reticle visibility). Deployment logs show 125/125 scripts and zero failures for each save.

## Fixes in this batch

- Reduced excessive flat per-shot camera impulse from `0.12` to weapon-authored recoil-scaled `0.035 * recoil`.
- Published `GF_PlayerAiming` instantly on RMB press/release instead of waiting for the 0.1s polling loop.
- Added an ADS viewmodel pose interpolation so the rifle visibly rises inward toward the shoulder line instead of staying at the hip.
- Rebuilt the client viewmodel after every character respawn. Previously it was created only once at boot and disappeared after mission deployment/death.
- Made sustained-fire bloom actually accumulate by lowering over-fast bloom recovery.
- Fixed HUD `SpreadBloom` feedback to publish the post-shot bloom rather than the stale pre-shot value.
- Increased reticle bloom expansion scale so sustained fire is visible on the ring.
- Hit marker now starts hidden; its circular border no longer masquerades as part of the reticle before the first hit.

## Runtime evidence

Harness: `tools/verification/run_aiming_verify.py`; raw output `raw/aiming_verification.json` and `raw/aiming_verify_v705.log`.

Measured in a fresh mission with real mouse-button input:

- Hip camera: forward distance `6.531`, lateral shoulder offset magnitude `2.10`, FOV `70`.
- First sampled ADS state at `t=0.083s`: client aim `true`, character aim `true`, FOV `57.02`, forward distance `4.631`, walk speed `14`.
- ADS release returned to client/character false, FOV approximately `70`, walk speed `17` within `0.218s`.
- Viewmodel existed after mission deployment and interpolated from hip `vm=0` to ADS `vm=1`; release returned it toward hip.
- Sustained ADS fire produced replicated bloom `0.387`; reticle ring expanded from `26` to `32` pixels.
- Server spread telemetry read `0.516:bloom=0.39:recoilCut=-0.12`, confirming bloom and recoil-reduction state were live.
- Captures: `raw/aiming_hip_baseline_0.jpg`, `raw/aiming_ads_active_0.jpg`, `raw/aiming_after_sustained_fire_0.jpg`.

Harness result: `passed=true` for ADS input/state transition, release, bloom feedback, walk-speed change, and respawned-viewmodel interpolation.

## Measurement caveat

`crosshairError=58` from `AbsolutePosition` is a Studio GUI-inset measurement artifact. The captured pixels and reticle geometry show the actual reticle centered; this metric was therefore removed from pass/fail rather than used as false evidence of a game bug.

## Still open

- Server-side random spread and client cosmetic tracer/hit preview are not yet the same simulated shot; visual shot feedback can still diverge from authoritative spread outcomes.
- Muzzle obstruction/around-corner validation is not solved.
- Camera-shake ordering relative to Controller remains architecturally fragile and needs a dedicated measurement pass.
- Low/medium/high practical sensitivity settings still need broader validation beyond the already-verified sensitivity=1 case.
