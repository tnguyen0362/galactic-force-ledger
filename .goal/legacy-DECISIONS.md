# DECISIONS

- **Landscape + station share one place.** `OrbitalStation` and `PlanetaryMission` as separate Roblox places
  needs a publishing round-trip I cannot do (no publish authorization). Station sits at Y=760 above the mission
  terrain; deploy = teleport inside the place. Documented as a deviation, not a silent cheat.
- **Native Terrain, not voxel parts.** 16-stud columns, 4096 columns, deterministic height field; faceted
  silhouette comes from `WorldDressing` rock wedges. One Part per voxel was rejected on performance grounds.
- **Hitscan with server validation.** Client sends intent; server raycasts, validates range/cooldown/ammo.
  No client-supplied target or damage.
- **Verification through observable state.** See PROGRESS lesson: `execute_luau` = fresh VM per call, so all
  checks read `workspace` attributes / prints / captures instead of module internals.
- **Memory-mode persistence fallback.** DataStore is forbidden in this Studio session; ProfileService degrades
  to session-only with a visible warn rather than failing the join. Persistence criterion marked BLOCKED.
- **Blocky original kit instead of meshes.** No asset-generation tool for characters; armored humanoid kit built
  from parts, accessories stripped so silhouettes read clean. Marked as proxy art pending swap.

## D11 — No dynamic light shadows anywhere (v57)
All 6 PointLight/SpotLight sites set `Shadows = false`. Rationale: 10 shadow-casting point lights is the most expensive per-light setting on Xbox-One-class GPUs, while the night scene reads from fog + neon + the 4 amber masts; shadowed light adds little. Measured delta: deployed shadow-casting lights 10 → 0, parts unchanged 511. Falsifier: if night screenshots lose depth/readability, restore shadows on the 4 lamp masts only.

## D12 — ACP exploit config (L1, user-owned `~/.pi/acp.json`)
Root cause of "nudging at 15%": ACP computes nudge thresholds as percentages of `modelContextLimit`; unset, it assumed a window far smaller than the real one, so defaults (min 0.45 / max 0.75 / emergency 0.95 — verified `dist/index.js:4752-4772`) fired at a small fraction of the true context. Fix: `{"modelContextLimit": 1000000, "outputHeadroomMaxPct": 0.08}` — both keys are in ACP's KNOWN set (`dist/index.js:206`), path confirmed as `userConfigPath(homedir(),"acp.json")` (`dist/index.js:47`). Effect: first nudge at 450K tokens instead of ~15%. Takes effect on next Pi process start (config is read at boot), not in-session.

## D13 — Audio is re-pitched engine sounds, no uploaded assets (v61)
Roblox has no runtime PCM synthesis, so "synthesized placeholders" means re-pitching engine-bundled `rbxasset://sounds/*` assets (16 of 17 candidates verified loading with real durations). Rationale: ships audio with zero upload budget, zero Open Cloud permission, works offline; cost is a rough, borrowed timbre. Falsifier: if the palette reads as wrong-genre to a listener, replace individual events with uploaded SFX — the `EVENTS` table is the single swap point.

## D14 — Gait comes from velocity, not MoveDirection (v61)
Measured 212 consecutive client frames with the character travelling 19 studs and `Humanoid.MoveDirection.Magnitude` staying exactly 0, so intent-based footstep detection silently never fires in this game's movement setup. `GFAudioRuntime.step()` now integrates `rootPart.AssemblyLinearVelocity` horizontally and emits a step every 3.0 studs. Evidence: 5 steps/17 studs, 6 steps/20 studs. Any future movement-driven logic must use velocity or position delta, not MoveDirection.
