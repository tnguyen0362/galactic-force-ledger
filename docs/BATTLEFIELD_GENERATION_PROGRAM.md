# Battlefield Generation Program — audit, architecture, implementation plan

Authority: user brief "GALACTIC FORCE — ADVANCED PROCEDURAL BATTLEFIELD REFINEMENT" (2026-11-26),
GOAL.md 262/341/354-374/704, Helldivers 2 developer research. Owner: beta.
Staging: `C:\Users\tnguy\gf-battlefield-build\` until mirror-write-lock returns to beta.

## PART 1 — Audit of the existing generator (measured from live code)

### 1.1 Hard quantitative findings

| Parameter | Current | Brief target | Verdict |
|---|---|---|---|
| Terrain extent | 704 studs/side | 1500-2000 | **2-3x too small** |
| Spawn→primary distance | 240 studs STRAIGHT-LINE, hardcoded | 650-1000 NAVIGABLE | **~3-4x too short, never measured as route** |
| Mission layout | FIXED positions, seed only changes noise | seeded layout topology | **layout is not procedural at all** |
| Terrain regeneration | once at server boot | per deployment | **same geography every mission** |
| Biome rotation | palette-only rotation over fixed geography | archetype-driven geography | cosmetic only |
| Objective approaches | 1 graded valley corridor, 62% flattened, 55-stud spine | >=2 meaningfully distinct | linear corridor confirmed |
| Optional outposts/bases | 0 (one relay objective only) | 2-4 | absent |
| Defensive positions | 8 cover walls in fixed ring | 3-6 authored positions | placeholder scatter |
| Patrols | 4 static guards at objective | 4-8 route-following patrols | absent as system |
| Installation types | 1 (relay compound ring) | template families | absent |
| Seed validation | trivial node-collision simulation | 150-seed metric suite | absent in substance |

### 1.2 Structural findings

1. `Mission.luau` hardcodes everything: flats at fixed positions, cargo/ship/beacon/conduits/cover
   at fixed offsets, doors at fixed positions, objective at (0,0,-120), LZ at (0,0,120).
   **Reseeding changes terrain noise only — never geography, never layout, never tactical situation.**
2. `TerrainService.generateGraph` scatters nodes in ±700 while terrain spans ±352 — vestigial,
   unused for actual placement, geometrically incoherent.
3. `SectorBuilder` noise stack (broad 170/mid 74/fine 28 + ridged crest + terrace quantization) is
   a solid foundation per the brief ("preserve working functionality") — KEEP, extend.
4. The 55-stud/62% spine + 11-stud corridor grading = double flattening of the SAME straight line.
   This is the "disguised linear level" mechanism in concrete form. Both must be replaced by
   discovered-route validation, not manufactured corridors.
5. `EncounterDirector` is actually good (token economy, alert-driven refill, phase scalars,
   player-scaled caps) — integrate, don't replace. What it lacks is spatial structure: patrol
   routes, garrison anchors, reinforcement approach regions, quiet intervals. The battlefield
   generator must EXPORT these zones to it.
6. `OutpostService` proves modular-kit composition works (deterministic LCG, ring layout) — it is
   the seed of the template system, but currently exactly one hardcoded ring layout.
7. `WorldDressing` biome kits are palette/flora parameter bundles — compatible with the archetype
   system as the composition layer.

### 1.3 Helldivers 2 research synthesis (primary-level-designer sources)

- **Stamps**: pre-authored level chunks tiled into procedural space with any orientation; in-bounds
  area size derives from combined location sizes; voronoi-style packing in dense environments.
  Authored chunks have max-diameter and shape-variation constraints so tiling isn't detectable.
- **Biome affects terrain BETWEEN locations + skin of locations, never location layout design.**
- **Spatial composition**: each installation breaks into clearly-defined areas (storage/living/
  working) distinguished by height, color, gameplay — readability through framing, silhouette,
  leading lines, verticality.
- **Multi-directional assault** was an explicit design requirement: "approachable from any
  direction and still fun."
- Difficulty scales map size, objective count, patrol frequency, outpost count/size.
- POIs fill leftover space (avg 11.6 on max difficulty); outposts tier light/medium/heavy/fortress.
- Patrols spawn on intervals, march routes biased across player positions unaggroed, visible
  approach → player choice to engage or avoid; despawn beyond 175m; reinforcement hordes finite
  with hidden cooldown; terror comes from converging alerted patrols, not infinite spawns.

## PART 2 — Target architecture

### 2.1 Pipeline (per brief section 4)

```
STAGE 0  SeedStream     independent deterministic streams: geography/layout/installations/
                        cover/encounters/cosmetic (LCG-seeded substreams, generator-versioned)
STAGE 1  Archetype      weighted selection per mission template + biome compatibility
STAGE 2  MacroGeo       analytic landform composition (domain-warped, directional, voronoi)
STAGE 3  Regions        traversability analysis -> region/landmark identification
STAGE 4  Topology       mission graph G=(V,E): nodes typed, edges costed, redundancy enforced
STAGE 5  Installations  template selection + placement scoring + terrain footprint shaping
STAGE 6  Routes         least-cost path discovery, selective grading (never flatten-to-base)
STAGE 7  Refinement     detail noise re-application, terrace tuning per archetype
STAGE 8  Cover          context-sensitive distribution (poisson + density fields)
STAGE 9  Encounters     export zones: garrisons, patrol routes, reinforcement approaches, quiet
                        corridors -> EncounterDirector consumes, owns spawning
