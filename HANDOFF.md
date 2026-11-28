# GALACTIC FORCE — session handoff (updated 2026-11-28)

Read this first, then `WORK_STATE.md`, `DECISIONS.md`, `.goal/GOAL.md`.

## What this project is NOW

A Roblox Helldivers-like built across TWO live Studio places on one universe (universeId 10778576038):

- **Playtest1** (placeId 120646942844931) — the station/lobby: armory, war table, drop pods, squad recruiting, lobby UI.
- **Missions** (placeId 13785118418) — the battlefield: objectives, enemy AI, extraction, biome looks, bosses.

The game code lives in the places, NOT in git. This repo (`C:\Users\tnguy\galactic-force`) is the ledger
plus a Luau mirror at `game-mirror/playtest1_current/` (shared GF codebase — both places draw from the
same module tree). **The owner publishes; agents never save or publish places.** Unsaved work accumulates
in the Edit DataModels — check the bus before assuming what state a place is in.

## Multi-agent coordination — READ THIS BEFORE TOUCHING ANYTHING

Multiple Devin instances work this project in parallel (delta, pi, claude-art, deepseek).
Coordination is mandatory and lives in `C:\Users\tnguy\devin-comms\`:

- `messages.log` — append-only bus. Post claims, releases, findings, integration notes. Read the tail
  before starting any work.
- `claims.md` — resource claims (blender, roblox-studio-control per place). NEVER use Blender or a
  Studio place without holding the claim. Release with a note when done. Do not clobber another agent's
  active claim; if blocked, post to the bus and work something else.
- Use the devin-comms skill scripts if present; otherwise append directly.

## The harness (Windows machine, current)

- **Studio MCP**: `list_roblox_studios` first for studio ids. `execute_luau` (Edit rejected during play —
  use Client/Server), `start_stop_play`, `get_console_output`, `screen_capture`, `search_game_tree`,
  `inspect_instance`, `insert_asset` (Edit mode only). Do NOT `save_place` — owner publishes.
- **Asset uploads**: `open_cloud_invoke` POST `/assets/v1/assets` (multipart, field `fileContent`),
  then poll `GET /assets/v1/operations/{id}` until done. Files must be inside owner-approved upload
  directories — currently `gf-art-build\out_dropship` is approved; staging anything there works.
  Creator userId 1889759131.
- **Blender MCP**: live Blender 5.x session. `execute_blender_code`, `look` (renders views — USE IT,
  pixel-level inspection is the owner's quality bar). CRITICAL LESSONS:
  - The session file `dropship_interior_wip.blend` is dirty/unsaved — NEVER save it.
  - Viewport `look` renders show foreign collections even when hide_render=True — set
    `coll.hide_viewport` for clean inspection, and check the scene root for orphan objects.
  - Never negative-scale mirror (flips verts to wrong side). Bake rotations into mesh vertices, never
    object-level rotation for placed parts. Blender 5.x removed legacy action API (slotted actions).
- **Art pipeline**: parametric Python generators in `gf-art-build/blender/` are the source of truth
  (build_cargoship.py, build_bastion.py) — rerunnable, no .blend snapshots needed. GLBs export to
  `gf-art-build\out_*`, staged copies go to `out_dropship` for upload.
- Art templates install as `ServerStorage.GF.Art.<name>` in the Missions Edit DM: strip `_mesh.NNN`
  suffixes, remove PackageLink, anchor parts, visual-verify with a Workspace test copy then delete it.

## Verification culture (owner-enforced)

Pixel-level visual inspection, honest critique, no overclaiming. The owner catches defects agents miss
("wtf r u deadass") — look at renders meticulously before declaring anything done. Numeric verification
(bbox measurements, bone-parenting counts) beats assuming. Owner is frequently on MOBILE — mobile
input/scaling is a first-class concern, and remember: players on the published build never see Edit-DM
work until the owner publishes.

## State snapshot (2026-11-28)

- **GF_CargoShip**: assetId 133889290183506, INSTALLED in Missions Edit DM `ServerStorage.GF.Art`
  (unsaved). 82m span heavy lifter, spin-contract props (local Z axis), 7,450 tris. No flight system yet.
- **GF_Boss_Bastion**: assetId 137515304103831, uploaded+approved, NOT yet installed. Rigged mini-boss:
  15 bones (waist/pod.L/pod.R/turret.R/gatspin.R + legs). `BastionWalker.luau` visual-swap integration
  written in mirror with zero-regression fallback — UNTESTED, needs template install + movement wiring
  + deploy + verification. Full integration analysis in messages.log [10:35Z 2026-11-28].
- **Unsaved Edit-DM work awaiting owner publish**: Playtest1 (lobby pods/hangar/UI/mobile fixes),
  Missions (cargo ship install, orange-haze biome pass, SiteDressing, GFGodMode dev panel, enemy AI
  tactics pass by claude-art in flight).
- **Mobile**: dead-button fix shipped (MouseButton1Click→Activated) + compaction. BIGGEST GAP: reload/
  dodge/abilities have NO touch bindings at all. Camera touch sensitivity untuned.
- **Enemy AI**: claude-art owns formation-movement pass (crouch/cover/fire-and-maneuver) in Missions.

## Owner directives standing

Pixel-level inspection, meticulous case studies before building (reference images sacred), autonomous
continuation without reprompting, escalate only genuine permission/payment/destructive blockers.
Owner plays on mobile. Owner quality bar is absolute — "there is no context budget".
