# Battlefield P1 Integration Spec — exact execution plan for the first Studio window

Purpose: when beta regains Studio control, execute integration in small verifiable steps without
improvisation. Ordered by dependency; every step has a verification gate before proceeding.

## Pre-flight (2 min)

1. Read alpha's handback notes on the bus; confirm mirror-write-lock + roblox-studio-control rows.
2. `git log` alpha's pushed mirror state — reconcile file list before editing anything.
3. Confirm deploy baseline: current place version, 126/126 manifest health.

## Step 1 — module drop-in, zero behavior change (target: 15 min + deploy)

Copy the 12 prototype modules into `game-mirror/playtest1_current/ServerScriptService/GF/Services/Battlefield/`
adjusting only the require style (they already use script.Parent — correct as-is).
Add 12 manifest entries (ModuleScript each). Deploy. **Nothing in the game changes** — nothing
requires them yet. Verification: deploy 138/138 failures 0, boot play solo, zero errors.

## Step 2 — headless generation smoke inside Studio (30 min)

In Edit mode, execute server-side Luau via MCP building a plan and printing the validation
report — proves the modules compile and run in the real VM (strict-mode typing issues would
surface here; fix forward). Measure Roblox VM generation time vs offline (0.8s reference).
Gate: one plan per archetype generates without errors; report printed.

## Step 3 — dev-only top-down visualization (1-2 hours, high value)

Brief section 17 requires this anyway: build a debug renderer that reads a BattlefieldPlan and
draws a top-down map as parts in a far corner of workspace (or as a SurfaceGui grid):
heightfield as color-coded studs, routes as lines, installations as footprints, nodes marked,
encounter zones as rings. **This is the first visual evidence gate** — capture screenshots per
archetype. This is where terrain quality stops being proxy metrics and becomes reviewable.
Gate: 6 archetype captures exist and are honestly critiqued in an evidence addendum.

## Step 4 — sampler A/B integration behind flag (1 hour)

`TerrainService.build` gains: if `GF_BattlefieldGen == true` (workspace attribute or config flag),
use `BattlefieldService.plan()` output sampler as the SectorBuilder samplerOverride and plan
extent (1664) instead of 704. Do NOT touch mission logic yet — the existing hardcoded mission
layout stays in the center of the bigger map. Verification: deploy flag-off (identical game),
then flag-on in playtest: measure terrain generation time, memory, capture visuals. Compare
side-by-side with legacy on same seed class.

## Step 5 — layout integration (the big one, multi-hour)

Mission.luau refactor: extract the hardcoded positions into a `MissionLayout` provider. Default
provider returns legacy fixed positions (flag off). Battlefield provider consumes the plan:
- LZ at nodes.lz, objective at nodes.primary, extraction at nodes.extraction
- flats replaced by plan foundation shaping (delete registerFlat hardcodes for battlefield path)
- ObjectiveService.setup(plan-anchored positions)
- supply crates / cover / scatter consume plan.cover and installation zones
- minimap meta/marker publication updated for the larger extent
Gate: full mission loop completes end-to-end on a battlefield-plan layout with harness evidence
(deploy → objective → extraction), all at the new scale.

## Step 6 — encounter zones + patrol integration (multi-hour, P4 overlap)

EncounterDirector consumes plan.encounterZones: garrison spawning replaces ring-of-guards,
patrols walk patrol_route polylines, quiet zone suppresses spawn noise near LZ approach,
reinforcement approach regions flavor spawn positioning. Preserve token economy untouched.
Gate: harness observes patrol movement along routes, garrison dormancy beyond activation radius,
no spawns inside quiet zone.

## Ordering notes / hazards

- **126-file deploy blast radius**: every deploy ships everything — coordinate window boundaries
  with alpha so partially-integrated battlefield work never ships inside a movement fix or vice
  versa. Flag-off state must always be deploy-safe.
- Mission.luau is boot-time; per-deployment regeneration means mission state must become
  re-entrant. Check DownedService/ExtractionService/ObjectiveService for module-level state
  captured once at boot — audit before refactor.
- Terrain write time at 1664 studs: 169 tiles vs 36 — measure. If >10s, consider 1280 extent
  or finer tile batching. Do NOT ship a 30s loading stall silently.
- The 30° slope constant vs real locomotion: pull alpha's validated step-height/slope numbers
  from their handback before finalizing MAX_SLOPE.


## Addendum 2026-11-26 — offline validation infrastructure now exceeds the original plan

Step 3's in-Studio visualization is partially front-run: an OFFLINE top-down render harness now
exists (gf-battlefield-build/test/dumpmap.lua + render.py) producing 900px shaded heightmaps
with routes/installations/nodes overlaid, no Studio needed. It already drove two critique
iterations Studio would have been wasted on — see evidence BATTLEFIELD_VISUAL_CRITIQUE.md.
In-Studio rendering remains necessary only for validating RUNTIME terrain fidelity (voxel
sampling artifacts, foundation carving, slope reality) — rescope step 3 to that.

Generator state entering integration (all validated offline, 150-seed batch):
- Feature-anchored topology: primaries sit on archetype features, missions span the map.
- Route separation mean-interior floor 80 with 110-stud penalty radius — corridor pairs dead.
- Dendritic spline-carved canyon network (voronoi foam removed).
- Tactical-diversity metric measures elevation structure in both directions.
- splitmix32 portable streams — bit-identical CLI/Roblox, no Random.new anywhere.
- Per-seed parameter jitter for within-archetype macro variety.

Integration hazards discovered since the spec was written:
- The retry loop re-rolls archetype per attempt: integration must expose WHICH attempt/seed
  produced a shipped map, or runtime debugging becomes guesswork. Log seed+archetype to
  server console at generation time (dev attribute too).
- plan() cost in the Roblox VM unknown; offline ~1.5-2s. Runtime generation happens at mission
  start — budget the loading screen accordingly, or pre-generate during lobby countdown.
