# ACCEPTANCE MATRIX — GALACTIC FORCE: COUNTEROFFENSIVE
Place: `Playtest1` (placeId 120646942844931, studio_id 586a4e54-321f-4609-aee4-e09dbc1e269c), saved version 26.
Verification ladder climbed: static (config check) → unit (formulas/tables) → integration (remotes, services)
→ live (played the loop through player-facing remotes, HUD read on capture).

| Area | Status | Evidence |
|---|---|---|
| Server boots, config valid | Implemented · Tested Studio | console `[GF] boot: config check PASS (369 assertions)` |
| 12 remotes, server-authoritative intents | Implemented · Tested Studio | `RemoteService.ensureRemotes()`, validation in Combat/Ability/Objective |
| Profile defaults + memory fallback | Implemented · Tested Studio | `[GF] profile ready 1889759131 credits=0` |
| Durable persistence | Implemented · **Tested Studio (live)** | `profile ready credits=450` (loaded prior award) + `profile persisted=true` + stored doc `credits=900 xp=1200 rank=2` |
| Hub station (deck, pillars, 3 ceiling lights, war table, panorama) | Implemented · Tested Studio | capture ScreenCapture_18 |
| War table → deploy | Implemented · Tested Studio | panel hides, HUD on, char `(0, 4, 118)` |
| Return to station | Implemented · Tested Studio | char `y=765, z=52`, table visible, HUD off |
| Repeat deployments (mission reset) | Implemented · Tested Studio | relay rebuilt (6 parts), `GF_ObjectiveComplete=false`, `GF_ExtractionState=idle` |
| Wasd/mouse movement, sprint, dodge 2 charges | Implemented · Tested Studio | HUD `DODGE 2/2` |
| Third-person camera | Implemented · Tested Studio | captures |
| Weapon fire/reload/ammo (AR-01, 28 rounds) | Implemented · Tested Studio | HUD `28/28`, server-side raycast validation |
| Shield 100 + health 100 with regen | Implemented · Tested Studio | HUD bars (e.g. shield 14 under fire) |
| Enemies: Rifleman, Scout, Marksman, Heavy, Officer | Implemented · Tested Studio | `[GF] mission online: 4 hostiles`, EncounterDirector budget |
| Objective: relay sabotage hold | Implemented · Tested Studio | `GF_ObjectiveComplete=true` via `InteractRequest("Relay")` |
| Extraction: call → 45s → dropship → board | Implemented · Tested Studio | `GF_ExtractionState=complete`, `BoardingZone` reached |
| Payout correctness (Normal) | Implemented · Tested Studio | `GF_LastPayout=ROBLOXISUS101:450`, debrief `+450 Cr / +600 XP`, Rank 2 |
| Debrief UI (single surface, salvage lines) | Implemented · Tested Studio | ScreenCapture_18 |
| Salvage tracking (scrap/energy/tech) | Implemented · Tested Studio | debrief `12 / 4 / 1` |
| Abilities: Airstrike, Dome, cooldown UI | Implemented · Tested Studio | HUD `AIRSTRIKE [Z] READY`, `DOME [X] READY` |
| Terrain generation (seeded, 4096 columns) | Implemented · Tested Studio | `[GF] terrain columns: 4096`, dressing `88` parts |
| Input: gamepad / touch layouts | Partial — bindings exist, not device-tested | no controller/touch hardware |
| Xbox One / mobile FPS | **Not verified** | see BLOCKED.md #2 |
| Opening cinematic (85–95 s) | Not started | — |
| OPERATION FIRST SPEAR tutorial | Not started | — |
| RECOVER_TECH / DEFEND_BEACON templates | Not started | — |
| Bastion Walker / High Marshal Veyr | Not started | — |
| Matchmaking, Priority Dispatch, reserved servers | Not started | needs published multi-place (BLOCKED #3) |
| Galactic War persistence | Not started | DataStore now works; war table is still local |
| Audio / Commander Voss voice | Not started | no asset path (BLOCKED #4); all text is subtitle-ready |

## Honest summary
What runs end-to-end today: open Studio → Play → stand in the orbital station → deploy → fight Ascendancy
troopers with a server-authoritative rifle, dodge, airstrike and dome → hold the relay terminal → call
extraction → defend/board the dropship → receive a correct Credits/XP/salvage debrief → return to the station
→ deploy again. That is one complete, repeatable operation, verified live, not a mockup.

What is not built: the cinematic, the tutorial, the other two mission templates, the two bosses, matchmaking/
dispatch, the persistent Galactic War, and all audio. Persistence is coded but blocked by Studio API access.
