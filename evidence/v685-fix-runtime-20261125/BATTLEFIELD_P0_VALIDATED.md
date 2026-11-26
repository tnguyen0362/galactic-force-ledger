# Battlefield Generation P0 — Offline Validation Evidence (2026-11-26)

## 150-seed acceptance batch (all 5 mission families cycling)

- **passRate 0.993 (149/150)**, 1.46s/seed generation
- **determinism**: same-seed regeneration bit-identical (fingerprinted)
- **archetype spread**: industrial 43, highland_valley 37, broken_basin 31,
  fortified_plateau 18, open_plains 13, canyon_network 7 — ALL SIX represented
- routeLen min/med/max: 642/823/1123 studs (target 650-1000 navigable)
- separation min/med/max: 66/113/264 studs between alternative routes
- reject tail (8 total attempts across 150 seeds): route_too_long 2, too_rugged 2,
  sigma 1, site_invalid 1, cover 1, diversity 1 — no dominant defect remains
- correlation_length rejections: 66 -> 0 after structural composer fixes
  (fixed the geography, not the seeds — per brief)

## Root causes found and fixed this iteration

1. SeedStream mix was linear-congruential: arithmetic-progression seeds produced
   linearly-correlated first draws, collapsing weighted archetype selection onto
   2-3 archetypes. Fixed with splitmix32 finalizer (pure Luau bit32, no Random.new).
2. fortified_plateau was one monolithic blob (corrLen 248-296 ABOVE band max 240):
   radius shrunk 0.22-0.30 -> 0.15-0.21 + apron mid-scale structure -> 184-232 in band.
3. open_plains had no macro structure (corrLen 72-88 BELOW band min 100):
   added 620-stud directional swells -> 104-120 in band.
4. industrial_wasteland borderline low: larger excavations + 380-scale rolling -> 104-152.
5. Retry loop masked failures: retries re-roll archetype, so failing archetypes were
   invisible in batch spread statistics. Diagnostics now replicate selection directly.

## Honest remaining gaps (next iterations)

- Within-archetype feature-vector similarity 0.979 pre-jitter; parameter jitter added
  but post-jitter diversity not yet re-measured (harness: test/diversity.lua).
- canyon_network underrepresented in spread (7/149) though selection weights are healthy —
  likely fails validation more often or retry-converts; investigate per-archetype fail rates.
- Validation is analytic-only (no Instances, no raycasts); runtime terrain+placement
  validation is P1 integration work per docs/BATTLEFIELD_P1_INTEGRATION_SPEC.md.
- Min route separation 66 studs is low for "meaningfully distinct approaches" — consider
  raising floor for primary objectives.

Harnesses: battlefield-prototype/full150.lua, corrlen.lua, diversity.lua (CLI-runnable offline).
