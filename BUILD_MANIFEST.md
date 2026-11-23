# BUILD MANIFEST

| field | value |
|---|---|
| Project | GALACTIC FORCE: COUNTEROFFENSIVE |
| Place | `Playtest1` |
| placeId | 120646942844931 |
| universeId | 10778576038 |
| Studio instance | `586a4e54-321f-4609-aee4-e09dbc1e269c` |
| Saved version | **73** (TeamCreate) |
| Source control | none in this project (repo root is `C:/`; git deliberately unused) |
| Tool surface | Roblox Studio MCP (`execute_luau`, `screen_capture`, `start_stop_play`, `save_place`, `search_asset`, `user_keyboard_input`, `user_mouse_input`) |
| Spec | `.goal/GOAL.md` = the full V3 contract, 304,412 bytes / 1,476 lines, byte-identical to the owner's `Downloads/GOAL.md` |
| Ledger | `REQUIREMENT_COVERAGE.csv` (155 rows) + `REQUIREMENT_COVERAGE.md` |
| Audit session | `evidence/v73-audit-20261123/` |

## Runtime shape (observed this session)

| item | observed |
|---|---|
| Services | 25 (`ServerScriptService.GF.Services`) |
| Client scripts | 12 (`StarterPlayerScripts`) |
| Configs | Missions 3, Weapons 6, Enemies 7, Abilities 6, Augments 10, Classes 4, Difficulties 4 |
| Station | 94 parts above Y700, 15 meshes, 2 window-frame parts, 5 non-player humanoids |
| Mission world | 551 parts / 325 meshparts, terrain 4096 columns |
| Hostiles per mission | 4, all `EnemyId = Rifleman` |
| UI | 4 runtime screens, 28 TextLabels, 12 buttons total |
| Code keyword hits | cinematic 0, tutorial 0, tacticalmap 0, dispatch 0, matchmaking 0, war 0 |

## Build state

`PLAYABLE INCOMPLETE` — the deploy → fight → sabotage → extract → debrief loop runs, but 81 of 155
ledger rows are ABSENT and 71 are PARTIAL. No row is owner-accepted. No public publish, no
monetisation, no external assets purchased.
