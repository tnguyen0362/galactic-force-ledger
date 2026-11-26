# Battlefield Reference Synthesis — Death Stranding, Risk of Rain 2, Helldivers 2

Status: design-reference analysis feeding the procedural battlefield generator.
Method note: direct image scraping from the games' wikis was blocked (JS-rendered/403); this
synthesis draws on published developer commentary (cited) plus detailed knowledge of the shipped
games. Treat as design-direction evidence, not pixel-level reference.

## 1. Helldivers 2 (primary structural reference)

Developer-confirmed architecture (Kevin Miles, principal level designer, kevmiles.net/helldivers):
- Levels are built from **"Stamps"** — pre-made pieces of level of varying size — **packed onto a
  Voronoi grid**. Zoning rules decide how the level is laid out and which stamps fill each zone.
- Map sizes, object counts and **player sightlines are explicitly tuned for performance**.
- The natural-landscape generator needed extra rules for man-made environments — installations
  are NOT random scatter; they follow zoning logic.

Material/terrain pipeline (Romain Lemaire, GDC/ArtStation):
- Biome variation comes from **feature generators**, not raw noise: a **dune generator**, a
  **crater generator** (also applied to "random war stamps"), rock sets distributed by RGB masks.
- Sandy archetype variants (Mineral/Acid/Spiky/Moon) reuse the same macro pipeline with different
  feature and material parameters — variation is parametric, not hand-authored per planet.

Community-documented biome archetypes (helldivers.wiki.gg): Sandy, Moor, Arctic, Primordial,
Swamp, Forest, Oasis, City — each planet = ONE biome; layout variation within a biome is large.

**Translations into our generator (status):**
- Stamps-on-Voronoi == our Templates + placement scoring + voronoi region analysis (P0 done).
- Feature generators == our Feature term in H(x,z): craters/excavations exist in industrial
  (P0); craters as general tactical bowls candidate for P2.
- Parametric biome variants: archetype parameter tables already structured this way.
- Sightline tuning as a first-class validation metric (already in Metrics suite).

## 2. Risk of Rain 2 (landmark + composition reference)

Developer commentary (GameDeveloper.com postmortem, GameDev.tv talk):
- They PROTOTYPED full procedural terrain and rejected it: "the level of difficulty needed to
  make interesting/memorable procedural maps in 3D was too much." Shipped **premade maps with
  per-run variations** (features toggled on/off) — direct validation of our authored-template
  hybrid over pure noise-driven procgen.
- "You first need to think about the gameplay... the environment has to be functional. Use the
  environment to guide the player — big shapes/small shapes and lighting."
- Each stage has **three or more variations** changing single features.

Terrain signatures of the shipped stages:
- **Titanic Plains**: rolling grassland + MASSIVE stone arches dominating the skyline; main
  playfield overlooks a vast fractured lowland. One or two dominant macro-landmarks visible from
  everywhere = constant player orientation without a minimap.
- **Distant Roost**: verticality — cliff islands, earth spires in fog; engagement rings at
  multiple heights.
- **Abandoned Aqueduct**: one dominant LINEAR megastructure organizing the entire map; tar pits
  and giant skeletons as secondary features.
- Cover comes from terrain undulation + scattered large rocks, not dense prop clutter.

**Translations:**
- Every battlefield should have 1-2 dominant orientation landmarks at macro scale (plateau,
  canyon spine, excavation district already do this per-archetype — P0 partially there).
- Elevation rings / high-ground loops around objective areas: validate that routes gain/lose
  elevation rather than staying flat (candidate P1 metric: route elevation profile variance).
- Variations-within-template == weighted internal template variation (already in Templates spec).

## 3. Death Stranding (terrain-as-gameplay reference)

Developer commentary (505 Games Reddit AMA with lead level designer Hiroaki Yoshiike et al.):
- Iceland was the visual/geological reference; environment artists did on-site photogrammetry
  scouting — rocks, cliffs and terrain assets come from real Icelandic geology.
- Even the audio system keys off **terrain shape** (wind sound parameters include the shape of
  the terrain) — terrain legibility permeates every system.

Terrain signatures:
- The terrain IS the gameplay: slope angle, surface roughness, water depth are all mechanically
  meaningful. Players read a valley and plan routes visually.
- Braided river valleys, mossy basalt moorland, scree slopes, isolated dramatic rock formations
  in open moor, distant mountain vistas layering the horizon.
- Slope steepness is LEGIBLE — you can judge traversability at a glance from terrain shape.

**Translations:**
- Slope legibility: our terrace quantization already gives readable strata; keep it (P0 done).
- Route planning as player skill: emerges from multiple validated routes + visibility of macro
  structure — supported by topology redundancy requirement (P0 done).
- Vista layering (distant mountains beyond playable bounds): P2+ cosmetic concern, noted, not
  in current perf budget.

## 4. Net effect on the generator backlog

Confirmed-correct existing decisions: archetype-first pipeline, stamps/templates, metrics-gated
rejection, per-stream determinism.

New/changed work items derived from this research:
1. (P1) Route elevation-profile variance metric — routes should cross elevation, not contour.
2. (P1) Dominant-landmark validation — every map must have 1-2 macro features visible from LZ.
3. (P2) Crater generator as a general feature type beyond industrial excavations.
4. (P2) Crater/mesa/outcrop feature stamps inside tactical positions.
5. (P2) Vista ring beyond playable bounds (cheap client-side presentation, deferred).
