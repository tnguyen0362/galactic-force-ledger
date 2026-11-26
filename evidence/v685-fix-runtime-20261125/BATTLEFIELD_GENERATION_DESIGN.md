# Battlefield Generation Design — guided open battlefields, not disguised linear levels

Status: design + offline prototype. Owner: beta. Priority: user's #1 design item.
Authority: GOAL.md lines 262/341/354-374/704 + user direction (geographical archetypes battle plan).

## 1. Diagnosis of the current generator

Current pipeline (`SectorBuilder` + `TerrainService`):

```
h(x,z) = base + (broad+mid+fine noise)*ridge + crest^4*26, then:
  - spine corridor: flatten 62% within 55 studs of the spawn→objective LINE
  - corridorFactor: flatten further to BASE within 11 studs half-width / 30 falloff of same line
  - terrace quantization 4.5 studs
```

Measured/structural problems:

1. **One predetermined corridor.** Both flattening passes key off the SAME spawn→objective straight
   line. Every mission physically funnels the player down a graded valley; surrounding relief is
   decorative. This is a linear level wearing terrain as a costume — the exact failure mode the
   user called out.
2. **Seed variance is noise-deep only.** Reseeding changes the bumps, not the geography. There is
   no structural difference between one mission valley and the next — no archetypes, no macro
   geography, no tactical layout logic. "Geographically and tactically different" (GOAL.md:262)
   is not achievable with octave parameters alone.
3. **Node placement is incoherent with the terrain extent.** `generateGraph` scatters nodes in
   ±700 while the built terrain spans ±352 — half the graph is outside the world. Validation is a
   trivial node-collision simulation, not measured terrain.
4. **No quantitative validation.** Nothing measures slope distribution, sightlines, cover, or
   route redundancy; GOAL.md:704's 100-seed dry-run requirement is unmet in substance.

## 2. Design principles

P1. **Geography determines gameplay.** Archetypes are not palettes — they change which weapons,
    abilities and tactics are correct. A canyon network mission must play differently from open
    plains even with identical objective logic.
P2. **Guided openness.** The generator guarantees *viability* (reachable, traversable, readable)
    without prescribing *the* route. Guidance comes from geography (valleys invite, ridgelines
    expose, cover converges) not from flattening a corridor.
P3. **Everything measurable.** No seed ships on vibes. Every candidate battlefield is scored on
    quantitative metrics with rejection envelopes before voxel writes.
P4. **Deterministic.** Same seed → same battlefield, reproducible QA (GOAL.md:341/704).
P5. **Budget-conscious.** All generation math is analytic and evaluated per-voxel-column at write
    time; no physics simulation, no erosion iteration on the hot path. Validation samples a grid,
    not the full field.

## 3. Generation pipeline

```
STAGE 1  Archetype selection (seeded)
STAGE 2  Macro geography: tectonic-scale landforms for that archetype
STAGE 3  Tactical layout: LZ, objective(s), extraction, strongholds, patrol anchors, cover zones
STAGE 4  Terrain refinement: detail noise, domain warp, carving, terracing
STAGE 5  Environmental composition: rocks/flora/wrecks/structures per geography (existing dressing)
STAGE 6  Validation: metric suite + envelope rejection (offline seed loop)
```

### Stage 1 — Archetypes (data-driven, per GOAL.md:374)

Veyra-7 is "rocky highland/frontier with dry valleys, wind-sculpted cliffs, dusty rock flats".
Archetypes are subterrains of that one biome (2–3 palettes per spec), not new biomes:

| Archetype | Geography | Tactical texture |
|---|---|---|
| `highland_valley` | broad valley floor between parallel ridgelines, side re-entrants | long lanes along valley, flanking height, exposed crossings |
| `canyon_network` | branching carved channels in a plateau | concealment, close engagement, rim fire positions |
| `fortified_plateau` | objective on mesa/bench with terraced approaches | exposed final approach, defender advantage, long-range support |
| `open_plains` | low-relief flats with scattered cover clusters | sightlines dominate; abilities/vehicular cover matter |
| `broken_basin` | ring/adjacent ridges around interconnected clearings | ambush, compartmentalized fights, route choice per clearing |

