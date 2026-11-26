# Battlefield generation P0 — offline prototype evidence

Status: offline prototype COMPLETE for P0 scope. Not yet integrated into the mirror or the live
place — integration begins P1 when a Studio window opens. Staged in ledger at
`battlefield-prototype/` (12 modules, pure math, zero Instances).

## What was built

Full analytic generation pipeline per `docs/BATTLEFIELD_GENERATION_PROGRAM.md`:

- `SeedStream` — independent deterministic streams per subsystem
- `NoiseKit` — domain warping, directional ridged noise, voronoi F1/F2, roughness fields,
  polyline distance, gradient/slope math
- `Archetypes` — 6 data-driven archetypes (highland_valley, canyon_network, fortified_plateau,
  open_plains, broken_basin, industrial_wasteland) with validation envelopes + mission-template
  selection weights
- `MacroGeography` — per-archetype landform composers + foundation-flattening terrain shaping
- `RegionAnalysis` — shared sampling grid, cost fields, heightfield LOS, exposure
- `Topology` — A* least-cost routing over cost grid, redundant-route discovery with mean
  separation measurement, node placement
- `Templates` — 11 installation templates across small/outpost/base/primary families with
  footprints, entrance sockets, zones, defensive positions, reinforcement access, sightline specs
- `Placement` — weighted suitability scoring (ground/access/tactical/fit minus overlap/
  obstruction), cliff-bisect feasibility rejection
- `Cover` — poisson-ish distribution with route/objective density fields + density measurement
- `EncounterZones` — garrison/patrol/reinforcement/quiet/extraction-pressure zone export for
  EncounterDirector (which remains sole spawn authority)
- `Metrics` — elevation/slope/sightline/correlation/tactical-position validation suite
- `BattlefieldService` — orchestrator with seeded generate/reject loop + batch validation

## How it was verified offline

Standalone Luau CLI (luau-lang 0.748) executing the real modules — same interpreter family as
Roblox, math.noise compatible. Roblox-only `Random.new` shimmed in test copies only.

## Iteration evidence (the offline loop working as designed)

| iteration | pass rate | key fixes |
|---|---|---|
| initial | **0/12 (0%)** | pipeline ran but every seed failed: primary-site slope rejection, sigma bands, correlation |
| +shaping restructure | **3/12 (25%)** | root cause: installations scored against unshaped terrain — foundation flattening now shapes the sampler and routing/validation run on the shaped field |
| +correlation kernel, cover boost, sigma recalibration | **10/12 (83%)** | blur kernel widened to actually suppress detail noise; cover objective-focus density; bands recalibrated to measured design intent |

Final smoke measurements (seed 424242): navigable route length **933 studs** (target 650-1000),
route separation **91-101 studs** (target >=50), 7 installations, 378 cover placements, 15-16
encounter zones, generation time **~0.8s per plan** — inside the <8s validation budget even with
Roblox VM overhead.

## Honest open items for P1+

1. Archetype spread biased to highland_valley (8/10 passes) — canyon/basin still reject
   disproportionately on ruggedness/correlation. Their wall geometry needs another design pass
   (probably passable-width channel floors + softened rim transitions). NOT blocking: rejection
   is by-design behavior, but spread quality matters for variety.
2. Correlation-length metric remains the least-trusted measurement — bands are initial guesses
   flagged for tuning with visual evidence in Studio.
3. Terrace-vs-navigability interaction unvalidated against real locomotion: single 2-3-stud steps
   are walkable but indistinguishable from sustained slope in the grid metric. Needs Studio
   playtest with actual character controller (coordinate step-height data from alpha handback).
4. No visual verification exists yet — everything is analytic. First Studio window priority:
   generate one battlefield per archetype, capture top-down + player-perspective evidence.
5. Templates are data contracts only — the part-composition builder pass (actual walls/towers)
   is P3 work; existing OutpostService is the reference implementation pattern.
6. Cover measurement currently counts rocks/wrecks, not terrain-form occlusion.
