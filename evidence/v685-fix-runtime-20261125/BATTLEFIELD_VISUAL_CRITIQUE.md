# Battlefield Visual Critique — Top-Down Render Evidence (2026-11-26)

Method: offline pipeline dumps grid heights + node positions + routes + installation footprints
to stdout; python/PIL renders 900px shaded heightmaps with overlays. Renders in
battlefield-renders/. This is the brief-mandated honest critique loop — metrics alone missed
every defect below.

## Round 1 critique (pre-fix evidence)

Five systematic defects visible across archetypes:

1. **Fake route redundancy.** "Alternate" routes hugged the primary 40-80 studs away for most
   of their length — visually one corridor, exactly the "disguised linear level" the design
   brief forbids. Root cause: A* penalty radius 55 studs, validation floor 50.
2. **Primary objective ignored archetype geography.** In fortified_plateau the primary sat in
   generic highlands while the plateau itself — the defining feature — stood empty. Node
   placement was uniform random with slope checks only; composer hints were never consumed.
3. **Extraction random-corner placement.** 15-degree anti-colinearity let extraction sit nearly
   on the backtrack line or flung to map corners with no spatial logic.
4. **Single-quadrant mission footprint.** LZ and primary both random-direction, often same-side;
   60-70% of the battlefield saw no mission content at all.
5. **Voronoi-foam canyon uniformity.** canyon_network read as cracked-mud/turtle-shell foam —
   isotropic cells of uniform scale edge-to-edge. Real canyons are dendritic branching systems
   with hierarchy (Helldivers 2 Rocky Canyons reference).

Positive findings: highland_valley already produced genuine flanked-valley macro structure;
broken_basin's sunken-cell compartments created real tactical variety; industrial excavations
read as convincing crater districts.

## Round 1 fixes (validated in round 2 renders)

- Feature-anchored topology: primary now placed AT the archetype's dominant feature
  (plateau center, excavation-district centroid, valley axis midpoint); LZ placed 620-950
  away crossing the map. Anchorless archetypes must place primary on the opposing half
  (dot-product test), killing single-quadrant footprints.
- Route separation penalty radius 55 → 110; validation floor 50 → 80 mean interior separation.
- Extraction anti-colinearity 15 → 35 degrees.

## Round 2 verified improvements (post-fix renders)

- fortified_plateau: primary ON the plateau top; cyan route sweeps the western flank while
  yellow climbs the southern face — genuinely distinct assault approaches, 150-300 studs of
  separation through the middle. Extraction east of objective, off the backtrack line.
- highland_valley: routes span the map diagonal; cyan crosses valley floor + western rim,
  yellow runs the eastern ridge — ridge-vs-valley-floor is a real tactical choice.

## Round 2 remaining defects (open)

1. canyon_network geography still foam — dendritic spline-carved rewrite implemented after
   round 2 renders; validation pending (this document updates when rendered).
2. open_plains alternates still converge in flat terrain — terrain cost uniform, so paths
   parallel. Deeper fix: route alternatives should traverse different encounter/cover zones;
   penalty radius alone cannot create meaning in featureless terrain.
3. Installation scatter still lacks tactical logic in outlying regions — outposts jittered
   around midfield rather than watching routes/approaches.
4. Mission footprint compression when the anchor is centrally located (plateau): LZ-primary
   euclidean can compress toward the 620 floor.
