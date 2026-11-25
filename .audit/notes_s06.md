# S06 enemy AI — gap analysis and implementation plan (2026-11-25)

## Discovery: architecture largely absent

EnemyService.luau (809 lines) implements basic behavior-driven enemies:
- behavior tags in config: GuardCover/FlankBeacon/ChargedShot/AreaBurst/CommandSquad/WalkerPhases/CommanderPhases
- cover usage exists; single central heartbeat (good); enemies use cover in live tests (observed spine1)
- NO hierarchical FSM states (Dormant/Patrol/Investigate/Acquire/Engage/Search/Return) — only "Guard" string found
- NO confidence model exp(-age/4), NO lastSeen tracking, NO radio knowledge sharing
- NO spatial grid, NO token-bucket pathfinding, NO threat-cost reinforcement economy
- NO hitProb config (S06-028 spec values absent), NO threatCost table (S06-039 absent)
- EncounterDirector.luau is only 238 lines — minimal spawn control

Enemies config (78 lines): solid per-archetype hp/shield/damage/speed/sight/burst but no hitProb/threatCost.

## Spec targets (from rows S06-003..044)

FSM states, central staggered scheduler (no per-NPC heartbeat — currently central single heartbeat: partial credit),
LOS raycasts bounded (2 max per check), sight 110 studs/110 deg cone, near-proximity 14, hearing 90,
confidence exp(-age/4), radio within 100 studs same group delay .5s, target scoring formula,
downed-not-targeted, cover node reservation TTL, pathfinding token bucket 8/s, stuck recovery 2s/6s,
hit probabilities rifleman .42 Vanguard .38 etc, suppressive-fire intentional misses, elite frequency 0/10/20/30%,
active cap round(4+2*(P-1)) scaled, Normal solo 3-5 active, threat costs, reinforcement token formula,
off-screen spawn validation 65-140 studs.

## Implementation plan (sub-batches)

S06-A perception/FSM core: implement state machine (Dormant/Patrol/Investigate/Acquire/Engage/Search/Return),
  LOS cone+distance checks, hearing on gunfire events, lastSeen+confidence, target scoring, downed exclusion.
  Verify: probe observes state transitions via attributes when player exposes/hides.
S06-B reinforcement economy: threat costs config, active caps by player count, token refill formula,
  off-screen spawn validation. Verify: probe counts actives over a mission, spawn positions outside LOS.
S06-C attack patterns: hitProb config per archetype, suppressive-fire zones, telegraph avoidance windows.
  Verify: statistical probe on synthetic engagements.
S06-D stuck recovery + cover reservation TTL + radio sharing.

Each sub-batch: implement -> deploy -> probe -> ledger update -> commit. Estimate multiple sessions.

## Row triage note
Config-checkable rows can be verified as implementation lands. Do NOT mark behavioral rows verified
without live probes. S06-012 (footstep sound not needed) is a negative-requirement: verifiable by absence.

## IN-FLIGHT at compaction (update after reading)

S06-A perception/FSM: DONE, place saved v596, committed. Probe PASS hidden=Guardx9 alerts=9 afterFire=Investigate.

S06-B reinforcement economy: IMPLEMENTED, verification in progress. Changes in EncounterDirector:
- DIFFICULTY_PRESSURE table, THREAT_COST (Rifleman1 Scout1 Marksman1.5 Heavy2.5 Officer2 bosses6)
- activeCap() = round(4+2*(P-1)) * pressure; refill tokens 0.12*P^0.7*pressure*phase*(0.5+A/100)/s burst cap 8
- alert +6/gunfire decay 2/s (was 4, tuned); phase scalar .6/1/1.4/1.5; GF_ExtractionCalled attribute
- isSpawnPointValid: 65-140 studs + outside LOS of all players
- spawnAround consumes tokens by threat cost; refill ticker publishes GF_EconomyTokens/Alert/Cap
- hearGunfire in EnemyService also calls EncounterDirector.noteGunfire
FIXED forward-ref bug: refillTokens must use EnemyService.count() not activeCount (local defined later).
Probe status: tokens=5.5 cap=4 publishing correct; spawn validation rejects correct; visible80=false correct.
Final rerun was testing alert measurement race fix (probe now samples immediately). Shell 2ed4ac.
NOT YET SAVED TO PLACE - deploy is NOSAVE. After PASS: save_place, evidence, ledger rows S06-036/038/039/040/041/042/044, commit.

CRITICAL NEXT: after S06-B completes, pivot to mission/extraction verification sweep (cheaper rows) then continue remaining clusters per severity.

## IN-FLIGHT at compaction (combat math fix)

Combat probe measured: headshot ratio exactly 2.00 PASS, shield absorbs RAW 18 not boosted PASS, TTK derivation 2.70s in band PASS.
BUG FOUND+FIXED: hitMultiplier was reset to 1 whenever augs existed, killing headshot bonus on shield overflow (measured 6 vs spec 12).
Fix in CombatService.damageEnemy: removed fold, added weakFactor applied to health portion only. NOT YET SAVED.
Probe rerun in progress (shell 24e143) expecting afterHead2 health=488. After PASS: save_place, evidence, update rows S04-014/S04-018/S04-046, commit.
