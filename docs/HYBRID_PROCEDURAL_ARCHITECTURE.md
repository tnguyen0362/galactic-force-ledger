# HYBRID PROCEDURAL EXPANSION — architecture (owner directive 2026-11-25)

The permanent Teton map is an APPROVED PROTOTYPE + regression reference, not the final system.
Goal: replayable procedural planetary military shooter with authored-quality geography.

## Three independent layers, independent deterministic streams
1. GEOGRAPHICAL GENERATION — seed stream G: foundation selection, subregion crop,
   orientation (rotation/reflection — legitimate for real terrain), controlled deformation
2. BATTLEFIELD COMPOSITION — seed stream C: vegetation distribution, scatter, atmosphere,
   materials/biome expression over the generated geography
3. MILITARY OPERATION GENERATION — seed stream O: installations, infrastructure, LZ,
   objectives (~1km deployment-to-primary where appropriate), encounters, extraction

## How genuine geographical variety works WITHOUT uncanny noise
- LARGE real elevation datasets yield MANY structurally distinct real subregions.
  Scan of existing Teton stitch alone (2304x2816): 38 qualifying mountain-valley
  windows, 8 diverse candidates catalogued in gf-geo/scan_candidates.npy
  (relief 1355-2175m, flat 18-43%, steep 15-25%).
- Each crop IS genuinely different geography: different landforms, routes, silhouettes.
- Orientation transforms (90-degree rotations, mirror) multiply variety while
  preserving coherence (a mirrored real valley is still real geography).
- Controlled deformation: LOW-AMPLITUDE, LOW-FREQUENCY warp only — never per-pixel noise.
  Deformation must preserve drainage coherence and slope statistics. Hard budget TBD
  by validation (start conservative: +/-5% height scale jitter, gentle large-scale tilt/bend).
- Expand datasets: additional ranges (Cascades, Sierra, Rockies) for landform diversity;
  forested basins + industrial wastelands are priority archetypes 2 and 3.

## Terrain loading architecture — evaluation required
Candidates: (a) runtime chunked WriteVoxels reconstruction from compressed heightfield
modules — STRONG FAVORITE: the edit-mode bake already reconstructs 1600 tiles in ~4s;
(b) pre-baked foundation places (multiple place slots); (c) hybrid.
BENCHMARKS REQUIRED: load time, generation time, server memory, client memory, runtime perf.
ALL heavy preprocessing offline. No raw elevation downloads at mission init.
Data modules already exist (delta+b85 compressed heightfields, 36 chunks per foundation).

## VALIDATION MILESTONE (before expanding broadly)
FIVE genuinely distinct Mountain Valley layouts, differing in underlying STRUCTURE.
Verify: deterministic regeneration from identical seeds; different geography from
different seeds; objective connectivity; NPC navigation compatibility; deployment/
extraction placement; load/generation performance; approved terrain quality preserved.
Evidence: ground-level gameplay screenshots + aerial overviews per layout.
DO NOT generate hundreds of unverified maps first.
Preserve existing Teton battlefield as regression reference.
Coordinate mission/nav interfaces with alpha.

## Immediate next actions
1. Preprocess the top 5 diverse scan candidates into compressed heightfield modules (offline)
2. Build runtime reconstruction benchmark (play-mode WriteVoxels timing + memory)
3. Implement GeographicalGeneration layer (seed -> crop+orientation+deformation)
4. Validation captures per the milestone

## IN-FLIGHT STATE (end of thread, resume here)
- foundation_v2..v6 heightfields PREPROCESSED in gf-geo (foundation_vN_heightfield.npy),
  relief 1140-1468 studs each. Crops from scan_candidates.npy rows: v2=r1260c1680,
  v3=r1050c1680, v4=r210c1785, v5=r420c1785, v6=r840c1785 (verify against scan_candidates order).
- export_modules.py was run with --batch but output may have overwritten out_full/out_half
  repeatedly — VERIFY: re-export per-foundation into separate dirs (out_v2..out_v6) before deploy.
- NEXT: per-foundation export -> deploy data modules -> runtime reconstruction benchmark ->
  GeographicalGeneration layer -> 5-layout validation milestone captures.
