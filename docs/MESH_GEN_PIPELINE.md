# AI Mesh Generation Pipeline — discovered 2026-11-25

## The pipeline EXISTS and works via Roblox_Studio MCP
- `generate_mesh` (textPrompt, size{x,y,z}, maxTriangles<=20000, segmentation, async, studio_id)
  — Roblox AI text-to-3D textured mesh generation. Async returns jobId; poll with `wait_job_finished`.
- Also available: `generate_scene`, `generate_texture`, `generate_material`,
  `generate_procedural_model`, `insert_asset`/`search_asset` (Creator Store).
- Works while a playtest is running (job accepted in Play mode, verify insertion target datamodel).

## FIRST TEST JOB (in flight at thread end)
- jobId: `f2b80fe4-c2d1-459a-a63d-6abdcd802f40`
- prompt: "tall alien conifer tree, tapered dark trunk, layered sweeping angular canopy branches,
  deep teal-green foliage with subtle bioluminescent hints, sci-fi alien highland forest,
  game-ready stylized realism"
- size 16x28x16, maxTriangles 4000, segmentation none
- studio_id: 0d5d4409-fdc9-49ad-ad7d-512c7af56ae2 (place Playtest1)

## NEXT STEPS for vegetation pipeline
1. wait_job_finished on the jobId; inspect the generated mesh quality/tris/texture
2. If good: generate 3-4 species (canopy conifer, mid alien broadleaf, low scrub, wasteland dead-tree)
   at ~2-4k tris each; store as mesh assets in ReplicatedStorage or ServerStorage
3. VegetationService swap: replace part-built trees with mesh clones (scale variance per instance);
   keep the ecology logic (forest regions/treeline/slope rejection) — it is asset-agnostic
4. Two-theme discipline per user: FOREST theme (dense canopy regions) + WASTELAND theme
   (rock formations, wrecks, sparse harsh scrub) — no thin universal scatter
5. LOD/perf: meshes at 2-4k tris x ~1000+ instances — watch memory; consider StreamingEnabled
   friendly parentage and MeshPart LOD where needed

## USER DIRECTION (2026-11-25)
- "stick to the two themes of the forest and the wasteland"
- part-built low-poly trees are a waste of time — quality assets or nothing
- black wall ROOT-CAUSED + FIXED (OrbitVista starfield inside playfield) — commit 96356c5

## CRITICAL: mesh ID schemes and persistence/replication (learned 2026-11-26, confirmed 2026-11-28)

- `rbxruntime://` mesh IDs are what the raw `GenerateModelAsync` harness path produces. They are
  SESSION-LOCAL: dead after the session ends — they do not replicate to clients and do not persist.
  Errors look like: `MeshContentProvider failed to process rbxruntime://... because 'could not fetch'`.
- `rbxassetid://` mesh IDs (generated through the official Assistant mesh-creation flow, or uploaded)
  are durable and replication-safe.
- RULE: old rbxruntime meshes stay dead forever — REGENERATE through the correct path, do not try
  to convert or repair them.
- The boot-log MeshContentProvider errors in Playtest1 are legacy debris from early generation
  experiments, not an ongoing pipeline failure. Cleanup happens naturally in the planned graphic
  overhaul; until then they are harmless noise (invisible meshes).
- Any new mesh production (Stage 8 loot/cache/container assets, overhaul art) must use the
  replication-safe path so meshes receive real asset IDs.
- OPEN ISSUE (neither alpha nor beta resolved): some edit-mode content (a probe model) once failed
  to survive into the playtest snapshot while other edit-mode models did. Pre-replication, not
  mesh-related. Watch for it when verifying generated assets in play mode.
