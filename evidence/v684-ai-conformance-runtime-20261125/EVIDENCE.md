# v684 AI conformance runtime evidence — 2026-11-25

## Scope and honesty boundary

Target batch requested for runtime proof:

1. FSM state transitions on live enemies; `GFState` should never be nil.
2. Marksman telegraph beam visuals.
3. Weak-core hits.
4. Officer energy sweep.
5. Scout beacon channel and cancellation.

Test environment:

- Roblox Studio MCP connected to exactly one Studio instance: `Playtest1`, placeId `120646942844931`, universeId `10778576038`.
- Studio was switched from Edit to Play; probes used the real Server and Client datamodels.
- The open cloud place is the deployed truth available on this machine. The user reports the deployed version as v684, but this session did **not** find an in-game version attribute that independently proves the string `v684`.
- No game source, module, or Edit-place content was modified. The missing `playtest1_current/` mirror remains a hard blocker for code edits.
- Several captures use documented harness positioning: live enemies/player were teleported for visibility, and one Scout was spawned at runtime through the live server `EnemyService` in the Play datamodel. AI, perception, combat, damage, VFX, HUD, and network paths were still the live game code. Harness manipulation is called out per artifact.

## Verdict summary

| Item | Verdict | Short reason |
|---|---:|---|
| `GFState` publication / never nil in observed samples | GREEN, limited | No nil `GFState` was observed in the sampled live enemies; multiple real transitions were captured. This is not full FSM conformance. |
| FSM behavioral conformance | RED/PARTIAL | Rich transitions exist, but sustained engagements also showed enemies stuck in `Advance` with zero fire slots, zero shots, and frozen positions. |
| Marksman telegraph beam | RED | Generic thin/short telegraph beams were captured in one noisy fight, but no conforming Marksman heavy beam. Server sends `def.telegraph` (0.55) instead of the charged wind-up and also schedules the shot on that shorter delay. |
| Weak-core hits | RED/PARTIAL | Server/client damage feedback proves weak-point multiplication can occur, but the weak core itself is invisible (`Transparency=1`) and hit volume behavior is inconsistent/occluded. |
| Officer energy sweep | RED/PARTIAL | Server sweep counter incremented and the player was hit, but there is no client renderer for the sweep telegraph; only a 1.5-stud self-directed tracer was observed. |
| Scout beacon channel/cancel | RED/PARTIAL | Server attributes prove channel start and cancellation, but there is no client renderer for `TransmissionUntil`; no player-visible beacon/rising icon existed. |

## 1. FSM state transitions and `GFState`

### Evidence

Artifacts:

- `raw/fsm_marksman_officer_video.mp4`
- `raw/fsm_marksman_officer_samples.json`
- `raw/clean_open_field_ai_video.mp4`
- `raw/clean_open_field_ai_samples.json`
- `raw/scout_beacon_channel_cancel_video.mp4`
- `raw/scout_beacon_samples.json`

Observed state sequences include:

- First objective fight: `Idle`, `Investigate`, `Suppress`, `Suspicious` across live Marksman/Rifleman/Officer actors.
- Scout sequence: `Idle` → `Investigate` → beacon channel active → cancellation → `Flank` → `Investigate` → `Attack` → `TakeCover` → `Advance`.
- Controlled open-field sequence: Marksman/Rifleman/Officer were perceived (`PerceptionConfidence=1`) and reported `Advance`; Officer entered sweep behavior.

No sampled live enemy in these runs had `GFState=nil` after the enemy tick had begun. That specific regression claim is supported within the limits of these samples.

### Defects/limitations observed

This is **not** full FSM verification:

- In the clean open-field sustained engagement, Marksman, Rifleman, and Officer stayed at identical coordinates for 13 seconds while reporting mostly `Advance`.
- During that same interval `GF_FireSlotsHeld` stayed `0`, `GF_EnemyHits=0`, `GF_EnemyMisses=0`, and no normal shot telegraph/tracer appeared.
- The enemies alternated `Advance` → one-sample `Idle` → `Advance` on a roughly 6.3 second cadence while perception remained `1`.
- Code inspection supports a likely engagement-reset defect: the engagement path writes `GFState="Engage"` and uses the attribute to decide whether to initialize reaction delay, but the end-of-tick spec-state resolver overwrites the attribute with values such as `Advance`. The next tick can therefore treat the engagement as new again and push `nextAttack` forward repeatedly. This needs instrumentation before being called proven root cause, but the runtime starvation is directly observed.
- The fire-slot code also has early-return paths inside the delayed attack task; if a shot aborts before the release call, slots can leak. This is a code-inspection risk, not yet isolated as the cause of this run.

## 2. Marksman telegraph beam visuals

### Evidence

Artifacts:

- `raw/fsm_marksman_officer_video.mp4`
- `raw/fsm_marksman_officer_samples.json`
- `raw/fsm_marksman_officer_frame_0.4s.jpg`
- `raw/fsm_marksman_officer_frame_1.2s.jpg`
- `raw/clean_open_field_ai_video.mp4`
- `raw/clean_open_field_ai_samples.json`

In the first objective fight the client probe observed `TelegraphBeam` parts. Their recorded properties were:

- size `0.06, 0.06, 40`
- transparency about `0.45`, pulsing to `0.05`
- color consistent with the generic/non-heavy beam path

The heavy/charged path is supposed to use the longer, thicker, redder beam (`length 90`, transparency `0.15`) for wind-ups of at least 0.9 seconds.

### Verdict: RED

No conforming Marksman charged telegraph was captured.

Code inspection explains the failure mode:

- `EnemyService` computes `windUp = def.chargeTime or def.telegraph`.
- It publishes `ChargingUntil = now + windUp`.
- But the client event is fired as `EnemyTelegraph:FireAllClients(model, (def.telegraph or 0.55))`.
- The attack is also scheduled with `task.delay((def.telegraph or 0.55), ...)`.
- Therefore Marksman `chargeTime=1.1` is not actually used for the client beam duration or the shot delay. The client can only receive the generic 0.55 second telegraph in this path.

## 3. Weak-core hits

### Evidence

Artifacts:

- `raw/weakcore_hit_video.mp4`
- `raw/weakcore_hit_samples.json`
- `raw/weakcore_hit_framed_video.mp4`
- `raw/weakcore_hit_framed_samples.json`
- `raw/weakcore_hit_control_video.mp4`
- `raw/weakcore_hit_control_samples.json`
- `raw/weakcore_immediate_0.jpg`
- `raw/weakcore2_immediate_0.jpg`
- `raw/weakcore3_immediate_0.jpg`

Measured client-side `DamageFeedback` rows:

- First successful weak hit: `weakPoint=true`, `damage=36`.
- Control sequence: one row `weakPoint=false`, `damage=18`; another row `weakPoint=true`, `damage=27`.
- Officer weak multiplier is 1.5, so the `18 -> 27` pair is consistent with the multiplier reaching the feedback path.

### Verdict: RED/PARTIAL

The damage multiplier path is real, but the player-visible feature is not conforming:

- The live Officer/Marksman `WeakCore` parts were inspected with `Transparency=1` and `CanQuery=true`.
- The model build code first excludes `WeakCore` when hiding primitive hit volumes, but a later rig-visibility loop hides every non-root BasePart without excluding `WeakCore`. The visible power core is therefore invisible whenever the authored rig path runs.
- Hit behavior is inconsistent. In one control sequence, aiming at the live core produced a non-weak hit while a torso-directed shot produced the weak hit. Invisible body hit volumes appear able to intercept rays before the small core volume.
- Floating damage-number code exists and damage feedback reached the client, but the captured video frames do not provide a clean, readable weak-core popup. This should be recaptured after the core visibility/hit-volume defects are fixed.

