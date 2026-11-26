# HYBRID PROCEDURAL VALIDATION MILESTONE — Mountain Valley archetype (2026-11-26)

Owner requirement: demonstrate at least five genuinely distinct playable geographical
layouts differing in underlying STRUCTURE, with determinism, connectivity, NPC nav,
placement, performance, and preserved terrain quality. Results below.

## Architecture validated
- Runtime chunked WriteVoxels reconstruction from compressed real-world heightfields
  IN PLAY MODE at mission init — no pre-baking needed per mission.
- GeographyService: deterministic stream G -> foundation + orientation + controlled
  deformation. Independent of composition (vegetation) and operation streams.
- 6 foundations deployed: fv1 (approved Teton regression reference) + fv2-fv6
  structurally distinct real-world crops, each 1250x1250 @ 4 studs/sample, 5000 studs.

## PERFORMANCE (measured live, per full-map regeneration)
- decode: 0.1s (delta+b85, 1.95M chars -> 1250x1250 heightfield)
- terrain write: 3.7-4.5s (shell-fill + fractional occupancy + per-tile vertical bounds)
- total: ~5s per complete geographical regeneration
- memory: server totals fluctuate 3150-3440MB in Studio playtest; +~30MB/generation
  not yet GC-reclaimed across rapid successive regens — acceptable for once-per-boot
  architecture, monitor for leak confirmation.
- NO raw elevation data processed at runtime — all preprocessing offline.

## DETERMINISM — PASS
fv2 generated twice in one session: probe lattices bit-identical
(1103,717,882,373,530,737,544,719,227,634,579,509,797,152,326,342,193,117,87,97,82,120,120,122,87 both times)

## STRUCTURAL DIVERSITY — PASS (25-probe lattice, studs)
fv1: peaks ~953 NW structure, valley floor 80-100 — approved Teton regression
fv2: peaks 1103, valley 82-87 — deeper valleys
fv3 (rot90): peaks 1188/1156 mid-map, valley 57-88 — different drainage orientation
fv4 (rot180+mirror): peak 1226, valley floor at 25 — deepest valley
fv5 (rot270): peak 1350 — highest relief, distinct slope structure
fv6 (mirror): max 973, broad lows 29-48 — gentler, wider valley systems
All six differ in landform structure, peak position, drainage, valley depth — not
merely in placement, lighting, or orientation of identical geometry.

## REGRESSION — PASS
fv1 runtime lattice matches offline source heightfield within 2-3 studs at all 25
lattice points; center probe 170 vs approved bake measurement 171 (the 797 artifact
at exact center is the concourse roof structure, not terrain — raycast hit station).

## NPC NAVIGATION — PASS (probe level)
PathfindingService ComputeAsync valley traversal (~1000 stud span): SUCCESS on all
six layouts, 264-322 waypoints each. Alpha coordination posted re: runtime terrain
regeneration vs navmesh caching (GF_TerrainReady gate documented).

## EVIDENCE
- hv2_fv1_r0_ground.png: player in valley grass, rolling foothills, objective
  installation visible at 335m — approved geography reproduced live at runtime
- hv3_* per-layout ground + overlook captures (fresh session per layout to avoid
  replication overload — client drops after ~6 rapid successive full-map regens;
  irrelevant for real sessions which generate once at boot)

## KNOWN LIMITATIONS / NEXT
- Deployment/objective placement is still legacy — the military operation layer
  (stream O) is the next major build: installation placement keyed to real terrain
  features, ~1km deployment-to-primary direction.
- Controlled deformation is conservative (height-scale only) — expansion after
  operations layer validation.
- Forested basin + industrial wasteland archetypes: datasets to acquire.
