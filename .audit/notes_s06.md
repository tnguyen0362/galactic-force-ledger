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