## 4. Officer energy sweep

### Evidence

Artifacts:

- `raw/clean_open_field_ai_video.mp4`
- `raw/clean_open_field_ai_samples.json`
- `raw/controlled_open_field_ai_video.mp4`
- `raw/controlled_open_field_ai_samples.json`

Measured runtime facts:

- `GF_OfficerSweeps` increased to `1`.
- `GF_SweepHits` increased to `1`.
- `SweepTelegraphUntil` was present on the Officer at the first clean sample.
- The client beam/tracer recorder saw only a violet `EnemyTracer` centered on the Officer with length approximately `1.5` studs.

### Verdict: RED/PARTIAL

The server-side sweep damage event exists, but the required player-readable energy-sweep telegraph does not. No StarterPlayer client script references `SweepTelegraphUntil` or `OfficerSweep`. The only client visual generated in this path is the generic `EnemyFired` tracer, approximately 1.5 studs long because the target is effectively the Officer's own position.

## 5. Scout beacon channel and cancellation

Artifacts: `raw/scout_beacon_channel_cancel_video.mp4`, `raw/scout_beacon_samples.json`, `raw/scout_channel_active_0.jpg`, and extracted frames.

Measured timeline:

- `t=0.0`: Scout `Idle`, `PerceptionConfidence=0`, no transmission.
- `t=0.348`: Scout `Investigate`, `PerceptionConfidence=0.72`, `TransmissionUntil` present, `GF_BeaconChannels=1`.
- `t=1.323`: `TransmissionUntil` nil, `GF_BeaconCancels=1`.
- Then: `Flank`, `Investigate`, `Attack`, `TakeCover`, `Advance`.

The client scan during the channel found only unrelated world objects such as `EmergencyBeacon` and station navigation beacon parts. It found no scout transmission effect, rising icon, beam, billboard, or other channel visual tied to the Scout.

### Verdict: RED/PARTIAL

The server-side channel/cancel state machine exists, but the player-visible beacon does not. The observed cancellation occurred as the Scout investigated into visibility/acquired the player; it validates cancellation on challenge but does not isolate damage cancellation. Cancellation also checks `Health`, so shield-only damage may not cancel. There is no explicit 24-stud proximity cancellation check in `tickScoutBeacon`; close-range cancellation is indirect through target acquisition. No StarterPlayer client script references `TransmissionUntil`.

## Cross-cutting observations

- Mission areas around the relay can be extremely dark; several captured frames are dominated by black silhouettes.
- Bastion Walker's phase bar appears during ordinary SABOTAGE_RELAY deployment because the field boss exists in the mission ecosystem. Whether that is intended needs a product decision.
- The build does not yet show the Helldivers-like patrol ecology from `../v620-runtime-verification-20261124/HELLDIVERS_FEEL_DESIGN.md`: enemies are still primarily objective/director spawns rather than unaggroed patrols moving through the world.

## Exact implementation blockers

1. `playtest1_current/` is still missing. Per project constraint, no game-code edits were made.
2. The deployed cloud place can be inspected and runtime-tested, but safe source editing/redeployment requires mirror restoration instructions or explicit authorization to edit the cloud place directly.
3. Any fix must be followed by fresh runtime capture; script presence alone is not verification.

## Recommended fix order

1. Fix attack engagement state/reaction-delay logic using actor-local state rather than reading the overwritten `GFState` attribute; ensure fire slots release on every early exit.
2. Use computed `windUp` for both `EnemyTelegraph` and `task.delay`; verify Marksman/Heavy charge duration visually.
3. Keep `WeakCore` visible after rig attachment and rework hit volumes so direct core shots are not intercepted by invisible body volumes.
4. Add real client renderers for `TransmissionUntil` and `SweepTelegraphUntil`, then prove cancellation with damage/proximity cases.
5. Re-run this exact evidence harness and compare metrics/artifacts.
