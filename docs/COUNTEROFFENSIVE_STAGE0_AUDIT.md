# COUNTEROFFENSIVE — Stage 0 Audit & Specification Reconciliation
**Author:** beta | **Date:** 2026-11-28 | **Authority:** Definitive Master Assignment (supersedes conflicting earlier specs)
**Method:** full-file reads of the strategic/matchmaking/mission services, structural grep of UI/combat layers, config audits, doc ledger cross-reference. Studio was NOT needed for this pass (all mirror-side). Items marked [DEEP] need file-level audit during their implementation stage.

---

## 1. Executive summary

The existing build is a **single-server, single-place prototype** with a verified core loop (deploy → objective → extract → reward). The master assignment requires architectural replacement of four pillars:

1. **The strategic layer is the prohibited architecture.** `GalacticWarService` is a scalar Helldivers-style liberation meter: per-territory `progress 0-100 = points/target`, one-dimensional sector score, no multidimensional state, no continuous enemy recovery, no population scaling. **Full replacement, not revision.**
2. **War persistence is per-server, not global.** Every server loads its own copy, mutates, and blind-`SetAsync`s the whole record — last-writer-wins across servers. Counteroffensive/defense schedulers run independently in **every** server (violates unique-authoritative-event requirement).
3. **Matchmaking is server-local.** Squads exist only in-memory per server; `quickDeploy` queue is per-server; MemoryStore global listings exist as a partial foundation but are not wired into a squad lifecycle; two different store names are used inconsistently (`GF_PublicSquads` vs `GF_SquadListings` — the seat-reservation path is broken/dead).
4. **The UI layer is prototype-grade.** Per-file ad-hoc color constants, no design tokens, no reusable component library, ScreenGuis scattered across 40+ client scripts, no full-screen menu architecture, no vertical sidebar. Replacement justified — but input layer, virtual cursor, and touch-control groundwork are solid and should be preserved/adapted.

