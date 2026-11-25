# v716/v717 — replication hot-path cleanup addendum

## What changed

Two FPS-audit findings implemented (audit items 3 and 5):

1. **Server→client enemy animation migration (v716).** `EnemyAnimation.luau` previously wrote
   Motor6D `C0` values on the server every heartbeat for every rigged enemy — cosmetic joint motion
   replicated to every client continuously. The server heartbeat is now disabled; a new client
   local script `StarterPlayerScripts/EnemyAnimClient.luau` computes the identical procedural walk
   cycle locally from observed per-frame displacement. Server retains the module as reference only.

2. **Debug-attribute replication gates (v716/v717).** Per-shot `workspace:SetAttribute` writes are
   write-only verification telemetry but replicated to all clients in the hot path:
   - CombatService `note()` (Accepted/Hits/Rejected/LastReject per shot)
   - EnemyService `GF_EnemyHits`/`GF_EnemyMisses`/`GF_LastShotPos`/`GF_LastAttackAttempt` (v716)
   - EnemyService `GF_FireSlotsHeld`, `GF_SuppressionShots`, `GF_StructureShots`,
     `GF_SentryShotsTaken` + los/entry attempt writes (v717)
   All are now gated behind opt-in flags `GF_DebugCombat` / `GF_DebugEnemy` (set true on workspace
   to re-enable for verification harnesses).
   **Not gated:** `GF_AlertedCount` — EncounterDirector.luau:72 reads it for escalation; it is
   gameplay-functional, not telemetry.

## Runtime verification (run_enemyanim_verify.py, raw/enemyanim_v716.json)

Method: fresh play solo → deploy SABOTAGE_RELAY → pivot 5 live enemies in a ring 9 studs around the
living player facing them → sample every Motor6D joint angle on client twice 1.5s apart, same on
server → compare.

- Enemies aggroed: states `Idle → Advance` on all five.
- `client_anim_moving = true` — joints animating on client (Rifleman/Officer full leg+arm sets
  changing; two stationary-in-place enemies unchanged as expected when not displacing).
- `server_joints_static = true` — zero joint angle drift on server: migration successful, server no
  longer pays or replicates cosmetic animation.
- `optin_ok = true` — with `GF_DebugEnemy`/`GF_DebugCombat` set, `GF_LastAttackAttempt` etc. resume
  publishing (harness compatibility preserved).
- `gate_ok` v716 run: false — exposed remaining ungated los/entry writes; fixed in v717.

v717 re-run (same harness, second pass): `gate_ok = true` — zero debug attribute writes during live
combat with flags unset; `server_joints_static = true` again. In that run enemies reached Engage
range before the first sample so no locomotion occurred (stationary shooters correctly do not play
walk cycles — the client_anim_moving positive proof is the v716 pass where Advance displacement was
ongoing). `optin_ok` in the v716 pass confirmed telemetry resumes when flags are set.

## Harness fixes during verification

- Enemy perception: sight cone 110deg, proximity auto-detect radius only 14 studs — teleporting the
  player behind enemies at 24 studs correctly produced no aggro (perception working as specced).
  Harness now pivots enemies onto the player instead.
- MCP exec returns Lua arrays as numeric-keyed objects; harness normalizes.

## Notes

- Enemy rigs spawn with `AscendancyTrooper` child model, 15 Motor6D joints, `GFEnemyRig` attribute.
- Corpse/idle enemies resting-pose correctly on client (rest state when not displacing).
