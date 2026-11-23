# REQUIREMENT COVERAGE — GALACTIC FORCE: COUNTEROFFENSIVE

Ledger: `REQUIREMENT_COVERAGE.csv` (155 rows). Audited **2026-11-22 23:14** against Studio `Playtest1`
(placeId 120646942844931, universe 10778576038, saved version 73).

No row is GREEN. `OWNER_ACCEPTED` requires the owner (V3-12).

## Totals

| Status | Rows |
|---|---:|
| ABSENT | 81 |
| PARTIAL | 71 |
| IMPLEMENTED_UNPROVEN | 1 |
| NOT_AUDITED | 2 |
| **total** | **155** |

## By group

| Group | Rows | ABSENT | PARTIAL | IMPLEMENTED_UNPROVEN |
|---|---:|---:|---:|---:|
| LC | 31 | 18 | 12 | 1 |
| EXT | 24 | 14 | 8 | 0 |
| MICRO | 100 | 49 | 51 | 0 |

## Launch inventory (LC-001..LC-031)

| ID | Requirement | Req | Have | Status | Basis (observed this session) |
|---|---|---:|---:|---|---|
| LC-001 | 3 unique playable: SABOTAGE_RELAY, RECOVER_BLACKBOX, DEFEND_BEAC | 3 | 1 | PARTIAL | Only SABOTAGE_RELAY is selectable; deploy options expose one template |
| LC-002 | Rifleman, Scout, Marksman, Heavy, Officer each spawning and figh | 5 | 1 | PARTIAL | 4 hostiles spawned, all EnemyId=Rifleman; Marksman/Heavy/Officer never spawn |
| LC-003 | Bastion Walker gameplay encounter | 1 | 0 | ABSENT | No Bastion Walker code or spawn |
| LC-004 | High Marshal Veyr phases and rewards | 1 | 0 | ABSENT | No High Marshal Veyr code or operation |
| LC-005 | AR-01, SG-04, MR-07, LMG-12, ER-16 playable and equippable | 5 | 1 | PARTIAL | AR-01 fired live; SG-04/MR-07/LMG-12/ER-16 exist only as config rows, never equipped |
| LC-006 | P-01 Service Pistol playable | 1 | 0 | IMPLEMENTED_UNPROVEN | P-01 in config and loadout defaults; never equipped or fired |
| LC-007 | Frag and EMP distinct and playable | 2 | 0 | ABSENT | No grenade implementation |
| LC-008 | Airstrike, Dome Shield, Sentry, Orbital Precision Strike | 4 | 2 | PARTIAL | Airstrike and Dome verified with cooldowns; Sentry and Orbital absent |
| LC-009 | Assault, Heavy, Recon, Support with functioning personal/squad p | 4 | 0 | ABSENT | Classes config exists; no service applies class passives |
| LC-010 | Ten distinct functional augments in V2-10 catalog | 10 | 0 | ABSENT | Augments config exists; no slot, no modifier, no UI |
| LC-011 | Scrap, Energy Cells, Military Technology distinct persistent ite | 3 | 0 | PARTIAL | Salvage counters exist and are awarded on extraction; no world pickups observed |
| LC-012 | Rank, Credits, XP, purchase, mastery, research, save persistence | 1 | 1 | PARTIAL | Credits/XP/rank persist; no purchase, no mastery, no research |
| LC-013 | Easy, Normal, Hard, Extreme real and reward scaled | 4 | 2 | PARTIAL | Easy/Normal selectable; Hard/Extreme not exposed and no scaling content |
| LC-014 | Navigable station with real panoramic windows, planet, ship traf | 1 | 0 | ABSENT | Station is a flat blue floor + black void; no windows, planet, traffic; crew unanimated |
| LC-015 | Functional equip/purchase/augment/loadout UI | 1 | 0 | ABSENT | No armory UI at all |
| LC-016 | Physical table and real mission selection, planetary status | 1 | 0 | PARTIAL | War Table is a text panel; one operation; no planetary state |
| LC-017 | Terrain-aware map, objective/POI markers, squad live position | 1 | 0 | ABSENT | No tactical map |
| LC-018 | Real distress broadcast and responder join | 1 | 0 | ABSENT | No Priority Dispatch |
| LC-019 | Actual public compatible mid-mission join | 1 | 0 | ABSENT | No matchmaking or mid-mission join |
| LC-020 | 1,2,3,4 players actual missions and return including reconnect | 4 | 1 | PARTIAL | Solo only; no multi-client session |
| LC-021 | 85–95 sec animated with voice/subtitles skip/replay | 1 | 0 | ABSENT | No cinematic code |
| LC-022 | Complete Operation First Spear playable end-to-end | 1 | 0 | ABSENT | No tutorial code |
| LC-023 | Gunship/vote/boarding/success/wipe/time expiry/salvage rules | 1 | 0 | PARTIAL | Dropship + boarding + complete state exist; no vote, no failure branch, no departure |
| LC-024 | Live HUD; labels; settings; feedback across controls | 1 | 0 | PARTIAL | 28 HUD labels + 12 buttons across 4 screens; no icons, map or settings |
| LC-025 | Station, armory, tutorial, missions, extraction without KBM | 1 | 0 | ABSENT | No gamepad-only path; no touch UI verified |
| LC-026 | Full focus/action parity | 1 | 0 | ABSENT | No controller focus system |
| LC-027 | Full gameplay/menu parity and smooth mouse aim | 1 | 0 | ABSENT | No gamepad parity |
| LC-028 | Full gameplay/menu parity with device safe areas | 1 | 0 | ABSENT | No touch parity or safe-area layout |
| LC-029 | Character/outpost/weapons/terrain/FX/ship/station coherent non-p | 1 | 0 | ABSENT | Blue part-stack characters, cylinder relay, flat pads; blockout only |
| LC-030 | Server-authoritative rewards/data, verified rejoin; live Galacti | 1 | 0 | PARTIAL | Server-authoritative combat verified; no matchmaking, no shared war state |
| LC-031 | Real device/performance, security, release gates and user accept | 1 | 0 | ABSENT | No device/hardware performance evidence |

## Reading

- **0 of 31** launch obligations complete. Two have real function behind them
  (Airstrike/Dome with cooldowns; the solo deploy-to-payout loop). The rest are absent
  or a single stand-in instance.
- Station, armory, tactical map, Priority Dispatch, matchmaking, cinematic, tutorial and the
  shared Galactic War have **no code**: keyword hits for each were 0 across
  `ReplicatedStorage` and `ServerScriptService`.
- The station spawn frame shows a blue floor and a black void with cyan strips; the mission
  frame shows blue/green terrain, blue boulder meshes and a cylinder-stack relay; every
  character is a default-avatar part stack. See `VISUAL_REVIEW.md`.

