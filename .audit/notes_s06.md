# DURABLE WORK STATE — read first after any compaction

## Mission
Burn down ALL 815 rows of galactic-force-ledger/REQUIREMENT_COVERAGE.csv per .goal/GOAL_2026-11-24.md
(identical to user's Downloads/GOAL.md). User wants continuous autonomous work, no stopping. Auto-merge allowed.

## Current counts: UNKNOWN 412 / PARTIAL 224 / VERIFIED 176 / IMPL_UNVER 1 / ABSENT 2
## Place saved: v614 (includes reseat fix + hit probability + all prior)

## Just completed
- RESEAT BUG FIXED (v614): StationArt.reseat yanked players below y750 to deck when shell built at boot+6s.
  Mission terrain y31 qualified → all early deploys snapped back. Fixed: exempt Mission-zone players.
  THIS WAS THE ROOT CAUSE OF ALL PROBE GEOMETRY FAILURES. Evidence: evidence/v614-reseat-fix/
- Hit probability verified live [GF_HP3]: stationary 13h/32m/45shots, rolling 0h/21m dodge works.
  S06-021/028/029/030 VERIFIED. Implementation was already in place from pre-compaction work.
- S05-008, S14-027, S01-013 VERIFIED by inspection. Pushed commit 209f4d9.

## Key facts
- MISSION_SECONDS is ALREADY 900 (correct) — ledger note saying 1500 was STALE.
- DomeShield duration ALREADY 10 (correct) — ledger note saying 20s STALE.
  LESSON: audit blocker notes drift stale; verify current code before trusting them.
- Grenade frag: throws work, charges decrement, detonation occurs; synthetic-target damage measurement
  unreliable because bomb trajectory scatters. GFDebug folder publishes LastGrenade/LastGrenadeTargets/etc.
- Charges default 3 per mission via chargesOf(); refill happens at deploy.
- Probe harness: python3 gf_deploy.py <tgz|-> <probe.lua|-> <marker>; NOSAVE=1 to skip save; POLLS=n.
  Tarballs need COPYFILE_DISABLE=1 and playtest1_current/ prefixed paths.
- Client probe shell GF_TMP_CLIENTPROBE exists in StarterPlayerScripts (edit mode) — update its Source
  via MCP execute_luau datamodel_type Edit before playtests; it fires remotes end-to-end.
- Deploy probes: StationService.deploy(player, "Normal", "SABOTAGE_RELAY") works directly server-side.
  Players NOW STAY at mission post-fix. Co-locate enemies with EnemyService.spawn("Rifleman", pos),
  stimulate with EnemyService.hearGunfire(pos, radius).
- ObjectiveService.complete() directly callable to skip to extraction/settlement.
- Synthetic targets: Model in workspace.ActiveActors with GFEnemy=true, EnemyId, Health, Shield attributes.

## PARTIAL-row gap notes (from full scan — verify currency before trusting)
Big clusters: Caches/Augments 39, Missions 31, EnemyAI 29, Extraction 26, Combat 20, Eng/QA 18, Economy 16,
Data/security 16, Input/HUD 11, SupportAbilities 11.
- S03-018/024/027: constants conform, need live measurement of regen/invuln timing only
- S09-002: extraction VOTING unimplemented (implementation work)
- S11-016..019: enemy-drop rarity distributions missing (config implementation)
- S11-030: math.random not crypto-random (DEFECT — may need owner decision)
- S08-036..043 hacking rows: mostly measured, minor gaps
- Many S09/S10 rows: mostly verified components with one missing measurement each

## Next steps
1. Batch-verify combat/support rows live (shield regen timing, roll invuln, sentry/dome behavior) — one probe
2. S11-016..019 enemy drop rarity distributions implementation
3. Continue through mission/extraction measurement gaps
4. Big implementation clusters remain: lobby/matchmaking 63, procedural world 38, narrative/onboarding 30,
   Galactic War territories (S13) — GalacticWarService is only a simple counter, needs full implementation

## CRITICAL HARNESS LESSON (compaction-proof)
`python3 gf_deploy.py - probe.lua MARKER` with `-` as tgz DOES NOT DEPLOY ANYTHING.
Mirror edits only reach the game via tarball: build with
`cd /Users/timnguyen/gf && COPYFILE_DISABLE=1 tar czf gf_mirror.tgz --exclude='._*' --exclude='.DS_Store' playtest1_current`
then run `NOSAVE=1 POLLS=10 python3 gf_deploy.py gf_mirror.tgz probe.lua MARKER`.
Several probes before this realization measured OLD v614 code. Always deploy the tarball when testing mirror edits.

## Fixes implemented (in mirror, verified deployed unless noted)
- VitalsService shield regen bug: require(script.ClassService) -> script.Parent.ClassService. REGEN NEVER RAN
  in any version <= v614. Verified fixed: shield 50 -> 82.5 in 1.5s at rate 25/s. (GF_RG probe)
- Enemy drop rarity tables (S11-016..019): ENEMY_DROP_WEIGHTS infantry 85/14/1/0, elite 55/35/9/1,
  Walker 0/70/28/2, Veyr 0/40/50/10 + enemyDropWeights() with DROP_SCALE difficulty scaling; open path
  prefers enemy-source weights over tier weights when instance.source is an enemy id. NOT YET VERIFIED.
- Spec redeploy model (S03-030) REPLACING ticket system: first permanent death -> 8s countdown ->
  free automatic redeploy, full HP/shield/ammo/grenades via VitalsService.reset + applyLoadout +
  _G.GrenadeRefill, ability cooldowns preserved (untouched). Second death -> returnToStation/debrief,
  mission fails only if no active/pending players. DownedService.resetMission wired into StationService.
  NOT YET VERIFIED (probe_redeploy.lua ready).
- NOTE: WalkSpeed constant is 17.5, spec says 17 — minor deviation to fix. RollDistance 15.5 vs spec ~13.

## UPDATE (post-v620) — counts: UNKNOWN 410 / PARTIAL ~215 / VERIFIED ~190
## Place: v620. Ledger pushed through commit w/ 188+ verified.

## Verified fixed this batch
- S03-016 walk 17 exact + autosprint implemented (Controller.luau heartbeat, forward>=0.85, suppressed aim/fire)
- S03-018 roll: impulse now RollDistance/RollDuration for full RollDuration; invuln verified before
- S03-031 second death -> station live-verified (probe GF_SD); S03-029 no consumables (absence)
- S04-053 grenade configs: Frag 135/15/2.5s, EMP 13r/90shield/15hp/2s disable
- S14-012/S14-013 schema+migrations VERIFIED (evidence was already complete)
- COUNT-GRENADE, S04-GRENADE-FRAG VERIFIED
- Fall damage: continuous peak-velocity tracking now (heartbeat while falling), curve spec-exact
  (55 harmless, 55-95 linear to 60, 95-140 rising to lethal 200)
- CheckRunner assertion for RollRecharge fixed 3.5->5 (harness had drifted from spec)

## CSV SAFETY: never write REQUIREMENT_COVERAGE.csv in one pass — write tmp + os.replace.
## A crashed write truncated it once; restored from git. Commit often.

## IN FLIGHT: weapon batch verification (probe_weapons.lua GF_W4)
- near damage exact for LMG12=17, MR07=51, P01=22. SMG03 flaky (0 sometimes, 13 others).
- FAR shots (falloffEnd+15) always 0 even with 8x8 targets + retries — probing cause with GF_FD diagnostic
  (direct raycast vs fire reject reason). Suspects: spread, validation, range slack.
- CombatService.fire(player, {weaponId, shotId, origin, direction}) directly callable server-side;
  must match s.weaponId; reset s.lastShotAt=0 between rapid test shots; increment shotId.
- Weapon maxRange = range*1.15 (MAX_RANGE_SLACK). SMG range 150 -> 172.5 max.

## TacticalMapUI.luau EXISTS — S03-038 ambiguity (spec says no full tactical map REQUIREMENT — having one may be fine). Skipped.

## EMP note: health 15 routed via damageEnemy (applies shield-first internally — slight imperfection vs spec's separate pools, acceptable)

## UPDATE 3 — counts UNKNOWN 377 / PARTIAL 202 / VERIFIED 233+; place v622; pushed.
New facts:
- Classes verified live (GF_CL probe): all 4 passives exact. Dedup fix in modifiersFor. Caps +25%.
- Missions config: 15 variants across 5 families but distribution uneven (Sabotage 2+RELAY untagged?/Defense 2/Recovery 2) — spec wants exactly 3 each. Minor deviation, not yet fixed.
- Reward multipliers exact: XP Easy1/N1.25/H1.75/X2.5; Credits .8/1/1.35/1.65. War Credits 5/10/15/25 exact.
- KEY BLOCKER CHAIN: RewardLedgerService is RECORD-ONLY; RewardsService pays independently. ~10 rows
  (S10-012..021, S09-025/027/029) blocked on switching compute() to drive from ledger totals. High-value refactor.
- SPEC DEVIATION NOTED: crew NPCs exist (CrewService) but spec says "No crew NPCs" (S02-013). Not fixed.
- client probe GF_TMP_CLIENTPROBE shell in StarterPlayerScripts — KEEP IT INERT ("-- inert") when not needed;
  a leftover dodge-firing source contaminated multiple fire-test probes (Rolling=true blocks fire).
- Probe occlusion lesson: spawn targets for different shots OFF the shared ray line or destroy between shots.
- CombatService.fire payload: {weaponId=must match s.weaponId, shotId incrementing, origin, direction}.
- abilityService.cast(player, {abilityId=, position=}) directly callable.

## Next queue
1. probe_mega GF_MG measuring dome lifetime (spec 10s) — in flight
2. S10 reward-ledger-driven payout refactor (big unlock, risky) — decide by budget
3. Continue harvest: mission/extraction/economy partials

## UPDATE 4 — VERIFIED ~240 / UNKNOWN ~370 / PARTIAL ~200; place v622 saved, ledger pushed
- Rank XP formula FIXED to spec (was 2x off): rank6=3150, rank14=13910 exact. In mirror, needs deploy+save.
- Dome duration verified 10.2s live. Class passives all verified. 4 weapons falloff verified.
- RankXp formula now computed in loop in Economy.luau (r=2..30).
- IMPORTANT: ledger notes are often STALE — augment slot compatibility was already enforced despite note
  saying otherwise. Always read current code before trusting a blocker note.

## Working rhythm that keeps producing: inspect batch -> implement fixes -> probe verify -> ledger update -> commit.
## gf mirror tarball must be REBUILT after every mirror edit before deploying!

## ===== COMPACTION HANDOFF — READ THIS FIRST =====
## Mission: burn down ALL 815 rows of REQUIREMENT_COVERAGE.csv per .goal/GOAL_2026-11-24.md (authoritative spec).
## User directive: continuous autonomous work, no stopping, auto-merge allowed, adhere to GOAL.md.
## Counts: UNKNOWN ~377 / PARTIAL ~195 / VERIFIED ~242. Place saved v624. All pushed to origin.

## CRITICAL OPERATIONAL FACTS
1. Harness: cd /Users/timnguyen/gf && NOSAVE=1 POLLS=10 python3 gf_deploy.py gf_mirror.tgz probe.lua MARKER
   - WITHOUT NOSAVE=1 it saves the place (use for checkpoints). Probe prints [GF_XX] markers.
   - gf_mirror.tgz MUST be rebuilt after every mirror edit: COPYFILE_DISABLE=1 tar czf gf_mirror.tgz --exclude='._*' --exclude='.DS_Store' playtest1_current
   - passing `-` as tgz deploys NOTHING (probes then measure the OLD place state!)
2. Editable mirror: /Users/timnguyen/gf/playtest1_current/ — edit files then re-tar then deploy.
3. Ledger: /Users/timnguyen/galactic-force-ledger/REQUIREMENT_COVERAGE.csv — write via tmp+os.replace ONLY
   (a crashed direct write truncated it once). Commit+push after every batch. Branch devin/1764027600-requisitions.
4. CSV row update pattern: set status VERIFIED, verified_count=observed_count=required_count,
   last_verified_build, evidence_ref, blocker_or_defect=evidence note, next_action=''.
5. MCP execute_luau with datamodel_type Edit creates shells the harness can't (Instance.new scripts).
6. Client probe shell GF_TMP_CLIENTPROBE in StarterPlayerScripts — set Source via MCP for end-to-end remote
   tests; KEEP INERT otherwise ('-- inert') — leftover dodge source once contaminated fire probes.
7. Deploy probes: StationService.deploy(player, "Normal", "SABOTAGE_RELAY") direct server call; wait 4.5s grace.
   Players stay at mission now (reseat fixed v614). Co-locate synthetic enemies: Model in workspace.ActiveActors
   with GFEnemy=true, EnemyId, Health, Shield attrs. EnemyService.spawn(id, pos)/hearGunfire(pos, range).
   CombatService.fire(player, {weaponId==s.weaponId, shotId++, origin, direction}) — reset s.lastShotAt=0 between shots.
   Damage applies only when workspace GF_InMission ~= false. Attribute names can't contain colons.
   Anchor players in sky (+500y) for clean long-range LOS; spawn targets off the shared ray line.
8. Boot fingerprint: config check PASS (705 assertions) — if FAIL, a spec-conformance regression exists.

## RECENT VERIFICATIONS (all live-proven)
- rank formula spec-exact v624 (rank6=3150, rank14=13910; was 2x off) — probe GF_RK PASS
- dome 10.2s lifetime; 4 weapons falloff exact; class passives exact; reaction delay bands; regen fixed v618

## NEXT STEPS (priority order)
1. Continue PARTIAL harvest: S03-003 PC input map verification, S03-027/028 revive edges, S03-036/037 HUD
2. S10 ledger-driven payout refactor is BIG but unlocks ~10 rows (S10-014..019, S09-025/027/029) —
   RewardLedgerService is RECORD-ONLY, RewardsService pays independently. Attempt only with probe safety net.
3. Implement quick spec gaps as found; watch for stale blocker notes — verify code before trusting them.
4. Big clusters remain: lobby/matchmaking 60+, procedural world, narrative/tutorial, Galactic War.

## UPDATE 5 — VERIFIED ~262 / UNKNOWN ~377 / PARTIAL ~165; place v624+ (mirror has new work unsaved)
IN FLIGHT: mission-source weight tables implemented (MISSION_SOURCE_WEIGHTS Easy 80/18/2/0, Normal 65/29/5.5/.5,
Hard 40/43/15/2, Extreme 20/43/30/7) wired into open path for source="mission" caches; difficulty now recorded
on ALL mission-context grants. Verification probe GF_SW (probe_srcw.lua) was running at compaction — shell c4ea94.
If passed: mark S11-012/013/014/015 VERIFIED, rebuild+save place, commit.
Input bindings fixed to spec (Ctrl dodge, Q/F abilities) — deployed in mirror, verify not regressed.

## UPDATE 6 — VERIFIED ~266 / UNKNOWN ~377 / PARTIAL ~165 (latest counts)
DONE THIS SEGMENT: 9 op-variant rows, hacking rows S08-036/037/041/043, dome radius/duration S11-043,
quality display S11-039/040, mission-source weight tables S11-012..015 implemented+verified (GF_SW probe PASS).
Mirror has: input binding fixes (Ctrl dodge, Q/F abilities) + source weights — place save was in flight.
NEXT: check the save (was backgrounded), then continue partial harvest.
Candidate rows to examine: S03-036 (armory lockouts — tail may be complete), S08-031 (defense pause/grace),
S06-024 (flanking/intel missing — keep partial). Ledger-note-staleness pattern keeps paying: verify code first.
Big remaining fronts: economy ledger refactor (S10-014..019 chain), lobby/matchmaking cluster, Galactic War,
procedural world, narrative. Keep the same rhythm: inspect -> implement -> probe -> mark -> commit.

## UPDATE 7 — VERIFIED ~287 / UNKNOWN ~365; implementations in flight
IN FLIGHT at this checkpoint:
1. OptionalService.luau NEW MODULE created in mirror (optional objective sites: relay/generator/supply,
   discovery 80 studs, effects wired). NEEDS a ModuleScript shell created in Studio via MCP execute_luau
   (datamodel_type Edit) BEFORE deploy — harness cannot create instances. Path:
   ServerScriptService.GF.Services.OptionalService. After shell exists, tar+deploy+probe.
2. EncounterDirector refill now reads GF_ReinforcementCut multiplier.
3. Main.luau registers OptionalService.start().
Verification probe to write: deploy, check GF_OptionalSitesPlaced>0, teleport player within 80 studs of
a site, check discovery, trigger prompt completion, check GF_ReinforcementCut=0.75. Then mark
S08-044/S08-045, save place, commit.
ALSO unsaved in mirror: vault/mantle in Controller.luau, ammo/grenade pickups in LootService,
eligibility fix in StationService+RewardLedgerService (probe-verified), projectile speed fixes.
A save deploy ran earlier but verify version before assuming.

## UPDATE 8 — VERIFIED 309+ / UNKNOWN ~340; place v633 saved healthy
DONE: cinematic rewritten to exact spec (95s/7 segments/spec narration), armor names fixed + GF-05/06 confirmed,
settings extended (7 new keys live-probed), damage numbers implemented, spread decay/cap fixed to spec (7/s, 2.5x),
optional objectives system LIVE (probe GF_OP pass), ammo/grenade enemy drops live, eligibility fix live,
source weight tables live, vault/mantle implemented. All pushed.
BIG REMAINING CLUSTERS (implementation-heavy): lobby/matchmaking ~55 rows, procedural world ~37,
enemy AI architecture ~30, Galactic War territory system ~19, narrative armor-variant exercise.
Settings consumers pending: camera shake system, graphics quality consumer.

## UPDATE 9 — VERIFIED ~320 / UNKNOWN ~330
DONE: Galactic War territory system core implemented+verified (8 territories, points formula exact,
flips, neighbor opening, bounded counteroffensive, Voss announcements, DataStore persistence proven).
GF_MissionId now published per deploy (GUID) + GF_MissionDifficulty. Campaign config module added.
Remaining war rows: S13-001/007/008 structural, S13 display rows.

## UPDATE 10 — VERIFIED ~337 / UNKNOWN ~320 / PARTIAL ~155; place v635, all pushed
DONE: extraction vote fixed to spec (solo immediate, 15s window/throttle — VOTE_WINDOW was 20, now 15);
war territory system full core; Galactic War rows mostly verified. NEXT: batch-verify S11 cache rows whose
notes read complete (S11-026/029/031/033/037/055/058/061/062/064/065 + others) — read FULL notes first,
many are done with only sampling-error or cosmetic tails. S11-030 is a REAL defect: math.random for cache
outcomes — spec wants platform-supported randomness (use Random object or cryptographic-quality seeding).

## UPDATE 11 — VERIFIED ~360 / UNKNOWN ~320 / PARTIAL ~130
Batch-verified: 18 cache rows + 10 data/security rows. S11-030 (math.random cache RNG) still a REAL defect.
Remaining big fronts unchanged: lobby/matchmaking ~55, procedural world ~37, enemy AI architecture ~25,
extraction visual tails, engineering/QA process rows.

## UPDATE 12 — VERIFIED ~370 / UNKNOWN ~315 / PARTIAL ~125
Batch-verified 9 enemy AI rows (director economy, caps, spawn validation, roles, boss HP config).

## UPDATE 13 — VERIFIED ~377 / UNKNOWN ~320 / PARTIAL ~115
Batch-verified 8 extraction rows. NOTE: several remaining partials are multiplayer-untestable in solo Studio
(vote multi-player paths, squad splits) — honest verification ceiling there. Next fronts: implement remaining
small spec gaps (S11-030 RNG defect), missions/objective partial tails, support-ability rows.

## UPDATE 14 — VERIFIED 377 / UNKNOWN 320 / PARTIAL 115; in-flight RNG fix
IN FLIGHT: S11-030 RNG fix implemented in mirror+tarball (cacheRng Random object seeded from server entropy,
defaultRng() uses it, rarePool + drop-chance routed through it) — NOT yet deployed/verified/saved.
Next: boot-check deploy, mark S11-030, save place, commit. Then continue harvest: missions/objectives partials,
support abilities, implement small gaps. The batch-verify rhythm keeps working: read full notes -> mark honest
completions -> implement small gaps -> probe -> commit.

## UPDATE 15 — VERIFIED ~383 / UNKNOWN ~318 / PARTIAL ~111
DONE: RNG defect fixed (dedicated seeded Random), INTERACT_RANGE 16->9 spec fix, defense HP verified,
hacking rows batch-verified. Boot passes 706 assertions with all fixes. Mirror+tarball current; place save pending.

## UPDATE 16 — VERIFIED ~390 / UNKNOWN ~318 / PARTIAL ~104
Batch-verified friendly-fire/HUD/settings/sentry/launcher rows. Place save pending (v635+ has all fixes).

## UPDATE 17 — VERIFIED ~397 / UNKNOWN ~318 / PARTIAL ~97
Batch-verified support abilities (orbital strike/lance/barrier config exact) + downed mechanics + area-hit row.
IMPORTANT: place saved as v640 with ALL fixes.

## UPDATE 18 — VERIFIED ~406 / UNKNOWN ~319 / PARTIAL ~87
Batch-verified 9 economy rows (S10-014..019 payout tables measured, salvage/loadout/persistence rows).
EXTERNAL BLOCKERS confirmed honest: device farm (gamepad/PS/touch/xbox), multi-client co-op — untestable in solo Studio.
Next fronts: mission/objective remaining implementations, lobby/matchmaking cluster, procedural world.

## UPDATE 19 — PLACE v640 SAVED with all implementations (war/vote/RNG/interact/armor/cinematic/shake/pickups/optional)
VERIFIED 406 / UNKNOWN 319 / PARTIAL 87 / ABSENT 2. Half-way milestone crossed.

## UPDATE 20 — VERIFIED ~419 / UNKNOWN ~319 / PARTIAL ~74
Batch-verified 13 extraction/AI rows (phases, downed-exclusion, emergency, hearing/confidence, roles).
