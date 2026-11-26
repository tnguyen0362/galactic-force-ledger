# Battlefield P1 Integration — Validated Live (2026-11-26)

Commit: 20b406a. Owner directive: "go crazy" with Studio control after alpha handback.

## What was validated in the real Roblox VM (Playtest1)

| Check | Result |
|---|---|
| Module drop-in compile (12 modules) | 138/138 deploy, zero failures |
| In-VM generation smoke test | all archetypes generate; separations 153-253; splitmix deterministic |
| Flag OFF boot | identical legacy behavior: `terrain columns: 4096`, zero errors |
| Flag ON boot — highland_valley | gen 2.38s, attempts 3, write 3.96s |
| Flag ON boot — canyon_network | gen 1.21s, attempts 1, write 4.12s |
| Flag ON boot — broken_basin | gen 0.88s, attempts 1, write 3.91s |
| Flag ON boot — highland_valley (video run) | gen 0.61s, write 3.89s |

Total worst-case boot cost ~6.3s — inside the loading-screen window. Terrain write
is ~4s for 1500 studs (4.5x legacy area); acceptable, no batching changes needed.

## Architecture

- `GF_BattlefieldGen` workspace attribute gates the path (default OFF — absent means legacy).
- `TerrainService.build` with flag on: `BattlefieldService.plan(seed*7919+101, template, difficulty)`
  -> plan.sampler -> SectorBuilder.write at size 1500; legacy spine path untouched otherwise.
- `TerrainService.currentPlan` retains the plan for the P2 mission-layout wiring.
- Debug attrs published: `GF_BFSeed`, `GF_BFArchetype`. Template/difficulty overridable
  via `GF_BFTemplate`/`GF_BFDifficulty` attrs (dev use).

## Evidence artifacts

- `evidence/v684-ai-conformance-runtime-20261125/raw/battlefield_aerial_p1_video.mp4` —
  aerial capture of a live-generated highland_valley battlefield (936KB).
- `evidence/v685-fix-runtime-20261125/battlefield-renders/map_*.png` — offline top-down
  analytic renders per archetype with routes/installations/cover/zones.
- Harnesses: `gf_tools/run_bf_smoke.py`, `run_bf_flagtest.py`, `run_bf_video.py`,
  probe `battlefield_smoke_probe.lua`.

## Honest limitations (P1 state)

1. **Flag-on is a terrain-only demo.** Mission logic still uses hardcoded positions
   (~240-stud layout); objectives/extraction/props do not yet track the battlefield.
   Playable coherence arrives with the P2 mission-layout wiring.
2. Installations exist as data (positions/rotations/templates) but no physical
   structures are built at footprints yet.
3. Encounter zones are exported in the plan but not yet consumed by EncounterDirector.
4. Template passed to plan() is a fixed default — real mission-family mapping is P2 work.
5. Route lengths run 660-1135 studs vs the brief's 650-1000 preference — final tuning
   needs alpha's locomotion constants and real traversal timing.

## P2 backlog (ordered)

1. Mission-layout wiring: nodes.lz/primary/extraction replace hardcoded flats/objective
   positions; scale-aware objective placement; extraction logic from plan.
2. Physical installation structures at template footprints (server-built parts, budgeted).
3. EncounterDirector consumption of garrison/patrol/reinforcement zones.
4. Cover object placement from plan cover data.
5. Per-mission regeneration with archetype variety + seed rotation.
6. Canyon-floor route preference, route-length tuning with real movement constants.