(`industrial_ruins`/`forested_basin` are composition-layer variants — same heightfield archetypes
with different structure/flora dressing; they arrive with the outpost-kit work, not here.)

Selection: seeded per mission, weighted by mission template. DEFEND_BEACON biases plateau/basin;
SABOTAGE_RELAY biases valley/canyon; plains always rare-but-possible. Template never hard-determines
archetype — variability within recognizability (GOAL.md:341).

### Stage 2 — Macro geography

Per-archetype parametric landform functions composed additively over a shared low-frequency
continental base. Key math:

**Domain warping** (cheap, large organic payoff):
```
W(x) = (N1(x/s), N2(x/s))        low-frequency vector field, s≈300, amplitude α≈40-70
h(x) = N(x + α·W(x))             sample noise at warped coordinates
```
Applied to the continental base AND the archetype landform masks so ridgelines bend, valleys
curve, canyon paths meander instead of following lattice-aligned noise.

**Directional noise for ridges:** ridgelines use ridged noise `1-|N|` sampled in rotated,
anisotropically-scaled coordinates (compress along ridge axis ≈3-4:1) — elongated ranges instead of
isotropic bumps. Direction per-archetype with seeded ±20° jitter; warp breaks the straightness.

**Spatially variable roughness:**
```
r(x) = smooth low-frequency field in [0.15, 1]
h_detail(x) = r(x) · (mid+fine octaves)
```
Plains archetypes keep r low valley-wide; highland archetypes let r vary so smooth aprons abut
rugged crags — the "smooth plains alongside rugged mountains" effect at near-zero cost.

**Voronoi basin fields** (basin/canyon archetypes): seeded feature-point lattice, F2−F1 border
distance drives both basin rims (raised at borders) and canyon channel carving (deepened along
borders). Branching structure for free, deterministic per seed.

### Stage 3 — Tactical layout

Layout is constraint-solved BEFORE terrain commit, in analytic space:

1. **LZ, primary, extraction** placed by rejection sampling inside the archetype's valid-zone
   masks (valley floor / plateau top / basin clearing), with spacing constraints
   (primary 280-520 studs from LZ; extraction 150-400 from primary, never colinear within 15°).
2. **Stronghold/outpost footprints** placed on defensible terrain: locally elevated, cover-rich,
   with 2+ approach sectors. The objective is embedded IN geography, not scattered on noise.
3. **Route analysis instead of route carving.** Compute 2-4 candidate approach corridors as
   least-cost paths (cost = slope + exposure + water/void) over the analytic field. If geography
   already yields 2+ viable separated routes, KEEP THE TERRAIN AS IS — the routes are discovered,
   not manufactured. Only if redundancy fails do we apply minimal localized grading — and never
   flatten-to-base: corridor shaping caps at reducing slope along the path, preserving cover and
   micro-relief. The 62%-flatten spine is deleted.
4. **Patrol anchors + cover zones** exported for EncounterDirector/EnemyService and Stage-5
   dressing: ridge crests, channel junctions, clearing centers, cover-cluster seeds.

### Stage 4 — Refinement

- Terrace quantization retained (art direction) but amplitude-scaled per archetype; canyon walls
  keep hard terraces, plains soften.
- Fine detail noise re-applied AFTER any corridor grading so routes never read as ironed ribbons.
- LZ/objective/extraction footprints: small-radius flattening only (existing registerFlat,
  20-30 studs) — enough for structures, small enough to preserve local geography.

### Stage 6 — Validation metrics (the acceptance gate)

Computed on the analytic sampler over a 4-stud grid inside the play volume; no voxel writes needed
so the offline loop is fast (target <8s per seed in Studio).

| Metric | Method | Envelope (initial, tunab