**What is genuinely strong and must be preserved:** server-authoritative economy/armory/profile stack with schema migration infrastructure and optimistic-concurrency fencing; the objective dependency-DAG machinery in OperationService (`requiresAny`, topological validation, diamond-dependency handling); the 15-variant mission roster with distinct mechanics; the semantic input abstraction (`Input.luau`); deploy-flow logic in SquadService (15s warning, ready-acceleration, solo-immediate); difficulty/unlock-rank config structure; combat-validated enemy tracking (beta's own completed mandate).

---

## 2. System-by-system current state

### 2.1 Strategic layer — GalacticWarService (363 lines) — REPLACE
- **State:** `missionsWon/missionsLost` scalars + per-territory `{progress, points, target, state, battlefront}` — a one-dimensional liberation meter per territory. NO [E,L,H,I,S] multidimensionality.
- **Contribution:** `pointsFor = round(10 * difficultyWeight * familyWeight * (1 + .20*(P-1)))` — flat per-family weights, all five families weight 1.0 except Conquest 1.25. No mission-variant-level semantic mapping (a Sabotage relay strike and an Elimination boss kill contribute identically modulo family). Mandate §28 requires per-variant justified contribution vectors.
- **Territory keying:** missions are NOT territory-keyed — points land on a "rotating active front" (first contested battlefront). Mandate requires fixed geographical mission locations with per-region strategic effects.
- **Recovery/counteroffensive:** recovery exists ONLY as an all-captured edge case (reopen 1-2 fronts at 40-60%). No continuous recovery, no state-dependent hazard, defense-phase scheduler runs in every server independently.
- **Persistence:** single DataStore key `GF_War_v1/campaign`, whole-state `SetAsync` per server — cross-server clobbering guaranteed under multi-server load. No event idempotency beyond in-memory `processedMissions` (lost on server restart → duplicate-award window on restart mid-settlement).
- **Population scaling:** `phaseTarget(estimatedDaily)` exists as a formula but is never called with measured activity — fixed ColdStartTarget 200 for all territories forever.

### 2.2 Matchmaking — MatchmakingService (185) / SquadService (361) / DispatchService (456) — REBUILD AROUND EXISTING PIECES
- **Global listings:** MemoryStore SortedMap `GF_PublicSquads` with 90s TTL — correct platform primitive, partial implementation. `list()` supports difficulty filter + free-slots. **Not wired**: no heartbeat actually re-publishes (the heartbeat loop is a no-op stub), no join-flow integration.
- **Broken path:** `reserveSeat` uses `GF_SquadListings` — a *different* store than publish. Dead code.
- **SquadService:** server-local in-memory `members` keyed by Player. Leader election by join order exists (deterministic — good foundation). Deploy flow matches mandate §86 already (15s warning, ready-accelerate, solo-immediate). Settings (privacy/minRank/maxRank) exist. **No cross-server squad membership at all** — a squad is a single-server object.
- **Quick Deploy:** in-memory per-server queue table — cannot match across servers. No matching logic at all (queue never drains).
- **DispatchService:** host-initiated distress beacons (mid-mission reinforcement), server-local, with privacy filtering, expiry, catch-up pay. This is the closest existing piece to Emergency Dispatch but the mandate's ED is **player-initiated global reinforcement** — different direction of discovery, and must be cross-server.
- **Farm prevention:** diminishing-returns per missionId exists (1.0/0.6/0.3) — relevant to §49 adversarial design.

### 2.3 Teleportation — TeleportFlowService (74) — ASPIRATIONAL SHELL
- Multi-place architecture sketched but **unconfigured**: `GF_MissionPlaceId` attribute unset → permanent single-place fallback. Missions run in-instance in the same server as the lobby today. Reserved-server logic written but untestable until a second place exists. Mandate §88 requires the reserved-server flow for real — a second place must be created (owner permission escalation likely required — creator-dashboard operation).

### 2.4 Lobby — StationService (890) / StationWarTable (280) — REVISE
- Single central War Table exists (`WarTableBase` in station geometry) with squad display. Mandate §72 removes it as the deployment architecture → four physical terminals. [DEEP: geometry build code in StationService needs surgical extraction when terminals are built — coordinate with claude's art lane.]
- **Lobby capacity: no code-level cap found** — MaxPlayers is a place configuration in Studio/Roblox dashboard, not in the mirror. WORK_STATE says "Lobby 20-player architecture" was the design. Changing to 40 is a place-setting change plus performance work, not a code change. [Verify in first Studio window.]
- Player collision disabled already exists per spec (verify [DEEP]).

### 2.5 Mission structure — OperationService (1119) / ObjectiveService (1759) / OptionalService (235) — SURGICAL REVISION
- **The dependency-DAG machinery already exists**: `requiresAny` alternative prerequisite sets (OR of ANDs), topological validation with cycle detection, diamond-dependency correctness. This is exactly what mandate §63 requires — preserve and build on it.
- **15 variants present** but three are placeholder-named/mismatched vs the canonical roster: `SABOTAGE_RELAY` "Sabotage Relay" (canonical: **Sever the Signal**), `RECOVER_TECH` "Recover Technology" (canonical: **Alien Legacy**), `DEFEND_BEACON` "Defend Beacon" (canonical: **Hold the Line**). FIRST_SPEAR tutorial entry has a malformed table constructor (missing close — the `id` key is overwritten by `SABOTAGE_RELAY` inside the same table; FIRST_SPEAR effectively does not exist as written). [DEEP: verify whether variant rename is pure presentation or whether mechanics differ; canonical names must be restored per §61.]
- **OptionalService: 1-2 optional sites per mission** (relay/generator/supply) with real gameplay effects (reinforcement cut ×0.75, turret disable, supply grant) and reward-ledger events. Mandate §60 removes formal optional objectives; §67 requires case-by-case adjudication — the relay/generator effects are legitimate mission-relevant mechanics that may belong inside prerequisite DAGs for some variants, NOT deleted wholesale. The supply outpost is an environmental loot opportunity (§66 permits it informally).
- `optionalPois = 2` on every mission config — pervasive coupling to clean.
- **Economy coupling**: optional completion feeds `RewardLedgerService` as `optionalComplete` events — economy rebalance impact must be computed (mandate §68). [DEEP: quantify what fraction of expected income optional bonuses represent before removal.]

### 2.6 Support abilities — AbilityService (1199) / ArmoryService (932) / ProfileService (697) — MIGRATE
- **Two-slot architecture confirmed everywhere**: `equippedSlots[plr][1/2]`, profile schema `selectedLoadout.ability1/ability2` (defaults "Airstrike"/"DomeShield"), input actions `Ability1` (Q/LB) and `Ability2` (F/RB), cooldown attributes `GF_AbilityCooldown1/2`, mid-mission-join reset loop `for slot = 1, 2`.
- **Migration surface inventory** (mandate §156): profile schema + migration fn (exists — `migrate()` with schemaVersion, good infrastructure), saved loadouts ×3, ArmoryService equip paths, AbilityService activation, Input bindings, TouchControls, HUD indicators, deploy snapshot/loadout-lock logic, tutorial. All identified; migration is well-scoped.
- Roster matches mandate exactly: Airstrike, DomeShield, Sentry, OrbitalStrike, OrbitalLance, ReflectiveBarrier. No new abilities needed.
- Server validation of ownership exists (`legitimate source` check line 829).

### 2.7 Input/UI layer — PRESERVE CORE, REPLACE PRESENTATION
- `Input.luau`: semantic action layer with per-device bindings + glyph labels — exactly the right architecture. **Conflict flagged**: `SwapWeapon` is currently gamepad `ButtonY`; mandate §7 requires Y/Triangle for Emergency Dispatch in lobby context. Resolution: context-dependent binding (lobby-vs-mission), which the mandate explicitly scopes ("in the appropriate lobby context").
- `VirtualCursor.luau`: free-moving gamepad cursor exists — the approved model. Validate/adapt, don't rebuild.
- `TouchControls.luau`: dedicated mobile buttons exist (fire/reload/dodge/jump/interact ≥52px) but incomplete vs §120 (no ADS button, no weapon switch, single ability, no grenade) and the game has NO Roblox PlayerModule (custom movement) so everything must be self-built.
- Presentation layer: hardcoded per-file palettes (CYAN/AMBER/PANEL in StationUI), no tokens, no components. StationUI = war table + debrief combined in one file. Replace systematically per the design system (Stage 5).
- `Voss.luau`: commander portrait/subtitle presentation exists — foundation for §141.
- `MissionHUD.luau`: single objective line + progress — foundation for §140, needs DAG consumption.
- `TacticalMapUI`/`Minimap`: in-mission terrain map (M key) — NOT the planetary picker; the strategic planetary mission picker does not exist at all. Full new build (Stage 7).
- Debrief exists inside StationUI [DEEP: assess vs §179-183 single-screen report requirements].

### 2.8 Economy/progression — PRESERVE
- Server-authoritative profile with revision fencing, schema migration, DataStore round-trip verified. ArmoryService single-writer decision (D-21). Cache/augment/requisition systems verified per WORK_STATE. No rewrite justified — UI presentation layer only.

---

## 3. Incompatibility ledger (existing ↔ revised requirements)

| # | Severity | Incompatibility | Resolution path |
|---|---|---|---|
| I-01 | BLOCKING | GalacticWarService is a scalar liberation meter — explicitly prohibited (§4, §252) | Full replacement with multidimensional model (Stage 2/3) |
| I-02 | BLOCKING | War state per-server, cross-server clobbering; no global authority (§52) | Authoritative persistence redesign (Stage 3) |
| I-03 | BLOCKING | Counteroffensive/defense schedulers run per-server, duplicated global events (§34) | Lease/ownership mechanism (Stage 3) |
| I-04 | BLOCKING | Missions not territory-keyed; no fixed geographical locations (§5, §92) | Geography/mission-site binding (Stage 2 model + Stage 7 map) |
| I-05 | BLOCKING | Lobby capacity 20 (place config), not 40 (§71) | Place config + perf validation (Stage 4) |
| I-06 | BLOCKING | Single central War Table is the deploy architecture (§72 prohibited) | Four terminals (Stage 4) |
| I-07 | BLOCKING | Two support ability slots throughout schema/input/UI (§153) | Migration (Stage 1) |
| I-08 | BLOCKING | Formal optional objectives with gameplay effects and rewards (§60) | Adjudicated removal/promotion (Stage 1) |
| I-09 | HIGH | Matchmaking server-local; quickDeploy non-functional cross-server (§78) | Rebuild around MemoryStore (Stage 4) |
| I-10 | HIGH | No global squad browser UI (§81) | Stage 4 + Stage 7 |
| I-11 | HIGH | Emergency Dispatch as player-initiated global reinforcement absent; no Y/Triangle binding (§7, §83) | Stage 4/6 |
| I-12 | HIGH | Multi-place teleport unconfigured; missions run in lobby server (§88) | Requires second place — owner permission escalation |
| I-13 | HIGH | No multidimensional strategic state, contribution matrix, recovery, adaptive scaling (§15-50) | Stage 2 math-first program |
| I-14 | HIGH | No design tokens, component library, vertical sidebar, full-screen menus (§104-116) | Stage 5 design system |
| I-15 | HIGH | No planetary 2D tactical mission picker (§90-103) | Stage 7 (new build) |
| I-16 | MEDIUM | Mobile controls incomplete vs §120 (no ADS/switch/grenade/ability buttons) | Stage 6 |
| I-17 | MEDIUM | FIRST_SPEAR tutorial table malformed in Missions config | Fix during Stage 1 |
| I-18 | MEDIUM | Canonical variant names missing for 3 missions (Sever the Signal, Alien Legacy, Hold the Line) | [DEEP] audit mechanics, restore canonical roster (Stage 1) |
| I-19 | MEDIUM | Squad-size contribution multiplier (1+.20(P-1)) in legacy formula — mandate §31 forbids claiming it approved; requires documented decision | Stage 2 analysis |
| I-20 | MEDIUM | Contribution committed at primary-success not extraction — mandate §29 says inspect contract; existing semantics documented | Preserve, validate consistent with op success semantics |
| I-21 | MEDIUM | No hysteresis/classification machinery — binary Contested/Human flip at 100% (§41) | Stage 2 model design |
| I-22 | LOW | Legacy `reserveSeat` dead code with wrong store name | Remove during rebuild |
| I-23 | LOW | Campaign config family weights flat (no semantic differentiation) | Superseded by contribution matrix |

## 4. Explicitly preserved (do-not-rewrite list per §8)
- Objective DAG machinery (OperationService `requiresAny`/topological validation)
- Server-authoritative economy/armory/profile/migration stack
- Semantic input layer architecture (rebind, don't rebuild)
- Virtual cursor existence; touch-control groundwork
- Deploy-flow timing logic in SquadService
- 15-variant mission mechanics (canonical names restored)
- Difficulty config structure, unlock ranks
- Enemy combat/tracking systems (beta's validated mandate — untouched)

## 5. Migration risk register
- **R1:** Profile schema change (two abilities → one) touches live player data — migration must preserve ownership, deterministic (§156: first-valid-slot retention candidate rule; validate before adopting).
- **R2:** Optional-objective removal changes expected economy income — quantify before removal, coordinate rebalancing (alpha's economy models exist in gf-research/economy).
- **R3:** War-state replacement orphans existing campaign persistence — acceptable (pre-launch, no live players) but the migration note must be recorded.
- **R4:** Second-place creation is a creator-dashboard operation outside agent capability — escalate to owner when Stage 4 arrives.
- **R5:** FIRST_SPEAR malformed config may indicate the tutorial path is broken — verify before building on it.

## 6. Coordination notes
- alpha: combat-balance research; strategic state isolated from combat at launch (§22) — no coupling conflicts expected. Economy rebalance coordination needed at Stage 1 completion (§68).
- claude: art/rig lane; terminal geometry + lobby physical redesign must coordinate (§73, §10). UI consumes production assets for equipment previews.
- Studio windows: audit needed none. Baseline evidence captures need one Edit+Play window (~30min). Stage 1 verification needs play windows.
