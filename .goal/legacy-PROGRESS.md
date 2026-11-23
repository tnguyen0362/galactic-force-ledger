# PROGRESS

Ledger: one line per verified item. Values are observed, not assumed. Verify command named before work.

## Phase 0 — foundation (verified)
| item | check | result |
|---|---|---|
| MCP tool surface answers | list_roblox_studios, execute_luau, screen_capture, save_place | OK, 1 Studio instance |
| Folder/config foundation | `[GF] boot: config check PASS` | 369 assertions PASS |
| Remote security (12 remotes, server intent validation) | boot + fire fuzzed args | OK |
| Profile defaults + memory fallback | console `[GF] profile ready ... credits=0` | OK |

## Phase 1 — combat playground (verified)
| item | check | result |
|---|---|---|
| Soldier rig + third-person camera | screen capture | OK (blocky GF kit) |
| Movement/sprint/dodge/jump | HUD dodge `2/2`, position deltas | OK |
| Weapon fire/reload/ammo HUD | HUD `28/28`, server-authoritative hits | OK |
| Shield 100 + health 100 regen | HUD bars | OK |
| 5 Ascendancy archetypes + state machines | EncounterDirector prints `4 hostiles, budget 8` | OK |
| Abilities: airstrike + dome, cooldowns | HUD `READY` panels, ability state remote | OK |
| Terrain + dressing | `[GF] terrain columns: 4096`, `world dressing parts: 88` | OK |

## Phase 2 — vertical slice (verified)
| item | check | result |
|---|---|---|
| Hub station + war table + deploy | capture: panel hides, HUD `true`, char at `(0,4.2,118)` | OK |
| Objective hold → complete | `workspace GF_ObjectiveComplete = true` | OK |
| Extraction call → 45s → dropship lands → board | `GF_ExtractionState = complete` | OK |
| Payout (Normal) | `GF_LastPayout = ROBLOXISUS101:450`, debrief `+450 Cr / +600 XP`, Rank 2 | OK |
| Return to station | `RequestReturn` remote + debrief close | pending re-verify |
| Route the mission payout from authoritative objective flag | `RewardsService.grantAll(success, difficulty, objective)` | OK (was 0 before fix) |
| ProfileService actually loads profiles at join | console `[GF] profile ready` | OK (was never called) |

## Bugs found and fixed (all verified by re-run)
- `Mission` required `InventoryService` (nonexistent) → whole mission died silently. Removed.
- `ProfileService.start()` never called; `init()` had no PlayerAdded hook → profiles always nil. Added load-on-join + retry + defaults fallback.
- `ensureRemote("RequestReturn")` passed an unknown class name to `Instance.new` → station crashed. Creates the RemoteEvent directly.
- Extraction payout read mission state after teardown → paid 0. Now captures difficulty/objective before teardown.
- Debrief and war table rendered on top of each other. Debrief hides the table, return restores it.
- Station lights overexposed the hall to white. Brightness 4→1.6, range 180→110.

## Lesson (cost real time)
`execute_luau` calls run in a **fresh Luau VM per call**. `require(SomeService)` inside a probe returns a
*separate module instance* from the live server's. Cross-call internal-state probes are therefore lies.
Verify through DataModel-observable state only: `workspace` attributes, prints, remotes, screen captures.

## 2026-11-22 — persistence unblocked (owner enabled Experience Settings > Security > API access)
- probe SetAsync/GetAsync -> `{"ok":true,"written":1795404054}`
- bug: `RewardsService.grant` awarded but never saved, never added salvage -> profile. Patch: markDirty + save + salvage accumulation, prints `profile persisted=`.
- live cycle 1 -> console `[GF] profile ready 1889759131 credits=450` (loaded previous award), `[GF] profile persisted=true`
- stored doc -> `credits=900 xp=1200 rank=2 schema=1` (450+450, proves read+write across sessions)
CHECK-PERSIST: PASS
- [verified] Lighting/perf pass: deployed-world audit — 511 parts, 426 shadow casters, 10 lights, 4 light masts, outpost 56 parts/42 pieces. Live FPS desktop 60 (p95 18.0ms/6s) — NOT Xbox One (no hardware). Patched 6 light sites `Shadows = false` (ObjectiveService:63, ExtractionService:65, StationService:100/133/138, OutpostService:97). Verify: all 4 modules loadstring OK; live play → lights=10, lightsWithShadows=0, masts=4, lampParts=4, boot `config check PASS (369 assertions)`, no GF errors. Saved v57.
- [note] Third-party noise, not GF: `cloud_12199271470.weapon system plugin` Line 109 errors `Game is not a valid member of ReplicatedStorage` at boot.
- [verified] Audio layer built from scratch (v61). `StarterPlayerScripts.GFAudio` (ModuleScript, 165 lines): 15 events + 3 loops, 14-voice round-robin pool, per-voice spatial anchors, zero uploaded assets (engine `rbxasset://sounds/*` re-pitched). `GFAudioRuntime` (LocalScript, 122 lines): ambient loop, footsteps, jump/land, hurt, death, mission start/end, UI clicks.
- [verified] Wired into gameplay: `Weapon` (rifle_fire on shot, hit_shield/hit_flesh on impact, reload_start/reload), `VFX.death` (enemy_death). All 4 modules loadstring OK.
- [fixed] Footsteps never fired: `Humanoid.MoveDirection` is always 0 under this game's movement system (measured: 212 frames, 0 moving, 19 studs travelled). Gait is now derived from `rootPart.AssemblyLinearVelocity` with a 3.0-stud stride. Verify: 5 steps / 17 studs, 6 steps / 20 studs (3.36 studs/step).
- [fixed] Duplicate `GFAudioVoices` folders when the module is instantiated twice (Studio tooling context vs game context) split the pool and hid voices from probes. Module now reuses an existing folder. Verify: 1 folder in SoundService.
- [verified] Live play, deployed mission: heard `Loop_ambient_wind`, `snap.wav` (footsteps), `action_get_up.mp3` (land), `electronicpingshort.wav` (mission confirm). Weapon path: 13 shots in 1.2s, `metal.ogg` + `impact_water.mp3` observed. 0 GF errors in log.
- [gap] Not observed live this session: UI-click cue, `enemy_death` (no real kill), `objective_done`/`mission_fail` transitions (no win/loss executed). Wired and syntax-clean only.
