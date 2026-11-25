# v691 deployment-manifest and performance addendum — 2026-11-25

## Critical deployment bug found

The deploy manifest contained only **95** scripts while the mirror contained **125**. Thirty live client/service/shared scripts were silently absent from every v685-v690 deployment, including:

- `LoadingScreen`
- `AimAssist`, `Flashlight`, `ArmorFlashlight`, `Nameplates`, `TouchControls`, `TutorialHints`, `VirtualCursor`
- `TelemetryService`, `PerformanceTelemetry`, `PathThrottle`, `SpatialGrid`, `WeatherService`, `OptionalService`, `NetGuard`, and others
- several shared config modules

This means some fixes that were correctly edited in the mirror were **not actually live** before v691. The clearest proof: after an attempted TelemetryService-only deploy, the Edit datamodel still reported `counter=false`; after the manifest repair and full deploy it reported `counter=true` and `scanComment=true`.

## v691 deployment

- Manifest repaired from 95 to **125** entries.
- v691 deployed **125/125** scripts with zero compile failures.
- Saved as cloud version **691**.
- Raw log: `raw/deploy_v691_full_manifest.log`.

## Performance measurements

Artifacts:

- `raw/v690_fresh_station_fps_baseline.json`
- `raw/v691_full_manifest_verification.json`
- `raw/v691_station_performance_0.jpg`
- `raw/v690_workspace_performance_inventory.json`

Measured fresh Studio Play Solo station samples:

- before: `fps=14.9`, `memory=2606.2 MB`
- after full-manifest + telemetry scan fix: `fps=14.9`, `memory=2665.2 MB`

The repeated exact 14.9 value strongly suggests a Studio/environment measurement cap or host-level bottleneck rather than proof that the telemetry scan was the rendering bottleneck. The telemetry scan defect was still real: once the sample ring filled, `240 % 60 == 0` made a full `workspace:GetDescendants()` scan run every heartbeat. It is fixed, but honest measurement says FPS did not improve in this harness.

Workspace inventory at sample time: 5,536 descendants, 1,311 Parts, 389 MeshParts, 59 lights, 3 shadowed lights.

## Honest status

FPS remains **open**, not fixed. The next useful step is targeted render/profiling work rather than blind optimization: isolate Studio cap versus real client, reduce simultaneous station+mission rendering cost, and inspect light/mesh/terrain cost with controlled toggles.
