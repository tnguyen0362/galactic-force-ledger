# MISSION INTEGRATION — COMPLETION MILESTONE (2026-11-27)

The mission-integration endgame is complete and live-validated. Planetary military operations
are multi-site, procedurally generated, dependency-gated missions on the real kilometer-scale
geography, with 15 operation variants across 5 families, procedural operational circumstances,
and a full lifecycle: deploy → objective DAG → extraction vote → boarding → settlement → return.

## Final validation: comprehensive regression 17/17 PASS (single cold-start session)

1. terrain_ready — hybrid terrain + geography analysis ready
2. operation_active — OP-42001 generated with correct DAG
3. player_deployed_at_operation_lz — 0-stud error
4. no_snapback_after_settle — stable at the op LZ
5. join_in_progress_no_regen — second deploy joins the SAME operation (no regeneration)
6. circumstance_published — seeded circumstance rolled and published
7. circumstance_lighting_consistent — lighting matches the rolled condition
8. comms_disable_interact — hold-interaction completes objective, reinforcement consequence fires
9. shield_destruction_unlocks_capture — destruction pipeline unlocks the dependent capture node
10. capture_completes_primary — hold-capture completes the primary objective
11. lethal_fall_downs_player — downed flow engages (health floors at 1, no death)
12. death_redeploy_lands_in_operation — automatic ticket redeploy lands 19 studs from op LZ
13. operation_survives_redeploy — same operation id persists through death/redeploy
14. extraction_called — console interact routes through the vote path
15. dropship_landed — transport arrives at the operation extraction pad
16. extraction_settlement_complete — boarding + Extract interact → squad departure → settlement
17. player_back_at_station — full loop closes at the orbital station

Prior validation milestones this program:
- Reference operation (CONQUEST_DOMINION): 10/10 live
- Extraction contract loop: 17/17 live (boarding holds, participant roster, hard deadline)
- Variant generation matrix: 15/15 templates live, plus 14/14 × 8 seeds offline (luau harness)
- Family mechanics: 7/7 live (defend auto-start, elimination death-watch, boss routing, multi-primary)
- Extraction hard-deadline self-heal: validated incidentally (force close as failed, return to station)

## Architecture (as built)

    OperationService — authoritative operation state
      generate(seed, template, difficulty) -> OperationDefinition (seed-reproducible, versioned)
        GeographyService.analysis — real terrain sites/valley floor
        OperationFamilies — 15 template DAG shapes on a shared spatial skeleton
        circumstance — seeded roll: standard / night_assault / storm / entrenched / alerted / fortified
      activate(def) — sites built by MissionSites, garrisons via EnemyService.spawn (ring composition,
        ground-probed), route patrol zones dormant until player proximity, extraction console
      interact — positional target matching, hold-to-complete (capture 4s, others 2.5s),
        cancelled by range/down/death/op-reset
      mechanics vocabulary: destroy (combat pipeline listener), capture/activate/disable/recover/restore
        (holds), eliminate (death-watch, boss-aware bespoke routing), defend (auto-start timer)

    StationService.deploy — op-mode gate for all 15 templates, join-in-progress
      (live operation for same template → join, else resetMission + generate), elevation-preserving
      spawn, op HUD publish for joiners

    ExtractionService — console interact → squad vote (solo immediate, majority, expiry,
      anti-grief throttle) → dropship → boarding HOLDS (proximity tracking; departure only via
      the Extract interact) → squad departure commit → settlement once at final close
      (war points, mastery, ledger, cache on success+objective) → return to station.
      Hard deadline 240s after landing enforced — force closes regardless.

    BoundaryService — 2500-stud terrain-extent rim, mission-participant scoped

## Root causes found and fixed this program

- **Deploy snapback**: BoundaryService legacy 900-stud mission-valley rim repositioned players
  deployed 1500-2500 studs out after exactly WARN_SECONDS=2.5s. NOT streaming (StreamingEnabled
  is false in this place), NOT respawn, NOT teleport logic. Fixed: 2500 radius + participant scoping.
- **Multiplayer operation wipe**: every deploy with a template regenerated the operation — a second
  squadmate deploying destroyed the first's in-progress mission. Fixed: join-in-progress.
- **Extraction initiation absent**: no legitimate path existed in shipped client code. Fixed:
  extraction console at the operation extraction pad, range-validated, vote-routed.
- **Extraction pressure leak / contract gaps**: boarding instant-extracted individuals, eligibility
  was not participant-scoped, hard deadline unenforced, joinedLate never reset. Reworked per audit.

## Validation engineering lessons (encoded in gf_tools/regression_final.py)

- execute_luau probes run in a SEPARATE plugin VM — module-table mutations via probe are void.
  Validate through game-VM paths only: client-fired remotes and real mechanics.
- Lethal fall (CFrame +210 studs + downward velocity) is the only reliable game-VM damage path
  for probes — setting Health=0 bypasses the downed flow (VitalsService lethal-damage interception).
- Extraction departure requires the Extract interact; proximity alone never departs.
- Anchor players through boarding tests — mountain extraction pads are steep.
- Studio play sessions die mid-probe unpredictably: compress validation into single cold-start scripts.

## Operation families (15 variants)

    SABOTAGE   RELAY / ARSENAL / AEGIS         RECOVERY  ARCHIVE / CONVOY (+RECOVER_TECH)
    DEFEND     BEACON                          DEFENSE   POWER / UPLINK
    ELIMINATE  COMMANDER / WALKER / TALON      CONQUEST  DOMINION / FOUNDRY / THRONEFALL

Rank gates: template-specific (CONQUEST_THRONEFALL requires rank 10); difficulty ranks unchanged.

## Known limitations / non-defects

- Multiplayer vote majority logic reviewed but not live-tested (single-client Studio); the starter
  must confirm their own vote via the banner (Y/N binds) — UX papercut, not a deadlock.
- Vote banner, boarding prompts, HUD DAG picture all render through pre-existing client surfaces.
- Enemy fire-slot ceiling (MAX_FIRING=2 global) is inherited tuning — noted for future balance,
  not changed (combat-feel ownership).
- Operation sites persist inert after mission end until the next deploy resets — atmospheric, inert.