STAGE 10 Validation     metric suite + envelope rejection loop (max K seeds, reason histogram)
```

### 2.2 Scale model

- Battlefield extent: **1664 studs/side baseline** (within 1500-2000,
  13x13 tiles of 128 studs — WriteVoxels batch count 169 vs current 36, budgeted over frames).
- Layout distances: LZ→primary **700-950 navigable** measured by least-cost path length, not
  euclidean. Enforced in validation.
- The sampler is pure math — extends infinitely; the WRITTEN volume stays bounded. Distant
  geography beyond the play volume is skybox-grade silhouette only (future cheap impostor ring).

### 2.3 Module map (all new, server)

```
ServerScriptService/GF/Services/Battlefield/
  SeedStream.luau        independent stream derivation from master seed + generator version
  NoiseKit.luau          warped/anisotropic/voronoi/ridged primitives (pure math, no Instances)
  Archetypes.luau        data-driven archetype parameter tables + selection weights + envelopes
  MacroGeography.luau    per-archetype landform composers -> heightfield sampler components
  RegionAnalysis.luau    grid sampling: slope/exposure/traversability fields, landmark extraction
  Topology.luau          mission graph construction, least-cost routing (A* over cost grid),
                         route redundancy measurement, selective grading masks
  Templates.luau         installation template definitions (footprint, zones, sockets, rules)
  Placement.luau         suitability scoring; rejection + fallback
  Cover.luau             poisson-disk + density-field cover distribution, context masks
  EncounterZones.luau    export format for EncounterDirector: anchors/routes/regions/budgets
  Metrics.luau           full validation suite incl. feature vector F
  BattlefieldService.luau orchestrator: seed in -> validated battlefield plan out
```

Integration contract: `BattlefieldService.plan(seed, missionTemplate, difficulty)` returns a
**BattlefieldPlan** — pure data: sampler function, node/edge graph, installation placements,
cover placements, encounter zones, validation report. `Mission.luau` consumes the plan instead of
hardcoded positions. Terrain writing stays in SectorBuilder (samplerOverride). This separation
keeps generation testable without touching gameplay services.

### 2.4 Archetype parameter sketch

Six archetypes per brief, parameterized: landform functions, roughness fields, terrace strength,
valid-zone masks for installations, route cost weights, envelope bands, composition hints.
Veyra-7 highland biome hosts: highland_valley, canyon_network, fortified_plateau, open_plains,
broken_basin, industrial_wasteland (excavation variant). Biome compatibility matrix per archetype.

### 2.5 Installation template sketch

Template = data: footprint polygon + foundation flatten spec + entrance sockets (directions,
min width) + interior zones + defensive positions + objective interaction sockets + reinforcement
access + sightline spec + validity rules. Families: guard_post, checkpoint, observation,
supply_depot, comms_relay, radar_station, ammo_storage, fortified_compound, comms_complex,
artillery, power_station, vehicle_compound, aa_installation, logistics_center, command_stronghold,
weapons_facility, research_installation, industrial_complex, strategic_redoubt.
Initial implementation: 2 small + 2 outpost + 1 base + 1 primary template MINIMUM viable set,
authored as part-composed kits like OutpostService but layout-driven from template data with
modular interior variation (seeded substream).

### 2.6 Validation metrics (brief section 14/17 — feature vector)

F = [elevationDistribution, slopeDistribution, routeRedundancy, engagementDistanceDistribution,
coverDensity, coverDistribution, installationComposition, objectiveSeparation, tacticalHighGround,
exposureDistribution] — computed analytically over a 4-stud sample grid + LOS step tests.
Anti-repetition: cosine distance of F vectors across recent generations in offline batch;
archetype weighted selection with light recent-layout avoidance.

### 2.7 Performance budget

- Generation latency target: <12s total per deployment on server (terrain writes dominate;
  bounded tiles yield as today). Validation adds <8s analytic (overlappable with write start
  since validation only needs the sampler).
- 169 tiles x WriteVoxels — same batching pattern, extended grid. Memory neutral: voxel count is
  what it is; streaming enabled already.
- No per-frame generation cost. Encounter zones are static data post-generation.

## PART 3 — Phasing

- **P0 (offline, now):** NoiseKit + Archetypes + MacroGeography + RegionAnalysis + Metrics
  prototype in scratch dir; test harness design; no mirror writes.
- **P1 (first Studio window):** integrate sampler behind `GF_BattlefieldGen` flag; side-by-side
  metric comparison old vs new on same seeds; visual capture comparison.
- **P2:** Topology + routing + selective grading; delete spine flattening; navigable-distance
  validation live.
- **P3:** Templates + Placement scoring; migrate relay compound to first template; LZ/primary/
  extraction placement per graph.
- **P4:** EncounterZones export + EncounterDirector integration (patrol routes, garrisons,
  quiet intervals); Mission.luau per-deployment regeneration consuming plans.
- **P5:** Cover distribution + composition integration (WorldDressing reads plan zones).
- **P6:** 150-seed batch validation across archetypes/templates/difficulties; envelope tuning;
  dev-only top-down visualization; cutover default-on.
