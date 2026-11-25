# v685 fix deployment and runtime evidence — 2026-11-25

## Deployment

The restored mirror at `game-mirror/playtest1_current/` was edited locally and deployed through the Windows Studio MCP helper. Studio was in Play mode initially; the helper stopped Play, wrote all 95 manifest scripts into the Edit datamodel, compile-checked each with `loadstring`, and saved the place.

Runtime deployment result:

- `deployed 95 / 95`
- `failures 0`
- `Saved to Roblox`
- reported cloud version: **685**

Raw deploy log: `../v684-ai-conformance-runtime-20261125/raw/deploy_v685_attempt2.log`.

## Code changes in this batch

1. `EnemyService.luau`
   - Keeps `WeakCore` visible after authored-rig hiding.
   - Enlarges/protrudes the weak core so it is more precisely hittable.
   - Latches engagement reaction-delay state in actor memory instead of rereading the overwritten public `GFState` attribute.
   - Uses the real charged `windUp` for both `EnemyTelegraph` and the delayed shot.
2. `VFX.luau`
   - Adds client rendering for Scout `TransmissionUntil`: vertical cyan channel beam plus `TRANSMITTING` billboard.
   - Adds client rendering for Officer `SweepTelegraphUntil`: expanding red-orange cylindrical ground ring.
3. `StationUI.luau`
   - Exposes Easy, Normal, Hard, and Extreme difficulty buttons.
4. The mirror also contained a previously written but undeployed over-the-shoulder camera/lighting/war-table pass; v685 is the first deployment of that full mirror state.

## Runtime verification captured

Artifacts in `raw/`:

- `v685_station_war_table_0.jpg`
- `v685_station_forced_ads_0.jpg`
- `v685_forced_telegraph_visuals_0.jpg`
- `v685_verification_samples.json`
- `v685_ai_verification_video.mp4`
- `v685_live_combat_0.jpg`
- `v685_live_combat_samples.json`
- `v685_live_combat_video.mp4`

### Difficulty selection — GREEN

Live client scan found all four buttons:

- EASY
- NORMAL
- HARD
- EXTREME

No INSANE button exists because the current spec/server vocabulary uses Extreme; whether Insane should replace or extend Extreme remains a product decision.

### Over-the-shoulder camera — PARTIAL GREEN

Measured live camera values:

- Hip: `CameraOffset=(2.1,0.5,0)`, `FOV=70`
- Forced ADS: `CameraOffset=(1.35,0.45,0)`, `FOV=57`

This proves the deployed mirror now has the close right-shoulder hip envelope and tightened ADS transition numerically active. It is not yet a full Helldivers-feel verification: recoil/reticle relationship, collision behavior, shoulder swap, and moment-to-moment input capture still need a dedicated playtest pass.

### Weak-core visibility — GREEN for visibility, hit behavior still pending

Live enemy inspection after v685 showed `WeakCore` transparency `0` for Marksman, Officer, and Scout. This fixes the previously proven invisible-core defect.

A fresh precision-hit damage comparison was not completed in this run, so weak-point hit-volume behavior remains unverified even though the visibility defect is fixed.

### Scout/officer telegraph rendering — GREEN for client renderer, end-to-end pending

The client renderer was validated by setting the already-published server attributes on live actors:

- `ScoutBeaconChannel` existed with size about `(0.42,17.0,0.42)`.
- `OfficerSweepTelegraph` existed and expanded to roughly 55.7 studs diameter.
- `v685_forced_telegraph_visuals_0.jpg` visibly shows the vertical cyan beacon beam and large orange/red sweep ring.

This proves the client visual layer now consumes the attributes. It is not yet end-to-end AI conformance proof because natural Scout channeling and Officer sweep triggering still need a clean controlled capture.

### Natural combat/FSM verification — INCONCLUSIVE

The live-combat harness remained flawed:

- Directly spawned enemies landed on high terrain and did not engage.
- Teleporting near the pre-existing objective group did not produce reliable perception; they remained visually unalerted in the samples.
- A later alert probe was invalid because the player had already returned to the station.
- Player health fluctuated during the first combat sample, so some damage source existed, but it was not attributable cleanly to the controlled enemies.

Therefore the reaction-delay and Marksman windup fixes are deployed and compile-checked, but not yet runtime-proven. Do not count them as verified passes yet.

## Lobby audit status after v685

- War table hologram is visibly improved versus v684: an orange planet-like hologram now exists above the table.
- The station remains darker than desired in the baseline spawn capture.
- Minimap exists but remains low-information for station interiors.
- Ability HUD was visible in mission capture; lobby ability/armory interaction still needs a focused test.

## Next highest-value work

1. Build a reliable flat-open-field combat harness using measured terrain height, then verify natural Marksman charged telegraph, reaction delay, movement, shots, and fire-slot behavior.
2. Prove weak-core hit multiplication again after the visibility/hit-volume change.
3. Capture natural Scout channel/cancel and natural Officer sweep end-to-end.
4. Continue lobby lighting, minimap POI, armory/ability UX, and war-table interaction work.
